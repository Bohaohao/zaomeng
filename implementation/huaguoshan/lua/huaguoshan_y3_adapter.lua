-- The future Y3 boundary. All engine work is injected by the real map root;
-- this offline package deliberately contains no direct engine namespace calls.
local Config = require 'huaguoshan_config'

local M = {}
local Adapter = {}
Adapter.__index = Adapter

M.LIVE_DELIVERY_CONTRACT = 'delivery_id_ack_reconciliation_v1'

local LIVE_GATES = {
    { name = 'real_map_binding_verified', error_code = 'real-map-binding-not-verified' },
    { name = 'production_ids_ready', error_code = 'production-ids-not-ready' },
    { name = 'y3editor_connected', error_code = 'y3editor-not-connected' },
    { name = 'map_logic_resources_verified', error_code = 'map-logic-resources-not-verified' },
    { name = 'unit_ids_assigned', error_code = 'unit-ids-not-assigned' },
    { name = 'ability_ids_assigned', error_code = 'ability-ids-not-assigned' },
    { name = 'modifier_ids_assigned', error_code = 'modifier-ids-not-assigned' },
    { name = 'projectile_ids_assigned', error_code = 'projectile-ids-not-assigned' },
    { name = 'model_ids_assigned', error_code = 'model-ids-not-assigned' },
    { name = 'icon_ids_assigned', error_code = 'icon-ids-not-assigned' },
    { name = 'effect_resources_assigned', error_code = 'effect-resources-not-assigned' },
    { name = 'encounter_runtime_bound', error_code = 'encounter-runtime-not-bound' },
    { name = 'distance_scale_verified', error_code = 'distance-scale-not-verified' },
    { name = 'instance_map_contract_verified', error_code = 'instance-map-contract-not-verified' },
    { name = 'authoritative_progression_validator_bound', error_code = 'authoritative-progression-validator-not-bound' },
}

