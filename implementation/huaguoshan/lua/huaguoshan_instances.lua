-- Slot allocation and lifecycle cleanup for Dragon Palace and Ox Battlefield.
local M = {}
local Config = require 'huaguoshan_config'

local OX_ENCOUNTER_KEY = 'HG_E_OX_BATTLEFIELD'

local DRAGON_PROGRESS_RULES = {
    HG_E_DRAGON_OLD_TIDE = {
        min_level = 8,
        discovery_key = 'dragon_palace_entrance',
        route_completion = Config.encounters.HG_E_DRAGON_OLD_TIDE.route_completion,
        rejection = 'old-tide-progression-not-eligible',
    },
    HG_E_DRAGON_REVERSE_TIDE = {
        min_level = 38,
        progression_key = Config.encounters.HG_E_DRAGON_REVERSE_TIDE.progression_key,
        rejection = 'reverse-tide-progression-not-eligible',
    },
}

local untrusted_authority_fields = {
    'authority_verified',
    'now',
    'members',
    'member_ids',
    'member_snapshot',
    'actor_snapshot',
    'kill_verified',
    'killed',
    'cleanup_verified',
    'cleanup_acknowledged',
    'success_verified',
    'succeeded',
    'failure_verified',
    'failed',
    'phase_verified',
    'all_members_dead',
    'operation_token',
    'proof',
    'operation_proof',
    'authority_proof',
    'cleanup_token',
    'completed_tick',
    'reason',
    'profession_id',
    'route_completion',
    'route_key',
    'route_attempt_id',
    'route_completed',
}

