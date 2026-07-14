local M = {}
local TargetContract = require 'zhenjie_target_contract'

local Targeting = {}
Targeting.__index = Targeting

local geometry = {
    C02_A01 = { shape = 'sector', radius = 2.6, angle = 120 },
    C02_A02 = { shape = 'rectangle', length = 3.8, width = 0.9 },
    C02_A03 = { shape = 'sector', radius = 2.8, angle = 140 },
    C02_A05 = { shape = 'circle', radius = 3.5, point_targeted = true },
    C02_A06 = { shape = 'rectangle', length = 4.0, width = 1.4 },
    C02_A08 = { shape = 'circle', radius = 3.5, point_targeted = true },
    C02_U01 = { shape = 'circle', radius = 4.0 },
}

function M.new(options)
    options = options or {}
    assert(_G.y3, 'zhenjie_y3_targeting must be loaded inside Y3')
    return setmetatable({
        options = options,
        distance_scale = options.distance_scale or 100,
    }, Targeting)
end

function Targeting:requires_cast_point(skill_key)
    return geometry[skill_key] and geometry[skill_key].point_targeted == true or false
end

local function shape_and_center(source, definition, direction, scale, cast_point)
    local source_point = source:get_point()
    if definition.shape == 'circle' then
        return y3.shape.create_circular_shape(definition.radius * scale), cast_point or source_point
    end
    if definition.shape == 'sector' then
        return y3.shape.create_sector_shape(definition.radius * scale, definition.angle, direction), source_point
    end
    local length = definition.length * scale
    local center = y3.point.get_point_offset_vector(source_point, direction, length / 2)
    return y3.shape.create_rectangle_shape(definition.width * scale, length, direction), center
end

function Targeting:_select(source, definition, direction, cast_point)
    local shape, center = shape_and_center(source, definition, direction, self.distance_scale, cast_point)
    return y3.selector.create()
        :in_shape(center, shape)
        :is_enemy(source:get_owner())
        :not_in_state(y3.const.UnitEnumState['无敌'])
        :without_tag(self.options.excluded_tag or '剧情无敌')
        :pick()
end

function Targeting:_team(source, radius)
    local picked = y3.selector.create()
        :in_range(source, radius * self.distance_scale)
        :is_ally(source:get_owner())
        :pick() or {}
    local allies = {}
    for _, unit in ipairs(picked) do
        if unit ~= source then
            allies[#allies + 1] = unit
        end
    end
    return allies
end

function Targeting:_resolve_cast_point(runtime, actor_id, skill_key, source, ability, event_data)
    if type(self.options.resolve_cast_point) ~= 'function' then
        return nil, 'cast-point-required'
    end
    local point, error_code = self.options.resolve_cast_point(
        runtime,
        actor_id,
        skill_key,
        source,
        ability,
        event_data
    )
    if not point then
        return nil, error_code or 'cast-point-required'
    end
    return point
end

local function target_rank(targeting, target)
    if type(targeting.options.target_rank) == 'function' then
        return targeting.options.target_rank(target) or 'normal'
    end
    return 'normal'
end

function Targeting:build_context(runtime, actor_id, skill_key, rank, source, ability, event_data)
    local definition = geometry[skill_key]
    if not definition then
        local team_targets = skill_key == 'C02_A07' and self:_team(source, 6.0) or {}
        return TargetContract.populate_context({
            ability = ability,
            skill_key = skill_key,
            hit = false,
            no_miss = true,
        }, source, actor_id, {}, team_targets)
    end

    local direction = source:get_facing()
    if type(self.options.resolve_direction) == 'function' then
        direction = self.options.resolve_direction(actor_id, source, ability, event_data, direction)
    end

    local cast_point
    if definition.point_targeted then
        local error_code
        cast_point, error_code = self:_resolve_cast_point(runtime, actor_id, skill_key, source, ability, event_data)
        if not cast_point then
            return TargetContract.populate_context({
                ability = ability,
                skill_key = skill_key,
                cast_error = error_code,
                cast_point_required = true,
                no_miss = true,
            }, source, actor_id, {}, {})
        end
    end

    local targets = self:_select(source, definition, direction, cast_point) or {}
    local team_targets = {}
    if skill_key == 'C02_A07' or skill_key == 'C02_A08' then
        team_targets = self:_team(source, 6.0)
    end

    local context = TargetContract.populate_context({
        ability = ability,
        skill_key = skill_key,
        angle = direction,
        cast_point = cast_point,
        target_point = cast_point,
        hit = #targets > 0,
        no_miss = true,
    }, source, actor_id, targets, team_targets)
    context.target_meta_by_id = {}
    local now = y3.game.current_game_run_time()
    for index, target in ipairs(context.targets) do
        local target_id = context.target_ids[index]
        local private_mark = runtime
            and type(runtime.get_effect) == 'function'
            and runtime:get_effect(target_id, 'C02_M07_JIEDING_MARK', now, actor_id) ~= nil
        context.target_meta_by_id[target_id] = {
            rank = target_rank(self, target),
            private_jieding = private_mark == true,
        }
    end
    if skill_key == 'C02_A03' then
        context.hit_count = #targets > 0 and 2 or 0
        -- Default no-miss geometry designates one primary target; additional
        -- nearby enemies no longer invalidate a two-hit primary sequence.
        context.primary_hit_twice = context.target_id ~= nil
    end
    if not context.target_point and context.target then
        context.target_point = context.target:get_point()
    end
    if type(self.options.decorate_context) == 'function' then
        self.options.decorate_context(runtime, actor_id, skill_key, rank, context)
    end
    return context
end

return M
