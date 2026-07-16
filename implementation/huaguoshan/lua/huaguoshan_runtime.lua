-- Encounter authority. It is independent from Y3 and accepts explicit events only.
local Config = require 'huaguoshan_config'
local MapBinding = require 'huaguoshan_map_binding'
local PublicBoss = require 'huaguoshan_public_boss'
local PublicTrace = require 'huaguoshan_public_trace'
local Instances = require 'huaguoshan_instances'

local M = {}
local Runtime = {}
Runtime.__index = Runtime

local function append(list, value)
    list[#list + 1] = value
end

local function append_commands(target, result)
    if result and result.commands then
        for _, command in ipairs(result.commands) do append(target, command) end
    end
end

local function sorted_keys(map)
    local keys = {}
    for key in pairs(map) do append(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function copy_options(options)
    local copy = {}
    for key, value in pairs(options or {}) do copy[key] = value end
    return copy
end

local function authority_provider_valid(provider)
    return type(provider) == 'function'
        or (type(provider) == 'table' and type(provider.verify) == 'function')
end

function M.new(options)
    options = options or {}
    local dragon_slots = options.dragon_slots or Instances.new_dragon_slots({
        progression_validator = options.progression_validator,
        authority_provider = options.authority_provider,
        actor_lifecycle_validator = options.actor_is_current,
    })
    local ox_battlefield = options.ox_battlefield or Instances.new_ox_battlefield({
        authority_provider = options.authority_provider,
        member_lifecycle_validator = options.actor_is_current,
    })
    if type(dragon_slots.set_actor_conflict_validator) == 'function' then
        dragon_slots:set_actor_conflict_validator(function(actor_id)
            return ox_battlefield:member_is_occupying(actor_id)
        end)
    end
    if type(options.actor_is_current) == 'function'
        and type(dragon_slots.set_actor_lifecycle_validator) == 'function' then
        dragon_slots:set_actor_lifecycle_validator(options.actor_is_current)
    end
    if type(ox_battlefield.set_actor_conflict_validator) == 'function' then
        ox_battlefield:set_actor_conflict_validator(function(actor_id)
            return dragon_slots:actor_is_occupying(actor_id)
        end)
    end

    return setmetatable({
        binding = options.binding or MapBinding.new(),
        authority_provider = options.authority_provider,
        actor_is_current = options.actor_is_current,
        source_unit_is_current = options.source_unit_is_current,
        skill_validator = options.skill_validator,
        public_bosses = {},
        public_boss_by_encounter = {},
        public_traces = {},
        dragon_slots = dragon_slots,
        ox_battlefield = ox_battlefield,
    }, Runtime)
end

function Runtime:bind_map(resolver, contract_id)
    return self.binding:bind(resolver, contract_id)
end

function Runtime:map_is_bound()
    return self.binding:is_bound()
end

function Runtime:start_public_boss(encounter_key, options)
    if not authority_provider_valid(self.authority_provider) then return false, 'authority-provider-required' end
    local encounter = Config.get_encounter(encounter_key)
    if not encounter or encounter.encounter_type ~= 'public_boss' then return false, 'invalid-public-boss-encounter' end
    local ready, error_code = self.binding:assert_encounter_ready(encounter_key)
    if not ready then return false, error_code end
    if type(options) ~= 'table' or options.boss_instance_id == nil then return false, 'boss-instance-id-required' end
    if self.public_bosses[options.boss_instance_id] then return false, 'public-boss-already-active' end
    if self.public_boss_by_encounter[encounter_key] then return false, 'public-boss-encounter-already-active' end
    local boss_options = copy_options(options)
    boss_options.authority_provider = self.authority_provider
    boss_options.source_unit_is_current = self.source_unit_is_current
    boss_options.skill_validator = self.skill_validator
    self.public_bosses[options.boss_instance_id] = PublicBoss.new(encounter_key, encounter, boss_options)
    self.public_boss_by_encounter[encounter_key] = options.boss_instance_id
    return true, self.public_bosses[options.boss_instance_id]
end

function Runtime:get_public_boss(boss_instance_id)
    return self.public_bosses[boss_instance_id]
end

function Runtime:report_public_damage(event)
    local boss = event and self.public_bosses[event.boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:record_damage(event, self.actor_is_current)
end

function Runtime:report_public_break(event)
    local boss = event and self.public_bosses[event.boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:record_break(event, self.actor_is_current)
end

function Runtime:report_public_protection(event)
    local boss = event and self.public_bosses[event.boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:record_protection(event, self.actor_is_current)
end

function Runtime:begin_public_action(boss_instance_id, request, ...)
    if select('#', ...) > 0 then return false, 'legacy-authority-arguments-forbidden' end
    local boss = self.public_bosses[boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:begin_action(request, self.actor_is_current)
end

function Runtime:complete_public_action(event)
    local boss = event and self.public_bosses[event.boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:complete_action(event, self.actor_is_current)
end

function Runtime:complete_public_actions(events)
    if type(events) ~= 'table' or #events == 0 then return false, 'action-events-required' end
    local boss_instance_id = events[1] and events[1].boss_instance_id
    local boss = self.public_bosses[boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    for _, event in ipairs(events) do
        if event.boss_instance_id ~= boss_instance_id then return false, 'mixed-public-boss-action-batch' end
    end
    return boss:complete_actions(events, self.actor_is_current)
end

function Runtime:cancel_public_action(boss_instance_id, actor_id, lifecycle_id, action_token)
    local boss = self.public_bosses[boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    if self.actor_is_current(actor_id, lifecycle_id) ~= true then return false, 'stale-actor-lifecycle' end
    return boss:cancel_action(actor_id, lifecycle_id, action_token)
end

function Runtime:resolve_water_chain(event)
    local boss = event and self.public_bosses[event.boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:resolve_water_chain(event, self.actor_is_current)
end

function Runtime:apply_public_water_chain(boss_instance_id)
    local boss = self.public_bosses[boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:apply_water_chain(self.actor_is_current)
end

function Runtime:mark_public_phase(boss_instance_id, marker_event)
    local boss = self.public_bosses[boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    if type(marker_event) ~= 'table' then return false, 'phase-marker-event-required' end
    if marker_event.boss_instance_id ~= boss_instance_id then return false, 'stale-boss-instance' end
    return boss:phase_marker(marker_event)
end

function Runtime:close_public_action_window(boss_instance_id, close_event)
    local boss = self.public_bosses[boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:close_action_window(close_event)
end

function Runtime:change_public_boss_phase(boss_instance_id, transition_event)
    if type(transition_event) ~= 'table' then return false, 'boss-phase-transition-event-required' end
    if transition_event.boss_instance_id ~= boss_instance_id then return false, 'stale-boss-instance' end
    local boss = self.public_bosses[boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    return boss:change_phase(transition_event)
end

function Runtime:finalize_public_boss(boss_instance_id, finalization_event)
    if type(finalization_event) ~= 'table' then return false, 'boss-finalization-event-required' end
    if finalization_event.boss_instance_id ~= boss_instance_id then return false, 'stale-boss-instance' end
    local boss = self.public_bosses[boss_instance_id]
    if not boss then return false, 'public-boss-not-found' end
    local summary, error_code = boss:finalize(finalization_event)
    if not summary then return false, error_code end
    self.public_bosses[boss_instance_id] = nil
    if self.public_boss_by_encounter[boss.encounter_key] == boss_instance_id then
        self.public_boss_by_encounter[boss.encounter_key] = nil
    end
    return true, summary
end

function Runtime:start_public_trace(encounter_key, options)
    if not authority_provider_valid(self.authority_provider) then return false, 'authority-provider-required' end
    local encounter = Config.get_encounter(encounter_key)
    if not encounter or encounter.encounter_type ~= 'public_trace' then return false, 'invalid-public-trace-encounter' end
    local ready, error_code = self.binding:assert_encounter_ready(encounter_key)
    if not ready then return false, error_code end
    if type(options) ~= 'table' or options.instance_id == nil then return false, 'trace-instance-id-required' end
    if self.public_traces[options.instance_id] then return false, 'public-trace-already-active' end
    local trace_options = copy_options(options)
    if trace_options.postlude_seconds == nil and encounter.action then
        trace_options.postlude_seconds = encounter.action.postlude_seconds
    end
    trace_options.authority_provider = self.authority_provider
    self.public_traces[options.instance_id] = PublicTrace.new(encounter_key, encounter, trace_options)
    return true, self.public_traces[options.instance_id]
end

function Runtime:get_public_trace(instance_id)
    return self.public_traces[instance_id]
end

function Runtime:begin_public_trace_action(instance_id, actor_id, lifecycle_id, ...)
    if select('#', ...) > 0 then return false, 'legacy-authority-arguments-forbidden' end
    local trace = self.public_traces[instance_id]
    if not trace then return false, 'public-trace-not-found' end
    return trace:begin_action(actor_id, lifecycle_id, self.actor_is_current)
end

function Runtime:complete_public_trace_action(event, ...)
    if select('#', ...) > 0 then return false, 'legacy-authority-arguments-forbidden' end
    local trace = event and self.public_traces[event.encounter_instance_id]
    if not trace then return false, 'public-trace-not-found' end
    return trace:complete_action(event, self.actor_is_current)
end

function Runtime:finish_public_trace(instance_id, reason, now)
    local trace = self.public_traces[instance_id]
    if not trace then return false, 'public-trace-not-found' end
    local item, error_code = trace:finish(reason, now)
    if not item then return false, error_code end
    return true, item
end

function Runtime:cancel_public_trace_action(instance_id, actor_id, lifecycle_id, action_token)
    local trace = self.public_traces[instance_id]
    if not trace then return false, 'public-trace-not-found' end
    if self.actor_is_current(actor_id, lifecycle_id) ~= true then return false, 'stale-actor-lifecycle' end
    return trace:cancel_action(actor_id, lifecycle_id, action_token)
end

function Runtime:start_dragon(request, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    local encounter = request and Config.get_encounter(request.encounter_key)
    if not encounter or encounter.encounter_type ~= 'solo_boss' then return false, 'invalid-dragon-encounter' end
    local ready, error_code = self.binding:assert_encounter_ready(request.encounter_key)
    if not ready then return false, error_code end
    if self.actor_is_current(request.actor_id, request.lifecycle_id) ~= true then return false, 'stale-actor-lifecycle' end
    return self.dragon_slots:open(request)
end

function Runtime:finish_dragon(event)
    if type(event) ~= 'table' then return false, 'dragon-callback-identity-required' end
    if self.actor_is_current(event.actor_id, event.lifecycle_id) ~= true then return false, 'stale-actor-lifecycle' end
    return self.dragon_slots:finish(event)
end

function Runtime:acknowledge_dragon_cleanup(acknowledgement)
    return self.dragon_slots:acknowledge_cleanup(acknowledgement)
end

function Runtime:start_ox(request, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    local ready, error_code = self.binding:assert_encounter_ready('HG_E_OX_BATTLEFIELD')
    if not ready then return false, error_code end
    if type(request) ~= 'table' then return false, 'raid-entry-request-required' end
    if request.actor_id == nil or request.lifecycle_id == nil then return false, 'raid-entry-actor-required' end
    if self.actor_is_current(request.actor_id, request.lifecycle_id) ~= true then
        return false, 'stale-actor-lifecycle'
    end
    return self.ox_battlefield:open(request)
end

function Runtime:swap_ox_phase(identity)
    return self.ox_battlefield:swap_to_white_ox(identity)
end

function Runtime:fail_ox(event, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    return self.ox_battlefield:fail(event)
end

function Runtime:succeed_ox(identity, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    return self.ox_battlefield:succeed(identity)
end

function Runtime:acknowledge_ox_cleanup(acknowledgement)
    return self.ox_battlefield:acknowledge_cleanup(acknowledgement)
end

function Runtime:invalidate_actor(actor_id, lifecycle_id, ...)
    if select('#', ...) > 0 then return false, 'legacy-instance-invalidation-arguments-forbidden' end
    local commands = {}
    local instance_plans = {}
    local dragon_owner_is_current = self.dragon_slots:owner_is_current(actor_id, lifecycle_id)
    local ox_member_is_current = self.ox_battlefield:member_is_current(actor_id, lifecycle_id)

    if dragon_owner_is_current then
        local ok, plan = self.dragon_slots:prepare_invalidate_actor(actor_id, lifecycle_id)
        if ok == true then
            append(instance_plans, {
                owner = self.dragon_slots,
                plan = plan,
                is_current = function()
                    return self.dragon_slots:owner_is_current(actor_id, lifecycle_id)
                end,
                fallback_error = 'dragon-invalidation-failed',
            })
        elseif self.dragon_slots:owner_is_current(actor_id, lifecycle_id) then
            return false, plan or 'dragon-invalidation-failed'
        end
    end
    if ox_member_is_current then
        local ok, plan = self.ox_battlefield:prepare_invalidate_actor(actor_id, lifecycle_id)
        if ok == true then
            append(instance_plans, {
                owner = self.ox_battlefield,
                plan = plan,
                is_current = function()
                    return self.ox_battlefield:member_is_current(actor_id, lifecycle_id)
                end,
                fallback_error = 'ox-invalidation-failed',
            })
        elseif self.ox_battlefield:member_is_current(actor_id, lifecycle_id) then
            return false, plan or 'ox-invalidation-failed'
        end
    end
    for _, item in ipairs(instance_plans) do
        local ready, ready_error = item.owner:can_commit_invalidation(item.plan)
        if ready ~= true then
            if item.is_current() then return false, ready_error or item.fallback_error end
            item.skip = true
        end
    end
    for _, item in ipairs(instance_plans) do
        if not item.skip then
            local committed, committed_item = item.owner:commit_invalidation(item.plan)
            if committed ~= true then return false, committed_item or item.fallback_error end
            append_commands(commands, committed_item)
        end
    end
    for _, boss_id in ipairs(sorted_keys(self.public_bosses)) do
        append_commands(commands, self.public_bosses[boss_id]:invalidate_actor(actor_id, lifecycle_id))
    end
    for _, trace_id in ipairs(sorted_keys(self.public_traces)) do
        append_commands(commands, self.public_traces[trace_id]:invalidate_actor(actor_id, lifecycle_id))
    end
    return true, { commands = commands }
end

function Runtime:tick(now)
    local commands = {}
    local authority_errors = {}
    for _, boss_id in ipairs(sorted_keys(self.public_bosses)) do
        local item = self.public_bosses[boss_id]:tick(now)
        append_commands(commands, item)
        if item.authority_error then
            append(authority_errors, {
                scope = 'public_boss', instance_id = boss_id, error_code = item.authority_error,
            })
        end
    end
    for _, trace_id in ipairs(sorted_keys(self.public_traces)) do
        local trace = self.public_traces[trace_id]
        local item = trace:tick(now)
        append_commands(commands, item)
        if item.authority_error then
            append(authority_errors, {
                scope = 'public_trace', instance_id = trace_id, error_code = item.authority_error,
            })
        end
        if trace.state == 'closed' then self.public_traces[trace_id] = nil end
    end
    local dragon_item = self.dragon_slots:tick()
    append_commands(commands, dragon_item)
    if dragon_item.authority_error then
        append(authority_errors, { scope = 'dragon_instance', error_code = dragon_item.authority_error })
    end
    local ox_item = self.ox_battlefield:tick()
    append_commands(commands, ox_item)
    if ox_item.authority_error then
        append(authority_errors, { scope = 'ox_battlefield', error_code = ox_item.authority_error })
    end
    local result = { commands = commands }
    if #authority_errors > 0 then result.authority_errors = authority_errors end
    return result
end

return M
