/**
 * Result of processing one PartyPublication row in one run (or, as `previous`, its state before the run).
 */
public inherited sharing class PubMigOutcome {

    public static final String STATUS_MIGRATED = 'Migrated';
    public static final String STATUS_FAILED = 'Failed';
    public static final String STATUS_EXCLUDED = 'Excluded';

    public Id sourceId;
    public String status;
    public String errorCode;
    public String message;
    public String groupKey;
    public Id contributorId;
    /** Not persisted by the default tracker; used for compensation and the summary. */
    public Id publicationId;
    /** State before this run, as returned by PubMigTracker.eligible(). Null if unknown. */
    public PubMigOutcome previous;

    public List<String> warningCodes = new List<String>();
    private List<String> warningMessages = new List<String>();

    public PubMigOutcome(Id sourceId) {
        this.sourceId = sourceId;
    }

    public void warn(String code, String text) {
        warningCodes.add(code);
        warningMessages.add(code + ': ' + text);
    }

    public void fail(String code, String text) {
        status = STATUS_FAILED;
        errorCode = code;
        message = text;
        contributorId = null;
        publicationId = null;
        warningCodes.clear();
        warningMessages.clear();
    }

    public void migrate(Id contributorId, Id publicationId) {
        status = STATUS_MIGRATED;
        errorCode = null;
        this.contributorId = contributorId;
        this.publicationId = publicationId;
        message = warningMessages.isEmpty() ? null : String.join(warningMessages, '\n');
    }

    public Boolean isMigrated() {
        return status == STATUS_MIGRATED;
    }

    public Boolean isFailed() {
        return status == STATUS_FAILED;
    }
}
