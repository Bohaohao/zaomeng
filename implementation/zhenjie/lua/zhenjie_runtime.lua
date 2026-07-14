local Core = require 'zhenjie_core'
local Skills = require 'zhenjie_skills'
local Effects = require 'zhenjie_effects'
local Contract = require 'zhenjie_adapter_contract'

local M = {}

local Runtime = {}
Runtime.__index = Runtime

function M.new(adapter)
    local valid, missing = Contract.validate(adapter)
    assert(valid, 'invalid Zhenjie adapter: ' .. table.concat(missing, ','))
    return setmetatable({ adapter = adapter, actors = {}, effects = Effects.new() }, Runtime)
end

local function state_or_error(runtime, actor_id)
    local state = runtime.actors[actor_id]
    if not state then
        return nil, 'unknown-actor'
    end
    return state
end

local function learned_rank(state, skill_key, requested_rank)
    local learned = state.ability_levels[skill_key] or 0
    local rank = requested_rank or learned
    if rank < 1 or rank > learned then
        return nil, 'skill-rank-not-learned'
    end
    return rank
end

local function prepare_context(state, context, now)
    context = context or {}
    context.now = now
    if context.lifecycle_id == nil then
        context.lifecycle_id = state.lifecycle_id
    end
    return context
end

local function track_effects(runtime, actor_id, commands, context)
    local now = context and context.now or 0
    for _, command in ipairs(commands or {}) do
        local handled, snapshots = Effects.execute(runtime.effects, actor_id, command, context, now)
        if handled then
            command.effect_snapshots = snapshots
        end
    end
end

local function dispatch(runtime, actor_id, commands, context)
    context = context or {}
    track_effects(runtime, actor_id, commands, context)
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
            if not applied then
                return false, apply_error
            end
        end
    end
    return true
end

local function flush_charge_updates(runtime, actor_id, state, now, context)
    for _, update in ipairs(Core.take_charge_updates(state, now)) do
        runtime.adapter:sync_ability_charge(actor_id, update, context or {})
    end
end

function Runtime:register(actor_id, options)
    assert(actor_id ~= nil, 'actor_id is required')
    assert(self.actors[actor_id] == nil, 'actor already registered')
    options = options or {}
    local state = Core.new(options)
    state.lifecycle_id = options.lifecycle_id
    self.actors[actor_id] = state
    Core.initialize_ability_charges(state)
    local context = options.context or {}
    context.current_hp = state.current_hp
    self.adapter:sync_hero_stats(actor_id, state.stats, context)
    flush_charge_updates(self, actor_id, state, options.now or 0, context)
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
    if not state then
        return false, error_code
    end
    state.ability_levels[skill_key] = rank
    flush_charge_updates(self, actor_id, state, now or 0, context)
    return true
end

function Runtime:set_level(actor_id, level, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return false, error_code
    end
    local stats = Core.set_level(state, level)
    context = prepare_context(state, context, context and context.now or 0)
    context.current_hp = state.current_hp
    self.adapter:sync_hero_stats(actor_id, stats, context)
    return true, stats
end

function Runtime:set_health(actor_id, current_hp)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return false, error_code
    end
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
    if not state then
        return { ok = false, error = error_code, commands = {} }
    end
    rank, error_code = learned_rank(state, skill_key, rank)
    if not rank then
        return { ok = false, error = error_code, commands = {} }
    end
    context = prepare_context(state, context, now)
    context.skill_key = skill_key
    local result = Skills.use(state, skill_key, rank, now, context)
    if not result.ok then
        return result
    end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    flush_charge_updates(self, actor_id, state, now, context)
    if not applied then
        return { ok = false, error = apply_error, commands = result.commands }
    end
    return result
end

function Runtime:commit_skill(actor_id, skill_key, rank, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return { ok = false, error = error_code, commands = {} }
    end
    rank, error_code = learned_rank(state, skill_key, rank)
    if not rank then
        return { ok = false, error = error_code, commands = {} }
    end
    context = prepare_context(state, context, now)
    context.skill_key = skill_key
    local result = Skills.commit_spender(state, skill_key, rank, now, context)
    if not result.ok then
        return result
    end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then
        return { ok = false, error = apply_error, commands = result.commands }
    end
    return result
end

function Runtime:confirm_skill_hit(actor_id, cast_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return { ok = false, error = error_code, commands = {} }
    end
    context = prepare_context(state, context, now)
    local result = Skills.confirm_spender_hit(state, cast_id, now, context)
    if not result.ok then
        return result
    end
    context.skill_key = result.skill_key
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then
        return { ok = false, error = apply_error, commands = result.commands }
    end
    return result
end

function Runtime:finish_skill_miss(actor_id, cast_id, now, reason, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return { ok = false, error = error_code, commands = {} }
    end
    context = prepare_context(state, context, now)
    local result = Skills.finish_spender_miss(state, cast_id, now, reason)
    if not result.ok then
        return result
    end
    context.skill_key = result.skill_key
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then
        return { ok = false, error = apply_error, commands = result.commands }
    end
    return result
end

function Runtime:on_damage_taken(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return { ok = false, error = error_code, commands = {} }
    end
    context = prepare_context(state, context, now)
    if context.current_hp ~= nil then
        Core.set_health(state, context.current_hp)
    end
    local result = Skills.trigger_guard_counter(state, now, context)
    if not result.ok then
        return result
    end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then
        return { ok = false, error = apply_error, commands = result.commands }
    end
    return result
end

function Runtime:on_move_finished()
    return true
end

function Runtime:normal_attack_hit()
    return true
end

function Runtime:activate_ultimate(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return { ok = false, error = error_code, commands = {} }
    end
    context = prepare_context(state, context, now)
    context.skill_key = 'C02_U01'
    local result = Skills.activate_ultimate(state, now)
    if not result.ok then
        return result
    end
    local applied, apply_error = dispatch(self, actor_id, result.commands, context)
    if not applied then
        return { ok = false, error = apply_error, commands = result.commands }
    end
    return result
end

function Runtime:tick(actor_id, now, context)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return false, error_code
    end
    context = prepare_context(state, context, now)
    local events = Core.tick(state, now)
    if #events > 0 then
        local applied, apply_error = dispatch(self, actor_id, events, context)
        if not applied then
            return false, apply_error
        end
    end
    local reconciled, reconcile_error = reconcile_shared_effects(self, actor_id, now, context)
    if not reconciled then
        return false, reconcile_error
    end
    flush_charge_updates(self, actor_id, state, now, context)
    return true
end

function Runtime:clear_transient(actor_id, now, reason)
    local state, error_code = state_or_error(self, actor_id)
    if not state then
        return false, error_code
    end
    Core.clear_transient(state, now)
    local cleanup = Effects.source_cleanup_commands(self.effects, actor_id)
    dispatch(self, actor_id, cleanup, { now = now, lifecycle_id = state.lifecycle_id })
    Effects.clear_unit(self.effects, actor_id)
    self.adapter:state_changed(actor_id, {
        type = 'transient_cleared', reason = reason, guard = 0, ultimate_gauge = 0, jieshi = false,
    }, { lifecycle_id = state.lifecycle_id })
    return true
end

return M
