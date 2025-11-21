@IsTest
private class LSC_ToolingUpdater_MorePaths_Test {
    @IsTest
    static void testQueryFailureThrows() {
        Test.setMock(HttpCalloutMock.class, new LSC_ToolingHttpMock(false, true)); // fail query
        try {
            new LSC_ToolingUpdater().updateByDeveloperName(new List<LSC_UpdateRequest>{
                makeReq('AccountSearchSettings_OrgLevel')
            });
            System.assert(false, 'Expected exception was not thrown');
        } catch (LSC_ToolingUpdaterException e) {
            System.assert(e.getMessage().contains('tooling/query'), 'Expected query failure message');
        }
    }

    private static LSC_UpdateRequest makeReq(String dn) {
        LSC_UpdateRequest r = new LSC_UpdateRequest();
        r.developerName = dn;
        r.fieldsToUpdate = new Map<String, Object>{ 'IsActive' => true };
        return r;
    }
}


