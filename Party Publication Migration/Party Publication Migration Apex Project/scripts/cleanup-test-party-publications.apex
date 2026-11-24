// ============================================================================================
// Removes everything the test data and a test migration created. Safe to run more than once.
// Only touches records whose Title / Name starts with "PUBMIG-TEST" (never other data).
// Run in the Developer Console: Debug -> Open Execute Anonymous Window.
// Use it to start over: run this, then create-test-party-publications.apex, then migrate again.
// ============================================================================================
final String PREFIX = 'PUBMIG-TEST';

// 1. Publications created by the migration (their Contributors are deleted with them)
List<Publication> pubs = [SELECT Id FROM Publication WHERE Name LIKE :(PREFIX + '%')];
delete pubs;

// 2. Path B only: log rows of the test records (skipped if the log object doesn't exist)
Integer logRows = 0;
if (Schema.getGlobalDescribe().containsKey('publicationmigrationlog__c')) {
    List<SObject> logs = Database.query(
        'SELECT Id FROM PublicationMigrationLog__c WHERE SourceId__c IN (SELECT Id FROM PartyPublication WHERE Title LIKE \'' + PREFIX + '%\')'
    );
    logRows = logs.size();
    delete logs;
}

// 3. The test PartyPublication records, then the test parties
List<PartyPublication> rows = [SELECT Id FROM PartyPublication WHERE Title LIKE :(PREFIX + '%')];
delete rows;
delete [SELECT Id FROM Account WHERE Name LIKE :(PREFIX + '%')];
delete [SELECT Id FROM Individual WHERE LastName LIKE :(PREFIX + '%')];
delete [SELECT Id FROM HealthcareProvider WHERE Name LIKE :(PREFIX + '%')];

System.debug('Deleted ' + pubs.size() + ' Publications, ' + rows.size() + ' PartyPublications, ' + logRows + ' log rows, plus the test parties.');
