# OpenClaw Charts

[![PR Check](https://github.com/jedwards1230/openclaw-charts/actions/workflows/pr-check.yml/badge.svg)](https://github.com/jedwards1230/openclaw-charts/actions/workflows/pr-check.yml)
[![Release](https://github.com/jedwards1230/openclaw-charts/actions/workflows/release.yml/badge.svg)](https://github.com/jedwards1230/openclaw-charts/actions/workflows/release.yml)

Custom Docker image and Helm chart for deploying [OpenClaw](https://github.com/openclaw/openclaw) — a multi-channel AI messaging gateway supporting Telegram, Discord, Slack, and more. Bundles CLI tooling (GitHub CLI, kubectl, ArgoCD, Helm, Go, Claude Code, etc.) for AI agent workflows that interact with infrastructure.

## Quick Start

```bash
helm install openclaw oci://ghcr.io/jedwards1230/charts/openclaw \
  --namespace openclaw --create-namespace \
  --set secrets.existingSecret=my-openclaw-secrets
```

## Features

- **Batteries-included image** — Pre-built with CLI tools for AI agents that manage infrastructure, repositories, and deployments
- **Helm chart** with sensible defaults and optional sidecars:
  - **Tailscale** — Expose the gateway on your tailnet with identity-based auth
  - **Webhookd** — GitHub webhook HMAC signature verification proxy
- **Plugin system** — Clone and mount plugin repos at startup via `pluginRepos` values
- **Playwright** — Optional Chrome Headless Shell for browser automation in containers
- **Security hardened** — Read-only root filesystem, dropped capabilities, seccomp, optional NetworkPolicy
- **1Password integration** — Optional secret injection via the 1Password Kubernetes Operator
- **Automated upstream tracking** — CI checks for new OpenClaw releases every 6 hours and opens bump PRs

## Installation

### OCI Helm Chart

```bash
# Install with custom values
helm install openclaw oci://ghcr.io/jedwards1230/charts/openclaw \
  --version 0.17.0 \
  --values my-values.yaml

# Or use the Docker image directly
docker run ghcr.io/jedwards1230/openclaw-charts:v2026.3.1-r2
```

### Configuration

See [`charts/openclaw/values.yaml`](charts/openclaw/values.yaml) for the full reference. Key values:

| Value | Description | Default |
|-------|-------------|---------|
| `gateway.port` | Gateway listen port | `18789` |
| `gateway.auth.mode` | Auth mode (`token`, `trusted-proxy`) | `token` |
| `config` | Freeform `openclaw.json` config (agents, channels, tools) | `{}` |
| `pluginRepos` | Git repos to clone as plugins at startup | `[]` |
| `tailscale.enabled` | Enable Tailscale sidecar | `false` |
| `webhookd.enabled` | Enable webhook verification sidecar | `false` |
| `networkPolicy.enabled` | Enable Kubernetes NetworkPolicy | `false` |
| `playwright.enabled` | Enable Chrome Headless Shell | `false` |
| `secrets.existingSecret` | Name of existing K8s Secret | `""` |
| `secrets.onepassword.enabled` | Use 1Password Operator for secrets | `false` |

Value profiles for common setups: [`values-development.yaml`](charts/openclaw/values-development.yaml), [`values-production.yaml`](charts/openclaw/values-production.yaml).

For detailed setup guides (GitHub App auth, Tailscale, webhookd, plugin repos, NetworkPolicy), see [`docs/configuration.md`](docs/configuration.md). For security hardening, see [`docs/security.md`](docs/security.md).

## Version Bumping

Upstream tracking is automated — a CI workflow checks for new releases every 6 hours and opens a PR. To bump manually:

```bash
./scripts/bump-version.sh 2026.3.1           # Bump app version
./scripts/bump-version.sh 2026.3.1 --bump-chart  # Also increment chart version
```

## License

[MIT](LICENSE)
