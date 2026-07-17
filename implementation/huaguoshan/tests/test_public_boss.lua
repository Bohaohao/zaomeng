package.path = 'implementation/huaguoshan/tests/?.lua;implementation/huaguoshan/lua/?.lua;' .. package.path

local Contribution = require 'huaguoshan_contribution'
local PublicBoss = require 'huaguoshan_public_boss'
local FakeAuthority = require 'fake_authority_provider'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then
        error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    end
end

local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local function contains(values, expected)
    for _, value in ipairs(values) do
        if value == expected then return true end
    end
    return false
end

local function copy_table(source)
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

local function has_mechanic_target(commands, target_id)
    for _, command in ipairs(commands) do
        if command.type == 'apply_mechanic' and command.target_id == target_id then return true end
    end
    return false
end

local function find_command(commands, expected_type)
    for _, command in ipairs(commands) do
        if command.type == expected_type then return command end
    end
    return nil
end

local encounter = {
    encounter_type = 'public_boss',
    break_profile = { threshold = 12, window_seconds = 4 },
    action = { key = 'drain_tide_eye', max_concurrent = 2, read_seconds = 1, window_seconds = 10 },
    phase = { submerge_seconds = 3 },
    mechanic = {
        key = 'HG_BOSS_WATER_CHAIN',
        resolutions = { purge_mechanic = true, drain_tide_eye = true, leave_tide_lane = true },
    },
}

local current = { a = 1, b = 1, c = 1, d = 1, e = 1, f = 1, g = 1, h = 1 }
local valid_skills = {
    DAMAGE = true,
    BREAK = true,
    GUARD = true,
    PURGE = true,
}

local function actor_is_current(actor_id, lifecycle_id)
    return current[actor_id] == lifecycle_id
end

local function source_is_current(actor_id, lifecycle_id, source_unit_id, source_unit_lifecycle_id)
    return actor_is_current(actor_id, lifecycle_id)
        and source_unit_id == actor_id .. '-unit-' .. tostring(lifecycle_id)
        and source_unit_lifecycle_id == lifecycle_id
end

local function skill_validator(event)
    return valid_skills[event.skill_key] == true
end

local authority = FakeAuthority.new({ now = 0, watermark = 0 })

local boss = PublicBoss.new('HG_E_JIAO_KING', encounter, {
    boss_instance_id = 'jiao-1',
    target_id = 'jiao-unit',
    target_lifecycle_id = 'jiao-life',
    protection_threshold = 10,
    skill_validator = skill_validator,
    source_unit_is_current = source_is_current,
    authority_provider = authority,
})

local function new_public_boss_fixture(suffix, fixture_authority)
    local instance_id = 'jiao-' .. suffix
    return PublicBoss.new('HG_E_JIAO_KING', encounter, {
        boss_instance_id = instance_id,
        target_id = instance_id .. '-unit',
        target_lifecycle_id = instance_id .. '-life',
        protection_threshold = 10,
        skill_validator = skill_validator,
        source_unit_is_current = source_is_current,
        authority_provider = fixture_authority,
    })
end

local function submerge_window_for(boss_fixture, suffix, open_tick)
    open_tick = open_tick or 0
    return {
        window_id = boss_fixture.boss_instance_id .. ':' .. boss_fixture.phase_id .. ':' .. suffix .. ':drain_tide_eye',
        mechanic_occurrence_id = suffix,
        encounter_action_key = 'drain_tide_eye',
        combat_scope = 'public',
        boss_instance_id = boss_fixture.boss_instance_id,
        phase_id = boss_fixture.phase_id,
        boss_target_id = boss_fixture.target_id,
        boss_target_lifecycle_id = boss_fixture.target_lifecycle_id,
        interaction_unit_id = suffix .. '-tide-eye',
        interaction_unit_lifecycle_id = suffix .. '-tide-eye-life',
        open_tick = open_tick,
        close_tick = open_tick + encounter.action.window_seconds,
        reading_duration_ticks = encounter.action.read_seconds,
        reservation_retention_ticks = 2,
    }
end

local function submerge_marker_for(boss_fixture, suffix, action_window_fixture)
    return {
        kind = 'phase_marker',
        event_id = 'marker:submerge:' .. suffix,
        marker_occurrence_id = suffix,
        marker = 'submerge',
        combat_scope = 'public',
        boss_instance_id = boss_fixture.boss_instance_id,
        phase_id = boss_fixture.phase_id,
        boss_target_id = boss_fixture.target_id,
        boss_target_lifecycle_id = boss_fixture.target_lifecycle_id,
        sync_tick = action_window_fixture.open_tick,
        action_window = action_window_fixture,
    }
end

local function new_submerged_boss_fixture(suffix)
    local fixture_authority = FakeAuthority.new({ now = 0, watermark = 0 })
    local fixture_boss = new_public_boss_fixture(suffix, fixture_authority)
    local fixture_window = submerge_window_for(fixture_boss, suffix, 0)
    local fixture_marker = submerge_marker_for(fixture_boss, suffix, fixture_window)
    local marker_ok, marker_result = fixture_boss:phase_marker(fixture_marker)
    truthy(marker_ok, 'fixture submerge starts for ' .. suffix)
    local pause = find_command(marker_result.commands, 'trace_pause')
    truthy(pause, 'fixture submerge emits trace pause for ' .. suffix)
    return fixture_boss, fixture_authority, pause
end

