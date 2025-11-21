@IsTest
private class LSC_MetadataSupport_Test {
    @IsTest
    static void testParseJsonRowsVariantsAndHelpers() {
        LSC_SeedResult r = new LSC_SeedResult();
        // Array form
        List<Map<String, Object>> rows1 = LSC_MetadataSupport.parseJsonRows('[]', 'X', r);
        System.assertNotEquals(null, rows1);
        // Object form with records
        List<Map<String, Object>> rows2 = LSC_MetadataSupport.parseJsonRows('{"records":[{}]}', 'X', r);
        System.assertEquals(1, rows2.size());
        // Invalid JSON
        List<Map<String, Object>> rows3 = LSC_MetadataSupport.parseJsonRows('{invalid', 'X', r);
        System.assert(rows3 == null || rows3.isEmpty(), 'Invalid JSON should produce null or empty rows and message');

        // tagMessages
        List<String> tagged = LSC_MetadataSupport.tagMessages(new List<String>{'a','b'}, 'TAG');
        System.assertEquals(2, tagged.size());
        System.assert(tagged[0].startsWith('[TAG]'));

        // getSObjectType existing and non-existing
        System.assertNotEquals(null, LSC_MetadataSupport.getSObjectType('Account', r));
        System.assertEquals(null, LSC_MetadataSupport.getSObjectType('DoesNotExist__c', r));

        // loadStaticResource for non-existing
        String sr = LSC_MetadataSupport.loadStaticResource('DoesNotExist', r);
        System.assertEquals(null, sr);
    }

    @IsTest
    static void testBuildersAndCoercionAndDmlHelpers() {
        // Build category sobjects (using Account type just to get an SObjectType)
        List<Map<String, Object>> catRows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'referenceId' => 'R1' },
                'Name' => 'Cat1'
            }
        };
        List<String> outRefs = new List<String>();
        List<SObject> catSob = LSC_MetadataSupport.buildCategorySObjects(catRows, Account.SObjectType, outRefs);
        System.assertEquals(1, catSob.size());
        System.assertEquals(1, outRefs.size());
        System.assertEquals('R1', outRefs[0]);

        // Build record sobjects with @ref mapping
        Map<String, String> catRefToId = new Map<String, String>{ 'CREF' => '001000000000001' };
        List<Map<String, Object>> recRows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'referenceId' => 'RR1' },
                'LifeScienceMetadataCategoryId' => '@CREF',
                'Name' => 'Rec1'
            }
        };
        List<String> recRefs = new List<String>();
        List<SObject> recSob = LSC_MetadataSupport.buildRecordSObjects(recRows, Account.SObjectType, recRefs, catRefToId);
        System.assertEquals(1, recSob.size());
        System.assertEquals('RR1', recRefs[0]);
        System.assertEquals('001000000000001', (String) recRows[0].get('LifeScienceMetadataCategoryId'));

        // Build field values with coercion using Account fields (Integer/Decimal)
        List<Map<String, Object>> fvRows = new List<Map<String, Object>>{
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'referenceId' => 'FV1' },
                'NumberOfEmployees' => '123',     // Integer
                'AnnualRevenue' => '12.34'        // Decimal/Currency
            },
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'referenceId' => 'FV2' },
                'NumberOfEmployees' => 'notAnInt',
                'AnnualRevenue' => 'notADec'
            }
        };
        List<String> fvRefs = new List<String>();
        Map<String, String> recordRefToId = new Map<String, String>{ 'ANY' => '001000000000002' };
        List<SObject> fvSob = LSC_MetadataSupport.buildFieldValueSObjects(fvRows, Account.SObjectType, recordRefToId, fvRefs);
        System.assertEquals(2, fvSob.size());
        System.assertEquals(123, (Integer) fvSob[0].get('NumberOfEmployees'));
        System.assertEquals(Decimal.valueOf('12.34'), (Decimal) fvSob[0].get('AnnualRevenue'));
        System.assertEquals(null, fvSob[1].get('NumberOfEmployees'));
        System.assertEquals(null, fvSob[1].get('AnnualRevenue'));
        System.assertEquals(new List<String>{'FV1','FV2'}, fvRefs);

        // Build field values with coercion using Contact fields (Boolean)
        List<Map<String, Object>> fvRowsContact = new List<Map<String, Object>>{
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'referenceId' => 'CFV1' },
                'HasOptedOutOfEmail' => 'true'
            },
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'referenceId' => 'CFV2' },
                'HasOptedOutOfEmail' => 'false'
            }
        };
        List<String> fvRefsContact = new List<String>();
        List<SObject> fvSobContact = LSC_MetadataSupport.buildFieldValueSObjects(fvRowsContact, Contact.SObjectType, new Map<String, String>(), fvRefsContact);
        System.assertEquals(2, fvSobContact.size());
        System.assertEquals(true, (Boolean) fvSobContact[0].get('HasOptedOutOfEmail'));
        System.assertEquals(false, (Boolean) fvSobContact[1].get('HasOptedOutOfEmail'));

        // DML helpers - failure path (missing required Name on Account)
        LSC_SeedResult dmlRes1 = new LSC_SeedResult();
        LSC_MetadataSupport.insertBulk(new List<SObject>{ new Account() }, dmlRes1);
        System.assertEquals(0, dmlRes1.inserted);
        System.assertEquals(1, dmlRes1.failed);
        System.assert(dmlRes1.messages.size() > 0);

        // DML helpers - mixed success/failure and ref mapping
        LSC_SeedResult dmlRes2 = new LSC_SeedResult();
        List<SObject> records = new List<SObject>{ new Account(Name='OK'), new Account() };
        List<String> refs = new List<String>{ 'ref-ok', 'ref-missing' };
        Map<String, String> refToId = new Map<String, String>();
        LSC_MetadataSupport.insertBulkWithRefMap(records, refs, refToId, dmlRes2);
        System.assertEquals(1, dmlRes2.inserted);
        System.assertEquals(1, dmlRes2.failed);
        System.assertEquals(true, refToId.containsKey('ref-ok'));
    }
}


