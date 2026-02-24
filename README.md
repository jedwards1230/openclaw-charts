# OpenClaw Charts

Custom OpenClaw Docker image and Helm chart for deploying a Discord bot with GitHub CLI support.

> **Note**: This is a customized build based on the upstream [openclaw/openclaw](https://github.com/openclaw/openclaw) project. It includes additional tooling and configuration for personal homelab deployments.

## What's Different

This customized build includes:

- **GitHub CLI (`gh`)** pre-installed for seamless GitHub interactions
- **GitHub App credential helper** for bot-identity authentication (git + gh)
- **Custom Helm chart** tailored for Kubernetes homelab deployments
- **Tailscale sidecar** for direct tailnet access with identity-based authentication
- **Personal homelab optimizations** including NFS storage support, 1Password integration, and multi-ingress routing

## Image

Builds from the official [openclaw/openclaw](https://github.com/openclaw/openclaw) source with `gh` CLI added. Published to `ghcr.io/jedwards1230/openclaw-charts`.

### Building locally

```bash
docker build -t openclaw .

# Pin a specific version
docker build --build-arg OPENCLAW_VERSION=v2026.2.22 -t openclaw .
```

## Helm Chart

The chart is published as an OCI artifact to `oci://ghcr.io/jedwards1230/charts/openclaw`.

### Install

```bash
helm install openclaw oci://ghcr.io/jedwards1230/charts/openclaw \
  --namespace home-agent \
  --values my-values.yaml
```

### Key Values

| Value | Description | Default |
|-------|-------------|---------|
| `image.repository` | Container image | `ghcr.io/jedwards1230/openclaw-charts` |
| `image.tag` | Image tag | `latest` |
| `gateway.port` | Gateway listen port | `18789` |
| `gateway.bind` | Network binding | `lan` |
| `gateway.controlUi.allowInsecureAuth` | Allow non-HTTPS auth for control UI | `false` |
| `config` | Freeform openclaw.json config (agents, channels, tools, etc.) | `{}` |
| `webhookd.enabled` | Enable GitHub webhook HMAC verification sidecar | `false` |
| `networkPolicy.enabled` | Enable Kubernetes NetworkPolicy | `false` |
| `secrets.onepassword.enabled` | Use 1Password operator | `false` |
| `persistence.nfs.enabled` | Use NFS for storage | `false` |
| `ingress.enabled` | Enable ingress | `false` |

See `charts/openclaw/values.yaml` for the full reference.

## GitHub App Authentication

The image includes `git-credential-github-app`, a git credential helper that generates short-lived GitHub App installation tokens just-in-time. This replaces personal access tokens with scoped, auto-expiring bot identity.

**How it works:**

```
git push  →  credential helper  →  generates installation token  →  x-access-token
gh pr create  →  /usr/bin/gh wrapper  →  same credential helper  →  GH_TOKEN
```

The credential helper chain falls back gracefully — if GitHub App env vars aren't set, git uses `gh auth git-credential` and gh uses `GITHUB_TOKEN` as before.

**Required env vars** (set via extraEnv + K8s secrets):

| Variable | Description |
|----------|-------------|
| `GITHUB_APP_ID` | GitHub App ID |
| `GITHUB_APP_INSTALLATION_ID` | Installation ID for the target org/user |
| `GITHUB_APP_PRIVATE_KEY` | PEM private key content |

Tokens are cached for ~55 minutes (5-minute buffer on the 1-hour lifetime), stored at `~/.cache/github-app-credential/token.json` with `0600` permissions.

## Tailscale Sidecar

The chart supports an optional Tailscale sidecar that exposes the OpenClaw gateway directly on your tailnet via `tailscale serve`. This enables direct access from any device on the tailnet without going through Traefik ingress.

### How it works

Instead of using OpenClaw's native `--tailscale` flag (which would conflict with the LAN binding needed for Traefik ingress), the chart runs a separate Tailscale sidecar container that:

1. Joins the tailnet using an auth key from a Kubernetes secret
2. Uses `tailscale serve` to reverse-proxy HTTPS traffic to the OpenClaw gateway on `127.0.0.1` using the configurable `gateway.port` value (default `18789`)
3. Shares the Tailscale socket with the main container via an emptyDir volume, enabling `tailscale whois` for identity-based authentication

The Docker image includes the `tailscale` CLI so the main OpenClaw container can call `tailscale whois` to verify caller identity from the shared socket. When `gateway.auth.allowTailscale` is enabled, requests arriving over Tailscale can authenticate using their tailnet identity instead of a token.

### Configuration

```yaml
tailscale:
  enabled: true
  authKeySecret: "my-tailscale-secret"   # K8s secret with the auth key
  authKeySecretKey: "TS_AUTHKEY"          # Key within the secret (default)
  hostname: "openclaw"                    # Tailnet hostname (e.g., openclaw.tailnet-name.ts.net)

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

### Tailscale ACL requirements

The auth key should be created with a tag that has appropriate ACL permissions. The Tailscale node will appear on your tailnet as `<hostname>.tailnet-name.ts.net`.

## Webhookd Sidecar

The chart includes an optional webhook verification sidecar (`webhookd.enabled: true`) that validates GitHub webhook signatures before forwarding to OpenClaw.

**What it does:**
- Receives GitHub webhook POSTs on a separate port
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

## Security Considerations

**`gateway.controlUi.allowInsecureAuth`** (default: `false`) — Controls whether the control UI accepts authentication over non-HTTPS connections. Set to `true` only for local development without TLS.

**`securityContext.readOnlyRootFilesystem`** (default: `true`) — The container filesystem is read-only. Writable paths (`/tmp`, `~/.cache`, `~/.npm`) are provided via emptyDir mounts. The persistent workspace is mounted at `~/.openclaw`.

**`networkPolicy.enabled`** (default: `false`) — When enabled, applies a NetworkPolicy that allows ingress from Traefik and other pods in the same namespace, and allows egress only to DNS, HTTP (TCP/80), HTTPS (TCP/443), and the in-namespace `mcp-proxy` service on TCP/8080. Recommended for production deployments.

**Image tags** — The default `image.tag` is `latest`. For production, pin to a specific SHA tag from the build workflow.

**`envsubst` init container** — Uses `dibi/envsubst:1` by default. Pin to a specific digest for maximum supply-chain safety.

## CI/CD

- **Docker build**: `.github/workflows/build.yml` -- triggers on Dockerfile changes or manual dispatch
- **Helm publish**: `.github/workflows/helm-publish.yml` -- triggers on chart changes or manual dispatch

## Version Bumping

To update the OpenClaw version:

1. Change `OPENCLAW_VERSION` default in `.github/workflows/build.yml`
2. Update `appVersion` in `charts/openclaw/Chart.yaml`
3. Push to `main` or run the build workflow manually
