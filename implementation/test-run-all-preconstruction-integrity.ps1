$ErrorActionPreference = 'Stop'

$runnerPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'run-all-preconstruction.ps1')).Path
$professionRunnerPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'run-all-professions.ps1')).Path
$trustedHostPath = (Resolve-Path -LiteralPath ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)).Path
$trustedHostItem = Get-Item -LiteralPath $trustedHostPath -Force
if ([string]$PSVersionTable.PSEdition -cne 'Desktop' -or $trustedHostItem.Name -ine 'powershell.exe') {
    throw "This integrity regression must run under Windows PowerShell powershell.exe: $trustedHostPath"
}

$trustedNodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $trustedNodeCommand -or [string]::IsNullOrWhiteSpace($trustedNodeCommand.Source)) {
    throw 'Node.js node.exe is required for the top-level runner integrity regression.'
}
$trustedNodePath = (Resolve-Path -LiteralPath $trustedNodeCommand.Source).Path
$initialNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
$initialNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
try {
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $null, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $null, 'Process')
    $trustedNodeIdentityPath = (& $trustedNodePath -p "(require('fs').realpathSync.native || require('fs').realpathSync)(process.execPath)").Trim()
}
finally {
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $initialNodeOptions, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $initialNodePath, 'Process')
}
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($trustedNodeIdentityPath)) {
    throw 'Unable to determine the physical identity of the trusted node.exe.'
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('run-all-preconstruction-integrity-' + [guid]::NewGuid().ToString('N'))
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$fixtureRootFullPath = [IO.Path]::GetFullPath($fixtureRoot)
if (-not $fixtureRootFullPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create an integrity fixture outside the temporary directory: $fixtureRootFullPath"
}

$fakeCommandDirectory = Join-Path $fixtureRoot 'fake-command-path'
$topFixtureRoot = Join-Path $fixtureRoot 'top-level'
$topFixtureRunnerPath = Join-Path $topFixtureRoot 'run-all-preconstruction.ps1'
$restorationWrapperPath = Join-Path $topFixtureRoot 'invoke-and-assert-restoration.ps1'
$coreEditionWrapperPath = Join-Path $fixtureRoot 'invoke-with-core-edition.ps1'
$professionFixtureRoot = Join-Path $fixtureRoot 'profession-runner'
$professionFixtureRunnerPath = Join-Path $professionFixtureRoot 'implementation\run-all-professions.ps1'
$professionRestorationWrapperPath = Join-Path $professionFixtureRoot 'invoke-and-assert-restoration.ps1'
$nodeInjectionRoot = Join-Path $fixtureRoot 'node-injection'
$nodeOptionsPreloadPath = Join-Path $nodeInjectionRoot 'preload.js'
$nodePathRoot = Join-Path $nodeInjectionRoot 'node-path'
$poisonedPathExt = '.CMD;.EXE'

$environmentVariableNames = @(
    'PATH',
    'PATHEXT',
    'NODE_OPTIONS',
    'NODE_PATH',
    'LOCALAPPDATA',
    'RUN_ALL_PRECONSTRUCTION_FAKE_POWERSHELL_MARKER',
    'RUN_ALL_PRECONSTRUCTION_FAKE_NODE_MARKER',
    'RUN_ALL_PRECONSTRUCTION_INTEGRITY_MARKER',
    'RUN_ALL_PRECONSTRUCTION_PROFESSION_MARKER',
    'RUN_ALL_PRECONSTRUCTION_NESTED_MARKER',
    'RUN_ALL_PRECONSTRUCTION_NODE_MARKER',
    'RUN_ALL_PRECONSTRUCTION_HGS_MARKER',
    'RUN_ALL_PRECONSTRUCTION_DIRECT_FAIL',
    'RUN_ALL_PRECONSTRUCTION_FAIL_NESTED',
    'RUN_ALL_PROFESSIONS_PACKAGE_MARKER',
    'RUN_ALL_PROFESSIONS_NODE_MARKER',
    'RUN_ALL_PROFESSIONS_NESTED_MARKER',
    'RUN_ALL_PROFESSIONS_EXPECTED_PNPM',
    'RUN_ALL_PROFESSIONS_FAIL_PACKAGE',
    'RUNNER_NODE_OPTIONS_MARKER',
    'RUNNER_NODE_PATH_MARKER'
)
$originalEnvironment = @{}
foreach ($name in $environmentVariableNames) {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Assert-TrustedHostMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description did not execute."
    }
    $recordedHostPath = (Get-Content -Raw -LiteralPath $Path).Trim()
    if ([string]::IsNullOrWhiteSpace($recordedHostPath)) {
        throw "$Description recorded an empty PowerShell host path."
    }
    $resolvedRecordedHostPath = (Resolve-Path -LiteralPath $recordedHostPath -ErrorAction Stop).Path
    if ($resolvedRecordedHostPath -ine $trustedHostPath) {
        throw "$Description used an unexpected PowerShell host: $resolvedRecordedHostPath"
    }
}

