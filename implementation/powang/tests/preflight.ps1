param(
    [switch]$RequireConstructionReady
)

$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$manifestPath = Join-Path $packageRoot 'preconstruction-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $script:errors.Add($Message)
    }
}

function Assert-LevelArrays {
    param($Ability)

    $maxLevel = [int]$Ability.object_fields.ability_max_level
    foreach ($field in @('cold_down_time', 'ability_cost', 'ability_hp_cost', 'ability_damage', 'required_level')) {
        $values = @($Ability.object_fields.$field)
        Assert-True ($values.Count -eq $maxLevel) "$($Ability.record_key).$field expected $maxLevel values, found $($values.Count)"
    }

    foreach ($field in @('ability_cost', 'ability_hp_cost', 'ability_damage')) {
        $nonZero = @($Ability.object_fields.$field | Where-Object { [double]$_ -ne 0 })
        Assert-True ($nonZero.Count -eq 0) "$($Ability.record_key).$field must remain zero for Lua-owned resource/damage"
    }
}

Assert-True ($manifest.version -eq 1) 'Manifest version must be 1'
Assert-True ($manifest.kind -eq 'powang-preconstruction-manifest') 'Unexpected manifest kind'
Assert-True ($manifest.record_schema.inherits_defaults -eq $true) 'Manifest must inherit standardized record defaults'
Assert-True ($manifest.record_schema.a_layer_canonical_name -eq 'y3_fields') 'Canonical A-layer name must be y3_fields'
foreach ($field in @('status', 'operation', 'chapter', 'source_doc', 'acceptance')) {
    Assert-True ($null -ne $manifest.record_defaults.$field) "Missing record default: $field"
}
Assert-True (@($manifest.abilities).Count -eq [int]$manifest.expected_counts.abilities) 'Ability count mismatch'
Assert-True (@($manifest.modifiers).Count -eq [int]$manifest.expected_counts.modifiers) 'Modifier count mismatch'
Assert-True ([int]$manifest.expected_counts.heroes -eq 1) 'Hero count must be 1'
Assert-True ([int]$manifest.expected_counts.projectiles -eq 0) 'Powang v1 must not create projectile objects'

$allKeys = @($manifest.hero.record_key) + @($manifest.abilities.record_key) + @($manifest.modifiers.record_key)
$uniqueKeys = @($allKeys | Sort-Object -Unique)
Assert-True ($allKeys.Count -eq 31) "Expected 31 stable keys including hero, found $($allKeys.Count)"
Assert-True ($uniqueKeys.Count -eq $allKeys.Count) 'Stable keys must be unique'
Assert-True ($manifest.hero.object_type -eq 'unit') 'C01_HERO.object_type must be unit'

foreach ($ability in $manifest.abilities) {
    Assert-True ($ability.object_type -eq 'ability') "$($ability.record_key).object_type must be ability"
    Assert-LevelArrays $ability
    $expectedCastType = if ($ability.category -in @('fixed-passive', 'learnable-passive')) { 3 } else { 2 }
    Assert-True ([int]$ability.object_fields.ability_cast_type -eq $expectedCastType) "$($ability.record_key).ability_cast_type expected $expectedCastType"
    Assert-True ('ability_cast_type' -notin @($ability.unresolved_fields)) "$($ability.record_key).ability_cast_type cannot remain unresolved"
    foreach ($dependency in @($ability.dependencies)) {
        Assert-True ($dependency -in $allKeys) "$($ability.record_key) has undefined dependency $dependency"
    }
}

foreach ($modifier in $manifest.modifiers) {
    Assert-True ($modifier.object_type -eq 'modifier') "$($modifier.record_key).object_type must be modifier"
}

Assert-True ($manifest.execution_gates.cast_types_verified -eq $true) 'Cast type gate must be verified against the pinned y3-lualib baseline'
$featureGateNames = @(
    'guardable_damage_classifier_bound',
    'lifecycle_callback_contract_bound',
    'target_rank_resolver_bound'
)
foreach ($gateName in $featureGateNames) {
    $property = $manifest.execution_gates.PSObject.Properties[$gateName]
    Assert-True ($null -ne $property) "Missing required feature gate: $gateName"
    if ($null -ne $property) {
        Assert-True ($property.Value -is [bool]) "Feature gate must be boolean: $gateName"
    }
}

foreach ($dependency in @($manifest.hero.dependencies)) {
    Assert-True ($dependency -in $allKeys) "Hero has undefined dependency $dependency"
}

foreach ($source in @($manifest.source_documents)) {
    $sourcePath = Join-Path $projectRoot $source
    Assert-True (Test-Path -LiteralPath $sourcePath) "Missing source document: $source"
}

$breakpoints = @{
    1  = @(620, 48, 22, 16)
    10 = @(1232, 99, 39, 30)
    20 = @(1912, 156, 58, 45)
    30 = @(2592, 213, 77, 60)
    40 = @(3272, 270, 96, 75)
    50 = @(3952, 327, 115, 90)
    55 = @(4292, 356, 125, 97)
    60 = @(4632, 384, 134, 105)
}

foreach ($entry in $breakpoints.GetEnumerator()) {
    $level = [int]$entry.Key
    $expected = $entry.Value
    $hp = [Math]::Round(620 + 68 * ($level - 1), 0, [MidpointRounding]::AwayFromZero)
    $attack = [Math]::Round(48 + 5.7 * ($level - 1), 0, [MidpointRounding]::AwayFromZero)
    $physicalDefense = [Math]::Round(22 + 1.9 * ($level - 1), 0, [MidpointRounding]::AwayFromZero)
    $magicDefense = [Math]::Round(16 + 1.5 * ($level - 1), 0, [MidpointRounding]::AwayFromZero)
    $actual = @($hp, $attack, $physicalDefense, $magicDefense)
    Assert-True (($actual -join ',') -eq ($expected -join ',')) "Hero breakpoint Lv$level expected $($expected -join '/'), found $($actual -join '/')"
}

$unresolvedIds = @($manifest.hero.y3_id) + @($manifest.abilities.y3_id) + @($manifest.modifiers.y3_id)
if (@($unresolvedIds | Where-Object { $null -eq $_ }).Count -gt 0) {
    $warnings.Add('Production Y3 IDs are intentionally unresolved until a real map is connected.')
}

$closedGates = @($manifest.execution_gates.PSObject.Properties | Where-Object { $_.Value -eq $false -or $null -eq $_.Value })
if ($closedGates.Count -gt 0) {
    $warnings.Add('Construction gates still closed: ' + (($closedGates.Name | Sort-Object) -join ', '))
}

if ($RequireConstructionReady -and $closedGates.Count -gt 0) {
    $errors.Add('Construction-ready mode requires every execution gate to be resolved.')
}

Write-Output "Powang preflight"
Write-Output "  abilities: $(@($manifest.abilities).Count)"
Write-Output "  modifiers: $(@($manifest.modifiers).Count)"
Write-Output "  stable keys: $($allKeys.Count)"
Write-Output "  errors: $($errors.Count)"
Write-Output "  warnings: $($warnings.Count)"

foreach ($warning in $warnings) {
    Write-Warning $warning
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) {
        Write-Error $message
    }
    exit 1
}

Write-Output 'PASS: design package is internally consistent.'
if ($closedGates.Count -gt 0) {
    Write-Output 'STATUS: validated offline; not ready for editor construction.'
} else {
    Write-Output 'STATUS: ready for editor construction.'
}
