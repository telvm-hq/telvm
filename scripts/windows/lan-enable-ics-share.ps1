#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Enable Windows Internet Connection Sharing (ICS): share this PC's internet uplink with a peer on Ethernet.

.DESCRIPTION
  Uses the same HNetCfg COM API as the "Sharing" tab on a network adapter (not netsh).
  Typical lab: Wi-Fi (or another NIC) has internet; a second physical Ethernet NIC is a direct cable to Ubuntu/Linux.

  After ICS, Windows usually assigns itself 192.168.137.1 on the shared Ethernet and DHCPs 192.168.137.0/24 to the peer.
  A peer configured only for 10.10.10.x + gateway 10.10.10.1 will not route until you use DHCP or a 192.168.137.x + gateway 192.168.137.1 layout on that link.

  Run from Windows PowerShell 5.1 (powershell.exe). PowerShell 7 may not load HNetCfg COM reliably.

.EXAMPLE
  .\lan-enable-ics-share.ps1

.EXAMPLE
  .\lan-enable-ics-share.ps1 -ListConnectionNames

.EXAMPLE
  .\lan-enable-ics-share.ps1 -PublicAdapterName "Wi-Fi" -PrivateAdapterName "Ethernet"

.EXAMPLE
  .\lan-enable-ics-share.ps1 -Disable
#>
param(
  [string] $PublicAdapterName,

  [string] $PrivateAdapterName,

  [switch] $ListConnectionNames,

  [switch] $Disable
)

$ErrorActionPreference = "Stop"

function Write-Section($Title) {
  Write-Host ""
  Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Get-PhysicalEthernetCandidates {
  $exclude = @(
    "Hyper-V", "WSL", "Virtual", "VMware", "VirtualBox", "Bluetooth", "Loopback",
    "Teredo"
  )
  Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
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

function Get-DefaultRouteAdapter {
  $routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } |
      Sort-Object RouteMetric)
  if ($routes.Count -eq 0) { return $null }
  $r = $routes[0]
  Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue
}

function Get-ComSharingManager {
  try {
    return New-Object -ComObject HNetCfg.HNetShare
  } catch {
    Write-Host "Failed to create COM object HNetCfg.HNetShare: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Try: regsvr32 /s hnetcfg.dll   (as Administrator), then re-run." -ForegroundColor Yellow
    Write-Host "Use Windows PowerShell 5.1 (powershell.exe), not necessarily pwsh." -ForegroundColor Yellow
    throw
  }
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

function Get-ComConnectionDisplayNames([object] $Manager) {
  $names = New-Object System.Collections.Generic.List[string]
  foreach ($c in (Get-ComConnections $Manager)) {
    $props = $Manager.NetConnectionProps($c)
    [void]$names.Add($props.Name)
  }
  return $names
}

function Disable-AllComSharing([object] $Manager) {
  foreach ($c in (Get-ComConnections $Manager)) {
    $cfg = $Manager.INetSharingConfigurationForINetConnection($c)
    if ($cfg.SharingEnabled) {
      $cfg.DisableSharing()
    }
  }
}

function Enable-IcsPair([object] $Manager, [string] $PublicName, [string] $PrivateName) {
  $pub = Get-ComConnectionByAdapterName -Manager $Manager -AdapterName $PublicName
  $prv = Get-ComConnectionByAdapterName -Manager $Manager -AdapterName $PrivateName
  if (-not $pub) {
    throw "Public/uplink adapter not found in Network Connections list: '$PublicName'. Use -ListConnectionNames."
  }
  if (-not $prv) {
    throw "Private/Ethernet adapter not found in Network Connections list: '$PrivateName'. Use -ListConnectionNames."
  }
  if ($PublicName -eq $PrivateName) {
    throw "Public and private adapter names must differ."
  }

  $pubCfg = $Manager.INetSharingConfigurationForINetConnection($pub)
  $prvCfg = $Manager.INetSharingConfigurationForINetConnection($prv)

  if ($pubCfg.SharingEnabled) { $pubCfg.DisableSharing() }
  if ($prvCfg.SharingEnabled) { $prvCfg.DisableSharing() }

  # ICSSHARINGTYPE_PUBLIC = 0, ICSSHARINGTYPE_PRIVATE = 1
  $pubCfg.EnableSharing(0)
  $prvCfg.EnableSharing(1)
}

function Ensure-SharedAccessService {
  $svc = Get-Service -Name SharedAccess -ErrorAction SilentlyContinue
  if (-not $svc) {
    Write-Host "SharedAccess service not found; ICS may still apply on some builds." -ForegroundColor Yellow
    return
  }
  if ($svc.StartType -eq "Disabled") {
    Set-Service -Name SharedAccess -StartupType Manual
  }
  if ($svc.Status -ne "Running") {
    Start-Service -Name SharedAccess
  }
}

function Enable-IcsFirewallRules {
  $groups = @(
    "Internet Connection Sharing (ICS)",
    "Core Networking"
  )
  foreach ($g in $groups) {
    try {
      Get-NetFirewallRule -DisplayGroup $g -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Enabled } |
        Enable-NetFirewallRule -ErrorAction SilentlyContinue
    } catch { }
  }
}

