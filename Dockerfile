# Development image: Elixir toolchain + Node (esbuild/tailwind) + Postgres client.
# Source is bind-mounted from the host; named volumes hold deps/_build.
FROM hexpm/elixir:1.17.3-erlang-27.3.2-debian-bookworm-20250317-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    postgresql-client \
    nodejs \
    npm \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=dev \
    LANG=C.UTF-8

COPY companion/mix.exs companion/mix.lock ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get

COPY companion/ ./
COPY docker/companion-entrypoint.sh /entrypoint.sh
# Windows checkouts may use CRLF; kernel then reports "no such file or directory" for the shebang.
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 4000

ENTRYPOINT ["/entrypoint.sh"]
