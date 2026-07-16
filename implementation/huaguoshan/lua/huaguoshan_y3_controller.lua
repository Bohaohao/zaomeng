-- Lifecycle owner for the offline encounter bridge. A real map root supplies
-- verified callbacks through huaguoshan_y3_adapter before live activation.
local Runtime = require 'huaguoshan_runtime'
local Adapter = require 'huaguoshan_y3_adapter'
local Config = require 'huaguoshan_config'

local M = {}
local Controller = {}
Controller.__index = Controller
local next_offline_delivery_namespace = 0

local function active(controller, actor_id, registration, lifecycle_id)
    return controller.registrations[actor_id] == registration
        and registration.retiring ~= true
        and registration.sealed ~= true
        and registration.lifecycle_id == lifecycle_id
end

local function retirement_identity_matches(registration, retirement)
    return type(registration) == 'table'
        and type(retirement) == 'table'
        and retirement.registration == registration
        and registration.retirement == retirement
        and registration.retirement_token == retirement.token
end

local function source_matches_registration(registration, source_unit_id, source_unit_lifecycle_id)
    local unit_ref = registration and registration.unit_ref
    local unit_id = type(unit_ref) == 'table' and (unit_ref.id or unit_ref.unit_id) or nil
    return unit_id ~= nil
        and source_unit_id == unit_id
        and source_unit_lifecycle_id == registration.lifecycle_id
end

local untrusted_authority_fields = {
    'authority_verified',
    'actor_alive',
    'within_interaction_area',
    'completed_reading',
    'reading_continuous',
    'boss_target_current',
    'interaction_unit_current',
    'target_current',
    'anchor_in_safe_line',
    'anchor_outside_vortex_core',
}

local instance_untrusted_authority_fields = {
    'authority_verified',
    'now',
    'members',
    'member_ids',
    'member_snapshot',
    'operation_token',
    'proof',
    'operation_proof',
    'authority_proof',
    'cleanup_token',
    'reason',
}

local function untrusted_authority_field(payload)
    if type(payload) ~= 'table' then return nil end
    for _, field in ipairs(untrusted_authority_fields) do
        if payload[field] ~= nil then return field end
    end
    return nil
end

local function instance_untrusted_authority_field(payload)
    if type(payload) ~= 'table' then return nil end
    for _, field in ipairs(instance_untrusted_authority_fields) do
        if payload[field] ~= nil then return field end
    end
    return nil
end

