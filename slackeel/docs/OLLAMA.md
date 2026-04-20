# Ollama — local inference utility (Slackeel)

**Category:** **utility** (OpenAI-compatible HTTP API). Slackeel’s Phoenix app will call `**GET …/v1/models`** and `**POST …/v1/chat/completions**` the same way any OpenAI-compatible client would. This document is **self-contained** in the Slackeel repo—you do **not** need the Telvm monorepo to run Ollama for development.

## Compose (this repo)


| Artifact            | Where                                                                                       | Notes                                                                           |
| ------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **Ollama (Phoenix on host)** | `[docker-compose.ollama-dev.yml](../docker-compose.ollama-dev.yml)` | **Ollama only** — use with `mix phx.server` under `server/` for hot reload. Same project name + volume as main compose. |
| **Container image** | `[docker-compose.yml](../docker-compose.yml)` `ollama` and `ollama_pull`                    | Pinned **semver** tag (not `:latest`).                                          |
| **Model manifest**  | `[manifest/models.json](../manifest/models.json)`                                           | Advertised Ollama names; `required: true` rows are checked by **model_doctor**. |
| **API contract**    | `**GET {base}/models`**, `**POST {base}/chat/completions**` with `base` ending in `**/v1**` | Matches common OpenAI-compatible servers.                                       |


Bump the image tag when you adopt a newer Ollama release; note it in [CHANGELOG.md](../CHANGELOG.md) if present.

## Model family catalog (Slackeel scope: five families)


| #   | Family      | Typical vendor | Notes                                                |
| --- | ----------- | -------------- | ---------------------------------------------------- |
| 1   | **Qwen**    | Alibaba Cloud  | Default smoke / Compose pull (`qwen2.5:0.5b`-class). |
| 2   | **Llama**   | Meta           | Llama 3.x / 4.x small instruct variants.             |
| 3   | **Gemma**   | Google         | Gemma 2 / 3 small instruct variants.                 |
| 4   | **Phi**     | **Microsoft**  | Phi-3 / Phi-4 class (see Ollama library).            |
| 5   | **Mistral** | Mistral AI     | E.g. Ministral / Mistral 7B-class.                   |


Details and disk planning: [MODEL_CATALOG.md](MODEL_CATALOG.md).

## Developer quickstart

**Prerequisites:** [Docker](https://docs.docker.com/get-docker/) with Compose v2.

**Working directory:** run all `docker compose` commands from the **Slackeel repo root** (the folder that contains `docker-compose.yml`). If you are in the **Telvm** monorepo parent directory, run `cd slackeel` first—otherwise Compose will not see `model_doctor` (it is **not** defined in Telvm’s top-level `docker-compose.yml`). Alternative: `docker compose -f slackeel/docker-compose.yml -p slackeel …` from the monorepo root.

For **local Phoenix + hot reload**, prefer **`docker-compose.ollama-dev.yml`** (Ollama only) and run **`mix phx.server`** in **`server/`** — see the **Local Phoenix (hot reload) + Ollama in Docker** section in [README.md](../README.md).

```bash
git clone <your-fork-or-upstream>/slackeel.git
cd slackeel
docker compose up -d ollama
docker compose up ollama_pull    # first run: downloads weights (can take several minutes)
./scripts/ollama/smoke-ollama.sh        # or smoke-ollama.ps1 on Windows
docker compose --profile doctor run --rm model_doctor   # verify manifest vs GET /v1/models
```

Ollama listens on `**http://127.0.0.1:11434**`. OpenAI-compatible base URL for app config: `**http://127.0.0.1:11434/v1**` (or `http://ollama:11434/v1` from another container on the same Compose network).

## Model manifest + `model_doctor` (Docker)

`[manifest/models.json](../manifest/models.json)` lists every **advertised** Ollama name. Entries with `**"required": true`** must appear in `**GET /v1/models**` after you pull them (the API only lists models present on disk).

The `**model_doctor**` service (Compose **profile `doctor`**, defined only in **this** repo’s `[docker-compose.yml](../docker-compose.yml)`) builds a tiny Alpine image with **curl** + **jq**, mounts the manifest, and:

1. Waits for `**/v1/models`**.
2. Fails if any **required** id is missing from the response (run `**ollama_pull`** or `ollama pull` first).
3. Prints **SKIP** for optional rows that are not pulled.
4. If `**DOCTOR_CHAT=1`**, sends a minimal `**POST /v1/chat/completions**` for each **required** model (slower; exercises inference).

```bash
docker compose --profile doctor run --rm model_doctor
DOCTOR_CHAT=1 docker compose --profile doctor run --rm model_doctor
```

`model_doctor` is **not** started by plain `**docker compose up`** so a cold stack does not fail before `**ollama_pull**` completes.

**Port `11434` already in use** (for example Telvm’s `docker compose` Ollama): the doctor service **does not** `depends_on` Slackeel’s `ollama` container, so Compose will not try to bind a second listener. By default **`OLLAMA_HOST=http://host.docker.internal:11434`** (with `extra_hosts: host-gateway`) so the check hits **whatever is serving on the host** at 11434. To target the in-compose DNS name instead: `OLLAMA_HOST=http://ollama:11434 docker compose --profile doctor run --rm model_doctor` (only after `docker compose up -d ollama` on the **same** project network).

## Update cadence (maintainers)


| Trigger                  | Action                                            |
| ------------------------ | ------------------------------------------------- |
| **Quarterly**            | Review Ollama release notes; consider image bump. |
| **CVE / breaking `/v1`** | Bump pinned image; run smoke scripts.             |


## Smoke test

**Goal:** verify the HTTP surface before/after an image pin change.

1. `**GET /v1/models`** — HTTP 200, JSON with `data` array.
2. `**POST /v1/chat/completions**` — HTTP 200, JSON with `choices[0].message.content`.

**Default model** for step 2: `qwen2.5:0.5b` (pulled by `ollama_pull`). Override with `OLLAMA_SMOKE_MODEL`.


| Variable             | Default                     | Meaning                                                     |
| -------------------- | --------------------------- | ----------------------------------------------------------- |
| `OLLAMA_SMOKE_BASE`  | `http://127.0.0.1:11434/v1` | Must include `**/v1`**.                                     |
| `OLLAMA_SMOKE_MODEL` | `qwen2.5:0.5b`              | Must exist on disk (`ollama_pull` or manual `ollama pull`). |


### Windows (PowerShell)

```powershell
./scripts/ollama/smoke-ollama.ps1
```

### Troubleshooting: connection refused

Nothing listens on `**127.0.0.1:11434**` until `**docker compose up -d ollama**` has completed. Run `**docker compose up ollama_pull**` before smoke if you need weights. See script output for hints.

### From another container on the same Compose project

```bash
OLLAMA_SMOKE_BASE=http://ollama:11434/v1 ./scripts/ollama/smoke-ollama.sh
```

## Relation to Telvm

The [Telvm](https://github.com/telvm-hq/telvm) monorepo may carry a **parallel** Ollama utility doc for Companion; behavior and pins should stay aligned when both repos are updated. Slackeel remains **cloneable and runnable alone** using **this** `docker-compose.yml` and **this** doc.

## Revision log


| Date       | Change                                                                                                |
| ---------- | ----------------------------------------------------------------------------------------------------- |
| 2026-04-19 | Self-contained Compose + doc + scripts in Slackeel repo.                                              |
| 2026-04-19 | `manifest/models.json` + `**model_doctor`** (Compose profile `doctor`) for manifest checks in Docker. |


