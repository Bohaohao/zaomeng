$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $root 'preconstruction-manifest.json'
$bindingPath = Join-Path $root 'map-logic-binding.json'
$configPath = Join-Path $root 'lua\huaguoshan_config.lua'
$tool = Join-Path $root 'tools\materialize-object-commands.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('huaguoshan-materializer-' + [guid]::NewGuid().ToString('N'))
$mapPath = Join-Path $tempRoot 'maps\EntryMap'
$scriptRoot = Join-Path $mapPath 'script'
$officialEditor = Join-Path $env:USERPROFILE '.codex\skills\y3-terrain-layout\sources\y3-maker-config\skills\y3-obj-edit\scripts\y3_obj_edit.py'
if (-not (Test-Path -LiteralPath $officialEditor -PathType Leaf)) {
    $officialEditor = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.codex\skills') -Recurse -File -Filter 'y3_obj_edit.py' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName.Replace('\', '/') -match '/skills/y3-obj-edit/scripts/y3_obj_edit\.py$' } |
        Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($officialEditor)) { throw 'Installed y3_obj_edit.py was not found.' }

New-Item -ItemType Directory -Path $scriptRoot -Force | Out-Null

function Copy-JsonObject {
    param($Object)
    return $Object | ConvertTo-Json -Depth 100 | ConvertFrom-Json
}

function ConvertTo-LuaLiteral {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'nil' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) { return ($Value | ConvertTo-Json -Compress) }
    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [pscustomobject]) {
        $items = @($Value | ForEach-Object { ConvertTo-LuaLiteral $_ })
        return '{' + ($items -join ',') + '}'
    }
    $fields = @($Value.PSObject.Properties | ForEach-Object {
        '[' + (ConvertTo-LuaLiteral $_.Name) + ']=' + (ConvertTo-LuaLiteral $_.Value)
    })
    return '{' + ($fields -join ',') + '}'
}

