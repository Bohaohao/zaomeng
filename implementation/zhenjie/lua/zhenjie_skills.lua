local Config = require 'zhenjie_config'
local Core = require 'zhenjie_core'

local M = {}

local function append(list, value)
    list[#list + 1] = value
end

local function append_all(target, source)
    for _, value in ipairs(source or {}) do
        append(target, value)
    end
end

local function value_at(values, rank)
    return values and values[rank] or nil
end

local function passive_level(state, key)
    return state.passive_levels[key] or 0
end

local function target_count(context)
    return math.max(0, math.floor((context and context.target_count) or 0))
end

local function target_meta(context, target_id)
    local metadata = context and context.target_meta_by_id
    if type(metadata) ~= 'table' then
        return {}
    end
    return metadata[target_id] or metadata[tostring(target_id)] or {}
end

local function matching_targets(context, predicate)
    local ids = (context and (context.target_ids or context.selected_target_ids)) or {}
    local refs = (context and (context.targets or context.selected_targets)) or {}
    local matched_ids, matched_refs = {}, {}
    for index, target_id in ipairs(ids) do
        local metadata = target_meta(context, target_id)
        if predicate(metadata, target_id, refs[index]) then
            matched_ids[#matched_ids + 1] = target_id
            matched_refs[#matched_refs + 1] = refs[index]
        end
    end
    return matched_ids, matched_refs
end

local function validate_rank(skill_key, rank)
    local ability = Config.abilities[skill_key]
    if not ability then
        return nil, 'unknown-skill'
    end
    if type(rank) ~= 'number' or rank < 1 or rank > ability.max_level then
        return nil, 'invalid-rank'
    end
    return ability
end

local function state_commands(events)
    local commands = {}
    for _, event in ipairs(events or {}) do
        append(commands, event)
    end
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
    for name, value in pairs(extra or {}) do
        command[name] = value
    end
    append(commands, command)
end

local function remove_modifier(commands, key, target_scope, extra)
    local command = { type = 'remove_modifier', key = key, target_scope = target_scope }
    for name, value in pairs(extra or {}) do
        command[name] = value
    end
    append(commands, command)
end

local function gain_generator(state, skill_key, amount, now)
    return Core.gain_generator_guard(state, amount, {
        now = now,
        generator_key = skill_key,
        effective = true,
    })
end

local function p02_command(state, token)
    local payload = token and token.passive_trigger
    if not payload then
        return nil
    end
    return {
        type = 'heal_and_guard',
        heal_max_hp = payload.heal_max_hp,
        damage_reduction = payload.damage_reduction,
        duration = payload.duration,
        guard_key = payload.guard_key,
    }
end

local function parry_window(state, rank, now)
    local ability = Config.abilities.C02_A04
    local p05 = passive_level(state, 'C02_P05')
    local duration = ability.guard_window + (p05 > 0 and value_at(Config.passives.C02_P05.window_bonus, p05) or 0)
    local payload = {
        rank = rank,
        damage_reduction = value_at(ability.damage_reduction, rank),
        counter_damage = value_at(ability.counter_damage, rank),
        guard_on_success = value_at(ability.guard_on_success, rank),
        triggered = false,
    }
    Core.apply_status(state, 'C02_M02_GUJIA', now, duration, payload)
    return duration, payload
end

local function generator_skill(state, skill_key, rank, now, context)
    local ability = Config.abilities[skill_key]
    local count = target_count(context)
    local commands = {}

    if skill_key == 'C02_A01' then
        if count > 0 then
            local extra = math.min(math.max(0, count - 1), ability.extra_target_cap)
            local events = gain_generator(state, skill_key, value_at(ability.guard, rank) + extra * ability.extra_guard_per_target, now)
            append_all(commands, state_commands(events))
            append(commands, { type = 'damage', coefficient = value_at(ability.damage, rank), break_value = ability.break_value, can_crit = true })
        end
    elseif skill_key == 'C02_A02' then
        if count > 0 then
            local events = gain_generator(state, skill_key, value_at(ability.guard, rank), now)
            append_all(commands, state_commands(events))
            append(commands, {
                type = 'damage', coefficient = value_at(ability.damage, rank),
                break_value = ability.break_value, can_crit = true,
            })
            if rank >= 3 then
                local ids, refs = matching_targets(context, function(metadata)
                    return metadata.rank == 'elite' or metadata.rank == 'boss'
                end)
                if #ids > 0 then
                    append(commands, {
                        type = 'break', target_scope = 'explicit', target_ids = ids, targets = refs,
                        break_value = ability.rank3_elite_break,
                    })
                end
            end
            apply_modifier(commands, 'C02_M06_JIEDING_SLOW', 'selected', ability.slow_duration, {
                normal_slow = value_at(ability.slow, rank), highest_value_refresh = true,
            })
        end
    elseif skill_key == 'C02_A03' then
        local hits = math.min(ability.hit_count, math.max(0, math.floor(context.hit_count or ability.hit_count)))
        if count > 0 and hits > 0 then
            local amount = hits * ability.guard_per_hit
            local same_target = hits == ability.hit_count and (context.same_target_all or context.primary_hit_twice)
            if same_target then
                amount = amount + ability.same_target_guard_bonus
            end
            local events = gain_generator(state, skill_key, amount, now)
            append_all(commands, state_commands(events))
            for index = 1, hits do
                append(commands, {
                    type = 'damage', coefficient = value_at(ability.damage_per_hit, rank), break_value = ability.break_per_hit,
                    can_crit = true, hit_index = index,
                })
            end
            if same_target then
                Core.apply_status(state, 'C02_P03_READY', now, 6.0, { rank = passive_level(state, 'C02_P03') })
                if rank >= 5 then
                    append(commands, { type = 'cooldown_delta', skill_key = 'C02_A06', amount = -ability.rank5_a06_cooldown_reduction })
                end
            end
        end
    elseif skill_key == 'C02_A04' then
        local duration, payload = parry_window(state, rank, now)
        apply_modifier(commands, 'C02_M02_GUJIA', 'self', duration, payload)
    elseif skill_key == 'C02_A05' then
        local p07 = passive_level(state, 'C02_P07')
        local mark_duration = ability.mark_duration + (p07 > 0 and value_at(Config.passives.C02_P07.mark_duration_bonus, p07) or 0)
        local slow = value_at(ability.slow, rank) + (p07 > 0 and value_at(Config.passives.C02_P07.slow_bonus, p07) or 0)
        if count > 0 then
            local events = gain_generator(state, skill_key, value_at(ability.guard, rank), now)
            append_all(commands, state_commands(events))
            append(commands, { type = 'damage', coefficient = value_at(ability.impact_damage, rank), break_value = ability.break_value, can_crit = true })
            apply_modifier(commands, 'C02_M06_JIEDING_SLOW', 'selected', ability.slow_duration, {
                normal_slow = slow, highest_value_refresh = true,
            })
            apply_modifier(commands, 'C02_M07_JIEDING_MARK', 'selected', mark_duration, { source_skill = skill_key })
        end
        -- The field remains at the synchronized cast point even when its first impact misses.
        for index = 1, ability.pulse_count do
            append(commands, {
                type = 'delayed_damage', delay = index * ability.duration / ability.pulse_count,
                coefficient = value_at(ability.pulse_damage, rank), break_value = ability.break_value * 0.25,
                area_radius = 3.5, can_crit = false,
            })
        end
    end
    return { ok = true, commands = commands }
end

local function a06_commands(state, token, rank, now, context)
    local ability = Config.abilities.C02_A06
    local commands = {}
    local coefficient = value_at(ability.damage, rank)
    local break_value = ability.break_value
    local p03 = Core.get_status(state, 'C02_P03_READY', now)
    if p03 and p03.payload.rank > 0 then
        coefficient = coefficient * (1.0 + value_at(Config.passives.C02_P03.a06_damage, p03.payload.rank))
        break_value = break_value + value_at(Config.passives.C02_P03.break_bonus, p03.payload.rank)
        Core.remove_status(state, 'C02_P03_READY')
    end
    local fanzhen = Core.get_status(state, 'C02_M04_FANZHEN', now)
    if fanzhen then
        coefficient = coefficient * 1.45
        local p04 = passive_level(state, 'C02_P04')
        if p04 > 0 then
            local events = Core.gain_guard(state, value_at(Config.passives.C02_P04.refund, p04), { now = now })
            append_all(commands, state_commands(events))
            if p04 >= 5 then
                append(commands, { type = 'delayed_damage', delay = 0.15, coefficient = coefficient * Config.passives.C02_P04.rank5_shock_ratio, break_value = 0.5, area_radius = 2.5, can_crit = false })
            end
        end
        Core.remove_status(state, 'C02_M04_FANZHEN')
        remove_modifier(commands, 'C02_M04_FANZHEN', 'self')
    end
    append(commands, { type = 'damage', coefficient = coefficient, break_value = break_value, can_crit = true })
    if token.jieshi then
        append(commands, {
            type = 'delayed_damage', delay = 0.12, coefficient = coefficient * ability.jieshi_shock_ratio,
            break_value = ability.jieshi_bonus_break, area_radius = 2.5, can_crit = false,
        })
    end
    return commands
end

local function a07_commands(state, token, rank, now)
    local ability = Config.abilities.C02_A07
    local commands = {}
    local p06 = passive_level(state, 'C02_P06')
    local shield_ratio = value_at(ability.shield_ratio, rank)
    if p06 > 0 then
        shield_ratio = shield_ratio * (1.0 + value_at(Config.passives.C02_P06.shield_bonus, p06))
    end
    local barrier_payload = { max_hp_ratio = shield_ratio, cast_id = token.id, refresh_once = p06 >= 5 }
    local guard_payload = { damage_reduction = value_at(ability.damage_reduction, rank), cast_id = token.id, guarded = false, rank = rank }
    Core.apply_status(state, 'C02_M08_BUDONG_BARRIER', now, ability.shield_duration, barrier_payload)
    Core.apply_status(state, 'C02_M09_BUDONG_GUARD', now, ability.guard_duration, guard_payload)
    apply_modifier(commands, 'C02_M08_BUDONG_BARRIER', 'self', ability.shield_duration, barrier_payload)
    apply_modifier(commands, 'C02_M09_BUDONG_GUARD', 'self', ability.guard_duration, guard_payload)
    if token.jieshi then
        apply_modifier(commands, 'C02_M10_TONGSHOU', 'team', ability.jieshi_team_duration, {
            damage_reduction = ability.jieshi_team_reduction, highest_value_refresh = true,
        })
    end
    return commands
end

local function a08_commands(state, token, rank, now, context)
    local ability = Config.abilities.C02_A08
    local commands = {}
    local marked_ids, marked_refs = matching_targets(context, function(metadata)
        return metadata.private_jieding == true
    end)
    local controllable_ids, controllable_refs = matching_targets(context, function(metadata)
        return metadata.rank ~= 'boss'
    end)
    append(commands, { type = 'damage', coefficient = value_at(ability.impact_damage, rank), break_value = ability.break_value, can_crit = true })
    if #marked_ids > 0 then
        append(commands, {
            type = 'damage', target_scope = 'explicit', target_ids = marked_ids, targets = marked_refs,
            coefficient = ability.mark_bonus, break_value = 0, can_crit = true,
        })
        local p08 = passive_level(state, 'C02_P08')
        if p08 > 0 then
            append(commands, {
                type = 'break', target_scope = 'explicit', target_ids = marked_ids, targets = marked_refs,
                break_value = ability.break_value * value_at(Config.passives.C02_P08.marked_break_bonus, p08),
            })
        end
    end
    for index = 1, ability.pulse_count do
        append(commands, {
            type = 'delayed_damage', delay = index * ability.duration / ability.pulse_count,
            coefficient = value_at(ability.pulse_damage, rank), break_value = ability.break_value * 0.25,
            area_radius = 3.5, can_crit = false,
        })
    end
    local root_bonus = token.jieshi and ability.jieshi_root_bonus or 0
    if #controllable_ids > 0 then
        apply_modifier(commands, 'C02_M11_ZHENYA', 'explicit', ability.duration, { jieshi = token.jieshi }, {
            target_ids = controllable_ids, targets = controllable_refs,
        })
    end
    append(commands, {
        type = 'control', target_scope = 'selected', normal_duration = ability.normal_root_duration + root_bonus,
        elite_duration = ability.elite_root_duration + root_bonus * 0.35,
        boss_converts_to_break = true,
        boss_break_value = (token.jieshi and ability.jieshi_bonus_break or 0),
        target_meta_by_id = context.target_meta_by_id,
    })
    local p08 = passive_level(state, 'C02_P08')
    if token.jieshi and #marked_ids > 0 and p08 >= 5 and not Core.get_status(state, 'C02_P08_ICD', now) then
        apply_modifier(commands, 'C02_M10_TONGSHOU', 'team', ability.team_duration, {
            damage_reduction = Config.passives.C02_P08.rank5_team_reduction, highest_value_refresh = true,
        })
        Core.apply_status(state, 'C02_P08_ICD', now, Config.passives.C02_P08.rank5_trigger_cooldown)
    end
    return commands
end

local function resolve_spender(state, token, rank, now, context)
    local commands = {}
    append_all(commands, state_commands(Core.resolve_spender_success(state, token, now)))
    if token.skill_key == 'C02_A06' then
        append_all(commands, a06_commands(state, token, rank, now, context))
    elseif token.skill_key == 'C02_A08' then
        append_all(commands, a08_commands(state, token, rank, now, context))
    end
    local passive = p02_command(state, token)
    if passive then
        append(commands, passive)
    end
    return commands
end

local function use_spender(state, skill_key, rank, now, context, deferred)
    local token, events_or_error = Core.begin_spender(state, skill_key, now, context)
    if not token then
        return { ok = false, error = events_or_error, commands = {} }
    end
    local commands = state_commands(events_or_error)
    if skill_key == 'C02_A07' then
        append_all(commands, a07_commands(state, token, rank, now))
        local passive = p02_command(state, token)
        if passive then
            append(commands, passive)
        end
        return { ok = true, cast_id = token.id, commands = commands, pending_guard = true }
    end
    if deferred then
        return { ok = true, cast_id = token.id, commands = commands }
    end
    if target_count(context) <= 0 then
        Core.finish_spender_miss(state, token.id, now, 'no-effective-hit')
        append(commands, Core.is_jieshi(state) and { type = 'guard_changed', guard = state.guard, jieshi = false } or { type = 'spender_missed' })
        return { ok = true, cast_id = token.id, commands = commands, missed = true }
    end
    local confirmed, error_code = Core.confirm_spender(state, token.id, now)
    if not confirmed then
        return { ok = false, error = error_code, commands = commands }
    end
    append_all(commands, resolve_spender(state, confirmed, rank, now, context))
    return { ok = true, cast_id = token.id, commands = commands }
end

function M.use(state, skill_key, rank, now, context)
    context = context or {}
    local ability, error_code = validate_rank(skill_key, rank)
    if not ability then
        return { ok = false, error = error_code, commands = {} }
    end
    if ability.generator or skill_key == 'C02_A04' then
        return generator_skill(state, skill_key, rank, now, context)
    end
    if ability.spender then
        return use_spender(state, skill_key, rank, now, context, false)
    end
    return { ok = false, error = 'unsupported-skill', commands = {} }
end

function M.commit_spender(state, skill_key, rank, now, context)
    local ability, error_code = validate_rank(skill_key, rank)
    if not ability or not ability.spender then
        return { ok = false, error = error_code or 'not-spender', commands = {} }
    end
    return use_spender(state, skill_key, rank, now, context or {}, true)
end

function M.confirm_spender_hit(state, cast_id, now, context)
    context = context or {}
    local token, error_code = Core.confirm_spender(state, cast_id, now)
    if not token then
        return { ok = false, error = error_code, commands = {} }
    end
    if token.skill_key == 'C02_A07' then
        return { ok = false, error = 'a07-requires-effective-guard', commands = {} }
    end
    local rank = state.ability_levels[token.skill_key] or 1
    return { ok = true, skill_key = token.skill_key, cast_id = cast_id, commands = resolve_spender(state, token, rank, now, context) }
end

function M.finish_spender_miss(state, cast_id, now, reason)
    local token, error_code = Core.finish_spender_miss(state, cast_id, now, reason)
    if not token then
        return { ok = false, error = error_code, commands = {} }
    end
    return { ok = true, skill_key = token.skill_key, cast_id = cast_id, commands = { { type = 'spender_missed', guard = state.guard, jieshi = Core.is_jieshi(state) } } }
end

function M.trigger_guard_counter(state, now, context)
    context = context or {}
    local commands = {}
    local parry = Core.get_status(state, 'C02_M02_GUJIA', now)
    if parry and not parry.payload.triggered then
        if context.guardable_hit ~= true then
            return { ok = false, error = 'not-guardable-hit', commands = {} }
        end
        parry.payload.triggered = true
        Core.remove_status(state, 'C02_M02_GUJIA')
        remove_modifier(commands, 'C02_M02_GUJIA', 'self')
        local events = Core.gain_guard(state, parry.payload.guard_on_success, { now = now })
        append_all(commands, state_commands(events))
        append_all(commands, state_commands(Core.gain_ultimate(state, Config.resource.parry_ultimate_gain)))
        if Core.is_guiyuan_active(state, now) and state.guiyuan.tier >= 1 then
            append_all(commands, state_commands(Core.gain_guard(state, Config.ultimate.tier1_parry_guard, { now = now })))
        end
        Core.arm_next_generator(state, passive_level(state, 'C02_P01'), now)
        local p05 = passive_level(state, 'C02_P05')
        if p05 > 0 then
            local payload = { damage_reduction = value_at(Config.passives.C02_P05.post_guard_reduction, p05) }
            Core.apply_status(state, 'C02_M03_HUSHOU', now, Config.passives.C02_P05.post_guard_duration, payload)
            apply_modifier(commands, 'C02_M03_HUSHOU', 'self', Config.passives.C02_P05.post_guard_duration, payload)
        end
        Core.apply_status(state, 'C02_M04_FANZHEN', now, Config.abilities.C02_A04.counter_ready_duration, {})
        apply_modifier(commands, 'C02_M04_FANZHEN', 'self', Config.abilities.C02_A04.counter_ready_duration, {})
        append(commands, { type = 'damage', coefficient = parry.payload.counter_damage, break_value = Config.abilities.C02_A04.counter_break, can_crit = true })
        if parry.payload.rank >= 5 then
            local shield = { max_hp_ratio = Config.abilities.C02_A04.rank5_shield_ratio }
            Core.apply_status(state, 'C02_M05_FANZHEN_SHIELD', now, Config.abilities.C02_A04.rank5_shield_duration, shield)
            apply_modifier(commands, 'C02_M05_FANZHEN_SHIELD', 'self', Config.abilities.C02_A04.rank5_shield_duration, shield)
        end
        return { ok = true, commands = commands, kind = 'parry' }
    end

    local barrier = Core.get_status(state, 'C02_M09_BUDONG_GUARD', now)
    if barrier and not barrier.payload.guarded then
        if context.effective_protection ~= true then
            return { ok = false, error = 'not-effective-protection', commands = {} }
        end
        barrier.payload.guarded = true
        local events = Core.gain_guard(state, Config.abilities.C02_A07.guard_on_success, { now = now })
        append_all(commands, state_commands(events))
        Core.arm_next_generator(state, passive_level(state, 'C02_P01'), now)
        local token, error_code = Core.confirm_spender(state, barrier.payload.cast_id, now)
        if token then
            append_all(commands, state_commands(Core.resolve_spender_success(state, token, now)))
            local passive = p02_command(state, token)
            if passive then
                append(commands, passive)
            end
        elseif error_code ~= 'unknown-cast' then
            return { ok = false, error = error_code, commands = commands }
        end
        local p06 = passive_level(state, 'C02_P06')
        if p06 > 0 then
            append(commands, {
                type = 'heal_and_guard', heal_max_hp = value_at(Config.passives.C02_P06.heal_max_hp, p06),
                damage_reduction = 0, duration = 0, guard_key = 'C02_M03_HUSHOU',
            })
        end
        return { ok = true, commands = commands, kind = 'guard' }
    end
    return { ok = false, error = 'no-guard-window', commands = {} }
end

function M.activate_ultimate(state, now)
    local realm, event_or_error = Core.activate_ultimate(state, now)
    if not realm then
        return { ok = false, error = event_or_error, commands = {} }
    end
    event_or_error.expires_at = realm.expires_at
    local commands = { event_or_error, {
        type = 'damage', coefficient = Config.ultimate.activation_damage, break_value = Config.ultimate.activation_break,
        area_radius = 4.0, can_crit = true,
    } }
    apply_modifier(commands, 'C02_M12_GUIYUAN', 'self', realm.expires_at - now, { tier = realm.tier })
    return { ok = true, commands = commands }
end

return M
