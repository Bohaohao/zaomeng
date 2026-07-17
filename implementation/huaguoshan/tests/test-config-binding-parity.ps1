$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$configPath = Join-Path $root 'implementation\huaguoshan\lua\huaguoshan_config.lua'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('huaguoshan-config-parity-' + [guid]::NewGuid().ToString('N'))
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
$fengari = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'pnpm\store') -Recurse -File -Filter 'lua-cli.js' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$' } |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $node -or -not $fengari) { throw 'cached fengari-node-cli and node are required for config parity verification' }

function ConvertTo-CanonicalValue {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $result[[string]$key] = ConvertTo-CanonicalValue $Value[$key]
        }
        return [pscustomobject]$result
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [pscustomobject])) {
        return @($Value | ForEach-Object { ConvertTo-CanonicalValue $_ })
    }
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
        $result[$property.Name] = ConvertTo-CanonicalValue $property.Value
    }
    return [pscustomobject]$result
}

function Get-CanonicalJson {
    param([AllowNull()][object]$Value)
    return (ConvertTo-CanonicalValue $Value | ConvertTo-Json -Depth 32 -Compress)
}

Push-Location $root
try {
    $output = & $node $fengari 'implementation/huaguoshan/tests/export_config_binding_projection.lua' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Lua config projection failed: $($output | Out-String)" }
    $actual = ($output | Out-String | ConvertFrom-Json)
    $binding = Get-Content -Raw -Encoding UTF8 'implementation/huaguoshan/map-logic-binding.json' | ConvertFrom-Json
    $manifest = Get-Content -Raw -Encoding UTF8 'implementation/huaguoshan/preconstruction-manifest.json' | ConvertFrom-Json

    $expected = [ordered]@{
        runtime_contract_id = $binding.runtime_contract_id
        editor_bound = $binding.real_map_binding_verified
        instance_map_contract_verified = $binding.instance_map_contract_verified
        return_points = @($binding.return_points | Sort-Object role | ForEach-Object {
            [ordered]@{ role = $_.role; resource_key = $_.resource_key; source = $_.source; expected_type = $_.expected_type }
        })
        encounter_resource_bindings = @($binding.encounter_resource_bindings | Sort-Object encounter_key, resource_key | ForEach-Object {
            [ordered]@{ encounter_key = $_.encounter_key; resource_key = $_.resource_key; source = $_.source; expected_type = $_.expected_type; role = $_.role }
        })
        spawn_bindings = @($binding.spawn_bindings | Sort-Object encounter_key, anchor_key, unit_key | ForEach-Object {
            [ordered]@{ encounter_key = $_.encounter_key; anchor_key = $_.anchor_key; unit_key = $_.unit_key }
        })
        encounter_action_bindings = @($binding.encounter_action_bindings | Sort-Object encounter_key | ForEach-Object {
            $item = [ordered]@{
                encounter_key = $_.encounter_key; action_key = $_.action_key; area_key = $_.area_key; anchor_key = $_.anchor_key
                radius_cells = $_.radius_cells; max_concurrent = $_.max_concurrent; read_seconds = $_.read_seconds
            }
            if ($null -ne $_.window_seconds) { $item.window_seconds = $_.window_seconds }
            if ($null -ne $_.postlude_seconds) { $item.postlude_seconds = $_.postlude_seconds }
            if ($null -ne $_.required_inside_area_key) { $item.required_inside_area_key = $_.required_inside_area_key }
            if ($null -ne $_.required_outside_area_key) { $item.required_outside_area_key = $_.required_outside_area_key }
            $item
        })
        encounter_instance_map_states = @($binding.encounter_instance_map_states | Sort-Object encounter_key | ForEach-Object {
            [ordered]@{
                encounter_key = $_.encounter_key; contract_key = $_.contract_key
                state = $_.state; slot_count = $_.slot_count
            }
        })
        instance_contract_role_schema = @($binding.instance_contract_role_schema | Sort-Object contract_key | ForEach-Object {
            [ordered]@{
                contract_key = $_.contract_key; layer = $_.layer; slot_count = $_.slot_count
                roles = @($_.roles | Sort-Object role | ForEach-Object {
                    [ordered]@{ role = $_.role; expected_type = $_.expected_type }
                })
            }
        })
        instance_map_contracts = @($binding.instance_map_contracts | Sort-Object contract_key | ForEach-Object {
            [ordered]@{
                contract_key = $_.contract_key; encounter_keys = @($_.encounter_keys)
                state = $_.state; layer = $_.layer; slot_count = $_.slot_count
                slots = @($_.slots | Sort-Object slot_id | ForEach-Object {
                    [ordered]@{
                        slot_id = $_.slot_id
                        roles = @($_.roles | ForEach-Object {
                            [ordered]@{
                                role = $_.role; resource_key = $_.resource_key; source = $_.source
                                expected_type = $_.expected_type; layer = $_.layer; stable_object_id = $_.stable_object_id
                            }
                        })
                    }
                })
            }
        })
    }

    $manifestResourceContracts = @($manifest.encounters | ForEach-Object {
        $encounter = $_
        @($encounter.map_logic_resource_keys | ForEach-Object {
            $resourceKey = [string]$_
            $roleProperty = $encounter.map_logic_resource_roles.PSObject.Properties[$resourceKey]
            $role = if ($null -eq $roleProperty) { '<missing-role>' } else { [string]$roleProperty.Value }
            "$($encounter.record_key)|$resourceKey|$role"
        })
    } | Sort-Object)
    $bindingResourceContracts = @($binding.encounter_resource_bindings | Sort-Object encounter_key, resource_key | ForEach-Object {
        "$($_.encounter_key)|$($_.resource_key)|$($_.role)"
    })
    if ((Get-CanonicalJson $manifestResourceContracts) -ne (Get-CanonicalJson $bindingResourceContracts)) {
        throw 'Manifest encounter resource keys/roles do not match map-logic-binding.json.'
    }

    $oxManifestEncounter = @($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_OX_BATTLEFIELD' })
    if ($oxManifestEncounter.Count -ne 1 -or
        $oxManifestEncounter[0].runtime_fields.failure_return_point -ne 'pt_hg_spawn' -or
        $oxManifestEncounter[0].runtime_fields.member_death_return_point -ne 'pt_hg_spawn' -or
        $oxManifestEncounter[0].runtime_fields.timeout_return_point -ne 'pt_hg_spawn' -or
        $oxManifestEncounter[0].runtime_fields.member_death_reentry_policy -ne 'deny_until_cleanup_ack') {
        throw 'Ox Battlefield manifest must return failed members to pt_hg_spawn and lock re-entry until cleanup acknowledgment.'
    }
    $reverseTideManifestEncounter = @($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_DRAGON_REVERSE_TIDE' })
    if ($reverseTideManifestEncounter.Count -ne 1 -or
        $reverseTideManifestEncounter[0].runtime_fields.unlock_rule -ne 'level_at_least_38_and_difu_yanluo_hall_cleared' -or
        $reverseTideManifestEncounter[0].runtime_fields.progression_key -ne 'DF_PROGRESS_YANLUO_HALL_CLEARED') {
        throw 'Reverse Tide manifest must require the trusted Yanluo Hall completion progression key.'
    }
    $oxBindingFailureReturn = @($binding.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_OX_BATTLEFIELD' -and $_.role -eq 'failure_return'
    })
    $oxProjectedFailureReturn = @($actual.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_OX_BATTLEFIELD' -and $_.role -eq 'failure_return'
    })
    if ($oxBindingFailureReturn.Count -ne 1 -or $oxBindingFailureReturn[0].resource_key -ne 'pt_hg_spawn' -or
        $oxProjectedFailureReturn.Count -ne 1 -or $oxProjectedFailureReturn[0].resource_key -ne 'pt_hg_spawn') {
        throw 'Ox Battlefield Config projection and map binding must both expose pt_hg_spawn as failure_return.'
    }

    $actualJson = Get-CanonicalJson $actual
    $expectedJson = Get-CanonicalJson ([pscustomobject]$expected)
    if ($actualJson -ne $expectedJson) {
        $differences = @()
        foreach ($property in @('runtime_contract_id','editor_bound','instance_map_contract_verified','return_points','encounter_resource_bindings','spawn_bindings','encounter_action_bindings','encounter_instance_map_states','instance_contract_role_schema','instance_map_contracts')) {
            if ((Get-CanonicalJson $actual.$property) -ne (Get-CanonicalJson $expected[$property])) { $differences += $property }
        }
        throw "Lua configuration and map-logic-binding.json drifted at: $($differences -join ', ')"
    }

    $roleDriftExpected = $expected | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $roleDriftEntry = @($roleDriftExpected.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_JIAO_KING' -and $_.resource_key -eq 'area_hg_boss_jiao'
    })[0]
    if ($null -eq $roleDriftEntry) { throw 'role-drift fixture could not locate HG_E_JIAO_KING boss pocket' }
    $roleDriftEntry.role = 'unexpected_role'
    if ((Get-CanonicalJson $actual) -eq (Get-CanonicalJson $roleDriftExpected)) {
        throw 'Lua configuration projection does not preserve encounter resource role semantics'
    }

    $contractStates = @($binding.instance_map_contracts | ForEach-Object {
        $contract = $_
        @($contract.encounter_keys | ForEach-Object {
            [pscustomobject][ordered]@{
                encounter_key = $_; contract_key = $contract.contract_key
                state = $contract.state; slot_count = $contract.slot_count
            }
        })
    } | Sort-Object encounter_key)
    $manifestStates = @($manifest.encounters | Where-Object { $_.combat_scope -in @('solo_instance','team_instance') } |
        Sort-Object record_key | ForEach-Object {
            [ordered]@{ encounter_key = $_.record_key; state = $_.runtime_fields.map_binding_state }
        })
    $projectedStatesJson = Get-CanonicalJson $expected.encounter_instance_map_states
    $projectedManifestStates = @($expected.encounter_instance_map_states | ForEach-Object {
        [ordered]@{ encounter_key = $_.encounter_key; state = $_.state }
    })
    if ((Get-CanonicalJson $contractStates) -ne $projectedStatesJson -or
        (Get-CanonicalJson $manifestStates) -ne (Get-CanonicalJson $projectedManifestStates)) {
        throw 'Instance map binding state drifted between Lua encounter projection, Config contracts, JSON binding, and manifest encounters.'
    }

    $canonicalContractByEncounter = @{
        HG_E_DRAGON_OLD_TIDE = 'HG_I_DRAGON_FOUR_SEAS'
        HG_E_DRAGON_REVERSE_TIDE = 'HG_I_DRAGON_FOUR_SEAS'
        HG_E_OX_BATTLEFIELD = 'HG_I_OX_BATTLEFIELD'
    }
    foreach ($state in $expected.encounter_instance_map_states) {
        if (-not $canonicalContractByEncounter.ContainsKey($state.encounter_key) -or
            $canonicalContractByEncounter[$state.encounter_key] -ne $state.contract_key) {
            throw "Canonical instance contract mapping is invalid for $($state.encounter_key)."
        }
        $contract = @($expected.instance_map_contracts | Where-Object { $_.contract_key -eq $state.contract_key })
        if ($contract.Count -ne 1 -or $state.slot_count -ne $contract[0].slot_count) {
            throw "Projected slot_count must derive from the instance contract for $($state.encounter_key)."
        }
        $manifestEncounter = @($manifest.encounters | Where-Object { $_.record_key -eq $state.encounter_key })
        if ($manifestEncounter.Count -eq 1 -and $manifestEncounter[0].combat_scope -eq 'solo_instance' -and
            $manifestEncounter[0].runtime_fields.instance_slots -ne $state.slot_count) {
            throw "Manifest instance_slots must match the projected instance contract for $($state.encounter_key)."
        }
    }
    $dragonContract = @($expected.instance_map_contracts | Where-Object { $_.contract_key -eq 'HG_I_DRAGON_FOUR_SEAS' })
    if ($dragonContract.Count -ne 1 -or $dragonContract[0].slot_count -ne 4 -or
        (Get-CanonicalJson @($dragonContract[0].encounter_keys | Sort-Object)) -ne
        (Get-CanonicalJson @('HG_E_DRAGON_OLD_TIDE','HG_E_DRAGON_REVERSE_TIDE'))) {
        throw 'Dragon encounters must share the single four-slot HG_I_DRAGON_FOUR_SEAS contract.'
    }
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $configSource = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8

    $spawnDriftConfigPath = Join-Path $tempRoot 'huaguoshan_config_spawn_drift.lua'
    $spawnDriftPattern = "boss_unit_key = 'HG_U_MACAQUE_KING', boss_spawn_anchor = 'arena_mihouwang'"
    if ([regex]::Matches($configSource, [regex]::Escape($spawnDriftPattern)).Count -ne 1) {
        throw 'Lua Boss spawn drift fixture could not locate the Macaque King spawn binding.'
    }
    $spawnDriftSource = $configSource.Replace(
        $spawnDriftPattern,
        "boss_unit_key = 'HG_U_MACAQUE_KING', boss_spawn_anchor = 'arena_jiaomowang_phase1'"
    )
    Set-Content -LiteralPath $spawnDriftConfigPath -Value $spawnDriftSource -Encoding UTF8
    $spawnDriftOutput = & $node $fengari 'implementation/huaguoshan/tests/export_config_binding_projection.lua' $spawnDriftConfigPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Lua Boss spawn drift projection failed: $($spawnDriftOutput | Out-String)" }
    $spawnDriftProjection = $spawnDriftOutput | Out-String | ConvertFrom-Json
    $projectedMacaqueSpawn = @($spawnDriftProjection.spawn_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_MACAQUE_KING' -and $_.unit_key -eq 'HG_U_MACAQUE_KING'
    })
    if ($projectedMacaqueSpawn.Count -ne 1 -or $projectedMacaqueSpawn[0].anchor_key -ne 'arena_jiaomowang_phase1') {
        throw 'Lua projection did not preserve the drifted Boss spawn binding.'
    }
    if ((Get-CanonicalJson $spawnDriftProjection.spawn_bindings) -eq (Get-CanonicalJson $expected.spawn_bindings)) {
        throw 'Lua/JSON parity does not cover spawn bindings.'
    }

    $driftConfigPath = Join-Path $tempRoot 'huaguoshan_config.lua'
    $driftPattern = "(?m)(^\s*HG_E_DRAGON_OLD_TIDE\s*=\s*\{\r?\n\s*encounter_type\s*=\s*'solo_boss',\s*combat_scope\s*=\s*'solo_instance',\r?\n)"
    if ([regex]::Matches($configSource, $driftPattern).Count -ne 1) {
        throw 'Lua instance_slots drift fixture could not locate HG_E_DRAGON_OLD_TIDE.'
    }
    $driftSource = [regex]::Replace(
        $configSource,
        $driftPattern,
        ('$1        instance_slots = 3,' + [Environment]::NewLine)
    )
    Set-Content -LiteralPath $driftConfigPath -Value $driftSource -Encoding UTF8
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $driftOutput = & $node $fengari 'implementation/huaguoshan/tests/export_config_binding_projection.lua' $driftConfigPath 2>&1
        $driftExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $driftText = $driftOutput | Out-String
    if ($driftText -notmatch 'instance_slots must no\s*t be declared') {
        throw "Lua source slot drift did not fail at the single-source guard (exit=$driftExitCode): $driftText"
    }

    Write-Output 'PASS: Lua, JSON, and manifest map contracts match, including spawn bindings, public resource roles, and complete instance slot state.'
}
finally {
    Pop-Location
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
