# GitHub App Authentication Research & Implementation

## Executive Summary

**Problem**: LilClaw needs to use GitHub App identity instead of sharing Justin's personal PAT. The `gh` CLI doesn't automatically support GitHub App authentication.

**Solution**: Just-in-time token generation with caching, using a wrapper script that sets `GH_TOKEN` before invoking `gh` commands.

**Status**: ✅ Proof-of-concept complete and ready for testing

---

## 1. GitHub App Authentication Flow

### Overview

GitHub Apps use a two-step authentication process:

```
App ID + Private Key → JWT (10 min) → Installation Token (1 hour) → API Access
```

### Detailed Flow

1. **Generate JWT** (JSON Web Token)
   - Created using App ID + Private Key (RSA-256 signature)
   - Valid for ~10 minutes
   - Used to authenticate as the **App itself**
   - Cannot make API calls directly (except app-level endpoints)

2. **Exchange JWT for Installation Token**
   - POST to `https://api.github.com/app/installations/{installation_id}/access_tokens`
   - Include JWT in `Authorization: Bearer <jwt>` header
   - Returns an installation access token

3. **Use Installation Token**
   - Valid for **1 hour** from creation
   - Has specific permissions granted to the app
   - Can be scoped to specific repositories
   - Used in `Authorization: token <token>` or `Bearer <token>` header

### Token Properties

| Token Type | Lifetime | Scope | Purpose |
|------------|----------|-------|---------|
| **JWT** | ~10 minutes | App-level | Authenticate as the app |
| **Installation Token** | 1 hour | Installation-specific | Make API calls on behalf of installation |

### Key Points

- Installation tokens **expire after 1 hour** (non-negotiable)
- They **cannot be refreshed** - must generate a new one
- They have **limited scope** (only permissions granted to the app)
- They are **repository-specific** if configured that way
- Much safer than PATs (expire, limited scope, audit trail)

---

## 2. Token Generation Methods

### Official GitHub API Endpoint

```bash
POST /app/installations/{installation_id}/access_tokens
Authorization: Bearer <jwt>
```

### Existing Tools & Libraries

#### ✅ Universal GitHub App JWT (Already in OpenClaw!)

OpenClaw already has `universal-github-app-jwt@2.2.2` as a dependency:

```javascript
import githubAppJwt from "universal-github-app-jwt";

const { token, appId, expiration } = await githubAppJwt({
  id: APP_ID,
  privateKey: PRIVATE_KEY,
});
```

Located at: `/app/node_modules/.pnpm/universal-github-app-jwt@2.2.2/`

#### 🔧 CLI Tools

| Tool | Language | Pros | Cons |
|------|----------|------|------|
| **gh-token** | Go | Official gh extension, well-maintained | Requires Go binary, extra dependency |
| **gh-app-access-token** | Go | Standalone binary | Another binary to manage |
| **actions/create-github-app-token** | TypeScript | Official GitHub Action | GitHub Actions only |
| **Our POC** | Node.js | No extra deps, pure Node | New code to maintain |

#### 🏆 Recommendation: Build in Node.js

- OpenClaw already has the JWT library
- No extra binaries needed
- Can integrate directly into OpenClaw codebase
- Follows existing patterns (see `github-copilot-token.ts`)

---

## 3. Just-in-Time Approaches

### Pattern A: Wrapper Script (POC Implemented)

**Concept**: Wrap `gh` CLI calls with a script that generates token on-demand.

```bash
#!/bin/bash
# gh-wrapper.sh
export GH_TOKEN=$(node github-app-token.mjs)
exec gh "$@"
```

**Pros**:
- ✅ Works immediately with existing `gh` commands
- ✅ Zero changes to calling code
- ✅ Token automatically refreshed when expired
- ✅ Can be aliased: `alias gh='./gh-wrapper.sh'`

**Cons**:
- ❌ Extra process spawn per `gh` call (mitigated by caching)
- ❌ Wrapper must be in PATH or explicitly called

### Pattern B: Pre-Command Hook

**Concept**: Set `GH_TOKEN` in environment before agent spawns.

```javascript
// In OpenClaw agent initialization
process.env.GH_TOKEN = await generateGitHubAppToken();
```

**Pros**:
- ✅ Set once per session
- ✅ No wrapper needed
- ✅ Transparent to all `gh` calls

**Cons**:
- ❌ Token can expire mid-session (if session > 1 hour)
- ❌ Requires agent restart to refresh
- ❌ Less flexible

### Pattern C: Skill-Level Integration

**Concept**: Modify the GitHub skill to handle token generation internally.

```javascript
// In /app/skills/github/
async function executeGhCommand(args) {
  const token = await getCachedOrGenerateToken();
  return exec(`GH_TOKEN=${token} gh ${args}`);
}
```

