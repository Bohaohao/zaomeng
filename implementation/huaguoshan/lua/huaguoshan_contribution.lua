-- Authoritative encounter contribution schema and replay ledger.
local M = {}

local valid_scopes = { public = true, solo_instance = true, team_instance = true }
local valid_kinds = {
    final_damage = true,
    actual_break = true,
    actual_protection = true,
    encounter_action_success = true,
    mechanic_resolved = true,
}
local skill_proof_kinds = {
    final_damage = true,
    actual_break = true,
    actual_protection = true,
    mechanic_resolved = true,
}
local completion_modes = { primary = true, assist = true }
local public_instance_context_fields = {
    'instance_slot_id',
    'session_instance_id',
    'session_epoch',
    'raid_instance_id',
    'team_member_ids',
    'member_ids',
    'slot_id',
    'cleanup_token',
    'cleanup_order',
}

local function present(value)
    return value ~= nil and value ~= ''
end

local function require_fields(event, fields)
    for _, field in ipairs(fields) do
        if not present(event[field]) then return false, 'missing-encounter-field:' .. field end
    end
    return true
end

local function skill_validator_from(options)
    if type(options) == 'function' then return options end
    if type(options) == 'table' then return options.skill_validator end
    return nil
end

local function offline_test_mode_from(options)
    return type(options) == 'table' and options.offline_test_mode == true
end

local function valid_offline_skill_proof(event)
    local proof = event.offline_skill_proof
    return type(proof) == 'table' and present(proof.fixture_id)
        and proof.skill_key == event.skill_key
end

local function validate_skill_proof(event, options)
    local ok, error_code = require_fields(event, {
        'source_unit_id', 'source_unit_lifecycle_id', 'skill_key',
    })
    if not ok then return false, error_code end

    local validator = skill_validator_from(options)
    if type(validator) == 'function' then
        local called, accepted = pcall(validator, event)
        if not called or accepted ~= true then return false, 'invalid-skill-proof' end
    elseif not offline_test_mode_from(options) or not valid_offline_skill_proof(event) then
        return false, 'invalid-skill-proof'
    end
    return true
end

local function validate_scope(event)
    if not valid_scopes[event.combat_scope] then return false, 'invalid-combat-scope' end
    if event.combat_scope == 'public' then
        for _, field in ipairs(public_instance_context_fields) do
            if event[field] ~= nil then
                return false, 'public-event-carries-instance-context:' .. field
            end
        end
    elseif event.combat_scope == 'solo_instance' then
        if not present(event.instance_slot_id) or not present(event.session_instance_id) then
            return false, 'solo-event-missing-session'
        end
    elseif event.combat_scope == 'team_instance' then
        if not present(event.raid_instance_id) or type(event.team_member_ids) ~= 'table' then
            return false, 'team-event-missing-session'
        end
    end
    return true
end

local function validate_action_success(event)
    local ok, error_code = require_fields(event, {
        'window_id', 'mechanic_occurrence_id', 'encounter_action_key', 'action_token',
        'interaction_unit_id', 'interaction_unit_lifecycle_id',
        'boss_target_id', 'boss_target_lifecycle_id', 'completed_tick', 'completion_mode',
    })
    if not ok then return false, error_code end
    if event.combat_scope ~= 'public' then return false, 'invalid-action-scope' end
    if type(event.completed_tick) ~= 'number' then return false, 'invalid-action-completed-tick' end
    if not completion_modes[event.completion_mode] then return false, 'invalid-action-completion-mode' end
    return true
end

