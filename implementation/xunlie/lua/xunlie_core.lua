-- C04's engine-neutral hunt-mark state. A state belongs to exactly one
-- character_profile_id; all target state is therefore private to that actor.
local Config = require 'xunlie_config'

local M = {}

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

local function active_ultimate(state, now)
    return state.ultimate ~= nil and now < state.ultimate.expires_at
end

local function core_skill_learned(state)
    for _, key in ipairs(Config.resource.core_skills) do
        if (state.ability_levels[key] or 0) > 0 then return true end
    end
    return false
end

local function count_tracked(state)
    local count = 0
    for _ in pairs(state.hunt_by_target) do count = count + 1 end
    return count
end

local function reservations_for_target(state, target_id)
    local count = 0
    for _, token in pairs(state.casts) do
        for _, reservation in pairs(token.reservations or {}) do
            if reservation.target_id == target_id and not reservation.released and not reservation.confirmed then
                count = count + reservation.count
            end
        end
    end
    return count
end

local function hunt_entry(state, target_id)
    return state.hunt_by_target[target_id] or state.hunt_by_target[tostring(target_id)]
end

local function hunt_event(state, event_type, target_id, reason)
    local entry = target_id ~= nil and hunt_entry(state, target_id) or nil
    return {
        type = event_type,
        target_id = target_id,
        marks = entry and entry.count or 0,
        locked = entry and entry.count >= Config.resource.marks_max or false,
        tracked_targets = count_tracked(state),
        resource_enabled = state.resource_enabled,
        ultimate_gauge = state.ultimate_gauge,
        reason = reason,
    }
end

