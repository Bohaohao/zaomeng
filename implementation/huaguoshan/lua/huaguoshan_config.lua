-- Offline source-of-truth snapshot for the Huaguoshan encounter bridge.
-- Logical resource keys intentionally match the 96x72 whitebox layout.
local M = {}

M.layout_contract = {
    id = 'huaguoshan-96x72-runtime-v1',
    source_layout = 'docs/归档/地图设计/terrain/huaguoshan-96x72/layout.json',
    editor_bound = false,
}

M.resources = {
    pt_hg_spawn = { source = 'logic_resource', expected_type = 'point' },
    pt_hg_teleport_city = { source = 'logic_resource', expected_type = 'point' },
    pt_hg_teleport_hub = { source = 'logic_resource', expected_type = 'point' },
    pt_hg_teleport_team = { source = 'logic_resource', expected_type = 'point' },
    pt_longgong_entry = { source = 'logic_resource', expected_type = 'point' },
    pt_fire_dungeon_entry = { source = 'logic_resource', expected_type = 'point' },
    pt_east_sea_anchor = { source = 'logic_resource', expected_type = 'point' },
    pt_hg_wind_eye_slot = { source = 'logic_resource', expected_type = 'point' },
    pt_hg_tide_eye_slot = { source = 'logic_resource', expected_type = 'point' },
    pt_hg_vortex_anchor_slot = { source = 'logic_resource', expected_type = 'point' },
    spawn_trace_tide_guard = { source = 'logic_resource', expected_type = 'point' },
    pt_hg_tide_trace_stone = { source = 'logic_resource', expected_type = 'point' },
    spawn_trace_vortex_node = { source = 'logic_resource', expected_type = 'point' },
    pt_hg_vortex_trace_anchor = { source = 'logic_resource', expected_type = 'point' },

    path_hg_main = { source = 'logic_resource', expected_type = 'path' },
    path_hg_peach = { source = 'logic_resource', expected_type = 'path' },
    path_hg_bat = { source = 'logic_resource', expected_type = 'path' },

    area_hg_public_mountain = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_public_waterfall = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_main_route_waterfall = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_boss_mihou = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_public_peach = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_public_bat = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_public_sevenstar = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_main_route_sevenstar = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_elite_garuda = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_public_east_sea = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_main_route_east_sea = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_boss_jiao = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_boss_shark = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_tide_trace_interact = { source = 'logic_resource', expected_type = 'circleArea' },
    area_hg_wind_eye_interact = { source = 'logic_resource', expected_type = 'circleArea' },
    area_hg_tide_eye_interact = { source = 'logic_resource', expected_type = 'circleArea' },
    area_hg_vortex_anchor_interact = { source = 'logic_resource', expected_type = 'circleArea' },
    area_hg_vortex_trace_interact = { source = 'logic_resource', expected_type = 'circleArea' },
    area_hg_shark_anchor_safe_line = { source = 'logic_resource', expected_type = 'rectArea' },
    area_hg_shark_vortex_core = { source = 'logic_resource', expected_type = 'circleArea' },

    spawn_mountain_monkey_a = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_stone_beast_a = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_vine_imp_a = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_monkey_leader = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_water_imp = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_spring_spirit = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_fish_sentry = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_water_guard = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_peach_demon = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_agile_monkey = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_cave_bat = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_cave_imp = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_sevenstar_demon = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_mandrill_shaman = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_winged_demon = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_bull_scout = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_fish_patrol = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_turtle_guard = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_water_shaman = { source = 'spawn', expected_type = 'spawn_anchor' },
    spawn_vortex_soldier = { source = 'spawn', expected_type = 'spawn_anchor' },

    arena_gorilla = { source = 'boss_zone', expected_type = 'boss_zone' },
    arena_mihouwang = { source = 'boss_zone', expected_type = 'boss_zone' },
    arena_yurongwang = { source = 'boss_zone', expected_type = 'boss_zone' },
    arena_bat_statue = { source = 'boss_zone', expected_type = 'boss_zone' },
    arena_lion = { source = 'boss_zone', expected_type = 'boss_zone' },
    arena_peng = { source = 'boss_zone', expected_type = 'boss_zone' },
    arena_jiaomowang_phase1 = { source = 'boss_zone', expected_type = 'boss_zone' },
    arena_shamowang_phase1 = { source = 'boss_zone', expected_type = 'boss_zone' },
}

