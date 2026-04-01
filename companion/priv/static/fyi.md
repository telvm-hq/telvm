# TELVM agent API (FYI)

Human-readable notes for the HTTP API under `/telvm/api/`.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/telvm/api/machines` | List lab containers |
| `GET` | `/telvm/api/machines/:id` | Inspect one container |
| `POST` | `/telvm/api/machines` | Create and start a machine |
| `POST` | `/telvm/api/machines/:id/exec` | Run a command inside a container |
| `DELETE` | `/telvm/api/machines/:id` | Stop and remove |
| `GET` | `/telvm/api/stream` | SSE stream of lifecycle events |

Responses are JSON. This companion serves on the same origin as the operator UI (`/health`, `/machines`).

## Trust model

v0 assumes a trusted local network — no authentication on these routes.
