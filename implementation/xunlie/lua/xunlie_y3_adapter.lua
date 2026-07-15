-- The sole C04 module allowed to call public Y3 Lua APIs. It does not invent
-- map data: unresolved target, point and pulse hooks simply produce no effect.
local Config = require 'xunlie_config'
local TargetContract = require 'xunlie_target_contract'

local M = {}
local Adapter = {}
Adapter.__index = Adapter

local function append(list, value)
    list[#list + 1] = value
end

local function percent(value)
    return value * 100
end

local function ticks_to_seconds(ticks)
    return (ticks or 0) / Config.ticks_per_second
end

local function clamp_min(value, minimum)
    return value < minimum and minimum or value
end

local function map_value(map, key)
    return type(map) == 'table' and (map[key] or map[tostring(key)]) or nil
end

function M.new(options)
    options = options or {}
    assert(_G.y3, 'xunlie_y3_adapter must be loaded inside Y3')
    assert(type(options.unit_by_actor) == 'function', 'unit_by_actor callback is required')
    return setmetatable({
        options = options, ability_ids = options.ability_ids or {}, ability_types = options.ability_types or {},
        modifier_ids = options.modifier_ids or {}, distance_scale = options.distance_scale or 100,
        dash_speed = options.dash_speed or 1200, actor_timers = {}, buff_instances = {}, effects = {},
        lifecycle_resolver = nil,
    }, Adapter)
end

function Adapter:set_lifecycle_resolver(resolver)
    assert(type(resolver) == 'function', 'lifecycle resolver must be a function')
    self.lifecycle_resolver = resolver
end

function Adapter:_is_lifecycle_current(actor_id, lifecycle_id)
    if lifecycle_id == nil or self.lifecycle_resolver == nil then return true end
    return self.lifecycle_resolver(actor_id, lifecycle_id) == true
end

function Adapter:_timer_bucket(actor_id, lifecycle_id, create)
    local by_actor = self.actor_timers[actor_id]
    if not by_actor and create then by_actor = {}; self.actor_timers[actor_id] = by_actor end
    if not by_actor then return nil end
    local key = lifecycle_id == nil and '__unbound__' or tostring(lifecycle_id)
    local bucket = by_actor[key]
    if not bucket and create then bucket = {}; by_actor[key] = bucket end
    return bucket, key
end

function Adapter:_track_timer(actor_id, lifecycle_id, timer)
    local bucket = self:_timer_bucket(actor_id, lifecycle_id, true)
    bucket[timer] = true
end

function Adapter:_untrack_timer(actor_id, lifecycle_id, timer)
    local bucket, key = self:_timer_bucket(actor_id, lifecycle_id, false)
    if not bucket then return end
    bucket[timer] = nil
    if next(bucket) == nil then
        local by_actor = self.actor_timers[actor_id]
        by_actor[key] = nil
        if next(by_actor) == nil then self.actor_timers[actor_id] = nil end
    end
end

function Adapter:_wait(actor_id, lifecycle_id, delay_ticks, callback, description)
    local timer
    timer = y3.timer.wait(ticks_to_seconds(delay_ticks), function()
        self:_untrack_timer(actor_id, lifecycle_id, timer)
        if self:_is_lifecycle_current(actor_id, lifecycle_id) then callback() end
    end, description)
    self:_track_timer(actor_id, lifecycle_id, timer)
    return timer
end

function Adapter:cancel_actor_timers(actor_id, lifecycle_id)
    local by_actor = self.actor_timers[actor_id]
    if not by_actor then return end
    local keys = {}
    for key in pairs(by_actor) do
        if lifecycle_id == nil or key == tostring(lifecycle_id) then append(keys, key) end
    end
    for _, key in ipairs(keys) do
        for timer in pairs(by_actor[key]) do timer:remove() end
        by_actor[key] = nil
    end
    if next(by_actor) == nil then self.actor_timers[actor_id] = nil end
end

function Adapter:_unit(reference)
    if type(reference) == 'table' and type(reference.is_exist) == 'function' then return reference end
    return self.options.unit_by_actor(reference)
end

function Adapter:_ability(actor_id, skill_key)
    local unit, ability_id = self:_unit(actor_id), self.ability_ids[skill_key]
    if not unit or not ability_id then return nil end
    return unit:find_ability(self.ability_types[skill_key] or '英雄', ability_id)
end

function Adapter:_targets(actor_id, command, context)
    context = context or {}
    local source = context.unit or self:_unit(actor_id)
    local source_id = TargetContract.id_of(source, actor_id)
    local refs = command.target_refs_by_id or context.target_refs_by_id or {}
    local entries, seen = {}, {}
    local function add(target_id, ref)
        if target_id == nil or seen[target_id] then return end
        ref = ref or map_value(refs, target_id)
        if ref == nil or (type(ref.is_exist) == 'function' and not ref:is_exist()) then return end
        seen[target_id] = true
        append(entries, { id = target_id, ref = ref })
    end
    local function add_many(ids, units)
        for index, target_id in ipairs(ids or {}) do add(target_id, units and units[index]) end
        if #(ids or {}) == 0 then
            for _, unit in ipairs(units or {}) do add(TargetContract.id_of(unit), unit) end
        end
    end
    if command.target_scope == 'self' then
        add(source_id, source)
    elseif command.target_scope == 'primary' then
        add(context.primary_target_id, context.primary_target_ref)
    elseif command.target_scope == 'selected' then
        add_many(command.target_ids or context.selected_target_ids, command.targets or context.selected_targets)
    elseif command.target_scope == 'explicit' then
        if command.target_id ~= nil or command.target ~= nil then add(command.target_id or TargetContract.id_of(command.target), command.target)
        else add_many(command.target_ids or command.explicit_target_ids, command.targets or command.explicit_targets) end
    end
    command.resolved_target_ids, command.resolved_target_refs, command.resolved_targets = {}, {}, entries
    local output = {}
    for index, entry in ipairs(entries) do
        command.resolved_target_ids[index], command.resolved_target_refs[index] = entry.id, entry.ref
        append(output, entry.ref)
    end
    return output
end

function Adapter:_effect_key(actor_id, target, modifier_key, source_id)
    local definition = Config.modifiers[modifier_key] or {}
    local key = tostring(TargetContract.id_of(target)) .. ':' .. modifier_key
    if definition.policy ~= 'shared_highest' and definition.policy ~= 'derived' then
        key = key .. ':' .. tostring(source_id or actor_id)
    end
    return key
end

function Adapter:_effect_snapshot(command, target_id)
    local snapshot = command.effect_snapshots and command.effect_snapshots[tostring(target_id)]
    if not snapshot then return command.payload or {}, command.duration end
    local definition = Config.modifiers[command.key] or {}
    local record = definition.policy == 'shared_highest' and snapshot.aggregate or snapshot.source
    if record and record.payload then
        local now = y3.game.current_game_run_time()
        return record.payload, record.expires_at and math.max(0, record.expires_at - now) or command.duration
    end
    return command.payload or {}, command.duration
end

function Adapter:sync_hero_stats(actor_id, stats, context)
    local unit = self:_unit(actor_id) or (context and context.unit)
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
    unit:set_attr('闪避率', percent(stats.dodge_rate), '基础')
    unit:set_attr('冷却缩减', percent(stats.cooldown_reduction), '基础')
    unit:set_attr('移动速度', stats.move_speed, '基础')
    unit:set_attr('攻击速度', stats.attack_speed, '基础')
    unit:set_attr('攻击间隔', stats.attack_interval, '基础')
    if context and context.current_hp ~= nil then unit:set_hp(context.current_hp) end
end

function Adapter:sync_ability_charge(actor_id, update)
    local ability = self:_ability(actor_id, update.skill_key)
    if not ability then return end
    ability:set_stack(update.current)
    ability:set_charge_time(update.remaining)
end

function Adapter:deal_damage(actor_id, command, context)
    local source = self:_unit(actor_id)
    if not source or not source:is_exist() then return end
    local ability = self:_ability(actor_id, command.skill_key or (context and context.skill_key))
    local attack = source:get_attr('物理攻击')
    for _, target in ipairs(self:_targets(actor_id, command, context)) do
        source:damage({
            target = target, type = '物理', damage = attack * command.coefficient,
            ability = ability, common_attack = false, no_miss = context and context.no_miss or false,
        })
    end
end

function Adapter:apply_break()
    -- C04 has no reviewed break value. Keep the adapter contract complete only.
end

function Adapter:_pulse_context(actor_id, command, context)
    if type(self.options.resolve_pulse_context) ~= 'function' then return nil end
    return self.options.resolve_pulse_context(actor_id, command, context)
end

function Adapter:schedule_damage(actor_id, command, context)
    self:_wait(actor_id, context and context.lifecycle_id, command.delay or 0, function()
        local pulse = command.pulse_key and self:_pulse_context(actor_id, command, context) or context
        if pulse then self:deal_damage(actor_id, command, pulse) end
    end, 'Xunlie delayed damage')
end

function Adapter:move_safely(actor_id, command, context)
    local unit = self:_unit(actor_id)
    if not unit or not unit:is_exist() then return end
    local lifecycle_id, completed = context and context.lifecycle_id, false
    local function finish()
        if completed then return end
        completed = true
        if self:_is_lifecycle_current(actor_id, lifecycle_id) and type(self.options.on_move_finished) == 'function' then
            self.options.on_move_finished(actor_id, command.cast_id, context)
        end
    end
    unit:mover_line({
        speed = self.dash_speed, angle = command.direction or unit:get_facing(),
        distance = command.distance * self.distance_scale, acceleration = 0,
        min_speed = self.dash_speed, max_speed = self.dash_speed,
        terrain_block = command.safe_landing_required ~= false, face_angle = true,
        on_finish = finish, on_block = finish, on_break = finish, on_remove = finish,
    })
end

local contribution_fields = {
    C04_M05_WIND = { field = 'move_speed', scale = 100 },
    C04_M07_SLOW = { field = 'slow', scale = -100 },
    C04_M12_RECOVERY = { field = 'move_speed', scale = 100 },
}

function Adapter:_remove_effect(key)
    local entry = self.effects[key]
    if not entry then return end
    if entry.target and entry.target:is_exist() and entry.attr_amount and entry.attr_amount ~= 0 then
        entry.target:add_attr('移动速度', -entry.attr_amount, '基础加成')
    end
    local buff = self.buff_instances[key]
    if buff then buff:remove() end
    self.buff_instances[key], self.effects[key] = nil, nil
end

function Adapter:_apply_effect(actor_id, target, command, target_id, context)
    local source_id = command.source_id or actor_id
    local key = self:_effect_key(actor_id, target, command.key, source_id)
    local payload, duration = self:_effect_snapshot(command, target_id)
    local definition = Config.modifiers[command.key] or {}
    if command.type == 'remove_modifier' then
        local current = command.effect_snapshots and command.effect_snapshots[tostring(target_id)]
        if definition.policy ~= 'shared_highest' or not (current and current.aggregate) then
            self:_remove_effect(key)
            return
        end
        -- A lower-priority slow expired. Reapply the remaining aggregate rather
        -- than removing the visible slow while another source is still valid.
        command = {
            type = 'apply_modifier', key = command.key, source_id = source_id,
            payload = payload, duration = duration, target_scope = command.target_scope,
        }
    end
    if command.key == 'C04_M07_SLOW' then
        local metadata = map_value(context and context.target_meta_by_id, target_id) or {}
        if metadata.rank ~= 'normal' and metadata.rank ~= 'elite' then return end
    end
    self:_remove_effect(key)
    local entry = { target = target, actor_id = actor_id, source_id = source_id, modifier_key = command.key }
    local contribution = contribution_fields[command.key]
    if contribution and type(payload[contribution.field]) == 'number' then
        entry.attr_amount = payload[contribution.field] * contribution.scale
        target:add_attr('移动速度', entry.attr_amount, '基础加成')
    end
    self.effects[key] = entry
    local buff_id = self.modifier_ids[command.key]
    if buff_id then
        local source = self:_unit(actor_id)
        local buff = target:add_buff({ key = buff_id, source = source, time = ticks_to_seconds(duration), stacks = 1, data = payload })
        self.buff_instances[key] = buff
    end
    if duration and duration > 0 then
        self:_wait(actor_id, context and context.lifecycle_id, duration, function() self:_remove_effect(key) end, 'Xunlie effect cleanup')
    end
end

function Adapter:apply_effect(actor_id, command, context)
    for index, target in ipairs(self:_targets(actor_id, command, context)) do
        local target_id = command.resolved_target_ids and command.resolved_target_ids[index] or TargetContract.id_of(target)
        if target and target:is_exist() then self:_apply_effect(actor_id, target, command, target_id, context) end
    end
end

function Adapter:change_cooldown(actor_id, skill_key, amount)
    local ability = self:_ability(actor_id, skill_key)
    if ability then ability:set_cd(clamp_min(ability:get_cd() + amount, 0)) end
end

function Adapter:apply_control()
    -- C04 deliberately has no hard-control command path.
end

function Adapter:set_combo_floor()
    -- C04 does not own a normal-combo floor.
end

function Adapter:heal_and_guard(actor_id, command)
    local unit = self:_unit(actor_id)
    if not unit or not unit:is_exist() then return end
    if command.heal_max_hp and command.heal_max_hp > 0 then
        unit:add_hp(unit:get_attr('最大生命') * command.heal_max_hp)
    end
end

function Adapter:state_changed(actor_id, event, context)
    if event.type == 'transient_cleared' then
        self:cancel_actor_timers(actor_id, context and context.lifecycle_id)
        local keys = {}
        for key, entry in pairs(self.effects) do if entry.actor_id == actor_id then append(keys, key) end end
        for _, key in ipairs(keys) do self:_remove_effect(key) end
    end
    if type(self.options.on_state_changed) == 'function' then self.options.on_state_changed(actor_id, event, context) end
end

return M
