# telvm

[![CI](https://github.com/telvm-hq/telvm/actions/workflows/ci.yml/badge.svg)](https://github.com/telvm-hq/telvm/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-1.17.3-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)

<p align="center">
  <img src="docs/assets/telvm-mascot.png" alt="Telvm mascot — cybernetic electric eel" width="420" />
</p>

Local-first control plane for AI coding agents inside Docker. This repository ships the Phoenix
**companion** app, Docker-first workflow, reverse proxy to sandbox containers, the **telvm** HTTP API,
and contract tests for Docker and preview routing.

Roadmap items (richer session UX, optional API-key flows, deeper sandbox automation) remain on the
**v0.1.0** track; see **Status** for what is implemented today.

## Integrations and ecosystem (Docker at the center)

Everything in telvm assumes **[Docker](https://www.docker.com/)** (Engine API via Unix socket, Compose networks, bridge DNS). The companion does not replace Docker — it **orchestrates and observes** containers: lifecycle, exec, port discovery, reverse proxy, and an HTTP API for tools. Think of Docker as the **runtime kernel**; telvm is the **control plane** on top.

| Layer | Role | How telvm uses it |
|--------|------|-------------------|
| **Docker Engine** | Containers, images, networks, volumes | Primary integration: `Companion.Docker.HTTP` → Finch → `docker.sock` |
| **Docker Compose** | Local orchestration | `docker compose up` brings Postgres, companion, lab helpers; `companion_test` profile for CI-style tests |
| **Cursor** (and similar IDEs) | Human + agent editing | Point agents at `http://localhost:4000/telvm/api/…` or use the dashboard; no Cursor-specific plugin required |
| **Claude Code** / **GitHub Copilot** / other CLI agents | Terminal-based agents | Same HTTP API + workspace bind mounts — agent-agnostic by design |
| **Any HTTP client** | Scripts, CI, custom agents | `GET /telvm/api/machines`, `POST …/exec`, `GET /telvm/api/stream` (SSE) |

telvm does **not** ship inference APIs (no bundled LLM). It pairs with **whatever model or agent** you already use.

## Quick start (Docker, recommended)

Prerequisites: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or compatible Engine).

```bash
docker compose up --build
```

Open [http://localhost:4000/machines](http://localhost:4000/machines) for the primary **Machines** tab
(container list, lab controls, and **VM manager pre-flight**). The same LiveView shell also exposes
**checks** (`/`) and **topology** (`/topology`). Legacy bookmarks **`/images`**, **`/vm-manager-preflight`**,
and **`/certificate`** **redirect to `/machines`** on full page load. **Explorer** is at
**`/explore/:id`** (full-viewport editor shell).

Platform pre-flight on `/` covers Postgres, Docker socket, **Finch → Docker Engine** (`GET /version` +
labeled container discovery for `vm_node`), ProxyPlug contract, and related rows. The VM manager
pre-flight flow runs a scripted lifecycle (ephemeral lab container + HTTP probe) via
`Companion.VmLifecycle.Runner`. Updates use **Phoenix PubSub** (`preflight:updates` and
`lifecycle:vm_manager_preflight`). Default Compose brings up **db**, **vm_node** (Node 22 +
`telvm.sandbox=true`), and **companion**. The companion container bind-mounts `./companion` and uses named
volumes for `deps`, `_build`, and `assets/node_modules`.

**OTP / dev note:** Phoenix code reloading recompiles modules but does **not** re-run `Application.start/2`.
The runner is started lazily under a `DynamicSupervisor` on first “Run VM manager pre-flight”, so you usually do not
need a restart for LiveView-only edits. If you change **supervised children** in
[`companion/lib/companion/application.ex`](companion/lib/companion/application.ex) (or the runner fails to
start), restart the BEAM: `docker compose restart companion`.

**Run the test suite inside Docker (recommended):**

```bash
docker compose --profile test run --rm companion_test
```

This uses the `test` Compose profile, starts Postgres if needed, sets `MIX_ENV=test` and
`TEST_DATABASE_URL` to reach the `db` service from inside the container.

Optional: copy [`.env.example`](.env.example) to `.env` and adjust; Compose picks up `.env` automatically
for variable substitution when referenced in `docker-compose.yml` (expand as you add services).

### Registry-backed VM manager pre-flight (optional)

The default lab image is **`node:22-alpine`** with an inline HTTP server command.

**From the UI:** on **Machines**, open the **VM manager pre-flight** section, choose **Go HTTP lab**, enter your published ref (optional: set **`TELVM_GO_HTTP_LAB_IMAGE`** in `.env` to pre-fill after refresh), then **Run**. That applies per-run overrides (`use_image_default_cmd` + image) without editing Compose.

**From env only:** set `TELVM_LAB_IMAGE` and **`TELVM_LAB_USE_IMAGE_CMD=1`** so Docker Engine uses the image’s own `CMD` (see [`Companion.VmLifecycle.lab_container_create_attrs/2`](companion/lib/companion/vm_lifecycle.ex)).

1. CI publishes to GHCR via [`.github/workflows/publish-go-http-lab.yml`](.github/workflows/publish-go-http-lab.yml) whenever `images/go-http-lab/**` changes on `main`. Image: **`ghcr.io/telvm-hq/telvm-go-http-lab`** (GitHub lowercases the org for the registry path). Tags include **`main`** and the commit SHA.
2. Pull on any machine with Docker:

   ```bash
   docker pull ghcr.io/telvm-hq/telvm-go-http-lab:main
   ```

3. After the first successful publish, the package appears under the org’s **Packages** and this repo’s **Packages** sidebar on GitHub.
4. For **private** packages, run `docker login ghcr.io` on the host whose Engine backs `docker.sock`.

### Non-interactive Phoenix scaffolding

If you regenerate the app with `mix phx.new`, pass **`--yes`** so Mix does not stop for prompts in CI or
automated shells.

## Local Elixir (optional)

From `companion/`:

```bash
mix setup
mix phx.server
```

You need Postgres matching `config/dev.exs` (or set `DATABASE_URL`). You can also run `mix test` on the
host if Postgres is on `localhost` and you are not using `TEST_DATABASE_URL` / `DATABASE_URL` for test
(see **Test strategy** below).

## Architecture (ASCII)

### Host, Compose, and a single published port

Sandbox workloads are intended to have **no host port bindings**; only the companion publishes **:4000**
and reverse-proxies to containers on the Docker bridge (**ProxyPlug** + **Finch**; Docker Engine via the
same Finch pools and `Companion.Docker.HTTP`).

```
  ┌─────────────────────────────────────────── HOST (Docker Desktop VM on Win/macOS) ───────────────────────────────────────────┐
  │                                                                                                                             │
  │   docker compose                                                                                                            │
  │   ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐ │
  │   │  bridge network (Compose project)                                                                                    │ │
  │   │                                                                                                                      │ │
  │   │   ┌─────────────────────────────┐      ┌──────────────────────────────┐      ┌──────────────────────────────┐       │ │
  │   │   │  companion (Phoenix/Bandit)  │      │  postgres                     │      │  vm_node (Node; telvm labels) │       │ │
  │   │   │  :4000 ───────► host :4000   │      │  :5432 (internal)             │      │  :3333 (internal HTTP echo)   │       │ │
  │   │   │  + docker.sock (read-only)   │      │                               │      │  example “companion VM”      │       │ │
  │   │   └─────────────────────────────┘      └──────────────────────────────┘      └──────────────────────────────┘       │ │
  │   │                                                                                                                      │ │
  │   └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
  │                                                                                                                             │
  └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Preview URL shape (reverse proxy)

Browser traffic to sandboxes uses **`/app/<container_name>/port/<port_number>/…`** (the container name is
the Docker bridge DNS hostname). **`CompanionWeb.ProxyPlug`** runs **before** the router, forwards via
**Finch** to `http://<container>:<port>/…`, and returns **502** if the upstream is unreachable.

```
  Browser
     │
     │  GET /app/<container_name>/port/<port>/…   (port segment optional; default 3000)
     ▼
  CompanionWeb.ProxyPlug  ──►  Finch → http://<container_name>:<port>/…
```

Example segments (see [`CompanionWeb.ProxyPlug.parse_app_path/1`](companion/lib/companion_web/proxy_plug.ex)):

- `["app", "sess_abc"]` → default port **3000**, empty path.
- `["app", "sess_abc", "index.html"]` → default port **3000**, path `index.html`.
- `["app", "sess_abc", "port", "5173", "assets", "a.js"]` → port **5173**, path `assets/a.js`.

### OTP supervision (this commit)

`Companion.Application` uses **`:rest_for_one`** with deliberate ordering: foundational processes start
before dependents; a crash in the web tier does not restart PubSub or Finch by itself.

```
  Companion.Application (:rest_for_one)
    │
    ├── CompanionWeb.Telemetry
    ├── Phoenix.PubSub
    ├── Companion.Repo
    ├── DNSCluster
    ├── Finch (named Companion.Finch; default + Docker Unix socket pool)
    ├── DynamicSupervisor (Companion.VmLifecycle.RunnerDynamicSupervisor)
    │     └── Companion.VmLifecycle.Runner  (started on demand; VM manager pre-flight script + PubSub log)
    ├── Companion.PreflightServer  →  PubSub.broadcast("preflight:updates", …)
    └── CompanionWeb.Endpoint       (:4000)
```

Still **planned** (among other roadmap items): registry-backed session UX, per-session
`DynamicSupervisor`, `ContainerManager`, `HealthMonitor`, and deeper automation around sandboxes.

## Why Elixir / OTP for this problem

- **Fault containment**: isolate session-scoped failures (supervision + `DynamicSupervisor`) so one bad
  container or agent stream does not tear down the whole node.
- **Concurrent I/O**: health polling, Docker API calls, and proxy traffic map cleanly to concurrent
  processes and `Task.async_stream` without manual thread pools.
- **LiveView**: one long-lived connection model suits operator-style UIs (sessions, logs, vitals).
- **Testable adapters**: a `Companion.Docker` behaviour with a mock implementation keeps HTTP-over-socket
  and CLI adapters honest.

“Telecom-grade” in marketing often implies five-nines; what you get from OTP here is **explicit
supervision policy**, **process isolation**, and a **single gateway port** for routing and telemetry — not
magic reliability without good Docker and application semantics.

## Status (this commit)

- [x] Phoenix **companion** app under [`companion/`](companion/).
- [x] `Companion.Docker` behaviour + [`Companion.Docker.Mock`](companion/lib/companion/docker/mock.ex) +
  [`Companion.Docker.HTTP`](companion/lib/companion/docker/http.ex) (Finch over the Engine Unix socket when
  the socket exists and `MIX_ENV` is not `test`).
- [x] **Pre-flight** root LiveView + [`Companion.Preflight`](companion/lib/companion/preflight.ex) +
  [`Companion.PreflightServer`](companion/lib/companion/preflight_server.ex) (PubSub topic
  `preflight:updates`).
- [x] `CompanionWeb.ProxyPlug`: **`parse_app_path/1`** plus **Finch** forwarding to
  `http://<container>:<port>/…`; **502** when upstream is unreachable (see
  [`proxy_plug_test.exs`](companion/test/companion_web/proxy_plug_test.exs)).
- [x] **`/telvm/api/*`** JSON API — [`MachineController`](companion/lib/companion_web/machine_controller.ex)
  (`GET/POST /telvm/api/machines`, `POST …/exec`, `DELETE …`, `GET /telvm/api/stream` SSE); tests in
  [`machine_controller_test.exs`](companion/test/companion_web/machine_controller_test.exs).
- [x] **`/explore/:id`** — [`ExplorerLive`](companion/lib/companion_web/live/explorer_live.ex) (isolated
  live session, root layout for full-viewport UI).
- [x] Root [`docker-compose.yml`](docker-compose.yml) (`db`, `vm_node`, `companion`) +
  [`Dockerfile`](Dockerfile) dev workflow.
- [x] **VM manager pre-flight** tab + [`Companion.VmLifecycle.Runner`](companion/lib/companion/vm_lifecycle/runner.ex)
  (lazy start under `RunnerDynamicSupervisor`) + configurable lab image/network via env (see Compose).
- [ ] Session supervisor, richer LiveView agent UI, full sandbox image set — **next milestones** (see roadmap).

## Test strategy

**Canonical (matches production-ish Linux + Compose):** run ExUnit inside the stack:

```bash
docker compose --profile test run --rm companion_test
```

The [`companion_test`](docker-compose.yml) service sets `entrypoint: ["/bin/sh", "-c", "mix deps.get && mix test"]`
(so `-c` receives a single script), sets `MIX_ENV=test` and
`TEST_DATABASE_URL=postgres://postgres:postgres@db:5432/companion_test`, and runs the full test alias.
[`config/test.exs`](companion/config/test.exs) reads **`TEST_DATABASE_URL` first**, then **`DATABASE_URL`**, so
the test database host can be `db` inside the network instead of `localhost`.

**Optional (host-only):** `cd companion && mix test` when Postgres is on `localhost` and neither env var is
set (the `test` alias still runs `ecto.create` / `ecto.migrate`). Useful for fast feedback if you already
run Elixir on the host.

**Ad-hoc one-liner** (equivalent idea, without the `companion_test` service):

```bash
docker compose run --rm --entrypoint "" \
  -e MIX_ENV=test \
  -e TEST_DATABASE_URL=postgres://postgres:postgres@db:5432/companion_test \
  companion \
  sh -c "mix deps.get && mix test"
```

**Contracts under test today:**

- [`Companion.Docker.Mock`](companion/test/companion/docker_mock_test.exs) exercises all Docker callbacks
  (happy paths + deliberate `__error__` branches).
- [`Companion.Preflight`](companion/test/companion/preflight_test.exs) covers label filters encoding and rollup
  rules.
- [`CompanionWeb.ProxyPlug`](companion/test/companion_web/proxy_plug_test.exs) table-tests path parsing,
  successful forward via injected HTTP function, **502** on upstream failure, and pass-through for non-`/app`
  paths.
- [`CompanionWeb.MachineController`](companion/test/companion_web/machine_controller_test.exs) covers the
  `/telvm/api` machine CRUD, exec, and SSE stream against `Docker.Mock`.
- [`CompanionWeb.StatusLive`](companion/test/companion_web/live/status_live_test.exs) covers LiveView tabs and
  redirects.
- [`Companion.VmLifecycle.Runner`](companion/test/companion/vm_lifecycle_runner_test.exs) exercises the
  VM manager pre-flight PubSub stream against `Docker.Mock` and a stub HTTP probe.

**Later:** integration tests that talk to a real Engine should be tagged (e.g. `@tag :docker`) and run only
when `RUN_DOCKER_TESTS=1` or similar, so default CI stays hermetic.

## Layout

| Path | Role |
|------|------|
| [`companion/`](companion/) | Phoenix application (`Companion` / `:companion`) |
| [`docker-compose.yml`](docker-compose.yml) | Local orchestration: Postgres + `vm_node` + companion + `companion_test` (profile `test`) |
| [`Dockerfile`](Dockerfile) | Dev image (Elixir + Node + `postgresql-client`) |
| [`docker/companion-entrypoint.sh`](docker/companion-entrypoint.sh) | deps, assets, ecto, `phx.server` |

## Community

- [Contributing](CONTRIBUTING.md) (tests, PRs, maintainer notes for branch protection and releases)
- [Architecture](ARCHITECTURE.md) (public overview of the companion slice)
- [Security policy](SECURITY.md)
- [Code of conduct](CODE_OF_CONDUCT.md)

## License

Apache-2.0 — see [LICENSE](LICENSE).
