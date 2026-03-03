# Verbose Logging (VERBOSE=1) - Sensitive Information Summary

This document lists all sensitive debug information that is logged when `LOG_VERBOSE=1` or `VERBOSE=1` is set.

## ⚠️ Sensitive Information Logged When VERBOSE=1

### 1. OAuth Login Debug (`index.js` lines 351-358)

**Location:** `/login` endpoint

**Logged Information:**
- ✅ **Login Base URL** - Salesforce login URL (e.g., `https://login.salesforce.com` or custom domain)
- ✅ **Client ID** - **MASKED** (only first 8 chars + last 4 chars shown, e.g., `3MVG9fph...la3`)
- ✅ **Client ID Length** - Length of Client ID (not sensitive)
- ✅ **Redirect URI** - OAuth callback URL (e.g., `https://yourapp.herokuapp.com/oauth/callback`)
- ✅ **Code Challenge** - **TRUNCATED** (only first 20 chars shown, e.g., `abc123def456...`)

**Security Status:** ✅ **SAFE** - Client ID and Code Challenge are masked/truncated

---

### 2. Token Exchange Debug (`index.js` lines 410-454)

**Location:** `/oauth/callback` endpoint

**Logged Information:**
- ✅ **Token URL** - Salesforce token endpoint (e.g., `https://login.salesforce.com/services/oauth2/token`)
- ✅ **Grant Type** - Always `authorization_code` (not sensitive)
- ✅ **Client ID** - **MASKED** (only first 8 chars + last 4 chars shown)
- ✅ **Redirect URI** - OAuth callback URL
- ✅ **OAuth Code** - **TRUNCATED** (only first 20 chars shown, e.g., `aPrxxxxxxxxxxxxxxxxxx...`)
- ✅ **Code Verifier** - **TRUNCATED** (only first 20 chars shown, e.g., `abc123def456...`)
- ✅ **Token Response Status** - HTTP status code (e.g., `200`)
- ⚠️ **Error Details** - **LIMITED** (only first 200 chars if token exchange fails - could contain sensitive info)
- ✅ **Instance URL** - **MASKED** (only domain shown, e.g., `https://myinstance.salesforce.com/***`)

**Security Status:** ✅ **MOSTLY SAFE** - Most info is masked/truncated. Error details could potentially contain sensitive info but limited to 200 chars.

---

### 3. Worker Deployment Logs (`worker.js` via `vwrite()`)

**Location:** Worker job processing

**Logged Information (via `vwrite()` function):**
- ✅ **OAuth code exchanged for tokens** - Informational message
- ✅ **CLI login via sfdx-url completed** - Informational message
- ✅ **Running sandbox verification SOQL...** - Informational message
- ✅ **Sandbox check result** - Boolean result (e.g., `true` or `false`)
- ✅ **Querying LifeSciMetadataCategory COUNT()...** - Informational message
- ✅ **COUNT() returned** - Number (e.g., `COUNT() returned 0`)
- ✅ **Downloading repository branch** - Branch name (e.g., `Downloading repository branch main...`)
- ✅ **Repository downloaded and extracted** - Informational message
- ✅ **Starting data load script...** - Informational message
- ✅ **Deployment completed** - Informational message

**Security Status:** ✅ **SAFE** - All messages are informational, no sensitive data

**Note:** All `vwrite()` output goes through `write()` function which sanitizes sensitive patterns automatically.

---

### 4. Redis Connection Events

**Location:** Both `index.js` and `worker.js`

**Logged Information:**
- ✅ **`[Web] Redis connected`** - Connection event (not sensitive)
- ✅ **`[Web] Redis ready`** - Ready event (not sensitive)
- ✅ **`[Worker] Redis connected`** - Connection event (not sensitive)
- ✅ **`[Worker] Redis ready`** - Ready event (not sensitive)

**Security Status:** ✅ **SAFE** - No sensitive data

---

### 5. Worker Job Events

**Location:** `worker.js`

**Logged Information:**
- ✅ **`[Worker] Job {id} completed successfully`** - Job ID and completion status (not sensitive)
- ✅ **`[Worker] Deployment worker started. Waiting for jobs...`** - Startup message (not sensitive)

**Security Status:** ✅ **SAFE** - No sensitive data

---

## Summary of Sensitive Data Exposure

### ✅ **MASKED/TRUNCATED (Safe):**
- Client ID - Only first 8 + last 4 characters shown
- Code Challenge - Only first 20 characters shown
- OAuth Code - Only first 20 characters shown
- Code Verifier - Only first 20 characters shown
- Instance URL - Only domain shown (path masked)

### ⚠️ **PARTIALLY EXPOSED (Low Risk):**
- **Error Details** - First 200 characters of token exchange error responses (could contain error messages but not tokens)
- **Redirect URI** - Full callback URL (contains your app domain, not sensitive)
- **Login Base URL** - Salesforce login domain (public information)

### ✅ **NOT SENSITIVE:**
- All `vwrite()` messages (informational only)
- Redis connection events
- Worker job events
- Deployment progress messages

## Security Recommendations

1. ✅ **Keep `LOG_VERBOSE=0` in production** - Minimizes log exposure
2. ✅ **Use `VERBOSE=1` only for debugging** - Enable temporarily when troubleshooting
3. ✅ **Monitor Papertrail logs** - Check for any unexpected sensitive data
4. ✅ **Rotate logs regularly** - Don't keep verbose logs indefinitely

## Risk Assessment

**Overall Risk Level:** 🟢 **LOW**

- All tokens and credentials are masked/truncated
- Instance URLs are masked
- Only partial OAuth codes/verifiers are shown (not usable)
- Error details are limited to 200 chars
- Most verbose logs are informational only

**When VERBOSE=0:** 🟢 **VERY LOW RISK** - No sensitive debug info is logged.