local function combat_event(kind, actor_id, lifecycle_id, event_id, value, overrides)
    local skill_by_kind = {
        final_damage = 'DAMAGE',
        actual_break = 'BREAK',
        actual_protection = 'GUARD',
        mechanic_resolved = 'PURGE',
    }
    local event = {
        kind = kind,
        event_id = event_id,
        actor_id = actor_id,
        lifecycle_id = lifecycle_id,
        source_unit_id = actor_id .. '-unit-' .. tostring(lifecycle_id),
        source_unit_lifecycle_id = lifecycle_id,
        skill_key = skill_by_kind[kind],
        skill_validated = true,
        combat_scope = 'public',
        boss_instance_id = 'jiao-1',
        phase_id = boss.phase_id,
        target_id = boss.target_id,
        target_lifecycle_id = boss.target_lifecycle_id,
        sync_tick = 1,
        value = value,
    }
    if kind == 'actual_break' then event.break_scope = 'boss_only' end
    if kind == 'actual_protection' then event.protection_scope = 'boss_guarded_direct' end
    if kind == 'mechanic_resolved' then
        event.mechanic_key = 'HG_BOSS_WATER_CHAIN'
        event.mechanic_resolution = 'purge_mechanic'
    end
    for key, item in pairs(overrides or {}) do event[key] = item end
    return event
end

do
    local explicit = combat_event('final_damage', 'a', 1, 'schema:explicit', 1)
    local live_ok, live_error = Contribution.validate(explicit)
    equal(live_ok, false, 'live contribution validation requires a trusted skill validator by default')
    equal(live_error, 'invalid-skill-proof', 'validated booleans are not live skill proof')

    explicit.offline_skill_proof = { fixture_id = 'public-boss-schema', skill_key = explicit.skill_key }
    truthy(Contribution.validate(explicit, { offline_test_mode = true }),
        'an explicit offline test fixture can provide a non-Y3 skill proof')
    for _, field in ipairs({
        'instance_slot_id', 'session_instance_id', 'session_epoch', 'raid_instance_id',
        'team_member_ids', 'member_ids', 'slot_id', 'cleanup_token', 'cleanup_order',
    }) do
        local polluted = combat_event('final_damage', 'a', 1, 'schema:public-instance:' .. field, 1)
        polluted.offline_skill_proof = { fixture_id = 'public-boss-schema', skill_key = polluted.skill_key }
        polluted[field] = field == 'team_member_ids' or field == 'member_ids' or field == 'cleanup_order'
            and { 'forged' } or 'forged'
        local polluted_ok, polluted_error = Contribution.validate(polluted, { offline_test_mode = true })
        equal(polluted_ok, false, 'public contribution rejects instance context field ' .. field)
        equal(polluted_error, 'public-event-carries-instance-context:' .. field,
            'public contribution names the rejected instance context field')
    end
    explicit.source_unit_id = nil
    local missing, missing_error = Contribution.validate(explicit, { offline_test_mode = true })
    equal(missing, false, 'source unit identity is mandatory for contribution events')
    equal(missing_error, 'missing-encounter-field:source_unit_id', 'missing source identity has a stable error')

    local forged = combat_event('final_damage', 'a', 1, 'schema:forged-skill', 1, {
        skill_key = 'MADE_UP', skill_validated = true, validated = true,
    })
    local forged_ok, forged_error = Contribution.validate(forged, { skill_validator = skill_validator })
    equal(forged_ok, false, 'trusted validation rejects a forged skill key despite validated booleans')
    equal(forged_error, 'invalid-skill-proof', 'forged skill rejection remains explicit')

    local live_boss = PublicBoss.new('HG_E_JIAO_KING', encounter, {
        boss_instance_id = 'live-proof',
        target_id = 'live-proof-target',
        target_lifecycle_id = 'live-proof-life',
        offline_test_mode = true,
        source_unit_is_current = source_is_current,
        authority_provider = authority,
    })
    local live_event = combat_event('final_damage', 'a', 1, 'schema:live-forged-skill', 1, {
        boss_instance_id = 'live-proof',
        target_id = 'live-proof-target',
        target_lifecycle_id = 'live-proof-life',
        skill_key = 'MADE_UP',
        skill_validated = true,
        validated = true,
        offline_skill_proof = { fixture_id = 'forged-live-input', skill_key = 'MADE_UP' },
    })
    local live_boss_ok, live_boss_error = live_boss:record_damage(live_event, actor_is_current)
    equal(live_boss_ok, false, 'PublicBoss rejects offline proof injected through a live startup payload')
    equal(live_boss_error, 'invalid-skill-proof', 'live PublicBoss rejection is explicit')

    local old_kind = combat_event('encounter_action', 'a', 1, 'schema:old-action', 1)
    local old_ok = Contribution.validate(old_kind)
    equal(old_ok, false, 'the legacy encounter_action kind is no longer accepted')

    local no_provider_boss = PublicBoss.new('HG_E_JIAO_KING', encounter, {
        boss_instance_id = 'no-provider',
        target_id = 'no-provider-target',
        target_lifecycle_id = 'no-provider-life',
        skill_validator = skill_validator,
        source_unit_is_current = source_is_current,
    })
    local no_provider_event = combat_event('final_damage', 'a', 1, 'no-provider:damage', 1, {
        boss_instance_id = 'no-provider',
        target_id = 'no-provider-target',
        target_lifecycle_id = 'no-provider-life',
    })
    local no_provider_ok, no_provider_error = no_provider_boss:record_damage(
        no_provider_event, actor_is_current)
    equal(no_provider_ok, false, 'a public Boss contribution fails closed without the Runtime authority provider')
    equal(no_provider_error, 'authority-provider-required', 'missing Boss authority provider is explicit')
end

do
    local scope_ledger = Contribution.new({ skill_validator = skill_validator })
    local first_phase = combat_event('final_damage', 'a', 1, 'scope:shared-event', 1, { phase_id = 'scope-1' })
    local second_phase = combat_event('final_damage', 'a', 1, 'scope:shared-event', 1, { phase_id = 'scope-2' })
    truthy(scope_ledger:accept(first_phase), 'a contribution event is accepted in its first Boss phase')
    truthy(scope_ledger:accept(second_phase), 'the same event_id is independent in another Boss phase')

    local duplicate, duplicate_error = scope_ledger:accept(first_phase)
    equal(duplicate, false, 'the same scoped contribution event remains deduplicated')
    equal(duplicate_error, 'duplicate-encounter-event', 'same-phase duplicate has a stable error')

    local conflicting = copy_table(first_phase)
    conflicting.value = 2
    local conflict_ok, conflict_error = scope_ledger:accept(conflicting)
    equal(conflict_ok, false, 'same scoped event_id cannot change its contribution payload')
    equal(conflict_error, 'encounter-event-origin-conflict', 'same-phase event mutation is explicit')
