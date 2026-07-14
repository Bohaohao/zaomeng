-- custom-built: C03 runtime owns actors and delegates all engine work through
-- the explicit adapter contract.
local Core = require 'chiming_core'
local Skills = require 'chiming_skills'
local Effects = require 'chiming_effects'
local Contract = require 'chiming_adapter_contract'

local M = {}
local Runtime = {}
Runtime.__index = Runtime

function M.new(adapter)
    local valid, missing = Contract.validate(adapter)
    assert(valid, 'invalid Chiming adapter: ' .. table.concat(missing, ','))
    return setmetatable({ adapter = adapter, actors = {}, effects = Effects.new() }, Runtime)
end

local function state_or_error(runtime, actor_id)
    local state = runtime.actors[actor_id]
    if not state then return nil, 'unknown-actor' end
    return state
end

local function learned_rank(state, skill_key, requested_rank)
    local learned = state.ability_levels[skill_key] or 0
    local rank = requested_rank or learned
    if rank < 1 or rank > learned then return nil, 'skill-rank-not-learned' end
    return rank
end

local function prepare_context(state, context, now)
    context = context or {}
    context.now = now
    if context.lifecycle_id == nil then context.lifecycle_id = state.lifecycle_id end
    return context
end

local modifier_commands = {
    apply_modifier = true,
    apply_modifier_to_targets = true,
    apply_team_modifier = true,
    remove_modifier = true,
    refresh_modifier = true,
    extend_modifier_once = true,
}

local function explicit_effect_snapshot(command, context)
    local scope = command.target_scope
    if scope == 'self' then return true end
    if scope == 'primary' then return command.target_id ~= nil or command.target ~= nil or context.primary_target_id ~= nil end
    if scope == 'selected' then
        return command.target_id ~= nil or command.target ~= nil or command.target_ids ~= nil or command.targets ~= nil
            or context.selected_target_ids ~= nil or context.selected_targets ~= nil
    end
    if scope == 'team' then
        return command.target_id ~= nil or command.target ~= nil or command.target_ids ~= nil or command.targets ~= nil
            or context.team_target_ids ~= nil or context.team_targets ~= nil
    end
    if scope == 'explicit' then
        return command.target_id ~= nil or command.target ~= nil or command.target_ids ~= nil or command.targets ~= nil
            or command.explicit_target_ids ~= nil or command.explicit_targets ~= nil
    end
    return false
end

local function track_effects(runtime, actor_id, commands, context)
    local now = context and context.now or 0
    for _, command in ipairs(commands or {}) do
        if modifier_commands[command.type] and not explicit_effect_snapshot(command, context or {}) then
            return false, 'implicit-effect-targets'
        end
        local handled, snapshots = Effects.execute(runtime.effects, actor_id, command, context, now)
        if handled then command.effect_snapshots = snapshots end
    end
    return true
end

local function dispatch(runtime, actor_id, commands, context)
    context = context or {}
    local tracked, track_error = track_effects(runtime, actor_id, commands, context)
    if not tracked then return false, track_error end
    return Contract.execute(runtime.adapter, actor_id, commands, context)
end

local function reconcile_shared_effects(runtime, actor_id, now, context)
    local changes = Effects.collect_shared_changes(runtime.effects, now)
    for _, change in ipairs(changes) do
        if change.unit_ref then
            local snapshot = change.current
            local source_id = (snapshot and snapshot.source_id)
                or (change.previous and change.previous.source_id)
                or actor_id
            local command = {
                type = snapshot and 'apply_modifier' or 'remove_modifier',
                key = change.modifier_key,
                target_scope = 'explicit',
                target_id = change.unit_id,
                target = change.unit_ref,
                target_ids = { change.unit_id },
                targets = { change.unit_ref },
                source_id = source_id,
            }
            if snapshot then
                command.duration = snapshot.expires_at and math.max(0, snapshot.expires_at - now) or nil
                command.payload = snapshot.payload
            end
            local applied, apply_error = Contract.execute(runtime.adapter, source_id, { command }, context or { now = now })
            if not applied then return false, apply_error end
        end
    end
    return true
end

function Runtime:register(actor_id, options)
    assert(actor_id ~= nil, 'actor_id is required')
    assert(self.actors[actor_id] == nil, 'actor already registered')
    options = options or {}
    local state = Core.new(options)
    state.lifecycle_id = options.lifecycle_id
    self.actors[actor_id] = state
    local context = options.context or {}
    context.current_hp = state.current_hp
    self.adapter:sync_hero_stats(actor_id, state.stats, context)
    return state
end

function Runtime:get_state(actor_id)
    return self.actors[actor_id]
end

function Runtime:get_effect(unit_id, modifier_key, now, source_id)
    return Effects.get(self.effects, unit_id, modifier_key, now, source_id)
