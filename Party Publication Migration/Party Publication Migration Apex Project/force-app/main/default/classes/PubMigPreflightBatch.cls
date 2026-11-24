/**
 * Pre-flight report (design §3.4, §9, D7). READ-ONLY: creates and updates nothing.
 *
 * Groups PartyPublication rows by normalized Title + PublicationDate and emails the running user a CSV of
 * groups the migration would split into more than one Publication:
 *
 *   MIXED_IDENTIFIER  some rows have a PublicationIdentifier and some don't (placeholders count as "don't").
 *                     They get different group keys, so they become separate Publications.
 *                     Fix: fill in the missing identifier before migrating.
 *   MULTIPLE_KEYS     same Title + Date, but the rows would still get more than one group key (different
 *                     identifiers, or different journal spelling). Often correct (e.g. an erratum with its
 *                     own DOI); review only.
 *
 * Rows without PublicationDate are skipped (the migration fails them with MISSING_PUBLICATION_DATE).
 * Rows the customer set to Excluded are skipped too. A group is reported only if at least one of its rows
 * is still to be migrated (status blank or Failed): groups that are fully Migrated are history, but Migrated
 * rows still count toward a group, because a new row without an identifier next to Migrated rows with one
 * would create a second Publication. Before the tracking fields / log object exist, every row counts.
 *
 * Run (Anonymous Apex):  PubMigPreflightBatch.run();
 */
