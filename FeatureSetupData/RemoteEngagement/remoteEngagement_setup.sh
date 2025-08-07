#!/bin/bash
set -e

echo "Running Remote Engagement Setup"

echo "============================================ PREREQUISITES ===================================================="
echo "Before running this script, ensure the following are configured:"
echo "1. Make sure digital experiences is enabled. If not, go to Setup/Digital Experiences/Settings, and enable 'Enable Digital Experiences'."
echo "   Otherwise, there will be an error: Communities must be enabled before deploying a Chatter Network Site"
echo "2. Make sure 'Enable ExperienceBundle Metadata API' is enabled."
echo "   If not, after enabling digital experiences, go to Setup/Digital Experiences/Settings again and enable 'Enable ExperienceBundle Metadata API'."
echo "   Switch to classic before enabling this, otherwise it does not seem to save properly. Make sure the setting is enabled. If not, go to Setup/Digital Experiences/Settings and enable it."
echo "3. LifeSciConfigRecord with VideoCallInvitationUrl field needs to exist on the org."
echo "   data_load.sh script deploys the config records, including VideoCallSettings_Twilio.lifeSciConfigRecord."
echo "   Either run data_load.sh or go to Admin Console/Remote Engagement/Settings, enter settings values, a dummy url for Video Call Invitation Link, and save."
echo "   If adding settings on Admin Console, make sure that Channel field on Visit entity has picklist values" 
echo "   so that Remote Visit Channel field on the admin console Settings page has values to pick from."
echo "================================================================================================================"

SITE_NAME="hcps"

COMMUNITY_STATUS=$(sf data query --query "SELECT Status FROM Network WHERE Name = '$SITE_NAME'" --json 2>/dev/null | jq -r '.result.records[0].Status' 2>/dev/null || echo "NOT_FOUND")

if [ "$COMMUNITY_STATUS" = "Live" ]; then
    echo "Experience site $SITE_NAME already exists"
else
    echo "Creating $SITE_NAME experience site"
    sf community create --name $SITE_NAME --template-name 'Build Your Own' --url-path-prefix $SITE_NAME

    # Wait for community to be fully created before proceeding
    echo "Waiting for experience site to be fully created..."
    sleep 10

    # Poll for community readiness
    echo "Checking experience site status..."
    MAX_ATTEMPTS=10
    ATTEMPT=1
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Checking if experience site is ready..."
        
        # Check if the community exists and is active
        COMMUNITY_STATUS=$(sf data query --query "SELECT Status FROM Network WHERE Name = '$SITE_NAME'" --json 2>/dev/null | jq -r '.result.records[0].Status' 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$COMMUNITY_STATUS" = "Live" ]; then
            echo "Experience site is ready!"
            break
        elif [ "$COMMUNITY_STATUS" = "NOT_FOUND" ] || [ -z "$COMMUNITY_STATUS" ] || [ "$COMMUNITY_STATUS" = "null" ]; then
            echo "Experience site not found yet, waiting..."
        else
            echo "Experience site status: $COMMUNITY_STATUS, waiting..."
        fi
        
        if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
            echo "Warning: Experience site may not be fully ready, but proceeding anyway..."
        fi
        
        sleep 10
        ATTEMPT=$((ATTEMPT + 1))
    done
fi

# set the user name in site metadata
USER_NAME=$(sf org display --json | jq -r '.result.username')
sed -i '' "s|%userName%|$USER_NAME|g" FeatureSetupData/RemoteEngagement/experienceSite/sites/$SITE_NAME.site-meta.xml
# set the email address in network metadata
EMAIL_ADDRESS=$(sf data query --query "SELECT Email FROM User WHERE Username = '$USER_NAME'" --json | jq -r '.result.records[0].Email')
sed -i '' "s|%emailAddress%|$EMAIL_ADDRESS|g" FeatureSetupData/RemoteEngagement/experienceSite/networks/$SITE_NAME.network-meta.xml

# deploy metadata for digital experience site "$SITE_NAME"
sf project deploy start -d FeatureSetupData/RemoteEngagement/experienceSite --ignore-conflicts

# publish the site
echo "Publishing $SITE_NAME site"
sf community publish --name $SITE_NAME

# replace the user name and email address in the site and network metadata back with the placeholders %userName% and %emailAddress%
sed -i '' "s|$USER_NAME|%userName%|g" FeatureSetupData/RemoteEngagement/experienceSite/sites/$SITE_NAME.site-meta.xml
sed -i '' "s|$EMAIL_ADDRESS|%emailAddress%|g" FeatureSetupData/RemoteEngagement/experienceSite/networks/$SITE_NAME.network-meta.xml

# create terms and conditions library and document
sf apex run --file FeatureSetupData/RemoteEngagement/TermsAndConditionsLibrary.apex
sf apex run --file FeatureSetupData/RemoteEngagement/TermsAndConditionsDocument.apex

# update invitation url in config settings
SITE_ID=$(sf data query --query "SELECT Id FROM Site WHERE Name = '${SITE_NAME}1'" --json | jq -r '.result.records[0].Id')
SITE_URL=$(sf data query --query "SELECT SecureUrl FROM SiteDetail WHERE DurableId = '$SITE_ID'" --json | jq -r '.result.records[0].SecureUrl')
VIDEO_CALL_URL="${SITE_URL}/video-call"
echo "Site id is $SITE_ID, site url is $SITE_URL, video call invitation url is $VIDEO_CALL_URL"

CONFIG_FIELD_RECORD_ID=$(sf data query --query "SELECT Id FROM LifeSciConfigFieldValue WHERE FieldName = 'VideoCallInvitationUrl'" --use-tooling-api --json | jq -r '.result.records[0].Id')
echo "Found config field record for VideoCallInvitationUrl, id is $CONFIG_FIELD_RECORD_ID"

sf data update record --sobject LifeSciConfigFieldValue --record-id $CONFIG_FIELD_RECORD_ID --values "UrlValue=$VIDEO_CALL_URL" --use-tooling-api
echo "Updated VideoCallInvitationUrl to $VIDEO_CALL_URL"

#assign permission set to the guest user
GUEST_USER_NAME=$(sf data query --query "SELECT Username FROM User WHERE Name = '${SITE_NAME} Site Guest User'" --json | jq -r '.result.records[0].Username')
sf org permset assign -n AccessRemoteEngagementTwilioDigitalExperience -b $GUEST_USER_NAME
echo "Assigned AccessRemoteEngagementTwilioDigitalExperience permission set to guest user $GUEST_USER_NAME"

echo "Remote Engagement Setup completed successfully!"
exit 0
