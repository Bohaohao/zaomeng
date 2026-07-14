local Runtime = require 'powang_runtime'
local Y3Adapter = require 'powang_y3_adapter'
local Y3Targeting = require 'powang_y3_targeting'

local M = {}

local Controller = {}
Controller.__index = Controller

function M.new(options)
    options = options or {}
    local units = {}
    options.unit_by_actor = options.unit_by_actor or function(actor_id)
        return units[actor_id]
    end
    local adapter = options.adapter or Y3Adapter.new(options)
    local targeting = options.targeting or Y3Targeting.new(options)
    local controller = setmetatable({
        options = options,
        adapter = adapter,
        runtime = Runtime.new(adapter),
        targeting = targeting,
        units = units,
        registrations = {},
        last_normal_attack_at = {},
        next_lifecycle_id = 0,
    }, Controller)
    if type(adapter.set_lifecycle_resolver) == 'function' then
        adapter:set_lifecycle_resolver(function(actor_id, lifecycle_id)
            local registration = controller.registrations[actor_id]
            return registration ~= nil and registration.lifecycle_id == lifecycle_id
        end)
    end
    options.on_move_finished = options.on_move_finished or function(actor_id)
        controller.runtime:on_move_finished(actor_id, y3.game.current_game_run_time())
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

local function is_active_registration(controller, actor_id, registration)
    return controller.registrations[actor_id] == registration
end

local function active_context(controller, actor_id, context, require_lifecycle_id)
    local registration = controller.registrations[actor_id]
    if not registration then
        return nil, 'unknown-actor'
    end
    context = context or {}
    if require_lifecycle_id and context.lifecycle_id == nil then
        return nil, 'lifecycle-id-required'
    end
    if context.lifecycle_id ~= nil and context.lifecycle_id ~= registration.lifecycle_id then
        return nil, 'stale-lifecycle'
    end
    context.lifecycle_id = registration.lifecycle_id
    context.unit = context.unit or registration.unit
    return context
end

function Controller:register(actor_id, unit, state_options)
    assert(self.registrations[actor_id] == nil, 'actor already registered')
    state_options = state_options or {}
    state_options.level = state_options.level or unit:get_level()
    state_options.now = state_options.now or now()
    self.next_lifecycle_id = self.next_lifecycle_id + 1
    local registration = {
        unit = unit,
        triggers = {},
        lifecycle_id = self.next_lifecycle_id,
    }
    self.units[actor_id] = unit
    self.registrations[actor_id] = registration
    state_options.lifecycle_id = registration.lifecycle_id
    state_options.context = state_options.context or { unit = unit }
    state_options.context.unit = unit
    state_options.context.lifecycle_id = registration.lifecycle_id
    local ok, state_or_error = pcall(function()
        return self.runtime:register(actor_id, state_options)
    end)
    if not ok then
        self.registrations[actor_id] = nil
        self.units[actor_id] = nil
        error(state_or_error)
    end
    local state = state_or_error

    registration.timer = y3.timer.loop(0.1, function()
        if not is_active_registration(self, actor_id, registration) or not unit:is_exist() then
            return
        end
        self.runtime:set_health(actor_id, unit:get_hp())
        self.runtime:tick(actor_id, now(), { unit = unit, lifecycle_id = registration.lifecycle_id })
    end, 'Powang runtime tick')

    add_trigger(registration, unit:event('单位-受到伤害后', function(_, data)
        if not is_active_registration(self, actor_id, registration) or not unit:is_exist() then
            return
        end
        local context = {
            now = now(),
            unit = unit,
            source_unit = data.source_unit,
            target_unit = data.target_unit,
            current_hp = unit:get_hp(),
            target = data.source_unit,
            targets = data.source_unit and { data.source_unit } or {},
            damage = data.damage,
            lifecycle_id = registration.lifecycle_id,
            guardable_hit = false,
            effective_protection = false,
        }
        if type(self.options.classify_guardable_damage) == 'function' then
            local qualification = self.options.classify_guardable_damage(actor_id, unit, data, context) or {}
            context.guardable_hit = qualification.guardable_hit == true
            context.effective_protection = qualification.effective_protection == true
            context.damage_qualification = qualification
        end
        self.runtime:on_damage_taken(actor_id, context.now, context)
    end))

    add_trigger(registration, unit:event('单位-造成伤害后', function(_, data)
        if not is_active_registration(self, actor_id, registration) or not unit:is_exist() then
            return
        end
        if data.is_normal_hit and data.damage > 0 then
            local attack_time = now()
            if self.last_normal_attack_at[actor_id] ~= attack_time then
                self.last_normal_attack_at[actor_id] = attack_time
                self.runtime:normal_attack_hit(actor_id, attack_time, {
                    unit = unit,
                    target = data.target_unit,
                    lifecycle_id = registration.lifecycle_id,
                })
            end
        end
    end))

    add_trigger(registration, unit:event('单位-升级', function()
        if not is_active_registration(self, actor_id, registration) or not unit:is_exist() then
            return
        end
        self.runtime:set_level(actor_id, unit:get_level(), {
            unit = unit,
            now = now(),
            lifecycle_id = registration.lifecycle_id,
        })
    end))

    add_trigger(registration, unit:event('单位-死亡', function()
        if not is_active_registration(self, actor_id, registration) then
            return
        end
        self.runtime:clear_transient(actor_id, now(), 'death', {
            unit = unit,
            lifecycle_id = registration.lifecycle_id,
        })
    end))

    if self.options.skill_by_y3_id then
        add_trigger(registration, unit:event('单位-施放技能', function(_, data)
            if not is_active_registration(self, actor_id, registration) or not unit:is_exist() then
                return
            end
            local ability = data.ability
            local skill_key = self.options.skill_by_y3_id and self.options.skill_by_y3_id[ability:get_key()]
            if not skill_key then
                return
            end
            local context
            if type(self.options.resolve_cast_context) == 'function' then
                context = self.options.resolve_cast_context(actor_id, unit, ability, data) or {}
            else
                context = self.targeting:build_context(
                    self.runtime,
                    actor_id,
                    skill_key,
                    ability:get_level(),
                    unit,
                    ability,
                    data
                )
            end
            context.unit = unit
            context.ability = ability
            context.skill_key = skill_key
            context.lifecycle_id = registration.lifecycle_id
            local cast_time = now()
            if skill_key == 'C01_U01' then
                self.runtime:activate_ultimate(actor_id, cast_time, context)
            elseif context.defer_hit then
                local result = self.runtime:commit_skill(actor_id, skill_key, ability:get_level(), cast_time, context)
                if result.ok and type(self.options.on_cast_committed) == 'function' then
                    self.options.on_cast_committed(actor_id, result.cast_id, context)
                end
            else
                self.runtime:use_skill(actor_id, skill_key, ability:get_level(), cast_time, context)
            end
        end))
    end

    return state
