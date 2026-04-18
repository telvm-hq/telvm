# Epic: Virtual telco lab (WhatsApp-Web–shaped demo)

**Pattern:** a **fully containerized** app—everything meaningful runs under **`docker compose up`**—so students and contributors can clone, run, and extend without a bespoke host install. The same pattern applies to the **[router-switch-learning-lab](BACKLOG.md)** epic (different domain, same Compose discipline).

Teaching lab—not a production chat product. Full WhatsApp Web implies WebRTC, push, E2E crypto, and mobile bridges; **those are out of scope** for the MVP below.

## Vision

- **`docker compose up`** spins a small **distributed Erlang/Elixir** system: each container is a **node** in a “telephone network” metaphor.
- A **central operator dashboard** (virtual network operator) shows topology, node health, and sessions.
- **Two browser tabs** (or two Playwright **browser contexts**) act as **separate subscribers**: onboarding (register / display name), then **text** end-to-end.
- **“Calling”** in phase 1 is **signaling + UI state** (ringing / connected)—no PSTN, no mandatory WebRTC. Phase 2 may add WebRTC audio or a canned mock.

## Phases

| Phase | Scope | Exit criteria |
|-------|--------|----------------|
| **1 — MVP** | Compose file; distributed Erlang cluster or Phoenix + explicit node roles; operator LiveView dashboard; Phoenix Channels (or process messaging) for **text**; minimal onboarding | README + 2-minute operator tour; manual two-tab smoke |
| **1b — E2E** | One **Playwright** test, two contexts, sends a message both ways | CI or `mix`/npm script documented |
| **2 — Call UX** | Signaling + state machine for calls; optional WebRTC or mock audio | Dashboard shows call state; docs spell out limitations |
| **3 — NMS variant** | Reuse skeleton for **router/switch learning**: fake ports, VLAN labels, traceroute-style visualization instead of chat—see [BACKLOG.md](BACKLOG.md) row **router-switch-learning-lab** | Same Compose discipline; teaching README |

## Non-goals

- Signal Protocol, MLS, or “real” E2E for MVP.
- Horizontal scale, federation, or mobile apps.
- Carrier interconnect or real DIDs.

## Pointers

- Compose patterns: [GROUND_TRUTH.md](GROUND_TRUTH.md), repo [docker-compose.yml](../../docker-compose.yml).
- Dual-browser automation patterns: [agents/morayeel](../../agents/morayeel).
- **Placement:** new repo, or `labs/virtual-telco/` under telvm—pick one in the first PR and link it here.
