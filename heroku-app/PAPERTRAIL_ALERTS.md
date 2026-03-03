# Papertrail Alerts Configuration Guide

This guide helps you set up alerts in Papertrail to monitor your deployment application.

## Accessing Papertrail

1. **Via Heroku Dashboard:**
   - Go to your app → **Resources** tab
   - Click on **Papertrail** add-on
   - This opens the Papertrail web interface

2. **Direct URL:**
   - Papertrail URL is available in your Heroku config:
   ```bash
   heroku config:get PAPERTRAIL_URL -a <your-app-name>
   ```

## Recommended Alerts

### 1. Critical: Worker Job Failures

**Alert Name:** `Worker Job Failures`

**Search Query:**
```
[Worker] Job * failed
```

**Why:** Alerts when a deployment job fails in the worker. This is critical for monitoring deployment success.

**Settings:**
- **Frequency:** Real-time (immediate)
- **Minimum matches:** 1
- **Delivery:** Email to your team

---

### 2. Critical: Worker Errors

**Alert Name:** `Worker Process Errors`

**Search Query:**
```
[Worker] Error:
```

**Why:** Catches worker process errors that could indicate Redis connection issues, worker crashes, or other system problems.

**Settings:**
- **Frequency:** Real-time (immediate)
- **Minimum matches:** 1
- **Delivery:** Email to your team

---

### 2a. Critical: Worker Crashes

**Alert Name:** `Worker Dyno Crashes`

**Search Query:**
```
[Worker] FATAL: OR State changed from up to crashed OR Process exited with code OR Error R10 OR Error R15
```

**Why:** Alerts when a worker dyno crashes unexpectedly. This includes:
- Uncaught exceptions in the worker process
- Unhandled promise rejections
- Heroku system-level crashes (boot timeout, memory quota exceeded)
- Process exits with non-zero codes

**Note:** Heroku automatically logs dyno state changes (e.g., "State changed from up to crashed") and process exits. Our application code also logs fatal errors before crashing.

**Settings:**
- **Frequency:** Real-time (immediate)
- **Minimum matches:** 1
- **Delivery:** Email to your team

---

### 3. Critical: OAuth Token Exchange Failures

**Alert Name:** `OAuth Authentication Failures`

**Search Query:**
```
Token Exchange Error: OR OAuth error:
```

**Why:** Alerts when users can't authenticate, indicating Connected App configuration issues or Salesforce API problems.

**Settings:**
- **Frequency:** Real-time (immediate)
- **Minimum matches:** 1
- **Delivery:** Email to your team

---

### 4. Warning: Production Org Detected

**Alert Name:** `Production Org Attempts`

**Search Query:**
```
❌ ERROR: This org is a Production org
```

**Why:** Alerts when someone tries to deploy to a Production org (which is blocked for safety).

**Settings:**
- **Frequency:** Every 5 minutes
- **Minimum matches:** 1
- **Delivery:** Email (optional - more for monitoring)

---

### 5. Warning: Deployment Already Exists

**Alert Name:** `Configuration Already Exists`

**Search Query:**
```
Configuration already exists. Please clear LifeSciMetadataCategory records
```

**Why:** Alerts when users try to deploy when configs already exist, indicating they need to clear data first.

**Settings:**
- **Frequency:** Every 5 minutes
- **Minimum matches:** 1
- **Delivery:** Email (optional)

---

### 6. Info: Worker Startup

**Alert Name:** `Worker Started` (Optional)

**Search Query:**
```
[Worker] Deployment worker started. Waiting for jobs...
```

**Why:** Confirms workers are starting correctly after deployments or dyno restarts.

**Settings:**
- **Frequency:** Every 15 minutes
- **Minimum matches:** 1
- **Delivery:** Email (optional - for monitoring)

**Note:** ⚠️ This alert **requires `LOG_VERBOSE=1`** to fire. If `VERBOSE=0`, this log message is not written and the alert won't trigger.

---

### 7. Critical: Preflight Failures

**Alert Name:** `Salesforce CLI Not Ready`

**Search Query:**
```
sf init failed
```

**Why:** Alerts when the Salesforce CLI fails to initialize, which would prevent all deployments.

**Settings:**
- **Frequency:** Real-time (immediate)
- **Minimum matches:** 1
- **Delivery:** Email to your team

---

### 8. Warning: Data Load Script Failures

**Alert Name:** `Data Load Script Failed`

**Search Query:**
```
Data load script failed
```

**Why:** Alerts when the deployment script itself fails, indicating issues with the deployment process.

**Settings:**
- **Frequency:** Real-time (immediate)
- **Minimum matches:** 1
- **Delivery:** Email to your team

---

## How to Create an Alert

1. **Open Papertrail** (via Heroku dashboard or direct URL)

