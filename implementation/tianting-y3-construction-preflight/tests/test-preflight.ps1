$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $packageRoot '..\..')).Path
$preflightPath = Join-Path $PSScriptRoot 'Invoke-TiantingY3ConstructionPreflight.ps1'
$fixturePath = Join-Path $PSScriptRoot 'fixtures\synthetic-complete-directory.json'
$fixture = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
$powershell = Join-Path $PSHOME 'powershell.exe'
$assertions = 0
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('tianting-y3-construction-preflight-' + [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw $Message }
}

function Invoke-Preflight {
    param([string[]]$ScriptArguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath @ScriptArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = ($output | Out-String)
    }
}

function New-SyntheticDirectoryFixture {
    param([string]$Root)
    foreach ($relativePath in @($fixture.directories)) {
        if ([IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Unsafe synthetic fixture path: $relativePath"
        }
        [void](New-Item -ItemType Directory -Path (Join-Path $Root $relativePath) -Force)
    }
}

function Remove-VerifiedTemporaryDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedPath.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a non-temporary fixture directory: $resolvedPath"
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

try {
    $workspaceResult = Invoke-Preflight -ScriptArguments @('-TargetMapRoot', $repoRoot)
    Assert-True ($workspaceResult.ExitCode -ne 0) 'The current repository unexpectedly passed as a real Y3 map root.'
    Assert-True ($workspaceResult.Text -match 'required map-local script root is missing') 'The current workspace failure did not identify the missing script root.'

    [void](New-Item -ItemType Directory -Path $tempRoot -Force)
    $missingY3Root = Join-Path $tempRoot 'missing-y3'
    [void](New-Item -ItemType Directory -Path (Join-Path $missingY3Root 'script') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $missingY3Root 'ui') -Force)
    $missingY3Result = Invoke-Preflight -ScriptArguments @('-TargetMapRoot', $missingY3Root)
    Assert-True ($missingY3Result.ExitCode -ne 0) 'A target lacking script/y3 unexpectedly passed.'
    Assert-True ($missingY3Result.Text -match 'required y3-lualib root is missing') 'Missing y3-lualib root was not diagnosed.'

    $missingUiRoot = Join-Path $tempRoot 'missing-ui'
    New-SyntheticDirectoryFixture -Root $missingUiRoot
    Remove-Item -LiteralPath (Join-Path $missingUiRoot 'ui') -Force
    $missingUiResult = Invoke-Preflight -ScriptArguments @('-TargetMapRoot', $missingUiRoot)
    Assert-True ($missingUiResult.ExitCode -ne 0) 'A target lacking ui unexpectedly passed.'
    Assert-True ($missingUiResult.Text -match 'required UI root is missing') 'Missing UI root was not diagnosed.'

    $completeRoot = Join-Path $tempRoot 'complete-map-root'
    New-SyntheticDirectoryFixture -Root $completeRoot
    $invalidInterfaceResult = Invoke-Preflight -ScriptArguments @('-TargetMapRoot', $completeRoot, '-ObjectInterfaceIdentifier', 'TT_UNIT_001')
    Assert-True ($invalidInterfaceResult.ExitCode -ne 0) 'An object-key-looking interface identifier unexpectedly passed.'
    Assert-True ($invalidInterfaceResult.Text -match 'object interface identifier must be a lowercase dotted interface name') 'Invalid object interface identifier was not diagnosed.'

    $passWithoutOptional = Invoke-Preflight -ScriptArguments @('-TargetMapRoot', $completeRoot, '-AsJson')
    Assert-True ($passWithoutOptional.ExitCode -eq 0) "A complete synthetic fixture without an optional interface failed: $($passWithoutOptional.Text)"
    $withoutOptionalReport = $passWithoutOptional.Text | ConvertFrom-Json
    Assert-True ($withoutOptionalReport.result -eq 'structural_preflight_passed') 'Synthetic fixture did not report a structural pass.'
    Assert-True ($withoutOptionalReport.structural_checks.object_interface_identifier -eq 'not_requested') 'Optional object interface was not reported as optional.'

    $passWithOptional = Invoke-Preflight -ScriptArguments @('-TargetMapRoot', $completeRoot, '-ObjectInterfaceIdentifier', $fixture.object_interface_identifier, '-AsJson')
    Assert-True ($passWithOptional.ExitCode -eq 0) "A complete synthetic fixture with an interface failed: $($passWithOptional.Text)"
    $withOptionalReport = $passWithOptional.Text | ConvertFrom-Json
    Assert-True ($withOptionalReport.structural_checks.y3_lualib_root -eq 'present') 'Synthetic fixture did not report y3-lualib structure.'
    Assert-True ($withOptionalReport.structural_checks.ui_root -eq 'present') 'Synthetic fixture did not report the UI root.'
    Assert-True ($withOptionalReport.structural_checks.object_interface_identifier -eq 'declared_opaque_not_invoked') 'Optional interface was not kept opaque.'
    Assert-True ($withOptionalReport.production_gate -eq 'closed') 'Structural pass unexpectedly opened the production gate.'
    Assert-True ($withOptionalReport.permissions.production_object_creation_permitted -eq $false) 'Structural pass unexpectedly permitted object creation.'
}
finally {
    Remove-VerifiedTemporaryDirectory -Path $tempRoot
}

Write-Output "PASS: $assertions TianTing Y3 construction preflight assertions"
