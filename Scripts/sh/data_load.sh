#!/bin/bash
set -e

echo "Loading package components and configurations..."

sf org assign permset -n HealthCloudStarter

#deploy 2GP package components
sf project deploy start -d PackageComponents

# Check if jq is installed
 if ! command -v jq &> /dev/null; then
   echo "jq could not be found. Please install jq to proceed (brew install jq)."
   exit 1
 fi

#deploy LSConfig entries
#import platform BPO entries
echo "Starting - sf data import tree --plan LSConfig/lifeSciMetadataRecord/LifeSciMetadataCategory-plan.json"
sf data import tree --plan LSConfig/lifeSciMetadataRecord/LifeSciMetadataCategory-plan.json
#deploy setup BPO entries, only works with Salesforce CLI version 2.80.4 or higher
echo "Starting - sf project deploy start -d LSConfig/lifeSciConfigRecord/1_inactive"
sf project deploy start -d LSConfig/lifeSciConfigRecord/1_inactive
echo "Starting - sf project deploy start -d LSConfig/lifeSciConfigRecord/2_activate"
sf project deploy start -d LSConfig/lifeSciConfigRecord/2_activate
