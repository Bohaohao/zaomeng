$ErrorActionPreference = 'Stop'

$verifier = Join-Path $PSScriptRoot 'verify-y3-api.ps1'
$y3LuaApiRoot = Join-Path $env:USERPROFILE '.codex\skills\y3-lua-api'
$baselinePath = Join-Path $PSScriptRoot 'y3-api-baseline.json'
$legacyBaselinePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'y3-api-baseline.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('huaguoshan-y3-api-baseline-' + [guid]::NewGuid().ToString('N'))

function New-TestPackage {
    param([string]$Name)

    $testPackageRoot = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $testPackageRoot 'lua') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testPackageRoot 'tests') -Force | Out-Null
    Copy-Item -LiteralPath $baselinePath -Destination (Join-Path $testPackageRoot 'tests\y3-api-baseline.json')
    Set-Content -LiteralPath (Join-Path $testPackageRoot 'lua\allowed_module.lua') -Encoding UTF8 -Value 'return true'
    return $testPackageRoot
}

function Invoke-Y3ApiVerifier {
    param(
        [string]$TestPackageRoot,
        [string]$TestBaselinePath
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command powershell -ErrorAction Stop).Source
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$verifier`" -Y3LuaApiRoot `"$y3LuaApiRoot`" -PackageRoot `"$TestPackageRoot`""
    if (-not [string]::IsNullOrWhiteSpace($TestBaselinePath)) {
        $startInfo.Arguments += " -BaselinePath `"$TestBaselinePath`""
    }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Text = $standardOutput + $standardError
        }
    }
    finally {
        $process.Dispose()
    }
}

try {
    $negativeCases = @(
        [pscustomobject]@{ Name = 'bare-alias'; Path = 'bare-alias.lua'; Source = 'local engine = y3; return engine'; ExpectedDisplay = 'y3' },
        [pscustomobject]@{ Name = 'indexed-call'; Path = 'indexed-call.lua'; Source = "return GameAPI['nonexistent']()"; ExpectedDisplay = 'GameAPI' },
        [pscustomobject]@{ Name = 'global-dot'; Path = 'global-dot.lua'; Source = 'return _G.GlobalAPI'; ExpectedDisplay = '_G' },
        [pscustomobject]@{ Name = 'global-bracket'; Path = 'global-bracket.lua'; Source = "return _G['CAPI']"; ExpectedDisplay = '_G' },
        [pscustomobject]@{ Name = 'global-rawget'; Path = 'nested\global-rawget.lua'; Source = "return rawget(_G, 'GameAPI')"; ExpectedDisplay = '_G' },
        [pscustomobject]@{ Name = 'global-environment'; Path = 'nested\global-environment.lua'; Source = "return rawget(_ENV, 'CAPI')"; ExpectedDisplay = '_ENV' },
        [pscustomobject]@{ Name = 'dynamic-engine'; Path = 'dynamic-engine.lua'; Source = "local name = string.char(71, 97, 109, 101, 65, 80, 73); return load('return ' .. name)()"; ExpectedDisplay = 'load' },
        [pscustomobject]@{ Name = 'dynamic-require'; Path = 'dynamic-require.lua'; Source = "return require(('huaguoshan_' .. 'config'))"; ExpectedDisplay = 'require(dynamic)' },
        [pscustomobject]@{ Name = 'external-require'; Path = 'external-require.lua'; Source = "return require 'outside_module'"; ExpectedDisplay = 'require:outside_module' },
        [pscustomobject]@{ Name = 'loadfile'; Path = 'loadfile.lua'; Source = "return loadfile('outside.lua')"; ExpectedDisplay = 'loadfile' },
        [pscustomobject]@{ Name = 'dofile'; Path = 'dofile.lua'; Source = "return dofile('outside.lua')"; ExpectedDisplay = 'dofile' },
        [pscustomobject]@{ Name = 'debug-getregistry'; Path = 'debug-getregistry.lua'; Source = 'return debug.getregistry()'; ExpectedDisplay = 'debug' },
        [pscustomobject]@{ Name = 'getfenv'; Path = 'getfenv.lua'; Source = 'return getfenv(0)'; ExpectedDisplay = 'getfenv' },
        [pscustomobject]@{ Name = 'setfenv'; Path = 'setfenv.lua'; Source = 'return setfenv(1, {})'; ExpectedDisplay = 'setfenv' },
        [pscustomobject]@{ Name = 'package-loaded'; Path = 'package-loaded.lua'; Source = "return package.loaded['y3']"; ExpectedDisplay = 'package' },
        [pscustomobject]@{ Name = 'package-searchers'; Path = 'package-searchers.lua'; Source = 'return package.searchers or package.loaders'; ExpectedDisplay = 'package' },
        [pscustomobject]@{ Name = 'os-getenv'; Path = 'os-getenv.lua'; Source = "return os.getenv('USERPROFILE')"; ExpectedDisplay = 'os' },
        [pscustomobject]@{ Name = 'io-open'; Path = 'io-open.lua'; Source = "return io.open('outside.lua', 'r')"; ExpectedDisplay = 'io' },
        [pscustomobject]@{ Name = 'ffi'; Path = 'ffi.lua'; Source = 'return ffi'; ExpectedDisplay = 'ffi' },
        [pscustomobject]@{ Name = 'jit'; Path = 'jit.lua'; Source = 'return jit'; ExpectedDisplay = 'jit' },
        [pscustomobject]@{ Name = 'indexed-os'; Path = 'indexed-os.lua'; Source = "return host['os']"; ExpectedDisplay = 'index:os' },
        [pscustomobject]@{ Name = 'indexed-io'; Path = 'indexed-io.lua'; Source = "return host['io']"; ExpectedDisplay = 'index:io' },
        [pscustomobject]@{ Name = 'indexed-ffi'; Path = 'indexed-ffi.lua'; Source = "return host['ffi']"; ExpectedDisplay = 'index:ffi' },
        [pscustomobject]@{ Name = 'indexed-jit'; Path = 'indexed-jit.lua'; Source = "return host['jit']"; ExpectedDisplay = 'index:jit' },
        [pscustomobject]@{ Name = 'method-require'; Path = 'method-require.lua'; Source = "return host:require('allowed_module')"; ExpectedDisplay = 'require(qualified)' },
        [pscustomobject]@{ Name = 'field-require'; Path = 'field-require.lua'; Source = "return host.require('allowed_module')"; ExpectedDisplay = 'require(qualified)' },
        [pscustomobject]@{ Name = 'indexed-require'; Path = 'indexed-require.lua'; Source = "return host['require']('allowed_module')"; ExpectedDisplay = 'index:require' },
        [pscustomobject]@{ Name = 'loadstring'; Path = 'loadstring.lua'; Source = "return loadstring('return 1')()"; ExpectedDisplay = 'loadstring' },
        [pscustomobject]@{ Name = 'module'; Path = 'module.lua'; Source = "module('outside_module')"; ExpectedDisplay = 'module' },
        [pscustomobject]@{ Name = 'dynamic-whitelisted-require'; Path = 'dynamic-whitelisted-require.lua'; Source = "return require('allowed_module' .. '')"; ExpectedDisplay = 'require(dynamic)' }
    )
    foreach ($case in $negativeCases) {
        $caseRoot = New-TestPackage -Name ('negative-' + $case.Name)
        $casePath = Join-Path (Join-Path $caseRoot 'lua') $case.Path
        New-Item -ItemType Directory -Path (Split-Path -Parent $casePath) -Force | Out-Null
        Set-Content -LiteralPath $casePath -Encoding UTF8 -Value $case.Source

        $negativeResult = Invoke-Y3ApiVerifier -TestPackageRoot $caseRoot
        if ($negativeResult.ExitCode -eq 0) {
            throw "Offline API isolation verifier unexpectedly accepted $($case.Name)."
        }
        $normalisedNegativeText = $negativeResult.Text -replace '[\r\n]', ''
        if ($normalisedNegativeText -notmatch 'offline Lua package contains forbidden engine') {
            throw "Offline API isolation verifier did not report the intended restriction for $($case.Name): $($negativeResult.Text)"
        }
        $leafName = Split-Path -Leaf $case.Path
        if ($normalisedNegativeText -notmatch [regex]::Escape($leafName)) {
            throw "Offline API isolation verifier did not report $leafName`: $($negativeResult.Text)"
        }
        if ($normalisedNegativeText -notmatch ('\[' + [regex]::Escape($case.ExpectedDisplay) + '\]')) {
            throw "Offline API isolation verifier did not identify $($case.ExpectedDisplay) in $leafName`: $($negativeResult.Text)"
        }
    }
    Write-Output "PASS: offline API isolation verifier independently rejects $($negativeCases.Count) engine, environment, and dynamic-loading paths."

    $positiveRoot = New-TestPackage -Name 'positive'
    $positiveLuaRoot = Join-Path $positiveRoot 'lua'
    $positiveSource = @'
