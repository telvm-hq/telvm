# Closed-agent + PowerShell network harness — integration test matrix

Runnable **manual** checklist for a **single Windows machine** with Docker and [telvm-network-agent](../agents/telvm-network-agent/README.md). Automate later by mapping each row to CI or scripted probes where feasible.

**Related:** [closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md) · [closed-agent-docker-labels.md](closed-agent-docker-labels.md)

**How to use:** Execute in order within a group when dependencies apply; check **Pass/Fail** and note evidence (screenshot, command output path).

---

## A. PowerShell network agent alone

| ID | Scenario | Steps | Expected | Pass |
|----|----------|-------|----------|------|
| A1 | Agent up, token set | Start `Start-NetworkAgent.ps1` with token; set companion `TELVM_NETWORK_AGENT_*`; open Pre-flight | Health shows reachable; hostname/version present | [ ] |
| A2 | Agent down | Stop network agent; refresh Pre-flight | Unreachable / degraded; no crash in companion | [ ] |
| A3 | ICS enabled | Enable ICS on gateway; poll `/ics/status` or Pre-flight | `enabled`, `gateway_ip`, `subnet` consistent | [ ] |
| A4 | ICS disabled | Disable ICS; refresh | Fields reflect disabled; UI copy still accurate | [ ] |

---

## B. Docker without closed-agent containers

| ID | Scenario | Steps | Expected | Pass |
|----|----------|-------|----------|------|
| B1 | Companion to inference | Configure inference URL; Agent setup or probe | Models or health OK per config | [ ] |
| B2 | Companion to network agent | With A1, Pre-flight polls | Snapshot updates on interval | [ ] |

---

## C. One Claude-profile container (when provisioned)

| ID | Scenario | Steps | Expected | Pass |
|----|----------|-------|----------|------|
| C1 | Provision | Create container with [closed-agent labels](closed-agent-docker-labels.md), Claude profile | Container exists | [ ] |
| C2 | Warm assets | Open Warm assets; refresh | Row type **agent**, vendor anthropic | [ ] |
| C3 | No API key | Do not inject key; observe state | Documented idle/stopped; no vendor traffic | [ ] |
| C4 | With API key + lab_relaxed | Inject key; minimal CLI or API check | Reachability to `api.anthropic.com` (and required ancillaries) succeeds | [ ] |
| C5 | Strict egress negative | Blocked URL curl from inside container | Fails as designed | [ ] |
| C6 | Strict egress positive | Allowlisted vendor endpoint | Succeeds | [ ] |

---

## D. One Codex-profile container (when provisioned)

| ID | Scenario | Steps | Expected | Pass |
|----|----------|-------|----------|------|
| D1 | Provision | Codex profile + labels | Container exists | [ ] |
| D2 | Warm assets | Refresh | Row type **agent**, vendor openai | [ ] |
| D3 | GitHub meta toggle | If mirroring Codex secure: `CODEX_INCLUDE_GITHUB_META_RANGES` off vs on | GitHub access matches toggle | [ ] |
| D4 | IPv6 | If strict + ip6tables: `curl -6` to non-allowlisted host | Fails; document if IPv4-only path instead | [ ] |

---

## E. Two containers (Claude + Codex)

| ID | Scenario | Steps | Expected | Pass |
|----|----------|-------|----------|------|
| E1 | Ports | Publish or document internal ports | No bind conflicts | [ ] |
| E2 | Volumes | Distinct volume names | No collision | [ ] |
| E3 | Logs | Tail each | Independent streams | [ ] |

---

## F. Secret safety

| ID | Scenario | Steps | Expected | Pass |
|----|----------|-------|----------|------|
| F1 | Inspect | `docker inspect` on running agent container | No plaintext key in env JSON if using file mount pattern | [ ] |
| F2 | Companion logs | Grep companion logs after key injection | No key material | [ ] |

---

## G. Order of operations

| ID | Scenario | Steps | Expected | Pass |
|----|----------|-------|----------|------|
| G1 | PS agent after Docker | Start Docker first, then PS agent | Companion recovers when agent starts | [ ] |
| G2 | Docker before PS agent | Stop PS agent; leave containers running | Pre-flight shows agent offline; containers still listed in Docker | [ ] |

---

## H. Harness correlation (Windows + Docker)

| ID | Scenario | Steps | Expected | Pass |
|----|----------|-------|----------|------|
| H1 | Copy accuracy | With ICS data, open Closed agents (when implemented) or harness doc | Plain-language line: LAN = physical; default agents = bridge | [ ] |
| H2 | Optional stretch | Known lab host on wire; compare `/ics/hosts` | Expected IP appears | [ ] |

---

## Sign-off

| Date | Operator | Environment (OS / Docker / branch) | Notes |
|------|----------|-----------------------------------|-------|
|      |          |                                   |       |
