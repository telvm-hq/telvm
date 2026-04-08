# telvm-node-agent

```
 _       _                                            _ 
| |_ ___| |_   ___ __ ___   __  __  _ ____      _____| |
| __/ _ \ \ \ / / '_ ` _ \  \ \/ / | '_ \ \ /\ / / __| |
| ||  __/ |\ V /| | | | | |  >  <  | |_) \ V  V /\__ \ |
 \__\___|_| \_/ |_| |_| |_| /_/\_\ | .__/ \_/\_/ |___/_|
                                    |_|
```

Minimal HTTP agent for remote Ubuntu machines in a telvm cluster. Runs as a static Linux binary, proxies a narrow slice of the local Docker Engine API, and exposes a health endpoint. The companion Phoenix app polls these agents over HTTP.

## Build

Requires [Zig](https://ziglang.org/download/) (0.13+).

```bash
# native (on the Ubuntu host itself)
cd agents/telvm-node-agent
zig build -Doptimize=ReleaseSafe

# cross-compile from Windows to Linux x86_64
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe
```

Output: `zig-out/bin/telvm-node-agent`

## Deploy (manual, per host)

```bash
# 1. Copy binary
scp zig-out/bin/telvm-node-agent ubuntu@HOST:~/

# 2. Install
ssh ubuntu@HOST 'sudo mv ~/telvm-node-agent /usr/local/bin/ && sudo chmod +x /usr/local/bin/telvm-node-agent'

# 3. Create env file with your token
ssh ubuntu@HOST 'echo "TELVM_NODE_TOKEN=your-secret-here" | sudo tee /etc/telvm-node-agent.env'

# 4. Install systemd unit
scp telvm-node-agent.service ubuntu@HOST:~/
ssh ubuntu@HOST 'sudo mv ~/telvm-node-agent.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now telvm-node-agent'
```

## API

All endpoints require `Authorization: Bearer <token>` header.

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Agent health: hostname, uptime, version, Docker socket reachable |
| `GET /docker/version` | Proxy to Docker Engine `GET /version` |
| `GET /docker/containers` | Proxy to `GET /containers/json` |
| `GET /docker/containers?all=true` | Proxy to `GET /containers/json?all=true` |
| `GET /docker/containers/:id/stats` | Proxy to `GET /containers/:id/stats?stream=false` |

### Example

```bash
curl -H "Authorization: Bearer your-secret-here" http://10.10.10.11:9100/health
# {"hostname":"node-1","uptime_s":86400,"agent_version":"0.1.0","docker_reachable":true}
```

## CLI

```
telvm-node-agent [OPTIONS]

Options:
  --port <PORT>    Listen port (default: 9100)
  --token <TOKEN>  Bearer token for auth (required)
  --version        Print version and exit
  --help           Show this help
```

## Systemd

The included `telvm-node-agent.service` unit reads `/etc/telvm-node-agent.env` for `TELVM_NODE_TOKEN`. Edit that file on each host with the shared cluster token.
