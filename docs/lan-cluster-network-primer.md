# LAN, Wi-Fi, Ethernet, and SSH: a primer for lab and cluster bring-up

This document ties together **layers of networking**, what the **Windows probe scripts** actually measure, and how **SSH** fits in when your laptop and a Ubuntu host share **Wi-Fi** while you also experiment with a **direct Ethernet cable**. It matches the situation observed in early 2026 bring-up (APIPA on a direct link, default route on Wi-Fi).

**Important:** No document can safely list "default passwords" for your machines. Credentials come from **who installed the OS**, **cloud-init**, or **your org**. Automated password guessing is out of scope and unsafe.

---

## 1. Situation summary (ground truth from your logs)

**Direct cable (Windows to one peer, no switch in path):**

- **L1/L2:** Good. Physical Ethernet shows **Up**, **1 Gbps** negotiated (link pulses and framing work).
- **L3 on that NIC:** **APIPA** only, e.g. `169.254.55.34/16`. That means **no DHCP server** answered on that segment (normal for a raw two-host cable unless one side runs DHCP or you set static addresses).
- **Peer visibility:** **No unicast IPv4** of the other host appeared in **ARP / neighbor cache** on that interface; optional **guess-ping** in the same `169.254.x.*` third octet did not surface replies in your run. So Windows had **no stable target IP on that wire** to open SSH to.

**Default route on the laptop:**

- Still **Wi-Fi**, e.g. **via `192.168.40.1`** on the wireless adapter.
- So **most IPv4 traffic** to addresses like **`192.168.x.x` on the LAN** leaves through **Wi-Fi**, **not** through the dedicated Ethernet cable.

**Implication:** If the Ubuntu box also has a **Wi-Fi (or switched LAN) address** on `192.168.x.x`, **`ssh user@192.168.x.x` from Windows typically uses Wi-Fi**, not the patch cable. That is often **desirable** for day-to-day ops.

---

## 2. Why "Ethernet plugged in" is not "full access"

| Layer | What it is | What it gives you |
|-------|------------|-------------------|
| **L1** | Electrical / optical link | Bits can move; **link up** at some speed. |
| **L2** | Ethernet frames, MAC addresses | Delivery on **one broadcast domain** (one switch, or point-to-point cable). |
| **L3** | IP addresses, subnets, routing | **Which** IP to send to; **which interface** Windows chooses for a destination. |
| **L4** | TCP/UDP ports | **SSH** is **TCP** (usually port **22**). |
| **App** | `sshd`, auth | Service must **listen**, **allow** your client, and **authenticate** you. |

A cable only guarantees you are in the **L1/L2** picture for **that** link. It does **not** by itself give you:

- A **chosen** IP subnet (DHCP or static still required),
- A **known peer IP**,
- **Routing** that sends your SSH packet out that NIC,
- Or a running **`sshd`**.

**What was "missing" on the wire in your logs (conceptually):**

- A **second host's IPv4** visible to Windows (or a **configured static pair** on both ends),
- **Unicast ARP** resolving that peer's MAC on the direct NIC,
- Therefore **no** `ssh user@<peer-ip>` target **on that cable** without further setup.

**What SSH needs end-to-end:**

1. **Your PC** picks a route to the **destination IP** (correct interface).
2. **TCP** connects to **port 22** (or another forwarded port).
3. **Ubuntu** runs **`sshd`** and firewall allows it.
4. **You** authenticate (key recommended at scale).

---

## 3. ASCII diagrams

### A) Through a switch (earlier topology)

```
[ Windows ]----Ethernet----[ Switch ]----...----[ Ubuntu host ]
      \
       \---- Wi-Fi ----[ router / LAN gateway ]
```

DHCP and other LAN devices often live beyond the switch; the cable from Windows might get a **normal LAN** address.

### B) Direct cable (what you measured)

```
[ Windows ]======== patch cable ========[ Ubuntu host ]

  Windows Ethernet: 169.254.55.34/16  (APIPA - no DHCP on link)
  Ubuntu:           unknown from Windows logs; no unicast ARP seen

[ Windows ]---- Wi-Fi ---- default route ---- 192.168.40.1 ---- LAN / Internet
```

SSH to **`192.168.x.x`** on the Ubuntu Wi-Fi interface **usually goes out Wi-Fi**, not this cable.

### C) Ideal 1:1 lab link (when you want SSH only over the wire)

```
[ Windows ]======== dedicated link ========[ Ubuntu ]

  Windows:  10.10.10.1  /30  (255.255.255.252)  gateway: empty
  Ubuntu:   10.10.10.2  /30                    gateway: empty

  Then: ssh user@10.10.10.2   (from Windows, out the Ethernet adapter)
```

Use a **private** `/30` (two usable hosts) or a slightly larger subnet if you add more gear later.

### D) Scale (~70 nodes): two planes

