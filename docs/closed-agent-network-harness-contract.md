# Closed-agent network harness — formal contract

This document defines how **telvm** composes three operational planes on a **single Windows host** with **Docker**: the PowerShell **telvm-network-agent** (Windows / ICS truth), **Docker** (container egress truth), and **vendor APIs** (closed inference). It is normative for UI copy, provisioning defaults, and integration tests.

**Related:** [closed-agent-docker-labels.md](closed-agent-docker-labels.md) · [closed-agent-integration-test-matrix.md](closed-agent-integration-test-matrix.md) · [closed-agent-provision-tab-wireframe.md](closed-agent-provision-tab-wireframe.md) · [telvm-network-agent README](../agents/telvm-network-agent/README.md)

---

## Default Docker egress and where `init-firewall` runs

**Default path to the internet (typical Compose / bridge container):** Process traffic leaves the container’s **Linux network namespace**, is **NAT’d** through the Docker bridge (on Docker Desktop for Windows: the Linux VM, then the Windows host stack), then to the uplink. No extra wiring is required for general HTTPS/DNS unless the host, a proxy, or an **in-container** policy blocks it.

**Upstream `init-firewall.sh` (Claude Code / Codex secure devcontainers):** These scripts manipulate **`iptables` / `ipset`**. They are intended to run **inside the same Linux environment as the workload** (usually **inside the container** at post-start, with `NET_ADMIN` / `NET_RAW`), **not** on the Windows host as a substitute for Windows Firewall. Running them on the host would be the wrong layer: **Plane A** uses the PowerShell **telvm-network-agent** and Windows Firewall semantics; **Plane B** optional allowlisting uses Linux netfilter **inside** the container netns.

**telvm-published “lab_relaxed” images** ([`images/telvm-closed-claude`](../images/telvm-closed-claude/README.md), [`images/telvm-closed-codex`](../images/telvm-closed-codex/README.md)) ship **without** executing `init-firewall` by default so they start quickly; egress is the default NAT path until you adopt a strict profile.

---

## 1. Planes of responsibility

### 1.1 Plane A — Windows host (telvm-network-agent)

**Authority:** Physical adapters, ICS public/private roles, typical ICS LAN addressing (e.g. `192.168.137.0/24`), ARP/neighbor host inventory, optional reachability diagnostics.

**Not authoritative for:** Linux container iptables, Docker bridge IPAM, or which URLs a process inside a container may call.

```
+--------------------------- WINDOWS HOST ---------------------------+
|  telvm-network-agent (PS)     ICS uplink / LAN / JSON HTTP        |
|         ^                                                        |
|         |  companion reaches via host.docker.internal (typical)   |
+---------|----------------------------------------------------------+
```

### 1.2 Plane B — Docker (Linux netns per container)

**Authority:** Container egress path (bridge NAT, published ports, internal DNS), image-defined optional **init-firewall** (iptables/ipset) inside the container’s network namespace.

**Not authoritative for:** Windows Firewall profiles or ICS COM state.

```
+---------v----------------------------------------------------------+
|              DOCKER (Linux VM / bridge on Windows)                 |
|   +----------------+   +------------------+   +------------------+ |
|   | companion      |   | optional ollama |   | closed-agent ctr | |
|   +----------------+   +------------------+   +------------------+ |
|          |                        ^                      |           |
|          +-------- HTTP to vendors / host --------------+           |
+-----------------------------------------------------------------------+
          |
          v
    [ Internet / host.docker.internal ]
```

### 1.3 Plane C — Vendor (closed inference)

**Authority:** API availability, authentication, rate limits.

**Contract:** Vendor API keys and OAuth material enter only via **operator-controlled injection** (mounted secret file, runtime env, or deliberate exec). They are never baked into images committed to git and must not appear in application logs.

---

## 2. Cross-plane coherence (the harness)

The **harness** is the set of rules telvm uses to **correlate** snapshots from Plane A with desired and actual state in Plane B, without claiming false ownership.

