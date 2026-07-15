-- C04 Xunlie's offline numeric baseline. All durations use the authoritative
-- 60 Hz project tick; the Y3 bridge only translates these neutral commands.
local M = {}

M.ticks_per_second = 60

M.hero = {
    level_min = 1,
    level_max = 60,
    hp_base = 560,
    hp_growth = 58,
    attack_physical_base = 46,
    attack_physical_growth = 5.45,
    defense_physical_base = 17,
    defense_physical_growth = 1.55,
    defense_magic_base = 18,
    defense_magic_growth = 1.65,
    critical_chance = 0.05,
    critical_damage = 1.50,
    hit_rate = 1.00,
    dodge_rate = 0.00,
    move_speed = 3.85,
    attack_speed = 104,
    attack_interval = 1.00,
    loadout_slots = 5,
}

M.resource = {
    unlock_level = 8,
    core_skills = { 'C04_A03', 'C04_A04', 'C04_A05' },
    marks_max = 5,
    tracked_target_max = 8,
    normal_attack_mark_cooldown_ticks = 132,
    idle_before_decay_ticks = 360,
    -- Rounding is intentional: runtime state must advance on integral sync
    -- ticks. The source values are 1.08/1.16/1.24/1.32/1.40 seconds.
    decay_interval_ticks = { 60, 65, 70, 74, 79, 84 },
    pending_cast_timeout_ticks = 300,
    ultimate_max = 100,
    ultimate_per_recovery = 20,
    first_recovery_delay_ticks = 252,
    recovery_cooldown_ticks = 960,
}

M.abilities = {
    C04_A01 = {
        max_level = 5, generator = true, requires_primary = true,
        damage = { 0.75, 0.85, 0.95, 1.05, 1.15 },
        cooldown = { 3.8, 3.8, 3.5, 3.3, 3.0 },
        required_level = { 1, 3, 8, 14, 20 },
        trace_duration_ticks = 180,
        rank5_trace_bonus_ticks = 60,
    },
    C04_A02 = {
        max_level = 5, generator = true, requires_direction = true,
        damage = { 0.42, 0.48, 0.54, 0.60, 0.66 },
        cooldown = { 8.5, 8.5, 8.0, 7.5, 7.0 },
        required_level = { 3, 8, 14, 20, 28 },
        target_cap = 5,
    },
    C04_A03 = {
        max_level = 5, spender = true, requires_primary = true,
        damage = { 1.10, 1.25, 1.40, 1.55, 1.70 },
        per_mark = { 0.30, 0.32, 0.34, 0.36, 0.38 },
        cooldown = { 8.5, 8.5, 8.0, 7.5, 7.0 },
        required_level = { 8, 14, 20, 28, 36 },
        consume = 2,
        pierce_duration_ticks = 240,
    },
    C04_A04 = {
        max_level = 5, spender = true, requires_direction = true, requires_safe_landing = true,
        wind_damage = { 0.45, 0.50, 0.55, 0.60, 0.65 },
        step_distance = { 3.4, 3.6, 3.8, 4.0, 4.2 },
        cooldown = { 13, 13, 12, 11, 10 },
        required_level = { 8, 14, 20, 28, 36 },
        consume = 1,
        wind_duration_ticks = 240,
    },
    C04_A05 = {
        max_level = 5, spender = true, requires_point = true,
        initial_damage = { 0.70, 0.80, 0.90, 1.00, 1.10 },
        pulse_damage = { 0.15, 0.18, 0.21, 0.24, 0.27 },
        slow = { 0.20, 0.25, 0.30, 0.35, 0.40 },
        cooldown = { 11.5, 11.5, 11.0, 10.5, 10.0 },
        required_level = { 8, 14, 20, 28, 36 },
        consume = 1, selected_cap = 5, consume_cap = 3,
        pulses = { 36, 72, 108 },
        slow_duration_ticks = 72,
        net_duration_ticks = 240,
        field_duration_ticks = 120,
        rank5_net_bonus_damage = 0.30,
    },
    C04_A06 = {
        max_level = 5, spender = true, requires_primary = true,
        damage = { 1.65, 1.80, 1.95, 2.10, 2.25 },
        per_mark = { 0.28, 0.30, 0.32, 0.34, 0.36 },
        cooldown = { 15.0, 15.0, 14.5, 14.0, 13.5 },
        required_level = { 20, 26, 33, 41, 50 },
        consume_all = true,
        pierce_a06_bonus = 0.15,
        complete_move_speed = 0.12,
        complete_move_duration_ticks = 120,
    },
    C04_A07 = {
        max_level = 5, spender = true, requires_primary = true,
        arrow_damage = { 0.50, 0.56, 0.62, 0.68, 0.74 },
        extra_per_mark = { 0.12, 0.14, 0.16, 0.18, 0.20 },
        cooldown = { 17, 17, 16, 15, 14 },
        required_level = { 20, 26, 33, 41, 50 },
        consume = 1,
        fire_ticks = { 21, 48, 75 },
        phase_close_ticks = { 93, 120, 147 },
        three_arrow_duration_ticks = 147,
    },
    C04_A08 = {
        max_level = 5, spender = true, requires_point = true,
        initial_damage = { 1.00, 1.15, 1.30, 1.45, 1.60 },
        pulse_damage = { 0.18, 0.21, 0.24, 0.27, 0.30 },
        low_mark_extra = { 0.20, 0.24, 0.28, 0.32, 0.36 },
        slow = { 0.25, 0.28, 0.31, 0.34, 0.37 },
        cooldown = { 18, 18, 17, 16, 15 },
        required_level = { 20, 26, 33, 41, 50 },
        consume = 2, selected_cap = 6, consume_cap = 3,
        minimum_marks = 3,
        pulses = { 42, 84, 126, 168 },
        slow_duration_ticks = 60,
        field_duration_ticks = 180,
        garrote_duration_ticks = 240,
    },
}

