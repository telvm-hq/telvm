# feat(api): container logs via Engine + GET /telvm/api/machines/:id/logs

## Summary

Adds `container_logs/2` to `Companion.Docker` with HTTP (Finch → Docker socket) implementation: Engine `GET /containers/{id}/logs` with stdout+stderr multiplex demux, tail cap, and mock + tests. Exposes **`GET /telvm/api/machines/:id/logs?tail=`** (JSON `%{logs: text}`) aligned with existing stats/error patterns. Updates **`fyi.md`** (route table, trust note for secrets in logs).

Also includes related **machine API** additions present on the integration branch (restart, stats, pause/unpause) and matching **`machine_controller_test`** coverage where applicable.

## Files

- `companion/lib/companion/docker.ex`, `docker/http.ex`, `docker/mock.ex`
- `companion/lib/companion_web/machine_controller.ex`, `router.ex`
- `companion/priv/static/fyi.md`
- `companion/test/companion/docker_mock_test.exs`, `machine_controller_test.exs`

## How to test

- `mix compile --warnings-as-errors`
- `mix test` (with `TEST_DATABASE_URL` / Postgres as in `config/test.exs`), or `docker compose --profile test run --rm companion_test`

## Follow-up

Operator UI (Warm assets logs panel, theme) lands in a separate PR stacked after this merges.