| Contract piece | Obligation |
|----------------|------------|
| **Context snapshot** | Provisioning UI and backend logic may consume `NetworkAgentPoller` data (health, ICS status, LAN hosts) as **read-only context** for warnings and copy (e.g. uplink down, subnet string). |
| **Docker network profile** | Each closed-agent profile declares: default network attachment (Compose project network vs host-gateway), DNS expectations (`host.docker.internal`), optional `extra_hosts` for internal names. |
| **Egress policy profile** | Each profile declares **lab_relaxed** (full bridge egress unless host firewall blocks) vs **strict** (in-container allowlist per upstream devcontainer pattern). The UI must name which profile is active. |
| **Inference routing** | **Closed-vendor inference** = HTTPS to Anthropic/OpenAI (and documented ancillary hosts). **Local inference** (e.g. Ollama) is a **separate URL class**; UI and docs must not conflate “base URL” for local chat with vendor API endpoints for agent CLIs. |
| **Observability hooks** | After provision: container health via inspect or in-container probe; **one plain-language line** when ICS data exists: LAN subnet is for **physical** peers shown in Pre-flight; default agent containers use **Docker bridge** unless an **advanced attach** profile (macvlan/ipvlan) is explicitly documented and selected. |

**Explicit non-claim:** The PowerShell agent does **not** validate or enforce Docker egress. UI must not imply it does.

---

## 3. Egress tiers

| Tier | In-container firewall | Typical use |
|------|------------------------|-------------|
| **lab_relaxed** | None or minimal | Fast local iteration; relies on host trust and workspace mounts. |
| **strict** | iptables/ipset allowlist (upstream-style) | Reduced arbitrary egress; requires `NET_ADMIN` / `NET_RAW` in container; allowlist must include all vendor and tooling endpoints for that CLI. |

**IPv6:** If strict tier mirrors scripts that only populate IPv4 ipsets, either adopt **ip6tables default-deny** (Codex-style) or document **IPv4-only restriction** and residual IPv6 risk.

---

## 4. Secret lifecycle

States (for UI and runbooks):

1. **provisioned_no_key** — Image/volumes exist; container may be stopped or idle; no vendor credential in env.
2. **running_with_key** — Operator injected key; agent may call vendor APIs per egress tier.
3. **blocked** — Network or policy failure (e.g. strict egress missing domain, uplink down on host).

Rules:

- Keys only via mount, env at `docker run`, or one-shot injection; never commit to VCS.
- Verify `docker inspect` and telvm logs never echo secrets.

---

## 5. Bridge vs advanced LAN attach

**Story A (default per release unless B is chosen):** Agent containers on **Docker bridge**; reach Windows host via `host.docker.internal`; reach internet via Docker NAT; **ICS LAN** visible in Pre-flight is **orthogonal** (physical lab), not automatically the container’s L2 segment.

**Story B (optional, ops-heavy):** **macvlan/ipvlan** (or equivalent) so a container receives an address on the **same L3 segment as ICS clients**. Requires explicit documentation, IP coordination, and Docker Desktop / host constraints.

**Rule:** Do not mix A and B in operator-facing defaults without a clear profile switch.

---

## 6. Companion integration points

- **Existing:** `TELVM_NETWORK_AGENT_URL`, `NetworkAgentPoller`, Pre-flight LiveView section (ICS / LAN context only — not Docker egress enforcement).
- **Egress enforcement (two layers, complementary):**
  1. **In-container (strict tier):** Upstream-style `init-firewall` / iptables allowlist in the **closed-agent container** netns (see §3). Requires `NET_ADMIN` / `NET_RAW` when you adopt that profile.
  2. **Companion Elixir proxy (optional):** One HTTP listener per configured **workload** (`TELVM_EGRESS_ENABLED`, `TELVM_EGRESS_WORKLOADS` or `TELVM_EGRESS_WORKLOADS_FILE`). Agents point `HTTP_PROXY` / `HTTPS_PROXY` at `http://companion:<port>`. Policy is host/SNI allowlist plus structured JSON denies; the allowlist must include **any host `apt` / `npm` / other tooling** will reach (e.g. **`.debian.org`** for `apt-get update` through the proxy), not only vendor API domains. Vendor `Authorization` may be injected from **runtime env** named per workload (`authorization_env`) — **not** from Postgres or the UI DB.
- **Dashboard:** Pre-flight shows proxy rows (internal URL, allowlist digest, recent denies) and PubSub `egress_proxy:updates`. This is **read-only** LiveView; proxy processes run under `Companion.EgressProxy.Supervisor`, not inside the LiveView process.
- **Bypass caveat:** Tools that ignore `HTTP_PROXY` / `HTTPS_PROXY` can still attempt direct egress; strict **in-container** firewall is the backstop for those paths when enabled.
- **Future:** Provisioning tab may read the same snapshots for **Plane A** context; Docker adapter supplies **Plane B** container facts; secrets remain **Plane C** operator-owned.

---

## Revision

Bump this doc when adding a new vendor profile, changing default network story A/B, or altering egress tier definitions.
