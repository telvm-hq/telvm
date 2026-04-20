# Slackeel — progress summary

Snapshot of what exists in the **`telvm`** tree under **`slackeel/`** (documentation, local inference, and a baseline Phoenix app).

## Done

| Area | Outcome |
|------|---------|
| **Vision** | Self-hosted team chat + local OSS inference; LiveView-first architecture in [ARCHITECTURE.md](ARCHITECTURE.md). |
| **Model planning** | [MODEL_CATALOG.md](MODEL_CATALOG.md): five families, disk estimates; [manifest/models.json](../manifest/models.json) machine-readable list. |
| **Ollama stack** | [docker-compose.yml](../docker-compose.yml): pinned `ollama/ollama`, `ollama_pull`, **`model_doctor`** (profile `doctor`). |
| **HTTP smoke** | [`scripts/ollama/`](../scripts/ollama/) host scripts; [OLLAMA.md](OLLAMA.md) procedures. |
| **Manifest doctor** | Dockerized check vs `GET /v1/models`; default `OLLAMA_HOST=host.docker.internal:11434` when sharing port with Telvm; CRLF-safe [`docker/model-doctor/`](../docker/model-doctor/). |
| **Host resource peek** | [`scripts/host-inspect/`](../scripts/host-inspect/) quick PowerShell / shell summaries (memory, disk, Docker). |
| **Phoenix + Pre-flight** | [`server/`](../server/) LiveView at **`/preflight`**; dev default **`GET`** to **`../../agents/telvm-network-agent`** `GET /preflight/metrics` for disk + network JSON; falls back to `:disksup`. See [PREFLIGHT_AND_PR.md](PREFLIGHT_AND_PR.md). |
| **Roadmap** | [ROADMAP_HOST_METRICS.md](ROADMAP_HOST_METRICS.md): Zig binary + richer host metrics (future). |

## In flight / not in repo yet

- Ecto persistence, chat channels, org bridge / tunnels — see [ARCHITECTURE.md](ARCHITECTURE.md).

## Relation to Telvm

**Clone [`telvm-hq/telvm`](https://github.com/telvm-hq/telvm)** for the supported path: Slackeel **`server/`** plus **`agents/telvm-network-agent/`** on the Windows gateway host. Pre-flight is designed around that layout.
