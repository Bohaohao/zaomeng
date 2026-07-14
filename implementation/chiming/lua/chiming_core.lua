-- custom-built: C03 持明的无 Y3 依赖资源与生命周期状态机。
local Config = require 'chiming_config'

local M = {}

local seal_origin_order = { 'earned', 'refunded', 'external' }
local seal_origins = {
    earned = true,
    refunded = true,
    external = true,
}

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function round_half_up(value)
    return math.floor(value + 0.5)
end

local function append(list, value)
    list[#list + 1] = value
end

local function value_at(values, rank)
    return values and values[rank] or nil
end

local function passive_level(state, key)
    return state.passive_levels[key] or 0
end

local function status_active(status, now)
    return status and (status.expires_at == nil or now < status.expires_at)
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

local function sync_seal_count(state)
    state.seals = #(state.seal_queue or {})
    return state.seals
end

local function clear_seals(state)
    state.seal_queue = {}
    state.seals = 0
end

local function seal_sources(state)
    local counts = { earned = 0, refunded = 0, external = 0 }
    for _, entry in ipairs(state.seal_queue or {}) do
        if counts[entry.origin] ~= nil then counts[entry.origin] = counts[entry.origin] + 1 end
    end
    return counts
end

local function append_seal(state, origin, reason)
    assert(seal_origins[origin], 'invalid seal origin: ' .. tostring(origin))
    if sync_seal_count(state) >= Config.resource.seal_max then return false end
    append(state.seal_queue, { origin = origin, reason = reason })
    sync_seal_count(state)
    return true
end

local function consume_seals(state, count)
    local consumed = {}
    for _, origin in ipairs(seal_origin_order) do
        local index = 1
        while index <= #state.seal_queue and #consumed < count do
            local entry = state.seal_queue[index]
            if entry.origin == origin then
                append(consumed, table.remove(state.seal_queue, index))
            else
                index = index + 1
            end
        end
        if #consumed == count then break end
    end
    sync_seal_count(state)
    return consumed
end

local function count_origin(entries, origin)
    local count = 0
    for _, entry in ipairs(entries or {}) do
        if entry.origin == origin then count = count + 1 end
    end
    return count
end

local function core_skill_learned(state)
    for _, key in ipairs(Config.resource.core_skills) do
        if (state.ability_levels[key] or 0) > 0 then return true end
    end
    return false
end

local function mingtai(state)
    return sync_seal_count(state) >= Config.resource.seal_max
end

local function state_event(state, event_type)
    return {
        type = event_type,
        seals = sync_seal_count(state),
        seal_sources = seal_sources(state),
        mingtai = mingtai(state),
        resource_enabled = state.resource_enabled,
        ultimate_gauge = state.ultimate_gauge,
        mingjie = M.is_mingjie_active(state, state.last_tick_at or 0),
    }
end

local function capture_snapshot(context)
    context = context or {}
    local primary_id = context.primary_target_id or context.target_id
    local refs = copy_map(context.target_refs_by_id or context.target_refs)
    local primary_ref = context.primary_target_ref or context.primary_target or context.target
    if primary_id ~= nil and primary_ref ~= nil then refs[primary_id] = primary_ref end
    return {
        actor_id = context.actor_id,
        lifecycle_id = context.lifecycle_id,
        unit_id = context.unit_id,
        primary_target_id = primary_id,
        primary_target_ref = primary_ref,
        target_refs_by_id = refs,
        cast_point = context.cast_point or context.target_point,
        team_target_ids = copy_list(context.team_target_ids),
        team_targets = copy_list(context.team_targets),
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
        attack_physical = round_half_up(Config.hero.attack_physical_base + Config.hero.attack_physical_growth * offset),
        attack_magic = round_half_up(Config.hero.attack_magic_base + Config.hero.attack_magic_growth * offset),
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
    local state = {
        level = level,
        stats = stats,
        ability_levels = options.ability_levels or {},
        passive_levels = options.passive_levels or {},
        ultimate_tier = options.ultimate_tier or 0,
        seals = 0,
        seal_queue = {},
        ultimate_gauge = 0,
        current_hp = clamp(options.current_hp or stats.hp_max, 0, stats.hp_max),
        statuses = {},
        casts = {},
        next_cast_id = 1,
        next_generator_at = now,
        last_effective_at = now,
        last_tick_at = now,
        p01_spend_progress = 0,
        p01_armed = false,
        p01_ready_at = now,
        p02_spend_progress = 0,
        p02_ready_at = now,
        p02_emergency_ready_at = now,
        mingjie = nil,
    }
    state.resource_enabled = level >= Config.resource.resource_unlock_level and core_skill_learned(state)
    return state
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
    M.refresh_resource_enabled(state)
    return state.stats
end

function M.set_ability_level(state, skill_key, rank)
    state.ability_levels[skill_key] = rank
    return M.refresh_resource_enabled(state)
end

function M.refresh_resource_enabled(state)
    local was_enabled = state.resource_enabled == true
    state.resource_enabled = state.level >= Config.resource.resource_unlock_level and core_skill_learned(state)
    if was_enabled and not state.resource_enabled then
        clear_seals(state)
        state.p01_armed = false
        state.p01_spend_progress = 0
        state.p02_spend_progress = 0
    end
    return state.resource_enabled, was_enabled ~= state.resource_enabled
end

function M.is_resource_enabled(state)
    return state.resource_enabled == true
end

function M.is_mingtai(state)
    return mingtai(state)
end

function M.seal_sources(state)
    return seal_sources(state)
end

-- Test and migration helper. Runtime generation must use gain_seal/refund_seal.
function M.set_seals(state, count, origin)
    assert(type(count) == 'number' and count >= 0 and count <= Config.resource.seal_max, 'invalid seal count')
    origin = origin or 'earned'
    assert(seal_origins[origin], 'invalid seal origin: ' .. tostring(origin))
    clear_seals(state)
    for _ = 1, count do append_seal(state, origin, 'set-seals') end
    return state_event(state, 'seal_changed')
end

function M.is_mingjie_active(state, now)
    return state.mingjie ~= nil and now < state.mingjie.expires_at
end

function M.apply_status(state, key, now, duration, payload)
    local status = {
        key = key,
        payload = payload or {},
        applied_at = now,
        expires_at = duration and now + duration or nil,
    }
    state.statuses[key] = status
    return status
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

function M.generator_window(state, now)
    if M.is_mingjie_active(state, now) then return Config.resource.mingjie_generator_window end
    return Config.resource.generator_window
end

function M.gain_seal(state, skill_key, now)
    if not M.is_resource_enabled(state) then return nil, 'resource-locked' end
    if skill_key ~= 'C03_A01' and skill_key ~= 'C03_A02' then return nil, 'not-generator' end
    if now < state.next_generator_at then return nil, 'shared-generator-window' end

    state.next_generator_at = now + M.generator_window(state, now)
    local gained = append_seal(state, 'earned', skill_key)
    state.last_effective_at = now
    local result = {
        gained = gained and 1 or 0,
        overflowed = not gained,
        events = { state_event(state, 'seal_changed') },
    }
    local p01 = passive_level(state, 'C03_P01')
    if result.gained > 0 and state.p01_armed and p01 > 0 and now >= state.p01_ready_at then
        state.p01_armed = false
        state.p01_ready_at = now + Config.resource.p01_internal_cooldown
        result.p01_trigger = { rank = p01, skill_key = skill_key }
    end
    return result
end

function M.refund_seal(state, now, reason, origin)
    if not M.is_resource_enabled(state) then return 0, { state_event(state, 'seal_changed') } end
    origin = origin or 'refunded'
    local gained = append_seal(state, origin, reason)
    state.last_effective_at = now
    local events = { state_event(state, 'seal_changed') }
    events[1].reason = reason
    events[1].origin = origin
    return gained and 1 or 0, events
end

local function spend_for_skill(state, skill_key)
    local ability = Config.abilities[skill_key]
    local seals = sync_seal_count(state)
    if ability.optional_spend then return seals > 0 and 1 or 0 end
    if ability.exact_spend then
        if seals < ability.exact_spend then return nil, 'insufficient-seals' end
        return ability.exact_spend
    end
    if ability.minimum_spend then
        if seals < ability.minimum_spend then return nil, 'insufficient-seals' end
        return ability.spend_all and seals or ability.minimum_spend
    end
    return 0
end

function M.begin_cast(state, skill_key, now, context)
    local ability = Config.abilities[skill_key]
    if not ability then return nil, 'unknown-skill' end
    local spent, error_code = spend_for_skill(state, skill_key)
    if spent == nil then return nil, error_code end
    if spent > 0 and not M.is_resource_enabled(state) then return nil, 'resource-locked' end

    local snapshot = capture_snapshot(context)
    local spent_seals = consume_seals(state, spent)
    local token = {
        id = state.next_cast_id,
        skill_key = skill_key,
        committed_at = now,
        pre_seals = spent + state.seals,
        spent = #spent_seals,
        spent_seals = spent_seals,
        earned_spent = count_origin(spent_seals, 'earned'),
        mingtai = spent + state.seals >= Config.resource.seal_max,
        confirmed = false,
        lifecycle_id = snapshot.lifecycle_id,
        snapshot = snapshot,
    }
    -- The bridge forwards this immutable record to the authoritative hit
    -- reporter. Keeping the cast identity on the snapshot prevents a later
    -- selection pass from silently retargeting an already committed cast.
    snapshot.cast_id = token.id
    snapshot.skill_key = skill_key
    state.next_cast_id = state.next_cast_id + 1
    state.casts[token.id] = token
    state.last_effective_at = now
    local events = {}
    if token.spent > 0 then append(events, state_event(state, 'seal_changed')) end
    return token, events
end

local function post_effective_spend(state, token, now)
    local result = { events = {}, p02_trigger = nil, tier3_echo = nil }
    if token.spent <= 0 then return result end

    local before = state.ultimate_gauge
    state.ultimate_gauge = clamp(
        state.ultimate_gauge + token.earned_spent * Config.resource.ultimate_per_effective_seal,
        0,
        Config.resource.ultimate_max
    )
    if state.ultimate_gauge ~= before then append(result.events, state_event(state, 'ultimate_gain')) end

    local p01 = passive_level(state, 'C03_P01')
    if p01 > 0 then
        state.p01_spend_progress = state.p01_spend_progress + token.spent
        if state.p01_spend_progress >= Config.resource.p01_spend_threshold then
            state.p01_spend_progress = state.p01_spend_progress - Config.resource.p01_spend_threshold
            state.p01_armed = true
        end
    end

    local p02 = passive_level(state, 'C03_P02')
    if p02 > 0 then
        state.p02_spend_progress = state.p02_spend_progress + token.spent
        if state.p02_spend_progress >= Config.resource.p02_spend_threshold then
            state.p02_spend_progress = state.p02_spend_progress - Config.resource.p02_spend_threshold
            if now >= state.p02_ready_at then
                state.p02_ready_at = now + Config.resource.p02_internal_cooldown
                result.p02_trigger = { rank = p02 }
            end
        end
    end

    if M.is_mingjie_active(state, now) and state.mingjie.tier >= 3 then
        state.mingjie.spent_meter = state.mingjie.spent_meter + token.spent
        if state.mingjie.spent_meter >= Config.ultimate.tier3_spend_threshold
            and state.mingjie.echo_count < Config.ultimate.tier3_echo_cap then
            state.mingjie.spent_meter = state.mingjie.spent_meter - Config.ultimate.tier3_spend_threshold
            state.mingjie.echo_count = state.mingjie.echo_count + 1
            result.tier3_echo = true
        end
    end
    return result
end

function M.confirm_cast(state, cast_id, now)
    local token = state.casts[cast_id]
    if not token then return nil, 'unknown-cast' end
    if token.confirmed then return nil, 'cast-already-confirmed' end
    if now - token.committed_at > Config.resource.pending_cast_timeout then
        state.casts[cast_id] = nil
        return nil, 'cast-expired'
    end
    token.confirmed = true
    state.casts[cast_id] = nil
    state.last_effective_at = now
    return token, post_effective_spend(state, token, now)
end

function M.finish_cast(state, cast_id, now, reason)
    local token = state.casts[cast_id]
    if not token then return nil, 'unknown-cast' end
    state.casts[cast_id] = nil
    token.finish_reason = reason or 'missed'
    token.finished_at = now
    return token, { state_event(state, 'spender_missed') }
end

function M.activate_ultimate(state, now)
    if state.ultimate_tier < 1 then return nil, 'ultimate-locked' end
    if state.ultimate_gauge < Config.resource.ultimate_max then return nil, 'insufficient-ultimate' end
    if M.is_mingjie_active(state, now) then return nil, 'mingjie-active' end
    state.ultimate_gauge = 0
    state.mingjie = {
        tier = state.ultimate_tier,
        expires_at = now + value_at(Config.ultimate.duration, state.ultimate_tier),
        tier2_refunds = 0,
        tier2_used_skills = {},
        spent_meter = 0,
        echo_count = 0,
    }
    state.last_effective_at = now
    return state.mingjie, state_event(state, 'ultimate_activated')
end

function M.try_tier2_refund(state, token, now)
    local realm = state.mingjie
    if not realm or now >= realm.expires_at or realm.tier < 2 or token.spent <= 0 then return 0, {} end
    if token.skill_key ~= 'C03_A03' and token.skill_key ~= 'C03_A04' and token.skill_key ~= 'C03_A05' then return 0, {} end
    if realm.tier2_used_skills[token.skill_key] or realm.tier2_refunds >= Config.ultimate.tier2_refund_cap then return 0, {} end
    realm.tier2_used_skills[token.skill_key] = true
    realm.tier2_refunds = realm.tier2_refunds + 1
    return M.refund_seal(state, now, 'mingjie-tier2', 'refunded')
end

function M.tick(state, now)
    local result = { events = {}, expired_statuses = {} }
    state.last_tick_at = now
    for key, status in pairs(state.statuses) do
        if status.expires_at and now >= status.expires_at then
            state.statuses[key] = nil
            append(result.expired_statuses, status)
        end
    end
    if state.mingjie and now >= state.mingjie.expires_at then
        state.mingjie = nil
        append(result.events, state_event(state, 'mingjie_expired'))
    end
    if state.resource_enabled and state.seals > 0 and now - state.last_effective_at >= Config.resource.out_of_combat_clear_delay then
        clear_seals(state)
        state.p01_armed = false
        append(result.events, state_event(state, 'seals_cleared_out_of_combat'))
    end
    for cast_id, token in pairs(state.casts) do
        if now - token.committed_at > Config.resource.pending_cast_timeout then state.casts[cast_id] = nil end
    end
    return result
end

function M.clear_transient(state, now)
    clear_seals(state)
    state.ultimate_gauge = 0
    state.statuses = {}
    state.casts = {}
    state.p01_spend_progress = 0
    state.p01_armed = false
    state.p02_spend_progress = 0
    state.mingjie = nil
    state.last_effective_at = now
    state.last_tick_at = now
    return state_event(state, 'transient_cleared')
end

return M
