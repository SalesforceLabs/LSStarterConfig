/**
 * End-to-end tests for the PartyPublication → Publication migration (design §11, T1–T22).
 * Requires the §1.1 / §1.2 custom fields to exist in the org (setup guide step 1).
 *
 * Most tests use PubMigTestData.runMigration (start/execute/finish inline) so one test can run
 * several chunks and several runs; realBatchMigrates200Rows uses Database.executeBatch.
 */
@IsTest
private class PartyPublicationMigrationBatchTest {

    private static final Date D1 = Date.newInstance(2020, 3, 1);
    private static final String DOI_A = PubMigTestData.DOI_A;

    @TestSetup
    static void parties() {
        PubMigTestData.account();
        // The Contributor domain is configurable. If this org's Contributor can't be an Individual / HealthcareProvider,
        // a second Account stands in, so the tests still exercise "different party, same paper".
        if (PubMigTestData.contributorAccepts('Individual')) {
            PubMigTestData.individual();
        } else {
            insert new Account(Name = 'PubMig Stand-in Individual');
        }
        if (PubMigTestData.contributorAccepts('HealthcareProvider')) {
            PubMigTestData.healthcareProvider();
        } else {
            insert new Account(Name = 'PubMig Stand-in Provider');
        }
    }

    private static Id acct() {
        return [SELECT Id FROM Account WHERE Name = 'PubMig Test University' LIMIT 1].Id;
    }

    private static Id indiv() {
        if (!PubMigTestData.contributorAccepts('Individual')) {
            return [SELECT Id FROM Account WHERE Name = 'PubMig Stand-in Individual' LIMIT 1].Id;
        }
        return [SELECT Id FROM Individual WHERE LastName = 'PubMigIndividual' LIMIT 1].Id;
    }

    private static Id hcp() {
        if (!PubMigTestData.contributorAccepts('HealthcareProvider')) {
            return [SELECT Id FROM Account WHERE Name = 'PubMig Stand-in Provider' LIMIT 1].Id;
        }
        return [SELECT Id FROM HealthcareProvider WHERE Name = 'PubMig Test Provider' LIMIT 1].Id;
    }

    // ==================================================================== setup verification

    @IsTest
    static void prerequisitesPassInThisOrg() {
        List<String> problems = PubMigGuard.problems(new PartyPublicationFieldTracker(), null);
        Assert.isTrue(problems.isEmpty(), 'Setup incomplete:\n' + String.join(problems, '\n'));
    }

    // ==================================================================== grouping

