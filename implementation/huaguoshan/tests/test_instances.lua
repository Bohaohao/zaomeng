package.path = 'implementation/huaguoshan/lua/?.lua;' .. package.path

local Instances = require 'huaguoshan_instances'

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
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function copy_members(source)
    local copy = {}
    for index, member in ipairs(source or {}) do copy[index] = copy_table(member) end
    return copy
end

local function table_size(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end

local function members()
    return {
        { actor_id = 'a', lifecycle_id = 1, team_id = 'team' },
        { actor_id = 'b', lifecycle_id = 2, team_id = 'team' },
        { actor_id = 'c', lifecycle_id = 3, team_id = 'team' },
        { actor_id = 'd', lifecycle_id = 4, team_id = 'team' },
    }
end

local function new_authority(options)
    options = options or {}
    local provider = {
        now = options.now or 0,
        member_snapshot = copy_members(options.member_snapshot or members()),
        member_statuses = {},
        rejected_operations = {},
        proof_overrides = {},
        verify_callbacks = {},
        calls = {},
        sequence = 0,
        next_token = nil,
        last_token = nil,
    }

    function provider:set_now(now)
        self.now = now
    end

    function provider:set_member_status(actor_id, status)
        self.member_statuses[actor_id] = status
    end

    function provider:reject(operation, rejected)
        self.rejected_operations[operation] = rejected ~= false
    end

    function provider:set_override(operation, field, value)
        local overrides = self.proof_overrides[operation] or {}
        self.proof_overrides[operation] = overrides
        overrides[field] = value
    end

    function provider:clear_override(operation, field)
        local overrides = self.proof_overrides[operation]
        if overrides then overrides[field] = nil end
    end

    function provider:reuse_next_token(token)
        self.next_token = token
    end

    function provider:on_verify(operation, callback)
        self.verify_callbacks[operation] = callback
    end

    function provider:verify(operation, context)
        self.calls[#self.calls + 1] = { operation = operation, context = copy_table(context) }
        if self.rejected_operations[operation] then return false end

        self.sequence = self.sequence + 1
        local proof = copy_table(context)
        proof.operation = operation
        proof.operation_token = self.next_token or (operation .. ':' .. tostring(self.sequence))
        self.next_token = nil
        self.last_token = proof.operation_token
        proof.now = self.now

        if operation == 'ox_entry' then
            proof.member_snapshot = copy_members(self.member_snapshot)
        elseif operation == 'ox_actor_invalidate' then
            proof.member_status = self.member_statuses[context.actor_id] or 'left'
        elseif operation == 'ox_phase_swap' then
            proof.next_phase_id = 'white_ox'
        elseif operation == 'dragon_finish'
            or operation == 'dragon_timeout'
            or operation == 'dragon_actor_invalidate' then
            proof.reason = context.requested_reason or 'finished'
        elseif operation == 'ox_failure' or operation == 'ox_timeout' then
            proof.reason = context.requested_reason
            if proof.reason == 'all_members_dead' then proof.all_members_dead = true end
        elseif operation == 'ox_success' then
            proof.reason = 'success'
        end

        for field, value in pairs(self.proof_overrides[operation] or {}) do proof[field] = value end
        local callback = self.verify_callbacks[operation]
        if callback then callback(context, proof) end
        return true, proof
    end

    return provider
end

local function dragon_request(encounter_key, actor_id, lifecycle_id)
    return {
        encounter_key = encounter_key,
        actor_id = actor_id,
        lifecycle_id = lifecycle_id,
    }
end

local function dragon_event(session)
    return {
        encounter_key = session.encounter_key,
        actor_id = session.owner_actor_id,
        lifecycle_id = session.owner_lifecycle_id,
        session_instance_id = session.session_instance_id,
        session_epoch = session.session_epoch,
    }
end

local function dragon_ack(session)
    return {
        encounter_key = session.encounter_key,
        actor_id = session.owner_actor_id,
        lifecycle_id = session.owner_lifecycle_id,
        session_instance_id = session.session_instance_id,
        session_epoch = session.session_epoch,
    }
end

local function ox_event(session)
    return {
        encounter_key = session.encounter_key,
        raid_instance_id = session.raid_instance_id,
        session_epoch = session.session_epoch,
        boss_instance_id = session.boss_instance_id,
        phase_id = session.phase_id,
    }
end

local function ox_ack(session)
    return {
        encounter_key = session.encounter_key,
        raid_instance_id = session.raid_instance_id,
        session_epoch = session.session_epoch,
        boss_instance_id = session.boss_instance_id,
        phase_id = session.phase_id,
    }
end

local function member_status(session, actor_id)
    for _, member in ipairs((session and session.members) or {}) do
        if member.actor_id == actor_id then return member.status end
    end
    return nil
end

local function assert_command_keys(payload, encounter_key, message)
    for index, command in ipairs((payload and payload.commands) or {}) do
        equal(command.encounter_key, encounter_key, (message or 'instance command') .. ' #' .. tostring(index))
    end
end

local function new_dragon(authority, progression_validator)
    return Instances.new_dragon_slots({
        authority_provider = authority,
        progression_validator = progression_validator or function() return true end,
    })
end

local function new_ox(authority, member_lifecycle_validator)
    return Instances.new_ox_battlefield({
        authority_provider = authority,
        member_lifecycle_validator = member_lifecycle_validator or function() return true end,
    })
end

local function ox_request(entry_request_id, actor_id, lifecycle_id)
    return {
        entry_request_id = entry_request_id,
        actor_id = actor_id or 'a',
        lifecycle_id = lifecycle_id or 1,
    }
end

do
    local dragon = Instances.new_dragon_slots({ progression_validator = function() return true end })
    local opened, error_code = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'a', 1))
    equal(opened, false, 'Dragon entry fails closed without a map-root authority provider')
    equal(error_code, 'authority-provider-required', 'missing Dragon authority provider is explicit')

    local ox = new_ox()
    opened, error_code = ox:open(ox_request('raid:no-provider'))
    equal(opened, false, 'Ox entry fails closed without a map-root authority provider')
    equal(error_code, 'authority-provider-required', 'missing Ox authority provider is explicit')
end

