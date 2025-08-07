#!/bin/bash
set -e

echo "Adding current user ID to recordMappings.json"

# Retrieve current user ID for Location PrimaryUserId
CURRENT_USER_ID=$(sf org display user --json | jq -r '.result.id')
echo "Current User ID: $CURRENT_USER_ID"

# Add user ID to recordMappings.json
if [ -f "FeatureSetupData/tmp/recordMappings.json" ]; then
  jq --arg id "$CURRENT_USER_ID" '. + {"$CurrentUserId$": $id}' FeatureSetupData/tmp/recordMappings.json > FeatureSetupData/tmp/recordMappings_temp.json
  mv FeatureSetupData/tmp/recordMappings_temp.json FeatureSetupData/tmp/recordMappings.json
  echo "Added current user ID to existing recordMappings.json"
fi 