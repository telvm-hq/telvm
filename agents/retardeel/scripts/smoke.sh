#!/usr/bin/env bash
set -euo pipefail

# retardeel smoke test — run on Linux after building the binary.
# Usage: ./scripts/smoke.sh [path-to-binary]

BINARY="${1:-./zig-out/bin/retardeel}"
PORT=9211
TOKEN="smoke-test-token"
ROOT=$(mktemp -d)
BASE="http://localhost:$PORT"
AUTH="Authorization: Bearer $TOKEN"
PASS=0
FAIL=0
PID=""

cleanup() {
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    rm -rf "$ROOT"
}
trap cleanup EXIT

# Seed workspace with sample files.
mkdir -p "$ROOT/src"
echo 'defmodule Hello do end' > "$ROOT/src/hello.ex"
echo '{}' > "$ROOT/package.json"
touch "$ROOT/mix.exs"
touch "$ROOT/Makefile"

# Start server.
"$BINARY" --token "$TOKEN" --root "$ROOT" --port "$PORT" &
PID=$!
sleep 0.5

if ! kill -0 "$PID" 2>/dev/null; then
    echo "FATAL: retardeel did not start"
    exit 1
fi

check() {
    local label="$1"
    local expect_status="$2"
    local method="$3"
    local url="$4"
    local data="${5:-}"

    local args=(-s -o /dev/null -w "%{http_code}" -H "$AUTH")
    if [ "$method" = "POST" ]; then
        args+=(-X POST -H "Content-Type: application/json")
        if [ -n "$data" ]; then
            args+=(-d "$data")
        fi
    fi

    local status
    status=$(curl "${args[@]}" "$url")

    if [ "$status" = "$expect_status" ]; then
        echo "  PASS  $label (HTTP $status)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $label (expected $expect_status, got $status)"
        FAIL=$((FAIL + 1))
    fi
}

check_body() {
    local label="$1"
    local expect_fragment="$2"
    local method="$3"
    local url="$4"
    local data="${5:-}"

    local args=(-s -H "$AUTH")
    if [ "$method" = "POST" ]; then
        args+=(-X POST -H "Content-Type: application/json")
        if [ -n "$data" ]; then
            args+=(-d "$data")
        fi
    fi

    local body
    body=$(curl "${args[@]}" "$url")

    if echo "$body" | grep -q "$expect_fragment"; then
        echo "  PASS  $label (body contains '$expect_fragment')"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $label (body missing '$expect_fragment')"
        echo "        got: $body"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "retardeel smoke test"
echo "===================="
echo "binary: $BINARY"
echo "root:   $ROOT"
echo "port:   $PORT"
echo ""

# --- Health ---
check "GET /health" "200" "GET" "$BASE/health"
check_body "health has version" "retardeel" "GET" "$BASE/health"

# --- Workspace discovery ---
check "GET /v1/workspace" "200" "GET" "$BASE/v1/workspace"
check_body "workspace finds mix.exs" "mix.exs" "GET" "$BASE/v1/workspace"
check_body "workspace hints elixir" "elixir" "GET" "$BASE/v1/workspace"

# --- Stat ---
check "POST /v1/stat (exists)" "200" "POST" "$BASE/v1/stat" '{"path":"src/hello.ex"}'
check_body "stat exists=true" "\"exists\":true" "POST" "$BASE/v1/stat" '{"path":"src/hello.ex"}'
check_body "stat not found" "\"exists\":false" "POST" "$BASE/v1/stat" '{"path":"nope.txt"}'

# --- Read ---
check "POST /v1/read" "200" "POST" "$BASE/v1/read" '{"path":"src/hello.ex"}'
check_body "read has content" "defmodule" "POST" "$BASE/v1/read" '{"path":"src/hello.ex"}'

# --- Write (create) ---
check "POST /v1/write (create)" "200" "POST" "$BASE/v1/write" '{"path":"new.txt","text":"created\n","mode":"create"}'
check_body "write returns sha256" "sha256" "POST" "$BASE/v1/write" '{"path":"overwrite.txt","text":"data","mode":"create"}'

# --- Write (replace) ---
check "POST /v1/write (replace)" "200" "POST" "$BASE/v1/write" '{"path":"new.txt","text":"replaced\n","mode":"replace"}'

# --- Write (create already exists) ---
check "POST /v1/write (conflict)" "409" "POST" "$BASE/v1/write" '{"path":"new.txt","text":"nope","mode":"create"}'

# --- List ---
check "POST /v1/list" "200" "POST" "$BASE/v1/list" '{"path":"src","max_entries":10}'
check_body "list has hello.ex" "hello.ex" "POST" "$BASE/v1/list" '{"path":"src"}'

# --- Jail escape attempts ---
check "jail escape (..)" "403" "POST" "$BASE/v1/read" '{"path":"../../etc/passwd"}'
check "jail escape (absolute)" "403" "POST" "$BASE/v1/read" '{"path":"/etc/passwd"}'

# --- Auth failure ---
status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health")
if [ "$status" = "401" ]; then
    echo "  PASS  no-auth returns 401"
    PASS=$((PASS + 1))
else
    echo "  FAIL  no-auth expected 401, got $status"
    FAIL=$((FAIL + 1))
fi

# --- 404 ---
check "unknown route" "404" "GET" "$BASE/v1/nonexistent"

echo ""
echo "===================="
echo "PASS: $PASS  FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "SMOKE TEST FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
fi
