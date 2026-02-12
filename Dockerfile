FROM node:22-bookworm

LABEL org.opencontainers.image.source="https://github.com/jedwards1230/openclaw-charts"
LABEL org.opencontainers.image.description="OpenClaw gateway with GitHub CLI, kubectl, ArgoCD, Helm, Helmfile, Logcli, Promtool, and Tailscale"
LABEL org.opencontainers.image.licenses="MIT"

# Install GitHub CLI (requires GitHub apt repo — not in standard Debian)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install CLI tools for K8s management (1Password CLI, kubectl, ArgoCD CLI)
RUN apt-get update \
    && apt-get install -y --no-install-recommends gnupg jq unzip \
    # Install 1Password CLI
    && curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
      | gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
      > /etc/apt/sources.list.d/1password.list \
    && mkdir -p /etc/debsig/policies/AC2D62742012EA22 \
    && curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol \
      > /etc/debsig/policies/AC2D62742012EA22/1password.pol \
    && mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 \
    && curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
      > /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
    # Install kubectl
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key \
      | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" \
      > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends 1password-cli kubectl \
    # Install ArgoCD CLI (pinned version)
    && ARGOCD_VERSION="v3.3.0" \
    && ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in amd64|arm64) ;; *) echo "Unsupported architecture for ArgoCD CLI: ${ARCH}" >&2; exit 1 ;; esac \
    && curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${ARCH}" \
    && chmod +x /usr/local/bin/argocd \
    # Install yq (YAML processor)
    && YQ_VERSION="v4.44.3" \
    && YQ_ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" \
    && chmod +x /usr/local/bin/yq \
    # Install Helm (Kubernetes package manager)
    && HELM_VERSION="v3.16.3" \
    && HELM_ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz" | tar xz -C /tmp \
    && mv /tmp/linux-${HELM_ARCH}/helm /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && rm -rf /tmp/linux-${HELM_ARCH} \
    # Install Helmfile (Helm release management)
    && HELMFILE_VERSION="v1.2.2" \
    && HELMFILE_ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_linux_${HELMFILE_ARCH}.tar.gz" | tar xz -C /tmp \
    && mv /tmp/helmfile /usr/local/bin/helmfile \
    && chmod +x /usr/local/bin/helmfile \
    # Install Logcli (Loki CLI)
    && LOGCLI_VERSION="v3.3.2" \
    && LOGCLI_ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/grafana/loki/releases/download/${LOGCLI_VERSION}/logcli-linux-${LOGCLI_ARCH}.zip" -o /tmp/logcli.zip \
    && unzip -q /tmp/logcli.zip -d /tmp \
    && mv /tmp/logcli-linux-${LOGCLI_ARCH} /usr/local/bin/logcli \
    && chmod +x /usr/local/bin/logcli \
    && rm /tmp/logcli.zip \
    # Install promtool (Prometheus CLI)
    && PROMTOOL_VERSION="v3.9.1" \
    && PROMTOOL_ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/prometheus/prometheus/releases/download/${PROMTOOL_VERSION}/prometheus-${PROMTOOL_VERSION#v}.linux-${PROMTOOL_ARCH}.tar.gz" | tar xz -C /tmp \
    && mv /tmp/prometheus-${PROMTOOL_VERSION#v}.linux-${PROMTOOL_ARCH}/promtool /usr/local/bin/promtool \
    && chmod +x /usr/local/bin/promtool \
    && rm -rf /tmp/prometheus-${PROMTOOL_VERSION#v}.linux-${PROMTOOL_ARCH} \
    && rm -rf /var/lib/apt/lists/*

# Install Bun (required by OpenClaw build scripts)
ARG BUN_VERSION=1.3.9
ENV BUN_INSTALL="/usr/local"
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"

RUN corepack enable

WORKDIR /app

# Clone OpenClaw at pinned version and remove .git for smaller image
ARG OPENCLAW_VERSION=v2026.2.6
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} \
      https://github.com/openclaw/openclaw.git . \
    && rm -rf .git

# Install dependencies and build (follows official Dockerfile exactly)
RUN pnpm install --frozen-lockfile
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Cache-bust: force rebuild 2026-02-08T15:28
# GitHub App credential helper: generates installation tokens just-in-time
# for both git (credential helper protocol) and gh (GH_TOKEN wrapper)
COPY scripts/git-credential-github-app /usr/local/bin/git-credential-github-app
RUN chmod +x /usr/local/bin/git-credential-github-app

# gh wrapper: injects GitHub App token as GH_TOKEN before calling real gh.
# Falls back to existing GITHUB_TOKEN/GH_TOKEN if App env vars aren't set.
RUN mv /usr/bin/gh /usr/bin/gh-real \
    && printf '#!/bin/sh\n\
TOKEN=$(/usr/local/bin/git-credential-github-app --token 2>/dev/null)\n\
[ -n "$TOKEN" ] && export GH_TOKEN="$TOKEN"\n\
exec /usr/bin/gh-real "$@"\n' > /usr/bin/gh \
    && chmod +x /usr/bin/gh

# Create cache directory for GitHub App credential helper.
# Use 770 so fsGroup (set via podSecurityContext) can grant access when the
# container runs as a different UID than the image default (uid 1000).
RUN mkdir -p /home/node/.cache/github-app-credential \
    && chown -R node:node /home/node/.cache \
    && chmod 770 /home/node/.cache \
    && chmod 700 /home/node/.cache/github-app-credential

# Install Tailscale CLI (for tailscale whois identity verification)
ARG TAILSCALE_VERSION=1.82.5
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${ARCH}.tgz" \
      | tar xzf - --strip-components=1 -C /usr/local/bin "tailscale_${TAILSCALE_VERSION}_${ARCH}/tailscale"

# Make openclaw CLI available in PATH (package.json declares bin but pnpm
# doesn't link it globally during install; symlink the entry point directly)
RUN ln -s /app/openclaw.mjs /usr/local/bin/openclaw

# Ensure node user owns everything
RUN chown -R node:node /app

# Run as non-root (node = uid 1000)
USER node

CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured", "--bind", "lan"]