function Read-Manifest {
    return Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-Binding {
    return Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-LuaConfigFixture {
    param(
        $Binding,
        [string]$LuaRoot,
        [switch]$KeepPending,
        [switch]$SynchronizePublicBindings,
        [AllowNull()][object]$EditorBoundOverride = $null
    )
    New-Item -ItemType Directory -Path $LuaRoot -Force | Out-Null
    $fixtureConfigPath = Join-Path $LuaRoot 'huaguoshan_config.lua'
    if ($KeepPending) {
        Copy-Item -LiteralPath $configPath -Destination $fixtureConfigPath -Force
        return
    }

    Copy-Item -LiteralPath $configPath -Destination (Join-Path $LuaRoot 'huaguoshan_config_base.lua') -Force
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("local Config = require 'huaguoshan_config_base'")
    $lines.Add("Config.layout_contract.id = $(ConvertTo-LuaLiteral $Binding.runtime_contract_id)")
    $editorBound = if ($null -eq $EditorBoundOverride) { $Binding.real_map_binding_verified } else { $EditorBoundOverride }
    if ($editorBound -isnot [bool]) { throw 'Lua editor_bound fixture must be boolean.' }
    $lines.Add("Config.layout_contract.editor_bound = $(ConvertTo-LuaLiteral $editorBound)")
    if ($SynchronizePublicBindings) {
        foreach ($group in @($Binding.encounter_resource_bindings | Group-Object encounter_key)) {
            $encounterKey = ConvertTo-LuaLiteral $group.Name
            $lines.Add("Config.encounters[$encounterKey].resources = $(ConvertTo-LuaLiteral @($group.Group.resource_key))")
            $lines.Add("Config.encounter_resource_roles[$encounterKey] = {}")
            foreach ($item in @($group.Group)) {
                $lines.Add("Config.encounter_resource_roles[$encounterKey][$(ConvertTo-LuaLiteral $item.resource_key)] = $(ConvertTo-LuaLiteral $item.role)")
            }
        }
        foreach ($group in @($Binding.spawn_bindings | Group-Object encounter_key)) {
            $encounterKey = ConvertTo-LuaLiteral $group.Name
            $lines.Add("Config.encounters[$encounterKey].spawn_plan = {}")
            $lines.Add("Config.encounters[$encounterKey].boss_unit_key = nil")
            $lines.Add("Config.encounters[$encounterKey].boss_spawn_anchor = nil")
            foreach ($item in @($group.Group)) {
                $spawn = [pscustomobject]@{ anchor = $item.anchor_key; unit_key = $item.unit_key }
                $lines.Add("table.insert(Config.encounters[$encounterKey].spawn_plan, $(ConvertTo-LuaLiteral $spawn))")
            }
        }
    }
    foreach ($projection in @($Binding.encounter_instance_map_states)) {
        $encounterKey = ConvertTo-LuaLiteral $projection.encounter_key
        $lines.Add("Config.encounters[$encounterKey].instance_map_contract = $(ConvertTo-LuaLiteral $projection.state)")
        $lines.Add("Config.encounters[$encounterKey].instance_map_contract_key = $(ConvertTo-LuaLiteral $projection.contract_key)")
    }
    $lines.Add('Config.instance_map_contracts = {}')
    foreach ($contract in @($Binding.instance_map_contracts)) {
        $contractValue = [pscustomobject][ordered]@{
            encounter_keys = @($contract.encounter_keys)
            state = $contract.state
            layer = $contract.layer
            slot_count = $contract.slot_count
            slots = @($contract.slots)
        }
        $lines.Add("Config.instance_map_contracts[$(ConvertTo-LuaLiteral $contract.contract_key)] = $(ConvertTo-LuaLiteral $contractValue)")
    }
    $lines.Add('return Config')
    Set-Content -LiteralPath $fixtureConfigPath -Value $lines -Encoding UTF8
}

function New-ResolvedManifest {
    param([switch]$OpenRuntimeGates)
    $manifest = Read-Manifest
    foreach ($property in $manifest.execution_gates.PSObject.Properties) {
        if ($property.Name -eq 'map_path') { $property.Value = $mapPath }
        elseif ($property.Name -eq 'script_root') { $property.Value = $scriptRoot }
        elseif ($property.Name -eq 'y3_obj_edit_script') { $property.Value = $officialEditor }
        else { $property.Value = $true }
    }

    $manifest.object_defaults.ability.unresolved_fields = @()
    $manifest.object_defaults.modifier.unresolved_fields = @()
    $manifest.object_defaults.projectile.unresolved_fields = @()

    $nextObjectId = 990000000
    $nextIconId = 991000000
    $nextModelId = 992000000
    foreach ($unit in @($manifest.units)) {
        $nextObjectId++
        $nextIconId++
        $nextModelId++
        $unit.status = 'id-assigned'
        $unit.operation = 'create'
        $unit.y3_id = $nextObjectId
        $unit.icon_id = $nextIconId
        $unit.model_id = $nextModelId
        $unit.unresolved_fields = @()
        $unit.object_fields | Add-Member -NotePropertyName common_atk_type -NotePropertyValue 1 -Force
        $unit.object_fields | Add-Member -NotePropertyName common_atk_range -NotePropertyValue 180 -Force
    }
    foreach ($group in @('abilities','modifiers','projectiles')) {
        foreach ($object in @($manifest.$group)) {
            $nextObjectId++
            $nextIconId++
            $object | Add-Member -NotePropertyName status -NotePropertyValue 'id-assigned' -Force
            $object | Add-Member -NotePropertyName operation -NotePropertyValue 'create' -Force
            $object | Add-Member -NotePropertyName y3_id -NotePropertyValue $nextObjectId -Force
            $object | Add-Member -NotePropertyName icon_id -NotePropertyValue $nextIconId -Force
            $object | Add-Member -NotePropertyName unresolved_fields -NotePropertyValue @() -Force
        }
    }
    if ($OpenRuntimeGates) {
        $manifest.runtime_package.status = 'production-runtime-public-map-contract-complete-instance-map-contract-verified'
        foreach ($name in @(
            'offline_runtime_complete','public_map_contract_complete','instance_map_contract_verified',
            'authoritative_progression_validator_bound','real_map_binding_verified','production_ids_ready'
        )) {
            $manifest.runtime_package.$name = $true
        }
        foreach ($encounter in @($manifest.encounters | Where-Object { $_.combat_scope -in @('solo_instance','team_instance') })) {
            $encounter.runtime_fields.map_binding_state = 'verified'
        }
    }
    return $manifest
}

function New-VerifiedBinding {
    $binding = Read-Binding
    $binding.status = 'production-bound-public-map-contract-complete-instance-map-contract-verified'
    $binding.real_map_binding_verified = $true
    $binding.production_ids_ready = $true
    $binding.instance_map_contract_verified = $true
    $nextStableId = 993000000
    foreach ($contract in @($binding.instance_map_contracts)) {
        $contract.state = 'verified'
        foreach ($slot in @($contract.slots)) {
            foreach ($role in @($slot.roles)) {
                $nextStableId++
                $role.stable_object_id = $nextStableId
            }
        }
    }
    foreach ($state in @($binding.encounter_instance_map_states)) { $state.state = 'verified' }
    return $binding
}

function Write-MaterializerFixture {
    param(
        $Manifest,
        $Binding,
        [string]$Name,
        [switch]$KeepLuaConfigPending,
        [switch]$SynchronizePublicBindings,
        [AllowNull()][object]$LuaEditorBoundOverride = $null,
        [AllowNull()][object]$LuaBinding = $null
    )
    $fixtureRoot = Join-Path $tempRoot $Name
    $fixturePath = Join-Path $fixtureRoot 'preconstruction-manifest.json'
    $outputPath = Join-Path $fixtureRoot 'commands.ps1'
    $bindingFixturePath = Join-Path $fixtureRoot ([string]$Manifest.runtime_package.map_logic_binding_path)
    $luaRoot = Join-Path $fixtureRoot ([string]$Manifest.runtime_package.lua_root)
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $bindingParent = Split-Path -Parent $bindingFixturePath
    if ($bindingParent) { New-Item -ItemType Directory -Path $bindingParent -Force | Out-Null }
    $Manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixturePath -Encoding UTF8
    $Binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bindingFixturePath -Encoding UTF8
    if ($null -eq $LuaBinding) { $LuaBinding = $Binding }
    Write-LuaConfigFixture -Binding $LuaBinding -LuaRoot $luaRoot -KeepPending:$KeepLuaConfigPending `
        -SynchronizePublicBindings:$SynchronizePublicBindings `
        -EditorBoundOverride $LuaEditorBoundOverride
    return [pscustomobject]@{
        ManifestPath = $fixturePath
        OutputPath = $outputPath
    }
}

function Assert-MaterializerRejects {
    param(
        $Manifest,
        [string]$Name,
        [string[]]$ExpectedPattern,
        $Binding = $null,
        [string]$OutputExtension = '.ps1',
        [switch]$KeepLuaConfigPending,
        [switch]$SynchronizePublicBindings,
        [AllowNull()][object]$LuaEditorBoundOverride = $null,
        [AllowNull()][object]$LuaBinding = $null
    )
    if ($null -eq $Binding) { $Binding = Read-Binding }
    $paths = Write-MaterializerFixture -Manifest $Manifest -Binding $Binding -Name $Name `
        -KeepLuaConfigPending:$KeepLuaConfigPending -SynchronizePublicBindings:$SynchronizePublicBindings `
        -LuaEditorBoundOverride $LuaEditorBoundOverride -LuaBinding $LuaBinding
    $outputPath = [IO.Path]::ChangeExtension($paths.OutputPath, $OutputExtension)
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -ManifestPath $paths.ManifestPath -OutputPath $outputPath 2>&1
    $exitCode = $LASTEXITCODE
    $text = $result | Out-String -Width 4096
    if ($exitCode -eq 0) { throw "materializer unexpectedly accepted fixture: $Name" }
    foreach ($pattern in $ExpectedPattern) {
        if ($text -notmatch $pattern) { throw "materializer did not report $pattern for ${Name}: $text" }
    }
    if (Test-Path -LiteralPath $outputPath) { throw "materializer wrote output for rejected fixture: $Name" }
}

function Assert-DuplicateRawAttackPhyRejected {
    param($Manifest, $Binding)
    $paths = Write-MaterializerFixture $Manifest $Binding 'duplicate-raw-attack-phy'
    $manifestText = Get-Content -LiteralPath $paths.ManifestPath -Raw -Encoding UTF8
    $attackPropertyPattern = [regex]'"attack_phy"\s*:\s*22,'
    $match = $attackPropertyPattern.Match($manifestText)
    if (-not $match.Success) { throw 'materializer duplicate-property fixture could not locate attack_phy' }
    $lineStart = $manifestText.LastIndexOf("`n", $match.Index)
    $lineStart = if ($lineStart -lt 0) { 0 } else { $lineStart + 1 }
    $indent = $manifestText.Substring($lineStart, $match.Index - $lineStart)
    $insertAt = $match.Index + $match.Length
    $manifestText = $manifestText.Insert($insertAt, [Environment]::NewLine + $indent + '"attack_phy": 999,')
    Set-Content -LiteralPath $paths.ManifestPath -Encoding UTF8 -Value $manifestText

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool `
            -ManifestPath $paths.ManifestPath -OutputPath $paths.OutputPath 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorActionPreference }
    $text = $result | Out-String -Width 4096
    if ($exitCode -eq 0) { throw 'materializer unexpectedly accepted a duplicate raw attack_phy property' }
    if ($text -notmatch 'duplicate JSON property "attack_phy" at \$\.units\[0\]\.object_fields') {
        throw "materializer did not diagnose the duplicate raw attack_phy property: $text"
    }
    if (Test-Path -LiteralPath $paths.OutputPath) { throw 'materializer wrote output for duplicate raw attack_phy input' }
}

try {
    $realOfflineOutput = Join-Path $tempRoot 'real-offline-commands.ps1'
    $realOfflineResult = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -ManifestPath $manifestPath -OutputPath $realOfflineOutput 2>&1
    $realOfflineText = $realOfflineResult | Out-String
    if ($LASTEXITCODE -eq 0) { throw 'materializer unexpectedly accepted the real offline artifacts' }
    if ($realOfflineText -notmatch 'materialization refused') { throw "real offline rejection was not reported: $realOfflineText" }
    if (Test-Path -LiteralPath $realOfflineOutput) { throw 'materializer wrote output for the real offline artifacts' }

    $unresolvedManifest = Read-Manifest
    Assert-MaterializerRejects $unresolvedManifest 'unresolved-production-data' 'materialization refused' (Read-Binding)

    $pendingManifest = New-ResolvedManifest
    Assert-MaterializerRejects $pendingManifest 'current-runtime-pending' 'runtime_package production gate unresolved: instance_map_contract_verified' (Read-Binding)

    $resolvedManifest = New-ResolvedManifest -OpenRuntimeGates
    $resolvedBinding = New-VerifiedBinding
    $resolvedPaths = Write-MaterializerFixture $resolvedManifest $resolvedBinding 'fully-consistent-production'
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -ManifestPath $resolvedPaths.ManifestPath -OutputPath $resolvedPaths.OutputPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "resolved materialization failed: $($result | Out-String)" }
    $generated = Get-Content -LiteralPath $resolvedPaths.OutputPath -Raw -Encoding UTF8
    $counts = [ordered]@{
        modifiers = ([regex]::Matches($generated, '-type modifier -create')).Count
        projectiles = ([regex]::Matches($generated, '-type projectile -create')).Count
        abilities = ([regex]::Matches($generated, '-type ability -create')).Count
        units = ([regex]::Matches($generated, '-type unit -create')).Count
        unit_edits = ([regex]::Matches($generated, '-type unit -edit')).Count
    }
    if ($counts.modifiers -ne 12 -or $counts.projectiles -ne 7 -or $counts.abilities -ne 55 -or $counts.units -ne 35 -or $counts.unit_edits -ne 35) {
        throw "generated command counts are invalid: $($counts | ConvertTo-Json -Compress)"
    }
    if ([regex]::Matches($generated, '-common_atk_range').Count -ne 35 -or $generated -cmatch '-Common_atk_range') {
        throw 'generated unit edits did not use the exact canonical common_atk_range key'
    }
    $generatedTokens = $null
    $generatedParseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($resolvedPaths.OutputPath, [ref]$generatedTokens, [ref]$generatedParseErrors)
    if ($generatedParseErrors.Count -gt 0) {
        $generatedParseMessages = @($generatedParseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "generated materializer script is not valid PowerShell: $generatedParseMessages"
    }

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.units = @($fixture.units | Select-Object -Skip 1)
    Assert-MaterializerRejects $fixture 'missing-canonical-unit' @(
        'units must contain exactly 35 objects; got 34',
        'missing canonical unit record_key: HG_U_MOUNTAIN_MONKEY'
    ) (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.modifiers[0].record_key = 'HG_M_INTRUDER'
    Assert-MaterializerRejects $fixture 'unexpected-canonical-modifier' @(
        'missing canonical modifier record_key: HG_M_STONE_SUNDER',
        'unexpected modifier record_key: HG_M_INTRUDER'
    ) (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.abilities[1].record_key = $fixture.abilities[0].record_key
    Assert-MaterializerRejects $fixture 'duplicate-stable-ability-record-key' @(
        'duplicate abilities record_key: HG_A_PACK_LEAP',
        'missing canonical ability record_key: HG_A_STONE_SMASH'
    ) (Copy-JsonObject $resolvedBinding)

    $recordKeyInjectionMarker = Join-Path $tempRoot 'record-key-injection-marker.txt'
    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.abilities[0].record_key = "HG_A_PACK_LEAP'; Set-Content -LiteralPath '$recordKeyInjectionMarker' -Value 'injected'; #"
    Assert-MaterializerRejects $fixture 'illegal-record-key-injection' `
        'abilities contains invalid stable ability record_key' (Copy-JsonObject $resolvedBinding)
    if (Test-Path -LiteralPath $recordKeyInjectionMarker) {
        throw 'an illegal record_key was able to inject a command into generated PowerShell'
    }

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.abilities[0].dependency_keys = @('HG_P_UNKNOWN')
    Assert-MaterializerRejects $fixture 'unknown-ability-dependency' `
        'HG_A_PACK_LEAP: unknown dependency HG_P_UNKNOWN' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.units[3].common_ability_keys = @('HG_A_PACK_LEAP')
    Assert-MaterializerRejects $fixture 'missing-owner-reciprocal-ability-binding' `
        'HG_A_PACK_CALL: owner HG_U_MONKEY_PACK_LEADER does not bind this ability' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $nonOwnerUnit = @($fixture.units | Where-Object { $_.record_key -eq 'HG_U_STONEHIDE_BEAST' })[0]
    $nonOwnerUnit.common_ability_keys = @($nonOwnerUnit.common_ability_keys) + @('HG_A_PACK_LEAP')
    Assert-MaterializerRejects $fixture 'undeclared-unit-ability-owner-binding' `
        'HG_U_STONEHIDE_BEAST: ability HG_A_PACK_LEAP does not list unit as owner' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $unitRecord = @($fixture.units)[0]
    $unitRecord.PSObject.Properties.Remove('unresolved_fields')
    Assert-MaterializerRejects $fixture 'missing-unit-record-unresolved-fields' `
        'HG_U_MOUNTAIN_MONKEY: unresolved_fields missing' (Copy-JsonObject $resolvedBinding)

    $unresolvedFieldKinds = @(
        [pscustomobject]@{ DefaultName = 'ability'; CollectionName = 'abilities' },
        [pscustomobject]@{ DefaultName = 'modifier'; CollectionName = 'modifiers' },
        [pscustomobject]@{ DefaultName = 'projectile'; CollectionName = 'projectiles' }
    )
    foreach ($kind in $unresolvedFieldKinds) {
        $recordKey = [string]@($resolvedManifest.PSObject.Properties[$kind.CollectionName].Value)[0].record_key

        $fixture = Copy-JsonObject $resolvedManifest
        $record = @($fixture.PSObject.Properties[$kind.CollectionName].Value)[0]
        $record.PSObject.Properties.Remove('unresolved_fields')
        Assert-MaterializerRejects $fixture "missing-$($kind.DefaultName)-record-unresolved-fields" `
            "${recordKey}: unresolved_fields missing" (Copy-JsonObject $resolvedBinding)

        $fixture = Copy-JsonObject $resolvedManifest
        $record = @($fixture.PSObject.Properties[$kind.CollectionName].Value)[0]
        $record.unresolved_fields = $null
        Assert-MaterializerRejects $fixture "null-$($kind.DefaultName)-record-unresolved-fields" `
            "${recordKey}: unresolved_fields must be an array" (Copy-JsonObject $resolvedBinding)

        $fixture = Copy-JsonObject $resolvedManifest
        $record = @($fixture.PSObject.Properties[$kind.CollectionName].Value)[0]
        $record.unresolved_fields = 'pending'
        Assert-MaterializerRejects $fixture "scalar-$($kind.DefaultName)-record-unresolved-fields" `
            "${recordKey}: unresolved_fields must be an array" (Copy-JsonObject $resolvedBinding)

        $fixture = Copy-JsonObject $resolvedManifest
        $defaults = $fixture.object_defaults.PSObject.Properties[$kind.DefaultName].Value
        $defaults.PSObject.Properties.Remove('unresolved_fields')
        Assert-MaterializerRejects $fixture "missing-$($kind.DefaultName)-default-unresolved-fields" `
            "object_defaults.$($kind.DefaultName): unresolved_fields missing" (Copy-JsonObject $resolvedBinding)

        $fixture = Copy-JsonObject $resolvedManifest
        $defaults = $fixture.object_defaults.PSObject.Properties[$kind.DefaultName].Value
        $defaults.unresolved_fields = $null
        Assert-MaterializerRejects $fixture "null-$($kind.DefaultName)-default-unresolved-fields" `
            "object_defaults.$($kind.DefaultName): unresolved_fields must be an array" (Copy-JsonObject $resolvedBinding)

        $fixture = Copy-JsonObject $resolvedManifest
        $defaults = $fixture.object_defaults.PSObject.Properties[$kind.DefaultName].Value
        $defaults.unresolved_fields = 'pending'
        Assert-MaterializerRejects $fixture "scalar-$($kind.DefaultName)-default-unresolved-fields" `
            "object_defaults.$($kind.DefaultName): unresolved_fields must be an array" (Copy-JsonObject $resolvedBinding)
    }

    Assert-DuplicateRawAttackPhyRejected (Copy-JsonObject $resolvedManifest) (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.object_defaults.ability.object_fields.PSObject.Properties.Remove('ability_max_level')
    Assert-MaterializerRejects $fixture 'missing-merged-ability-max-level' `
        'missing merged ability field ability_max_level' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.units[0].object_fields | Add-Member -NotePropertyName attack_phyy -NotePropertyValue 1
    Assert-MaterializerRejects $fixture 'unknown-unit-object-field' 'object_fields unknown field: attack_phyy' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.units[0].object_fields.PSObject.Properties.Remove('common_atk_range')
    $fixture.units[0].object_fields | Add-Member -NotePropertyName Common_atk_range -NotePropertyValue 180
    Assert-MaterializerRejects $fixture 'wrong-case-common-attack-range' 'object_fields unknown field: Common_atk_range' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.abilities[0].object_fields | Add-Member -NotePropertyName sight_type -NotePropertyValue 99 -Force
    Assert-MaterializerRejects $fixture 'invalid-ability-enum' 'object_fields sight_type has an invalid value' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.abilities[0].object_fields | Add-Member -NotePropertyName cold_down_time -NotePropertyValue @(8, 7) -Force
    Assert-MaterializerRejects $fixture 'invalid-ability-level-array-length' 'object_fields cold_down_time must contain exactly 1 values' (Copy-JsonObject $resolvedBinding)

    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.package = 'unexpected-package'
    Assert-MaterializerRejects -Manifest (Copy-JsonObject $resolvedManifest) -Name 'invalid-binding-package' `
        -ExpectedPattern 'map logic binding package is invalid' -Binding $bindingFixture -LuaBinding (Copy-JsonObject $resolvedBinding)

    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.schema_version = '5'
    Assert-MaterializerRejects -Manifest (Copy-JsonObject $resolvedManifest) -Name 'invalid-binding-schema-version' `
        -ExpectedPattern 'map logic binding schema_version is invalid' -Binding $bindingFixture -LuaBinding (Copy-JsonObject $resolvedBinding)

    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.status = 'reviewed'
    Assert-MaterializerRejects -Manifest (Copy-JsonObject $resolvedManifest) -Name 'invalid-binding-status' `
        -ExpectedPattern 'map logic binding status is invalid for materialization' -Binding $bindingFixture -LuaBinding (Copy-JsonObject $resolvedBinding)

    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.source_layout_relpath = 'docs/wrong-layout.json'
    Assert-MaterializerRejects -Manifest (Copy-JsonObject $resolvedManifest) -Name 'invalid-binding-source-layout' `
        -ExpectedPattern 'map logic binding source_layout_relpath is invalid' -Binding $bindingFixture -LuaBinding (Copy-JsonObject $resolvedBinding)

    $requiredBindingProperties = @(
        'package','schema_version','status','runtime_contract_id','source_layout_relpath',
        'real_map_binding_verified','production_ids_ready','instance_map_contract_verified',
        'instance_contract_role_schema','encounter_instance_map_states','return_points',
        'encounter_resource_bindings','instance_map_contracts','spawn_bindings','encounter_action_bindings'
    )
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $missingBindingPatterns = @()
    foreach ($propertyName in $requiredBindingProperties) {
        $bindingFixture.PSObject.Properties.Remove($propertyName)
        $missingBindingPatterns += ("map logic binding missing required property: " + $propertyName)
    }
    Assert-MaterializerRejects -Manifest (Copy-JsonObject $resolvedManifest) -Name 'missing-binding-properties' `
        -ExpectedPattern $missingBindingPatterns -Binding $bindingFixture -LuaBinding (Copy-JsonObject $resolvedBinding)

    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture | Add-Member -NotePropertyName unexpected_contract_field -NotePropertyValue $true
    Assert-MaterializerRejects -Manifest (Copy-JsonObject $resolvedManifest) -Name 'unexpected-binding-property' `
        -ExpectedPattern 'map logic binding has unexpected property: unexpected_contract_field' `
        -Binding $bindingFixture -LuaBinding (Copy-JsonObject $resolvedBinding)

    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.return_points = [pscustomobject]@{ role = 'spawn' }
    Assert-MaterializerRejects -Manifest (Copy-JsonObject $resolvedManifest) -Name 'invalid-binding-array-shape' `
        -ExpectedPattern 'map logic binding return_points must be an array' `
        -Binding $bindingFixture -LuaBinding (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.execution_gates.map_path = Join-Path $tempRoot 'missing-map-path'
    $fixture.execution_gates.script_root = Join-Path $tempRoot 'missing-script-root'
    Assert-MaterializerRejects $fixture 'missing-production-paths' 'path must be an existing directory' (Copy-JsonObject $resolvedBinding)

    $skipPaths = Write-MaterializerFixture $fixture (Copy-JsonObject $resolvedBinding) 'legacy-skip-path-flag'
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $legacySkipResult = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool `
            -ManifestPath $skipPaths.ManifestPath -OutputPath $skipPaths.OutputPath -SkipPathExistenceCheck 2>&1
        $legacySkipExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($legacySkipExitCode -eq 0) { throw 'legacy path-skip invocation unexpectedly generated object commands' }
    if (Test-Path -LiteralPath $skipPaths.OutputPath) { throw 'legacy path-skip invocation wrote object commands' }

    $fixture = Copy-JsonObject $resolvedManifest
    Assert-MaterializerRejects -Manifest $fixture -Name 'lua-config-pending' `
        -ExpectedPattern 'Lua Config instance_map_contract_verified gate unresolved' `
        -Binding (Copy-JsonObject $resolvedBinding) -KeepLuaConfigPending

    $fixture = Copy-JsonObject $resolvedManifest
    Assert-MaterializerRejects -Manifest $fixture -Name 'lua-editor-bound-false' `
        -ExpectedPattern 'Lua Config editor_bound gate unresolved' `
        -Binding (Copy-JsonObject $resolvedBinding) -LuaEditorBoundOverride $false

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.real_map_binding_verified = $false
    Assert-MaterializerRejects -Manifest $fixture -Name 'json-editor-bound-false-lua-true' `
        -ExpectedPattern 'Lua Config editor_bound gate does not match map logic binding' `
        -Binding $bindingFixture -LuaEditorBoundOverride $true

    $fixture = Copy-JsonObject $resolvedManifest
    $missingConfigPaths = Write-MaterializerFixture $fixture (Copy-JsonObject $resolvedBinding) 'lua-config-unreadable'
    Remove-Item -LiteralPath (Join-Path (Split-Path -Parent $missingConfigPaths.ManifestPath) 'lua\huaguoshan_config.lua') -Force
    $missingConfigResult = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool `
        -ManifestPath $missingConfigPaths.ManifestPath -OutputPath $missingConfigPaths.OutputPath 2>&1
    $missingConfigText = $missingConfigResult | Out-String
    if ($LASTEXITCODE -eq 0) { throw 'materializer unexpectedly accepted an unreadable Lua Config projection' }
    if ($missingConfigText -notmatch 'runtime_package Lua Config does not exist') {
        throw "materializer did not fail closed for an unreadable Lua Config projection: $missingConfigText"
    }
    if (Test-Path -LiteralPath $missingConfigPaths.OutputPath) { throw 'materializer wrote output without a readable Lua Config projection' }

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[1].slots[0].roles[0].stable_object_id =
        $bindingFixture.instance_map_contracts[0].slots[0].roles[0].stable_object_id
    Assert-MaterializerRejects $fixture 'cross-contract-duplicate-stable-id' 'duplicate global stable_object_id' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].slots = @()
    Assert-MaterializerRejects $fixture 'empty-verified-instance-slots' 'instance map contract slots must not be empty' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].slots[0].roles = @($bindingFixture.instance_map_contracts[0].slots[0].roles | Select-Object -First 3)
    Assert-MaterializerRejects $fixture 'missing-canonical-instance-role' 'slot roles must exactly match canonical role schema' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].slots[0].roles[3].role = 'unexpected_exit'
    Assert-MaterializerRejects $fixture 'unexpected-canonical-instance-role' 'role is not canonical' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].slots[0].roles[0].expected_type = 'point'
    Assert-MaterializerRejects $fixture 'canonical-instance-role-type' 'expected_type violates canonical role schema' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $dragonRoleSchema = @($bindingFixture.instance_contract_role_schema | Where-Object { $_.contract_key -eq 'HG_I_DRAGON_FOUR_SEAS' })[0]
    (@($dragonRoleSchema.roles | Where-Object { $_.role -eq 'slot_bounds' })[0]).expected_type = 'point'
    foreach ($slot in @($bindingFixture.instance_map_contracts[0].slots)) {
        (@($slot.roles | Where-Object { $_.role -eq 'slot_bounds' })[0]).expected_type = 'point'
    }
    Assert-MaterializerRejects $fixture 'lua-config-role-schema-drift' 'Lua Config instance contract role schema does not match map logic binding' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.encounter_resource_bindings[0].role = ''
    Assert-MaterializerRejects $fixture 'blank-public-resource-role' 'encounter resource binding has invalid role' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.encounter_resource_bindings[0].role = 'unexpected_public_role'
    Assert-MaterializerRejects $fixture 'nonempty-public-resource-role-drift' 'Lua Config encounter resource bindings do not match map logic binding' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.return_points = @($bindingFixture.return_points) + [pscustomobject]@{
        role = 'escape'; resource_key = 'pt_hg_spawn'; source = 'logic_resource'; expected_type = 'point'
    }
    Assert-MaterializerRejects $fixture 'extra-return-point' 'map logic binding return_points must contain exactly 4 entries' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.spawn_bindings[0] | Add-Member -NotePropertyName unexpected_spawn_field -NotePropertyValue $true
    Assert-MaterializerRejects $fixture 'unknown-spawn-field' 'spawn binding has unexpected property: unexpected_spawn_field' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $macaqueSpawn = @($bindingFixture.spawn_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_MACAQUE_KING' -and $_.unit_key -eq 'HG_U_MACAQUE_KING'
    })[0]
    if ($null -eq $macaqueSpawn) { throw 'Materializer cross-Boss fixture could not find the Macaque King spawn.' }
    $macaqueSpawn.anchor_key = 'arena_jiaomowang_phase1'
    Assert-MaterializerRejects -Manifest $fixture -Name 'cross-boss-arena' -ExpectedPattern @(
        'HG_E_MACAQUE_KING: public boss spawn anchor must match encounter boss_arena arena_mihouwang',
        'Lua Config spawn bindings do not match map logic binding'
    ) -Binding $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $macaqueEncounter = @($fixture.encounters | Where-Object { $_.record_key -eq 'HG_E_MACAQUE_KING' })[0]
    $jiaoEncounter = @($fixture.encounters | Where-Object { $_.record_key -eq 'HG_E_JIAO_KING' })[0]
    $macaqueEncounter.boss_unit_key = 'HG_U_JIAO_KING_P1'
    $jiaoEncounter.boss_unit_key = 'HG_U_MACAQUE_KING'
    $macaqueEncounter.map_logic_resource_keys = @($macaqueEncounter.map_logic_resource_keys | ForEach-Object {
        if ($_ -eq 'arena_mihouwang') { 'arena_jiaomowang_phase1' } else { $_ }
    })
    $jiaoEncounter.map_logic_resource_keys = @($jiaoEncounter.map_logic_resource_keys | ForEach-Object {
        if ($_ -eq 'arena_jiaomowang_phase1') { 'arena_mihouwang' } else { $_ }
    })
    $macaqueEncounter.map_logic_resource_roles.PSObject.Properties.Remove('arena_mihouwang')
    $macaqueEncounter.map_logic_resource_roles | Add-Member -NotePropertyName arena_jiaomowang_phase1 -NotePropertyValue boss_arena
    $jiaoEncounter.map_logic_resource_roles.PSObject.Properties.Remove('arena_jiaomowang_phase1')
    $jiaoEncounter.map_logic_resource_roles | Add-Member -NotePropertyName arena_mihouwang -NotePropertyValue boss_arena

    $bindingFixture = Copy-JsonObject $resolvedBinding
    (@($bindingFixture.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_MACAQUE_KING' -and $_.resource_key -eq 'arena_mihouwang'
    })[0]).resource_key = 'arena_jiaomowang_phase1'
    (@($bindingFixture.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_JIAO_KING' -and $_.resource_key -eq 'arena_jiaomowang_phase1'
    })[0]).resource_key = 'arena_mihouwang'
    $macaqueSpawn = @($bindingFixture.spawn_bindings | Where-Object { $_.encounter_key -eq 'HG_E_MACAQUE_KING' })[0]
    $jiaoSpawn = @($bindingFixture.spawn_bindings | Where-Object { $_.encounter_key -eq 'HG_E_JIAO_KING' })[0]
    $macaqueSpawn.unit_key = 'HG_U_JIAO_KING_P1'
    $macaqueSpawn.anchor_key = 'arena_jiaomowang_phase1'
    $jiaoSpawn.unit_key = 'HG_U_MACAQUE_KING'
    $jiaoSpawn.anchor_key = 'arena_mihouwang'
    Assert-MaterializerRejects -Manifest $fixture -Name 'synchronized-public-boss-identity-swap' `
        -ExpectedPattern @(
            'manifest HG_E_MACAQUE_KING: canonical public boss tuple must be HG_U_MACAQUE_KING -> arena_mihouwang',
            'map logic binding HG_E_MACAQUE_KING: canonical public boss tuple must be HG_U_MACAQUE_KING -> arena_mihouwang',
            'Lua Config HG_E_MACAQUE_KING: canonical public boss tuple must be HG_U_MACAQUE_KING -> arena_mihouwang'
        ) -Binding $bindingFixture -LuaBinding $bindingFixture -SynchronizePublicBindings

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $sharkAction = @($bindingFixture.encounter_action_bindings | Where-Object { $_.encounter_key -eq 'HG_E_SHARK_KING' })[0]
    if ($null -eq $sharkAction) { throw 'Materializer illegal action fixture could not find the Shark King action.' }
    $sharkAction.area_key = 'area_hg_shark_vortex_core'
    Assert-MaterializerRejects $fixture 'action-uses-wrong-resource-role' 'HG_E_SHARK_KING: action area must use interaction_area role' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.encounter_action_bindings[0] | Add-Member -NotePropertyName unexpected_action_field -NotePropertyValue 1
    Assert-MaterializerRejects $fixture 'unknown-action-field' 'encounter action binding has unexpected property: unexpected_action_field' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bossPocket = @($bindingFixture.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_JIAO_KING' -and $_.resource_key -eq 'area_hg_boss_jiao'
    })[0]
    $bossPocket.expected_type = 'circleArea'
    Assert-MaterializerRejects $fixture 'nonempty-public-resource-type-drift' 'Lua Config encounter resource bindings do not match map logic binding' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts = @($bindingFixture.instance_map_contracts) + $bindingFixture.instance_map_contracts[0]
    Assert-MaterializerRejects $fixture 'duplicate-instance-contract-key' 'duplicate instance map contract key' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[1].contract_key = 'HG_I_UNKNOWN'
    Assert-MaterializerRejects $fixture 'unknown-instance-contract-key' 'unknown instance map contract key' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].encounter_keys = @('HG_E_UNKNOWN','HG_E_DRAGON_REVERSE_TIDE')
    Assert-MaterializerRejects $fixture 'unknown-instance-encounter' 'references unknown encounter' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].encounter_keys = @('HG_E_DRAGON_OLD_TIDE','HG_E_DRAGON_OLD_TIDE')
    Assert-MaterializerRejects $fixture 'duplicate-instance-encounter' 'duplicate encounter key' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].encounter_keys = @('HG_E_MACAQUE_KING','HG_E_DRAGON_REVERSE_TIDE')
    Assert-MaterializerRejects $fixture 'non-instance-encounter' 'references non-instance encounter' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.encounter_instance_map_states[0].state = 'pending'
    Assert-MaterializerRejects $fixture 'instance-state-mismatch' 'encounter instance map state must be verified' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.encounter_instance_map_states[0].slot_count = 3
    Assert-MaterializerRejects $fixture 'instance-state-slot-count-drift' 'encounter instance map state slot_count contradicts contract' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    (@($fixture.encounters | Where-Object { $_.record_key -eq 'HG_E_DRAGON_OLD_TIDE' })[0]).runtime_fields.instance_slots = 3
    Assert-MaterializerRejects $fixture 'manifest-instance-slot-count-drift' 'manifest instance_slots does not match instance map contract' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.encounter_instance_map_states[2].contract_key = 'HG_I_DRAGON_FOUR_SEAS'
    Assert-MaterializerRejects $fixture 'instance-contract-mapping-mismatch' 'invalid contract mapping' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].slots[0].roles[1].resource_key = $bindingFixture.instance_map_contracts[0].slots[0].roles[0].resource_key
    Assert-MaterializerRejects $fixture 'duplicate-instance-resource' 'resource_key is duplicated globally' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].slots[0].roles[1].role = $bindingFixture.instance_map_contracts[0].slots[0].roles[0].role
    Assert-MaterializerRejects $fixture 'duplicate-instance-role' 'instance map contract role is duplicated' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].slots[1].slot_id = $bindingFixture.instance_map_contracts[0].slots[0].slot_id
    Assert-MaterializerRejects $fixture 'duplicate-instance-slot' 'invalid or duplicate slot_id' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.production_ids_ready = $false
    Assert-MaterializerRejects $fixture 'cross-artifact-production-gate-drift' 'map logic binding production_ids_ready gate does not match manifest runtime package' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.runtime_contract_id = 'huaguoshan-96x72-runtime-v2'
    Assert-MaterializerRejects $fixture 'cross-artifact-runtime-contract-drift' 'map logic binding runtime contract does not match manifest runtime package' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $bindingFixture = Copy-JsonObject $resolvedBinding
    $bindingFixture.instance_map_contracts[0].state = 'pending'
    $bindingFixture.encounter_instance_map_states[0].state = 'pending'
    Assert-MaterializerRejects $fixture 'pending-instance-contract' 'instance map contract must be verified' $bindingFixture

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.runtime_package.map_logic_binding_path = '..\outside-binding.json'
    Assert-MaterializerRejects $fixture 'binding-path-escape' 'map_logic_binding_path must resolve to a file inside the manifest package' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.units[0].status = 'reviewed'
    Assert-MaterializerRejects $fixture 'reviewed-object-status' 'status must be id-assigned before materialization' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.units[0].operation = 'update'
    Assert-MaterializerRejects $fixture 'noncreate-object-operation' 'operation must be create before materialization' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.execution_gates.PSObject.Properties.Remove('distance_scale_verified')
    Assert-MaterializerRejects $fixture 'missing-gate' 'execution_gates missing required property: distance_scale_verified' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.execution_gates.unit_ids_assigned = 1
    Assert-MaterializerRejects $fixture 'nonboolean-gate' 'execution gate must be boolean: unit_ids_assigned' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.abilities[0].y3_id = $fixture.units[0].y3_id
    Assert-MaterializerRejects $fixture 'duplicate-production-id' 'duplicate global y3_id' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.units[0].y3_id = [string]$fixture.units[0].y3_id
    Assert-MaterializerRejects $fixture 'noninteger-production-id' 'y3_id must be a positive integer' (Copy-JsonObject $resolvedBinding)

    $fakeEditor = Join-Path $tempRoot 'fake\y3_obj_edit.py'
    New-Item -ItemType Directory -Path (Split-Path -Parent $fakeEditor) -Force | Out-Null
    Set-Content -LiteralPath $fakeEditor -Encoding UTF8 -Value 'def create_unit(): pass'
    $fixture = Copy-JsonObject $resolvedManifest
    $fixture.execution_gates.y3_obj_edit_script = $fakeEditor
    Assert-MaterializerRejects $fixture 'fake-object-editor' 'must point to skills/y3-obj-edit/scripts/y3_obj_edit.py' (Copy-JsonObject $resolvedBinding)

    $fixture = Copy-JsonObject $resolvedManifest
    Assert-MaterializerRejects -Manifest $fixture -Name 'wrong-output-type' -ExpectedPattern 'OutputPath must use the \.ps1 extension' -Binding (Copy-JsonObject $resolvedBinding) -OutputExtension '.txt'

    Write-Output 'PASS: materializer requires the strict binding schema, matching editor and instance state, production paths, stable IDs, and complete production data before emitting commands.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
