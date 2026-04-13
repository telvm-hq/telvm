# Morayeel deterministic verification checklist

Use this before treating the Morayeel LiveView tab as “trusted” in a release or demo.

1. **Image reproducibility** — `agents/morayeel/Dockerfile` `FROM mcr.microsoft.com/playwright:…` matches `package.json` / `package-lock.json` `playwright` semver (same minor line).
2. **Compose wiring** — `morayeel_lab` resolves on `telvm_default`; from the companion container, `curl -sS http://morayeel_lab:8080/` returns `200` and a `Set-Cookie` header.
3. **Proxy + lab** — The runner sets `HTTP_PROXY=http://companion:4003` (workload **`morayeel`**, port **4003**, allowlist **`morayeel_lab`**) and **`NO_PROXY=…,morayeel_lab`**. The lab is fetched **directly** on `telvm_default` so Chromium persists **`Set-Cookie`** into `storageState.json` reliably; the **:4003** listener remains the path for allowlisted upstreams when traffic is not bypassed. To see a **`403`** JSON deny, use `curl`/`dirteel` through **:4003** to a host **not** on the workload allowlist (see [connection.ex](../companion/lib/companion/egress_proxy/connection.ex)).
4. **Artifact contract** — After a successful run, the run directory contains at least `run.json`, `storageState.json`, `runner.log`, and `network.har`; `storageState.json` parses as JSON and lists cookie **`morayeel_lab_cookie`** (synthetic value from the lab).
5. **Failure mode** — With `TARGET_URL=http://morayeel_lab:9999/` (nothing listening), the run exits non-zero, `run.json` has `"status":"failed"`, and `last.png` exists when navigation failed after a page existed (optional refinement).
6. **Concurrency** — Starting a second run while the first is **running** is rejected or queued (GenServer guard); UI shows a clear message.
7. **Scope** — Default target is the first-party lab only; documenting real third-party targets is operator responsibility.

## Quick manual commands

```bash
# Lab HTTP
docker compose exec companion sh -lc 'curl -sSI http://morayeel_lab:8080/ | head -n 20'

# Egress listener (from companion network)
docker compose exec companion sh -lc 'python3 -c "import socket;s=socket.create_connection((\"127.0.0.1\",4003));s.sendall(b\"CONNECT morayeel_lab:80 HTTP/1.1\\r\\nHost: morayeel_lab:80\\r\\n\\r\\n\");print(s.recv(4096).decode(errors=\"replace\"))"'
```

Adjust host/port if your compose project renames services or workloads.
