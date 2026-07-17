package.path = 'implementation/huaguoshan/lua/?.lua;' .. package.path

local Config = require 'huaguoshan_config'
local Binding = require 'huaguoshan_map_binding'
local Adapter = require 'huaguoshan_y3_adapter'
local Controller = require 'huaguoshan_y3_controller'
local Instances = require 'huaguoshan_instances'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

equal(Config.encounters.HG_E_OX_BATTLEFIELD.return_point, 'pt_hg_spawn',
    'Ox failure and timeout returns use the chapter initial spawn')
equal(Config.encounters.HG_E_OX_BATTLEFIELD.reentry_policy, 'deny_until_cleanup_ack',
    'Ox reentry stays locked until the matching cleanup acknowledgement')
equal(Config.encounters.HG_E_DRAGON_REVERSE_TIDE.unlock_rule,
    'level_at_least_38_and_difu_yanluo_hall_cleared',
    'Reverse Tide names the Lv38 plus Yanluo Hall completion rule')
equal(Config.encounters.HG_E_DRAGON_REVERSE_TIDE.progression_key, 'DF_PROGRESS_YANLUO_HALL_CLEARED',
    'Reverse Tide consumes the trusted Yanluo Hall completion key')

local function resolved_resource(key, source, expected_type, generation)
    return {
        logic_key = key,
        engine_object_id = 'engine:' .. key,
        ref = { id = key, generation = generation or 'default' },
        source = source,
        type = expected_type,
    }
end

local function resolver(key, source, expected_type)
    return resolved_resource(key, source, expected_type)
end