local function append(list, value)
    list[#list + 1] = value
end

local function sorted_keys(map)
    local keys = {}
    for key in pairs(map or {}) do append(keys, key) end
    table.sort(keys)
    return keys
end

local function supported_mode(mode)
    return mode == 'offline_test' or mode == 'live'
end

local function gate_value(options, name)
    if options[name] ~= nil then return options[name] end
    if type(options.execution_gates) == 'table' then return options.execution_gates[name] end
    return nil
end

local function non_empty_string(value)
    return type(value) == 'string' and value:match('%S') ~= nil
end

local function stable_object_id(binding)
    if type(binding) ~= 'table' then return nil end
    local object_id = binding.engine_object_id
    local ref = binding.ref
    if object_id == nil and type(ref) == 'table' then object_id = ref.engine_object_id or ref.id end
    if object_id == nil and (type(ref) == 'string' or type(ref) == 'number') then object_id = ref end
    if type(object_id) == 'string' then
        if not non_empty_string(object_id) or object_id:match('^%s') or object_id:match('%s$') then return nil end
    elseif type(object_id) == 'number' then
        if object_id ~= object_id or object_id <= 0 or object_id % 1 ~= 0 then return nil end
    else
        return nil
    end
    return object_id, type(object_id) .. ':' .. tostring(object_id)
end

function M.new(options)
    options = options or {}
    return setmetatable({
        options = options,
        mode = options.mode,
        binding = nil,
        owner_hooks = {},
        emitted_commands = {},
        delivered_command_ids = {},
        unknown_command_deliveries = {},
    }, Adapter)
end

function Adapter:_validate_mode()
    if not supported_mode(self.mode) then return false, 'unsupported-adapter-mode' end
    return true
end

function Adapter:_validate_live_gates()
    if self.mode ~= 'live' then return false, self.mode == 'offline_test' and 'offline-test-mode' or 'unsupported-adapter-mode' end
    for _, gate in ipairs(LIVE_GATES) do
        local value = gate_value(self.options, gate.name)
        if type(value) ~= 'boolean' then return false, 'live-gate-not-boolean:' .. gate.name end
        if value ~= true then return false, gate.error_code end
    end
    return true
end

function Adapter:_validate_live_instance_map_contract(encounter_key, encounter, global_object_ids)
    if encounter.combat_scope ~= 'solo_instance' and encounter.combat_scope ~= 'team_instance' then return true end
    local contract, contract_key = Config.get_instance_map_contract(encounter_key)
    local role_schema = Config.instance_contract_role_schema[contract_key]
    if encounter.instance_map_contract ~= 'verified'
        or type(contract) ~= 'table'
        or contract.state ~= 'verified' then
        return false, 'instance-map-contract-state-not-verified:' .. encounter_key
    end
    if type(role_schema) ~= 'table' or type(role_schema.roles) ~= 'table'
        or contract.layer ~= role_schema.layer or contract.slot_count ~= role_schema.slot_count then
        return false, 'instance-map-contract-role-schema-invalid:' .. tostring(contract_key)
    end
    local contract_contains_encounter = false
    for _, key in ipairs(contract.encounter_keys or {}) do
        if key == encounter_key then contract_contains_encounter = true break end
    end
    if not contract_contains_encounter then
        return false, 'instance-map-contract-encounter-not-member:' .. tostring(encounter_key)
    end
    if type(self.options.resolve_instance_map_role) ~= 'function' then
        return false, 'instance-map-role-resolver-required'
    end
    if type(contract.slot_count) ~= 'number' or contract.slot_count <= 0 or contract.slot_count % 1 ~= 0
        or type(contract.slots) ~= 'table' or #contract.slots ~= contract.slot_count then
        return false, 'instance-map-contract-slots-invalid:' .. encounter_key
    end
    local used_object_ids = global_object_ids or {}
    local used_resource_keys = {}
    local used_slot_ids = {}
    local required_role_count = 0
    for _ in pairs(role_schema.roles) do required_role_count = required_role_count + 1 end
    for _, slot in ipairs(contract.slots) do
        local slot_id = slot.slot_id
        if type(slot_id) ~= 'number' or slot_id <= 0 or slot_id % 1 ~= 0 or slot_id > contract.slot_count
            or used_slot_ids[slot_id] or type(slot.roles) ~= 'table' then
            return false, 'instance-map-contract-slot-invalid:' .. encounter_key
        end
        if #slot.roles ~= required_role_count then
            return false, 'instance-map-contract-role-schema-invalid:' .. tostring(contract_key) .. ':'
                .. tostring(slot_id)
        end
        used_slot_ids[slot_id] = true
        local used_role_names = {}
        for _, role in ipairs(slot.roles) do
            local role_name = type(role) == 'table' and role.role or nil
            if not non_empty_string(role_name) or used_role_names[role_name]
                or not non_empty_string(role.resource_key) or not non_empty_string(role.source)
                or not non_empty_string(role.expected_type) or role.layer ~= contract.layer then
                return false, 'instance-map-contract-role-invalid:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            if role_schema.roles[role_name] ~= role.expected_type then
                return false, 'instance-map-contract-role-schema-invalid:' .. tostring(contract_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            used_role_names[role_name] = true
            local expected_object_id, expected_identity = stable_object_id({ engine_object_id = role.stable_object_id })
            if expected_object_id == nil then
                return false, 'instance-map-contract-stable-id-required:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            if used_resource_keys[role.resource_key] then
                return false, 'instance-map-role-resource-not-unique:' .. tostring(encounter_key)
            end
            if used_object_ids[expected_identity] then
                return false, 'instance-map-role-object-not-unique:' .. tostring(encounter_key)
            end
            used_resource_keys[role.resource_key] = true
            used_object_ids[expected_identity] = true

            local called, binding = pcall(
                self.options.resolve_instance_map_role, contract_key, slot_id, role_name, role, encounter_key
            )
            if not called or binding == nil then
                return false, 'instance-map-role-unresolved:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            if binding.resource_key ~= role.resource_key then
                return false, 'instance-map-role-resource-key-mismatch:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            if binding.source ~= role.source then
                return false, 'instance-map-role-source-mismatch:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            if (binding.expected_type or binding.type) ~= role.expected_type then
                return false, 'instance-map-role-type-mismatch:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            if binding.layer ~= role.layer then
                return false, 'instance-map-role-layer-mismatch:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            local object_id, object_identity = stable_object_id(binding)
            if object_id == nil then
                return false, 'instance-map-role-missing-stable-id:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
            if object_identity ~= expected_identity then
                return false, 'instance-map-role-stable-id-mismatch:' .. tostring(encounter_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
        end
        for role_name in pairs(role_schema.roles) do
            if not used_role_names[role_name] then
                return false, 'instance-map-contract-role-schema-invalid:' .. tostring(contract_key) .. ':'
                    .. tostring(slot_id) .. ':' .. tostring(role_name)
            end
        end
    end
    return true
end

function Adapter:_validate_all_verified_instance_map_contracts()
    local global_object_ids = {}
    for _, contract_key in ipairs(sorted_keys(Config.instance_map_contracts)) do
        local contract = Config.instance_map_contracts[contract_key]
        local encounter_keys = type(contract) == 'table' and contract.encounter_keys or nil
        local should_validate = type(contract) == 'table' and contract.state == 'verified'
        if type(encounter_keys) ~= 'table' or #encounter_keys == 0 then
            return false, 'instance-map-contract-encounters-invalid:' .. tostring(contract_key)
        end
        local seen_encounter_keys = {}
        for _, encounter_key in ipairs(encounter_keys) do
            if seen_encounter_keys[encounter_key] then
                return false, 'instance-map-contract-duplicate-encounter:' .. tostring(contract_key)
            end
            seen_encounter_keys[encounter_key] = true
            local encounter = Config.get_encounter(encounter_key)
            if not encounter then return false, 'instance-map-contract-unknown-encounter:' .. tostring(contract_key) end
            local mapped_contract, mapped_contract_key = Config.get_instance_map_contract(encounter_key)
            if mapped_contract ~= contract or mapped_contract_key ~= contract_key then
                return false, 'instance-map-contract-mapping-mismatch:' .. tostring(encounter_key)
            end
            if encounter.instance_map_contract == 'verified' then should_validate = true end
            if should_validate and encounter.instance_map_contract ~= 'verified' then
                return false, 'instance-map-contract-state-not-verified:' .. tostring(encounter_key)
            end
        end
        if should_validate then
            local representative_key = encounter_keys[1]
            local representative = Config.get_encounter(representative_key)
            local ready, error_code = self:_validate_live_instance_map_contract(
                representative_key, representative, global_object_ids
            )
            if not ready then return false, error_code end
        end
    end
    return true
end

function Adapter:bind_map(binding, contract_id)
    local mode_ok, mode_error = self:_validate_mode()
    if not mode_ok then return false, mode_error end
    if type(binding) ~= 'table' or type(binding.bind) ~= 'function' then return false, 'map-binding-required' end
    if self.mode == 'live' then
        local gate_ok, gate_error = self:_validate_live_gates()
        if not gate_ok then return false, gate_error end
    end
    if type(self.options.resolve_logic_resource) ~= 'function' then
        return false, 'logic-resource-resolver-required'
    end
    local ok, error_code = binding:bind(self.options.resolve_logic_resource, contract_id)
    if not ok then return false, error_code end
    self.binding = binding
    return true
end

function Adapter:_mark_command_delivered(delivery_id, command)
    self.unknown_command_deliveries[delivery_id] = nil
    self.delivered_command_ids[delivery_id] = true
    append(self.emitted_commands, command)
end

-- The map root, not this in-memory Adapter, owns exactly-once protection. Declaring
-- this contract means emit_command is idempotent through an authoritative external
-- delivery_id ledger and reconcile_command is a side-effect-free query of that ledger.
-- Both callbacks return true for delivered, false only when no side effect occurred,
-- and nil/raise when the execution state cannot be proven.
function Adapter:_validate_live_delivery_contract()
    if self.options.live_delivery_contract ~= M.LIVE_DELIVERY_CONTRACT then
        return false, 'live-delivery-contract-not-verified'
    end
    if type(self.options.emit_command) ~= 'function' then return false, 'command-executor-required' end
    if type(self.options.reconcile_command) ~= 'function' then return false, 'command-reconciler-required' end
    return true
end

function Adapter:_reconcile_unknown_command(delivery_id)
    local command = self.unknown_command_deliveries[delivery_id]
    local called, reconciled, reconciliation_error = pcall(
        self.options.reconcile_command, delivery_id, command
    )
    if not called then
        return nil, 'command-reconciliation-failed:' .. tostring(delivery_id)
    end
    if reconciled == true then
        self:_mark_command_delivered(delivery_id, command)
        return 'delivered'
    end
    if reconciled == false then
        self.unknown_command_deliveries[delivery_id] = nil
        return 'not_executed', nil, command
    end
    return nil, reconciliation_error or ('command-reconciliation-status-unknown:' .. tostring(delivery_id))
end

function Adapter:_execute_live_command(command)
    local delivery_id = command.delivery_id
    local called, executed, execution_error = pcall(self.options.emit_command, command)
    if called and executed == true then
        self:_mark_command_delivered(delivery_id, command)
        return true
    end
    if called and executed == false then
        return false, execution_error or 'command-execution-failed'
    end

    -- nil or a raised callback cannot prove whether the external side effect happened.
    self.unknown_command_deliveries[delivery_id] = command
    if not called then
        return false, 'command-execution-status-unknown:' .. tostring(delivery_id)
    end
    return false, execution_error or ('command-execution-status-unknown:' .. tostring(delivery_id))
end

function Adapter:emit(result)
    local mode_ok, mode_error = self:_validate_mode()
    if not mode_ok then return false, mode_error end
    local commands = (result and result.commands) or {}
    if type(commands) ~= 'table' then return false, 'command-list-required' end
    if self.mode == 'live' then
        local ready, error_code = self:can_activate_live_encounters()
        if not ready then return false, error_code end
    end
    for index, command in ipairs(commands) do
        if type(command) ~= 'table' then return false, 'invalid-runtime-command:' .. tostring(index) end
        if self.mode == 'live' then
            if not non_empty_string(command.encounter_key) then
                return false, 'command-encounter-key-required:' .. tostring(index)
            end
            local encounter_ready, encounter_error = self:can_start_encounter(command.encounter_key)
            if not encounter_ready then return false, encounter_error end
            if not non_empty_string(command.delivery_id) then
                return false, 'command-delivery-id-required:' .. tostring(index)
            end
        end
    end
    if self.mode == 'live' and #commands > 0 then
        local contract_ready, contract_error = self:_validate_live_delivery_contract()
        if not contract_ready then return false, contract_error end
    end
    for _, command in ipairs(commands) do
        local delivery_id = command.delivery_id
        if delivery_id == nil or not self.delivered_command_ids[delivery_id] then
            if self.mode == 'live' then
                local delivery_command = command
                local should_execute = true
                if self.unknown_command_deliveries[delivery_id] ~= nil then
                    local status, reconciliation_error, original_command = self:_reconcile_unknown_command(delivery_id)
                    if status == nil then return false, reconciliation_error end
                    if status == 'delivered' then
                        should_execute = false
                    else
                        delivery_command = original_command
                    end
                end
                if should_execute then
                    local executed, execution_error = self:_execute_live_command(delivery_command)
                    if executed ~= true then return false, execution_error end
                end
            else
                if delivery_id ~= nil then self.delivered_command_ids[delivery_id] = true end
                append(self.emitted_commands, command)
            end
        end
    end
    return true
end

function Adapter:can_activate_live_encounters()
    local ready, error_code = self:_validate_live_gates()
    if not ready then return false, error_code end
    if not self.binding or self.binding:is_bound() ~= true then return false, 'map-not-bound' end
    return true
end

function Adapter:can_start_encounter(encounter_key)
    local mode_ok, mode_error = self:_validate_mode()
    if not mode_ok then return false, mode_error end
    if type(encounter_key) ~= 'string' or encounter_key:match('%S') == nil then return false, 'encounter-key-required' end
    local encounter = Config.get_encounter(encounter_key)
    if not encounter then return false, 'unknown-encounter' end
    if self.mode == 'live' then
        local ready, error_code = self:can_activate_live_encounters()
        if not ready then return false, error_code end
        if encounter.combat_scope == 'solo_instance' or encounter.combat_scope == 'team_instance' then
            local contracts_ready, contracts_error = self:_validate_all_verified_instance_map_contracts()
            if not contracts_ready then return false, contracts_error end
        end
        local contract_ready, contract_error = self:_validate_live_instance_map_contract(encounter_key, encounter)
        if not contract_ready then return false, contract_error end
    elseif not self.binding or self.binding:is_bound() ~= true then
        return false, 'map-not-bound'
    end
    return self.binding:assert_encounter_ready(encounter_key)
end

function Adapter:install_hook(owner_key, hook_key, callback)
    local mode_ok, mode_error = self:_validate_mode()
    if not mode_ok then return false, mode_error end
    if self.mode == 'live' then
        local ready, error_code = self:can_activate_live_encounters()
        if not ready then return false, error_code end
    end
    if type(self.options.register_hook) ~= 'function' then return false, 'map-hook-registrar-required' end
    if type(callback) ~= 'function' then return false, 'map-hook-callback-required' end
    local called, handle = pcall(self.options.register_hook, hook_key, callback)
    if not called or handle == nil or handle == false then
        return false, 'map-hook-registration-failed'
    end
    local list = self.owner_hooks[owner_key] or {}
    self.owner_hooks[owner_key] = list
    append(list, handle)
    return true, handle
end

function Adapter:remove_owner_hooks(owner_key)
    local mode_ok, mode_error = self:_validate_mode()
    if not mode_ok then return false, mode_error end
    local hooks = self.owner_hooks[owner_key]
    if not hooks then return true end
    local remaining = {}
    local first_error = nil
    for _, handle in ipairs(hooks) do
        local called, removed, error_code = true, true, nil
        if type(handle) == 'table' and type(handle.remove) == 'function' then
            called, removed, error_code = pcall(handle.remove, handle)
        elseif type(self.options.remove_hook) == 'function' then
            called, removed, error_code = pcall(self.options.remove_hook, handle)
        end
        if not called then
            append(remaining, handle)
            if first_error == nil then
                first_error = 'map-hook-removal-failed'
                if removed ~= nil then first_error = first_error .. ':' .. tostring(removed) end
            end
        elseif removed == false then
            append(remaining, handle)
            first_error = first_error or error_code or 'map-hook-removal-failed'
        end
    end
    if #remaining > 0 then
        self.owner_hooks[owner_key] = remaining
        return false, first_error
    end
    self.owner_hooks[owner_key] = nil
    return true
end

return M
