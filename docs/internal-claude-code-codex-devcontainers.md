# Internal note: Claude Code vs Codex devcontainer topology

This document summarizes upstream [anthropics/claude-code](https://github.com/anthropics/claude-code) and [openai/codex](https://github.com/openai/codex) as **VS Code Dev Container** setups (not generic “soak” lab images). It focuses on `.devcontainer/` layout, how each agent is delivered in-container, and what the shared `init-firewall.sh` pattern does.

Sources: upstream `devcontainer.json`, `Dockerfile` / `Dockerfile.secure`, and `init-firewall.sh` as of the repos’ `main` branches (fetched 2026-04-11).

---

## Topology at a glance

| Aspect | Claude Code | Codex |
|--------|-------------|--------|
| **Primary devcontainer** | Single profile: “Claude Code Sandbox” | **Two profiles**: contributor (`devcontainer.json`) vs customer-oriented **secure** (`devcontainer.secure.json`) |
| **Base image** | `node:20` | Contributor: `ubuntu:24.04`. Secure: `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` |
| **Agent install** | `npm install -g @anthropic-ai/claude-code` (version via build arg) | Secure: `npm install -g @openai/codex` + Corepack/pnpm. Contributor: Rust toolchain only (build from source) |
| **Firewall in default flow** | **Always** (`postStartCommand` → `init-firewall.sh`) | **Contributor: none.** **Secure: optional** via `CODEX_ENABLE_FIREWALL` (default on) |
| **Linux caps** | `NET_ADMIN`, `NET_RAW` | Secure only: same caps. Contributor: none listed |
| **Remote user** | `node` | Contributor: `ubuntu`. Secure: `vscode` |

---

## Shared functionality (both codebases)

- **Dev Container pattern**: `devcontainer.json` + `Dockerfile` (Codex secure adds `Dockerfile.secure`), workspace bind-mount under `/workspace`, editor customizations (extensions, terminal shell).
- **Outbound restriction concept**: Post-start logic configures **iptables** + **ipset** (`allowed-domains` hash:net) so only resolved IPv4 targets and (when enabled) **GitHub meta** CIDRs are allowed; default policy is restrictive after setup.
- **Docker DNS preservation**: Both scripts snapshot `iptables-save -t nat` lines for `127.0.0.11` and re-apply them after flushing tables, so embedded Docker DNS keeps working.
- **Allow DNS + loopback** early in the rule set; **allow traffic to host gateway /24** (detected from default route) for typical bridge networking.
- **Verification**: Both `curl` **https://example.com** and expect failure after rules are applied; both confirm reachability to an allowlisted API (`api.github.com` in Claude; `api.openai.com` + conditional GitHub in Codex secure).
- **Tooling in firewall path**: `dig`, `jq`, `curl`, `ipset`, `iptables`, `iproute2`; Claude also uses **`aggregate`** to merge GitHub CIDRs before adding to ipset.

---

## Differences that matter for integration

### 1. When the firewall runs

- **Claude Code**: Firewall is **mandatory** for the documented devcontainer; `postStartCommand` is `sudo /usr/local/bin/init-firewall.sh` with `waitFor: postStartCommand`. Sudo is limited to that script for `node`.
- **Codex**: The **default** contributor container has **no** `postStartCommand` firewall—it's a lightweight Rust build image (`platform: linux/arm64`). The **secure** profile uses `post-start.sh`, which can skip the firewall entirely if `CODEX_ENABLE_FIREWALL != 1`.

### 2. How allowlists are defined

- **Claude Code**: Domains are **hardcoded** in `init-firewall.sh` (npm registry, Anthropic API, Sentry/Statsig, VS Code marketplace/update hosts). GitHub ranges come from `https://api.github.com/meta` and are merged with `aggregate`.
- **Codex secure**: Domains come from env **`OPENAI_ALLOWED_DOMAINS`** (comma/space separated); `post-start.sh` writes `/etc/codex/allowed_domains.txt`, then `init-firewall.sh` reads that file (or falls back to `api.openai.com`). GitHub meta inclusion is toggled with **`CODEX_INCLUDE_GITHUB_META_RANGES`** (default on).

### 3. IPv6 and rule symmetry

- **Codex** `init-firewall.sh` adds **`configure_ipv6_default_deny`** (`ip6tables` default DROP) and verifies that **IPv6** to example.com fails—closing a bypass path for allowlist-only IPv4 ipset rules.
- **Claude Code** `init-firewall.sh` does **not** configure `ip6tables`; policy is IPv4-oriented only in the fetched script.

### 4. Extra services / SSH

- **Claude Code** explicitly allows outbound/inbound **SSH** (port 22) in iptables.
- **Codex** secure script (fetched) does **not** add a special SSH allow rule in the same way; policy is centered on DNS, localhost, host LAN, established connections, and the ipset.

### 5. Hooks beyond the firewall

- **Codex secure** runs **`post_install.py`** after create (history dirs, `chown` fixes for mounted volumes, local git config merge). **Claude Code** relies on image build + devcontainer mounts for `~/.claude` and command history.

### 6. Platform assumptions

- **Codex contributor** `devcontainer.json` pins **`linux/arm64`** in build and `runArgs`, which is awkward on **x86_64** hosts unless emulation is acceptable.
- **Claude Code** does not pin architecture in the fetched `devcontainer.json` (Node image follows platform).

---

## Conceptual assessment: “drop into local soak images”

**What these repos are:** definitions for **Dev Containers** (build context, VS Code metadata, lifecycle hooks). They are **not** drop-in replacements for minimal lab images (e.g. small Alpine service images) unless you intentionally merge their Docker layers and runtime contract.

**Seamlessness — moderate friction, not zero:**

1. **Capability model**: Strict networking requires **`NET_ADMIN` and `NET_RAW`**. Generic soak pools often avoid privileged caps; without them, `init-firewall.sh` will not work as designed.
2. **Linux-only inside the container**: Iptables/ipset assume a **Linux network namespace**. On Windows/macOS this runs inside Docker’s Linux VM; behavior is consistent with “Linux container,” not native Windows networking.
3. **Two different “Codex” stories**: Only **`devcontainer.secure.json`** matches the Claude-style “agent + locked-down egress” mental model. The **default** Codex devcontainer is for **building Codex**, not for shipping the prebuilt CLI with firewall.
4. **Maintenance**: Allowlists must track **DNS drift** (ipset stores IPs resolved at start). New third-party endpoints require script edits (Claude) or env updates (Codex secure).
5. **Auth remains external**: Images install CLIs; **API keys / ChatGPT sign-in / subscriptions** are still required at runtime—containers don’t bundle credentials.
6. **License / redistribution**: Treat CLI packages and branding as upstream terms; this note does not cover legal review.

**Practical integration paths (high level):**

- **A. Reuse Dockerfiles**: Extract `Dockerfile` / `Dockerfile.secure` and run with the same `runArgs` and entrypoint sequence (or a single combined image) in your compose/soak stack.
- **B. Dev Containers CLI**: Keep upstream `devcontainer.json` and use `devcontainer up` (or IDE) for parity with upstream—good for developer sandboxes, heavier for automated soak.
- **C. Cherry-pick firewall only**: Mount a unified `init-firewall.sh` + allowlist mechanism if the goal is only egress control, not full parity with either upstream image.

---

## File map (upstream)

**Claude Code** — [.devcontainer](https://github.com/anthropics/claude-code/tree/main/.devcontainer):

- `devcontainer.json` — build args (TZ, versions), caps, mounts for bash history and `~/.claude`, `postStartCommand` firewall.
- `Dockerfile` — Node 20, tooling, global `claude-code`, copies `init-firewall.sh`, sudoers for firewall only.
- `init-firewall.sh` — iptables/ipset, GitHub meta + fixed domain list, verification.

**Codex** — [.devcontainer](https://github.com/openai/codex/tree/main/.devcontainer):

- `devcontainer.json` — contributor Rust image, **no** firewall.
- `devcontainer.secure.json` — secure profile: caps, many named volumes, env allowlist + `OPENAI_API_KEY` from host, `postCreateCommand` / `postStartCommand`.
- `Dockerfile` / `Dockerfile.secure` — contributor vs full secure stack (Node + Codex npm, Rust, firewall scripts).
- `post-start.sh` — writes allowlist file; invokes `init-firewall.sh` unless disabled.
- `post_install.py` — volume ownership and git helper files.
- `init-firewall.sh` — file-driven domains, optional GitHub meta, IPv6 deny, stricter REJECT coverage on chains.

For Codex’s own description of the two container paths, see upstream [.devcontainer/README.md](https://github.com/openai/codex/blob/main/.devcontainer/README.md).

---

## Default egress vs `init-firewall` placement

Containers on the default Docker bridge reach the internet via **NAT** through the host unless restricted. Upstream **`init-firewall.sh`** scripts target **Linux netfilter** and are meant to run **inside** the devcontainer (with `NET_ADMIN`), not on the Windows host. The Windows **telvm-network-agent** is separate (**ICS / LAN observation**). Telvm’s **lab_relaxed** published images (`telvm-closed-claude`, `telvm-closed-codex`) do not run `init-firewall` by default; see [closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md#default-docker-egress-and-where-init-firewall-runs).

---

## Telvm: closed-agent harness (Companion + Docker)

For provisioning **closed-inference** agent containers on the same machine as the companion while **composing with** the Windows `telvm-network-agent` (ICS / LAN truth vs Docker egress truth), see:

- [closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md)
- [closed-agent-provision-tab-wireframe.md](closed-agent-provision-tab-wireframe.md)
- [closed-agent-docker-labels.md](closed-agent-docker-labels.md)
- [closed-agent-integration-test-matrix.md](closed-agent-integration-test-matrix.md)
- [closed-agent-upstream-submodule-policy.md](closed-agent-upstream-submodule-policy.md)

---

## References

- [anthropics/claude-code](https://github.com/anthropics/claude-code)
- [openai/codex](https://github.com/openai/codex)
