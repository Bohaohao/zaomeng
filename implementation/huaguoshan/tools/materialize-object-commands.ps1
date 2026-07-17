param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Runtime.Serialization

function Get-JsonReaderMemberName {
    param([System.Xml.XmlReader]$Reader)
    $name = [string]$Reader.LocalName
    if ($name -cne 'item' -or -not $Reader.HasAttributes) { return $name }
    for ($index = 0; $index -lt $Reader.AttributeCount; $index++) {
        [void]$Reader.MoveToAttribute($index)
        if ($Reader.Name -ceq 'item') {
            $name = [string]$Reader.Value
            break
        }
    }
    [void]$Reader.MoveToElement()
    return $name
}

function Get-JsonMemberPath {
    param([string]$ParentPath, [string]$Name)
    if ($Name -cmatch '^[A-Za-z_][A-Za-z0-9_]*$') { return "$ParentPath.$Name" }
    $escaped = $Name.Replace('\', '\\').Replace("'", "\'")
    return "$ParentPath['$escaped']"
}

function Assert-NoDuplicateJsonProperties {
    param([string]$JsonText, [string]$SourceLabel)
    $reader = $null
    $duplicatePrefix = "${SourceLabel}: duplicate JSON property"
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($JsonText)
        $reader = [Runtime.Serialization.Json.JsonReaderWriterFactory]::CreateJsonReader(
            $bytes,
            [Xml.XmlDictionaryReaderQuotas]::Max
        )
        $containers = [System.Collections.Generic.Stack[object]]::new()
        while ($reader.Read()) {
            if ($reader.NodeType -eq [Xml.XmlNodeType]::Element) {
                $valuePath = '$'
                if ($containers.Count -gt 0) {
                    $parent = $containers.Peek()
                    if ($parent.Kind -ceq 'object') {
                        $memberName = Get-JsonReaderMemberName $reader
                        if (-not $parent.Names.Add($memberName)) {
                            throw "${SourceLabel}: duplicate JSON property `"$memberName`" at $($parent.Path)"
                        }
                        $valuePath = Get-JsonMemberPath $parent.Path $memberName
                    }
                    else {
                        $valuePath = "$($parent.Path)[$($parent.NextIndex)]"
                        $parent.NextIndex = [int]$parent.NextIndex + 1
                    }
                }

                $kind = [string]$reader.GetAttribute('type')
                if ($kind -cin @('object', 'array')) {
                    $memberNames = $null
                    if ($kind -ceq 'object') {
                        $memberNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    }
                    $containers.Push([pscustomobject]@{
                        Depth = [int]$reader.Depth
                        Kind = $kind
                        Path = $valuePath
                        Names = $memberNames
                        NextIndex = 0
                    })
                }
            }
            elseif ($reader.NodeType -eq [Xml.XmlNodeType]::EndElement -and
                $containers.Count -gt 0 -and $containers.Peek().Depth -eq $reader.Depth) {
                [void]$containers.Pop()
            }
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($message.StartsWith($duplicatePrefix, [StringComparison]::Ordinal)) { throw $message }
        throw "${SourceLabel}: invalid JSON: $message"
    }
    finally {
        if ($null -ne $reader) { $reader.Close() }
    }
}

function ConvertFrom-StrictJson {
    param([string]$JsonText, [string]$SourceLabel)
    Assert-NoDuplicateJsonProperties $JsonText $SourceLabel
    try { return ConvertFrom-Json -InputObject $JsonText }
    catch { throw "${SourceLabel}: JSON conversion failed: $($_.Exception.Message)" }
}

function Read-StrictJsonFile {
    param([string]$Path, [string]$SourceLabel)
    try { $jsonText = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 }
    catch { throw "${SourceLabel}: cannot read JSON input: $($_.Exception.Message)" }
    return ConvertFrom-StrictJson $jsonText $SourceLabel
}

function Quote-PowerShell {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "''" }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function Format-Scalar {
    param([object]$Value)
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) { return Quote-PowerShell $Value }
    return [string]$Value
}

function Get-ExactJsonProperty {
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]::Equals($property.Name, $Name, [StringComparison]::Ordinal)) { return $property }
    }
    return $null
}

function Merge-Fields {
    param($Defaults, $Overrides)
    $result = @{}
    if ($null -ne $Defaults) {
        foreach ($property in $Defaults.PSObject.Properties) { $result[$property.Name] = $property.Value }
    }
    if ($null -ne $Overrides) {
        foreach ($property in $Overrides.PSObject.Properties) { $result[$property.Name] = $property.Value }
    }
    return [pscustomobject]$result
}

function Resolve-Record {
    param($Defaults, $Record)
    $result = @{}
    if ($null -ne $Defaults) {
        foreach ($property in $Defaults.PSObject.Properties) {
            if ($property.Name -notin @('object_fields', 'unresolved_fields')) { $result[$property.Name] = $property.Value }
        }
    }
    foreach ($property in $Record.PSObject.Properties) {
        if ($property.Name -notin @('object_fields', 'unresolved_fields')) { $result[$property.Name] = $property.Value }
    }
    $result['object_fields'] = Merge-Fields $Defaults.object_fields $Record.object_fields
    $result['unresolved_fields'] = @($Defaults.unresolved_fields) + @($Record.unresolved_fields) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
    return [pscustomobject]$result
}

function Add-FieldTokens {
    param([System.Collections.Generic.List[string]]$Tokens, $Fields, [string[]]$AllowedFields, [string[]]$ArrayFields)
    foreach ($name in $AllowedFields) {
        $property = Get-ExactJsonProperty $Fields $name
        if ($null -eq $property -or $null -eq $property.Value) { continue }
        $Tokens.Add('-' + $name)
        if ($name -in $ArrayFields) { $Tokens.Add((Quote-PowerShell (@($property.Value) -join ','))) }
        else { $Tokens.Add((Format-Scalar $property.Value)) }
    }
}

function Add-Command {
    param([System.Collections.Generic.List[string]]$Lines, [System.Collections.Generic.List[string]]$Tokens, [string]$RecordKey)
    $Lines.Add(($Tokens -join ' '))
    $Lines.Add("if (`$LASTEXITCODE -ne 0) { throw $(Quote-PowerShell ("Failed to create $RecordKey")) }")
    $Lines.Add('')
}

function Test-PositiveInteger {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    $isIntegerType =
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
    return $isIntegerType -and [decimal]$Value -gt 0
}

function Test-PositiveNumber {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    $isNumber =
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
    return $isNumber -and [decimal]$Value -gt 0
}

function Test-StableObjectId {
    param([AllowNull()][object]$Value)
    if ($Value -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -eq $Value.Trim()
    }
    return Test-PositiveInteger $Value
}

function Test-NonEmptyTrimmedString {
    param([AllowNull()][object]$Value)
    return $Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value) -and $Value -eq $Value.Trim()
}

function Test-StableRecordKey {
    param([AllowNull()][object]$Value, [string]$Prefix)
    if (-not (Test-NonEmptyTrimmedString $Value)) { return $false }
    return [regex]::IsMatch(
        [string]$Value,
        ('^' + [regex]::Escape($Prefix) + '[A-Z0-9]+(?:_[A-Z0-9]+)*$'),
        [Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
}

function Test-StableObjectRecordKey {
    param([AllowNull()][object]$Value)
    if (-not (Test-NonEmptyTrimmedString $Value)) { return $false }
    return [regex]::IsMatch(
        [string]$Value,
        '^HG_[UAMP]_[A-Z0-9]+(?:_[A-Z0-9]+)*$',
        [Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
}

function Test-JsonArray {
    param([AllowNull()][object]$Value)
    return $null -ne $Value -and $Value -isnot [string] -and $Value -isnot [pscustomobject] -and
        $Value -is [System.Collections.IEnumerable]
}

function Assert-CanonicalObjectCollection {
    param(
        [AllowNull()][object]$Records,
        [string]$CollectionName,
        [string]$ObjectType,
        [string]$RecordKeyPrefix,
        [string[]]$ExpectedKeys,
        [System.Collections.Generic.Dictionary[string,string]]$GlobalRecordKeyOwners,
        [System.Collections.Generic.List[string]]$Errors
    )

    $recordsByKey = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    if (-not (Test-JsonArray $Records)) {
        $Errors.Add("$CollectionName must be an array")
        return ,$recordsByKey
    }

    $recordList = @($Records)
    if ($recordList.Count -ne $ExpectedKeys.Count) {
        $Errors.Add("$CollectionName must contain exactly $($ExpectedKeys.Count) objects; got $($recordList.Count)")
    }

    $expectedKeySet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($expectedKey in $ExpectedKeys) { [void]$expectedKeySet.Add($expectedKey) }

    foreach ($record in $recordList) {
        if ($record -isnot [pscustomobject]) {
            $Errors.Add("$CollectionName contains a non-object record")
            continue
        }
        $recordKeyProperty = Get-ExactJsonProperty $record 'record_key'
        if ($null -eq $recordKeyProperty) {
            $Errors.Add("$CollectionName record_key is required")
            continue
        }
        if (-not (Test-StableRecordKey $recordKeyProperty.Value $RecordKeyPrefix)) {
            $Errors.Add("$CollectionName contains invalid stable $ObjectType record_key: $([string]$recordKeyProperty.Value)")
            continue
        }

        $recordKey = [string]$recordKeyProperty.Value
        if ($recordsByKey.ContainsKey($recordKey)) {
            $Errors.Add("duplicate $CollectionName record_key: $recordKey")
            continue
        }
        $recordsByKey.Add($recordKey, $record)
        if ($GlobalRecordKeyOwners.ContainsKey($recordKey)) {
            $Errors.Add("duplicate global record_key ${recordKey}: $CollectionName and $($GlobalRecordKeyOwners[$recordKey])")
        }
        else {
            $GlobalRecordKeyOwners.Add($recordKey, $CollectionName)
        }
    }

    foreach ($expectedKey in $ExpectedKeys) {
        if (-not $recordsByKey.ContainsKey($expectedKey)) {
            $Errors.Add("missing canonical $ObjectType record_key: $expectedKey")
        }
    }
    foreach ($recordKey in $recordsByKey.Keys) {
        if (-not $expectedKeySet.Contains($recordKey)) {
            $Errors.Add("unexpected $ObjectType record_key: $recordKey")
        }
    }
    return ,$recordsByKey
}

function Get-ReferenceKeyList {
    param(
        [AllowNull()][object]$Record,
        [string]$RecordKey,
        [string]$PropertyName,
        [System.Collections.Generic.List[string]]$Errors
    )

    $values = [System.Collections.Generic.List[object]]::new()
    $property = Get-ExactJsonProperty $Record $PropertyName
    if ($null -eq $property) {
        $Errors.Add("${RecordKey}: $PropertyName is required")
        return ,$values
    }
    if ($property.Value -is [string]) {
        $values.Add($property.Value)
    }
    elseif (Test-JsonArray $property.Value) {
        foreach ($value in @($property.Value)) { $values.Add($value) }
    }
    else {
        $Errors.Add("${RecordKey}: $PropertyName must be an array of record_key values")
    }
    return ,$values
}

function Add-ObjectDependencyClosureErrors {
    param(
        [object[]]$Units,
        [object[]]$Abilities,
        [object]$ObjectByKey,
        [object]$UnitByKey,
        [object]$AbilityByKey,
        [System.Collections.Generic.List[string]]$Errors
    )

    $boundAbilitiesByUnit = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($unit in @($Units)) {
        if ($unit -isnot [pscustomobject] -or -not (Test-StableRecordKey $unit.record_key 'HG_U_')) { continue }
        $unitKey = [string]$unit.record_key
        $boundAbilityKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $boundAbilitiesByUnit[$unitKey] = $boundAbilityKeys
        $abilityKeys = Get-ReferenceKeyList $unit $unitKey 'common_ability_keys' $Errors
        foreach ($abilityKeyValue in $abilityKeys) {
            if (-not (Test-StableRecordKey $abilityKeyValue 'HG_A_')) {
                $Errors.Add("${unitKey}: common_ability_keys contains invalid ability record_key: $([string]$abilityKeyValue)")
                continue
            }
            $abilityKey = [string]$abilityKeyValue
            if (-not $boundAbilityKeys.Add($abilityKey)) {
                $Errors.Add("${unitKey}: common_ability_keys contains duplicate ability $abilityKey")
                continue
            }
            if (-not $AbilityByKey.ContainsKey($abilityKey)) {
                $Errors.Add("${unitKey}: unknown common ability $abilityKey")
            }
            elseif (@($AbilityByKey[$abilityKey].owner_keys) -notcontains $unitKey) {
                $Errors.Add("${unitKey}: ability $abilityKey does not list unit as owner")
            }
        }
    }

    foreach ($ability in @($Abilities)) {
        if ($ability -isnot [pscustomobject] -or -not (Test-StableRecordKey $ability.record_key 'HG_A_')) { continue }
        $abilityKey = [string]$ability.record_key
        $ownerKeys = Get-ReferenceKeyList $ability $abilityKey 'owner_keys' $Errors
        if ($ownerKeys.Count -eq 0) { $Errors.Add("${abilityKey}: owner_keys must not be empty") }
        $seenOwners = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($ownerKeyValue in $ownerKeys) {
            if (-not (Test-StableRecordKey $ownerKeyValue 'HG_U_')) {
                $Errors.Add("${abilityKey}: owner_keys contains invalid unit record_key: $([string]$ownerKeyValue)")
                continue
            }
            $ownerKey = [string]$ownerKeyValue
            if (-not $seenOwners.Add($ownerKey)) {
                $Errors.Add("${abilityKey}: owner_keys contains duplicate unit $ownerKey")
                continue
            }
            if (-not $UnitByKey.ContainsKey($ownerKey)) {
                $Errors.Add("${abilityKey}: unknown owner $ownerKey")
            }
            elseif (-not $boundAbilitiesByUnit.ContainsKey($ownerKey) -or -not $boundAbilitiesByUnit[$ownerKey].Contains($abilityKey)) {
                $Errors.Add("${abilityKey}: owner $ownerKey does not bind this ability")
            }
        }

        $dependencyKeys = Get-ReferenceKeyList $ability $abilityKey 'dependency_keys' $Errors
        $seenDependencies = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($dependencyKeyValue in $dependencyKeys) {
            if (-not (Test-StableObjectRecordKey $dependencyKeyValue)) {
                $Errors.Add("${abilityKey}: dependency_keys contains invalid object record_key: $([string]$dependencyKeyValue)")
                continue
            }
            $dependencyKey = [string]$dependencyKeyValue
            if (-not $seenDependencies.Add($dependencyKey)) {
                $Errors.Add("${abilityKey}: dependency_keys contains duplicate object $dependencyKey")
                continue
            }
            if (-not $ObjectByKey.ContainsKey($dependencyKey)) {
                $Errors.Add("${abilityKey}: unknown dependency $dependencyKey")
            }
        }
    }
}

function Add-UnresolvedFieldsContractErrors {
    param(
        [AllowNull()][object]$Object,
        [string]$RecordKey,
        [System.Collections.Generic.List[string]]$Errors
    )
    $property = Get-ExactJsonProperty $Object 'unresolved_fields'
    if ($null -eq $property) {
        $Errors.Add("${RecordKey}: unresolved_fields missing")
    }
    elseif ($property.Value -isnot [System.Array]) {
        $Errors.Add("${RecordKey}: unresolved_fields must be an array")
    }
}

function Test-JsonNumber {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    $isNumber = $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
    if (-not $isNumber) { return $false }
    $number = [double]$Value
    return -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)
}

function Test-JsonInteger {
    param([AllowNull()][object]$Value)
    return (Test-JsonNumber $Value) -and [math]::Truncate([double]$Value) -eq [double]$Value
}

function Test-ObjectFieldValue {
    param([AllowNull()][object]$Value, [object]$Rule)
    switch -CaseSensitive ([string]$Rule.Kind) {
        'boolean' { return $Value -is [bool] }
        'enum' { return (Test-JsonInteger $Value) -and @($Rule.Values) -contains [int]$Value }
        'positive_integer' { return (Test-JsonInteger $Value) -and [double]$Value -gt 0 }
        'nonnegative_number' { return (Test-JsonNumber $Value) -and [double]$Value -ge 0 }
        'positive_number' { return (Test-JsonNumber $Value) -and [double]$Value -gt 0 }
        'nonnegative_number_array' {
            if ($Value -isnot [System.Array]) { return $false }
            foreach ($item in @($Value)) { if (-not (Test-JsonNumber $item) -or [double]$item -lt 0) { return $false } }
            return $true
        }
        'positive_integer_array' {
            if ($Value -isnot [System.Array]) { return $false }
            foreach ($item in @($Value)) { if (-not (Test-JsonInteger $item) -or [double]$item -le 0) { return $false } }
            return $true
        }
        'rgb_array' {
            if ($Value -isnot [System.Array] -or @($Value).Count -ne 3) { return $false }
            foreach ($item in @($Value)) { if (-not (Test-JsonInteger $item) -or [int]$item -lt 0 -or [int]$item -gt 255) { return $false } }
            return $true
        }
        default { return $false }
    }
}

function Add-ObjectFieldErrors {
    param($Fields, [System.Collections.IDictionary]$Schema, [string]$RecordKey, [System.Collections.Generic.List[string]]$Errors)
    if ($Fields -isnot [pscustomobject]) { $Errors.Add("${RecordKey}: object_fields must be an object"); return }
    $schemaNames = @($Schema.Keys)
    foreach ($property in @($Fields.PSObject.Properties)) {
        if ($schemaNames -cnotcontains $property.Name) {
            $Errors.Add("${RecordKey}: object_fields unknown field: $($property.Name)")
            continue
        }
        if (-not (Test-ObjectFieldValue $property.Value $Schema[$property.Name])) {
            $Errors.Add("${RecordKey}: object_fields $($property.Name) has an invalid value")
        }
    }
}

function Add-RequiredObjectFieldErrors {
    param(
        $Fields,
        [string[]]$RequiredFields,
        [string]$ObjectType,
        [string]$RecordKey,
        [System.Collections.Generic.List[string]]$Errors
    )
    if ($Fields -isnot [pscustomobject]) { return }
    foreach ($fieldName in $RequiredFields) {
        if ($null -eq (Get-ExactJsonProperty $Fields $fieldName)) {
            $Errors.Add("${RecordKey}: missing merged $ObjectType field $fieldName")
        }
    }
}

function Add-AbilityLevelArrayErrors {
    param($Fields, [string]$RecordKey, [string[]]$ArrayFields, [System.Collections.Generic.List[string]]$Errors)
    $maxLevel = Get-ExactJsonProperty $Fields 'ability_max_level'
    if ($null -eq $maxLevel -or -not (Test-JsonInteger $maxLevel.Value) -or [int]$maxLevel.Value -le 0) { return }
    foreach ($fieldName in $ArrayFields) {
        $property = Get-ExactJsonProperty $Fields $fieldName
        if ($null -ne $property -and $property.Value -is [System.Array] -and @($property.Value).Count -ne [int]$maxLevel.Value) {
            $Errors.Add("${RecordKey}: object_fields $fieldName must contain exactly $([int]$maxLevel.Value) values")
        }
    }
}

$unitFieldSchema = [ordered]@{
    hp_max=@{Kind='positive_number'}; hp_max_grow=@{Kind='nonnegative_number'}; mp_max=@{Kind='nonnegative_number'}; mp_max_grow=@{Kind='nonnegative_number'}
    attack_phy=@{Kind='nonnegative_number'}; attack_phy_grow=@{Kind='nonnegative_number'}; attack_mag=@{Kind='nonnegative_number'}
    defense_phy=@{Kind='nonnegative_number'}; defense_mag=@{Kind='nonnegative_number'}; attack_speed=@{Kind='nonnegative_number'}
    attack_interval=@{Kind='positive_number'}; common_atk_type=@{Kind='enum';Values=@(0,1)}; ori_speed=@{Kind='nonnegative_number'}
    turn_speed=@{Kind='nonnegative_number'}; sight_range=@{Kind='nonnegative_number'}; attack_range=@{Kind='nonnegative_number'}
    common_atk_range=@{Kind='positive_number'}; reward_exp=@{Kind='nonnegative_number'}; reward_official_res_1=@{Kind='nonnegative_number'}
}
$abilityFieldSchema = [ordered]@{
    ability_max_level=@{Kind='positive_integer'}; sight_type=@{Kind='enum';Values=@(0,1,2,3,4,5,6,7)}; ability_cast_type=@{Kind='enum';Values=@(2,3)}
    ability_cast_point=@{Kind='nonnegative_number'}; ability_bw_point=@{Kind='nonnegative_number'}; is_immediate=@{Kind='boolean'}; is_meele=@{Kind='boolean'}
    cold_down_time=@{Kind='nonnegative_number_array'}; ability_cost=@{Kind='nonnegative_number_array'}; ability_hp_cost=@{Kind='nonnegative_number_array'}
    ability_damage=@{Kind='nonnegative_number_array'}; ability_damage_range=@{Kind='nonnegative_number_array'}; ability_cast_range=@{Kind='nonnegative_number_array'}
    circle_radius=@{Kind='nonnegative_number_array'}; sector_radius=@{Kind='nonnegative_number_array'}; sector_angle=@{Kind='nonnegative_number_array'}
    arrow_length=@{Kind='nonnegative_number_array'}; arrow_width=@{Kind='nonnegative_number_array'}; required_level=@{Kind='positive_integer_array'}
}
$abilityLevelArrayFields = @('cold_down_time','ability_cost','ability_hp_cost','ability_damage','ability_damage_range','ability_cast_range','circle_radius','sector_radius','sector_angle','arrow_length','arrow_width','required_level')
$modifierFieldSchema = [ordered]@{
    modifier_type=@{Kind='enum';Values=@(1,2,3,4)}; modifier_effect=@{Kind='enum';Values=@(1,2,3)}; layer_max=@{Kind='positive_integer'}
    disappear_when_dead=@{Kind='boolean'}; show_on_ui=@{Kind='boolean'}; shield_value=@{Kind='nonnegative_number'}; shield_type=@{Kind='enum';Values=@(0,1,2)}
    influence_rng=@{Kind='nonnegative_number'}; is_influence_self=@{Kind='boolean'}; material_color=@{Kind='rgb_array'}
}
$projectileFieldSchema = [ordered]@{
    max_duration=@{Kind='positive_number'}; move_channel=@{Kind='enum';Values=@(0,1)}
    move_limitation=@{Kind='enum';Values=@(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15)}; sfx_loop=@{Kind='boolean'}
    effect_foes=@{Kind='positive_integer'}; effect_friend=@{Kind='positive_integer'}
}
$requiredUnitFields = @(
    'hp_max','hp_max_grow','mp_max','mp_max_grow','attack_phy','attack_phy_grow','attack_mag',
    'defense_phy','defense_mag','attack_speed','attack_interval','common_atk_type','ori_speed',
    'turn_speed','sight_range','common_atk_range','reward_exp','reward_official_res_1'
)
$requiredAbilityFields = @(
    'ability_max_level','ability_cast_type','ability_cast_point','ability_bw_point','is_immediate',
    'is_meele','cold_down_time','ability_cost','ability_hp_cost','ability_damage','required_level','sight_type'
)
$requiredModifierFields = @('modifier_type','modifier_effect','layer_max','disappear_when_dead','show_on_ui')
$requiredProjectileFields = @('max_duration','move_channel','move_limitation','sfx_loop')

$canonicalObjectKeys = [ordered]@{
    units = @(
        'HG_U_MOUNTAIN_MONKEY','HG_U_STONEHIDE_BEAST','HG_U_VINE_IMP','HG_U_MONKEY_PACK_LEADER',
        'HG_U_GREAT_APE','HG_U_WATERFALL_IMP','HG_U_SPRING_SPIRIT','HG_U_FISH_SENTINEL',
        'HG_U_WATERFALL_GUARD','HG_U_TIDE_TRACE_GUARD','HG_U_MACAQUE_KING','HG_U_PEACH_SPIRIT',
        'HG_U_MIST_MONKEY','HG_U_CAVE_BAT','HG_U_CAVE_IMP','HG_U_YURONG_KING','HG_U_BAT_STATUE',
        'HG_U_SEVENSTAR_DEMON','HG_U_SHANXIAO_CASTER','HG_U_WINGED_DEMON','HG_U_BULL_SCOUT',
        'HG_U_LION_CAMEL_KING','HG_U_PENG_KING','HG_U_FISH_PATROLLER','HG_U_TURTLE_GUARD',
        'HG_U_WATER_MAGE','HG_U_VORTEX_SOLDIER','HG_U_RIPTIDE_NODE_SOLDIER','HG_U_JIAO_KING_P1',
        'HG_U_SHARK_KING_P1','HG_U_TURTLE_MINISTER','HG_U_DRAGON_KING_P1','HG_U_DRAGON_KING_P2',
        'HG_U_OX_KING_HUMAN','HG_U_ARMORED_WHITE_OX'
    )
    abilities = @(
        'HG_A_PACK_LEAP','HG_A_STONE_SMASH','HG_A_VINE_DART','HG_A_PACK_CALL','HG_A_APE_QUAKE',
        'HG_A_APE_THROW','HG_A_WATER_DASH','HG_A_SPRING_BLESS','HG_A_FISH_BOLT','HG_A_WATER_GUARD_WAVE',
        'HG_A_TRACE_OVERFLOW','HG_A_MACAQUE_CLONE','HG_A_MACAQUE_SPIN','HG_A_MACAQUE_WIND_EYE',
        'HG_A_PEACH_POLLEN','HG_A_MIST_STEP','HG_A_BAT_DIVE','HG_A_WING_DIVE','HG_A_YURONG_FOG',
        'HG_A_YURONG_PHANTOM','HG_A_BAT_SONIC','HG_A_BAT_CALL','HG_A_SEVENSTAR_REND',
        'HG_A_SHANXIAO_SPIKE','HG_A_BULL_CHARGE','HG_A_BULL_FLAME_SLASH','HG_A_LION_CHARGE',
        'HG_A_LION_ROAR','HG_A_PENG_DIVE','HG_A_PENG_WIND_BLADE','HG_A_PENG_WIND_EYE',
        'HG_A_FISH_PATROL_DASH','HG_A_TURTLE_SHELL','HG_A_WATER_MAGE_POOL','HG_A_VORTEX_PULL',
        'HG_A_RIPTIDE_ANCHOR','HG_A_JIAO_COLUMN','HG_A_JIAO_TAIL','HG_A_JIAO_SUBMERGE',
        'HG_A_JIAO_TIDE_EYE','HG_A_SHARK_BITE','HG_A_SHARK_VORTEX','HG_A_SHARK_FRENZY',
        'HG_A_SHARK_ANCHOR','HG_A_TURTLE_MINISTER_SHELL','HG_A_DRAGON_WATER_LANCE',
        'HG_A_DRAGON_TIDE_FIELD','HG_A_DRAGON_SEA_EYE','HG_A_DRAGON_REVERSE_TIDE',
        'HG_A_DRAGON_FALL','HG_A_OX_CLEAVE','HG_A_OX_EARTH_CRACK','HG_A_OX_WHITE_CHARGE',
        'HG_A_OX_HUMAN_ECHO','HG_A_OX_MAGMA_RING'
    )
    modifiers = @(
        'HG_M_STONE_SUNDER','HG_M_SPRING_BLESS','HG_M_TURTLE_SHELL','HG_M_PEACH_POLLEN',
        'HG_M_MIST_FOG','HG_M_TIDE_TRACE_EXPOSED','HG_M_RIPTIDE_EXPOSED','HG_M_VORTEX_PULL',
        'HG_M_BOSS_FRENZY','HG_M_DRAGON_TIDE','HG_M_OX_RAGE','HG_M_OX_ARROGANCE'
    )
    projectiles = @(
        'HG_P_VINE_DART','HG_P_FISH_BOLT','HG_P_PEACH_POLLEN','HG_P_APE_STONE',
        'HG_P_WIND_BLADE','HG_P_WATER_LANCE','HG_P_FLAME_ARC'
    )
}

$canonicalPublicBossByEncounter = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$canonicalPublicBossByEncounter.Add('HG_E_MACAQUE_KING', [pscustomobject]@{
    UnitKey = 'HG_U_MACAQUE_KING'; ArenaKey = 'arena_mihouwang'
})
$canonicalPublicBossByEncounter.Add('HG_E_JIAO_KING', [pscustomobject]@{
    UnitKey = 'HG_U_JIAO_KING_P1'; ArenaKey = 'arena_jiaomowang_phase1'
})
$canonicalPublicBossByEncounter.Add('HG_E_SHARK_KING', [pscustomobject]@{
    UnitKey = 'HG_U_SHARK_KING_P1'; ArenaKey = 'arena_shamowang_phase1'
})
$publicBossArenaByUnit = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach ($canonicalBoss in $canonicalPublicBossByEncounter.Values) {
    $publicBossArenaByUnit.Add([string]$canonicalBoss.UnitKey, [string]$canonicalBoss.ArenaKey)
}

function Add-CanonicalPublicBossBindingErrors {
    param(
        [AllowNull()][object[]]$SpawnBindings,
        [AllowNull()][object[]]$ResourceBindings,
        [string]$SourceLabel,
        [System.Collections.Generic.List[string]]$Errors
    )
    foreach ($entry in $canonicalPublicBossByEncounter.GetEnumerator()) {
        $encounterKey = [string]$entry.Key
        $canonicalBoss = $entry.Value
        $spawns = @($SpawnBindings | Where-Object { $_ -is [pscustomobject] -and $_.encounter_key -ceq $encounterKey })
        $arenas = @($ResourceBindings | Where-Object {
            $_ -is [pscustomobject] -and $_.encounter_key -ceq $encounterKey -and $_.role -ceq 'boss_arena'
        })
        $valid = $spawns.Count -eq 1 -and $arenas.Count -eq 1 -and
            $spawns[0].unit_key -ceq $canonicalBoss.UnitKey -and
            $spawns[0].anchor_key -ceq $canonicalBoss.ArenaKey -and
            $arenas[0].resource_key -ceq $canonicalBoss.ArenaKey
        if (-not $valid) {
            $Errors.Add("$SourceLabel ${encounterKey}: canonical public boss tuple must be $($canonicalBoss.UnitKey) -> $($canonicalBoss.ArenaKey)")
        }
    }
}

function Assert-ExactProperties {
    param(
        $Object,
        [string[]]$Names,
        [string]$Prefix,
        [System.Collections.Generic.List[string]]$Errors
    )
    $valid = $true
    foreach ($name in $Names) {
        if ($null -eq (Get-ExactJsonProperty $Object $name)) {
            $Errors.Add("$Prefix missing required property: $name")
            $valid = $false
        }
    }
    foreach ($property in $Object.PSObject.Properties) {
        if ($Names -cnotcontains $property.Name) {
            $Errors.Add("$Prefix has unexpected property: $($property.Name)")
            $valid = $false
        }
    }
    return $valid
}

function Test-InstanceContractShape {
    param(
        $Contract,
        [string]$ContractKey,
        [System.Collections.Generic.List[string]]$Errors,
        $ResourceOwners,
        $RoleSchemas
    )

    $valid = $true
    $roleSchema = $RoleSchemas[$ContractKey]
    if ($null -eq $roleSchema) {
        $Errors.Add("instance map contract has no canonical role schema: $ContractKey")
        return $false
    }
    if (-not (Test-NonEmptyTrimmedString $Contract.layer)) {
        $Errors.Add("instance map contract layer must be a non-empty trimmed string: $ContractKey")
        $valid = $false
    }
    elseif ($Contract.layer -ne $roleSchema.layer) {
        $Errors.Add("instance map contract layer violates canonical role schema: $ContractKey")
        $valid = $false
    }
    if (-not (Test-PositiveInteger $Contract.slot_count)) {
        $Errors.Add("instance map contract slot_count must be a positive integer: $ContractKey")
        return $false
    }
    if ($ContractKey -eq 'HG_I_DRAGON_FOUR_SEAS' -and $Contract.slot_count -ne 4) {
        $Errors.Add('HG_I_DRAGON_FOUR_SEAS must declare exactly four slots')
        $valid = $false
    }
    elseif ($Contract.slot_count -ne $roleSchema.slot_count) {
        $Errors.Add("instance map contract slot_count violates canonical role schema: $ContractKey")
        $valid = $false
    }
    $slotsProperty = $Contract.PSObject.Properties['slots']
    $slotsValue = $null
    if ($null -ne $slotsProperty) { $slotsValue = $slotsProperty.Value }
    if (-not (Test-JsonArray $slotsValue)) {
        $Errors.Add("instance map contract slots must be an array: $ContractKey")
        return $false
    }
    $slots = @($slotsValue)
    if ($slots.Count -eq 0) {
        $Errors.Add("instance map contract slots must not be empty: $ContractKey")
        return $false
    }
    if ($slots.Count -ne $Contract.slot_count) {
        $Errors.Add("instance map contract slots must contain exactly $($Contract.slot_count) entries: $ContractKey")
        return $false
    }

    $slotIds = @{}
    foreach ($slot in $slots) {
        if ($slot -isnot [pscustomobject] -or -not (Test-PositiveInteger $slot.slot_id) -or
            $slot.slot_id -gt $Contract.slot_count -or $slotIds.ContainsKey([string]$slot.slot_id)) {
            $Errors.Add("instance map contract has an invalid or duplicate slot_id: $ContractKey")
            $valid = $false
            continue
        }
        if (-not (Assert-ExactProperties $slot @('slot_id','roles') "instance map contract slot for $ContractKey" $Errors)) {
            $valid = $false
        }
        $slotIds[[string]$slot.slot_id] = $true
        $rolesProperty = $slot.PSObject.Properties['roles']
        $rolesValue = $null
        if ($null -ne $rolesProperty) { $rolesValue = $rolesProperty.Value }
        if (-not (Test-JsonArray $rolesValue) -or @($rolesValue).Count -eq 0) {
            $Errors.Add("instance map contract slot roles must be a non-empty array: ${ContractKey}:$($slot.slot_id)")
            $valid = $false
            continue
        }
        if (@($rolesValue).Count -ne $roleSchema.roles.Count) {
            $Errors.Add("instance map contract slot roles must exactly match canonical role schema: ${ContractKey}:$($slot.slot_id)")
            $valid = $false
        }
        $roleNames = @{}
        foreach ($role in @($rolesValue)) {
            if ($role -isnot [pscustomobject]) {
                $Errors.Add("instance map contract role must be an object: ${ContractKey}:$($slot.slot_id)")
                $valid = $false
                continue
            }
            if (-not (Assert-ExactProperties $role @('role','resource_key','source','expected_type','layer','stable_object_id') "instance role for ${ContractKey}:$($slot.slot_id)" $Errors)) {
                $valid = $false
            }
            foreach ($field in @('role', 'resource_key', 'source', 'expected_type', 'layer')) {
                if (-not (Test-NonEmptyTrimmedString $role.$field)) {
                    $Errors.Add("instance map contract role has invalid $($field): ${ContractKey}:$($slot.slot_id)")
                    $valid = $false
                }
            }
            if ((Test-NonEmptyTrimmedString $role.role) -and $roleNames.ContainsKey([string]$role.role)) {
                $Errors.Add("instance map contract role is duplicated: ${ContractKey}:$($slot.slot_id):$($role.role)")
                $valid = $false
            }
            elseif (Test-NonEmptyTrimmedString $role.role) {
                $roleNames[[string]$role.role] = $true
            }
            if (Test-NonEmptyTrimmedString $role.role) {
                if (-not $roleSchema.roles.ContainsKey([string]$role.role)) {
                    $Errors.Add("instance map contract role is not canonical: ${ContractKey}:$($slot.slot_id):$($role.role)")
                    $valid = $false
                }
                elseif ($role.expected_type -ne $roleSchema.roles[[string]$role.role]) {
                    $Errors.Add("instance map contract role expected_type violates canonical role schema: ${ContractKey}:$($slot.slot_id):$($role.role)")
                    $valid = $false
                }
            }
            if (Test-NonEmptyTrimmedString $role.resource_key) {
                $owner = "${ContractKey}:$($slot.slot_id):$($role.role)"
                if ($ResourceOwners.ContainsKey([string]$role.resource_key)) {
                    $Errors.Add("instance map contract resource_key is duplicated globally: $($role.resource_key)")
                    $valid = $false
                }
                else { $ResourceOwners[[string]$role.resource_key] = $owner }
            }
            if ($role.source -ne 'instance_logic_resource') {
                $Errors.Add("instance map contract role source is invalid: ${ContractKey}:$($slot.slot_id):$($role.role)")
                $valid = $false
            }
            if ($role.expected_type -notin @('point','rectArea')) {
                $Errors.Add("instance map contract role expected_type is invalid: ${ContractKey}:$($slot.slot_id):$($role.role)")
                $valid = $false
            }
            if ($role.layer -ne $Contract.layer) {
                $Errors.Add("instance map contract role layer does not match contract: ${ContractKey}:$($slot.slot_id)")
                $valid = $false
            }
        }
        foreach ($requiredRole in $roleSchema.roles.Keys) {
            if (-not $roleNames.ContainsKey([string]$requiredRole)) {
                $Errors.Add("instance map contract slot is missing canonical role: ${ContractKey}:$($slot.slot_id):$requiredRole")
                $valid = $false
            }
        }
    }
    return $valid
}

function Resolve-PackageLeafPath {
    param(
        [string]$PackageRoot,
        [string]$RelativePath,
        [string]$Label,
        [string]$ExpectedExtension,
        [string]$ExpectedFileType,
        [string]$ExpectedFileName
    )
    $candidatePath = [IO.Path]::GetFullPath((Join-Path $PackageRoot $RelativePath))
    $rootPrefix = $PackageRoot.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidatePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must resolve to a file inside the manifest package"
    }
    if ([IO.Path]::GetExtension($candidatePath) -ne $ExpectedExtension) {
        throw "$Label must resolve to a $ExpectedFileType file"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedFileName) -and [IO.Path]::GetFileName($candidatePath) -ne $ExpectedFileName) {
        throw "$Label must resolve to $ExpectedFileName"
    }
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        throw "$Label does not exist: $RelativePath"
    }

    $currentPath = $candidatePath
    while (-not [string]::Equals($currentPath, $PackageRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $item = Get-Item -LiteralPath $currentPath -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label may not traverse a reparse point"
        }
        $parentPath = Split-Path -Parent $currentPath
        if ([string]::IsNullOrWhiteSpace($parentPath) -or [string]::Equals($parentPath, $currentPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "$Label could not be safely resolved"
        }
        $currentPath = $parentPath
    }

    $resolvedPath = (Resolve-Path -LiteralPath $candidatePath).Path
    if (-not $resolvedPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must resolve to a file inside the manifest package"
    }
    return $resolvedPath
}

function ConvertTo-CanonicalValue {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or
        $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $result[[string]$key] = ConvertTo-CanonicalValue $Value[$key]
        }
        return [pscustomobject]$result
    }
    if (Test-JsonArray $Value) {
        $items = @()
        foreach ($item in $Value) { $items += ,(ConvertTo-CanonicalValue $item) }
        return ,$items
    }
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
        $result[$property.Name] = ConvertTo-CanonicalValue $property.Value
    }
    return [pscustomobject]$result
}

function Get-CanonicalJson {
    param([AllowNull()][object]$Value)
    $canonicalValue = ConvertTo-CanonicalValue $Value
    return ConvertTo-Json -InputObject $canonicalValue -Depth 100 -Compress
}

if (-not ('HuaguoshanMaterializer.Trust.NativeFilePath' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace HuaguoshanMaterializer.Trust
{
    public static class NativeFilePath
    {
        private const uint FileShareRead = 0x00000001;
        private const uint FileShareWrite = 0x00000002;
        private const uint FileShareDelete = 0x00000004;
        private const uint OpenExisting = 3;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle file,
            StringBuilder filePath,
            uint filePathLength,
            uint flags);

        public static string GetFinalPath(string path)
        {
            using (SafeFileHandle handle = CreateFileW(
                path,
                0,
                FileShareRead | FileShareWrite | FileShareDelete,
                IntPtr.Zero,
                OpenExisting,
                0,
                IntPtr.Zero))
            {
                if (handle.IsInvalid)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to open path: " + path);
                }

                StringBuilder buffer = new StringBuilder(1024);
                uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
                if (length == 0)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to resolve final path: " + path);
                }
                if (length >= buffer.Capacity)
                {
                    buffer = new StringBuilder((int)length + 1);
                    length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
                    if (length == 0 || length >= buffer.Capacity)
                    {
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to resolve final path: " + path);
                    }
                }
                return buffer.ToString();
            }
        }
    }
}
'@
}

function Get-MaterializerFinalFileSystemPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $finalPath = [HuaguoshanMaterializer.Trust.NativeFilePath]::GetFinalPath($resolvedPath)
    if ($finalPath.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $finalPath.Substring(8)
    }
    if ($finalPath.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        return $finalPath.Substring(4)
    }
    return $finalPath
}

function Assert-MaterializerExecutionEnvironmentClean {
    foreach ($name in @('NODE_OPTIONS','NODE_PATH')) {
        if ($null -ne [Environment]::GetEnvironmentVariable($name, 'Process')) {
            throw "Untrusted Node environment variable is set: $name"
        }
    }
    $luaEnvironmentNames = @(
        [Environment]::GetEnvironmentVariables('Process').Keys |
            ForEach-Object { [string]$_ } |
            Where-Object { $_ -match '(?i)^LUA_' } |
            Sort-Object -Unique
    )
    foreach ($name in $luaEnvironmentNames) {
        throw "Untrusted Lua environment variable is set: $name"
    }
}

function Get-MaterializerTrustedNodeExecutable {
    param([AllowNull()][string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        throw 'The original process PATH is empty; a trusted node.exe cannot be resolved.'
    }

    $seenPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $rejections = New-Object 'Collections.Generic.List[string]'
    foreach ($entry in $PathValue.Split([IO.Path]::PathSeparator)) {
        $candidatePath = $null
        $directory = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim([char]'"'))
        if ([string]::IsNullOrWhiteSpace($directory)) { continue }

        try {
            $candidatePath = Join-Path $directory 'node.exe'
            if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }

            $nodePath = Get-MaterializerFinalFileSystemPath -Path $candidatePath
            if (-not $seenPaths.Add($nodePath)) { continue }

            $nodeItem = Get-Item -LiteralPath $nodePath -Force -ErrorAction Stop
            if ($nodeItem.PSIsContainer -or
                [IO.Path]::GetExtension($nodePath) -ine '.exe' -or
                [IO.Path]::GetFileName($nodePath) -ine 'node.exe') {
                throw "resolved to an unexpected physical file: $nodePath"
            }

            $sha256BeforeVerification = (Get-FileHash -Algorithm SHA256 -LiteralPath $nodePath).Hash
            $nodeSignature = Get-AuthenticodeSignature -LiteralPath $nodePath
            $nodeSignerSubject = if ($nodeSignature.SignerCertificate) { [string]$nodeSignature.SignerCertificate.Subject } else { '' }
            if ($nodeSignature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
                $nodeSignerSubject -notmatch '(?i)(^|,\s*)(CN|O)=(OpenJS Foundation|Node\.js Foundation)(,|$)') {
                throw 'does not have a valid OpenJS/Node.js Foundation signature'
            }

            $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($nodePath)
            if ($versionInfo.OriginalFilename -ine 'node.exe' -or
                $versionInfo.ProductName -ine 'Node.js' -or
                [string]$versionInfo.ProductVersion -cnotmatch '^\d+\.\d+\.\d+$' -or
                $versionInfo.FileMajorPart -le 0) {
                throw 'has invalid Node.js product or version metadata'
            }
            $metadataVersion = '{0}.{1}.{2}' -f $versionInfo.FileMajorPart, $versionInfo.FileMinorPart, $versionInfo.FileBuildPart
            if ([string]$versionInfo.ProductVersion -cne $metadataVersion) {
                throw "has inconsistent version metadata: product $($versionInfo.ProductVersion), file $metadataVersion"
            }

            $nodePathAfterVerification = Get-MaterializerFinalFileSystemPath -Path $candidatePath
            $sha256AfterVerification = (Get-FileHash -Algorithm SHA256 -LiteralPath $nodePath).Hash
            if ($nodePathAfterVerification -ine $nodePath -or
                $sha256AfterVerification -cne $sha256BeforeVerification) {
                throw 'changed during signature and metadata verification'
            }

            return [pscustomobject]@{
                Path = $nodePath
                Directory = Split-Path -Parent $nodePath
                ProductVersion = [string]$versionInfo.ProductVersion
                RuntimeVersion = 'v' + $metadataVersion
                Sha256 = $sha256AfterVerification
            }
        }
        catch {
            if ($candidatePath) {
                $rejections.Add("$candidatePath - $($_.Exception.Message)")
            }
        }
    }

    $details = if ($rejections.Count -gt 0) { ' Rejected candidates: ' + ($rejections -join '; ') } else { '' }
    throw "No trusted, signed Node.js node.exe was found on the original process PATH.$details"
}

