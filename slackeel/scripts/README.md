# Slackeel `scripts/`

| Script | Purpose |
|--------|---------|
| [ollama-dev-up.ps1](ollama-dev-up.ps1) / [ollama-dev-up.sh](ollama-dev-up.sh) | Start **only** the Ollama container ([`docker-compose.ollama-dev.yml`](../docker-compose.ollama-dev.yml)) for local Phoenix dev |
| [phx-server.ps1](phx-server.ps1) / [phx-server.sh](phx-server.sh) | `cd` to **`server/`** and run **`mix phx.server`** (dev port **4020** is set in [`server/config/dev.exs`](../server/config/dev.exs)) |

| Directory | Contents |
|-----------|----------|
| [`ollama/`](ollama/) | Host-side inference smoke tests — see [docs/OLLAMA.md](../docs/OLLAMA.md) |
| [`host-inspect/`](host-inspect/) | [host-inspect.ps1](host-inspect/host-inspect.ps1) / [host-inspect.sh](host-inspect/host-inspect.sh) — memory, disk, `docker system df` (see [ROADMAP_HOST_METRICS.md](../docs/ROADMAP_HOST_METRICS.md)); [who-owns-port.ps1](host-inspect/who-owns-port.ps1) — which process (and Docker container) is listening on a port (default **11434** when Ollama/Docker says “port already allocated”) |

Manifest verification runs **in Docker** via Compose service **`model_doctor`** (profile **`doctor`**) — see [docs/OLLAMA.md](../docs/OLLAMA.md) and [`docker/model-doctor/`](../docker/model-doctor/).
