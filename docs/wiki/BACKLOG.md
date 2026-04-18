# Telecom learning requests

**Curious about telecom—how traffic moves, how operators see a network, how “nodes” talk to each other?** You can **build it yourself** here. This page is an **open invitation**: concrete ideas that fit the **telvm** monorepo ([telvm-hq/telvm](https://github.com/telvm-hq/telvm)), not homework for maintainers.

We bias toward **fully containerized** stacks (`docker compose up`), Elixir/Erlang, and a little drama in the UI so the lesson sticks. Pick an epic, open a draft PR early, and we will help you steer.

**Repository note:** these docs live under **`docs/wiki/`** at the **telvm** repo root (same project as `companion/`, `docker-compose.yml`, and `agents/`). They are **not** scoped to the standalone **`speedeel/`** guides app on port 4010—that is a different surface in this monorepo.

Day-to-day companion polish lives in [GROUND_TRUTH.md](GROUND_TRUTH.md). Epic phases and non-goals: [BACKLOG-virtual-telco-lab.md](BACKLOG-virtual-telco-lab.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

## Epic labs (start here)

| ID | What to build | Pointers | Suggested exit |
|----|---------------|----------|----------------|
| **virtual-telco-lab** | Compose-first “virtual telco”: each container an Erlang/Elixir **node**, central **operator dashboard**, two **browser sessions** (tabs or Playwright contexts), onboarding, **text** E2E; “calls” as signaling/UI first—not a WhatsApp clone. | [BACKLOG-virtual-telco-lab.md](BACKLOG-virtual-telco-lab.md), [agents/morayeel](../../agents/morayeel), [GROUND_TRUTH.md](GROUND_TRUTH.md), [docker-compose.yml](../../docker-compose.yml) | Phase 1 in spec + README; optional Playwright E2E; link chosen repo or `labs/` path in the spec. |
| **router-switch-learning-lab** | Same **containerized skeleton** as virtual-telco: multi-node + dashboard, but teach **L2/L3** (ports, VLANs, traceroute-style view) instead of chat. | [BACKLOG-virtual-telco-lab.md](BACKLOG-virtual-telco-lab.md) (reuse Compose discipline), new teaching README | Reuse Elixir/Compose layout; swap domain model; document classroom goals. |

## Zig node agent: static cluster list (companion)

**Why this row exists:** LAN Pre-flight today uses **`NetworkAgentPoller`** → Windows **[telvm-network-agent](../../agents/telvm-network-agent/README.md)** → discovers hosts → probes **[telvm-node-agent](../../agents/telvm-node-agent/README.md)** (Zig) at **`http://<ip>:9100`**. That path is the **default** for ICS-style labs.

Some deployments want a **fixed list of Zig node URLs** (no Windows gateway). **`Companion.ClusterNodePoller`** was written for that: poll **`GET /health`** on each configured **Zig agent** over HTTP. It is **not** supervised, **`TELVM_CLUSTER_*` is not loaded** in [runtime.exs](../../companion/config/runtime.exs), and **no LiveView** subscribes to **`cluster_nodes:updates`**.

| ID | Symptom | Pointers | Suggested exit |
|----|---------|----------|----------------|
| **zig-static-cluster-dashboard** | Operators with a **known set of Zig `telvm-node-agent` hosts** get no Pre-flight table unless they use Windows discovery. | [cluster_node_poller.ex](../../companion/lib/companion/cluster_node_poller.ex), [cluster_nodes_config.ex](../../companion/lib/companion/cluster_nodes_config.ex), [application.ex](../../companion/lib/companion/application.ex), [runtime.exs](../../companion/config/runtime.exs), [agents/telvm-node-agent/README.md](../../agents/telvm-node-agent/README.md) | **A)** Load `TELVM_CLUSTER_NODES` / token in `runtime.exs`, supervise `ClusterNodePoller`, subscribe from Pre-flight/LiveView. **B)** Delete poller + tests + env stubs and document “LAN + Zig probe only.” |

## Done (recent)

| Item | PR / notes |
|------|------------|
| Docs spine: GROUND_TRUTH, contributor backlog index, README debloat, LAN alignment, `TELVM_ZIG_NODE_PROBE_TOKEN` | [telvm-hq/telvm#44](https://github.com/telvm-hq/telvm/pull/44) |
| Maintainer PR stacking notes | [docs/releases/README.md](../releases/README.md), [SPLIT_PRS_workflow.md](../releases/SPLIT_PRS_workflow.md) |

When you close **zig-static-cluster-dashboard**, move it here with a PR link. User-visible lab work should also touch [CHANGELOG.md](../CHANGELOG.md).
