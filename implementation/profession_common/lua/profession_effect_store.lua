local DefaultTargetContract = require 'profession_target_contract'

local M = {}

local function unit_bucket(engine, unit_id, unit_ref)
    local bucket = engine.units[unit_id]
    if not bucket then
        bucket = { effects = {}, unit_ref = unit_ref }
        engine.units[unit_id] = bucket
    elseif unit_ref then
        bucket.unit_ref = unit_ref
    end
    return bucket
end

local function source_key(source_id)
    if source_id == nil then
        return '__system__'
    end
    return tostring(source_id)
end

local function copy_payload(payload)
    local result = {}
    for key, value in pairs(payload or {}) do
        result[key] = value
    end
    return result
end

local function purge_effect(effect, now)
    for key, source in pairs(effect.sources) do
        if source.expires_at and now >= source.expires_at then
            effect.sources[key] = nil
        end
    end
end

local function source_count(effect)
    local count = 0
    for _ in pairs(effect.sources) do
        count = count + 1
    end
    return count
end

function M.new(modifier_definitions, target_contract)
    assert(type(modifier_definitions) == 'table', 'modifier definitions are required')
    return {
        units = {},
        shared_presentations = {},
        modifier_definitions = modifier_definitions,
        target_contract = target_contract or DefaultTargetContract,
    }
end

function M.apply(engine, unit_id, modifier_key, source_id, now, duration, payload, unit_ref)
    local definition = engine.modifier_definitions and engine.modifier_definitions[modifier_key]
    assert(definition, 'unknown modifier: ' .. tostring(modifier_key))
    assert(definition.policy ~= 'derived', 'derived modifier cannot be applied directly')

    local bucket = unit_bucket(engine, unit_id, unit_ref)
    local effect = bucket.effects[modifier_key]
    if not effect then
        effect = {
            key = modifier_key,
            policy = definition.policy,
            priority_key = definition.priority_key,
            sources = {},
        }
        bucket.effects[modifier_key] = effect
    end

    purge_effect(effect, now)
    local key = source_key(source_id)
    effect.sources[key] = {
        source_id = source_id,
        applied_at = now,
        duration = duration,
        expires_at = duration and (now + duration) or nil,
        payload = copy_payload(payload),
    }
    return effect.sources[key]
end

function M.refresh(engine, unit_id, modifier_key, source_id, now, duration)
    local bucket = engine.units[unit_id]
    if not bucket then
        return false
    end
    local effect = bucket.effects[modifier_key]
    if not effect then
        return false
    end
    purge_effect(effect, now)
    local source = effect.sources[source_key(source_id)]
    if not source then
        return false
    end
    local refresh_duration = duration or source.duration
    if not refresh_duration then
        return false
    end
    source.duration = refresh_duration
    source.expires_at = now + refresh_duration
    return true
end

function M.refresh_all(engine, unit_id, modifier_key, now)
    local bucket = engine.units[unit_id]
    local effect = bucket and bucket.effects[modifier_key]
    if not effect then
        return false
    end
    purge_effect(effect, now)
    local refreshed = false
    for _, source in pairs(effect.sources) do
        if source.duration then
            source.expires_at = now + source.duration
            refreshed = true
        end
    end
    return refreshed
end

function M.extend_shared_once(engine, unit_id, modifier_key, extender_id, now, duration, marker)
    local bucket = engine.units[unit_id]
    local effect = bucket and bucket.effects[modifier_key]
    if not effect then
        return false
    end
    purge_effect(effect, now)
    effect.extension_markers = effect.extension_markers or {}
    local extension_key = source_key(extender_id) .. ':' .. tostring(marker)
    if effect.extension_markers[extension_key] then
        return false
    end
    effect.extension_markers[extension_key] = true
    local extended = false
    for _, source in pairs(effect.sources) do
        source.expires_at = (source.expires_at or now) + duration
        extended = true
    end
    return extended
end

function M.remove_source(engine, unit_id, modifier_key, source_id)
    local bucket = engine.units[unit_id]
    if not bucket then
        return false
    end
    local effect = bucket.effects[modifier_key]
    if not effect then
        return false
    end
    local key = source_key(source_id)
    local existed = effect.sources[key] ~= nil
    effect.sources[key] = nil
    if source_count(effect) == 0 then
        bucket.effects[modifier_key] = nil
    end
    return existed
end

function M.extend_once(engine, unit_id, modifier_key, source_id, now, duration, marker)
    local bucket = engine.units[unit_id]
    if not bucket then
        return false
    end
    local effect = bucket.effects[modifier_key]
    if not effect then
        return false
    end
    purge_effect(effect, now)

    local key = source_key(source_id)
    local source = effect.sources[key]
    if not source then
        return false
    end
    source.extension_markers = source.extension_markers or {}
    if source.extension_markers[marker] then
        return false
    end
    source.extension_markers[marker] = true
    source.expires_at = (source.expires_at or now) + duration
    return true
