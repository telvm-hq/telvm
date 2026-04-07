<#
.SYNOPSIS
  Show local IPv4 setup, ARP/neighbors, and optionally scan the LAN for live hosts.
  Run in PowerShell as Administrator for best results.

.NOTES
  - "New" devices appear after they send traffic or after you scan/ping them.
  - Client isolation on Wi‑Fi can hide peers; Ethernet switch usually does not.
#>

[CmdletBinding()]
param(
    [switch]$FullSubnetPingScan,
    [int]$PingTimeoutMs = 400
)

$ErrorActionPreference = 'Continue'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host "=== Elevation ===" -ForegroundColor Cyan
if (-not (Test-IsAdmin)) {
    Write-Warning "Not running elevated. Some neighbor data may be incomplete. Re-run as Administrator."
} else {
    Write-Host "Running as Administrator."
}

Write-Host "`n=== Hostname / OS ===" -ForegroundColor Cyan
$env:COMPUTERNAME
[System.Environment]::OSVersion.VersionString

Write-Host "`n=== IPv4 interfaces (non-loopback) ===" -ForegroundColor Cyan
Get-NetIPConfiguration |
  Where-Object { $_.IPv4Address -and $_.InterfaceAlias -notmatch 'Loopback' } |
  ForEach-Object {
    $iface = $_.InterfaceAlias
    $ips = @($_.IPv4Address | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join ', '
    $gw = ($_.IPv4DefaultGateway | Select-Object -First 1).NextHop
    $metric = $_.InterfaceMetric
    [PSCustomObject]@{
      Interface = $iface
      IPv4      = $ips
      Gateway   = $gw
      Metric    = $metric
    }
  } | Format-Table -AutoSize

Write-Host "`n=== IPv4 routes (connected / on-link, common) ===" -ForegroundColor Cyan
Get-NetRoute -AddressFamily IPv4 |
  Where-Object { $_.RouteMetric -lt 256 -or $_.DestinationPrefix -match '^\d+\.\d+\.\d+\.\d+/\d+$' } |
  Sort-Object RouteMetric, DestinationPrefix |
  Select-Object -First 30 DestinationPrefix, NextHop, InterfaceAlias, RouteMetric |
  Format-Table -AutoSize

Write-Host "`n=== ARP cache (classic) ===" -ForegroundColor Cyan
arp -a

Write-Host "`n=== Get-NetNeighbor (IPv4, interesting states) ===" -ForegroundColor Cyan
Get-NetNeighbor -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.|224\.)' } |
  Sort-Object State, IPAddress |
  Select-Object IPAddress, LinkLayerAddress, State, InterfaceAlias |
  Format-Table -AutoSize

Write-Host "`n=== DNS client servers (per interface) ===" -ForegroundColor Cyan
Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.ServerAddresses } |
  Select-Object InterfaceAlias, ServerAddresses |
  Format-Table -AutoSize

if ($FullSubnetPingScan) {
    Write-Host "`n=== Full subnet ping scan (slow; populates neighbor cache) ===" -ForegroundColor Yellow
    $ifaces = Get-NetIPAddress -AddressFamily IPv4 |
      Where-Object {
        $_.IPAddress -notmatch '^(127\.)' -and
        $_.PrefixOrigin -ne 'WellKnown' -or $_.IPAddress -match '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)'
      }

    foreach ($a in $ifaces) {
        $ip = $a.IPAddress
        $pl = $a.PrefixLength
        if ($pl -ge 32) { continue }

        # crude: assume last octet is host; scan .1-.254 for /24 only
        if ($pl -ne 24) {
            Write-Warning "Skipping scan for $ip/$pl (script only auto-scans /24). Run ping manually for other prefixes."
            continue
        }

        $oct = $ip -split '\.'
        if ($oct.Count -ne 4) { continue }
        $base = "$($oct[0]).$($oct[1]).$($oct[2])"
        Write-Host "Scanning $base.0/24 from interface context..." -ForegroundColor Cyan

        $jobs = 1..254 | ForEach-Object -ThrottleLimit 40 {
            $target = "$using:base.$_"
            if ($target -eq $using:ip) { return }
            $p = Test-Connection -ComputerName $target -Count 1 -Quiet -TimeoutSeconds 1 -ErrorAction SilentlyContinue
            if ($p) { $target }
        }
        # PS 5.1: ForEach-Object -Parallel doesn't exist. Use jobs fallback:

    }

    Write-Warning "PowerShell 5.1: parallel ping not in this block. Use simple loop (slower)..."

    foreach ($a in Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixLength -eq 24 -and $_.IPAddress -notmatch '^127\.' }) {
        $ip = $a.IPAddress
        $oct = $ip -split '\.'
        $base = "$($oct[0]).$($oct[1]).$($oct[2])"
        Write-Host "Pinging $base.1 - $base.254 (one sec timeout each batch of 32)..." -ForegroundColor Cyan
        for ($h = 1; $h -le 254; $h++) {
            $target = "$base.$h"
            if ($target -eq $ip) { continue }
            [void][Net.Networkinformation.Ping]::new().SendPingAsync($target, $PingTimeoutMs).Result
        }
    }

    Write-Host "`n=== ARP / Neighbors after scan ===" -ForegroundColor Cyan
    Get-NetNeighbor -AddressFamily IPv4 |
      Where-Object { $_.IPAddress -notmatch '^(127\.|224\.)' } |
      Sort-Object IPAddress |
      Select-Object IPAddress, LinkLayerAddress, State, InterfaceAlias |
      Format-Table -AutoSize
}

Write-Host "`n=== Done ===" -ForegroundColor Green
Write-Host "Tip: If the new PC is missing, run with -FullSubnetPingScan (slow), or ping the new host from the router DHCP lease list, then re-run." -ForegroundColor DarkGray