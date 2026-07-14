package.path = 'implementation/profession_common/lua/?.lua;implementation/powang/lua/?.lua;' .. package.path

local Config = require 'powang_config'
local Core = require 'powang_core'
local Skills = require 'powang_skills'
local Effects = require 'powang_effects'
local Contract = require 'powang_adapter_contract'
local Runtime = require 'powang_runtime'

local tests = 0

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

local function truthy(value, message)
    tests = tests + 1
    if not value then
        error(message or 'expected truthy value')
    end
end

local function find(commands, event_type, tag)
    for _, command in ipairs(commands) do
        if command.type == event_type and (tag == nil or command.tag == tag) then
            return command
        end
    end
    return nil
end

local function count_keys(values)
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end

do
    equal(count_keys(Config.abilities), 8, 'active skill config count')
    equal(count_keys(Config.passives), 8, 'passive skill config count')
    equal(count_keys(Config.modifiers), 12, 'modifier config count')
    truthy(loadfile('implementation/powang/lua/powang_y3_adapter.lua') ~= nil, 'Y3 adapter syntax')
    truthy(loadfile('implementation/powang/lua/powang_y3_controller.lua') ~= nil, 'Y3 controller syntax')
    truthy(loadfile('implementation/powang/lua/powang_y3_targeting.lua') ~= nil, 'Y3 targeting syntax')
end

do
    local expected = {
        [1] = { 620, 48, 22, 16 },
        [20] = { 1912, 156, 58, 45 },
        [40] = { 3272, 270, 96, 75 },
        [60] = { 4632, 384, 134, 105 },
    }
    for level, values in pairs(expected) do
        local stats = Core.hero_stats(level)
        equal(stats.hp_max, values[1], 'hp breakpoint')
        equal(stats.attack_physical, values[2], 'attack breakpoint')
        equal(stats.defense_physical, values[3], 'physical defense breakpoint')
        equal(stats.defense_magic, values[4], 'magic defense breakpoint')
    end
    local stats = Core.hero_stats(1)
    near(stats.critical_chance, 0.05, 0.00001, 'base critical chance')
    near(stats.critical_damage, 1.5, 0.00001, 'base critical damage')
    near(stats.hit_rate, 1.0, 0.00001, 'base hit rate')
    near(stats.dodge_rate, 0.0, 0.00001, 'base dodge rate')
    near(stats.cooldown_reduction, 0.0, 0.00001, 'base cooldown reduction')
end

do
    local state = Core.new { level = 1, now = 0 }
    Core.set_health(state, state.stats.hp_max * 0.5)
    Core.set_level(state, 20)
    equal(state.level, 20, 'set level')
    equal(state.stats.hp_max, 1912, 'level recomputes stats')
    equal(state.current_hp, 956, 'level preserves health ratio')
end

do
    local state = Core.new { now = 0 }
    Core.normal_attack_hit(state, 0)
    Core.normal_attack_hit(state, 1)
    Core.normal_attack_hit(state, 2)
    equal(state.momentum, 15, 'normal combo momentum')
    equal(state.normal_attack_stage, 3, 'normal combo stage')
end

do
    local state = Core.new { now = 0 }
    state.ability_levels.C01_A04 = 5
    Core.initialize_ability_charges(state)
    local initial = Core.take_charge_updates(state, 0)
    equal(initial[1].current, 2, 'a04 initializes two charges')
    local ok, update = Core.consume_ability_charge(state, 'C01_A04', 5, 0)
    truthy(ok and update.current == 1, 'a04 first charge')
    ok, update = Core.consume_ability_charge(state, 'C01_A04', 5, 0)
    truthy(ok and update.current == 0, 'a04 second charge')
    ok = Core.consume_ability_charge(state, 'C01_A04', 5, 0)
    truthy(not ok, 'a04 empty charge gate')
    Core.tick(state, 10)
    local updates = Core.take_charge_updates(state, 10)
    equal(updates[1].current, 1, 'a04 first sequential recharge')
    Core.tick(state, 20)
    updates = Core.take_charge_updates(state, 20)
    equal(updates[1].current, 2, 'a04 second sequential recharge')
end

