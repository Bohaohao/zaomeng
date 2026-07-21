-- Shared authority for public trace encounters and their local postlude.
local M = {}
local Trace = {}
Trace.__index = Trace

local function append(list, value)
    list[#list + 1] = value
end

local function result(commands)
    return { commands = commands or {} }
end

local function sorted_actor_ids(actions)
    local actor_ids = {}
    for actor_id in pairs(actions) do append(actor_ids, actor_id) end
    table.sort(actor_ids, function(left, right) return tostring(left) < tostring(right) end)
    return actor_ids
end

local function state_error(trace)
    if trace.state == 'resolved' then return 'trace-already-resolved' end
    if trace.state == 'closed' then return 'trace-already-closed' end
    return nil
end

local untrusted_authority_fields = {
    'authority_verified',
    'actor_alive',
    'within_interaction_area',
    'completed_reading',
    'reading_continuous',
    'target_current',
    'authority_proof_ref',
}

local function untrusted_authority_field(payload)
    if type(payload) ~= 'table' then return nil end
    for _, field in ipairs(untrusted_authority_fields) do
        if payload[field] ~= nil then return field end
    end
    return nil
end

local function copy_fields(source, fields)
    local copy = {}
    for _, field in ipairs(fields) do copy[field] = source[field] end
    return copy
end

local function authority_provider_valid(provider)
    return type(provider) == 'function'
        or (type(provider) == 'table' and type(provider.verify) == 'function')
end

function Trace:_authority_proof(operation, context, identity_fields)
    local provider = self.authority_provider
    if not authority_provider_valid(provider) then return nil, 'authority-provider-required' end

    local called, accepted, proof
    if type(provider) == 'function' then
        called, accepted, proof = pcall(provider, operation, context)
    else
        called, accepted, proof = pcall(provider.verify, provider, operation, context)
    end
    if not called then return nil, 'authority-provider-error' end
    if accepted ~= true or type(proof) ~= 'table' then
        return nil, 'authority-proof-rejected:' .. operation
    end
    for _, field in ipairs(identity_fields or {}) do
        if proof[field] ~= context[field] then
            return nil, 'authority-proof-mismatch:' .. field
        end
    end
    return proof
end

local trace_completion_fields = {
    'event_id', 'actor_id', 'lifecycle_id', 'combat_scope', 'encounter_instance_id',
    'target_id', 'target_lifecycle_id', 'encounter_action_key', 'action_token',
}

local function trace_event_origin(event, completed_tick)
    local parts = {}
    for _, field in ipairs(trace_completion_fields) do
        append(parts, tostring(field) .. '=' .. tostring(event[field]))
    end
    append(parts, 'completed_tick=' .. tostring(completed_tick))
    return table.concat(parts, '|')
end

local function complete_event_valid(trace, event, current_lifecycle)
    if type(event) ~= 'table' then return false, 'invalid-trace-event' end
    local untrusted = untrusted_authority_field(event)
    if untrusted then return false, 'untrusted-authority-field:' .. untrusted end
    if event.sync_tick ~= nil or event.completed_tick ~= nil then
        return false, 'caller-trace-timing-forbidden'
    end
    for _, field in ipairs(trace_completion_fields) do
        if event[field] == nil or event[field] == '' then return false, 'missing-trace-field:' .. field end
    end
    if event.combat_scope ~= 'public'
        or event.session_instance_id ~= nil or event.session_epoch ~= nil then
        return false, 'invalid-trace-scope'
    end
    if event.encounter_instance_id ~= trace.instance_id
        or event.target_id ~= trace.target_id
        or event.target_lifecycle_id ~= trace.target_lifecycle_id then
        return false, 'stale-trace-target'
    end
    if event.encounter_action_key ~= trace.action.key then return false, 'invalid-trace-action' end
    if type(current_lifecycle) ~= 'function' then return false, 'current-lifecycle-required' end
    if current_lifecycle(event.actor_id, event.lifecycle_id) ~= true then
        return false, 'stale-actor-lifecycle'
    end
    return true
end

function M.new(encounter_key, encounter, options)
    assert(type(encounter) == 'table' and encounter.encounter_type == 'public_trace', 'public trace encounter required')
    options = options or {}
    assert(options.instance_id ~= nil and options.target_id ~= nil
        and options.target_lifecycle_id ~= nil, 'trace identity is required')
    local postlude_seconds = options.postlude_seconds or 30
    assert(type(postlude_seconds) == 'number' and postlude_seconds >= 0, 'non-negative postlude_seconds required')
    return setmetatable({
        encounter_key = encounter_key,
        encounter = encounter,
        action = encounter.action,
        instance_id = options.instance_id,
        target_id = options.target_id,
        target_lifecycle_id = options.target_lifecycle_id,
        postlude_seconds = postlude_seconds,
        authority_provider = options.authority_provider,
        active_actions = {},
        credited_actors = {},
        seen_event_ids = {},
        next_token = 0,
        state = 'active',
        postlude_until = nil,
        environment_until = nil,
        resolve_reason = nil,
        ended = false,
    }, Trace)
end

local trace_begin_authority_fields = {
    'encounter_key', 'encounter_instance_id', 'target_id', 'target_lifecycle_id',
    'encounter_action_key', 'actor_id', 'lifecycle_id',
}

function Trace:begin_action(actor_id, lifecycle_id, current_lifecycle)
    local blocked = state_error(self)
    if blocked then return false, blocked end
    if type(current_lifecycle) ~= 'function' then return false, 'current-lifecycle-required' end
    if current_lifecycle(actor_id, lifecycle_id) ~= true then
        return false, 'stale-actor-lifecycle'
    end

    local context = {
        encounter_key = self.encounter_key,
        encounter_instance_id = self.instance_id,
        target_id = self.target_id,
        target_lifecycle_id = self.target_lifecycle_id,
        encounter_action_key = self.action.key,
        actor_id = actor_id,
        lifecycle_id = lifecycle_id,
    }
    local proof, proof_error = self:_authority_proof(
        'public_trace_action_begin', context, trace_begin_authority_fields)
    if not proof then return false, proof_error end
    if proof.actor_alive ~= true or proof.within_interaction_area ~= true
        or proof.target_current ~= true then
        return false, 'trace-action-not-authority-verified'
    end
    local now = proof.observed_tick
    if type(now) ~= 'number' then return false, 'trusted-trace-tick-required' end
    if self.active_actions[actor_id] then return false, 'trace-action-already-reserved' end
    local active_count = 0
    for _ in pairs(self.active_actions) do active_count = active_count + 1 end
    if active_count >= self.action.max_concurrent then return false, 'trace-action-concurrency-full' end
    local read_seconds = self.action.read_seconds
    if type(read_seconds) ~= 'number' or read_seconds < 0 then return false, 'invalid-trace-read-seconds' end
    self.next_token = self.next_token + 1
    local token = table.concat({
        tostring(self.instance_id), tostring(actor_id), tostring(lifecycle_id), tostring(self.next_token),
    }, ':')
    local ready_at = now + read_seconds
    local expires_at = ready_at
    self.active_actions[actor_id] = {
        token = token,
        actor_id = actor_id,
        lifecycle_id = lifecycle_id,
        began_at = now,
        ready_at = ready_at,
        expires_at = expires_at,
    }
    return true, {
        action_token = token,
        action_key = self.action.key,
        ready_at = ready_at,
        expires_at = expires_at,
    }
end

function Trace:complete_action(event, current_lifecycle)
    local blocked = state_error(self)
    if blocked then return false, blocked end
    local ok, error_code = complete_event_valid(self, event, current_lifecycle)
    if not ok then return false, error_code end
    local reservation = self.active_actions[event.actor_id]
    if not reservation or reservation.lifecycle_id ~= event.lifecycle_id
        or reservation.token ~= event.action_token then
        return false, 'stale-trace-reservation'
    end

    local context = copy_fields(event, trace_completion_fields)
    context.encounter_key = self.encounter_key
    context.reading_started_tick = reservation.began_at
    local identity_fields = {
        'encounter_key', 'event_id', 'actor_id', 'lifecycle_id', 'combat_scope',
        'encounter_instance_id', 'target_id', 'target_lifecycle_id',
        'encounter_action_key', 'action_token', 'reading_started_tick',
    }
    local proof, proof_error = self:_authority_proof(
        'public_trace_action_complete', context, identity_fields)
    if not proof then return false, proof_error end
    if proof.actor_alive ~= true or proof.within_interaction_area ~= true
        or proof.completed_reading ~= true or proof.reading_continuous ~= true
        or proof.target_current ~= true then
        return false, 'trace-action-not-authoritatively-complete'
    end
    if type(proof.authority_proof_ref) ~= 'string' or proof.authority_proof_ref:match('%S') == nil then
        return false, 'trusted-trace-proof-reference-required'
    end
    local now = proof.completed_tick
    if type(now) ~= 'number' then return false, 'trusted-trace-completed-tick-required' end
    if now < reservation.ready_at then return false, 'trace-reading-incomplete' end
    if now > reservation.expires_at then return false, 'trace-reading-expired' end

    local origin = trace_event_origin(event, now)
    local old_origin = self.seen_event_ids[event.event_id]
    if old_origin then
        if old_origin ~= origin then return false, 'trace-event-origin-conflict' end
        return false, 'duplicate-trace-event'
    end

    self.seen_event_ids[event.event_id] = origin
    local first_credit = not self.credited_actors[event.actor_id]
    self.credited_actors[event.actor_id] = true
    self.state = 'resolved'
    self.ended = true
    self.resolve_reason = 'action_completed'
    self.postlude_until = now + self.postlude_seconds
    self.environment_until = self.postlude_until

    local commands = {
        {
            type = 'trace_action_completed',
            event_id = event.event_id,
            actor_id = event.actor_id,
            lifecycle_id = event.lifecycle_id,
            encounter_key = self.encounter_key,
            encounter_instance_id = self.instance_id,
            target_id = self.target_id,
            target_lifecycle_id = self.target_lifecycle_id,
            encounter_action_key = event.encounter_action_key,
            action_token = event.action_token,
            combat_scope = event.combat_scope,
            completed_tick = now,
            authority_proof_ref = proof.authority_proof_ref,
            source_identity_fingerprint = origin,
            target_scope = 'explicit',
            credit_personal_progress = first_credit,
            rare_eligibility = 'none',
        },
        {
            type = 'set_trace_local_environment',
            encounter_key = self.encounter_key,
            encounter_instance_id = self.instance_id,
            duration_seconds = self.postlude_seconds,
            expires_at = self.environment_until,
        },
    }
    local cancelled = 0
    for _ in pairs(self.active_actions) do cancelled = cancelled + 1 end
    self.active_actions = {}
    if cancelled > 1 then
        append(commands, {
            type = 'cancel_trace_action_reservations',
            encounter_key = self.encounter_key,
            encounter_instance_id = self.instance_id,
            count = cancelled - 1,
            reason = 'trace_resolved',
        })
    end
    return true, result(commands)
end

function Trace:cancel_action(actor_id, lifecycle_id, token)
    local blocked = state_error(self)
    if blocked then return false, blocked end
    local reservation = self.active_actions[actor_id]
    if not reservation then return false, 'trace-action-not-reserved' end
    if reservation.lifecycle_id ~= lifecycle_id or reservation.token ~= token then
        return false, 'stale-trace-reservation'
    end
    self.active_actions[actor_id] = nil
    return true
end

function Trace:invalidate_actor(actor_id, lifecycle_id)
    if self.state ~= 'active' then return result() end
    local reservation = self.active_actions[actor_id]
    if not reservation or reservation.lifecycle_id ~= lifecycle_id then return result() end
    self.active_actions[actor_id] = nil
    return result({ {
        type = 'cancel_trace_action_reservation',
        encounter_key = self.encounter_key,
        encounter_instance_id = self.instance_id,
        actor_id = actor_id,
        lifecycle_id = lifecycle_id,
        action_token = reservation.token,
        reason = 'lifecycle_invalid',
    } })
end

function Trace:_expire_actions(now, commands)
    for _, actor_id in ipairs(sorted_actor_ids(self.active_actions)) do
        local reservation = self.active_actions[actor_id]
        if now > reservation.expires_at then
            self.active_actions[actor_id] = nil
            append(commands, {
                type = 'cancel_trace_action_reservation',
                encounter_key = self.encounter_key,
                encounter_instance_id = self.instance_id,
                actor_id = actor_id,
                lifecycle_id = reservation.lifecycle_id,
                action_token = reservation.token,
                reason = 'reading_expired',
            })
        end
    end
end

function Trace:finish(reason, now)
    if self.state == 'closed' then return nil, 'trace-already-closed' end
    if self.state == 'resolved' then
        if self.resolve_reason == nil then self.resolve_reason = reason or 'trace_resolved' end
        return result()
    end

    local resolved_reason = reason or 'trace_resolved'
    local context = {
        encounter_key = self.encounter_key,
        encounter_instance_id = self.instance_id,
        target_id = self.target_id,
        target_lifecycle_id = self.target_lifecycle_id,
        reason = resolved_reason,
        requested_tick = now,
    }
    local proof, proof_error = self:_authority_proof('public_trace_finish', context, {
        'encounter_key', 'encounter_instance_id', 'target_id', 'target_lifecycle_id', 'reason',
    })
    if not proof then return nil, proof_error end
    local observed_tick = proof.observed_tick
    if type(observed_tick) ~= 'number' then return nil, 'trusted-trace-tick-required' end

    local commands = {}
    if next(self.active_actions) ~= nil then
        append(commands, {
            type = 'cancel_trace_action_reservations',
            encounter_key = self.encounter_key,
            encounter_instance_id = self.instance_id,
            reason = resolved_reason,
        })
    end
    self.active_actions = {}
    self.state = 'resolved'
    self.ended = true
    self.resolve_reason = resolved_reason
    self.postlude_until = observed_tick + self.postlude_seconds
    return result(commands)
end

function Trace:tick(requested_tick)
    local commands = {}
    if self.state == 'closed' then return result(commands) end
    local context = {
        encounter_key = self.encounter_key,
        encounter_instance_id = self.instance_id,
        target_id = self.target_id,
        target_lifecycle_id = self.target_lifecycle_id,
        requested_tick = requested_tick,
    }
    local proof, proof_error = self:_authority_proof('public_trace_watermark', context, {
        'encounter_key', 'encounter_instance_id', 'target_id', 'target_lifecycle_id',
    })
    if not proof then
        local item = result(commands)
        item.authority_error = proof_error
        return item
    end
    local now = proof.watermark_tick
    if type(now) ~= 'number' then
        local item = result(commands)
        item.authority_error = 'trusted-trace-watermark-required'
        return item
    end
    if self.state == 'active' then
        self:_expire_actions(now, commands)
        return result(commands)
    end
    if self.state ~= 'resolved' or now < self.postlude_until then return result() end
    if self.environment_until then
        append(commands, {
            type = 'clear_trace_local_environment',
            encounter_key = self.encounter_key,
            encounter_instance_id = self.instance_id,
            reason = 'postlude_complete',
        })
        self.environment_until = nil
    end
    self.state = 'closed'
    append(commands, {
        type = 'close_public_trace',
        encounter_key = self.encounter_key,
        encounter_instance_id = self.instance_id,
        reason = self.resolve_reason or 'trace_resolved',
    })
    return result(commands)
end

return M
