param([string]$PnpmPath)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Resolve-SupportedWindowsPowerShellPath {
    param(
        [AllowNull()][string]$HostPath,
        [AllowNull()][string]$PowerShellEdition
    )

    $unsupportedHostMessage = 'The profession runner supports only Windows PowerShell powershell.exe.'
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

$currentHostPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$resolvedHostPath = Resolve-SupportedWindowsPowerShellPath `
    -HostPath $currentHostPath `
    -PowerShellEdition ([string]$PSVersionTable.PSEdition)

$originalPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
$originalPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
$originalNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
$originalNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')

if (-not ('ProfessionRunner.Trust.NativeFilePath' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace ProfessionRunner.Trust
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
    $finalPath = [ProfessionRunner.Trust.NativeFilePath]::GetFinalPath($resolvedPath)
    if ($finalPath.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $finalPath.Substring(8)
    }
    if ($finalPath.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        return $finalPath.Substring(4)
    }
    return $finalPath
}

function Get-TrustedNodeExecutable {
    param([AllowNull()][string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        throw 'The original process PATH is empty; a trusted node.exe cannot be resolved.'
    }

    $seenPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $rejections = New-Object 'Collections.Generic.List[string]'
    foreach ($entry in $PathValue.Split([IO.Path]::PathSeparator)) {
        $candidatePath = $null
        $directory = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim([char]'"'))
        if ([string]::IsNullOrWhiteSpace($directory)) { continue }

        try {
            $candidatePath = Join-Path $directory 'node.exe'
            if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }

            $nodePath = Get-FinalFileSystemPath -Path $candidatePath
            if (-not $seenPaths.Add($nodePath)) { continue }

            $nodeItem = Get-Item -LiteralPath $nodePath -Force -ErrorAction Stop
            if ($nodeItem.PSIsContainer -or
                [IO.Path]::GetExtension($nodePath) -ine '.exe' -or
                [IO.Path]::GetFileName($nodePath) -ine 'node.exe') {
                throw "resolved to an unexpected physical file: $nodePath"
            }

            $nodeSignature = Get-AuthenticodeSignature -LiteralPath $nodePath
            $nodeSignerSubject = if ($nodeSignature.SignerCertificate) { [string]$nodeSignature.SignerCertificate.Subject } else { '' }
            if ($nodeSignature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
                $nodeSignerSubject -notmatch '(?i)(^|,\s*)(CN|O)=(OpenJS Foundation|Node\.js Foundation)(,|$)') {
                throw 'does not have a valid OpenJS/Node.js Foundation signature'
            }

            $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($nodePath)
            if ($versionInfo.OriginalFilename -ine 'node.exe' -or
                $versionInfo.ProductName -ine 'Node.js' -or
                [string]$versionInfo.ProductVersion -cnotmatch '^\d+\.\d+\.\d+$' -or
                $versionInfo.FileMajorPart -le 0) {
                throw 'has invalid Node.js product or version metadata'
            }

            $metadataVersion = '{0}.{1}.{2}' -f $versionInfo.FileMajorPart, $versionInfo.FileMinorPart, $versionInfo.FileBuildPart
            if ([string]$versionInfo.ProductVersion -cne $metadataVersion) {
                throw "has inconsistent version metadata: product $($versionInfo.ProductVersion), file $metadataVersion"
            }

            $runtimeOutput = & $nodePath --version 2>&1
            $runtimeExitCode = $LASTEXITCODE
            $runtimeVersion = (($runtimeOutput | ForEach-Object { [string]$_ }) -join '').Trim()
            $expectedRuntimeVersion = 'v' + $metadataVersion
            if ($runtimeExitCode -ne 0 -or $runtimeVersion -cne $expectedRuntimeVersion) {
                throw "reports runtime version '$runtimeVersion', expected '$expectedRuntimeVersion'"
            }

            return [pscustomobject]@{
                Path = $nodePath
                Directory = Split-Path -Parent $nodePath
                Version = $runtimeVersion
                Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $nodePath).Hash
            }
        }
        catch {
            if ($candidatePath) {
                $rejections.Add("$candidatePath - $($_.Exception.Message)")
            }
        }
    }

    $details = if ($rejections.Count -gt 0) { ' Rejected candidates: ' + ($rejections -join '; ') } else { '' }
    throw "No trusted, signed Node.js node.exe was found on the original process PATH.$details"
}

