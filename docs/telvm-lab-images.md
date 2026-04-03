# Telvm certified lab images — verification and companion integration

This document records **registry verification** (GitHub Actions and GHCR), the **HTTP probe contract** shared by all certified stacks, and how the **companion** uses them (`LabCatalog`, certified soak, optional container env).

## GitHub Actions (`publish-telvm-lab-images`)

Workflow file: [`.github/workflows/publish-telvm-lab-images.yml`](../.github/workflows/publish-telvm-lab-images.yml).

**Verification notes (automated checks):**

- The workflow must exist on the default branch (`main`) for the repository API to list runs. If it exists only on a feature branch, `gh run list --workflow publish-telvm-lab-images.yml` returns **404** until it is merged.
- After merge, confirm **Actions → “Publish telvm certified lab images”** is green (all five matrix legs), or run **workflow_dispatch**.

## GHCR packages and `docker pull`

Published tags follow **`ghcr.io/<lowercase-owner>/telvm-lab-<stack>:main`** and **`:<sha>`** (see workflow).

**Verification:**

1. `docker login ghcr.io` (required for private packages or when the daemon is not already authenticated).
2. Pull each image, for example:  
   `docker pull ghcr.io/telvm-hq/telvm-lab-phoenix:main`  
   (repeat for `go`, `python`, `erlang`, `c`).
3. Smoke test:  
   `docker run --rm -p 3333:3333 ghcr.io/telvm-hq/telvm-lab-phoenix:main`  
   then `curl -s http://127.0.0.1:3333/`.

If pull returns **denied**, log in, confirm the package exists under the org/user **Packages**, and that your token has `read:packages` where applicable.

## Probe contract

Certified images expose **port 3333** and respond to **`GET /`** with **HTTP 200** and JSON:

```json
{"status":"ok","service":"telvm-lab","probe":"/"}
```

The companion VM manager uses this for bind wait and soak stability probes against `http://telvm-lab-workload:3333/` on the Compose bridge.

## Companion: `LabCatalog` and certified soak

- **Machines catalog** lists only the five **GHCR certified** stacks (`Companion.LabCatalog.entries/0`); there are no Docker Hub preset chips. Use the **image ref / BYOI** field for any other image. Each chip includes **stack disclosure** (installed components, versions, runtime layout) and a **best-practice** note—shown in the UI even before `docker pull`, for operators and agents.
- Chips use the image’s embedded **`CMD`** (`use_image_cmd: true`) and **`telvm_certified: true`**.
- Override the registry owner with **`TELVM_LAB_GHCR_ORG`** (default **`telvm-hq`**) if your pulls use a different org/user name.
- **Certified soak (60s)** applies to those catalog selections (or paste a matching certified ref).

## Container `Env` (VmLifecycle and API)

`Companion.VmLifecycle.lab_container_create_attrs/2` accepts optional **`container_env`** as a list of `{name, value}` tuples merged into the Engine **`Env`** field.

- **Lab catalog:** each entry may include **`container_env`** (empty for current certified rows; reserved for stacks that need e.g. `DATABASE_URL` with Compose-backed DB).
- **API:** `POST /telvm/api/machines` accepts optional **`env`**: a JSON array of **`"KEY=value"`** strings and/or objects `{"name":"KEY","value":"value"}`.

## Legacy `go-http-lab` vs `telvm-lab-go`

The minimal [`images/go-http-lab/`](../images/go-http-lab/) image and [`.github/workflows/publish-go-http-lab.yml`](../.github/workflows/publish-go-http-lab.yml) remain for backward compatibility. The certified **Go** stack is [`images/telvm-lab-go/`](../images/telvm-lab-go/) published as **`telvm-lab-go`**. Plan to retire the legacy workflow once all consumers use `telvm-lab-go` and companion defaults are stable.
