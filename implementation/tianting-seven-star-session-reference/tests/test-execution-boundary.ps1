$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$contractPath = Join-Path $packageRoot 'package-contract.json'
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding utf8 | ConvertFrom-Json

if ($contract.production_gate -ne 'closed' -or $contract.non_production -ne $true) {
    throw 'seven-star reference package production boundary drifted'
}

if ($contract.execution.dependencies -ne 'Node.js standard library only' -or $contract.execution.network -ne $false -or $contract.execution.persistence -ne $false) {
    throw 'seven-star reference execution boundary drifted'
}

if ($contract.route_registry.Count -ne 7) {
    throw 'seven-star route registry must contain exactly seven routes'
}

$identityFields = @('owner_actor_id', 'lifecycle_id', 'session_instance_id', 'session_epoch', 'revision', 'cleanup_token')
if (@($contract.session_identity_fields).Count -ne $identityFields.Count -or @($contract.session_identity_fields | Where-Object { $_ -notin $identityFields }).Count -ne 0) {
    throw 'seven-star session identity fields drifted'
}

$rawContract = Get-Content -LiteralPath $contractPath -Raw -Encoding utf8
if ($rawContract -match '"runtime_key"') {
    throw 'seven-star reference contract must not define a runtime key'
}

$forbiddenExtensions = @('*.lua', '*.y3', '*.upui')
foreach ($pattern in $forbiddenExtensions) {
    $forbiddenFiles = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter $pattern)
    if ($forbiddenFiles.Count -ne 0) {
        throw "forbidden runtime artifact found for pattern $pattern"
    }
}

$forbiddenDirectories = @('map', 'maps', 'ui', 'object', 'objects')
foreach ($name in $forbiddenDirectories) {
    if (Test-Path -LiteralPath (Join-Path $packageRoot $name)) {
        throw "forbidden construction directory found: $name"
    }
}

$runtimeMarkers = @('require\s*\(\s*["'']y3', 'GameAPI', 'y3\.')
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'reference') -Recurse -File -Filter '*.js') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.js')
foreach ($sourceFile in $sourceFiles) {
    $content = Get-Content -LiteralPath $sourceFile.FullName -Raw -Encoding utf8
    foreach ($marker in $runtimeMarkers) {
        if ($content -match $marker) {
            throw "runtime marker '$marker' found in $($sourceFile.FullName)"
        }
    }
}

$referenceSource = Get-Content -LiteralPath (Join-Path $packageRoot 'reference\seven-star-session-reference.js') -Raw -Encoding utf8
$forbiddenReferenceMarkers = @('\bevent_id\b', '\bsuccess_event\b', '\beconomy-v2\b', '\bsource_profile\b', '\bruntime_key\b', '\breward_slot\b', '\bhp_max\b', '\battack_(phy|mag)\b', '\bdefense_(phy|mag)\b', '\bmove_speed\b', '\bskill_damage\b')
foreach ($marker in $forbiddenReferenceMarkers) {
    if ($referenceSource -match $marker) {
        throw "forbidden reference marker '$marker' found in reference model"
    }
}

Write-Output 'PASS: tianting-seven-star-session-reference execution boundary'
