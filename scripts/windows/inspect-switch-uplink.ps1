#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  L2/L3 / ICS snapshot from a Windows gateway PC: uplink path, switch-facing Ethernet,
  neighbors, and optional probes toward the ICS LAN and Zig agents.

.DESCRIPTION
  Use this when debugging "why does telvm see 0 hosts?" or mapping topology.
  Run 2-3 times after power-on, ping tests, or DHCP renewals; neighbor cache updates over time.

  Sections: host, ICS (COM), adapter inventory, IPv4/DNS, routes, neighbors (raw + filtered),
  telvm listeners, optional ICS subnet + :9100 probes, interpretation hints.

.PARAMETER OutFile
  Append all plain-text lines to this path (UTF-8) in addition to the console.

.PARAMETER ProbeIcsLan
  Ping-scan a slice of the ICS subnet (default .2-.31) and, for responders, try HTTP GET
  http://<ip>:9100/health (Zig telvm-node-agent) with a short timeout.

.PARAMETER IcsScanStart
  Last octet to start ping scan (default 2).

.PARAMETER IcsScanEnd
  Last octet to end ping scan inclusive (default 31). Increase toward 254 for fuller picture.

.PARAMETER IncludeVirtualNeighbors
  Also dump Get-NetNeighbor for virtual Hyper-V/WSL-style adapters (often confuses "switch" reads).

.EXAMPLE
  .\inspect-switch-uplink.ps1 -OutFile .\logs\switch-inspect.txt

.EXAMPLE
  .\inspect-switch-uplink.ps1 -ProbeIcsLan -IcsScanEnd 50
#>
param(
  [string] $OutFile,
  [switch] $ProbeIcsLan,
  [int]    $IcsScanStart = 2,
  [int]    $IcsScanEnd   = 31,
  [switch] $IncludeVirtualNeighbors
)

$ErrorActionPreference = "Continue"
$script:_log = New-Object System.Collections.Generic.List[string]

function Out-Line {
  param(
    [string] $Message,
    [string] $Color = $null
  )
  if ($Color) { Write-Host $Message -ForegroundColor $Color }
  else { Write-Host $Message }
  [void]$script:_log.Add($Message)
}

function Write-Section($Title) {
  Out-Line ""
  Out-Line "=== $Title ===" "Cyan"
}

function Get-IcsInspectStatus {
  $r = @{
    enabled         = $false
    public_adapter  = $null
    private_adapter = $null
    gateway_ip      = $null
    subnet_hint     = $null
    com_error       = $null
  }
  try {
    $mgr = New-Object -ComObject HNetCfg.HNetShare
    foreach ($c in @($mgr.EnumEveryConnection())) {
      $cfg = $mgr.INetSharingConfigurationForINetConnection($c)
      $props = $mgr.NetConnectionProps($c)
      if ($cfg.SharingEnabled) {
        $r.enabled = $true
        if ($cfg.SharingConnectionType -eq 0) { $r.public_adapter = $props.Name }
        elseif ($cfg.SharingConnectionType -eq 1) { $r.private_adapter = $props.Name }
      }
    }
  } catch {
    $r.com_error = $_.Exception.Message
  }
  if ($r.private_adapter) {
    $ad = Get-NetAdapter -Name $r.private_adapter -ErrorAction SilentlyContinue
    if ($ad) {
      $ip = Get-NetIPAddress -InterfaceIndex $ad.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Select-Object -First 1
      if ($ip) {
        $r.gateway_ip = $ip.IPAddress
        $oct = $ip.IPAddress -split '\.'
        $r.subnet_hint = "$($oct[0]).$($oct[1]).$($oct[2]).0/$($ip.PrefixLength)"
      }
    }
  }
  return $r
}

function Test-IsVirtualAdapter($Adapter) {
  $d = $Adapter.InterfaceDescription
  $n = $Adapter.Name
  foreach ($x in @("Hyper-V", "WSL", "Virtual", "VMware", "VirtualBox", "Bluetooth", "Teredo", "Loopback")) {
    if ($d -like "*$x*" -or $n -like "*$x*") { return $true }
  }
  return $false
}

function Get-PhysicalEthernetUp {
  Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    $_.Status -eq "Up" -and $_.PhysicalMediaType -match "802.3" -and -not (Test-IsVirtualAdapter $_)
  } | Sort-Object InterfaceIndex
}

# --- begin output ---

Write-Section "Host"
Out-Line "Computer: $env:COMPUTERNAME"
Out-Line "User:     $env:USERNAME"
Out-Line "UTC:      $([DateTime]::UtcNow.ToString('o'))"
Out-Line "PS:       $($PSVersionTable.PSVersion)"

