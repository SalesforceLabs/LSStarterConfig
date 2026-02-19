require('dotenv').config();
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const express = require('express');
const session = require('express-session');
const RedisStore = require('connect-redis').default;
const { spawn } = require('child_process');
const fetch = require('node-fetch');
const { Queue } = require('bullmq');
const Redis = require('ioredis');

const app = express();
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.use(express.json({ limit: '1mb' }));
 
 // Ensure req.protocol reflects the original protocol (https on Heroku)
 app.set('trust proxy', 1);

// Redis connection for sessions (separate from queue connection to avoid conflicts)
// Use same Redis instance but different connection for session store
const sessionRedisConnection = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
  maxRetriesPerRequest: 3,
  enableReadyCheck: false,
  enableOfflineQueue: false,
  retryStrategy: (times) => {
    const delay = Math.min(times * 100, 2000);
    if (times > 10) {
      return null;
    }
    return delay;
  },
  reconnectOnError: (err) => {
    const targetError = 'READONLY';
    if (err.message.includes(targetError)) {
      return true;
    }
    return false;
  },
  keepAlive: 30000,
  connectTimeout: 10000,
  tls: process.env.REDIS_URL && process.env.REDIS_URL.startsWith('rediss://') ? {
    rejectUnauthorized: false, // Heroku Redis uses self-signed certs
  } : undefined,
});

// Session middleware for PKCE flow - using Redis store for multi-dyno support
// IMPORTANT: For OAuth redirects from Salesforce, we need sameSite: 'none' with secure: true
// This allows cookies to be sent on cross-site redirects (Salesforce -> Heroku)
app.use(session({
  store: new RedisStore({ 
    client: sessionRedisConnection,
    prefix: 'lsstarter:sess:',
  }),
  secret: process.env.SESSION_SECRET || crypto.randomBytes(32).toString('hex'),
  resave: false,
  saveUninitialized: false,
  name: 'lsstarter.sid', // Custom session name to avoid conflicts
  cookie: {
    secure: process.env.NODE_ENV === 'production', // true on Heroku (HTTPS) - REQUIRED for sameSite: 'none'
    httpOnly: true,
    sameSite: process.env.NODE_ENV === 'production' ? 'none' : 'lax', // 'none' for cross-site redirects (requires secure: true)
    maxAge: 600000, // 10 minutes - enough for OAuth flow
    // Don't set domain - let browser use default (current domain)
    // This ensures cookies work with custom domains
  }
}));

const REPO = 'SalesforceLabs/LSStarterConfig';
const DEFAULT_BRANCH = 'main';
// Use login.salesforce.com to support both Sandbox and Production orgs
// Can be overridden with SF_LOGIN_BASE env var (e.g., https://test.salesforce.com for Sandbox-only)
const SF_LOGIN_BASE = process.env.SF_LOGIN_BASE || 'https://login.salesforce.com';
const SF_CLIENT_ID = process.env.SF_CLIENT_ID || '';
// SF_CLIENT_SECRET not required for PKCE flow

// Instance whitelist configuration (only instance names from Organization object)
let allowedInstanceNames = [];

// Load instance configuration from environment variable
function loadInstanceConfig() {
  // Load instance names from comma-separated environment variable
  if (process.env.ALLOWED_INSTANCE_NAMES) {
    allowedInstanceNames = process.env.ALLOWED_INSTANCE_NAMES.split(',').map(s => s.trim().toUpperCase()).filter(Boolean);
    console.log(`[Config] Loaded instance names from ALLOWED_INSTANCE_NAMES env var: ${allowedInstanceNames.join(', ') || 'none'}`);
    return;
  }

  // Default: no instance names configured (only sandboxes allowed)
  console.log('[Config] No instance names configured. Only Sandbox orgs will be allowed.');
}

// Validate if deployment is allowed based on org type and instance name
// Logic (based ONLY on Organization object fields):
// 1. If org is a Sandbox (IsSandbox = true), allow deployment
// 2. If org instance name (InstanceName) is in the configured list, allow deployment
// 3. Otherwise, deny deployment
function isDeploymentAllowed(isSandbox, instanceName) {
  // Rule 1: Sandbox orgs are always allowed
  if (isSandbox) {
    return { allowed: true, reason: 'Sandbox org detected' };
  }

  // Rule 2: Check if instance name is in the allowed list
  if (allowedInstanceNames.length > 0) {
    if (instanceName && allowedInstanceNames.includes(instanceName.toUpperCase())) {
      return { allowed: true, reason: `Instance name ${instanceName} is in the allowed list` };
    }
    
    // If instance names are configured but instanceName is null or not in list, deny
    if (!instanceName) {
      return { 
        allowed: false, 
        reason: 'Could not determine instance name. This deployment tool only allows Sandbox orgs or orgs with instance names in the configured list.' 
      };
    }
    
    return { 
      allowed: false, 
      reason: `Instance name ${instanceName} is not in the allowed list (${allowedInstanceNames.join(', ')}). This deployment tool only allows Sandbox orgs or orgs with instance names in the configured list.` 
    };
  }

  // If no instance names are configured, only sandboxes are allowed
  return { 
    allowed: false, 
    reason: 'This deployment tool only allows Sandbox orgs. Please log in to a Sandbox org, or configure allowed instance names.' 
  };
}

