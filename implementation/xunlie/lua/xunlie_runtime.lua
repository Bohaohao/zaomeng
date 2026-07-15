-- C04 runtime owns actor state and ensures that engine bridges can only
-- receive explicit, lifecycle-scoped commands.
local Core = require 'xunlie_core'
local Skills = require 'xunlie_skills'
local Effects = require 'xunlie_effects'
local Contract = require 'xunlie_adapter_contract'

local M = {}
local Runtime = {}
Runtime.__index = Runtime

local modifier_commands = {
    apply_modifier = true, apply_modifier_to_targets = true, apply_team_modifier = true,
    remove_modifier = true, refresh_modifier = true, extend_modifier_once = true,
}

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

local function same_session(expected, context)
    context = context or {}
    local scope = context.combat_scope or 'public'
    if scope ~= expected.combat_scope then return false end
    if scope == 'public' then return context.session_instance_id == nil and context.session_epoch == nil end
    return context.session_instance_id == expected.session_instance_id and context.session_epoch == expected.session_epoch
end

local function prepare_context(state, context, now)
    context = context or {}
    context.now = now
    context.lifecycle_id = context.lifecycle_id == nil and state.lifecycle_id or context.lifecycle_id
    context.combat_scope = context.combat_scope or state.session.combat_scope
    if context.combat_scope == 'private_session' then
        context.session_instance_id = context.session_instance_id or state.session.session_instance_id
        context.session_epoch = context.session_epoch or state.session.session_epoch
    end
    return context
end

local function has_explicit_effect_targets(command, context)
    if command.target_scope == 'self' then return true end
    if command.target_scope == 'primary' then return command.target_id ~= nil or context.primary_target_id ~= nil end
    if command.target_scope == 'selected' then
        return command.target_ids ~= nil or command.targets ~= nil or context.selected_target_ids ~= nil or context.selected_targets ~= nil
    end
    if command.target_scope == 'explicit' then return command.target_id ~= nil or command.target_ids ~= nil or command.target ~= nil or command.targets ~= nil end
    return false
end

local function track_effects(runtime, actor_id, commands, context)
    for _, command in ipairs(commands or {}) do
        if modifier_commands[command.type] then
            if not has_explicit_effect_targets(command, context or {}) then return false, 'implicit-effect-targets' end
            local handled, snapshots = Effects.execute(runtime.effects, actor_id, command, context, context.now)
            if handled then command.effect_snapshots = snapshots end
        end
    end
    return true
end

local function dispatch(runtime, actor_id, commands, context)
    local tracked, error_code = track_effects(runtime, actor_id, commands, context)
    if not tracked then return false, error_code end
    return Contract.execute(runtime.adapter, actor_id, commands, context)
end

local function source_ids(actor_id)
    return {
        actor_id, tostring(actor_id) .. ':C04_A05', tostring(actor_id) .. ':C04_A08',
        tostring(actor_id) .. ':wind', tostring(actor_id) .. ':a06',
    }
end

local function cleanup_effects(runtime, actor_id, context)
    for _, source_id in ipairs(source_ids(actor_id)) do
        local commands = Effects.source_cleanup_commands(runtime.effects, source_id)
        if #commands > 0 then dispatch(runtime, actor_id, commands, context) end
        Effects.clear_source(runtime.effects, source_id)
    end
    Effects.clear_unit(runtime.effects, actor_id)
end

function M.new(adapter)
    local valid, missing = Contract.validate(adapter)
    assert(valid, 'invalid Xunlie adapter: ' .. table.concat(missing, ','))
    return setmetatable({ adapter = adapter, actors = {}, effects = Effects.new() }, Runtime)
end

function Runtime:register(actor_id, options)
    assert(actor_id ~= nil, 'actor_id is required')
    assert(self.actors[actor_id] == nil, 'actor already registered')
    options = options or {}
    assert(options.lifecycle_id ~= nil, 'lifecycle_id is required')
    local scope = options.combat_scope or 'public'
    assert(scope == 'public' or scope == 'private_session', 'invalid combat_scope')
    if scope == 'public' then
        assert(options.session_instance_id == nil and options.session_epoch == nil, 'public registrations cannot carry a session')
    else
        assert(options.session_instance_id ~= nil and options.session_epoch ~= nil, 'private registrations require a session')
    end
    local state = Core.new(options)
    state.lifecycle_id = options.lifecycle_id
    state.session = {
        combat_scope = options.combat_scope or 'public',
        session_instance_id = options.session_instance_id,
        session_epoch = options.session_epoch,
    }
    self.actors[actor_id] = state
    local context = prepare_context(state, options.context or {}, options.now or 0)
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
    return dispatch(self, actor_id, {{
        type = 'hunt_changed', resource_enabled = Core.is_resource_enabled(state),
        ultimate_gauge = state.ultimate_gauge, marks = 0, locked = false,
    }}, context)
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

