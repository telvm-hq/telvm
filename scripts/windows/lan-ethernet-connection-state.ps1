#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Inspect Windows Ethernet/L3 state and optional reachability to a LAN VM by IP.

.DESCRIPTION
  No Docker, no git - local OS only. Shows adapters, IPv4 addresses, default route,
  and (if you pass -TargetVmIp) ping, ARP, and TCP probes to common ports.

.EXAMPLE
  .\lan-ethernet-connection-state.ps1

.EXAMPLE
  .\lan-ethernet-connection-state.ps1 -TargetVmIp 192.168.1.50

.EXAMPLE
  .\lan-ethernet-connection-state.ps1 -TargetVmIp 192.168.1.50 -TcpPorts 22,80,443
#>
param(
  [string] $TargetVmIp,

  [int[]] $TcpPorts = @(22, 80, 443)
)

$ErrorActionPreference = "Continue"

function Write-Section($Title) {
  Write-Host ""
  Write-Host "=== $Title ===" -ForegroundColor Cyan
}

Write-Section "Time and host"
Write-Host "Local computer: $env:COMPUTERNAME"
Write-Host "UTC:            $([DateTime]::UtcNow.ToString('o'))"

Write-Section "Physical / virtual Ethernet adapters (status)"
Get-NetAdapter | Where-Object {
  $_.Status -eq "Up" -and (
    $_.PhysicalMediaType -match "802.3" -or
    $_.InterfaceDescription -match "Ethernet|Gigabit|LAN|USB.*Ethernet|Realtek|Intel.*Network"
  )
} | Sort-Object InterfaceIndex | ForEach-Object {
  $a = $_
  $ips = Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
  Write-Host ""
  Write-Host ("Adapter: {0} ({1})" -f $a.Name, $a.InterfaceDescription)
  Write-Host ("  Status: {0}  LinkSpeed: {1}" -f $a.Status, $a.LinkSpeed)
  foreach ($ip in $ips) {
    $pref = $ip.PrefixLength
    Write-Host ("  IPv4: {0}/{1}" -f $ip.IPAddress, $pref)
  }
}

Write-Section "All IPv4 addresses (any interface, Up adapters only)"
Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object {
    $idx = $_.InterfaceIndex
    (Get-NetAdapter -InterfaceIndex $idx -ErrorAction SilentlyContinue).Status -eq "Up"
  } |
  Sort-Object InterfaceIndex, IPAddress |
  ForEach-Object {
    Write-Host ("{0,-40} {1}/{2}  ifIndex={3}" -f $_.InterfaceAlias, $_.IPAddress, $_.PrefixLength, $_.InterfaceIndex)
  }

Write-Section "Default IPv4 route (where general internet/LAN egress goes)"
Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } |
  Sort-Object RouteMetric |
  ForEach-Object {
    Write-Host ("Via {0}  ifIndex={1}  Metric={2}" -f $_.NextHop, $_.InterfaceIndex, $_.RouteMetric)
  }

if (-not [string]::IsNullOrWhiteSpace($TargetVmIp)) {
  Write-Section "Target VM: $TargetVmIp"

  $valid = $TargetVmIp -as [System.Net.IPAddress]
  if (-not $valid) {
    Write-Host "TargetVmIp is not a valid IP address." -ForegroundColor Red
    exit 1
  }

  Write-Host "Most specific route to target:"
  Find-NetRoute -RemoteIPAddress $TargetVmIp -ErrorAction SilentlyContinue |
    ForEach-Object {
      Write-Host ("  DestinationPrefix: {0}" -f $_.DestinationPrefix)
      Write-Host ("  NextHop:           {0}" -f $_.NextHop)
      Write-Host ("  InterfaceAlias:    {0}" -f $_.InterfaceAlias)
      Write-Host ("  RouteMetric:       {0}" -f $_.RouteMetric)
    }

  Write-Host ""
  Write-Host "ARP / neighbor cache entry (if any):"
  $n = Get-NetNeighbor -IPAddress $TargetVmIp -ErrorAction SilentlyContinue
  if ($n) {
    $n | ForEach-Object {
      Write-Host ("  State={0}  LinkLayerAddress={1}  ifIndex={2}" -f $_.State, $_.LinkLayerAddress, $_.InterfaceIndex)
    }
  } else {
    Write-Host "  (no entry yet - often appears after first L2 contact, e.g. ping)"
  }

  Write-Host ""
  Write-Host "ICMP (ping), 1 attempt:"
  try {
    $ping = Test-Connection -ComputerName $TargetVmIp -Count 1 -Quiet -ErrorAction Stop
    if ($ping) { Write-Host "  Ping: success" -ForegroundColor Green }
    else { Write-Host "  Ping: no reply (or blocked)" -ForegroundColor Yellow }
  } catch {
    Write-Host "  Ping: error - $($_.Exception.Message)" -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "TCP connect tests (client from this PC):"
  foreach ($port in $TcpPorts) {
    try {
      $t = Test-NetConnection -ComputerName $TargetVmIp -Port $port -WarningAction SilentlyContinue
      if ($t.TcpTestSucceeded) {
        Write-Host ("  Port {0}: reachable" -f $port) -ForegroundColor Green
      } else {
        Write-Host ("  Port {0}: not reachable (refused/filtered/no listener)" -f $port) -ForegroundColor Yellow
      }
    } catch {
      Write-Host ("  Port {0}: error - {1}" -f $port, $_.Exception.Message) -ForegroundColor Yellow
    }
  }

  Write-Host ""
  Write-Host "ARP again after probes:"
  $n2 = Get-NetNeighbor -IPAddress $TargetVmIp -ErrorAction SilentlyContinue
  if ($n2) {
    $n2 | ForEach-Object {
      Write-Host ("  State={0}  MAC={1}" -f $_.State, $_.LinkLayerAddress)
    }
  } else {
    Write-Host "  Still no neighbor entry - different subnet, routing issue, or no L2 path."
  }
} else {
  Write-Section "Target VM"
  Write-Host "No -TargetVmIp passed. Re-run with your Ubuntu VM IPv4, e.g.:"
  Write-Host "  .\lan-ethernet-connection-state.ps1 -TargetVmIp 192.168.x.x"
}

Write-Host ""
Write-Host "Done."
