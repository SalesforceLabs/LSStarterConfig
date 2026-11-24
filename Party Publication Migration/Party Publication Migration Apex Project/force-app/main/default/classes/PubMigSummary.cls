/**
 * Run counters (kept across chunks by Database.Stateful) and the summary email (design §7.3).
 */
public inherited sharing class PubMigSummary {

    public static final Integer MAX_LISTED = 200;

    public List<String> abortReasons = new List<String>();
    public Integer processed = 0;
    public Integer migrated = 0;
    public Integer failed = 0;
    public Integer withWarnings = 0;
    public Integer publicationsCreated = 0;
    public Integer contributorsCreated = 0;
    public Integer contributorsReused = 0;
    public Integer publicationsCompensated = 0;
    public Integer contributorsCompensated = 0;
    public Integer notRecordedTotal = 0;
    public Map<String, Integer> failedByCode = new Map<String, Integer>();
    public Map<String, Integer> warningsByCode = new Map<String, Integer>();
    public List<String> notRecorded = new List<String>();
    public List<String> compensationFailures = new List<String>();
    /** Chunks whose exception was caught; their changes were rolled back (PartyPublicationMigrationBatch.execute). */
    public Integer chunksFailed = 0;
    public Integer rowsInFailedChunks = 0;
    public List<String> chunkErrors = new List<String>();
    /** AsyncApexJob.NumberOfErrors: chunks that ended with an uncaught exception (for example a governor limit). */
    public Integer jobErrors = 0;
    public String jobStatusDetail;

    public Boolean isAborted() {
        return !abortReasons.isEmpty();
    }

    /** True when some rows were skipped because a whole chunk failed, so a "clean" count would be misleading. */
    public Boolean hasChunkProblems() {
        return chunksFailed > 0 || jobErrors > 0;
    }

    public void addChunkFailure(Integer rowCount, Exception e) {
        chunksFailed++;
        rowsInFailedChunks += rowCount;
        if (chunkErrors.size() < MAX_LISTED) {
            chunkErrors.add(e.getTypeName() + ': ' + e.getMessage());
        }
    }

    public void add(PubMigEngine.ChunkResult r) {
        processed += r.outcomes.size();
        publicationsCreated += r.publicationsCreated;
        contributorsCreated += r.contributorsCreated;
        contributorsReused += r.contributorsReused;
        publicationsCompensated += r.publicationsCompensated;
        contributorsCompensated += r.contributorsCompensated;
        for (PubMigOutcome o : r.outcomes) {
            if (r.notRecorded.containsKey(o.sourceId)) {
                notRecordedTotal++;
                if (notRecorded.size() < MAX_LISTED) {
                    notRecorded.add(o.sourceId + ': ' + r.notRecorded.get(o.sourceId));
                }
                continue;
            }
            if (o.isMigrated()) {
                migrated++;
                if (!o.warningCodes.isEmpty()) {
                    withWarnings++;
                }
                for (String code : o.warningCodes) {
                    increment(warningsByCode, code);
                }
            } else {
                failed++;
                increment(failedByCode, o.errorCode);
            }
        }
        for (String f : r.compensationFailures) {
            if (compensationFailures.size() < MAX_LISTED) {
                compensationFailures.add(f);
            }
        }
    }

    private static void increment(Map<String, Integer> m, String key) {
        m.put(key, (m.containsKey(key) ? m.get(key) : 0) + 1);
    }

    public String render(Id jobId) {
        List<String> l = new List<String>();
        l.add('PartyPublication → Publication migration' + (jobId == null ? '' : ' (job ' + jobId + ')'));
        l.add('');
        if (isAborted()) {
            l.add('THE RUN DID NOT START. Nothing was created or updated. Fix the following, then rerun:');
            for (String reason : abortReasons) {
                l.add('  - ' + reason);
            }
            return String.join(l, '\n');
        }
        l.add('Records processed:          ' + processed);
        l.add('  Migrated:                 ' + migrated + ' (with warnings: ' + withWarnings + ')');
        l.add('  Failed:                   ' + failed);
        for (String code : failedByCode.keySet()) {
            l.add('    ' + code + ': ' + failedByCode.get(code));
        }
        for (String code : warningsByCode.keySet()) {
            l.add('  Warning ' + code + ': ' + warningsByCode.get(code));
        }
        l.add('Publications created:       ' + publicationsCreated + ' (removed again by compensation: ' + publicationsCompensated + ')');
        l.add('Contributors created:       ' + contributorsCreated + ' (reused: ' + contributorsReused + ', removed by compensation: ' + contributorsCompensated + ')');
        if (hasChunkProblems()) {
            l.add('');
            l.add('ATTENTION: THE RUN DID NOT COMPLETE. The counts above do not include every record.');
            if (chunksFailed > 0) {
                l.add('  ' + chunksFailed + ' chunk(s) (' + rowsInFailedChunks + ' records) threw an exception. Their changes were rolled back,');
                l.add('  so nothing was created for them and they have no status. Fix the cause, then rerun:');
                for (String s : chunkErrors) {
                    l.add('    - ' + s);
                }
            }
            if (jobErrors > 0) {
                l.add('  ' + jobErrors + ' chunk(s) ended with an uncaught exception (for example a governor limit)' +
                    (String.isBlank(jobStatusDetail) ? '.' : ': ' + jobStatusDetail));
                l.add('  Rerun with a smaller batch size, for example Database.executeBatch(new PartyPublicationMigrationBatch(), 50).');
            }
        }
        if (failed > 0) {
            l.add('');
            l.add('Failed records: open the "Publication Migration - Failed" list view on PartyPublication. Each record\'s');
            l.add('Migration Message says what to fix. Fixed records are retried automatically on the next run.');
        }
        if (notRecordedTotal > 0) {
            l.add('');
            l.add('Records whose migration status could NOT be saved (' + notRecordedTotal + '). Anything created for them was removed,');
            l.add('and they will be retried on the next run. Usually a validation rule, trigger or flow on PartyPublication blocked the update:');
            for (String s : notRecorded) {
                l.add('  - ' + s);
            }
        }
        if (!compensationFailures.isEmpty()) {
            l.add('');
            l.add('ACTION NEEDED: these records were created by this run but could not be removed after a failure.');
            l.add('Delete them manually before the next run, or the next run will create duplicates:');
            for (String s : compensationFailures) {
                l.add('  - ' + s);
            }
        }
        return String.join(l, '\n');
    }

    /** Emails the running user. Never throws: a mail problem must not fail the job. */
    public void send(Id jobId) {
        String body = render(jobId);
        System.debug(LoggingLevel.INFO, body);
        try {
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setTargetObjectId(UserInfo.getUserId());
            m.setSaveAsActivity(false);
            m.setSubject(isAborted()
                ? 'Publication migration did not start'
                : (hasChunkProblems() ? 'Publication migration INCOMPLETE: ' : 'Publication migration: ') +
                    migrated + ' migrated, ' + failed + ' failed');
            m.setPlainTextBody(body);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Publication migration summary email not sent: ' + e.getMessage());
        }
    }
}
