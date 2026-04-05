# Goose CLI — pinned release; Ollama via OLLAMA_HOST on the Compose network.
# Interactive sessions: docker compose exec -it goose goose session
FROM debian:bookworm-slim

ARG GOOSE_VERSION=1.29.1
ARG TARGETARCH

# Upstream Linux Goose binary dynamically links libgomp (OpenMP); bookworm-slim does not ship it by default.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl bzip2 libgomp1 \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  case "$TARGETARCH" in \
    amd64) ARCH=x86_64 ;; \
    arm64) ARCH=aarch64 ;; \
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://github.com/block/goose/releases/download/v${GOOSE_VERSION}/goose-${ARCH}-unknown-linux-gnu.tar.bz2" -o /tmp/goose.tar.bz2; \
  tar -xjf /tmp/goose.tar.bz2 -C /usr/local/bin; \
  test -x /usr/local/bin/goose; \
  rm /tmp/goose.tar.bz2; \
  /usr/local/bin/goose --version

ENV PATH="/usr/local/bin:${PATH}"

CMD ["sleep", "infinity"]
