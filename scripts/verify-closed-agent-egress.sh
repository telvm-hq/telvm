#!/usr/bin/env sh
# Verify HTTPS to vendor APIs via Telvm companion egress proxy (explicit curl --proxy).
# Prereq: docker compose up --build (companion healthy; telvm_closed_* running).
# See docs/closed-agent-network-harness-contract.md — lab_relaxed may still allow direct egress for processes that ignore HTTP_PROXY.
set -e
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo "telvm: verify closed-agent egress via companion proxy"
echo "Note: lab_relaxed images may still allow direct TCP; this checks the proxy path only."
echo ""

code_c=$(
  docker compose exec -T telvm_closed_claude sh -c \
    'curl -sS -o /dev/null -w "%{http_code}" --max-time 25 --proxy http://companion:4001 https://api.anthropic.com/' \
    || echo 000
)
echo "telvm_closed_claude -> companion:4001 -> api.anthropic.com  HTTP $code_c"
if [ "$code_c" = "000" ]; then
  echo "FAIL: no HTTP response (stack up? run: docker compose up --build)" >&2
  exit 1
fi

code_x=$(
  docker compose exec -T telvm_closed_codex sh -c \
    'curl -sS -o /dev/null -w "%{http_code}" --max-time 25 --proxy http://companion:4002 https://api.openai.com/' \
    || echo 000
)
echo "telvm_closed_codex  -> companion:4002 -> api.openai.com    HTTP $code_x"
if [ "$code_x" = "000" ]; then
  echo "FAIL: no HTTP response" >&2
  exit 1
fi

echo ""
echo "apt through proxy (HTTP_PROXY is set; images run as root — no sudo needed):"
docker compose exec -T telvm_closed_claude sh -c \
  'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq' \
  && echo "telvm_closed_claude  apt-get update  OK" \
  || { echo "FAIL: apt-get update in telvm_closed_claude" >&2; exit 1; }

docker compose exec -T telvm_closed_codex sh -c \
  'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq' \
  && echo "telvm_closed_codex   apt-get update  OK" \
  || { echo "FAIL: apt-get update in telvm_closed_codex" >&2; exit 1; }

echo ""
echo "OK. Correlate allowed CONNECT lines in companion logs:"
echo "  docker compose logs companion 2>&1 | grep egress_proxy"