// Load configuration on startup
loadInstanceConfig();

// Redis connection for queue
// Heroku Redis uses TLS - configure ioredis to handle it properly
const redisConnection = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
  maxRetriesPerRequest: 3, // Limit retries to avoid connection buildup
  enableReadyCheck: false,
  enableOfflineQueue: false, // Don't queue commands when offline (reduces connections)
  retryStrategy: (times) => {
    const delay = Math.min(times * 100, 2000);
    // Stop retrying after 10 attempts
    if (times > 10) {
      return null;
    }
    return delay;
  },
  reconnectOnError: (err) => {
    const targetError = 'READONLY';
    if (err.message.includes(targetError)) {
      return true; // Reconnect on READONLY errors
    }
    return false; // Don't reconnect on other errors
  },
  keepAlive: 30000, // Keep connections alive for 30 seconds (reuse connections)
  connectTimeout: 10000, // 10 second connection timeout
  tls: process.env.REDIS_URL && process.env.REDIS_URL.startsWith('rediss://') ? {
    rejectUnauthorized: false, // Heroku Redis uses self-signed certs
  } : undefined,
});

// Handle Redis connection errors gracefully (throttle logging)
let lastWebErrorTime = 0;
let lastWebErrorMessage = '';

redisConnection.on('error', (err) => {
  const now = Date.now();
  const errorMsg = err.message || String(err);
  
  // Throttle error logging - only log once per 5 seconds for same error
  if (errorMsg !== lastWebErrorMessage || (now - lastWebErrorTime) > 5000) {
    console.error('[Web] Redis connection error:', errorMsg);
    lastWebErrorTime = now;
    lastWebErrorMessage = errorMsg;
  }
  // Don't crash - let ioredis handle reconnection
});

redisConnection.on('connect', () => {
  // Only log connection events if verbose (reduces log noise)
  const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
  if (VERBOSE) {
    console.log('[Web] Redis connected');
  }
  // Reset error tracking on successful connection
  lastWebErrorTime = 0;
  lastWebErrorMessage = '';
});

redisConnection.on('ready', () => {
  // Only log ready events if verbose (reduces log noise)
  const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
  if (VERBOSE) {
    console.log('[Web] Redis ready');
  }
});

// BullMQ queue for deployment jobs
const deploymentQueue = new Queue('deployment-queue', {
  connection: redisConnection,
});

const preflight = { ready: false, message: 'Initializing...' };

function tmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'lsstarter-'));
}

function spawnPromise(cmd, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { ...options, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout?.on('data', (d) => { stdout += String(d); });
    child.stderr?.on('data', (d) => { stderr += String(d); });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve({ stdout, stderr, code });
      else {
        const err = new Error(stderr || `Process exited with code ${code}`);
        err.code = code;
        err.stdout = stdout;
        err.stderr = stderr;
        reject(err);
      }
    });
  });
}

async function runSf(args, env = {}) {
  const mergedEnv = {
    ...process.env,
    SF_AUTOUPDATE_DISABLE: '1',
    NODE_NO_WARNINGS: '1',
    ...env,
  };
  const { stdout } = await spawnPromise('npx', ['sf', ...args], { env: mergedEnv });
  return { stdout };
}

// Preflight: ensure sf CLI is invokable
(async () => {
  try {
    const { stdout } = await spawnPromise('npx', ['sf', '--version'], {
      env: { ...process.env, SF_AUTOUPDATE_DISABLE: '1', NODE_NO_WARNINGS: '1' },
    });
    const firstLine = String(stdout || '').split('\n')[0].trim();
    preflight.ready = true;
    preflight.message = firstLine ? `sf OK: ${firstLine}` : 'sf OK';
  } catch (e) {
    preflight.ready = false;
    preflight.message = `sf init failed: ${String(e.message || e)}`;
    // Log to console for Papertrail alerts (critical error)
    console.error('sf init failed:', String(e.message || e));
  }
})();

// Helper function to get username from org
async function getUsername(alias) {
  try {
    const disp = await runSf(['org', 'display', '--json', '-o', alias]);
    const dispJson = JSON.parse(disp.stdout || '{}');
    return dispJson?.result?.username || '';
  } catch {
    return '';
  }
}

