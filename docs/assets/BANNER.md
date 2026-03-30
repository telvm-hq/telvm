# README / social banner (Canva)

- **Mermaid + Simple Icons:** accurate host layout (companion peer to Engine, not “inside” Docker) lives in [`ARCHITECTURE-DIAGRAM.md`](ARCHITECTURE-DIAGRAM.md); the README embeds a short Mermaid overview and links there for the full diagram and icon row.
- Export a **wide hero** for the GitHub README as **`telvm-banner.png`** (or replace `telvm-banner.svg`) in this folder. Suggested width **920–1200 px**; height **~360–480 px** works well above the fold.
- **Story to show:** one **localhost:4000** entrypoint with **two clear client lanes** merging into the **companion**:
  - **Browser** → LiveView dashboard + Preview **`/app/…`** + Explorer **`/explore/…`**
  - **Agents / automation** → **`/telvm/api`** (JSON + SSE)
  Then **Docker Engine**, **N containers**, and how **`/app/<container>/port/<n>/…`** maps preview traffic to the bridge (see [Architecture](../../ARCHITECTURE.md) ASCII).
- **Repository social preview** (link unfurls): **1280×640** — see [`SOCIAL_PREVIEW.md`](SOCIAL_PREVIEW.md).