end

do
    truthy(boss:record_damage(combat_event('final_damage', 'a', 1, 'damage:a:life-1', 70), actor_is_current),
        'current lifecycle damage is accepted')
    local duplicate, duplicate_error = boss:record_damage(
        combat_event('final_damage', 'a', 1, 'damage:a:life-1', 70), actor_is_current)
    equal(duplicate, false, 'event_id replay cannot write damage twice')
    equal(duplicate_error, 'duplicate-encounter-event', 'event_id replay is rejected by the contribution ledger')

    current.a = 2
    boss:invalidate_actor('a', 1)
    local stale = combat_event('final_damage', 'a', 1, 'damage:a:upgrade', 5)
    local stale_ok, stale_error = boss:record_damage(stale, actor_is_current)
    equal(stale_ok, false, 'an old lifecycle cannot write contribution')
    equal(stale_error, 'stale-actor-lifecycle', 'old lifecycle rejection happens before ledger mutation')

    local upgraded = combat_event('final_damage', 'a', 2, 'damage:a:upgrade', 5)
    truthy(boss:record_damage(upgraded, actor_is_current),
        'the same event_id can be accepted from the current lifecycle after the stale attempt was rejected')
    equal(boss.participants.a.damage, 75, 'lifecycle upgrade retains this encounter cumulative damage')
    equal(boss.participants.a.lifecycle_id, 2, 'participant identity upgrades to the current lifecycle')

    local invalid_skill = combat_event('final_damage', 'a', 2, 'damage:a:invalid-skill', 1, { skill_key = 'MADE_UP' })
    local invalid_ok, invalid_error = boss:record_damage(invalid_skill, actor_is_current)
    equal(invalid_ok, false, 'the injected skill validator rejects made-up contribution skills')
    equal(invalid_error, 'invalid-skill-proof', 'invalid skill proof remains explicit')
end

do
    local break_ok, break_result = boss:record_break(
        combat_event('actual_break', 'b', 1, 'break:b', 12), actor_is_current)
    truthy(break_ok, 'actual break is accepted from a verified source and skill')
    equal(break_result.commands[1].type, 'boss_break_triggered', 'crossing the break threshold emits one command')
    truthy(boss.participants.b.break_qualified, 'the threshold-crossing break actor gains effective participation')

    truthy(boss:record_protection(
        combat_event('actual_protection', 'c', 1, 'guard:c:1', 4), actor_is_current),
        'partial actual protection is recorded')
    local guard_ok, guard_result = boss:record_protection(
        combat_event('actual_protection', 'c', 1, 'guard:c:2', 6), actor_is_current)
    truthy(guard_ok, 'actual protection can accumulate to the injected threshold')
    equal(guard_result.commands[1].type, 'boss_protection_threshold_reached',
        'crossing the protection threshold emits one command')
    truthy(boss.participants.c.protection_qualified,
        'the threshold-crossing protection actor gains effective participation')
end

local action_window = {
    window_id = 'jiao-1:phase-1:dive-1:drain_tide_eye',
    mechanic_occurrence_id = 'dive-1',
    encounter_action_key = 'drain_tide_eye',
    combat_scope = 'public',
    boss_instance_id = 'jiao-1',
    phase_id = 'phase-1',
    boss_target_id = 'jiao-unit',
    boss_target_lifecycle_id = 'jiao-life',
    interaction_unit_id = 'tide-eye-1',
    interaction_unit_lifecycle_id = 'tide-eye-life-1',
    open_tick = 0,
    close_tick = 10,
    reading_duration_ticks = 1,
    reservation_retention_ticks = 2,
}

do
    local shortened = copy_table(action_window)
    shortened.reading_duration_ticks = encounter.action.read_seconds - 0.5
    local shortened_ok, shortened_error = boss:_validate_action_window(shortened)
    equal(shortened_ok, false, 'an external phase marker cannot shorten the configured read')
    equal(shortened_error, 'action-window-reading-duration-mismatch', 'shortened read has a stable rejection')

    local expanded = copy_table(action_window)
    expanded.close_tick = expanded.open_tick + encounter.action.window_seconds + 1
    local expanded_ok, expanded_error = boss:_validate_action_window(expanded)
    equal(expanded_ok, false, 'an external phase marker cannot enlarge the configured action window')
    equal(expanded_error, 'action-window-duration-mismatch', 'expanded window has a stable rejection')

    truthy(boss:_validate_action_window(action_window),
        'the configured read_seconds and window_seconds define the accepted action window')
end

local phase_marker = {
    kind = 'phase_marker',
    event_id = 'marker:submerge:1',
    marker_occurrence_id = 'dive-1',
    marker = 'submerge',
    combat_scope = 'public',
    boss_instance_id = 'jiao-1',
    phase_id = 'phase-1',
    boss_target_id = 'jiao-unit',
    boss_target_lifecycle_id = 'jiao-life',
    sync_tick = 0,
    action_window = action_window,
}

local active_trace_pause_id = nil

