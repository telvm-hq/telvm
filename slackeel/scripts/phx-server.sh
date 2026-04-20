#!/usr/bin/env sh
# Run Slackeel Phoenix from the correct directory (slackeel/server).
# Dev port is fixed in config/dev.exs (:4020).
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT/server"
exec mix phx.server
