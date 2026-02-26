#!/bin/bash
# Stop hook: Run helm lint on modified charts before allowing Claude to stop.
set -euo pipefail

INPUT=$(cat)

# Prevent infinite loops
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0
fi

# Only check if there are uncommitted changes to chart files
MODIFIED=$(git diff --name-only HEAD 2>/dev/null || true)
[ -z "$MODIFIED" ] && exit 0

CHART_CHANGED=$(echo "$MODIFIED" | grep '^charts/' | head -1 || true)
[ -z "$CHART_CHANGED" ] && exit 0

# Lint all value profiles
FAILED=0

for values_file in "" "-f charts/openclaw/values-development.yaml" "-f charts/openclaw/values-production.yaml"; do
  RESULT=$(helm lint charts/openclaw/ $values_file 2>&1)
  if [ $? -ne 0 ]; then
    echo "helm lint failed${values_file:+ with $values_file}:" >&2
    echo "$RESULT" >&2
    FAILED=1
  fi
done

if [ $FAILED -eq 1 ]; then
  exit 2
fi

exit 0