local function live_options(overrides)
    local options = {
        mode = 'live',
        real_map_binding_verified = true,
        production_ids_ready = true,
        y3editor_connected = true,
        map_logic_resources_verified = true,
        unit_ids_assigned = true,
        ability_ids_assigned = true,
        modifier_ids_assigned = true,
        projectile_ids_assigned = true,
        model_ids_assigned = true,
        icon_ids_assigned = true,
        effect_resources_assigned = true,
        encounter_runtime_bound = true,
        distance_scale_verified = true,
        instance_map_contract_verified = true,
        authoritative_progression_validator_bound = true,
        resolve_logic_resource = resolver,
        live_delivery_contract = Adapter.LIVE_DELIVERY_CONTRACT,
        reconcile_command = function() return nil, 'unexpected-command-reconciliation' end,
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return options
end

do
    local binding = Binding.new()
    local ok, error_code = binding:bind(resolver, Config.layout_contract.id)
    truthy(ok, error_code)
    truthy(binding:is_bound(), 'all declared whitebox resources bind before runtime starts')
    local refs, refs_error = binding:encounter_refs('HG_E_JIAO_KING')
    truthy(refs, refs_error)
    equal(refs.arena_jiaomowang_phase1.id, 'arena_jiaomowang_phase1', 'boss arena uses its stable logic key')
    local ready, ready_error = binding:assert_encounter_ready('HG_E_OX_BATTLEFIELD')
    truthy(ready, ready_error)
end

do
    local binding = Binding.new()
    local ok, error_code = binding:bind(function(key, source, expected_type)
        if key == 'area_hg_boss_jiao' then
            local result = resolved_resource(key, source, expected_type)
            result.type = 'circleArea'
            return result
        end
        return resolver(key, source, expected_type)
    end, Config.layout_contract.id)
    equal(ok, false, 'wrong area type cannot enter the runtime binding')
    equal(error_code, 'logic-resource-type-mismatch:area_hg_boss_jiao', 'type mismatch names the offending key')
    equal(binding:is_bound(), false, 'failed initial binding stays unbound')
end

do
    local binding = Binding.new()
    local ok, error_code = binding:bind(function(key, source, expected_type)
        if key == 'pt_hg_teleport_hub' then return nil end
        return resolver(key, source, expected_type)
    end, Config.layout_contract.id)
    equal(ok, false, 'missing return point blocks all encounter activation')
    truthy(error_code:match('missing%-logic%-resource:pt_hg_teleport_hub'), 'missing resource is explicit')
end

do
    local binding = Binding.new()
    local ok, error_code = binding:bind(resolver, nil)
    equal(ok, false, 'nil runtime contract is rejected')
    equal(error_code, 'layout-contract-required', 'nil runtime contract has a stable error')
    equal(binding:is_bound(), false, 'nil runtime contract cannot bind the map')
end

do
    local binding = Binding.new()
    truthy(binding:bind(function(key, source, expected_type)
        return resolved_resource(key, source, expected_type, 'old')
    end, Config.layout_contract.id), 'initial binding succeeds')
    local old_ref = binding:get('pt_hg_spawn')
    local ok, error_code = binding:bind(function(key, source, expected_type)
        if key == 'pt_hg_teleport_hub' then return nil end
        return resolved_resource(key, source, expected_type, 'candidate')
    end, Config.layout_contract.id)
    equal(ok, false, 'failed rebind is rejected')
    truthy(error_code:match('missing%-logic%-resource:pt_hg_teleport_hub'), 'failed rebind reports its missing resource')
    equal(binding:is_bound(), true, 'failed rebind preserves the previous complete binding')
    equal(binding:get('pt_hg_spawn'), old_ref, 'failed rebind preserves the previous reference snapshot')
    equal(#binding.missing, 0, 'failed rebind does not publish candidate missing state')
end

do
    local binding = Binding.new()
    local calls = 0
    local first_logic_key
    local ok, error_code = binding:bind(function(key, source, expected_type)
        calls = calls + 1
        local result = resolved_resource(key, source, expected_type)
        if calls == 1 then first_logic_key = key end
        if calls == 2 then result.logic_key = first_logic_key end
        return result
    end, Config.layout_contract.id)
    equal(ok, false, 'duplicate logical resource identity is rejected')
    truthy(error_code:match('^duplicate%-logic%-resource%-key:'), 'duplicate logical key error is explicit')
end

do
    local binding = Binding.new()
    local calls = 0
    local ok, error_code = binding:bind(function(key, source, expected_type)
        calls = calls + 1
        local result = resolved_resource(key, source, expected_type)
        if calls <= 2 then result.engine_object_id = 'engine:shared' end
        return result
    end, Config.layout_contract.id)
    equal(ok, false, 'one engine object cannot masquerade as two logical resources')
    truthy(error_code:match('^logic%-resource%-engine%-object%-reused:'), 'engine object reuse error is explicit')
    equal(binding:is_bound(), false, 'engine object reuse cannot publish a partial binding')
end

do
    local binding = Binding.new()
    local first = true
    local ok, error_code = binding:bind(function(key, source, expected_type)
        local result = resolved_resource(key, source, expected_type)
        if first then
            first = false
            result.engine_object_id = nil
            result.ref.id = nil
        end
        return result
    end, Config.layout_contract.id)
    equal(ok, false, 'resource without a stable engine object ID is rejected')
    truthy(error_code:match('^logic%-resource%-engine%-object%-id%-required:'), 'missing engine object ID error is explicit')
end

do
    local executed = 0
    local adapter = Adapter.new({
        mode = 'offline_test',
        resolve_logic_resource = resolver,
        emit_command = function() executed = executed + 1 end,
    })
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id), 'offline test mode binds the offline resource snapshot')
    truthy(adapter:can_start_encounter('HG_E_MACAQUE_KING'), 'offline test mode can drive a known bound encounter')
    truthy(adapter:emit({ commands = { { type = 'offline-command' } } }), 'offline test mode records simulated commands')
    equal(#adapter.emitted_commands, 1, 'offline test mode retains its simulated command log')
    equal(executed, 0, 'offline test mode never invokes the injected real command executor')
    local live, live_error = adapter:can_activate_live_encounters()
    equal(live, false, 'offline test mode cannot report live activation')
    equal(live_error, 'offline-test-mode', 'offline live query is explicit')
end

do
    local adapter = Adapter.new({ mode = 'preview', resolve_logic_resource = resolver })
    local ok, error_code = adapter:bind_map(Binding.new(), Config.layout_contract.id)
    equal(ok, false, 'unknown adapter mode cannot bind')
    equal(error_code, 'unsupported-adapter-mode', 'unknown adapter mode has a stable rejection')
    local emitted, emit_error = adapter:emit({ commands = { { type = 'forbidden' } } })
    equal(emitted, false, 'unknown adapter mode cannot emit')
    equal(emit_error, 'unsupported-adapter-mode', 'unknown mode emit rejection is stable')
end

do
    local options = live_options({ real_map_binding_verified = 1 })
    local adapter = Adapter.new(options)
    local ok, error_code = adapter:bind_map(Binding.new(), Config.layout_contract.id)
    equal(ok, false, 'integer one cannot impersonate a live boolean gate')
    equal(error_code, 'live-gate-not-boolean:real_map_binding_verified', 'non-boolean live gate is named')
end

do
    local executed = 0
    local options = live_options({
        real_map_binding_verified = false,
        delivery_namespace = 'map-binding-closed-live',
        emit_command = function() executed = executed + 1 return true end,
    })
    local adapter = Adapter.new(options)
    local ok, error_code = adapter:bind_map(Binding.new(), Config.layout_contract.id)
    equal(ok, false, 'closed live gate blocks map publication')
    equal(error_code, 'real-map-binding-not-verified', 'closed live map gate is explicit')
    local emitted, emit_error = adapter:emit({ commands = { { type = 'forbidden-live-command' } } })
    equal(emitted, false, 'closed live gate blocks command emission')
    equal(emit_error, 'real-map-binding-not-verified', 'blocked live command reports its gate')
    equal(executed, 0, 'closed live gate never reaches the command executor')

    local controller = Controller.new(options)
    local bound, bind_error = controller:bind_map()
    equal(bound, false, 'controller cannot bind its runtime through a closed live adapter')
    equal(bind_error, 'real-map-binding-not-verified', 'controller binding reports the closed live gate')
    local started, start_error = controller:start_public_boss('HG_E_MACAQUE_KING', {
        boss_instance_id = 'blocked-boss', target_id = 'boss-unit', target_lifecycle_id = 'boss-life',
    })
    equal(started, false, 'controller cannot start an encounter after live binding was refused')
    equal(start_error, 'real-map-binding-not-verified', 'blocked controller start reports the exact live gate')

    local fake_runtime = { binding = Binding.new() }
    function fake_runtime:mark_public_phase()
        return true, { commands = { { type = 'controller-forbidden-command' } } }
    end
    local forwarding_controller = Controller.new({
        adapter = adapter,
        runtime = fake_runtime,
        delivery_namespace = 'map-binding-forwarding-live',
    })
    local forwarded, forwarding_result = forwarding_controller:mark_public_phase('blocked-boss', 'phase', 1)
    equal(forwarded, true, 'controller accepts a committed command when the closed adapter leaves delivery pending')
    equal(forwarding_result.delivery_error, 'real-map-binding-not-verified',
        'controller preserves the closed adapter gate on its pending delivery')
    equal(#forwarding_controller.pending_deliveries, 1, 'controller retains a failed command delivery for retry')
    equal(executed, 0, 'controller cannot make a closed live adapter execute a real command')
    equal(#adapter.emitted_commands, 0, 'closed live adapter does not record a command as emitted')
end

do
    local executed = 0
    local options = live_options({
        emit_command = function(command)
            executed = executed + 1
            equal(command.type, 'live-command', 'live executor receives the authorized command')
            return true
        end,
    })
    local adapter = Adapter.new(options)
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id), 'all strict live gates permit exact map binding')
    truthy(adapter:can_activate_live_encounters(), 'all strict live gates and map binding permit activation')
    truthy(adapter:can_start_encounter('HG_E_JIAO_KING'), 'authorized live adapter can start a ready encounter')
    local instance_ready, instance_error = adapter:can_start_encounter('HG_E_DRAGON_OLD_TIDE')
    equal(instance_ready, false, 'live adapter rejects a solo instance while its internal map contract is pending')
    equal(instance_error, 'instance-map-contract-state-not-verified:HG_E_DRAGON_OLD_TIDE',
        'pending live instance contract names the blocked encounter')
    truthy(adapter:emit({ commands = {
        { type = 'live-command', delivery_id = 'delivery-live', encounter_key = 'HG_E_JIAO_KING' },
    } }), 'authorized live adapter executes commands')
    equal(executed, 1, 'authorized live command executes exactly once')
    equal(#adapter.emitted_commands, 1, 'authorized live command is recorded')
end

do
    local attempts = {}
    local adapter = Adapter.new(live_options({
        emit_command = function(command)
            attempts[command.delivery_id] = (attempts[command.delivery_id] or 0) + 1
            if command.delivery_id == 'delivery-b' and attempts[command.delivery_id] == 1 then
                return false, 'simulated-second-command-failure'
            end
            return true
        end,
    }))
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id), 'delivery retry test has an authorized live adapter')
    local batch = { commands = {
        { type = 'delivery-a', delivery_id = 'delivery-a', encounter_key = 'HG_E_MACAQUE_KING' },
        { type = 'delivery-b', delivery_id = 'delivery-b', encounter_key = 'HG_E_MACAQUE_KING' },
    } }
    local first_sent, first_error = adapter:emit(batch)
    equal(first_sent, false, 'partial live delivery reports the command executor failure')
    equal(first_error, 'simulated-second-command-failure', 'partial live delivery forwards the executor error')
    equal(attempts['delivery-a'], 1, 'first command executes before the later failure')
    equal(attempts['delivery-b'], 1, 'failing command is attempted once')
    truthy(adapter:emit(batch), 'retry replays the retained command batch')
    equal(attempts['delivery-a'], 1, 'retry skips a delivery ID already acknowledged by the adapter')
    equal(attempts['delivery-b'], 2, 'retry re-attempts only the failed delivery ID')
    equal(#adapter.emitted_commands, 2, 'adapter records each stable delivery ID only once')
    truthy(adapter.unknown_command_deliveries['delivery-b'] == nil,
        'an explicit not-executed result never enters the unknown delivery ledger')
end

do
    local attempts = 0
    local side_effects = 0
    local reconciliation = 'unknown'
    local reconciliation_calls = 0
    local adapter = Adapter.new(live_options({
        emit_command = function(command)
            attempts = attempts + 1
            side_effects = side_effects + 1
            equal(command.type, 'unknown-ack-command', 'executor receives the Controller command before acknowledgement fails')
            return nil, 'command-acknowledgement-failed'
        end,
        reconcile_command = function(delivery_id, command)
            reconciliation_calls = reconciliation_calls + 1
            equal(delivery_id, command.delivery_id, 'reconciler queries the stable delivery ID and original command together')
            if reconciliation == 'delivered' then return true end
            return nil, 'command-status-still-unknown'
        end,
    }))
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id),
        'unknown acknowledgement regression test has an authorized live adapter')
    local fake_runtime = { binding = Binding.new() }
    function fake_runtime:mark_public_phase()
        return true, { commands = {
            { type = 'unknown-ack-command', encounter_key = 'HG_E_MACAQUE_KING' },
        } }
    end
    local controller = Controller.new({
        adapter = adapter,
        runtime = fake_runtime,
        delivery_namespace = 'map-binding-unknown-ack-live',
    })
    local sent, pending_result = controller:mark_public_phase('boss', {})
    equal(sent, true, 'an unconfirmed external execution remains accepted and pending in the Controller')
    equal(pending_result.delivery_error, 'command-acknowledgement-failed',
        'the initial acknowledgement failure is preserved on the accepted result')
    equal(attempts, 1, 'the command executor is called once before the result becomes unknown')
    equal(side_effects, 1, 'the mock external side effect occurs before acknowledgement fails')
    equal(#controller.pending_deliveries, 1, 'Controller retains the unknown delivery for reconciliation')
    local delivery_id = controller.pending_deliveries[1].payload.commands[1].delivery_id
    truthy(adapter.unknown_command_deliveries[delivery_id] ~= nil,
        'Adapter quarantines an execution whose external result is unknown')

    sent, error_code = controller:retry_pending_deliveries()
    equal(sent, false, 'an inconclusive reconciliation fails closed')
    equal(error_code, 'command-status-still-unknown', 'the reconciliation error is reported')
    equal(attempts, 1, 'Controller retry does not blindly call the executor again')
    equal(side_effects, 1, 'inconclusive reconciliation cannot duplicate the external side effect')
    equal(reconciliation_calls, 1, 'Controller retry explicitly queries the external delivery state')
    equal(#controller.pending_deliveries, 1, 'unknown delivery stays pending after an inconclusive query')

    reconciliation = 'delivered'
    truthy(controller:retry_pending_deliveries(), 'explicit delivered reconciliation completes the pending delivery')
    equal(attempts, 1, 'delivered reconciliation never replays the executor')
    equal(side_effects, 1, 'delivered reconciliation preserves exactly one external side effect')
    equal(reconciliation_calls, 2, 'resolved reconciliation performs one final external query')
    equal(#controller.pending_deliveries, 0, 'Controller clears a reconciled delivery')
    equal(adapter.delivered_command_ids[delivery_id], true, 'reconciled delivery enters the idempotency ledger')
    truthy(adapter.unknown_command_deliveries[delivery_id] == nil, 'reconciled delivery leaves the unknown ledger')
    equal(#adapter.emitted_commands, 1, 'reconciled success is recorded exactly once')
end

do
    local attempts = 0
    local adapter = Adapter.new(live_options({
        emit_command = function()
            attempts = attempts + 1
            if attempts == 1 then return nil, 'first-attempt-status-unknown' end
            return true
        end,
        reconcile_command = function() return false end,
    }))
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id),
        'not-executed reconciliation test has an authorized live adapter')
    local batch = { commands = {
        { type = 'safe-retry-command', delivery_id = 'delivery-safe-retry', encounter_key = 'HG_E_MACAQUE_KING' },
    } }
    local sent, error_code = adapter:emit(batch)
    equal(sent, false, 'unknown first attempt is not treated as a delivery')
    equal(error_code, 'first-attempt-status-unknown', 'unknown first attempt preserves its error')
    equal(attempts, 1, 'unknown first attempt executes once')
    truthy(adapter:emit(batch), 'explicit not-executed reconciliation permits a safe retry')
    equal(attempts, 2, 'executor is retried only after the reconciler proves no prior side effect')
    equal(adapter.delivered_command_ids['delivery-safe-retry'], true, 'safe retry records explicit success')
    truthy(adapter.unknown_command_deliveries['delivery-safe-retry'] == nil,
        'safe retry clears the unknown delivery state')
    equal(#adapter.emitted_commands, 1, 'safe retry records the delivery exactly once')
end

do
    local executed = 0
    local options = live_options({
        emit_command = function() executed = executed + 1 return true end,
    })
    options.live_delivery_contract = nil
    local adapter = Adapter.new(options)
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id),
        'missing delivery contract test binds the otherwise authorized live adapter')
    local emitted, error_code = adapter:emit({ commands = {
        { type = 'unverified-delivery-contract', delivery_id = 'delivery-unverified-contract',
            encounter_key = 'HG_E_MACAQUE_KING' },
    } })
    equal(emitted, false, 'live execution requires the external delivery ID ledger contract')
    equal(error_code, 'live-delivery-contract-not-verified', 'missing delivery capability is explicit')
    equal(executed, 0, 'unverified delivery capability blocks the external executor')
end

do
    local executed = 0
    local options = live_options({
        emit_command = function() executed = executed + 1 return true end,
    })
    options.reconcile_command = nil
    local adapter = Adapter.new(options)
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id),
        'missing reconciler test binds the otherwise authorized live adapter')
    local emitted, error_code = adapter:emit({ commands = {
        { type = 'missing-reconciler', delivery_id = 'delivery-missing-reconciler', encounter_key = 'HG_E_MACAQUE_KING' },
    } })
    equal(emitted, false, 'live execution is gated without an external delivery reconciler')
    equal(error_code, 'command-reconciler-required', 'missing production reconciliation capability is explicit')
    equal(executed, 0, 'missing reconciler gate blocks the external executor')
