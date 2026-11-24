/**
 * THE ONE SWITCH: where does the migration keep its progress (Migrated / Failed / Excluded per record)?
 *
 *   USE_LOG_OBJECT = false  (default) PATH A: five custom fields on PartyPublication.
 *                           The migration UPDATES PartyPublication records (setup guide Step 1, Path A).
 *   USE_LOG_OBJECT = true             PATH B: a separate custom object, PublicationMigrationLog__c.
 *                           PartyPublication is only READ: no field, no update, no trigger, no change event.
 *                           (setup guide Step 1, Path B)
 *
 * Edit the value below ONCE, before you deploy the classes (setup guide Step 3), and don't change it
 * between runs: each path keeps its own record of what was already migrated, so switching paths in the
 * middle of a migration would create duplicate Publications.
 *
 * The customer creates the fields (Path A) or the object (Path B). The migration checks for them in start()
 * and stops with a list of whatever is missing.
 */
public inherited sharing class PubMigConfig {

    public static final Boolean USE_LOG_OBJECT = false;

    /** The tracker used by PartyPublicationMigrationBatch() and PubMigPreflightBatch(). */
    public static PubMigTracker tracker() {
        if (USE_LOG_OBJECT) {
            return new PubMigLogTracker();
        }
        return new PartyPublicationFieldTracker();
    }
}