```
        [ Operator laptop ]
               |
          Wi-Fi or VPN
               |
         [ Lab LAN / gateway ]
          /     |     \
    [Node1] [Node2] ... [NodeN]
         \     |     /
      [ Ethernet fabric - east/west cluster traffic ]
```

- **Management:** you reach nodes via **stable LAN or VPN IPs** and **SSH** (or APIs).
- **Cluster traffic:** often **between nodes on Ethernet** (or a dedicated network), independent of how your laptop connects.

---

## 4. How to SSH when Windows and Ubuntu share Wi-Fi

1. On **Ubuntu** (from the **interactive shell** you already have): find addresses:

   ```bash
   ip -br a
   ```

   Note the **Wi-Fi or Ethernet** IPv4 that is on the **same subnet** as your Windows Wi-Fi (e.g. `192.168.x.x`).

2. On **Windows** (PowerShell or CMD):

   ```text
   ssh <username>@<that-ip>
   ```

   Use the **OpenSSH client** (`ssh`). The username is **whatever exists on Ubuntu** (`whoami` on the box), not a generic "default."

3. If **connection refused** or **timeout**:

   - **Timeout:** wrong IP, firewall, or not on the same L3 network.
   - **Refused:** **`sshd` not listening** or blocked.

   On Ubuntu, typical checks:

   ```bash
   sudo systemctl status ssh
   ss -tlnp | grep 22
   sudo ufw status
   ```

   Install server if needed (package names vary slightly by release):

   ```bash
   sudo apt update && sudo apt install -y openssh-server
   sudo systemctl enable --now ssh
   ```

4. At **~70 machines**, prefer **SSH keys** and **one** provisioning path (Ansible, cloud-init, or dirteel-style automation), not shared passwords.

---

## 5. Credentials (where they come from; no guessing here)

- **Ubuntu Desktop** installed by hand: the **user you created** in the installer.
- **Server / cloud images:** **cloud-init**, vendor README, or **serial console** output.
- **Corporate images:** **internal** runbook only.

If you have a **local interactive shell** on the machine, you already know **at least one** way in; use that to **create** `~/.ssh/authorized_keys`, **enable** `sshd`, and **document** the official username for automation (inventory YAML).

---

## 6. Relation to telvm, dirteel, and clustering

- **[Ubuntu lab node: network snapshot](lan-ubuntu-node-network-snapshot.md)** - **Ground truth** from **inside** a lab Ubuntu VM (`ip link`, `ip route`, `nmcli`): how **L2-up / L3-missing** and **Wi-Fi DOWN** clarify the **exact** connectivity gap.
- **[`inventories/lan-host/`](../inventories/lan-host/README.md)** - Store **per-host baseline** (IPs, listeners, notes) once you know them.
- **telvm scripts** - From Windows or the **companion** container: **reachability** probes and **inventory** helpers; they do not replace SSH on the node.
- **dirteel** (sibling repo, future) - **Provision/join** many hosts; assumes **repeatable** network facts and **SSH or HTTP APIs**, not a one-off patch cable.
- **Sane scale posture:** DHCP reservations or a **written IP plan**, **DNS or inventory DB**, **one bootstrap** per wave of nodes, **BMC/serial** for break-glass.

---

## 7. Scripts to run next (Windows)

- **General LAN + optional target IP:** [`scripts/windows/lan-ethernet-connection-state.ps1`](../scripts/windows/lan-ethernet-connection-state.ps1) (use **`-TargetVmIp`** when you have the Ubuntu address).
- **Switch segment + default route vs Wi-Fi:** [`scripts/windows/inspect-switch-uplink.ps1`](../scripts/windows/inspect-switch-uplink.ps1) (Ethernet on **10.10.10.x** may have **no** IPv4 gateway while **Wi-Fi** holds the default route).
- **Direct cable focus (APIPA, ARP, static /30 hint):** [`scripts/windows/lan-direct-cable-peer.ps1`](../scripts/windows/lan-direct-cable-peer.ps1) (use **`-PeerIp`** and optionally **`-GuessPing169ThirdOctet`**).
- **Quick TCP check:** [`scripts/windows/test-lan-connectivity.ps1`](../scripts/windows/test-lan-connectivity.ps1).

**UniFi gateway + static Netplan for lab nodes (.11 / .12):** [UniFi + Netplan lab runbook](lan-unifi-netplan-lab-runbook.md).

Companion container probes and env vars are described in [`inventories/lan-host/README.md`](../inventories/lan-host/README.md) and the repo **`.env.example`**.

---

## 8. What this assistant cannot do

It cannot **SSH into your network**, **scan** your LAN, or **verify passwords**. Run **`ssh`** and **`Test-NetConnection`** on **your** PC, and keep secrets out of git (see **`baseline.local.yaml`** gitignore pattern in the repo).