do
    local state = Core.new { now = 0 }
    Core.gain_momentum(state, 50, { now = 0, effective_hit = true })
    Core.tick(state, 3.9)
    equal(state.momentum, 50, 'momentum before decay delay')
    Core.tick(state, 5.0)
    equal(state.momentum, 38, 'momentum decay after one second')
end

do
    local state = Core.new { now = 0, passive_levels = { C01_P01 = 5 } }
    Core.gain_momentum(state, 50, { now = 0, effective_hit = true })
    Core.tick(state, 5.9)
    equal(state.momentum, 50, 'p01 rank5 extended delay')
    Core.tick(state, 7.0)
    equal(state.momentum, 38, 'p01 rank5 decay')
end

do
    local state = Core.new { now = 0, passive_levels = { C01_P01 = 5 } }
    Core.gain_momentum(state, 80, { now = 0, effective_hit = true })
    local token = Core.begin_spender(state, 'C01_A02', 0, {})
    truthy(token.dongming, '80 momentum should be dongming')
    equal(state.momentum, 50, 'a02 spend')
    Core.confirm_spender_hit(state, token.id, 0)
    truthy(state.casts[token.id] == nil, 'confirmed casts are released')
    equal(state.ultimate_gauge, 6, 'a02 ultimate gain')
    Core.gain_momentum(state, 10, { now = 0, effective_hit = true, generator_key = 'C01_A01' })
    equal(state.momentum, 67, 'p01 next generator bonus')
end

do
    local generator_contexts = {
        C01_A01 = { target_count = 2 },
        C01_A03 = { target_count = 1, hit_count = 3, same_target_all = true, target_rank = 'elite' },
        C01_A04 = { target_count = 1 },
        C01_A05 = { target_count = 3 },
    }
    for key, context in pairs(generator_contexts) do
        local state = Core.new { now = 0 }
        local result = Skills.use(state, key, 5, 0, context)
        truthy(result.ok, key .. ' generator smoke')
        truthy(find(result.commands, 'damage') ~= nil, key .. ' damage command')
    end

    local spender_contexts = {
        C01_A02 = { hit = true, target_id = 'target', target_rank = 'normal' },
        C01_A06 = { hit = true, target_id = 'target', target_rank = 'elite', target_health_ratio = 0.5 },
        C01_A07 = { hit = true, target_id = 'target', target_rank = 'normal', guard_triggered = true },
        C01_A08 = { hit = true, target_id = 'target', target_rank = 'boss', xianwang = true },
    }
    for key, context in pairs(spender_contexts) do
        local state = Core.new { now = 0 }
        Core.gain_momentum(state, 100, { now = 0, effective_hit = true })
        local result = Skills.use(state, key, 5, 0, context)
        truthy(result.ok, key .. ' spender smoke')
        truthy(find(result.commands, 'damage') ~= nil, key .. ' damage command')
    end
end

do
    local state = Core.new { now = 0 }
    local failed = Skills.use(state, 'C01_A02', 5, 0, { hit = true })
    truthy(not failed.ok and failed.error == 'insufficient-momentum', 'spender resource gate')
    failed = Skills.use(state, 'C01_A01', 6, 0, { target_count = 1 })
    truthy(not failed.ok and failed.error == 'invalid-rank', 'skill rank gate')
end

do
    local state = Core.new { now = 0 }
    Core.gain_momentum(state, 100, { now = 0, effective_hit = true })
    local committed = Skills.commit_spender(state, 'C01_A02', 5, 0, {})
    truthy(committed.ok and committed.cast_id ~= nil, 'spender asynchronous commit')
    equal(state.ultimate_gauge, 0, 'commit does not grant ultimate gauge')
    local confirmed = Skills.confirm_spender_hit(state, committed.cast_id, 0.2, { target_id = 'enemy' })
    truthy(confirmed.ok, 'spender asynchronous hit confirmation')
    equal(state.ultimate_gauge, 6, 'confirmed hit grants ultimate gauge')

    Core.gain_momentum(state, 100, { now = 1, effective_hit = true })
    committed = Skills.commit_spender(state, 'C01_A02', 5, 1, {})
    local missed = Skills.finish_spender_miss(state, committed.cast_id, 1.2, 'no-target')
    truthy(missed.ok and missed.missed, 'spender miss finalization')
    truthy(Core.get_cast(state, committed.cast_id) == nil, 'missed cast released')