local function spawn(anchor, unit_key, category)
    return { anchor = anchor, unit_key = unit_key, category = category or 'normal' }
end

M.encounters = {
    HG_E_MOUNTAIN_PATH = {
        encounter_type = 'public_zone', combat_scope = 'public',
        resources = { 'area_hg_public_mountain', 'path_hg_main', 'arena_gorilla' },
        main_route_overlap = 'forbidden',
        spawn_plan = {
            spawn('spawn_mountain_monkey_a', 'HG_U_MOUNTAIN_MONKEY'),
            spawn('spawn_stone_beast_a', 'HG_U_STONEHIDE_BEAST'),
            spawn('spawn_vine_imp_a', 'HG_U_VINE_IMP'),
            spawn('spawn_monkey_leader', 'HG_U_MONKEY_PACK_LEADER', 'elite'),
            spawn('arena_gorilla', 'HG_U_GREAT_APE', 'major_elite'),
        },
    },
    HG_E_WATERFALL_PATH = {
        encounter_type = 'public_zone', combat_scope = 'public',
        resources = { 'area_hg_public_waterfall', 'area_hg_main_route_waterfall' },
        main_route_overlap = 'forbidden',
        spawn_plan = {
            spawn('spawn_water_imp', 'HG_U_WATERFALL_IMP'),
            spawn('spawn_spring_spirit', 'HG_U_SPRING_SPIRIT'),
            spawn('spawn_fish_sentry', 'HG_U_FISH_SENTINEL'),
            spawn('spawn_water_guard', 'HG_U_WATERFALL_GUARD', 'elite'),
        },
    },
    HG_E_TIDE_TRACE = {
        encounter_type = 'public_trace', combat_scope = 'public',
        resources = { 'spawn_trace_tide_guard', 'pt_hg_tide_trace_stone', 'area_hg_tide_trace_interact' },
        spawn_plan = { spawn('spawn_trace_tide_guard', 'HG_U_TIDE_TRACE_GUARD', 'trace') },
        action = {
            key = 'stabilize_tide_trace', area = 'area_hg_tide_trace_interact', anchor = 'pt_hg_tide_trace_stone',
            radius_cells = 2, max_concurrent = 4, read_seconds = 2, postlude_seconds = 30,
        },
    },
    HG_E_MACAQUE_KING = {
        encounter_type = 'public_boss', combat_scope = 'public',
        resources = { 'arena_mihouwang', 'area_hg_boss_mihou', 'pt_hg_wind_eye_slot', 'area_hg_wind_eye_interact' },
        boss_unit_key = 'HG_U_MACAQUE_KING', boss_spawn_anchor = 'arena_mihouwang', respawn_seconds = 600,
        break_profile = { threshold = 8, window_seconds = 4 },
        action = {
            key = 'stabilize_wind_eye', area = 'area_hg_wind_eye_interact', anchor = 'pt_hg_wind_eye_slot',
            radius_cells = 3, max_concurrent = 4, read_seconds = 2, window_seconds = 8,
        },
        phase = { clone_count = 2, clone_duration_seconds = 2.5, frenzy_at_hp = 0.30 },
    },
    HG_E_PEACH_GROVE = {
        encounter_type = 'public_zone', combat_scope = 'public',
        resources = { 'area_hg_public_peach', 'path_hg_peach', 'arena_yurongwang' }, main_route_overlap = 'forbidden',
        spawn_plan = {
            spawn('spawn_peach_demon', 'HG_U_PEACH_SPIRIT'),
            spawn('spawn_agile_monkey', 'HG_U_MIST_MONKEY'),
            spawn('arena_yurongwang', 'HG_U_YURONG_KING', 'major_elite'),
        },
    },
    HG_E_BAT_CAVE = {
        encounter_type = 'public_zone', combat_scope = 'public',
        resources = { 'area_hg_public_bat', 'path_hg_bat', 'arena_bat_statue' }, exit_blocking = 'forbidden',
        spawn_plan = {
            spawn('spawn_cave_bat', 'HG_U_CAVE_BAT'),
            spawn('spawn_cave_imp', 'HG_U_CAVE_IMP'),
            spawn('arena_bat_statue', 'HG_U_BAT_STATUE', 'major_elite'),
        },
    },
    HG_E_SEVENSTAR_PATH = {
        encounter_type = 'public_zone', combat_scope = 'public',
        resources = { 'area_hg_public_sevenstar', 'area_hg_main_route_sevenstar', 'arena_lion' }, main_route_overlap = 'forbidden',
        spawn_plan = {
            spawn('spawn_sevenstar_demon', 'HG_U_SEVENSTAR_DEMON'),
            spawn('spawn_mandrill_shaman', 'HG_U_SHANXIAO_CASTER'),
            spawn('spawn_winged_demon', 'HG_U_WINGED_DEMON'),
            spawn('spawn_bull_scout', 'HG_U_BULL_SCOUT', 'elite'),
            spawn('arena_lion', 'HG_U_LION_CAMEL_KING', 'major_elite'),
        },
    },
    HG_E_PENG_SIDE = {
        encounter_type = 'public_elite', combat_scope = 'public',
        resources = { 'arena_peng', 'area_hg_elite_garuda' },
        spawn_plan = { spawn('arena_peng', 'HG_U_PENG_KING', 'major_elite') }, optional = true,
    },
    HG_E_EASTSEA_PATH = {
        encounter_type = 'public_zone', combat_scope = 'public',
        resources = { 'area_hg_public_east_sea', 'area_hg_main_route_east_sea', 'pt_east_sea_anchor' }, main_route_overlap = 'forbidden',
        spawn_plan = {
            spawn('spawn_fish_patrol', 'HG_U_FISH_PATROLLER'),
            spawn('spawn_turtle_guard', 'HG_U_TURTLE_GUARD'),
            spawn('spawn_water_shaman', 'HG_U_WATER_MAGE'),
            spawn('spawn_vortex_soldier', 'HG_U_VORTEX_SOLDIER', 'elite'),
        },
    },
    HG_E_RIPTIDE_NODE = {
        encounter_type = 'public_trace', combat_scope = 'public',
        resources = { 'spawn_trace_vortex_node', 'pt_hg_vortex_trace_anchor', 'area_hg_vortex_trace_interact' },
        spawn_plan = { spawn('spawn_trace_vortex_node', 'HG_U_RIPTIDE_NODE_SOLDIER', 'trace') },
        action = {
            key = 'seal_vortex', area = 'area_hg_vortex_trace_interact', anchor = 'pt_hg_vortex_trace_anchor',
            radius_cells = 2, max_concurrent = 4, read_seconds = 2, postlude_seconds = 30,
        },
    },
    HG_E_JIAO_KING = {
        encounter_type = 'public_boss', combat_scope = 'public',
        resources = { 'arena_jiaomowang_phase1', 'area_hg_boss_jiao', 'pt_hg_tide_eye_slot', 'area_hg_tide_eye_interact' },
        boss_unit_key = 'HG_U_JIAO_KING_P1', boss_spawn_anchor = 'arena_jiaomowang_phase1', respawn_seconds = 720,
        break_profile = { threshold = 12, window_seconds = 4 },
        action = {
            key = 'drain_tide_eye', area = 'area_hg_tide_eye_interact', anchor = 'pt_hg_tide_eye_slot',
            radius_cells = 3, max_concurrent = 4, read_seconds = 2, window_seconds = 8,
        },
        phase = { submerge_seconds = 3 },
        mechanic = { key = 'HG_BOSS_WATER_CHAIN', resolutions = { purge_mechanic = true, drain_tide_eye = true, leave_tide_lane = true } },
    },
    HG_E_SHARK_KING = {
        encounter_type = 'public_boss', combat_scope = 'public',
        resources = { 'arena_shamowang_phase1', 'area_hg_boss_shark', 'pt_hg_vortex_anchor_slot', 'area_hg_vortex_anchor_interact', 'area_hg_shark_anchor_safe_line', 'area_hg_shark_vortex_core' },
        boss_unit_key = 'HG_U_SHARK_KING_P1', boss_spawn_anchor = 'arena_shamowang_phase1', respawn_seconds = 720,
        break_profile = { threshold = 16, window_seconds = 4 },
        action = {
            key = 'stabilize_vortex_anchor', area = 'area_hg_vortex_anchor_interact', anchor = 'pt_hg_vortex_anchor_slot',
            radius_cells = 3, max_concurrent = 4, read_seconds = 2, window_seconds = 8, safe_line_required = true,
        },
        phase = { frenzy_at_hp = 0.30 },
    },
    HG_E_DRAGON_OLD_TIDE = {
        encounter_type = 'solo_boss', combat_scope = 'solo_instance',
        resources = { 'pt_longgong_entry', 'pt_hg_teleport_hub' },
        deadline_seconds = 720, return_point = 'pt_hg_teleport_hub', boss_unit_key = 'HG_U_DRAGON_KING_P1',
        break_profile = { threshold = 11, window_seconds = 4 },
        unlock_rule = 'longgong_discovered_and_level_at_least_8',
        instance_map_contract = 'pending',
        instance_map_contract_key = 'HG_I_DRAGON_FOUR_SEAS',
    },
    HG_E_DRAGON_REVERSE_TIDE = {
        encounter_type = 'solo_boss', combat_scope = 'solo_instance',
        resources = { 'pt_longgong_entry', 'pt_hg_teleport_hub' },
        deadline_seconds = 900, return_point = 'pt_hg_teleport_hub', boss_unit_key = 'HG_U_DRAGON_KING_P2',
        break_profile = { threshold = 18, window_seconds = 3.5 },
        unlock_rule = 'level_at_least_38_and_underworld_late_progress',
        instance_map_contract = 'pending',
        instance_map_contract_key = 'HG_I_DRAGON_FOUR_SEAS',
    },
    HG_E_OX_BATTLEFIELD = {
        encounter_type = 'team_boss', combat_scope = 'team_instance',
        resources = { 'pt_fire_dungeon_entry', 'pt_hg_teleport_team' }, max_members = 4,
        deadline_seconds = 1200, return_point = 'pt_hg_teleport_team',
        phases = {
            { id = 'human', boss_unit_key = 'HG_U_OX_KING_HUMAN', break_profile = { threshold = 20, window_seconds = 4 } },
            { id = 'white_ox', boss_unit_key = 'HG_U_ARMORED_WHITE_OX', break_profile = { threshold = 24, window_seconds = 4 } },
        },
        failure_modifier = 'HG_M_OX_ARROGANCE', rage_duration_seconds = 300, rage_per_layer = 0.05,
        instance_map_contract = 'pending',
        instance_map_contract_key = 'HG_I_OX_BATTLEFIELD',
    },
}

