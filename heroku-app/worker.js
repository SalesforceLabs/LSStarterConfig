require('dotenv').config();
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { Worker } = require('bullmq');
const Redis = require('ioredis');
const { spawn } = require('child_process');
const fetch = require('node-fetch');
const unzipper = require('unzipper');

// Redis connection (uses REDIS_URL from Heroku if available)
// Heroku Redis uses TLS - configure ioredis to handle it properly
// IMPORTANT: Configure connection pooling to stay within Redis Mini plan limits (18 connections)
const redisConnection = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
  maxRetriesPerRequest: null, // REQUIRED by BullMQ for blocking operations (BLPOP, etc.)
  enableReadyCheck: false,
  enableOfflineQueue: false, // Don't queue commands when offline (reduces connections)
  retryStrategy: (times) => {
    // Exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms, max 2000ms
    const delay = Math.min(times * 100, 2000);
    // Stop retrying after 10 attempts (20 seconds total)
    if (times > 10) {
      return null; // Stop retrying
    }
    return delay;
  },
  reconnectOnError: (err) => {
    const targetError = 'READONLY';
    if (err.message.includes(targetError)) {
      return true; // Reconnect on READONLY errors
    }
    // Don't reconnect on connection errors - let retryStrategy handle it
    return false;
  },
  lazyConnect: false, // Connect immediately
  // Connection pool: reuse connections, don't create new ones unnecessarily
  keepAlive: 30000, // Keep connections alive for 30 seconds
  connectTimeout: 10000, // 10 second connection timeout
  tls: process.env.REDIS_URL && process.env.REDIS_URL.startsWith('rediss://') ? {
    rejectUnauthorized: false, // Heroku Redis uses self-signed certs
  } : undefined,
});

// Handle Redis connection errors gracefully (only log once per error type)
let lastErrorTime = 0;
let lastErrorMessage = '';

redisConnection.on('error', (err) => {
  const now = Date.now();
  const errorMsg = err.message || String(err);
  
  // Throttle error logging - only log once per 5 seconds for same error
  if (errorMsg !== lastErrorMessage || (now - lastErrorTime) > 5000) {
    console.error('[Worker] Redis connection error:', errorMsg);
    lastErrorTime = now;
    lastErrorMessage = errorMsg;
  }
  // Don't crash - let ioredis handle reconnection
});

redisConnection.on('connect', () => {
  // Only log connection events if verbose (reduces log noise)
  const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
  if (VERBOSE) {
    console.log('[Worker] Redis connected');
  }
  // Reset error tracking on successful connection
  lastErrorTime = 0;
  lastErrorMessage = '';
});

redisConnection.on('ready', () => {
  // Only log ready events if verbose (reduces log noise)
  const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
  if (VERBOSE) {
    console.log('[Worker] Redis ready');
  }
});

redisConnection.on('close', () => {
  // Don't log close events - they're normal during reconnection
});

const REPO = 'SalesforceLabs/LSStarterConfig';
const SF_CLIENT_ID = process.env.SF_CLIENT_ID || '';

// Instance whitelist configuration (only instance names from Organization object)
let allowedInstanceNames = [];

// Load instance configuration from environment variable
function loadInstanceConfig() {
  // Load instance names from comma-separated environment variable
  if (process.env.ALLOWED_INSTANCE_NAMES) {
    allowedInstanceNames = process.env.ALLOWED_INSTANCE_NAMES.split(',').map(s => s.trim().toUpperCase()).filter(Boolean);
    console.log(`[Worker Config] Loaded instance names from ALLOWED_INSTANCE_NAMES env var: ${allowedInstanceNames.join(', ') || 'none'}`);
    return;
  }

  // Default: no instance names configured (only sandboxes allowed)
  console.log('[Worker Config] No instance names configured. Only Sandbox orgs will be allowed.');
}

// Load configuration on startup
loadInstanceConfig();

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

async function downloadZip(branch, destDir) {
  const url = `https://github.com/${REPO}/archive/refs/heads/${branch}.zip`;
  const zipPath = path.join(destDir, 'repo.zip');
  
  // Use curl for reliable SSL handling on Heroku (node-fetch has SSL issues)
  await new Promise((resolve, reject) => {
    const curl = spawn('curl', [
      '-L',           // Follow redirects
      '--fail',       // Fail on HTTP errors
      '--silent',     // Silent mode
      '--show-error', // Show errors
      '--location',   // Follow redirects
      '--max-time', '300', // 5 minute timeout
      '-o', zipPath,  // Output file
      url
    ], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    
    let stderr = '';
    curl.stderr?.on('data', (d) => { stderr += String(d); });
    curl.on('error', (err) => {
      reject(new Error(`curl failed: ${err.message}`));
    });
    curl.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`curl failed with code ${code}: ${stderr || 'Unknown error'}`));
      }
    });
  });
  
  await fs.createReadStream(zipPath)
    .pipe(unzipper.Extract({ path: destDir }))
    .promise();
  const entries = fs.readdirSync(destDir).filter((d) => d.startsWith('LSStarterConfig-') && fs.statSync(path.join(destDir, d)).isDirectory());
  if (entries.length === 0) throw new Error('Extracted folder not found after unzip.');
  const extractedRoot = path.join(destDir, entries[0]);
  return extractedRoot;
}

