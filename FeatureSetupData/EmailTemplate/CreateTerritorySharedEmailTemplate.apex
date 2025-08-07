// Get remote engagement related LifeSciEmailTemplate records
List<LifeSciEmailTemplate> lifeSciEmailTemplates = [SELECT Id, Name FROM LifeSciEmailTemplate WHERE Name IN ('Create Remote Engagement Email Template', 'Update Remote Engagement Email Template','Cancel Remote Engagement Email Template')];

//Get TerritoryIds
Id territoryId = [SELECT Name FROM Territory2 WHERE DeveloperName IN ('DMChicago20A02') LIMIT 1].Id;

Id groupId = [SELECT Id FROM Group WHERE Type = 'Territory' AND RelatedId = :territoryId LIMIT 1].Id;

for (LifeSciEmailTemplate lifeSciEmailTemplate : lifeSciEmailTemplates) {
    LifeSciEmailTemplateShare shareRecord = new LifeSciEmailTemplateShare();
    shareRecord.ParentId = Id.valueOf(lifeSciEmailTemplate.Id);
    shareRecord.UserOrGroupId = groupId;
    shareRecord.AccessLevel = 'Edit';
    insert shareRecord;
}
