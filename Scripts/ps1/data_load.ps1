# data_load.ps1
# Deploys LSC Starter Configurations
$ErrorActionPreference = "Stop"

Write-Host "Deploying configurations..."

# Verify Salesforce CLI is installed
if (-not (Get-Command "sf" -ErrorAction SilentlyContinue) -and -not (Get-Command "sfdx" -ErrorAction SilentlyContinue)) {
    Write-Error "Salesforce CLI (sf or sfdx) could not be found. Please install the Salesforce CLI to proceed."
    exit 1
}

# 1. Deploy the LSC Custom Profile
Write-Host "Deploying LSC Custom Profile..."
sf project deploy start -d "PackageComponents/profiles/LSC Custom Profile.profile-meta.xml" --json *> $null

# 2. Import Metadata Categories
Write-Host "Importing LifeSciMetadataCategories..."
# Suppress output; duplicates will fail silently as intended by the original script
sf data import tree --plan LSConfig/lifeSciMetadataRecord/LifeSciMetadataCategory-plan.json --json *> $null

# 3. Deploy configuration records
Write-Host "Deploying Config Records..."
sf project deploy start -d LSConfig/lifeSciConfigRecord --json *> $null

# 4. Activate Trigger Handlers
Write-Host "Activating Trigger Handlers..."
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir\activate_trigger_handlers.ps1" -file "TriggerHandlers\TriggerHandlers.ts"

Write-Host "Deployment Completed Successfuly!"
