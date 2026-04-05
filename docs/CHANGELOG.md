# Changelog

All notable changes to this project are documented here and in [GitHub Releases](https://github.com/telvm-hq/telvm/releases).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where it applies to tagged releases.

## [Unreleased]

### Agent setup (optional CPU inference)

- **Compose:** optional **Ollama**, one-shot **ollama_pull**, and **Goose** CLI image; companion env **`TELVM_INFERENCE_BASE_URL`**, **`TELVM_AGENT_DEFAULT_MODEL`** (see [quickstart](quickstart.md)).
- **LiveView (`/agent`):** OpenAI-compatible model list + **Model** tab chat ([`Companion.InferenceChat`](../companion/lib/companion/inference_chat.ex)), **Goose** tab via Engine **exec** ([`Companion.GooseRuntime`](../companion/lib/companion/goose_runtime.ex)), [`Companion.GooseHealth`](../companion/lib/companion/goose_health.ex) probes, operator diagnostics (logs / restart). Default tab **Goose**; auto-probe Ollama on load; Model chat completion runs **asynchronously** so the UI can render before the HTTP reply finishes.
- **Goose image:** Debian **`libgomp1`** for the upstream Linux binary; build-time **`goose --version`** check.

No breaking changes to the **Machine API** (`/telvm/api`) or to **ProxyPlug** / lab **Verify** flows.

## [1.1.0] — 2026-03-31

Major companion **operator UI** refresh. Full narrative for maintainers and GitHub Releases: [`releases/v1.1.0.md`](releases/v1.1.0.md).

### Operator UI (dashboard)

- **Navigation:** Distinct **Pre-flight** (`/health`), **Warm assets** (`/warm`), and **Machines** (`/machines`) with a shared console shell layout and consistent top nav.
- **Mission / lab layout:** Stable **preview** column and fixed preview frame height; tighter headers; shared max content width across tabs (`telvm-console-shell`).
- **Theming:** **Light** and **dark** shell modes and selectable **accent** colors (for operational contrast and branding).
- **Lab catalog:** Five **Docker Hub** stock labs with **text + Heroicon** chips—**Node + Bun**, **Go**, **Elixir + mix**, **python + uv**, **C + gcc**; catalog logo image assets removed in favor of labels only.

No breaking changes to the **Machine API** (`/telvm/api`) in this release; see [`agent-api.md`](agent-api.md) for the HTTP surface.

## [0.1.0] — 2026-03-29

Initial public OSS snapshot. Summary: [`releases/v0.1.0.md`](releases/v0.1.0.md). HTTP automation surface: [`agent-api.md`](agent-api.md).

### Elixir / OTP and transport

- **Finch + Unix socket:** Docker Engine access uses **Finch** with a dedicated **`{:http, {:local, /var/run/docker.sock}}`** pool (**HTTP/1**), alongside the default pool used for **ProxyPlug** upstreams to containers on the bridge ([`application.ex`](../companion/lib/companion/application.ex)).
- **Supervision:** top-level **`Companion.Supervisor`** is **`:rest_for_one`**; VM manager pre-flight runners start under a **`DynamicSupervisor`** on demand.
- **Real-time fan-out:** **Phoenix PubSub** feeds **LiveView** and the **`/telvm/api/stream`** SSE loop ([`plumbing.md`](plumbing.md)).

Docs: [Architecture — OTP, Finch, Docker socket](ARCHITECTURE.md#otp-finch-and-the-docker-unix-socket), [Why Elixir / OTP](ARCHITECTURE.md#why-elixir--otp), [Plumbing](plumbing.md).

[1.1.0]: https://github.com/telvm-hq/telvm/releases/tag/v1.1.0
[0.1.0]: https://github.com/telvm-hq/telvm/releases/tag/v0.1.0
