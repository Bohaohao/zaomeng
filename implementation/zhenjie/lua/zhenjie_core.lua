local Config = require 'zhenjie_config'

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

local function append(list, value)
    list[#list + 1] = value
end

local function passive_level(state, key)
    return state.passive_levels[key] or 0
end

local function value_at(values, rank)
    return values and values[rank] or nil
end

local function realm_active(state, now)
    return state.guiyuan ~= nil and now < state.guiyuan.expires_at
end

local function status_active(status, now)
    return status and (status.expires_at == nil or now < status.expires_at)
end

local function state_event(state, event_type)
    return {
        type = event_type,
        guard = state.guard,
        ultimate_gauge = state.ultimate_gauge,
        jieshi = M.is_jieshi(state),
    }
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
        guard = 0,
        ultimate_gauge = 0,
        current_hp = clamp(options.current_hp or stats.hp_max, 0, stats.hp_max),
        statuses = {},
        casts = {},
        next_cast_id = 1,
        last_effective_at = now,
        last_tick_at = now,
        next_generator_bonus = nil,
        guard_spend_meter = 0,
        guiyuan = nil,
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

function M.is_jieshi(state)
    return state.level >= Config.resource.jieshi_unlock_level
        and state.guard >= Config.resource.jieshi_threshold
end

function M.is_guiyuan_active(state, now)
    return realm_active(state, now)
end

function M.apply_status(state, key, now, duration, payload)
    state.statuses[key] = {
        key = key,
        payload = payload or {},
        applied_at = now,
        expires_at = duration and (now + duration) or nil,
    }
    return state.statuses[key]
end

function M.get_status(state, key, now)
    local status = state.statuses[key]
    if status and not status_active(status, now) then
        state.statuses[key] = nil
        return nil
    end
    return status
end

function M.remove_status(state, key)
    local existed = state.statuses[key] ~= nil
    state.statuses[key] = nil
    return existed
end

local function gain_guard_raw(state, amount, now)
    local before = state.guard
    state.guard = clamp(state.guard + amount, 0, Config.resource.guard_max)
    state.last_effective_at = now
    return state.guard - before
end

function M.gain_guard(state, amount, context)
    context = context or {}
    assert(type(amount) == 'number' and amount >= 0, 'guard gain must be non-negative')
    if context.effective == false then
        return {}, 0
    end

    local now = context.now or state.last_tick_at
    local gained = gain_guard_raw(state, amount, now)
    local events = {}
    if gained > 0 then
        append(events, state_event(state, 'guard_gain'))
    end
    return events, gained
end

function M.gain_generator_guard(state, amount, context)
    context = context or {}
    local now = context.now or state.last_tick_at
    local bonus = 0
    if state.next_generator_bonus and now < state.next_generator_bonus.expires_at then
        bonus = state.next_generator_bonus.amount
        state.next_generator_bonus = nil
    elseif state.next_generator_bonus then
        state.next_generator_bonus = nil
    end

    local events, gained = M.gain_guard(state, amount + bonus, {
        now = now,
        effective = context.effective ~= false,
    })
    local realm = state.guiyuan
    if gained > 0 and realm_active(state, now) and realm.tier >= 2 and context.generator_key then
        realm.distinct_generators = realm.distinct_generators or {}
        if not realm.distinct_generators[context.generator_key]
            and realm.distinct_generator_count < Config.ultimate.tier2_distinct_generator_cap then
            realm.distinct_generators[context.generator_key] = true
            realm.distinct_generator_count = realm.distinct_generator_count + 1
            local extra_events = M.gain_guard(state, Config.ultimate.tier2_distinct_generator_bonus, { now = now })
            for _, event in ipairs(extra_events) do
                event.type = 'guiyuan_generator_bonus'
                append(events, event)
            end
        end
    end
    return events, gained
end

function M.arm_next_generator(state, rank, now)
    if rank <= 0 then
        return nil
    end
    local amount = value_at(Config.passives.C02_P01.next_generator_guard, rank)
    state.next_generator_bonus = {
        amount = amount,
        expires_at = now + Config.passives.C02_P01.ready_duration,
    }
    return state.next_generator_bonus
end

function M.gain_ultimate(state, amount)
    if amount <= 0 then
        return {}, 0
    end
    local before = state.ultimate_gauge
    state.ultimate_gauge = clamp(state.ultimate_gauge + amount, 0, Config.resource.ultimate_max)
    local gained = state.ultimate_gauge - before
    if gained <= 0 then
        return {}, 0
    end
    return { state_event(state, 'ultimate_gain') }, gained
end

local function spend_passive_trigger(state, now)
    local rank = passive_level(state, 'C02_P02')
    if rank <= 0 then
        return nil
    end
    local config = Config.passives.C02_P02
    if state.guard_spend_meter < config.spend_threshold then
        return nil
    end
    local status = M.get_status(state, 'C02_P02_ICD', now)
    if status then
        return nil
    end

    state.guard_spend_meter = state.guard_spend_meter - config.spend_threshold
    M.apply_status(state, 'C02_P02_ICD', now, config.internal_cooldown)
    local payload = {
        heal_max_hp = value_at(config.heal_max_hp, rank),
        damage_reduction = value_at(config.damage_reduction, rank),
        duration = config.duration,
        guard_key = 'C02_M03_HUSHOU',
    }
    if rank >= 5 and state.current_hp / state.stats.hp_max <= config.rank5_emergency_threshold
        and not M.get_status(state, 'C02_P02_EMERGENCY_ICD', now) then
        payload.heal_max_hp = payload.heal_max_hp + config.rank5_emergency_heal
        M.apply_status(state, 'C02_P02_EMERGENCY_ICD', now, config.rank5_emergency_cooldown)
    end
    return payload
end

function M.begin_spender(state, skill_key, now, context)
    context = context or {}
    local cost = Config.resource.spender_costs[skill_key]
    if not cost then
        return nil, 'not-spender'
    end
    if state.guard < cost then
        return nil, 'insufficient-guard'
    end

    local token = {
        id = state.next_cast_id,
        skill_key = skill_key,
        cost = cost,
        committed_at = now,
        expires_at = now + Config.resource.pending_cast_timeout,
        jieshi = M.is_jieshi(state),
        context = context,
    }
    state.next_cast_id = state.next_cast_id + 1
    state.casts[token.id] = token
    state.guard = state.guard - cost
    state.guard_spend_meter = state.guard_spend_meter + cost
    token.passive_trigger = spend_passive_trigger(state, now)
    return token, { state_event(state, 'spender_committed') }
end

function M.confirm_spender(state, cast_id, now)
    local token = state.casts[cast_id]
    if not token then
        return nil, 'unknown-cast'
    end
    if now > token.expires_at then
        state.casts[cast_id] = nil
        return nil, 'cast-expired'
    end
    state.casts[cast_id] = nil
    token.confirmed_at = now
    return token
end

function M.finish_spender_miss(state, cast_id, now, reason)
    local token = state.casts[cast_id]
    if not token then
        return nil, 'unknown-cast'
    end
    state.casts[cast_id] = nil
    token.missed_at = now
    token.miss_reason = reason
    return token
end

function M.resolve_spender_success(state, token, now)
    local events = {}
    state.last_effective_at = now
    local ultimate_events = M.gain_ultimate(state, token.cost * Config.resource.ultimate_per_guard_spent)
    for _, event in ipairs(ultimate_events) do
        append(events, event)
    end

    local realm = state.guiyuan
    if realm_active(state, now) and realm.tier >= 3 then
        realm.spent_since_echo = realm.spent_since_echo + token.cost
        while realm.spent_since_echo >= Config.ultimate.tier3_spend_threshold
            and realm.echo_count < Config.ultimate.tier3_echo_cap do
            realm.spent_since_echo = realm.spent_since_echo - Config.ultimate.tier3_spend_threshold
            realm.echo_count = realm.echo_count + 1
            append(events, {
                type = 'ultimate_echo',
                coefficient = Config.ultimate.tier3_echo_damage,
                break_value = Config.ultimate.tier3_echo_break,
                area_radius = 4.0,
            })
        end
    end
    return events
end

function M.activate_ultimate(state, now)
    if state.ultimate_tier <= 0 then
        return nil, 'ultimate-not-unlocked'
    end
    if state.ultimate_gauge < Config.resource.ultimate_max then
        return nil, 'insufficient-ultimate'
    end
    local tier = clamp(state.ultimate_tier, 1, 3)
    state.ultimate_gauge = 0
    state.guiyuan = {
        tier = tier,
        expires_at = now + Config.ultimate.duration[tier],
        distinct_generators = {},
        distinct_generator_count = 0,
        spent_since_echo = 0,
        echo_count = 0,
    }
    return state.guiyuan, state_event(state, 'ultimate_activated')
end

function M.initialize_ability_charges()
    return nil
end

function M.take_charge_updates()
    return {}
end

function M.normal_attack_hit()
    return {}
end

function M.tick(state, now)
    assert(now >= state.last_tick_at, 'time must be monotonic')
    local events = {}
    if state.guiyuan and now >= state.guiyuan.expires_at then
        state.guiyuan = nil
        append(events, state_event(state, 'guiyuan_expired'))
    end
    for key, status in pairs(state.statuses) do
        if not status_active(status, now) then
            state.statuses[key] = nil
        end
    end
    for cast_id, token in pairs(state.casts) do
        if now > token.expires_at then
            state.casts[cast_id] = nil
        end
    end
    if state.next_generator_bonus and now >= state.next_generator_bonus.expires_at then
        state.next_generator_bonus = nil
    end
    if state.guard > 0 and now - state.last_effective_at >= Config.resource.out_of_combat_clear_delay then
        state.guard = 0
        append(events, state_event(state, 'guard_cleared_out_of_combat'))
    end
    state.last_tick_at = now
    return events
end

function M.clear_transient(state, now)
    state.guard = 0
    state.ultimate_gauge = 0
    state.statuses = {}
    state.casts = {}
    state.next_generator_bonus = nil
    state.guard_spend_meter = 0
    state.guiyuan = nil
    state.last_effective_at = now
    state.last_tick_at = now
end

M.clamp = clamp
M.passive_level = passive_level

return M
