package.path = table.concat({
    'implementation/huaguoshan/tests/?.lua',
    'implementation/huaguoshan/lua/?.lua',
    'implementation/growth/lua/?.lua',
    'implementation/huaguoshan/first-six-hours-vertical-slice/lua/?.lua',
    package.path,
}, ';')

local HuaguoshanConfig = require 'huaguoshan_config'
local HuaguoshanRuntime = require 'huaguoshan_runtime'
local FakeAuthority = require 'fake_authority_provider'
local Growth = require 'growth_runtime'
local Bridge = require 'vertical_slice_bridge'

local tests = 0

local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then
        error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    end
end

local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local function copy_table(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function resolver(key, source, expected_type)
    return {
        ref = { id = 'ref:' .. key },
        logic_key = key,
        engine_object_id = 'engine:' .. key,
        source = source,
        type = expected_type,
    }
end

do
    local missing, missing_error = Bridge.new({})
    equal(missing, nil, 'bridge refuses construction without a trusted completion verifier')
    equal(missing_error, 'trace-completion-verifier-required', 'missing verifier has a stable rejection')

    local no_growth, no_growth_error = Bridge.new({
        verify_trace_completion = function() return true, {} end,
    })
    equal(no_growth, nil, 'bridge refuses construction without the injected growth runtime')
    equal(no_growth_error, 'growth-runtime-required', 'missing growth runtime has a stable rejection')
end

local authority = FakeAuthority.new({ now = 0, watermark = 0 })
local runtime = HuaguoshanRuntime.new({
    authority_provider = authority,
    actor_is_current = function(actor_id, lifecycle_id)
        return actor_id == 'a' and lifecycle_id == 1
    end,
})

truthy(runtime:bind_map(resolver, HuaguoshanConfig.layout_contract.id),
    'the Tide Trace uses the existing offline map binding contract')
truthy(runtime:start_public_trace('HG_E_TIDE_TRACE', {
    instance_id = 'slice-trace-1',
    target_id = 'slice-trace-unit',
    target_lifecycle_id = 'slice-trace-life',
}), 'the existing Tide Trace state machine starts through a trusted authority provider')

authority:set_now(10)
local reserved, reservation = runtime:begin_public_trace_action('slice-trace-1', 'a', 1)
truthy(reserved, 'the player obtains a trusted Tide Trace action reservation')
equal(reservation.ready_at, 12, 'the bridge fixture honors the existing two-second authoritative read')

local completion_event = {
    event_id = 'slice-trace-event-1',
    actor_id = 'a',
    lifecycle_id = 1,
    combat_scope = 'public',
    encounter_instance_id = 'slice-trace-1',
    target_id = 'slice-trace-unit',
    target_lifecycle_id = 'slice-trace-life',
    encounter_action_key = 'stabilize_tide_trace',
    action_token = reservation.action_token,
}
authority:set_completion(completion_event.event_id, 12)
local completed, completion = runtime:complete_public_trace_action(completion_event)
truthy(completed, 'a trusted Tide Trace completion resolves the existing encounter')
local trace = runtime:get_public_trace('slice-trace-1')
equal(trace.state, 'resolved', 'the existing encounter records its resolved postlude state')
equal(completion.commands[1].type, 'trace_action_completed', 'the existing encounter emits completion evidence before settlement')
truthy(trace.seen_event_ids[completion_event.event_id], 'the existing encounter retains a stable source fingerprint')
local completion_evidence = completion.commands[1]
equal(completion_evidence.event_id, completion_event.event_id,
    'the bridge consumes the canonical event identity emitted by the real trace command')
equal(completion_evidence.actor_id, completion_event.actor_id,
    'the bridge consumes the canonical actor identity emitted by the real trace command')
equal(completion_evidence.completed_tick, 12,
    'the bridge consumes the authoritative completion tick emitted by the real trace command')
truthy(completion_evidence.authority_proof_ref,
    'the bridge consumes the authoritative proof reference emitted by the real trace command')
equal(completion_evidence.source_identity_fingerprint, trace.seen_event_ids[completion_event.event_id],
    'the bridge consumes the canonical source fingerprint emitted by the real trace command')

local growth_state = Growth.new_state('a')
truthy(growth_state, 'the growth runtime creates an owner-scoped ledger state')
equal(growth_state.total_xp, 0, 'the Tide Trace settlement never fabricates an XP receipt')

local candidate_boundary_violations = {
    { field = 'package_status', value = 'production_adopted' },
    { field = 'production_gate', value = 'open' },
    { field = 'runtime_handoff', value = true },
    { field = 'resource_table_status', value = 'production_adopted' },
}
for _, violation in ipairs(candidate_boundary_violations) do
    local invalid_candidate_runtime = copy_table(Growth)
    invalid_candidate_runtime.Config = copy_table(Growth.Config)
    invalid_candidate_runtime.Config[violation.field] = violation.value
    local invalid_candidate_bridge, invalid_candidate_error = Bridge.new({
        verify_trace_completion = function() return true, {} end,
        growth_runtime = invalid_candidate_runtime,
    })
    equal(invalid_candidate_bridge, nil, 'the bridge refuses a growth runtime outside the offline candidate boundary')
    equal(invalid_candidate_error, 'growth-runtime-not-offline-candidate',
        'each offline candidate boundary field has a stable construction rejection')
end
equal(next(growth_state.resources), nil, 'a rejected noncandidate runtime cannot mutate the character balance')
equal(next(growth_state.reward_receipts), nil, 'a rejected noncandidate runtime cannot create a receipt')

local function trusted_completion_verifier(event)
    if type(event) ~= 'table' or event.event_id ~= completion_event.event_id then
        return false, 'unknown-trace-completion'
    end
    if trace.state ~= 'resolved' or trace.seen_event_ids[event.event_id] == nil then
        return false, 'trace-completion-not-authoritative'
    end
    return true, copy_table(completion_evidence)
end

local bridge, bridge_error = Bridge.new({
    verify_trace_completion = trusted_completion_verifier,
    growth_runtime = Growth,
})
truthy(bridge, bridge_error)

local evidence_ok, evidence = trusted_completion_verifier(completion_event)
truthy(evidence_ok, 'the verifier returns the canonical completion command from the resolved trace')
local request = {
    schema_version = 1,
    settlement_contract_version = Bridge.SETTLEMENT_CONTRACT_VERSION,
    request_id = 'slice-settlement-request-1',
    idempotency_key = 'slice-settlement-idempotency-1',
    owner_scope = Growth.Config.owner_scope,
    owner_id = 'a',
    event_id = completion_event.event_id,
    encounter_instance_id = completion_event.encounter_instance_id,
    resource_table_version = Growth.Config.resource_table_version,
    source_profile = Bridge.TRACE_PROFILE,
    reward_slot_key = Bridge.TRACE_REWARD_SLOT,
    eligibility_evidence_contract_id = Bridge.EVIDENCE_CONTRACT_ID,
    eligibility_evidence_schema_version = 1,
    eligibility_evidence_ref = evidence.source_identity_fingerprint,
    reward_grant_ref = 'f6h-hg-tide-trace-v1',
    completion_event = completion_event,
}
request.qualification_snapshot_id = Bridge.qualification_snapshot_id(request.owner_id, evidence.source_identity_fingerprint)
truthy(request.qualification_snapshot_id, 'the qualification snapshot identity is deterministic before settlement')

local drift_runtime = copy_table(Growth)
drift_runtime.Config = copy_table(Growth.Config)
local drift_bridge, drift_bridge_error = Bridge.new({
    verify_trace_completion = trusted_completion_verifier,
    growth_runtime = drift_runtime,
})
truthy(drift_bridge, drift_bridge_error)
drift_runtime.Config.production_gate = 'open'
local drift_state, drift_state_error = Growth.new_state('a')
truthy(drift_state, drift_state_error)
local drift_request = copy_table(request)
drift_request.request_id = 'slice-settlement-request-runtime-drift'
drift_request.idempotency_key = 'slice-settlement-idempotency-runtime-drift'
local drift_ok, drift_error = drift_bridge:settle_trace_completion(drift_state, drift_request)
equal(drift_ok, false, 'the bridge rechecks an injected runtime if it drifts out of the candidate boundary')
equal(drift_error, 'growth-runtime-not-offline-candidate', 'runtime drift has a stable settlement rejection')
equal(next(drift_state.resources), nil, 'runtime drift cannot mutate the character balance')
equal(next(drift_state.reward_receipts), nil, 'runtime drift cannot create a receipt')

local foreign_state, foreign_state_error = Growth.new_state('b')
truthy(foreign_state, foreign_state_error)
local foreign_owner_request = copy_table(request)
foreign_owner_request.request_id = 'slice-settlement-request-foreign-owner'
foreign_owner_request.idempotency_key = 'slice-settlement-idempotency-foreign-owner'
foreign_owner_request.owner_id = 'b'
foreign_owner_request.qualification_snapshot_id = Bridge.qualification_snapshot_id(
    foreign_owner_request.owner_id, evidence.source_identity_fingerprint)
local foreign_owner_ok, foreign_owner_error = bridge:settle_trace_completion(foreign_state, foreign_owner_request)
equal(foreign_owner_ok, false, 'a trace completion for actor a cannot settle rewards to actor b')
equal(foreign_owner_error, 'owner-evidence-actor-mismatch', 'cross-owner settlement has a stable rejection')
equal(next(foreign_state.resources), nil, 'a rejected cross-owner settlement cannot mutate the foreign balance')
equal(next(foreign_state.reward_receipts), nil, 'a rejected cross-owner settlement cannot create a foreign receipt')

local settled, receipt, replayed = bridge:settle_trace_completion(growth_state, request)
truthy(settled, receipt)
equal(receipt.settlement_status, 'settled', 'the first trusted request produces one settlement receipt')
equal(receipt.settlement_contract_version, Bridge.SETTLEMENT_CONTRACT_VERSION,
    'the receipt preserves the versioned settlement contract')
equal(receipt.eligibility_evidence_contract_id, Bridge.EVIDENCE_CONTRACT_ID,
    'the receipt preserves the evidence contract identity')
equal(receipt.awards, nil, 'the bridge returns a receipt reference instead of exposing inline rewards')
truthy(receipt.settlement_ledger_ref, 'the receipt points to the growth settlement ledger')
truthy(next(growth_state.resources) ~= nil, 'the injected growth runtime applies the configured profile bundle')
equal(growth_state.total_xp, 0, 'reward settlement leaves XP separate from the Tide Trace receipt')
equal(replayed, false, 'the first settlement is not classified as a replay')

local resources_after_first = copy_table(growth_state.resources)
local replay_ok, replay_receipt, replayed_again = bridge:settle_trace_completion(growth_state, request)
truthy(replay_ok, 'the same idempotency identity replays its original receipt')
equal(replay_receipt.settlement_status, 'duplicate_replayed', 'the bridge labels an idempotent replay explicitly')
equal(replay_receipt.settlement_ledger_ref, receipt.settlement_ledger_ref, 'a replay preserves the original ledger reference')
equal(replayed_again, true, 'the bridge exposes replay status to its caller')
equal(growth_state.resources.CUR_GOLD, resources_after_first.CUR_GOLD, 'a replay cannot mutate the character balance')

local collision = copy_table(request)
collision.request_id = 'slice-settlement-request-2'
collision.idempotency_key = 'slice-settlement-idempotency-2'
local collision_ok, collision_error = bridge:settle_trace_completion(growth_state, collision)
equal(collision_ok, false, 'the same trace evidence cannot be submitted under a new idempotency identity')
equal(collision_error, 'duplicate-request-identity-conflict', 'source-identity collision has a terminal rejection')
equal(growth_state.resources.CUR_GOLD, resources_after_first.CUR_GOLD, 'a conflicting replay cannot mutate the character balance')

local inline_reward = copy_table(request)
inline_reward.request_id = 'slice-settlement-request-3'
inline_reward.idempotency_key = 'slice-settlement-idempotency-3'
inline_reward.xp_amount = 1
local inline_ok, inline_error = bridge:settle_trace_completion(growth_state, inline_reward)
equal(inline_ok, false, 'the bridge rejects caller-provided reward amounts')
equal(inline_error, 'inline-reward-field-forbidden:xp_amount', 'inline reward rejection names the prohibited field')
equal(growth_state.resources.CUR_GOLD, resources_after_first.CUR_GOLD, 'a prohibited inline amount cannot mutate the character balance')

local unavailable_version = copy_table(request)
unavailable_version.request_id = 'slice-settlement-request-4'
unavailable_version.idempotency_key = 'slice-settlement-idempotency-4'
unavailable_version.resource_table_version = 'unknown-version'
local unavailable_ok, unavailable_error = bridge:settle_trace_completion(growth_state, unavailable_version)
equal(unavailable_ok, false, 'the bridge refuses a resource table that is unavailable in the offline candidate simulation')
equal(unavailable_error, 'resource-table-version-unavailable', 'unsupported resource table version has a stable rejection')
equal(growth_state.resources.CUR_GOLD, resources_after_first.CUR_GOLD, 'an unavailable table cannot mutate the character balance')

local forged_bridge, forged_bridge_error = Bridge.new({
    verify_trace_completion = function(event)
        local accepted, forged_evidence = trusted_completion_verifier(event)
        if not accepted then return false, forged_evidence end
        forged_evidence.action_token = 'forged-token'
        return true, forged_evidence
    end,
    growth_runtime = Growth,
})
truthy(forged_bridge, forged_bridge_error)
local forged_request = copy_table(request)
forged_request.request_id = 'slice-settlement-request-5'
forged_request.idempotency_key = 'slice-settlement-idempotency-5'
local forged_ok, forged_error = forged_bridge:settle_trace_completion(growth_state, forged_request)
equal(forged_ok, false, 'a verifier cannot substitute an action token after trace completion')
equal(forged_error, 'evidence-event-mismatch:action_token', 'the bridge rejects mismatched trusted evidence explicitly')
equal(growth_state.resources.CUR_GOLD, resources_after_first.CUR_GOLD, 'forged evidence cannot mutate the character balance')

local malformed_bridge, malformed_bridge_error = Bridge.new({
    verify_trace_completion = function(event)
        local accepted, malformed_evidence = trusted_completion_verifier(event)
        if not accepted then return false, malformed_evidence end
        malformed_evidence.completed_tick = '12'
        return true, malformed_evidence
    end,
    growth_runtime = Growth,
})
truthy(malformed_bridge, malformed_bridge_error)
local malformed_request = copy_table(request)
malformed_request.request_id = 'slice-settlement-request-6'
malformed_request.idempotency_key = 'slice-settlement-idempotency-6'
local malformed_ok, malformed_error = malformed_bridge:settle_trace_completion(growth_state, malformed_request)
equal(malformed_ok, false, 'a completion evidence tick must be an authoritative number')
equal(malformed_error, 'invalid-evidence-completed-tick', 'malformed completion tick has a stable rejection')
equal(growth_state.resources.CUR_GOLD, resources_after_first.CUR_GOLD, 'malformed evidence cannot mutate the character balance')

authority:set_watermark(42)
local cleanup = runtime:tick(42)
truthy(#cleanup.commands == 2, 'the completed trace runs its normal postlude cleanup after settlement')
equal(cleanup.commands[1].type, 'clear_trace_local_environment', 'postlude cleanup clears only the existing trace environment')
equal(cleanup.commands[2].type, 'close_public_trace', 'postlude cleanup closes the existing trace lifecycle')
equal(trace.state, 'closed', 'the original Tide Trace transitions to closed after postlude cleanup')
equal(runtime:get_public_trace('slice-trace-1'), nil, 'the runtime releases a closed trace instance')
truthy(growth_state.reward_receipts[receipt.receipt_id], 'the completed settlement receipt survives encounter cleanup')
equal(growth_state.resources.CUR_GOLD, resources_after_first.CUR_GOLD,
    'encounter cleanup cannot rewrite an already-settled reward receipt')

print('PASS: ' .. tests .. ' tide trace growth bridge assertions')
