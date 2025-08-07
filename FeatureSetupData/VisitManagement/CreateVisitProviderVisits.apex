Map<Id, List<Id>> AccsByTerrsMap = new Map<Id, List<Id>>();
List<Visit> visitsToInsert = new List<Visit>();
List<ProviderVisit> providerVisitsToInsert = new List<ProviderVisit>();
List<ContactPointAddress> AccAddress = new List<ContactPointAddress> {};
Map<Id, Id> accAddrByAcc = new Map<Id, Id> {};

List<ProviderAcctTerritoryInfo> accountsByTerritories = [SELECT Territory2Id, AccountId
                                                            FROM ProviderAcctTerritoryInfo
                                                            WHERE Territory2.DeveloperName = 'TMSPCAurora20A02T06'
                                                            ORDER BY Territory2Id, AccountId];

for (ProviderAcctTerritoryInfo accByTerr :  accountsByTerritories) {
    ContactPointAddress accAddr = new ContactPointAddress(Name = 'TestContactPointAddress', ParentId = accByTerr.AccountId);
    AccAddress.add(accAddr);
    if (AccsByTerrsMap.containsKey(accByTerr.Territory2Id)) {
        List<Id> accs = AccsByTerrsMap.get(accByTerr.Territory2Id);
        if (accs.size() < 5) {
            accs.add(accByTerr.AccountId);
            AccsByTerrsMap.put(accByTerr.Territory2Id, accs);
        } else {
            continue;
        }
    } else {
        List<Id> accs= new List<Id>{accByTerr.AccountId};
        AccsByTerrsMap.put(accByTerr.Territory2Id, accs);
    }
}

insert AccAddress;
for (ContactPointAddress addr : AccAddress) {
    accAddrByAcc.put(addr.ParentId, addr.Id);
}

System.debug('Account Addresses: ' + accAddrByAcc);

for (Id key : AccsByTerrsMap.keyset()) {
    List<Id> accounts = AccsByTerrsMap.get(key);
    for (Id accId : accounts) {
        Visit visit1 = new Visit(PlaceId = accAddrByAcc.get(accId), AccountId = accId, TerritoryId = key, PlannedVisitStartTime = DateTime.now(), Status = 'Completed');
        visitsToInsert.add(visit1);
        Visit visit2 = new Visit(PlaceId = accAddrByAcc.get(accId), AccountId = accId, TerritoryId = key, PlannedVisitStartTime = DateTime.now().addDays(1), Status = 'Planned');
        visitsToInsert.add(visit2);
    }
}
insert visitsToInsert;

for (Visit visit : visitsToInsert) {
    ProviderVisit providerVisit = new ProviderVisit(VisitId = visit.Id);
    providerVisitsToInsert.add(providerVisit);
}

insert providerVisitsToInsert;

// Share visits and provider visits with aurora territory
List<VisitShare> visitShares = new List<VisitShare>();
List<ProviderVisitShare> providerVisitShares = new List<ProviderVisitShare>();

// List<Visit> visitsToInsert = [Select Id, TerritoryId from Visit];
// List<ProviderVisit> providerVisitsToInsert = [Select Id, Visit.TerritoryId from ProviderVisit];

// Get Aurora territory ID
Id auroraTerritoryId = [SELECT Id FROM Territory2 WHERE DeveloperName = 'TMSPCAurora20A02T06' LIMIT 1].Id;

// Get the territory-related group instead of territory ID
Id groupId = [SELECT Id FROM Group WHERE Type = 'Territory' AND RelatedId = :auroraTerritoryId LIMIT 1].Id;

// Share visits with Aurora territory
for(Visit visit : visitsToInsert) {
    VisitShare auroraVisitShare = new VisitShare(
        ParentId = visit.Id,
        UserOrGroupId = groupId,
        AccessLevel = 'Edit',
        RowCause = 'Manual'
    );
    visitShares.add(auroraVisitShare);
}

// Share provider visits with Aurora territory 
for(ProviderVisit provVisit : providerVisitsToInsert) {
    ProviderVisitShare auroraProvVisitShare = new ProviderVisitShare(
        ParentId = provVisit.Id,
        UserOrGroupId = groupId,
        AccessLevel = 'Edit',
        RowCause = 'Manual'
    );
    providerVisitShares.add(auroraProvVisitShare);
}

try {
    if (!visitShares.isEmpty()) {
        insert visitShares;
    }
    if (!providerVisitShares.isEmpty()) {
        insert providerVisitShares;
    }
} catch (Exception e) {
    System.debug('Error sharing records: ' + e.getMessage());
}
