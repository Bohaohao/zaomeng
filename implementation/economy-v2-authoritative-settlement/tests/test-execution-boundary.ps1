$ErrorActionPreference = 'Stop'

$runner = (Resolve-Path (Join-Path $PSScriptRoot 'run-all.ps1')).Path
$powershell = Join-Path $PSHOME 'powershell.exe'
$assertions = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw $Message }
}

function Invoke-ExpectedEnvironmentFailure {
    param([string]$VariableName)

    $escapedRunner = $runner.Replace("'", "''")
    $command = "`$env:$VariableName = 'injected'; & '$escapedRunner' -EnvironmentOnly"
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $powershell -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    Assert-True -Condition ($exitCode -ne 0) -Message "$VariableName injection unexpectedly succeeded"
    Assert-True -Condition (($output | Out-String) -match 'Untrusted (Node|Lua) environment variable is set') -Message "$VariableName rejection was not explicit"
}

foreach ($variable in @('NODE_OPTIONS', 'NODE_PATH', 'LUA_INIT', 'LUA_PATH_5_3')) {
    Invoke-ExpectedEnvironmentFailure -VariableName $variable
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('economy-v2-fake-node-' + [Guid]::NewGuid().ToString('N'))
$originalPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
try {
    [void](New-Item -ItemType Directory -Path $temporaryDirectory -Force)
    [IO.File]::WriteAllText((Join-Path $temporaryDirectory 'node.exe'), 'not-a-signed-node-executable', [Text.Encoding]::ASCII)
    $escapedRunner = $runner.Replace("'", "''")
    $command = "`$env:PATH = '$($temporaryDirectory.Replace("'", "''"));' + `$env:PATH; & '$escapedRunner' -NodeTrustOnly"
    $output = & $powershell -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1
    $text = $output | Out-String
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Fake node PATH probe failed: $text"
    Assert-True -Condition ($text -match 'PASS: economy-v2 trusted Node is') -Message 'Trusted Node probe did not report a verified executable'
    Assert-True -Condition ($text -notmatch [regex]::Escape($temporaryDirectory)) -Message 'Trusted Node probe accepted the fake PATH executable'
}
finally {
    [Environment]::SetEnvironmentVariable('PATH', $originalPath, 'Process')
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "PASS: $assertions economy-v2 execution-boundary assertions"
