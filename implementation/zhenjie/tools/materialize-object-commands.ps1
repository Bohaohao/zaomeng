param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    # Retained for command-line compatibility; production path checks are never bypassed.
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
        $property = Get-ExactJsonProperty -Object $Fields -Name $name
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

function Get-ExactJsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    return @($Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name } | Select-Object -First 1)[0]
}

function Test-JsonNumber {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    if ($Value -isnot [byte] -and $Value -isnot [sbyte] -and
        $Value -isnot [int16] -and $Value -isnot [uint16] -and
        $Value -isnot [int32] -and $Value -isnot [uint32] -and
        $Value -isnot [int64] -and $Value -isnot [uint64] -and
        $Value -isnot [single] -and $Value -isnot [double] -and
        $Value -isnot [decimal]) {
        return $false
    }
    $number = [double]$Value
    return -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)
}

function Test-JsonInteger {
    param([AllowNull()][object]$Value)
    if (-not (Test-JsonNumber $Value)) { return $false }
    $number = [double]$Value
    return [math]::Truncate($number) -eq $number
}

function Test-ObjectFieldValue {
    param(
        [AllowNull()][object]$Value,
        [object]$Rule
    )

    switch -CaseSensitive ([string]$Rule.Kind) {
        'boolean' { return $Value -is [bool] }
        'enum' {
            if (-not (Test-JsonInteger $Value)) { return $false }
            return @($Rule.Values) -contains [int]$Value
        }
        'nonnegative_integer' { return (Test-JsonInteger $Value) -and [double]$Value -ge 0 }
        'positive_integer' { return (Test-JsonInteger $Value) -and [double]$Value -gt 0 }
        'nonnegative_number' { return (Test-JsonNumber $Value) -and [double]$Value -ge 0 }
        'positive_number' { return (Test-JsonNumber $Value) -and [double]$Value -gt 0 }
        'nonnegative_number_array' {
            if ($Value -isnot [System.Array]) { return $false }
            foreach ($item in @($Value)) {
                if (-not (Test-JsonNumber $item) -or [double]$item -lt 0) { return $false }
            }
            return $true
        }
        'positive_integer_array' {
            if ($Value -isnot [System.Array]) { return $false }
            foreach ($item in @($Value)) {
                if (-not (Test-JsonInteger $item) -or [double]$item -le 0) { return $false }
            }
            return $true
        }
        'ability_reference_array' {
            if ($Value -isnot [System.Array]) { return $false }
            foreach ($item in @($Value)) {
                if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) { return $false }
            }
            return $true
        }
        default { return $false }
    }
}

function Get-ObjectFieldExpectation {
    param([object]$Rule)
    switch -CaseSensitive ([string]$Rule.Kind) {
        'boolean' { return 'a boolean' }
        'enum' { return 'one of: ' + (@($Rule.Values) -join ', ') }
        'nonnegative_integer' { return 'a non-negative integer' }
        'positive_integer' { return 'a positive integer' }
        'nonnegative_number' { return 'a non-negative finite number' }
        'positive_number' { return 'a positive finite number' }
        'nonnegative_number_array' { return 'an array of non-negative finite numbers' }
        'positive_integer_array' { return 'an array of positive integers' }
        'ability_reference_array' { return 'an array of non-empty ability references' }
        default { return 'a valid value' }
    }
}

function Add-RecordObjectFieldErrors {
    param(
        [object]$Record,
        [System.Collections.IDictionary]$Schema,
        [string[]]$LevelArrayFields,
        [System.Collections.Generic.List[string]]$Errors
    )

    $recordKeyProperty = Get-ExactJsonProperty -Object $Record -Name 'record_key'
    $recordKey = if ($null -ne $recordKeyProperty -and $recordKeyProperty.Value -is [string]) { [string]$recordKeyProperty.Value } else { '<missing record_key>' }
    $fieldsProperty = Get-ExactJsonProperty -Object $Record -Name 'object_fields'
    if ($null -eq $fieldsProperty -or $fieldsProperty.Value -isnot [pscustomobject]) {
        $Errors.Add("${recordKey}: object_fields must be an object")
        return
    }

    $fields = $fieldsProperty.Value
    $schemaNames = @($Schema.Keys)
    foreach ($property in @($fields.PSObject.Properties)) {
        if ($schemaNames -cnotcontains $property.Name) {
            $Errors.Add("${recordKey}: object_fields unknown field: $($property.Name)")
            continue
        }
        $rule = $Schema[$property.Name]
        if (-not (Test-ObjectFieldValue -Value $property.Value -Rule $rule)) {
            $Errors.Add("${recordKey}: object_fields $($property.Name) must be $(Get-ObjectFieldExpectation $rule)")
        }
    }

    if ($LevelArrayFields.Count -eq 0) { return }
    $maxLevel = Get-ExactJsonProperty -Object $fields -Name 'ability_max_level'
    if ($null -eq $maxLevel -or -not (Test-JsonInteger $maxLevel.Value) -or [int]$maxLevel.Value -le 0) { return }
    foreach ($fieldName in $LevelArrayFields) {
        $property = Get-ExactJsonProperty -Object $fields -Name $fieldName
        if ($null -ne $property -and $property.Value -is [System.Array] -and @($property.Value).Count -ne [int]$maxLevel.Value) {
            $Errors.Add("${recordKey}: object_fields $fieldName must contain exactly $([int]$maxLevel.Value) values")
        }
    }
}

