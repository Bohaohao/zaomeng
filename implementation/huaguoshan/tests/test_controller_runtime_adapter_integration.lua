package.path = 'implementation/huaguoshan/lua/?.lua;' .. package.path

local Controller = require 'huaguoshan_y3_controller'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then
        error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    end
end

local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local function copy_table(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function resolver(prefix)
    return function(key, source, expected_type)
        local ref = { id = prefix .. ':' .. key }
        return {
            ref = ref,
            engine_object_id = ref.id,
            logic_key = key,
            source = source,
            type = expected_type,
        }
    end
end

local function new_authority()
    local authority = { now = 100, sequence = 0, callbacks = {} }

    function authority:on_verify(operation, callback)
        self.callbacks[operation] = callback
    end

    function authority:verify(operation, context)
        self.sequence = self.sequence + 1
        local proof = copy_table(context)
        proof.operation = operation
        proof.operation_token = operation .. ':integration:' .. tostring(self.sequence)
        proof.now = self.now
        if operation == 'dragon_actor_invalidate' then proof.reason = 'actor_invalidated' end
        if operation == 'dragon_finish' then proof.reason = 'success' end
        if operation == 'dragon_timeout' then proof.reason = 'timeout' end
        local callback = self.callbacks[operation]
        if callback then callback(context, proof) end
        return true, proof
    end

    return authority
end

do
    local authority = new_authority()
    local trigger_remove_fails = true
    local trigger_handle
    local controller = Controller.new({
        mode = 'offline_test',
        authority_provider = authority,
        progression_validator = function() return true end,
        register_hook = function(hook_key, callback)
            trigger_handle = { key = hook_key, callback = callback, removed = false }
            function trigger_handle:remove()
                if trigger_remove_fails then error('trigger-remove-failed') end
                self.removed = true
                return true
            end
            return trigger_handle
        end,
        resolve_logic_resource = function(key, source, expected_type)
            local ref = { id = 'integration:' .. key }
            return {
                ref = ref,
                engine_object_id = ref.id,
                logic_key = key,
                source = source,
                type = expected_type,
            }
        end,
    })

    truthy(controller:bind_map(), 'actual Controller binds the actual Runtime through the actual offline Adapter')
    local hero = controller:register_actor('integration-hero', { id = 'integration-unit' }, 'integration-team')
    truthy(hero.lifecycle_id ~= nil, 'Controller registration produces an actor lifecycle')

    local rejected, reject_error = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = 'integration-hero',
        lifecycle_id = hero.lifecycle_id,
        now = 1,
    })
    equal(rejected, false, 'actual Controller rejects caller-owned instance clocks before Runtime')
    equal(reject_error, 'untrusted-instance-authority-field:now',
        'instance clock rejection keeps the Controller boundary contract')

    local started, start = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = 'integration-hero',
        lifecycle_id = hero.lifecycle_id,
    })
    equal(started, true, 'actual Controller starts a Dragon session through Runtime and Adapter')
    equal(start.accepted, true, 'integrated start reports its accepted state')
    equal(start.delivery_pending, false, 'offline Adapter immediately delivers the integrated start commands')
    truthy(start.operation_id ~= nil and start.delivery_id ~= nil,
        'integrated start returns stable operation and batch delivery identities')
    equal(start.session.cleanup_token, nil, 'integrated public session omits the cleanup capability')
    start.session.state = 'forged'
    equal(controller.runtime.dragon_slots:get_by_actor('integration-hero').state, 'active',
        'integrated returned session mutation cannot alter Runtime session state')
    for _, command in ipairs(start.commands) do
        truthy(command.delivery_id ~= nil, 'every integrated start command receives a stable delivery ID')
    end

    local trigger_calls = 0
    truthy(controller:install_actor_hook('integration-hero', 'integration-trigger', function()
        trigger_calls = trigger_calls + 1
    end), 'actual Adapter installs a lifecycle-owned trigger before invalidation')
    trigger_handle.callback()
    equal(trigger_calls, 1, 'current integrated trigger executes before retirement')
    local emitted_before_cleanup = #controller.adapter.emitted_commands

    authority:on_verify('dragon_actor_invalidate', function()
        equal(controller.runtime.actor_is_current('integration-hero', hero.lifecycle_id), false,
            'actual Runtime sees a retiring actor lifecycle as non-current inside authority verification')
        equal(controller.runtime.source_unit_is_current(
            'integration-hero', hero.lifecycle_id, 'integration-unit', hero.lifecycle_id
        ), false, 'actual Runtime rejects a retiring source lifecycle inside authority verification')
        trigger_handle.callback()
        equal(trigger_calls, 1, 'actual retiring trigger is inert inside authority verification')
        local accepted, error_code = controller:finish_dragon({
            encounter_key = start.session.encounter_key,
            actor_id = 'integration-hero',
            lifecycle_id = hero.lifecycle_id,
            session_instance_id = start.session.session_instance_id,
            session_epoch = start.session.session_epoch,
        })
        equal(accepted, false, 'actual Controller rejects an old lifecycle event during Runtime invalidation')
        equal(error_code, 'actor-lifecycle-retiring',
            'actual retiring event rejection is explicit')
    end)

    local invalidated, invalidation_error = controller:invalidate_actor(
        'integration-hero', 'integration-test', 0
    )
    equal(invalidated, false, 'trigger teardown failure reports local retirement failure')
    truthy(tostring(invalidation_error):find('map-hook-removal-failed', 1, true) ~= nil,
        'trigger teardown failure keeps the Controller hook-removal error boundary')
    truthy(tostring(invalidation_error):find('trigger-remove-failed', 1, true) ~= nil,
        'trigger teardown failure retains the underlying trigger error')
    truthy(hero.sealed, 'actual Runtime commitment seals the lifecycle before trigger teardown fails')
    equal(#controller.pending_deliveries, 1,
        'actual Runtime cleanup is pending before trigger teardown failure is reported')
    equal(controller.pending_deliveries[1].payload.commands[1].type, 'cleanup_dragon_instance',
        'pending integrated delivery contains the real Dragon cleanup command')
    equal(#controller.adapter.emitted_commands, emitted_before_cleanup,
        'trigger teardown failure does not discard or prematurely emit real cleanup')
    trigger_handle.callback()
    equal(trigger_calls, 1, 'sealed integrated trigger is inert while physical removal is unresolved')

    truthy(controller:retry_pending_deliveries(),
        'real Dragon cleanup remains retryable after trigger teardown failure')
    equal(#controller.pending_deliveries, 0, 'successful integrated cleanup retry clears the queue')
    equal(#controller.adapter.emitted_commands, emitted_before_cleanup + 1,
        'integrated cleanup retry emits the real cleanup command exactly once')
    equal(controller.adapter.emitted_commands[#controller.adapter.emitted_commands].type, 'cleanup_dragon_instance',
        'integrated cleanup retry preserves the real command type')

    local authority_sequence = authority.sequence
    trigger_remove_fails = false
    local recovered, replacement_lifecycle, invalidation = controller:invalidate_actor(
        'integration-hero', 'integration-test', 1
    )
    equal(recovered, true, 'integrated retirement resumes after trigger removal recovers')
    truthy(replacement_lifecycle > hero.lifecycle_id, 'integrated invalidation advances the actor lifecycle')
    equal(invalidation.delivery_pending, false, 'recovered invalidation reuses the delivered cleanup status')
    truthy(trigger_handle.removed, 'recovered integrated retirement removes the trigger')
    equal(authority.sequence, authority_sequence,
        'integrated retirement recovery does not commit Runtime invalidation twice')
    equal(#controller.adapter.emitted_commands, emitted_before_cleanup + 1,
        'integrated retirement recovery does not emit duplicate cleanup')

    local stale, stale_error = controller:finish_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = 'integration-hero',
        lifecycle_id = hero.lifecycle_id,
        session_instance_id = start.session.session_instance_id,
        session_epoch = start.session.session_epoch,
    })
    equal(stale, false, 'old integrated actor events cannot affect a replacement lifecycle')
    equal(stale_error, 'stale-actor-lifecycle', 'integrated stale event rejection is explicit')
