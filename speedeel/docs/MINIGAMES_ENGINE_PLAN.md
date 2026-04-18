# Catacombs engine — theme, ten chambers, 2D Three.js

Companion to [MINIGAMES.md](MINIGAMES.md). Edit here **before** you grow gameplay logic; keep the circuit on `/` and the dungeon on `/minigames` mentally separate.

## Series theme

**The Hospitality Catacombs** — a gentle underground orientation for **distinguished infrastructure guests**. Each **chamber** (minigame) teaches exactly one **custody** lesson: who owns **start/stop truth**, **observable reality**, **burst economics**, **nested tenancy**, and friends. Lap times are optional garnish.

## Act I funding lens (why the fourth seat moved)

Act I names **four funded infra guests** we caricature directly. **“Egress”** is a telvm *design pattern*, not a Series A character with a GitHub org—so it was a weak fourth plaque. **Loft Labs** (~**$28.6M** raised to date, including a **$24M Series A** in 2024 per [Business Wire](https://www.businesswire.com/news/home/20240416839215/en/Loft-Labs-Inventors-of-Virtual-Kubernetes-Clusters-Raises-%2424-Million-Series-A)) sits in the **~$20–100M** venture band we care about here. **Runloop** is a strong *sandbox / devbox* story but still **seed-scale** (~**$7M** per [Runloop press](https://runloop.ai/media/runloop-raises-7m-seed-round-to-bring-enterprise-grade-infrastructure-to-ai-agents))—so Runloop stays in **Act II**, not the honored quartet.

## Ten chambers (full guest list)

Act I is **Daytona**, **E2B**, **Modal**, **Loft Labs**; Act II–III adds the rest without repeating the same punchline. **Replit** is intentionally **absent** from all speedeel minigames copy and UI; do not add it.

| # | Guest (public) | Chamber name | One-line lesson |
|---|----------------|--------------|-----------------|
| 1 | Daytona | *The Long Nap Hallway* | Pit / resume **trust** vs lifecycle you own |
| 2 | E2B | *The Telemetry Tea Party* | API fog vs **operator-visible** truth |
| 3 | Modal | *The Burst Candy Shop* | Rented **seconds** vs supervised continuity on your metal |
| 4 | Loft Labs (vCluster) | *The Nested Keep* | Nested control planes vs **Engine-flat** custody |
| 5 | Lovable (archetype) | *The Purple Confetti Closet* | Vibes vs **verify + containers** |
| 6 | GitHub Codespaces | *The Deep-Link Maze* | Port-forward ceremony vs **path preview** on your host |
| 7 | Gitpod / Coder-class | *The Ephemeral Foyer* | Workspace SaaS vs **Compose-first** custody |
| 8 | Runloop | *The Devbox Annex* | Agent devboxes vs **your** lifecycle truth |
| 9 | Hyperscaler notebooks | *The Notebook Nursery* | Managed ML sandboxes vs **exec + logs + sidecars** |
| 10 | Edge isolates (Workers-style) | *The Coldstart Cloister* | Isolate **burst** vs long-lived Engine truth |

**Receipts:** Daytona and E2B threads stay anchored in [speedeel README](../README.md). On **`/minigames`**, Act I cards link **three GitHub issues each**: Modal receipts are pulled from **currently open** [modal-labs/modal-examples issues](https://github.com/modal-labs/modal-examples/issues); Loft Labs from **open** [loft-sh/vcluster issues](https://github.com/loft-sh/vcluster/issues). Keep long-form positioning in the wiki; this UI is receipts-only.

## Two halls, one dependency graph

| Hall | Route | Renderer | Notes |
|------|-------|-----------|-------|
| Showroom | `/` | `SpeedeelRace` | Existing 3D loop—do not refactor for dungeon work |
| Catacombs | `/minigames` | `SpeedeelDungeon` | New orthographic **pixel** stage |

Both use **Three.js** from the same `npm` graph—no second renderer stack.

## Unified JS contract (`chamber_id`)

Grow from a single profile enum (implementation detail):

- `chamber_id`: `:daytona | :e2b | :modal | :loft_labs | :lovable | :codespaces | :gitpod_coder | :runloop | :notebooks | :edge_cloister` (atoms or strings in JS). No `:replit` slot.

Shared entry shape (document now, implement per chamber later):

```text
createChamber({ mountEl, chamberId, onEnd })
```

Each chamber supplies **data**: palette overrides, hazard density, HUD copy, timer curves—**one physics core**, many polite pamphlets.

## Physics strategy (2D, pixel-forward)

- **Camera:** `OrthographicCamera`, integer-friendly world units (tile **16** recommended).
- **Collision:** circles / AABBs in the drive plane; **hand-rolled** first—**no new npm deps** for v1.
- **Pixel look:** outer wrapper uses CSS variables below + `image-rendering: pixelated` on the canvas; optional **low internal resolution** (e.g. 320×180) scaled up with `setSize(internalW, internalH)` then CSS `width: 100%` for crunch.

Escalation (only if needed): evaluate Rapier or Matter.js in a **separate** decision—never block the catacombs’ opening night.

## Palette appendix (CSS variables)

Defined on `.speedeel-dungeon-root` (see `assets/css/app.css`). **Display names** are sweet; **roles** are honest.

| Variable | Friendly name | Role |
|----------|---------------|------|
| `--dungeon-molasses` | molasses | Deep void background |
| `--dungeon-peach-pit` | peach pit | Stone panels / walls |
| `--dungeon-warm-milk` | warm milk | Highlights / torch bloom |
| `--dungeon-sour-honey` | sour honey | Accent danger / “please mind the gap” |
| `--dungeon-old-gold` | old gold | Coins / pick-ups (later) |
| `--dungeon-lichen` | lichen | Muted UI chrome |

Hex values live in CSS so designers can tweak without spelunking TypeScript.

## Phased delivery

1. **Phase A (now):** `/minigames` shell + dungeon hook stub + docs + palette.
2. **Phase B:** One **template** chamber (`chamber_id` fixed) proving mount/destroy/focus.
3. **Phase C:** Reskin + copy for quartet, then roll forward through six.
