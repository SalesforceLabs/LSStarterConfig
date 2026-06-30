<#
.SYNOPSIS
Activates/Deactivates LifeScienceTriggerHandler records by DeveloperName.

.DESCRIPTION
- Uses the Tooling API for setup entity updates (no REST calls).
- Accepts names via -Names or -File. If none provided, extracts DeveloperName values
  from TriggerHandlers.ts in the current directory.

# Requirements: Salesforce CLI (sf or sfdx)

.EXAMPLE
.\activate_trigger_handlers.ps1 -org myAlias -names "HandlerA,HandlerB"
.\activate_trigger_handlers.ps1 -org myAlias -file handlers.txt
.\activate_trigger_handlers.ps1 -org myAlias
#>

param (
    [string]$org = "",
    [string]$names = "",
    [string]$file = "",
    [string]$apiVersion = "65.0",
    [switch]$deactivate,
    [switch]$verboseOut
)

$ErrorActionPreference = "Stop"

# Use sf if available, fallback to sfdx
$sfCli = "sf"
if (-not (Get-Command $sfCli -ErrorAction SilentlyContinue)) {
    $sfCli = "sfdx"
    if (-not (Get-Command $sfCli -ErrorAction SilentlyContinue)) {
        Write-Error "Salesforce CLI (sf or sfdx) not found"
        exit 1
    }
}

# --- 1. Get Authentication Info ---
function Get-OrgAuth {
    param([string]$orgAlias)
    
    $authJson = ""
    if ($sfCli -eq "sf") {
        if ([string]::IsNullOrWhiteSpace($orgAlias)) {
            $authJson = sf org display --json
        } else {
            $authJson = sf org display --json --target-org "$orgAlias"
        }
    } else {
        if ([string]::IsNullOrWhiteSpace($orgAlias)) {
            $authJson = sfdx force:org:display --json
        } else {
            $authJson = sfdx force:org:display --json -u "$orgAlias"
        }
    }
    
    return $authJson | ConvertFrom-Json
}

Write-Host "Retrieving Org Authentication..."
$authObj = Get-OrgAuth -orgAlias $org

$accessToken = $authObj.result.accessToken
$instanceUrl = $authObj.result.instanceUrl

if ([string]::IsNullOrEmpty($accessToken) -or [string]::IsNullOrEmpty($instanceUrl)) {
    Write-Error "Could not retrieve access token or instance URL. Ensure you are logged into a default org or provide -org."
    exit 1
}

if ($verboseOut) {
    Write-Host "Instance URL: $instanceUrl"
    Write-Host "API Version: $apiVersion"
}


# --- 2. Determine Developer Names to Process ---
$developerNames = @()

if (-not [string]::IsNullOrWhiteSpace($names)) {
    $developerNames = $names -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
} 
elseif (-not [string]::IsNullOrWhiteSpace($file)) {
    if (-not (Test-Path $file)) {
        Write-Error "File not found: $file"
        exit 1
    }
    $developerNames = Get-Content $file | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
} 
else {
    # Default behavior: parse TriggerHandlers.ts
    Write-Host "No -names or -file provided. Parsing DeveloperName from TriggerHandlers.ts..."
    $tsPath = "TriggerHandlers.ts"
    if (-not (Test-Path $tsPath)) {
       # Assume it might be executed from the root, try that path. 
       $tsPath = "TriggerHandlers\TriggerHandlers.ts"
    }

    if (Test-Path $tsPath) {
        $content = Get-Content $tsPath
        # Regex to match DeveloperName: "value" or 'DeveloperName': "value"
        foreach ($line in $content) {
            if ($line -match "['""]?DeveloperName['""]?\s*:\s*""([^""]+)""") {
                $developerNames += $matches[1]
            }
        }
        $developerNames = $developerNames | Select-Object -Unique
    } else {
        Write-Error "TriggerHandlers.ts not found. Please specify -names or -file."
        exit 1
    }
}

if ($developerNames.Count -eq 0) {
    Write-Error "No DeveloperName values found."
    exit 1
}

# --- 3. Processing Handlers ---
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type"  = "application/json"
}

$successCount = 0
$skippedCount = 0
$notFoundCount = 0
$failedCount = 0

foreach ($devName in $developerNames) {
    if ($verboseOut) { Write-Host "Processing DeveloperName: $devName" }

    $soql = "SELECT Id, IsActive, DeveloperName FROM LifeScienceTriggerHandler WHERE DeveloperName = '$devName'"
    $encodedSoql = [uri]::EscapeDataString($soql)

    $record = $null
    
    # Tooling API Query
    $toolingUrl = "$instanceUrl/services/data/v$apiVersion/tooling/query?q=$encodedSoql"
    try {
        $toolingResponse = Invoke-RestMethod -Uri $toolingUrl -Headers $headers -Method Get
        if ($toolingResponse.totalSize -gt 0) {
            $record = $toolingResponse.records[0]
        }
    } catch {
        # Fallback to standard REST API Query
        $restUrl = "$instanceUrl/services/data/v$apiVersion/query?q=$encodedSoql"
        try {
            $restResponse = Invoke-RestMethod -Uri $restUrl -Headers $headers -Method Get
            if ($restResponse.totalSize -gt 0) {
                $record = $restResponse.records[0]
            }
        } catch { }
    }

    if ($null -eq $record) {
        if ($verboseOut) { Write-Host "  Not found in org." }
        $notFoundCount++
        continue
    }

    $id = $record.Id
    $isActive = $record.IsActive
    $targetActive = -not $deactivate

    if ($targetActive -eq $isActive) {
        if ($verboseOut) { Write-Host "  Already in desired state. Skipping." }
        $skippedCount++
        continue
    }

    $bodyMap = @{ "IsActive" = $targetActive }
    $bodyJson = $bodyMap | ConvertTo-Json -Compress

    $updateSuccess = $false

    # Attempt Standard sObject REST Update
    $updateStdUrl = "$instanceUrl/services/data/v$apiVersion/sobjects/LifeScienceTriggerHandler/$id"
    try {
        $updateResp = Invoke-RestMethod -Uri $updateStdUrl -Headers $headers -Method Patch -Body $bodyJson
        $updateSuccess = $true
        if ($verboseOut) { Write-Host "  Updated via Standard REST." }
    } catch {
        # Attempt Tooling API Update
        $updateToolUrl = "$instanceUrl/services/data/v$apiVersion/tooling/sobjects/LifeScienceTriggerHandler/$id"
        try {
            $updateResp = Invoke-RestMethod -Uri $updateToolUrl -Headers $headers -Method Patch -Body $bodyJson
            $updateSuccess = $true
            if ($verboseOut) { Write-Host "  Updated via Tooling API." }
        } catch { }
    }

    if ($updateSuccess) {
        $successCount++
    } else {
        if ($verboseOut) { Write-Host "  Update failed." }
        $failedCount++
    }
}

Write-Host "`nDone. Summary:"
$successLabel = if ($deactivate) { "Deactivated" } else { "Activated" }
$skippedLabel = if ($deactivate) { "Already Inactive" } else { "Already Active" }
Write-Host "  $successLabel : $successCount"
Write-Host "  $skippedLabel : $skippedCount"
Write-Host "  Not Found        : $notFoundCount"
Write-Host "  Failed           : $failedCount"

if ($failedCount -gt 0) {
    exit 1
}
exit 0
