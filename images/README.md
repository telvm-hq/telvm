# Telvm certified lab images

Foundation images for VM manager **Verify** / soak and future **telvm-certified** catalog chips. Each image listens on **port 3333** and returns **HTTP 200** with JSON:

```json
{"status":"ok","service":"telvm-lab","probe":"/"}
```

| Directory | Stack | Notes |
|-----------|-------|--------|
| [`telvm-lab-phoenix/`](telvm-lab-phoenix/) | Elixir + Phoenix + Bandit | Full `mix release`; largest image |
| [`telvm-lab-go/`](telvm-lab-go/) | Go + Fiber | Static binary, small |
| [`telvm-lab-python/`](telvm-lab-python/) | Python + FastAPI + uvicorn | Slim bookworm |
| [`telvm-lab-erlang/`](telvm-lab-erlang/) | Erlang + Cowboy | `rebar3` release |
| [`telvm-lab-c/`](telvm-lab-c/) | C + libmicrohttpd | Minimal HTTP (not Kore); easy to CI |

Legacy minimal probe (unchained from this matrix until retired): [`go-http-lab/`](go-http-lab/).

**CI:** [`.github/workflows/publish-telvm-lab-images.yml`](../.github/workflows/publish-telvm-lab-images.yml) pushes **`ghcr.io/<org>/telvm-lab-<name>:main`** per matrix row.

**Docs:** companion integration, GHCR verification, and probe contract — [`docs/telvm-lab-images.md`](../docs/telvm-lab-images.md).

**Local build:**

```bash
docker build -t telvm-lab-phoenix:local images/telvm-lab-phoenix
docker run --rm -p 3333:3333 telvm-lab-phoenix:local
curl -s http://127.0.0.1:3333/
```