2. **Create a Saved Search:**
   - Click **"Saved Searches"** in the top menu
   - Click **"Create Saved Search"**
   - Enter a descriptive name (e.g., "Worker Job Failures")
   - Paste the search query from above
   - Click **"Save"**

3. **Create an Alert:**
   - Open your saved search
   - Click **"Create Alert"** button
   - Configure:
     - **Alert Name:** Same as saved search name
     - **Frequency:** Choose based on criticality (see recommendations above)
     - **Minimum Matches:** Usually 1 for critical alerts
     - **Delivery:** 
       - **Email:** Add email addresses (supports multiple)
       - **Webhook:** Optional - for Slack/PagerDuty integration
   - Click **"Create Alert"**

## Alert Frequency Options

- **Real-time (immediate):** For critical errors that need immediate attention
- **Every 5 minutes:** For warnings that should be addressed soon
- **Every 15 minutes:** For informational alerts
- **Hourly/Daily:** For summary reports

## Email Configuration

### Adding Multiple Recipients

When configuring email delivery:
- Enter multiple email addresses separated by commas
- Example: `team@example.com, oncall@example.com, admin@example.com`

### Email Subject Customization

Papertrail allows customizing email subjects:
- Use descriptive subjects like: `[CRITICAL] Worker Job Failed - Deployment App`
- Include key information: `[WARNING] Production Org Attempt Detected`

## Advanced: Webhook Integration

For Slack or PagerDuty integration:

1. **Create a webhook URL** in your notification service
2. **In Papertrail alert settings:**
   - Select **"Webhook"** as delivery method
   - Enter your webhook URL
   - Configure payload format (JSON)

### Example Slack Webhook Payload:
```json
{
  "text": "Alert: {{alert_name}}",
  "attachments": [{
    "color": "danger",
    "text": "{{matches_count}} matches found",
    "fields": [{
      "title": "Search Query",
      "value": "{{search_query}}",
      "short": false
    }]
  }]
}
```

## Testing Alerts

After creating alerts:

1. **Trigger a test error** (if safe to do so)
2. **Or wait for a real error** to occur
3. **Verify** you receive the alert email/webhook
4. **Check** that the alert contains useful information

## Monitoring Best Practices

1. **Start with critical alerts** (Worker failures, OAuth errors)
2. **Add warning alerts** after monitoring for a few days
3. **Review alert frequency** weekly and adjust as needed
4. **Set up a dedicated email** for alerts (e.g., `alerts@yourdomain.com`)
5. **Use email filters** to organize alerts by priority

## Alert Maintenance

- **Review monthly:** Check which alerts are firing most often
- **Tune queries:** Refine search queries to reduce false positives
- **Update recipients:** Keep email lists current
- **Archive old alerts:** Remove alerts that are no longer relevant

## Quick Reference: Critical Alerts Checklist

- [ ] Worker Job Failures (Real-time)
- [ ] Worker Process Errors (Real-time)
- [ ] Worker Dyno Crashes (Real-time)
- [ ] OAuth Authentication Failures (Real-time)
- [ ] Salesforce CLI Not Ready (Real-time)
- [ ] Data Load Script Failures (Real-time)

## VERBOSE Mode Dependency

**Question:** Will alerts fire when `LOG_VERBOSE=0` or `VERBOSE=0`?

**Answer:** Most alerts will fire regardless of VERBOSE setting, but one alert requires VERBOSE mode:

### ✅ Alerts that work with VERBOSE=0 (default):

All **critical alerts** work without VERBOSE mode:
- ✅ **Worker Job Failures** - Uses `console.error()` (always logged)
- ✅ **Worker Process Errors** - Uses `console.error()` (always logged)
- ✅ **Worker Dyno Crashes** - Uses `console.error()` for FATAL errors + Heroku system logs (always logged)
- ✅ **OAuth Authentication Failures** - Uses `console.error()` (always logged)
- ✅ **Salesforce CLI Not Ready** - Uses `console.error()` (always logged)
- ✅ **Data Load Script Failures** - Written via `write()` function (always logged)
- ✅ **Production Org Detected** - Written via `write()` function (always logged)
- ✅ **Configuration Already Exists** - Written via `write()` function (always logged)

### ⚠️ Alerts that require VERBOSE=1:

- ⚠️ **Worker Started** (Alert #6) - Uses `console.log()` conditional on VERBOSE

**Recommendation:** Set `LOG_VERBOSE=0` in production to reduce log noise. All critical alerts will still fire. Only the optional "Worker Started" informational alert requires VERBOSE mode.

## Support

For Papertrail-specific issues:
- Papertrail Documentation: https://help.papertrailapp.com/
- Heroku Papertrail Add-on: https://devcenter.heroku.com/articles/papertrail
