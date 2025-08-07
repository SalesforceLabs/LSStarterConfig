// WARNING: This script deletes all presentation data and related ContentDocuments

// Get a list of all ContentDocumentIds related to PresentationPage
List<Id> contentDocumentIds = new List<Id>();
for (ContentDocumentLink cdl : [select ContentDocumentId from ContentDocumentLink 
    where LinkedEntityId in (select Id from PresentationPage)]) {
    contentDocumentIds.add(cdl.ContentDocumentId);
}

delete [select id from PresentationFileReference];
delete [select id from PresentationLinkedPage];
delete [select id from PresentationPage];
delete [select id from Presentation];    

delete [select id from ContentDocument where Id in :contentDocumentIds];