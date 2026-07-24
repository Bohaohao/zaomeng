$ErrorActionPreference = 'Stop'

& node (Join-Path $PSScriptRoot 'test-external-capture-onboarding.js')
if ($LASTEXITCODE -ne 0) {
    throw "external-capture-onboarding reference test failed with exit code $LASTEXITCODE"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-execution-boundary.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "external-capture-onboarding execution-boundary test failed with exit code $LASTEXITCODE"
}

Write-Output 'PASS: P0 external-capture-onboarding run-all'
