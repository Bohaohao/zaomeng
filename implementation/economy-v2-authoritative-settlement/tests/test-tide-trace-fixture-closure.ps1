[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$IsolationVerifier,
    [switch]$SkipIsolationScan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Assertions = 0

function Assert-Condition {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    $script:Assertions++
    if (-not $Condition) { throw $Message }
}

function Test-PathWithin {
    param([Parameter(Mandatory = $true)][string]$Parent, [Parameter(Mandatory = $true)][string]$Candidate)
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    return $candidateFull.StartsWith($parentFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-PhysicalPathUnderRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-Condition (Test-PathWithin -Parent $Root -Candidate $Candidate) "$Label escapes its trusted root"
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    $relative = $candidateFull.Substring($rootFull.Length).TrimStart('\', '/')
    $cursor = $rootFull
    foreach ($segment in $relative.Split(@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $segment
        $item = Get-Item -Force -LiteralPath $cursor -ErrorAction Stop
        Assert-Condition (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "$Label traverses a reparse point: $cursor"
    }
}

function Get-Sha256Lower {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}

function Get-ClosureDigest {
    param([Parameter(Mandatory = $true)][object[]]$Records)
    $builder = [Text.StringBuilder]::new()
    foreach ($record in @($Records | Sort-Object -Property path)) {
        [void]$builder.Append([string]$record.path)
        [void]$builder.Append([char]0)
        [void]$builder.Append(([string]$record.sha256).ToLowerInvariant())
        [void]$builder.Append([char]10)
    }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return (($algorithm.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($builder.ToString())) |
            ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $algorithm.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Split-Path -Parent $PSScriptRoot
}
$packageRoot = (Resolve-Path -LiteralPath $PackageRoot -ErrorAction Stop).Path
$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $packageRoot '..\..') -ErrorAction Stop).Path
$huaguoshanRoot = (Resolve-Path -LiteralPath (Join-Path $workspaceRoot 'implementation\huaguoshan') -ErrorAction Stop).Path
$manifestPath = Join-Path $packageRoot 'contract\tide-trace-fixture-closure.json'
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json

Assert-Condition ($manifest.schema_version -eq 1) 'fixture closure manifest schema_version must be 1'
Assert-Condition ($manifest.contract_id -eq 'ECO_V2_TIDE_TRACE_FIXTURE_CLOSURE_V1') 'fixture closure manifest contract id drifted'
Assert-Condition ($manifest.runtime_handoff -eq $false -and $manifest.production_gate -eq 'closed') 'fixture closure must remain offline-only'
Assert-Condition ($manifest.closure_hash_contract.algorithm -eq 'SHA-256') 'fixture closure digest algorithm drifted'
Assert-Condition ($manifest.closure_hash_contract.record_encoding -eq 'UTF-8 without BOM') 'fixture closure digest encoding drifted'

$expectedRoles = @{
    '../huaguoshan/lua/huaguoshan_config.lua' = 'fixture_lua'
    '../huaguoshan/lua/huaguoshan_contribution.lua' = 'fixture_lua'
    '../huaguoshan/lua/huaguoshan_instances.lua' = 'fixture_lua'
    '../huaguoshan/lua/huaguoshan_map_binding.lua' = 'fixture_lua'
    '../huaguoshan/lua/huaguoshan_public_boss.lua' = 'fixture_lua'
    '../huaguoshan/lua/huaguoshan_public_trace.lua' = 'fixture_lua'
    '../huaguoshan/lua/huaguoshan_runtime.lua' = 'fixture_lua'
    '../huaguoshan/tests/fake_authority_provider.lua' = 'fixture_lua'
    '../huaguoshan/tests/verify-y3-api.ps1' = 'isolation_verifier'
}
$entries = @($manifest.closure_hash_contract.files)
Assert-Condition ($entries.Count -eq $expectedRoles.Count) 'fixture closure manifest file count drifted'
$seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$resolvedEntries = @()
foreach ($entry in $entries) {
    $relativePath = [string]$entry.path
    Assert-Condition ($expectedRoles.ContainsKey($relativePath)) "fixture closure has an undeclared path: $relativePath"
    Assert-Condition ($seenPaths.Add($relativePath)) "fixture closure has a duplicate path: $relativePath"
    Assert-Condition ([string]$entry.role -eq $expectedRoles[$relativePath]) "fixture closure role drifted: $relativePath"
    Assert-Condition ([string]$entry.sha256 -match '^[0-9A-F]{64}$') "fixture closure has an invalid SHA-256: $relativePath"
    $candidate = [IO.Path]::GetFullPath((Join-Path $packageRoot $relativePath))
    Assert-Condition (Test-PathWithin -Parent $huaguoshanRoot -Candidate $candidate) "fixture closure path is outside Huaguoshan: $relativePath"
    Assert-PhysicalPathUnderRoot -Root $workspaceRoot -Candidate $candidate -Label "fixture closure path $relativePath"
    $item = Get-Item -Force -LiteralPath $candidate -ErrorAction Stop
    Assert-Condition (-not $item.PSIsContainer) "fixture closure entry must be a file: $relativePath"
    Assert-Condition ((Get-Sha256Lower -Path $candidate) -eq ([string]$entry.sha256).ToLowerInvariant()) "fixture closure content hash drifted: $relativePath"
    $resolvedEntries += [pscustomobject]@{ path = $relativePath; role = [string]$entry.role; sha256 = [string]$entry.sha256; physical_path = $candidate }
}
Assert-Condition ($seenPaths.Count -eq $expectedRoles.Count) 'fixture closure omitted an expected external dependency'
Assert-Condition ((Get-ClosureDigest -Records $resolvedEntries) -eq [string]$manifest.closure_hash_contract.expected_sha256) 'fixture closure digest drifted'

$verifierEntry = @($resolvedEntries | Where-Object { $_.role -eq 'isolation_verifier' })
Assert-Condition ($verifierEntry.Count -eq 1) 'fixture closure must contain exactly one isolation verifier'
$verifier = if ([string]::IsNullOrWhiteSpace($IsolationVerifier)) { $verifierEntry[0].physical_path } else { (Resolve-Path -LiteralPath $IsolationVerifier -ErrorAction Stop).Path }
Assert-Condition ([IO.Path]::GetFullPath($verifier) -ieq [IO.Path]::GetFullPath($verifierEntry[0].physical_path)) 'isolation verifier must be the manifest-pinned file'

if (-not $SkipIsolationScan) {
    $scratchRoot = Join-Path $packageRoot ('tests\.fixture-isolation-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $scratchRoot 'lua'), (Join-Path $scratchRoot 'tests') | Out-Null
    foreach ($entry in @($resolvedEntries | Where-Object { $_.role -eq 'fixture_lua' })) {
        $destination = Join-Path (Join-Path $scratchRoot 'lua') ([IO.Path]::GetFileName($entry.physical_path))
        Copy-Item -LiteralPath $entry.physical_path -Destination $destination -Force
        Assert-Condition ((Get-Sha256Lower -Path $destination) -eq $entry.sha256.ToLowerInvariant()) "fixture isolation copy drifted: $($entry.path)"
    }
    Copy-Item -LiteralPath (Join-Path $packageRoot 'tests\y3-api-baseline.json') -Destination (Join-Path $scratchRoot 'tests\y3-api-baseline.json') -Force
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $verifierOutput = & $verifier -PackageRoot $scratchRoot 2>&1
        $verifierSucceeded = $?
        $verifierExitCode = if ($verifierSucceeded) { 0 } else { 1 }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $verifierText = ($verifierOutput | ForEach-Object { [string]$_ }) -join "`n"
    Assert-Condition ($verifierExitCode -eq 0) "fixture API isolation verifier failed: $verifierText"
    Assert-Condition ($verifierText -match 'PASS: Huaguoshan offline API isolation check passed\.') "fixture API isolation verifier did not confirm the external closure: $verifierText"
}
finally {
    if (Test-Path -LiteralPath $scratchRoot) {
        Assert-PhysicalPathUnderRoot -Root $packageRoot -Candidate $scratchRoot -Label 'fixture isolation scratch root'
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force
    }
}
}

# Recheck all external sources after the verifier and scratch scan.  The caller
# also runs this script before and after the Fengari executions, so any drift
# within the declared trusted-filesystem condition fails the acceptance run.
foreach ($entry in $resolvedEntries) {
    Assert-PhysicalPathUnderRoot -Root $workspaceRoot -Candidate $entry.physical_path -Label "post-scan fixture path $($entry.path)"
    Assert-Condition ((Get-Sha256Lower -Path $entry.physical_path) -eq $entry.sha256.ToLowerInvariant()) "fixture closure changed during isolation scan: $($entry.path)"
}
Assert-Condition ((Get-ClosureDigest -Records $resolvedEntries) -eq [string]$manifest.closure_hash_contract.expected_sha256) 'fixture closure digest changed during isolation scan'

Write-Output "PASS: $script:Assertions economy-v2 Tide Trace fixture-closure assertions"
