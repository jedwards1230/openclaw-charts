#!/usr/bin/env node
/**
 * GitHub App Installation Token Generator
 * 
 * Generates just-in-time installation access tokens for GitHub Apps.
 * Based on OpenClaw's existing Copilot token pattern.
 * 
 * Usage:
 *   node github-app-token.mjs --app-id 123456 --installation-id 98765 --private-key-path ./key.pem
 *   
 *   Or with environment variables:
 *   GITHUB_APP_ID=123456 GITHUB_APP_INSTALLATION_ID=98765 GITHUB_APP_PRIVATE_KEY_PATH=./key.pem node github-app-token.mjs
 *   
 *   With base64-encoded key:
 *   node github-app-token.mjs --app-id 123456 --installation-id 98765 --base64-key "$(base64 -w0 < key.pem)"
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';

// ============================================================================
// Configuration
// ============================================================================

const CACHE_DIR = process.env.OPENCLAW_CACHE_DIR
  || path.join(os.homedir(), '.openclaw', 'state', 'credentials');
const CACHE_FILE = path.join(CACHE_DIR, 'github-app.token.json');
const GITHUB_API_URL = process.env.GITHUB_API_URL || 'https://api.github.com';

// Token is valid for 1 hour, we refresh 5 minutes before expiry
const TOKEN_EXPIRY_BUFFER_MS = 5 * 60 * 1000;

// ============================================================================
// JWT Generation (from universal-github-app-jwt pattern)
// ============================================================================

/**
 * Generate a GitHub App JWT (valid for ~10 minutes)
 * This JWT is used to authenticate as the App itself.
 */
function generateJWT(appId, privateKeyPem) {
  // Convert PKCS#1 (GitHub's format) to PKCS#8 (WebCrypto/Node format)
  const privateKey = crypto.createPrivateKey(privateKeyPem);
  const privateKeyPkcs8 = privateKey.export({
    type: 'pkcs8',
    format: 'pem',
  });

  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iat: now - 60, // Issued 60s in the past to account for clock skew
    exp: now + 600, // Expires in 10 minutes
    iss: appId.toString(),
  };

  const header = { alg: 'RS256', typ: 'JWT' };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signatureInput = `${encodedHeader}.${encodedPayload}`;

  const signature = crypto.sign('RSA-SHA256', Buffer.from(signatureInput), {
    key: privateKeyPkcs8,
    padding: crypto.constants.RSA_PKCS1_PADDING,
  });

  return `${signatureInput}.${base64UrlEncode(signature)}`;
}

function base64UrlEncode(data) {
  const buffer = typeof data === 'string' ? Buffer.from(data, 'utf8') : data;
  return buffer
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

// ============================================================================
// Installation Token Generation
// ============================================================================

/**
 * Generate an installation access token using the GitHub App JWT
 * This token can be used to make API calls on behalf of the installation.
 */
async function generateInstallationToken(appId, installationId, privateKeyPem) {
  const jwt = generateJWT(appId, privateKeyPem);

  const url = `${GITHUB_API_URL}/app/installations/${installationId}/access_tokens`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${jwt}`,
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Failed to generate installation token: HTTP ${response.status}\n${text}`);
  }

  const data = await response.json();
  
  // Parse expires_at (ISO 8601 string) to timestamp
  const expiresAt = new Date(data.expires_at).getTime();

  return {
    token: data.token,
    expiresAt,
    permissions: data.permissions,
    repositories: data.repositories,
  };
}

// ============================================================================
// Token Caching (inspired by github-copilot-token.ts)
// ============================================================================

function loadCachedToken(appId, installationId, apiUrl) {
  try {
    if (!fs.existsSync(CACHE_FILE)) {
      return null;
    }
    const content = fs.readFileSync(CACHE_FILE, 'utf8');
    const cached = JSON.parse(content);
    
    // Validate required fields
    if (typeof cached.token !== 'string' || 
        typeof cached.expiresAt !== 'number' ||
        !cached.token) {
      return null; // Invalid cache format
    }
    
    // Validate cache matches current configuration
    if (cached.appId !== appId || 
        cached.installationId !== installationId ||
        cached.apiUrl !== apiUrl) {
      return null; // Cache is for different app/installation/API
    }
    
    // Check if token is still valid (with buffer)
    const now = Date.now();
    if (cached.expiresAt - now > TOKEN_EXPIRY_BUFFER_MS) {
      return cached;
    }
    
    return null; // Token expired or about to expire
  } catch (error) {
    return null;
  }
}

