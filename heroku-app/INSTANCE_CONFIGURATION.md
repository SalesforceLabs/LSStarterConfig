# Instance Configuration Guide

This application restricts deployments based on org type and instance name.

## Deployment Rules

Deployment is allowed if **either** of the following conditions is met:

1. **The org is a Sandbox** (`IsSandbox = true` in Organization object) ✅
2. **The org's instance name** (`InstanceName` field in Organization object) is in the configured allowed list ✅

If **neither** condition is met, deployment is denied ❌

## Configuration Methods

You can configure allowed instance names using environment variables:

### Environment Variable (Comma-Separated)

Set `ALLOWED_INSTANCE_NAMES` with comma-separated instance names:

**For Heroku:**
```bash
heroku config:set ALLOWED_INSTANCE_NAMES="USA794,USA796" --app your-app-name
```

**For Local Development:**
Add to `heroku-app/.env`:
```bash
ALLOWED_INSTANCE_NAMES="USA794,USA796"
```

**Example:**
```bash
heroku config:set ALLOWED_INSTANCE_NAMES="USA794,USA796,CS123,NA456" --app lsstarterconfig
```

This works for all org types (custom domains, direct instance URLs, etc.).

## How It Works

1. **User authenticates** via OAuth
2. **App authenticates** to the Salesforce org using the refresh token
3. **App queries** the Organization object for:
   - `IsSandbox` field (boolean)
   - `InstanceName` field (string, e.g., "USA794")
4. **Validation logic:**
   - If `IsSandbox = true` → ✅ Allow deployment
   - Else if `InstanceName` is in `allowedInstanceNames` list → ✅ Allow deployment
   - Otherwise → ❌ Deny deployment

## Default Behavior

**If no `allowedInstanceNames` are configured**, only Sandbox orgs are allowed. Production orgs will be denied unless they're Sandboxes.

## Examples

### Example 1: Allow Only Sandboxes (No Instance Names Configured)

**Configuration:** Leave `ALLOWED_INSTANCE_NAMES` unset or empty

**Result:**
- ✅ Sandbox orgs → Allowed
- ❌ Production orgs → Denied

### Example 2: Allow Specific Instance Names

**Configuration:**
```bash
heroku config:set ALLOWED_INSTANCE_NAMES="USA794,USA796" --app your-app-name
```

**Result:**
- ✅ Sandbox orgs → Allowed (regardless of instance name)
- ✅ Production orgs on USA794 → Allowed
- ✅ Production orgs on USA796 → Allowed
- ❌ Production orgs on other instances → Denied

### Example 3: Allow All Sandboxes + Specific Production Instances

**Configuration:**
```bash
heroku config:set ALLOWED_INSTANCE_NAMES="USA794,USA796" --app your-app-name
```

**Result:**
- ✅ Any Sandbox org → Allowed
- ✅ Production orgs on USA794 → Allowed
- ✅ Production orgs on USA796 → Allowed
- ❌ Production orgs on other instances → Denied

## Error Messages

### Sandbox Denied (Shouldn't happen, but if it does):
```
Access denied: This deployment tool only allows Sandbox orgs. Please log in to a Sandbox org, or configure allowed instance names.
```

### Production Org Denied (Instance Name Not in List):
```
Access denied: Instance name CS123 is not in the allowed list (USA794, USA796). This deployment tool only allows Sandbox orgs or orgs with instance names in the configured list.
```

### Production Org Denied (No Instance Names Configured):
```
Access denied: This deployment tool only allows Sandbox orgs. Please log in to a Sandbox org, or configure allowed instance names.
```

### Instance Name Could Not Be Determined:
```
Access denied: Could not determine instance name. This deployment tool only allows Sandbox orgs or orgs with instance names in the configured list.
```

## Viewing Current Configuration

To view your current Heroku config vars:

```bash
heroku config --app your-app-name
```

To view the configuration locally:

```bash
cat heroku-app/.env | grep ALLOWED_INSTANCE_NAMES
```

## Updating Configuration

### On Heroku:

1. Update the config var:
   ```bash
   heroku config:set ALLOWED_INSTANCE_NAMES="USA794,USA796" --app your-app-name
   ```

2. Restart the app to reload configuration:
   ```bash
   heroku restart --app your-app-name
   ```

### Locally:

1. Edit `heroku-app/.env` and update `ALLOWED_INSTANCE_NAMES`
2. Restart your local server

## Testing

After configuring instance names, test by:

1. Logging in with a **Sandbox org** → Should succeed ✅
2. Logging in with a **Production org** on an **allowed instance** → Should succeed ✅
3. Logging in with a **Production org** on a **non-allowed instance** → Should fail with 403 error ❌

## Instance Name Format

- Instance names are queried directly from the Organization object
- Matching is **case-insensitive** (automatically converted to uppercase)
- Works with **all org types** including:
  - Custom domains (e.g., `mycompany--dev.sandbox.my.salesforce.com`)
  - Direct instance URLs (e.g., `https://na123.salesforce.com`)
  - My Domain URLs

## Security Notes

- Validation happens **after** OAuth authentication but **before** deployment starts
- The Organization object is queried using the authenticated session
- Sandbox orgs are **always allowed** regardless of instance name configuration
- Configuration is loaded at application startup; restart required for changes to take effect

## Troubleshooting

### Issue: "Access denied" for a Sandbox org

**This shouldn't happen.** If it does:
1. Check that the Organization query is working correctly
2. Review logs with `VERBOSE=1` to see the `IsSandbox` value
3. Verify the org is actually a Sandbox (check in Salesforce Setup)

### Issue: "Access denied" for a Production org on an allowed instance

**Check:**
1. Verify the instance name is spelled correctly (case-insensitive)
2. Check Heroku config vars: `heroku config --app your-app-name`
3. Review logs with `VERBOSE=1` to see the queried `InstanceName` value
4. Ensure the instance name matches exactly (e.g., `USA794` not `US794`)

### Issue: "Could not determine instance name"

**Cause:** The Organization query failed or returned null.

**Fix:**
1. Check that the org is accessible
2. Verify the authenticated session is valid
3. Review logs with `VERBOSE=1` to see the query error
4. Ensure the org has proper permissions to query Organization object

### Issue: Configuration not loading

**Check:**
1. Verify environment variable is set: `heroku config --app your-app-name` (for Heroku) or check `.env` file (for local)
2. Verify format is correct: comma-separated values (e.g., `"USA794,USA796"`)
3. Check Heroku config vars: `heroku config --app your-app-name`
4. Restart the app after configuration changes
