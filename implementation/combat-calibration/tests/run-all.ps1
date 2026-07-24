$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot

& node (Join-Path $PSScriptRoot 'test-calibration.js')
if ($LASTEXITCODE -ne 0) {
    throw "reference test failed with exit code $LASTEXITCODE"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-execution-boundary.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "execution-boundary test failed with exit code $LASTEXITCODE"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot 'evidence-adoption\tests\run-all.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "evidence-adoption test failed with exit code $LASTEXITCODE"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $packageRoot 'external-capture-onboarding\tests\run-all.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "external-capture-onboarding test failed with exit code $LASTEXITCODE"
}

Write-Output 'PASS: combat-calibration run-all'
