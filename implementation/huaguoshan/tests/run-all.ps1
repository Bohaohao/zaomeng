param(
    [string]$PnpmPath,
    [switch]$NodeIntegritySelfTestOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-SupportedWindowsPowerShellPath {
    param(
        [AllowNull()][string]$HostPath,
        [AllowNull()][string]$PowerShellEdition
    )

    $unsupportedHostMessage = 'Huaguoshan offline runner supports only Windows PowerShell powershell.exe.'
    if ($PowerShellEdition -cne 'Desktop') {
        throw "$unsupportedHostMessage Current edition: $PowerShellEdition"
    }
    if ([string]::IsNullOrWhiteSpace($HostPath) -or -not [IO.Path]::IsPathRooted($HostPath)) {
        throw "$unsupportedHostMessage Unable to determine an absolute current host path."
    }

    $resolvedHostPath = (Resolve-Path -LiteralPath $HostPath -ErrorAction Stop).Path
    $hostItem = Get-Item -LiteralPath $resolvedHostPath -Force -ErrorAction Stop
    if ($hostItem.PSIsContainer -or
        [IO.Path]::GetExtension($resolvedHostPath) -ine '.exe' -or
        $hostItem.Name -ine 'powershell.exe') {
        throw "$unsupportedHostMessage Current host: $resolvedHostPath"
    }
    return $resolvedHostPath
}

$currentPowerShellHostPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$powershellPath = Resolve-SupportedWindowsPowerShellPath `
    -HostPath $currentPowerShellHostPath `
    -PowerShellEdition ([string]$PSVersionTable.PSEdition)
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not [string]::IsNullOrWhiteSpace($PnpmPath)) {
    throw '-PnpmPath is not accepted because pnpm dlx cannot prove the exact offline Lua dependency graph.'
}

$originalNodeEnvironment = @{}
Get-ChildItem Env: | Where-Object { $_.Name -match '^NODE_' } | ForEach-Object {
    $originalNodeEnvironment[$_.Name] = [string]$_.Value
}
$originalPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
$originalPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')

try {
Get-ChildItem Env: | Where-Object { $_.Name -match '^NODE_' } | ForEach-Object {
    [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
}

if (-not ('Huaguoshan.Runner.NativeFilePath' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Huaguoshan.Runner
{
    public static class NativeFilePath
    {
        private const uint FileShareRead = 0x00000001;
        private const uint FileShareWrite = 0x00000002;
        private const uint FileShareDelete = 0x00000004;
        private const uint OpenExisting = 3;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle file,
            StringBuilder filePath,
            uint filePathLength,
            uint flags);

        public static string GetFinalPath(string path)
        {
            using (SafeFileHandle handle = CreateFileW(
                path,
                0,
                FileShareRead | FileShareWrite | FileShareDelete,
                IntPtr.Zero,
                OpenExisting,
                0,
                IntPtr.Zero))
            {
                if (handle.IsInvalid)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to open path: " + path);
                }

                StringBuilder buffer = new StringBuilder(1024);
                uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
                if (length == 0)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to resolve final path: " + path);
                }
                if (length >= buffer.Capacity)
                {
                    buffer = new StringBuilder((int)length + 1);
                    length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
                    if (length == 0 || length >= buffer.Capacity)
                    {
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to resolve final path: " + path);
                    }
                }
                return buffer.ToString();
            }
        }
    }
}
'@
}

function Get-FinalFileSystemPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $finalPath = [Huaguoshan.Runner.NativeFilePath]::GetFinalPath($resolvedPath)
    if ($finalPath.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $finalPath.Substring(8)
    }
    if ($finalPath.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        return $finalPath.Substring(4)
    }
    return $finalPath
}

$nodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $nodeCommand -or [string]::IsNullOrWhiteSpace($nodeCommand.Source)) {
    throw 'Node.js is required for the pinned offline Lua runner.'
}
if ([IO.Path]::GetExtension($nodeCommand.Source) -ine '.exe') {
    throw "Node.js must resolve to an executable file, not a PATH shim: $($nodeCommand.Source)"
}

