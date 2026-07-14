local M = {}
local TargetContract = require 'powang_target_contract'

local Targeting = {}
Targeting.__index = Targeting

local geometry = {
    C01_A01 = { shape = 'sector', radius = 2.5, angle = 120 },
    C01_A02 = { shape = 'rectangle', length = 3.5, width = 0.8 },
    C01_A03 = { shape = 'sector', radius = 2.8, angle = 60 },
    C01_A04 = { shape = 'rectangle', length = 4.5, width = 1.0 },
    C01_A05 = { shape = 'circle', radius = 3.0 },
    C01_A06 = { shape = 'rectangle', length = 4.2, width = 1.2 },
    C01_A07 = { shape = 'sector', radius = 2.0, angle = 120 },
    C01_A08 = { shape = 'rectangle', length = 5.0, width = 1.3 },
    C01_U01 = { shape = 'circle', radius = 4.0 },
}

function M.new(options)
    options = options or {}
    assert(_G.y3, 'powang_y3_targeting must be loaded inside Y3')
    return setmetatable({
        options = options,
        distance_scale = options.distance_scale or 100,
        modifier_ids = options.modifier_ids or {},
    }, Targeting)
end

local function shape_and_center(source, definition, direction, scale)
    local point = source:get_point()
    if definition.shape == 'circle' then
        return y3.shape.create_circular_shape(definition.radius * scale), point
    end
    if definition.shape == 'sector' then
        return y3.shape.create_sector_shape(definition.radius * scale, definition.angle, direction), point
    end
    local length = definition.length * scale
    local center = y3.point.get_point_offset_vector(point, direction, length / 2)
    return y3.shape.create_rectangle_shape(definition.width * scale, length, direction), center
end

function Targeting:_select(source, definition, direction)
    local shape, center = shape_and_center(source, definition, direction, self.distance_scale)
    return y3.selector.create()
        :in_shape(center, shape)
        :is_enemy(source:get_owner())
        :not_in_state(y3.const.UnitEnumState['无敌'])
        :without_tag(self.options.excluded_tag or '剧情无敌')
        :pick()
end

function Targeting:_team(source, radius)
    return y3.selector.create()
        :in_range(source, radius * self.distance_scale)
        :is_ally(source:get_owner())
        :pick()
end

local function target_rank(targeting, target)
    if type(targeting.options.target_rank) == 'function' then
        return targeting.options.target_rank(target)
    end
    return nil
end

function Targeting:build_context(runtime, actor_id, skill_key, rank, source, ability, event_data)
    local definition = geometry[skill_key]
    if not definition then
        return TargetContract.populate_context({
            ability = ability,
            skill_key = skill_key,
            hit = false,
            no_miss = true,
        }, source, actor_id, {}, {})
    end
    local direction = source:get_facing()
    if type(self.options.resolve_direction) == 'function' then
        direction = self.options.resolve_direction(actor_id, source, ability, event_data, direction)
    end

    local targets = self:_select(source, definition, direction) or {}
    local team_targets = {}
    if skill_key == 'C01_A08' then
        team_targets = self:_team(source, 6.0) or {}
    end

    local context = TargetContract.populate_context({
        ability = ability,
        skill_key = skill_key,
        angle = direction,
        hit = #targets > 0,
        no_miss = true,
    }, source, actor_id, targets, team_targets)
    context.target_meta_by_id = {}
    for index, target in ipairs(context.targets) do
        local target_id = context.target_ids[index]
        context.target_meta_by_id[target_id] = {
            rank = target_rank(self, target),
        }
    end
    if skill_key == 'C01_A03' then
        context.hit_count = #targets > 0 and 3 or 0
        context.same_target_all = #targets == 1
    end
    if targets[1] then
        context.target = targets[1]
        context.target_id = context.target_ids[1]
        context.target_point = targets[1]:get_point()
        context.target_rank = context.target_meta_by_id[context.target_id].rank
        local xianwang_id = self.modifier_ids.C01_M02_XIANWANG
        context.xianwang = xianwang_id and targets[1]:find_buff(xianwang_id) ~= nil or false
        if type(self.options.target_health_ratio) == 'function' then
            context.target_health_ratio = self.options.target_health_ratio(targets[1])
        else
            local maximum = targets[1]:get_attr('最大生命')
            context.target_health_ratio = maximum > 0 and targets[1]:get_attr('生命') / maximum or 0
        end
    end
    if type(self.options.decorate_context) == 'function' then
        self.options.decorate_context(runtime, actor_id, skill_key, rank, context)
    end
    return context
end

return M
