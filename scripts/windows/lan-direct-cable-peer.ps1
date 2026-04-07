#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Inspect a direct Windows <-> machine Ethernet link (no switch), typical APIPA or small static lab.

.DESCRIPTION
  Complements lan-ethernet-connection-state.ps1. Optimized for:
    machine --- Ethernet cable --- Windows
  (not: machine --- switch --- Windows)

  ASCII only - safe for Windows PowerShell 5.1 encoding.

.EXAMPLE
  .\lan-direct-cable-peer.ps1

.EXAMPLE
  .\lan-direct-cable-peer.ps1 -PeerIp 169.254.88.12

.EXAMPLE
  .\lan-direct-cable-peer.ps1 -GuessPing169ThirdOctet
#>
param(
  [string] $PeerIp,

  [switch] $GuessPing169ThirdOctet,

  [int[]] $TcpPorts = @(22)
)

$ErrorActionPreference = "Continue"

function Write-Section($Title) {
  Write-Host ""
  Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Test-IsApiPa([string] $IPv4) {
  return $IPv4.StartsWith("169.254.")
}

function Get-PhysicalEthernetCandidates {
  $exclude = @(
    "Hyper-V", "WSL", "Virtual", "VMware", "VirtualBox", "Bluetooth", "Loopback",
    "Teredo", "Wi-Fi", "Wireless", "802.11"
  )
  Get-NetAdapter | Where-Object {
    $_.Status -eq "Up" -and $_.PhysicalMediaType -match "802.3"
  } | Where-Object {
    $d = $_.InterfaceDescription
    $hit = $false
    foreach ($x in $exclude) {
      if ($d -like "*$x*") { $hit = $true; break }
    }
    -not $hit
  } | Sort-Object InterfaceIndex
}

Write-Section "Topology"
Write-Host "Mode: direct cable (peer machine --- cable --- this Windows PC)."
Write-Host "If you use a switch or router DHCP, use lan-ethernet-connection-state.ps1 instead."

Write-Section "Time and host"
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "UTC:      $([DateTime]::UtcNow.ToString('o'))"

Write-Section "Default route (often Wi-Fi, not the direct cable)"
$def = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } |
  Sort-Object RouteMetric | Select-Object -First 3
foreach ($r in $def) {
  $ad = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
  $alias = if ($ad) { $ad.Name } else { "ifIndex=$($r.InterfaceIndex)" }
  Write-Host "  Via $($r.NextHop)  $alias  metric=$($r.RouteMetric)"
}
Write-Host "  Gotcha: traffic to non-link-local IPs usually follows this route, not the direct wire."

Write-Section "Physical Ethernet candidates (direct link NIC)"
$cands = @(Get-PhysicalEthernetCandidates)
if ($cands.Count -eq 0) {
  Write-Host "No obvious physical Ethernet adapter found (Up). Check cable and driver."
  exit 1
}

$nic = $cands[0]
if ($cands.Count -gt 1) {
  Write-Host "Multiple candidates; using first: $($nic.Name). Others:"
  $cands | Select-Object -Skip 1 | ForEach-Object { Write-Host "  - $($_.Name)" }
}

$ips = @(Get-NetIPAddress -InterfaceIndex $nic.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
Write-Host ""
Write-Host "NIC: $($nic.Name)"
Write-Host "  Description: $($nic.InterfaceDescription)"
Write-Host "  Link: $($nic.LinkSpeed)  Status: $($nic.Status)"
foreach ($ip in $ips) {
  $a = $ip.IPAddress
  $pfx = $ip.PrefixLength
  $kind = if (Test-IsApiPa $a) { "APIPA link-local (no DHCP on this link)" } else { "configured address" }
  Write-Host "  IPv4: $a/$pfx  ($kind)"
}

$primary = $ips | Select-Object -First 1
if (-not $primary) {
  Write-Host "  No IPv4 on this adapter yet."
  exit 1
}

$myIp = $primary.IPAddress

Write-Section "On-link routes for 169.254.0.0/16 (APIPA)"
Get-NetRoute -InterfaceIndex $nic.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.DestinationPrefix -like "169.254*" } |
  ForEach-Object {
    Write-Host "  $($_.DestinationPrefix) -> $($_.NextHop) metric=$($_.RouteMetric)"
  }

