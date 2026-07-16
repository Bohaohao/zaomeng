package.path = 'implementation/huaguoshan/tests/?.lua;implementation/huaguoshan/lua/?.lua;' .. package.path

local Config = require 'huaguoshan_config'
local Runtime = require 'huaguoshan_runtime'
local Instances = require 'huaguoshan_instances'
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

local current = { a = 1, b = 1 }
local progression_queries = {}
local authority = FakeAuthority.new({ now = 0, watermark = 0 })
local runtime = Runtime.new({
    authority_provider = authority,
    actor_is_current = function(actor_id, lifecycle_id)
        return current[actor_id] == lifecycle_id
    end,
    source_unit_is_current = function(actor_id, lifecycle_id, source_unit_id, source_unit_lifecycle_id)
        return current[actor_id] == lifecycle_id
            and source_unit_id == actor_id .. '-unit'
            and source_unit_lifecycle_id == lifecycle_id
    end,
    skill_validator = function(event)
        return event.skill_key == 'TEST_SKILL'
    end,
    progression_validator = function(query)
        progression_queries[#progression_queries + 1] = query
        return query.actor_id == 'a'
    end,
})

local function resolver(key, source, expected_type)
    return {
        ref = { id = 'ref:' .. key },
        logic_key = key,
        engine_object_id = 'engine:' .. key,
        source = source,
        type = expected_type,
    }
end

truthy(runtime:bind_map(resolver, Config.layout_contract.id), 'runtime binds a fully resolved map contract')

local missing_authority_runtime = Runtime.new({
    actor_is_current = function() return true end,
})
truthy(missing_authority_runtime:bind_map(resolver, Config.layout_contract.id),
    'a runtime without public authority can still bind its offline map contract')
local missing_authority_ok, missing_authority_error = missing_authority_runtime:start_public_boss(
    'HG_E_MACAQUE_KING', {
        boss_instance_id = 'missing-authority-boss',
        target_id = 'missing-authority-unit',
        target_lifecycle_id = 'missing-authority-life',
    })
equal(missing_authority_ok, false, 'public Boss startup requires an authority provider')
equal(missing_authority_error, 'authority-provider-required',
    'public Boss authority-provider gate has a stable error')
missing_authority_ok, missing_authority_error = missing_authority_runtime:start_public_trace(
    'HG_E_TIDE_TRACE', {
        instance_id = 'missing-authority-trace',
        target_id = 'missing-authority-trace-unit',
        target_lifecycle_id = 'missing-authority-trace-life',
    })
equal(missing_authority_ok, false, 'public trace startup requires an authority provider')
equal(missing_authority_error, 'authority-provider-required',
    'public trace authority-provider gate has a stable error')

local function boss_window(boss_instance_id, target_id, target_lifecycle_id)
    return {
        window_id = boss_instance_id .. ':phase-1:clone-end-1:stabilize_wind_eye',
        mechanic_occurrence_id = 'clone-end-1',
        encounter_action_key = 'stabilize_wind_eye',
        combat_scope = 'public',
        boss_instance_id = boss_instance_id,
        phase_id = 'phase-1',
        boss_target_id = target_id,
        boss_target_lifecycle_id = target_lifecycle_id,
        interaction_unit_id = 'wind-eye-1',
        interaction_unit_lifecycle_id = 'wind-eye-life-1',
        open_tick = 0,
        close_tick = 8,
        reading_duration_ticks = 2,
        reservation_retention_ticks = 3,
    }
end

local macaque_options = {
    boss_instance_id = 'macaque-1',
    target_id = 'macaque-unit',
    target_lifecycle_id = 'macaque-life',
    protection_threshold = 1,
}
truthy(runtime:start_public_boss('HG_E_MACAQUE_KING', macaque_options),
    'first instance of a public encounter can start')
local duplicate_ok, duplicate_error = runtime:start_public_boss('HG_E_MACAQUE_KING', {
    boss_instance_id = 'macaque-2', target_id = 'macaque-unit-2', target_lifecycle_id = 'macaque-life-2',
})
equal(duplicate_ok, false, 'one encounter cannot own two simultaneous public Boss instances')
equal(duplicate_error, 'public-boss-encounter-already-active', 'duplicate encounter rejection is explicit')
truthy(runtime:start_public_boss('HG_E_JIAO_KING', {
    boss_instance_id = 'jiao-1', target_id = 'jiao-unit', target_lifecycle_id = 'jiao-life',
}), 'a different public Boss encounter remains independently available')

truthy(runtime:report_public_damage({
    kind = 'final_damage', event_id = 'damage:jiao-runtime:a', actor_id = 'a', lifecycle_id = 1,
    source_unit_id = 'a-unit', source_unit_lifecycle_id = 1, skill_key = 'TEST_SKILL', skill_validated = true,
    combat_scope = 'public', boss_instance_id = 'jiao-1', phase_id = 'phase-1',
    target_id = 'jiao-unit', target_lifecycle_id = 'jiao-life', sync_tick = 0, value = 1,
}), 'runtime records a current public participant before the Jiao water-chain phase')
local jiao_window = {
    window_id = 'jiao-1:phase-1:dive-runtime:drain_tide_eye',
    mechanic_occurrence_id = 'dive-runtime', encounter_action_key = 'drain_tide_eye', combat_scope = 'public',
    boss_instance_id = 'jiao-1', phase_id = 'phase-1',
    boss_target_id = 'jiao-unit', boss_target_lifecycle_id = 'jiao-life',
    interaction_unit_id = 'tide-eye-runtime', interaction_unit_lifecycle_id = 'tide-eye-runtime-life',
    open_tick = 0, close_tick = 8, reading_duration_ticks = 2, reservation_retention_ticks = 3,
}
truthy(runtime:mark_public_phase('jiao-1', {
    kind = 'phase_marker', event_id = 'marker:jiao-runtime:submerge', marker_occurrence_id = 'dive-runtime',
    marker = 'submerge', combat_scope = 'public', boss_instance_id = 'jiao-1', phase_id = 'phase-1',
    boss_target_id = 'jiao-unit', boss_target_lifecycle_id = 'jiao-life', sync_tick = 0, action_window = jiao_window,
}), 'runtime opens the authority-certified Jiao submerge phase')
local chain_ok, chain_result = runtime:apply_public_water_chain('jiao-1')
truthy(chain_ok, 'runtime exposes the water-chain application path after submerge')
local chain_command = nil
for _, command in ipairs(chain_result.commands) do
    if command.type == 'apply_mechanic' and command.target_id == 'a' then chain_command = command end
end
truthy(chain_command, 'runtime water-chain path emits the current participant mechanic command')
equal(chain_command.encounter_key, 'HG_E_JIAO_KING',
    'runtime water-chain mechanic command is live-dispatchable by encounter key')
local resolved_chain_ok, resolved_chain_result = runtime:resolve_water_chain({
    kind = 'mechanic_resolved', event_id = 'water:jiao-runtime:a', actor_id = 'a', lifecycle_id = 1,
    source_unit_id = 'a-unit', source_unit_lifecycle_id = 1, skill_key = 'TEST_SKILL', skill_validated = true,
    combat_scope = 'public', boss_instance_id = 'jiao-1', phase_id = 'phase-1',
    target_id = 'jiao-unit', target_lifecycle_id = 'jiao-life', sync_tick = 1, value = 1,
    mechanic_key = 'HG_BOSS_WATER_CHAIN', mechanic_resolution = 'purge_mechanic',
})
truthy(resolved_chain_ok, 'runtime resolves an applied water chain through the public contribution path')
equal(resolved_chain_result.commands[1].type, 'remove_mechanic',
    'runtime water-chain resolution returns a concrete cleanup command')

local jiao_transition = {
    kind = 'boss_phase_transition', event_id = 'phase:jiao-runtime:1',
    combat_scope = 'public',
    boss_instance_id = 'jiao-1', from_phase = 'phase-1',
    boss_target_id = 'jiao-unit', boss_target_lifecycle_id = 'jiao-life',
    to_phase = 'phase-2',
    next_boss_target_id = 'jiao-unit-2', next_boss_target_lifecycle_id = 'jiao-life-2',
    reason = 'submerge-ended',
}
truthy(runtime:change_public_boss_phase('jiao-1', jiao_transition),
    'runtime forwards a compare-and-swap public Boss phase event')
local wrong_transition, wrong_transition_error = runtime:change_public_boss_phase('jiao-1', {
    boss_instance_id = 'jiao-other',
})
equal(wrong_transition, false, 'runtime rejects a phase event routed to another Boss instance')
equal(wrong_transition_error, 'stale-boss-instance', 'phase routing keeps the Boss identity explicit')

local window = boss_window('macaque-1', 'macaque-unit', 'macaque-life')
truthy(runtime:mark_public_phase('macaque-1', {
    kind = 'phase_marker', event_id = 'macaque-marker-1', marker_occurrence_id = 'clone-end-1',
    marker = 'clone_end', combat_scope = 'public', boss_instance_id = 'macaque-1', phase_id = 'phase-1',
    boss_target_id = 'macaque-unit', boss_target_lifecycle_id = 'macaque-life', sync_tick = 0,
    action_window = window,
}), 'runtime forwards the formal public phase marker')

local reserved_ok, reservation = runtime:begin_public_action('macaque-1', {
    actor_id = 'a', lifecycle_id = 1, window_id = window.window_id,
    encounter_action_key = window.encounter_action_key,
    interaction_unit_id = window.interaction_unit_id,
    interaction_unit_lifecycle_id = window.interaction_unit_lifecycle_id,
})
truthy(reserved_ok, 'runtime forwards the formal public action reservation')
local action_event_id = window.window_id .. ':a'
authority:set_completion(action_event_id, 2)
local action_completed, action_error = runtime:complete_public_actions({ {
    kind = 'encounter_action_success', event_id = action_event_id, actor_id = 'a', lifecycle_id = 1,
    combat_scope = 'public', boss_instance_id = 'macaque-1', phase_id = 'phase-1',
    window_id = window.window_id, mechanic_occurrence_id = window.mechanic_occurrence_id,
    encounter_action_key = window.encounter_action_key,
    interaction_unit_id = window.interaction_unit_id,
    interaction_unit_lifecycle_id = window.interaction_unit_lifecycle_id,
    boss_target_id = 'macaque-unit', boss_target_lifecycle_id = 'macaque-life',
    action_token = reservation.action_token,
} })
truthy(action_completed, action_error or 'runtime queues the authority-certified action completion batch')
authority:set_watermark(2)
local settled_actions = runtime:tick(2)
equal(settled_actions.authority_errors, nil, 'authority watermark settles public actions without a provider error')

truthy(runtime:finalize_public_boss('macaque-1', {
    kind = 'boss_finalization', event_id = 'final:macaque-runtime:1',
    combat_scope = 'public',
    boss_instance_id = 'macaque-1', from_phase = 'phase-1',
    boss_target_id = 'macaque-unit', boss_target_lifecycle_id = 'macaque-life', reason = 'defeated',
}), 'public Boss finalization releases encounter ownership')
truthy(runtime:start_public_boss('HG_E_MACAQUE_KING', {
    boss_instance_id = 'macaque-3', target_id = 'macaque-unit-3', target_lifecycle_id = 'macaque-life-3',
}), 'the same public encounter can restart only after finalization')

truthy(runtime:start_public_trace('HG_E_TIDE_TRACE', {
    instance_id = 'tide-trace-1', target_id = 'trace-unit', target_lifecycle_id = 'trace-life',
}), 'public trace starts from the map-bound contract')
authority:set_now(10)
local trace_reserved, trace_reservation = runtime:begin_public_trace_action(
    'tide-trace-1', 'a', 1
)
truthy(trace_reserved, 'trace action reserves while active')
authority:set_completion('tide-trace-action-a', 12)
truthy(runtime:complete_public_trace_action({
    event_id = 'tide-trace-action-a', actor_id = 'a', lifecycle_id = 1, combat_scope = 'public',
    encounter_instance_id = 'tide-trace-1', target_id = 'trace-unit', target_lifecycle_id = 'trace-life',
    encounter_action_key = 'stabilize_tide_trace', action_token = trace_reservation.action_token,
}), 'trace completion enters resolved postlude')
truthy(runtime:get_public_trace('tide-trace-1') ~= nil, 'resolved trace remains authoritative during its postlude')
authority:set_watermark(41)
runtime:tick(41)
truthy(runtime:get_public_trace('tide-trace-1') ~= nil, 'trace is retained before its postlude expires')
authority:set_watermark(42)
runtime:tick(42)
equal(runtime:get_public_trace('tide-trace-1'), nil, 'trace is removed only after postlude closure')

truthy(runtime:start_public_trace('HG_E_TIDE_TRACE', {
    instance_id = 'tide-trace-cancel', target_id = 'trace-cancel-unit', target_lifecycle_id = 'trace-cancel-life',
}), 'a second public trace can exercise lifecycle cancellation independently')
authority:set_now(50)
local cancelled_trace_ok, cancelled_trace_reservation = runtime:begin_public_trace_action(
    'tide-trace-cancel', 'b', 1)
truthy(cancelled_trace_ok, 'trace action can reserve for an independently current actor')
local trace_invalidation_ok, trace_invalidation = runtime:invalidate_actor('b', 1)
truthy(trace_invalidation_ok, 'runtime reports successful trace lifecycle invalidation')
local trace_cancel_command = nil
for _, command in ipairs(trace_invalidation.commands) do
    if command.type == 'cancel_trace_action_reservation'
        and command.encounter_instance_id == 'tide-trace-cancel' then
        trace_cancel_command = command
    end
end
truthy(trace_cancel_command, 'actor invalidation emits a concrete trace-reservation cancellation command')
equal(trace_cancel_command.actor_id, 'b', 'trace cancellation keeps the actor identity')
equal(trace_cancel_command.lifecycle_id, 1, 'trace cancellation keeps the lifecycle identity')
equal(trace_cancel_command.action_token, cancelled_trace_reservation.action_token,
    'trace cancellation targets the original authority reservation token')

local function copy_table(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function copy_members(source)
    local copy = {}
    for index, member in ipairs(source or {}) do copy[index] = copy_table(member) end
    return copy
end

local function new_instance_authority(members, statuses)
    local authority = {
        members = members,
        statuses = statuses or {},
        rejected = {},
        tick = 0,
    }

    function authority:reject(operation, rejected)
        self.rejected[operation] = rejected ~= false
    end

    function authority:verify(operation, context)
        if self.rejected[operation] then return false end
        self.tick = self.tick + 1
        local proof = copy_table(context)
        proof.operation = operation
        proof.operation_token = operation .. ':' .. tostring(self.tick)
        proof.now = self.tick
        if operation == 'dragon_entry' then
            -- The provider echoes the opening identity and owns the time proof.
        elseif operation == 'dragon_actor_invalidate' then
            proof.reason = context.requested_reason
        elseif operation == 'ox_entry' then
            proof.member_snapshot = copy_members(self.members)
        elseif operation == 'ox_actor_invalidate' then
            proof.member_status = self.statuses[context.actor_id] or 'left'
        elseif operation == 'ox_failure' then
            proof.reason = context.requested_reason
            proof.all_members_dead = context.requested_reason == 'all_members_dead'
        else
            return false
        end
        return true, proof
    end

    return authority
end

local function new_instance_runtime(members, statuses)
    local authority = new_instance_authority(members, statuses)
    local dragon_slots = Instances.new_dragon_slots({
        authority_provider = authority,
        progression_validator = function() return true end,
    })
    local ox_battlefield = Instances.new_ox_battlefield({
        authority_provider = authority,
        member_lifecycle_validator = function() return true end,
    })
    local instance_runtime = Runtime.new({
        authority_provider = authority,
        actor_is_current = function() return true end,
        dragon_slots = dragon_slots,
        ox_battlefield = ox_battlefield,
    })
    return instance_runtime, authority, dragon_slots, ox_battlefield
end

do
    local instance_runtime, authority, dragon_slots = new_instance_runtime({ {
        actor_id = 'dragon', lifecycle_id = 1, team_id = 'team',
    } })
    local opened_ok, opened = dragon_slots:open({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'dragon', lifecycle_id = 1,
        entry_request_id = 'dragon-entry',
    })
    truthy(opened_ok, 'authority opens a Dragon session for lifecycle invalidation coverage: ' .. tostring(opened))
    authority:reject('dragon_actor_invalidate')
    local rejected, rejected_error = instance_runtime:invalidate_actor('dragon', 1)
    equal(rejected, false, 'runtime fails closed when Dragon invalidation lacks authority proof')
    equal(rejected_error, 'authority-proof-rejected:dragon_actor_invalidate',
        'runtime forwards the Dragon authority-proof rejection')
    equal(dragon_slots:get_by_actor('dragon').state, 'active',
        'rejected Dragon invalidation preserves the active session')
    authority:reject('dragon_actor_invalidate', false)
    local invalidated, cleanup = instance_runtime:invalidate_actor('dragon', 1)
    truthy(invalidated, 'runtime accepts a Dragon invalidation with authority proof')
    equal(cleanup.commands[1].type, 'cleanup_dragon_instance',
        'valid Dragon invalidation emits the required cleanup command')
    local authority_tick = authority.tick
    local retired, retirement = instance_runtime:invalidate_actor('dragon', 1)
    equal(retired, true, 'runtime permits actor retirement while Dragon cleanup is pending')
    equal(#retirement.commands, 0,
        'cleanup-pending Dragon retirement does not emit a duplicate cleanup command')
    equal(authority.tick, authority_tick,
        'cleanup-pending Dragon retirement does not request another authority proof')
    equal(dragon_slots:get_by_actor('dragon').state, 'cleanup_pending',
        'actor retirement leaves the existing Dragon cleanup delivery authoritative')
end

do
    local instance_runtime, authority, _, ox_battlefield = new_instance_runtime({ {
        actor_id = 'leave', lifecycle_id = 1, team_id = 'team',
    } })
    local opened_ok, opened = ox_battlefield:open({
        entry_request_id = 'leave-entry', actor_id = 'leave', lifecycle_id = 1,
    })
    truthy(opened_ok, 'authority opens an Ox raid for leave invalidation coverage')
    authority:reject('ox_actor_invalidate')
    local rejected, rejected_error = instance_runtime:invalidate_actor('leave', 1)
    equal(rejected, false, 'runtime fails closed when Ox leave lacks authority proof')
    equal(rejected_error, 'authority-proof-rejected:ox_actor_invalidate',
        'runtime forwards the Ox leave authority-proof rejection')
    equal(ox_battlefield:get_active_session().members[1].status, 'active',
        'rejected Ox leave does not mutate the authoritative member snapshot')
    authority:reject('ox_actor_invalidate', false)
    local left, leave_result = instance_runtime:invalidate_actor('leave', 1)
    truthy(left, 'runtime accepts a team-member leave with authority proof')
    equal(leave_result.commands[1].member_status, 'left',
        'valid authority proof determines the team-member leave status')
    local stale_ok, stale_result = instance_runtime:invalidate_actor('leave', 1)
    truthy(stale_ok, 'an already-invalidated lifecycle is ignored without an instance error')
    equal(#stale_result.commands, 0, 'an old instance lifecycle remains silent after invalidation')
end

do
    local instance_runtime, _, _, ox_battlefield = new_instance_runtime({
        { actor_id = 'death-a', lifecycle_id = 1, team_id = 'team' },
        { actor_id = 'death-b', lifecycle_id = 1, team_id = 'team' },
    }, {
        ['death-a'] = 'dead',
        ['death-b'] = 'dead',
    })
    local opened_ok = ox_battlefield:open({
        entry_request_id = 'death-entry', actor_id = 'death-a', lifecycle_id = 1,
    })
    truthy(opened_ok, 'authority opens an Ox raid for death cleanup coverage')
    truthy(instance_runtime:invalidate_actor('death-a', 1),
        'runtime accepts the first authority-certified team-member death')
    local final_death, wipe = instance_runtime:invalidate_actor('death-b', 1)
    truthy(final_death, 'runtime accepts the final authority-certified team-member death')
    local cleanup_requested = false
    for _, command in ipairs(wipe.commands) do
        if command.type == 'cleanup_ox_raid' and command.reason == 'all_members_dead' then cleanup_requested = true end
    end
    truthy(cleanup_requested, 'valid deaths trigger the required authority-certified Ox cleanup')
end

do
    local instance_runtime, authority, _, ox_battlefield = new_instance_runtime({ {
        actor_id = 'wipe-proof', lifecycle_id = 1, team_id = 'team',
    } }, { ['wipe-proof'] = 'dead' })
    truthy(ox_battlefield:open({
        entry_request_id = 'wipe-proof-entry', actor_id = 'wipe-proof', lifecycle_id = 1,
    }),
        'authority opens an Ox raid for cleanup-proof coverage')
    authority:reject('ox_failure')
    local rejected, rejected_error = instance_runtime:invalidate_actor('wipe-proof', 1)
    equal(rejected, false, 'runtime fails closed when the required Ox wipe cleanup proof is missing')
    equal(rejected_error, 'authority-proof-rejected:ox_failure',
        'runtime forwards the final Ox cleanup authority rejection')
    equal(ox_battlefield:get_active_session().members[1].status, 'active',
        'failed final Ox cleanup leaves the member retryable')
    authority:reject('ox_failure', false)
    local retried, cleanup = instance_runtime:invalidate_actor('wipe-proof', 1)
    truthy(retried, 'runtime retries the final Ox invalidation after a fresh authority proof')
    equal(ox_battlefield:get_active_session().members[1].status, 'dead',
        'runtime retry commits the final Ox member death')
    equal(ox_battlefield:get_active_session().state, 'cleanup_pending',
        'runtime retry commits Ox cleanup with the member death')
    equal(cleanup.commands[1].type, 'mark_raid_member_unavailable',
        'retry commits the member invalidation before cleanup')
    equal(cleanup.commands[2].type, 'cleanup_ox_raid', 'retry emits the required Ox cleanup command')
end

do
    local _, authority, dragon_slots, ox_battlefield = new_instance_runtime({ {
        actor_id = 'dragon-to-ox', lifecycle_id = 1, team_id = 'team',
    } })
    truthy(dragon_slots:open({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'dragon-to-ox', lifecycle_id = 1,
    }), 'Dragon-to-Ox exclusion fixture opens the Dragon session')
    local authority_tick = authority.tick
    local opened, error_code = ox_battlefield:open({
        entry_request_id = 'dragon-to-ox-entry', actor_id = 'dragon-to-ox', lifecycle_id = 1,
    })
    equal(opened, false, 'an active Dragon owner cannot enter the Ox battlefield')
    equal(error_code, 'raid-member-active-in-dragon-instance',
        'Dragon-to-Ox exclusion has a stable error')
    equal(authority.tick, authority_tick,
        'Dragon-to-Ox rejection happens before requesting an entry proof')
    equal(dragon_slots:get_by_actor('dragon-to-ox').state, 'active',
        'Dragon-to-Ox rejection leaves the Dragon session unchanged')
    equal(ox_battlefield:get_active_session(), nil,
        'Dragon-to-Ox rejection does not create an Ox session')
end

do
    local _, authority, dragon_slots, ox_battlefield = new_instance_runtime({ {
        actor_id = 'ox-to-dragon', lifecycle_id = 1, team_id = 'team',
    } })
    truthy(ox_battlefield:open({
        entry_request_id = 'ox-to-dragon-entry', actor_id = 'ox-to-dragon', lifecycle_id = 1,
    }), 'Ox-to-Dragon exclusion fixture opens the Ox session')
    local authority_tick = authority.tick
    local opened, error_code = dragon_slots:open({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'ox-to-dragon', lifecycle_id = 1,
    })
    equal(opened, false, 'an active Ox member cannot enter Dragon Palace')
    equal(error_code, 'actor-active-in-ox-instance', 'Ox-to-Dragon exclusion has a stable error')
    equal(authority.tick, authority_tick,
        'Ox-to-Dragon rejection happens before requesting an entry proof')
    equal(dragon_slots:get_by_actor('ox-to-dragon'), nil,
        'Ox-to-Dragon rejection does not create a Dragon session')
    equal(ox_battlefield:get_active_session().members[1].status, 'active',
        'Ox-to-Dragon rejection leaves the Ox member active')
end

do
    local authority = new_instance_authority({ {
        actor_id = 'overlap', lifecycle_id = 1, team_id = 'team',
    } })
    local dragon_slots = Instances.new_dragon_slots({
        authority_provider = authority,
        progression_validator = function() return true end,
    })
    local ox_battlefield = Instances.new_ox_battlefield({
        authority_provider = authority,
        member_lifecycle_validator = function() return true end,
    })
    truthy(dragon_slots:open({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'overlap', lifecycle_id = 1,
    }), 'broken-invariant fixture opens Dragon before cross-instance wiring')
    truthy(ox_battlefield:open({
        entry_request_id = 'overlap-entry', actor_id = 'overlap', lifecycle_id = 1,
    }), 'broken-invariant fixture opens Ox before cross-instance wiring')
    local instance_runtime = Runtime.new({
        authority_provider = authority,
        actor_is_current = function() return true end,
        dragon_slots = dragon_slots,
        ox_battlefield = ox_battlefield,
    })

    authority:reject('ox_actor_invalidate')
    local invalidated, error_code = instance_runtime:invalidate_actor('overlap', 1)
    equal(invalidated, false, 'cross-instance invalidation fails closed when a later proof is rejected')
    equal(error_code, 'authority-proof-rejected:ox_actor_invalidate',
        'cross-instance invalidation forwards the later authority rejection')
    equal(dragon_slots:get_by_actor('overlap').state, 'active',
        'later Ox rejection does not partially commit Dragon cleanup')
    equal(ox_battlefield:get_active_session().members[1].status, 'active',
        'later Ox rejection leaves the Ox member unchanged')

    authority:reject('ox_actor_invalidate', false)
    local retried, result = instance_runtime:invalidate_actor('overlap', 1)
    truthy(retried, 'a fresh fully authorized cross-instance invalidation commits')
    local saw_dragon_cleanup, saw_ox_invalidation = false, false
    for _, command in ipairs(result.commands) do
        if command.type == 'cleanup_dragon_instance' then saw_dragon_cleanup = true end
        if command.type == 'mark_raid_member_unavailable' then saw_ox_invalidation = true end
    end
    truthy(saw_dragon_cleanup, 'transactional retry retains the Dragon cleanup command')
    truthy(saw_ox_invalidation, 'transactional retry retains the Ox invalidation command')
    equal(dragon_slots:get_by_actor('overlap').state, 'cleanup_pending',
        'fully authorized retry commits Dragon cleanup')
    equal(ox_battlefield:get_active_session().members[1].status, 'left',
        'fully authorized retry commits Ox invalidation')
end

do
    local actor = { actor_id = 'dragon-authority-reentry', lifecycle_id = 1, team_id = 'team' }
    local instance_runtime, authority, dragon_slots, ox_battlefield = new_instance_runtime({ actor })
    local base_verify = authority.verify
    local reenter = true
    local nested_ok, nested
    authority.verify = function(self, operation, context)
        if operation == 'dragon_entry' and reenter then
            reenter = false
            nested_ok, nested = ox_battlefield:open({
                entry_request_id = 'nested-ox-during-dragon-proof',
                actor_id = actor.actor_id,
                lifecycle_id = actor.lifecycle_id,
            })
        end
        return base_verify(self, operation, context)
    end

    local opened, error_code = dragon_slots:open({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = actor.actor_id,
        lifecycle_id = actor.lifecycle_id,
    })
    equal(nested_ok, true, 'Dragon authority callback can complete the nested Ox fixture')
    truthy(nested and nested.session, 'nested Ox fixture returns its committed raid')
    equal(opened, false, 'Dragon entry rejects an Ox occupation committed by its authority callback')
    equal(error_code, 'actor-active-in-ox-instance',
        'Dragon post-authority conflict recheck has a stable error')
    equal(dragon_slots:get_by_actor(actor.actor_id), nil,
        'Dragon authority reentry cannot create a second active instance for the actor')
    truthy(ox_battlefield:get_by_actor(actor.actor_id),
        'the nested Ox instance remains the sole actor occupation')
end

do
    local actor = { actor_id = 'ox-authority-reentry', lifecycle_id = 1, team_id = 'team' }
    local instance_runtime, authority, dragon_slots, ox_battlefield = new_instance_runtime({ actor })
    local base_verify = authority.verify
    local reenter = true
    local nested_ok, nested
    authority.verify = function(self, operation, context)
        if operation == 'ox_entry' and reenter then
            reenter = false
            nested_ok, nested = dragon_slots:open({
                encounter_key = 'HG_E_DRAGON_OLD_TIDE',
                actor_id = actor.actor_id,
                lifecycle_id = actor.lifecycle_id,
            })
        end
        return base_verify(self, operation, context)
    end

    local opened, error_code = ox_battlefield:open({
        entry_request_id = 'outer-ox-with-dragon-reentry',
        actor_id = actor.actor_id,
        lifecycle_id = actor.lifecycle_id,
    })
    equal(nested_ok, true, 'Ox authority callback can complete the nested Dragon fixture')
    truthy(nested and nested.session, 'nested Dragon fixture returns its committed session')
    equal(opened, false, 'Ox entry rejects a Dragon occupation committed by its authority callback')
    equal(error_code, 'raid-member-active-in-dragon-instance',
        'Ox post-authority conflict recheck has a stable error')
    equal(ox_battlefield:get_active_session(), nil,
        'Ox authority reentry cannot create a second active instance for the actor')
    truthy(dragon_slots:get_by_actor(actor.actor_id),
        'the nested Dragon session remains the sole actor occupation')
end

print('PASS: ' .. tests .. ' runtime assertions')
