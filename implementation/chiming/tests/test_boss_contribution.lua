package.path = 'implementation/profession_common/lua/?.lua;implementation/chiming/lua/?.lua;' .. package.path

local Core = require 'chiming_core'
local Skills = require 'chiming_skills'
local Ledger = require 'chiming_boss_contribution'
local Controller = require 'chiming_y3_controller'

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
local function find(commands, predicate)
    for _, command in ipairs(commands or {}) do if predicate(command) then return command end end
    return nil
end

local function unit(id)
    local value = { id = id, exists = true, alive = true, attrs = { ['最大生命'] = 100, ['生命'] = 100 }, events = {} }
    function value:get_id() return self.id end
    function value:is_exist() return self.exists end
    function value:is_alive() return self.alive end
    function value:get_level() return 8 end
    function value:get_hp() return self.attrs['生命'] end
    function value:set_hp(amount) self.attrs['生命'] = amount end
    function value:get_attr(name) return self.attrs[name] or 0 end
    function value:set_attr(name, amount) self.attrs[name] = amount end
    function value:add_attr(name, amount) self.attrs[name] = (self.attrs[name] or 0) + amount end
    function value:add_hp(amount) self.attrs['生命'] = self.attrs['生命'] + amount end
    function value:get_owner() return 'ally' end
    function value:get_point() return {} end
    function value:get_facing() return 0 end
    function value:find_ability() return nil end
    function value:find_buff() return nil end
    function value:add_buff()
        local buff = {}
        function buff:set_time() end
        function buff:set_shield() end
        function buff:remove() end
        return buff
    end
    function value:event(name, callback)
        local trigger = { name = name, callback = callback }
        function trigger:remove() self.removed = true end
        self.events[name] = self.events[name] or {}
        self.events[name][#self.events[name] + 1] = trigger
        return trigger
    end
    return value
end

local hero, boss = unit('hero'), unit('boss')

local function state()
    local value = Core.new {
        level = 60, ultimate_tier = 1,
        ability_levels = { C03_A03 = 5, C03_A05 = 5, C03_A08 = 5 },
        passive_levels = { C03_P07 = 5 },
    }
    value.lifecycle_id = 1
    return value
end

local function hit(cast_id, skill_phase)
    return {
        cast_id = cast_id, lifecycle_id = 1, phase = skill_phase, target_id = 'boss', target = boss,
        damage_dealt = 1, hit_time = 0.1, path_distance = 1, target_rank = 'boss', alive = true,
    }
end

do
    local value = state()
    Core.set_seals(value, 3, 'earned')
    local cast = Skills.commit_skill(value, 'C03_A08', 5, 0, {
        actor_id = 'hero', lifecycle_id = 1, unit_id = 'hero', cast_point = { id = 'point' }, target_point = { id = 'point' },
        target_refs_by_id = { boss = boss },
    })
    truthy(cast.ok, 'A08 commit: ' .. tostring(cast.error))
    local result = Skills.confirm_skill_hit(value, cast.cast_id, 0.1, {
        lifecycle_id = 1, unit_id = 'hero', target_refs_by_id = { boss = boss },
        target_meta_by_id = { boss = { rank = 'boss', private_luyin = true } }, hit_events = { hit(cast.cast_id, 'impact') },
    })
    truthy(result.ok, 'A08 confirmation: ' .. tostring(result.error))
    local impact = find(result.commands, function(command) return command.break_event_key == 'a08-impact' end)
    local marked = find(result.commands, function(command) return command.break_event_key == 'a08-luyin' end)
    local passive = find(result.commands, function(command) return command.break_event_key == 'a08-p07' end)
    near(impact.break_value + marked.break_value + passive.break_value, 3.0, 0.00001, 'A08 initial, M06, and P07 break total is capped at 3.0')
    equal(#result.commands > 0, true, 'A08 emits its normal command sequence')
end

do
    local value = state()
    Core.set_seals(value, 1, 'earned')
    local cast = Skills.commit_skill(value, 'C03_A05', 5, 0, {
        actor_id = 'hero', lifecycle_id = 1, cast_point = { id = 'point' }, target_point = { id = 'point' }, target_refs_by_id = { boss = boss },
    })
    local result = Skills.confirm_skill_hit(value, cast.cast_id, 0.1, {
        lifecycle_id = 1, target_refs_by_id = { boss = boss }, hit_events = { hit(cast.cast_id, 'impact') },
    })
    local pulse_count = 0
    for _, command in ipairs(result.commands) do
        if command.pulse_key == 'C03_A05' then
            pulse_count = pulse_count + 1
            equal(command.break_scope, 'boss_only', 'A05 pulse break has an explicit boss-only scope')
            equal(command.break_value, 0.2, 'A05 pulse break is one quarter of its base break')
        end
    end
    equal(pulse_count, 3, 'A05 creates three independently keyed pulse breaks')
end

do
    local ledger = Ledger.new()
    local common = { boss_instance_id = 'boss-1', phase_id = 'p1', actor_id = 'hero', lifecycle_id = 1, target_id = 'boss' }
    truthy(ledger:accept({ kind = 'final_damage', event_id = 'damage-1', skill_key = 'C03_A03', value = 10,
        boss_instance_id = common.boss_instance_id, phase_id = common.phase_id, actor_id = common.actor_id,
        lifecycle_id = common.lifecycle_id, target_id = common.target_id }), 'final damage contribution is accepted')
    truthy(ledger:accept({ kind = 'actual_break', event_id = 'break-1', skill_key = 'C03_A08', value = 3.0,
        boss_instance_id = common.boss_instance_id, phase_id = common.phase_id, actor_id = common.actor_id,
        lifecycle_id = common.lifecycle_id, target_id = common.target_id }), 'actual break contribution is accepted')
    truthy(ledger:accept({ kind = 'actual_protection', event_id = 'guard-1', skill_key = 'C03_A04', value = 5,
        boss_instance_id = common.boss_instance_id, phase_id = common.phase_id, actor_id = common.actor_id,
        lifecycle_id = common.lifecycle_id, target_id = common.target_id }), 'actual protection contribution is accepted')
    truthy(ledger:accept({ kind = 'purge_mechanic', event_id = 'purge-1', skill_key = 'C03_A08', mechanic_id = 'drowning',
        alternative_resolution = 'dodge', boss_instance_id = common.boss_instance_id, phase_id = common.phase_id,
        actor_id = common.actor_id, lifecycle_id = common.lifecycle_id, target_id = common.target_id }), 'purge contribution is accepted')
    local duplicate, duplicate_reason = ledger:accept({ kind = 'final_damage', event_id = 'damage-1', skill_key = 'C03_A03', value = 10,
        boss_instance_id = common.boss_instance_id, phase_id = common.phase_id, actor_id = common.actor_id,
        lifecycle_id = common.lifecycle_id, target_id = common.target_id })
    truthy(not duplicate and duplicate_reason == 'duplicate-contribution-event', 'phase event ID deduplicates public reward data')
    local missing, missing_reason = ledger:accept({ kind = 'actual_break', event_id = 'missing', skill_key = 'C03_A08', value = 1,
        phase_id = 'p1', actor_id = 'hero', lifecycle_id = 1, target_id = 'boss' })
    truthy(not missing and missing_reason == 'missing-contribution-field:boss_instance_id', 'missing schema fields are rejected')
end

_G.y3 = {
    game = { current_game_run_time = function() return 0 end },
    timer = {
        wait = function(_, callback) local timer = { callback = callback }; function timer:remove() self.removed = true end; return timer end,
        loop = function(_, callback) local timer = { callback = callback }; function timer:remove() self.removed = true end; return timer end,
    },
    const = { UnitEnumState = { ['无敌'] = 1, ['禁止移动'] = 2 } },
    shape = { create_circular_shape = function() return {} end, create_rectangle_shape = function() return {} end, create_sector_shape = function() return {} end },
    point = { get_point_offset_vector = function(point) return point end },
    selector = { create = function()
        local selector = {}
        function selector:in_shape() return self end; function selector:in_range() return self end; function selector:is_enemy() return self end
        function selector:is_ally() return self end; function selector:not_in_state() return self end; function selector:without_tag() return self end
        function selector:pick() return {} end
        return selector
    end },
}

do
    local reports = {}
    local controller = Controller.new { report_boss_contribution = function(item) reports[#reports + 1] = item end }
    controller:register('hero', hero, { ability_levels = { C03_A03 = 1 }, now = 0 })
    local lifecycle_id = controller.registrations.hero.lifecycle_id
    local accepted = controller:_report_boss_contribution({
        kind = 'final_damage', event_id = 'controller-valid', skill_key = 'C03_A03', value = 2,
        boss_instance_id = 'boss-1', phase_id = 'p1', actor_id = 'hero', lifecycle_id = lifecycle_id, target_id = 'boss',
    })
    truthy(accepted, 'controller forwards a valid current-lifecycle contribution')
    local stale, reason = controller:_report_boss_contribution({
        kind = 'final_damage', event_id = 'controller-stale', skill_key = 'C03_A03', value = 2,
        boss_instance_id = 'boss-1', phase_id = 'p1', actor_id = 'hero', lifecycle_id = lifecycle_id - 1, target_id = 'boss',
    })
    truthy(not stale and reason == 'stale-contribution-lifecycle', 'old lifecycle contribution is ignored')
    equal(#reports, 1, 'rejected contribution never reaches public reward reporting')
    controller:remove('hero')
end

print('PASS: ' .. tests .. ' boss contribution assertions')
