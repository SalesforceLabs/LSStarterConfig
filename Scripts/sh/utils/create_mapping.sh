#!/bin/bash

# This script helps create JSON mappings from Salesforce query.

# Function to handle mapping with a single key field
create_mapping_single_key() {
  local query="$1"
  local key_field="$2"
  local value_field="$3"
  local output_file="$4"

  sf data query --query "$query" --json | \
  jq -r ".result.records | map({(\"\$\(.[\"$key_field\"])\$\"): .[\"$value_field\"]}) | add" > "$output_file"
}

create_mapping_double_key() {
  local query="$1"
  local key_field1="$2"
  local value_field="$3"
  local output_file="$4"
  local key_field2="$5"

  sf data query --query "$query" --json | \
  jq -r ".result.records | map({(\"\$\(.[\"$key_field1\"]).\(.[\"$key_field2\"])\$\"): .[\"$value_field\"]}) | add" > "$output_file"
}

# Main script logic
if [ "$#" -eq 4 ]; then
  # Single key field mapping
  create_mapping_single_key "$1" "$2" "$3" "$4"
elif [ "$#" -eq 5 ]; then
  # Double key field mapping
  create_mapping_double_key "$1" "$2" "$3" "$4" "$5"
else
  echo "Usage: $0 \"query\" keyField valueField outputFile [keyField2]"
  exit 1
fi

echo "Mapping created successfully in $4"