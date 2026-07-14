package.path = 'implementation/profession_common/lua/?.lua;implementation/chiming/lua/?.lua;' .. package.path

local Config = require 'chiming_config'
local Core = require 'chiming_core'
local Skills = require 'chiming_skills'
local Runtime = require 'chiming_runtime'
local Effects = require 'chiming_effects'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function near(actual, expected, epsilon, message)
    tests = tests + 1
    if math.abs(actual - expected) > epsilon then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end
local function find(commands, command_type, predicate)
    for _, command in ipairs(commands or {}) do
        if command.type == command_type and (predicate == nil or predicate(command)) then return command end
    end
    return nil
end
local function count(commands, command_type, predicate)
    local result = 0
    for _, command in ipairs(commands or {}) do
        if command.type == command_type and (predicate == nil or predicate(command)) then result = result + 1 end
    end
    return result
end
local function count_keys(values)
    local result = 0
    for _ in pairs(values) do result = result + 1 end
    return result
end

local function unit(id)
    local value = { id = id, exists = true, alive = true }
    function value:get_id() return self.id end
    function value:is_exist() return self.exists end
    function value:is_alive() return self.alive end
    return value
end

local hero, enemy, enemy2, enemy3, ally = unit('hero'), unit('enemy'), unit('enemy2'), unit('enemy3'), unit('ally')

local function refs()
    return { hero = hero, enemy = enemy, enemy2 = enemy2, enemy3 = enemy3, ally = ally }
end

local function cast_context(options)
    options = options or {}
    local value = {
        actor_id = 'hero', lifecycle_id = options.lifecycle_id or 1,
        unit = hero, unit_id = 'hero', primary_target_id = options.primary_target_id,
        primary_target_ref = options.primary_target_ref,
        target_refs_by_id = options.target_refs_by_id or refs(),
        cast_point = options.cast_point, target_point = options.cast_point,
        team_target_ids = options.team_target_ids or { 'ally' },
        team_targets = options.team_targets or { ally },
    }
    if value.primary_target_id == nil and options.no_primary ~= true then
        value.primary_target_id, value.primary_target_ref = 'enemy', enemy
    end
    for key, item in pairs(options) do value[key] = item end
    return value
end

local function confirmation_context(options)
    options = options or {}
    local value = {
        actor_id = 'hero', lifecycle_id = options.lifecycle_id or 1,
        unit = hero, unit_id = 'hero', target_refs_by_id = options.target_refs_by_id or refs(),
        target_meta_by_id = options.target_meta_by_id or {}, hit_events = options.hit_events or {},
        reflection_candidates = options.reflection_candidates or {}, pierce_candidates = options.pierce_candidates or {},
        team_purge_success_ids = options.team_purge_success_ids or {},
        team_purge_success_targets = options.team_purge_success_targets or {},
    }
    for key, item in pairs(options) do value[key] = item end
    return value
end

local function hit(cast_id, target, phase, rank, time, distance)
    return {
        cast_id = cast_id, lifecycle_id = 1, phase = phase or 'direct', target_id = target:get_id(), target = target,
        damage_dealt = 1, hit_time = time or 0, path_distance = distance or 0, target_rank = rank or 'normal', alive = true,
    }
end

local function full_state(options)
    options = options or {}
    options.level = options.level or 60
    options.ultimate_tier = options.ultimate_tier or 3
    options.ability_levels = options.ability_levels or {
        C03_A01 = 5, C03_A02 = 5, C03_A03 = 5, C03_A04 = 5,
        C03_A05 = 5, C03_A06 = 5, C03_A07 = 5, C03_A08 = 5,
    }
    options.passive_levels = options.passive_levels or {
        C03_P01 = 5, C03_P02 = 5, C03_P03 = 5, C03_P04 = 5,
        C03_P05 = 5, C03_P06 = 5, C03_P07 = 5, C03_P08 = 5,
    }
    local state = Core.new(options)
    state.lifecycle_id = 1
    return state