end

local function source_priority(source, priority_key)
    if priority_key and type(source.payload[priority_key]) == 'number' then
        return source.payload[priority_key]
    end
    local highest = 0
    for _, value in pairs(source.payload) do
        if type(value) == 'number' and value > highest then
            highest = value
        end
    end
    return highest
end

local function source_expiry(source)
    return source.expires_at or math.huge
end

local function aggregate_highest(effect)
    local winner, winner_key, winner_priority
    for key, source in pairs(effect.sources) do
        local priority = source_priority(source, effect.priority_key)
        local replace = winner == nil or priority > winner_priority
        if not replace and priority == winner_priority then
            local expiry = source_expiry(source)
            local winner_expiry = source_expiry(winner)
            replace = expiry > winner_expiry
                or (expiry == winner_expiry and tostring(key) < tostring(winner_key))
        end
        if replace then
            winner = source
            winner_key = key
            winner_priority = priority
        end
    end
    if not winner then
        return {}, nil, nil
    end
    return copy_payload(winner.payload), winner.expires_at, winner.source_id
end

function M.get(engine, unit_id, modifier_key, now, source_id)
    local bucket = engine.units[unit_id]
    if not bucket then
        return nil
    end
    local effect = bucket.effects[modifier_key]
    if not effect then
        return nil
    end
    purge_effect(effect, now)
    if source_count(effect) == 0 then
        bucket.effects[modifier_key] = nil
        return nil
    end

    if source_id ~= nil then
        return effect.sources[source_key(source_id)]
    end

    if effect.policy == 'shared_highest' then
        local payload, expires_at, aggregate_source_id = aggregate_highest(effect)
        return {
            key = modifier_key,
            policy = effect.policy,
            payload = payload,
            expires_at = expires_at,
            source_id = aggregate_source_id,
            source_count = source_count(effect),
        }
    end

    return {
        key = modifier_key,
        policy = effect.policy,
        sources = effect.sources,
        source_count = source_count(effect),
    }
end

local function payloads_equal(first, second)
    for key, value in pairs(first or {}) do
        if second == nil or second[key] ~= value then
            return false
        end
    end
    for key, value in pairs(second or {}) do
        if first == nil or first[key] ~= value then
            return false
        end
    end
    return true
end

local function presentations_equal(first, second)
    if first == nil or second == nil then
        return first == second
    end
    return first.source_id == second.source_id
        and first.expires_at == second.expires_at
        and payloads_equal(first.payload, second.payload)
end

local function set_shared_presentation(engine, unit_id, modifier_key, snapshot)
    local presentations = engine.shared_presentations
    local unit_presentations = presentations[unit_id]
    if snapshot == nil then
        if unit_presentations then
            unit_presentations[modifier_key] = nil
            if next(unit_presentations) == nil then
                presentations[unit_id] = nil
            end
        end
        return
    end
    if not unit_presentations then
        unit_presentations = {}
        presentations[unit_id] = unit_presentations
    end
    unit_presentations[modifier_key] = {
        source_id = snapshot.source_id,
        expires_at = snapshot.expires_at,
        payload = copy_payload(snapshot.payload),
    }
end

