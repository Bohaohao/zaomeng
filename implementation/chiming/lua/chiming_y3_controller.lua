-- custom-built: actor-scoped Y3 event registration for C03. Old callbacks are
-- made inert before a same actor_id can be registered again.
local Runtime = require 'chiming_runtime'
local Y3Adapter = require 'chiming_y3_adapter'
local Y3Targeting = require 'chiming_y3_targeting'
local BossContribution = require 'chiming_boss_contribution'

local M = {}
local Controller = {}
Controller.__index = Controller

function M.new(options)
    options = options or {}
    local units = {}
    options.unit_by_actor = options.unit_by_actor or function(actor_id) return units[actor_id] end
    local adapter = options.adapter or Y3Adapter.new(options)
    local targeting = options.targeting or Y3Targeting.new(options)
    local controller = setmetatable({
        options = options, adapter = adapter, runtime = Runtime.new(adapter), targeting = targeting,
        units = units, registrations = {}, next_lifecycle_id = 0,
        contribution_ledger = BossContribution.new(),
    }, Controller)
    if type(adapter.set_lifecycle_resolver) == 'function' then
        adapter:set_lifecycle_resolver(function(actor_id, lifecycle_id)
            local registration = controller.registrations[actor_id]
            return registration ~= nil and registration.lifecycle_id == lifecycle_id
        end)
    end
    if type(adapter.set_contribution_sink) == 'function' then
        adapter:set_contribution_sink(function(item)
            controller:_report_boss_contribution(item)
        end)
    end
    return controller
end

local function now()
    return y3.game.current_game_run_time()
end

