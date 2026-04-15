#!/usr/bin/env bash
# Run morayeel run.mjs. Default: headless. Pass --headed for a visible Chromium window (local host).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MORAYEEL_HEADLESS="${MORAYEEL_HEADLESS:-1}"
filtered=()
for arg in "$@"; do
  if [[ "$arg" == "--headed" ]]; then
    export MORAYEEL_HEADLESS=0
  else
    filtered+=("$arg")
  fi
done
exec node "$ROOT/run.mjs" "${filtered[@]}"
