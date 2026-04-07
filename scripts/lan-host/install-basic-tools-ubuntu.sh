#!/usr/bin/env bash
# Install basic tools on a minimal Ubuntu server (e.g. ubuntu-server-minimal).
# Bare installs often have no editor and no ping.
#
# Usage:
#   sudo bash install-basic-tools-ubuntu.sh
#   sudo bash install-basic-tools-ubuntu.sh --vim-tiny
set -euo pipefail

VIM_PKG="vim"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vim-tiny)
      VIM_PKG="vim-tiny"
      shift
      ;;
    -h|--help)
      echo "Usage: sudo bash $0 [--vim-tiny]"
      echo ""
      echo "  --vim-tiny   Install vim-tiny instead of full vim"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "error: must run as root (use sudo)" >&2
  exit 1
fi

echo "==> Updating apt"
apt-get update -y

echo "==> Installing ${VIM_PKG} and iputils-ping"
apt-get install -y "${VIM_PKG}" iputils-ping

echo "==> Installed:"
dpkg -l "${VIM_PKG}" iputils-ping 2>/dev/null | grep '^ii' | awk '{print "    " $2 " " $3}'
