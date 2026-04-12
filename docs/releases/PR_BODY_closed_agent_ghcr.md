## Summary

Adds **pinned git submodules** for upstream [anthropics/claude-code](https://github.com/anthropics/claude-code) and [openai/codex](https://github.com/openai/codex), **two telvm-owned Docker images** (Claude Code and Codex CLIs on Node 22 bookworm) with the **closed-agent `LABEL` contract**, **GHCR publish workflows**, and **harness documentation** (default Docker NAT egress vs in-container `init-firewall` vs Windows `telvm-network-agent`).

## What ships

- `third_party/claude-code`, `third_party/codex` — submodule pointers; pins recorded in `docs/closed-agent-upstream-submodule-policy.md`.
- `images/telvm-closed-claude`, `images/telvm-closed-codex` — npm global install, **`telvm.agent.*` labels**, **`CMD sleep infinity`** until operators inject API keys at runtime.
- `.github/workflows/publish-telvm-closed-{claude,codex}.yml` — push to `ghcr.io/<owner>/telvm-closed-*` (`main` + `${{ github.sha }}`), checkout **with submodules**, `workflow_dispatch` enabled.
- Docs: harness contract, wireframe, docker labels, integration test matrix, submodule policy, internal devcontainer note, CONTRIBUTING submodule clone, quickstart pull/build, CHANGELOG, ARCHITECTURE.

## How to verify locally

```bash
git submodule update --init --recursive
docker build -f images/telvm-closed-claude/Dockerfile -t telvm-closed-claude:local .
docker build -f images/telvm-closed-codex/Dockerfile -t telvm-closed-codex:local .
```

After merge: confirm Actions publish succeeds, then `docker pull ghcr.io/<org>/telvm-closed-claude:main` (same for codex).

## Follow-ups (not in this PR)

- Compose services or runbook for `claude` / `codex` with env-injected keys.
- Warm assets classification for `telvm.agent=closed` rows.
- Optional **strict** image variant using upstream `init-firewall` + `NET_ADMIN`.
