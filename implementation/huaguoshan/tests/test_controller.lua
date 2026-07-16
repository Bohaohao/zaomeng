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

local function append(list, value)
    list[#list + 1] = value
end

local function new_adapter()
    local adapter = {
        emitted = {},
        hooks = {},
        timers = {},
        gate_calls = {},
        blocked = false,
    }

    function adapter:bind_map()
        return true
    end

    function adapter:can_start_encounter(encounter_key)
        append(self.gate_calls, encounter_key)
        if self.blocked then return false, 'encounter-disabled' end
        return true
    end

    function adapter:emit(payload)
        if self.fail_next_emit then
            local error_code = self.fail_next_emit
            self.fail_next_emit = nil
            return false, error_code
        end
        for _, command in ipairs((payload and payload.commands) or {}) do
            append(self.emitted, command)
            local callback = self.on_emit
            self.on_emit = nil
            if callback then callback(command) end
        end
        return true
    end

    function adapter:install_hook(owner_key, hook_key, callback)
        local handle = { owner_key = owner_key, key = hook_key, callback = callback, removed = false }
        local list = self.hooks[owner_key] or {}
        self.hooks[owner_key] = list
        append(list, handle)
        return true, handle
    end

    function adapter:install_timer(owner_key, timer_key, callback)
        local handle = { owner_key = owner_key, key = timer_key, callback = callback, removed = false }
        local list = self.timers[owner_key] or {}
        self.timers[owner_key] = list
        append(list, handle)
        return true, handle
    end

    function adapter:remove_owner_hooks(owner_key)
        for _, handle in ipairs(self.hooks[owner_key] or {}) do handle.removed = true end
        self.hooks[owner_key] = nil
    end

    function adapter:remove_owner_timers(owner_key)
        for _, handle in ipairs(self.timers[owner_key] or {}) do handle.removed = true end
        self.timers[owner_key] = nil
    end

    function adapter:can_activate_live_encounters()
        return false, 'real-map-binding-not-verified'
    end

    return adapter
end

local function new_runtime()
    local runtime = {
        binding = {},
        calls = {
            invalidations = {},
            public_damage = {},
            starts = { public_boss = 0, public_trace = 0, dragon = 0, ox = 0 },
        },
    }

    function runtime:invalidate_actor(actor_id, lifecycle_id, now, reason)
        append(self.calls.invalidations, {
            actor_id = actor_id, lifecycle_id = lifecycle_id, now = now, reason = reason,
        })
        return true, {
            commands = { { type = 'runtime_actor_invalidated', actor_id = actor_id, lifecycle_id = lifecycle_id } },
        }
    end

    function runtime:validate_actor_invalidation()
        return true
    end

    function runtime:start_public_boss(encounter_key, options)
        self.calls.starts.public_boss = self.calls.starts.public_boss + 1
        return true, { encounter_key = encounter_key, options = options }
    end

    function runtime:start_public_trace(encounter_key, options)
        self.calls.starts.public_trace = self.calls.starts.public_trace + 1
        return true, { encounter_key = encounter_key, options = options }
    end

    function runtime:start_dragon(request, now)
        self.calls.starts.dragon = self.calls.starts.dragon + 1
        self.calls.last_dragon_start = request
        return true, { commands = { { type = 'dragon_started', now = now } } }
    end

    function runtime:finish_dragon(event)
        self.calls.last_dragon_finish = event
        return true, { commands = { { type = 'dragon_cleanup_requested' } } }
    end

    function runtime:acknowledge_dragon_cleanup(acknowledgement)
        self.calls.last_dragon_ack = acknowledgement
        return true, { commands = { { type = 'dragon_lock_released' } } }
    end

    function runtime:start_ox(request, now)
        self.calls.starts.ox = self.calls.starts.ox + 1
        self.calls.last_ox_start = request
        return true, { commands = { { type = 'ox_started', now = now } } }
    end

    function runtime:swap_ox_phase(identity)
        self.calls.last_ox_swap = identity
        return true, { commands = { { type = 'ox_phase_swapped' } } }
    end

    function runtime:fail_ox(event, now)
        self.calls.last_ox_fail = event
        self.calls.last_ox_fail_at = now
        return true, { commands = { { type = 'ox_cleanup_requested', reason = event.reason } } }
    end

    function runtime:succeed_ox(identity, now)
        self.calls.last_ox_success = identity
        self.calls.last_ox_success_at = now
        return true, { commands = { { type = 'ox_cleanup_requested', reason = 'success' } } }
    end

    function runtime:acknowledge_ox_cleanup(acknowledgement)
        self.calls.last_ox_ack = acknowledgement
        return true, { commands = { { type = 'ox_locks_released' } } }
    end

    function runtime:report_public_damage(event)
        append(self.calls.public_damage, event)
        return true, { commands = { { type = 'public_damage_recorded', event_id = event.event_id } } }
    end

    function runtime:change_public_boss_phase(boss_instance_id, transition_event)
        self.calls.last_public_phase_transition = {
            boss_instance_id = boss_instance_id, event = transition_event,
        }
        return true, { commands = { { type = 'public_boss_phase_changed', event_id = transition_event.event_id } } }
    end

    function runtime:finalize_public_boss(boss_instance_id, finalization_event)
        self.calls.last_public_boss_finalization = {
            boss_instance_id = boss_instance_id, event = finalization_event,
        }
        return true, { commands = { { type = 'public_boss_finalized', event_id = finalization_event.event_id } } }
    end

    function runtime:apply_public_water_chain(boss_instance_id)
        self.calls.last_public_water_chain = boss_instance_id
        return true, { commands = { {
            type = 'apply_mechanic', encounter_key = 'HG_E_JIAO_KING', boss_instance_id = boss_instance_id,
        } } }
    end

    function runtime:tick(now)
        self.calls.last_tick = now
        return { commands = { { type = 'runtime_tick', now = now } } }
    end

    return runtime
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })
    truthy(controller:bind_map(), 'controller delegates map binding')
    local hero = controller:register_actor('hero', { id = 'hero-unit' }, 'team-red')
    local ally = controller:register_actor('ally', { id = 'ally-unit' }, 'team-red')

    local rejected, rejected_error = controller:begin_public_action('boss', {
        actor_id = 'hero', lifecycle_id = hero.lifecycle_id, authority_verified = true,
    })
    equal(rejected, false, 'Controller rejects caller-supplied Boss action authority claims')
    equal(rejected_error, 'untrusted-authority-field:authority_verified',
        'Boss action authority claims have a stable rejection')
    rejected, rejected_error = controller:begin_public_trace_action('trace', 'hero', hero.lifecycle_id, 0)
    equal(rejected, false, 'Controller rejects legacy trace authority arguments')
    equal(rejected_error, 'legacy-authority-arguments-forbidden',
        'trace legacy authority rejection is explicit')
    rejected, rejected_error = controller:complete_public_trace_action({
        actor_id = 'hero', lifecycle_id = hero.lifecycle_id, sync_tick = 1,
    })
    equal(rejected, false, 'Controller rejects caller-supplied trace completion timing')
    equal(rejected_error, 'caller-trace-timing-forbidden',
        'trace completion timing rejection is explicit')
    rejected, rejected_error = controller:change_public_boss_phase('boss', {
        authority_verified = true,
    })
    equal(rejected, false, 'Controller rejects caller-supplied phase authority claims')
    equal(rejected_error, 'untrusted-authority-field:authority_verified',
        'phase authority rejection is explicit')
    rejected, rejected_error = controller:finalize_public_boss('boss', {
        authority_verified = true,
    })
    equal(rejected, false, 'Controller rejects caller-supplied finalization authority claims')
    equal(rejected_error, 'untrusted-authority-field:authority_verified',
        'finalization authority rejection is explicit')

    rejected, rejected_error = controller:start_ox({
        entry_request_id = 'controller-forged-members', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
        members = { { actor_id = 'hero', lifecycle_id = hero.lifecycle_id } },
    })
    equal(rejected, false, 'Controller rejects caller-supplied raid member snapshots')
    equal(rejected_error, 'untrusted-instance-authority-field:members',
        'raid member snapshot rejection is explicit at the Controller boundary')
    rejected, rejected_error = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
    }, 1)
    equal(rejected, false, 'Controller rejects a caller-provided Dragon clock')
    equal(rejected_error, 'caller-instance-time-forbidden', 'Dragon clock rejection is explicit at the Controller boundary')
    rejected, rejected_error = controller:finish_dragon({
        actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
        session_instance_id = 'dragon:forged', session_epoch = 1, reason = 'success',
    })
    equal(rejected, false, 'Controller rejects caller-supplied Dragon completion reasons')
    equal(rejected_error, 'untrusted-instance-authority-field:reason',
        'Dragon completion reason rejection is explicit at the Controller boundary')
    rejected, rejected_error = controller:acknowledge_dragon_cleanup({
        actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
        session_instance_id = 'dragon:forged', session_epoch = 1, cleanup_token = 'forged-cleanup',
    })
    equal(rejected, false, 'Controller rejects caller-supplied Dragon cleanup tokens')
    equal(rejected_error, 'untrusted-instance-authority-field:cleanup_token',
        'Dragon cleanup token rejection is explicit at the Controller boundary')

    adapter.blocked = true
    local ok, error_code = controller:start_public_boss('HG_E_MACAQUE_KING', { boss_instance_id = 'boss' })
    equal(ok, false, 'public boss start obeys adapter encounter gate')
    equal(error_code, 'encounter-disabled', 'public boss forwards gate rejection')
    equal(runtime.calls.starts.public_boss, 0, 'blocked public boss never reaches runtime')

    ok = controller:start_public_trace('HG_E_TIDE_TRACE', { instance_id = 'trace' })
    equal(ok, false, 'public trace start obeys adapter encounter gate')
    equal(runtime.calls.starts.public_trace, 0, 'blocked public trace never reaches runtime')

    ok = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
    })
    equal(ok, false, 'Dragon start obeys adapter encounter gate')
    equal(runtime.calls.starts.dragon, 0, 'blocked Dragon never reaches runtime')

    ok = controller:start_ox({
        entry_request_id = 'controller-gate:blocked', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
    })
    equal(ok, false, 'Ox start obeys adapter encounter gate')
    equal(runtime.calls.starts.ox, 0, 'blocked Ox never reaches runtime')

    adapter.blocked = false
    truthy(controller:start_public_boss('HG_E_MACAQUE_KING', { boss_instance_id = 'boss' }), 'allowed public boss reaches runtime')
    truthy(controller:start_public_trace('HG_E_TIDE_TRACE', { instance_id = 'trace' }), 'allowed public trace reaches runtime')
    truthy(controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
    }), 'allowed Dragon reaches runtime')
    truthy(controller:start_ox({
        entry_request_id = 'controller-gate:allowed', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
    }), 'allowed Ox reaches runtime')
    equal(runtime.calls.starts.public_boss, 1, 'public boss runtime start occurs once')
    equal(runtime.calls.starts.public_trace, 1, 'public trace runtime start occurs once')
    equal(runtime.calls.starts.dragon, 1, 'Dragon runtime start occurs once')
    equal(runtime.calls.starts.ox, 1, 'Ox runtime start occurs once')

    local phase_event = {
        kind = 'boss_phase_transition', event_id = 'phase:controller:1', boss_instance_id = 'boss',
        combat_scope = 'public',
        from_phase = 'phase-1', boss_target_id = 'boss-unit', boss_target_lifecycle_id = 'boss-life',
        to_phase = 'phase-2', next_boss_target_id = 'boss-unit-2', next_boss_target_lifecycle_id = 'boss-life-2',
    }
    truthy(controller:change_public_boss_phase('boss', phase_event),
        'Controller forwards the full compare-and-swap Boss phase event')
    equal(runtime.calls.last_public_phase_transition.event, phase_event,
        'Controller leaves the Boss phase event intact for runtime identity validation')
    local finalization_event = {
        kind = 'boss_finalization', event_id = 'final:controller:1', boss_instance_id = 'boss',
        combat_scope = 'public',
        from_phase = 'phase-2', boss_target_id = 'boss-unit-2', boss_target_lifecycle_id = 'boss-life-2',
    }
    truthy(controller:finalize_public_boss('boss', finalization_event),
        'Controller forwards the full compare-and-swap Boss finalization event')
    equal(runtime.calls.last_public_boss_finalization.event, finalization_event,
        'Controller leaves the Boss finalization event intact for runtime identity validation')
    truthy(controller:apply_public_water_chain('boss'),
        'Controller dispatches the explicit public water-chain application path')
    equal(runtime.calls.last_public_water_chain, 'boss',
        'Controller keeps the Boss instance identity on water-chain application')

    local ready, ready_error = controller:live_activation_ready()
    equal(ready, false, 'live activation remains adapter-gated')
    equal(ready_error, 'real-map-binding-not-verified', 'live activation reports adapter reason')
