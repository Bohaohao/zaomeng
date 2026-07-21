-- custom-built: offline, engine-neutral first-six-hours economy data.
-- This file intentionally contains no Y3 API calls or object identifiers.
local M = {}

M.schema_version = 1
M.package_status = 'offline_candidate_simulation_not_adopted'
M.execution_status = 'offline_simulation_ready'
M.production_gate = 'closed'
M.runtime_handoff = false
M.resource_table_status = 'offline_candidate_not_adopted'
M.resource_table_version = 'f6h-v1'
M.owner_scope = 'character'

M.scope = {
    active_minutes_min = 0,
    active_minutes_max = 360,
    supported_player_counts = { 1, 2, 3, 4 },
    level_start = 1,
    level_end = 20,
    chapter = 'huaguoshan',
    wall_clock_excluded = true,
    note = 'This is an offline pacing simulation. It is not a live Y3 reward table.',
}

-- cumulative_xp is the total experience needed to enter the stated level.
M.level_curve = {
    { level = 1, xp_to_next = 100, cumulative_xp = 0, target_active_minute = 0 },
    { level = 2, xp_to_next = 120, cumulative_xp = 100, target_active_minute = 2 },
    { level = 3, xp_to_next = 145, cumulative_xp = 220, target_active_minute = 5 },
    { level = 4, xp_to_next = 170, cumulative_xp = 365, target_active_minute = 7 },
    { level = 5, xp_to_next = 200, cumulative_xp = 535, target_active_minute = 9 },
    { level = 6, xp_to_next = 235, cumulative_xp = 735, target_active_minute = 10 },
    { level = 7, xp_to_next = 275, cumulative_xp = 970, target_active_minute = 12 },
    { level = 8, xp_to_next = 320, cumulative_xp = 1245, target_active_minute = 13 },
    { level = 9, xp_to_next = 370, cumulative_xp = 1565, target_active_minute = 15 },
    { level = 10, xp_to_next = 425, cumulative_xp = 1935, target_active_minute = 17 },
    { level = 11, xp_to_next = 485, cumulative_xp = 2360, target_active_minute = 20 },
    { level = 12, xp_to_next = 550, cumulative_xp = 2845, target_active_minute = 23 },
    { level = 13, xp_to_next = 620, cumulative_xp = 3395, target_active_minute = 28 },
    { level = 14, xp_to_next = 695, cumulative_xp = 4015, target_active_minute = 34 },
    { level = 15, xp_to_next = 775, cumulative_xp = 4710, target_active_minute = 40 },
    { level = 16, xp_to_next = 860, cumulative_xp = 5485, target_active_minute = 44 },
    { level = 17, xp_to_next = 950, cumulative_xp = 6345, target_active_minute = 47 },
    { level = 18, xp_to_next = 1045, cumulative_xp = 7295, target_active_minute = 49 },
    { level = 19, xp_to_next = 1145, cumulative_xp = 8340, target_active_minute = 52 },
    { level = 20, xp_to_next = 0, cumulative_xp = 9485, target_active_minute = 55 },
}

M.xp_sources = {
    XP_INTRO = { base_xp = 100, source_level = 1, source_kind = 'main_quest' },
    XP_MOUNTAIN = { base_xp = 500, source_level = 3, source_kind = 'public_normal' },
    XP_WATERFALL = { base_xp = 500, source_level = 5, source_kind = 'public_elite' },
    XP_MACAQUE = { base_xp = 800, source_level = 8, source_kind = 'public_boss' },
    XP_PEACH = { base_xp = 600, source_level = 10, source_kind = 'side_quest' },
    XP_CAVE = { base_xp = 650, source_level = 11, source_kind = 'solo_instance' },
    XP_SEVENSTAR = { base_xp = 800, source_level = 13, source_kind = 'public_elite' },
    XP_PENG = { base_xp = 500, source_level = 14, source_kind = 'optional_boss' },
    XP_EASTSEA = { base_xp = 900, source_level = 16, source_kind = 'public_normal' },
    XP_JIAO = { base_xp = 1200, source_level = 18, source_kind = 'public_boss' },
    XP_SHARK = { base_xp = 1200, source_level = 19, source_kind = 'public_boss' },
    XP_CHAPTER_CLEAR = { base_xp = 1735, source_level = 20, source_kind = 'chapter_clear' },
}

