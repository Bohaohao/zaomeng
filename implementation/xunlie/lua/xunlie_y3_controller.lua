-- Actor-scoped Y3 controller. It owns registration, lifecycle invalidation and
-- public-Boss contribution admission; map-specific hit wiring remains gated.
local Runtime = require 'xunlie_runtime'
local Y3Adapter = require 'xunlie_y3_adapter'
local Y3Targeting = require 'xunlie_y3_targeting'
local BossContribution = require 'xunlie_boss_contribution'

local M = {}
local Controller = {}
Controller.__index = Controller

local function append(list, value)
    list[#list + 1] = value
end

local function now()
    return y3.game.current_game_run_time()
end

local function add_trigger(registration, trigger)
    registration.triggers[#registration.triggers + 1] = trigger
end

local function active(controller, actor_id, registration, lifecycle_id)
    return controller.registrations[actor_id] == registration
        and registration.lifecycle_id == lifecycle_id
end

local function add_unit_context(registration, context)
    context = context or {}
    context.lifecycle_id = context.lifecycle_id == nil and registration.lifecycle_id or context.lifecycle_id
    context.unit = context.unit or registration.unit
    context.source_unit = context.source_unit or registration.unit
    context.unit_id = context.unit_id or registration.unit:get_id()
    context.source_unit_id = context.source_unit_id or registration.unit:get_id()
    context.combat_scope = context.combat_scope or registration.session.combat_scope
    if context.combat_scope == 'private_session' then
        context.session_instance_id = context.session_instance_id or registration.session.session_instance_id
        context.session_epoch = context.session_epoch or registration.session.session_epoch
    end
    return context
end

local function bind_cast_session(registration, context)
    context.combat_scope = registration.session.combat_scope
    context.session_instance_id = registration.session.session_instance_id
    context.session_epoch = registration.session.session_epoch
    return add_unit_context(registration, context)
end

function M.new(options)
    options = options or {}
    local units = {}
    options.unit_by_actor = options.unit_by_actor or function(actor_id) return units[actor_id] end
    local adapter = options.adapter or Y3Adapter.new(options)
    local targeting = options.targeting or Y3Targeting.new(options)
    local controller = setmetatable({
        options = options, adapter = adapter, targeting = targeting, runtime = Runtime.new(adapter),
        units = units, registrations = {}, next_lifecycle_id = 0,
        contribution_ledger = BossContribution.new(),
    }, Controller)
    if type(adapter.set_lifecycle_resolver) == 'function' then
        adapter:set_lifecycle_resolver(function(actor_id, lifecycle_id)
            local registration = controller.registrations[actor_id]
            return registration ~= nil and registration.lifecycle_id == lifecycle_id
        end)
    end
    if adapter.options then
        adapter.options.resolve_pulse_context = function(actor_id, command, context)
            local registration = controller.registrations[actor_id]
            if not registration or registration.lifecycle_id ~= context.lifecycle_id then return nil end
            return targeting:build_pulse_context(actor_id, command, registration.unit, context)
        end
        adapter.options.on_move_finished = function(actor_id, cast_id, context)
            local registration = controller.registrations[actor_id]
            if not registration or registration.lifecycle_id ~= context.lifecycle_id then return end
            controller:confirm_safe_landing(actor_id, cast_id, add_unit_context(registration, { lifecycle_id = context.lifecycle_id }))
        end
    end
    return controller
end

function Controller:_report_boss_hit(actor_id, registration, result, event)
    local snapshot = event and event.encounter_snapshot
    if not result.ok or not snapshot or event.target_rank ~= 'boss' then return false end
    if type(event.final_damage_event_id) ~= 'string' or event.final_damage_event_id == '' then return false end
    if type(event.damage_dealt) ~= 'number' or event.damage_dealt <= 0 then return false end
    local item = {
        kind = 'final_damage', event_id = event.final_damage_event_id,
        actor_id = actor_id, lifecycle_id = registration.lifecycle_id,
        boss_instance_id = snapshot.boss_instance_id, phase_id = snapshot.phase_id,
        target_id = snapshot.target_id, target_lifecycle_id = snapshot.target_lifecycle_id,
        skill_key = result.skill_key, value = event.damage_dealt,
        combat_scope = 'public', session_instance_id = nil, session_epoch = nil,
    }
    local accepted, error_code = self.contribution_ledger:accept(item)
    if not accepted then
        if type(self.options.on_contribution_rejected) == 'function' then self.options.on_contribution_rejected(item, error_code) end
        return false, error_code
    end
    if type(self.options.report_boss_contribution) == 'function' then self.options.report_boss_contribution(item) end
    return true
end

function Controller:_start_tick(registration, actor_id)
    if registration.timer then registration.timer:remove() end
    local lifecycle_id = registration.lifecycle_id
    registration.timer = y3.timer.loop(0.05, function()
        if active(self, actor_id, registration, lifecycle_id) then
            self.runtime:tick(actor_id, now(), add_unit_context(registration, { lifecycle_id = lifecycle_id }))
        end
    end, 'Xunlie runtime tick')
end

function Controller:register(actor_id, unit, state_options)
    if self.registrations[actor_id] then self:remove(actor_id, 're-register') end
    state_options = state_options or {}
    self.next_lifecycle_id = self.next_lifecycle_id + 1
    local lifecycle_id = self.next_lifecycle_id
    local session = {
        combat_scope = state_options.combat_scope or 'public',
        session_instance_id = state_options.session_instance_id,
        session_epoch = state_options.session_epoch,
    }
    if session.combat_scope == 'public' then session.session_instance_id, session.session_epoch = nil, nil end
    local registration = { unit = unit, lifecycle_id = lifecycle_id, session = session, triggers = {} }
    self.registrations[actor_id], self.units[actor_id] = registration, unit
    state_options.lifecycle_id, state_options.combat_scope = lifecycle_id, session.combat_scope
    state_options.session_instance_id, state_options.session_epoch = session.session_instance_id, session.session_epoch
    state_options.context = add_unit_context(registration, state_options.context or {})
    self.runtime:register(actor_id, state_options)
    self:_start_tick(registration, actor_id)

    local bound_lifecycle = lifecycle_id
    add_trigger(registration, unit:event('单位-升级', function()
        if active(self, actor_id, registration, bound_lifecycle) then
            self.runtime:set_level(actor_id, unit:get_level(), add_unit_context(registration, { lifecycle_id = bound_lifecycle }))
        end
    end))
    add_trigger(registration, unit:event('单位-死亡', function()
        if active(self, actor_id, registration, bound_lifecycle) then self:invalidate_lifecycle(actor_id, 'death') end
    end))
    add_trigger(registration, unit:event('单位-造成伤害后', function(_, event_data)
        if active(self, actor_id, registration, bound_lifecycle) and type(self.options.on_damage_event) == 'function' then
            self.options.on_damage_event(actor_id, event_data, registration)
        end
    end))
    return registration
end

function Controller:begin_cast(actor_id, skill_key, rank, event_data)
    local registration = self.registrations[actor_id]
    if not registration then return { ok = false, error = 'unknown-actor', commands = {} } end
    local context = self.targeting:build_context(self.runtime, actor_id, skill_key, rank, registration.unit, nil, event_data)
    context = bind_cast_session(registration, context)
    if context.cast_error then return { ok = false, error = context.cast_error, commands = {} } end
    return self.runtime:begin_cast(actor_id, skill_key, rank, now(), context)
end

function Controller:begin_normal_attack(actor_id, context)
    local registration = self.registrations[actor_id]
    if not registration then return { ok = false, error = 'unknown-actor', commands = {} } end
    return self.runtime:begin_normal_attack(actor_id, now(), add_unit_context(registration, context))
end

local function valid_event_source(registration, event)
    if event.source_unit_id ~= nil and event.source_unit_id ~= registration.unit:get_id() then return false end
    if event.source_unit_ref ~= nil and event.source_unit_ref ~= registration.unit then return false end
    return true
end

function Controller:confirm_skill_hit(actor_id, cast_id, event, context)
    local registration = self.registrations[actor_id]
    if not registration then return { ok = false, error = 'unknown-actor', commands = {} } end
    if not valid_event_source(registration, event or {}) then return { ok = false, error = 'stale-source-unit', commands = {} } end
    context = add_unit_context(registration, context or {})
    local result = self.runtime:confirm_skill_hit(actor_id, cast_id, now(), event, context)
    if result.ok then self:_report_boss_hit(actor_id, registration, result, event) end
    return result
end

function Controller:confirm_hit(actor_id, cast_id, event, context)
    return self:confirm_skill_hit(actor_id, cast_id, event, context)
end

function Controller:confirm_normal_attack(actor_id, cast_id, event, context)
    local registration = self.registrations[actor_id]
    if not registration then return { ok = false, error = 'unknown-actor', commands = {} } end
    if not valid_event_source(registration, event or {}) then return { ok = false, error = 'stale-source-unit', commands = {} } end
    return self.runtime:confirm_normal_attack(actor_id, cast_id, now(), event, add_unit_context(registration, context or {}))
end

function Controller:confirm_safe_landing(actor_id, cast_id, context)
    local registration = self.registrations[actor_id]
    if not registration then return { ok = false, error = 'unknown-actor', commands = {} } end
    return self.runtime:confirm_safe_landing(actor_id, cast_id, now(), add_unit_context(registration, context or {}))
end

function Controller:finalize_phase(actor_id, cast_id, phase, context)
    local registration = self.registrations[actor_id]
    if not registration then return { ok = false, error = 'unknown-actor', commands = {} } end
    return self.runtime:finalize_phase(actor_id, cast_id, phase, now(), add_unit_context(registration, context or {}))
end

function Controller:finalize_cast(actor_id, cast_id, reason, context)
    local registration = self.registrations[actor_id]
    if not registration then return { ok = false, error = 'unknown-actor', commands = {} } end
    return self.runtime:finalize_cast(actor_id, cast_id, now(), reason, add_unit_context(registration, context or {}))
end

function Controller:activate_ultimate(actor_id, event_data)
    local registration = self.registrations[actor_id]
    if not registration then return { ok = false, error = 'unknown-actor', commands = {} } end
    local context = self.targeting:build_context(self.runtime, actor_id, 'C04_U01', 1, registration.unit, nil, event_data)
    context = bind_cast_session(registration, context)
    if context.cast_error then return { ok = false, error = context.cast_error, commands = {} } end
    return self.runtime:activate_ultimate(actor_id, now(), context)
end

function Controller:invalidate_lifecycle(actor_id, reason)
    local registration = self.registrations[actor_id]
    if not registration then return false, 'unknown-actor' end
    local previous = registration.lifecycle_id
    if type(self.adapter.cancel_actor_timers) == 'function' then self.adapter:cancel_actor_timers(actor_id, previous) end
    self.next_lifecycle_id = self.next_lifecycle_id + 1
    local next_lifecycle = self.next_lifecycle_id
    local cleared, error_code = self.runtime:invalidate_lifecycle(actor_id, next_lifecycle, now(), reason)
    if not cleared then return false, error_code end
    registration.lifecycle_id = next_lifecycle
    self:_start_tick(registration, actor_id)
    return true, next_lifecycle
end

function Controller:remove(actor_id, reason)
    local registration = self.registrations[actor_id]
    if not registration then return false, 'unknown-actor' end
    self:invalidate_lifecycle(actor_id, reason or 'remove')
    self.registrations[actor_id] = nil
    if registration.timer then registration.timer:remove() end
    for _, trigger in ipairs(registration.triggers) do trigger:remove() end
    if type(self.adapter.cancel_actor_timers) == 'function' then self.adapter:cancel_actor_timers(actor_id) end
    self.runtime:remove(actor_id)
    self.units[actor_id] = nil
    return true
end

return M
