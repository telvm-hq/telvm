# Minimal Ollama HTTP smoke: GET /v1/models + POST /v1/chat/completions.
# See docs/OLLAMA.md
$ErrorActionPreference = "Stop"

$base = if ($env:OLLAMA_SMOKE_BASE) { $env:OLLAMA_SMOKE_BASE.Trim() } else { "http://127.0.0.1:11434/v1" }
$model = if ($env:OLLAMA_SMOKE_MODEL) { $env:OLLAMA_SMOKE_MODEL.Trim() } else { "qwen2.5:0.5b" }

if (-not $base.EndsWith("/v1")) {
  $base = $base.TrimEnd("/") + "/v1"
}

Write-Host "slackeel: Ollama smoke"
Write-Host "  base:  $base"
Write-Host "  model: $model"
Write-Host ""

Write-Host "Step 1: GET $base/models"
try {
  $null = Invoke-RestMethod -Uri "$base/models" -Method Get -TimeoutSec 30
} catch {
  Write-Host "  FAIL: cannot reach $base" -ForegroundColor Red
  Write-Host ""
  Write-Host "From repo root:  docker compose up -d ollama" -ForegroundColor Yellow
  Write-Host "Then:            docker compose up ollama_pull" -ForegroundColor Yellow
  Write-Host "If Ollama runs elsewhere, set OLLAMA_SMOKE_BASE (must end with /v1)." -ForegroundColor Yellow
  exit 1
}
Write-Host "  OK"

Write-Host "Step 2: POST $base/chat/completions"
$bodyObj = @{
  model    = $model
  messages = @(@{ role = "user"; content = "ping" })
  stream   = $false
}
$bodyJson = $bodyObj | ConvertTo-Json -Depth 6 -Compress
try {
  $resp = Invoke-RestMethod -Uri "$base/chat/completions" -Method Post -Body $bodyJson -ContentType "application/json; charset=utf-8" -TimeoutSec 120
} catch {
  Write-Host "FAIL: chat completion (model pulled? try: docker compose up ollama_pull or ollama pull $model)" -ForegroundColor Red
  throw
}

if (-not $resp.choices) {
  Write-Host "FAIL: unexpected JSON shape" -ForegroundColor Red
  $resp | ConvertTo-Json -Depth 6
  exit 1
}
Write-Host "  OK (response contains choices)"

Write-Host ""
Write-Host "slackeel: Ollama smoke PASSED"
