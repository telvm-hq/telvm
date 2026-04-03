# Telvm certified lab: Phoenix + Bandit. GET / -> JSON 200 on port 3333.
FROM hexpm/elixir:1.18.2-erlang-27.2-alpine-3.21.2 AS build

WORKDIR /app
RUN apk add --no-cache build-base git

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
COPY lib lib

RUN mix deps.get --only prod \
  && mix deps.compile \
  && mix release

FROM alpine:3.21 AS runtime

RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs

RUN adduser -D -u 10001 labuser

WORKDIR /app

COPY --from=build /app/_build/prod/rel/telvm_lab ./

USER labuser

ENV PHX_SERVER=true
ENV HOME=/app
EXPOSE 3333

CMD ["/app/bin/telvm_lab", "start"]
