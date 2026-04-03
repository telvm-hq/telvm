# Cursor + telvm MCP (first-time setup)

Use this guide if you are **new to telvm** and want **Cursor** (or any MCP client) to call the **Machine API** via the **telvm MCP server** — a small Node process that speaks [Model Context Protocol](https://modelcontextprotocol.io) over **stdio** and forwards requests to **`http://localhost:4000/telvm/api`**.

**Security (v0.1.0):** The companion has **no API authentication**. Run only on **trusted localhost**; do not expose port **4000** to the internet.

---

## Prerequisites

- **Docker** (Desktop or Engine) running on your machine  
- **Git**  
- **Node.js 18+** (for building and running the MCP server on the **host**, where Cursor runs)  
- **Cursor** IDE  

---

## 1. Start the telvm stack

From the repo root:

```bash
git clone https://github.com/telvm-hq/telvm.git
cd telvm
docker compose up --build
```

Wait until the **companion** is listening on **`http://localhost:4000`**.

---

## 2. Sanity-check the Machine API

In another terminal (on the **host**):

```bash
curl -s http://localhost:4000/telvm/api/machines
```

You should see JSON (possibly `{"machines":[]}` if no lab containers are running). If you get **connection refused**, the stack is not up or port **4000** is blocked.

---

## 3. Build the MCP server

The MCP package lives under **`mcp/`** in this repository.

```bash
cd mcp
npm ci
npm run build
```

This produces **`mcp/dist/index.js`**.

---

## 4. Configure Cursor to launch the MCP server

Cursor reads MCP configuration from **global** or **project** settings. Prefer a **project-local** config so each clone can point at the right path.

### Option A — `mcp.json` (recommended for Cursor)

Create or edit **`.cursor/mcp.json`** at the **telvm repo root** (same level as `docker-compose.yml`):

Replace **`YOUR_PATH`** with the absolute path to your clone (Windows example shown):

```json
{
  "mcpServers": {
    "telvm": {
      "command": "node",
      "args": ["C:/Users/YOUR_USER/path/to/telvm/mcp/dist/index.js"],
      "env": {
        "TELVM_BASE_URL": "http://localhost:4000"
      }
    }
  }
}
```

- **`command` / `args`:** Run the **compiled** server. Use **forward slashes** or escaped backslashes on Windows.  
- **`TELVM_BASE_URL`:** Optional; defaults to `http://localhost:4000` if omitted. Use this if the companion listens on another host/port.

Restart Cursor or reload the window so MCP settings are picked up.

### Option B — Cursor Settings UI

Open **Cursor Settings → MCP** and add a server with the same **command**, **arguments**, and **environment** as above. The exact UI may change between Cursor versions; if in doubt, use **Option A**.

---

## 5. Verify in chat

1. Ensure **`docker compose up`** is still running.  
2. Open the telvm project in Cursor.  
3. In **Agent** chat, ask something like:

   > Use the telvm MCP tools to list machines.

You should see tool calls such as **`telvm_list_machines`**. If tools are missing, check that **`.cursor/mcp.json`** points to the correct **`dist/index.js`** and that **Node** is on your `PATH`.

---

## 6. Troubleshooting

| Symptom | What to check |
|--------|----------------|
| Connection refused / cannot reach companion | `docker compose ps`, `curl http://localhost:4000/telvm/api/machines` |
| MCP server exits immediately | Run `node mcp/dist/index.js` in a terminal — it should **block** (stdio). Errors print to stderr. |
| Wrong host/port | Set **`TELVM_BASE_URL`** explicitly in **`env`**. |
| Tools not listed in Cursor | Path in **`args`** must be **absolute** and to **`dist/index.js`** after **`npm run build`**. |

---

## 7. Tools exposed (summary)

| Tool | API |
|------|-----|
| `telvm_list_machines` | `GET /telvm/api/machines` |
| `telvm_get_machine` | `GET /telvm/api/machines/:id` |
| `telvm_create_machine` | `POST /telvm/api/machines` |
| `telvm_exec` | `POST /telvm/api/machines/:id/exec` |
| `telvm_delete_machine` | `DELETE /telvm/api/machines/:id` |
| `telvm_machine_logs` | `GET /telvm/api/machines/:id/logs` |
| `telvm_machine_stats` | `GET /telvm/api/machines/:id/stats` |
| `telvm_restart_machine` | `POST /telvm/api/machines/:id/restart` |
| `telvm_pause_machine` | `POST /telvm/api/machines/:id/pause` |
| `telvm_unpause_machine` | `POST /telvm/api/machines/:id/unpause` |

Full REST details: [Machine API (agents)](agent-api.md).

---

## See also

- [`mcp/README.md`](../mcp/README.md) — develop and test the MCP package locally  
- [Quick start](quickstart.md) — Docker compose overview  