function Assert-TrustedNodeMarker {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description did not execute."
    }
    $recordedNodePath = (Get-Content -Raw -LiteralPath $Path).Trim()
    if ($recordedNodePath -ine $trustedNodeIdentityPath) {
        throw "$Description used an unexpected Node.js executable: $recordedNodePath"
    }
}

function Assert-NoForgedCommand {
    param(
        [Parameter(Mandatory = $true)]$Markers,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (Test-Path -LiteralPath $Markers.FakePowerShell) {
        throw "PATH-first fake powershell.exe executed during $Description."
    }
    if (Test-Path -LiteralPath $Markers.FakeNode) {
        throw "PATH-first node.cmd executed during $Description."
    }
}

function Assert-NoNodeInjection {
    param(
        [Parameter(Mandatory = $true)]$Markers,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (Test-Path -LiteralPath $Markers.NodeOptions) {
        throw "NODE_OPTIONS preload executed during $Description."
    }
    if (Test-Path -LiteralPath $Markers.NodePath) {
        throw "NODE_PATH changed module resolution during $Description."
    }
}

function Invoke-CapturedPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "The integrity harness cannot invoke a missing PowerShell executable: $FilePath"
    }

    $savedErrorActionPreference = $ErrorActionPreference
    $invocationFailure = $null
    $output = @()
    $exitCode = $null
    try {
        $ErrorActionPreference = 'Continue'
        try {
            $output = @(& $FilePath @ArgumentList 2>&1)
            $exitCode = $LASTEXITCODE
        }
        catch {
            $invocationFailure = $_
        }
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }

    if ($invocationFailure) {
        throw "The integrity harness failed to invoke '$FilePath': $($invocationFailure.Exception.Message)"
    }
    if ($null -eq $exitCode) {
        throw "The integrity harness invocation of '$FilePath' did not produce a process exit code."
    }

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = [object[]]$output
    }
}

