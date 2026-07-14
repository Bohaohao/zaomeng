package.path = 'implementation/profession_common/lua/?.lua;implementation/zhenjie/lua/?.lua;' .. package.path

local Config = require 'zhenjie_config'
local Core = require 'zhenjie_core'
local Skills = require 'zhenjie_skills'
local Effects = require 'zhenjie_effects'
local Contract = require 'zhenjie_adapter_contract'
local Runtime = require 'zhenjie_runtime'

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

local function count_keys(values)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    return count
end

local function find(commands, command_type, key)
    for _, command in ipairs(commands or {}) do
        if command.type == command_type and (key == nil or command.key == key) then return command end
    end
    return nil
end

do
    equal(count_keys(Config.abilities), 8, 'active skill count')
    equal(count_keys(Config.passives), 8, 'passive skill count')
    equal(count_keys(Config.modifiers), 12, 'modifier count')
    truthy(loadfile('implementation/zhenjie/lua/zhenjie_y3_adapter.lua') ~= nil, 'Y3 adapter syntax')
    truthy(loadfile('implementation/zhenjie/lua/zhenjie_y3_controller.lua') ~= nil, 'Y3 controller syntax')
    truthy(loadfile('implementation/zhenjie/lua/zhenjie_y3_targeting.lua') ~= nil, 'Y3 targeting syntax')
end

do
    local expected = {
        [1] = { 720, 42, 28, 20 }, [20] = { 2240, 131, 72, 54 },
        [40] = { 3840, 225, 118, 90 }, [60] = { 5440, 319, 164, 126 },
    }
    for level, values in pairs(expected) do
        local stats = Core.hero_stats(level)
        equal(stats.hp_max, values[1], 'hp breakpoint')
        equal(stats.attack_physical, values[2], 'attack breakpoint')
        equal(stats.defense_physical, values[3], 'physical defense breakpoint')
        equal(stats.defense_magic, values[4], 'magic defense breakpoint')
    end
    local stats = Core.hero_stats(1)
    near(stats.critical_chance, 0.04, 0.00001, 'base critical chance')
    near(stats.critical_damage, 1.45, 0.00001, 'base critical damage')
    near(stats.move_speed, 3.55, 0.00001, 'base move speed')
end

do
    local state = Core.new { now = 0 }
    local events, gained = Core.gain_guard(state, 150, { now = 0 })
    equal(gained, 100, 'guard caps at one hundred')
    equal(state.guard, 100, 'guard stored at cap')
    truthy(not Core.is_jieshi(state), 'Lv1 guard does not expose an unusable jieshi threshold')
    Core.set_level(state, 15)
    truthy(Core.is_jieshi(state), 'Lv15 guard threshold enables jieshi with a spender available')
    equal(events[1].type, 'guard_gain', 'guard emits state event')
    Core.tick(state, 6.0)
    equal(state.guard, 0, 'six second out of combat clears guard')
    truthy(not Core.is_jieshi(state), 'out of combat removes jieshi')
end

do
    local state = Core.new { now = 0, passive_levels = { C02_P01 = 5 } }
    Core.arm_next_generator(state, 5, 0)
    local _, gained = Core.gain_generator_guard(state, 10, { now = 1, generator_key = 'C02_A01' })
    equal(gained, 17, 'P01 adds guard to the next generator only')
    local _, second = Core.gain_generator_guard(state, 10, { now = 2, generator_key = 'C02_A02' })
    equal(second, 10, 'P01 is consumed after one generator')
end

do
    local state = Core.new { now = 0, ability_levels = { C02_A01 = 5 } }
    local result = Skills.use(state, 'C02_A01', 5, 0, { target_count = 4 })
    truthy(result.ok, 'A01 usable')
    equal(state.guard, 20, 'A01 gains base plus capped extra target guard')
    truthy(find(result.commands, 'damage'), 'A01 creates damage command')
end

do
    local state = Core.new { now = 0, ability_levels = { C02_A04 = 5 }, passive_levels = { C02_P01 = 5, C02_P05 = 5 } }
    local open = Skills.use(state, 'C02_A04', 5, 0, {})
    truthy(open.ok, 'A04 opens guard window')
    truthy(find(open.commands, 'apply_modifier', 'C02_M02_GUJIA'), 'A04 applies guard modifier')
    local periodic = Skills.trigger_guard_counter(state, 0.2, { damage = 10, periodic = true, guardable_hit = false, source_unit = { id = 'enemy' } })
    truthy(not periodic.ok, 'periodic damage cannot trigger parry')
    local counter = Skills.trigger_guard_counter(state, 0.3, { damage = 10, guardable_hit = true, source_unit = { id = 'enemy' } })
    truthy(counter.ok, 'real enemy damage triggers parry')
    equal(counter.kind, 'parry', 'A04 reports parry kind')
    equal(state.guard, 18, 'parry gives its rank guard and only arms P01 for a later generator')
    truthy(find(counter.commands, 'apply_modifier', 'C02_M04_FANZHEN'), 'parry arms counterattack')
    local repeated = Skills.trigger_guard_counter(state, 0.4, { damage = 10, guardable_hit = true, source_unit = { id = 'enemy' } })
    truthy(not repeated.ok, 'one A04 cast only parries once')
