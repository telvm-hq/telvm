# WebForms reverse engineering: Versatec lessons and morayeel OSS context

**Audience:** future us, and agents extending **[morayeel](https://github.com/)** (telvm: `telvm/agents/morayeel`) with better capture modes.  
**Scope:** conceptual flow and artifacts—not live credentials or tenant-specific field dumps.

See also: [HAR_CAPTURE.md](HAR_CAPTURE.md), [DISCOVERY.md](DISCOVERY.md), [SCOUT_PIPELINE.md](SCOUT_PIPELINE.md).

---

## 1. Stateful HTML is two problems, not one

ASP.NET **WebForms** + **DevExpress** couples **identity** (session cookies) with **action validity** (hidden fields, anti-forgery tokens, callback payloads). Fixing only one side produces confusing failures.

```
  +----------------------+         +-------------------------------+
  |  Problem A: SESSION  |         |  Problem B: POST SHAPE        |
  |  Who is the client?  |         |  What bytes does the server |
  |  Cookies / forms auth|         |  accept on the next POST?   |
  +----------+-----------+         +---------------+---------------+
             |                                       |
             |    BOTH must align for replay         |
             v                                       v
        storageState.json              VERSATEC_TX_EXTRA (pipe)
        OR Elixir login chain          from HAR (POST to report URL)
             \                           /
              \                         /
               v                       v
            +-----------------------------+
            |  Elixir Req (no JS engine)  |
            |  GET -> merge -> POST       |
            +-----------------------------+
```

**Takeaway:** treat **cookie jar** and **replayable POST suffix** as separate artifacts; merging them mentally avoids “we have a HAR but Elixir still gets zero rows.”

---

## 2. GET report page ≠ POST that fills the grid

Navigation often ends at a **GET** of the `.aspx` **shell** (menus, filters, empty or partial grid). DevExpress frequently issues a **second** **XHR POST** to the **same path** with `__CALLBACKID` / `__CALLBACKPARAM` (e.g. load “Datos”).

```
  time --->
       |
       v
  GET /Reportes/frmRptTransaccionesCliente.aspx
       |
       +--> HTML shell (may mention report name everywhere)
       |
       v
  POST /Reportes/frmRptTransaccionesCliente.aspx   (XHR, huge body)
       |
       +--> HTML with grid markers (e.g. dxgvDataRow)
```

**Takeaway:** `mix versatec.har.tx_extra` filters on **POST + request URL** containing the report fragment—not on grep hits inside **response** HTML.

---

## 3. HAR is a tape; `har.tx_extra` is a narrow extractor

```
  Browser session
        |
        |  DevTools / Playwright recordHar
        v
  +------------------+
  |  file.har        |  many entries: GET, JS, images, POST...
  +--------+---------+
           |
           |  Versatec.Flota.Reports.HarTxExtra
           v
  subset: POST && url =~ "frmRptTransaccionesCliente"
           |
           +--> pick entry (prefer grid-like response body)
           +--> emit VERSATEC_TX_EXTRA= name=value|...
```

**Takeaway:** a “busy” HAR can still fail extraction if no qualifying **POST URL** exists (e.g. only navigated with GET, or Preserve log off).

---

## 4. Four recurring web reverse-engineering setups

| Setup | Pattern | HAR + storageState |
|--------|---------|-------------------|
| **A** | Stateless JSON API + token | HAR optional |
| **B** | SPA + XHR JSON + token in JS/memory | HAR useful; jar alone often insufficient |
| **C** | Cookies + HTML forms + XHR postbacks (WebForms / “classic”) | **Both** artifacts high value (Versatec) |
| **D** | Blobs, print, native download, WebSocket-only payloads | Headed + special hooks; HAR incomplete |

Versatec is mainly **C**; export flows may touch **D** (viewer / PDF path vs simple CSV).

```
        complexity of "replay without browser"
 A -------- B -------- C -------- D -->
 low                              high
```

---

## 5. Headless vs headed: what breaks where

| Mode | Strength | Weakness |
|------|----------|----------|
| **Headless** | CI, repeatability, Docker | Misses tricky DOM/focus; may skip the **second** POST unless scripted; downloads need explicit handling |
| **Headed / human** | Ground truth for “which click fires which POST” | Not CI-native; operator discipline; secrets in HAR |

```
  Discovery quality
        ^
        |     +------------------+
        |     | headed / human   |  best for unknown DevExpress
        |     +------------------+
        |            /
        |           /
        |    +------+-------+
        |    | headless     |  good once selectors + waits known
        +----+--------------+----------------> automation cost
```

**Takeaway:** use **headed** to learn; use **headless** to repeat—same as `ops/har-capture/manual-browser.mjs` vs `record-har.mjs`.

---

## 6. morayeel: what exists today vs Versatec-informed OSS gap

**Today (morayeel `run.mjs`):**

- **`MORAYEEL_CAPTURE=oneshot`** (default): headless Chromium → single `goto` → `storageState.json` + `network.har` + `run.json` (with `capture.version` / `capture.mode`).
- **`MORAYEEL_CAPTURE=session`:** same initial navigation and HAR recording, then **Chromium remote debugging (CDP)** on `0.0.0.0` (see `MORAYEEL_CDP_PORT`), **periodic `storageState.json` snapshots**, shutdown on **SIGINT/SIGTERM** or sentinel file **`morayeel.done`** in `OUT_DIR`, optional **`MORAYEEL_SESSION_MAX_MS`** timeout; `run.json` includes **`capture.request_summary`** (GET/POST counts and POSTs to the `TARGET_URL` host) and **`capture.session`** metadata. Docker: publish CDP with `-p`; details and security notes in [README.md](README.md).

**Gap revealed by Versatec:** one navigation is not enough for **Setup C**; operators need capture after **human-driven** steps (second XHR POST). Session mode addresses that **without headed UI in the container** by attaching via CDP from the host.

**OSS direction (remaining / follow-ups):**

1. ~~Interactive-style capture + periodic storage~~ — **Implemented** as `MORAYEEL_CAPTURE=session` (CDP + snapshots + signal/sentinel); headed UI remains optional for other workflows.
2. **“Live HAR bytes” while the session is still open** — Playwright still finalizes **`network.har`** on **`context.close()`**; for streaming or mid-session dumps, plan **Playwright trace** or **raw CDP** capture later.
3. **Optional read-only status HTTP** (metadata, SSE from log tail)—no cookie values in HTML.

That keeps morayeel **tenant-agnostic** while Versatec keeps **Mix tasks + parsers** (`lib/mix/tasks/versatec.har.tx_extra.ex`, `lib/versatec/flota/reports/har_tx_extra.ex`, sync pipeline).

---

## 7. Security (one line, non-negotiable)

HAR files capture **plaintext login POST bodies**. Treat `*.har` as **secrets**; rotate passwords if leaked; keep HARs gitignored (see repo `.gitignore`).

---

## 8. Quick reference: Versatec repo touchpoints

| Concern | Where |
|---------|--------|
| HAR → `VERSATEC_TX_EXTRA` | `mix versatec.har.tx_extra path.har [--list]` |
| Implementation | `lib/versatec/flota/reports/har_tx_extra.ex` |
| Sync rows | `mix versatec.sync.transacciones` + `.env.example` |
| Playwright capture | `ops/har-capture/record-har.mjs`, `manual-browser.mjs` |

---

*This doc is an educational synthesis; implementation details drift with tenant markup—re-verify with a fresh HAR when the portal changes.*
