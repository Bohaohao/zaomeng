[CmdletBinding()]
param(
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$script:AssertionCount = 0

function Assert-That {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:AssertionCount++
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Assert-NullFields {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Label
    )

    foreach ($Field in $Fields) {
        Assert-That -Condition ($null -ne $Object.PSObject.Properties[$Field]) -Message "$Label.$Field must be reserved explicitly"
        Assert-That -Condition ($null -eq $Object.$Field) -Message "$Label.$Field must remain null"
    }
}

function Assert-RequiredProperties {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Label
    )

    foreach ($Field in $Fields) {
        Assert-That -Condition ($null -ne $Object.PSObject.Properties[$Field]) -Message "$Label.$Field must be present"
    }
}

function Assert-NoNormalizedDesignProperties {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) {
        return
    }

    if ($Value -is [System.Array]) {
        for ($Index = 0; $Index -lt $Value.Count; $Index++) {
            Assert-NoNormalizedDesignProperties -Value $Value[$Index] -Path "$Path[$Index]"
        }
        return
    }

    foreach ($Property in $Value.PSObject.Properties) {
        Assert-That -Condition ($Property.Name -notin @('assets', 'mode')) -Message "$Path.$($Property.Name) must not be a normalized-design property"
        Assert-NoNormalizedDesignProperties -Value $Property.Value -Path "$Path.$($Property.Name)"
    }
}

function Assert-NonEmptyString {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-That -Condition ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value)) -Message "$Label must be a non-empty string"
    if ($Value -is [string]) {
        Assert-That -Condition ($Value -notmatch '(?i)(?:stable_object_key|copyfrom|source_template_key|editor_field_mapping|unit_object_id|ability_object_ids|buff_object_ids|projectile_object_ids|model_resource_id|animation_resource_id|vfx_resource_id|sound_resource_id|material_resource_id|icon_resource_id)\s*(?:=|:)') -Message "$Label must not embed a direct object, template or resource binding"
        Assert-That -Condition ($Value -notmatch '(?:=|:)\s*[+-]?\d+(?:\.\d+)?') -Message "$Label must not embed a direct numeric projection"
    }
}

function Assert-NonEmptyStringArray {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][int]$MinimumCount,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-That -Condition ($Value -is [System.Array] -and $Value.Count -ge $MinimumCount) -Message "$Label must be an array with at least $MinimumCount entries"
    if ($Value -is [System.Array]) {
        for ($Index = 0; $Index -lt $Value.Count; $Index++) {
            Assert-NonEmptyString -Value $Value[$Index] -Label "$Label[$Index]"
        }
    }
}

function Assert-AllRuntimeKeysNull {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) {
        return
    }

    if ($Value -is [System.Array]) {
        for ($Index = 0; $Index -lt $Value.Count; $Index++) {
            Assert-AllRuntimeKeysNull -Value $Value[$Index] -Path "$Path[$Index]"
        }
        return
    }

    foreach ($Property in $Value.PSObject.Properties) {
        $PropertyPath = "$Path.$($Property.Name)"
        if ($Property.Name -match '^(runtime(?:_.+)?_key|runtimeKey)$') {
            Assert-That -Condition ($null -eq $Property.Value) -Message "$PropertyPath must remain null"
        }
        Assert-AllRuntimeKeysNull -Value $Property.Value -Path $PropertyPath
    }
}

function Test-OnlyAllowedPropertyNames {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string[]]$Allowed
    )

    if ($null -eq $Object) {
        return $false
    }

    $Unexpected = @($Object.PSObject.Properties | Where-Object { $_.Name -notin $Allowed })
    return $Unexpected.Count -eq 0
}

function Assert-OnlyAllowedPropertyNames {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $Unexpected = @($Object.PSObject.Properties | Where-Object { $_.Name -notin $Allowed } | ForEach-Object { $_.Name })
    Assert-That -Condition ($Unexpected.Count -eq 0) -Message "$Label must not introduce unreserved fields: $($Unexpected -join ', ')"
}

function Get-NamedStringPropertyValues {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $Values = [System.Collections.Generic.List[string]]::new()

    function Visit-Value {
        param([AllowNull()]$Node)

        if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) {
            return
        }

        if ($Node -is [System.Array]) {
            foreach ($Item in $Node) {
                Visit-Value -Node $Item
            }
            return
        }

        foreach ($Property in $Node.PSObject.Properties) {
            if ($Property.Name -eq $PropertyName -and -not [string]::IsNullOrWhiteSpace([string]$Property.Value)) {
                $Values.Add([string]$Property.Value) | Out-Null
            }
            Visit-Value -Node $Property.Value
        }
    }

    Visit-Value -Node $Value
    return @($Values | Sort-Object -Unique)
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($Hasher.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $Hasher.Dispose()
    }
}

function Get-CanonicalJsonSha256 {
    param([Parameter(Mandatory = $true)]$Value)

    $Json = $Value | ConvertTo-Json -Depth 100 -Compress
    $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Json)
    return Get-Sha256Hex -Bytes $Bytes
}

$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$SpecRoot = Split-Path -Parent $PackageRoot
$ContractPath = Join-Path $PackageRoot 'tianting-object-field-reservation-contract.json'
$ReadmePath = Join-Path $PackageRoot 'README.md'
$MarkdownSpecifications = @(Get-ChildItem -LiteralPath $PackageRoot -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' })
Assert-That -Condition ($MarkdownSpecifications.Count -eq 1) -Message 'exactly one human-readable specification must exist beside README'
$MarkdownPath = $MarkdownSpecifications[0].FullName

$ExpectedPackageFiles = @(
    'README.md',
    'tianting-object-field-reservation-contract.json',
    [string]$MarkdownSpecifications[0].Name,
    'tests/Test-ObjectFieldReservation.ps1',
    'tests/run-all.ps1'
) | Sort-Object
$ActualPackageFiles = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File |
    ForEach-Object { $_.FullName.Substring($PackageRoot.Length + 1).Replace('\', '/') } |
    Sort-Object)
Assert-That -Condition (($ActualPackageFiles -join '|') -eq ($ExpectedPackageFiles -join '|')) -Message "package file allow-list must remain exact; expected: $($ExpectedPackageFiles -join ', '); found: $($ActualPackageFiles -join ', ')"

foreach ($Path in @($ContractPath, $MarkdownPath, $ReadmePath)) {
    Assert-That -Condition (Test-Path -LiteralPath $Path -PathType Leaf) -Message "required package file must exist: $Path"
}

foreach ($RelativePath in @(
    'object-blueprint\tianting-object-art-vfx-blueprint-contract.json',
    'enemy-ecology\tianting-enemy-ecology-contract.json',
    'mainline-boss\tianting-mainline-boss-contract.json',
    'tianting-content-expansion-contract.json',
    'combat\tianting-combat-readability-contract.json'
)) {
    Assert-That -Condition (Test-Path -LiteralPath (Join-Path $SpecRoot $RelativePath) -PathType Leaf) -Message "source material must exist: $RelativePath"
}

$WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $SpecRoot '..\..\..')).Path
foreach ($RelativePath in @(
    'implementation\combat-calibration\contract\cross-profession-combat-calibration-contract.json',
    'implementation\tianting-surface-construction-manifest\surface-construction-manifest.json'
)) {
    Assert-That -Condition (Test-Path -LiteralPath (Join-Path $WorkspaceRoot $RelativePath) -PathType Leaf) -Message "external source material must exist: $RelativePath"
}

