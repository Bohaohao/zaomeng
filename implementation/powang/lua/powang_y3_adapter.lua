local TargetContract = require 'powang_target_contract'
local ControlLedger = require 'powang_y3_control_ledger'
local Config = require 'powang_config'

local M = {}

local Adapter = {}
Adapter.__index = Adapter

local function clamp_min(value, minimum)
    if value < minimum then
        return minimum
    end
    return value
end

local function percent(value)
    return value * 100
end

function M.new(options)
    options = options or {}
    assert(_G.y3, 'powang_y3_adapter must be loaded inside Y3')
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
        control_leases = {},
        next_effect_generation = 0,
        lifecycle_resolver = nil,
        controls = ControlLedger.new(),
    }, Adapter)
end

function Adapter:set_lifecycle_resolver(resolver)
    assert(type(resolver) == 'function', 'lifecycle resolver must be a function')
    self.lifecycle_resolver = resolver
end

function Adapter:_is_lifecycle_current(actor, lifecycle_id)
    if lifecycle_id == nil or self.lifecycle_resolver == nil then
        return true
    end
    return self.lifecycle_resolver(actor, lifecycle_id) == true
end

function Adapter:_timer_bucket(actor, lifecycle_id, create)
    local by_actor = self.actor_timers[actor]
    if not by_actor and create then
        by_actor = {}
        self.actor_timers[actor] = by_actor
    end
    if not by_actor then
        return nil
    end
    local key = lifecycle_id == nil and '__unbound__' or tostring(lifecycle_id)
    local bucket = by_actor[key]
    if not bucket and create then
        bucket = {}
        by_actor[key] = bucket
    end
    return bucket, key
end

function Adapter:_track_timer(actor, lifecycle_id, timer)
    local bucket = self:_timer_bucket(actor, lifecycle_id, true)
    bucket[timer] = true
end

function Adapter:_untrack_timer(actor, lifecycle_id, timer)
    local bucket, key = self:_timer_bucket(actor, lifecycle_id, false)
    if not bucket then
        return
    end
    bucket[timer] = nil
    if next(bucket) == nil then
        local by_actor = self.actor_timers[actor]
        by_actor[key] = nil
        if next(by_actor) == nil then
            self.actor_timers[actor] = nil
        end
    end
end

function Adapter:_wait_for_actor(actor, lifecycle_id, delay, callback, description)
    local timer
    timer = y3.timer.wait(delay, function()
        self:_untrack_timer(actor, lifecycle_id, timer)
        if self:_is_lifecycle_current(actor, lifecycle_id) then
            callback()
        end
    end, description)
    self:_track_timer(actor, lifecycle_id, timer)
    return timer
end

function Adapter:_control_bucket(actor, lifecycle_id, create)
    local by_actor = self.control_leases[actor]
    if not by_actor and create then
        by_actor = {}
        self.control_leases[actor] = by_actor
    end
    if not by_actor then
        return nil
    end
    local key = lifecycle_id == nil and '__unbound__' or tostring(lifecycle_id)
    local bucket = by_actor[key]
    if not bucket and create then
        bucket = {}
        by_actor[key] = bucket
    end
    return bucket, key
end

function Adapter:_track_control_lease(actor, lifecycle_id, lease)
    local bucket = self:_control_bucket(actor, lifecycle_id, true)
    bucket[lease] = true
end

function Adapter:_untrack_control_lease(actor, lifecycle_id, lease)
    local bucket, key = self:_control_bucket(actor, lifecycle_id, false)
    if not bucket then
        return
    end
    bucket[lease] = nil
    if next(bucket) == nil then
        local by_actor = self.control_leases[actor]
        by_actor[key] = nil
        if next(by_actor) == nil then
            self.control_leases[actor] = nil
        end
    end
end

