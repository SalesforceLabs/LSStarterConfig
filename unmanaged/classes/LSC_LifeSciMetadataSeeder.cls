/**
 * Seeds LifeSci Metadata setup objects from JSON static resources.
 * Expects three Static Resources whose content exactly matches the repo JSON files:
 *  - LifeSciMetadataCategory  -> LSStarterConfig/LSConfig/lifeSciMetadataRecord/LifeSciMetadataCategory.json
 *  - LifeSciMetadataRecord    -> LSStarterConfig/LSConfig/lifeSciMetadataRecord/LifeSciMetadataRecord.json
 *  - LifeSciMetadataFieldValue-> LSStarterConfig/LSConfig/lifeSciMetadataRecord/LifeSciMetadataFieldValue.json
 *
 * Call:
 *  LSC_AllSeedResult res = new LSC_LifeSciMetadataSeeder().seedAll();
 *  System.debug(res.messages);
 * 
 * 
 * Order of creation:
 *   Category -> Record -> FieldValue
 */
public with sharing class LSC_LifeSciMetadataSeeder {

    @TestVisible
    private static Boolean TEST_forceExceptions = false;

    // Reference maps populated during seed to resolve @referenceId links
    private Map<String, String> categoryRefToId = new Map<String, String>();
    private Map<String, String> recordRefToId   = new Map<String, String>();

    // One-call entrypoint
    public LSC_AllSeedResult seedAll() {
        LSC_AllSeedResult all = new LSC_AllSeedResult();
        try {
            if (TEST_forceExceptions) {
                throw new LSC_ToolingUpdaterException('forced categories exception');
            }
            all.categories = this.insertCategories();
        } catch (Exception e) {
            all.categories = this.errorResult('Categories', e);
        }
        this.appendPhaseMessages(all, 'Categories', all.categories);
        try {
            if (TEST_forceExceptions) {
                throw new LSC_ToolingUpdaterException('forced records exception');
            }
            all.records = this.insertRecords();
        } catch (Exception e) {
            all.records = this.errorResult('Records', e);
        }
        this.appendPhaseMessages(all, 'Records', all.records);
        try {
            if (TEST_forceExceptions) {
                throw new LSC_ToolingUpdaterException('forced fieldValues exception');
            }
            all.fieldValues = this.insertFieldValues();
        } catch (Exception e) {
            all.fieldValues = this.errorResult('FieldValues', e);
        }
        this.appendPhaseMessages(all, 'FieldValues', all.fieldValues);
        // Always emit errors to debug so users see duplicates and other failures without a custom runner
        if (all.messages != null && all.messages.size() > 0) {
            System.debug('=== LSC_LifeSciMetadataSeeder errors ===');
            for (String m : all.messages) {
                System.debug(m);
            }
        }
        return all;
    }

    // Phase 1: Categories
    private LSC_SeedResult insertCategories() {
        LSC_SeedResult result = new LSC_SeedResult();
        String json = this.loadStaticResource('LifeSciMetadataCategory');
        if (String.isBlank(json)) {
            result.messages.add('Static Resource not found or empty: LifeSciMetadataCategory');
            return result;
        }
        List<Map<String, Object>> rows = LSC_MetadataSupport.parseJsonRows(json, 'LifeSciMetadataCategory', result);
        if (rows == null || rows.isEmpty()) {
            result.messages.add('No rows to insert for LifeSciMetadataCategory');
            return result;
        }
        SObjectType sobType = this.getSObjectType('LifeSciMetadataCategory');
        if (sobType == null) {
            result.messages.add('Unknown sObjectType: LifeSciMetadataCategory');
            return result;
        }
        List<String> refs = new List<String>();
        List<SObject> toInsert = LSC_MetadataSupport.buildCategorySObjects(rows, sobType, refs);
        if (toInsert.isEmpty()) {
            result.messages.add('No valid rows parsed for LifeSciMetadataCategory');
            return result;
        }
        // Pre-check duplicates via utility (reduces complexity and centralizes logic)
        toInsert = LSC_MetadataSupport.filterDuplicateCategories(toInsert, refs, result);
        if (toInsert.isEmpty()) {
            return result;
        }
        LSC_MetadataSupport.insertBulkWithRefMap(toInsert, refs, categoryRefToId, result);
        return result;
    }

    // Phase 2: Records (resolve category refs)
    private LSC_SeedResult insertRecords() {
        LSC_SeedResult result = new LSC_SeedResult();
        String json = this.loadStaticResource('LifeSciMetadataRecord');
        if (String.isBlank(json)) {
            result.messages.add('Static Resource not found or empty: LifeSciMetadataRecord');
            return result;
        }
        List<Map<String, Object>> rows = LSC_MetadataSupport.parseJsonRows(json, 'LifeSciMetadataRecord', result);
        if (rows == null || rows.isEmpty()) {
            result.messages.add('No rows to insert for LifeSciMetadataRecord');
            return result;
        }
        SObjectType sobType = this.getSObjectType('LifeSciMetadataRecord');
        if (sobType == null) {
            result.messages.add('Unknown sObjectType: LifeSciMetadataRecord');
            return result;
        }
        List<String> refs = new List<String>();
        List<SObject> toInsert = LSC_MetadataSupport.buildRecordSObjects(rows, sobType, refs, categoryRefToId);
        if (toInsert.isEmpty()) {
            result.messages.add('No valid rows parsed for LifeSciMetadataRecord');
            return result;
        }
        LSC_MetadataSupport.insertBulkWithRefMap(toInsert, refs, recordRefToId, result);
        return result;
    }

    // (moved helpers to LSC_MetadataSeedUtils)
    // Phase 3: Field Values (resolve record refs)
    private LSC_SeedResult insertFieldValues() {
        LSC_SeedResult result = new LSC_SeedResult();
        String json = this.loadStaticResource('LifeSciMetadataFieldValue');
        if (String.isBlank(json)) {
            result.messages.add('Static Resource not found or empty: LifeSciMetadataFieldValue');
            return result;
        }
        List<Map<String, Object>> rows = LSC_MetadataSupport.parseJsonRows(json, 'LifeSciMetadataFieldValue', result);
        if (rows == null || rows.isEmpty()) {
            result.messages.add('No rows to insert for LifeSciMetadataFieldValue');
            return result;
        }
        SObjectType sobType = this.getSObjectType('LifeSciMetadataFieldValue');
        if (sobType == null) {
            result.messages.add('Unknown sObjectType: LifeSciMetadataFieldValue');
            return result;
        }
        List<String> refs = new List<String>();
        List<SObject> toInsert = LSC_MetadataSupport.buildFieldValueSObjects(rows, sobType, recordRefToId, refs);
        if (toInsert.isEmpty()) {
            result.messages.add('No valid rows parsed for LifeSciMetadataFieldValue');
            return result;
        }
        LSC_MetadataSupport.insertBulkWithRefMap(toInsert, refs, null, result);
        return result;
    }

    // --- helpers moved to LSC_MetadataSeedUtils ---

    // Centralized unexpected error formatting so Execute Anonymous prints details instead of generic faults
    private LSC_SeedResult errorResult(String phase, Exception e) {
        LSC_SeedResult r = new LSC_SeedResult();
        r.failed = 1;
        r.messages.add(phase + ' failed with unexpected exception: ' + e.getTypeName() + ' - ' + e.getMessage());
        String st = e.getStackTraceString();
        if (st != null && st != '') {
            // Limit stack to a few lines to keep output readable
            List<String> lines = st.split('\n');
            Integer lineLimit = Math.min(lines.size(), 10);
            for (Integer i = 0; i < lineLimit; i++) {
                r.messages.add(lines[i]);
            }
        }
        return r;
    }

    // Aggregate phase messages to top-level so System.debug(result) shows errors prominently
    private void appendPhaseMessages(LSC_AllSeedResult all, String phase, LSC_SeedResult phaseResult) {
        if (phaseResult == null || phaseResult.messages == null) {
            return;
        }
        for (String msg : phaseResult.messages) {
            all.messages.add('[' + phase + '] ' + msg);
        }
    }

    private String loadStaticResource(String name) {
        try {
            // CRUD/FLS checks
            if (!Schema.sObjectType.StaticResource.isAccessible()) {
                return null;
            }
            if (!Schema.sObjectType.StaticResource.fields.Body.isAccessible()) {
                return null;
            }
            StaticResource sr = [SELECT Body FROM StaticResource WHERE Name = :name LIMIT 1];
            return sr != null ? sr.Body.toString() : null;
        } catch (Exception e) {
            return null;
        }
    }

    private SObjectType getSObjectType(String apiName) {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Schema.SObjectType t = gd.get(apiName);
        return t;
    }
}


