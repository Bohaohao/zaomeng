param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$SkipPathExistenceCheck,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
function Quote-PowerShell { param([AllowNull()][object]$Value) if ($null -eq $Value) { return "''" }; return "'" + ([string]$Value).Replace("'", "''") + "'" }
function Scalar { param([object]$Value) if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }; if ($Value -is [string]) { return Quote-PowerShell $Value }; return [string]$Value }
function Add-Fields {
    param([System.Collections.Generic.List[string]]$Tokens, $Fields, [string[]]$Names, [string[]]$ArrayNames)
    foreach ($name in $Names) {
        $property = $Fields.PSObject.Properties[$name]
        if (-not $property -or $null -eq $property.Value) { continue }
        $Tokens.Add('-' + $name)
        if ($name -in $ArrayNames) { $Tokens.Add((Quote-PowerShell (@($property.Value) -join ','))) }
        else { $Tokens.Add((Scalar $property.Value)) }
    }
}

$manifest = Get-Content -Raw -Encoding UTF8 (Resolve-Path -LiteralPath $ManifestPath) | ConvertFrom-Json
$errors = [System.Collections.Generic.List[string]]::new()
foreach ($property in $manifest.execution_gates.PSObject.Properties) {
    if ($null -eq $property.Value -or $property.Value -eq $false -or $property.Value -eq '') { $errors.Add("execution gate unresolved: $($property.Name)") }
}
if (-not $SkipPathExistenceCheck) {
    foreach ($gate in @('map_path','script_root','y3_obj_edit_script')) {
        $value = $manifest.execution_gates.$gate
        if ($value -and -not (Test-Path -LiteralPath $value)) { $errors.Add("path does not exist: $gate=$value") }
    }
}
$objects = @($manifest.hero) + @($manifest.modifiers) + @($manifest.abilities)
foreach ($object in $objects) {
    if ($null -eq $object.y3_id) { $errors.Add("$($object.record_key): y3_id unresolved") }
    if ($null -eq $object.icon_id) { $errors.Add("$($object.record_key): icon_id unresolved") }
    if (@($object.unresolved_fields).Count -gt 0) { $errors.Add("$($object.record_key): unresolved fields: $(@($object.unresolved_fields) -join ',')") }
}
if ($null -eq $manifest.hero.model_id) { $errors.Add('C03_HERO: model_id unresolved') }
if ($errors.Count -gt 0) { Write-Output 'Chiming object command materialization refused:'; foreach ($message in $errors) { Write-Output ('  - ' + $message) }; exit 1 }

$outputFullPath = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath)) }
if ((Test-Path -LiteralPath $outputFullPath) -and -not $Force) { throw "Output already exists: $outputFullPath. Pass -Force to replace it." }
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Generated from Chiming preconstruction manifest. Do not edit Y3 JSON directly.')
$lines.Add("`$ErrorActionPreference = 'Stop'")
$editor = [string]$manifest.execution_gates.y3_obj_edit_script
$map = [string]$manifest.execution_gates.map_path
$modifierFields = @('modifier_type','modifier_effect','layer_max','disappear_when_dead','show_on_ui','shield_value','shield_type','influence_rng','is_influence_self','material_color')
foreach ($modifier in $manifest.modifiers) {
    $tokens = [System.Collections.Generic.List[string]]::new(); $tokens.Add('& py -3'); $tokens.Add((Quote-PowerShell $editor)); $tokens.Add('-map'); $tokens.Add((Quote-PowerShell $map)); $tokens.Add('-type modifier -create'); $tokens.Add((Quote-PowerShell "$($modifier.y3_id),$($modifier.name),$($modifier.icon_id)"))
    Add-Fields $tokens $modifier.object_fields $modifierFields @('material_color')
    $lines.Add(($tokens -join ' ')); $lines.Add("if (`$LASTEXITCODE -ne 0) { throw 'Failed to create $($modifier.record_key)' }")
}
$abilityFields = @('ability_max_level','sight_type','ability_cast_type','ability_cast_point','ability_bw_point','is_immediate','is_meele','cold_down_time','ability_cost','ability_hp_cost','ability_damage','ability_damage_range','ability_cast_range','circle_radius','sector_radius','sector_angle','arrow_length','arrow_width','required_level')
$abilityArrays = @('cold_down_time','ability_cost','ability_hp_cost','ability_damage','ability_damage_range','ability_cast_range','circle_radius','sector_radius','sector_angle','arrow_length','arrow_width','required_level')
foreach ($ability in $manifest.abilities) {
    $tokens = [System.Collections.Generic.List[string]]::new(); $tokens.Add('& py -3'); $tokens.Add((Quote-PowerShell $editor)); $tokens.Add('-map'); $tokens.Add((Quote-PowerShell $map)); $tokens.Add('-type ability -create'); $tokens.Add((Quote-PowerShell "$($ability.y3_id),$($ability.name),$($ability.icon_id)"))
    Add-Fields $tokens $ability.object_fields $abilityFields $abilityArrays
    $lines.Add(($tokens -join ' ')); $lines.Add("if (`$LASTEXITCODE -ne 0) { throw 'Failed to create $($ability.record_key)' }")
}
$unitFields = @('hp_max','hp_max_grow','mp_max','mp_max_grow','attack_phy','attack_phy_grow','attack_mag','defense_phy','defense_mag','attack_speed','attack_interval','common_atk_type','ori_speed','turn_speed','sight_range','attack_range','hero_ability_list','common_ability_list')
$heroTokens = [System.Collections.Generic.List[string]]::new(); $heroTokens.Add('& py -3'); $heroTokens.Add((Quote-PowerShell $editor)); $heroTokens.Add('-map'); $heroTokens.Add((Quote-PowerShell $map)); $heroTokens.Add('-type unit -create'); $heroTokens.Add((Quote-PowerShell "$($manifest.hero.y3_id),$($manifest.hero.name),$($manifest.hero.unit_type),$($manifest.hero.model_id),$($manifest.hero.icon_id)"))
Add-Fields $heroTokens $manifest.hero.object_fields $unitFields @('hero_ability_list','common_ability_list')
$lines.Add(($heroTokens -join ' ')); $lines.Add("if (`$LASTEXITCODE -ne 0) { throw 'Failed to create C03_HERO' }")
if ($manifest.hero.object_fields.PSObject.Properties['common_atk_range']) {
    $lines.Add("& py -3 $(Quote-PowerShell $editor) -map $(Quote-PowerShell $map) -type unit -edit $($manifest.hero.y3_id) -common_atk_range $(Scalar $manifest.hero.object_fields.common_atk_range)")
}
$lines.Add("Write-Output 'Created 12 modifiers, 18 abilities, and 1 hero unit.'")
$lines.Add("Write-Output 'Next: hotfix object editor, save, and read back all 31 objects.'")
$parent = Split-Path -Parent $outputFullPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
Set-Content -LiteralPath $outputFullPath -Value $lines -Encoding UTF8
Write-Output "Generated: $outputFullPath"
