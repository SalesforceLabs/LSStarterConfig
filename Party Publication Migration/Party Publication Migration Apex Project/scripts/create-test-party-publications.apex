// ============================================================================================
// Creates 10 PartyPublication test records (plus 3 test parties) for the Publication migration.
// Run: Developer Console -> Debug -> Open Execute Anonymous Window -> paste -> Execute.
// Every Title starts with "PUBMIG-TEST - " so cleanup-test-party-publications.apex can find them.
//
// What the 10 records are for (expected result of the migration in the last column):
//
//  #  Paper            Identifier                              Party   What it tests                                   Expected
//  1  Gene Editing     10.5555/pubmig.gene                     Acct    oldest record creates the Publication           Migrated
//  2  Gene Editing     https://doi.org/10.5555/PUBMIG.GENE     Indiv   DOI written another way = same paper            Migrated
//  3  Gene Editing     doi:10.5555/pubmig.gene (title differs) HCP     same paper; title differs                       Migrated + PAPER_FIELD_CONFLICT
//  4  Soil Microbiome  (none)                                  Acct    no identifier: key = Title + Date + Journal     Migrated
//  5  Soil Microbiome  N/A                                     Indiv   placeholder counts as blank = same paper as 4   Migrated
//  6  Vaccine Trial    31452104 (a PMID)                       HCP     not a DOI -> External Identifier                Migrated
//  7  Mixed Paper      10.5555/pubmig.mixed                    Acct    has an identifier ...                           Migrated
//  8  Mixed Paper      (none)                                  Indiv   ... its sibling has none -> a 2nd Publication   Migrated (pre-flight flags it)
//  9  Undated Paper    (none), no Publication Date             Indiv   missing date                                    Failed MISSING_PUBLICATION_DATE
// 10  Gene Editing     10.5555/pubmig.gene                     Acct    same person + paper as #1 -> shared Contributor Migrated
//
// Expected totals after one migration run: 9 Migrated, 1 Failed, 5 Publications, 8 Contributors.
// Pre-flight report: 1 finding (MIXED_IDENTIFIER, "Mixed Paper").
// ============================================================================================

final String PREFIX = 'PUBMIG-TEST - ';

// true = also fill Party Role Type, Publication Category, Status and Listing Platform Type on each record.
// The script first prints which of these values are missing from which picklist (search the log for "MISSING").
// Set to false to leave those four fields empty.
final Boolean SET_PICKLISTS = true;

// Values this script uses, and where the migration needs each one:
//   Party Publication.PartyRoleType        -> Publication Contributor.ContributorRole
//   Party Publication.PublicationCategory  -> Publication.PublicationCategory__c
//   Party Publication.Status               -> Publication.Status
//   Party Publication.ListingPlatformType  -> Publication.ListingPlatformType
final List<String> ROLES      = new List<String>{ 'First Author', 'Co-Author', 'Senior Author', 'Corresponding Author' };
final List<String> CATEGORIES = new List<String>{ 'Journal Article', 'Conference Paper', 'Clinical Trial', 'Review' };
final List<String> STATUSES   = new List<String>{ 'Published', 'In Press', 'Draft' };
final List<String> PLATFORMS  = new List<String>{ 'PubMed', 'Scopus', 'Web of Science' };

void checkPicklist(String objectName, String fieldName, List<String> needed) {
    Schema.SObjectType t = Schema.getGlobalDescribe().get(objectName.toLowerCase());
    if (t == null) { System.debug(LoggingLevel.WARN, 'MISSING object ' + objectName + ' (is this feature enabled in the org?)'); return; }
    Schema.SObjectField f = t.getDescribe().fields.getMap().get(fieldName.toLowerCase());
    if (f == null) { System.debug(LoggingLevel.WARN, 'MISSING field ' + objectName + '.' + fieldName + (fieldName.endsWith('__c') ? ' (create it, setup guide step 1b)' : '')); return; }
    Set<String> have = new Set<String>();
    for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) { if (e.isActive()) { have.add(e.getValue()); } }
    List<String> missing = new List<String>();
    for (String v : needed) { if (!have.contains(v)) { missing.add(v); } }
    System.debug((missing.isEmpty() ? 'OK      ' : 'MISSING ') + objectName + '.' + fieldName + (missing.isEmpty() ? '' : ': add ' + String.join(missing, ', ')));
}
if (SET_PICKLISTS) {
    checkPicklist('PartyPublication', 'PartyRoleType', ROLES);
    checkPicklist('PartyPublication', 'PublicationCategory', CATEGORIES);
    checkPicklist('PartyPublication', 'Status', STATUSES);
    checkPicklist('PartyPublication', 'ListingPlatformType', PLATFORMS);
    checkPicklist('PublicationContributor', 'ContributorRole', ROLES);
    checkPicklist('Publication', 'PublicationCategory__c', CATEGORIES);
    checkPicklist('Publication', 'Status', STATUSES);
    checkPicklist('Publication', 'ListingPlatformType', PLATFORMS);
}

if ([SELECT COUNT() FROM PartyPublication WHERE Title LIKE :(PREFIX + '%')] > 0) {
    System.debug(LoggingLevel.ERROR, 'Test records already exist. Run cleanup-test-party-publications.apex first.');
    return;
}