// Query Organization object for IsSandbox and InstanceName
async function getOrgInfo(alias) {
  try {
    const soqlOut = await runSf(['data', 'query', '-q', 'SELECT IsSandbox, InstanceName FROM Organization LIMIT 1', '--json', '-o', alias]);
    const soqlJson = JSON.parse(soqlOut.stdout || '{}');
    const org = soqlJson?.result?.records?.[0];
    if (!org) {
      return { isSandbox: false, instanceName: null };
    }
    const isSandbox = org.IsSandbox === true || String(org.IsSandbox).toLowerCase() === 'true';
    const instanceName = org.InstanceName ? String(org.InstanceName).toUpperCase() : null;
    return { isSandbox, instanceName };
  } catch (e) {
    const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
    if (VERBOSE) {
      console.log(`[Config] Could not query Organization: ${e.message || String(e)}`);
    }
    return { isSandbox: false, instanceName: null };
  }
}

app.get('/', (req, res) => {
  // Build the important message dynamically based on configured instance names
  let importantMessage = '';
  if (allowedInstanceNames.length > 0) {
    importantMessage = `This deployment tool works with <strong>any Sandbox org</strong>. If the org is a Production org, deployment will be supported only for specific instance names (${allowedInstanceNames.join(',')}).`;
  } else {
    importantMessage = `This deployment tool works with <strong>any Sandbox org</strong>. Production orgs are not supported.`;
  }
  
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(`
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Life Sciences Cloud for Customer Engagement Starter Configuration Deployer</title>
    <style>
      :root {
        /* Approximate SLDS palette */
        --brand-primary: #0176d3;         /* slds color-brand */
        --brand-primary-dark: #0b5cab;    /* hover */
        --text: #080707;                  /* slds text default */
        --muted: #706e6b;                 /* slds text weak */
        --bg: #f3f2f2;                    /* slds color-background */
        --card: #ffffff;                  /* slds color-background-alt */
        --border: #dddbda;                /* slds color-border */
      }
      body {
        font-family: "Salesforce Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        font-size: 14px; /* SLDS base size */
        line-height: 1.5;
        margin: 0;
        color: var(--text);
        background: var(--bg);
      }
      .container {
        max-width: 960px;
        margin: 48px auto;
        padding: 0 20px;
      }
      .card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 4px;
        box-shadow: 0 2px 6px rgba(0,0,0,0.06);
        overflow: hidden;
      }
      .hero {
        padding: 16px 20px;
        background: linear-gradient(135deg, var(--brand-primary), #1b96ff);
        color: #fff;
      }
      .hero h1 { margin: 0; font-weight: 600; font-size: 18px; }
      .content { padding: 16px 20px; }
      .note { color: var(--muted); }
      .row { display: flex; gap: 12px; align-items: center; margin-top: 12px; }
      button {
        margin: 0;
        padding: 8px 14px;
        font: inherit;
        background: var(--brand-primary);
        border: 1px solid var(--brand-primary);
        color: #fff;
        border-radius: 4px;
        cursor: pointer;
      }
      button:hover { background: var(--brand-primary-dark); border-color: var(--brand-primary-dark); }
      button:disabled { opacity: 0.6; cursor: not-allowed; }
      .divider { margin: 20px 0; border-top: 1px solid var(--border); }
      pre { font: inherit; }
      .log {
        background: #fafaf9;
        border: 1px solid var(--border);
        border-radius: 4px;
        padding: 12px;
        min-height: 50vh;
        overflow: auto;
        white-space: pre-wrap;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="card">
        <div class="hero">
          <h1>Life Sciences Cloud for Customer Engagement Starter Configuration Deployer</h1>
        </div>
        <div class="content">
          <div id="preflight" class="note"></div>
          <p class="note">Click "Login & Deploy" to authenticate in your Salesforce organization and deploy the sample configurations.<br/>You will be redirected to Salesforce to sign in, then returned here to watch progress.</p>
          <div style="background: #fff3cd; border: 1px solid #ffc107; border-radius: 4px; padding: 12px; margin: 12px 0;">
            <strong style="color: #856404;">⚠️ Important:</strong>
            <span style="color: #856404;">${importantMessage}</span>
          </div>
          <div class="row">
            <button id="loginDeploy">Login & Deploy</button>
          </div>
          <div class="divider"></div>
          <pre id="log" class="log"></pre>
        </div>
      </div>
    </div>

    <script>
      const logEl = document.getElementById('log');
      const loginBtn = document.getElementById('loginDeploy');
      const urlParams = new URLSearchParams(window.location.search);
      let runId = urlParams.get('id') || null;
      async function loadPreflight(){
        try{
          const r = await fetch('/preflight');
          if(!r.ok) return;
          const d = await r.json();
          const el = document.getElementById('preflight');
          if (!d.ready) {
            el.style.display = 'block';
            el.textContent = d.message || 'Salesforce CLI is not ready.';
            el.style.color = '#b00020';
            if (loginBtn) loginBtn.disabled = true;
          } else {
            el.style.display = 'none';
            el.textContent = '';
            if (loginBtn) loginBtn.disabled = false;
          }
        } catch {}
      }

      async function poll() {
        if (!runId) return;
        try {
          const r = await fetch('/status?id=' + encodeURIComponent(runId));
          if (!r.ok) return;
          const data = await r.json();
          logEl.textContent = (data.logs || []).join('\\n');
          if (data.status === 'success' || data.status === 'error') return;
        } catch {}
        setTimeout(poll, 2000);
      }

      if (runId) {
        logEl.textContent = 'Authentication successful. Starting deployment...\\nThis may take 2–3 minutes. Progress will appear below.\\n';
        poll();
      }
      loadPreflight();

      loginBtn?.addEventListener('click', () => {
        window.location.href = '/login';
      });
    </script>
  </body>
</html>
  `);
});

