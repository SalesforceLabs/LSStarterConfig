#!/bin/bash

# Function to process a single JSON file and replace references
process_json_file() {
  local json_file="$1"
  local id_mapping_file="$2"

  # Read the ID mapping JSON
  id_mapping=$(jq -r '.' "$id_mapping_file")

  # Iterate through the keys (references) in the ID mapping using jq correctly
  jq -r 'keys[] as $k | "\($k)=\(.[$k])"' "$id_mapping_file" | while IFS='=' read -r key value; do
    # Escape special characters in the key for sed
    escaped_key=$(printf '%s' "$key" | sed 's/[\/&]/\\&/g')

    # Use jq to perform the replacement within the current JSON file
    jq --arg value "$value" --arg key "$escaped_key" '. | walk(if type == "string" and . == $key then $value else . end)' "$json_file" > "$json_file.tmp" && mv "$json_file.tmp" "$json_file"

  done

}

# Main script execution (same as before)
if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <id_mapping_file.json> <json_files...>"
  exit 1
fi

id_mapping_file="$1"
shift # Remove the id_mapping_file from the arguments

if [ ! -f "$id_mapping_file" ]; then
  echo "Error: ID mapping file '$id_mapping_file' not found."
  exit 1
fi

if [ -z "$@" ]; then
  echo "Error: No JSON files provided."
  exit 1
fi


for json_file in "$@"; do
  if [ ! -f "$json_file" ]; then
    echo "Error: JSON file '$json_file' not found."
    continue  # Skip to the next file
  fi
    echo "Processing: $json_file"
    process_json_file "$json_file" "$id_mapping_file"
    echo "Finished: $json_file"
done

echo "Done."

exit 0