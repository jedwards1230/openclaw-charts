# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A custom Helm chart + Docker image for deploying [OpenClaw](https://github.com/openclaw/openclaw) — an AI messaging gateway (Telegram, Discord, Slack). This is a fork that adds tooling CLIs (gh, kubectl, argocd, 1password, etc.) to the upstream OpenClaw image and wraps it in a Helm chart with sidecars for Tailscale identity auth and GitHub webhook verification.

## Common Commands

### Helm Linting & Validation

```bash
# Lint with all value profiles
helm lint charts/openclaw/
helm lint charts/openclaw/ -f charts/openclaw/values-development.yaml
helm lint charts/openclaw/ -f charts/openclaw/values-production.yaml

# Template render (check output)
helm template test charts/openclaw/
helm template test charts/openclaw/ -f charts/openclaw/values-production.yaml

# Chart-testing (CI-style validation)
ct lint --config ct.yaml
```

### Version Bumping

```bash
# Bump upstream OpenClaw version (updates Dockerfile, Chart.yaml, README.md)
./scripts/bump-version.sh 2026.2.25

# Also bump chart version (patch increment)
./scripts/bump-version.sh 2026.2.25 --bump-chart
```

### Docker Build

```bash
docker build -t openclaw-charts:test .
```

## Version Sync Rules (CI-Enforced)

Three files must stay in sync — `version-check.yml` blocks PRs on mismatch:

| File | Field | Example |
|------|-------|---------|
| `Dockerfile` | `ARG OPENCLAW_VERSION=v<version>` | `v2026.2.24` |
| `charts/openclaw/Chart.yaml` | `appVersion: "<version>"` | `"2026.2.24"` |
| `README.md` | All `v<version>` references | `v2026.2.24` |

If chart templates or values change, `Chart.yaml` `version:` must also be bumped (patch increment). Use `./scripts/bump-version.sh <version> --bump-chart` to handle both.

## Architecture

### Docker Image (Multi-Stage)

1. **`tools` stage** — Downloads static CLI binaries (ArgoCD, Helm, Helmfile, kubectl, yq, Go, Claude CLI, Tailscale, etc.)
2. **`builder` stage** — Clones upstream OpenClaw at the pinned version, installs MCP plugin, builds with `pnpm build && pnpm ui:build`
3. **`runtime` stage** — Node 25-bookworm with all tools + built app. Non-root (`node:node`), read-only root filesystem

Published to `ghcr.io/jedwards1230/openclaw-charts`.

### Helm Chart (`charts/openclaw/`)

**Key templates:**
- `deployment.yaml` — Main pod with envsubst init container for secret injection, optional Tailscale + webhookd sidecars
- `configmap.yaml` — Dynamically generates `openclaw.json` by merging `gateway.*` values with `config` values; auto-appends plugin repo paths
- `configmap-webhookd.yaml` — Node.js sidecar that verifies GitHub webhook HMAC signatures before forwarding to the gateway
- `configmap-tailscale.yaml` — Tailscale sidecar startup script
- `networkpolicy.yaml` — Optional egress restrictions (DNS, HTTP/S, mcp-proxy, ollama, otel)

**Values profiles:**
- `values.yaml` — Full defaults (419 lines), token auth, no persistence
- `values-development.yaml` — HTTP auth allowed, `pullPolicy: Always`, relaxed security
- `values-production.yaml` — TLS, NFS persistence, hardened security, ingress enabled

**Notable values patterns:**
- `gateway.*` — Mapped to openclaw gateway config (port, bind, auth mode, rate limiting, control UI)
- `config` — Freeform object merged into `openclaw.json` (for app-level config beyond gateway)
- `pluginRepos` — Git repos cloned at startup and auto-registered as plugin paths
- `hookTransforms` / `agentScripts` — Mounted as files into OpenClaw directories
- `secrets.onepassword.*` — 1Password Operator integration for secret injection
- `webhookd.enabled` / `tailscale.enabled` — Optional sidecar toggles

### CI/CD Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `pr-check.yml` | PR | Docker build + helm lint/template + ct lint |
| `version-check.yml` | PR to main | Enforce Dockerfile ↔ Chart.yaml version sync |
| `build.yml` | Dockerfile changes | Build + push Docker image to GHCR |
| `helm-publish.yml` | Chart changes | Package + push Helm chart to OCI registry |
| `release.yml` | Daily 02:00 UTC | Create GitHub releases (Docker + Helm) |
| `check-upstream.yml` | Every 6 hours | Auto-detect new upstream releases, create bump PR |
| `claude-upgrade-analysis.yml` | Called by check-upstream | Claude analysis of upgrade impact |

### Upstream Tracking

The `auto/bump-openclaw` branch is auto-managed by `check-upstream.yml`. It stacks multiple upstream releases if the PR isn't merged between releases. Each version gets its own commit and PR comment with release notes.
