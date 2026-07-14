-- custom-built: C03 public-boss contribution schema and phase-scoped dedupe.
local M = {}

local Ledger = {}
Ledger.__index = Ledger

local valid_kinds = {
    final_damage = true,
    actual_break = true,
    actual_protection = true,
    purge_mechanic = true,
}

local valid_skills = {
    C03_A01 = true,
    C03_A02 = true,
    C03_A03 = true,
    C03_A04 = true,
    C03_A05 = true,
    C03_A06 = true,
    C03_A07 = true,
    C03_A08 = true,
    C03_U01 = true,
}

local function present(value)
    return value ~= nil and value ~= ''
end

function M.validate(event)
    if type(event) ~= 'table' then return false, 'invalid-contribution' end
    if not valid_kinds[event.kind] then return false, 'invalid-contribution-kind' end
    for _, field in ipairs({ 'boss_instance_id', 'phase_id', 'actor_id', 'lifecycle_id', 'target_id', 'event_id' }) do
        if not present(event[field]) then return false, 'missing-contribution-field:' .. field end
    end

    if event.kind == 'purge_mechanic' then
        if event.skill_key ~= 'C03_A08' then return false, 'invalid-purge-skill' end
        if not present(event.mechanic_id) then return false, 'missing-contribution-field:mechanic_id' end
        if not present(event.alternative_resolution) then return false, 'missing-contribution-field:alternative_resolution' end
        return true
    end

    if not valid_skills[event.skill_key] then return false, 'invalid-contribution-skill' end
    if type(event.value) ~= 'number' or event.value <= 0 then return false, 'invalid-contribution-value' end
    return true
end

function M.new()
    return setmetatable({ seen = {} }, Ledger)
end

function Ledger:accept(event)
    local ok, error_code = M.validate(event)
    if not ok then return false, error_code end
    local key = table.concat({ tostring(event.boss_instance_id), tostring(event.phase_id), tostring(event.event_id) }, ':')
    if self.seen[key] then return false, 'duplicate-contribution-event' end
    self.seen[key] = true
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