// Preflight endpoint
app.get('/preflight', (req, res) => {
  res.json(preflight);
});

// Start OAuth web login and redirect to Salesforce (PKCE flow)
app.get('/login', (req, res) => {
  const targetAlias = (String(req.query.alias || 'LSStarterConfigSandbox')).trim();
  const repoBranch = (String(req.query.branch || DEFAULT_BRANCH)).trim();
  
  if (!SF_CLIENT_ID) {
    res.status(500).send('Server not configured: set SF_CLIENT_ID.');
    return;
  }
  
  // Use configured SF_LOGIN_BASE (defaults to login.salesforce.com)
  // login.salesforce.com works for both Sandbox and Production orgs when using Production Connected App
  const loginBase = SF_LOGIN_BASE;
  
  // Generate PKCE values
  const codeVerifier = crypto.randomBytes(32).toString('base64url');
  const codeChallenge = crypto.createHash('sha256')
    .update(codeVerifier)
    .digest('base64url');
  
  const protoLogin = (req.headers['x-forwarded-proto'] || '').split(',')[0] || req.protocol;
  const baseUrl = `${protoLogin}://${req.get('host')}`;
  const redirectUri = `${baseUrl}/oauth/callback`;
  
  // Store code_verifier and redirect_uri in session (must use exact same redirect_uri in token exchange)
  req.session.codeVerifier = codeVerifier;
  req.session.redirectUri = redirectUri; // Store redirect_uri to ensure exact match
  req.session.codeChallenge = codeChallenge; // Store code_challenge for verification
  req.session.pkceState = { alias: targetAlias, branch: repoBranch };
  const state = Buffer.from(JSON.stringify({ alias: targetAlias, branch: repoBranch }), 'utf8').toString('base64url');
  
  // Store login base URL in session for token exchange
  req.session.loginBase = loginBase;
  
  // Ensure session is saved before redirecting (critical for Redis sessions)
  // Wait for session save to complete before redirecting
  
  // Debug logging (Client ID masked for security)
  const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
  if (VERBOSE) {
    console.log('=== OAuth Login Debug ===');
    console.log('Login Base URL:', loginBase);
    console.log('Client ID:', SF_CLIENT_ID ? `${SF_CLIENT_ID.substring(0, 8)}...${SF_CLIENT_ID.substring(SF_CLIENT_ID.length - 4)}` : 'not set');
    console.log('Client ID Length:', SF_CLIENT_ID ? SF_CLIENT_ID.length : 0);
    console.log('Redirect URI:', redirectUri);
    console.log('Code Challenge:', codeChallenge.substring(0, 20) + '...');
    console.log('Session ID:', req.sessionID);
    console.log('========================');
  }
  
  // Build authorization URL with PKCE parameters
  // IMPORTANT: Salesforce requires code_challenge to be URL-encoded in the authorization URL
  // Even though base64url is URL-safe, Salesforce's OAuth implementation expects URL-encoded values
  const authUrl = `${loginBase}/services/oauth2/authorize?` +
    `response_type=code&` +
    `client_id=${encodeURIComponent(SF_CLIENT_ID)}&` +
    `redirect_uri=${encodeURIComponent(redirectUri)}&` +
    `scope=${encodeURIComponent('refresh_token api offline_access')}&` +
    `state=${state}&` +
    `prompt=login&` +
    `code_challenge=${encodeURIComponent(codeChallenge)}&` +  // URL-encode for Salesforce compatibility
    `code_challenge_method=S256`;
  
  // Debug: Log the exact code_challenge sent to Salesforce
  if (VERBOSE) {
    console.log('Code Challenge sent to Salesforce:', codeChallenge);
    console.log('Code Challenge (raw):', codeChallenge);
    console.log('Code Challenge (URL-encoded):', encodeURIComponent(codeChallenge));
    console.log('Code Challenge length:', codeChallenge.length);
    console.log('Authorization URL (first 300 chars):', authUrl.substring(0, 300) + '...');
  }
  
  // Save session before redirecting to ensure it's persisted
  // CRITICAL: Must save session before redirect so cookie is set
  req.session.save((err) => {
    if (err) {
      console.error('[OAuth] Session save error before redirect:', err.message);
      res.status(500).send('Failed to initialize session. Please try again.');
      return;
    }
    
    const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
    if (VERBOSE) {
      console.log('[OAuth] Session saved successfully before redirect');
      console.log('[OAuth] Session ID:', req.sessionID);
      console.log('[OAuth] Session cookie will be set:', req.session.cookie);
      console.log('[OAuth] Cookie name:', req.session.cookie.name);
      console.log('[OAuth] Cookie secure:', req.session.cookie.secure);
      console.log('[OAuth] Cookie sameSite:', req.session.cookie.sameSite);
    }
    
    // Redirect after session is saved
    res.redirect(authUrl);
  });
});