end

do
    local state = Core.new {
        now = 0,
        passive_levels = { C01_P03 = 5 },
    }
    local result = Skills.use(state, 'C01_A04', 5, 0, { target_count = 1 })
    truthy(result.ok, 'a04 movement passive setup')
    Core.normal_attack_hit(state, 0.2)
    Core.normal_attack_hit(state, 0.8)
    Core.normal_attack_hit(state, 1.4)
    equal(state.momentum, 32, 'p03 rank5 first combo bonus')
end

do
    local state = Core.new { now = 0 }
    Core.gain_momentum(state, 79, { now = 0, effective_hit = true })
    local token = Core.begin_spender(state, 'C01_A02', 0, {})
    truthy(not token.dongming, '79 momentum must not be dongming')
end

do
    local state = Core.new { now = 0, ultimate_tier = 3 }
    state.ultimate_gauge = 100
    local result = Skills.activate_ultimate(state, 0)
    truthy(result.ok, 'ultimate activation')
    equal(state.momentum, 35, 'ultimate fixed momentum')
    Core.gain_momentum(state, 10, { now = 1, effective_hit = true, generator_key = 'C01_A01' })
    equal(state.momentum, 52, 'tier2 distinct generator and multiplier')
    local spender = Skills.use(state, 'C01_A06', 5, 1, { hit = true, target_id = 'boss', target_rank = 'boss', target_health_ratio = 1 })
    truthy(spender.ok, 'a06 during ultimate')
    local echo = find(spender.commands, 'ultimate_echo')
    truthy(echo ~= nil, 'tier3 echo after 50 spend')
    near(echo.coefficient, 0.8, 0.00001, 'tier3 echo coefficient field')
end

do
    for tier = 1, 3 do
        local state = Core.new { now = 0, ultimate_tier = tier }
        state.ultimate_gauge = 100
        local result = Skills.activate_ultimate(state, 0)
        truthy(result.ok, 'ultimate tier activation ' .. tostring(tier))
        near(state.true_realm.expires_at, Config.ultimate.duration[tier], 0.00001, 'ultimate tier duration')
    end
end

do
    local state = Core.new {
        now = 0,
        passive_levels = { C01_P05 = 5 },
    }
    Core.gain_momentum(state, 100, { now = 0, effective_hit = true })
    Core.set_health(state, state.stats.hp_max * 0.30)
    local token, events = Core.begin_spender(state, 'C01_A06', 0, { health_ratio = 0.30 })
    truthy(token ~= nil, 'p05 spender commit')
    local trigger = find(events, 'shouyi_trigger')
    truthy(trigger ~= nil, 'p05 trigger')
    near(trigger.heal_max_hp, 0.03, 0.00001, 'p05 emergency heal')
end

do
    local state = Core.new { now = 0 }
    local result = Skills.use(state, 'C01_A05', 5, 0, { target_count = 8, target_rank = 'normal' })
    truthy(result.ok, 'a05 use')
    equal(state.momentum, 18, 'a05 multi-target momentum cap')
    truthy(find(result.commands, 'apply_modifier_to_targets') ~= nil, 'a05 applies xianwang')
end

do
    local state = Core.new {
        now = 0,
        ability_levels = { C01_A05 = 5 },
        passive_levels = { C01_P06 = 5, C01_P02 = 5 },
    }
    Core.gain_momentum(state, 100, { now = 0, effective_hit = true })
    local first = Skills.use(state, 'C01_A02', 5, 0, { hit = true, target_id = 'boss', target_rank = 'boss' })
    truthy(first.ok and first.dongming, 'first dongming spender')
    Core.gain_momentum(state, 100, { now = 1, effective_hit = true })
    local second = Skills.use(state, 'C01_A06', 5, 1, {
        hit = true,
        target_id = 'boss',
        target_rank = 'boss',
        target_health_ratio = 0.20,
    })
    truthy(second.ok, 'second spender')
    truthy(find(second.commands, 'momentum_refund') ~= nil, 'poxi refund')
    truthy(find(second.commands, 'delayed_damage') ~= nil, 'a06 dongming second strike')
    truthy(find(second.commands, 'damage', 'xianwang-echo') == nil, 'xianwang echo requires xianwang context')
end

