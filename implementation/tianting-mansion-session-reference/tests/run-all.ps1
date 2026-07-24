$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-package-boundary.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "package boundary test failed with exit code $LASTEXITCODE"
}

& node (Join-Path $PSScriptRoot 'test-mansion-session.js')
if ($LASTEXITCODE -ne 0) {
    throw "mansion session reference test failed with exit code $LASTEXITCODE"
}

Write-Output 'PASS: TianTing mansion session reference run-all'