end

do
    local adapter = new_adapter()
    adapter.can_start_encounter = nil
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })
    local ok, error_code = controller:start_public_boss('HG_E_MACAQUE_KING', {})
    equal(ok, false, 'missing encounter gate rejects start')
    equal(error_code, 'encounter-start-gate-unavailable', 'missing gate has a stable error')
    equal(runtime.calls.starts.public_boss, 0, 'missing gate never reaches runtime')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })

    local old = controller:register_actor('hero', { id = 'old-unit' }, 'team-red')
    local hook_calls, timer_calls = 0, 0
    local hook_ok, old_hook = controller:install_actor_hook('hero', 'damage-hook', function() hook_calls = hook_calls + 1 end)
    local timer_ok, old_timer = controller:install_actor_timer('hero', 'delay-timer', function() timer_calls = timer_calls + 1 end)
    truthy(hook_ok, 'actor hook installs with lifecycle wrapper')
    truthy(timer_ok, 'actor timer installs with lifecycle wrapper')
    old_hook.callback()
    old_timer.callback()
    equal(hook_calls, 1, 'current actor hook executes')
    equal(timer_calls, 1, 'current actor timer executes')

    adapter.on_emit = function()
        truthy(old.sealed, 're-register seals old lifecycle before emitter')
        truthy(old_hook.removed, 're-register removes old hook before emitter')
        truthy(old_timer.removed, 're-register removes old timer before emitter')
        old_hook.callback()
        old_timer.callback()
        equal(hook_calls, 1, 'old hook is inert inside reentrant emitter')
        equal(timer_calls, 1, 'old timer is inert inside reentrant emitter')
        equal(controller.registrations.hero.unit_ref.id, 'fresh-unit', 'new registration exists before emitter')
        local stale = controller:report_public_damage({
            actor_id = 'hero', lifecycle_id = old.lifecycle_id, event_id = 'old-emitter-event',
        })
        equal(stale, false, 'old unit event is rejected inside reentrant emitter')
    end
    local fresh = controller:register_actor('hero', { id = 'fresh-unit' }, 'team-red')
    truthy(fresh.lifecycle_id > old.lifecycle_id, 'same-id re-registration advances lifecycle')
    truthy(controller.registrations.hero == fresh, 'same-id re-registration keeps the new unit current')

    local stale, stale_error = controller:report_public_damage({
        actor_id = 'hero', lifecycle_id = old.lifecycle_id, event_id = 'old-event',
    })
    equal(stale, false, 'old unit event cannot affect same-id replacement')
    equal(stale_error, 'stale-actor-lifecycle', 'old unit event has explicit lifecycle rejection')
    equal(#runtime.calls.public_damage, 0, 'stale event never reaches runtime')
    truthy(controller:report_public_damage({
        actor_id = 'hero', lifecycle_id = fresh.lifecycle_id, event_id = 'fresh-event',
    }), 'fresh unit event reaches runtime')
    equal(#runtime.calls.public_damage, 1, 'only fresh event reaches runtime')

    local invalidated = controller:register_actor('invalidate-me', { id = 'same-unit' }, 'team-blue')
    local invalid_hook_calls, invalid_timer_calls = 0, 0
    local _, invalid_hook = controller:install_actor_hook('invalidate-me', 'hook', function()
        invalid_hook_calls = invalid_hook_calls + 1
    end)
    local _, invalid_timer = controller:install_actor_timer('invalidate-me', 'timer', function()
        invalid_timer_calls = invalid_timer_calls + 1
    end)
    adapter.on_emit = function()
        truthy(invalidated.sealed, 'invalidate seals old registration before emitter')
        truthy(invalid_hook.removed, 'invalidate removes hook before emitter')
        truthy(invalid_timer.removed, 'invalidate removes timer before emitter')
        invalid_hook.callback()
        invalid_timer.callback()
        equal(invalid_hook_calls, 0, 'invalidated hook is inert during emitter')
        equal(invalid_timer_calls, 0, 'invalidated timer is inert during emitter')
        truthy(controller.registrations['invalidate-me'].lifecycle_id > invalidated.lifecycle_id, 'replacement lifecycle exists before emitter')
    end
    local invalidate_ok, replacement_lifecycle = controller:invalidate_actor('invalidate-me', 'unit-replaced', 10)
    truthy(invalidate_ok, 'invalidate creates a replacement lifecycle')
    truthy(replacement_lifecycle > invalidated.lifecycle_id, 'invalidate advances lifecycle identity')

    local removed = controller:register_actor('remove-me', { id = 'removed-unit' }, 'team-green')
    local remove_hook_calls = 0
    local _, remove_hook = controller:install_actor_hook('remove-me', 'remove-hook', function()
        remove_hook_calls = remove_hook_calls + 1
    end)
    local reentrant_registration
    adapter.on_emit = function()
        truthy(removed.sealed, 'remove seals lifecycle before emitter')
        truthy(remove_hook.removed, 'remove unregisters hook before emitter')
        equal(controller.registrations['remove-me'], nil, 'remove clears old registration before emitter')
        remove_hook.callback()
        equal(remove_hook_calls, 0, 'removed hook is inert during emitter')
        reentrant_registration = controller:register_actor('remove-me', { id = 'reentrant-unit' }, 'team-green')
    end
    truthy(controller:remove_actor('remove-me', 'remove', 20), 'remove completes with a reentrant emitter')
    truthy(controller.registrations['remove-me'] == reentrant_registration, 'remove does not clobber reentrant same-id registration')
    truthy(reentrant_registration.lifecycle_id > removed.lifecycle_id, 'reentrant registration receives a fresh lifecycle')

    equal(runtime.calls.invalidations[1].lifecycle_id, old.lifecycle_id, 're-register invalidates the old lifecycle')
    equal(runtime.calls.invalidations[2].lifecycle_id, invalidated.lifecycle_id, 'invalidate forwards the sealed lifecycle')
    equal(runtime.calls.invalidations[3].lifecycle_id, removed.lifecycle_id, 'remove forwards the sealed lifecycle')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })
    local registration = controller:register_actor('retiring-rejection', { id = 'retiring-unit' }, 'team')
    local hook_calls, timer_calls = 0, 0
    local _, hook = controller:install_actor_hook('retiring-rejection', 'retiring-hook', function()
        hook_calls = hook_calls + 1
    end)
    local _, timer = controller:install_actor_timer('retiring-rejection', 'retiring-timer', function()
        timer_calls = timer_calls + 1
    end)

    runtime.invalidate_actor = function(self, actor_id, lifecycle_id)
        append(self.calls.invalidations, { actor_id = actor_id, lifecycle_id = lifecycle_id })
        equal(registration.retiring, true,
            'Controller marks a lifecycle retiring before Runtime invalidation')
        hook.callback()
        timer.callback()
        equal(hook_calls, 0, 'retiring lifecycle hook is inert inside Runtime invalidation')
        equal(timer_calls, 0, 'retiring lifecycle timer is inert inside Runtime invalidation')
        local accepted, error_code = controller:report_public_damage({
            actor_id = actor_id,
            lifecycle_id = lifecycle_id,
            event_id = 'retiring-runtime-reentry',
        })
        equal(accepted, false, 'retiring lifecycle event is rejected inside Runtime invalidation')
        equal(error_code, 'actor-lifecycle-retiring',
            'retiring lifecycle rejection is explicit')
        return false, 'runtime-invalidation-rejected'
    end

    local removed, error_code = controller:remove_actor('retiring-rejection', 'remove', 25)
    equal(removed, false, 'explicit Runtime rejection aborts Controller retirement')
    equal(error_code, 'runtime-invalidation-rejected', 'Runtime rejection is forwarded')
    equal(controller.registrations['retiring-rejection'], registration,
        'rejected retirement keeps the same registration current')
    equal(registration.retiring, false,
        'rejected Runtime invalidation rolls back retiring on the same registration')
    equal(registration.sealed, false, 'rejected Runtime invalidation does not seal the lifecycle')
    equal(hook.removed, false, 'rejected Runtime invalidation leaves the hook installed')
    equal(timer.removed, false, 'rejected Runtime invalidation leaves the timer installed')

    hook.callback()
    timer.callback()
    equal(hook_calls, 1, 'rolled-back lifecycle hook becomes active again')
    equal(timer_calls, 1, 'rolled-back lifecycle timer becomes active again')
