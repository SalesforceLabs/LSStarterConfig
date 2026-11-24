/**
 * Test data and helpers for the PartyPublication migration tests.
 */
@IsTest
public class PubMigTestData {

    public static final String DOI_A = '10.1038/nature12373';

    // ---------------------------------------------------------------- parties (one of each domain type)

    public static Account account() {
        Account a = new Account(Name = 'PubMig Test University');
        insert a;
        return a;
    }

    /** True if PublicationContributor.ContributorId can point at this object in this org (the Contributor domain is configurable). */
    public static Boolean contributorAccepts(String objectName) {
        for (Schema.SObjectType t : Schema.SObjectType.PublicationContributor.fields.getMap().get('contributorid').getDescribe().getReferenceTo()) {
            if (t.getDescribe().getName() == objectName) {
                return true;
            }
        }
        return false;
    }

    public static Individual individual() {
        Individual i = new Individual(LastName = 'PubMigIndividual');
        insert i;
        return i;
    }

    public static HealthcareProvider healthcareProvider() {
        HealthcareProvider h = new HealthcareProvider(Name = 'PubMig Test Provider');
        insert h;
        return h;
    }

    // ---------------------------------------------------------------- source rows

    public static PartyPublication row(Id partyId, String title, Date publicationDate, String identifier) {
        return new PartyPublication(
            PartyId = partyId,
            Title = title,
            PublicationDate = publicationDate,
            PublicationIdentifier = identifier,
            PublishedOn = 'Nature'
        );
    }

    /** Inserts in list order, so Ids (and therefore the creator order) follow the list. */
    public static List<PartyPublication> insertRows(List<PartyPublication> rows) {
        insert rows;
        return rows;
    }

    // ---------------------------------------------------------------- reading state

    public static Map<Id, SObject> state() {
        return new Map<Id, SObject>(Database.query(
            'SELECT Id, ' + String.join(PartyPublicationFieldTracker.MIGRATION_FIELDS, ', ') +
            ', PublicationContributor__r.PublicationId FROM PartyPublication'
        ));
    }

    public static String status(SObject row) {
        return (String) row.get(PartyPublicationFieldTracker.F_STATUS);
    }

    public static String code(SObject row) {
        return (String) row.get(PartyPublicationFieldTracker.F_CODE);
    }

    public static String message(SObject row) {
        return (String) row.get(PartyPublicationFieldTracker.F_MESSAGE);
    }

    public static Id contributorId(SObject row) {
        return (Id) row.get(PartyPublicationFieldTracker.F_LOOKUP);
    }

    public static Id publicationId(SObject row) {
        SObject c = row.getSObject('PublicationContributor__r');
        return c == null ? null : (Id) c.get('PublicationId');
    }

    public static Integer publicationCount() {
        return [SELECT COUNT() FROM Publication];
    }

    public static Integer contributorCount() {
        return [SELECT COUNT() FROM PublicationContributor];
    }

    /**
     * A picklist value that exists on both fields, or null (value sets are org-configurable,
     * so tests that need a real value skip their assertion if there is none).
     */
    public static String commonPicklistValue(Schema.SObjectField sourceField, Schema.SObjectType targetType, String targetFieldName) {
        Schema.SObjectField target = targetType.getDescribe().fields.getMap().get(targetFieldName.toLowerCase());
        if (target == null) {
            return null;
        }
        Schema.DescribeFieldResult td = target.getDescribe();
        Boolean targetIsPicklist = td.getType() == Schema.DisplayType.PICKLIST || td.getType() == Schema.DisplayType.MULTIPICKLIST;
        Set<String> targetValues = new Set<String>();
        for (Schema.PicklistEntry e : td.getPicklistValues()) {
            if (e.isActive()) {
                targetValues.add(e.getValue());
            }
        }
        for (Schema.PicklistEntry e : sourceField.getDescribe().getPicklistValues()) {
            if (e.isActive() && (!targetIsPicklist || targetValues.contains(e.getValue()))) {
                return e.getValue();
            }
        }
        return null;
    }

    // ---------------------------------------------------------------- running the batch inline

    /**
     * Runs start → execute (chunks of chunkSize) → finish synchronously. Lets one test method run several
     * chunks and several runs, which Database.executeBatch can't do in a test (one execute only).
     */
    public static PubMigSummary runMigration(PubMigTracker tracker, Integer chunkSize) {
        return runMigration(tracker, chunkSize, null);
    }

    public static PubMigSummary runMigration(PubMigTracker tracker, Integer chunkSize, PubMigInsertHook hook) {
        PartyPublicationMigrationBatch batch = new PartyPublicationMigrationBatch(
            tracker == null ? new PartyPublicationFieldTracker() : tracker, hook
        );
        Database.QueryLocatorIterator it = batch.start(null).iterator();
        List<SObject> all = new List<SObject>();
        while (it.hasNext()) {
            all.add(it.next());
        }
        List<SObject> chunk = new List<SObject>();
        for (SObject r : all) {
            chunk.add(r);
            if (chunk.size() == chunkSize) {
                batch.execute(null, chunk);
                chunk = new List<SObject>();
            }
        }
        if (!chunk.isEmpty()) {
            batch.execute(null, chunk);
        }
        batch.finish(null);
        return batch.summary;
    }

    public static PubMigSummary runMigration() {
        return runMigration(null, PartyPublicationMigrationBatch.DEFAULT_BATCH_SIZE);
    }
}
