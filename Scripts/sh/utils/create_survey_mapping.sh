#!/bin/bash

# Script to create survey ID mappings from org surveys and survey versions
# Usage: sh scripts/sh/utils/create_survey_mapping.sh

echo "Creating survey and survey version ID mappings..."

# Output file for survey mappings
SURVEY_MAPPING_FILE="FeatureSetupData/tmp/surveyMapping.json"

# Ensure the tmp directory exists
mkdir -p "FeatureSetupData/tmp"

# Query surveys from the org
echo "Querying surveys from the org..."

# Try to get survey data
if sf data query --query "SELECT Id, Name, DeveloperName FROM Survey WHERE IsDeleted = false ORDER BY CreatedDate ASC LIMIT 10" --json > "FeatureSetupData/tmp/survey_query.json" 2>/dev/null; then
    
    # Check if we got valid results
    SURVEY_COUNT=$(jq -r '.result.records | length' "FeatureSetupData/tmp/survey_query.json" 2>/dev/null || echo "0")
    
    if [[ "$SURVEY_COUNT" -gt 0 ]]; then
        echo "Found $SURVEY_COUNT surveys. Querying survey versions..."
        
        # Get the first two survey IDs
        SURVEY1_ID=$(jq -r '.result.records[0].Id // "NO_SURVEY_1"' "FeatureSetupData/tmp/survey_query.json")
        SURVEY2_ID=$(jq -r '.result.records[1].Id // "NO_SURVEY_2"' "FeatureSetupData/tmp/survey_query.json")
        
        echo "Survey1 ID: $SURVEY1_ID"
        echo "Survey2 ID: $SURVEY2_ID"
        
        # Query SurveyVersions for these specific surveys
        sf data query --query "SELECT Id, SurveyId FROM SurveyVersion WHERE SurveyId IN ('$SURVEY1_ID', '$SURVEY2_ID') ORDER BY SurveyId, CreatedDate ASC LIMIT 10" --json > "FeatureSetupData/tmp/survey_version_query.json" 2>/dev/null
        
        # Get survey version IDs - ensuring each version belongs to its corresponding survey
        SURVEY_VERSION1_ID=$(jq -r ".result.records[] | select(.SurveyId == \"$SURVEY1_ID\") | .Id" "FeatureSetupData/tmp/survey_version_query.json" 2>/dev/null | head -1)
        SURVEY_VERSION2_ID=$(jq -r ".result.records[] | select(.SurveyId == \"$SURVEY2_ID\") | .Id" "FeatureSetupData/tmp/survey_version_query.json" 2>/dev/null | head -1)
        
        # Validate that we got the correct relationships
        if [[ -n "$SURVEY_VERSION1_ID" && "$SURVEY_VERSION1_ID" != "null" ]]; then
            echo "✓ SurveyVersion1 ($SURVEY_VERSION1_ID) belongs to Survey1 ($SURVEY1_ID)"
        else
            SURVEY_VERSION1_ID="NO_SURVEY_VERSION_FOR_SURVEY1"
            echo "⚠ No SurveyVersion found for Survey1 ($SURVEY1_ID)"
        fi
        
        if [[ -n "$SURVEY_VERSION2_ID" && "$SURVEY_VERSION2_ID" != "null" ]]; then
            echo "✓ SurveyVersion2 ($SURVEY_VERSION2_ID) belongs to Survey2 ($SURVEY2_ID)"
        else
            SURVEY_VERSION2_ID="NO_SURVEY_VERSION_FOR_SURVEY2"
            echo "⚠ No SurveyVersion found for Survey2 ($SURVEY2_ID)"
        fi
        
        # Query SurveyQuestions for these SurveyVersions
        echo "Querying SurveyQuestions for the survey versions..."
        sf data query --query "SELECT Id, SurveyVersionId FROM SurveyQuestion WHERE SurveyVersionId IN ('$SURVEY_VERSION1_ID', '$SURVEY_VERSION2_ID') ORDER BY SurveyVersionId, CreatedDate ASC LIMIT 10" --json > "FeatureSetupData/tmp/survey_question_query.json" 2>/dev/null
        
        # Get survey question IDs - ensuring each question belongs to its corresponding survey version
        SURVEY_QUESTION1_ID=$(jq -r ".result.records[] | select(.SurveyVersionId == \"$SURVEY_VERSION1_ID\") | .Id" "FeatureSetupData/tmp/survey_question_query.json" 2>/dev/null | head -1)
        SURVEY_QUESTION2_ID=$(jq -r ".result.records[] | select(.SurveyVersionId == \"$SURVEY_VERSION2_ID\") | .Id" "FeatureSetupData/tmp/survey_question_query.json" 2>/dev/null | head -1)
        
        # Validate SurveyQuestion relationships
        if [[ -n "$SURVEY_QUESTION1_ID" && "$SURVEY_QUESTION1_ID" != "null" ]]; then
            echo "✓ SurveyQuestion1 ($SURVEY_QUESTION1_ID) belongs to SurveyVersion1 ($SURVEY_VERSION1_ID)"
        else
            SURVEY_QUESTION1_ID="NO_SURVEY_QUESTION_FOR_VERSION1"
            echo "⚠ No SurveyQuestion found for SurveyVersion1 ($SURVEY_VERSION1_ID)"
        fi
        
        if [[ -n "$SURVEY_QUESTION2_ID" && "$SURVEY_QUESTION2_ID" != "null" ]]; then
            echo "✓ SurveyQuestion2 ($SURVEY_QUESTION2_ID) belongs to SurveyVersion2 ($SURVEY_VERSION2_ID)"
        else
            SURVEY_QUESTION2_ID="NO_SURVEY_QUESTION_FOR_VERSION2"
            echo "⚠ No SurveyQuestion found for SurveyVersion2 ($SURVEY_VERSION2_ID)"
        fi
        
        # Query SurveyQuestionChoices for these SurveyQuestions (if they exist)
        SURVEY_QUESTION_CHOICE1_ID="test"
        SURVEY_QUESTION_CHOICE2_ID="test"
        
        if [[ "$SURVEY_QUESTION1_ID" != "NO_SURVEY_QUESTION_FOR_VERSION1" ]]; then
            echo "Querying SurveyQuestionChoices for SurveyQuestion1..."
            SURVEY_QUESTION_CHOICE1_ID=$(sf data query --query "SELECT Id FROM SurveyQuestionChoice WHERE SurveyQuestionId = '$SURVEY_QUESTION1_ID' LIMIT 1" --json 2>/dev/null | jq -r '.result.records[0].Id // "test"')
        fi
        
        if [[ "$SURVEY_QUESTION2_ID" != "NO_SURVEY_QUESTION_FOR_VERSION2" ]]; then
            echo "Querying SurveyQuestionChoices for SurveyQuestion2..."
            SURVEY_QUESTION_CHOICE2_ID=$(sf data query --query "SELECT Id FROM SurveyQuestionChoice WHERE SurveyQuestionId = '$SURVEY_QUESTION2_ID' LIMIT 1" --json 2>/dev/null | jq -r '.result.records[0].Id // "test"')
        fi
        
        echo "SurveyQuestionChoice1: $SURVEY_QUESTION_CHOICE1_ID"
        echo "SurveyQuestionChoice2: $SURVEY_QUESTION_CHOICE2_ID"
        
        # Create mapping file with all survey-related objects
        cat > "$SURVEY_MAPPING_FILE" << EOF
{
    "\$Survey.Survey1\$": "$SURVEY1_ID",
    "\$Survey.Survey2\$": "$SURVEY2_ID",
    "\$Survey.SurveyVersion1\$": "$SURVEY_VERSION1_ID",
    "\$Survey.SurveyVersion2\$": "$SURVEY_VERSION2_ID",
    "\$Survey.SurveyQuestion1\$": "$SURVEY_QUESTION1_ID",
    "\$Survey.SurveyQuestion2\$": "$SURVEY_QUESTION2_ID",
    "\$Survey.SurveyQuestionChoice1\$": "$SURVEY_QUESTION_CHOICE1_ID",
    "\$Survey.SurveyQuestionChoice2\$": "$SURVEY_QUESTION_CHOICE2_ID"
}
EOF
        
    else
        echo "No surveys found in org. Creating placeholder mapping..."
        cat > "$SURVEY_MAPPING_FILE" << 'EOF'
{
    "$Survey.Survey1$": "NO_SURVEY_FOUND_1",
    "$Survey.Survey2$": "NO_SURVEY_FOUND_2",
    "$Survey.SurveyVersion1$": "NO_SURVEY_VERSION_1",
    "$Survey.SurveyVersion2$": "NO_SURVEY_VERSION_2",
    "$Survey.SurveyQuestion1$": "NO_SURVEY_QUESTION_1",
    "$Survey.SurveyQuestion2$": "NO_SURVEY_QUESTION_2",
    "$Survey.SurveyQuestionChoice1$": "test",
    "$Survey.SurveyQuestionChoice2$": "test"
}
EOF
    fi
    
