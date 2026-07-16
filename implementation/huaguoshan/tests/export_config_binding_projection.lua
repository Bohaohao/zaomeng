local config_path = arg and arg[1]
local Config

if config_path and config_path ~= '' then
    config_path = config_path:gsub('\\', '/')
    local config_root = config_path:match('^(.*)/[^/]+$') or '.'
    package.path = config_root .. '/?.lua;' .. package.path
    local chunk, load_error = loadfile(config_path)
    if not chunk then error('failed to load Config: ' .. tostring(load_error)) end
    Config = chunk()
else
    package.path = 'implementation/huaguoshan/lua/?.lua;' .. package.path
    Config = require 'huaguoshan_config'
end

if type(Config) ~= 'table' or type(Config.build_map_binding_projection) ~= 'function' then
    error('huaguoshan_config.lua must return Config with build_map_binding_projection')
end

local function is_array(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' then return false end
        count = count + 1
    end
    return count == #value
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
    if is_array(value) then
        local items = {}
        for _, item in ipairs(value) do items[#items + 1] = encode(item) end
        return '[' .. table.concat(items, ',') .. ']'
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    local items = {}
    for _, key in ipairs(keys) do
        items[#items + 1] = quote(key) .. ':' .. encode(value[key])
    end
    return '{' .. table.concat(items, ',') .. '}'
end

print(encode(Config.build_map_binding_projection()))
