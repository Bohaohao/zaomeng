-- Public-Boss authority. Engine work is represented only by explicit commands.
local Contribution = require 'huaguoshan_contribution'

local M = {}
local Boss = {}
Boss.__index = Boss

local skill_event_kinds = {
    final_damage = true,
    actual_break = true,
    actual_protection = true,
    mechanic_resolved = true,
}

local function append(list, value)
    list[#list + 1] = value
end

local function sorted_ids(map)
    local ids = {}
    for id in pairs(map) do append(ids, id) end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    return ids
end

local function present(value)
    return value ~= nil and value ~= ''
end

local function missing_field(event, fields)
    for _, field in ipairs(fields) do
        if not present(event[field]) then return field end
    end
end

local function identity_origin(event, fields)
    local parts = {}
    for _, field in ipairs(fields) do
        local value = tostring(event[field])
        append(parts, tostring(#field) .. ':' .. field .. '=' .. tostring(#value) .. ':' .. value)
    end
    return table.concat(parts, '|')
end

local function empty_result()
    return { commands = {} }
end

local function add_command(result, command)
    append(result.commands, command)
end

local function append_commands(target, source)
    for _, command in ipairs((source and source.commands) or {}) do add_command(target, command) end
end

local function copy_fields(source, fields)
    local copy = {}
    for _, field in ipairs(fields) do copy[field] = source[field] end
    return copy
end

local function min(a, b)
    if a < b then return a end
    return b
end

local untrusted_authority_fields = {
    'authority_verified',
    'actor_alive',
    'within_interaction_area',
    'completed_reading',
    'reading_continuous',
    'boss_target_current',
    'interaction_unit_current',
    'anchor_in_safe_line',
    'anchor_outside_vortex_core',
}

local function untrusted_authority_field(payload)
    if type(payload) ~= 'table' then return nil end
    for _, field in ipairs(untrusted_authority_fields) do
        if payload[field] ~= nil then return field end
    end
    return nil
end

local function copy_table(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function authority_provider_valid(provider)
    return type(provider) == 'function'
        or (type(provider) == 'table' and type(provider.verify) == 'function')
end

function Boss:_authority_proof(operation, context, identity_fields)
    local provider = self.authority_provider
    if not authority_provider_valid(provider) then return nil, 'authority-provider-required' end

    local called, accepted, proof
    if type(provider) == 'function' then
        called, accepted, proof = pcall(provider, operation, context)
    else
        called, accepted, proof = pcall(provider.verify, provider, operation, context)
    end
    if not called then return nil, 'authority-provider-error' end
    if accepted ~= true or type(proof) ~= 'table' then
        return nil, 'authority-proof-rejected:' .. operation
    end
    for _, field in ipairs(identity_fields or {}) do
        if proof[field] ~= context[field] then
            return nil, 'authority-proof-mismatch:' .. field
        end
    end
    return proof
end

function M.new(encounter_key, encounter, options)
    assert(type(encounter) == 'table' and encounter.encounter_type == 'public_boss', 'public boss encounter required')
    options = options or {}
    assert(options.boss_instance_id ~= nil, 'boss_instance_id is required')
    assert(options.target_id ~= nil, 'target_id is required')
    assert(options.target_lifecycle_id ~= nil, 'target_lifecycle_id is required')
    local protection_threshold = options.protection_threshold or encounter.protection_threshold or 1
    assert(type(protection_threshold) == 'number' and protection_threshold > 0, 'positive protection_threshold is required')
    return setmetatable({
        encounter_key = encounter_key,
        encounter = encounter,
        boss_instance_id = options.boss_instance_id,
        target_id = options.target_id,
        target_lifecycle_id = options.target_lifecycle_id,
        phase_id = options.phase_id or 'phase-1',
        ledger = Contribution.new({ skill_validator = options.skill_validator }),
        authority_provider = options.authority_provider,
        source_unit_is_current = options.source_unit_is_current,
        protection_threshold = protection_threshold,
        participants = {},
        action_windows = {},
        active_action_window_id = nil,
        active_actions = {},
        next_action_token = 0,
        action_credit = {},
        mechanic_credit = {},
        water_chain = {},
        break_meter = 0,
        trace_pause_until = nil,
        submerged = false,
        frenzy = false,
        seen_phase_marker_events = {},
        phase_marker_occurrences = {},
        seen_action_close_events = {},
        seen_identity_events = {},
        phase_history = { [options.phase_id or 'phase-1'] = true },
        ended = false,
    }, Boss)
end

function Boss:_validate_envelope(event, current_lifecycle)
    if self.ended then return false, 'boss-already-ended' end
    if event.combat_scope ~= 'public' then return false, 'non-public-boss-event' end
    if event.boss_instance_id ~= self.boss_instance_id then return false, 'stale-boss-instance' end
    if event.phase_id ~= self.phase_id then return false, 'stale-boss-phase' end

    local target_id = event.kind == 'encounter_action_success' and event.boss_target_id or event.target_id
    local target_lifecycle_id = event.kind == 'encounter_action_success'
        and event.boss_target_lifecycle_id or event.target_lifecycle_id
    if target_id ~= self.target_id or target_lifecycle_id ~= self.target_lifecycle_id then
        return false, 'stale-boss-target'
    end
    if type(current_lifecycle) ~= 'function' then return false, 'current-lifecycle-required' end
    if current_lifecycle(event.actor_id, event.lifecycle_id) ~= true then
        return false, 'stale-actor-lifecycle'
    end
    if skill_event_kinds[event.kind] then
        if type(self.source_unit_is_current) ~= 'function' then
            return false, 'source-unit-lifecycle-provider-required'
        end
        if self.source_unit_is_current(
            event.actor_id, event.lifecycle_id,
            event.source_unit_id, event.source_unit_lifecycle_id
        ) ~= true then
            return false, 'stale-source-unit-lifecycle'
        end
    end
    return true
end

local contribution_authority_fields = {
    'kind', 'event_id', 'actor_id', 'lifecycle_id', 'team_id',
    'source_unit_id', 'source_unit_lifecycle_id', 'skill_key',
    'boss_instance_id', 'phase_id', 'target_id', 'target_lifecycle_id',
    'sync_tick', 'value', 'break_scope', 'protection_scope',
    'mechanic_key', 'mechanic_resolution',
}

function Boss:_authorize_contribution(event)
    local context = copy_fields(event, contribution_authority_fields)
    context.encounter_key = self.encounter_key
    local identity_fields = copy_table(contribution_authority_fields)
    append(identity_fields, 'encounter_key')
    local proof, error_code = self:_authority_proof(
        'public_boss_contribution', context, identity_fields)
    if not proof then return nil, error_code end
    if proof.actor_alive ~= true or proof.boss_target_current ~= true then
        return nil, 'contribution-not-authority-verified'
    end

    local canonical = copy_table(event)
    if canonical.kind == 'mechanic_resolved' then canonical.authority_verified = true end
    return canonical
end

function Boss:_participant_plan(event)
    local participant = self.participants[event.actor_id]
    return {
        participant = participant,
        upgrade_lifecycle = participant ~= nil and participant.lifecycle_id ~= event.lifecycle_id,
        create = participant == nil,
    }
end

function Boss:_commit_participant(plan, event)
    local participant = plan.participant
    if plan.create then
        participant = {
            actor_id = event.actor_id,
            lifecycle_id = event.lifecycle_id,
            team_id = event.team_id,
            damage = 0,
            break_value = 0,
            protection = 0,
            action = false,
            break_qualified = false,
            protection_qualified = false,
        }
        self.participants[event.actor_id] = participant
    elseif plan.upgrade_lifecycle then
        participant.lifecycle_id = event.lifecycle_id
    end
    if event.team_id ~= nil then participant.team_id = event.team_id end
    return participant
end

function Boss:_validate_for_participant(event, current_lifecycle)
    local untrusted = untrusted_authority_field(event)
    if untrusted then return nil, 'untrusted-authority-field:' .. untrusted end
    local ok, error_code = self:_validate_envelope(event, current_lifecycle)
    if not ok then return nil, error_code end
    local canonical
    canonical, error_code = self:_authorize_contribution(event)
    if not canonical then return nil, error_code end
    ok, error_code = Contribution.validate(canonical, {
        skill_validator = self.ledger.skill_validator,
        offline_test_mode = self.ledger.offline_test_mode,
    })
    if not ok then return nil, error_code end
    return self:_participant_plan(canonical), canonical
end

function Boss:_prepare_event(event, current_lifecycle)
    local participant_plan, canonical_or_error = self:_validate_for_participant(event, current_lifecycle)
    local error_code = canonical_or_error
    if not participant_plan then return nil, error_code end
    local canonical = canonical_or_error
    local accepted, ticket = self.ledger:can_accept(canonical)
    if not accepted then return nil, ticket end
    return { participant_plan = participant_plan, ticket = ticket, canonical = canonical }
end

function Boss:_commit_event(_, prepared)
    self.ledger:commit(prepared.canonical, prepared.ticket)
    return self:_commit_participant(prepared.participant_plan, prepared.canonical)
end

function Boss:record_damage(event, current_lifecycle)
    if type(event) ~= 'table' or event.kind ~= 'final_damage' then return false, 'expected-final-damage' end
    local prepared, error_code = self:_prepare_event(event, current_lifecycle)
    if not prepared then return false, error_code end
    local participant = self:_commit_event(event, prepared)
    participant.damage = participant.damage + event.value
    return true, empty_result()
end

function Boss:record_break(event, current_lifecycle)
    if type(event) ~= 'table' or event.kind ~= 'actual_break' then return false, 'expected-actual-break' end
    local prepared, error_code = self:_prepare_event(event, current_lifecycle)
    if not prepared then return false, error_code end
    local participant = self:_commit_event(event, prepared)
    participant.break_value = participant.break_value + event.value
    self.break_meter = self.break_meter + event.value

    local result = empty_result()
    local threshold = self.encounter.break_profile.threshold
    while self.break_meter >= threshold do
        self.break_meter = self.break_meter - threshold
        participant.break_qualified = true
        add_command(result, {
            type = 'boss_break_triggered',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            actor_id = event.actor_id,
            threshold = threshold,
            target_scope = 'explicit',
            target_id = self.target_id,
        })
    end
    return true, result
end

function Boss:record_protection(event, current_lifecycle)
    if type(event) ~= 'table' or event.kind ~= 'actual_protection' then
        return false, 'expected-actual-protection'
    end
    local prepared, error_code = self:_prepare_event(event, current_lifecycle)
    if not prepared then return false, error_code end
    local participant = self:_commit_event(event, prepared)
    participant.protection = participant.protection + event.value

    local result = empty_result()
    if not participant.protection_qualified and participant.protection >= self.protection_threshold then
        participant.protection_qualified = true
        add_command(result, {
            type = 'boss_protection_threshold_reached',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            actor_id = event.actor_id,
            threshold = self.protection_threshold,
            target_scope = 'explicit',
            target_id = self.target_id,
        })
    end
    return true, result
end

local action_window_fields = {
    'window_id', 'mechanic_occurrence_id', 'encounter_action_key', 'combat_scope',
    'boss_instance_id', 'phase_id', 'boss_target_id', 'boss_target_lifecycle_id',
    'interaction_unit_id', 'interaction_unit_lifecycle_id', 'open_tick', 'close_tick',
    'reading_duration_ticks', 'reservation_retention_ticks',
}

local function action_window_origin(window)
    return table.concat({
        tostring(window.boss_instance_id), tostring(window.phase_id),
        tostring(window.boss_target_id), tostring(window.boss_target_lifecycle_id),
        tostring(window.mechanic_occurrence_id), tostring(window.encounter_action_key),
        tostring(window.interaction_unit_id), tostring(window.interaction_unit_lifecycle_id),
        tostring(window.open_tick), tostring(window.close_tick),
        tostring(window.reading_duration_ticks), tostring(window.reservation_retention_ticks),
    }, ':')
end

function Boss:_validate_action_window(window)
    if self.ended then return false, 'boss-already-ended' end
    if type(window) ~= 'table' then return false, 'invalid-action-window' end
    for _, field in ipairs(action_window_fields) do
        if not present(window[field]) then return false, 'missing-action-window-field:' .. field end
    end
    if window.combat_scope ~= 'public'
        or window.session_instance_id ~= nil or window.session_epoch ~= nil then
        return false, 'invalid-action-window-scope'
    end
    if window.boss_instance_id ~= self.boss_instance_id then return false, 'stale-boss-instance' end
    if window.phase_id ~= self.phase_id then return false, 'stale-boss-phase' end
    if window.boss_target_id ~= self.target_id
        or window.boss_target_lifecycle_id ~= self.target_lifecycle_id then
        return false, 'stale-boss-target'
    end
    local action = self.encounter.action
    if not action or window.encounter_action_key ~= action.key then
        return false, 'invalid-encounter-action'
    end
    if type(action.read_seconds) ~= 'number' or action.read_seconds <= 0
        or type(action.window_seconds) ~= 'number' or action.window_seconds <= 0
        or action.read_seconds > action.window_seconds then
        return false, 'invalid-encounter-action-timing'
    end
    local expected_window_id = table.concat({
        tostring(self.boss_instance_id), tostring(self.phase_id),
        tostring(window.mechanic_occurrence_id), tostring(window.encounter_action_key),
    }, ':')
    if window.window_id ~= expected_window_id then return false, 'invalid-action-window-id' end
    if type(window.open_tick) ~= 'number' or type(window.close_tick) ~= 'number'
        or window.close_tick <= window.open_tick then
        return false, 'invalid-action-window-range'
    end
    if type(window.reading_duration_ticks) ~= 'number' or window.reading_duration_ticks <= 0 then
        return false, 'invalid-action-reading-duration'
    end
    if window.reading_duration_ticks ~= action.read_seconds then
        return false, 'action-window-reading-duration-mismatch'
    end
    if window.close_tick ~= window.open_tick + action.window_seconds then
        return false, 'action-window-duration-mismatch'
    end
    if type(window.reservation_retention_ticks) ~= 'number'
        or window.reservation_retention_ticks < window.reading_duration_ticks then
        return false, 'invalid-action-reservation-retention'
    end
    if window.open_tick + window.reading_duration_ticks > window.close_tick then
        return false, 'action-window-too-short'
    end
    return true
end

local function action_candidate_less(left, right)
    if left.completed_tick ~= right.completed_tick then
        return left.completed_tick < right.completed_tick
    end
    if tostring(left.event.actor_id) ~= tostring(right.event.actor_id) then
        return tostring(left.event.actor_id) < tostring(right.event.actor_id)
    end
    return tostring(left.event.event_id) < tostring(right.event.event_id)
end

function Boss:_settle_action_completions(window, watermark_tick, result)
    if type(watermark_tick) ~= 'number' then return false, 'trusted-action-watermark-required' end
    if watermark_tick < window.settled_watermark then return false, 'action-watermark-regressed' end

    local candidates = {}
    for _, candidate in pairs(window.pending_completions) do
        if candidate.completed_tick <= watermark_tick then append(candidates, candidate) end
    end
    table.sort(candidates, action_candidate_less)

    local prepared = {}
    local primary_exists = window.primary_actor_id ~= nil
    for _, candidate in ipairs(candidates) do
        local canonical = copy_table(candidate.event)
        canonical.completed_tick = candidate.completed_tick
        canonical.completion_mode = primary_exists and 'assist' or 'primary'
        local accepted, ticket = self.ledger:can_accept(canonical)
        if not accepted then return false, ticket end
        append(prepared, {
            candidate = candidate,
            canonical = canonical,
            ticket = ticket,
        })
        primary_exists = true
    end

    if #prepared > 0 then result.action_results = result.action_results or {} end
    for _, item in ipairs(prepared) do
        local candidate = item.candidate
        local event = item.canonical
        self.ledger:commit(event, item.ticket)
        local participant = self:_commit_participant(self:_participant_plan(event), event)
        window.pending_completions[event.event_id] = nil
        window.pending_by_actor[event.actor_id] = nil
        window.success_by_actor[event.actor_id] = event.event_id

        if event.completion_mode == 'primary' then
            window.primary_actor_id = event.actor_id
            add_command(result, {
                type = 'resolve_encounter_action_primary',
                encounter_key = self.encounter_key,
                boss_instance_id = self.boss_instance_id,
                phase_id = self.phase_id,
                window_id = event.window_id,
                mechanic_occurrence_id = event.mechanic_occurrence_id,
                encounter_action_key = event.encounter_action_key,
                actor_id = event.actor_id,
                completed_tick = event.completed_tick,
            })
        end

        local contribution_counted = not self.action_credit[event.actor_id]
        if contribution_counted then
            self.action_credit[event.actor_id] = true
            participant.action = true
        end
        append(result.action_results, {
            event_id = event.event_id,
            actor_id = event.actor_id,
            completed_tick = event.completed_tick,
            completion_mode = event.completion_mode,
            contribution_counted = contribution_counted,
        })
        add_command(result, {
            type = 'record_encounter_action_success',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            window_id = event.window_id,
            mechanic_occurrence_id = event.mechanic_occurrence_id,
            actor_id = event.actor_id,
            completed_tick = event.completed_tick,
            completion_mode = event.completion_mode,
            event_id = event.event_id,
        })
        if self.encounter_key == 'HG_E_JIAO_KING' then
            self:_clear_water_chain(event.actor_id, event.lifecycle_id, 'drain_tide_eye', result)
        end
    end

    window.settled_watermark = watermark_tick
    return true
end

function Boss:_close_action_window(window, reason, result, watermark_tick)
    if not window or window.state ~= 'open' then return true end
    for _, candidate in pairs(window.pending_completions) do
        if candidate.completed_tick > watermark_tick then
            return false, 'action-completion-after-close-watermark'
        end
    end
    local settled, settle_error = self:_settle_action_completions(window, watermark_tick, result)
    if not settled then return false, settle_error end
    if next(window.pending_completions) ~= nil then return false, 'action-completion-not-settled' end
    local cancelled = 0
    for _, actor_id in ipairs(sorted_ids(self.active_actions)) do
        local reservation = self.active_actions[actor_id]
        if reservation.window_id == window.window_id then
            self.active_actions[actor_id] = nil
            cancelled = cancelled + 1
        end
    end
    if cancelled > 0 then
        add_command(result, {
            type = 'cancel_encounter_action_reservations',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = window.phase_id,
            window_id = window.window_id,
            count = cancelled,
            reason = reason or 'window_closed',
        })
    end
    window.state = 'closed'
    window.close_reason = reason or 'window_closed'
    if self.active_action_window_id == window.window_id then self.active_action_window_id = nil end
    add_command(result, {
        type = 'close_encounter_action_window',
        encounter_key = self.encounter_key,
        boss_instance_id = self.boss_instance_id,
        phase_id = window.phase_id,
        window_id = window.window_id,
        reason = window.close_reason,
    })
    return true
end

function Boss:_open_action_window(window, watermark_tick)
    local ok, error_code = self:_validate_action_window(window)
    if not ok then return false, error_code end
    local old = self.action_windows[window.window_id]
    if old then
        if old.origin ~= action_window_origin(window) then return false, 'action-window-origin-conflict' end
        return false, 'duplicate-action-window'
    end

    local result = empty_result()
    local active = self.action_windows[self.active_action_window_id]
    if active then
        local closed, close_error = self:_close_action_window(active, 'superseded', result, watermark_tick)
        if not closed then return false, close_error end
    end

    local stored = copy_fields(window, action_window_fields)
    stored.origin = action_window_origin(window)
    stored.state = 'open'
    stored.primary_actor_id = nil
    stored.success_by_actor = {}
    stored.pending_completions = {}
    stored.pending_by_actor = {}
    stored.completion_origin_by_event = {}
    stored.settled_watermark = stored.open_tick - 1
    self.action_windows[stored.window_id] = stored
    self.active_action_window_id = stored.window_id
    add_command(result, {
        type = 'open_encounter_action_window',
        encounter_key = self.encounter_key,
        boss_instance_id = stored.boss_instance_id,
        phase_id = stored.phase_id,
        window_id = stored.window_id,
        mechanic_occurrence_id = stored.mechanic_occurrence_id,
        encounter_action_key = stored.encounter_action_key,
        interaction_unit_id = stored.interaction_unit_id,
        interaction_unit_lifecycle_id = stored.interaction_unit_lifecycle_id,
        open_tick = stored.open_tick,
        close_tick = stored.close_tick,
    })
    return true, result
end

local action_close_fields = {
    'kind', 'event_id', 'boss_instance_id', 'phase_id', 'window_id', 'reason',
}

function Boss:close_action_window(event)
    if type(event) ~= 'table' or event.kind ~= 'action_window_close' then
        return false, 'invalid-action-window-close-event'
    end
    local untrusted = untrusted_authority_field(event)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    local field = missing_field(event, action_close_fields)
    if field then return false, 'missing-action-window-close-field:' .. field end

    local origin = identity_origin(event, action_close_fields)
    local old_origin = self.seen_action_close_events[event.event_id]
    if old_origin then
        if old_origin ~= origin then return false, 'action-window-close-origin-conflict' end
        return false, 'duplicate-action-window-close'
    end
    if event.boss_instance_id ~= self.boss_instance_id then return false, 'stale-boss-instance' end
    if event.phase_id ~= self.phase_id then return false, 'stale-boss-phase' end
    local window = self.action_windows[event.window_id]
    if not window or window.state ~= 'open' then return false, 'action-window-not-open' end

    local context = copy_fields(event, action_close_fields)
    context.encounter_key = self.encounter_key
    local identity_fields = copy_table(action_close_fields)
    append(identity_fields, 'encounter_key')
    local proof, proof_error = self:_authority_proof(
        'public_boss_action_window_close', context, identity_fields)
    if not proof then return false, proof_error end
    if type(proof.watermark_tick) ~= 'number' then return false, 'trusted-action-watermark-required' end

    local result = empty_result()
    local closed, close_error = self:_close_action_window(window, event.reason, result, proof.watermark_tick)
    if not closed then return false, close_error end
    self.seen_action_close_events[event.event_id] = origin
    return true, result
end

function Boss:_expire_action_reservations(now, result)
    for _, actor_id in ipairs(sorted_ids(self.active_actions)) do
        local reservation = self.active_actions[actor_id]
        if now > reservation.expires_tick then
            self.active_actions[actor_id] = nil
            add_command(result, {
                type = 'cancel_encounter_action_reservation',
                encounter_key = self.encounter_key,
                boss_instance_id = self.boss_instance_id,
                phase_id = self.phase_id,
                window_id = reservation.window_id,
                actor_id = actor_id,
                lifecycle_id = reservation.lifecycle_id,
                action_token = reservation.token,
                reason = 'reading_expired',
            })
        end
    end
end

local action_begin_authority_fields = {
    'encounter_key', 'boss_instance_id', 'phase_id', 'boss_target_id',
    'boss_target_lifecycle_id', 'window_id', 'encounter_action_key',
    'interaction_unit_id', 'interaction_unit_lifecycle_id', 'actor_id', 'lifecycle_id',
}

function Boss:begin_action(request, current_lifecycle)
    if self.ended then return false, 'boss-already-ended' end
    if type(request) ~= 'table' then return false, 'action-request-required' end
    local untrusted = untrusted_authority_field(request)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    if request.session_instance_id ~= nil or request.session_epoch ~= nil then
        return false, 'public-event-carries-session'
    end
    for _, field in ipairs({
        'actor_id', 'lifecycle_id', 'window_id', 'encounter_action_key',
        'interaction_unit_id', 'interaction_unit_lifecycle_id',
    }) do
        if not present(request[field]) then return false, 'missing-action-request-field:' .. field end
    end

    local window = self.action_windows[request.window_id]
    if not window or window.state ~= 'open' or self.active_action_window_id ~= request.window_id then
        return false, 'action-window-not-open'
    end
    if request.encounter_action_key ~= window.encounter_action_key then return false, 'invalid-encounter-action' end
    if request.interaction_unit_id ~= window.interaction_unit_id
        or request.interaction_unit_lifecycle_id ~= window.interaction_unit_lifecycle_id then
        return false, 'stale-action-interaction-unit'
    end
    if type(current_lifecycle) ~= 'function' then return false, 'current-lifecycle-required' end
    if current_lifecycle(request.actor_id, request.lifecycle_id) ~= true then
        return false, 'stale-actor-lifecycle'
    end

    local context = {
        encounter_key = self.encounter_key,
        boss_instance_id = self.boss_instance_id,
        phase_id = self.phase_id,
        boss_target_id = self.target_id,
        boss_target_lifecycle_id = self.target_lifecycle_id,
        window_id = window.window_id,
        encounter_action_key = window.encounter_action_key,
        interaction_unit_id = window.interaction_unit_id,
        interaction_unit_lifecycle_id = window.interaction_unit_lifecycle_id,
        actor_id = request.actor_id,
        lifecycle_id = request.lifecycle_id,
    }
    local proof, proof_error = self:_authority_proof(
        'public_boss_action_begin', context, action_begin_authority_fields)
    if not proof then return false, proof_error end
    if proof.actor_alive ~= true or proof.within_interaction_area ~= true
        or proof.boss_target_current ~= true or proof.interaction_unit_current ~= true then
        return false, 'action-not-authority-verified'
    end
    local now = proof.observed_tick
    if type(now) ~= 'number' then return false, 'trusted-action-tick-required' end
    if now < window.open_tick or now > window.close_tick then return false, 'action-window-expired' end
    local action = self.encounter.action
    if action.safe_line_required
        and (proof.anchor_in_safe_line ~= true or proof.anchor_outside_vortex_core ~= true) then
        return false, 'invalid-vortex-anchor-position'
    end
    if now + window.reading_duration_ticks > window.close_tick then return false, 'action-window-too-late' end

    if window.success_by_actor[request.actor_id] then return false, 'action-already-completed' end
    if window.pending_by_actor[request.actor_id] then return false, 'action-completion-pending' end
    if self.active_actions[request.actor_id] then return false, 'action-already-reserved' end
    local active_count = 0
    for _, reservation in pairs(self.active_actions) do
        if reservation.window_id == window.window_id then active_count = active_count + 1 end
    end
    if active_count >= action.max_concurrent then return false, 'action-concurrency-full' end

    self.next_action_token = self.next_action_token + 1
    local token = table.concat({
        tostring(window.window_id), tostring(request.actor_id),
        tostring(request.lifecycle_id), tostring(self.next_action_token),
    }, ':')
    local ready_tick = now + window.reading_duration_ticks
    local expires_tick = min(window.close_tick, now + window.reservation_retention_ticks)
    self.active_actions[request.actor_id] = {
        token = token,
        actor_id = request.actor_id,
        lifecycle_id = request.lifecycle_id,
        window_id = window.window_id,
        action_key = window.encounter_action_key,
        interaction_unit_id = window.interaction_unit_id,
        interaction_unit_lifecycle_id = window.interaction_unit_lifecycle_id,
        began_at = now,
        ready_tick = ready_tick,
        expires_tick = expires_tick,
    }
    return true, {
        action_token = token,
        action_key = window.encounter_action_key,
        window_id = window.window_id,
        mechanic_occurrence_id = window.mechanic_occurrence_id,
        ready_tick = ready_tick,
        expires_tick = expires_tick,
        commands = {},
    }
end

function Boss:cancel_action(actor_id, lifecycle_id, token)
    local reservation = self.active_actions[actor_id]
    if not reservation then return false, 'action-not-reserved' end
    if reservation.lifecycle_id ~= lifecycle_id or reservation.token ~= token then
        return false, 'stale-action-reservation'
    end
    self.active_actions[actor_id] = nil
    return true
end

local action_completion_fields = {
    'kind', 'event_id', 'actor_id', 'lifecycle_id', 'team_id', 'combat_scope',
    'boss_instance_id', 'phase_id', 'window_id', 'mechanic_occurrence_id',
    'encounter_action_key', 'interaction_unit_id', 'interaction_unit_lifecycle_id',
    'boss_target_id', 'boss_target_lifecycle_id', 'action_token',
}

local function action_completion_origin(event)
    return identity_origin(event, action_completion_fields)
end

function Boss:_prepare_action_candidate(event, current_lifecycle, batch_event_ids, batch_actors)
    local untrusted = untrusted_authority_field(event)
    if untrusted then return nil, 'untrusted-authority-field:' .. untrusted end
    if event.completed_tick ~= nil or event.sync_tick ~= nil then
        return nil, 'caller-action-timing-forbidden'
    end
    if event.completion_mode ~= nil then return nil, 'caller-completion-mode-forbidden' end
    if event.session_instance_id ~= nil or event.session_epoch ~= nil then
        return nil, 'public-event-carries-session'
    end
    local field = missing_field(event, {
        'event_id', 'actor_id', 'lifecycle_id', 'combat_scope', 'boss_instance_id', 'phase_id',
        'window_id', 'mechanic_occurrence_id', 'encounter_action_key', 'interaction_unit_id',
        'interaction_unit_lifecycle_id', 'boss_target_id', 'boss_target_lifecycle_id', 'action_token',
    })
    if field then return nil, 'missing-action-completion-field:' .. field end
    local envelope_ok, envelope_error = self:_validate_envelope(event, current_lifecycle)
    if not envelope_ok then return nil, envelope_error end

    local window = self.action_windows[event.window_id]
    if not window or window.state ~= 'open' or self.active_action_window_id ~= event.window_id then
        return nil, 'action-window-not-open'
    end
    if event.mechanic_occurrence_id ~= window.mechanic_occurrence_id
        or event.encounter_action_key ~= window.encounter_action_key then
        return nil, 'stale-action-window'
    end
    if event.interaction_unit_id ~= window.interaction_unit_id
        or event.interaction_unit_lifecycle_id ~= window.interaction_unit_lifecycle_id then
        return nil, 'stale-action-interaction-unit'
    end
    local expected_event_id = window.window_id .. ':' .. tostring(event.actor_id)
    if event.event_id ~= expected_event_id then return nil, 'invalid-action-event-id' end
    if window.success_by_actor[event.actor_id] then return nil, 'duplicate-action-success' end

    local claim_origin = action_completion_origin(event)
    local old_origin = window.completion_origin_by_event[event.event_id]
    if old_origin then
        if old_origin.claim_origin ~= claim_origin then return nil, 'action-completion-origin-conflict' end
        return nil, 'duplicate-action-completion'
    end
    if window.pending_by_actor[event.actor_id] then return nil, 'duplicate-action-success' end

    local reservation = self.active_actions[event.actor_id]
    if not reservation then return nil, 'action-not-reserved' end
    if reservation.lifecycle_id ~= event.lifecycle_id or reservation.token ~= event.action_token
        or reservation.window_id ~= event.window_id then
        return nil, 'stale-action-reservation'
    end
    if batch_event_ids[event.event_id] then return nil, 'duplicate-encounter-event' end
    if batch_actors[event.actor_id] then return nil, 'duplicate-action-success' end

    local context = copy_fields(event, action_completion_fields)
    context.encounter_key = self.encounter_key
    context.reading_started_tick = reservation.began_at
    local identity_fields = copy_table(action_completion_fields)
    append(identity_fields, 'encounter_key')
    append(identity_fields, 'reading_started_tick')
    local proof, proof_error = self:_authority_proof(
        'public_boss_action_complete', context, identity_fields)
    if not proof then return nil, proof_error end
    if proof.actor_alive ~= true or proof.within_interaction_area ~= true
        or proof.completed_reading ~= true or proof.reading_continuous ~= true
        or proof.boss_target_current ~= true or proof.interaction_unit_current ~= true then
        return nil, 'action-not-authority-verified'
    end
    local completed_tick = proof.completed_tick
    if type(completed_tick) ~= 'number' then return nil, 'trusted-action-completed-tick-required' end
    if completed_tick < window.open_tick or completed_tick > window.close_tick then
        return nil, 'action-window-expired'
    end
    if completed_tick < reservation.ready_tick then return nil, 'action-reading-incomplete' end
    if completed_tick > reservation.expires_tick then return nil, 'action-reading-expired' end
    if completed_tick <= window.settled_watermark then return nil, 'action-completion-behind-watermark' end

    batch_event_ids[event.event_id] = true
    batch_actors[event.actor_id] = true
    return {
        event = copy_table(event),
        window = window,
        reservation = reservation,
        completed_tick = completed_tick,
        claim_origin = claim_origin,
    }
end

function Boss:_clear_water_chain(actor_id, lifecycle_id, resolution, result)
    local chain = self.water_chain[actor_id]
    if not chain or not chain.active then return false, 'water-chain-not-active' end
    if chain.lifecycle_id ~= lifecycle_id then return false, 'stale-water-chain-lifecycle' end
    chain.active = false
    chain.resolution = resolution
    add_command(result, {
        type = 'remove_mechanic',
        encounter_key = self.encounter_key,
        mechanic_key = 'HG_BOSS_WATER_CHAIN',
        target_scope = 'explicit',
        target_id = actor_id,
        target_lifecycle_id = lifecycle_id,
        source_boss_instance_id = self.boss_instance_id,
        phase_id = self.phase_id,
    })
    return true
end

function Boss:complete_actions(events, current_lifecycle)
    if type(events) ~= 'table' or #events == 0 then return false, 'action-events-required' end
    local candidates = {}
    local batch_event_ids, batch_actors = {}, {}
    local batch_window = nil
    for _, event in ipairs(events) do
        if type(event) ~= 'table' or event.kind ~= 'encounter_action_success' then
            return false, 'expected-encounter-action-success'
        end
        local candidate, error_code = self:_prepare_action_candidate(
            event, current_lifecycle, batch_event_ids, batch_actors)
        if not candidate then return false, error_code end
        if batch_window and batch_window ~= candidate.window then return false, 'mixed-action-window-batch' end
        batch_window = candidate.window
        append(candidates, candidate)
    end

    local result = empty_result()
    result.queued_actions = {}
    for _, candidate in ipairs(candidates) do
        local event = candidate.event
        if self.active_actions[event.actor_id] == candidate.reservation then
            self.active_actions[event.actor_id] = nil
        end
        candidate.window.pending_completions[event.event_id] = candidate
        candidate.window.pending_by_actor[event.actor_id] = event.event_id
        candidate.window.completion_origin_by_event[event.event_id] = {
            claim_origin = candidate.claim_origin,
            completed_tick = candidate.completed_tick,
        }
        append(result.queued_actions, {
            event_id = event.event_id,
            actor_id = event.actor_id,
            completed_tick = candidate.completed_tick,
        })
    end
    if #result.queued_actions == 1 then
        result.queued = true
        result.event_id = result.queued_actions[1].event_id
        result.completed_tick = result.queued_actions[1].completed_tick
    end
    return true, result
end

function Boss:complete_action(event, current_lifecycle)
    if type(event) ~= 'table' or event.kind ~= 'encounter_action_success' then
        return false, 'expected-encounter-action-success'
    end
    return self:complete_actions({ event }, current_lifecycle)
end

local function participant_engaged(participant)
    return participant.damage > 0 or participant.break_value > 0 or participant.protection > 0
        or participant.action or participant.break_qualified or participant.protection_qualified
end

function Boss:apply_water_chain(current_lifecycle)
    if self.encounter_key ~= 'HG_E_JIAO_KING' or not self.submerged then
        return false, 'water-chain-not-available'
    end
    if type(current_lifecycle) ~= 'function' then return false, 'current-lifecycle-required' end
    local context = {
        encounter_key = self.encounter_key,
        boss_instance_id = self.boss_instance_id,
        phase_id = self.phase_id,
        boss_target_id = self.target_id,
        boss_target_lifecycle_id = self.target_lifecycle_id,
    }
    local proof, proof_error = self:_authority_proof('public_boss_apply_water_chain', context, {
        'encounter_key', 'boss_instance_id', 'phase_id',
        'boss_target_id', 'boss_target_lifecycle_id',
    })
    if not proof then return false, proof_error end
    if proof.boss_target_current ~= true then return false, 'boss-target-not-authority-verified' end
    local result = empty_result()
    for _, actor_id in ipairs(sorted_ids(self.participants)) do
        local participant = self.participants[actor_id]
        if participant_engaged(participant)
            and current_lifecycle(actor_id, participant.lifecycle_id) == true
            and (not self.water_chain[actor_id] or not self.water_chain[actor_id].active
                or self.water_chain[actor_id].lifecycle_id ~= participant.lifecycle_id) then
            self.water_chain[actor_id] = { active = true, lifecycle_id = participant.lifecycle_id }
            add_command(result, {
                type = 'apply_mechanic',
                encounter_key = self.encounter_key,
                mechanic_key = 'HG_BOSS_WATER_CHAIN',
                target_scope = 'explicit',
                target_id = actor_id,
                target_lifecycle_id = participant.lifecycle_id,
                source_boss_instance_id = self.boss_instance_id,
                phase_id = self.phase_id,
            })
        end
    end
    return true, result
end

function Boss:resolve_water_chain(event, current_lifecycle)
    if self.encounter_key ~= 'HG_E_JIAO_KING' then return false, 'water-chain-not-available' end
    if type(event) ~= 'table' or event.kind ~= 'mechanic_resolved'
        or event.mechanic_key ~= 'HG_BOSS_WATER_CHAIN' then
        return false, 'expected-water-chain-resolution'
    end
    local mechanic = self.encounter.mechanic
    if not mechanic.resolutions[event.mechanic_resolution] then return false, 'invalid-water-chain-resolution' end

    local participant_plan, canonical_or_error = self:_validate_for_participant(event, current_lifecycle)
    if not participant_plan then return false, canonical_or_error end
    local canonical = canonical_or_error
    local chain = self.water_chain[event.actor_id]
    if not chain or not chain.active then return false, 'water-chain-not-active' end
    if chain.lifecycle_id ~= event.lifecycle_id then return false, 'stale-water-chain-lifecycle' end
    local accepted, ticket = self.ledger:can_accept(canonical)
    if not accepted then return false, ticket end

    self.ledger:commit(canonical, ticket)
    local participant = self:_commit_participant(participant_plan, canonical)
    local result = empty_result()
    self:_clear_water_chain(event.actor_id, event.lifecycle_id, event.mechanic_resolution, result)
    if not self.mechanic_credit[event.actor_id] then
        self.mechanic_credit[event.actor_id] = true
        self.action_credit[event.actor_id] = true
        participant.action = true
        result.contribution_counted = true
    else
        result.contribution_counted = false
    end
    return true, result
end

local function phase_marker_origin(event)
    return table.concat({
        tostring(event.boss_instance_id), tostring(event.phase_id), tostring(event.marker),
        tostring(event.marker_occurrence_id), tostring(event.boss_target_id),
        tostring(event.boss_target_lifecycle_id), tostring(event.sync_tick),
        tostring(event.action_window and action_window_origin(event.action_window) or ''),
    }, ':')
end

function Boss:_validate_phase_marker(event)
    if self.ended then return false, 'boss-already-ended' end
    if type(event) ~= 'table' or event.kind ~= 'phase_marker' then return false, 'invalid-phase-marker-event' end
    local untrusted = untrusted_authority_field(event)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    for _, field in ipairs({
        'event_id', 'marker_occurrence_id', 'marker', 'combat_scope', 'boss_instance_id',
        'phase_id', 'boss_target_id', 'boss_target_lifecycle_id', 'sync_tick',
    }) do
        if not present(event[field]) then return false, 'missing-phase-marker-field:' .. field end
    end
    if event.combat_scope ~= 'public'
        or event.session_instance_id ~= nil or event.session_epoch ~= nil then
        return false, 'invalid-phase-marker-scope'
    end
    if event.boss_instance_id ~= self.boss_instance_id then return false, 'stale-boss-instance' end
    if event.phase_id ~= self.phase_id then return false, 'stale-boss-phase' end
    if event.boss_target_id ~= self.target_id
        or event.boss_target_lifecycle_id ~= self.target_lifecycle_id then
        return false, 'stale-boss-target'
    end

    local action_required = (event.marker == 'submerge' and self.encounter_key == 'HG_E_JIAO_KING')
        or (event.marker == 'clone_end' and self.encounter_key == 'HG_E_MACAQUE_KING')
        or (event.marker == 'vortex_warning' and self.encounter_key == 'HG_E_SHARK_KING')
    local valid_without_action = (event.marker == 'clone_window' and self.encounter_key == 'HG_E_MACAQUE_KING')
        or (event.marker == 'frenzy'
            and (self.encounter_key == 'HG_E_MACAQUE_KING' or self.encounter_key == 'HG_E_SHARK_KING'))
    if not action_required and not valid_without_action then return false, 'invalid-phase-marker' end
    if action_required then
        if type(event.action_window) ~= 'table' then return false, 'phase-marker-action-window-required' end
        if event.action_window.mechanic_occurrence_id ~= event.marker_occurrence_id then
            return false, 'phase-marker-occurrence-mismatch'
        end
        if event.action_window.open_tick ~= event.sync_tick then
            return false, 'phase-marker-window-start-mismatch'
        end
        local window_ok, window_error = self:_validate_action_window(event.action_window)
        if not window_ok then return false, window_error end
    elseif event.action_window ~= nil then
        return false, 'unexpected-phase-marker-action-window'
    end
    return true, action_required
end

function Boss:phase_marker(event)
    local ok, action_required = self:_validate_phase_marker(event)
    if not ok then return false, action_required end
    local origin = phase_marker_origin(event)
    local old_origin = self.seen_phase_marker_events[event.event_id]
    if old_origin then
        if old_origin ~= origin then return false, 'phase-marker-origin-conflict' end
        return false, 'duplicate-phase-marker'
    end
    local occurrence_key = table.concat({
        tostring(event.phase_id), tostring(event.marker), tostring(event.marker_occurrence_id),
    }, ':')
    if self.phase_marker_occurrences[occurrence_key] then return false, 'duplicate-phase-marker-occurrence' end

    local context = {
        encounter_key = self.encounter_key,
        kind = event.kind,
        event_id = event.event_id,
        marker_occurrence_id = event.marker_occurrence_id,
        marker = event.marker,
        combat_scope = event.combat_scope,
        boss_instance_id = event.boss_instance_id,
        phase_id = event.phase_id,
        boss_target_id = event.boss_target_id,
        boss_target_lifecycle_id = event.boss_target_lifecycle_id,
        sync_tick = event.sync_tick,
        action_window_origin = event.action_window and action_window_origin(event.action_window) or '',
    }
    local proof, proof_error = self:_authority_proof('public_boss_phase_marker', context, {
        'encounter_key', 'kind', 'event_id', 'marker_occurrence_id', 'marker', 'combat_scope',
        'boss_instance_id', 'phase_id', 'boss_target_id', 'boss_target_lifecycle_id',
        'sync_tick', 'action_window_origin',
    })
    if not proof then return false, proof_error end
    if type(proof.watermark_tick) ~= 'number' then return false, 'trusted-action-watermark-required' end

    local result = empty_result()
    if action_required then
        local opened, open_result = self:_open_action_window(event.action_window, proof.watermark_tick)
        if not opened then return false, open_result end
        append_commands(result, open_result)
    end
    self.seen_phase_marker_events[event.event_id] = origin
    self.phase_marker_occurrences[occurrence_key] = event.event_id

    if event.marker == 'clone_window' then
        add_command(result, {
            type = 'spawn_ephemeral_clones',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            count = self.encounter.phase.clone_count,
            duration_seconds = self.encounter.phase.clone_duration_seconds,
            eligible_for_contribution = false,
            inherit_private_marks = false,
        })
    elseif event.marker == 'submerge' then
        local submerge_end_tick = event.action_window.open_tick + self.encounter.phase.submerge_seconds
        self.submerged = true
        self.trace_pause_until = submerge_end_tick
        add_command(result, {
            type = 'trace_pause',
            encounter_key = self.encounter_key,
            event_id = event.event_id,
            marker_occurrence_id = event.marker_occurrence_id,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            target_id = self.target_id,
            target_lifecycle_id = self.target_lifecycle_id,
            start_tick = event.action_window.open_tick,
            end_tick = submerge_end_tick,
            duration_seconds = self.encounter.phase.submerge_seconds,
        })
    elseif event.marker == 'frenzy' then
        self.frenzy = true
        add_command(result, {
            type = 'apply_boss_frenzy',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            target_scope = 'explicit',
            target_id = self.target_id,
        })
    end
    return true, result
end

function Boss:tick(requested_tick)
    local result = empty_result()
    local context = {
        encounter_key = self.encounter_key,
        boss_instance_id = self.boss_instance_id,
        phase_id = self.phase_id,
        boss_target_id = self.target_id,
        boss_target_lifecycle_id = self.target_lifecycle_id,
        requested_tick = requested_tick,
    }
    local proof, proof_error = self:_authority_proof('public_boss_watermark', context, {
        'encounter_key', 'boss_instance_id', 'phase_id',
        'boss_target_id', 'boss_target_lifecycle_id',
    })
    if not proof then
        result.authority_error = proof_error
        return result
    end
    local watermark_tick = proof.watermark_tick
    if type(watermark_tick) ~= 'number' then
        result.authority_error = 'trusted-action-watermark-required'
        return result
    end

    self:_expire_action_reservations(watermark_tick, result)
    local window = self.action_windows[self.active_action_window_id]
    if window then
        local settled, settle_error = self:_settle_action_completions(window, watermark_tick, result)
        if not settled then
            result.authority_error = settle_error
            return result
        end
        if watermark_tick >= window.close_tick then
            local closed, close_error = self:_close_action_window(
                window, 'window_expired', result, watermark_tick)
            if not closed then
                result.authority_error = close_error
                return result
            end
        end
    end
    if self.trace_pause_until and watermark_tick >= self.trace_pause_until then
        self.trace_pause_until = nil
        self.submerged = false
        add_command(result, {
            type = 'trace_resume',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            target_id = self.target_id,
            target_lifecycle_id = self.target_lifecycle_id,
        })
    end
    return result
end

function Boss:invalidate_actor(actor_id, lifecycle_id)
    local result = empty_result()
    local reservation = self.active_actions[actor_id]
    if reservation and reservation.lifecycle_id == lifecycle_id then
        self.active_actions[actor_id] = nil
        add_command(result, {
            type = 'cancel_encounter_action_reservation',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            window_id = reservation.window_id,
            actor_id = actor_id,
            lifecycle_id = lifecycle_id,
            action_token = reservation.token,
            reason = 'lifecycle_invalid',
        })
    end
    local chain = self.water_chain[actor_id]
    if chain and chain.active and chain.lifecycle_id == lifecycle_id then
        self:_clear_water_chain(actor_id, lifecycle_id, 'lifecycle_invalid', result)
    end
    return result
end

local identity_base_fields = {
    'event_id', 'combat_scope', 'boss_instance_id', 'from_phase', 'boss_target_id', 'boss_target_lifecycle_id',
}

local phase_transition_fields = {
    'event_id', 'combat_scope', 'boss_instance_id', 'from_phase', 'boss_target_id', 'boss_target_lifecycle_id',
    'to_phase', 'next_boss_target_id', 'next_boss_target_lifecycle_id',
}

local phase_transition_origin_fields = {
    'kind', 'event_id', 'combat_scope', 'boss_instance_id', 'from_phase', 'boss_target_id',
    'boss_target_lifecycle_id', 'to_phase', 'next_boss_target_id',
    'next_boss_target_lifecycle_id', 'reason',
}

local finalization_origin_fields = {
    'kind', 'event_id', 'combat_scope', 'boss_instance_id', 'from_phase', 'boss_target_id',
    'boss_target_lifecycle_id', 'reason',
}

function Boss:_validate_identity_event(event, kind, required_fields, origin_fields, invalid_error, duplicate_error)
    if type(event) ~= 'table' or event.kind ~= kind then return false, invalid_error end
    local untrusted = untrusted_authority_field(event)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    local field = missing_field(event, required_fields)
    if field then return false, 'missing-boss-identity-field:' .. field end
    if event.combat_scope ~= 'public'
        or event.session_instance_id ~= nil or event.session_epoch ~= nil then
        return false, 'invalid-public-boss-identity-scope'
    end

    local origin = identity_origin(event, origin_fields)
    local old_origin = self.seen_identity_events[event.event_id]
    if old_origin then
        if old_origin ~= origin then return false, 'boss-identity-event-conflict' end
        return false, duplicate_error
    end

    if event.boss_instance_id ~= self.boss_instance_id then return false, 'stale-boss-instance' end
    if self.ended then return false, 'boss-already-ended' end
    if event.from_phase ~= self.phase_id then return false, 'stale-boss-phase' end
    if event.boss_target_id ~= self.target_id
        or event.boss_target_lifecycle_id ~= self.target_lifecycle_id then
        return false, 'stale-boss-target'
    end
    return true, origin
end

function Boss:_validate_phase_transition(event)
    local ok, origin = self:_validate_identity_event(
        event, 'boss_phase_transition', phase_transition_fields, phase_transition_origin_fields,
        'invalid-boss-phase-transition-event', 'duplicate-boss-phase-transition'
    )
    if not ok then return false, origin end
    if event.to_phase == self.phase_id then return false, 'invalid-boss-phase-transition' end
    if self.phase_history[event.to_phase] then return false, 'boss-phase-rollback' end
    return true, origin
end

function Boss:change_phase(event)
    local ok, origin = self:_validate_phase_transition(event)
    if not ok then return false, origin end

    local context = copy_fields(event, phase_transition_origin_fields)
    context.encounter_key = self.encounter_key
    local identity_fields = copy_table(phase_transition_origin_fields)
    append(identity_fields, 'encounter_key')
    local proof, proof_error = self:_authority_proof(
        'public_boss_phase_transition', context, identity_fields)
    if not proof then return false, proof_error end
    if type(proof.watermark_tick) ~= 'number' then return false, 'trusted-action-watermark-required' end

    local reason = event.reason or 'phase_changed'
    local result = empty_result()
    local window = self.action_windows[self.active_action_window_id]
    if window then
        local closed, close_error = self:_close_action_window(window, reason, result, proof.watermark_tick)
        if not closed then return false, close_error end
    end
    for _, actor_id in ipairs(sorted_ids(self.active_actions)) do self.active_actions[actor_id] = nil end
    for _, actor_id in ipairs(sorted_ids(self.water_chain)) do
        local chain = self.water_chain[actor_id]
        if chain.active then self:_clear_water_chain(actor_id, chain.lifecycle_id, 'phase_changed', result) end
    end
    if self.trace_pause_until then
        add_command(result, {
            type = 'trace_resume',
            encounter_key = self.encounter_key,
            boss_instance_id = self.boss_instance_id,
            phase_id = self.phase_id,
            target_id = self.target_id,
            target_lifecycle_id = self.target_lifecycle_id,
            reason = reason,
        })
    end
    self.seen_identity_events[event.event_id] = origin
    self.phase_history[event.to_phase] = true
    self.phase_id = event.to_phase
    self.target_id = event.next_boss_target_id
    self.target_lifecycle_id = event.next_boss_target_lifecycle_id
    self.break_meter = 0
    self.mechanic_credit = {}
    self.trace_pause_until = nil
    self.submerged = false
    self.frenzy = false
    return true, result
end

function Boss:finalize(event)
    local ok, origin = self:_validate_identity_event(
        event, 'boss_finalization', identity_base_fields, finalization_origin_fields,
        'invalid-boss-finalization-event', 'duplicate-boss-finalization'
    )
    if not ok then return nil, origin end

    local context = copy_fields(event, finalization_origin_fields)
    context.encounter_key = self.encounter_key
    local identity_fields = copy_table(finalization_origin_fields)
    append(identity_fields, 'encounter_key')
    local proof, proof_error = self:_authority_proof(
        'public_boss_finalization', context, identity_fields)
    if not proof then return nil, proof_error end
    if type(proof.watermark_tick) ~= 'number' then return nil, 'trusted-action-watermark-required' end

    local cleanup = empty_result()
    local window = self.action_windows[self.active_action_window_id]
    if window then
        local closed, close_error = self:_close_action_window(
            window, 'boss_ended', cleanup, proof.watermark_tick)
        if not closed then return nil, close_error end
    end
    for _, actor_id in ipairs(sorted_ids(self.water_chain)) do
        local chain = self.water_chain[actor_id]
        if chain.active then self:_clear_water_chain(actor_id, chain.lifecycle_id, 'boss_ended', cleanup) end
    end
    self.active_actions = {}
    self.seen_identity_events[event.event_id] = origin
    self.ended = true

    local total_damage, principal = 0, nil
    for _, actor_id in ipairs(sorted_ids(self.participants)) do
        local participant = self.participants[actor_id]
        total_damage = total_damage + participant.damage
        if participant.damage > 0 and (not principal or participant.damage > principal.damage
            or (participant.damage == principal.damage and tostring(actor_id) < tostring(principal.actor_id))) then
            principal = participant
        end
    end

    local effective, honor_sync = {}, {}
    for _, actor_id in ipairs(sorted_ids(self.participants)) do
        local participant = self.participants[actor_id]
        local ratio = total_damage > 0 and participant.damage / total_damage or 0
        if ratio >= 0.03 or participant.action
            or participant.break_qualified or participant.protection_qualified then
            append(effective, actor_id)
        end
        if principal and actor_id ~= principal.actor_id and participant.team_id ~= nil
            and participant.team_id == principal.team_id and ratio > 0.10 then
            append(honor_sync, actor_id)
        end
    end
    return {
        encounter_key = self.encounter_key,
        boss_instance_id = self.boss_instance_id,
        phase_id = self.phase_id,
        finalization_event_id = event.event_id,
        end_reason = event.reason or 'defeated',
        commands = cleanup.commands,
        total_damage = total_damage,
        principal_actor_id = principal and principal.actor_id or nil,
        honor_sync_actor_ids = honor_sync,
        effective_participant_ids = effective,
        rare_eligibility = 'deferred_resource_table',
    }
end

return M
