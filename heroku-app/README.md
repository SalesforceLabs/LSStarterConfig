# LSStarterConfig Deployer (Heroku)

Simple Heroku web app that logs into a Salesforce Sandbox with an SFDX auth URL and deploys the LSStarterConfig sample configuration using the Salesforce CLI (`sf`), matching the macOS shell script flow.

## How it works
1. You paste an SFDX auth URL (generated on your machine once) and provide an org alias (e.g., `LSStarterConfigSandbox`).
2. The app:
   - logs in via `sf org login sfdx-url`
   - verifies the org is a Sandbox
   - runs `SELECT COUNT() FROM LifeSciMetadataCategory` and exits if data exists
   - downloads the LSStarterConfig repo for a chosen branch (default `main`)
   - executes `Scripts/sh/data_load.sh` from the repo
3. Returns logs/results in the browser.

## Deploy to Heroku

Prereqs: Heroku account and the Heroku CLI.

```bash
cd heroku-app
heroku create
git init
git add .
git commit -m "Heroku app"
heroku buildpacks:add heroku/nodejs
git push heroku HEAD:main
heroku open
```

Alternatively, use the Heroku Dashboard to create an app and connect this folder as a GitHub repo.

## Generate an SFDX auth URL (run locally once)

On your machine where you can log in interactively:
```bash
# If not already logged in:
sf org login web -r https://test.salesforce.com -a LSStarterConfigSandbox --set-default

# Generate SFDX auth URL
sf org generate sfdx-url -o LSStarterConfigSandbox --json
```
Copy the URL (starts with `force://PlatformCLI::...`) and paste it into the app form.

## Notes
- The app installs `@salesforce/cli` as a dependency and uses `npx sf` at runtime.
- The repo ZIP is downloaded directly from GitHub; no git binary required.
- The filesystem is ephemeral per dyno; not intended for persistent artifacts.
- This app is a proof-of-concept; for production, add:
  - authentication/authorization for the web page
  - logging/monitoring
  - input validation and rate limiting
  - version pinning (tag/commit SHA) instead of branch where needed


