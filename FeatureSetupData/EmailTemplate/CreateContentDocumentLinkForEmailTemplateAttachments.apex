// Get remote engagement related ContentDocumentLink records
List<ContentDocumentLink> contentDocumentLinks = [SELECT Id, ContentDocumentId FROM ContentDocumentLink 
    WHERE LinkedEntityId IN (SELECT Id FROM LifeSciEmailTmplSnapshot WHERE FileName IN ('RemoteEngagementCreateEmail', 'RemoteEngagementCancelEmail','RemoteEngagementUpdateEmail'))];

String fileName = '';

if (contentDocumentLinks.isEmpty()) {
    fileName = 'RemoteEngagementCancelEmail';
} else  if(contentDocumentLinks.size() == 2){
    fileName = 'RemoteEngagementCreateEmail';
} else {
    fileName = 'RemoteEngagementUpdateEmail';
}

// Get remote engagement related LifeSciEmailTmplSnapshot records
List<LifeSciEmailTmplSnapshot> lifeSciEmailTmplSnapshots = [SELECT Id, FileName FROM LifeSciEmailTmplSnapshot WHERE FileName =:fileName];

// Get remote engagement related ContentDocument thumbnail and index records
List<ContentDocument> contentDocuments= [SELECT Id, Title FROM ContentDocument WHERE Title IN ('thumbnail', 'index')];





Map<String, Boolean> contentDocumentLinkMap = new Map<String, Boolean>();

for(ContentDocumentLink contentDocumentLink : contentDocumentLinks) {
    contentDocumentLinkMap.put(contentDocumentLink.ContentDocumentId, true);
}



// Create ContentDocumentLink records for each remote engagement related LifeSciEmailTmplSnapshot and ContentDocument
for(LifeSciEmailTmplSnapshot lifeSciEmailTmplSnapshot : lifeSciEmailTmplSnapshots) {
    for(ContentDocument contentDocument : contentDocuments) {
        if (contentDocumentLinkMap.containsKey(contentDocument.Id)) {
            continue;
        }
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink(
            ContentDocumentId = contentDocument.Id,
            LinkedEntityId = lifeSciEmailTmplSnapshot.Id,
            ShareType = 'I'
        );
        insert contentDocumentLink;
    }
}