M.passives = {
    C04_P01 = { decay_interval_ticks = { 65, 70, 74, 79, 84 } },
    C04_P02 = {
        recovery_heal_max_hp = { 0.008, 0.010, 0.012, 0.014, 0.016 },
        recovery_move_speed = { 0.04, 0.05, 0.06, 0.07, 0.08 },
        duration_ticks = 180,
    },
    C04_P03 = {
        pierce_duration_bonus_ticks = { 30, 60, 90, 120, 150 },
        a06_bonus_per_mark = { 0.03, 0.04, 0.05, 0.06, 0.07 },
    },
    C04_P04 = { a06_total_multiplier_per_mark = { 0.02, 0.03, 0.04, 0.05, 0.06 } },
    C04_P05 = {
        step_distance_bonus = { 0.2, 0.4, 0.6, 0.8, 1.0 },
        wind_duration_bonus_ticks = { 15, 30, 45, 60, 75 },
        rank5_wind_move_speed = 0.15,
        rank5_wind_move_duration_ticks = 60,
    },
    C04_P06 = {
        a07_cooldown_reduction = { 0.3, 0.4, 0.5, 0.6, 0.7 },
        rank5_free_wind_arrow = true,
    },
    C04_P07 = {
        slow_bonus = { 0.02, 0.04, 0.06, 0.08, 0.10 },
        net_duration_bonus_ticks = { 30, 60, 90, 120, 150 },
    },
    C04_P08 = {
        a08_per_mark_extra = { 0.04, 0.06, 0.08, 0.10, 0.12 },
        a05_cooldown_reduction = { 1.0, 1.5, 2.0, 2.5, 3.0 },
        tier5_garrote_pulse = 0.35,
    },
}

M.ultimate = {
    key = 'C04_U01',
    duration_ticks = { 600, 720, 720 },
    opening_damage = 2.10,
    opening_rebound_damage = 0.70,
    opening_rebound_cap = 2,
    tier2_skill_reaction = 0.45,
    tier2_reaction_cap = 4,
    tier3_recovery_reverb = 0.70,
    tier3_reverb_cap = 3,
}

M.modifiers = {
    C04_M01_HUNT = { policy = 'derived' },
    C04_M02_LOCKED = { policy = 'derived' },
    C04_M03_TRACE = { policy = 'source_refresh' },
    C04_M04_PIERCE = { policy = 'source_bound' },
    C04_M05_WIND = { policy = 'source_refresh' },
    C04_M06_THREE_ARROWS = { policy = 'source_refresh' },
    C04_M07_SLOW = { policy = 'shared_highest', priority_key = 'slow' },
    C04_M08_NET = { policy = 'source_bound' },
    C04_M09_FIELD = { policy = 'source_refresh' },
    C04_M10_GARROTE = { policy = 'source_bound' },
    C04_M11_ULTIMATE = { policy = 'source_refresh' },
    C04_M12_RECOVERY = { policy = 'source_refresh' },
}

return M
