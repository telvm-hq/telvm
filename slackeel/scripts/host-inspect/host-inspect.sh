#!/bin/sh
# Slackeel — quick host + Docker resource peek (Linux/macOS). See docs/ROADMAP_HOST_METRICS.md
set -e

echo ""
echo "=== slackeel host-inspect (Unix) ==="
echo ""

echo "--- System ---"
uname -a 2>/dev/null || true

echo ""
echo "--- Memory ---"
if command -v free >/dev/null 2>&1; then
  free -h
elif [ -r /proc/meminfo ]; then
  head -n 5 /proc/meminfo
else
  echo "  (no free or /proc/meminfo)"
fi

echo ""
echo "--- Disk (.) ---"
df -h . 2>/dev/null || true

echo ""
echo "--- Docker ---"
if command -v docker >/dev/null 2>&1; then
  docker version --format '{{.Server.Version}}' 2>/dev/null | sed 's/^/  Server version: /' || true
  echo "  docker system df:"
  docker system df 2>&1 || true
else
  echo "  docker CLI not on PATH"
fi

echo ""
echo "Done."
