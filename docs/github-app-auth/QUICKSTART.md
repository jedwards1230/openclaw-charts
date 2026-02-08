# GitHub App Authentication - Quick Start Guide

## 🚀 Get Started in 5 Minutes

### Prerequisites

You need:
1. GitHub App created (with App ID and Private Key)
2. App installed on target org/repo (with Installation ID)
3. `gh` CLI installed

### Step 1: Get Your Credentials

#### Find App ID
1. Go to GitHub → Settings → Developer Settings → GitHub Apps
2. Click your app name
3. App ID is shown at the top

#### Get Installation ID
```bash
# Option A: Check the app installation URL
# Go to: https://github.com/settings/installations
# Click on your app → Look at URL: /settings/installations/INSTALLATION_ID

# Option B: Use the API (requires a temporary JWT)
gh api /app/installations --header "Authorization: Bearer <jwt>" | jq '.[0].id'
```

#### Download Private Key
1. In your GitHub App settings
2. Scroll to "Private keys"
3. Click "Generate a private key"
4. Save the `.pem` file securely

### Step 2: Set Environment Variables

```bash
export GITHUB_APP_ID="123456"  # Your App ID
export GITHUB_APP_INSTALLATION_ID="98765"  # Your Installation ID
export GITHUB_APP_PRIVATE_KEY_PATH="$HOME/github-app-key.pem"  # Path to .pem file

# OR use base64-encoded key (useful for containers)
export GITHUB_APP_PRIVATE_KEY_BASE64="$(base64 -w0 < $HOME/github-app-key.pem)"
```

### Step 3: Test Token Generation

```bash
# Generate a token (cached for 1 hour)
node github-app-token.mjs

# Output: ghs_1234567890abcdef...

# Get full token info (JSON)
node github-app-token.mjs --json
```

Expected output:
```json
{
  "token": "ghs_...",
  "expiresAt": 1707337200000,
  "permissions": {
    "issues": "write",
    "pull_requests": "write"
  }
}
```

### Step 4: Use with gh CLI

#### Option A: Wrapper Script

```bash
# Use the wrapper script
./gh-wrapper.sh pr list --repo owner/repo
./gh-wrapper.sh issue list --repo owner/repo

# Or create an alias
alias gh='./gh-wrapper.sh'
gh pr list --repo owner/repo
```

#### Option B: Manual Token Export

```bash
# Export token to environment
export GH_TOKEN=$(node github-app-token.mjs)

# Now gh commands use the app token
gh pr list --repo owner/repo
gh auth status  # Should show authenticated as your app
```

### Step 5: Verify It Works

```bash
# Check who you're authenticated as
./gh-wrapper.sh auth status

# Should show:
# Logged in to github.com as YOUR-APP-NAME[bot]

# Test a real command
./gh-wrapper.sh pr list --repo owner/repo
```

---

## 🎯 Integration Patterns

### Pattern 1: Shell Alias (Easiest)

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export GITHUB_APP_ID="123456"
export GITHUB_APP_INSTALLATION_ID="98765"
export GITHUB_APP_PRIVATE_KEY_PATH="$HOME/github-app-key.pem"
alias gh='$HOME/.openclaw/workspace/gh-wrapper.sh'
```

Now `gh` automatically uses GitHub App authentication!

### Pattern 2: Pre-Set Token (Sessions)

For agent sessions:

```javascript
// At session start
const token = (await exec('node github-app-token.mjs')).stdout.trim();
process.env.GH_TOKEN = token;

// Now all gh calls use the app
await exec('gh pr list --repo owner/repo');
```

### Pattern 3: Per-Command Wrapper

For explicit control:

```javascript
// Wrap each gh command
async function ghWithAppAuth(command) {
  return exec(`./gh-wrapper.sh ${command}`);
}

await ghWithAppAuth('pr list --repo owner/repo');
```

---

## 🔧 Deployment to LilClaw

### Docker/Kubernetes

#### 1. Create Secret

```bash
# Create Kubernetes secret
kubectl create secret generic github-app \
  --from-literal=app-id=123456 \
  --from-literal=installation-id=98765 \
  --from-file=private-key=./github-app-key.pem
```

#### 2. Mount Secret in Pod

```yaml
# In your pod spec
env:
  - name: GITHUB_APP_ID
    valueFrom:
      secretKeyRef:
        name: github-app
        key: app-id
  - name: GITHUB_APP_INSTALLATION_ID
    valueFrom:
      secretKeyRef:
        name: github-app
        key: installation-id
  - name: GITHUB_APP_PRIVATE_KEY_PATH
    value: /secrets/github-app/private-key

