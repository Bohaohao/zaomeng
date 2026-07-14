local M = {}

M.scopes = {
    self = 'self',
    primary = 'primary',
    selected = 'selected',
    team = 'team',
    explicit = 'explicit',
}
M.SCOPES = M.scopes
M.target_scopes = M.scopes

local scope_names = {
    'self',
    'primary',
    'selected',
    'team',
    'explicit',
}

local function append(list, value)
    list[#list + 1] = value
end

local function append_unique(entries, id, ref, seen)
    if id == nil then
        return
    end
    if seen[id] then
        return
    end
    seen[id] = true
    append(entries, { id = id, ref = ref })
end

local function read_method(value, name)
    if value == nil then
        return nil
    end
    local ok, method = pcall(function()
        return value[name]
    end)
    if ok and type(method) == 'function' then
        return method
    end
    return nil
end

local function call_get_id(value)
    local method = read_method(value, 'get_id')
    if not method then
        return nil
    end
    local ok, id = pcall(method, value)
    if ok and id ~= nil then
        return id
    end
    return nil
end

function M.id_of(value, fallback)
    if value == nil then
        return fallback
    end

    local value_type = type(value)
    if value_type ~= 'table' and value_type ~= 'userdata' then
        return value
    end

    local id = call_get_id(value)
    if id ~= nil then
        return id
    end

    if value_type == 'table' and value.id ~= nil then
        return value.id
    end

    if fallback ~= nil then
        return fallback
    end

    -- Offline stubs may not implement Unit:get_id; real Y3 units take the path above.
    return tostring(value)
end

M.get_id = M.id_of
M.unit_id = M.id_of

local function map_lookup(map, id)
    if type(map) ~= 'table' then
        return nil
    end
    local ref = map[id]
    if ref ~= nil then
        return ref
    end
    return map[tostring(id)]
end

local function context_maps(context, command)
    local maps = {}
    local function add(map)
        if type(map) == 'table' then
            append(maps, map)
        end
    end
    add(command and command.target_refs)
    add(command and command.target_refs_by_id)
    add(command and command.targets_by_id)
    add(command and command.units_by_id)
    add(context.target_refs)
    add(context.target_refs_by_id)
    add(context.targets_by_id)
    add(context.units_by_id)
    add(context.unit_by_id)
    add(context.id_to_unit)
    add(context.selected_target_refs)
    add(context.team_target_refs)
    return maps
end

local function lookup_ref(context, command, id)
    if id == nil then
        return nil
    end
    for _, map in ipairs(context_maps(context, command)) do
        local ref = map_lookup(map, id)
        if ref ~= nil then
            return ref
        end
    end
    return nil
end

local function collection_entries(ids, refs, context, command)
    local entries = {}
    local seen = {}
    ids = ids or {}
    refs = refs or {}

    for index, id in ipairs(ids) do
        local ref = refs[index] or lookup_ref(context, command, id)
        append_unique(entries, id, ref, seen)
    end

    if #ids == 0 then
        for index, ref in ipairs(refs) do
            append_unique(entries, M.id_of(ref), ref, seen)
        end
    end

    return entries
end

local function explicit_collection(command, context)
    local ids = command.target_ids
    local refs = command.targets

    if command.target_id ~= nil then
        ids = { command.target_id }
        refs = command.target and { command.target } or {}
    elseif command.target ~= nil then
        ids = { M.id_of(command.target) }
        refs = { command.target }
    elseif not ids and not refs then
        ids = command.explicit_target_ids or context.explicit_target_ids
        refs = command.explicit_targets or context.explicit_targets
    end

    return collection_entries(ids, refs, context, command)
end

local function primary_collection(command, context)
    if command.target_id ~= nil or command.target ~= nil then
        return explicit_collection(command, context)
    end

    local id = context.target_id
    local ref = context.target or context.primary_target
    if id ~= nil then
        return collection_entries({ id }, { ref }, context, command)
    end
    if ref ~= nil then
        return collection_entries({ M.id_of(ref) }, { ref }, context, command)
    end

    local ids = context.target_ids or context.selected_target_ids
    local refs = context.targets or context.selected_targets
    if ids and ids[1] ~= nil then
        return collection_entries({ ids[1] }, { refs and refs[1] }, context, command)
    end
    if refs and refs[1] ~= nil then
        return collection_entries({ M.id_of(refs[1]) }, { refs[1] }, context, command)
    end
    return {}
end

local function selected_collection(command, context)
    if command.target_ids or command.targets or command.target_id or command.target then
        return explicit_collection(command, context)
    end
    return collection_entries(
        context.selected_target_ids or context.target_ids,
        context.selected_targets or context.targets,
        context,
        command
    )
end

local function team_collection(command, context)
    if command.target_ids or command.targets or command.target_id or command.target then
        return explicit_collection(command, context)
    end
    local entries = collection_entries(
        context.team_target_ids,
        context.team_targets,
        context,
        command
    )
    local self_id = context.unit_id or context.source_unit_id
    if self_id == nil then
        self_id = M.id_of(context.unit or context.source_unit, context.actor_id)
    end
    if self_id == nil then
        return entries
    end
    local teammates = {}
    for _, entry in ipairs(entries) do
        if entry.id ~= self_id then
            append(teammates, entry)
        end
    end
    return teammates
end

local function self_collection(actor_id, command, context)
    local ref = context.unit or context.source_unit or context.self
    local id = context.unit_id or context.source_unit_id or context.actor_unit_id
    if id == nil then
        id = M.id_of(ref, actor_id)
    end
    return collection_entries({ id }, { ref }, context, command)
end

local function valid_scope(scope)
    if type(scope) ~= 'string' then
        return false
    end
    for _, name in ipairs(scope_names) do
        if scope == name then
            return true
        end
    end
    return false
end

function M.validate_scope(scope)
    if valid_scope(scope) then
        return true
    end
    return false, 'invalid-target-scope:' .. tostring(scope)
end

function M.is_modifier_command(command_type)
    return command_type == 'apply_modifier'
        or command_type == 'apply_modifier_to_targets'
        or command_type == 'apply_team_modifier'
        or command_type == 'remove_modifier'
        or command_type == 'refresh_modifier'
        or command_type == 'extend_modifier_once'
end

function M.ensure_scope(command)
    assert(type(command) == 'table', 'modifier command must be a table')
    assert(command.target_scope ~= nil, 'modifier command requires target_scope')
    local ok, error_code = M.validate_scope(command.target_scope)
    assert(ok, error_code)
    return command.target_scope
end

function M.index_units(units)
    local ids = {}
    local refs = {}
    local by_id = {}
    for _, ref in ipairs(units or {}) do
        if ref ~= nil then
            local id = M.id_of(ref)
            append(ids, id)
            append(refs, ref)
            by_id[id] = ref
        end
    end
    return ids, refs, by_id
end

M.index = M.index_units
M.ids_and_refs = M.index_units

local function merge_maps(target, source)
    for id, ref in pairs(source or {}) do
        target[id] = ref
    end
end

function M.populate_context(context, source, actor_id, selected, team)
    context = context or {}
    selected = selected or context.targets or context.selected_targets or {}
    team = team or context.team_targets or {}

    local source_id = context.unit_id or context.source_unit_id or M.id_of(source, actor_id)
    local target_ids, target_refs, target_map = M.index_units(selected)
    local team_ids, team_refs, team_map = M.index_units(team)
    local refs_by_id = {}

    if source ~= nil then
        refs_by_id[source_id] = source
    end
    merge_maps(refs_by_id, target_map)
    merge_maps(refs_by_id, team_map)

    context.actor_id = context.actor_id or actor_id
    context.unit = context.unit or source
    context.source_unit = context.source_unit or source
    context.unit_id = source_id
    context.source_unit_id = source_id
    context.actor_unit_id = source_id

    context.targets = target_refs
    context.target_ids = target_ids
    context.selected_targets = target_refs
    context.selected_target_ids = target_ids
    context.target_count = #target_refs
    context.target = target_refs[1]
    context.primary_target = target_refs[1]
    context.target_id = target_ids[1]

    context.team_targets = team_refs
    context.team_target_ids = team_ids
    context.team_target_refs = team_map
    context.selected_target_refs = target_map

    -- These aliases keep the ID -> Unit contract discoverable to bridge callers.
    context.target_refs = refs_by_id
    context.target_refs_by_id = refs_by_id
    context.targets_by_id = refs_by_id
    context.units_by_id = refs_by_id
    context.unit_by_id = refs_by_id
    context.id_to_unit = refs_by_id
    return context
end

M.build_context = M.populate_context

function M.resolve(actor_id, command, context)
    context = context or {}
    if type(command) ~= 'table' then
        return nil, 'invalid-target-command'
    end

    local ok, error_code = M.validate_scope(command.target_scope)
    if not ok then
        return nil, error_code
    end

    local scope = command.target_scope
    if scope == M.scopes.self then
        return self_collection(actor_id, command, context)
    end
    if scope == M.scopes.primary then
        return primary_collection(command, context)
    end
    if scope == M.scopes.selected then
        return selected_collection(command, context)
    end
    if scope == M.scopes.team then
        return team_collection(command, context)
    end
    return explicit_collection(command, context)
end

M.resolve_targets = M.resolve
M.resolve_scope = function(scope, actor_id, command, context)
    command = command or {}
    command.target_scope = scope
    return M.resolve(actor_id, command, context)
end

return M
