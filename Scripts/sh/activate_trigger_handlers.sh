#!/usr/bin/env bash
set -euo pipefail

# Activates/Deactivates LifeScienceTriggerHandler records by DeveloperName.
# - Uses the Tooling API for setup entity updates (no REST calls).
# - Accepts names via --names or --file. If none provided, extracts DeveloperName values
#   from TriggerHandlers.ts in the current directory.
#
# Requirements: Salesforce CLI (sf or sfdx), jq, curl
#
# Examples:
#   ./activate_trigger_handlers.sh --org myAlias --names "HandlerA,HandlerB"
#   ./activate_trigger_handlers.sh --org myAlias --file handlers.txt
#   ./activate_trigger_handlers.sh --org myAlias  # parses DeveloperName from TriggerHanlders.ts

API_VERSION=${API_VERSION:-65.0}
# Controls per-handler logging; set VERBOSE=true to see detailed output
VERBOSE=${VERBOSE:-false}

print_usage() {
  cat <<EOF
Usage: $0 [--org <alias>] [--names "Name1,Name2,..." | --file <path>] [--deactivate] [--api-version <n.n>]

Options:
  -o, --org           Salesforce org alias/username (optional; uses default if omitted)
  -n, --names         Comma-separated DeveloperName values to activate
  -f, --file          File with DeveloperName values (one per line)
  -v, --api-version   API version (default: ${API_VERSION})
      --deactivate    Set handlers to inactive (default: activate)
  -h, --help          Show this help

Behavior:
  If --names and --file are omitted, the script will attempt to parse DeveloperName
  values from TriggerHandlers.ts in the current working directory.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found in PATH" >&2
    exit 1
  fi
}

ORG_ALIAS=""
NAMES_CSV=""
NAMES_FILE=""
DEACTIVATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--org)
      ORG_ALIAS="$2"; shift 2 ;;
    -n|--names)
      NAMES_CSV="$2"; shift 2 ;;
    -f|--file)
      NAMES_FILE="$2"; shift 2 ;;
    -v|--api-version)
      API_VERSION="$2"; shift 2 ;;
    --deactivate)
      DEACTIVATE=true; shift 1 ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      print_usage; exit 1 ;;
  esac
done

## --org is optional; we'll use the CLI default org if not provided

require_cmd jq
require_cmd curl

# Prefer modern 'sf'; fall back to legacy 'sfdx'
SF_CLI=""
if command -v sf >/dev/null 2>&1; then
  SF_CLI="sf"
elif command -v sfdx >/dev/null 2>&1; then
  SF_CLI="sfdx"
else
  echo "Error: Salesforce CLI (sf or sfdx) not found" >&2
  exit 1
fi

get_org_auth() {
  local org_alias="$1"
  if [[ "$SF_CLI" == "sf" ]]; then
    if [[ -n "$org_alias" ]]; then
      $SF_CLI org display --json --target-org "$org_alias"
    else
      $SF_CLI org display --json
    fi
  else
    if [[ -n "$org_alias" ]]; then
      $SF_CLI force:org:display --json -u "$org_alias"
    else
      $SF_CLI force:org:display --json
    fi
  fi
}

AUTH_JSON=$(get_org_auth "$ORG_ALIAS")
ACCESS_TOKEN=$(echo "$AUTH_JSON" | jq -r '.result.accessToken // empty')
INSTANCE_URL=$(echo "$AUTH_JSON" | jq -r '.result.instanceUrl // empty')

if [[ -z "$ACCESS_TOKEN" || -z "$INSTANCE_URL" ]]; then
  if [[ -z "$ORG_ALIAS" ]]; then
    echo "Error: No default org set and --org not provided. Please run 'sf org login web' or pass --org." >&2
  else
    echo "Error: Failed to obtain access token/instance URL for org '$ORG_ALIAS'" >&2
  fi
  exit 1
fi

if [[ "$VERBOSE" == true ]]; then 
  echo "Using org: $ORG_ALIAS"
  echo "Instance URL: $INSTANCE_URL"
  echo "API Version: $API_VERSION"
