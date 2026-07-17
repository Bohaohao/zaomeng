$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $root '..\..')).Path
$manifestPath = Join-Path $root 'preconstruction-manifest.json'
$bindingPath = Join-Path $root 'map-logic-binding.json'
$preflightPath = Join-Path $PSScriptRoot 'preflight.ps1'
$layoutPath = (Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs') -Recurse -File -Filter 'layout.json' |
    Where-Object { $_.FullName -like '*huaguoshan-96x72*' } |
    Select-Object -First 1).FullName
if ([string]::IsNullOrWhiteSpace($layoutPath)) { throw 'Missing huaguoshan-96x72 layout.json.' }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('huaguoshan-preflight-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

function Read-Manifest {
    return Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-Binding {
    return Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-PreflightRejects {
    param($Manifest, [string]$Name, [string]$ExpectedPattern, $Binding = $null)
    $fixturePath = Join-Path $tempRoot ($Name + '.json')
    $Manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixturePath -Encoding UTF8
    $declaredBindingFixturePath = Join-Path $tempRoot 'map-logic-binding.json'
    (Read-Binding) | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $declaredBindingFixturePath -Encoding UTF8
    if ($null -ne $Binding) {
        $bindingFixturePath = Join-Path $tempRoot ($Name + '-binding.json')
        $Binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bindingFixturePath -Encoding UTF8
        $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $fixturePath -LayoutPath $layoutPath -BindingPath $bindingFixturePath 2>&1
    }
    else {
        $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $fixturePath -LayoutPath $layoutPath 2>&1
    }
    $exitCode = $LASTEXITCODE
    $text = $result | Out-String
    if ($exitCode -eq 0) { throw "preflight unexpectedly accepted fixture: $Name" }
    if ($text -notmatch $ExpectedPattern) { throw "preflight did not report $ExpectedPattern for ${Name}: $text" }
}

function Assert-PreflightRawManifestRejects {
    param([string]$ManifestText, [string]$Name, [string]$ExpectedPattern)
    $fixturePath = Join-Path $tempRoot ($Name + '.json')
    $bindingFixturePath = Join-Path $tempRoot 'map-logic-binding.json'
    Set-Content -LiteralPath $fixturePath -Encoding UTF8 -Value $ManifestText
    (Read-Binding) | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bindingFixturePath -Encoding UTF8
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath `
            -ManifestPath $fixturePath -LayoutPath $layoutPath -BindingPath $bindingFixturePath 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorActionPreference }
    $text = $result | Out-String
    if ($exitCode -eq 0) { throw "preflight unexpectedly accepted raw fixture: $Name" }
    if ($text -notmatch $ExpectedPattern) { throw "preflight did not report $ExpectedPattern for ${Name}: $text" }
}

function Assert-AdapterInstanceMapContractGuard {
    $fixturePath = Join-Path $tempRoot 'adapter-instance-map-contract-guard.lua'
    $script = @'
package.path = 'lua/?.lua;' .. package.path

local Config = require 'huaguoshan_config'
local Binding = require 'huaguoshan_map_binding'
local Adapter = require 'huaguoshan_y3_adapter'

local function equal(actual, expected, message)
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end

local function resolver(key, source, expected_type)
    return {
        logic_key = key,
        engine_object_id = 'engine:' .. key,
        ref = { id = key },
        source = source,
        type = expected_type,
    }
end

local executed = 0
local function live_options()
    return {
        mode = 'live',
        real_map_binding_verified = true,
        production_ids_ready = true,
        y3editor_connected = true,
        map_logic_resources_verified = true,
        unit_ids_assigned = true,
        ability_ids_assigned = true,
        modifier_ids_assigned = true,
        projectile_ids_assigned = true,
        model_ids_assigned = true,
        icon_ids_assigned = true,
        effect_resources_assigned = true,
        encounter_runtime_bound = true,
        distance_scale_verified = true,
        instance_map_contract_verified = true,
        authoritative_progression_validator_bound = true,
        resolve_logic_resource = resolver,
        emit_command = function() executed = executed + 1 return true end,
    }
end
local live = Adapter.new(live_options())
assert(live:bind_map(Binding.new(), Config.layout_contract.id))
local emitted, emit_error = live:emit({ commands = {
    { type = 'pending-instance-bypass', encounter_key = 'HG_E_DRAGON_OLD_TIDE' },
} })
equal(emitted, false, 'direct emit cannot bypass a rejected pending instance')
equal(emit_error, 'instance-map-contract-state-not-verified:HG_E_DRAGON_OLD_TIDE', 'emit reuses the instance start contract')
equal(executed, 0, 'rejected instance emit never calls the executor')

for _, encounter_key in ipairs({ 'HG_E_DRAGON_OLD_TIDE', 'HG_E_OX_BATTLEFIELD' }) do
    local allowed, error_code = live:can_start_encounter(encounter_key)
    equal(allowed, false, 'live pending instance contract is rejected')
    equal(error_code, 'instance-map-contract-state-not-verified:' .. encounter_key, 'live rejection names the pending encounter')
end

local offline = Adapter.new({ mode = 'offline_test', resolve_logic_resource = resolver })
assert(offline:bind_map(Binding.new(), Config.layout_contract.id))
assert(offline:can_start_encounter('HG_E_DRAGON_OLD_TIDE'))
print('PASS: adapter instance map contract guard')
'@
    Set-Content -LiteralPath $fixturePath -Encoding UTF8 -Value $script

    Push-Location $root
    try {
    $lua = Get-Command lua -ErrorAction SilentlyContinue
    if ($lua) {
        $result = & $lua.Source $fixturePath 2>&1
    }
    else {
        $node = (Get-Command node -ErrorAction SilentlyContinue).Source
        $fengari = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'pnpm\store') -Recurse -File -Filter 'lua-cli.js' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$' } |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $node -or -not $fengari) { throw 'Lua runtime is required for adapter instance map contract regression coverage.' }
        $result = & $node $fengari $fixturePath 2>&1
    }
    }
    finally {
        Pop-Location
    }
    $exitCode = $LASTEXITCODE
    $text = $result | Out-String
    if ($exitCode -ne 0 -or $text -notmatch 'PASS: adapter instance map contract guard') {
        throw "adapter instance map contract regression failed: $text"
    }
}

try {
    $manifest = Read-Manifest
    $manifest.units[0].common_ability_keys = @('HG_A_MISSING')
    Assert-PreflightRejects $manifest 'missing-reference' 'unknown common ability HG_A_MISSING'

    $manifest = Read-Manifest
    $manifest.execution_gates.PSObject.Properties.Remove('distance_scale_verified')
    Assert-PreflightRejects $manifest 'missing-gate' 'execution_gates missing required property: distance_scale_verified'

    $manifest = Read-Manifest
    $manifest.execution_gates.map_logic_resources_verified = 1
    Assert-PreflightRejects $manifest 'nonboolean-gate' 'execution gate must be boolean: map_logic_resources_verified'

    $manifest = Read-Manifest
    $manifest.units[0].y3_id = 990100001
    $manifest.abilities[0] | Add-Member -NotePropertyName y3_id -NotePropertyValue 990100001 -Force
    Assert-PreflightRejects $manifest 'duplicate-production-id' 'duplicate global y3_id 990100001'

    $manifest = Read-Manifest
    $manifest.units[0].status = 'draft'
    Assert-PreflightRejects $manifest 'unit-status' 'effective status/operation must remain reviewed/create'

    $manifest = Read-Manifest
    $manifest.abilities[0] | Add-Member -NotePropertyName status -NotePropertyValue 'draft' -Force
    Assert-PreflightRejects $manifest 'ability-status' 'effective status/operation must remain reviewed/create'

    $manifest = Read-Manifest
    $manifest.modifiers[0] | Add-Member -NotePropertyName operation -NotePropertyValue 'update' -Force
    Assert-PreflightRejects $manifest 'modifier-operation' 'effective status/operation must remain reviewed/create'

    $manifest = Read-Manifest
    $manifest.projectiles[0] | Add-Member -NotePropertyName status -NotePropertyValue 'id-assigned' -Force
    Assert-PreflightRejects $manifest 'projectile-status' 'effective status/operation must remain reviewed/create'

    $manifest = Read-Manifest
    $manifest.units[0].object_fields | Add-Member -NotePropertyName attack_phyy -NotePropertyValue 1
    Assert-PreflightRejects $manifest 'unknown-unit-object-field' 'object_fields unknown field: attack_phyy'

    $manifestText = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $attackPropertyPattern = [regex]'"attack_phy":22'
    if ($attackPropertyPattern.Matches($manifestText).Count -lt 1) {
        throw 'duplicate-property fixture could not locate the first attack_phy field'
    }
    $duplicateAttackText = $attackPropertyPattern.Replace(
        $manifestText,
        '"attack_phy":22,"attack_phy":999',
        1
    )
    Assert-PreflightRawManifestRejects $duplicateAttackText 'duplicate-raw-attack-phy' `
        'duplicate JSON property "attack_phy" at \$\.units\[0\]\.object_fields'

    $manifest = Read-Manifest
    $manifest.units[0].object_fields.PSObject.Properties.Remove('attack_phy')
    $manifest.units[0].object_fields | Add-Member -NotePropertyName Attack_phy -NotePropertyValue 1
    Assert-PreflightRejects $manifest 'wrong-case-unit-object-field' 'object_fields unknown field: Attack_phy'

    $manifest = Read-Manifest
    $manifest.units[0].object_fields.hp_max = '280'
    Assert-PreflightRejects $manifest 'invalid-unit-object-field-type' 'object_fields hp_max must be a positive finite number'

    $manifest = Read-Manifest
    $manifest.abilities[0].object_fields | Add-Member -NotePropertyName sight_type -NotePropertyValue 99 -Force
    Assert-PreflightRejects $manifest 'invalid-ability-enum' 'object_fields sight_type must be one of:'

    $manifest = Read-Manifest
    $manifest.abilities[0].object_fields | Add-Member -NotePropertyName cold_down_time -NotePropertyValue @(8, 7) -Force
    Assert-PreflightRejects $manifest 'invalid-ability-level-array-length' 'object_fields cold_down_time must contain exactly 1 values'

    $manifest = Read-Manifest
    $manifest.projectiles[0].object_fields | Add-Member -NotePropertyName move_channel -NotePropertyValue 9 -Force
    Assert-PreflightRejects $manifest 'invalid-projectile-enum' 'object_fields move_channel must be one of:'

    $manifest = Read-Manifest
    $oldTide = @($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_DRAGON_OLD_TIDE' })[0]
    $oldTide.runtime_fields.route_completion.trial_seconds = 59
    Assert-PreflightRejects $manifest 'old-tide-route-duration' 'HG_E_DRAGON_OLD_TIDE route completion trial_seconds must be 60'

    $manifest = Read-Manifest
    $oldTide = @($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_DRAGON_OLD_TIDE' })[0]
    $oldTide.runtime_fields.route_completion.completion_keys_by_profession.C04 = @('C04_ROUTE_LV8_hunt','C04_ROUTE_LV8_wind')
    Assert-PreflightRejects $manifest 'old-tide-route-c04-key-drift' 'HG_E_DRAGON_OLD_TIDE route completion keys differ for C04'

    $publicBossAnchors = @(
        [pscustomobject]@{ Encounter = 'HG_E_MOUNTAIN_PATH'; Resource = 'arena_gorilla'; Role = 'major_elite_anchor' },
        [pscustomobject]@{ Encounter = 'HG_E_PEACH_GROVE'; Resource = 'arena_yurongwang'; Role = 'major_elite_anchor' },
        [pscustomobject]@{ Encounter = 'HG_E_BAT_CAVE'; Resource = 'arena_bat_statue'; Role = 'major_elite_anchor' }
    )
    $manifest = Read-Manifest
    foreach ($contract in $publicBossAnchors) {
        $encounter = @($manifest.encounters | Where-Object { $_.record_key -eq $contract.Encounter })[0]
        if ($null -eq $encounter -or @($encounter.map_logic_resource_keys) -notcontains $contract.Resource) {
            throw "$($contract.Encounter) manifest is missing public Boss anchor $($contract.Resource)"
        }
        $roleProperty = $encounter.map_logic_resource_roles.PSObject.Properties[$contract.Resource]
        if ($null -eq $roleProperty -or $roleProperty.Value -ne $contract.Role) {
            throw "$($contract.Encounter) manifest has an invalid role for public Boss anchor $($contract.Resource)"
        }
    }

    $manifest = Read-Manifest
    $mountainEncounter = @($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_MOUNTAIN_PATH' })[0]
    $mountainEncounter.map_logic_resource_keys = @($mountainEncounter.map_logic_resource_keys | Where-Object { $_ -ne 'arena_gorilla' })
    $mountainEncounter.map_logic_resource_roles.PSObject.Properties.Remove('arena_gorilla')
    Assert-PreflightRejects $manifest 'manifest-omits-public-boss-anchor' `
        'map logic binding declares resource absent from manifest: HG_E_MOUNTAIN_PATH\|arena_gorilla'

    $manifest = Read-Manifest
    (@($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_MOUNTAIN_PATH' })[0]).map_logic_resource_roles.arena_gorilla = 'unexpected_major_anchor'
    Assert-PreflightRejects $manifest 'manifest-public-resource-role-drift' `
        'manifest resource role differs from map logic binding for HG_E_MOUNTAIN_PATH\|arena_gorilla'

    $binding = Read-Binding
    $binding.encounter_resource_bindings[0].role = 'unexpected_public_role'
    Assert-PreflightRejects (Read-Manifest) 'unknown-public-resource-role' `
        'encounter resource binding has invalid role: unexpected_public_role' $binding

    $binding = Read-Binding
    $binding.encounter_resource_bindings[0].expected_type = 'polygon'
    Assert-PreflightRejects (Read-Manifest) 'unknown-public-resource-type' `
        'encounter resource binding role contract is invalid for HG_E_MOUNTAIN_PATH\|area_hg_public_mountain' $binding

    $binding = Read-Binding
    $binding.return_points[0].source = 'future_source'
    Assert-PreflightRejects (Read-Manifest) 'unknown-return-source' `
        'return point source/type is invalid for role spawn' $binding

    $binding = Read-Binding
    $binding.return_points = @($binding.return_points) + [pscustomobject]@{
        role = 'escape'; resource_key = 'pt_hg_spawn'; source = 'logic_resource'; expected_type = 'point'
    }
    Assert-PreflightRejects (Read-Manifest) 'extra-return-point' `
        'map logic binding return_points must contain exactly 4 entries' $binding

    $binding = Read-Binding
    $binding.spawn_bindings[0] | Add-Member -NotePropertyName unexpected_spawn_field -NotePropertyValue $true
    Assert-PreflightRejects (Read-Manifest) 'unknown-spawn-field' `
        'spawn binding has unexpected property: unexpected_spawn_field' $binding

    $binding = Read-Binding
    $macaqueSpawn = @($binding.spawn_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_MACAQUE_KING' -and $_.unit_key -eq 'HG_U_MACAQUE_KING'
    })[0]
    if ($null -eq $macaqueSpawn) { throw 'Cross-Boss arena fixture could not find the Macaque King spawn.' }
    $macaqueSpawn.anchor_key = 'arena_jiaomowang_phase1'
    Assert-PreflightRejects (Read-Manifest) 'cross-boss-arena' `
        'HG_E_MACAQUE_KING: public boss spawn anchor must match encounter boss_arena arena_mihouwang' $binding

    $binding = Read-Binding
    $sharkAction = @($binding.encounter_action_bindings | Where-Object { $_.encounter_key -eq 'HG_E_SHARK_KING' })[0]
    if ($null -eq $sharkAction) { throw 'Illegal action fixture could not find the Shark King action.' }
    $sharkAction.area_key = 'area_hg_shark_vortex_core'
    Assert-PreflightRejects (Read-Manifest) 'action-uses-wrong-resource-role' `
        'HG_E_SHARK_KING: action area must use interaction_area role' $binding

    $binding = Read-Binding
    $binding.encounter_action_bindings[0] | Add-Member -NotePropertyName unexpected_action_field -NotePropertyValue 1
    Assert-PreflightRejects (Read-Manifest) 'unknown-action-field' `
        'encounter action binding has unexpected property: unexpected_action_field' $binding

    $binding = Read-Binding
    $binding.PSObject.Properties.Remove('instance_map_contract_verified')
    Assert-PreflightRejects (Read-Manifest) 'missing-instance-contract-gate' 'map logic binding missing required property: instance_map_contract_verified' $binding

    $binding = Read-Binding
    $binding.instance_map_contract_verified = 1
    Assert-PreflightRejects (Read-Manifest) 'nonboolean-instance-contract-gate' 'map logic binding property must be boolean: instance_map_contract_verified' $binding

    $binding = Read-Binding
    $binding.PSObject.Properties.Remove('instance_map_contracts')
    Assert-PreflightRejects (Read-Manifest) 'missing-instance-contracts' 'map logic binding missing required property: instance_map_contracts' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].slots = @()
    Assert-PreflightRejects (Read-Manifest) 'empty-instance-slots' 'instance map contract slots must not be empty for HG_I_DRAGON_FOUR_SEAS' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].slots[0].roles = @($binding.instance_map_contracts[0].slots[0].roles | Select-Object -First 3)
    Assert-PreflightRejects (Read-Manifest) 'missing-canonical-instance-role' 'instance map contract slot roles must exactly match canonical role schema for HG_I_DRAGON_FOUR_SEAS:1' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].slots[0].roles[3].role = 'unexpected_exit'
    Assert-PreflightRejects (Read-Manifest) 'unexpected-canonical-instance-role' 'instance role is not canonical for HG_I_DRAGON_FOUR_SEAS:1:unexpected_exit' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].slots[0].roles[0].expected_type = 'point'
    Assert-PreflightRejects (Read-Manifest) 'canonical-instance-role-type' 'instance role expected_type violates canonical role schema for HG_I_DRAGON_FOUR_SEAS:1:slot_bounds' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts = @($binding.instance_map_contracts) + $binding.instance_map_contracts[0]
    Assert-PreflightRejects (Read-Manifest) 'duplicate-contract-key' 'duplicate instance map contract key HG_I_DRAGON_FOUR_SEAS' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[1].contract_key = 'HG_I_UNKNOWN'
    Assert-PreflightRejects (Read-Manifest) 'unknown-contract-key' 'unknown instance map contract key HG_I_UNKNOWN' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].encounter_keys = @('HG_E_UNKNOWN','HG_E_DRAGON_REVERSE_TIDE')
    Assert-PreflightRejects (Read-Manifest) 'unknown-instance-encounter' 'instance map contract references unknown encounter HG_E_UNKNOWN' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].encounter_keys = @('HG_E_DRAGON_OLD_TIDE','HG_E_DRAGON_OLD_TIDE')
    Assert-PreflightRejects (Read-Manifest) 'duplicate-instance-encounter' 'duplicate encounter key in instance map contract HG_I_DRAGON_FOUR_SEAS' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].encounter_keys = @('HG_E_MACAQUE_KING','HG_E_DRAGON_REVERSE_TIDE')
    Assert-PreflightRejects (Read-Manifest) 'non-instance-encounter' 'instance map contract references non-instance encounter HG_E_MACAQUE_KING' $binding

    $binding = Read-Binding
    $binding.encounter_instance_map_states[0].state = 'verified'
    Assert-PreflightRejects (Read-Manifest) 'instance-state-mismatch' 'encounter instance map state differs from instance contract' $binding

    $binding = Read-Binding
    $binding.encounter_instance_map_states[2].contract_key = 'HG_I_DRAGON_FOUR_SEAS'
    Assert-PreflightRejects (Read-Manifest) 'instance-contract-mapping-mismatch' 'encounter instance map state contract mapping is invalid' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].slots[0].roles[1].resource_key = $binding.instance_map_contracts[0].slots[0].roles[0].resource_key
    Assert-PreflightRejects (Read-Manifest) 'duplicate-instance-resource' 'instance role resource_key is not globally unique' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].slots[0].roles[1].role = $binding.instance_map_contracts[0].slots[0].roles[0].role
    Assert-PreflightRejects (Read-Manifest) 'duplicate-instance-role' 'instance role name is invalid or duplicate' $binding

    $binding = Read-Binding
    $binding.instance_map_contracts[0].slots[1].slot_id = $binding.instance_map_contracts[0].slots[0].slot_id
    Assert-PreflightRejects (Read-Manifest) 'duplicate-instance-slot' 'instance map contract has invalid or duplicate slot_id' $binding

    $binding = Read-Binding
    $binding.instance_map_contract_verified = $true
    Assert-PreflightRejects (Read-Manifest) 'pending-instance-contract-claims-verified' 'instance_map_contract_verified cannot be true while pending instance map contracts remain' $binding

    Assert-PreflightRejects (Read-Manifest) 'binding-path-mismatch' 'BindingPath must match runtime_package map_logic_binding_path' (Read-Binding)

    $manifest = Read-Manifest
    $manifest.runtime_package.map_logic_binding_path = $null
    Assert-PreflightRejects $manifest 'missing-binding-path' 'runtime_package map_logic_binding_path must be a non-empty package-relative path' (Read-Binding)

    $binding = Read-Binding
    $manifest = Read-Manifest
    $nextStableId = 1000
    foreach ($contract in @($binding.instance_map_contracts)) {
        $contract.state = 'verified'
        foreach ($slot in @($contract.slots)) { foreach ($role in @($slot.roles)) { $nextStableId++; $role.stable_object_id = $nextStableId } }
    }
    foreach ($state in @($binding.encounter_instance_map_states)) { $state.state = 'verified' }
    foreach ($encounter in @($manifest.encounters | Where-Object { $_.combat_scope -in @('solo_instance','team_instance') })) { $encounter.runtime_fields.map_binding_state = 'verified' }
    Assert-PreflightRejects $manifest 'verified-instance-contracts-claim-unverified' 'instance_map_contract_verified must be true when all instance map contracts are verified' $binding

    $binding = Read-Binding
    $manifest = Read-Manifest
    $verifiedContracts = @($binding.instance_map_contracts | Select-Object -First 2)
    if ($verifiedContracts.Count -lt 2) { throw 'Cross-contract stable_object_id fixture requires at least two instance map contracts.' }
    $nextStableId = 88000
    foreach ($contract in $verifiedContracts) {
        $contract.state = 'verified'
        foreach ($encounterKey in @($contract.encounter_keys)) {
            ($binding.encounter_instance_map_states | Where-Object { $_.encounter_key -eq $encounterKey }).state = 'verified'
            ($manifest.encounters | Where-Object { $_.record_key -eq $encounterKey }).runtime_fields.map_binding_state = 'verified'
        }
        foreach ($slot in @($contract.slots)) {
            foreach ($role in @($slot.roles)) {
                $nextStableId++
                $role.stable_object_id = $nextStableId
            }
        }
    }
    $verifiedContracts[1].slots[0].roles[0].stable_object_id = $verifiedContracts[0].slots[0].roles[0].stable_object_id
    Assert-PreflightRejects $manifest 'cross-contract-stable-id-reuse' 'verified instance role stable_object_id is not globally unique: 88001' $binding

    $manifest = Read-Manifest
    $manifest.runtime_package.instance_map_contract_verified = $true
    Assert-PreflightRejects $manifest 'manifest-instance-contract-gate-mismatch' 'map logic binding instance_map_contract_verified gate does not match manifest runtime package'

    $manifest = Read-Manifest
    ($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_DRAGON_OLD_TIDE' }).runtime_fields.map_binding_state = 'verified'
    Assert-PreflightRejects $manifest 'manifest-map-state-drift' 'manifest map_binding_state differs from instance contract'

    $binding = Read-Binding
    $binding.instance_map_contracts[0].slots[0].roles[0].stable_object_id = 9001
    Assert-PreflightRejects (Read-Manifest) 'pending-stable-id-claim' 'pending instance role must not claim stable_object_id' $binding

    Assert-AdapterInstanceMapContractGuard
    Write-Output 'PASS: preflight rejects missing references, manifest resource drift, strict-gate violations, contradictory instance contracts, and duplicate production IDs.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