M.party_xp_policy = {
    policy_id = 'F6H_PARTY_FULL_QUALIFIED_XP_V1',
    distribution = 'each-qualified-character-receives-the-full-base-award-once',
    qualification_required = true,
    party_size_changes_base_award = false,
    level_difference_multipliers = {
        { max_over_level = 2, multiplier = 1.00 },
        { max_over_level = 4, multiplier = 0.80 },
        { max_over_level = 6, multiplier = 0.50 },
        { max_over_level = 999, multiplier = 0.20 },
    },
    death_rule = 'A character receives no new live-combat XP while dead. A previously issued receipt replays unchanged after revive or reconnect.',
    reconnect_rule = 'The same XP receipt is returned once; reconnect never duplicates XP.',
}

M.public_chest_policy = {
    candidate_policy_id = 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION',
    source_decision_id = 'ECO-P1-001',
    source_decision_status = 'conflict',
    progression_participation = 'damage>=3% OR valid_break OR valid_guard OR valid_public_action',
    participation_chest = 'when_action_window_opened: valid_public_action AND (damage>=3% OR valid_break OR valid_guard); otherwise: damage>=3% OR valid_break OR valid_guard',
    rare_eligibility = 'separate authority-attested Boss-clear channel; it is never inferred from a chest result',
    pity_progress = 'only after an eligible rare roll misses and its receipt settles',
}

-- This is an authority-attested input contract for the offline team-raid path.
-- It deliberately does not name or call any Y3 API: a live adapter must stay
-- production-gated and provide an equivalent trusted snapshot before use.
M.team_raid_qualification_policy = {
    policy_id = 'F6H_TEAM_RAID_RARE_ELIGIBILITY_V1',
    snapshot_schema_version = 1,
    min_members = 1,
    max_members = 4,
    required_snapshot_fields = {
        'schema_version', 'policy_id', 'snapshot_id', 'raid_instance_id',
        'completion_event_id', 'profile_key', 'completed', 'rare_clear_attested',
        'authority_proof_ref', 'members',
    },
    required_member_fields = {
        'owner_id', 'joined_before_lock', 'present_at_completion',
        'actor_alive_at_completion', 'contribution_attested', 'rare_clear_attested',
    },
    participation = 'joined_before_lock AND present_at_completion AND actor_alive_at_completion AND contribution_attested',
    rare_eligibility = 'qualified participation AND authority-attested team clear AND authority-attested member rare eligibility',
    replay = 'the character-owned reward receipt remains authoritative after the snapshot is accepted once',
}

M.offline_simulation_owner_placeholder = '__F6H_SIMULATION_OWNER__'

M.currencies = {
    CUR_GOLD = { owner_scope = 'character', usable_in_first_six_hours = true },
    CUR_RAID_MARK = { owner_scope = 'character', usable_in_first_six_hours = true },
    CUR_TOWER_TOKEN = { owner_scope = 'character', usable_in_first_six_hours = false },
}

M.unique_resources = {
    EQ_HG_WEAPON_T1 = true,
    EQ_HG_ARMOR_T1 = true,
    EQ_HG_RING_T1 = true,
    EQ_HG_SET_GUARD_T1 = true,
    EQ_HG_TRINKET_T1 = true,
    ART_HG_TIDE_SEAL = true,
    ART_HG_FLAME_CORE = true,
}