fi

read_names_from_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Error: file not found: $file_path" >&2
    exit 1
  fi
  grep -v '^\s*$' "$file_path" | sed 's/\r$//' | sed 's/^\s*//; s/\s*$//' | awk 'NF > 0'
}

parse_names_from_ts() {
  # Source file
  local candidates=("TriggerHandlers.ts")
  local found_tmp
  found_tmp=$(mktemp)
  for ts_path in "${candidates[@]}"; do
    if [[ -f "$ts_path" ]]; then
      # Extract DeveloperName values from either quoted or unquoted key forms
      # Matches: DeveloperName: "..." or "DeveloperName": "..."
      sed -n "s/.*\([\"']\?DeveloperName[\"']\?\)[[:space:]]*:[[:space:]]*\"\([^\"]\+\)\".*/\2/p" "$ts_path" >> "$found_tmp"
    fi
  done
  if [[ -s "$found_tmp" ]]; then
    sort -u "$found_tmp"
  fi
  rm -f "$found_tmp"
}

declare -a DEVELOPER_NAMES

if [[ -n "$NAMES_CSV" ]]; then
  IFS=',' read -r -a DEVELOPER_NAMES <<< "$NAMES_CSV"
  for i in "${!DEVELOPER_NAMES[@]}"; do
    DEVELOPER_NAMES[$i]=$(echo "${DEVELOPER_NAMES[$i]}" | sed 's/^\s*//; s/\s*$//')
  done
elif [[ -n "$NAMES_FILE" ]]; then
  while IFS= read -r line; do
    DEVELOPER_NAMES+=("$line")
  done < <(read_names_from_file "$NAMES_FILE")
else
  echo "No --names or --file provided. Attempting to parse DeveloperName values from TriggerHandlers.ts..."
  while IFS= read -r line; do
    DEVELOPER_NAMES+=("$line")
  done < <(parse_names_from_ts)
fi

