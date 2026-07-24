[CmdletBinding()]
param(
    [switch]$EnvironmentOnly,
    [switch]$NodeTrustOnly
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$untrustedVariables = @(
    Get-ChildItem Env: |
        Where-Object { $_.Name -match '^(NODE_|LUA_)' } |
        Select-Object -ExpandProperty Name
)
if ($untrustedVariables.Count -gt 0) {
    throw "Untrusted Node or Lua environment variable is set: $($untrustedVariables -join ', ')"
}
if ($EnvironmentOnly) {
    Write-Output 'PASS: TianTing authority-core execution boundary environment is clean.'
    return
}

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workspaceRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$trustedRunner = Join-Path $workspaceRoot 'implementation\huaguoshan\tests\run-all.ps1'
$testPath = Join-Path $packageRoot 'tests\test_tianting_authority_core.lua'
if (-not (Test-Path -LiteralPath $trustedRunner -PathType Leaf)) {
    throw 'Trusted Node/Fengari runner is unavailable.'
}
if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
    throw 'Authority-core Lua regression fixture is unavailable.'
}

$powershell = Join-Path $PSHOME 'powershell.exe'
if ($NodeTrustOnly) {
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $trustedRunner -NodeIntegritySelfTestOnly
    if ($LASTEXITCODE -ne 0) { throw 'Trusted Node identity gate failed.' }
    Write-Output 'PASS: TianTing authority-core inherits the trusted Node/Fengari execution boundary.'
    return
}

$testHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $testPath).Hash
Push-Location $workspaceRoot
try {
    # The Lua fixture names only package-local modules; the wrapper fixes the
    # repository working directory before calling the inherited trusted runner.
    # This is a deterministic test-path allowlist, not a Node module lookup path.
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $trustedRunner `
        -ExternalLuaTestPath $testPath `
        -ExternalLuaTestSha256 $testHash `
        -ExternalLuaPassLine 'PASS: 70 TianTing authority-core assertions' `
        -ExternalPackageRoot $packageRoot
    if ($LASTEXITCODE -ne 0) { throw 'Trusted Node/Fengari authority-core regression failed.' }
}
finally {
    Pop-Location
}
Write-Output 'PASS: TianTing authority vertical-slice offline package.'
