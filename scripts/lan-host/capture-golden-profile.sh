#!/usr/bin/env bash
# Run on the golden Ubuntu host (SSH or console). Writes a directory of text artifacts
# for reproducing ubuntu-server-minimal-style installs on a new machine.
#
# Usage:
#   bash scripts/lan-host/capture-golden-profile.sh
#   bash scripts/lan-host/capture-golden-profile.sh -o ~/golden-out
#   bash scripts/lan-host/capture-golden-profile.sh --include-inventory
#   bash scripts/lan-host/capture-golden-profile.sh --archive
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INCLUDE_INVENTORY=0
ARCHIVE=0
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out)
      OUT="${2:?}"
      shift 2
      ;;
    --include-inventory)
      INCLUDE_INVENTORY=1
      shift
      ;;
    --archive)
      ARCHIVE=1
      shift
      ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUT" ]]; then
  OUT="${HOME}/golden-profile-$(date -u +%Y%m%dT%H%M%SZ)"
fi

mkdir -p "$OUT"

ts_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

{
  echo "generated_at_utc: $(ts_utc)"
  echo "hostname: $(hostname -f 2>/dev/null || hostname)"
  echo "output_dir: $OUT"
} > "$OUT/MANIFEST.txt"

echo "--- /etc/os-release ---" > "$OUT/os-release.txt"
cat /etc/os-release 2>/dev/null >> "$OUT/os-release.txt" || echo "(missing)" >> "$OUT/os-release.txt"

{
  echo "--- lsb_release -a ---"
  if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -a 2>/dev/null || true
  else
    echo "(lsb_release not installed)"
  fi
} > "$OUT/lsb_release.txt"

echo "--- uname -a ---" > "$OUT/uname.txt"
uname -a >> "$OUT/uname.txt"

# One package name per line (suitable for: xargs -a file sudo apt install -y)
if command -v apt-mark >/dev/null 2>&1; then
  apt-mark showmanual | sort -u > "$OUT/golden-manual-packages.txt"
else
  echo "(apt-mark missing)" > "$OUT/golden-manual-packages.txt"
fi

echo "--- snap list ---" > "$OUT/snap-list.txt"
if command -v snap >/dev/null 2>&1; then
  snap list 2>/dev/null >> "$OUT/snap-list.txt" || echo "(snap list failed)" >> "$OUT/snap-list.txt"
else
  echo "(snap missing)" >> "$OUT/snap-list.txt"
fi

echo "--- dpkg ubuntu-server / cloud-init ---" > "$OUT/dpkg-metapackages.txt"
dpkg-query -W -f='${Package}\t${Status}\n' \
  ubuntu-server ubuntu-server-minimal cloud-init 2>/dev/null >> "$OUT/dpkg-metapackages.txt" || true

{
  echo "--- systemctl is-enabled cloud-init* ---"
  systemctl is-enabled cloud-init-local cloud-init cloud-config cloud-final 2>/dev/null || true
  echo ""
  echo "--- cloud-init --version ---"
  cloud-init --version 2>/dev/null || echo "(cloud-init cli missing)"
  echo ""
  echo "--- cloud-init status (may need sudo for full detail) ---"
  cloud-init status 2>/dev/null || true
  echo ""
  echo "--- sudo cloud-init status (run manually if empty above) ---"
  echo "sudo cloud-init status"
} > "$OUT/cloud-init.txt"

echo "--- ip -br a ---" > "$OUT/ip-address.txt"
ip -br a 2>/dev/null >> "$OUT/ip-address.txt" || echo "(ip missing)" >> "$OUT/ip-address.txt"

echo "--- ip r ---" > "$OUT/ip-route.txt"
ip r 2>/dev/null >> "$OUT/ip-route.txt" || echo "(ip missing)" >> "$OUT/ip-route.txt"

if [[ -d /etc/netplan ]]; then
  echo "--- /etc/netplan (concatenated) ---" > "$OUT/netplan-concat.txt"
  shopt -s nullglob
  for f in /etc/netplan/*.yaml /etc/netplan/*.yml; do
    echo ""
    echo "### $f"
    cat "$f" 2>/dev/null || true
  done >> "$OUT/netplan-concat.txt"
  shopt -u nullglob
else
  echo "(no /etc/netplan)" > "$OUT/netplan-concat.txt"
fi

if [[ "$INCLUDE_INVENTORY" -eq 1 ]]; then
  echo "--- collect-ubuntu-inventory.sh ---" > "$OUT/baseline-inventory.txt"
  bash "${SCRIPT_DIR}/collect-ubuntu-inventory.sh" >> "$OUT/baseline-inventory.txt" 2>&1 || true
fi

if [[ "$ARCHIVE" -eq 1 ]]; then
  parent="$(dirname "$OUT")"
  base="$(basename "$OUT")"
  tar -czf "${parent}/${base}.tgz" -C "$parent" "$base"
  echo "Archive: ${parent}/${base}.tgz"
fi

echo ""
echo "Golden profile written to: $OUT"
echo "Copy to Windows (example):"
echo "  scp -r ubuntu@GOLDEN_HOST:${OUT} ."
echo "Or single file for apt parity:"
echo "  scp ubuntu@GOLDEN_HOST:${OUT}/golden-manual-packages.txt ./golden-manual-packages.local.txt"
echo ""
echo "Tip: run 'sudo cloud-init status' on the golden host if cloud-init.txt is incomplete."