$unitFieldSchema = [ordered]@{
    hp_max = [pscustomobject]@{ Kind = 'nonnegative_integer' }
    hp_max_grow = [pscustomobject]@{ Kind = 'nonnegative_number' }
    mp_max = [pscustomobject]@{ Kind = 'nonnegative_integer' }
    mp_max_grow = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_phy = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_phy_grow = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_mag = [pscustomobject]@{ Kind = 'nonnegative_number' }
    defense_phy = [pscustomobject]@{ Kind = 'nonnegative_number' }
    defense_mag = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_speed = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_interval = [pscustomobject]@{ Kind = 'positive_number' }
    common_atk_type = [pscustomobject]@{ Kind = 'nonnegative_integer' }
    ori_speed = [pscustomobject]@{ Kind = 'nonnegative_number' }
    turn_speed = [pscustomobject]@{ Kind = 'nonnegative_number' }
    sight_range = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_range = [pscustomobject]@{ Kind = 'nonnegative_number' }
    common_atk_range = [pscustomobject]@{ Kind = 'nonnegative_number' }
    hero_ability_list = [pscustomobject]@{ Kind = 'ability_reference_array' }
    common_ability_list = [pscustomobject]@{ Kind = 'ability_reference_array' }
}
$abilityFieldSchema = [ordered]@{
    ability_max_level = [pscustomobject]@{ Kind = 'positive_integer' }
    sight_type = [pscustomobject]@{ Kind = 'enum'; Values = @(0, 1, 2, 3, 7) }
    ability_cast_type = [pscustomobject]@{ Kind = 'enum'; Values = @(2, 3) }
    ability_cast_point = [pscustomobject]@{ Kind = 'nonnegative_number' }
    ability_bw_point = [pscustomobject]@{ Kind = 'nonnegative_number' }
    is_immediate = [pscustomobject]@{ Kind = 'boolean' }
    is_meele = [pscustomobject]@{ Kind = 'boolean' }
    cold_down_time = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    ability_cost = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    ability_hp_cost = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    ability_damage = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    ability_damage_range = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    ability_cast_range = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    circle_radius = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    sector_radius = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    sector_angle = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    arrow_length = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    arrow_width = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
    required_level = [pscustomobject]@{ Kind = 'positive_integer_array' }
}
$abilityLevelArrayFields = @(
    'cold_down_time', 'ability_cost', 'ability_hp_cost', 'ability_damage',
    'ability_damage_range', 'ability_cast_range', 'circle_radius',
    'sector_radius', 'sector_angle', 'arrow_length', 'arrow_width', 'required_level'
)
$modifierFieldSchema = [ordered]@{
    modifier_type = [pscustomobject]@{ Kind = 'enum'; Values = @(1, 4) }
    modifier_effect = [pscustomobject]@{ Kind = 'enum'; Values = @(2, 3) }
    layer_max = [pscustomobject]@{ Kind = 'positive_integer' }
    disappear_when_dead = [pscustomobject]@{ Kind = 'boolean' }
    show_on_ui = [pscustomobject]@{ Kind = 'boolean' }
    shield_value = [pscustomobject]@{ Kind = 'nonnegative_number' }
    shield_type = [pscustomobject]@{ Kind = 'enum'; Values = @(2) }
    influence_rng = [pscustomobject]@{ Kind = 'nonnegative_number' }
    is_influence_self = [pscustomobject]@{ Kind = 'boolean' }
    material_color = [pscustomobject]@{ Kind = 'nonnegative_number_array' }
}


function Add-ExecutionGateErrors {
    param(
        [object]$Gates,
        [string[]]$RequiredBooleanGates,
        [System.Collections.Generic.List[string]]$Errors
    )

    if ($Gates -isnot [pscustomobject]) {
        $Errors.Add('execution_gates must be an object')
        return
    }

    $requiredPaths = [ordered]@{
        map_path = 'Leaf'
        script_root = 'Container'
        y3_obj_edit_script = 'Leaf'
    }
    $expectedGates = @($requiredPaths.Keys) + @($RequiredBooleanGates)
    foreach ($gateName in $expectedGates) {
        $property = Get-ExactJsonProperty -Object $Gates -Name $gateName
        if ($null -eq $property) {
            $Errors.Add("execution gate missing: $gateName")
            continue
        }

        if ($requiredPaths.Contains($gateName)) {
            $value = $property.Value
            if (-not ($value -is [string]) -or [string]::IsNullOrWhiteSpace($value)) {
                $Errors.Add("execution gate path invalid: $gateName")
            } elseif (-not (Test-Path -LiteralPath $value -PathType $requiredPaths[$gateName])) {
                $Errors.Add("execution gate path must be $($requiredPaths[$gateName]): $gateName=$value")
            }
        } elseif (-not ($property.Value -is [bool]) -or $property.Value -ne $true) {
            $Errors.Add("execution gate unresolved: $gateName")
        }
    }

    foreach ($property in @($Gates.PSObject.Properties)) {
        if ($expectedGates -cnotcontains $property.Name) {
            $Errors.Add("execution gate unknown: $($property.Name)")
        }
    }
}

$manifestFullPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()
Add-ExecutionGateErrors $manifest.execution_gates @(
    'python_dependencies_ready', 'y3editor_connected', 'unit_id_assigned',
    'ability_ids_assigned', 'modifier_ids_assigned', 'model_id_assigned',
    'icon_ids_assigned', 'cast_types_verified', 'distance_scale_verified',
    'cast_point_resolver_bound', 'guardable_damage_classifier_bound',
    'lifecycle_callback_contract_bound', 'melee_template_verified'
) $errors

$objects = @($manifest.hero) + @($manifest.modifiers) + @($manifest.abilities)
foreach ($object in $objects) {
    $recordKeyProperty = Get-ExactJsonProperty -Object $object -Name 'record_key'
    $recordKey = if ($null -ne $recordKeyProperty -and $recordKeyProperty.Value -is [string]) { [string]$recordKeyProperty.Value } else { '<missing record_key>' }
    $y3Id = Get-ExactJsonProperty -Object $object -Name 'y3_id'
    if ($null -eq $y3Id -or $null -eq $y3Id.Value) {
        $errors.Add("${recordKey}: y3_id unresolved")
    }
    $iconId = Get-ExactJsonProperty -Object $object -Name 'icon_id'
    if ($null -eq $iconId -or $null -eq $iconId.Value) {
        $errors.Add("${recordKey}: icon_id unresolved")
    }
    $unresolvedFields = Get-ExactJsonProperty -Object $object -Name 'unresolved_fields'
    if ($null -eq $unresolvedFields) {
        $errors.Add("${recordKey}: unresolved_fields missing")
    } elseif ($unresolvedFields.Value -isnot [System.Array]) {
        $errors.Add("${recordKey}: unresolved_fields must be an array")
    } elseif (@($unresolvedFields.Value).Count -gt 0) {
        $errors.Add("${recordKey}: unresolved fields: $(@($unresolvedFields.Value) -join ',')")
    }
}
Add-RecordObjectFieldErrors $manifest.hero $unitFieldSchema @() $errors
foreach ($ability in $manifest.abilities) {
    Add-RecordObjectFieldErrors $ability $abilityFieldSchema $abilityLevelArrayFields $errors
}
foreach ($modifier in $manifest.modifiers) {
    Add-RecordObjectFieldErrors $modifier $modifierFieldSchema @() $errors
}
$heroObjectType = Get-ExactJsonProperty -Object $manifest.hero -Name 'object_type'
if ($null -eq $heroObjectType -or $heroObjectType.Value -cne 'unit') {
    $errors.Add('C02_HERO: object_type must be unit')
}
foreach ($ability in $manifest.abilities) {
    $objectType = Get-ExactJsonProperty -Object $ability -Name 'object_type'
    $recordKey = (Get-ExactJsonProperty -Object $ability -Name 'record_key').Value
    if ($null -eq $objectType -or $objectType.Value -cne 'ability') {
        $errors.Add("${recordKey}: object_type must be ability")
    }
}
foreach ($modifier in $manifest.modifiers) {
    $objectType = Get-ExactJsonProperty -Object $modifier -Name 'object_type'
    $recordKey = (Get-ExactJsonProperty -Object $modifier -Name 'record_key').Value
    if ($null -eq $objectType -or $objectType.Value -cne 'modifier') {
        $errors.Add("${recordKey}: object_type must be modifier")
    }
}
$heroModelId = Get-ExactJsonProperty -Object $manifest.hero -Name 'model_id'
if ($null -eq $heroModelId -or $null -eq $heroModelId.Value) {
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

$commonAttackRange = Get-ExactJsonProperty -Object $manifest.hero.object_fields -Name 'common_atk_range'
if ($null -ne $commonAttackRange -and $null -ne $commonAttackRange.Value) {
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
    $lines.Add("Write-Output 'Applied the required post-create common attack range edit.'")
}

$lines.Add("Write-Output 'Created 12 modifiers, 18 abilities, and 1 hero unit.'")
$lines.Add("Write-Output 'Next: hotfix object editor, wait 3 seconds, save, then read back all 31 objects.'")

$parent = Split-Path -Parent $outputFullPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
Set-Content -LiteralPath $outputFullPath -Value $lines -Encoding UTF8
Write-Output "Generated: $outputFullPath"

