# Guides / labs Phoenix app — monorepo placement

See also the [speedeel docs index](README.md) (minigames planning, engine brief).

## Decision

**Option A — top-level sibling app** (this repo: `speedeel/` next to `companion/`).

### Pros

- Clear deployable surface: its own `mix.exs`, own Docker/Compose service, own release story.
- Matches the product split: **run beside Companion, not inside the dashboard**.
- Common pattern for a small monorepo with multiple web surfaces (Companion + docs/labs).

### Cons

- Another app to CI and version.
- Some duplication of Phoenix boilerplate vs Companion.

## Implementation notes (this repo)

- **Port**: `4010` locally and in Compose (`PORT` / `SpeedeelWeb.Endpoint`).
- **Markdown**: `Earmark` renders `.md` from a configurable directory (`TELVM_GUIDES_ROOT`, defaulting to `docs/events/diy-pawnshop-electric-cars`).
- **Compose**: `speedeel` service builds `speedeel/Dockerfile` with repo-root context; bind-mounts `./speedeel` for dev iteration; read-only `./docs` mount for guide content.

## Alternatives considered

- **Inside Companion**: faster to ship, but couples labs to dashboard auth, deploy cadence, and UI chrome — rejected for this use case.
- **Static site generator only**: great for pure docs, weaker for interactive labs later.
