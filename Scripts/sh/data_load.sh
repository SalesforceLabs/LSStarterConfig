#!/bin/bash
set -e

echo "Deploying configurations..."

# Check if jq is installed
 if ! command -v jq &> /dev/null; then
   echo "jq could not be found. Please install jq to proceed (brew install jq)."
   exit 1
 fi

sf project deploy start -d "PackageComponents/profiles/LSC Custom Profile.profile-meta.xml" --json 1>/dev/null 2>/dev/null
sf data import tree --plan LSConfig/lifeSciMetadataRecord/LifeSciMetadataCategory-plan.json --json 1>/dev/null 2>/dev/null
sf project deploy start -d LSConfig/lifeSciConfigRecord/1_inactive --json 1>/dev/null 2>/dev/null
sf project deploy start -d LSConfig/lifeSciConfigRecord/2_activate --json 1>/dev/null 2>/dev/null
bash Scripts/sh/activate_trigger_handlers.sh --file TriggerHandlers/TriggerHandlers.ts