do
    local state = Core.new { now = 0 }
    Core.gain_momentum(state, 100, { now = 0, effective_hit = true })
    local result = Skills.use(state, 'C01_A07', 5, 0, {
        hit = true,
        guard_triggered = true,
        target_id = 'enemy',
        target_rank = 'normal',
    })
    truthy(result.ok, 'a07 use')
    truthy(find(result.commands, 'damage', 'counter') ~= nil, 'a07 counter')
    local shield = find(result.commands, 'apply_modifier')
    truthy(shield ~= nil, 'a07 modifier commands')
end

do
    local state = Core.new { now = 0, ability_levels = { C01_A07 = 5 } }
    Core.gain_momentum(state, 25, { now = 0, effective_hit = true })
    local result = Skills.use(state, 'C01_A07', 5, 0, {
        hit = true,
        target_id = 'enemy',
        target_rank = 'normal',
    })
    truthy(result.ok and find(result.commands, 'damage', 'counter') == nil, 'normal a07 waits for damage event')
    local rejected = Skills.trigger_guard_counter(state, 0.2, { target_id = 'enemy' })
    truthy(not rejected.ok and rejected.error == 'guard-hit-not-eligible', 'a07 ignores unqualified damage events')
    local counter = Skills.trigger_guard_counter(state, 0.2, {
        target_id = 'enemy',
        guardable_hit = true,
    })
    truthy(counter.ok and find(counter.commands, 'damage', 'counter') ~= nil, 'a07 damage event counter')
    truthy(find(counter.commands, 'momentum_refund') ~= nil, 'a07 actual counter refund')
    local repeated = Skills.trigger_guard_counter(state, 0.3, { target_id = 'enemy' })
    truthy(not repeated.ok, 'a07 counter triggers once per guard')
end

do
    local state = Core.new {
        now = 0,
        ability_levels = { C01_A05 = 5 },
    }
    Core.gain_momentum(state, 100, { now = 0, effective_hit = true })
    local first = Skills.use(state, 'C01_A02', 5, 0, {
        hit = true,
        xianwang = true,
        target_id = 'boss',
        target_rank = 'boss',
    })
    truthy(find(first.commands, 'damage', 'xianwang-echo') ~= nil, 'first spender triggers xianwang echo')
    Core.gain_momentum(state, 100, { now = 1, effective_hit = true })
    local second = Skills.use(state, 'C01_A02', 5, 1, {
        hit = true,
        xianwang = true,
        target_id = 'boss',
        target_rank = 'boss',
    })
    truthy(find(second.commands, 'damage', 'xianwang-echo') == nil, 'xianwang echo target cooldown')
end

do
    local engine = Effects.new()
    Effects.apply(engine, 'boss', 'C01_M02_XIANWANG', 'p1', 0, 5, {
        defense_reduction = 0.11,
        break_taken = 0.08,
    })
    Effects.apply(engine, 'boss', 'C01_M02_XIANWANG', 'p2', 0, 8, {
        defense_reduction = 0.06,
        break_taken = 0.08,
    })
    local active = Effects.get(engine, 'boss', 'C01_M02_XIANWANG', 4)
    near(active.payload.defense_reduction, 0.11, 0.00001, 'xianwang highest value')
    equal(active.source_count, 2, 'xianwang source count')
    active = Effects.get(engine, 'boss', 'C01_M02_XIANWANG', 6)
    near(active.payload.defense_reduction, 0.06, 0.00001, 'xianwang weaker source remains after strong expires')
    equal(active.source_count, 1, 'xianwang expired source removed')
end

do
    local engine = Effects.new()
    Effects.apply(engine, 'boss', 'C01_M02_XIANWANG', 'p1', 0, 5, { defense_reduction = 0.11 })
    Effects.apply(engine, 'boss', 'C01_M02_XIANWANG', 'p2', 0, 8, { defense_reduction = 0.06 })
    truthy(Effects.refresh_all(engine, 'boss', 'C01_M02_XIANWANG', 4), 'shared xianwang refresh')
    local p1 = Effects.get(engine, 'boss', 'C01_M02_XIANWANG', 4, 'p1')
    local p2 = Effects.get(engine, 'boss', 'C01_M02_XIANWANG', 4, 'p2')
    equal(p1.expires_at, 9, 'shared refresh keeps strong source duration')
    equal(p2.expires_at, 12, 'shared refresh keeps weak source duration')
    truthy(Effects.extend_shared_once(engine, 'boss', 'C01_M02_XIANWANG', 'p3', 4, 2, 'cast-1'), 'shared extension')
    truthy(not Effects.extend_shared_once(engine, 'boss', 'C01_M02_XIANWANG', 'p3', 4, 2, 'cast-1'), 'shared extension once per cast')
    equal(Effects.get(engine, 'boss', 'C01_M02_XIANWANG', 4, 'p1').expires_at, 11, 'shared extension applies to all sources')
