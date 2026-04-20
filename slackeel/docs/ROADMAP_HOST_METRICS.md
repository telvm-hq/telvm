# Roadmap — host metrics (Zig + MCP-shaped)

## Today

- **[scripts/host-inspect/](../scripts/host-inspect/)** — small **PowerShell** and **POSIX shell** scripts that print:
  - rough **memory** and **disk** headroom
  - **`docker info`** / **`docker system df`** snippets when the Docker CLI is available  
  No daemon; run manually when sizing Ollama pulls or debugging compose.

## Direction (not implemented)

**Goal:** a **single static binary** (prefer **Zig** for cross-compilation to Windows, Linux, and optionally macOS) that can:

- Report **RAM**, **CPU load**, **disk** on the host.
- Call the **Docker Engine API** or wrap **`docker`** CLI for **running containers**, **image/volume** usage, and **compose project** hints where feasible.
- Expose the same facts through a small **local-only HTTP** or **stdio JSON** interface suitable for an **MCP server** adapter in the IDE—so agents can query “do we have enough RAM for `mistral:7b`?” without shelling ad hoc.

**Constraints to preserve:**

- **Opt-in** and **local** by default (no telemetry; bind to loopback).
- **Read-mostly** — no stopping containers unless explicitly requested later.

**Steps (future PRs):**

1. Scaffold `zig build` project under e.g. `host-metrics/` with subcommands `summary`, `json`.
2. Replace or wrap the shell scripts as thin launchers during transition.
3. Optional **MCP** packaging: stdio server mapping tool calls → Zig binary output.

This document is **normative intent** only; implementation may differ after spike.
