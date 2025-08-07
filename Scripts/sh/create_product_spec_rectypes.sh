#!/bin/bash
set -e

echo "Creating ProductSpecificationRecType records using Tooling API..."

# Get the Record Type IDs from recordTypeMapping.json
PROMOTIONAL_ITEM_RT_ID=$(jq -r '."$Product2.Promotional_Item$"' FeatureSetupData/tmp/recordTypeMapping.json)
SAMPLE_PRODUCT_RT_ID=$(jq -r '."$Product2.Sample_Product$"' FeatureSetupData/tmp/recordTypeMapping.json)

# Check if we got valid IDs
if [[ -z "$PROMOTIONAL_ITEM_RT_ID" || "$PROMOTIONAL_ITEM_RT_ID" == "null" ]]; then
    echo "Error: Could not find Promotional_Item Record Type ID in recordTypeMapping.json"
    exit 1
fi

if [[ -z "$SAMPLE_PRODUCT_RT_ID" || "$SAMPLE_PRODUCT_RT_ID" == "null" ]]; then
    echo "Error: Could not find Sample_Product Record Type ID in recordTypeMapping.json"
    exit 1
fi

# Create the records using Tooling API
echo "Creating Promotional_Item ProductSpecificationRecType record..."
sf data create record --sobject ProductSpecificationRecType --use-tooling-api --values "DeveloperName=Promotional_Item MasterLabel='Promotional Item' RecordTypeId=$PROMOTIONAL_ITEM_RT_ID ProductSpecificationType=LSPromotionalItem"

echo "Creating Sample_Product ProductSpecificationRecType record..."
sf data create record --sobject ProductSpecificationRecType --use-tooling-api --values "DeveloperName=Sample_Product MasterLabel='Sample Product' RecordTypeId=$SAMPLE_PRODUCT_RT_ID ProductSpecificationType=LSSampleProduct"

echo "ProductSpecificationRecType records created successfully." 