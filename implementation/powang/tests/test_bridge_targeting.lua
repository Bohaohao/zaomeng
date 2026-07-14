package.path = 'implementation/profession_common/lua/?.lua;implementation/powang/lua/?.lua;' .. package.path

local Effects = require 'powang_effects'
local TargetContract = require 'powang_target_contract'

local tests = 0

local function truthy(value, message)
    tests = tests + 1
    if not value then
        error(message or 'expected truthy value')
    end
end

local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then
        error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    end
end

local function near(actual, expected, epsilon, message)
    tests = tests + 1
    if math.abs(actual - expected) > epsilon then
        error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    end
end

local timers = {}

local function make_unit(id, owner)
    local unit = {
        id = id,
        owner = owner or 'enemy',
        exists = true,
        attrs = { ['最大生命'] = 100, ['生命'] = 100 },
        buffs = {},
    }
    function unit:get_id() return self.id end
    function unit:is_exist() return self.exists end
    function unit:get_owner() return self.owner end
    function unit:get_attr(name) return self.attrs[name] or 0 end
    function unit:add_attr(name, amount)
        self.attrs[name] = (self.attrs[name] or 0) + amount
    end
    function unit:add_hp(amount)
        self.attrs['生命'] = self.attrs['生命'] + amount
    end
    function unit:find_buff(key) return self.buffs[key] end
    function unit:add_buff(data)
        local buff = {
            key = data.key,
            time = data.time,
            data = data.data,
        }
        function buff:set_time(time) self.time = time end
        function buff:set_shield(value) self.shield = value end
        function buff:remove() unit.buffs[self.key] = nil end
        unit.buffs[data.key] = buff
        return buff
    end
    return unit
end

