# The Hospitality Catacombs — minigames planning (speedeel)

Welcome, valued guest. This document is the **canonical** home for how we host our little underground tour—**versioned in `speedeel/docs/`**, not in a temp folder, not in a slide deck nobody opens. We keep the tone **soft as marshmallow** and the premise **firm as bedrock**: each chamber is a tiny videogame-shaped thank-you note to named product directions we *are* happy to cite or caricature fairly.

**Who gets a nameplate here:** **Daytona**, **E2B**, **Modal**, **Loft Labs** (vCluster / nested tenancy), then **Lovable**, **GitHub Codespaces**, **Gitpod** / **Coder**, **Runloop**, **hyperscaler** notebook stacks, and **edge** / **Workers**-style isolates. *Egress-shaped hardening* stays a telvm product story (Companion), not a fourth “guest” with a cap table. **Replit** is **not** on the catacombs guest list—do not add it under `speedeel/`; if it appears elsewhere in the monorepo, that is outside this folder’s jurisdiction.

## What we are building (sweetly)

- **`GET /`** stays the **bright showroom**: your existing **Three.js** circuit (`SpeedeelRace` hook)—unchanged, friendly, “look, a toy car.”
- **`GET /minigames`** is the **Hospitality Catacombs**: a **2D pixel dungeon** shell—orthographic Three.js, limited palette, `SpeedeelDungeon` hook—where we hang **ten** themed chambers over time. Act I ships first as design + stub; gameplay arrives in polite increments.

Investors and PMs from **Daytona**, **E2B**, **Modal**, and **Loft Labs** are invited to read this as **hospitality documentation**. If the copy makes your stomach do a little flip, that is merely the complimentary **torchlight dramamine** kicking in.

## Routing (for implementers)

| Route | LiveView | Mood |
|-------|-----------|------|
| `/` | `GuidesLive.Index` | Sunlit circuit, 3D |
| `/minigames` | `MinigamesLive.Index` | Catacombs, 2D pixel stage |
| `/guides/:slug` | `GuidesLive.Show` | Markdown library |

Nav: left rail gains a **guest map** link to the catacombs; active states use `nav_active` (`:circuit` \| `:minigames` \| `{:guide, slug}`).

## Optional Elixir catalog (later)

When you add `Speedeel.Minigames`, keep `@moduledoc` in the same voice: educational satire, not legal advice. Point to [telvm wiki](../../docs/wiki/README.md) and [telvm#16](https://github.com/telvm-hq/telvm/issues/16) for receipts where Daytona/E2B threads already live in the parent README.

## Execution checklist

- [x] Router: `live "/minigames", MinigamesLive.Index, :index`
- [x] `MinigamesLive.Index` + dungeon shell + `SpeedeelDungeon` mount
- [x] `guides_nav` + `nav_active`
- [x] CSS variables under `.speedeel-dungeon-root`
- [x] `assets/js/hooks/dungeon_stage.js` + `app.js` merge
- [ ] `Speedeel.Minigames` modules (deferred—docs-first wave landed UI)
- [ ] Playable chambers (Phase B/C per engine doc)

## Related

- [MINIGAMES_ENGINE_PLAN.md](MINIGAMES_ENGINE_PLAN.md) — palette, physics contract, ten chambers table
- [speedeel README](../README.md) — receipts cluster for hosted sandboxes
- [docs index](README.md)
