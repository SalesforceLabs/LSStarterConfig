// Get all ProductGuidance records
List<ProductGuidance> guidanceRecords = [SELECT Id FROM ProductGuidance];

// Get Aurora territory ID
Id auroraTerritoryId = [SELECT Id FROM Territory2 WHERE DeveloperName = 'TMSPCAurora20A02T06' LIMIT 1].Id;

// Get the territory-related group instead of territory ID
Id groupId = [SELECT Id FROM Group WHERE Type = 'Territory' AND RelatedId = :auroraTerritoryId LIMIT 1].Id;

List<ProductGuidanceShare> guidanceShareToInsert = new List<ProductGuidanceShare>();

for(ProductGuidance guidance : guidanceRecords) {
    ProductGuidanceShare guidanceShare = new ProductGuidanceShare(
        ParentId = guidance.Id,
        UserOrGroupId = groupId,
        AccessLevel = 'Read'
    );
    guidanceShareToInsert.add(guidanceShare);
}

if(!guidanceShareToInsert.isEmpty()) {
    try {
        insert guidanceShareToInsert;
        System.debug('Successfully shared ProductGuidance records with territory');
    } catch(Exception e) {
        System.debug('Error sharing ProductGuidance records: ' + e.getMessage());
    }
}


