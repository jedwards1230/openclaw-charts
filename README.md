# OpenClaw Charts

Custom OpenClaw Docker image and Helm chart for deploying a Discord bot with GitHub CLI support.

> **Note**: This is a customized build based on the upstream [openclaw/openclaw](https://github.com/openclaw/openclaw) project. It includes additional tooling and configuration for personal homelab deployments.

## What's Different

This customized build includes:

- **GitHub CLI (`gh`)** pre-installed for seamless GitHub interactions
- **GitHub App credential helper** for bot-identity authentication (git + gh)
- **Custom Helm chart** tailored for Kubernetes homelab deployments
- **Personal homelab optimizations** including NFS storage support, 1Password integration, and multi-ingress routing

## Image

Builds from the official [openclaw/openclaw](https://github.com/openclaw/openclaw) source with `gh` CLI added. Published to `ghcr.io/jedwards1230/openclaw-charts`.

### Building locally

```bash
docker build -t openclaw .

# Pin a specific version
docker build --build-arg OPENCLAW_VERSION=v2026.2.6 -t openclaw .
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
| `discord.enabled` | Enable Discord channel | `true` |
| `agents.defaults.model.primary` | Default LLM model | `anthropic/claude-sonnet-4-5` |
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

## CI/CD

- **Docker build**: `.github/workflows/build.yml` -- triggers on Dockerfile changes or manual dispatch
- **Helm publish**: `.github/workflows/helm-publish.yml` -- triggers on chart changes or manual dispatch

## Version Bumping

To update the OpenClaw version:

1. Change `OPENCLAW_VERSION` default in `.github/workflows/build.yml`
2. Update `appVersion` in `charts/openclaw/Chart.yaml`
3. Push to `main` or run the build workflow manually
