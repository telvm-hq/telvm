# Telvm certified lab: C + libmicrohttpd. GET / -> JSON 200 on port 3333.
FROM alpine:3.21 AS build

RUN apk add --no-cache gcc musl-dev libmicrohttpd-dev

WORKDIR /src
COPY main.c .
RUN gcc -o /lab main.c -lmicrohttpd

FROM alpine:3.21

RUN apk add --no-cache libmicrohttpd \
  && adduser -D -u 10001 labuser

COPY --from=build /lab /lab

USER labuser

EXPOSE 3333

CMD ["/lab"]
