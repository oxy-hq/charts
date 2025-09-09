#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "Searching for charts under $ROOT/charts"
found=0
exit_code=0
while IFS= read -r chartfile; do
  found=1
  chartdir="$(dirname "$chartfile")"
  echo "-> Linting chart: $chartdir"
  if ! helm lint "$chartdir"; then
    echo "helm lint failed for $chartdir"
    exit_code=1
  fi
done < <(find charts -name Chart.yaml 2>/dev/null || true)

if [ "$found" -eq 0 ]; then
  echo "No charts found under $ROOT/charts"
  exit 0
fi

exit $exit_code
