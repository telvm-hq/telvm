# telvm agents

Small programs and services that sit **beside** or **under** the [companion](../companion) Phoenix app: probes, sidecars, and LAN/edge helpers. Each agent has its own directory and README; this file is the **atlas** view.

## Stack topology (bird’s eye)

```
                         +---------------------------+
                         |   companion (:4000)       |
                         |   LiveView + egress       |
                         +--+--------+--------+------+
                            |        |        |
         HTTP poll         |        |        |  docker.sock / compose
              +------------+        |        +------------------------+
              |                     |                                 |
              v                     v                                 v
   +--------------------+   +------------------+            +------------------+
   | telvm-network-agent |   | EgressProxy      |            | docker engine    |
   | (Windows gateway)   |   | :4001 :4002 :4003|            | morayeel_lab     |
   +----------+---------+   +--------+---------+            | closed agents    |
              |                      |                       +------------------+
              | LAN / ICS            | CONNECT / GET
              v                      v
   +--------------------+   +------------------+
   | LAN hosts          |   | dirteel          |
   | (ARP, probes)      |   | (Zig CLI probe)  |
   +--------------------+   +------------------+

   +--------------------+   +------------------+
   | Linux cluster nodes|   | retardeel        |
   | telvm-node-agent   |   | (Zig FS jail)    |
   +--------------------+   +------------------+

   +--------------------+
   | morayeel           |
   | (Playwright image) |-----> morayeel_runs volume + LiveView "Morayeel" tab
   +--------------------+
```

---

## `dirteel/` — egress probe (Zig)

**Role:** Static binary: exercise **HTTP CONNECT** (and helpers) through companion’s **egress listener** with the same contract as `curl --proxy`; keep **`profiles/closed_images.json`** aligned with the Elixir catalog.

```
  [ container or host ]              [ companion ]
         |                                |
         |  dirteel egress-probe          |
         |  curl --proxy :4001          v
         +---------------------------> Listener
                                              |
                                              v
                                       upstream :443
```

Details: [dirteel/README.md](dirteel/README.md)

---

## `retardeel/` — jailed filesystem agent (Zig)

**Role:** HTTP API over a **chroot-like** workspace root: list/read/write files inside a declared tree only. Drop into lab containers for IDE / tooling without mounting the whole host.

```
  [ client : IDE ]                    [ retardeel ]
         |                                  |
         |  GET /v1/workspace               |
         +--------------------------------->|
         |                                  |
         |                    +-------------v-------------+
         |                    | root = /tmp/lab-workspace |
         |                    | (no escape upward)      |
         |                    +-------------------------+
```

Details: [retardeel/README.md](retardeel/README.md)

---

## `telvm-node-agent/` — Linux node + Docker slice (Zig)

**Role:** Runs on **Ubuntu** cluster nodes; narrow **Docker Engine HTTP** proxy + health. Companion **polls** these agents to show machines / engine state.

```
  [ companion ] ----HTTP poll----> [ telvm-node-agent :9100 ]
                                           |
                                           v
                                    [ docker.sock ]
```

Details: [telvm-node-agent/README.md](telvm-node-agent/README.md)

---

## `telvm-network-agent/` — Windows gateway / LAN (PowerShell)

**Role:** On the **Windows** gateway PC: **ICS** state, LAN discovery, small JSON API. Companion polls it like the Linux node agent (different OS, same pattern).

```
  [ companion ] ----HTTP----> [ network-agent :9225 ]
                                     |
                                     v
                              [ ARP / ICS / LAN ]
```

Details: [telvm-network-agent/README.md](telvm-network-agent/README.md)

---

## `morayeel/` — headless browser lab (Playwright + tiny Node lab)

**Role:** **Playwright** drives Chromium in Docker; writes **`storageState.json`**, **`network.har`**, **`run.json`** to volume **`morayeel_runs`**; companion **MorayeelRunner** + **LiveView** tab trigger runs and show logs / downloads.

```
  [ morayeel run container ]     [ morayeel_lab :8080 ]
         |                                ^
         |  goto lab (compose DNS)        | Set-Cookie (synthetic)
         +--------------------------------+
         |
         v
  morayeel_runs:/artifacts/<run_id>/...
         |
         === same volume ===> [ companion:/morayeel-runs ]
```

Details: [morayeel/README.md](morayeel/README.md)

---

## Adding another agent

Keep it **one directory**, **one README**, **one responsibility**; link it here with a five-line ASCII diagram so the next reader does not have to diff your soul from `git log`.
