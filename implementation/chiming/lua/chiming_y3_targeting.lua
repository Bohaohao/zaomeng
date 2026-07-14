-- custom-built: C03 targeting translates only authoritative cast snapshots.
-- Hit confirmation, path contacts and pulse reselection stay project-owned.
local M = {}
local TargetContract = require 'chiming_target_contract'

local Targeting = {}
Targeting.__index = Targeting

local primary_skills = {
    C03_A01 = true,
    C03_A03 = true,
    C03_A06 = true,
}

local hit_confirmed_skills = {
    C03_A01 = true,
    C03_A02 = true,
    C03_A03 = true,
    C03_A05 = true,
    C03_A06 = true,
    C03_A08 = true,
}

local team_radii = {
    C03_A07 = 4.0,
    C03_A08 = 3.5,
}

function M.new(options)
    options = options or {}
    assert(_G.y3, 'chiming_y3_targeting must be loaded inside Y3')
    return setmetatable({ options = options, distance_scale = options.distance_scale or 100 }, Targeting)
end

function Targeting:requires_cast_point(skill_key)
    return skill_key == 'C03_A05' or skill_key == 'C03_A08'
end

function Targeting:requires_hit_confirmation(skill_key)
    return hit_confirmed_skills[skill_key] == true
end

local function id_of(unit)
    return TargetContract.id_of(unit)
end

