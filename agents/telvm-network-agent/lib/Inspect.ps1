<#
.SYNOPSIS
  Network inspection / diagnostics functions.
  Dot-source this file; do not run directly.
#>

function Get-NetworkDiagnostics {
  <#
  .SYNOPSIS Returns structured network diagnostics as a hashtable.
  #>
  $diag = @{
    hostname   = $env:COMPUTERNAME
    utc        = [DateTime]::UtcNow.ToString('o')
    adapters   = @()
    interfaces = @()
    routes     = @()
    reachability = @{
      gateway       = $null
      gateway_ip    = $null
      public_ip_ok  = $false
      dns_ok        = $false
    }
  }

  # Ethernet adapters (Up)
  $ethUp = Get-NetAdapter | Where-Object {
    $_.Status -eq "Up" -and (
      $_.PhysicalMediaType -match "802.3" -or
      $_.InterfaceDescription -match "Ethernet|Gigabit|LAN|2\.5G|10G|USB.*Ethernet|Realtek|Intel.*Network|Mellanox"
    )
  } | Sort-Object InterfaceIndex

  foreach ($a in $ethUp) {
    $diag.adapters += @{
      name         = $a.Name
      description  = $a.InterfaceDescription
      status       = $a.Status
      speed        = $a.LinkSpeed
      ifIndex      = $a.InterfaceIndex
      mac          = $a.MacAddress
    }
  }

  # IPv4 per connected Ethernet-like interface
  Get-NetIPConfiguration |
    Where-Object { $_.NetAdapter.Status -eq "Up" } |
    ForEach-Object {
      $na = $_.NetAdapter
      if ($na.PhysicalMediaType -notmatch "802.3" -and
          $na.InterfaceDescription -notmatch "Ethernet|Gigabit|LAN|USB.*Ethernet|Hyper-V") {
        return
      }
      foreach ($addr in $_.IPv4Address) {
        if ($addr.IPAddress) {
          $gw = $_.IPv4DefaultGateway
          $dns = ($_.DnsServer | Where-Object { $_.ServerAddresses } |
                  Select-Object -ExpandProperty ServerAddresses) -join ", "
          $diag.interfaces += @{
            name         = $_.InterfaceAlias
            description  = $na.InterfaceDescription
            address      = "$($addr.IPAddress)/$($addr.PrefixLength)"
            gateway      = if ($gw) { $gw.NextHop } else { $null }
            dns          = $dns
          }
        }
      }
    }

  # Default IPv4 routes
  $defs = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } |
    Sort-Object RouteMetric
  foreach ($r in $defs) {
    $alias = (Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue).Name
    $diag.routes += @{
      destination = $r.DestinationPrefix
      next_hop    = $r.NextHop
      interface   = $alias
      ifIndex     = $r.InterfaceIndex
      metric      = $r.RouteMetric
    }
  }

  # Reachability probes
  $firstGw = ($defs | Select-Object -First 1).NextHop
  if ($firstGw) {
    $diag.reachability.gateway_ip = $firstGw
    $gwPing = Test-Connection -ComputerName $firstGw -Count 1 -Quiet -ErrorAction SilentlyContinue
    $diag.reachability.gateway = [bool]$gwPing
  }

  $pubPing = Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet -ErrorAction SilentlyContinue
  $diag.reachability.public_ip_ok = [bool]$pubPing

  try {
    $null = Resolve-DnsName -Name "google.com" -DnsOnly -ErrorAction Stop
    $diag.reachability.dns_ok = $true
  } catch {
    $diag.reachability.dns_ok = $false
  }

  return $diag
}