-- y3.nonexistent()
-- _G['GameAPI']
--[=[
GlobalAPI.nonexistent()
_G.CAPI
debug.getregistry()
package.loaded
getfenv(0)
setfenv(1, {})
os.getenv('USERPROFILE')
io.open('outside.lua', 'r')
ffi
jit
host['os']
host['io']
host['ffi']
host['jit']
host:require('allowed_module')
]=]
local double_quoted = "GameAPI.nonexistent(\"y3.nonexistent()\")"
local single_quoted = 'GlobalAPI.nonexistent(\'CAPI.nonexistent()\')'
local ordinary_text = "host['os']; host['io']; host['ffi']; host['jit']; host:require('allowed_module')"
local long_string = [==[
CAPI.nonexistent()
_G.y3
_G['GameAPI']
debug.getregistry()
package.loaded
loadstring('return y3')
]==]
return { double_quoted, single_quoted, ordinary_text, long_string }
'@
    Set-Content -LiteralPath (Join-Path $positiveLuaRoot 'comments-and-strings.lua') -Encoding UTF8 -Value $positiveSource
    New-Item -ItemType Directory -Path (Join-Path $positiveLuaRoot 'nested') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $positiveLuaRoot 'nested\helper.lua') -Encoding UTF8 -Value 'return true'
    $staticRequireSource = @'