local function origin(event)
    local fields = {
        'kind', 'combat_scope', 'session_instance_id', 'session_epoch', 'instance_slot_id',
        'raid_instance_id', 'boss_instance_id', 'phase_id', 'actor_id', 'lifecycle_id', 'team_id',
        'source_unit_id', 'source_unit_lifecycle_id', 'skill_key', 'target_id',
        'target_lifecycle_id', 'boss_target_id', 'boss_target_lifecycle_id', 'sync_tick', 'value',
        'break_scope', 'protection_scope', 'mechanic_key', 'mechanic_resolution',
        'authority_verified', 'window_id', 'mechanic_occurrence_id', 'encounter_action_key',
        'action_token', 'interaction_unit_id', 'interaction_unit_lifecycle_id', 'completed_tick',
        'completion_mode',
    }
    local parts = {}
    for _, field in ipairs(fields) do
        local value = tostring(event[field])
        parts[#parts + 1] = tostring(#value) .. ':' .. value
    end
    return table.concat(parts, '|')
end

local function phase_events(seen, boss_instance_id, phase_id, create)
    local by_boss = seen[boss_instance_id]
    if not by_boss and create then
        by_boss = {}
        seen[boss_instance_id] = by_boss
    end
    if not by_boss then return nil end

    local by_phase = by_boss[phase_id]
    if not by_phase and create then
        by_phase = {}
        by_boss[phase_id] = by_phase
    end
    return by_phase
end

function M.validate(event, options)
    if type(event) ~= 'table' then return false, 'invalid-encounter-event' end
    if not valid_kinds[event.kind] then return false, 'invalid-encounter-event-kind' end

    local ok, error_code = require_fields(event, {
        'event_id', 'actor_id', 'lifecycle_id', 'combat_scope', 'boss_instance_id', 'phase_id',
    })
    if not ok then return false, error_code end
    ok, error_code = validate_scope(event)
    if not ok then return false, error_code end

    if event.kind == 'encounter_action_success' then
        return validate_action_success(event)
    end

    ok, error_code = require_fields(event, { 'target_id', 'target_lifecycle_id', 'sync_tick' })
    if not ok then return false, error_code end
    if skill_proof_kinds[event.kind] then
        ok, error_code = validate_skill_proof(event, options)
        if not ok then return false, error_code end
    end

    if event.kind == 'final_damage' then
        if type(event.value) ~= 'number' or event.value <= 0 then return false, 'invalid-damage-value' end
    elseif event.kind == 'actual_break' then
        if event.break_scope ~= 'boss_only' and event.break_scope ~= 'boss_confirmed' then
            return false, 'invalid-break-scope'
        end
        if type(event.value) ~= 'number' or event.value <= 0 then return false, 'invalid-break-value' end
    elseif event.kind == 'actual_protection' then
        if event.protection_scope ~= 'boss_guarded_direct' and event.protection_scope ~= 'boss_confirmed' then
            return false, 'invalid-protection-scope'
        end
        if type(event.value) ~= 'number' or event.value <= 0 then return false, 'invalid-protection-value' end
    elseif event.kind == 'mechanic_resolved' then
        if not present(event.mechanic_key) or not present(event.mechanic_resolution) then
            return false, 'mechanic-event-missing-key'
        end
        if event.authority_verified ~= true then return false, 'mechanic-not-authority-verified' end
    end
    return true
end

local Ledger = {}
Ledger.__index = Ledger

function M.new(options)
    options = options or {}
    return setmetatable({
        seen = {},
        skill_validator = options.skill_validator,
        offline_test_mode = options.offline_test_mode == true,
    }, Ledger)
end

function Ledger:can_accept(event)
    local ok, error_code = M.validate(event, {
        skill_validator = self.skill_validator,
        offline_test_mode = self.offline_test_mode,
    })
    if not ok then return false, error_code end

    local event_origin = origin(event)
    local events = phase_events(self.seen, event.boss_instance_id, event.phase_id, false)
    local old_origin = events and events[event.event_id]
    if old_origin then
        if old_origin ~= event_origin then return false, 'encounter-event-origin-conflict' end
        return false, 'duplicate-encounter-event'
    end
    return true, {
        event_id = event.event_id,
        event_origin = event_origin,
        boss_instance_id = event.boss_instance_id,
        phase_id = event.phase_id,
    }
end

function Ledger:commit(event, ticket)
    if type(ticket) ~= 'table' or ticket.event_id ~= event.event_id
        or ticket.boss_instance_id ~= event.boss_instance_id or ticket.phase_id ~= event.phase_id
        or ticket.event_origin ~= origin(event) then
        local ok, prepared = self:can_accept(event)
        if not ok then return false, prepared end
        ticket = prepared
    end
    local events = phase_events(self.seen, ticket.boss_instance_id, ticket.phase_id, true)
    events[ticket.event_id] = ticket.event_origin
    return true
end

function Ledger:accept(event)
    local ok, ticket = self:can_accept(event)
    if not ok then return false, ticket end
    return self:commit(event, ticket)
end

function Ledger:clear_phase(boss_instance_id, phase_id)
    local by_boss = self.seen[boss_instance_id]
    if by_boss then
        by_boss[phase_id] = nil
        if next(by_boss) == nil then self.seen[boss_instance_id] = nil end
    end
end

M.Ledger = Ledger

return M
