#!/usr/bin/env bash
# Install Docker Engine (CE) + Compose plugin on Ubuntu from Docker's official apt repo.
# Follows https://docs.docker.com/engine/install/ubuntu/ — no snap, no distro packages.
#
# Usage:
#   sudo bash install-docker-engine-ubuntu.sh
#   sudo bash install-docker-engine-ubuntu.sh --add-user-docker-group
#   sudo bash install-docker-engine-ubuntu.sh --skip-hello
#   sudo bash install-docker-engine-ubuntu.sh --add-user-docker-group --skip-hello
set -euo pipefail

ADD_USER=0
SKIP_HELLO=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --add-user-docker-group)
      ADD_USER=1
      shift
      ;;
    --skip-hello)
      SKIP_HELLO=1
      shift
      ;;
    -h|--help)
      echo "Usage: sudo bash $0 [--add-user-docker-group] [--skip-hello]"
      echo ""
      echo "  --add-user-docker-group   Add \$SUDO_USER to the docker group (requires re-login)"
      echo "  --skip-hello              Skip the hello-world smoke test at the end"
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

# ── 1. Remove conflicting packages ──────────────────────────────────────────
echo "==> Removing conflicting packages (if any)"
for pkg in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
  apt-get remove -y "$pkg" 2>/dev/null || true
done

# ── 2. Set up Docker's official apt repository ──────────────────────────────
echo "==> Installing prerequisites"
apt-get update -y
apt-get install -y ca-certificates curl

echo "==> Adding Docker GPG key"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "==> Adding Docker apt repository"
# shellcheck disable=SC1091
CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y

# ── 3. Install Docker Engine + Compose plugin ───────────────────────────────
echo "==> Installing docker-ce, cli, containerd, buildx, compose"
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# ── 4. Verify ───────────────────────────────────────────────────────────────
echo "==> Docker version:"
docker version --format '  Engine {{.Server.Version}}  CLI {{.Client.Version}}'

echo "==> Compose version:"
docker compose version

if [[ "${SKIP_HELLO}" -eq 0 ]]; then
  echo "==> Smoke test (docker run hello-world; needs outbound network)"
  docker run --rm hello-world
fi

# ── 5. Optional: add user to docker group ───────────────────────────────────
if [[ "${ADD_USER}" -eq 1 ]]; then
  TARGET_USER="${SUDO_USER:-}"
  if [[ -z "${TARGET_USER}" ]]; then
    echo "warning: --add-user-docker-group requires SUDO_USER; skipping" >&2
  else
    echo "==> Adding ${TARGET_USER} to docker group (re-login required)"
    usermod -aG docker "${TARGET_USER}"
  fi
fi

echo ""
echo "==> Docker Engine installed. Services enabled and running."
echo "    If you used --add-user-docker-group, log out and back in for group to take effect."
