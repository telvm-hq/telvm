# Start only the Ollama container for local Slackeel Phoenix development.
# Run from anywhere; resolves slackeel/ from this script's location.
$ErrorActionPreference = "Stop"
$slackeelRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$composeFile = Join-Path $slackeelRoot "docker-compose.ollama-dev.yml"
if (-not (Test-Path $composeFile)) {
  Write-Error "Missing compose file: $composeFile"
}
Push-Location $slackeelRoot
try {
  docker compose -f docker-compose.ollama-dev.yml up -d
} finally {
  Pop-Location
}
