# Multi-stage build: produces a static Linux binary from the Zig source.
# Usage:
#   docker build -t retardeel:latest .
#   docker create --name retardeel-tmp retardeel:latest
#   docker cp retardeel-tmp:/retardeel ./retardeel
#   docker rm retardeel-tmp

FROM alpine:3.20 AS build

RUN apk add --no-cache curl tar xz
RUN curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz \
    | tar -xJ -C /opt \
 && ln -s /opt/zig-linux-x86_64-0.13.0/zig /usr/local/bin/zig

COPY . /src
WORKDIR /src
RUN zig build -Doptimize=ReleaseSafe

FROM scratch
COPY --from=build /src/zig-out/bin/retardeel /retardeel
ENTRYPOINT ["/retardeel"]
