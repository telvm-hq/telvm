#!/bin/sh
set -e
cd /app
mix deps.get
# Bind-mount replaces /app with host sources, but _build often lives on a named volume with *stale* .beam
# files from an older compile (e.g. old Mix.Tasks.Speedeel.Npm). Force recompile so tasks match the mount.
mix compile --force
mix assets.setup
mix assets.build
exec mix phx.server