-- Resource roles are part of the encounter contract, not display-only labels.
-- build_map_binding_projection exports them for JSON parity and preflight validation.
M.encounter_resource_roles = {
    HG_E_MOUNTAIN_PATH = {
        area_hg_public_mountain = 'public_area',
        path_hg_main = 'main_route_exclusion',
        arena_gorilla = 'major_elite_anchor',
    },
    HG_E_WATERFALL_PATH = {
        area_hg_public_waterfall = 'public_area',
        area_hg_main_route_waterfall = 'main_route_exclusion',
    },
    HG_E_TIDE_TRACE = {
        spawn_trace_tide_guard = 'trace_carrier_anchor',
        pt_hg_tide_trace_stone = 'interaction_anchor',
        area_hg_tide_trace_interact = 'interaction_area',
    },
    HG_E_MACAQUE_KING = {
        arena_mihouwang = 'boss_arena',
        area_hg_boss_mihou = 'boss_pocket',
        pt_hg_wind_eye_slot = 'interaction_anchor',
        area_hg_wind_eye_interact = 'interaction_area',
    },
    HG_E_PEACH_GROVE = {
        area_hg_public_peach = 'public_area',
        path_hg_peach = 'main_route_exclusion',
        arena_yurongwang = 'major_elite_anchor',
    },
    HG_E_BAT_CAVE = {
        area_hg_public_bat = 'public_area',
        path_hg_bat = 'exit_path',
        arena_bat_statue = 'major_elite_anchor',
    },
    HG_E_SEVENSTAR_PATH = {
        area_hg_public_sevenstar = 'public_area',
        area_hg_main_route_sevenstar = 'main_route_exclusion',
        arena_lion = 'major_elite_anchor',
    },
    HG_E_PENG_SIDE = {
        arena_peng = 'optional_elite_arena',
        area_hg_elite_garuda = 'optional_elite_pocket',
    },
    HG_E_EASTSEA_PATH = {
        area_hg_public_east_sea = 'public_area',
        area_hg_main_route_east_sea = 'main_route_exclusion',
        pt_east_sea_anchor = 'future_east_sea_anchor',
    },
    HG_E_RIPTIDE_NODE = {
        spawn_trace_vortex_node = 'trace_carrier_anchor',
        pt_hg_vortex_trace_anchor = 'interaction_anchor',
        area_hg_vortex_trace_interact = 'interaction_area',
    },
    HG_E_JIAO_KING = {
        arena_jiaomowang_phase1 = 'boss_arena',
        area_hg_boss_jiao = 'boss_pocket',
        pt_hg_tide_eye_slot = 'interaction_anchor',
        area_hg_tide_eye_interact = 'interaction_area',
    },
    HG_E_SHARK_KING = {
        arena_shamowang_phase1 = 'boss_arena',
        area_hg_boss_shark = 'boss_pocket',
        pt_hg_vortex_anchor_slot = 'interaction_anchor',
        area_hg_vortex_anchor_interact = 'interaction_area',
        area_hg_shark_anchor_safe_line = 'required_safe_line',
        area_hg_shark_vortex_core = 'forbidden_vortex_core',
    },
    HG_E_DRAGON_OLD_TIDE = {
        pt_longgong_entry = 'entry_point',
        pt_hg_teleport_hub = 'failure_return',
    },
    HG_E_DRAGON_REVERSE_TIDE = {
        pt_longgong_entry = 'entry_point',
        pt_hg_teleport_hub = 'failure_return',
    },
    HG_E_OX_BATTLEFIELD = {
        pt_fire_dungeon_entry = 'entry_point',
        pt_hg_teleport_team = 'failure_return',
    },
}

