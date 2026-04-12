# Multi-stage: static Linux dirteel binary (same pattern as retardeel).
# From repo root:
#   docker build -f agents/dirteel/Dockerfile -t dirteel:build .
#   docker create --name dirteel-tmp dirteel:build
#   docker cp dirteel-tmp:/out/dirteel ./dirteel-linux-amd64 && docker rm dirteel-tmp

FROM alpine:3.20 AS build
RUN apk add --no-cache curl tar xz
RUN curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz \
    | tar -xJ -C /opt \
 && ln -s /opt/zig-linux-x86_64-0.13.0/zig /usr/local/bin/zig

WORKDIR /src
COPY agents/dirteel /src
RUN mkdir -p /out \
 && zig build -Doptimize=ReleaseSafe \
 && cp zig-out/bin/dirteel /out/dirteel

FROM scratch
COPY --from=build /out/dirteel /dirteel
