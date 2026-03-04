# Configuration

## GitHub App Authentication

The image includes `git-credential-github-app`, a git credential helper that generates short-lived GitHub App installation tokens just-in-time. This replaces personal access tokens with scoped, auto-expiring bot identity.

```
git push  →  credential helper  →  generates installation token  →  x-access-token
gh pr create  →  /usr/bin/gh wrapper  →  same credential helper  →  GH_TOKEN
```

The credential helper chain falls back gracefully — if GitHub App env vars aren't set, git uses `gh auth git-credential` and gh uses `GITHUB_TOKEN` as before.

### Required env vars

Set via `extraEnv` + K8s secrets:

| Variable | Description |
|----------|-------------|
| `GITHUB_APP_ID` | GitHub App ID |
| `GITHUB_APP_INSTALLATION_ID` | Installation ID for the target org/user |
| `GITHUB_APP_PRIVATE_KEY` | PEM private key content |

Tokens are cached for ~55 minutes (5-minute buffer on the 1-hour lifetime), stored at `~/.cache/github-app-credential/token.json` with `0600` permissions.

## Tailscale Sidecar

The chart supports an optional Tailscale sidecar that exposes the OpenClaw gateway directly on your tailnet via `tailscale serve`. This enables direct access from any device on the tailnet without going through ingress.

Instead of using OpenClaw's native `--tailscale` flag (which would conflict with the LAN binding needed for ingress), the chart runs a separate Tailscale sidecar container that:

1. Joins the tailnet using an auth key from a Kubernetes secret
2. Uses `tailscale serve` to reverse-proxy HTTPS traffic to the OpenClaw gateway on `127.0.0.1` using the configurable `gateway.port` value (default `18789`)
3. Shares the Tailscale socket with the main container via an emptyDir volume, enabling `tailscale whois` for identity-based authentication

### Configuration

```yaml
tailscale:
  enabled: true
  authKeySecret: "my-tailscale-secret"   # K8s secret with the auth key
  authKeySecretKey: "TS_AUTHKEY"          # Key within the secret (default)
  hostname: "openclaw"                    # Tailnet hostname

gateway:
  auth:
    allowTailscale: true                  # Enable tailscale identity auth
```

### Required values

| Value | Description | Required |
|-------|-------------|----------|
| `tailscale.enabled` | Enable the Tailscale sidecar | Yes |
| `tailscale.authKeySecret` | Name of K8s secret containing the Tailscale auth key | Yes |
| `tailscale.hostname` | Hostname on the tailnet | Recommended |
| `gateway.auth.allowTailscale` | Allow Tailscale identity-header authentication | Recommended |

### ACL requirements

The auth key should be created with a tag that has appropriate ACL permissions. The Tailscale node will appear on your tailnet as `<hostname>.tailnet-name.ts.net`.

## Webhookd Sidecar

The chart includes an optional webhook verification sidecar (`webhookd.enabled: true`) that validates GitHub webhook signatures before forwarding to OpenClaw.

**What it does:**
- Receives GitHub webhook POSTs on a separate port (default `8090`)
- Verifies `X-Hub-Signature-256` HMAC using `timingSafeEqual`
- Forwards verified requests to OpenClaw's `/hooks/agent` endpoint with the `x-openclaw-token` header
- Rejects unsigned or tampered payloads with `401 Unauthorized`
- Enforces a 1 MB payload size limit

**Required secrets** (in addition to `WEBHOOK_TOKEN`):
- `GITHUB_WEBHOOK_SECRET` — the secret configured in your GitHub webhook settings

Route `/hooks` traffic to the webhookd sidecar using `additionalIngresses` with `servicePort: webhookd`:

```yaml
additionalIngresses:
  - name: webhook
    enabled: true
    host: openclaw.example.com
    path: /hooks
    pathType: Prefix
    servicePort: webhookd  # routes to the webhookd sidecar, not the main gateway
```

This keeps the main UI on a separate, LAN-restricted ingress.

## Plugin Repos

Clone Git repositories as plugins at pod startup:

```yaml
pluginRepos:
  - name: my-plugins
    url: https://github.com/org/openclaw-plugins.git
    ref: main
  - name: private-plugins
    url: https://github.com/org/private-plugins.git
    ref: main
    subdir: my-plugin
    auth:
      secretName: openclaw-secrets
      secretKey: GITHUB_TOKEN
```

Each entry clones into `/plugins/<name>` and automatically appends the path to `config.plugins.load.paths`. The cloned volume is mounted read-only in the main container. Repos are re-cloned on every pod restart (emptyDir volume).

## NetworkPolicy

When `networkPolicy.enabled: true`, a Kubernetes NetworkPolicy restricts traffic:

**Ingress:** Allows traffic from the configured ingress controller (default: Traefik in `kube-system`) and pods in the same namespace.

**Egress:** DNS, HTTP/80, HTTPS/443, plus optional toggles:

| Toggle | Port | Description |
|--------|------|-------------|
| `allowMcpProxy` | TCP/8080 | MCP proxy pods in same namespace |
| `allowOllama` | TCP/11434 | Ollama LLM service (CIDR configurable) |
| `allowOtel` | TCP/4317-4318 | OTEL collector (namespace configurable) |
| `allowKubeAPI` | TCP/6443 | Kubernetes API server |
| `discord.voice.enabled` | UDP/* | Discord voice servers |

### Custom ingress controller

Override the default Traefik assumption:

```yaml
networkPolicy:
  enabled: true
  ingressController:
    namespace: ingress-nginx
    podSelector:
      app.kubernetes.io/name: ingress-nginx
  otelNamespace: observability  # default: monitoring
```
