param([switch]$RequireConstructionReady)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'preconstruction-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $script:errors.Add($Message) }
}

function Assert-LevelArrays {
    param($Ability)
    $maxLevel = [int]$Ability.object_fields.ability_max_level
    foreach ($field in @('cold_down_time','ability_cost','ability_hp_cost','ability_damage','required_level')) {
        $values = @($Ability.object_fields.$field)
        Assert-True ($values.Count -eq $maxLevel) "$($Ability.record_key).$field expected $maxLevel values, found $($values.Count)"
    }
    foreach ($field in @('ability_cost','ability_hp_cost','ability_damage')) {
        Assert-True (@($Ability.object_fields.$field | Where-Object { [double]$_ -ne 0 }).Count -eq 0) "$($Ability.record_key).$field must remain Lua-owned zero values"
    }
}

Assert-True ($manifest.version -eq 1) 'Manifest version must be 1'
Assert-True ($manifest.kind -eq 'chiming-preconstruction-manifest') 'Unexpected manifest kind'
Assert-True ($manifest.status -in @('offline-stage-under-construction','offline-stage-accepted')) 'Unexpected manifest stage'
Assert-True ($manifest.record_schema.inherits_defaults -eq $true) 'Manifest must inherit record defaults'
Assert-True ($manifest.record_schema.a_layer_canonical_name -eq 'y3_fields') 'Canonical A-layer name must be y3_fields'
foreach ($field in @('status','operation','chapter','source_doc','acceptance')) {
    Assert-True ($null -ne $manifest.record_defaults.$field) "Missing record default: $field"
}

Assert-True (@($manifest.abilities).Count -eq 18) 'Expected 18 abilities'
Assert-True (@($manifest.modifiers).Count -eq 12) 'Expected 12 modifiers'
Assert-True ($manifest.expected_counts.heroes -eq 1) 'Expected one hero'
Assert-True ($manifest.expected_counts.projectiles -eq 0) 'C03 v1 must not create projectile objects'
$allKeys = @($manifest.hero.record_key) + @($manifest.abilities.record_key) + @($manifest.modifiers.record_key)
Assert-True ($allKeys.Count -eq 31) "Expected 31 stable keys, found $($allKeys.Count)"
Assert-True ((@($allKeys | Sort-Object -Unique).Count -eq $allKeys.Count)) 'Stable keys must be unique'

foreach ($ability in $manifest.abilities) {
    Assert-LevelArrays $ability
    $expectedCastType = if ($ability.category -in @('fixed-passive','learnable-passive')) { 3 } else { 2 }
    Assert-True ([int]$ability.object_fields.ability_cast_type -eq $expectedCastType) "$($ability.record_key).ability_cast_type mismatch"
    Assert-True ('ability_cast_type' -notin @($ability.unresolved_fields)) "$($ability.record_key).ability_cast_type cannot remain unresolved"
    foreach ($dependency in @($ability.dependencies)) {
        Assert-True ($dependency -in $allKeys) "$($ability.record_key) has undefined dependency $dependency"
    }
}
foreach ($key in @('C03_A06','C03_A07','C03_A08')) {
    $ability = @($manifest.abilities | Where-Object { $_.record_key -eq $key })[0]
    Assert-True ($null -ne $ability) "Missing advanced skill: $key"
    if ($ability) { Assert-True ([int]$ability.object_fields.required_level[0] -eq 20) "$key must unlock at Lv20" }
}
foreach ($dependency in @($manifest.hero.dependencies)) {
    Assert-True ($dependency -in $allKeys) "C03_HERO has undefined dependency $dependency"
}
foreach ($source in @($manifest.source_documents)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot $source)) "Missing source document: $source"
}
Assert-True ($manifest.execution_gates.cast_types_verified -eq $true) 'Cast type gate must be verified'
Assert-True ($null -ne $manifest.execution_gates.target_rank_resolver_bound) 'Target rank resolver gate must be declared'

$breakpoints = @{
    1 = @(590,24,52,18,22); 20 = @(1806,66,168,48,56); 40 = @(3086,110,290,80,92); 60 = @(4366,154,412,112,128)
}
foreach ($entry in $breakpoints.GetEnumerator()) {
    $level = [int]$entry.Key
    $actual = @(
        [Math]::Round(590 + 64 * ($level - 1),0,[MidpointRounding]::AwayFromZero),
        [Math]::Round(24 + 2.2 * ($level - 1),0,[MidpointRounding]::AwayFromZero),
        [Math]::Round(52 + 6.1 * ($level - 1),0,[MidpointRounding]::AwayFromZero),
        [Math]::Round(18 + 1.6 * ($level - 1),0,[MidpointRounding]::AwayFromZero),
        [Math]::Round(22 + 1.8 * ($level - 1),0,[MidpointRounding]::AwayFromZero)
    )
    Assert-True (($actual -join ',') -eq ($entry.Value -join ',')) "Lv$level hero breakpoint mismatch"
}

$unresolvedIds = @($manifest.hero.y3_id) + @($manifest.abilities.y3_id) + @($manifest.modifiers.y3_id)
if (@($unresolvedIds | Where-Object { $null -eq $_ }).Count -gt 0) { $warnings.Add('Production Y3 IDs are intentionally unresolved until a real map is connected.') }
$closedGates = @($manifest.execution_gates.PSObject.Properties | Where-Object { $_.Value -eq $false -or $null -eq $_.Value })
if ($closedGates.Count -gt 0) { $warnings.Add('Construction gates still closed: ' + (($closedGates.Name | Sort-Object) -join ', ')) }
if ($RequireConstructionReady -and $closedGates.Count -gt 0) { $errors.Add('Construction-ready mode requires every execution gate to be resolved.') }

Write-Output 'Chiming preflight'
Write-Output "  abilities: $(@($manifest.abilities).Count)"
Write-Output "  modifiers: $(@($manifest.modifiers).Count)"
Write-Output "  stable keys: $($allKeys.Count)"
Write-Output "  errors: $($errors.Count)"
Write-Output "  warnings: $($warnings.Count)"
foreach ($warning in $warnings) { Write-Warning $warning }
if ($errors.Count -gt 0) { foreach ($message in $errors) { Write-Error $message }; exit 1 }
Write-Output 'PASS: Chiming design package is internally consistent.'
if ($closedGates.Count -gt 0) { Write-Output 'STATUS: validated offline; not ready for editor construction.' } else { Write-Output 'STATUS: ready for editor construction.' }