end

do
    local state = Core.new {
        now = 0, ability_levels = { C02_A07 = 5 }, passive_levels = { C02_P01 = 5, C02_P06 = 5 },
    }
    state.guard = 35
    local wall = Skills.use(state, 'C02_A07', 5, 0, { team_targets = {} })
    truthy(wall.ok and wall.pending_guard, 'A07 creates pending effective guard')
    equal(state.guard, 0, 'A07 spends its guard on commit')
    truthy(find(wall.commands, 'apply_modifier', 'C02_M08_BUDONG_BARRIER'), 'A07 applies shield')
    local guard = Skills.trigger_guard_counter(state, 0.5, { damage = 20, effective_protection = true, source_unit = { id = 'enemy' } })
    truthy(guard.ok and guard.kind == 'guard', 'A07 effective protection resolves once')
    equal(state.guard, 12, 'A07 success restores only documented guard')
    local repeated = Skills.trigger_guard_counter(state, 0.6, { damage = 20, effective_protection = true, source_unit = { id = 'enemy' } })
    truthy(not repeated.ok, 'A07 cannot farm repeated hits')
end

do
    local state = Core.new {
        now = 0, level = 15,
        ability_levels = { C02_A03 = 5, C02_A04 = 5, C02_A06 = 5 },
        passive_levels = { C02_P03 = 5, C02_P04 = 5 },
    }
    state.guard = 80
    Core.apply_status(state, 'C02_M04_FANZHEN', 0, 5, {})
    Core.apply_status(state, 'C02_P03_READY', 0, 5, { rank = 5 })
    local result = Skills.use(state, 'C02_A06', 5, 0.1, { target_count = 1 })
    truthy(result.ok, 'A06 can spend guard')
    equal(state.guard, 41, 'A06 cost then P04 refund is applied')
    truthy(find(result.commands, 'delayed_damage'), 'A06 creates fanzhen or jieshi follow-up damage')
    truthy(find(result.commands, 'remove_modifier', 'C02_M04_FANZHEN'), 'A06 consumes fanzhen')
end

do
    local state = Core.new { now = 0, level = 15, ability_levels = { C02_A08 = 5 }, passive_levels = { C02_P08 = 5 } }
    state.guard = 80
    local boss = { id = 'boss' }
    local result = Skills.use(state, 'C02_A08', 5, 0, {
        target_count = 1,
        targets = { boss }, target_ids = { 'boss' },
        target_meta_by_id = { boss = { rank = 'boss', private_jieding = true } },
    })
    truthy(result.ok, 'A08 usable')
    local control = find(result.commands, 'control')
    truthy(control and control.boss_converts_to_break, 'A08 converts boss control to break')
    truthy(control.boss_break_value > 0, 'jieshi improves boss break')
    truthy(find(result.commands, 'apply_modifier', 'C02_M10_TONGSHOU'), 'P08 grants team benefit under jieshi')
end

