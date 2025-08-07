#!/bin/bash
set -e

echo "Running Data Load"

# Check if the directory exists, create it if it doesn't
if [ ! -d "FeatureSetupData/tmp" ]; then
    mkdir -p "FeatureSetupData/tmp"
    echo "Created directory FeatureSetupData/tmp"
fi

# Clear the recordMappings.json file
echo "Clearing recordMappings.json file"
# Use the directory of the script as reference
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
echo "{}" > "$SCRIPT_DIR/../../FeatureSetupData/tmp/recordMappings.json"

# Assign HealthCloudStarter permset to current user
sf org assign permset -n HealthCloudStarter

#deploy 2GP package components
sf project deploy start -d PackageComponents

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "jq could not be found. Please install jq to proceed (brew install jq)."
  exit 1
fi

#retrieve record type id and save developername to id map.
echo "Starting - sh Scripts/sh/utils/create_mapping.sh..."
sh Scripts/sh/utils/create_mapping.sh "SELECT Id, Name, SobjectType, DeveloperName FROM RecordType WHERE SobjectType IN ('Account','PersonAccount','HealthCareProvider','Product2')" SobjectType Id FeatureSetupData/tmp/recordTypeMapping.json DeveloperName

#resolve references in Account.json and HealthCareProvider.json file
echo "Starting - Scripts/sh/utils/replace_onDemand.sh FeatureSetupData/tmp/recordTypeMapping.json..."
sh Scripts/sh/utils/replace_onDemand.sh FeatureSetupData/tmp/recordTypeMapping.json FeatureSetupData/Core/Account.json FeatureSetupData/Core/HealthcareProvider.json FeatureSetupData/Core/Product2.json

#import Core data
echo "Starting - Scripts/sh/utils/load_tree_save_mappings.sh FeatureSetupData/Core/Core-plan.json"
sh Scripts/sh/utils/load_tree_save_mappings.sh FeatureSetupData/Core/Core-plan.json

#Add current user ID to recordMappings.json
echo "Starting - sh Scripts/sh/utils/add_current_user_mapping.sh"
sh Scripts/sh/utils/add_current_user_mapping.sh

#resolve core references
echo "Starting - sh Scripts/sh/utils/replace_references.sh"
sh Scripts/sh/utils/replace_references.sh

#import Workflow data
echo "Starting - sf data import tree --plan FeatureSetupData/workflow/workflow-plan.json"
sf data import tree --plan FeatureSetupData/workflow/workflow-plan.json

#import TerritoryAccountScore data
echo "Starting - sf data import tree --plan FeatureSetupData/NextBestCustomer/TerritoryAccountScore-plan.json"
sf data import tree --plan FeatureSetupData/NextBestCustomer/TerritoryAccountScore-plan.json

#import AccountManagement data
echo "Starting - sf data import tree --plan FeatureSetupData/AccountManagement/AccountManagement-plan.json"
sf data import tree --plan FeatureSetupData/AccountManagement/AccountManagement-plan.json

#import KeyAccountManagement data
echo "Starting - sf data import tree --plan FeatureSetupData/KeyAccountManagement/KeyAccountManagement-plan.json"
sf data import tree --plan FeatureSetupData/KeyAccountManagement/KeyAccountManagement-plan.json

#import AppAlert data
echo "Starting - sf data import tree --plan FeatureSetupData/AppAlerts/AppAlert-plan.json"
sf data import tree --plan FeatureSetupData/AppAlerts/AppAlert-plan.json

#import ActivityHistory data
echo "Starting - sf data import tree --plan FeatureSetupData/ActivityHistory/ActivityHistory-plan-step1.json"
sf data import tree --plan FeatureSetupData/ActivityHistory/ActivityHistory-plan-step1.json

#Create Presentation Pages With Content
echo "Starting - sf apex run --file FeatureSetupData/ActivityHistory/CreatePresentationPagesWithContent.apex"
sf apex run --file FeatureSetupData/ActivityHistory/CreatePresentationPagesWithContent.apex

#Create Presentation Relationships
echo "Starting - sf apex run --file FeatureSetupData/ActivityHistory/CreatePresentationRelationships.apex"
sf apex run --file FeatureSetupData/ActivityHistory/CreatePresentationRelationships.apex

#Account merge
echo "Starting - sf data import tree --plan FeatureSetupData/AccountMerge/AccountMerge-plan.json"
sf data import tree --plan FeatureSetupData/AccountMerge/AccountMerge-plan.json

# Execute Apex scripts // Keep them before metadata related commands as it keeps breaking the data loads
echo "Starting - sf apex run --file FeatureSetupData/TerritoryManagement/AssignUserToTerritory.apex"
sf apex run --file FeatureSetupData/TerritoryManagement/AssignUserToTerritory.apex

echo "Starting - sf apex run --file FeatureSetupData/ProductManagement/ProductTerritoryAvailability.apex"
sf apex run --file FeatureSetupData/ProductManagement/ProductTerritoryAvailability.apex

echo "Starting - sf apex run --file FeatureSetupData/ProductManagement/LifeSciProductAcctRstrc.apex"
sf apex run --file FeatureSetupData/ProductManagement/LifeSciProductAcctRstrc.apex

