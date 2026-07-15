-- Authoritative C04 cast snapshots. This bridge refuses to infer primary
-- targets, points, directions or safety from generic candidate collections.
local TargetContract = require 'xunlie_target_contract'
local Core = require 'xunlie_core'

local M = {}
local Targeting = {}
Targeting.__index = Targeting

local primary_skills = {
    C04_A01 = true, C04_A03 = true, C04_A06 = true, C04_A07 = true, C04_U01 = true,
}

local direction_skills = { C04_A02 = true, C04_A04 = true }
local point_skills = { C04_A05 = true, C04_A08 = true }
local selected_limits = { C04_A05 = 5, C04_A08 = 6, C04_U01 = 2 }

local function append(list, value)
    list[#list + 1] = value
end

local function id_of(unit)
    return TargetContract.id_of(unit)
end

local function unit_available(unit)
    if unit == nil then return false end
    if type(unit.is_exist) == 'function' and not unit:is_exist() then return false end
    if type(unit.is_alive) == 'function' and not unit:is_alive() then return false end
    return true
end

local function normalize_units(value)
    if type(value) ~= 'table' then return {} end
    return value.units or value.targets or value.selected_targets or value
end

local function sort_by_id(units)
    table.sort(units, function(left, right) return tostring(id_of(left)) < tostring(id_of(right)) end)
    return units
end

local function distance_of(targeting, source, target)
    if type(targeting.options.target_distance) ~= 'function' then return math.huge end
    local distance = targeting.options.target_distance(source, target)
    return type(distance) == 'number' and distance or math.huge
end

local function sort_selected(targeting, runtime, actor_id, skill_key, source, units)
    local state = runtime and type(runtime.get_state) == 'function' and runtime:get_state(actor_id) or nil
    table.sort(units, function(left, right)
        if skill_key == 'C04_A05' and state then
            local left_marks = Core.available_marks(state, id_of(left))
            local right_marks = Core.available_marks(state, id_of(right))
            if left_marks ~= right_marks then return left_marks > right_marks end
        end
        local left_distance = distance_of(targeting, source, left)
        local right_distance = distance_of(targeting, source, right)
        if left_distance ~= right_distance then return left_distance < right_distance end
        return tostring(id_of(left)) < tostring(id_of(right))
    end)
    return units
end

local function rank_of(targeting, target)
    if type(targeting.options.target_rank) == 'function' then
        local rank = targeting.options.target_rank(target)
        if rank == 'normal' or rank == 'elite' or rank == 'boss' then return rank end
    end
    return 'unknown'
end

function M.new(options)
    options = options or {}
    assert(_G.y3, 'xunlie_y3_targeting must be loaded inside Y3')
    return setmetatable({ options = options }, Targeting)
end

function Targeting:_primary(runtime, actor_id, skill_key, source, ability, event_data)
    if type(self.options.resolve_primary_target) ~= 'function' then return nil, nil, 'primary-target-required' end
    local result, error_code = self.options.resolve_primary_target(runtime, actor_id, skill_key, source, ability, event_data)
    local target = type(result) == 'table' and (result.target or result.unit) or result
    local target_id = type(result) == 'table' and (result.target_id or result.id) or nil
    target_id = target_id or id_of(target)
    if target_id == nil or not unit_available(target) then return nil, nil, error_code or 'primary-target-required' end
    return target_id, target
end

function Targeting:_direction(runtime, actor_id, skill_key, source, ability, event_data)
    if type(self.options.resolve_cast_direction) ~= 'function' then return nil, 'cast-direction-required' end
    local direction, error_code = self.options.resolve_cast_direction(runtime, actor_id, skill_key, source, ability, event_data)
    if direction == nil then return nil, error_code or 'cast-direction-required' end
    return direction
end

function Targeting:_point(runtime, actor_id, skill_key, source, ability, event_data)
    if type(self.options.resolve_cast_point) ~= 'function' then return nil, 'cast-point-required' end
    local point, error_code = self.options.resolve_cast_point(runtime, actor_id, skill_key, source, ability, event_data)
    if point == nil then return nil, error_code or 'cast-point-required' end
    return point
end

function Targeting:_safe_landing(runtime, actor_id, source, ability, event_data)
    if type(self.options.resolve_safe_landing) ~= 'function' then return nil, 'safe-landing-required' end
    local result, error_code = self.options.resolve_safe_landing(runtime, actor_id, 'C04_A04', source, ability, event_data)
    local point = type(result) == 'table' and (result.point or result.safe_landing_point) or result
    local allowed = type(result) == 'table' and result.allowed ~= false or point ~= nil
    if not allowed or point == nil then return nil, error_code or 'safe-landing-required' end
    return point
end

function Targeting:_selected(runtime, actor_id, skill_key, source, ability, event_data, limit)
    if type(self.options.resolve_selected_targets) ~= 'function' then return {} end
    -- The selector supplies all legal in-radius candidates. C04 owns the
    -- final cap because A05 must prefer the actor's private mark counts.
    local result = self.options.resolve_selected_targets(runtime, actor_id, skill_key, source, ability, event_data, nil)
    local output, seen = {}, {}
    for _, target in ipairs(normalize_units(result)) do
        local target_id = id_of(target)
        if target_id ~= nil and not seen[target_id] and unit_available(target) then
            seen[target_id] = true
            append(output, target)
        end
    end
    sort_selected(self, runtime, actor_id, skill_key, source, output)
    while #output > limit do output[#output] = nil end
    return output
end

local function add_metadata(targeting, runtime, actor_id, context, targets, now)
    context.target_meta_by_id = context.target_meta_by_id or {}
    for _, target in ipairs(targets or {}) do
        local target_id = id_of(target)
        if target_id ~= nil then
            context.target_refs_by_id[target_id] = target
            context.target_meta_by_id[target_id] = {
                rank = rank_of(targeting, target),
                distance = type(targeting.options.target_distance) == 'function'
                    and targeting.options.target_distance(context.unit, target) or nil,
                has_own_m08_pre_hit = runtime and runtime:get_effect(target_id, 'C04_M08_NET', now, actor_id) ~= nil,
            }
        end
    end
end

function Targeting:build_context(runtime, actor_id, skill_key, rank, source, ability, event_data)
    local selected = {}
    if selected_limits[skill_key] then selected = self:_selected(runtime, actor_id, skill_key, source, ability, event_data, selected_limits[skill_key]) end
    local context = TargetContract.populate_context({
        ability = ability, skill_key = skill_key, hit = false, no_miss = false,
        combat_scope = type(self.options.resolve_combat_scope) == 'function'
            and self.options.resolve_combat_scope(runtime, actor_id, source, event_data) or 'public',
    }, source, actor_id, selected, {})
    context.selected_target_ids, context.selected_targets = context.target_ids, context.targets
    context.target_ids, context.targets = {}, {}
    context.target, context.target_id, context.primary_target = nil, nil, nil
    context.target_count = #context.selected_target_ids

    if primary_skills[skill_key] then
        local target_id, target, error_code = self:_primary(runtime, actor_id, skill_key, source, ability, event_data)
        if not target_id then context.cast_error = error_code; return context end
        context.primary_target_id, context.primary_target_ref = target_id, target
        context.target_refs_by_id[target_id] = target
    end
    if direction_skills[skill_key] then
        local direction, error_code = self:_direction(runtime, actor_id, skill_key, source, ability, event_data)
        if direction == nil then context.cast_error = error_code; return context end
        context.direction = direction
    end
    if point_skills[skill_key] then
        local point, error_code = self:_point(runtime, actor_id, skill_key, source, ability, event_data)
        if point == nil then context.cast_error = error_code; return context end
        context.cast_point, context.target_point = point, point
    end
    if skill_key == 'C04_A04' then
        local point, error_code = self:_safe_landing(runtime, actor_id, source, ability, event_data)
        if point == nil then context.cast_error = error_code; return context end
        context.safe_landing_result, context.safe_landing_point = true, point
    end
    local now = y3.game.current_game_run_time()
    add_metadata(self, runtime, actor_id, context, selected, now)
    if context.primary_target_ref then add_metadata(self, runtime, actor_id, context, { context.primary_target_ref }, now) end
    if type(self.options.decorate_context) == 'function' then self.options.decorate_context(runtime, actor_id, skill_key, rank, context) end
    return context
end

function Targeting:build_pulse_context(actor_id, command, source, context)
    if type(self.options.resolve_pulse_targets) ~= 'function' then return nil end
    local result = self.options.resolve_pulse_targets(actor_id, command.pulse_key, command, context)
    local targets, seen = {}, {}
    for _, target in ipairs(normalize_units(result)) do
        local target_id = id_of(target)
        if target_id ~= nil and not seen[target_id] and unit_available(target) then
            seen[target_id] = true
            append(targets, target)
        end
    end
    sort_by_id(targets)
    local limit = command.target_limit or #targets
    while #targets > limit do targets[#targets] = nil end
    local pulse = TargetContract.populate_context({
        now = context and context.now, lifecycle_id = context and context.lifecycle_id,
        combat_scope = context and context.combat_scope, session_instance_id = context and context.session_instance_id,
        session_epoch = context and context.session_epoch,
    }, source, actor_id, targets, {})
    pulse.selected_target_ids, pulse.selected_targets = pulse.target_ids, pulse.targets
    pulse.target_ids, pulse.targets = {}, {}
    return pulse
end

return M
