# Security Hardening - OpenClaw Deployment

## Overview

This document describes the security hardening measures applied to the OpenClaw deployment.

## Implemented Security Controls

### 1. Container Security Context

**Pod-level security:**
- ✅ `runAsNonRoot: true` - Enforces container cannot run as root
- ✅ `runAsUser: 568` / `runAsGroup: 568` - Consistent non-privileged user
- ✅ `fsGroup: 568` - Ensures volume permissions work correctly
- ✅ `seccompProfile: RuntimeDefault` - Reduces syscall attack surface

**Container-level security:**
- ✅ `allowPrivilegeEscalation: false` - Prevents gaining privileges
- ✅ `capabilities.drop: ALL` - Removes all Linux capabilities
- ✅ `runAsNonRoot: true` - Double enforcement at container level
- ⚠️ `readOnlyRootFilesystem: false` - Required for OpenClaw's runtime operations (node_modules, git, npm cache)

### 2. ServiceAccount & RBAC

- ✅ Dedicated ServiceAccount created for OpenClaw pod
- ✅ `automountServiceAccountToken: false` - Prevents unnecessary API access
- ✅ No additional RBAC permissions (uses default isolated SA)

### 3. Pod Security Standards

Pod labels applied for Kubernetes Pod Security Admission:
- `pod-security.kubernetes.io/enforce: baseline` - Enforces baseline security
- `pod-security.kubernetes.io/audit: restricted` - Audits against restricted standard
- `pod-security.kubernetes.io/warn: restricted` - Warns about restricted violations

### 4. Network Segmentation

- ✅ NetworkPolicy template created (currently disabled)
- When enabled, restricts:
  - Ingress: Only from Traefik and same namespace
  - Egress: DNS, HTTPS, HTTP, and MCP proxy access
  - Denies all other traffic by default

### 5. Secret Management

- ✅ Secrets injected via init container using envsubst
- ✅ Secrets stored in 1Password via External Secrets Operator
- ✅ No secrets in environment variables of main container
- ✅ Config file with secrets written to ephemeral volume

### 6. Authentication & Authorization

- ⚠️ `allowInsecureAuth: false` - Changed from `true` (requires proper auth flow)
- ✅ Gateway uses token-based authentication
- ✅ Ingress protected by Traefik middleware (LAN-only access)

## Known Limitations

### readOnlyRootFilesystem

Currently set to `false` because OpenClaw requires write access to:
- `/app` - For node_modules and runtime operations
- `/home/node/.openclaw` - For workspace, config, and git operations

**Future improvement:** Use emptyDir volumes for writable paths to enable readOnlyRootFilesystem.

### NetworkPolicy

Currently disabled to match cluster-wide policy (no NetworkPolicies in use).

**Future improvement:** Enable when cluster adopts NetworkPolicy-based microsegmentation.

### Dockerfile Security

Current Dockerfile runs build as root, then switches to node user.

**Future improvements:**
- Multi-stage build to reduce image size
- Verify GitHub CLI and Bun installer signatures
- Use distroless or Alpine-based final image
- Build as non-root throughout

## Testing Recommendations

After applying changes:

1. **Verify pod starts successfully:**
   ```bash
   kubectl get pods -n home-agent -l app.kubernetes.io/name=openclaw
   kubectl logs -n home-agent -l app.kubernetes.io/name=openclaw
   ```

2. **Test authentication:**
   - Verify gateway requires token authentication
   - Test Discord bot connectivity
   - Confirm Traefik ingress works

3. **Check security context:**
   ```bash
   kubectl get pod -n home-agent -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].spec.securityContext}'
   ```

4. **Verify ServiceAccount:**
   ```bash
   kubectl get sa -n home-agent openclaw
   kubectl get pod -n home-agent -l app.kubernetes.io/name=openclaw -o jsonpath='{.items[0].spec.serviceAccountName}'
   ```

## Rollback Plan

If issues arise:

1. Revert helmfile changes:
   ```bash
   cd k8s/apps/hagen/openclaw
   git revert <commit>
   ```

2. Downgrade chart version:
   ```yaml
   chart: oci://ghcr.io/jedwards1230/charts/openclaw
   version: 0.2.0  # Previous version
   ```

3. Re-enable insecure auth temporarily:
   ```yaml
   gateway:
     controlUi:
       allowInsecureAuth: true
   ```

## References

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [NSA/CISA Kubernetes Hardening Guide](https://www.cisa.gov/news-events/alerts/2022/03/15/updated-kubernetes-hardening-guide)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
