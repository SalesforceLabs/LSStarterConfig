List<Territory2> territories = [SELECT Id FROM Territory2 where DeveloperName in ( 'TMSPCAurora20A02T06' ) ];

List<Account> accounts = [Select Id, Name from Account];

List<ObjectTerritory2Association> OT2Arecords = new List<ObjectTerritory2Association>();

for(Territory2 territory : territories) {
    for(Account account : accounts) {
        ObjectTErritory2Association ota = new ObjectTErritory2Association(ObjectId = account.Id, Territory2Id = territory.Id, AssociationCause= 'Territory2Manual');
        OT2Arecords.add(ota);
    }
}

if(!OT2Arecords.isEmpty())
    insert OT2Arecords;