/**
 * Checks run in start() before any record is processed (design §1.5, I8).
 * If anything is returned, the batch processes nothing and the summary email lists the problems.
 */
public without sharing class PubMigGuard {

    private static final List<String> PUBLICATION_FIELDS = new List<String>{
        'Name', 'Title', 'PublishedDate', 'OriginalSourceName', 'AbstractText', PubMigRules.FIELD_DOI,
        PubMigRules.FIELD_EXTERNAL_ID, 'PublicationUrl', 'CitationCount', 'ImpactFactor', 'Status', 'OwnerId'
    };
    private static final List<String> CONTRIBUTOR_FIELDS = new List<String>{
        'PublicationId', 'ContributorId', 'ContributorRole', 'IsEqualContribution'
    };

    public static List<String> problems(PubMigTracker tracker, Id currentJobId) {
        List<String> problems = new List<String>();
        problems.addAll(tracker.checkPrerequisites());
        problems.addAll(targetProblems());
        Id other = otherRunningInstance(currentJobId);
        if (other != null) {
            problems.add('Another migration job (' + other + ') is already queued or running. Wait for it to finish, then rerun.');
        }
        return problems;
    }

    @TestVisible
    private static List<String> targetProblems() {
        List<String> problems = new List<String>();

        Schema.DescribeSObjectResult pub = Schema.SObjectType.Publication;
        Schema.DescribeSObjectResult ctrb = Schema.SObjectType.PublicationContributor;
        if (!pub.isCreateable() || !pub.isDeletable()) {
            problems.add('Running user lacks create/delete on Publication (Publications permissions: create and delete; delete is used only to remove records this run created but could not link).');
        }
        if (!ctrb.isCreateable() || !ctrb.isDeletable()) {
            problems.add('Running user lacks create/delete on Publication Contributor.');
        }

        Map<String, Schema.SObjectField> pubFields = pub.fields.getMap();
        Schema.SObjectField category = pubFields.get(PubMigRules.CATEGORY_FIELD.toLowerCase());
        if (category == null) {
            problems.add('Required field Publication.' + PubMigRules.CATEGORY_FIELD + ' is missing. Create it before running the migration.');
        } else if (!category.getDescribe().isCreateable()) {
            problems.add('Running user lacks edit field-level security on Publication.' + PubMigRules.CATEGORY_FIELD + '.');
        }
        if (PubMigRules.LISTING_FIELD == null) {
            problems.add('Required field Publication.ListingPlatformType is missing in this org.');
        } else if (!pubFields.get(PubMigRules.LISTING_FIELD.toLowerCase()).getDescribe().isCreateable()) {
            problems.add('Running user lacks edit field-level security on Publication.' + PubMigRules.LISTING_FIELD + '.');
        }
        problems.addAll(fieldSecurityProblems('Publication', pubFields, PUBLICATION_FIELDS));
        problems.addAll(fieldSecurityProblems('PublicationContributor', ctrb.fields.getMap(), CONTRIBUTOR_FIELDS));
        return problems;
    }

    private static List<String> fieldSecurityProblems(String objectName, Map<String, Schema.SObjectField> fields, List<String> names) {
        List<String> problems = new List<String>();
        for (String name : names) {
            Schema.SObjectField f = fields.get(name.toLowerCase());
            if (f == null) {
                problems.add('Required field ' + objectName + '.' + name + ' is missing in this org.');
            } else if (!f.getDescribe().isCreateable()) {
                problems.add('Running user lacks edit field-level security on ' + objectName + '.' + name + '.');
            }
        }
        return problems;
    }

    /** I8: another instance of this batch that is queued or running. */
    public static Id otherRunningInstance(Id currentJobId) {
        List<AsyncApexJob> jobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
              AND ApexClass.Name = :PartyPublicationMigrationBatch.class.getName()
              AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
              AND Id != :currentJobId
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0].Id;
    }
}
