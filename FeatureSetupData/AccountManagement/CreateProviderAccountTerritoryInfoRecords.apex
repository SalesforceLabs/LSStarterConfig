// Write a script that creates ProviderAccountTerritoryInfo records for all accounts in the Org and for these territories 'TMSPCAurora20A02T06', 'TMSPCChico20D02T14' , 'TMSPCAkron20A06T14'
List<ProviderAcctTerritoryInfo> paRecords = new List<ProviderAcctTerritoryInfo>();
List<Account> accounts = [SELECT Id FROM Account];
List<Territory2> territories = [SELECT Id FROM Territory2 WHERE DeveloperName IN ('TMSPCAurora20A02T06')];

for (Account account : accounts) {
    for (Territory2 territory : territories) {
        ProviderAcctTerritoryInfo pa = new ProviderAcctTerritoryInfo(
            AccountId = account.Id,
            Territory2Id = territory.Id,
            IsAvailableOffline = true
        );
        paRecords.add(pa);
    }
}

if (!paRecords.isEmpty()) {
    try {
        insert paRecords;
        System.debug('Inserted ' + paRecords.size() + ' records');
    } catch(Exception e) {
        System.debug('Error: ' + e.getMessage());
    }
}


// delete all ProviderAcctTerritoryInfo records
// delete [SELECT Id FROM ProviderAcctTerritoryInfo];