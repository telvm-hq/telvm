# telvm

[![CI](https://github.com/telvm-hq/telvm/actions/workflows/ci.yml/badge.svg)](https://github.com/telvm-hq/telvm/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-1.17.3-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)

<p align="center">
  <img src="docs/assets/telvm-banner.svg" alt="telvm: one host, browser on port 4000, companion, Docker Engine, N containers" width="920" />
</p>

1. **telvm** is a **local** control plane for **AI coding agents** and humans.  
2. It is one **Phoenix** app (the **companion**) that sits next to **Docker Engine** on **your computer**.  
3. You need **[Docker](https://www.docker.com/)**; telvm does **not** replace the Engine.  
4. The companion exposes a **web UI** and a **JSON + SSE HTTP API** on **one port** (default **4000**).  
5. It uses the **Engine API** (HTTP over the Docker socket) to run, inspect, and drive **one or many containers** on the same host.  
6. **BYOI:** use any container image for labs and sandboxes.  
7. **Cursor**, **Claude Code**, **Copilot**, or **`curl`** can call **`/telvm/api`**; telvm does **not** bundle an LLM.  
8. **Preview** paths can proxy browser traffic to workloads; **Explorer** (`/explore/:id`) gives **visibility** into files and process context inside a container (editor + room for exec/logs).  
9. This is **local-first** tooling, not a hosted “telecom” or multi-tenant cloud product.  
10. **License:** Apache-2.0 — see [**Community**](#community) for contributing, security, and conduct.

**Human-readable:** one URL on localhost, one Engine, N containers. **Machine-readable:** Docker HTTP adapter, `/telvm/api`, `/app/...` proxy — [Architecture](ARCHITECTURE.md).

<p align="center">
  <img src="docs/assets/telvm-mascot.png" alt="Telvm mascot — cybernetic electric eel" width="320" />
</p>

### At a glance (same idea as the banner you can draw in Canva)

```
+------------------------------------------------------------------+
|  YOUR COMPUTER (one Docker host)                                 |
|   [ Browser / agents ] --http://localhost:4000-->  companion     |
|                              |                                   |
|                    Docker Engine                                 |
|                         |   |   |                                |
|              [Container 1] ... [Container N]                   |
+------------------------------------------------------------------+
```

Replace the SVG above with your **Canva** export when ready: save as **`docs/assets/telvm-banner.png`** and point the `<img>` `src` at that file ([`docs/assets/BANNER.md`](docs/assets/BANNER.md)).

| Layer | Role |
|--------|------|
| **Docker Engine** | Runs containers; companion talks to it via **`docker.sock`**. |
| **Agents & IDEs** | Use **`http://localhost:4000/telvm/api/…`** or the UI—no vendor lock-in. |
| **HTTP API** | Machines, exec, SSE stream—see [Architecture](ARCHITECTURE.md). |

## Docs (detail)

| Doc | Contents |
|-----|----------|
| [docs/quickstart.md](docs/quickstart.md) | `docker compose up`, routes, tests, GHCR lab image, env |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Diagrams, ProxyPlug paths, Explorer/proxy/agent loop, tests, layout |
| [CHANGELOG.md](CHANGELOG.md) | Version notes; GitHub Releases link |

## Community

- [Contributing](CONTRIBUTING.md) (tests, PRs, branch protection, releases)
- [Architecture](ARCHITECTURE.md)
- [Security policy](SECURITY.md)
- [Code of conduct](CODE_OF_CONDUCT.md)

## License

Apache-2.0 — see [LICENSE](LICENSE).
