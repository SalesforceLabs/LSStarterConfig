# How to Handle Logs Containing Client IDs

This guide explains how to deal with already-logged messages that contain Client IDs in Papertrail.

## ⚠️ Important: Papertrail Limitations

**Papertrail logs are append-only** - Once logs are ingested, you **cannot selectively delete individual log messages**. This is a standard security feature of centralized logging systems to maintain audit trails.

## Options for Handling Sensitive Logs

### Option 1: Wait for Log Retention Expiration (Recommended)

**How it works:**
- Papertrail plans have log retention periods (e.g., 7 days, 30 days, 1 year)
- Logs older than your retention period are automatically purged
- No action needed - logs will expire naturally

**Steps:**
1. Check your Papertrail plan's retention period:
   - Free plan: 2 days
   - Choklad plan: 7 days
   - Growth plan: 30 days
   - Higher plans: Up to 1 year

2. Wait for the retention period to expire
3. Logs containing Client IDs will be automatically deleted

**Pros:**
- ✅ No manual work required
- ✅ Maintains audit trail integrity
- ✅ Automatic cleanup

**Cons:**
- ⏳ Takes time (depends on retention period)

---

### Option 2: Contact Papertrail Support (For Critical Issues)

**When to use:**
- If Client ID exposure is a critical security issue
- If you need immediate log removal
- If you're on a paid plan with support

**Steps:**
1. Contact Papertrail Support:
   - Email: support@papertrailapp.com
   - Or use the support form in your Papertrail dashboard

2. Request:
   - Explain the security concern
   - Provide approximate timestamps of logs containing Client IDs
   - Request log deletion or redaction

3. They may be able to:
   - Delete logs from a specific time range
   - Redact sensitive data in historical logs (if available)
   - Provide guidance on best practices

**Pros:**
- ✅ May get immediate resolution
- ✅ Professional support

**Cons:**
- ⚠️ May not be available for free plans
- ⚠️ May require justification
- ⚠️ Not guaranteed to work

---

### Option 3: Rotate/Change Your Client ID (If Compromised)

**When to use:**
- If you believe the Client ID has been compromised
- If logs are accessible to unauthorized users
- As a security best practice

**Steps:**

1. **Create a new Connected App in Salesforce:**
   ```
   Setup → App Manager → New Connected App
   ```

2. **Generate new Consumer Key (Client ID):**
   - New Connected App will have a new Consumer Key
   - Note down the new Consumer Key

3. **Update Heroku config:**
   ```bash
   heroku config:set SF_CLIENT_ID=<new-client-id> -a <your-app-name>
   ```

4. **Restart dynos:**
   ```bash
   heroku restart -a <your-app-name>
   ```

5. **Revoke old Connected App (optional but recommended):**
   - In Salesforce: Setup → App Manager → [Old Connected App] → Manage
   - Revoke or disable the old Connected App

**Pros:**
- ✅ Immediate security improvement
- ✅ Old Client ID becomes invalid
- ✅ Prevents future use of exposed Client ID

**Cons:**
- ⚠️ Requires updating configuration
- ⚠️ May require updating other systems using the same Client ID

---

### Option 4: Search and Monitor (For Awareness)

**Purpose:** Identify which logs contain Client IDs to understand exposure

**Steps:**

1. **Search Papertrail for Client ID patterns:**
   ```
   Search query: "Client ID:" OR "client_id"
   ```

2. **Review results:**
   - Check if Client IDs are masked (should show `3MVG9fph...la3` format)
   - Identify any unmasked Client IDs
   - Note timestamps of exposure

3. **Monitor access:**
   - Review who has access to Papertrail logs
   - Ensure only authorized personnel can view logs
   - Consider restricting Papertrail access if needed

**Pros:**
- ✅ Understands scope of exposure
- ✅ Helps with security assessment

**Cons:**
- ⚠️ Doesn't remove logs
- ⚠️ Only for awareness

---

## Current Status: Are Client IDs Actually Exposed?

### ✅ **Good News:** Current Code Masks Client IDs

Looking at the current code (`index.js` lines 354, 414), Client IDs are **already masked**:

```javascript
console.log('Client ID:', SF_CLIENT_ID ? 
  `${SF_CLIENT_ID.substring(0, 8)}...${SF_CLIENT_ID.substring(SF_CLIENT_ID.length - 4)}` 
  : 'not set');
```

**This means:**
- Only first 8 + last 4 characters are shown (e.g., `3MVG9fph...la3`)
- Full Client ID is **NOT** logged
- Even if logs are exposed, Client ID cannot be reconstructed

### ⚠️ **Check Your Logs:**

1. **Search Papertrail for:**
   ```
   "Client ID:"
   ```

2. **Verify format:**
   - ✅ **Safe:** `Client ID: 3MVG9fph...la3` (masked)
   - ⚠️ **Unsafe:** `Client ID: 3MVG9fphf4bStCMm3y6cqtc75utQZroK4ESpim6XJQQIVbIQngnkw48n2LpgWV8JCnNCy7wwyefL5kHDVtla3` (full ID)

3. **If you see full Client IDs:**
   - Check when those logs were created (before masking was added)
   - Follow Option 1 (wait for retention) or Option 3 (rotate Client ID)

---

## Best Practices Going Forward

### ✅ **Prevent Future Exposure:**

1. **Keep `LOG_VERBOSE=0` in production:**
   ```bash
   heroku config:set LOG_VERBOSE=0 -a <your-app-name>
   ```

2. **Only enable VERBOSE for debugging:**
   ```bash
   # Temporarily enable
   heroku config:set LOG_VERBOSE=1 -a <your-app-name>
   
   # Debug, then disable
   heroku config:set LOG_VERBOSE=0 -a <your-app-name>
   ```

3. **Monitor Papertrail regularly:**
   - Set up alerts for sensitive patterns
   - Review logs periodically
   - Ensure proper access controls

4. **Use environment variables:**
   - Never hardcode Client IDs
   - Use Heroku config vars
   - Rotate credentials periodically

---

## Summary

| Option | Action | Timeframe | Best For |
|--------|--------|-----------|----------|
| **Option 1** | Wait for retention | 2-30 days | Non-critical exposure |
| **Option 2** | Contact support | Immediate | Critical security issue |
| **Option 3** | Rotate Client ID | Immediate | Compromised credentials |
| **Option 4** | Search & monitor | Ongoing | Awareness & assessment |

## Recommendation

1. ✅ **First:** Check if Client IDs in logs are masked (should be `3MVG9fph...la3` format)
2. ✅ **If masked:** No immediate action needed - logs will expire naturally
3. ✅ **If unmasked:** Consider Option 3 (rotate Client ID) if security-critical
4. ✅ **Going forward:** Keep `LOG_VERBOSE=0` in production

## Additional Resources

- Papertrail Support: https://help.papertrailapp.com/
- Heroku Papertrail Add-on: https://devcenter.heroku.com/articles/papertrail
- Salesforce Connected App Security: https://help.salesforce.com/s/articleView?id=sf.connected_app_create.htm
