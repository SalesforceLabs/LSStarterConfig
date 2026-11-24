@IsTest
private class PubMigRulesTest {

    // T4: DOI routing table (design §4)
    @IsTest
    static void routesIdentifiers() {
        Map<String, List<String>> expected = new Map<String, List<String>>{
            '10.1038/nature12373' => new List<String>{ PubMigRules.FIELD_DOI, '10.1038/nature12373' },
            'https://doi.org/10.1038/nature12373' => new List<String>{ PubMigRules.FIELD_DOI, '10.1038/nature12373' },
            'http://dx.doi.org/10.1038/nature12373' => new List<String>{ PubMigRules.FIELD_DOI, '10.1038/nature12373' },
            '  DOI: 10.48550/arXiv.2101.00001 ' => new List<String>{ PubMigRules.FIELD_DOI, '10.48550/arXiv.2101.00001' },
            '10.1002/(SICI)1097-4636(199706)35:4<417::AID-JBM1>3.0.CO;2-K' =>
                new List<String>{ PubMigRules.FIELD_DOI, '10.1002/(SICI)1097-4636(199706)35:4<417::AID-JBM1>3.0.CO;2-K' },
            'PMID: 31452104' => new List<String>{ PubMigRules.FIELD_EXTERNAL_ID, 'PMID: 31452104' },
            ' 31452104 ' => new List<String>{ PubMigRules.FIELD_EXTERNAL_ID, '31452104' },
            'arXiv:2101.00001' => new List<String>{ PubMigRules.FIELD_EXTERNAL_ID, 'arXiv:2101.00001' },
            'NCT01234567' => new List<String>{ PubMigRules.FIELD_EXTERNAL_ID, 'NCT01234567' },
            '10.12/x' => new List<String>{ PubMigRules.FIELD_EXTERNAL_ID, '10.12/x' } // registrant too short
        };
        for (String raw : expected.keySet()) {
            PubMigRules.RoutedIdentifier r = PubMigRules.routeIdentifier(raw);
            Assert.isNotNull(r, raw);
            Assert.areEqual(expected.get(raw)[0], r.field, raw);
            Assert.areEqual(expected.get(raw)[1], r.value, raw);
        }
    }

    // §3.3: placeholders are blank
    @IsTest
    static void placeholdersAreBlank() {
        for (String raw : new List<String>{ null, '', '   ', 'N/A', ' na ', 'None', 'NULL', 'tbd', '-', '0' }) {
            String shown = 'value: ' + raw; // a null message makes Assert throw
            Assert.isTrue(PubMigRules.isPlaceholder(raw), shown);
            Assert.isNull(PubMigRules.routeIdentifier(raw), shown);
        }
        Assert.isFalse(PubMigRules.isPlaceholder('00'));
    }

    @IsTest
    static void normalizesText() {
        Assert.areEqual('a study of x ray s', PubMigRules.norm('  A  Study of X-Ray\'s!! '));
        Assert.areEqual('', PubMigRules.norm(null));
        Assert.areEqual('étude 2', PubMigRules.norm('Étude, 2.'));
    }

    // §3.2 key rules
    @IsTest
    static void buildsGroupKeys() {
        Date d = Date.newInstance(2020, 1, 15);
        // identifier wins; DOI forms are equal; DOIs are case-insensitive
        Assert.areEqual('ID|10.1038/nature12373', PubMigRules.rawGroupKey('https://doi.org/10.1038/NATURE12373', 'x', null, null));
        Assert.areEqual(
            PubMigRules.groupKey('doi:10.1038/nature12373', 'Title one', d, 'Nature'),
            PubMigRules.groupKey('10.1038/NATURE12373', 'Different title', d.addDays(3), 'Science'));
        // fallback ignores case, punctuation, spacing
        Assert.areEqual(
            PubMigRules.groupKey(null, 'Deep Learning: A Review', d, 'Nature'),
            PubMigRules.groupKey('N/A', 'deep learning  a review.', d, 'NATURE'));
        Assert.areNotEqual(
            PubMigRules.groupKey(null, 'Deep Learning', d, 'Nature'),
            PubMigRules.groupKey(null, 'Deep Learning', d, 'Science'));
        // no identifier, no date → no key
        Assert.isNull(PubMigRules.groupKey(null, 'x', null, null));
        // hashed to a fixed 64 characters
        Assert.areEqual(64, PubMigRules.groupKey(null, 'x', d, null).length());
    }