do
    local forged_marker = copy_table(phase_marker)
    forged_marker.event_id = 'marker:submerge:forged'
    authority:reject_event(forged_marker.event_id)
    local forged_ok, forged_error = boss:phase_marker(forged_marker)
    equal(forged_ok, false, 'a structurally valid but untrusted phase marker is rejected')
    equal(forged_error, 'authority-proof-rejected:public_boss_phase_marker',
        'phase marker rejection comes from the trusted provider')

    local shifted_window = copy_table(action_window)
    shifted_window.mechanic_occurrence_id = 'dive-shifted'
    shifted_window.window_id = 'jiao-1:phase-1:dive-shifted:drain_tide_eye'
    shifted_window.open_tick = 1
    shifted_window.close_tick = 11
    local shifted_marker = copy_table(phase_marker)
    shifted_marker.event_id = 'marker:submerge:shifted'
    shifted_marker.marker_occurrence_id = 'dive-shifted'
    shifted_marker.action_window = shifted_window
    local shifted_ok, shifted_error = boss:phase_marker(shifted_marker)
    equal(shifted_ok, false, 'a phase marker cannot delay its action window past the sync tick')
    equal(shifted_error, 'phase-marker-window-start-mismatch', 'shifted action window has a stable rejection')

    local marker_ok, marker_result = boss:phase_marker(phase_marker)
    truthy(marker_ok, 'an explicit phase marker opens the action window')
    equal(marker_result.commands[1].type, 'open_encounter_action_window',
        'phase opening publishes the frozen action window')
    for _, command in ipairs(marker_result.commands) do
        equal(command.encounter_key, 'HG_E_JIAO_KING',
            'every public Boss phase command carries its encounter key for live dispatch')
    end
    local trace_pause = find_command(marker_result.commands, 'trace_pause')
    truthy(trace_pause, 'submerge emits an explicit trace pause command')
    equal(trace_pause.pause_id,
        'trace_pause:13:encounter_key=14:HG_E_JIAO_KING|16:boss_instance_id=6:jiao-1|8:phase_id=7:phase-1|14:boss_target_id=9:jiao-unit|24:boss_target_lifecycle_id=9:jiao-life|6:marker=8:submerge|20:marker_occurrence_id=6:dive-1',
        'submerge trace pause derives a stable business pause_id')
    active_trace_pause_id = trace_pause.pause_id
    equal(trace_pause.start_tick, action_window.open_tick,
        'the trace pause starts with the frozen submerge action window')
    equal(trace_pause.end_tick, action_window.open_tick + encounter.phase.submerge_seconds,
        'the trace pause ends after the fixed submerge duration instead of at action-window close')
    equal(trace_pause.duration_seconds, encounter.phase.submerge_seconds,
        'the trace pause command preserves the configured fixed submerge duration')
    equal(boss.trace_pause_id, active_trace_pause_id,
        'the active Boss state keeps the same trace pause identity')
    equal(boss.trace_pause_until, 3, 'the submerge pause uses its fixed three-second duration')

    local duplicate, duplicate_error = boss:phase_marker(phase_marker)
    equal(duplicate, false, 'an identical phase marker replay is idempotently rejected')
    equal(duplicate_error, 'duplicate-phase-marker', 'phase marker event_id is deduplicated')
    equal(boss.trace_pause_id, active_trace_pause_id, 'a duplicate phase marker cannot replace trace pause identity')
    equal(boss.trace_pause_until, 3, 'a duplicate phase marker cannot extend trace pause')

    local duplicate_occurrence = copy_table(phase_marker)
    duplicate_occurrence.event_id = 'marker:submerge:duplicate-occurrence'
    local occurrence_ok, occurrence_error = boss:phase_marker(duplicate_occurrence)
    equal(occurrence_ok, false, 'the same phase marker occurrence is idempotently rejected across event_ids')
    equal(occurrence_error, 'duplicate-phase-marker-occurrence',
        'same marker occurrence has a stable rejection')
    equal(boss.trace_pause_id, active_trace_pause_id,
        'same-occurrence replay cannot replace the active pause identity')
    equal(boss.trace_pause_until, 3, 'same-occurrence replay cannot extend trace pause')

    local overlapping_window = copy_table(action_window)
    overlapping_window.window_id = 'jiao-1:phase-1:dive-2:drain_tide_eye'
    overlapping_window.mechanic_occurrence_id = 'dive-2'
    local overlapping_marker = copy_table(phase_marker)
    overlapping_marker.event_id = 'marker:submerge:overlap'
    overlapping_marker.marker_occurrence_id = 'dive-2'
    overlapping_marker.action_window = overlapping_window
    local overlap_ok, overlap_error = boss:phase_marker(overlapping_marker)
    equal(overlap_ok, false, 'a second trace pause cannot start while one is active')
    equal(overlap_error, 'trace-pause-already-active', 'overlapping trace pause has a stable rejection')
    equal(boss.trace_pause_id, active_trace_pause_id,
        'overlapping trace pause cannot replace the active pause identity')
    equal(boss.trace_pause_until, 3, 'overlapping trace pause cannot extend the active deadline')
end

do
    local late_authority = FakeAuthority.new({ now = 0, watermark = 3 })
    local late_boss = new_public_boss_fixture('late-pause', late_authority)
    local late_window = submerge_window_for(late_boss, 'dive-late', 0)
    local late_marker = submerge_marker_for(late_boss, 'dive-late', late_window)
    local late_ok, late_error = late_boss:phase_marker(late_marker)
    equal(late_ok, false, 'a phase marker cannot open a trace pause after its fixed pause window')
    equal(late_error, 'expired-trace-pause-marker', 'expired trace pause marker has a stable rejection')
    equal(late_boss.trace_pause_id, nil, 'expired trace pause marker does not create a pause identity')
    equal(late_boss.trace_pause_until, nil, 'expired trace pause marker does not create a pause deadline')
end