end

function Runtime:set_ability_level(actor_id, skill_key, rank, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    Core.set_ability_level(state, skill_key, rank)
    context = prepare_context(state, context, now or 0)
    local command = {
        type = 'seal_changed', seals = state.seals, mingtai = Core.is_mingtai(state),
        resource_enabled = Core.is_resource_enabled(state), ultimate_gauge = state.ultimate_gauge,
    }
    return dispatch(self, actor_id, { command }, context)
end

function Runtime:set_level(actor_id, level, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    local stats = Core.set_level(state, level)
    context = prepare_context(state, context, context and context.now or 0)
    context.current_hp = state.current_hp
    self.adapter:sync_hero_stats(actor_id, stats, context)
    return true, stats
end

function Runtime:set_health(actor_id, current_hp)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    Core.set_health(state, current_hp)
    return true
end

function Runtime:remove(actor_id)
    local state = self.actors[actor_id]
    local cleanup = Effects.source_cleanup_commands(self.effects, actor_id)
    dispatch(self, actor_id, cleanup, { now = 0, lifecycle_id = state and state.lifecycle_id })
    Effects.clear_unit(self.effects, actor_id)
    self.actors[actor_id] = nil
end

function Runtime:use_skill(actor_id, skill_key, rank, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    rank, error_code = learned_rank(state, skill_key, rank)
    if not rank then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    context.actor_id = actor_id
    context.skill_key = skill_key
    local result = Skills.use(state, skill_key, rank, now, context)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:commit_skill(actor_id, skill_key, rank, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    rank, error_code = learned_rank(state, skill_key, rank)
    if not rank then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    context.actor_id = actor_id
    context.skill_key = skill_key
    local result = Skills.commit_skill(state, skill_key, rank, now, context)
    if not result.ok then return result end
    context.cast_id = result.cast_id
    context.cast_snapshot = result.cast_snapshot
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

-- Names matching the bridge contract. The older commit/finish entry points
-- stay available for the two existing profession packages.
function Runtime:begin_cast(actor_id, skill_key, rank, now, snapshot)
    return self:commit_skill(actor_id, skill_key, rank, now, snapshot)
end

function Runtime:confirm_skill_hit(actor_id, cast_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    if type(context) ~= 'table' or context.lifecycle_id == nil then
        return { ok = false, error = 'lifecycle-id-required', commands = {} }
    end
    if state.lifecycle_id ~= nil and context.lifecycle_id ~= state.lifecycle_id then
        return { ok = false, error = 'stale-lifecycle', commands = {} }
    end
    context = prepare_context(state, context, now)
    context.actor_id = actor_id
    context.cast_id = cast_id
    local result = Skills.confirm_skill_hit(state, cast_id, now, context)
    if not result.ok then return result end
    context.skill_key = result.skill_key or context.skill_key
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:finish_skill_miss(actor_id, cast_id, now, reason, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    context.actor_id = actor_id
    context.cast_id = cast_id
    local result = Skills.finish_skill_miss(state, cast_id, now, reason)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:finalize_cast(actor_id, cast_id, now, reason, context)
    return self:finish_skill_miss(actor_id, cast_id, now, reason, context)
end

function Runtime:on_damage_taken(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    context.actor_id = actor_id
    if context.current_hp ~= nil then Core.set_health(state, context.current_hp) end
    local result = Skills.on_damage_taken(state, now, context)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:activate_ultimate(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    context.actor_id = actor_id
    context.skill_key = 'C03_U01'
    local result = Skills.activate_ultimate(state, now)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:tick(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    context = prepare_context(state, context, now)
    context.actor_id = actor_id
    local commands = Skills.tick(state, now)
    if #commands > 0 then
        local applied, apply_error = dispatch(self, actor_id, commands, context)
        if not applied then return false, apply_error end
    end
    return reconcile_shared_effects(self, actor_id, now, context)
end

function Runtime:clear_transient(actor_id, now, reason)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    local event = Core.clear_transient(state, now)
    local cleanup = Effects.source_cleanup_commands(self.effects, actor_id)
    dispatch(self, actor_id, cleanup, { now = now, lifecycle_id = state.lifecycle_id })
    Effects.clear_unit(self.effects, actor_id)
    dispatch(self, actor_id, { event }, { now = now, lifecycle_id = state.lifecycle_id, reason = reason })
    return true
end

function Runtime:invalidate_lifecycle(actor_id, next_lifecycle_id, now, reason)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    local previous_lifecycle_id = state.lifecycle_id
    self:clear_transient(actor_id, now, reason)
    state.lifecycle_id = next_lifecycle_id
    return true, previous_lifecycle_id
end

return M
