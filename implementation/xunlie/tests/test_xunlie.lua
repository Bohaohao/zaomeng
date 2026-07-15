package.path = 'implementation/profession_common/lua/?.lua;implementation/xunlie/lua/?.lua;' .. package.path

local Config = require 'xunlie_config'
local Core = require 'xunlie_core'
local Skills = require 'xunlie_skills'

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
    if math.abs(actual - expected) > epsilon then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function find(commands, command_type, key)
    for _, command in ipairs(commands or {}) do
        if command.type == command_type and (key == nil or command.key == key) then return command end
    end
    return nil
end

local function ref(id)
    return { id = id }
end

local function context(primary, selected, metadata)
    local refs = {}
    if primary then refs[primary.id] = primary end
    for _, target in ipairs(selected or {}) do refs[target.id] = target end
    return {
        actor_id = 'actor', lifecycle_id = 1, combat_scope = 'public', source_unit_id = 'hero',
        source_unit = ref('hero'), unit_id = 'hero', unit = ref('hero'),
        primary_target_id = primary and primary.id or nil, primary_target_ref = primary,
        selected_target_ids = (function()
            local ids = {}; for index, target in ipairs(selected or {}) do ids[index] = target.id end; return ids
        end)(),
        target_refs_by_id = refs, target_meta_by_id = metadata or {}, direction = 0,
        cast_point = { x = 1, y = 1 }, safe_landing_result = true, safe_landing_point = { x = 2, y = 2 },
    }
end

local function fill(state, target_id, count, start)
    for index = 1, count do
        local result, error_code = Core.gain_hunt(state, target_id, (start or 0) + index, 'C04_A01')
        truthy(result ~= nil, 'mark gain should not fail: ' .. tostring(error_code))
    end
end

do
    local stats = Core.hero_stats(60)
    equal(stats.hp_max, 3982, 'Lv60 HP follows the approved formula')
    equal(stats.attack_physical, 368, 'Lv60 physical attack follows the approved formula')
    equal(stats.defense_physical, 108, 'Lv60 physical defense follows the approved formula')
    equal(stats.defense_magic, 115, 'Lv60 magic defense follows the approved formula')
end

do
    equal(Config.abilities.C04_A05.cooldown[2], 11.5, 'A05 rank two cooldown follows the formal baseline')
    equal(Config.abilities.C04_A06.cooldown[2], 15.0, 'A06 rank two cooldown follows the formal baseline')
    equal(Config.abilities.C04_A07.cooldown[2], 17, 'A07 rank two cooldown follows the formal baseline')
    equal(Config.abilities.C04_A08.cooldown[2], 18, 'A08 rank two cooldown follows the formal baseline')
end

do
    local state = Core.new { level = 8, ability_levels = { C04_A03 = 1 } }
    truthy(Core.is_resource_enabled(state), 'Lv8 learned core enables hunt marks')
    fill(state, 'boss', 5)
    equal(Core.hunt_count(state, 'boss'), 5, 'marks cap at five')
    local full = Core.gain_hunt(state, 'boss', 10, 'C04_A01')
    equal(full.gained, 0, 'full target only refreshes')
    equal(Core.hunt_count(state, 'boss'), 5, 'full refresh never adds a sixth mark')
    local normal = Core.gain_hunt(state, 'normal', 20, 'normal')
    equal(normal.gained, 1, 'normal attack adds one mark')
    local blocked = Core.gain_hunt(state, 'normal', 21, 'normal')
    equal(blocked.gained, 0, 'normal attack respects its per-target interval')
end

