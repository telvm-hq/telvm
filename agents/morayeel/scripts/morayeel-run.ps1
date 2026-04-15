# Run morayeel run.mjs. Default: headless. Use -Headed for a visible Chromium window (local host).
param(
    [switch]$Headed
)
$ErrorActionPreference = "Stop"
$agentRoot = Split-Path -Parent $PSScriptRoot
if ($Headed) {
    $env:MORAYEEL_HEADLESS = "0"
} else {
    if (-not $env:MORAYEEL_HEADLESS) {
        $env:MORAYEEL_HEADLESS = "1"
    }
}
$nodeScript = Join-Path $agentRoot "run.mjs"
& node $nodeScript @args
