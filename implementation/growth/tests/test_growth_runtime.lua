package.path = 'implementation/growth/lua/?.lua;' .. package.path

local Runtime = require 'growth_runtime'
local Config = require 'growth_config'

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

local function falsy(value, message)
    tests = tests + 1
    if value then error(message or 'expected falsy value') end
end

local function xp_request(owner_id, event_id, source_key, alive, qualified)
    return {
        owner_scope = 'character',
        owner_id = owner_id,
        resource_table_version = Config.resource_table_version,
        event_id = event_id,
        source_key = source_key,
        actor_alive = alive,
        party_qualified = qualified,
    }
end

local function reward_request(owner_id, event_id, profile_key, slot, evidence, roll, encounter_qualified)
    return {
        owner_scope = 'character',
        owner_id = owner_id,
        resource_table_version = Config.resource_table_version,
        event_id = event_id,
        profile_key = profile_key,
        reward_slot_key = slot or 'primary',
        qualification_snapshot_id = 'snap:' .. event_id,
        evidence = evidence,
        roll_basis_points = roll,
        encounter_qualified = encounter_qualified,
    }
end

local function table_is_empty(value)
    for _ in pairs(value) do return false end
    return true
end

local function team_member(owner_id, overrides)
    local member = {
        owner_id = owner_id,
        joined_before_lock = true,
        present_at_completion = true,
        actor_alive_at_completion = true,
        contribution_attested = true,
        rare_clear_attested = true,
    }
    for key, value in pairs(overrides or {}) do member[key] = value end
    return member
end

local function team_snapshot(event_id, snapshot_id, members, overrides)
    local snapshot = {
        schema_version = 1,
        policy_id = Config.team_raid_qualification_policy.policy_id,
        snapshot_id = snapshot_id,
        raid_instance_id = 'raid-instance:' .. event_id,
        completion_event_id = event_id,
        profile_key = 'HG_DROP_OX_RAID',
        completed = true,
        rare_clear_attested = true,
        authority_proof_ref = 'fixture:team-raid:' .. event_id,
        members = members,
    }
    for key, value in pairs(overrides or {}) do snapshot[key] = value end
    return snapshot
end

local function team_reward_request(owner_id, event_id, snapshot, roll)
    local request = reward_request(owner_id, event_id, 'HG_DROP_OX_RAID', 'raid', nil, roll, nil)
    request.qualification_snapshot_id = snapshot.snapshot_id
    request.team_snapshot = snapshot
    return request
end

truthy(Runtime.validate_config(), 'growth config validates')

local state, state_error = Runtime.new_state('hero-a')
truthy(state, state_error)
local invalid_state, invalid_state_error = Runtime.new_state('')
falsy(invalid_state, 'empty owner is rejected')
equal(invalid_state_error, 'invalid-owner-id', 'empty owner error is stable')

local ok, xp, replayed = Runtime.grant_xp(state, xp_request('hero-a', 'xp-1', 'XP_INTRO', true, true))
truthy(ok, xp)
equal(xp.awarded_xp, 100, 'intro award is deterministic')
equal(state.level, 2, 'intro reaches level two')
falsy(replayed, 'first XP receipt is new')
local before_replay_xp = state.total_xp
ok, xp, replayed = Runtime.grant_xp(state, xp_request('hero-a', 'xp-1', 'XP_INTRO', false, true))
truthy(ok, xp)
truthy(replayed, 'same XP receipt replays after reconnect')
equal(state.total_xp, before_replay_xp, 'replayed XP receipt does not change XP')
ok, xp = Runtime.grant_xp(state, xp_request('hero-a', 'xp-1', 'XP_MOUNTAIN', true, true))
falsy(ok, 'same XP event cannot change source')
equal(xp, 'xp-event-origin-conflict', 'XP conflict error is stable')
ok, xp = Runtime.grant_xp(state, xp_request('hero-a', 'xp-dead', 'XP_MOUNTAIN', false, true))
falsy(ok, 'dead actor cannot receive new XP')
equal(xp, 'actor-not-alive', 'death rule error is stable')
ok, xp = Runtime.grant_xp(state, xp_request('hero-a', 'xp-unqualified', 'XP_MOUNTAIN', true, false))
falsy(ok, 'unqualified party member cannot receive XP')
equal(xp, 'party-qualification-required', 'party qualification error is stable')

