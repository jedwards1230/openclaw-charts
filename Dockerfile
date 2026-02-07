FROM node:22-bookworm

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
    # Install ArgoCD CLI
    && curl -fsSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-$(dpkg --print-architecture | sed 's/amd64/amd64/;s/arm64/arm64/') \
    && chmod +x /usr/local/bin/argocd \
    && rm -rf /var/lib/apt/lists/*

# Install Bun (required by OpenClaw build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

# Clone OpenClaw at pinned version and remove .git for smaller image
ARG OPENCLAW_VERSION=v2026.2.3
RUN git clone --depth 1 --branch ${OPENCLAW_VERSION} \
      https://github.com/openclaw/openclaw.git . \
    && rm -rf .git

# Install dependencies and build (follows official Dockerfile exactly)
RUN pnpm install --frozen-lockfile
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Ensure node user owns everything
RUN chown -R node:node /app

# Run as non-root (node = uid 1000)
USER node

CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured", "--bind", "lan"]