do
    local missing_callback, missing_callback_error = boss:apply_water_chain()
    equal(missing_callback, false, 'water-chain application requires current lifecycle authority')
    equal(missing_callback_error, 'current-lifecycle-required', 'missing lifecycle authority is explicit')

    current.b = 2
    local applied, applied_result = boss:apply_water_chain(actor_is_current)
    truthy(applied, 'an active submerge applies water chain to current participants')
    truthy(has_mechanic_target(applied_result.commands, 'a'), 'a current participant receives water chain')
    equal(applied_result.commands[1].encounter_key, 'HG_E_JIAO_KING',
        'water-chain application carries the encounter key')
    equal(has_mechanic_target(applied_result.commands, 'b'), false,
        'historical contribution does not reapply water chain to a stale lifecycle')
    local first_ok, first_result = boss:resolve_water_chain(
        combat_event('mechanic_resolved', 'a', 2, 'water:a:1', nil), actor_is_current)
    truthy(first_ok, 'the first verified water-chain resolution clears the field')
    equal(first_result.commands[1].type, 'remove_mechanic', 'the first resolution emits field cleanup')
    equal(first_result.commands[1].encounter_key, 'HG_E_JIAO_KING',
        'water-chain cleanup carries the encounter key')
    equal(first_result.contribution_counted, true, 'the first mechanism resolution counts contribution')

    local reapplied, reapplied_result = boss:apply_water_chain(actor_is_current)
    truthy(reapplied, 'a later occurrence can apply water chain again for current lifecycles')
    equal(has_mechanic_target(reapplied_result.commands, 'b'), false,
        'a stale lifecycle remains excluded on later water-chain occurrences')
    local second_ok, second_result = boss:resolve_water_chain(
        combat_event('mechanic_resolved', 'a', 2, 'water:a:2', nil), actor_is_current)
    truthy(second_ok, 'the second verified resolution still clears the new field occurrence')
    equal(second_result.commands[1].type, 'remove_mechanic', 'the second occurrence emits field cleanup again')
    equal(second_result.contribution_counted, false, 'mechanism contribution is credited only once per phase')
end

do
    authority:set_watermark(2)
    local before_resume = boss:tick(2)
    equal(boss.submerged, true, 'submerge remains active before its fixed duration expires')
    equal(boss.trace_pause_until, 3, 'submerge keeps the fixed trace-pause deadline before expiry')
    equal(find_command(before_resume.commands, 'trace_resume'), nil,
        'a trace resume is not emitted before the fixed submerge duration expires')

    authority:set_watermark(3)
    local resumed = boss:tick(3)
    equal(boss.submerged, false, 'submerge state restores at the fixed three-second deadline')
    equal(boss.trace_pause_until, nil, 'the expired trace-pause deadline is cleared on restore')
    equal(boss.trace_pause_id, nil, 'the expired trace-pause identity is cleared on restore')
    local trace_resume = find_command(resumed.commands, 'trace_resume')
    truthy(trace_resume,
        'trace restore emits an explicit trace resume command at the fixed deadline')
    equal(trace_resume.pause_id, active_trace_pause_id,
        'trace restore pairs with the original stable pause identity')
    truthy(boss.action_windows[action_window.window_id],
        'trace restoration does not prematurely close the longer encounter action window')

    authority:set_watermark(4)
    local repeated = boss:tick(4)
    equal(find_command(repeated.commands, 'trace_resume'), nil,
        'an already-restored trace pause is not resumed a second time')
end

local reservations = {}
local function begin_request(actor_id)
    return {
        actor_id = actor_id,
        lifecycle_id = current[actor_id],
        window_id = action_window.window_id,
        encounter_action_key = action_window.encounter_action_key,
        interaction_unit_id = action_window.interaction_unit_id,
        interaction_unit_lifecycle_id = action_window.interaction_unit_lifecycle_id,
    }
end

do
    local forged_request = begin_request('d')
    forged_request.authority_verified = true
    local forged_begin, forged_begin_error = boss:begin_action(forged_request, actor_is_current)
    equal(forged_begin, false, 'caller authority booleans cannot reserve a Boss action')
    equal(forged_begin_error, 'untrusted-authority-field:authority_verified',
        'forged Boss begin proof is rejected explicitly')

    authority:set_now(1)
    local lifecycle_reservation_ok, lifecycle_reservation = boss:begin_action(begin_request('h'), actor_is_current)
    truthy(lifecycle_reservation_ok, 'a current actor can reserve before lifecycle invalidation')
    local lifecycle_cancel = boss:invalidate_actor('h', 1)
    local lifecycle_cancel_command = lifecycle_cancel.commands[1]
    equal(lifecycle_cancel_command.type, 'cancel_encounter_action_reservation',
        'Boss lifecycle invalidation emits a concrete cancellation command')
    equal(lifecycle_cancel_command.encounter_key, 'HG_E_JIAO_KING',
        'Boss lifecycle cancellation carries the encounter key')
    equal(lifecycle_cancel_command.lifecycle_id, 1,
        'Boss lifecycle cancellation preserves the invalidated lifecycle')
    equal(lifecycle_cancel_command.action_token, lifecycle_reservation.action_token,
        'Boss lifecycle cancellation preserves the original reservation token')
    for _, actor_id in ipairs({ 'd', 'e' }) do
        local ok, reservation = boss:begin_action(begin_request(actor_id), actor_is_current)
        truthy(ok, 'the formal action window reserves an actor read')
        reservations[actor_id] = reservation
    end
    local full, full_error = boss:begin_action(begin_request('f'), actor_is_current)
    equal(full, false, 'the window enforces its concurrent reservation cap')
    equal(full_error, 'action-concurrency-full', 'concurrency rejection is explicit')

    authority:set_watermark(4)
    local expiration = boss:tick(4)
    equal(next(boss.active_actions), nil, 'expired read reservations release inside the same action window')
    local expiration_command = nil
    for _, command in ipairs(expiration.commands) do
        if command.type == 'cancel_encounter_action_reservation' and command.actor_id == 'd' then
            expiration_command = command
        end
    end
    truthy(expiration_command, 'expiration emits a concrete cancellation for the old reservation')
    equal(expiration_command.encounter_key, 'HG_E_JIAO_KING',
        'expired reservation cancellation carries the encounter key')
    equal(expiration_command.lifecycle_id, 1,
        'expired reservation cancellation carries the old lifecycle')
    equal(expiration_command.action_token, reservations.d.action_token,
        'expired reservation cancellation carries the old action token')
    local expired_event = {
        kind = 'encounter_action_success', event_id = action_window.window_id .. ':d',
        actor_id = 'd', lifecycle_id = 1, combat_scope = 'public', boss_instance_id = 'jiao-1', phase_id = 'phase-1',
        window_id = action_window.window_id, mechanic_occurrence_id = action_window.mechanic_occurrence_id,
        encounter_action_key = action_window.encounter_action_key,
        interaction_unit_id = action_window.interaction_unit_id,
        interaction_unit_lifecycle_id = action_window.interaction_unit_lifecycle_id,
        boss_target_id = 'jiao-unit', boss_target_lifecycle_id = 'jiao-life',
        action_token = reservations.d.action_token,
    }
    local expired_ok = boss:complete_action(expired_event, actor_is_current)
    equal(expired_ok, false, 'an expired read cannot complete after its slot was released')

    authority:set_now(4)
    for _, actor_id in ipairs({ 'f', 'g' }) do
        local ok, reservation = boss:begin_action(begin_request(actor_id), actor_is_current)
        truthy(ok, 'released slots admit new actors in the same window')
        reservations[actor_id] = reservation
    end
