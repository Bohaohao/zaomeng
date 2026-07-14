package.path = 'implementation/profession_common/lua/?.lua;implementation/chiming/lua/?.lua;' .. package.path

local Adapter = require 'chiming_y3_adapter'
local Targeting = require 'chiming_y3_targeting'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local timers = {}
local function make_unit(id, owner)
    local unit = {
        id = id, owner = owner or 'enemy', exists = true, alive = true, damage_calls = 0,
        attrs = { ['最大生命'] = 100, ['生命'] = 100 }, buffs = {}, states = {}, added_buffs = {},
    }
    function unit:get_id() return self.id end
    function unit:is_exist() return self.exists end
    function unit:is_alive() return self.alive end
    function unit:get_owner() return self.owner end
    function unit:get_point() return { id = self.id } end
    function unit:get_facing() return 0 end
    function unit:get_attr(name) return self.attrs[name] or 0 end
    function unit:set_attr(name, value) self.attrs[name] = value end
    function unit:add_attr(name, amount) self.attrs[name] = (self.attrs[name] or 0) + amount end
    function unit:add_hp(amount) self.attrs['生命'] = self.attrs['生命'] + amount end
    function unit:add_state(state) self.states[state] = (self.states[state] or 0) + 1 end
    function unit:remove_state(state) self.states[state] = math.max(0, (self.states[state] or 0) - 1) end
    function unit:find_buff(key) return self.buffs[key] end
    function unit:add_buff(data)
        local buff = { key = data.key, time = data.time, data = data.data, removed = false }
        function buff:set_time(time) self.time = time end
        function buff:set_shield(value) self.shield = value end
        function buff:remove() self.removed = true end
        self.buffs[data.key] = buff
        self.added_buffs[#self.added_buffs + 1] = buff
        return buff
    end
    function unit:find_ability() return nil end
    function unit:damage() self.damage_calls = self.damage_calls + 1 end
    return unit
end

_G.y3 = {
    timer = { wait = function(delay, callback, description)
        local timer = { delay = delay, callback = callback, description = description }
        function timer:remove() self.removed = true end
        timers[#timers + 1] = timer
        return timer
    end },
    game = { current_game_run_time = function() return 0 end },
    const = { UnitEnumState = { ['无敌'] = 1, ['禁止移动'] = 2 } },
    shape = {
        create_circular_shape = function(radius) return { shape = 'circle', radius = radius } end,
        create_rectangle_shape = function(width, length, angle) return { shape = 'rectangle', width = width, length = length, angle = angle } end,
        create_sector_shape = function(radius, angle, facing) return { shape = 'sector', radius = radius, angle = angle, facing = facing } end,
    },
    point = { get_point_offset_vector = function(point) return point end },
    selector = { create = function()
        local selector = {}
        function selector:in_shape() return self end
        function selector:in_range() return self end
        function selector:is_enemy() return self end
        function selector:is_ally() return self end
        function selector:not_in_state() return self end
        function selector:without_tag() return self end
        function selector:pick() return {} end
        return selector
    end },
}

local hero = make_unit('hero', 'ally')
local hero2 = make_unit('hero2', 'ally')
local ally = make_unit('ally', 'ally')
local enemy = make_unit('enemy', 'enemy')
local boss = make_unit('boss', 'enemy')
local units = { hero = hero, hero2 = hero2, ally = ally, enemy = enemy, boss = boss }

local break_calls, contributions = 0, {}
local adapter = Adapter.new {
    unit_by_actor = function(actor_id) return units[actor_id] end,
    modifier_ids = {
        C03_M02_MINGHEN = 9002, C03_M03_CHENGXIN_SHIELD = 9003, C03_M06_LUYIN = 9006,
        C03_M08_TONGMING_SHIELD = 9008, C03_M09_JINGLV_ZHENYA = 9009, C03_M10_TONGLV_QINGMING = 9010,
    },
    apply_break = function() break_calls = break_calls + 1; return { actual_break = true, value = 2.3 } end,
    resolve_boss_context = function() return { boss_instance_id = 'boss-1', phase_id = 'p1', event_id = 'break-1' } end,
}
adapter:set_contribution_sink(function(item) contributions[#contributions + 1] = item end)

do
    adapter:apply_effect('hero', {
        type = 'apply_modifier', key = 'C03_M03_CHENGXIN_SHIELD', target_scope = 'self', duration = 4,
        payload = { max_hp_ratio = 0.10 },
    }, { unit = hero, unit_id = 'hero', target_refs_by_id = { hero = hero, enemy = enemy }, now = 0 })
    equal(hero.added_buffs[#hero.added_buffs].shield, 10, 'self shield uses the caster maximum health')
    equal(#enemy.added_buffs, 0, 'self buff cannot fall through to an enemy')

    adapter:apply_effect('hero', {
        type = 'apply_modifier', key = 'C03_M02_MINGHEN', target_scope = 'primary', duration = 5, payload = {},
    }, { unit = hero, unit_id = 'hero', primary_target_id = 'enemy', primary_target_ref = enemy,
        target_refs_by_id = { enemy = enemy }, now = 0 })
    equal(#enemy.added_buffs, 1, 'primary effect needs the explicit locked primary')
    adapter:apply_effect('hero', {
        type = 'apply_modifier', key = 'C03_M02_MINGHEN', target_scope = 'primary', duration = 5, payload = {},
    }, { unit = hero, unit_id = 'hero', target = enemy, target_refs_by_id = { enemy = enemy }, now = 0 })
    equal(#enemy.added_buffs, 1, 'primary effect ignores an unbound generic context target')
end

do
    adapter:apply_effect('hero', {
        type = 'apply_modifier', key = 'C03_M06_LUYIN', target_scope = 'explicit', target_id = 'enemy', target = enemy,
        duration = 5, payload = {},
    }, { unit = hero, now = 0 })
    adapter:apply_effect('hero2', {
        type = 'apply_modifier', key = 'C03_M06_LUYIN', target_scope = 'explicit', target_id = 'enemy', target = enemy,
        duration = 5, payload = {},
    }, { unit = hero2, now = 0 })
    local first = adapter.buff_instances['enemy:C03_M06_LUYIN:hero']
    local second = adapter.buff_instances['enemy:C03_M06_LUYIN:hero2']
    truthy(first ~= nil and second ~= nil and first ~= second, 'source-bound M06 has one physical handle per caster')
    adapter:apply_effect('hero', {
        type = 'remove_modifier', key = 'C03_M06_LUYIN', target_scope = 'explicit', target_id = 'enemy', target = enemy,
    }, { unit = hero, now = 1 })
    truthy(first.removed, 'one source can remove its M06 handle')
    truthy(not second.removed, 'one source cannot remove another M06 handle')
end

do
    adapter:deal_damage('hero', { type = 'damage', target_scope = 'selected', coefficient = 1 }, {
        unit = hero, targets = { enemy }, target_refs_by_id = { enemy = enemy }, now = 0,
    })
    equal(hero.damage_calls, 0, 'selected damage does not fall back to generic context.targets')
    adapter:deal_damage('hero', { type = 'damage', target_scope = 'selected', coefficient = 1 }, {
        unit = hero, selected_target_ids = { 'enemy' }, selected_targets = { enemy }, target_refs_by_id = { enemy = enemy }, now = 0,
    })
    equal(hero.damage_calls, 1, 'selected damage uses an explicit selection snapshot')
end

do
    adapter:apply_control('hero', {
        type = 'control', target_scope = 'explicit', target_id = 'enemy', target = enemy,
        normal_duration = 1, elite_duration = 0.5,
    }, { unit = hero, lifecycle_id = 1, target_meta_by_id = { enemy = { rank = 'unknown' } } })
    equal(enemy.states[2] or 0, 0, 'unknown rank cannot receive control')
    adapter:apply_control('hero', {
        type = 'control', target_scope = 'explicit', target_id = 'enemy', target = enemy,
        normal_duration = 1, elite_duration = 0.5, cast_id = 3,
    }, { unit = hero, lifecycle_id = 1, target_meta_by_id = { enemy = { rank = 'normal' } } })
    equal(enemy.states[2], 1, 'normal rank receives a control lease')
    adapter:cancel_actor_timers('hero', 1)
    equal(enemy.states[2], 0, 'lifecycle cancellation releases only the caster control lease')
end

do
    local command = {
        type = 'break', target_scope = 'explicit', target_id = 'boss', target = boss, break_value = 2.3,
        break_scope = 'boss_confirmed', break_event_key = 'a08-impact', cast_id = 9,
    }
    adapter:apply_break('hero', command, { unit = hero, lifecycle_id = 1, skill_key = 'C03_A08', target_meta_by_id = { boss = { rank = 'boss' } } })
    adapter:apply_break('hero', command, { unit = hero, lifecycle_id = 1, skill_key = 'C03_A08', target_meta_by_id = { boss = { rank = 'boss' } } })
    equal(break_calls, 1, 'break ledger rejects a replayed cast event')
    equal(#contributions, 1, 'accepted break reports one contribution event')
    adapter:apply_break('hero', {
        type = 'break', target_scope = 'explicit', target_id = 'enemy', target = enemy, break_value = 1,
        break_scope = 'boss_confirmed', break_event_key = 'unknown', cast_id = 10,
    }, { unit = hero, lifecycle_id = 1, skill_key = 'C03_A08', target_meta_by_id = { enemy = { rank = 'unknown' } } })
    equal(break_calls, 1, 'unknown rank cannot become an implicit boss break')
end

do
    local no_pulse = Adapter.new { unit_by_actor = function(actor_id) return units[actor_id] end }
    no_pulse:schedule_damage('hero', {
        type = 'delayed_damage', target_scope = 'selected', pulse_key = 'C03_A05', delay = 0.1, coefficient = 1,
    }, { unit = hero, lifecycle_id = 11, selected_targets = { enemy }, selected_target_ids = { 'enemy' } })
    local timer = timers[#timers]
    timer.callback()
    equal(hero.damage_calls, 1, 'missing pulse resolver leaves a pulse without targets')

    local pulse = Adapter.new {
        unit_by_actor = function(actor_id) return units[actor_id] end,
        resolve_pulse_targets = function()
            return { targets = { enemy }, target_meta_by_id = { enemy = { rank = 'normal' } } }
        end,
    }
    pulse:schedule_damage('hero', {
        type = 'delayed_damage', target_scope = 'selected', pulse_key = 'C03_A05', delay = 0.1, coefficient = 1,
    }, { unit = hero, lifecycle_id = 12 })
    timer = timers[#timers]
    timer.callback()
    equal(hero.damage_calls, 2, 'pulse damage uses a freshly resolved selected snapshot')
end

do
    local targeting = Targeting.new {}
    local missing = targeting:build_context({ get_effect = function() return nil end, get_state = function() return { seals = 3 } end },
        'hero', 'C03_A03', 1, hero, {}, {})
    equal(missing.cast_error, 'primary-target-required', 'A03 refuses a geometry-derived primary target')

    targeting = Targeting.new {
        resolve_primary_target = function() return enemy end,
        resolve_cast_point = function() return { id = 'point' } end,
        resolve_team_members = function() return { hero, ally } end,
        resolve_team_purge = function()
            return {
                targets = { ally, enemy },
                boss_contribution = { kind = 'purge_mechanic', target_id = 'ally', mechanic_id = 'drowning', alternative_resolution = 'dodge' },
            }
        end,
        target_rank = function(target) return target.id == 'enemy' and 'elite' or nil end,
    }
    local runtime = {
        get_state = function() return { seals = 3 } end,
        get_effect = function() return nil end,
    }
    local a03 = targeting:build_context(runtime, 'hero', 'C03_A03', 5, hero, {}, {})
    equal(a03.primary_target_id, 'enemy', 'primary resolver writes a stable Unit ID')
    equal(a03.target_meta_by_id.enemy.rank, 'elite', 'only a valid resolver rank becomes elite')
    local a05 = targeting:build_context(runtime, 'hero', 'C03_A05', 5, hero, {}, {})
    equal(#a05.selected_target_ids, 0, 'A05 no longer captures a generic cast-time area list')
    local a08 = targeting:build_context(runtime, 'hero', 'C03_A08', 5, hero, {}, {})
    equal(a08.team_target_ids[1], 'ally', 'team resolver excludes the caster')
    equal(a08.team_purge_success_ids[1], 'ally', 'purge intersects the cast snapshot and removes outsiders')
    equal(#a08.team_purge_success_ids, 1, 'purge result is deduplicated')
    equal(a08.boss_contributions[1].target_id, 'ally', 'only a legal team purge report survives')
end

print('PASS: ' .. tests .. ' bridge targeting assertions')