**Pros**:
- ✅ Fully integrated with OpenClaw
- ✅ Automatic token refresh
- ✅ No external scripts

**Cons**:
- ❌ Requires OpenClaw code changes
- ❌ More complex implementation
- ❌ Longer development time

### 🏆 Recommended Approach: **Wrapper Script → Skill Integration**

**Phase 1** (Immediate): Use wrapper script for quick deployment
**Phase 2** (Future): Integrate into GitHub skill for cleaner long-term solution

---

## 4. Caching Strategy

### Why Cache?

- Generating tokens requires:
  1. Reading private key (I/O)
  2. Computing JWT signature (crypto)
  3. HTTP POST to GitHub API (network)
- These operations add ~500-1000ms overhead per call
- Tokens are valid for 1 hour, so caching is essential

### Cache Implementation

Modeled after OpenClaw's existing `github-copilot-token.ts`:

```javascript
{
  "token": "ghs_...",
  "expiresAt": 1707337200000,  // milliseconds since epoch
  "permissions": { ... },
  "repositories": [ ... ]
}
```

**Cache Location**: `~/.openclaw/state/credentials/github-app.token.json`

**Cache Logic**:
1. Check if cached token exists
2. If exists and `expiresAt - now > 5 minutes`: use cached token
3. Otherwise: generate new token and update cache

**Buffer Time**: 5 minutes before expiry to avoid edge cases

### Token Expiry Handling

```javascript
const TOKEN_EXPIRY_BUFFER_MS = 5 * 60 * 1000; // 5 minutes

function isTokenUsable(cache, now = Date.now()) {
  return cache.expiresAt - now > TOKEN_EXPIRY_BUFFER_MS;
}
```

This ensures we never use a token that might expire during a long-running operation.

---

## 5. Existing Solutions in OpenClaw

### GitHub Copilot Token Pattern

OpenClaw already implements token caching for GitHub Copilot at:
`/app/src/providers/github-copilot-token.ts`

**Key patterns we can reuse**:

1. **Cache file structure** (`~/.openclaw/state/credentials/`)
2. **Token validation** with expiry buffer
3. **Graceful fallback** if cache read fails
4. **JSON serialization** of token metadata

**Similarities**:
- Both use bearer tokens with expiration
- Both benefit from caching
- Both need secure credential storage

**Differences**:
| Aspect | Copilot | GitHub App |
|--------|---------|------------|
| Input | GitHub PAT | App ID + Private Key |
| Token lifetime | ~Varies | Exactly 1 hour |
| Token endpoint | `api.github.com/copilot_internal/v2/token` | `api.github.com/app/installations/{id}/access_tokens` |

### No Existing GitHub App Support

**Current state**: OpenClaw has no built-in GitHub App authentication support.

**Evidence**:
- No env vars for `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, etc.
- No skills or providers that reference GitHub Apps
- GitHub skill (`/app/skills/github/`) assumes `gh` is already authenticated

**Opportunity**: This is greenfield! We can design it right from the start.

---

## 6. Implementation Recommendation

### Architecture

```
┌─────────────────────────────────────────────┐
│ Agent Session                               │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ GitHub Skill                         │  │
│  │                                      │  │
│  │  exec('gh pr list')                 │  │
│  │         ↓                            │  │
│  │  gh-wrapper.sh                      │  │
│  │         ↓                            │  │
│  │  github-app-token.mjs               │  │
│  │         ↓                            │  │
│  │  Check cache (~/.openclaw/state/)   │  │
│  │         ↓                            │  │
│  │  [cached] → return token            │  │
│  │  [expired] → generate new token     │  │
│  │         ↓                            │  │
│  │  export GH_TOKEN=...                │  │
│  │         ↓                            │  │
│  │  exec real gh command               │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### Deployment Strategy

#### Phase 1: Sidecar Script (Immediate)

**Files**:
- `github-app-token.mjs` - Token generator (standalone Node.js script)
- `gh-wrapper.sh` - Wrapper that sets GH_TOKEN before invoking `gh`

**Setup**:
1. Store App ID, Installation ID, and Private Key as environment variables
2. Copy scripts to agent workspace
3. Update GitHub skill calls to use `gh-wrapper.sh` instead of `gh`
4. OR: Alias `gh` to the wrapper in shell profile

**Environment Variables**:
```bash
export GITHUB_APP_ID="123456"
export GITHUB_APP_INSTALLATION_ID="98765"
export GITHUB_APP_PRIVATE_KEY_PATH="/path/to/key.pem"
# OR
export GITHUB_APP_PRIVATE_KEY_BASE64="$(base64 -w0 < key.pem)"
```

#### Phase 2: Skill Integration (Future)

