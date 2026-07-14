param(
    [string]$PnpmPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

if (-not $PnpmPath) {
    $command = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($command) {
        $PnpmPath = $command.Source
    } else {
        $candidate = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd'
        if (Test-Path -LiteralPath $candidate) {
            $PnpmPath = $candidate
        }
    }
}

$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
$fengariCli = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'pnpm\store') -Recurse -File -Filter 'lua-cli.js' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$' } |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $fengariCli -and (-not $PnpmPath -or -not (Test-Path -LiteralPath $PnpmPath))) {
    throw 'No cached fengari-node-cli or pnpm fallback was found. Pass -PnpmPath with an absolute path.'
}

function Invoke-LuaTest {
    param([string]$Path)

    if ($fengariCli -and $nodePath) {
        $luaOutput = & $nodePath $fengariCli $Path 2>&1
    } else {
        $luaOutput = & $PnpmPath --package=fengari-node-cli dlx fengari $Path 2>&1
    }
    $luaExitCode = $LASTEXITCODE
    $luaOutput | Write-Output
    $luaPassed = $luaOutput -match '^PASS: \d+(?: [a-z]+){0,2} assertions$'
    if ($luaExitCode -ne 0 -or -not $luaPassed -or $luaOutput -match 'stack traceback') {
        throw "Lua test failed for $Path with exit code $luaExitCode"
    }
}

Push-Location $projectRoot
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File '.\implementation\powang\tests\preflight.ps1'
    if ($LASTEXITCODE -ne 0) {
        throw "preflight failed with exit code $LASTEXITCODE"
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File '.\implementation\powang\tests\test-materializer.ps1'
    if ($LASTEXITCODE -ne 0) {
        throw "materializer tests failed with exit code $LASTEXITCODE"
    }

    Invoke-LuaTest 'implementation/powang/tests/test_powang.lua'
    Invoke-LuaTest 'implementation/powang/tests/test_bridge_targeting.lua'
    Invoke-LuaTest 'implementation/powang/tests/test_bridge_lifecycle.lua'

    & powershell -NoProfile -ExecutionPolicy Bypass -File '.\implementation\powang\tests\verify-y3-api.ps1'
    if ($LASTEXITCODE -ne 0) {
        throw "Y3 API baseline verification failed with exit code $LASTEXITCODE"
    }

    $forbidden = Get-ChildItem -LiteralPath '.\implementation\powang\lua' -File -Filter '*.lua' |
        Where-Object { $_.Name -notlike 'powang_y3_*.lua' } |
        Select-String -Pattern 'y3\.|GameAPI\.|GlobalAPI\.'
    if ($forbidden) {
        $forbidden | Format-Table Path,LineNumber,Line -AutoSize
        throw 'Adapter-neutral core must not contain Y3 API calls.'
    }

    Write-Output 'PASS: Powang offline construction package.'
} finally {
    Pop-Location
}
