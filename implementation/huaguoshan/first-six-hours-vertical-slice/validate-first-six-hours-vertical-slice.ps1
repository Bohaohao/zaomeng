[CmdletBinding()]
param(
    [string]$ContractPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $PSScriptRoot 'slice-contract.json'
}

$script:CheckCount = 0
$script:Errors = New-Object 'System.Collections.Generic.List[string]'

function Test-Requirement {
    param(
        [bool]$Condition,
        [string]$Message
    )

    $script:CheckCount += 1
    if (-not $Condition) {
        [void]$script:Errors.Add($Message)
    }
}

function Test-Property {
    param(
        $Object,
        [string]$Name,
        [string]$Context
    )

    $present = $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
    Test-Requirement $present "$Context is missing field $Name"
    return $present
}

function Test-ExactValue {
    param(
        $Actual,
        $Expected,
        [string]$Context
    )

    Test-Requirement ($Actual -eq $Expected) "$Context expected '$Expected', got '$Actual'"
}

function Test-RequiredProperties {
    param(
        $Object,
        [string[]]$Names,
        [string]$Context
    )

    foreach ($name in $Names) {
        [void](Test-Property -Object $Object -Name $name -Context $Context)
    }
}

function Test-ContainsValues {
    param(
        $Values,
        [string[]]$Expected,
        [string]$Context
    )

    $actual = @($Values)
    foreach ($value in $Expected) {
        Test-Requirement ($actual -contains $value) "$Context is missing value '$value'"
    }
}

