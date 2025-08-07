#!/bin/bash

# Check if the plan file argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <plan_file>"
  exit 1
fi

plan_file="$1"
mappings_file="FeatureSetupData/tmp/recordMappings.json"
tmp_mappings_file="FeatureSetupData/tmp/recordMappings.tmp.json"

# Check if the directory exists, create it if it doesn't
if [ ! -d "FeatureSetupData/tmp" ]; then
    mkdir -p "FeatureSetupData/tmp"
    echo "Created directory FeatureSetupData/tmp"
fi

# Check if recordMappings.json exists, create it if it doesn't
if [ ! -f "$mappings_file" ]; then
  echo "Creating $mappings_file"
  echo "{}" > "$mappings_file"  # Create an empty JSON object
fi

# Get the JSON output from the sf command using the provided plan file and wait for it to finish
json_output=$(sf data import tree --plan "$plan_file" --json)

# Print the original JSON output to the console
echo "Original JSON output:"
echo "$json_output"

# Check if the sf command was successful
if [[ $(echo "$json_output" | jq -r '.status') -ne "0" ]]; then
    echo "Error: sf data import failed. Check the plan file and sf command."
    echo "sf command output: $json_output"
    exit 1
fi

# Extract the refId and id pairs and construct the JSON update
update_json=$(jq -r '.result | map({("$\(.refId)$"): .id}) | add' <<< "$json_output")

echo "NEW JSON output:" 
echo "$update_json" > "$tmp_mappings_file"

jq -s 'add' "$mappings_file" "$tmp_mappings_file" > temp.json && mv temp.json "$mappings_file"

rm -f "$tmp_mappings_file"

echo "Updated $mappings_file"