end

do
    local authority = new_authority()
    local hook_handle, timer_handle
    local hook_calls, timer_calls = 0, 0
    local controller = Controller.new({
        mode = 'offline_test',
        authority_provider = authority,
        progression_validator = function() return true end,
        register_hook = function(hook_key, callback)
            hook_handle = { key = hook_key, callback = callback, removed = false }
            function hook_handle:remove()
                self.removed = true
                return true
            end
            return hook_handle
        end,
        register_timer = function(timer_key, callback)
            timer_handle = { key = timer_key, callback = callback, removed = false }
            function timer_handle:remove()
                self.removed = true
                return true
            end
            return timer_handle
        end,
        resolve_logic_resource = function(key, source, expected_type)
            local ref = { id = 'cleanup-pending:' .. key }
            return {
                ref = ref,
                engine_object_id = ref.id,
                logic_key = key,
                source = source,
                type = expected_type,
            }
        end,
    })

    truthy(controller:bind_map(), 'cleanup-pending integration fixture binds the offline map')
    local registration = controller:register_actor(
        'cleanup-pending-hero', { id = 'cleanup-pending-unit' }, 'integration-team'
    )
    local started, start = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = registration.actor_id,
        lifecycle_id = registration.lifecycle_id,
    })
    truthy(started, 'cleanup-pending integration fixture starts Dragon')
    truthy(controller:install_actor_hook(registration.actor_id, 'cleanup-pending-hook', function()
        hook_calls = hook_calls + 1
    end), 'cleanup-pending integration fixture installs its actor hook')
    truthy(controller:install_actor_timer(registration.actor_id, 'cleanup-pending-timer', function()
        timer_calls = timer_calls + 1
    end), 'cleanup-pending integration fixture installs its actor timer')
    hook_handle.callback()
    timer_handle.callback()
    equal(hook_calls, 1, 'cleanup-pending hook executes before retirement')
    equal(timer_calls, 1, 'cleanup-pending timer executes before retirement')

    local finished, finish = controller:finish_dragon({
        encounter_key = start.session.encounter_key,
        actor_id = registration.actor_id,
        lifecycle_id = registration.lifecycle_id,
        session_instance_id = start.session.session_instance_id,
        session_epoch = start.session.session_epoch,
    })
    truthy(finished, 'actual Controller begins Dragon cleanup before actor retirement')
    equal(finish.commands[1].type, 'cleanup_dragon_instance',
        'actual Dragon finish uses the existing cleanup delivery command')
    local cleanup_delivery_id = finish.commands[1].delivery_id
    local authority_sequence = authority.sequence

    local removed, retirement = controller:remove_actor(registration.actor_id, 'remove', 101)
    truthy(removed, 'cleanup-pending Dragon owner can retire through actual Runtime')
    equal(controller.registrations[registration.actor_id], nil,
        'cleanup-pending retirement removes the old registration')
    truthy(registration.sealed, 'cleanup-pending retirement seals the old lifecycle')
    truthy(hook_handle.removed, 'cleanup-pending retirement removes the old hook')
    truthy(timer_handle.removed, 'cleanup-pending retirement removes the old timer')
    equal(authority.sequence, authority_sequence,
        'cleanup-pending retirement does not request a duplicate Dragon invalidation proof')
    equal(#retirement.commands, 0,
        'cleanup-pending retirement does not manufacture another cleanup command')
    hook_handle.callback()
    timer_handle.callback()
    equal(hook_calls, 1, 'retired cleanup-pending hook remains lifecycle-inert')
    equal(timer_calls, 1, 'retired cleanup-pending timer remains lifecycle-inert')

    local cleanup_commands = 0
    for _, command in ipairs(controller.adapter.emitted_commands) do
        if command.type == 'cleanup_dragon_instance' then
            cleanup_commands = cleanup_commands + 1
            equal(command.delivery_id, cleanup_delivery_id,
                'retirement preserves the original Dragon cleanup delivery identity')
        end
    end
    equal(cleanup_commands, 1,
        'cleanup-pending retirement leaves exactly one delivered Dragon cleanup command')

    local acknowledged, acknowledgement = controller:acknowledge_dragon_cleanup({
        encounter_key = start.session.encounter_key,
        actor_id = registration.actor_id,
        lifecycle_id = registration.lifecycle_id,
        session_instance_id = start.session.session_instance_id,
        session_epoch = start.session.session_epoch,
    })
    truthy(acknowledged, 'Dragon cleanup acknowledgement remains deliverable after actor retirement')
    equal(acknowledgement.commands[1].type, 'release_solo_instance_lock',
        'post-retirement acknowledgement releases the original Dragon slot')
    equal(controller.runtime.dragon_slots:get_by_actor(registration.actor_id), nil,
        'post-retirement acknowledgement closes the Dragon session')