M.reward_bundles = {
    mountain_common = { guaranteed = { { key = 'CUR_GOLD', amount = 8 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 1 } } },
    mountain_elite = { guaranteed = { { key = 'CUR_GOLD', amount = 20 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 2 } } },
    mountain_major = { guaranteed = { { key = 'CUR_GOLD', amount = 32 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 3 } } },
    waterfall_common = { guaranteed = { { key = 'CUR_GOLD', amount = 10 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 1 } } },
    waterfall_elite = { guaranteed = { { key = 'CUR_GOLD', amount = 24 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 2 } } },
    public_boss = { guaranteed = { { key = 'CUR_GOLD', amount = 50 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 3 } } },
    peach_common = { guaranteed = { { key = 'CUR_GOLD', amount = 14 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 1 } } },
    peach_major = { guaranteed = { { key = 'CUR_GOLD', amount = 34 }, { key = 'MAT_ADVANCE_HG', amount = 1 } } },
    cave_common = { guaranteed = { { key = 'CUR_GOLD', amount = 16 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 1 } } },
    cave_major = { guaranteed = { { key = 'CUR_GOLD', amount = 38 }, { key = 'MAT_ADVANCE_HG', amount = 1 } } },
    sevenstar_common = { guaranteed = { { key = 'CUR_GOLD', amount = 18 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 2 } } },
    sevenstar_elite = { guaranteed = { { key = 'CUR_GOLD', amount = 28 }, { key = 'MAT_ADVANCE_HG', amount = 1 } } },
    sevenstar_major = { guaranteed = { { key = 'CUR_GOLD', amount = 42 }, { key = 'MAT_ADVANCE_HG', amount = 2 } } },
    optional_major = { guaranteed = { { key = 'CUR_GOLD', amount = 44 }, { key = 'MAT_ARTIFACT_DUST', amount = 2 } } },
    eastsea_common = { guaranteed = { { key = 'CUR_GOLD', amount = 20 }, { key = 'MAT_STRENGTHEN_SHARD', amount = 2 } } },
    eastsea_elite = { guaranteed = { { key = 'CUR_GOLD', amount = 32 }, { key = 'MAT_ADVANCE_HG', amount = 1 } } },
    dragon_old = { guaranteed = { { key = 'CUR_GOLD', amount = 100 }, { key = 'MAT_ARTIFACT_DUST', amount = 5 } } },
    dragon_reverse = { guaranteed = { { key = 'CUR_GOLD', amount = 120 }, { key = 'MAT_ARTIFACT_DUST', amount = 6 } } },
    ox_raid = { guaranteed = { { key = 'CUR_GOLD', amount = 120 }, { key = 'CUR_RAID_MARK', amount = 1 }, { key = 'MAT_ADVANCE_HG', amount = 2 } } },
}