public without sharing class PubMigPreflightBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final String MIXED_IDENTIFIER = 'MIXED_IDENTIFIER';
    public static final String MULTIPLE_KEYS = 'MULTIPLE_KEYS';
    public static final Integer MAX_FINDINGS = 2000;
    private static final Integer MAX_IDS_PER_FINDING = 20;

    public class Bucket {
        public String title;
        public Date publicationDate;
        public Integer withIdentifier = 0;
        public Integer withoutIdentifier = 0;
        public Integer rowsToMigrate = 0;
        public Set<String> groupKeys = new Set<String>();
        public List<Id> sampleIds = new List<Id>();
    }

    public class Finding {
        public String code;
        public Bucket bucket;
        public Finding(String code, Bucket bucket) {
            this.code = code;
            this.bucket = bucket;
        }
    }

    // Buckets for the date currently being read. Rows arrive ordered by PublicationDate, so when the date
    // changes every bucket of the previous date is complete and can be evaluated (keeps heap bounded).
    private Date currentDate;
    private Map<String, Bucket> currentBuckets = new Map<String, Bucket>();
    // Where Migrated / Excluded rows are recorded (fields on PartyPublication or the log object). A custom
    // tracker that doesn't implement PubMigStatusReader counts as "no row has a status".
    private final PubMigStatusReader statusReader;
    @TestVisible
    private List<Finding> findings = new List<Finding>();
    @TestVisible
    private Integer findingsTotal = 0;
    @TestVisible
    private Integer rowsRead = 0;

    public PubMigPreflightBatch() {
        this(PubMigConfig.tracker());
    }

    public PubMigPreflightBatch(PubMigTracker tracker) {
        this.statusReader = tracker instanceof PubMigStatusReader ? (PubMigStatusReader) tracker : null;
    }

    public static Id run() {
        return Database.executeBatch(new PubMigPreflightBatch(), 2000);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Title, PublicationDate, PublishedOn, PublicationIdentifier
            FROM PartyPublication
            WHERE PublicationDate != null
            ORDER BY PublicationDate, Id
        ]);
    }

    public void execute(Database.BatchableContext bc, List<PartyPublication> scope) {
        Map<Id, String> statusById = statusReader == null ? new Map<Id, String>() : statusReader.statusBySource(new Map<Id, PartyPublication>(scope).keySet());
        for (PartyPublication row : scope) {
            String status = statusById.get(row.Id);
            if (status == PubMigOutcome.STATUS_EXCLUDED) {
                continue; // never migrated, so it can't split a paper
            }
            rowsRead++;
            if (row.PublicationDate != currentDate) {
                flush();
                currentDate = row.PublicationDate;
            }
            String titleKey = PubMigRules.norm(row.Title);
            Bucket b = currentBuckets.get(titleKey);
            if (b == null) {
                b = new Bucket();
                b.title = row.Title;
                b.publicationDate = row.PublicationDate;
                currentBuckets.put(titleKey, b);
            }
            if (status != PubMigOutcome.STATUS_MIGRATED) {
                b.rowsToMigrate++;
            }
            if (PubMigRules.routeIdentifier(row.PublicationIdentifier) == null) {
                b.withoutIdentifier++;
            } else {
                b.withIdentifier++;
            }
            b.groupKeys.add(PubMigRules.rawGroupKey(row.PublicationIdentifier, row.Title, row.PublicationDate, row.PublishedOn));
            if (b.sampleIds.size() < MAX_IDS_PER_FINDING) {
                b.sampleIds.add(row.Id);
            }
        }
    }

    @TestVisible
    private void flush() {
        for (Bucket b : currentBuckets.values()) {
            if (b.rowsToMigrate == 0) {
                continue; // nothing left to migrate in this group
            }
            String code = null;
            if (b.withIdentifier > 0 && b.withoutIdentifier > 0) {
                code = MIXED_IDENTIFIER;
            } else if (b.groupKeys.size() > 1) {
                code = MULTIPLE_KEYS;
            }
            if (code == null) {
                continue;
            }
            findingsTotal++;
            if (findings.size() < MAX_FINDINGS) {
                b.groupKeys = null; // not needed in the report; frees heap
                findings.add(new Finding(code, b));
            }
        }
        currentBuckets.clear();
    }

    public void finish(Database.BatchableContext bc) {
        flush();
        String summary = 'Publication migration pre-flight report' + (bc == null ? '' : ' (job ' + bc.getJobId() + ')') + '\n\n' +
            'Rows read (with Publication Date): ' + rowsRead + '\n' +
            'Groups flagged: ' + findingsTotal + (findingsTotal > findings.size() ? ' (first ' + findings.size() + ' attached)' : '') + '\n\n' +
            MIXED_IDENTIFIER + ': same Title + Date, but only some rows have a Publication Identifier. These would become\n' +
            '  separate Publications. Fill in the missing identifier on the listed records before migrating.\n' +
            MULTIPLE_KEYS + ': same Title + Date, but different identifiers or journal. Review only; often correct.\n\n' +
            'Groups whose records are all Migrated or Excluded are not reported.\n' +
            'Nothing was created or changed by this report.';
        System.debug(LoggingLevel.INFO, summary);
        try {
            Messaging.EmailFileAttachment csv = new Messaging.EmailFileAttachment();
            csv.setFileName('publication-migration-preflight.csv');
            csv.setContentType('text/csv');
            csv.setBody(Blob.valueOf(toCsv()));
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setTargetObjectId(UserInfo.getUserId());
            m.setSaveAsActivity(false);
            m.setSubject('Publication migration pre-flight: ' + findingsTotal + ' group(s) to review');
            m.setPlainTextBody(summary);
            m.setFileAttachments(new List<Messaging.EmailFileAttachment>{ csv });
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Pre-flight email not sent: ' + e.getMessage() + '\n' + toCsv());
        }
    }

    @TestVisible
    private String toCsv() {
        List<String> lines = new List<String>{ 'Code,Title,PublicationDate,RowsWithIdentifier,RowsWithoutIdentifier,RecordIds' };
        for (Finding f : findings) {
            lines.add(String.join(new List<String>{
                f.code,
                csvEscape(f.bucket.title),
                String.valueOf(f.bucket.publicationDate),
                String.valueOf(f.bucket.withIdentifier),
                String.valueOf(f.bucket.withoutIdentifier),
                csvEscape(String.join(f.bucket.sampleIds, ' '))
            }, ','));
        }
        return String.join(lines, '\n');
    }

    /** Quotes the value and defuses spreadsheet formulas: a leading = + - @ tab or CR gets a leading apostrophe. */
    @TestVisible
    private static String csvEscape(String s) {
        if (s == null) {
            return '';
        }
        String value = s;
        if (value.length() > 0 && '=+-@\t\r'.contains(value.substring(0, 1))) {
            value = '\'' + value;
        }
        return '"' + value.replace('"', '""') + '"';
    }
}