end

local function action_event(actor_id, overrides)
    local event = {
        kind = 'encounter_action_success',
        event_id = action_window.window_id .. ':' .. actor_id,
        actor_id = actor_id,
        lifecycle_id = current[actor_id],
        combat_scope = 'public',
        boss_instance_id = 'jiao-1',
        phase_id = 'phase-1',
        window_id = action_window.window_id,
        mechanic_occurrence_id = action_window.mechanic_occurrence_id,
        encounter_action_key = action_window.encounter_action_key,
        interaction_unit_id = action_window.interaction_unit_id,
        interaction_unit_lifecycle_id = action_window.interaction_unit_lifecycle_id,
        boss_target_id = 'jiao-unit',
        boss_target_lifecycle_id = 'jiao-life',
        action_token = reservations[actor_id].action_token,
    }
    for key, item in pairs(overrides or {}) do event[key] = item end
    return event
end

do
    local legacy = action_event('f', { kind = 'encounter_action' })
    local legacy_ok, legacy_error = boss:complete_action(legacy, actor_is_current)
    equal(legacy_ok, false, 'public Boss completion rejects the legacy encounter_action kind')
    equal(legacy_error, 'expected-encounter-action-success', 'legacy action failure is explicit')

    local wrong_instance = action_event('f', { boss_instance_id = 'jiao-other' })
    local wrong_ok, wrong_error = boss:complete_action(wrong_instance, actor_is_current)
    equal(wrong_ok, false, 'an action event from another Boss instance is rejected')
    equal(wrong_error, 'stale-boss-instance', 'wrong Boss instance has a stable rejection')

    local stale_lifecycle = action_event('f', {
        lifecycle_id = 99,
    })
    local stale_ok, stale_error = boss:complete_action(stale_lifecycle, actor_is_current)
    equal(stale_ok, false, 'an old actor lifecycle cannot complete a reserved action')
    equal(stale_error, 'stale-actor-lifecycle', 'action lifecycle is checked before event_id is consumed')

    local forged = action_event('f', { authority_verified = true })
    local forged_ok, forged_error = boss:complete_action(forged, actor_is_current)
    equal(forged_ok, false, 'caller authority booleans cannot prove an action completion')
    equal(forged_error, 'untrusted-authority-field:authority_verified',
        'forged action completion authority is rejected explicitly')

    authority:set_completion(action_event('g').event_id, 6)
    authority:set_completion(action_event('f').event_id, 5)
    local later_ok, later_result = boss:complete_action(action_event('g'), actor_is_current)
    truthy(later_ok, 'the later trusted completion can arrive first and remain queued')
    equal(later_result.queued, true, 'a single completion waits for a trusted watermark')
    equal(boss.action_windows[action_window.window_id].primary_actor_id, nil,
        'arrival alone cannot claim primary ownership')

    local earlier_ok, earlier_result = boss:complete_action(action_event('f'), actor_is_current)
    truthy(earlier_ok, 'the earlier trusted completion can arrive second and remain queued')
    equal(earlier_result.queued, true, 'the second arrival also waits for settlement')

    authority:set_watermark(6)
    local settled = boss:tick(6)
    equal(settled.action_results[1].actor_id, 'f',
        'lower completed_tick wins primary regardless of network arrival order')
    equal(settled.action_results[1].completion_mode, 'primary', 'the stable first completion owns primary')
    equal(settled.action_results[2].actor_id, 'g', 'the later completion settles second')
    equal(settled.action_results[2].completion_mode, 'assist', 'the other completion is an assist')
    equal(boss.action_windows[action_window.window_id].primary_actor_id, 'f',
        'primary ownership is written exactly once to the window')
end

do
    local paused_boss, paused_authority, pause = new_submerged_boss_fixture('phase-cleanup')
    local pause_transition = {
        kind = 'boss_phase_transition',
        event_id = 'phase:jiao:pause-cleanup',
        combat_scope = 'public',
        boss_instance_id = paused_boss.boss_instance_id,
        from_phase = paused_boss.phase_id,
        boss_target_id = paused_boss.target_id,
        boss_target_lifecycle_id = paused_boss.target_lifecycle_id,
        to_phase = 'phase-2',
        next_boss_target_id = paused_boss.boss_instance_id .. '-unit-2',
        next_boss_target_lifecycle_id = paused_boss.boss_instance_id .. '-life-2',
        reason = 'phase_changed',
    }
    local phase_ok, phase_result = paused_boss:change_phase(pause_transition)
    truthy(phase_ok, 'phase transition succeeds while trace pause is active')
    local trace_resume = find_command(phase_result.commands, 'trace_resume')
    truthy(trace_resume, 'phase transition resumes active trace pause before mutating identity')
    equal(trace_resume.pause_id, pause.pause_id, 'phase transition resumes the original pause identity')
    equal(trace_resume.reason, 'phase_changed', 'phase transition records the resume reason')
    equal(paused_boss.trace_pause_id, nil, 'phase transition clears trace pause identity')
    equal(paused_boss.trace_pause_until, nil, 'phase transition clears trace pause deadline')
    equal(paused_boss.submerged, false, 'phase transition clears submerged state')
    paused_authority:set_watermark(3)
    equal(find_command(paused_boss:tick(3).commands, 'trace_resume'), nil,
        'phase transition trace cleanup is not repeated on the old deadline')
