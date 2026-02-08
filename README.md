# OpenClaw Charts

Custom OpenClaw Docker image and Helm chart for deploying a Discord bot with GitHub CLI support.

> **Note**: This is a customized build based on the upstream [openclaw/openclaw](https://github.com/openclaw/openclaw) project. It includes additional tooling and configuration for personal homelab deployments.

## What's Different

This customized build includes:

- **GitHub CLI (`gh`)** pre-installed for seamless GitHub interactions
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

## CI/CD

- **Docker build**: `.github/workflows/build.yml` -- triggers on Dockerfile changes or manual dispatch
- **Helm publish**: `.github/workflows/helm-publish.yml` -- triggers on chart changes or manual dispatch

## Version Bumping

To update the OpenClaw version:

1. Change `OPENCLAW_VERSION` default in `.github/workflows/build.yml`
2. Update `appVersion` in `charts/openclaw/Chart.yaml`
3. Push to `main` or run the build workflow manually
