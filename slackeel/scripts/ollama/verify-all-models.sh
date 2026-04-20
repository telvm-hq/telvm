#!/usr/bin/env bash
# Deterministic manifest-wide Ollama verification (parallel + retries).
# See docs/INTEGRATION_VERIFY.md
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../../server" && pwd)"
cd "$SERVER_DIR"
exec mix slackeel.verify_ollama "$@"