end

local function commit(state, skill_key, rank, now, options)
    local result = Skills.commit_skill(state, skill_key, rank, now, cast_context(options))
    truthy(result.ok, skill_key .. ' commits')
    return result
end

local function confirm(state, cast, now, options)
    return Skills.confirm_skill_hit(state, cast.cast_id, now, confirmation_context(options))
end

do
    equal(count_keys(Config.abilities), 8, 'active skill count')
    equal(count_keys(Config.passives), 8, 'passive skill count')
    equal(count_keys(Config.modifiers), 12, 'modifier count')
    equal(Config.resource.ultimate_per_effective_seal, 5, 'one earned seal contributes five ultimate')
    truthy(loadfile('implementation/chiming/lua/chiming_boss_contribution.lua') ~= nil, 'contribution module syntax')
    truthy(loadfile('implementation/chiming/lua/chiming_y3_adapter.lua') ~= nil, 'adapter syntax')
    truthy(loadfile('implementation/chiming/lua/chiming_y3_controller.lua') ~= nil, 'controller syntax')
end

do
    local expected = {
        [1] = { 590, 24, 52, 18, 22 }, [20] = { 1806, 66, 168, 48, 56 },
        [40] = { 3086, 110, 290, 80, 92 }, [60] = { 4366, 154, 412, 112, 128 },
    }
    for level, values in pairs(expected) do
        local stats = Core.hero_stats(level)
        equal(stats.hp_max, values[1], 'hp breakpoint')
        equal(stats.attack_physical, values[2], 'physical breakpoint')
        equal(stats.attack_magic, values[3], 'magic breakpoint')
        equal(stats.defense_physical, values[4], 'physical defense breakpoint')
        equal(stats.defense_magic, values[5], 'magic defense breakpoint')
    end
    near(Core.hero_stats(1).move_speed, 3.65, 0.00001, 'move speed')
end

do
    local locked = Core.new { level = 1, ability_levels = { C03_A01 = 1 }, now = 0 }
    truthy(not Core.is_resource_enabled(locked), 'Lv1 does not expose seals')
    local result, error_code = Core.gain_seal(locked, 'C03_A01', 0)
    equal(result, nil, 'locked gain is rejected')
    equal(error_code, 'resource-locked', 'locked resource error')
    Core.set_level(locked, 8)
    Core.set_ability_level(locked, 'C03_A03', 1)
    truthy(Core.is_resource_enabled(locked), 'Lv8 core skill enables seals')
end

do
    local state = full_state { now = 0 }
    equal(Core.gain_seal(state, 'C03_A01', 0).gained, 1, 'generator creates earned seal')
    local blocked, error_code = Core.gain_seal(state, 'C03_A02', 1)
    equal(blocked, nil, 'shared generator window blocks a second source')
    equal(error_code, 'shared-generator-window', 'shared generator error')
    equal(Core.gain_seal(state, 'C03_A02', 4).gained, 1, 'second earned seal follows the window')
    Core.refund_seal(state, 4, 'test-refund', 'refunded')
    equal(state.seals, 3, 'three entries fill the queue')
    local overflow = Core.refund_seal(state, 5, 'test-external', 'external')
    equal(overflow, 0, 'full queue rejects new entries without replacement')
    local sources = Core.seal_sources(state)
    equal(sources.earned, 2, 'earned entries remain intact on overflow')
    equal(sources.refunded, 1, 'refunded entry remains intact on overflow')
    equal(sources.external, 0, 'external entry was not inserted on overflow')
end

do
    local state = full_state { now = 0 }
    Core.set_seals(state, 1, 'earned')
    Core.refund_seal(state, 0, 'refund', 'refunded')
    Core.refund_seal(state, 0, 'external', 'external')
    local token = Core.begin_cast(state, 'C03_A06', 0, cast_context())
    equal(token.spent_seals[1].origin, 'earned', 'spend priority begins with earned')
    equal(token.spent_seals[2].origin, 'refunded', 'spend priority continues with refunded')
    equal(token.spent_seals[3].origin, 'external', 'spend priority ends with external')
    Core.finish_cast(state, token.id, 0, 'test')