local overleveled, overleveled_error = Runtime.new_state('hero-over')
truthy(overleveled, overleveled_error)
overleveled.total_xp = 1935
overleveled.level = 10
ok, xp = Runtime.grant_xp(overleveled, xp_request('hero-over', 'xp-over', 'XP_INTRO', true, true))
truthy(ok, xp)
equal(xp.multiplier, 0.20, 'over-level multiplier reaches its floor')
equal(xp.awarded_xp, 20, 'over-level XP award is floored deterministically')

local action_only = Runtime.resolve_public_qualification({ valid_public_action = true, public_action_window_opened = true })
truthy(action_only.progression_participation, 'action can grant progression participation')
falsy(action_only.participation_chest_eligibility, 'action alone cannot grant an action-window chest')
falsy(action_only.rare_drop_eligibility, 'action alone cannot grant rare eligibility')
local chest_only = Runtime.resolve_public_qualification({ damage_ratio = 0.04, valid_public_action = true, public_action_window_opened = true })
truthy(chest_only.participation_chest_eligibility, 'damage plus action grants chest')
falsy(chest_only.rare_drop_eligibility, 'chest does not imply rare eligibility')
local rare_qualified = Runtime.resolve_public_qualification({ damage_ratio = 0.04, valid_public_action = true, public_action_window_opened = true, rare_clear_attested = true })
truthy(rare_qualified.rare_drop_eligibility, 'authority attestation opens rare eligibility')
equal(rare_qualified.candidate_policy_id, 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION',
    'qualification identifies the selected P1 simulation candidate without calling it final')
equal(rare_qualified.source_decision_status, 'conflict',
    'qualification preserves the unresolved source-decision status')

local rewards, rewards_error = Runtime.new_state('hero-reward')
truthy(rewards, rewards_error)
ok, xp = Runtime.settle_reward(rewards, reward_request('hero-reward', 'rw-normal', 'HG_DROP_MOUNTAIN_COMMON', 'primary', nil, nil, true))
truthy(ok, xp)
equal(rewards.resources.CUR_GOLD, 8, 'normal reward grants gold')
local normal_gold = rewards.resources.CUR_GOLD
ok, xp, replayed = Runtime.settle_reward(rewards, reward_request('hero-reward', 'rw-normal', 'HG_DROP_MOUNTAIN_COMMON', 'primary', nil, nil, true))
truthy(ok, xp)
truthy(replayed, 'normal reward receipt replays')
equal(rewards.resources.CUR_GOLD, normal_gold, 'replayed reward does not add currency')
ok, xp = Runtime.settle_reward(rewards, reward_request('hero-reward', 'rw-normal', 'HG_DROP_MOUNTAIN_ELITE', 'primary', nil, nil, true))
falsy(ok, 'same reward event and slot cannot change profile')
equal(xp, 'reward-event-origin-conflict', 'reward conflict error is stable')

ok, xp = Runtime.settle_reward(rewards, reward_request('hero-reward', 'rw-public-invalid', 'HG_DROP_MACAQUE_PUBLIC', 'primary', { valid_public_action = true, public_action_window_opened = true }, 9000, nil))
falsy(ok, 'public chest is denied without damage, break, or guard')
equal(xp, 'public-chest-not-qualified', 'invalid public chest error is stable')

local evidence = { damage_ratio = 0.10, valid_public_action = true, public_action_window_opened = true, rare_clear_attested = true }