// ---- 3 parties: one of each type the migration supports
Account acct = new Account(Name = 'PUBMIG-TEST University');
insert acct;
Individual indiv = new Individual(LastName = 'PUBMIG-TEST Individual');
insert indiv;
HealthcareProvider hcp = new HealthcareProvider(Name = 'PUBMIG-TEST Provider');
insert hcp;

Date d1 = Date.newInstance(2022, 3, 1);
Date d2 = Date.newInstance(2021, 6, 30);
Date d3 = Date.newInstance(2020, 1, 15);
Date d4 = Date.newInstance(2019, 9, 9);

// Inserted in this order, so Ids (and the "oldest record creates the Publication" rule) follow the list.
List<PartyPublication> rows = new List<PartyPublication>{
    new PartyPublication(PartyId = acct.Id,  Title = PREFIX + 'Gene Editing in Crops', PublicationDate = d1, PublishedOn = 'Nature', PublicationIdentifier = '10.5555/pubmig.gene'),                        // 1
    new PartyPublication(PartyId = indiv.Id, Title = PREFIX + 'Gene Editing in Crops', PublicationDate = d1, PublishedOn = 'Nature', PublicationIdentifier = 'https://doi.org/10.5555/PUBMIG.GENE'),         // 2
    new PartyPublication(PartyId = hcp.Id,   Title = PREFIX + 'Gene editing in crops.', PublicationDate = d1, PublishedOn = 'Nature', PublicationIdentifier = 'doi:10.5555/pubmig.gene'),                   // 3
    new PartyPublication(PartyId = acct.Id,  Title = PREFIX + 'Soil Microbiome Study', PublicationDate = d2, PublishedOn = 'Science', PublicationIdentifier = null),                                         // 4
    new PartyPublication(PartyId = indiv.Id, Title = PREFIX + 'soil microbiome study', PublicationDate = d2, PublishedOn = 'Science', PublicationIdentifier = 'N/A'),                                        // 5
    new PartyPublication(PartyId = hcp.Id,   Title = PREFIX + 'Vaccine Trial Results', PublicationDate = d3, PublishedOn = 'The Lancet', PublicationIdentifier = '31452104'),                               // 6
    new PartyPublication(PartyId = acct.Id,  Title = PREFIX + 'Mixed Paper', PublicationDate = d4, PublishedOn = 'Cell', PublicationIdentifier = '10.5555/pubmig.mixed'),                                    // 7
    new PartyPublication(PartyId = indiv.Id, Title = PREFIX + 'Mixed Paper', PublicationDate = d4, PublishedOn = 'Cell', PublicationIdentifier = null),                                                      // 8
    new PartyPublication(PartyId = indiv.Id, Title = PREFIX + 'Undated Paper', PublicationDate = null, PublishedOn = 'Cell', PublicationIdentifier = null),                                                  // 9
    new PartyPublication(PartyId = acct.Id,  Title = PREFIX + 'Gene Editing in Crops', PublicationDate = d1, PublishedOn = 'Nature', PublicationIdentifier = '10.5555/pubmig.gene')                         // 10
};

if (SET_PICKLISTS) {
    //                       Role                    Category            Status       Listing platform (multi-select uses ;)
    String[][] pick = new String[][]{
        new String[]{ 'First Author',         'Journal Article',  'Published', 'PubMed;Scopus' }, // 1
        new String[]{ 'Co-Author',            'Journal Article',  'Published', 'PubMed' },         // 2
        new String[]{ 'Corresponding Author', 'Journal Article',  'Published', 'PubMed' },         // 3
        new String[]{ 'First Author',         'Review',           'Published', 'Scopus' },         // 4
        new String[]{ 'Co-Author',            'Review',           'Published', 'Scopus' },         // 5
        new String[]{ 'Senior Author',        'Clinical Trial',   'In Press',  'PubMed' },         // 6
        new String[]{ 'First Author',         'Conference Paper', 'Published', 'Web of Science' }, // 7
        new String[]{ 'Co-Author',            'Conference Paper', 'Published', 'Web of Science' }, // 8
        new String[]{ 'First Author',         'Conference Paper', 'Draft',     null },             // 9
        new String[]{ 'First Author',         'Journal Article',  'Published', 'PubMed;Scopus' }   // 10: same person, role and paper as #1 -> shares its Contributor
    };
    for (Integer i = 0; i < rows.size(); i++) {
        rows[i].put('PartyRoleType', pick[i][0]);
        rows[i].put('PublicationCategory', pick[i][1]);
        rows[i].put('Status', pick[i][2]);
        rows[i].put('ListingPlatformType', pick[i][3]);
    }
}

List<Database.SaveResult> results = Database.insert(rows, false);
Integer ok = 0;
for (Integer i = 0; i < results.size(); i++) {
    if (results[i].isSuccess()) {
        ok++;
    } else {
        System.debug(LoggingLevel.ERROR, 'Record #' + (i + 1) + ' failed: ' + results[i].getErrors()[0].getMessage());
    }
}
System.debug('Created ' + ok + ' of ' + rows.size() + ' PartyPublication records. Filter the log on USER_DEBUG.');
