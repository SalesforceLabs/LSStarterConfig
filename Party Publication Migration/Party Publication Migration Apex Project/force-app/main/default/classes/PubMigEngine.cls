/**
 * Processes one chunk of PartyPublication rows (design §3.1, §6.3).
 *
 *   SOQL  1  tracker.eligible                     current state of still-eligible rows
 *   SOQL  2  source rows                          standard fields only
 *   SOQL  3  tracker.existingPublicationByGroupKey Publications created by earlier runs/chunks
 *   SOQL  4  inactive owners                      only when the chunk creates Publications
 *   SOQL  5  existing Publications                for PAPER_FIELD_CONFLICT
 *   SOQL  6  existing Contributors                reuse (PublicationId, ContributorId, Role)
 *   DML   1  insert Publications                  allOrNone=false
 *   DML   2  insert Contributors                  allOrNone=false
 *   DML   3  tracker.record                       migration fields only
 *   DML 4-5  compensation deletes                 only records created in THIS transaction
 *
 * No SOQL or DML inside loops. Never deletes or edits customer data; never updates an existing
 * Publication or Contributor (I6).
 */
public without sharing class PubMigEngine {

    // Error codes (design §5)
    public static final String MISSING_PUBLICATION_DATE = 'MISSING_PUBLICATION_DATE';
    public static final String PUBLICATION_CREATE_FAILED = 'PUBLICATION_CREATE_FAILED';
    public static final String CONTRIBUTOR_CREATE_FAILED = 'CONTRIBUTOR_CREATE_FAILED';
    public static final String CUSTOM_FIELD_WRITE_FAILED = 'CUSTOM_FIELD_WRITE_FAILED';
    // Warning codes
    public static final String PAPER_FIELD_CONFLICT = 'PAPER_FIELD_CONFLICT';
    public static final String OWNER_INACTIVE_REASSIGNED = 'OWNER_INACTIVE_REASSIGNED';

    @TestVisible
    private static final String MSG_MISSING_DATE =
        'Publication Date is required. Each PartyPublication record must have its own Publication Date; ' +
        'the migration doesn\'t copy it from other records of the same publication. ' +
        'Populate Publication Date, then rerun the migration.';

    public class ChunkResult {
        public List<PubMigOutcome> outcomes = new List<PubMigOutcome>();
        public Map<Id, String> notRecorded = new Map<Id, String>();
        public List<String> compensationFailures = new List<String>();
        public Integer publicationsCreated = 0;
        public Integer contributorsCreated = 0;
        public Integer contributorsReused = 0;
        public Integer publicationsCompensated = 0;
        public Integer contributorsCompensated = 0;
    }

    private final PubMigTracker tracker;
    private final PubMigInsertHook hook; // null in production runs

    public PubMigEngine(PubMigTracker tracker) {
        this(tracker, null);
    }

    public PubMigEngine(PubMigTracker tracker, PubMigInsertHook hook) {
        this.tracker = tracker;
        this.hook = hook;
    }

    public ChunkResult run(Set<Id> scopeIds) {
        ChunkResult res = new ChunkResult();

        // ------------------------------------------------ re-check eligibility at execute time (§6.1)
        Map<Id, PubMigOutcome> previous = tracker.eligible(scopeIds);
        if (previous.isEmpty()) {
            return res;
        }
        Set<Id> eligibleIds = previous.keySet();
        List<PartyPublication> rows = [
            SELECT Id, PartyId, Title, PublishedOn, Summary, PublicationDate, PublicationIdentifier, Url,
                   CitationCount, ImpactFactor, ListingPlatformType, Status, PublicationCategory, PartyRoleType,
                   OwnerId, CreatedDate
            FROM PartyPublication
            WHERE Id IN :eligibleIds
            ORDER BY CreatedDate, Id
        ];

        // ------------------------------------------------ [1] validate, [2] group key, map (no DML)
        Map<Id, PubMigOutcome> outcomeById = new Map<Id, PubMigOutcome>();
        Map<Id, Publication> candidateBySource = new Map<Id, Publication>();
        List<PartyPublication> valid = new List<PartyPublication>();
        for (PartyPublication row : rows) {
            PubMigOutcome o = new PubMigOutcome(row.Id);
            o.previous = previous.get(row.Id);
            outcomeById.put(row.Id, o);
            res.outcomes.add(o);

            o.groupKey = PubMigRules.groupKey(row); // recomputed every attempt (§3.2); null if no identifier and no date
            if (row.PublicationDate == null) {
                o.fail(MISSING_PUBLICATION_DATE, MSG_MISSING_DATE);
                continue;
            }
            try {
                candidateBySource.put(row.Id, PubMigRules.toPublication(row));
            } catch (SObjectException e) {
                o.fail(CUSTOM_FIELD_WRITE_FAILED, categoryMessage(row.PublicationCategory, e.getMessage()));
                continue;
            }
            valid.add(row);
        }

        // ------------------------------------------------ [3] existing Publication per key, [4] in-chunk claim, [5] creator
        Set<String> keys = new Set<String>();
        for (PartyPublication row : valid) {
            keys.add(outcomeById.get(row.Id).groupKey);
        }
        Map<String, Id> existingPubByKey = valid.isEmpty() ? new Map<String, Id>() : tracker.existingPublicationByGroupKey(keys);

        Map<String, List<PartyPublication>> rowsByKey = new Map<String, List<PartyPublication>>();
        Map<String, Id> creatorByKey = new Map<String, Id>();
        List<String> newKeys = new List<String>();
        Set<Id> creatorUserOwners = new Set<Id>();
        for (PartyPublication row : valid) {
            String key = outcomeById.get(row.Id).groupKey;
            if (!rowsByKey.containsKey(key)) {
                rowsByKey.put(key, new List<PartyPublication>());
            }
            rowsByKey.get(key).add(row);
            if (!existingPubByKey.containsKey(key) && !creatorByKey.containsKey(key)) {
                creatorByKey.put(key, row.Id); // first valid row by CreatedDate, Id (§3.5)
                newKeys.add(key);
                if (row.OwnerId != null && row.OwnerId.getSObjectType() == User.SObjectType) {
                    creatorUserOwners.add(row.OwnerId);
                }
            }
        }

        // ------------------------------------------------ DML 1: new Publications
        Map<String, Id> newPubIdByKey = insertPublications(newKeys, creatorByKey, rowsByKey, candidateBySource, outcomeById, creatorUserOwners, res);

        // ------------------------------------------------ PAPER_FIELD_CONFLICT for non-creator rows
        Set<Id> existingPubIds = new Set<Id>(existingPubByKey.values());
        Map<Id, SObject> existingPubs = new Map<Id, SObject>();
        if (!existingPubIds.isEmpty()) {
            existingPubs = new Map<Id, SObject>(Database.query(
                'SELECT Id, ' + String.join(PubMigRules.PAPER_FIELDS, ', ') + ' FROM Publication WHERE Id IN :existingPubIds'
            ));
        }
        Map<Id, Id> pubIdBySource = new Map<Id, Id>();
        for (PartyPublication row : valid) {
            PubMigOutcome o = outcomeById.get(row.Id);
            if (o.isFailed()) {
                continue;
            }
            Id pubId = existingPubByKey.containsKey(o.groupKey) ? existingPubByKey.get(o.groupKey) : newPubIdByKey.get(o.groupKey);
            pubIdBySource.put(row.Id, pubId);
            if (creatorByKey.get(o.groupKey) == row.Id) {
                continue;
            }
            SObject reference = existingPubByKey.containsKey(o.groupKey)
                ? existingPubs.get(pubId)
                : candidateBySource.get(creatorByKey.get(o.groupKey));
            if (reference != null) {
                List<String> diffs = PubMigRules.differingFields(candidateBySource.get(row.Id), reference);
                if (!diffs.isEmpty()) {
                    o.warn(PAPER_FIELD_CONFLICT,
                        'This record\'s values for ' + String.join(diffs, ', ') + ' differ from Publication ' + pubId +
                        ', which was created from another record of the same publication. The Publication was not changed.');
                }
            }
        }

        // ------------------------------------------------ [6] SOQL + DML 2: reuse or create Contributors
        Set<Id> newContributorIds = upsertContributors(valid, pubIdBySource, existingPubIds, outcomeById, res);

        // ------------------------------------------------ DML 3: persist outcomes (migration fields only)
        res.notRecorded = tracker.record(res.outcomes);

        // ------------------------------------------------ DML 4-5: compensation (§6.3, I9)
        compensate(res, new Set<Id>(newPubIdByKey.values()), newContributorIds);
        return res;
    }

    // ==================================================================== Publications

    private Map<String, Id> insertPublications(
        List<String> newKeys, Map<String, Id> creatorByKey, Map<String, List<PartyPublication>> rowsByKey,
        Map<Id, Publication> candidateBySource, Map<Id, PubMigOutcome> outcomeById, Set<Id> creatorUserOwners, ChunkResult res
    ) {
        Map<String, Id> newPubIdByKey = new Map<String, Id>();
        if (newKeys.isEmpty()) {
            return newPubIdByKey;
        }
        Set<Id> inactiveOwners = creatorUserOwners.isEmpty()
            ? new Set<Id>()
            : new Map<Id, User>([SELECT Id FROM User WHERE Id IN :creatorUserOwners AND IsActive = false]).keySet();
        Id runningUser = UserInfo.getUserId();

        List<Publication> toInsert = new List<Publication>();
        Map<Id, Id> ownerBySource = new Map<Id, Id>();
        for (PartyPublication row : rowsAsList(rowsByKey, newKeys, creatorByKey)) {
            Publication p = candidateBySource.get(row.Id);
            p.OwnerId = PubMigRules.resolveOwner(row.OwnerId, inactiveOwners, runningUser);
            ownerBySource.put(row.Id, row.OwnerId);
            if (hook != null) {
                hook.beforePublicationInsert(row.Id, p);
            }
            toInsert.add(p);
        }

        List<Database.SaveResult> results = Database.insert(toInsert, false);
        for (Integer i = 0; i < results.size(); i++) {
            String key = newKeys[i];
            Id creatorId = creatorByKey.get(key);
            if (results[i].isSuccess()) {
                newPubIdByKey.put(key, results[i].getId());
                res.publicationsCreated++;
                if (inactiveOwners.contains(ownerBySource.get(creatorId))) {
                    outcomeById.get(creatorId).warn(OWNER_INACTIVE_REASSIGNED,
                        'The record owner (' + ownerBySource.get(creatorId) + ') is inactive, so Publication ' + results[i].getId() +
                        ' is owned by the user who ran the migration (' + runningUser + ').');
                }
                continue;
            }
            List<Database.Error> errors = results[i].getErrors();
            String code = PUBLICATION_CREATE_FAILED;
            String message = 'Couldn\'t create Publication: ' + describeErrors(errors) + '. All records for this publication were marked failed.';
            if (touchesField(errors, PubMigRules.CATEGORY_FIELD)) {
                code = CUSTOM_FIELD_WRITE_FAILED;
                message = categoryMessage((String) toInsert[i].get(PubMigRules.CATEGORY_FIELD), describeErrors(errors));
            }
            for (PartyPublication sibling : rowsByKey.get(key)) {
                outcomeById.get(sibling.Id).fail(code, message); // a group shares one paper, so one error (§5)
            }
        }
        return newPubIdByKey;
    }

    /** Creator rows in newKeys order, so toInsert[i] corresponds to newKeys[i]. */
    private static List<PartyPublication> rowsAsList(Map<String, List<PartyPublication>> rowsByKey, List<String> newKeys, Map<String, Id> creatorByKey) {
        List<PartyPublication> creators = new List<PartyPublication>();
        for (String key : newKeys) {
            for (PartyPublication row : rowsByKey.get(key)) {
                if (row.Id == creatorByKey.get(key)) {
                    creators.add(row);
                    break;
                }
            }
        }
        return creators;
    }

    // ==================================================================== Contributors

    private Set<Id> upsertContributors(
        List<PartyPublication> valid, Map<Id, Id> pubIdBySource, Set<Id> existingPubIds,
        Map<Id, PubMigOutcome> outcomeById, ChunkResult res
    ) {
        // I4: reuse an existing (PublicationId, ContributorId, ContributorRole)
        Map<String, Id> existingByKey = new Map<String, Id>();
        if (!existingPubIds.isEmpty()) {
            for (PublicationContributor c : [
                SELECT Id, PublicationId, ContributorId, ContributorRole
                FROM PublicationContributor
                WHERE PublicationId IN :existingPubIds
            ]) {
                existingByKey.put(contributorKey(c.PublicationId, c.ContributorId, c.ContributorRole), c.Id);
            }
        }

        // I5: dedupe new contributors inside the chunk
        Map<String, List<Id>> sourcesByNewKey = new Map<String, List<Id>>();
        List<String> newKeys = new List<String>();
        List<PublicationContributor> toInsert = new List<PublicationContributor>();
        for (PartyPublication row : valid) {
            PubMigOutcome o = outcomeById.get(row.Id);
            if (o.isFailed()) {
                continue;
            }
            Id pubId = pubIdBySource.get(row.Id);
            String key = contributorKey(pubId, row.PartyId, row.PartyRoleType);
            if (existingByKey.containsKey(key)) {
                o.migrate(existingByKey.get(key), pubId);
                res.contributorsReused++;
                continue;
            }
            if (!sourcesByNewKey.containsKey(key)) {
                sourcesByNewKey.put(key, new List<Id>());
                newKeys.add(key);
                PublicationContributor c = new PublicationContributor(
                    PublicationId = pubId,
                    ContributorId = row.PartyId,
                    ContributorRole = row.PartyRoleType,
                    IsEqualContribution = false
                );
                if (hook != null) {
                    hook.beforeContributorInsert(row.Id, c);
                }
                toInsert.add(c);
            }
            sourcesByNewKey.get(key).add(row.Id);
        }

        Set<Id> created = new Set<Id>();
        if (toInsert.isEmpty()) {
            return created;
        }
        List<Database.SaveResult> results = Database.insert(toInsert, false);
        for (Integer i = 0; i < results.size(); i++) {
            List<Id> sources = sourcesByNewKey.get(newKeys[i]);
            if (results[i].isSuccess()) {
                created.add(results[i].getId());
                res.contributorsCreated++;
                for (Id sourceId : sources) {
                    outcomeById.get(sourceId).migrate(results[i].getId(), toInsert[i].PublicationId);
                }
            } else {
                String message = 'Couldn\'t create Publication Contributor: ' + describeErrors(results[i].getErrors()) + '.';
                for (Id sourceId : sources) {
                    outcomeById.get(sourceId).fail(CONTRIBUTOR_CREATE_FAILED, message);
                }
            }
        }
        return created;
    }

    private static String contributorKey(Id publicationId, Id contributorId, String role) {
        return String.valueOf(publicationId) + '|' + String.valueOf(contributorId) + '|' + (role == null ? '' : role);
    }

    // ==================================================================== Compensation (§6.3)

    /**
     * Deletes records created in THIS transaction that no successfully recorded Migrated row points to:
     *  a. new Contributors of rows whose outcome couldn't be recorded (unless a recorded row shares them)
     *  b. new Publications with no recorded Migrated row (covers contributor failures and record failures)
     * Without this, the next run couldn't find them and would create duplicates.
     */
    private static void compensate(ChunkResult res, Set<Id> newPubIds, Set<Id> newContributorIds) {
        if (newPubIds.isEmpty() && newContributorIds.isEmpty()) {
            return;
        }
        Set<Id> linkedPubIds = new Set<Id>();
        Set<Id> linkedContributorIds = new Set<Id>();
        Map<Id, Id> pubByContributor = new Map<Id, Id>();
        for (PubMigOutcome o : res.outcomes) {
            if (o.contributorId != null) {
                pubByContributor.put(o.contributorId, o.publicationId);
            }
            if (o.isMigrated() && !res.notRecorded.containsKey(o.sourceId)) {
                linkedPubIds.add(o.publicationId);
                linkedContributorIds.add(o.contributorId);
            }
        }

        List<Id> pubsToDelete = new List<Id>();
        for (Id pubId : newPubIds) {
            if (!linkedPubIds.contains(pubId)) {
                pubsToDelete.add(pubId);
            }
        }
        Set<Id> pubsToDeleteSet = new Set<Id>(pubsToDelete);
        List<Id> contributorsToDelete = new List<Id>();
        for (Id contributorId : newContributorIds) {
            if (!linkedContributorIds.contains(contributorId) && !pubsToDeleteSet.contains(pubByContributor.get(contributorId))) {
                contributorsToDelete.add(contributorId); // its Publication stays, so delete it explicitly
            }
        }

        if (!contributorsToDelete.isEmpty()) {
            List<Database.DeleteResult> dr = Database.delete(contributorsToDelete, false);
            for (Integer i = 0; i < dr.size(); i++) {
                if (dr[i].isSuccess()) {
                    res.contributorsCompensated++;
                } else {
                    res.compensationFailures.add('PublicationContributor ' + contributorsToDelete[i] + ': ' + describeErrors(dr[i].getErrors()));
                }
            }
        }
        if (!pubsToDelete.isEmpty()) {
            List<Database.DeleteResult> dr = Database.delete(pubsToDelete, false); // cascades to its contributors
            for (Integer i = 0; i < dr.size(); i++) {
                if (dr[i].isSuccess()) {
                    res.publicationsCompensated++;
                } else {
                    res.compensationFailures.add('Publication ' + pubsToDelete[i] + ': ' + describeErrors(dr[i].getErrors()));
                }
            }
        }
    }

    // ==================================================================== helpers

    public static String describeErrors(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error e : errors) {
            String part = e.getStatusCode() + ': ' + e.getMessage();
            if (e.getFields() != null && !e.getFields().isEmpty()) {
                part += ' [' + String.join(e.getFields(), ', ') + ']';
            }
            parts.add(part);
        }
        return String.join(parts, '; ');
    }

    private static Boolean touchesField(List<Database.Error> errors, String fieldName) {
        for (Database.Error e : errors) {
            if (e.getFields() == null) {
                continue;
            }
            for (String f : e.getFields()) {
                if (f.equalsIgnoreCase(fieldName)) {
                    return true;
                }
            }
        }
        return false;
    }

    private static String categoryMessage(String value, String error) {
        return 'Couldn\'t write Publication Category \'' + value + '\' to Publication.' + PubMigRules.CATEGORY_FIELD + ': ' + error +
            '. Add the value to the field (or change its type), then rerun the migration.';
    }
}
