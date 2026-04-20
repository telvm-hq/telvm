<#
.SYNOPSIS
  Show what is listening on a TCP port on Windows (default: 11434, Ollama).

.DESCRIPTION
  Use this when Docker reports: "Bind for 0.0.0.0:11434 failed: port is already allocated".

  docker compose down only removes containers for that Compose project. It does not:
  - Stop Ollama (or anything else) installed outside that compose file
  - Free the port if another stack still publishes 11434
  - Always clear a stuck docker-proxy (restarting Docker Desktop can help)

  The telvm-network-agent exposes HTTP metrics; it does not replace host port diagnostics - this script does.

.PARAMETER Port
  TCP port to inspect (default 11434).

.EXAMPLE
  .\who-owns-port.ps1
  .\who-owns-port.ps1 -Port 4020
#>
param(
  [Parameter(Mandatory = $false)]
  [ValidateRange(1, 65535)]
  [int]$Port = 11434
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "=== Who owns TCP port $Port ? (Slackeel / Windows) ===" -ForegroundColor Cyan
Write-Host ""

try {
  $listeners = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
} catch {
  Write-Host "Could not query TCP listeners: $_" -ForegroundColor Red
  exit 1
}

if (-not $listeners) {
  Write-Host "No LISTEN socket on port $Port right now - the port looks free from this host TCP stack." -ForegroundColor Green
  Write-Host "(If Docker still errors, try restarting Docker Desktop or check WSL/Hyper-V port forwarding.)" -ForegroundColor DarkGray
  Write-Host ""
  exit 0
}

$pids = $listeners | Select-Object -ExpandProperty OwningProcess -Unique | Sort-Object

Write-Host "--- Owning process(es) ---" -ForegroundColor Yellow
foreach ($procId in $pids) {
  try {
    $p = Get-Process -Id $procId -ErrorAction Stop
    $path = $p.Path
    if (-not $path) { $path = "(path unavailable - try running as Administrator)" }
    Write-Host ("  PID {0,-8} {1,-24} {2}" -f $procId, $p.ProcessName, $path)
  } catch {
    Write-Host ("  PID {0,-8} (could not resolve process: {1})" -f $procId, $_)
  }
}

Write-Host ""
Write-Host "Hints:" -ForegroundColor DarkGray
Write-Host "  - com.docker.backend / vpnkit / docker-proxy often mean Docker is publishing the port for some container." -ForegroundColor DarkGray
Write-Host "  - ollama / Ollama means a native or separate install is using the API port." -ForegroundColor DarkGray
Write-Host ""

if (Get-Command docker -ErrorAction SilentlyContinue) {
  Write-Host "--- Docker: containers publishing this port (if any) ---" -ForegroundColor Yellow
  $dockerOut = docker ps --filter "publish=$Port" --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" 2>&1
  if ($LASTEXITCODE -eq 0 -and $dockerOut) {
    $dockerOut | ForEach-Object { Write-Host $_ }
  } else {
    Write-Host "  (none matched filter publish=$Port, or docker failed - try: docker ps)" -ForegroundColor DarkGray
  }
  Write-Host ""
}

Write-Host "Done." -ForegroundColor Green
Write-Host ""
