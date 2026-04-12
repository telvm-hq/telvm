# telvm-published image: OpenAI Codex CLI on Debian bookworm (Node 22).
# Upstream reference tree: third_party/codex (git submodule). This Dockerfile installs
# the published npm CLI; it does not mirror the full secure devcontainer (init-firewall).
# Build from repo root: docker build -f images/telvm-closed-codex/Dockerfile .

FROM node:22-bookworm

ARG CODEX_VERSION=latest

LABEL org.opencontainers.image.title="telvm-closed-codex"
LABEL org.opencontainers.image.description="OpenAI Codex CLI for telvm closed-agent workflows (no API key in image)"
LABEL org.opencontainers.image.source="https://github.com/telvm-hq/telvm"
LABEL telvm.agent="closed"
LABEL telvm.agent.vendor="openai"
LABEL telvm.agent.product="codex"
LABEL telvm.agent.egress="lab_relaxed"
LABEL telvm.managed_by="telvm-build"

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates git \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable \
  && npm install -g @openai/codex@${CODEX_VERSION} \
  && npm cache clean --force

WORKDIR /workspace

# Secret lifecycle: no OPENAI_API_KEY in image. Operator injects at runtime.
CMD ["sleep", "infinity"]