Write-Section "ICS (Windows COM / Internet Connection Sharing)"
$ics = Get-IcsInspectStatus
if ($ics.com_error) {
  Out-Line "  COM error: $($ics.com_error)" "Yellow"
} elseif (-not $ics.enabled) {
  Out-Line "  ICS not enabled (no shared connection reported by HNetCfg)." "Yellow"
} else {
  Out-Line ("  Enabled: yes")
  Out-Line ("  Public (shared uplink):  {0}" -f $(if ($ics.public_adapter) { $ics.public_adapter } else { "(unknown)" }))
  Out-Line ("  Private (LAN / switch): {0}" -f $(if ($ics.private_adapter) { $ics.private_adapter } else { "(unknown)" }))
  Out-Line ("  Private IPv4 (ICS gateway on LAN): {0}" -f $(if ($ics.gateway_ip) { $ics.gateway_ip } else { "(none)" }))
  Out-Line ("  Subnet hint: {0}" -f $(if ($ics.subnet_hint) { $ics.subnet_hint } else { "(n/a)" }))
}
Out-Line "  Note: telvm Discover uses this private adapter + Get-NetNeighbor (ARP cache); no active subnet scan unless you use -ProbeIcsLan here."

Write-Section "All network adapters (Up) - inventory"
$allUp = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Sort-Object InterfaceIndex
foreach ($a in $allUp) {
  $virt = if (Test-IsVirtualAdapter $a) { "virtual" } else { "physical/other" }
  $media = $a.PhysicalMediaType
  Out-Line ("  [{0}] {1}  /  {2}" -f $a.InterfaceIndex, $a.Name, $a.InterfaceDescription)
  Out-Line ("      Status={0}  Speed={1}  Media={2}  ({3})" -f $a.Status, $a.LinkSpeed, $media, $virt)
}

Write-Section "IPv4 + gateway + DNS (Up interfaces)"
Get-NetIPConfiguration -ErrorAction SilentlyContinue |
  Where-Object { $_.NetAdapter.Status -eq "Up" } |
  ForEach-Object {
    $na = $_.NetAdapter
    Out-Line ""
    Out-Line ("Interface: {0} ({1})  ifIndex={2}" -f $_.InterfaceAlias, $na.InterfaceDescription, $na.InterfaceIndex)
    foreach ($addr in $_.IPv4Address) {
      if ($addr.IPAddress) {
        $dhcp = if ($addr.PrefixOrigin -eq "Dhcp" -or $addr.SuffixOrigin -eq "Dhcp") { "DHCP" } else { "static/other" }
        Out-Line ("  IPv4: {0}/{1}  ({2})" -f $addr.IPAddress, $addr.PrefixLength, $dhcp)
      }
    }
    $gw = $_.IPv4DefaultGateway
    if ($gw) {
      Out-Line ("  Gateway on this if: {0}" -f $gw.NextHop) "Green"
    } else {
      Out-Line "  Gateway on this if: (none - normal for ICS private side; default route is usually Wi-Fi)"
    }
    $dns = ($_.DnsServer | Where-Object { $_.ServerAddresses } | ForEach-Object { $_.ServerAddresses }) | Select-Object -Unique
    if ($dns) { Out-Line ("  DNS: {0}" -f ($dns -join ", ")) }
  }

Write-Section "IPv4 routes (default + RFC1918-ish + on-link ICS)"
$routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue)
$defs = $routes | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } | Sort-Object RouteMetric
foreach ($r in $defs) {
  $alias = (Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue).Name
  Out-Line ("DEFAULT  {0} -> if {1} ({2}) metric {3}" -f $r.NextHop, $r.InterfaceIndex, $alias, $r.RouteMetric)
}
$interesting = $routes | Where-Object {
  $p = $_.DestinationPrefix
  $p -match '^192\.168\.' -or $p -match '^10\.' -or $p -match '^172\.(1[6-9]|2[0-9]|3[0-1])\.' -or
  $p -match '^169\.254\.' -or $p -eq "224.0.0.0/4"
} | Sort-Object DestinationPrefix, RouteMetric
foreach ($r in $interesting | Select-Object -First 40) {
  $alias = (Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue).Name
  Out-Line ("  {0,-18} nh={1,-15} if={2} {3}" -f $r.DestinationPrefix, $(if ($r.NextHop) { $r.NextHop } else { "on-link" }), $r.InterfaceIndex, $alias)
}
if ($interesting.Count -gt 40) { Out-Line "  ... ($($interesting.Count) total matching; truncated to 40)" "DarkGray" }

