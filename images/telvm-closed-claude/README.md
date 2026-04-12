# telvm-closed-claude

Published as **`ghcr.io/<owner>/telvm-closed-claude`** (tags `main`, `<git-sha>`) via [`.github/workflows/publish-telvm-closed-claude.yml`](../../.github/workflows/publish-telvm-closed-claude.yml).

- **CLI:** `@anthropic-ai/claude-code` (install version override: build-arg `CLAUDE_CODE_VERSION`).
- **Labels:** See [closed-agent-docker-labels.md](../../docs/closed-agent-docker-labels.md); this image uses `telvm.agent.egress=lab_relaxed` (no in-container iptables allowlist in this quick path).
- **Secrets:** Do not bake `ANTHROPIC_API_KEY` into the image. Pass at runtime, e.g. `-e ANTHROPIC_API_KEY=...` or a mounted env file.

## Local build

From repo root (after `git submodule update --init --recursive` if you need upstream reference under `third_party/`):

```bash
docker build -f images/telvm-closed-claude/Dockerfile -t telvm-closed-claude:local .
```

## Example run

```bash
docker run --rm -it -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" telvm-closed-claude:local claude --help
```

Default `CMD` is `sleep infinity` so the container stays up without a key for Warm-style discovery.

## Upstream submodule

Source-of-truth for upstream devcontainer / firewall scripts: [`third_party/claude-code`](../../third_party/claude-code). Pin updates: [closed-agent-upstream-submodule-policy.md](../../docs/closed-agent-upstream-submodule-policy.md).
