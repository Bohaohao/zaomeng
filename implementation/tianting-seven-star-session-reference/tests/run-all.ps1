$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$packageRoot = Split-Path -Parent $PSScriptRoot
$contract = Get-Content -LiteralPath (Join-Path $packageRoot 'package-contract.json') -Raw -Encoding utf8 | ConvertFrom-Json
if ($contract.production_gate -ne 'closed') {
    throw 'package contract must remain closed before tests run'
}

& node (Join-Path $PSScriptRoot 'test-seven-star-session-reference.js')
if ($LASTEXITCODE -ne 0) {
    throw "reference test failed with exit code $LASTEXITCODE"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-execution-boundary.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "execution-boundary test failed with exit code $LASTEXITCODE"
}

Write-Output 'PASS: tianting-seven-star-session-reference run-all'
