# Slackeel — quick host + Docker resource peek (Windows). See docs/ROADMAP_HOST_METRICS.md
$ErrorActionPreference = "Continue"
Write-Host ""
Write-Host "=== slackeel host-inspect (Windows) ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "--- Memory (OS) ---"
try {
  $os = Get-CimInstance Win32_OperatingSystem
  $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
  $free = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
  Write-Host "  Total visible (approx GiB): $total"
  Write-Host "  Free physical (approx GiB):  $free"
} catch {
  Write-Host "  (unavailable: $_)"
}

Write-Host ""
Write-Host "--- Fixed disks (used %) ---"
Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used } | ForEach-Object {
  $cap = $_.Used + $_.Free
  if ($cap -le 0) {
    Write-Host ("  {0,-3} (no size reported, skipped)" -f $_.Name)
    return
  }
  $u = [math]::Round(100 * $_.Used / $cap, 1)
  Write-Host ("  {0,-3} {1,6} GiB used of {2,6} GiB  ({3}%)" -f $_.Name, [math]::Round($_.Used/1GB,1), [math]::Round($cap/1GB,1), $u)
}

Write-Host ""
Write-Host "--- Docker ---"
if (Get-Command docker -ErrorAction SilentlyContinue) {
  docker version --format '{{.Server.Version}}' 2>$null | ForEach-Object { Write-Host "  Server version: $_" }
  Write-Host "  docker system df:"
  docker system df 2>&1
} else {
  Write-Host "  docker CLI not on PATH"
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
