param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [switch]$SkipPathExistenceCheck,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Quote-PowerShell {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {
        return "''"
    }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function Format-Scalar {
    param([object]$Value)
    if ($Value -is [bool]) {
        return $(if ($Value) { 'true' } else { 'false' })
    }
    if ($Value -is [string]) {
        return Quote-PowerShell $Value
    }
    return [string]$Value
}

function Add-FieldTokens {
    param(
        [System.Collections.Generic.List[string]]$Tokens,
        $Fields,
        [string[]]$AllowedFields,
        [string[]]$ArrayFields
    )

    foreach ($name in $AllowedFields) {
        $property = $Fields.PSObject.Properties[$name]
        if (-not $property -or $null -eq $property.Value) {
            continue
        }
        $Tokens.Add('-' + $name)
        if ($name -in $ArrayFields) {
            $Tokens.Add((Quote-PowerShell (@($property.Value) -join ',')))
        } else {
            $Tokens.Add((Format-Scalar $property.Value))
        }
    }
}

function Add-Command {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [System.Collections.Generic.List[string]]$Tokens,
        [string]$RecordKey
    )
    $Lines.Add(($Tokens -join ' '))
    $Lines.Add("if (`$LASTEXITCODE -ne 0) { throw 'Failed to create $RecordKey' }")
    $Lines.Add('')
}

$manifestFullPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()

foreach ($property in $manifest.execution_gates.PSObject.Properties) {
    if ($null -eq $property.Value -or $property.Value -eq $false -or $property.Value -eq '') {
        $errors.Add("execution gate unresolved: $($property.Name)")
    }
}

if (-not $SkipPathExistenceCheck) {
    foreach ($gateName in @('map_path', 'script_root', 'y3_obj_edit_script')) {
        $value = $manifest.execution_gates.$gateName
        if ($value -and -not (Test-Path -LiteralPath $value)) {
            $errors.Add("path does not exist: $gateName=$value")
        }
    }
}

$objects = @($manifest.hero) + @($manifest.modifiers) + @($manifest.abilities)
foreach ($object in $objects) {
    if ($null -eq $object.y3_id) {
        $errors.Add("$($object.record_key): y3_id unresolved")
    }
    if ($null -eq $object.icon_id) {
        $errors.Add("$($object.record_key): icon_id unresolved")
    }
    if ($object.PSObject.Properties['unresolved_fields'] -and @($object.unresolved_fields).Count -gt 0) {
        $errors.Add("$($object.record_key): unresolved fields: $(@($object.unresolved_fields) -join ',')")
    }
}
if ($null -eq $manifest.hero.model_id) {
    $errors.Add('C02_HERO: model_id unresolved')
}

if ($errors.Count -gt 0) {
    Write-Output 'Zhenjie object command materialization refused:'
    foreach ($message in $errors) {
        Write-Output ('  - ' + $message)
    }
    exit 1
}

$outputFullPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
}
if ((Test-Path -LiteralPath $outputFullPath) -and -not $Force) {
    throw "Output already exists: $outputFullPath. Pass -Force to replace it."
}

$mapPath = [string]$manifest.execution_gates.map_path
$editorScript = [string]$manifest.execution_gates.y3_obj_edit_script
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Generated from Zhenjie preconstruction manifest. Do not edit Y3 JSON directly.")
$lines.Add("`$ErrorActionPreference = 'Stop'")
$lines.Add('')

$modifierFields = @(
    'modifier_type', 'modifier_effect', 'layer_max', 'disappear_when_dead',
    'show_on_ui', 'shield_value', 'shield_type', 'influence_rng',
    'is_influence_self', 'material_color'
)
$modifierArrayFields = @('material_color')

foreach ($modifier in $manifest.modifiers) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    $tokens.Add('& py -3')
    $tokens.Add((Quote-PowerShell $editorScript))
    $tokens.Add('-map')
    $tokens.Add((Quote-PowerShell $mapPath))
    $tokens.Add('-type modifier -create')
    $tokens.Add((Quote-PowerShell ("$($modifier.y3_id),$($modifier.name),$($modifier.icon_id)")))
    Add-FieldTokens $tokens $modifier.object_fields $modifierFields $modifierArrayFields
    Add-Command $lines $tokens $modifier.record_key
}

