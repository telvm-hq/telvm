#!/usr/bin/env bash
# Run mix slackeel.verify_ollama from the Phoenix app (slackeel/server).
# Usage from slackeel/: ./verify-ollama.sh [--model "qwen2.5:0.5b"] ...
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT/server"
exec mix slackeel.verify_ollama "$@"
