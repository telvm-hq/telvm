#Requires -Version 5.1
<#
.SYNOPSIS
  Probes ICMP (optional) and TCP to a LAN Ubuntu host from Windows (Phoenix host).

.PARAMETER TargetIp
  IPv4 of the target machine.

.PARAMETER SshPort
  SSH port to test (default 22).
#>
param(
  [Parameter(Mandatory = $true)]
  [string] $TargetIp,

  [int] $SshPort = 22
)

$ErrorActionPreference = "Continue"
Write-Host "Windows -> LAN probe: $TargetIp tcp/$SshPort"

try {
  $ping = Test-Connection -ComputerName $TargetIp -Count 1 -Quiet -ErrorAction SilentlyContinue
  if ($ping) { Write-Host "ping: ok" } else { Write-Host "ping: failed or blocked (ICMP may be disabled; continuing with TCP)" }
}
catch {
  Write-Host "ping: skipped ($($_.Exception.Message))"
}

try {
  $tcp = Test-NetConnection -ComputerName $TargetIp -Port $SshPort -WarningAction SilentlyContinue
  if ($tcp.TcpTestSucceeded) {
    Write-Host "tcp ${SshPort}: reachable"
    exit 0
  }
  Write-Host "tcp ${SshPort}: NOT reachable" -ForegroundColor Red
  exit 1
}
catch {
  Write-Host "tcp test error: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
