# Ground truth (repo vs docs)

Single place for **what actually runs** after `docker compose up --build`, ports, pollers, and auth assumptions. Use this when trimming README/quickstart so marketing does not drift from code.

## Compose services (default `docker-compose.yml`)

| Service | Host ports | Role | Volumes / notes |
|--------|------------|------|-----------------|
| `db` | (internal) | Postgres 16 | `telvm_pgdata` |
| `vm_node` | — | Node 22 HTTP on 3333; labels for Engine discovery | — |
| `ollama` | **11434** | Inference | `ollama_data` |
| `ollama_pull` | — | One-shot model pull | restart: no |
| `goose` | — | Goose CLI; `telvm.goose` label | `goose_config` |
| `morayeel_lab` | — | Synthetic cookie lab for Playwright | — |
| `companion` | **4000** | Phoenix control plane + egress listeners **4001–4003** (internal) | `docker.sock`, `./companion`, `./images`, `./scripts`, `./agents`, `morayeel_runs` |
| `speedeel` | **4010** | Guides Phoenix app | `./speedeel`, `./docs` ro |
| `companion_test` | — | Profile `test`; `mix test` | — |
| `telvm_closed_claude` / `telvm_closed_codex` | — | Vendor CLI; `HTTP_PROXY` → companion | — |

Egress workloads and ports are defined by **`TELVM_EGRESS_ENABLED`** / **`TELVM_EGRESS_WORKLOADS`** in Compose (default includes closed workloads + morayeel).

## Morayeel (`morayeel_lab` vs runner)

- **`morayeel_lab`** is a normal Compose service: small HTTP server with a synthetic session cookie on the default network.
- **Playwright runs** are started by **`Companion.MorayeelRunner`** from the companion UI (build/run **morayeel** image on demand). There is **no** always-on `morayeel` Compose service in the default file—only the lab + volume for artifacts. See [agents/morayeel/README.md](../../agents/morayeel/README.md).

## NetworkAgentPoller without a Windows host

Compose defaults **`TELVM_NETWORK_AGENT_URL`** to **`http://host.docker.internal:9225`**. On **Linux-only** dev machines nothing may listen there: expect periodic unreachable polls / log lines—safe to ignore for Engine work. To suppress the poller, set companion **`TELVM_NETWORK_AGENT_URL`** to empty (see [companion/lib/companion/application.ex](../../companion/lib/companion/application.ex): empty URL skips `NetworkAgentPoller`).

## Pollers and agents (who talks to whom)

| Component | Supervised? | Behavior |
|-----------|-------------|----------|
| **`Companion.NetworkAgentPoller`** | Yes (when `TELVM_NETWORK_AGENT_URL` is non-empty; Compose sets default URL) | Polls Windows **`telvm-network-agent`** (`/health`, `/ics/hosts`), then probes each LAN IP at **`http://<ip>:9100/health`** with **Bearer** token from **`TELVM_ZIG_NODE_PROBE_TOKEN`** (default `test123`). Publishes **`network_agent:updates`** on PubSub → Pre-flight **LAN / ICS** UI. |
| **`Companion.ClusterNodePoller`** | **No** | Module + tests exist; would read **`ClusterNodesConfig`** (`:cluster_nodes`, `:cluster_token`). **`runtime.exs` does not load `TELVM_CLUSTER_*`** into those keys today. **Not** in `Companion.Application`; **no** LiveView subscribes to **`cluster_nodes:updates`**. Do not document as shipped until wired. |
| **`telvm-network-agent`** | External (Windows host) | PowerShell **HttpListener**; ICS + ARP-style host list. See [agents/telvm-network-agent/README.md](../../agents/telvm-network-agent/README.md). |
| **`telvm-node-agent`** | External (Linux LAN nodes) | Zig binary on **:9100**; narrow Docker proxy + `/health`. See [agents/telvm-node-agent/README.md](../../agents/telvm-node-agent/README.md). |

## Auth and trust (local dev defaults)

| Surface | Auth today | Notes |
|---------|------------|--------|
| **`/telvm/api`** | None | Trusted LAN / localhost only — see [agent-api.md](../agent-api.md). |
| **`telvm-network-agent`** | Optional Bearer (`TELVM_NETWORK_AGENT_TOKEN`) | Requires **Administrator** on Windows for ICS + listener. |
| **`telvm-node-agent`** | Bearer (`--token` / env) | **Must** match **`TELVM_ZIG_NODE_PROBE_TOKEN`** on the companion for LAN probes to show **ok**. |
| Egress listeners | Per-workload allowlist (+ optional `authorization_env`) | Vendor traffic only through declared hosts unless you extend JSON. |

## README / doc mismatches (fixed in wiki + spine)

- **Static cluster poller:** older docs implied **`TELVM_CLUSTER_*`** drove Pre-flight; **ground truth** is **NetworkAgentPoller + Windows agent + Zig :9100** until `ClusterNodePoller` is supervised, env is wired, and UI subscribes.

## Related docs

- LAN bring-up: [lan-cluster-network-primer.md](../lan-cluster-network-primer.md), [inventories/lan-host/README.md](../../inventories/lan-host/README.md)
- Agents atlas: [agents/README.md](../../agents/README.md)