local function copy_value(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, nested in pairs(value) do copy[key] = copy_value(nested) end
    return copy
end

local function copy_command(command)
    return copy_value(command)
end

local function normalize_delivery_namespace(options)
    local namespace = options.delivery_namespace
    if namespace == nil then namespace = options.delivery_boot_epoch end
    if namespace == nil then
        local adapter = options.adapter
        local live_mode = options.mode == 'live'
            or (type(adapter) == 'table' and adapter.mode == 'live')
        if options.require_delivery_namespace == true or live_mode then
            error('delivery_namespace is required for live or explicitly durable controllers', 3)
        end
        next_offline_delivery_namespace = next_offline_delivery_namespace + 1
        return 'offline-controller-' .. tostring(next_offline_delivery_namespace)
    end
    if type(namespace) ~= 'string' and type(namespace) ~= 'number' then
        error('delivery_namespace must be a non-empty string or number', 3)
    end
    namespace = tostring(namespace)
    if namespace == '' or namespace:find('%S') == nil then
        error('delivery_namespace must be a non-empty string or number', 3)
    end
    return namespace
end

local function delivery_identity(controller, prefix, sequence)
    local namespace = controller.delivery_namespace
    if namespace ~= nil then
        return prefix .. ':' .. namespace .. ':' .. tostring(sequence)
    end
    return prefix .. ':' .. tostring(sequence)
end

local function apply_delivery_status(payload, delivery, pending, error_code)
    payload.accepted = true
    payload.operation_id = delivery.operation_id
    payload.delivery_id = delivery.batch_id
    payload.delivery_pending = pending == true
    payload.delivery_error = pending == true and error_code or nil
    if delivery.namespace ~= nil then payload.delivery_namespace = delivery.namespace end
end

local function set_delivery_status(delivery, pending, error_code)
    apply_delivery_status(delivery.payload, delivery, pending, error_code)
    if delivery.public_payload ~= delivery.payload then
        apply_delivery_status(delivery.public_payload, delivery, pending, error_code)
    end
end

local function pending_delivery_index(controller, delivery)
    for index, candidate in ipairs(controller.pending_deliveries) do
        if candidate == delivery then return index end
    end
    return nil
end

local function stage_delivery(controller, payload)
    if type(payload) ~= 'table' or type(payload.commands) ~= 'table' then
        return true, nil
    end
    for _, command in ipairs(payload.commands) do
        if type(command) ~= 'table' then return false, 'invalid-runtime-command' end
    end
    controller.next_delivery_id = controller.next_delivery_id + 1
    local batch_id = delivery_identity(controller, 'huaguoshan-delivery', controller.next_delivery_id)
    local delivery = {
        batch_id = batch_id,
        operation_id = delivery_identity(controller, 'huaguoshan-operation', controller.next_delivery_id),
        namespace = controller.delivery_namespace,
        payload = copy_value(payload),
        public_payload = payload,
    }
    local commands = {}
    for index, command in ipairs(payload.commands) do
        local delivered = copy_command(command)
        delivered.delivery_id = delivered.delivery_id or (batch_id .. ':' .. tostring(index))
        commands[index] = delivered
    end
    delivery.payload.commands = copy_value(commands)
    payload.commands = copy_value(commands)
    set_delivery_status(delivery, #commands > 0)
    apply_delivery_status(payload, delivery, #commands > 0)
    if #commands > 0 then
        controller.pending_deliveries[#controller.pending_deliveries + 1] = delivery
    end
    return true, delivery
end

local function emit(controller, payload)
    local staged, delivery = stage_delivery(controller, payload)
    if staged ~= true then return false, delivery end
    if delivery == nil or pending_delivery_index(controller, delivery) == nil then return true end

    local drained, error_code = controller:retry_pending_deliveries()
    if pending_delivery_index(controller, delivery) ~= nil and drained ~= true then
        error_code = error_code or 'command-dispatch-failed'
        set_delivery_status(delivery, true, error_code)
        return false, error_code
    end
    return true
end

local function delivered_result(controller, ok, payload)
    if ok ~= true then return false, payload end
    local public_payload = type(payload) == 'table' and copy_value(payload) or payload
    if type(public_payload) == 'table' and public_payload.commands == nil then public_payload.commands = {} end
    local emitted, error_code = emit(controller, public_payload)
    if emitted ~= true then
        if type(public_payload) == 'table' and public_payload.delivery_pending == true then
            public_payload.delivery_error = public_payload.delivery_error or error_code or 'command-dispatch-failed'
            return true, public_payload
        end
        return false, error_code or 'command-dispatch-failed'
    end
    return true, public_payload
end

local function stage_committed_delivery(controller, payload)
    local public_payload = type(payload) == 'table' and copy_value(payload) or payload
    local staged, delivery = stage_delivery(controller, public_payload)
    if staged ~= true then return false, delivery end
    return true, public_payload, delivery
end

local function dispatch_staged_delivery(controller, payload, delivery)
    if controller.delivery_drain_suspended > 0 or #controller.pending_deliveries == 0 then
        return true, payload
    end
    local drained, error_code = controller:retry_pending_deliveries()
    if delivery ~= nil and pending_delivery_index(controller, delivery) ~= nil and drained ~= true then
        set_delivery_status(delivery, true, error_code or 'command-dispatch-failed')
    end
    return true, payload
end

local function teardown_failure(default_error, error_code)
    if error_code == nil then return default_error end
    return default_error .. ':' .. tostring(error_code)
end

local function invoke_teardown(default_error, callback, ...)
    local called, removed, error_code = pcall(callback, ...)
    if not called then return false, teardown_failure(default_error, removed) end
    if removed == false then return false, error_code or default_error end
    return true
end

local function cancel_timer(controller, handle)
    if type(handle) == 'table' and type(handle.remove) == 'function' then
        return invoke_teardown('map-timer-removal-failed', handle.remove, handle)
    end
    if type(handle) == 'table' and type(handle.cancel) == 'function' then
        return invoke_teardown('map-timer-removal-failed', handle.cancel, handle)
    end
    if type(controller.timer_remover) == 'function' then
        return invoke_teardown('map-timer-removal-failed', controller.timer_remover, handle)
    end
    return false, 'map-timer-remover-required'
end

function M.new(options)
    options = options or {}
    local delivery_namespace = normalize_delivery_namespace(options)
    local controller = setmetatable({
        adapter = options.adapter or Adapter.new(options),
        registrations = {},
        next_lifecycle_id = 0,
        next_retirement_id = 0,
        next_delivery_id = 0,
        delivery_namespace = delivery_namespace,
        pending_deliveries = {},
        delivery_drain_active = false,
        delivery_drain_suspended = 0,
        pending_retirements = {},
        pending_retirement_order = {},
        retirement_retry_active = false,
        owner_timers = {},
        timer_registrar = options.register_timer,
        timer_remover = options.remove_timer,
    }, Controller)
    controller.runtime = options.runtime or Runtime.new({
        authority_provider = options.authority_provider,
        actor_is_current = function(actor_id, lifecycle_id)
            local registration = controller.registrations[actor_id]
            return registration ~= nil
                and registration.retiring ~= true
                and registration.sealed ~= true
                and registration.lifecycle_id == lifecycle_id
        end,
        source_unit_is_current = function(actor_id, lifecycle_id, source_unit_id, source_unit_lifecycle_id)
            local registration = controller.registrations[actor_id]
            return registration ~= nil
                and registration.retiring ~= true
                and registration.sealed ~= true
                and registration.lifecycle_id == lifecycle_id
                and source_matches_registration(registration, source_unit_id, source_unit_lifecycle_id)
        end,
        skill_validator = options.skill_validator,
        progression_validator = options.progression_validator,
    })
    return controller
end

function Controller:retry_pending_deliveries()
    if self.delivery_drain_suspended > 0 then return true end
    if self.delivery_drain_active then return true end
    self.delivery_drain_active = true
    while #self.pending_deliveries > 0 do
        local delivery = self.pending_deliveries[1]
        local called, delivered, error_code = pcall(self.adapter.emit, self.adapter, delivery.payload)
        if not called then
            set_delivery_status(delivery, true, tostring(delivered))
            self.delivery_drain_active = false
            error(delivered, 0)
        end
        if delivered ~= true then
            error_code = error_code or 'command-dispatch-failed'
            set_delivery_status(delivery, true, error_code)
            self.delivery_drain_active = false
            return false, error_code
        end
        local delivery_index = pending_delivery_index(self, delivery)
        if delivery_index == nil then
            error_code = 'delivery-queue-identity-lost:' .. tostring(delivery.batch_id)
            set_delivery_status(delivery, true, error_code)
            self.delivery_drain_active = false
            return false, error_code
        end
        table.remove(self.pending_deliveries, delivery_index)
        set_delivery_status(delivery, false)
    end
    self.delivery_drain_active = false
    return true
end

function Controller:bind_map()
    return self.adapter:bind_map(self.runtime.binding, Config.layout_contract.id)
end

function Controller:_owner_key(actor_id, lifecycle_id)
    return 'actor:' .. tostring(actor_id) .. ':lifecycle:' .. tostring(lifecycle_id)
end

function Controller:_track_retirement(retirement)
    local token = retirement and retirement.token
    if token == nil then return false, 'actor-retirement-token-required' end
    if self.pending_retirements[token] ~= nil then
        return false, 'actor-retirement-identity-collision'
    end
    self.pending_retirements[token] = retirement
    self.pending_retirement_order[#self.pending_retirement_order + 1] = token
    return true
end

function Controller:_retirement_is_pending(retirement)
    return type(retirement) == 'table'
        and self.pending_retirements[retirement.token] == retirement
end

function Controller:_forget_retirement(retirement)
    if not self:_retirement_is_pending(retirement) then return false end
    self.pending_retirements[retirement.token] = nil
    for index, token in ipairs(self.pending_retirement_order) do
        if token == retirement.token then
            table.remove(self.pending_retirement_order, index)
            break
        end
    end
    return true
end

function Controller:_remove_actor_resources(registration)
    local owner_key = registration.owner_key
        or self:_owner_key(registration.actor_id, registration.lifecycle_id)
    if type(self.adapter.remove_owner_hooks) == 'function' then
        local removed, error_code = invoke_teardown(
            'map-hook-removal-failed', self.adapter.remove_owner_hooks, self.adapter, owner_key
        )
        if removed == false then return false, error_code or 'map-hook-removal-failed' end
    end
    local adapter_timers_removed = false
    local adapter_timer_error = nil
    if type(self.adapter.remove_owner_timers) == 'function' then
        local removed, error_code = invoke_teardown(
            'map-timer-removal-failed', self.adapter.remove_owner_timers, self.adapter, owner_key
        )
        adapter_timers_removed = removed == true
        if not adapter_timers_removed then adapter_timer_error = error_code end
    end
    local remaining_timers = {}
    local first_timer_error = nil
    for _, entry in ipairs(self.owner_timers[owner_key] or {}) do
        if not entry.adapter_owned or not adapter_timers_removed then
            local removed, error_code = cancel_timer(self, entry.handle)
            if not removed then
                remaining_timers[#remaining_timers + 1] = entry
                first_timer_error = first_timer_error or error_code or 'map-timer-removal-failed'
            end
        end
    end
    if #remaining_timers > 0 then
        self.owner_timers[owner_key] = remaining_timers
        return false, first_timer_error
    end
    self.owner_timers[owner_key] = nil
    if adapter_timer_error then return false, adapter_timer_error end
    return true
end

function Controller:_remember_timer(owner_key, handle, adapter_owned)
    local timers = self.owner_timers[owner_key] or {}
    self.owner_timers[owner_key] = timers
    timers[#timers + 1] = { handle = handle, adapter_owned = adapter_owned }
end

function Controller:_resume_retirement(retirement)
    local registration = retirement and retirement.registration
    if not retirement_identity_matches(registration, retirement) then
        return nil, 'stale-actor-retirement'
    end
    if retirement.teardown_complete then
        return retirement.payload, nil, retirement.delivery
    end
    if not self:_retirement_is_pending(retirement) then
        return nil, 'stale-actor-retirement'
    end
    if retirement.teardown_active then return nil, 'actor-retirement-in-progress' end

    retirement.teardown_active = true
    self.delivery_drain_suspended = self.delivery_drain_suspended + 1
    local removed, error_code = self:_remove_actor_resources(registration)
    self.delivery_drain_suspended = self.delivery_drain_suspended - 1
    retirement.teardown_active = false
    if not retirement_identity_matches(registration, retirement)
        or not self:_retirement_is_pending(retirement) then
        return nil, 'stale-actor-retirement'
    end
    if not removed then
        retirement.teardown_error = error_code
        return nil, error_code
    end

    retirement.teardown_error = nil
    retirement.teardown_complete = true
    if self.registrations[registration.actor_id] == registration then
        self.registrations[registration.actor_id] = nil
    end
    self:_forget_retirement(retirement)
    return retirement.payload, nil, retirement.delivery
end

function Controller:retry_pending_retirements()
    if self.retirement_retry_active then return true end
    self.retirement_retry_active = true
    local pending_tokens = {}
    for index, token in ipairs(self.pending_retirement_order) do pending_tokens[index] = token end

    local first_error = nil
    for _, token in ipairs(pending_tokens) do
        local retirement = self.pending_retirements[token]
        if retirement ~= nil then
            local _, error_code = self:_resume_retirement(retirement)
            if error_code ~= nil and error_code ~= 'actor-retirement-in-progress' then
                first_error = first_error or error_code
            end
        end
    end
    self.retirement_retry_active = false
    if first_error ~= nil then return false, first_error end
    return self:retry_pending_deliveries()
end

function Controller:_retire_registration(registration, reason, now)
    local retirement = registration.retirement
    if retirement == nil then
        if registration.sealed then return nil, 'actor-lifecycle-sealed' end
        if registration.retiring then return nil, 'actor-lifecycle-retiring' end
        registration.retiring = true
        local invalidated, invalidation = self.runtime:invalidate_actor(
            registration.actor_id, registration.lifecycle_id
        )
        if invalidated ~= true then
            if self.registrations[registration.actor_id] == registration
                and registration.retirement == nil
                and registration.sealed ~= true then
                registration.retiring = false
            end
            return nil, invalidation or 'actor-invalidation-failed'
        end
        registration.sealed = true
        registration.retiring = false
        local staged, public_invalidation, delivery = stage_committed_delivery(self, invalidation)
        if staged ~= true then return nil, public_invalidation end
        self.next_retirement_id = self.next_retirement_id + 1
        local retirement_token = 'actor-retirement:'
            .. tostring(registration.actor_id) .. ':'
            .. tostring(registration.lifecycle_id) .. ':'
            .. tostring(self.next_retirement_id)
        retirement = {
            payload = public_invalidation,
            delivery = delivery,
            registration = registration,
            token = retirement_token,
            teardown_active = false,
            teardown_complete = false,
        }
        registration.retirement_token = retirement_token
        registration.retirement = retirement
        local tracked, track_error = self:_track_retirement(retirement)
        if tracked ~= true then return nil, track_error end
    end
    return self:_resume_retirement(retirement)
end

function Controller:_new_registration(actor_id, unit_ref, team_id)
    self.next_lifecycle_id = self.next_lifecycle_id + 1
    local lifecycle_id = self.next_lifecycle_id
    return {
        actor_id = actor_id,
        unit_ref = unit_ref,
        team_id = team_id,
        lifecycle_id = lifecycle_id,
        owner_key = self:_owner_key(actor_id, lifecycle_id),
        retiring = false,
        sealed = false,
    }
end

function Controller:_register_during_retirement(previous, unit_ref, team_id)
    local retirement = previous.retirement
    if retirement == nil or retirement.teardown_active ~= true then
        return nil, 'actor-retirement-in-progress'
    end
    if not retirement_identity_matches(previous, retirement)
        or self.registrations[previous.actor_id] ~= previous then
        return nil, 'stale-actor-retirement'
    end
    if retirement.superseded_by ~= nil then return nil, 'actor-registration-superseded' end

    local registration = self:_new_registration(previous.actor_id, unit_ref, team_id)
    if not retirement_identity_matches(previous, retirement)
        or self.registrations[previous.actor_id] ~= previous then
        return nil, 'stale-actor-retirement'
    end
    retirement.superseded_by = registration
    self.registrations[previous.actor_id] = registration
    local _, delivery = dispatch_staged_delivery(self, retirement.payload, retirement.delivery)
    return registration, delivery
end

function Controller:_can_start_encounter(encounter_key)
    if encounter_key == nil then return false, 'encounter-key-required' end
    if type(self.adapter.can_start_encounter) ~= 'function' then
        return false, 'encounter-start-gate-unavailable'
    end
    local allowed, error_code = self.adapter:can_start_encounter(encounter_key)
    if allowed ~= true then return false, error_code or 'encounter-start-rejected' end
    return true
end

function Controller:register_actor(actor_id, unit_ref, team_id, now)
    local previous = self.registrations[actor_id]
    local invalidation = nil
    local invalidation_delivery = nil
    if previous then
        if previous.retirement and previous.retirement.teardown_active then
            return self:_register_during_retirement(previous, unit_ref, team_id)
        end
        local error_code
        invalidation, error_code, invalidation_delivery = self:_retire_registration(previous, 're-register', now)
        if error_code then return nil, error_code end
        local current = self.registrations[actor_id]
        if current ~= nil then
            local _, delivery = dispatch_staged_delivery(self, invalidation, invalidation_delivery)
            if current ~= previous then
                return nil, 'actor-registration-superseded', delivery
            end
            return nil, 'stale-actor-retirement', delivery
        end
    end
    if self.registrations[actor_id] ~= nil then return nil, 'actor-registration-superseded' end
    local registration = self:_new_registration(actor_id, unit_ref, team_id)
    self.registrations[actor_id] = registration
    local _, delivery = dispatch_staged_delivery(self, invalidation, invalidation_delivery)
    return registration, delivery
end

function Controller:_registration(actor_id, lifecycle_id)
    local registration = self.registrations[actor_id]
    if not registration then return nil, 'unknown-actor' end
    if registration.retiring then return nil, 'actor-lifecycle-retiring' end
    if registration.sealed then return nil, 'actor-lifecycle-sealed' end
    if lifecycle_id ~= nil and registration.lifecycle_id ~= lifecycle_id then return nil, 'stale-actor-lifecycle' end
    return registration
end

function Controller:_registration_for_retirement(actor_id)
    local registration = self.registrations[actor_id]
    if not registration then return nil, 'unknown-actor' end
    if registration.retiring and registration.retirement == nil then
        return nil, 'actor-lifecycle-retiring'
    end
    if registration.sealed and registration.retirement == nil then return nil, 'actor-lifecycle-sealed' end
    return registration
end

function Controller:_decorate_actor_event(event)
    local untrusted = untrusted_authority_field(event)
    if untrusted then return nil, 'untrusted-authority-field:' .. untrusted end
    local registration, error_code = self:_registration(event and event.actor_id, event and event.lifecycle_id)
    if not registration then return nil, error_code end
    if event.team_id ~= nil and registration.team_id ~= nil and event.team_id ~= registration.team_id then
        return nil, 'team-id-mismatch'
    end
    local source_bound = {
        final_damage = true,
        actual_break = true,
        actual_protection = true,
        mechanic_resolved = true,
    }
    if source_bound[event.kind] and not source_matches_registration(
        registration, event.source_unit_id, event.source_unit_lifecycle_id
    ) then
        return nil, 'stale-source-unit-lifecycle'
    end
    event.team_id = registration.team_id
    return event
end

function Controller:install_actor_hook(actor_id, hook_key, callback)
    local registration, error_code = self:_registration(actor_id)
    if not registration then return false, error_code end
    if type(callback) ~= 'function' then return false, 'map-hook-callback-required' end
    local lifecycle_id = registration.lifecycle_id
    return self.adapter:install_hook(registration.owner_key, hook_key, function(...)
        if active(self, actor_id, registration, lifecycle_id) then callback(...) end
    end)
end

function Controller:install_actor_timer(actor_id, timer_key, callback)
    local registration, error_code = self:_registration(actor_id)
    if not registration then return false, error_code end
    if type(callback) ~= 'function' then return false, 'map-timer-callback-required' end
    local lifecycle_id = registration.lifecycle_id
    local owner_key = registration.owner_key
    local wrapped = function(...)
        if active(self, actor_id, registration, lifecycle_id) then callback(...) end
    end
    local handle, adapter_owned
    if type(self.adapter.install_timer) == 'function' then
        local installed, install_result = self.adapter:install_timer(owner_key, timer_key, wrapped)
        if installed ~= true then return false, install_result or 'map-timer-registration-failed' end
        handle, adapter_owned = install_result, true
    elseif type(self.timer_registrar) == 'function' then
        local called, registered_handle = pcall(self.timer_registrar, timer_key, wrapped)
        if not called or registered_handle == nil or registered_handle == false then
            return false, 'map-timer-registration-failed'
        end
        handle, adapter_owned = registered_handle, false
    else
        return false, 'map-timer-registrar-required'
    end
    self:_remember_timer(owner_key, handle, adapter_owned)
    return true, handle
end

function Controller:track_actor_timer(actor_id, handle)
    local registration, error_code = self:_registration(actor_id)
    if not registration then return false, error_code end
    if handle == nil then return false, 'timer-handle-required' end
    self:_remember_timer(registration.owner_key, handle, false)
    return true, handle
end

function Controller:invalidate_actor(actor_id, reason, now)
    local registration, error_code = self:_registration_for_retirement(actor_id)
    if not registration then return false, error_code end
    local invalidation, retire_error, invalidation_delivery = self:_retire_registration(
        registration, reason or 'lifecycle_invalid', now
    )
    if retire_error then return false, retire_error end
    local replacement = self.registrations[actor_id]
    if replacement == nil then
        replacement = self:_new_registration(actor_id, registration.unit_ref, registration.team_id)
        self.registrations[actor_id] = replacement
    elseif replacement == registration then
        return false, 'stale-actor-retirement'
    end
    local _, delivery = dispatch_staged_delivery(self, invalidation, invalidation_delivery)
    return true, replacement.lifecycle_id, delivery
end

function Controller:remove_actor(actor_id, reason, now)
    local registration, error_code = self:_registration_for_retirement(actor_id)
    if not registration then return false, error_code end
    local invalidation, retire_error, invalidation_delivery = self:_retire_registration(
        registration, reason or 'remove', now
    )
    if retire_error then return false, retire_error end
    local _, delivery = dispatch_staged_delivery(self, invalidation, invalidation_delivery)
    return true, delivery
end

function Controller:start_public_boss(encounter_key, options)
    local allowed, error_code = self:_can_start_encounter(encounter_key)
    if not allowed then return false, error_code end
    return self.runtime:start_public_boss(encounter_key, options)
end

function Controller:report_public_damage(event)
    local payload, error_code = self:_decorate_actor_event(event)
    if not payload then return false, error_code end
    local ok, result = self.runtime:report_public_damage(payload)
    return delivered_result(self, ok, result)
end

function Controller:report_public_break(event)
    local payload, error_code = self:_decorate_actor_event(event)
    if not payload then return false, error_code end
    local ok, result = self.runtime:report_public_break(payload)
    return delivered_result(self, ok, result)
end

function Controller:report_public_protection(event)
    local payload, error_code = self:_decorate_actor_event(event)
    if not payload then return false, error_code end
    local ok, result = self.runtime:report_public_protection(payload)
    return delivered_result(self, ok, result)
end

function Controller:begin_public_action(boss_instance_id, request, ...)
    if select('#', ...) > 0 then return false, 'legacy-authority-arguments-forbidden' end
    if type(request) ~= 'table' then return false, 'action-request-required' end
    local untrusted = untrusted_authority_field(request)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    local registration, error_code = self:_registration(request.actor_id, request.lifecycle_id)
    if not registration then return false, error_code end
    request.lifecycle_id = registration.lifecycle_id
    local ok, result = self.runtime:begin_public_action(boss_instance_id, request)
    return delivered_result(self, ok, result)
end

function Controller:complete_public_action(event)
    if type(event) == 'table' and (event.completed_tick ~= nil or event.sync_tick ~= nil) then
        return false, 'caller-action-timing-forbidden'
    end
    if type(event) == 'table' and event.completion_mode ~= nil then
        return false, 'caller-completion-mode-forbidden'
    end
    local payload, error_code = self:_decorate_actor_event(event)
    if not payload then return false, error_code end
    local ok, result = self.runtime:complete_public_action(payload)
    return delivered_result(self, ok, result)
end

function Controller:complete_public_actions(events)
    if type(events) ~= 'table' or #events == 0 then return false, 'action-events-required' end
    local payloads = {}
    for index, event in ipairs(events) do
        if type(event) ~= 'table' then return false, 'expected-encounter-action-success' end
        if event.completed_tick ~= nil or event.sync_tick ~= nil then
            return false, 'caller-action-timing-forbidden'
        end
        if event.completion_mode ~= nil then return false, 'caller-completion-mode-forbidden' end
        local payload, error_code = self:_decorate_actor_event(event)
        if not payload then return false, error_code end
        payloads[index] = payload
    end
    local ok, result = self.runtime:complete_public_actions(payloads)
    return delivered_result(self, ok, result)
end

function Controller:cancel_public_action(boss_instance_id, actor_id, lifecycle_id, action_token)
    local registration, error_code = self:_registration(actor_id, lifecycle_id)
    if not registration then return false, error_code end
    return self.runtime:cancel_public_action(boss_instance_id, actor_id, registration.lifecycle_id, action_token)
end

function Controller:resolve_water_chain(event)
    local payload, error_code = self:_decorate_actor_event(event)
    if not payload then return false, error_code end
    local ok, result = self.runtime:resolve_water_chain(payload)
    return delivered_result(self, ok, result)
end

function Controller:apply_public_water_chain(boss_instance_id)
    local ok, result = self.runtime:apply_public_water_chain(boss_instance_id)
    return delivered_result(self, ok, result)
end

function Controller:mark_public_phase(boss_instance_id, marker_event)
    local untrusted = untrusted_authority_field(marker_event)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    local ok, result = self.runtime:mark_public_phase(boss_instance_id, marker_event)
    return delivered_result(self, ok, result)
end

function Controller:close_public_action_window(boss_instance_id, close_event)
    local untrusted = untrusted_authority_field(close_event)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    local ok, result = self.runtime:close_public_action_window(boss_instance_id, close_event)
    return delivered_result(self, ok, result)
end

function Controller:change_public_boss_phase(boss_instance_id, transition_event)
    local untrusted = untrusted_authority_field(transition_event)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    local ok, result = self.runtime:change_public_boss_phase(boss_instance_id, transition_event)
    return delivered_result(self, ok, result)
end

function Controller:finalize_public_boss(boss_instance_id, finalization_event)
    local untrusted = untrusted_authority_field(finalization_event)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    local ok, summary = self.runtime:finalize_public_boss(boss_instance_id, finalization_event)
    return delivered_result(self, ok, summary)
end

function Controller:start_public_trace(encounter_key, options)
    local allowed, error_code = self:_can_start_encounter(encounter_key)
    if not allowed then return false, error_code end
    return self.runtime:start_public_trace(encounter_key, options)
end

function Controller:begin_public_trace_action(instance_id, actor_id, lifecycle_id, ...)
    if select('#', ...) > 0 then return false, 'legacy-authority-arguments-forbidden' end
    local registration, error_code = self:_registration(actor_id, lifecycle_id)
    if not registration then return false, error_code end
    return self.runtime:begin_public_trace_action(instance_id, actor_id, registration.lifecycle_id)
end

function Controller:complete_public_trace_action(event, ...)
    if select('#', ...) > 0 then return false, 'legacy-authority-arguments-forbidden' end
    if type(event) == 'table' and (event.sync_tick ~= nil or event.completed_tick ~= nil) then
        return false, 'caller-trace-timing-forbidden'
    end
    local payload, error_code = self:_decorate_actor_event(event)
    if not payload then return false, error_code end
    local ok, result = self.runtime:complete_public_trace_action(payload)
    return delivered_result(self, ok, result)
end

function Controller:finish_public_trace(instance_id, reason, now)
    local ok, result = self.runtime:finish_public_trace(instance_id, reason, now)
    return delivered_result(self, ok, result)
end

function Controller:cancel_public_trace_action(instance_id, actor_id, lifecycle_id, action_token)
    local registration, error_code = self:_registration(actor_id, lifecycle_id)
    if not registration then return false, error_code end
    return self.runtime:cancel_public_trace_action(instance_id, actor_id, registration.lifecycle_id, action_token)
end

function Controller:start_dragon(request, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    local untrusted = instance_untrusted_authority_field(request)
    if untrusted then return false, 'untrusted-instance-authority-field:' .. untrusted end
    local allowed, gate_error = self:_can_start_encounter(request and request.encounter_key)
    if not allowed then return false, gate_error end
    local registration, error_code = self:_registration(request and request.actor_id, request and request.lifecycle_id)
    if not registration then return false, error_code end
    local ok, result = self.runtime:start_dragon(request)
    return delivered_result(self, ok, result)
end

function Controller:finish_dragon(event)
    if type(event) ~= 'table' then return false, 'dragon-callback-identity-required' end
    local untrusted = instance_untrusted_authority_field(event)
    if untrusted then return false, 'untrusted-instance-authority-field:' .. untrusted end
    local registration, error_code = self:_registration(event.actor_id, event.lifecycle_id)
    if not registration then return false, error_code end
    local ok, result = self.runtime:finish_dragon(event)
    return delivered_result(self, ok, result)
end

function Controller:acknowledge_dragon_cleanup(acknowledgement)
    local untrusted = instance_untrusted_authority_field(acknowledgement)
    if untrusted then return false, 'untrusted-instance-authority-field:' .. untrusted end
    local ok, result = self.runtime:acknowledge_dragon_cleanup(acknowledgement)
    return delivered_result(self, ok, result)
end

function Controller:start_ox(request, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    local untrusted = instance_untrusted_authority_field(request)
    if untrusted then return false, 'untrusted-instance-authority-field:' .. untrusted end
    local allowed, gate_error = self:_can_start_encounter('HG_E_OX_BATTLEFIELD')
    if not allowed then return false, gate_error end
    local registration, error_code = self:_registration(request and request.actor_id, request and request.lifecycle_id)
    if not registration then return false, error_code end
    local ok, result = self.runtime:start_ox(request)
    return delivered_result(self, ok, result)
end

function Controller:swap_ox_phase(identity)
    local ok, result = self.runtime:swap_ox_phase(identity)
    return delivered_result(self, ok, result)
end

function Controller:fail_ox(event, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    local untrusted = instance_untrusted_authority_field(event)
    if untrusted then return false, 'untrusted-instance-authority-field:' .. untrusted end
    local ok, result = self.runtime:fail_ox(event)
    return delivered_result(self, ok, result)
end

function Controller:succeed_ox(identity, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    local ok, result = self.runtime:succeed_ox(identity)
    return delivered_result(self, ok, result)
end

function Controller:acknowledge_ox_cleanup(acknowledgement)
    local untrusted = instance_untrusted_authority_field(acknowledgement)
    if untrusted then return false, 'untrusted-instance-authority-field:' .. untrusted end
    local ok, result = self.runtime:acknowledge_ox_cleanup(acknowledgement)
    return delivered_result(self, ok, result)
end

function Controller:tick(now)
    local flushed, error_code = self:retry_pending_retirements()
    if flushed ~= true then return false, error_code end
    return delivered_result(self, true, self.runtime:tick(now))
end

function Controller:live_activation_ready()
    return self.adapter:can_activate_live_encounters()
end

return M