local direct = require 'allowed_module'
local parenthesized = require("allowed_module")
local nested = require('nested.helper')
return direct and parenthesized and nested
'@
    Set-Content -LiteralPath (Join-Path $positiveLuaRoot 'static-require.lua') -Encoding UTF8 -Value $staticRequireSource

    $positiveResult = Invoke-Y3ApiVerifier -TestPackageRoot $positiveRoot
    if ($positiveResult.ExitCode -ne 0) {
        throw "Offline API isolation verifier reported restricted text inside comments or strings: $($positiveResult.Text)"
    }
    if ($positiveResult.Text -notmatch 'PASS: Huaguoshan offline API isolation check passed\.' -or
        $positiveResult.Text -notmatch 'Y3 API compatibility baseline: unavailable \(real map script root not integrated\)') {
        throw "Offline API isolation verifier did not explicitly report the empty compatibility state: $($positiveResult.Text)"
    }
    Write-Output 'PASS: offline API isolation verifier accepts static package-local requires, ignores restricted text in comments/strings, and reports that no Y3 API compatibility baseline exists.'

    if (-not (Test-Path -LiteralPath $legacyBaselinePath -PathType Leaf)) {
        throw "Legacy package-root isolation metadata is missing: $legacyBaselinePath"
    }
    $legacyFallbackRoot = New-TestPackage -Name 'legacy-root-fallback'
    Remove-Item -LiteralPath (Join-Path $legacyFallbackRoot 'tests\y3-api-baseline.json') -Force
    Copy-Item -LiteralPath $legacyBaselinePath -Destination (Join-Path $legacyFallbackRoot 'y3-api-baseline.json') -Force
    $legacyFallbackResult = Invoke-Y3ApiVerifier -TestPackageRoot $legacyFallbackRoot
    if ($legacyFallbackResult.ExitCode -ne 0 -or
        $legacyFallbackResult.Text -notmatch 'Y3 API compatibility baseline: unavailable \(real map script root not integrated\)') {
        throw "Offline API isolation verifier did not accept the declared legacy package-root metadata fallback: $($legacyFallbackResult.Text)"
    }
    Write-Output 'PASS: legacy package-root offline-isolation metadata fallback satisfies the full schema.'

    $matchingCopiesRoot = New-TestPackage -Name 'matching-metadata-copies'
    $matchingCopiesMetadata = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $matchingCopiesRoot 'tests\y3-api-baseline.json') | ConvertFrom-Json
    $matchingCopiesMetadata | ConvertTo-Json -Depth 10 -Compress | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $matchingCopiesRoot 'y3-api-baseline.json')
    $matchingCopiesResult = Invoke-Y3ApiVerifier -TestPackageRoot $matchingCopiesRoot
    if ($matchingCopiesResult.ExitCode -ne 0) {
        throw "Offline API isolation verifier rejected semantically equal metadata copies with different formatting: $($matchingCopiesResult.Text)"
    }
    Write-Output 'PASS: authoritative and fallback metadata copies are compared semantically rather than byte-for-byte.'

    $outsideOverridePath = Join-Path $tempRoot 'outside-y3-api-baseline.json'
    Copy-Item -LiteralPath $baselinePath -Destination $outsideOverridePath -Force
    $outsideOverrideResult = Invoke-Y3ApiVerifier -TestPackageRoot $matchingCopiesRoot -TestBaselinePath $outsideOverridePath
    $normalisedOutsideOverrideText = $outsideOverrideResult.Text -replace '[\r\n]', ''
    if ($outsideOverrideResult.ExitCode -eq 0 -or
        $normalisedOutsideOverrideText -notmatch 'BaselinePath must select the package-authoritative or package-root fallback metadata') {
        throw "Offline API isolation verifier accepted an out-of-package BaselinePath override: $($outsideOverrideResult.Text)"
    }
    Write-Output 'PASS: BaselinePath cannot select metadata outside the package authority/fallback candidates.'

    $inconsistentOverridePath = Join-Path $matchingCopiesRoot 'tests\override-y3-api-baseline.json'
    $inconsistentOverride = Get-Content -Raw -Encoding UTF8 -LiteralPath $baselinePath | ConvertFrom-Json
    $inconsistentOverride.scope = 'Semantically different package-local override metadata.'
    $inconsistentOverride | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $inconsistentOverridePath
    $inconsistentOverrideResult = Invoke-Y3ApiVerifier -TestPackageRoot $matchingCopiesRoot -TestBaselinePath $inconsistentOverridePath
    $normalisedInconsistentOverrideText = $inconsistentOverrideResult.Text -replace '[\r\n]', ''
    if ($inconsistentOverrideResult.ExitCode -eq 0 -or
        $normalisedInconsistentOverrideText -notmatch 'BaselinePath must select the package-authoritative or package-root fallback metadata') {
        throw "Offline API isolation verifier accepted an inconsistent non-candidate BaselinePath override: $($inconsistentOverrideResult.Text)"
    }
    Write-Output 'PASS: BaselinePath cannot introduce an inconsistent third metadata document inside the package.'

    $symlinkRoot = New-TestPackage -Name 'symlinked-authoritative-metadata'
    $externalSymlinkMetadataPath = Join-Path $tempRoot 'external-symlink-y3-api-baseline.json'
    $externalSymlinkMetadata = Get-Content -Raw -Encoding UTF8 -LiteralPath $baselinePath | ConvertFrom-Json
    $externalSymlinkMetadata.scope = 'External metadata reached only through a reparse point.'
    $externalSymlinkMetadata | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $externalSymlinkMetadataPath
    $symlinkedAuthoritativePath = Join-Path $symlinkRoot 'tests\y3-api-baseline.json'
    Remove-Item -LiteralPath $symlinkedAuthoritativePath -Force
    New-Item -ItemType SymbolicLink -Path $symlinkedAuthoritativePath -Target $externalSymlinkMetadataPath | Out-Null
    $symlinkResult = Invoke-Y3ApiVerifier -TestPackageRoot $symlinkRoot -TestBaselinePath 'tests\y3-api-baseline.json'
    $normalisedSymlinkText = $symlinkResult.Text -replace '[\r\n]', ''
    if ($symlinkResult.ExitCode -eq 0 -or $normalisedSymlinkText -notmatch 'must not traverse a reparse point') {
        throw "Offline API isolation verifier accepted a reparse-point baseline candidate: $($symlinkResult.Text)"
    }
    Write-Output 'PASS: BaselinePath rejects authoritative or fallback metadata reached through a reparse point.'

    $metadataSchemaCases = @(
        [pscustomobject]@{
            Name = 'missing-scope'
            Expected = "field 'scope'"
            Mutate = { param($metadata) $metadata.PSObject.Properties.Remove('scope') }
        },
        [pscustomobject]@{
            Name = 'wrong-schema-version'
            Expected = 'schema_version'
            Mutate = { param($metadata) $metadata.schema_version = 2 }
        },
        [pscustomobject]@{
            Name = 'wrong-status-type'
            Expected = "field 'status'"
            Mutate = { param($metadata) $metadata.status = $true }
        },
        [pscustomobject]@{
            Name = 'wrong-boolean-type'
            Expected = 'must be a boolean'
            Mutate = { param($metadata) $metadata.compatibility_baseline_available = 'false' }
        },
        [pscustomobject]@{
            Name = 'blank-repository'
            Expected = "field 'repository'"
            Mutate = { param($metadata) $metadata.repository = '   ' }
        },
        [pscustomobject]@{
            Name = 'wrong-modules-type'
            Expected = 'must define a modules object'
            Mutate = { param($metadata) $metadata.modules = @() }
        },
        [pscustomobject]@{
            Name = 'empty-module-method-array'
            Expected = 'must list at least one non-empty string method name'
            Mutate = {
                param($metadata)
                $metadata.modules | Add-Member -NotePropertyName 'unit' -NotePropertyValue ([object[]]@())
            }
        },
        [pscustomobject]@{
            Name = 'wrong-events-type'
            Expected = 'must define an events array'
            Mutate = { param($metadata) $metadata.events = [pscustomobject]@{} }
        }
    )
    foreach ($case in $metadataSchemaCases) {
        $metadataCaseRoot = New-TestPackage -Name ('invalid-metadata-' + $case.Name)
        $metadataCasePath = Join-Path $metadataCaseRoot 'tests\y3-api-baseline.json'
        $metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath $metadataCasePath | ConvertFrom-Json
        $mutation = $case.Mutate
        & $mutation $metadata
        $metadata | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $metadataCasePath

        $metadataCaseResult = Invoke-Y3ApiVerifier -TestPackageRoot $metadataCaseRoot
        $normalisedMetadataCaseText = $metadataCaseResult.Text -replace '[\r\n]', ''
        if ($metadataCaseResult.ExitCode -eq 0 -or $normalisedMetadataCaseText -notmatch [regex]::Escape($case.Expected)) {
            throw "Offline API isolation verifier did not reject metadata case $($case.Name) with '$($case.Expected)': $($metadataCaseResult.Text)"
        }
    }
    Write-Output "PASS: offline API isolation metadata rejects $($metadataSchemaCases.Count) missing, fixed-value, and wrong-type schema violations."

    $inconsistentCopiesRoot = New-TestPackage -Name 'inconsistent-metadata-copies'
    Copy-Item -LiteralPath $legacyBaselinePath -Destination (Join-Path $inconsistentCopiesRoot 'y3-api-baseline.json') -Force
    $inconsistentFallbackPath = Join-Path $inconsistentCopiesRoot 'y3-api-baseline.json'
    $inconsistentFallback = Get-Content -Raw -Encoding UTF8 -LiteralPath $inconsistentFallbackPath | ConvertFrom-Json
    $inconsistentFallback.scope = 'Semantically different fallback metadata.'
    $inconsistentFallback | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $inconsistentFallbackPath
    $inconsistentCopiesResult = Invoke-Y3ApiVerifier -TestPackageRoot $inconsistentCopiesRoot -TestBaselinePath 'y3-api-baseline.json'
    $normalisedInconsistentCopiesText = $inconsistentCopiesResult.Text -replace '[\r\n]', ''
    if ($inconsistentCopiesResult.ExitCode -eq 0 -or
        $normalisedInconsistentCopiesText -notmatch 'metadata copies differ') {
        throw "Offline API isolation verifier accepted inconsistent authoritative and fallback metadata: $($inconsistentCopiesResult.Text)"
    }
    Write-Output 'PASS: a fallback BaselinePath override cannot bypass semantic equality with authoritative metadata.'

    $invalidBaselineRoot = New-TestPackage -Name 'invalid-empty-compatibility-claim'
    $invalidBaselinePath = Join-Path $invalidBaselineRoot 'tests\y3-api-baseline.json'
    $invalidBaseline = Get-Content -Raw -Encoding UTF8 -LiteralPath $invalidBaselinePath | ConvertFrom-Json
    $invalidBaseline.status = 'y3_api_compatibility_baseline'
    $invalidBaseline.compatibility_baseline_available = $true
    $invalidBaseline.real_map_script_root_integrated = $true
    $invalidBaseline | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $invalidBaselinePath

    $invalidBaselineResult = Invoke-Y3ApiVerifier -TestPackageRoot $invalidBaselineRoot
    if ($invalidBaselineResult.ExitCode -eq 0 -or
        $invalidBaselineResult.Text -notmatch 'empty modules/events must explicitly declare') {
        throw "Offline API isolation verifier accepted an empty compatibility-baseline claim: $($invalidBaselineResult.Text)"
    }
    Write-Output 'PASS: empty modules/events cannot be presented as a Y3 API compatibility baseline.'

    $emptyLuaRoot = New-TestPackage -Name 'empty-lua-package'
    Remove-Item -LiteralPath (Join-Path $emptyLuaRoot 'lua\allowed_module.lua') -Force
    $emptyLuaResult = Invoke-Y3ApiVerifier -TestPackageRoot $emptyLuaRoot
    if ($emptyLuaResult.ExitCode -eq 0 -or $emptyLuaResult.Text -notmatch 'offline Lua package contains no Lua files') {
        throw "Offline API isolation verifier accepted an empty Lua package: $($emptyLuaResult.Text)"
    }
    Write-Output 'PASS: an empty Lua package cannot produce a vacuous offline-isolation PASS.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