do
    local authority = new_authority({ now = 20 })
    local dragon = new_dragon(authority)
    local forged = dragon_request('HG_E_DRAGON_OLD_TIDE', 'a', 1)
    forged.authority_verified = true
    local opened, error_code = dragon:open(forged)
    equal(opened, false, 'caller authority booleans cannot open Dragon Palace')
    equal(error_code, 'untrusted-instance-authority-field:authority_verified',
        'Dragon rejects a caller authority boolean')

    local dragon_with_now = dragon_request('HG_E_DRAGON_OLD_TIDE', 'a', 1)
    dragon_with_now.now = 20
    opened, error_code = dragon:open(dragon_with_now)
    equal(opened, false, 'Dragon rejects a clock embedded in the caller request')
    equal(error_code, 'untrusted-instance-authority-field:now', 'Dragon request clock rejection is explicit')

    opened, error_code = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'a', 1), 20)
    equal(opened, false, 'Dragon rejects a caller-provided clock')
    equal(error_code, 'caller-instance-time-forbidden', 'Dragon clock rejection is explicit')

    local ox = new_ox(authority)
    opened, error_code = ox:open({ entry_request_id = 'raid:forged', actor_id = 'a', lifecycle_id = 1, members = members() })
    equal(opened, false, 'Ox rejects a caller-supplied raid-member snapshot')
    equal(error_code, 'untrusted-instance-authority-field:members', 'member snapshot rejection is explicit')

    opened, error_code = ox:open({ entry_request_id = 'raid:forged', actor_id = 'a', lifecycle_id = 1, authority_verified = true })
    equal(opened, false, 'Ox rejects a caller authority boolean')
    equal(error_code, 'untrusted-instance-authority-field:authority_verified',
        'Ox authority boolean rejection is explicit')

    local ox_with_now = ox_request('raid:forged')
    ox_with_now.now = 20
    opened, error_code = ox:open(ox_with_now)
    equal(opened, false, 'Ox rejects a clock embedded in the caller request')
    equal(error_code, 'untrusted-instance-authority-field:now', 'Ox request clock rejection is explicit')

    opened, error_code = ox:open(ox_request('raid:forged'), 20)
    equal(opened, false, 'Ox rejects a caller-provided clock')
    equal(error_code, 'caller-instance-time-forbidden', 'Ox clock rejection is explicit')
end

do
    local authority = new_authority({ now = 100 })
    local progress = {
        locked_old = { level = 60, discovered = false, underworld_late = true },
        locked_route = {
            level = 60, discovered = true, profession_id = 'C01',
            route_completion = { C02_ROUTE_LV8_core = true },
        },
        low_old = { level = 7, discovered = true, underworld_late = true },
        locked_reverse = { level = 60, discovered = true, underworld_late = false },
        a = {
            level = 8, discovered = true, underworld_late = false, profession_id = 'C01',
            route_completion = { C01_ROUTE_LV8_core = true },
        },
        c04 = {
            level = 8, discovered = true, underworld_late = false, profession_id = 'C04',
            selected_route_key = 'C04_ROUTE_LV8_wind',
            route_completion = { C04_ROUTE_LV8_hunt = true },
        },
    }
    local seen_requirements = {}
    local dragon = new_dragon(authority, function(query)
        seen_requirements[query.encounter_key] = query.requirements
        local state = progress[query.actor_id]
        if not state or state.level < query.requirements.min_level then return false end
        if query.requirements.discovery_key and not state.discovered then return false end
        if query.requirements.progression_key and not state[query.requirements.progression_key] then return false end
        local route = query.requirements.route_completion
        if route then
            local candidate_keys = route.completion_keys_by_profession[state.profession_id]
            if type(candidate_keys) ~= 'table' then return false end
            local selected_key = state.selected_route_key
            if #candidate_keys == 1 then selected_key = candidate_keys[1] end
            local selected_is_allowed = false
            for _, candidate_key in ipairs(candidate_keys) do
                if candidate_key == selected_key then selected_is_allowed = true end
            end
            if not selected_is_allowed or state.route_completion[selected_key] ~= true then return false end
        end
        return true
    end)

    local locked = dragon_request('HG_E_DRAGON_OLD_TIDE', 'locked_old', 90)
    locked.unlock_verified, locked.discovered, locked.level = true, true, 60
    local opened, error_code = dragon:open(locked)
    equal(opened, false, 'caller progression booleans cannot forge Dragon eligibility')
    equal(error_code, 'old-tide-progression-not-eligible', 'trusted progression result still controls old tide entry')

    opened, error_code = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'low_old', 91))
    equal(opened, false, 'trusted Lv8 rule rejects a low-level caller')
    equal(error_code, 'old-tide-progression-not-eligible', 'low-level Dragon rejection is explicit')

    opened, error_code = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'locked_route', 93))
    equal(opened, false, 'old tide rejects a discovered high-level actor without the persisted route completion')
    equal(error_code, 'old-tide-progression-not-eligible', 'missing old-tide route completion is explicit')

    opened, error_code = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'c04', 94))
    equal(opened, false, 'C04 cannot use a completed route different from the actor selected route')
    equal(error_code, 'old-tide-progression-not-eligible', 'C04 selected-route mismatch is explicit')
    progress.c04.route_completion.C04_ROUTE_LV8_wind = true

    local forged_route = dragon_request('HG_E_DRAGON_OLD_TIDE', 'a', 1)
    forged_route.profession_id = 'C04'
    opened, error_code = dragon:open(forged_route)
    equal(opened, false, 'caller profession cannot replace authoritative progression identity')
    equal(error_code, 'untrusted-instance-authority-field:profession_id', 'caller profession rejection is explicit')

    opened, error_code = dragon:open(dragon_request('HG_E_DRAGON_REVERSE_TIDE', 'locked_reverse', 92))
    equal(opened, false, 'trusted late-underworld rule rejects the reverse tide caller')
    equal(error_code, 'reverse-tide-progression-not-eligible', 'reverse tide rejection is explicit')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.min_level, 8, 'old tide proof query preserves Lv8')
    equal(seen_requirements.HG_E_DRAGON_REVERSE_TIDE.min_level, 38, 'reverse tide proof query preserves Lv38')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.route_completion.scope, 'actor_current_profession',
        'old tide route completion is actor-private and profession-resolved')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.route_completion.trial_seconds, 60,
        'old tide route completion preserves the 60-second trial contract')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.route_completion.completion_keys_by_profession.C01[1],
        'C01_ROUTE_LV8_core', 'old tide proof query preserves the C01 route key')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.route_completion.completion_keys_by_profession.C02[1],
        'C02_ROUTE_LV8_core', 'old tide proof query preserves the C02 route key')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.route_completion.completion_keys_by_profession.C03[1],
        'C03_ROUTE_LV8_core', 'old tide proof query preserves the C03 route key')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.route_completion.completion_keys_by_profession.C04[1],
        'C04_ROUTE_LV8_hunt', 'old tide proof query preserves the C04 hunt route option')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.route_completion.completion_keys_by_profession.C04[2],
        'C04_ROUTE_LV8_wind', 'old tide proof query preserves the C04 route options')
    equal(seen_requirements.HG_E_DRAGON_OLD_TIDE.route_completion.completion_keys_by_profession.C04[3],
        'C04_ROUTE_LV8_bind', 'old tide proof query preserves the C04 bind route option')

    authority:reject('dragon_entry')
    opened, error_code = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'a', 1))
    equal(opened, false, 'Dragon entry rejects a missing root proof')
    equal(error_code, 'authority-proof-rejected:dragon_entry', 'Dragon entry proof failure is explicit')
    authority:reject('dragon_entry', false)

    local opened_ok, opened_result = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'a', 1))
    truthy(opened_ok, 'authority-signed Dragon entry opens a slot')
    local c04_opened = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'c04', 2))
    truthy(c04_opened, 'authority resolves the C04 selected route from actor progress rather than caller input')
    equal(opened_result.session.opened_at, 100, 'Dragon stores only provider time')
    equal(opened_result.session.deadline_at, 820, 'Dragon deadline derives from provider time')
    equal(opened_result.session.cleanup_token, nil, 'Dragon public session snapshot omits cleanup capability')
    opened_result.session.state, opened_result.session.deadline_at, opened_result.session.slot_id = 'forged', 0, 99
    equal(dragon:get_by_actor('a').state, 'active', 'mutating a Dragon session snapshot cannot affect authority state')
    equal(dragon:get_by_actor('a').deadline_at, 820, 'Dragon deadline remains private from snapshot mutations')
    equal(dragon:get_by_actor('a').slot_id, 1, 'Dragon slot allocation remains private from open-result mutations')
    local dragon_lookup = dragon:get_by_actor('a')
    equal(dragon_lookup.cleanup_token, nil, 'Dragon actor lookup omits cleanup capability')
    dragon_lookup.state, dragon_lookup.slot_id, dragon_lookup.owner_lifecycle_id = 'closed', 88, 999
    equal(dragon:get_by_actor('a').state, 'active', 'mutating a Dragon actor lookup cannot close the real session')
    equal(dragon:get_by_actor('a').slot_id, 1, 'mutating a Dragon actor lookup cannot move the real slot')
    equal(dragon:get_by_actor('a').owner_lifecycle_id, 1,
        'mutating a Dragon actor lookup cannot change the real lifecycle')
    assert_command_keys(opened_result, 'HG_E_DRAGON_OLD_TIDE', 'Dragon entry command')

    local forged_finish = dragon_event(opened_result.session, 'success')
    forged_finish.kill_verified = true
    local finished, finish_error = dragon:finish(forged_finish)
    equal(finished, false, 'caller kill proof cannot finish Dragon Palace')
    equal(finish_error, 'untrusted-instance-authority-field:kill_verified', 'Dragon kill proof rejection is explicit')
    equal(dragon:get_by_actor('a').state, 'active', 'forged Dragon kill leaves the slot active')

    forged_finish = dragon_event(opened_result.session)
    forged_finish.reason = 'success'
    finished, finish_error = dragon:finish(forged_finish)
    equal(finished, false, 'caller completion reasons cannot finish Dragon Palace')
    equal(finish_error, 'untrusted-instance-authority-field:reason', 'Dragon finish reason is provider-owned')

    authority:reject('dragon_finish')
    finished, finish_error = dragon:finish(dragon_event(opened_result.session, 'success'))
    equal(finished, false, 'Dragon finish fails closed without a root operation proof')
    equal(finish_error, 'authority-proof-rejected:dragon_finish', 'Dragon finish proof failure is explicit')
    equal(dragon:get_by_actor('a').state, 'active', 'missing finish proof leaves Dragon active')
    authority:reject('dragon_finish', false)

    local finished_ok, pending = dragon:finish(dragon_event(opened_result.session, 'success'))
    truthy(finished_ok, 'authority-signed Dragon finish begins cleanup')
    equal(dragon:get_by_actor('a').state, 'cleanup_pending', 'Dragon waits for a root-signed cleanup acknowledgement')
    equal(pending.commands[1].slot_id, 1, 'Dragon cleanup still targets the authoritative slot')
    assert_command_keys(pending, 'HG_E_DRAGON_OLD_TIDE', 'Dragon cleanup command')

    local forged_ack = dragon_ack(opened_result.session)
    forged_ack.cleanup_token = 'forged-cleanup-token'
    local acknowledged, ack_error = dragon:acknowledge_cleanup(forged_ack)
    equal(acknowledged, false, 'caller cleanup token cannot release a Dragon slot')
    equal(ack_error, 'untrusted-instance-authority-field:cleanup_token', 'Dragon cleanup token rejection is explicit')

    local forged_ack_boolean = dragon_ack(opened_result.session)
    forged_ack_boolean.cleanup_verified = true
    acknowledged, ack_error = dragon:acknowledge_cleanup(forged_ack_boolean)
    equal(acknowledged, false, 'caller cleanup boolean cannot release a Dragon slot')
    equal(ack_error, 'untrusted-instance-authority-field:cleanup_verified',
        'Dragon cleanup boolean rejection is explicit')

    authority:reject('dragon_cleanup_ack')
    acknowledged, ack_error = dragon:acknowledge_cleanup(dragon_ack(opened_result.session))
    equal(acknowledged, false, 'Dragon cleanup acknowledgement fails closed without proof')
    equal(ack_error, 'authority-proof-rejected:dragon_cleanup_ack', 'Dragon ack proof failure is explicit')
    equal(dragon:get_by_actor('a').state, 'cleanup_pending', 'missing ack proof keeps the slot occupied')
    authority:reject('dragon_cleanup_ack', false)

    local acknowledged_ok, released = dragon:acknowledge_cleanup(dragon_ack(opened_result.session))
    truthy(acknowledged_ok, 'authority-signed Dragon cleanup acknowledgement releases the slot')
    assert_command_keys(released, 'HG_E_DRAGON_OLD_TIDE', 'Dragon release command')
    equal(dragon:get_by_actor('a'), nil, 'Dragon owner lock releases only after the proof-backed ack')
