# Ollama — utility runtime (not closed-agent)

**Category:** **utility** (local OpenAI-compatible inference). This is **not** part of [closed-agent-upstream-submodule-policy.md](closed-agent-upstream-submodule-policy.md) or the closed-vendor harness.

## Model family catalog (telvm scope: five families)

We standardize on **five upstream families** for small / CPU-friendly models in docs, smoke defaults, and future UI lists. Exact **`ollama pull`** names change with registry updates; treat this table as **governance**, not a hardcoded manifest.

| # | Family | Typical vendor | Notes |
|---|--------|----------------|--------|
| 1 | **Qwen** | Alibaba Cloud | Default smoke / Compose default model (`qwen2.5:0.5b`-class). |
| 2 | **Llama** | Meta | Llama 3.x / 4.x small instruct variants as published in Ollama. |
| 3 | **Gemma** | Google | Gemma 2 / 3 small instruct variants. |
| 4 | **Phi** | **Microsoft** | Phi-3, Phi-4, and related small **Microsoft** instruct models (see [Azure AI / Phi](https://azure.microsoft.com/en-us/products/phi) and Ollama library names). |
| 5 | **Mistral** | Mistral AI | Small instruct models (e.g. Ministral / Mistral 7B-class) for diversity in regression tests. |

**Operational reality:** Ollama loads **one (or a few) models at a time** from disk; tracking five **families** does not mean keeping five large weights resident—only what you `pull` and invoke.

## What telvm pins

| Artifact | Where | Notes |
|----------|--------|--------|
| **Container image** | [`docker-compose.yml`](../docker-compose.yml) `ollama` and `ollama_pull` `image:` | Pinned **semver** tag (not `:latest`) for reproducible pulls. |
| **API contract** | Companion expects OpenAI-compatible **`GET …/v1/models`** and **`POST …/v1/chat/completions`** | Same as [`Companion.InferencePreflight`](../companion/lib/companion/inference_preflight.ex) / [`Companion.InferenceChat`](../companion/lib/companion/inference_chat.ex). |

Bump the image tag when you intentionally adopt a newer Ollama release; record the change in [CHANGELOG.md](CHANGELOG.md).

## Update cadence (minimal effort)

| Trigger | Action |
|---------|--------|
| **Calendar** | Review **quarterly** (security notes + upstream release notes). |
| **CVE / urgent fix** | Bump the pinned tag when upstream publishes a fix you need. |
| **Breaking `/v1` behavior** | If `GET /v1/models` or non-streaming `POST /v1/chat/completions` changes, bump pin and run the smoke below; fix Companion only if the contract truly diverges. |

## Smoke test (required before/after a pin bump)

**Goal:** prove the **HTTP surface** Companion uses — not full model quality.

1. **`GET /v1/models`** — HTTP 200 and JSON with a `data` array (OpenAI-style list).
2. **`POST /v1/chat/completions`** — HTTP 200, JSON with `choices[0].message.content` (non-streaming).

**Default model** for step 2: whatever you already pull in Compose (`qwen2.5:0.5b` by default in [`docker-compose.yml`](../docker-compose.yml) `ollama_pull`). Override with `OLLAMA_SMOKE_MODEL` if needed.

### From the repo root (host has `curl`)

With Compose up and Ollama listening on **localhost:11434**:

```bash
./scripts/smoke-ollama.sh
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `OLLAMA_SMOKE_BASE` | `http://127.0.0.1:11434/v1` | OpenAI-compatible base **including `/v1`**. |
| `OLLAMA_SMOKE_MODEL` | `qwen2.5:0.5b` | Model id for one chat completion (must exist — run `ollama_pull` or `ollama pull` first). |

### Windows (PowerShell)

```powershell
./scripts/smoke-ollama.ps1
```

Same environment variables.

### Troubleshooting: connection refused (Windows / Linux)

**Symptom:** `No connection could be made because the target machine actively refused it` (or equivalent) on **`127.0.0.1:11434`**.

**Cause:** The smoke script talks to **localhost:11434**. Nothing is listening until the **`ollama`** Compose service is up and publishes that port.

**Fix (from repo root):**

```bash
docker compose up -d ollama
docker compose up ollama_pull
```

(`ollama_pull` is one-shot; first run downloads weights and can take several minutes.) Or bring up the full stack: `docker compose up --build`. Then rerun **`./scripts/smoke-ollama.ps1`** or **`./scripts/smoke-ollama.sh`**.

If Ollama runs on another host or port, set **`OLLAMA_SMOKE_BASE`** (must include **`/v1`**, e.g. `http://192.168.1.10:11434/v1`).

### Inside Docker (optional)

From a shell that can reach the **`ollama`** service on the Compose network:

```bash
OLLAMA_SMOKE_BASE=http://ollama:11434/v1 ./scripts/smoke-ollama.sh
```

## Revision log

| Date | Change |
|------|--------|
| 2026-04-19 | Initial utility policy + smoke scripts; Compose **`ollama/ollama:0.20.5`** pin (see [`docker-compose.yml`](../docker-compose.yml)). |
| 2026-04-19 | **Five-family** catalog: Qwen, Llama, Gemma, **Phi (Microsoft)**, Mistral. |
