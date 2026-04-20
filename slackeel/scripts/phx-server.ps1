# Run Slackeel Phoenix from the correct directory (slackeel/server).
# Dev port is fixed in config/dev.exs (:4020).
$ErrorActionPreference = "Stop"
$serverDir = Resolve-Path (Join-Path $PSScriptRoot "..\server")
if (-not (Test-Path (Join-Path $serverDir "mix.exs"))) {
  Write-Error "Expected mix.exs under: $serverDir"
}
Push-Location $serverDir
try {
  mix phx.server
} finally {
  Pop-Location
}
