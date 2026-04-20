# Changelog

All notable changes to the Slackeel repository are documented here.

## [Unreleased]

### Added

- **Ollama integration probe** — Pre-flight button runs **`POST /v1/chat/completions`** for each manifest model with configurable parallelism (**`SLACKEEL_VERIFY_MAX_PARALLEL`**, default 3); see [`docs/INTEGRATION_VERIFY.md`](docs/INTEGRATION_VERIFY.md).
- **Phoenix Pre-flight** — LiveView at **`/preflight`** ([`server/`](server/)): compares manifest pull sizes to free disk space; **`MIX_ENV=dev`** defaults **`SLACKEEL_PREFLIGHT_METRICS_URL`** to **`telvm-network-agent`** `GET /preflight/metrics` (see [`agents/telvm-network-agent/`](../agents/telvm-network-agent/)); optional Bearer via **`SLACKEEL_PREFLIGHT_METRICS_TOKEN`**; else **`:disksup`** fallback. Documented in [`docs/PREFLIGHT_AND_PR.md`](docs/PREFLIGHT_AND_PR.md).
- **[`docs/PROGRESS.md`](docs/PROGRESS.md)** — summary of repo status; **[`docs/ROADMAP_HOST_METRICS.md`](docs/ROADMAP_HOST_METRICS.md)** — Zig + MCP-shaped host metrics direction.
- **[`scripts/host-inspect/`](scripts/host-inspect/)** — [`host-inspect.ps1`](scripts/host-inspect/host-inspect.ps1), [`host-inspect.sh`](scripts/host-inspect/host-inspect.sh) for memory, disk, Docker `df`.
- **[`manifest/models.json`](manifest/models.json)** — advertised Ollama model ids; **`model_doctor`** (Compose profile **`doctor`**, [`docker/model-doctor/`](docker/model-doctor/)) verifies **`required`** rows against **`GET /v1/models`** inside Docker. Documented in [`docs/OLLAMA.md`](docs/OLLAMA.md).
- Self-contained **Ollama** stack: [`docker-compose.yml`](docker-compose.yml), [`docs/OLLAMA.md`](docs/OLLAMA.md), [`scripts/ollama/smoke-ollama.sh`](scripts/ollama/smoke-ollama.sh), [`scripts/ollama/smoke-ollama.ps1`](scripts/ollama/smoke-ollama.ps1). Full **Pre-flight** integration expects the **`telvm`** monorepo and [`telvm-network-agent`](../agents/telvm-network-agent/).
