# Ubuntu lab node: network snapshot (VM console, early 2026)

This note captures **observations from inside the Ubuntu machine** (hostname `node`) and ties them to the **Layer 3** problem described in [LAN, Wi-Fi, Ethernet, and SSH: a primer](lan-cluster-network-primer.md). It is **ground truth from one run**; re-run `ip -br a` and `ip r` after any config change.

---

## 1. What we collected (verbatim facts, normalized)

| Source | Observation |
|--------|----------------|
| **hostname** | `node` |
| **Kernel** | Linux `6.8.0-*` (Ubuntu) on `x86_64` — typical generic HWE kernel line (`uname -a`). |
| **`ip -br link`** | **`lo`**: loopback, UP. **`enp2s0`**: Ethernet, **UP**, broadcast/multicast — **L1/L2 present** on the wired NIC. **`wlp3s0`**: Wi-Fi, **DOWN** — **not associated / not powered on that path**. |
| **`ip r show table all \| head -n 80`** | Output shows **IPv6 link-local** on `enp2s0` (`fe80::/64`, local and multicast entries). **No IPv4 default route**, **no `169.254.0.0/16` APIPA line**, and **no `192.168.x.x/24`-style connected route** appeared in the pasted fragment. (See §3 for interpretation.) |
| **`nmcli device status`** | **No useful output** (empty, or command unavailable). |

**Naming note:** Interface names are normalized here to **`enp2s0`** / **`wlp3s0`** (common on Ubuntu). If your paste used `enp2so` / `wlp3so`, treat that as the same devices.

---

## 2. Comprehensive summary

### System

- The machine identifies as **`node`**, running a **stock Ubuntu kernel** on **generic** hardware or a VM. Nothing in this snapshot contradicts a normal server or desktop install.

### Data link (L2)

- **Ethernet `enp2s0` is UP.** That means the **NIC is active**, the **driver is bound**, and at the **link layer** the OS considers the interface usable (carrier typically present). This **aligns with** earlier Windows-side logs: **1 Gbps, link up** on the direct cable is plausible.
- **Wi-Fi `wlp3s0` is DOWN.** So the **Wi-Fi path is not in play** in this snapshot. Any plan that assumed *“SSH from Windows to the Ubuntu Wi-Fi address on `192.168.x.x`”* **does not apply** until Wi-Fi is brought **UP**, associated to an SSID, and given **L3** (DHCP or static).

### Network layer (L3) — what the routing snippet shows

The pasted `ip r show table all` lines are dominated by:

- **Local IPv6** (`::1`, interface-local addresses on `enp2s0`),
- **IPv6 link-local** scope on `enp2s0` (`fe80::/64`).

That tells us the kernel has **basic IPv6 link-local plumbing** on the wire interface.

What is **not** shown in the fragment:

- A **`default via <gateway>`** IPv4 route (typical for internet or LAN),
- A **connected IPv4 subnet** on `enp2s0` (e.g. `192.168.1.0/24` or `169.254.0.0/16`).

So **from this paste alone**, the picture is: **wired L2 is up**, but **there is no clear, documented IPv4 path** in the snippet—either because **IPv4 was not printed in the first lines** (possible), or because **IPv4 is missing or not configured** on `enp2s0` yet.

**Exact gap:** Remote access over **IPv4** (SSH from Windows to a known address) requires **at least one** of:

1. **IPv4 + route** on `enp2s0` (DHCP, static `/30` on the direct cable, or APIPA),
2. **IPv4 on another interface that is UP** (e.g. Wi-Fi — **not** the case while `wlp3s0` is DOWN),
3. Or a **deliberate IPv6-only** setup with **global IPv6** and SSH over v6 (not indicated in this paste).

Until one of those exists and matches how Windows routes traffic, **L3 remains the blocker** for *“easy SSH from the laptop.”*

### Why `nmcli` returned nothing

Common on **Ubuntu Server** or **minimal** images:

- **NetworkManager** is not installed or not the **renderer** for net config; **`netplan`** + **`systemd-networkd`** (or **`NetworkManager`**) owns the interfaces instead.
- An empty `nmcli` is **not** proof that the network is fine; it only means **NM is not your management tool** on this box.

---

## 3. The exact issue we are facing (synthesis)

Putting **Windows-side** and **Ubuntu-side** evidence together:

| Layer | Windows (prior logs) | Ubuntu VM (this snapshot) | Conclusion |
|-------|----------------------|-----------------------------|------------|
| **L1/L2** | Ethernet up, 1 Gbps | `enp2s0` UP | **Aligned:** physical link is usable. |
| **L3 IPv4** | APIPA on direct NIC; no stable peer in ARP | **No IPv4 routes shown** in the pasted `ip r` slice; Wi-Fi **DOWN** | **The problem is not “cable bad”** — it is **missing or mismatched IPv4 configuration** (and no alternate Wi-Fi path in this state). |
| **Remote SSH** | No target IP on the wire | No evidence in this paste of a **reachable IPv4** on `enp2s0` for the peer | **SSH cannot be targeted** until **both ends** share a **known IPv4** (or you use IPv6 by design). |

**One-sentence diagnosis:** You have a **healthy Ethernet link** (`enp2s0` UP), but **no confirmed, symmetric IPv4 path** between Windows and Ubuntu in the data we have—**and Wi-Fi is down**, so the usual **“use the LAN Wi-Fi address”** escape hatch is **off** until Wi-Fi is enabled. That is **exactly** the **L3** class of problem: **link without a mutually agreed IP plan for unicast.**

---

## 4. What to run next (to remove ambiguity)

Use these on **Ubuntu** to complete the picture (not already in the first paste):

```bash
ip -br a
ip r
ip -4 r
ip neigh show dev enp2s0
```

- **`ip -br a`** is definitive for **whether `enp2s0` has any IPv4** (APIPA `169.254.x.x`, static, or DHCP).
- **`ip -4 r`** shows **IPv4-only** routes (default route, connected subnets).
- **`ip neigh`** shows **ARP/NDP** neighbors on the cable (whether the **other host’s** IP ever appeared).

Optional (if using netplan):

```bash
ls /etc/netplan/
```

---

## 5. Relation to clustering (forward look)

For **Phoenix / Erlang clustering** with other hosts on a **switch**, nodes need **mutual L3 reachability** on the **fabric** (and open **EPMD / distribution** ports). This snapshot does not yet establish **management** L3 from your operator machine to `node`; fix **SSH reachability** first (static `/30` on the direct cable, or bring up Wi-Fi/LAN, or DHCP on a switched segment). See the primer’s **diagram D** and **§6** for the split between **management** and **east-west** cluster traffic.

---

## 6. Related repo files

- [LAN / Wi-Fi / Ethernet / SSH primer](lan-cluster-network-primer.md)
- [UniFi + Netplan lab runbook (10.10.10.x, gateway, DNS, apply)](lan-unifi-netplan-lab-runbook.md)
- [LAN host inventory](../inventories/lan-host/README.md)
- [collect-ubuntu-inventory.sh](../scripts/lan-host/collect-ubuntu-inventory.sh)
