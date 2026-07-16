package.path = 'implementation/huaguoshan/lua/?.lua;' .. package.path

local Adapter = require 'huaguoshan_y3_adapter'
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

local function append(list, value)
    list[#list + 1] = value
end

local function new_runtime()
    local runtime = { invalidations = 0, last_tick = nil }

    function runtime:invalidate_actor(actor_id, lifecycle_id)
        self.invalidations = self.invalidations + 1
        return true, {
            actor_id = actor_id,
            lifecycle_id = lifecycle_id,
            commands = {},
        }
    end

    function runtime:tick(now)
        self.last_tick = now
        return { now = now, commands = {} }
    end

    return runtime
end

do
    local handles = {}
    local controller
    local fresh_registration
    local adapter = Adapter.new({
        mode = 'offline_test',
        register_hook = function(hook_key, callback)
            local handle = {
                key = hook_key,
                callback = callback,
                removed = false,
                remove_attempts = 0,
            }
            function handle:remove()
                self.remove_attempts = self.remove_attempts + 1
                if self.key == 'old-hook' and self.remove_attempts == 1 then
                    fresh_registration = controller:register_actor(
                        'retry-actor', { id = 'fresh-unit' }, 'team'
                    )
                    return false, 'trigger-remove-failed'
                end
                self.removed = true
                return true
            end
            append(handles, handle)
            return handle
        end,
    })
    local runtime = new_runtime()
    controller = Controller.new({ adapter = adapter, runtime = runtime })

    local original = controller:register_actor('retry-actor', { id = 'old-unit' }, 'team')
    local old_calls = 0
    local installed, old_handle = controller:install_actor_hook('retry-actor', 'old-hook', function()
        old_calls = old_calls + 1
    end)
    truthy(installed, 'actual Adapter installs the old lifecycle trigger')
    old_handle.callback()
    equal(old_calls, 1, 'old lifecycle trigger runs while current')

    local removed, removal_error = controller:remove_actor('retry-actor', 'remove', 100)
    equal(removed, false, 'false returned by trigger remove keeps retirement pending')
    equal(removal_error, 'trigger-remove-failed', 'trigger remove error is forwarded')
    truthy(fresh_registration, 'trigger teardown reentry installs a fresh lifecycle')
    equal(controller.registrations['retry-actor'], fresh_registration,
        'fresh lifecycle remains current after old trigger removal fails')
    truthy(fresh_registration.lifecycle_id > original.lifecycle_id,
        'fresh lifecycle has a distinct identity')
    truthy(original.sealed, 'old lifecycle is sealed before physical trigger removal')
    equal(old_handle.removed, false, 'failed trigger remains physically registered')
    truthy(adapter.owner_hooks[original.owner_key], 'failed trigger owner registry is retained')
    equal(#adapter.owner_hooks[original.owner_key], 1,
        'failed trigger owner registry retains exactly the failed handle')
    equal(adapter.owner_hooks[original.owner_key][1], old_handle,
        'failed trigger handle identity remains retryable')
    equal(#controller.pending_retirement_order, 1,
        'Controller retains the detached old retirement for tick retry')

    old_handle.callback()
    equal(old_calls, 1, 'physically registered old trigger cannot affect the fresh actor')

    local fresh_calls = 0
    local fresh_installed, fresh_handle = controller:install_actor_hook(
        'retry-actor', 'fresh-hook', function() fresh_calls = fresh_calls + 1 end
    )
    truthy(fresh_installed, 'fresh lifecycle can install its own trigger while old retirement is pending')
    fresh_handle.callback()
    equal(fresh_calls, 1, 'fresh lifecycle trigger remains active during old retirement retry')

    local ticked = controller:tick(101)
    truthy(ticked, 'later tick retries and completes the failed trigger removal')
    equal(runtime.last_tick, 101, 'Runtime tick resumes after retirement convergence')
    equal(old_handle.remove_attempts, 2, 'old trigger removal is retried exactly once')
    truthy(old_handle.removed, 'old trigger is physically removed on retry')
    equal(adapter.owner_hooks[original.owner_key], nil,
        'successful retry releases only the old owner registry')
    equal(#controller.pending_retirement_order, 0,
        'successful retry clears deterministic retirement order')
    equal(controller.pending_retirements[original.retirement_token], nil,
        'successful retry clears the old retirement identity')
    equal(controller.registrations['retry-actor'], fresh_registration,
        'old retirement convergence preserves the fresh actor')
    equal(fresh_handle.removed, false, 'old retirement retry does not remove the fresh trigger')
    fresh_handle.callback()
    equal(fresh_calls, 2, 'fresh trigger still runs after old retirement convergence')
    old_handle.callback()
    equal(old_calls, 1, 'old trigger callback stays lifecycle-inert after physical removal')
    equal(runtime.invalidations, 1, 'old Runtime lifecycle is invalidated exactly once')
end

do
    local handles = {}
    local adapter = Adapter.new({
        mode = 'offline_test',
        register_hook = function(hook_key, callback)
            local handle = {
                key = hook_key,
                callback = callback,
                removed = false,
                remove_attempts = 0,
            }
            function handle:remove()
                self.remove_attempts = self.remove_attempts + 1
                if self.key == 'throwing-hook' and self.remove_attempts == 1 then
                    error('trigger-remove-threw')
                end
                self.removed = true
                return true
            end
            append(handles, handle)
            return handle
        end,
    })
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })
    local registration = controller:register_actor('multi-hook-actor', { id = 'unit' }, 'team')

    local first_installed, first_handle = controller:install_actor_hook(
        'multi-hook-actor', 'first-hook', function() end
    )
    local throwing_installed, throwing_handle = controller:install_actor_hook(
        'multi-hook-actor', 'throwing-hook', function() end
    )
    local last_installed, last_handle = controller:install_actor_hook(
        'multi-hook-actor', 'last-hook', function() end
    )
    truthy(first_installed and throwing_installed and last_installed,
        'multi-hook retirement installs all trigger handles')

    local removed, removal_error = controller:remove_actor('multi-hook-actor', 'remove', 200)
    equal(removed, false, 'one throwing trigger keeps the actor retirement pending')
    truthy(tostring(removal_error):find('map-hook-removal-failed', 1, true) ~= nil,
        'throwing trigger preserves the Controller removal error boundary')
    truthy(tostring(removal_error):find('trigger-remove-threw', 1, true) ~= nil,
        'throwing trigger preserves the underlying removal error')
    equal(first_handle.remove_attempts, 1, 'the first trigger is removed once before the throw')
    truthy(first_handle.removed, 'the first trigger removal succeeds')
    equal(throwing_handle.remove_attempts, 1, 'the throwing trigger is attempted once')
    equal(throwing_handle.removed, false, 'the throwing trigger remains physically registered')
    equal(last_handle.remove_attempts, 1, 'later triggers are still processed after the throw')
    truthy(last_handle.removed, 'the later trigger removal succeeds in the same pass')
    equal(#adapter.owner_hooks[registration.owner_key], 1,
        'only the throwing trigger remains in the owner retry registry')
    equal(adapter.owner_hooks[registration.owner_key][1], throwing_handle,
        'the owner retry registry retains the failed trigger identity')
    equal(#controller.pending_retirement_order, 1,
        'the partial trigger failure retains one Controller retirement')

    local ticked = controller:tick(201)
    truthy(ticked, 'the next tick retries the failed trigger and converges retirement')
    equal(runtime.last_tick, 201, 'Runtime tick runs after trigger retirement converges')
    equal(first_handle.remove_attempts, 1, 'the successful first trigger is not retried')
    equal(throwing_handle.remove_attempts, 2, 'only the failed trigger is retried')
    equal(last_handle.remove_attempts, 1, 'the successful later trigger is not retried')
    truthy(throwing_handle.removed, 'the failed trigger is removed on retry')
    equal(adapter.owner_hooks[registration.owner_key], nil,
        'converged trigger retirement releases the owner retry registry')
    equal(#controller.pending_retirement_order, 0,
        'converged trigger retirement clears deterministic retry order')
    equal(controller.pending_retirements[registration.retirement_token], nil,
        'converged trigger retirement clears its retirement identity')
    equal(controller.registrations['multi-hook-actor'], nil,
        'converged trigger retirement removes the sealed actor registration')
    equal(runtime.invalidations, 1, 'trigger retry does not repeat Runtime invalidation')