function Ensure-IpForwardingRegistry {
  $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
  if (-not (Test-Path $path)) { return }
  $cur = Get-ItemProperty -Path $path -Name IPEnableRouter -ErrorAction SilentlyContinue
  if ($cur.IPEnableRouter -ne 1) {
    Set-ItemProperty -Path $path -Name IPEnableRouter -Value 1 -Type DWord
    Write-Host "Set IPEnableRouter=1 under Tcpip\Parameters (reboot may be required for some stacks)." -ForegroundColor Yellow
  }
}

# --- main ---

Write-Section "Host"
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "Use Windows PowerShell 5.1 when possible (ICS COM)."

$mgr = Get-ComSharingManager

if ($ListConnectionNames) {
  Write-Section "Network connection names (use these for -PublicAdapterName / -PrivateAdapterName)"
  $i = 0
  foreach ($n in (Get-ComConnectionDisplayNames $mgr)) {
    $i++
    Write-Host ("  {0,-3} {1}" -f $i, $n)
  }
  Write-Host ""
  Write-Host "Done (list only)."
  exit 0
}

if ($Disable) {
  Write-Section "Disabling ICS on all connections (COM)"
  Disable-AllComSharing -Manager $mgr
  Write-Host "ICS disabled." -ForegroundColor Green
  exit 0
}

$publicAd = $null
$privateAd = $null

if (-not [string]::IsNullOrWhiteSpace($PublicAdapterName)) {
  $publicAd = Get-NetAdapter -Name $PublicAdapterName -ErrorAction SilentlyContinue
  if (-not $publicAd) { throw "No Get-NetAdapter match for -PublicAdapterName '$PublicAdapterName'." }
} else {
  $publicAd = Get-DefaultRouteAdapter
  if (-not $publicAd) { throw "Could not determine default-route adapter. Pass -PublicAdapterName explicitly." }
}

if (-not [string]::IsNullOrWhiteSpace($PrivateAdapterName)) {
  $privateAd = Get-NetAdapter -Name $PrivateAdapterName -ErrorAction SilentlyContinue
  if (-not $privateAd) { throw "No Get-NetAdapter match for -PrivateAdapterName '$PrivateAdapterName'." }
} else {
  $cands = @(Get-PhysicalEthernetCandidates)
  $privateAd = $cands | Where-Object { $_.InterfaceIndex -ne $publicAd.InterfaceIndex } | Select-Object -First 1
  if (-not $privateAd) {
    $privateAd = $cands | Select-Object -First 1
  }
  if (-not $privateAd) {
    throw "No Up physical Ethernet adapter found. Plug in the cable and install the driver, or pass -PrivateAdapterName."
  }
  if ($privateAd.InterfaceIndex -eq $publicAd.InterfaceIndex) {
    throw "Public and private resolve to the same adapter ($($publicAd.Name)). Specify -PrivateAdapterName for the NIC that goes to the peer (second Ethernet, etc.)."
  }
}

$publicName = $publicAd.Name
$privateName = $privateAd.Name

Write-Section "Adapters"
Write-Host "Public  (internet uplink): $publicName  ($($publicAd.InterfaceDescription))"
Write-Host "Private (peer on wire):    $privateName  ($($privateAd.InterfaceDescription))"

Ensure-IpForwardingRegistry
Ensure-SharedAccessService
Enable-IcsFirewallRules

Write-Section "Applying ICS (COM)"
try {
  Enable-IcsPair -Manager $mgr -PublicName $publicName -PrivateName $privateName
} catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host "If names mismatch the GUI, run: .\lan-enable-ics-share.ps1 -ListConnectionNames" -ForegroundColor Yellow
  exit 1
}

Write-Host "ICS enabled: '$publicName' shared to '$privateName'." -ForegroundColor Green

Write-Section "Peer (Ubuntu) reminder"
Write-Host "On the Ethernet link to this PC, use DHCP or static 192.168.137.x/24, gateway 192.168.137.1."
Write-Host "Then: ping 192.168.137.1 ; ping 1.1.1.1 ; sudo apt update"
Write-Host ""
Write-Host "Done."
