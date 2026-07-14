package.path = 'implementation/profession_common/lua/?.lua;implementation/powang/lua/?.lua;' .. package.path

local ControlLedger = require 'powang_y3_control_ledger'
local Core = require 'powang_core'
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

do
    local scheduled = {}
    local target = { id = 3001, exists = true, add_count = 0, remove_count = 0 }
    function target:get_id() return self.id end
    function target:is_exist() return self.exists end
    function target:add_state() self.add_count = self.add_count + 1 end
    function target:remove_state() self.remove_count = self.remove_count + 1 end

    local ledger = ControlLedger.new()
    local function schedule(_, callback)
        local timer = { callback = callback }
        function timer:remove() self.removed = true end
        scheduled[#scheduled + 1] = timer
        return timer
    end
    ledger:acquire(target, 'root', 1, { schedule = schedule })
    ledger:acquire(target, 'root', 2, { schedule = schedule })
    equal(target.add_count, 1, 'overlapping root adds state once')
    equal(ledger:count(3001, 'root'), 2, 'two root leases tracked')
    scheduled[1].callback()
    equal(target.remove_count, 0, 'first root expiry keeps later root active')
    equal(ledger:count(3001, 'root'), 1, 'one root lease remains')
    scheduled[2].callback()
    equal(target.remove_count, 1, 'last root expiry removes state once')
    equal(ledger:count(3001, 'root'), 0, 'all root leases cleared')

    ledger:acquire(target, 'root', 3, { schedule = schedule })
    target.exists = false
    truthy(ledger:reap(3001), 'destroyed target reaped')
    equal(ledger:count(3001, 'root'), 0, 'destroyed target does not retain control records')
end

local event_time = 0
local loop_timers = {}
local wait_timers = {}
_G.y3 = {
    game = { current_game_run_time = function() return event_time end },
    timer = {
        loop = function(_, callback)
            local timer = { callback = callback }
            function timer:remove() self.removed = true end
            loop_timers[#loop_timers + 1] = timer
            return timer
        end,
        wait = function(_, callback)
            local timer = { callback = callback }
            function timer:remove() self.removed = true end
            wait_timers[#wait_timers + 1] = timer
            return timer
        end,
    },
    const = { UnitEnumState = { ['禁止移动'] = 2 } },
}

package.loaded.powang_y3_adapter = nil
package.loaded.powang_y3_controller = nil
local Adapter = require 'powang_y3_adapter'
local Controller = require 'powang_y3_controller'

local function make_unit(id)
    local unit = { id = id, exists = true, events = {} }
    function unit:get_id() return self.id end
    function unit:is_exist() return self.exists end
    function unit:get_level() return 1 end
    function unit:get_hp() return 620 end
    function unit:event(name, callback)
        local trigger = { name = name, callback = callback }
        function trigger:remove() self.removed = true end
        self.events[name] = trigger
        return trigger
    end
    return unit
end

local function make_effect_unit(id)
    local unit = {
        id = id,
        exists = true,
        attrs = { ['最大生命'] = 100, ['生命'] = 100 },
        buffs = {},
    }
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

local function fake_adapter()
    local adapter = {}
    local names = {
        'sync_hero_stats', 'sync_ability_charge', 'deal_damage', 'apply_break', 'schedule_damage',
        'move_safely', 'apply_effect', 'change_cooldown', 'apply_control',
        'set_combo_floor', 'heal_and_guard', 'state_changed',
    }
    for _, name in ipairs(names) do
        adapter[name] = function() end
    end
    function adapter:set_lifecycle_resolver(resolver)
        self.lifecycle_resolver = resolver
    end
    function adapter:cancel_actor_timers(actor, lifecycle_id)
        self.cancelled_actor = actor
        self.cancelled_lifecycle_id = lifecycle_id
    end
    return adapter
end

do
    local source_one = { id = 4101, exists = true }
    local source_two = { id = 4102, exists = true }
    local target = { id = 4103, exists = true, add_count = 0, remove_count = 0 }
    for _, unit in ipairs({ source_one, source_two, target }) do
        function unit:get_id() return self.id end
        function unit:is_exist() return self.exists end
    end
    function target:add_state() self.add_count = self.add_count + 1 end
    function target:remove_state() self.remove_count = self.remove_count + 1 end

    local units = { one = source_one, two = source_two }
    local adapter = Adapter.new({ unit_by_actor = function(actor_id) return units[actor_id] end })
    local command = {
        type = 'control',
        normal_duration = 1,
        elite_duration = 0.5,
    }
    adapter:apply_control('one', command, { targets = { target }, target_rank = 'normal' })
    adapter:apply_control('two', command, { targets = { target }, target_rank = 'normal' })
    equal(target.add_count, 1, 'adapter root uses one state for overlapping casts')
    wait_timers[1].callback()
    equal(target.remove_count, 0, 'adapter keeps root after first overlapping cast ends')
    wait_timers[2].callback()
    equal(target.remove_count, 1, 'adapter removes root after final overlapping cast ends')
end

do
    local source = { id = 4151, exists = true }
    local normal = { id = 4152, exists = true, add_count = 0, remove_count = 0 }
    local boss = { id = 4153, exists = true, add_count = 0, remove_count = 0 }
    local unknown = { id = 4154, exists = true, add_count = 0, remove_count = 0 }
    for _, unit in ipairs({ source, normal, boss, unknown }) do
        function unit:get_id() return self.id end
        function unit:is_exist() return self.exists end
    end
    for _, unit in ipairs({ normal, boss, unknown }) do
        function unit:add_state() self.add_count = self.add_count + 1 end
        function unit:remove_state() self.remove_count = self.remove_count + 1 end
    end
    local breaks = {}
    local adapter = Adapter.new({
        unit_by_actor = function() return source end,
        apply_break = function(_, target)
            breaks[#breaks + 1] = target
        end,
    })
    local context = TargetContract.populate_context({}, source, 'actor', { normal, boss, unknown }, {})
    context.target_meta_by_id = {
        [normal.id] = { rank = 'normal' },
        [boss.id] = { rank = 'boss' },
    }
    local command = {
        type = 'control',
        target_scope = 'selected',
        requires_target_rank = true,
        normal_duration = 1,
        elite_duration = 0.5,
        boss_converts_to_break = true,
        boss_break_value = 0.5,
        target_meta_by_id = context.target_meta_by_id,
    }
    local timer_start = #wait_timers
    adapter:apply_control('actor', command, context)
    equal(normal.add_count, 1, 'a08 roots a normal target')
    equal(boss.add_count, 0, 'a08 never roots a boss target')
    equal(#breaks, 1, 'a08 converts each boss target into one break event')
    truthy(breaks[1] == boss, 'a08 break conversion addresses the boss target itself')
    equal(unknown.add_count, 0, 'a08 skips a target whose rank was not resolved')
    wait_timers[timer_start + 1].callback()
    equal(normal.remove_count, 1, 'a08 normal root expires through its own lease')
end

do
    local unit = make_effect_unit('initial-sync')
    local adapter = Adapter.new({ unit_by_actor = function() return nil end })
    local stats = Core.hero_stats(1)
    adapter:sync_hero_stats('actor', stats, { unit = unit, current_hp = 77 })
    equal(unit.attrs['最大生命'], 620, 'register context supplies the initial hero unit before external mapping is ready')
    equal(unit.attrs['生命'], 77, 'initial hero sync preserves the supplied current health')
end

do
    local unit = make_effect_unit('lifecycle-effect')
    local current_lifecycle = 1
    local adapter = Adapter.new({ unit_by_actor = function() return unit end })
    adapter:set_lifecycle_resolver(function(_, lifecycle_id)
        return lifecycle_id == current_lifecycle
    end)
    local timer_start = #wait_timers
    adapter:apply_effect('actor', {
        type = 'apply_modifier',
        key = 'C01_M10_JINTUI_GUARD',
        target_scope = 'self',
        duration = 2,
        payload = { damage_reduction = 0.15 },
    }, { unit = unit, lifecycle_id = 1, now = 0 })
    local old_timer = wait_timers[timer_start + 1]
    adapter:cancel_actor_timers('actor', 1)
    truthy(old_timer.removed, 'removing an actor cancels its old effect cleanup timer')
    current_lifecycle = 2
    adapter:apply_effect('actor', {
        type = 'apply_modifier',
        key = 'C01_M10_JINTUI_GUARD',
        target_scope = 'self',
        duration = 2,
        payload = { damage_reduction = 0.10 },
    }, { unit = unit, lifecycle_id = 2, now = 0 })
    local new_timer = wait_timers[#wait_timers]
    old_timer.callback()
    near(unit.attrs['受伤减免'], 10, 0.00001, 'old lifecycle cleanup callback cannot remove a re-registered actor effect')
    new_timer.callback()
    near(unit.attrs['受伤减免'], 0, 0.00001, 'current lifecycle cleanup still removes its own effect')
end

do
    local source = make_effect_unit('delayed-source')
    local target = make_effect_unit('delayed-target')
    local damage_count = 0
    function source:damage()
        damage_count = damage_count + 1
    end
    local current_lifecycle = 1
    local adapter = Adapter.new({ unit_by_actor = function() return source end })
    adapter:set_lifecycle_resolver(function(_, lifecycle_id)
        return lifecycle_id == current_lifecycle
    end)
    local context = TargetContract.populate_context({}, source, 'actor', { target }, {})
    context.lifecycle_id = 1
    context.skill_key = 'C01_A06'
    local timer_start = #wait_timers
    adapter:schedule_damage('actor', { delay = 0.5, coefficient = 1 }, context)
    local old_timer = wait_timers[timer_start + 1]
    adapter:cancel_actor_timers('actor', 1)
    current_lifecycle = 2
    old_timer.callback()
    equal(damage_count, 0, 'old delayed damage cannot execute after actor lifecycle removal')

    context.lifecycle_id = 2
    adapter:schedule_damage('actor', { delay = 0.5, coefficient = 1 }, context)
    wait_timers[#wait_timers].callback()
    equal(damage_count, 1, 'current lifecycle delayed damage still executes')
end

do
    local source = make_effect_unit('mover-source')
    local current_lifecycle = 1
    local completed = 0
    function source:get_facing() return 0 end
    function source:mover_line(data)
        self.mover = data
    end
    local adapter = Adapter.new({
        unit_by_actor = function() return source end,
        on_move_finished = function()
            completed = completed + 1
        end,
    })
    adapter:set_lifecycle_resolver(function(_, lifecycle_id)
        return lifecycle_id == current_lifecycle
    end)
    adapter:move_safely('actor', {
        distance = 1,
        damage_reduction = 0.4,
        damage_reduction_category = 'mobility',
    }, { lifecycle_id = 1 })
    near(source.attrs['受伤减免'], 40, 0.00001, 'movement reduction enters the mitigation ledger')
    local old_mover = source.mover
    adapter:cancel_actor_timers('actor', 1)
    near(source.attrs['受伤减免'], 0, 0.00001, 'actor removal clears the pending movement reduction')
    current_lifecycle = 2
    old_mover.on_finish()
    equal(completed, 0, 'old movement completion callback is inert after lifecycle replacement')
    near(source.attrs['受伤减免'], 0, 0.00001, 'old movement callback cannot restore a cleared reduction')
end

do
    local source = { id = 4201, exists = true }
    local target = { id = 4202, exists = true, add_count = 0, remove_count = 0 }
    for _, unit in ipairs({ source, target }) do
        function unit:get_id() return self.id end
        function unit:is_exist() return self.exists end
    end
    function target:add_state() self.add_count = self.add_count + 1 end
    function target:remove_state() self.remove_count = self.remove_count + 1 end
    local current_lifecycle = 1
    local adapter = Adapter.new({ unit_by_actor = function() return source end })
    adapter:set_lifecycle_resolver(function(_, lifecycle_id)
        return lifecycle_id == current_lifecycle
    end)
    local context = TargetContract.populate_context({}, source, 'actor', { target }, {})
    context.lifecycle_id = 1
    context.target_meta_by_id = { [target.id] = { rank = 'normal' } }
    local command = {
        type = 'control',
        target_scope = 'selected',
        requires_target_rank = true,
        normal_duration = 1,
        elite_duration = 0.5,
        boss_converts_to_break = true,
        target_meta_by_id = context.target_meta_by_id,
    }
    local timer_start = #wait_timers
    adapter:apply_control('actor', command, context)
    local old_timer = wait_timers[timer_start + 1]
    equal(target.add_count, 1, 'lifecycle control applies the initial root')
    adapter:cancel_actor_timers('actor', 1)
    truthy(old_timer.removed, 'removing an actor cancels its old control lease timer')
    equal(target.remove_count, 1, 'removing an actor releases its own control lease')

    current_lifecycle = 2
    context.lifecycle_id = 2
    adapter:apply_control('actor', command, context)
    local new_timer = wait_timers[#wait_timers]
    equal(target.add_count, 2, 'new lifecycle applies a fresh control lease')
    old_timer.callback()
    equal(target.remove_count, 1, 'old control timer cannot release a new lifecycle root')
    new_timer.callback()
    equal(target.remove_count, 2, 'current control timer releases its own root')
end

do
    local controller = Controller.new({ adapter = fake_adapter(), targeting = {} })
    local loop_start = #loop_timers
    local first = make_unit(4001)
    controller:register('player', first, { now = 0 })
    local old_lifecycle = controller.registrations.player.lifecycle_id
    local old_normal_trigger = first.events['单位-造成伤害后']
    truthy(controller:remove('player'), 'controller removes registered actor')
    truthy(loop_timers[loop_start + 1].removed, 'controller removes actor timer')
    for _, trigger in pairs(first.events) do
        truthy(trigger.removed, 'controller removes every unit trigger')
    end

    local second = make_unit(4002)
    local state = controller:register('player', second, { now = 0 })
    old_normal_trigger.callback(nil, {
        is_normal_hit = true,
        damage = 10,
        target_unit = make_unit(4999),
    })
    equal(state.momentum, 0, 'old trigger stays inert after actor id re-registration')
    local missing = controller:confirm_skill_hit('player', 1, {})
    equal(missing.error, 'lifecycle-id-required', 'late hit confirmation requires an explicit lifecycle id')
    local stale = controller:confirm_skill_hit('player', 1, { lifecycle_id = old_lifecycle })
    equal(stale.error, 'stale-lifecycle', 'late hit confirmation rejects an old lifecycle')
end

do
    local qualification = false
    local controller = Controller.new({
        adapter = fake_adapter(),
        targeting = {},
        classify_guardable_damage = function()
            return { guardable_hit = qualification }
        end,
    })
    local hero = make_unit(4301)
    local source = make_unit(4302)
    local state = controller:register('guard', hero, {
        now = 0,
        ability_levels = { C01_A07 = 1 },
    })
    Core.apply_status(state, 'C01_M04_HUIFENG_GUARD', 0, 1, {
        counter_available = true,
        rank = 1,
        counter_coefficient = 1,
        counter_break_value = 1,
    })
    hero.events['单位-受到伤害后'].callback(nil, {
        damage = 10,
        source_unit = source,
        target_unit = hero,
    })
    truthy(Core.get_status(state, 'C01_M04_HUIFENG_GUARD', 0).payload.counter_available,
        'unqualified damage cannot trigger the Powang guard counter')

    qualification = true
    hero.events['单位-受到伤害后'].callback(nil, {
        damage = 10,
        source_unit = source,
        target_unit = hero,
    })
    truthy(not Core.get_status(state, 'C01_M04_HUIFENG_GUARD', 0).payload.counter_available,
        'classified guardable damage triggers exactly one guard counter')
end

_G.y3 = nil
print('PASS: ' .. tostring(tests) .. ' bridge lifecycle assertions')
