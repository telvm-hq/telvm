# telvm-network-agent

```
 _       _                                            _ 
| |_ ___| |_   ___ __ ___   __  __  _ ____      _____| |
| __/ _ \ \ \ / / '_ ` _ \  \ \/ / | '_ \ \ /\ / / __| |
| ||  __/ |\ V /| | | | | |  >  <  | |_) \ V  V /\__ \ |
 \__\___|_| \_/ |_| |_| |_| /_/\_\ | .__/ \_/\_/ |___/_|
                                    |_|
```

Lightweight HTTP service that runs on the **Windows gateway PC** and exposes ICS
(Internet Connection Sharing) state, LAN host discovery, and network diagnostics
as JSON endpoints. Designed to be polled by the telvm companion dashboard — the
same pattern the Zig `telvm-node-agent` uses on Linux cluster nodes.

## Requirements

- Windows 10 / 11 with **two NICs** (e.g. Wi-Fi for internet + Ethernet to the switch)
- **Windows PowerShell 5.1** (`powershell.exe`, not `pwsh`) — ICS COM requires it
- Run as **Administrator** (ICS and `HttpListener` on `+:port` require elevation)

## Quick start

```powershell
# From this directory, as Administrator in PowerShell 5.1:
.\Start-NetworkAgent.ps1 -Token "my-secret-token"

# Or use environment variables:
$env:TELVM_NETWORK_AGENT_TOKEN = "my-secret-token"
$env:TELVM_NETWORK_AGENT_PORT  = "9225"   # default
.\Start-NetworkAgent.ps1
```

## API

All endpoints return JSON. Requests must include `Authorization: Bearer <token>`
when a token is configured.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Agent alive, ICS summary, uplink reachable |
| `GET` | `/ics/status` | Full ICS configuration (adapters, subnet, gateway) |
| `GET` | `/ics/hosts` | Discovered hosts on ICS subnet (IP, MAC, state) |
| `GET` | `/ics/diagnostics` | Adapters, routes, interfaces, reachability probes |
| `POST` | `/ics/enable` | Enable ICS (optional JSON body: `public_adapter`, `private_adapter`) |
| `POST` | `/ics/disable` | Disable ICS on all connections |

### Example: query hosts

```bash
curl -H "Authorization: Bearer my-secret-token" http://192.168.137.1:9225/ics/hosts
```

```json
{
  "hosts": [
    { "ip": "192.168.137.139", "mac": "A4-BB-6D-B7-22-08", "state": "Permanent", "interface": "Ethernet" }
  ],
  "count": 1,
  "polled_at": "2026-04-08T04:30:00.0000000Z"
}
```

## Integration with companion

Set these environment variables in `docker-compose.yml` or `.env`:

```env
TELVM_NETWORK_AGENT_URL=http://host.docker.internal:9225
TELVM_NETWORK_AGENT_TOKEN=my-secret-token
```

The companion's `NetworkAgentPoller` will poll `/health` and `/ics/hosts` and
broadcast results via PubSub to the dashboard's preflight "Network / ICS" panel.

## Architecture

```
lib/
  Ics.ps1        # ICS enable/disable via HNetCfg COM
  Inspect.ps1    # Adapter/route/reachability diagnostics
  Discover.ps1   # ARP/neighbor-based host enumeration
Start-NetworkAgent.ps1  # HttpListener loop, auth, routing
```

The `lib/` modules are dot-sourced by the entry point. Each exports pure functions
that return hashtables (converted to JSON by the HTTP layer). The original scripts
in `scripts/windows/` remain as standalone CLI tools.