local function refresh_frozen_decay(state, target_id, now)
    if not active_ultimate(state, now) then return end
    local realm = state.ultimate
    realm.frozen_decay_by_target = realm.frozen_decay_by_target or {}
    local previous = realm.frozen_decay_by_target[target_id] or {}
    realm.frozen_decay_by_target[target_id] = {
        remaining_ticks = Config.resource.idle_before_decay_ticks,
        revision = (previous.revision or 0) + 1,
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
    local state = {
        level = level,
        stats = stats,
        ability_levels = options.ability_levels or {},
        passive_levels = options.passive_levels or {},
        ultimate_tier = options.ultimate_tier or 0,
        current_hp = clamp(options.current_hp or stats.hp_max, 0, stats.hp_max),
        hunt_by_target = {},
        casts = {},
        statuses = {},
        next_cast_id = 1,
        ultimate_gauge = 0,
        ultimate = nil,
        combat_epoch_start = nil,
        first_recovery_earliest_tick = nil,
        -- This clock intentionally survives death, challenge failure, crossing
        -- a layer and re-registration for the same character profile.
        recovery_next_eligible_tick = options.recovery_next_eligible_tick or 0,
        last_tick_at = now,
        lifecycle_id = options.lifecycle_id,
    }
    state.resource_enabled = level >= Config.resource.unlock_level and core_skill_learned(state)
    return state
end

function M.set_health(state, current_hp)
    state.current_hp = clamp(current_hp, 0, state.stats.hp_max)
end

function M.set_level(state, level)
    local previous_max = state.stats.hp_max
    local ratio = previous_max > 0 and state.current_hp / previous_max or 1
    state.level = level
    state.stats = M.hero_stats(level)
    state.current_hp = clamp(round_half_up(state.stats.hp_max * ratio), 0, state.stats.hp_max)
    M.refresh_resource_enabled(state)
    return state.stats
end

function M.set_ability_level(state, skill_key, rank)
    state.ability_levels[skill_key] = rank
    return M.refresh_resource_enabled(state)
end

function M.refresh_resource_enabled(state)
    local previous = state.resource_enabled == true
    state.resource_enabled = state.level >= Config.resource.unlock_level and core_skill_learned(state)
    if previous and not state.resource_enabled then
        state.hunt_by_target = {}
        state.casts = {}
    end
    return state.resource_enabled, previous ~= state.resource_enabled
end

function M.is_resource_enabled(state)
    return state.resource_enabled == true
end

function M.hunt_count(state, target_id)
    local entry = hunt_entry(state, target_id)
    return entry and entry.count or 0
end

function M.is_locked(state, target_id)
    return M.hunt_count(state, target_id) >= Config.resource.marks_max
end

function M.available_marks(state, target_id)
    return math.max(0, M.hunt_count(state, target_id) - reservations_for_target(state, target_id))
end

function M.apply_status(state, key, now, duration, payload)
    local status = { key = key, applied_at = now, payload = payload or {} }
    status.expires_at = duration and now + duration or nil
    state.statuses[key] = status
    return status
end

function M.get_status(state, key, now)
    local status = state.statuses[key]
    if status and status.expires_at and now >= status.expires_at then
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

function M.decay_interval_ticks(state)
    local rank = passive_level(state, 'C04_P01')
    if rank <= 0 then return Config.resource.decay_interval_ticks[1] end
    return value_at(Config.passives.C04_P01.decay_interval_ticks, rank)
        or Config.resource.decay_interval_ticks[1]
end

function M.gain_hunt(state, target_id, now, source)
    if not M.is_resource_enabled(state) then return nil, 'resource-locked' end
    if target_id == nil then return nil, 'target-required' end
    if source ~= 'normal' and source ~= 'C04_A01' and source ~= 'C04_A02' then
        return nil, 'invalid-hunt-source'
    end

    local entry = hunt_entry(state, target_id)
    if not entry then
        if count_tracked(state) >= Config.resource.tracked_target_max then
            return nil, 'tracked-target-cap'
        end
        entry = { target_id = target_id, count = 0, next_normal_mark_at = 0 }
        state.hunt_by_target[target_id] = entry
    end
    if source == 'normal' and now < (entry.next_normal_mark_at or 0) then
        return { gained = 0, at_cap = entry.count >= Config.resource.marks_max, event = hunt_event(state, 'hunt_changed', target_id, 'normal-icd') }
    end
    if source == 'normal' then
        local cooldown = Config.resource.normal_attack_mark_cooldown_ticks
        if active_ultimate(state, now) and state.ultimate.tier >= 1 then cooldown = 108 end
        entry.next_normal_mark_at = now + cooldown
    end
    entry.last_refresh_at = now
    entry.next_decay_at = now + Config.resource.idle_before_decay_ticks + M.decay_interval_ticks(state)
    refresh_frozen_decay(state, target_id, now)
    if entry.count >= Config.resource.marks_max then
        return { gained = 0, at_cap = true, event = hunt_event(state, 'hunt_changed', target_id, 'refresh-at-cap') }
    end
    entry.count = entry.count + 1
    return { gained = 1, at_cap = entry.count >= Config.resource.marks_max, event = hunt_event(state, 'hunt_changed', target_id, source) }
end

function M.create_cast(state, skill_key, now, snapshot, direct_damage)
    snapshot = snapshot or {}
    local token = {
        id = state.next_cast_id,
        skill_key = skill_key,
        committed_at = now,
        expires_at = now + Config.resource.pending_cast_timeout_ticks,
        lifecycle_id = snapshot.lifecycle_id,
        snapshot = snapshot,
        reservations = {},
        direct_damage = direct_damage == true,
        finalized = false,
    }
    state.next_cast_id = state.next_cast_id + 1
    snapshot.cast_id = token.id
    snapshot.skill_key = skill_key
    state.casts[token.id] = token
    if direct_damage and state.combat_epoch_start == nil then
        state.combat_epoch_start = now
        state.first_recovery_earliest_tick = now + Config.resource.first_recovery_delay_ticks
    end
    return token
end

function M.get_cast(state, cast_id)
    return state.casts[cast_id]
end

function M.reserve_hunt(state, cast_id, target_id, count, now, reservation_key)
    local token = state.casts[cast_id]
    if not token then return nil, 'unknown-cast' end
    if now > token.expires_at then state.casts[cast_id] = nil; return nil, 'cast-expired' end
    if target_id == nil or count <= 0 then return nil, 'invalid-reservation' end
    local entry = hunt_entry(state, target_id)
    if not entry or M.available_marks(state, target_id) < count then return nil, 'insufficient-hunt-marks' end
    local key = reservation_key or tostring(target_id)
    if token.reservations[key] then return nil, 'target-already-reserved' end
    local reservation = {
        key = key,
        target_id = target_id,
        count = count,
        was_locked = entry.count >= Config.resource.marks_max,
        marks_before = entry.count,
        reserved_at = now,
    }
    token.reservations[key] = reservation
    return reservation
end

local function recovery_candidate(state, token, reservation, now)
    if not reservation.was_locked then return nil end
    if state.first_recovery_earliest_tick == nil or now < state.first_recovery_earliest_tick then return nil end
    if now < state.recovery_next_eligible_tick then return nil end
    return {
        cast_id = token.id,
        target_id = reservation.target_id,
        accepted_at = now,
    }
end

-- A candidate is deliberately side-effect free. Multi-target skills choose a
-- frozen preferred target at cast close, then this single CAS-like operation
-- writes the shared recovery clock exactly once.
function M.commit_recovery(state, token, candidate, now)
    if type(candidate) ~= 'table' or candidate.cast_id ~= token.id then return nil, 'invalid-recovery-candidate' end
    if state.first_recovery_earliest_tick == nil or candidate.accepted_at < state.first_recovery_earliest_tick then
        return nil, 'recovery-not-yet-eligible'
    end
    if candidate.accepted_at < state.recovery_next_eligible_tick then return nil, 'recovery-cooldown' end
    state.recovery_next_eligible_tick = candidate.accepted_at + Config.resource.recovery_cooldown_ticks
    local during_ultimate = active_ultimate(state, candidate.accepted_at)
    if not during_ultimate then
        state.ultimate_gauge = clamp(state.ultimate_gauge + Config.resource.ultimate_per_recovery, 0, Config.resource.ultimate_max)
    end
    local result = {
        type = 'hunt_recovery',
        cast_id = token.id,
        target_id = candidate.target_id,
        ultimate_gauge = state.ultimate_gauge,
        next_eligible_tick = state.recovery_next_eligible_tick,
    }
    local realm = state.ultimate
    if during_ultimate and realm then realm.had_recovery = true end
    if during_ultimate and realm and realm.tier >= 3 and realm.reverb_count < Config.ultimate.tier3_reverb_cap then
        realm.reverb_count = realm.reverb_count + 1
        result.reverb_coefficient = Config.ultimate.tier3_recovery_reverb
        result.reverb_index = realm.reverb_count
    end
    return result
end

function M.confirm_reservation(state, cast_id, target_id, now, reservation_key, options)
    local token = state.casts[cast_id]
    if not token then return nil, 'unknown-cast' end
    if now > token.expires_at then state.casts[cast_id] = nil; return nil, 'cast-expired' end
    local reservation = token.reservations[reservation_key or tostring(target_id)]
    if not reservation or reservation.released then return nil, 'unknown-reservation' end
    if reservation.confirmed then return nil, 'reservation-already-confirmed' end
    local entry = hunt_entry(state, target_id)
    if not entry then return nil, 'hunt-target-missing' end
    reservation.confirmed = true
    entry.count = math.max(0, entry.count - reservation.count)
    entry.last_refresh_at = now
    entry.next_decay_at = now + Config.resource.idle_before_decay_ticks + M.decay_interval_ticks(state)
    if entry.count == 0 then
        state.hunt_by_target[entry.target_id] = nil
        if state.ultimate and state.ultimate.frozen_decay_by_target then
            state.ultimate.frozen_decay_by_target[target_id] = nil
        end
    end
    local candidate = recovery_candidate(state, token, reservation, now)
    local recovery_event
    if candidate and not (options and options.defer_recovery == true) then
        recovery_event = M.commit_recovery(state, token, candidate, now)
    end
    return {
        reservation = reservation,
        recovery_candidate = candidate,
        recovery = recovery_event,
        event = hunt_event(state, 'hunt_changed', target_id, 'consumed'),
    }
end

function M.release_reservation(state, cast_id, target_id, reason, reservation_key)
    local token = state.casts[cast_id]
    if not token then return false end
    local reservation = token.reservations[reservation_key or tostring(target_id)]
    if not reservation or reservation.confirmed or reservation.released then return false end
    reservation.released = true
    reservation.release_reason = reason or 'missed'
    return true
end

function M.finalize_cast(state, cast_id, now, reason)
    local token = state.casts[cast_id]
    if not token then return nil, 'unknown-cast' end
    for target_key, reservation in pairs(token.reservations) do
        if not reservation.confirmed then
            reservation.released = true
            reservation.release_reason = reason or 'finalized'
        end
        token.reservations[target_key] = reservation
    end
    token.finalized = true
    token.finalized_at = now
    token.finish_reason = reason or 'finalized'
    state.casts[cast_id] = nil
    return token
end

function M.activate_ultimate(state, now, primary_target_id)
    if state.ultimate_tier < 1 then return nil, 'ultimate-locked' end
    if state.ultimate_gauge < Config.resource.ultimate_max then return nil, 'insufficient-ultimate' end
    if primary_target_id == nil then return nil, 'primary-target-required' end
    if active_ultimate(state, now) then return nil, 'ultimate-active' end
    local tier = clamp(state.ultimate_tier, 1, 3)
    local frozen_decay_by_target = {}
    for target_id, entry in pairs(state.hunt_by_target) do
        frozen_decay_by_target[target_id] = {
            remaining_ticks = math.max(0, (entry.next_decay_at or now) - now),
            revision = 1,
        }
    end
    state.ultimate_gauge = 0
    state.ultimate = {
        tier = tier,
        primary_target_id = primary_target_id,
        expires_at = now + Config.ultimate.duration_ticks[tier],
        reaction_count = 0,
        reverb_count = 0,
        reaction_skills = {},
        had_recovery = false,
        frozen_decay_by_target = frozen_decay_by_target,
    }
    return state.ultimate, {
        type = 'ultimate_activated',
        ultimate_gauge = state.ultimate_gauge,
        primary_target_id = primary_target_id,
        expires_at = state.ultimate.expires_at,
        tier = tier,
    }
end

function M.try_ultimate_skill_reaction(state, now, skill_key)
    local realm = state.ultimate
    if not active_ultimate(state, now) or realm.tier < 2 then return nil end
    if realm.reaction_count >= Config.ultimate.tier2_reaction_cap then return nil end
    if realm.reaction_skills[skill_key] then return nil end
    realm.reaction_skills[skill_key] = true
    realm.reaction_count = realm.reaction_count + 1
    return { skill_key = skill_key, coefficient = Config.ultimate.tier2_skill_reaction, index = realm.reaction_count }
end

function M.clear_target(state, target_id)
    local entry = hunt_entry(state, target_id)
    if not entry then return false end
    state.hunt_by_target[entry.target_id] = nil
    if state.ultimate and state.ultimate.frozen_decay_by_target then
        state.ultimate.frozen_decay_by_target[target_id] = nil
    end
    for _, token in pairs(state.casts) do
        for _, reservation in pairs(token.reservations) do
            if reservation.target_id == target_id and not reservation.confirmed then
                reservation.released = true
                reservation.release_reason = 'target-cleared'
            end
        end
    end
    return true
end

function M.tick(state, now)
    assert(now >= state.last_tick_at, 'time must be monotonic')
    local events = {}
    local frozen = active_ultimate(state, now)
    if state.ultimate and not frozen then
        for target_id, snapshot in pairs(state.ultimate.frozen_decay_by_target or {}) do
            local entry = state.hunt_by_target[target_id]
            if entry then entry.next_decay_at = now + math.max(0, snapshot.remaining_ticks or 0) end
        end
        local expired = state.ultimate
        state.ultimate = nil
        append(events, {
            type = 'ultimate_expired', ultimate_gauge = state.ultimate_gauge,
            tier = expired.tier, had_recovery = expired.had_recovery == true,
        })
    end
    for key, status in pairs(state.statuses) do
        if status.expires_at and now >= status.expires_at then state.statuses[key] = nil end
    end
    for cast_id, token in pairs(state.casts) do
        if now > token.expires_at then M.finalize_cast(state, cast_id, now, 'cast-expired') end
    end
    if not frozen then
        local interval = M.decay_interval_ticks(state)
        local targets = {}
        for target_id in pairs(state.hunt_by_target) do append(targets, target_id) end
        for _, target_id in ipairs(targets) do
            local entry = state.hunt_by_target[target_id]
            while entry and entry.count > 0 and entry.next_decay_at and now >= entry.next_decay_at do
                local was_below_three = entry.count < 3
                entry.count = entry.count - 1
                entry.next_decay_at = entry.next_decay_at + interval
                if passive_level(state, 'C04_P01') >= 5 and was_below_three and not entry.first_decay_pause_used then
                    entry.first_decay_pause_used = true
                    entry.next_decay_at = entry.next_decay_at + 30
                end
                append(events, hunt_event(state, 'hunt_changed', target_id, 'decay'))
                if entry.count == 0 then state.hunt_by_target[target_id] = nil; entry = nil end
            end
        end
    end
    state.last_tick_at = now
    return events
end

function M.clear_transient(state, now)
    state.hunt_by_target = {}
    state.casts = {}
    state.statuses = {}
    state.ultimate_gauge = 0
    state.ultimate = nil
    state.combat_epoch_start = nil
    state.first_recovery_earliest_tick = nil
    state.last_tick_at = now
    return hunt_event(state, 'transient_cleared', nil, 'lifecycle-cleanup')
end

function M.invalidate_lifecycle(state, next_lifecycle_id, now)
    local previous = state.lifecycle_id
    local event = M.clear_transient(state, now)
    state.lifecycle_id = next_lifecycle_id
    return previous, event
end

M.passive_level = passive_level
M.active_ultimate = active_ultimate

return M
