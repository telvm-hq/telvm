# Architecture diagram (Mermaid + icons)

Accurate high-level layout: the **companion** is a **peer** on the host that **calls** Docker Engine over **`docker.sock`**; containers do not open SSE into telvm. For **PubSub**, **SSE vs LiveView**, and **`machines_snapshot`**, see [Plumbing](../plumbing.md).

Icons below are from **[Simple Icons](https://simpleicons.org/)** (CC0 1.0), loaded from [jsDelivr](https://www.jsdelivr.com/package/npm/simple-icons).

<p align="center">
  <img src="https://cdn.jsdelivr.net/npm/simple-icons@v11/icons/docker.svg" height="28" width="28" alt="Docker" />
  &nbsp;
  <img src="https://cdn.jsdelivr.net/npm/simple-icons@v11/icons/elixir.svg" height="28" width="28" alt="Elixir" />
  &nbsp;
  <img src="https://cdn.jsdelivr.net/npm/simple-icons@v11/icons/phoenixframework.svg" height="28" width="28" alt="Phoenix Framework" />
</p>

## Diagram

```mermaid
flowchart TB
  subgraph clients [Clients]
    browser["Browser LiveView /app /explore"]
    agents["Agents curl IDE"]
  end
  subgraph companionBlock [Companion on host]
    phx["Phoenix :4000"]
  end
  subgraph dockerSide [Docker]
    engine["Engine API docker.sock"]
    labs["Lab containers BYOI bridge"]
  end
  browser -->|HTTP| phx
  agents -->|JSON and SSE| phx
  phx <-->|Engine API| engine
  engine --> labs
  phx -->|ProxyPlug| labs
```

**Caption:** One published host port (**`:4000`**) for the dashboard, Preview paths, Explorer, and **`/telvm/api`**. The companion **pulls** container state via the Engine API and **pushes** SSE to clients that subscribe to **`/telvm/api/stream`**; see [Plumbing](../plumbing.md).

## Licenses

- **Simple Icons** — [CC0 1.0](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md).
