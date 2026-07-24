-- Deterministic offline fixture only. It is not a production proof, session, or storage provider.
local M = {}
local Provider = {}
Provider.__index = Provider

local function copy_table(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == 'table' then
            result[key] = copy_table(value)
        else
            result[key] = value
        end
    end
    return result
end

function M.new(seed)
    seed = seed or {}
    return setmetatable({
        actors = copy_table(seed.actors),
        handoffs = copy_table(seed.handoffs),
        entry_events = copy_table(seed.entry_events),
        observatory_events = copy_table(seed.observatory_events),
        admissions = copy_table(seed.admissions),
        completions = copy_table(seed.completions),
        cleanup_transitions = copy_table(seed.cleanup_transitions),
        cleanup_acks = copy_table(seed.cleanup_acks),
    }, Provider)
end

function Provider:resolve_current_actor(actor_id)
    return copy_table(self.actors[actor_id])
end

function Provider:resolve_yanluo_handoff(reference)
    return copy_table(self.handoffs[reference])
end

function Provider:resolve_entry_success(reference)
    return copy_table(self.entry_events[reference])
end

function Provider:resolve_observatory_success(reference)
    return copy_table(self.observatory_events[reference])
end

function Provider:resolve_lingxiao_admission(reference)
    return copy_table(self.admissions[reference])
end

function Provider:resolve_lingxiao_completion(reference)
    return copy_table(self.completions[reference])
end

function Provider:resolve_lingxiao_cleanup_transition(reference)
    return copy_table(self.cleanup_transitions[reference])
end

function Provider:resolve_lingxiao_cleanup_ack(reference)
    return copy_table(self.cleanup_acks[reference])
end

function Provider:set_actor(actor_id, actor)
    self.actors[actor_id] = copy_table(actor)
end

return M