function Get-ControlledPathValue {
    param(
        [Parameter(Mandatory = $true)][string[]]$PinnedDirectories,
        [AllowNull()][string]$OriginalPath
    )

    $entries = New-Object 'Collections.Generic.List[string]'
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $candidates = New-Object 'Collections.Generic.List[string]'
    foreach ($directory in $PinnedDirectories) { $candidates.Add($directory) }
    if (-not [string]::IsNullOrWhiteSpace($OriginalPath)) {
        foreach ($entry in $OriginalPath.Split([IO.Path]::PathSeparator)) { $candidates.Add($entry) }
    }

    foreach ($candidate in $candidates) {
        $normalized = [Environment]::ExpandEnvironmentVariables(([string]$candidate).Trim().Trim([char]'"'))
        if ([string]::IsNullOrWhiteSpace($normalized) -or -not [IO.Path]::IsPathRooted($normalized)) { continue }
        try { $normalized = [IO.Path]::GetFullPath($normalized) } catch { continue }
        if ($seen.Add($normalized)) { $entries.Add($normalized) }
    }
    return $entries -join [IO.Path]::PathSeparator
}

function Invoke-TrustedNode {
    param(
        [Parameter(Mandatory = $true)][string]$NodePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [AllowNull()][string]$StandardInput,
        [switch]$PipeStandardInput
    )

    if ($PipeStandardInput) {
        $output = $StandardInput | & $NodePath @ArgumentList 2>&1
    }
    else {
        $output = & $NodePath @ArgumentList 2>&1
    }
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

function Assert-ControlledNodeEnvironment {
    param([Parameter(Mandatory = $true)][string]$NodePath)

    $probe = @'
if (Object.prototype.hasOwnProperty.call(process.env, "NODE_OPTIONS") ||
    Object.prototype.hasOwnProperty.call(process.env, "NODE_PATH")) {
    throw new Error("controlled Node environment retained NODE_OPTIONS or NODE_PATH");
}

try {
    require("profession-runner-node-path-probe");
    throw new Error("NODE_PATH changed controlled module resolution");
} catch (error) {
    if (!error || error.code !== "MODULE_NOT_FOUND") throw error;
}
'@
    $result = Invoke-TrustedNode `
        -NodePath $NodePath `
        -ArgumentList @('-') `
        -StandardInput $probe `
        -PipeStandardInput
    $outputText = ($result.Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($result.ExitCode -ne 0 -or $result.Output.Count -ne 0) {
        throw "Controlled Node environment probe failed: $outputText"
    }
}

$pinnedFengariVersion = '0.1.0'
$pinnedFengariSnapshot = '41ec8406e7a68140b8436c01df2bb294a02c6dc5111f463b8777f1ec3b7eef50'
$pinnedFengariClosureSha256 = 'E8E88EFDB5BEFFE0F140BA72EDDCEC5E1B52D7788062A9FCF0E09F6988745AF4'
$expectedCommonPassLine = 'PASS: 27 common assertions'
$expectedCommonSourceSha256 = '6F54E3D03C9D8E78BD2349FEC0BB5586A826201B63C7E85AA2F49E59ACE1D2E9'

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
    param(
        [Parameter(Mandatory = $true)][string]$NodePath,
        [Parameter(Mandatory = $true)][string]$NodeModulesRoot
    )

    $result = Invoke-TrustedNode `
        -NodePath $NodePath `
        -ArgumentList @('-', $NodeModulesRoot) `
        -StandardInput $nodeModulesClosureHasher `
        -PipeStandardInput
    $hash = ($result.Output | ForEach-Object { [string]$_ }) -join ''
    if ($result.ExitCode -ne 0 -or $hash -cnotmatch '^[0-9A-F]{64}$') {
        throw "Unable to hash the Node resolver closure at $NodeModulesRoot`: $hash"
    }
    return $hash
}

function Resolve-PinnedFengariCli {
    param([Parameter(Mandatory = $true)][string]$NodePath)

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is required to locate the pinned offline Lua runner cache.'
    }

    $pnpmStore = Join-Path $env:LOCALAPPDATA 'pnpm\store'
    $expectedSuffix = '[\\/]fengari-node-cli[\\/]' + [regex]::Escape($pinnedFengariVersion) +
        '[\\/]' + $pinnedFengariSnapshot +
        '[\\/]node_modules[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$'
    $pinnedCandidates = @(
        Get-ChildItem -LiteralPath $pnpmStore -Recurse -File -Filter 'lua-cli.js' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match $expectedSuffix } |
            Sort-Object -Property FullName |
            Select-Object -ExpandProperty FullName
    )
    if ($pinnedCandidates.Count -ne 1) {
        throw "Expected exactly one pinned fengari-node-cli $pinnedFengariVersion snapshot $pinnedFengariSnapshot; found $($pinnedCandidates.Count)."
    }

    $resolvedPath = (Resolve-Path -LiteralPath $pinnedCandidates[0] -ErrorAction Stop).Path
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
    $closureSha256 = Get-NodeModulesClosureSha256 -NodePath $NodePath -NodeModulesRoot $nodeModulesRoot
    if ($closureSha256 -cne $pinnedFengariClosureSha256) {
        throw "fengari-node-cli resolver closure integrity mismatch at $nodeModulesRoot`: expected $pinnedFengariClosureSha256, found $closureSha256"
    }
    return $resolvedPath
}