volumeMounts:
  - name: github-app-key
    mountPath: /secrets/github-app
    readOnly: true

volumes:
  - name: github-app-key
    secret:
      secretName: github-app
      items:
        - key: private-key
          path: private-key
          mode: 0400  # Read-only by owner
```

#### 3. Copy Scripts to Container

```dockerfile
# In your Dockerfile
COPY github-app-token.mjs /app/scripts/
COPY gh-wrapper.sh /app/scripts/
RUN chmod +x /app/scripts/gh-wrapper.sh /app/scripts/github-app-token.mjs

# Set PATH or alias
ENV PATH="/app/scripts:$PATH"
RUN echo 'alias gh="/app/scripts/gh-wrapper.sh"' >> /etc/profile
```

### Direct Installation (VPS/Bare Metal)

```bash
# 1. Copy scripts
cp github-app-token.mjs ~/bin/
cp gh-wrapper.sh ~/bin/
chmod +x ~/bin/gh-wrapper.sh ~/bin/github-app-token.mjs

# 2. Set up credentials
cat > ~/.github-app-env << 'EOF'
export GITHUB_APP_ID="123456"
export GITHUB_APP_INSTALLATION_ID="98765"
export GITHUB_APP_PRIVATE_KEY_PATH="$HOME/.ssh/github-app-key.pem"
EOF
chmod 600 ~/.github-app-env

# 3. Add to shell profile
echo 'source ~/.github-app-env' >> ~/.bashrc
echo 'alias gh="$HOME/bin/gh-wrapper.sh"' >> ~/.bashrc

# 4. Copy private key securely
scp github-app-key.pem user@server:~/.ssh/
ssh user@server 'chmod 600 ~/.ssh/github-app-key.pem'
```

---

## 🐛 Troubleshooting

### Token Generation Fails

```bash
# Test JWT generation manually
node -e "
const crypto = require('crypto');
const fs = require('fs');
const pem = fs.readFileSync(process.env.GITHUB_APP_PRIVATE_KEY_PATH, 'utf8');
const key = crypto.createPrivateKey(pem);
console.log('Key loaded successfully:', key.type);
"
```

### Installation ID Unknown

```bash
# List all installations for this GitHub App (requires a JWT)
# 1) Generate a short-lived JWT for your GitHub App and export it, e.g.:
#    export GITHUB_APP_JWT="<your GitHub App JWT>"
#
# 2) Call the GitHub Apps API to list installations and show their IDs:
gh api /app/installations \
  -H "Authorization: Bearer $GITHUB_APP_JWT" \
  -H "Accept: application/vnd.github+json" | \
  jq '.[] | {id, account: .account.login, target_type}'

# If you prefer the web UI, you can also open:
# https://github.com/settings/installations
```

### Permission Denied

1. Check app permissions in GitHub settings
2. Reinstall app (permission changes require reinstallation)
3. Verify token permissions: `node github-app-token.mjs --json | jq .permissions`

### Cache Issues

```bash
# Clear cache and regenerate
rm -f ~/.openclaw/state/credentials/github-app.token.json
node github-app-token.mjs --force-refresh
```

---

## 📋 Checklist

Before going live, verify:

- [ ] GitHub App created with required permissions
- [ ] App installed on target repositories/organization
- [ ] App ID and Installation ID noted
- [ ] Private key downloaded and secured (`chmod 600`)
- [ ] Environment variables set correctly
- [ ] Scripts are executable
- [ ] Token generation works: `node github-app-token.mjs`
- [ ] gh CLI works with token: `./gh-wrapper.sh auth status`
- [ ] Test commands work: `./gh-wrapper.sh pr list --repo owner/repo`
- [ ] Cache directory exists: `~/.openclaw/state/credentials/`
- [ ] Token caching works (second call is fast)

---

## 🎓 Next Steps

Once basic setup works:

1. **Test in production** with real LilClaw workflows
2. **Monitor logs** for any authentication errors
3. **Measure performance** (cache hit rate, generation time)
4. **Plan skill integration** for cleaner long-term solution
5. **Document any quirks** or edge cases discovered

---

## 📚 Additional Resources

- **Full research**: See `GITHUB_APP_AUTH_RESEARCH.md`
- **GitHub App docs**: https://docs.github.com/en/apps
- **Permissions reference**: https://docs.github.com/en/apps/creating-github-apps/setting-permissions-for-github-apps/permissions-required-for-github-apps
- **API reference**: https://docs.github.com/en/rest/apps

---

**Questions?** Check the research doc or GitHub's official documentation.

**Ready to deploy?** Start with Step 1 above! 🚀