function Assert-MaterializerTrustedNodeIdentity {
    param([Parameter(Mandatory = $true)]$TrustedNode)

    $pathResolvedNode = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pathResolvedNode -or [string]::IsNullOrWhiteSpace($pathResolvedNode.Source)) {
        throw 'Controlled PATH no longer resolves the verified Node.js executable.'
    }
    $pathResolvedNodePhysicalPath = Get-MaterializerFinalFileSystemPath -Path $pathResolvedNode.Source
    if ($pathResolvedNodePhysicalPath -ine $TrustedNode.Path) {
        throw "Controlled PATH resolved a different Node.js executable: $pathResolvedNodePhysicalPath"
    }

    $currentVersionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($TrustedNode.Path)
    $currentSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $TrustedNode.Path).Hash
    if ([string]$currentVersionInfo.ProductVersion -cne $TrustedNode.ProductVersion -or
        $currentSha256 -cne $TrustedNode.Sha256) {
        throw "Verified Node.js executable identity changed during Lua projection: $($TrustedNode.Path)"
    }
}

function Invoke-MaterializerTrustedNode {
    param(
        [Parameter(Mandatory = $true)]$TrustedNode,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [AllowNull()][string]$StandardInput,
        [switch]$PipeStandardInput
    )

    Assert-MaterializerExecutionEnvironmentClean
    Assert-MaterializerTrustedNodeIdentity -TrustedNode $TrustedNode
    if ($PipeStandardInput) {
        $output = $StandardInput | & $TrustedNode.Path @ArgumentList 2>&1
    }
    else {
        $output = & $TrustedNode.Path @ArgumentList 2>&1
    }
    return [pscustomobject]@{
        Output = @($output)
        ExitCode = $LASTEXITCODE
    }
}

function Assert-MaterializerTrustedNodeRuntimeVersion {
    param([Parameter(Mandatory = $true)]$TrustedNode)

    $expectedRuntimeVersion = 'v' + [string]$TrustedNode.ProductVersion
    if ([string]$TrustedNode.RuntimeVersion -cne $expectedRuntimeVersion) {
        throw "Verified Node.js runtime version contract is inconsistent: product $($TrustedNode.ProductVersion), runtime $($TrustedNode.RuntimeVersion)"
    }
    $result = Invoke-MaterializerTrustedNode -TrustedNode $TrustedNode -ArgumentList @('--version')
    $runtimeVersion = (($result.Output | ForEach-Object { [string]$_ }) -join '').Trim()
    if ($result.ExitCode -ne 0 -or $runtimeVersion -cne $TrustedNode.RuntimeVersion) {
        throw "Verified Node.js runtime version mismatch: expected $($TrustedNode.RuntimeVersion), found '$runtimeVersion'"
    }
}

function Assert-MaterializerControlledNodeEnvironment {
    param([Parameter(Mandatory = $true)]$TrustedNode)

    $probe = @'
const forbiddenEnvironmentNames = [
    "NODE_OPTIONS", "NODE_PATH",
    "LUA_INIT", "LUA_INIT_5_3", "LUA_PATH", "LUA_PATH_5_3", "LUA_CPATH", "LUA_CPATH_5_3"
];
if (forbiddenEnvironmentNames.some((name) => Object.prototype.hasOwnProperty.call(process.env, name)) ||
    Object.keys(process.env).some((name) => name.toUpperCase().startsWith("LUA_"))) {
    throw new Error("controlled Node environment retained a Node or Lua injection variable");
}

try {
    require("huaguoshan-materializer-node-path-probe");
    throw new Error("NODE_PATH changed controlled module resolution");
} catch (error) {
    if (!error || error.code !== "MODULE_NOT_FOUND") throw error;
}
'@
    $result = Invoke-MaterializerTrustedNode -TrustedNode $TrustedNode -ArgumentList @('-') -StandardInput $probe -PipeStandardInput
    $outputText = ($result.Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($result.ExitCode -ne 0 -or $result.Output.Count -ne 0) {
        throw "Controlled Node environment probe failed: $outputText"
    }
}

$materializerPinnedFengariVersion = '0.1.0'
$materializerPinnedFengariSnapshot = '41ec8406e7a68140b8436c01df2bb294a02c6dc5111f463b8777f1ec3b7eef50'
$materializerPinnedFengariClosureSha256 = 'E8E88EFDB5BEFFE0F140BA72EDDCEC5E1B52D7788062A9FCF0E09F6988745AF4'

$materializerNodeModulesClosureHasher = @'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const root = path.resolve(process.argv[2]);
const rootStat = fs.lstatSync(root);
if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) {
    throw new Error("closure root must be a physical directory: " + root);
}

const hash = crypto.createHash("sha256");
const activeDirectories = new Set();
const realpath = fs.realpathSync.native || fs.realpathSync;
const writeRecord = (kind, logicalPath, payload) => {
    hash.update(kind, "utf8");
    hash.update("\0", "utf8");
    hash.update(logicalPath, "utf8");
    hash.update("\0", "utf8");
    if (payload) hash.update(payload);
    hash.update("\n", "utf8");
};

function walkDirectory(physicalPath, logicalPath) {
    const resolvedDirectory = realpath(physicalPath);
    const cycleKey = process.platform === "win32" ? resolvedDirectory.toLowerCase() : resolvedDirectory;
    if (activeDirectories.has(cycleKey)) {
        throw new Error("reparse cycle in dependency closure at " + logicalPath);
    }
    activeDirectories.add(cycleKey);
    writeRecord("D", logicalPath);
    const names = fs.readdirSync(resolvedDirectory).sort((left, right) =>
        left < right ? -1 : left > right ? 1 : 0
    );
    for (const name of names) {
        const childLogicalPath = logicalPath ? logicalPath + "/" + name : name;
        walk(path.join(resolvedDirectory, name), childLogicalPath);
    }
    activeDirectories.delete(cycleKey);
}