do
    local state = Core.new { level = 8, ability_levels = { C04_A03 = 5 } }
    fill(state, 'boss', 5)
    state.combat_epoch_start, state.first_recovery_earliest_tick = 15, 267
    local target = ref('boss')
    local started = Skills.commit_skill(state, 'C04_A03', 5, 292, context(target))
    truthy(started.ok, 'A03 reserves two marks')
    equal(Core.hunt_count(state, 'boss'), 5, 'reservation does not consume before a confirmed hit')
    local hit = Skills.confirm_skill_hit(state, started.cast_id, 292, {
        target_id = 'boss', target_ref = target, phase = 'direct', hit_key = 'a03-hit', component_key = 'main', damage_dealt = 1, alive = true,
    })
    truthy(hit.ok, 'A03 confirms a matching primary hit')
    equal(Core.hunt_count(state, 'boss'), 3, 'A03 consumes exactly its reserved two marks')
    equal(state.ultimate_gauge, 20, 'first legal locked consumption grants exactly 20 ultimate')
    equal(state.recovery_next_eligible_tick, 1252, 'recovery writes the persistent 16 second clock')
    local direct = find(hit.commands, 'damage')
    near(direct.coefficient, 2.46, 0.00001, 'A03 uses base plus two confirmed marks')
    truthy(find(hit.commands, 'apply_modifier', 'C04_M04_PIERCE') ~= nil, 'A03 creates private pierce')
    Core.clear_transient(state, 300)
    equal(state.recovery_next_eligible_tick, 1252, 'transient cleanup never resets recovery eligibility')
end

do
    local state = Core.new { level = 8, ability_levels = { C04_A01 = 5, C04_A03 = 1 } }
    fill(state, 'target', 3)
    local target = ref('target')
    local started = Skills.commit_skill(state, 'C04_A01', 5, 30, context(target))
    local hit = Skills.confirm_skill_hit(state, started.cast_id, 30, {
        target_id = 'target', target_ref = target, phase = 'direct', hit_key = 'a01-hit', component_key = 'main', damage_dealt = 1, alive = true,
    })
    truthy(hit.ok, 'A01 accepts its locked target')
    truthy(find(hit.commands, 'apply_modifier', 'C04_M03_TRACE') ~= nil, 'A01 rank five creates trace at three prior marks')
end

do
    local state = Core.new { level = 8, ability_levels = { C04_A05 = 5 } }
    fill(state, 'one', 5); fill(state, 'two', 2); fill(state, 'three', 1)
    local one, two, three = ref('one'), ref('two'), ref('three')
    local started = Skills.commit_skill(state, 'C04_A05', 5, 100, context(nil, { one, two, three }, {
        one = { rank = 'normal', distance = 1, has_own_m08_pre_hit = true },
        two = { rank = 'elite', distance = 2 }, three = { rank = 'boss', distance = 3 },
    }))
    truthy(started.ok, 'A05 creates a field from an explicit point snapshot')
    truthy(find(started.commands, 'apply_modifier', 'C04_M09_FIELD') ~= nil, 'A05 field is self-owned')
    local hit = Skills.confirm_skill_hit(state, started.cast_id, 100, {
        target_id = 'one', target_ref = one, phase = 'initial', hit_key = 'a05-hit', component_key = 'initial', damage_dealt = 1, alive = true,
    })
    truthy(hit.ok, 'A05 accepts an explicit selected initial target')
    truthy(find(hit.commands, 'apply_modifier', 'C04_M08_NET') ~= nil, 'A05 creates private net only after hit confirmation')
    truthy(find(hit.commands, 'apply_modifier', 'C04_M07_SLOW') ~= nil, 'A05 only gives soft limit to normal or elite')
end

do
    local state = Core.new { level = 20, ability_levels = { C04_A05 = 3, C04_A08 = 5 }, passive_levels = { C04_P08 = 5 } }
    fill(state, 'target', 5)
    local target = ref('target')
    local started = Skills.commit_skill(state, 'C04_A08', 5, 300, context(nil, { target }, {
        target = { rank = 'elite', distance = 1, has_own_m08_pre_hit = true },
    }))
    truthy(started.ok, 'A08 accepts the explicit point selection')
    local hit = Skills.confirm_skill_hit(state, started.cast_id, 300, {
        target_id = 'target', target_ref = target, phase = 'initial', hit_key = 'a08-hit', component_key = 'initial', damage_dealt = 1, alive = true,
    })
    truthy(hit.ok, 'A08 commits its two-mark reservation after confirmation')
    local direct = find(hit.commands, 'damage')
    near(direct.coefficient, 2.56, 0.00001, 'A08 uses B plus n times C plus P08')
    truthy(find(hit.commands, 'apply_modifier', 'C04_M10_GARROTE') ~= nil, 'locked A08 target receives private garrote')