local function add_trigger(registration, trigger)
    registration.triggers[#registration.triggers + 1] = trigger
    return trigger
end

local function active(controller, actor_id, registration)
    return controller.registrations[actor_id] == registration
end

local function active_context(controller, actor_id, context, require_lifecycle_id)
    local registration = controller.registrations[actor_id]
    if not registration then return nil, 'unknown-actor' end
    context = context or {}
    if require_lifecycle_id and context.lifecycle_id == nil then return nil, 'lifecycle-id-required' end
    if context.lifecycle_id ~= nil and context.lifecycle_id ~= registration.lifecycle_id then return nil, 'stale-lifecycle' end
    context.lifecycle_id = registration.lifecycle_id
    context.unit = context.unit or registration.unit
    return context
end

function Controller:_report_boss_contribution(item)
    if type(item) ~= 'table' then return false, 'invalid-contribution' end
    local registration = self.registrations[item.actor_id]
    if not registration then return false, 'unknown-contribution-actor' end
    if registration.lifecycle_id ~= item.lifecycle_id then return false, 'stale-contribution-lifecycle' end
    local accepted, error_code = self.contribution_ledger:accept(item)
    if not accepted then
        if type(self.options.on_contribution_rejected) == 'function' then
            self.options.on_contribution_rejected(item, error_code)
        end
        return false, error_code
    end
    if type(self.options.report_boss_contribution) == 'function' then
        self.options.report_boss_contribution(item)
    end
    return true
end

local function report_context(controller, actor_id, registration, context)
    for _, item in ipairs(context.boss_contributions or {}) do
        local report = {}
        for key, value in pairs(item) do report[key] = value end
        report.actor_id = actor_id
        report.lifecycle_id = registration.lifecycle_id
        controller:_report_boss_contribution(report)
    end
end

function Controller:register(actor_id, unit, state_options)
    if self.registrations[actor_id] then self:remove(actor_id, 're-register') end
    state_options = state_options or {}
    state_options.level = state_options.level or unit:get_level()
    state_options.now = state_options.now or now()
    self.next_lifecycle_id = self.next_lifecycle_id + 1
    local registration = { unit = unit, triggers = {}, lifecycle_id = self.next_lifecycle_id }
    self.units[actor_id], self.registrations[actor_id] = unit, registration
    state_options.lifecycle_id = registration.lifecycle_id
    state_options.context = state_options.context or { unit = unit }
    state_options.context.unit = unit
    state_options.context.lifecycle_id = registration.lifecycle_id
    local ok, state_or_error = pcall(function() return self.runtime:register(actor_id, state_options) end)
    if not ok then
        self.registrations[actor_id], self.units[actor_id] = nil, nil
        error(state_or_error)
    end

    registration.timer = y3.timer.loop(0.1, function()
        if not active(self, actor_id, registration) or not unit:is_exist() then return end
        self.runtime:set_health(actor_id, unit:get_hp())
        self.runtime:tick(actor_id, now(), { unit = unit, lifecycle_id = registration.lifecycle_id })
    end, 'Chiming runtime tick')

    add_trigger(registration, unit:event('单位-受到伤害后', function(_, data)
        if not active(self, actor_id, registration) or not unit:is_exist() then return end
        local context = {
            now = now(), unit = unit, source_unit = data.source_unit, target_unit = data.target_unit,
            target = data.source_unit, damage = data.damage, current_hp = unit:get_hp(),
            lifecycle_id = registration.lifecycle_id, unit_id = unit:get_id(),
        }
        if type(self.options.classify_effective_protection) == 'function' then
            local result = self.options.classify_effective_protection(actor_id, unit, data, context) or {}
            context.protection_qualification = result
            if result.actual_protection and result.boss_contribution then
                context.boss_contributions = { result.boss_contribution }
            end
        end
        self.runtime:on_damage_taken(actor_id, context.now, context)
        report_context(self, actor_id, registration, context)
    end))

    add_trigger(registration, unit:event('单位-造成伤害后', function(_, data)
        if not active(self, actor_id, registration) or not unit:is_exist() or not data.target_unit
            or type(data.damage) ~= 'number' or data.damage <= 0 then return end
        if type(self.options.resolve_boss_context) ~= 'function' then return end
        local boss = self.options.resolve_boss_context(data.target_unit, data, { actor_id = actor_id, lifecycle_id = registration.lifecycle_id })
        if boss and boss.boss_instance_id and boss.phase_id and boss.event_id then
            self:_report_boss_contribution({
                kind = 'final_damage', boss_instance_id = boss.boss_instance_id, phase_id = boss.phase_id,
                actor_id = actor_id, lifecycle_id = registration.lifecycle_id, target_id = data.target_unit:get_id(),
                skill_key = data.ability and self.options.skill_by_y3_id and self.options.skill_by_y3_id[data.ability:get_key()] or nil,
                event_id = boss.event_id, value = data.damage,
            })
        end
    end))

    add_trigger(registration, unit:event('单位-升级', function()
        if not active(self, actor_id, registration) or not unit:is_exist() then return end
        self.runtime:set_level(actor_id, unit:get_level(), { unit = unit, now = now(), lifecycle_id = registration.lifecycle_id })
    end))

    add_trigger(registration, unit:event('单位-死亡', function()
        if active(self, actor_id, registration) then self:invalidate_lifecycle(actor_id, 'death') end
    end))

    if self.options.skill_by_y3_id then
        add_trigger(registration, unit:event('单位-施放技能', function(_, data)
            if not active(self, actor_id, registration) or not unit:is_exist() then return end
            local ability = data.ability
            local skill_key = ability and self.options.skill_by_y3_id[ability:get_key()]
            if not skill_key then return end
            local context
            if type(self.options.resolve_cast_context) == 'function' then
                context = self.options.resolve_cast_context(actor_id, unit, ability, data) or {}
            else
                context = self.targeting:build_context(self.runtime, actor_id, skill_key, ability:get_level(), unit, ability, data)
            end
            context.unit, context.ability, context.skill_key, context.lifecycle_id = unit, ability, skill_key, registration.lifecycle_id
            if context.cast_error or (self.targeting:requires_cast_point(skill_key) and not context.target_point) then
                if type(self.options.on_cast_rejected) == 'function' then
                    self.options.on_cast_rejected(actor_id, skill_key, context.cast_error or 'cast-point-required', context)
                end
                return
            end
            local cast_time, result = now(), nil
            if skill_key == 'C03_U01' then
                result = self.runtime:activate_ultimate(actor_id, cast_time, context)
            elseif type(self.targeting.requires_hit_confirmation) == 'function'
                and self.targeting:requires_hit_confirmation(skill_key) then
                if type(self.options.on_cast_committed) ~= 'function' then
                    if type(self.options.on_cast_rejected) == 'function' then
                        self.options.on_cast_rejected(actor_id, skill_key, 'hit-confirmation-hook-required', context)
                    end
                    return
                end
                result = self.runtime:commit_skill(actor_id, skill_key, ability:get_level(), cast_time, context)
                if result.ok then self.options.on_cast_committed(actor_id, result.cast_id, result.cast_snapshot, context) end
            else
                result = self.runtime:use_skill(actor_id, skill_key, ability:get_level(), cast_time, context)
            end
            if result and result.ok then
                registration.last_invalidation_reason = nil
                report_context(self, actor_id, registration, context)
            end
        end))
    end
    return state_or_error
end

function Controller:confirm_skill_hit(actor_id, cast_id, context)
    local active_context_value, error_code = active_context(self, actor_id, context, true)
    if not active_context_value then return { ok = false, error = error_code, commands = {} } end
    local result = self.runtime:confirm_skill_hit(actor_id, cast_id, now(), active_context_value)
    if result.ok then
        report_context(self, actor_id, self.registrations[actor_id], active_context_value)
    end
    return result
end

function Controller:begin_cast(actor_id, skill_key, rank, context)
    local active_context_value, error_code = active_context(self, actor_id, context, false)
    if not active_context_value then return { ok = false, error = error_code, commands = {} } end
    return self.runtime:begin_cast(actor_id, skill_key, rank, now(), active_context_value)
end

function Controller:confirm_hit(actor_id, cast_id, context)
    return self:confirm_skill_hit(actor_id, cast_id, context)
end

function Controller:set_ability_level(actor_id, skill_key, rank, context)
    local active_context_value, error_code = active_context(self, actor_id, context, false)
    if not active_context_value then return false, error_code end
    return self.runtime:set_ability_level(actor_id, skill_key, rank, now(), active_context_value)
end

function Controller:finish_skill_miss(actor_id, cast_id, reason, context)
    local active_context_value, error_code = active_context(self, actor_id, context, true)
    if not active_context_value then return { ok = false, error = error_code, commands = {} } end
    return self.runtime:finish_skill_miss(actor_id, cast_id, now(), reason, active_context_value)
end

function Controller:finalize_cast(actor_id, cast_id, reason, context)
    return self:finish_skill_miss(actor_id, cast_id, reason, context)
end

function Controller:tick(actor_id, context)
    local active_context_value, error_code = active_context(self, actor_id, context, false)
    if not active_context_value then return false, error_code end
    return self.runtime:tick(actor_id, now(), active_context_value)
end

function Controller:invalidate_lifecycle(actor_id, reason)
    local registration = self.registrations[actor_id]
    if not registration then return false, 'unknown-actor' end
    if registration.last_invalidation_reason == reason then return true, registration.lifecycle_id end

    local previous_lifecycle_id = registration.lifecycle_id
    if type(self.adapter.cancel_actor_timers) == 'function' then
        self.adapter:cancel_actor_timers(actor_id, previous_lifecycle_id)
    end
    self.next_lifecycle_id = self.next_lifecycle_id + 1
    local next_lifecycle_id = self.next_lifecycle_id
    local cleared, error_code = self.runtime:invalidate_lifecycle(actor_id, next_lifecycle_id, now(), reason)
    if not cleared then return false, error_code end
    registration.lifecycle_id = next_lifecycle_id
    registration.last_invalidation_reason = reason
    return true, next_lifecycle_id
end

function Controller:clear(actor_id, reason)
    return self:invalidate_lifecycle(actor_id, reason or 'clear')
end

function Controller:remove(actor_id, reason)
    local registration = self.registrations[actor_id]
    if not registration then return false, 'unknown-actor' end
    self:invalidate_lifecycle(actor_id, reason or 'remove')
    self.registrations[actor_id] = nil
    if type(self.adapter.cancel_actor_timers) == 'function' then self.adapter:cancel_actor_timers(actor_id, registration.lifecycle_id) end
    if registration.timer then registration.timer:remove() end
    for _, trigger in ipairs(registration.triggers) do trigger:remove() end
    self.runtime:remove(actor_id)
    self.units[actor_id] = nil
    return true
end

return M
