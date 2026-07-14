-- Compatibility facade: C03 keeps a profession-local module name while sharing
-- source-aware effect storage with C01 and C02.
local Store = require 'profession_effect_store'
local Config = require 'chiming_config'
local TargetContract = require 'chiming_target_contract'

local M = {}

function M.new()
    return Store.new(Config.modifiers, TargetContract)
end

return setmetatable(M, { __index = Store })