Write-Section "Physical Ethernet (switch / ICS LAN side) - Get-NetNeighbor"
$physEth = Get-PhysicalEthernetUp
if (-not $physEth) {
  Out-Line "No Up non-virtual 802.3 adapters. Cables, driver, or only virtual NICs?" "Yellow"
} else {
  foreach ($a in $physEth) {
    Out-Line ""
    Out-Line "Adapter: $($a.Name)  ifIndex=$($a.InterfaceIndex)"
    $allN = @(Get-NetNeighbor -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(224\.|239\.|255\.)' } |
        Sort-Object IPAddress)
    if (-not $allN) {
      Out-Line "  (no IPv4 neighbor rows - ARP empty for this interface)" "Yellow"
    } else {
      Out-Line "  RAW (all states):"
      foreach ($n in $allN) {
        Out-Line ("    {0,-16}  {1,-17}  State={2}" -f $n.IPAddress, $n.LinkLayerAddress, $n.State)
      }
      $good = $allN | Where-Object {
        $_.State -match "Reachable|Stale|Delay|Probe|Permanent" -and
        $_.LinkLayerAddress -and
        $_.LinkLayerAddress -notmatch '^(00-00-00-00-00-00|FF-FF-FF-FF-FF-FF)$'
      }
      Out-Line "  FILTERED (likely real peers):"
      if (-not $good) {
        Out-Line "    (none - no usable L2 entries yet; power on downstream PCs, ping them from this host, or fix VLAN/cable)" "Yellow"
      } else {
        foreach ($n in $good) {
          Out-Line ("    {0,-16}  {1,-17}  {2}" -f $n.IPAddress, $n.LinkLayerAddress, $n.State) "Green"
        }
      }
    }
  }
}

if ($IncludeVirtualNeighbors) {
  Write-Section "Virtual adapters - Get-NetNeighbor (WSL/Hyper-V etc.)"
  $virtAdapters = Get-NetAdapter -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -eq "Up" -and (Test-IsVirtualAdapter $_) }
  foreach ($a in $virtAdapters) {
    Out-Line ""
    Out-Line "Adapter: $($a.Name)  ifIndex=$($a.InterfaceIndex)"
    $allN = @(Get-NetNeighbor -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(224\.|239\.|255\.)' } |
        Sort-Object IPAddress)
    foreach ($n in $allN) {
      Out-Line ("  {0,-16}  {1,-17}  State={2}" -f $n.IPAddress, $n.LinkLayerAddress, $n.State)
    }
  }
}

Write-Section "Windows Firewall (ICS private interface)"
$privateIfIndex = if ($ics.private_adapter) {
  $pa = Get-NetAdapter -Name $ics.private_adapter -ErrorAction SilentlyContinue
  if ($pa) { $pa.InterfaceIndex } else { $null }
} else { $null }

$fwProfiles = @("Domain", "Private", "Public")
foreach ($prof in $fwProfiles) {
  $fw = Get-NetFirewallProfile -Name $prof -ErrorAction SilentlyContinue
  if ($fw) {
    $state = if ($fw.Enabled) { "ON" } else { "OFF" }
    Out-Line ("  Profile {0}: {1}" -f $prof, $state)
  }
}

$dhcpRules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -match "DHCP" -and $_.Direction -eq "Inbound" })
if ($dhcpRules) {
  foreach ($r in $dhcpRules) {
    $action = if ($r.Enabled -eq "True" -or $r.Enabled -eq $true) { "ENABLED" } else { "disabled" }
    Out-Line ("  DHCP rule: {0}  Action={1}  {2}" -f $r.DisplayName, $r.Action, $action)
  }
} else {
  Out-Line "  No inbound DHCP firewall rules found." "Yellow"
}

$icmpRules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -match "ICMPv4" -and $_.Direction -eq "Inbound" })
if ($icmpRules) {
  foreach ($r in $icmpRules | Select-Object -First 5) {
    $action = if ($r.Enabled -eq "True" -or $r.Enabled -eq $true) { "ENABLED" } else { "disabled" }
    Out-Line ("  ICMP rule: {0}  Action={1}  {2}" -f $r.DisplayName, $r.Action, $action)
  }
} else {
  Out-Line "  No inbound ICMPv4 rules found - ping from LAN hosts may fail." "Yellow"
}

Write-Section "telvm-related listeners (this PC)"
$listen9225 = @(Get-NetTCPConnection -LocalPort 9225 -State Listen -ErrorAction SilentlyContinue)
if ($listen9225) {
  foreach ($c in $listen9225) {
    Out-Line ("  Port 9225 LISTEN  PID={0}  Local={1}" -f $c.OwningProcess, $c.LocalAddress) "Green"
  }
} else {
  Out-Line "  Port 9225 not listening - telvm-network-agent not running here?" "Yellow"
}
$listen9100 = @(Get-NetTCPConnection -LocalPort 9100 -State Listen -ErrorAction SilentlyContinue)
if ($listen9100) {
  foreach ($c in $listen9100) {
    Out-Line ("  Port 9100 LISTEN  PID={0}" -f $c.OwningProcess) "Green"
  }
} else {
  Out-Line "  Port 9100 not listening on this PC (expected if Zig agent runs on cluster nodes, not gateway)."
}