end

do
    local authority = new_authority({ now = 10 })
    local dragon = new_dragon(authority)
    local opened_ok, opened = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'timeout', 1))
    truthy(opened_ok, 'Dragon timeout fixture opens through authority')
    local caller_tick = dragon:tick(opened.session.deadline_at)
    equal(caller_tick.authority_error, 'caller-instance-time-forbidden', 'Dragon tick rejects caller clock input')
    equal(dragon:get_by_actor('timeout').state, 'active', 'rejected Dragon tick does not mutate state')

    authority:set_now(opened.session.deadline_at - 1)
    local early_tick = dragon:tick()
    equal(#early_tick.commands, 0, 'authoritative pre-deadline Dragon tick is inert')
    authority:set_now(opened.session.deadline_at)
    authority:reject('dragon_timeout')
    local denied_timeout = dragon:tick()
    equal(#denied_timeout.commands, 0, 'Dragon timeout cannot cleanup without a root terminal proof')
    equal(denied_timeout.authority_error, 'authority-proof-rejected:dragon_timeout',
        'Dragon timeout proof failure is surfaced')
    equal(dragon:get_by_actor('timeout').state, 'active', 'missing Dragon timeout proof leaves session active')
    authority:reject('dragon_timeout', false)
    local timed = dragon:tick()
    equal(#timed.commands, 1, 'authority-signed Dragon timeout emits cleanup')
    assert_command_keys(timed, 'HG_E_DRAGON_OLD_TIDE', 'Dragon timeout command')
    equal(dragon:get_by_actor('timeout').state, 'cleanup_pending', 'Dragon timeout keeps the slot pending acknowledgement')
end

do
    local authority = new_authority({ now = 30 })
    local dragon = new_dragon(authority)
    local opened_ok, opened = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'invalidate', 3))
    truthy(opened_ok, 'Dragon invalidation fixture opens')
    authority:reject('dragon_actor_invalidate')
    local invalidated, invalidation_error = dragon:invalidate_actor('invalidate', 3)
    equal(invalidated, false, 'Dragon actor invalidation fails closed without proof')
    equal(invalidation_error, 'authority-proof-rejected:dragon_actor_invalidate',
        'Dragon invalidation proof failure is explicit')
    equal(dragon:get_by_actor('invalidate').state, 'active', 'failed Dragon invalidation does not mutate state')
    authority:reject('dragon_actor_invalidate', false)
    local invalidated_ok, invalidation = dragon:invalidate_actor('invalidate', 3)
    truthy(invalidated_ok, 'authority-signed Dragon actor invalidation begins cleanup')
    assert_command_keys(invalidation, 'HG_E_DRAGON_OLD_TIDE', 'Dragon actor invalidation command')

    local replay_authority = new_authority({ now = 50 })
    local replay_dragon = new_dragon(replay_authority)
    local replay_opened_ok, replay_opened = replay_dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'replay', 4))
    truthy(replay_opened_ok, 'Dragon replay fixture opens')
    replay_authority:reuse_next_token(replay_authority.last_token)
    local replayed, replay_error = replay_dragon:finish(dragon_event(replay_opened.session, 'success'))
    equal(replayed, false, 'reused root proof token cannot finish a Dragon session')
    equal(replay_error, 'authority-operation-token-replayed', 'Dragon proof token replay is explicit')
    equal(replay_dragon:get_by_actor('replay').state, 'active', 'replayed proof cannot mutate Dragon state')
