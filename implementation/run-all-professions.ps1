param([string]$PnpmPath)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Push-Location $root
try {
    $powangArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\implementation\powang\tests\run-all.ps1')
    if ($PnpmPath) { $powangArgs += @('-PnpmPath', $PnpmPath) }
    & powershell @powangArgs
    if ($LASTEXITCODE -ne 0) { throw 'Powang package failed.' }
    $zhenjieArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\implementation\zhenjie\tests\run-all.ps1')
    if ($PnpmPath) { $zhenjieArgs += @('-PnpmPath', $PnpmPath) }
    & powershell @zhenjieArgs
    if ($LASTEXITCODE -ne 0) { throw 'Zhenjie package failed.' }
    $chimingArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\implementation\chiming\tests\run-all.ps1')
    if ($PnpmPath) { $chimingArgs += @('-PnpmPath', $PnpmPath) }
    & powershell @chimingArgs
    if ($LASTEXITCODE -ne 0) { throw 'Chiming package failed.' }
    $xunlieArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '.\implementation\xunlie\tests\run-all.ps1')
    if ($PnpmPath) { $xunlieArgs += @('-PnpmPath', $PnpmPath) }
    & powershell @xunlieArgs
    if ($LASTEXITCODE -ne 0) { throw 'Xunlie package failed.' }

    $nodePath = (Get-Command node -ErrorAction Stop).Source
    $fengariCli = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'pnpm\store') -Recurse -File -Filter 'lua-cli.js' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$' } |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $fengariCli) { throw 'No cached fengari-node-cli found for profession_common tests.' }
    $output = & $nodePath $fengariCli '.\implementation\profession_common\tests\test_common.lua' 2>&1
    $output | Write-Output
    if ($LASTEXITCODE -ne 0 -or $output -notmatch '^PASS: \d+ common assertions$') {
        throw 'Profession common tests failed.'
    }
    Write-Output 'PASS: C01/C02/C03/C04 cross-profession offline construction packages.'
} finally {
    Pop-Location
}