function walk(physicalPath, logicalPath) {
    const stat = fs.lstatSync(physicalPath);
    if (stat.isSymbolicLink()) {
        writeRecord("L", logicalPath);
        const resolvedTarget = realpath(physicalPath);
        const targetStat = fs.statSync(physicalPath);
        if (targetStat.isDirectory()) {
            walkDirectory(resolvedTarget, logicalPath);
            return;
        }
        if (targetStat.isFile()) {
            const content = fs.readFileSync(resolvedTarget);
            writeRecord("F", logicalPath, Buffer.concat([Buffer.from(String(content.length) + "\0"), content]));
            return;
        }
        throw new Error("unsupported reparse target in dependency closure: " + logicalPath);
    }
    if (stat.isDirectory()) {
        walkDirectory(physicalPath, logicalPath);
        return;
    }
    if (stat.isFile()) {
        const content = fs.readFileSync(physicalPath);
        writeRecord("F", logicalPath, Buffer.concat([Buffer.from(String(content.length) + "\0"), content]));
        return;
    }
    throw new Error("unsupported filesystem entry in dependency closure: " + logicalPath);
}

walkDirectory(root, "");
process.stdout.write(hash.digest("hex").toUpperCase());
'@

function Get-MaterializerNodeModulesClosureSha256 {
    param(
        [Parameter(Mandatory = $true)]$TrustedNode,
        [Parameter(Mandatory = $true)][string]$NodeModulesRoot
    )

    $result = Invoke-MaterializerTrustedNode -TrustedNode $TrustedNode -ArgumentList @('-', $NodeModulesRoot) -StandardInput $materializerNodeModulesClosureHasher -PipeStandardInput
    $hash = ($result.Output | ForEach-Object { [string]$_ }) -join ''
    if ($result.ExitCode -ne 0 -or $hash -cnotmatch '^[0-9A-F]{64}$') {
        throw ('Unable to hash the Fengari resolver closure at {0}: {1}' -f $NodeModulesRoot, $hash)
    }
    return $hash
}

function Resolve-MaterializerPinnedFengariCli {
    param([Parameter(Mandatory = $true)]$TrustedNode)

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is required to locate the pinned Fengari cache.'
    }
    $pnpmStore = Join-Path $env:LOCALAPPDATA 'pnpm\store'
    $expectedSuffix = '[\\/]fengari-node-cli[\\/]' + [regex]::Escape($materializerPinnedFengariVersion) +
        '[\\/]' + $materializerPinnedFengariSnapshot +
        '[\\/]node_modules[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$'
    $pinnedCandidates = @(
        Get-ChildItem -LiteralPath $pnpmStore -Recurse -File -Filter 'lua-cli.js' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match $expectedSuffix } |
            Sort-Object -Property FullName |
            Select-Object -ExpandProperty FullName
    )
    if ($pinnedCandidates.Count -ne 1) {
        throw "Expected exactly one pinned fengari-node-cli $materializerPinnedFengariVersion snapshot $materializerPinnedFengariSnapshot; found $($pinnedCandidates.Count)."
    }

    $cliPath = Get-MaterializerFinalFileSystemPath -Path $pinnedCandidates[0]
    $packageRoot = Split-Path -Parent (Split-Path -Parent $cliPath)
    $manifestPath = Join-Path $packageRoot 'package.json'
    try {
        $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    }
    catch {
        throw ('Unreadable fengari-node-cli manifest at {0}: {1}' -f $manifestPath, $_.Exception.Message)
    }
    if ([string]$manifest.name -cne 'fengari-node-cli' -or [string]$manifest.version -cne $materializerPinnedFengariVersion) {
        throw "Unexpected Fengari package identity at $manifestPath"
    }

    $nodeModulesRoot = Split-Path -Parent $packageRoot
    $closureSha256 = Get-MaterializerNodeModulesClosureSha256 -TrustedNode $TrustedNode -NodeModulesRoot $nodeModulesRoot
    if ($closureSha256 -cne $materializerPinnedFengariClosureSha256) {
        throw ('fengari-node-cli resolver closure integrity mismatch at {0}: expected {1}, found {2}' -f $nodeModulesRoot, $materializerPinnedFengariClosureSha256, $closureSha256)
    }
    return [pscustomobject]@{
        CliPath = $cliPath
        PackageRoot = $packageRoot
        NodeModulesRoot = $nodeModulesRoot
        CliSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $cliPath).Hash
        ClosureSha256 = $closureSha256
    }
}

function Assert-MaterializerPinnedFengariIdentity {
    param(
        [Parameter(Mandatory = $true)]$TrustedNode,
        [Parameter(Mandatory = $true)]$Fengari
    )

    $currentCliPath = Get-MaterializerFinalFileSystemPath -Path $Fengari.CliPath
    $currentCliSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Fengari.CliPath).Hash
    if ($currentCliPath -ine $Fengari.CliPath -or $currentCliSha256 -cne $Fengari.CliSha256) {
        throw "Verified Fengari CLI identity changed during Lua projection: $($Fengari.CliPath)"
    }
    $currentClosureSha256 = Get-MaterializerNodeModulesClosureSha256 -TrustedNode $TrustedNode -NodeModulesRoot $Fengari.NodeModulesRoot
    if ($currentClosureSha256 -cne $materializerPinnedFengariClosureSha256 -or
        $currentClosureSha256 -cne $Fengari.ClosureSha256) {
        throw "fengari-node-cli resolver closure identity changed during Lua projection: $($Fengari.NodeModulesRoot)"
    }
}

function Invoke-MaterializerLuaProjection {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectionScript,
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    $originalPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
    $originalPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
    $originalNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
    $originalNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
    $luaEnvironmentNames = @('LUA_INIT','LUA_INIT_5_3','LUA_PATH','LUA_PATH_5_3','LUA_CPATH','LUA_CPATH_5_3')
    $originalLuaEnvironment = @{}
    foreach ($name in $luaEnvironmentNames) {
        $originalLuaEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        Assert-MaterializerExecutionEnvironmentClean
        $trustedNode = Get-MaterializerTrustedNodeExecutable -PathValue $originalPath
        [Environment]::SetEnvironmentVariable('PATH', $trustedNode.Directory, 'Process')
        [Environment]::SetEnvironmentVariable('PATHEXT', '.EXE', 'Process')
        [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $null, 'Process')
        [Environment]::SetEnvironmentVariable('NODE_PATH', $null, 'Process')
        foreach ($name in $luaEnvironmentNames) {
            [Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }

        Assert-MaterializerTrustedNodeRuntimeVersion -TrustedNode $trustedNode
        Assert-MaterializerControlledNodeEnvironment -TrustedNode $trustedNode
        $fengari = Resolve-MaterializerPinnedFengariCli -TrustedNode $trustedNode
        Assert-MaterializerPinnedFengariIdentity -TrustedNode $trustedNode -Fengari $fengari
        return Invoke-MaterializerTrustedNode -TrustedNode $trustedNode -ArgumentList @($fengari.CliPath, '-E', $ProjectionScript, $ConfigPath)
    }
    finally {
        [Environment]::SetEnvironmentVariable('PATH', $originalPath, 'Process')
        [Environment]::SetEnvironmentVariable('PATHEXT', $originalPathExt, 'Process')
        [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $originalNodeOptions, 'Process')
        [Environment]::SetEnvironmentVariable('NODE_PATH', $originalNodePath, 'Process')
        foreach ($name in $originalLuaEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $originalLuaEnvironment[$name], 'Process')
        }
    }
}

function Read-LuaConfigProjection {
    param([string]$ConfigPath)
    $projectionScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\tests\export_config_binding_projection.lua'))
    if (-not (Test-Path -LiteralPath $projectionScript -PathType Leaf)) {
        throw 'Lua Config projection helper is unavailable'
    }
    $result = Invoke-MaterializerLuaProjection -ProjectionScript $projectionScript -ConfigPath $ConfigPath
    $outputText = $result.Output | Out-String
    if ($result.ExitCode -ne 0) {
        throw "Lua Config projection execution failed: $outputText"
    }
    try { $projection = ConvertFrom-StrictJson $outputText 'Lua Config projection' }
    catch { throw "Lua Config projection did not return valid JSON: $($_.Exception.Message)" }
    if ($null -eq $projection -or $projection -isnot [pscustomobject]) {
        throw 'Lua Config projection must return a JSON object'
    }
    return $projection
}

function Test-Y3ObjectEditorScriptShape {
    param([string]$Path)
    try { $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 }
    catch { return $false }
    foreach ($pattern in @(
        'def\s+create_unit\s*\(', 'def\s+create_ability\s*\(',
        'def\s+create_modifier\s*\(', 'def\s+create_projectile\s*\(',
        'add_argument\("-map"', 'add_argument\("-type"',
        'add_argument\("-create"', 'add_argument\("-edit"'
    )) {
        if ($content -notmatch $pattern) { return $false }
    }
    return $true
}

$manifestFullPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifest = Read-StrictJsonFile $manifestFullPath "manifest '$manifestFullPath'"
$errors = [System.Collections.Generic.List[string]]::new()

$gatePathNames = @('map_path','script_root','y3_obj_edit_script')
$gateBooleanNames = @(
    'y3editor_connected','map_logic_resources_verified','unit_ids_assigned','ability_ids_assigned',
    'modifier_ids_assigned','projectile_ids_assigned','model_ids_assigned','icon_ids_assigned',
    'effect_resources_assigned','encounter_runtime_bound','distance_scale_verified',
    'instance_map_contract_verified','authoritative_progression_validator_bound'
)
$gateNames = @($gatePathNames) + @($gateBooleanNames)
$gateNameSet = @{}
foreach ($name in $gateNames) { $gateNameSet[$name] = $true }
$executionGatesProperty = $manifest.PSObject.Properties['execution_gates']
$executionGates = if ($null -eq $executionGatesProperty) { $null } else { $executionGatesProperty.Value }
if ($null -eq $executionGates) {
    $errors.Add('execution_gates is required')
    $executionGates = [pscustomobject]@{}
}
else {
    foreach ($property in $executionGates.PSObject.Properties) {
        if (-not $gateNameSet.ContainsKey($property.Name)) {
            $errors.Add("execution_gates has unexpected property: $($property.Name)")
        }
    }
}
foreach ($name in $gateNames) {
    if ($null -eq $executionGates.PSObject.Properties[$name]) {
        $errors.Add("execution_gates missing required property: $name")
    }
}
foreach ($name in $gatePathNames) {
    $property = $executionGates.PSObject.Properties[$name]
    if ($null -eq $property) { continue }
    if ($property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        $errors.Add("execution gate must be a non-empty path string: $name")
    }
}
foreach ($name in $gateBooleanNames) {
    $property = $executionGates.PSObject.Properties[$name]
    if ($null -eq $property) { continue }
    if ($property.Value -isnot [bool]) {
        $errors.Add("execution gate must be boolean: $name")
    }
    elseif ($property.Value -ne $true) {
        $errors.Add("execution gate unresolved: $name")
    }
}

$editorGate = $executionGates.PSObject.Properties['y3_obj_edit_script']
if ($null -ne $editorGate -and $editorGate.Value -is [string] -and -not [string]::IsNullOrWhiteSpace($editorGate.Value)) {
    if ([IO.Path]::GetFileName($editorGate.Value) -ne 'y3_obj_edit.py') {
        $errors.Add('y3_obj_edit_script must name y3_obj_edit.py')
    }
    if ($editorGate.Value.Replace('\', '/') -notmatch '/skills/y3-obj-edit/scripts/y3_obj_edit\.py$') {
        $errors.Add('y3_obj_edit_script must point to skills/y3-obj-edit/scripts/y3_obj_edit.py')
    }
    if (-not (Test-Path -LiteralPath $editorGate.Value -PathType Leaf)) {
        $errors.Add("path must be an existing file: y3_obj_edit_script=$($editorGate.Value)")
    }
    elseif (-not (Test-Y3ObjectEditorScriptShape $editorGate.Value)) {
        $errors.Add('y3_obj_edit_script does not expose the required object editor command interface')
    }
}
foreach ($gateName in @('map_path', 'script_root')) {
    $property = $executionGates.PSObject.Properties[$gateName]
    if ($null -ne $property -and $property.Value -is [string] -and -not [string]::IsNullOrWhiteSpace($property.Value) -and
        -not (Test-Path -LiteralPath $property.Value -PathType Container)) {
        $errors.Add("path must be an existing directory: $gateName=$($property.Value)")
    }
}

$packageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $manifestFullPath))
$runtimePackageProperty = $manifest.PSObject.Properties['runtime_package']
$runtimePackage = if ($null -eq $runtimePackageProperty) { $null } else { $runtimePackageProperty.Value }
$binding = $null
$bindingFullPath = $null
$luaConfigFullPath = $null
$luaProjection = $null
$runtimeBooleanNames = @(
    'offline_runtime_complete','public_map_contract_complete','instance_map_contract_verified',
    'authoritative_progression_validator_bound','real_map_binding_verified','production_ids_ready'
)
if ($null -eq $runtimePackage -or $runtimePackage -isnot [pscustomobject]) {
    $errors.Add('runtime_package is required and must be an object')
}
else {
    foreach ($name in @('lua_root','map_logic_binding_path','runtime_contract_id') + $runtimeBooleanNames) {
        if ($null -eq $runtimePackage.PSObject.Properties[$name]) {
            $errors.Add("runtime_package missing required property: $name")
        }
    }
    $runtimeContractProperty = $runtimePackage.PSObject.Properties['runtime_contract_id']
    if ($null -ne $runtimeContractProperty -and -not (Test-NonEmptyTrimmedString $runtimeContractProperty.Value)) {
        $errors.Add('runtime_package runtime_contract_id must be a non-empty trimmed string')
    }
    foreach ($name in $runtimeBooleanNames) {
        $property = $runtimePackage.PSObject.Properties[$name]
        if ($null -eq $property) { continue }
        if ($property.Value -isnot [bool]) {
            $errors.Add("runtime_package production gate must be boolean: $name")
        }
        elseif ($property.Value -ne $true) {
            $errors.Add("runtime_package production gate unresolved: $name")
        }
    }

    $bindingPathProperty = $runtimePackage.PSObject.Properties['map_logic_binding_path']
    if ($null -ne $bindingPathProperty) {
        $bindingRelativePath = $bindingPathProperty.Value
        if (-not (Test-NonEmptyTrimmedString $bindingRelativePath)) {
            $errors.Add('runtime_package map_logic_binding_path must be a non-empty relative path string')
        }
        elseif ([IO.Path]::IsPathRooted($bindingRelativePath) -or $bindingRelativePath -match '^[A-Za-z]:') {
            $errors.Add('runtime_package map_logic_binding_path must be relative to the manifest package')
        }
        else {
            try {
                $bindingFullPath = Resolve-PackageLeafPath -PackageRoot $packageRoot -RelativePath $bindingRelativePath `
                    -Label 'runtime_package map_logic_binding_path' -ExpectedExtension '.json' -ExpectedFileType 'JSON' -ExpectedFileName ''
                $binding = Read-StrictJsonFile $bindingFullPath "map logic binding '$bindingFullPath'"
                if ($null -eq $binding -or $binding -isnot [pscustomobject]) {
                    throw 'map logic binding must contain a JSON object'
                }
            }
            catch {
                $errors.Add($_.Exception.Message)
                $binding = $null
            }
        }
    }

    $luaRootProperty = $runtimePackage.PSObject.Properties['lua_root']
    if ($null -ne $luaRootProperty) {
        $luaRootRelativePath = $luaRootProperty.Value
        if (-not (Test-NonEmptyTrimmedString $luaRootRelativePath)) {
            $errors.Add('runtime_package lua_root must be a non-empty relative path string')
        }
        elseif ([IO.Path]::IsPathRooted($luaRootRelativePath) -or $luaRootRelativePath -match '^[A-Za-z]:') {
            $errors.Add('runtime_package lua_root must be relative to the manifest package')
        }
        else {
            try {
                $configRelativePath = Join-Path $luaRootRelativePath 'huaguoshan_config.lua'
                $luaConfigFullPath = Resolve-PackageLeafPath -PackageRoot $packageRoot -RelativePath $configRelativePath `
                    -Label 'runtime_package Lua Config' -ExpectedExtension '.lua' -ExpectedFileType 'Lua' -ExpectedFileName 'huaguoshan_config.lua'
                $luaProjection = Read-LuaConfigProjection $luaConfigFullPath
            }
            catch {
                $errors.Add($_.Exception.Message)
                $luaProjection = $null
            }
        }
    }
}