local function append(list, value)
    list[#list + 1] = value
end

local function copy_value(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, nested in pairs(value) do
        copy[copy_value(key, seen)] = copy_value(nested, seen)
    end
    return copy
end

local function copy_members(members)
    local copy = {}
    for index, member in ipairs(members or {}) do copy[index] = copy_value(member) end
    return copy
end

local function copy_active_member_ids(members)
    local copy = {}
    for _, member in ipairs(members or {}) do
        if member.status == 'active' then
            append(copy, { actor_id = member.actor_id, lifecycle_id = member.lifecycle_id })
        end
    end
    return copy
end

-- Public instance reads must never alias authoritative session state.  The
-- map root receives cleanup capabilities only through delivered commands.
local function dragon_session_snapshot(session)
    if not session then return nil end
    return {
        encounter_key = session.encounter_key,
        combat_scope = session.combat_scope,
        state = session.state,
        slot_id = session.slot_id,
        owner_actor_id = session.owner_actor_id,
        owner_lifecycle_id = session.owner_lifecycle_id,
        session_epoch = session.session_epoch,
        session_instance_id = session.session_instance_id,
        opened_at = session.opened_at,
        deadline_at = session.deadline_at,
        return_point = session.return_point,
        end_reason = session.end_reason,
        finished_at = session.finished_at,
        cleanup_acknowledged_at = session.cleanup_acknowledged_at,
    }
end

local function ox_session_snapshot(session)
    if not session then return nil end
    local members = copy_members(session.members)
    local member_by_actor = {}
    for _, member in ipairs(members) do member_by_actor[member.actor_id] = member end
    return {
        encounter_key = session.encounter_key,
        combat_scope = session.combat_scope,
        state = session.state,
        raid_instance_id = session.raid_instance_id,
        boss_instance_id = session.boss_instance_id,
        session_epoch = session.session_epoch,
        entry_actor_id = session.entry_actor_id,
        entry_lifecycle_id = session.entry_lifecycle_id,
        members = members,
        member_by_actor = member_by_actor,
        phase_id = session.phase_id,
        opened_at = session.opened_at,
        deadline_at = session.deadline_at,
        return_point = session.return_point,
        reentry_policy = session.reentry_policy,
        rage_layers = session.rage_layers,
        rage_bonus = session.rage_bonus,
        end_reason = session.end_reason,
        failed = session.failed,
        finished_at = session.finished_at,
        cleanup_acknowledged_at = session.cleanup_acknowledged_at,
    }
end

local function sorted_numeric_keys(map)
    local keys = {}
    for key in pairs(map) do append(keys, key) end
    table.sort(keys)
    return keys
end

local function result(commands, authority_error)
    local item = { commands = commands or {} }
    if authority_error then item.authority_error = authority_error end
    return item
end

local function non_empty_string(value)
    return type(value) == 'string' and value:match('%S') ~= nil
end

local function untrusted_authority_field(payload)
    if type(payload) ~= 'table' then return nil end
    for _, field in ipairs(untrusted_authority_fields) do
        if payload[field] ~= nil then return field end
    end
    return nil
end

local function reject_untrusted_authority_fields(payload)
    local field = untrusted_authority_field(payload)
    if field then return false, 'untrusted-instance-authority-field:' .. field end
    return true
end

local function authority_provider_valid(provider)
    return type(provider) == 'function'
        or (type(provider) == 'table' and type(provider.verify) == 'function')
end

local function authority_proof(provider, operation, context, identity_fields)
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
    if proof.operation ~= operation then return nil, 'authority-proof-operation-mismatch' end
    if not non_empty_string(proof.operation_token) then
        return nil, 'authority-operation-token-required'
    end
    for _, field in ipairs(identity_fields or {}) do
        if proof[field] ~= context[field] then
            return nil, 'authority-proof-mismatch:' .. field
        end
    end
    return proof
end

local function trusted_now(proof)
    if type(proof.now) ~= 'number' then return nil, 'trusted-instance-time-required' end
    return proof.now
end

local function operation_token_available(owner, proof)
    local token = proof.operation_token
    if owner.used_authority_tokens[token] then return false, 'authority-operation-token-replayed' end
    return true
end

local function consume_operation_token(owner, scope_id, proof)
    local available, available_error = operation_token_available(owner, proof)
    if not available then return false, available_error end
    local token = proof.operation_token
    local scope = owner.authority_token_scopes[scope_id]
    if not scope then
        scope = {}
        owner.authority_token_scopes[scope_id] = scope
    end
    owner.used_authority_tokens[token] = true
    scope[token] = true
    return true
end

local function release_operation_token_scope(owner, scope_id)
    local scope = owner.authority_token_scopes[scope_id]
    if not scope then return end
    for token in pairs(scope) do owner.used_authority_tokens[token] = nil end
    owner.authority_token_scopes[scope_id] = nil
end

local function progression_query(request, rule)
    return {
        actor_id = request.actor_id,
        lifecycle_id = request.lifecycle_id,
        encounter_key = request.encounter_key,
        requirements = {
            min_level = rule.min_level,
            discovery_key = rule.discovery_key,
            progression_key = rule.progression_key,
            route_completion = copy_value(rule.route_completion),
        },
    }
end

local function dragon_identity_matches(session, identity)
    return type(identity) == 'table'
        and identity.actor_id == session.owner_actor_id
        and identity.lifecycle_id == session.owner_lifecycle_id
        and identity.session_instance_id == session.session_instance_id
        and identity.session_epoch == session.session_epoch
        and (identity.encounter_key == nil or identity.encounter_key == session.encounter_key)
end

local function dragon_identity(session)
    return {
        encounter_key = session.encounter_key,
        actor_id = session.owner_actor_id,
        lifecycle_id = session.owner_lifecycle_id,
        session_instance_id = session.session_instance_id,
        session_epoch = session.session_epoch,
    }
end

local dragon_identity_fields = {
    'encounter_key',
    'actor_id',
    'lifecycle_id',
    'session_instance_id',
    'session_epoch',
}

local DragonSlots = {}
DragonSlots.__index = DragonSlots

function M.new_dragon_slots(options)
    options = options or {}
    local count = options.slot_count or 4
    assert(count == 4, 'Dragon Palace must keep exactly four independent slots')
    return setmetatable({
        slot_count = count,
        slots = {},
        by_actor = {},
        next_epoch = 0,
        progression_validator = options.progression_validator,
        authority_provider = options.authority_provider,
        actor_lifecycle_validator = options.actor_lifecycle_validator,
        actor_conflict_validator = options.actor_conflict_validator,
        used_authority_tokens = {},
        authority_token_scopes = {},
    }, DragonSlots)
end

function DragonSlots:set_actor_conflict_validator(validator)
    self.actor_conflict_validator = validator
end

function DragonSlots:set_actor_lifecycle_validator(validator)
    self.actor_lifecycle_validator = validator
end

function DragonSlots:_actor_has_conflict(actor_id, lifecycle_id)
    return type(self.actor_conflict_validator) == 'function'
        and self.actor_conflict_validator(actor_id, lifecycle_id) == true
end

function DragonSlots:_actor_lifecycle_is_current(actor_id, lifecycle_id)
    return type(self.actor_lifecycle_validator) ~= 'function'
        or self.actor_lifecycle_validator(actor_id, lifecycle_id) == true
end

function DragonSlots:_entry_state_is_current(request, slot_id)
    if self.by_actor[request.actor_id] then return false, 'actor-already-in-dragon-session' end
    if self.slots[slot_id] then return false, 'dragon-instance-slot-no-longer-free' end
    local lifecycle_current = self:_actor_lifecycle_is_current(request.actor_id, request.lifecycle_id)
    if self.by_actor[request.actor_id] then return false, 'actor-already-in-dragon-session' end
    if self.slots[slot_id] then return false, 'dragon-instance-slot-no-longer-free' end
    if not lifecycle_current then return false, 'stale-actor-lifecycle' end
    local conflict = self:_actor_has_conflict(request.actor_id, request.lifecycle_id)
    if self.by_actor[request.actor_id] then return false, 'actor-already-in-dragon-session' end
    if self.slots[slot_id] then return false, 'dragon-instance-slot-no-longer-free' end
    if conflict then return false, 'actor-active-in-ox-instance' end
    lifecycle_current = self:_actor_lifecycle_is_current(request.actor_id, request.lifecycle_id)
    if self.by_actor[request.actor_id] then return false, 'actor-already-in-dragon-session' end
    if self.slots[slot_id] then return false, 'dragon-instance-slot-no-longer-free' end
    if not lifecycle_current then return false, 'stale-actor-lifecycle' end
    return true
end

function DragonSlots:_free_slot()
    for slot_id = 1, self.slot_count do
        if not self.slots[slot_id] then return slot_id end
    end
    return nil
end

function DragonSlots:_validate_progression(request, rule)
    if type(self.progression_validator) ~= 'function' then
        return false, 'dragon-progression-validator-required'
    end
    local allowed, error_code = self.progression_validator(progression_query(request, rule))
    if allowed ~= true then return false, error_code or rule.rejection end
    return true
end

function DragonSlots:_session_for_callback(identity)
    local session = type(identity) == 'table' and self.by_actor[identity.actor_id] or nil
    if not session then return nil, 'dragon-session-not-found' end
    if not dragon_identity_matches(session, identity) then return nil, 'stale-dragon-session' end
    return session
end

function DragonSlots:_active_session_is_current(session, identity, revision)
    if self.by_actor[session.owner_actor_id] ~= session
        or self.slots[session.slot_id] ~= session then
        return false, 'stale-dragon-session'
    end
    if session.state ~= 'active' then return false, 'dragon-cleanup-pending' end
    if not dragon_identity_matches(session, identity) or session.revision ~= revision then
        return false, 'stale-dragon-session'
    end
    return true
end

function DragonSlots:_cleanup_session_is_current(session, identity, revision)
    if self.by_actor[session.owner_actor_id] ~= session
        or self.slots[session.slot_id] ~= session then
        return false, 'dragon-session-not-found'
    end
    if session.state ~= 'cleanup_pending' then return false, 'dragon-cleanup-not-pending' end
    if not dragon_identity_matches(session, identity) or session.revision ~= revision then
        return false, 'stale-dragon-session'
    end
    return true
end

function DragonSlots:_proof(operation, context, identity_fields)
    return authority_proof(self.authority_provider, operation, context, identity_fields)
end

function DragonSlots:open(request, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    if type(request) ~= 'table' then return false, 'invalid-solo-request' end
    local trusted, trusted_error = reject_untrusted_authority_fields(request)
    if not trusted then return false, trusted_error end
    local admission = {
        encounter_key = request.encounter_key,
        actor_id = request.actor_id,
        lifecycle_id = request.lifecycle_id,
    }
    local rule = DRAGON_PROGRESS_RULES[admission.encounter_key]
    if not rule then return false, 'invalid-dragon-encounter' end
    if admission.actor_id == nil or admission.lifecycle_id == nil then return false, 'solo-owner-required' end
    if self.by_actor[admission.actor_id] then return false, 'actor-already-in-dragon-session' end
    if self:_actor_has_conflict(admission.actor_id, admission.lifecycle_id) then
        return false, 'actor-active-in-ox-instance'
    end
    local slot_id = self:_free_slot()
    if not slot_id then return false, 'dragon-instance-slots-full' end
    local entry_current, entry_error = self:_entry_state_is_current(admission, slot_id)
    if not entry_current then return false, entry_error end
    local progression_ok, progression_error = self:_validate_progression(admission, rule)
    if not progression_ok then return false, progression_error end
    entry_current, entry_error = self:_entry_state_is_current(admission, slot_id)
    if not entry_current then return false, entry_error end

    local proof, proof_error = self:_proof('dragon_entry', progression_query(admission, rule), {
        'encounter_key', 'actor_id', 'lifecycle_id',
    })
    if not proof then return false, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return false, now_error end
    entry_current, entry_error = self:_entry_state_is_current(admission, slot_id)
    if not entry_current then return false, entry_error end
    local session_epoch = self.next_epoch + 1
    local token_scope = 'dragon-session:' .. tostring(session_epoch)
    local consumed, consume_error = consume_operation_token(self, token_scope, proof)
    if not consumed then return false, consume_error end

    self.next_epoch = session_epoch
    local deadline_seconds = admission.encounter_key == 'HG_E_DRAGON_REVERSE_TIDE' and 900 or 720
    local session = {
        encounter_key = admission.encounter_key,
        combat_scope = 'solo_instance',
        state = 'active',
        slot_id = slot_id,
        owner_actor_id = admission.actor_id,
        owner_lifecycle_id = admission.lifecycle_id,
        revision = 0,
        session_epoch = session_epoch,
        session_instance_id = 'dragon:' .. tostring(slot_id) .. ':' .. tostring(session_epoch),
        cleanup_token = 'dragon-cleanup:' .. tostring(slot_id) .. ':' .. tostring(session_epoch),
        token_scope = token_scope,
        opened_at = now,
        deadline_at = now + deadline_seconds,
        return_point = 'pt_hg_teleport_hub',
    }
    self.slots[slot_id], self.by_actor[admission.actor_id] = session, session
    return true, {
        session = dragon_session_snapshot(session),
        commands = {
            {
                type = 'lock_solo_instance',
                encounter_key = session.encounter_key,
                actor_id = session.owner_actor_id,
                lifecycle_id = session.owner_lifecycle_id,
                slot_id = slot_id,
                session_instance_id = session.session_instance_id,
                session_epoch = session.session_epoch,
                cleanup_token = session.cleanup_token,
            },
            {
                type = 'enter_solo_instance',
                encounter_key = session.encounter_key,
                actor_id = session.owner_actor_id,
                lifecycle_id = session.owner_lifecycle_id,
                slot_id = slot_id,
                session_instance_id = session.session_instance_id,
                session_epoch = session.session_epoch,
                cleanup_token = session.cleanup_token,
            },
        },
    }
end

function DragonSlots:get_by_actor(actor_id)
    return dragon_session_snapshot(self.by_actor[actor_id])
end

function DragonSlots:owner_is_current(actor_id, lifecycle_id)
    local session = self.by_actor[actor_id]
    return session ~= nil
        and session.state == 'active'
        and session.owner_lifecycle_id == lifecycle_id
end

function DragonSlots:actor_is_occupying(actor_id)
    return self.by_actor[actor_id] ~= nil
end

function DragonSlots:_authorize_finish_session(session, operation, requested_reason)
    if session.state ~= 'active' then return false, 'dragon-cleanup-pending' end
    local identity = dragon_identity(session)
    local revision = session.revision
    local context = copy_value(identity)
    context.requested_reason = requested_reason
    local proof, proof_error = self:_proof(operation, context, dragon_identity_fields)
    if not proof then return false, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return false, now_error end
    local expected_reason = {
        dragon_finish = 'success',
        dragon_timeout = 'timeout',
        dragon_actor_invalidate = 'actor_invalidated',
    }
    if proof.reason ~= expected_reason[operation] then
        return false, 'authority-proof-mismatch:reason'
    end
    if proof.reason == 'timeout' and now < session.deadline_at then
        return false, 'dragon-timeout-not-reached'
    end
    local current, current_error = self:_active_session_is_current(session, identity, revision)
    if not current then return false, current_error end
    return true, {
        proof = proof,
        now = now,
        reason = proof.reason,
        identity = identity,
        revision = revision,
    }
end

function DragonSlots:_commit_finish_session(session, authorization)
    session.revision = session.revision + 1
    session.state = 'cleanup_pending'
    session.end_reason = authorization.reason
    session.finished_at = authorization.now
    return true, result({
        {
            type = 'cleanup_dragon_instance',
            encounter_key = session.encounter_key,
            combat_scope = session.combat_scope,
            actor_id = session.owner_actor_id,
            lifecycle_id = session.owner_lifecycle_id,
            slot_id = session.slot_id,
            session_instance_id = session.session_instance_id,
            session_epoch = session.session_epoch,
            cleanup_token = session.cleanup_token,
            reason = session.end_reason,
            point_key = session.return_point,
            cleanup_order = {
                'invalidate_instance_lifecycle',
                'teleport_actor',
                'clear_instance_entities',
                'clear_instance_timers_and_hooks',
            },
        },
    })
end

function DragonSlots:_finish_session(session, operation, requested_reason)
    local authorized, authorization = self:_authorize_finish_session(session, operation, requested_reason)
    if not authorized then return false, authorization end
    local current, current_error = self:_active_session_is_current(
        session, authorization.identity, authorization.revision
    )
    if not current then return false, current_error end
    local consumed, consume_error = consume_operation_token(self, session.token_scope, authorization.proof)
    if not consumed then return false, consume_error end
    return self:_commit_finish_session(session, authorization)
end

function DragonSlots:finish(event, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    if type(event) ~= 'table' then return false, 'dragon-callback-identity-required' end
    local trusted, trusted_error = reject_untrusted_authority_fields(event)
    if not trusted then return false, trusted_error end
    local session, error_code = self:_session_for_callback(event)
    if not session then return false, error_code end
    return self:_finish_session(session, 'dragon_finish', 'success')
end

function DragonSlots:invalidate_actor(actor_id, lifecycle_id, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    local prepared, plan = self:prepare_invalidate_actor(actor_id, lifecycle_id)
    if not prepared then return false, plan end
    local ready, ready_error = self:can_commit_invalidation(plan)
    if not ready then return false, ready_error end
    return self:commit_invalidation(plan)
end

function DragonSlots:prepare_invalidate_actor(actor_id, lifecycle_id)
    local session = self.by_actor[actor_id]
    if not session or session.owner_lifecycle_id ~= lifecycle_id then
        return false, 'stale-dragon-session'
    end
    local authorized, authorization = self:_authorize_finish_session(
        session, 'dragon_actor_invalidate', 'actor_invalidated'
    )
    if not authorized then return false, authorization end
    local consumed, consume_error = consume_operation_token(self, session.token_scope, authorization.proof)
    if not consumed then return false, consume_error end
    return true, {
        owner = self,
        kind = 'dragon_actor_invalidation',
        session = session,
        authorization = authorization,
    }
end

function DragonSlots:can_commit_invalidation(plan)
    if type(plan) ~= 'table'
        or plan.owner ~= self
        or plan.kind ~= 'dragon_actor_invalidation'
        or type(plan.authorization) ~= 'table' then
        return false, 'invalid-dragon-invalidation-plan'
    end
    local session = plan.session
    local current = self:_active_session_is_current(
        session, plan.authorization.identity, plan.authorization.revision
    )
    if not current then
        return false, 'stale-dragon-invalidation-plan'
    end
    return true
end

function DragonSlots:commit_invalidation(plan)
    local ready, ready_error = self:can_commit_invalidation(plan)
    if not ready then return false, ready_error end
    return self:_commit_finish_session(plan.session, plan.authorization)
end

function DragonSlots:acknowledge_cleanup(acknowledgement, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    if type(acknowledgement) ~= 'table' then return false, 'dragon-callback-identity-required' end
    local trusted, trusted_error = reject_untrusted_authority_fields(acknowledgement)
    if not trusted then return false, trusted_error end
    local session, error_code = self:_session_for_callback(acknowledgement)
    if not session then return false, error_code end
    if session.state ~= 'cleanup_pending' then return false, 'dragon-cleanup-not-pending' end

    local identity = dragon_identity(session)
    local revision = session.revision
    local context = copy_value(identity)
    context.cleanup_token = session.cleanup_token
    local proof, proof_error = self:_proof('dragon_cleanup_ack', context, {
        'encounter_key', 'actor_id', 'lifecycle_id', 'session_instance_id', 'session_epoch', 'cleanup_token',
    })
    if not proof then return false, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return false, now_error end
    local current, current_error = self:_cleanup_session_is_current(session, identity, revision)
    if not current then return false, current_error end
    local consumed, consume_error = consume_operation_token(self, session.token_scope, proof)
    if not consumed then return false, consume_error end

    session.revision = session.revision + 1
    if self.by_actor[session.owner_actor_id] == session then self.by_actor[session.owner_actor_id] = nil end
    if self.slots[session.slot_id] == session then self.slots[session.slot_id] = nil end
    session.state = 'closed'
    session.cleanup_acknowledged_at = now
    release_operation_token_scope(self, session.token_scope)
    return true, result({
        {
            type = 'release_solo_instance_lock',
            encounter_key = session.encounter_key,
            actor_id = session.owner_actor_id,
            lifecycle_id = session.owner_lifecycle_id,
            slot_id = session.slot_id,
            session_instance_id = session.session_instance_id,
            session_epoch = session.session_epoch,
            cleanup_token = session.cleanup_token,
        },
    })
end

function DragonSlots:tick(...)
    if select('#', ...) > 0 then return result({}, 'caller-instance-time-forbidden') end
    local commands = {}
    local authority_error = nil
    for _, slot_id in ipairs(sorted_numeric_keys(self.slots)) do
        local session = self.slots[slot_id]
        if session.state == 'active' then
            local identity = dragon_identity(session)
            local revision = session.revision
            local proof, proof_error = self:_proof('dragon_tick', identity, dragon_identity_fields)
            local now, now_error
            if proof then now, now_error = trusted_now(proof) end
            if not proof then
                authority_error = authority_error or proof_error
            elseif now == nil then
                authority_error = authority_error or now_error
            else
                local current, current_error = self:_active_session_is_current(session, identity, revision)
                if not current then
                    authority_error = authority_error or current_error
                else
                    local consumed, consume_error = consume_operation_token(self, session.token_scope, proof)
                    if not consumed then
                        authority_error = authority_error or consume_error
                    elseif now >= session.deadline_at then
                        local closed, item = self:_finish_session(session, 'dragon_timeout', 'timeout')
                        if closed then
                            for _, command in ipairs(item.commands) do append(commands, command) end
                        else
                            authority_error = authority_error or item
                        end
                    end
                end
            end
        end
    end
    return result(commands, authority_error)
end

local OxBattlefield = {}
OxBattlefield.__index = OxBattlefield

local function unique_members(members)
    if type(members) ~= 'table' then return nil, 'invalid-raid-member-snapshot' end
    local seen, normalized = {}, {}
    for _, member in ipairs(members) do
        if type(member) ~= 'table' or member.actor_id == nil or member.lifecycle_id == nil then
            return nil, 'invalid-raid-member'
        end
        if seen[member.actor_id] then return nil, 'duplicate-raid-member' end
        seen[member.actor_id] = true
        append(normalized, {
            actor_id = member.actor_id,
            lifecycle_id = member.lifecycle_id,
            team_id = member.team_id,
            status = 'active',
        })
    end
    if #normalized < 1 or #normalized > 4 then return nil, 'invalid-raid-member-count' end
    return normalized
end

local function ox_identity_matches(session, identity)
    return type(identity) == 'table'
        and identity.raid_instance_id == session.raid_instance_id
        and identity.session_epoch == session.session_epoch
        and identity.boss_instance_id == session.boss_instance_id
        and identity.phase_id == session.phase_id
        and (identity.encounter_key == nil or identity.encounter_key == session.encounter_key)
end

local function ox_identity(session)
    return {
        encounter_key = session.encounter_key,
        raid_instance_id = session.raid_instance_id,
        session_epoch = session.session_epoch,
        boss_instance_id = session.boss_instance_id,
        phase_id = session.phase_id,
    }
end

local ox_identity_fields = {
    'encounter_key',
    'raid_instance_id',
    'session_epoch',
    'boss_instance_id',
    'phase_id',
}

local function all_members_dead(session)
    for _, member in ipairs(session.members) do
        if member.status ~= 'dead' then return false end
    end
    return true
end

local function all_members_dead_after(session, actor_id, status)
    for _, member in ipairs(session.members) do
        local effective_status = member.actor_id == actor_id and status or member.status
        if effective_status ~= 'dead' then return false end
    end
    return true
end

function M.new_ox_battlefield(options)
    options = options or {}
    return setmetatable({
        active = nil,
        next_epoch = 0,
        next_rage_epoch = 0,
        rage = {
            layers = 0,
            expires_at = nil,
            remaining_seconds = 0,
            paused = false,
            token_scope = nil,
        },
        rage_duration_seconds = options.rage_duration_seconds or 300,
        rage_per_layer = options.rage_per_layer or 0.05,
        authority_provider = options.authority_provider,
        member_lifecycle_validator = options.member_lifecycle_validator,
        actor_conflict_validator = options.actor_conflict_validator,
        used_authority_tokens = {},
        authority_token_scopes = {},
    }, OxBattlefield)
end

function OxBattlefield:set_actor_conflict_validator(validator)
    self.actor_conflict_validator = validator
end

function OxBattlefield:_actor_has_conflict(actor_id, lifecycle_id)
    return type(self.actor_conflict_validator) == 'function'
        and self.actor_conflict_validator(actor_id, lifecycle_id) == true
end

function OxBattlefield:_entry_state_is_current(members)
    if self.active then return false, 'ox-battlefield-already-active' end
    for _, member in ipairs(members) do
        local lifecycle_current = self.member_lifecycle_validator(member.actor_id, member.lifecycle_id)
        if self.active then return false, 'ox-battlefield-already-active' end
        if lifecycle_current ~= true then return false, 'stale-raid-member-lifecycle' end
        local conflict = self:_actor_has_conflict(member.actor_id, member.lifecycle_id)
        if self.active then return false, 'ox-battlefield-already-active' end
        if conflict then return false, 'raid-member-active-in-dragon-instance' end
    end
    if self.active then return false, 'ox-battlefield-already-active' end
    return true
end

function OxBattlefield:_proof(operation, context, identity_fields)
    return authority_proof(self.authority_provider, operation, context, identity_fields)
end

function OxBattlefield:_ensure_rage_token_scope()
    if not self.rage.token_scope then
        self.next_rage_epoch = self.next_rage_epoch + 1
        self.rage.token_scope = 'ox-rage:' .. tostring(self.next_rage_epoch)
    end
    return self.rage.token_scope
end

function OxBattlefield:_clear_rage_token_scope()
    if self.rage.token_scope then
        release_operation_token_scope(self, self.rage.token_scope)
        self.rage.token_scope = nil
    end
end

function OxBattlefield:_refresh_rage(now)
    if self.rage.paused then return false end
    if self.rage.expires_at and now >= self.rage.expires_at then
        self.rage.layers, self.rage.expires_at, self.rage.remaining_seconds = 0, nil, 0
        self:_clear_rage_token_scope()
        return true
    end
    if self.rage.expires_at then self.rage.remaining_seconds = math.max(0, self.rage.expires_at - now) end
    return false
end

function OxBattlefield:_session_for_callback(identity)
    local session = self.active
    if not session then return nil, 'ox-battlefield-not-active' end
    if not ox_identity_matches(session, identity) then return nil, 'stale-ox-session' end
    return session
end

function OxBattlefield:_active_session_is_current(session, identity, revision)
    if self.active ~= session then return false, 'ox-battlefield-not-active' end
    if session.state ~= 'active' then return false, 'ox-cleanup-pending' end
    if not ox_identity_matches(session, identity) or session.revision ~= revision then
        return false, 'stale-ox-session'
    end
    return true
end

function OxBattlefield:_phase_session_is_current(session, identity, revision)
    if self.active ~= session then return false, 'ox-battlefield-not-active' end
    if session.state ~= 'active' then return false, 'ox-cleanup-pending' end
    if session.phase_id ~= 'human' then return false, 'invalid-ox-phase-swap' end
    if not ox_identity_matches(session, identity) or session.revision ~= revision then
        return false, 'stale-ox-session'
    end
    return true
end

function OxBattlefield:_cleanup_session_is_current(session, identity, revision)
    if self.active ~= session then return false, 'ox-battlefield-not-active' end
    if session.state ~= 'cleanup_pending' then return false, 'ox-cleanup-not-pending' end
    if not ox_identity_matches(session, identity) or session.revision ~= revision then
        return false, 'stale-ox-session'
    end
    return true
end

function OxBattlefield:open(request, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    if self.active then
        if type(request) == 'table' and request.actor_id ~= nil and self:member_is_occupying(request.actor_id) then
            return false, 'raid-member-reentry-locked'
        end
        return false, 'ox-battlefield-already-active'
    end
    if type(request) ~= 'table' then return false, 'raid-entry-request-required' end
    local trusted, trusted_error = reject_untrusted_authority_fields(request)
    if not trusted then return false, trusted_error end
    if not non_empty_string(request.entry_request_id) then return false, 'raid-entry-request-required' end
    if request.actor_id == nil or request.lifecycle_id == nil then return false, 'raid-entry-actor-required' end
    if self:_actor_has_conflict(request.actor_id, request.lifecycle_id) then
        return false, 'raid-member-active-in-dragon-instance'
    end

    local context = {
        encounter_key = OX_ENCOUNTER_KEY,
        entry_request_id = request.entry_request_id,
        actor_id = request.actor_id,
        lifecycle_id = request.lifecycle_id,
    }
    local proof, proof_error = self:_proof('ox_entry', context, {
        'encounter_key', 'entry_request_id', 'actor_id', 'lifecycle_id',
    })
    if not proof then return false, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return false, now_error end
    local members, member_error = unique_members(proof.member_snapshot)
    if not members then return false, 'trusted-raid-member-snapshot-invalid:' .. member_error end
    if type(self.member_lifecycle_validator) ~= 'function' then
        return false, 'raid-member-lifecycle-validator-required'
    end
    local entry_current, entry_error = self:_entry_state_is_current(members)
    if not entry_current then return false, entry_error end
    local member_by_actor = {}
    for _, member in ipairs(members) do
        member_by_actor[member.actor_id] = member
    end
    local entry_member = member_by_actor[request.actor_id]
    if not entry_member or entry_member.lifecycle_id ~= request.lifecycle_id then
        return false, 'raid-entry-actor-not-in-member-snapshot'
    end
    local session_epoch = self.next_epoch + 1
    local token_scope = 'ox-session:' .. tostring(session_epoch)
    self:_refresh_rage(now)
    local consumed, consume_error = consume_operation_token(self, token_scope, proof)
    if not consumed then return false, consume_error end

    self.next_epoch = session_epoch
    local encounter = Config.encounters[OX_ENCOUNTER_KEY]
    local session = {
        encounter_key = OX_ENCOUNTER_KEY,
        combat_scope = 'team_instance',
        state = 'active',
        raid_instance_id = 'ox-raid:' .. tostring(session_epoch),
        boss_instance_id = 'ox-boss:' .. tostring(session_epoch),
        revision = 0,
        session_epoch = session_epoch,
        cleanup_token = 'ox-cleanup:' .. tostring(session_epoch),
        token_scope = token_scope,
        entry_actor_id = request.actor_id,
        entry_lifecycle_id = request.lifecycle_id,
        members = members,
        member_by_actor = member_by_actor,
        phase_id = 'human',
        opened_at = now,
        deadline_at = now + encounter.deadline_seconds,
        return_point = encounter.return_point,
        reentry_policy = encounter.reentry_policy,
        rage_layers = self.rage.layers,
        rage_bonus = self.rage.layers * self.rage_per_layer,
    }
    self.active = session
    if self.rage.layers > 0 and self.rage.expires_at then
        self.rage.remaining_seconds = math.max(0, self.rage.expires_at - now)
        self.rage.expires_at, self.rage.paused = nil, true
    end

    return true, {
        session = ox_session_snapshot(session),
        rage_layers = session.rage_layers,
        rage_bonus = session.rage_bonus,
        commands = {
            {
                type = 'lock_raid_members',
                encounter_key = session.encounter_key,
                raid_instance_id = session.raid_instance_id,
                session_epoch = session.session_epoch,
                boss_instance_id = session.boss_instance_id,
                phase_id = session.phase_id,
                cleanup_token = session.cleanup_token,
                member_ids = copy_members(members),
                reentry_policy = session.reentry_policy,
            },
            {
                type = 'enter_team_instance',
                encounter_key = session.encounter_key,
                raid_instance_id = session.raid_instance_id,
                session_epoch = session.session_epoch,
                boss_instance_id = session.boss_instance_id,
                phase_id = session.phase_id,
                cleanup_token = session.cleanup_token,
                rage_layers = session.rage_layers,
                rage_bonus = session.rage_bonus,
            },
            {
                type = 'apply_ox_rage_layers',
                encounter_key = session.encounter_key,
                raid_instance_id = session.raid_instance_id,
                session_epoch = session.session_epoch,
                boss_instance_id = session.boss_instance_id,
                phase_id = session.phase_id,
                modifier_key = 'HG_M_OX_ARROGANCE',
                layers = session.rage_layers,
                bonus = session.rage_bonus,
            },
        },
    }
end

function OxBattlefield:get_active_session()
    return ox_session_snapshot(self.active)
end

function OxBattlefield:get_by_actor(actor_id)
    local session = self.active
    if not session or not session.member_by_actor[actor_id] then return nil end
    return ox_session_snapshot(session)
end

function OxBattlefield:member_is_current(actor_id, lifecycle_id)
    local session = self.active
    local member = session and session.member_by_actor[actor_id] or nil
    return session ~= nil
        and session.state == 'active'
        and member ~= nil
        and member.status == 'active'
        and member.lifecycle_id == lifecycle_id
end

function OxBattlefield:member_is_occupying(actor_id)
    local session = self.active
    local member = session and session.member_by_actor[actor_id] or nil
    return session ~= nil
        and session.state ~= 'closed'
        and member ~= nil
end

function OxBattlefield:prepare_invalidate_actor(actor_id, lifecycle_id)
    if not self:member_is_current(actor_id, lifecycle_id) then
        return false, 'stale-raid-member-lifecycle'
    end
    local session = self.active
    local session_identity = ox_identity(session)
    local session_revision = session.revision
    local member = session.member_by_actor[actor_id]
    local context = copy_value(session_identity)
    context.actor_id = actor_id
    context.lifecycle_id = lifecycle_id
    local proof, proof_error = self:_proof('ox_actor_invalidate', context, {
        'encounter_key', 'raid_instance_id', 'session_epoch', 'boss_instance_id', 'phase_id', 'actor_id', 'lifecycle_id',
    })
    if not proof then return false, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return false, now_error end
    if proof.member_status ~= 'dead' and proof.member_status ~= 'left' then
        return false, 'trusted-raid-member-status-required'
    end
    local current, current_error = self:_active_session_is_current(
        session, session_identity, session_revision
    )
    if not current then return false, current_error end
    if session.member_by_actor[actor_id] ~= member
        or member.status ~= 'active'
        or member.lifecycle_id ~= lifecycle_id then
        return false, 'stale-raid-member-lifecycle'
    end
    local consumed, consume_error = consume_operation_token(self, session.token_scope, proof)
    if not consumed then return false, consume_error end

    local final_wipe = proof.member_status == 'dead'
        and all_members_dead_after(session, actor_id, proof.member_status)
    local cleanup_authorization = nil
    if final_wipe then
        local cleanup_ok, cleanup = self:_authorize_cleanup(
            session, 'ox_failure', 'all_members_dead', true, true
        )
        if not cleanup_ok then return false, cleanup end
        local cleanup_consumed, cleanup_consume_error = consume_operation_token(
            self, session.token_scope, cleanup.proof
        )
        if not cleanup_consumed then return false, cleanup_consume_error end
        cleanup_authorization = cleanup
    end

    return true, {
        owner = self,
        kind = 'ox_actor_invalidation',
        session = session,
        session_identity = session_identity,
        session_revision = session_revision,
        member = member,
        actor_id = actor_id,
        lifecycle_id = lifecycle_id,
        member_status = proof.member_status,
        invalidated_at = now,
        cleanup_authorization = cleanup_authorization,
    }
end

function OxBattlefield:can_commit_invalidation(plan)
    if type(plan) ~= 'table'
        or plan.owner ~= self
        or plan.kind ~= 'ox_actor_invalidation'
        or type(plan.session_identity) ~= 'table'
        or type(plan.session_revision) ~= 'number' then
        return false, 'invalid-ox-invalidation-plan'
    end
    local session = plan.session
    local member = session and session.member_by_actor[plan.actor_id] or nil
    if session ~= self.active
        or session.state ~= 'active'
        or not ox_identity_matches(session, plan.session_identity)
        or session.revision ~= plan.session_revision
        or member ~= plan.member
        or member.status ~= 'active'
        or member.lifecycle_id ~= plan.lifecycle_id then
        return false, 'stale-ox-invalidation-plan'
    end
    if plan.cleanup_authorization
        and (plan.member_status ~= 'dead'
            or not all_members_dead_after(session, plan.actor_id, plan.member_status)) then
        return false, 'stale-ox-invalidation-plan'
    end
    return true
end

function OxBattlefield:commit_invalidation(plan)
    local ready, ready_error = self:can_commit_invalidation(plan)
    if not ready then return false, ready_error end

    local session = plan.session
    local member = plan.member
    member.status = plan.member_status
    member.invalidated_at = plan.invalidated_at
    session.revision = session.revision + 1
    local commands = {
        {
            type = 'mark_raid_member_unavailable',
            encounter_key = session.encounter_key,
            actor_id = plan.actor_id,
            lifecycle_id = plan.lifecycle_id,
            member_status = member.status,
            raid_instance_id = session.raid_instance_id,
            session_epoch = session.session_epoch,
            boss_instance_id = session.boss_instance_id,
            phase_id = session.phase_id,
            reentry_policy = session.reentry_policy,
            revive_and_teleport = member.status == 'dead' or nil,
            point_key = member.status == 'dead' and session.return_point or nil,
        },
    }

    if plan.cleanup_authorization then
        local committed_cleanup = self:_commit_cleanup(session, plan.cleanup_authorization)
        for _, command in ipairs(committed_cleanup.commands) do append(commands, command) end
        local outcome = result(commands)
        outcome.rage_layers = committed_cleanup.rage_layers
        outcome.rage_bonus = committed_cleanup.rage_bonus
        return true, outcome
    end

    return true, result(commands)
end

function OxBattlefield:invalidate_actor(actor_id, lifecycle_id, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    local prepared, plan = self:prepare_invalidate_actor(actor_id, lifecycle_id)
    if not prepared then return false, plan end
    local ready, ready_error = self:can_commit_invalidation(plan)
    if not ready then return false, ready_error end
    return self:commit_invalidation(plan)
end

function OxBattlefield:swap_to_white_ox(identity, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    if type(identity) ~= 'table' then return false, 'ox-callback-identity-required' end
    local trusted, trusted_error = reject_untrusted_authority_fields(identity)
    if not trusted then return false, trusted_error end
    local session, error_code = self:_session_for_callback(identity)
    if not session then return false, error_code end
    if session.state ~= 'active' then return false, 'ox-cleanup-pending' end
    if session.phase_id ~= 'human' then return false, 'invalid-ox-phase-swap' end

    local identity = ox_identity(session)
    local revision = session.revision
    local context = copy_value(identity)
    context.requested_phase_id = 'white_ox'
    local proof, proof_error = self:_proof('ox_phase_swap', context, ox_identity_fields)
    if not proof then return false, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return false, now_error end
    if proof.next_phase_id ~= 'white_ox' then return false, 'authority-proof-mismatch:next_phase_id' end
    local current, current_error = self:_phase_session_is_current(session, identity, revision)
    if not current then return false, current_error end
    local consumed, consume_error = consume_operation_token(self, session.token_scope, proof)
    if not consumed then return false, consume_error end

    session.revision = session.revision + 1
    session.phase_id = 'white_ox'
    session.phase_changed_at = now
    return true, result({
        {
            type = 'swap_ox_phase',
            encounter_key = session.encounter_key,
            raid_instance_id = session.raid_instance_id,
            session_epoch = session.session_epoch,
            boss_instance_id = session.boss_instance_id,
            previous_phase_id = 'human',
            phase_id = session.phase_id,
            cleanup_token = session.cleanup_token,
            preserve_members = true,
            rage_layers = session.rage_layers,
        },
    })
end

function OxBattlefield:_authorize_cleanup(session, operation, reason, failed, wipe_confirmed)
    if session.state ~= 'active' then return false, 'ox-cleanup-pending' end
    local identity = ox_identity(session)
    local revision = session.revision
    local context = copy_value(identity)
    context.requested_reason = reason
    local proof, proof_error = self:_proof(operation, context, ox_identity_fields)
    if not proof then return false, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return false, now_error end
    if proof.reason ~= reason then return false, 'authority-proof-mismatch:reason' end
    if reason == 'all_members_dead' then
        if proof.all_members_dead ~= true or wipe_confirmed ~= true then
            return false, 'ox-wipe-not-authoritative'
        end
    elseif reason == 'timeout' and now < session.deadline_at then
        return false, 'ox-timeout-not-reached'
    end
    local current, current_error = self:_active_session_is_current(session, identity, revision)
    if not current then return false, current_error end
    return true, {
        proof = proof,
        now = now,
        reason = reason,
        failed = failed,
        identity = identity,
        revision = revision,
    }
end

function OxBattlefield:_commit_cleanup(session, authorization)
    local now = authorization.now
    local reason = authorization.reason
    local failed = authorization.failed
    session.revision = session.revision + 1
    session.state = 'cleanup_pending'
    session.end_reason = reason
    session.failed = failed
    session.finished_at = now
    if failed then
        self:_ensure_rage_token_scope()
        self.rage.layers = self.rage.layers + 1
        self.rage.remaining_seconds = self.rage_duration_seconds
        self.rage.expires_at = now + self.rage_duration_seconds
        self.rage.paused = false
    else
        self.rage.layers, self.rage.expires_at, self.rage.remaining_seconds, self.rage.paused = 0, nil, 0, false
        self:_clear_rage_token_scope()
    end

    local teleport_member_ids = {}
    if failed then teleport_member_ids = copy_active_member_ids(session.members) end
    local cleanup_order = { 'invalidate_instance_lifecycle' }
    if #teleport_member_ids > 0 then append(cleanup_order, 'teleport_raid_members') end
    append(cleanup_order, 'clear_instance_entities')
    append(cleanup_order, 'clear_instance_timers_and_hooks')

    return {
        rage_layers = self.rage.layers,
        rage_bonus = self.rage.layers * self.rage_per_layer,
        commands = {
            {
                type = 'cleanup_ox_raid',
                encounter_key = session.encounter_key,
                combat_scope = session.combat_scope,
                raid_instance_id = session.raid_instance_id,
                session_epoch = session.session_epoch,
                boss_instance_id = session.boss_instance_id,
                phase_id = session.phase_id,
                cleanup_token = session.cleanup_token,
                member_ids = copy_members(session.members),
                reason = reason,
                failed = failed,
                teleport_members = #teleport_member_ids > 0,
                teleport_member_ids = teleport_member_ids,
                point_key = session.return_point,
                reentry_policy = session.reentry_policy,
                cleanup_order = cleanup_order,
            },
        },
    }
end

function OxBattlefield:_begin_cleanup(session, operation, reason, failed)
    local wipe_confirmed = reason ~= 'all_members_dead' or all_members_dead(session)
    local authorized, authorization = self:_authorize_cleanup(
        session, operation, reason, failed, wipe_confirmed
    )
    if not authorized then return false, authorization end
    local current, current_error = self:_active_session_is_current(
        session, authorization.identity, authorization.revision
    )
    if not current then return false, current_error end
    local consumed, consume_error = consume_operation_token(self, session.token_scope, authorization.proof)
    if not consumed then return false, consume_error end
    return true, self:_commit_cleanup(session, authorization)
end

function OxBattlefield:fail(event, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    if type(event) ~= 'table' then return false, 'ox-callback-identity-required' end
    local trusted, trusted_error = reject_untrusted_authority_fields(event)
    if not trusted then return false, trusted_error end
    local session, error_code = self:_session_for_callback(event)
    if not session then return false, error_code end
    return self:_begin_cleanup(session, 'ox_failure', 'all_members_dead', true)
end

function OxBattlefield:succeed(identity, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    if type(identity) ~= 'table' then return false, 'ox-callback-identity-required' end
    local trusted, trusted_error = reject_untrusted_authority_fields(identity)
    if not trusted then return false, trusted_error end
    local session, error_code = self:_session_for_callback(identity)
    if not session then return false, error_code end
    return self:_begin_cleanup(session, 'ox_success', 'success', false)
end

function OxBattlefield:acknowledge_cleanup(acknowledgement, ...)
    if select('#', ...) > 0 then return false, 'caller-instance-time-forbidden' end
    if type(acknowledgement) ~= 'table' then return false, 'ox-callback-identity-required' end
    local trusted, trusted_error = reject_untrusted_authority_fields(acknowledgement)
    if not trusted then return false, trusted_error end
    local session, error_code = self:_session_for_callback(acknowledgement)
    if not session then return false, error_code end
    if session.state ~= 'cleanup_pending' then return false, 'ox-cleanup-not-pending' end

    local identity = ox_identity(session)
    local revision = session.revision
    local context = copy_value(identity)
    context.cleanup_token = session.cleanup_token
    local proof, proof_error = self:_proof('ox_cleanup_ack', context, {
        'encounter_key', 'raid_instance_id', 'session_epoch', 'boss_instance_id', 'phase_id', 'cleanup_token',
    })
    if not proof then return false, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return false, now_error end
    local current, current_error = self:_cleanup_session_is_current(session, identity, revision)
    if not current then return false, current_error end
    local consumed, consume_error = consume_operation_token(self, session.token_scope, proof)
    if not consumed then return false, consume_error end

    session.revision = session.revision + 1
    if self.active == session then self.active = nil end
    session.state = 'closed'
    session.cleanup_acknowledged_at = now
    release_operation_token_scope(self, session.token_scope)
    return true, result({
        {
            type = 'release_raid_member_locks',
            encounter_key = session.encounter_key,
            raid_instance_id = session.raid_instance_id,
            session_epoch = session.session_epoch,
            boss_instance_id = session.boss_instance_id,
            phase_id = session.phase_id,
                cleanup_token = session.cleanup_token,
                member_ids = copy_members(session.members),
                release_reentry_lock = true,
            },
    })
end

function OxBattlefield:tick(...)
    if select('#', ...) > 0 then return result({}, 'caller-instance-time-forbidden') end
    local commands = {}
    local session = self.active
    local authority_error = nil
    if session and session.state == 'active' then
        local identity = ox_identity(session)
        local revision = session.revision
        local proof, proof_error = self:_proof('ox_tick', identity, ox_identity_fields)
        local now, now_error
        if proof then now, now_error = trusted_now(proof) end
        if not proof then
            authority_error = proof_error
        elseif now == nil then
            authority_error = now_error
        else
            local current, current_error = self:_active_session_is_current(session, identity, revision)
            if not current then
                authority_error = current_error
            else
                local consumed, consume_error = consume_operation_token(self, session.token_scope, proof)
                if not consumed then
                    authority_error = consume_error
                elseif now >= session.deadline_at then
                    local cleanup_ok, cleanup = self:_begin_cleanup(session, 'ox_timeout', 'timeout', true)
                    if cleanup_ok then
                        for _, command in ipairs(cleanup.commands) do append(commands, command) end
                    else
                        authority_error = cleanup
                    end
                end
            end
        end
    elseif self.rage.expires_at ~= nil or self.rage.layers > 0 then
        local proof, proof_error = self:_proof('ox_rage_tick', {
            encounter_key = OX_ENCOUNTER_KEY,
        }, { 'encounter_key' })
        local now, now_error
        if proof then now, now_error = trusted_now(proof) end
        if not proof then
            authority_error = proof_error
        elseif now == nil then
            authority_error = now_error
        elseif self.active ~= nil then
            authority_error = 'ox-battlefield-already-active'
        else
            local rage_token_scope = self:_ensure_rage_token_scope()
            local consumed, consume_error = consume_operation_token(self, rage_token_scope, proof)
            if not consumed then
                authority_error = consume_error
            elseif self:_refresh_rage(now) then
                append(commands, {
                    type = 'clear_ox_arrogance',
                    encounter_key = OX_ENCOUNTER_KEY,
                    modifier_key = 'HG_M_OX_ARROGANCE',
                })
            end
        end
    end
    return result(commands, authority_error)
end

function OxBattlefield:rage_state(...)
    if select('#', ...) > 0 then return nil, 'caller-instance-time-forbidden' end
    local proof, proof_error = self:_proof('ox_rage_state', {
        encounter_key = OX_ENCOUNTER_KEY,
    }, { 'encounter_key' })
    if not proof then return nil, proof_error end
    local now, now_error = trusted_now(proof)
    if now == nil then return nil, now_error end
    local token_scope = self.active and self.active.token_scope or nil
    if not token_scope and (self.rage.expires_at ~= nil or self.rage.layers > 0) then
        token_scope = self:_ensure_rage_token_scope()
    end
    if token_scope then
        local consumed, consume_error = consume_operation_token(self, token_scope, proof)
        if not consumed then return nil, consume_error end
    end
    self:_refresh_rage(now)
    return {
        layers = self.rage.layers,
        bonus = self.rage.layers * self.rage_per_layer,
        remaining_seconds = self.rage.remaining_seconds,
        paused = self.rage.paused,
    }
end

return M