function Invoke-TopFixtureScenario {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$DirectFailure,
        [Parameter(Mandatory = $true)][bool]$FailNestedSuite,
        [switch]$AssertRestoration
    )

    $scenarioRoot = Join-Path $fixtureRoot $Name
    New-Item -ItemType Directory -Path $scenarioRoot -Force | Out-Null
    $markers = [ordered]@{
        FakePowerShell = Join-Path $scenarioRoot 'fake-powershell.marker'
        FakeNode = Join-Path $scenarioRoot 'fake-node.marker'
        Integrity = Join-Path $scenarioRoot 'integrity.marker'
        Profession = Join-Path $scenarioRoot 'profession.marker'
        Nested = Join-Path $scenarioRoot 'nested.marker'
        Node = Join-Path $scenarioRoot 'node.marker'
        Huaguoshan = Join-Path $scenarioRoot 'huaguoshan.marker'
        Restoration = Join-Path $scenarioRoot 'restoration.marker'
        NodeOptions = Join-Path $scenarioRoot 'node-options.marker'
        NodePath = Join-Path $scenarioRoot 'node-path.marker'
    }

    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_FAKE_POWERSHELL_MARKER', $markers.FakePowerShell, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_FAKE_NODE_MARKER', $markers.FakeNode, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_INTEGRITY_MARKER', $markers.Integrity, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_PROFESSION_MARKER', $markers.Profession, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_NESTED_MARKER', $markers.Nested, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_NODE_MARKER', $markers.Node, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_HGS_MARKER', $markers.Huaguoshan, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_DIRECT_FAIL', $(if ($DirectFailure) { '1' } else { '0' }), 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_FAIL_NESTED', $(if ($FailNestedSuite) { '1' } else { '0' }), 'Process')
    [Environment]::SetEnvironmentVariable('RUNNER_NODE_OPTIONS_MARKER', $markers.NodeOptions, 'Process')
    [Environment]::SetEnvironmentVariable('RUNNER_NODE_PATH_MARKER', $markers.NodePath, 'Process')

    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
    if ($AssertRestoration) {
        $argumentList += @($restorationWrapperPath, '-RunnerPath', $topFixtureRunnerPath, '-MarkerPath', $markers.Restoration)
    }
    else {
        $argumentList += $topFixtureRunnerPath
    }
    $invocation = Invoke-CapturedPowerShell -FilePath $trustedHostPath -ArgumentList $argumentList
    $output = $invocation.Output
    $exitCode = $invocation.ExitCode
    if ([Environment]::GetEnvironmentVariable('PATH', 'Process') -cne $poisonedPath -or
        [Environment]::GetEnvironmentVariable('PATHEXT', 'Process') -cne $poisonedPathExt -or
        [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process') -cne $injectedNodeOptions -or
        [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process') -cne $nodePathRoot) {
        throw "The integrity harness environment changed after scenario '$Name'."
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
        Markers = $markers
    }
}

function Invoke-ProfessionFixtureScenario {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$FailPackage,
        [ValidateSet('Pinned', 'Unpinned')][string]$Cache = 'Pinned',
        [switch]$AssertRestoration
    )

    $scenarioRoot = Join-Path $fixtureRoot $Name
    New-Item -ItemType Directory -Path $scenarioRoot -Force | Out-Null
    $markers = [ordered]@{
        FakePowerShell = Join-Path $scenarioRoot 'fake-powershell.marker'
        FakeNode = Join-Path $scenarioRoot 'fake-node.marker'
        Packages = Join-Path $scenarioRoot 'packages.marker'
        Node = Join-Path $scenarioRoot 'node.marker'
        Nested = Join-Path $scenarioRoot 'nested.marker'
        Restoration = Join-Path $scenarioRoot 'restoration.marker'
        NodeOptions = Join-Path $scenarioRoot 'node-options.marker'
        NodePath = Join-Path $scenarioRoot 'node-path.marker'
    }
    $pnpmSentinel = Join-Path $scenarioRoot 'pnpm sentinel.cmd'

    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_FAKE_POWERSHELL_MARKER', $markers.FakePowerShell, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PRECONSTRUCTION_FAKE_NODE_MARKER', $markers.FakeNode, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PROFESSIONS_PACKAGE_MARKER', $markers.Packages, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PROFESSIONS_NODE_MARKER', $markers.Node, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PROFESSIONS_NESTED_MARKER', $markers.Nested, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PROFESSIONS_EXPECTED_PNPM', $pnpmSentinel, 'Process')
    [Environment]::SetEnvironmentVariable('RUN_ALL_PROFESSIONS_FAIL_PACKAGE', $FailPackage, 'Process')
    [Environment]::SetEnvironmentVariable('RUNNER_NODE_OPTIONS_MARKER', $markers.NodeOptions, 'Process')
    [Environment]::SetEnvironmentVariable('RUNNER_NODE_PATH_MARKER', $markers.NodePath, 'Process')
    $localAppData = if ($Cache -ceq 'Pinned') {
        [string]$originalEnvironment['LOCALAPPDATA']
    }
    else {
        Join-Path $professionFixtureRoot 'localappdata'
    }
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $localAppData, 'Process')

    $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
    if ($AssertRestoration) {
        $argumentList += @(
            $professionRestorationWrapperPath,
            '-RunnerPath', $professionFixtureRunnerPath,
            '-PnpmPath', $pnpmSentinel,
            '-MarkerPath', $markers.Restoration
        )
    }
    else {
        $argumentList += @($professionFixtureRunnerPath, '-PnpmPath', $pnpmSentinel)
    }
    $invocation = Invoke-CapturedPowerShell -FilePath $trustedHostPath -ArgumentList $argumentList
    $output = $invocation.Output
    $exitCode = $invocation.ExitCode
    if ([Environment]::GetEnvironmentVariable('PATH', 'Process') -cne $poisonedPath -or
        [Environment]::GetEnvironmentVariable('PATHEXT', 'Process') -cne $poisonedPathExt -or
        [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process') -cne $injectedNodeOptions -or
        [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process') -cne $nodePathRoot) {
        throw "The profession integrity harness environment changed after scenario '$Name'."
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
        Markers = $markers
        PnpmPath = $pnpmSentinel
    }
}

function Assert-ProfessionPackageMarkers {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string[]]$ExpectedPackages,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Result.Markers.Packages -PathType Leaf)) {
        throw "$Description did not execute any profession packages."
    }
    $records = @(Get-Content -LiteralPath $Result.Markers.Packages)
    if ($records.Count -ne $ExpectedPackages.Count) {
        throw "$Description executed $($records.Count) profession packages; expected $($ExpectedPackages.Count)."
    }
    for ($index = 0; $index -lt $records.Count; $index++) {
        $parts = @($records[$index] -split '\|', 3)
        if ($parts.Count -ne 3 -or $parts[0] -cne $ExpectedPackages[$index]) {
            throw "$Description recorded an unexpected package entry: $($records[$index])"
        }
        $recordedHostPath = (Resolve-Path -LiteralPath $parts[1] -ErrorAction Stop).Path
        if ($recordedHostPath -ine $trustedHostPath) {
            throw "$Description used an unexpected PowerShell host: $recordedHostPath"
        }
        if ($parts[2] -cne $Result.PnpmPath) {
            throw "$Description did not preserve -PnpmPath for $($parts[0])."
        }
    }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $topFixtureRoot 'huaguoshan\tests') -Force | Out-Null
    New-Item -ItemType Directory -Path $fakeCommandDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $professionFixtureRunnerPath) -Force | Out-Null
    New-Item -ItemType Directory -Path $nodeInjectionRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $nodePathRoot 'profession-runner-node-path-probe') -Force | Out-Null
    Copy-Item -LiteralPath $runnerPath -Destination $topFixtureRunnerPath
    Copy-Item -LiteralPath $professionRunnerPath -Destination $professionFixtureRunnerPath

    Set-Content -LiteralPath (Join-Path $topFixtureRoot 'test-run-all-preconstruction-integrity.ps1') -Encoding ASCII -Value @'
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $env:RUN_ALL_PRECONSTRUCTION_INTEGRITY_MARKER -Encoding ASCII -Value ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
if ($env:RUN_ALL_PRECONSTRUCTION_DIRECT_FAIL -ceq '1') { exit 37 }
'@
    Set-Content -LiteralPath (Join-Path $topFixtureRoot 'run-all-professions.ps1') -Encoding ASCII -Value @'
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $env:RUN_ALL_PRECONSTRUCTION_PROFESSION_MARKER -Encoding ASCII -Value ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'nested-profession-suite.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$nodeProbe = @"
const fs = require('fs');
if (Object.prototype.hasOwnProperty.call(process.env, 'NODE_OPTIONS') ||
    Object.prototype.hasOwnProperty.call(process.env, 'NODE_PATH')) {
  throw new Error('controlled Node environment retained NODE_OPTIONS or NODE_PATH');
}
try {
  require('profession-runner-node-path-probe');
  throw new Error('NODE_PATH changed controlled module resolution');
} catch (error) {
  if (!error || error.code !== 'MODULE_NOT_FOUND') throw error;
}
const realpath = fs.realpathSync.native || fs.realpathSync;
fs.writeFileSync(process.env.RUN_ALL_PRECONSTRUCTION_NODE_MARKER, realpath(process.execPath));
process.stdout.write('PASS: fixture node probe.\n');
"@
$nodeOutput = & node -e $nodeProbe 2>&1
$nodeExitCode = $LASTEXITCODE
$nodeOutput | Write-Output
$nodeOutputText = (@($nodeOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
if ($nodeExitCode -ne 0 -or $nodeOutputText -notmatch '(?m)^PASS: fixture node probe\.$') { exit 43 }
Write-Output 'PASS: fixture profession suite.'
'@
    Set-Content -LiteralPath (Join-Path $topFixtureRoot 'nested-profession-suite.ps1') -Encoding ASCII -Value @'
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $env:RUN_ALL_PRECONSTRUCTION_NESTED_MARKER -Encoding ASCII -Value ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
if ($env:RUN_ALL_PRECONSTRUCTION_FAIL_NESTED -ceq '1') { exit 41 }
Write-Output 'PASS: fixture nested profession suite.'
'@
    Set-Content -LiteralPath (Join-Path $topFixtureRoot 'huaguoshan\tests\run-all.ps1') -Encoding ASCII -Value @'
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $env:RUN_ALL_PRECONSTRUCTION_HGS_MARKER -Encoding ASCII -Value ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
Write-Output 'PASS: fixture Huaguoshan suite.'
'@
    Set-Content -LiteralPath $restorationWrapperPath -Encoding ASCII -Value @'
param(
    [Parameter(Mandatory = $true)][string]$RunnerPath,
    [Parameter(Mandatory = $true)][string]$MarkerPath
)
$ErrorActionPreference = 'Stop'
$beforePath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
$beforePathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
$beforeNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
$beforeNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
. $RunnerPath
$afterPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
$afterPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
$afterNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
$afterNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
if ($afterPath -cne $beforePath -or
    $afterPathExt -cne $beforePathExt -or
    $afterNodeOptions -cne $beforeNodeOptions -or
    $afterNodePath -cne $beforeNodePath) { exit 53 }
Set-Content -LiteralPath $MarkerPath -Encoding ASCII -Value 'restored'
'@
    Set-Content -LiteralPath $professionRestorationWrapperPath -Encoding ASCII -Value @'
param(
    [Parameter(Mandatory = $true)][string]$RunnerPath,
    [Parameter(Mandatory = $true)][string]$PnpmPath,
    [Parameter(Mandatory = $true)][string]$MarkerPath
)
$ErrorActionPreference = 'Stop'
$beforePath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
$beforePathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
$beforeNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
$beforeNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
$caught = $null
try {
    . $RunnerPath -PnpmPath $PnpmPath
}
catch {
    $caught = $_
}
$afterPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
$afterPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
$afterNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
$afterNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
if ($afterPath -cne $beforePath -or
    $afterPathExt -cne $beforePathExt -or
    $afterNodeOptions -cne $beforeNodeOptions -or
    $afterNodePath -cne $beforeNodePath) { exit 54 }
Set-Content -LiteralPath $MarkerPath -Encoding ASCII -Value 'restored'
if ($caught) { throw $caught }
'@
    Set-Content -LiteralPath $coreEditionWrapperPath -Encoding ASCII -Value @'
param(
    [Parameter(Mandatory = $true)][string]$RunnerPath,
    [string]$PnpmPath
)
$ErrorActionPreference = 'Stop'
$originalEdition = [string]$PSVersionTable.PSEdition
try {
    $PSVersionTable.PSEdition = 'Core'
    if ([string]::IsNullOrWhiteSpace($PnpmPath)) {
        . $RunnerPath
    } else {
        . $RunnerPath -PnpmPath $PnpmPath
    }
}
finally {
    $PSVersionTable.PSEdition = $originalEdition
}
'@

    $fakePowerShellPath = Join-Path $fakeCommandDirectory 'powershell.exe'
    Add-Type -Language CSharp -OutputType ConsoleApplication -OutputAssembly $fakePowerShellPath -TypeDefinition @'
using System;
using System.IO;

public static class FakePowerShell
{
    public static int Main(string[] args)
    {
        string markerPath = Environment.GetEnvironmentVariable("RUN_ALL_PRECONSTRUCTION_FAKE_POWERSHELL_MARKER");
        if (!String.IsNullOrWhiteSpace(markerPath))
        {
            File.AppendAllText(markerPath, "invoked" + Environment.NewLine);
        }
        Console.WriteLine("PASS: profession and Huaguoshan offline preconstruction packages.");
        return 0;
    }
}
'@
    Set-Content -LiteralPath (Join-Path $fakeCommandDirectory 'node.cmd') -Encoding ASCII -Value @'
@echo off
if not "%RUN_ALL_PRECONSTRUCTION_FAKE_NODE_MARKER%"=="" echo invoked>>"%RUN_ALL_PRECONSTRUCTION_FAKE_NODE_MARKER%"
if /I "%~1"=="-e" (
  echo PASS: fixture node probe.
) else (
  echo PASS: 27 common assertions
)
exit /b 0
'@
    Set-Content -LiteralPath $nodeOptionsPreloadPath -Encoding ASCII -Value @'
const fs = require('fs');
const marker = process.env.RUNNER_NODE_OPTIONS_MARKER;
if (marker) fs.writeFileSync(marker, 'NODE_OPTIONS preload executed');
'@
    Set-Content -LiteralPath (Join-Path $nodePathRoot 'profession-runner-node-path-probe\index.js') -Encoding ASCII -Value @'
const fs = require('fs');
const marker = process.env.RUNNER_NODE_PATH_MARKER;
if (marker) fs.writeFileSync(marker, 'NODE_PATH module resolved');
module.exports = true;
'@

    $pwshAliasPath = Join-Path $fixtureRoot 'pwsh.exe'
    Copy-Item -LiteralPath $trustedHostPath -Destination $pwshAliasPath

    $packageScriptTemplate = @'
param([string]$PnpmPath)
$ErrorActionPreference = 'Stop'
$packageName = '__PACKAGE__'
$hostPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
Add-Content -LiteralPath $env:RUN_ALL_PROFESSIONS_PACKAGE_MARKER -Encoding ASCII -Value ($packageName + '|' + $hostPath + '|' + $PnpmPath)
if ($PnpmPath -cne $env:RUN_ALL_PROFESSIONS_EXPECTED_PNPM) { exit 48 }
if ($env:RUN_ALL_PROFESSIONS_FAIL_PACKAGE -ceq $packageName) { exit 47 }
if ($packageName -ceq 'Powang') {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'nested-powershell.ps1')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Write-Output ('PASS: fixture ' + $packageName + ' package.')
'@
    foreach ($packageName in @('Powang', 'Zhenjie', 'Chiming', 'Xunlie')) {
        $packageDirectoryName = $packageName.ToLowerInvariant()
        $packageRunnerDirectory = Join-Path $professionFixtureRoot "implementation\$packageDirectoryName\tests"
        New-Item -ItemType Directory -Path $packageRunnerDirectory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $packageRunnerDirectory 'run-all.ps1') -Encoding ASCII -Value $packageScriptTemplate.Replace('__PACKAGE__', $packageName)
    }
    Set-Content -LiteralPath (Join-Path $professionFixtureRoot 'implementation\powang\tests\nested-powershell.ps1') -Encoding ASCII -Value @'
$ErrorActionPreference = 'Stop'
Set-Content -LiteralPath $env:RUN_ALL_PROFESSIONS_NESTED_MARKER -Encoding ASCII -Value ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
Write-Output 'PASS: fixture nested profession PowerShell.'
'@

    $commonTestDirectory = Join-Path $professionFixtureRoot 'implementation\profession_common\tests'
    $commonLuaDirectory = Join-Path $professionFixtureRoot 'implementation\profession_common\lua'
    $fengariDirectory = Join-Path $professionFixtureRoot 'localappdata\pnpm\store\fixture\fengari-node-cli\src'
    New-Item -ItemType Directory -Path $commonTestDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $commonLuaDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $fengariDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'profession_common\tests\test_common.lua') -Destination (Join-Path $commonTestDirectory 'test_common.lua')
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'profession_common\lua') -File |
        Copy-Item -Destination $commonLuaDirectory
    Set-Content -LiteralPath (Join-Path $fengariDirectory 'lua-cli.js') -Encoding ASCII -Value @'
