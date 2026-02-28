#!/bin/bash
# Hook: SessionStart
# Fires once when a fresh Claude Code session begins (not on resume).
#
# In Claude Code Web (ephemeral containers), installs required tools.
# In local devcontainers, tools are pre-installed via Dockerfile.

set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  echo "[hook:session-start] Running in Claude Code Web (ephemeral container)"
  
  # Install helm if not present
  if ! command -v helm &>/dev/null; then
    echo "[hook:session-start] Installing helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1
  fi

  # Install yq if not present
  if ! command -v yq &>/dev/null; then
    echo "[hook:session-start] Installing yq..."
    curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
      -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
  fi
else
  echo "[hook:session-start] Running in local devcontainer -- tools pre-installed"
fi

echo "[hook:session-start] Done"
exit 0