-- A malformed rare roll must be rejected before any reward-visible state changes.
local invalid_roll_state, invalid_roll_state_error = Runtime.new_state('hero-invalid-roll')
truthy(invalid_roll_state, invalid_roll_state_error)
ok, xp = Runtime.settle_reward(invalid_roll_state, reward_request(
    'hero-invalid-roll', 'rw-invalid-roll', 'HG_DROP_MACAQUE_PUBLIC', 'primary', evidence, 0, nil
))
falsy(ok, 'invalid rare roll is rejected')
equal(xp, 'invalid-rare-roll', 'invalid rare roll error is stable')
truthy(table_is_empty(invalid_roll_state.resources), 'invalid rare roll leaves resources unchanged')
truthy(table_is_empty(invalid_roll_state.unique_resources), 'invalid rare roll leaves uniques unchanged')
truthy(table_is_empty(invalid_roll_state.first_clears), 'invalid rare roll leaves first clears unchanged')
truthy(table_is_empty(invalid_roll_state.pity_progress), 'invalid rare roll leaves pity unchanged')
truthy(table_is_empty(invalid_roll_state.reward_receipts), 'invalid rare roll leaves receipts unchanged')
truthy(table_is_empty(invalid_roll_state.reward_event_origins), 'invalid rare roll leaves event origins unchanged')
ok, xp, replayed = Runtime.settle_reward(invalid_roll_state, reward_request(
    'hero-invalid-roll', 'rw-invalid-roll', 'HG_DROP_MACAQUE_PUBLIC', 'primary', evidence, 9000, nil
))
truthy(ok, xp)
falsy(replayed, 'a corrected retry is not treated as an already-settled receipt')

for _, invalid_case in ipairs({
    { id = 'nan', roll = 0 / 0 },
    { id = 'fractional', roll = 1.5 },
}) do
    local malformed_roll_state, malformed_roll_state_error = Runtime.new_state('hero-invalid-roll-' .. invalid_case.id)
    truthy(malformed_roll_state, malformed_roll_state_error)
    ok, xp = Runtime.settle_reward(malformed_roll_state, reward_request(
        'hero-invalid-roll-' .. invalid_case.id,
        'rw-invalid-roll-' .. invalid_case.id,
        'HG_DROP_MACAQUE_PUBLIC', 'primary', evidence, invalid_case.roll, nil
    ))
    falsy(ok, invalid_case.id .. ' rare roll is rejected')
    equal(xp, 'invalid-rare-roll', invalid_case.id .. ' rare roll error is stable')
    truthy(table_is_empty(malformed_roll_state.resources), invalid_case.id .. ' rare roll leaves resources unchanged')
    truthy(table_is_empty(malformed_roll_state.unique_resources), invalid_case.id .. ' rare roll leaves uniques unchanged')
    truthy(table_is_empty(malformed_roll_state.first_clears), invalid_case.id .. ' rare roll leaves first clears unchanged')
    truthy(table_is_empty(malformed_roll_state.pity_progress), invalid_case.id .. ' rare roll leaves pity unchanged')
    truthy(table_is_empty(malformed_roll_state.reward_receipts), invalid_case.id .. ' rare roll leaves receipts unchanged')
    truthy(table_is_empty(malformed_roll_state.reward_event_origins), invalid_case.id .. ' rare roll leaves event origins unchanged')
end

