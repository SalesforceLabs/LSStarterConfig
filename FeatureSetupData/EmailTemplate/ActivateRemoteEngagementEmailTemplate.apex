
// Get all LifeSciEmailTemplate records
List<LifeSciEmailTemplate> lifeSciEmailTemplates = [SELECT Id, IsActive FROM LifeSciEmailTemplate WHERE Name IN ('Create Remote Engagement Email Template', 'Update Remote Engagement Email Template','Cancel Remote Engagement Email Template')];

// Update IsActive to true for all records
for (LifeSciEmailTemplate template : lifeSciEmailTemplates) {
    template.IsActive = true;
}

// Update the records
try {
    update lifeSciEmailTemplates;
} catch (Exception e) {
    System.debug('Error updating records: ' + e.getMessage());
}



