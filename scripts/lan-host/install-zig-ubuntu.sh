#!/usr/bin/env bash
# Install Zig on Ubuntu (x86_64) from the official tarball.
# Queries ziglang.org/download/index.json for the real tarball URL so it works
# across naming-scheme changes (0.13 used zig-linux-x86_64-*, 0.14+ uses zig-x86_64-linux-*).
#
# Usage:
#   sudo bash install-zig-ubuntu.sh
#   sudo bash install-zig-ubuntu.sh --version 0.14.1
#   sudo bash install-zig-ubuntu.sh --remove
set -euo pipefail

ZIG_VERSION="${ZIG_VERSION:-0.13.0}"
INSTALL_DIR="/opt"
LINK="/usr/local/bin/zig"
INDEX_URL="https://ziglang.org/download/index.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      ZIG_VERSION="${2:?--version requires a value}"
      shift 2
      ;;
    --remove)
      echo "==> Removing Zig from ${INSTALL_DIR} and ${LINK}"
      rm -f "${LINK}"
      rm -rf "${INSTALL_DIR}"/zig-*-linux-* "${INSTALL_DIR}"/zig-linux-*
      echo "    done"
      exit 0
      ;;
    -h|--help)
      echo "Usage: sudo bash $0 [--version X.Y.Z] [--remove]"
      echo ""
      echo "  --version   Zig version to install (default: ${ZIG_VERSION})"
      echo "  --remove    Uninstall any Zig version installed by this script"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

ARCH="$(uname -m)"
if [[ "${ARCH}" != "x86_64" ]]; then
  echo "error: this script only supports x86_64 (detected: ${ARCH})" >&2
  exit 1
fi

echo "==> Resolving tarball URL for Zig ${ZIG_VERSION} (x86_64-linux) from index.json"
URL="$(curl -sfL "${INDEX_URL}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
v = d.get('${ZIG_VERSION}', {})
entry = v.get('x86_64-linux', {})
url = entry.get('tarball', '')
if not url:
    print('ERROR', file=sys.stderr)
    sys.exit(1)
print(url)
")"

if [[ -z "${URL}" ]]; then
  echo "error: could not find tarball URL for Zig ${ZIG_VERSION} x86_64-linux" >&2
  exit 1
fi

TARBALL="$(basename "${URL}")"
DIRNAME="${TARBALL%.tar.xz}"
DEST="${INSTALL_DIR}/${DIRNAME}"

if [[ -d "${DEST}" ]]; then
  echo "==> Zig ${ZIG_VERSION} already installed at ${DEST}"
else
  echo "==> Downloading ${URL}"
  curl -fL "${URL}" -o "/tmp/${TARBALL}"

  echo "==> Extracting to ${INSTALL_DIR}"
  tar -xf "/tmp/${TARBALL}" -C "${INSTALL_DIR}"
  rm -f "/tmp/${TARBALL}"
fi

rm -f "${LINK}"
ln -s "${DEST}/zig" "${LINK}"

echo "==> Zig installed:"
zig version
echo "    binary: $(readlink -f "${LINK}")"
echo "    symlink: ${LINK}"
