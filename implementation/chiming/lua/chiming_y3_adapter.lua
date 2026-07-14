-- custom-built: the only C03 module that calls public Y3 APIs. It mirrors the
-- C01/C02 lifecycle rules and keeps all target ownership explicit.
local ControlLedger = require 'chiming_y3_control_ledger'
local TargetContract = require 'chiming_target_contract'
local Config = require 'chiming_config'

local M = {}
local Adapter = {}
Adapter.__index = Adapter

local function clamp_min(value, minimum)
    return value < minimum and minimum or value
end

local function percent(value)
    return value * 100
end

local function append(list, value)
    list[#list + 1] = value
end

function M.new(options)
    options = options or {}
    assert(_G.y3, 'chiming_y3_adapter must be loaded inside Y3')
    assert(type(options.unit_by_actor) == 'function', 'unit_by_actor callback is required')
    return setmetatable({
        options = options,
        ability_ids = options.ability_ids or {},
        ability_types = options.ability_types or {},
        modifier_ids = options.modifier_ids or {},
        distance_scale = options.distance_scale or 100,
        dash_speed = options.dash_speed or 1200,
        effects = {},
        reduction_applied = {},
        actor_timers = {},
        temporary_speed = {},
        buff_instances = {},
        break_ledger = {},
        next_effect_generation = 0,
        lifecycle_resolver = nil,
        contribution_sink = nil,
        controls = ControlLedger.new(),
    }, Adapter)
end

function Adapter:set_lifecycle_resolver(resolver)
    assert(type(resolver) == 'function', 'lifecycle resolver must be a function')
    self.lifecycle_resolver = resolver
end

function Adapter:set_contribution_sink(sink)
    assert(sink == nil or type(sink) == 'function', 'contribution sink must be a function or nil')
    self.contribution_sink = sink
end

function Adapter:_is_lifecycle_current(actor, lifecycle_id)
    if lifecycle_id == nil or self.lifecycle_resolver == nil then return true end
    return self.lifecycle_resolver(actor, lifecycle_id) == true
end

function Adapter:_timer_bucket(actor, lifecycle_id, create)
    local by_actor = self.actor_timers[actor]
    if not by_actor and create then by_actor = {}; self.actor_timers[actor] = by_actor end
    if not by_actor then return nil end
    local key = lifecycle_id == nil and '__unbound__' or tostring(lifecycle_id)
    local bucket = by_actor[key]
    if not bucket and create then bucket = {}; by_actor[key] = bucket end
    return bucket, key
end

function Adapter:_track_timer(actor, lifecycle_id, timer)
    local bucket = self:_timer_bucket(actor, lifecycle_id, true)
    bucket[timer] = true
end

function Adapter:_untrack_timer(actor, lifecycle_id, timer)
    local bucket, key = self:_timer_bucket(actor, lifecycle_id, false)
    if not bucket then return end
    bucket[timer] = nil
    if next(bucket) == nil then
        local by_actor = self.actor_timers[actor]
        by_actor[key] = nil
        if next(by_actor) == nil then self.actor_timers[actor] = nil end
    end
end

function Adapter:_wait_for_actor(actor, lifecycle_id, delay, callback, description)
    local timer
    timer = y3.timer.wait(delay, function()
        self:_untrack_timer(actor, lifecycle_id, timer)
        if self:_is_lifecycle_current(actor, lifecycle_id) then callback() end
    end, description)
    self:_track_timer(actor, lifecycle_id, timer)
    return timer
end

function Adapter:cancel_actor_timers(actor, lifecycle_id)
    local by_actor = self.actor_timers[actor]
    if by_actor then
        local keys = {}
        for key in pairs(by_actor) do
            if lifecycle_id == nil or key == tostring(lifecycle_id) then append(keys, key) end
        end
        for _, key in ipairs(keys) do
            for timer in pairs(by_actor[key]) do timer:remove() end
            by_actor[key] = nil
        end
        if next(by_actor) == nil then self.actor_timers[actor] = nil end
    end
    if type(self.controls.release_by_source) == 'function' then
        self.controls:release_by_source(actor, lifecycle_id)
    end
    for key, entry in pairs(self.break_ledger) do
        if entry.actor == actor and (lifecycle_id == nil or entry.lifecycle_id == lifecycle_id) then
            self.break_ledger[key] = nil
        end
    end
end

function Adapter:_unit(reference)
    if type(reference) == 'table' and type(reference.is_exist) == 'function' then return reference end
    return self.options.unit_by_actor(reference)
end

function Adapter:_ability(actor, skill_key)
    local unit = self:_unit(actor)
    local ability_id = self.ability_ids[skill_key]
    if not unit or not ability_id then return nil end
    return unit:find_ability(self.ability_types[skill_key] or '英雄', ability_id)
end

local function map_value(map, key)
    if type(map) ~= 'table' then return nil end
    return map[key] or map[tostring(key)]
end

local function append_target(entries, seen, id, ref)
    if id == nil or ref == nil or seen[id] then return end
    seen[id] = true
    append(entries, { id = id, ref = ref })
end

function Adapter:_targets(actor, command, context)
    context = context or {}
    local scope = command.target_scope
    if scope ~= 'self' and scope ~= 'primary' and scope ~= 'selected'
        and scope ~= 'team' and scope ~= 'explicit' then
        return {}
    end

    local source = context.unit or self:_unit(actor)
    local source_id = TargetContract.id_of(source, actor)
    local refs = command.target_refs_by_id or command.target_refs or context.target_refs_by_id
        or context.target_refs or context.units_by_id or {}
    local entries, seen = {}, {}
    local function add(id, ref)
        append_target(entries, seen, id, ref or map_value(refs, id))
    end
    local function add_many(ids, units)
        for index, id in ipairs(ids or {}) do add(id, units and units[index]) end
        if #(ids or {}) == 0 then
            for _, unit in ipairs(units or {}) do add(TargetContract.id_of(unit), unit) end
        end
    end

    if scope == 'self' then
        add(source_id, source)
    elseif scope == 'primary' then
        -- Primary is a cast-time lock; generic candidate lists may never fill it.
        add(context.primary_target_id, context.primary_target_ref)
    elseif scope == 'selected' then
        add_many(command.target_ids or context.selected_target_ids, command.targets or context.selected_targets)
    elseif scope == 'team' then
        add_many(command.target_ids or context.team_target_ids, command.targets or context.team_targets)
    else -- explicit
        if command.target_id ~= nil or command.target ~= nil then
            add(command.target_id or TargetContract.id_of(command.target), command.target)
        else
            add_many(command.target_ids or command.explicit_target_ids, command.targets or command.explicit_targets)
        end
    end

    if scope == 'team' then
        local filtered = {}
        for _, entry in ipairs(entries) do
            if entry.id ~= source_id then append(filtered, entry) end
        end
        entries = filtered
    end
    command.resolved_targets, command.resolved_target_ids, command.resolved_target_refs = entries, {}, {}
    local targets = {}
    for index, entry in ipairs(entries) do
        command.resolved_target_ids[index] = entry.id
        command.resolved_target_refs[index] = entry.ref
        append(targets, entry.ref)
    end
    return targets
end

function Adapter:_effect_snapshot(command, target_id)
    local snapshot = command.effect_snapshots and command.effect_snapshots[tostring(target_id)]
    if not snapshot then return nil, nil end
    if snapshot.aggregate and snapshot.aggregate.payload then return snapshot.aggregate.payload, snapshot.aggregate.expires_at end
    if snapshot.source then return snapshot.source.payload, snapshot.source.expires_at end
    return nil, nil
end

function Adapter:sync_hero_stats(actor, stats, context)
    local unit = self:_unit(actor) or (context and context.unit)
    if not unit or not unit:is_exist() then return end
    unit:set_attr('最大生命', stats.hp_max, '基础')
    unit:set_attr('最大魔法', stats.mp_max, '基础')
    unit:set_attr('物理攻击', stats.attack_physical, '基础')
    unit:set_attr('法术攻击', stats.attack_magic, '基础')
    unit:set_attr('物理防御', stats.defense_physical, '基础')
    unit:set_attr('法术防御', stats.defense_magic, '基础')
    unit:set_attr('暴击率', percent(stats.critical_chance), '基础')
    unit:set_attr('暴击伤害', percent(stats.critical_damage), '基础')
    unit:set_attr('命中率', percent(stats.hit_rate), '基础')
    unit:set_attr('躲避率', percent(stats.dodge_rate), '基础')
    unit:set_attr('冷却缩减', percent(stats.cooldown_reduction), '基础')
    unit:set_attr('移动速度', stats.move_speed, '基础')
    unit:set_attr('攻击速度', stats.attack_speed, '基础')
    unit:set_attr('攻击间隔', stats.attack_interval, '基础')
    if context and context.current_hp ~= nil then unit:set_hp(context.current_hp) end
end

function Adapter:sync_ability_charge(actor, update)
    local ability = self:_ability(actor, update.skill_key)
    if not ability then return end
    ability:set_stack(update.current)
    ability:set_charge_time(update.remaining)
end

function Adapter:_target_metadata(command, context, target)
    local target_id = TargetContract.id_of(target)
    local metadata = map_value(command.target_meta_by_id, target_id)
        or map_value(context and context.target_meta_by_id, target_id)
        or {}
    local rank = metadata.rank
    if rank == nil and type(self.options.target_rank) == 'function' then
        rank = self.options.target_rank(target, command, context)
    end
    if rank ~= 'normal' and rank ~= 'elite' and rank ~= 'boss' then rank = 'unknown' end
    metadata.rank = rank
    return metadata
end

function Adapter:_break_key(actor, target, command, context)
    local lifecycle_id = command.lifecycle_id or (context and context.lifecycle_id)
    local cast_id = command.cast_id or (context and context.cast_id) or (context and context.now)
    local event_key = command.break_event_key
    if lifecycle_id == nil or cast_id == nil or event_key == nil then return nil end
    return table.concat({
        tostring(actor), tostring(lifecycle_id), tostring(cast_id),
        tostring(TargetContract.id_of(target)), tostring(event_key),
    }, ':')
end

function Adapter:_can_apply_break(target, command, context)
    if type(command.break_value) ~= 'number' or command.break_value <= 0 then return false end
    if command.break_scope ~= 'boss_only' and command.break_scope ~= 'boss_confirmed' then return false end
    return self:_target_metadata(command, context, target).rank == 'boss'
end

function Adapter:_emit_boss_contribution(item)
    local sink = self.contribution_sink or self.options.report_boss_contribution
    if type(sink) == 'function' then sink(item) end
end

function Adapter:_report_break(actor, target, value, command, context, result)
    if result ~= true and (type(result) ~= 'table' or result.actual_break ~= true) then return end
    local boss = type(self.options.resolve_boss_context) == 'function'
        and self.options.resolve_boss_context(target, command, context) or nil
    if not boss or boss.boss_instance_id == nil or boss.phase_id == nil or boss.event_id == nil then return end
    local actual = type(result) == 'table' and result.value or value
    if type(actual) ~= 'number' or actual <= 0 then return end
    self:_emit_boss_contribution({
        kind = 'actual_break', boss_instance_id = boss.boss_instance_id, phase_id = boss.phase_id,
        actor_id = actor, lifecycle_id = command.lifecycle_id or (context and context.lifecycle_id),
        target_id = TargetContract.id_of(target), skill_key = command.skill_key or (context and context.skill_key),
        event_id = boss.event_id, value = actual,
    })
end

function Adapter:_attempt_break(actor, source, target, command, context)
    if not self:_can_apply_break(target, command, context) or type(self.options.apply_break) ~= 'function' then return false end
    local key = self:_break_key(actor, target, command, context)
    if not key or self.break_ledger[key] then return false end
    self.break_ledger[key] = {
        actor = actor,
        lifecycle_id = command.lifecycle_id or (context and context.lifecycle_id),
    }
    local result = self.options.apply_break(source, target, command.break_value, command, context)
    self:_report_break(actor, target, command.break_value, command, context, result)
    return true
end

function Adapter:deal_damage(actor, command, context)
    local source = self:_unit(actor)
    if not source or not source:is_exist() then return end
    local ability = self:_ability(actor, (context and context.skill_key) or command.skill_key)
    local attack = source:get_attr('法术攻击')
    for _, target in ipairs(self:_targets(actor, command, context)) do
        if target and target:is_exist() then
            source:damage({
                target = target, type = '法术', damage = attack * command.coefficient,
                ability = ability, common_attack = false, no_miss = context and context.no_miss or false,
            })
            self:_attempt_break(actor, source, target, command, context)
        end
    end
end

function Adapter:apply_break(actor, command, context)
    if type(self.options.apply_break) ~= 'function' then return end
    local source = self:_unit(actor)
    if not source or not source:is_exist() then return end
    for _, target in ipairs(self:_targets(actor, command, context)) do
        if target and target:is_exist() then
            self:_attempt_break(actor, source, target, command, context)
        end
    end
end

local function copy_context(context)
    local copied = {}
    for key, value in pairs(context or {}) do copied[key] = value end
    return copied
end

function Adapter:_pulse_context(actor, command, context)
    if type(self.options.resolve_pulse_targets) ~= 'function' then return nil end
    local result = self.options.resolve_pulse_targets(actor, command.pulse_key, command, context)
    if type(result) ~= 'table' then return nil end
    local units = result.targets or result.units or result.selected_targets or result
    local ids = result.target_ids or result.ids or result.selected_target_ids or {}
    local pulse_context = copy_context(context)
    pulse_context.selected_targets, pulse_context.selected_target_ids = {}, {}
    pulse_context.target_refs_by_id = copy_context(context and context.target_refs_by_id or {})
    pulse_context.target_meta_by_id = copy_context(context and context.target_meta_by_id or {})
    local seen = {}
    local function add(target_id, target)
        target_id = target_id or TargetContract.id_of(target)
        if target_id == nil or target == nil or seen[target_id] then return end
        if type(target.is_exist) == 'function' and not target:is_exist() then return end
        seen[target_id] = true
        append(pulse_context.selected_target_ids, target_id)
        append(pulse_context.selected_targets, target)
        pulse_context.target_refs_by_id[target_id] = target
        local metadata = result.target_meta_by_id and map_value(result.target_meta_by_id, target_id) or nil
        if metadata then pulse_context.target_meta_by_id[target_id] = metadata end
    end
    for index, target_id in ipairs(ids) do add(target_id, units[index]) end
    if #ids == 0 then
        for _, target in ipairs(units) do add(nil, target) end
    end
    if #pulse_context.selected_targets == 0 then return nil end
    return pulse_context
end

function Adapter:schedule_damage(actor, command, context)
    self:_wait_for_actor(actor, context and context.lifecycle_id, command.delay or 0, function()
        local pulse_context = context
        if command.pulse_key then pulse_context = self:_pulse_context(actor, command, context) end
        if pulse_context then self:deal_damage(actor, command, pulse_context) end
    end, 'Chiming delayed damage')
end

function Adapter:move_safely(actor, command, context)
    local unit = self:_unit(actor)
    if not unit or not unit:is_exist() then return end
    local reduction, released = command.damage_reduction or 0, false
    local lifecycle_id = context and context.lifecycle_id
    if reduction > 0 then unit:add_attr('受伤减免', percent(reduction), '增益') end
    local function finish()
        if released then return end
        released = true
        if reduction > 0 and unit:is_exist() then unit:add_attr('受伤减免', -percent(reduction), '增益') end
        if self:_is_lifecycle_current(actor, lifecycle_id) and type(self.options.on_move_finished) == 'function' then
            self.options.on_move_finished(actor)
        end
    end
    unit:mover_line({
        speed = context and context.dash_speed or self.dash_speed, angle = context and context.angle or unit:get_facing(),
        distance = command.distance * self.distance_scale, acceleration = 0,
        min_speed = context and context.dash_speed or self.dash_speed,
        max_speed = context and context.dash_speed or self.dash_speed,
        terrain_block = command.safe_landing_required ~= false, face_angle = true,
        on_finish = finish, on_block = finish, on_break = finish, on_remove = finish,
    })
end

local contribution_fields = {
    move_speed = { attr = '移动速度', attr_type = '基础加成', scale = 100 },
    normal_slow = { attr = '移动速度', attr_type = '基础加成', scale = -100 },
}

local reduction_categories = {
    C03_M04_CHENGXIN_GUARD = 'personal_guard',
    C03_M12_XINDENG_YUWEN = 'xindeng',
}

local max_combined_reduction = 0.55

local function source_bound_policy(modifier_key)
    local policy = Config.modifiers[modifier_key] and Config.modifiers[modifier_key].policy
    return policy == 'source_bound' or policy == 'same_source_shield_refresh'
end

function Adapter:_effect_key(actor, target, modifier_key)
    local base = tostring(TargetContract.id_of(target)) .. ':' .. tostring(modifier_key)
    if source_bound_policy(modifier_key) then
        return base .. ':' .. tostring(actor)
    end
    return base
end

function Adapter:_remove_contribution(entry)
    if not entry or not entry.target or not entry.target:is_exist() then return end
    for _, value in pairs(entry.contributions or {}) do
        entry.target:add_attr(value.attr, -value.amount, value.attr_type)
    end
end

function Adapter:_recompute_damage_reduction(target)
    if not target or not target:is_exist() then return end
    local target_id, categories = TargetContract.id_of(target), {}
    for _, entry in pairs(self.effects) do
        if entry.target and TargetContract.id_of(entry.target) == target_id and entry.damage_reduction and entry.damage_reduction > 0 then
            local category = entry.reduction_category or 'other'
            categories[category] = math.max(categories[category] or 0, entry.damage_reduction)
        end
    end
    local remaining = 1
    for _, reduction in pairs(categories) do remaining = remaining * (1 - reduction) end
    local next_total = math.min(1 - remaining, max_combined_reduction)
    local previous = self.reduction_applied[target_id] or 0
    if next_total ~= previous then target:add_attr('受伤减免', percent(next_total - previous), '增益') end
    if next_total > 0 then self.reduction_applied[target_id] = next_total else self.reduction_applied[target_id] = nil end
end

function Adapter:_apply_contribution(actor, target, modifier_key, payload, duration, lifecycle_id)
    local key = self:_effect_key(actor, target, modifier_key)
    local previous = self.effects[key]
    if previous then self:_remove_contribution(previous) end
    local entry = {
        actor = actor, target = target, modifier_key = modifier_key, contributions = {},
        damage_reduction = payload and payload.damage_reduction or 0,
        reduction_category = reduction_categories[modifier_key], duration = duration,
    }
    self.next_effect_generation = self.next_effect_generation + 1
    entry.generation = self.next_effect_generation
    for payload_key, definition in pairs(contribution_fields) do
        local raw = payload and payload[payload_key]
        if raw and raw ~= 0 then
            local amount = raw * definition.scale
            target:add_attr(definition.attr, amount, definition.attr_type)
            entry.contributions[payload_key] = { attr = definition.attr, attr_type = definition.attr_type, amount = amount }
        end
    end
    self.effects[key] = entry
    self:_recompute_damage_reduction(target)
    if type(self.options.on_effect_payload) == 'function' then self.options.on_effect_payload(actor, target, modifier_key, payload or {}, duration) end
    if duration and duration > 0 then
        local generation = entry.generation
        self:_wait_for_actor(actor, lifecycle_id, duration, function()
            local current = self.effects[key]
            if current and current.generation == generation then
                self:_remove_contribution(current)
                self.effects[key] = nil
                local buff = self.buff_instances[key]
                if buff and type(buff.remove) == 'function' then buff:remove() end
                self.buff_instances[key] = nil
                self:_recompute_damage_reduction(current.target)
            end
        end, 'Chiming effect contribution cleanup')
    end
end

function Adapter:_remove_effect(actor, target, modifier_key)
    local buff_id = self.modifier_ids[modifier_key]
    local key = self:_effect_key(actor, target, modifier_key)
    if buff_id then
        local buff = self.buff_instances[key]
        if not buff and not source_bound_policy(modifier_key) then buff = target:find_buff(buff_id) end
        if buff then buff:remove() end
    end
    self.buff_instances[key] = nil
    local entry = self.effects[key]
    if entry then
        self:_remove_contribution(entry)
        self.effects[key] = nil
        self:_recompute_damage_reduction(target)
    end
end

function Adapter:apply_effect(actor, command, context)
    context = context or {}
    local effect_actor = command.source_id or actor
    local source = self:_unit(effect_actor) or self:_unit(actor)
    context.unit = context.unit or self:_unit(actor)
    local buff_id = self.modifier_ids[command.key]
    for index, target in ipairs(self:_targets(actor, command, context)) do
        if target and target:is_exist() then
            local target_id = command.resolved_target_ids and command.resolved_target_ids[index] or TargetContract.id_of(target)
            local payload, expires_at = self:_effect_snapshot(command, target_id)
            local current_time = context.now or y3.game.current_game_run_time()
            local duration = expires_at and math.max(0, expires_at - current_time) or command.duration
            if command.type == 'remove_modifier' and not payload then
                self:_remove_effect(effect_actor, target, command.key)
            else
                local instance_key = self:_effect_key(effect_actor, target, command.key)
                local buff = self.buff_instances[instance_key]
                if not buff and buff_id and not source_bound_policy(command.key) then buff = target:find_buff(buff_id) end
                if command.type == 'extend_modifier_once' then
                    if buff and duration then buff:set_time(duration) end
                    if payload and duration then self:_apply_contribution(effect_actor, target, command.key, payload, duration, context.lifecycle_id) end
                elseif command.type == 'refresh_modifier' then
                    if buff and duration then buff:set_time(duration) end
                    if payload and duration then self:_apply_contribution(effect_actor, target, command.key, payload, duration, context.lifecycle_id) end
                else
                    payload = payload or command.payload or {}
                    duration = duration or 0
                    if buff then
                        buff:set_time(duration)
                    elseif buff_id then
                        buff = target:add_buff({ key = buff_id, source = source, time = duration, stacks = 1, data = payload })
                    end
                    if buff then self.buff_instances[instance_key] = buff end
                    if buff and payload.max_hp_ratio then buff:set_shield(target:get_attr('最大生命') * payload.max_hp_ratio) end
                    self:_apply_contribution(effect_actor, target, command.key, payload, duration, context.lifecycle_id)
                end
            end
        end
    end
end

function Adapter:change_cooldown(actor, skill_key, amount)
    local ability = self:_ability(actor, skill_key)
    if ability then ability:set_cd(clamp_min(ability:get_cd() + amount, 0)) end
end

function Adapter:apply_control(actor, command, context)
    for _, target in ipairs(self:_targets(actor, command, context)) do
        if target and target:is_exist() then
            local target_id = TargetContract.id_of(target)
            local metadata = self:_target_metadata(command, context, target)
            if metadata.rank == 'boss' and command.boss_converts_to_break then
                self:apply_break(actor, {
                    type = 'break', target_scope = 'explicit', target_id = target_id, target = target,
                    break_value = command.boss_break_value or 0, break_scope = command.break_scope,
                    break_event_key = command.break_event_key, cast_id = command.cast_id,
                    lifecycle_id = command.lifecycle_id,
                    target_meta_by_id = command.target_meta_by_id,
                }, context)
            elseif metadata.rank == 'normal' or metadata.rank == 'elite' then
                local duration = metadata.rank == 'elite' and command.elite_duration or command.normal_duration
                if type(duration) == 'number' and duration > 0 then
                    self.controls:reap(target_id)
                    self.controls:acquire({
                        target = target,
                        target_id = target_id,
                        control_key = 'root',
                        duration = duration,
                        source_actor_id = actor,
                        lifecycle_id = command.lifecycle_id or (context and context.lifecycle_id),
                        cast_id = command.cast_id or (context and context.cast_id),
                        schedule = function(wait_time, callback, description) return y3.timer.wait(wait_time, callback, description) end,
                        is_alive = function(unit) return unit and unit:is_exist() end,
                        add_state = function(unit) unit:add_state(y3.const.UnitEnumState['禁止移动']) end,
                        remove_state = function(unit) unit:remove_state(y3.const.UnitEnumState['禁止移动']) end,
                    })
                end
            end
        end
    end
end

function Adapter:set_combo_floor(actor, stage, duration, context)
    if type(self.options.on_combo_floor) == 'function' then self.options.on_combo_floor(actor, stage, duration, context) end
end

function Adapter:heal_and_guard(actor, command, context)
    local unit = self:_unit(actor)
    if not unit or not unit:is_exist() then return end
    if command.heal_max_hp and command.heal_max_hp > 0 then unit:add_hp(unit:get_attr('最大生命') * command.heal_max_hp) end
    if (command.duration or 0) > 0 or (command.damage_reduction or 0) > 0 then
        self:apply_effect(actor, {
            type = 'apply_modifier', key = command.guard_key or 'C03_M12_XINDENG_YUWEN', target_scope = 'self',
            duration = command.duration, payload = { damage_reduction = command.damage_reduction },
        }, context)
    end
end

function Adapter:_set_state_buff(actor, modifier_key, enabled, duration)
    local unit, buff_id = self:_unit(actor), self.modifier_ids[modifier_key]
    if not unit or not unit:is_exist() or not buff_id then return end
    local buff = unit:find_buff(buff_id)
    if enabled then
        if buff then if duration then buff:set_time(duration) end
        else unit:add_buff({ key = buff_id, source = unit, time = duration or -1, stacks = 1 }) end
    elseif buff then
        buff:remove()
    end
end

function Adapter:_set_temporary_speed(actor, kind, amount, duration, lifecycle_id)
    local unit = self:_unit(actor)
    if not unit or not unit:is_exist() then return end
    local key = tostring(actor) .. ':' .. kind
    local previous = self.temporary_speed[key]
    if previous and previous.unit and previous.unit:is_exist() then previous.unit:add_attr('移动速度', -previous.amount, '基础加成') end
    local entry = { unit = unit, amount = percent(amount) }
    self.temporary_speed[key] = entry
    unit:add_attr('移动速度', entry.amount, '基础加成')
    self:_wait_for_actor(actor, lifecycle_id, duration, function()
        if self.temporary_speed[key] == entry then
            if unit:is_exist() then unit:add_attr('移动速度', -entry.amount, '基础加成') end
            self.temporary_speed[key] = nil
        end
    end, 'Chiming temporary move speed')
end

function Adapter:_clear_temporary_speed(actor)
    local prefix = tostring(actor) .. ':'
    for key, entry in pairs(self.temporary_speed) do
        if key:sub(1, #prefix) == prefix then
            if entry.unit and entry.unit:is_exist() then entry.unit:add_attr('移动速度', -entry.amount, '基础加成') end
            self.temporary_speed[key] = nil
        end
    end
end

function Adapter:state_changed(actor, event, context)
    context = context or {}
    if event.mingtai ~= nil then self:_set_state_buff(actor, 'C03_M01_MINGTAI', event.mingtai == true) end
    if event.type == 'ultimate_activated' then
        local now = context.now or y3.game.current_game_run_time()
        self:_set_state_buff(actor, 'C03_M11_MINGJIE', true, event.expires_at and event.expires_at - now or nil)
    elseif event.type == 'mingjie_expired' then
        self:_set_state_buff(actor, 'C03_M11_MINGJIE', false)
    elseif event.type == 'p01_speed' or event.type == 'a04_protection_speed' or event.type == 'a07_protection_speed' then
        self:_set_temporary_speed(actor, event.type, event.move_speed or 0, event.duration or 0, context.lifecycle_id)
    elseif event.type == 'transient_cleared' then
        self:_set_state_buff(actor, 'C03_M01_MINGTAI', false)
        self:_set_state_buff(actor, 'C03_M11_MINGJIE', false)
        self:_clear_temporary_speed(actor)
        local removals = {}
        for _, entry in pairs(self.effects) do
            if entry.actor == actor or entry.target == self:_unit(actor) then
                append(removals, {
                    actor = entry.actor,
                    target = entry.target,
                    modifier_key = entry.modifier_key,
                })
            end
        end
        for _, removal in ipairs(removals) do
            self:_remove_effect(removal.actor, removal.target, removal.modifier_key)
        end
    end
    if type(self.options.on_state_changed) == 'function' then self.options.on_state_changed(actor, event, context) end
end

return M
