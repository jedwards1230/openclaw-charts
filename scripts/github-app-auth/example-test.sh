#!/bin/bash
set -euo pipefail

# Example test script - DO NOT RUN without setting credentials!
# This demonstrates the full workflow

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔍 Checking prerequisites..."

# Check if env vars are set
if [[ -z "$GITHUB_APP_ID" ]] || [[ -z "$GITHUB_APP_INSTALLATION_ID" ]]; then
  echo "❌ Error: GitHub App credentials not set"
  echo "Please set:"
  echo "  export GITHUB_APP_ID='your-app-id'"
  echo "  export GITHUB_APP_INSTALLATION_ID='your-installation-id'"
  echo "  export GITHUB_APP_PRIVATE_KEY_PATH='/path/to/key.pem'"
  exit 1
fi

echo "✅ Credentials found"
echo ""

echo "🔑 Generating token..."
TOKEN=$(node "$SCRIPT_DIR/github-app-token.mjs")
echo "✅ Token generated: ${TOKEN:0:20}..."
echo ""

echo "📊 Getting token details..."
node "$SCRIPT_DIR/github-app-token.mjs" --json
echo ""

echo "🧪 Testing gh CLI with wrapper..."
"$SCRIPT_DIR/gh-wrapper.sh" auth status
echo ""

echo "✅ All tests passed!"
echo ""
echo "Try these commands:"
echo "  ./gh-wrapper.sh pr list --repo owner/repo"
echo "  ./gh-wrapper.sh issue list --repo owner/repo"
