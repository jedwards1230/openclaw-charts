#!/bin/bash
# gh-wrapper.sh - Wrapper for gh CLI that auto-injects GitHub App token
#
# This script wraps the `gh` CLI and automatically generates/caches a GitHub App
# installation token, setting it as GH_TOKEN before invoking the real gh command.
#
# Usage:
#   1. Set environment variables:
#      export GITHUB_APP_ID="123456"
#      export GITHUB_APP_INSTALLATION_ID="98765"
#      export GITHUB_APP_PRIVATE_KEY_PATH="/path/to/key.pem"
#   
#   2. Use this script as you would use `gh`:
#      ./gh-wrapper.sh pr list
#      ./gh-wrapper.sh issue create --title "Test"
#
#   3. Or create an alias:
#      alias gh="$PWD/gh-wrapper.sh"

set -euo pipefail

# Path to the token generator script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_GENERATOR="$SCRIPT_DIR/github-app-token.mjs"

# Check if token generator exists
if [[ ! -f "$TOKEN_GENERATOR" ]]; then
  echo "Error: github-app-token.mjs not found at $TOKEN_GENERATOR" >&2
  exit 1
fi

# Check for required environment variables
if [[ -z "${GITHUB_APP_ID:-}" ]] || [[ -z "${GITHUB_APP_INSTALLATION_ID:-}" ]]; then
  echo "Error: GITHUB_APP_ID and GITHUB_APP_INSTALLATION_ID must be set" >&2
  exit 1
fi

if [[ -z "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]] && [[ -z "${GITHUB_APP_PRIVATE_KEY_BASE64:-}" ]]; then
  echo "Error: Either GITHUB_APP_PRIVATE_KEY_PATH or GITHUB_APP_PRIVATE_KEY_BASE64 must be set" >&2
  exit 1
fi

# Generate/fetch token (uses cache if valid)
export GH_TOKEN=$(node "$TOKEN_GENERATOR")

if [[ -z "$GH_TOKEN" ]]; then
  echo "Error: Failed to generate GitHub App token" >&2
  exit 1
fi

# Execute gh with the token
exec gh "$@"
