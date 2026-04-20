# Manifest

| File | Role |
|------|------|
| [`models.json`](models.json) | Advertised **Ollama** model names; **`required: true`** entries must appear in `GET /v1/models` after pull. Currently only **`qwen2.5:0.5b`** is required; **`tinyllama`** is optional (often pulled by `ollama_pull` but your host Ollama may only have Qwen). |

Validated by **`docker compose --profile doctor run --rm model_doctor`** (see [docs/OLLAMA.md](../docs/OLLAMA.md)).

Keep in sync with [docs/MODEL_CATALOG.md](../docs/MODEL_CATALOG.md).
