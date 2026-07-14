-- custom-built: C03 持明技能指令。这里只生成适配器中立命令，不直接调用 Y3。
local Config = require 'chiming_config'
local Core = require 'chiming_core'

local M = {}

local hit_confirmed_skills = {
    C03_A01 = true,
    C03_A02 = true,
    C03_A03 = true,
    C03_A05 = true,
    C03_A06 = true,
    C03_A08 = true,
}

local valid_ranks = { normal = true, elite = true, boss = true, unknown = true }

local function append(list, value)
    list[#list + 1] = value
end

local function append_all(target, source)
    for _, value in ipairs(source or {}) do append(target, value) end
end

local function value_at(values, rank)
    return values and values[rank] or nil
end

local function passive_level(state, key)
    return state.passive_levels[key] or 0
end

local function id_of(value)
    if value == nil then return nil end
    if type(value) ~= 'table' and type(value) ~= 'userdata' then return value end
    if type(value.get_id) == 'function' then
        local ok, id = pcall(value.get_id, value)
        if ok and id ~= nil then return id end
    end
    return value.id
end

local function copy_map(target, source)
    for key, value in pairs(source or {}) do target[key] = value end
end

local function target_ref(context, target_id, fallback)
    if fallback ~= nil then return fallback end
    local refs = context.target_refs_by_id or context.target_refs or {}
    return refs[target_id] or refs[tostring(target_id)]
end

local function target_meta(context, target_id)
    local metadata = context.target_meta_by_id or {}
    return metadata[target_id] or metadata[tostring(target_id)] or {}
end

local function state_commands(events)
    local commands = {}
    append_all(commands, events)
    return commands
end

local function apply_modifier(commands, key, target_scope, duration, payload, extra)
    local command = {
        type = 'apply_modifier',
        key = key,
        target_scope = target_scope,
        duration = duration,
        payload = payload or {},
    }
    for field, value in pairs(extra or {}) do command[field] = value end
    append(commands, command)
end

local function remove_modifier(commands, key, target_scope, extra)
    local command = { type = 'remove_modifier', key = key, target_scope = target_scope }
    for field, value in pairs(extra or {}) do command[field] = value end
    append(commands, command)
end

local function validate_rank(skill_key, rank)
    local ability = Config.abilities[skill_key]
    if not ability then return nil, 'unknown-skill' end
    if type(rank) ~= 'number' or rank < 1 or rank > ability.max_level then return nil, 'invalid-rank' end
    return ability
end

local function explicit_target_fields(target_id, target)
    return { target_ids = { target_id }, targets = target and { target } or {}, target_id = target_id, target = target }
end

local function explicit_targets_fields(entries)
    local ids, refs = {}, {}
    for _, entry in ipairs(entries or {}) do
        append(ids, entry.target_id)
        append(refs, entry.target)
    end
    return { target_ids = ids, targets = refs }
end

local function add_fields(command, fields)
    for key, value in pairs(fields or {}) do command[key] = value end
    return command
end

local function apply_p01_trigger(commands, result)
    local trigger = result and result.p01_trigger
    if not trigger then return end
    local config = Config.passives.C03_P01
    append(commands, {
        type = 'cooldown_delta',
        skill_key = trigger.skill_key,
        amount = -value_at(config.cooldown_reduction, trigger.rank),
    })
    if trigger.rank >= 5 then
        append(commands, {
            type = 'p01_speed',
            move_speed = config.rank5_move_speed,
            duration = config.rank5_move_duration,
        })
    end
end

local function append_p02_commands(state, commands, post, now)
    local trigger = post and post.p02_trigger
    if not trigger then return end
    local config = Config.passives.C03_P02
    local heal_ratio = value_at(config.heal_ratio, trigger.rank)
    if trigger.rank >= 5 and state.current_hp / state.stats.hp_max <= config.rank5_emergency_threshold
        and now >= state.p02_emergency_ready_at then
        heal_ratio = config.rank5_emergency_heal
        state.p02_emergency_ready_at = now + Config.resource.p02_emergency_cooldown
    end
    local payload = { damage_reduction = value_at(config.damage_reduction, trigger.rank), category = 'xindeng' }
    Core.apply_status(state, 'C03_M12_XINDENG_YUWEN', now, config.duration, payload)
    append(commands, {
        type = 'heal_and_guard',
        heal_max_hp = heal_ratio,
        damage_reduction = 0,
        duration = 0,
        guard_key = 'C03_M12_XINDENG_YUWEN',
    })
    apply_modifier(commands, 'C03_M12_XINDENG_YUWEN', 'self', config.duration, payload)
end

local function append_success(state, commands, token, now, context)
    local confirmed, post_or_error = Core.confirm_cast(state, token.id, now)
    if not confirmed then return false, post_or_error end
    append_all(commands, post_or_error.events)
    local _, refund_events = Core.try_tier2_refund(state, confirmed, now)
    append_all(commands, refund_events)
    append_p02_commands(state, commands, post_or_error, now)
    if post_or_error.tier3_echo and #(context.selected_target_ids or {}) > 0 then
        append(commands, {
            type = 'ultimate_echo',
            target_scope = 'selected',
            coefficient = Config.ultimate.tier3_echo_damage,
            break_value = Config.ultimate.tier3_echo_break,
            break_scope = 'boss_confirmed',
            break_event_key = 'mingjie-echo',
            cast_id = token.id,
            can_crit = false,
            area_radius = 4.2,
        })
    end
    return true
end

local function finish_miss(state, commands, token, now, reason)
    local _, events = Core.finish_cast(state, token.id, now, reason)
    append_all(commands, events)
end

local function begin_cast(state, skill_key, rank, now, context)
    local token, events_or_error = Core.begin_cast(state, skill_key, now, context)
    if not token then return nil, events_or_error end
    token.rank = rank
    return token, events_or_error
end

local function valid_hit_event(token, context, event)
    if type(event) ~= 'table' then return nil end
    if event.cast_id ~= token.id then return nil end
    if token.lifecycle_id ~= nil and event.lifecycle_id ~= token.lifecycle_id then return nil end
    if type(event.phase) ~= 'string' then return nil end
    if type(event.damage_dealt) ~= 'number' or event.damage_dealt <= 0 then return nil end
    if event.alive == false then return nil end
    if type(event.hit_time) ~= 'number' or type(event.path_distance) ~= 'number' then return nil end
    local target_id = event.target_id or id_of(event.target or event.target_ref)
    if target_id == nil then return nil end
    local target = target_ref(context, target_id, event.target or event.target_ref)
    if target == nil then return nil end
    local rank = valid_ranks[event.target_rank] and event.target_rank or 'unknown'
    return {
        target_id = target_id,
        target = target,
        rank = rank,
        phase = event.phase,
        hit_time = event.hit_time,
        path_distance = event.path_distance,
    }
end

local function prepare_confirmation_context(token, context)
    context = context or {}
    local snapshot = token.snapshot or {}
    context.actor_id = context.actor_id or snapshot.actor_id
    context.lifecycle_id = context.lifecycle_id or snapshot.lifecycle_id
    context.unit_id = context.unit_id or snapshot.unit_id
    context.primary_target_id = snapshot.primary_target_id
    context.primary_target_ref = snapshot.primary_target_ref
    context.target_id = snapshot.primary_target_id
    context.target = snapshot.primary_target_ref
    context.primary_target = snapshot.primary_target_ref
    context.target_refs_by_id = context.target_refs_by_id or {}
    copy_map(context.target_refs_by_id, snapshot.target_refs_by_id)
    if snapshot.primary_target_id ~= nil and snapshot.primary_target_ref ~= nil then
        context.target_refs_by_id[snapshot.primary_target_id] = snapshot.primary_target_ref
    end
    context.team_target_ids = snapshot.team_target_ids or context.team_target_ids or {}
    context.team_targets = snapshot.team_targets or context.team_targets or {}
    context.committed_team_target_ids = snapshot.team_target_ids or {}
    context.target_meta_by_id = context.target_meta_by_id or {}
    return context
end

local function collect_valid_hits(token, context)
    local events = {}
    for _, event in ipairs(context.hit_events or {}) do
        local normalized = valid_hit_event(token, context, event)
        if normalized then
            context.target_refs_by_id[normalized.target_id] = normalized.target
            local metadata = target_meta(context, normalized.target_id)
            metadata.rank = normalized.rank
            context.target_meta_by_id[normalized.target_id] = metadata
            append(events, normalized)
        end
    end
    return events
end

local function phase_matches(event, names)
    for _, name in ipairs(names) do
        if event.phase == name then return true end
    end
    return false
end

local function select_events(context, events)
    local ids, refs, seen = {}, {}, {}
    for _, event in ipairs(events or {}) do
        if not seen[event.target_id] then
            seen[event.target_id] = true
            append(ids, event.target_id)
            append(refs, event.target)
        end
    end
    context.selected_target_ids = ids
    context.selected_targets = refs
    context.target_count = #ids
end

local function primary_hit(token, events)
    local target_id = token.snapshot and token.snapshot.primary_target_id
    if target_id == nil then return nil end
    for _, event in ipairs(events) do
        if event.target_id == target_id and phase_matches(event, { 'direct', 'impact' }) then return event end
    end
    return nil
end

local function sort_path_hits(events)
    local earliest = {}
    for _, event in ipairs(events) do
        local existing = earliest[event.target_id]
        if not existing
            or event.hit_time < existing.hit_time
            or (event.hit_time == existing.hit_time and event.path_distance < existing.path_distance)
            or (event.hit_time == existing.hit_time and event.path_distance == existing.path_distance
                and tostring(event.target_id) < tostring(existing.target_id)) then
            earliest[event.target_id] = event
        end
    end
    local result = {}
    for _, event in pairs(earliest) do append(result, event) end
    table.sort(result, function(left, right)
        if left.hit_time ~= right.hit_time then return left.hit_time < right.hit_time end
        if left.path_distance ~= right.path_distance then return left.path_distance < right.path_distance end
        return tostring(left.target_id) < tostring(right.target_id)
    end)
    return result
end

local function candidates(context, key, primary_id, require_mark_priority, max_distance)
    local result, seen = {}, {}
    for _, value in ipairs(context[key] or {}) do
        local target = value.target or value.target_ref or value.unit or value
        local target_id = value.target_id or value.id or id_of(target)
        local distance = value.distance
        if target_id ~= nil and target_id ~= primary_id and type(distance) == 'number'
            and (max_distance == nil or distance <= max_distance) and not seen[target_id] then
            local ref = target_ref(context, target_id, target)
            if ref then
                seen[target_id] = true
                append(result, {
                    target_id = target_id,
                    target = ref,
                    distance = distance,
                    marked = target_meta(context, target_id).private_minghen == true,
                })
            end
        end
    end
    table.sort(result, function(left, right)
        if require_mark_priority and left.marked ~= right.marked then return left.marked end
        if left.distance ~= right.distance then return left.distance < right.distance end
        return tostring(left.target_id) < tostring(right.target_id)
    end)
    return result
end

local function target_available(target)
    if target == nil then return false end
    if type(target.is_exist) == 'function' and not target:is_exist() then return false end
    if type(target.is_alive) == 'function' and not target:is_alive() then return false end
    return true
end

local function approved_team_purge(context)
    local allowed, ids, refs, seen = {}, {}, {}, {}
    for _, id in ipairs(context.committed_team_target_ids or context.team_target_ids or {}) do allowed[id] = true end
    local success_ids = context.team_purge_success_ids or {}
    local success_refs = context.team_purge_success_targets or {}
    for index, id in ipairs(success_ids) do
        local ref = success_refs[index] or target_ref(context, id)
        if allowed[id] and id ~= context.unit_id and not seen[id] and target_available(ref) then
            seen[id] = true
            append(ids, id)
            append(refs, ref)
        end
    end
    for _, ref in ipairs(success_refs) do
        local id = id_of(ref)
        if allowed[id] and id ~= context.unit_id and not seen[id] and target_available(ref) then
            seen[id] = true
            append(ids, id)
            append(refs, ref)
        end
    end
    context.team_purge_success_ids = ids
    context.team_purge_success_targets = refs
    return ids, refs
end

local function append_pulse(commands, token, skill_key, delay, coefficient, radius, break_value)
    local command = {
        type = 'delayed_damage',
        target_scope = 'selected',
        pulse_key = skill_key,
        delay = delay,
        coefficient = coefficient,
        area_radius = radius,
        can_crit = false,
        cast_id = token.id,
        lifecycle_id = token.lifecycle_id,
    }
    if break_value then
        command.break_value = break_value
        command.break_scope = 'boss_only'
        command.break_event_key = skill_key .. '-pulse-' .. tostring(delay)
    end
    append(commands, command)
end

local function resolve_a01(state, token, now, context, events)
    local hit = primary_hit(token, events)
    local commands = {}
    if not hit then
        finish_miss(state, commands, token, now, 'no-effective-hit')
        return { ok = true, cast_id = token.id, missed = true, commands = commands }
    end
    select_events(context, { hit })
    local ability = Config.abilities.C03_A01
    append(commands, add_fields({
        type = 'damage', target_scope = 'explicit', coefficient = value_at(ability.damage, token.rank),
        break_value = ability.break_value, break_scope = 'boss_confirmed', break_event_key = 'a01-direct',
        cast_id = token.id, can_crit = true,
    }, explicit_target_fields(hit.target_id, hit.target)))
    if token.rank >= 5 and target_meta(context, hit.target_id).private_minghen == true then
        append(commands, add_fields({
            type = 'delayed_damage', delay = 0.08, target_scope = 'explicit', coefficient = ability.rank5_minghen_echo,
            break_value = 0, break_scope = 'boss_confirmed', break_event_key = 'a01-minghen-echo',
            cast_id = token.id, can_crit = false,
        }, explicit_target_fields(hit.target_id, hit.target)))
    end
    local ok, error_code = append_success(state, commands, token, now, context)
    if not ok then return { ok = false, error = error_code, cast_id = token.id, commands = commands } end
    local result = Core.gain_seal(state, 'C03_A01', now)
    if result then
        append_all(commands, result.events)
        apply_p01_trigger(commands, result)
    end
    return { ok = true, cast_id = token.id, skill_key = token.skill_key, commands = commands }
end

local function resolve_a02(state, token, now, context, events)
    local outbound, returning = {}, {}
    for _, event in ipairs(events) do
        if event.phase == 'outbound' then append(outbound, event) end
        if event.phase == 'return' then append(returning, event) end
    end
    outbound, returning = sort_path_hits(outbound), sort_path_hits(returning)
    local commands, all = {}, {}
    for _, event in ipairs(outbound) do append(all, event) end
    for _, event in ipairs(returning) do append(all, event) end
    if #all == 0 then
        finish_miss(state, commands, token, now, 'no-effective-hit')
        return { ok = true, cast_id = token.id, missed = true, commands = commands }
    end
    select_events(context, all)
    local ability = Config.abilities.C03_A02
    for index, path in ipairs({ outbound, returning }) do
        if #path > 0 then
            append(commands, add_fields({
                type = 'damage', target_scope = 'explicit', coefficient = value_at(ability.damage_per_path, token.rank),
                break_value = ability.break_per_path, break_scope = 'boss_confirmed',
                break_event_key = index == 1 and 'a02-outbound' or 'a02-return', cast_id = token.id,
                can_crit = true, hit_index = index,
            }, explicit_targets_fields(path)))
        end
    end
    if token.rank >= 5 then
        local marked = {}
        for _, event in ipairs(all) do
            if target_meta(context, event.target_id).private_minghen == true then append(marked, event) end
        end
        if #marked > 0 then
            append(commands, add_fields({
                type = 'extend_modifier_once', key = 'C03_M02_MINGHEN', target_scope = 'explicit',
                duration = ability.rank5_minghen_extend, reason = 'C03_A02_rank5',
            }, explicit_targets_fields(marked)))
        end
    end
    local ok, error_code = append_success(state, commands, token, now, context)
    if not ok then return { ok = false, error = error_code, cast_id = token.id, commands = commands } end
    local result = Core.gain_seal(state, 'C03_A02', now)
    if result then
        append_all(commands, result.events)
        apply_p01_trigger(commands, result)
    end
    return { ok = true, cast_id = token.id, skill_key = token.skill_key, commands = commands }
end

local function resolve_a03(state, token, now, context, events)
    local hit = primary_hit(token, events)
    local commands = {}
    if not hit then
        finish_miss(state, commands, token, now, 'no-effective-hit')
        return { ok = true, cast_id = token.id, missed = true, commands = commands }
    end
    select_events(context, { hit })
    local ability = Config.abilities.C03_A03
    append(commands, add_fields({
        type = 'damage', target_scope = 'explicit', coefficient = value_at(ability.damage, token.rank),
        break_value = ability.break_value, break_scope = 'boss_confirmed', break_event_key = 'a03-direct',
        cast_id = token.id, can_crit = true,
    }, explicit_target_fields(hit.target_id, hit.target)))
    local marker_duration = value_at(ability.marker_duration, token.rank)
    local p03 = passive_level(state, 'C03_P03')
    if p03 > 0 then marker_duration = marker_duration + value_at(Config.passives.C03_P03.marker_duration_bonus, p03) end
    apply_modifier(commands, 'C03_M02_MINGHEN', 'explicit', marker_duration, { source_skill = 'C03_A03' }, explicit_target_fields(hit.target_id, hit.target))

    if token.spent > 0 then
        local reflections = candidates(context, 'reflection_candidates', hit.target_id, true, 4.0)
        local primary_reflection = reflections[1]
        local coefficient = value_at(ability.reflection, token.rank)
        if primary_reflection then
            append(commands, add_fields({
                type = 'delayed_damage', delay = 0.08, target_scope = 'explicit', coefficient = coefficient,
                break_value = ability.reflection_break, break_scope = 'boss_confirmed', break_event_key = 'a03-reflection',
                cast_id = token.id, can_crit = false,
            }, explicit_target_fields(primary_reflection.target_id, primary_reflection.target)))
        else
            append(commands, add_fields({
                type = 'delayed_damage', delay = 0.08, target_scope = 'explicit', coefficient = coefficient * 0.70,
                break_value = ability.reflection_break * 0.70, break_scope = 'boss_confirmed', break_event_key = 'a03-reflection-fallback',
                cast_id = token.id, can_crit = false, fallback_to_primary = true,
            }, explicit_target_fields(hit.target_id, hit.target)))
        end
        local extra_ratio = token.mingtai and value_at(ability.mingtao_extra_reflection, token.rank) or 0
        if extra_ratio and extra_ratio > 0 and reflections[2] then
            append(commands, add_fields({
                type = 'delayed_damage', delay = 0.14, target_scope = 'explicit', coefficient = coefficient * extra_ratio,
                break_value = ability.reflection_break * extra_ratio, break_scope = 'boss_confirmed', break_event_key = 'a03-mingtai-reflection',
                cast_id = token.id, can_crit = false,
            }, explicit_target_fields(reflections[2].target_id, reflections[2].target)))
        end
    end
    local ok, error_code = append_success(state, commands, token, now, context)
    return { ok = ok, error = error_code, cast_id = token.id, skill_key = token.skill_key, commands = commands }
end

local function append_a05_pulses(commands, token)
    local ability = Config.abilities.C03_A05
    for index = 1, ability.pulse_count do
        append_pulse(
            commands,
            token,
            'C03_A05',
            index * ability.duration / ability.pulse_count,
            value_at(ability.pulse_damage, token.rank),
            2.4,
            ability.break_value * 0.25
        )
    end
end

local function resolve_a05(state, token, now, context, events)
    local impacts = {}
    for _, event in ipairs(events) do
        if phase_matches(event, { 'impact', 'direct' }) then append(impacts, event) end
    end
    impacts = sort_path_hits(impacts)
    local commands = {}
    append_a05_pulses(commands, token)
    if #impacts == 0 then
        finish_miss(state, commands, token, now, 'no-effective-hit')
        return { ok = true, cast_id = token.id, missed = true, commands = commands }
    end
    select_events(context, impacts)
    local ability = Config.abilities.C03_A05
    append(commands, add_fields({
        type = 'damage', target_scope = 'explicit', coefficient = value_at(ability.impact_damage, token.rank),
        break_value = ability.break_value, break_scope = 'boss_confirmed', break_event_key = 'a05-impact',
        cast_id = token.id, can_crit = true,
    }, explicit_targets_fields(impacts)))
    if token.spent > 0 then
        local slow = value_at(ability.slow, token.rank)
        local p07 = passive_level(state, 'C03_P07')
        if p07 > 0 then slow = slow + value_at(Config.passives.C03_P07.slow_bonus, p07) end
        local mark_duration = ability.mark_duration
        if p07 > 0 then mark_duration = mark_duration + value_at(Config.passives.C03_P07.mark_duration_bonus, p07) end
        apply_modifier(commands, 'C03_M05_LUYUE', 'selected', ability.slow_duration, {
            normal_slow = slow, highest_value_refresh = true,
        })
        apply_modifier(commands, 'C03_M06_LUYIN', 'selected', mark_duration, { source_skill = 'C03_A05' })
        if token.mingtai then
            append(commands, {
                type = 'control', target_scope = 'selected', normal_duration = ability.normal_root_duration,
                elite_duration = ability.elite_root_duration, boss_converts_to_break = true,
                boss_break_value = ability.mingtao_boss_break, break_scope = 'boss_confirmed',
                break_event_key = 'a05-mingtai-control', cast_id = token.id,
            })
        end
    end
    local ok, error_code = append_success(state, commands, token, now, context)
    return { ok = ok, error = error_code, cast_id = token.id, skill_key = token.skill_key, commands = commands }
end

local function resolve_a06(state, token, now, context, events)
    local hit = primary_hit(token, events)
    local commands = {}
    if not hit then
        finish_miss(state, commands, token, now, 'no-effective-hit')
        return { ok = true, cast_id = token.id, missed = true, commands = commands }
    end
    select_events(context, { hit })
    local ability = Config.abilities.C03_A06
    local coefficient = value_at(ability.damage, token.rank) + value_at(ability.per_seal_damage, token.rank) * token.spent
    local break_value = ability.break_value + ability.break_per_seal * token.spent
    local marked = target_meta(context, hit.target_id).private_minghen == true
    local p03 = passive_level(state, 'C03_P03')
    if marked and p03 > 0 then coefficient = coefficient * (1 + value_at(Config.passives.C03_P03.a06_mark_damage, p03)) end
    local p04 = passive_level(state, 'C03_P04')
    if token.mingtai and p04 > 0 then
        coefficient = coefficient + value_at(Config.passives.C03_P04.mingtao_a06_damage, p04)
        break_value = break_value + value_at(Config.passives.C03_P04.mingtao_a06_break, p04)
    end
    append(commands, add_fields({
        type = 'damage', target_scope = 'explicit', coefficient = coefficient,
        break_value = break_value, break_scope = 'boss_confirmed', break_event_key = 'a06-direct',
        cast_id = token.id, can_crit = true,
    }, explicit_target_fields(hit.target_id, hit.target)))
    if marked then
        remove_modifier(commands, 'C03_M02_MINGHEN', 'explicit', explicit_target_fields(hit.target_id, hit.target))
        local echo = value_at(ability.minghen_echo, token.rank) + (p03 >= 5 and Config.passives.C03_P03.rank5_echo_bonus or 0)
        append(commands, add_fields({
            type = 'delayed_damage', delay = 0.10, target_scope = 'explicit', coefficient = echo,
            break_value = 0, break_scope = 'boss_confirmed', break_event_key = 'a06-minghen-echo',
            cast_id = token.id, can_crit = false,
        }, explicit_target_fields(hit.target_id, hit.target)))
        if token.mingtai and p04 >= 5 then
            append(commands, { type = 'cooldown_delta', skill_key = 'C03_A03', amount = -Config.passives.C03_P04.rank5_a03_cooldown_reduction })
        end
    end
    if token.mingtai then
        local pierce = candidates(context, 'pierce_candidates', hit.target_id, false, nil)[1]
        if pierce then
            append(commands, add_fields({
                type = 'damage', target_scope = 'explicit', coefficient = coefficient * ability.mingtao_pierce_ratio,
                break_value = break_value * ability.mingtao_pierce_ratio, break_scope = 'boss_confirmed',
                break_event_key = 'a06-mingtai-pierce', cast_id = token.id, can_crit = true,
            }, explicit_target_fields(pierce.target_id, pierce.target)))
        end
    end
    local ok, error_code = append_success(state, commands, token, now, context)
    return { ok = ok, error = error_code, cast_id = token.id, skill_key = token.skill_key, commands = commands }
end

local function append_a08_team_support(state, commands, rank, context)
    local success_ids, success_targets = approved_team_purge(context)
    if #success_ids == 0 then return false end
    local p08 = passive_level(state, 'C03_P08')
    local duration = 2.0 + (p08 > 0 and value_at(Config.passives.C03_P08.duration_bonus, p08) or 0)
    local speed = value_at({ 0.12, 0.14, 0.16, 0.18, 0.20 }, rank)
    if p08 > 0 then speed = speed + value_at(Config.passives.C03_P08.move_speed_bonus, p08) end
    apply_modifier(commands, 'C03_M10_TONGLV_QINGMING', 'explicit', duration, {
        move_speed = speed, highest_value_refresh = true,
    }, { target_ids = success_ids, targets = success_targets })
    return true
end

local function append_a08_pulses(commands, token)
    local ability = Config.abilities.C03_A08
    for index = 1, ability.pulse_count do
        append_pulse(
            commands,
            token,
            'C03_A08',
            index * ability.duration / ability.pulse_count,
            value_at(ability.pulse_damage, token.rank),
            3.5,
            nil
        )
    end
end

local function resolve_a08(state, token, now, context, events)
    local impacts = {}
    for _, event in ipairs(events) do
        if phase_matches(event, { 'impact', 'direct' }) then append(impacts, event) end
    end
    impacts = sort_path_hits(impacts)
    local commands = {}
    append_a08_pulses(commands, token)
    local ability = Config.abilities.C03_A08
    if #impacts > 0 then
        select_events(context, impacts)
        append(commands, add_fields({
            type = 'damage', target_scope = 'explicit', coefficient = value_at(ability.impact_damage, token.rank),
            break_value = value_at(ability.boss_break, token.rank), break_scope = 'boss_confirmed',
            break_event_key = 'a08-impact', cast_id = token.id, can_crit = true,
        }, explicit_targets_fields(impacts)))
        local controllable, marked_bosses = {}, {}
        for _, event in ipairs(impacts) do
            local metadata = target_meta(context, event.target_id)
            if metadata.rank == 'normal' or metadata.rank == 'elite' then append(controllable, event) end
            if metadata.rank == 'boss' and metadata.private_luyin == true then append(marked_bosses, event) end
        end
        if #controllable > 0 then
            apply_modifier(commands, 'C03_M09_JINGLV_ZHENYA', 'explicit', ability.duration, { source_skill = 'C03_A08' }, explicit_targets_fields(controllable))
            append(commands, add_fields({
                type = 'control', target_scope = 'explicit', normal_duration = value_at(ability.normal_root, token.rank),
                elite_duration = value_at(ability.normal_root, token.rank) * ability.elite_root_ratio,
                cast_id = token.id,
            }, explicit_targets_fields(controllable)))
        end
        if #marked_bosses > 0 then
            append(commands, add_fields({
                type = 'break', target_scope = 'explicit', break_value = ability.luyin_break,
                break_scope = 'boss_confirmed', break_event_key = 'a08-luyin', cast_id = token.id,
            }, explicit_targets_fields(marked_bosses)))
            if passive_level(state, 'C03_P07') >= 5 then
                append(commands, add_fields({
                    type = 'break', target_scope = 'explicit', break_value = Config.passives.C03_P07.rank5_marked_break,
                    break_scope = 'boss_confirmed', break_event_key = 'a08-p07', cast_id = token.id,
                }, explicit_targets_fields(marked_bosses)))
            end
        end
    end
    local team_purged = append_a08_team_support(state, commands, token.rank, context)
    if #impacts == 0 then
        if team_purged and passive_level(state, 'C03_P08') >= 5 then
            local _, refund_events = Core.refund_seal(state, now, 'C03_P08', 'refunded')
            append_all(commands, refund_events)
        end
        finish_miss(state, commands, token, now, 'no-effective-hit')
        return { ok = true, cast_id = token.id, missed = true, commands = commands }
    end
    local ok, error_code = append_success(state, commands, token, now, context)
    if not ok then return { ok = false, error = error_code, cast_id = token.id, commands = commands } end
    if team_purged and passive_level(state, 'C03_P08') >= 5 then
        local _, refund_events = Core.refund_seal(state, now, 'C03_P08', 'refunded')
        append_all(commands, refund_events)
    end
    return { ok = true, cast_id = token.id, skill_key = token.skill_key, commands = commands }
end

local function resolve_hit_skill(state, token, now, context)
    local events = collect_valid_hits(token, context)
    if token.skill_key == 'C03_A01' then return resolve_a01(state, token, now, context, events) end
    if token.skill_key == 'C03_A02' then return resolve_a02(state, token, now, context, events) end
    if token.skill_key == 'C03_A03' then return resolve_a03(state, token, now, context, events) end
    if token.skill_key == 'C03_A05' then return resolve_a05(state, token, now, context, events) end
    if token.skill_key == 'C03_A06' then return resolve_a06(state, token, now, context, events) end
    if token.skill_key == 'C03_A08' then return resolve_a08(state, token, now, context, events) end
    return { ok = false, error = 'unsupported-cast', commands = {} }
end

local function use_a04(state, rank, now, context)
    local token, events_or_error = begin_cast(state, 'C03_A04', rank, now, context)
    if not token then return { ok = false, error = events_or_error, commands = {} } end
    local ability = Config.abilities.C03_A04
    local p05 = passive_level(state, 'C03_P05')
    local shield = value_at(ability.shield_ratio, rank)
    local reduction = value_at(ability.damage_reduction, rank)
    if p05 > 0 then
        shield = shield * (1 + value_at(Config.passives.C03_P05.shield_bonus, p05))
        reduction = reduction + value_at(Config.passives.C03_P05.reduction_bonus, p05)
    end
    local commands = state_commands(events_or_error)
    local shield_payload = { max_hp_ratio = shield, cast_id = token.id, protected = false, rank = rank }
    Core.apply_status(state, 'C03_M03_CHENGXIN_SHIELD', now, ability.shield_duration, shield_payload)
    apply_modifier(commands, 'C03_M03_CHENGXIN_SHIELD', 'self', ability.shield_duration, shield_payload)
    if token.spent > 0 then
        local guard_payload = { damage_reduction = reduction, cast_id = token.id, protected = false, rank = rank }
        Core.apply_status(state, 'C03_M04_CHENGXIN_GUARD', now, ability.guard_duration, guard_payload)
        apply_modifier(commands, 'C03_M04_CHENGXIN_GUARD', 'self', ability.guard_duration, guard_payload)
    end
    if token.spent == 0 or (token.mingtai and context.self_purge_success == true) then
        local ok, error_code = append_success(state, commands, token, now, context)
        return { ok = ok, error = error_code, cast_id = token.id, commands = commands }
    end
    return { ok = true, cast_id = token.id, pending_protection = true, commands = commands }
end

local function use_a07(state, rank, now, context)
    local token, events_or_error = begin_cast(state, 'C03_A07', rank, now, context)
    if not token then return { ok = false, error = events_or_error, commands = {} } end
    local ability = Config.abilities.C03_A07
    local p06 = passive_level(state, 'C03_P06')
    local shield = value_at(ability.shield_ratio, rank)
    if p06 > 0 then shield = shield * (1 + value_at(Config.passives.C03_P06.shield_bonus, p06)) end
    local commands = state_commands(events_or_error)
    local shield_payload = { max_hp_ratio = shield, cast_id = token.id, protected = false, rank = rank }
    Core.apply_status(state, 'C03_M07_FANZHAO_SHIELD', now, ability.shield_duration, shield_payload)
    apply_modifier(commands, 'C03_M07_FANZHAO_SHIELD', 'self', ability.shield_duration, shield_payload)
    if token.mingtai then
        local team_duration = ability.team_shield_duration
        if rank >= 3 and context.self_purge_success == true then team_duration = team_duration + ability.rank3_team_extension end
        apply_modifier(commands, 'C03_M08_TONGMING_SHIELD', 'team', team_duration, {
            max_hp_ratio = value_at(ability.team_shield_ratio, rank), source_skill = 'C03_A07',
        })
    end
    if context.self_purge_success == true then
        local ok, error_code = append_success(state, commands, token, now, context)
        return { ok = ok, error = error_code, cast_id = token.id, commands = commands }
    end
    return { ok = true, cast_id = token.id, pending_protection = true, commands = commands }
end

function M.use(state, skill_key, rank, now, context)
    context = context or {}
    local ability, error_code = validate_rank(skill_key, rank)
    if not ability then return { ok = false, error = error_code, commands = {} } end
    if hit_confirmed_skills[skill_key] then return { ok = false, error = 'hit-confirmation-required', commands = {} } end
    if skill_key == 'C03_A04' then return use_a04(state, rank, now, context) end
    if skill_key == 'C03_A07' then return use_a07(state, rank, now, context) end
    return { ok = false, error = 'unsupported-skill', commands = {} }
end

function M.commit_skill(state, skill_key, rank, now, context)
    context = context or {}
    local ability, error_code = validate_rank(skill_key, rank)
    if not ability then return { ok = false, error = error_code, commands = {} } end
    if not hit_confirmed_skills[skill_key] then return { ok = false, error = 'not-hit-confirmed-skill', commands = {} } end
    if (skill_key == 'C03_A05' or skill_key == 'C03_A08') and not context.target_point then
        return { ok = false, error = 'cast-point-required', commands = {} }
    end
    if (skill_key == 'C03_A01' or skill_key == 'C03_A03' or skill_key == 'C03_A06')
        and context.primary_target_id == nil then
        return { ok = false, error = 'primary-target-required', commands = {} }
    end
    local token, events_or_error = begin_cast(state, skill_key, rank, now, context)
    if not token then return { ok = false, error = events_or_error, commands = {} } end
    return {
        ok = true,
        cast_id = token.id,
        skill_key = skill_key,
        cast_snapshot = token.snapshot,
        commands = state_commands(events_or_error),
    }
end

function M.confirm_skill_hit(state, cast_id, now, context)
    local token = state.casts[cast_id]
    if not token then return { ok = false, error = 'unknown-cast', commands = {} } end
    context = prepare_confirmation_context(token, context)
    if token.lifecycle_id ~= nil and context.lifecycle_id ~= token.lifecycle_id then
        return { ok = false, error = 'stale-lifecycle', commands = {} }
    end
    context.cast_id = cast_id
    return resolve_hit_skill(state, token, now, context)
end

function M.finish_skill_miss(state, cast_id, now, reason)
    local token, events_or_error = Core.finish_cast(state, cast_id, now, reason)
    if not token then return { ok = false, error = events_or_error, commands = {} } end
    return {
        ok = true,
        cast_id = cast_id,
        skill_key = token.skill_key,
        commands = state_commands(events_or_error),
    }
end

function M.on_damage_taken(state, now, context)
    context = context or {}
    local qualification = context.protection_qualification
    if type(qualification) ~= 'table' or qualification.effective_protection ~= true then
        return { ok = false, error = 'not-effective-protection', commands = {} }
    end
    if type(qualification.cast_id) ~= 'number' or type(qualification.effect_key) ~= 'string' then
        return { ok = false, error = 'protection-attribution-required', commands = {} }
    end
    if (qualification.absorbed or 0) <= 0 and (qualification.reduced or 0) <= 0 then
        return { ok = false, error = 'not-effective-protection', commands = {} }
    end
    if qualification.lifecycle_id ~= nil and state.lifecycle_id ~= nil and qualification.lifecycle_id ~= state.lifecycle_id then
        return { ok = false, error = 'stale-lifecycle', commands = {} }
    end
    if qualification.target_id ~= nil and context.unit_id ~= nil and qualification.target_id ~= context.unit_id then
        return { ok = false, error = 'protection-target-mismatch', commands = {} }
    end
    local token = state.casts[qualification.cast_id]
    if not token then return { ok = false, error = 'no-protection-window', commands = {} } end
    local allowed = {
        C03_M03_CHENGXIN_SHIELD = 'C03_A04',
        C03_M04_CHENGXIN_GUARD = 'C03_A04',
        C03_M07_FANZHAO_SHIELD = 'C03_A07',
    }
    if allowed[qualification.effect_key] ~= token.skill_key then
        return { ok = false, error = 'protection-attribution-mismatch', commands = {} }
    end
    local status = Core.get_status(state, qualification.effect_key, now)
    if not status or status.payload.cast_id ~= token.id or status.payload.protected then
        return { ok = false, error = 'no-protection-window', commands = {} }
    end
    status.payload.protected = true
    if token.skill_key == 'C03_A04' then
        for _, key in ipairs({ 'C03_M03_CHENGXIN_SHIELD', 'C03_M04_CHENGXIN_GUARD' }) do
            local related = Core.get_status(state, key, now)
            if related and related.payload.cast_id == token.id then related.payload.protected = true end
        end
    end
    local commands = {}
    local ok, error_code = append_success(state, commands, token, now, context)
    if not ok then return { ok = false, error = error_code, commands = commands } end
    if token.skill_key == 'C03_A04' then
        local p05 = passive_level(state, 'C03_P05')
        if p05 >= 5 then
            append(commands, { type = 'cooldown_delta', skill_key = 'C03_A04', amount = -Config.passives.C03_P05.rank5_a04_cooldown_reduction })
        end
        if token.rank >= 5 then
            append(commands, {
                type = 'a04_protection_speed', move_speed = Config.abilities.C03_A04.rank5_move_speed,
                duration = Config.abilities.C03_A04.rank5_move_duration,
            })
        end
    else
        local p06 = passive_level(state, 'C03_P06')
        if p06 > 0 then
            append(commands, {
                type = 'heal_and_guard', heal_max_hp = value_at(Config.passives.C03_P06.heal_ratio, p06),
                damage_reduction = 0, duration = 0, guard_key = 'C03_M12_XINDENG_YUWEN',
            })
        end
        if token.rank >= 5 then
            append(commands, {
                type = 'a07_protection_speed', move_speed = Config.abilities.C03_A07.rank5_move_speed,
                duration = Config.abilities.C03_A07.rank5_move_duration,
            })
        end
    end
    return { ok = true, kind = 'effective-protection', commands = commands }
end

function M.activate_ultimate(state, now)
    local realm, event_or_error = Core.activate_ultimate(state, now)
    if not realm then return { ok = false, error = event_or_error, commands = {} } end
    event_or_error.expires_at = realm.expires_at
    local commands = { event_or_error, {
        type = 'damage', target_scope = 'selected', coefficient = Config.ultimate.activation_damage,
        break_value = Config.ultimate.activation_break, break_scope = 'boss_confirmed',
        break_event_key = 'u01-activation', can_crit = true,
    } }
    apply_modifier(commands, 'C03_M11_MINGJIE', 'self', realm.expires_at - now, { tier = realm.tier })
    return { ok = true, commands = commands }
end

function M.tick(state, now)
    local tick = Core.tick(state, now)
    local commands = state_commands(tick.events)
    for _, status in ipairs(tick.expired_statuses) do
        remove_modifier(commands, status.key, 'self')
        if status.key == 'C03_M07_FANZHAO_SHIELD' and status.payload.protected and passive_level(state, 'C03_P06') >= 5 then
            local residual = status.payload.max_hp_ratio * Config.passives.C03_P06.rank5_residual_ratio
            local duration = Config.passives.C03_P06.rank5_residual_duration
            local payload = { max_hp_ratio = residual, cast_id = nil, protected = false, residual = true, rank = status.payload.rank }
            Core.apply_status(state, 'C03_M07_FANZHAO_SHIELD', now, duration, payload)
            apply_modifier(commands, 'C03_M07_FANZHAO_SHIELD', 'self', duration, payload)
        end
    end
    return commands
end

function M.requires_hit_confirmation(skill_key)
    return hit_confirmed_skills[skill_key] == true
end

-- Public bridge vocabulary. The existing names remain for compatibility with
-- the first offline package, while new map code can use the staged contract.
M.begin_cast = M.commit_skill
M.confirm_hit = M.confirm_skill_hit
M.finalize_cast = M.finish_skill_miss

return M
