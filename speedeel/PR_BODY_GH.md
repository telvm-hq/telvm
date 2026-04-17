## Summary

- Introduces **speedeel**: standalone Phoenix LiveView app on **:4010** for markdown **guides** (default `docs/events/diy-pawnshop-electric-cars`) and a **Three.js** home “circuit” for digital play—**physical + digital racing** as the north star, without replacing the companion control plane on **:4000**.

## What’s in this PR

- `speedeel/` Phoenix app: guide routes, sidebar + mascot frame, footer (Built with Cursor + telvm.com), prose styling for ASCII-heavy markdown.
- Repo **guides** under `docs/events/diy-pawnshop-electric-cars/` refactored toward **ASCII-first** fenced blocks where tables used to dominate.
- Static assets under `speedeel/priv/static/images/` (mascot, checker SVG, footer mark) plus optional authoring copy under `speedeel/assets/` (node_modules installed via npm in dev/CI; not committed).
- Root **docker-compose** service **`speedeel`**, **`docker/speedeel-entrypoint.sh`**, **`.dockerignore`** paths, **CI** job `speedeel (preflight)`, and pointers in **README** / **docs/quickstart.md**.

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