end

do
    local final_boss, final_authority, pause = new_submerged_boss_fixture('final-cleanup')
    local pause_finalization = {
        kind = 'boss_finalization',
        event_id = 'final:jiao:pause-cleanup',
        combat_scope = 'public',
        boss_instance_id = final_boss.boss_instance_id,
        from_phase = final_boss.phase_id,
        boss_target_id = final_boss.target_id,
        boss_target_lifecycle_id = final_boss.target_lifecycle_id,
        reason = 'timeout',
    }
    local summary = final_boss:finalize(pause_finalization)
    truthy(summary, 'finalization succeeds while trace pause is active')
    local trace_resume = find_command(summary.commands, 'trace_resume')
    truthy(trace_resume, 'finalization resumes active trace pause before ending Boss')
    equal(trace_resume.pause_id, pause.pause_id, 'finalization resumes the original pause identity')
    equal(trace_resume.reason, 'timeout', 'finalization records the resume reason')
    equal(final_boss.trace_pause_id, nil, 'finalization clears trace pause identity')
    equal(final_boss.trace_pause_until, nil, 'finalization clears trace pause deadline')
    equal(final_boss.submerged, false, 'finalization clears submerged state')
    final_authority:set_watermark(3)
    equal(find_command(final_boss:tick(3).commands, 'trace_resume'), nil,
        'finalization trace cleanup is not repeated on the old deadline')
end

local phase_transition_event = {
    kind = 'boss_phase_transition',
    event_id = 'phase:jiao:1',
    combat_scope = 'public',
    boss_instance_id = 'jiao-1',
    from_phase = 'phase-1',
    boss_target_id = 'jiao-unit',
    boss_target_lifecycle_id = 'jiao-life',
    to_phase = 'phase-2',
    next_boss_target_id = 'jiao-unit-2',
    next_boss_target_lifecycle_id = 'jiao-life-2',
    reason = 'phase_changed',
}

