-- C04 only reports accepted final damage. Hunt marks, slow effects and UI
-- prediction are deliberately not public-Boss contribution events.
local M = {}

local Ledger = {}
Ledger.__index = Ledger

local valid_skills = {
    C04_F01 = true, C04_BASIC = true,
    C04_A01 = true, C04_A02 = true, C04_A03 = true, C04_A04 = true,
    C04_A05 = true, C04_A06 = true, C04_A07 = true, C04_A08 = true,
    C04_U01 = true,
}

local function present(value)
    return value ~= nil and value ~= ''
end

local function origin(event)
    return table.concat({
        tostring(event.combat_scope), tostring(event.session_instance_id), tostring(event.session_epoch),
        tostring(event.boss_instance_id), tostring(event.phase_id), tostring(event.target_id),
        tostring(event.target_lifecycle_id),
    }, ':')
end

function M.validate(event)
    if type(event) ~= 'table' then return false, 'invalid-contribution' end
    if event.kind ~= 'final_damage' then return false, 'invalid-contribution-kind' end
    for _, field in ipairs({
        'event_id', 'actor_id', 'lifecycle_id', 'boss_instance_id', 'phase_id',
        'target_id', 'target_lifecycle_id', 'skill_key',
    }) do
        if not present(event[field]) then return false, 'missing-contribution-field:' .. field end
    end
    if event.combat_scope ~= 'public' or event.session_instance_id ~= nil or event.session_epoch ~= nil then
        return false, 'private-or-invalid-contribution-scope'
    end
    if not valid_skills[event.skill_key] then return false, 'invalid-contribution-skill' end
    if type(event.value) ~= 'number' or event.value <= 0 then return false, 'invalid-contribution-value' end
    return true
end

function M.new()
    return setmetatable({ seen = {}, event_origin_index = {} }, Ledger)
end

function Ledger:accept(event)
    local ok, error_code = M.validate(event)
    if not ok then return false, error_code end
    local event_origin = origin(event)
    local existing_origin = self.event_origin_index[event.event_id]
    if existing_origin and existing_origin ~= event_origin then return false, 'contribution-origin-conflict' end
    local phase_key = table.concat({ tostring(event.boss_instance_id), tostring(event.phase_id), tostring(event.event_id) }, ':')
    if self.seen[phase_key] then return false, 'duplicate-contribution-event' end
    self.event_origin_index[event.event_id] = event_origin
    self.seen[phase_key] = true
    return true
end

function Ledger:clear_phase(boss_instance_id, phase_id)
    local prefix = tostring(boss_instance_id) .. ':' .. tostring(phase_id) .. ':'
    for key in pairs(self.seen) do
        if key:sub(1, #prefix) == prefix then self.seen[key] = nil end
    end
end

M.Ledger = Ledger
M.accept = Ledger.accept

return M
