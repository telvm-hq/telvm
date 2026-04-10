# LAN host baseline inventory

Use this folder to store a **factual snapshot** of each Ubuntu (or other) machine before automating against it.

For **Wi-Fi vs direct Ethernet, APIPA, routing, and SSH** (how this fits real bring-up), see the primer: [LAN / Wi-Fi / Ethernet / SSH](../../docs/lan-cluster-network-primer.md).

## Network addressing paths

### Path A: Windows ICS (192.168.137.0/24) -- recommended for quick setups

Windows ICS shares internet from Wi-Fi to Ethernet and runs a built-in DHCP server on **192.168.137.0/24**. Each Ubuntu node just needs `dhcp4: true` on its wired NIC.

**One-command setup** (on each Ubuntu node, as root):

```bash
sudo bash scripts/lan-host/apply-ics-dhcp.sh
```

This auto-detects the wired NIC, writes `/etc/netplan/99-ics-dhcp.yaml`, and applies it. The address **persists across reboots**. Override the NIC name if needed:

```bash
sudo bash scripts/lan-host/apply-ics-dhcp.sh enp0s31f6
```

Manual alternative: copy the example and edit the interface name:

- [netplan-ics-dhcp.example.yaml](netplan-ics-dhcp.example.yaml)

```bash
sudo install -m 600 -T netplan-ics-dhcp.example.yaml /etc/netplan/99-ics-dhcp.yaml
sudo netplan apply
```

### Path B: UniFi / static lab (10.10.10.x)

For **UniFi gateway + DHCP DNS** and **static Netplan** on **10.10.10.11 / .12**, see [UniFi + Netplan lab runbook](../../docs/lan-unifi-netplan-lab-runbook.md). Example files (copy to `/etc/netplan/`, mode **600**):

- [netplan-10.10.10.11.example.yaml](netplan-10.10.10.11.example.yaml)
- [netplan-10.10.10.12.example.yaml](netplan-10.10.10.12.example.yaml)

> **Do not mix paths.** ICS uses 192.168.137.x; UniFi/static uses 10.10.10.x. Pick one per deployment.

## Golden host profile (reproduce on a fresh install)

On the **reference** Ubuntu machine (SSH or console), from a checkout of this repo:

```bash
bash scripts/lan-host/capture-golden-profile.sh
bash scripts/lan-host/capture-golden-profile.sh --include-inventory   # also runs collect-ubuntu-inventory.sh
bash scripts/lan-host/capture-golden-profile.sh --archive             # adds ~/golden-profile-*.tgz next to the dir
```

This writes a timestamped directory under `$HOME` (override with `-o DIR`) containing:

- `os-release.txt`, `lsb_release.txt`, `uname.txt`
- `golden-manual-packages.txt` — **only** package names, one per line (`apt-mark showmanual`), for parity on a new host
- `snap-list.txt`, `dpkg-metapackages.txt`, `cloud-init.txt`
- `ip-address.txt`, `ip-route.txt`, `netplan-concat.txt`
- `MANIFEST.txt` (generation time and paths)

Copy artifacts to your admin PC (paths shown by the script), e.g.:

```bash
scp -r ubuntu@GOLDEN_HOST:~/golden-profile-YYYYMMDDTHHMMSSZ .
```

On Windows, place a copy of `golden-manual-packages.txt` next to this folder as `golden-manual-packages.local.txt` if you want a local path (that name pattern is gitignored via `*.local.txt`). For full `cloud-init` status, run `sudo cloud-init status` on the golden host once and paste into your notes if needed.

## Steps

1. **Discover the target IPv4** (DHCP lease table, router UI, or `ip -br a` on the box).
2. On the Ubuntu host, run the collector (copy script over, or clone repo and run):

   ```bash
   bash scripts/lan-host/collect-ubuntu-inventory.sh
   ```

3. Save the output:
   - Copy into `baseline.local.yaml` under `raw_console_output:` (see [baseline.example.yaml](baseline.example.yaml)), **or**
   - Save as a separate `.txt` file next to this README (add that filename to `.gitignore` if it contains sensitive data).

4. Fill structured fields in `baseline.local.yaml` (copy from [baseline.example.yaml](baseline.example.yaml)). That file is gitignored so hostnames, IPs, and service lists stay local.

## Windows connectivity

From the repo root on Windows:

```powershell
.\scripts\windows\test-lan-connectivity.ps1 -TargetIp 192.168.x.x
```

## Cluster over HTTP (companion integration)

Instead of raw TCP probes from the companion container, deploy the **[`telvm-node-agent`](../../agents/telvm-node-agent/README.md)** Zig binary to each host. The companion polls `GET /health` on each agent over HTTP; results appear on the **Pre-flight** page when `TELVM_CLUSTER_NODES` is set.

See **[agents/telvm-node-agent/README.md](../../agents/telvm-node-agent/README.md)** for build, deploy, API, and systemd setup.

## Shell probe from the companion container (legacy)

With Compose running and `TELVM_LAN_TARGET_HOST` set (see root `.env.example`):

```bash
docker compose exec companion /bin/bash /telvm-scripts/lan-host/test-lan-from-companion.sh
```
