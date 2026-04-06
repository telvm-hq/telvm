# UniFi + Netplan runbook: 10.10.10.x lab nodes

This runbook implements the **LAN troubleshooting checkpoint**: read the **correct gateway and DNS** from UniFi for your **10.10.10.0/24** (or equivalent) network, then apply **static Netplan** on Ubuntu nodes (e.g. **.11** / **.12**) so **SSH and apt** share one sane L3 config.

**Related:** [LAN primer](lan-cluster-network-primer.md), [Ubuntu network snapshot](lan-ubuntu-node-network-snapshot.md), example Netplan files under [`inventories/lan-host/`](../inventories/lan-host/).

---

## Part A: UniFi checklist (gateway + DHCP DNS)

Do this in the **UniFi Site Manager / Network Application** (wording varies by version).

1. Open **Settings** (or **Networks**) and select the **network / VLAN** that carries **10.10.10.x** (the same segment as your lab switch).
2. Note **Gateway IP** / **Router** / **DHCP Gateway** for that network. This is the **`via:`** address for a default route on lab hosts. **Do not assume `.1`**; use the value UniFi shows.
3. Open **DHCP** (or DHCP options) for that same network:
   - Note **DNS** (or DHCP option 6). It must be **reachable from 10.10.10.x**.
   - **Anti-pattern:** advertising **192.168.40.1** (or any other subnet) as DNS **without** a route from **10.10.10.x** to that subnet causes `Temporary failure resolving` and hung lookups.
4. **Fix in UniFi if needed:** set DHCP DNS to:
   - the **lab gateway** if it resolves DNS for clients, or
   - **public resolvers** (e.g. 1.1.1.1, 8.8.8.8) **after** clients have a **default route** to the internet, or
   - a **Pi-hole / internal resolver** that is **routable** from 10.10.10.x.

Write the values you captured here (local notes or `baseline.local.yaml`, not committed secrets):

| Field | Your value |
|-------|------------|
| Lab subnet | e.g. 10.10.10.0/24 |
| Gateway (default `via:`) | |
| DHCP DNS (should match reachability) | |

---

## Part B: Netplan on each Ubuntu node (.11 / .12)

### Prerequisites

- Interface name: usually **`enp2s0`**; confirm with `ip -br link`.
- **One file** should own **`enp2s0`** (avoid two netplan files both defining the same interface).
- File mode **600** (netplan warns if world-readable).

### Example files in this repo

Copy and edit on the node, or copy from the repo and adjust **only** `via:` if your UniFi gateway differs from the example:

- [`netplan-10.10.10.11.example.yaml`](../inventories/lan-host/netplan-10.10.10.11.example.yaml)
- [`netplan-10.10.10.12.example.yaml`](../inventories/lan-host/netplan-10.10.10.12.example.yaml)

Each file uses **`via: 10.10.10.1`** as a **placeholder**: **replace with your actual gateway** from Part A if different.

### Install procedure (does not run `apply` until you choose)

From the Ubuntu node, with a path to the example file (e.g. scp’d from your PC):

```bash
sudo install -m 600 -T netplan-10.10.10.11.example.yaml /etc/netplan/99-lab-static.yaml
# or .12 on the other host
sudo netplan generate
```

If `generate` errors, fix YAML before continuing.

### Apply (may reset SSH for a moment)

Use **console / BMC / physical access** if possible.

```bash
sudo netplan apply
```

Safer variant (auto-revert if you lose access):

```bash
sudo netplan try
```

### Verify

```bash
ip -4 route show default
resolvectl status enp2s0
getent hosts archive.ubuntu.com
ping -c 2 8.8.8.8
sudo apt update
```

---

## Part C: Windows operator snapshot (switch segment)

When the PC is on the same switch with **10.10.10.10/24** and **internet defaults over Wi-Fi**, see [inspect-switch-uplink.ps1](../scripts/windows/inspect-switch-uplink.ps1): Ethernet may show **no IPv4 gateway** while **Wi-Fi** holds **`0.0.0.0/0`**. Lab nodes still need their **own** default route **on `enp2s0`** via the **UniFi gateway for 10.10.10.x**, independent of how Windows routes.

---

## Quick failure reference

| Symptom | Typical cause |
|---------|----------------|
| `Network is unreachable` to 8.8.8.8 | No **default route** on the node |
| `Temporary failure resolving` | **DNS server not reachable** from node IP (wrong subnet / no route) or no route to internet |
| `netplan apply` drops SSH | Address/gateway changed; use **`netplan try`** or console |
