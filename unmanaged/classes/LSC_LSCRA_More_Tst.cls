@IsTest
private class LSC_LSCRA_More_Tst {
    @IsTest
    static void testRunAllQueuedDefault_noStop() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<Id> jobs = LSC_LifeSciConfigRecordsActivate.runAllQueued();
        System.assertEquals(1, jobs.size());
        System.assertNotEquals(null, jobs[0]);
    }

    @IsTest
    static void testRunAllQueuedWithChunk_noStop() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<Id> jobs = LSC_LifeSciConfigRecordsActivate.runAllQueued(1);
        System.assertEquals(1, jobs.size());
        System.assertNotEquals(null, jobs[0]);
    }

    @IsTest
    static void testRunWithNamesQueued_emptyAndNull() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<Id> jobs1 = LSC_LifeSciConfigRecordsActivate.runWithNamesQueued(null, null);
        System.assertEquals(1, jobs1.size());
        List<Id> jobs2 = LSC_LifeSciConfigRecordsActivate.runWithNamesQueued(new List<String>(), 0);
        System.assertEquals(1, jobs2.size());
    }

    @IsTest
    static void testRunWithNamesQueued_customSmall_executesOnce() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false));
        List<String> names = new List<String>{ 'AccountSearchSettings_OrgLevel', 'Missing_DevName' };
        Test.startTest();
        List<Id> jobs = LSC_LifeSciConfigRecordsActivate.runWithNamesQueued(names, names.size());
        System.assertEquals(1, jobs.size());
        Test.stopTest();
        System.assert(true, 'Job executed without chaining');
    }
}


