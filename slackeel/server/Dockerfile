# Phoenix release for Slackeel — use with slackeel/docker-compose.yml (Ollama + manifest mount).
FROM hexpm/elixir:1.18.4-erlang-27.3.3-alpine-3.21.3 AS build

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# `config/runtime.exs` runs for every Mix task in prod and requires DATABASE_URL.
# Image build has no Compose network yet — dummy URL (no connection during deps/compile).
# Override at container runtime via Compose `DATABASE_URL`.
ARG DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/postgres
ENV DATABASE_URL=$DATABASE_URL

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod && mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile && mix assets.deploy && mix release

FROM alpine:3.21.3 AS app

RUN apk add --no-cache openssl ncurses-libs libstdc++ libgcc

WORKDIR /app

RUN addgroup -S slackeel && adduser -S slackeel -G slackeel

COPY --from=build /app/_build/prod/rel/slackeel ./

USER slackeel

ENV HOME=/app
EXPOSE 4020

ENTRYPOINT ["/app/bin/slackeel"]
CMD ["start"]
