#!/usr/bin/env sh
# Start only the Ollama container for local Slackeel Phoenix development.
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec docker compose -f docker-compose.ollama-dev.yml up -d