M.return_points = {
    spawn = 'pt_hg_spawn', city = 'pt_hg_teleport_city', hub = 'pt_hg_teleport_hub', team = 'pt_hg_teleport_team',
}

local function instance_role(role, resource_key, expected_type, layer)
    return {
        role = role,
        resource_key = resource_key,
        source = 'instance_logic_resource',
        expected_type = expected_type,
        layer = layer,
        stable_object_id = false,
    }
end

local function dragon_instance_slots(prefix)
    local schema = M.instance_contract_role_schema.HG_I_DRAGON_FOUR_SEAS
    local slots = {}
    for slot_id = 1, 4 do
        local slot_prefix = prefix .. '_slot_' .. tostring(slot_id)
        slots[#slots + 1] = {
            slot_id = slot_id,
            roles = {
                instance_role('slot_bounds', 'area_' .. slot_prefix .. '_bounds', schema.roles.slot_bounds, schema.layer),
                instance_role('slot_spawn', 'pt_' .. slot_prefix .. '_spawn', schema.roles.slot_spawn, schema.layer),
                instance_role('boss_arena', 'area_' .. slot_prefix .. '_boss_arena', schema.roles.boss_arena, schema.layer),
                instance_role('return_exit', 'pt_' .. slot_prefix .. '_return_exit', schema.roles.return_exit, schema.layer),
            },
        }
    end
    return slots