function saveCachedToken(tokenData) {
  try {
    // Ensure directory exists with restrictive permissions (0700)
    fs.mkdirSync(CACHE_DIR, { recursive: true, mode: 0o700 });

    const tmpFile = CACHE_FILE + '.tmp';

    // Write to a temporary file with restrictive permissions (0600),
    // then atomically rename into place.
    fs.writeFileSync(tmpFile, JSON.stringify(tokenData, null, 2), {
      encoding: 'utf8',
      mode: 0o600,
    });

    fs.renameSync(tmpFile, CACHE_FILE);

    // Ensure final file permissions are restrictive even if it already existed.
    try {
      fs.chmodSync(CACHE_FILE, 0o600);
    } catch {
      // Ignore chmod errors (e.g., on non-POSIX systems); caching is best-effort.
    }
  } catch (error) {
    console.error('Warning: Failed to cache token:', error.message);
  }
}

// ============================================================================
// Main Function
// ============================================================================

async function main() {
  // Parse arguments
  const args = process.argv.slice(2);
  const getArg = (name, envVar) => {
    const index = args.indexOf(`--${name}`);
    if (index !== -1 && args[index + 1]) {
      return args[index + 1];
    }
    return process.env[envVar];
  };

  const appId = getArg('app-id', 'GITHUB_APP_ID');
  const installationId = getArg('installation-id', 'GITHUB_APP_INSTALLATION_ID');
  const privateKeyPath = getArg('private-key-path', 'GITHUB_APP_PRIVATE_KEY_PATH');
  const base64Key = getArg('base64-key', 'GITHUB_APP_PRIVATE_KEY_BASE64');
  const forceRefresh = args.includes('--force-refresh');
  const jsonOutput = args.includes('--json');

  if (!appId || !installationId) {
    console.error('Error: Missing required arguments');
    console.error('');
    console.error('Usage:');
    console.error('  node github-app-token.mjs --app-id <id> --installation-id <id> --private-key-path <path>');
    console.error('  node github-app-token.mjs --app-id <id> --installation-id <id> --base64-key <base64>');
    console.error('');
    console.error('Environment variables:');
    console.error('  GITHUB_APP_ID');
    console.error('  GITHUB_APP_INSTALLATION_ID');
    console.error('  GITHUB_APP_PRIVATE_KEY_PATH');
    console.error('  GITHUB_APP_PRIVATE_KEY_BASE64');
    console.error('');
    console.error('Options:');
    console.error('  --force-refresh   Ignore cache and generate new token');
    console.error('  --json           Output JSON instead of plain token');
    process.exit(1);
  }

  // Check cache first (unless force refresh)
  if (!forceRefresh) {
    const cached = loadCachedToken(appId, installationId, GITHUB_API_URL);
    if (cached) {
      if (jsonOutput) {
        console.log(JSON.stringify(cached, null, 2));
      } else {
        console.log(cached.token);
      }
      return;
    }
  }

  // Read private key
  let privateKeyPem;
  if (base64Key) {
    privateKeyPem = Buffer.from(base64Key, 'base64').toString('utf8');
  } else if (privateKeyPath) {
    privateKeyPem = fs.readFileSync(privateKeyPath, 'utf8');
  } else {
    console.error('Error: Must provide either --private-key-path or --base64-key');
    process.exit(1);
  }

  // Generate token
  const tokenData = await generateInstallationToken(appId, installationId, privateKeyPem);
  
  // Add validation fields for cache
  const cacheData = {
    ...tokenData,
    appId,
    installationId,
    apiUrl: GITHUB_API_URL,
  };
  
  // Cache it
  saveCachedToken(cacheData);

  // Output (without the validation fields for backwards compatibility)
  if (jsonOutput) {
    console.log(JSON.stringify(tokenData, null, 2));
  } else {
    console.log(tokenData.token);
  }
}

main().catch(error => {
  console.error('Error:', error.message);
  process.exit(1);
});
