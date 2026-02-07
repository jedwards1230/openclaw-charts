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