if ($null -ne $binding) {
    $bindingPropertyNames = @(
        'package','schema_version','status','runtime_contract_id','source_layout_relpath',
        'real_map_binding_verified','production_ids_ready','instance_map_contract_verified',
        'instance_contract_role_schema','encounter_instance_map_states','return_points',
        'encounter_resource_bindings','instance_map_contracts','spawn_bindings','encounter_action_bindings'
    )
    [void](Assert-ExactProperties $binding $bindingPropertyNames 'map logic binding' $errors)
    if ($binding.package -ne 'huaguoshan-map-logic-binding') {
        $errors.Add('map logic binding package is invalid')
    }
    if (-not (Test-PositiveInteger $binding.schema_version) -or [decimal]$binding.schema_version -ne 5) {
        $errors.Add('map logic binding schema_version is invalid')
    }
    if ($binding.status -ne 'production-bound-public-map-contract-complete-instance-map-contract-verified') {
        $errors.Add('map logic binding status is invalid for materialization')
    }
    $expectedLayoutRelativePath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
        'ZG9jcy/lvZLmoaMv5Zyw5Zu+6K6+6K6hL3RlcnJhaW4vaHVhZ3Vvc2hhbi05Nng3Mi9sYXlvdXQuanNvbg=='
    ))
    if ($binding.source_layout_relpath -ne $expectedLayoutRelativePath) {
        $errors.Add('map logic binding source_layout_relpath is invalid')
    }
    foreach ($name in @(
        'instance_contract_role_schema','encounter_instance_map_states','return_points',
        'encounter_resource_bindings','instance_map_contracts','spawn_bindings','encounter_action_bindings'
    )) {
        $property = $binding.PSObject.Properties[$name]
        if ($null -ne $property -and -not (Test-JsonArray $property.Value)) {
            $errors.Add("map logic binding $name must be an array")
        }
    }
    $bindingArrays = @{}
    foreach ($name in @('return_points','encounter_resource_bindings','spawn_bindings','encounter_action_bindings')) {
        $property = $binding.PSObject.Properties[$name]
        $bindingArrays[$name] = @()
        if ($null -ne $property -and (Test-JsonArray $property.Value)) {
            $bindingArrays[$name] = @($property.Value)
        }
    }
    $returnPointBindings = @($bindingArrays['return_points'])
    $encounterResourceBindings = @($bindingArrays['encounter_resource_bindings'])
    $spawnBindings = @($bindingArrays['spawn_bindings'])
    $encounterActionBindings = @($bindingArrays['encounter_action_bindings'])
    Add-CanonicalPublicBossBindingErrors $spawnBindings $encounterResourceBindings 'map logic binding' $errors
    $bindingBooleanNames = @('real_map_binding_verified','production_ids_ready','instance_map_contract_verified')
    $bindingContractProperty = $binding.PSObject.Properties['runtime_contract_id']
    if ($null -ne $bindingContractProperty -and -not (Test-NonEmptyTrimmedString $bindingContractProperty.Value)) {
        $errors.Add('map logic binding runtime_contract_id must be a non-empty trimmed string')
    }
    foreach ($name in $bindingBooleanNames) {
        $property = $binding.PSObject.Properties[$name]
        if ($null -eq $property) { continue }
        if ($property.Value -isnot [bool]) {
            $errors.Add("map logic binding production gate must be boolean: $name")
        }
        elseif ($property.Value -ne $true) {
            $errors.Add("map logic binding production gate unresolved: $name")
        }
    }

    $manifestEncounterByKey = @{}
    foreach ($encounter in @($manifest.encounters)) {
        if ($encounter -isnot [pscustomobject] -or -not (Test-NonEmptyTrimmedString $encounter.record_key)) {
            $errors.Add('manifest encounter must be an object with a non-empty record_key')
            continue
        }
        if ($manifestEncounterByKey.ContainsKey([string]$encounter.record_key)) {
            $errors.Add("manifest has duplicate encounter key: $($encounter.record_key)")
        }
        else { $manifestEncounterByKey[[string]$encounter.record_key] = $encounter }
    }

    $oxEncounter = $manifestEncounterByKey['HG_E_OX_BATTLEFIELD']
    if ($null -eq $oxEncounter -or $oxEncounter.runtime_fields -isnot [pscustomobject]) {
        $errors.Add('HG_E_OX_BATTLEFIELD runtime_fields must be an object')
    }
    else {
        $oxRuntime = $oxEncounter.runtime_fields
        if ($oxRuntime.max_members -ne 4) {
            $errors.Add('HG_E_OX_BATTLEFIELD max_members must be 4')
        }
        if ($oxRuntime.failure_return_point -ne 'pt_hg_spawn') {
            $errors.Add('HG_E_OX_BATTLEFIELD failure_return_point must be pt_hg_spawn')
        }
        if ($oxRuntime.member_death_return_point -ne 'pt_hg_spawn') {
            $errors.Add('HG_E_OX_BATTLEFIELD member_death_return_point must be pt_hg_spawn')
        }
        if ($oxRuntime.member_death_reentry_policy -ne 'deny_until_cleanup_ack') {
            $errors.Add('HG_E_OX_BATTLEFIELD member_death_reentry_policy must be deny_until_cleanup_ack')
        }
        if ($oxRuntime.timeout_return_point -ne 'pt_hg_spawn') {
            $errors.Add('HG_E_OX_BATTLEFIELD timeout_return_point must be pt_hg_spawn')
        }
    }

    $reverseTideEncounter = $manifestEncounterByKey['HG_E_DRAGON_REVERSE_TIDE']
    if ($null -eq $reverseTideEncounter -or $reverseTideEncounter.runtime_fields -isnot [pscustomobject]) {
        $errors.Add('HG_E_DRAGON_REVERSE_TIDE runtime_fields must be an object')
    }
    else {
        $reverseTideRuntime = $reverseTideEncounter.runtime_fields
        if ($reverseTideRuntime.unlock_rule -ne 'level_at_least_38_and_difu_yanluo_hall_cleared') {
            $errors.Add('HG_E_DRAGON_REVERSE_TIDE unlock_rule must require Lv38 and Yanluo Hall completion')
        }
        if ($reverseTideRuntime.progression_key -ne 'DF_PROGRESS_YANLUO_HALL_CLEARED') {
            $errors.Add('HG_E_DRAGON_REVERSE_TIDE progression_key must be DF_PROGRESS_YANLUO_HALL_CLEARED')
        }
    }

    $unitByKey = @{}
    foreach ($unit in @($manifest.units)) {
        if ($unit -is [pscustomobject] -and (Test-NonEmptyTrimmedString $unit.record_key)) {
            $unitByKey[[string]$unit.record_key] = $unit
        }
    }

    $manifestResourcePairs = @{}
    $manifestResourceRoles = @{}
    $manifestResourcesByEncounterRole = @{}
    foreach ($encounter in @($manifest.encounters)) {
        if ($encounter -isnot [pscustomobject] -or -not (Test-NonEmptyTrimmedString $encounter.record_key)) { continue }
        $encounterKey = [string]$encounter.record_key
        $resourceKeysProperty = $encounter.PSObject.Properties['map_logic_resource_keys']
        $resourceKeys = @()
        if ($null -eq $resourceKeysProperty -or -not (Test-JsonArray $resourceKeysProperty.Value)) {
            $errors.Add("${encounterKey}: map_logic_resource_keys must be an array")
        }
        else { $resourceKeys = @($resourceKeysProperty.Value) }
        $rolesProperty = $encounter.PSObject.Properties['map_logic_resource_roles']
        $roles = if ($null -eq $rolesProperty) { $null } else { $rolesProperty.Value }
        if ($null -eq $roles -or $roles -isnot [pscustomobject]) {
            $errors.Add("${encounterKey}: map_logic_resource_roles must be an object")
            $roles = [pscustomobject]@{}
        }
        $localResourceKeys = @{}
        foreach ($resourceKey in $resourceKeys) {
            if (-not (Test-NonEmptyTrimmedString $resourceKey)) {
                $errors.Add("${encounterKey}: map logic resource key must be a non-empty trimmed string")
                continue
            }
            if ($localResourceKeys.ContainsKey($resourceKey)) {
                $errors.Add("${encounterKey}: duplicate map logic resource key $resourceKey")
                continue
            }
            $localResourceKeys[$resourceKey] = $true
            $pairKey = "$encounterKey|$resourceKey"
            $manifestResourcePairs[$pairKey] = $true
            $roleProperty = $roles.PSObject.Properties[$resourceKey]
            if ($null -eq $roleProperty -or -not (Test-NonEmptyTrimmedString $roleProperty.Value)) {
                $errors.Add("${encounterKey}: missing or invalid map logic resource role for $resourceKey")
            }
            else {
                $roleName = [string]$roleProperty.Value
                $manifestResourceRoles[$pairKey] = $roleName
                $encounterRoleKey = "$encounterKey|$roleName"
                if ($manifestResourcesByEncounterRole.ContainsKey($encounterRoleKey)) {
                    $manifestResourcesByEncounterRole[$encounterRoleKey] = @($manifestResourcesByEncounterRole[$encounterRoleKey]) + @($resourceKey)
                }
                else { $manifestResourcesByEncounterRole[$encounterRoleKey] = @($resourceKey) }
            }
        }
        foreach ($roleProperty in $roles.PSObject.Properties) {
            if (-not $localResourceKeys.ContainsKey($roleProperty.Name)) {
                $errors.Add("${encounterKey}: map logic resource role has no declared key $($roleProperty.Name)")
            }
        }
    }

    $encounterResourceRoleContracts = @{
        public_area = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('rectArea') }
        main_route_exclusion = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('path','rectArea') }
        major_elite_anchor = [pscustomobject]@{ source = 'boss_zone'; expected_types = @('boss_zone') }
        exit_path = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('path') }
        trace_carrier_anchor = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('point') }
        boss_arena = [pscustomobject]@{ source = 'boss_zone'; expected_types = @('boss_zone') }
        boss_pocket = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('rectArea') }
        interaction_anchor = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('point') }
        interaction_area = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('circleArea') }
        optional_elite_arena = [pscustomobject]@{ source = 'boss_zone'; expected_types = @('boss_zone') }
        optional_elite_pocket = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('rectArea') }
        future_east_sea_anchor = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('point') }
        required_safe_line = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('rectArea') }
        forbidden_vortex_core = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('circleArea') }
        entry_point = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('point') }
        failure_return = [pscustomobject]@{ source = 'logic_resource'; expected_types = @('point') }
    }
    $encounterResourceBindingFields = @('encounter_key','resource_key','source','expected_type','role')
    $encounterResourceBindingsProperty = $binding.PSObject.Properties['encounter_resource_bindings']
    $bindingResourcePairs = @{}
    foreach ($item in $encounterResourceBindings) {
        if ($item -isnot [pscustomobject]) {
            $errors.Add('map logic binding encounter resource binding must be an object')
            continue
        }
        [void](Assert-ExactProperties $item $encounterResourceBindingFields 'encounter resource binding' $errors)
        foreach ($field in $encounterResourceBindingFields) {
            if (-not (Test-NonEmptyTrimmedString $item.$field)) { $errors.Add("encounter resource binding has invalid $field") }
        }
        if (-not (Test-NonEmptyTrimmedString $item.encounter_key) -or -not (Test-NonEmptyTrimmedString $item.resource_key)) { continue }
        if (-not $manifestEncounterByKey.ContainsKey([string]$item.encounter_key)) {
            $errors.Add("encounter resource binding references unknown encounter: $($item.encounter_key)")
            continue
        }
        $pairKey = "$($item.encounter_key)|$($item.resource_key)"
        if ($bindingResourcePairs.ContainsKey($pairKey)) { $errors.Add("duplicate map binding resource pair: $pairKey") }
        else { $bindingResourcePairs[$pairKey] = $item }
        $roleContract = $encounterResourceRoleContracts[$item.role]
        if ($null -eq $roleContract) {
            $errors.Add("encounter resource binding has invalid role: $($item.role)")
        }
        elseif ($item.source -ne $roleContract.source -or $roleContract.expected_types -notcontains $item.expected_type) {
            $errors.Add("encounter resource binding role contract is invalid for $pairKey")
        }
        if (-not $manifestResourcePairs.ContainsKey($pairKey)) {
            $errors.Add("map logic binding declares resource absent from manifest: $pairKey")
        }
        elseif ($manifestResourceRoles.ContainsKey($pairKey) -and $item.role -ne $manifestResourceRoles[$pairKey]) {
            $errors.Add("manifest resource role differs from map logic binding for $pairKey")
        }
    }
    foreach ($pairKey in $manifestResourcePairs.Keys) {
        if (-not $bindingResourcePairs.ContainsKey($pairKey)) {
            $errors.Add("map logic binding omits manifest resource: $pairKey")
        }
    }

    $expectedReturnPoints = @{ spawn = 'pt_hg_spawn'; city = 'pt_hg_teleport_city'; hub = 'pt_hg_teleport_hub'; team = 'pt_hg_teleport_team' }
    if ($returnPointBindings.Count -ne $expectedReturnPoints.Count) {
        $errors.Add("map logic binding return_points must contain exactly $($expectedReturnPoints.Count) entries")
    }
    $returnRoles = @{}
    $returnResources = @{}
    foreach ($item in $returnPointBindings) {
        if ($item -isnot [pscustomobject]) {
            $errors.Add('return point must be an object')
            continue
        }
        [void](Assert-ExactProperties $item @('role','resource_key','source','expected_type') 'return point' $errors)
        foreach ($field in @('role','resource_key','source','expected_type')) {
            if (-not (Test-NonEmptyTrimmedString $item.$field)) { $errors.Add("return point has invalid $field") }
        }
        if (-not (Test-NonEmptyTrimmedString $item.role)) { continue }
        if (-not $expectedReturnPoints.ContainsKey($item.role)) { $errors.Add("return point has invalid role: $($item.role)") }
        if ($returnRoles.ContainsKey($item.role)) { $errors.Add("duplicate return point role: $($item.role)") }
        else { $returnRoles[$item.role] = $true }
        if (Test-NonEmptyTrimmedString $item.resource_key) {
            if ($returnResources.ContainsKey($item.resource_key)) { $errors.Add("duplicate return point resource_key: $($item.resource_key)") }
            else { $returnResources[$item.resource_key] = $true }
        }
        if ($item.source -ne 'logic_resource' -or $item.expected_type -ne 'point') {
            $errors.Add("return point source/type is invalid for role $($item.role)")
        }
        if ($expectedReturnPoints.ContainsKey($item.role) -and $item.resource_key -ne $expectedReturnPoints[$item.role]) {
            $errors.Add("return point resource is invalid for role $($item.role)")
        }
    }
    foreach ($role in $expectedReturnPoints.Keys) {
        if (-not $returnRoles.ContainsKey($role)) { $errors.Add("map logic binding return point is missing for role $role") }
    }

    $expectedSpawnPairs = @{}
    foreach ($encounter in @($manifest.encounters)) {
        if ($encounter -isnot [pscustomobject] -or $encounter.combat_scope -ne 'public') { continue }
        $encounterKey = [string]$encounter.record_key
        $anchors = @()
        $units = @()
        $anchorProperty = $encounter.runtime_fields.PSObject.Properties['spawn_anchors']
        if ($null -ne $anchorProperty) {
            if (-not (Test-JsonArray $anchorProperty.Value)) { $errors.Add("${encounterKey}: spawn_anchors must be an array") }
            else { $anchors = @($anchorProperty.Value) }
            $spawnUnitsProperty = $encounter.PSObject.Properties['spawn_unit_keys']
            if ($null -eq $spawnUnitsProperty -or -not (Test-JsonArray $spawnUnitsProperty.Value)) {
                $errors.Add("${encounterKey}: spawn_unit_keys must be an array when spawn_anchors are declared")
            }
            else { $units = @($spawnUnitsProperty.Value) }
        }
        elseif ($encounter.encounter_type -in @('public_trace','public_elite')) {
            $anchorRole = if ($encounter.encounter_type -eq 'public_trace') { 'trace_carrier_anchor' } else { 'optional_elite_arena' }
            $anchors = @($manifestResourcesByEncounterRole["$encounterKey|$anchorRole"])
            if ($anchors.Count -ne 1) { $errors.Add("${encounterKey}: $anchorRole must resolve to exactly one spawn anchor") }
            $spawnUnitsProperty = $encounter.PSObject.Properties['spawn_unit_keys']
            if ($null -eq $spawnUnitsProperty -or -not (Test-JsonArray $spawnUnitsProperty.Value)) { $errors.Add("${encounterKey}: spawn_unit_keys must be an array") }
            else { $units = @($spawnUnitsProperty.Value) }
            if ($units.Count -ne 1) { $errors.Add("${encounterKey}: $($encounter.encounter_type) must declare exactly one spawn unit") }
        }
        elseif ($encounter.encounter_type -eq 'public_boss') {
            $anchors = @($manifestResourcesByEncounterRole["$encounterKey|boss_arena"])
            if ($anchors.Count -ne 1) { $errors.Add("${encounterKey}: boss_arena must resolve to exactly one resource") }
            if (-not (Test-NonEmptyTrimmedString $encounter.boss_unit_key)) { $errors.Add("${encounterKey}: public boss must declare boss_unit_key") }
            else {
                $bossUnitKey = [string]$encounter.boss_unit_key
                $units = @($bossUnitKey)
                if (-not $canonicalPublicBossByEncounter.ContainsKey($encounterKey)) {
                    $errors.Add("manifest ${encounterKey}: public boss has no canonical identity")
                }
                else {
                    $canonicalBoss = $canonicalPublicBossByEncounter[$encounterKey]
                    if ($bossUnitKey -cne $canonicalBoss.UnitKey) {
                        $errors.Add("manifest ${encounterKey}: canonical public boss tuple must be $($canonicalBoss.UnitKey) -> $($canonicalBoss.ArenaKey)")
                    }
                    if ($anchors.Count -eq 1 -and $anchors[0] -cne $canonicalBoss.ArenaKey) {
                        $errors.Add("${encounterKey}: public boss spawn anchor must match encounter boss_arena $($canonicalBoss.ArenaKey)")
                    }
                }
            }
        }
        else { $errors.Add("${encounterKey}: unsupported public encounter spawn projection $($encounter.encounter_type)") }
        if ($anchors.Count -ne $units.Count) { $errors.Add("${encounterKey}: spawn anchors and unit keys must have matching counts") }
        for ($index = 0; $index -lt [Math]::Min($anchors.Count, $units.Count); $index++) {
            $anchorKey = $anchors[$index]
            $unitKey = $units[$index]
            if (-not (Test-NonEmptyTrimmedString $anchorKey) -or -not (Test-NonEmptyTrimmedString $unitKey)) {
                $errors.Add("${encounterKey}: spawn projection has an invalid anchor or unit key")
                continue
            }
            $pairKey = "$encounterKey|$anchorKey|$unitKey"
            if ($expectedSpawnPairs.ContainsKey($pairKey)) { $errors.Add("duplicate expected spawn binding: $pairKey") }
            else { $expectedSpawnPairs[$pairKey] = $true }
        }
    }
    if ($spawnBindings.Count -ne $expectedSpawnPairs.Count) {
        $errors.Add("map logic binding spawn_bindings must contain exactly $($expectedSpawnPairs.Count) entries")
    }
    $spawnPairs = @{}
    $spawnAnchorOwners = @{}
    foreach ($item in $spawnBindings) {
        if ($item -isnot [pscustomobject]) {
            $errors.Add('spawn binding must be an object')
            continue
        }
        [void](Assert-ExactProperties $item @('encounter_key','anchor_key','unit_key') 'spawn binding' $errors)
        foreach ($field in @('encounter_key','anchor_key','unit_key')) {
            if (-not (Test-NonEmptyTrimmedString $item.$field)) { $errors.Add("spawn binding has invalid $field") }
        }
        if (-not (Test-NonEmptyTrimmedString $item.encounter_key) -or -not (Test-NonEmptyTrimmedString $item.anchor_key) -or
            -not (Test-NonEmptyTrimmedString $item.unit_key)) { continue }
        $encounter = $manifestEncounterByKey[$item.encounter_key]
        if ($null -eq $encounter) { $errors.Add("spawn binding references unknown encounter: $($item.encounter_key)"); continue }
        if (-not $unitByKey.ContainsKey([string]$item.unit_key)) { $errors.Add("spawn binding references unknown unit: $($item.unit_key)") }
        $pairKey = "$($item.encounter_key)|$($item.anchor_key)|$($item.unit_key)"
        if ($spawnPairs.ContainsKey($pairKey)) { $errors.Add("duplicate spawn binding: $pairKey") }
        else { $spawnPairs[$pairKey] = $true }
        $anchorOwnerKey = "$($item.encounter_key)|$($item.anchor_key)"
        if ($spawnAnchorOwners.ContainsKey($anchorOwnerKey)) { $errors.Add("spawn anchor is bound more than once for encounter: $anchorOwnerKey") }
        else { $spawnAnchorOwners[$anchorOwnerKey] = $item.unit_key }
        if ($publicBossArenaByUnit.ContainsKey([string]$item.unit_key) -and
            $item.anchor_key -cne $publicBossArenaByUnit[[string]$item.unit_key]) {
            $errors.Add("$($item.encounter_key): public boss spawn anchor must match encounter boss_arena $($publicBossArenaByUnit[[string]$item.unit_key])")
        }
        if (-not $expectedSpawnPairs.ContainsKey($pairKey)) { $errors.Add("spawn binding is not declared by encounter projection: $pairKey") }
    }
    foreach ($pairKey in $expectedSpawnPairs.Keys) {
        if (-not $spawnPairs.ContainsKey($pairKey)) { $errors.Add("spawn binding omits encounter projection: $pairKey") }
    }

    $expectedActionEncounters = @{}
    foreach ($encounter in @($manifest.encounters)) {
        if ($encounter -isnot [pscustomobject]) { continue }
        $actionProperty = $encounter.runtime_fields.PSObject.Properties['encounter_action_key']
        if ($null -eq $actionProperty) { continue }
        if (-not (Test-NonEmptyTrimmedString $actionProperty.Value)) { $errors.Add("$($encounter.record_key): encounter_action_key must be a non-empty trimmed string") }
        else { $expectedActionEncounters[$encounter.record_key] = $encounter }
    }
    if ($encounterActionBindings.Count -ne $expectedActionEncounters.Count) {
        $errors.Add("map logic binding encounter_action_bindings must contain exactly $($expectedActionEncounters.Count) entries")
    }
    $actionPairs = @{}
    $actionKeyOwners = @{}
    $baseActionFields = @('encounter_key','action_key','area_key','anchor_key','radius_cells','max_concurrent','read_seconds')
    foreach ($item in $encounterActionBindings) {
        if ($item -isnot [pscustomobject]) {
            $errors.Add('encounter action binding must be an object')
            continue
        }
        $encounterKey = $item.encounter_key
        $encounter = if (Test-NonEmptyTrimmedString $encounterKey) { $manifestEncounterByKey[$encounterKey] } else { $null }
        $actionFields = @($baseActionFields)
        if ($null -ne $encounter -and $encounter.encounter_type -eq 'public_trace') {
            $actionFields += 'postlude_seconds'
        }
        elseif ($null -ne $encounter -and $encounter.encounter_type -eq 'public_boss') {
            $actionFields += 'window_seconds'
            if ($encounter.runtime_fields.safe_line_required -eq $true) { $actionFields += @('required_inside_area_key','required_outside_area_key') }
        }
        [void](Assert-ExactProperties $item $actionFields 'encounter action binding' $errors)
        foreach ($field in @('encounter_key','action_key','area_key','anchor_key')) {
            if (-not (Test-NonEmptyTrimmedString $item.$field)) { $errors.Add("encounter action binding has invalid $field") }
        }
        if (-not (Test-PositiveInteger $item.radius_cells)) { $errors.Add("${encounterKey}: action radius_cells must be a positive integer") }
        if (-not (Test-PositiveInteger $item.max_concurrent)) { $errors.Add("${encounterKey}: action max_concurrent must be a positive integer") }
        if (-not (Test-PositiveNumber $item.read_seconds)) { $errors.Add("${encounterKey}: action read_seconds must be positive") }
        foreach ($field in @('window_seconds','postlude_seconds')) {
            $property = $item.PSObject.Properties[$field]
            if ($null -ne $property -and -not (Test-PositiveNumber $property.Value)) { $errors.Add("${encounterKey}: action $field must be positive") }
        }
        if ($null -eq $encounter) { $errors.Add("action binding references unknown encounter: $encounterKey"); continue }
        if (-not $expectedActionEncounters.ContainsKey($encounterKey)) { $errors.Add("${encounterKey}: action binding is not declared by encounter") }
        if ($actionPairs.ContainsKey($encounterKey)) { $errors.Add("duplicate encounter action binding for $encounterKey") }
        else { $actionPairs[$encounterKey] = $item }
        if (Test-NonEmptyTrimmedString $item.action_key) {
            if ($actionKeyOwners.ContainsKey($item.action_key)) { $errors.Add("duplicate encounter action key: $($item.action_key)") }
            else { $actionKeyOwners[$item.action_key] = $encounterKey }
        }
        $runtime = $encounter.runtime_fields
        if ($runtime.encounter_action_key -ne $item.action_key) { $errors.Add("${encounterKey}: action binding key differs from encounter") }
        if ($runtime.interaction_radius_cells -ne $item.radius_cells -or $runtime.max_concurrent_actors -ne $item.max_concurrent) {
            $errors.Add("${encounterKey}: action binding radius or concurrency differs from encounter")
        }
        if ($encounter.encounter_type -eq 'public_trace' -and $item.postlude_seconds -ne $runtime.local_environment_seconds) {
            $errors.Add("${encounterKey}: action postlude_seconds differs from encounter local environment")
        }
        $areaBinding = $bindingResourcePairs["$encounterKey|$($item.area_key)"]
        $anchorBinding = $bindingResourcePairs["$encounterKey|$($item.anchor_key)"]
        if ($null -eq $areaBinding -or $null -eq $anchorBinding) {
            $errors.Add("${encounterKey}: action resources must be explicitly bound")
        }
        else {
            if ($areaBinding.role -ne 'interaction_area') { $errors.Add("${encounterKey}: action area must use interaction_area role") }
            if ($anchorBinding.role -ne 'interaction_anchor') { $errors.Add("${encounterKey}: action anchor must use interaction_anchor role") }
        }
        if ($encounter.runtime_fields.safe_line_required -eq $true) {
            $insideResources = @($manifestResourcesByEncounterRole["$encounterKey|required_safe_line"])
            $outsideResources = @($manifestResourcesByEncounterRole["$encounterKey|forbidden_vortex_core"])
            if ($insideResources.Count -ne 1 -or $item.required_inside_area_key -ne $insideResources[0]) {
                $errors.Add("${encounterKey}: action must use the declared required_safe_line resource")
            }
            if ($outsideResources.Count -ne 1 -or $item.required_outside_area_key -ne $outsideResources[0]) {
                $errors.Add("${encounterKey}: action must use the declared forbidden_vortex_core resource")
            }
            $insideBinding = $bindingResourcePairs["$encounterKey|$($item.required_inside_area_key)"]
            $outsideBinding = $bindingResourcePairs["$encounterKey|$($item.required_outside_area_key)"]
            if ($null -eq $insideBinding -or $insideBinding.role -ne 'required_safe_line') { $errors.Add("${encounterKey}: required_inside_area_key must use required_safe_line role") }
            if ($null -eq $outsideBinding -or $outsideBinding.role -ne 'forbidden_vortex_core') { $errors.Add("${encounterKey}: required_outside_area_key must use forbidden_vortex_core role") }
        }
    }
    foreach ($encounterKey in $expectedActionEncounters.Keys) {
        if (-not $actionPairs.ContainsKey($encounterKey)) { $errors.Add("${encounterKey}: encounter action binding is missing") }
    }

    if ($null -ne $runtimePackage -and $runtimePackage -is [pscustomobject]) {
        $runtimeContractProperty = $runtimePackage.PSObject.Properties['runtime_contract_id']
        if ($null -ne $runtimeContractProperty -and $null -ne $bindingContractProperty -and
            (Test-NonEmptyTrimmedString $runtimeContractProperty.Value) -and (Test-NonEmptyTrimmedString $bindingContractProperty.Value) -and
            -not [string]::Equals($runtimeContractProperty.Value, $bindingContractProperty.Value, [StringComparison]::Ordinal)) {
            $errors.Add('map logic binding runtime contract does not match manifest runtime package')
        }
        foreach ($name in $bindingBooleanNames) {
            $runtimeProperty = $runtimePackage.PSObject.Properties[$name]
            $bindingProperty = $binding.PSObject.Properties[$name]
            if ($null -ne $runtimeProperty -and $null -ne $bindingProperty -and
                $runtimeProperty.Value -is [bool] -and $bindingProperty.Value -is [bool] -and
                $runtimeProperty.Value -ne $bindingProperty.Value) {
                $errors.Add("map logic binding $name gate does not match manifest runtime package")
            }
        }
        foreach ($name in @('instance_map_contract_verified','authoritative_progression_validator_bound')) {
            $runtimeProperty = $runtimePackage.PSObject.Properties[$name]
            $executionProperty = $executionGates.PSObject.Properties[$name]
            if ($null -ne $runtimeProperty -and $null -ne $executionProperty -and
                $runtimeProperty.Value -is [bool] -and $executionProperty.Value -is [bool] -and
                $runtimeProperty.Value -ne $executionProperty.Value) {
                $errors.Add("runtime_package $name gate does not match execution_gates")
            }
        }
    }

    $instanceValidationErrorStart = $errors.Count
    $instanceContractFields = @('contract_key','encounter_keys','state','layer','slot_count','slots')
    $instanceStateFields = @('encounter_key','contract_key','state','slot_count')
    $instanceRoleSchemaFields = @('contract_key','layer','slot_count','roles')
    $instanceRoleSchemaRoleFields = @('role','expected_type')
    $expectedInstanceContractByEncounter = @{
        HG_E_DRAGON_OLD_TIDE = 'HG_I_DRAGON_FOUR_SEAS'
        HG_E_DRAGON_REVERSE_TIDE = 'HG_I_DRAGON_FOUR_SEAS'
        HG_E_OX_BATTLEFIELD = 'HG_I_OX_BATTLEFIELD'
    }
    $expectedInstanceEncounterKeysByContract = @{
        HG_I_DRAGON_FOUR_SEAS = @('HG_E_DRAGON_OLD_TIDE','HG_E_DRAGON_REVERSE_TIDE')
        HG_I_OX_BATTLEFIELD = @('HG_E_OX_BATTLEFIELD')
    }
    $expectedInstanceRoleSchemaByContract = @{
        HG_I_DRAGON_FOUR_SEAS = [pscustomobject]@{
            layer = 'four_seas'; slot_count = 4
            roles = @{ boss_arena = 'rectArea'; return_exit = 'point'; slot_bounds = 'rectArea'; slot_spawn = 'point' }
        }
        HG_I_OX_BATTLEFIELD = [pscustomobject]@{
            layer = 'dream_realm'; slot_count = 1
            roles = @{ boss_arena = 'rectArea'; member_spawn = 'point'; raid_bounds = 'rectArea'; return_exit = 'point' }
        }
    }
    $instanceRoleSchemas = @()
    $instanceRoleSchemaProperty = $binding.PSObject.Properties['instance_contract_role_schema']
    if ($null -eq $instanceRoleSchemaProperty -or -not (Test-JsonArray $instanceRoleSchemaProperty.Value)) {
        $errors.Add('map logic binding instance_contract_role_schema must be an array')
    }
    else { $instanceRoleSchemas = @($instanceRoleSchemaProperty.Value) }
    if ($instanceRoleSchemas.Count -eq 0) { $errors.Add('map logic binding instance_contract_role_schema must not be empty') }
    $instanceRoleSchemaByContract = @{}
    foreach ($schema in $instanceRoleSchemas) {
        if ($schema -isnot [pscustomobject]) {
            $errors.Add('instance contract role schema must be an object')
            continue
        }
        [void](Assert-ExactProperties $schema $instanceRoleSchemaFields 'instance contract role schema' $errors)
        $contractKey = $schema.contract_key
        if (-not (Test-NonEmptyTrimmedString $contractKey)) {
            $errors.Add('instance contract role schema has invalid contract_key')
            continue
        }
        if ($instanceRoleSchemaByContract.ContainsKey($contractKey)) {
            $errors.Add("duplicate instance contract role schema: $contractKey")
            continue
        }
        if (-not $expectedInstanceEncounterKeysByContract.ContainsKey($contractKey)) {
            $errors.Add("instance contract role schema has unknown contract key: $contractKey")
        }
        $expectedSchema = $expectedInstanceRoleSchemaByContract[$contractKey]
        $valid = $true
        if (-not (Test-NonEmptyTrimmedString $schema.layer)) {
            $errors.Add("instance contract role schema has invalid layer: $contractKey")
            $valid = $false
        }
        elseif ($null -ne $expectedSchema -and $schema.layer -ne $expectedSchema.layer) {
            $errors.Add("instance contract role schema layer is not canonical: $contractKey")
            $valid = $false
        }
        if (-not (Test-PositiveInteger $schema.slot_count)) {
            $errors.Add("instance contract role schema slot_count must be a positive integer: $contractKey")
            $valid = $false
        }
        elseif ($null -ne $expectedSchema -and $schema.slot_count -ne $expectedSchema.slot_count) {
            $errors.Add("instance contract role schema slot_count is not canonical: $contractKey")
            $valid = $false
        }
        $rolesProperty = $schema.PSObject.Properties['roles']
        $rolesValue = if ($null -eq $rolesProperty) { $null } else { $rolesProperty.Value }
        if (-not (Test-JsonArray $rolesValue) -or @($rolesValue).Count -eq 0) {
            $errors.Add("instance contract role schema roles must be a non-empty array: $contractKey")
            $valid = $false
        }
        $roleTypes = @{}
        foreach ($role in @($rolesValue)) {
            if ($role -isnot [pscustomobject]) {
                $errors.Add("instance contract role schema role must be an object: $contractKey")
                $valid = $false
                continue
            }
            if (-not (Assert-ExactProperties $role $instanceRoleSchemaRoleFields "instance contract role schema role for $contractKey" $errors)) {
                $valid = $false
            }
            if (-not (Test-NonEmptyTrimmedString $role.role) -or $roleTypes.ContainsKey([string]$role.role)) {
                $errors.Add("instance contract role schema role is invalid or duplicate: $contractKey")
                $valid = $false
                continue
            }
            if ($null -ne $expectedSchema -and -not $expectedSchema.roles.ContainsKey([string]$role.role)) {
                $errors.Add("instance contract role schema role is not canonical: ${contractKey}:$($role.role)")
                $valid = $false
                continue
            }
            if ($role.expected_type -notin @('point','rectArea')) {
                $errors.Add("instance contract role schema expected_type is invalid: ${contractKey}:$($role.role)")
                $valid = $false
                continue
            }
            if ($null -ne $expectedSchema -and $role.expected_type -ne $expectedSchema.roles[[string]$role.role]) {
                $errors.Add("instance contract role schema expected_type is not canonical: ${contractKey}:$($role.role)")
                $valid = $false
                continue
            }
            $roleTypes[[string]$role.role] = $role.expected_type
        }
        if ($null -ne $expectedSchema) {
            if ($roleTypes.Count -ne $expectedSchema.roles.Count) {
                $errors.Add("instance contract role schema roles must exactly match canonical roles: $contractKey")
                $valid = $false
            }
            foreach ($expectedRole in $expectedSchema.roles.Keys) {
                if (-not $roleTypes.ContainsKey([string]$expectedRole)) {
                    $errors.Add("instance contract role schema is missing canonical role: ${contractKey}:$expectedRole")
                    $valid = $false
                }
            }
        }
        if ($valid) {
            $instanceRoleSchemaByContract[$contractKey] = [pscustomobject]@{
                layer = $schema.layer; slot_count = $schema.slot_count; roles = $roleTypes
            }
        }
    }
    foreach ($expectedContractKey in $expectedInstanceEncounterKeysByContract.Keys) {
        if (-not $instanceRoleSchemaByContract.ContainsKey($expectedContractKey)) {
            $errors.Add("map logic binding missing instance contract role schema: $expectedContractKey")
        }
    }
    $instanceContracts = @()
    $instanceContractsProperty = $binding.PSObject.Properties['instance_map_contracts']
    if ($null -eq $instanceContractsProperty -or -not (Test-JsonArray $instanceContractsProperty.Value)) {
        $errors.Add('map logic binding instance_map_contracts must be an array')
    }
    else { $instanceContracts = @($instanceContractsProperty.Value) }
    if ($instanceContracts.Count -eq 0) { $errors.Add('map logic binding instance_map_contracts must not be empty') }

    $contractByKey = @{}
    $contractKeyByEncounter = @{}
    $stableObjectIdOwners = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $resourceOwners = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($contract in $instanceContracts) {
        if ($contract -isnot [pscustomobject]) {
            $errors.Add('map logic binding instance map contract must be an object')
            continue
        }
        [void](Assert-ExactProperties $contract $instanceContractFields 'instance map contract' $errors)
        $contractKey = $contract.contract_key
        if (-not (Test-NonEmptyTrimmedString $contractKey)) {
            $errors.Add('map logic binding instance map contract has invalid contract_key')
            continue
        }
        if ($contractByKey.ContainsKey($contractKey)) {
            $errors.Add("map logic binding has duplicate instance map contract key: $contractKey")
            continue
        }
        $contractByKey[$contractKey] = $contract
        if (-not $expectedInstanceEncounterKeysByContract.ContainsKey($contractKey)) {
            $errors.Add("map logic binding has unknown instance map contract key: $contractKey")
        }
        if ($contract.state -ne 'verified') {
            $errors.Add("map logic binding instance map contract must be verified: $contractKey (state=$($contract.state))")
        }

        $encounterKeysProperty = $contract.PSObject.Properties['encounter_keys']
        $encounterKeysValue = $null
        if ($null -ne $encounterKeysProperty) { $encounterKeysValue = $encounterKeysProperty.Value }
        $encounterKeys = @()
        if (-not (Test-JsonArray $encounterKeysValue)) {
            $errors.Add("instance map contract encounter_keys must be an array: $contractKey")
        }
        else { $encounterKeys = @($encounterKeysValue) }
        if ($encounterKeys.Count -eq 0) { $errors.Add("instance map contract encounter_keys must not be empty: $contractKey") }
        $localEncounterKeys = @{}
        foreach ($encounterKey in $encounterKeys) {
            if (-not (Test-NonEmptyTrimmedString $encounterKey)) {
                $errors.Add("instance map contract has invalid encounter key: $contractKey")
                continue
            }
            if ($localEncounterKeys.ContainsKey($encounterKey)) {
                $errors.Add("instance map contract has duplicate encounter key: ${contractKey}:$encounterKey")
                continue
            }
            $localEncounterKeys[$encounterKey] = $true
            if ($contractKeyByEncounter.ContainsKey($encounterKey)) {
                $errors.Add("instance encounter key is assigned to multiple contracts: $encounterKey")
            }
            else { $contractKeyByEncounter[$encounterKey] = $contractKey }
            $encounter = $manifestEncounterByKey[$encounterKey]
            if ($null -eq $encounter) {
                $errors.Add("instance map contract references unknown encounter: $encounterKey")
            }
            elseif ($encounter.combat_scope -notin @('solo_instance','team_instance')) {
                $errors.Add("instance map contract references non-instance encounter: $encounterKey")
            }
            if ($expectedInstanceContractByEncounter.ContainsKey($encounterKey) -and
                $expectedInstanceContractByEncounter[$encounterKey] -ne $contractKey) {
                $errors.Add("canonical instance contract mapping is invalid: $encounterKey -> $contractKey")
            }
        }
        if ($expectedInstanceEncounterKeysByContract.ContainsKey($contractKey)) {
            foreach ($expectedEncounterKey in $expectedInstanceEncounterKeysByContract[$contractKey]) {
                if (-not $localEncounterKeys.ContainsKey($expectedEncounterKey)) {
                    $errors.Add("instance map contract $contractKey is missing encounter $expectedEncounterKey")
                }
            }
        }

        if (-not (Test-InstanceContractShape $contract $contractKey $errors $resourceOwners $instanceRoleSchemaByContract)) { continue }
        foreach ($slot in @($contract.slots)) {
            foreach ($role in @($slot.roles)) {
                if (-not (Test-StableObjectId $role.stable_object_id)) {
                    $errors.Add("verified instance role requires stable_object_id: $contractKey")
                }
                else {
                    $stableId = $role.stable_object_id
                    $stableKey = $stableId.GetType().FullName + ':' + [string]$stableId
                    $owner = "${contractKey}:$($slot.slot_id):$($role.role)"
                    if ($stableObjectIdOwners.ContainsKey($stableKey)) {
                        $errors.Add("duplicate global stable_object_id $stableId`: $owner and $($stableObjectIdOwners[$stableKey])")
                    }
                    else { $stableObjectIdOwners[$stableKey] = $owner }
                }
            }
        }
    }
    foreach ($expectedContractKey in $expectedInstanceEncounterKeysByContract.Keys) {
        if (-not $contractByKey.ContainsKey($expectedContractKey)) {
            $errors.Add("map logic binding missing canonical instance map contract: $expectedContractKey")
        }
    }

    $projectedStates = @{}
    $stateProjectionProperty = $binding.PSObject.Properties['encounter_instance_map_states']
    $stateProjections = @()
    if ($null -eq $stateProjectionProperty -or -not (Test-JsonArray $stateProjectionProperty.Value)) {
        $errors.Add('map logic binding encounter_instance_map_states must be an array')
    }
    else { $stateProjections = @($stateProjectionProperty.Value) }
    foreach ($projection in $stateProjections) {
        if ($projection -isnot [pscustomobject]) {
            $errors.Add('map logic binding encounter instance map state must be an object')
            continue
        }
        [void](Assert-ExactProperties $projection $instanceStateFields 'encounter instance map state' $errors)
        $encounterKey = $projection.encounter_key
        $contractKey = $projection.contract_key
        if (-not (Test-NonEmptyTrimmedString $encounterKey) -or $projectedStates.ContainsKey([string]$encounterKey)) {
            $errors.Add("map logic binding has invalid or duplicate encounter instance map state: $encounterKey")
            continue
        }
        $projectedStates[$encounterKey] = $projection
        if (-not (Test-NonEmptyTrimmedString $contractKey) -or -not $contractByKey.ContainsKey([string]$contractKey)) {
            $errors.Add("map logic binding encounter instance map state references unknown contract: $contractKey")
        }
        if ($projection.state -ne 'verified') {
            $errors.Add("map logic binding encounter instance map state must be verified: $encounterKey (state=$($projection.state))")
        }
        if (-not (Test-PositiveInteger $projection.slot_count)) {
            $errors.Add("map logic binding encounter instance map state slot_count must be a positive integer: $encounterKey")
        }
        $encounter = $manifestEncounterByKey[$encounterKey]
        if ($null -eq $encounter) {
            $errors.Add("map logic binding encounter instance map state references unknown encounter: $encounterKey")
        }
        elseif ($encounter.combat_scope -notin @('solo_instance','team_instance')) {
            $errors.Add("map logic binding encounter instance map state references non-instance encounter: $encounterKey")
        }
        if ($expectedInstanceContractByEncounter.ContainsKey($encounterKey) -and
            $expectedInstanceContractByEncounter[$encounterKey] -ne $contractKey) {
            $errors.Add("encounter instance map state has invalid contract mapping: $encounterKey -> $contractKey")
        }
    }
    foreach ($encounterKey in $contractKeyByEncounter.Keys) {
        $contractKey = $contractKeyByEncounter[$encounterKey]
        $projection = $projectedStates[$encounterKey]
        if ($null -eq $projection) {
            $errors.Add("map logic binding missing encounter instance map state: $encounterKey")
        }
        else {
            if ($projection.contract_key -ne $contractKey) {
                $errors.Add("map logic binding encounter contract mapping contradicts contract: $encounterKey")
            }
            if ($contractByKey.ContainsKey($contractKey) -and $projection.state -ne $contractByKey[$contractKey].state) {
                $errors.Add("map logic binding instance map state contradicts contract: $encounterKey")
            }
            if ($contractByKey.ContainsKey($contractKey) -and $projection.slot_count -ne $contractByKey[$contractKey].slot_count) {
                $errors.Add("map logic binding encounter instance map state slot_count contradicts contract: $encounterKey")
            }
        }
    }
    foreach ($encounterKey in $projectedStates.Keys) {
        if (-not $contractKeyByEncounter.ContainsKey($encounterKey) -or
            $contractKeyByEncounter[$encounterKey] -ne $projectedStates[$encounterKey].contract_key) {
            $errors.Add("map logic binding encounter instance map state has no matching contract mapping: $encounterKey")
        }
    }

    $manifestInstanceStates = @{}
    foreach ($encounter in @($manifest.encounters)) {
        if ($encounter -isnot [pscustomobject] -or $encounter.combat_scope -notin @('solo_instance','team_instance')) { continue }
        $encounterKey = [string]$encounter.record_key
        if ([string]::IsNullOrWhiteSpace($encounterKey) -or $manifestInstanceStates.ContainsKey($encounterKey)) {
            $errors.Add("manifest has blank or duplicate instance encounter: $encounterKey")
            continue
        }
        $state = $encounter.runtime_fields.map_binding_state
        $manifestInstanceStates[$encounterKey] = $state
        if ($state -ne 'verified') {
            $errors.Add("manifest instance map contract must be verified: $encounterKey (state=$state)")
        }
        if (-not $contractKeyByEncounter.ContainsKey($encounterKey)) {
            $errors.Add("manifest instance encounter has no map contract mapping: $encounterKey")
            continue
        }
        $contractKey = $contractKeyByEncounter[$encounterKey]
        $projection = $projectedStates[$encounterKey]
        if ($null -eq $projection) {
            $errors.Add("manifest instance encounter has no state projection: $encounterKey")
        }
        elseif ($projection.state -ne $state -or ($contractByKey.ContainsKey($contractKey) -and $contractByKey[$contractKey].state -ne $state)) {
            $errors.Add("manifest instance map state contradicts map logic binding: $encounterKey")
        }
        $manifestSlotsProperty = $encounter.runtime_fields.PSObject.Properties['instance_slots']
        if ($encounter.combat_scope -eq 'solo_instance') {
            if ($null -eq $manifestSlotsProperty -or -not (Test-PositiveInteger $manifestSlotsProperty.Value)) {
                $errors.Add("manifest instance_slots must be a positive integer: $encounterKey")
            }
            elseif ($contractByKey.ContainsKey($contractKey) -and
                $manifestSlotsProperty.Value -ne $contractByKey[$contractKey].slot_count) {
                $errors.Add("manifest instance_slots does not match instance map contract: $encounterKey")
            }
        }
    }
    foreach ($encounterKey in $contractKeyByEncounter.Keys) {
        if (-not $manifestInstanceStates.ContainsKey($encounterKey)) {
            $errors.Add("manifest missing instance encounter for map contract: $encounterKey")
        }
    }
    $allInstanceContractsVerified =
        $instanceContracts.Count -eq $expectedInstanceEncounterKeysByContract.Count -and
        $errors.Count -eq $instanceValidationErrorStart

    $topLevelInstanceGate = $binding.PSObject.Properties['instance_map_contract_verified']
    if ($null -ne $luaProjection) {
        $luaProjectionPropertyNames = @(
            'runtime_contract_id','editor_bound','instance_map_contract_verified','return_points',
            'encounter_resource_bindings','spawn_bindings','encounter_action_bindings',
            'encounter_instance_map_states','instance_contract_role_schema','instance_map_contracts'
        )
        [void](Assert-ExactProperties $luaProjection $luaProjectionPropertyNames 'Lua Config projection' $errors)

        $luaContractProperty = $luaProjection.PSObject.Properties['runtime_contract_id']
        if ($null -ne $luaContractProperty -and -not (Test-NonEmptyTrimmedString $luaContractProperty.Value)) {
            $errors.Add('Lua Config runtime_contract_id must be a non-empty trimmed string')
        }
        elseif ($null -ne $luaContractProperty -and $null -ne $bindingContractProperty -and
            (Test-NonEmptyTrimmedString $bindingContractProperty.Value) -and
            -not [string]::Equals($luaContractProperty.Value, $bindingContractProperty.Value, [StringComparison]::Ordinal)) {
            $errors.Add('Lua Config runtime contract does not match map logic binding')
        }

        $luaEditorBoundProperty = $luaProjection.PSObject.Properties['editor_bound']
        $bindingEditorBoundProperty = $binding.PSObject.Properties['real_map_binding_verified']
        if ($null -ne $luaEditorBoundProperty) {
            if ($luaEditorBoundProperty.Value -isnot [bool]) {
                $errors.Add('Lua Config editor_bound gate must be boolean')
            }
            else {
                if ($luaEditorBoundProperty.Value -ne $true) {
                    $errors.Add('Lua Config editor_bound gate unresolved')
                }
                if ($null -ne $bindingEditorBoundProperty -and $bindingEditorBoundProperty.Value -is [bool] -and
                    $luaEditorBoundProperty.Value -ne $bindingEditorBoundProperty.Value) {
                    $errors.Add('Lua Config editor_bound gate does not match map logic binding')
                }
            }
        }

        $luaGateProperty = $luaProjection.PSObject.Properties['instance_map_contract_verified']
        if ($null -ne $luaGateProperty) {
            if ($luaGateProperty.Value -isnot [bool]) {
                $errors.Add('Lua Config instance_map_contract_verified gate must be boolean')
            }
            else {
                if ($luaGateProperty.Value -ne $true) {
                    $errors.Add('Lua Config instance_map_contract_verified gate unresolved')
                }
                if ($null -ne $topLevelInstanceGate -and $topLevelInstanceGate.Value -is [bool] -and
                    $luaGateProperty.Value -ne $topLevelInstanceGate.Value) {
                    $errors.Add('Lua Config instance_map_contract_verified gate does not match map logic binding')
                }
            }
        }

        $luaProjectionArrayMessages = @{
            return_points = 'Lua Config return points do not match map logic binding'
            encounter_resource_bindings = 'Lua Config encounter resource bindings do not match map logic binding'
            spawn_bindings = 'Lua Config spawn bindings do not match map logic binding'
            encounter_action_bindings = 'Lua Config encounter action bindings do not match map logic binding'
            encounter_instance_map_states = 'Lua Config encounter instance map states do not match map logic binding'
            instance_contract_role_schema = 'Lua Config instance contract role schema does not match map logic binding'
            instance_map_contracts = 'Lua Config instance map contracts do not match map logic binding'
        }
        foreach ($name in $luaProjectionArrayMessages.Keys) {
            $property = $luaProjection.PSObject.Properties[$name]
            if ($null -ne $property -and -not (Test-JsonArray $property.Value)) {
                $errors.Add("Lua Config projection $name must be an array")
            }
            $bindingProperty = $binding.PSObject.Properties[$name]
            if ($null -ne $property -and $null -ne $bindingProperty -and
                (Test-JsonArray $property.Value) -and (Test-JsonArray $bindingProperty.Value)) {
                $luaValue = $property.Value
                $bindingValue = $bindingProperty.Value
                if ($name -eq 'return_points') {
                    $luaValue = @($luaValue | Sort-Object role)
                    $bindingValue = @($bindingValue | Sort-Object role)
                }
                elseif ($name -eq 'encounter_resource_bindings') {
                    $luaValue = @($luaValue | Sort-Object encounter_key, resource_key)
                    $bindingValue = @($bindingValue | Sort-Object encounter_key, resource_key)
                }
                elseif ($name -eq 'spawn_bindings') {
                    $luaValue = @($luaValue | Sort-Object encounter_key, anchor_key, unit_key)
                    $bindingValue = @($bindingValue | Sort-Object encounter_key, anchor_key, unit_key)
                }
                elseif ($name -eq 'encounter_action_bindings') {
                    $luaValue = @($luaValue | Sort-Object encounter_key)
                    $bindingValue = @($bindingValue | Sort-Object encounter_key)
                }
                elseif ($name -eq 'encounter_instance_map_states') {
                    $luaValue = @($luaValue | Sort-Object encounter_key)
                    $bindingValue = @($bindingValue | Sort-Object encounter_key)
                }
                elseif ($name -in @('instance_contract_role_schema','instance_map_contracts')) {
                    $luaValue = @($luaValue | Sort-Object contract_key)
                    $bindingValue = @($bindingValue | Sort-Object contract_key)
                }
                if ((Get-CanonicalJson $luaValue) -ne (Get-CanonicalJson $bindingValue)) {
                    $errors.Add($luaProjectionArrayMessages[$name])
                }
            }
        }
        $luaSpawnProperty = $luaProjection.PSObject.Properties['spawn_bindings']
        $luaResourceProperty = $luaProjection.PSObject.Properties['encounter_resource_bindings']
        if ($null -ne $luaSpawnProperty -and $null -ne $luaResourceProperty -and
            (Test-JsonArray $luaSpawnProperty.Value) -and (Test-JsonArray $luaResourceProperty.Value)) {
            Add-CanonicalPublicBossBindingErrors @($luaSpawnProperty.Value) @($luaResourceProperty.Value) 'Lua Config' $errors
        }
    }

    if ($null -ne $topLevelInstanceGate -and $topLevelInstanceGate.Value -is [bool]) {
        if ($topLevelInstanceGate.Value -and -not $allInstanceContractsVerified) {
            $errors.Add('map logic binding instance_map_contract_verified cannot be true unless every instance contract is verified')
        }
        elseif (-not $topLevelInstanceGate.Value -and $allInstanceContractsVerified) {
            $errors.Add('map logic binding instance_map_contract_verified must be true when every instance contract is verified')
        }
    }
}

