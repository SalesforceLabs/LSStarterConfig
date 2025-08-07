//delete LifeSciProductAcctRstrc
List<LifeSciProductAcctRstrc> lsparRecords = [Select Id from LifeSciProductAcctRstrc];
if(!lsparRecords.isEmpty()) delete lsparRecords;

//get data from providerAccountTerritoryInfo and create lspar

List<ProviderAcctTerritoryInfo> accountTerritories = [SELECT Id, AccountId, Territory2Id FROM ProviderAcctTerritoryInfo WHERE Territory2.DeveloperName = 'TMSPCAurora20A02T06'];

List<LifeSciMarketableProduct> lsmpToInsert = new List<LifeSciMarketableProduct>();

//create a LSMP record for this purpose and extract the same

List<Id> lsmpIds= new List<Id>();
LifeSciMarketableProduct lsmpBrand = new LifeSciMarketableProduct(
        Name= 'Product for Restriction Brand',
        Type= 'Brand',
        IsActive= true
    );
    lsmpToInsert.add(lsmpBrand);

    LifeSciMarketableProduct lsmpIndication = new LifeSciMarketableProduct(
        Name= 'Product for Restriction Indication',
        Type= 'Indication',
        IsActive= true
    );
    lsmpToInsert.add(lsmpIndication);

    LifeSciMarketableProduct lsmpTA = new LifeSciMarketableProduct(
        Name= 'Product for Restriction TherapeuticArea',
        Type= 'TherapeuticArea',
        IsActive= true
    );
    lsmpToInsert.add(lsmpTA);

    insert lsmpToInsert;

    for(LifeSciMarketableProduct lsmp:lsmpToInsert)
    {
        Id lsmpId;
        try {
                lsmpIds.add(lsmp.ID);
        } catch (DmlException e) {
            System.debug('Error inserting LifeSciMarketableProduct record: ' + e.getMessage());
        }
    
    }
    System.debug('======lsmpIds records size'+lsmpIds.size());

// check if lsmpId is not null and a LSMP record is created then only create the LSPAR records 
List<LifeSciProductAcctRstrc> lsparToInsert;
if(lsmpToInsert.size()>0)
    {
        lsparToInsert = new List<LifeSciProductAcctRstrc>();

        for(ProviderAcctTerritoryInfo lsProduct: accountTerritories)
        {
            for(LifeSciMarketableProduct lsmp :lsmpToInsert)
            {
                
                LifeSciProductAcctRstrc lspar=new LifeSciProductAcctRstrc(
                ProductId= lsmp.Id,
                AccountId=lsProduct.AccountId,
                TerritoryId=lsProduct.Territory2Id
            );
            lsparToInsert.add(lspar);
            }
        }

        // Insert the LifeSciProductAcctRstrc records
        if (!lsparToInsert.isEmpty()) {
            try {
                insert lsparToInsert;
                System.debug('======lsparToInsert success');

            } catch (DmlException e) {
                // Handle any DML exceptions, such as logging or error reporting
                System.debug('Error inserting LifeSciProductAcctRstrc records: ' + e.getMessage());
                for (Integer i = 0; i < e.getNumDml(); i++) {
                    System.debug('DML error ' + i + ': ' + e.getDmlMessage(i));
                }
            }
        } else {
            System.debug('No LifeSciProductAcctRstrc records to insert.');
        }
}
else
{
    System.debug('Error creating LifeSciMarketableProduct,hence no LifeSciProductAcctRstrc were inserted');

}


// Share LifeSciProductAcctRstrc records with territories

 // List<LifeSciProductAcctRstrc> lsparToInsert = [SELECT Id, TerritoryId FROM LifeSciProductAcctRstrc];

// Get Aurora territory ID
Id auroraTerritoryId = [SELECT Id FROM Territory2 WHERE DeveloperName = 'TMSPCAurora20A02T06' LIMIT 1].Id;

// Get Group IDs for territories
Set<Id> territoryIds = new Set<Id>();
for(LifeSciProductAcctRstrc lspar : lsparToInsert) {
    if(lspar.TerritoryId != null) {
        territoryIds.add(lspar.TerritoryId);
    }
}

Map<Id, Id> territoryToGroupIdMap = new Map<Id, Id>();
if(!territoryIds.isEmpty()) {
    for(Group g : [SELECT Id, RelatedId FROM Group WHERE Type = 'Territory' AND RelatedId IN :territoryIds]) {
        territoryToGroupIdMap.put(g.RelatedId, g.Id);
    }
}

List<LifeSciProductAcctRstrcShare> acctRstrcShareToInsert = new List<LifeSciProductAcctRstrcShare>();

for(LifeSciProductAcctRstrc lspar : lsparToInsert) {
    LifeSciProductAcctRstrcShare acctRstrcShare = new LifeSciProductAcctRstrcShare(
        ParentId = lspar.Id,
        UserOrGroupId = lspar.TerritoryId !=null ? territoryToGroupIdMap.get(lspar.TerritoryId) : territoryToGroupIdMap.get(auroraTerritoryId),
        AccessLevel = 'Read'
    );
    acctRstrcShareToInsert.add(acctRstrcShare);
}

if(!acctRstrcShareToInsert.isEmpty()) {
    try {
        insert acctRstrcShareToInsert;
        System.debug('Successfully shared LifeSciProductAcctRstrc records with territories');
    } catch(Exception e) {
        System.debug('Error sharing LifeSciProductAcctRstrc records: ' + e.getMessage());
    }
}


