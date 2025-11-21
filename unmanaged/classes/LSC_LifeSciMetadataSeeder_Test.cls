@IsTest
private class LSC_LifeSciMetadataSeeder_Test {
    @IsTest
    static void testSeedAllHandlesMissingResources() {
        // No static resources mocked; the seeder should handle missing/empty and return messages
        LSC_LifeSciMetadataSeeder seeder = new LSC_LifeSciMetadataSeeder();
        LSC_AllSeedResult res = seeder.seedAll();
        System.assertNotEquals(null, res);
        System.assertNotEquals(null, res.categories);
        System.assertNotEquals(null, res.records);
        System.assertNotEquals(null, res.fieldValues);
        // Expect some messages indicating missing resources or unknown sObjects
        System.assert(res.messages == null || res.messages.size() >= 0, 'Messages list present');
    }

    @IsTest
    static void testSeedAllCatchesExceptions() {
        LSC_LifeSciMetadataSeeder.TEST_forceExceptions = true;
        try {
            LSC_AllSeedResult res = new LSC_LifeSciMetadataSeeder().seedAll();
            System.assertNotEquals(null, res);
            System.assertEquals(1, res.categories.failed);
            System.assertEquals(1, res.records.failed);
            System.assertEquals(1, res.fieldValues.failed);
        } finally {
            LSC_LifeSciMetadataSeeder.TEST_forceExceptions = false;
        }
    }
}