$abilityFields = @(
    'ability_max_level', 'sight_type', 'ability_cast_type', 'ability_cast_point',
    'ability_bw_point', 'is_immediate', 'is_meele', 'cold_down_time',
    'ability_cost', 'ability_hp_cost', 'ability_damage', 'ability_damage_range',
    'ability_cast_range', 'circle_radius', 'sector_radius', 'sector_angle',
    'arrow_length', 'arrow_width', 'required_level'
)
$abilityArrayFields = @(
    'cold_down_time', 'ability_cost', 'ability_hp_cost', 'ability_damage',
    'ability_damage_range', 'ability_cast_range', 'circle_radius',
    'sector_radius', 'sector_angle', 'arrow_length', 'arrow_width', 'required_level'
)

foreach ($ability in $manifest.abilities) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    $tokens.Add('& py -3')
    $tokens.Add((Quote-PowerShell $editorScript))
    $tokens.Add('-map')
    $tokens.Add((Quote-PowerShell $mapPath))
    $tokens.Add('-type ability -create')
    $tokens.Add((Quote-PowerShell ("$($ability.y3_id),$($ability.name),$($ability.icon_id)")))
    Add-FieldTokens $tokens $ability.object_fields $abilityFields $abilityArrayFields
    Add-Command $lines $tokens $ability.record_key
}

$unitFields = @(
    'hp_max', 'hp_max_grow', 'mp_max', 'mp_max_grow', 'attack_phy',
    'attack_phy_grow', 'attack_mag', 'defense_phy', 'defense_mag',
    'attack_speed', 'attack_interval', 'common_atk_type', 'ori_speed',
    'turn_speed', 'sight_range', 'attack_range',
    'hero_ability_list', 'common_ability_list'
)
$unitArrayFields = @('hero_ability_list', 'common_ability_list')
$heroTokens = [System.Collections.Generic.List[string]]::new()
$heroTokens.Add('& py -3')
$heroTokens.Add((Quote-PowerShell $editorScript))
$heroTokens.Add('-map')
$heroTokens.Add((Quote-PowerShell $mapPath))
$heroTokens.Add('-type unit -create')
$heroTokens.Add((Quote-PowerShell ("$($manifest.hero.y3_id),$($manifest.hero.name),$($manifest.hero.unit_type),$($manifest.hero.model_id),$($manifest.hero.icon_id)")))
Add-FieldTokens $heroTokens $manifest.hero.object_fields $unitFields $unitArrayFields
Add-Command $lines $heroTokens $manifest.hero.record_key

$commonAttackRange = $manifest.hero.object_fields.PSObject.Properties['common_atk_range']
if ($commonAttackRange -and $null -ne $commonAttackRange.Value) {
    $rangeTokens = [System.Collections.Generic.List[string]]::new()
    $rangeTokens.Add('& py -3')
    $rangeTokens.Add((Quote-PowerShell $editorScript))
    $rangeTokens.Add('-map')
    $rangeTokens.Add((Quote-PowerShell $mapPath))
    $rangeTokens.Add('-type unit -edit')
    $rangeTokens.Add((Format-Scalar $manifest.hero.y3_id))
    $rangeTokens.Add('-common_atk_range')
    $rangeTokens.Add((Format-Scalar $commonAttackRange.Value))
    Add-Command $lines $rangeTokens ($manifest.hero.record_key + ':common_atk_range')
}

$lines.Add("Write-Output 'Created 12 modifiers, 18 abilities, and 1 hero unit.'")
$lines.Add("Write-Output 'Applied the required post-create common attack range edit.'")
$lines.Add("Write-Output 'Next: hotfix object editor, wait 3 seconds, save, then read back all 31 objects.'")

$parent = Split-Path -Parent $outputFullPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
Set-Content -LiteralPath $outputFullPath -Value $lines -Encoding UTF8
Write-Output "Generated: $outputFullPath"