end

do
    local adapter = new_adapter()
    adapter.install_timer = nil
    adapter.remove_owner_timers = nil
    local runtime = new_runtime()
    local timer_handle
    local timer_calls = 0
    local controller = Controller.new({
        adapter = adapter,
        runtime = runtime,
        register_timer = function(timer_key, callback)
            timer_handle = { key = timer_key, callback = callback, removed = false }
            function timer_handle:remove() self.removed = true end
            return timer_handle
        end,
    })
    controller:register_actor('timer-owner', { id = 'timer-unit' }, 'team')
    truthy(controller:install_actor_timer('timer-owner', 'fallback-timer', function()
        timer_calls = timer_calls + 1
    end), 'Controller can own an injected timer without Adapter timer methods')
    timer_handle.callback()
    equal(timer_calls, 1, 'injected current timer executes')
    adapter.on_emit = function()
        truthy(timer_handle.removed, 'injected timer is cancelled before emitter')
        timer_handle.callback()
        equal(timer_calls, 1, 'cancelled injected timer is lifecycle-inert during emitter')
    end
    truthy(controller:remove_actor('timer-owner', 'remove', 30), 'remove supports injected timer cleanup')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })
    local registration = controller:register_actor('sealed-owner', { id = 'sealed-unit' }, 'team')
    local hook_calls = 0
    local _, hook = controller:install_actor_hook('sealed-owner', 'sealed-hook', function()
        hook_calls = hook_calls + 1
    end)
    local remove_owner_hooks = adapter.remove_owner_hooks
    adapter.remove_owner_hooks = function()
        return false, 'hook-removal-failed'
    end
    local removed, error_code = controller:remove_actor('sealed-owner', 'remove', 40)
    equal(removed, false, 'hook removal failure stops actor removal')
    equal(error_code, 'hook-removal-failed', 'hook removal failure is forwarded')
    truthy(registration.sealed, 'failed removal keeps the lifecycle sealed')
    equal(#runtime.calls.invalidations, 1,
        'instance invalidation completes before a later hook-removal failure')
    equal(#adapter.emitted, 0, 'failed hook removal defers the committed cleanup dispatch')
    equal(#controller.pending_deliveries, 1,
        'committed cleanup is pending before a hook-removal failure is reported')
    equal(controller.pending_deliveries[1].payload.commands[1].lifecycle_id, registration.lifecycle_id,
        'pending cleanup retains the sealed lifecycle identity')
    hook.callback()
    equal(hook_calls, 0, 'sealed hook remains lifecycle-inert after physical removal fails')

    truthy(controller:retry_pending_deliveries(),
        'sealed lifecycle cleanup remains independently retryable after hook-removal failure')
    equal(#controller.pending_deliveries, 0, 'successful cleanup retry clears the pending delivery')
    equal(#adapter.emitted, 1, 'successful cleanup retry emits the committed invalidation exactly once')

    adapter.remove_owner_hooks = remove_owner_hooks
    local recovered, recovery = controller:remove_actor('sealed-owner', 'remove', 41)
    truthy(recovered, 'sealed actor retirement can resume after hook teardown recovers')
    equal(controller.registrations['sealed-owner'], nil, 'recovered retirement removes the sealed registration')
    equal(#runtime.calls.invalidations, 1, 'retirement recovery does not invalidate runtime twice')
    equal(recovery.delivery_pending, false, 'recovered retirement reuses the delivered cleanup result')
    truthy(hook.removed, 'retirement recovery completes physical hook removal')

    local replacement = controller:register_actor('sealed-owner', { id = 'replacement-unit' }, 'team')
    hook.callback()
    equal(hook_calls, 0, 'old sealed hook cannot affect a later same-ID registration')
    truthy(replacement.lifecycle_id > registration.lifecycle_id,
        'same-ID registration after recovery receives a fresh lifecycle')
end

do
    local adapter = new_adapter()
    adapter.install_timer = nil
    adapter.remove_owner_timers = nil
    local runtime = new_runtime()
    local timer_remove_fails = true
    local timer_handle
    local timer_calls = 0
    local controller = Controller.new({
        adapter = adapter,
        runtime = runtime,
        register_timer = function(timer_key, callback)
            timer_handle = { key = timer_key, callback = callback, removed = false }
            function timer_handle:remove()
                if timer_remove_fails then return false, 'timer-removal-failed' end
                self.removed = true
                return true
            end
            return timer_handle
        end,
    })
    local registration = controller:register_actor('timer-failure', { id = 'timer-unit' }, 'team')
    truthy(controller:install_actor_timer('timer-failure', 'failing-timer', function()
        timer_calls = timer_calls + 1
    end), 'failing injected timer installs before retirement')
    timer_handle.callback()
    equal(timer_calls, 1, 'current injected timer executes before retirement')

    local removed, error_code = controller:remove_actor('timer-failure', 'remove', 50)
    equal(removed, false, 'timer cancellation failure stops local actor teardown')
    equal(error_code, 'timer-removal-failed', 'timer cancellation failure is reported')
    truthy(registration.sealed, 'timer cancellation failure leaves the committed lifecycle sealed')
    equal(#controller.pending_deliveries, 1,
        'runtime cleanup is pending before timer cancellation failure is reported')
    equal(#adapter.emitted, 0, 'timer cancellation failure does not discard or prematurely dispatch cleanup')
    timer_handle.callback()
    equal(timer_calls, 1, 'sealed timer callback is inert while physical cancellation is unresolved')

    truthy(controller:retry_pending_deliveries(),
        'cleanup remains retryable after injected timer cancellation failure')
    equal(#adapter.emitted, 1, 'cleanup retry emits the timer owner invalidation')
    timer_remove_fails = false
    local recovered, recovery = controller:remove_actor('timer-failure', 'remove', 51)
    truthy(recovered, 'sealed actor retirement resumes after timer cancellation recovers')
    truthy(timer_handle.removed, 'retirement recovery cancels the injected timer')
    equal(controller.registrations['timer-failure'], nil, 'timer recovery removes the sealed registration')
    equal(#runtime.calls.invalidations, 1, 'timer recovery does not repeat committed runtime invalidation')
    equal(recovery.delivery_pending, false, 'timer recovery reuses the delivered cleanup status')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller
    local actor_id = 'timer-teardown-reentry'
    local reentered = false
    local nested_registration, nested_retirement
    local nested_timer_ok, nested_timer
    local nested_event_ok, nested_event
    local nested_event_pending_during_teardown
    local emitted_during_teardown
    local remove_owner_timers = adapter.remove_owner_timers
    adapter.remove_owner_timers = function(self, owner_key)
        if not reentered then
            reentered = true
            nested_registration, nested_retirement = controller:register_actor(
                actor_id, { id = 'timer-reentry-unit-inner' }, 'team'
            )
            nested_timer_ok, nested_timer = controller:install_actor_timer(
                actor_id, 'timer-reentry-inner', function() end
            )
            nested_event_ok, nested_event = controller:report_public_damage({
                actor_id = actor_id,
                lifecycle_id = nested_registration.lifecycle_id,
                event_id = 'timer-reentry-inner-event',
            })
            nested_event_pending_during_teardown = nested_event.delivery_pending
            emitted_during_teardown = #self.emitted
        end
        return remove_owner_timers(self, owner_key)
    end
    controller = Controller.new({ adapter = adapter, runtime = runtime })

    local original = controller:register_actor(
        actor_id, { id = 'timer-reentry-unit-original' }, 'team'
    )
    local old_timer_ok, old_timer = controller:install_actor_timer(
        actor_id, 'timer-reentry-old', function() end
    )
    truthy(old_timer_ok, 'timer teardown reentry fixture installs the old lifecycle timer')

    local outer_registration, outer_error = controller:register_actor(
        actor_id, { id = 'timer-reentry-unit-outer' }, 'team'
    )
    equal(reentered, true, 'remove_owner_timers synchronously re-enters register_actor')
    truthy(nested_registration, 'timer teardown callback successfully registers the inner lifecycle')
    truthy(type(nested_retirement) == 'table',
        'inner timer teardown registration returns the committed retirement payload')
    truthy(nested_timer_ok, 'inner lifecycle installs its timer during outer teardown')
    truthy(nested_event_ok, 'inner lifecycle can commit a runtime command during outer teardown')
    equal(nested_event_pending_during_teardown, true,
        'inner runtime command remains pending inside timer teardown')
    equal(nested_event.delivery_pending, false,
        'outer teardown completion updates the retained inner delivery status')
    equal(emitted_during_teardown, 0,
        'timer teardown callback cannot drain the old invalidation delivery')
    equal(outer_registration, nil,
        'outer timer teardown registration does not overwrite the inner lifecycle')
    equal(outer_error, 'actor-registration-superseded',
        'outer timer teardown registration reports the retirement CAS loss')
    equal(controller.registrations[actor_id], nested_registration,
        'inner timer teardown registration remains current')
    equal(old_timer.removed, true, 'old lifecycle timer is physically removed')
    equal(nested_timer.removed, false, 'old lifecycle teardown preserves the inner timer owner')
    equal(#adapter.emitted, 2,
        'old invalidation and inner command each emit once after timer teardown returns')
    equal(adapter.emitted[1].type, 'runtime_actor_invalidated',
        'old lifecycle invalidation remains first in the delivery queue')
    equal(adapter.emitted[2].type, 'public_damage_recorded',
        'inner lifecycle command follows the completed physical teardown')

    truthy(controller:remove_actor(actor_id, 'remove', 60),
        'inner timer teardown registration can retire normally')
    equal(nested_timer.removed, true,
        'inner lifecycle retirement removes its own timer')
    equal(#runtime.calls.invalidations, 2,
        'timer teardown reentry invalidates each committed lifecycle exactly once')
    equal(#adapter.emitted, 3,
        'timer teardown reentry delivers each lifecycle invalidation exactly once')
    truthy(original.sealed, 'original timer teardown lifecycle remains sealed')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller
    local actor_id = 'retirement-registry-reentry'
    local original_owner_key
    local reentered = false
    local timer_remove_fails = true
    local nested_registration, nested_retirement
    local nested_hook_ok, nested_hook
    local nested_timer_ok, nested_timer
    local old_hook_calls, old_timer_calls = 0, 0
    local nested_hook_calls, nested_timer_calls = 0, 0
    local remove_owner_hooks = adapter.remove_owner_hooks
    local remove_owner_timers = adapter.remove_owner_timers

    adapter.remove_owner_hooks = function(self, owner_key)
        local removed, error_code = remove_owner_hooks(self, owner_key)
        if owner_key == original_owner_key and not reentered then
            reentered = true
            nested_registration, nested_retirement = controller:register_actor(
                actor_id, { id = 'retirement-registry-inner-unit' }, 'team'
            )
            nested_hook_ok, nested_hook = controller:install_actor_hook(
                actor_id, 'retirement-registry-inner-hook', function()
                    nested_hook_calls = nested_hook_calls + 1
                end
            )
            nested_timer_ok, nested_timer = controller:install_actor_timer(
                actor_id, 'retirement-registry-inner-timer', function()
                    nested_timer_calls = nested_timer_calls + 1
                end
            )
            nested_hook.callback()
            nested_timer.callback()
        end
        return removed, error_code
    end
    adapter.remove_owner_timers = function(self, owner_key)
        if owner_key == original_owner_key and timer_remove_fails then
            return false, 'timer-removal-after-reentry-failed'
        end
        return remove_owner_timers(self, owner_key)
    end
    controller = Controller.new({ adapter = adapter, runtime = runtime })

    local original = controller:register_actor(
        actor_id, { id = 'retirement-registry-original-unit' }, 'team'
    )
    original_owner_key = original.owner_key
    local old_hook_ok, old_hook = controller:install_actor_hook(
        actor_id, 'retirement-registry-old-hook', function()
            old_hook_calls = old_hook_calls + 1
        end
    )
    local old_timer_ok, old_timer = controller:install_actor_timer(
        actor_id, 'retirement-registry-old-timer', function()
            old_timer_calls = old_timer_calls + 1
        end
    )
    function old_timer:remove()
        if timer_remove_fails then return false, 'timer-removal-after-reentry-failed' end
        self.removed = true
        return true
    end
    truthy(old_hook_ok and old_timer_ok,
        'retirement registry fixture installs old hook and timer resources')
    old_hook.callback()
    old_timer.callback()
    equal(old_hook_calls, 1, 'old hook executes before retirement registry teardown')
    equal(old_timer_calls, 1, 'old timer executes before retirement registry teardown')

    local outer_registration, outer_error = controller:register_actor(
        actor_id, { id = 'retirement-registry-outer-unit' }, 'team'
    )
    equal(reentered, true, 'old hook teardown synchronously re-enters actor registration')
    equal(outer_registration, nil,
        'outer registration reports the later old-resource teardown failure')
    equal(outer_error, 'timer-removal-after-reentry-failed',
        'outer registration preserves the post-reentry timer removal error')
    truthy(nested_registration, 'hook teardown reentry commits a fresh lifecycle')
    truthy(type(nested_retirement) == 'table',
        'hook teardown reentry retains the old committed retirement payload')
    truthy(nested_hook_ok and nested_timer_ok,
        'fresh lifecycle installs hook and timer resources during old teardown')
    equal(nested_hook_calls, 1, 'fresh hook is active during old teardown')
    equal(nested_timer_calls, 1, 'fresh timer is active during old teardown')
    equal(controller.registrations[actor_id], nested_registration,
        'post-reentry teardown failure preserves the fresh current lifecycle')
    equal(controller.pending_retirements[original.retirement_token], original.retirement,
        'failed old retirement remains registered by retirement identity')
    equal(#controller.pending_retirement_order, 1,
        'failed old retirement has one deterministic retry entry')
    equal(#controller.pending_deliveries, 1,
        'failed old retirement keeps its committed cleanup pending')
    equal(#adapter.emitted, 0,
        'post-reentry resource failure does not prematurely deliver old cleanup')
    equal(#runtime.calls.invalidations, 1,
        'post-reentry resource failure commits old Runtime invalidation once')
    truthy(old_hook.removed, 'old hook is removed before the later timer failure')
    equal(old_timer.removed, false, 'failed old timer remains available to the retirement retry')
    old_hook.callback()
    old_timer.callback()
    equal(old_hook_calls, 1, 'sealed old hook stays inert after reentry failure')
    equal(old_timer_calls, 1, 'sealed old timer stays inert after reentry failure')

    local failed_tick, failed_tick_error = controller:tick(70)
    equal(failed_tick, false, 'tick reports a still-failing detached retirement retry')
    equal(failed_tick_error, 'timer-removal-after-reentry-failed',
        'tick preserves the detached retirement teardown error')
    equal(runtime.calls.last_tick, nil,
        'runtime tick waits until detached physical teardown converges')
    equal(#controller.pending_retirement_order, 1,
        'failed tick keeps the detached retirement retry registered')
    equal(#adapter.emitted, 0, 'failed detached retirement retry still emits no cleanup')

    timer_remove_fails = false
    local converged, tick_result = controller:tick(71)
    truthy(converged, 'tick converges a detached retirement after resource removal recovers')
    equal(runtime.calls.last_tick, 71, 'runtime tick resumes after detached retirement convergence')
    equal(controller.pending_retirements[original.retirement_token], nil,
        'converged retirement leaves the identity registry')
    equal(#controller.pending_retirement_order, 0,
        'converged retirement clears its deterministic retry entry')
    equal(controller.owner_timers[original_owner_key], nil,
        'converged retirement releases the old timer owner registry')
    truthy(old_timer.removed, 'converged retirement physically removes the old timer')
    equal(controller.registrations[actor_id], nested_registration,
        'detached retirement convergence does not replace the fresh lifecycle')
    equal(nested_hook.removed, false,
        'detached old retirement does not remove the fresh hook owner')
    equal(nested_timer.removed, false,
        'detached old retirement does not remove the fresh timer owner')
    equal(nested_retirement.delivery_pending, false,
        'detached retirement retry drains its retained cleanup delivery')
    equal(#controller.pending_deliveries, 0,
        'detached retirement convergence leaves no pending cleanup')
    equal(#runtime.calls.invalidations, 1,
        'detached retirement retry does not repeat Runtime invalidation')
    local old_cleanup_deliveries = 0
    for _, command in ipairs(adapter.emitted) do
        if command.type == 'runtime_actor_invalidated'
            and command.lifecycle_id == original.lifecycle_id then
            old_cleanup_deliveries = old_cleanup_deliveries + 1
        end
    end
    equal(old_cleanup_deliveries, 1,
        'detached retirement cleanup is delivered exactly once after convergence')
    truthy(type(tick_result) == 'table' and tick_result.delivery_pending == false,
        'converged tick delivery completes normally')

    local emitted_after_convergence = #adapter.emitted
    truthy(controller:retry_pending_retirements(),
        'empty retirement retry remains idempotently successful')
    equal(#adapter.emitted, emitted_after_convergence,
        'idempotent retirement retry does not duplicate old cleanup delivery')
    nested_hook.callback()
    nested_timer.callback()
    equal(nested_hook_calls, 2, 'fresh hook remains active after old retirement convergence')
    equal(nested_timer_calls, 2, 'fresh timer remains active after old retirement convergence')

    truthy(controller:remove_actor(actor_id, 'remove', 72),
        'fresh lifecycle can retire after detached old retirement convergence')
    truthy(nested_hook.removed, 'fresh retirement removes its own hook')
    truthy(nested_timer.removed, 'fresh retirement removes its own timer')
    equal(#runtime.calls.invalidations, 2,
        'each lifecycle commits exactly one Runtime invalidation')
    equal(#controller.pending_retirement_order, 0,
        'fresh retirement also leaves no pending retirement identity')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })
    local hero = controller:register_actor('hero', { id = 'hero' }, 'team')

    local dragon_finish = {
        actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
        session_instance_id = 'dragon:1:7', session_epoch = 7,
    }
    truthy(controller:finish_dragon(dragon_finish), 'Controller forwards full Dragon finish identity')
    truthy(runtime.calls.last_dragon_finish == dragon_finish, 'Dragon finish event reaches runtime unchanged')
    local dragon_ack = {
        actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
        session_instance_id = 'dragon:1:7', session_epoch = 7,
    }
    truthy(controller:acknowledge_dragon_cleanup(dragon_ack), 'Controller forwards Dragon cleanup acknowledgement')
    truthy(runtime.calls.last_dragon_ack == dragon_ack, 'Dragon cleanup ack reaches runtime unchanged')

    local ox_identity = {
        raid_instance_id = 'ox-raid:9', session_epoch = 9,
        boss_instance_id = 'ox-boss:9', phase_id = 'human',
    }
    truthy(controller:swap_ox_phase(ox_identity), 'Controller forwards identity-bound Ox phase callback')
    truthy(runtime.calls.last_ox_swap == ox_identity, 'Ox phase identity reaches runtime unchanged')
    local ox_failure = {
        raid_instance_id = 'ox-raid:9', session_epoch = 9,
        boss_instance_id = 'ox-boss:9', phase_id = 'white_ox',
    }
    truthy(controller:fail_ox(ox_failure), 'Controller forwards identity-bound Ox failure')
    truthy(runtime.calls.last_ox_fail == ox_failure, 'Ox failure reaches runtime unchanged')
    truthy(controller:succeed_ox(ox_failure), 'Controller forwards identity-bound Ox success')
    truthy(runtime.calls.last_ox_success == ox_failure, 'Ox success reaches runtime unchanged')
    local ox_acknowledgement = {
        raid_instance_id = 'ox-raid:9', session_epoch = 9,
        boss_instance_id = 'ox-boss:9', phase_id = 'white_ox',
    }
    truthy(controller:acknowledge_ox_cleanup(ox_acknowledgement), 'Controller forwards Ox cleanup acknowledgement')
    truthy(runtime.calls.last_ox_ack == ox_acknowledgement, 'Ox cleanup ack reaches runtime unchanged')

    truthy(controller:tick(200), 'Controller emits runtime tick commands')
    equal(runtime.calls.last_tick, 200, 'Controller forwards tick time')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    function runtime:start_dragon(request)
        self.calls.starts.dragon = self.calls.starts.dragon + 1
        if self.active_dragon then return false, 'actor-already-in-dragon-session' end
        local session = {
            actor_id = request.actor_id,
            lifecycle_id = request.lifecycle_id,
            session_instance_id = 'dragon:delivery-test',
            session_epoch = 41,
        }
        self.active_dragon = session
        return true, {
            session = session,
            commands = { {
                type = 'dragon_started',
                actor_id = session.actor_id,
                lifecycle_id = session.lifecycle_id,
                session_instance_id = session.session_instance_id,
                session_epoch = session.session_epoch,
            } },
        }
    end
    function runtime:acknowledge_dragon_cleanup(acknowledgement)
        if self.cleanup_acknowledged then return false, 'dragon-session-not-found' end
        self.cleanup_acknowledged = true
        self.calls.last_dragon_ack = acknowledgement
        return true, { commands = { {
            type = 'dragon_lock_released',
            actor_id = acknowledgement.actor_id,
            lifecycle_id = acknowledgement.lifecycle_id,
            session_instance_id = acknowledgement.session_instance_id,
            session_epoch = acknowledgement.session_epoch,
        } } }
    end
    local controller = Controller.new({
        adapter = adapter,
        runtime = runtime,
        delivery_namespace = 'controller-boot-41',
        require_delivery_namespace = true,
    })
    local hero = controller:register_actor('hero', { id = 'hero' }, 'team')
    adapter.fail_next_emit = 'command-execution-failed'
    local started, start_result = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
    })
    equal(started, true, 'Controller accepts a runtime-committed start when command delivery fails')
    equal(start_result.accepted, true, 'accepted start payload records runtime commitment')
    equal(start_result.delivery_pending, true, 'accepted start reports pending delivery')
    equal(start_result.delivery_error, 'command-execution-failed', 'accepted start reports the adapter failure')
    equal(start_result.delivery_namespace, 'controller-boot-41', 'accepted start exposes its delivery namespace')
    truthy(start_result.operation_id ~= nil, 'accepted start exposes a stable operation ID')
    truthy(start_result.delivery_id ~= nil, 'accepted start exposes a stable batch delivery ID')
    truthy(start_result.session ~= runtime.active_dragon,
        'accepted start returns a detached committed-session projection')
    equal(start_result.session.session_instance_id, runtime.active_dragon.session_instance_id,
        'accepted start projection preserves the committed session identity')
    equal(#controller.pending_deliveries, 1, 'failed delivery remains queued for retry')
    truthy(controller.pending_deliveries[1].payload ~= start_result,
        'queued delivery owns a detached accepted result payload')
    local command_delivery_id = controller.pending_deliveries[1].payload.commands[1].delivery_id
    truthy(command_delivery_id ~= nil, 'queued commands carry a stable delivery ID')
    start_result.commands[1].actor_id = 'forged-actor'
    equal(controller.pending_deliveries[1].payload.commands[1].actor_id, 'hero',
        'mutating a returned pending command cannot alter the queued delivery')

    local duplicate_started, duplicate_error = controller:start_dragon({
        encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
    })
    equal(duplicate_started, false, 'retrying the same start cannot reopen a committed session')
    equal(duplicate_error, 'actor-already-in-dragon-session', 'duplicate start reports the committed-state conflict')
    equal(runtime.active_dragon.session_instance_id, start_result.session.session_instance_id,
        'duplicate start cannot replace the committed session')
    equal(#controller.pending_deliveries, 1, 'duplicate start does not enqueue a second delivery')

    adapter.fail_next_emit = 'retry-command-execution-failed'
    local retried, retry_error = controller:retry_pending_deliveries()
    equal(retried, false, 'public delivery retry retains an explicit failure result')
    equal(retry_error, 'retry-command-execution-failed', 'public delivery retry reports the adapter error')
    equal(start_result.delivery_error, retry_error, 'pending payload tracks the latest retry error')
    equal(#controller.pending_deliveries, 1, 'failed retry retains the pending delivery')

    local start_operation_id, start_delivery_id = start_result.operation_id, start_result.delivery_id
    truthy(controller:retry_pending_deliveries(), 'Controller can later deliver the retained start')
    equal(#controller.pending_deliveries, 0, 'successful retry clears the pending delivery')
    equal(start_result.delivery_pending, false, 'successful retry clears pending status on the returned payload')
    equal(start_result.delivery_error, nil, 'successful retry clears the returned delivery error')
    equal(start_result.operation_id, start_operation_id, 'start operation ID remains stable across retries')
    equal(start_result.delivery_id, start_delivery_id, 'start delivery ID remains stable across retries')
    equal(adapter.emitted[1].delivery_id, command_delivery_id, 'command delivery ID remains stable across retries')
    equal(#adapter.emitted, 1, 'retry delivers the retained command exactly once after a pre-dispatch failure')

    local acknowledgement = {
        actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
        session_instance_id = start_result.session.session_instance_id,
        session_epoch = start_result.session.session_epoch,
    }
    adapter.fail_next_emit = 'ack-command-execution-failed'
    local acknowledged, ack_result = controller:acknowledge_dragon_cleanup(acknowledgement)
    equal(acknowledged, true, 'Controller accepts a runtime-committed cleanup acknowledgement on delivery failure')
    equal(ack_result.accepted, true, 'accepted acknowledgement records runtime commitment')
    equal(ack_result.delivery_pending, true, 'accepted acknowledgement reports pending delivery')
    equal(ack_result.delivery_error, 'ack-command-execution-failed',
        'accepted acknowledgement reports its adapter failure')
    truthy(ack_result.operation_id ~= start_operation_id,
        'cleanup acknowledgement has a distinct stable operation identity')
    truthy(ack_result.delivery_id ~= start_delivery_id,
        'cleanup acknowledgement has a distinct stable delivery identity')
    equal(#controller.pending_deliveries, 1, 'failed acknowledgement delivery remains queued')

    local duplicate_acknowledged, duplicate_ack_error = controller:acknowledge_dragon_cleanup(acknowledgement)
    equal(duplicate_acknowledged, false, 'retrying a committed acknowledgement cannot commit it again')
    equal(duplicate_ack_error, 'dragon-session-not-found',
        'duplicate acknowledgement reports the already-committed state')
    truthy(controller:retry_pending_deliveries(), 'Controller can later deliver the retained acknowledgement')
    equal(ack_result.delivery_pending, false, 'acknowledgement payload observes successful later delivery')
    equal(#controller.pending_deliveries, 0, 'successful acknowledgement retry clears the queue')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })
    local hero = controller:register_actor('reentrant-delivery', { id = 'reentrant-unit' }, 'team')
    local base_emit = adapter.emit
    local fail_inner = true
    function adapter:emit(payload)
        local command = payload and payload.commands and payload.commands[1]
        if fail_inner and command and command.event_id == 'inner-delivery' then
            fail_inner = false
            return false, 'inner-delivery-failed'
        end
        return base_emit(self, payload)
    end

    local nested_ok, nested_result
    adapter.on_emit = function(command)
        equal(command.event_id, 'outer-delivery', 'outer delivery enters the adapter first')
        nested_ok, nested_result = controller:report_public_damage({
            actor_id = 'reentrant-delivery', lifecycle_id = hero.lifecycle_id,
            event_id = 'inner-delivery',
        })
        equal(nested_ok, true, 'runtime-committed reentrant delivery remains accepted')
        equal(nested_result.delivery_pending, true, 'reentrant delivery only queues while the outer drain is active')
    end

    local outer_ok, outer_result = controller:report_public_damage({
        actor_id = 'reentrant-delivery', lifecycle_id = hero.lifecycle_id,
        event_id = 'outer-delivery',
    })
    equal(outer_ok, true, 'outer delivery succeeds even when the reentrant delivery later fails')
    equal(outer_result.delivery_pending, false, 'outer delivery status remains bound to the delivered outer identity')
    equal(nested_ok, true, 'reentrant operation returns its accepted result')
    equal(nested_result.delivery_pending, true, 'failed reentrant delivery remains pending after the outer drain')
    equal(nested_result.delivery_error, 'inner-delivery-failed',
        'failed reentrant delivery receives its own adapter error')
    equal(#controller.pending_deliveries, 1, 'outer completion cannot remove the reentrant delivery')
    equal(controller.pending_deliveries[1].payload.commands[1].event_id, 'inner-delivery',
        'the retained queue entry is the reentrant delivery identity')
    equal(#adapter.emitted, 1, 'non-reentrant drain emits the outer command only once')

    local inner_delivery_id = controller.pending_deliveries[1].payload.commands[1].delivery_id
    truthy(controller:retry_pending_deliveries(), 'retained reentrant delivery can be retried later')
    equal(#controller.pending_deliveries, 0, 'successful reentrant retry clears the queue')
    equal(nested_result.delivery_pending, false, 'successful retry updates the reentrant accepted result')
    equal(adapter.emitted[2].event_id, 'inner-delivery', 'retry emits the retained inner command')
    equal(adapter.emitted[2].delivery_id, inner_delivery_id,
        'reentrant retry preserves the original command delivery identity')
end

do
    local adapter = new_adapter()
    local runtime = new_runtime()
    local controller = Controller.new({ adapter = adapter, runtime = runtime })
    local hero = controller:register_actor('delivery-invalidated', { id = 'delivery-unit' }, 'team')
    adapter.fail_next_emit = 'invalidation-dispatch-failed'
    local accepted, replacement_lifecycle, delivery = controller:invalidate_actor(
        'delivery-invalidated', 'death', 1
    )
    equal(accepted, true, 'committed lifecycle invalidation remains accepted when delivery is pending')
    truthy(replacement_lifecycle > hero.lifecycle_id,
        'accepted pending invalidation still advances the lifecycle')
    equal(delivery.delivery_pending, true, 'pending invalidation returns delivery status instead of a false rejection')
    equal(controller.registrations['delivery-invalidated'].lifecycle_id, replacement_lifecycle,
        'pending invalidation keeps its committed replacement registration')
    truthy(controller:retry_pending_deliveries(), 'pending lifecycle invalidation can be delivered later')
    equal(delivery.delivery_pending, false, 'later delivery resolves the invalidation status projection')
end

do
    local function first_delivery(namespace_option, namespace)
        local adapter = new_adapter()
        local runtime = new_runtime()
        local options = {
            adapter = adapter,
            runtime = runtime,
            require_delivery_namespace = true,
        }
        options[namespace_option] = namespace
        local controller = Controller.new(options)
        local hero = controller:register_actor('hero', { id = 'hero' }, 'team')
        local accepted, result = controller:start_dragon({
            encounter_key = 'HG_E_DRAGON_OLD_TIDE', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
        })
        truthy(accepted, 'namespaced Controller accepts the test operation')
        return result, adapter.emitted[1]
    end

    local first, first_command = first_delivery('delivery_namespace', 'controller-boot-a')
    local second, second_command = first_delivery('delivery_boot_epoch', 'controller-boot-b')
    truthy(first.operation_id ~= second.operation_id,
        'different Controller boot namespaces produce distinct operation IDs')
    truthy(first.delivery_id ~= second.delivery_id,
        'different Controller boot namespaces produce distinct batch delivery IDs')
    truthy(first_command.delivery_id ~= second_command.delivery_id,
        'different Controller boot namespaces produce distinct command delivery IDs')

    local default_one = Controller.new({ adapter = new_adapter(), runtime = new_runtime() })
    local default_two = Controller.new({ adapter = new_adapter(), runtime = new_runtime() })
    truthy(default_one.delivery_namespace ~= default_two.delivery_namespace,
        'offline Controller reconstruction allocates distinct delivery namespaces')

    local constructed, construction_error = pcall(function()
        Controller.new({ adapter = new_adapter(), runtime = new_runtime(), require_delivery_namespace = true })
    end)
    equal(constructed, false, 'live-style Controller construction can require an explicit delivery namespace')
    truthy(tostring(construction_error):find('delivery_namespace is required', 1, true) ~= nil,
        'missing required delivery namespace has an explicit construction error')
    local live_constructed, live_error = pcall(function()
        Controller.new({ mode = 'live', adapter = new_adapter(), runtime = new_runtime() })
    end)
    equal(live_constructed, false, 'live Controller construction requires a durable delivery namespace')
    truthy(tostring(live_error):find('delivery_namespace is required', 1, true) ~= nil,
        'live construction rejects an implicit offline delivery namespace')
end

do
    local function copy_table(source)
        local copy = {}
        for key, value in pairs(source or {}) do copy[key] = value end
        return copy
    end

    local function new_instance_authority(statuses)
        local authority = { members = {}, statuses = statuses or {}, rejected = {}, tick = 0 }

        function authority:reject(operation, rejected)
            self.rejected[operation] = rejected ~= false
        end

        function authority:verify(operation, context)
            if self.rejected[operation] then return false end
            self.tick = self.tick + 1
            local proof = copy_table(context)
            proof.operation = operation
            proof.operation_token = operation .. ':' .. tostring(self.tick)
            proof.now = self.tick
            if operation == 'ox_entry' then
                proof.member_snapshot = self.members
            elseif operation == 'ox_actor_invalidate' then
                proof.member_status = self.statuses[context.actor_id] or 'left'
            elseif operation == 'ox_failure' then
                proof.reason = 'all_members_dead'
                proof.all_members_dead = true
            else
                return false
            end
            return true, proof
        end

        return authority
    end

    local function new_instance_controller(statuses)
        local adapter = new_adapter()
        local authority = new_instance_authority(statuses)
        local controller = Controller.new({ adapter = adapter, authority_provider = authority })
        return controller, adapter, authority
    end

    local function start_ox_raid(controller, authority)
        local hero = controller:register_actor('hero', { id = 'hero-unit' }, 'team-red')
        local ally = controller:register_actor('ally', { id = 'ally-unit' }, 'team-red')
        authority.members = {
            { actor_id = 'hero', lifecycle_id = hero.lifecycle_id, team_id = 'team-red' },
            { actor_id = 'ally', lifecycle_id = ally.lifecycle_id, team_id = 'team-red' },
        }
        local started, raid = controller.runtime.ox_battlefield:open({
            entry_request_id = 'controller-entry', actor_id = 'hero', lifecycle_id = hero.lifecycle_id,
        })
        truthy(started, 'authority opens an Ox raid for Controller invalidation coverage: ' .. tostring(raid))
        return hero, ally, raid
    end

    local function emitted_member_status(adapter, actor_id)
        for _, command in ipairs(adapter.emitted) do
            if command.type == 'mark_raid_member_unavailable' and command.actor_id == actor_id then
                return command.member_status
            end
        end
        return nil
    end

    do
        local controller, adapter, authority = new_instance_controller({ hero = 'left' })
        local hero = start_ox_raid(controller, authority)
        local hook_calls = 0
        local _, old_hook = controller:install_actor_hook('hero', 'leave-hook', function()
            hook_calls = hook_calls + 1
        end)

        authority:reject('ox_actor_invalidate')
        local removed, removal_error = controller:remove_actor('hero', 'leave', 5)
        equal(removed, false, 'Controller fails closed when a team-member leave lacks authority proof')
        equal(removal_error, 'authority-proof-rejected:ox_actor_invalidate',
            'Controller forwards the Ox leave proof failure')
        equal(controller.registrations.hero, hero, 'failed leave keeps the old registration current')
        equal(hero.sealed, false, 'failed leave does not seal the old lifecycle')
        equal(old_hook.removed, false, 'failed leave does not unregister old lifecycle hooks')
        equal(controller.runtime.ox_battlefield.active.member_by_actor.hero.status, 'active',
            'failed leave does not mutate the raid snapshot')

        authority:reject('ox_actor_invalidate', false)
        truthy(controller:remove_actor('hero', 'leave', 6),
            'Controller accepts a team-member leave with authority proof')
        equal(emitted_member_status(adapter, 'hero'), 'left',
            'Controller dispatches the required team-member leave cleanup')
        old_hook.callback()
        equal(hook_calls, 0, 'old leave lifecycle callbacks remain silent after retirement')
    end

    do
        local controller, adapter, authority = new_instance_controller({ hero = 'dead', ally = 'dead' })
        local hero, ally = start_ox_raid(controller, authority)

        authority:reject('ox_actor_invalidate')
        local invalidated, invalidation_error = controller:invalidate_actor('hero', 'death', 6)
        equal(invalidated, false, 'Controller fails closed when a team-member death lacks authority proof')
        equal(invalidation_error, 'authority-proof-rejected:ox_actor_invalidate',
            'Controller forwards the Ox death proof failure')
        equal(controller.registrations.hero, hero, 'failed death keeps the old registration current')
        equal(hero.sealed, false, 'failed death does not seal the old lifecycle')

        authority:reject('ox_actor_invalidate', false)
        local death_ok, replacement_lifecycle = controller:invalidate_actor('hero', 'death', 7)
        truthy(death_ok, 'Controller accepts a team-member death with authority proof')
        truthy(replacement_lifecycle > hero.lifecycle_id,
            'successful death creates a replacement lifecycle only after instance invalidation')
        equal(emitted_member_status(adapter, 'hero'), 'dead',
            'Controller dispatches the required team-member death cleanup')
        truthy(controller:invalidate_actor('ally', 'death', 8),
            'Controller accepts the final authority-certified team-member death')
        local cleanup_requested = false
        for _, command in ipairs(adapter.emitted) do
            if command.type == 'cleanup_ox_raid' and command.reason == 'all_members_dead' then
                cleanup_requested = true
            end
        end
        truthy(cleanup_requested, 'Controller dispatches raid cleanup when authority-certified deaths complete a wipe')
    end

    do
        local controller, adapter, authority = new_instance_controller({ hero = 'left' })
        local hero = start_ox_raid(controller, authority)
        local hook_calls = 0
        local _, old_hook = controller:install_actor_hook('hero', 're-register-hook', function()
            hook_calls = hook_calls + 1
        end)

        authority:reject('ox_actor_invalidate')
        local replacement, replacement_error = controller:register_actor(
            'hero', { id = 'replacement-unit' }, 'team-red', 8
        )
        equal(replacement, nil, 'Controller rejects re-registration without authority proof')
        equal(replacement_error, 'authority-proof-rejected:ox_actor_invalidate',
            'Controller forwards the re-registration proof failure')
        equal(controller.registrations.hero, hero, 'failed re-registration keeps the old registration current')
        equal(hero.sealed, false, 'failed re-registration does not seal the old lifecycle')
        equal(old_hook.removed, false, 'failed re-registration does not unregister old lifecycle hooks')

        authority:reject('ox_actor_invalidate', false)
        replacement = controller:register_actor('hero', { id = 'replacement-unit' }, 'team-red', 9)
        truthy(replacement, 'Controller accepts re-registration with authority proof')
        truthy(replacement.lifecycle_id > hero.lifecycle_id,
            'successful re-registration advances the actor lifecycle')
        equal(emitted_member_status(adapter, 'hero'), 'left',
            'successful re-registration invalidates the old team member before replacement')
        old_hook.callback()
        equal(hook_calls, 0, 'old re-registered lifecycle callbacks remain silent')
        local stale, stale_error = controller:report_public_damage({
            actor_id = 'hero', lifecycle_id = hero.lifecycle_id, event_id = 'old-lifecycle-event',
        })
        equal(stale, false, 'old re-registered lifecycle events stay silent')
        equal(stale_error, 'stale-actor-lifecycle', 'old re-registered lifecycle rejection is explicit')
    end
end

print('PASS: ' .. tests .. ' controller assertions')
