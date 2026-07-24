$ErrorActionPreference = 'Stop'

$runner = (Resolve-Path (Join-Path $PSScriptRoot 'run-all.ps1')).Path
$powershell = Join-Path $PSHOME 'powershell.exe'
$assertions = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw $Message }
}

foreach ($variable in @('NODE_OPTIONS', 'NODE_PATH', 'LUA_INIT', 'LUA_PATH_5_3')) {
    $escapedRunner = $runner.Replace("'", "''")
    $command = "`$env:$variable = 'injected'; & '$escapedRunner' -EnvironmentOnly"
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $powershell -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    Assert-True ($exitCode -ne 0) "$variable injection unexpectedly succeeded"
    Assert-True (($output | Out-String) -match 'Untrusted Node or Lua environment variable is set') "$variable rejection was not explicit"
}

$trustOutput = & $powershell -NoProfile -ExecutionPolicy Bypass -File $runner -NodeTrustOnly 2>&1
Assert-True ($LASTEXITCODE -eq 0) "trusted Node boundary failed: $($trustOutput | Out-String)"
Assert-True (($trustOutput | Out-String) -match 'TianTing authority-core inherits the trusted Node/Fengari execution boundary') 'trusted Node/Fengari inheritance was not reported'

Write-Output "PASS: $assertions TianTing authority-core execution-boundary assertions"
