@IsTest
private class PubMigPreflightBatchTest {

    private static final Date D1 = Date.newInstance(2020, 3, 1);
    private static final Date D2 = Date.newInstance(2021, 6, 30);

    @TestSetup
    static void data() {
        Id a = PubMigTestData.account().Id;
        PubMigTestData.insertRows(new List<PartyPublication>{
            // MIXED_IDENTIFIER: same paper, one row with a DOI, one without (placeholder counts as without)
            PubMigTestData.row(a, 'Mixed Paper', D1, PubMigTestData.DOI_A),
            PubMigTestData.row(a, 'mixed paper.', D1, 'N/A'),
            // MULTIPLE_KEYS: same Title + Date, two different DOIs
            PubMigTestData.row(a, 'Erratum Paper', D1, '10.5555/one'),
            PubMigTestData.row(a, 'Erratum Paper', D1, '10.5555/two'),
            // fine: same DOI on both rows
            PubMigTestData.row(a, 'Clean Paper', D2, '10.5555/clean'),
            PubMigTestData.row(a, 'Clean Paper', D2, 'https://doi.org/10.5555/clean'),
            // skipped: no date
            PubMigTestData.row(a, 'Undated', null, null)
        });
    }

    @IsTest
    static void flagsMixedAndMultipleKeysInline() {
        PubMigPreflightBatch b = new PubMigPreflightBatch();
        Database.QueryLocatorIterator it = b.start(null).iterator();
        List<PartyPublication> scope = new List<PartyPublication>();
        while (it.hasNext()) {
            scope.add((PartyPublication) it.next());
        }
        // two chunks, split inside the D1 rows, to exercise state kept across chunks
        b.execute(null, new List<PartyPublication>{ scope[0], scope[1], scope[2] });
        b.execute(null, new List<PartyPublication>{ scope[3], scope[4], scope[5] });
        b.finish(null);

        Assert.areEqual(6, b.rowsRead, 'undated row skipped');
        Assert.areEqual(2, b.findingsTotal);
        Map<String, String> codeByTitle = new Map<String, String>();
        for (PubMigPreflightBatch.Finding f : b.findings) {
            codeByTitle.put(PubMigRules.norm(f.bucket.title), f.code);
        }
        Assert.areEqual(PubMigPreflightBatch.MIXED_IDENTIFIER, codeByTitle.get('mixed paper'));
        Assert.areEqual(PubMigPreflightBatch.MULTIPLE_KEYS, codeByTitle.get('erratum paper'));

        String csv = b.toCsv();
        Assert.isTrue(csv.startsWith('Code,Title,PublicationDate'));
        Assert.areEqual(3, csv.split('\n').size(), 'header + 2 findings');
        Assert.areEqual(0, [SELECT COUNT() FROM Publication], 'pre-flight is read-only');
    }

    @IsTest
    static void runsAsRealBatch() {
        Test.startTest();
        Id jobId = PubMigPreflightBatch.run();
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Publication]);
        // Look the job up by the Id run() returned. Counting by class name also counts the BatchApexWorker row
        // Salesforce adds for each batch (and any earlier runs in the org), so the count is not 1.
        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        Assert.areEqual('Completed', job.Status);
        Assert.areEqual(0, job.NumberOfErrors);
    }

    // Code review finding 9: only groups that still have something to migrate are reported
    @IsTest
    static void reportsOnlyGroupsWithRowsLeftToMigrate() {
        Id a = [SELECT Id FROM Account WHERE Name = 'PubMig Test University' LIMIT 1].Id;
        String migrated = PubMigOutcome.STATUS_MIGRATED;
        String excluded = PubMigOutcome.STATUS_EXCLUDED;
        PartyPublication doneA = withStatus(PubMigTestData.row(a, 'Done Paper', D2, '10.5555/done'), migrated);
        PartyPublication doneB = withStatus(PubMigTestData.row(a, 'done paper', D2, null), migrated);
        PartyPublication skipA = withStatus(PubMigTestData.row(a, 'Skipped Paper', D2, '10.5555/skip'), excluded);
        PartyPublication skipB = withStatus(PubMigTestData.row(a, 'Skipped Paper', D2, null), excluded);
        PartyPublication partlyA = withStatus(PubMigTestData.row(a, 'Partly Paper', D2, '10.5555/partly'), migrated);
        PartyPublication partlyB = PubMigTestData.row(a, 'Partly Paper', D2, null); // still to migrate
        PubMigTestData.insertRows(new List<PartyPublication>{ doneA, doneB, skipA, skipB, partlyA, partlyB });

        PubMigPreflightBatch b = new PubMigPreflightBatch();
        Database.QueryLocatorIterator it = b.start(null).iterator();
        List<PartyPublication> scope = new List<PartyPublication>();
        while (it.hasNext()) {
            scope.add((PartyPublication) it.next());
        }
        b.execute(null, scope);
        b.finish(null);

        Map<String, String> codeByTitle = new Map<String, String>();
        for (PubMigPreflightBatch.Finding f : b.findings) {
            codeByTitle.put(PubMigRules.norm(f.bucket.title), f.code);
        }
        Assert.isFalse(codeByTitle.containsKey('done paper'), 'fully Migrated group is history');
        Assert.isFalse(codeByTitle.containsKey('skipped paper'), 'Excluded rows are never migrated');
        Assert.areEqual(PubMigPreflightBatch.MIXED_IDENTIFIER, codeByTitle.get('partly paper'),
            'a new row without an identifier next to Migrated rows with one would create a second Publication');
        Assert.isTrue([SELECT COUNT() FROM PartyPublication WHERE Title = 'Skipped Paper'] == 2, 'the report changes nothing');
    }

    // Code review finding 9: titles are untrusted text that ends up in a CSV opened in a spreadsheet
    @IsTest
    static void csvDefusesSpreadsheetFormulas() {
        Assert.areEqual('"\'=HYPERLINK(""http://x"",""y"")"', PubMigPreflightBatch.csvEscape('=HYPERLINK("http://x","y")'));
        Assert.areEqual('"\'+1"', PubMigPreflightBatch.csvEscape('+1'));
        Assert.areEqual('"\'-1"', PubMigPreflightBatch.csvEscape('-1'));
        Assert.areEqual('"\'@SUM(A1)"', PubMigPreflightBatch.csvEscape('@SUM(A1)'));
        Assert.areEqual('"Plain, title"', PubMigPreflightBatch.csvEscape('Plain, title'));
        Assert.areEqual('', PubMigPreflightBatch.csvEscape(null));

        PubMigPreflightBatch.Bucket bk = new PubMigPreflightBatch.Bucket();
        bk.title = '=cmd';
        bk.publicationDate = D1;
        PubMigPreflightBatch b = new PubMigPreflightBatch();
        b.findings.add(new PubMigPreflightBatch.Finding(PubMigPreflightBatch.MIXED_IDENTIFIER, bk));
        Assert.isTrue(b.toCsv().contains('"\'=cmd"'), b.toCsv());
    }

    private static PartyPublication withStatus(PartyPublication r, String status) {
        r.put(PartyPublicationFieldTracker.F_STATUS, status);
        return r;
    }
}
