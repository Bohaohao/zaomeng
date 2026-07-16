$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $PSScriptRoot).Path

$unsupportedHostMessage = 'This offline preconstruction entry point supports only Windows PowerShell powershell.exe.'
if ([string]$PSVersionTable.PSEdition -cne 'Desktop') {
    throw "$unsupportedHostMessage Current edition: $([string]$PSVersionTable.PSEdition)"
}

$currentHostPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ([string]::IsNullOrWhiteSpace($currentHostPath) -or -not [IO.Path]::IsPathRooted($currentHostPath)) {
    throw "$unsupportedHostMessage Unable to determine the absolute path of the current PowerShell host."
}
$resolvedHostPath = (Resolve-Path -LiteralPath $currentHostPath -ErrorAction Stop).Path
$powershellHostItem = Get-Item -LiteralPath $resolvedHostPath -Force -ErrorAction Stop
if ($powershellHostItem.PSIsContainer -or
    [IO.Path]::GetExtension($resolvedHostPath) -ine '.exe' -or
    $powershellHostItem.Name -ine 'powershell.exe') {
    throw "$unsupportedHostMessage Current host is '$($powershellHostItem.Name)' at '$resolvedHostPath'."
}

$originalPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
$originalPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
$originalNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
$originalNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')

if (-not ('Preconstruction.Runner.NativeFilePath' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Preconstruction.Runner
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
    $finalPath = [Preconstruction.Runner.NativeFilePath]::GetFinalPath($resolvedPath)
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

$childExitCode = 0
try {
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $null, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $null, 'Process')

    $powershellHostPath = Get-FinalFileSystemPath -Path $resolvedHostPath
    $trustedNode = Get-TrustedNodeExecutable -PathValue $originalPath
    $hostDirectory = Split-Path -Parent $powershellHostPath
    $controlledPathEntries = New-Object 'Collections.Generic.List[string]'
    foreach ($directory in @($hostDirectory, $trustedNode.Directory)) {
        if (-not $controlledPathEntries.Contains($directory)) {
            $controlledPathEntries.Add($directory)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($originalPath)) {
        foreach ($entry in $originalPath.Split([IO.Path]::PathSeparator)) {
            $normalizedEntry = $entry.Trim().Trim([char]'"')
            if ([string]::IsNullOrWhiteSpace($normalizedEntry)) { continue }
            $expandedEntry = [Environment]::ExpandEnvironmentVariables($normalizedEntry)
            if ($expandedEntry -ine $trustedNode.Directory -and
                $expandedEntry -ine $hostDirectory -and
                -not $controlledPathEntries.Contains($expandedEntry)) {
                $controlledPathEntries.Add($expandedEntry)
            }
        }
    }

    $suitePaths = @(
        (Join-Path $root 'test-run-all-preconstruction-integrity.ps1'),
        (Join-Path $root 'run-all-professions.ps1'),
        (Join-Path $root 'huaguoshan\tests\run-all.ps1')
    )

    [Environment]::SetEnvironmentVariable('PATH', ($controlledPathEntries -join [IO.Path]::PathSeparator), 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', '.EXE', 'Process')
    foreach ($suitePath in $suitePaths) {
        & $powershellHostPath -NoProfile -ExecutionPolicy Bypass -File $suitePath
        $suiteExitCode = $LASTEXITCODE
        if ($suiteExitCode -ne 0) {
            $childExitCode = $suiteExitCode
            break
        }
    }
}
finally {
    [Environment]::SetEnvironmentVariable('PATH', $originalPath, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', $originalPathExt, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $originalNodeOptions, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $originalNodePath, 'Process')
}

if ($childExitCode -ne 0) { exit $childExitCode }

Write-Output 'PASS: profession and Huaguoshan offline preconstruction packages.'