$outputFullPath = $null
try {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw 'OutputPath must be non-empty.' }
    if ([IO.Path]::GetExtension($OutputPath) -ne '.ps1') { throw 'OutputPath must use the .ps1 extension.' }
    $outputFullPath = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath)) }
    if ([string]::Equals($outputFullPath, $manifestFullPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutputPath may not overwrite the source manifest.'
    }
    if ((Test-Path -LiteralPath $outputFullPath) -and -not (Test-Path -LiteralPath $outputFullPath -PathType Leaf)) {
        throw 'OutputPath must resolve to a file, not a directory.'
    }
    $outputParent = Split-Path -Parent $outputFullPath
    if ($outputParent -and (Test-Path -LiteralPath $outputParent) -and -not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        throw 'OutputPath parent must resolve to a directory.'
    }
}
catch {
    $errors.Add($_.Exception.Message)
}

$objectCollectionSpecs = @(
    [pscustomobject]@{ CollectionName = 'units'; ObjectType = 'unit'; RecordKeyPrefix = 'HG_U_' },
    [pscustomobject]@{ CollectionName = 'abilities'; ObjectType = 'ability'; RecordKeyPrefix = 'HG_A_' },
    [pscustomobject]@{ CollectionName = 'modifiers'; ObjectType = 'modifier'; RecordKeyPrefix = 'HG_M_' },
    [pscustomobject]@{ CollectionName = 'projectiles'; ObjectType = 'projectile'; RecordKeyPrefix = 'HG_P_' }
)
$objectRecords = [ordered]@{}
$objectRecordsByKey = [ordered]@{}
$globalRecordKeyOwners = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach ($spec in $objectCollectionSpecs) {
    $property = Get-ExactJsonProperty $manifest $spec.CollectionName
    $records = if ($null -eq $property) { $null } else { $property.Value }
    $objectRecords[$spec.CollectionName] = $records
    $objectRecordsByKey[$spec.CollectionName] = Assert-CanonicalObjectCollection `
        -Records $records -CollectionName $spec.CollectionName -ObjectType $spec.ObjectType `
        -RecordKeyPrefix $spec.RecordKeyPrefix -ExpectedKeys $canonicalObjectKeys[$spec.CollectionName] `
        -GlobalRecordKeyOwners $globalRecordKeyOwners -Errors $errors
}
$units = @($objectRecords['units'] | Where-Object { $_ -is [pscustomobject] })
$rawAbilities = @($objectRecords['abilities'] | Where-Object { $_ -is [pscustomobject] })
$rawModifiers = @($objectRecords['modifiers'] | Where-Object { $_ -is [pscustomobject] })
$rawProjectiles = @($objectRecords['projectiles'] | Where-Object { $_ -is [pscustomobject] })

$abilityDefaultsFields = Get-ExactJsonProperty $manifest.object_defaults.ability 'object_fields'
$modifierDefaultsFields = Get-ExactJsonProperty $manifest.object_defaults.modifier 'object_fields'
$projectileDefaultsFields = Get-ExactJsonProperty $manifest.object_defaults.projectile 'object_fields'
Add-UnresolvedFieldsContractErrors $manifest.object_defaults.ability 'object_defaults.ability' $errors
Add-UnresolvedFieldsContractErrors $manifest.object_defaults.modifier 'object_defaults.modifier' $errors
Add-UnresolvedFieldsContractErrors $manifest.object_defaults.projectile 'object_defaults.projectile' $errors
Add-ObjectFieldErrors $(if ($null -eq $abilityDefaultsFields) { $null } else { $abilityDefaultsFields.Value }) $abilityFieldSchema 'object_defaults.ability' $errors
Add-ObjectFieldErrors $(if ($null -eq $modifierDefaultsFields) { $null } else { $modifierDefaultsFields.Value }) $modifierFieldSchema 'object_defaults.modifier' $errors
Add-ObjectFieldErrors $(if ($null -eq $projectileDefaultsFields) { $null } else { $projectileDefaultsFields.Value }) $projectileFieldSchema 'object_defaults.projectile' $errors
foreach ($unit in $units) {
    Add-UnresolvedFieldsContractErrors $unit ([string]$unit.record_key) $errors
    $property = Get-ExactJsonProperty $unit 'object_fields'
    Add-ObjectFieldErrors $(if ($null -eq $property) { $null } else { $property.Value }) $unitFieldSchema ([string]$unit.record_key) $errors
}
foreach ($ability in $rawAbilities) {
    Add-UnresolvedFieldsContractErrors $ability ([string]$ability.record_key) $errors
    $property = Get-ExactJsonProperty $ability 'object_fields'
    Add-ObjectFieldErrors $(if ($null -eq $property) { $null } else { $property.Value }) $abilityFieldSchema ([string]$ability.record_key) $errors
}
foreach ($modifier in $rawModifiers) {
    Add-UnresolvedFieldsContractErrors $modifier ([string]$modifier.record_key) $errors
    $property = Get-ExactJsonProperty $modifier 'object_fields'
    Add-ObjectFieldErrors $(if ($null -eq $property) { $null } else { $property.Value }) $modifierFieldSchema ([string]$modifier.record_key) $errors
}
foreach ($projectile in $rawProjectiles) {
    Add-UnresolvedFieldsContractErrors $projectile ([string]$projectile.record_key) $errors
    $property = Get-ExactJsonProperty $projectile 'object_fields'
    Add-ObjectFieldErrors $(if ($null -eq $property) { $null } else { $property.Value }) $projectileFieldSchema ([string]$projectile.record_key) $errors
}

$modifiers = @($rawModifiers | ForEach-Object { Resolve-Record $manifest.object_defaults.modifier $_ })
$projectiles = @($rawProjectiles | ForEach-Object { Resolve-Record $manifest.object_defaults.projectile $_ })
$abilities = @($rawAbilities | ForEach-Object { Resolve-Record $manifest.object_defaults.ability $_ })
foreach ($unit in $units) {
    Add-ObjectFieldErrors $unit.object_fields $unitFieldSchema ([string]$unit.record_key) $errors
    Add-RequiredObjectFieldErrors $unit.object_fields $requiredUnitFields 'unit' ([string]$unit.record_key) $errors
}
foreach ($ability in $abilities) {
    Add-ObjectFieldErrors $ability.object_fields $abilityFieldSchema ([string]$ability.record_key) $errors
    Add-RequiredObjectFieldErrors $ability.object_fields $requiredAbilityFields 'ability' ([string]$ability.record_key) $errors
    Add-AbilityLevelArrayErrors $ability.object_fields ([string]$ability.record_key) $abilityLevelArrayFields $errors
}
foreach ($modifier in $modifiers) {
    Add-ObjectFieldErrors $modifier.object_fields $modifierFieldSchema ([string]$modifier.record_key) $errors
    Add-RequiredObjectFieldErrors $modifier.object_fields $requiredModifierFields 'modifier' ([string]$modifier.record_key) $errors
}
foreach ($projectile in $projectiles) {
    Add-ObjectFieldErrors $projectile.object_fields $projectileFieldSchema ([string]$projectile.record_key) $errors
    Add-RequiredObjectFieldErrors $projectile.object_fields $requiredProjectileFields 'projectile' ([string]$projectile.record_key) $errors
}
$allObjects = $modifiers + $projectiles + $abilities + $units
$productionIdOwners = @{}
foreach ($object in $allObjects) {
    if ($object.status -ne 'id-assigned') {
        $errors.Add("$($object.record_key): status must be id-assigned before materialization")
    }
    if ($object.operation -ne 'create') {
        $errors.Add("$($object.record_key): operation must be create before materialization")
    }
    if (-not (Test-PositiveInteger $object.y3_id)) {
        $errors.Add("$($object.record_key): y3_id must be a positive integer")
    }
    else {
        $normalizedId = [string]$object.y3_id
        if ($productionIdOwners.ContainsKey($normalizedId)) {
            $errors.Add("duplicate global y3_id ${normalizedId}: $($object.record_key) and $($productionIdOwners[$normalizedId])")
        }
        else { $productionIdOwners[$normalizedId] = $object.record_key }
    }
    if (-not (Test-PositiveInteger $object.icon_id)) { $errors.Add("$($object.record_key): icon_id must be a positive integer") }
    if (@($object.unresolved_fields).Count -gt 0) { $errors.Add("$($object.record_key): unresolved fields: $(@($object.unresolved_fields) -join ',')") }
}
foreach ($unit in $units) {
    if ($unit.object_type -ne 'unit') { $errors.Add("$($unit.record_key): object_type must be unit") }
    if (-not (Test-PositiveInteger $unit.model_id)) { $errors.Add("$($unit.record_key): model_id must be a positive integer") }
    if ($null -eq (Get-ExactJsonProperty $unit.object_fields 'common_atk_range')) { $errors.Add("$($unit.record_key): common_atk_range unresolved") }
}
foreach ($ability in $abilities) { if ($ability.object_type -ne 'ability') { $errors.Add("$($ability.record_key): object_type must be ability") } }
foreach ($modifier in $modifiers) { if ($modifier.object_type -ne 'modifier') { $errors.Add("$($modifier.record_key): object_type must be modifier") } }
foreach ($projectile in $projectiles) { if ($projectile.object_type -ne 'projectile') { $errors.Add("$($projectile.record_key): object_type must be projectile") } }

$objectByKey = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($collectionName in @('units','abilities','modifiers','projectiles')) {
    foreach ($recordKey in $objectRecordsByKey[$collectionName].Keys) {
        if (-not $objectByKey.ContainsKey($recordKey)) {
            $objectByKey.Add($recordKey, $objectRecordsByKey[$collectionName][$recordKey])
        }
    }
}
Add-ObjectDependencyClosureErrors -Units $units -Abilities $abilities -ObjectByKey $objectByKey `
    -UnitByKey $objectRecordsByKey['units'] -AbilityByKey $objectRecordsByKey['abilities'] -Errors $errors

if ($errors.Count -gt 0) {
    Write-Output 'Huaguoshan object command materialization refused:'
    foreach ($entry in $errors) { Write-Output ('  - ' + $entry) }
    exit 1
}

if ((Test-Path -LiteralPath $outputFullPath) -and -not $Force) { throw "Output already exists: $outputFullPath. Pass -Force to replace it." }

$abilityIds = @{}
foreach ($ability in $abilities) { $abilityIds[$ability.record_key] = $ability.y3_id }
$editor = [string]$executionGates.y3_obj_edit_script
$map = [string]$executionGates.map_path
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Generated from Huaguoshan preconstruction manifest. Do not edit Y3 JSON directly.')
$lines.Add("`$ErrorActionPreference = 'Stop'")
$lines.Add('')

$modifierFields = @('modifier_type','modifier_effect','layer_max','disappear_when_dead','show_on_ui','shield_value','shield_type','influence_rng','is_influence_self','material_color')
foreach ($modifier in $modifiers) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    $tokens.Add('& py -3'); $tokens.Add((Quote-PowerShell $editor)); $tokens.Add('-map'); $tokens.Add((Quote-PowerShell $map)); $tokens.Add('-type modifier -create')
    $tokens.Add((Quote-PowerShell "$($modifier.y3_id),$($modifier.name),$($modifier.icon_id)"))
    Add-FieldTokens $tokens $modifier.object_fields $modifierFields @('material_color')
    Add-Command $lines $tokens $modifier.record_key
}

