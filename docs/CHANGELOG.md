# Changelog

All notable changes to this project are documented here and in [GitHub Releases](https://github.com/telvm-hq/telvm/releases).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where it applies to tagged releases.

## [Unreleased]

### Closed-inference agents + PowerShell network harness (docs)

- **Docs:** [closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md) (three-plane contract, egress tiers, secrets, bridge vs LAN attach), [closed-agent-provision-tab-wireframe.md](closed-agent-provision-tab-wireframe.md) (new tab + Warm assets + Pre-flight links), [closed-agent-docker-labels.md](closed-agent-docker-labels.md) (container labels and naming), [closed-agent-integration-test-matrix.md](closed-agent-integration-test-matrix.md) (manual checklist), [closed-agent-upstream-submodule-policy.md](closed-agent-upstream-submodule-policy.md) (submodule decision and pin process). Cross-links from [internal-claude-code-codex-devcontainers.md](internal-claude-code-codex-devcontainers.md) and [telvm-network-agent README](../agents/telvm-network-agent/README.md).

### Closed-agent GHCR images + upstream submodules

- **Submodules:** `third_party/claude-code` (anthropics/claude-code), `third_party/codex` (openai/codex), with pins recorded in [closed-agent-upstream-submodule-policy.md](closed-agent-upstream-submodule-policy.md).
- **Images:** [images/telvm-closed-claude](../images/telvm-closed-claude/README.md), [images/telvm-closed-codex](../images/telvm-closed-codex/README.md) — Node 22 bookworm, npm CLIs, `telvm.*` labels, default `CMD sleep infinity` (no API keys in image).
- **CI:** [publish-telvm-closed-claude.yml](../.github/workflows/publish-telvm-closed-claude.yml), [publish-telvm-closed-codex.yml](../.github/workflows/publish-telvm-closed-codex.yml) → `ghcr.io/<owner>/telvm-closed-{claude,codex}`.
- **Docs:** [CONTRIBUTING](CONTRIBUTING.md) submodule clone note; [quickstart](quickstart.md) pull/build pointers; harness contract section on default egress vs `init-firewall`.

### Agent setup (optional CPU inference)

- **Compose:** optional **Ollama**, one-shot **ollama_pull**, and **Goose** CLI image; companion env **`TELVM_INFERENCE_BASE_URL`**, **`TELVM_AGENT_DEFAULT_MODEL`** (see [quickstart](quickstart.md)).
- **LiveView (`/agent`):** OpenAI-compatible model list + **Model** tab chat ([`Companion.InferenceChat`](../companion/lib/companion/inference_chat.ex)), **Goose** tab via Engine **exec** ([`Companion.GooseRuntime`](../companion/lib/companion/goose_runtime.ex)), [`Companion.GooseHealth`](../companion/lib/companion/goose_health.ex) probes, operator diagnostics (logs / restart). Default tab **Goose**; auto-probe Ollama on load; Model chat completion runs **asynchronously** so the UI can render before the HTTP reply finishes.
- **Goose image:** Debian **`libgomp1`** for the upstream Linux binary; build-time **`goose --version`** check.

No breaking changes to the **Machine API** (`/telvm/api`) or to **ProxyPlug** / lab **Verify** flows.

### retardeel -- Zig filesystem agent (v0.1.0) → telvm-agent nervous system

- **New agent:** `agents/retardeel/` -- static Zig binary for jailed filesystem operations (health, workspace discovery, stat, read, write, list) with Bearer auth and path jailing.
- **Dockerfile:** multi-stage Alpine + Zig 0.13 build; no host toolchain required.
- **RetardeelVerifier:** companion GenServer that builds the image, injects the binary into a sandbox container, and runs 14 endpoint checks (TDD-style, manual trigger from Agent setup).
- **Agent setup UI:** "Verify retardeel" button with PASS/FAIL/SKIP results panel.
- **Infra:** Docker CLI added to companion image; `./agents` mounted read-only into the companion container.

### portscout + proctop -- guest-side telemetry (v0.2.0)

- **`GET /v1/ports` (portscout):** parses `/proc/net/tcp` and `/proc/net/tcp6` to discover all listening ports inside a container with protocol info. No configuration required -- services light up automatically.
- **`GET /v1/proc` (proctop):** reads `/proc/loadavg`, `/proc/meminfo`, and `/proc/[pid]/stat` to return load averages, memory usage, and top processes sorted by CPU time with RSS.
- **`TelvmAgentPoller` GenServer:** periodic poller that discovers sandbox containers, probes `/health`, `/v1/ports`, and `/v1/proc`, and broadcasts snapshots via PubSub.
- **Warm Assets dashboard:** per-container "telvm-agent" panel showing discovered services (port badges), memory usage bar, load averages, and top-5 process table.
- **Verifier expansion:** 11 → 14 checks: ports endpoint, proc telemetry, and port discovery (spawns a Node.js listener and verifies portscout finds it).

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
