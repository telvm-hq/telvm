<#
.SYNOPSIS
  Host discovery functions for the ICS subnet.
  Dot-source this file; do not run directly.
#>

function Get-IcsHosts {
  <#
  .SYNOPSIS
    Returns structured list of hosts discovered on ICS-managed Ethernet interfaces.
    Reads from ARP / Get-NetNeighbor; does not perform active scans.
  #>
  param(
    [string] $PrivateAdapterName
  )

  $hosts = @()

  # Determine which interface(s) to query
  $targetAdapters = @()
  if ($PrivateAdapterName) {
    $ad = Get-NetAdapter -Name $PrivateAdapterName -ErrorAction SilentlyContinue
    if ($ad) { $targetAdapters += $ad }
  } else {
    # Find ICS private adapter via COM, or fall back to physical Ethernet with 192.168.137.x
    $icsPrivate = $null
    try {
      $mgr = New-Object -ComObject HNetCfg.HNetShare
      foreach ($c in $mgr.EnumEveryConnection()) {
        $cfg = $mgr.INetSharingConfigurationForINetConnection($c)
        $props = $mgr.NetConnectionProps($c)
        if ($cfg.SharingEnabled -and $cfg.SharingConnectionType -eq 1) {
          $icsPrivate = $props.Name
          break
        }
      }
    } catch { }

    if ($icsPrivate) {
      $ad = Get-NetAdapter -Name $icsPrivate -ErrorAction SilentlyContinue
      if ($ad) { $targetAdapters += $ad }
    }

    # Fallback: any adapter with 192.168.137.x
    if ($targetAdapters.Count -eq 0) {
      $icsIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -like "192.168.137.*" }
      foreach ($ip in $icsIps) {
        $ad = Get-NetAdapter -InterfaceIndex $ip.InterfaceIndex -ErrorAction SilentlyContinue
        if ($ad -and $ad.Status -eq "Up") { $targetAdapters += $ad }
      }
    }
  }

  $now = [DateTime]::UtcNow.ToString('o')

  foreach ($ad in $targetAdapters) {
    $neighbors = Get-NetNeighbor -InterfaceIndex $ad.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object {
        $_.IPAddress -notmatch '^(224\.|239\.|255\.)' -and
        $_.LinkLayerAddress -and
        $_.LinkLayerAddress -ne "00-00-00-00-00-00" -and
        $_.LinkLayerAddress -ne "FF-FF-FF-FF-FF-FF"
      } | Sort-Object IPAddress

    foreach ($n in $neighbors) {
      $hosts += @{
        ip              = $n.IPAddress
        mac             = $n.LinkLayerAddress
        state           = $n.State.ToString()
        interface       = $ad.Name
        interface_index = $ad.InterfaceIndex
        discovered_at   = $now
      }
    }
  }

  return $hosts
}
