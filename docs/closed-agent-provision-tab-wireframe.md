# Closed-inference agent provisioning tab — UX wireframe

ASCII wireframes for a **new top-level nav tab** (name TBD: e.g. **Closed agents** or **Provision agents**) and how it connects to **Pre-flight** and **Warm assets**. No implementation detail; layout and flow only.

**Related:** [closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md) · [closed-agent-docker-labels.md](closed-agent-docker-labels.md)

---

## 1. Global nav (conceptual)

```
+------------------------------------------------------------------+
|  Warm assets | Machines | Agent setup | Pre-flight | [Closed agents] |
+------------------------------------------------------------------+
```

- **Closed agents** — provisioning wizard + harness status (this tab).
- **Pre-flight** — Windows + ICS + `telvm-network-agent` + LAN hosts (unchanged authority); **deep link** from Closed agents: “Open Pre-flight for gateway / LAN”.
- **Warm assets** — all warm workloads including provisioned agent containers (typed rows); **deep link** from Closed agents: “View in Warm assets”.

---

## 2. Closed agents tab — top region (context strip)

Always visible after first paint when companion has poller data:

```
+------------------------------------------------------------------+
|  Harness context (read-only)                                      |
|  [ PS agent: OK | unreachable ]   ICS: [ on/off ]  Uplink: ...   |
|  LAN subnet (physical): 192.168.137.0/24  (from Pre-flight data) |
|  Note: Agent containers use Docker bridge unless advanced attach. |
|  [ Link: Open Pre-flight ]                                        |
+------------------------------------------------------------------+
```

- Soft gate: if PS agent unreachable, show **warning banner** + “Continue anyway” for Docker-only actions (per harness contract).

---

## 3. Wizard steps (vertical or stepped horizontal)

### Step 1 — Choose profile

```
+------------------------+
|  Profile               |
|  ( ) Claude Code       |
|  ( ) OpenAI Codex      |
|      [ ] secure egress |
|  [ Next ]              |
+------------------------+
```

- **secure egress** maps to harness **strict** tier when implemented.

### Step 2 — Egress + resources

```
+------------------------+
|  Egress tier           |
|  ( ) lab_relaxed       |
|  ( ) strict            |
|                        |
|  Ports / volumes       |
|  (summary read-only    |
|   from profile spec)   |
|  [ Back ]  [ Next ]    |
+------------------------+
```

### Step 3 — Provision / teardown

```
+------------------------+
|  Actions               |
|  [ Provision ]         |
|  [ Teardown selected ] |
|                        |
|  Last result           |
|  OK / error message    |
|  [ Link: View in Warm ]|
+------------------------+
```

### Step 4 — API key (operator deliberate)

```
+------------------------+
|  Vendor API key        |
|  (not stored in telvm)  |
|  Instructions:          |
|  - mount file …         |
|  - or env at start …    |
|  State: provisioned_no_key |
|  [ Link: docs ]         |
+------------------------+
```

- No key input field in Phoenix that persists to DB (align with harness contract).

---

## 4. Optional lower panel — running instances table

```
+------------------------------------------------------------------+
|  Managed closed-agent containers                                 |
+--------+------------+----------+-----------+---------------------+
| Type   | Name       | State    | Egress    | Actions             |
+--------+------------+----------+-----------+---------------------+
| claude | telvm-...  | running  | strict    | Logs | Restart | …  |
| codex  | telvm-...  | exited   | lab_rel.  | Logs | Start   | …  |
+--------+------------+----------+-----------+---------------------+
|  [ Refresh ]  [ Open Warm assets filtered ]                      |
+------------------------------------------------------------------+
```

---

## 5. Warm assets tab — row types (extension)

Existing warm list gains **typed** rows (visual distinction only in wireframe):

```
+------------------------------------------------------------------+
|  Warm assets                                                      |
+--------+------------------+---------+---------------------------+
| Type   | Name / image     | State   | Quick actions             |
+--------+------------------+---------+---------------------------+
| lab    | telvm-lab-…      | running | logs …                    |
| agent  | telvm-agent-…   | running | logs | key help | preflight|
+--------+------------------+---------+---------------------------+
```

- **agent** rows: same `docker logs` affordance as today; add **key help** (modal = Step 4 copy); **preflight** link.

---

## 6. Pre-flight tab — unchanged block + inbound link

Pre-flight keeps current **Network / ICS** panel. Optional one-line when user landed from Closed agents:

```
(You followed a link from Closed agents — ICS data is authoritative for the physical LAN.)
```

---

## 7. Flow diagram (operator journey)

```
  Nav: Closed agents
        |
        v
  Context strip (PS agent + ICS summary + link Pre-flight)
        |
        v
  Wizard: profile -> egress -> provision
        |
        v
  Success -> "View in Warm assets" + key instructions
        |
        v
  Warm assets: agent row -> logs / restart
```

---

## Revision

Update when nav label is finalized, when advanced LAN attach (macvlan) is offered as a wizard branch, or when new vendor profiles are added.