$projectileFields = @('max_duration','move_channel','move_limitation','sfx_loop','effect_foes','effect_friend')
foreach ($projectile in $projectiles) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    $tokens.Add('& py -3'); $tokens.Add((Quote-PowerShell $editor)); $tokens.Add('-map'); $tokens.Add((Quote-PowerShell $map)); $tokens.Add('-type projectile -create')
    $tokens.Add((Quote-PowerShell "$($projectile.y3_id),$($projectile.name),$($projectile.icon_id)"))
    Add-FieldTokens $tokens $projectile.object_fields $projectileFields @()
    Add-Command $lines $tokens $projectile.record_key
}

$abilityFields = @('ability_max_level','sight_type','ability_cast_type','ability_cast_point','ability_bw_point','is_immediate','is_meele','cold_down_time','ability_cost','ability_hp_cost','ability_damage','ability_damage_range','ability_cast_range','circle_radius','sector_radius','sector_angle','arrow_length','arrow_width','required_level')
$abilityArrays = @('cold_down_time','ability_cost','ability_hp_cost','ability_damage','ability_damage_range','ability_cast_range','circle_radius','sector_radius','sector_angle','arrow_length','arrow_width','required_level')
foreach ($ability in $abilities) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    $tokens.Add('& py -3'); $tokens.Add((Quote-PowerShell $editor)); $tokens.Add('-map'); $tokens.Add((Quote-PowerShell $map)); $tokens.Add('-type ability -create')
    $tokens.Add((Quote-PowerShell "$($ability.y3_id),$($ability.name),$($ability.icon_id)"))
    Add-FieldTokens $tokens $ability.object_fields $abilityFields $abilityArrays
    Add-Command $lines $tokens $ability.record_key
}

