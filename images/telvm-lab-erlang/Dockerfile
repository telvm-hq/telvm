# Telvm certified lab: Erlang + Cowboy. GET / -> JSON 200 on port 3333.
FROM erlang:27-alpine

RUN apk add --no-cache curl \
  && curl -fsSL -o /usr/local/bin/rebar3 https://github.com/erlang/rebar3/releases/download/3.24.0/rebar3 \
  && chmod +x /usr/local/bin/rebar3

WORKDIR /app

COPY rebar.config .
COPY src src

RUN rebar3 release

RUN adduser -D -u 10001 labuser

USER labuser

WORKDIR /app/_build/default/rel/telvm_lab

ENV HOME=/app/_build/default/rel/telvm_lab
EXPOSE 3333

CMD ["bin/telvm_lab", "foreground"]
