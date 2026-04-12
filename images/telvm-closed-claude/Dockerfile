# telvm-published image: Anthropic Claude Code CLI on Debian bookworm (Node 22).
# Upstream reference tree: third_party/claude-code (git submodule). This Dockerfile
# does not COPY upstream devcontainer wholesale; it installs the published npm CLI.
# Build from repo root: docker build -f images/telvm-closed-claude/Dockerfile .

FROM node:22-bookworm

ARG CLAUDE_CODE_VERSION=latest

LABEL org.opencontainers.image.title="telvm-closed-claude"
LABEL org.opencontainers.image.description="Claude Code CLI for telvm closed-agent workflows (no API key in image)"
LABEL org.opencontainers.image.source="https://github.com/telvm-hq/telvm"
LABEL telvm.agent="closed"
LABEL telvm.agent.vendor="anthropic"
LABEL telvm.agent.product="claude-code"
LABEL telvm.agent.egress="lab_relaxed"
LABEL telvm.managed_by="telvm-build"

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates git \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
  && npm cache clean --force

WORKDIR /workspace

# Secret lifecycle: no ANTHROPIC_API_KEY in image. Operator injects at runtime.
# Idle process keeps container up for `docker run` / Compose without credentials.
CMD ["sleep", "infinity"]