echo "Starting - sf apex run --file FeatureSetupData/TerritoryAlignment/CreateObjectTerritory2Association.apex"
sf apex run --file FeatureSetupData/TerritoryAlignment/CreateObjectTerritory2Association.apex

echo "Starting - sf apex run --file FeatureSetupData/TerritoryManagement/ActivateTerritoryModel.apex"
sf apex run --file FeatureSetupData/TerritoryManagement/ActivateTerritoryModel.apex

echo "Starting - sf apex run --file FeatureSetupData/AccountManagement/CreateProviderAccountTerritoryInfoRecords.apex"
sf apex run --file FeatureSetupData/AccountManagement/CreateProviderAccountTerritoryInfoRecords.apex

echo "Starting - sf apex run --file FeatureSetupData/VisitManagement/CreateVisitProviderVisits.apex"
sf apex run --file FeatureSetupData/VisitManagement/CreateVisitProviderVisits.apex

echo "Starting - sf apex run --file FeatureSetupData/KeyAccountManagement/KeyAccountManDataScript.apex"
sf apex run --file FeatureSetupData/KeyAccountManagement/KeyAccountManDataScript.apex

#create remote engagement email templates
echo "Starting - sh FeatureSetupData/RemoteEngagement/create_remote_engagement_email_templates.sh"
sh FeatureSetupData/RemoteEngagement/create_remote_engagement_email_templates.sh

# Create ProductSpecificationRecType records using Tooling API
echo "Starting - sh Scripts/sh/create_product_spec_rectypes.sh"
sh Scripts/sh/create_product_spec_rectypes.sh

#import ProductManagement data
echo "Starting - sh Scripts/sh/utils/load_tree_save_mappings.sh FeatureSetupData/ProductManagement/ProductManagement-plan.json"
sh Scripts/sh/utils/load_tree_save_mappings.sh FeatureSetupData/ProductManagement/ProductManagement-plan.json
#resolve product management references
echo "Starting - sh Scripts/sh/utils/replace_references.sh"
sh Scripts/sh/utils/replace_references.sh

#import Visit data
echo "Starting - sf data import tree --plan FeatureSetupData/VisitManagement/VisitManagement-plan.json"
sf data import tree --plan FeatureSetupData/VisitManagement/VisitManagement-plan.json

#import SampleLimits data
echo "Starting - sh Scripts/sh/utils/load_tree_save_mappings.sh FeatureSetupData/SampleLimits/SampleLimits-plan.json"
sh Scripts/sh/utils/load_tree_save_mappings.sh FeatureSetupData/SampleLimits/SampleLimits-plan.json
echo "Starting - sf apex run --file FeatureSetupData/SampleLimits/ProviderSampleLimit.apex"
sf apex run --file FeatureSetupData/SampleLimits/ProviderSampleLimit.apex

#deploy LSConfig entries
#import platform BPO entries
echo "Starting - sf data import tree --plan LSConfig/lifeSciMetadataRecord/LifeSciMetadataCategory-plan.json"
sf data import tree --plan LSConfig/lifeSciMetadataRecord/LifeSciMetadataCategory-plan.json
#deploy setup BPO entries, only works with Salesforce CLI version 2.80.4 or higher
echo "Starting - sf project deploy start -d LSConfig/lifeSciConfigRecord/1_inactive"
sf project deploy start -d LSConfig/lifeSciConfigRecord/1_inactive
echo "Starting - sf project deploy start -d LSConfig/lifeSciConfigRecord/2_activate"
sf project deploy start -d LSConfig/lifeSciConfigRecord/2_activate

#share ProductionBatch and ProductGuidance records
echo "Starting - sf apex run --file FeatureSetupData/ProductManagement/CreateProductionBatchShares.apex"
sf apex run --file FeatureSetupData/ProductManagement/CreateProductionBatchShares.apex
echo "Starting - sf apex run --file FeatureSetupData/ProductManagement/CreateProductGuidanceShares.apex"
sf apex run --file FeatureSetupData/ProductManagement/CreateProductGuidanceShares.apex

#create digital experience site for remote engagement
echo "Starting - sh FeatureSetupData/RemoteEngagement/remoteEngagement_setup.sh"
sh FeatureSetupData/RemoteEngagement/remoteEngagement_setup.sh

# Process Survey data - fetch survey IDs and resolve SurveyInvitation references
echo "Processing Survey data..."
sh Scripts/sh/utils/create_survey_mapping.sh

# Resolve survey references in both SurveyInvitation and SurveyResponseOffline JSON files
echo "Resolving survey references.."
SURVEY_MAPPING_FILE="$(pwd)/FeatureSetupData/tmp/surveyMapping.json"
sh scripts/sh/utils/replace_onDemand.sh "$SURVEY_MAPPING_FILE" "$(pwd)/FeatureSetupData/Surveys/SurveyInvitation.json"
sh scripts/sh/utils/replace_onDemand.sh "$SURVEY_MAPPING_FILE" "$(pwd)/FeatureSetupData/Surveys/SurveyResponseOffline.json"
sh scripts/sh/utils/replace_onDemand.sh "$SURVEY_MAPPING_FILE" "$(pwd)/FeatureSetupData/Surveys/SurveyQstnResponseOffline.json"

echo "Starting - sf data import tree --plan FeatureSetupData/Surveys/Survey-plan.json"
sf data import tree --plan FeatureSetupData/Surveys/Survey-plan.json