local function append(list, value)
    list[#list + 1] = value
end

local function unit_available(unit)
    if unit == nil then return false end
    if type(unit.is_exist) == 'function' and not unit:is_exist() then return false end
    if type(unit.is_alive) == 'function' and not unit:is_alive() then return false end
    return true
end

local function sort_by_id(units)
    table.sort(units, function(left, right)
        return tostring(id_of(left)) < tostring(id_of(right))
    end)
    return units
end

local function normalize_units(value)
    if type(value) ~= 'table' then return {} end
    return value.units or value.targets or value.members or value
end

function Targeting:_resolve_cast_point(runtime, actor_id, skill_key, source, ability, event_data)
    if type(self.options.resolve_cast_point) ~= 'function' then return nil, 'cast-point-required' end
    local point, error_code = self.options.resolve_cast_point(runtime, actor_id, skill_key, source, ability, event_data)
    if not point then return nil, error_code or 'cast-point-required' end
    return point
end

function Targeting:_resolve_primary(runtime, actor_id, skill_key, source, ability, event_data)
    if type(self.options.resolve_primary_target) ~= 'function' then return nil, nil, 'primary-target-required' end
    local result, error_code = self.options.resolve_primary_target(runtime, actor_id, skill_key, source, ability, event_data)
    local target = type(result) == 'table' and (result.target or result.unit) or result
    local target_id = type(result) == 'table' and (result.target_id or result.id) or nil
    target_id = target_id or id_of(target)
    if target_id == nil or not unit_available(target) then return nil, nil, error_code or 'primary-target-required' end
    return target_id, target
end

function Targeting:_team(runtime, actor_id, skill_key, source, ability, event_data, radius)
    if type(self.options.resolve_team_members) ~= 'function' then return {} end
    local result = self.options.resolve_team_members(runtime, actor_id, skill_key, source, ability, event_data, radius)
    local members, seen = {}, {}
    local source_id = id_of(source)
    for _, unit in ipairs(normalize_units(result)) do
        local unit_id = id_of(unit)
        if unit_id ~= nil and unit_id ~= source_id and not seen[unit_id] and unit_available(unit) then
            seen[unit_id] = true
            append(members, unit)
        end
    end
    return sort_by_id(members)
end

function Targeting:_select_ultimate(source)
    local units = y3.selector.create()
        :in_range(source, 4.2 * self.distance_scale)
        :is_enemy(source:get_owner())
        :not_in_state(y3.const.UnitEnumState['无敌'])
        :without_tag(self.options.excluded_tag or '剧情无敌')
        :pick() or {}
    return sort_by_id(units)
end

local function target_rank(targeting, target)
    if type(targeting.options.target_rank) == 'function' then
        local rank = targeting.options.target_rank(target)
        if rank == 'normal' or rank == 'elite' or rank == 'boss' then return rank end
    end
    return 'unknown'
end

local function normalize_self_purge(result)
    if result == true then return true end
    return type(result) == 'table' and result.success == true
end

local function carry_boss_contributions(context, result, allowed_target_ids)
    if type(result) ~= 'table' then return end
    local reports = result.boss_contributions
    if type(reports) ~= 'table' and type(result.boss_contribution) == 'table' then reports = { result.boss_contribution } end
    if type(reports) ~= 'table' then return end
    context.boss_contributions = context.boss_contributions or {}
    for _, report in ipairs(reports) do
        if allowed_target_ids == nil or allowed_target_ids[report.target_id] then
            append(context.boss_contributions, report)
        end
    end
end

local function normalize_team_purge(result, context, source)
    if type(result) ~= 'table' then return {}, {} end
    local refs = result.targets or result.units or result.success_targets or result
    local ids = result.target_ids or result.ids or result.success_ids or {}
    local allowed, output_ids, output_refs, seen = {}, {}, {}, {}
    for _, id in ipairs(context.team_target_ids or {}) do allowed[id] = true end
    local source_id = id_of(source)
    local function add(id, ref)
        if id == nil or id == source_id or not allowed[id] or seen[id] then return end
        ref = ref or context.target_refs_by_id[id] or context.target_refs_by_id[tostring(id)]
        if not unit_available(ref) then return end
        seen[id] = true
        append(output_ids, id)
        append(output_refs, ref)
    end
    for index, id in ipairs(ids) do add(id, refs[index]) end
    if #ids == 0 then
        for _, unit in ipairs(refs) do add(id_of(unit), unit) end
    end
    return output_ids, output_refs
end

local function add_metadata(targeting, runtime, actor_id, context, targets, now)
    context.target_meta_by_id = context.target_meta_by_id or {}
    for _, target in ipairs(targets or {}) do
        local target_id = id_of(target)
        if target_id ~= nil then
            context.target_refs_by_id[target_id] = target
            context.target_meta_by_id[target_id] = {
                rank = target_rank(targeting, target),
                private_minghen = runtime and runtime:get_effect(target_id, 'C03_M02_MINGHEN', now, actor_id) ~= nil,
                private_luyin = runtime and runtime:get_effect(target_id, 'C03_M06_LUYIN', now, actor_id) ~= nil,
            }
        end
    end
end

function Targeting:build_context(runtime, actor_id, skill_key, rank, source, ability, event_data)
    local cast_point
    if self:requires_cast_point(skill_key) then
        local error_code
        cast_point, error_code = self:_resolve_cast_point(runtime, actor_id, skill_key, source, ability, event_data)
        if not cast_point then
            return TargetContract.populate_context({
                ability = ability, skill_key = skill_key, cast_error = error_code,
                cast_point_required = true, no_miss = false,
            }, source, actor_id, {}, {})
        end
    end

    local team_targets = {}
    if team_radii[skill_key] then
        team_targets = self:_team(runtime, actor_id, skill_key, source, ability, event_data, team_radii[skill_key])
    end
    local selected = {}
    if skill_key == 'C03_U01' then
        if type(self.options.resolve_ultimate_targets) == 'function' then
            selected = sort_by_id(normalize_units(self.options.resolve_ultimate_targets(runtime, actor_id, source, ability, event_data)))
        else
            selected = self:_select_ultimate(source)
        end
    end
    local context = TargetContract.populate_context({
        ability = ability,
        skill_key = skill_key,
        cast_point = cast_point,
        target_point = cast_point,
        hit = false,
        no_miss = false,
    }, source, actor_id, selected, team_targets)

    if primary_skills[skill_key] then
        local primary_id, primary, error_code = self:_resolve_primary(runtime, actor_id, skill_key, source, ability, event_data)
        if not primary_id then
            context.cast_error = error_code
            return context
        end
        context.primary_target_id = primary_id
        context.primary_target_ref = primary
        context.target_id = primary_id
        context.target = primary
        context.primary_target = primary
        context.target_refs_by_id[primary_id] = primary
    end

    local state = runtime and runtime:get_state(actor_id)
    if ((skill_key == 'C03_A04' and state and state.seals >= 3) or skill_key == 'C03_A07')
        and type(self.options.resolve_self_purge) == 'function' then
        local result = self.options.resolve_self_purge(runtime, actor_id, skill_key, source, ability, event_data, context)
        context.self_purge_success = normalize_self_purge(result)
        carry_boss_contributions(context, result)
    end
    if skill_key == 'C03_A08' and type(self.options.resolve_team_purge) == 'function' then
        local result = self.options.resolve_team_purge(runtime, actor_id, source, ability, event_data, context.team_targets, context)
        context.team_purge_success_ids, context.team_purge_success_targets = normalize_team_purge(result, context, source)
        local allowed = {}
        for _, target_id in ipairs(context.team_purge_success_ids) do allowed[target_id] = true end
        carry_boss_contributions(context, result, allowed)
    end

    local now = y3.game.current_game_run_time()
    add_metadata(self, runtime, actor_id, context, selected, now)
    if context.primary_target_ref then add_metadata(self, runtime, actor_id, context, { context.primary_target_ref }, now) end
    if type(self.options.decorate_context) == 'function' then self.options.decorate_context(runtime, actor_id, skill_key, rank, context) end
    return context
end

return M