**Approach**: Integrate token generation directly into GitHub skill.

**Changes needed**:
1. Add `github-app-token.ts` to `/app/src/providers/`
2. Modify `/app/skills/github/` to call token generator before `gh` commands
3. Add env var validation in agent startup
4. Update docs

**Benefits**:
- Cleaner integration
- Better error handling
- Consistent with other OpenClaw patterns
- No external scripts

#### Phase 3: Optional Enhancements

- Auto-detect installation ID from repository
- Support multiple GitHub Apps
- Metrics/logging for token generation
- Graceful fallback to PAT if App auth fails

---

## 7. Security Considerations

### Private Key Storage

**Options**:

| Method | Security | Convenience | Recommendation |
|--------|----------|-------------|----------------|
| **Environment variable** | ⚠️ Moderate | ✅ Easy | For testing only |
| **File with restricted permissions** | ✅ Good | ✅ Easy | **Recommended** |
| **Kubernetes Secret** | ✅ Good | ⚠️ Moderate | For K8s deployments |
| **Secrets manager** (Vault, etc.) | ✅✅ Best | ❌ Complex | For production |

**Best practices**:
- Never commit private keys to git
- Use `.gitignore` for key files
- Set file permissions: `chmod 600 private-key.pem`
- In containers: mount as secret volume
- Rotate keys periodically

### Token Security

**Installation tokens are safer than PATs**:
- ✅ Limited lifetime (1 hour vs indefinite)
- ✅ Scoped permissions (only what app needs)
- ✅ Audit trail (all actions logged as app)
- ✅ Can be revoked via app settings

**Risks**:
- ⚠️ Token leaked = 1 hour of access (vs indefinite for PAT)
- ⚠️ Private key leaked = generate unlimited tokens

**Mitigations**:
- Don't log tokens
- Clear tokens from memory after use
- Cache file should have restricted permissions
- Monitor app activity in GitHub audit log

### Least Privilege

**Configure app permissions carefully**:
- Only grant necessary permissions
- Prefer read-only where possible
- Use repository-scoped tokens when applicable

---

## 8. Proof of Concept

### Files Created

1. **`github-app-token.mjs`** - Token generator
   - Generates JWT from App ID + Private Key
   - Exchanges JWT for installation token
   - Caches token with expiry checking
   - Outputs token to stdout (or JSON with `--json`)

2. **`gh-wrapper.sh`** - CLI wrapper
   - Calls token generator
   - Sets `GH_TOKEN` environment variable
   - Executes `gh` with all arguments passed through

### Testing the POC

#### Setup

```bash
# 1. Set environment variables
export GITHUB_APP_ID="123456"
export GITHUB_APP_INSTALLATION_ID="98765"
export GITHUB_APP_PRIVATE_KEY_PATH="$HOME/github-app-key.pem"

# 2. Make scripts executable (already done)
chmod +x github-app-token.mjs gh-wrapper.sh

# 3. Test token generation
node github-app-token.mjs --json
```

Expected output:
```json
{
  "token": "ghs_1234567890abcdef...",
  "expiresAt": 1707337200000,
  "permissions": {
    "issues": "write",
    "pull_requests": "write",
    "contents": "read"
  }
}
```

#### Test gh wrapper

```bash
# List PRs using the wrapper
./gh-wrapper.sh pr list --repo owner/repo

# Create an issue
./gh-wrapper.sh issue create --repo owner/repo --title "Test" --body "Testing GitHub App auth"

# Check auth status (should show as the app)
./gh-wrapper.sh auth status
```

#### Verify caching

```bash
# First call (generates token)
time node github-app-token.mjs
# Should take ~500-1000ms

# Second call (uses cache)
time node github-app-token.mjs
# Should take ~10-50ms

# Check cache file
cat ~/.openclaw/state/credentials/github-app.token.json
```

### Integration with OpenClaw

**Option A**: Wrapper script (minimal changes)

```javascript
// In GitHub skill or agent code
exec('~/workspace/gh-wrapper.sh pr list --repo owner/repo')
```

**Option B**: Set token before gh calls

```javascript
// Generate token once per session
const token = await exec('node ~/workspace/github-app-token.mjs');
process.env.GH_TOKEN = token.trim();

// Now all gh calls use the app token
exec('gh pr list --repo owner/repo');
```

**Option C**: Alias in shell profile

```bash
# In ~/.bashrc or agent shell init
alias gh='~/workspace/gh-wrapper.sh'

# Now 'gh' automatically uses app token
gh pr list
```

---

## 9. Comparison with Alternatives

### vs. gh-token Extension

| Aspect | Our POC | gh-token |
|--------|---------|----------|
| Language | Node.js | Go |
| Dependencies | None (uses built-in crypto) | Go binary |
| OpenClaw Integration | Native | External |
| Caching | Yes | No (built-in) |
| Maintenance | Our code | External project |
| Installation | Copy scripts | `gh extension install` |