do
    authority:set_now(6)
    local reserve_ok = boss:begin_action(begin_request('h'), actor_is_current)
    truthy(reserve_ok, 'an action reservation exists before phase transition')

    local forged_transition = copy_table(phase_transition_event)
    forged_transition.event_id = 'phase:jiao:forged'
    authority:reject_event(forged_transition.event_id)
    local forged_phase_ok, forged_phase_error = boss:change_phase(forged_transition)
    equal(forged_phase_ok, false, 'a structurally valid phase transition still requires trusted authority')
    equal(forged_phase_error, 'authority-proof-rejected:public_boss_phase_transition',
        'forged phase transition is rejected by the provider')

    local wrong_scope = copy_table(phase_transition_event)
    wrong_scope.event_id = 'phase:jiao:wrong-scope'
    wrong_scope.combat_scope = 'team_instance'
    local wrong_scope_ok, wrong_scope_error = boss:change_phase(wrong_scope)
    equal(wrong_scope_ok, false, 'a non-public phase transition cannot mutate a public Boss')
    equal(wrong_scope_error, 'invalid-public-boss-identity-scope',
        'phase transition scope rejection is explicit')
    local session_bound = copy_table(phase_transition_event)
    session_bound.event_id = 'phase:jiao:session-bound'
    session_bound.session_instance_id = 'raid:forged'
    local session_bound_ok, session_bound_error = boss:change_phase(session_bound)
    equal(session_bound_ok, false, 'a phase transition carrying an instance session is rejected')
    equal(session_bound_error, 'invalid-public-boss-identity-scope',
        'phase transition session rejection is explicit')

    local phase_ok, phase_result = boss:change_phase(phase_transition_event)
    truthy(phase_ok, 'a CAS phase event can transition to a new explicit target lifecycle')
    equal(next(boss.active_actions), nil, 'phase transition clears all action reservations')
    truthy(#phase_result.commands > 0, 'phase transition emits reservation/window cleanup commands')

    local duplicate, duplicate_error = boss:change_phase(phase_transition_event)
    equal(duplicate, false, 'the same phase transition event is deduplicated')
    equal(duplicate_error, 'duplicate-boss-phase-transition', 'phase transition duplicate has a stable error')

    local conflicting = copy_table(phase_transition_event)
    conflicting.to_phase = 'phase-3'
    local conflict_ok, conflict_error = boss:change_phase(conflicting)
    equal(conflict_ok, false, 'a reused transition event_id cannot change its target phase')
    equal(conflict_error, 'boss-identity-event-conflict', 'changed transition identity is explicit')

    local late = copy_table(phase_transition_event)
    late.event_id = 'phase:jiao:late'
    local late_ok, late_error = boss:change_phase(late)
    equal(late_ok, false, 'an out-of-order old phase callback is rejected')
    equal(late_error, 'stale-boss-phase', 'old phase callback has a stable rejection')

    local stale_target = copy_table(phase_transition_event)
    stale_target.event_id = 'phase:jiao:stale-target'
    stale_target.from_phase = 'phase-2'
    stale_target.to_phase = 'phase-3'
    local stale_target_ok, stale_target_error = boss:change_phase(stale_target)
    equal(stale_target_ok, false, 'a phase callback must compare the current Boss target lifecycle')
    equal(stale_target_error, 'stale-boss-target', 'stale Boss target callback has a stable rejection')

    local rollback = {
        kind = 'boss_phase_transition',
        event_id = 'phase:jiao:rollback',
        combat_scope = 'public',
        boss_instance_id = 'jiao-1',
        from_phase = 'phase-2',
        boss_target_id = 'jiao-unit-2',
        boss_target_lifecycle_id = 'jiao-life-2',
        to_phase = 'phase-1',
        next_boss_target_id = 'jiao-unit',
        next_boss_target_lifecycle_id = 'jiao-life',
    }
    local rollback_ok, rollback_error = boss:change_phase(rollback)
    equal(rollback_ok, false, 'a CAS phase event cannot roll back to an entered phase')
    equal(rollback_error, 'boss-phase-rollback', 'phase rollback has a stable rejection')

    local old_phase = combat_event('final_damage', 'a', 2, 'damage:old-phase', 1, {
        phase_id = 'phase-1', target_id = 'jiao-unit', target_lifecycle_id = 'jiao-life',
    })
    local old_ok, old_error = boss:record_damage(old_phase, actor_is_current)
    equal(old_ok, false, 'an event from the previous Boss phase is rejected')
    equal(old_error, 'stale-boss-phase', 'old phase rejection is explicit')
end

local finalization_event = {
    kind = 'boss_finalization',
    event_id = 'final:jiao:1',
    combat_scope = 'public',
    boss_instance_id = 'jiao-1',
    from_phase = 'phase-2',
    boss_target_id = 'jiao-unit-2',
    boss_target_lifecycle_id = 'jiao-life-2',
    reason = 'defeated',
}

do
    local late_finalization = copy_table(finalization_event)
    late_finalization.event_id = 'final:jiao:late'
    late_finalization.from_phase = 'phase-1'
    late_finalization.boss_target_id = 'jiao-unit'
    late_finalization.boss_target_lifecycle_id = 'jiao-life'
    local late_summary, late_error = boss:finalize(late_finalization)
    equal(late_summary, nil, 'an out-of-order finalization cannot end the current Boss')
    equal(late_error, 'stale-boss-phase', 'out-of-order finalization has a stable rejection')

    local forged_finalization = copy_table(finalization_event)
    forged_finalization.event_id = 'final:jiao:forged'
    authority:reject_event(forged_finalization.event_id)
    local forged_summary, forged_error = boss:finalize(forged_finalization)
    equal(forged_summary, nil, 'a structurally valid finalization still requires trusted authority')
    equal(forged_error, 'authority-proof-rejected:public_boss_finalization',
        'forged finalization is rejected by the provider')

    local finalization_scope = copy_table(finalization_event)
    finalization_scope.event_id = 'final:jiao:wrong-scope'
    finalization_scope.combat_scope = 'solo_instance'
    local scoped_summary, scoped_error = boss:finalize(finalization_scope)
    equal(scoped_summary, nil, 'a non-public finalization cannot end a public Boss')
    equal(scoped_error, 'invalid-public-boss-identity-scope',
        'finalization scope rejection is explicit')

    local summary = boss:finalize(finalization_event)
    equal(summary.finalization_event_id, finalization_event.event_id, 'final summary carries its stable event identity')
    equal(summary.principal_actor_id, 'a', 'damage totals survive lifecycle upgrade and still determine principal DPS')
    truthy(contains(summary.effective_participant_ids, 'b'),
        'the actor who reached the break threshold is an effective participant without damage')
    truthy(contains(summary.effective_participant_ids, 'c'),
        'the actor who reached the protection threshold is an effective participant without damage')
    truthy(contains(summary.effective_participant_ids, 'f'),
        'the primary action actor is an effective participant')
    truthy(contains(summary.effective_participant_ids, 'g'),
        'the assist action actor is an effective participant')
    equal(contains(summary.effective_participant_ids, 'h'), false,
        'a cancelled reservation alone never grants effective participation')

    local duplicate, duplicate_error = boss:finalize(finalization_event)
    equal(duplicate, nil, 'the same finalization event is deduplicated')
    equal(duplicate_error, 'duplicate-boss-finalization', 'finalization duplicate has a stable error')

    local conflicting = copy_table(finalization_event)
    conflicting.reason = 'timeout'
    local conflict_summary, conflict_error = boss:finalize(conflicting)
    equal(conflict_summary, nil, 'a reused finalization event_id cannot alter the end reason')
    equal(conflict_error, 'boss-identity-event-conflict', 'changed finalization identity is explicit')
end

do
    local reused_transition_boss = PublicBoss.new('HG_E_JIAO_KING', encounter, {
        boss_instance_id = 'jiao-1',
        target_id = 'jiao-reused-unit',
        target_lifecycle_id = 'jiao-reused-life',
        skill_validator = skill_validator,
    })
    local old_transition_ok, old_transition_error = reused_transition_boss:change_phase(phase_transition_event)
    equal(old_transition_ok, false, 'reused boss_instance_id rejects an old phase callback by target lifecycle')
    equal(old_transition_error, 'stale-boss-target', 'reused phase callback has a stable rejection')

    local reused_finalization_boss = PublicBoss.new('HG_E_JIAO_KING', encounter, {
        boss_instance_id = 'jiao-1',
        phase_id = 'phase-2',
        target_id = 'jiao-reused-unit-2',
        target_lifecycle_id = 'jiao-reused-life-2',
        skill_validator = skill_validator,
    })
    local old_summary, old_finalization_error = reused_finalization_boss:finalize(finalization_event)
    equal(old_summary, nil, 'reused boss_instance_id rejects an old finalization callback by target lifecycle')
    equal(old_finalization_error, 'stale-boss-target', 'reused finalization callback has a stable rejection')
end

print('PASS: ' .. tests .. ' public boss assertions')
