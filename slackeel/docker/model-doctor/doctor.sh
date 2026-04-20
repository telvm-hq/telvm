#!/bin/bash
# Verify manifest models are listed by Ollama OpenAI-compatible API (implies pulled locally).
# Optional: DOCTOR_CHAT=1 runs one non-streaming chat completion per required model.
set -e

MANIFEST="${MANIFEST:-/manifest/models.json}"
HOST="${OLLAMA_HOST:-http://ollama:11434}"
BASE="${HOST%/}/v1"

echo "slackeel model-doctor"
echo "  manifest: $MANIFEST"
echo "  Ollama:   $HOST"
echo ""

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: need curl and jq" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "FAIL: manifest not found: $MANIFEST" >&2
  exit 1
fi

echo "Waiting for Ollama API..."
i=0
while [ "$i" -lt 120 ]; do
  if curl -sS -f --max-time 5 -H "accept: application/json" "$BASE/models" -o /tmp/models.json 2>/dev/null; then
    echo "  API ready."
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$i" -eq 120 ]; then
  echo "FAIL: timeout waiting for $BASE/models" >&2
  exit 1
fi

fail=0
echo ""
echo "Checking required models (must appear in GET /v1/models)..."
while IFS= read -r line; do
  name=$(echo "$line" | jq -r '.ollama')
  fam=$(echo "$line" | jq -r '.family')
  req=$(echo "$line" | jq -r '.required')
  if [ "$req" != "true" ]; then
    continue
  fi
  if jq -e --arg m "$name" 'any((.data // [])[]; .id == $m)' /tmp/models.json >/dev/null 2>&1; then
    echo "  OK  [$fam] $name"
  else
    echo "  FAIL [$fam] $name — not listed. Pull with: ollama pull $name (or: docker compose up ollama_pull)" >&2
    fail=1
  fi
done <<EOF
$(jq -c '.models[]' "$MANIFEST")
EOF

echo ""
echo "Optional models (warning only if missing)..."
while IFS= read -r line; do
  name=$(echo "$line" | jq -r '.ollama')
  req=$(echo "$line" | jq -r '.required')
  if [ "$req" = "true" ]; then
    continue
  fi
  if jq -e --arg m "$name" 'any((.data // [])[]; .id == $m)' /tmp/models.json >/dev/null 2>&1; then
    echo "  OK   $name"
  else
    echo "  SKIP $name (not pulled — optional)"
  fi
done <<EOF
$(jq -c '.models[]' "$MANIFEST")
EOF

if [ "${DOCTOR_CHAT:-0}" = "1" ]; then
  echo ""
  echo "DOCTOR_CHAT=1 — POST /v1/chat/completions (ping) for required models..."
  while IFS= read -r line; do
    name=$(echo "$line" | jq -r '.ollama')
    req=$(echo "$line" | jq -r '.required')
    if [ "$req" != "true" ]; then
      continue
    fi
    if ! jq -e --arg m "$name" 'any((.data // [])[]; .id == $m)' /tmp/models.json >/dev/null 2>&1; then
      echo "  SKIP chat $name (not in API)"
      continue
    fi
    body=$(jq -nc --arg m "$name" '{model:$m,messages:[{role:"user",content:"ping"}],stream:false}')
    if curl -sS -f --max-time 120 -X POST "$BASE/chat/completions" \
      -H "content-type: application/json" \
      -d "$body" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
      echo "  OK  chat $name"
    else
      echo "  FAIL chat $name" >&2
      fail=1
    fi
  done <<EOF
$(jq -c '.models[]' "$MANIFEST")
EOF
fi

echo ""
if [ "$fail" -ne 0 ]; then
  echo "slackeel model-doctor FAILED" >&2
  exit 1
fi
echo "slackeel model-doctor PASSED"