// Worker to process deployment jobs
const worker = new Worker(
  'deployment-queue',
  async (job) => {
    const { id, alias, branch, instanceUrl, refreshToken, username } = job.data;
    const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
    
    // Helper to sanitize log lines for sensitive data
    const sanitizeLogLine = (line) => {
      return String(line)
        .replace(/refreshToken[=:]\s*[^\s]+/gi, 'refreshToken=***')
        .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
        .replace(/access_token[=:]\s*[^\s]+/gi, 'access_token=***')
        .replace(/instance[_-]?url[=:]\s*[^\s]+/gi, 'instance_url=***');
    };
    
    const write = (line = '') => {
      const ts = new Date().toISOString();
      const parts = [`[${ts}]`];
      if (username) parts.push(`[${username}]`);
      // Sanitize line before logging to prevent sensitive data exposure
      const sanitizedLine = sanitizeLogLine(line);
      const logLine = parts.join(' ') + ' ' + sanitizedLine;
      job.updateProgress({ logs: [...(job.progress?.logs || []), logLine] });
    };
    
    const vwrite = (line = '') => { if (VERBOSE) write(line); };
    
    try {
      write('Starting deployment process...');
      
      // Build SFDX auth URL for PKCE
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
      
      vwrite('OAuth code exchanged for tokens.');
      await spawnPromise('npx', ['sf', 'org', 'login', 'sfdx-url',
        '--sfdx-url-file', authFile,
        '-a', alias,
        '--set-default'
      ], { env: { ...process.env, SF_AUTOUPDATE_DISABLE: '1', NODE_NO_WARNINGS: '1' } });
      
      vwrite('CLI login via sfdx-url completed.');
      if (username) {
        write(`Logged in as ${username}`);
      }

      // Query Organization object for IsSandbox and InstanceName
      vwrite('Querying Organization for IsSandbox and InstanceName...');
      const orgOut = await runSf(['data', 'query', '-q', 'SELECT IsSandbox, InstanceName FROM Organization LIMIT 1', '--json', '-o', alias]);
      const orgJson = JSON.parse(orgOut.stdout);
      const org = orgJson?.result?.records?.[0];
      const isSandbox = org?.IsSandbox === true || String(org?.IsSandbox).toLowerCase() === 'true';
      const instanceName = org?.InstanceName ? String(org.InstanceName).toUpperCase() : null;
      vwrite(`IsSandbox: ${String(org?.IsSandbox)}, InstanceName: ${instanceName || 'null'}`);
      
      // Validate deployment based on org type and instance name
      const validationResult = isDeploymentAllowed(isSandbox, instanceName);
      if (!validationResult.allowed) {
        write('');
        write(`❌ ERROR: ${validationResult.reason}`);
        write('');
        throw new Error(`Deployment rejected: ${validationResult.reason}`);
      }
      
      vwrite(`Deployment allowed: ${validationResult.reason}`);

      // COUNT check
      vwrite('Querying LifeSciMetadataCategory COUNT()...');
      const countOut = await runSf(['data', 'query', '-q', 'SELECT COUNT() FROM LifeSciMetadataCategory', '--json', '-o', alias]);
      const countJson = JSON.parse(countOut.stdout);
      const count = Number(countJson?.result?.totalSize ?? 0);
      vwrite(`COUNT() returned ${count}.`);
      if (count > 0) {
        write('Configuration already exists. Please clear LifeSciMetadataCategory records before deploying.');
        throw new Error('Configuration already exists. Please clear LifeSciMetadataCategory records before deploying.');
      }

      // Download repo and run data load
      vwrite(`Downloading repository branch ${branch}...`);
      const repoWork = tmpDir();
      const repoRoot = await downloadZip(branch, repoWork);
      vwrite('Repository downloaded and extracted.');

      const scriptPath = path.join(repoRoot, 'Scripts', 'sh', 'data_load.sh');
      if (!fs.existsSync(scriptPath)) throw new Error('Data load script not found in repo.');
      fs.chmodSync(scriptPath, 0o755);
      vwrite('Starting data load script...');
      
      const dl = spawn('bash', [scriptPath], { 
        cwd: repoRoot, 
        env: { ...process.env, SF_AUTOUPDATE_DISABLE: '1', NODE_NO_WARNINGS: '1' }, 
        stdio: ['ignore', 'pipe', 'pipe'] 
      });
      
      dl.stdout?.on('data', (d) => write(String(d).trimEnd()));
      dl.stderr?.on('data', (d) => write(String(d).trimEnd()));
      
      await new Promise((resolve, reject) => {
        dl.on('error', reject);
        dl.on('close', (code) => code === 0 ? resolve() : reject(new Error('Data load script failed')));
      });
      
      write('');
      write('SUCCESS: Configurations have been deployed successfully.');
      vwrite('Deployment completed.');
      
      return { status: 'success', logs: job.progress?.logs || [] };
    } catch (e) {
      // Sanitize error message to avoid exposing sensitive data
      const errorMsg = e.message || String(e);
      const sanitized = errorMsg
        .replace(/refreshToken[=:]\s*[^\s]+/gi, 'refreshToken=***')
        .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
        .replace(/access_token[=:]\s*[^\s]+/gi, 'access_token=***')
        .replace(/instance[_-]?url[=:]\s*[^\s]+/gi, 'instance_url=***')
        .substring(0, 500); // Limit length
      write(`ERROR: ${sanitized}`);
      throw e;
    }
  },
  {
    connection: redisConnection,
    concurrency: 5, // Process up to 5 jobs concurrently per worker
    removeOnComplete: { count: 100 }, // Keep last 100 completed jobs
    removeOnFail: { count: 50 }, // Keep last 50 failed jobs
  }
);

