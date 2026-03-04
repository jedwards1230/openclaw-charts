# Security

## Container Security

**`securityContext.readOnlyRootFilesystem`** (default: `true`) — The container filesystem is read-only. Writable paths (`/tmp`, `~/.cache`, `~/.npm`) are provided via emptyDir mounts. The persistent workspace is mounted at `~/.openclaw`.

**`podSecurityContext`** defaults:
- `runAsUser: 1000` / `runAsGroup: 1000` / `fsGroup: 1000`
- `runAsNonRoot: true`
- `seccompProfile.type: RuntimeDefault`
- All capabilities dropped (`capabilities.drop: [ALL]`)

## Authentication

**`gateway.controlUi.allowInsecureAuth`** (default: `false`) — Controls whether the control UI accepts authentication over non-HTTPS connections. Set to `true` only for local development without TLS.

**`gateway.controlUi.dangerouslyDisableDeviceAuth`** (default: `false`) — Break-glass option to disable per-device pairing for the web UI. Use only as temporary recovery when locked out; revert immediately after.

## Network Security

**`networkPolicy.enabled`** (default: `false`) — When enabled, applies a NetworkPolicy that restricts ingress and egress. Recommended for production since OpenClaw can execute agent code and make arbitrary web requests. See [configuration.md](configuration.md#networkpolicy) for details.

## Supply Chain

**Image tags** — The default `image.tag` is `latest`. For production, pin to a specific version tag (e.g., `v2026.3.1`) from the [releases page](https://github.com/jedwards1230/openclaw-charts/releases).

**`envsubst` init container** — Uses `dibi/envsubst:1` by default. Pin to a specific digest for maximum supply-chain safety:
```yaml
envsubst:
  image: dibi/envsubst:1@sha256:<digest>
```

## Playwright / Chrome Headless Shell

When `playwright.enabled: true`, the chart sets `browser.noSandbox=true` in `openclaw.json`. Chrome's renderer sandbox is disabled because it requires privileged syscalls blocked by Kubernetes RuntimeDefault seccomp. This is a known trade-off for containerized headless browsers. Mitigate by enabling `networkPolicy` to limit what a compromised renderer process can reach.