$nodePath = Get-FinalFileSystemPath -Path $nodeCommand.Source
$nodeItem = Get-Item -LiteralPath $nodePath -Force -ErrorAction Stop
if ($nodeItem.PSIsContainer -or [IO.Path]::GetFileName($nodePath) -ine 'node.exe') {
    throw "Node.js resolved to an unexpected physical path: $nodePath"
}

$nodeSignature = Get-AuthenticodeSignature -LiteralPath $nodePath
$nodeSignerSubject = if ($nodeSignature.SignerCertificate) { [string]$nodeSignature.SignerCertificate.Subject } else { '' }
if ($nodeSignature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
    $nodeSignerSubject -notmatch '(?i)(^|,\s*)(CN|O)=(OpenJS Foundation|Node\.js Foundation)(,|$)') {
    throw "Node.js executable is not validly signed by the OpenJS/Node.js Foundation: $nodePath"
}

$nodeVersionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($nodePath)
if ($nodeVersionInfo.OriginalFilename -ine 'node.exe' -or $nodeVersionInfo.ProductName -ine 'Node.js' -or
    [string]::IsNullOrWhiteSpace($nodeVersionInfo.ProductVersion)) {
    throw "Node.js executable metadata is invalid: $nodePath"
}

$nodeIdentity = [pscustomobject]@{
    Path = $nodePath
    ProductVersion = [string]$nodeVersionInfo.ProductVersion
    Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $nodePath).Hash
    RuntimeVersion = $null
}

$powershellPath = Get-FinalFileSystemPath -Path $powershellPath
$gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$gitPath = if ($gitCommand -and -not [string]::IsNullOrWhiteSpace($gitCommand.Source)) {
    Get-FinalFileSystemPath -Path $gitCommand.Source
} else {
    $null
}

$controlledPathDirectories = New-Object 'Collections.Generic.List[string]'
foreach ($directory in @(
    (Split-Path -Parent $nodeIdentity.Path),
    (Split-Path -Parent $powershellPath),
    $(if ($gitPath) { Split-Path -Parent $gitPath })
)) {
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not $controlledPathDirectories.Contains($directory)) {
        $controlledPathDirectories.Add($directory)
    }
}
$env:PATH = $controlledPathDirectories -join [IO.Path]::PathSeparator
$env:PATHEXT = '.EXE'

function Assert-ControlledNodeIdentity {
    $unexpectedNodeEnvironment = @(Get-ChildItem Env: | Where-Object { $_.Name -match '^NODE_' })
    if ($unexpectedNodeEnvironment.Count -ne 0) {
        throw 'Controlled Node subprocess environment contains a NODE_* variable.'
    }

    $pathResolvedNode = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pathResolvedNode) {
        throw 'Controlled PATH no longer resolves the verified Node.js executable.'
    }
    $pathResolvedNodePhysicalPath = Get-FinalFileSystemPath -Path $pathResolvedNode.Source
    if ($pathResolvedNodePhysicalPath -ine $nodeIdentity.Path) {
        throw "Controlled PATH resolved a different Node.js executable: $pathResolvedNodePhysicalPath"
    }

    $currentVersionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($nodeIdentity.Path)
    $currentSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $nodeIdentity.Path).Hash
    if ([string]$currentVersionInfo.ProductVersion -cne $nodeIdentity.ProductVersion -or
        $currentSha256 -cne $nodeIdentity.Sha256) {
        throw "Verified Node.js executable identity changed during the runner: $($nodeIdentity.Path)"
    }
}

function Invoke-ControlledNode {
    param(
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [AllowNull()][string]$StandardInput,
        [switch]$PipeStandardInput
    )

    Assert-ControlledNodeIdentity
    if ($PipeStandardInput) {
        $output = $StandardInput | & $nodeIdentity.Path @ArgumentList 2>&1
    } else {
        $output = & $nodeIdentity.Path @ArgumentList 2>&1
    }
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

function Invoke-ControlledPowerShellFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$ArgumentList = @()
    )

    Assert-ControlledNodeIdentity
    $output = & $powershellPath -NoProfile -ExecutionPolicy Bypass -File $Path @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