-- HG_DROP_OX_RAID is a team-raid contract, not an encounter_qualified bypass.
local four_member_snapshot = team_snapshot('rw-raid-hit', 'snap:rw-raid-hit', {
    team_member('hero-raid'), team_member('hero-raid-b'),
    team_member('hero-raid-c'), team_member('hero-raid-d'),
})
local team_qualification, team_qualification_error = Runtime.resolve_team_raid_qualification(
    four_member_snapshot, 'hero-raid', 'HG_DROP_OX_RAID', 'rw-raid-hit', 'snap:rw-raid-hit'
)
truthy(team_qualification, team_qualification_error)
equal(team_qualification.team_size, 4, 'four-member team snapshot is accepted')
truthy(team_qualification.participation_chest_eligibility, 'attested team member receives raid participation eligibility')
truthy(team_qualification.rare_drop_eligibility, 'attested team member receives raid rare eligibility')
local personal_rare_denied_qualification, personal_rare_denied_error = Runtime.resolve_team_raid_qualification(
    team_snapshot('rw-raid-personal-rare-denied', 'snap:rw-raid-personal-rare-denied', {
        team_member('hero-raid', { rare_clear_attested = false }),
    }),
    'hero-raid', 'HG_DROP_OX_RAID', 'rw-raid-personal-rare-denied', 'snap:rw-raid-personal-rare-denied'
)
truthy(personal_rare_denied_qualification, personal_rare_denied_error)
truthy(personal_rare_denied_qualification.participation_chest_eligibility, 'team participation can remain valid without personal rare attestation')
falsy(personal_rare_denied_qualification.rare_drop_eligibility, 'team clear alone cannot grant a member rare eligibility')

local empty_team_qualification, empty_team_error = Runtime.resolve_team_raid_qualification(
    team_snapshot('rw-raid-empty', 'snap:rw-raid-empty', {}),
    'hero-raid', 'HG_DROP_OX_RAID', 'rw-raid-empty', 'snap:rw-raid-empty'
)
falsy(empty_team_qualification, 'zero-member team snapshot is rejected')
equal(empty_team_error, 'team-member-count-out-of-range', 'zero-member error is stable')
local oversized_team_qualification, oversized_team_error = Runtime.resolve_team_raid_qualification(
    team_snapshot('rw-raid-five', 'snap:rw-raid-five', {
        team_member('hero-raid'), team_member('hero-raid-b'), team_member('hero-raid-c'),
        team_member('hero-raid-d'), team_member('hero-raid-e'),
    }),
    'hero-raid', 'HG_DROP_OX_RAID', 'rw-raid-five', 'snap:rw-raid-five'
)
falsy(oversized_team_qualification, 'five-member team snapshot is rejected')
equal(oversized_team_error, 'team-member-count-out-of-range', 'five-member error is stable')
local proof_missing_qualification, proof_missing_error = Runtime.resolve_team_raid_qualification(
    team_snapshot('rw-raid-proof', 'snap:rw-raid-proof', { team_member('hero-raid') }, { authority_proof_ref = '' }),
    'hero-raid', 'HG_DROP_OX_RAID', 'rw-raid-proof', 'snap:rw-raid-proof'
)
falsy(proof_missing_qualification, 'raid snapshot requires an authority proof reference')
equal(proof_missing_error, 'team-authority-proof-required', 'missing team proof error is stable')
local member_field_missing = team_member('hero-raid')
member_field_missing.contribution_attested = nil
local member_field_missing_qualification, member_field_missing_error = Runtime.resolve_team_raid_qualification(
    team_snapshot('rw-raid-member-field', 'snap:rw-raid-member-field', { member_field_missing }),
    'hero-raid', 'HG_DROP_OX_RAID', 'rw-raid-member-field', 'snap:rw-raid-member-field'
)
falsy(member_field_missing_qualification, 'raid snapshot requires every member attestation field')
equal(member_field_missing_error, 'team-member-attestation-required', 'missing member attestation error is stable')
local mismatch_qualification, mismatch_error = Runtime.resolve_team_raid_qualification(
    team_snapshot('rw-raid-mismatch', 'snap:rw-raid-mismatch', { team_member('hero-raid') }),
    'hero-raid', 'HG_DROP_OX_RAID', 'rw-raid-mismatch', 'snap:other'
)
falsy(mismatch_qualification, 'raid snapshot id must match the settlement request')
equal(mismatch_error, 'team-snapshot-id-mismatch', 'team snapshot id mismatch error is stable')

