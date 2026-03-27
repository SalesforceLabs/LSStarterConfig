#!/bin/bash
#
# Post-deployment script: Assign Lightning Home Page to profiles
#
# This script assigns the "Home_Page_LSC_Default" FlexiPage as the
# Lightning home page for the specified profiles. This step is required
# because Lightning home page profile assignments are not deployable
# via the Metadata API.
#
# Usage:
#   ./scripts/assign-homepage.sh <target-org-alias>
#
# Example:
#   ./scripts/assign-homepage.sh my-sandbox
#

set -e

TARGET_ORG="${1:?Usage: $0 <target-org-alias>}"
FLEXIPAGE_NAME="Home_Page_LSC_Default"
PROFILES=("Admin" "LSC Custom Profile")

echo "============================================"
echo "  Home Page Assignment - Post Deployment"
echo "============================================"
echo ""
echo "Target Org  : $TARGET_ORG"
echo "FlexiPage   : $FLEXIPAGE_NAME"
echo "Profiles    : ${PROFILES[*]}"
echo ""

# Step 1: Check if the FlexiPage exists in the target org
echo "[1/4] Verifying FlexiPage exists in target org..."
FLEXIPAGE_CHECK=$(sf data query \
    --query "SELECT Id, DeveloperName FROM FlexiPage WHERE DeveloperName = '$FLEXIPAGE_NAME' LIMIT 1" \
    --use-tooling-api \
    --target-org "$TARGET_ORG" \
    --json 2>/dev/null)

FLEXIPAGE_COUNT=$(echo "$FLEXIPAGE_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['totalSize'])")
if [ "$FLEXIPAGE_COUNT" -eq 0 ]; then
    echo "ERROR: FlexiPage '$FLEXIPAGE_NAME' not found in target org."
    echo "       Deploy the FlexiPage first, then re-run this script."
    exit 1
fi
echo "       FlexiPage found."
echo ""

# Step 2: Check for existing assignments
echo "[2/4] Checking existing home page assignments..."
EXISTING=$(sf data query \
    --query "SELECT Id, FlexipageName, ProfileId FROM FlexipageDefault WHERE FlexipageName = '$FLEXIPAGE_NAME'" \
    --use-tooling-api \
    --target-org "$TARGET_ORG" \
    --json 2>/dev/null)

EXISTING_COUNT=$(echo "$EXISTING" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['totalSize'])")
echo "       Found $EXISTING_COUNT existing assignment(s) for this page."
echo ""

# Step 3: Look up Profile IDs
echo "[3/4] Looking up Profile IDs..."
declare -A PROFILE_IDS

for PROFILE_NAME in "${PROFILES[@]}"; do
    PROFILE_RESULT=$(sf data query \
        --query "SELECT Id, Name FROM Profile WHERE Name = '$PROFILE_NAME' LIMIT 1" \
        --target-org "$TARGET_ORG" \
        --json 2>/dev/null)

    PROFILE_ID=$(echo "$PROFILE_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data['result']['records']
print(records[0]['Id'] if records else '')
")

    if [ -z "$PROFILE_ID" ]; then
        echo "  WARNING: Profile '$PROFILE_NAME' not found in target org. Skipping."
        continue
    fi

    PROFILE_IDS["$PROFILE_NAME"]="$PROFILE_ID"
    echo "  $PROFILE_NAME => $PROFILE_ID"
done
echo ""

# Step 4: Create assignments
echo "[4/4] Assigning home page to profiles..."
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

for PROFILE_NAME in "${!PROFILE_IDS[@]}"; do
    PROFILE_ID="${PROFILE_IDS[$PROFILE_NAME]}"

    # Check if assignment already exists for this profile
    ALREADY_ASSIGNED=$(echo "$EXISTING" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data['result']['records']
exists = any(r.get('ProfileId','').startswith('${PROFILE_ID:0:15}') for r in records)
print('true' if exists else 'false')
")

    if [ "$ALREADY_ASSIGNED" = "true" ]; then
        echo "  SKIP: '$PROFILE_NAME' - already assigned."
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    echo "  Assigning to '$PROFILE_NAME' ($PROFILE_ID)..."
    RESULT=$(sf api request rest \
        --method POST \
        --url "/tooling/sobjects/FlexipageDefault" \
        --body "{\"FlexipageName\":\"$FLEXIPAGE_NAME\",\"ProfileId\":\"$PROFILE_ID\"}" \
        --target-org "$TARGET_ORG" \
        --json 2>&1) || true

    IS_SUCCESS=$(echo "$RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict) and data.get('result', {}).get('success', False):
        print('true')
    elif isinstance(data, dict) and data.get('success', False):
        print('true')
    else:
        print('false')
except:
    print('false')
")

    if [ "$IS_SUCCESS" = "true" ]; then
        echo "    SUCCESS"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "    FAILED - Response: $RESULT"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
echo "  Assigned : $SUCCESS_COUNT"
echo "  Skipped  : $SKIP_COUNT (already assigned)"
echo "  Failed   : $FAIL_COUNT"
echo "============================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "Some assignments failed. You may need to assign manually:"
    echo "  Setup > Home > Home Page Settings > Assign to profiles"
    exit 1
fi

echo ""
echo "Done."