end

-- These are future role blueprints, not claimed editor bindings. A false
-- stable_object_id is explicit pending state and is invalid for a verified contract.
M.instance_contract_role_schema = {
    HG_I_DRAGON_FOUR_SEAS = {
        layer = 'four_seas',
        slot_count = 4,
        roles = {
            slot_bounds = 'rectArea',
            slot_spawn = 'point',
            boss_arena = 'rectArea',
            return_exit = 'point',
        },
    },
    HG_I_OX_BATTLEFIELD = {
        layer = 'dream_realm',
        slot_count = 1,
        roles = {
            raid_bounds = 'rectArea',
            member_spawn = 'point',
            boss_arena = 'rectArea',
            return_exit = 'point',
        },
    },
}

local dragon_instance_schema = M.instance_contract_role_schema.HG_I_DRAGON_FOUR_SEAS
local ox_instance_schema = M.instance_contract_role_schema.HG_I_OX_BATTLEFIELD

M.instance_map_contracts = {
    HG_I_DRAGON_FOUR_SEAS = {
        state = 'pending', layer = dragon_instance_schema.layer, slot_count = dragon_instance_schema.slot_count,
        encounter_keys = { 'HG_E_DRAGON_OLD_TIDE', 'HG_E_DRAGON_REVERSE_TIDE' },
        slots = dragon_instance_slots('hg_dragon_four_seas'),
    },
    HG_I_OX_BATTLEFIELD = {
        state = 'pending', layer = ox_instance_schema.layer, slot_count = ox_instance_schema.slot_count,
        encounter_keys = { 'HG_E_OX_BATTLEFIELD' },
        slots = {
            {
                slot_id = 1,
                roles = {
                    instance_role('raid_bounds', 'area_hg_ox_battlefield_raid_bounds', ox_instance_schema.roles.raid_bounds, ox_instance_schema.layer),
                    instance_role('member_spawn', 'pt_hg_ox_battlefield_member_spawn', ox_instance_schema.roles.member_spawn, ox_instance_schema.layer),
                    instance_role('boss_arena', 'area_hg_ox_battlefield_boss_arena', ox_instance_schema.roles.boss_arena, ox_instance_schema.layer),
                    instance_role('return_exit', 'pt_hg_ox_battlefield_return_exit', ox_instance_schema.roles.return_exit, ox_instance_schema.layer),
                },
            },
        },
    },
}

