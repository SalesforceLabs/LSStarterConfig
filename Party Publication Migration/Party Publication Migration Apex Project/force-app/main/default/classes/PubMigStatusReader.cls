/**
 * Optional second interface for a PubMigTracker: lets the pre-flight report ask which rows are already
 * Migrated or Excluded without knowing where the tracker keeps that. Both built-in trackers implement it.
 * A custom tracker that doesn't implement it is treated as "no row has a status".
 */
public interface PubMigStatusReader {

    /** Status (Migrated / Failed / Excluded) of each of these source rows that has one. Rows without a status are absent. */
    Map<Id, String> statusBySource(Set<Id> sourceIds);
}
