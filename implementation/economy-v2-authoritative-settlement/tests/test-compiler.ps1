[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$forbiddenEnvironmentNames = @(
    [Environment]::GetEnvironmentVariables().Keys |
        Where-Object { $_ -eq 'NODE_OPTIONS' -or $_ -eq 'NODE_PATH' -or $_ -like 'LUA_*' }
)
if ($forbiddenEnvironmentNames.Count -gt 0) {
    throw "Refusing compiler test with injected execution environment: $($forbiddenEnvironmentNames -join ', ')"
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $packageRoot)
$compilerPath = Join-Path $packageRoot 'reference\compile-economy-v2.js'
$allowlistPath = Join-Path $packageRoot 'contract\input-allowlist.json'
$docsRoot = Join-Path $workspaceRoot 'docs'
$v2Candidates = @(Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter 'economy-v2-resource-table.json')
$v1Candidates = @(Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter 'economy-v1-resource-table.json')
if ($v2Candidates.Count -ne 1) { throw "Expected one frozen v2 table below docs, found $($v2Candidates.Count)." }
if ($v1Candidates.Count -ne 1) { throw "Expected one historical v1 table below docs, found $($v1Candidates.Count)." }
$sourcePath = $v2Candidates[0].FullName
$v1Path = $v1Candidates[0].FullName
$relativeSourcePath = $sourcePath.Substring($workspaceRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) { throw "Missing compiler: $compilerPath" }
if (-not (Test-Path -LiteralPath $allowlistPath -PathType Leaf)) { throw "Missing allowlist: $allowlistPath" }
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Missing frozen v2 table: $sourcePath" }
if (-not (Test-Path -LiteralPath $v1Path -PathType Leaf)) { throw "Missing historical v1 table: $v1Path" }

$node = (Get-Command node -ErrorAction Stop).Source
if (-not (Test-Path -LiteralPath $node -PathType Leaf)) { throw "Node executable is not a file: $node" }

$testRoot = Join-Path $PSScriptRoot ('.compiler-test-' + $PID + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$escapeRoot = $null
$outputJunction = $null

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Invoke-Compiler {
    param(
        [Parameter(Mandatory = $true)][string]$Compiler,
        [Parameter(Mandatory = $true)][string]$Output,
        [string]$InputPath,
        [string]$ExpectedFailureCode
    )

    $arguments = @($Compiler, '--output', $Output)
    if (-not [string]::IsNullOrEmpty($InputPath)) {
        $arguments += @('--input', $InputPath)
    }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $outputText = & $node @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ([string]::IsNullOrEmpty($ExpectedFailureCode)) {
        if ($exitCode -ne 0) {
            throw "Compiler unexpectedly failed ($exitCode): $outputText"
        }
        Assert-True -Condition (Test-Path -LiteralPath $Output -PathType Leaf) -Message "Compiler did not create expected output: $Output"
        return $outputText
    }

    if ($exitCode -eq 0) {
        throw "Compiler unexpectedly accepted a rejected input ($ExpectedFailureCode): $outputText"
    }
    Assert-True -Condition ($outputText -match [regex]::Escape($ExpectedFailureCode)) -Message "Expected $ExpectedFailureCode, got: $outputText"
    Assert-True -Condition (-not (Test-Path -LiteralPath $Output)) -Message "Rejected input left output behind: $Output"
    $temporaryOutputs = @(Get-ChildItem -LiteralPath (Split-Path -Parent $Output) -Force -Filter ('.' + [IO.Path]::GetFileName($Output) + '.*.tmp') -ErrorAction SilentlyContinue)
    $temporaryOutputNames = if ($temporaryOutputs.Count -gt 0) { $temporaryOutputs | ForEach-Object { $_.FullName } } else { @() }
    Assert-True -Condition ($temporaryOutputs.Count -eq 0) -Message "Rejected input left temporary output behind: $($temporaryOutputNames -join ', ')"
    return $outputText
}

function New-CloneWorkspace {
    param([Parameter(Mandatory = $true)][string]$Name)

    $cloneRoot = Join-Path $testRoot $Name
    $clonePackageRoot = Join-Path $cloneRoot 'implementation\economy-v2-authoritative-settlement'
    $cloneCompilerPath = Join-Path $clonePackageRoot 'reference\compile-economy-v2.js'
    $cloneAllowlistPath = Join-Path $clonePackageRoot 'contract\input-allowlist.json'
    $cloneSourcePath = Join-Path $cloneRoot $relativeSourcePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cloneCompilerPath), (Split-Path -Parent $cloneAllowlistPath), (Split-Path -Parent $cloneSourcePath), (Join-Path $clonePackageRoot 'tests') | Out-Null
    Copy-Item -LiteralPath $compilerPath -Destination $cloneCompilerPath
    Copy-Item -LiteralPath $allowlistPath -Destination $cloneAllowlistPath
    Copy-Item -LiteralPath $sourcePath -Destination $cloneSourcePath
    return [pscustomobject]@{
        Root = $cloneRoot
        PackageRoot = $clonePackageRoot
        Compiler = $cloneCompilerPath
        Source = $cloneSourcePath
        Output = (Join-Path $clonePackageRoot 'tests\rejected.json')
    }
}

function Set-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

try {
    $firstOutput = Join-Path $testRoot 'compiled-a.json'
    $secondOutput = Join-Path $testRoot 'compiled-b.json'
    Invoke-Compiler -Compiler $compilerPath -Output $firstOutput | Out-Null
    Invoke-Compiler -Compiler $compilerPath -Output $secondOutput | Out-Null
    $firstBytes = [IO.File]::ReadAllBytes($firstOutput)
    $secondBytes = [IO.File]::ReadAllBytes($secondOutput)
    Assert-True -Condition ([Convert]::ToBase64String($firstBytes) -eq [Convert]::ToBase64String($secondBytes)) -Message 'Compiler output is not byte-for-byte deterministic.'
    $compiled = Get-Content -LiteralPath $firstOutput -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True -Condition ($compiled.baseline_schema_version -eq 1) -Message 'Missing baseline_schema_version=1.'
    Assert-True -Condition ($compiled.compiler_id -eq 'economy-v2-authoritative-settlement-offline-compiler-v1') -Message 'Unexpected compiler_id.'
    Assert-True -Condition ($compiled.source.resource_table_version -eq 'economy-v2') -Message 'Compiled source version is not economy-v2.'
    Assert-True -Condition ($compiled.source.resource_table_file_sha256 -eq '3288BD9CD1BFBB516DB4808EF002C45FECCF5F1C7F4C80499DB81E31B2F84EAE') -Message 'Compiled source SHA drifted.'
    Assert-True -Condition ($compiled.source.runtime_handoff -eq $false) -Message 'Compiled source runtime_handoff must remain false.'
    Assert-True -Condition ($compiled.source.production_gate -eq 'closed') -Message 'Compiled source production gate must remain closed.'
    Assert-True -Condition ($compiled.resource_table.resource_table_version -eq 'economy-v2') -Message 'Compiled baseline omitted the full resource_table.'

    # Concurrent replacement of an otherwise trusted parent is outside the
    # reference package's declared filesystem boundary. This regression proves
    # that a reparse point already present at validation time fails closed.
    $escapeRoot = Join-Path $workspaceRoot ('.economy-v2-compiler-escape-' + [guid]::NewGuid().ToString('N'))
    $outputJunction = Join-Path $testRoot 'output-junction'
    New-Item -ItemType Directory -Path $escapeRoot -Force | Out-Null
    try {
        New-Item -ItemType Junction -Path $outputJunction -Target $escapeRoot -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Unable to create compiler output junction test fixture: $($_.Exception.Message)"
    }
    $junctionOutput = Join-Path $outputJunction 'must-not-escape.json'
    Invoke-Compiler -Compiler $compilerPath -Output $junctionOutput -ExpectedFailureCode 'OUTPUT_REPARSE_FORBIDDEN' | Out-Null
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $escapeRoot 'must-not-escape.json'))) -Message 'Compiler wrote through an output junction.'

    Invoke-Compiler -Compiler $compilerPath -InputPath $v1Path -Output (Join-Path $testRoot 'v1-rejected.json') -ExpectedFailureCode 'INPUT_PATH_DRIFT' | Out-Null

    $hashDrift = New-CloneWorkspace -Name 'hash-drift'
    $hashText = [IO.File]::ReadAllText($hashDrift.Source, [Text.UTF8Encoding]::new($false)).Replace('"decision_status": "accepted-baseline"', '"decision_status": "accepted-baseline-drift"')
    Set-Utf8NoBomText -Path $hashDrift.Source -Text $hashText
    Invoke-Compiler -Compiler $hashDrift.Compiler -Output $hashDrift.Output -ExpectedFailureCode 'SOURCE_SHA256_MISMATCH' | Out-Null

    $bomDrift = New-CloneWorkspace -Name 'bom-drift'
    $originalBytes = [IO.File]::ReadAllBytes($bomDrift.Source)
    $bomBytes = New-Object byte[] ($originalBytes.Length + 3)
    $bomBytes[0] = 0xEF; $bomBytes[1] = 0xBB; $bomBytes[2] = 0xBF
    [Array]::Copy($originalBytes, 0, $bomBytes, 3, $originalBytes.Length)
    [IO.File]::WriteAllBytes($bomDrift.Source, $bomBytes)
    Invoke-Compiler -Compiler $bomDrift.Compiler -Output $bomDrift.Output -ExpectedFailureCode 'INPUT_BOM_FORBIDDEN' | Out-Null

    $duplicateKey = New-CloneWorkspace -Name 'duplicate-key'
    $duplicateText = [IO.File]::ReadAllText($duplicateKey.Source, [Text.UTF8Encoding]::new($false))
    $duplicateText = $duplicateText.Replace('  "version": 1,', "  `"version`": 1,`n  `"version`": 1,")
    Assert-True -Condition ($duplicateText -match '"version": 1,\s+"version": 1') -Message 'Test fixture did not insert a duplicate key.'
    Set-Utf8NoBomText -Path $duplicateKey.Source -Text $duplicateText
    Invoke-Compiler -Compiler $duplicateKey.Compiler -Output $duplicateKey.Output -ExpectedFailureCode 'DUPLICATE_JSON_KEY' | Out-Null

    $candidate = New-CloneWorkspace -Name 'candidate-version'
    $candidateText = [IO.File]::ReadAllText($candidate.Source, [Text.UTF8Encoding]::new($false)).Replace('"resource_table_version": "economy-v2"', '"resource_table_version": "economy-v1"')
    Set-Utf8NoBomText -Path $candidate.Source -Text $candidateText
    Invoke-Compiler -Compiler $candidate.Compiler -Output $candidate.Output -ExpectedFailureCode 'RESOURCE_TABLE_VERSION_MISMATCH' | Out-Null

    $allowlistDrift = New-CloneWorkspace -Name 'allowlist-drift'
    $allowlistText = [IO.File]::ReadAllText((Join-Path $allowlistDrift.PackageRoot 'contract\input-allowlist.json'), [Text.UTF8Encoding]::new($false)).Replace('3288BD9CD1BFBB516DB4808EF002C45FECCF5F1C7F4C80499DB81E31B2F84EAE', '0000000000000000000000000000000000000000000000000000000000000000')
    Set-Utf8NoBomText -Path (Join-Path $allowlistDrift.PackageRoot 'contract\input-allowlist.json') -Text $allowlistText
    Invoke-Compiler -Compiler $allowlistDrift.Compiler -Output $allowlistDrift.Output -ExpectedFailureCode 'ALLOWLIST_DRIFT' | Out-Null

    $runtimeGate = New-CloneWorkspace -Name 'runtime-gate'
    $runtimeText = [IO.File]::ReadAllText($runtimeGate.Source, [Text.UTF8Encoding]::new($false)).Replace('"runtime_handoff": false', '"runtime_handoff": true')
    Set-Utf8NoBomText -Path $runtimeGate.Source -Text $runtimeText
    Invoke-Compiler -Compiler $runtimeGate.Compiler -Output $runtimeGate.Output -ExpectedFailureCode 'RUNTIME_HANDOFF_MISMATCH' | Out-Null

    $productionGate = New-CloneWorkspace -Name 'production-gate'
    $productionText = [IO.File]::ReadAllText($productionGate.Source, [Text.UTF8Encoding]::new($false)).Replace('"production_gate": "closed"', '"production_gate": "open"')
    Set-Utf8NoBomText -Path $productionGate.Source -Text $productionText
    Invoke-Compiler -Compiler $productionGate.Compiler -Output $productionGate.Output -ExpectedFailureCode 'PRODUCTION_GATE_MISMATCH' | Out-Null

    Write-Output 'economy-v2 compiler tests: PASS'
}
finally {
    if ($null -ne $outputJunction -and (Test-Path -LiteralPath $outputJunction)) {
        Remove-Item -LiteralPath $outputJunction -Force
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
    if ($null -ne $escapeRoot -and (Test-Path -LiteralPath $escapeRoot)) {
        $fullWorkspaceRoot = [IO.Path]::GetFullPath($workspaceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $fullEscapeRoot = [IO.Path]::GetFullPath($escapeRoot)
        if (-not $fullEscapeRoot.StartsWith($fullWorkspaceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to delete compiler escape fixture outside workspace: $fullEscapeRoot"
        }
        Remove-Item -LiteralPath $escapeRoot -Recurse -Force
    }
}
