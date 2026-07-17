param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\preconstruction-manifest.json'),
    [string]$LayoutPath = '',
    [string]$BindingPath = (Join-Path $PSScriptRoot '..\map-logic-binding.json')
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

function Get-PropertyValue {
    param($Object, [string]$Name)
    $property = Get-ExactJsonProperty $Object $Name
    if ($null -eq $property) { return $null }
    return $property.Value
}

function From-Base64Utf8 {
    param([string]$Value)
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function Add-Error {
    param([System.Collections.Generic.List[string]]$Errors, [string]$Message)
    $Errors.Add($Message)
}

function Get-ExactJsonProperty {
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    foreach ($property in @($Object.PSObject.Properties)) {
        if ([string]::Equals($property.Name, $Name, [StringComparison]::Ordinal)) { return $property }
    }
    return $null
}

function New-OrdinalMap {
    return [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
}

function ConvertTo-OrdinalMap {
    param([System.Collections.IDictionary]$Source)
    $result = New-OrdinalMap
    foreach ($key in $Source.Keys) { $result.Add([string]$key, $Source[$key]) }
    return $result
}

function Test-OrdinalMapKey {
    param([System.Collections.IDictionary]$Map, [string]$Name)
    foreach ($key in $Map.Keys) {
        if ([string]::Equals([string]$key, $Name, [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Get-OrdinalMapValue {
    param([System.Collections.IDictionary]$Map, [string]$Name)
    foreach ($key in $Map.Keys) {
        if ([string]::Equals([string]$key, $Name, [StringComparison]::Ordinal)) { return $Map[$key] }
    }
    return $null
}

function Assert-RequiredProperties {
    param($Object, [string[]]$Names, [string]$Prefix, [System.Collections.Generic.List[string]]$Errors)
    foreach ($name in $Names) {
        if ($null -eq (Get-ExactJsonProperty $Object $name)) {
            Add-Error $Errors "$Prefix missing required property: $name"
        }
    }
}

function Assert-ExactProperties {
    param($Object, [string[]]$Names, [string]$Prefix, [System.Collections.Generic.List[string]]$Errors)
    Assert-RequiredProperties $Object $Names $Prefix $Errors
    foreach ($property in $Object.PSObject.Properties) {
        if ($Names -cnotcontains $property.Name) {
            Add-Error $Errors "$Prefix has unexpected property: $($property.Name)"
        }
    }
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

function Test-JsonNumber {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    $isNumber =
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
    if (-not $isNumber) { return $false }
    $number = [double]$Value
    return -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)
}

function Test-JsonInteger {
    param([AllowNull()][object]$Value)
    if (-not (Test-JsonNumber $Value)) { return $false }
    $number = [double]$Value
    return [math]::Truncate($number) -eq $number
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

function Test-JsonArray {
    param([AllowNull()][object]$Value)
    return $null -ne $Value -and $Value -isnot [string] -and $Value -isnot [pscustomobject] -and
        $Value -is [System.Collections.IEnumerable]
}

function Get-EffectivePropertyValue {
    param($Defaults, $Record, [string]$Name)
    if ($null -ne $Record) {
        $property = Get-ExactJsonProperty $Record $Name
        if ($null -ne $property) { return $property.Value }
    }
    if ($null -ne $Defaults) {
        $property = Get-ExactJsonProperty $Defaults $Name
        if ($null -ne $property) { return $property.Value }
    }
    return $null
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

function Get-MergedFields {
    param($Defaults, $Overrides)
    $result = [ordered]@{}
    if ($null -ne $Defaults) {
        foreach ($property in $Defaults.PSObject.Properties) { $result[$property.Name] = $property.Value }
    }
    if ($null -ne $Overrides) {
        foreach ($property in $Overrides.PSObject.Properties) { $result[$property.Name] = $property.Value }
    }
    return $result
}

function Test-ObjectFieldValue {
    param([AllowNull()][object]$Value, [object]$Rule)
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
        'rgb_array' {
            if ($Value -isnot [System.Array] -or @($Value).Count -ne 3) { return $false }
            foreach ($item in @($Value)) {
                if (-not (Test-JsonInteger $item) -or [int]$item -lt 0 -or [int]$item -gt 255) { return $false }
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
        'rgb_array' { return 'an RGB array of exactly three integers from 0 to 255' }
        default { return 'a valid value' }
    }
}

function Add-ObjectFieldErrors {
    param(
        [AllowNull()][object]$Fields,
        [System.Collections.IDictionary]$Schema,
        [string]$RecordKey,
        [System.Collections.Generic.List[string]]$Errors
    )
    if ($Fields -isnot [pscustomobject]) {
        Add-Error $Errors "${RecordKey}: object_fields must be an object"
        return
    }
    $schemaNames = @($Schema.Keys)
    foreach ($property in @($Fields.PSObject.Properties)) {
        if ($schemaNames -cnotcontains $property.Name) {
            Add-Error $Errors "${RecordKey}: object_fields unknown field: $($property.Name)"
            continue
        }
        $rule = Get-OrdinalMapValue $Schema $property.Name
        if (-not (Test-ObjectFieldValue $property.Value $rule)) {
            Add-Error $Errors "${RecordKey}: object_fields $($property.Name) must be $(Get-ObjectFieldExpectation $rule)"
        }
    }
}

function Add-AbilityLevelArrayErrors {
    param(
        [AllowNull()][object]$Fields,
        [string]$RecordKey,
        [string[]]$ArrayFields,
        [System.Collections.Generic.List[string]]$Errors
    )
    if ($Fields -isnot [pscustomobject]) { return }
    $maxLevelProperty = Get-ExactJsonProperty $Fields 'ability_max_level'
    if ($null -eq $maxLevelProperty -or -not (Test-JsonInteger $maxLevelProperty.Value) -or [int]$maxLevelProperty.Value -le 0) { return }
    foreach ($fieldName in $ArrayFields) {
        $property = Get-ExactJsonProperty $Fields $fieldName
        if ($null -ne $property -and $property.Value -is [System.Array] -and @($property.Value).Count -ne [int]$maxLevelProperty.Value) {
            Add-Error $Errors "${RecordKey}: object_fields $fieldName must contain exactly $([int]$maxLevelProperty.Value) values"
        }
    }
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
    return ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $Value) -Depth 100 -Compress
}

$unitFieldSchema = ConvertTo-OrdinalMap ([ordered]@{
    hp_max = [pscustomobject]@{ Kind = 'positive_number' }
    hp_max_grow = [pscustomobject]@{ Kind = 'nonnegative_number' }
    mp_max = [pscustomobject]@{ Kind = 'nonnegative_number' }
    mp_max_grow = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_phy = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_phy_grow = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_mag = [pscustomobject]@{ Kind = 'nonnegative_number' }
    defense_phy = [pscustomobject]@{ Kind = 'nonnegative_number' }
    defense_mag = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_speed = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_interval = [pscustomobject]@{ Kind = 'positive_number' }
    common_atk_type = [pscustomobject]@{ Kind = 'enum'; Values = @(0, 1) }
    ori_speed = [pscustomobject]@{ Kind = 'nonnegative_number' }
    turn_speed = [pscustomobject]@{ Kind = 'nonnegative_number' }
    sight_range = [pscustomobject]@{ Kind = 'nonnegative_number' }
    attack_range = [pscustomobject]@{ Kind = 'nonnegative_number' }
    common_atk_range = [pscustomobject]@{ Kind = 'positive_number' }
    reward_exp = [pscustomobject]@{ Kind = 'nonnegative_number' }
    reward_official_res_1 = [pscustomobject]@{ Kind = 'nonnegative_number' }
})
$abilityFieldSchema = ConvertTo-OrdinalMap ([ordered]@{
    ability_max_level = [pscustomobject]@{ Kind = 'positive_integer' }
    sight_type = [pscustomobject]@{ Kind = 'enum'; Values = @(0, 1, 2, 3, 4, 5, 6, 7) }
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
})
$abilityLevelArrayFields = @(
    'cold_down_time','ability_cost','ability_hp_cost','ability_damage','ability_damage_range',
    'ability_cast_range','circle_radius','sector_radius','sector_angle','arrow_length','arrow_width','required_level'
)
$modifierFieldSchema = ConvertTo-OrdinalMap ([ordered]@{
    modifier_type = [pscustomobject]@{ Kind = 'enum'; Values = @(1, 2, 3, 4) }
    modifier_effect = [pscustomobject]@{ Kind = 'enum'; Values = @(1, 2, 3) }
    layer_max = [pscustomobject]@{ Kind = 'positive_integer' }
    disappear_when_dead = [pscustomobject]@{ Kind = 'boolean' }
    show_on_ui = [pscustomobject]@{ Kind = 'boolean' }
    shield_value = [pscustomobject]@{ Kind = 'nonnegative_number' }
    shield_type = [pscustomobject]@{ Kind = 'enum'; Values = @(0, 1, 2) }
    influence_rng = [pscustomobject]@{ Kind = 'nonnegative_number' }
    is_influence_self = [pscustomobject]@{ Kind = 'boolean' }
    material_color = [pscustomobject]@{ Kind = 'rgb_array' }
})
$projectileFieldSchema = ConvertTo-OrdinalMap ([ordered]@{
    max_duration = [pscustomobject]@{ Kind = 'positive_number' }
    move_channel = [pscustomobject]@{ Kind = 'enum'; Values = @(0, 1) }
    move_limitation = [pscustomobject]@{ Kind = 'enum'; Values = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15) }
    sfx_loop = [pscustomobject]@{ Kind = 'boolean' }
    effect_foes = [pscustomobject]@{ Kind = 'positive_integer' }
    effect_friend = [pscustomobject]@{ Kind = 'positive_integer' }
})

# Immutable acceptance policy: these encounter identities are not inferred from any artifact under validation.
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
            Add-Error $Errors "$SourceLabel ${encounterKey}: canonical public boss tuple must be $($canonicalBoss.UnitKey) -> $($canonicalBoss.ArenaKey)"
        }
    }
}

function Read-LuaConfigProjection {
    param([string]$ConfigPath)
    $projectionScript = Join-Path $PSScriptRoot 'export_config_binding_projection.lua'
    if (-not (Test-Path -LiteralPath $projectionScript -PathType Leaf)) {
        throw 'Lua Config projection helper is unavailable'
    }
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $nodeCommand -or [string]::IsNullOrWhiteSpace($nodeCommand.Source)) {
        throw 'Node is required to read the Lua Config projection'
    }
    $pnpmStore = Join-Path $env:LOCALAPPDATA 'pnpm\store'
    $fengari = if (Test-Path -LiteralPath $pnpmStore -PathType Container) {
        Get-ChildItem -LiteralPath $pnpmStore -Recurse -File -Filter 'lua-cli.js' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$' } |
            Select-Object -First 1 -ExpandProperty FullName
    }
    else { $null }
    if ([string]::IsNullOrWhiteSpace($fengari)) {
        throw 'cached fengari-node-cli is required to read the Lua Config projection'
    }

    $output = & $nodeCommand.Source $fengari $projectionScript $ConfigPath 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = $output | Out-String
    if ($exitCode -ne 0) { throw "Lua Config projection execution failed: $outputText" }
    try { $projection = ConvertFrom-StrictJson $outputText 'Lua Config projection' }
    catch { throw "Lua Config projection did not return valid JSON: $($_.Exception.Message)" }
    if ($null -eq $projection -or $projection -isnot [pscustomobject]) {
        throw 'Lua Config projection must return a JSON object'
    }
    return $projection
}

$manifestFullPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($LayoutPath)) {
    $layoutCandidates = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs') -Recurse -File -Filter 'layout.json' |
        Where-Object { $_.FullName -like '*huaguoshan-96x72*' })
    if ($layoutCandidates.Count -ne 1) { throw 'Expected exactly one huaguoshan-96x72 layout.json under docs.' }
    $LayoutPath = $layoutCandidates[0].FullName
}
$layoutFullPath = (Resolve-Path -LiteralPath $LayoutPath).Path
$bindingFullPath = (Resolve-Path -LiteralPath $BindingPath).Path
$repoUri = [Uri]($repoRoot.TrimEnd('\') + '\')
$layoutRelativePath = [Uri]::UnescapeDataString($repoUri.MakeRelativeUri([Uri]$layoutFullPath).ToString()).Replace('\', '/')
$manifest = Read-StrictJsonFile $manifestFullPath "manifest '$manifestFullPath'"
$layout = Read-StrictJsonFile $layoutFullPath "layout '$layoutFullPath'"
$binding = Read-StrictJsonFile $bindingFullPath "map logic binding '$bindingFullPath'"
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

Assert-ExactProperties $manifest @(
    'package','schema_version','status','scope','source_docs','execution_gates','runtime_package',
    'object_defaults','runtime_profiles','units','abilities','modifiers','projectiles','encounters'
) 'manifest' $errors

$executionGatePathNames = @('map_path','script_root','y3_obj_edit_script')
$executionGateBooleanNames = @(
    'y3editor_connected','map_logic_resources_verified','unit_ids_assigned','ability_ids_assigned',
    'modifier_ids_assigned','projectile_ids_assigned','model_ids_assigned','icon_ids_assigned',
    'effect_resources_assigned','encounter_runtime_bound','distance_scale_verified',
    'instance_map_contract_verified','authoritative_progression_validator_bound'
)
$executionGateNames = @($executionGatePathNames) + @($executionGateBooleanNames)
$executionGates = Get-PropertyValue $manifest 'execution_gates'
if ($null -eq $executionGates) {
    Add-Error $errors 'execution_gates is required'
    $executionGates = [pscustomobject]@{}
}
else {
    Assert-ExactProperties $executionGates $executionGateNames 'execution_gates' $errors
}
foreach ($name in $executionGateBooleanNames) {
    $property = Get-ExactJsonProperty $executionGates $name
    if ($null -ne $property -and $property.Value -isnot [bool]) {
        Add-Error $errors "execution gate must be boolean: $name"
    }
}
foreach ($name in $executionGatePathNames) {
    $property = Get-ExactJsonProperty $executionGates $name
    if ($null -eq $property -or $null -eq $property.Value) { continue }
    if ($property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        Add-Error $errors "execution gate must be a non-empty path string or null: $name"
    }
}

$mapPathGate = Get-PropertyValue $executionGates 'map_path'
if ($mapPathGate -is [string] -and -not [string]::IsNullOrWhiteSpace($mapPathGate) -and -not (Test-Path -LiteralPath $mapPathGate -PathType Container)) {
    Add-Error $errors 'map_path must resolve to an existing directory when assigned'
}
$scriptRootGate = Get-PropertyValue $executionGates 'script_root'
if ($scriptRootGate -is [string] -and -not [string]::IsNullOrWhiteSpace($scriptRootGate) -and -not (Test-Path -LiteralPath $scriptRootGate -PathType Container)) {
    Add-Error $errors 'script_root must resolve to an existing directory when assigned'
}
$objectEditorGate = Get-PropertyValue $executionGates 'y3_obj_edit_script'
if ($objectEditorGate -is [string] -and -not [string]::IsNullOrWhiteSpace($objectEditorGate)) {
    if ([IO.Path]::GetFileName($objectEditorGate) -ne 'y3_obj_edit.py') {
        Add-Error $errors 'y3_obj_edit_script must name y3_obj_edit.py'
    }
    if ($objectEditorGate.Replace('\', '/') -notmatch '/skills/y3-obj-edit/scripts/y3_obj_edit\.py$') {
        Add-Error $errors 'y3_obj_edit_script must point to skills/y3-obj-edit/scripts/y3_obj_edit.py'
    }
    if (-not (Test-Path -LiteralPath $objectEditorGate -PathType Leaf)) {
        Add-Error $errors 'y3_obj_edit_script must resolve to an existing file when assigned'
    }
    elseif (-not (Test-Y3ObjectEditorScriptShape $objectEditorGate)) {
        Add-Error $errors 'y3_obj_edit_script does not expose the required object editor command interface'
    }
}

if ($manifest.status -ne 'reviewed') { Add-Error $errors 'package status must remain reviewed before editor construction' }

$runtimePackage = Get-PropertyValue $manifest 'runtime_package'
$luaProjection = $null
if ($null -eq $runtimePackage) {
    Add-Error $errors 'runtime_package is required'
}
else {
    Assert-RequiredProperties $runtimePackage @('status','lua_root','map_logic_binding_path','runtime_contract_id','offline_runtime_complete','public_map_contract_complete','instance_map_contract_verified','authoritative_progression_validator_bound','real_map_binding_verified','production_ids_ready') 'runtime_package' $errors
    if ($runtimePackage.status -ne 'offline-runtime-public-map-contract-complete-instance-map-contract-pending') { Add-Error $errors 'runtime_package status is invalid' }
    foreach ($name in @('offline_runtime_complete','public_map_contract_complete','instance_map_contract_verified','authoritative_progression_validator_bound','real_map_binding_verified','production_ids_ready')) {
        $property = Get-ExactJsonProperty $runtimePackage $name
        if ($null -ne $property -and $property.Value -isnot [bool]) { Add-Error $errors "runtime_package property must be boolean: $name" }
    }
    if ($runtimePackage.offline_runtime_complete -is [bool] -and $runtimePackage.offline_runtime_complete -ne $true) { Add-Error $errors 'runtime_package must record offline runtime completion' }
    if ($runtimePackage.public_map_contract_complete -is [bool] -and $runtimePackage.public_map_contract_complete -ne $true) { Add-Error $errors 'runtime_package must record public map contract completion' }
    if (($runtimePackage.instance_map_contract_verified -is [bool] -and $runtimePackage.instance_map_contract_verified -ne $false) -or
        ($runtimePackage.authoritative_progression_validator_bound -is [bool] -and $runtimePackage.authoritative_progression_validator_bound -ne $false) -or
        ($runtimePackage.real_map_binding_verified -is [bool] -and $runtimePackage.real_map_binding_verified -ne $false) -or
        ($runtimePackage.production_ids_ready -is [bool] -and $runtimePackage.production_ids_ready -ne $false)) {
        Add-Error $errors 'runtime_package may not claim pending instance, progression, map, or production gates'
    }
    if ($runtimePackage.instance_map_contract_verified -is [bool] -and
        $executionGates.instance_map_contract_verified -is [bool] -and
        $runtimePackage.instance_map_contract_verified -ne $executionGates.instance_map_contract_verified) {
        Add-Error $errors 'runtime_package instance map contract gate does not match execution_gates'
    }
    if ($runtimePackage.authoritative_progression_validator_bound -is [bool] -and
        $executionGates.authoritative_progression_validator_bound -is [bool] -and
        $runtimePackage.authoritative_progression_validator_bound -ne $executionGates.authoritative_progression_validator_bound) {
        Add-Error $errors 'runtime_package progression gate does not match execution_gates'
    }
    $packageRoot = Split-Path -Parent $manifestFullPath
    $declaredBindingPath = Get-PropertyValue $runtimePackage 'map_logic_binding_path'
    if ($declaredBindingPath -isnot [string] -or [string]::IsNullOrWhiteSpace($declaredBindingPath)) {
        Add-Error $errors 'runtime_package map_logic_binding_path must be a non-empty package-relative path'
    }
    else {
        if ([IO.Path]::IsPathRooted($declaredBindingPath)) {
            Add-Error $errors 'runtime_package map_logic_binding_path must be package-relative'
        }
        else {
            $expectedBindingCandidate = [IO.Path]::GetFullPath((Join-Path $packageRoot $declaredBindingPath))
            $packagePrefix = $packageRoot.TrimEnd('\') + '\'
            if (-not $expectedBindingCandidate.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                Add-Error $errors 'runtime_package map_logic_binding_path must remain inside the package directory'
            }
            elseif (-not (Test-Path -LiteralPath $expectedBindingCandidate -PathType Leaf)) {
                Add-Error $errors 'runtime_package map_logic_binding_path does not resolve to a file'
            }
            else {
                $expectedBindingItem = Get-Item -LiteralPath $expectedBindingCandidate -Force
                if (($expectedBindingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    Add-Error $errors 'runtime_package map_logic_binding_path may not resolve through a reparse point'
                }
                else {
                    $expectedBindingFullPath = (Resolve-Path -LiteralPath $expectedBindingCandidate).Path
                    if (-not [string]::Equals($bindingFullPath, $expectedBindingFullPath, [StringComparison]::OrdinalIgnoreCase)) {
                        Add-Error $errors 'BindingPath must match runtime_package map_logic_binding_path'
                    }
                }
            }
        }
    }
    foreach ($module in @('huaguoshan_config.lua','huaguoshan_map_binding.lua','huaguoshan_contribution.lua','huaguoshan_public_boss.lua','huaguoshan_public_trace.lua','huaguoshan_instances.lua','huaguoshan_runtime.lua','huaguoshan_y3_adapter.lua','huaguoshan_y3_controller.lua')) {
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $packageRoot $runtimePackage.lua_root) $module))) {
            Add-Error $errors "runtime_package missing Lua module: $module"
        }
    }
    $luaConfigCandidate = Join-Path (Join-Path $packageRoot $runtimePackage.lua_root) 'huaguoshan_config.lua'
    if (Test-Path -LiteralPath $luaConfigCandidate -PathType Leaf) {
        try { $luaProjection = Read-LuaConfigProjection $luaConfigCandidate }
        catch { Add-Error $errors $_.Exception.Message }
    }
}

$expectedCounts = @{ units = 35; abilities = 55; modifiers = 12; projectiles = 7; encounters = 15 }
foreach ($pair in $expectedCounts.GetEnumerator()) {
    $actual = @($manifest.$($pair.Key)).Count
    if ($actual -ne $pair.Value) { Add-Error $errors "$($pair.Key) expected $($pair.Value), got $actual" }
}

$allObjects = @($manifest.units) + @($manifest.abilities) + @($manifest.modifiers) + @($manifest.projectiles)
$objectByKey = @{}
foreach ($object in $allObjects) {
    Assert-RequiredProperties $object @('record_key', 'object_type', 'name') 'object' $errors
    if ([string]::IsNullOrWhiteSpace([string]$object.record_key)) { Add-Error $errors 'object has blank record_key'; continue }
    if ($objectByKey.ContainsKey($object.record_key)) { Add-Error $errors "duplicate object record_key: $($object.record_key)" }
    else { $objectByKey[$object.record_key] = $object }
}

$productionIdOwners = @{}
$productionGroups = @(
    [pscustomobject]@{ Records = @($manifest.units); Defaults = $null; Gate = 'unit_ids_assigned' },
    [pscustomobject]@{ Records = @($manifest.abilities); Defaults = $manifest.object_defaults.ability; Gate = 'ability_ids_assigned' },
    [pscustomobject]@{ Records = @($manifest.modifiers); Defaults = $manifest.object_defaults.modifier; Gate = 'modifier_ids_assigned' },
    [pscustomobject]@{ Records = @($manifest.projectiles); Defaults = $manifest.object_defaults.projectile; Gate = 'projectile_ids_assigned' }
)
foreach ($group in $productionGroups) {
    $gateProperty = $executionGates.PSObject.Properties[$group.Gate]
    foreach ($object in $group.Records) {
        $status = Get-EffectivePropertyValue $group.Defaults $object 'status'
        $operation = Get-EffectivePropertyValue $group.Defaults $object 'operation'
        if ($status -ne 'reviewed' -or $operation -ne 'create') {
            Add-Error $errors "$($object.record_key): effective status/operation must remain reviewed/create"
        }
        $y3Id = Get-EffectivePropertyValue $group.Defaults $object 'y3_id'
        if ($null -eq $y3Id) {
            if ($null -ne $gateProperty -and $gateProperty.Value -is [bool] -and $gateProperty.Value) {
                Add-Error $errors "$($object.record_key): y3_id is required while $($group.Gate) is open"
            }
        }
        elseif (-not (Test-PositiveInteger $y3Id)) {
            Add-Error $errors "$($object.record_key): y3_id must be a positive integer"
        }
        else {
            $normalizedId = [string]$y3Id
            if ($productionIdOwners.ContainsKey($normalizedId)) {
                Add-Error $errors "duplicate global y3_id ${normalizedId}: $($object.record_key) and $($productionIdOwners[$normalizedId])"
            }
            else { $productionIdOwners[$normalizedId] = $object.record_key }
            if ($null -ne $gateProperty -and $gateProperty.Value -is [bool] -and -not $gateProperty.Value) {
                Add-Error $errors "$($object.record_key): y3_id assigned while $($group.Gate) is closed"
            }
        }

        $iconId = Get-EffectivePropertyValue $group.Defaults $object 'icon_id'
        $iconGate = $executionGates.PSObject.Properties['icon_ids_assigned']
        if ($null -eq $iconId) {
            if ($null -ne $iconGate -and $iconGate.Value -is [bool] -and $iconGate.Value) {
                Add-Error $errors "$($object.record_key): icon_id is required while icon_ids_assigned is open"
            }
        }
        elseif (-not (Test-PositiveInteger $iconId)) {
            Add-Error $errors "$($object.record_key): icon_id must be a positive integer"
        }
        elseif ($null -ne $iconGate -and $iconGate.Value -is [bool] -and -not $iconGate.Value) {
            Add-Error $errors "$($object.record_key): icon_id assigned while icon_ids_assigned is closed"
        }
    }
}

$modelGate = $executionGates.PSObject.Properties['model_ids_assigned']
foreach ($unit in @($manifest.units)) {
    $modelId = Get-EffectivePropertyValue $null $unit 'model_id'
    if ($null -eq $modelId) {
        if ($null -ne $modelGate -and $modelGate.Value -is [bool] -and $modelGate.Value) {
            Add-Error $errors "$($unit.record_key): model_id is required while model_ids_assigned is open"
        }
    }
    elseif (-not (Test-PositiveInteger $modelId)) {
        Add-Error $errors "$($unit.record_key): model_id must be a positive integer"
    }
    elseif ($null -ne $modelGate -and $modelGate.Value -is [bool] -and -not $modelGate.Value) {
        Add-Error $errors "$($unit.record_key): model_id assigned while model_ids_assigned is closed"
    }
}

$encounterByKey = @{}
foreach ($encounter in @($manifest.encounters)) {
    Assert-RequiredProperties $encounter @('record_key', 'encounter_type', 'combat_scope', 'map_logic_resource_keys', 'map_logic_resource_roles', 'runtime_fields') 'encounter' $errors
    if ([string]::IsNullOrWhiteSpace([string]$encounter.record_key)) { Add-Error $errors 'encounter has blank record_key'; continue }
    if ($objectByKey.ContainsKey($encounter.record_key) -or $encounterByKey.ContainsKey($encounter.record_key)) { Add-Error $errors "duplicate global record_key: $($encounter.record_key)" }
    else { $encounterByKey[$encounter.record_key] = $encounter }
}

$allowedUnitTypes = @(
    (From-Base64Utf8 '6L+R5oiY5bCP5oCq'),
    (From-Base64Utf8 '6L+c56iL5bCP5oCq'),
    (From-Base64Utf8 '6L+R5oiY57K+6Iux'),
    (From-Base64Utf8 '6L+c56iL57K+6Iux'),
    (From-Base64Utf8 '6L+R5oiYYm9zcw=='),
    (From-Base64Utf8 '6L+c56iLYm9zcw==')
)
$unitFieldNames = @('hp_max','hp_max_grow','mp_max','mp_max_grow','attack_phy','attack_phy_grow','attack_mag','defense_phy','defense_mag','attack_speed','attack_interval','ori_speed','turn_speed','sight_range','reward_exp','reward_official_res_1')
$validTargetRanks = @('normal', 'elite', 'boss')
$unitByKey = @{}
foreach ($unit in @($manifest.units)) {
    if ($unit.object_type -ne 'unit') { Add-Error $errors "$($unit.record_key): object_type must be unit" }
    if ($unit.status -ne 'reviewed' -or $unit.operation -ne 'create') { Add-Error $errors "$($unit.record_key): must remain reviewed/create" }
    if ($allowedUnitTypes -notcontains $unit.unit_type) { Add-Error $errors "$($unit.record_key): unsupported unit_type $($unit.unit_type)" }
    $unitObjectFields = Get-PropertyValue $unit 'object_fields'
    Add-ObjectFieldErrors $unitObjectFields $unitFieldSchema ([string]$unit.record_key) $errors
    foreach ($field in $unitFieldNames) {
        if ($null -eq (Get-ExactJsonProperty $unitObjectFields $field)) { Add-Error $errors "$($unit.record_key): missing unit object field $field" }
    }
    $rank = Get-PropertyValue $unit.runtime_fields 'target_rank'
    if ($validTargetRanks -notcontains $rank) { Add-Error $errors "$($unit.record_key): invalid target_rank $rank" }
    $unitByKey[$unit.record_key] = $unit
}

$profileByKey = @{}
foreach ($profileGroup in @('participation', 'break', 'mechanics', 'drop')) {
    foreach ($profile in @($manifest.runtime_profiles.$profileGroup)) {
        if ([string]::IsNullOrWhiteSpace([string]$profile.record_key)) { Add-Error $errors "runtime profile group $profileGroup has blank record_key"; continue }
        if ($objectByKey.ContainsKey($profile.record_key) -or $encounterByKey.ContainsKey($profile.record_key) -or $profileByKey.ContainsKey($profile.record_key)) {
            Add-Error $errors "duplicate global record_key: $($profile.record_key)"
        }
        else { $profileByKey[$profile.record_key] = $profile }
    }
}
foreach ($unit in @($manifest.units)) {
    foreach ($profileField in @('drop_profile', 'participation_profile', 'break_profile')) {
        $profileKey = Get-PropertyValue $unit.runtime_fields $profileField
        if ($profileKey -and -not $profileByKey.ContainsKey($profileKey)) { Add-Error $errors "$($unit.record_key): unknown $profileField $profileKey" }
    }
}
$abilityDefaults = $manifest.object_defaults.ability
$abilityDefaultFields = Get-PropertyValue $abilityDefaults 'object_fields'
Add-ObjectFieldErrors $abilityDefaultFields $abilityFieldSchema 'object_defaults.ability' $errors
$requiredAbilityFields = @('ability_max_level','ability_cast_type','ability_cast_point','ability_bw_point','is_immediate','is_meele','cold_down_time','ability_cost','ability_hp_cost','ability_damage','required_level','sight_type')
$abilityByKey = @{}
foreach ($ability in @($manifest.abilities)) {
    if ($ability.object_type -ne 'ability') { Add-Error $errors "$($ability.record_key): object_type must be ability" }
    $abilityObjectFields = Get-PropertyValue $ability 'object_fields'
    Add-ObjectFieldErrors $abilityObjectFields $abilityFieldSchema ([string]$ability.record_key) $errors
    $fields = Get-MergedFields $abilityDefaultFields $abilityObjectFields
    $mergedFields = [pscustomobject]$fields
    foreach ($field in $requiredAbilityFields) {
        if ($null -eq (Get-ExactJsonProperty $mergedFields $field)) { Add-Error $errors "$($ability.record_key): missing merged ability field $field" }
    }
    Add-AbilityLevelArrayErrors $mergedFields ([string]$ability.record_key) $abilityLevelArrayFields $errors
    foreach ($ownerKey in @($ability.owner_keys)) {
        if (-not $unitByKey.ContainsKey($ownerKey)) { Add-Error $errors "$($ability.record_key): unknown owner $ownerKey"; continue }
        if (@($unitByKey[$ownerKey].common_ability_keys) -notcontains $ability.record_key) { Add-Error $errors "$($ability.record_key): owner $ownerKey does not bind this ability" }
    }
    foreach ($dependencyKey in @($ability.dependency_keys)) {
        if (-not $objectByKey.ContainsKey($dependencyKey)) { Add-Error $errors "$($ability.record_key): unknown dependency $dependencyKey" }
    }
    $runtime = $ability.runtime_fields
    Assert-RequiredProperties $runtime @('kind', 'target_scope') "$($ability.record_key): runtime_fields" $errors
    $abilityByKey[$ability.record_key] = $ability
}

foreach ($unit in @($manifest.units)) {
    foreach ($abilityKey in @($unit.common_ability_keys)) {
        if (-not $abilityByKey.ContainsKey($abilityKey)) { Add-Error $errors "$($unit.record_key): unknown common ability $abilityKey"; continue }
        if (@($abilityByKey[$abilityKey].owner_keys) -notcontains $unit.record_key) { Add-Error $errors "$($unit.record_key): ability $abilityKey does not list unit as owner" }
    }
}

foreach ($mechanic in @($manifest.runtime_profiles.mechanics)) {
    Assert-RequiredProperties $mechanic @('record_key','encounter_key','trigger_ability_key','target_scope','purge_contract','alternative_resolution','contribution_rule') 'mechanic profile' $errors
    if (-not $encounterByKey.ContainsKey($mechanic.encounter_key)) { Add-Error $errors "$($mechanic.record_key): unknown encounter $($mechanic.encounter_key)" }
    if (-not $abilityByKey.ContainsKey($mechanic.trigger_ability_key)) { Add-Error $errors "$($mechanic.record_key): unknown trigger ability $($mechanic.trigger_ability_key)" }
}

$modifierDefaults = $manifest.object_defaults.modifier
$modifierDefaultFields = Get-PropertyValue $modifierDefaults 'object_fields'
Add-ObjectFieldErrors $modifierDefaultFields $modifierFieldSchema 'object_defaults.modifier' $errors
$modifierByKey = @{}
foreach ($modifier in @($manifest.modifiers)) {
    if ($modifier.object_type -ne 'modifier') { Add-Error $errors "$($modifier.record_key): object_type must be modifier" }
    $modifierObjectFields = Get-PropertyValue $modifier 'object_fields'
    Add-ObjectFieldErrors $modifierObjectFields $modifierFieldSchema ([string]$modifier.record_key) $errors
    $fields = Get-MergedFields $modifierDefaultFields $modifierObjectFields
    foreach ($field in @('modifier_type','modifier_effect','layer_max','disappear_when_dead','show_on_ui')) {
        if (-not (Test-OrdinalMapKey $fields $field)) { Add-Error $errors "$($modifier.record_key): missing merged modifier field $field" }
    }
    $modifierByKey[$modifier.record_key] = $modifier
}

$projectileDefaults = $manifest.object_defaults.projectile
$projectileDefaultFields = Get-PropertyValue $projectileDefaults 'object_fields'
Add-ObjectFieldErrors $projectileDefaultFields $projectileFieldSchema 'object_defaults.projectile' $errors
$projectileByKey = @{}
foreach ($projectile in @($manifest.projectiles)) {
    if ($projectile.object_type -ne 'projectile') { Add-Error $errors "$($projectile.record_key): object_type must be projectile" }
    $projectileObjectFields = Get-PropertyValue $projectile 'object_fields'
    Add-ObjectFieldErrors $projectileObjectFields $projectileFieldSchema ([string]$projectile.record_key) $errors
    $fields = Get-MergedFields $projectileDefaultFields $projectileObjectFields
    foreach ($field in @('max_duration','move_channel','move_limitation','sfx_loop')) {
        if (-not (Test-OrdinalMapKey $fields $field)) { Add-Error $errors "$($projectile.record_key): missing merged projectile field $field" }
    }
    $projectileByKey[$projectile.record_key] = $projectile
}

$layoutResourceKeys = @{}
$layoutResourceMetadata = @{}
foreach ($resource in @($layout.logicResources)) {
    if ($resource.id) {
        $layoutResourceKeys[$resource.id] = $true
        $layoutResourceMetadata[$resource.id] = [pscustomobject]@{ source = 'logic_resource'; expected_type = [string]$resource.type }
    }
}
foreach ($resource in @($layout.bossZones)) {
    if ($resource.id) {
        $layoutResourceKeys[$resource.id] = $true
        $layoutResourceMetadata[$resource.id] = [pscustomobject]@{ source = 'boss_zone'; expected_type = 'boss_zone' }
    }
}
foreach ($resource in @($layout.spawns)) {
    if ($resource.id) {
        $layoutResourceKeys[$resource.id] = $true
        $layoutResourceMetadata[$resource.id] = [pscustomobject]@{ source = 'spawn'; expected_type = 'spawn_anchor' }
    }
}

$bindingPropertyNames = @(
    'package','schema_version','status','runtime_contract_id','source_layout_relpath',
    'real_map_binding_verified','production_ids_ready','instance_map_contract_verified',
    'instance_contract_role_schema','encounter_instance_map_states','return_points',
    'encounter_resource_bindings','instance_map_contracts','spawn_bindings','encounter_action_bindings'
)
Assert-ExactProperties $binding $bindingPropertyNames 'map logic binding' $errors
if ($binding.package -ne 'huaguoshan-map-logic-binding' -or $binding.schema_version -ne 5) { Add-Error $errors 'map logic binding package or schema is invalid' }
if ($binding.status -ne 'offline-declared-public-map-contract-complete-instance-map-contract-pending') { Add-Error $errors 'map logic binding must remain public-contract-complete and instance-contract-pending' }
if ($binding.source_layout_relpath -ne $layoutRelativePath) { Add-Error $errors 'map logic binding source layout path is invalid' }
foreach ($name in @('real_map_binding_verified','production_ids_ready','instance_map_contract_verified')) {
    $property = $binding.PSObject.Properties[$name]
    if ($null -ne $property -and $property.Value -isnot [bool]) { Add-Error $errors "map logic binding property must be boolean: $name" }
}
if (($binding.real_map_binding_verified -is [bool] -and $binding.real_map_binding_verified -ne $false) -or
    ($binding.production_ids_ready -is [bool] -and $binding.production_ids_ready -ne $false)) { Add-Error $errors 'map logic binding may not claim editor or production readiness' }
if ($runtimePackage -and $binding.runtime_contract_id -ne $runtimePackage.runtime_contract_id) { Add-Error $errors 'map logic binding runtime contract does not match manifest' }
if ($runtimePackage) {
    foreach ($name in @('real_map_binding_verified','production_ids_ready','instance_map_contract_verified')) {
        $runtimeProperty = $runtimePackage.PSObject.Properties[$name]
        $bindingProperty = $binding.PSObject.Properties[$name]
        if ($null -ne $runtimeProperty -and $null -ne $bindingProperty -and
            $runtimeProperty.Value -is [bool] -and $bindingProperty.Value -is [bool] -and
            $runtimeProperty.Value -ne $bindingProperty.Value) {
            Add-Error $errors "map logic binding $name gate does not match manifest runtime package"
        }
    }
}

$bindingArrays = @{}
foreach ($name in @('return_points','encounter_resource_bindings','spawn_bindings','encounter_action_bindings')) {
    $property = $binding.PSObject.Properties[$name]
    $bindingArrays[$name] = @()
    if ($null -eq $property -or -not (Test-JsonArray $property.Value)) {
        Add-Error $errors "map logic binding $name must be an array"
    }
    else { $bindingArrays[$name] = @($property.Value) }
}
$returnPointBindings = @($bindingArrays['return_points'])
$encounterResourceBindings = @($bindingArrays['encounter_resource_bindings'])
$spawnBindings = @($bindingArrays['spawn_bindings'])
$encounterActionBindings = @($bindingArrays['encounter_action_bindings'])
Add-CanonicalPublicBossBindingErrors $spawnBindings $encounterResourceBindings 'map logic binding' $errors

if ($null -ne $luaProjection) {
    $luaProjectionPropertyNames = @(
        'runtime_contract_id','editor_bound','instance_map_contract_verified','return_points',
        'encounter_resource_bindings','spawn_bindings','encounter_action_bindings',
        'encounter_instance_map_states','instance_contract_role_schema','instance_map_contracts'
    )
    Assert-ExactProperties $luaProjection $luaProjectionPropertyNames 'Lua Config projection' $errors
    $luaRuntimeContractProperty = $luaProjection.PSObject.Properties['runtime_contract_id']
    if ($null -ne $luaRuntimeContractProperty) {
        if (-not (Test-NonEmptyTrimmedString $luaRuntimeContractProperty.Value)) {
            Add-Error $errors 'Lua Config runtime_contract_id must be a non-empty trimmed string'
        }
        elseif ((Test-NonEmptyTrimmedString $binding.runtime_contract_id) -and
            $luaRuntimeContractProperty.Value -ne $binding.runtime_contract_id) {
            Add-Error $errors 'Lua Config runtime contract does not match map logic binding'
        }
    }
    $luaEditorBoundProperty = $luaProjection.PSObject.Properties['editor_bound']
    if ($null -ne $luaEditorBoundProperty) {
        if ($luaEditorBoundProperty.Value -isnot [bool]) {
            Add-Error $errors 'Lua Config editor_bound gate must be boolean'
        }
        elseif ($binding.real_map_binding_verified -is [bool] -and
            $luaEditorBoundProperty.Value -ne $binding.real_map_binding_verified) {
            Add-Error $errors 'Lua Config editor_bound gate does not match map logic binding'
        }
    }
    $luaInstanceGateProperty = $luaProjection.PSObject.Properties['instance_map_contract_verified']
    if ($null -ne $luaInstanceGateProperty) {
        if ($luaInstanceGateProperty.Value -isnot [bool]) {
            Add-Error $errors 'Lua Config instance_map_contract_verified gate must be boolean'
        }
        elseif ($binding.instance_map_contract_verified -is [bool] -and
            $luaInstanceGateProperty.Value -ne $binding.instance_map_contract_verified) {
            Add-Error $errors 'Lua Config instance_map_contract_verified gate does not match map logic binding'
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
        $luaProperty = $luaProjection.PSObject.Properties[$name]
        $bindingProperty = $binding.PSObject.Properties[$name]
        if ($null -ne $luaProperty -and -not (Test-JsonArray $luaProperty.Value)) {
            Add-Error $errors "Lua Config projection $name must be an array"
        }
        if ($null -ne $luaProperty -and $null -ne $bindingProperty -and
            (Test-JsonArray $luaProperty.Value) -and (Test-JsonArray $bindingProperty.Value)) {
            $luaValue = $luaProperty.Value
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
            if ((Get-CanonicalJson $luaValue) -ne (Get-CanonicalJson $bindingValue)) {
                Add-Error $errors $luaProjectionArrayMessages[$name]
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
    Add-Error $errors 'map logic binding instance_contract_role_schema must be an array'
}
else { $instanceRoleSchemas = @($instanceRoleSchemaProperty.Value) }
if ($instanceRoleSchemas.Count -eq 0) { Add-Error $errors 'map logic binding instance_contract_role_schema must not be empty' }

$roleSchemaByContract = @{}
foreach ($schema in $instanceRoleSchemas) {
    if ($schema -isnot [pscustomobject]) {
        Add-Error $errors 'instance contract role schema must be an object'
        continue
    }
    Assert-ExactProperties $schema $instanceRoleSchemaFields 'instance contract role schema' $errors
    $contractKey = Get-PropertyValue $schema 'contract_key'
    if (-not (Test-NonEmptyTrimmedString $contractKey)) {
        Add-Error $errors 'instance contract role schema has invalid contract_key'
        continue
    }
    if ($roleSchemaByContract.ContainsKey($contractKey)) {
        Add-Error $errors "duplicate instance contract role schema for $contractKey"
        continue
    }
    if (-not $expectedInstanceEncounterKeysByContract.ContainsKey($contractKey)) {
        Add-Error $errors "instance contract role schema has unknown contract key $contractKey"
    }
    $expectedSchema = $expectedInstanceRoleSchemaByContract[$contractKey]
    $layer = Get-PropertyValue $schema 'layer'
    if (-not (Test-NonEmptyTrimmedString $layer)) {
        Add-Error $errors "instance contract role schema has invalid layer for $contractKey"
    }
    elseif ($null -ne $expectedSchema -and $layer -ne $expectedSchema.layer) {
        Add-Error $errors "instance contract role schema layer is not canonical for $contractKey"
    }
    $slotCount = Get-PropertyValue $schema 'slot_count'
    if (-not (Test-PositiveInteger $slotCount)) {
        Add-Error $errors "instance contract role schema slot_count must be a positive integer for $contractKey"
    }
    elseif ($null -ne $expectedSchema -and $slotCount -ne $expectedSchema.slot_count) {
        Add-Error $errors "instance contract role schema slot_count is not canonical for $contractKey"
    }
    $rolesProperty = $schema.PSObject.Properties['roles']
    $rolesValue = if ($null -eq $rolesProperty) { $null } else { $rolesProperty.Value }
    $roles = @()
    if (-not (Test-JsonArray $rolesValue)) {
        Add-Error $errors "instance contract role schema roles must be an array for $contractKey"
    }
    else { $roles = @($rolesValue) }
    if ($roles.Count -eq 0) { Add-Error $errors "instance contract role schema roles must not be empty for $contractKey" }
    $roleTypes = @{}
    foreach ($role in $roles) {
        if ($role -isnot [pscustomobject]) {
            Add-Error $errors "instance contract role schema role must be an object for $contractKey"
            continue
        }
        Assert-ExactProperties $role $instanceRoleSchemaRoleFields "instance contract role schema role for $contractKey" $errors
        $roleName = Get-PropertyValue $role 'role'
        $expectedType = Get-PropertyValue $role 'expected_type'
        if (-not (Test-NonEmptyTrimmedString $roleName) -or $roleTypes.ContainsKey($roleName)) {
            Add-Error $errors "instance contract role schema role is invalid or duplicate for $contractKey"
            continue
        }
        if ($null -ne $expectedSchema -and -not $expectedSchema.roles.ContainsKey($roleName)) {
            Add-Error $errors "instance contract role schema role is not canonical for ${contractKey}:$roleName"
            continue
        }
        if ($expectedType -notin @('point','rectArea')) {
            Add-Error $errors "instance contract role schema expected_type is invalid for ${contractKey}:$roleName"
            continue
        }
        if ($null -ne $expectedSchema -and $expectedType -ne $expectedSchema.roles[$roleName]) {
            Add-Error $errors "instance contract role schema expected_type is not canonical for ${contractKey}:$roleName"
            continue
        }
        $roleTypes[$roleName] = $expectedType
    }
    if ($null -ne $expectedSchema) {
        if ($roleTypes.Count -ne $expectedSchema.roles.Count) {
            Add-Error $errors "instance contract role schema roles must exactly match canonical roles for $contractKey"
        }
        foreach ($expectedRole in $expectedSchema.roles.Keys) {
            if (-not $roleTypes.ContainsKey($expectedRole)) {
                Add-Error $errors "instance contract role schema is missing canonical role for ${contractKey}:$expectedRole"
            }
        }
    }
    $roleSchemaByContract[$contractKey] = [pscustomobject]@{ layer = $layer; slot_count = $slotCount; roles = $roleTypes }
}
foreach ($expectedContractKey in $expectedInstanceEncounterKeysByContract.Keys) {
    if (-not $roleSchemaByContract.ContainsKey($expectedContractKey)) {
        Add-Error $errors "map logic binding missing instance contract role schema $expectedContractKey"
    }
}

$encounterMapStates = @()
$encounterMapStatesProperty = $binding.PSObject.Properties['encounter_instance_map_states']
if ($null -eq $encounterMapStatesProperty -or -not (Test-JsonArray $encounterMapStatesProperty.Value)) {
    Add-Error $errors 'map logic binding encounter_instance_map_states must be an array'
}
else { $encounterMapStates = @($encounterMapStatesProperty.Value) }

$encounterMapStateByKey = @{}
foreach ($item in $encounterMapStates) {
    if ($item -isnot [pscustomobject]) {
        Add-Error $errors 'encounter instance map state must be an object'
        continue
    }
    Assert-ExactProperties $item $instanceStateFields 'encounter instance map state' $errors
    $encounterKey = Get-PropertyValue $item 'encounter_key'
    $contractKey = Get-PropertyValue $item 'contract_key'
    $state = Get-PropertyValue $item 'state'
    $slotCount = Get-PropertyValue $item 'slot_count'
    if (-not (Test-NonEmptyTrimmedString $encounterKey)) {
        Add-Error $errors 'encounter instance map state has invalid encounter_key'
        continue
    }
    if ($encounterMapStateByKey.ContainsKey($encounterKey)) {
        Add-Error $errors "duplicate encounter instance map state for $encounterKey"
        continue
    }
    $encounterMapStateByKey[$encounterKey] = $item
    if (-not (Test-NonEmptyTrimmedString $contractKey)) {
        Add-Error $errors "encounter instance map state has invalid contract_key for $encounterKey"
    }
    elseif (-not $expectedInstanceEncounterKeysByContract.ContainsKey($contractKey)) {
        Add-Error $errors "encounter instance map state references unknown contract key $contractKey"
    }
    if ($state -notin @('pending','verified')) {
        Add-Error $errors "encounter instance map state has invalid state for ${encounterKey}: $state"
    }
    if (-not (Test-PositiveInteger $slotCount)) {
        Add-Error $errors "encounter instance map state has invalid slot_count for $encounterKey"
    }
    $encounter = $encounterByKey[$encounterKey]
    if ($null -eq $encounter) {
        Add-Error $errors "encounter instance map state references unknown encounter $encounterKey"
    }
    elseif ($encounter.combat_scope -notin @('solo_instance','team_instance')) {
        Add-Error $errors "encounter instance map state references non-instance encounter $encounterKey"
    }
    if ($expectedInstanceContractByEncounter.ContainsKey($encounterKey) -and
        $contractKey -ne $expectedInstanceContractByEncounter[$encounterKey]) {
        Add-Error $errors "${encounterKey}: encounter instance map state contract mapping is invalid"
    }
}

$instanceMapContracts = @()
$instanceMapContractsProperty = $binding.PSObject.Properties['instance_map_contracts']
if ($null -eq $instanceMapContractsProperty -or -not (Test-JsonArray $instanceMapContractsProperty.Value)) {
    Add-Error $errors 'map logic binding instance_map_contracts must be an array'
}
else { $instanceMapContracts = @($instanceMapContractsProperty.Value) }
if ($instanceMapContracts.Count -eq 0) { Add-Error $errors 'map logic binding instance_map_contracts must not be empty' }

$instanceContractByKey = @{}
$instanceContractKeyByEncounter = @{}
$pendingInstanceContracts = [System.Collections.Generic.List[string]]::new()
$verifiedInstanceRoleStableIds = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
$instanceRoleResourceOwners = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach ($contract in $instanceMapContracts) {
    if ($contract -isnot [pscustomobject]) {
        Add-Error $errors 'map logic binding instance map contract must be an object'
        continue
    }
    Assert-ExactProperties $contract $instanceContractFields 'instance map contract' $errors
    $contractKey = Get-PropertyValue $contract 'contract_key'
    if (-not (Test-NonEmptyTrimmedString $contractKey)) {
        Add-Error $errors 'map logic binding instance map contract has invalid contract_key'
        continue
    }
    if ($instanceContractByKey.ContainsKey($contractKey)) {
        Add-Error $errors "duplicate instance map contract key $contractKey"
        continue
    }
    $instanceContractByKey[$contractKey] = $contract
    if (-not $expectedInstanceEncounterKeysByContract.ContainsKey($contractKey)) {
        Add-Error $errors "unknown instance map contract key $contractKey"
    }
    $roleSchema = $roleSchemaByContract[$contractKey]

    $encounterKeysProperty = $contract.PSObject.Properties['encounter_keys']
    $encounterKeysValue = $null
    if ($null -ne $encounterKeysProperty) { $encounterKeysValue = $encounterKeysProperty.Value }
    $encounterKeys = @()
    if (-not (Test-JsonArray $encounterKeysValue)) {
        Add-Error $errors "instance map contract encounter_keys must be an array for $contractKey"
    }
    else { $encounterKeys = @($encounterKeysValue) }
    if ($encounterKeys.Count -eq 0) {
        Add-Error $errors "instance map contract encounter_keys must not be empty for $contractKey"
    }
    $localEncounterKeys = @{}
    foreach ($encounterKey in $encounterKeys) {
        if (-not (Test-NonEmptyTrimmedString $encounterKey)) {
            Add-Error $errors "instance map contract has invalid encounter key for $contractKey"
            continue
        }
        if ($localEncounterKeys.ContainsKey($encounterKey)) {
            Add-Error $errors "duplicate encounter key in instance map contract ${contractKey}: $encounterKey"
            continue
        }
        $localEncounterKeys[$encounterKey] = $true
        if ($instanceContractKeyByEncounter.ContainsKey($encounterKey)) {
            Add-Error $errors "instance encounter key is assigned to multiple contracts: $encounterKey"
        }
        else { $instanceContractKeyByEncounter[$encounterKey] = $contractKey }

        $encounter = $encounterByKey[$encounterKey]
        if ($null -eq $encounter) {
            Add-Error $errors "instance map contract references unknown encounter $encounterKey"
        }
        elseif ($encounter.combat_scope -notin @('solo_instance','team_instance')) {
            Add-Error $errors "instance map contract references non-instance encounter $encounterKey"
        }
        if ($expectedInstanceContractByEncounter.ContainsKey($encounterKey) -and
            $expectedInstanceContractByEncounter[$encounterKey] -ne $contractKey) {
            Add-Error $errors "${encounterKey}: canonical instance contract mapping must be $($expectedInstanceContractByEncounter[$encounterKey])"
        }
    }
    if ($expectedInstanceEncounterKeysByContract.ContainsKey($contractKey)) {
        foreach ($expectedEncounterKey in $expectedInstanceEncounterKeysByContract[$contractKey]) {
            if (-not $localEncounterKeys.ContainsKey($expectedEncounterKey)) {
                Add-Error $errors "instance map contract $contractKey is missing encounter $expectedEncounterKey"
            }
        }
    }

    $state = Get-PropertyValue $contract 'state'
    if ($state -notin @('pending','verified')) {
        Add-Error $errors "instance map contract has invalid state for ${contractKey}: $state"
    }
    elseif ($state -eq 'pending') { $pendingInstanceContracts.Add($contractKey) }
    $layer = Get-PropertyValue $contract 'layer'
    if (-not (Test-NonEmptyTrimmedString $layer)) {
        Add-Error $errors "instance map contract has invalid layer for $contractKey"
    }
    elseif ($null -ne $roleSchema -and $layer -ne $roleSchema.layer) {
        Add-Error $errors "instance map contract layer violates canonical role schema for $contractKey"
    }
    $slotCount = Get-PropertyValue $contract 'slot_count'
    if (-not (Test-PositiveInteger $slotCount)) {
        Add-Error $errors "instance map contract slot_count must be a positive integer for $contractKey"
    }
    elseif ($contractKey -eq 'HG_I_DRAGON_FOUR_SEAS' -and $slotCount -ne 4) {
        Add-Error $errors 'HG_I_DRAGON_FOUR_SEAS must declare exactly four slots'
    }
    elseif ($null -ne $roleSchema -and $slotCount -ne $roleSchema.slot_count) {
        Add-Error $errors "instance map contract slot_count violates canonical role schema for $contractKey"
    }
    $slotsProperty = $contract.PSObject.Properties['slots']
    $slotsValue = $null
    if ($null -ne $slotsProperty) { $slotsValue = $slotsProperty.Value }
    $slots = @()
    if (-not (Test-JsonArray $slotsValue)) {
        Add-Error $errors "instance map contract slots must be an array for $contractKey"
    }
    else { $slots = @($slotsValue) }
    if ($slots.Count -eq 0) { Add-Error $errors "instance map contract slots must not be empty for $contractKey" }
    if ((Test-PositiveInteger $slotCount) -and $slots.Count -ne $slotCount) {
        Add-Error $errors "instance map contract slots must match slot_count for $contractKey"
    }

    $slotIds = @{}
    foreach ($slot in $slots) {
        if ($slot -isnot [pscustomobject]) {
            Add-Error $errors "instance map contract slot must be an object for $contractKey"
            continue
        }
        Assert-ExactProperties $slot @('slot_id','roles') "instance map contract slot for $contractKey" $errors
        $slotId = Get-PropertyValue $slot 'slot_id'
        if (-not (Test-PositiveInteger $slotId) -or ((Test-PositiveInteger $slotCount) -and $slotId -gt $slotCount) -or $slotIds.ContainsKey([string]$slotId)) {
            Add-Error $errors "instance map contract has invalid or duplicate slot_id for ${contractKey}: $slotId"
            continue
        }
        $slotIds[[string]$slotId] = $true
        $rolesProperty = $slot.PSObject.Properties['roles']
        $rolesValue = $null
        if ($null -ne $rolesProperty) { $rolesValue = $rolesProperty.Value }
        $roles = @()
        if (-not (Test-JsonArray $rolesValue)) {
            Add-Error $errors "instance map contract slot roles must be an array for ${contractKey}:$slotId"
        }
        else { $roles = @($rolesValue) }
        if ($roles.Count -eq 0) {
            Add-Error $errors "instance map contract slot roles must not be empty for ${contractKey}:$slotId"
            continue
        }
        if ($null -ne $roleSchema -and $roles.Count -ne $roleSchema.roles.Count) {
            Add-Error $errors "instance map contract slot roles must exactly match canonical role schema for ${contractKey}:$slotId"
        }
        $roleNames = @{}
        foreach ($role in $roles) {
            if ($role -isnot [pscustomobject]) {
                Add-Error $errors "instance role must be an object for ${contractKey}:$slotId"
                continue
            }
            Assert-ExactProperties $role @('role','resource_key','source','expected_type','layer','stable_object_id') "instance role for ${contractKey}:$slotId" $errors
            $roleName = Get-PropertyValue $role 'role'
            $resourceKey = Get-PropertyValue $role 'resource_key'
            if (-not (Test-NonEmptyTrimmedString $roleName) -or $roleNames.ContainsKey($roleName)) {
                Add-Error $errors "instance role name is invalid or duplicate for ${contractKey}:$slotId"
            }
            else { $roleNames[$roleName] = $true }
            if ($null -ne $roleSchema -and (Test-NonEmptyTrimmedString $roleName)) {
                if (-not $roleSchema.roles.ContainsKey($roleName)) {
                    Add-Error $errors "instance role is not canonical for ${contractKey}:${slotId}:${roleName}"
                }
                elseif ((Get-PropertyValue $role 'expected_type') -ne $roleSchema.roles[$roleName]) {
                    Add-Error $errors "instance role expected_type violates canonical role schema for ${contractKey}:${slotId}:${roleName}"
                }
            }
            $owner = "${contractKey}:${slotId}:$roleName"
            if (-not (Test-NonEmptyTrimmedString $resourceKey)) {
                Add-Error $errors "instance role resource_key is invalid for $owner"
            }
            elseif ($instanceRoleResourceOwners.ContainsKey($resourceKey)) {
                Add-Error $errors "instance role resource_key is not globally unique: $resourceKey"
            }
            else { $instanceRoleResourceOwners[$resourceKey] = $owner }
            if ((Get-PropertyValue $role 'source') -ne 'instance_logic_resource') { Add-Error $errors "instance role source is invalid for $owner" }
            if ((Get-PropertyValue $role 'expected_type') -notin @('point','rectArea')) { Add-Error $errors "instance role expected_type is invalid for $owner" }
            if ((Get-PropertyValue $role 'layer') -ne $layer) { Add-Error $errors "instance role layer differs from contract for $owner" }
            $stableId = Get-PropertyValue $role 'stable_object_id'
            if ($state -eq 'pending' -and ($stableId -isnot [bool] -or $stableId)) {
                Add-Error $errors "pending instance role must not claim stable_object_id for $owner"
            }
            elseif ($state -eq 'verified') {
                if (-not (Test-StableObjectId $stableId)) { Add-Error $errors "verified instance role requires stable_object_id for $owner" }
                else {
                    $stableKey = $stableId.GetType().FullName + ':' + [string]$stableId
                    if ($verifiedInstanceRoleStableIds.ContainsKey($stableKey)) {
                        Add-Error $errors "verified instance role stable_object_id is not globally unique: $stableId"
                    }
                    else { $verifiedInstanceRoleStableIds[$stableKey] = $owner }
                }
            }
        }
        if ($null -ne $roleSchema) {
            foreach ($requiredRoleName in $roleSchema.roles.Keys) {
                if (-not $roleNames.ContainsKey($requiredRoleName)) {
                    Add-Error $errors "instance map contract slot is missing canonical role for ${contractKey}:${slotId}:${requiredRoleName}"
                }
            }
        }
    }
}

foreach ($expectedContractKey in $expectedInstanceEncounterKeysByContract.Keys) {
    if (-not $instanceContractByKey.ContainsKey($expectedContractKey)) {
        Add-Error $errors "map logic binding missing canonical instance map contract $expectedContractKey"
    }
}
foreach ($encounter in @($manifest.encounters | Where-Object { $_.combat_scope -in @('solo_instance','team_instance') })) {
    $encounterKey = $encounter.record_key
    if (-not $instanceContractKeyByEncounter.ContainsKey($encounterKey)) {
        Add-Error $errors "map logic binding missing instance map contract mapping for $encounterKey"
        continue
    }
    $contractKey = $instanceContractKeyByEncounter[$encounterKey]
    $contract = $instanceContractByKey[$contractKey]
    $projection = $encounterMapStateByKey[$encounterKey]
    if ($null -eq $contract) {
        Add-Error $errors "${encounterKey}: mapped instance contract is unavailable: $contractKey"
        continue
    }
    if ($null -eq $projection) {
        Add-Error $errors "map logic binding missing encounter instance map state for $encounterKey"
        continue
    }
    if ($projection.contract_key -ne $contractKey) {
        Add-Error $errors "${encounterKey}: encounter instance map state contract differs from declared contract mapping"
    }
    if ($projection.state -ne $contract.state) {
        Add-Error $errors "${encounterKey}: encounter instance map state differs from instance contract"
    }
    if ($projection.slot_count -ne $contract.slot_count) {
        Add-Error $errors "${encounterKey}: encounter instance map state slot_count differs from instance contract"
    }
    if ($encounter.runtime_fields.map_binding_state -ne $contract.state) {
        Add-Error $errors "${encounterKey}: manifest map_binding_state differs from instance contract"
    }
    $manifestSlotsProperty = $encounter.runtime_fields.PSObject.Properties['instance_slots']
    if ($encounter.combat_scope -eq 'solo_instance') {
        if ($null -eq $manifestSlotsProperty -or -not (Test-PositiveInteger $manifestSlotsProperty.Value)) {
            Add-Error $errors "${encounterKey}: manifest instance_slots must be a positive integer"
        }
        elseif ($manifestSlotsProperty.Value -ne $contract.slot_count) {
            Add-Error $errors "${encounterKey}: manifest instance_slots does not match instance map contract"
        }
    }
}
foreach ($encounterKey in $encounterMapStateByKey.Keys) {
    $projection = $encounterMapStateByKey[$encounterKey]
    if (-not $instanceContractByKey.ContainsKey($projection.contract_key)) {
        Add-Error $errors "encounter instance map state references undeclared contract $($projection.contract_key)"
    }
    elseif (-not $instanceContractKeyByEncounter.ContainsKey($encounterKey) -or
        $instanceContractKeyByEncounter[$encounterKey] -ne $projection.contract_key) {
        Add-Error $errors "${encounterKey}: encounter instance map state does not match contract encounter_keys"
    }
}

$allInstanceContractsVerified =
    $instanceMapContracts.Count -eq $expectedInstanceEncounterKeysByContract.Count -and
    $pendingInstanceContracts.Count -eq 0 -and
    $errors.Count -eq $instanceValidationErrorStart
if ($binding.instance_map_contract_verified -is [bool]) {
    if ($binding.instance_map_contract_verified -and $pendingInstanceContracts.Count -gt 0) {
        Add-Error $errors "map logic binding instance_map_contract_verified cannot be true while pending instance map contracts remain: $($pendingInstanceContracts -join ',')"
    }
    elseif ($binding.instance_map_contract_verified -and -not $allInstanceContractsVerified) {
        Add-Error $errors 'map logic binding instance_map_contract_verified cannot be true unless all canonical instance map contracts are verified'
    }
    elseif (-not $binding.instance_map_contract_verified -and $allInstanceContractsVerified) {
        Add-Error $errors 'map logic binding instance_map_contract_verified must be true when all instance map contracts are verified'
    }
}

$manifestResourcePairs = @{}
$manifestResourceRoles = @{}
$manifestResourcesByEncounterRole = @{}
foreach ($encounter in @($manifest.encounters)) {
    $encounterKey = [string]$encounter.record_key
    $resourceKeysProperty = $encounter.PSObject.Properties['map_logic_resource_keys']
    $resourceKeys = @()
    if ($null -eq $resourceKeysProperty -or -not (Test-JsonArray $resourceKeysProperty.Value)) {
        Add-Error $errors "${encounterKey}: map_logic_resource_keys must be an array"
    }
    else { $resourceKeys = @($resourceKeysProperty.Value) }

    $rolesProperty = $encounter.PSObject.Properties['map_logic_resource_roles']
    $roles = if ($null -eq $rolesProperty) { $null } else { $rolesProperty.Value }
    if ($null -eq $roles -or $roles -isnot [pscustomobject]) {
        Add-Error $errors "${encounterKey}: map_logic_resource_roles must be an object"
        $roles = [pscustomobject]@{}
    }

    $localResourceKeys = @{}
    foreach ($resourceKey in $resourceKeys) {
        if (-not (Test-NonEmptyTrimmedString $resourceKey)) {
            Add-Error $errors "${encounterKey}: map logic resource key must be a non-empty trimmed string"
            continue
        }
        if ($localResourceKeys.ContainsKey($resourceKey)) {
            Add-Error $errors "${encounterKey}: duplicate map logic resource key $resourceKey"
            continue
        }
        $localResourceKeys[$resourceKey] = $true
        $pairKey = "$encounterKey|$resourceKey"
        $manifestResourcePairs[$pairKey] = $true
        $roleProperty = $roles.PSObject.Properties[$resourceKey]
        if ($null -eq $roleProperty -or -not (Test-NonEmptyTrimmedString $roleProperty.Value)) {
            Add-Error $errors "${encounterKey}: missing or invalid map logic resource role for $resourceKey"
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
        if (-not $layoutResourceMetadata.ContainsKey($resourceKey)) {
            Add-Error $errors "${encounterKey}: manifest references unknown layout resource $resourceKey"
        }
    }
    foreach ($roleProperty in $roles.PSObject.Properties) {
        if (-not $localResourceKeys.ContainsKey($roleProperty.Name)) {
            Add-Error $errors "${encounterKey}: map logic resource role has no declared key $($roleProperty.Name)"
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

$bindingResourcePairs = @{}
foreach ($item in $encounterResourceBindings) {
    if ($item -isnot [pscustomobject]) {
        Add-Error $errors 'encounter resource binding must be an object'
        continue
    }
    Assert-ExactProperties $item @('encounter_key','resource_key','source','expected_type','role') 'encounter resource binding' $errors
    foreach ($field in @('encounter_key','resource_key','source','expected_type','role')) {
        if (-not (Test-NonEmptyTrimmedString $item.$field)) { Add-Error $errors "encounter resource binding has invalid $field" }
    }
    if (-not (Test-NonEmptyTrimmedString $item.role)) {
        Add-Error $errors "map binding resource role must be a non-empty string for $($item.encounter_key)|$($item.resource_key)"
    }
    if (-not (Test-NonEmptyTrimmedString $item.encounter_key) -or -not (Test-NonEmptyTrimmedString $item.resource_key)) { continue }
    if (-not $encounterByKey.ContainsKey($item.encounter_key)) { Add-Error $errors "map binding references unknown encounter $($item.encounter_key)"; continue }
    $pairKey = "$($item.encounter_key)|$($item.resource_key)"
    if ($bindingResourcePairs.ContainsKey($pairKey)) { Add-Error $errors "duplicate map binding resource pair $pairKey" }
    else { $bindingResourcePairs[$pairKey] = $item }
    $roleContract = $encounterResourceRoleContracts[$item.role]
    if ($null -eq $roleContract) {
        Add-Error $errors "encounter resource binding has invalid role: $($item.role)"
    }
    elseif ($item.source -ne $roleContract.source -or $roleContract.expected_types -notcontains $item.expected_type) {
        Add-Error $errors "encounter resource binding role contract is invalid for $pairKey"
    }
    if (-not $manifestResourcePairs.ContainsKey($pairKey)) {
        Add-Error $errors "map logic binding declares resource absent from manifest: $pairKey"
    }
    elseif ($manifestResourceRoles.ContainsKey($pairKey) -and $item.role -ne $manifestResourceRoles[$pairKey]) {
        Add-Error $errors "manifest resource role differs from map logic binding for $pairKey"
    }
    $actual = $layoutResourceMetadata[$item.resource_key]
    if ($null -eq $actual) { Add-Error $errors "map binding references unknown layout resource $($item.resource_key)" }
    elseif ($item.source -ne $actual.source -or $item.expected_type -ne $actual.expected_type) {
        Add-Error $errors "map binding type mismatch for $($item.resource_key)"
    }
}
foreach ($pairKey in $manifestResourcePairs.Keys) {
    if (-not $bindingResourcePairs.ContainsKey($pairKey)) {
        $parts = $pairKey.Split('|', 2)
        Add-Error $errors "$($parts[0]): map logic binding omits declared resource $($parts[1])"
    }
}

$expectedReturnPoints = @{ spawn = 'pt_hg_spawn'; city = 'pt_hg_teleport_city'; hub = 'pt_hg_teleport_hub'; team = 'pt_hg_teleport_team' }
if ($returnPointBindings.Count -ne $expectedReturnPoints.Count) {
    Add-Error $errors "map logic binding return_points must contain exactly $($expectedReturnPoints.Count) entries"
}
$returnRoles = @{}
$returnResources = @{}
foreach ($item in $returnPointBindings) {
    if ($item -isnot [pscustomobject]) {
        Add-Error $errors 'return point must be an object'
        continue
    }
    Assert-ExactProperties $item @('role','resource_key','source','expected_type') 'return point' $errors
    foreach ($field in @('role','resource_key','source','expected_type')) {
        if (-not (Test-NonEmptyTrimmedString $item.$field)) { Add-Error $errors "return point has invalid $field" }
    }
    if (-not (Test-NonEmptyTrimmedString $item.role)) { continue }
    if (-not $expectedReturnPoints.ContainsKey($item.role)) {
        Add-Error $errors "return point has invalid role: $($item.role)"
    }
    if ($returnRoles.ContainsKey($item.role)) { Add-Error $errors "duplicate return point role: $($item.role)" }
    else { $returnRoles[$item.role] = $true }
    if (Test-NonEmptyTrimmedString $item.resource_key) {
        if ($returnResources.ContainsKey($item.resource_key)) { Add-Error $errors "duplicate return point resource_key: $($item.resource_key)" }
        else { $returnResources[$item.resource_key] = $true }
    }
    if ($item.source -ne 'logic_resource' -or $item.expected_type -ne 'point') {
        Add-Error $errors "return point source/type is invalid for role $($item.role)"
    }
    if ($expectedReturnPoints.ContainsKey($item.role) -and $item.resource_key -ne $expectedReturnPoints[$item.role]) {
        Add-Error $errors "return point resource is invalid for role $($item.role)"
    }
    $actual = $layoutResourceMetadata[$item.resource_key]
    if ($null -eq $actual -or $actual.source -ne 'logic_resource' -or $actual.expected_type -ne 'point') {
        Add-Error $errors "return point does not resolve to a logic point for role $($item.role)"
    }
}
foreach ($role in $expectedReturnPoints.Keys) {
    if (-not $returnRoles.ContainsKey($role)) { Add-Error $errors "map logic binding return point is missing for role $role" }
}

$expectedSpawnPairs = @{}
foreach ($encounter in @($manifest.encounters)) {
    if ($encounter.combat_scope -ne 'public') { continue }
    $encounterKey = [string]$encounter.record_key
    $anchors = @()
    $units = @()
    $anchorProperty = $encounter.runtime_fields.PSObject.Properties['spawn_anchors']
    if ($null -ne $anchorProperty) {
        if (-not (Test-JsonArray $anchorProperty.Value)) {
            Add-Error $errors "${encounterKey}: spawn_anchors must be an array"
        }
        else { $anchors = @($anchorProperty.Value) }
        $spawnUnitsProperty = $encounter.PSObject.Properties['spawn_unit_keys']
        if ($null -eq $spawnUnitsProperty -or -not (Test-JsonArray $spawnUnitsProperty.Value)) {
            Add-Error $errors "${encounterKey}: spawn_unit_keys must be an array when spawn_anchors are declared"
        }
        else { $units = @($spawnUnitsProperty.Value) }
    }
    elseif ($encounter.encounter_type -in @('public_trace','public_elite')) {
        $anchorRole = if ($encounter.encounter_type -eq 'public_trace') { 'trace_carrier_anchor' } else { 'optional_elite_arena' }
        $anchors = @($manifestResourcesByEncounterRole["$encounterKey|$anchorRole"])
        if ($anchors.Count -ne 1) { Add-Error $errors "${encounterKey}: $anchorRole must resolve to exactly one spawn anchor" }
        $spawnUnitsProperty = $encounter.PSObject.Properties['spawn_unit_keys']
        if ($null -eq $spawnUnitsProperty -or -not (Test-JsonArray $spawnUnitsProperty.Value)) {
            Add-Error $errors "${encounterKey}: spawn_unit_keys must be an array"
        }
        else { $units = @($spawnUnitsProperty.Value) }
        if ($units.Count -ne 1) { Add-Error $errors "${encounterKey}: $($encounter.encounter_type) must declare exactly one spawn unit" }
    }
    elseif ($encounter.encounter_type -eq 'public_boss') {
        $anchors = @($manifestResourcesByEncounterRole["$encounterKey|boss_arena"])
        if ($anchors.Count -ne 1) { Add-Error $errors "${encounterKey}: boss_arena must resolve to exactly one resource" }
        if (-not (Test-NonEmptyTrimmedString $encounter.boss_unit_key)) {
            Add-Error $errors "${encounterKey}: public boss must declare boss_unit_key"
        }
        else {
            $bossUnitKey = [string]$encounter.boss_unit_key
            $units = @($bossUnitKey)
            if (-not $canonicalPublicBossByEncounter.ContainsKey($encounterKey)) {
                Add-Error $errors "manifest ${encounterKey}: public boss has no canonical identity"
            }
            else {
                $canonicalBoss = $canonicalPublicBossByEncounter[$encounterKey]
                if ($bossUnitKey -cne $canonicalBoss.UnitKey) {
                    Add-Error $errors "manifest ${encounterKey}: canonical public boss tuple must be $($canonicalBoss.UnitKey) -> $($canonicalBoss.ArenaKey)"
                }
                if ($anchors.Count -eq 1 -and $anchors[0] -cne $canonicalBoss.ArenaKey) {
                    Add-Error $errors "${encounterKey}: public boss spawn anchor must match encounter boss_arena $($canonicalBoss.ArenaKey)"
                }
            }
        }
    }
    else {
        Add-Error $errors "${encounterKey}: unsupported public encounter spawn projection $($encounter.encounter_type)"
    }
    if ($anchors.Count -ne $units.Count) { Add-Error $errors "${encounterKey}: spawn anchors and unit keys must have matching counts" }
    for ($index = 0; $index -lt [Math]::Min($anchors.Count, $units.Count); $index++) {
        $anchorKey = $anchors[$index]
        $unitKey = $units[$index]
        if (-not (Test-NonEmptyTrimmedString $anchorKey) -or -not (Test-NonEmptyTrimmedString $unitKey)) {
            Add-Error $errors "${encounterKey}: spawn projection has an invalid anchor or unit key"
            continue
        }
        $pairKey = "$encounterKey|$anchorKey|$unitKey"
        if ($expectedSpawnPairs.ContainsKey($pairKey)) { Add-Error $errors "duplicate expected spawn binding $pairKey" }
        else { $expectedSpawnPairs[$pairKey] = $true }
    }
}

if ($spawnBindings.Count -ne $expectedSpawnPairs.Count) {
    Add-Error $errors "map logic binding spawn_bindings must contain exactly $($expectedSpawnPairs.Count) entries"
}
$spawnPairs = @{}
$spawnAnchorOwners = @{}
foreach ($item in $spawnBindings) {
    if ($item -isnot [pscustomobject]) {
        Add-Error $errors 'spawn binding must be an object'
        continue
    }
    Assert-ExactProperties $item @('encounter_key','anchor_key','unit_key') 'spawn binding' $errors
    foreach ($field in @('encounter_key','anchor_key','unit_key')) {
        if (-not (Test-NonEmptyTrimmedString $item.$field)) { Add-Error $errors "spawn binding has invalid $field" }
    }
    if (-not (Test-NonEmptyTrimmedString $item.encounter_key) -or -not (Test-NonEmptyTrimmedString $item.anchor_key) -or
        -not (Test-NonEmptyTrimmedString $item.unit_key)) { continue }
    $encounter = $encounterByKey[$item.encounter_key]
    if ($null -eq $encounter) { Add-Error $errors "spawn binding references unknown encounter $($item.encounter_key)"; continue }
    if (-not $unitByKey.ContainsKey($item.unit_key)) { Add-Error $errors "spawn binding references unknown unit $($item.unit_key)" }
    $actual = $layoutResourceMetadata[$item.anchor_key]
    $validAnchor = $null -ne $actual -and (
        ($actual.source -eq 'spawn' -and $actual.expected_type -eq 'spawn_anchor') -or
        ($actual.source -eq 'logic_resource' -and $actual.expected_type -eq 'point') -or
        ($actual.source -eq 'boss_zone' -and $actual.expected_type -eq 'boss_zone')
    )
    if (-not $validAnchor) { Add-Error $errors "spawn binding anchor source/type is invalid: $($item.anchor_key)" }
    $pairKey = "$($item.encounter_key)|$($item.anchor_key)|$($item.unit_key)"
    if ($spawnPairs.ContainsKey($pairKey)) { Add-Error $errors "duplicate spawn binding $pairKey" }
    else { $spawnPairs[$pairKey] = $true }
    $anchorOwnerKey = "$($item.encounter_key)|$($item.anchor_key)"
    if ($spawnAnchorOwners.ContainsKey($anchorOwnerKey)) { Add-Error $errors "spawn anchor is bound more than once for encounter: $anchorOwnerKey" }
    else { $spawnAnchorOwners[$anchorOwnerKey] = $item.unit_key }
    if ($publicBossArenaByUnit.ContainsKey([string]$item.unit_key) -and
        $item.anchor_key -cne $publicBossArenaByUnit[[string]$item.unit_key]) {
        Add-Error $errors "$($item.encounter_key): public boss spawn anchor must match encounter boss_arena $($publicBossArenaByUnit[[string]$item.unit_key])"
    }
    if (-not $expectedSpawnPairs.ContainsKey($pairKey)) { Add-Error $errors "spawn binding is not declared by encounter projection: $pairKey" }
}
foreach ($pairKey in $expectedSpawnPairs.Keys) {
    if (-not $spawnPairs.ContainsKey($pairKey)) { Add-Error $errors "spawn binding omits encounter projection: $pairKey" }
}

$expectedActionEncounters = @{}
foreach ($encounter in @($manifest.encounters)) {
    $actionProperty = $encounter.runtime_fields.PSObject.Properties['encounter_action_key']
    if ($null -eq $actionProperty) { continue }
    if (-not (Test-NonEmptyTrimmedString $actionProperty.Value)) {
        Add-Error $errors "$($encounter.record_key): encounter_action_key must be a non-empty trimmed string"
    }
    else { $expectedActionEncounters[$encounter.record_key] = $encounter }
}
if ($encounterActionBindings.Count -ne $expectedActionEncounters.Count) {
    Add-Error $errors "map logic binding encounter_action_bindings must contain exactly $($expectedActionEncounters.Count) entries"
}
$actionPairs = @{}
$actionKeyOwners = @{}
$baseActionFields = @('encounter_key','action_key','area_key','anchor_key','radius_cells','max_concurrent','read_seconds')
foreach ($item in $encounterActionBindings) {
    if ($item -isnot [pscustomobject]) {
        Add-Error $errors 'encounter action binding must be an object'
        continue
    }
    $encounterKey = Get-PropertyValue $item 'encounter_key'
    $encounter = if (Test-NonEmptyTrimmedString $encounterKey) { $encounterByKey[$encounterKey] } else { $null }
    $actionFields = @($baseActionFields)
    if ($null -ne $encounter -and $encounter.encounter_type -eq 'public_trace') {
        $actionFields += 'postlude_seconds'
    }
    elseif ($null -ne $encounter -and $encounter.encounter_type -eq 'public_boss') {
        $actionFields += 'window_seconds'
        if ($encounter.runtime_fields.safe_line_required -eq $true) {
            $actionFields += @('required_inside_area_key','required_outside_area_key')
        }
    }
    Assert-ExactProperties $item $actionFields 'encounter action binding' $errors
    foreach ($field in @('encounter_key','action_key','area_key','anchor_key')) {
        if (-not (Test-NonEmptyTrimmedString $item.$field)) { Add-Error $errors "encounter action binding has invalid $field" }
    }
    if (-not (Test-PositiveInteger $item.radius_cells)) { Add-Error $errors "${encounterKey}: action radius_cells must be a positive integer" }
    if (-not (Test-PositiveInteger $item.max_concurrent)) { Add-Error $errors "${encounterKey}: action max_concurrent must be a positive integer" }
    if (-not (Test-PositiveNumber $item.read_seconds)) { Add-Error $errors "${encounterKey}: action read_seconds must be positive" }
    foreach ($field in @('window_seconds','postlude_seconds')) {
        $property = $item.PSObject.Properties[$field]
        if ($null -ne $property -and -not (Test-PositiveNumber $property.Value)) { Add-Error $errors "${encounterKey}: action $field must be positive" }
    }
    if ($null -eq $encounter) { Add-Error $errors "action binding references unknown encounter $encounterKey"; continue }
    if (-not $expectedActionEncounters.ContainsKey($encounterKey)) { Add-Error $errors "${encounterKey}: action binding is not declared by encounter" }
    if ($actionPairs.ContainsKey($encounterKey)) { Add-Error $errors "duplicate encounter action binding for $encounterKey" }
    else { $actionPairs[$encounterKey] = $item }
    if (Test-NonEmptyTrimmedString $item.action_key) {
        if ($actionKeyOwners.ContainsKey($item.action_key)) { Add-Error $errors "duplicate encounter action key: $($item.action_key)" }
        else { $actionKeyOwners[$item.action_key] = $encounterKey }
    }
    $runtime = $encounter.runtime_fields
    if ($runtime.encounter_action_key -ne $item.action_key) { Add-Error $errors "${encounterKey}: action binding key differs from encounter" }
    if ($runtime.interaction_radius_cells -ne $item.radius_cells -or $runtime.max_concurrent_actors -ne $item.max_concurrent) {
        Add-Error $errors "${encounterKey}: action binding radius or concurrency differs from encounter"
    }
    if ($encounter.encounter_type -eq 'public_trace' -and $item.postlude_seconds -ne $runtime.local_environment_seconds) {
        Add-Error $errors "${encounterKey}: action postlude_seconds differs from encounter local environment"
    }
    $area = $layoutResourceMetadata[$item.area_key]
    $anchor = $layoutResourceMetadata[$item.anchor_key]
    if ($null -eq $area -or $area.source -ne 'logic_resource' -or $area.expected_type -ne 'circleArea') { Add-Error $errors "${encounterKey}: action area must resolve to circleArea" }
    if ($null -eq $anchor -or $anchor.source -ne 'logic_resource' -or $anchor.expected_type -ne 'point') { Add-Error $errors "${encounterKey}: action anchor must resolve to point" }
    $areaBinding = $bindingResourcePairs["$encounterKey|$($item.area_key)"]
    $anchorBinding = $bindingResourcePairs["$encounterKey|$($item.anchor_key)"]
    if ($null -eq $areaBinding -or $null -eq $anchorBinding) {
        Add-Error $errors "${encounterKey}: action resources must be explicitly bound"
    }
    else {
        if ($areaBinding.role -ne 'interaction_area') { Add-Error $errors "${encounterKey}: action area must use interaction_area role" }
        if ($anchorBinding.role -ne 'interaction_anchor') { Add-Error $errors "${encounterKey}: action anchor must use interaction_anchor role" }
    }
    if ($encounter.runtime_fields.safe_line_required -eq $true) {
        $insideResources = @($manifestResourcesByEncounterRole["$encounterKey|required_safe_line"])
        $outsideResources = @($manifestResourcesByEncounterRole["$encounterKey|forbidden_vortex_core"])
        if ($insideResources.Count -ne 1 -or $item.required_inside_area_key -ne $insideResources[0]) {
            Add-Error $errors "${encounterKey}: action must use the declared required_safe_line resource"
        }
        if ($outsideResources.Count -ne 1 -or $item.required_outside_area_key -ne $outsideResources[0]) {
            Add-Error $errors "${encounterKey}: action must use the declared forbidden_vortex_core resource"
        }
        $insideBinding = $bindingResourcePairs["$encounterKey|$($item.required_inside_area_key)"]
        $outsideBinding = $bindingResourcePairs["$encounterKey|$($item.required_outside_area_key)"]
        if ($null -eq $insideBinding -or $insideBinding.role -ne 'required_safe_line') { Add-Error $errors "${encounterKey}: required_inside_area_key must use required_safe_line role" }
        if ($null -eq $outsideBinding -or $outsideBinding.role -ne 'forbidden_vortex_core') { Add-Error $errors "${encounterKey}: required_outside_area_key must use forbidden_vortex_core role" }
    }
}
foreach ($encounterKey in $expectedActionEncounters.Keys) {
    if (-not $actionPairs.ContainsKey($encounterKey)) { Add-Error $errors "${encounterKey}: encounter action binding is missing" }
}

$expectedPublicBosses = @('HG_E_MACAQUE_KING','HG_E_JIAO_KING','HG_E_SHARK_KING')
$actualPublicBosses = @($manifest.encounters | Where-Object { $_.encounter_type -eq 'public_boss' })
if ($actualPublicBosses.Count -ne 3) { Add-Error $errors "expected 3 public bosses, got $($actualPublicBosses.Count)" }
foreach ($expectedKey in $expectedPublicBosses) {
    if (-not $encounterByKey.ContainsKey($expectedKey)) { Add-Error $errors "missing public boss encounter $expectedKey" }
}

$validScopes = @('public','solo_instance','team_instance')
foreach ($encounter in @($manifest.encounters)) {
    if ($validScopes -notcontains $encounter.combat_scope) { Add-Error $errors "$($encounter.record_key): invalid combat_scope $($encounter.combat_scope)" }
    foreach ($resourceKey in @($encounter.map_logic_resource_keys)) {
        if (-not $layoutResourceKeys.ContainsKey($resourceKey)) { Add-Error $errors "$($encounter.record_key): unknown whitebox map resource $resourceKey" }
    }
    foreach ($unitKey in @((Get-PropertyValue $encounter 'spawn_unit_keys'))) {
        if ([string]::IsNullOrWhiteSpace([string]$unitKey)) { continue }
        if (-not $unitByKey.ContainsKey($unitKey)) { Add-Error $errors "$($encounter.record_key): unknown spawn unit $unitKey" }
    }
    if ($encounter.encounter_type -eq 'public_boss') {
        if ($encounter.combat_scope -ne 'public') { Add-Error $errors "$($encounter.record_key): public boss must use public scope" }
        if (-not $unitByKey.ContainsKey($encounter.boss_unit_key)) { Add-Error $errors "$($encounter.record_key): unknown boss unit" }
        elseif ($unitByKey[$encounter.boss_unit_key].runtime_fields.target_rank -ne 'boss') { Add-Error $errors "$($encounter.record_key): boss unit must resolve as target_rank boss" }
        foreach ($field in @('respawn_seconds','break_threshold','break_window_seconds','participant_rule','encounter_action_key','interaction_radius_cells','max_concurrent_actors','main_route_overlap')) {
            if ($null -eq $encounter.runtime_fields.PSObject.Properties[$field]) { Add-Error $errors "$($encounter.record_key): missing public boss runtime field $field" }
        }
        if ($encounter.runtime_fields.interaction_radius_cells -ne 3) { Add-Error $errors "$($encounter.record_key): public action radius must be 3 cells" }
        if ($encounter.runtime_fields.max_concurrent_actors -ne 4) { Add-Error $errors "$($encounter.record_key): public action concurrency must be 4" }
        if ($encounter.runtime_fields.main_route_overlap -ne 'forbidden') { Add-Error $errors "$($encounter.record_key): boss may not overlap main route" }
        if (-not $profileByKey.ContainsKey($encounter.runtime_fields.participant_rule)) { Add-Error $errors "$($encounter.record_key): unknown participation profile $($encounter.runtime_fields.participant_rule)" }
        $bossBreakProfile = $unitByKey[$encounter.boss_unit_key].runtime_fields.break_profile
        if (-not $profileByKey.ContainsKey($bossBreakProfile)) { Add-Error $errors "$($encounter.record_key): unknown boss break profile $bossBreakProfile" }
        else {
            $breakProfile = $profileByKey[$bossBreakProfile]
            if ($breakProfile.threshold -ne $encounter.runtime_fields.break_threshold -or $breakProfile.window_seconds -ne $encounter.runtime_fields.break_window_seconds) {
                Add-Error $errors "$($encounter.record_key): break profile and encounter threshold differ"
            }
        }
    }
    if ($encounter.encounter_type -eq 'public_trace') {
        if ($encounter.combat_scope -ne 'public') { Add-Error $errors "$($encounter.record_key): trace must use public scope" }
        if ($encounter.runtime_fields.interaction_radius_cells -ne 2) { Add-Error $errors "$($encounter.record_key): trace interaction radius must be 2 cells" }
        if ($encounter.runtime_fields.max_concurrent_actors -ne 4) { Add-Error $errors "$($encounter.record_key): trace concurrency must be 4" }
    }
}

if ($encounterByKey['HG_E_JIAO_KING'].runtime_fields.trace_pause -ne $true -or $encounterByKey['HG_E_JIAO_KING'].runtime_fields.trace_pause_max_seconds -ne 3) {
    Add-Error $errors 'HG_E_JIAO_KING must have an explicit 3-second trace_pause'
}
foreach ($key in @('HG_E_MACAQUE_KING','HG_E_SHARK_KING')) {
    if ($encounterByKey[$key].runtime_fields.trace_pause -ne $false) { Add-Error $errors "$key must not emit trace_pause" }
}
if ($encounterByKey['HG_E_OX_BATTLEFIELD'].runtime_fields.max_members -ne 4) { Add-Error $errors 'ox battlefield must cap membership at four' }

$oldTideRuntime = $encounterByKey['HG_E_DRAGON_OLD_TIDE'].runtime_fields
if ($oldTideRuntime.discovery_rule -ne 'longgong_discovered_and_level_at_least_8') {
    Add-Error $errors 'HG_E_DRAGON_OLD_TIDE discovery_rule must preserve discovered-and-Lv8 guidance'
}
if ($oldTideRuntime.unlock_rule -ne 'longgong_discovered_and_level_at_least_8_and_actor_current_profession_lv8_route_completed') {
    Add-Error $errors 'HG_E_DRAGON_OLD_TIDE unlock_rule must require the actor current-profession Lv8 route completion'
}
$oldTideRouteCompletion = $oldTideRuntime.route_completion
if ($oldTideRouteCompletion -isnot [pscustomobject]) {
    Add-Error $errors 'HG_E_DRAGON_OLD_TIDE route_completion must be an object'
}
else {
    if ($oldTideRouteCompletion.scope -ne 'actor_current_profession') {
        Add-Error $errors 'HG_E_DRAGON_OLD_TIDE route completion scope must be actor_current_profession'
    }
    if ($oldTideRouteCompletion.trial_seconds -ne 60) {
        Add-Error $errors 'HG_E_DRAGON_OLD_TIDE route completion trial_seconds must be 60'
    }
    $completionKeys = $oldTideRouteCompletion.completion_keys_by_profession
    if ($completionKeys -isnot [pscustomobject]) {
        Add-Error $errors 'HG_E_DRAGON_OLD_TIDE route completion keys must be an object'
    }
    else {
        $expectedRouteKeys = [ordered]@{
            C01 = @('C01_ROUTE_LV8_core')
            C02 = @('C02_ROUTE_LV8_core')
            C03 = @('C03_ROUTE_LV8_core')
            C04 = @('C04_ROUTE_LV8_hunt','C04_ROUTE_LV8_wind','C04_ROUTE_LV8_bind')
        }
        foreach ($professionId in $expectedRouteKeys.Keys) {
            $actualProperty = $completionKeys.PSObject.Properties[$professionId]
            if ($null -eq $actualProperty -or -not (Test-JsonArray $actualProperty.Value)) {
                Add-Error $errors "HG_E_DRAGON_OLD_TIDE route completion keys missing array for $professionId"
                continue
            }
            if ((@($actualProperty.Value) -join '|') -ne (@($expectedRouteKeys[$professionId]) -join '|')) {
                Add-Error $errors "HG_E_DRAGON_OLD_TIDE route completion keys differ for $professionId"
            }
        }
    }
}

foreach ($name in $executionGateNames) {
    $property = $executionGates.PSObject.Properties[$name]
    if ($null -eq $property -or $null -eq $property.Value -or ($property.Value -is [bool] -and -not $property.Value)) {
        $warnings.Add("production gate remains closed: $name")
    }
}

Write-Output 'Huaguoshan encounter preflight'
Write-Output "  units: $(@($manifest.units).Count)"
Write-Output "  abilities: $(@($manifest.abilities).Count)"
Write-Output "  modifiers: $(@($manifest.modifiers).Count)"
Write-Output "  projectiles: $(@($manifest.projectiles).Count)"
Write-Output "  encounters: $(@($manifest.encounters).Count)"
Write-Output "  errors: $($errors.Count)"
if ($errors.Count -gt 0) {
    foreach ($entry in $errors) { Write-Output "ERROR: $entry" }
    exit 1
}
foreach ($warning in $warnings) { Write-Output "WARNING: $warning" }
Write-Output 'PASS: Huaguoshan object and encounter package is internally consistent.'
Write-Output 'STATUS: validated offline; not ready for editor construction.'
