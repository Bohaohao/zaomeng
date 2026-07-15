package.path = 'implementation/profession_common/lua/?.lua;implementation/xunlie/lua/?.lua;' .. package.path

local Adapter = require 'xunlie_y3_adapter'
local Targeting = require 'xunlie_y3_targeting'
local Runtime = require 'xunlie_runtime'
local Contract = require 'xunlie_adapter_contract'
local Core = require 'xunlie_core'

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

local timers = {}
_G.y3 = {
    game = { current_game_run_time = function() return 0 end },
    timer = {
        wait = function(delay, callback) local timer = { delay = delay, callback = callback }; function timer:remove() self.removed = true end; timers[#timers + 1] = timer; return timer end,
        loop = function(delay, callback) local timer = { delay = delay, callback = callback }; function timer:remove() self.removed = true end; timers[#timers + 1] = timer; return timer end,
    },
}

local function unit(id)
    local value = { id = id, exists = true, attrs = { ['最大生命'] = 100, ['生命'] = 100 }, buffs = {}, damage_calls = {} }
    function value:get_id() return self.id end
    function value:is_exist() return self.exists end
    function value:get_owner() return 'owner' end
    function value:get_facing() return 0 end
    function value:get_attr(key) return self.attrs[key] or 0 end
    function value:set_attr(key, amount) self.attrs[key] = amount end
    function value:add_attr(key, amount) self.attrs[key] = (self.attrs[key] or 0) + amount end
    function value:set_hp(amount) self.attrs['生命'] = amount end
    function value:add_hp(amount) self.attrs['生命'] = self.attrs['生命'] + amount end
    function value:find_ability() return nil end
    function value:damage(data) self.damage_calls[#self.damage_calls + 1] = data end
    function value:add_buff(data)
        local buff = { key = data.key, time = data.time }
        function buff:remove() value.buffs[self.key] = nil end
        function buff:set_time(time) self.time = time end
        value.buffs[data.key] = buff
        return buff
    end
    function value:mover_line(data) self.mover = data; if data.on_finish then data.on_finish() end end
    return value
end

local hero, enemy, unknown = unit('hero'), unit('enemy'), unit('unknown')
hero.attrs['物理攻击'] = 50
local units = { actor = hero }
local adapter = Adapter.new {
    unit_by_actor = function(actor_id) return units[actor_id] end,
    modifier_ids = { C04_M05_WIND = 5005, C04_M07_SLOW = 5007, C04_M08_NET = 5008 },
}

do
    adapter:apply_effect('actor', {
        type = 'apply_modifier', key = 'C04_M05_WIND', target_scope = 'self', duration = 120,
        payload = { move_speed = 0.10 },
    }, { unit = hero, now = 0 })
    near(hero.attrs['移动速度'], 10, 0.00001, 'self wind only changes the caster')
    equal(enemy.attrs['移动速度'] or 0, 0, 'self wind never falls through to a selected enemy')
end

do
    adapter:apply_effect('actor', {
        type = 'apply_modifier', key = 'C04_M07_SLOW', target_scope = 'explicit', target_id = 'unknown', target = unknown,
        payload = { slow = 0.4 }, duration = 72,
    }, { unit = hero, target_refs_by_id = { unknown = unknown }, target_meta_by_id = { unknown = { rank = 'unknown' } }, now = 0 })
    equal(unknown.attrs['移动速度'] or 0, 0, 'unknown rank never receives the soft limit')
    adapter:apply_effect('actor', {
        type = 'apply_modifier', key = 'C04_M07_SLOW', target_scope = 'explicit', target_id = 'enemy', target = enemy,
        payload = { slow = 0.4 }, duration = 72,
    }, { unit = hero, target_refs_by_id = { enemy = enemy }, target_meta_by_id = { enemy = { rank = 'elite' } }, now = 0 })
    near(enemy.attrs['移动速度'], -40, 0.00001, 'normal or elite soft limit applies its explicit target value')
end

do
    local targeting = Targeting.new {}
    local rejected = targeting:build_context(nil, 'actor', 'C04_A03', 1, hero, nil, {})
    equal(rejected.cast_error, 'primary-target-required', 'A03 never substitutes a generic candidate for primary')
    local point_rejected = targeting:build_context(nil, 'actor', 'C04_A05', 1, hero, nil, {})
    equal(point_rejected.cast_error, 'cast-point-required', 'A05 refuses without a synchronized point')
end

do
    local targeting = Targeting.new {
        resolve_cast_point = function() return { x = 1, y = 1 } end,
        resolve_selected_targets = function() return { enemy } end,
        target_rank = function() return 'elite' end,
    }
    local runtime = { get_effect = function() return nil end }
    local built = targeting:build_context(runtime, 'actor', 'C04_A05', 1, hero, nil, {})
    equal(built.selected_target_ids[1], 'enemy', 'A05 records an explicit selected snapshot')
    equal(built.primary_target_id, nil, 'A05 does not invent a primary target from selected')
    equal(built.target_meta_by_id.enemy.rank, 'elite', 'target rank belongs to the selected snapshot')
end

do
    local close, marked, far = unit('close'), unit('marked'), unit('far')
    close.distance, marked.distance, far.distance = 1, 3, 2
    local state = Core.new { level = 8, ability_levels = { C04_A05 = 1 } }
    for tick = 1, 4 do Core.gain_hunt(state, 'marked', tick, 'C04_A01') end
    local resolver_limit
    local targeting = Targeting.new {
        resolve_cast_point = function() return { x = 1, y = 1 } end,
        resolve_selected_targets = function(_, _, _, _, _, _, limit)
            resolver_limit = limit
            return { close, marked, far }
        end,
        target_rank = function() return 'elite' end,
        target_distance = function(_, target) return target.distance end,
    }
    local runtime = {
        get_effect = function() return nil end,
        get_state = function() return state end,
    }
    local built = targeting:build_context(runtime, 'actor', 'C04_A05', 1, hero, nil, {})
    equal(resolver_limit, nil, 'bridge captures legal candidates before applying the private mark priority')
    equal(built.selected_target_ids[1], 'marked', 'A05 selection prefers the actor\'s highest private mark count')
    equal(built.selected_target_ids[2], 'close', 'A05 ties resolve by distance after private marks')
end

do
    local calls = {}
    local fake = {}
    for _, name in ipairs(Contract.required_methods()) do
        fake[name] = function(_, actor_id, command) calls[#calls + 1] = { actor_id = actor_id, command = command } end
    end
    local runtime = Runtime.new(fake)
    runtime:register('one', { level = 8, lifecycle_id = 1, ability_levels = { C04_A03 = 1 }, context = { unit = hero } })
    runtime:register('two', { level = 8, lifecycle_id = 2, ability_levels = { C04_A03 = 1 }, context = { unit = enemy } })
    local first = runtime:commit_skill('one', 'C04_A03', 1, 0, {
        actor_id = 'one', lifecycle_id = 1, combat_scope = 'public', primary_target_id = 'enemy', primary_target_ref = enemy,
        target_refs_by_id = { enemy = enemy },
    })
    truthy(not first.ok and first.error == 'insufficient-hunt-marks', 'state is private and cannot borrow marks from another actor')
    truthy(#calls >= 2, 'register operations dispatch through the shared adapter contract')
end

print('PASS: ' .. tests .. ' bridge targeting assertions')
