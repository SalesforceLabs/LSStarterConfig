#!/bin/bash

RECORD_MAPPINGS="FeatureSetupData/tmp/recordMappings.json"
FILES_LIST="FeatureSetupData/toBeProcess.json"

# Ensure 'jq' is installed:
if ! command -v jq &> /dev/null; then
    echo "ERROR: 'jq' is not installed. Please install jq before running this script."
    exit 1
fi

# Loop over each file in toBeProcess.json
for JSON_FILE in $(jq -r '.[]' "$FILES_LIST"); do
    FILE_PATH="FeatureSetupData/$JSON_FILE"
    if [[ ! -f "$FILE_PATH" ]]; then
        echo "WARNING: $FILE_PATH does not exist. Skipping."
        continue
    fi

    echo "Processing $JSON_FILE ..."

    placeholders=$(grep -o '\$[^$]\+\$' "$FILE_PATH" 2>/dev/null | sort | uniq)

    # If no placeholders found, move on
    if [[ -z "$placeholders" ]]; then
        echo "  No placeholders found in $JSON_FILE."
        continue
    fi

    # For each placeholder found, look it up in recordMappings.json
    for ph in $placeholders; do
        # Retrieve value from recordMappings.json (returns empty string if key doesn't exist)
        value=$(jq -r --arg p "$ph" '.[$p] // empty' "$RECORD_MAPPINGS")

        # If a value was found, replace the placeholder in the file
        if [[ -n "$value" ]]; then
            # Using sed to do in-place substitution.
            # We pick a delimiter (|) that is unlikely to appear in your values/keys.
            escapedPh=$(printf '%s' "$ph" | sed 's/\$/\\$/g')
            sed -i '' "s|$escapedPh|$value|g" "$FILE_PATH"
        else
            echo "  WARNING: No mapping found for '$ph' in recordMappings.json."
        fi
    done
done

echo "All files processed."
