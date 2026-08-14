# LS Starter Config

This repository contains the starter configuration records, profiles, and trigger handlers necessary to initialize a Life Sciences Cloud org or sandbox.

## Prerequisites

Before deploying this package to your org, ensure your environment is set up correctly:

1.  **Target Org Requirements:**
    *   A Life Sciences Cloud (LSC4CE) Org with the 2GP package installed.
    *   The org MUST have the following permission set licenses available:
        *   `Health Cloud Starter`
        *   `Life Science Commercial`
2.  **Local Environment Requirements:**
    *   [Salesforce CLI (`sf`)](https://developer.salesforce.com/tools/salesforcecli) installed.
    *   [Node.js and npm](https://nodejs.org/en) installed.
    *   *(Mac/Linux only)* `jq` installed (`brew install jq` or `apt-get install jq`).

---

## Deployment Steps

Choose the appropriate tab below depending on your operating system (Mac/Linux vs. Windows).

### 1. Authorize Your Org
First, authenticate the Salesforce CLI with the exact org where you wish to deploy these configurations. 

**For Production:**
```bash
sf org login web --set-default
```

**For Sandboxes:**
```bash
sf org login web -r https://test.salesforce.com --set-default
```
*(Follow the browser prompts to log in and allow CLI access).*

### 2. Install Dependencies
Install the local tooling required to deploy the project (like Prettier and testing frameworks):
```bash
npm install
```

### 3. Run the Data Loader Script
This script will deploy the custom profile, seed metadata framework records, push configuration records, and activate all necessary trigger handlers.

**Mac / Linux:**
```bash
sh Scripts/sh/data_load.sh
```

**Windows (PowerShell):**
```powershell
.\Scripts\ps1\data_load.ps1
```

---

## Troubleshooting

### Error: `Unknown user permission: EnableCommunityAppLauncher`
If your deployment fails loudly on the `LSC Custom Profile` step stating that `EnableCommunityAppLauncher` is an unknown user permission, this means your specific org shape does not support this permission.

**Fix:** 
1. Open `PackageComponents/profiles/LSC Custom Profile.profile-meta.xml`.
2. Locate the `<userPermissions>` block containing `<name>EnableCommunityAppLauncher</name>` (around line 93).
3. Delete that entire block.
4. Re-run the data loader script.

### Warnings: `DUPLICATE_VALUE` on tree import
During step 3 (Data Loader), you may see a table of errors stating `duplicate value found: Name duplicates value on record with id...`.
This is **safe to ignore**. It simply means that your org already contains the standard Life Sciences metadata categories provided by the package, so the CLI skipped recreating them.
