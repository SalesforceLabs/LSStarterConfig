/**
 * PATH B tracker: keeps migration state in a separate custom object, PublicationMigrationLog__c, so
 * PartyPublication is only ever READ (no field, no update, no trigger, no change event).
 * Switch to it with PubMigConfig.USE_LOG_OBJECT = true (setup guide Step 1, Path B).
 *
 * One log row per PartyPublication row, found by SourceId__c (External ID, Unique):
 *
 *   SourceId__c               Text(18)  External ID, Unique   the PartyPublication Id
 *   GroupKey__c               Text(64)  External ID           same paper => same key
 *   Status__c                 Picklist  Migrated / Failed / Excluded
 *   ErrorCode__c              Text(80)
 *   Message__c                Long Text Area (32768)
 *   PublicationContributor__c Lookup(Publication Contributor)  cleared if the Contributor is deleted
 *   Publication__c            Lookup(Publication)              cleared if the Publication is deleted
 *   Name                      Auto Number (the migration doesn't provide a name)
 *
 * All access is dynamic, so this class compiles in an org that doesn't have the object (Path A orgs).
 *
 * State rules are the same as PartyPublicationFieldTracker: no log row or Failed => eligible; Migrated and
 * Excluded are skipped. A customer excludes a record by upserting a log row with Status__c = Excluded.
 */
