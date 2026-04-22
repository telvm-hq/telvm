<#
.SYNOPSIS
  Disk free-space helpers for Slackeel preflight (same conservative heuristic as host-inspect).
  Dot-source from Start-NetworkAgent.ps1; do not run directly.
#>

function Get-PreflightDiskSummary {
  <#
  .SYNOPSIS
    Per-volume PSDrive stats plus min free bytes (the value Pre-flight uses as the bottleneck).
  #>
  $min = [long]::MaxValue
  $volumes = [System.Collections.ArrayList]@()
  Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used } | ForEach-Object {
    $cap = $_.Used + $_.Free
    if ($cap -gt 0) {
      $free = [long]$_.Free
      if ($free -lt $min) { $min = $free }
      $root = $null
      try { $root = $_.Root } catch { }
      [void]$volumes.Add(@{
        name           = $_.Name
        root           = $root
        free_bytes     = $free
        used_bytes     = [long]$_.Used
        capacity_bytes = [long]$cap
      })
    }
  }
  if ($min -eq [long]::MaxValue) { $min = [long]0 }
  return @{
    min_free_bytes = $min
    volumes        = @($volumes)
  }
}

function Get-PreflightMinFreeBytes {
  <#
  .SYNOPSIS
    Minimum free bytes among fixed filesystem volumes (same as disk_summary.min_free_bytes).
  #>
  return (Get-PreflightDiskSummary).min_free_bytes
}
