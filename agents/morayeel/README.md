# morayeel

Headless **Playwright / Chromium** lab agent for telvm: drive an in-cluster **HTTP lab**, export **`storageState.json`**, **`network.har`**, and **`run.json`** under a deterministic per-run directory (same spirit as [dirteel](../dirteel/README.md) egress probes, but for browser session artifacts).

**Capture modes:** `MORAYEEL_CAPTURE=oneshot` (default) performs one navigation and exits. `MORAYEEL_CAPTURE=session` opens Chromium with **remote debugging (CDP)** on `0.0.0.0:${MORAYEEL_CDP_PORT:-9222}`, refreshes **`storageState.json`** on an interval until you send **SIGINT/SIGTERM** or create **`morayeel.done`** in `OUT_DIR`, then closes the context so **`network.har`** is finalized. Use session mode when you need a human-driven tape (e.g. classic WebForms / DevExpress second POST); see [morayeel_additions.md](morayeel_additions.md).

**Headless vs headed:** By default Chromium is **headless** (`MORAYEEL_HEADLESS=1`). Set **`MORAYEEL_HEADLESS=0`** (or `false` / `no` / `off`) to open a **visible browser** on your machine. That is intended for **local** runs (`node run.mjs` or [`scripts/morayeel-run.sh`](scripts/morayeel-run.sh) / [`scripts/morayeel-run.ps1`](scripts/morayeel-run.ps1) with `--headed`). The default **Docker** image has no X11 display; headed mode there will usually fail unless you add a virtual framebuffer or mount a display socket yourself. **`MORAYEEL_CAPTURE=session`** (CDP) can be combined with headless or headed; CDP is most useful when headless and you attach from the host.

## Flow

```
[ morayeel container ]                    [ companion ]
       |                                        |
       |  HTTP_PROXY=:4003 (egress morayeel)    |
       |  NO_PROXY includes morayeel_lab       |
       |       => lab GET is direct on         |
       |          telvm_default                 |
       v                                        v
  morayeel_lab:8080  (Set-Cookie)              :4003 listener
       |                                   (allowlist for
       |                                    proxied traffic)
       v
  /artifacts/<run_id>/storageState.json …
```

## Build image (repo root or any machine with Docker)

```bash
docker build -f agents/morayeel/Dockerfile -t morayeel:latest agents/morayeel
```

## One-shot smoke (full stack)

From repo root with `docker compose up` (companion healthy, `morayeel_lab` up, egress includes `morayeel` workload on port **4003**):

```bash
docker compose run --rm \
  --network telvm_default \
  -v morayeel_runs:/artifacts \
  -e TARGET_URL=http://morayeel_lab:8080/ \
  -e OUT_DIR=/artifacts/smoke-manual \
  -e HTTP_PROXY=http://companion:4003 \
  -e HTTPS_PROXY=http://companion:4003 \
  -e NO_PROXY=companion,db,ollama,localhost,127.0.0.1,morayeel_lab \
  morayeel:latest
```

Expect `storageState.json` with cookie name `morayeel_lab_cookie` and `run.json` with `"status":"passed"`.

## Environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `TARGET_URL` | (see below) | First page to open. **Unset** in `node run.mjs` on the host defaults to **`http://127.0.0.1:4000/`** (companion dashboard). The **Dockerfile** sets **`http://morayeel_lab:8080/`** for in-cluster lab runs. |
| `OUT_DIR` | `/artifacts/run` | Directory for `storageState.json`, `network.har`, `run.json`, `runner.log`, optional `last.png`. |
| `HTTP_PROXY` / `HTTPS_PROXY` | (unset) | Forwarded to Playwright context when set. |
| `MORAYEEL_CAPTURE` | `oneshot` | `oneshot` or `session`. |
| `MORAYEEL_CDP_PORT` | `9222` | Remote debugging port when `session` (must publish with Docker `-p`). |
| `MORAYEEL_STORAGE_SNAPSHOT_MS` | `30000` | Minimum milliseconds between periodic `storageState.json` writes in `session`. |
| `MORAYEEL_SESSION_MAX_MS` | `0` | If `> 0`, end session with `shutdown_reason: timeout` after this many ms. |
| `MORAYEEL_HEADLESS` | `1` | If `0` / `false` / `no` / `off`, launch a **headed** browser (local dev). |

Successful runs include a **`capture`** object in `run.json` (`version`, `mode`, `headless`; in `session`, also `request_summary` and `session` metadata including `shutdown_reason`).

## Local run (headless or headed)

From **`agents/morayeel`** after Node 20+ and `npm ci`:

```bash
npx playwright install chromium
```

**Headless (default):** start companion on port **4000**, then (defaults to **`http://127.0.0.1:4000/`** when `TARGET_URL` is unset):

```bash
export OUT_DIR="/tmp/morayeel-out"
mkdir -p "$OUT_DIR"
node run.mjs
```

**Headed** (same flags, visible window):

```bash
./scripts/morayeel-run.sh --headed
# or: MORAYEEL_HEADLESS=0 node run.mjs
```

On **Windows** (PowerShell), from `agents\morayeel`:

```powershell
.\scripts\morayeel-run.ps1 -Headed
```

Proxy / lab URLs are your responsibility on the host; the in-cluster **`morayeel_lab`** hostname only resolves inside Docker Compose.

## Session mode (CDP observer)

1. Publish the CDP port to your host (example uses default **9222**):

```bash
docker compose run --rm \
  --network telvm_default \
  -p 9222:9222 \
  -v morayeel_runs:/artifacts \
  -e MORAYEEL_CAPTURE=session \
  -e TARGET_URL=http://morayeel_lab:8080/ \
  -e OUT_DIR=/artifacts/session-demo \
  -e HTTP_PROXY=http://companion:4003 \
  -e HTTPS_PROXY=http://companion:4003 \
  -e NO_PROXY=companion,db,ollama,localhost,127.0.0.1,morayeel_lab \
  morayeel:latest
```

2. Attach with Chrome **Inspect** targets or `curl http://127.0.0.1:9222/json/version` (host port must match `-p`).

3. When finished, either create **`$OUT_DIR/morayeel.done`** inside the container (e.g. `docker exec <container> touch /artifacts/session-demo/morayeel.done` while it runs) or stop the container (**SIGTERM**).

**Security:** CDP is **full control** of the browser; map **localhost** only and never expose it on a public interface. **`network.har`** can contain secrets (including login POST bodies); treat artifacts like credentials.

**HAR semantics:** Playwright writes a complete **`network.har`** when the **browser context** is closed. During `session`, the file on disk may be incomplete until shutdown finalizes it.

## Pinning

The **Dockerfile base tag** and **npm `playwright` version** must stay on the **same release line** (e.g. `v1.49.1-jammy` + `1.49.1`) to avoid “Executable doesn’t exist” skew.

## Lab service

[`lab/`](lab/) is a minimal Node `http.Server` that sets a synthetic session cookie for demos (no real auth).
