/**
 * Where the migration keeps its per-row state (design §6.5).
 *
 * Every read and write of migration state goes through this interface. The default implementation,
 * PartyPublicationFieldTracker, stores state in five customer-created fields on PartyPublication.
 * A customer who doesn't allow updates to PartyPublication implements this interface against their
 * own tracking object and passes it to the batch:
 *
 *     Database.executeBatch(new PartyPublicationMigrationBatch(new MyTracker()), 200);
 *
 * CONTRACT: record() must durably persist each outcome before the next run. The duplicate-prevention
 * rules (no re-processing of Migrated rows, reuse of a paper's existing Publication) depend on it.
 */
public interface PubMigTracker {

    /** Tracker-specific prerequisites (fields, FLS). Each returned string is one problem; empty = OK. */
    List<String> checkPrerequisites();

    /** Rows to consider, ordered by CreatedDate, Id. May be a superset; eligible() filters again. */
    Database.QueryLocator candidates();

    /**
     * Of these source rows, the ones still eligible (not Migrated, not Excluded, not linked),
     * mapped to their current state (status, code, message, key, contributor) for change detection.
     */
    Map<Id, PubMigOutcome> eligible(Set<Id> sourceIds);

    /** Publication already created by this script for each group key (decision step [3], design §3.1). */
    Map<String, Id> existingPublicationByGroupKey(Set<String> groupKeys);

    /**
     * Persist each outcome. Should skip outcomes that equal their previous state.
     * Returns sourceId -> error for every outcome that could NOT be persisted; the engine
     * then deletes what it created for those rows (compensation, design §6.3).
     */
    Map<Id, String> record(List<PubMigOutcome> outcomes);
}