M.reward_profiles = {
    HG_DROP_MOUNTAIN_COMMON = { bundle = 'mountain_common', scope = 'encounter' },
    HG_DROP_MOUNTAIN_ELITE = { bundle = 'mountain_elite', scope = 'encounter' },
    HG_DROP_MOUNTAIN_MAJOR = { bundle = 'mountain_major', scope = 'encounter' },
    HG_DROP_WATERFALL_COMMON = { bundle = 'waterfall_common', scope = 'encounter' },
    HG_DROP_WATERFALL_ELITE = { bundle = 'waterfall_elite', scope = 'encounter' },
    HG_DROP_MACAQUE_PUBLIC = {
        bundle = 'public_boss', scope = 'public_boss',
        first_clear = { key = 'EQ_HG_WEAPON_T1', conversion = { key = 'CUR_GOLD', amount = 90 } },
        rare = { key = 'EQ_HG_TRINKET_T1', chance_basis_points = 1000, pity_pool_key = 'PITY_HG_PUBLIC_GEAR', pity_after_misses = 5, conversion = { key = 'CUR_GOLD', amount = 110 } },
    },
    HG_DROP_PEACH_COMMON = { bundle = 'peach_common', scope = 'encounter' },
    HG_DROP_PEACH_MAJOR = { bundle = 'peach_major', scope = 'encounter' },
    HG_DROP_CAVE_COMMON = { bundle = 'cave_common', scope = 'encounter' },
    HG_DROP_CAVE_MAJOR = { bundle = 'cave_major', scope = 'encounter' },
    HG_DROP_SEVENSTAR_COMMON = { bundle = 'sevenstar_common', scope = 'encounter' },
    HG_DROP_SEVENSTAR_ELITE = { bundle = 'sevenstar_elite', scope = 'encounter' },
    HG_DROP_SEVENSTAR_MAJOR = { bundle = 'sevenstar_major', scope = 'encounter' },
    HG_DROP_PENG_OPTIONAL = { bundle = 'optional_major', scope = 'encounter' },
    HG_DROP_EASTSEA_COMMON = { bundle = 'eastsea_common', scope = 'encounter' },
    HG_DROP_EASTSEA_ELITE = { bundle = 'eastsea_elite', scope = 'encounter' },
    HG_DROP_JIAO_PUBLIC = { bundle = 'public_boss', scope = 'public_boss', first_clear = { key = 'EQ_HG_ARMOR_T1', conversion = { key = 'CUR_GOLD', amount = 90 } } },
    HG_DROP_SHARK_PUBLIC = { bundle = 'public_boss', scope = 'public_boss', first_clear = { key = 'EQ_HG_RING_T1', conversion = { key = 'CUR_GOLD', amount = 90 } } },
    HG_DROP_DRAGON_OLD = { bundle = 'dragon_old', scope = 'encounter', first_clear = { key = 'ART_HG_TIDE_SEAL', conversion = { key = 'MAT_ARTIFACT_DUST', amount = 8 } } },
    HG_DROP_DRAGON_REVERSE = { bundle = 'dragon_reverse', scope = 'encounter' },
    HG_DROP_OX_RAID = {
        bundle = 'ox_raid', scope = 'team_raid',
        first_clear = { key = 'EQ_HG_SET_GUARD_T1', conversion = { key = 'CUR_RAID_MARK', amount = 2 } },
        rare = { key = 'ART_HG_FLAME_CORE', chance_basis_points = 800, pity_pool_key = 'PITY_HG_RAID_ARTIFACT', pity_after_misses = 6, conversion = { key = 'CUR_RAID_MARK', amount = 3 } },
    },
}

M.enhancement_costs = {
    HG_ENHANCE_T1 = { CUR_GOLD = 60, MAT_STRENGTHEN_SHARD = 3 },
}

M.first_five_build_milestones = {
    { key = 'SKILL_SECOND_ACTIVE', minute = 5, rule = 'level_at_least_3' },
    { key = 'CORE_ROUTE', minute = 13, rule = 'level_at_least_8' },
    { key = 'FIRST_EQUIPMENT', minute = 13, rule = 'owns_EQ_HG_WEAPON_T1' },
    { key = 'FIRST_ENHANCEMENT', minute = 20, rule = 'completed_HG_ENHANCE_T1' },
    { key = 'FIRST_ARTIFACT', minute = 75, rule = 'owns_ART_HG_TIDE_SEAL' },
}

