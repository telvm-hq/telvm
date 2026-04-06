#!/usr/bin/env bash
# Run inside the companion container: verifies reachability to TELVM_LAN_TARGET_HOST
# (same path Windows host uses). Requires curl or bash /dev/tcp (bash is present in the image).
set -eu

TARGET="${TELVM_LAN_TARGET_HOST:-}"
PORT="${TELVM_LAN_TARGET_SSH_PORT:-22}"

if [[ -z "$TARGET" ]]; then
  echo "error: set TELVM_LAN_TARGET_HOST (e.g. in .env for docker compose)" >&2
  exit 1
fi

echo "companion -> LAN probe: host=$TARGET ssh_port=$PORT"

if ping -c 1 -W 2 "$TARGET" >/dev/null 2>&1; then
  echo "ping: ok"
else
  echo "ping: failed or blocked (ICMP may be disabled; continuing with TCP)"
fi

if command -v curl >/dev/null 2>&1; then
  # curl connects to SSH banner without speaking the protocol
  if curl -sS --connect-timeout 3 "telnet://$TARGET:$PORT" -o /dev/null; then
    echo "tcp $PORT: reachable (curl)"
  else
    echo "tcp $PORT: NOT reachable (curl)" >&2
    exit 1
  fi
else
  if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$TARGET/$PORT"; then
    echo "tcp $PORT: reachable (/dev/tcp)"
  else
    echo "tcp $PORT: NOT reachable (/dev/tcp)" >&2
    exit 1
  fi
fi

echo "done."