    // T1: 3 rows, same DOI (3 spellings), HCP + Individual + Account → 1 Publication, 3 Contributors
    @IsTest
    static void sameDoiThreePartyTypesOnePublication() {
        List<PartyPublication> rows = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(hcp(), 'Paper', D1, 'https://doi.org/' + DOI_A),
            PubMigTestData.row(indiv(), 'Paper', D1, DOI_A),
            PubMigTestData.row(acct(), 'Paper', D1, 'doi:' + DOI_A.toUpperCase())
        });

        PubMigSummary s = PubMigTestData.runMigration();

        Assert.areEqual(1, PubMigTestData.publicationCount());
        Assert.areEqual(3, PubMigTestData.contributorCount());
        Assert.areEqual(3, s.migrated);
        Assert.areEqual(1, s.publicationsCreated);
        Map<Id, SObject> st = PubMigTestData.state();
        Id pubId = PubMigTestData.publicationId(st.get(rows[0].Id));
        for (PartyPublication r : rows) {
            Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(r.Id)));
            Assert.areEqual(pubId, PubMigTestData.publicationId(st.get(r.Id)));
            Assert.areEqual(64, ((String) st.get(r.Id).get(PartyPublicationFieldTracker.F_KEY)).length());
        }
        Set<Id> contributorParties = new Set<Id>();
        for (PublicationContributor c : [SELECT ContributorId, IsEqualContribution FROM PublicationContributor]) {
            contributorParties.add(c.ContributorId);
            Assert.isFalse(c.IsEqualContribution);
        }
        Assert.areEqual(new Set<Id>{ hcp(), indiv(), acct() }, contributorParties);
        SObject pub = Database.query('SELECT Name, Title, PublishedDate, OriginalSourceName, ' + PubMigRules.FIELD_DOI + ' FROM Publication');
        Assert.areEqual(DOI_A, pub.get(PubMigRules.FIELD_DOI));
        Assert.areEqual('Paper', pub.get('Name'));
        Assert.areEqual(D1, pub.get('PublishedDate'));
        Assert.areEqual('Nature', pub.get('OriginalSourceName'));
    }

    // T2: no identifier → Title + Date + Journal, ignoring case/punctuation/spacing
    @IsTest
    static void fallbackKeyGroupsByTitleDateJournal() {
        PartyPublication a = PubMigTestData.row(acct(), 'Deep Learning: A Review', D1, null);
        PartyPublication b = PubMigTestData.row(indiv(), 'deep learning  a review.', D1, 'N/A');
        b.PublishedOn = 'NATURE.';
        PartyPublication otherJournal = PubMigTestData.row(hcp(), 'Deep Learning: A Review', D1, null);
        otherJournal.PublishedOn = 'Science';
        PubMigTestData.insertRows(new List<PartyPublication>{ a, b, otherJournal });

        PubMigTestData.runMigration();

        Assert.areEqual(2, PubMigTestData.publicationCount());
        Map<Id, SObject> st = PubMigTestData.state();
        Assert.areEqual(PubMigTestData.publicationId(st.get(a.Id)), PubMigTestData.publicationId(st.get(b.Id)));
        Assert.areNotEqual(PubMigTestData.publicationId(st.get(a.Id)), PubMigTestData.publicationId(st.get(otherJournal.Id)));
    }

    // T3: group split across chunks → 1 Publication from the earliest row; later rows warn
    @IsTest
    static void groupSplitAcrossChunksReusesPublication() {
        List<PartyPublication> rows = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Original Title', D1, DOI_A),
            PubMigTestData.row(indiv(), 'Original title (preprint)', D1, DOI_A),
            PubMigTestData.row(hcp(), 'Original Title', D1, DOI_A)
        });

        PubMigSummary s = PubMigTestData.runMigration(null, 1);

        Assert.areEqual(1, PubMigTestData.publicationCount());
        Assert.areEqual(3, PubMigTestData.contributorCount());
        Assert.areEqual(1, s.publicationsCreated);
        Assert.areEqual('Original Title', [SELECT Title FROM Publication].Title);
        Map<Id, SObject> st = PubMigTestData.state();
        Assert.isTrue(PubMigTestData.message(st.get(rows[1].Id)).contains(PubMigEngine.PAPER_FIELD_CONFLICT));
        Assert.isTrue(PubMigTestData.message(st.get(rows[1].Id)).contains('Title'));
        Assert.isNull(PubMigTestData.message(st.get(rows[2].Id)), 'identical paper fields → no warning');
    }

    // T20: placeholder identifiers don't merge unrelated papers
    @IsTest
    static void placeholderIdentifiersDoNotMerge() {
        PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper One', D1, 'N/A'),
            PubMigTestData.row(indiv(), 'Paper Two', D1, 'n/a')
        });

        PubMigTestData.runMigration();

        Assert.areEqual(2, PubMigTestData.publicationCount());
        for (SObject p : Database.query('SELECT ' + PubMigRules.FIELD_DOI + ', ' + PubMigRules.FIELD_EXTERNAL_ID + ' FROM Publication')) {
            Assert.isNull(p.get(PubMigRules.FIELD_DOI));
            Assert.isNull(p.get(PubMigRules.FIELD_EXTERNAL_ID));
        }
    }

    // ==================================================================== contributors

    // T11: same party twice on one paper (same role) → 1 Contributor; in one chunk and across chunks
    @IsTest
    static void samePartyTwiceSharesOneContributor() {
        List<PartyPublication> rows = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A),
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A),
            PubMigTestData.row(acct(), 'Other', D1, '10.5555/other'),
            PubMigTestData.row(acct(), 'Other', D1, '10.5555/other')
        });

        PubMigTestData.runMigration(null, 3); // rows 0-1 in one chunk; rows 2 / 3 in different chunks

        Assert.areEqual(2, PubMigTestData.publicationCount());
        Assert.areEqual(2, PubMigTestData.contributorCount());
        Map<Id, SObject> st = PubMigTestData.state();
        Assert.areEqual(PubMigTestData.contributorId(st.get(rows[0].Id)), PubMigTestData.contributorId(st.get(rows[1].Id)));
        Assert.areEqual(PubMigTestData.contributorId(st.get(rows[2].Id)), PubMigTestData.contributorId(st.get(rows[3].Id)));
    }

    // T12: sibling with different paper values → Migrated + PAPER_FIELD_CONFLICT; Publication unchanged
    @IsTest
    static void paperFieldConflictWarnsAndKeepsCreatorValues() {
        PartyPublication a = PubMigTestData.row(acct(), 'Paper', D1, DOI_A);
        a.Summary = 'Original abstract';
        PartyPublication b = PubMigTestData.row(indiv(), 'Paper', D1, DOI_A);
        b.Summary = 'Different abstract';
        PubMigTestData.insertRows(new List<PartyPublication>{ a, b });

        PubMigSummary s = PubMigTestData.runMigration();

        Map<Id, SObject> st = PubMigTestData.state();
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(b.Id)));
        Assert.isNull(PubMigTestData.code(st.get(b.Id)), 'warnings are not error codes');
        Assert.isTrue(PubMigTestData.message(st.get(b.Id)).startsWith(PubMigEngine.PAPER_FIELD_CONFLICT));
        Assert.isTrue(PubMigTestData.message(st.get(b.Id)).contains('AbstractText'));
        Assert.areEqual('Original abstract', [SELECT AbstractText FROM Publication].AbstractText);
        Assert.areEqual(1, s.warningsByCode.get(PubMigEngine.PAPER_FIELD_CONFLICT));
        Assert.areEqual(1, s.withWarnings);
    }

    // ==================================================================== failures and retries

    // T5 + T6: missing date → Failed, nothing created; fix → Migrated
    @IsTest
    static void missingDateFailsThenMigratesAfterFix() {
        PartyPublication r = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', null, null)
        })[0];

        PubMigSummary s = PubMigTestData.runMigration();

        SObject row = PubMigTestData.state().get(r.Id);
        Assert.areEqual(PubMigOutcome.STATUS_FAILED, PubMigTestData.status(row));
        Assert.areEqual(PubMigEngine.MISSING_PUBLICATION_DATE, PubMigTestData.code(row));
        Assert.areEqual(PubMigEngine.MSG_MISSING_DATE, PubMigTestData.message(row));
        Assert.isNull(row.get(PartyPublicationFieldTracker.F_KEY), 'no identifier and no date → no key');
        Assert.areEqual(0, PubMigTestData.publicationCount());
        Assert.areEqual(0, PubMigTestData.contributorCount());
        Assert.areEqual(1, s.failedByCode.get(PubMigEngine.MISSING_PUBLICATION_DATE));

        r.PublicationDate = D1; // customer fix
        update r;
        PubMigTestData.runMigration();

        row = PubMigTestData.state().get(r.Id);
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(row));
        Assert.isNull(PubMigTestData.code(row));
        Assert.isNull(PubMigTestData.message(row));
        Assert.areEqual(1, PubMigTestData.publicationCount());
    }

    // T18 + T19: dated + undated sibling; fix → attaches to the same Publication, date not changed
    @IsTest
    static void undatedSiblingFailsThenJoinsExistingPublication() {
        PartyPublication a = PubMigTestData.row(acct(), 'Paper', D1, DOI_A);
        PartyPublication b = PubMigTestData.row(indiv(), 'Paper', null, DOI_A);
        PubMigTestData.insertRows(new List<PartyPublication>{ a, b });

        PubMigTestData.runMigration();

        Map<Id, SObject> st = PubMigTestData.state();
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(a.Id)));
        Assert.areEqual(PubMigEngine.MISSING_PUBLICATION_DATE, PubMigTestData.code(st.get(b.Id)));
        Assert.areEqual(1, PubMigTestData.publicationCount());
        Assert.areEqual(1, PubMigTestData.contributorCount());

        b.PublicationDate = D1.addDays(10);
        update b;
        PubMigTestData.runMigration();

        st = PubMigTestData.state();
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(b.Id)));
        Assert.areEqual(PubMigTestData.publicationId(st.get(a.Id)), PubMigTestData.publicationId(st.get(b.Id)));
        Assert.areEqual(1, PubMigTestData.publicationCount());
        Assert.areEqual(2, PubMigTestData.contributorCount());
        Assert.areEqual(D1, [SELECT PublishedDate FROM Publication].PublishedDate);
        Assert.isTrue(PubMigTestData.message(st.get(b.Id)).contains('PublishedDate'));
    }

    // T7: rerun with no changes → no inserts, no source updates (I1, I7)
    @IsTest
    static void rerunWithoutChangesTouchesNothing() {
        PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A),
            PubMigTestData.row(indiv(), 'No date', null, null)
        });
        PubMigTestData.runMigration();
        Integer pubs = PubMigTestData.publicationCount();
        Integer contributors = PubMigTestData.contributorCount();
        PartyPublicationFieldTracker.rowsUpdated = 0;

        PubMigSummary s = PubMigTestData.runMigration();

        Assert.areEqual(1, s.processed, 'only the Failed row is reconsidered');
        Assert.areEqual(0, PartyPublicationFieldTracker.rowsUpdated, 'same failure → row not rewritten');
        Assert.areEqual(pubs, PubMigTestData.publicationCount());
        Assert.areEqual(contributors, PubMigTestData.contributorCount());
    }

    // T9a: Publication insert fails (e.g. Status value missing in target) → whole group fails; retry works
    @IsTest
    static void publicationInsertFailureFailsGroupThenRetries() {
        List<PartyPublication> rows = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A),
            PubMigTestData.row(indiv(), 'Paper', D1, DOI_A),
            PubMigTestData.row(hcp(), 'Unrelated', D1, '10.5555/ok')
        });
        BreakHook hook = new BreakHook();
        hook.breakPublicationFor.add(rows[0].Id);

        PubMigSummary s = PubMigTestData.runMigration(null, PartyPublicationMigrationBatch.DEFAULT_BATCH_SIZE, hook);

        Map<Id, SObject> st = PubMigTestData.state();
        for (Integer i = 0; i < 2; i++) {
            Assert.areEqual(PubMigEngine.PUBLICATION_CREATE_FAILED, PubMigTestData.code(st.get(rows[i].Id)));
            Assert.isTrue(PubMigTestData.message(st.get(rows[i].Id)).startsWith('Couldn\'t create Publication: '));
        }
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(rows[2].Id)), 'one bad group must not fail the chunk (R9)');
        Assert.areEqual(1, PubMigTestData.publicationCount());
        Assert.areEqual(2, s.failed);

        hook.breakPublicationFor.clear(); // customer fix
        PubMigTestData.runMigration();

        st = PubMigTestData.state();
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(rows[0].Id)));
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(rows[1].Id)));
        Assert.areEqual(2, PubMigTestData.publicationCount());
        Assert.areEqual(3, PubMigTestData.contributorCount());
    }

    // T9b: only contributor of a new Publication fails (e.g. PartyRoleType missing) → Publication compensated
    @IsTest
    static void contributorFailureCompensatesUnlinkedPublication() {
        PartyPublication r = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A)
        })[0];
        BreakHook hook = new BreakHook();
        hook.breakContributorFor.add(r.Id);

        PubMigSummary s = PubMigTestData.runMigration(null, PartyPublicationMigrationBatch.DEFAULT_BATCH_SIZE, hook);

        Assert.areEqual(PubMigEngine.CONTRIBUTOR_CREATE_FAILED, PubMigTestData.code(PubMigTestData.state().get(r.Id)));
        Assert.areEqual(0, PubMigTestData.publicationCount(), 'orphan Publication must be deleted');
        Assert.areEqual(1, s.publicationsCreated);
        Assert.areEqual(1, s.publicationsCompensated);

        hook.breakContributorFor.clear();
        PubMigTestData.runMigration();

        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(PubMigTestData.state().get(r.Id)));
        Assert.areEqual(1, PubMigTestData.publicationCount(), 'exactly one Publication after the retry');
    }

    // T9b': contributor of a sibling fails → Publication kept for the migrated row; retry attaches
    @IsTest
    static void contributorFailureKeepsPublicationUsedBySibling() {
        List<PartyPublication> rows = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A),
            PubMigTestData.row(indiv(), 'Paper', D1, DOI_A)
        });
        BreakHook hook = new BreakHook();
        hook.breakContributorFor.add(rows[1].Id);

        PubMigTestData.runMigration(null, PartyPublicationMigrationBatch.DEFAULT_BATCH_SIZE, hook);

        Map<Id, SObject> st = PubMigTestData.state();
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(rows[0].Id)));
        Assert.areEqual(PubMigEngine.CONTRIBUTOR_CREATE_FAILED, PubMigTestData.code(st.get(rows[1].Id)));
        Assert.areEqual(1, PubMigTestData.publicationCount());
        Assert.areEqual(1, PubMigTestData.contributorCount());

        hook.breakContributorFor.clear();
        PubMigTestData.runMigration();

        st = PubMigTestData.state();
        Assert.areEqual(PubMigTestData.publicationId(st.get(rows[0].Id)), PubMigTestData.publicationId(st.get(rows[1].Id)));
        Assert.areEqual(1, PubMigTestData.publicationCount());
        Assert.areEqual(2, PubMigTestData.contributorCount());
    }

    // T10: status write blocked (e.g. validation rule) → that row's new records are deleted; listed in summary
    @IsTest
    static void unrecordedOutcomeIsCompensated() {
        List<PartyPublication> rows = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A),           // A: creator, recorded
            PubMigTestData.row(indiv(), 'Paper', D1, DOI_A),          // B: sibling, record fails
            PubMigTestData.row(hcp(), 'Alone', D1, '10.5555/alone')   // C: alone, record fails
        });
        FailingRecordTracker tracker = new FailingRecordTracker(new Set<Id>{ rows[1].Id, rows[2].Id });

        PubMigSummary s = PubMigTestData.runMigration(tracker, 200);

        Map<Id, SObject> st = PubMigTestData.state();
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(rows[0].Id)));
        Assert.isNull(PubMigTestData.status(st.get(rows[1].Id)));
        Assert.isNull(PubMigTestData.status(st.get(rows[2].Id)));
        Assert.areEqual(1, PubMigTestData.publicationCount(), 'C\'s Publication deleted; A\'s kept');
        Assert.areEqual(1, PubMigTestData.contributorCount(), 'B\'s and C\'s contributors deleted');
        Assert.areEqual(2, s.notRecordedTotal);
        Assert.areEqual(1, s.migrated);
        Assert.areEqual(1, s.publicationsCompensated);
        Assert.areEqual(1, s.contributorsCompensated); // B's explicitly; C's went with its Publication
        Assert.isTrue(s.render(null).contains('could NOT be saved'));
        Assert.isTrue(s.compensationFailures.isEmpty());

        PubMigTestData.runMigration(); // validation rule removed → default tracker

        st = PubMigTestData.state();
        Assert.areEqual(PubMigTestData.publicationId(st.get(rows[0].Id)), PubMigTestData.publicationId(st.get(rows[1].Id)));
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(rows[2].Id)));
        Assert.areEqual(2, PubMigTestData.publicationCount());
        Assert.areEqual(3, PubMigTestData.contributorCount());
    }

    // ==================================================================== PublicationCategory__c and picklists

    // T13 (present): category and status values are copied
    @IsTest
    static void copiesCategoryAndStatus() {
        String category = PubMigTestData.commonPicklistValue(PartyPublication.PublicationCategory, Publication.SObjectType, PubMigRules.CATEGORY_FIELD);
        String status = PubMigTestData.commonPicklistValue(PartyPublication.Status, Publication.SObjectType, 'Status');
        PartyPublication r = PubMigTestData.row(acct(), 'Paper', D1, DOI_A);
        r.PublicationCategory = category;
        r.Status = status;
        PubMigTestData.insertRows(new List<PartyPublication>{ r });

        PubMigTestData.runMigration();

        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(PubMigTestData.state().get(r.Id)));
        SObject pub = Database.query('SELECT Status, ' + PubMigRules.CATEGORY_FIELD + ' FROM Publication');
        Assert.areEqual(category, pub.get(PubMigRules.CATEGORY_FIELD));
        Assert.areEqual(status, pub.get('Status'));
    }

    // T13 (rejected value): category value missing from a restricted picklist → CUSTOM_FIELD_WRITE_FAILED
    @IsTest
    static void categoryValueRejectedByRestrictedPicklist() {
        Schema.DescribeFieldResult target = Publication.SObjectType.getDescribe().fields.getMap()
            .get(PubMigRules.CATEGORY_FIELD.toLowerCase()).getDescribe();
        if (target.getType() != Schema.DisplayType.PICKLIST || !target.isRestrictedPicklist()) {
            System.debug('Skipped: ' + PubMigRules.CATEGORY_FIELD + ' is not a restricted picklist in this org.');
            return;
        }
        Set<String> targetValues = new Set<String>();
        for (Schema.PicklistEntry e : target.getPicklistValues()) {
            targetValues.add(e.getValue());
        }
        String missing = null;
        for (Schema.PicklistEntry e : PartyPublication.PublicationCategory.getDescribe().getPicklistValues()) {
            if (e.isActive() && !targetValues.contains(e.getValue())) {
                missing = e.getValue();
                break;
            }
        }
        if (missing == null) {
            System.debug('Skipped: every source category value exists on ' + PubMigRules.CATEGORY_FIELD + '.');
            return;
        }
        PartyPublication r = PubMigTestData.row(acct(), 'Paper', D1, DOI_A);
        r.PublicationCategory = missing;
        PubMigTestData.insertRows(new List<PartyPublication>{ r });

        PubMigTestData.runMigration();

        SObject row = PubMigTestData.state().get(r.Id);
        Assert.areEqual(PubMigEngine.CUSTOM_FIELD_WRITE_FAILED, PubMigTestData.code(row));
        Assert.isTrue(PubMigTestData.message(row).contains(missing));
        Assert.areEqual(0, PubMigTestData.publicationCount());
    }

    // ==================================================================== guard

    // T13 (absent) + T21: a prerequisite problem aborts in start() with zero DML
    @IsTest
    static void missingPrerequisiteAbortsWithoutDml() {
        PartyPublication r = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A)
        })[0];
        String problem = 'Required field PartyPublication.' + PartyPublicationFieldTracker.F_STATUS + ' is missing (expected Picklist).';
        PartyPublicationFieldTracker.rowsUpdated = 0;

        PubMigSummary s = PubMigTestData.runMigration(new ProblemTracker(problem), PartyPublicationMigrationBatch.DEFAULT_BATCH_SIZE);

        Assert.isTrue(s.isAborted());
        Assert.areEqual(new List<String>{ problem }, s.abortReasons);
        Assert.areEqual(0, s.processed);
        Assert.areEqual(0, PubMigTestData.publicationCount());
        Assert.areEqual(0, PartyPublicationFieldTracker.rowsUpdated);
        Assert.isNull(PubMigTestData.status(PubMigTestData.state().get(r.Id)));
        Assert.isTrue(s.render(null).contains('THE RUN DID NOT START'));
    }

    // T15: a second run while one is queued aborts
    @IsTest
    static void secondConcurrentRunAborts() {
        Test.startTest();
        Id first = Database.executeBatch(new PartyPublicationMigrationBatch(), 200);
        PubMigSummary second = PubMigTestData.runMigration();
        Test.stopTest();

        Assert.isTrue(second.isAborted());
        Assert.isTrue(String.join(second.abortReasons, ' ').contains(String.valueOf(first)), String.join(second.abortReasons, ' '));
    }

    // ==================================================================== R8 + custom tracker

    // T14: no field other than the 5 migration fields changes on PartyPublication; nothing deleted
    @IsTest
    static void sourceFieldsOtherThanMigrationFieldsUnchanged() {
        PartyPublication a = PubMigTestData.row(acct(), 'Paper', D1, 'https://doi.org/' + DOI_A);
        a.Summary = 'Abstract';
        a.Url = 'https://example.org/a';
        a.CitationCount = 12;
        a.ImpactFactor = 4.5;
        PartyPublication b = PubMigTestData.row(indiv(), 'Paper', D1, DOI_A);
        PartyPublication noDate = PubMigTestData.row(hcp(), 'No date', null, 'PMID 1');
        PubMigTestData.insertRows(new List<PartyPublication>{ a, b, noDate });
        Map<Id, Map<String, Object>> before = snapshot(true);

        PubMigTestData.runMigration();

        Assert.areEqual(before, snapshot(true));
        Assert.areEqual(3, [SELECT COUNT() FROM PartyPublication]);
    }

    // T22: custom tracker → source rows completely untouched; rerun creates no duplicates
    @IsTest
    static void customTrackerLeavesSourceUntouched() {
        PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'Paper', D1, DOI_A),
            PubMigTestData.row(indiv(), 'Paper', D1, DOI_A),
            PubMigTestData.row(hcp(), 'Other', D1, '10.5555/other')
        });
        Map<Id, Map<String, Object>> before = snapshot(false);
        InMemoryTracker tracker = new InMemoryTracker();

        PubMigSummary first = PubMigTestData.runMigration(tracker, 2);
        PubMigSummary second = PubMigTestData.runMigration(tracker, 2);

        Assert.areEqual(3, first.migrated);
        Assert.areEqual(0, second.processed);
        Assert.areEqual(2, PubMigTestData.publicationCount());
        Assert.areEqual(3, PubMigTestData.contributorCount());
        Assert.areEqual(before, snapshot(false), 'not even the migration fields are written');
    }

    // ==================================================================== chunk failure (code review finding 1)

    // An exception after the chunk's DML → rolled back, reported in the summary, job continues, rows retried
    @IsTest
    static void chunkExceptionRollsBackIsReportedAndRetried() {
        List<PartyPublication> rows = PubMigTestData.insertRows(new List<PartyPublication>{
            PubMigTestData.row(acct(), 'First Paper', D1, '10.5555/first'),
            PubMigTestData.row(indiv(), 'Second Paper', D1, '10.5555/second')
        });
        ThrowingRecordTracker tracker = new ThrowingRecordTracker(1); // 1st record() call throws, after the DML

        PubMigSummary s = PubMigTestData.runMigration(tracker, 1);

        Assert.areEqual(1, s.chunksFailed);
        Assert.areEqual(1, s.rowsInFailedChunks);
        Assert.isTrue(s.hasChunkProblems());
        Assert.isTrue(s.chunkErrors[0].contains('boom'), s.chunkErrors[0]);
        Assert.areEqual(1, s.migrated, 'the job continued with the next chunk');
        Assert.areEqual(1, PubMigTestData.publicationCount(), 'first chunk rolled back: no orphan Publication');
        Assert.areEqual(1, PubMigTestData.contributorCount());
        Map<Id, SObject> st = PubMigTestData.state();
        Assert.isNull(PubMigTestData.status(st.get(rows[0].Id)));
        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(st.get(rows[1].Id)));
        String email = s.render(null);
        Assert.isTrue(email.contains('DID NOT COMPLETE'), email);
        Assert.isTrue(email.contains('boom'), email);

        PubMigTestData.runMigration(); // cause fixed → default tracker

        Assert.areEqual(PubMigOutcome.STATUS_MIGRATED, PubMigTestData.status(PubMigTestData.state().get(rows[0].Id)));
        Assert.areEqual(2, PubMigTestData.publicationCount(), 'exactly one Publication per paper after the retry');
        Assert.areEqual(2, PubMigTestData.contributorCount());
    }

    @IsTest
    static void summaryReportsUncaughtJobErrors() {
        PubMigSummary s = new PubMigSummary();
        s.jobErrors = 2;
        s.jobStatusDetail = 'First error: Too many query rows: 50001';

        Assert.isTrue(s.hasChunkProblems());
        String email = s.render(null);
        Assert.isTrue(email.contains('DID NOT COMPLETE'), email);
        Assert.isTrue(email.contains('Too many query rows'), email);
        Assert.isFalse(new PubMigSummary().hasChunkProblems());
        Assert.isFalse(new PubMigSummary().render(null).contains('DID NOT COMPLETE'));
    }

    // ==================================================================== master-detail cascade (code review finding 2)

    // compensate() deletes only the Publication and relies on this cascade for its Contributors
    @IsTest
    static void deletingPublicationDeletesItsContributors() {
        Publication p = new Publication(Name = 'Cascade', Title = 'Cascade', PublishedDate = D1);
        insert p;
        insert new List<PublicationContributor>{
            new PublicationContributor(PublicationId = p.Id, ContributorId = acct(), IsEqualContribution = false),
            new PublicationContributor(PublicationId = p.Id, ContributorId = indiv(), IsEqualContribution = false)
        };
        Assert.areEqual(2, PubMigTestData.contributorCount());

        delete p;

        Assert.areEqual(0, PubMigTestData.contributorCount(), 'PublicationContributor.Publication must be master-detail');
    }

    // ==================================================================== bulk

    // T8 + T17 (real batch): 200 rows in one execute, 1 bad row → 199 Migrated, batch completes
    @IsTest
    static void realBatchMigrates200Rows() {
        Id a = acct();
        Id i = indiv();
        List<PartyPublication> rows = new List<PartyPublication>();
        for (Integer n = 0; n < 100; n++) {
            rows.add(PubMigTestData.row(a, 'Paper ' + n, D1, '10.5555/p' + n));
            rows.add(PubMigTestData.row(i, 'Paper ' + n, D1, '10.5555/p' + n));
        }
        rows[199].PublicationDate = null;
        rows[199].PublicationIdentifier = null;
        PubMigTestData.insertRows(rows);

        Test.startTest();
        PartyPublicationMigrationBatch.run();
        Test.stopTest();

        Map<String, Integer> byStatus = new Map<String, Integer>();
        for (SObject r : PubMigTestData.state().values()) {
            String key = String.valueOf(PubMigTestData.status(r));
            byStatus.put(key, (byStatus.containsKey(key) ? byStatus.get(key) : 0) + 1);
        }
        Assert.areEqual(199, byStatus.get(PubMigOutcome.STATUS_MIGRATED));
        Assert.areEqual(1, byStatus.get(PubMigOutcome.STATUS_FAILED));
        Assert.areEqual(100, PubMigTestData.publicationCount());
        Assert.areEqual(199, PubMigTestData.contributorCount());
    }

    // T17 (inline): 250 rows over 2 chunks stay well inside governor limits
    @IsTest
    static void bulk250RowsTwoChunks() {
        Id a = acct();
        List<PartyPublication> rows = new List<PartyPublication>();
        for (Integer n = 0; n < 250; n++) {
            rows.add(PubMigTestData.row(a, 'Paper ' + n, D1, 'PMID ' + n));
        }
        PubMigTestData.insertRows(rows);

        Test.startTest();
        PubMigSummary s = PubMigTestData.runMigration(null, 200);
        Integer queries = Limits.getQueries();
        Integer dml = Limits.getDmlStatements();
        Test.stopTest();

        Assert.areEqual(250, s.migrated);
        Assert.areEqual(250, PubMigTestData.publicationCount());
        Assert.isTrue(queries <= 2 + 2 * 6, 'SOQL per chunk must be constant; used ' + queries);
        Assert.isTrue(dml <= 2 * 6, 'DML per chunk must be constant (5 + the rollback savepoint); used ' + dml);
    }

    // ==================================================================== helpers

    /** Every field value of every PartyPublication, minus system audit fields (and optionally the migration fields). */
    private static Map<Id, Map<String, Object>> snapshot(Boolean excludeMigrationFields) {
        Set<String> skip = new Set<String>{ 'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp', 'lastvieweddate', 'lastreferenceddate' };
        if (excludeMigrationFields) {
            for (String f : PartyPublicationFieldTracker.MIGRATION_FIELDS) {
                skip.add(f.toLowerCase());
            }
        }
        List<String> fields = new List<String>();
        for (Schema.SObjectField f : PartyPublication.SObjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (!skip.contains(d.getName().toLowerCase()) && d.getType() != Schema.DisplayType.ADDRESS && d.getType() != Schema.DisplayType.LOCATION) {
                fields.add(d.getName());
            }
        }
        Map<Id, Map<String, Object>> result = new Map<Id, Map<String, Object>>();
        for (SObject r : Database.query('SELECT ' + String.join(fields, ', ') + ' FROM PartyPublication')) {
            result.put(r.Id, new Map<String, Object>(r.getPopulatedFieldsAsMap()));
        }
        return result;
    }

    /** Breaks inserts for chosen source rows by blanking a required field, so the platform rejects them for real. */
    private class BreakHook implements PubMigInsertHook {
        public Set<Id> breakPublicationFor = new Set<Id>();
        public Set<Id> breakContributorFor = new Set<Id>();

        public void beforePublicationInsert(Id sourceId, Publication candidate) {
            if (breakPublicationFor.contains(sourceId)) {
                candidate.Title = null;
            }
        }
        public void beforeContributorInsert(Id sourceId, PublicationContributor candidate) {
            if (breakContributorFor.contains(sourceId)) {
                candidate.ContributorId = null;
            }
        }
    }

    /** Reports a prerequisite problem, like a missing custom field would. */
    private class ProblemTracker implements PubMigTracker {
        private final PartyPublicationFieldTracker delegate = new PartyPublicationFieldTracker();
        private final String problem;

        public ProblemTracker(String problem) {
            this.problem = problem;
        }
        public List<String> checkPrerequisites() {
            return new List<String>{ problem };
        }
        public Database.QueryLocator candidates() {
            return delegate.candidates();
        }
        public Map<Id, PubMigOutcome> eligible(Set<Id> sourceIds) {
            return delegate.eligible(sourceIds);
        }
        public Map<String, Id> existingPublicationByGroupKey(Set<String> groupKeys) {
            return delegate.existingPublicationByGroupKey(groupKeys);
        }
        public Map<Id, String> record(List<PubMigOutcome> outcomes) {
            return delegate.record(outcomes);
        }
    }

    private class BoomException extends Exception {}

    /** record() throws on the Nth call, after the engine has already inserted Publications and Contributors. */
    private class ThrowingRecordTracker implements PubMigTracker {
        private final PartyPublicationFieldTracker delegate = new PartyPublicationFieldTracker();
        private final Integer throwOnCall;
        private Integer calls = 0;

        public ThrowingRecordTracker(Integer throwOnCall) {
            this.throwOnCall = throwOnCall;
        }
        public List<String> checkPrerequisites() {
            return delegate.checkPrerequisites();
        }
        public Database.QueryLocator candidates() {
            return delegate.candidates();
        }
        public Map<Id, PubMigOutcome> eligible(Set<Id> sourceIds) {
            return delegate.eligible(sourceIds);
        }
        public Map<String, Id> existingPublicationByGroupKey(Set<String> groupKeys) {
            return delegate.existingPublicationByGroupKey(groupKeys);
        }
        public Map<Id, String> record(List<PubMigOutcome> outcomes) {
            calls++;
            if (calls == throwOnCall) {
                throw new BoomException('boom');
            }
            return delegate.record(outcomes);
        }
    }

    /** Simulates a validation rule on PartyPublication that blocks the status write for some rows. */
    private class FailingRecordTracker implements PubMigTracker {
        private final PartyPublicationFieldTracker delegate = new PartyPublicationFieldTracker();
        private final Set<Id> failIds;

        public FailingRecordTracker(Set<Id> failIds) {
            this.failIds = failIds;
        }
        public List<String> checkPrerequisites() {
            return delegate.checkPrerequisites();
        }
        public Database.QueryLocator candidates() {
            return delegate.candidates();
        }
        public Map<Id, PubMigOutcome> eligible(Set<Id> sourceIds) {
            return delegate.eligible(sourceIds);
        }
        public Map<String, Id> existingPublicationByGroupKey(Set<String> groupKeys) {
            return delegate.existingPublicationByGroupKey(groupKeys);
        }
        public Map<Id, String> record(List<PubMigOutcome> outcomes) {
            List<PubMigOutcome> pass = new List<PubMigOutcome>();
            Map<Id, String> failed = new Map<Id, String>();
            for (PubMigOutcome o : outcomes) {
                if (failIds.contains(o.sourceId)) {
                    failed.put(o.sourceId, 'FIELD_CUSTOM_VALIDATION_EXCEPTION: blocked by test');
                } else {
                    pass.add(o);
                }
            }
            failed.putAll(delegate.record(pass));
            return failed;
        }
    }

    /** A tracker that never writes PartyPublication (§1.4 option 2). Test-only: state lives in memory. */
    private class InMemoryTracker implements PubMigTracker {
        private final Map<Id, PubMigOutcome> store = new Map<Id, PubMigOutcome>();

        public List<String> checkPrerequisites() {
            return new List<String>();
        }
        public Database.QueryLocator candidates() {
            return Database.getQueryLocator([SELECT Id FROM PartyPublication ORDER BY CreatedDate, Id]);
        }
        public Map<Id, PubMigOutcome> eligible(Set<Id> sourceIds) {
            Map<Id, PubMigOutcome> result = new Map<Id, PubMigOutcome>();
            for (Id sourceId : sourceIds) {
                PubMigOutcome prev = store.get(sourceId);
                if (prev == null) {
                    result.put(sourceId, new PubMigOutcome(sourceId));
                } else if (prev.isFailed()) {
                    result.put(sourceId, prev);
                }
            }
            return result;
        }
        public Map<String, Id> existingPublicationByGroupKey(Set<String> groupKeys) {
            Map<String, Id> result = new Map<String, Id>();
            for (PubMigOutcome o : store.values()) {
                if (o.isMigrated() && groupKeys.contains(o.groupKey)) {
                    result.put(o.groupKey, o.publicationId);
                }
            }
            return result;
        }
        public Map<Id, String> record(List<PubMigOutcome> outcomes) {
            for (PubMigOutcome o : outcomes) {
                store.put(o.sourceId, o);
            }
            return new Map<Id, String>();
        }
    }
}