public without sharing class PubMigLogTracker implements PubMigTracker, PubMigStatusReader {

    public static final String OBJECT_NAME = 'PublicationMigrationLog__c';
    public static final String F_SOURCE = 'SourceId__c';
    public static final String F_KEY = 'GroupKey__c';
    public static final String F_STATUS = 'Status__c';
    public static final String F_CODE = 'ErrorCode__c';
    public static final String F_MESSAGE = 'Message__c';
    public static final String F_CONTRIBUTOR = 'PublicationContributor__c';
    public static final String F_PUBLICATION = 'Publication__c';

    public static final List<String> LOG_FIELDS = new List<String>{
        F_SOURCE, F_KEY, F_STATUS, F_CODE, F_MESSAGE, F_CONTRIBUTOR, F_PUBLICATION
    };

    /** Test-only: number of log rows this tracker has sent to upsert. */
    @TestVisible
    private static Integer rowsWritten = 0;

    private static Schema.SObjectType cachedType;

    private static Schema.SObjectType logType() {
        if (cachedType == null) {
            cachedType = Schema.getGlobalDescribe().get(OBJECT_NAME.toLowerCase());
        }
        return cachedType;
    }

    // ---------------------------------------------------------------- prerequisites

    public List<String> checkPrerequisites() {
        List<String> problems = new List<String>();
        Schema.SObjectType t = logType();
        if (t == null) {
            problems.add('Required object ' + OBJECT_NAME + ' is missing. Create it, or set PubMigConfig.USE_LOG_OBJECT back to false.');
            return problems;
        }
        Schema.DescribeSObjectResult obj = t.getDescribe();
        if (!obj.isAccessible() || !obj.isCreateable() || !obj.isUpdateable()) {
            problems.add('Running user lacks read/create/edit on object ' + OBJECT_NAME + '.');
        }
        Map<String, Schema.SObjectField> fields = obj.fields.getMap();
        Schema.SObjectField name = fields.get('name');
        if (name != null && !name.getDescribe().isAutoNumber()) {
            problems.add('The Name field of ' + OBJECT_NAME + ' must be an Auto Number (for example PML-{00000000}). The migration doesn\'t provide a name.');
        }

        Schema.DescribeFieldResult source = describe(fields, F_SOURCE, Schema.DisplayType.STRING, 'Text(18), External ID, Unique', problems);
        if (source != null) {
            if (source.getLength() < 18) {
                problems.add(wrongType(F_SOURCE, 'Text(18), External ID, Unique') + ' Its length is ' + source.getLength() + '.');
            }
            if (!source.isExternalId() || !source.isUnique()) {
                problems.add('Field ' + OBJECT_NAME + '.' + F_SOURCE + ' must be marked External ID and Unique (it is the upsert key: one log row per PartyPublication record).');
            }
        }

        Schema.DescribeFieldResult key = describe(fields, F_KEY, Schema.DisplayType.STRING, 'Text(64), External ID', problems);
        if (key != null) {
            if (key.getLength() < 64) {
                problems.add(wrongType(F_KEY, 'Text(64), External ID') + ' Its length is ' + key.getLength() + '.');
            }
            if (!key.isExternalId()) {
                problems.add('Field ' + OBJECT_NAME + '.' + F_KEY + ' must be marked External ID (it is used to find Publications created by earlier runs).');
            }
            if (key.isUnique()) {
                problems.add('Field ' + OBJECT_NAME + '.' + F_KEY + ' must NOT be unique: all records of one publication share the same key.');
            }
        }

        Schema.DescribeFieldResult status = describe(fields, F_STATUS, Schema.DisplayType.PICKLIST, 'Picklist', problems);
        if (status != null) {
            Set<String> values = new Set<String>();
            for (Schema.PicklistEntry e : status.getPicklistValues()) {
                values.add(e.getValue());
            }
            for (String required : new List<String>{ PubMigOutcome.STATUS_MIGRATED, PubMigOutcome.STATUS_FAILED, PubMigOutcome.STATUS_EXCLUDED }) {
                if (!values.contains(required)) {
                    problems.add('Picklist ' + OBJECT_NAME + '.' + F_STATUS + ' is missing the value "' + required + '" (API name, case-sensitive).');
                }
            }
        }

        describe(fields, F_CODE, Schema.DisplayType.STRING, 'Text(80)', problems);
        describe(fields, F_MESSAGE, Schema.DisplayType.TEXTAREA, 'Long Text Area(32768)', problems);

        Schema.DescribeFieldResult contributor = describe(fields, F_CONTRIBUTOR, Schema.DisplayType.REFERENCE, 'Lookup(Publication Contributor)', problems);
        if (contributor != null && !contributor.getReferenceTo().contains(PublicationContributor.SObjectType)) {
            problems.add(wrongType(F_CONTRIBUTOR, 'Lookup(Publication Contributor)'));
        }
        Schema.DescribeFieldResult publication = describe(fields, F_PUBLICATION, Schema.DisplayType.REFERENCE, 'Lookup(Publication)', problems);
        if (publication != null && !publication.getReferenceTo().contains(Publication.SObjectType)) {
            problems.add(wrongType(F_PUBLICATION, 'Lookup(Publication)'));
        }
        return problems;
    }

    private static Schema.DescribeFieldResult describe(
        Map<String, Schema.SObjectField> fields, String name, Schema.DisplayType expected, String expectedLabel, List<String> problems
    ) {
        Schema.SObjectField f = fields.get(name.toLowerCase());
        if (f == null) {
            problems.add('Required field ' + OBJECT_NAME + '.' + name + ' is missing (expected ' + expectedLabel + ').');
            return null;
        }
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.getType() != expected) {
            problems.add(wrongType(name, expectedLabel));
            return null;
        }
        if (!d.isAccessible() || !d.isCreateable() || !d.isUpdateable()) {
            problems.add('Running user lacks read/edit field-level security on ' + OBJECT_NAME + '.' + name + '.');
        }
        return d;
    }

    private static String wrongType(String name, String expectedLabel) {
        return 'Required field ' + OBJECT_NAME + '.' + name + ' has the wrong type (expected ' + expectedLabel + ').';
    }

    // ---------------------------------------------------------------- reads

    /** Every PartyPublication row. The log can't filter them in SOQL, so eligible() filters each chunk. */
    public Database.QueryLocator candidates() {
        return Database.getQueryLocator([SELECT Id FROM PartyPublication ORDER BY CreatedDate, Id]);
    }

    public Map<Id, PubMigOutcome> eligible(Set<Id> sourceIds) {
        Map<Id, PubMigOutcome> result = new Map<Id, PubMigOutcome>();
        Set<String> sourceKeys = asKeys(sourceIds);
        Map<Id, SObject> logBySource = new Map<Id, SObject>();
        for (SObject log : Database.query(
            'SELECT Id, ' + String.join(LOG_FIELDS, ', ') + ' FROM ' + OBJECT_NAME + ' WHERE ' + F_SOURCE + ' IN :sourceKeys'
        )) {
            logBySource.put((Id) log.get(F_SOURCE), log);
        }
        for (Id sourceId : sourceIds) {
            SObject log = logBySource.get(sourceId);
            if (log == null) {
                result.put(sourceId, new PubMigOutcome(sourceId)); // never processed
                continue;
            }
            String status = (String) log.get(F_STATUS);
            if (log.get(F_CONTRIBUTOR) != null || (status != null && status != PubMigOutcome.STATUS_FAILED)) {
                continue; // Migrated, Excluded or already linked
            }
            PubMigOutcome prev = new PubMigOutcome(sourceId);
            prev.status = status;
            prev.errorCode = (String) log.get(F_CODE);
            prev.message = (String) log.get(F_MESSAGE);
            prev.groupKey = (String) log.get(F_KEY);
            prev.contributorId = (Id) log.get(F_CONTRIBUTOR);
            prev.publicationId = (Id) log.get(F_PUBLICATION);
            result.put(sourceId, prev);
        }
        return result;
    }

    public Map<String, Id> existingPublicationByGroupKey(Set<String> groupKeys) {
        Map<String, Id> result = new Map<String, Id>();
        if (groupKeys == null || groupKeys.isEmpty()) {
            return result;
        }
        for (SObject log : Database.query(
            'SELECT ' + F_KEY + ', ' + F_PUBLICATION + ' FROM ' + OBJECT_NAME +
            ' WHERE ' + F_KEY + ' IN :groupKeys AND ' + F_PUBLICATION + ' != null ORDER BY CreatedDate, Id'
        )) {
            String key = (String) log.get(F_KEY);
            if (!result.containsKey(key)) {
                result.put(key, (Id) log.get(F_PUBLICATION));
            }
        }
        return result;
    }

    /** For the pre-flight report: rows that are already Migrated or Excluded. */
    public Map<Id, String> statusBySource(Set<Id> sourceIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (sourceIds == null || sourceIds.isEmpty()) {
            return result;
        }
        Set<String> sourceKeys = asKeys(sourceIds);
        for (SObject log : Database.query(
            'SELECT ' + F_SOURCE + ', ' + F_STATUS + ' FROM ' + OBJECT_NAME +
            ' WHERE ' + F_SOURCE + ' IN :sourceKeys AND ' + F_STATUS + ' != null'
        )) {
            result.put((Id) log.get(F_SOURCE), (String) log.get(F_STATUS));
        }
        return result;
    }

    private static Set<String> asKeys(Set<Id> ids) {
        Set<String> keys = new Set<String>();
        for (Id i : ids) {
            keys.add(String.valueOf(i)); // 18 characters, as stored in SourceId__c
        }
        return keys;
    }

    // ---------------------------------------------------------------- writes

    /** One upsert on SourceId__c: creates the row the first time a record is processed, updates it afterwards. */
    public Map<Id, String> record(List<PubMigOutcome> outcomes) {
        Map<Id, String> notRecorded = new Map<Id, String>();
        Schema.SObjectType t = logType();
        Map<String, Schema.SObjectField> fields = t.getDescribe().fields.getMap();
        Integer messageLength = fields.get(F_MESSAGE.toLowerCase()).getDescribe().getLength();

        // Upsert with an External ID needs a concrete list type; a generic List<SObject> is rejected at run time.
        List<SObject> upserts = (List<SObject>) Type.forName('List<' + OBJECT_NAME + '>').newInstance();
        List<Id> sourceIds = new List<Id>();
        for (PubMigOutcome o : outcomes) {
            String message = o.message == null ? null : o.message.abbreviate(messageLength);
            if (!isChanged(o, message)) {
                continue; // don't rewrite rows whose state didn't change
            }
            SObject log = t.newSObject();
            log.put(F_SOURCE, String.valueOf(o.sourceId));
            log.put(F_STATUS, o.status);
            log.put(F_CODE, o.errorCode);
            log.put(F_MESSAGE, message);
            log.put(F_KEY, o.groupKey);
            log.put(F_CONTRIBUTOR, o.contributorId);
            log.put(F_PUBLICATION, o.publicationId);
            upserts.add(log);
            sourceIds.add(o.sourceId);
        }
        if (upserts.isEmpty()) {
            return notRecorded;
        }
        rowsWritten += upserts.size();
        List<Database.UpsertResult> results = Database.upsert(upserts, fields.get(F_SOURCE.toLowerCase()), false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                notRecorded.put(sourceIds[i], PubMigEngine.describeErrors(results[i].getErrors()));
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
            !same(o.groupKey, p.groupKey) || o.contributorId != p.contributorId || o.publicationId != p.publicationId;
    }

    private static Boolean same(String a, String b) {
        return a == null ? b == null : a.equals(b);
    }
}