    @IsTest
    static void mapsPaperFields() {
        PartyPublication src = new PartyPublication(
            Title = 'T', PublicationDate = Date.newInstance(2021, 2, 3), PublishedOn = 'J', Summary = 'S',
            Url = 'https://example.org', CitationCount = 7, ImpactFactor = 3.25, PublicationIdentifier = 'doi:10.1000/abc'
        );
        Publication p = PubMigRules.toPublication(src);
        Assert.areEqual('T', p.Name);
        Assert.areEqual('T', p.Title);
        Assert.areEqual(src.PublicationDate, p.PublishedDate);
        Assert.areEqual('J', p.OriginalSourceName);
        Assert.areEqual('S', p.AbstractText);
        Assert.areEqual('https://example.org', p.PublicationUrl);
        Assert.areEqual(7, p.CitationCount);
        Assert.areEqual(src.ImpactFactor, p.ImpactFactor);
        Assert.areEqual('10.1000/abc', p.get(PubMigRules.FIELD_DOI));
        Assert.isNull(p.get(PubMigRules.FIELD_EXTERNAL_ID));

        src.PublicationIdentifier = 'PMID 1';
        p = PubMigRules.toPublication(src);
        Assert.isNull(p.get(PubMigRules.FIELD_DOI));
        Assert.areEqual('PMID 1', p.get(PubMigRules.FIELD_EXTERNAL_ID));
    }

    // T16 (unit level): inactive owner → running user
    @IsTest
    static void resolvesOwner() {
        Id active = UserInfo.getUserId();
        Id inactive = fakeUserId(1);
        Id fallback = fakeUserId(2);
        Assert.areEqual(active, PubMigRules.resolveOwner(active, new Set<Id>{ inactive }, fallback));
        Assert.areEqual(fallback, PubMigRules.resolveOwner(inactive, new Set<Id>{ inactive }, fallback));
        Assert.areEqual(fallback, PubMigRules.resolveOwner(null, new Set<Id>(), fallback));
    }

    @IsTest
    static void comparesValues() {
        Assert.isTrue(PubMigRules.sameValue('Title', null, ''));
        Assert.isFalse(PubMigRules.sameValue('Title', null, 'a'));
        Assert.isFalse(PubMigRules.sameValue('Title', 'Abc', 'abc')); // case-sensitive
        Assert.isTrue(PubMigRules.sameValue('ListingPlatformType', 'B;A', 'A;B'));
        Assert.isFalse(PubMigRules.sameValue('ListingPlatformType', 'A', 'A;B'));
        Assert.isTrue(PubMigRules.sameValue('ImpactFactor', 1.5, 1.50));
        Assert.isTrue(PubMigRules.sameValue('ImpactFactor', Double.valueOf('2.5'), Decimal.valueOf('2.5')));
        Assert.isTrue(PubMigRules.sameValue('CitationCount', 3, Decimal.valueOf(3)));
        Assert.isFalse(PubMigRules.sameValue('CitationCount', 3, 4));
        Assert.isTrue(PubMigRules.sameValue('PublishedDate', Date.newInstance(2020, 1, 1), Date.newInstance(2020, 1, 1)));

        Publication a = new Publication(Title = 'X', AbstractText = 'one');
        Publication b = new Publication(Title = 'X', AbstractText = 'two');
        if (PubMigRules.LISTING_FIELD != null) { // differingFields reads every compared field, so the org must have it
            a.put(PubMigRules.LISTING_FIELD, 'A');
            b.put(PubMigRules.LISTING_FIELD, 'A');
        }
        Assert.areEqual(new List<String>{ 'AbstractText' }, PubMigRules.differingFields(a, b));
    }

    @IsTest
    static void outcomeTransitions() {
        PubMigOutcome o = new PubMigOutcome(null);
        o.warn('W1', 'first');
        o.migrate(fakeUserId(3), null); // any Id; the outcome doesn't check the type
        Assert.isTrue(o.isMigrated());
        Assert.areEqual('W1: first', o.message);
        o.fail('E1', 'boom');
        Assert.isTrue(o.isFailed());
        Assert.isNull(o.contributorId);
        Assert.isTrue(o.warningCodes.isEmpty());
        Assert.areEqual('boom', o.message);
    }

    private static Id fakeUserId(Integer n) {
        return Id.valueOf(User.SObjectType.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0'));
    }
}
