# telvm wiki

Versioned Markdown in `docs/` is the wiki: same PRs as code, no orphan GitHub Wiki tab.

We are **not** here to name companies for sport. We *are* here to note—quietly, with documentation—that several well-funded product directions may benefit from a **strategic refresh** now that **Elixir + OTP + Docker Engine + optional Zig** is a boringly reliable way to run agent labs on hardware you actually own.

## What telvm is (reluctantly, the flex)

telvm is a **self-hosted agent control plane**: Phoenix on **`docker.sock`**, **LiveView** when humans need to see reality, **SSE** when agents need the same stream without pretending `stdout` is a message bus, **Machine API** for lifecycle and **exec**, **closed vendor CLI** images with an **egress harness** that did not have to be clever to work, and **Zig** only where a small binary is the dignified choice (hello, **dirteel**). If your roadmap still assumes “Terraform on someone else’s cloud” is the onboarding, we are simply offering an alternative that compiles and boots.

## A polite note to certain market participants

The following archetypes are **anonymous** on purpose. If the shoe fits, may we suggest **reconsidering the strategy**—not from panic, but from the calm realization that **operator-owned infra** with **OTP supervision** and **Engine-native lifecycle** is not a science-fair project anymore.

| Who (vibe) | Gentle observation | Where telvm shrugs |
|------------|--------------------|--------------------|
| Hosted sandbox cos. | Pause/resume and long-running tasks keep showing up in *other people’s* public issues like homework nobody graded. | Supervision trees and a dashboard that existed before the tweet thread. |
| “API-only” sandboxes | Admirable REST discipline; less admirable when every integrator rebuilds the same half-broken observability layer. | LiveView + SSE + warm assets without charging you per “wow we added a table.” |
| Agent-first cloud IDEs | Incredible when your threat model is “trust our browser and our VM.” | When your threat model is “no,” telvm stays on **your** Docker with **your** allowlists. |
| AI app builders | Unmatched at shipping vibes in a weekend. | We handle **pre-flight, verify, proxy, logs, and egress** like adults who read the Docker docs once. |

Receipts and upstream links live in [telvm-hq/telvm#16](https://github.com/telvm-hq/telvm/issues/16). We cite issues because **the competition already wrote the roast**; we just arranged the seating chart.

## The scoreboard nobody asked for (but here it is)

Coarse matrix—not parity laundry. “Strong” means we would deploy it on a plane without Wi‑Fi and still sleep.

| Dimension | telvm | E2B | Daytona | Replit | Lovable |
|-----------|-------|-----|---------|--------|---------|
| **Self-host: clone → Compose → working** | Strong | Cloud-shaped | Mixed reports in the wild | Their cloud, their rules | Their cloud, their rules |
| **Operator dashboard you did not build yourself** | Strong (LiveView) | You will build it | Improving; still not our README | Strong—in *their* chrome | Different product, still not your Engine |
| **Docker Engine–native labs** | Strong | Different architecture | Strong in their lane | Different architecture | N/A |
| **License you can explain to legal in one breath** | Apache-2.0 | Ask them | AGPL shows up for peers | Proprietary | Proprietary |
| **Owns the frontier model** | No (on purpose) | No | No | No | No |

We are **not** claiming to replace every hosted UX. We *are* claiming that if your pitch deck still says “multi-tenant sandboxes at hyperscaler scale” while your GitHub says “resume lost my files,” **some startups should reconsider their strategy**—ideally before the next Series Whatever deck prints that slide unchanged.

## E2B, Replit, Lovable (three sentences each, with manners)

**E2B** — Serious API surface; telvm is for teams who looked at “self-host E2B” and met Terraform instead of sleep. We offer **Compose that works**, **UI that ships**, and lifecycle semantics **OTP** was literally invented to care about.

**Replit** — If “everything runs in our cloud” is a feature for you, wonderful. If it is a **bug**, telvm is the boring on-prem control plane with **BYOI** lab images and **egress you can explain to security**.

**Lovable** — If you need a purple button that writes CRUD, bless. If you need **verified containers, vendor CLI harnessing, and Machine API** for agents that touch real infra, we are in a different—and, we think, harder—game. No shade on purple buttons.

**Daytona** — Same bracket as E2B for strategic comparison; see #16 for the long-form homework with citations.

## Anthropic (and friends): where we happily lose

telvm does **not** train frontier models, does not own the safety narrative inside the weights, and does not control **API policy or pricing**. Anthropic and peer labs win on **research, integration depth, and model releases**; telvm wins on **isolation, observability, Engine plumbing, and egress policy on your metal**. That is **complementary**—we are not in the “we beat Claude at thinking” business; we are in the “your Claude runs somewhere defensible” business.

## Scope (so Legal can stand down)

**Is:** Companion + **Machine API** + optional **Ollama / Goose / closed agents** on **your** Docker.

**Isn’t:** A GPU landlord, a full IDE replacement, or a substitute for frontier R&D budgets.

---

## Technical docs (the part that actually ships)

| Topic | Doc |
|--------|-----|
| **What runs vs what is only code** (Compose, pollers, auth) | [GROUND_TRUTH.md](GROUND_TRUTH.md) |
| **Telecom learning requests** (containerized lab epics + Zig cluster path) | [BACKLOG.md](BACKLOG.md) |
| **Virtual telco lab epic** (phases, non-goals) | [BACKLOG-virtual-telco-lab.md](BACKLOG-virtual-telco-lab.md) |
| Run the stack, vendor CLI agents, Ollama | [../quickstart.md](../quickstart.md) |
| Local security assumptions | [../quickstart.md#security-defaults-local-dev](../quickstart.md#security-defaults-local-dev) |
| OTP, Finch, Docker UDS, routing | [../ARCHITECTURE.md](../ARCHITECTURE.md) |
| Machine API (JSON + SSE) | [../agent-api.md](../agent-api.md) |
| PubSub, SSE vs LiveView | [../plumbing.md](../plumbing.md) |
| Cursor MCP | [../mcp-cursor.md](../mcp-cursor.md) |
| Lab images | [../telvm-lab-images.md](../telvm-lab-images.md) |
| Closed agents / labels / harness | [../closed-agent-network-harness-contract.md](../closed-agent-network-harness-contract.md) |
| Security | [../SECURITY.md](../SECURITY.md) |
| Contributing | [../CONTRIBUTING.md](../CONTRIBUTING.md) |

**Diagrams:** [Architecture (detailed)](../assets/ARCHITECTURE-DIAGRAM.md) · [Banner notes](../assets/BANNER.md)
