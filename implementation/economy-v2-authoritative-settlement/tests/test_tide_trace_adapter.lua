package.path = table.concat({
    'implementation/economy-v2-authoritative-settlement/lua/?.lua',
    'implementation/huaguoshan/tests/?.lua',
    'implementation/huaguoshan/lua/?.lua',
    package.path,
}, ';')

local Adapter = require 'economy_v2_tide_trace_adapter'
local HuaguoshanConfig = require 'huaguoshan_config'
local HuaguoshanRuntime = require 'huaguoshan_runtime'
local FakeAuthority = require 'fake_authority_provider'

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
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
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

local function expect_error(adapter, evidence, expected, message)
    local accepted, error_code = adapter:to_settlement_request(evidence)
    equal(accepted, false, message or 'adapter rejects invalid evidence')
    equal(error_code, expected, 'adapter returns a stable rejection')
end

do
    local missing, missing_error = Adapter.new({})
    equal(missing, nil, 'adapter refuses construction without a canonical trace verifier')
    equal(missing_error, 'trace-completion-verifier-required', 'missing verifier has a stable rejection')
end

local authority = FakeAuthority.new({ now = 0, watermark = 0 })
local runtime = HuaguoshanRuntime.new({
    authority_provider = authority,
    actor_is_current = function(actor_id, lifecycle_id)
        return actor_id == 'trace-actor-a' and lifecycle_id == 7
    end,
})

truthy(runtime:bind_map(resolver, HuaguoshanConfig.layout_contract.id),
    'the real offline map-binding contract accepts its known resources')
truthy(runtime:start_public_trace('HG_E_TIDE_TRACE', {
    instance_id = 'economy-v2-trace-instance-1',
    target_id = 'economy-v2-trace-target-1',
    target_lifecycle_id = 'economy-v2-trace-life-1',
}), 'the real Tide Trace state machine starts through the fixture authority provider')

authority:set_now(10)
local reserved, reservation = runtime:begin_public_trace_action(
    'economy-v2-trace-instance-1', 'trace-actor-a', 7)
truthy(reserved, 'the real state machine reserves a canonical trace action')
equal(reservation.ready_at, 12, 'the real state machine preserves its authoritative two-second reading')

local completion_event = {
    event_id = 'economy-v2-trace-event-1',
    actor_id = 'trace-actor-a',
    lifecycle_id = 7,
    combat_scope = 'public',
    encounter_instance_id = 'economy-v2-trace-instance-1',
    target_id = 'economy-v2-trace-target-1',
    target_lifecycle_id = 'economy-v2-trace-life-1',
    encounter_action_key = 'stabilize_tide_trace',
    action_token = reservation.action_token,
}
authority:set_completion(completion_event.event_id, 12)
local completed, completion = runtime:complete_public_trace_action(completion_event)
truthy(completed, 'the real Tide Trace state machine resolves the action')
equal(completion.commands[1].type, 'trace_action_completed',
    'the fixture receives the canonical command from the real state machine')
local canonical = completion.commands[1]
local trace = runtime:get_public_trace('economy-v2-trace-instance-1')
equal(trace.state, 'resolved', 'the state machine is resolved before the adapter sees evidence')
truthy(trace.seen_event_ids[canonical.event_id], 'the source state machine retained the canonical origin fingerprint')

local verifier_calls = 0
local function trusted_trace_completion_verifier(evidence)
    verifier_calls = verifier_calls + 1
    if type(evidence) ~= 'table' or evidence.event_id ~= canonical.event_id then return false end
    if trace.state ~= 'resolved' or trace.seen_event_ids[evidence.event_id] == nil then return false end
    return true, copy_table(canonical)
end

local adapter, adapter_error = Adapter.new({
    verify_trace_completion = trusted_trace_completion_verifier,
})
truthy(adapter, adapter_error)

local mapped, request = adapter:to_settlement_request(canonical)
truthy(mapped, 'only a canonical command accepted by the state-machine verifier maps downstream')
equal(request.schema_version, 1, 'adapter marks its request schema')
equal(request.source_event_type, 'trace_action_completed', 'adapter preserves the canonical source type')
equal(request.event_type, 'drop_bundle', 'adapter fixes the settlement event type')
equal(request.source_profile, 'HG_DROP_WATERFALL_ELITE', 'adapter fixes the economy-v2 source profile')
equal(request.reward_slot_key, 'base_bundle', 'adapter fixes the economy-v2 reward slot')
equal(request.event_id, canonical.event_id, 'adapter preserves the canonical event identity')
equal(request.actor_id, canonical.actor_id, 'adapter preserves raw actor identity for downstream owner resolution')
equal(request.lifecycle_id, canonical.lifecycle_id, 'adapter preserves raw lifecycle identity for downstream owner resolution')
equal(request.authority_proof_ref, canonical.authority_proof_ref, 'adapter preserves the canonical proof reference')
equal(request.source_identity_fingerprint, canonical.source_identity_fingerprint,
    'adapter preserves the source replay fingerprint')
equal(request.completed_tick, 12, 'adapter preserves the trusted completion tick')
equal(request.owner_id, nil, 'adapter never accepts or manufactures an owner')
equal(request.reward, nil, 'adapter never accepts or manufactures a reward')
equal(request.award_plan, nil, 'adapter never accepts or manufactures an award plan')
equal(verifier_calls, 1, 'adapter checks the canonical source before mapping')

local before_rejected_verifier_calls = verifier_calls
local forged_owner = copy_table(canonical)
forged_owner.owner_id = 'caller-forged-owner'
expect_error(adapter, forged_owner, 'forbidden-evidence-field:owner_id',
    'caller-owned identity is rejected at the adapter boundary')