$unitFields = @('hp_max','hp_max_grow','mp_max','mp_max_grow','attack_phy','attack_phy_grow','attack_mag','defense_phy','defense_mag','attack_speed','attack_interval','common_atk_type','ori_speed','turn_speed','sight_range','attack_range','reward_exp','reward_official_res_1','common_ability_list')
foreach ($unit in $units) {
    $fields = @{}
    foreach ($property in $unit.object_fields.PSObject.Properties) { $fields[$property.Name] = $property.Value }
    $abilityTokens = [System.Collections.Generic.List[string]]::new()
    foreach ($abilityKey in @($unit.common_ability_keys)) {
        if (-not $abilityIds.ContainsKey($abilityKey)) { throw "$($unit.record_key): no resolved ability ID for $abilityKey" }
        $abilityTokens.Add("$($abilityIds[$abilityKey]):1")
    }
    if ($abilityTokens.Count -gt 0) { $fields['common_ability_list'] = $abilityTokens -join ',' }
    $fieldObject = [pscustomobject]$fields
    $tokens = [System.Collections.Generic.List[string]]::new()
    $tokens.Add('& py -3'); $tokens.Add((Quote-PowerShell $editor)); $tokens.Add('-map'); $tokens.Add((Quote-PowerShell $map)); $tokens.Add('-type unit -create')
    $tokens.Add((Quote-PowerShell "$($unit.y3_id),$($unit.name),$($unit.unit_type),$($unit.model_id),$($unit.icon_id)"))
    Add-FieldTokens $tokens $fieldObject $unitFields @('common_ability_list')
    Add-Command $lines $tokens $unit.record_key
    $commonAttackRange = Get-ExactJsonProperty $unit.object_fields 'common_atk_range'
    $rangeTokens = [System.Collections.Generic.List[string]]::new()
    $rangeTokens.Add('& py -3'); $rangeTokens.Add((Quote-PowerShell $editor)); $rangeTokens.Add('-map'); $rangeTokens.Add((Quote-PowerShell $map)); $rangeTokens.Add('-type unit -edit')
    $rangeTokens.Add((Format-Scalar $unit.y3_id)); $rangeTokens.Add('-common_atk_range'); $rangeTokens.Add((Format-Scalar $commonAttackRange.Value))
    Add-Command $lines $rangeTokens ($unit.record_key + ':common_atk_range')
}

$lines.Add("Write-Output 'Created $($modifiers.Count) modifiers, $($projectiles.Count) projectiles, $($abilities.Count) abilities, and $($units.Count) units.'")
$lines.Add("Write-Output 'Next: hotfix object editor, wait 3 seconds, save, then read back all created objects.'")
$parent = Split-Path -Parent $outputFullPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
Set-Content -LiteralPath $outputFullPath -Value $lines -Encoding UTF8
Write-Output "Generated: $outputFullPath"