end

do
    local executed = 0
    local adapter = Adapter.new(live_options({
        emit_command = function() executed = executed + 1 return true end,
    }))
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id), 'encounter-key guard has an authorized live adapter')
    local emitted, error_code = adapter:emit({ commands = { { type = 'missing-key' } } })
    equal(emitted, false, 'live command without encounter_key is rejected')
    equal(error_code, 'command-encounter-key-required:1', 'missing command encounter key names its index')
    emitted, error_code = adapter:emit({ commands = { { type = 'unknown-key', encounter_key = 'HG_E_UNKNOWN' } } })
    equal(emitted, false, 'live command with unknown encounter_key is rejected')
    equal(error_code, 'unknown-encounter', 'unknown command encounter is fail-closed')
    emitted, error_code = adapter:emit({ commands = {
        { type = 'missing-delivery-id', encounter_key = 'HG_E_MACAQUE_KING' },
    } })
    equal(emitted, false, 'live command without a delivery ID is rejected before external execution')
    equal(error_code, 'command-delivery-id-required:1', 'missing live delivery ID names its command index')
    local allowed, start_error = adapter:can_start_encounter('HG_E_DRAGON_OLD_TIDE')
    equal(allowed, false, 'pending instance cannot start before direct emit regression')
    emitted, error_code = adapter:emit({ commands = {
        { type = 'pending-instance-bypass', encounter_key = 'HG_E_DRAGON_OLD_TIDE' },
    } })
    equal(emitted, false, 'direct emit cannot bypass a rejected pending instance')
    equal(error_code, start_error, 'direct instance emit reuses can_start_encounter contract rejection')
    equal(executed, 0, 'rejected keyed commands never call the executor')
