#!/bin/bash
# Hook: Stop
# Fires when Claude finishes a response.
# Use for running linters or tests on changed files.

set -euo pipefail

# Run helm lint if available
for chart_dir in charts/*/; do
  if [ -f "${chart_dir}Chart.yaml" ] && command -v helm &>/dev/null; then
    helm lint "$chart_dir" 2>&1 || true
  fi
done

exit 0
