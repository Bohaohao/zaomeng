-- C04 skill command builder. It never calls Y3 directly: every damage and
-- modifier command carries an explicit target scope and a cast-local identity.
local Config = require 'xunlie_config'
local Core = require 'xunlie_core'

local M = {}

local active_keys = {
    C04_A01 = true, C04_A02 = true, C04_A03 = true, C04_A04 = true,
    C04_A05 = true, C04_A06 = true, C04_A07 = true, C04_A08 = true,
}

local function append(list, value)
    list[#list + 1] = value
end

local function value_at(values, rank)
    return values and values[rank] or nil
end

local function passive_level(state, key)
    return state.passive_levels[key] or 0
end

local function map_value(map, key)
    return type(map) == 'table' and (map[key] or map[tostring(key)]) or nil
end

local function id_less(left, right)
    return tostring(left) < tostring(right)
end

local function copy_list(values)
    local result = {}
    for index, value in ipairs(values or {}) do result[index] = value end
    return result
end

local function copy_map(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function target_ref(context, target_id)
    return map_value(context and context.target_refs_by_id, target_id)
        or map_value(context and context.target_refs, target_id)
end

local function snapshot(context)
    context = context or {}
    local refs = copy_map(context.target_refs_by_id or context.target_refs or {})
    if context.primary_target_id ~= nil and context.primary_target_ref ~= nil then
        refs[context.primary_target_id] = context.primary_target_ref
    end
    return {
        actor_id = context.actor_id,
        lifecycle_id = context.lifecycle_id,
        combat_scope = context.combat_scope or 'public',
        session_instance_id = context.session_instance_id,
        session_epoch = context.session_epoch,
        source_unit_id = context.source_unit_id or context.unit_id,
        source_unit_ref = context.source_unit or context.unit,
        cast_sequence = context.cast_sequence,
        primary_target_id = context.primary_target_id,
        primary_target_ref = context.primary_target_ref,
        target_refs_by_id = refs,
        target_lifecycle_by_id = copy_map(context.target_lifecycle_by_id),
        selected_target_ids = copy_list(context.selected_target_ids),
        team_id = context.team_id,
        team_target_ids = copy_list(context.team_target_ids),
        cast_point = context.cast_point,
        direction = context.direction,
        safe_landing_result = context.safe_landing_result,
        safe_landing_point = context.safe_landing_point,
        recovery_candidate_target_id = context.recovery_candidate_target_id,
        target_meta_by_id = copy_map(context.target_meta_by_id),
    }
end

local function public_or_private_snapshot_valid(snap)
    if snap.combat_scope == 'public' then
        return snap.session_instance_id == nil and snap.session_epoch == nil
    end
    if snap.combat_scope == 'private_session' then
        return snap.session_instance_id ~= nil and snap.session_epoch ~= nil
    end
    return false
end

local function modifier(key, scope, duration, payload, extra)
    local command = {
        type = 'apply_modifier', key = key, target_scope = scope,
        duration = duration, payload = payload or {},
    }
    for name, value in pairs(extra or {}) do command[name] = value end
    return command
end

local function remove_modifier(key, scope, extra)
    local command = { type = 'remove_modifier', key = key, target_scope = scope }
    for name, value in pairs(extra or {}) do command[name] = value end
    return command
end

local function explicit_target(target_id, ref, extra)
    local command = {
        target_scope = 'explicit', target_id = target_id, target = ref,
        target_ids = { target_id }, targets = ref and { ref } or {},
    }
    for name, value in pairs(extra or {}) do command[name] = value end
    return command
end

local function damage(target_id, ref, coefficient, extra)
    local command = explicit_target(target_id, ref, extra)
    command.type = 'damage'
    command.coefficient = coefficient
    command.can_crit = true
    return command
end

local function delayed_damage(scope, coefficient, delay, extra)
    local command = {
        type = 'delayed_damage', target_scope = scope, coefficient = coefficient,
        delay = delay or 0, can_crit = true,
    }
    for name, value in pairs(extra or {}) do command[name] = value end
    return command
end

local function valid_rank(skill_key, rank)
    local ability = Config.abilities[skill_key]
    if not ability then return nil, 'unknown-skill' end
    if type(rank) ~= 'number' or rank < 1 or rank > ability.max_level then return nil, 'invalid-rank' end
    return ability
end

local function selected_snapshot(snap)
    local selected, seen = {}, {}
    for _, target_id in ipairs(snap.selected_target_ids or {}) do
        if target_id ~= nil and not seen[target_id] then
            seen[target_id] = true
            append(selected, target_id)
        end
    end
    return selected
end

local function target_meta(snap, target_id)
    return map_value(snap.target_meta_by_id, target_id) or {}
end

local function target_rank(snap, target_id)
    local rank = target_meta(snap, target_id).rank
    if rank == 'normal' or rank == 'elite' or rank == 'boss' then return rank end
    return 'unknown'
end

local function source_key(snap, skill_key)
    return tostring(snap.actor_id or 'actor') .. ':' .. skill_key
end

local function command_context(snapshot_value, command)
    command.cast_id = snapshot_value.cast_id
    command.lifecycle_id = snapshot_value.lifecycle_id
    command.skill_key = snapshot_value.skill_key
    command.combat_scope = snapshot_value.combat_scope
    command.session_instance_id = snapshot_value.session_instance_id
    command.session_epoch = snapshot_value.session_epoch
    return command
end

local function add_hunt_event(commands, result)
    if result and result.event then append(commands, result.event) end
end

local function apply_recovery(state, recovery, now, snap, commands)
    if not recovery then return end
    append(commands, recovery)
    local p02 = passive_level(state, 'C04_P02')
    if p02 > 0 then
        local passive = Config.passives.C04_P02
        append(commands, {
            type = 'heal_and_guard', heal_max_hp = value_at(passive.recovery_heal_max_hp, p02),
            damage_reduction = 0, duration = passive.duration_ticks,
            guard_key = 'C04_M12_RECOVERY', move_speed = value_at(passive.recovery_move_speed, p02),
        })
        append(commands, modifier('C04_M12_RECOVERY', 'self', passive.duration_ticks, {
            move_speed = value_at(passive.recovery_move_speed, p02),
            recovery_target_id = recovery.target_id,
        }, { source_id = snap.actor_id }))
    end
    if recovery.reverb_coefficient then
        append(commands, delayed_damage('selected', recovery.reverb_coefficient, 0, {
            pulse_key = 'C04_U01_REVERB', recovery_target_id = recovery.target_id,
            source_point_target_id = recovery.target_id, cast_id = recovery.cast_id,
            lifecycle_id = snap.lifecycle_id, skill_key = 'C04_U01',
        }))
    end
end

local function apply_ultimate_reaction(state, now, snap, triggering_skill_key, commands)
    local reaction = Core.try_ultimate_skill_reaction(state, now, triggering_skill_key)
    if not reaction then return end
    local realm = state.ultimate
    local target_id = realm and realm.primary_target_id
    local ref = realm and realm.primary_target_ref
    if target_id == nil or ref == nil then return end
    append(commands, delayed_damage('explicit', reaction.coefficient, 0, {
        target_id = target_id, target = ref, target_ids = { target_id }, targets = { ref },
        u01_reaction_index = reaction.index, cast_id = snap.cast_id,
        lifecycle_id = snap.lifecycle_id, skill_key = 'C04_U01',
    }))
end

local function accept_hit(token, event, expected_phase)
    if type(event) ~= 'table' then return false, 'invalid-hit-event' end
    if event.target_id == nil then return false, 'hit-target-required' end
    if type(event.hit_key) ~= 'string' or event.hit_key == '' then return false, 'hit-key-required' end
    if type(event.component_key) ~= 'string' or event.component_key == '' then return false, 'component-key-required' end
    if type(event.damage_dealt) ~= 'number' or event.damage_dealt <= 0 or event.alive == false then return false, 'ineffective-hit' end
    if expected_phase and event.phase ~= nil and event.phase ~= expected_phase then return false, 'unexpected-hit-phase' end
    token.accepted_hits = token.accepted_hits or {}
    if token.accepted_hits[event.hit_key] then return false, 'duplicate-hit-key' end
    token.accepted_hits[event.hit_key] = true
    return true
end

local function trace_status_key(target_id)
    return 'C04_M03_TRACE:' .. tostring(target_id)
end

local function apply_trace(state, rank, now, snap, target_id, ref, marks_before, commands)
    if rank < 5 or marks_before < 3 then return end
    local key = trace_status_key(target_id)
    local previous = Core.get_status(state, key, now)
    local revision = previous and ((previous.payload.revision or 0) + 1) or 1
    local duration = Config.abilities.C04_A01.trace_duration_ticks + Config.abilities.C04_A01.rank5_trace_bonus_ticks
    local effect_id = previous and previous.payload.effect_instance_id
        or table.concat({ 'C04_M03', tostring(snap.actor_id), tostring(snap.lifecycle_id), tostring(target_id), tostring(revision) }, ':')
    Core.apply_status(state, key, now, duration, {
        target_id = target_id, target_ref = ref, revision = revision,
        effect_instance_id = effect_id, next_tick = now + Config.ticks_per_second,
        tick_index = 0, expires_at = now + duration,
    })
    append(commands, modifier('C04_M03_TRACE', 'explicit', duration, {
        effect_instance_id = effect_id, revision = revision,
    }, explicit_target(target_id, ref, { source_id = snap.actor_id })))
end

local function wind_status(state, now)
    return Core.get_status(state, 'C04_M05_WIND', now)
end

local function snapshot_wind_window(state, now)
    local status = wind_status(state, now)
    if status and not status.payload.consumed_by_hit_key then return status.payload.window_id end
    return nil
end

local function consume_wind_window(state, token, now, event, snap, commands)
    local window_id = token.wind_window_id
    if not window_id then return end
    local status = wind_status(state, now)
    if not status or status.payload.window_id ~= window_id or status.payload.consumed_by_hit_key then return end
    status.payload.consumed_by_hit_key = event.hit_key
    Core.remove_status(state, 'C04_M05_WIND')
    append(commands, remove_modifier('C04_M05_WIND', 'self', { source_id = snap.actor_id }))

    local target_id = event.target_id
    local ref = event.target_ref or map_value(snap.target_refs_by_id, target_id)
    if Core.available_marks(state, target_id) <= 0 then return end
    local reservation_key = 'wind:' .. event.hit_key
    local reservation = Core.reserve_hunt(state, token.id, target_id, 1, now, reservation_key)
    if not reservation then return end
    local settled = Core.confirm_reservation(state, token.id, target_id, now, reservation_key)
    if not settled then return end
    local a04_rank = state.ability_levels.C04_A04 or 0
    if a04_rank <= 0 then return end
    append(commands, damage(target_id, ref, value_at(Config.abilities.C04_A04.wind_damage, a04_rank), {
        skill_key = 'C04_A04', cast_id = token.id, lifecycle_id = snap.lifecycle_id,
        component_key = 'wind:' .. event.component_key,
    }))
    add_hunt_event(commands, settled)
    apply_recovery(state, settled.recovery, now, snap, commands)
    if a04_rank >= 5 then append(commands, { type = 'cooldown_delta', skill_key = 'C04_A01', amount = -1.5 }) end
    if passive_level(state, 'C04_P05') >= 5 then
        append(commands, modifier('C04_M12_RECOVERY', 'self', Config.passives.C04_P05.rank5_wind_move_duration_ticks, {
            move_speed = Config.passives.C04_P05.rank5_wind_move_speed,
        }, { source_id = tostring(snap.actor_id) .. ':wind' }))
    end
end

local function reserve_single(state, token, target_id, amount, now, reservation_key)
    if amount <= 0 then return nil end
    return Core.reserve_hunt(state, token.id, target_id, amount, now, reservation_key)
end

local function selected_order(state, snap, ids, skill_key)
    table.sort(ids, function(left, right)
        local left_meta, right_meta = target_meta(snap, left), target_meta(snap, right)
        local left_distance, right_distance = left_meta.distance or math.huge, right_meta.distance or math.huge
        if skill_key == 'C04_A05' then
            local left_marks, right_marks = Core.available_marks(state, left), Core.available_marks(state, right)
            if left_marks ~= right_marks then return left_marks > right_marks end
        end
        if left_distance ~= right_distance then return left_distance < right_distance end
        return id_less(left, right)
    end)
    return ids
end

local function queue_recovery_candidate(token, settled, event, snap)
    if not settled or not settled.recovery_candidate then return end
    local candidate = settled.recovery_candidate
    candidate.hit_time = event.hit_time or candidate.accepted_at
    candidate.path_distance = event.path_distance or target_meta(snap, candidate.target_id).distance or math.huge
    token.recovery_candidates = token.recovery_candidates or {}
    append(token.recovery_candidates, candidate)
end

local function settle_deferred_recovery(state, token, now, snap, commands)
    local candidates = token.recovery_candidates or {}
    if #candidates == 0 then return end
    local selected
    if token.recovery_candidate_target_id ~= nil then
        for _, candidate in ipairs(candidates) do
            if candidate.target_id == token.recovery_candidate_target_id then
                selected = candidate
                break
            end
        end
    end
    if not selected then
        table.sort(candidates, function(left, right)
            if left.hit_time ~= right.hit_time then return left.hit_time < right.hit_time end
            if left.path_distance ~= right.path_distance then return left.path_distance < right.path_distance end
            return id_less(left.target_id, right.target_id)
        end)
        selected = candidates[1]
    end
    local recovery = Core.commit_recovery(state, token, selected, now)
    apply_recovery(state, recovery, now, snap, commands)
end

local function add_field(state, token, now, snap, skill_key, commands)
    local ability = Config.abilities[skill_key]
    local status_key = 'C04_M09_FIELD:' .. skill_key
    local previous = Core.get_status(state, status_key, now)
    local field_source_id = source_key(snap, skill_key)
    if previous then
        append(commands, remove_modifier('C04_M09_FIELD', 'self', { source_id = previous.payload.source_id }))
    end
    local duration = ability.field_duration_ticks
    Core.apply_status(state, status_key, now, duration, {
        source_id = field_source_id, cast_id = token.id, source_skill_key = skill_key,
        cast_point = snap.cast_point, expires_at = now + duration,
    })
    append(commands, modifier('C04_M09_FIELD', 'self', duration, {
        cast_id = token.id, source_skill_key = skill_key, cast_point = snap.cast_point,
    }, { source_id = field_source_id }))
    for ordinal, delay in ipairs(ability.pulses) do
        append(commands, delayed_damage('selected', value_at(ability.pulse_damage, token.rank), delay, {
            pulse_key = skill_key, field_cast_id = token.id, pulse_ordinal = ordinal,
            source_skill_key = skill_key, lifecycle_id = snap.lifecycle_id, skill_key = skill_key,
            target_limit = ability.selected_cap,
        }))
    end
end

local function mark_pierce_snapshot(state, snap, target_id, now)
    local status = Core.get_status(state, 'C04_M04_PIERCE:' .. tostring(target_id), now)
    if not status then return false end
    if status.payload.source_id ~= snap.actor_id then return false end
    return true
end

local function apply_pierce(state, token, now, target_id, ref, commands)
    local rank = token.rank
    local p03 = passive_level(state, 'C04_P03')
    local duration = Config.abilities.C04_A03.pierce_duration_ticks
    if p03 > 0 then duration = duration + value_at(Config.passives.C04_P03.pierce_duration_bonus_ticks, p03) end
    Core.apply_status(state, 'C04_M04_PIERCE:' .. tostring(target_id), now, duration, {
        source_id = token.snapshot.actor_id, target_id = target_id, expires_at = now + duration,
    })
    append(commands, modifier('C04_M04_PIERCE', 'explicit', duration, {},
        explicit_target(target_id, ref, { source_id = token.snapshot.actor_id })))
end

local function apply_slow(snap, skill_key, rank, target_id, ref, commands, bonus)
    local rank_value = target_rank(snap, target_id)
    if rank_value ~= 'normal' and rank_value ~= 'elite' then return end
    local ability = Config.abilities[skill_key]
    append(commands, modifier('C04_M07_SLOW', 'explicit', ability.slow_duration_ticks, {
        slow = math.min(0.75, value_at(ability.slow, rank) + (bonus or 0)),
        aggregation_category = 'move_speed_slow', source_skill_key = skill_key,
    }, explicit_target(target_id, ref, { source_id = source_key(snap, skill_key) })))
end

local function add_reaction_if_needed(state, token, now, commands)
    if token.skill_key ~= 'C04_A01' and token.skill_key ~= 'C04_A02' and token.skill_key ~= 'C04_A03'
        and token.skill_key ~= 'C04_A04' and token.skill_key ~= 'C04_A05' and token.skill_key ~= 'C04_A06'
        and token.skill_key ~= 'C04_A07' and token.skill_key ~= 'C04_A08' then return end
    apply_ultimate_reaction(state, now, token.snapshot, token.skill_key, commands)
end

function M.commit_skill(state, skill_key, rank, now, context)
    local ability, error_code = valid_rank(skill_key, rank)
    if not ability or not active_keys[skill_key] then return { ok = false, error = error_code or 'not-active-skill', commands = {} } end
    local snap = snapshot(context)
    if not public_or_private_snapshot_valid(snap) then return { ok = false, error = 'invalid-session-context', commands = {} } end
    if ability.requires_primary and (snap.primary_target_id == nil or snap.primary_target_ref == nil) then
        return { ok = false, error = 'primary-target-required', commands = {} }
    end
    if ability.requires_direction and snap.direction == nil then return { ok = false, error = 'cast-direction-required', commands = {} } end
    if ability.requires_point and snap.cast_point == nil then return { ok = false, error = 'cast-point-required', commands = {} } end
    if ability.requires_safe_landing and (snap.safe_landing_result ~= true or snap.safe_landing_point == nil) then
        return { ok = false, error = 'safe-landing-required', commands = {} }
    end

    local token = Core.create_cast(state, skill_key, now, snap, true)
    token.rank, token.phase = rank, 'direct'
    token.wind_window_id = snapshot_wind_window(state, now)
    local commands = {}

    if skill_key == 'C04_A03' then
        local reservation, reserve_error = reserve_single(state, token, snap.primary_target_id, ability.consume, now)
        if not reservation then Core.finalize_cast(state, token.id, now, reserve_error); return { ok = false, error = reserve_error, commands = {} } end
        token.phase = 'direct'
    elseif skill_key == 'C04_A04' then
        token.phase = 'landing'
        token.awaiting_safe_landing = true
        append(commands, { type = 'move', distance = value_at(ability.step_distance, rank)
            + (passive_level(state, 'C04_P05') > 0 and value_at(Config.passives.C04_P05.step_distance_bonus, passive_level(state, 'C04_P05')) or 0),
            direction = snap.direction, target_scope = 'self', safe_landing_required = true,
            safe_landing_point = snap.safe_landing_point, cast_id = token.id, lifecycle_id = snap.lifecycle_id })
    elseif skill_key == 'C04_A05' or skill_key == 'C04_A08' then
        token.phase = 'initial'
        local selected = selected_snapshot(snap)
        selected_order(state, snap, selected, skill_key)
        while #selected > ability.selected_cap do selected[#selected] = nil end
        token.selected_by_id, token.pre_m08_by_target = {}, {}
        for _, target_id in ipairs(selected) do
            token.selected_by_id[target_id] = true
            token.pre_m08_by_target[target_id] = target_meta(snap, target_id).has_own_m08_pre_hit == true
        end
        local reserve_candidates = copy_list(selected)
        local reserved = 0
        for _, target_id in ipairs(reserve_candidates) do
            local minimum = skill_key == 'C04_A08' and ability.minimum_marks or 1
            if reserved < ability.consume_cap and Core.available_marks(state, target_id) >= minimum then
                local reservation = reserve_single(state, token, target_id, ability.consume, now)
                if reservation then
                    reserved = reserved + 1
                    if reservation.was_locked
                        and (snap.recovery_candidate_target_id == target_id or token.recovery_candidate_target_id == nil) then
                        token.recovery_candidate_target_id = target_id
                    end
                end
            end
        end
        add_field(state, token, now, snap, skill_key, commands)
    elseif skill_key == 'C04_A06' then
        local amount = Core.available_marks(state, snap.primary_target_id)
        if amount <= 0 then Core.finalize_cast(state, token.id, now, 'insufficient-hunt-marks'); return { ok = false, error = 'insufficient-hunt-marks', commands = {} } end
        local reservation, reserve_error = reserve_single(state, token, snap.primary_target_id, amount, now)
        if not reservation then Core.finalize_cast(state, token.id, now, reserve_error); return { ok = false, error = reserve_error, commands = {} } end
        token.has_own_pierce_pre_cast = mark_pierce_snapshot(state, snap, snap.primary_target_id, now)
        token.phase = 'direct'
    elseif skill_key == 'C04_A07' then
        token.phase = 'arrow'
        token.phase_close_ticks, token.phase_hits, token.phase_consumed = {}, {}, {}
        local arrows = math.min(3, Core.available_marks(state, snap.primary_target_id))
        for phase = 1, 3 do
            token.phase_close_ticks[phase] = now + ability.phase_close_ticks[phase]
            if phase <= arrows then reserve_single(state, token, snap.primary_target_id, ability.consume, now, 'a07:' .. phase) end
        end
        append(commands, modifier('C04_M06_THREE_ARROWS', 'self', ability.three_arrow_duration_ticks, {
            cast_id = token.id, phase_close_ticks = copy_list(token.phase_close_ticks),
        }, { source_id = snap.actor_id }))
    end
    return { ok = true, cast_id = token.id, cast_snapshot = snap, commands = commands }
end

function M.begin_normal_attack(state, now, context)
    local snap = snapshot(context)
    if not public_or_private_snapshot_valid(snap) then return { ok = false, error = 'invalid-session-context', commands = {} } end
    if snap.primary_target_id == nil or snap.primary_target_ref == nil then return { ok = false, error = 'primary-target-required', commands = {} } end
    local token = Core.create_cast(state, 'C04_BASIC', now, snap, true)
    token.phase = 'basic'
    token.wind_window_id = snapshot_wind_window(state, now)
    return { ok = true, cast_id = token.id, cast_snapshot = snap, commands = {} }
end

function M.confirm_normal_attack(state, cast_id, now, event)
    local token = Core.get_cast(state, cast_id)
    if not token or token.skill_key ~= 'C04_BASIC' then return { ok = false, error = 'unknown-cast', commands = {} } end
    local accepted, error_code = accept_hit(token, event, 'basic')
    if not accepted then return { ok = false, error = error_code, commands = {} } end
    if event.target_id ~= token.snapshot.primary_target_id then return { ok = false, error = 'primary-target-mismatch', commands = {} } end
    local commands = {}
    local result = Core.gain_hunt(state, event.target_id, now, 'normal')
    add_hunt_event(commands, result)
    consume_wind_window(state, token, now, event, token.snapshot, commands)
    Core.finalize_cast(state, cast_id, now, 'basic-confirmed')
    return { ok = true, skill_key = 'C04_BASIC', commands = commands }
end

local function confirm_a01(state, token, now, event)
    local accepted, error_code = accept_hit(token, event, 'direct')
    if not accepted then return nil, error_code end
    if event.target_id ~= token.snapshot.primary_target_id then return nil, 'primary-target-mismatch' end
    local commands, ref = {}, event.target_ref or map_value(token.snapshot.target_refs_by_id, event.target_id)
    local marks_before = Core.hunt_count(state, event.target_id)
    append(commands, damage(event.target_id, ref, value_at(Config.abilities.C04_A01.damage, token.rank), {
        skill_key = token.skill_key, cast_id = token.id, lifecycle_id = token.snapshot.lifecycle_id,
        component_key = event.component_key,
    }))
    local result = Core.gain_hunt(state, event.target_id, now, 'C04_A01')
    add_hunt_event(commands, result)
    apply_trace(state, token.rank, now, token.snapshot, event.target_id, ref, marks_before, commands)
    consume_wind_window(state, token, now, event, token.snapshot, commands)
    add_reaction_if_needed(state, token, now, commands)
    return commands
end

local function confirm_a02(token, event)
    local accepted, error_code = accept_hit(token, event, 'fan')
    if not accepted then return nil, error_code end
    token.a02_candidates = token.a02_candidates or {}
    append(token.a02_candidates, event)
    return {}
end

local function confirm_a03(state, token, now, event)
    local accepted, error_code = accept_hit(token, event, 'direct')
    if not accepted then return nil, error_code end
    if event.target_id ~= token.snapshot.primary_target_id then return nil, 'primary-target-mismatch' end
    local settled, settle_error = Core.confirm_reservation(state, token.id, event.target_id, now)
    if not settled then return nil, settle_error end
    local ref, commands = event.target_ref or map_value(token.snapshot.target_refs_by_id, event.target_id), {}
    append(commands, damage(event.target_id, ref,
        value_at(Config.abilities.C04_A03.damage, token.rank) + settled.reservation.count * value_at(Config.abilities.C04_A03.per_mark, token.rank),
        { skill_key = token.skill_key, cast_id = token.id, lifecycle_id = token.snapshot.lifecycle_id, component_key = event.component_key }))
    apply_pierce(state, token, now, event.target_id, ref, commands)
    add_hunt_event(commands, settled)
    apply_recovery(state, settled.recovery, now, token.snapshot, commands)
    add_reaction_if_needed(state, token, now, commands)
    return commands
end

local function confirm_a05_or_a08(state, token, now, event)
    local accepted, error_code = accept_hit(token, event, 'initial')
    if not accepted then return nil, error_code end
    if not token.selected_by_id[event.target_id] then return nil, 'selected-target-mismatch' end
    local ability, snap, ref = Config.abilities[token.skill_key], token.snapshot,
        event.target_ref or map_value(token.snapshot.target_refs_by_id, event.target_id)
    local commands = {}
    local reservation = token.reservations[tostring(event.target_id)]
    local settled
    if reservation then
        settled, error_code = Core.confirm_reservation(state, token.id, event.target_id, now, nil, { defer_recovery = true })
        if not settled then return nil, error_code end
    end
    local coefficient
    if token.skill_key == 'C04_A05' then
        coefficient = value_at(ability.initial_damage, token.rank)
        if token.pre_m08_by_target[event.target_id] and token.rank >= 5 then coefficient = coefficient + ability.rank5_net_bonus_damage end
    else
        local spent = settled and settled.reservation.count or 0
        coefficient = value_at(ability.initial_damage, token.rank) + spent
            * (value_at(ability.low_mark_extra, token.rank) + (passive_level(state, 'C04_P08') > 0
                and value_at(Config.passives.C04_P08.a08_per_mark_extra, passive_level(state, 'C04_P08')) or 0))
    end
    append(commands, damage(event.target_id, ref, coefficient, {
        skill_key = token.skill_key, cast_id = token.id, lifecycle_id = snap.lifecycle_id,
        component_key = event.component_key,
    }))
    local slow_bonus = token.skill_key == 'C04_A05' and (passive_level(state, 'C04_P07') > 0
        and value_at(Config.passives.C04_P07.slow_bonus, passive_level(state, 'C04_P07')) or 0) or 0
    if token.skill_key == 'C04_A08' and token.pre_m08_by_target[event.target_id] then slow_bonus = slow_bonus + 0.10 end
    apply_slow(snap, token.skill_key, token.rank, event.target_id, ref, commands, slow_bonus)
    if token.skill_key == 'C04_A05' then
        local p07 = passive_level(state, 'C04_P07')
        local duration = ability.net_duration_ticks + (p07 > 0 and value_at(Config.passives.C04_P07.net_duration_bonus_ticks, p07) or 0)
        Core.apply_status(state, 'C04_M08_NET:' .. tostring(event.target_id), now, duration, {
            source_id = snap.actor_id, target_id = event.target_id, expires_at = now + duration,
        })
        append(commands, modifier('C04_M08_NET', 'explicit', duration, {},
            explicit_target(event.target_id, ref, { source_id = snap.actor_id })))
        if p07 >= 5 and token.pre_m08_by_target[event.target_id] then
            local trace = Core.get_status(state, trace_status_key(event.target_id), now)
            if trace then
                trace.expires_at = trace.expires_at + 60
            end
        end
    elseif settled and settled.reservation.was_locked then
        Core.apply_status(state, 'C04_M10_GARROTE:' .. tostring(event.target_id), now, ability.garrote_duration_ticks, {
            source_id = snap.actor_id, target_id = event.target_id, expires_at = now + ability.garrote_duration_ticks,
        })
        append(commands, modifier('C04_M10_GARROTE', 'explicit', ability.garrote_duration_ticks, {},
            explicit_target(event.target_id, ref, { source_id = snap.actor_id })))
    end
    if settled then
        add_hunt_event(commands, settled)
        queue_recovery_candidate(token, settled, event, snap)
    end
    if token.skill_key == 'C04_A08' and token.pre_m08_by_target[event.target_id] then
        token.pre_m08_hit_count = (token.pre_m08_hit_count or 0) + 1
        if token.pre_m08_hit_count == 2 and passive_level(state, 'C04_P08') > 0 then
            append(commands, { type = 'cooldown_delta', skill_key = 'C04_A05',
                amount = -value_at(Config.passives.C04_P08.a05_cooldown_reduction, passive_level(state, 'C04_P08')) })
        end
    end
    add_reaction_if_needed(state, token, now, commands)
    return commands
end

local function confirm_a06(state, token, now, event)
    local accepted, error_code = accept_hit(token, event, 'direct')
    if not accepted then return nil, error_code end
    if event.target_id ~= token.snapshot.primary_target_id then return nil, 'primary-target-mismatch' end
    local settled, settle_error = Core.confirm_reservation(state, token.id, event.target_id, now)
    if not settled then return nil, settle_error end
    local n, ability = settled.reservation.count, Config.abilities.C04_A06
    local p04, p03 = passive_level(state, 'C04_P04'), passive_level(state, 'C04_P03')
    local multiplier = 1 + n * (p04 > 0 and value_at(Config.passives.C04_P04.a06_total_multiplier_per_mark, p04) or 0)
    if token.has_own_pierce_pre_cast and Core.get_status(state, 'C04_M04_PIERCE:' .. tostring(event.target_id), now) then
        multiplier = multiplier + ability.pierce_a06_bonus + (p03 > 0 and value_at(Config.passives.C04_P03.a06_bonus_per_mark, p03) or 0)
    end
    local ref, commands = event.target_ref or map_value(token.snapshot.target_refs_by_id, event.target_id), {}
    append(commands, damage(event.target_id, ref,
        (value_at(ability.damage, token.rank) + n * value_at(ability.per_mark, token.rank)) * multiplier,
        { skill_key = token.skill_key, cast_id = token.id, lifecycle_id = token.snapshot.lifecycle_id, component_key = event.component_key }))
    append(commands, remove_modifier('C04_M04_PIERCE', 'explicit', explicit_target(event.target_id, ref, { source_id = token.snapshot.actor_id })))
    Core.remove_status(state, 'C04_M04_PIERCE:' .. tostring(event.target_id))
    if n == Config.resource.marks_max then
        append(commands, modifier('C04_M12_RECOVERY', 'self', ability.complete_move_duration_ticks, {
            move_speed = ability.complete_move_speed,
        }, { source_id = tostring(token.snapshot.actor_id) .. ':a06' }))
    end
    if p03 >= 5 then append(commands, { type = 'cooldown_delta', skill_key = 'C04_A06', amount = -1.0 }) end
    if p04 >= 5 and n == Config.resource.marks_max then append(commands, { type = 'cooldown_delta', skill_key = 'C04_A01', amount = -2.0 }) end
    add_hunt_event(commands, settled)
    apply_recovery(state, settled.recovery, now, token.snapshot, commands)
    add_reaction_if_needed(state, token, now, commands)
    return commands
end

local function numeric_phase(value)
    if type(value) == 'number' then return value end
    if type(value) == 'string' then return tonumber(value:match('arrow_(%d+)')) end
    return nil
end

local function confirm_a07(state, token, now, event)
    local phase = numeric_phase(event.phase)
    if not phase or phase < 1 or phase > 3 then return nil, 'invalid-a07-phase' end
    if now > token.phase_close_ticks[phase] then return nil, 'phase-expired' end
    local accepted, error_code = accept_hit(token, event, 'arrow_' .. phase)
    if not accepted then return nil, error_code end
    if event.target_id ~= token.snapshot.primary_target_id then return nil, 'primary-target-mismatch' end
    if token.phase_hits[phase] then return nil, 'phase-already-hit' end
    token.phase_hits[phase] = true
    local key = 'a07:' .. phase
    local reservation = token.reservations[key]
    local settled
    if reservation then
        settled, error_code = Core.confirm_reservation(state, token.id, event.target_id, now, key)
        if not settled then return nil, error_code end
        token.phase_consumed[phase] = true
    end
    local ability, ref, commands = Config.abilities.C04_A07,
        event.target_ref or map_value(token.snapshot.target_refs_by_id, event.target_id), {}
    local coefficient = value_at(ability.arrow_damage, token.rank)
    if settled then coefficient = coefficient + value_at(ability.extra_per_mark, token.rank) end
    append(commands, damage(event.target_id, ref, coefficient, {
        skill_key = token.skill_key, cast_id = token.id, lifecycle_id = token.snapshot.lifecycle_id,
        phase = 'arrow_' .. phase, component_key = event.component_key,
    }))
    if passive_level(state, 'C04_P06') > 0 then
        append(commands, { type = 'cooldown_delta', skill_key = 'C04_A04',
            amount = -value_at(Config.passives.C04_P06.a07_cooldown_reduction, passive_level(state, 'C04_P06')) })
    end
    if settled then
        add_hunt_event(commands, settled)
        apply_recovery(state, settled.recovery, now, token.snapshot, commands)
    end
    add_reaction_if_needed(state, token, now, commands)
    return commands
end

function M.confirm_skill_hit(state, cast_id, now, event)
    local token = Core.get_cast(state, cast_id)
    if not token then return { ok = false, error = 'unknown-cast', commands = {} } end
    local commands, error_code
    if token.skill_key == 'C04_A01' then commands, error_code = confirm_a01(state, token, now, event)
    elseif token.skill_key == 'C04_A02' then commands, error_code = confirm_a02(token, event)
    elseif token.skill_key == 'C04_A03' then commands, error_code = confirm_a03(state, token, now, event)
    elseif token.skill_key == 'C04_A05' or token.skill_key == 'C04_A08' then commands, error_code = confirm_a05_or_a08(state, token, now, event)
    elseif token.skill_key == 'C04_A06' then commands, error_code = confirm_a06(state, token, now, event)
    elseif token.skill_key == 'C04_A07' then commands, error_code = confirm_a07(state, token, now, event)
    else return { ok = false, error = 'hit-not-supported', commands = {} } end
    if not commands then return { ok = false, error = error_code, commands = {} } end
    return { ok = true, skill_key = token.skill_key, commands = commands }
end

function M.confirm_safe_landing(state, cast_id, now)
    local token = Core.get_cast(state, cast_id)
    if not token or token.skill_key ~= 'C04_A04' or not token.awaiting_safe_landing then
        return { ok = false, error = 'landing-not-pending', commands = {} }
    end
    token.awaiting_safe_landing = false
    local p05 = passive_level(state, 'C04_P05')
    local duration = Config.abilities.C04_A04.wind_duration_ticks
        + (p05 > 0 and value_at(Config.passives.C04_P05.wind_duration_bonus_ticks, p05) or 0)
    local window_id = 'C04_M05:' .. tostring(token.id)
    Core.apply_status(state, 'C04_M05_WIND', now, duration, {
        window_id = window_id, source_cast_id = token.id, consumed_by_hit_key = nil,
    })
    token.wind_window_id = window_id
    return { ok = true, commands = { modifier('C04_M05_WIND', 'self', duration, { window_id = window_id },
        { source_id = token.snapshot.actor_id }) } }
end

function M.finalize_phase(state, cast_id, phase, now)
    local token = Core.get_cast(state, cast_id)
    if not token or token.skill_key ~= 'C04_A07' then return { ok = false, error = 'unknown-cast', commands = {} } end
    if type(phase) ~= 'number' or phase < 1 or phase > 3 then return { ok = false, error = 'invalid-a07-phase', commands = {} } end
    if now < token.phase_close_ticks[phase] then return { ok = false, error = 'phase-not-closed', commands = {} } end
    if token.phase_closed and token.phase_closed[phase] then return { ok = false, error = 'phase-already-closed', commands = {} } end
    token.phase_closed = token.phase_closed or {}
    token.phase_closed[phase] = true
    Core.release_reservation(state, token.id, token.snapshot.primary_target_id, 'phase-finalized', 'a07:' .. phase)
    local commands = {}
    if phase == 3 then
        local all_hit = token.phase_hits[1] and token.phase_hits[2] and token.phase_hits[3]
        local consumed = 0
        for index = 1, 3 do if token.phase_consumed[index] then consumed = consumed + 1 end end
        if all_hit then append(commands, { type = 'cooldown_delta', skill_key = 'C04_A04', amount = -2.0 }) end
        if all_hit and consumed >= 2 and passive_level(state, 'C04_P06') >= 5 then
            local a04_rank = state.ability_levels.C04_A04 or 0
            if a04_rank > 0 then
                append(commands, damage(token.snapshot.primary_target_id, token.snapshot.primary_target_ref,
                    value_at(Config.abilities.C04_A04.wind_damage, a04_rank), {
                        skill_key = 'C04_A04', cast_id = token.id, lifecycle_id = token.snapshot.lifecycle_id,
                        component_key = 'a07-free-wind',
                    }))
            end
        end
        append(commands, remove_modifier('C04_M06_THREE_ARROWS', 'self', { source_id = token.snapshot.actor_id }))
        Core.finalize_cast(state, cast_id, now, 'a07-complete')
    end
    return { ok = true, commands = commands }
end

function M.finish_skill_miss(state, cast_id, now, reason)
    local token = Core.get_cast(state, cast_id)
    if not token then return { ok = false, error = 'unknown-cast', commands = {} } end
    local commands = {}
    if token.skill_key == 'C04_A07' then append(commands, remove_modifier('C04_M06_THREE_ARROWS', 'self', { source_id = token.snapshot.actor_id })) end
    if token.skill_key == 'C04_A05' or token.skill_key == 'C04_A08' then
        settle_deferred_recovery(state, token, now, token.snapshot, commands)
    end
    Core.finalize_cast(state, cast_id, now, reason or 'missed')
    return { ok = true, commands = commands }
end

function M.finalize_cast(state, cast_id, now, reason)
    local token = Core.get_cast(state, cast_id)
    if not token then return { ok = false, error = 'unknown-cast', commands = {} } end
    local commands = {}
    if token.skill_key == 'C04_A02' then
        local first_by_target = {}
        for _, event in ipairs(token.a02_candidates or {}) do
            local existing = first_by_target[event.target_id]
            if not existing or (event.hit_time or now) < (existing.hit_time or now)
                or ((event.hit_time or now) == (existing.hit_time or now)
                    and ((event.path_distance or math.huge) < (existing.path_distance or math.huge)
                        or ((event.path_distance or math.huge) == (existing.path_distance or math.huge)
                            and id_less(event.target_id, existing.target_id)))) then
                first_by_target[event.target_id] = event
            end
        end
        local candidates = {}
        for _, event in pairs(first_by_target) do append(candidates, event) end
        table.sort(candidates, function(left, right)
            if (left.hit_time or now) ~= (right.hit_time or now) then return (left.hit_time or now) < (right.hit_time or now) end
            if (left.path_distance or math.huge) ~= (right.path_distance or math.huge) then return (left.path_distance or math.huge) < (right.path_distance or math.huge) end
            return id_less(left.target_id, right.target_id)
        end)
        for index, event in ipairs(candidates) do
            if index > Config.abilities.C04_A02.target_cap then break end
            local ref = event.target_ref or map_value(token.snapshot.target_refs_by_id, event.target_id)
            append(commands, damage(event.target_id, ref, value_at(Config.abilities.C04_A02.damage, token.rank), {
                skill_key = token.skill_key, cast_id = token.id, lifecycle_id = token.snapshot.lifecycle_id,
                component_key = event.component_key,
            }))
            add_hunt_event(commands, Core.gain_hunt(state, event.target_id, now, 'C04_A02'))
            add_reaction_if_needed(state, token, now, commands)
        end
    end
    if token.skill_key == 'C04_A07' then append(commands, remove_modifier('C04_M06_THREE_ARROWS', 'self', { source_id = token.snapshot.actor_id })) end
    if token.skill_key == 'C04_A05' or token.skill_key == 'C04_A08' then
        settle_deferred_recovery(state, token, now, token.snapshot, commands)
    end
    Core.finalize_cast(state, cast_id, now, reason or 'finalized')
    return { ok = true, commands = commands }
end

function M.activate_ultimate(state, now, context)
    local snap = snapshot(context)
    if not public_or_private_snapshot_valid(snap) then return { ok = false, error = 'invalid-session-context', commands = {} } end
    if snap.primary_target_id == nil or snap.primary_target_ref == nil then return { ok = false, error = 'primary-target-required', commands = {} } end
    local realm, event_or_error = Core.activate_ultimate(state, now, snap.primary_target_id)
    if not realm then return { ok = false, error = event_or_error, commands = {} } end
    realm.primary_target_ref = snap.primary_target_ref
    local commands = { event_or_error,
        modifier('C04_M11_ULTIMATE', 'self', realm.expires_at - now, {
            u01_cast_id = 'C04_U01:' .. tostring(snap.actor_id) .. ':' .. tostring(realm.expires_at),
            primary_target_id = snap.primary_target_id, tier = realm.tier,
        }, { source_id = snap.actor_id }),
        damage(snap.primary_target_id, snap.primary_target_ref, Config.ultimate.opening_damage, {
            skill_key = 'C04_U01', lifecycle_id = snap.lifecycle_id, component_key = 'opening-main',
        }),
    }
    local rebound = selected_snapshot(snap)
    while #rebound > Config.ultimate.opening_rebound_cap do rebound[#rebound] = nil end
    for ordinal, target_id in ipairs(rebound) do
        if target_id ~= snap.primary_target_id and Core.hunt_count(state, target_id) > 0 then
            append(commands, damage(target_id, map_value(snap.target_refs_by_id, target_id), Config.ultimate.opening_rebound_damage, {
                skill_key = 'C04_U01', lifecycle_id = snap.lifecycle_id, component_key = 'opening-rebound-' .. ordinal,
            }))
        end
    end
    return { ok = true, commands = commands }
end

local function trace_ticks(state, now)
    local commands = {}
    for key, status in pairs(state.statuses) do
        if key:sub(1, #'C04_M03_TRACE:') == 'C04_M03_TRACE:' and status.payload then
            while status.payload.next_tick and status.payload.next_tick <= now
                and status.payload.next_tick <= status.expires_at do
                status.payload.tick_index = status.payload.tick_index + 1
                append(commands, damage(status.payload.target_id, status.payload.target_ref, 0.12, {
                    skill_key = 'C04_F01', periodic = true, effect_instance_id = status.payload.effect_instance_id,
                    effect_revision = status.payload.revision,
                    periodic_event_id = status.payload.effect_instance_id .. ':' .. status.payload.tick_index,
                    component_key = 'trace-' .. status.payload.tick_index,
                }))
                status.payload.next_tick = status.payload.next_tick + Config.ticks_per_second
            end
        end
    end
    return commands
end

function M.tick(state, now)
    local commands = trace_ticks(state, now)
    for _, event in ipairs(Core.tick(state, now)) do
        append(commands, event)
        if event.type == 'ultimate_expired' then
            append(commands, remove_modifier('C04_M11_ULTIMATE', 'self'))
            if event.had_recovery and passive_level(state, 'C04_P02') >= 5 then
                append(commands, { type = 'heal_and_guard', heal_max_hp = 0.01, damage_reduction = 0, duration = 0 })
            end
        end
    end
    return commands
end

return M