end

do
    local state = full_state { now = 0 }
    local first = commit(state, 'C03_A01', 5, 0)
    local missed = confirm(state, first, 0.1, { hit_events = { hit(first.cast_id, enemy2, 'direct', 'normal') } })
    truthy(missed.ok and missed.missed, 'A01 rejects a non-primary contact')
    equal(state.seals, 0, 'missed A01 cannot generate a seal')
    local second = commit(state, 'C03_A01', 5, 4)
    local landed = confirm(state, second, 4.1, { hit_events = { hit(second.cast_id, enemy, 'direct', 'normal') } })
    truthy(landed.ok, 'A01 accepts a confirmed primary hit')
    equal(state.seals, 1, 'confirmed A01 generates one earned seal')
    equal(Core.seal_sources(state).earned, 1, 'A01 output is marked earned')
end

do
    local state = full_state { now = 0 }
    local cast = commit(state, 'C03_A02', 5, 0, { no_primary = true })
    local result = confirm(state, cast, 0.2, {
        hit_events = {
            hit(cast.cast_id, enemy, 'outbound', 'normal', 0.1, 3),
            hit(cast.cast_id, enemy, 'outbound', 'normal', 0.2, 4),
            hit(cast.cast_id, enemy, 'return', 'normal', 0.3, 2),
            hit(cast.cast_id, enemy2, 'return', 'elite', 0.4, 5),
        },
    })
    truthy(result.ok, 'A02 accepts explicit path hit events')
    equal(state.seals, 1, 'two paths still award only one earned seal')
    equal(count(result.commands, 'damage'), 2, 'A02 produces one command per path')
end

do
    local state = full_state { now = 0 }
    Core.set_seals(state, 1, 'earned')
    local cast = commit(state, 'C03_A03', 5, 0)
    local fallback = confirm(state, cast, 0.1, { hit_events = { hit(cast.cast_id, enemy, 'direct', 'normal') } })
    local reflection = find(fallback.commands, 'delayed_damage', function(command) return command.break_event_key == 'a03-reflection-fallback' end)
    truthy(reflection ~= nil, 'A03 falls back to the actual primary when no reflection target exists')
    near(reflection.coefficient, Config.abilities.C03_A03.reflection[5] * 0.70, 0.00001, 'fallback uses the fixed seventy percent coefficient')
    equal(reflection.target_id, 'enemy', 'fallback cannot retarget from candidate geometry')

    local mingtai = full_state { now = 0 }
    Core.set_seals(mingtai, 3, 'earned')
    local enhanced = commit(mingtai, 'C03_A03', 5, 1)
    local ordered = confirm(mingtai, enhanced, 1.1, {
        hit_events = { hit(enhanced.cast_id, enemy, 'direct', 'normal') },
        target_meta_by_id = { enemy2 = { private_minghen = true }, enemy3 = { private_minghen = false } },
        reflection_candidates = {
            { target = enemy3, distance = 1.0 }, { target = enemy2, distance = 3.0 },
        },
    })
    local first_reflection = find(ordered.commands, 'delayed_damage', function(command) return command.break_event_key == 'a03-reflection' end)
    local extra_reflection = find(ordered.commands, 'delayed_damage', function(command) return command.break_event_key == 'a03-mingtai-reflection' end)
    equal(first_reflection.target_id, 'enemy2', 'private M02 marker wins reflection priority before distance')
    equal(extra_reflection.target_id, 'enemy3', 'Mingtai adds exactly one distinct second reflection')
end