const fs = require('fs');
const realpath = fs.realpathSync.native || fs.realpathSync;
fs.writeFileSync(process.env.RUN_ALL_PROFESSIONS_NODE_MARKER, realpath(process.execPath));
process.stdout.write('PASS: 27 common assertions\n');
'@

    $poisonedPath = $fakeCommandDirectory
    if (-not [string]::IsNullOrWhiteSpace([string]$originalEnvironment['PATH'])) {
        $poisonedPath += [IO.Path]::PathSeparator + [string]$originalEnvironment['PATH']
    }
    [Environment]::SetEnvironmentVariable('PATH', $poisonedPath, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', $poisonedPathExt, 'Process')
    $injectedNodeOptions = '--require "' + $nodeOptionsPreloadPath + '"'
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $injectedNodeOptions, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $nodePathRoot, 'Process')

    $success = Invoke-TopFixtureScenario -Name 'top-success' -DirectFailure $false -FailNestedSuite $false -AssertRestoration
    if ($success.ExitCode -ne 0) {
        throw "Trusted top-level fixture run failed with exit code $($success.ExitCode): $($success.Output -join [Environment]::NewLine)"
    }
    if (@($success.Output | Where-Object { $_ -ceq 'PASS: profession and Huaguoshan offline preconstruction packages.' }).Count -ne 1) {
        throw "Trusted top-level fixture run did not emit exactly one total PASS: $($success.Output -join [Environment]::NewLine)"
    }
    Assert-TrustedHostMarker -Path $success.Markers.Integrity -Description 'Top-level integrity suite'
    Assert-TrustedHostMarker -Path $success.Markers.Profession -Description 'Profession suite'
    Assert-TrustedHostMarker -Path $success.Markers.Nested -Description 'Nested profession suite'
    Assert-TrustedHostMarker -Path $success.Markers.Huaguoshan -Description 'Huaguoshan suite'
    Assert-TrustedNodeMarker -Path $success.Markers.Node -Description 'Nested bare node probe'
    if (-not (Test-Path -LiteralPath $success.Markers.Restoration -PathType Leaf)) {
        throw 'The top-level runner did not restore PATH, PATHEXT, NODE_OPTIONS, and NODE_PATH after a successful in-process run.'
    }
    Assert-NoForgedCommand -Markers $success.Markers -Description 'the successful top-level fixture run'
    Assert-NoNodeInjection -Markers $success.Markers -Description 'the successful top-level fixture run'

    $directFailure = Invoke-TopFixtureScenario -Name 'top-direct-failure' -DirectFailure $true -FailNestedSuite $false
    if ($directFailure.ExitCode -ne 37) {
        throw "Direct suite failure was not preserved; expected exit code 37, found $($directFailure.ExitCode): $($directFailure.Output -join [Environment]::NewLine)"
    }
    if (@($directFailure.Output | Where-Object { $_ -ceq 'PASS: profession and Huaguoshan offline preconstruction packages.' }).Count -ne 0) {
        throw 'A forged total PASS was emitted after a direct suite failure.'
    }
    Assert-TrustedHostMarker -Path $directFailure.Markers.Integrity -Description 'Directly failing integrity suite'
    foreach ($path in @($directFailure.Markers.Profession, $directFailure.Markers.Nested, $directFailure.Markers.Node, $directFailure.Markers.Huaguoshan)) {
        if (Test-Path -LiteralPath $path) { throw 'The top-level runner continued after a direct suite failure.' }
    }
    Assert-NoForgedCommand -Markers $directFailure.Markers -Description 'the direct-failure top-level fixture run'
    Assert-NoNodeInjection -Markers $directFailure.Markers -Description 'the direct-failure top-level fixture run'

    $nestedFailure = Invoke-TopFixtureScenario -Name 'top-nested-failure' -DirectFailure $false -FailNestedSuite $true
    if ($nestedFailure.ExitCode -ne 41) {
        throw "Nested suite failure was not preserved; expected exit code 41, found $($nestedFailure.ExitCode): $($nestedFailure.Output -join [Environment]::NewLine)"
    }
    if (@($nestedFailure.Output | Where-Object { $_ -ceq 'PASS: profession and Huaguoshan offline preconstruction packages.' }).Count -ne 0) {
        throw 'A forged total PASS was emitted after a nested suite failure.'
    }
    Assert-TrustedHostMarker -Path $nestedFailure.Markers.Integrity -Description 'Integrity suite before the nested failure'
    Assert-TrustedHostMarker -Path $nestedFailure.Markers.Profession -Description 'Profession suite before the nested failure'
    Assert-TrustedHostMarker -Path $nestedFailure.Markers.Nested -Description 'Failing nested profession suite'
    foreach ($path in @($nestedFailure.Markers.Node, $nestedFailure.Markers.Huaguoshan)) {
        if (Test-Path -LiteralPath $path) { throw 'The top-level runner continued after a nested suite failure.' }
    }
    Assert-NoForgedCommand -Markers $nestedFailure.Markers -Description 'the nested-failure top-level fixture run'
    Assert-NoNodeInjection -Markers $nestedFailure.Markers -Description 'the nested-failure top-level fixture run'

    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $pwshOutput = & $pwshAliasPath -NoProfile -ExecutionPolicy Bypass -File $topFixtureRunnerPath 2>&1
        $pwshExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($pwshExitCode -eq 0 -or ($pwshOutput -join [Environment]::NewLine) -notmatch 'supports only Windows PowerShell powershell\.exe') {
        throw "The top-level runner did not clearly reject pwsh.exe: $($pwshOutput -join [Environment]::NewLine)"
    }
    if (@($pwshOutput | Where-Object { [string]$_ -ceq 'PASS: profession and Huaguoshan offline preconstruction packages.' }).Count -ne 0) {
        throw 'The pwsh.exe rejection path emitted a forged total PASS.'
    }

    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $topCoreOutput = & $trustedHostPath -NoProfile -ExecutionPolicy Bypass -File $coreEditionWrapperPath `
            -RunnerPath $topFixtureRunnerPath 2>&1
        $topCoreExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($topCoreExitCode -eq 0 -or
        ($topCoreOutput -join [Environment]::NewLine) -notmatch 'supports only Windows PowerShell powershell\.exe\. Current edition: Core') {
        throw "The top-level runner did not reject a Core edition presented by powershell.exe: $($topCoreOutput -join [Environment]::NewLine)"
    }

    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $professionCoreOutput = & $trustedHostPath -NoProfile -ExecutionPolicy Bypass -File $coreEditionWrapperPath `
            -RunnerPath $professionFixtureRunnerPath `
            -PnpmPath (Join-Path $fixtureRoot 'core-edition-pnpm.cmd') 2>&1
        $professionCoreExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($professionCoreExitCode -eq 0 -or
        ($professionCoreOutput -join [Environment]::NewLine) -notmatch 'supports only Windows PowerShell powershell\.exe\. Current edition: Core') {
        throw "The profession runner did not reject a Core edition presented by powershell.exe: $($professionCoreOutput -join [Environment]::NewLine)"
    }

    $professionSuccess = Invoke-ProfessionFixtureScenario -Name 'profession-success' -FailPackage '' -AssertRestoration
    if ($professionSuccess.ExitCode -ne 0) {
        throw "Profession runner fixture failed with exit code $($professionSuccess.ExitCode): $($professionSuccess.Output -join [Environment]::NewLine)"
    }
    if (@($professionSuccess.Output | Where-Object { $_ -ceq 'PASS: C01/C02/C03/C04 cross-profession offline construction packages.' }).Count -ne 1) {
        throw "Profession runner fixture did not emit exactly one total PASS: $($professionSuccess.Output -join [Environment]::NewLine)"
    }
    if (@($professionSuccess.Output | Where-Object { $_ -ceq 'PASS: 27 common assertions' }).Count -ne 1) {
        throw "Profession runner fixture did not emit exactly one verified common PASS: $($professionSuccess.Output -join [Environment]::NewLine)"
    }
    Assert-ProfessionPackageMarkers -Result $professionSuccess -ExpectedPackages @('Powang', 'Zhenjie', 'Chiming', 'Xunlie') -Description 'Successful profession runner fixture'
    Assert-TrustedHostMarker -Path $professionSuccess.Markers.Nested -Description 'Nested bare PowerShell invocation from a profession child runner'
    if (-not (Test-Path -LiteralPath $professionSuccess.Markers.Restoration -PathType Leaf)) {
        throw 'The profession runner did not restore PATH, PATHEXT, NODE_OPTIONS, and NODE_PATH after a successful in-process run.'
    }
    Assert-NoForgedCommand -Markers $professionSuccess.Markers -Description 'the successful profession runner fixture'
    Assert-NoNodeInjection -Markers $professionSuccess.Markers -Description 'the successful profession runner fixture'

    $professionFailure = Invoke-ProfessionFixtureScenario -Name 'profession-failure' -FailPackage 'Zhenjie'
    if ($professionFailure.ExitCode -ne 47) {
        throw "Profession child failure was not preserved; expected exit code 47, found $($professionFailure.ExitCode): $($professionFailure.Output -join [Environment]::NewLine)"
    }
    if (@($professionFailure.Output | Where-Object { $_ -ceq 'PASS: C01/C02/C03/C04 cross-profession offline construction packages.' }).Count -ne 0) {
        throw 'The profession runner emitted a total PASS after a child package failure.'
    }
    Assert-ProfessionPackageMarkers -Result $professionFailure -ExpectedPackages @('Powang', 'Zhenjie') -Description 'Failing profession runner fixture'
    Assert-TrustedHostMarker -Path $professionFailure.Markers.Nested -Description 'Nested bare PowerShell invocation before a profession child failure'
    if (Test-Path -LiteralPath $professionFailure.Markers.Node) {
        throw 'The profession runner continued to common tests after a child package failure.'
    }
    Assert-NoForgedCommand -Markers $professionFailure.Markers -Description 'the failing profession runner fixture'
    Assert-NoNodeInjection -Markers $professionFailure.Markers -Description 'the failing profession runner fixture'

    $fixtureCommonTestPath = Join-Path $commonTestDirectory 'test_common.lua'
    $canonicalCommonTestPath = Join-Path $PSScriptRoot 'profession_common\tests\test_common.lua'
    Add-Content -LiteralPath $fixtureCommonTestPath -Encoding ASCII -Value '-- integrity tamper'
    $sourceMismatch = Invoke-ProfessionFixtureScenario -Name 'profession-source-mismatch' -FailPackage '' -AssertRestoration
    if ($sourceMismatch.ExitCode -eq 0 -or
        ($sourceMismatch.Output -join [Environment]::NewLine) -notmatch 'Profession common Lua source integrity mismatch') {
        throw "The profession runner accepted a modified common Lua source: $($sourceMismatch.Output -join [Environment]::NewLine)"
    }
    if (-not (Test-Path -LiteralPath $sourceMismatch.Markers.Restoration -PathType Leaf)) {
        throw 'The profession runner did not restore its caller environment after a common-source integrity failure.'
    }
    Assert-TrustedHostMarker -Path $sourceMismatch.Markers.Nested -Description 'Nested bare PowerShell invocation before common-source rejection'
    Assert-NoForgedCommand -Markers $sourceMismatch.Markers -Description 'the common-source rejection fixture'
    Assert-NoNodeInjection -Markers $sourceMismatch.Markers -Description 'the common-source rejection fixture'
    Copy-Item -LiteralPath $canonicalCommonTestPath -Destination $fixtureCommonTestPath -Force

    $fixtureCommonModulePath = Join-Path $commonLuaDirectory 'profession_target_contract.lua'
    $originalCommonModuleBytes = [IO.File]::ReadAllBytes($fixtureCommonModulePath)
    $duplicatePassPrefix = [Text.Encoding]::UTF8.GetBytes("print('PASS: 27 common assertions')`r`n")
    $duplicatePassModuleBytes = New-Object byte[] ($duplicatePassPrefix.Length + $originalCommonModuleBytes.Length)
    [Buffer]::BlockCopy($duplicatePassPrefix, 0, $duplicatePassModuleBytes, 0, $duplicatePassPrefix.Length)
    [Buffer]::BlockCopy($originalCommonModuleBytes, 0, $duplicatePassModuleBytes, $duplicatePassPrefix.Length, $originalCommonModuleBytes.Length)
    [IO.File]::WriteAllBytes($fixtureCommonModulePath, $duplicatePassModuleBytes)
    try {
        $duplicatePass = Invoke-ProfessionFixtureScenario -Name 'profession-duplicate-pass' -FailPackage '' -AssertRestoration
    }
    finally {
        [IO.File]::WriteAllBytes($fixtureCommonModulePath, $originalCommonModuleBytes)
    }
    if ($duplicatePass.ExitCode -eq 0 -or
        ($duplicatePass.Output -join [Environment]::NewLine) -notmatch 'must emit exactly.*PASS: 27 common assertions.*and no other output') {
        throw "The profession runner accepted ambiguous duplicate PASS output: $($duplicatePass.Output -join [Environment]::NewLine)"
    }
    if (@($duplicatePass.Output | Where-Object { $_ -ceq 'PASS: 27 common assertions' }).Count -ne 2) {
        throw "The duplicate-PASS fixture did not exercise two identical PASS lines: $($duplicatePass.Output -join [Environment]::NewLine)"
    }
    if (-not (Test-Path -LiteralPath $duplicatePass.Markers.Restoration -PathType Leaf)) {
        throw 'The profession runner did not restore its caller environment after ambiguous common output.'
    }
    Assert-TrustedHostMarker -Path $duplicatePass.Markers.Nested -Description 'Nested bare PowerShell invocation before duplicate-PASS rejection'
    Assert-NoForgedCommand -Markers $duplicatePass.Markers -Description 'the duplicate-PASS rejection fixture'
    Assert-NoNodeInjection -Markers $duplicatePass.Markers -Description 'the duplicate-PASS rejection fixture'

    $unpinnedCache = Invoke-ProfessionFixtureScenario -Name 'profession-unpinned-cache' -FailPackage '' -Cache Unpinned -AssertRestoration
    if ($unpinnedCache.ExitCode -eq 0 -or
        ($unpinnedCache.Output -join [Environment]::NewLine) -notmatch 'Expected exactly one pinned fengari-node-cli') {
        throw "The profession runner accepted an arbitrary cached Fengari CLI: $($unpinnedCache.Output -join [Environment]::NewLine)"
    }
    if (Test-Path -LiteralPath $unpinnedCache.Markers.Node) {
        throw 'The profession runner executed the arbitrary cached Fengari CLI before rejecting it.'
    }
    if (-not (Test-Path -LiteralPath $unpinnedCache.Markers.Restoration -PathType Leaf)) {
        throw 'The profession runner did not restore its caller environment after rejecting an unpinned cache.'
    }
    Assert-TrustedHostMarker -Path $unpinnedCache.Markers.Nested -Description 'Nested bare PowerShell invocation before unpinned-cache rejection'
    Assert-NoForgedCommand -Markers $unpinnedCache.Markers -Description 'the unpinned-cache rejection fixture'
    Assert-NoNodeInjection -Markers $unpinnedCache.Markers -Description 'the unpinned-cache rejection fixture'
}
finally {
    foreach ($name in $environmentVariableNames) {
        [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $fixtureRoot) {
        $deleteTarget = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $fixtureRoot).Path)
        if (-not $deleteTarget.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove an integrity fixture outside the temporary directory: $deleteTarget"
        }
        Remove-Item -LiteralPath $deleteTarget -Recurse -Force
    }
}

foreach ($name in $environmentVariableNames) {
    if ([Environment]::GetEnvironmentVariable($name, 'Process') -cne $originalEnvironment[$name]) {
        throw "Integrity regression did not restore process environment variable $name."
    }
}

Write-Output 'PASS: top-level and profession runners pin powershell.exe/node.exe, preserve exit codes, and restore their environment.'