end

do
    local engine = Effects.new()
    Effects.apply(engine, 'hero', 'C01_M05_HUIFENG_SHIELD', 'p1', 0, 3, { value = 100 })
    Effects.apply(engine, 'hero', 'C01_M05_HUIFENG_SHIELD', 'p1', 1, 3, { value = 120 })
    local shield = Effects.get(engine, 'hero', 'C01_M05_HUIFENG_SHIELD', 1)
    equal(shield.source_count, 1, 'same source shield refreshes')
    local source = Effects.get(engine, 'hero', 'C01_M05_HUIFENG_SHIELD', 1, 'p1')
    equal(source.payload.value, 120, 'shield refresh replaces source value')
end

do
    local engine = Effects.new()
    Effects.apply(engine, 'boss', 'C01_M08_POXI', 'p1', 0, 6, { skill_key = 'C01_A02' })
    Effects.apply(engine, 'boss', 'C01_M08_POXI', 'p2', 0, 6, { skill_key = 'C01_A06' })
    local p1 = Effects.get(engine, 'boss', 'C01_M08_POXI', 1, 'p1')
    local p2 = Effects.get(engine, 'boss', 'C01_M08_POXI', 1, 'p2')
    equal(p1.payload.skill_key, 'C01_A02', 'poxi source one')
    equal(p2.payload.skill_key, 'C01_A06', 'poxi source two')
    Effects.clear_source(engine, 'p1')
    truthy(Effects.get(engine, 'boss', 'C01_M08_POXI', 1, 'p1') == nil, 'poxi source clear')
    truthy(Effects.get(engine, 'boss', 'C01_M08_POXI', 1, 'p2') ~= nil, 'other poxi source remains')
end

do
    local engine = Effects.new()
    local unit_ref = {}
    Effects.execute(engine, 'p1', {
        type = 'apply_modifier_to_targets',
        key = 'C01_M02_XIANWANG',
        target_scope = 'selected',
        duration = 5,
        payload = { defense_reduction = 0.05 },
    }, {
        target_ids = { 'boss' },
        targets = { unit_ref },
    }, 0)
    local cleanup = Effects.source_cleanup_commands(engine, 'p1')
    truthy(cleanup[1].target == unit_ref, 'effect cleanup preserves target unit reference')
end

do
    local adapter = setmetatable({}, {
        __index = function()
            return function() end
        end,
    })
    local runtime = Runtime.new(adapter)
    runtime:register('p1', {
        now = 0,
        ability_levels = { C01_A05 = 5 },
        passive_levels = { C01_P08 = 5 },
    })
    runtime:register('p2', {
        now = 0,
        ability_levels = { C01_A05 = 5 },
    })
    runtime:use_skill('p1', 'C01_A05', 5, 0, { target_count = 1, target_ids = { 'boss' } })
    runtime:use_skill('p2', 'C01_A05', 5, 1, { target_count = 1, target_ids = { 'boss' } })
    local effect = runtime:get_effect('boss', 'C01_M02_XIANWANG', 1)
    near(effect.payload.defense_reduction, 0.11, 0.00001, 'runtime shared highest effect')
    runtime:clear_transient('p1', 2, 'test-source-clear')
    effect = runtime:get_effect('boss', 'C01_M02_XIANWANG', 2)
    near(effect.payload.defense_reduction, 0.06, 0.00001, 'runtime falls back to remaining source')
    runtime:clear_transient('p2', 3, 'test-source-clear')
    truthy(runtime:get_effect('boss', 'C01_M02_XIANWANG', 3) == nil, 'runtime clears final shared source')
end