$nodeVersionResult = Invoke-ControlledNode -ArgumentList @('--version')
$reportedNodeVersion = (($nodeVersionResult.Output | ForEach-Object { [string]$_ }) -join '').Trim()
if ($nodeVersionResult.ExitCode -ne 0 -or $reportedNodeVersion -cnotmatch '^v\d+\.\d+\.\d+$') {
    throw "Verified Node.js executable did not report a valid runtime version: $reportedNodeVersion"
}
$expectedNodeVersion = 'v{0}.{1}.{2}' -f $nodeVersionInfo.FileMajorPart, $nodeVersionInfo.FileMinorPart, $nodeVersionInfo.FileBuildPart
if ($reportedNodeVersion -cne $expectedNodeVersion) {
    throw "Node.js runtime version does not match signed executable metadata: expected $expectedNodeVersion, found $reportedNodeVersion"
}
$nodeIdentity.RuntimeVersion = $reportedNodeVersion

function Test-ControlledNodeSubprocessEnvironment {
    $probe = @'
const fs = require("fs");

if (Object.prototype.hasOwnProperty.call(process.env, "NODE_OPTIONS") ||
    Object.prototype.hasOwnProperty.call(process.env, "NODE_PATH")) {
    throw new Error("controlled Node environment retained NODE_OPTIONS or NODE_PATH");
}

try {
    require("huaguoshan-runner-node-path-probe");
    throw new Error("NODE_PATH changed controlled module resolution");
} catch (error) {
    if (!error || error.code !== "MODULE_NOT_FOUND") throw error;
}

const realpath = fs.realpathSync.native || fs.realpathSync;
process.stdout.write(JSON.stringify({
    execPath: realpath(process.execPath),
    version: process.version
}));
'@
    $probeResult = Invoke-ControlledNode -ArgumentList @('-') -StandardInput $probe -PipeStandardInput
    $probeOutput = ($probeResult.Output | ForEach-Object { [string]$_ }) -join ''
    if ($probeResult.ExitCode -ne 0) {
        throw "Controlled Node subprocess environment probe failed: $probeOutput"
    }
    try {
        $probeIdentity = $probeOutput | ConvertFrom-Json
    } catch {
        throw "Controlled Node subprocess environment probe returned invalid output: $probeOutput"
    }
    $probePhysicalPath = Get-FinalFileSystemPath -Path ([string]$probeIdentity.execPath)
    if ($probePhysicalPath -ine $nodeIdentity.Path -or [string]$probeIdentity.version -cne $nodeIdentity.RuntimeVersion) {
        throw "Controlled Node subprocess used an unexpected executable identity: $probeOutput"
    }
    Write-Output 'PASS: controlled Node subprocess environment rejects NODE_OPTIONS and NODE_PATH injection.'
}

if ($NodeIntegritySelfTestOnly) {
    Test-ControlledNodeSubprocessEnvironment
    return
}

Write-Output "Using verified Node.js $($nodeIdentity.RuntimeVersion) at $($nodeIdentity.Path) (SHA-256 $($nodeIdentity.Sha256))."
Test-ControlledNodeSubprocessEnvironment
$pinnedFengariVersion = '0.1.0'
$pinnedFengariSnapshot = '41ec8406e7a68140b8436c01df2bb294a02c6dc5111f463b8777f1ec3b7eef50'
$pinnedFengariClosureSha256 = 'E8E88EFDB5BEFFE0F140BA72EDDCEC5E1B52D7788062A9FCF0E09F6988745AF4'

$nodeModulesClosureHasher = @'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(process.argv[2]);
const rootStat = fs.lstatSync(root);
if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) {
    throw new Error(`closure root must be a physical directory: ${root}`);
}

