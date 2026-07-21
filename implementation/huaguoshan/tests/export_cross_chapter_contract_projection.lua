-- Read-only projection for the Difu <-> Huaguoshan contract checker.
-- It intentionally evaluates the target Config table so Lua duplicate-key
-- semantics are observed instead of inferred from source text.  The Config
-- chunk receives a deliberately minimal environment: it cannot access host
-- process, filesystem, package loading, debug, or dynamic-code globals.

local config_path = arg and arg[1]
if type(config_path) ~= 'string' or config_path == '' then
    error('a huaguoshan_config.lua path is required')
end

local config_environment = {
    _VERSION = _VERSION,
    assert = assert,
    error = error,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    table = {
        concat = table.concat,
        insert = table.insert,
        sort = table.sort,
    },
}
config_environment._G = config_environment

for _, forbidden_name in ipairs({
    'os', 'io', 'package', 'require', 'debug', 'load', 'dofile', 'loadfile',
    'collectgarbage', 'getmetatable', 'setmetatable', 'rawget', 'rawset',
    'rawequal', 'coroutine',
}) do
    if config_environment[forbidden_name] ~= nil then
        error('unsafe Config environment global exposed: ' .. forbidden_name)
    end
end

local chunk, load_error = loadfile(config_path, 't', config_environment)
if not chunk then error('failed to load Config: ' .. tostring(load_error)) end
local Config = chunk()
if type(Config) ~= 'table' or type(Config.encounters) ~= 'table' then
    error('huaguoshan_config.lua must return Config.encounters')
end

local function required_string_fields(encounter_key, field_names)
    local encounter = Config.encounters[encounter_key]
    if type(encounter) ~= 'table' then
        error('missing encounter: ' .. encounter_key)
    end

    local result = {}
    for _, field_name in ipairs(field_names) do
        local value = encounter[field_name]
        if type(value) ~= 'string' or value == '' then
            error(encounter_key .. '.' .. field_name .. ' must be a non-empty string')
        end
        result[field_name] = value
    end
    return result
end

-- Export every effective Config.encounters progression-key consumer, not only
-- the two cross-chapter encounters below.  This lets the caller prove that a
-- Difu progression key has no hidden second consumer after normal Lua table
-- evaluation (including duplicate-key last-write semantics).
local function progression_key_consumers()
    local result = {}
    for encounter_key, encounter in pairs(Config.encounters) do
        if type(encounter_key) ~= 'string' or encounter_key == '' then
            error('Config.encounters contains a non-string or blank encounter key')
        end
        if type(encounter) ~= 'table' then
            error('Config.encounters.' .. encounter_key .. ' must be a table')
        end

        local progression_key = encounter.progression_key
        if progression_key ~= nil then
            if type(progression_key) ~= 'string' or progression_key == '' then
                error('Config.encounters.' .. encounter_key .. '.progression_key must be a non-empty string when present')
            end
            result[encounter_key] = progression_key
        end
    end
    return result
end

local function quote(value)
    return '"' .. value
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r')
        :gsub('\t', '\\t') .. '"'
end

local function encode(value)
    local value_type = type(value)
    if value_type == 'string' then return quote(value) end
    if value_type == 'number' or value_type == 'boolean' then return tostring(value) end
    if value_type ~= 'table' then error('unsupported projection value: ' .. value_type) end

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    local items = {}
    for _, key in ipairs(keys) do
        items[#items + 1] = quote(key) .. ':' .. encode(value[key])
    end
    return '{' .. table.concat(items, ',') .. '}'
end

local projection = {
    reverse_tide = required_string_fields('HG_E_DRAGON_REVERSE_TIDE', {
        'encounter_type',
        'combat_scope',
        'return_point',
        'unlock_rule',
        'progression_key',
    }),
    ox_battlefield = required_string_fields('HG_E_OX_BATTLEFIELD', {
        'encounter_type',
        'combat_scope',
        'return_point',
        'reentry_policy',
    }),
    progression_key_consumers = progression_key_consumers(),
}

print(encode(projection))
