/**
 * Optional hook called just before the engine inserts a target record. It exists so tests can inject
 * real insert failures through the constructor instead of test-only branches in production code.
 * Production runs pass no hook.
 *
 *     Database.executeBatch(new PartyPublicationMigrationBatch(new PartyPublicationFieldTracker(), myHook), 200);
 *
 * A hook may change the candidate record. It must not run SOQL or DML (the engine is bulk-safe because it
 * doesn't), and it must not throw. Not part of the supported extension surface (design §10.3).
 */
public interface PubMigInsertHook {

    /** Called once per new Publication, with the creator row's Id. */
    void beforePublicationInsert(Id sourceId, Publication candidate);

    /** Called once per new PublicationContributor, with the first source row that needs it. */
    void beforeContributorInsert(Id sourceId, PublicationContributor candidate);
}
