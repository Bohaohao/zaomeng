param()

$ErrorActionPreference = 'Stop'

if ($args.Count -ne 0) { throw "Unexpected arguments are not permitted: $($args -join ' ')" }

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$validatorPath = (Resolve-Path (Join-Path $PSScriptRoot 'validate-first-six-hours-package.ps1')).Path
$luaTestPath = (Resolve-Path (Join-Path $PSScriptRoot 'test_growth_runtime.lua')).Path
$growthRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$trustedRunnerPath = (Resolve-Path (Join-Path $projectRoot 'implementation\huaguoshan\tests\run-all.ps1')).Path
$verticalSliceRunnerPath = (Resolve-Path (Join-Path $projectRoot 'implementation\huaguoshan\first-six-hours-vertical-slice\tests\run-all.ps1')).Path
$windowsPowerShellPath = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf)) {
    throw 'Windows PowerShell powershell.exe is required by the trusted offline Lua runner.'
}

Push-Location $projectRoot
try {
    & $windowsPowerShellPath -NoProfile -ExecutionPolicy Bypass -File $validatorPath
    if ($LASTEXITCODE -ne 0) { throw 'first-six-hours package validation failed' }

    $testSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $luaTestPath).Hash
    & $windowsPowerShellPath -NoProfile -ExecutionPolicy Bypass -File $trustedRunnerPath `
        -ExternalLuaTestPath $luaTestPath `
        -ExternalLuaTestSha256 $testSha256 `
        -ExternalLuaPassLine 'PASS: 155 growth runtime assertions' `
        -ExternalPackageRoot $growthRoot
    if ($LASTEXITCODE -ne 0) { throw 'trusted growth Lua runtime regression failed' }

    & $windowsPowerShellPath -NoProfile -ExecutionPolicy Bypass -File $verticalSliceRunnerPath
    if ($LASTEXITCODE -ne 0) { throw 'Huaguoshan vertical-slice bridge regression failed' }

    Write-Output 'PASS: first-six-hours growth offline environment.'
}
finally {
    Pop-Location
}
