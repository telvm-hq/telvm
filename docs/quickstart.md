# Quick start and runbook

**Spine:** [README — Start here](../README.md#start-here-60-seconds) for the one-minute path; **this file** is the runbook (egress, vendor CLI, Ollama, LAN, tests).

After Compose is up: **`localhost:4000`** → **`/health`** (Pre-flight); **`/machines`**; **`/telvm/api`** ([agent-api.md](agent-api.md)); **Preview** **`/app/<container>/port/<n>/…`**; **Explorer** **`/explore/:id`**; **`/telvm/api/fyi`**. Glossary: [README — Glossary](../README.md#glossary).

## Docker (recommended)

Prerequisites: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or a compatible Engine).

If you use **closed-agent upstream submodules** (`third_party/claude-code`, `third_party/codex`), initialize them after clone: `git submodule update --init --recursive` (see [CONTRIBUTING — Git submodules](CONTRIBUTING.md#git-submodules-closed-agent-upstream-trees)).

```bash
docker compose up --build
```

Open [http://localhost:4000/machines](http://localhost:4000/machines) for **Machines**. **`/`** → **`/health`**; **`/topology`** → **`/warm`**. Legacy **`/images`**, **`/vm-manager-preflight`**, **`/certificate`** → **`/machines`**. **Explorer:** **`/explore/:id`**. Automation: **[Machine API](agent-api.md)**.

**Guides (speedeel):** Compose starts **`speedeel`** on **[http://localhost:4010](http://localhost:4010)** — separate app; see **[`speedeel/README.md`](../speedeel/README.md)** or **`cd speedeel && docker compose up`** for guides-only.

**Compose rows, pollers, and ports** (authoritative): [wiki — GROUND_TRUTH.md](wiki/GROUND_TRUTH.md).

Pre-flight on **`/health`** includes Postgres, Docker socket, **Finch → Engine**, ProxyPlug, egress cards, and (when configured) **LAN / ICS** from **`NetworkAgentPoller`**. VM manager uses **`Companion.VmLifecycle.Runner`**; soak via **`SoakRunner`**. PubSub: `preflight:updates`, `lifecycle:vm_manager_preflight`. Companion bind-mounts **`./companion`** with named volumes for deps, `_build`, and `assets/node_modules`.

### LAN / Windows network agent (optional)

For a **Windows gateway** (Wi‑Fi uplink + Ethernet to a lab switch), run **[`agents/telvm-network-agent`](../agents/telvm-network-agent/README.md)** elevated; set **`TELVM_NETWORK_AGENT_TOKEN`** on both the agent and companion (**`.env`** or Compose). Compose defaults **`TELVM_NETWORK_AGENT_URL`** to **`http://host.docker.internal:9225`**.

**Companion** starts **`Companion.NetworkAgentPoller`**, which polls the network agent and probes each discovered host at **`http://<ip>:9100/health`** for **[`telvm-node-agent`](../agents/telvm-node-agent/README.md)** (Zig). Set **`TELVM_ZIG_NODE_PROBE_TOKEN`** on companion to the **same** Bearer secret as each Linux agent’s **`--token`** (default in dev is **`test123`** — override for anything beyond trusted LAN).

A separate **static list** poller (**`Companion.ClusterNodePoller`**) exists in the codebase but is **not** supervised, **not** connected to the UI, and **`TELVM_CLUSTER_*` env vars are not loaded** in `runtime.exs` yet — ignore for production until wired. Details: [wiki/GROUND_TRUTH.md](wiki/GROUND_TRUTH.md).

### Closed-agent egress (verify)

From the repo root, after **`docker compose up --build`** reports **companion** healthy:

```bash
./scripts/verify-closed-agent-egress.sh
docker compose logs companion 2>&1 | grep egress_proxy
```

On Windows (PowerShell): **`./scripts/verify-closed-agent-egress.ps1`**, then filter logs with **`Select-String egress_proxy`**. Allowed **CONNECT** lines look like **`egress_proxy CONNECT allowed workload=closed_claude target=api.anthropic.com:443`**. The verify script also runs **`apt-get update`** inside each closed container so package index fetches must succeed through the proxy; **`TELVM_EGRESS_WORKLOADS`** therefore includes **`deb.debian.org`**, **`security.debian.org`**, and **`.debian.org`** alongside vendor hosts. If your **`sources.list`** points at other mirror hostnames, add them to the allowlist. **lab_relaxed** images may still allow tools that ignore **`HTTP_PROXY`** to use direct egress — see [closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md).

### Vendor CLI agents (5 min)

Goal: after **`docker compose up --build`**, a new clone can **pull** the published Claude/Codex images, run **Basic soak** on **Machines**, and see the container on **Warm assets**.

1. Open **[http://localhost:4000/health](http://localhost:4000/health)** (Pre-flight). In the **egress proxy** card, confirm **enabled** and two workloads (**4001** / **4002**) with allowlists — see [Diagnosing Basic soak](#diagnosing-basic-soak-curl-exit-56) if soak fails later.
2. Open **[http://localhost:4000/machines](http://localhost:4000/machines)**. Under **Vendor CLI agents**, pick **Node + Claude Code** or **Node + Codex**.
3. Click **pull image** (GHCR `:main`; org follows **`TELVM_LAB_GHCR_ORG`**, default **`telvm-hq`**). Ensure the matching Compose service is **running** (`telvm_closed_claude` / `telvm_closed_codex` — they **`depends_on: companion`** healthy).
4. Click **Basic soak** (egress `curl` via **`http://companion:<port>`** + **`apt-get update`**). On success, open **[http://localhost:4000/warm](http://localhost:4000/warm)** — the closed container appears there until companion restarts (in-memory registry).

**Discovery:** Machines lists closed containers whose labels include **`telvm.agent=closed`** and **`com.docker.compose.project=<name>`**. The project name defaults to **`telvm`** (from the Compose file `name:`). If you use **`docker compose -p mystack up`**, set **`TELVM_COMPOSE_PROJECT=mystack`** for the companion service (see **`.env.example`** and [docker-compose.yml](../docker-compose.yml)).

### Diagnosing Basic soak (curl exit 56)

**Exit 56** (“Recv failure: Connection reset by peer”) usually means the **TLS or HTTP path through the egress proxy** failed—not that the UI or Docker exec is broken.

Work through these in order:

1. **Host script (canonical):** from repo root, run **`./scripts/verify-closed-agent-egress.sh`** (or **`scripts/verify-closed-agent-egress.ps1`**). If the script fails but the UI passed (or the reverse), compare environments (same Engine, same Compose project).
2. **Companion logs:** `docker compose logs companion 2>&1 | grep egress_proxy` (Windows: **`findstr egress_proxy`**). Look for **deny** lines vs **CONNECT allowed** for `api.anthropic.com` / `api.openai.com`.
3. **Pre-flight card:** on **`/health`**, open **recent denies** under egress — if a hostname is blocked, extend **`TELVM_EGRESS_WORKLOADS`** `allow_hosts` in **`docker-compose.yml`** (then `docker compose up -d companion`).
4. **Isolate bridge DNS vs listener:** from the **companion** container, a direct probe uses **`127.0.0.1`** instead of the hostname **`companion`**:  
   `docker compose exec companion sh -c 'curl -sS -o /dev/null --max-time 25 --proxy http://127.0.0.1:4001 https://api.anthropic.com/'`  
   If this fails the same way, focus on **EgressProxy** / allowlist; if it succeeds from companion but fails from **`telvm_closed_claude`**, focus on **container → companion:4001** routing.
5. **Verbose soak (optional):** set **`TELVM_CLOSED_SOAK_VERBOSE=1`** on the **companion** service and restart it; Basic soak then captures more **`curl`** output in the error panel (noisy — turn off after debugging).

### Ollama (OSS Agents / CPU smoke)

Compose runs **[Ollama](https://ollama.com/)** with a named volume for weights (`ollama_data`). No GPU is requested; `CUDA_VISIBLE_DEVICES=-1` biases toward CPU. A short-lived **`ollama_pull`** service waits for the API, then pulls **`qwen2.5:0.5b`** and **`tinyllama`** (fixed in **`docker-compose.yml`**; override only if you add variables to a **`.env`** file and reference them from Compose). First start can take a while while blobs download.

After `docker compose up --build` settles, open **[http://localhost:4000/oss-agents](http://localhost:4000/oss-agents)** (legacy **`/agent`** redirects here). The page **auto-probes** Ollama (OpenAI-compatible `GET /v1/models`), lists models, and when possible **starts the Model tab chat** with **`TELVM_AGENT_DEFAULT_MODEL`** (default **`qwen2.5:0.5b`**). The **Goose agent** tab is the default for in-container chat. Use **Refresh models** to re-fetch after changing the base URL. The companion uses **`TELVM_INFERENCE_BASE_URL=http://ollama:11434/v1`** on the Compose network.

Optional manual smoke on the host (sequential, one model at a time):

```bash
docker compose exec ollama ollama run tinyllama "say hi in one line"
docker compose exec ollama ollama run qwen2.5:0.5b "say hi in one line"
```

### Goose CLI (optional container)

Compose can build a **`goose`** service (Goose CLI + `sleep infinity`) on the same network as Ollama. Config lives in the **`goose_config`** volume at **`/root/.config/goose`** inside the container (persists `goose configure` output).

**First-time setup** (interactive; run from the host, repo root):

```bash
docker compose exec -it goose goose configure
```

Choose the **Ollama** provider, point at **`OLLAMA_HOST`** (Compose sets `http://ollama:11434`), pick a model you have pulled, and say **No** to the keyring if prompted (typical for Linux containers).

**Interactive session** (TTY; not the Phoenix UI):

```bash
docker compose exec -it goose goose session
```

The **OSS Agents** tab puts **Model / Goose chat** in the main right-hand column on wide screens (sticky panel); **Agent runtime · diagnostics** (container id, state, engine log tail, refresh / restart) sits under the inference URL panel on the left. On **Machines**, under **Vendor CLI agents**, pull **Claude Code** / **Codex** images and run **Basic soak** (egress + apt); on success they appear on **Warm assets** (in-memory until companion restart). On narrow viewports the OSS Agents stack is preflight, then diagnostics, then weights, then chat. Full interactive CLI remains **`docker compose exec -it goose goose session`** (TTY).

Companion uses the **absolute path** `/usr/local/bin/goose` for Docker Engine **exec** (no login shell, so `goose` alone can fail with **exit 127**). If you see 127, rebuild the `goose` image or confirm the binary exists in the container. **`Companion.GooseHealth`** (slow background probe + line on the Goose tab) checks the labeled container, `goose --version`, `curl` to Ollama from inside that container, and optionally a short `goose run` hello.

**Troubleshooting (dynamic libraries):** If stderr mentions **`libgomp.so.1`** or **`error while loading shared libraries`**, the prebuilt Goose binary needs extra runtime packages that **`debian:bookworm-slim`** does not include by default. The telvm **`images/goose/Dockerfile`** installs **`libgomp1`** for this reason. Run **`docker compose build goose --no-cache`** (or **`docker compose up --build`**) after pulling Dockerfile changes. Upstream release tarballs may add new dependencies in future versions; **`goose --version`** at image build time fails fast if the binary cannot start.

**Limitations (honest):** each Goose send from the UI runs one blocking **`goose run --text`** via Docker exec until the process exits — no token streaming or step-by-step reasoning in the browser yet; long runs can feel like a hang. Configure Goose inside the container (`goose configure`); the Phoenix **Refresh models** / auto-probe path does not write Goose config.

The **Model** tab runs chat completion in a **background task** so your message and a “replying” state appear **before** the full answer arrives; replies are still **non-streaming** (one completion body), not SSE token-by-token.

**OTP / dev note:** Phoenix code reloading recompiles modules but does **not** re-run `Application.start/2`. The runner starts lazily under a `DynamicSupervisor` on first **Verify** or pre-flight run. If you change **supervised children** in [`companion/lib/companion/application.ex`](companion/lib/companion/application.ex), restart the BEAM: `docker compose restart companion`.

### Tests

```bash
docker compose --profile test run --rm companion_test
```

This uses the `test` Compose profile, starts Postgres if needed, sets `MIX_ENV=test` and `TEST_DATABASE_URL` to reach the `db` service. See [Architecture](ARCHITECTURE.md#test-strategy) for host-only testing and module-level contracts.

**Optional host smoke (real Engine + egress):** with the default stack already up (`docker compose up --build`), from repo root on Linux/macOS/Git Bash:

```bash
make smoke-closed-egress
```

This runs **`scripts/verify-closed-agent-egress.sh`** (same checks as the UI Basic soak path). On Windows without `make`, run the **`.ps1`** script directly (see [Closed-agent egress](#closed-agent-egress-verify) above).

### Environment

Optional: copy [`.env.example`](../.env.example) to `.env` for overrides (network agent tokens, Zig probe token, API keys, Ollama model names). The default stack does not need a `.env` file.

### Security defaults (local dev)

telvm targets **trusted localhost / lab LAN**, not anonymous multi-tenant internet:

- **`/telvm/api`** has **no authentication** — see [agent-api.md](agent-api.md).
- **Windows network agent** needs elevation and should use a **strong Bearer token**; bind to LAN only in real deployments.
- **Egress allowlists** (`TELVM_EGRESS_WORKLOADS`) are your outbound policy; extend `allow_hosts` when mirrors or vendors change.
- **`TELVM_ZIG_NODE_PROBE_TOKEN`** must match **`telvm-node-agent`** on each node; the companion default is for dev only — see [wiki/GROUND_TRUTH.md](wiki/GROUND_TRUTH.md).

### Registry-backed VM manager pre-flight (optional)

The default lab image is **`node:22-alpine`** with an inline HTTP server command.

**From the UI:** on **Machines**, open **VM manager pre-flight**, choose **Go HTTP lab**, enter your published ref (optional: **`TELVM_GO_HTTP_LAB_IMAGE`** in `.env`), then **Run**.

**From env only:** set `TELVM_LAB_IMAGE` and **`TELVM_LAB_USE_IMAGE_CMD=1`** so Docker Engine uses the image’s own `CMD` (see [`Companion.VmLifecycle.lab_container_create_attrs/2`](../companion/lib/companion/vm_lifecycle.ex)).

GHCR publishes the optional **go-http-lab** image when `images/go-http-lab/**` changes on `main` ([workflow](../.github/workflows/publish-go-http-lab.yml)):

- Image: **`ghcr.io/telvm-hq/telvm-go-http-lab`** (tags: **`main`**, commit SHA).

```bash
docker pull ghcr.io/telvm-hq/telvm-go-http-lab:main
```

After the first successful publish, the package appears under the org’s **Packages**. For **private** packages, run `docker login ghcr.io` on the host whose Engine backs `docker.sock`.

### Closed-agent images (Claude Code / Codex CLI)

GitHub Actions publish **`ghcr.io/<lowercase-owner>/telvm-closed-claude`** and **`ghcr.io/<lowercase-owner>/telvm-closed-codex`** when `images/telvm-closed-*` or the corresponding `third_party/*` submodule pointer changes on `main` (workflows: [`publish-telvm-closed-claude.yml`](../.github/workflows/publish-telvm-closed-claude.yml), [`publish-telvm-closed-codex.yml`](../.github/workflows/publish-telvm-closed-codex.yml)). Tags: **`main`**, commit SHA.

```bash
docker pull ghcr.io/telvm-hq/telvm-closed-claude:main
docker pull ghcr.io/telvm-hq/telvm-closed-codex:main
```

Build locally from repo root: see [`images/telvm-closed-claude/README.md`](../images/telvm-closed-claude/README.md) and [`images/telvm-closed-codex/README.md`](../images/telvm-closed-codex/README.md). Labels and egress defaults: [closed-agent-docker-labels.md](closed-agent-docker-labels.md), [closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md).

### Non-interactive Phoenix scaffolding

If you regenerate the app with `mix phx.new`, pass **`--yes`** so Mix does not stop for prompts in CI.

## Local Elixir (optional)

From `companion/`:

```bash
mix setup
mix phx.server
```

You need Postgres matching `config/dev.exs` (or `DATABASE_URL`). See [Architecture — Test strategy](ARCHITECTURE.md#test-strategy) for `mix test` on the host.
