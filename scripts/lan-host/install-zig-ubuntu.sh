#!/usr/bin/env bash
# Install Zig on Ubuntu (x86_64) from the official tarball.
# Used to build telvm-node-agent on remote lab hosts.
#
# Usage:
#   sudo bash scripts/lan-host/install-zig-ubuntu.sh
#   sudo bash scripts/lan-host/install-zig-ubuntu.sh --version 0.14.1
#   sudo bash scripts/lan-host/install-zig-ubuntu.sh --remove
set -euo pipefail

ZIG_VERSION="${ZIG_VERSION:-0.15.2}"
INSTALL_DIR="/opt"
LINK="/usr/local/bin/zig"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      ZIG_VERSION="${2:?--version requires a value}"
      shift 2
      ;;
    --remove)
      echo "==> Removing Zig from ${INSTALL_DIR} and ${LINK}"
      rm -f "${LINK}"
      rm -rf "${INSTALL_DIR}"/zig-linux-x86_64-*
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

TARBALL="zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
URL="https://ziglang.org/download/${ZIG_VERSION}/${TARBALL}"
DEST="${INSTALL_DIR}/zig-linux-x86_64-${ZIG_VERSION}"

if [[ -d "${DEST}" ]]; then
  echo "==> Zig ${ZIG_VERSION} already installed at ${DEST}"
else
  echo "==> Downloading ${URL}"
  curl -fL "${URL}" -o "/tmp/${TARBALL}"

  echo "==> Extracting to ${INSTALL_DIR}"
  tar -xf "/tmp/${TARBALL}" -C "${INSTALL_DIR}"
  rm -f "/tmp/${TARBALL}"
fi

# Remove any previous symlink (possibly to an older version)
rm -f "${LINK}"
ln -s "${DEST}/zig" "${LINK}"

echo "==> Zig installed:"
zig version
echo "    binary: $(readlink -f "${LINK}")"
echo "    symlink: ${LINK}"