local missing_team_state, missing_team_state_error = Runtime.new_state('hero-no-team')
truthy(missing_team_state, missing_team_state_error)
ok, xp = Runtime.settle_reward(missing_team_state, reward_request(
    'hero-no-team', 'rw-no-team-snapshot', 'HG_DROP_OX_RAID', 'raid', nil, 1, true
))
falsy(ok, 'encounter_qualified cannot bypass the required team snapshot')
equal(xp, 'team-qualification-snapshot-required', 'missing team snapshot error is stable')
truthy(table_is_empty(missing_team_state.resources), 'missing team snapshot has no reward side effects')

local raid_hit_state, raid_hit_state_error = Runtime.new_state('hero-raid')
truthy(raid_hit_state, raid_hit_state_error)
ok, xp, replayed = Runtime.settle_reward(raid_hit_state, team_reward_request(
    'hero-raid', 'rw-raid-hit', four_member_snapshot, 1
))
truthy(ok, xp)
falsy(replayed, 'first team-raid settlement is new')
truthy(xp.qualification.rare_drop_eligibility, 'team-raid receipt records rare qualification')
truthy(xp.rare.attempted, 'team-raid rare roll is attempted')
truthy(xp.rare.awarded, 'team-raid rare hit awards the configured unique')
equal(xp.rare.reason, 'roll-success', 'team-raid rare hit reason is stable')
truthy(raid_hit_state.unique_resources.ART_HG_FLAME_CORE, 'team-raid rare hit grants the flame core')
local raid_hit_gold = raid_hit_state.resources.CUR_GOLD
xp.rare.reason = 'tampered'
xp.awards[1].amount = -1
ok, xp, replayed = Runtime.settle_reward(raid_hit_state, team_reward_request(
    'hero-raid', 'rw-raid-hit', four_member_snapshot, 1
))
truthy(ok, xp)
truthy(replayed, 'team-raid receipt replays idempotently')
equal(raid_hit_state.resources.CUR_GOLD, raid_hit_gold, 'team-raid replay does not add currency')
equal(raid_hit_state.pity_progress.PITY_HG_RAID_ARTIFACT, 0, 'team-raid replay preserves the hit pity reset')
equal(xp.rare.reason, 'roll-success', 'team-raid replay returns an immutable receipt result')
equal(xp.awards[1].amount, 120, 'team-raid replay returns the original base award')

local raid_pity_state, raid_pity_state_error = Runtime.new_state('hero-raid-pity')
truthy(raid_pity_state, raid_pity_state_error)
for index = 1, 5 do
    local event_id = 'rw-raid-miss-' .. tostring(index)
    local snapshot = team_snapshot(event_id, 'snap:' .. event_id, { team_member('hero-raid-pity') })
    ok, xp = Runtime.settle_reward(raid_pity_state, team_reward_request('hero-raid-pity', event_id, snapshot, 10000))
    truthy(ok, xp)
    equal(xp.rare.reason, 'roll-miss', 'eligible team-raid miss is recorded')
    equal(raid_pity_state.pity_progress.PITY_HG_RAID_ARTIFACT, index, 'eligible team-raid miss advances pity')
end
local forced_event_id = 'rw-raid-pity-forced'
local forced_snapshot = team_snapshot(forced_event_id, 'snap:' .. forced_event_id, { team_member('hero-raid-pity') })
ok, xp = Runtime.settle_reward(raid_pity_state, team_reward_request('hero-raid-pity', forced_event_id, forced_snapshot, 10000))
truthy(ok, xp)
equal(xp.rare.reason, 'pity-forced', 'sixth eligible team-raid miss is pity-forced')
truthy(xp.rare.awarded, 'pity-forced team-raid result awards the rare')
truthy(raid_pity_state.unique_resources.ART_HG_FLAME_CORE, 'team-raid pity grants the flame core')
equal(raid_pity_state.pity_progress.PITY_HG_RAID_ARTIFACT, 0, 'team-raid pity resets after its forced award')

for index = 1, 5 do
    ok, xp = Runtime.settle_reward(rewards, reward_request('hero-reward', 'rw-public-' .. tostring(index), 'HG_DROP_MACAQUE_PUBLIC', 'primary', evidence, 9000, nil))
    truthy(ok, xp)