_G.y3 = {
    timer = {
        wait = function(delay, callback, description)
            local timer = { delay = delay, callback = callback, description = description }
            function timer:remove() self.removed = true end
            timers[#timers + 1] = timer
            return timer
        end,
    },
    game = { current_game_run_time = function() return 0 end },
    const = { UnitEnumState = { ['无敌'] = 1, ['禁止移动'] = 2 } },
}

package.loaded.powang_y3_adapter = nil
local Adapter = require 'powang_y3_adapter'

local hero = make_unit(1001, 'ally')
local enemy_one = make_unit(2001, 'enemy')
local enemy_two = make_unit(2002, 'enemy')
local ally = make_unit(1002, 'ally')
local units = { player = hero }
local adapter = Adapter.new({
    unit_by_actor = function(actor_id) return units[actor_id] end,
    modifier_ids = {
        C01_M09_TAXU_WIND = 9009,
        C01_M10_JINTUI_GUARD = 9010,
        C01_M07_SHOUYI_GUARD = 9007,
        C01_M08_POXI = 9008,
        C01_M11_MINGSHI = 9011,
    },
})

local function build_context(selected, team)
    return TargetContract.populate_context({}, hero, 'player', selected or {}, team or {})
end

local function dispatch_effect(engine, command, context)
    local handled = Effects.execute(engine, 'player', command, context, 0)
    truthy(handled, 'effect command handled')
    adapter:apply_effect('player', command, context)
end

do
    local engine = Effects.new()
    local context = build_context({ enemy_one })
    dispatch_effect(engine, {
        type = 'apply_modifier',
        key = 'C01_M09_TAXU_WIND',
        target_scope = 'self',
        duration = 3,
        payload = { move_speed = 0.15, attack_speed = 0.12 },
    }, context)
    truthy(hero:find_buff(9009) ~= nil, 'self movement buff applies to hero')
    truthy(enemy_one:find_buff(9009) == nil, 'self movement buff never applies to selected enemy')
end

do
    local engine = Effects.new()
    local context = build_context({ enemy_one })
    adapter:heal_and_guard('player', {
        heal_max_hp = 0.1,
        damage_reduction = 0.15,
        duration = 2,
    }, context)
    truthy(hero:find_buff(9007) ~= nil, 'shouyi guard applies to hero')
    truthy(enemy_one:find_buff(9007) == nil, 'shouyi guard never applies to selected enemy')
    truthy(engine ~= nil, 'bridge test engine remains isolated')
end

do
    local engine = Effects.new()
    local context = build_context({ enemy_one, enemy_two })
    local apply = {
        type = 'apply_modifier',
        key = 'C01_M08_POXI',
        target_scope = 'explicit',
        target_id = enemy_one:get_id(),
        duration = 6,
    }
    dispatch_effect(engine, apply, context)
    equal(#apply.resolved_targets, 1, 'poxi resolves exactly one explicit target')
    truthy(apply.resolved_targets[1].ref == enemy_one, 'poxi resolves the bound target reference')
    truthy(enemy_one:find_buff(9008) ~= nil, 'poxi applies to explicit primary target')
    truthy(enemy_two:find_buff(9008) == nil, 'poxi does not fan out to selected targets')

    local remove = {
        type = 'remove_modifier',
        key = 'C01_M08_POXI',
        target_scope = 'explicit',
        target_id = enemy_one:get_id(),
    }
    dispatch_effect(engine, remove, context)
    truthy(enemy_one:find_buff(9008) == nil, 'poxi cleanup removes only bound target')
    truthy(enemy_two:find_buff(9008) == nil, 'poxi cleanup leaves unrelated target untouched')
end

do
    local engine = Effects.new()
    local context = build_context({ enemy_one }, { hero, ally })
    dispatch_effect(engine, {
        type = 'apply_team_modifier',
        key = 'C01_M11_MINGSHI',
        target_scope = 'team',
        duration = 4,
        payload = { target_break_bonus = 0.2 },
    }, context)
    truthy(hero:find_buff(9011) == nil, 'team buff excludes caster under the shared teammate contract')
    truthy(ally:find_buff(9011) ~= nil, 'team buff applies to ally')
    truthy(enemy_one:find_buff(9011) == nil, 'team buff never applies to selected enemy')
end

do
    local mitigation_hero = make_unit(3001, 'ally')
    local mitigation_adapter = Adapter.new({
        unit_by_actor = function(actor_id)
            return actor_id == 'mitigation' and mitigation_hero or nil
        end,
    })
    local context = TargetContract.populate_context({}, mitigation_hero, 'mitigation', {}, {})
    local function apply(key, payload)
        mitigation_adapter:apply_effect('mitigation', {
            type = 'apply_modifier',
            key = key,
            target_scope = 'self',
            duration = 6,
            payload = payload,
        }, context)
    end
    local function remove(key)
        mitigation_adapter:apply_effect('mitigation', {
            type = 'remove_modifier',
            key = key,
            target_scope = 'self',
        }, context)
    end

    apply('C01_M04_HUIFENG_GUARD', { damage_reduction = 0.35 })
    apply('C01_M07_SHOUYI_GUARD', { damage_reduction = 0.08 })
    apply('C01_M10_JINTUI_GUARD', { damage_reduction = 0.15 })
    near(mitigation_hero:get_attr('受伤减免'), 49.17, 0.00001, 'categories multiply after each category keeps its highest reduction')

    apply('C01_M03_TAXU_SWIFT', {
        damage_reduction = 0.60,
        damage_reduction_category = 'guard',
    })
    near(mitigation_hero:get_attr('受伤减免'), 68.72, 0.00001, 'same category keeps only the higher guard reduction')

    apply('C01_M09_TAXU_WIND', {
        damage_reduction = 0.90,
        damage_reduction_category = 'external',
    })
    near(mitigation_hero:get_attr('受伤减免'), 70, 0.00001, 'combined mitigation respects the Powang cap')

    remove('C01_M09_TAXU_WIND')
    near(mitigation_hero:get_attr('受伤减免'), 68.72, 0.00001, 'removing the capped source recomputes the fallback total')
    remove('C01_M03_TAXU_SWIFT')
    remove('C01_M04_HUIFENG_GUARD')
    remove('C01_M07_SHOUYI_GUARD')
    remove('C01_M10_JINTUI_GUARD')
    near(mitigation_hero:get_attr('受伤减免'), 0, 0.00001, 'all mitigation removals restore the base attribute')
end

_G.y3 = nil
print('PASS: ' .. tostring(tests) .. ' bridge targeting assertions')
