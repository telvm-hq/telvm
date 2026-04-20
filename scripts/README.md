# `scripts/` layout

Helper scripts for Telvm. Run from the **repository root** unless a script says otherwise.

| Directory | Contents |
|-----------|----------|
| [`ollama/`](ollama/) | OpenAI-compatible inference smoke (`smoke-ollama.sh` / `.ps1`) — see [docs/utilities-ollama.md](../docs/utilities-ollama.md) |
| [`closed-agent/`](closed-agent/) | Closed-agent egress verification (`verify-closed-agent-egress.sh` / `.ps1`) |
| [`docker/`](docker/) | Host diagnostics (`docker-diagnostics.ps1`) |
| [`lan-host/`](lan-host/) | Ubuntu LAN / inventory / golden profile (see [inventories/lan-host/README.md](../inventories/lan-host/README.md)) |
| [`windows/`](windows/) | Windows PowerShell LAN and connectivity helpers |

The companion container mounts this tree read-only at **`/telvm-scripts`** (see `docker-compose.yml`).
