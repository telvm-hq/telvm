# telvm-lab-phoenix

**Elixir + Phoenix + Bandit** — minimal JSON probe on **port 3333** (`GET /`), `mix release` in Docker.

```bash
docker build -t telvm-lab-phoenix:local .
docker run --rm -p 3333:3333 telvm-lab-phoenix:local
```

Expect a large image (full Hex deps + release).
