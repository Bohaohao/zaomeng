local Config = require 'powang_config'
local Core = require 'powang_core'

local M = {}

local function append(list, value)
    list[#list + 1] = value
end

local function append_all(target, source)
    if not source then
        return
    end
    for _, value in ipairs(source) do
        append(target, value)
    end
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function passive_level(state, key)
    return state.passive_levels[key] or 0
end

local function value_at(values, rank)
    return values[rank]
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

local function target_count(context)
    return math.max(0, math.floor(context.target_count or 0))
end

local function apply_break_passives(state, break_value, context, dongming)
    local result = break_value
    local p04 = passive_level(state, 'C01_P04')
    if p04 > 0 and context.xianwang then
        result = result * (1.0 + value_at(Config.passives.C01_P04.break_bonus, p04))
    end
    local p02 = passive_level(state, 'C01_P02')
    if p02 >= 5 and dongming then
        result = result + Config.passives.C01_P02.rank5_break_bonus
    end
    return result
end

local function movement_passive_commands(state, now, commands)
    local p03 = passive_level(state, 'C01_P03')
    if p03 > 0 then
        local payload = {
            move_speed = value_at(Config.passives.C01_P03.move_speed, p03),
            attack_speed = value_at(Config.passives.C01_P03.attack_speed, p03),
            combo_bonus_available = p03 >= 5,
        }
        Core.apply_status(state, 'C01_M09_TAXU_WIND', now, Config.passives.C01_P03.duration, payload)
        append(commands, {
            type = 'apply_modifier',
            key = 'C01_M09_TAXU_WIND',
            target_scope = 'self',
            duration = Config.passives.C01_P03.duration,
            payload = payload,
        })
    end

    local p07 = passive_level(state, 'C01_P07')
    if p07 > 0 then
        local payload = {
            damage_reduction = value_at(Config.passives.C01_P07.damage_reduction, p07),
            damage_reduction_category = Config.mitigation.effect_categories.C01_M10_JINTUI_GUARD,
            displacement_immunity = p07 >= 5,
        }
        Core.apply_status(state, 'C01_M10_JINTUI_GUARD', now, Config.passives.C01_P07.duration_after_move, payload)
        append(commands, {
            type = 'apply_modifier',
            key = 'C01_M10_JINTUI_GUARD',
            target_scope = 'self',
            duration = Config.passives.C01_P07.duration_after_move,
            payload = payload,
        })
    end
end

local function xianwang_payload(state, rank)
    local p08 = passive_level(state, 'C01_P08')
    local p04 = passive_level(state, 'C01_P04')
    local duration = value_at(Config.abilities.C01_A05.xianwang_duration, rank)
    local defense_reduction = value_at(Config.abilities.C01_A05.xianwang_defense_reduction, rank)
    local normal_slow = Config.abilities.C01_A05.xianwang_normal_slow

    if p08 > 0 then
        duration = duration + value_at(Config.passives.C01_P08.duration_bonus, p08)
        defense_reduction = defense_reduction + value_at(Config.passives.C01_P08.defense_reduction_bonus, p08)
    end
    if p04 > 0 then
        normal_slow = normal_slow + value_at(Config.passives.C01_P04.normal_slow_bonus, p04)
    end

    return {
        duration = duration,
        defense_reduction = defense_reduction,
        break_taken = Config.abilities.C01_A05.xianwang_break_taken,
        normal_slow = normal_slow,
        highest_value_refresh = true,
    }
end

local function generator_result(state, skill_key, rank, now, context)
    local ability = Config.abilities[skill_key]
    local count = target_count(context)
    local commands = {}
    local resource_events = {}

    if skill_key == 'C01_A01' then
        if count > 0 then
            local extra = math.min(math.max(0, count - 1), ability.extra_target_cap)
            local amount = value_at(ability.momentum, rank) + extra * ability.extra_momentum_per_target
            resource_events = Core.gain_momentum(state, amount, {
                now = now,
                effective_hit = true,
                generator_key = skill_key,
            })
            append(commands, {
                type = 'damage',
                coefficient = value_at(ability.damage, rank),
                break_value = apply_break_passives(state, ability.break_value, context, false),
                can_crit = true,
            })
        end
        if rank >= 5 then
            append(commands, { type = 'normal_combo_floor', stage = 2, duration = 2.0 })
        end
    elseif skill_key == 'C01_A03' then
        local hits = clamp(math.floor(context.hit_count or ability.hit_count), 0, ability.hit_count)
        if count > 0 and hits > 0 then
            local amount = hits * ability.momentum_per_hit
            if hits == ability.hit_count and context.same_target_all then
                amount = amount + ability.same_target_bonus
            end
            resource_events = Core.gain_momentum(state, amount, {
                now = now,
                effective_hit = true,
                generator_key = skill_key,
            })
            for index = 1, hits do
                append(commands, {
                    type = 'damage',
                    coefficient = value_at(ability.damage_per_hit, rank),
                    break_value = apply_break_passives(state, ability.break_per_hit, context, false),
                    can_crit = true,
                    hit_index = index,
                })
            end
            if rank >= 5 and hits == ability.hit_count and context.same_target_all
                and (context.target_rank == 'elite' or context.target_rank == 'boss') then
                append(commands, { type = 'cooldown_delta', skill_key = 'C01_A06', amount = -2.0 })
            end
        end
    elseif skill_key == 'C01_A04' then
        append(commands, {
            type = 'move',
            distance = ability.movement_distance,
            safe_landing_required = true,
            damage_reduction = ability.movement_damage_reduction,
            damage_reduction_category = Config.mitigation.move_category,
        })
        movement_passive_commands(state, now, commands)
        if count > 0 then
            resource_events = Core.gain_momentum(state, ability.momentum, {
                now = now,
                effective_hit = true,
                generator_key = skill_key,
            })
            append(commands, {
                type = 'damage',
                coefficient = value_at(ability.damage, rank),
                break_value = apply_break_passives(state, ability.break_value, context, false),
                can_crit = true,
            })
            if rank >= 3 then
                local payload = { move_speed = ability.rank3_move_speed }
                Core.apply_status(state, 'C01_M03_TAXU_SWIFT', now, ability.rank3_move_speed_duration, payload)
                append(commands, {
                    type = 'apply_modifier',
                    key = 'C01_M03_TAXU_SWIFT',
                    target_scope = 'self',
                    duration = ability.rank3_move_speed_duration,
                    payload = payload,
                })
            end
        end
    elseif skill_key == 'C01_A05' then
        if count > 0 then
            local extra = math.min(math.max(0, count - 1), ability.extra_target_cap)
            local amount = value_at(ability.momentum, rank) + extra * ability.extra_momentum_per_target
            resource_events = Core.gain_momentum(state, amount, {
                now = now,
                effective_hit = true,
                generator_key = skill_key,
            })
            append(commands, {
                type = 'damage',
                coefficient = value_at(ability.damage, rank),
                break_value = apply_break_passives(state, ability.break_value, context, false),
                can_crit = true,
            })
            local payload = xianwang_payload(state, rank)
            append(commands, {
                type = 'apply_modifier_to_targets',
                key = 'C01_M02_XIANWANG',
                target_scope = 'selected',
                target_count = count,
                duration = payload.duration,
                payload = payload,
            })
        end
    end

    append_all(commands, resource_events)
    return {
        ok = true,
        skill_key = skill_key,
        rank = rank,
        commands = commands,
    }
end

local function poxi_bonus(state, token, now, context)
    local rank = passive_level(state, 'C01_P06')
    local target_id = context.target_id
    if rank <= 0 or not target_id then
        return 1.0, {}
    end

    state.poxi_by_target = state.poxi_by_target or {}
    local current = state.poxi_by_target[target_id]
    local events = {}
    local multiplier = 1.0

    if current and now <= current.expires_at and current.skill_key ~= token.skill_key then
        multiplier = 1.0 + value_at(Config.passives.C01_P06.damage_bonus, rank)
        state.poxi_by_target[target_id] = nil
        append(events, Core.refund_momentum(
            state,
            value_at(Config.passives.C01_P06.refund, rank),
            now,
            'poxi-consumed'
        ))
        if rank >= 5 then
            append(events, {
                type = 'cooldown_delta',
                skill_key = 'C01_A06',
                amount = -Config.passives.C01_P06.rank5_a06_cooldown_reduction,
            })
        end
        append(events, {
            type = 'remove_modifier',
            key = 'C01_M08_POXI',
            target_scope = 'explicit',
            target_id = target_id,
        })
    end

    if token.dongming then
        state.poxi_by_target[target_id] = {
            skill_key = token.skill_key,
            expires_at = now + Config.passives.C01_P06.duration,
        }
        append(events, {
            type = 'apply_modifier',
            key = 'C01_M08_POXI',
            target_scope = 'explicit',
            target_id = target_id,
            duration = Config.passives.C01_P06.duration,
            source_bound = true,
        })
    end

    return multiplier, events
end

local function guard_counter_commands(state, guard, now, actual_trigger)
    if not guard or not guard.counter_available then
        return {}
    end

    guard.counter_available = false
    local commands = {
        {
            type = 'damage',
            coefficient = guard.counter_coefficient,
            break_value = guard.counter_break_value,
            can_crit = true,
            tag = 'counter',
        },
    }
    if actual_trigger and guard.rank >= 3 then
        append(commands, Core.refund_momentum(state, Config.abilities.C01_A07.rank3_refund, now, 'a07-rank3-counter'))
    end
    if guard.rank >= 5 then
        append(commands, {
            type = 'apply_modifier',
            key = 'C01_M05_HUIFENG_SHIELD',
            target_scope = 'self',
            duration = Config.abilities.C01_A07.rank5_shield_duration,
            payload = { max_hp_ratio = Config.abilities.C01_A07.rank5_shield_max_hp },
        })
    end
    return commands
end

local function spender_damage_commands(state, token, rank, now, context)
    local ability = Config.abilities[token.skill_key]
    local commands = {}
    local poxi_multiplier, poxi_events = poxi_bonus(state, token, now, context)
    append_all(commands, poxi_events)

    local common_multiplier = token.damage_multiplier * poxi_multiplier
    local dongming = token.dongming

    local a05_rank = state.ability_levels.C01_A05 or 0
    if a05_rank >= 5 and context.xianwang and context.target_id then
        state.xianwang_echo_ready = state.xianwang_echo_ready or {}
        local ready_at = state.xianwang_echo_ready[context.target_id] or 0
        if now >= ready_at then
            state.xianwang_echo_ready[context.target_id] = now + Config.abilities.C01_A05.rank5_echo_cooldown
            append(commands, {
                type = 'damage',
                coefficient = Config.abilities.C01_A05.rank5_echo_damage,
                break_value = 0,
                can_crit = false,
                tag = 'xianwang-echo',
                area_radius = 1.5,
            })
        end
    end

    if token.skill_key == 'C01_A02' then
        append(commands, {
            type = 'damage',
            coefficient = value_at(ability.damage, rank) * common_multiplier,
            break_value = apply_break_passives(state, ability.break_value, context, dongming),
            can_crit = true,
        })
        if dongming then
            append(commands, {
                type = 'damage',
                coefficient = value_at(ability.dongming_damage, rank) * common_multiplier,
                break_value = ability.dongming_break_value,
                can_crit = false,
                tag = 'echo',
                pierce_extension = rank >= 3 and 1.0 or 0,
            })
            if rank >= 5 then
                append(commands, Core.refund_momentum(state, 5, now, 'a02-rank5-dongming'))
            end
        end
    elseif token.skill_key == 'C01_A06' then
        local hp_ratio = clamp(context.target_health_ratio or 1.0, 0, 1)
        local execute_bonus = 0
        if rank >= 3 and hp_ratio < ability.execute_threshold then
            execute_bonus = math.min(ability.execute_bonus_cap, (1.0 - hp_ratio) * ability.execute_bonus_cap)
        end
        local primary = value_at(ability.damage, rank) * common_multiplier * (1.0 + execute_bonus)
        append(commands, {
            type = 'damage',
            coefficient = primary,
            break_value = apply_break_passives(state, ability.break_value, context, dongming),
            can_crit = true,
        })
        if dongming then
            local ratio = value_at(ability.dongming_second_ratio, rank)
            if rank >= 5 and hp_ratio < ability.rank5_low_health_threshold then
                ratio = ability.rank5_low_health_second_ratio
            end
            append(commands, {
                type = 'delayed_damage',
                delay = 0.45,
                coefficient = primary * ratio,
                break_value = ability.dongming_break_value,
                can_crit = false,
                tag = 'echo',
            })
        end
    elseif token.skill_key == 'C01_A07' then
        append(commands, {
            type = 'move',
            distance = ability.movement_distance,
            safe_landing_required = true,
        })
        movement_passive_commands(state, now, commands)
        append(commands, {
            type = 'damage',
            coefficient = value_at(ability.sweep_damage, rank) * common_multiplier,
            break_value = apply_break_passives(state, ability.sweep_break, context, dongming),
            can_crit = true,
        })
        local guard_payload = {
            damage_reduction = ability.guard_reduction,
            damage_reduction_category = Config.mitigation.effect_categories.C01_M04_HUIFENG_GUARD,
            dongming_damage_reduction = dongming and ability.dongming_reduction or nil,
            dongming_window = dongming and ability.dongming_window or nil,
            counter_available = true,
            rank = rank,
            counter_coefficient = value_at(ability.counter_damage, rank) * common_multiplier,
            counter_break_value = ability.counter_break,
        }
        Core.apply_status(state, 'C01_M04_HUIFENG_GUARD', now, ability.guard_duration, guard_payload)
        append(commands, {
            type = 'apply_modifier',
            key = 'C01_M04_HUIFENG_GUARD',
            target_scope = 'self',
            duration = ability.guard_duration,
            payload = guard_payload,
        })
        if dongming then
            append_all(commands, guard_counter_commands(state, guard_payload, now, false))
        end
    elseif token.skill_key == 'C01_A08' then
        local break_value = ability.break_value
        if context.target_rank == 'boss' then
            break_value = break_value + ability.boss_extra_break
        end
        append(commands, {
            type = 'damage',
            coefficient = value_at(ability.damage, rank) * common_multiplier,
            break_value = apply_break_passives(state, break_value, context, dongming),
            can_crit = true,
        })
        if context.xianwang then
            append(commands, {
                type = 'damage',
                coefficient = value_at(ability.xianwang_bonus_damage, rank) * common_multiplier,
                break_value = 0,
                can_crit = false,
                tag = 'xianwang-followup',
                area_radius = rank >= 3 and 1.5 or nil,
            })
            append(commands, {
                type = 'refresh_modifier',
                key = 'C01_M02_XIANWANG',
                target_scope = 'primary',
                highest_value_refresh = true,
            })
        end
        if dongming then
            for index = 1, ability.fissure_hits do
                append(commands, {
                    type = 'delayed_damage',
                    delay = index * (ability.fissure_duration / ability.fissure_hits),
                    coefficient = value_at(ability.fissure_damage, rank) * common_multiplier,
                    break_value = 0,
                    can_crit = false,
                    tag = 'fissure',
                    hit_index = index,
                    area_radius = 1.0,
                })
            end
        end
        append(commands, {
            type = 'control',
            target_scope = 'selected',
            normal_duration = ability.normal_root_duration,
            elite_duration = ability.elite_root_duration,
            boss_converts_to_break = true,
            requires_target_rank = true,
            target_meta_by_id = context.target_meta_by_id,
        })

        local p04 = passive_level(state, 'C01_P04')
        if p04 >= 5 and context.xianwang then
            append(commands, {
                type = 'extend_modifier_once',
                key = 'C01_M02_XIANWANG',
                target_scope = 'primary',
                reason = 'p04-first-hard-control:' .. tostring(token.id),
                duration = Config.passives.C01_P04.rank5_extension,
            })
        end
        if rank >= 5 and dongming and context.xianwang then
            append(commands, {
                type = 'extend_modifier_once',
                key = 'C01_M02_XIANWANG',
                target_scope = 'primary',
                reason = 'a08-rank5-first-fissure:' .. tostring(token.id),
                duration = 2.0,
            })
        end

        local p08 = passive_level(state, 'C01_P08')
        if p08 >= 5 and context.xianwang
            and (context.target_rank == 'elite' or context.target_rank == 'boss') then
            state.mingshi_ready_at = state.mingshi_ready_at or 0
            if now >= state.mingshi_ready_at then
                state.mingshi_ready_at = now + Config.passives.C01_P08.rank5_trigger_cooldown
                append(commands, {
                    type = 'apply_team_modifier',
                    key = 'C01_M11_MINGSHI',
                    target_scope = 'team',
                    duration = Config.passives.C01_P08.rank5_mingshi_duration,
                    radius = 6.0,
                    payload = { target_break_bonus = Config.passives.C01_P08.rank5_mingshi_break_bonus },
                })
            end
        end
    end

    return commands
end

function M.trigger_guard_counter(state, now, context)
    context = context or {}
    local status = Core.get_status(state, 'C01_M04_HUIFENG_GUARD', now)
    if not status or not status.payload or not status.payload.counter_available then
        return { ok = false, error = 'guard-not-active', commands = {} }
    end
    if context.guardable_hit ~= true then
        return { ok = false, error = 'guard-hit-not-eligible', commands = {} }
    end
    return {
        ok = true,
        skill_key = 'C01_A07',
        commands = guard_counter_commands(state, status.payload, now, true),
        context = context,
    }
end

function M.commit_spender(state, skill_key, rank, now, context)
    context = context or {}
    local ability, error_code = validate_rank(skill_key, rank)
    if not ability then
        return { ok = false, error = error_code, commands = {} }
    end
    if not ability.spender then
        return { ok = false, error = 'not-a-spender', commands = {} }
    end

    local token, events_or_error = Core.begin_spender(state, skill_key, now, {
        health_ratio = context.health_ratio,
    })
    if not token then
        return { ok = false, error = events_or_error, commands = {} }
    end
    token.rank = rank
    return {
        ok = true,
        committed = true,
        skill_key = skill_key,
        rank = rank,
        cast_id = token.id,
        dongming = token.dongming,
        commands = events_or_error,
    }
end

function M.confirm_spender_hit(state, cast_id, now, context)
    context = context or {}
    local token = Core.get_cast(state, cast_id)
    if not token then
        return { ok = false, error = 'unknown-cast', commands = {} }
    end

    local confirmation, confirmation_error = Core.confirm_spender_hit(state, cast_id, now)
    if not confirmation then
        return { ok = false, error = confirmation_error, commands = {} }
    end
    local commands = {}
    append_all(commands, confirmation)
    append_all(commands, spender_damage_commands(state, token, token.rank, now, context))
    return {
        ok = true,
        skill_key = token.skill_key,
        rank = token.rank,
        cast_id = cast_id,
        dongming = token.dongming,
        commands = commands,
    }
end

function M.finish_spender_miss(state, cast_id, now, reason)
    local event, error_code = Core.finish_spender_miss(state, cast_id, now, reason)
    if not event then
        return { ok = false, error = error_code, commands = {} }
    end
    return { ok = true, skill_key = event.skill_key, cast_id = cast_id, missed = true, commands = { event } }
end

function M.use(state, skill_key, rank, now, context)
    context = context or {}
    local ability, error_code = validate_rank(skill_key, rank)
    if not ability then
        return { ok = false, error = error_code, commands = {} }
    end

    if ability.generator then
        return generator_result(state, skill_key, rank, now, context)
    end

    if not ability.spender then
        return { ok = false, error = 'unsupported-active-kind', commands = {} }
    end

    local committed = M.commit_spender(state, skill_key, rank, now, context)
    if not committed.ok or context.defer_hit then
        return committed
    end
    if context.hit == false then
        local missed = M.finish_spender_miss(state, committed.cast_id, now, context.miss_reason)
        append_all(committed.commands, missed.commands)
        committed.missed = true
        return committed
    end

    local confirmed = M.confirm_spender_hit(state, committed.cast_id, now, context)
    if not confirmed.ok then
        return confirmed
    end
    append_all(committed.commands, confirmed.commands)
    committed.confirmed_hit = true
    return committed
end

function M.activate_ultimate(state, now)
    local commands, error_code = Core.activate_ultimate(state, now)
    if not commands then
        return { ok = false, error = error_code, commands = {} }
    end
    return { ok = true, skill_key = Config.ultimate.key, commands = commands }
end

return M
