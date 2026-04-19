# Model catalog — ground truth

This document is the **authoritative planning baseline** for which **families** and **model artifacts** Slackeel intends to expose in the product UI (channel defaults, `@model` routing, admin presets). It is **not** a legal or licensing substitute—verify terms before redistribution.

## How to read disk numbers


| Column                  | Meaning                                                                                                                           |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **Approx. disk (pull)** | Typical on-disk size **after** `ollama pull <name>` on amd64, **Q4_K_M-class** (or Ollama default for that tag), single blob set. |
| **Variance**            | Different tags, quantizations, or Ollama versions can shift sizes by **±15–25%**.                                                 |


**Verify locally:** `ollama show <name>` (reports size) or inspect blobs under the Ollama data root after pull.

## Five families (scope)

Slackeel standardizes on **five upstream families** for OSS / CPU-first inference:

1. **Qwen** (Alibaba Cloud)
2. **Llama** (Meta)
3. **Gemma** (Google)
4. **Phi** (Microsoft)
5. **Mistral** (Mistral AI)

---

## 1. Qwen (Alibaba Cloud)

**Role in Slackeel:** default **tiny** instruct for smoke, low-RAM hosts, and multilingual coverage.


| Planned Ollama name | Params (approx.) | Approx. disk (pull) | Notes                                                                |
| ------------------- | ---------------- | ------------------- | -------------------------------------------------------------------- |
| `qwen2.5:0.5b`      | 0.5B             | **~0.4 GB**         | Primary default for dev/smoke; matches Telvm Compose default intent. |
| `qwen2.5:1.5b`      | 1.5B             | **~1.0 GB**         | Step-up when 0.5B is too weak.                                       |


**License / terms:** Apache-2.0 (Qwen2.5) — confirm on [model card](https://huggingface.co/Qwen) for your exact variant.

---

## 2. Llama (Meta)

**Role in Slackeel:** widely known **Llama** instruct line; good for comparability and tooling.


| Planned Ollama name | Params (approx.) | Approx. disk (pull) | Notes                                                   |
| ------------------- | ---------------- | ------------------- | ------------------------------------------------------- |
| `llama3.2:1b`       | 1B               | **~1.3 GB**         | Small instruct; strong “known baseline” for UX testing. |
| `llama3.2:3b`       | 3B               | **~2.0 GB**         | Heavier option when 1B is insufficient.                 |


**License / terms:** Llama Community License — read Meta’s terms for redistribution and attribution.

---

## 3. Gemma (Google)

**Role in Slackeel:** compact **Gemma 2** instruct models; different training lineage from Llama/Qwen.


| Planned Ollama name | Params (approx.) | Approx. disk (pull) | Notes                                 |
| ------------------- | ---------------- | ------------------- | ------------------------------------- |
| `gemma2:2b`         | 2B               | **~1.6 GB**         | Typical catalog pick for small Gemma. |


**License / terms:** Gemma Terms of Use — verify for your deployment context.

---

## 4. Phi (Microsoft)

**Role in Slackeel:** **Microsoft** small-language-model line (Phi-3 / Phi-4 ecosystem); explicit vendor diversity in the five-family set.


| Planned Ollama name | Params (approx.) | Approx. disk (pull) | Notes                                                                          |
| ------------------- | ---------------- | ------------------- | ------------------------------------------------------------------------------ |
| `phi3:mini`         | 3.8B             | **~2.2 GB**         | Common “mini” instruct; larger than sub-1B tiers.                              |
| `phi3:3.8b`         | 3.8B             | **~2.3 GB**         | Alternative tag depending on registry naming; confirm with `ollama pull` list. |


**License / terms:** MIT (many Phi-3 releases) — confirm the exact checkpoint.

---

## 5. Mistral (Mistral AI)

**Role in Slackeel:** European OSS-friendly line; offers both **tiny** and **7B-class** staples.


| Planned Ollama name | Params (approx.) | Approx. disk (pull) | Notes                                                                                                                     |
| ------------------- | ---------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `ministral-3:3b`    | 3B               | **~3.0 GB**         | Lighter Mistral-family option (registry: [ministral-3](https://ollama.com/library/ministral-3)); quant may vary slightly. |
| `mistral:7b`        | 7B               | **~4.4 GB**         | Canonical “small but capable” Mistral; higher RAM at runtime.                                                             |


**License / terms:** Apache-2.0 (many Mistral checkpoints) — verify per model card.

> **Note:** Ollama **library names** change over time. If a tag disappears, use `ollama search mistral` and update this table in a doc PR.

---

## Roll-up: disk planning


| Scenario                                       | Models included                                                           | Rough total disk                                        |
| ---------------------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------- |
| **Minimal dev set** (one smallest per family)  | `qwen2.5:0.5b`, `llama3.2:1b`, `gemma2:2b`, `phi3:mini`, `ministral-3:3b` | **~8–10 GB**                                            |
| **“Canonical” heavier Mistral**                | Same but swap `ministral-3:3b` → `mistral:7b`                             | **~10–12 GB**                                           |
| **Full table above** (both tiers where listed) | All rows                                                                  | **~18–22 GB** (order-of-magnitude; quantizations stack) |


**Runtime RAM** is separate: loaded models need **RAM + KV cache**, often **larger** than raw disk for a given model. Slackeel UI should surface **disk** (pulled blobs) and **memory pressure** (operational, later).

---

## Revision log


| Date       | Change                                                                  |
| ---------- | ----------------------------------------------------------------------- |
| 2026-04-19 | Initial catalog: five families, planned Ollama names, approximate disk. |