do
    local state = Core.new { now = 0, level = 15, ability_levels = { C02_A08 = 5 }, passive_levels = { C02_P08 = 5 } }
    state.guard = 50
    local marked, unmarked = { id = 'marked' }, { id = 'unmarked' }
    local result = Skills.use(state, 'C02_A08', 5, 0, {
        target_count = 2,
        targets = { marked, unmarked }, target_ids = { 'marked', 'unmarked' },
        target_meta_by_id = {
            marked = { rank = 'normal', private_jieding = true },
            unmarked = { rank = 'boss', private_jieding = false },
        },
    })
    local marked_bonus = nil
    for _, command in ipairs(result.commands) do
        if command.type == 'damage' and command.target_scope == 'explicit' then
            marked_bonus = command
        end
    end
    truthy(marked_bonus ~= nil, 'A08 emits a separate private-mark damage command')
    equal(#marked_bonus.target_ids, 1, 'A08 mark bonus does not spread through the whole area')
    equal(marked_bonus.target_ids[1], 'marked', 'A08 mark bonus only resolves the caster private mark')
    local zhenya = find(result.commands, 'apply_modifier', 'C02_M11_ZHENYA')
    equal(zhenya.target_ids[1], 'marked', 'A08 only applies control modifier to normal or elite targets')
    local control = find(result.commands, 'control')
    equal(control.target_scope, 'selected', 'A08 control preserves per-target rank metadata for boss conversion')
end

do
    local state = Core.new { now = 0, ability_levels = { C02_A02 = 3 } }
    local normal, elite, boss = { id = 'normal' }, { id = 'elite' }, { id = 'boss' }
    local result = Skills.use(state, 'C02_A02', 3, 0, {
        target_count = 3,
        targets = { normal, elite, boss }, target_ids = { 'normal', 'elite', 'boss' },
        target_meta_by_id = { normal = { rank = 'normal' }, elite = { rank = 'elite' }, boss = { rank = 'boss' } },
    })
    local rank_break = find(result.commands, 'break')
    equal(#rank_break.target_ids, 2, 'A02 rank-three bonus break excludes normal targets')
    equal(rank_break.target_ids[1], 'elite', 'A02 rank-three bonus includes elite target')
    equal(rank_break.target_ids[2], 'boss', 'A02 rank-three bonus includes boss target')
end

do
    local state = Core.new { now = 0, ability_levels = { C02_A03 = 1 } }
    local result = Skills.use(state, 'C02_A03', 1, 0, {
        target_count = 2, hit_count = 2, primary_hit_twice = true,
    })
    truthy(result.ok, 'A03 accepts a stable primary two-hit sequence with nearby adds')
    equal(state.guard, 13, 'A03 grants the two-hit same-primary bonus without requiring a single target area')
end

do
    local effects = Effects.new()
    Effects.apply(effects, 'boss', 'C02_M06_JIEDING_SLOW', 'p1', 0, 5, { normal_slow = 0.15 })
    Effects.apply(effects, 'boss', 'C02_M06_JIEDING_SLOW', 'p2', 0, 8, { normal_slow = 0.30 })
    local shared = Effects.get(effects, 'boss', 'C02_M06_JIEDING_SLOW', 1)
    near(shared.payload.normal_slow, 0.30, 0.00001, 'slow takes shared highest value')
    Effects.apply(effects, 'boss', 'C02_M07_JIEDING_MARK', 'p1', 0, 4, {})
    Effects.apply(effects, 'boss', 'C02_M07_JIEDING_MARK', 'p2', 0, 4, {})
    truthy(Effects.remove_source(effects, 'boss', 'C02_M07_JIEDING_MARK', 'p1'), 'one private mark removes')
    truthy(Effects.get(effects, 'boss', 'C02_M07_JIEDING_MARK', 1, 'p2') ~= nil, 'other private mark remains')
end

do
    local state = Core.new { now = 0, ultimate_tier = 3 }
    state.ultimate_gauge = 100
    local result = Skills.activate_ultimate(state, 0)
    truthy(result.ok, 'ultimate activates at full gauge')
    truthy(find(result.commands, 'apply_modifier', 'C02_M12_GUIYUAN'), 'ultimate applies realm modifier')
    equal(state.ultimate_gauge, 0, 'ultimate consumes gauge')
    local _, extra = Core.gain_generator_guard(state, 10, { now = 1, generator_key = 'C02_A01' })
    equal(extra, 10, 'first generator remains a valid gain')
    equal(state.guard, 15, 'tier two generator bonus also applies during tier three')
end

do
    local calls = {}
    local adapter = {}
    for _, name in ipairs(Contract.required_methods()) do
        adapter[name] = function(_, actor, command)
            calls[#calls + 1] = { name = name, actor = actor, command = command }
        end
    end
    local runtime = Runtime.new(adapter)
    local unit = { id = 'hero' }
    runtime:register('one', { now = 0, context = { unit = unit }, ability_levels = { C02_A01 = 5 } })
    runtime:register('two', { now = 0, context = { unit = { id = 'hero-two' } }, ability_levels = { C02_A01 = 5 } })
    local first = runtime:use_skill('one', 'C02_A01', 5, 0, { unit = unit, target_count = 1, targets = { { id = 'boss' } } })
    truthy(first.ok, 'runtime dispatches generator')
    equal(runtime:get_state('one').guard, 14, 'actor one owns its guard')
    equal(runtime:get_state('two').guard, 0, 'actor two remains isolated')
    truthy(#calls > 0, 'runtime dispatches through adapter contract')
end

print('PASS: ' .. tests .. ' assertions')
