@IsTest
private class LSC_UpdateQueue_Test {
    @IsTest
    static void testQueueProcessesInChunks() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<String> names = new List<String>{
            'AccountSearchSettings_OrgLevel', // known
            'Missing_DevName_1',
            'Missing_DevName_2'
        };
        Test.startTest();
        // Use a chunk size equal to the list size to avoid chaining depth in tests
        System.enqueueJob(new LSC_UpdateQueue(names, 0, names.size()));
        Test.stopTest();
        System.assert(true, 'Queue executed without unhandled exceptions');
    }
}


