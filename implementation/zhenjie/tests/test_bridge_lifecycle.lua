package.path = 'implementation/profession_common/lua/?.lua;implementation/zhenjie/lua/?.lua;' .. package.path

local Ledger = require 'zhenjie_y3_control_ledger'
local Adapter = require 'zhenjie_y3_adapter'
local Controller = require 'zhenjie_y3_controller'
local Core = require 'zhenjie_core'

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

local scheduled, loops = {}, {}
local event_time = 0
_G.y3 = {
    game = { current_game_run_time = function() return event_time end },
    timer = {
        wait = function(_, callback) local timer = { callback = callback }; function timer:remove() self.removed = true end; scheduled[#scheduled + 1] = timer; return timer end,
        loop = function(_, callback) local timer = { callback = callback }; function timer:remove() self.removed = true end; loops[#loops + 1] = timer; return timer end,
    },
    const = { UnitEnumState = { ['无敌'] = 1, ['禁止移动'] = 2 } },
}

do
    local target = { id = 3001, exists = true, added = 0, removed = 0 }
    function target:get_id() return self.id end
    function target:is_exist() return self.exists end
    function target:add_state() self.added = self.added + 1 end
    function target:remove_state() self.removed = self.removed + 1 end
    local ledger = Ledger.new()
    local local_timers = {}
    local function wait(_, callback) local timer = { callback = callback }; function timer:remove() self.removed = true end; local_timers[#local_timers + 1] = timer; return timer end
    ledger:acquire(target, 'root', 1, { schedule = wait })
    ledger:acquire(target, 'root', 2, { schedule = wait })
    equal(target.added, 1, 'overlapping roots add once')
    equal(ledger:count(3001, 'root'), 2, 'two leases tracked')
    local_timers[1].callback()
    equal(target.removed, 0, 'first expiry keeps later root')
    local_timers[2].callback()
    equal(target.removed, 1, 'last expiry removes root')
    target.exists = false
    local dead_target = { id = 3002, is_exist = function() return false end }
    local dead_lease, dead_error = ledger:acquire({
        target = dead_target,
        target_id = 3002,
        control_key = 'root',
        duration = 1,
        schedule = wait,
    })
    equal(dead_lease, nil, 'destroyed target creates no lease')
    equal(dead_error, 'target-destroyed', 'destroyed target is rejected explicitly')
    equal(ledger:count(3002, 'root'), 0, 'destroyed target leaves no control record')
end

do
    local target = { id = 4001, exists = true, added = 0, removed = 0 }
    function target:get_id() return self.id end
    function target:is_exist() return self.exists end
    function target:add_state() self.added = self.added + 1 end
    function target:remove_state() self.removed = self.removed + 1 end
    local adapter = Adapter.new { unit_by_actor = function() return target end }
    local command = { type = 'control', normal_duration = 1, elite_duration = 1, boss_converts_to_break = true, boss_break_value = 0.5 }
    adapter:apply_control('one', command, { targets = { target }, target_rank = 'normal' })
    adapter:apply_control('two', command, { targets = { target }, target_rank = 'normal' })
    equal(target.added, 1, 'adapter shares overlapping root lease')
    scheduled[#scheduled - 1].callback()
    equal(target.removed, 0, 'adapter first lease expiry leaves root active')
    scheduled[#scheduled].callback()
    equal(target.removed, 1, 'adapter final lease expiry removes root')
end

local function make_unit(id)
    local unit = { id = id, exists = true, events = {}, hp = 100 }
    function unit:get_id() return self.id end
    function unit:is_exist() return self.exists end
    function unit:get_level() return 1 end
    function unit:get_hp() return self.hp end
    function unit:event(_, callback) local trigger = { callback = callback }; function trigger:remove() self.removed = true end; unit.events[#unit.events + 1] = trigger; return trigger end
    return unit
end

local function make_effect_unit(id)
    local unit = { id = id, exists = true, attrs = { ['最大生命'] = 100, ['生命'] = 100 }, buffs = {} }
    function unit:get_id() return self.id end
    function unit:is_exist() return self.exists end
    function unit:get_attr(name) return self.attrs[name] or 0 end
    function unit:set_attr(name, value) self.attrs[name] = value end
    function unit:add_attr(name, amount) self.attrs[name] = (self.attrs[name] or 0) + amount end
    function unit:set_hp(value) self.attrs['生命'] = value end
    function unit:find_buff(key) return self.buffs[key] end
    function unit:add_buff(data)
        local buff = { key = data.key, time = data.time }
        function buff:set_time(time) self.time = time end
        function buff:set_shield(value) self.shield = value end
        function buff:remove() unit.buffs[self.key] = nil end
        unit.buffs[data.key] = buff
        return buff
    end
    return unit
end

do
    local unit = make_effect_unit('initial-sync')
    local adapter = Adapter.new { unit_by_actor = function() return nil end }
    local stats = Core.hero_stats(1)
    adapter:sync_hero_stats('actor', stats, { unit = unit, current_hp = 77 })
    equal(unit.attrs['最大生命'], 720, 'register context supplies the initial hero unit before external mapping is ready')
    equal(unit.attrs['生命'], 77, 'initial hero sync preserves the supplied current health')
end

do
    local unit = make_effect_unit('lifecycle-effect')
    local current_lifecycle = 1
    local adapter = Adapter.new {
        unit_by_actor = function() return unit end,
        modifier_ids = { C02_M09_BUDONG_GUARD = 9009 },
    }
    adapter:set_lifecycle_resolver(function(_, lifecycle_id)
        return lifecycle_id == current_lifecycle
    end)
    local timer_start = #scheduled
    adapter:apply_effect('actor', {
        type = 'apply_modifier', key = 'C02_M09_BUDONG_GUARD', target_scope = 'self', duration = 2,
        payload = { damage_reduction = 0.15 },
    }, { unit = unit, lifecycle_id = 1, now = 0 })
    local old_timer = scheduled[timer_start + 1]
    adapter:cancel_actor_timers('actor', 1)
    truthy(old_timer.removed, 'removing an actor cancels its old effect cleanup timer')
    current_lifecycle = 2
    adapter:apply_effect('actor', {
        type = 'apply_modifier', key = 'C02_M09_BUDONG_GUARD', target_scope = 'self', duration = 2,
        payload = { damage_reduction = 0.10 },
    }, { unit = unit, lifecycle_id = 2, now = 0 })
    local new_timer = scheduled[#scheduled]
    old_timer.callback()
    near(unit.attrs['受伤减免'], 10, 0.00001, 'old lifecycle cleanup callback cannot remove a re-registered actor effect')
    new_timer.callback()
    near(unit.attrs['受伤减免'], 0, 0.00001, 'current lifecycle cleanup still removes its own effect')
end

do
    local calls = 0
    local adapter = {}
    local methods = require('zhenjie_adapter_contract').required_methods()
    for _, name in ipairs(methods) do adapter[name] = function() calls = calls + 1 end end
    local controller = Controller.new { adapter = adapter, targeting = { build_context = function() return {} end } }
    local old = make_unit('old')
    controller:register('actor', old, { ability_levels = { C02_A01 = 1 }, context = { unit = old } })
    local old_lifecycle = controller.registrations.actor.lifecycle_id
    local old_triggers = old.events
    truthy(controller:remove('actor'), 'controller removes registration')
    truthy(loops[#loops].removed, 'controller removes runtime loop')
    for _, trigger in ipairs(old_triggers) do truthy(trigger.removed, 'controller removes every unit trigger') end
    local fresh = make_unit('fresh')
    controller:register('actor', fresh, { ability_levels = { C02_A01 = 1 }, context = { unit = fresh } })
    local before = calls
    old_triggers[1].callback(nil, { damage = 10, source_unit = fresh, target_unit = old })
    equal(calls, before, 'old callback is inert after actor id reuse')
    local stale = controller:confirm_skill_hit('actor', 1, { lifecycle_id = old_lifecycle })
    truthy(not stale.ok, 'late hit confirmation from an old lifecycle is rejected')
    equal(stale.error, 'stale-lifecycle', 'late hit confirmation reports a lifecycle mismatch')
    equal(calls, before, 'late hit confirmation cannot mutate the re-registered actor')
end

print('PASS: ' .. tests .. ' bridge lifecycle assertions')
