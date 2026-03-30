#Requires -Version 5.1
<#
.SYNOPSIS
  Collect telvm Docker Compose + HTTP diagnostics in one run (Windows / PowerShell).

.DESCRIPTION
  From the repo root (or anywhere — script locates repo via its own path):
    .\scripts\docker-diagnostics.ps1

  Prints:
    - docker compose ps -a
    - recent logs for companion, vm_node, db
    - host-side request to http://127.0.0.1:4000/
    - in-container curl to http://127.0.0.1:4000/ (no Mix)
    - mix run --no-start scripts/diagnostics.exs (TCP/HTTP + ss + env; does not boot the OTP app)

  If `mix run` complains about _build locks, stop the stack once and re-run, or wait until
  the first `mix phx.server` boot finishes compiling.
#>

$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

Write-Host "telvm docker diagnostics" -ForegroundColor Green
Write-Host "Repo: $RepoRoot"

Write-Section "docker compose ps -a"
docker compose ps -a

Write-Section "docker compose logs companion --tail 150"
docker compose logs companion --tail 150

Write-Section "docker compose logs vm_node --tail 30"
docker compose logs vm_node --tail 30

Write-Section "docker compose logs db --tail 15"
docker compose logs db --tail 15

Write-Section "Host -> http://127.0.0.1:4000/ (Invoke-WebRequest)"
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:4000/" -UseBasicParsing -TimeoutSec 15
    Write-Host "StatusCode: $($r.StatusCode) Content-Length: $($r.RawContentLength)"
}
catch {
    Write-Host "FAILED: $($_.Exception.Message)"
}

$companionId = docker compose ps -q companion 2>$null
if (-not $companionId) {
    Write-Section "In-container probes"
    Write-Host "companion container is not running - skipping exec."
}
else {
    Write-Section "In-container curl -> http://127.0.0.1:4000/"
    docker compose exec -T companion sh -c 'curl -sS -m 10 -D- http://127.0.0.1:4000/ -o /tmp/telvm_diag_body.txt 2>&1; echo; echo "--- body (first 1200 bytes) ---"; head -c 1200 /tmp/telvm_diag_body.txt 2>/dev/null; echo'

    Write-Section "mix run --no-start scripts/diagnostics.exs (from /app)"
    docker compose exec -T companion sh -c 'cd /app && mix run --no-start scripts/diagnostics.exs'
}

Write-Section "done"
Write-Host "If port 4000 fails: check companion logs above for compile time, crashes, or DB errors." -ForegroundColor Yellow
