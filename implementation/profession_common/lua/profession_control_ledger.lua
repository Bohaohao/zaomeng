-- Canonical API: ledger:acquire(target, control_key, duration, hooks).
-- hooks.target_id and hooks.schedule keep this module independent of Y3.

local M = {}

local Ledger = {}
Ledger.__index = Ledger

local function default_is_alive(target)
    if not target then
        return false
    end
    if type(target.is_exist) == 'function' then
        return target:is_exist()
    end
    if type(target.is_destroyed) == 'function' then
        return not target:is_destroyed()
    end
    return true
end

local function cancel_timer(timer)
    if timer and type(timer.remove) == 'function' then
        timer:remove()
    elseif type(timer) == 'function' then
        timer()
    end
end

local function lease_count(bucket)
    local count = 0
    for _ in pairs(bucket.leases) do
        count = count + 1
    end
    return count
end

local function read_now(ledger, hooks, explicit_now)
    if explicit_now ~= nil then
        return explicit_now
    end
    if type(hooks.now) == 'function' then
        return hooks.now()
    end
    if type(hooks.now) == 'number' then
        return hooks.now
    end
    if type(ledger.options.now) == 'function' then
        return ledger.options.now()
    end
    if type(ledger.options.now) == 'number' then
        return ledger.options.now
    end
    return 0
end

local function resolve_target_id(target, hooks)
    if hooks.target_id ~= nil then
        return hooks.target_id
    end
    if hooks.id ~= nil then
        return hooks.id
    end
    if type(hooks.get_target_id) == 'function' then
        return hooks.get_target_id(target)
    end
    if target and type(target.get_id) == 'function' then
        return target:get_id()
    end
    if target and target.id ~= nil then
        return target.id
    end
    return nil
end

local function merge_hooks(ledger, hooks)
    hooks = hooks or {}
    return {
        target_id = hooks.target_id,
        source_actor_id = hooks.source_actor_id,
        lifecycle_id = hooks.lifecycle_id,
        cast_id = hooks.cast_id,
        schedule = hooks.schedule or hooks.timer_wait or hooks.wait or ledger.options.schedule,
        is_alive = hooks.is_alive or hooks.is_target_alive or ledger.options.is_alive or ledger.options.is_target_alive or default_is_alive,
        add_state = hooks.add_state or hooks.add_control or ledger.options.add_state or function(target, control_key)
            if target and type(target.add_state) == 'function' then
                target:add_state(control_key)
            end
        end,
        remove_state = hooks.remove_state or hooks.remove_control or ledger.options.remove_state or function(target, control_key)
            if target and type(target.remove_state) == 'function' then
                target:remove_state(control_key)
            end
        end,
        now = hooks.now,
    }
end

function M.new(options)
    options = options or {}
    local records = {}
    return setmetatable({
        options = options,
        records = records,
        leases = records,
        next_lease_id = 0,
    }, Ledger)
end

function Ledger:_remove_bucket(target_id, control_key, bucket)
    local target_records = self.records[target_id]
    if not target_records or target_records[control_key] ~= bucket then
        return false
    end

    target_records[control_key] = nil
    if next(target_records) == nil then
        self.records[target_id] = nil
    end

    if bucket.hooks.is_alive(bucket.target) then
        bucket.hooks.remove_state(bucket.target, control_key)
    end
    return true
end

function Ledger:_clear_bucket(target_id, control_key, bucket)
    for _, lease in pairs(bucket.leases) do
        cancel_timer(lease.timer)
    end
    bucket.leases = {}
    bucket.count = 0
    return self:_remove_bucket(target_id, control_key, bucket)
end

local function parse_acquire(first, control_key, third, fourth, fifth)
    if type(first) == 'table' and control_key == nil then
        return first.target, first.target_id, first.control_key or first.control_type, first.duration, first, first.now
    end

    -- target-first is the public form. The ID-first form remains accepted for
    -- bridge code that already has a stable ID before resolving the target.
    if type(first) == 'table' and type(third) == 'number' then
        return first, nil, control_key, third, fourth or {}, fifth
    end
    return third, first, control_key, fourth, {}, fifth
end

function Ledger:acquire(first, control_key, third, fourth, fifth)
    local target, target_id, resolved_control_key, duration, hooks, explicit_now = parse_acquire(
        first,
        control_key,
        third,
        fourth,
        fifth
    )
    hooks = merge_hooks(self, hooks)
    resolved_control_key = resolved_control_key or self.options.default_control_type or 'root'
    target_id = target_id or resolve_target_id(target, hooks)

    assert(target_id ~= nil, 'stable target_id is required')
    assert(target ~= nil, 'target is required')
    assert(type(duration) == 'number' and duration >= 0, 'duration must be a non-negative number')
    if type(hooks.schedule) ~= 'function' then
        return nil, 'schedule-required'
    end
    if not hooks.is_alive(target) then
        return nil, 'target-destroyed'
    end

    local target_records = self.records[target_id]
    local bucket = target_records and target_records[resolved_control_key]
    if bucket and not bucket.hooks.is_alive(bucket.target) then
        self:_clear_bucket(target_id, resolved_control_key, bucket)
        target_records = self.records[target_id]
        bucket = nil
    end

    if not bucket then
        target_records = target_records or {}
        self.records[target_id] = target_records
        bucket = {
            target = target,
            target_id = target_id,
            control_key = resolved_control_key,
            control_type = resolved_control_key,
            leases = {},
            count = 0,
            hooks = hooks,
        }
        target_records[resolved_control_key] = bucket
        hooks.add_state(target, resolved_control_key)
    end

    self.next_lease_id = self.next_lease_id + 1
    local acquired_at = read_now(self, hooks, explicit_now)
    local lease = {
        id = self.next_lease_id,
        lease_id = self.next_lease_id,
        target_id = target_id,
        control_key = resolved_control_key,
        control_type = resolved_control_key,
        target = bucket.target,
        acquired_at = acquired_at,
        expires_at = acquired_at + duration,
        -- Ownership is optional for legacy callers, but bridge callers must
        -- supply it so a dead or replaced actor can release only its lease.
        source_actor_id = hooks.source_actor_id,
        lifecycle_id = hooks.lifecycle_id,
        cast_id = hooks.cast_id,
    }
    bucket.leases[lease.id] = lease
    bucket.count = bucket.count + 1

    lease.timer = hooks.schedule(duration, function()
        self:expire(target_id, resolved_control_key, lease.id)
    end, self.options.description or 'Profession control lease cleanup')
    lease.release = function()
        return self:expire(target_id, resolved_control_key, lease.id)
    end

    return lease
