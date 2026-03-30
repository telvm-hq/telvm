#!/bin/sh
set -e
cd /app
mix deps.get
mix assets.setup
mix assets.build
mix ecto.create --quiet || true
mix ecto.migrate --quiet
exec mix phx.server
