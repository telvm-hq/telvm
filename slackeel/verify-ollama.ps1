# Run mix slackeel.verify_ollama from the Phoenix app (slackeel/server).
# Usage from slackeel/:  .\verify-ollama.ps1 [--model "qwen2.5:0.5b"] ...
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $root "server")
mix slackeel.verify_ollama @args
exit $LASTEXITCODE
