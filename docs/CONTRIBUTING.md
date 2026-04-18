# Contributing

Thanks for helping improve telvm. This document covers how to work on the repo and what maintainers configure on GitHub.

## Principles

- **Private planning** belongs outside the public tree. The repo [`.gitignore`](../.gitignore) excludes `.internal/` — do not `git add -f` paths under `.internal/`.
- Prefer **small, focused PRs** with a clear description of behavior change.
- Match existing **formatting and naming** in Elixir and HEEx; run the project’s usual checks before pushing.
- **Unfinished or “someone should fix this” work** is tracked in [wiki/BACKLOG.md](wiki/BACKLOG.md) (not buried in README).

## Development setup

- **Docker (recommended):** [quickstart.md](quickstart.md) — `docker compose up --build`, tests via `docker compose --profile test run --rm companion_test`.
- **Local Elixir:** from `companion/`, `mix setup` then `mix phx.server` with Postgres as in `config/dev.exs`.

### Git submodules (closed-agent upstream trees)

The repo pins **`third_party/claude-code`** and **`third_party/codex`** ([policy](closed-agent-upstream-submodule-policy.md)). After clone, run:

```bash
git submodule update --init --recursive
```

CI workflows that build those images use **`actions/checkout` with `submodules: recursive`**. If submodule directories are empty, local **`docker build -f images/telvm-closed-*/Dockerfile .`** still works (Dockerfiles install from npm), but you will miss upstream reference files until submodules are initialized.

## Before you open a PR

1. Run the **full test suite** the same way CI does (Docker Compose command above), or `mix test` from `companion/` with `TEST_DATABASE_URL` / Postgres configured.
2. If you change Elixir code, run **`mix format`** under `companion/` when applicable.

## CI and branch protection (maintainers)

After [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) has a **green** run on `main`:

1. **Settings → Rules → Rulesets** (or **Branches → Branch protection rules**): protect `main`.
2. Require **pull requests** before merging.
3. Require status check **`ci`** (job name in the workflow) to pass.

This keeps `main` aligned with the canonical Docker test command.

## Social preview image (maintainers)

See [`assets/SOCIAL_PREVIEW.md`](assets/SOCIAL_PREVIEW.md) for **1280×640** GitHub social preview dimensions and where to upload.

## Releases

1. Tag from the commit you intend to ship: `git tag -a v0.1.0 -m "Release notes summary"`.
2. Push the tag: `git push origin v0.1.0`.
3. On GitHub: **Releases → Draft a new release**, choose the tag, add notes (high-level changes, upgrade steps if any). Draft text examples: [`releases/v0.1.0.md`](releases/v0.1.0.md), [`releases/v1.1.0.md`](releases/v1.1.0.md). For a docs-only PR that ships these notes, see [`releases/PR_BODY_v1.1.0.md`](releases/PR_BODY_v1.1.0.md). Index of maintainer artifacts in this folder: [`releases/README.md`](releases/README.md).

## Labels

Maintainers can use **`good first issue`** for small, well-scoped tasks to welcome new contributors.

## Code of conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). Report concerns to maintainers via channels they designate (see [SECURITY.md](SECURITY.md) for sensitive issues).