end

do
    local authority = new_authority()
    local controller
    local admitted_lifecycle
    local replacement, replacement_error
    local reentered = false
    controller = Controller.new({
        mode = 'offline_test',
        authority_provider = authority,
        progression_validator = function(query)
            if query.actor_id == 'progression-reentry-hero'
                and query.lifecycle_id == admitted_lifecycle
                and not reentered then
                reentered = true
                replacement, replacement_error = controller:register_actor(
                    query.actor_id, { id = 'progression-reentry-unit-l2' }, 'integration-team'
                )
            end
            return true
        end,
        resolve_logic_resource = resolver('progression-reentry'),
    })

    truthy(controller:bind_map(), 'progression reentry fixture binds the actual offline map')
    local original = controller:register_actor(
        'progression-reentry-hero', { id = 'progression-reentry-unit-l1' }, 'integration-team'
    )
    admitted_lifecycle = original.lifecycle_id
    local emitted_before = #controller.adapter.emitted_commands
    local started, error_code = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = original.actor_id,
        lifecycle_id = original.lifecycle_id,
    })
    equal(reentered, true, 'actual progression callback synchronously re-registers the actor')
    truthy(replacement, 'actual progression callback creates the replacement lifecycle')
    truthy(type(replacement_error) == 'table',
        'actual progression callback replacement returns its committed retirement payload')
    equal(started, false, 'outer Dragon admission cannot commit after progression re-registration')
    equal(error_code, 'stale-actor-lifecycle',
        'actual progression re-registration reports the stale admitted lifecycle')
    equal(controller.runtime.dragon_slots:get_by_actor(original.actor_id), nil,
        'actual stale progression admission leaves every Dragon slot free')
    equal(#controller.adapter.emitted_commands, emitted_before,
        'actual stale progression admission emits no instance command')
    equal(authority.sequence, 0,
        'actual stale progression admission stops before requesting entry authority')

    local replacement_started, replacement_start = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = replacement.actor_id,
        lifecycle_id = replacement.lifecycle_id,
    })
    truthy(replacement_started, 'actual L2 can immediately start Dragon after progression reentry')
    equal(replacement_start.session.owner_lifecycle_id, replacement.lifecycle_id,
        'actual progression replacement is the committed Dragon session owner')
    equal(replacement_start.session.slot_id, 1,
        'actual progression replacement receives the first free Dragon slot')
