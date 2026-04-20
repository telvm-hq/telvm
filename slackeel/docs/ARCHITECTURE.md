# Architecture — conceptual baseline

Slackeel is a **separate product** from Telvm Companion: a **Phoenix LiveView** application focused on **team messaging** and **inference-aware** UX (channels, threads, `@model` routing), backed by the **OpenAI-compatible** local inference contract documented in **[OLLAMA.md](OLLAMA.md)** (same HTTP surface whether you clone Slackeel alone or work beside Telvm).

## Goals


| Goal                  | Description                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------- |
| **Self-host**         | Operators run Slackeel + dependencies on their own infra (Docker-first).                    |
| **Inference utility** | Treat **Ollama** (or any `/v1`-compatible server) as **plumbing**, not as a “closed agent.” |
| **LiveView-first**    | Real-time UI, server-owned state, **PubSub** fan-out—appropriate for chat and presence.     |


## Major components (planned)

```
┌─────────────────────────────────────────────────────────────────┐
│  Slackeel Phoenix app (OTP application)                         │
│  • LiveView: channels, composer, admin, model picker              │
│  • PubSub: message fan-out, presence (design phase)               │
│  • Policy layer: which model replies, @mentions, rate limits       │
│  • HTTP client: OpenAI-compatible chat + models to Ollama       │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTP GET/POST …/v1/*
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Ollama (or compatible) — utility runtime                         │
│  • Loads GGUF weights from disk; schedules inference              │
│  • Not part of Slackeel BEAM tree                               │
└─────────────────────────────────────────────────────────────────┘
```

## Boundaries


| Concern                                                  | Owner                                                                                                                        |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **Chat persistence, users, channels**                    | Slackeel app (Postgres, later).                                                                                              |
| **Model weights, VRAM/RAM loading**                      | Ollama process + host resources.                                                                                             |
| **HTTP contract** (`/v1/models`, `/v1/chat/completions`) | Shared convention; see [MODEL_CATALOG.md](MODEL_CATALOG.md) and Telvm [utilities-ollama.md](../../docs/utilities-ollama.md). |


## What is explicitly out of scope for early scaffolding

- Concrete **Ecto schemas** and **migration** files for chat persistence.
- **LiveView module** names beyond the initial **Pre-flight** surface are still evolving; see [`PREFLIGHT_AND_PR.md`](PREFLIGHT_AND_PR.md).
- **Notification graph** parity with commercial products (policy doc may reference the viral decision diagram conceptually only).

## Relationship to Telvm


| Telvm                                                 | Slackeel                                           |
| ----------------------------------------------------- | -------------------------------------------------- |
| Control plane for labs, machines, OSS Agents smoke UI | Product UX for **team chat + model orchestration** |
| May share **Docker** patterns and Ollama pins         | **Does not** require Telvm to be installed         |


Cross-links are **documentation only** until Slackeel ships code that calls a known host for inference.

## Revision log


| Date       | Change                                                                       |
| ---------- | ---------------------------------------------------------------------------- |
| 2026-04-19 | Initial conceptual architecture + diagram.                                   |
| 2026-04-19 | Boundaries link to repo-local [OLLAMA.md](OLLAMA.md) (self-contained clone). |


