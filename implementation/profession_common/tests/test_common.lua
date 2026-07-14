package.path = 'implementation/profession_common/lua/?.lua;' .. package.path

local Target = require 'profession_target_contract'
local Store = require 'profession_effect_store'
local Ledger = require 'profession_control_ledger'
local Contract = require 'profession_adapter_contract'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local source = { id = 'source' }
local first = { id = 'first' }
local second = { id = 'second' }
local context = Target.populate_context({}, source, 'actor', { first, second }, { source, second })

do
    local self_targets = Target.resolve('actor', { target_scope = 'self' }, context)
    equal(self_targets[1].id, 'source', 'self resolves source unit')
    local selected = Target.resolve('actor', { target_scope = 'selected' }, context)
    equal(#selected, 2, 'selected resolves every selected unit')
    local team = Target.resolve('actor', { target_scope = 'team' }, context)
    equal(#team, 1, 'team excludes the source unit even when upstream selection includes it')
    equal(team[1].id, 'second', 'team keeps actual teammate')
    local explicit = Target.resolve('actor', { target_scope = 'explicit', target_id = 'first' }, context)
    equal(explicit[1].id, 'first', 'explicit resolves stable id through context map')
    local aliased = Target.resolve('actor', { target_scope = 'explicit', target_id = 'second' }, {
        target_refs_by_id = { second = second },
    })
    equal(aliased[1].ref, second, 'target_refs_by_id is accepted as an explicit bridge alias')
    local valid = Target.validate_scope('invalid')
    truthy(not valid, 'invalid target scope is rejected')
end

do
    local store = Store.new({ shared = { policy = 'shared_highest', priority_key = 'slow' }, private = { policy = 'source_bound' } }, Target)
    Store.apply(store, 'boss', 'shared', 'a', 0, 8, { slow = 0.15, label = 'low' })
    Store.apply(store, 'boss', 'shared', 'b', 0, 4, { slow = 0.30, label = 'high' })
    equal(Store.get(store, 'boss', 'shared', 1).payload.slow, 0.30, 'shared store chooses highest numeric payload')
    equal(Store.get(store, 'boss', 'shared', 1).source_id, 'b', 'shared store identifies the active highest source')
    local initial_changes = Store.collect_shared_changes(store, 1)
    equal(initial_changes[1].current.source_id, 'b', 'initial shared presentation records the highest source')
    local fallback_changes = Store.collect_shared_changes(store, 4)
    equal(fallback_changes[1].current.source_id, 'a', 'expired high source falls back to the active lower source')
    equal(fallback_changes[1].current.payload.label, 'low', 'fallback keeps one source payload rather than merging sources')
    local removal_changes = Store.collect_shared_changes(store, 8)
    truthy(removal_changes[1].current == nil, 'shared presentation removes only after its final source expires')
    Store.apply(store, 'boss', 'private', 'a', 0, 4, {})
    Store.apply(store, 'boss', 'private', 'b', 0, 4, {})
    truthy(Store.remove_source(store, 'boss', 'private', 'a'), 'private source removes independently')
    truthy(Store.get(store, 'boss', 'private', 1, 'b') ~= nil, 'other private source remains')
    local cleanup = Store.source_cleanup_commands(store, 'b')
    equal(cleanup[1].target_scope, 'explicit', 'source cleanup is explicit')
end

do
    local timers = {}
    local target = { id = 'root', exists = true, added = 0, removed = 0 }
    function target:get_id() return self.id end
    function target:is_exist() return self.exists end
    function target:add_state() self.added = self.added + 1 end
    function target:remove_state() self.removed = self.removed + 1 end
    local ledger = Ledger.new()
    local function wait(_, callback)
        local timer = { callback = callback }
        function timer:remove() self.removed = true end
        timers[#timers + 1] = timer
        return timer
    end
    ledger:acquire(target, 'root', 1, { schedule = wait })
    ledger:acquire(target, 'root', 2, { schedule = wait })
    equal(target.added, 1, 'first lease adds state once')
    timers[1].callback()
    equal(target.removed, 0, 'first expiry retains later lease')
    timers[2].callback()
    equal(target.removed, 1, 'final expiry removes state')
end

do
    local timers = {}
    local target = { id = 'source-root', exists = true, added = 0, removed = 0 }
    function target:get_id() return self.id end
    function target:is_exist() return self.exists end
    function target:add_state() self.added = self.added + 1 end
    function target:remove_state() self.removed = self.removed + 1 end
    local ledger = Ledger.new()
    local function wait(_, callback)
        local timer = { callback = callback }
        function timer:remove() self.removed = true end
        timers[#timers + 1] = timer
        return timer
    end
    ledger:acquire({ target = target, target_id = target.id, control_key = 'root', duration = 4,
        source_actor_id = 'first', lifecycle_id = 1, schedule = wait })
    ledger:acquire({ target = target, target_id = target.id, control_key = 'root', duration = 4,
        source_actor_id = 'second', lifecycle_id = 2, schedule = wait })
    equal(target.added, 1, 'source-owned leases still add one root state')
    equal(ledger:release_by_source('first', 1), 1, 'source release removes only its own lease')
    equal(target.removed, 0, 'other source keeps overlapping control alive')
    equal(ledger:release_by_source('second', 2), 1, 'second source lease can be released independently')
    equal(target.removed, 1, 'last released source removes root state')
end

do
    local adapter = {}
    for _, name in ipairs(Contract.required_methods()) do adapter[name] = function() end end
    truthy(Contract.validate(adapter), 'adapter with every method validates')
    local ok, reason = Contract.execute(adapter, 'actor', { { type = 'guard_gain', guard = 10 } }, {})
    truthy(ok and reason == nil, 'generic guard state event dispatches')
    local seal_ok, seal_reason = Contract.execute(adapter, 'actor', {
        { type = 'seal_changed', seals = 3, mingtai = true },
        { type = 'p01_speed', move_speed = 0.12, duration = 2 },
    }, {})
    truthy(seal_ok and seal_reason == nil, 'profession-neutral seal and temporary speed events dispatch')
end

print('PASS: ' .. tests .. ' common assertions')
