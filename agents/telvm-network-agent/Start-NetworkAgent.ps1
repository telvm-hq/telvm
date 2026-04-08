#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  telvm network agent - lightweight HTTP service exposing ICS state and host discovery.

.DESCRIPTION
  Long-running PowerShell process that listens on a configurable port, authenticates
  requests via Bearer token, and serves JSON endpoints for ICS management and LAN
  host discovery. Designed to be polled by the telvm companion dashboard.

.EXAMPLE
  .\Start-NetworkAgent.ps1 -Token "my-secret"

.EXAMPLE
  .\Start-NetworkAgent.ps1 -Port 9225 -Token "my-secret"
#>
param(
  [int]    $Port  = $(if ($env:TELVM_NETWORK_AGENT_PORT) { [int]$env:TELVM_NETWORK_AGENT_PORT } else { 9225 }),
  [string] $Token = $(if ($env:TELVM_NETWORK_AGENT_TOKEN) { $env:TELVM_NETWORK_AGENT_TOKEN } else { "" })
)

$ErrorActionPreference = "Stop"
$script:Version = "0.1.0"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\lib\Ics.ps1"
. "$ScriptDir\lib\Inspect.ps1"
. "$ScriptDir\lib\Discover.ps1"

# ── helpers ──────────────────────────────────────────────────────────────────

function ConvertTo-JsonSafe($obj) {
  # PowerShell 5.1 ConvertTo-Json defaults to depth 2; we need deeper.
  ConvertTo-Json $obj -Depth 10 -Compress
}

function Send-JsonResponse {
  param(
    [System.Net.HttpListenerResponse] $Response,
    [int] $StatusCode,
    $Body
  )
  $Response.StatusCode = $StatusCode
  $Response.ContentType = "application/json; charset=utf-8"
  $Response.AddHeader("X-Telvm-Agent", "network/$script:Version")

  $json = if ($Body -is [string]) { $Body } else { ConvertTo-JsonSafe $Body }
  $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
  $Response.ContentLength64 = $buf.Length
  $Response.OutputStream.Write($buf, 0, $buf.Length)
  $Response.OutputStream.Close()
}

function Test-BearerAuth {
  param(
    [System.Net.HttpListenerRequest] $Request,
    [string] $ExpectedToken
  )
  if ([string]::IsNullOrEmpty($ExpectedToken)) { return $true }

  $auth = $Request.Headers["Authorization"]
  if (-not $auth) { return $false }
  if (-not $auth.StartsWith("Bearer ", [StringComparison]::OrdinalIgnoreCase)) { return $false }
  $provided = $auth.Substring(7)
  return $provided -eq $ExpectedToken
}

function Read-RequestBody {
  param([System.Net.HttpListenerRequest] $Request)
  if (-not $Request.HasEntityBody) { return $null }
  $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
  try { return $reader.ReadToEnd() }
  finally { $reader.Close() }
}

# ── route handlers ───────────────────────────────────────────────────────────

function Handle-Health {
  $icsStatus = Get-IcsStatus
  return @{
    agent    = "telvm-network-agent"
    version  = $script:Version
    hostname = $env:COMPUTERNAME
    utc      = [DateTime]::UtcNow.ToString('o')
    ics      = @{
      enabled         = $icsStatus.enabled
      public_adapter  = $icsStatus.public_adapter
      private_adapter = $icsStatus.private_adapter
    }
    uplink_reachable = (Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet -ErrorAction SilentlyContinue)
  }
}

function Handle-IcsStatus {
  return Get-IcsStatus
}

function Handle-IcsHosts {
  $hosts = Get-IcsHosts
  return @{
    hosts       = $hosts
    count       = $hosts.Count
    polled_at   = [DateTime]::UtcNow.ToString('o')
  }
}

function Handle-IcsEnable {
  param([string] $RequestBody)
  $params = @{}
  if ($RequestBody) {
    try { $params = $RequestBody | ConvertFrom-Json } catch { }
  }
  $public  = if ($params.public_adapter)  { $params.public_adapter }  else { $null }
  $private = if ($params.private_adapter) { $params.private_adapter } else { $null }
  return Enable-Ics -PublicName $public -PrivateName $private
}

function Handle-IcsDisable {
  return Disable-Ics
}

function Handle-IcsDiagnostics {
  return Get-NetworkDiagnostics
}

# ── main loop ────────────────────────────────────────────────────────────────

if ([string]::IsNullOrEmpty($Token)) {
  Write-Warning "No --Token or TELVM_NETWORK_AGENT_TOKEN set. Agent will accept unauthenticated requests."
}

$prefix = "http://+:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
  $listener.Start()
} catch {
  Write-Host "Failed to start listener on $prefix - $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Ensure the port is free and you are running as Administrator." -ForegroundColor Yellow
  exit 1
}

Write-Host "telvm-network-agent $script:Version listening on :$Port" -ForegroundColor Green

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response

    $method = $req.HttpMethod.ToUpper()
    $path   = $req.Url.AbsolutePath.TrimEnd('/')

    try {
      if (-not (Test-BearerAuth -Request $req -ExpectedToken $Token)) {
        Send-JsonResponse -Response $res -StatusCode 401 -Body @{ error = "unauthorized" }
        continue
      }

      $body    = $null
      $status  = 200

      switch ("$method $path") {
        "GET /health"           { $body = Handle-Health }
        "GET /ics/status"       { $body = Handle-IcsStatus }
        "GET /ics/hosts"        { $body = Handle-IcsHosts }
        "GET /ics/diagnostics"  { $body = Handle-IcsDiagnostics }
        "POST /ics/enable"      {
          $reqBody = Read-RequestBody -Request $req
          $body = Handle-IcsEnable -RequestBody $reqBody
        }
        "POST /ics/disable"     { $body = Handle-IcsDisable }
        default {
          $status = 404
          $body = @{ error = "not_found"; path = $path; method = $method }
        }
      }

      Send-JsonResponse -Response $res -StatusCode $status -Body $body
    } catch {
      try {
        Send-JsonResponse -Response $res -StatusCode 500 -Body @{
          error   = "internal_error"
          message = $_.Exception.Message
        }
      } catch { }
      Write-Host "[ERROR] $method $path - $($_.Exception.Message)" -ForegroundColor Red
    }
  }
} finally {
  $listener.Stop()
  $listener.Close()
  Write-Host "Agent stopped." -ForegroundColor Yellow
}