equal(verifier_calls, before_rejected_verifier_calls, 'forbidden owner data never reaches the verifier')

local forged_reward = copy_table(canonical)
forged_reward.reward = { CUR_GOLD = 999999 }
expect_error(adapter, forged_reward, 'forbidden-evidence-field:reward',
    'caller-provided reward data is rejected at the adapter boundary')

local forged_profile = copy_table(canonical)
forged_profile.source_profile = 'HG_DROP_MACAQUE_PUBLIC'
expect_error(adapter, forged_profile, 'forbidden-evidence-field:source_profile',
    'caller cannot choose a different economy profile')

local forged_slot = copy_table(canonical)
forged_slot.reward_slot_key = 'rare_reward'
expect_error(adapter, forged_slot, 'forbidden-evidence-field:reward_slot_key',
    'caller cannot choose a different reward slot')

local forged_event_type = copy_table(canonical)
forged_event_type.event_type = 'tower_reward'
expect_error(adapter, forged_event_type, 'forbidden-evidence-field:event_type',
    'caller cannot choose another settlement event type')

local nonstring_key = copy_table(canonical)
nonstring_key[true] = 'not-an-evidence-field'
expect_error(adapter, nonstring_key, 'unexpected-evidence-field-key-type',
    'non-string table keys cannot bypass the exact canonical-field allowlist')

local missing_action_token = copy_table(canonical)
missing_action_token.action_token = nil
expect_error(adapter, missing_action_token, 'missing-evidence-field:action_token',
    'a partial trace command is rejected before provenance lookup')

local malformed_tick = copy_table(canonical)
malformed_tick.completed_tick = '12'
expect_error(adapter, malformed_tick, 'invalid-evidence-field:completed_tick',
    'an untrusted string cannot impersonate the authoritative completion tick')

local fractional_lifecycle = copy_table(canonical)
fractional_lifecycle.lifecycle_id = 7.5
expect_error(adapter, fractional_lifecycle, 'invalid-evidence-field:lifecycle_id',
    'a fractional lifecycle id cannot cross the Lua-to-Node boundary')

local oversized_lifecycle = copy_table(canonical)
oversized_lifecycle.lifecycle_id = 9007199254740992
expect_error(adapter, oversized_lifecycle, 'invalid-evidence-field:lifecycle_id',
    'a lifecycle id above the JavaScript safe-integer limit is rejected')

local fractional_tick = copy_table(canonical)
fractional_tick.completed_tick = 12.5
expect_error(adapter, fractional_tick, 'invalid-evidence-field:completed_tick',
    'a fractional completion tick cannot cross the Lua-to-Node boundary')

local oversized_tick = copy_table(canonical)
oversized_tick.completed_tick = 9007199254740992
expect_error(adapter, oversized_tick, 'invalid-evidence-field:completed_tick',
    'a completion tick above the JavaScript safe-integer limit is rejected')

for _, field in ipairs({
    'event_id', 'actor_id', 'encounter_instance_id', 'target_id',
    'target_lifecycle_id', 'action_token', 'authority_proof_ref',
}) do
    local spaced_identifier = copy_table(canonical)
    spaced_identifier[field] = 'caller supplied value'
    expect_error(adapter, spaced_identifier, 'invalid-evidence-field:' .. field,
        field .. ' must use the canonical ASCII identifier grammar')
end

local unicode_actor = copy_table(canonical)
unicode_actor.actor_id = '玩家-1'
expect_error(adapter, unicode_actor, 'invalid-evidence-field:actor_id',
    'a Unicode identifier cannot produce a Node settlement request')

local percent_actor = copy_table(canonical)
percent_actor.actor_id = 'actor%percent'
expect_error(adapter, percent_actor, 'invalid-evidence-field:actor_id',
    'Lua uses the same identifier grammar as the Node boundary and rejects percent')

equal(Adapter.canonical_fields, nil,
    'the adapter does not expose its mutable canonical-field list')
Adapter.canonical_fields = {}

local wrong_scope = copy_table(canonical)
wrong_scope.combat_scope = 'team_instance'
expect_error(adapter, wrong_scope, 'wrong-evidence-field:combat_scope',
    'only the fixed Tide Trace public scope is accepted')

local mismatched_token = copy_table(canonical)
mismatched_token.action_token = 'caller-forged-token'
expect_error(adapter, mismatched_token, 'canonical-evidence-mismatch:action_token',
    'an external module-table mutation cannot weaken canonical evidence comparison')

local metatable_backed = copy_table(canonical)
setmetatable(metatable_backed, {})
expect_error(adapter, metatable_backed, 'evidence-metatable-forbidden',
    'metatable-backed evidence cannot influence the strict allowlist')

local malicious_verifier, malicious_verifier_error = Adapter.new({
    verify_trace_completion = function()
        local altered = copy_table(canonical)
        altered.owner_id = 'verifier-must-not-smuggle-owner'
        return true, altered
    end,
})
truthy(malicious_verifier, malicious_verifier_error)
expect_error(malicious_verifier, canonical, 'invalid-canonical-evidence:forbidden-evidence-field:owner_id',
    'the adapter validates even a verifier-returned canonical command before mapping')

local rejecting_verifier, rejecting_verifier_error = Adapter.new({
    verify_trace_completion = function() return false end,
})
truthy(rejecting_verifier, rejecting_verifier_error)
expect_error(rejecting_verifier, canonical, 'trace-completion-not-authoritative',
    'a command not confirmed by the upstream verifier cannot become a settlement request')

print('PASS: ' .. tests .. ' economy-v2 Tide Trace adapter assertions')