Write-Section "ARP / neighbor cache on this NIC (ifIndex=$($nic.InterfaceIndex))"
$neigh = Get-NetNeighbor -InterfaceIndex $nic.InterfaceIndex -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' }
if ($neigh) {
  $neigh | Sort-Object State, IPAddress | ForEach-Object {
    Write-Host "  $($_.IPAddress)  state=$($_.State)  MAC=$($_.LinkLayerAddress)"
  }
} else {
  Write-Host "  (empty - normal until there is L2 traffic, e.g. ping peer or peer talks first)"
}

Write-Section "All 169.254.* ARP entries (any interface)"
cmd /c "arp -a" 2>$null | Select-String "169\.254\." | ForEach-Object { Write-Host "  $($_.Line.Trim())" }

if ($GuessPing169ThirdOctet -and (Test-IsApiPa $myIp)) {
  Write-Section "Guess ping same 169.254.x.* third octet as this PC"
  $parts = $myIp.Split(".")
  $p = "{0}.{1}.{2}" -f $parts[0], $parts[1], $parts[2]
  Write-Host "Probing $p.* (timeout ~250ms each, common lab guess - not exhaustive)"
  $ping = New-Object System.Net.NetworkInformation.Ping
  foreach ($last in @(1, 2, 10, 100, 101, 200, 254)) {
    $target = "$p.$last"
    if ($target -eq $myIp) { continue }
    try {
      $r = $ping.Send($target, 250)
      if ($r.Status -eq "Success") {
        Write-Host "  reply: $target" -ForegroundColor Green
      }
    } catch { }
  }
  $ping.Dispose()
  Write-Host "If nothing replied, set static IPs on both ends or read peer IP from its console (ip -br a)."
}

if (-not [string]::IsNullOrWhiteSpace($PeerIp)) {
  Write-Section "Peer checks: $PeerIp"
  $valid = $PeerIp -as [System.Net.IPAddress]
  if (-not $valid) {
    Write-Host "Invalid IPv4." -ForegroundColor Red
    exit 1
  }

  Write-Host "Route Windows would use:"
  Find-NetRoute -RemoteIPAddress $PeerIp -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  iface=$($_.InterfaceAlias) nextHop=$($_.NextHop) dest=$($_.DestinationPrefix)"
  }

  Write-Host ""
  Write-Host "ICMP 1x:"
  $ok = Test-Connection -ComputerName $PeerIp -Count 1 -Quiet -ErrorAction SilentlyContinue
  if ($ok) { Write-Host "  ping: ok" -ForegroundColor Green }
  else { Write-Host "  ping: no reply (firewall off, wrong IP, or not same L2 segment)" -ForegroundColor Yellow }

  foreach ($port in $TcpPorts) {
    $t = Test-NetConnection -ComputerName $PeerIp -Port $port -WarningAction SilentlyContinue
    if ($t.TcpTestSucceeded) {
      Write-Host "  TCP $port : open/reachable" -ForegroundColor Green
    } else {
      Write-Host "  TCP $port : not reachable" -ForegroundColor Yellow
    }
  }

  Write-Host ""
  Write-Host "Neighbor entry for peer after probe:"
  Get-NetNeighbor -IPAddress $PeerIp -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  state=$($_.State) MAC=$($_.LinkLayerAddress) ifIndex=$($_.InterfaceIndex)"
  }
}

Write-Section "Static lab pair (when APIPA is not enough)"
Write-Host "On Ubuntu (Netplan or nmcli), and Windows adapter IPv4 properties, use e.g.:"
Write-Host "  Windows: 10.10.10.1  mask 255.255.255.252  gateway (empty)"
Write-Host "  Ubuntu:  10.10.10.2  mask 255.255.255.252  gateway (empty)"
Write-Host "Then: .\lan-direct-cable-peer.ps1 -PeerIp 10.10.10.2"

Write-Host ""
Write-Host "Done."