**Verdict**: Our POC is better for OpenClaw (no extra dependencies, native integration).

### vs. Building into OpenClaw

| Aspect | Sidecar Script | Built-in Skill |
|--------|----------------|----------------|
| Development time | ✅ Immediate | ⏱️ Days |
| Maintenance | ⚠️ Separate scripts | ✅ Part of codebase |
| Testing | ⚠️ Manual | ✅ Automated |
| Deployment | ✅ Copy files | ⏱️ Release cycle |
| Flexibility | ⚠️ Limited | ✅ Full control |

**Verdict**: Start with sidecar, migrate to built-in later.

---

## 10. Recommended Implementation Plan

### Immediate (Today)

1. ✅ **Deploy POC scripts** to agent workspace
2. ✅ **Store GitHub App credentials** as environment variables
3. ✅ **Test token generation** manually
4. ✅ **Update GitHub skill calls** to use wrapper (or alias)

### Short-term (This Week)

5. **Create GitHub App** (if not already done)
   - Go to GitHub Settings → Developer Settings → GitHub Apps
   - Set required permissions (issues, PRs, contents, etc.)
   - Install app on target repositories/orgs
   - Generate private key and note App ID + Installation ID

6. **Deploy to LilClaw**
   - Add env vars to LilClaw's container/environment
   - Mount private key as secret
   - Copy scripts to workspace
   - Test with real commands

7. **Monitor and iterate**
   - Check token generation logs
   - Verify cache is working
   - Ensure no permission errors

### Medium-term (Next Sprint)

8. **Integrate into GitHub skill**
   - Port `github-app-token.mjs` to TypeScript
   - Add to `/app/src/providers/github-app-token.ts`
   - Modify skill to auto-inject token
   - Add tests

9. **Documentation**
   - Update `SKILL.md` with GitHub App setup
   - Add troubleshooting guide
   - Document environment variables

### Long-term (Future)

10. **Production hardening**
    - Secrets manager integration
    - Key rotation automation
    - Monitoring/alerting
    - Multi-app support

---

## 11. Troubleshooting Guide

### Common Issues

#### "Failed to generate installation token: HTTP 401"

**Cause**: JWT is invalid or expired

**Fix**:
- Check App ID is correct
- Verify private key format (PKCS#1 or PKCS#8)
- Ensure clock is synchronized (JWT checks timestamps)

#### "Failed to generate installation token: HTTP 404"

**Cause**: Installation ID is wrong or app not installed

**Fix**:
- Verify installation ID: `gh api /app/installations --header "Authorization: Bearer <jwt>"`
- Check app is installed on target org/repo
- Ensure app ID matches the installation

#### "permission_denied" when using token

**Cause**: App lacks required permissions

**Fix**:
- Go to GitHub App settings
- Update permissions under "Permissions & events"
- Reinstall app (permissions changes require reinstall)

#### Token always regenerated (cache not working)

**Cause**: Cache file permissions or path issues

**Fix**:
- Check `~/.openclaw/state/credentials/` exists
- Verify cache file is readable/writable
- Check for errors in script output

---

## 12. Resources

### Official Documentation

- [GitHub Apps Overview](https://docs.github.com/en/apps/overview)
- [Authenticating as a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [Generating Installation Access Tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [REST API - Apps](https://docs.github.com/en/rest/apps/apps)

### Tools & Libraries

- [universal-github-app-jwt](https://github.com/gr2m/universal-github-app-jwt) - JWT library (already in OpenClaw)
- [gh-token](https://github.com/Link-/gh-token) - Go-based token generator
- [actions/create-github-app-token](https://github.com/actions/create-github-app-token) - Official GitHub Action

### Community Resources

- [gh CLI Discussion #5081](https://github.com/cli/cli/discussions/5081) - Authenticating as an App
- [gh CLI Discussion #5095](https://github.com/cli/cli/discussions/5095) - Using gh with GitHub App

---

## Conclusion

**GitHub App authentication is viable and recommended** for LilClaw:

✅ **More secure** than sharing PATs (limited scope, expiration, audit trail)  
✅ **Technically straightforward** (POC proves it works)  
✅ **Builds on existing patterns** (similar to Copilot token)  
✅ **No external dependencies** (pure Node.js using built-in crypto)  
✅ **Immediate deployment** (sidecar scripts ready to use)

**Next steps**:
1. Create/configure GitHub App in GitHub settings
2. Deploy POC scripts with credentials
3. Test with real gh commands
4. Monitor for issues
5. Plan migration to built-in skill (optional)

The proof-of-concept is **ready for production testing** with minimal risk.