function Runtime:commit_skill(actor_id, skill_key, rank, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    rank, error_code = learned_rank(state, skill_key, rank)
    if not rank then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    if context.lifecycle_id ~= state.lifecycle_id then return { ok = false, error = 'stale-lifecycle', commands = {} } end
    if not same_session(state.session, context) then return { ok = false, error = 'stale-session', commands = {} } end
    context.actor_id, context.skill_key = actor_id, skill_key
    local result = Skills.commit_skill(state, skill_key, rank, now, context)
    if not result.ok then return result end
    context.cast_id, context.cast_snapshot = result.cast_id, result.cast_snapshot
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:begin_cast(...)
    return self:commit_skill(...)
end

local function validate_hit_context(state, context, event)
    if type(context) ~= 'table' or context.lifecycle_id == nil then return false, 'lifecycle-id-required' end
    if context.lifecycle_id ~= state.lifecycle_id then return false, 'stale-lifecycle' end
    if not same_session(state.session, context) then return false, 'stale-session' end
    if type(event) ~= 'table' or event.lifecycle_id == nil or event.lifecycle_id ~= state.lifecycle_id then return false, 'stale-hit-lifecycle' end
    if event.combat_scope ~= context.combat_scope then return false, 'stale-hit-session' end
    if context.combat_scope == 'private_session'
        and (event.session_instance_id ~= context.session_instance_id or event.session_epoch ~= context.session_epoch) then
        return false, 'stale-hit-session'
    end
    return true
end

function Runtime:confirm_skill_hit(actor_id, cast_id, now, event, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    local valid, hit_error = validate_hit_context(state, context, event)
    if not valid then return { ok = false, error = hit_error, commands = {} } end
    context.actor_id, context.cast_id = actor_id, cast_id
    local result = Skills.confirm_skill_hit(state, cast_id, now, event)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:confirm_hit(...)
    return self:confirm_skill_hit(...)
end

function Runtime:begin_normal_attack(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    if context.lifecycle_id ~= state.lifecycle_id or not same_session(state.session, context) then
        return { ok = false, error = 'stale-context', commands = {} }
    end
    context.actor_id = actor_id
    return Skills.begin_normal_attack(state, now, context)
end

function Runtime:confirm_normal_attack(actor_id, cast_id, now, event, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    local valid, hit_error = validate_hit_context(state, context, event)
    if not valid then return { ok = false, error = hit_error, commands = {} } end
    local result = Skills.confirm_normal_attack(state, cast_id, now, event)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:confirm_safe_landing(actor_id, cast_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    if context.lifecycle_id ~= state.lifecycle_id or not same_session(state.session, context) then
        return { ok = false, error = 'stale-context', commands = {} }
    end
    local result = Skills.confirm_safe_landing(state, cast_id, now)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:finalize_phase(actor_id, cast_id, phase, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    if context.lifecycle_id ~= state.lifecycle_id or not same_session(state.session, context) then
        return { ok = false, error = 'stale-context', commands = {} }
    end
    local result = Skills.finalize_phase(state, cast_id, phase, now)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:finalize_cast(actor_id, cast_id, now, reason, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    if context.lifecycle_id ~= state.lifecycle_id or not same_session(state.session, context) then
        return { ok = false, error = 'stale-context', commands = {} }
    end
    local result = Skills.finalize_cast(state, cast_id, now, reason)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:finish_skill_miss(actor_id, cast_id, now, reason, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    if context.lifecycle_id ~= state.lifecycle_id or not same_session(state.session, context) then
        return { ok = false, error = 'stale-context', commands = {} }
    end
    local result = Skills.finish_skill_miss(state, cast_id, now, reason)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:activate_ultimate(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return { ok = false, error = error_code, commands = {} } end
    context = prepare_context(state, context, now)
    if context.lifecycle_id ~= state.lifecycle_id or not same_session(state.session, context) then
        return { ok = false, error = 'stale-context', commands = {} }
    end
    context.actor_id, context.skill_key = actor_id, 'C04_U01'
    local result = Skills.activate_ultimate(state, now, context)
    if not result.ok then return result end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then return { ok = false, error = apply_error, commands = result.commands } end
    return result
end

function Runtime:tick(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    context = prepare_context(state, context, now)
    if context.lifecycle_id ~= state.lifecycle_id or not same_session(state.session, context) then return false, 'stale-context' end
    local commands = Skills.tick(state, now)
    if #commands == 0 then return true end
    return dispatch(self, actor_id, commands, context)
end

function Runtime:clear_transient(actor_id, now, reason)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    local context = prepare_context(state, { lifecycle_id = state.lifecycle_id }, now)
    cleanup_effects(self, actor_id, context)
    local event = Core.clear_transient(state, now)
    return dispatch(self, actor_id, { event }, context)
end

function Runtime:invalidate_lifecycle(actor_id, next_lifecycle_id, now, reason)
    local state, error_code = state_or_error(self, actor_id)
    if not state then return false, error_code end
    local previous = state.lifecycle_id
    self:clear_transient(actor_id, now, reason)
    state.lifecycle_id = next_lifecycle_id
    return true, previous
end

function Runtime:remove(actor_id)
    local state = self.actors[actor_id]
    if not state then return false end
    cleanup_effects(self, actor_id, prepare_context(state, { lifecycle_id = state.lifecycle_id }, 0))
    self.actors[actor_id] = nil
    return true
end

return M
