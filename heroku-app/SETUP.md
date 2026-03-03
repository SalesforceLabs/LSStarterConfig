# Setup Guide for LSStarter Config Deployer

This guide will help you configure the Heroku app to deploy Life Sciences Cloud Starter Configurations.

## Prerequisites

1. **Salesforce Sandbox** with a PKCE-enabled Connected App
2. **Heroku account** and CLI installed (for deployment)
3. **Node.js 18+** installed

## Quick Setup

Run the interactive setup script:

```bash
cd heroku-app
npm run setup
```

The script will guide you through:
- Entering your Salesforce Consumer Key
- Generating a secure session secret
- Configuring local development (.env)
- Configuring Heroku (config vars)

## Manual Setup

### 1. Get Your Salesforce Consumer Key

1. Log into your Salesforce **Sandbox**
2. Go to **Setup** → **Apps** → **App Manager**
3. Find your Connected App → Click dropdown → **View**
4. Copy the **Consumer Key**

### 2. Configure Connected App

Ensure your Connected App has:

- ✅ **OAuth Enabled**
- ✅ **Callback URL**: `https://your-heroku-app.herokuapp.com/oauth/callback`
- ✅ **Scopes**: `refresh_token`, `api`, `offline_access`
- ✅ **PKCE Required**: Enabled
- ℹ️ **Require Secret**: Can be disabled (not needed for PKCE)

### 3. Set Environment Variables

#### For Local Development:

Create a `.env` file:

```bash
SF_CLIENT_ID=your_consumer_key_here
SESSION_SECRET=$(openssl rand -hex 32)
NODE_ENV=development
PORT=3000
```

Install dotenv:

```bash
npm install dotenv
```

Add to top of `index.js`:

```javascript
require('dotenv').config();
```

#### For Heroku:

```bash
# Set Consumer Key
heroku config:set SF_CLIENT_ID=your_consumer_key_here

# Set Session Secret
heroku config:set SESSION_SECRET=$(openssl rand -hex 32)

# Enable session affinity (for multiple dynos)
heroku features:enable http-session-affinity
```

## Deployment

### Deploy to Heroku

```bash
# Login to Heroku
heroku login

# Create app (first time only)
heroku create your-app-name

# Push code
git push heroku main

# Open in browser
heroku open
```

### Run Locally

```bash
npm start
```

Access at http://localhost:3000

## Testing

1. Navigate to your deployed URL or http://localhost:3000
2. Click "Login & Deploy"
3. Authenticate with your Sandbox credentials
4. Watch the deployment progress

## Troubleshooting

### "Session expired or invalid"

- Session timeout (10 minutes)
- Solution: Click "Login & Deploy" again

### "Token exchange failed"

- Consumer Key incorrect
- Connected App not PKCE-enabled
- Callback URL mismatch
- Solution: Verify Connected App configuration

### "Deployment is supported only for Sandbox orgs"

- You're trying to use a Production org
- Solution: Only Sandbox orgs are supported (by design)

### "Configuration already exists"

- Org already has LifeSciMetadataCategory records
- Solution: Clear existing configuration first

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `SF_CLIENT_ID` | ✅ Yes | Consumer Key from Connected App |
| `SESSION_SECRET` | ⚠️ Recommended | Secret for session encryption (auto-generated if not set) |
| `NODE_ENV` | ❌ Optional | Set to `production` on Heroku |
| `PORT` | ❌ Optional | Port number (Heroku sets this automatically) |

## Security Notes

- ✅ Only Consumer Key needed (no secret stored)
- ✅ PKCE flow prevents CSRF attacks
- ✅ Sessions expire after 10 minutes
- ✅ Only works with Sandbox orgs
- ✅ User must explicitly authorize each deployment
- ⚠️ Keep your Consumer Key confidential
- ⚠️ Never commit `.env` file to git

## Architecture

```
User → Heroku App → Salesforce (PKCE OAuth)
                 ↓
           SF CLI (sfdx-url auth)
                 ↓
           Deploy Config to Sandbox
```

## Support

For issues with:
- **Connected App setup**: Contact your Salesforce admin
- **Heroku deployment**: Check Heroku logs with `heroku logs --tail`
- **Configuration errors**: Review deployment logs in the UI

## Next Steps

After setup:
1. Test login flow
2. Deploy to a test sandbox first
3. Share Heroku URL with team members
4. Monitor deployments via Heroku logs

---

**Need Help?** Run the interactive setup: `npm run setup`

