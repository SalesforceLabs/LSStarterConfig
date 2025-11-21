@IsTest
private class LSC_ToolingUpdater_Test {
    @IsTest
    static void testUpdateSuccessAndNotFound() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<LSC_UpdateRequest> reqs = new List<LSC_UpdateRequest>();

        LSC_UpdateRequest r1 = new LSC_UpdateRequest();
        r1.developerName = 'AccountSearchSettings_OrgLevel'; // known in mock
        r1.fieldsToUpdate = new Map<String, Object>{ 'IsActive' => true };
        reqs.add(r1);

        LSC_UpdateRequest r2 = new LSC_UpdateRequest();
        r2.developerName = 'Missing_DevName'; // not returned by query mock
        r2.fieldsToUpdate = new Map<String, Object>{ 'IsActive' => true };
        reqs.add(r2);

        Map<String, String> result = new LSC_ToolingUpdater().updateByDeveloperName(reqs);
        System.assertEquals('Updated', result.get('AccountSearchSettings_OrgLevel'));
        System.assertEquals('Not found', result.get('Missing_DevName'));
    }

    @IsTest
    static void testUpdatePatchFailure() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(true));
        List<LSC_UpdateRequest> reqs = new List<LSC_UpdateRequest>();
        LSC_UpdateRequest r1 = new LSC_UpdateRequest();
        r1.developerName = 'AccountSearchSettings_OrgLevel';
        r1.fieldsToUpdate = new Map<String, Object>{ 'IsActive' => true };
        reqs.add(r1);
        Map<String, String> result = new LSC_ToolingUpdater().updateByDeveloperName(reqs);
        System.assert(result.get('AccountSearchSettings_OrgLevel').startsWithIgnoreCase('Failed:'), 'Expected failure message');
    }
}


