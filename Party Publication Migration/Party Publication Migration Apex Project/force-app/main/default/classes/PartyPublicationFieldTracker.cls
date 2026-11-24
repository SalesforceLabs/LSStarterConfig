/**
 * Default tracker: stores migration state in five customer-created fields on PartyPublication
 * (design §1.1). These are the ONLY fields the migration ever writes on PartyPublication (R8, §6.4).
 *
 * All field access is dynamic so the class compiles before the customer creates the fields.
 */
public without sharing class PartyPublicationFieldTracker implements PubMigTracker, PubMigStatusReader {

    public static final String F_LOOKUP = 'PublicationContributor__c';
    public static final String F_STATUS = 'MigrationStatus__c';
    public static final String F_CODE = 'MigrationErrorCode__c';
    public static final String F_MESSAGE = 'MigrationMessage__c';
    public static final String F_KEY = 'MigrationGroupKey__c';

    public static final List<String> MIGRATION_FIELDS = new List<String>{ F_LOOKUP, F_STATUS, F_CODE, F_MESSAGE, F_KEY };

    /** Test-only: number of PartyPublication rows this tracker has sent to update (verifies I7). */
    @TestVisible
    private static Integer rowsUpdated = 0;

    private static final String ELIGIBLE_FILTER =
        '(' + F_STATUS + ' = null OR ' + F_STATUS + ' = \'' + PubMigOutcome.STATUS_FAILED + '\') AND ' + F_LOOKUP + ' = null';

    // ---------------------------------------------------------------- prerequisites (§1.5)

    public List<String> checkPrerequisites() {
        List<String> problems = new List<String>();
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.PartyPublication.fields.getMap();

        Schema.DescribeFieldResult lookup = describe(fields, F_LOOKUP, Schema.DisplayType.REFERENCE, 'Lookup(Publication Contributor)', problems);
        if (lookup != null && !lookup.getReferenceTo().contains(PublicationContributor.SObjectType)) {
            problems.add(wrongType(F_LOOKUP, 'Lookup(Publication Contributor)'));
        }

        Schema.DescribeFieldResult status = describe(fields, F_STATUS, Schema.DisplayType.PICKLIST, 'Picklist', problems);
        if (status != null) {
            Set<String> values = new Set<String>();
            for (Schema.PicklistEntry e : status.getPicklistValues()) {
                values.add(e.getValue());
            }
            for (String required : new List<String>{ PubMigOutcome.STATUS_MIGRATED, PubMigOutcome.STATUS_FAILED, PubMigOutcome.STATUS_EXCLUDED }) {
                if (!values.contains(required)) {
                    problems.add('Picklist PartyPublication.' + F_STATUS + ' is missing the value "' + required + '" (API name, case-sensitive).');
                }
            }
        }

        describe(fields, F_CODE, Schema.DisplayType.STRING, 'Text(80)', problems);
        describe(fields, F_MESSAGE, Schema.DisplayType.TEXTAREA, 'Long Text Area(32768)', problems);

        Schema.DescribeFieldResult key = describe(fields, F_KEY, Schema.DisplayType.STRING, 'Text(64), External ID', problems);
        if (key != null) {
            if (key.getLength() < 64) {
                problems.add(wrongType(F_KEY, 'Text(64), External ID') + ' Its length is ' + key.getLength() + '.');
            }
            if (!key.isExternalId()) {
                problems.add('Field PartyPublication.' + F_KEY + ' must be marked External ID (it is used to find Publications created by earlier runs).');
            }
            if (key.isUnique()) {
                problems.add('Field PartyPublication.' + F_KEY + ' must NOT be unique: all records of one publication share the same key.');
            }
        }
        return problems;
    }

    private static Schema.DescribeFieldResult describe(
        Map<String, Schema.SObjectField> fields, String name, Schema.DisplayType expected, String expectedLabel, List<String> problems
    ) {
        Schema.SObjectField f = fields.get(name.toLowerCase());
        if (f == null) {
            problems.add('Required field PartyPublication.' + name + ' is missing (expected ' + expectedLabel + ').');
            return null;
        }
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.getType() != expected) {
            problems.add(wrongType(name, expectedLabel));
            return null;
        }
        if (!d.isAccessible() || !d.isUpdateable()) {
            problems.add('Running user lacks read/edit field-level security on PartyPublication.' + name + '.');
        }
        return d;
    }

    private static String wrongType(String name, String expectedLabel) {
        return 'Required field PartyPublication.' + name + ' has the wrong type (expected ' + expectedLabel + ').';
    }

    // ---------------------------------------------------------------- reads

    public Database.QueryLocator candidates() {
        return Database.getQueryLocator(
            'SELECT Id FROM PartyPublication WHERE ' + ELIGIBLE_FILTER + ' ORDER BY CreatedDate, Id'
        );
    }

    public Map<Id, PubMigOutcome> eligible(Set<Id> sourceIds) {
        Map<Id, PubMigOutcome> result = new Map<Id, PubMigOutcome>();
        String soql = 'SELECT Id, ' + String.join(MIGRATION_FIELDS, ', ') +
            ' FROM PartyPublication WHERE Id IN :sourceIds AND ' + ELIGIBLE_FILTER;
        for (SObject r : Database.query(soql)) {
            PubMigOutcome prev = new PubMigOutcome(r.Id);
            prev.status = (String) r.get(F_STATUS);
            prev.errorCode = (String) r.get(F_CODE);
            prev.message = (String) r.get(F_MESSAGE);
            prev.groupKey = (String) r.get(F_KEY);
            prev.contributorId = (Id) r.get(F_LOOKUP);
            result.put(r.Id, prev);
        }
        return result;
    }

    public Map<String, Id> existingPublicationByGroupKey(Set<String> groupKeys) {
        Map<String, Id> result = new Map<String, Id>();
        if (groupKeys == null || groupKeys.isEmpty()) {
            return result;
        }
        String relationship = F_LOOKUP.removeEnd('__c') + '__r';
        String soql = 'SELECT ' + F_KEY + ', ' + relationship + '.PublicationId FROM PartyPublication' +
            ' WHERE ' + F_KEY + ' IN :groupKeys AND ' + F_LOOKUP + ' != null ORDER BY CreatedDate, Id';
        for (SObject r : Database.query(soql)) {
            String key = (String) r.get(F_KEY);
            SObject contributor = r.getSObject(relationship);
            if (!result.containsKey(key) && contributor != null && contributor.get('PublicationId') != null) {
                result.put(key, (Id) contributor.get('PublicationId'));
            }
        }
        return result;
    }

    /** For the pre-flight report. Empty before the status field exists (setup guide Step 1). */
    public Map<Id, String> statusBySource(Set<Id> sourceIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (sourceIds == null || sourceIds.isEmpty() || !Schema.SObjectType.PartyPublication.fields.getMap().containsKey(F_STATUS.toLowerCase())) {
            return result;
        }
        for (SObject r : Database.query('SELECT Id, ' + F_STATUS + ' FROM PartyPublication WHERE Id IN :sourceIds AND ' + F_STATUS + ' != null')) {
            result.put(r.Id, (String) r.get(F_STATUS));
        }
        return result;
    }

    // ---------------------------------------------------------------- writes (§6.4)

    public Map<Id, String> record(List<PubMigOutcome> outcomes) {
        Map<Id, String> notRecorded = new Map<Id, String>();
        Integer messageLength = Schema.SObjectType.PartyPublication.fields.getMap().get(F_MESSAGE.toLowerCase()).getDescribe().getLength();

        List<SObject> updates = new List<SObject>();
        for (PubMigOutcome o : outcomes) {
            String message = o.message == null ? null : o.message.abbreviate(messageLength);
            if (!isChanged(o, message)) {
                continue; // I7: don't touch rows whose migration state didn't change
            }
            // R8: a fresh sObject carrying ONLY migration fields; never a queried instance.
            SObject upd = PartyPublication.SObjectType.newSObject(o.sourceId);
            upd.put(F_STATUS, o.status);
            upd.put(F_CODE, o.errorCode);
            upd.put(F_MESSAGE, message);
            upd.put(F_KEY, o.groupKey);
            upd.put(F_LOOKUP, o.contributorId);
            updates.add(upd);
        }
        if (updates.isEmpty()) {
            return notRecorded;
        }
        rowsUpdated += updates.size();
        List<Database.SaveResult> results = Database.update(updates, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                notRecorded.put(updates[i].Id, PubMigEngine.describeErrors(results[i].getErrors()));
            }
        }
        return notRecorded;
    }

    private static Boolean isChanged(PubMigOutcome o, String truncatedMessage) {
        PubMigOutcome p = o.previous;
        if (p == null) {
            return true;
        }
        return !same(o.status, p.status) || !same(o.errorCode, p.errorCode) || !same(truncatedMessage, p.message) ||
            !same(o.groupKey, p.groupKey) || o.contributorId != p.contributorId;
    }

    private static Boolean same(String a, String b) {
        return a == null ? b == null : a.equals(b);
    }
}