local function sorted_keys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function copy_instance_role_schema(schema)
    local result = {}
    for _, contract_key in ipairs(sorted_keys(schema)) do
        local definition = schema[contract_key]
        local roles = {}
        for _, role in ipairs(sorted_keys(definition.roles or {})) do
            roles[#roles + 1] = {
                role = role,
                expected_type = definition.roles[role],
            }
        end
        result[#result + 1] = {
            contract_key = contract_key,
            layer = definition.layer,
            slot_count = definition.slot_count,
            roles = roles,
        }
    end
    return result
end

local function copy_array(values)
    local result = {}
    for index, value in ipairs(values or {}) do result[index] = value end
    return result
end

local function copy_instance_slots(slots)
    local result = {}
    for _, slot in ipairs(slots or {}) do
        local slot_copy = { slot_id = slot.slot_id, roles = {} }
        for _, role in ipairs(slot.roles or {}) do
            slot_copy.roles[#slot_copy.roles + 1] = {
                role = role.role,
                resource_key = role.resource_key,
                source = role.source,
                expected_type = role.expected_type,
                layer = role.layer,
                stable_object_id = role.stable_object_id,
            }
        end
        result[#result + 1] = slot_copy
    end
    return result
end

local function compact_action(action, encounter_key)
    if not action then return nil end
    local result = {
        encounter_key = encounter_key,
        action_key = action.key,
        area_key = action.area,
        anchor_key = action.anchor,
        radius_cells = action.radius_cells,
        max_concurrent = action.max_concurrent,
        read_seconds = action.read_seconds,
    }
    if action.window_seconds then result.window_seconds = action.window_seconds end
    if action.postlude_seconds then result.postlude_seconds = action.postlude_seconds end
    if action.safe_line_required then
        result.required_inside_area_key = 'area_hg_shark_anchor_safe_line'
        result.required_outside_area_key = 'area_hg_shark_vortex_core'
    end
    return result
end

local function projected_instance_slot_count(encounter_key, encounter)
    if encounter.instance_slots ~= nil then
        error(encounter_key .. ' instance_slots must not be declared; derive it from instance_map_contracts.slot_count')
    end
    local contract_key = encounter.instance_map_contract_key
    local contract = contract_key and M.instance_map_contracts[contract_key]
    if not contract then
        error(encounter_key .. ' has no declared instance map contract')
    end
    return contract.slot_count
end

-- A complete runtime-facing projection. The PowerShell parity test compares this
-- projection with map-logic-binding.json so the JSON cannot silently drift from Lua.
function M.build_map_binding_projection()
    local projection = {
        runtime_contract_id = M.layout_contract.id,
        editor_bound = M.layout_contract.editor_bound,
        instance_map_contract_verified = true,
        return_points = {},
        encounter_resource_bindings = {},
        spawn_bindings = {},
        encounter_action_bindings = {},
        encounter_instance_map_states = {},
        instance_contract_role_schema = copy_instance_role_schema(M.instance_contract_role_schema),
        instance_map_contracts = {},
    }
    for _, role in ipairs(sorted_keys(M.return_points)) do
        local resource_key = M.return_points[role]
        local resource = M.resources[resource_key]
        projection.return_points[#projection.return_points + 1] = {
            role = role, resource_key = resource_key, source = resource.source, expected_type = resource.expected_type,
        }
    end
    for _, encounter_key in ipairs(sorted_keys(M.encounters)) do
        local encounter = M.encounters[encounter_key]
        for _, resource_key in ipairs(copy_array(encounter.resources)) do
            local resource = M.resources[resource_key]
            projection.encounter_resource_bindings[#projection.encounter_resource_bindings + 1] = {
                encounter_key = encounter_key, resource_key = resource_key,
                source = resource.source, expected_type = resource.expected_type,
                role = (M.encounter_resource_roles[encounter_key] or {})[resource_key],
            }
        end
        for _, item in ipairs(copy_array(encounter.spawn_plan)) do
            projection.spawn_bindings[#projection.spawn_bindings + 1] = {
                encounter_key = encounter_key, anchor_key = item.anchor, unit_key = item.unit_key,
            }
        end
        if encounter.boss_unit_key and encounter.boss_spawn_anchor then
            projection.spawn_bindings[#projection.spawn_bindings + 1] = {
                encounter_key = encounter_key,
                anchor_key = encounter.boss_spawn_anchor,
                unit_key = encounter.boss_unit_key,
            }
        end
        local action = compact_action(encounter.action, encounter_key)
        if action then projection.encounter_action_bindings[#projection.encounter_action_bindings + 1] = action end
        if encounter.instance_map_contract then
            projection.encounter_instance_map_states[#projection.encounter_instance_map_states + 1] = {
                encounter_key = encounter_key,
                state = encounter.instance_map_contract,
                contract_key = encounter.instance_map_contract_key,
                slot_count = projected_instance_slot_count(encounter_key, encounter),
            }
        end
    end
    for _, contract_key in ipairs(sorted_keys(M.instance_map_contracts)) do
        local contract = M.instance_map_contracts[contract_key]
        if contract.state ~= 'verified' then projection.instance_map_contract_verified = false end
        projection.instance_map_contracts[#projection.instance_map_contracts + 1] = {
            contract_key = contract_key,
            encounter_keys = copy_array(contract.encounter_keys),
            state = contract.state,
            layer = contract.layer,
            slot_count = contract.slot_count,
            slots = copy_instance_slots(contract.slots),
        }
    end
    table.sort(projection.encounter_resource_bindings, function(a, b)
        if a.encounter_key ~= b.encounter_key then return a.encounter_key < b.encounter_key end
        return a.resource_key < b.resource_key
    end)
    table.sort(projection.spawn_bindings, function(a, b)
        if a.encounter_key ~= b.encounter_key then return a.encounter_key < b.encounter_key end
        if a.anchor_key ~= b.anchor_key then return a.anchor_key < b.anchor_key end
        return a.unit_key < b.unit_key
    end)
    return projection
end

function M.get_encounter(key)
    return M.encounters[key]
end

function M.get_resource(key)
    return M.resources[key]
end

function M.get_instance_map_contract(encounter_key)
    local encounter = M.encounters[encounter_key]
    local contract_key = encounter and encounter.instance_map_contract_key
    return contract_key and M.instance_map_contracts[contract_key] or nil, contract_key
end

return M