function Adapter:_release_control_leases(actor, lifecycle_id)
    local by_actor = self.control_leases[actor]
    if not by_actor then
        return
    end
    local keys = {}
    for key in pairs(by_actor) do
        if lifecycle_id == nil or key == tostring(lifecycle_id) then
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do
        local bucket = by_actor[key]
        local leases = {}
        for lease in pairs(bucket) do
            leases[#leases + 1] = lease
        end
        for _, lease in ipairs(leases) do
            if type(lease.release) == 'function' then
                lease:release()
            else
                self.controls:expire(lease)
            end
        end
        by_actor[key] = nil
    end
    if next(by_actor) == nil then
        self.control_leases[actor] = nil
    end
end

function Adapter:cancel_actor_timers(actor, lifecycle_id)
    self:_release_control_leases(actor, lifecycle_id)
    self:_clear_actor_transient_entries(actor, lifecycle_id)

    local by_actor = self.actor_timers[actor]
    if not by_actor then
        return
    end
    local keys = {}
    for key in pairs(by_actor) do
        if lifecycle_id == nil or key == tostring(lifecycle_id) then
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do
        local bucket = by_actor[key]
        for timer in pairs(bucket) do
            timer:remove()
        end
        by_actor[key] = nil
    end
    if next(by_actor) == nil then
        self.actor_timers[actor] = nil
    end
end

function Adapter:_unit(reference)
    if type(reference) == 'table' and type(reference.is_exist) == 'function' then
        return reference
    end
    return self.options.unit_by_actor(reference)
end

function Adapter:_ability(actor, skill_key)
    local unit = self:_unit(actor)
    local ability_id = self.ability_ids[skill_key]
    if not unit or not ability_id then
        return nil
    end
    return unit:find_ability(self.ability_types[skill_key] or '英雄', ability_id)
end

function Adapter:_targets(actor, command, context)
    context = context or {}
    if command.target_scope then
        local source = self:_unit(actor)
        context.unit = context.unit or source
        local entries = TargetContract.resolve(actor, command, context)
        if not entries then
            return {}
        end
        command.resolved_targets = entries
        command.resolved_target_ids = {}
        command.resolved_target_refs = {}
        local targets = {}
        for index, entry in ipairs(entries) do
            command.resolved_target_ids[index] = entry.id
            command.resolved_target_refs[index] = entry.ref
            if entry.ref then
                targets[#targets + 1] = entry.ref
            end
        end
        return targets
    end
    if type(self.options.resolve_targets) == 'function' then
        local resolved = self.options.resolve_targets(actor, command, context)
        if resolved then
            return resolved
        end
    end
    if command.area_radius and (context.target_point or context.target) then
        local source = self:_unit(actor)
        if source and source:is_exist() then
            return y3.selector.create()
                :in_range(context.target_point or context.target, command.area_radius * self.distance_scale)
                :is_enemy(source:get_owner())
                :not_in_state(y3.const.UnitEnumState['无敌'])
                :without_tag(self.options.excluded_tag or '剧情无敌')
                :pick()
        end
    end
    if command.type == 'apply_team_modifier' and context.team_targets then
        return context.team_targets
    end
    if command.targets then
        return command.targets
    end
    if context.targets then
        return context.targets
    end
    if context.target then
        return { context.target }
    end
    if command.target then
        return { command.target }
    end
    if command.target_id then
        local target = self:_unit(command.target_id)
        return target and { target } or {}
    end
    local unit = self:_unit(actor)
    return unit and { unit } or {}
end

function Adapter:_effect_snapshot(command, target_id)
    local snapshots = command.effect_snapshots
    if not snapshots then
        return nil, nil
    end
    local snapshot = snapshots[tostring(target_id)]
    if not snapshot then
        return nil, nil
    end
    if snapshot.aggregate and snapshot.aggregate.payload then
        return snapshot.aggregate.payload, snapshot.aggregate.expires_at
    end
    if snapshot.source then
        return snapshot.source.payload, snapshot.source.expires_at
    end
    return nil, nil
end

function Adapter:sync_hero_stats(actor, stats, context)
    local unit = self:_unit(actor) or (context and context.unit)
    if not unit or not unit:is_exist() then
        return
    end
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
    if context and context.current_hp ~= nil then
        unit:set_hp(context.current_hp)
    end
end

function Adapter:sync_ability_charge(actor, update)
    local ability = self:_ability(actor, update.skill_key)
    if not ability then
        return
    end
    ability:set_stack(update.current)
    ability:set_charge_time(update.remaining)
end

function Adapter:deal_damage(actor, command, context)
    local source = self:_unit(actor)
    if not source or not source:is_exist() then
        return
    end
    local ability = self:_ability(actor, context.skill_key or command.skill_key)
    local attack = source:get_attr('物理攻击')
    for _, target in ipairs(self:_targets(actor, command, context)) do
        if target and target:is_exist() then
            source:damage({
                target = target,
                type = '物理',
                damage = attack * command.coefficient,
                ability = ability,
                common_attack = false,
                no_miss = context.no_miss or false,
            })
            if command.break_value and type(self.options.apply_break) == 'function' then
                self.options.apply_break(source, target, command.break_value, command, context)
            end
        end
    end
end

function Adapter:apply_break(actor, command, context)
    if type(self.options.apply_break) ~= 'function' then
        return
    end
    local source = self:_unit(actor)
    if not source or not source:is_exist() then
        return
    end
    for _, target in ipairs(self:_targets(actor, command, context)) do
        if target and target:is_exist() then
            self.options.apply_break(source, target, command.break_value, command, context)
        end
    end
end

function Adapter:schedule_damage(actor, command, context)
    local delay = command.delay or 0
    self:_wait_for_actor(actor, context and context.lifecycle_id, delay, function()
        self:deal_damage(actor, command, context)
    end, 'Powang delayed damage')
end

function Adapter:move_safely(actor, command, context)
    context = context or {}
    local unit = self:_unit(actor)
    if not unit or not unit:is_exist() then
        return
    end
    local reduction = command.damage_reduction or 0
    local lifecycle_id = context.lifecycle_id
    local reduction_key
    if reduction > 0 then
        reduction_key = self:_add_transient_reduction(
            actor,
            unit,
            reduction,
            command.damage_reduction_category or Config.mitigation.move_category,
            lifecycle_id
        )
    end
    local released = false
    local function finish_move()
        if released then
            return
        end
        released = true
        self:_remove_transient_reduction(reduction_key)
        if not self:_is_lifecycle_current(actor, lifecycle_id) then
            return
        end
        if unit:is_exist() then
            for _, refresh in ipairs(context.powang_after_move_refreshes or {}) do
                local buff_id = self.modifier_ids[refresh.key]
                local buff = buff_id and unit:find_buff(buff_id) or nil
                if buff then
                    buff:set_time(refresh.duration)
                end
                self:_apply_contribution(
                    actor,
                    unit,
                    refresh.key,
                    refresh.payload,
                    refresh.duration,
                    lifecycle_id
                )
            end
        end
        if type(self.options.on_move_finished) == 'function' then
            self.options.on_move_finished(actor, lifecycle_id)
        end
    end
    unit:mover_line({
        speed = context.dash_speed or self.dash_speed,
        angle = context.angle or unit:get_facing(),
        distance = command.distance * self.distance_scale,
        acceleration = 0,
        min_speed = context.dash_speed or self.dash_speed,
        max_speed = context.dash_speed or self.dash_speed,
        terrain_block = command.safe_landing_required ~= false,
        face_angle = true,
        on_finish = finish_move,
        on_block = finish_move,
        on_break = finish_move,
        on_remove = finish_move,
    })
end

local contribution_fields = {
    move_speed = { attr = '移动速度', attr_type = '基础加成', scale = 100 },
    attack_speed = { attr = '攻击速度', attr_type = '基础加成', scale = 100 },
    defense_reduction = { attr = '物理防御', attr_type = '基础加成', scale = -100 },
    normal_slow = { attr = '移动速度', attr_type = '基础加成', scale = -100 },
}

local reduction_categories = Config.mitigation.effect_categories or {}
local max_combined_reduction = Config.mitigation.max_combined_damage_reduction or 0.70

function Adapter:_effect_key(target, modifier_key)
    return tostring(TargetContract.id_of(target)) .. ':' .. tostring(modifier_key)
end

function Adapter:_remove_contribution(entry)
    if not entry or not entry.target or not entry.target:is_exist() then
        return
    end
    for _, value in pairs(entry.contributions or {}) do
        entry.target:add_attr(value.attr, -value.amount, value.attr_type)
    end
end

function Adapter:_recompute_damage_reduction(target)
    if not target or not target:is_exist() then
        return
    end
    local target_id = TargetContract.id_of(target)
    local categories = {}
    for _, entry in pairs(self.effects) do
        if entry.target and TargetContract.id_of(entry.target) == target_id
            and type(entry.damage_reduction) == 'number' and entry.damage_reduction > 0 then
            local category = entry.reduction_category or 'external'
            local bounded = math.min(math.max(entry.damage_reduction, 0), 1)
            categories[category] = math.max(categories[category] or 0, bounded)
        end
    end
    local remaining = 1
    for _, reduction in pairs(categories) do
        remaining = remaining * (1 - reduction)
    end
    local next_total = math.min(1 - remaining, max_combined_reduction)
    local previous = self.reduction_applied[target_id] or 0
    if next_total ~= previous then
        target:add_attr('受伤减免', percent(next_total - previous), '增益')
    end
    if next_total > 0 then
        self.reduction_applied[target_id] = next_total
    else
        self.reduction_applied[target_id] = nil
    end
end

function Adapter:_add_transient_reduction(actor, target, amount, category, lifecycle_id)
    if type(amount) ~= 'number' or amount <= 0 then
        return nil
    end
    self.next_effect_generation = self.next_effect_generation + 1
    local key = self:_effect_key(target, '__move_reduction:' .. tostring(actor) .. ':' .. tostring(self.next_effect_generation))
    self.effects[key] = {
        actor = actor,
        target = target,
        modifier_key = '__move_reduction',
        contributions = {},
        damage_reduction = amount,
        reduction_category = category,
        lifecycle_id = lifecycle_id,
        generation = self.next_effect_generation,
        transient = true,
    }
    self:_recompute_damage_reduction(target)
    return key
end

function Adapter:_remove_transient_reduction(key)
    if not key then
        return
    end
    local entry = self.effects[key]
    if not entry then
        return
    end
    self:_remove_contribution(entry)
    self.effects[key] = nil
    self:_recompute_damage_reduction(entry.target)
end

function Adapter:_clear_actor_transient_entries(actor, lifecycle_id)
    local keys = {}
    for key, entry in pairs(self.effects) do
        if entry.transient and entry.actor == actor
            and (lifecycle_id == nil or entry.lifecycle_id == lifecycle_id) then
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do
        self:_remove_transient_reduction(key)
    end
end

function Adapter:_apply_contribution(actor, target, modifier_key, payload, duration, lifecycle_id)
    local key = self:_effect_key(target, modifier_key)
    local previous = self.effects[key]
    if previous then
        self:_remove_contribution(previous)
    end

    self.next_effect_generation = self.next_effect_generation + 1
    local entry = {
        actor = actor,
        target = target,
        modifier_key = modifier_key,
        contributions = {},
        damage_reduction = payload and payload.damage_reduction or 0,
        reduction_category = (payload and payload.damage_reduction_category)
            or reduction_categories[modifier_key]
            or 'external',
        lifecycle_id = lifecycle_id,
        generation = self.next_effect_generation,
        duration = duration,
    }
    for payload_key, definition in pairs(contribution_fields) do
        local raw = payload and payload[payload_key]
        if type(raw) == 'number' and raw ~= 0 then
            local amount = raw * definition.scale
            target:add_attr(definition.attr, amount, definition.attr_type)
            entry.contributions[payload_key] = {
                attr = definition.attr,
                attr_type = definition.attr_type,
                amount = amount,
            }
        end
    end
    self.effects[key] = entry
    self:_recompute_damage_reduction(target)

    if type(self.options.on_effect_payload) == 'function' then
        self.options.on_effect_payload(actor, target, modifier_key, payload or {}, duration)
    end
    if duration and duration > 0 then
        local generation = entry.generation
        self:_wait_for_actor(actor, lifecycle_id, duration, function()
            local current = self.effects[key]
            if current and current.generation == generation then
                self:_remove_contribution(current)
                self.effects[key] = nil
                self:_recompute_damage_reduction(current.target)
            end
        end, 'Powang effect contribution cleanup')
    end
end

function Adapter:_remove_effect(actor, target, modifier_key)
    local buff_id = self.modifier_ids[modifier_key]
    if buff_id then
        local buff = target:find_buff(buff_id)
        if buff then
            buff:remove()
        end
    end
    local key = self:_effect_key(target, modifier_key)
    local entry = self.effects[key]
    if entry then
        self:_remove_contribution(entry)
        self.effects[key] = nil
        self:_recompute_damage_reduction(target)
    end
end

function Adapter:apply_effect(actor, command, context)
    context = context or {}
    local source = self:_unit(actor)
    context.unit = context.unit or source
    local buff_id = self.modifier_ids[command.key]
    for index, target in ipairs(self:_targets(actor, command, context)) do
        if target and target:is_exist() then
            local target_id = command.resolved_target_ids and command.resolved_target_ids[index]
                or TargetContract.id_of(target)
            local resolved_payload, resolved_expires_at = self:_effect_snapshot(command, target_id)
            local current_time = context.now or y3.game.current_game_run_time()
            local resolved_duration = resolved_expires_at and math.max(0, resolved_expires_at - current_time) or command.duration
            if command.type == 'remove_modifier' and not resolved_payload then
                self:_remove_effect(actor, target, command.key)
            else
                local buff = buff_id and target:find_buff(buff_id) or nil
                if command.type == 'extend_modifier_once' then
                    if buff and resolved_duration then
                        buff:set_time(resolved_duration)
                    end
                    if resolved_payload and resolved_duration then
                        self:_apply_contribution(
                            actor,
                            target,
                            command.key,
                            resolved_payload,
                            resolved_duration,
                            context.lifecycle_id
                        )
                    end
                elseif command.type == 'refresh_modifier' then
                    local entry = self.effects[self:_effect_key(target, command.key)]
                    if buff and (resolved_duration or (entry and entry.duration)) then
                        buff:set_time(resolved_duration or entry.duration)
                    end
                    if resolved_payload and resolved_duration then
                        self:_apply_contribution(
                            actor,
                            target,
                            command.key,
                            resolved_payload,
                            resolved_duration,
                            context.lifecycle_id
                        )
                    end
                else
                    local duration = resolved_duration or 0
                    local payload = resolved_payload or command.payload
                    if buff then
                        buff:set_time(duration)
                    elseif buff_id then
                        buff = target:add_buff({
                            key = buff_id,
                            source = source,
                            time = duration,
                            stacks = 1,
                            data = payload or {},
                        })
                    end
                    if buff and payload and payload.max_hp_ratio then
                        buff:set_shield(target:get_attr('最大生命') * payload.max_hp_ratio)
                    end
                    self:_apply_contribution(
                        actor,
                        target,
                        command.key,
                        payload,
                        duration,
                        context.lifecycle_id
                    )
                    if source
                        and TargetContract.id_of(target) == TargetContract.id_of(source)
                        and (command.key == 'C01_M09_TAXU_WIND' or command.key == 'C01_M10_JINTUI_GUARD') then
                        context.powang_after_move_refreshes = context.powang_after_move_refreshes or {}
                        context.powang_after_move_refreshes[#context.powang_after_move_refreshes + 1] = {
                            key = command.key,
                            payload = payload,
                            duration = duration,
                        }
                    end
                end
            end
        end
    end
end

function Adapter:change_cooldown(actor, skill_key, amount)
    local ability = self:_ability(actor, skill_key)
    if ability then
        ability:set_cd(clamp_min(ability:get_cd() + amount, 0))
    end
end

function Adapter:apply_control(actor, command, context)
    context = context or {}
    local lifecycle_id = context.lifecycle_id
    for _, target in ipairs(self:_targets(actor, command, context)) do
        if target and target:is_exist() then
            local target_id = TargetContract.id_of(target)
            local metadata = (command.target_meta_by_id and (
                command.target_meta_by_id[target_id] or command.target_meta_by_id[tostring(target_id)]
            )) or (context.target_meta_by_id and (
                context.target_meta_by_id[target_id] or context.target_meta_by_id[tostring(target_id)]
            )) or {}
            local rank = metadata.rank
            if rank == nil and not command.requires_target_rank then
                rank = context.target_rank or 'normal'
            end
            if rank ~= nil then
                if rank == 'boss' and command.boss_converts_to_break then
                    if type(self.options.apply_break) == 'function' then
                        self.options.apply_break(self:_unit(actor), target, command.boss_break_value or 0.5, command, context)
                    end
                else
                    local duration = rank == 'elite' and command.elite_duration or command.normal_duration
                    self.controls:reap(target_id)
                    local lease
                    local function schedule(wait_time, callback, description)
                        return self:_wait_for_actor(actor, lifecycle_id, wait_time, function()
                            callback()
                            if lease then
                                self:_untrack_control_lease(actor, lifecycle_id, lease)
                            end
                        end, description)
                    end
                    lease = self.controls:acquire(target, 'root', duration, {
                        target_id = target_id,
                        schedule = schedule,
                        is_alive = function(unit)
                            return unit and unit:is_exist()
                        end,
                        add_state = function(unit)
                            unit:add_state(y3.const.UnitEnumState['禁止移动'])
                        end,
                        remove_state = function(unit)
                            unit:remove_state(y3.const.UnitEnumState['禁止移动'])
                        end,
                    })
                    if lease then
                        self:_track_control_lease(actor, lifecycle_id, lease)
                    end
                end
            end
        end
    end
end

function Adapter:set_combo_floor(actor, stage, duration, context)
    if type(self.options.on_combo_floor) == 'function' then
        self.options.on_combo_floor(actor, stage, duration, context)
    end
end

function Adapter:heal_and_guard(actor, command, context)
    local unit = self:_unit(actor)
    if not unit or not unit:is_exist() then
        return
    end
    unit:add_hp(unit:get_attr('最大生命') * command.heal_max_hp)
    self:apply_effect(actor, {
        type = 'apply_modifier',
        key = 'C01_M07_SHOUYI_GUARD',
        target_scope = 'self',
        duration = command.duration,
        payload = {
            damage_reduction = command.damage_reduction,
            damage_reduction_category = command.damage_reduction_category
                or reduction_categories.C01_M07_SHOUYI_GUARD,
        },
    }, context)
end

function Adapter:_set_state_buff(actor, modifier_key, enabled, duration)
    local unit = self:_unit(actor)
    local buff_id = self.modifier_ids[modifier_key]
    if not unit or not unit:is_exist() or not buff_id then
        return
    end
    local buff = unit:find_buff(buff_id)
    if enabled then
        if buff then
            if duration then
                buff:set_time(duration)
            end
        else
            unit:add_buff({ key = buff_id, source = unit, time = duration or -1, stacks = 1 })
        end
    elseif buff then
        buff:remove()
    end
end

function Adapter:state_changed(actor, event, context)
    context = context or {}
    if event.dongming ~= nil then
        self:_set_state_buff(actor, 'C01_M01_DONGMING', event.dongming)
    elseif event.momentum ~= nil then
        self:_set_state_buff(actor, 'C01_M01_DONGMING', event.momentum >= 80)
    end
    if event.type == 'ultimate_activated' then
        local now = context.now or y3.game.current_game_run_time()
        self:_set_state_buff(actor, 'C01_M12_ZHENJING', true, event.expires_at - now)
    elseif event.type == 'transient_cleared' then
        self:_set_state_buff(actor, 'C01_M01_DONGMING', false)
        self:_set_state_buff(actor, 'C01_M12_ZHENJING', false)
        self:cancel_actor_timers(actor, context.lifecycle_id)
        local actor_unit = self:_unit(actor) or context.unit
        local affected_targets = {}
        for key, entry in pairs(self.effects) do
            if entry.actor == actor or entry.target == actor_unit then
                self:_remove_contribution(entry)
                self.effects[key] = nil
                affected_targets[#affected_targets + 1] = entry.target
            end
        end
        for _, target in ipairs(affected_targets) do
            self:_recompute_damage_reduction(target)
        end
    end
    if type(self.options.on_state_changed) == 'function' then
        self.options.on_state_changed(actor, event, context)
    end
end

return M
