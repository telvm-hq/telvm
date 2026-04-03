# telvm-mcp

**Model Context Protocol** server for [telvm](https://github.com/telvm-hq/telvm): exposes the companion **Machine API** (`/telvm/api`) as MCP **tools** so **Cursor** and other MCP clients can list, create, exec, and delete lab containers.

- **Transport:** stdio (Cursor spawns this process).  
- **Backend:** HTTP to the Phoenix app — default **`http://localhost:4000`**, override with **`TELVM_BASE_URL`**.

## Requirements

- Node **18+**  
- Running telvm stack: `docker compose up` from repo root (companion on port **4000**)

## Build

```bash
npm ci
npm run build
```

## Run (manual smoke test)

```bash
node dist/index.js
```

The process waits on **stdin**; in Cursor it is started automatically. Press Ctrl+C to exit.

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `TELVM_BASE_URL` | `http://localhost:4000` | Companion base URL (no trailing slash) |

## Scripts

| Command | Purpose |
|---------|---------|
| `npm run build` | Compile TypeScript to `dist/` |
| `npm start` | `node dist/index.js` |
| `npm test` | Vitest unit tests |

## Tools

See [docs/mcp-cursor.md](../docs/mcp-cursor.md) for the tool list and **Cursor** setup.

## License

Apache-2.0 (same as the telvm repository).