end

do
    local authority = new_authority()
    local controller = Controller.new({
        mode = 'offline_test',
        authority_provider = authority,
        progression_validator = function() return true end,
        resolve_logic_resource = resolver('authority-reentry'),
    })
    truthy(controller:bind_map(), 'authority reentry fixture binds the actual offline map')
    local original = controller:register_actor(
        'authority-reentry-hero', { id = 'authority-reentry-unit-l1' }, 'integration-team'
    )
    local replacement, replacement_error
    local stale_entry_token
    local reentered = false
    authority:on_verify('dragon_entry', function(context, proof)
        if context.actor_id == original.actor_id
            and context.lifecycle_id == original.lifecycle_id
            and not reentered then
            reentered = true
            stale_entry_token = proof.operation_token
            replacement, replacement_error = controller:register_actor(
                original.actor_id, { id = 'authority-reentry-unit-l2' }, 'integration-team'
            )
        end
    end)

    local emitted_before = #controller.adapter.emitted_commands
    local started, error_code = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = original.actor_id,
        lifecycle_id = original.lifecycle_id,
    })
    equal(reentered, true, 'actual authority callback synchronously re-registers the actor')
    truthy(replacement, 'actual authority callback creates the replacement lifecycle')
    truthy(type(replacement_error) == 'table',
        'actual authority callback replacement returns its committed retirement payload')
    equal(started, false, 'outer Dragon admission cannot commit after authority re-registration')
    equal(error_code, 'stale-actor-lifecycle',
        'actual authority re-registration reports the stale admitted lifecycle')
    equal(controller.runtime.dragon_slots:get_by_actor(original.actor_id), nil,
        'actual stale authority admission leaves every Dragon slot free')
    equal(controller.runtime.dragon_slots.used_authority_tokens[stale_entry_token], nil,
        'actual stale authority proof is not consumed')
    equal(#controller.adapter.emitted_commands, emitted_before,
        'actual stale authority admission emits no instance command')

    local replacement_started, replacement_start = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
        actor_id = replacement.actor_id,
        lifecycle_id = replacement.lifecycle_id,
    })
    truthy(replacement_started, 'actual L2 can immediately start Dragon after authority reentry')
    equal(replacement_start.session.owner_lifecycle_id, replacement.lifecycle_id,
        'actual authority replacement is the committed Dragon session owner')
    equal(replacement_start.session.slot_id, 1,
        'actual authority replacement receives the first free Dragon slot')
end

