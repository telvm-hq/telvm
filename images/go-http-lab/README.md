# go-http-lab

Tiny `net/http` server for **VM manager pre-flight**: listens on **3333** (all interfaces), **`GET /` → 200**, body `ok`. Aligns with the five-image roadmap `go-http` row as a **probe-only** slice (no Claude CLI in this image).

## Build locally

```bash
docker build -t telvm-go-http-lab:local images/go-http-lab
docker run --rm -p 3333:3333 telvm-go-http-lab:local
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3333/
```

## Use with the companion (Compose)

After pushing to GHCR (see repo workflow), set on the **companion** service:

- `TELVM_LAB_IMAGE=ghcr.io/<owner>/telvm-go-http-lab:main` (use your published tag)
- `TELVM_LAB_USE_IMAGE_CMD=1` so Docker uses this image’s `CMD` (not the default Node inline script)

Private registry: `docker login ghcr.io` on the host whose Engine backs `docker.sock`.

## CI

GitHub Actions (`.github/workflows/publish-go-http-lab.yml`) builds and pushes when `images/go-http-lab/**` changes on `main`, or via **workflow_dispatch**.

Source layout: `Dockerfile`, `go.mod`, `main.go`.