do
    local state = full_state { now = 0 }
    Core.set_seals(state, 1, 'refunded')
    local cast = commit(state, 'C03_A03', 5, 0)
    local result = confirm(state, cast, 0.1, { hit_events = { hit(cast.cast_id, enemy) } })
    truthy(result.ok, 'refunded seal may pay a skill cost')
    equal(state.ultimate_gauge, 0, 'refunded seal never adds ultimate')
    Core.set_seals(state, 1, 'external')
    cast = commit(state, 'C03_A03', 5, 1)
    result = confirm(state, cast, 1.1, { hit_events = { hit(cast.cast_id, enemy) } })
    truthy(result.ok, 'external seal may pay a skill cost')
    equal(state.ultimate_gauge, 0, 'external seal never adds ultimate')
end

do
    local state = full_state { now = 0 }
    for index = 1, 20 do
        Core.set_seals(state, 1, 'earned')
        local cast = commit(state, 'C03_A03', 5, index * 4)
        local result = confirm(state, cast, index * 4 + 0.1, { hit_events = { hit(cast.cast_id, enemy) } })
        truthy(result.ok, 'eligible earned spend confirms')
    end
    equal(state.ultimate_gauge, 100, 'twenty eligible earned spends fill the ultimate gauge')
    truthy(Skills.activate_ultimate(state, 84).ok, 'first ultimate opens around the eighty-four second balance target')
    for index = 1, 3 do
        Core.set_seals(state, 1, 'earned')
        local cast = commit(state, 'C03_A03', 5, 84 + index)
        confirm(state, cast, 84 + index + 0.1, { hit_events = { hit(cast.cast_id, enemy) } })
    end
    equal(state.ultimate_gauge, 15, 'three later earned spends leave fifteen ultimate after activation')
end

do
    local state = full_state { now = 0 }
    Core.set_seals(state, 1, 'earned')
    local cast = Skills.use(state, 'C03_A04', 5, 0, cast_context())
    truthy(cast.ok and cast.pending_protection, 'A04 waits for an attributed protection event')
    local wrong = Skills.on_damage_taken(state, 0.2, {
        protection_qualification = { effective_protection = true, cast_id = cast.cast_id, effect_key = 'C03_M07_FANZHAO_SHIELD',
            target_id = 'hero', lifecycle_id = 1, absorbed = 10 }, unit_id = 'hero', lifecycle_id = 1,
    })
    truthy(not wrong.ok and wrong.error == 'protection-attribution-mismatch', 'A04 rejects another skill protection window')
    local protected = Skills.on_damage_taken(state, 0.3, {
        protection_qualification = { effective_protection = true, cast_id = cast.cast_id, effect_key = 'C03_M03_CHENGXIN_SHIELD',
            target_id = 'hero', lifecycle_id = 1, absorbed = 10, reduced = 0 }, unit_id = 'hero', lifecycle_id = 1,
    })
    truthy(protected.ok, 'A04 accepts its own effective shield event')
    equal(state.ultimate_gauge, 5, 'an earned A04 spend contributes five ultimate')
    truthy(not Skills.on_damage_taken(state, 0.4, {
        protection_qualification = { effective_protection = true, cast_id = cast.cast_id, effect_key = 'C03_M03_CHENGXIN_SHIELD',
            target_id = 'hero', lifecycle_id = 1, absorbed = 10 }, unit_id = 'hero', lifecycle_id = 1,
    }).ok, 'one protection token cannot settle twice')
end

