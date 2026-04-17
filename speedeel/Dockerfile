# Dev image for speedeel: bind-mount ./speedeel at /app (same pattern as repo-root Dockerfile for companion).
FROM hexpm/elixir:1.17.3-erlang-27.3.2-debian-bookworm-20250317-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    nodejs \
    npm \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=dev \
    LANG=C.UTF-8

COPY speedeel/mix.exs speedeel/mix.lock ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get

COPY speedeel/ ./
COPY docker/speedeel-entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 4010

ENTRYPOINT ["/entrypoint.sh"]
