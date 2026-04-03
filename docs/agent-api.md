# Machine API (agents and automation)

Base URL (default dev): **`http://localhost:4000/telvm/api`**

The companion exposes a **thin HTTP layer** over Docker Engine for **machines** (labeled lab containers): list, create, exec, delete, plus a **live event stream**. Use it from **Cursor**, other agent runtimes, **`curl`**, or any HTTP client. telvm does **not** bundle an LLM.

## Model Context Protocol (MCP)

The repository includes a **reference MCP server** ([`mcp/`](../mcp/)) that exposes the same operations as **tools** (stdio → HTTP to this API). It adds **no** duplicate business logic in Phoenix — only HTTP forwarding. Setup for **Cursor**: [mcp-cursor.md](mcp-cursor.md).

## Security and scope (v0.1.0)

- **No authentication** — intended for **local** use with **trusted networks** only.
- **Local-first** — not a multi-tenant cloud control plane.

## REST endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/telvm/api/machines` | List warm lab containers (label `telvm.vm_manager_lab=true`). |
| `GET` | `/telvm/api/machines/:id` | Single machine detail. |
| `POST` | `/telvm/api/machines` | Create and start a lab container (optional JSON: `image`, `workspace`, `cmd`, `use_image_cmd`). |
| `POST` | `/telvm/api/machines/:id/exec` | Run a command inside the container. Body: `cmd` (non-empty list of strings), optional `workdir`. |
| `DELETE` | `/telvm/api/machines/:id` | Stop and remove the container. |

JSON responses for machines include **`proxy_urls`**: ready-made **`http://localhost:4000/app/<name>/port/<n>/`** URLs so agents can hit services inside containers without opening a browser.

## Live stream: Server-Sent Events

`GET /telvm/api/stream` — **`text/event-stream`**. Subscribe with any SSE client (`curl -N`, browser `EventSource`, etc.).

Periodic **`machines_snapshot`** events (about every 5s) carry the current machine list. Additional event types reflect UI-driven flows (PubSub-backed). For which topics reach **only LiveView** vs **SSE** as well, see [Plumbing](plumbing.md).

| Event | Meaning |
|-------|---------|
| `machines_snapshot` | JSON payload with `machines` array. |
| `soak_session` | Soak monitor session phase (or clear when `phase` is null). |
| `soak_done` | Soak run finished; includes `result` and `stability_probes`. |
| `preflight_session` | VM manager pre-flight session phase (or clear). |
| `preflight_done` | Pre-flight finished; includes `result`. |

Keepalive comments are sent on idle (see implementation in [`machine_controller.ex`](../companion/lib/companion_web/machine_controller.ex)).

## Protocol: today and later

- **Today:** **HTTP** — JSON request/response for CRUD and exec, **SSE** for streaming updates.
- **Later:** A **WebSocket** channel for agents is plausible for lower-latency bidirectional control; it is **not** part of the v0.1.0 surface. Treat anything beyond documented HTTP + SSE as **not shipped** until noted in the changelog.

## See also

- [MCP + Cursor](mcp-cursor.md) — configure the telvm MCP server for IDE agents.
- [Plumbing](plumbing.md) — PubSub, operator UI vs SSE, `machines_snapshot` vs Docker pull.
- [Quick start](quickstart.md) — run Compose, operator UI, tests.
- [Architecture](ARCHITECTURE.md) — ProxyPlug, router order, Docker adapter, tests.
