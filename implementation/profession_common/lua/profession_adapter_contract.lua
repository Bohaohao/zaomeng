local M = {}

local required_methods = {
    'sync_hero_stats',
    'sync_ability_charge',
    'deal_damage',
    'apply_break',
    'schedule_damage',
    'move_safely',
    'apply_effect',
    'change_cooldown',
    'apply_control',
    'set_combo_floor',
    'heal_and_guard',
    'state_changed',
}

local function append(list, value)
    list[#list + 1] = value
end

function M.required_methods()
    local result = {}
    for index, name in ipairs(required_methods) do
        result[index] = name
    end
    return result
end

function M.validate(adapter)
    local missing = {}
    if type(adapter) ~= 'table' then
        return false, required_methods
    end
    for _, name in ipairs(required_methods) do
        if type(adapter[name]) ~= 'function' then
            append(missing, name)
        end
    end
    return #missing == 0, missing
end

local state_event_types = {
    guard_gain = true,
    guard_changed = true,
    guard_cleared_out_of_combat = true,
    guiyuan_generator_bonus = true,
    guiyuan_expired = true,
    momentum_gain = true,
    momentum_refund = true,
    ultimate_gain = true,
    ultimate_activated = true,
    ultimate_distinct_generator_bonus = true,
    spender_committed = true,
    spender_missed = true,
    shixing_ready = true,
    shixing_consumed = true,
    normal_attack_stage = true,
    transient_cleared = true,
    -- Profession-neutral resource/UI notifications. They intentionally carry
    -- only state snapshots; adapters remain responsible for any Y3 Buff or UI.
    seal_changed = true,
    seals_cleared_out_of_combat = true,
    mingjie_expired = true,
    p01_speed = true,
    a04_protection_speed = true,
    a07_protection_speed = true,
    -- C04 hunt-mark resource notifications. They are intentionally neutral
    -- state snapshots so shared adapters do not need to know C04's rules.
    hunt_changed = true,
    hunt_recovery = true,
    ultimate_expired = true,
}

function M.execute(adapter, actor, commands, context)
    local valid, missing = M.validate(adapter)
    if not valid then
        return false, 'adapter-missing:' .. table.concat(missing, ',')
    end

    context = context or {}
    for _, command in ipairs(commands or {}) do
        local command_type = command.type
        if command_type == 'damage' or command_type == 'ultimate_echo' then
            if type(command.coefficient) ~= 'number' then
                return false, 'invalid-damage-coefficient:' .. tostring(command_type)
            end
            adapter:deal_damage(actor, command, context)
        elseif command_type == 'break' then
            if type(command.break_value) ~= 'number' then
                return false, 'invalid-break-value'
            end
            adapter:apply_break(actor, command, context)
        elseif command_type == 'delayed_damage' then
            if type(command.coefficient) ~= 'number' then
                return false, 'invalid-damage-coefficient:delayed_damage'
            end
            adapter:schedule_damage(actor, command, context)
        elseif command_type == 'move' then
            adapter:move_safely(actor, command, context)
        elseif command_type == 'apply_modifier'
            or command_type == 'apply_modifier_to_targets'
            or command_type == 'apply_team_modifier'
            or command_type == 'remove_modifier'
            or command_type == 'refresh_modifier'
            or command_type == 'extend_modifier_once' then
            adapter:apply_effect(actor, command, context)
        elseif command_type == 'cooldown_delta' then
            adapter:change_cooldown(actor, command.skill_key, command.amount, context)
        elseif command_type == 'mobility_cooldown_reduction' then
            for _, skill_key in ipairs(command.skills) do
                adapter:change_cooldown(actor, skill_key, -command.amount, context)
            end
        elseif command_type == 'control' then
            adapter:apply_control(actor, command, context)
        elseif command_type == 'normal_combo_floor' then
            adapter:set_combo_floor(actor, command.stage, command.duration, context)
        elseif command_type == 'shouyi_trigger' or command_type == 'heal_and_guard' then
            adapter:heal_and_guard(actor, command, context)
        elseif state_event_types[command_type] then
            adapter:state_changed(actor, command, context)
        else
            return false, 'unknown-command:' .. tostring(command_type)
        end
    end
    return true
end

return M
