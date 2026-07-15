package.path = 'implementation/profession_common/lua/?.lua;implementation/xunlie/lua/?.lua;' .. package.path

local Adapter = require 'xunlie_y3_adapter'
local Controller = require 'xunlie_y3_controller'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local scheduled, loops = {}, {}
local time = 0
_G.y3 = {
    game = { current_game_run_time = function() return time end },
    timer = {
        wait = function(delay, callback) local timer = { delay = delay, callback = callback }; function timer:remove() self.removed = true end; scheduled[#scheduled + 1] = timer; return timer end,
        loop = function(delay, callback) local timer = { delay = delay, callback = callback }; function timer:remove() self.removed = true end; loops[#loops + 1] = timer; return timer end,
    },
}

local function unit(id)
    local value = { id = id, exists = true, level = 8, events = {}, attrs = { ['最大生命'] = 100, ['生命'] = 100 } }
    function value:get_id() return self.id end
    function value:is_exist() return self.exists end
    function value:get_level() return self.level end
    function value:get_attr(key) return self.attrs[key] or 0 end
    function value:set_attr(key, amount) self.attrs[key] = amount end
    function value:add_attr(key, amount) self.attrs[key] = (self.attrs[key] or 0) + amount end
    function value:set_hp(amount) self.attrs['生命'] = amount end
    function value:add_hp(amount) self.attrs['生命'] = self.attrs['生命'] + amount end
    function value:find_ability() return nil end
    function value:add_buff(data) local buff = { key = data.key }; function buff:remove() end; return buff end
    function value:damage() end
    function value:mover_line(data) if data.on_finish then data.on_finish() end end
    function value:event(_, callback)
        local trigger = { callback = callback }
        function trigger:remove() self.removed = true end
        value.events[#value.events + 1] = trigger
        return trigger
    end
    return value
end

do
    local old, fresh = unit('old'), unit('fresh')
    local current = old
    local adapter = Adapter.new { unit_by_actor = function() return current end }
    local controller = Controller.new { adapter = adapter, targeting = { build_context = function() return {} end } }
    controller:register('actor', old, { ability_levels = { C04_A03 = 1 } })
    local old_registration = controller.registrations.actor
    local old_lifecycle = old_registration.lifecycle_id
    local old_loop, old_events = old_registration.timer, old.events
    truthy(controller:remove('actor'), 'remove clears the registration')
    truthy(old_loop.removed, 'remove stops the actor loop')
    for _, trigger in ipairs(old_events) do truthy(trigger.removed, 'remove unregisters every unit trigger') end

    current = fresh
    controller:register('actor', fresh, { ability_levels = { C04_A03 = 1 } })
    local fresh_lifecycle = controller.registrations.actor.lifecycle_id
    old_events[2].callback()
    equal(controller.registrations.actor.lifecycle_id, fresh_lifecycle, 'old unit death callback cannot invalidate the re-registered actor')
    old_loop.callback()
    equal(controller.registrations.actor.lifecycle_id, fresh_lifecycle, 'old loop callback is inert after actor reuse')
    local stale = controller:confirm_skill_hit('actor', 999, {
        lifecycle_id = old_lifecycle, combat_scope = 'public', source_unit_id = 'fresh',
        target_id = 'target', hit_key = 'late', component_key = 'late', damage_dealt = 1, alive = true,
    }, { lifecycle_id = old_lifecycle })
    truthy(not stale.ok, 'old lifecycle hit is rejected')
    equal(stale.error, 'stale-lifecycle', 'old lifecycle reports the lifecycle mismatch')
end

do
    local actor = unit('timed')
    local adapter = Adapter.new { unit_by_actor = function() return actor end, modifier_ids = { C04_M05_WIND = 5005 } }
    local life = 1
    adapter:set_lifecycle_resolver(function(_, lifecycle_id) return lifecycle_id == life end)
    adapter:apply_effect('actor', {
        type = 'apply_modifier', key = 'C04_M05_WIND', target_scope = 'self', duration = 120, payload = { move_speed = 0.1 },
    }, { unit = actor, lifecycle_id = 1, now = 0 })
    local old_timer = scheduled[#scheduled]
    adapter:cancel_actor_timers('actor', 1)
    truthy(old_timer.removed, 'lifecycle invalidation cancels deferred effect cleanup')
    life = 2
    adapter:apply_effect('actor', {
        type = 'apply_modifier', key = 'C04_M05_WIND', target_scope = 'self', duration = 120, payload = { move_speed = 0.2 },
    }, { unit = actor, lifecycle_id = 2, now = 0 })
    local new_timer = scheduled[#scheduled]
    old_timer.callback()
    equal(actor.attrs['移动速度'], 20, 'old cleanup cannot remove the new lifecycle effect')
    new_timer.callback()
    equal(actor.attrs['移动速度'], 0, 'current lifecycle cleanup still removes its own effect')
end

print('PASS: ' .. tests .. ' bridge lifecycle assertions')
