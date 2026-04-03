# TELVM agent API (FYI)

Human-readable notes for the HTTP API under `/telvm/api/`.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/telvm/api/machines` | List lab containers |
| `GET` | `/telvm/api/machines/:id/stats` | One-shot cgroup stats (`?raw=1` for full Engine JSON) |
| `GET` | `/telvm/api/machines/:id/logs` | One-shot stdout/stderr tail (`?tail=` lines, default 500, max 10_000). Raw text may include secrets from the container. |
| `GET` | `/telvm/api/machines/:id` | Inspect one container |
| `POST` | `/telvm/api/machines` | Create and start a machine |
| `POST` | `/telvm/api/machines/:id/exec` | Run a command inside a container |
| `POST` | `/telvm/api/machines/:id/restart` | Restart container in place (optional `?t=` stop grace seconds, default 10, max 300) |
| `POST` | `/telvm/api/machines/:id/pause` | Pause all processes (cgroup freeze); not a substitute for restart |
| `POST` | `/telvm/api/machines/:id/unpause` | Resume after pause |
| `DELETE` | `/telvm/api/machines/:id` | Stop and remove |
| `GET` | `/telvm/api/stream` | SSE stream of lifecycle events |

Responses are JSON. This companion serves on the same origin as the operator UI (`/health`, `/machines`).

### Stats

- Default response shape trims Engine output to `cpu_percent`, `memory_usage_bytes`, `memory_limit_bytes`, `network_rx_bytes`, and `network_tx_bytes` (summed over interfaces).
- `GET .../stats?raw=1` returns the raw Engine stats object under `stats` for power users and agents that parse fields themselves.

### Restart vs pause

- **Restart** stops and starts the same container (same ID, same writable layer). Use when a dev server or process must fully restart to pick up changes.
- **Pause** suspends the cgroup; it does **not** reload processes or guarantee UI refresh. Use to freeze a lab without deleting it.

## Trust model

v0 assumes a trusted local network — no authentication on these routes.

Container logs are raw Engine output: they may include environment variables, tokens, or other secrets emitted by processes. Treat log responses like sensitive data.

## Engine API roadmap (not exposed yet)

These Docker Engine capabilities are **not** fully wrapped by `Companion.Docker` today; approximate priority if we extend the control plane:

1. **Container log streaming** — `follow=true` / SSE / WebSocket tail (the HTTP API and UI expose one-shot logs only).
2. **Engine events** — `GET /events` long poll or stream (partially overlaps companion PubSub + `/telvm/api/stream`).
3. **Networks / volumes (read-only)** — introspection only; careful with path and driver leakage on shared hosts.

One-shot logs (`GET /telvm/api/machines/:id/logs` and Warm assets preview) map to Engine `GET /containers/{id}/logs` with multiplexed stdout/stderr decoded to plain text.