try {
    $ContractSnapshotBytes = [System.IO.File]::ReadAllBytes($ContractPath)
    $ContractSnapshotSha256 = Get-Sha256Hex -Bytes $ContractSnapshotBytes
    $ContractJson = [System.Text.UTF8Encoding]::new($false).GetString($ContractSnapshotBytes)
    if ($ContractJson.Length -gt 0 -and $ContractJson[0] -eq [char]0xFEFF) {
        $ContractJson = $ContractJson.Substring(1)
    }
    $Contract = $ContractJson | ConvertFrom-Json
}
catch {
    throw "contract must be valid UTF-8 JSON: $($_.Exception.Message)"
}

$Markdown = Get-Content -LiteralPath $MarkdownPath -Raw -Encoding UTF8
$Readme = Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8

Assert-OnlyAllowedPropertyNames -Object $Contract -Allowed @('schema_version', 'identity', 'scope', 'source_contracts', 'gate_snapshot', 'card_schema', 'field_reservation_profiles', 'shared_semantic_families', 'logical_asset_groups', 'acceptance', 'hard_boundaries') -Label 'contract'
Assert-OnlyAllowedPropertyNames -Object $Contract.identity -Allowed @('spec_id', 'display_name', 'package_status', 'production_gate', 'runtime_key', 'plugin_generation', 'normalized_design_input', 'generated_plugin') -Label 'identity'
Assert-OnlyAllowedPropertyNames -Object $Contract.scope -Allowed @('included', 'excluded') -Label 'scope'
Assert-OnlyAllowedPropertyNames -Object $Contract.gate_snapshot -Allowed @('absolute_projection_candidate_id', 'required_gate_ids', 'currently_satisfied_gate_ids', 'object_resource_inventory', 'evidence_adoption_source', 'generation_requires') -Label 'gate_snapshot'
Assert-OnlyAllowedPropertyNames -Object $Contract.gate_snapshot.object_resource_inventory -Allowed @('source_spec_id', 'status', 'write_authorization', 'stable_object_keys', 'approved_templates', 'field_reference', 'model_animation_vfx_sfx_resources') -Label 'object_resource_inventory'
Assert-OnlyAllowedPropertyNames -Object $Contract.gate_snapshot.evidence_adoption_source -Allowed @('artifact', 'spec_id', 'source_content_sha256', 'current_adoption_state', 'currently_satisfied_gate_ids', 'actual_capture_provider', 'actual_y3_project_ref', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload') -Label 'gate_snapshot.evidence_adoption_source'
Assert-OnlyAllowedPropertyNames -Object $Contract.card_schema -Allowed @('logical_asset_contract', 'must_not_be_treated_as_y3_object', 'binding_order', 'required_card_fields', 'future_binding_profile_ref') -Label 'card_schema'
Assert-OnlyAllowedPropertyNames -Object $Contract.hard_boundaries -Allowed @('authority_and_economy', 'current_outputs', 'protected_identity_rules') -Label 'hard_boundaries'
Assert-OnlyAllowedPropertyNames -Object $Contract.hard_boundaries.authority_and_economy -Allowed @('authority_state_input', 'progression_write', 'session_adjudication', 'rotation_calculation', 'qualification_decision', 'cleanup_decision', 'reward', 'receipt', 'economy_input') -Label 'authority_and_economy'
Assert-OnlyAllowedPropertyNames -Object $Contract.hard_boundaries.current_outputs -Allowed @('y3_object_write', 'plugin_script', 'lua_write', 'map_write', 'ui_write', 'asset_write', 'object_config_design') -Label 'current_outputs'
foreach ($Acceptance in @($Contract.acceptance)) {
    Assert-OnlyAllowedPropertyNames -Object $Acceptance -Allowed @('id', 'rule') -Label "acceptance.$($Acceptance.id)"
    Assert-RequiredProperties -Object $Acceptance -Fields @('id', 'rule') -Label "acceptance.$($Acceptance.id)"
    Assert-NonEmptyString -Value $Acceptance.id -Label "acceptance.$($Acceptance.id).id"
    Assert-NonEmptyString -Value $Acceptance.rule -Label "acceptance.$($Acceptance.id).rule"
}

Assert-RequiredProperties -Object $Contract.identity -Fields @('spec_id', 'display_name', 'package_status', 'production_gate', 'runtime_key', 'plugin_generation', 'normalized_design_input', 'generated_plugin') -Label 'identity'
Assert-NonEmptyString -Value $Contract.identity.spec_id -Label 'identity.spec_id'
Assert-NonEmptyString -Value $Contract.identity.display_name -Label 'identity.display_name'
Assert-NonEmptyString -Value $Contract.identity.package_status -Label 'identity.package_status'
Assert-NonEmptyString -Value $Contract.identity.production_gate -Label 'identity.production_gate'
Assert-That -Condition ($Contract.identity.plugin_generation -is [bool]) -Message 'identity.plugin_generation must be boolean'
Assert-RequiredProperties -Object $Contract.scope -Fields @('included', 'excluded') -Label 'scope'
Assert-NonEmptyStringArray -Value $Contract.scope.included -MinimumCount 1 -Label 'scope.included'
Assert-NonEmptyStringArray -Value $Contract.scope.excluded -MinimumCount 1 -Label 'scope.excluded'
Assert-RequiredProperties -Object $Contract.gate_snapshot -Fields @('absolute_projection_candidate_id', 'required_gate_ids', 'currently_satisfied_gate_ids', 'object_resource_inventory', 'evidence_adoption_source', 'generation_requires') -Label 'gate_snapshot'
Assert-NonEmptyString -Value $Contract.gate_snapshot.absolute_projection_candidate_id -Label 'gate_snapshot.absolute_projection_candidate_id'
Assert-NonEmptyStringArray -Value $Contract.gate_snapshot.required_gate_ids -MinimumCount 1 -Label 'gate_snapshot.required_gate_ids'
Assert-That -Condition ($Contract.gate_snapshot.currently_satisfied_gate_ids -is [System.Array]) -Message 'gate_snapshot.currently_satisfied_gate_ids must be an array'
Assert-NonEmptyStringArray -Value $Contract.gate_snapshot.generation_requires -MinimumCount 1 -Label 'gate_snapshot.generation_requires'
Assert-RequiredProperties -Object $Contract.gate_snapshot.object_resource_inventory -Fields @('source_spec_id', 'status', 'write_authorization', 'stable_object_keys', 'approved_templates', 'field_reference', 'model_animation_vfx_sfx_resources') -Label 'object_resource_inventory'
Assert-NonEmptyString -Value $Contract.gate_snapshot.object_resource_inventory.source_spec_id -Label 'object_resource_inventory.source_spec_id'
Assert-NonEmptyString -Value $Contract.gate_snapshot.object_resource_inventory.status -Label 'object_resource_inventory.status'
Assert-That -Condition ($Contract.gate_snapshot.object_resource_inventory.write_authorization -is [bool]) -Message 'object_resource_inventory.write_authorization must be boolean'
Assert-That -Condition ($Contract.gate_snapshot.object_resource_inventory.status -eq 'not_read_from_real_y3_project') -Message 'object_resource_inventory.status must preserve the unread real-project boundary'
Assert-That -Condition ($Contract.gate_snapshot.object_resource_inventory.write_authorization -eq $false) -Message 'object_resource_inventory.write_authorization must remain false'
Assert-RequiredProperties -Object $Contract.gate_snapshot.evidence_adoption_source -Fields @('artifact', 'spec_id', 'source_content_sha256', 'current_adoption_state', 'currently_satisfied_gate_ids', 'actual_capture_provider', 'actual_y3_project_ref', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload') -Label 'gate_snapshot.evidence_adoption_source'
Assert-NonEmptyString -Value $Contract.gate_snapshot.evidence_adoption_source.artifact -Label 'gate_snapshot.evidence_adoption_source.artifact'
Assert-NonEmptyString -Value $Contract.gate_snapshot.evidence_adoption_source.spec_id -Label 'gate_snapshot.evidence_adoption_source.spec_id'
Assert-NonEmptyString -Value $Contract.gate_snapshot.evidence_adoption_source.source_content_sha256 -Label 'gate_snapshot.evidence_adoption_source.source_content_sha256'
Assert-That -Condition ([string]$Contract.gate_snapshot.evidence_adoption_source.source_content_sha256 -match '^[0-9a-f]{64}$') -Message 'gate_snapshot.evidence_adoption_source.source_content_sha256 must be a lowercase SHA-256 digest'
Assert-NonEmptyString -Value $Contract.gate_snapshot.evidence_adoption_source.current_adoption_state -Label 'gate_snapshot.evidence_adoption_source.current_adoption_state'
Assert-That -Condition ($Contract.gate_snapshot.evidence_adoption_source.currently_satisfied_gate_ids -is [System.Array]) -Message 'gate_snapshot.evidence_adoption_source.currently_satisfied_gate_ids must be an array'
Assert-RequiredProperties -Object $Contract.card_schema -Fields @('logical_asset_contract', 'must_not_be_treated_as_y3_object', 'binding_order', 'required_card_fields', 'future_binding_profile_ref') -Label 'card_schema'
Assert-That -Condition ($Contract.card_schema.logical_asset_contract -is [bool]) -Message 'card_schema.logical_asset_contract must be boolean'
Assert-That -Condition ($Contract.card_schema.must_not_be_treated_as_y3_object -is [bool]) -Message 'card_schema.must_not_be_treated_as_y3_object must be boolean'
Assert-That -Condition ($Contract.card_schema.logical_asset_contract -eq $true) -Message 'card_schema.logical_asset_contract must remain true'
Assert-That -Condition ($Contract.card_schema.must_not_be_treated_as_y3_object -eq $true) -Message 'card_schema.must_not_be_treated_as_y3_object must remain true'
Assert-NonEmptyStringArray -Value $Contract.card_schema.binding_order -MinimumCount 1 -Label 'card_schema.binding_order'
Assert-NonEmptyStringArray -Value $Contract.card_schema.required_card_fields -MinimumCount 1 -Label 'card_schema.required_card_fields'
Assert-NonEmptyString -Value $Contract.card_schema.future_binding_profile_ref -Label 'card_schema.future_binding_profile_ref'
Assert-RequiredProperties -Object $Contract.hard_boundaries -Fields @('authority_and_economy', 'current_outputs', 'protected_identity_rules') -Label 'hard_boundaries'
Assert-RequiredProperties -Object $Contract.hard_boundaries.authority_and_economy -Fields @('authority_state_input', 'progression_write', 'session_adjudication', 'rotation_calculation', 'qualification_decision', 'cleanup_decision', 'reward', 'receipt', 'economy_input') -Label 'authority_and_economy'
Assert-NonEmptyString -Value $Contract.hard_boundaries.authority_and_economy.authority_state_input -Label 'authority_and_economy.authority_state_input'
Assert-RequiredProperties -Object $Contract.hard_boundaries.current_outputs -Fields @('y3_object_write', 'plugin_script', 'lua_write', 'map_write', 'ui_write', 'asset_write', 'object_config_design') -Label 'current_outputs'
Assert-NonEmptyStringArray -Value $Contract.hard_boundaries.protected_identity_rules -MinimumCount 1 -Label 'hard_boundaries.protected_identity_rules'

Assert-That -Condition (@($Contract.field_reservation_profiles).Count -eq 1) -Message 'exactly one all-null field reservation profile is allowed'
foreach ($Profile in @($Contract.field_reservation_profiles)) {
    Assert-OnlyAllowedPropertyNames -Object $Profile -Allowed @('spec_id', 'purpose', 'future_object_binding', 'future_resource_binding', 'absolute_projection', 'future_runtime_binding') -Label "field_reservation_profile.$($Profile.spec_id)"
    Assert-RequiredProperties -Object $Profile -Fields @('spec_id', 'purpose', 'future_object_binding', 'future_resource_binding', 'absolute_projection', 'future_runtime_binding') -Label "field_reservation_profile.$($Profile.spec_id)"
    Assert-NonEmptyString -Value $Profile.spec_id -Label "field_reservation_profile.$($Profile.spec_id).spec_id"
    Assert-NonEmptyString -Value $Profile.purpose -Label "field_reservation_profile.$($Profile.spec_id).purpose"
    Assert-OnlyAllowedPropertyNames -Object $Profile.future_object_binding -Allowed @('object_table_type', 'stable_object_key', 'copyFrom', 'source_template_key', 'editor_field_mapping', 'unit_object_id', 'ability_object_ids', 'buff_object_ids', 'projectile_object_ids') -Label "future_object_binding.$($Profile.spec_id)"
    Assert-OnlyAllowedPropertyNames -Object $Profile.future_resource_binding -Allowed @('model_resource_id', 'animation_resource_id', 'vfx_resource_id', 'sound_resource_id', 'material_resource_id', 'icon_resource_id') -Label "future_resource_binding.$($Profile.spec_id)"
    Assert-OnlyAllowedPropertyNames -Object $Profile.absolute_projection -Allowed @('health', 'physical_attack', 'magical_attack', 'physical_defense', 'magical_defense', 'attack_speed', 'attack_range', 'movement_speed', 'damage', 'area', 'cooldown', 'cast_seconds', 'duration_seconds', 'frequency') -Label "absolute_projection.$($Profile.spec_id)"
    Assert-OnlyAllowedPropertyNames -Object $Profile.future_runtime_binding -Allowed @('ai_behavior', 'wave_definition', 'spawn_point', 'collision', 'map_binding', 'lua_module', 'session_command', 'progression_write', 'authority_event', 'rotation_source', 'qualification_source', 'cleanup_command', 'reward', 'receipt', 'economy_input') -Label "future_runtime_binding.$($Profile.spec_id)"
}

$ExpectedSharedSemanticFamilies = [ordered]@{
    'projection_and_area' = 7
    'presentation_state' = 4
    'sound_semantics' = 4
}
Assert-OnlyAllowedPropertyNames -Object $Contract.shared_semantic_families -Allowed @($ExpectedSharedSemanticFamilies.Keys) -Label 'shared_semantic_families'
foreach ($FamilyName in $ExpectedSharedSemanticFamilies.Keys) {
    $FamilyEntries = @($Contract.shared_semantic_families.PSObject.Properties[$FamilyName].Value)
    Assert-That -Condition ($FamilyEntries.Count -eq $ExpectedSharedSemanticFamilies[$FamilyName]) -Message "shared semantic family must preserve its exact entry count: $FamilyName"
    foreach ($Entry in $FamilyEntries) {
        Assert-OnlyAllowedPropertyNames -Object $Entry -Allowed @('spec_id', 'meaning', 'runtime_key') -Label "shared_semantic_families.$FamilyName"
        Assert-NonEmptyString -Value $Entry.spec_id -Label "shared_semantic_families.$FamilyName.spec_id"
        Assert-NonEmptyString -Value $Entry.meaning -Label "shared_semantic_families.$FamilyName.meaning"
        Assert-That -Condition ($null -eq $Entry.runtime_key) -Message "shared_semantic_families.$FamilyName runtime_key must remain null"
    }
}

Assert-That -Condition ($Contract.schema_version -eq 1) -Message 'schema version must be 1'
Assert-That -Condition ($Contract.identity.spec_id -eq 'TT_SPEC_TIANTING_OBJECT_FIELD_RESERVATION') -Message 'field reservation identity must remain stable'
Assert-That -Condition ($Contract.identity.package_status -eq 'offline_field_reservation_only') -Message 'package must remain offline field reservation only'
Assert-That -Condition ($Contract.identity.production_gate -eq 'closed') -Message 'production gate must remain closed'
Assert-That -Condition ($Contract.identity.plugin_generation -eq $false) -Message 'plugin generation must be explicitly disabled'
Assert-NullFields -Object $Contract.identity -Fields @('runtime_key', 'normalized_design_input', 'generated_plugin') -Label 'identity'
Assert-NoNormalizedDesignProperties -Value $Contract -Path 'contract'
Assert-AllRuntimeKeysNull -Value $Contract -Path 'contract'
$ReviewedSemanticSnapshot = [PSCustomObject]@{
    card_schema = $Contract.card_schema
    shared_semantic_families = $Contract.shared_semantic_families
    logical_asset_groups = $Contract.logical_asset_groups
}
Assert-That -Condition ((Get-CanonicalJsonSha256 -Value $ReviewedSemanticSnapshot) -eq '1ef5f046b46c28ed57ea3abab9bb4c155322dff87d55b36ad4f599625dbb9506') -Message 'reviewed logical card semantics must not drift without an explicit test revision'

$ExpectedSourceContracts = [ordered]@{
    '../object-blueprint/tianting-object-art-vfx-blueprint-contract.json' = [PSCustomObject]@{ spec_ids = @('TT_SPEC_TIANTING_OBJECT_ART_VFX_BLUEPRINT'); contract_ids = @(); sha256 = '5444473c68e951832775fdf8ea491e9ead4ae4a55fd4c1cbcb59566e09d20a15' }
    '../enemy-ecology/tianting-enemy-ecology-contract.json' = [PSCustomObject]@{ spec_ids = @('TT_SPEC_TIANTING_ENEMY_ECOLOGY'); contract_ids = @(); sha256 = '925e4ce3392f2f6218b511f260b4b54fa02cf7eb602bc78ec2446e57f3583fc5' }
    '../mainline-boss/tianting-mainline-boss-contract.json' = [PSCustomObject]@{ spec_ids = @('TT_SPEC_TIANTING_MAINLINE_BOSS_DEEPENING'); contract_ids = @(); sha256 = '45ad7962512ce67317a30c952fc03f6899528c725da897d574a5cb96a8af5c78' }
    '../tianting-content-expansion-contract.json' = [PSCustomObject]@{ spec_ids = @('TT_SPEC_MAINLINE_CONTENT_EXPANSION', 'TT_SPEC_SEVEN_STAR_SOLO_SERIES', 'TT_SPEC_TWENTY_EIGHT_MANSIONS_RAID', 'TT_SPEC_MANSION_NIGHTMARE_MODE'); contract_ids = @(); sha256 = '78ac581deca1324a56ae898f9edafe04ec9e8fafbb831dc6e72b288d4d3bc50e' }
    '../combat/tianting-combat-readability-contract.json' = [PSCustomObject]@{ spec_ids = @('TT_SPEC_TIANTING_COMBAT_READABILITY'); contract_ids = @(); sha256 = '8ec1e322659bcb4e3360ecebe426010a84f856ff92a6e10e39d8f9b7530cff94' }
    '../../../../implementation/combat-calibration/contract/cross-profession-combat-calibration-contract.json' = [PSCustomObject]@{ spec_ids = @(); contract_ids = @('CAL_SPEC_CROSS_PROFESSION_ABSOLUTE_COMBAT_V1'); sha256 = '72405ee76ed8841ff067eb3bb691db6dd29702d1635dc8103adc27d6a3f6f2a8' }
    '../../../../implementation/combat-calibration/evidence-adoption/p0-evidence-collection-and-adoption-contract.json' = [PSCustomObject]@{ spec_ids = @('CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1'); contract_ids = @(); sha256 = '2d3cbffd7233e75ef554e8febd9f152ba81153419fd4edcb5ddc5ed2f921dfec' }
    '../../../../implementation/tianting-surface-construction-manifest/surface-construction-manifest.json' = [PSCustomObject]@{ spec_ids = @('TT_SPEC_SURFACE_CONSTRUCTION_DISCOVERY_MANIFEST'); contract_ids = @(); sha256 = '9c37da713e0a5487c06ea9b0b1378b03b95de17aad3b547226aa719cd61d0e9e' }
}
$ActualSourceArtifacts = @($Contract.source_contracts | ForEach-Object { [string]$_.artifact })
Assert-That -Condition (($ActualSourceArtifacts -join '|') -eq (@($ExpectedSourceContracts.Keys) -join '|')) -Message 'source_contracts must preserve the canonical source manifest and order'

$DeclaredSources = @{}
$WorkspaceRootWithSeparator = $WorkspaceRoot.TrimEnd('\') + '\'
foreach ($SourceDeclaration in @($Contract.source_contracts)) {
    Assert-OnlyAllowedPropertyNames -Object $SourceDeclaration -Allowed @('artifact', 'spec_id', 'source_spec_ids', 'contract_id', 'role', 'runtime_key', 'source_content_sha256') -Label 'source_contracts declaration'
    Assert-RequiredProperties -Object $SourceDeclaration -Fields @('artifact', 'role', 'runtime_key', 'source_content_sha256') -Label 'source_contracts declaration'
    $SourceArtifact = [string]$SourceDeclaration.artifact
    Assert-NonEmptyString -Value $SourceDeclaration.artifact -Label 'source_contracts.artifact'
    Assert-NonEmptyString -Value $SourceDeclaration.role -Label "source_contracts.$SourceArtifact.role"
    Assert-NonEmptyString -Value $SourceDeclaration.source_content_sha256 -Label "source_contracts.$SourceArtifact.source_content_sha256"
    Assert-That -Condition ([string]$SourceDeclaration.source_content_sha256 -match '^[0-9a-f]{64}$') -Message "source_contracts.$SourceArtifact.source_content_sha256 must be a lowercase SHA-256 digest"
    Assert-That -Condition ($ExpectedSourceContracts.Contains($SourceArtifact)) -Message "source artifact must be part of the canonical manifest: $SourceArtifact"
    Assert-That -Condition (-not $DeclaredSources.ContainsKey($SourceArtifact)) -Message "source artifact must be declared once: $SourceArtifact"

    $DeclaredSourceSpecIds = [System.Collections.Generic.List[string]]::new()
    if ($SourceDeclaration.PSObject.Properties.Name -contains 'spec_id') {
        Assert-NonEmptyString -Value $SourceDeclaration.spec_id -Label "source_contracts.$SourceArtifact.spec_id"
        $DeclaredSourceSpecIds.Add([string]$SourceDeclaration.spec_id) | Out-Null
    }
    if ($SourceDeclaration.PSObject.Properties.Name -contains 'source_spec_ids') {
        Assert-NonEmptyStringArray -Value $SourceDeclaration.source_spec_ids -MinimumCount 1 -Label "source_contracts.$SourceArtifact.source_spec_ids"
        foreach ($SourceSpecId in @($SourceDeclaration.source_spec_ids)) {
            $DeclaredSourceSpecIds.Add([string]$SourceSpecId) | Out-Null
        }
    }
    $DeclaredSourceContractIds = [System.Collections.Generic.List[string]]::new()
    if ($SourceDeclaration.PSObject.Properties.Name -contains 'contract_id') {
        Assert-NonEmptyString -Value $SourceDeclaration.contract_id -Label "source_contracts.$SourceArtifact.contract_id"
        $DeclaredSourceContractIds.Add([string]$SourceDeclaration.contract_id) | Out-Null
    }
    $ExpectedSourceIdentity = $ExpectedSourceContracts[$SourceArtifact]
    Assert-That -Condition ((@($DeclaredSourceSpecIds) -join '|') -eq (@($ExpectedSourceIdentity.spec_ids) -join '|')) -Message "source declaration must preserve canonical spec identities: $SourceArtifact"
    Assert-That -Condition ((@($DeclaredSourceContractIds) -join '|') -eq (@($ExpectedSourceIdentity.contract_ids) -join '|')) -Message "source declaration must preserve canonical contract identities: $SourceArtifact"
    Assert-That -Condition ([string]$SourceDeclaration.source_content_sha256 -eq $ExpectedSourceIdentity.sha256) -Message "source declaration must preserve its reviewed source content digest: $SourceArtifact"

    $SourcePath = Join-Path $PackageRoot $SourceArtifact
    Assert-That -Condition (Test-Path -LiteralPath $SourcePath -PathType Leaf) -Message "declared source artifact must exist: $SourceArtifact"
    $ResolvedSourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    Assert-That -Condition (($ResolvedSourcePath -eq $WorkspaceRoot) -or $ResolvedSourcePath.StartsWith($WorkspaceRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) -Message "declared source artifact must stay inside the workspace: $SourceArtifact"
    $ActualSourceDigest = (Get-FileHash -LiteralPath $ResolvedSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-That -Condition ($ActualSourceDigest -eq [string]$SourceDeclaration.source_content_sha256) -Message "declared source content digest must match its artifact: $SourceArtifact"

    try {
        $SourceContract = Get-Content -LiteralPath $ResolvedSourcePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "declared source artifact must be valid UTF-8 JSON: $SourceArtifact ($($_.Exception.Message))"
    }

    $ParsedSpecIds = @(Get-NamedStringPropertyValues -Value $SourceContract -PropertyName 'spec_id')
    $ParsedContractIds = @(Get-NamedStringPropertyValues -Value $SourceContract -PropertyName 'contract_id')
    Assert-That -Condition ($ParsedSpecIds.Count -gt 0 -or $ParsedContractIds.Count -gt 0) -Message "declared source artifact must expose a stable contract identity: $SourceArtifact"

    if ($SourceDeclaration.PSObject.Properties.Name -contains 'spec_id') {
        Assert-That -Condition ($ParsedSpecIds -contains [string]$SourceDeclaration.spec_id) -Message "declared source spec_id must resolve from its artifact: $SourceArtifact"
    }
    if ($SourceDeclaration.PSObject.Properties.Name -contains 'source_spec_ids') {
        $DeclaredSpecIds = @($SourceDeclaration.source_spec_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
        Assert-That -Condition ($DeclaredSpecIds.Count -gt 0) -Message "declared source_spec_ids must not be empty: $SourceArtifact"
        foreach ($DeclaredSpecId in $DeclaredSpecIds) {
            Assert-That -Condition ($ParsedSpecIds -contains $DeclaredSpecId) -Message "declared source_spec_id must resolve from its artifact: $DeclaredSpecId"
        }
    }
    if ($SourceDeclaration.PSObject.Properties.Name -contains 'contract_id') {
        Assert-That -Condition ($ParsedContractIds -contains [string]$SourceDeclaration.contract_id) -Message "declared contract_id must resolve from its artifact: $SourceArtifact"
    }

    $DeclaredSources[$SourceArtifact] = [PSCustomObject]@{
        path = $ResolvedSourcePath
        spec_ids = $ParsedSpecIds
        contract_ids = $ParsedContractIds
        document = $SourceContract
    }
}

$ExpectedP0GateIds = @(
    'P0-GATE-01-all-12-fixed-builds-declared-and-replayed',
    'P0-GATE-02-general-physical-magical-defense-formulas-adopted',
    'P0-GATE-03-hit-crit-control-formulas-adopted',
    'P0-GATE-04-engine-action-frame-and-speed-readback',
    'P0-GATE-05-terrain-collision-and-camera-fixture',
    'P0-GATE-06-authoritative-one-to-four-member-replays',
    'P0-GATE-07-stable-object-keys-and-template-readback'
)
$ExpectedGenerationRequires = @(
    'all P0 required_gate_ids adopted',
    'real Y3 object and resource inventory read',
    'stable object keys and source templates approved',
    'explicit real-project write authorization'
)
Assert-That -Condition ((@($Contract.gate_snapshot.required_gate_ids) -join '|') -eq ($ExpectedP0GateIds -join '|')) -Message 'reservation must preserve the exact canonical P0 gate sequence'
Assert-That -Condition ((@($Contract.gate_snapshot.generation_requires) -join '|') -eq ($ExpectedGenerationRequires -join '|')) -Message 'reservation must preserve the exact generation prerequisite sequence'
$CalibrationSourceArtifact = '../../../../implementation/combat-calibration/contract/cross-profession-combat-calibration-contract.json'
$CalibrationSource = $DeclaredSources[$CalibrationSourceArtifact].document
Assert-That -Condition ((@($CalibrationSource.absolute_projection_gate.required_gate_ids) -join '|') -eq ($ExpectedP0GateIds -join '|')) -Message 'calibration source must preserve the exact canonical P0 gate sequence'
Assert-That -Condition ((@($Contract.gate_snapshot.required_gate_ids) -join '|') -eq (@($CalibrationSource.absolute_projection_gate.required_gate_ids) -join '|')) -Message 'reservation P0 gate snapshot must exactly match calibration source'
Assert-That -Condition ($CalibrationSource.absolute_projection_gate.candidate.candidate_id -eq $Contract.gate_snapshot.absolute_projection_candidate_id) -Message 'reservation absolute projection candidate must exactly match calibration source'
Assert-That -Condition (@($Contract.gate_snapshot.currently_satisfied_gate_ids).Count -eq 0) -Message 'no P0 gate may be represented as satisfied'
Assert-That -Condition ((@($Contract.gate_snapshot.currently_satisfied_gate_ids) -join '|') -eq (@($CalibrationSource.absolute_projection_gate.current_satisfied_gate_ids) -join '|')) -Message 'reservation satisfied P0 gate snapshot must exactly match calibration source'
Assert-That -Condition ($Contract.gate_snapshot.absolute_projection_candidate_id -eq 'TT_CAL_ABSOLUTE_OBJECT_FIELDS_V1') -Message 'reservation must point to the one absolute projection candidate'
Assert-That -Condition ($Contract.gate_snapshot.object_resource_inventory.source_spec_id -eq 'TT_DISCOVERY_OBJECT_AND_RESOURCE_INVENTORY') -Message 'reservation must require the object and resource inventory'
Assert-That -Condition ($Contract.gate_snapshot.object_resource_inventory.write_authorization -eq $false) -Message 'inventory must not authorize writes'
Assert-NullFields -Object $Contract.gate_snapshot.object_resource_inventory -Fields @('stable_object_keys', 'approved_templates', 'field_reference', 'model_animation_vfx_sfx_resources') -Label 'object_resource_inventory'

$EvidenceAdoptionSourceArtifact = '../../../../implementation/combat-calibration/evidence-adoption/p0-evidence-collection-and-adoption-contract.json'
$EvidenceAdoptionSnapshot = $Contract.gate_snapshot.evidence_adoption_source
$EvidenceAdoptionSource = $DeclaredSources[$EvidenceAdoptionSourceArtifact].document
Assert-That -Condition ($EvidenceAdoptionSnapshot.artifact -eq $EvidenceAdoptionSourceArtifact) -Message 'reservation must identify the direct P0 evidence-adoption artifact'
Assert-That -Condition ($EvidenceAdoptionSnapshot.spec_id -eq 'CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1') -Message 'reservation must identify the direct P0 evidence-adoption spec'
Assert-That -Condition ($EvidenceAdoptionSnapshot.source_content_sha256 -eq '2d3cbffd7233e75ef554e8febd9f152ba81153419fd4edcb5ddc5ed2f921dfec') -Message 'reservation must preserve the reviewed P0 evidence-adoption digest'
Assert-That -Condition ($EvidenceAdoptionSnapshot.source_content_sha256 -eq (Get-FileHash -LiteralPath $DeclaredSources[$EvidenceAdoptionSourceArtifact].path -Algorithm SHA256).Hash.ToLowerInvariant()) -Message 'reservation P0 evidence-adoption snapshot digest must match its direct artifact'
Assert-That -Condition ($EvidenceAdoptionSource.identity.spec_id -eq $EvidenceAdoptionSnapshot.spec_id) -Message 'reservation evidence-adoption spec_id must resolve from its direct artifact'
Assert-That -Condition ($EvidenceAdoptionSource.identity.production_gate -eq 'closed') -Message 'direct P0 evidence-adoption source production gate must remain closed'
Assert-That -Condition ((@($EvidenceAdoptionSource.source_calibration_contract.required_gate_ids) -join '|') -eq ($ExpectedP0GateIds -join '|')) -Message 'evidence-adoption source must preserve the exact canonical P0 gate sequence'
Assert-That -Condition (@($EvidenceAdoptionSource.gate_collection_plans).Count -eq $ExpectedP0GateIds.Count) -Message 'evidence-adoption source must retain one blocked collection plan for every P0 gate'
Assert-That -Condition ($EvidenceAdoptionSnapshot.current_adoption_state -eq 'closed') -Message 'reservation evidence-adoption snapshot must remain closed'
Assert-That -Condition ($EvidenceAdoptionSnapshot.current_adoption_state -eq $EvidenceAdoptionSource.adoption_controls.current_adoption_state) -Message 'reservation evidence-adoption state must match its direct artifact'
Assert-That -Condition (@($EvidenceAdoptionSnapshot.currently_satisfied_gate_ids).Count -eq 0) -Message 'reservation evidence-adoption snapshot must remain at zero of seven adopted gates'
Assert-That -Condition ((@($EvidenceAdoptionSnapshot.currently_satisfied_gate_ids) -join '|') -eq (@($EvidenceAdoptionSource.adoption_controls.current_satisfied_gate_ids) -join '|')) -Message 'reservation evidence-adoption adopted-gate snapshot must match its direct artifact'
Assert-That -Condition (@($EvidenceAdoptionSource.gate_collection_plans | Where-Object { $_.collection_status -ne 'blocked_pending_external_evidence' -or $_.adoption_status -ne 'blocked_pending_external_evidence' }).Count -eq 0) -Message 'all P0 evidence collection plans must remain blocked pending external evidence'
Assert-That -Condition (@($EvidenceAdoptionSource.gate_collection_plans | Where-Object { $null -ne $_.accepted_evidence_refs }).Count -eq 0) -Message 'all P0 evidence collection plans must retain null accepted evidence references'
Assert-NullFields -Object $EvidenceAdoptionSnapshot -Fields @('actual_capture_provider', 'actual_y3_project_ref', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload') -Label 'evidence_adoption_source'
Assert-NullFields -Object $EvidenceAdoptionSource.identity -Fields @('actual_capture_provider', 'actual_y3_project_ref', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload') -Label 'evidence_adoption_source.identity'

$Binding = @($Contract.field_reservation_profiles | Where-Object { $_.spec_id -eq 'TT_SPEC_OBJRES_ALL_NULL_BINDINGS' })
Assert-That -Condition ($Binding.Count -eq 1) -Message 'exactly one all-null binding profile is required'
$Binding = $Binding[0]
Assert-NullFields -Object $Binding.future_object_binding -Fields @('object_table_type', 'stable_object_key', 'copyFrom', 'source_template_key', 'editor_field_mapping', 'unit_object_id', 'ability_object_ids', 'buff_object_ids', 'projectile_object_ids') -Label 'future_object_binding'
Assert-NullFields -Object $Binding.future_resource_binding -Fields @('model_resource_id', 'animation_resource_id', 'vfx_resource_id', 'sound_resource_id', 'material_resource_id', 'icon_resource_id') -Label 'future_resource_binding'
Assert-NullFields -Object $Binding.absolute_projection -Fields @('health', 'physical_attack', 'magical_attack', 'physical_defense', 'magical_defense', 'attack_speed', 'attack_range', 'movement_speed', 'damage', 'area', 'cooldown', 'cast_seconds', 'duration_seconds', 'frequency') -Label 'absolute_projection'
Assert-NullFields -Object $Binding.future_runtime_binding -Fields @('ai_behavior', 'wave_definition', 'spawn_point', 'collision', 'map_binding', 'lua_module', 'session_command', 'progression_write', 'authority_event', 'rotation_source', 'qualification_source', 'cleanup_command', 'reward', 'receipt', 'economy_input') -Label 'future_runtime_binding'

$ExpectedGroups = [ordered]@{
    'TT_SPEC_OBJRES_GROUP_ENEMY_ECOLOGY' = @(
        'TT_SPEC_ENEMY_CONTROLLED_CELESTIAL_SOLDIER', 'TT_SPEC_ELITE_FOUR_GATE_GUARD_MECHANISM', 'TT_SPEC_ELITE_UNCONTROLLED_CLOUD_BEAST', 'TT_SPEC_ELITE_GENERIC_STAR_OBSERVER', 'TT_SPEC_ENTITY_PATROL_SIGNAL_ECHO', 'TT_SPEC_ENTITY_BROKEN_RAINBOW_FORMATION_EYE', 'TT_SPEC_ENTITY_STAR_CALENDAR_RIFT', 'TT_SPEC_ENTITY_FRACTURED_LAW_COMMAND_NODE', 'TT_SPEC_ENTITY_SEVEN_STAR_RULE_ECHO', 'TT_SPEC_ENTITY_MANSION_ORIENTATION_ECHO', 'TT_SPEC_ENTITY_NIGHTMARE_RESONANCE_SUPPORT'
    )
    'TT_SPEC_OBJRES_GROUP_MAINLINE' = @(
        'TT_SPEC_MAINLINE_BOSS_SPLIT_SOUTH_GATE', 'TT_SPEC_MAINLINE_BOSS_BROKEN_RAINBOW_FORMATION', 'TT_SPEC_MAINLINE_BOSS_FOUR_GATE_IMBALANCE', 'TT_SPEC_MAINLINE_BOSS_CELESTIAL_OBSERVATORY', 'TT_SPEC_MAINLINE_BOSS_LINGXIAO_OUTER_COURT'
    )
    'TT_SPEC_OBJRES_GROUP_SEVEN_STAR' = @(
        'TT_SPEC_SOLO_TIANSHU', 'TT_SPEC_SOLO_TIANXUAN', 'TT_SPEC_SOLO_TIANJI', 'TT_SPEC_SOLO_TIANQUAN', 'TT_SPEC_SOLO_YUHENG', 'TT_SPEC_SOLO_KAIYANG', 'TT_SPEC_SOLO_YAOGUANG'
    )
    'TT_SPEC_OBJRES_GROUP_TWENTY_EIGHT_MANSIONS' = @(
        'TT_SPEC_MANSION_JIA_MU_JIAO', 'TT_SPEC_MANSION_KANG_JIN_LONG', 'TT_SPEC_MANSION_DI_TU_HE', 'TT_SPEC_MANSION_FANG_RI_TU', 'TT_SPEC_MANSION_XIN_YUE_HU', 'TT_SPEC_MANSION_WEI_HUO_HU', 'TT_SPEC_MANSION_JI_SHUI_BAO',
        'TT_SPEC_MANSION_JING_MU_AN', 'TT_SPEC_MANSION_GUI_JIN_YANG', 'TT_SPEC_MANSION_LIU_TU_ZHANG', 'TT_SPEC_MANSION_XING_RI_MA', 'TT_SPEC_MANSION_ZHANG_YUE_LU', 'TT_SPEC_MANSION_YI_HUO_SHE', 'TT_SPEC_MANSION_ZHEN_SHUI_YIN',
        'TT_SPEC_MANSION_KUI_MU_LANG', 'TT_SPEC_MANSION_LOU_JIN_GOU', 'TT_SPEC_MANSION_WEI_TU_ZHI', 'TT_SPEC_MANSION_MAO_RI_JI', 'TT_SPEC_MANSION_BI_YUE_WU', 'TT_SPEC_MANSION_ZI_HUO_HOU', 'TT_SPEC_MANSION_SHEN_SHUI_YUAN',
        'TT_SPEC_MANSION_DOU_MU_XIE', 'TT_SPEC_MANSION_NIU_JIN_NIU', 'TT_SPEC_MANSION_NV_TU_FU', 'TT_SPEC_MANSION_XU_RI_SHU', 'TT_SPEC_MANSION_WEI_YUE_YAN', 'TT_SPEC_MANSION_SHI_HUO_ZHU', 'TT_SPEC_MANSION_BI_SHUI_YU'
    )
    'TT_SPEC_OBJRES_GROUP_FOUR_SACRED' = @('TT_SPEC_RAID_AZURE_DRAGON', 'TT_SPEC_RAID_VERMILION_BIRD', 'TT_SPEC_RAID_WHITE_TIGER', 'TT_SPEC_RAID_BLACK_TORTOISE')
}
$ExpectedGroupSources = [ordered]@{
    'TT_SPEC_OBJRES_GROUP_ENEMY_ECOLOGY' = [PSCustomObject]@{ artifact = '../enemy-ecology/tianting-enemy-ecology-contract.json'; source_spec_id = 'TT_SPEC_TIANTING_ENEMY_ECOLOGY'; batch_status = 'future_mainline_p0_candidate_only' }
    'TT_SPEC_OBJRES_GROUP_MAINLINE' = [PSCustomObject]@{ artifact = '../mainline-boss/tianting-mainline-boss-contract.json'; source_spec_id = 'TT_SPEC_TIANTING_MAINLINE_BOSS_DEEPENING'; batch_status = 'future_mainline_p0_candidate_only' }
    'TT_SPEC_OBJRES_GROUP_SEVEN_STAR' = [PSCustomObject]@{ artifact = '../tianting-content-expansion-contract.json'; source_spec_id = 'TT_SPEC_SEVEN_STAR_SOLO_SERIES'; batch_status = 'future_p2_only' }
    'TT_SPEC_OBJRES_GROUP_TWENTY_EIGHT_MANSIONS' = [PSCustomObject]@{ artifact = '../tianting-content-expansion-contract.json'; source_spec_id = 'TT_SPEC_TWENTY_EIGHT_MANSIONS_RAID'; batch_status = 'future_p3_only' }
    'TT_SPEC_OBJRES_GROUP_FOUR_SACRED' = [PSCustomObject]@{ artifact = '../tianting-content-expansion-contract.json'; source_spec_id = 'TT_SPEC_MANSION_NIGHTMARE_MODE'; batch_status = 'future_p3_only' }
}

Assert-That -Condition (@($Contract.logical_asset_groups).Count -eq $ExpectedGroups.Count) -Message 'exactly five logical source groups are required'
$AllowedGroupFields = @('group_id', 'source_spec_id', 'source_artifact', 'batch_status', 'cards')
$AllowedCardFields = @('reservation_id', 'source_selector', 'display_name', 'role_class', 'encounter_scope', 'semantic_skill_slots', 'p0_spatial_signals', 'independent_channel', 'counterplay_result', 'readability_adaptation', 'alias_policy', 'future_binding_profile_ref', 'runtime_key')
$AllowedAliasPolicyFields = @('canonical_full_name', 'aliases')
$AllReservationIds = [System.Collections.Generic.List[string]]::new()
$AllSourceSelectors = [System.Collections.Generic.List[string]]::new()
foreach ($GroupId in $ExpectedGroups.Keys) {
    $Matches = @($Contract.logical_asset_groups | Where-Object { $_.group_id -eq $GroupId })
    Assert-That -Condition ($Matches.Count -eq 1) -Message "one logical group is required: $GroupId"
    $Group = $Matches[0]
    Assert-OnlyAllowedPropertyNames -Object $Group -Allowed $AllowedGroupFields -Label "logical_group.$GroupId"
    $GroupSourceArtifact = [string]$Group.source_artifact
    $ExpectedGroupSource = $ExpectedGroupSources[$GroupId]
    Assert-NonEmptyString -Value $Group.group_id -Label "logical_group.$GroupId.group_id"
    Assert-NonEmptyString -Value $Group.source_spec_id -Label "logical_group.$GroupId.source_spec_id"
    Assert-NonEmptyString -Value $Group.source_artifact -Label "logical_group.$GroupId.source_artifact"
    Assert-NonEmptyString -Value $Group.batch_status -Label "logical_group.$GroupId.batch_status"
    Assert-That -Condition ($GroupSourceArtifact -eq $ExpectedGroupSource.artifact) -Message "$GroupId must retain its canonical source artifact"
    Assert-That -Condition ([string]$Group.source_spec_id -eq $ExpectedGroupSource.source_spec_id) -Message "$GroupId must retain its canonical source spec_id"
    Assert-That -Condition ([string]$Group.batch_status -eq $ExpectedGroupSource.batch_status) -Message "$GroupId must retain its canonical deferred batch status"
    Assert-That -Condition ($DeclaredSources.ContainsKey($GroupSourceArtifact)) -Message "$GroupId source artifact must be declared by source_contracts: $GroupSourceArtifact"
    $GroupSource = $DeclaredSources[$GroupSourceArtifact]
    Assert-That -Condition (@($GroupSource.spec_ids) -contains [string]$Group.source_spec_id) -Message "$GroupId source_spec_id must resolve from its declared source artifact"
    $ActualSelectors = @($Group.cards | ForEach-Object { [string]$_.source_selector })
    Assert-That -Condition (($ActualSelectors -join '|') -eq ($ExpectedGroups[$GroupId] -join '|')) -Message "$GroupId must preserve its exact source ordering and coverage"

    foreach ($Card in @($Group.cards)) {
        Assert-OnlyAllowedPropertyNames -Object $Card -Allowed $AllowedCardFields -Label "logical_card.$($Card.reservation_id)"
        Assert-That -Condition (@($GroupSource.spec_ids) -contains [string]$Card.source_selector) -Message "$($Card.reservation_id) source_selector must resolve from $GroupSourceArtifact"
        $AllReservationIds.Add([string]$Card.reservation_id) | Out-Null
        $AllSourceSelectors.Add([string]$Card.source_selector) | Out-Null
        foreach ($Field in @('reservation_id', 'source_selector', 'display_name', 'role_class', 'encounter_scope', 'independent_channel', 'counterplay_result', 'readability_adaptation', 'future_binding_profile_ref')) {
            Assert-NonEmptyString -Value $Card.$Field -Label "$($Card.reservation_id).$Field"
        }
        Assert-NonEmptyStringArray -Value $Card.semantic_skill_slots -MinimumCount 3 -Label "$($Card.reservation_id).semantic_skill_slots"
        Assert-That -Condition (@($Card.semantic_skill_slots).Count -eq 3) -Message "$($Card.reservation_id) must retain exactly three semantic skill slots"
        Assert-NonEmptyStringArray -Value $Card.p0_spatial_signals -MinimumCount 1 -Label "$($Card.reservation_id).p0_spatial_signals"
        Assert-That -Condition ($Card.future_binding_profile_ref -eq 'TT_SPEC_OBJRES_ALL_NULL_BINDINGS') -Message "$($Card.reservation_id) must use all-null field reservation profile"
        Assert-That -Condition ($null -eq $Card.runtime_key) -Message "$($Card.reservation_id) must not bind a runtime key"
        if ($null -ne $Card.alias_policy) {
            Assert-OnlyAllowedPropertyNames -Object $Card.alias_policy -Allowed $AllowedAliasPolicyFields -Label "alias_policy.$($Card.reservation_id)"
            Assert-NonEmptyString -Value $Card.alias_policy.canonical_full_name -Label "alias_policy.$($Card.reservation_id).canonical_full_name"
            Assert-NonEmptyStringArray -Value $Card.alias_policy.aliases -MinimumCount 1 -Label "alias_policy.$($Card.reservation_id).aliases"
        }
    }
}

$MutatedCard = $Contract.logical_asset_groups[0].cards[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$MutatedCard | Add-Member -NotePropertyName 'stable_object_key' -NotePropertyValue 134200001
Assert-That -Condition (-not (Test-OnlyAllowedPropertyNames -Object $MutatedCard -Allowed $AllowedCardFields)) -Message 'card property allow-list must reject a direct stable object key mutation'

Assert-That -Condition ($AllReservationIds.Count -eq 55) -Message 'the five logical groups must cover exactly 55 source identities'
Assert-That -Condition ((@($AllReservationIds | Sort-Object -Unique).Count) -eq $AllReservationIds.Count) -Message 'logical reservation identities must be unique'
Assert-That -Condition ((@($AllSourceSelectors | Sort-Object -Unique).Count) -eq $AllSourceSelectors.Count) -Message 'source identities must not duplicate across cards'

$WeiTuZhi = @($Contract.logical_asset_groups | ForEach-Object { $_.cards } | Where-Object { $_.source_selector -eq 'TT_SPEC_MANSION_WEI_TU_ZHI' })
Assert-That -Condition ($WeiTuZhi.Count -eq 1) -Message 'canonical officer alias record must occur exactly once'
Assert-That -Condition (-not [string]::IsNullOrWhiteSpace([string]$WeiTuZhi[0].alias_policy.canonical_full_name)) -Message 'canonical officer alias policy must retain a full name'
Assert-That -Condition (@($WeiTuZhi[0].alias_policy.aliases).Count -eq 1) -Message 'canonical officer alias policy must not create a duplicate officer'

Assert-NullFields -Object $Contract.hard_boundaries.authority_and_economy -Fields @('progression_write', 'session_adjudication', 'rotation_calculation', 'qualification_decision', 'cleanup_decision', 'reward', 'receipt', 'economy_input') -Label 'authority_and_economy'
Assert-NullFields -Object $Contract.hard_boundaries.current_outputs -Fields @('y3_object_write', 'plugin_script', 'lua_write', 'map_write', 'ui_write', 'asset_write', 'object_config_design') -Label 'current_outputs'

Assert-That -Condition ($Markdown -match 'production_gate = closed') -Message 'markdown must state closed production gate'
Assert-That -Condition ($Markdown -match 'null/deferred') -Message 'markdown must state deferred field bindings'
Assert-That -Condition ($Markdown -match 'P0') -Message 'markdown must state P0 calibration gate'
Assert-That -Condition ($Markdown -match 'copyFrom') -Message 'markdown must document template deferral'
Assert-That -Condition ($Markdown -match 'L3') -Message 'markdown must document readable counter-results'
Assert-That -Condition ($Readme -match 'y3-object-config') -Message 'README must state the intended later tool handoff'
Assert-That -Condition ($Readme -match 'assets') -Message 'README must state it is not a normalized design input'

$ForbiddenRuntimeArtifacts = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object { $_.Extension -in @('.lua', '.y3', '.upui', '.js') }
Assert-That -Condition (@($ForbiddenRuntimeArtifacts).Count -eq 0) -Message 'package must not contain runtime map, Lua, UI or plugin artifacts'

Write-Output "PASS: $script:AssertionCount assertions passed for the object field reservation package. contract_sha256=$ContractSnapshotSha256"