end

do
    local authority = new_authority({ now = 200 })
    local ox = new_ox(authority)
    authority:reject('ox_entry')
    local opened, error_code = ox:open(ox_request('raid:proof-required'))
    equal(opened, false, 'Ox entry rejects a missing root member snapshot proof')
    equal(error_code, 'authority-proof-rejected:ox_entry', 'Ox entry proof failure is explicit')
    authority:reject('ox_entry', false)
    authority:set_override('ox_entry', 'member_snapshot', false)
    opened, error_code = ox:open(ox_request('raid:bad-snapshot'))
    equal(opened, false, 'Ox rejects an invalid provider member snapshot')
    equal(error_code, 'trusted-raid-member-snapshot-invalid:invalid-raid-member-snapshot',
        'invalid root member snapshot is explicit')
    authority:clear_override('ox_entry', 'member_snapshot')

    local stale_member_ox = new_ox(authority, function(actor_id)
        return actor_id ~= 'd'
    end)
    opened, error_code = stale_member_ox:open(ox_request('raid:stale-member'))
    equal(opened, false, 'a root-signed member snapshot still requires current member lifecycles')
    equal(error_code, 'stale-raid-member-lifecycle', 'stale member snapshot rejection is explicit')

    authority:set_override('ox_entry', 'member_snapshot', { {
        actor_id = 'b', lifecycle_id = 2, team_id = 'team',
    } })
    local missing_entry_ox = new_ox(authority)
    opened, error_code = missing_entry_ox:open(ox_request('raid:missing-entry-member'))
    equal(opened, false, 'the triggering actor must be present in the root-signed raid snapshot')
    equal(error_code, 'raid-entry-actor-not-in-member-snapshot', 'missing triggering member is explicit')
    authority:clear_override('ox_entry', 'member_snapshot')

    local opened_ok, opened_result = ox:open(ox_request('raid:legal'))
    truthy(opened_ok, 'authority-signed Ox entry uses the root member snapshot')
    equal(#opened_result.session.members, 4, 'Ox copies four root-signed members')
    equal(opened_result.session.members[1].actor_id, 'a', 'Ox member identity comes from root snapshot')
    equal(opened_result.session.deadline_at, 1400, 'Ox deadline derives from provider time')
    equal(opened_result.session.cleanup_token, nil, 'Ox public session snapshot omits cleanup capability')
    opened_result.session.members[1].status = 'left'
    opened_result.session.member_by_actor.a.status = 'left'
    equal(member_status(ox:get_active_session(), 'a'), 'active',
        'mutating an Ox session member snapshot cannot affect authority state')
    local ox_lookup = ox:get_by_actor('a')
    equal(ox_lookup.cleanup_token, nil, 'Ox actor lookup omits cleanup capability')
    ox_lookup.state = 'closed'
    ox_lookup.members[1].status = 'dead'
    ox_lookup.member_by_actor.a.status = 'dead'
    equal(ox:get_by_actor('a').state, 'active', 'mutating an Ox actor lookup cannot close the real raid')
    equal(member_status(ox:get_by_actor('a'), 'a'), 'active',
        'mutating an Ox actor lookup cannot change the real member status')
    opened_result.commands[1].member_ids[1].status = 'left'
    opened_result.commands[1].member_ids[1].actor_id = 'forged-member'
    equal(member_status(ox:get_active_session(), 'a'), 'active',
        'mutating an Ox lock command member list cannot affect authority state')
    equal(#ox:get_active_session().members, 4, 'mutating an Ox lock command cannot change the real member count')
    assert_command_keys(opened_result, 'HG_E_OX_BATTLEFIELD', 'Ox entry command')

    local phase_with_clock, phase_clock_error = ox:swap_to_white_ox(ox_event(opened_result.session), 201)
    equal(phase_with_clock, false, 'Ox phase swap rejects caller time')
    equal(phase_clock_error, 'caller-instance-time-forbidden', 'Ox phase clock rejection is explicit')
    local forged_phase = ox_event(opened_result.session)
    forged_phase.phase_verified = true
    local phased, phase_error = ox:swap_to_white_ox(forged_phase)
    equal(phased, false, 'caller phase proof cannot advance Ox')
    equal(phase_error, 'untrusted-instance-authority-field:phase_verified', 'Ox phase proof rejection is explicit')
    authority:reject('ox_phase_swap')
    phased, phase_error = ox:swap_to_white_ox(ox_event(opened_result.session))
    equal(phased, false, 'Ox phase swap fails closed without root proof')
    equal(phase_error, 'authority-proof-rejected:ox_phase_swap', 'Ox phase proof failure is explicit')
    authority:reject('ox_phase_swap', false)
    local phase_ok, phase = ox:swap_to_white_ox(ox_event(opened_result.session))
    truthy(phase_ok, 'authority-signed Ox phase swap succeeds')
    assert_command_keys(phase, 'HG_E_OX_BATTLEFIELD', 'Ox phase command')

    authority:set_member_status('a', 'dead')
    local invalidated, invalidation_error = ox:invalidate_actor('a', 1, 201, 'death')
    equal(invalidated, false, 'Ox invalidation rejects caller clock and reason')
    equal(invalidation_error, 'caller-instance-time-forbidden', 'Ox invalidation clock rejection is explicit')
    authority:reject('ox_actor_invalidate')
    invalidated, invalidation_error = ox:invalidate_actor('a', 1)
    equal(invalidated, false, 'Ox actor invalidation fails closed without root proof')
    equal(invalidation_error, 'authority-proof-rejected:ox_actor_invalidate', 'Ox invalidation proof failure is explicit')
    authority:reject('ox_actor_invalidate', false)
    local invalidated_ok, invalidation = ox:invalidate_actor('a', 1)
    truthy(invalidated_ok, 'authority-signed Ox actor invalidation records root status')
    equal(member_status(ox:get_active_session(), 'a'), 'dead', 'Ox keeps the authority-signed member status')
    assert_command_keys(invalidation, 'HG_E_OX_BATTLEFIELD', 'Ox member invalidation command')

    local forged_success = ox_event(ox:get_active_session())
    forged_success.success_verified = true
    local succeeded, success_error = ox:succeed(forged_success)
    equal(succeeded, false, 'caller success proof cannot finish Ox')
    equal(success_error, 'untrusted-instance-authority-field:success_verified', 'Ox success proof rejection is explicit')
    succeeded, success_error = ox:succeed(ox_event(ox:get_active_session()), 201)
    equal(succeeded, false, 'Ox success rejects caller time')
    equal(success_error, 'caller-instance-time-forbidden', 'Ox success clock rejection is explicit')
    authority:reject('ox_success')
    succeeded, success_error = ox:succeed(ox_event(ox:get_active_session()))
    equal(succeeded, false, 'Ox success fails closed without root proof')
    equal(success_error, 'authority-proof-rejected:ox_success', 'Ox success proof failure is explicit')
    authority:reject('ox_success', false)
    local succeeded_ok, success_cleanup = ox:succeed(ox_event(ox:get_active_session()))
    truthy(succeeded_ok, 'authority-signed Ox success begins cleanup')
    assert_command_keys(success_cleanup, 'HG_E_OX_BATTLEFIELD', 'Ox success cleanup command')
    success_cleanup.commands[1].member_ids[1].status = 'active'
    success_cleanup.commands[1].member_ids[1].actor_id = 'forged-member'
    equal(member_status(ox:get_by_actor('a'), 'a'), 'dead',
        'mutating an Ox cleanup command member list cannot change the real member status')
    equal(#ox:get_by_actor('a').members, 4,
        'mutating an Ox cleanup command member list cannot change the real member count')

    local forged_ack = ox_ack(opened_result.session)
    forged_ack.cleanup_token = 'forged-cleanup-token'
    local acknowledged, ack_error = ox:acknowledge_cleanup(forged_ack)
    equal(acknowledged, false, 'caller cleanup token cannot release Ox')
    equal(ack_error, 'untrusted-instance-authority-field:cleanup_token', 'Ox cleanup token rejection is explicit')

    local forged_ack_boolean = ox_ack(opened_result.session)
    forged_ack_boolean.cleanup_verified = true
    acknowledged, ack_error = ox:acknowledge_cleanup(forged_ack_boolean)
    equal(acknowledged, false, 'caller cleanup boolean cannot release Ox')
    equal(ack_error, 'untrusted-instance-authority-field:cleanup_verified',
        'Ox cleanup boolean rejection is explicit')
    authority:reject('ox_cleanup_ack')
    acknowledged, ack_error = ox:acknowledge_cleanup(ox_ack(ox:get_active_session()))
    equal(acknowledged, false, 'Ox cleanup acknowledgement fails closed without root proof')
    equal(ack_error, 'authority-proof-rejected:ox_cleanup_ack', 'Ox ack proof failure is explicit')
    authority:reject('ox_cleanup_ack', false)
    local acknowledged_ok, released = ox:acknowledge_cleanup(ox_ack(ox:get_active_session()))
    truthy(acknowledged_ok, 'authority-signed Ox cleanup acknowledgement releases the raid')
    assert_command_keys(released, 'HG_E_OX_BATTLEFIELD', 'Ox release command')
    equal(ox:get_active_session(), nil, 'Ox active lock releases only after proof-backed acknowledgement')
end

do
    local authority = new_authority({ now = 300 })
    local ox = new_ox(authority)
    local opened_ok, opened = ox:open(ox_request('raid:failure'))
    truthy(opened_ok, 'Ox failure fixture opens')
    for _, member in ipairs(opened.session.members) do authority:set_member_status(member.actor_id, 'dead') end

    local final_member = opened.session.members[#opened.session.members]
    for index, member in ipairs(opened.session.members) do
        if index == #opened.session.members then authority:reject('ox_failure') end
        local invalidated, item = ox:invalidate_actor(member.actor_id, member.lifecycle_id)
        if index == #opened.session.members then
            equal(invalidated, false, 'final Ox death stays uncommitted when terminal cleanup proof is absent')
            equal(item, 'authority-proof-rejected:ox_failure',
                'final Ox death reports its missing terminal cleanup proof')
        else
            truthy(invalidated, 'authority-signed Ox death invalidates a current member')
            assert_command_keys(item, 'HG_E_OX_BATTLEFIELD', 'Ox death invalidation command')
        end
    end
    equal(ox:get_active_session().state, 'active', 'missing terminal failure proof cannot start cleanup')
    equal(member_status(ox:get_active_session(), final_member.actor_id), 'active',
        'missing terminal failure proof leaves the final member retryable')
    local rejected_invalidation_token = authority.last_token
    authority:reject('ox_failure', false)
    authority:reuse_next_token(rejected_invalidation_token)
    local replayed, replay_error = ox:invalidate_actor(final_member.actor_id, final_member.lifecycle_id)
    equal(replayed, false, 'the rejected final-death proof token cannot be replayed on retry')
    equal(replay_error, 'authority-operation-token-replayed',
        'retry still enforces the actor authority-token constraint')
    equal(member_status(ox:get_active_session(), final_member.actor_id), 'active',
        'a replayed retry proof still leaves the final member uncommitted')

    local forged_failure = ox_event(ox:get_active_session())
    forged_failure.failure_verified = true
    local failed, failure_error = ox:fail(forged_failure)
    equal(failed, false, 'caller failure proof cannot start Ox cleanup')
    equal(failure_error, 'untrusted-instance-authority-field:failure_verified', 'Ox failure proof rejection is explicit')
    failed, failure_error = ox:fail(ox_event(ox:get_active_session()), 301)
    equal(failed, false, 'Ox failure rejects caller time')
    equal(failure_error, 'caller-instance-time-forbidden', 'Ox failure clock rejection is explicit')
    authority:set_override('ox_failure', 'all_members_dead', false)
    failed, failure_error = ox:fail(ox_event(ox:get_active_session()))
    equal(failed, false, 'Ox failure requires the root wipe assertion')
    equal(failure_error, 'ox-wipe-not-authoritative', 'missing root wipe assertion is explicit')
    authority:clear_override('ox_failure', 'all_members_dead')
    local failed_ok, cleanup = ox:invalidate_actor(final_member.actor_id, final_member.lifecycle_id)
    truthy(failed_ok, 'a fresh root proof retries and commits the final Ox death')
    equal(member_status(ox:get_active_session(), final_member.actor_id), 'dead',
        'the successful retry commits the final member death')
    equal(ox:get_active_session().state, 'cleanup_pending',
        'the successful retry commits cleanup in the same transition')
    equal(cleanup.rage_layers, 1, 'root-signed Ox failure adds one rage layer')
    assert_command_keys(cleanup, 'HG_E_OX_BATTLEFIELD', 'Ox failure cleanup command')
    truthy(ox:acknowledge_cleanup(ox_ack(ox:get_active_session())),
        'root-signed Ox failure acknowledgement releases the raid')

    authority:set_now(600)
    local rage_cleared = ox:tick()
    equal(#rage_cleared.commands, 1, 'authoritative rage clock clears expired Ox rage')
    assert_command_keys(rage_cleared, 'HG_E_OX_BATTLEFIELD', 'Ox rage clear command')
    local rage = ox:rage_state()
    equal(rage.layers, 0, 'authority-backed rage state observes expiration')
end

do
    local authority = new_authority({ now = 500 })
    local ox = new_ox(authority)
    local opened_ok, opened = ox:open(ox_request('raid:timeout'))
    truthy(opened_ok, 'Ox timeout fixture opens')
    local caller_tick = ox:tick(opened.session.deadline_at)
    equal(caller_tick.authority_error, 'caller-instance-time-forbidden', 'Ox tick rejects caller clock input')
    authority:set_now(opened.session.deadline_at - 1)
    local early_tick = ox:tick()
    equal(#early_tick.commands, 0, 'authoritative pre-deadline Ox tick is inert')
    authority:set_now(opened.session.deadline_at)
    authority:reject('ox_timeout')
    local denied_timeout = ox:tick()
    equal(#denied_timeout.commands, 0, 'Ox timeout cannot cleanup without root terminal proof')
    equal(denied_timeout.authority_error, 'authority-proof-rejected:ox_timeout',
        'Ox timeout proof failure is surfaced')
    equal(ox:get_active_session().state, 'active', 'missing Ox timeout proof leaves the raid active')
    authority:reject('ox_timeout', false)
    local timed = ox:tick()
    equal(#timed.commands, 1, 'authority-signed Ox timeout emits cleanup')
    assert_command_keys(timed, 'HG_E_OX_BATTLEFIELD', 'Ox timeout command')
    equal(ox:get_active_session().state, 'cleanup_pending', 'Ox timeout waits for cleanup acknowledgement')
end

do
    local authority = new_authority({ now = 0 })
    local dragon = new_dragon(authority)
    local opened_ok, opened = dragon:open(dragon_request('HG_E_DRAGON_OLD_TIDE', 'token-dragon', 1))
    truthy(opened_ok, 'Dragon token-lifecycle fixture opens')
    local first_entry_token = authority.last_token
    local tick_error = nil
    for now = 1, 200 do
        authority:set_now(now)
        local item = dragon:tick()
        if item.authority_error or #item.commands ~= 0 then
            tick_error = item.authority_error or 'unexpected-command'
            break
        end
    end
    equal(tick_error, nil, 'long-running Dragon ticks remain authorized before the deadline')
    truthy(table_size(dragon.used_authority_tokens) > 100,
        'an active Dragon session retains enough token history to reject old in-session replays')

    authority:set_now(201)
    truthy(dragon:finish(dragon_event(opened.session)), 'Dragon token-lifecycle fixture begins cleanup')
    authority:set_now(202)
    truthy(dragon:acknowledge_cleanup(dragon_ack(dragon:get_by_actor('token-dragon'))),
        'Dragon token-lifecycle fixture releases its slot')
    equal(table_size(dragon.used_authority_tokens), 0,
        'closing a Dragon session releases its operation-token replay ledger')
    equal(table_size(dragon.authority_token_scopes), 0,
        'closing a Dragon session releases its token-scope index')

    authority:reuse_next_token(first_entry_token)
    local reopened_ok, reopened = dragon:open(
        dragon_request('HG_E_DRAGON_OLD_TIDE', 'token-dragon', 1)
    )
    truthy(reopened_ok, 'a closed Dragon session can safely reclaim and reuse an old token value')
    local stale_ok, stale_error = dragon:finish(dragon_event(opened.session))
    equal(stale_ok, false, 'reclaiming a token does not authorize an old Dragon session epoch')
    equal(stale_error, 'stale-dragon-session', 'old Dragon epoch rejection remains explicit after reclamation')
    authority:reuse_next_token(first_entry_token)
    local replayed, replay_error = dragon:finish(dragon_event(reopened.session))
    equal(replayed, false, 'the reclaimed entry token still cannot replay inside its new active Dragon session')
    equal(replay_error, 'authority-operation-token-replayed',
        'current Dragon session replay rejection survives ledger reclamation')
    truthy(dragon:finish(dragon_event(reopened.session)), 'a fresh Dragon proof can finish the reopened session')
    truthy(dragon:acknowledge_cleanup(dragon_ack(dragon:get_by_actor('token-dragon'))),
        'the reopened Dragon session releases cleanly')
    equal(table_size(dragon.used_authority_tokens), 0,
        'repeated Dragon session closure leaves no replay-ledger residue')
    equal(table_size(dragon.authority_token_scopes), 0,
        'repeated Dragon session closure leaves no token-scope residue')
end

do
    local authority = new_authority({
        now = 0,
        member_snapshot = { { actor_id = 'token-ox', lifecycle_id = 1, team_id = 'team' } },
    })
    local ox = new_ox(authority)
    local opened_ok, opened = ox:open(ox_request('raid:token-lifecycle', 'token-ox', 1))
    truthy(opened_ok, 'Ox token-lifecycle fixture opens')
    local tick_error = nil
    for now = 1, 200 do
        authority:set_now(now)
        local item = ox:tick()
        if item.authority_error or #item.commands ~= 0 then
            tick_error = item.authority_error or 'unexpected-command'
            break
        end
    end
    equal(tick_error, nil, 'long-running Ox ticks remain authorized before the deadline')
    truthy(table_size(ox.used_authority_tokens) > 100,
        'an active Ox session retains enough token history to reject old in-session replays')

    authority:set_now(201)
    truthy(ox:succeed(ox_event(opened.session)), 'Ox token-lifecycle fixture begins successful cleanup')
    authority:set_now(202)
    truthy(ox:acknowledge_cleanup(ox_ack(ox:get_active_session())),
        'Ox token-lifecycle fixture releases its member locks')
    equal(table_size(ox.used_authority_tokens), 0,
        'closing an Ox session releases its operation-token replay ledger')
    equal(table_size(ox.authority_token_scopes), 0,
        'closing a successful Ox session releases its token-scope index')

    local idle_error = nil
    for now = 203, 402 do
        authority:set_now(now)
        local state, error_code = ox:rage_state()
        if not state then
            idle_error = error_code
            break
        end
    end
    equal(idle_error, nil, 'authority-backed idle Ox state remains readable after session closure')
    equal(table_size(ox.used_authority_tokens), 0,
        'long-term idle Ox reads do not recreate an unbounded token ledger')
    equal(table_size(ox.authority_token_scopes), 0,
        'long-term idle Ox reads do not recreate token scopes')
end

do
    local authority = new_authority({
        now = 0,
        member_snapshot = { { actor_id = 'rage-reset', lifecycle_id = 1, team_id = 'team' } },
    })
    local ox = new_ox(authority)
    local opened_ok, opened = ox:open(ox_request('raid:rage-reset-old', 'rage-reset', 1))
    truthy(opened_ok, 'Ox rage-reset token fixture opens its first session')
    authority:set_member_status('rage-reset', 'dead')
    truthy(ox:invalidate_actor('rage-reset', 1), 'Ox rage-reset fixture creates a failed rage cycle')
    truthy(ox:acknowledge_cleanup(ox_ack(ox:get_active_session())),
        'Ox rage-reset fixture releases its failed session')

    authority:set_now(10)
    truthy(ox:rage_state(), 'Ox rage-reset fixture records a token inside the live rage cycle')
    local rage_token = authority.last_token
    authority:set_now(301)
    authority:reuse_next_token(rage_token)
    local reopened_ok, reopened = ox:open(ox_request('raid:rage-reset-new', 'rage-reset', 1))
    truthy(reopened_ok, 'an expired Ox rage cycle safely reclaims its token values for a new session')
    equal(reopened.rage_layers, 0, 'authoritative expiry resets Ox rage before the new session opens')

    local stale_ok, stale_error = ox:succeed(ox_event(opened.session))
    equal(stale_ok, false, 'rage token reclamation does not authorize an old Ox session epoch')
    equal(stale_error, 'stale-ox-session', 'old Ox epoch rejection remains explicit after rage reset')
    authority:reuse_next_token(rage_token)
    local replayed, replay_error = ox:succeed(ox_event(reopened.session))
    equal(replayed, false, 'the reclaimed token cannot replay inside the new active Ox session')
    equal(replay_error, 'authority-operation-token-replayed',
        'current Ox session replay rejection survives rage reset')
    truthy(ox:succeed(ox_event(reopened.session)), 'a fresh proof finishes the post-reset Ox session')
    truthy(ox:acknowledge_cleanup(ox_ack(ox:get_active_session())),
        'the post-reset Ox session releases cleanly')
    equal(table_size(ox.used_authority_tokens), 0,
        'post-reset Ox closure leaves no operation-token residue')
    equal(table_size(ox.authority_token_scopes), 0,
        'post-reset Ox closure leaves no token-scope residue')
end

do
    local authority = new_authority({ now = 10 })
    local dragon
    local nested_ok, nested
    local reentered = false
    dragon = Instances.new_dragon_slots({
        authority_provider = authority,
        progression_validator = function(query)
            if query.actor_id == 'outer-slot' and not reentered then
                reentered = true
                nested_ok, nested = dragon:open(dragon_request(
                    'HG_E_DRAGON_OLD_TIDE', 'nested-slot', 2
                ))
            end
            return true
        end,
    })

    local opened, error_code = dragon:open(dragon_request(
        'HG_E_DRAGON_OLD_TIDE', 'outer-slot', 1
    ))
    equal(nested_ok, true, 'Dragon progression callback can complete the nested slot fixture')
    equal(opened, false, 'Dragon entry rejects a slot claimed during progression validation')
    equal(error_code, 'dragon-instance-slot-no-longer-free',
        'Dragon slot CAS rejection is explicit')
    equal(dragon:get_by_actor('outer-slot'), nil,
        'stale outer Dragon entry never creates an actor session')
    equal(nested.session.slot_id, 1, 'nested Dragon entry retains the slot it committed')
    equal(dragon:get_by_actor('nested-slot').session_instance_id, nested.session.session_instance_id,
        'outer Dragon entry cannot overwrite the nested slot owner')
end

do
    local authority = new_authority({ now = 15 })
    local actor_id = 'dragon-progression-lifecycle-reentry'
    local current_lifecycle = 1
    local request = dragon_request('HG_E_DRAGON_OLD_TIDE', actor_id, current_lifecycle)
    local reentered = false
    local dragon = Instances.new_dragon_slots({
        authority_provider = authority,
        actor_lifecycle_validator = function(candidate_actor_id, lifecycle_id)
            return candidate_actor_id == actor_id and lifecycle_id == current_lifecycle
        end,
        progression_validator = function(query)
            if query.actor_id == actor_id and query.lifecycle_id == 1 and not reentered then
                reentered = true
                current_lifecycle = 2
                request.lifecycle_id = current_lifecycle
            end
            return true
        end,
    })

    local opened, error_code = dragon:open(request)
    equal(reentered, true, 'Dragon progression callback completes the lifecycle reentry fixture')
    equal(opened, false, 'Dragon progression reentry rejects the admitted old lifecycle')
    equal(error_code, 'stale-actor-lifecycle',
        'Dragon progression reentry has a stable lifecycle rejection')
    equal(dragon:get_by_actor(actor_id), nil,
        'stale progression admission does not occupy a Dragon slot')
    equal(#authority.calls, 0,
        'stale progression admission does not request an entry authority proof')
    equal(table_size(dragon.used_authority_tokens), 0,
        'stale progression admission does not consume an authority token')

    local reopened, replacement = dragon:open(request)
    truthy(reopened, 'replacement lifecycle can immediately enter Dragon after progression reentry')
    equal(replacement.session.owner_lifecycle_id, current_lifecycle,
        'replacement Dragon session is owned by the current lifecycle')
    equal(replacement.session.slot_id, 1,
        'replacement lifecycle receives the still-free first Dragon slot')
    equal(replacement.commands[1].lifecycle_id, current_lifecycle,
        'replacement lifecycle is the only owner emitted to the map adapter')
end

do
    local authority = new_authority({ now = 18 })
    local actor_id = 'dragon-authority-lifecycle-reentry'
    local current_lifecycle = 1
    local request = dragon_request('HG_E_DRAGON_OLD_TIDE', actor_id, current_lifecycle)
    local stale_entry_token
    local reentered = false
    local dragon = Instances.new_dragon_slots({
        authority_provider = authority,
        actor_lifecycle_validator = function(candidate_actor_id, lifecycle_id)
            return candidate_actor_id == actor_id and lifecycle_id == current_lifecycle
        end,
        progression_validator = function() return true end,
    })
    authority:on_verify('dragon_entry', function(context, proof)
        if context.actor_id == actor_id and context.lifecycle_id == 1 and not reentered then
            reentered = true
            stale_entry_token = proof.operation_token
            current_lifecycle = 2
            request.lifecycle_id = current_lifecycle
        end
    end)

    local opened, error_code = dragon:open(request)
    equal(reentered, true, 'Dragon authority callback completes the lifecycle reentry fixture')
    equal(opened, false, 'Dragon authority reentry rejects the admitted old lifecycle')
    equal(error_code, 'stale-actor-lifecycle',
        'Dragon authority reentry has a stable lifecycle rejection')
    equal(dragon:get_by_actor(actor_id), nil,
        'stale authority admission does not occupy a Dragon slot')
    equal(dragon.used_authority_tokens[stale_entry_token], nil,
        'stale authority admission proof is not consumed')

    local reopened, replacement = dragon:open(request)
    truthy(reopened, 'replacement lifecycle can immediately enter Dragon after authority reentry')
    equal(replacement.session.owner_lifecycle_id, current_lifecycle,
        'authority reentry replacement owns the committed Dragon session')
    equal(replacement.session.slot_id, 1,
        'authority reentry leaves the first Dragon slot available for the replacement')
    equal(replacement.commands[2].lifecycle_id, current_lifecycle,
        'stale authority callback emits no old-lifecycle enter command')
end

do
    local authority = new_authority({ now = 20 })
    local ox = new_ox(authority)
    local nested_ok, nested
    local reentered = false
    authority:on_verify('ox_entry', function(context)
        if context.entry_request_id == 'raid:outer-reentrant' and not reentered then
            reentered = true
            nested_ok, nested = ox:open(ox_request('raid:nested-reentrant'))
        end
    end)

    local opened, error_code = ox:open(ox_request('raid:outer-reentrant'))
    equal(nested_ok, true, 'Ox authority callback can complete the nested active-session fixture')
    equal(opened, false, 'Ox entry rejects an active raid committed during authority verification')
    equal(error_code, 'ox-battlefield-already-active', 'Ox active-session CAS rejection is explicit')
    equal(ox:get_active_session().raid_instance_id, nested.session.raid_instance_id,
        'outer Ox entry cannot overwrite the nested active raid')
    equal(ox.used_authority_tokens['ox_entry:1'], nil,
        'stale outer Ox entry proof is not consumed')
end

do
    local authority = new_authority({ now = 30 })
    local dragon = new_dragon(authority)
    local opened_ok, opened = dragon:open(dragon_request(
        'HG_E_DRAGON_OLD_TIDE', 'dragon-reentrant-finish', 1
    ))
    truthy(opened_ok, 'Dragon finish reentry fixture opens')
    local event = dragon_event(opened.session)
    local nested_finish_ok, nested_finish
    local outer_finish_token
    local finishing = false
    authority:on_verify('dragon_finish', function(_, proof)
        if not finishing then
            finishing = true
            outer_finish_token = proof.operation_token
            nested_finish_ok, nested_finish = dragon:finish(event)
        end
    end)

    local finished, finish_error = dragon:finish(event)
    equal(nested_finish_ok, true, 'nested Dragon finish commits during the outer proof callback')
    equal(#nested_finish.commands, 1, 'nested Dragon finish emits exactly one cleanup command')
    equal(finished, false, 'outer Dragon finish rejects the reentrant state change')
    equal(finish_error, 'dragon-cleanup-pending', 'Dragon finish CAS rejection preserves the protocol error')
    equal(dragon:get_by_actor('dragon-reentrant-finish').state, 'cleanup_pending',
        'reentrant Dragon finish commits cleanup only once')
    equal(dragon.used_authority_tokens[outer_finish_token], nil,
        'stale outer Dragon finish proof is not consumed')

    local acknowledgement = dragon_ack(dragon:get_by_actor('dragon-reentrant-finish'))
    local nested_ack_ok, nested_ack
    local outer_ack_token
    local acknowledging = false
    authority:on_verify('dragon_cleanup_ack', function(_, proof)
        if not acknowledging then
            acknowledging = true
            outer_ack_token = proof.operation_token
            nested_ack_ok, nested_ack = dragon:acknowledge_cleanup(acknowledgement)
        end
    end)
    local acknowledged, ack_error = dragon:acknowledge_cleanup(acknowledgement)
    equal(nested_ack_ok, true, 'nested Dragon cleanup acknowledgement closes the session')
    equal(#nested_ack.commands, 1, 'nested Dragon acknowledgement emits one lock-release command')
    equal(acknowledged, false, 'outer Dragon acknowledgement rejects the reentrant closure')
    equal(ack_error, 'dragon-session-not-found',
        'Dragon acknowledgement CAS rejection matches a repeated closed-session callback')
    equal(dragon:get_by_actor('dragon-reentrant-finish'), nil,
        'reentrant Dragon acknowledgement releases the slot only once')
    equal(dragon.used_authority_tokens[outer_ack_token], nil,
        'stale outer Dragon acknowledgement proof is not consumed')
    equal(table_size(dragon.used_authority_tokens), 0,
        'reentrant Dragon acknowledgement leaves no replay-ledger residue')
end

do
    local authority = new_authority({ now = 40 })
    local ox = new_ox(authority)
    local opened_ok, opened = ox:open(ox_request('raid:reentrant-transitions'))
    truthy(opened_ok, 'Ox transition reentry fixture opens')

    local phase_identity = ox_event(opened.session)
    local nested_phase_ok, nested_phase
    local outer_phase_token
    local swapping = false
    authority:on_verify('ox_phase_swap', function(_, proof)
        if not swapping then
            swapping = true
            outer_phase_token = proof.operation_token
            nested_phase_ok, nested_phase = ox:swap_to_white_ox(phase_identity)
        end
    end)
    local swapped, swap_error = ox:swap_to_white_ox(phase_identity)
    equal(nested_phase_ok, true, 'nested Ox phase swap commits during the outer proof callback')
    equal(#nested_phase.commands, 1, 'nested Ox phase swap emits exactly one command')
    equal(swapped, false, 'outer Ox phase swap rejects the reentrant phase change')
    equal(swap_error, 'invalid-ox-phase-swap', 'Ox phase CAS rejection preserves the protocol error')
    equal(ox:get_active_session().phase_id, 'white_ox', 'reentrant Ox phase swap commits only once')
    equal(ox.used_authority_tokens[outer_phase_token], nil,
        'stale outer Ox phase proof is not consumed')

    local success_identity = ox_event(ox:get_active_session())
    local nested_success_ok, nested_success
    local outer_success_token
    local succeeding = false
    authority:on_verify('ox_success', function(_, proof)
        if not succeeding then
            succeeding = true
            outer_success_token = proof.operation_token
            nested_success_ok, nested_success = ox:succeed(success_identity)
        end
    end)
    local succeeded, success_error = ox:succeed(success_identity)
    equal(nested_success_ok, true, 'nested Ox success commits during the outer cleanup proof callback')
    equal(#nested_success.commands, 1, 'nested Ox success emits exactly one cleanup command')
    equal(succeeded, false, 'outer Ox success rejects the reentrant cleanup')
    equal(success_error, 'ox-cleanup-pending', 'Ox cleanup CAS rejection preserves the protocol error')
    equal(ox:get_active_session().state, 'cleanup_pending', 'reentrant Ox cleanup commits only once')
    equal(ox.used_authority_tokens[outer_success_token], nil,
        'stale outer Ox cleanup proof is not consumed')

    local acknowledgement = ox_ack(ox:get_active_session())
    local nested_ack_ok, nested_ack
    local outer_ack_token
    local acknowledging = false
    authority:on_verify('ox_cleanup_ack', function(_, proof)
        if not acknowledging then
            acknowledging = true
            outer_ack_token = proof.operation_token
            nested_ack_ok, nested_ack = ox:acknowledge_cleanup(acknowledgement)
        end
    end)
    local acknowledged, ack_error = ox:acknowledge_cleanup(acknowledgement)
    equal(nested_ack_ok, true, 'nested Ox cleanup acknowledgement closes the raid')
    equal(#nested_ack.commands, 1, 'nested Ox acknowledgement emits one lock-release command')
    equal(acknowledged, false, 'outer Ox acknowledgement rejects the reentrant closure')
    equal(ack_error, 'ox-battlefield-not-active',
        'Ox acknowledgement CAS rejection matches a repeated closed-session callback')
    equal(ox:get_active_session(), nil, 'reentrant Ox acknowledgement releases the raid only once')
    equal(ox.used_authority_tokens[outer_ack_token], nil,
        'stale outer Ox acknowledgement proof is not consumed')
    equal(table_size(ox.used_authority_tokens), 0,
        'reentrant Ox acknowledgement leaves no replay-ledger residue')
end

print('PASS: ' .. tests .. ' instance assertions')