worker.on('completed', (job) => {
  // Only log completion if verbose (reduces log noise)
  const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
  if (VERBOSE) {
    console.log(`[Worker] Job ${job.id} completed successfully`);
  }
});

worker.on('failed', (job, err) => {
  // Log job failures (important for monitoring)
  // Sanitize error message to avoid exposing sensitive data
  const errorMsg = err.message || String(err);
  // Remove potential sensitive data patterns
  const sanitized = errorMsg
    .replace(/refreshToken[=:]\s*[^\s]+/gi, 'refreshToken=***')
    .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
    .replace(/access_token[=:]\s*[^\s]+/gi, 'access_token=***')
    .replace(/instance[_-]?url[=:]\s*[^\s]+/gi, 'instance_url=***')
    .substring(0, 500); // Limit length
  console.error(`[Worker] Job ${job.id} failed:`, sanitized);
});

worker.on('error', (err) => {
  // Filter out Redis connection errors - they're already handled by Redis error handler
  if (err.code === 'ECONNRESET' || 
      err.message?.includes('TLS connection') || 
      err.message?.includes('socket disconnected') ||
      err.message?.includes('Client network socket')) {
    // Silently ignore - Redis error handler already logged it
    return;
  }
  // Only log non-Redis errors, sanitize to avoid exposing sensitive data
  const errorMsg = err.message || String(err);
  const sanitized = errorMsg
    .replace(/refreshToken[=:]\s*[^\s]+/gi, 'refreshToken=***')
    .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
    .replace(/access_token[=:]\s*[^\s]+/gi, 'access_token=***')
    .substring(0, 500); // Limit length
  console.error('[Worker] Error:', sanitized);
});

// Handle uncaught exceptions and unhandled rejections (worker crashes)
// These will be logged before the process exits, allowing Papertrail to capture them
process.on('uncaughtException', (err) => {
  const errorMsg = err.message || String(err);
  const sanitized = errorMsg
    .replace(/refreshToken[=:]\s*[^\s]+/gi, 'refreshToken=***')
    .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
    .replace(/access_token[=:]\s*[^\s]+/gi, 'access_token=***')
    .substring(0, 500);
  console.error('[Worker] FATAL: Uncaught exception (worker will crash):', sanitized);
  // Give time for log to flush before exit
  setTimeout(() => {
    process.exit(1);
  }, 1000);
});

process.on('unhandledRejection', (reason, promise) => {
  const errorMsg = reason?.message || String(reason);
  const sanitized = errorMsg
    .replace(/refreshToken[=:]\s*[^\s]+/gi, 'refreshToken=***')
    .replace(/client_id[=:]\s*[^\s]+/gi, 'client_id=***')
    .replace(/access_token[=:]\s*[^\s]+/gi, 'access_token=***')
    .substring(0, 500);
  console.error('[Worker] FATAL: Unhandled rejection (worker may crash):', sanitized);
});

// Log graceful shutdowns vs crashes
let isShuttingDown = false;
process.on('SIGTERM', () => {
  isShuttingDown = true;
  console.log('[Worker] Received SIGTERM, shutting down gracefully...');
  worker.close().then(() => {
    console.log('[Worker] Worker closed, exiting...');
    process.exit(0);
  }).catch((err) => {
    console.error('[Worker] Error closing worker:', err.message);
    process.exit(1);
  });
});

process.on('SIGINT', () => {
  isShuttingDown = true;
  console.log('[Worker] Received SIGINT, shutting down gracefully...');
  worker.close().then(() => {
    console.log('[Worker] Worker closed, exiting...');
    process.exit(0);
  }).catch((err) => {
    console.error('[Worker] Error closing worker:', err.message);
    process.exit(1);
  });
});

// Log when process exits unexpectedly (crash)
process.on('exit', (code) => {
  if (!isShuttingDown && code !== 0) {
    console.error(`[Worker] Process exiting with code ${code} (unexpected crash)`);
  }
});

// Only log startup if verbose (reduces log noise)
const VERBOSE = (process.env.LOG_VERBOSE === '1' || process.env.VERBOSE === '1');
if (VERBOSE) {
  console.log('[Worker] Deployment worker started. Waiting for jobs...');
}