end

do
    local state = Core.new { level = 20, ability_levels = { C04_A05 = 1 } }
    fill(state, 'preferred', 5); fill(state, 'first', 5)
    state.combat_epoch_start, state.first_recovery_earliest_tick = 15, 267
    local preferred, first = ref('preferred'), ref('first')
    local cast_context = context(nil, { first, preferred }, {
        first = { rank = 'normal', distance = 1 }, preferred = { rank = 'elite', distance = 5 },
    })
    cast_context.recovery_candidate_target_id = 'preferred'
    local started = Skills.commit_skill(state, 'C04_A05', 1, 292, cast_context)
    truthy(started.ok, 'A05 accepts two locked selected targets')
    local first_hit = Skills.confirm_skill_hit(state, started.cast_id, 292, {
        target_id = 'first', target_ref = first, phase = 'initial', hit_key = 'a05-first', component_key = 'initial',
        damage_dealt = 1, alive = true, hit_time = 292, path_distance = 1,
    })
    local preferred_hit = Skills.confirm_skill_hit(state, started.cast_id, 293, {
        target_id = 'preferred', target_ref = preferred, phase = 'initial', hit_key = 'a05-preferred', component_key = 'initial',
        damage_dealt = 1, alive = true, hit_time = 293, path_distance = 5,
    })
    truthy(first_hit.ok and preferred_hit.ok, 'both selected initial hits settle their own reservations')
    equal(state.ultimate_gauge, 0, 'multi-target recovery stays pending until cast finalization')
    local final = Skills.finalize_cast(state, started.cast_id, 294, 'initial-complete')
    local recovery = find(final.commands, 'hunt_recovery')
    truthy(final.ok and recovery ~= nil, 'cast finalization commits exactly one recovery candidate')
    equal(recovery.target_id, 'preferred', 'frozen recovery candidate wins over earlier fallback hit')
    equal(state.ultimate_gauge, 20, 'the committed candidate contributes exactly one ultimate recovery')
end

do
    local state = Core.new { level = 20, ability_levels = { C04_A04 = 3, C04_A07 = 5 } }
    fill(state, 'boss', 3)
    local target = ref('boss')
    local started = Skills.commit_skill(state, 'C04_A07', 5, 0, context(target))
    truthy(started.ok, 'A07 begins with phase-local reservations')
    for phase = 1, 3 do
        local hit = Skills.confirm_skill_hit(state, started.cast_id, phase * 20, {
            target_id = 'boss', target_ref = target, phase = 'arrow_' .. phase,
            hit_key = 'a07-' .. phase, component_key = 'arrow-' .. phase, damage_dealt = 1, alive = true,
        })
        truthy(hit.ok, 'A07 phase ' .. phase .. ' accepts its own hit')
    end
    equal(Core.hunt_count(state, 'boss'), 0, 'three confirmed phases consume three independent marks')
    local final = Skills.finalize_phase(state, started.cast_id, 3, 147)
    truthy(final.ok, 'last A07 phase has an independent close')
end

do
    local state = Core.new { level = 15, ability_levels = { C04_A03 = 1 }, ultimate_tier = 3 }
    state.ultimate_gauge = 100
    fill(state, 'boss', 5)
    local target = ref('boss')
    local started = Skills.activate_ultimate(state, 0, context(target))
    truthy(started.ok, 'U01 activates only with full gauge and a primary target')
    truthy(Core.active_ultimate(state, 1), 'U01 freezes marks while active')
    state.combat_epoch_start, state.first_recovery_earliest_tick = 0, 0
    local cast = Core.create_cast(state, 'C04_A03', 20, context(target), true)
    Core.reserve_hunt(state, cast.id, 'boss', 2, 20)
    local settled = Core.confirm_reservation(state, cast.id, 'boss', 20)
    equal(state.ultimate_gauge, 0, 'recovery inside U01 does not refill its gauge')
    truthy(settled.recovery and settled.recovery.reverb_coefficient == 0.70, 'tier three converts recovery to limited reverb')
end

print('PASS: ' .. tests .. ' assertions')