function Get-JsonFile {
    param([string]$Path)

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

try {
    Test-Requirement (Test-Path -LiteralPath $ContractPath -PathType Leaf) "Contract file is missing: $ContractPath"
    if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
        throw "Contract file is missing: $ContractPath"
    }

    $contractText = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8
    $contract = $contractText | ConvertFrom-Json

    Test-RequiredProperties -Object $contract -Names @(
        'schema_version', 'package', 'contract_version', 'status', 'scope', 'source_contracts',
        'entry_and_map_resource_contract', 'authoritative_interaction', 'public_eligibility_evidence',
        'versioned_reward_settlement_request', 'settlement_receipt',
        'failure_retry_and_duplicate_contract', 'acceptance_requirements', 'unresolved_and_out_of_scope'
    ) -Context 'contract root'
    Test-ExactValue -Actual $contract.schema_version -Expected 1 -Context 'schema_version'
    Test-ExactValue -Actual $contract.package -Expected 'huaguoshan-first-six-hours-vertical-slice' -Context 'package'
    Test-ExactValue -Actual $contract.status -Expected 'offline-bridge-validated' -Context 'status'
    Test-ExactValue -Actual $contract.contract_version -Expected 'huaguoshan-tide-trace-first-six-hours-v1' -Context 'contract_version'

    Test-RequiredProperties -Object $contract.scope -Names @(
        'encounter_key', 'encounter_type', 'combat_scope', 'delivery_layer', 'first_six_hours_semantics',
        'actual_y3_map_playable', 'new_y3_object_creation', 'materializer_invocation', 'economic_values_defined'
    ) -Context 'scope'
    Test-ExactValue -Actual $contract.scope.encounter_key -Expected 'HG_E_TIDE_TRACE' -Context 'scope.encounter_key'
    Test-ExactValue -Actual $contract.scope.encounter_type -Expected 'public_trace' -Context 'scope.encounter_type'
    Test-ExactValue -Actual $contract.scope.combat_scope -Expected 'public' -Context 'scope.combat_scope'
    Test-ExactValue -Actual $contract.scope.delivery_layer -Expected 'offline-contract-runtime-and-acceptance' -Context 'scope.delivery_layer'
    Test-Requirement ($contract.scope.actual_y3_map_playable -eq $false) 'Contract must not claim a playable real Y3 map'
    Test-Requirement ($contract.scope.new_y3_object_creation -eq $false) 'Contract must not create new Y3 objects'
    Test-Requirement ($contract.scope.materializer_invocation -eq $false) 'Contract must not invoke the materializer'
    Test-Requirement ($contract.scope.economic_values_defined -eq $false) 'Contract must not define economy values'

    Test-RequiredProperties -Object $contract.source_contracts -Names @(
        'huaguoshan_runtime_contract_id', 'map_binding_status', 'offline_growth_bridge', 'source_files'
    ) -Context 'source_contracts'
    Test-ExactValue -Actual $contract.source_contracts.huaguoshan_runtime_contract_id -Expected 'huaguoshan-96x72-runtime-v1' -Context 'source_contracts.huaguoshan_runtime_contract_id'
    Test-ExactValue -Actual $contract.source_contracts.map_binding_status -Expected 'offline-declared-public-map-contract-complete-instance-map-contract-pending' -Context 'source_contracts.map_binding_status'
    Test-Requirement (@($contract.source_contracts.source_files).Count -ge 4) 'source_contracts.source_files must reference four Huaguoshan source contracts'
    $offlineBridge = $contract.source_contracts.offline_growth_bridge
    Test-RequiredProperties -Object $offlineBridge -Names @(
        'status', 'module', 'test', 'growth_runtime', 'resource_table_version', 'source_profile', 'reward_slot_key',
        'package_status', 'resource_table_status', 'runtime_handoff', 'production_gate'
    ) -Context 'source_contracts.offline_growth_bridge'
    Test-ExactValue -Actual $offlineBridge.status -Expected 'offline-integrated-nonproduction' -Context 'offline_growth_bridge.status'
    Test-ExactValue -Actual $offlineBridge.module -Expected 'lua/vertical_slice_bridge.lua' -Context 'offline_growth_bridge.module'
    Test-ExactValue -Actual $offlineBridge.test -Expected 'tests/test_tide_trace_growth_bridge.lua' -Context 'offline_growth_bridge.test'
    Test-ExactValue -Actual $offlineBridge.growth_runtime -Expected '../../growth/lua/growth_runtime.lua' -Context 'offline_growth_bridge.growth_runtime'
    Test-ExactValue -Actual $offlineBridge.resource_table_version -Expected 'f6h-v1' -Context 'offline_growth_bridge.resource_table_version'
    Test-ExactValue -Actual $offlineBridge.source_profile -Expected 'HG_DROP_WATERFALL_ELITE' -Context 'offline_growth_bridge.source_profile'
    Test-ExactValue -Actual $offlineBridge.reward_slot_key -Expected 'trace_completion' -Context 'offline_growth_bridge.reward_slot_key'
    Test-ExactValue -Actual $offlineBridge.package_status -Expected 'offline_candidate_simulation_not_adopted' -Context 'offline_growth_bridge.package_status'
    Test-ExactValue -Actual $offlineBridge.resource_table_status -Expected 'offline_candidate_not_adopted' -Context 'offline_growth_bridge.resource_table_status'
    Test-Requirement ($offlineBridge.runtime_handoff -eq $false) 'offline_growth_bridge.runtime_handoff must remain false'
    Test-ExactValue -Actual $offlineBridge.production_gate -Expected 'closed' -Context 'offline_growth_bridge.production_gate'

    $entry = $contract.entry_and_map_resource_contract
    Test-RequiredProperties -Object $entry -Names @('entry_identity_fields', 'required_resources', 'existing_spawn_contract', 'binding_invariants') -Context 'entry_and_map_resource_contract'
    Test-ContainsValues -Values $entry.entry_identity_fields -Expected @('encounter_instance_id', 'target_id', 'target_lifecycle_id') -Context 'entry_identity_fields'
    Test-Requirement (@($entry.required_resources).Count -eq 3) 'Tide Trace must declare exactly three map resources'

    $expectedResources = @(
        @{ resource_key = 'spawn_trace_tide_guard'; expected_type = 'point'; role = 'trace_carrier_anchor' },
        @{ resource_key = 'pt_hg_tide_trace_stone'; expected_type = 'point'; role = 'interaction_anchor' },
        @{ resource_key = 'area_hg_tide_trace_interact'; expected_type = 'circleArea'; role = 'interaction_area' }
    )
    foreach ($expected in $expectedResources) {
        $found = @($entry.required_resources | Where-Object {
            $_.resource_key -eq $expected.resource_key -and $_.expected_type -eq $expected.expected_type -and $_.role -eq $expected.role
        })
        Test-Requirement ($found.Count -eq 1) "Contract is missing or misdeclares Tide Trace resource $($expected.resource_key)"
    }
    Test-ExactValue -Actual $entry.existing_spawn_contract.anchor_key -Expected 'spawn_trace_tide_guard' -Context 'existing_spawn_contract.anchor_key'
    Test-ExactValue -Actual $entry.existing_spawn_contract.unit_key -Expected 'HG_U_TIDE_TRACE_GUARD' -Context 'existing_spawn_contract.unit_key'

    $interaction = $contract.authoritative_interaction
    Test-RequiredProperties -Object $interaction -Names @(
        'action_key', 'max_concurrent', 'read_seconds', 'postlude_seconds', 'authority_provider_required',
        'begin_proof_fields', 'completion_proof_fields', 'caller_asserted_authority_fields_rejected', 'completion_invariants'
    ) -Context 'authoritative_interaction'
    Test-ExactValue -Actual $interaction.action_key -Expected 'stabilize_tide_trace' -Context 'authoritative_interaction.action_key'
    Test-ExactValue -Actual $interaction.max_concurrent -Expected 4 -Context 'authoritative_interaction.max_concurrent'
    Test-ExactValue -Actual $interaction.read_seconds -Expected 2 -Context 'authoritative_interaction.read_seconds'
    Test-ExactValue -Actual $interaction.postlude_seconds -Expected 30 -Context 'authoritative_interaction.postlude_seconds'
    Test-Requirement ($interaction.authority_provider_required -eq $true) 'Tide Trace must require a trusted authority provider'
    Test-ContainsValues -Values $interaction.begin_proof_fields -Expected @('actor_alive', 'within_interaction_area', 'target_current', 'observed_tick') -Context 'begin_proof_fields'
    Test-ContainsValues -Values $interaction.completion_proof_fields -Expected @('event_id', 'action_token', 'completed_reading', 'reading_continuous', 'completed_tick') -Context 'completion_proof_fields'
    Test-ContainsValues -Values $interaction.caller_asserted_authority_fields_rejected -Expected @('authority_verified', 'completed_reading', 'reading_continuous', 'completed_tick', 'authority_proof_ref') -Context 'caller_asserted_authority_fields_rejected'

    $evidence = $contract.public_eligibility_evidence
    Test-RequiredProperties -Object $evidence -Names @('contract_id', 'schema_version', 'integration_status', 'producer', 'consumer', 'required_fields', 'fixed_context', 'non_reward_semantics') -Context 'public_eligibility_evidence'
    Test-ExactValue -Actual $evidence.contract_id -Expected 'growth-public-eligibility-evidence-v1' -Context 'public_eligibility_evidence.contract_id'
    Test-ExactValue -Actual $evidence.schema_version -Expected 1 -Context 'public_eligibility_evidence.schema_version'
    Test-ExactValue -Actual $evidence.integration_status -Expected 'offline-integrated-nonproduction' -Context 'public_eligibility_evidence.integration_status'
    Test-Requirement (([string]$evidence.consumer) -match 'implementation/growth') 'Eligibility evidence must target the implementation/growth boundary'
    Test-ContainsValues -Values $evidence.required_fields -Expected @('event_id', 'actor_id', 'lifecycle_id', 'encounter_instance_id', 'action_token', 'authority_proof_ref', 'source_identity_fingerprint') -Context 'public_eligibility_evidence.required_fields'
    Test-ExactValue -Actual $evidence.fixed_context.encounter_key -Expected 'HG_E_TIDE_TRACE' -Context 'public_eligibility_evidence.fixed_context.encounter_key'
    Test-ExactValue -Actual $evidence.fixed_context.combat_scope -Expected 'public' -Context 'public_eligibility_evidence.fixed_context.combat_scope'
    Test-ExactValue -Actual $evidence.fixed_context.completion_command -Expected 'trace_action_completed' -Context 'public_eligibility_evidence.fixed_context.completion_command'
    Test-ExactValue -Actual $evidence.fixed_context.canonical_projection -Expected 'completion command payload is consumed directly after trusted verification' -Context 'public_eligibility_evidence.fixed_context.canonical_projection'
    Test-ExactValue -Actual $evidence.fixed_context.rare_eligibility -Expected 'none' -Context 'public_eligibility_evidence.fixed_context.rare_eligibility'

    $request = $contract.versioned_reward_settlement_request
    Test-RequiredProperties -Object $request -Names @(
        'contract_id', 'schema_version', 'direction', 'implementation_status', 'producer', 'consumer', 'activation_gate',
        'required_fields', 'opaque_versioned_fields', 'prohibited_inline_reward_fields'
    ) -Context 'versioned_reward_settlement_request'
    Test-ExactValue -Actual $request.contract_id -Expected 'growth-reward-settlement-request-v1' -Context 'versioned_reward_settlement_request.contract_id'
    Test-ExactValue -Actual $request.schema_version -Expected 1 -Context 'versioned_reward_settlement_request.schema_version'
    Test-ExactValue -Actual $request.direction -Expected 'implementation/growth offline simulation -> first-six-hours slice settlement boundary' -Context 'versioned_reward_settlement_request.direction'
    Test-ExactValue -Actual $request.implementation_status -Expected 'offline-integrated-nonproduction' -Context 'versioned_reward_settlement_request.implementation_status'
    Test-ContainsValues -Values $request.required_fields -Expected @(
        'settlement_contract_version', 'request_id', 'idempotency_key', 'owner_scope', 'owner_id', 'event_id',
        'encounter_instance_id', 'qualification_snapshot_id', 'source_profile', 'reward_slot_key',
        'resource_table_version', 'eligibility_evidence_ref', 'reward_grant_ref'
    ) -Context 'versioned_reward_settlement_request.required_fields'
    Test-ExactValue -Actual $request.opaque_versioned_fields.owner_id -Expected 'Must exactly equal the authoritative evidence actor_id; a caller cannot redirect a valid trace completion to another character.' -Context 'versioned_reward_settlement_request.owner_binding'
    Test-ContainsValues -Values $request.prohibited_inline_reward_fields -Expected @(
        'xp_amount', 'experience_amount', 'currency_amount', 'material_amount', 'item_quantity',
        'drop_rate', 'drop_probability', 'pity_increment', 'pity_threshold'
    ) -Context 'prohibited_inline_reward_fields'
    Test-Requirement (@($request.activation_gate).Count -ge 4) 'Growth settlement requests must retain explicit activation gates'

    $receipt = $contract.settlement_receipt
    Test-RequiredProperties -Object $receipt -Names @(
        'contract_id', 'schema_version', 'producer', 'consumers', 'implementation_status', 'required_fields',
        'terminal_statuses', 'retryable_status', 'receipt_rules'
    ) -Context 'settlement_receipt'
    Test-ExactValue -Actual $receipt.contract_id -Expected 'growth-reward-settlement-receipt-v1' -Context 'settlement_receipt.contract_id'
    Test-ExactValue -Actual $receipt.schema_version -Expected 1 -Context 'settlement_receipt.schema_version'
    Test-ExactValue -Actual $receipt.implementation_status -Expected 'offline-integrated-nonproduction' -Context 'settlement_receipt.implementation_status'
    Test-ContainsValues -Values $receipt.required_fields -Expected @(
        'receipt_id', 'request_id', 'idempotency_key', 'owner_scope', 'owner_id', 'event_id',
        'qualification_snapshot_id', 'resource_table_version', 'source_profile', 'reward_slot_key',
        'settlement_status', 'settlement_ledger_ref'
    ) -Context 'settlement_receipt.required_fields'
    Test-ContainsValues -Values $receipt.terminal_statuses -Expected @('settled', 'duplicate_replayed', 'terminal_rejection') -Context 'settlement_receipt.terminal_statuses'
    Test-ExactValue -Actual $receipt.retryable_status -Expected 'retryable_failure' -Context 'settlement_receipt.retryable_status'

    $replay = $contract.failure_retry_and_duplicate_contract
    Test-RequiredProperties -Object $replay -Names @(
        'source_event_identity', 'settlement_dedupe_identity', 'same_event_retry', 'same_id_different_fingerprint',
        'retryable_failures', 'terminal_rejections', 'retry_invariants'
    ) -Context 'failure_retry_and_duplicate_contract'
    Test-ContainsValues -Values $replay.source_event_identity -Expected @('event_id', 'actor_id', 'lifecycle_id', 'encounter_instance_id', 'action_token', 'completed_tick') -Context 'source_event_identity'
    Test-ContainsValues -Values $replay.settlement_dedupe_identity -Expected @('owner_scope', 'owner_id', 'event_id', 'source_profile', 'reward_slot_key', 'resource_table_version') -Context 'settlement_dedupe_identity'
    Test-ContainsValues -Values $replay.retryable_failures -Expected @('future_growth_unavailable', 'settlement_transport_timeout', 'receipt_persistence_unconfirmed') -Context 'retryable_failures'
    Test-ContainsValues -Values $replay.terminal_rejections -Expected @('missing_or_untrusted_eligibility_evidence', 'unsupported_settlement_contract_version', 'growth-runtime-not-offline-candidate', 'owner-evidence-actor-mismatch', 'invalid-evidence-completed-tick', 'duplicate_request_identity_conflict') -Context 'terminal_rejections'

    $acceptanceIds = @($contract.acceptance_requirements | ForEach-Object { $_.id })
    Test-ContainsValues -Values $acceptanceIds -Expected @('VS-001', 'VS-002', 'VS-003', 'VS-004', 'VS-005', 'VS-006', 'VS-007', 'VS-008', 'VS-009', 'VS-010') -Context 'acceptance_requirements'
    Test-Requirement (@($contract.unresolved_and_out_of_scope).Count -ge 4) 'Contract must record growth, Y3 map, and first-six-hours unresolved items'

    $forbiddenDefinedRewardFields = [regex]::Matches(
        $contractText,
        '(?m)^\s*"(?:xp_amount|experience_amount|currency_amount|material_amount|item_quantity|drop_rate|drop_probability|pity_increment|pity_threshold)"\s*:'
    )
    Test-Requirement ($forbiddenDefinedRewardFields.Count -eq 0) 'Contract must not inline XP, drop, pity, or reward amount fields'
    $forbiddenY3ObjectFields = [regex]::Matches($contractText, '(?m)^\s*"(?:create_unit|create_ability|create_modifier|create_projectile|y3_object_id)"\s*:')
    Test-Requirement ($forbiddenY3ObjectFields.Count -eq 0) 'Contract must not define new Y3 object fields'

    $huaguoshanRoot = Split-Path -Parent $PSScriptRoot
    $implementationRoot = Split-Path -Parent $huaguoshanRoot
    $mapBindingPath = Join-Path $huaguoshanRoot 'map-logic-binding.json'
    $configPath = Join-Path $huaguoshanRoot 'lua\huaguoshan_config.lua'
    $tracePath = Join-Path $huaguoshanRoot 'lua\huaguoshan_public_trace.lua'
    $traceTestPath = Join-Path $huaguoshanRoot 'tests\test_public_trace.lua'
    $bridgeModulePath = Join-Path $PSScriptRoot $offlineBridge.module
    $bridgeTestPath = Join-Path $PSScriptRoot $offlineBridge.test
    $bridgeBaselinePath = Join-Path $PSScriptRoot 'tests\y3-api-baseline.json'
    $growthRuntimePath = Join-Path $implementationRoot 'growth\lua\growth_runtime.lua'
    $growthConfigPath = Join-Path $implementationRoot 'growth\lua\growth_config.lua'
    foreach ($sourcePath in @($mapBindingPath, $configPath, $tracePath, $traceTestPath)) {
        Test-Requirement (Test-Path -LiteralPath $sourcePath -PathType Leaf) "Referenced Huaguoshan source file is missing: $sourcePath"
    }
    foreach ($sourcePath in @($bridgeModulePath, $bridgeTestPath, $bridgeBaselinePath, $growthRuntimePath, $growthConfigPath)) {
        Test-Requirement (Test-Path -LiteralPath $sourcePath -PathType Leaf) "Offline bridge dependency is missing: $sourcePath"
    }

    if (Test-Path -LiteralPath $mapBindingPath -PathType Leaf) {
        $binding = Get-JsonFile -Path $mapBindingPath
        Test-ExactValue -Actual $binding.runtime_contract_id -Expected $contract.source_contracts.huaguoshan_runtime_contract_id -Context 'existing map-logic-binding.runtime_contract_id'
        Test-ExactValue -Actual $binding.status -Expected $contract.source_contracts.map_binding_status -Context 'existing map-logic-binding.status'
        foreach ($expected in $expectedResources) {
            $bindingMatch = @($binding.encounter_resource_bindings | Where-Object {
                $_.encounter_key -eq 'HG_E_TIDE_TRACE' -and $_.resource_key -eq $expected.resource_key -and $_.expected_type -eq $expected.expected_type -and $_.role -eq $expected.role
            })
            Test-Requirement ($bindingMatch.Count -eq 1) "Existing map contract is missing or drifts Tide Trace resource $($expected.resource_key)"
        }
        $spawnMatch = @($binding.spawn_bindings | Where-Object {
            $_.encounter_key -eq 'HG_E_TIDE_TRACE' -and $_.anchor_key -eq 'spawn_trace_tide_guard' -and $_.unit_key -eq 'HG_U_TIDE_TRACE_GUARD'
        })
        Test-Requirement ($spawnMatch.Count -eq 1) 'Existing map contract is missing the Tide Trace carrier spawn binding'
        $actionMatch = @($binding.encounter_action_bindings | Where-Object {
            $_.encounter_key -eq 'HG_E_TIDE_TRACE' -and $_.action_key -eq $interaction.action_key -and $_.area_key -eq 'area_hg_tide_trace_interact' -and $_.anchor_key -eq 'pt_hg_tide_trace_stone' -and $_.radius_cells -eq 2 -and $_.max_concurrent -eq $interaction.max_concurrent -and $_.read_seconds -eq $interaction.read_seconds -and $_.postlude_seconds -eq $interaction.postlude_seconds
        })
        Test-Requirement ($actionMatch.Count -eq 1) 'Existing map contract is missing or drifts the Tide Trace action binding'
    }

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        Test-Requirement ($configText -match 'HG_E_TIDE_TRACE') 'Existing config is missing HG_E_TIDE_TRACE'
        Test-Requirement ($configText -match 'stabilize_tide_trace') 'Existing config is missing stabilize_tide_trace'
        Test-Requirement ($configText -match 'HG_U_TIDE_TRACE_GUARD') 'Existing config is missing HG_U_TIDE_TRACE_GUARD'
    }

    if (Test-Path -LiteralPath $tracePath -PathType Leaf) {
        $traceText = Get-Content -LiteralPath $tracePath -Raw -Encoding UTF8
        Test-Requirement ($traceText -match 'authority-provider-required') 'Trace state machine no longer rejects a missing authority provider'
        Test-Requirement ($traceText -match 'duplicate-trace-event') 'Trace state machine no longer retains duplicate-event rejection'
        Test-Requirement ($traceText -match 'trace_action_completed') 'Trace state machine no longer emits the completion evidence command'
        Test-Requirement ($traceText -match 'authority_proof_ref') 'Trace state machine no longer requires or emits an authority proof reference'
        Test-Requirement ($traceText -match 'source_identity_fingerprint') 'Trace state machine no longer emits the canonical source identity fingerprint'
    }

    if (Test-Path -LiteralPath $traceTestPath -PathType Leaf) {
        $traceTestText = Get-Content -LiteralPath $traceTestPath -Raw -Encoding UTF8
        Test-Requirement ($traceTestText -match 'trace begin fails closed without a trusted authority provider') 'Existing Tide Trace test lacks the authority-provider negative case'
        Test-Requirement ($traceTestText -match 'caller completed_reading cannot prove a trace read') 'Existing Tide Trace test lacks the forged completion negative case'
        Test-Requirement ($traceTestText -match 'resolved trace rejects replay') 'Existing Tide Trace test lacks the replay-rejection assertion'
    }

    if (Test-Path -LiteralPath $bridgeModulePath -PathType Leaf) {
        $bridgeText = Get-Content -LiteralPath $bridgeModulePath -Raw -Encoding UTF8
        Test-Requirement ($bridgeText -match 'growth-runtime-required') 'Bridge must require an injected growth runtime'
        Test-Requirement ($bridgeText -match 'trace-completion-verifier-required') 'Bridge must require a trusted completion verifier'
        Test-Requirement ($bridgeText -match 'qualification-snapshot-mismatch') 'Bridge must validate the deterministic qualification snapshot'
        Test-Requirement ($bridgeText -match 'duplicate-request-identity-conflict') 'Bridge must reject conflicting idempotency identities'
        Test-Requirement ($bridgeText -match 'inline-reward-field-forbidden') 'Bridge must reject inline reward fields'
        Test-Requirement ($bridgeText -match 'owner-evidence-actor-mismatch') 'Bridge must reject cross-owner settlement requests'
        Test-Requirement ($bridgeText -match 'invalid-evidence-completed-tick') 'Bridge must require a numeric authoritative completion tick'
        Test-Requirement ($bridgeText -match 'growth-runtime-not-offline-candidate') 'Bridge must reject a noncandidate or production growth runtime'
        Test-Requirement ($bridgeText -match 'offline_candidate_simulation_not_adopted') 'Bridge must bind the injected growth runtime to the offline candidate package status'
        Test-Requirement ($bridgeText -match 'resource_table_status') 'Bridge must bind the injected growth runtime to the candidate resource table status'
        Test-Requirement ($bridgeText -match 'settle_reward') 'Bridge must delegate settlement to the injected growth runtime'
    }
    if (Test-Path -LiteralPath $bridgeTestPath -PathType Leaf) {
        $bridgeTestText = Get-Content -LiteralPath $bridgeTestPath -Raw -Encoding UTF8
        Test-Requirement ($bridgeTestText -match 'trace_action_completed') 'Bridge regression must start from the Tide Trace completion command'
        Test-Requirement ($bridgeTestText -match 'copy_table\(completion_evidence\)') 'Bridge regression must consume canonical trace completion evidence instead of reconstructing it'
        Test-Requirement ($bridgeTestText -match 'owner-evidence-actor-mismatch') 'Bridge regression must cover cross-owner settlement rejection'
        Test-Requirement ($bridgeTestText -match 'invalid-evidence-completed-tick') 'Bridge regression must cover malformed completion-tick rejection'
        Test-Requirement ($bridgeTestText -match 'growth-runtime-not-offline-candidate') 'Bridge regression must cover noncandidate runtime rejection'
        Test-Requirement ($bridgeTestText -match 'duplicate-request-identity-conflict') 'Bridge regression must cover conflicting replay identity'
        Test-Requirement ($bridgeTestText -match 'inline-reward-field-forbidden') 'Bridge regression must cover inline reward rejection'
        Test-Requirement ($bridgeTestText -match 'duplicate_replayed') 'Bridge regression must cover idempotent receipt replay'
        Test-Requirement ($bridgeTestText -match 'clear_trace_local_environment') 'Bridge regression must preserve Tide Trace postlude cleanup'
    }
}
catch {
    [void]$script:Errors.Add("Validator exception: $($_.Exception.Message)")
}

if ($script:Errors.Count -gt 0) {
    Write-Output "FAIL: Huaguoshan first-six-hours offline vertical-slice contract failed ($($script:Errors.Count) issues, $($script:CheckCount) checks)."
    foreach ($errorItem in $script:Errors) {
        Write-Output " - $errorItem"
    }
    exit 1
}

Write-Output "PASS: Huaguoshan first-six-hours offline vertical-slice contract passed $($script:CheckCount) checks."
Write-Output 'STATUS: validated offline Tide Trace-to-growth bridge; production gate remains closed and no real Y3 map, object creation, persistence, or live reward values are claimed.'
