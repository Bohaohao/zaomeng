local Config = require 'powang_config'

local M = {}

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function round_half_up(value)
    return math.floor(value + 0.5)
end

local function level_value(values, level)
    if not values then
        return nil
    end
    return values[level]
end

local function passive_level(state, key)
    return state.passive_levels[key] or 0
end

local function append(list, value)
    list[#list + 1] = value
end

local function realm_active(state, now)
    return state.true_realm ~= nil and now < state.true_realm.expires_at
end

local function decay_delay(state)
    if passive_level(state, 'C01_P01') >= 5 then
        return Config.resource.decay_delay_p01_rank5
    end
    return Config.resource.decay_delay
end

local function refresh_charges(state, now)
    for _, charge in pairs(state.ability_charges or {}) do
        while charge.next_charge_at and now >= charge.next_charge_at do
            charge.current = math.min(charge.max, charge.current + 1)
            charge.dirty = true
            if charge.current < charge.max then
                charge.next_charge_at = charge.next_charge_at + charge.recovery
            else
                charge.next_charge_at = nil
            end
        end
    end
end

local function ensure_charge(state, skill_key, rank)
    if skill_key ~= 'C01_A04' or rank < 5 then
        return nil
    end
    local charge = state.ability_charges[skill_key]
    if not charge then
        local config = Config.abilities.C01_A04
        charge = {
            current = config.rank5_charges,
            max = config.rank5_charges,
            recovery = config.rank5_charge_recovery,
            next_charge_at = nil,
            dirty = true,
        }
        state.ability_charges[skill_key] = charge
    end
    return charge
end

function M.hero_stats(level)
    assert(type(level) == 'number', 'level must be a number')
    assert(level >= Config.hero.level_min and level <= Config.hero.level_max, 'level outside v1 range')

    local offset = level - 1
    return {
        level = level,
        hp_max = round_half_up(Config.hero.hp_base + Config.hero.hp_growth * offset),
        mp_max = 0,
        attack_physical = round_half_up(Config.hero.attack_base + Config.hero.attack_growth * offset),
        attack_magic = 0,
        defense_physical = round_half_up(Config.hero.defense_physical_base + Config.hero.defense_physical_growth * offset),
        defense_magic = round_half_up(Config.hero.defense_magic_base + Config.hero.defense_magic_growth * offset),
        critical_chance = Config.hero.critical_chance,
        critical_damage = Config.hero.critical_damage,
        hit_rate = Config.hero.hit_rate,
        dodge_rate = Config.hero.dodge_rate,
        cooldown_reduction = 0,
        move_speed = Config.hero.move_speed,
        attack_speed = Config.hero.attack_speed,
        attack_interval = Config.hero.attack_interval,
    }
end

function M.new(options)
    options = options or {}
    local level = options.level or 1
    local stats = M.hero_stats(level)
    local now = options.now or 0

    return {
        level = level,
        stats = stats,
        ability_levels = options.ability_levels or {},
        passive_levels = options.passive_levels or {},
        ultimate_tier = options.ultimate_tier or 0,
        momentum = 0,
        ultimate_gauge = 0,
        current_hp = clamp(options.current_hp or stats.hp_max, 0, stats.hp_max),
        last_effective_attack_at = now,
        last_tick_at = now,
        decay_remainder = 0,
        next_cast_id = 1,
        casts = {},
        ability_charges = {},
        statuses = {},
        shixing_ready_until = nil,
        shouyi_meter = 0,
        shouyi_ready_at = now,
        shouyi_emergency_ready_at = now,
        normal_attack_stage = 0,
        normal_attack_expires_at = nil,
        true_realm = nil,
    }
end

function M.set_health(state, current_hp)
    state.current_hp = clamp(current_hp, 0, state.stats.hp_max)
end

function M.set_level(state, level)
    local previous_max = state.stats.hp_max
    local health_ratio = previous_max > 0 and state.current_hp / previous_max or 1
    state.level = level
    state.stats = M.hero_stats(level)
    state.current_hp = clamp(round_half_up(state.stats.hp_max * health_ratio), 0, state.stats.hp_max)
    return state.stats
end

function M.is_true_realm_active(state, now)
    return realm_active(state, now)
end

function M.is_dongming(state, now)
    return state.momentum >= Config.resource.dongming_threshold or realm_active(state, now)
end

function M.tick(state, now)
    assert(now >= state.last_tick_at, 'time must be monotonic')

    if state.true_realm and now >= state.true_realm.expires_at then
        state.true_realm = nil
    end

    if state.shixing_ready_until and now > state.shixing_ready_until then
        state.shixing_ready_until = nil
    end

    for key, status in pairs(state.statuses) do
        if status.expires_at and now >= status.expires_at then
            state.statuses[key] = nil
        end
    end

    for cast_id, cast in pairs(state.casts) do
        if cast.expires_at and now >= cast.expires_at then
            state.casts[cast_id] = nil
        end
    end

    refresh_charges(state, now)

    if state.momentum > 0 and not realm_active(state, now) then
        local decay_starts_at = state.last_effective_attack_at + decay_delay(state)
        local decay_from = math.max(state.last_tick_at, decay_starts_at)
        if now > decay_from then
            local total = state.decay_remainder + (now - decay_from) * Config.resource.decay_per_second
            local whole = math.floor(total + 0.0000001)
            state.decay_remainder = total - whole
            state.momentum = math.max(0, state.momentum - whole)
            if state.momentum == 0 then
                state.decay_remainder = 0
            end
        end
    end

    state.last_tick_at = now
end

function M.consume_ability_charge(state, skill_key, rank, now)
    if skill_key ~= 'C01_A04' or rank < 5 then
        return true, nil
    end

    M.tick(state, now)
    local charge = ensure_charge(state, skill_key, rank)
    if charge.current <= 0 then
        return false, 'no-charge'
    end

    charge.current = charge.current - 1
    if not charge.next_charge_at then
        charge.next_charge_at = now + charge.recovery
    end
    charge.dirty = true
    return true, {
        skill_key = skill_key,
        current = charge.current,
        maximum = charge.max,
        remaining = math.max(0, charge.next_charge_at - now),
    }
end

function M.initialize_ability_charges(state)
    ensure_charge(state, 'C01_A04', state.ability_levels.C01_A04 or 0)
end

function M.take_charge_updates(state, now)
    M.tick(state, now)
    local updates = {}
    for skill_key, charge in pairs(state.ability_charges) do
        if charge.dirty then
            append(updates, {
                skill_key = skill_key,
                current = charge.current,
                maximum = charge.max,
                remaining = charge.next_charge_at and math.max(0, charge.next_charge_at - now) or 0,
            })
            charge.dirty = false
        end
    end
    return updates
end

function M.record_effective_attack(state, now)
    M.tick(state, now)
    state.last_effective_attack_at = now
    state.decay_remainder = 0
end

local function add_raw_momentum(state, amount)
    local before = state.momentum
    state.momentum = clamp(before + amount, 0, Config.resource.momentum_max)
    return state.momentum - before, math.max(0, before + amount - Config.resource.momentum_max)
end

function M.gain_momentum(state, base_amount, options)
    options = options or {}
    local now = options.now or state.last_tick_at
    M.tick(state, now)

    local amount = base_amount
    local events = {}

    if realm_active(state, now) and not options.ignore_realm_multiplier then
        local tier = state.true_realm.tier
        amount = math.floor(amount * Config.ultimate.generation_multiplier[tier])

        if tier >= 2 and options.generator_key and not state.true_realm.distinct_generators[options.generator_key] then
            if state.true_realm.distinct_generator_count < Config.ultimate.tier2_distinct_generator_cap then
                state.true_realm.distinct_generators[options.generator_key] = true
                state.true_realm.distinct_generator_count = state.true_realm.distinct_generator_count + 1
                amount = amount + Config.ultimate.tier2_distinct_generator_bonus
                append(events, { type = 'ultimate_distinct_generator_bonus', amount = Config.ultimate.tier2_distinct_generator_bonus })
            end
        end
    end

    local p01 = passive_level(state, 'C01_P01')
    if p01 > 0 and options.generator_key and state.shixing_ready_until and now <= state.shixing_ready_until then
        local bonus = level_value(Config.passives.C01_P01.bonus_momentum, p01)
        amount = amount + bonus
        state.shixing_ready_until = nil
        append(events, { type = 'shixing_consumed', amount = bonus })
    end

    local gained, overflow = add_raw_momentum(state, math.floor(amount))
    if options.effective_hit then
        state.last_effective_attack_at = now
        state.decay_remainder = 0
    end

    append(events, {
        type = 'momentum_gain',
        requested = math.floor(amount),
        gained = gained,
        overflow = overflow,
        momentum = state.momentum,
    })
    return events
end

function M.normal_attack_hit(state, now)
    M.tick(state, now)

    if not state.normal_attack_expires_at or now > state.normal_attack_expires_at then
        state.normal_attack_stage = 1
    else
        state.normal_attack_stage = state.normal_attack_stage % 3 + 1
    end
    state.normal_attack_expires_at = now + Config.resource.normal_attack_combo_window

    local amount = Config.resource.normal_attack_momentum[state.normal_attack_stage]
    local taxu_wind = state.statuses.C01_M09_TAXU_WIND
    if state.normal_attack_stage == 3
        and taxu_wind
        and taxu_wind.payload
        and taxu_wind.payload.combo_bonus_available then
        amount = amount + Config.passives.C01_P03.rank5_normal_combo_momentum
        taxu_wind.payload.combo_bonus_available = false
    end
    local events = M.gain_momentum(state, amount, {
        now = now,
        effective_hit = true,
    })
    append(events, { type = 'normal_attack_stage', stage = state.normal_attack_stage })
    return events
end

local function health_ratio(state, provided)
    if provided ~= nil then
        return clamp(provided, 0, 1)
    end
    if state.stats.hp_max <= 0 then
        return 0
    end
    return state.current_hp / state.stats.hp_max
end

local function apply_shouyi(state, cost, now, options, events)
    local rank = passive_level(state, 'C01_P05')
    if rank <= 0 then
        return
    end

    local config = Config.passives.C01_P05
    state.shouyi_meter = math.min(config.spend_threshold, state.shouyi_meter + cost)

    if state.shouyi_meter < config.spend_threshold or now < state.shouyi_ready_at then
        return
    end

    state.shouyi_meter = 0
    state.shouyi_ready_at = now + config.internal_cooldown
    local heal = level_value(config.heal_max_hp, rank)
    local ratio = health_ratio(state, options.health_ratio)
    if rank >= 5 and ratio < config.rank5_emergency_threshold and now >= state.shouyi_emergency_ready_at then
        heal = config.rank5_emergency_heal
        state.shouyi_emergency_ready_at = now + config.rank5_emergency_cooldown
    end

    state.current_hp = clamp(state.current_hp + state.stats.hp_max * heal, 0, state.stats.hp_max)

    append(events, {
        type = 'shouyi_trigger',
        heal_max_hp = heal,
        damage_reduction = level_value(config.damage_reduction, rank),
        duration = config.duration,
    })
end

local function apply_true_realm_spend(state, cost, events)
    if not state.true_realm or state.true_realm.tier < 3 then
        return
    end

    state.true_realm.spend_meter = state.true_realm.spend_meter + cost
    while state.true_realm.spend_meter >= Config.ultimate.tier3_spend_threshold
        and state.true_realm.echo_count < Config.ultimate.tier3_echo_cap do
        state.true_realm.spend_meter = state.true_realm.spend_meter - Config.ultimate.tier3_spend_threshold
        state.true_realm.echo_count = state.true_realm.echo_count + 1
        append(events, {
            type = 'ultimate_echo',
            coefficient = Config.ultimate.tier3_echo_damage,
            break_value = Config.ultimate.tier3_echo_break,
            area_radius = 4.0,
            index = state.true_realm.echo_count,
        })
    end
end

local function p02_damage_multiplier(state, pre_spend_momentum, dongming)
    local rank = passive_level(state, 'C01_P02')
    if rank <= 0 then
        return 1.0
    end
    if dongming then
        return 1.0 + level_value(Config.passives.C01_P02.dongming_damage, rank)
    end
    if pre_spend_momentum >= 40 then
        return 1.0 + level_value(Config.passives.C01_P02.mid_momentum_damage, rank)
    end
    return 1.0
end

function M.begin_spender(state, skill_key, now, options)
    options = options or {}
    M.tick(state, now)

    local cost = Config.resource.spender_costs[skill_key]
    if not cost then
        return nil, 'not-a-spender'
    end
    if state.momentum < cost then
        return nil, 'insufficient-momentum'
    end

    local pre_spend = state.momentum
    local dongming = M.is_dongming(state, now)
    state.momentum = state.momentum - cost

    local token = {
        id = state.next_cast_id,
        skill_key = skill_key,
        cost = cost,
        committed_at = now,
        pre_spend_momentum = pre_spend,
        dongming = dongming,
        confirmed_hit = false,
        expires_at = now + Config.resource.pending_cast_timeout,
        damage_multiplier = p02_damage_multiplier(state, pre_spend, dongming),
    }
    state.next_cast_id = state.next_cast_id + 1
    state.casts[token.id] = token

    local events = {
        {
            type = 'spender_committed',
            skill_key = skill_key,
            cost = cost,
            dongming = dongming,
            momentum = state.momentum,
            damage_multiplier = token.damage_multiplier,
        },
    }

    apply_shouyi(state, cost, now, options, events)
    apply_true_realm_spend(state, cost, events)

    local p07 = passive_level(state, 'C01_P07')
    if p07 > 0 and cost >= Config.passives.C01_P07.minimum_spend then
        append(events, {
            type = 'mobility_cooldown_reduction',
            amount = level_value(Config.passives.C01_P07.cooldown_reduction, p07),
            skills = { 'C01_A04', 'C01_A07' },
        })
    end

    return token, events
end

function M.get_cast(state, token_id)
    return state.casts[token_id]
end

function M.confirm_spender_hit(state, token_id, now)
    M.tick(state, now)
    local token = state.casts[token_id]
    if not token then
        return nil, 'unknown-cast'
    end
    if token.confirmed_hit then
        return nil, 'already-confirmed'
    end

    token.confirmed_hit = true
    state.casts[token_id] = nil
    state.last_effective_attack_at = now
    state.decay_remainder = 0

    local gained = token.cost * Config.resource.ultimate_per_momentum_spent
    local before = state.ultimate_gauge
    state.ultimate_gauge = clamp(before + gained, 0, Config.resource.ultimate_max)

    local events = {
        {
            type = 'ultimate_gain',
            requested = gained,
            gained = state.ultimate_gauge - before,
            ultimate_gauge = state.ultimate_gauge,
        },
    }

    local p01 = passive_level(state, 'C01_P01')
    if p01 > 0 then
        state.shixing_ready_until = now + Config.passives.C01_P01.ready_duration
        append(events, { type = 'shixing_ready', expires_at = state.shixing_ready_until })
    end

    return events
end

function M.finish_spender_miss(state, token_id, now, reason)
    M.tick(state, now)
    local token = state.casts[token_id]
    if not token then
        return nil, 'unknown-cast'
    end
    state.casts[token_id] = nil
    return {
        type = 'spender_missed',
        skill_key = token.skill_key,
        cost = token.cost,
        reason = reason or 'miss',
    }
end

function M.refund_momentum(state, amount, now, reason)
    M.tick(state, now)
    local gained, overflow = add_raw_momentum(state, amount)
    return {
        type = 'momentum_refund',
        reason = reason,
        requested = amount,
        gained = gained,
        overflow = overflow,
        momentum = state.momentum,
    }
end

function M.activate_ultimate(state, now)
    M.tick(state, now)
    local tier = state.ultimate_tier
    if tier < 1 or tier > 3 then
        return nil, 'ultimate-tier-locked'
    end
    if state.ultimate_gauge < Config.resource.ultimate_max then
        return nil, 'insufficient-ultimate-gauge'
    end

    state.ultimate_gauge = 0
    state.true_realm = {
        tier = tier,
        expires_at = now + Config.ultimate.duration[tier],
        distinct_generators = {},
        distinct_generator_count = 0,
        spend_meter = 0,
        echo_count = 0,
    }
    local gained, overflow = add_raw_momentum(state, Config.ultimate.momentum_gain)
    state.last_effective_attack_at = now
    state.decay_remainder = 0

    return {
        { type = 'ultimate_activated', tier = tier, expires_at = state.true_realm.expires_at },
        { type = 'damage', coefficient = Config.ultimate.activation_damage, break_value = Config.ultimate.activation_break, can_crit = true },
        { type = 'momentum_gain', requested = Config.ultimate.momentum_gain, gained = gained, overflow = overflow, momentum = state.momentum },
    }
end

function M.apply_status(state, key, now, duration, payload)
    M.tick(state, now)
    state.statuses[key] = {
        applied_at = now,
        duration = duration,
        expires_at = duration and (now + duration) or nil,
        payload = payload or {},
    }
    return state.statuses[key]
end

function M.refresh_status(state, key, now, duration)
    M.tick(state, now)
    local status = state.statuses[key]
    if not status then
        return false
    end
    local refresh_duration = duration or status.duration
    if not refresh_duration then
        return false
    end
    status.duration = refresh_duration
    status.expires_at = now + refresh_duration
    return true
end

function M.has_status(state, key, now)
    M.tick(state, now)
    return state.statuses[key] ~= nil
end

function M.get_status(state, key, now)
    M.tick(state, now)
    return state.statuses[key]
end

function M.clear_transient(state, now)
    state.momentum = 0
    state.ultimate_gauge = 0
    state.last_effective_attack_at = now
    state.last_tick_at = now
    state.decay_remainder = 0
    state.casts = {}
    state.statuses = {}
    state.shixing_ready_until = nil
    state.shouyi_meter = 0
    state.shouyi_ready_at = now
    state.shouyi_emergency_ready_at = now
    state.normal_attack_stage = 0
    state.normal_attack_expires_at = nil
    state.true_realm = nil
    state.poxi_by_target = nil
    state.xianwang_echo_ready = nil
    state.mingshi_ready_at = nil
end

return M