M.first_six_hours_trace = {
    { kind = 'xp', minute = 2, event_id = 'f6h-xp-01', source_key = 'XP_INTRO' },
    { kind = 'reward', minute = 3, event_id = 'f6h-rw-01', profile_key = 'HG_DROP_MOUNTAIN_COMMON', encounter_qualified = true },
    { kind = 'xp', minute = 5, event_id = 'f6h-xp-02', source_key = 'XP_MOUNTAIN' },
    { kind = 'reward', minute = 6, event_id = 'f6h-rw-02', profile_key = 'HG_DROP_MOUNTAIN_COMMON', encounter_qualified = true },
    { kind = 'xp', minute = 8, event_id = 'f6h-xp-03', source_key = 'XP_WATERFALL' },
    { kind = 'reward', minute = 9, event_id = 'f6h-rw-03', profile_key = 'HG_DROP_MOUNTAIN_ELITE', encounter_qualified = true },
    { kind = 'xp', minute = 13, event_id = 'f6h-xp-04', source_key = 'XP_MACAQUE' },
    { kind = 'reward', minute = 13, event_id = 'f6h-rw-04', profile_key = 'HG_DROP_MACAQUE_PUBLIC', roll_basis_points = 9000, evidence = { damage_ratio = 0.12, valid_public_action = true, public_action_window_opened = true, rare_clear_attested = true } },
    { kind = 'xp', minute = 17, event_id = 'f6h-xp-05', source_key = 'XP_PEACH' },
    { kind = 'spend', minute = 20, event_id = 'f6h-sp-01', intent_key = 'HG_ENHANCE_T1' },
    { kind = 'xp', minute = 22, event_id = 'f6h-xp-06', source_key = 'XP_CAVE' },
    { kind = 'xp', minute = 28, event_id = 'f6h-xp-07', source_key = 'XP_SEVENSTAR' },
    { kind = 'xp', minute = 34, event_id = 'f6h-xp-08', source_key = 'XP_PENG' },
    { kind = 'xp', minute = 41, event_id = 'f6h-xp-09', source_key = 'XP_EASTSEA' },
    { kind = 'xp', minute = 47, event_id = 'f6h-xp-10', source_key = 'XP_JIAO' },
    { kind = 'xp', minute = 52, event_id = 'f6h-xp-11', source_key = 'XP_SHARK' },
    { kind = 'xp', minute = 55, event_id = 'f6h-xp-12', source_key = 'XP_CHAPTER_CLEAR' },
    { kind = 'reward', minute = 75, event_id = 'f6h-rw-05', profile_key = 'HG_DROP_DRAGON_OLD', encounter_qualified = true },
    {
        kind = 'reward', minute = 120, event_id = 'f6h-rw-06', profile_key = 'HG_DROP_OX_RAID', roll_basis_points = 9900,
        team_snapshot = {
            schema_version = 1, policy_id = 'F6H_TEAM_RAID_RARE_ELIGIBILITY_V1',
            snapshot_id = 'snapshot:f6h-rw-06', raid_instance_id = 'offline-ox-raid-01',
            completion_event_id = 'f6h-rw-06', profile_key = 'HG_DROP_OX_RAID',
            completed = true, rare_clear_attested = true,
            authority_proof_ref = 'offline-fixture:f6h-rw-06',
            members = {
                {
                    owner_id = '__F6H_SIMULATION_OWNER__', joined_before_lock = true,
                    present_at_completion = true, actor_alive_at_completion = true,
                    contribution_attested = true, rare_clear_attested = true,
                },
            },
        },
    },
    { kind = 'reward', minute = 180, event_id = 'f6h-rw-07', profile_key = 'HG_DROP_EASTSEA_ELITE', encounter_qualified = true },
    { kind = 'reward', minute = 240, event_id = 'f6h-rw-08', profile_key = 'HG_DROP_DRAGON_OLD', encounter_qualified = true },
    {
        kind = 'reward', minute = 300, event_id = 'f6h-rw-09', profile_key = 'HG_DROP_OX_RAID', roll_basis_points = 9900,
        team_snapshot = {
            schema_version = 1, policy_id = 'F6H_TEAM_RAID_RARE_ELIGIBILITY_V1',
            snapshot_id = 'snapshot:f6h-rw-09', raid_instance_id = 'offline-ox-raid-02',
            completion_event_id = 'f6h-rw-09', profile_key = 'HG_DROP_OX_RAID',
            completed = true, rare_clear_attested = true,
            authority_proof_ref = 'offline-fixture:f6h-rw-09',
            members = {
                {
                    owner_id = '__F6H_SIMULATION_OWNER__', joined_before_lock = true,
                    present_at_completion = true, actor_alive_at_completion = true,
                    contribution_attested = true, rare_clear_attested = true,
                },
            },
        },
    },
    { kind = 'checkpoint', minute = 360, event_id = 'f6h-end' },
}

return M
