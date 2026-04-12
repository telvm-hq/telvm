# telvm-closed-codex

Published as **`ghcr.io/<owner>/telvm-closed-codex`** (tags `main`, `<git-sha>`) via [`.github/workflows/publish-telvm-closed-codex.yml`](../../.github/workflows/publish-telvm-closed-codex.yml).

- **CLI:** `@openai/codex` (install version override: build-arg `CODEX_VERSION`).
- **Labels:** See [closed-agent-docker-labels.md](../../docs/closed-agent-docker-labels.md); `telvm.agent.egress=lab_relaxed` for this quick path (no bundled `init-firewall.sh` execution).
- **Secrets:** Do not bake API keys into the image. Use `-e OPENAI_API_KEY=...` or mounted secrets at runtime.

## Local build

From repo root:

```bash
docker build -f images/telvm-closed-codex/Dockerfile -t telvm-closed-codex:local .
```

## Example run

```bash
docker run --rm -it -e OPENAI_API_KEY="$OPENAI_API_KEY" telvm-closed-codex:local codex --help
```

## Upstream submodule

Reference: [`third_party/codex`](../../third_party/codex). For contributor vs secure devcontainer differences, see [internal-claude-code-codex-devcontainers.md](../../docs/internal-claude-code-codex-devcontainers.md).
