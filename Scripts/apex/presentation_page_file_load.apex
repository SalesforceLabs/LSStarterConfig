//Map file names to ContentDocument Ids
Map<String, Id> fileMap = new Map<String, Id>();
for (ContentDocument file : [SELECT Id, Title, FileExtension FROM ContentDocument]) {
    fileMap.put(file.Title + '.' + file.FileExtension, file.Id);
}

//Map presentation page names to Ids
Map<String, Id> pageMap = new Map<String, Id>();
for (PresentationPage page : [SELECT Id, Name FROM PresentationPage]) {
    pageMap.put(page.Name, page.Id);
}

//Relate the files to the presentation pages
List<ContentDocumentLink> linkList = new List<ContentDocumentLink>();
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('01_Patients with arterial hypertension.pdf'), LinkedEntityId = pageMap.get('Patients with arterial hypertension'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('01_Patients with arterial hypertension.zip'), LinkedEntityId = pageMap.get('Patients with arterial hypertension'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('01_thumbnail.jpg'), LinkedEntityId = pageMap.get('Patients with arterial hypertension'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('02_Risks and prevalence.pdf'), LinkedEntityId = pageMap.get('Risks and prevalence'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('02_Risks and prevalence.zip'), LinkedEntityId = pageMap.get('Risks and prevalence'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('02_thumbnail.jpg'), LinkedEntityId = pageMap.get('Risks and prevalence'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('03_Graph.pdf'), LinkedEntityId = pageMap.get('Graph'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('03_Graph.zip'), LinkedEntityId = pageMap.get('Graph'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('03_thumbnail.jpg'), LinkedEntityId = pageMap.get('Graph'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('04_thumbnail.jpg'), LinkedEntityId = pageMap.get('Video'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('04_Video.pdf'), LinkedEntityId = pageMap.get('Video'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('04_Video.zip'), LinkedEntityId = pageMap.get('Video'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('pdf_thumbnail_01.jpg'), LinkedEntityId = pageMap.get('LSC4CE Dev Guide Page 1'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('Life Sciences Cloud Customer Engagement Developer Guide (Pilot).pdf'), LinkedEntityId = pageMap.get('LSC4CE Dev Guide Page 1'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('pdf_thumbnail_02.jpg'), LinkedEntityId = pageMap.get('LSC4CE Dev Guide Page 2'), ShareType = 'I'));
linkList.add(new ContentDocumentLink(ContentDocumentId = fileMap.get('pdf_thumbnail_03.jpg'), LinkedEntityId = pageMap.get('LSC4CE Dev Guide Page 3'), ShareType = 'I'));

insert linkList;

//Rename all thumbnails to thumbnail.jpg (convention)
for (List<ContentDocument> thumbnails : [SELECT Id, Title FROM ContentDocument WHERE Title LIKE '%thumbnail%']) {
    for (ContentDocument thumbnail : thumbnails) {
        thumbnail.title = 'thumbnail';
    }
    update thumbnails;
}