Write-Section "Quick reachability (uplink)"
$firstGw = ($defs | Select-Object -First 1).NextHop
if ($firstGw) {
  Out-Line "Ping default gateway $firstGw ..."
  Test-Connection -ComputerName $firstGw -Count 2 -ErrorAction SilentlyContinue |
    ForEach-Object { Out-Line ("  Reply from {0} time={1}ms" -f $_.Address, $_.ResponseTime) }
} else {
  Out-Line "No default IPv4 route."
}
Out-Line "Ping 1.1.1.1 ..."
$pub = Test-Connection -ComputerName 1.1.1.1 -Count 2 -ErrorAction SilentlyContinue
if ($pub) {
  $pub | ForEach-Object { Out-Line ("  Reply from {0} time={1}ms" -f $_.Address, $_.ResponseTime) }
} else {
  Out-Line "  No reply (ICMP blocked or no route)." "Yellow"
}
Out-Line "DNS: google.com"
try {
  $r = Resolve-DnsName -Name google.com -DnsOnly -ErrorAction Stop | Select-Object -First 1
  Out-Line ("  OK: {0}" -f $r.Name) "Green"
} catch {
  Out-Line ("  Failed: {0}" -f $_.Exception.Message) "Yellow"
}

if ($ProbeIcsLan) {
  Write-Section "Probe ICS LAN (ping slice + Zig :9100/health)"
  $base3 = $null
  if ($ics.gateway_ip) {
    $oct = $ics.gateway_ip -split '\.'
    $base3 = "$($oct[0]).$($oct[1]).$($oct[2])"
  } elseif (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like "192.168.137.*" }) {
    $base3 = "192.168.137"
  } else {
    Out-Line "  Cannot infer ICS /24 (no private ICS IP and no 192.168.137.* on host). Set ICS or add address." "Yellow"
    $base3 = $null
  }
  if ($base3) {
    if ($IcsScanEnd -lt $IcsScanStart) {
      Out-Line "  IcsScanEnd < IcsScanStart; swap or fix parameters." "Yellow"
    } else {
      Out-Line "  Scanning $base3.$IcsScanStart .. $base3.$IcsScanEnd (ICMP then TCP 9100 HTTP) ..."
      $pinger = New-Object System.Net.NetworkInformation.Ping
      try {
      for ($last = $IcsScanStart; $last -le $IcsScanEnd; $last++) {
        $ip = "$base3.$last"
        if ($ip -eq $ics.gateway_ip) {
          Out-Line "  $ip  (skip - this gateway host)"
          continue
        }
        try {
          $pr = $pinger.Send($ip, 1000)
          $okPing = ($pr.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
          $rtt = if ($okPing) { $pr.RoundtripTime } else { $null }
        } catch {
          $okPing = $false
          $rtt = $null
        }
        if (-not $okPing) {
          Out-Line ("  {0,-16}  ping: no reply" -f $ip) "DarkGray"
          continue
        }
        Out-Line ("  {0,-16}  ping: OK ({1} ms)" -f $ip, $rtt) "Green"
        try {
          $u = "http://${ip}:9100/health"
          $resp = Invoke-WebRequest -Uri $u -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
          $snippet = if ($resp.Content.Length -gt 120) { $resp.Content.Substring(0, 120) + "..." } else { $resp.Content }
          Out-Line ("        Zig HTTP {0} -> {1}  body: {2}" -f $u, $resp.StatusCode, $snippet) "Green"
        } catch {
          Out-Line ("        Zig HTTP :9100/health  no/failed ({0})" -f $_.Exception.Message) "DarkGray"
        }
      }
      } finally {
        if ($pinger) { $pinger.Dispose() }
      }
    }
  }
}

Write-Section "Interpretation (best-effort)"
Out-Line "* Default route via Wi-Fi to 192.168.40.1 = normal for ICS: shared internet is public side; Ethernet 192.168.137.1 is ICS private gateway."
Out-Line "* If FILTERED neighbors on physical Ethernet is empty, telvm will show 0 LAN hosts until Windows learns MACs (traffic on that segment)."
Out-Line "* 169.254.x / APIPA or 00-00-00-00-00-00 rows are usually noise, not downstream PCs."
Out-Line "* vEthernet (WSL) neighbors are VMs on this PC, not machines on your unmanaged switch."
Out-Line "* Use -ProbeIcsLan to actively ping a range and test Zig :9100 on responders."
Out-Line "* Run script again after powering on the 3 configured + 2 pending cluster PCs and after a ping from this host to their IPs."

Out-Line ""
Out-Line "Done." "DarkGray"

if ($OutFile) {
  $dir = Split-Path -Parent $OutFile
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $script:_log | Set-Content -LiteralPath $OutFile -Encoding UTF8
  Out-Line "Wrote log: $OutFile" "Cyan"
}