function M.collect_shared_changes(engine, now)
    local changes = {}
    local seen = {}
    local unit_ids = {}
    for unit_id in pairs(engine.units) do
        unit_ids[#unit_ids + 1] = unit_id
    end

    for _, unit_id in ipairs(unit_ids) do
        local bucket = engine.units[unit_id]
        if bucket then
            local modifier_keys = {}
            for modifier_key, effect in pairs(bucket.effects) do
                if effect.policy == 'shared_highest' then
                    modifier_keys[#modifier_keys + 1] = modifier_key
                end
            end
            for _, modifier_key in ipairs(modifier_keys) do
                local previous = engine.shared_presentations[unit_id]
                    and engine.shared_presentations[unit_id][modifier_key]
                    or nil
                local current = M.get(engine, unit_id, modifier_key, now)
                seen[unit_id] = seen[unit_id] or {}
                seen[unit_id][modifier_key] = true
                if not presentations_equal(previous, current) then
                    changes[#changes + 1] = {
                        unit_id = unit_id,
                        unit_ref = bucket.unit_ref,
                        modifier_key = modifier_key,
                        previous = previous,
                        current = current,
                    }
                    set_shared_presentation(engine, unit_id, modifier_key, current)
                end
            end
        end
    end

    local stale_units = {}
    for unit_id in pairs(engine.shared_presentations) do
        stale_units[#stale_units + 1] = unit_id
    end
    for _, unit_id in ipairs(stale_units) do
        local unit_presentations = engine.shared_presentations[unit_id]
        local stale_modifiers = {}
        for modifier_key in pairs(unit_presentations or {}) do
            if not (seen[unit_id] and seen[unit_id][modifier_key]) then
                stale_modifiers[#stale_modifiers + 1] = modifier_key
            end
        end
        for _, modifier_key in ipairs(stale_modifiers) do
            local previous = engine.shared_presentations[unit_id]
                and engine.shared_presentations[unit_id][modifier_key]
                or nil
            if previous then
                local bucket = engine.units[unit_id]
                changes[#changes + 1] = {
                    unit_id = unit_id,
                    unit_ref = bucket and bucket.unit_ref or nil,
                    modifier_key = modifier_key,
                    previous = previous,
                    current = nil,
                }
                set_shared_presentation(engine, unit_id, modifier_key, nil)
            end
        end
    end
    return changes
end

function M.clear_unit(engine, unit_id)
    engine.units[unit_id] = nil
    engine.shared_presentations[unit_id] = nil
end

function M.clear_source(engine, source_id)
    local key = source_key(source_id)
    for unit_id, bucket in pairs(engine.units) do
        for modifier_key, effect in pairs(bucket.effects) do
            effect.sources[key] = nil
            if source_count(effect) == 0 then
                bucket.effects[modifier_key] = nil
            end
        end
        if next(bucket.effects) == nil then
            engine.units[unit_id] = nil
        end
    end
end

function M.execute(engine, actor_id, command, context, now)
    context = context or {}
    now = now or context.now or 0
    local command_type = command.type
    if command_type ~= 'apply_modifier'
        and command_type ~= 'apply_modifier_to_targets'
        and command_type ~= 'apply_team_modifier'
        and command_type ~= 'remove_modifier'
        and command_type ~= 'refresh_modifier'
        and command_type ~= 'extend_modifier_once' then
        return false, nil
    end

    local target_contract = engine.target_contract or DefaultTargetContract
    target_contract.ensure_scope(command)
    local entries, resolve_error = target_contract.resolve(actor_id, command, context)
    if not entries then
        return false, resolve_error
    end

    -- Keep the resolved ownership visible to the Y3 bridge without making the
    -- bridge depend on this offline effect store.
    command.resolved_targets = entries
    command.resolved_target_ids = {}
    command.resolved_target_refs = {}
    for index, entry in ipairs(entries) do
        command.resolved_target_ids[index] = entry.id
        command.resolved_target_refs[index] = entry.ref
    end

    local snapshots = {}
    local source_id = command.source_id
    if source_id == nil then
        source_id = actor_id
    end
    for _, entry in ipairs(entries) do
        local unit_id = entry.id
        local unit_ref = entry.ref
        if command_type == 'apply_modifier'
            or command_type == 'apply_modifier_to_targets'
            or command_type == 'apply_team_modifier' then
            M.apply(engine, unit_id, command.key, source_id, now, command.duration, command.payload, unit_ref)
        elseif command_type == 'remove_modifier' then
            M.remove_source(engine, unit_id, command.key, source_id)
        elseif command_type == 'refresh_modifier' then
            if command.highest_value_refresh then
                M.refresh_all(engine, unit_id, command.key, now)
            else
                M.refresh(engine, unit_id, command.key, source_id, now, command.duration)
            end
        elseif command_type == 'extend_modifier_once' then
            local bucket = engine.units[unit_id]
            local effect = bucket and bucket.effects[command.key]
            if effect and effect.policy == 'shared_highest' then
                M.extend_shared_once(engine, unit_id, command.key, source_id, now, command.duration, command.reason)
            else
                M.extend_once(engine, unit_id, command.key, source_id, now, command.duration, command.reason)
            end
        end
        snapshots[tostring(unit_id)] = {
            aggregate = M.get(engine, unit_id, command.key, now),
            source = M.get(engine, unit_id, command.key, now, source_id),
        }
        local definition = engine.modifier_definitions[command.key]
        if definition and definition.policy == 'shared_highest' then
            set_shared_presentation(engine, unit_id, command.key, snapshots[tostring(unit_id)].aggregate)
        end
    end
    return true, snapshots
end

function M.source_cleanup_commands(engine, source_id)
    local commands = {}
    local key = source_key(source_id)
    for unit_id, bucket in pairs(engine.units) do
        for modifier_key, effect in pairs(bucket.effects) do
            if effect.sources[key] then
            commands[#commands + 1] = {
                type = 'remove_modifier',
                key = modifier_key,
                target_id = unit_id,
                target = bucket.unit_ref,
                target_ids = { unit_id },
                targets = bucket.unit_ref and { bucket.unit_ref } or {},
                target_scope = 'explicit',
                source_id = source_id,
            }
            end
        end
    end
    return commands
end

return M
