-- Offline-only adapter for the canonical Huaguoshan Tide Trace completion command.
-- It deliberately owns no reward data, owner mapping, ledger state, or Y3 integration.
local M = {}
local Adapter = {}
Adapter.__index = Adapter

local canonical_fields = {
    'type',
    'event_id',
    'actor_id',
    'lifecycle_id',
    'encounter_key',
    'encounter_instance_id',
    'target_id',
    'target_lifecycle_id',
    'encounter_action_key',
    'action_token',
    'combat_scope',
    'completed_tick',
    'authority_proof_ref',
    'source_identity_fingerprint',
    'target_scope',
    'credit_personal_progress',
    'rare_eligibility',
}

local allowed_fields = {}
for _, field in ipairs(canonical_fields) do allowed_fields[field] = true end

local forbidden_fields = {
    owner_id = true,
    owner_scope = true,
    reward = true,
    rewards = true,
    grant = true,
    grants = true,
    currency_delta = true,
    material_delta = true,
    event_type = true,
    source_profile = true,
    reward_slot_key = true,
    resource_table_version = true,
    resource_table_sha256 = true,
    award_plan = true,
    award_plan_hash = true,
    receipt_id = true,
    qualification_snapshot = true,
    pity = true,
    first_clear = true,
}

local fixed_values = {
    type = 'trace_action_completed',
    encounter_key = 'HG_E_TIDE_TRACE',
    encounter_action_key = 'stabilize_tide_trace',
    combat_scope = 'public',
    target_scope = 'explicit',
    credit_personal_progress = true,
    rare_eligibility = 'none',
}

local fixed_field_order = {
    'type',
    'encounter_key',
    'encounter_action_key',
    'combat_scope',
    'target_scope',
    'credit_personal_progress',
    'rare_eligibility',
}

local function nonempty_string(value)
    return type(value) == 'string' and value:match('%S') ~= nil
end

local function canonical_identifier(value)
    -- Keep this byte-for-byte aligned with the Node contract grammar:
    -- ^[A-Za-z0-9_.:-]+$.  A hyphen at the end of a Lua character class is
    -- literal, avoiding the old ambiguous %- form that admitted '%'.
    return type(value) == 'string' and value:match('^[A-Za-z0-9_.:-]+$') ~= nil
end

local function nonnegative_safe_integer(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value >= 0
        and value <= 9007199254740991
        and value == math.floor(value)
end

local function copy_field_values(source)
    local copy = {}
    for _, field in ipairs(canonical_fields) do copy[field] = source[field] end
    return copy
end

local function unexpected_field_error(field)
    if forbidden_fields[field] then return 'forbidden-evidence-field:' .. field end
    return 'unexpected-evidence-field:' .. field
end

local function validate_canonical_evidence(evidence)
    if type(evidence) ~= 'table' then return false, 'evidence-table-required' end
    if getmetatable(evidence) ~= nil then return false, 'evidence-metatable-forbidden' end

    local unexpected = {}
    for field in pairs(evidence) do
        if type(field) ~= 'string' then return false, 'unexpected-evidence-field-key-type' end
        if not allowed_fields[field] then
            unexpected[#unexpected + 1] = field
        end
    end
    if #unexpected > 0 then
        table.sort(unexpected, function(left, right) return tostring(left) < tostring(right) end)
        return false, unexpected_field_error(unexpected[1])
    end

    for _, field in ipairs(canonical_fields) do
        if evidence[field] == nil then return false, 'missing-evidence-field:' .. field end
    end

    local identifier_fields = {
        'event_id', 'actor_id', 'encounter_instance_id', 'target_id',
        'target_lifecycle_id', 'action_token', 'authority_proof_ref',
    }
    for _, field in ipairs(identifier_fields) do
        if not canonical_identifier(evidence[field]) then return false, 'invalid-evidence-field:' .. field end
    end
    if not nonempty_string(evidence.source_identity_fingerprint) then
        return false, 'invalid-evidence-field:source_identity_fingerprint'
    end
    if not nonnegative_safe_integer(evidence.lifecycle_id) then
        return false, 'invalid-evidence-field:lifecycle_id'
    end
    if not nonnegative_safe_integer(evidence.completed_tick) then
        return false, 'invalid-evidence-field:completed_tick'
    end
    if type(evidence.credit_personal_progress) ~= 'boolean' then
        return false, 'invalid-evidence-field:credit_personal_progress'
    end

    for _, field in ipairs(fixed_field_order) do
        local expected = fixed_values[field]
        if evidence[field] ~= expected then return false, 'wrong-evidence-field:' .. field end
    end
    return true
end

local function same_canonical_evidence(left, right)
    for _, field in ipairs(canonical_fields) do
        if left[field] ~= right[field] then return false, field end
    end
    return true
end

function M.new(options)
    options = options or {}
    if type(options.verify_trace_completion) ~= 'function' then
        return nil, 'trace-completion-verifier-required'
    end
    return setmetatable({
        verify_trace_completion = options.verify_trace_completion,
    }, Adapter)
end

function Adapter:to_settlement_request(evidence)
    local accepted, error_code = validate_canonical_evidence(evidence)
    if not accepted then return false, error_code end

    local called, trusted, canonical = pcall(self.verify_trace_completion, evidence)
    if not called then return false, 'trace-completion-verifier-error' end
    if trusted ~= true or type(canonical) ~= 'table' then
        return false, 'trace-completion-not-authoritative'
    end

    local canonical_ok, canonical_error = validate_canonical_evidence(canonical)
    if not canonical_ok then return false, 'invalid-canonical-evidence:' .. canonical_error end
    local same, mismatch_field = same_canonical_evidence(evidence, canonical)
    if not same then return false, 'canonical-evidence-mismatch:' .. mismatch_field end

    return true, {
        schema_version = 1,
        source_event_type = 'trace_action_completed',
        event_type = 'drop_bundle',
        source_profile = 'HG_DROP_WATERFALL_ELITE',
        reward_slot_key = 'base_bundle',
        event_id = evidence.event_id,
        actor_id = evidence.actor_id,
        lifecycle_id = evidence.lifecycle_id,
        encounter_key = evidence.encounter_key,
        encounter_instance_id = evidence.encounter_instance_id,
        target_id = evidence.target_id,
        target_lifecycle_id = evidence.target_lifecycle_id,
        encounter_action_key = evidence.encounter_action_key,
        action_token = evidence.action_token,
        combat_scope = evidence.combat_scope,
        completed_tick = evidence.completed_tick,
        authority_proof_ref = evidence.authority_proof_ref,
        source_identity_fingerprint = evidence.source_identity_fingerprint,
        target_scope = evidence.target_scope,
        credit_personal_progress = evidence.credit_personal_progress,
        rare_eligibility = evidence.rare_eligibility,
    }
end

Adapter.adapt = Adapter.to_settlement_request
return M