do
    local authority = new_authority()
    local controller
    local actor_id = 'teardown-reentry-hero'
    local handles = {}
    local reentered = false
    local nested_registration, nested_registration_error
    local nested_hook_ok, nested_hook
    local nested_start_ok, nested_start
    local emitted_during_teardown
    local nested_delivery_pending_during_teardown
    local nested_hook_calls = 0
    controller = Controller.new({
        mode = 'offline_test',
        authority_provider = authority,
        progression_validator = function() return true end,
        register_hook = function(hook_key, callback)
            local handle = { key = hook_key, callback = callback, removed = false }
            function handle:remove()
                self.removed = true
                if self.key == 'outer-teardown-hook' and not reentered then
                    reentered = true
                    nested_registration, nested_registration_error = controller:register_actor(
                        actor_id, { id = 'teardown-reentry-unit-inner' }, 'integration-team'
                    )
                    nested_hook_ok, nested_hook = controller:install_actor_hook(
                        actor_id, 'inner-lifecycle-hook', function()
                            nested_hook_calls = nested_hook_calls + 1
                        end
                    )
                    nested_start_ok, nested_start = controller:start_dragon({
                        encounter_key = 'HG_E_DRAGON_OLD_TIDE',
                        actor_id = actor_id,
                        lifecycle_id = nested_registration.lifecycle_id,
                    })
                    nested_delivery_pending_during_teardown = nested_start.delivery_pending
                    emitted_during_teardown = #controller.adapter.emitted_commands
                end
                return true
            end
            handles[#handles + 1] = handle
            return handle
        end,
        resolve_logic_resource = resolver('teardown-reentry'),
    })

    truthy(controller:bind_map(), 'teardown reentry fixture binds the actual offline map')
    local original = controller:register_actor(
        actor_id, { id = 'teardown-reentry-unit-original' }, 'integration-team'
    )
    local installed, outer_hook = controller:install_actor_hook(
        actor_id, 'outer-teardown-hook', function() end
    )
    truthy(installed, 'teardown reentry fixture installs the original trigger')

    local outer_registration, outer_error = controller:register_actor(
        actor_id, { id = 'teardown-reentry-unit-outer' }, 'integration-team'
    )
    equal(reentered, true, 'actual trigger removal synchronously re-enters register_actor')
    truthy(nested_registration, 'actual trigger callback successfully registers the inner lifecycle')
    truthy(type(nested_registration_error) == 'table',
        'inner teardown registration returns the committed outer retirement payload')
    truthy(nested_hook_ok, 'inner lifecycle installs a trigger during outer teardown')
    truthy(nested_start_ok, 'inner lifecycle starts Dragon during outer teardown')
    equal(nested_delivery_pending_during_teardown, true,
        'inner instance delivery remains pending until physical teardown returns')
    equal(emitted_during_teardown, 0,
        'physical teardown callback cannot drain instance commands reentrantly')
    equal(outer_registration, nil,
        'outer registration exits instead of overwriting the inner registration')
    equal(outer_error, 'actor-registration-superseded',
        'outer registration reports its retirement identity was superseded')
    equal(controller.registrations[actor_id], nested_registration,
        'inner registration remains the current lifecycle after outer teardown returns')
    equal(controller.runtime.dragon_slots:get_by_actor(actor_id).owner_lifecycle_id,
        nested_registration.lifecycle_id,
        'inner Dragon session owner remains aligned with the current registration')
    equal(nested_start.delivery_pending, false,
        'outer teardown completion drains the retained inner delivery')
    equal(#controller.adapter.emitted_commands, 2,
        'inner Dragon commands emit exactly once after outer teardown completes')
    equal(outer_hook.removed, true, 'outer lifecycle trigger is physically removed')
    equal(nested_hook.removed, false, 'outer lifecycle teardown does not remove the inner trigger')
    nested_hook.callback()
    equal(nested_hook_calls, 1, 'inner trigger remains live after outer teardown')

    local finished, finish = controller:finish_dragon({
        encounter_key = nested_start.session.encounter_key,
        actor_id = actor_id,
        lifecycle_id = nested_registration.lifecycle_id,
        session_instance_id = nested_start.session.session_instance_id,
        session_epoch = nested_start.session.session_epoch,
    })
    truthy(finished, 'inner session owner remains usable after outer registration exits')
    equal(finish.commands[1].type, 'cleanup_dragon_instance',
        'inner session owner can commit its Dragon cleanup')
    truthy(controller:remove_actor(actor_id, 'remove', 200),
        'inner registration can retire after the reentrant chain')
    equal(nested_hook.removed, true,
        'inner lifecycle retirement still finds and removes its own trigger')
    equal(original.sealed, true, 'original lifecycle remains sealed after the reentrant retirement')
end

print('PASS: ' .. tests .. ' controller runtime adapter integration assertions')
