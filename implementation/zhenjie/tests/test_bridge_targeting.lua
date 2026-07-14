package.path = 'implementation/profession_common/lua/?.lua;implementation/zhenjie/lua/?.lua;' .. package.path

local Adapter = require 'zhenjie_y3_adapter'
local Targeting = require 'zhenjie_y3_targeting'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end
local function near(actual, expected, epsilon, message)
    tests = tests + 1
    if math.abs(actual - expected) > epsilon then
        error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    end
end

local timers = {}
local selector_result = {}
local function make_unit(id, owner)
    local unit = { id = id, owner = owner or 'enemy', exists = true, attrs = { ['最大生命'] = 100, ['生命'] = 100 }, buffs = {} }
    function unit:get_id() return self.id end
    function unit:is_exist() return self.exists end
    function unit:get_owner() return self.owner end
    function unit:get_point() return { owner = self.id } end
    function unit:get_facing() return 0 end
    function unit:get_attr(name) return self.attrs[name] or 0 end
    function unit:add_attr(name, amount) self.attrs[name] = (self.attrs[name] or 0) + amount end
    function unit:add_hp(amount) self.attrs['生命'] = self.attrs['生命'] + amount end
    function unit:find_buff(key) return self.buffs[key] end
    function unit:add_buff(data)
        local buff = { key = data.key, time = data.time, data = data.data }
        function buff:set_time(time) self.time = time end
        function buff:set_shield(value) self.shield = value end
        function buff:remove() unit.buffs[self.key] = nil end
        unit.buffs[data.key] = buff
        return buff
    end
    return unit
end

