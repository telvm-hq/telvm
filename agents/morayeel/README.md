# morayeel

Headless **Playwright / Chromium** lab agent for telvm: drive an in-cluster **HTTP lab**, export **`storageState.json`**, **`network.har`**, and **`run.json`** under a deterministic per-run directory (same spirit as [dirteel](../dirteel/README.md) egress probes, but for browser session artifacts).

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

## Pinning

The **Dockerfile base tag** and **npm `playwright` version** must stay on the **same release line** (e.g. `v1.49.1-jammy` + `1.49.1`) to avoid “Executable doesn’t exist” skew.

## Lab service

[`lab/`](lab/) is a minimal Node `http.Server` that sets a synthetic session cookie for demos (no real auth).
