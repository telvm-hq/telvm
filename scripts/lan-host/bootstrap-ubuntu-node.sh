#!/usr/bin/env bash
# bootstrap-ubuntu-node.sh -- One-command setup for a telvm cluster node.
#
# Installs everything needed for a fresh Ubuntu machine to join a telvm ICS
# cluster and survive reboots: basic tools, Docker Engine, Zig, the
# telvm-node-agent binary + systemd unit, and persistent ICS DHCP netplan.
#
# Prerequisites:
#   - Ubuntu 22.04+ with console or SSH access
#   - Internet access (even if only via ICS -- run apply-ics-dhcp.sh first if
#     the machine does not yet have an IP)
#   - This script must be run as root (sudo)
#
# Usage:
#   sudo bash bootstrap-ubuntu-node.sh --token <shared-cluster-token>
#   sudo bash bootstrap-ubuntu-node.sh --token mytoken --zig-version 0.13.0
#   sudo bash bootstrap-ubuntu-node.sh --token mytoken --skip-dhcp
#   sudo bash bootstrap-ubuntu-node.sh --token mytoken --skip-docker
#   sudo bash bootstrap-ubuntu-node.sh --token mytoken --nic enp0s31f6
#
# What it does (in order):
#   1. Applies ICS DHCP netplan (unless --skip-dhcp)
#   2. Installs basic tools (vim, ping)
#   3. Installs Docker Engine from Docker's official repo (unless --skip-docker)
#   4. Installs Zig from upstream tarball
#   5. Builds telvm-node-agent from source (requires repo checkout)
#   6. Installs telvm-node-agent binary + systemd service
#   7. Runs a self-test
set -euo pipefail

TOKEN=""
ZIG_VERSION="0.13.0"
SKIP_DHCP=0
SKIP_DOCKER=0
NIC_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)
      TOKEN="${2:?--token requires a value}"
      shift 2
      ;;
    --zig-version)
      ZIG_VERSION="${2:?--zig-version requires a value}"
      shift 2
      ;;
    --skip-dhcp)
      SKIP_DHCP=1
      shift
      ;;
    --skip-docker)
      SKIP_DOCKER=1
      shift
      ;;
    --nic)
      NIC_OVERRIDE="${2:?--nic requires an interface name}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: sudo bash $0 --token <TOKEN> [OPTIONS]"
      echo ""
      echo "  --token <TOKEN>      Shared cluster Bearer token (required)"
      echo "  --zig-version <VER>  Zig version to install (default: ${ZIG_VERSION})"
      echo "  --skip-dhcp          Skip ICS DHCP netplan setup"
      echo "  --skip-docker        Skip Docker Engine installation"
      echo "  --nic <IFACE>        Override NIC name for DHCP (default: auto-detect)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Run as root (sudo)." >&2
  exit 1
fi

if [[ -z "${TOKEN}" ]]; then
  echo "ERROR: --token is required." >&2
  echo "  Usage: sudo bash $0 --token <shared-cluster-token>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

section() { echo ""; echo "========== $1 =========="; }

# ── 1. ICS DHCP ─────────────────────────────────────────────────────────────
if [[ "${SKIP_DHCP}" -eq 0 ]]; then
  section "ICS DHCP netplan"
  if [[ -n "${NIC_OVERRIDE}" ]]; then
    bash "${SCRIPT_DIR}/apply-ics-dhcp.sh" "${NIC_OVERRIDE}"
  else
    bash "${SCRIPT_DIR}/apply-ics-dhcp.sh"
  fi
else
  section "ICS DHCP (skipped)"
fi

# ── 2. Basic tools ──────────────────────────────────────────────────────────
section "Basic tools"
bash "${SCRIPT_DIR}/install-basic-tools-ubuntu.sh" --vim-tiny

