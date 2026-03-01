# ═══════════════════════════════════════════════════════════════
# Stage 1: Download static CLI binaries
# Cached independently — only rebuilds when tool versions change
# ═══════════════════════════════════════════════════════════════
FROM debian:bookworm-slim AS tools

ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# All static binaries in a single layer for better caching
ARG ARGOCD_VERSION=v3.3.0
ARG YQ_VERSION=v4.52.2
ARG HELM_VERSION=v4.1.0
ARG HELMFILE_VERSION=v1.2.2
ARG LOGCLI_VERSION=v3.6.5
ARG PROMTOOL_VERSION=v3.9.1
ARG TAILSCALE_VERSION=1.82.5

RUN mkdir -p /out \
    # ArgoCD CLI
    && curl -fsSL -o /out/argocd \
       "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${TARGETARCH}" \
    # yq (YAML processor)
    && curl -fsSL -o /out/yq \
       "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}" \
    # Helm
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
       | tar xz -C /tmp \
    && mv /tmp/linux-${TARGETARCH}/helm /out/helm \
    && rm -rf /tmp/linux-${TARGETARCH} \
    # Helmfile
    && curl -fsSL "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_linux_${TARGETARCH}.tar.gz" \
       | tar xz -C /tmp \
    && mv /tmp/helmfile /out/helmfile \
    # Logcli (Loki CLI)
    && curl -fsSL "https://github.com/grafana/loki/releases/download/${LOGCLI_VERSION}/logcli-linux-${TARGETARCH}.zip" \
       -o /tmp/logcli.zip \
    && unzip -q /tmp/logcli.zip -d /tmp \
    && mv /tmp/logcli-linux-${TARGETARCH} /out/logcli \
    && rm /tmp/logcli.zip \
    # Promtool (Prometheus CLI)
    && curl -fsSL "https://github.com/prometheus/prometheus/releases/download/${PROMTOOL_VERSION}/prometheus-${PROMTOOL_VERSION#v}.linux-${TARGETARCH}.tar.gz" \
       | tar xz -C /tmp \
    && mv /tmp/prometheus-${PROMTOOL_VERSION#v}.linux-${TARGETARCH}/promtool /out/promtool \
    && rm -rf /tmp/prometheus-* \
    # Tailscale CLI
    && curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TARGETARCH}.tgz" \
       | tar xzf - --strip-components=1 -C /out "tailscale_${TAILSCALE_VERSION}_${TARGETARCH}/tailscale" \
    && chmod +x /out/*

# Go SDK (large — separate layer for caching)
ARG GO_VERSION=1.26.0
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
      | tar -xzC /usr/local \
    && /usr/local/go/bin/go version

# Go language server (used by Claude Code for Go repos)
RUN GOBIN=/out /usr/local/go/bin/go install golang.org/x/tools/gopls@latest \
    && chmod 755 /out/gopls

# Claude Code CLI (install script extracts binary)
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp -L /root/.local/bin/claude /out/claude \
    && chmod 755 /out/claude \
    && rm -rf /root/.local/share/claude /root/.local/bin/claude /root/.claude


# ═══════════════════════════════════════════════════════════════
# Stage 2: Build OpenClaw application
# Bun is only needed here — not shipped to runtime
# ═══════════════════════════════════════════════════════════════
FROM node:25-bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates unzip python3 make g++ libopus-dev \
    && rm -rf /var/lib/apt/lists/*

# Bun (required by OpenClaw build scripts — build-time only)
ARG BUN_VERSION=1.3.9
ENV BUN_INSTALL="/usr/local"
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"

# Node 25 removed corepack — install it explicitly for pnpm
RUN npm install -g --force corepack && corepack enable

WORKDIR /app

# Clone OpenClaw at pinned version and remove .git for smaller copy
ARG OPENCLAW_VERSION=v2026.2.26
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} \
      https://github.com/openclaw/openclaw.git . \
    && rm -rf .git

# Install dependencies and build
RUN pnpm install --frozen-lockfile

# Discord voice: encryption lib (pure JS, no native deps) + rebuild native opus addon
RUN pnpm add -w libsodium-wrappers @snazzah/davey \
    && pnpm rebuild @discordjs/opus
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# Install MCP integration plugin (community extension, pinned commit)
# Upstream stores openclaw.plugin.json in config/ — OpenClaw resolves package.json
# "main" (src/index.js) and expects the manifest next to the entry point.
ARG MCP_PLUGIN_COMMIT=fa9c22b9be58d1e1218014c93fb2c2a514cfc44b
RUN git init extensions/mcp-integration \
    && cd extensions/mcp-integration \
    && git remote add origin https://github.com/lunarpulse/openclaw-mcp-plugin.git \
    && git fetch --depth 1 origin ${MCP_PLUGIN_COMMIT} \
    && git checkout FETCH_HEAD \
    && cp config/openclaw.plugin.json . \
    && cp config/openclaw.plugin.json src/ \
    && npm install --production \
    && rm -rf .git

ENV NODE_ENV=production


# ═══════════════════════════════════════════════════════════════
# Stage 3: Runtime image
# All tools available, no build-time cruft (Bun, build deps)
# ═══════════════════════════════════════════════════════════════
FROM node:25-bookworm

LABEL org.opencontainers.image.source="https://github.com/jedwards1230/openclaw-charts"
LABEL org.opencontainers.image.description="OpenClaw gateway with GitHub CLI, kubectl, ArgoCD, Helm, Helmfile, Logcli, Promtool, Go, Tailscale, and Claude Code"
LABEL org.opencontainers.image.licenses="MIT"

# Install apt-managed CLIs: GitHub CLI, 1Password CLI, kubectl
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
      | gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
      > /etc/apt/sources.list.d/1password.list \
    && mkdir -p /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22 \
    && curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol \
      > /etc/debsig/policies/AC2D62742012EA22/1password.pol \
    && curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
      > /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
      | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
      > /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh 1password-cli kubectl gnupg jq wakeonlan ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Chromium for headless browser automation (used by research agent via CDP)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       chromium chromium-sandbox fonts-liberation fonts-noto-color-emoji \
       libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 \
       libnss3 libxcomposite1 libxdamage1 libxrandr2 libxss1 \
    && rm -rf /var/lib/apt/lists/*

# Static CLI binaries from tools stage
COPY --from=tools /out/ /usr/local/bin/

# Go SDK from tools stage
COPY --from=tools /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# Node 25 removed corepack — install it explicitly for pnpm at runtime
RUN npm install -g --force corepack && corepack enable

# Make openclaw CLI available in PATH (package.json declares bin but pnpm
# doesn't link it globally during install; dangling symlink resolves after build)
RUN ln -s /app/openclaw.mjs /usr/local/bin/openclaw

# Prepare directories with correct ownership so all app files are created as
# node user — eliminates the need for a costly `chown -R` layer at the end.
# Cache dir uses 770 so fsGroup (podSecurityContext) can grant access when
# the container runs as a different UID than the image default (uid 1000).
RUN mkdir -p /app \
    && chown node:node /app \
    && mkdir -p /home/node/.cache \
    && chown -R node:node /home/node/.cache \
    && chmod 770 /home/node/.cache

WORKDIR /app
USER node

# Application from builder stage (dist, node_modules, extensions)
COPY --from=builder --chown=node:node /app /app

ENV NODE_ENV=production
ENV OPENCLAW_PREFER_PNPM=1

CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured", "--bind", "lan"]