do
    local state = full_state { now = 0 }
    Core.set_seals(state, 3, 'earned')
    local cast = commit(state, 'C03_A08', 5, 0, { cast_point = { id = 'point' }, team_target_ids = { 'ally' }, team_targets = { ally } })
    local result = confirm(state, cast, 0.1, {
        hit_events = { hit(cast.cast_id, enemy, 'impact', 'boss') },
        target_meta_by_id = { enemy = { rank = 'boss', private_luyin = true } },
        team_purge_success_ids = { 'ally', 'enemy' }, team_purge_success_targets = { ally, enemy },
    })
    truthy(result.ok, 'A08 confirms against a boss')
    local impact = find(result.commands, 'damage', function(command) return command.break_event_key == 'a08-impact' end)
    equal(impact.break_value, 2.3, 'rank-five A08 initial break is 2.3')
    equal(count(result.commands, 'break', function(command) return command.break_event_key == 'a08-luyin' end), 1, 'M06 adds one break event')
    equal(count(result.commands, 'break', function(command) return command.break_event_key == 'a08-p07' end), 1, 'P07 adds one break event')
    equal(count(result.commands, 'delayed_damage', function(command) return command.break_value ~= nil end), 0, 'A08 pulses never carry break')
    local team = find(result.commands, 'apply_modifier', function(command) return command.key == 'C03_M10_TONGLV_QINGMING' end)
    equal(team.target_ids[1], 'ally', 'team purge reward intersects the committed team snapshot')
    equal(#team.target_ids, 1, 'team purge reward removes duplicates and unauthorized targets')

    local unknown = full_state { now = 0 }
    Core.set_seals(unknown, 3, 'earned')
    local unknown_cast = commit(unknown, 'C03_A08', 5, 0, { cast_point = { id = 'point' } })
    local unknown_result = confirm(unknown, unknown_cast, 0.1, { hit_events = { hit(unknown_cast.cast_id, enemy, 'impact', 'unknown') } })
    truthy(find(unknown_result.commands, 'apply_modifier', function(command) return command.key == 'C03_M09_JINGLV_ZHENYA' end) == nil,
        'unknown rank cannot receive M09 control')
    truthy(find(unknown_result.commands, 'control') == nil, 'unknown rank cannot receive root control')
end

do
    local state = full_state { now = 0 }
    Core.set_seals(state, 1, 'earned')
    local cast = commit(state, 'C03_A05', 5, 0, { cast_point = { id = 'point' } })
    local missed = confirm(state, cast, 0.1, { hit_events = {} })
    truthy(missed.ok and missed.missed, 'A05 retains its field after a missed initial hit')
    truthy(find(missed.commands, 'delayed_damage', function(command) return command.pulse_key == 'C03_A05' end) ~= nil,
        'A05 pulse commands carry a required pulse snapshot key')
    equal(state.ultimate_gauge, 0, 'a missed spender does not award ultimate')
end

do
    local state = full_state { now = 0 }
    Core.set_seals(state, 2, 'earned')
    state.ultimate_gauge, state.last_effective_at = 40, 0
    local tick = Skills.tick(state, 6)
    equal(state.seals, 0, 'out of combat clears every seal source')
    equal(state.ultimate_gauge, 40, 'out of combat preserves the ultimate gauge')
    truthy(find(tick, 'seals_cleared_out_of_combat') ~= nil, 'clear emits a resource state event')
    truthy(Effects.new() ~= nil, 'C03 creates the source-aware common effect store')
end

do
    local adapter = {}
    for _, name in ipairs(require('chiming_adapter_contract').required_methods()) do adapter[name] = function() end end
    local runtime = Runtime.new(adapter)
    runtime:register('one', { level = 8, lifecycle_id = 7, ability_levels = { C03_A03 = 1 }, context = { unit = hero } })
    local cast = runtime:commit_skill('one', 'C03_A03', 1, 0, cast_context { lifecycle_id = 7 })
    truthy(cast.ok, 'runtime commits an explicit snapshot')
    local missing = runtime:confirm_skill_hit('one', cast.cast_id, 0.1, { hit_events = {} })
    truthy(not missing.ok and missing.error == 'lifecycle-id-required', 'runtime refuses hit confirmation without lifecycle identity')
    runtime:remove('one')
    equal(runtime:get_state('one'), nil, 'runtime removes actor state')
end

print('PASS: ' .. tests .. ' core assertions')
