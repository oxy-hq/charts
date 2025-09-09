#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Ensure helm-unittest plugin is installed
if ! helm plugin list 2>/dev/null | grep -q helm-unittest; then
  echo "Installing helm-unittest plugin"
  helm plugin install https://github.com/quintush/helm-unittest || true
fi

# Run lint first
bash scripts/lint.sh

# Run helm unittest across charts
found=0
exit_code=0
while IFS= read -r chartfile; do
  found=1
  chartdir="$(dirname "$chartfile")"
  echo "-> Running helm unittest for $chartdir"
  if ! helm unittest "$chartdir"; then
    echo "helm unittest failed for $chartdir"
    exit_code=1
  fi
done < <(find charts -name Chart.yaml 2>/dev/null || true)

if [ "$found" -eq 0 ]; then
  echo "No charts found under $ROOT/charts"
  exit 0
fi

exit $exit_code
