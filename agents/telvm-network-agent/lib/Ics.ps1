<#
.SYNOPSIS
  ICS (Internet Connection Sharing) management functions.
  Dot-source this file; do not run directly.
#>

function Get-ComSharingManager {
  New-Object -ComObject HNetCfg.HNetShare
}

function Get-ComConnections([object] $Manager) {
  $list = New-Object System.Collections.Generic.List[object]
  try {
    foreach ($c in $Manager.EnumEveryConnection()) {
      [void]$list.Add($c)
    }
  } catch {
    $enum = $Manager.EnumEveryConnection()
    if ($null -ne $enum) {
      foreach ($c in @($enum)) { [void]$list.Add($c) }
    }
  }
  return $list
}

function Get-ComConnectionByAdapterName([object] $Manager, [string] $AdapterName) {
  foreach ($c in (Get-ComConnections $Manager)) {
    $props = $Manager.NetConnectionProps($c)
    if ($props.Name -eq $AdapterName) { return $c }
  }
  return $null
}

function Get-PhysicalEthernetCandidates {
  $exclude = @("Hyper-V", "WSL", "Virtual", "VMware", "VirtualBox", "Bluetooth", "Loopback", "Teredo")
  Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    $_.Status -eq "Up" -and $_.PhysicalMediaType -match "802.3"
  } | Where-Object {
    $d = $_.InterfaceDescription
    $hit = $false
    foreach ($x in $exclude) { if ($d -like "*$x*") { $hit = $true; break } }
    -not $hit
  } | Sort-Object InterfaceIndex
}

function Get-DefaultRouteAdapter {
  $routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } |
      Sort-Object RouteMetric)
  if ($routes.Count -eq 0) { return $null }
  Get-NetAdapter -InterfaceIndex $routes[0].InterfaceIndex -ErrorAction SilentlyContinue
}

function Get-IcsStatus {
  <#
  .SYNOPSIS Returns structured ICS state as a hashtable.
  #>
  $result = @{
    enabled        = $false
    public_adapter = $null
    private_adapter = $null
    subnet         = $null
    gateway_ip     = $null
    error          = $null
  }

  try {
    $mgr = Get-ComSharingManager
    foreach ($c in (Get-ComConnections $mgr)) {
      $cfg = $mgr.INetSharingConfigurationForINetConnection($c)
      $props = $mgr.NetConnectionProps($c)
      if ($cfg.SharingEnabled) {
        $result.enabled = $true
        # SharingConnectionType: 0 = public, 1 = private
        if ($cfg.SharingConnectionType -eq 0) {
          $result.public_adapter = $props.Name
        } elseif ($cfg.SharingConnectionType -eq 1) {
          $result.private_adapter = $props.Name
        }
      }
    }
  } catch {
    $result.error = $_.Exception.Message
    return $result
  }

  if ($result.private_adapter) {
    $ad = Get-NetAdapter -Name $result.private_adapter -ErrorAction SilentlyContinue
    if ($ad) {
      $ip = Get-NetIPAddress -InterfaceIndex $ad.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($ip) {
        $result.gateway_ip = $ip.IPAddress
        $oct = $ip.IPAddress -split '\.'
        $result.subnet = "$($oct[0]).$($oct[1]).$($oct[2]).0/$($ip.PrefixLength)"
      }
    }
  }

  return $result
}

function Enable-Ics {
  param(
    [string] $PublicName,
    [string] $PrivateName
  )

  $svc = Get-Service -Name SharedAccess -ErrorAction SilentlyContinue
  if ($svc) {
    if ($svc.StartType -eq "Disabled") { Set-Service -Name SharedAccess -StartupType Manual }
    if ($svc.Status -ne "Running") { Start-Service -Name SharedAccess }
  }

  # IP forwarding
  $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
  if (Test-Path $regPath) {
    $cur = Get-ItemProperty -Path $regPath -Name IPEnableRouter -ErrorAction SilentlyContinue
    if ($cur.IPEnableRouter -ne 1) {
      Set-ItemProperty -Path $regPath -Name IPEnableRouter -Value 1 -Type DWord
    }
  }

  # Firewall rules
  foreach ($g in @("Internet Connection Sharing (ICS)", "Core Networking")) {
    try {
      Get-NetFirewallRule -DisplayGroup $g -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Enabled } |
        Enable-NetFirewallRule -ErrorAction SilentlyContinue
    } catch { }
  }

  if (-not $PublicName) {
    $pub = Get-DefaultRouteAdapter
    if (-not $pub) { throw "Cannot determine default-route adapter." }
    $PublicName = $pub.Name
  }

  if (-not $PrivateName) {
    $cands = @(Get-PhysicalEthernetCandidates)
    $pubAd = Get-NetAdapter -Name $PublicName -ErrorAction SilentlyContinue
    $prv = $cands | Where-Object { $_.InterfaceIndex -ne $pubAd.InterfaceIndex } | Select-Object -First 1
    if (-not $prv) { $prv = $cands | Select-Object -First 1 }
    if (-not $prv) { throw "No physical Ethernet adapter found for private side." }
    $PrivateName = $prv.Name
  }

  $mgr = Get-ComSharingManager

  # Disable existing sharing first
  foreach ($c in (Get-ComConnections $mgr)) {
    $cfg = $mgr.INetSharingConfigurationForINetConnection($c)
    if ($cfg.SharingEnabled) { $cfg.DisableSharing() }
  }

  $pub = Get-ComConnectionByAdapterName -Manager $mgr -AdapterName $PublicName
  $prv = Get-ComConnectionByAdapterName -Manager $mgr -AdapterName $PrivateName
  if (-not $pub) { throw "Public adapter '$PublicName' not found in COM connections." }
  if (-not $prv) { throw "Private adapter '$PrivateName' not found in COM connections." }

  $pubCfg = $mgr.INetSharingConfigurationForINetConnection($pub)
  $prvCfg = $mgr.INetSharingConfigurationForINetConnection($prv)
  $pubCfg.EnableSharing(0)  # ICSSHARINGTYPE_PUBLIC
  $prvCfg.EnableSharing(1)  # ICSSHARINGTYPE_PRIVATE

  return @{ ok = $true; public_adapter = $PublicName; private_adapter = $PrivateName }
}

function Disable-Ics {
  $mgr = Get-ComSharingManager
  foreach ($c in (Get-ComConnections $mgr)) {
    $cfg = $mgr.INetSharingConfigurationForINetConnection($c)
    if ($cfg.SharingEnabled) { $cfg.DisableSharing() }
  }
  return @{ ok = $true }
}
