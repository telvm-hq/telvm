# Ollama integration verification

## Canonical path (script / Mix)

Use the **CLI** for deterministic, repeatable checks. The Pre-flight LiveView button is optional manual QA.

By default the task **pulls** each manifest model via Ollama `POST /api/pull` (so weights do not need to exist beforehand), then **probes** with `POST /v1/chat/completions`, then **unloads** each model from VRAM with native `POST /api/chat` (`messages: []`, `keep_alive: 0`). Opt out with `--skip-pull` / `--skip-unload` if you manage disk or memory yourself.

**Working directory:** Mix must run where `mix.exs` lives — **`slackeel/server`**. From repo root or `slackeel/`, use the wrappers below instead of calling `mix` in the wrong folder.

From `slackeel/server`:

```bash
mix slackeel.verify_ollama
# or
mix verify_ollama
```

From **`slackeel/`** (same args as Mix):

- `./verify-ollama.sh` (Unix)
- `.\verify-ollama.ps1` (Windows PowerShell)

Or from **`slackeel/scripts/ollama/`** (forwards args to Mix):

- `verify-all-models.sh` (Unix)
- `verify-all-models.ps1` (Windows)

Options:

- `--parallel N` — max concurrent Ollama requests in phased mode (default from `config :slackeel, :integration_verify_max_parallel` in `server/config/config.exs`).
- `--retries N` — attempts per model, with backoff on retryable errors (HTTP 429/502/503/504, transport timeouts, connection refused, etc.). **Not** used for HTTP 404 (missing model).
- `--manifest PATH` — override `manifest/models.json` (otherwise `config :slackeel, :manifest_path`).
- `--model NAME` — probe **only** this Ollama tag (ignores the manifest list; use for troubleshooting one failure).
- `--verbose` / `-v` — log `POST` URL, timeout, user-message preview, full HTTP error bodies, and on 404 a hint: `ollama pull NAME` (all on stderr).
- `--json` — print a JSON summary (exit code 0 = all OK, 1 = any failure).
- `--skip-pull` — skip `POST /api/pull` (probe only; requires models already on disk).
- `--skip-unload` — skip the final VRAM unload pass.
- `--pull-parallel N` — concurrent pulls (default **1**; large downloads are usually best serialized).

Tuning: edit `server/config/config.exs` (`:ollama_base_url`, `:ollama_chat_timeout_ms`, `:ollama_pull_timeout_ms`, `:integration_verify_max_parallel`, `:integration_verify_prompt`, etc.). No `.env` required.

Implementation: `Slackeel.Ollama.VerifyRunner` (orchestration), `Slackeel.Ollama.IntegrationVerify.probe/1` (single model), `Slackeel.Ollama.Chat` (HTTP).

---

## Original LiveView plan (5-step implementation plan)

This is the plan used to add **Run chat probe on all models** on the Pre-flight LiveView.

1. **Configuration** — Add `SLACKEEL_OLLAMA_BASE_URL` (default `http://127.0.0.1:11434`), chat timeout, **`SLACKEEL_VERIFY_MAX_PARALLEL`** (default `3`), and **`SLACKEEL_INTEGRATION_VERIFY_PROMPT`** (overridable probe text). Keeps behavior tunable for small vs large hosts.

2. **HTTP client** — Implement `Slackeel.Ollama.Chat.completion/2` using `Req` + `Finch` against `POST /v1/chat/completions`, parsing assistant `content` and API errors.

3. **Probe wrapper** — `Slackeel.Ollama.IntegrationVerify.probe/1` sends one user message (the configured prompt) and returns `{:ok, text}` or `{:error, _}`.

4. **Parallel orchestration** — On button click, collect manifest Ollama names, initialize each row as `:running`, spawn a background task that runs `Task.async_stream(..., max_concurrency: N, ordered: false)` so at most **N** models hit Ollama at once. Each completion `send`s to the LiveView process; a final `:verify_complete` clears the running flag.

5. **LiveView UI** — Section with disabled-while-running button, per-model status badges, error text or reply `<pre>` (scroll-limited). Copy explains parallel cap and env overrides.

See runtime config in `server/config/runtime.exs` and modules under `server/lib/slackeel/ollama/`.

## Troubleshooting

- **`scheme is required for url: /v1/chat/completions`** — Usually means `SLACKEEL_OLLAMA_BASE_URL` was set to an **empty** value. In Elixir, `"" || default` still yields `""`, so Req only saw a path. Unset the variable or set a full URL (e.g. `http://127.0.0.1:11434`). The app now treats `nil` and `""` as “use default,” and `Slackeel.Ollama.Chat` defends against missing `http(s)://`.