do
    local state_events = {}
    local adapter = setmetatable({
        state_changed = function(_, _, event)
            state_events[#state_events + 1] = event
        end,
    }, {
        __index = function()
            return function() end
        end,
    })
    local runtime = Runtime.new(adapter)
    local state = runtime:register('dongming', { now = 0 })
    state.momentum = 80
    runtime:tick('dongming', 5, {})
    truthy(state_events[#state_events].dongming == false, 'decay removes derived dongming')
    state.true_realm = { tier = 1, expires_at = 10 }
    state.momentum = 35
    runtime:normal_attack_hit('dongming', 6, {})
    local found_true = false
    for _, event in ipairs(state_events) do
        if event.dongming == true then
            found_true = true
        end
    end
    truthy(found_true, 'true realm preserves derived dongming below threshold')
end

do
    local state = Core.new {
        now = 0,
        passive_levels = { C01_P08 = 5, C01_P04 = 5 },
    }
    Core.gain_momentum(state, 100, { now = 0, effective_hit = true })
    local result = Skills.use(state, 'C01_A08', 5, 0, {
        hit = true,
        xianwang = true,
        target_id = 'boss',
        target_rank = 'boss',
    })
    truthy(result.ok, 'a08 use')
    truthy(find(result.commands, 'damage', 'xianwang-followup') ~= nil, 'a08 xianwang followup')
    truthy(find(result.commands, 'delayed_damage', 'fissure') ~= nil, 'a08 fissure')
    truthy(find(result.commands, 'apply_team_modifier') ~= nil, 'p08 mingshi')
end

do
    local first = Core.new { now = 0 }
    local second = Core.new { now = 0 }
    Core.gain_momentum(first, 80, { now = 0, effective_hit = true })
    equal(first.momentum, 80, 'first state resource')
    equal(second.momentum, 0, 'second state isolated')
    Core.clear_transient(first, 10)
    equal(first.momentum, 0, 'clear momentum')
    equal(first.ultimate_gauge, 0, 'clear ultimate')
end

do
    local enemy = {
        id = 7001,
        get_id = function(self) return self.id end,
        find_buff = function() return nil end,
        get_attr = function(_, name) return name == '最大生命' and 100 or 50 end,
        get_point = function() return {} end,
    }
    local ally = {}
    local selector_methods = {}
    function selector_methods:in_shape() return self end
    function selector_methods:in_range() return self end
    function selector_methods:is_enemy() self.mode = 'enemy'; return self end
    function selector_methods:is_ally() self.mode = 'ally'; return self end
    function selector_methods:not_in_state() return self end
    function selector_methods:without_tag() return self end
    function selector_methods:pick() return self.mode == 'ally' and { ally } or { enemy } end
    _G.y3 = {
        const = { UnitEnumState = { ['无敌'] = 1 } },
        selector = { create = function() return setmetatable({}, { __index = selector_methods }) end },
        shape = {
            create_circular_shape = function() return {} end,
            create_rectangle_shape = function() return {} end,
            create_sector_shape = function() return {} end,
        },
        point = { get_point_offset_vector = function(point) return point end },
    }
    package.loaded.powang_y3_targeting = nil
    local Targeting = require 'powang_y3_targeting'
    local targeting = Targeting.new {}
    local source = {
        get_point = function() return {} end,
        get_facing = function() return 90 end,
        get_owner = function() return 'player' end,
    }
    local context = targeting:build_context(nil, 'p1', 'C01_A03', 5, source, nil, {})
    equal(context.target_count, 1, 'default targeting enemy count')
    equal(context.hit_count, 3, 'default targeting a03 hit count')
    truthy(context.same_target_all, 'default targeting same target')
    context = targeting:build_context(nil, 'p1', 'C01_A08', 5, source, nil, {})
    equal(#context.team_targets, 1, 'default targeting team range')
    truthy(context.target_meta_by_id[context.target_id] ~= nil, 'targeting stores metadata for every selected target')
    equal(context.target_meta_by_id[context.target_id].rank, nil, 'missing project rank resolver does not guess a special rank')
    _G.y3 = nil
end

do
    local valid, missing = Contract.validate({})
    truthy(not valid, 'empty adapter rejected')
    equal(#missing, 12, 'adapter required method count')

    local calls = {}
    local adapter = {}
    local function record(name, ...)
        calls[#calls + 1] = { name = name, values = { ... } }
    end
    function adapter:sync_hero_stats(...) record('sync_hero_stats', ...) end
    function adapter:sync_ability_charge(...) record('sync_ability_charge', ...) end
    function adapter:deal_damage(...) record('deal_damage', ...) end
    function adapter:apply_break(...) record('apply_break', ...) end
    function adapter:schedule_damage(...) record('schedule_damage', ...) end
    function adapter:move_safely(...) record('move_safely', ...) end
    function adapter:apply_effect(...) record('apply_effect', ...) end
    function adapter:change_cooldown(...) record('change_cooldown', ...) end
    function adapter:apply_control(...) record('apply_control', ...) end
    function adapter:set_combo_floor(...) record('set_combo_floor', ...) end
    function adapter:heal_and_guard(...) record('heal_and_guard', ...) end
    function adapter:state_changed(...) record('state_changed', ...) end

    valid, missing = Contract.validate(adapter)
    truthy(valid and #missing == 0, 'complete adapter accepted')

    local runtime = Runtime.new(adapter)
    local state = runtime:register('player-1', {
        level = 60,
        ability_levels = { C01_A04 = 5, C01_A05 = 5, C01_A08 = 5, C01_A02 = 5 },
        passive_levels = { C01_P03 = 5, C01_P07 = 5 },
        ultimate_tier = 3,
        now = 0,
    })
    equal(state.stats.hp_max, 4632, 'runtime actor stats')

    local generator = runtime:use_skill('player-1', 'C01_A04', 5, 0, { target_count = 1 })
    truthy(generator.ok, 'runtime generator use')
    truthy(#calls > 0, 'runtime dispatched adapter calls')
    truthy(runtime:on_move_finished('player-1', 0.4), 'runtime movement completion')
    near(state.statuses.C01_M09_TAXU_WIND.expires_at, 3.4, 0.00001, 'p03 refreshes after movement')
    near(state.statuses.C01_M10_JINTUI_GUARD.expires_at, 1.9, 0.00001, 'p07 refreshes after movement')

    local mark = runtime:use_skill('player-1', 'C01_A05', 5, 0.5, {
        target_count = 1,
        target_ids = { 'boss' },
    })
    truthy(mark.ok, 'runtime xianwang application')
    truthy(runtime:get_effect('boss', 'C01_M02_XIANWANG', 0.5, 'player-1') ~= nil, 'runtime effect store connected')

    Core.gain_momentum(state, 100, { now = 1, effective_hit = true })
    local spender = runtime:use_skill('player-1', 'C01_A08', 5, 1, {
        hit = true,
        xianwang = true,
        target_id = 'boss',
        target_rank = 'boss',
    })
    truthy(spender.ok, 'runtime spender use')
    local a08_control = find(spender.commands, 'control')
    equal(a08_control.target_scope, 'selected', 'a08 control declares its selected target scope')
    truthy(a08_control.requires_target_rank, 'a08 control requires per-target rank metadata')

    Core.gain_momentum(state, 100, { now = 1.2, effective_hit = true })
    local committed = runtime:commit_skill('player-1', 'C01_A02', 5, 1.2, {})
    truthy(committed.ok, 'runtime asynchronous commit')
    local confirmed = runtime:confirm_skill_hit('player-1', committed.cast_id, 1.3, {
        target_id = 'boss',
        target_rank = 'boss',
    })
    truthy(confirmed.ok, 'runtime asynchronous confirmation')

    state.ultimate_gauge = 100
    local ultimate = runtime:activate_ultimate('player-1', 2, {})
    truthy(ultimate.ok, 'runtime ultimate use')

    truthy(runtime:clear_transient('player-1', 3, 'test'), 'runtime clear')
    equal(state.momentum, 0, 'runtime clear momentum')
    truthy(runtime:get_effect('boss', 'C01_M02_XIANWANG', 3, 'player-1') == nil, 'runtime source effects clear')
    local unknown = runtime:use_skill('missing', 'C01_A01', 1, 0, { target_count = 1 })
    truthy(not unknown.ok and unknown.error == 'unknown-actor', 'runtime unknown actor guard')
end

print('PASS: ' .. tostring(tests) .. ' assertions')
