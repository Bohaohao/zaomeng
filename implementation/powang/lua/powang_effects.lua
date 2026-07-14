-- Compatibility facade: Powang keeps its public module name while using the
-- profession-neutral effect store with its own modifier policy table.
local Store = require 'profession_effect_store'
local Config = require 'powang_config'
local TargetContract = require 'powang_target_contract'

local M = {}

function M.new()
    return Store.new(Config.modifiers, TargetContract)
end

return setmetatable(M, { __index = Store })