# ── 3. Docker Engine ────────────────────────────────────────────────────────
if [[ "${SKIP_DOCKER}" -eq 0 ]]; then
  section "Docker Engine"
  if command -v docker &>/dev/null && docker version &>/dev/null; then
    echo "Docker already installed:"
    docker version --format '  Engine {{.Server.Version}}  CLI {{.Client.Version}}'
  else
    bash "${SCRIPT_DIR}/install-docker-engine-ubuntu.sh" --add-user-docker-group --skip-hello
  fi
else
  section "Docker Engine (skipped)"
fi

# ── 4. Zig ──────────────────────────────────────────────────────────────────
section "Zig ${ZIG_VERSION}"
if command -v zig &>/dev/null; then
  INSTALLED="$(zig version 2>/dev/null || echo unknown)"
  echo "Zig already installed: ${INSTALLED}"
  if [[ "${INSTALLED}" != "${ZIG_VERSION}" ]]; then
    echo "Upgrading to ${ZIG_VERSION} ..."
    bash "${SCRIPT_DIR}/install-zig-ubuntu.sh" --version "${ZIG_VERSION}"
  fi
else
  bash "${SCRIPT_DIR}/install-zig-ubuntu.sh" --version "${ZIG_VERSION}"
fi

# ── 5. Build telvm-node-agent ───────────────────────────────────────────────
section "Build telvm-node-agent"
AGENT_DIR="${REPO_ROOT}/agents/telvm-node-agent"
if [[ ! -f "${AGENT_DIR}/build.zig" ]]; then
  echo "ERROR: Cannot find ${AGENT_DIR}/build.zig" >&2
  echo "  Make sure this script is run from a telvm repo checkout." >&2
  exit 1
fi

cd "${AGENT_DIR}"
zig build -Doptimize=ReleaseSafe
AGENT_BIN="${AGENT_DIR}/zig-out/bin/telvm-node-agent"
if [[ ! -f "${AGENT_BIN}" ]]; then
  echo "ERROR: Build succeeded but binary not found at ${AGENT_BIN}" >&2
  exit 1
fi
echo "Built: ${AGENT_BIN}"

# ── 6. Install agent + systemd ──────────────────────────────────────────────
section "Install telvm-node-agent"
install -m 755 "${AGENT_BIN}" /usr/local/bin/telvm-node-agent

echo "TELVM_NODE_TOKEN=${TOKEN}" > /etc/telvm-node-agent.env
chmod 600 /etc/telvm-node-agent.env

install -m 644 "${AGENT_DIR}/telvm-node-agent.service" /etc/systemd/system/telvm-node-agent.service
systemctl daemon-reload
systemctl enable telvm-node-agent
systemctl restart telvm-node-agent

echo "Waiting for agent to start ..."
sleep 2
if systemctl is-active --quiet telvm-node-agent; then
  echo "telvm-node-agent is running."
else
  echo "WARNING: telvm-node-agent did not start. Check: journalctl -u telvm-node-agent" >&2
fi

# ── 7. Self-test ────────────────────────────────────────────────────────────
section "Self-test"
echo "GET http://127.0.0.1:9100/health ..."
if command -v curl &>/dev/null; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    --max-time 5 http://127.0.0.1:9100/health 2>/dev/null || echo "000")
  if [[ "${HTTP_CODE}" == "200" ]]; then
    echo "  OK (HTTP 200)"
    curl -s -H "Authorization: Bearer ${TOKEN}" http://127.0.0.1:9100/health
    echo ""
  else
    echo "  FAIL (HTTP ${HTTP_CODE}). Check: journalctl -u telvm-node-agent" >&2
  fi
else
  echo "  curl not available; skipping HTTP self-test."
fi

echo ""
echo "IP addresses on this machine:"
ip -br a 2>/dev/null || ip addr
echo ""
echo "========== Bootstrap complete =========="
echo "This node will:"
echo "  - Request a DHCP address from ICS on every boot (192.168.137.x)"
echo "  - Start telvm-node-agent on :9100 via systemd after Docker is ready"
echo "  - Be discoverable by the telvm companion dashboard"
