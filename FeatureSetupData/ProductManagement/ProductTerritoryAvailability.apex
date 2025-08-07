// delete ProductTerritoryAvailability

List<ProductTerritoryAvailability> availibilityRecords = [Select Id from ProductTerritoryAvailability];
if(!availibilityRecords.isEmpty()) delete availibilityRecords;

List<ProductTerritoryAvailability> ptasToInsert = new List<ProductTerritoryAvailability>();

// Fetch some marketable products as Qualification API will not work for per territory more than 50 products are allinged this can be changed to all products post fix for qualification API from DT to SOQL approach  
List<LifeSciMarketableProduct> lsProducts = [SELECT Id, Name, ProductId, Product.SpecificationType, Type FROM LifeSciMarketableProduct where Name in ('Aleve','ADRACHOL TAB 25-10 MG','PLOMAX 100 MCG PEN','NyQuil – Congestion','Robitussin – Cough','OTC Market', 'Pain Relief', 'Advil', 'Fever','Advil - Fever','Tylenol - Headache','ADRAVIL','Plomax') ];


// Fetch all territories
List<Territory2> territories = [SELECT Id FROM Territory2 where DeveloperName in ('RDMidwest20A' ) ];

// Iterate through each product and territory to create ProductTerritoryAvailability records
for (LifeSciMarketableProduct product : lsProducts) {
    Id productORLSProductId = (product.productId == null) ? product.Id : product.productId;
    for (Territory2 territory : territories) {
        ProductTerritoryAvailability pta = new ProductTerritoryAvailability(
            ProductId = productORLSProductId,
            AlignmentType = 'Territory and Subordinates Inclusion',
            Purpose = 'Visit',
            Status= 'Queued',
            TerritoryId = territory.Id
        );
        ptasToInsert.add(pta);
    }
}
//Fetch all territories for creating exclusion records for ProductTerritoryAvailability
List<Territory2> exclusionTerritories = [SELECT Id FROM Territory2 where DeveloperName in ( 'TMSPCJoliet20A02T11' ) ];
// Iterate through each product and territory to create ProductTerritoryAvailability records for exclusion
for (LifeSciMarketableProduct product : lsProducts) {
    Id productORLSProductId = (product.productId == null) ? product.Id : product.productId;
    for (Territory2 territory : exclusionTerritories) {
        ProductTerritoryAvailability pta = new ProductTerritoryAvailability(
            ProductId = productORLSProductId,
            AlignmentType = 'Territory Exclusion',
            Purpose = 'Visit',
            Status= 'Queued',
            TerritoryId = territory.Id
        );
        ptasToInsert.add(pta);
    }
}

// Insert the ProductTerritoryAvailability records
if (!ptasToInsert.isEmpty()) {
    try {
        insert ptasToInsert;
       
    } catch (DmlException e) {
        // Handle any DML exceptions, such as logging or error reporting
        System.debug('Error inserting ProductTerritoryAvailability records: ' + e.getMessage());
        for (Integer i = 0; i < e.getNumDml(); i++) {
            System.debug('DML error ' + i + ': ' + e.getDmlMessage(i));
        }
    }
} else {
    System.debug('No ProductTerritoryAvailability records to insert.');
}

if(ptasToInsert.size() > 0){
    // Query for current status
    List<ProductTerritoryAvailability> recordsToUpdate = [
        SELECT Id, Status 
        FROM ProductTerritoryAvailability 
        WHERE Id IN :ptasToInsert AND Status In ('Queued', 'Draft')
    ];
    
    for(ProductTerritoryAvailability pta: recordsToUpdate){
        pta.Status = 'Active';
    }
    
    if(!recordsToUpdate.isEmpty()) {
        update recordsToUpdate;
    }
}