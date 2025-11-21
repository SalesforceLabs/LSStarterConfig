@IsTest
private class LSC_LifeSciConfigRecordsActivate_Test {
    @IsTest
    static void testRunAllQueuedChainsJobs() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        Test.startTest();
        // Use a tiny list to avoid deep chaining and callout limits in test context
        List<String> names = new List<String>{
            'AccountSearchSettings_OrgLevel',
            'Missing_DevName_1',
            'Missing_DevName_2'
        };
        List<Id> jobIds = LSC_LifeSciConfigRecordsActivate.runWithNamesQueued(names, names.size());
        System.assertEquals(1, jobIds.size(), 'Expected one initial job id');
        Test.stopTest();
        System.assert(true, 'Runner queued and processed without unhandled exceptions');
    }
}