const hash = crypto.createHash("sha256");
const activeDirectories = new Set();
const realpath = fs.realpathSync.native || fs.realpathSync;
const writeRecord = (kind, logicalPath, payload) => {
    hash.update(kind, "utf8");
    hash.update("\0", "utf8");
    hash.update(logicalPath, "utf8");
    hash.update("\0", "utf8");
    if (payload) hash.update(payload);
    hash.update("\n", "utf8");
};

function walkDirectory(physicalPath, logicalPath) {
    const resolvedDirectory = realpath(physicalPath);
    const cycleKey = process.platform === "win32" ? resolvedDirectory.toLowerCase() : resolvedDirectory;
    if (activeDirectories.has(cycleKey)) {
        throw new Error(`reparse cycle in dependency closure at ${logicalPath}`);
    }

    activeDirectories.add(cycleKey);
    writeRecord("D", logicalPath);
    const names = fs.readdirSync(resolvedDirectory).sort((left, right) =>
        left < right ? -1 : left > right ? 1 : 0
    );
    for (const name of names) {
        const childLogicalPath = logicalPath ? `${logicalPath}/${name}` : name;
        walk(path.join(resolvedDirectory, name), childLogicalPath);
    }
    activeDirectories.delete(cycleKey);
}

function walk(physicalPath, logicalPath) {
    const stat = fs.lstatSync(physicalPath);
    if (stat.isSymbolicLink()) {
        writeRecord("L", logicalPath);
        const resolvedTarget = realpath(physicalPath);
        const targetStat = fs.statSync(physicalPath);
        if (targetStat.isDirectory()) {
            walkDirectory(resolvedTarget, logicalPath);
            return;
        }
        if (targetStat.isFile()) {
            const content = fs.readFileSync(resolvedTarget);
            writeRecord("F", logicalPath, Buffer.concat([Buffer.from(String(content.length) + "\0"), content]));
            return;
        }
        throw new Error(`unsupported reparse target in dependency closure: ${logicalPath}`);
    }
    if (stat.isDirectory()) {
        walkDirectory(physicalPath, logicalPath);
        return;
    }
    if (stat.isFile()) {
        const content = fs.readFileSync(physicalPath);
        writeRecord("F", logicalPath, Buffer.concat([Buffer.from(String(content.length) + "\0"), content]));
        return;
    }
    throw new Error(`unsupported filesystem entry in dependency closure: ${logicalPath}`);
}

walkDirectory(root, "");
process.stdout.write(hash.digest("hex").toUpperCase());
'@

function Get-NodeModulesClosureSha256 {
    param([string]$NodeModulesRoot)

    $nodeResult = Invoke-ControlledNode -ArgumentList @('-', $NodeModulesRoot) -StandardInput $nodeModulesClosureHasher -PipeStandardInput
    $output = $nodeResult.Output
    $exitCode = $nodeResult.ExitCode
    $hash = ($output | ForEach-Object { [string]$_ }) -join ''
    if ($exitCode -ne 0 -or $hash -cnotmatch '^[0-9A-F]{64}$') {
        throw "Unable to hash the Node resolver closure at $NodeModulesRoot`: $hash"
    }
    return $hash
}

