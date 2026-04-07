#!/usr/bin/env bash
# Run on the Ubuntu host (SSH session or local console). Emits a single text blob
# suitable for pasting into inventories/lan-host/baseline.local.yaml notes or gitignored archive.
set -eu

echo "=== dirteel/telvm baseline inventory ==="
echo "generated_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

echo "--- /etc/os-release ---"
cat /etc/os-release 2>/dev/null || echo "(missing)"
echo

echo "--- uname -a ---"
uname -a
echo

echo "--- ip -br a ---"
ip -br a 2>/dev/null || echo "(ip missing)"
echo

echo "--- ip r ---"
ip r 2>/dev/null || echo "(ip missing)"
echo

echo "--- ss -tlnp ---"
ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || echo "(ss/netstat missing)"
echo

echo "--- ss -ulnp ---"
ss -ulnp 2>/dev/null || echo "(ss missing)"
echo

echo "--- lscpu (summary) ---"
lscpu 2>/dev/null | head -n 40 || echo "(lscpu missing)"
echo

echo "--- free -h ---"
free -h 2>/dev/null || echo "(free missing)"
echo

echo "--- lsblk ---"
lsblk 2>/dev/null || echo "(lsblk missing)"
echo

echo "--- systemd running services (names only) ---"
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -n 50 || echo "(systemctl missing)"
