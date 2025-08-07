// Script to create PresentationPage records with ContentDocumentIds
// This script should be run after ContentVersions have been loaded

// Get all ContentVersions created for ActivityHistory
List<ContentVersion> contentVersions = [
    SELECT Id, ContentDocumentId, Title, PathOnClient
    FROM ContentVersion 
    WHERE Title IN (
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
    ORDER BY Title
];

// Create mapping between ContentVersion titles and ContentDocumentIds
Map<String, Id> titleToContentDocumentId = new Map<String, Id>();
for (ContentVersion cv : contentVersions) {
    titleToContentDocumentId.put(cv.Title, cv.ContentDocumentId);
}

// Create PresentationPage records with ContentDocumentId
List<PresentationPage> pagesToCreate = new List<PresentationPage>();

// ZIP type pages
if (titleToContentDocumentId.containsKey('Product Introduction and Overview')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Product Introduction and Overview',
        Type = 'ZIP',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Product Introduction and Overview'),
        ActivationDate = DateTime.newInstance(2024, 1, 1, 8, 0, 0),
        DeactivationDate = DateTime.newInstance(2024, 12, 31, 23, 59, 59)
    ));
}

if (titleToContentDocumentId.containsKey('Clinical Efficacy Data')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Clinical Efficacy Data',
        Type = 'ZIP',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Clinical Efficacy Data'),
        ActivationDate = DateTime.newInstance(2024, 1, 1, 8, 0, 0),
        DeactivationDate = DateTime.newInstance(2024, 12, 31, 23, 59, 59)
    ));
}

if (titleToContentDocumentId.containsKey('Safety Profile and Monitoring')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Safety Profile and Monitoring',
        Type = 'ZIP',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Safety Profile and Monitoring'),
        ActivationDate = DateTime.newInstance(2024, 1, 1, 8, 0, 0),
        DeactivationDate = DateTime.newInstance(2024, 12, 31, 23, 59, 59)
    ));
}

// PDF type pages
if (titleToContentDocumentId.containsKey('Phase III Trial Results Summary')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Phase III Trial Results Summary',
        Type = 'PDF',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Phase III Trial Results Summary'),
        PageNumber = 1,
        ActivationDate = DateTime.newInstance(2024, 1, 15, 9, 0, 0),
        DeactivationDate = DateTime.newInstance(2024, 12, 31, 23, 59, 59)
    ));
}

if (titleToContentDocumentId.containsKey('Real-World Evidence Analysis')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Real-World Evidence Analysis',
        Type = 'PDF',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Real-World Evidence Analysis'),
        PageNumber = 2,
        ActivationDate = DateTime.newInstance(2024, 1, 15, 9, 0, 0),
        DeactivationDate = DateTime.newInstance(2024, 12, 31, 23, 59, 59)
    ));
}

if (titleToContentDocumentId.containsKey('Comparative Effectiveness Research')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Comparative Effectiveness Research',
        Type = 'PDF',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Comparative Effectiveness Research'),
        PageNumber = 3,
        ActivationDate = DateTime.newInstance(2024, 1, 15, 9, 0, 0),
        DeactivationDate = DateTime.newInstance(2024, 12, 31, 23, 59, 59)
    ));
}

// ZIP type pages for third presentation
if (titleToContentDocumentId.containsKey('Disease Pathophysiology Overview')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Disease Pathophysiology Overview',
        Type = 'ZIP',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Disease Pathophysiology Overview'),
        ActivationDate = DateTime.newInstance(2024, 2, 1, 10, 0, 0),
        DeactivationDate = DateTime.newInstance(2025, 1, 31, 23, 59, 59)
    ));
}

if (titleToContentDocumentId.containsKey('Treatment Guidelines and Protocols')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Treatment Guidelines and Protocols',
        Type = 'ZIP',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Treatment Guidelines and Protocols'),
        ActivationDate = DateTime.newInstance(2024, 2, 1, 10, 0, 0),
        DeactivationDate = DateTime.newInstance(2025, 1, 31, 23, 59, 59)
    ));
}

if (titleToContentDocumentId.containsKey('Patient Care Best Practices')) {
    pagesToCreate.add(new PresentationPage(
        Name = 'Patient Care Best Practices',
        Type = 'ZIP',
        Status = 'Active',
        ContentDocumentId = titleToContentDocumentId.get('Patient Care Best Practices'),
        ActivationDate = DateTime.newInstance(2024, 2, 1, 10, 0, 0),
        DeactivationDate = DateTime.newInstance(2025, 1, 31, 23, 59, 59)
    ));
}

// Insert the PresentationPages
if (!pagesToCreate.isEmpty()) {
    insert pagesToCreate;
    System.debug('Successfully created ' + pagesToCreate.size() + ' PresentationPages with ContentDocuments');
    
    // Print the mappings for verification
    for (PresentationPage page : pagesToCreate) {
        System.debug('Created PresentationPage: ' + page.Name + ' with ContentDocument: ' + page.ContentDocumentId);
    }
} else {
    System.debug('No PresentationPages created - ContentVersions not found or mapping failed');
}

System.debug('PresentationPage creation with ContentDocuments completed'); 