end

function Ledger:expire(target_id, control_key, lease_id)
    if type(target_id) == 'table' and control_key == nil then
        local lease = target_id
        target_id = lease.target_id
        control_key = lease.control_key or lease.control_type
        lease_id = lease.id or lease.lease_id
    end

    local target_records = self.records[target_id]
    local bucket = target_records and target_records[control_key]
    local lease = bucket and bucket.leases[lease_id]
    if not lease then
        return false
    end

    bucket.leases[lease_id] = nil
    bucket.count = lease_count(bucket)
    cancel_timer(lease.timer)
    if bucket.count == 0 then
        self:_remove_bucket(target_id, control_key, bucket)
    end
    return true
end

function Ledger:release(target_id, control_key, lease_id)
    return self:expire(target_id, control_key, lease_id)
end

-- Releases only leases created by one actor lifecycle. This intentionally does
-- not clear the whole bucket: another caster can still own the same control.
function Ledger:release_by_source(source_actor_id, lifecycle_id)
    if source_actor_id == nil then
        return 0
    end

    local matches = {}
    for target_id, target_records in pairs(self.records) do
        for control_key, bucket in pairs(target_records) do
            for lease_id, lease in pairs(bucket.leases) do
                if lease.source_actor_id == source_actor_id
                    and (lifecycle_id == nil or lease.lifecycle_id == lifecycle_id) then
                    matches[#matches + 1] = {
                        target_id = target_id,
                        control_key = control_key,
                        lease_id = lease_id,
                    }
                end
            end
        end
    end

    local released = 0
    for _, match in ipairs(matches) do
        if self:expire(match.target_id, match.control_key, match.lease_id) then
            released = released + 1
        end
    end
    return released
end

function Ledger:clear_target(target_id)
    local target_records = self.records[target_id]
    if not target_records then
        return false
    end

    local cleared = false
    local controls = {}
    for control_key in pairs(target_records) do
        controls[#controls + 1] = control_key
    end
    for _, control_key in ipairs(controls) do
        local bucket = target_records[control_key]
        if bucket then
            cleared = self:_clear_bucket(target_id, control_key, bucket) or cleared
        end
    end
    return cleared
end

function Ledger:clear_target_for(target)
    local target_ids = {}
    for target_id, target_records in pairs(self.records) do
        for _, bucket in pairs(target_records) do
            if bucket.target == target then
                target_ids[#target_ids + 1] = target_id
                break
            end
        end
    end
    local cleared = false
    for _, target_id in ipairs(target_ids) do
        cleared = self:clear_target(target_id) or cleared
    end
    return cleared
end

function Ledger:reap(target_id)
    local target_records = self.records[target_id]
    if not target_records then
        return false
    end
    local removed = false
    local controls = {}
    for control_key in pairs(target_records) do
        controls[#controls + 1] = control_key
    end
    for _, control_key in ipairs(controls) do
        local bucket = target_records[control_key]
        if bucket and not bucket.hooks.is_alive(bucket.target) then
            removed = self:_clear_bucket(target_id, control_key, bucket) or removed
        end
    end
    return removed
end

function Ledger:get(target_id, control_key)
    local target_records = self.records[target_id]
    if not target_records then
        return nil
    end
    if control_key == nil then
        return target_records
    end
    return target_records[control_key]
end

function Ledger:count(target_id, control_key)
    local bucket = self:get(target_id, control_key)
    if not bucket then
        return 0
    end
    if control_key == nil then
        local total = 0
        for _, control_bucket in pairs(bucket) do
            total = total + (control_bucket.count or lease_count(control_bucket))
        end
        return total
    end
    return bucket.count or lease_count(bucket)
end

function Ledger:has(target_id, control_key)
    return self:count(target_id, control_key) > 0
end

function Ledger:clear()
    local target_ids = {}
    for target_id in pairs(self.records) do
        target_ids[#target_ids + 1] = target_id
    end
    for _, target_id in ipairs(target_ids) do
        self:clear_target(target_id)
    end
end

M.Ledger = Ledger
M.acquire = Ledger.acquire
M.add = Ledger.acquire
M.lease = Ledger.acquire
M.expire = Ledger.expire
M.release = Ledger.release
M.release_by_source = Ledger.release_by_source
M.clear_target = Ledger.clear_target

return M
