# Contributing

Thanks for helping improve telvm. This document covers how to work on the repo and what maintainers configure on GitHub.

## Principles

- **Private planning** belongs outside the public tree. The repo [`.gitignore`](.gitignore) excludes `.internal/` — do not `git add -f` paths under `.internal/`.
- Prefer **small, focused PRs** with a clear description of behavior change.
- Match existing **formatting and naming** in Elixir and HEEx; run the project’s usual checks before pushing.

## Development setup

- **Docker (recommended):** [docs/quickstart.md](docs/quickstart.md) — `docker compose up --build`, tests via `docker compose --profile test run --rm companion_test`.
- **Local Elixir:** from `companion/`, `mix setup` then `mix phx.server` with Postgres as in `config/dev.exs`.

## Before you open a PR

1. Run the **full test suite** the same way CI does (Docker Compose command above), or `mix test` from `companion/` with `TEST_DATABASE_URL` / Postgres configured.
2. If you change Elixir code, run **`mix format`** under `companion/` when applicable.

## CI and branch protection (maintainers)

After [`.github/workflows/ci.yml`](.github/workflows/ci.yml) has a **green** run on `main`:

1. **Settings → Rules → Rulesets** (or **Branches → Branch protection rules**): protect `main`.
2. Require **pull requests** before merging.
3. Require status check **`ci`** (job name in the workflow) to pass.

This keeps `main` aligned with the canonical Docker test command.

## Social preview image (maintainers)

See [`docs/assets/SOCIAL_PREVIEW.md`](docs/assets/SOCIAL_PREVIEW.md) for **1280×640** GitHub social preview dimensions and where to upload.

## Releases

1. Tag from the commit you intend to ship: `git tag -a v0.1.0 -m "Release notes summary"`.
2. Push the tag: `git push origin v0.1.0`.
3. On GitHub: **Releases → Draft a new release**, choose the tag, add notes (high-level changes, upgrade steps if any). Draft text for **v0.1.0** lives in [`docs/releases/v0.1.0.md`](docs/releases/v0.1.0.md) for copy-paste.

## Labels

Maintainers can use **`good first issue`** for small, well-scoped tasks to welcome new contributors.

## Code of conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). Report concerns to maintainers via channels they designate (see [SECURITY.md](SECURITY.md) for sensitive issues).