function Test-NodeModulesClosureSha256CoversResolvedReparseTargets {
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('huaguoshan-runner-integrity-' + [guid]::NewGuid().ToString('N'))
    try {
        $nodeModulesRoot = Join-Path $fixtureRoot 'snapshot\node_modules'
        $cliRoot = Join-Path $nodeModulesRoot 'fengari-node-cli'
        $dependencyRoot = Join-Path $fixtureRoot 'store\fengari'
        $dependencyLink = Join-Path $nodeModulesRoot 'fengari'
        $dependencyPath = Join-Path $dependencyRoot 'index.js'
        New-Item -ItemType Directory -Path (Join-Path $cliRoot 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path $dependencyRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cliRoot 'package.json') -Encoding UTF8 -Value '{"name":"fengari-node-cli","version":"0.1.0"}'
        Set-Content -LiteralPath (Join-Path $cliRoot 'src\lua-cli.js') -Encoding UTF8 -Value 'module.exports = require("fengari")'
        Set-Content -LiteralPath (Join-Path $dependencyRoot 'package.json') -Encoding UTF8 -Value '{"name":"fengari","version":"0.1.5","main":"index.js"}'
        Set-Content -LiteralPath $dependencyPath -Encoding UTF8 -Value 'module.exports = 1'
        New-Item -ItemType Junction -Path $dependencyLink -Target $dependencyRoot | Out-Null

        $resolver = 'const fs=require("fs");const value=require.resolve(process.argv[3],{paths:[process.argv[2]]});process.stdout.write((fs.realpathSync.native||fs.realpathSync)(value));'
        $resolverResult = Invoke-ControlledNode -ArgumentList @('-', (Join-Path $cliRoot 'src'), 'fengari') -StandardInput $resolver -PipeStandardInput
        $resolvedDependency = ($resolverResult.Output | ForEach-Object { [string]$_ }) -join ''
        if ($resolverResult.ExitCode -ne 0 -or [IO.Path]::GetFullPath($resolvedDependency) -cne [IO.Path]::GetFullPath($dependencyPath)) {
            throw "Node fixture did not resolve fengari through the parent node_modules reparse point: $resolvedDependency"
        }

        $before = Get-NodeModulesClosureSha256 -NodeModulesRoot $nodeModulesRoot
        Set-Content -LiteralPath $dependencyPath -Encoding UTF8 -Value 'module.exports = 2'
        $after = Get-NodeModulesClosureSha256 -NodeModulesRoot $nodeModulesRoot
        if ($before -ceq $after) {
            throw 'Pinned Lua runner closure hash must change when a resolved reparse target changes.'
        }
        Write-Output 'PASS: pinned Lua runner closure hash covers Node-resolved reparse targets.'
    }
    finally {
        if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    }
}

