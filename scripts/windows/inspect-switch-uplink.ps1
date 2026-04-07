#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  From a Windows PC on a switch, summarize L2/L3 path toward "the other cable" (uplink/internet).

.DESCRIPTION
  Shows which Ethernet links are up, your IPv4 + gateway + DNS, default routes, ARP neighbors
  on those segments, and quick probes to the gateway and the public internet.

  The default gateway on your subnet is usually the device on the uplink path (router/firewall).

.EXAMPLE
  .\inspect-switch-uplink.ps1
#>
$ErrorActionPreference = "Continue"

function Write-Section($Title) {
  Write-Host ""
  Write-Host "=== $Title ===" -ForegroundColor Cyan
}

Write-Section "Host"
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "UTC:      $([DateTime]::UtcNow.ToString('o'))"

Write-Section "Ethernet adapters (Up)"
$ethUp = Get-NetAdapter | Where-Object {
  $_.Status -eq "Up" -and (
    $_.PhysicalMediaType -match "802.3" -or
    $_.InterfaceDescription -match "Ethernet|Gigabit|LAN|2\.5G|10G|USB.*Ethernet|Realtek|Intel.*Network|Mellanox"
  )
} | Sort-Object InterfaceIndex

if (-not $ethUp) {
  Write-Host "No matching Up Ethernet adapters found. Is the cable connected?" -ForegroundColor Yellow
} else {
  foreach ($a in $ethUp) {
    Write-Host ""
    Write-Host ("{0}  |  {1}" -f $a.Name, $a.InterfaceDescription)
    Write-Host ("  Link: {0}  Speed: {1}  ifIndex={2}" -f $a.Status, $a.LinkSpeed, $a.InterfaceIndex)
  }
}

Write-Section "IPv4, gateway, DNS (per connected interface)"
Get-NetIPConfiguration |
  Where-Object { $_.NetAdapter.Status -eq "Up" } |
  ForEach-Object {
    $na = $_.NetAdapter
    if ($na.PhysicalMediaType -notmatch "802.3" -and $na.InterfaceDescription -notmatch "Ethernet|Gigabit|LAN|USB.*Ethernet") {
      return
    }
    Write-Host ""
    Write-Host ("Interface: {0} ({1})" -f $_.InterfaceAlias, $na.InterfaceDescription)
    foreach ($addr in $_.IPv4Address) {
      if ($addr.IPAddress) {
        Write-Host ("  Address:  {0}/{1}" -f $addr.IPAddress, $addr.PrefixLength)
      }
    }
    $gw = $_.IPv4DefaultGateway
    if ($gw) {
      Write-Host ("  Gateway:  {0}  (typical uplink / router for this subnet)" -f $gw.NextHop) -ForegroundColor Green
    } else {
      Write-Host "  Gateway:  (none - no default route on this interface)" -ForegroundColor Yellow
    }
    $dns = ($_.DnsServer | Where-Object { $_.ServerAddresses } | Select-Object -ExpandProperty ServerAddresses)
    if ($dns) {
      Write-Host ("  DNS:      {0}" -f ($dns -join ", "))
    }
  }

Write-Section "Default IPv4 routes (0.0.0.0/0)"
$defs = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } |
  Sort-Object RouteMetric
if (-not $defs) {
  Write-Host "No default route - internet/off-LAN traffic has no next hop." -ForegroundColor Yellow
} else {
  foreach ($r in $defs) {
    $alias = (Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue).Name
    Write-Host ("Next hop: {0}  Interface: {1} (ifIndex {2})  Metric: {3}" -f $r.NextHop, $alias, $r.InterfaceIndex, $r.RouteMetric)
  }
}

Write-Section "ARP / neighbors on this segment (same switch broadcast domain)"
foreach ($a in $ethUp) {
  $neigh = Get-NetNeighbor -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.State -match "Reachable|Stale|Delay|Probe" -and
      $_.IPAddress -notmatch "^(224\.|239\.|255\.)"
    } |
    Sort-Object IPAddress
  Write-Host ""
  Write-Host "Adapter: $($a.Name)"
  if (-not $neigh) {
    Write-Host "  (no cached neighbors - try ping gateway or browse; or segment is quiet)"
  } else {
    $neigh | ForEach-Object {
      Write-Host ("  {0,-16}  {1}" -f $_.IPAddress, $_.LinkLayerAddress)
    }
  }
}

Write-Section "Quick reachability"
$firstGw = ($defs | Select-Object -First 1).NextHop
if ($firstGw) {
  Write-Host "Pinging gateway $firstGw ..."
  Test-Connection -ComputerName $firstGw -Count 2 -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host ("  Reply from {0} time={1}ms" -f $_.Address, $_.ResponseTime) }
} else {
  Write-Host "Skip gateway ping (no default route)."
}

Write-Host "Pinging 1.1.1.1 (public IP, tests routing past gateway) ..."
$pub = Test-Connection -ComputerName 1.1.1.1 -Count 2 -ErrorAction SilentlyContinue
if ($pub) {
  $pub | ForEach-Object { Write-Host ("  Reply from {0} time={1}ms" -f $_.Address, $_.ResponseTime) }
} else {
  Write-Host "  No reply - uplink/NAT/firewall may block ICMP, or no route to internet." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "DNS lookup test: resolve google.com"
try {
  $r = Resolve-DnsName -Name google.com -DnsOnly -ErrorAction Stop | Select-Object -First 1
  Write-Host ("  OK: {0}" -f $r.Name)
} catch {
  Write-Host ("  Failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done. Your default gateway IP is the best single clue for what sits on the uplink path." -ForegroundColor DarkGray
