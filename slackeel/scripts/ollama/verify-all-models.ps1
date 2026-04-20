# Deterministic manifest-wide Ollama verification (parallel + retries).
# Canonical implementation: Mix task `slackeel.verify_ollama` → `Slackeel.Ollama.VerifyRunner`.
# See docs/INTEGRATION_VERIFY.md
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverDir = Join-Path $scriptDir "..\..\server" | Resolve-Path

Push-Location $serverDir
try {
  mix slackeel.verify_ollama @args
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
