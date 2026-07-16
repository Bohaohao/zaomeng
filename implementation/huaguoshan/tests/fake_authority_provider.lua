local M = {}

local function copy_table(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

function M.new(options)
    options = options or {}
    local provider = {
        now = options.now or 0,
        watermark = options.watermark or 0,
        completion_ticks = {},
        rejected_event_ids = {},
        rejected_operations = {},
        proof_overrides = {},
        calls = {},
    }

    function provider:set_now(now)
        self.now = now
    end

    function provider:set_watermark(watermark)
        self.watermark = watermark
    end

    function provider:set_completion(event_id, completed_tick)
        self.completion_ticks[event_id] = completed_tick
    end

    function provider:reject_event(event_id, rejected)
        self.rejected_event_ids[event_id] = rejected ~= false
    end

    function provider:reject_operation(operation, rejected)
        self.rejected_operations[operation] = rejected ~= false
    end

    function provider:set_proof_override(operation, field, value)
        local overrides = self.proof_overrides[operation] or {}
        self.proof_overrides[operation] = overrides
        overrides[field] = value
    end

    function provider:verify(operation, context)
        self.calls[#self.calls + 1] = { operation = operation, context = copy_table(context) }
        if self.rejected_operations[operation]
            or (context.event_id and self.rejected_event_ids[context.event_id]) then
            return false
        end

        local proof = copy_table(context)
        if operation == 'public_boss_contribution' then
            proof.actor_alive = true
            proof.boss_target_current = true
        elseif operation == 'public_boss_action_begin' then
            proof.observed_tick = self.now
            proof.actor_alive = true
            proof.within_interaction_area = true
            proof.boss_target_current = true
            proof.interaction_unit_current = true
            proof.anchor_in_safe_line = true
            proof.anchor_outside_vortex_core = true
        elseif operation == 'public_boss_action_complete' then
            proof.completed_tick = self.completion_ticks[context.event_id]
            if proof.completed_tick == nil then return false end
            proof.actor_alive = true
            proof.within_interaction_area = true
            proof.completed_reading = true
            proof.reading_continuous = true
            proof.boss_target_current = true
            proof.interaction_unit_current = true
        elseif operation == 'public_boss_apply_water_chain' then
            proof.boss_target_current = true
        elseif operation == 'public_boss_phase_marker'
            or operation == 'public_boss_phase_transition'
            or operation == 'public_boss_finalization'
            or operation == 'public_boss_action_window_close' then
            proof.watermark_tick = self.watermark
        elseif operation == 'public_boss_watermark' then
            proof.watermark_tick = self.watermark
        elseif operation == 'public_trace_action_begin' then
            proof.observed_tick = self.now
            proof.actor_alive = true
            proof.within_interaction_area = true
            proof.target_current = true
        elseif operation == 'public_trace_action_complete' then
            proof.completed_tick = self.completion_ticks[context.event_id]
            if proof.completed_tick == nil then return false end
            proof.actor_alive = true
            proof.within_interaction_area = true
            proof.completed_reading = true
            proof.reading_continuous = true
            proof.target_current = true
        elseif operation == 'public_trace_finish' then
            proof.observed_tick = self.now
        elseif operation == 'public_trace_watermark' then
            proof.watermark_tick = self.watermark
        else
            return false
        end

        for field, value in pairs(self.proof_overrides[operation] or {}) do proof[field] = value end
        return true, proof
    end

    return provider
end

return M