// OAuth callback: exchange code using PKCE, start deployment in background, redirect back with run id
app.get('/oauth/callback', async (req, res) => {
  const code = String(req.query.code || '');
  const error = req.query.error;
  const errorDescription = req.query.error_description;
  if (error) {
    const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
    let errorMessage = `OAuth error: ${error}`;
    if (errorDescription) {
      errorMessage += ` - ${decodeURIComponent(String(errorDescription))}`;
    }
    if (VERBOSE) {
      console.error('[OAuth] Authorization error:', errorMessage);
      console.error('[OAuth] Error details:', { error, errorDescription, query: req.query });
    }
    
    // Provide helpful messages for common errors
    if (error === 'invalid_grant' && errorDescription && errorDescription.includes('expired')) {
      errorMessage += '. This usually happens when the redirect_uri doesn\'t match exactly or there\'s a delay. Please try logging in again.';
    } else if (error === 'invalid_client_id') {
      errorMessage += '. Please check that the Connected App Consumer Key (SF_CLIENT_ID) is correct.';
    } else if (error === 'redirect_uri_mismatch') {
      errorMessage += '. The callback URL must match exactly what\'s configured in your Connected App.';
    }
    
    res.status(400).send(errorMessage);
    return;
  }
  if (!code) {
    res.status(400).send('Missing OAuth code');
    return;
  }
  
  // Retrieve code_verifier and redirect_uri from session (must use exact same redirect_uri)
  const codeVerifier = req.session.codeVerifier;
  const storedCodeChallenge = req.session.codeChallenge;
  let redirectUri = req.session.redirectUri; // Use stored redirect_uri to ensure exact match
  
  if (!codeVerifier) {
    const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
    if (VERBOSE) {
      // Extract session ID from cookie to check if it matches
      let cookieSessionId = null;
      if (req.headers.cookie) {
        const cookies = req.headers.cookie.split(';').map(c => c.trim());
        const sessionCookie = cookies.find(c => c.startsWith('lsstarter.sid='));
        if (sessionCookie) {
          // Cookie format: lsstarter.sid=s%3AsessionId.signature
          // URL decode and extract session ID
          try {
            const cookieValue = decodeURIComponent(sessionCookie.split('=')[1]);
            // Express session cookie format: s:sessionId.signature
            if (cookieValue.startsWith('s:')) {
              cookieSessionId = cookieValue.split('.')[0].substring(2);
            }
          } catch (e) {
            // Ignore decode errors
          }
        }
      }
      
      // Try to manually check Redis for the session
      let redisSessionData = null;
      if (cookieSessionId) {
        try {
          const redisKey = `lsstarter:sess:${cookieSessionId}`;
          const rawData = await sessionRedisConnection.get(redisKey);
          if (rawData) {
            redisSessionData = JSON.parse(rawData);
          }
        } catch (e) {
          console.error('[OAuth] Error checking Redis for session:', e.message);
        }
      }
      
      console.log('[OAuth] Session debug:', {
        currentSessionId: req.sessionID,
        cookieSessionId: cookieSessionId,
        sessionIdsMatch: req.sessionID === cookieSessionId,
        hasSession: !!req.session,
        sessionKeys: req.session ? Object.keys(req.session) : [],
        cookies: req.headers.cookie ? 'present' : 'missing',
        cookieName: 'lsstarter.sid',
        redisStore: 'using Redis store',
        redisSessionFound: !!redisSessionData,
        redisSessionKeys: redisSessionData ? Object.keys(redisSessionData) : [],
        host: req.get('host'),
        protocol: req.protocol,
        'x-forwarded-proto': req.headers['x-forwarded-proto'],
      });
      
      // Try to find the session cookie in the request
      if (req.headers.cookie) {
        const cookies = req.headers.cookie.split(';').map(c => c.trim());
        const sessionCookie = cookies.find(c => c.startsWith('lsstarter.sid='));
        console.log('[OAuth] Session cookie found:', sessionCookie ? sessionCookie.substring(0, 50) + '...' : 'NOT FOUND');
        console.log('[OAuth] All cookies:', cookies);
      }
    }
    res.status(400).send('Session expired or invalid. Please try logging in again. If using a custom domain, ensure cookies are enabled and try again.');
    return;
  }
  
  // Verify code_verifier matches code_challenge (PKCE validation)
  if (storedCodeChallenge) {
    const verifyChallenge = crypto.createHash('sha256')
      .update(codeVerifier)
      .digest('base64url');
    if (verifyChallenge !== storedCodeChallenge) {
      const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
      if (VERBOSE) {
        console.error('[OAuth] PKCE verification failed: code_verifier does not match code_challenge');
      }
      res.status(400).send('OAuth security verification failed. Please try logging in again.');
      return;
    }
  }
  
  if (!redirectUri) {
    // Fallback: construct redirect_uri if not in session (for backward compatibility)
    const protoCb = (req.headers['x-forwarded-proto'] || '').split(',')[0] || req.protocol;
    const baseUrl = `${protoCb}://${req.get('host')}`;
    redirectUri = `${baseUrl}/oauth/callback`;
    console.warn('[OAuth] redirect_uri not in session, using constructed value:', redirectUri);
  }
  
  let meta = {};
  try {
    meta = JSON.parse(Buffer.from(String(req.query.state || ''), 'base64url').toString('utf8'));
  } catch {}
  const targetAlias = (String(meta.alias || 'LSStarterConfigSandbox')).trim();
  const repoBranch = (String(meta.branch || DEFAULT_BRANCH)).trim();

  // Exchange code for tokens using PKCE
  let tokenJson;
  try {
    // IMPORTANT: For Sandbox orgs, we may need to use test.salesforce.com for token exchange
    // even when using a Production Connected App. The authorization code from a Sandbox
    // login might need to be exchanged at the Sandbox token endpoint.
    // Use the same login base URL that was used for authorization
    let tokenLoginBase = req.session.loginBase || SF_LOGIN_BASE;
    
    const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
    if (VERBOSE) {
      console.log('=== Token Exchange Debug ===');
      console.log('Token URL:', `${tokenLoginBase}/services/oauth2/token`);
      console.log('Grant Type:', 'authorization_code');
      console.log('Client ID:', SF_CLIENT_ID ? `${SF_CLIENT_ID.substring(0, 8)}...${SF_CLIENT_ID.substring(SF_CLIENT_ID.length - 4)}` : 'not set');
      console.log('Redirect URI:', redirectUri);
      console.log('Code:', code ? code.substring(0, 20) + '...' : 'missing');
      console.log('Code Verifier Length:', codeVerifier ? codeVerifier.length : 0);
      console.log('Code Verifier (first 20):', codeVerifier ? codeVerifier.substring(0, 20) + '...' : 'missing');
      console.log('Stored Code Challenge:', storedCodeChallenge ? storedCodeChallenge.substring(0, 20) + '...' : 'missing');
      // Verify code_verifier matches code_challenge
      if (codeVerifier && storedCodeChallenge) {
        const verifyChallenge = crypto.createHash('sha256')
          .update(codeVerifier)
          .digest('base64url');
        console.log('Verified Challenge:', verifyChallenge.substring(0, 20) + '...');
        console.log('Challenge Match:', verifyChallenge === storedCodeChallenge);
      }
    }
    
    // Build token request body
    const tokenBody = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      client_id: SF_CLIENT_ID,
      code_verifier: codeVerifier,  // Use code_verifier instead of client_secret
      redirect_uri: redirectUri,
    });
    
    if (VERBOSE) {
      console.log('Token Request Body (sanitized):', tokenBody.toString()
        .replace(/code_verifier=[^&]+/, 'code_verifier=***')
        .replace(/code=[^&]+/, 'code=***'));
    }
    
    const tokenRes = await fetch(`${tokenLoginBase}/services/oauth2/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: tokenBody,
    });
    
    if (VERBOSE) {
      console.log('Token Response Status:', tokenRes.status);
    }
    
    if (!tokenRes.ok) {
      const errorText = await tokenRes.text();
      let errorMessage = `Token exchange failed: ${tokenRes.status}`;
      let errorCode = '';
      let errorDescription = '';
      
      // Log full error response for debugging (sanitized)
      if (VERBOSE) {
        const sanitizedErrorText = errorText
          .replace(/client_id[=:]\s*[^\s"']+/gi, 'client_id=***')
          .replace(/redirect_uri[=:]\s*[^\s"']+/gi, 'redirect_uri=***')
          .replace(/code_verifier[=:]\s*[^\s"']+/gi, 'code_verifier=***')
          .replace(/code[=:]\s*[^\s"']+/gi, 'code=***');
        console.error('[OAuth] Full error response (sanitized):', sanitizedErrorText.substring(0, 500));
        console.error('[OAuth] Error response headers:', JSON.stringify(Object.fromEntries(tokenRes.headers.entries())));
      }
      
      // Try to parse error response for more details
      try {
        const errorJson = JSON.parse(errorText);
        if (errorJson.error) {
          errorCode = errorJson.error;
          errorMessage = `Token exchange failed: ${errorJson.error}`;
          if (errorJson.error_description) {
            errorDescription = decodeURIComponent(String(errorJson.error_description));
            errorMessage += ` - ${errorDescription}`;
          }
          // Log additional error fields if present
          if (VERBOSE && errorJson.error_uri) {
            console.error('[OAuth] Error URI:', errorJson.error_uri);
          }
        }
      } catch {
        // If not JSON, use the text (but sanitize it)
        if (errorText && VERBOSE) {
          const sanitizedError = errorText
            .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
            .replace(/redirect_uri[=:]\s*[^\s]+/gi, 'redirect_uri=***')
            .substring(0, 500);
          console.error('[OAuth] Non-JSON error response:', sanitizedError);
          errorMessage += ` - ${sanitizedError}`;
        }
      }
      
      // If using login.salesforce.com and getting invalid_grant, try test.salesforce.com for Sandbox orgs
      // This is a known issue: Sandbox authorization codes may need to be exchanged at test.salesforce.com
      // even when using a Production Connected App
      if (errorCode === 'invalid_grant' && tokenLoginBase === 'https://login.salesforce.com') {
        if (VERBOSE) {
          console.log('[OAuth] Retrying token exchange with test.salesforce.com for Sandbox org...');
        }
        
        // Recreate token body for retry (URLSearchParams can only be read once)
        const retryTokenBody = new URLSearchParams({
          grant_type: 'authorization_code',
          code,
          client_id: SF_CLIENT_ID,
          code_verifier: codeVerifier,
          redirect_uri: redirectUri,
        });
        
        const sandboxTokenRes = await fetch('https://test.salesforce.com/services/oauth2/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: retryTokenBody,
        });
        
        if (sandboxTokenRes.ok) {
          if (VERBOSE) {
            console.log('[OAuth] Token exchange succeeded with test.salesforce.com!');
          }
          tokenJson = await sandboxTokenRes.json();
          // Update session loginBase for future reference
          req.session.loginBase = 'https://test.salesforce.com';
          // Skip the rest of the error handling since we succeeded
        } else {
          // Still failed, log the error and continue with original error
          const sandboxErrorText = await sandboxTokenRes.text();
          if (VERBOSE) {
            console.error('[OAuth] Token exchange also failed with test.salesforce.com:', sandboxTokenRes.status);
            try {
              const sandboxErrorJson = JSON.parse(sandboxErrorText);
              console.error('[OAuth] Sandbox error:', sandboxErrorJson.error, sandboxErrorJson.error_description);
            } catch {}
          }
        }
      }
      
      // If we successfully got tokenJson from retry, skip error handling
      if (tokenJson) {
        // Success! Continue with token processing
      } else {
        // If we still don't have tokenJson, throw the original error
        // Log error without exposing sensitive details
        console.error('[OAuth] Token Exchange Error:', tokenRes.status, errorCode);
        if (VERBOSE) {
          console.error('[OAuth] Error details:', errorMessage);
          console.error('[OAuth] Redirect URI used:', redirectUri);
          console.error('[OAuth] Code length:', code.length);
          console.error('[OAuth] Code Verifier length:', codeVerifier ? codeVerifier.length : 0);
        }
        
        // Provide helpful error messages for common issues
        if (errorCode === 'invalid_grant') {
          if (errorDescription && errorDescription.includes('expired')) {
            errorMessage += '. The authorization code may have expired. Please try logging in again.';
          } else if (errorDescription && errorDescription.includes('authentication failure')) {
            errorMessage += '. This usually means the code_verifier doesn\'t match the code_challenge, or for Sandbox orgs, the token exchange endpoint might need to be test.salesforce.com. Please try logging in again.';
          } else {
            errorMessage += '. Please ensure your Connected App is configured correctly and try logging in again.';
          }
        }
        
        throw new Error(errorMessage);
      }
    }
    
    // Only read tokenRes.json() if we don't already have tokenJson from retry
    if (!tokenJson) {
      tokenJson = await tokenRes.json();
    }
    if (VERBOSE) {
      console.log('Token Exchange Success!');
      // Mask instance URL for security (only show domain, not full path)
      const instanceUrl = tokenJson.instance_url || '';
      const maskedUrl = instanceUrl ? instanceUrl.replace(/^https?:\/\/([^\/]+).*$/, 'https://$1/***') : 'not set';
      console.log('Instance URL:', maskedUrl);
      console.log('=========================');
    }
  } catch (e) {
    // Log error without exposing stack traces or sensitive data
    const errorMsg = e.message || String(e);
    // Sanitize error message to remove potential sensitive data
    const sanitized = errorMsg
      .replace(/refreshToken[=:]\s*[^\s]+/gi, 'refreshToken=***')
      .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
      .replace(/access_token[=:]\s*[^\s]+/gi, 'access_token=***')
      .replace(/code_verifier[=:]\s*[^\s]+/gi, 'code_verifier=***')
      .replace(/instance[_-]?url[=:]\s*[^\s]+/gi, 'instance_url=***')
      .substring(0, 500); // Limit length
    console.error('Token Exchange Error:', sanitized);
    res.status(500).send(`OAuth token exchange failed: ${sanitized || 'Internal server error'}`);
    return;
  }
  
  // Clear session values after successful exchange
  delete req.session.codeVerifier;
  delete req.session.codeChallenge;
  delete req.session.redirectUri;
  delete req.session.loginBase;
  delete req.session.pkceState;

  const instanceUrl = tokenJson.instance_url;
  const refreshToken = tokenJson.refresh_token;
  if (!instanceUrl) {
    res.status(500).send('Missing instance_url from token response.');
    return;
  }
  if (!refreshToken) {
    res.status(500).send('Connected App must allow offline_access to return a refresh_token.');
    return;
  }

  // Authenticate to org first (required to query Organization object)
  let username = '';
  let orgInfo = { isSandbox: false, instanceName: null };
  try {
    // Build temporary auth URL
    let instanceHost;
    try {
      instanceHost = new URL(instanceUrl).host;
    } catch {
      instanceHost = String(instanceUrl).replace(/^https?:\/\//, '').replace(/\/+$/, '');
    }
    const authUrl = `force://${encodeURIComponent(SF_CLIENT_ID)}::${encodeURIComponent(refreshToken)}@${instanceHost}`;
    const work = tmpDir();
    const authFile = path.join(work, 'auth.sfdxurl');
    fs.writeFileSync(authFile, authUrl, { encoding: 'utf8' });
    await spawnPromise('npx', ['sf', 'org', 'login', 'sfdx-url',
      '--sfdx-url-file', authFile,
      '-a', targetAlias,
      '--set-default'
    ], { env: { ...process.env, SF_AUTOUPDATE_DISABLE: '1', NODE_NO_WARNINGS: '1' } });
    
    // Get username for logging
    username = await getUsername(targetAlias);
    
    // Query Organization object for IsSandbox and InstanceName
    orgInfo = await getOrgInfo(targetAlias);
  } catch (e) {
    // If authentication fails, deny access
    const errorMsg = e.message || String(e);
    const sanitized = errorMsg
      .replace(/refreshToken[=:]\s*[^\s]+/gi, 'refreshToken=***')
      .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
      .substring(0, 500);
    console.error('[OAuth] Authentication failed:', sanitized);
    res.status(500).send(`Failed to authenticate with Salesforce org. Please try again.`);
    return;
  }

  // Validate deployment based on org type and instance name
  const validationResult = isDeploymentAllowed(orgInfo.isSandbox, orgInfo.instanceName);
  if (!validationResult.allowed) {
    const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
    if (VERBOSE) {
      console.log(`[OAuth] Deployment validation failed: ${validationResult.reason}`);
      console.log(`[OAuth] IsSandbox: ${orgInfo.isSandbox}, InstanceName: ${orgInfo.instanceName || 'null'}`);
    }
    res.status(403).send(`Access denied: ${validationResult.reason}`);
    return;
  }

  // Enqueue deployment job
  const jobId = Buffer.from(`${Date.now()}-${Math.random()}`).toString('base64url');
  const job = await deploymentQueue.add(
    'deploy',
    {
      id: jobId,
      alias: targetAlias,
      branch: repoBranch,
      instanceUrl,
      refreshToken,
      username,
    },
    {
      jobId, // Use our custom ID
      removeOnComplete: { count: 100 },
      removeOnFail: { count: 50 },
    }
  );

  // Seed initial progress with welcome message
  await job.updateProgress({
    logs: [
      'Authentication successful. Starting deployment...',
      'This may take 2–3 minutes. Progress will appear below.',
      '',
    ],
  });

  // Redirect back to home with job id to start polling
  res.redirect('/?id=' + encodeURIComponent(jobId));
});

// Polling endpoint
app.get('/status', async (req, res) => {
  const id = String(req.query.id || '');
  if (!id) {
    res.json({ status: 'unknown', logs: [] });
    return;
  }

  try {
    const job = await deploymentQueue.getJob(id);
    if (!job) {
      res.json({ status: 'unknown', logs: [] });
      return;
    }

    const state = await job.getState();
    const progress = job.progress || {};
    const logs = progress.logs || [];

    // Map BullMQ states to our status format
    let status = 'pending';
    if (state === 'completed') {
      status = 'success';
    } else if (state === 'failed') {
      status = 'error';
      // Add error message to logs if not already present
      if (job.failedReason && !logs.some(l => l.includes('ERROR:'))) {
        logs.push(`ERROR: ${job.failedReason}`);
      }
    } else if (state === 'active' || state === 'waiting' || state === 'delayed') {
      status = 'running';
    }

    res.json({ status, logs });
  } catch (e) {
    // Log error without exposing full stack trace
    console.error('Error getting job status:', e.message || String(e));
    res.json({ status: 'unknown', logs: [] });
  }
});


const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server listening on port ${PORT}`);
});


