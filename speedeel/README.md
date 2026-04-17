# speedeel (guides / labs)

```
┌─────────────────────────────────────────────────────────────┐
│                      S P E E D E E L                        │
│    physical builds (guides)  +  digital cart (circuit)      │
│                    :4010  ·  not Companion                │
└─────────────────────────────────────────────────────────────┘
```

**North star:** race **in the shop and on the track**—hands-on curriculum (pawn-shop electric build series in Markdown) plus a small **Three.js** “circuit” on the home page. telvm’s serious stack (companion on **:4000**, lifecycle, egress, dashboards) stays the substrate; **speedeel** is the **labs / guides / toy-race** façade: approachable, forkable, and safe to demo without pretending this folder replaces the control plane.

**Scope (intentionally narrow):** this app is **not** a product comparison microsite, a second operator dashboard, or a commitment to ship every differentiator below inside Phoenix. It stays **illustrative and educational**. The competitive notes are **signposts**—enough to explain why telvm’s architecture direction matters—while the game stays small enough to teach and to enjoy.

## Where hosted sandboxes struggle (and where telvm leans)

Upstream issues are cited for **receipts**; telvm’s deeper scoreboard lives in [docs/wiki/README.md](../docs/wiki/README.md) and [telvm#16](https://github.com/telvm-hq/telvm/issues/16).

1. **Pause / resume reliability** — **Pain:** reported file loss across resume cycles and “zombie” processes hard to rediscover after resume on one stack; multi-hour **stuck “starting”** sandboxes on another. **telvm angle:** OTP **supervision trees** and Engine-backed lifecycle are the right semantic layer for stop/start truth. — [e2b-dev/E2B#884](https://github.com/e2b-dev/E2B/issues/884), [e2b-dev/E2B#1031](https://github.com/e2b-dev/E2B/issues/1031), [daytonaio/daytona#2390](https://github.com/daytonaio/daytona/issues/2390)

2. **Operator visibility** — **Pain:** API-only sandboxes push every team to reinvent observability; dashboards elsewhere still lag on deep links, persistence, and live event streams for agents. **telvm angle:** **LiveView** + **SSE** + warm-asset **explorer / logs** is already a differentiated operator surface—owned by you, on your Docker. — (see [#16](https://github.com/telvm-hq/telvm/issues/16) for citations)

3. **Secrets / credential brokering** — **Pain:** secrets copied **into** untrusted VM images risk exfiltration; client-side API keys for browser flows are another weak seam. **telvm angle:** **egress-level** injection (outbound HTTP gets headers the sandbox never holds) is a natural telvm-shaped hardening path. — [e2b-dev/E2B#1160](https://github.com/e2b-dev/E2B/issues/1160), [daytonaio/daytona#1930](https://github.com/daytonaio/daytona/issues/1930)

4. **Sandbox → client communication** — **Pain:** no first-class structured channel back to the orchestrator—stdout markers and ad hoc tunnels fill the gap. **telvm angle:** **PubSub + SSE** already exist; a structured “events up” path is a small conceptual leap, not a new platform. — [e2b-dev/E2B#646](https://github.com/e2b-dev/E2B/issues/646)

5. **Long-running tasks** — **Pain:** background PIDs vanish on short horizons; `kill` paths block; missing hooks for long jobs; gaps for startup tasks and MCP session ergonomics elsewhere. **telvm angle:** **GenServers**, explicit lifecycle, and streaming first—agent work as supervised processes, not accidental zombies. — [e2b-dev/E2B#1074](https://github.com/e2b-dev/E2B/issues/1074), [e2b-dev/E2B#1034](https://github.com/e2b-dev/E2B/issues/1034), [e2b-dev/E2B#1069](https://github.com/e2b-dev/E2B/issues/1069), [daytonaio/daytona#1982](https://github.com/daytonaio/daytona/issues/1982), [daytonaio/daytona#1912](https://github.com/daytonaio/daytona/issues/1912)

## Next steps (deliberately vague)

A **series of minigames** orbiting the same **cart-racing** fantasy—not a parallel product roadmap—could echo the five pains above in playful form (pit stops, telemetry boards, sealed fuel, pit-to-wall radio, endurance laps). **No specs, no dates:** if a mechanic teaches the lesson without a slide deck, it belongs here; if it needs a whitepaper, it belongs in the wiki or companion. **Receipts and long-form positioning:** [docs/wiki/README.md](../docs/wiki/README.md), [telvm#16](https://github.com/telvm-hq/telvm/issues/16).

---

**Today, this repo is:** a standalone Phoenix LiveView app for rendering markdown **guides** from the monorepo (not part of Companion).

## Run locally

```bash
cd speedeel
mix deps.get
mix assets.setup
mix phx.server
```

`mix assets.setup` runs Tailwind/esbuild installers and **`mix speedeel.npm`** (`npm install` in `assets/`, including **three.js** for the home-page circuit hook).

**Brand static files** (served at `/images/…`, not processed by esbuild): place **`speedeel_mascot_core.png`**, **`speedeel_double_checker.svg`**, and (later) a checker **GIF** under [`priv/static/images/`](priv/static/images/). A waving-flag GIF can replace the CSS footer chip when you add the file. If you author art under [`assets/speedeel_mascot_core.png`](assets/speedeel_mascot_core.png) (or variants), **copy** the file you want served into `priv/static/images/` so `/images/…` picks it up.

**Footer mark** [`priv/static/images/cursor-mark.svg`](priv/static/images/cursor-mark.svg): small decorative chevron next to “Built with Cursor”; not Cursor’s official logo—swap for an approved asset from [Cursor](https://cursor.com) if you need trademark-correct branding.

Open [http://localhost:4010](http://localhost:4010) — the index route is a **left nav + Three.js** panel (arrow keys or on-screen controls after focusing the track).

## Guides root

By default, guides are read from `../docs/events/diy-pawnshop-electric-cars` (relative to `speedeel/config/`).

Override with `TELVM_GUIDES_ROOT` (absolute path to a directory of `.md` files).

## Preflight (before Docker)

Run the same checks as Docker before `mix phx.server` (compile, `npm install` in `assets/`, Tailwind + esbuild), then **ExUnit in a subprocess with `MIX_ENV=test`** (so Mix stays happy while Esbuild stays `:dev`-only):

```bash
cd speedeel
mix deps.get
mix speedeel.preflight
```

Implementation: [`lib/mix/tasks/speedeel.preflight.ex`](lib/mix/tasks/speedeel.preflight.ex) (`mix speedeel.preflight`).

**Optional — stricter assets** (minify + `phx.digest`; keep default **`MIX_ENV=dev`** so Esbuild/Tailwind deps from `mix.exs` stay available):

```bash
cd speedeel
mix do compile, assets.deploy
```

A full **`MIX_ENV=prod`** asset pipeline would require promoting Esbuild/Tailwind (or a release image) to non-`:dev` deps; this app’s Docker dev path uses **`mix assets.build`** after `npm install` instead.

## Docker

From **this folder** (recommended for working only on guides):

```bash
docker compose up
```

From **repo root** (full stack, including Companion):

```bash
docker compose up speedeel
```

Service listens on **4010** and mounts repo `docs/` read-only at `/telvm-docs`, with `TELVM_GUIDES_ROOT=/telvm-docs/events/diy-pawnshop-electric-cars`. Compose sets **`SPEEDEEL_DOCKER=1`** so asset **watchers** and **code reloader** stay off inside the container (they often hang or fail with Docker bind mounts, especially from Windows).

First boot can take a minute while **`mix assets.setup`** runs. Check readiness with **`docker compose logs -f speedeel`** until you see the Endpoint listening line.

### Why `docker compose build --no-cache` did not fix `:none` / old Mix task errors

Compose **bind-mounts** `./speedeel` onto `/app`, so at runtime the **image’s old COPY of `lib/` is hidden** — the container always runs **your host tree** for sources. Separately, **`speedeel_build:/app/_build`** is a **named volume**: Elixir `.beam` files there can stay **stale** after you edit `lib/` on the host, so Mix can still execute an **old compiled** `Mix.Tasks.Speedeel.Npm` (e.g. the broken `env: :none` version) until `_build` is refreshed.

The entrypoint runs **`mix compile --force`** before **`mix assets.setup`** so task modules match the mounted source. If you still see ghosts, reset the volume once:

```bash
docker compose down
docker volume rm telvm_speedeel_build
docker compose up speedeel -d
```

(Project name may differ; use `docker volume ls | findstr speedeel` on Windows.)

See `docs/MONOREPO_GUIDES_PLAN.md` for the repo layout rationale.

## Draft PR (copy into GitHub)

**Title:** `speedeel: initial labs app (guides, circuit, positioning README)`

**Body** (copy everything inside this fence):

````markdown
## Summary

- Introduces **speedeel**: standalone Phoenix LiveView app on **:4010** for markdown **guides** (default `docs/events/diy-pawnshop-electric-cars`) and a **Three.js** home “circuit” for digital play—**physical + digital racing** as the north star, without replacing the companion control plane on **:4000**.

## What’s in this PR

- `speedeel/` Phoenix app: guide routes, sidebar + mascot frame, footer (Built with Cursor + telvm.com), prose styling for ASCII-heavy markdown.
- Repo **guides** under `docs/events/diy-pawnshop-electric-cars/` refactored toward **ASCII-first** fenced blocks where tables used to dominate.
- Static assets under `speedeel/priv/static/images/` (mascot, checker SVG, footer mark) plus optional authoring copy under `speedeel/assets/`.
- **README** refresh: ASCII banner, scope guard, upstream-issue “receipts” section with telvm angles, vague minigame roadmap hook, existing run / preflight / Docker docs preserved.

## Why

- Keeps **educational scope** small: guides + toy race UI. Competitive differentiation is **signposted** in README; deep dives stay in `docs/wiki/README.md` and telvm#16. **Minigames** are named only as a deliberately vague future direction—not a committed roadmap.

## How to verify

```bash
cd speedeel && mix deps.get && mix speedeel.preflight
mix phx.server
```

Then open http://localhost:4010 — home circuit + nav; open `/guides/pawnshop-procurement` (or another slug) for markdown + `<pre>` ASCII. Optional: `docker compose up speedeel` from repo root.

## Risks / follow-ups

- PNG assets increase repo size; keep “authoring in `assets/` → copy to `priv/static/images/`” documented in README.
- Footer `cursor-mark.svg` is explicitly non-official; swap if brand compliance requires it.
````
