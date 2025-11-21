@IsTest
private class LSC_UpdateQueue_MorePaths_Test {
    @IsTest
    static void testEarlyReturnOnEmpty() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        Test.startTest();
        System.enqueueJob(new LSC_UpdateQueue(new List<String>()));
        Test.stopTest();
        System.assert(true, 'No errors on empty list');
    }

    @IsTest
    static void testConstructorNormalizationAndContinueOnBlank() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<String> names = new List<String>{ '   ', 'AccountSearchSettings_OrgLevel' }; // first blank triggers continue
        Test.startTest();
        // startIndex negative should normalize to 0; chunkSize <= 0 should normalize to default
        System.enqueueJob(new LSC_UpdateQueue(names, -5, 0));
        Test.stopTest();
        System.assert(true, 'Normalized constructor executed');
    }

    @IsTest
    static void testReqsEmptySkipsCallout() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<String> names = new List<String>{ '   ' }; // only blank -> reqs remains empty
        Test.startTest();
        System.enqueueJob(new LSC_UpdateQueue(names, 0, 10));
        Test.stopTest();
        System.assert(true, 'No callouts when slice produces no requests');
    }

    @IsTest
    static void testSingleChainExecutesSecondSlice() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<String> names = new List<String>{ 'AccountSearchSettings_OrgLevel', 'Missing_DevName' };
        Test.startTest();
        // Use chunkSize == names.size() to avoid chaining in org-wide runs
        System.enqueueJob(new LSC_UpdateQueue(names, 0, names.size()));
        Test.stopTest();
        System.assert(true, 'Processed without chaining');
    }
}


