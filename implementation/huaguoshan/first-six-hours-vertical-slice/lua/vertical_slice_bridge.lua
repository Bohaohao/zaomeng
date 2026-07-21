-- custom-built: offline bridge from a trusted Tide Trace completion to growth settlement.
-- Dependencies are injected so this package remains engine-neutral and has no Y3 API surface.
local M = {}
local Bridge = {}
Bridge.__index = Bridge

local EVIDENCE_CONTRACT_ID = 'growth-public-eligibility-evidence-v1'
local SETTLEMENT_CONTRACT_VERSION = 'growth-reward-settlement-request-v1'
local TRACE_ENCOUNTER_KEY = 'HG_E_TIDE_TRACE'
local TRACE_PROFILE = 'HG_DROP_WATERFALL_ELITE'
local TRACE_REWARD_SLOT = 'trace_completion'
local OFFLINE_CANDIDATE_PACKAGE_STATUS = 'offline_candidate_simulation_not_adopted'
local OFFLINE_CANDIDATE_RESOURCE_TABLE_STATUS = 'offline_candidate_not_adopted'

local function non_empty_string(value)
    return type(value) == 'string' and value ~= '' and value == value:match('^%s*(.-)%s*$')
end

local function length_part(value)
    local text = tostring(value)
    return tostring(#text) .. ':' .. text
end

local function identity(parts)
    local output = {}
    for index, value in ipairs(parts) do output[index] = length_part(value) end
    return table.concat(output, '|')
end

local function copy_table(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function is_offline_candidate_growth_runtime(growth_runtime)
    local config = type(growth_runtime) == 'table' and growth_runtime.Config or nil
    return type(config) == 'table'
        and config.package_status == OFFLINE_CANDIDATE_PACKAGE_STATUS
        and config.production_gate == 'closed'
        and config.runtime_handoff == false
        and config.resource_table_status == OFFLINE_CANDIDATE_RESOURCE_TABLE_STATUS
end

local function validate_completion_evidence(event, evidence)
    if type(event) ~= 'table' or type(evidence) ~= 'table' then return false, 'missing-or-untrusted-eligibility-evidence' end
    local string_fields = {
        'event_id', 'actor_id', 'encounter_key', 'encounter_instance_id', 'target_id',
        'encounter_action_key', 'action_token', 'combat_scope', 'authority_proof_ref',
        'source_identity_fingerprint',
    }
    for _, field in ipairs(string_fields) do
        if not non_empty_string(evidence[field]) then return false, 'missing-evidence-field:' .. field end
    end
    for _, field in ipairs({ 'lifecycle_id', 'target_lifecycle_id' }) do
        if not non_empty_string(evidence[field]) and type(evidence[field]) ~= 'number' then
            return false, 'missing-evidence-field:' .. field
        end
    end
    if type(evidence.completed_tick) ~= 'number'
        or evidence.completed_tick ~= evidence.completed_tick
        or evidence.completed_tick < 0 then
        return false, 'invalid-evidence-completed-tick'
    end
    if evidence.encounter_key ~= TRACE_ENCOUNTER_KEY or evidence.combat_scope ~= 'public' then
        return false, 'invalid-trace-evidence-scope'
    end
    local event_fields = {
        'event_id', 'actor_id', 'lifecycle_id', 'encounter_instance_id', 'target_id',
        'target_lifecycle_id', 'encounter_action_key', 'action_token', 'combat_scope',
    }
    for _, field in ipairs(event_fields) do
        if evidence[field] ~= event[field] then return false, 'evidence-event-mismatch:' .. field end
    end
    if evidence.encounter_action_key ~= 'stabilize_tide_trace' then return false, 'invalid-trace-evidence-action' end
    return true
end

local function validate_request_fields(request)
    if type(request) ~= 'table' then return false, 'invalid-settlement-request' end
    local required = {
        'request_id', 'idempotency_key', 'owner_scope', 'owner_id', 'event_id',
        'encounter_instance_id', 'qualification_snapshot_id', 'resource_table_version',
        'source_profile', 'reward_slot_key', 'eligibility_evidence_contract_id',
        'eligibility_evidence_ref', 'reward_grant_ref',
    }
    for _, field in ipairs(required) do
        if not non_empty_string(request[field]) then return false, 'missing-settlement-field:' .. field end
    end
    if request.schema_version ~= 1 then return false, 'unsupported-settlement-schema-version' end
    if request.settlement_contract_version ~= SETTLEMENT_CONTRACT_VERSION then
        return false, 'unsupported-settlement-contract-version'
    end
    if request.eligibility_evidence_contract_id ~= EVIDENCE_CONTRACT_ID
        or request.eligibility_evidence_schema_version ~= 1 then
        return false, 'unsupported-eligibility-evidence-contract'
    end
    if request.source_profile ~= TRACE_PROFILE then return false, 'invalid-trace-source-profile' end
    if request.reward_slot_key ~= TRACE_REWARD_SLOT then return false, 'invalid-trace-reward-slot' end
    local prohibited = {
        'xp_amount', 'experience_amount', 'currency_amount', 'material_amount', 'item_quantity',
        'drop_rate', 'drop_probability', 'pity_increment', 'pity_threshold',
    }
    for _, field in ipairs(prohibited) do
        if request[field] ~= nil then return false, 'inline-reward-field-forbidden:' .. field end
    end
    return true
end

function M.qualification_snapshot_id(owner_id, source_identity_fingerprint)
    if not non_empty_string(owner_id) or not non_empty_string(source_identity_fingerprint) then return nil end
    return identity({ 'trace-snapshot', owner_id, source_identity_fingerprint })
end

function M.new(options)
    options = options or {}
    if type(options.verify_trace_completion) ~= 'function' then return nil, 'trace-completion-verifier-required' end
    if type(options.growth_runtime) ~= 'table' or type(options.growth_runtime.settle_reward) ~= 'function'
        or type(options.growth_runtime.Config) ~= 'table' then
        return nil, 'growth-runtime-required'
    end
    if not is_offline_candidate_growth_runtime(options.growth_runtime) then
        return nil, 'growth-runtime-not-offline-candidate'
    end
    return setmetatable({
        verify_trace_completion = options.verify_trace_completion,
        growth_runtime = options.growth_runtime,
        requests_by_idempotency = {},
        requests_by_id = {},
        request_id_by_source_identity = {},
    }, Bridge)
end

function Bridge:settle_trace_completion(state, request)
    if not is_offline_candidate_growth_runtime(self.growth_runtime) then
        return false, 'growth-runtime-not-offline-candidate'
    end
    local request_ok, request_error = validate_request_fields(request)
    if not request_ok then return false, request_error end
    if request.owner_scope ~= self.growth_runtime.Config.owner_scope then return false, 'invalid-owner-scope' end
    if request.resource_table_version ~= self.growth_runtime.Config.resource_table_version then
        return false, 'resource-table-version-unavailable'
    end

    local verified, evidence = self.verify_trace_completion(request.completion_event)
    if verified ~= true then return false, evidence or 'missing-or-untrusted-eligibility-evidence' end
    local evidence_ok, evidence_error = validate_completion_evidence(request.completion_event, evidence)
    if not evidence_ok then return false, evidence_error end
    if request.owner_id ~= evidence.actor_id then
        return false, 'owner-evidence-actor-mismatch'
    end
    if request.event_id ~= evidence.event_id then return false, 'settlement-event-mismatch' end
    if request.encounter_instance_id ~= evidence.encounter_instance_id then
        return false, 'settlement-instance-mismatch'
    end
    if request.eligibility_evidence_ref ~= evidence.source_identity_fingerprint then
        return false, 'eligibility-evidence-reference-mismatch'
    end

    local qualification_snapshot_id = M.qualification_snapshot_id(request.owner_id, evidence.source_identity_fingerprint)
    if request.qualification_snapshot_id ~= qualification_snapshot_id then
        return false, 'qualification-snapshot-mismatch'
    end
    local source_identity = identity({
        request.owner_scope, request.owner_id, evidence.event_id, evidence.source_identity_fingerprint,
        request.source_profile, request.reward_slot_key, request.resource_table_version,
    })
    local origin = identity({
        request.request_id, request.idempotency_key, source_identity, qualification_snapshot_id,
        request.reward_grant_ref,
    })
    local by_idempotency = self.requests_by_idempotency[request.idempotency_key]
    if by_idempotency then
        if by_idempotency.origin ~= origin then return false, 'duplicate-request-identity-conflict' end
        local replay = copy_table(by_idempotency.receipt)
        replay.settlement_status = 'duplicate_replayed'
        return true, replay, true
    end
    local by_request_id = self.requests_by_id[request.request_id]
    if by_request_id and by_request_id.origin ~= origin then return false, 'duplicate-request-identity-conflict' end
    local existing_idempotency = self.request_id_by_source_identity[source_identity]
    if existing_idempotency and existing_idempotency ~= request.idempotency_key then
        return false, 'duplicate-request-identity-conflict'
    end

    local settled, outcome, replayed = self.growth_runtime.settle_reward(state, {
        owner_scope = request.owner_scope,
        owner_id = request.owner_id,
        event_id = evidence.event_id,
        profile_key = request.source_profile,
        reward_slot_key = request.reward_slot_key,
        resource_table_version = request.resource_table_version,
        qualification_snapshot_id = qualification_snapshot_id,
        encounter_qualified = true,
    })
    if not settled then return false, outcome end

    local settlement_status = 'settled'
    if replayed then settlement_status = 'duplicate_replayed' end
    local receipt = {
        schema_version = 1,
        settlement_contract_version = SETTLEMENT_CONTRACT_VERSION,
        receipt_id = outcome.receipt_id,
        request_id = request.request_id,
        idempotency_key = request.idempotency_key,
        owner_scope = request.owner_scope,
        owner_id = request.owner_id,
        event_id = evidence.event_id,
        encounter_instance_id = evidence.encounter_instance_id,
        qualification_snapshot_id = qualification_snapshot_id,
        resource_table_version = request.resource_table_version,
        source_profile = request.source_profile,
        reward_slot_key = request.reward_slot_key,
        settlement_status = settlement_status,
        settlement_ledger_ref = outcome.receipt_id,
        eligibility_evidence_contract_id = EVIDENCE_CONTRACT_ID,
        eligibility_evidence_schema_version = 1,
        eligibility_evidence_ref = evidence.source_identity_fingerprint,
    }
    local stored = { origin = origin, receipt = receipt }
    self.requests_by_idempotency[request.idempotency_key] = stored
    self.requests_by_id[request.request_id] = stored
    self.request_id_by_source_identity[source_identity] = request.idempotency_key
    return true, copy_table(receipt), false
end

M.EVIDENCE_CONTRACT_ID = EVIDENCE_CONTRACT_ID
M.SETTLEMENT_CONTRACT_VERSION = SETTLEMENT_CONTRACT_VERSION
M.TRACE_ENCOUNTER_KEY = TRACE_ENCOUNTER_KEY
M.TRACE_PROFILE = TRACE_PROFILE
M.TRACE_REWARD_SLOT = TRACE_REWARD_SLOT

return M
