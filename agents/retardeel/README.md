# retardeel

```
          _                _           _
 _ __ ___| |_ __ _ _ __ __| | ___  ___| |
| '__/ _ \ __/ _` | '__/ _` |/ _ \/ _ \ |
| | |  __/ || (_| | | | (_| |  __/  __/ |
|_|  \___|\__\__,_|_|  \__,_|\___|\___|_|
```

Dead-simple static Zig binary for jailed Unix filesystem access over HTTP. Drop it into **any** Linux container or VM — no runtime, no libc, no dependencies.

Part of the [telvm](../../README.md) stack.

## Build

Requires [Zig](https://ziglang.org/download/) (0.13+).

```bash
# Native (on the Linux host itself)
cd agents/retardeel
zig build -Doptimize=ReleaseSafe

# Cross-compile from Windows/macOS to Linux x86_64 (static musl)
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe

# Cross-compile for aarch64
zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe
```

Output: `zig-out/bin/retardeel`

## Deploy

### Option 1: Bake into a BYOI Dockerfile

```dockerfile
FROM node:22-alpine
COPY retardeel /usr/local/bin/retardeel
CMD ["retardeel", "--token", "secret", "--root", "/app", "--port", "9200"]
```

Works with any base image including `FROM scratch`.

### Option 2: Shared volume (init container)

Mount a volume, copy the binary from an init container, then start it in the workspace container.

### Option 3: On-demand inject

```bash
docker cp retardeel CONTAINER_ID:/usr/local/bin/retardeel
docker exec CONTAINER_ID retardeel --token secret --root /workspace --port 9200 &
```

The static binary works regardless of what libc or runtime is in the target image.

### Systemd (bare metal / VM)

```bash
sudo cp retardeel /usr/local/bin/
sudo cp retardeel.service /etc/systemd/system/
echo "RETARDEEL_TOKEN=your-secret-here" | sudo tee /etc/retardeel.env
echo "RETARDEEL_ROOT=/home/user/workspace" | sudo tee -a /etc/retardeel.env
echo "RETARDEEL_PORT=9200" | sudo tee -a /etc/retardeel.env
sudo systemctl daemon-reload
sudo systemctl enable --now retardeel
```

## API

All endpoints require `Authorization: Bearer <token>` header.

| Method | Route | Description |
|--------|-------|-------------|
| `GET` | `/health` | Agent version, hostname, root, arch, os, uptime |
| `GET` | `/v1/workspace` | Detect project manifests (mix.exs, package.json, etc.) |
| `POST` | `/v1/stat` | File/directory metadata: exists, size, is_dir, mtime |
| `POST` | `/v1/read` | Read file content (UTF-8 text or base64), with offset/limit |
| `POST` | `/v1/write` | Atomic write (temp + rename), returns SHA-256 |
| `POST` | `/v1/list` | Bounded directory listing (max 1000 entries) |

### Examples

```bash
TOKEN="your-secret-here"
BASE="http://localhost:9200"
AUTH="Authorization: Bearer $TOKEN"

# Health check
curl -s -H "$AUTH" "$BASE/health" | jq .

# Discover workspace type
curl -s -H "$AUTH" "$BASE/v1/workspace" | jq .

# Stat a file
curl -s -H "$AUTH" -X POST "$BASE/v1/stat" \
  -d '{"path":"src/main.zig"}' | jq .

# Read a file (first 4096 bytes)
curl -s -H "$AUTH" -X POST "$BASE/v1/read" \
  -d '{"path":"src/main.zig","limit":4096}' | jq .

# Write a file (create new)
curl -s -H "$AUTH" -X POST "$BASE/v1/write" \
  -d '{"path":"hello.txt","text":"hello world\n","mode":"create"}' | jq .

# Write a file (replace existing)
curl -s -H "$AUTH" -X POST "$BASE/v1/write" \
  -d '{"path":"hello.txt","text":"updated\n","mode":"replace"}' | jq .

# List directory contents
curl -s -H "$AUTH" -X POST "$BASE/v1/list" \
  -d '{"path":"src","max_entries":50}' | jq .

# Jail escape attempt (should return 403)
curl -s -H "$AUTH" -X POST "$BASE/v1/read" \
  -d '{"path":"../../etc/passwd"}' | jq .
```

## Security

- **Path jail**: every request path is resolved to an absolute path via `realpath` and verified to be a prefix of `--root`. Symlinks that escape are rejected. Absolute paths in requests are rejected.
- **Bearer token**: required on every request. Same pattern as `telvm-node-agent`.
- **No Docker socket**: this binary never touches `/var/run/docker.sock` or any host-level API.
- **No shell exec**: v01 has no `/v1/exec` endpoint. The binary can only read/write/stat/list files.
- **Atomic writes**: writes go to a temp file then `rename`, preventing partial/corrupt files.
- **Bounded I/O**: all reads and writes capped at `--max-body` (default 4 MiB).

## Non-goals (v01)

- **Shell execution** (`/v1/exec`) — deferred to v02.
- **Recursive tree walk** — callers iterate with `/v1/list`.
- **TLS** — handled by the network boundary (SSH tunnel, Docker network, sidecar proxy).
- **Streaming / chunked responses** — single bounded response bodies only.
- **Package manager operations** — belong in the orchestrator, not the file agent.

## CLI

```
retardeel [OPTIONS]

Options:
  --port <PORT>        Listen port (default: 9200)
  --token <TOKEN>      Bearer token for auth (required)
  --root <ABS_PATH>    Workspace root to jail into (required)
  --max-body <BYTES>   Max request/response body (default: 4194304)
  --version            Print version and exit
  --help               Show this help
```

## Comparison with telvm-node-agent

| | retardeel | telvm-node-agent |
|---|---|---|
| **Purpose** | Filesystem access inside workspaces | Docker Engine proxy on cluster hosts |
| **Port** | 9200 | 9100 |
| **Privilege** | Jailed to `--root`, no sockets | Access to `/var/run/docker.sock` |
| **Blast radius** | One workspace directory | Host-level Docker API |
| **Placement** | Inside containers / VMs | On bare-metal cluster hosts |
