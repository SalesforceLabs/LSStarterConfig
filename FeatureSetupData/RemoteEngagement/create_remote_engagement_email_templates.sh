#!/bin/bash

# create zip content documents for remote engagement email templates
sf data create file --file 'FeatureSetupData/EmailTemplate/RemoteEngagementCreateEmail.zip' --title 'RemoteEngagementCreateEmail'
sf data create file --file 'FeatureSetupData/EmailTemplate/RemoteEngagementUpdateEmail.zip' --title 'RemoteEngagementUpdateEmail'
sf data create file --file 'FeatureSetupData/EmailTemplate/RemoteEngagementCancelEmail.zip' --title 'RemoteEngagementCancelEmail'

sf apex run --file FeatureSetupData/EmailTemplate/CreateContentDocumentLinkForEmailTemplates.apex

# create related thumbnails and index for remote engagement cancel email template
sf data create file --file 'FeatureSetupData/EmailTemplate/CancelAttachment/thumbnail.jpg' --title 'thumbnail'
sf data create file --file 'FeatureSetupData/EmailTemplate/CancelAttachment/index.html' --title 'index'

# create content document link for remote engagement cancel email template
sf apex run --file FeatureSetupData/EmailTemplate/CreateContentDocumentLinkForEmailTemplateAttachments.apex


# create related thumbnails and index for remote engagement create email template
sf data create file --file 'FeatureSetupData/EmailTemplate/CreateAttachment/thumbnail.jpg' --title 'thumbnail'
sf data create file --file 'FeatureSetupData/EmailTemplate/CreateAttachment/index.html' --title 'index'

# create content document link for remote engagement create email template
sf apex run --file FeatureSetupData/EmailTemplate/CreateContentDocumentLinkForEmailTemplateAttachments.apex


# create related thumbnails and index for remote engagement update email template
sf data create file --file 'FeatureSetupData/EmailTemplate/UpdateAttachment/thumbnail.jpg' --title 'thumbnail'
sf data create file --file 'FeatureSetupData/EmailTemplate/UpdateAttachment/index.html' --title 'index'

# create content document link for remote engagement update email template
sf apex run --file FeatureSetupData/EmailTemplate/CreateContentDocumentLinkForEmailTemplateAttachments.apex

# create territory shared email template
sf apex run --file FeatureSetupData/EmailTemplate/CreateTerritorySharedEmailTemplate.apex

# activate remote engagement email template
sf apex run --file FeatureSetupData/EmailTemplate/ActivateRemoteEngagementEmailTemplate.apex