_G.y3 = {
    timer = { wait = function(delay, callback, description)
        local timer = { delay = delay, callback = callback, description = description }
        function timer:remove() self.removed = true end
        timers[#timers + 1] = timer
        return timer
    end },
    game = { current_game_run_time = function() return 0 end },
    const = { UnitEnumState = { ['无敌'] = 1, ['禁止移动'] = 2 } },
    shape = {
        create_circular_shape = function(radius) return { shape = 'circle', radius = radius } end,
        create_rectangle_shape = function(width, length, angle) return { shape = 'rectangle', width = width, length = length, angle = angle } end,
        create_sector_shape = function(radius, angle, facing) return { shape = 'sector', radius = radius, angle = angle, facing = facing } end,
    },
    point = { get_point_offset_vector = function(point) return point end },
    selector = { create = function()
        local selector = {}
        function selector:in_shape() return self end
        function selector:in_range() return self end
        function selector:is_enemy() return self end
        function selector:is_ally() return self end
        function selector:not_in_state() return self end
        function selector:without_tag() return self end
        function selector:pick() return selector_result end
        return selector
    end },
}

local hero = make_unit('hero', 'ally')
local ally = make_unit('ally', 'ally')
local enemy = make_unit('enemy', 'enemy')
local units = { hero = hero, ally = ally, enemy = enemy }
local adapter = Adapter.new {
    unit_by_actor = function(actor_id) return units[actor_id] end,
    modifier_ids = {
        C02_M08_BUDONG_BARRIER = 9008,
        C02_M09_BUDONG_GUARD = 9009,
        C02_M07_JIEDING_MARK = 9007,
        C02_M10_TONGSHOU = 9010,
    },
}

do
    adapter:apply_effect('hero', {
        type = 'apply_modifier', key = 'C02_M08_BUDONG_BARRIER', target_scope = 'self', duration = 3,
        payload = { max_hp_ratio = 0.15 },
    }, { unit = hero, targets = { enemy }, target_ids = { 'enemy' }, now = 0 })
    truthy(hero:find_buff(9008) ~= nil, 'self barrier applies to hero')
    truthy(enemy:find_buff(9008) == nil, 'self barrier never falls through to selected enemy')
    equal(hero:find_buff(9008).shield, 15, 'self barrier calculates target max health')
end

do
    selector_result = { enemy }
    local cast_point = { id = 'cast-point' }
    local targeting = Targeting.new {
        resolve_cast_point = function() return cast_point end,
        target_rank = function() return 'elite' end,
    }
    local runtime = {
        get_effect = function(_, unit_id, modifier_key, _, source_id)
            return unit_id == 'enemy' and modifier_key == 'C02_M07_JIEDING_MARK' and source_id == 'hero' and { source_id = 'hero' } or nil
        end,
    }
    local context = targeting:build_context(runtime, 'hero', 'C02_A05', 1, hero, {}, {})
    equal(context.target_point, cast_point, 'point-targeted A05 keeps the synchronized cast point')
    equal(context.target_meta_by_id.enemy.rank, 'elite', 'target metadata is captured per selected target')
    truthy(context.target_meta_by_id.enemy.private_jieding, 'private mark lookup is scoped to the casting actor')
    local rejected = Targeting.new({}):build_context(runtime, 'hero', 'C02_A08', 1, hero, {}, {})
    equal(rejected.cast_error, 'cast-point-required', 'point-targeted A08 never falls back to caster position')
end

do
    adapter:apply_effect('hero', {
        type = 'apply_modifier', key = 'C02_M09_BUDONG_GUARD', target_scope = 'self', duration = 2,
        payload = { damage_reduction = 0.15 },
    }, { unit = hero, selected_targets = { enemy }, selected_target_ids = { 'enemy' }, now = 0 })
    near(hero.attrs['受伤减免'], 15, 0.00001, 'self guard contributes only to hero')
    near(enemy.attrs['受伤减免'] or 0, 0, 0.00001, 'enemy receives no self damage reduction')
end

do
    adapter:apply_effect('hero', {
        type = 'apply_modifier', key = 'C02_M07_JIEDING_MARK', target_scope = 'selected', duration = 4,
    }, { unit = hero, selected_targets = { enemy }, selected_target_ids = { 'enemy' }, now = 0 })
    truthy(enemy:find_buff(9007) ~= nil, 'selected mark applies to enemy')
    adapter:apply_effect('hero', {
        type = 'remove_modifier', key = 'C02_M07_JIEDING_MARK', target_scope = 'explicit', target = enemy, target_id = 'enemy', source_id = 'hero',
    }, { unit = hero, selected_targets = { ally }, selected_target_ids = { 'ally' }, now = 1 })
    truthy(enemy:find_buff(9007) == nil, 'explicit cleanup removes bound enemy mark')
    truthy(ally:find_buff(9007) == nil, 'explicit cleanup does not touch current selection')
end

do
    adapter:apply_effect('hero', {
        type = 'apply_team_modifier', key = 'C02_M10_TONGSHOU', target_scope = 'team', duration = 4,
        payload = { damage_reduction = 0.10 },
    }, { unit = hero, team_targets = { hero, ally }, team_target_ids = { 'hero', 'ally' }, now = 0 })
    truthy(hero:find_buff(9010) == nil, 'team benefit excludes its source even when upstream selection includes it')
    truthy(ally:find_buff(9010) ~= nil, 'team benefit reaches ally')
    truthy(enemy:find_buff(9010) == nil, 'team benefit excludes enemy')
    near(ally.attrs['受伤减免'], 10, 0.00001, 'team contribution applies to ally')
    near(hero.attrs['受伤减免'], 15, 0.00001, 'team contribution does not alter the source self guard')
    adapter:apply_effect('ally', {
        type = 'apply_modifier', key = 'C02_M09_BUDONG_GUARD', target_scope = 'self', duration = 2,
        payload = { damage_reduction = 0.15 },
    }, { unit = ally, now = 0 })
    near(ally.attrs['受伤减免'], 23.5, 0.00001, 'personal and team reductions compose multiplicatively')
    adapter:apply_effect('ally', {
        type = 'apply_modifier', key = 'C02_TEST_OTHER_GUARD', target_scope = 'self', duration = 2,
        payload = { damage_reduction = 0.75 },
    }, { unit = ally, now = 0 })
    near(ally.attrs['受伤减免'], 75, 0.00001, 'combined reductions respect the 75 percent cap')
end

print('PASS: ' .. tests .. ' bridge targeting assertions')
