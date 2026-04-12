# Upstream Claude Code / Codex — submodule vs vendored policy

**Decision for telvm:** Prefer **git submodules** for upstream agent **source definitions** (`anthropics/claude-code`, `openai/codex`) when those trees are needed as **build context or reference** (e.g. devcontainer JSON, upstream `init-firewall.sh`). Always keep a **thin telvm adapter layer** in-repo (Compose services, Dockerfiles that COPY from submodule paths, label conventions) that is **not** generated solely from upstream.

**Related:** [internal-claude-code-codex-devcontainers.md](internal-claude-code-codex-devcontainers.md) · [closed-agent-docker-labels.md](closed-agent-docker-labels.md)

---

## 1. Rationale

| Approach | Verdict |
|----------|---------|
| **Submodule** | **Chosen** for provenance, explicit **pin** to a commit, and clear boundary between “upstream” vs “telvm-owned overlay”. |
| **Vendored copy without submodule** | Acceptable for CI-only snapshots if submodule friction blocks contributors; document alternate in CONTRIBUTING. |
| **Fork-per-vendor** | Use only if telvm must carry **long-lived patches** upstream will not take; otherwise avoid maintenance tax. |

---

## 2. Submodule layout (conceptual)

```
telvm/
  third_party/
    claude-code/     # submodule -> anthropics/claude-code @ <pin>
    codex/           # submodule -> openai/codex @ <pin>
  docs/
    closed-agent-upstream-submodule-policy.md   # (this file)
```

Exact paths are chosen when implementation lands; policy requires **one directory per upstream** and **no** manual copy of upstream files into random paths without recording the commit.

---

## 3. Pin and update process

1. **Initial pin:** Record upstream commit SHA in this doc or in `docs/releases` note when adding submodule.
2. **Update cadence:** Periodic (e.g. monthly) or on-demand when security/CVE or devcontainer breaking change is announced.
3. **Update steps (operator):**
   - `cd third_party/claude-code` (or `codex`)
   - `git fetch origin && git checkout <new_sha>` (detached OK)
   - Return to telvm root; commit **submodule pointer** change.
4. **Regression:** Run **relevant rows** of [closed-agent-integration-test-matrix.md](closed-agent-integration-test-matrix.md) after each pin bump, especially **strict egress** and **Compose build** paths.

---

## 4. CI expectations

- Clone with **submodules** (`git submodule update --init --recursive`) in CI and contributor docs.
- Fail fast if submodule path required by Dockerfile is empty.

---

## 5. What submodules do **not** replace

- **Docker image publishing** (if any) remains telvm-controlled.
- **Label contract** ([closed-agent-docker-labels.md](closed-agent-docker-labels.md)) remains telvm-owned.
- **Harness contract** ([closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md)) remains telvm-owned.

---

## 6. Alternatives if submodules are removed later

- **Sparse fetch script:** Pin SHA in a small manifest file; script clones depth-1 into `third_party/` at build time.
- Document migration in CHANGELOG when switching.

---

## Revision log

| Date | Change |
|------|--------|
| 2026-04-12 | Initial pins: `third_party/claude-code` @ `9772e13f820002c9730af67a2409702799c7ddc6`; `third_party/codex` @ `1325bcd3f6ff054d88170413f0946c3434533430`. |
