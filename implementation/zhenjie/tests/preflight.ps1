param(
    [switch]$RequireConstructionReady
)

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
    foreach ($field in @('cold_down_time', 'ability_cost', 'ability_hp_cost', 'ability_damage', 'required_level')) {
        $values = @($Ability.object_fields.$field)
        Assert-True ($values.Count -eq $maxLevel) "$($Ability.record_key).$field expected $maxLevel values, found $($values.Count)"
    }
    foreach ($field in @('ability_cost', 'ability_hp_cost', 'ability_damage')) {
        Assert-True (@($Ability.object_fields.$field | Where-Object { [double]$_ -ne 0 }).Count -eq 0) "$($Ability.record_key).$field must remain Lua-owned zero values"
    }
}

Assert-True ($manifest.version -eq 1) 'Manifest version must be 1'
Assert-True ($manifest.kind -eq 'zhenjie-preconstruction-manifest') 'Unexpected manifest kind'
Assert-True ($manifest.record_schema.inherits_defaults -eq $true) 'Manifest must inherit standardized record defaults'
Assert-True ($manifest.record_schema.a_layer_canonical_name -eq 'y3_fields') 'Canonical A-layer name must be y3_fields'
foreach ($field in @('status', 'operation', 'chapter', 'source_doc', 'acceptance')) {
    Assert-True ($null -ne $manifest.record_defaults.$field) "Missing record default: $field"
}

Assert-True (@($manifest.abilities).Count -eq 18) 'Expected 18 abilities'
Assert-True (@($manifest.modifiers).Count -eq 12) 'Expected 12 modifiers'
Assert-True ($manifest.expected_counts.heroes -eq 1) 'Expected one hero'
Assert-True ($manifest.expected_counts.projectiles -eq 0) 'Zhenjie v1 must not create projectile objects'

$allKeys = @($manifest.hero.record_key) + @($manifest.abilities.record_key) + @($manifest.modifiers.record_key)
Assert-True ($allKeys.Count -eq 31) "Expected 31 stable keys, found $($allKeys.Count)"
Assert-True ((@($allKeys | Sort-Object -Unique).Count -eq $allKeys.Count)) 'Stable keys must be unique'

foreach ($ability in $manifest.abilities) {
    Assert-LevelArrays $ability
    $expectedCastType = if ($ability.category -in @('fixed-passive', 'learnable-passive')) { 3 } else { 2 }
    Assert-True ([int]$ability.object_fields.ability_cast_type -eq $expectedCastType) "$($ability.record_key).ability_cast_type mismatch"
    Assert-True ('ability_cast_type' -notin @($ability.unresolved_fields)) "$($ability.record_key).ability_cast_type cannot remain unresolved"
    foreach ($dependency in @($ability.dependencies)) {
        Assert-True ($dependency -in $allKeys) "$($ability.record_key) has undefined dependency $dependency"
    }
}
foreach ($spenderKey in @('C02_A06', 'C02_A07', 'C02_A08')) {
    $spender = @($manifest.abilities | Where-Object { $_.record_key -eq $spenderKey })[0]
    Assert-True ($null -ne $spender) "Missing first spender: $spenderKey"
    if ($spender) {
        Assert-True ([int]$spender.object_fields.required_level[0] -eq 15) "$spenderKey must unlock with the Lv15 Jieshi threshold"
    }
}
foreach ($dependency in @($manifest.hero.dependencies)) {
    Assert-True ($dependency -in $allKeys) "C02_HERO has undefined dependency $dependency"
}
foreach ($source in @($manifest.source_documents)) {
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot $source)) "Missing source document: $source"
}
Assert-True ($manifest.execution_gates.cast_types_verified -eq $true) 'Cast type gate must be verified'

$breakpoints = @{
    1 = @(720, 42, 28, 20); 10 = @(1440, 84, 49, 36); 20 = @(2240, 131, 72, 54); 30 = @(3040, 178, 95, 72);
    40 = @(3840, 225, 118, 90); 50 = @(4640, 272, 141, 108); 55 = @(5040, 296, 152, 117); 60 = @(5440, 319, 164, 126)
}
foreach ($entry in $breakpoints.GetEnumerator()) {
    $level = [int]$entry.Key
    $actual = @(
        [Math]::Round(720 + 80 * ($level - 1), 0, [MidpointRounding]::AwayFromZero),
        [Math]::Round(42 + 4.7 * ($level - 1), 0, [MidpointRounding]::AwayFromZero),
        [Math]::Round(28 + 2.3 * ($level - 1), 0, [MidpointRounding]::AwayFromZero),
        [Math]::Round(20 + 1.8 * ($level - 1), 0, [MidpointRounding]::AwayFromZero)
    )
    Assert-True (($actual -join ',') -eq ($entry.Value -join ',')) "Lv$level hero breakpoint mismatch"
}

$unresolvedIds = @($manifest.hero.y3_id) + @($manifest.abilities.y3_id) + @($manifest.modifiers.y3_id)
if (@($unresolvedIds | Where-Object { $null -eq $_ }).Count -gt 0) { $warnings.Add('Production Y3 IDs are intentionally unresolved until a real map is connected.') }
$closedGates = @($manifest.execution_gates.PSObject.Properties | Where-Object { $_.Value -eq $false -or $null -eq $_.Value })
if ($closedGates.Count -gt 0) { $warnings.Add('Construction gates still closed: ' + (($closedGates.Name | Sort-Object) -join ', ')) }
if ($RequireConstructionReady -and $closedGates.Count -gt 0) { $errors.Add('Construction-ready mode requires every execution gate to be resolved.') }

Write-Output 'Zhenjie preflight'
Write-Output "  abilities: $(@($manifest.abilities).Count)"
Write-Output "  modifiers: $(@($manifest.modifiers).Count)"
Write-Output "  stable keys: $($allKeys.Count)"
Write-Output "  errors: $($errors.Count)"
Write-Output "  warnings: $($warnings.Count)"
foreach ($warning in $warnings) { Write-Warning $warning }
if ($errors.Count -gt 0) { foreach ($message in $errors) { Write-Error $message }; exit 1 }
Write-Output 'PASS: Zhenjie design package is internally consistent.'
if ($closedGates.Count -gt 0) { Write-Output 'STATUS: validated offline; not ready for editor construction.' } else { Write-Output 'STATUS: ready for editor construction.' }
