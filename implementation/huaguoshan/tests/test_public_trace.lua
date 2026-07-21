package.path = 'implementation/huaguoshan/lua/?.lua;implementation/huaguoshan/tests/?.lua;' .. package.path

local PublicTrace = require 'huaguoshan_public_trace'
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

local encounter = {
    encounter_type = 'public_trace',
    action = { key = 'stabilize_tide_trace', max_concurrent = 4, read_seconds = 2 },
}
local current = { a = 1, b = 1, c = 1, d = 1, e = 1, f = 1, g = 1, h = 1, invalid = 1 }
local function actor_is_current(actor_id, lifecycle_id)
    return current[actor_id] == lifecycle_id
end

local function new_trace(instance_id, authority_provider)
    return PublicTrace.new('HG_E_TIDE_TRACE', encounter, {
        instance_id = instance_id,
        target_id = 'trace-carrier',
        target_lifecycle_id = 'trace-life',
        postlude_seconds = 30,
        authority_provider = authority_provider,
    })
end

local function event(trace, reservations, actor_id, event_id, overrides)
    local value = {
        event_id = event_id,
        actor_id = actor_id,
        lifecycle_id = current[actor_id],
        combat_scope = 'public',
        encounter_instance_id = trace.instance_id,
        target_id = trace.target_id,
        target_lifecycle_id = trace.target_lifecycle_id,
        encounter_action_key = 'stabilize_tide_trace',
        action_token = reservations[actor_id].action_token,
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
end

do
    local trace = new_trace('trace-no-provider')
    local ok, error_code = trace:begin_action('a', 1, actor_is_current)
    equal(ok, false, 'trace begin fails closed without a trusted authority provider')
    equal(error_code, 'authority-provider-required', 'missing trace authority is explicit')
end

do
    local authority = FakeAuthority.new({ now = 0 })
    local trace = new_trace('trace-timing', authority)
    local ok, reservation = trace:begin_action('a', 1, actor_is_current)
    truthy(ok, 'trusted trace authority reserves the configured read duration')
    equal(reservation.ready_at, 2, 'reservation reports Config read_seconds as ready time')
    equal(reservation.expires_at, 2, 'reservation expires when its configured read duration ends')
    equal(trace.active_actions.a.ready_at, 2, 'trace stores its authoritative ready time')
    equal(trace.active_actions.a.expires_at, 2, 'trace stores its authoritative expiry time')

    local forged, forged_error = trace:complete_action(
        event(trace, { a = reservation }, 'a', 'trace:forged', { completed_reading = true }), actor_is_current)
    equal(forged, false, 'caller completed_reading cannot prove a trace read')
    equal(forged_error, 'untrusted-authority-field:completed_reading',
        'forged trace read proof is rejected explicitly')

    local forged_proof_ref, forged_proof_ref_error = trace:complete_action(
        event(trace, { a = reservation }, 'a', 'trace:forged-proof-ref', {
            authority_proof_ref = 'caller-controlled-proof-ref',
        }), actor_is_current)
    equal(forged_proof_ref, false, 'caller authority proof references cannot complete a trace')
    equal(forged_proof_ref_error, 'untrusted-authority-field:authority_proof_ref',
        'caller authority proof references are rejected explicitly')

    authority:set_completion('trace:no-proof-reference', 2)
    authority:set_proof_override('public_trace_action_complete', 'authority_proof_ref', false)
    local no_proof_ref, no_proof_ref_error = trace:complete_action(
        event(trace, { a = reservation }, 'a', 'trace:no-proof-reference'), actor_is_current)
    equal(no_proof_ref, false, 'trace completion requires a trusted proof reference')
    equal(no_proof_ref_error, 'trusted-trace-proof-reference-required',
        'a missing or invalid trusted proof reference is explicit')
    authority:set_proof_override('public_trace_action_complete', 'authority_proof_ref',
        'fixture:public_trace_action_complete:trace-ready')

    authority:set_completion('trace:early', 1)
    local early, early_error = trace:complete_action(
        event(trace, { a = reservation }, 'a', 'trace:early'), actor_is_current)
    equal(early, false, 'trusted completion before the configured duration is rejected')
    equal(early_error, 'trace-reading-incomplete', 'early trace completion is explicit')

    authority:set_completion('trace:ready', 2)
    authority:set_proof_override('public_trace_action_complete', 'completed_reading', false)
    local unproven, unproven_error = trace:complete_action(
        event(trace, { a = reservation }, 'a', 'trace:ready'), actor_is_current)
    equal(unproven, false, 'trace completion requires trusted read proof')
    equal(unproven_error, 'trace-action-not-authoritatively-complete',
        'trusted negative read proof blocks completion')
    authority:set_proof_override('public_trace_action_complete', 'completed_reading', true)
    local complete_ok = trace:complete_action(
        event(trace, { a = reservation }, 'a', 'trace:ready'), actor_is_current)
    truthy(complete_ok, 'trusted positive read proof accepts completion at ready time')
end

do
    local authority = FakeAuthority.new({ now = 0 })
    local trace = new_trace('trace-expiry', authority)
    local reservations = {}
    for _, actor_id in ipairs({ 'a', 'b', 'c', 'd' }) do
        local ok, reservation = trace:begin_action(actor_id, 1, actor_is_current)
        truthy(ok, 'active trace accepts each of four concurrent reservations')
        reservations[actor_id] = reservation
    end
    local full, full_error = trace:begin_action('e', 1, actor_is_current)
    equal(full, false, 'four missing callbacks consume the concurrency cap before expiry')
    equal(full_error, 'trace-action-concurrency-full', 'trace concurrency rejection is explicit')

    authority:set_completion('trace:expired', 3)
    local expired, expired_error = trace:complete_action(
        event(trace, reservations, 'a', 'trace:expired'), actor_is_current)
    equal(expired, false, 'an expired trace read cannot complete')
    equal(expired_error, 'trace-reading-expired', 'expired trace completion is explicit')

    authority:set_watermark(3)
    local expired_actions = trace:tick(3)
    equal(#expired_actions.commands, 4, 'active trace tick cancels every expired reservation')
    equal(expired_actions.commands[1].type, 'cancel_trace_action_reservation', 'expiry emits cancellation commands')
    equal(expired_actions.commands[1].reason, 'reading_expired', 'expiry cancellation records its reason')
    equal(expired_actions.commands[1].action_token, reservations.a.action_token,
        'expiry cancellation carries the expired reservation token')
    equal(next(trace.active_actions), nil, 'expired reservations release all trace concurrency')
    authority:set_now(3)
    truthy(trace:begin_action('e', 1, actor_is_current),
        'released trace concurrency admits a new reservation')
end

do
    local authority = FakeAuthority.new({ now = 0 })
    local trace = new_trace('trace-invalidate', authority)
    local ok, reservation = trace:begin_action('h', 1, actor_is_current)
    truthy(ok, 'trace reservation exists before lifecycle invalidation')
    local invalidated = trace:invalidate_actor('h', 1)
    equal(#invalidated.commands, 1, 'lifecycle invalidation emits one reservation cancellation')
    equal(invalidated.commands[1].type, 'cancel_trace_action_reservation',
        'trace invalidation exposes an explicit cancellation command')
    equal(invalidated.commands[1].action_token, reservation.action_token,
        'trace invalidation carries the cancelled reservation token')
    equal(invalidated.commands[1].reason, 'lifecycle_invalid',
        'trace invalidation records the lifecycle reason')
    equal(trace.active_actions.h, nil, 'trace invalidation releases the reservation')
end

local authority = FakeAuthority.new({ now = 0 })
local trace = new_trace('trace-1', authority)
local reservations = {}
for _, actor_id in ipairs({ 'a', 'b' }) do
    local ok, reservation = trace:begin_action(actor_id, 1, actor_is_current)
    truthy(ok, 'active trace accepts concurrent reservations')
    reservations[actor_id] = reservation
end

do
    local stale, stale_error = trace:begin_action('c', 99, actor_is_current)
    equal(stale, false, 'old lifecycle cannot reserve a trace action')
    equal(stale_error, 'stale-actor-lifecycle', 'trace lifecycle rejection is explicit')
end

do
    authority:set_completion('trace:a', 2)
    local completion_event = event(trace, reservations, 'a', 'trace:a')
    local ok, completion = trace:complete_action(completion_event, actor_is_current)
    truthy(ok, 'the first trusted completed trace action resolves the encounter')
    equal(trace.state, 'resolved', 'trace enters resolved postlude after its first success')
    equal(completion.commands[1].type, 'trace_action_completed', 'resolution records personal progress once')
    local evidence = completion.commands[1]
    equal(evidence.event_id, completion_event.event_id, 'completion evidence retains the authoritative event identity')
    equal(evidence.actor_id, completion_event.actor_id, 'completion evidence retains the actor identity')
    equal(evidence.lifecycle_id, completion_event.lifecycle_id, 'completion evidence retains the actor lifecycle')
    equal(evidence.encounter_key, 'HG_E_TIDE_TRACE', 'completion evidence identifies the Tide Trace encounter')
    equal(evidence.encounter_instance_id, completion_event.encounter_instance_id,
        'completion evidence retains the encounter instance')
    equal(evidence.target_id, completion_event.target_id, 'completion evidence retains the target identity')
    equal(evidence.target_lifecycle_id, completion_event.target_lifecycle_id,
        'completion evidence retains the target lifecycle')
    equal(evidence.encounter_action_key, completion_event.encounter_action_key,
        'completion evidence retains the encounter action')
    equal(evidence.action_token, completion_event.action_token,
        'completion evidence retains the trusted reservation token')
    equal(evidence.combat_scope, completion_event.combat_scope,
        'completion evidence retains the public combat scope')
    equal(evidence.completed_tick, 2, 'completion evidence retains the authoritative completion tick')
    equal(evidence.authority_proof_ref, 'fixture:public_trace_action_complete:trace:a',
        'completion evidence carries the trusted authority proof reference')
    equal(evidence.source_identity_fingerprint, trace.seen_event_ids[completion_event.event_id],
        'completion evidence carries the stable source identity fingerprint')
    equal(completion.commands[2].type, 'set_trace_local_environment', 'resolution starts the local environment')
    equal(trace.postlude_until, 32, 'postlude retains the environment for the configured duration')
    equal(next(trace.active_actions), nil, 'resolution cancels every remaining action reservation')

    local begin_again, begin_error = trace:begin_action('c', 1, actor_is_current)
    equal(begin_again, false, 'resolved trace cannot begin another action')
    equal(begin_error, 'trace-already-resolved', 'post-resolution begin rejection is explicit')

    local complete_again, complete_error = trace:complete_action(
        event(trace, reservations, 'b', 'trace:b'), actor_is_current)
    equal(complete_again, false, 'resolved trace cannot complete a previously reserved second action')
    equal(complete_error, 'trace-already-resolved', 'post-resolution completion rejection is explicit')

    local replay, replay_error = trace:complete_action(
        event(trace, reservations, 'a', 'trace:a'), actor_is_current)
    equal(replay, false, 'resolved trace rejects replay before any second behavior can run')
    equal(replay_error, 'trace-already-resolved', 'resolved state owns the replay rejection')
end

do
    local finish_result = trace:finish('carrier_dead', 5)
    truthy(finish_result, 'finish is idempotent while a resolved trace is in postlude')
    equal(trace.state, 'resolved', 'finish does not close a trace before postlude expiry')
    equal(#finish_result.commands, 0, 'finish never clears the environment during postlude')

    authority:set_watermark(31)
    equal(#trace:tick(31).commands, 0, 'environment remains active before postlude expiry')
    truthy(trace.environment_until ~= nil, 'environment state is retained throughout postlude')
    authority:set_watermark(32)
    local closed = trace:tick(32)
    equal(closed.commands[1].type, 'clear_trace_local_environment',
        'environment clears exactly when postlude ends')
    equal(trace.state, 'closed', 'trace closes only after postlude cleanup')
    equal(trace.environment_until, nil, 'closed trace no longer owns environment state')

    local closed_begin, closed_error = trace:begin_action('c', 1, actor_is_current)
    equal(closed_begin, false, 'closed trace cannot begin actions')
    equal(closed_error, 'trace-already-closed', 'closed trace rejection is distinct from resolved postlude')
end

print('PASS: ' .. tests .. ' public trace assertions')