end
truthy(rewards.unique_resources.EQ_HG_WEAPON_T1, 'Macaque first clear grants first weapon')
truthy(rewards.unique_resources.EQ_HG_TRINKET_T1, 'fifth eligible rare miss is pity-forced')
equal(rewards.pity_progress.PITY_HG_PUBLIC_GEAR, 0, 'pity resets after a forced award')
local before_duplicate_conversion = rewards.resources.CUR_GOLD
ok, xp = Runtime.settle_reward(rewards, reward_request('hero-reward', 'rw-public-6', 'HG_DROP_MACAQUE_PUBLIC', 'primary', evidence, 1, nil))
truthy(ok, xp)
equal(xp.rare.result, 'converted', 'duplicate rare converts rather than granting a second unique')
equal(rewards.resources.CUR_GOLD, before_duplicate_conversion + 110 + 50, 'duplicate conversion and base bundle are both credited')

local spend_state, spend_error = Runtime.new_state('hero-spend')
truthy(spend_state, spend_error)
spend_state.resources.CUR_GOLD = 60
spend_state.resources.MAT_STRENGTHEN_SHARD = 3
ok, xp = Runtime.spend_intent(spend_state, {
    owner_scope = 'character', owner_id = 'hero-spend', resource_table_version = Config.resource_table_version,
    event_id = 'sp-1', intent_key = 'HG_ENHANCE_T1',
})
truthy(ok, xp)
truthy(spend_state.completed_intents.HG_ENHANCE_T1, 'enhancement intent is recorded')
equal(spend_state.resources.CUR_GOLD, 0, 'enhancement consumes gold')
ok, xp, replayed = Runtime.spend_intent(spend_state, {
    owner_scope = 'character', owner_id = 'hero-spend', resource_table_version = Config.resource_table_version,
    event_id = 'sp-1', intent_key = 'HG_ENHANCE_T1',
})
truthy(ok, xp)
truthy(replayed, 'spend receipt replays')
local poor_state, poor_error = Runtime.new_state('hero-poor')
truthy(poor_state, poor_error)
ok, xp = Runtime.spend_intent(poor_state, {
    owner_scope = 'character', owner_id = 'hero-poor', resource_table_version = Config.resource_table_version,
    event_id = 'sp-poor', intent_key = 'HG_ENHANCE_T1',
})
falsy(ok, 'insufficient cost is rejected')
equal(xp, 'insufficient-resource:CUR_GOLD', 'spend rejection names a missing resource')

local simulated, trace_state = Runtime.simulate_first_six_hours('hero-trace')
truthy(simulated, trace_state)
equal(trace_state.level, 20, 'six-hour trace reaches Lv20')
equal(trace_state.total_xp, 9485, 'six-hour trace reaches the exact Lv20 XP cap')
equal(trace_state.milestone_minutes.SKILL_SECOND_ACTIVE, 5, 'second active hits its planned minute')
equal(trace_state.milestone_minutes.CORE_ROUTE, 13, 'core route hits its planned minute')
equal(trace_state.milestone_minutes.FIRST_EQUIPMENT, 13, 'first equipment hits its planned minute')
equal(trace_state.milestone_minutes.FIRST_ENHANCEMENT, 20, 'first enhancement hits its planned minute')
equal(trace_state.milestone_minutes.FIRST_ARTIFACT, 75, 'first artifact hits its planned minute')
truthy(trace_state.unique_resources.EQ_HG_SET_GUARD_T1, 'trace includes a team-Boss build reward')
truthy(trace_state.resources.CUR_RAID_MARK >= 1, 'trace includes a character-owned raid mark')
equal(trace_state.timeline[#trace_state.timeline].minute, 360, 'trace closes at the six-hour active-time boundary')

print('PASS: ' .. tostring(tests) .. ' growth runtime assertions')