end

do
    local old_tide_key = 'HG_E_DRAGON_OLD_TIDE'
    local reverse_tide_key = 'HG_E_DRAGON_REVERSE_TIDE'
    local ox_key = 'HG_E_OX_BATTLEFIELD'
    local encounter = Config.encounters[old_tide_key]
    local reverse_encounter = Config.encounters[reverse_tide_key]
    local ox_encounter = Config.encounters[ox_key]
    local contract, contract_key = Config.get_instance_map_contract(old_tide_key)
    local reverse_contract, reverse_contract_key = Config.get_instance_map_contract(reverse_tide_key)
    local ox_contract = Config.get_instance_map_contract(ox_key)
    equal(contract_key, 'HG_I_DRAGON_FOUR_SEAS', 'Old Tide resolves the canonical Four Seas contract')
    equal(reverse_contract_key, contract_key, 'Reverse Tide reuses the canonical Four Seas contract')
    equal(reverse_contract, contract, 'both Dragon variants share the same four-slot table')
    encounter.instance_map_contract = 'verified'
    reverse_encounter.instance_map_contract = 'verified'
    contract.state = 'verified'
    for _, slot in ipairs(contract.slots) do
        for _, role in ipairs(slot.roles) do role.stable_object_id = 'instance:' .. role.resource_key end
    end
    local function instance_resolver(_, _, _, role)
        return {
            resource_key = role.resource_key,
            source = role.source,
            expected_type = role.expected_type,
            layer = role.layer,
            engine_object_id = role.stable_object_id,
            ref = { id = role.stable_object_id },
        }
    end
    local adapter = Adapter.new(live_options({ resolve_instance_map_role = instance_resolver }))
    truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id), 'verified instance role test binds public map resources')
    truthy(adapter:can_start_encounter(old_tide_key), 'verified shared Dragon roles match every declared field')
    truthy(adapter:can_start_encounter(reverse_tide_key), 'both Dragon variants use the same verified four slots')

    local saved_reverse_contract_key = reverse_encounter.instance_map_contract_key
    reverse_encounter.instance_map_contract_key = 'HG_I_OX_BATTLEFIELD'
    local ready, error_code = adapter:can_start_encounter(old_tide_key)
    equal(ready, false, 'an Encounter cannot silently point outside its shared map contract')
    equal(error_code, 'instance-map-contract-mapping-mismatch:' .. reverse_tide_key,
        'shared-contract mapping drift names the mismatched Encounter')
    reverse_encounter.instance_map_contract_key = saved_reverse_contract_key

    local missing_role = table.remove(contract.slots[1].roles)
    ready, error_code = adapter:can_start_encounter(old_tide_key)
    equal(ready, false, 'a verified Dragon slot cannot omit a required role')
    truthy(error_code:match('^instance%-map%-contract%-role%-schema%-invalid:HG_I_DRAGON_FOUR_SEAS:'),
        'missing required Dragon role fails the canonical role schema')
    contract.slots[1].roles[#contract.slots[1].roles + 1] = missing_role

    local saved_role_name = contract.slots[1].roles[4].role
    contract.slots[1].roles[4].role = 'unexpected_exit'
    ready, error_code = adapter:can_start_encounter(old_tide_key)
    equal(ready, false, 'a verified Dragon slot cannot substitute an arbitrary role name')
    truthy(error_code:match('^instance%-map%-contract%-role%-schema%-invalid:HG_I_DRAGON_FOUR_SEAS:'),
        'unexpected Dragon role names fail the canonical role schema')
    contract.slots[1].roles[4].role = saved_role_name

    local saved_role_type = contract.slots[1].roles[1].expected_type
    contract.slots[1].roles[1].expected_type = 'point'
    ready, error_code = adapter:can_start_encounter(old_tide_key)
    equal(ready, false, 'a verified Dragon role cannot change its canonical expected type')
    truthy(error_code:match('^instance%-map%-contract%-role%-schema%-invalid:HG_I_DRAGON_FOUR_SEAS:'),
        'canonical Dragon role types fail closed before resolver output')
    contract.slots[1].roles[1].expected_type = saved_role_type

    local mismatched = Adapter.new(live_options({
        resolve_instance_map_role = function(a, b, c, role)
            local result = instance_resolver(a, b, c, role)
            if role.role == 'boss_arena' then result.expected_type = 'point' end
            return result
        end,
    }))
    truthy(mismatched:bind_map(Binding.new(), Config.layout_contract.id), 'mismatch test binds public map resources')
    ready, error_code = mismatched:can_start_encounter(old_tide_key)
    equal(ready, false, 'arbitrary distinct object IDs cannot mask a role type mismatch')
    truthy(error_code:match('^instance%-map%-role%-type%-mismatch:'), 'role type mismatch is explicit')

    local first_id = contract.slots[1].roles[1].stable_object_id
    contract.slots[1].roles[2].stable_object_id = first_id
    ready, error_code = adapter:can_start_encounter(old_tide_key)
    equal(ready, false, 'verified instance roles must remain independent')
    equal(error_code, 'instance-map-role-object-not-unique:' .. old_tide_key, 'duplicate stable ID is rejected')

    contract.slots[1].roles[2].stable_object_id = 'instance:' .. contract.slots[1].roles[2].resource_key
    reverse_encounter.instance_map_contract = 'pending'
    ready, error_code = adapter:can_start_encounter(old_tide_key)
    equal(ready, false, 'a shared contract cannot be verified for only one Dragon variant')
    equal(error_code, 'instance-map-contract-state-not-verified:' .. reverse_tide_key,
        'shared-contract state mismatch names the unverified Dragon variant')
    reverse_encounter.instance_map_contract = 'verified'

    ox_encounter.instance_map_contract = 'verified'
    ox_contract.state = 'verified'
    for _, slot in ipairs(ox_contract.slots) do
        for _, role in ipairs(slot.roles) do role.stable_object_id = 'instance:' .. role.resource_key end
    end
    ox_contract.slots[1].roles[1].stable_object_id = contract.slots[1].roles[1].stable_object_id
    ready, error_code = adapter:can_start_encounter(old_tide_key)
    equal(ready, false, 'distinct canonical contracts cannot reuse a stable object ID')
    equal(error_code, 'instance-map-role-object-not-unique:' .. ox_key,
        'cross-contract stable ID reuse names the conflicting encounter')

    ox_encounter.instance_map_contract = 'pending'
    ox_contract.state = 'pending'
    for _, slot in ipairs(ox_contract.slots) do
        for _, role in ipairs(slot.roles) do role.stable_object_id = false end
    end
    encounter.instance_map_contract = 'pending'
    reverse_encounter.instance_map_contract = 'pending'
    contract.state = 'pending'
    for _, slot in ipairs(contract.slots) do
        for _, role in ipairs(slot.roles) do role.stable_object_id = false end
    end
end

do
    local instance_keys = {
        'HG_E_DRAGON_OLD_TIDE',
        'HG_E_DRAGON_REVERSE_TIDE',
        'HG_E_OX_BATTLEFIELD',
    }
    local saved_encounter_states = {}
    local saved_contracts = {}
    for _, encounter_key in ipairs(instance_keys) do
        local encounter = Config.encounters[encounter_key]
        local contract, contract_key = Config.get_instance_map_contract(encounter_key)
        truthy(contract, 'instance command preflight resolves its map contract')
        saved_encounter_states[encounter_key] = encounter.instance_map_contract
        encounter.instance_map_contract = 'verified'
        if not saved_contracts[contract_key] then
            local saved = { contract = contract, contract_state = contract.state, roles = {} }
            saved_contracts[contract_key] = saved
            contract.state = 'verified'
            for slot_index, slot in ipairs(contract.slots) do
                local saved_slot = {}
                saved.roles[slot_index] = saved_slot
                for role_index, role in ipairs(slot.roles) do
                    saved_slot[role_index] = role.stable_object_id
                    role.stable_object_id = 'instance:' .. contract_key .. ':' .. role.resource_key
                end
            end
        end
    end

    local function restore_instance_contracts()
        for _, encounter_key in ipairs(instance_keys) do
            local encounter = Config.encounters[encounter_key]
            encounter.instance_map_contract = saved_encounter_states[encounter_key]
        end
        for _, saved in pairs(saved_contracts) do
            local contract = saved.contract
            contract.state = saved.contract_state
            for slot_index, slot in ipairs(contract.slots) do
                for role_index, role in ipairs(slot.roles) do
                    role.stable_object_id = saved.roles[slot_index][role_index]
                end
            end
        end
    end

    local function instance_resolver(_, _, _, role)
        return {
            resource_key = role.resource_key,
            source = role.source,
            expected_type = role.expected_type,
            layer = role.layer,
            engine_object_id = role.stable_object_id,
            ref = { id = role.stable_object_id },
        }
    end

    local function copy_command(command)
        local copy = {}
        for key, value in pairs(command) do copy[key] = value end
        return copy
    end

    local function append_commands(target, source)
        for _, command in ipairs((source and source.commands) or {}) do
            target[#target + 1] = command
        end
    end

    local function authority_provider()
        local provider = {
            now = 1,
            sequence = 0,
            member_snapshot = { { actor_id = 'map-ox', lifecycle_id = 9, team_id = 'raid' } },
        }

        function provider:verify(operation, context)
            self.sequence = self.sequence + 1
            local proof = {}
            for key, value in pairs(context) do proof[key] = value end
            proof.operation = operation
            proof.operation_token = 'map-instance-proof:' .. operation .. ':' .. tostring(self.sequence)
            proof.now = self.now
            if operation == 'ox_entry' then
                proof.member_snapshot = self.member_snapshot
            elseif operation == 'dragon_finish'
                or operation == 'dragon_timeout'
                or operation == 'dragon_actor_invalidate' then
                proof.reason = context.requested_reason or 'finished'
            elseif operation == 'ox_phase_swap' then
                proof.next_phase_id = 'white_ox'
            elseif operation == 'ox_success' then
                proof.reason = 'success'
            elseif operation == 'ox_failure' or operation == 'ox_timeout' then
                proof.reason = context.requested_reason
                if proof.reason == 'all_members_dead' then proof.all_members_dead = true end
            end
            return true, proof
        end

        return provider
    end

    local ok, test_error = pcall(function()
        local authority = authority_provider()
        local dragon = Instances.new_dragon_slots({
            authority_provider = authority,
            progression_validator = function() return true end,
        })
        local all_commands = {}

        local opened, old_tide = dragon:open({
            encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'map-dragon-old', lifecycle_id = 1,
        })
        truthy(opened, 'authority-issued Old Tide entry produces instance commands')
        for _, command in ipairs(old_tide.commands) do
            equal(command.encounter_key, 'HG_E_DRAGON_OLD_TIDE', 'Old Tide command has its encounter key')
        end
        append_commands(all_commands, old_tide)
        authority.now = 2
        local finished, old_cleanup = dragon:finish({
            actor_id = old_tide.session.owner_actor_id,
            lifecycle_id = old_tide.session.owner_lifecycle_id,
            session_instance_id = old_tide.session.session_instance_id,
            session_epoch = old_tide.session.session_epoch,
        })
        truthy(finished, 'authority-issued Old Tide finish produces cleanup command')
        equal(old_cleanup.commands[1].encounter_key, 'HG_E_DRAGON_OLD_TIDE', 'Old Tide cleanup has its encounter key')
        append_commands(all_commands, old_cleanup)
        authority.now = 3
        local released, old_release = dragon:acknowledge_cleanup({
            actor_id = old_tide.session.owner_actor_id,
            lifecycle_id = old_tide.session.owner_lifecycle_id,
            session_instance_id = old_tide.session.session_instance_id,
            session_epoch = old_tide.session.session_epoch,
        })
        truthy(released, 'authority-issued Old Tide ack produces release command')
        equal(old_release.commands[1].encounter_key, 'HG_E_DRAGON_OLD_TIDE', 'Old Tide release has its encounter key')
        append_commands(all_commands, old_release)

        authority.now = 4
        opened, old_tide = dragon:open({
            encounter_key = 'HG_E_DRAGON_REVERSE_TIDE', actor_id = 'map-dragon-reverse', lifecycle_id = 2,
        })
        truthy(opened, 'authority-issued Reverse Tide entry produces instance commands')
        for _, command in ipairs(old_tide.commands) do
            equal(command.encounter_key, 'HG_E_DRAGON_REVERSE_TIDE', 'Reverse Tide command has its encounter key')
        end
        append_commands(all_commands, old_tide)
        authority.now = 5
        finished, old_cleanup = dragon:finish({
            actor_id = old_tide.session.owner_actor_id,
            lifecycle_id = old_tide.session.owner_lifecycle_id,
            session_instance_id = old_tide.session.session_instance_id,
            session_epoch = old_tide.session.session_epoch,
        })
        truthy(finished, 'authority-issued Reverse Tide finish produces cleanup command')
        equal(old_cleanup.commands[1].encounter_key, 'HG_E_DRAGON_REVERSE_TIDE', 'Reverse Tide cleanup has its encounter key')
        append_commands(all_commands, old_cleanup)
        authority.now = 6
        released, old_release = dragon:acknowledge_cleanup({
            actor_id = old_tide.session.owner_actor_id,
            lifecycle_id = old_tide.session.owner_lifecycle_id,
            session_instance_id = old_tide.session.session_instance_id,
            session_epoch = old_tide.session.session_epoch,
        })
        truthy(released, 'authority-issued Reverse Tide ack produces release command')
        equal(old_release.commands[1].encounter_key, 'HG_E_DRAGON_REVERSE_TIDE', 'Reverse Tide release has its encounter key')
        append_commands(all_commands, old_release)

        authority.now = 7
        local ox = Instances.new_ox_battlefield({
            authority_provider = authority,
            member_lifecycle_validator = function(actor_id, lifecycle_id)
                return actor_id == 'map-ox' and lifecycle_id == 9
            end,
        })
        local ox_opened, ox_start = ox:open({
            entry_request_id = 'map:ox-success', actor_id = 'map-ox', lifecycle_id = 9,
        })
        truthy(ox_opened, 'authority-issued Ox entry produces instance commands')
        for _, command in ipairs(ox_start.commands) do
            equal(command.encounter_key, 'HG_E_OX_BATTLEFIELD', 'Ox start command has its encounter key')
        end
        append_commands(all_commands, ox_start)
        authority.now = 8
        local swapped, ox_phase = ox:swap_to_white_ox({
            raid_instance_id = ox_start.session.raid_instance_id,
            session_epoch = ox_start.session.session_epoch,
            boss_instance_id = ox_start.session.boss_instance_id,
            phase_id = ox_start.session.phase_id,
        })
        truthy(swapped, 'authority-issued Ox phase produces instance command')
        equal(ox_phase.commands[1].encounter_key, 'HG_E_OX_BATTLEFIELD', 'Ox phase command has its encounter key')
        append_commands(all_commands, ox_phase)
        authority.now = 9
        local succeeded, ox_cleanup = ox:succeed({
            raid_instance_id = ox_start.session.raid_instance_id,
            session_epoch = ox_start.session.session_epoch,
            boss_instance_id = ox_start.session.boss_instance_id,
            phase_id = 'white_ox',
        })
        truthy(succeeded, 'authority-issued Ox success produces cleanup command')
        equal(ox_cleanup.commands[1].encounter_key, 'HG_E_OX_BATTLEFIELD', 'Ox cleanup has its encounter key')
        append_commands(all_commands, ox_cleanup)
        authority.now = 10
        released, old_release = ox:acknowledge_cleanup({
            raid_instance_id = ox_start.session.raid_instance_id,
            session_epoch = ox_start.session.session_epoch,
            boss_instance_id = ox_start.session.boss_instance_id,
            phase_id = 'white_ox',
        })
        truthy(released, 'authority-issued Ox ack produces release command')
        equal(old_release.commands[1].encounter_key, 'HG_E_OX_BATTLEFIELD', 'Ox release has its encounter key')
        append_commands(all_commands, old_release)

        local emitted = 0
        local adapter = Adapter.new(live_options({
            resolve_instance_map_role = instance_resolver,
            emit_command = function(command)
                emitted = emitted + 1
                truthy(command.encounter_key ~= nil, 'live executor receives an encounter-keyed instance command')
                return true
            end,
        }))
        truthy(adapter:bind_map(Binding.new(), Config.layout_contract.id),
            'live instance command preflight binds verified contracts')
        local live_commands = {}
        for index, command in ipairs(all_commands) do
            local delivered = copy_command(command)
            delivered.delivery_id = 'instance-command-preflight:' .. tostring(index)
            live_commands[index] = delivered
        end
        truthy(adapter:emit({ commands = live_commands }),
            'live Adapter preflights every authority-issued instance command')
        equal(emitted, #live_commands, 'every preflighted instance command reaches the live executor exactly once')
    end)
    restore_instance_contracts()
    if not ok then error(test_error) end
end

do
    local count = 0
    for _ in pairs(Config.encounters) do count = count + 1 end
    equal(count, 15, 'all fifteen declared encounters are represented in the runtime config')
end

print('PASS: ' .. tests .. ' map binding assertions')
