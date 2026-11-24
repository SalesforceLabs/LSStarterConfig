/**
 * Migrates PartyPublication (Life Sciences) to Publication + PublicationContributor (Education Cloud).
 * Design: partypublication-to-publication-migration-script-design.md (v0.3).
 *
 * Run (Anonymous Apex):
 *     PartyPublicationMigrationBatch.run();
 * It tracks progress with fields on PartyPublication (Path A) or with PublicationMigrationLog__c (Path B),
 * as set by PubMigConfig.USE_LOG_OBJECT. With a custom tracker / batch size:
 *     Database.executeBatch(new PartyPublicationMigrationBatch(new MyTracker()), 50);
 *
 * Safe to rerun: Migrated and Excluded rows are skipped, Failed rows are retried, and
 * Publications created by earlier runs are reused.
 *
 * without sharing: the job must see every source row. Restrict who can run it with an
 * admin-only permission set (setup guide step 2).
 */
public without sharing class PartyPublicationMigrationBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private final PubMigTracker tracker;
    private final PubMigInsertHook hook; // null in production runs
    @TestVisible
    private PubMigSummary summary = new PubMigSummary();

    public PartyPublicationMigrationBatch() {
        this(PubMigConfig.tracker()); // PubMigConfig.USE_LOG_OBJECT picks the tracker
    }

    public PartyPublicationMigrationBatch(PubMigTracker tracker) {
        this(tracker, null);
    }

    public PartyPublicationMigrationBatch(PubMigTracker tracker, PubMigInsertHook hook) {
        this.tracker = tracker;
        this.hook = hook;
    }

    public static Id run() {
        return Database.executeBatch(new PartyPublicationMigrationBatch(), DEFAULT_BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        List<String> problems = PubMigGuard.problems(tracker, bc == null ? null : bc.getJobId());
        if (!problems.isEmpty()) {
            summary.abortReasons.addAll(problems);
            return Database.getQueryLocator([SELECT Id FROM PartyPublication LIMIT 0]);
        }
        return tracker.candidates();
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (summary.isAborted()) {
            return;
        }
        // An exception in the middle of a chunk would otherwise leave Publications and Contributors that no
        // PartyPublication row points to, and the retry would duplicate them. Roll the whole chunk back, report
        // it in the summary, and let the job continue. The rows stay eligible, so the next run retries them.
        // (Limit exceptions can't be caught; finish() reports those through the job's error count.)
        Savepoint sp = Database.setSavepoint();
        try {
            summary.add(new PubMigEngine(tracker, hook).run(new Map<Id, SObject>(scope).keySet()));
        } catch (Exception e) {
            Database.rollback(sp);
            summary.addChunkFailure(scope.size(), e);
        }
    }

    public void finish(Database.BatchableContext bc) {
        Id jobId = bc == null ? null : bc.getJobId();
        if (jobId != null) {
            for (AsyncApexJob job : [SELECT NumberOfErrors, ExtendedStatus FROM AsyncApexJob WHERE Id = :jobId]) {
                summary.jobErrors = job.NumberOfErrors == null ? 0 : job.NumberOfErrors;
                summary.jobStatusDetail = job.ExtendedStatus;
            }
        }
        summary.send(jobId);
    }
}
