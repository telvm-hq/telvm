# Verify HTTPS via Telvm egress proxy from closed-agent containers (Windows-friendly).
# Prereq: repo root, docker compose up --build.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "telvm: verify closed-agent egress via companion proxy"
Write-Host "Note: lab_relaxed may still allow direct TCP; this checks the proxy path only."
Write-Host ""

$cmdC = 'curl -sS -o /dev/null -w "%{http_code}" --max-time 25 --proxy http://companion:4001 https://api.anthropic.com/'
$codeC = & docker compose exec -T telvm_closed_claude sh -c $cmdC 2>$null
if (-not $codeC) { $codeC = "000" }
Write-Host "telvm_closed_claude -> companion:4001 -> api.anthropic.com  HTTP $codeC"
if ($codeC -eq "000") {
    throw "FAIL: no HTTP response (stack up? docker compose up --build)"
}

$cmdX = 'curl -sS -o /dev/null -w "%{http_code}" --max-time 25 --proxy http://companion:4002 https://api.openai.com/'
$codeX = & docker compose exec -T telvm_closed_codex sh -c $cmdX 2>$null
if (-not $codeX) { $codeX = "000" }
Write-Host "telvm_closed_codex  -> companion:4002 -> api.openai.com    HTTP $codeX"
if ($codeX -eq "000") {
    throw "FAIL: no HTTP response"
}

Write-Host ""
Write-Host "apt through proxy (HTTP_PROXY set; root user — no sudo):"
$aptC = "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq"
& docker compose exec -T telvm_closed_claude sh -c $aptC
if ($LASTEXITCODE -ne 0) { throw "FAIL: apt-get update in telvm_closed_claude" }
Write-Host "telvm_closed_claude  apt-get update  OK"

& docker compose exec -T telvm_closed_codex sh -c $aptC
if ($LASTEXITCODE -ne 0) { throw "FAIL: apt-get update in telvm_closed_codex" }
Write-Host "telvm_closed_codex   apt-get update  OK"

Write-Host ""
Write-Host "OK. Companion log correlation:"
Write-Host "  docker compose logs companion 2>&1 | Select-String egress_proxy"
