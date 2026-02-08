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
    && apt-get install -y --no-install-recommends gnupg \
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

# Ensure node user owns everything
RUN chown -R node:node /app

# Run as non-root (node = uid 1000)
USER node

CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured", "--bind", "lan"]
