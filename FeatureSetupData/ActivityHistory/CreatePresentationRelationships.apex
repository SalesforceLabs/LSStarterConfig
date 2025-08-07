// Script to create Presentation relationships after PresentationPages have been created
// This script should be run after PresentationPages have been created via the previous script

// Get all PresentationPages created today
List<PresentationPage> presentationPages = [
    SELECT Id, Name, Type
    FROM PresentationPage 
    WHERE Name IN (
        'Product Introduction and Overview',
        'Clinical Efficacy Data',
        'Safety Profile and Monitoring',
        'Phase III Trial Results Summary',
        'Real-World Evidence Analysis',
        'Comparative Effectiveness Research',
        'Disease Pathophysiology Overview',
        'Treatment Guidelines and Protocols',
        'Patient Care Best Practices'
    )
    AND CreatedDate = TODAY
    ORDER BY Name
];

// Get all Visits created today for PresentationForum references
List<Visit> visits = [
    SELECT Id, Name
    FROM Visit
    WHERE CreatedDate = TODAY
    ORDER BY Id
];

// Get ProviderVisit for reference
List<ProviderVisit> providerVisits = [
    SELECT Id
    FROM ProviderVisit
    WHERE CreatedDate = TODAY
    LIMIT 1
];

// Create mapping between page names and IDs
Map<String, Id> pageNameToId = new Map<String, Id>();
for (PresentationPage page : presentationPages) {
    pageNameToId.put(page.Name, page.Id);
}

// Create Presentations
List<Presentation> presentationsToCreate = new List<Presentation>();

presentationsToCreate.add(new Presentation(
    Name = 'Sample Medicine A Product Presentation',
    Status = 'Active',
    Type = 'ZIP',
    CanSendByEmail = true,
    ActivationDate = Date.newInstance(2024, 1, 1),
    DeactivationDate = Date.newInstance(2024, 12, 31),
    IsCustom = false,
    Version = '1.0'
));

presentationsToCreate.add(new Presentation(
    Name = 'Sample Medicine B Clinical Trial Results',
    Status = 'Active',
    Type = 'PDF',
    CanSendByEmail = true,
    ActivationDate = Date.newInstance(2024, 1, 15),
    DeactivationDate = Date.newInstance(2024, 12, 31),
    IsCustom = false,
    Version = '2.1'
));

presentationsToCreate.add(new Presentation(
    Name = 'Healthcare Provider Education Series',
    Status = 'Active',
    Type = 'ZIP',
    CanSendByEmail = false,
    ActivationDate = Date.newInstance(2024, 2, 1),
    DeactivationDate = Date.newInstance(2025, 1, 31),
    IsCustom = true,
    Version = '3.0'
));

// Insert Presentations
insert presentationsToCreate;
System.debug('Created ' + presentationsToCreate.size() + ' Presentations');

// Create PresentationLinkedPage records
List<PresentationLinkedPage> linkedPagesToCreate = new List<PresentationLinkedPage>();

// Presentation 1 - Sample Medicine A Product Presentation
if (pageNameToId.containsKey('Product Introduction and Overview')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[0].Id,
        PresentationPageId = pageNameToId.get('Product Introduction and Overview'),
        DisplayOrder = 1
    ));
}

if (pageNameToId.containsKey('Clinical Efficacy Data')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[0].Id,
        PresentationPageId = pageNameToId.get('Clinical Efficacy Data'),
        DisplayOrder = 2
    ));
}

if (pageNameToId.containsKey('Safety Profile and Monitoring')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[0].Id,
        PresentationPageId = pageNameToId.get('Safety Profile and Monitoring'),
        DisplayOrder = 3
    ));
}

// Presentation 2 - Sample Medicine B Clinical Trial Results
if (pageNameToId.containsKey('Phase III Trial Results Summary')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[1].Id,
        PresentationPageId = pageNameToId.get('Phase III Trial Results Summary'),
        DisplayOrder = 1
    ));
}

if (pageNameToId.containsKey('Real-World Evidence Analysis')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[1].Id,
        PresentationPageId = pageNameToId.get('Real-World Evidence Analysis'),
        DisplayOrder = 2
    ));
}

if (pageNameToId.containsKey('Comparative Effectiveness Research')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[1].Id,
        PresentationPageId = pageNameToId.get('Comparative Effectiveness Research'),
        DisplayOrder = 3
    ));
}

// Presentation 3 - Healthcare Provider Education Series
if (pageNameToId.containsKey('Disease Pathophysiology Overview')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[2].Id,
        PresentationPageId = pageNameToId.get('Disease Pathophysiology Overview'),
        DisplayOrder = 1
    ));
}

if (pageNameToId.containsKey('Treatment Guidelines and Protocols')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[2].Id,
        PresentationPageId = pageNameToId.get('Treatment Guidelines and Protocols'),
        DisplayOrder = 2
    ));
}

if (pageNameToId.containsKey('Patient Care Best Practices')) {
    linkedPagesToCreate.add(new PresentationLinkedPage(
        PresentationId = presentationsToCreate[2].Id,
        PresentationPageId = pageNameToId.get('Patient Care Best Practices'),
        DisplayOrder = 3
    ));
}

// Insert PresentationLinkedPage records
if (!linkedPagesToCreate.isEmpty()) {
    insert linkedPagesToCreate;
    System.debug('Created ' + linkedPagesToCreate.size() + ' PresentationLinkedPages');
}

// Create PresentationForum records
List<PresentationForum> forumsToCreate = new List<PresentationForum>();

if (visits.size() >= 3) {
    forumsToCreate.add(new PresentationForum(
        PresentationId = presentationsToCreate[0].Id,
        ForumReferenceId = visits[0].Id
    ));
    
    forumsToCreate.add(new PresentationForum(
        PresentationId = presentationsToCreate[1].Id,
        ForumReferenceId = visits[0].Id
    ));
    
    forumsToCreate.add(new PresentationForum(
        PresentationId = presentationsToCreate[0].Id,
        ForumReferenceId = visits[1].Id
    ));
    
    forumsToCreate.add(new PresentationForum(
        PresentationId = presentationsToCreate[2].Id,
        ForumReferenceId = visits[2].Id
    ));
    
    forumsToCreate.add(new PresentationForum(
        PresentationId = presentationsToCreate[1].Id,
        ForumReferenceId = visits[2].Id
    ));
}

// Insert PresentationForum records
if (!forumsToCreate.isEmpty()) {
    insert forumsToCreate;
    System.debug('Created ' + forumsToCreate.size() + ' PresentationForums');
}

System.debug('Presentation relationships creation completed'); 