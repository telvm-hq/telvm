#!/usr/bin/env sh
# Minimal Ollama HTTP smoke: GET /v1/models + POST /v1/chat/completions.
# See docs/utilities-ollama.md — not a closed-agent check.
set -e

BASE="${OLLAMA_SMOKE_BASE:-http://127.0.0.1:11434/v1}"
MODEL="${OLLAMA_SMOKE_MODEL:-qwen2.5:0.5b}"

# Normalize to .../v1 (match Companion.InferencePreflight)
BASE=$(echo "$BASE" | sed 's/[[:space:]]//g' | sed 's|/*$||')
case "$BASE" in
  */v1) ;;
  *) BASE="${BASE}/v1" ;;
esac

echo "telvm: Ollama utility smoke"
echo "  base:  $BASE"
echo "  model: $MODEL"
echo ""

echo "Step 1: GET $BASE/models"
if ! curl -sS -f --max-time 30 -H "accept: application/json" "$BASE/models" >/dev/null; then
  echo "FAIL: cannot reach $BASE (connection refused?)" >&2
  echo "" >&2
  echo "Start Ollama first from repo root:  docker compose up -d ollama" >&2
  echo "Then pull models:                   docker compose up ollama_pull" >&2
  echo "Or full stack:                     docker compose up --build" >&2
  exit 1
fi
echo "  OK"

echo "Step 2: POST $BASE/chat/completions"
BODY_JSON=$(printf '{"model":"%s","messages":[{"role":"user","content":"ping"}],"stream":false}' "$MODEL")

RESP=$(curl -sS -f --max-time 120 -X POST "$BASE/chat/completions" \
  -H "content-type: application/json" \
  -H "accept: application/json" \
  -d "$BODY_JSON") || {
  echo "FAIL: chat completion request failed (model pulled? try: docker compose run --rm ollama_pull or ollama pull $MODEL)" >&2
  exit 1
}

case "$RESP" in
  *'"choices"'*) echo "  OK (response contains choices)" ;;
  *)
    echo "FAIL: unexpected JSON shape" >&2
    echo "$RESP" | head -c 400 >&2
    exit 1
    ;;
esac

echo ""
echo "telvm: Ollama utility smoke PASSED"