function Test-ExactCommonPassOutput {
    param([object[]]$Output)

    $lines = @($Output | ForEach-Object { [string]$_ })
    return $lines.Count -eq 1 -and $lines[0] -ceq $expectedCommonPassLine
}

$professionSuites = [ordered]@{
    Powang = '.\implementation\powang\tests\run-all.ps1'
    Zhenjie = '.\implementation\zhenjie\tests\run-all.ps1'
    Chiming = '.\implementation\chiming\tests\run-all.ps1'
    Xunlie = '.\implementation\xunlie\tests\run-all.ps1'
}
$childExitCode = 0

try {
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $null, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $null, 'Process')

    $powershellHostPath = Get-FinalFileSystemPath -Path $resolvedHostPath
    $trustedNode = Get-TrustedNodeExecutable -PathValue $originalPath
    $controlledPath = Get-ControlledPathValue `
        -PinnedDirectories @((Split-Path -Parent $powershellHostPath), $trustedNode.Directory) `
        -OriginalPath $originalPath
    [Environment]::SetEnvironmentVariable('PATH', $controlledPath, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', '.EXE', 'Process')
    Assert-ControlledNodeEnvironment -NodePath $trustedNode.Path

    Push-Location $root
    try {
        foreach ($suite in $professionSuites.GetEnumerator()) {
            $suiteArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $suite.Value)
            if ($PnpmPath) { $suiteArgs += @('-PnpmPath', $PnpmPath) }
            & $powershellHostPath @suiteArgs
            $suiteExitCode = $LASTEXITCODE
            if ($suiteExitCode -ne 0) {
                $childExitCode = $suiteExitCode
                break
            }
        }

        if ($childExitCode -eq 0) {
            $commonTestPath = Join-Path $root 'implementation\profession_common\tests\test_common.lua'
            $actualCommonSourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $commonTestPath).Hash
            if ($actualCommonSourceSha256 -cne $expectedCommonSourceSha256) {
                throw "Profession common Lua source integrity mismatch at $commonTestPath`: expected $expectedCommonSourceSha256, found $actualCommonSourceSha256"
            }

            $fengariCli = Resolve-PinnedFengariCli -NodePath $trustedNode.Path
            $result = Invoke-TrustedNode -NodePath $trustedNode.Path -ArgumentList @($fengariCli, $commonTestPath)
            $result.Output | Write-Output
            if ($result.ExitCode -ne 0) {
                $childExitCode = $result.ExitCode
            }
            elseif (-not (Test-ExactCommonPassOutput -Output $result.Output)) {
                $actualOutput = ($result.Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
                throw "Profession common tests must emit exactly '$expectedCommonPassLine' and no other output; found: $actualOutput"
            }
        }

        if ($childExitCode -eq 0) {
            Write-Output 'PASS: C01/C02/C03/C04 cross-profession offline construction packages.'
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    [Environment]::SetEnvironmentVariable('PATH', $originalPath, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', $originalPathExt, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $originalNodeOptions, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $originalNodePath, 'Process')
}

if ($childExitCode -ne 0) { exit $childExitCode }
