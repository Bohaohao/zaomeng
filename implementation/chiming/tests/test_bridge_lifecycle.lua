package.path = 'implementation/profession_common/lua/?.lua;implementation/chiming/lua/?.lua;' .. package.path

local Ledger = require 'chiming_y3_control_ledger'
local Adapter = require 'chiming_y3_adapter'
local Controller = require 'chiming_y3_controller'
local Core = require 'chiming_core'
local Skills = require 'chiming_skills'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local scheduled, loops, game_time = {}, {}, 0
_G.y3 = {
    game = { current_game_run_time = function() return game_time end },
    timer = {
        wait = function(_, callback) local timer = { callback = callback }; function timer:remove() self.removed = true end; scheduled[#scheduled + 1] = timer; return timer end,
        loop = function(_, callback) local timer = { callback = callback }; function timer:remove() self.removed = true end; loops[#loops + 1] = timer; return timer end,
    },
    const = { UnitEnumState = { ['无敌'] = 1, ['禁止移动'] = 2 } },
    shape = { create_circular_shape = function() return {} end, create_rectangle_shape = function() return {} end, create_sector_shape = function() return {} end },
    point = { get_point_offset_vector = function(point) return point end },
    selector = { create = function()
        local selector = {}
        function selector:in_shape() return self end; function selector:in_range() return self end
        function selector:is_enemy() return self end; function selector:is_ally() return self end
        function selector:not_in_state() return self end; function selector:without_tag() return self end
        function selector:pick() return {} end
        return selector
    end },
}

do
    local target = { id = 'root-target', exists = true, added = 0, removed = 0 }
    function target:get_id() return self.id end
    function target:is_exist() return self.exists end
    function target:add_state() self.added = self.added + 1 end
    function target:remove_state() self.removed = self.removed + 1 end
    local timers = {}
    local ledger = Ledger.new()
    local function wait(_, callback)
        local timer = { callback = callback }
        function timer:remove() self.removed = true end
        timers[#timers + 1] = timer
        return timer
    end
    ledger:acquire({ target = target, target_id = target.id, control_key = 'root', duration = 1,
        source_actor_id = 'first', lifecycle_id = 1, cast_id = 1, schedule = wait })
    ledger:acquire({ target = target, target_id = target.id, control_key = 'root', duration = 2,
        source_actor_id = 'second', lifecycle_id = 1, cast_id = 2, schedule = wait })
    equal(target.added, 1, 'two roots add the state once')
    timers[1].callback()
    equal(target.removed, 0, 'first root expiry retains the second root')
    equal(ledger:release_by_source('second', 1), 1, 'source cleanup releases the later root')
    equal(target.removed, 1, 'last source lease restores movement exactly once')
end

local function make_unit(id)
    local unit = {
        id = id, exists = true, level = 8, hp = 100, attrs = { ['最大生命'] = 100, ['生命'] = 100 },
        events = {}, damage_calls = 0, buffs = {}, states = {},
    }
    function unit:get_id() return self.id end
    function unit:is_exist() return self.exists end
    function unit:is_alive() return self.exists end
    function unit:get_level() return self.level end
    function unit:get_hp() return self.hp end
    function unit:set_hp(value) self.hp = value end
    function unit:get_attr(name) return self.attrs[name] or 0 end
    function unit:set_attr(name, value) self.attrs[name] = value end
    function unit:add_attr(name, value) self.attrs[name] = (self.attrs[name] or 0) + value end
    function unit:add_hp(value) self.hp = self.hp + value end
    function unit:get_owner() return 'ally' end
    function unit:get_point() return {} end
    function unit:get_facing() return 0 end
    function unit:find_ability() return nil end
    function unit:find_buff(key) return self.buffs[key] end
    function unit:add_buff(data)
        local buff = { key = data.key }
        function buff:set_time() end
        function buff:set_shield() end
        function buff:remove() unit.buffs[self.key] = nil; self.removed = true end
        unit.buffs[data.key] = buff
        return buff
    end
    function unit:add_state(state) self.states[state] = (self.states[state] or 0) + 1 end
    function unit:remove_state(state) self.states[state] = math.max(0, (self.states[state] or 0) - 1) end
    function unit:damage() self.damage_calls = self.damage_calls + 1 end
    function unit:event(name, callback)
        local trigger = { callback = callback, name = name }
        function trigger:remove() self.removed = true end
        unit.events[name] = unit.events[name] or {}
        unit.events[name][#unit.events[name] + 1] = trigger
        return trigger
    end
    return unit
end

do
    local source, target = make_unit('source'), make_unit('target')
    local adapter = Adapter.new { unit_by_actor = function(actor) return actor == 'source' and source or target end }
    local lifecycle_current = true
    adapter:set_lifecycle_resolver(function(_, lifecycle) return lifecycle_current and lifecycle == 1 end)
    adapter:schedule_damage('source', { type = 'delayed_damage', coefficient = 1, target_scope = 'explicit', target_id = 'target', target = target }, { lifecycle_id = 1 })
    local timer = scheduled[#scheduled]
    lifecycle_current = false
    adapter:cancel_actor_timers('source', 1)
    truthy(timer.removed, 'actor cancellation removes pending delayed damage')
    timer.callback()
    equal(source.damage_calls, 0, 'stale delayed callback cannot damage after lifecycle invalidation')
end

do
    local old_unit, new_unit = make_unit('same'), make_unit('same')
    local controller = Controller.new {}
    local state = controller:register('same', old_unit, { ability_levels = { C03_A03 = 1 }, now = 0 })
    truthy(state ~= nil, 'controller registers an actor')
    local old_lifecycle = controller.registrations.same.lifecycle_id
    controller.adapter:schedule_damage('same', {
        type = 'delayed_damage', coefficient = 1, target_scope = 'explicit', target_id = 'same', target = old_unit,
    }, { lifecycle_id = old_lifecycle })
    local death_timer = scheduled[#scheduled]
    local old_death = old_unit.events['单位-死亡'][1]
    old_death.callback(nil, {})
    truthy(death_timer.removed, 'death invalidates and cancels old delayed work')
    truthy(controller.registrations.same.lifecycle_id ~= old_lifecycle, 'death rotates lifecycle identity')
    local after_death_lifecycle = controller.registrations.same.lifecycle_id

    controller.adapter:schedule_damage('same', {
        type = 'delayed_damage', coefficient = 1, target_scope = 'explicit', target_id = 'same', target = old_unit,
    }, { lifecycle_id = after_death_lifecycle })
    local challenge_timer = scheduled[#scheduled]
    local cleared = controller:clear('same', 'challenge-failure')
    truthy(cleared, 'challenge failure invalidates an active lifecycle')
    truthy(challenge_timer.removed, 'challenge failure cancels pending pulses')
    local cross_layer_lifecycle = controller.registrations.same.lifecycle_id
    local crossed = controller:clear('same', 'cross-layer')
    truthy(crossed and controller.registrations.same.lifecycle_id ~= cross_layer_lifecycle, 'cross-layer rotates the lifecycle again')

    local old_timer = controller.registrations.same.timer
    local old_triggers = {}
    for _, triggers in pairs(old_unit.events) do for _, trigger in ipairs(triggers) do old_triggers[#old_triggers + 1] = trigger end end
    local removed = controller:remove('same')
    truthy(removed and old_timer.removed, 'remove stops the runtime loop')
    for _, trigger in ipairs(old_triggers) do truthy(trigger.removed, 'remove unregisters every unit trigger') end

    controller:register('same', new_unit, { ability_levels = { C03_A03 = 1 }, now = 0 })
    local new_state = controller.runtime:get_state('same')
    Core.set_seals(new_state, 3, 'earned')
    old_death.callback(nil, {})
    equal(new_state.seals, 3, 'old unit callback is inert after same-ID re-registration')
    local stale = controller:confirm_skill_hit('same', 1, { lifecycle_id = old_lifecycle, hit_events = {} })
    truthy(not stale.ok and stale.error == 'stale-lifecycle', 'old hit confirmation is rejected before touching new state')
    controller:remove('same')
end

do
    local state = Core.new {
        level = 60, ultimate_tier = 1,
        ability_levels = { C03_A03 = 1, C03_A04 = 5, C03_A07 = 5 },
    }
    state.lifecycle_id = 1
    Core.set_seals(state, 1, 'earned')
    local a04 = Skills.use(state, 'C03_A04', 5, 0, { actor_id = 'hero', lifecycle_id = 1, unit_id = 'hero' })
    Core.set_seals(state, 2, 'earned')
    local a07 = Skills.use(state, 'C03_A07', 5, 0, { actor_id = 'hero', lifecycle_id = 1, unit_id = 'hero', self_purge_success = false })
    truthy(a04.ok and a07.ok, 'A04 and A07 can hold independent pending protection windows')
    local a07_result = Skills.on_damage_taken(state, 0.2, {
        lifecycle_id = 1, unit_id = 'hero',
        protection_qualification = { effective_protection = true, cast_id = a07.cast_id, effect_key = 'C03_M07_FANZHAO_SHIELD',
            target_id = 'hero', lifecycle_id = 1, absorbed = 5 },
    })
    truthy(a07_result.ok, 'M07 settles only A07')
    local a04_result = Skills.on_damage_taken(state, 0.3, {
        lifecycle_id = 1, unit_id = 'hero',
        protection_qualification = { effective_protection = true, cast_id = a04.cast_id, effect_key = 'C03_M03_CHENGXIN_SHIELD',
            target_id = 'hero', lifecycle_id = 1, reduced = 5 },
    })
    truthy(a04_result.ok, 'M03 settles only A04 after A07 has already settled')
end

print('PASS: ' .. tests .. ' bridge lifecycle assertions')
