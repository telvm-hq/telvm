# Closed-agent Docker naming and labels

Convention so **Warm assets**, provisioning orchestration, and logs pick up **closed-inference agent** containers without scattered name heuristics. Apply at **container create** time (Compose `labels` / `docker run --label`).

**Related:** [closed-agent-network-harness-contract.md](closed-agent-network-harness-contract.md) · [closed-agent-provision-tab-wireframe.md](closed-agent-provision-tab-wireframe.md)

---

## 1. Required labels (normative)

| Label key | Value | Meaning |
|-----------|--------|---------|
| `telvm.agent` | `closed` | Participates in closed-agent provisioning / harness. |
| `telvm.agent.vendor` | `anthropic` \| `openai` | Vendor family for UI and docs links. |
| `telvm.agent.product` | `claude-code` \| `codex` | Specific product profile. |
| `telvm.agent.egress` | `lab_relaxed` \| `strict` | Harness egress tier (see harness contract). |

**Optional:**

| Label key | Value | Meaning |
|-----------|--------|---------|
| `telvm.agent.profile` | string | Versioned profile id inside telvm (e.g. `claude-code-secure-v1`). |
| `telvm.managed_by` | `telvm-companion` | Set when companion or a telvm script creates the container. |

---

## 2. Container name prefix

**Pattern:** `telvm-agent-<vendor>-<product>-<suffix>`

Examples (illustrative):

- `telvm-agent-anthropic-claude-code-a`
- `telvm-agent-openai-codex-b`

Rules:

- **Prefix** `telvm-agent-` reserved for this class (avoid for unrelated workloads).
- **suffix** — short random or operator slug; unique per machine.
- Names must stay **DNS-safe** (lowercase, hyphens).

**Classification rule for UIs:** If `telvm.agent=closed` is present on inspect, treat as **closed agent row**; else fall back to legacy heuristics only during migration.

---

## 3. Compose service names (optional alignment)

Inside `docker-compose.yml`, service keys may differ from container names. Prefer **either**:

- Set **container_name** to the prefix pattern above **and** the labels, **or**
- Leave dynamic names but **always** set the four required labels.

Do not rely on Compose service name alone for Warm assets classification (rename breaks).

---

## 4. Images and tags

Image reference is **not** part of the classification contract (repos change). Use **labels** as source of truth for vendor/product.

Document recommended base images in the profile spec (separate from this file).

---

## 5. Warm assets integration (conceptual)

When listing containers from the Docker engine:

1. If labels include `telvm.agent=closed` → row **type** = `agent`, subtype from `telvm.agent.vendor` / `telvm.agent.product`.
2. Else if existing telvm lab labels (e.g. lab workload markers) → **lab**.
3. Else → **generic** (current behavior).

---

## 6. Conflicts and migration

- **Collision:** Two containers must not share the same `container_name` if used; suffix enforces uniqueness.
- **Legacy containers:** Without labels, show as generic until recreated with labels.

---

## Revision

Add new `telvm.agent.product` values only with a harness contract and wireframe update.
