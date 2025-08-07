// Get all ProductionBatch records
List<ProductionBatch> batchRecords = [SELECT Id FROM ProductionBatch];

// Get Aurora territory ID
Id auroraTerritoryId = [SELECT Id FROM Territory2 WHERE DeveloperName = 'TMSPCAurora20A02T06' LIMIT 1].Id;

// Get the territory-related group instead of territory ID
Id groupId = [SELECT Id FROM Group WHERE Type = 'Territory' AND RelatedId = :auroraTerritoryId LIMIT 1].Id;

List<ProductionBatchShare> batchShareToInsert = new List<ProductionBatchShare>();

for(ProductionBatch batch : batchRecords) {
    ProductionBatchShare batchShare = new ProductionBatchShare(
        ParentId = batch.Id,
        UserOrGroupId = groupId,
        AccessLevel = 'Read'
    );
    batchShareToInsert.add(batchShare);
}

if(!batchShareToInsert.isEmpty()) {
    try {
        insert batchShareToInsert;
        System.debug('Successfully shared ProductionBatch records with territory');
    } catch(Exception e) {
        System.debug('Error sharing ProductionBatch records: ' + e.getMessage());
    }
}
