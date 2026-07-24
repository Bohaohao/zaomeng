$ErrorActionPreference = 'Stop'

& node (Join-Path $PSScriptRoot 'test-evidence-adoption.js')
if ($LASTEXITCODE -ne 0) {
    throw "evidence-adoption reference test failed with exit code $LASTEXITCODE"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-execution-boundary.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "evidence-adoption execution-boundary test failed with exit code $LASTEXITCODE"
}

Write-Output 'PASS: P0 evidence-adoption run-all'
