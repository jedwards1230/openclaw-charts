#!/bin/bash
# Stop hook: Block if chart content changed but Chart.yaml version wasn't bumped.
# Mirrors CI version-check.yml but catches issues before commit/push.
set -euo pipefail

INPUT=$(cat)

# Prevent infinite loops — skip if we already blocked once
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0
fi

# Only check if there are uncommitted changes
MODIFIED=$(git diff --name-only HEAD 2>/dev/null || true)
[ -z "$MODIFIED" ] && exit 0

# Check if chart content (templates, values, crds) was modified
CHART_CHANGED=$(echo "$MODIFIED" | grep -E '(charts/.*/templates/|charts/.*/values|charts/.*/crds/)' | head -1 || true)
[ -z "$CHART_CHANGED" ] && exit 0

# Chart content changed — verify Chart.yaml version was also bumped
VERSION_BUMPED=$(git diff HEAD -- 'charts/*/Chart.yaml' 2>/dev/null | grep '^[+-]version:' | head -1 || true)
if [ -z "$VERSION_BUMPED" ]; then
  echo "Chart content changed but Chart.yaml version was not bumped. Run: ./scripts/bump-version.sh <ver> --bump-chart" >&2
  exit 2
fi

exit 0
