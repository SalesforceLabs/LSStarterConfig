
//***********************************************************************************************************************************************
//*   Prerequisites for running this script: Territory model which has been defined in TerritoryHierarchy-plan.json should be made active.      *
//***********************************************************************************************************************************************

String territoryName = 'RDMidwest20A';

Contact contact = new Contact(FirstName='Charles', LastName='Green');

insert contact;

Territory2 terr1 = [select Id from Territory2 where DeveloperName=:territoryName];

// create record alerts

Date futureDate = Date.today().addDays(7);

RecordAlert ra1 = new RecordAlert(
    Subject = 'New Important Update',
    Description = 'Please complete your month end inventory count assessment.',
    EffectiveDate = Date.newInstance(2025, 2, 2),
    ValidUntilDate = futureDate,
    IsActive = true,
    Type = 'Notification',
    WhatId = contact.Id
);

RecordAlert ra2 = new RecordAlert(
    Subject = 'You\'ve been added to a new Territory',
    Description = 'You\'ve been added to a new Territory RD - Midwest 20A',
    EffectiveDate = Date.newInstance(2025, 2, 2),
    ValidUntilDate = futureDate,
    IsActive = true,
    Type = 'Notification',
    WhatId = contact.Id
);

List<RecordAlert> recordAlerts = new List<RecordAlert>{ra1, ra2};

insert recordAlerts;

// create app alert territories

AppAlertTerritory at1 = new AppAlertTerritory(
    AlertReferenceRecordId = ra1.Id,
    TerritoryId = terr1.Id
);

AppAlertTerritory at2 = new AppAlertTerritory(
    AlertReferenceRecordId = ra2.Id,
    TerritoryId = terr1.Id
);

List<AppAlertTerritory> appAlertTerritories = new List<AppAlertTerritory>{at1, at2};

insert appAlertTerritories;