end

do
    local registered = {}
    local register_calls = 0
    local adapter = Adapter.new({
        mode = 'offline_test',
        register_hook = function(hook_key, callback)
            register_calls = register_calls + 1
            local handle = { key = hook_key, callback = callback }
            append(registered, handle)
            return handle
        end,
    })
    local controller = Controller.new({ adapter = adapter, runtime = new_runtime() })
    local registration = controller:register_actor('nil-callback', { id = 'unit' }, 'team')

    local installed, install_error = controller:install_actor_hook('nil-callback', 'nil-hook', nil)
    equal(installed, false, 'nil actor hook callback is rejected before Adapter registration')
    equal(install_error, 'map-hook-callback-required', 'nil callback rejection has a stable error')
    equal(register_calls, 0, 'nil callback rejection does not register a trigger')
    equal(#registered, 0, 'nil callback rejection leaves the map trigger list empty')
    equal(adapter.owner_hooks[registration.owner_key], nil,
        'nil callback rejection creates no owner registry entry')

    local nil_trigger_ok, nil_trigger_error = pcall(function()
        for _, handle in ipairs(registered) do
            if handle.key == 'nil-hook' then handle.callback() end
        end
    end)
    truthy(nil_trigger_ok, 'firing the rejected trigger key cannot call nil: ' .. tostring(nil_trigger_error))

    local valid_calls = 0
    truthy(controller:install_actor_hook('nil-callback', 'valid-hook', function()
        valid_calls = valid_calls + 1
    end), 'a later valid callback still registers normally')
    equal(register_calls, 1, 'only the valid callback reaches the Adapter registrar')
    local valid_trigger_ok, valid_trigger_error = pcall(function()
        for _, handle in ipairs(registered) do
            if handle.key == 'valid-hook' then handle.callback() end
        end
    end)
    truthy(valid_trigger_ok, 'valid trigger dispatch remains error-free: ' .. tostring(valid_trigger_error))
    equal(valid_calls, 1, 'valid trigger dispatch calls only the valid callback')
end

do
    local remove_calls = 0
    local adapter = Adapter.new({
        mode = 'offline_test',
        register_hook = function(hook_key)
            if hook_key == 'returned-false-hook' then return false end
            error('hook-registration-threw')
        end,
        remove_hook = function()
            remove_calls = remove_calls + 1
            return true
        end,
    })

    local false_call_ok, false_installed, false_error = pcall(function()
        return adapter:install_hook('returned-false-owner', 'returned-false-hook', function() end)
    end)
    truthy(false_call_ok, 'false hook registration result is returned instead of thrown')
    equal(false_installed, false, 'false hook registration result is rejected')
    equal(false_error, 'map-hook-registration-failed',
        'false hook registration result has a stable error')
    equal(adapter.owner_hooks['returned-false-owner'], nil,
        'false hook registration result is not retained as a removable handle')

    local thrown_call_ok, thrown_installed, thrown_error = pcall(function()
        return adapter:install_hook('throwing-owner', 'throwing-hook', function() end)
    end)
    truthy(thrown_call_ok, 'throwing hook registrar is converted into a normal return')
    equal(thrown_installed, false, 'throwing hook registrar reports registration failure')
    equal(thrown_error, 'map-hook-registration-failed',
        'throwing hook registrar has a stable error')
    equal(adapter.owner_hooks['throwing-owner'], nil,
        'throwing hook registrar creates no owner registry entry')
    truthy(adapter:remove_owner_hooks('returned-false-owner'),
        'returned false leaves no hook cleanup work')
    truthy(adapter:remove_owner_hooks('throwing-owner'),
        'thrown registration leaves no hook cleanup work')
    equal(remove_calls, 0, 'failed hook registrations never reach the external remover')
end

do
    local adapter = Adapter.new({ mode = 'offline_test' })
    local runtime = new_runtime()
    local handles = {}
    local controller = Controller.new({
        adapter = adapter,
        runtime = runtime,
        register_timer = function(timer_key, callback)
            local handle = {
                key = timer_key,
                callback = callback,
                removed = false,
                remove_attempts = 0,
            }
            function handle:remove()
                self.remove_attempts = self.remove_attempts + 1
                if self.removed then error('timer-removal-is-not-idempotent:' .. self.key) end
                if self.key == 'retry-timer' and self.remove_attempts == 1 then
                    return false, 'timer-remove-failed'
                end
                self.removed = true
                return true
            end
            append(handles, handle)
            return handle
        end,
    })
    local registration = controller:register_actor('multi-timer-actor', { id = 'unit' }, 'team')

    local first_installed, first_handle = controller:install_actor_timer(
        'multi-timer-actor', 'first-timer', function() end
    )
    local retry_installed, retry_handle = controller:install_actor_timer(
        'multi-timer-actor', 'retry-timer', function() end
    )
    local last_installed, last_handle = controller:install_actor_timer(
        'multi-timer-actor', 'last-timer', function() end
    )
    truthy(first_installed and retry_installed and last_installed,
        'multi-timer retirement installs all direct timer handles')

    local removed, removal_error = controller:remove_actor('multi-timer-actor', 'remove', 300)
    equal(removed, false, 'one failed timer keeps the actor retirement pending')
    equal(removal_error, 'timer-remove-failed', 'failed timer removal error is forwarded')
    equal(first_handle.remove_attempts, 1, 'the first timer is removed once before the failure')
    truthy(first_handle.removed, 'the first timer removal succeeds')
    equal(retry_handle.remove_attempts, 1, 'the failed timer is attempted once')
    equal(retry_handle.removed, false, 'the failed timer remains physically registered')
    equal(last_handle.remove_attempts, 1, 'later timers are still processed after a failure')
    truthy(last_handle.removed, 'the later timer removal succeeds in the same pass')
    equal(#controller.owner_timers[registration.owner_key], 1,
        'only the failed timer remains in the owner retry registry')
    equal(controller.owner_timers[registration.owner_key][1].handle, retry_handle,
        'the owner retry registry retains the failed timer identity')
    equal(#controller.pending_retirement_order, 1,
        'the partial timer failure retains one Controller retirement')

    local ticked = controller:tick(301)
    truthy(ticked, 'the next tick retries only the failed timer and converges retirement')
    equal(runtime.last_tick, 301, 'Runtime tick runs after timer retirement converges')
    equal(first_handle.remove_attempts, 1, 'the successful first timer is never retried')
    equal(retry_handle.remove_attempts, 2, 'only the failed timer is retried')
    equal(last_handle.remove_attempts, 1, 'the successful later timer is never retried')
    truthy(retry_handle.removed, 'the failed timer is removed on retry')
    equal(controller.owner_timers[registration.owner_key], nil,
        'converged timer retirement releases the owner retry registry')
    equal(#controller.pending_retirement_order, 0,
        'converged timer retirement clears deterministic retry order')
    equal(controller.registrations['multi-timer-actor'], nil,
        'converged timer retirement removes the sealed actor registration')
    equal(runtime.invalidations, 1, 'timer retry does not repeat Runtime invalidation')
end

do
    local adapter = Adapter.new({ mode = 'offline_test' })
    local register_calls = 0
    local controller = Controller.new({
        adapter = adapter,
        runtime = new_runtime(),
        register_timer = function()
            register_calls = register_calls + 1
            error('timer-registration-threw')
        end,
    })
    local registration = controller:register_actor('throwing-timer-owner', { id = 'unit' }, 'team')

    local call_ok, installed, install_error = pcall(function()
        return controller:install_actor_timer('throwing-timer-owner', 'throwing-timer', function() end)
    end)
    truthy(call_ok, 'throwing direct timer registrar is converted into a normal return')
    equal(installed, false, 'throwing direct timer registrar reports registration failure')
    equal(install_error, 'map-timer-registration-failed',
        'throwing direct timer registrar has a stable error')
    equal(register_calls, 1, 'throwing direct timer registrar is called exactly once')
    equal(controller.owner_timers[registration.owner_key], nil,
        'throwing direct timer registrar creates no owner timer entry')
end

print('PASS: ' .. tests .. ' controller runtime adapter assertions')