if [[ ${#DEVELOPER_NAMES[@]} -eq 0 ]]; then
  echo "Error: No DeveloperName values provided or found." >&2
  exit 1
fi

if [[ "$DEACTIVATE" == true ]]; then
  SUMMARY_SUCCESS_LABEL="Deactivated"
  SUMMARY_SKIPPED_LABEL="Already inactive"
else
  SUMMARY_SUCCESS_LABEL="Activated"
  SUMMARY_SKIPPED_LABEL="Already active"
fi

urlencode() {
  # Use jq for robust URL encoding
  jq -rn --arg v "$1" '$v|@uri'
}

soql_query_encode() {
  local soql="$1"
  urlencode "$soql"
}

http_get_json() {
  local url="$1"
  curl -sS -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" "$url"
}

http_patch() {
  local url="$1"
  local body="$2"
  # Return status code separately
  curl -sS -o /tmp/resp.$$ -w "%{http_code}" -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" -X PATCH -d "$body" "$url"
}

find_handler() {
  local dev_name="$1"
  local soql="SELECT Id, IsActive, DeveloperName FROM LifeScienceTriggerHandler WHERE DeveloperName = '$dev_name'"
  local enc_soql
  enc_soql=$(soql_query_encode "$soql")

  # Prefer Tooling API first for setup entity
  local url_tool="$INSTANCE_URL/services/data/v$API_VERSION/tooling/query?q=$enc_soql"
  local res_tool
  res_tool=$(http_get_json "$url_tool")
  local total_tool
  total_tool=$(echo "$res_tool" | jq -r 'if (type=="object" and has("totalSize")) then .totalSize else 0 end')
  if [[ "$total_tool" != "0" ]]; then
    echo "$res_tool" | jq -c '.records[0]'
    return 0
  fi

  # Try standard REST next; guard against error-arrays
  local url_std="$INSTANCE_URL/services/data/v$API_VERSION/query?q=$enc_soql"
  local res_std
  res_std=$(http_get_json "$url_std")
  local total_std
  total_std=$(echo "$res_std" | jq -r 'if (type=="object" and has("totalSize")) then .totalSize else 0 end')
  if [[ "$total_std" != "0" ]]; then
    echo "$res_std" | jq -c '.records[0]'
    return 0
  fi

  echo "" # not found
}

activate_handler() {
  local id="$1"
  local current_is_active="$2"
  local target_active
  if [[ "$DEACTIVATE" == true ]]; then
    target_active=false
  else
    target_active=true
  fi
  local json_body
  json_body=$(printf '{"IsActive":%s}' "$target_active")

  if [[ "$DEACTIVATE" == true ]]; then
    if [[ "$current_is_active" == "false" ]]; then
      echo "already-inactive"
      return 0
    fi
  else
    if [[ "$current_is_active" == "true" ]]; then
      echo "already-active"
      return 0
    fi
  fi

  # Try standard REST sObject PATCH
  local url_std="$INSTANCE_URL/services/data/v$API_VERSION/sobjects/LifeScienceTriggerHandler/$id"
  local code
  code=$(http_patch "$url_std" "$json_body")
  if [[ "$code" =~ ^2 ]]; then
    echo "updated-standard"
    return 0
  fi

  # Fallback to Tooling API sObject PATCH
  local url_tool="$INSTANCE_URL/services/data/v$API_VERSION/tooling/sobjects/LifeScienceTriggerHandler/$id"
  code=$(http_patch "$url_tool" "$json_body")
  if [[ "$code" =~ ^2 ]]; then
    echo "updated-tooling"
    return 0
  fi

  echo "failed"
}

declare -i success_count=0
declare -i skipped_count=0
declare -i notfound_count=0
declare -i failed_count=0

for name in "${DEVELOPER_NAMES[@]}"; do
  [[ -z "$name" ]] && continue
  if [[ "$VERBOSE" == true ]]; then
    echo "Processing DeveloperName: $name"
  fi
  record_json=$(find_handler "$name")
  if [[ -z "$record_json" || "$record_json" == "null" ]]; then
    if [[ "$VERBOSE" == true ]]; then
      echo "  Not found in org (standard and tooling)."
    fi
    notfound_count+=1
    continue
  fi
  id=$(echo "$record_json" | jq -r '.Id')
  is_active=$(echo "$record_json" | jq -r '.IsActive')

  result=$(activate_handler "$id" "$is_active")
  case "$result" in
    already-active)
      if [[ "$VERBOSE" == true ]]; then
        echo "  Already active. Skipping."
      fi
      skipped_count+=1 ;;
    already-inactive)
      if [[ "$VERBOSE" == true ]]; then
        echo "  Already inactive. Skipping."
      fi
      skipped_count+=1 ;;
    updated-standard)
      if [[ "$VERBOSE" == true ]]; then
        if [[ "$DEACTIVATE" == true ]]; then
          echo "  Deactivated via standard REST API."
        else
          echo "  Activated via standard REST API."
        fi
      fi
      success_count+=1 ;;
    updated-tooling)
      if [[ "$VERBOSE" == true ]]; then
        if [[ "$DEACTIVATE" == true ]]; then
          echo "  Deactivated via Tooling API."
        else
          echo "  Activated via Tooling API."
        fi
      fi
      success_count+=1 ;;
    failed)
      if [[ "$VERBOSE" == true ]]; then
        echo "  Failed to activate (both standard and Tooling PATCH failed)."
      fi
      failed_count+=1 ;;
    *)
      if [[ "$VERBOSE" == true ]]; then
        echo "  Unexpected result: $result"
      fi
      failed_count+=1 ;;
  esac
done

  if [[ "$VERBOSE" == true ]]; then
    echo
    echo "Done. Summary:"
    echo "  $SUMMARY_SUCCESS_LABEL: $success_count"
    echo "  $SUMMARY_SKIPPED_LABEL: $skipped_count"
    echo "  Not found: $notfound_count"
    echo "  Failed: $failed_count"
  fi

if (( failed_count > 0 )); then
  exit 1
fi

exit 0
