# Quick start and runbook

**Same spine as the [README](../README.md#start-here-60-seconds):** after Compose is up, **`localhost:4000`** serves the **operator UI** (`/`, `/machines`, `/topology`), the **Machine API** at **`/telvm/api`** for agents and scripts ([agent-api.md](agent-api.md)), **Preview** at **`/app/<container>/port/<n>/…`**, and **Explorer** (read-only Monaco) at **`/explore/:id`**. Glossary: [README — Glossary](../README.md#glossary).

## Docker (recommended)

Prerequisites: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or a compatible Engine).

```bash
docker compose up --build
```

Open [http://localhost:4000/machines](http://localhost:4000/machines) for the **Machines** tab (container list, lab controls, and **VM manager pre-flight**). The same LiveView shell also exposes **checks** (`/`) and **topology** (`/topology`). Legacy bookmarks **`/images`**, **`/vm-manager-preflight`**, and **`/certificate`** redirect to **`/machines`** on full page load. **Explorer** is at **`/explore/:id`** (full-viewport shell for deep visibility into a workload). For **Cursor**-style automation without the browser, use **[Machine API](agent-api.md)** (`/telvm/api/…`).

Platform pre-flight on `/` covers Postgres, Docker socket, **Finch → Docker Engine** (`GET /version` + labeled container discovery for `vm_node`), ProxyPlug contract, and related rows. The VM manager pre-flight flow runs a scripted lifecycle (ephemeral lab container + HTTP probe) via `Companion.VmLifecycle.Runner`. Updates use **Phoenix PubSub** (`preflight:updates` and `lifecycle:vm_manager_preflight`). Default Compose brings up **db**, **vm_node** (Node 22 + `telvm.sandbox=true`), and **companion**. The companion container bind-mounts `./companion` and uses named volumes for `deps`, `_build`, and `assets/node_modules`.

**OTP / dev note:** Phoenix code reloading recompiles modules but does **not** re-run `Application.start/2`. The runner starts lazily under a `DynamicSupervisor` on first “Run VM manager pre-flight”. If you change **supervised children** in [`companion/lib/companion/application.ex`](companion/lib/companion/application.ex), restart the BEAM: `docker compose restart companion`.

### Tests

```bash
docker compose --profile test run --rm companion_test
```

This uses the `test` Compose profile, starts Postgres if needed, sets `MIX_ENV=test` and `TEST_DATABASE_URL` to reach the `db` service. See [Architecture](../ARCHITECTURE.md#test-strategy) for host-only testing and module-level contracts.

### Environment

Optional: copy [`.env.example`](../.env.example) to `.env`; Compose picks up `.env` for variable substitution when referenced in `docker-compose.yml`.

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

### Non-interactive Phoenix scaffolding

If you regenerate the app with `mix phx.new`, pass **`--yes`** so Mix does not stop for prompts in CI.

## Local Elixir (optional)

From `companion/`:

```bash
mix setup
mix phx.server
```

You need Postgres matching `config/dev.exs` (or `DATABASE_URL`). See [Architecture — Test strategy](../ARCHITECTURE.md#test-strategy) for `mix test` on the host.
