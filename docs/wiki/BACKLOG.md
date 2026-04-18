# Contributor backlog

Short, **actionable** items we are not hiding—good targets if you want to pour tokens into the repo. For what actually ships today, see [GROUND_TRUTH.md](GROUND_TRUTH.md).

**Rules:** each row = symptom + pointers + plausible exit. No delivery dates.

| ID | Symptom | Pointers | Suggested exit |
|----|---------|----------|----------------|
| **cluster-poller** | Static node list poller never runs in production layout. | [companion/lib/companion/cluster_node_poller.ex](../../companion/lib/companion/cluster_node_poller.ex), [cluster_nodes_config.ex](../../companion/lib/companion/cluster_nodes_config.ex), [application.ex](../../companion/lib/companion/application.ex), [runtime.exs](../../companion/config/runtime.exs) | **A)** Parse `TELVM_CLUSTER_*` in `runtime.exs`, supervise `ClusterNodePoller`, subscribe from LiveView on `cluster_nodes:updates`. **B)** Remove poller + tests + env stubs if LAN-only is the long-term answer. |
| **machine-api-auth** | `/telvm/api` is unauthenticated by design (local trust). | [docs/agent-api.md](../agent-api.md), Machine controller / router under `companion/lib/companion_web/` | Optional shared secret header, mTLS, or reverse-proxy auth—document threat model first; keep default zero-config for local dev. |
| **status-live-size** | Single LiveView module is very large (operator UX debt). | [companion/lib/companion_web/live/status_live.ex](../../companion/lib/companion_web/live/status_live.ex) | Extract components or child LiveViews by tab; add focused tests per slice. |
| **pr-split-notes** | Maintainer notes for stacking PRs lived in README; moved here for debloat. | [SPLIT_PRS_workflow.md](../releases/SPLIT_PRS_workflow.md), [releases/README.md](../releases/README.md), `PR_BODY_*.md` in same folder | Keep using `docs/releases/` for `gh pr create --body-file` drafts. |

When you close an item, delete or shrink its row and mention the PR in [CHANGELOG.md](../CHANGELOG.md) if user-visible.