end

function Controller:confirm_skill_hit(actor_id, cast_id, context)
    local active, error_code = active_context(self, actor_id, context, true)
    if not active then
        return { ok = false, error = error_code, commands = {} }
    end
    return self.runtime:confirm_skill_hit(actor_id, cast_id, now(), active)
end

function Controller:set_ability_level(actor_id, skill_key, rank, context)
    local active, error_code = active_context(self, actor_id, context, false)
    if not active then
        return false, error_code
    end
    return self.runtime:set_ability_level(actor_id, skill_key, rank, now(), active)
end

function Controller:finish_skill_miss(actor_id, cast_id, reason, context)
    local active, error_code = active_context(self, actor_id, context, true)
    if not active then
        return { ok = false, error = error_code, commands = {} }
    end
    return self.runtime:finish_skill_miss(actor_id, cast_id, now(), reason, active)
end

function Controller:tick(actor_id, context)
    local active, error_code = active_context(self, actor_id, context, false)
    if not active then
        return false, error_code
    end
    return self.runtime:tick(actor_id, now(), active)
end

function Controller:clear(actor_id, reason)
    local active, error_code = active_context(self, actor_id, nil, false)
    if not active then
        return false, error_code
    end
    return self.runtime:clear_transient(actor_id, now(), reason, active)
end

function Controller:remove(actor_id)
    local registration = self.registrations[actor_id]
    if not registration then
        return false, 'unknown-actor'
    end
    self.registrations[actor_id] = nil
    if type(self.adapter.cancel_actor_timers) == 'function' then
        self.adapter:cancel_actor_timers(actor_id, registration.lifecycle_id)
    end
    if registration.timer then
        registration.timer:remove()
    end
    for _, trigger in ipairs(registration.triggers) do
        trigger:remove()
    end
    self.runtime:remove(actor_id, {
        unit = registration.unit,
        lifecycle_id = registration.lifecycle_id,
        now = now(),
    })
    self.units[actor_id] = nil
    self.last_normal_attack_at[actor_id] = nil
    return true
end

return M
