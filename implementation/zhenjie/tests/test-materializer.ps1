$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$manifestPath = Join-Path $packageRoot 'preconstruction-manifest.json'
$materializer = Join-Path $packageRoot 'tools\materialize-object-commands.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('zhenjie-materializer-' + [Guid]::NewGuid().ToString('N'))
$fixturePath = Join-Path $tempRoot 'resolved-test-manifest.json'
$outputPath = Join-Path $tempRoot 'commands.ps1'
$refusedOutput = Join-Path $tempRoot 'must-not-exist.ps1'
$syntheticMapPath = Join-Path $tempRoot 'maps\EntryMap.map'
$syntheticScriptRoot = Join-Path $tempRoot 'maps\EntryMap\script'
$syntheticEditor = Join-Path $tempRoot 'y3_obj_edit.py'

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $syntheticMapPath) -Force | Out-Null
New-Item -ItemType Directory -Path $syntheticScriptRoot -Force | Out-Null
Set-Content -LiteralPath $syntheticMapPath -Encoding UTF8 -Value '# synthetic map fixture'
Set-Content -LiteralPath $syntheticEditor -Encoding UTF8 -Value '# synthetic object-editor fixture'

function Assert-MaterializerRefusal {
    param(
        [object]$Fixture,
        [string]$Name,
        [string[]]$ExpectedMessages
    )

    $fixturePath = Join-Path $tempRoot ($Name + '-manifest.json')
    $output = Join-Path $tempRoot ($Name + '-commands.ps1')
    $Fixture | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixturePath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $materializer -ManifestPath $fixturePath -OutputPath $output -SkipPathExistenceCheck 2>&1
    if ($LASTEXITCODE -ne 1) {
        throw "$Name must be refused."
    }
    foreach ($expectedMessage in $ExpectedMessages) {
        if (($result -join "`n") -notmatch [regex]::Escape($expectedMessage)) {
            throw "$Name must be refused with: $expectedMessage"
        }
    }
    if (Test-Path -LiteralPath $output) {
        throw "$Name must not create an output file."
    }
}

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $manifest.execution_gates.PSObject.Properties) {
        if ($property.Name -eq 'map_path') {
            $property.Value = $syntheticMapPath
        } elseif ($property.Name -eq 'script_root') {
            $property.Value = $syntheticScriptRoot
        } elseif ($property.Name -eq 'y3_obj_edit_script') {
            $property.Value = $syntheticEditor
        } else {
            $property.Value = $true
        }
    }

    $manifest.hero.y3_id = 990100001
    $manifest.hero.model_id = 990900001
    $manifest.hero.icon_id = 990900002
    $manifest.hero.unresolved_fields = @()
    $manifest.hero.object_fields | Add-Member -NotePropertyName common_atk_type -NotePropertyValue 1
    $manifest.hero.object_fields | Add-Member -NotePropertyName turn_speed -NotePropertyValue 10
    $manifest.hero.object_fields | Add-Member -NotePropertyName sight_range -NotePropertyValue 1200
    $manifest.hero.object_fields | Add-Member -NotePropertyName common_atk_range -NotePropertyValue 200
    $manifest.hero.object_fields | Add-Member -NotePropertyName hero_ability_list -NotePropertyValue @('990200001:1','990200018:1')
    $manifest.hero.object_fields | Add-Member -NotePropertyName common_ability_list -NotePropertyValue @('990800001:1')

    $index = 0
    foreach ($ability in $manifest.abilities) {
        $index++
        $ability.y3_id = 990200000 + $index
        $ability.icon_id = 990910000 + $index
        $ability.unresolved_fields = @()
        $levels = [int]$ability.object_fields.ability_max_level
        $geometry = @(1..$levels | ForEach-Object { 100 })
        $ability.object_fields | Add-Member -NotePropertyName ability_damage_range -NotePropertyValue $geometry
        if ($ability.object_fields.sight_type -eq 1) {
            $ability.object_fields | Add-Member -NotePropertyName sector_radius -NotePropertyValue $geometry
            $ability.object_fields | Add-Member -NotePropertyName sector_angle -NotePropertyValue @(1..$levels | ForEach-Object { 90 })
        } elseif ($ability.object_fields.sight_type -eq 2 -or $ability.object_fields.sight_type -eq 7) {
            $ability.object_fields | Add-Member -NotePropertyName arrow_length -NotePropertyValue $geometry
            $ability.object_fields | Add-Member -NotePropertyName arrow_width -NotePropertyValue @(1..$levels | ForEach-Object { 50 })
        }
    }

    $index = 0
    foreach ($modifier in $manifest.modifiers) {
        $index++
        $modifier.y3_id = 990300000 + $index
        $modifier.icon_id = 990920000 + $index
        $modifier.unresolved_fields = @()
    }

    $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixturePath -Encoding UTF8

    & powershell -NoProfile -ExecutionPolicy Bypass -File $materializer -ManifestPath $fixturePath -OutputPath $outputPath -SkipPathExistenceCheck
    if ($LASTEXITCODE -ne 0) {
        throw "Synthetic materialization failed with exit code $LASTEXITCODE"
    }

    $generated = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
    $modifierCount = ([regex]::Matches($generated, '-type modifier -create')).Count
    $abilityCount = ([regex]::Matches($generated, '-type ability -create')).Count
    $unitCount = ([regex]::Matches($generated, '-type unit -create')).Count
    $unitEditCount = ([regex]::Matches($generated, '-type unit -edit')).Count
    if ($modifierCount -ne 12 -or $abilityCount -ne 18 -or $unitCount -ne 1 -or $unitEditCount -ne 1) {
        throw "Generated counts mismatch: modifier=$modifierCount ability=$abilityCount unit=$unitCount"
    }
    $firstModifier = $generated.IndexOf('-type modifier -create')
    $firstAbility = $generated.IndexOf('-type ability -create')
    $firstUnit = $generated.IndexOf('-type unit -create')
    if (-not ($firstModifier -lt $firstAbility -and $firstAbility -lt $firstUnit)) {
        throw 'Generated creation order must be modifiers, abilities, hero.'
    }
    if ($generated.IndexOf('-type unit -edit') -lt $firstUnit) {
        throw 'Common attack range edit must occur after hero creation.'
    }

    $missingPathFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $missingPathFixture.execution_gates.map_path = Join-Path $tempRoot 'missing-map-path'
    Assert-MaterializerRefusal $missingPathFixture 'missing-path' 'execution gate path must be Leaf: map_path'

    $missingGateFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $missingGateFixture.execution_gates.PSObject.Properties.Remove('python_dependencies_ready')
    Assert-MaterializerRefusal $missingGateFixture 'missing-gate' 'execution gate missing: python_dependencies_ready'

    $unknownGateFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $unknownGateFixture.execution_gates | Add-Member -NotePropertyName unexpected_gate -NotePropertyValue $true
    Assert-MaterializerRefusal $unknownGateFixture 'unknown-gate' 'execution gate unknown: unexpected_gate'

    $stringGateFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $stringGateFixture.execution_gates.python_dependencies_ready = 'pending'
    Assert-MaterializerRefusal $stringGateFixture 'string-gate' 'execution gate unresolved: python_dependencies_ready'

    $mapTypeFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $mapTypeFixture.execution_gates.map_path = $syntheticScriptRoot
    Assert-MaterializerRefusal $mapTypeFixture 'map-path-type' 'execution gate path must be Leaf: map_path'

    $scriptRootTypeFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $scriptRootTypeFixture.execution_gates.script_root = $syntheticEditor
    Assert-MaterializerRefusal $scriptRootTypeFixture 'script-root-type' 'execution gate path must be Container: script_root'

    $editorTypeFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $editorTypeFixture.execution_gates.y3_obj_edit_script = $syntheticScriptRoot
    Assert-MaterializerRefusal $editorTypeFixture 'editor-path-type' 'execution gate path must be Leaf: y3_obj_edit_script'

    $missingUnresolvedFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $missingUnresolvedFixture.hero.PSObject.Properties.Remove('unresolved_fields')
    Assert-MaterializerRefusal $missingUnresolvedFixture 'missing-unresolved-fields' 'C02_HERO: unresolved_fields missing'

    $invalidUnresolvedFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $invalidUnresolvedFixture.hero.unresolved_fields = 'pending'
    Assert-MaterializerRefusal $invalidUnresolvedFixture 'invalid-unresolved-fields' 'C02_HERO: unresolved_fields must be an array'

    $caseGateFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $caseGateFixture.execution_gates.PSObject.Properties.Remove('python_dependencies_ready')
    $caseGateFixture.execution_gates | Add-Member -NotePropertyName Python_Dependencies_Ready -NotePropertyValue $true
    Assert-MaterializerRefusal $caseGateFixture 'case-gate-key' 'execution gate missing: python_dependencies_ready'

    $caseObjectTypeValueFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $caseObjectTypeValueFixture.hero.object_type = 'Unit'
    Assert-MaterializerRefusal $caseObjectTypeValueFixture 'case-object-type-value' 'C02_HERO: object_type must be unit'

    $caseObjectTypeKeyFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $caseObjectTypeKeyFixture.hero.PSObject.Properties.Remove('object_type')
    $caseObjectTypeKeyFixture.hero | Add-Member -NotePropertyName Object_Type -NotePropertyValue 'unit'
    Assert-MaterializerRefusal $caseObjectTypeKeyFixture 'case-object-type-key' 'C02_HERO: object_type must be unit'

    $caseUnresolvedKeyFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $caseUnresolvedKeyFixture.hero.PSObject.Properties.Remove('unresolved_fields')
    $caseUnresolvedKeyFixture.hero | Add-Member -NotePropertyName Unresolved_Fields -NotePropertyValue @()
    Assert-MaterializerRefusal $caseUnresolvedKeyFixture 'case-unresolved-key' 'C02_HERO: unresolved_fields missing'

    $invalidHeroTypeFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $invalidHeroTypeFixture.hero.object_type = 'modifier'
    Assert-MaterializerRefusal $invalidHeroTypeFixture 'invalid-hero-type' 'C02_HERO: object_type must be unit'

    $invalidAbilityTypeFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $invalidAbilityTypeFixture.abilities[0].object_type = 'modifier'
    Assert-MaterializerRefusal $invalidAbilityTypeFixture 'invalid-ability-type' 'C02_F01: object_type must be ability'

    $invalidModifierTypeFixture = $manifest | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $invalidModifierTypeFixture.modifiers[0].object_type = 'ability'
    Assert-MaterializerRefusal $invalidModifierTypeFixture 'invalid-modifier-type' 'C02_M01_JIESHI: object_type must be modifier'

    $schemaFixtureBase = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $heroKey = [string]$schemaFixtureBase.hero.record_key
    $abilityKey = [string]$schemaFixtureBase.abilities[0].record_key
    $activeAbilityKey = [string]$schemaFixtureBase.abilities[1].record_key
    $modifierKey = [string]$schemaFixtureBase.modifiers[0].record_key

    $unknownFieldsFixture = $schemaFixtureBase | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $unknownFieldsFixture.abilities[0].object_fields | Add-Member -NotePropertyName unexpected_field -NotePropertyValue 1
    $unknownFieldsFixture.abilities[0].object_fields.PSObject.Properties.Remove('ability_cast_type')
    $unknownFieldsFixture.abilities[0].object_fields | Add-Member -NotePropertyName Ability_Cast_Type -NotePropertyValue 3
    Assert-MaterializerRefusal $unknownFieldsFixture 'unknown-object-fields' @(
        "${abilityKey}: object_fields unknown field: unexpected_field",
        "${abilityKey}: object_fields unknown field: Ability_Cast_Type"
    )

    $invalidEnumFixture = $schemaFixtureBase | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $invalidEnumFixture.abilities[0].object_fields.ability_cast_type = 99
    $invalidEnumFixture.abilities[0].object_fields.sight_type = 99
    $invalidEnumFixture.modifiers[0].object_fields.modifier_type = 99
    $invalidEnumFixture.modifiers[0].object_fields.modifier_effect = 99
    Assert-MaterializerRefusal $invalidEnumFixture 'invalid-object-field-enums' @(
        "${abilityKey}: object_fields ability_cast_type must be one of: 2, 3",
        "${abilityKey}: object_fields sight_type must be one of: 0, 1, 2, 3, 7",
        "${modifierKey}: object_fields modifier_type must be one of: 1, 4",
        "${modifierKey}: object_fields modifier_effect must be one of: 2, 3"
    )

    $invalidShapeFixture = $schemaFixtureBase | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $invalidShapeFixture.hero.object_fields.hp_max = '620'
    $invalidShapeFixture.abilities[0].object_fields.ability_cost = 0
    $invalidShapeFixture.abilities[1].object_fields.is_immediate = 0
    $invalidShapeFixture.modifiers[0].object_fields | Add-Member -NotePropertyName material_color -NotePropertyValue 'red'
    Assert-MaterializerRefusal $invalidShapeFixture 'invalid-object-field-shapes' @(
        "${heroKey}: object_fields hp_max must be a non-negative integer",
        "${abilityKey}: object_fields ability_cost must be an array of non-negative finite numbers",
        "${activeAbilityKey}: object_fields is_immediate must be a boolean",
        "${modifierKey}: object_fields material_color must be an array of non-negative finite numbers"
    )

    $invalidLengthFixture = $schemaFixtureBase | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $invalidLengthFixture.abilities[0].object_fields.ability_cost = @(0, 0)
    Assert-MaterializerRefusal $invalidLengthFixture 'invalid-level-array-length' "${abilityKey}: object_fields ability_cost must contain exactly 1 values"

    $noRangeFixture = $schemaFixtureBase | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $noRangeFixture.hero.object_fields.PSObject.Properties.Remove('common_atk_range')
    $noRangeFixturePath = Join-Path $tempRoot 'no-common-atk-range-manifest.json'
    $noRangeOutput = Join-Path $tempRoot 'no-common-atk-range-commands.ps1'
    $noRangeFixture | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $noRangeFixturePath -Encoding UTF8
    $noRangeResult = & powershell -NoProfile -ExecutionPolicy Bypass -File $materializer -ManifestPath $noRangeFixturePath -OutputPath $noRangeOutput -SkipPathExistenceCheck 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Manifest without canonical common_atk_range must materialize without an edit: $($noRangeResult -join "`n")"
    }
    if ((Get-Content -LiteralPath $noRangeOutput -Raw -Encoding UTF8) -match '-type unit -edit') {
        throw 'Common attack range edit must not be emitted without the exact canonical field.'
    }

    $caseRangeFixture = $schemaFixtureBase | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $caseRangeFixture.hero.object_fields.PSObject.Properties.Remove('common_atk_range')
    $caseRangeFixture.hero.object_fields | Add-Member -NotePropertyName Common_Atk_Range -NotePropertyValue 200
    Assert-MaterializerRefusal $caseRangeFixture 'case-common-atk-range' "${heroKey}: object_fields unknown field: Common_Atk_Range"


    $refusal = & powershell -NoProfile -ExecutionPolicy Bypass -File $materializer -ManifestPath $manifestPath -OutputPath $refusedOutput -SkipPathExistenceCheck 2>&1
    if ($LASTEXITCODE -ne 1) {
        throw 'Unresolved production manifest must be refused.'
    }
    if (Test-Path -LiteralPath $refusedOutput) {
        throw 'Refused materialization must not create an output file.'
    }

    Write-Output 'PASS: materializer generated 31 creates and strictly enforced gate, path, type, and unresolved-field contracts.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