else
    echo "Failed to query surveys. Creating placeholder mapping..."
    cat > "$SURVEY_MAPPING_FILE" << 'EOF'
{
    "$Survey.Survey1$": "QUERY_FAILED_1",
    "$Survey.Survey2$": "QUERY_FAILED_2",
    "$Survey.SurveyVersion1$": "QUERY_FAILED_VERSION_1",
    "$Survey.SurveyVersion2$": "QUERY_FAILED_VERSION_2",
    "$Survey.SurveyQuestion1$": "QUERY_FAILED_QUESTION_1",
    "$Survey.SurveyQuestion2$": "QUERY_FAILED_QUESTION_2",
    "$Survey.SurveyQuestionChoice1$": "test",
    "$Survey.SurveyQuestionChoice2$": "test"
}
EOF
fi

# Clean up temp files
rm -f "FeatureSetupData/tmp/survey_query.json"
rm -f "FeatureSetupData/tmp/survey_version_query.json"
rm -f "FeatureSetupData/tmp/survey_question_query.json"

# Verify the mapping file was created
if [[ -f "$SURVEY_MAPPING_FILE" ]]; then
    echo "Survey and survey version mapping file created successfully at: $SURVEY_MAPPING_FILE"
    echo "Contents:"
    cat "$SURVEY_MAPPING_FILE"
else
    echo "ERROR: Failed to create survey mapping file"
    exit 1
fi 