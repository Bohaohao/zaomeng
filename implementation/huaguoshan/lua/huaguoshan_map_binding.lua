-- Resolves declarative layout keys to opaque map references. This module owns
-- no Y3 API calls so it can be tested before a real map script root exists.
local Config = require 'huaguoshan_config'

local M = {}
local Binding = {}
Binding.__index = Binding

local function append(list, value)
    list[#list + 1] = value
end

local function sorted_keys(map)
    local result = {}
    for key in pairs(map) do append(result, key) end
    table.sort(result)
    return result
end

local function non_empty_string(value)
    return type(value) == 'string' and value:match('%S') ~= nil
end

local function stable_engine_object_id(result)
    local object_id = result.engine_object_id
    if object_id == nil and type(result.ref) == 'table' then
        object_id = result.ref.engine_object_id or result.ref.id
    end
    if object_id == nil and (type(result.ref) == 'string' or type(result.ref) == 'number') then
        object_id = result.ref
    end
    if type(object_id) == 'string' then
        if not non_empty_string(object_id) or object_id:match('^%s') or object_id:match('%s$') then return nil end
    elseif type(object_id) == 'number' then
        if object_id ~= object_id or object_id <= 0 or object_id % 1 ~= 0 then return nil end
    else
        return nil
    end
    return object_id, tostring(object_id)
end

function M.new(options)
    options = options or {}
    return setmetatable({
        options = options,
        refs = {},
        engine_object_ids = {},
        bound = false,
        missing = {},
        contract_id = nil,
    }, Binding)
end

function Binding:bind(resolver, contract_id)
    if type(resolver) ~= 'function' then return false, 'logic-resource-resolver-required' end
    if not non_empty_string(contract_id) then return false, 'layout-contract-required' end
    if contract_id ~= Config.layout_contract.id then return false, 'layout-contract-mismatch' end

    local candidate_refs = {}
    local candidate_object_ids = {}
    local candidate_missing = {}
    local seen_logic_keys = {}
    local seen_object_ids = {}
    local seen_refs = {}
    for _, key in ipairs(sorted_keys(Config.resources)) do
        local expected = Config.resources[key]
        local result = resolver(key, expected.source, expected.expected_type)
        if type(result) ~= 'table' or result.ref == nil then
            append(candidate_missing, key)
        elseif result.source ~= expected.source or result.type ~= expected.expected_type then
            return false, 'logic-resource-type-mismatch:' .. key
        else
            local logic_key = result.logic_key or key
            if not non_empty_string(logic_key) then return false, 'logic-resource-key-required:' .. key end
            if seen_logic_keys[logic_key] then return false, 'duplicate-logic-resource-key:' .. logic_key end
            if logic_key ~= key then return false, 'logic-resource-key-mismatch:' .. key end

            local object_id, normalized_object_id = stable_engine_object_id(result)
            if object_id == nil then return false, 'logic-resource-engine-object-id-required:' .. key end
            local previous_key = seen_object_ids[normalized_object_id]
            if previous_key then
                return false, 'logic-resource-engine-object-reused:' .. key .. ':' .. previous_key
            end
            if type(result.ref) == 'table' or type(result.ref) == 'userdata' then
                previous_key = seen_refs[result.ref]
                if previous_key then
                    return false, 'logic-resource-engine-object-reused:' .. key .. ':' .. previous_key
                end
                seen_refs[result.ref] = key
            end

            seen_logic_keys[logic_key] = true
            seen_object_ids[normalized_object_id] = key
            candidate_refs[key] = result.ref
            candidate_object_ids[key] = object_id
        end
    end
    if #candidate_missing > 0 then
        table.sort(candidate_missing)
        return false, 'missing-logic-resource:' .. table.concat(candidate_missing, ',')
    end

    self.refs = candidate_refs
    self.engine_object_ids = candidate_object_ids
    self.missing = {}
    self.contract_id = contract_id
    self.bound = true
    return true
end

function Binding:is_bound()
    return self.bound
end

function Binding:get(key)
    return self.refs[key]
end

function Binding:encounter_refs(encounter_key)
    if not self.bound then return nil, 'map-not-bound' end
    local encounter = Config.get_encounter(encounter_key)
    if not encounter then return nil, 'unknown-encounter' end
    local refs = {}
    for _, key in ipairs(encounter.resources or {}) do
        local ref = self.refs[key]
        if ref == nil then return nil, 'missing-encounter-resource:' .. key end
        refs[key] = ref
    end
    for _, plan in ipairs(encounter.spawn_plan or {}) do
        local ref = self.refs[plan.anchor]
        if ref == nil then return nil, 'missing-spawn-anchor:' .. plan.anchor end
        refs[plan.anchor] = ref
    end
    return refs
end

function Binding:assert_encounter_ready(encounter_key)
    local refs, error_code = self:encounter_refs(encounter_key)
    if not refs then return false, error_code end
    return true
end

return M
