@IsTest
private class LSC_ToolingUpdaterException_Test {
    @IsTest
    static void coversConstructorsAndTouch() {
        // touch static
        System.assertEquals(true, LSC_ToolingUpdaterException.touch());
        // default ctor
        LSC_ToolingUpdaterException e1 = new LSC_ToolingUpdaterException();
        System.assertNotEquals(null, e1);
        // throw/catch
        try {
            throw new LSC_ToolingUpdaterException();
        } catch (LSC_ToolingUpdaterException ex) {
            System.assertNotEquals(null, ex);
        }
    }
}


