#!/usr/bin/env bash
# Bump the OpenClaw upstream version across all references.
# Usage: ./scripts/bump-version.sh <new-version> [--bump-chart]
# Example: ./scripts/bump-version.sh 2026.2.12
# Example: ./scripts/bump-version.sh 2026.2.12 --bump-chart

set -euo pipefail

BUMP_CHART=false
NEW_VERSION=""

for arg in "$@"; do
  case "$arg" in
    --bump-chart) BUMP_CHART=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) NEW_VERSION="$arg" ;;
  esac
done

if [[ -z "$NEW_VERSION" ]]; then
  echo "Usage: $0 <new-version> [--bump-chart]" >&2
  exit 1
fi

# Strip leading 'v' if provided
NEW_VERSION="${NEW_VERSION#v}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART_YAML="$REPO_ROOT/charts/openclaw/Chart.yaml"

# Find current version from Chart.yaml (source of truth)
CURRENT="$(grep '^appVersion:' "$CHART_YAML" \
  | sed 's/appVersion: *"\(.*\)"/\1/')"

if [[ "$CURRENT" == "$NEW_VERSION" ]]; then
  echo "Already at version $NEW_VERSION"
  exit 0
fi

echo "Bumping OpenClaw version: $CURRENT → $NEW_VERSION"

# 1. Dockerfile — ARG OPENCLAW_VERSION=v<version>
sed -i "s|OPENCLAW_VERSION=v${CURRENT}|OPENCLAW_VERSION=v${NEW_VERSION}|g" \
  "$REPO_ROOT/Dockerfile"

# 2. Chart.yaml — appVersion: "<version>"
sed -i "s|appVersion: \"${CURRENT}\"|appVersion: \"${NEW_VERSION}\"|" \
  "$CHART_YAML"

# 3. build.yml — description example
sed -i "s|v${CURRENT}|v${NEW_VERSION}|g" \
  "$REPO_ROOT/.github/workflows/build.yml"

# 4. README.md — doc examples
sed -i "s|v${CURRENT}|v${NEW_VERSION}|g" \
  "$REPO_ROOT/README.md"

# 5. Optionally bump chart version (patch increment)
if [[ "$BUMP_CHART" == "true" ]]; then
  CHART_VERSION="$(grep '^version:' "$CHART_YAML" | awk '{print $2}')"
  MAJOR="${CHART_VERSION%%.*}"
  REST="${CHART_VERSION#*.}"
  MINOR="${REST%%.*}"
  PATCH="${REST#*.}"
  NEW_CHART_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
  sed -i "s|^version: ${CHART_VERSION}|version: ${NEW_CHART_VERSION}|" "$CHART_YAML"
  echo "Chart version bumped: $CHART_VERSION → $NEW_CHART_VERSION"
fi

echo ""
echo "Updated files:"
git -C "$REPO_ROOT" diff --stat
