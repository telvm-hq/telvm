# Slackeel Pre-flight + telvm-network-agent (PR description)

Use the text below as the GitHub PR title and body when opening a PR against **`telvm-hq/telvm`**.

## Title

```
slackeel: Phoenix LiveView shell + Pre-flight dashboard wired to telvm-network-agent
```

## Body

### Summary

This PR adds a **baseline Phoenix LiveView application** under `slackeel/server/` with a **Pre-flight** dashboard at **`/preflight`**. The dashboard compares **manifest model pull sizes** (catalog variance buffer) to **free disk space** and surfaces **network diagnostics** by calling the existing **`telvm-network-agent`** HTTP API in this monorepo.

**Supported workflow:** clone the full **`telvm-hq/telvm`** repository, run **`agents/telvm-network-agent/Start-NetworkAgent.ps1`** (Administrator, Windows) on the host, then run **`mix phx.server`** from `slackeel/server/`. In **`MIX_ENV=dev`**, the app defaults **`SLACKEEL_PREFLIGHT_METRICS_URL`** to **`http://127.0.0.1:9225/preflight/metrics`**, matching the agent’s listen port. Optional **`SLACKEEL_PREFLIGHT_METRICS_TOKEN`** / **`TELVM_NETWORK_AGENT_TOKEN`** align Bearer auth.

If the agent is unreachable, Pre-flight **falls back** to Erlang **`:disksup`** on the BEAM host so local development still degrades gracefully.

### Changes

- **`agents/telvm-network-agent`**: new **`GET /preflight/metrics`** returning JSON with **`free_bytes`**, **`source: telvm-network-agent`**, and a **`network`** object (from existing **`Get-NetworkDiagnostics`**). New **`lib/Disk.ps1`** for conservative minimum free-bytes across fixed drives.
- **`slackeel/server`**: LiveView Pre-flight page; **`Req`** + optional Bearer; dev default metrics URL; network block rendered when present.
- **Docs / env**: README and `.env.example` updated; this file for PR copy-paste.

### How to verify

1. From repo root (Administrator PowerShell):  
   `.\agents\telvm-network-agent\Start-NetworkAgent.ps1`  
   (optionally `-Token "secret"` and set the same for Phoenix env).

2. `cd slackeel\server` → `mix phx.server` → open **`http://127.0.0.1:4020/preflight`**.

3. Confirm **Source** shows **telvm-network-agent** and **Network** JSON appears when the agent responds.

### Scope / follow-ups

- Chat persistence, Ecto, and product UX beyond Pre-flight remain future work.
- Non-Windows hosts do not run `telvm-network-agent`; use **`SLACKEEL_PREFLIGHT_METRICS_URL`** to point at another JSON metrics endpoint or rely on **`:disksup` fallback**.
