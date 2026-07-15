local Store = require 'profession_effect_store'
local Config = require 'xunlie_config'
local TargetContract = require 'xunlie_target_contract'

local M = {}

function M.new()
    return Store.new(Config.modifiers, TargetContract)
end

return setmetatable(M, { __index = Store })
