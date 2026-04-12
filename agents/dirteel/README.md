# dirteel

```
      _ _      _            _
   __| (_)_ __| |_ ___  ___| |
  / _` | | '__| __/ _ \/ _ \ |
 | (_| | | |  | ||  __/  __/ |
  \__,_|_|_|   \__\___|\___|_|
```

Static Zig binary for **telvm closed-agent egress**: raw HTTP `CONNECT` through the companion egress listener (same contract as `curl --proxy`), plus a **JSON manifest** helper so `profiles/closed_images.json` stays aligned with [`ClosedAgents.Catalog`](../../companion/lib/companion/closed_agents/catalog.ex).

Part of the [telvm](../../README.md) stack (same spirit as [retardeel](../retardeel/README.md)).

## Why this exists

```
  [ closed container ]                    [ companion ]
        |                                       |
        |  curl --proxy http://companion:4001   |
        |       or                              |
        |  dirteel egress-probe ...               |
        v                                       v
  +------------------+                 +----------------------+
  | HTTP CONNECT     |  TCP :4001      | EgressProxy.Listener |
  | api.vendor:443   +-------------->| Connection (policy)  |
  +------------------+                 +----------+-----------+
                                                  |
                     Internet                     v
                                      +----------------------+
                                      | vendor :443          |
                                      +----------------------+
```

Operational lessons encoded here and in companion:

| Symptom | Likely cause | Where to look |
|--------|----------------|---------------|
| `curl: (56) Recv failure: Connection reset by peer` | Listener crashed after `accept` (e.g. `:einval` on redundant `setopts`) | [`egress_proxy/listener.ex`](../../companion/lib/companion/egress_proxy/listener.ex) |
| `curl: (56) CONNECT tunnel failed, response 403` | Proxy returned JSON deny (`not_on_allowlist`, `upstream_connect_failed`, …) or **`malformed_connect`** if CONNECT line was parsed wrong | [`egress_proxy/connection.ex`](../../companion/lib/companion/egress_proxy/connection.ex), allowlist in `TELVM_EGRESS_WORKLOADS` ([`docker-compose.yml`](../../docker-compose.yml)) |
| Raw `CONNECT` returns `malformed_connect` | Host/port regex must not swallow `:443` into the host token (pattern must split `host` and `:port`) | `connection.ex` `@connect_re` |

Raw TCP check (no `dirteel` / no `curl` body on failed CONNECT), e.g. inside `companion`:

```bash
python3 -c "import socket;s=socket.create_connection(('127.0.0.1',4001));s.sendall(b'CONNECT api.anthropic.com:443 HTTP/1.1\r\nHost: api.anthropic.com:443\r\n\r\n');print(s.recv(4096).decode(errors='replace'))"
```

## Build

Requires [Zig](https://ziglang.org/download/) **0.13.x** (matches retardeel).

```bash
cd agents/dirteel
zig build -Doptimize=ReleaseSafe
# zig-out/bin/dirteel
```

Cross-compile (static musl):

```bash
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe
```

Docker (no local Zig), from **repo root**:

```bash
docker build -f agents/dirteel/Dockerfile -t dirteel:build .
docker create --name dirteel-tmp dirteel:build
docker cp dirteel-tmp:/dirteel ./dirteel-linux-amd64
docker rm dirteel-tmp
```

## Usage

### `egress-probe`

```bash
dirteel egress-probe \
  --proxy-host companion \
  --proxy-port 4001 \
  --https-url 'https://api.anthropic.com/'
```

- **stdout**: one minified JSON line (`ok`, `status_line`, optional `body_preview`, optional `err`).
- **stderr**: one human-readable line.
- **exit 0** only if status line starts with `HTTP/1.1 200` or `HTTP/1.0 200` (`Connection Established`).

**Quoting (PowerShell vs sh)**

- In **Git Bash / WSL / Linux** use single quotes around `--https-url` as above.
- In **PowerShell** prefer running inside a container so quoting matches sh:

  ```powershell
  docker compose exec -T companion sh -c "dirteel egress-probe --proxy-host companion --proxy-port 4001 --https-url 'https://api.anthropic.com/'"
  ```

  Or pass the URL without spaces (no quotes needed).

### `manifest`

Canonical closed-image fields live in [`profiles/closed_images.json`](profiles/closed_images.json). Sort order is normalized internally; the **SHA-256** is over the minified sorted array JSON.

```bash
dirteel manifest profiles/closed_images.json
# stdout: JSON with profile_bundle_sha256, suggested_label, ...

dirteel manifest profiles/closed_images.json --quiet-sha-only
# stdout: hex sha256 + newline only
```

Suggested OCI label (copy into Dockerfiles when you want provenance on the image):

```dockerfile
LABEL telvm.dirteel.profile_sha256="<value from JSON or --quiet-sha-only>"
```

## CI / Makefile

From repo root, keep profiles in sync with Elixir catalog:

```bash
make check-dirteel-catalog
```

(Uses Docker Compose `companion_test` + Postgres; see [Makefile](../../Makefile).)

## Version

`dirteel --version` prints the semver string baked into the binary.