function Assert-PinnedFengariCli {
    param([string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $expectedSuffix = '[\\/]fengari-node-cli[\\/]' + [regex]::Escape($pinnedFengariVersion) +
        '[\\/]' + $pinnedFengariSnapshot +
        '[\\/]node_modules[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$'
    if ($resolvedPath -notmatch $expectedSuffix) {
        throw "Unpinned fengari-node-cli cache entry: $resolvedPath"
    }

    $packageRoot = Split-Path -Parent (Split-Path -Parent $resolvedPath)
    $manifestPath = Join-Path $packageRoot 'package.json'
    try {
        $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    }
    catch {
        throw "Unreadable fengari-node-cli manifest at $manifestPath`: $($_.Exception.Message)"
    }
    if ([string]$manifest.name -cne 'fengari-node-cli' -or [string]$manifest.version -cne $pinnedFengariVersion) {
        throw "Unexpected Fengari package identity at $manifestPath"
    }

    $nodeModulesRoot = Split-Path -Parent $packageRoot
    $closureSha256 = Get-NodeModulesClosureSha256 -NodeModulesRoot $nodeModulesRoot
    if ($closureSha256 -cne $pinnedFengariClosureSha256) {
        throw "fengari-node-cli resolver closure integrity mismatch at $nodeModulesRoot`: expected $pinnedFengariClosureSha256, found $closureSha256"
    }
    return $resolvedPath
}

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'LOCALAPPDATA is required to locate the pinned offline Lua runner cache.'
}
Test-NodeModulesClosureSha256CoversResolvedReparseTargets
$pnpmStore = Join-Path $env:LOCALAPPDATA 'pnpm\store'
$cachedFengariCliPaths = @(
    Get-ChildItem -LiteralPath $pnpmStore -Recurse -File -Filter 'lua-cli.js' -ErrorAction Stop |
        Where-Object { $_.FullName -match '[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$' } |
        Sort-Object -Property FullName |
        Select-Object -ExpandProperty FullName
)
if ($cachedFengariCliPaths.Count -eq 0) {
    throw "Pinned fengari-node-cli $pinnedFengariVersion snapshot $pinnedFengariSnapshot is not available offline."
}

$validatedFengariCliPaths = @($cachedFengariCliPaths | ForEach-Object { Assert-PinnedFengariCli -Path $_ })
$fengariCli = $validatedFengariCliPaths[0]
Write-Output "Using pinned offline Lua runner: fengari-node-cli $pinnedFengariVersion ($pinnedFengariSnapshot)."

$luaTestContracts = [ordered]@{
    'implementation/huaguoshan/tests/test_map_binding.lua' = [pscustomobject]@{
        PassLine = 'PASS: 196 map binding assertions'
        SourceSha256 = '145033C95F9A28A9CE8D149C16848B57304916B5C91666BB3C148A1F7AAB256B'
    }
    'implementation/huaguoshan/tests/test_public_trace.lua' = [pscustomobject]@{
        PassLine = 'PASS: 60 public trace assertions'
        SourceSha256 = 'D9F5292C78112EA4C01AE95A8CF5F1675681C7F4B5FC94557007906D8FF4215E'
    }
    'implementation/huaguoshan/tests/test_public_boss.lua' = [pscustomobject]@{
        PassLine = 'PASS: 214 public boss assertions'
        SourceSha256 = '56466FD63A3D6D32F2FA4BAEF7D541A30A4518BE74250688ACF49A766D16EC99'
    }
    'implementation/huaguoshan/tests/test_instances.lua' = [pscustomobject]@{
        PassLine = 'PASS: 327 instance assertions'
        SourceSha256 = '2900245C3924DC3EA0A87ED7AE9979CDBC4A20659A58DF75754446816A155E8E'
    }
    'implementation/huaguoshan/tests/test_controller.lua' = [pscustomobject]@{
        PassLine = 'PASS: 330 controller assertions'
        SourceSha256 = '9CAB23720F7B70EEBDD856FF313C716E9461FBAD2A2DF2A610C606877D684853'
    }
    'implementation/huaguoshan/tests/test_controller_runtime_adapter.lua' = [pscustomobject]@{
        PassLine = 'PASS: 100 controller runtime adapter assertions'
        SourceSha256 = 'F993425877A78B39EC63FB60F6DF92A46A419477E5E52B56728A276851EAF3F6'
    }
    'implementation/huaguoshan/tests/test_runtime.lua' = [pscustomobject]@{
        PassLine = 'PASS: 113 runtime assertions'
        SourceSha256 = '462180E16501DD6D5CBD84D63DF26324E43350B15E4A05CD034621B0EBC9A014'
    }
    'implementation/huaguoshan/tests/test_controller_runtime_adapter_integration.lua' = [pscustomobject]@{
        PassLine = 'PASS: 108 controller runtime adapter integration assertions'
        SourceSha256 = 'EF236BA8D0BF161E07B46AF10DD84AD11077F54565F4B8BFC4607BF6A09AAC83'
    }
}

function Test-LuaPassOutput {
    param(
        [object[]]$Output,
        [string]$ExpectedPassLine
    )

    $nonEmptyLines = @($Output |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($nonEmptyLines.Count -ne 1) { return $false }
    return $nonEmptyLines[0] -ceq $ExpectedPassLine
}

if (Test-LuaPassOutput -Output @('PASS: 1 runtime assertions') -ExpectedPassLine 'PASS: 105 runtime assertions') { throw 'Lua PASS gate accepted a self-reported but uncontracted assertion result.' }
if (-not (Test-LuaPassOutput -Output @('PASS: 105 runtime assertions') -ExpectedPassLine 'PASS: 105 runtime assertions')) { throw 'Lua PASS gate rejected its exact expected result.' }
if (Test-LuaPassOutput -Output @('PASS: 105 runtime assertions', 'unexpected output') -ExpectedPassLine 'PASS: 105 runtime assertions') { throw 'Lua PASS gate accepted extra output.' }

function Invoke-LuaTest {
    param(
        [string]$Path,
        [pscustomobject]$Contract
    )

    $actualSourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    if ($actualSourceSha256 -cne $Contract.SourceSha256) {
        throw "Lua test source integrity mismatch for $Path`: expected $($Contract.SourceSha256), found $actualSourceSha256"
    }
    $nodeResult = Invoke-ControlledNode -ArgumentList @($fengariCli, $Path)
    $output = $nodeResult.Output
    $exitCode = $nodeResult.ExitCode
    $output | Write-Output
    if ($exitCode -ne 0 -or -not (Test-LuaPassOutput -Output @($output) -ExpectedPassLine $Contract.PassLine) -or $output -match 'stack traceback') {
        throw "Lua test failed for $Path with exit code $exitCode; expected exactly one verified result line: $($Contract.PassLine)"
    }
}

function Invoke-OfflineApiIsolationGate {
    param([string]$PackageRoot)

    $result = Invoke-ControlledPowerShellFile -Path (Join-Path $PSScriptRoot 'verify-y3-api.ps1') -ArgumentList @('-PackageRoot', $PackageRoot)
    $result.Output | Write-Output
    if ($result.ExitCode -ne 0) { throw "offline API isolation check failed for $PackageRoot" }
}

function Invoke-RunnerPowerShellTest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $result = Invoke-ControlledPowerShellFile -Path $Path
    $result.Output | Write-Output
    if ($result.ExitCode -ne 0) { throw $FailureMessage }
}

function Test-RunAllOfflineApiIsolationLexerPath {
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('huaguoshan-run-all-api-isolation-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'lua') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'tests') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'y3-api-baseline.json') -Destination (Join-Path $fixtureRoot 'tests\y3-api-baseline.json')
        $fixtureSource = @'
-- y3.nonexistent()
-- GameAPI.nonexistent()
local ordinary_text = "GlobalAPI.nonexistent(); CAPI.nonexistent()"
return ordinary_text
'@
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'lua\comments-and-strings.lua') -Encoding UTF8 -Value $fixtureSource
        Invoke-OfflineApiIsolationGate -PackageRoot $fixtureRoot
        Write-Output 'PASS: run-all offline API isolation path ignores restricted text in Lua comments and strings.'
    }
    finally {
        if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    }
}

