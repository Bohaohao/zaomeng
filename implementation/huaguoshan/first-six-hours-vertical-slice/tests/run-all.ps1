param()

$ErrorActionPreference = 'Stop'

if ($args.Count -ne 0) { throw "Unexpected arguments are not permitted: $($args -join ' ')" }

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$validatorPath = (Resolve-Path (Join-Path $packageRoot 'validate-first-six-hours-vertical-slice.ps1')).Path
$luaTestPath = (Resolve-Path (Join-Path $PSScriptRoot 'test_tide_trace_growth_bridge.lua')).Path
$trustedRunnerPath = (Resolve-Path (Join-Path $projectRoot 'implementation\huaguoshan\tests\run-all.ps1')).Path
$windowsPowerShellPath = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf)) {
    throw 'Windows PowerShell powershell.exe is required by the trusted offline Lua runner.'
}

Push-Location $projectRoot
try {
    & $windowsPowerShellPath -NoProfile -ExecutionPolicy Bypass -File $validatorPath
    if ($LASTEXITCODE -ne 0) { throw 'first-six-hours vertical-slice contract validation failed' }

    $testSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $luaTestPath).Hash
    & $windowsPowerShellPath -NoProfile -ExecutionPolicy Bypass -File $trustedRunnerPath `
        -ExternalLuaTestPath $luaTestPath `
        -ExternalLuaTestSha256 $testSha256 `
        -ExternalLuaPassLine 'PASS: 81 tide trace growth bridge assertions' `
        -ExternalPackageRoot $packageRoot
    if ($LASTEXITCODE -ne 0) { throw 'trusted Tide Trace growth bridge regression failed' }

    Write-Output 'PASS: Huaguoshan first-six-hours vertical slice offline bridge.'
}
finally {
    Pop-Location
}