Push-Location $projectRoot
try {
    Invoke-RunnerPowerShellTest -Path (Join-Path $PSScriptRoot 'test-runner-integrity.ps1') -FailureMessage 'runner integrity regression failed'
    Invoke-RunnerPowerShellTest -Path (Join-Path $PSScriptRoot 'preflight.ps1') -FailureMessage 'preflight failed'
    Invoke-RunnerPowerShellTest -Path (Join-Path $PSScriptRoot 'test-preflight.ps1') -FailureMessage 'preflight reference tests failed'
    Invoke-RunnerPowerShellTest -Path (Join-Path $PSScriptRoot 'test-map-binding.ps1') -FailureMessage 'map binding tests failed'
    Invoke-RunnerPowerShellTest -Path (Join-Path $PSScriptRoot 'test-config-binding-parity.ps1') -FailureMessage 'configuration and map binding parity tests failed'
    Invoke-RunnerPowerShellTest -Path (Join-Path $PSScriptRoot 'test-materializer.ps1') -FailureMessage 'materializer tests failed'
    foreach ($path in $luaTestContracts.Keys) {
        Invoke-LuaTest -Path $path -Contract $luaTestContracts[$path]
    }
    Invoke-RunnerPowerShellTest -Path (Join-Path $PSScriptRoot 'test-y3-api-baseline.ps1') -FailureMessage 'offline API isolation tests failed'
    Test-RunAllOfflineApiIsolationLexerPath
    Invoke-OfflineApiIsolationGate -PackageRoot (Join-Path $projectRoot 'implementation\huaguoshan')
    Write-Output 'PASS: Huaguoshan offline object, encounter runtime, and map-binding package.'
} finally { Pop-Location }
}
finally {
    Get-ChildItem Env: | Where-Object { $_.Name -match '^NODE_' } | ForEach-Object {
        [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
    }
    foreach ($entry in $originalNodeEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable([string]$entry.Key, [string]$entry.Value, 'Process')
    }
    [Environment]::SetEnvironmentVariable('PATH', $originalPath, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', $originalPathExt, 'Process')
}
