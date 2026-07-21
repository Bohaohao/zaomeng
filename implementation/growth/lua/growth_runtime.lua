-- custom-built: deterministic, engine-neutral growth and settlement runtime.
local Config = require 'growth_config'

local M = {}

local function present(value)
    return value ~= nil and value ~= ''
end

local function non_empty_string(value)
    return type(value) == 'string' and value ~= '' and value == value:match('^%s*(.-)%s*$')
end

local function shallow_copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function dense_array_count(source)
    if type(source) ~= 'table' then return nil end
    local count = 0
    for index in pairs(source) do
        if type(index) ~= 'number' or index < 1 or index % 1 ~= 0 then return nil end
        count = count + 1
    end
    if count ~= #source then return nil end
    return count
end

local function is_boolean(value)
    return type(value) == 'boolean'
end

local function copy_list(source)
    local result = {}
    for index, value in ipairs(source or {}) do result[index] = shallow_copy(value) end
    return result
end

local function copy_reward_outcome(outcome)
    local result = shallow_copy(outcome)
    result.qualification = shallow_copy(outcome.qualification)
    result.awards = copy_list(outcome.awards)
    result.rare = shallow_copy(outcome.rare)
    return result
end

local function append(list, value)
    list[#list + 1] = value
end

local function sorted_keys(source)
    local keys = {}
    for key in pairs(source) do append(keys, key) end
    table.sort(keys)
    return keys
end

local function length_part(value)
    local text = tostring(value)
    return tostring(#text) .. ':' .. text
end

local function receipt_id(parts)
    local result = {}
    for _, part in ipairs(parts) do append(result, length_part(part)) end
    return table.concat(result, '|')
end

local function level_for_xp(total_xp)
    local current = Config.level_curve[1]
    for _, row in ipairs(Config.level_curve) do
        if total_xp >= row.cumulative_xp then current = row else break end
    end
    return current.level
end

local function cap_xp()
    return Config.level_curve[#Config.level_curve].cumulative_xp
end

local function over_level_multiplier(character_level, source_level)
    local over_level = character_level - source_level
    for _, rule in ipairs(Config.party_xp_policy.level_difference_multipliers) do
        if over_level <= rule.max_over_level then return rule.multiplier end
    end
    return 0
end

local function add_resource(state, resource_key, amount)
    state.resources[resource_key] = (state.resources[resource_key] or 0) + amount
end

local function award_unique(state, descriptor, awards)
    local key = descriptor.key
    if not Config.unique_resources[key] then return false, 'unknown-unique-resource:' .. tostring(key) end
    if state.unique_resources[key] then
        if not descriptor.conversion then return false, 'duplicate-unique-without-conversion:' .. key end
        add_resource(state, descriptor.conversion.key, descriptor.conversion.amount)
        append(awards, { key = descriptor.conversion.key, amount = descriptor.conversion.amount, converted_from = key })
        return true, 'converted'
    end
    state.unique_resources[key] = true
    append(awards, { key = key, amount = 1, unique = true })
    return true, 'granted'
end

local function reward_staging_state(state)
    return {
        resources = shallow_copy(state.resources),
        unique_resources = shallow_copy(state.unique_resources),
        first_clears = shallow_copy(state.first_clears),
        pity_progress = shallow_copy(state.pity_progress),
        reward_receipts = shallow_copy(state.reward_receipts),
        reward_event_origins = shallow_copy(state.reward_event_origins),
    }
end

local function commit_reward_staging(state, staged)
    state.resources = staged.resources
    state.unique_resources = staged.unique_resources
    state.first_clears = staged.first_clears
    state.pity_progress = staged.pity_progress
    state.reward_receipts = staged.reward_receipts
    state.reward_event_origins = staged.reward_event_origins
end

local function copy_simulation_team_snapshot(template, owner_id)
    local snapshot = shallow_copy(template)
    snapshot.members = {}
    for index, member in ipairs(template.members) do
        local copied_member = shallow_copy(member)
        if copied_member.owner_id == Config.offline_simulation_owner_placeholder then
            copied_member.owner_id = owner_id
        end
        snapshot.members[index] = copied_member
    end
    return snapshot
end

local function validate_owner(state, request)
    if type(request) ~= 'table' then return false, 'invalid-request' end
    if request.owner_scope ~= Config.owner_scope then return false, 'invalid-owner-scope' end
    if request.owner_id ~= state.owner_id then return false, 'owner-mismatch' end
    if request.resource_table_version ~= Config.resource_table_version then return false, 'resource-table-version-mismatch' end
    return true
end

local function settlement_receipt_id(request)
    return receipt_id({
        'reward', request.owner_scope, request.owner_id, request.event_id,
        request.profile_key, request.reward_slot_key, request.resource_table_version,
    })
end

local function xp_receipt_id(request)
    return receipt_id({
        'xp', request.owner_scope, request.owner_id, request.event_id,
        request.source_key, request.resource_table_version,
    })
end

local function spend_receipt_id(request)
    return receipt_id({
        'spend', request.owner_scope, request.owner_id, request.event_id,
        request.intent_key, request.resource_table_version,
    })
end

function M.validate_config()
    if Config.package_status ~= 'offline_candidate_simulation_not_adopted'
        or Config.execution_status ~= 'offline_simulation_ready'
        or Config.production_gate ~= 'closed'
        or Config.runtime_handoff ~= false
        or Config.resource_table_status ~= 'offline_candidate_not_adopted' then
        return false, 'invalid-offline-candidate-boundary'
    end
    local previous_cumulative = -1
    for index, row in ipairs(Config.level_curve) do
        if row.level ~= index then return false, 'level-curve-not-continuous' end
        if type(row.xp_to_next) ~= 'number' or row.xp_to_next < 0 then return false, 'invalid-xp-to-next' end
        if type(row.cumulative_xp) ~= 'number' or row.cumulative_xp <= previous_cumulative then
            return false, 'invalid-cumulative-xp'
        end
        if index == #Config.level_curve and row.xp_to_next ~= 0 then return false, 'cap-has-next-xp' end
        previous_cumulative = row.cumulative_xp
    end
    local profile_count = 0
    for _, profile in pairs(Config.reward_profiles) do
        profile_count = profile_count + 1
        if not Config.reward_bundles[profile.bundle] then return false, 'unknown-reward-bundle' end
    end
    if profile_count ~= 21 then return false, 'unexpected-profile-count' end
    if Config.public_chest_policy.candidate_policy_id ~= 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION'
        or Config.public_chest_policy.source_decision_id ~= 'ECO-P1-001'
        or Config.public_chest_policy.source_decision_status ~= 'conflict' then
        return false, 'unexpected-public-chest-policy'
    end
    local team_policy = Config.team_raid_qualification_policy
    if type(team_policy) ~= 'table'
        or team_policy.policy_id ~= 'F6H_TEAM_RAID_RARE_ELIGIBILITY_V1'
        or team_policy.snapshot_schema_version ~= 1
        or team_policy.min_members ~= 1
        or team_policy.max_members ~= 4 then
        return false, 'invalid-team-raid-qualification-policy'
    end
    local ox_raid = Config.reward_profiles.HG_DROP_OX_RAID
    if not ox_raid or ox_raid.scope ~= 'team_raid' or not ox_raid.rare then
        return false, 'invalid-ox-raid-profile'
    end
    return true
end

function M.new_state(owner_id)
    if not non_empty_string(owner_id) then return nil, 'invalid-owner-id' end
    return {
        owner_id = owner_id,
        total_xp = 0,
        level = 1,
        resources = {},
        unique_resources = {},
        first_clears = {},
        pity_progress = {},
        xp_receipts = {},
        reward_receipts = {},
        spend_receipts = {},
        xp_event_origins = {},
        reward_event_origins = {},
        spend_event_origins = {},
        completed_intents = {},
        milestone_minutes = {},
        timeline = {},
    }
end

function M.resolve_public_qualification(evidence)
    evidence = evidence or {}
    local damage = type(evidence.damage_ratio) == 'number' and evidence.damage_ratio >= 0.03
    local broke = evidence.valid_break == true
    local guarded = evidence.valid_guard == true
    local action = evidence.valid_public_action == true
    local action_window = evidence.public_action_window_opened == true
    local progression = damage or broke or guarded or action
    local chest = damage or broke or guarded
    if action_window then chest = action and chest end
    local rare = evidence.rare_clear_attested == true and progression and (damage or broke or guarded)
    return {
        progression_participation = progression,
        participation_chest_eligibility = chest,
        rare_drop_eligibility = rare,
        pity_eligible = rare,
        candidate_policy_id = Config.public_chest_policy.candidate_policy_id,
        source_decision_id = Config.public_chest_policy.source_decision_id,
        source_decision_status = Config.public_chest_policy.source_decision_status,
    }
end

-- Validates the authority-attested 1–4 person raid snapshot before reward code
-- can use it. A member may be listed but ineligible; malformed or uncorrelated
-- snapshots are rejected outright instead of being partially trusted.
function M.resolve_team_raid_qualification(snapshot, owner_id, profile_key, event_id, qualification_snapshot_id)
    local policy = Config.team_raid_qualification_policy
    if type(snapshot) ~= 'table' then return false, 'team-qualification-snapshot-required' end
    if snapshot.schema_version ~= policy.snapshot_schema_version then return false, 'team-snapshot-schema-version-mismatch' end
    if snapshot.policy_id ~= policy.policy_id then return false, 'team-snapshot-policy-mismatch' end
    if snapshot.snapshot_id ~= qualification_snapshot_id then return false, 'team-snapshot-id-mismatch' end
    if not non_empty_string(snapshot.raid_instance_id) then return false, 'team-raid-instance-required' end
    if snapshot.completion_event_id ~= event_id then return false, 'team-completion-event-mismatch' end
    if snapshot.profile_key ~= profile_key then return false, 'team-profile-mismatch' end
    if snapshot.completed ~= true then return false, 'team-raid-not-completed' end
    if not is_boolean(snapshot.rare_clear_attested) then return false, 'team-rare-clear-attestation-required' end
    if not non_empty_string(snapshot.authority_proof_ref) then return false, 'team-authority-proof-required' end

    local member_count = dense_array_count(snapshot.members)
    if not member_count then return false, 'team-members-must-be-dense-array' end
    if member_count < policy.min_members or member_count > policy.max_members then
        return false, 'team-member-count-out-of-range'
    end

    local seen_owners = {}
    local owner_member = nil
    for index = 1, member_count do
        local member = snapshot.members[index]
        if type(member) ~= 'table' or not non_empty_string(member.owner_id) then
            return false, 'team-member-owner-required'
        end
        if seen_owners[member.owner_id] then return false, 'duplicate-team-member-owner' end
        seen_owners[member.owner_id] = true
        if not is_boolean(member.joined_before_lock)
            or not is_boolean(member.present_at_completion)
            or not is_boolean(member.actor_alive_at_completion)
            or not is_boolean(member.contribution_attested)
            or not is_boolean(member.rare_clear_attested) then
            return false, 'team-member-attestation-required'
        end
        if member.owner_id == owner_id then owner_member = member end
    end
    if not owner_member then return false, 'team-owner-not-in-snapshot' end

    local participation = owner_member.joined_before_lock
        and owner_member.present_at_completion
        and owner_member.actor_alive_at_completion
        and owner_member.contribution_attested
    local rare = participation and snapshot.rare_clear_attested and owner_member.rare_clear_attested
    return {
        policy_id = policy.policy_id,
        team_size = member_count,
        raid_instance_id = snapshot.raid_instance_id,
        completion_event_id = snapshot.completion_event_id,
        progression_participation = participation,
        participation_chest_eligibility = participation,
        rare_drop_eligibility = rare,
        pity_eligible = rare,
    }
end

function M.grant_xp(state, request)
    local valid_owner, owner_error = validate_owner(state, request)
    if not valid_owner then return false, owner_error end
    if not non_empty_string(request.event_id) or not non_empty_string(request.source_key) then
        return false, 'xp-event-identity-required'
    end
    local id = xp_receipt_id(request)
    local existing = state.xp_receipts[id]
    if existing then return true, shallow_copy(existing), true end
    local source = Config.xp_sources[request.source_key]
    if not source then return false, 'unknown-xp-source' end
    local origin = request.source_key .. '|' .. request.resource_table_version
    local prior_origin = state.xp_event_origins[request.event_id]
    if prior_origin and prior_origin ~= origin then return false, 'xp-event-origin-conflict' end
    if request.party_qualified ~= true then return false, 'party-qualification-required' end
    if request.actor_alive ~= true then return false, 'actor-not-alive' end

    local multiplier = over_level_multiplier(state.level, source.source_level)
    local raw_award = math.floor(source.base_xp * multiplier)
    local before = state.total_xp
    state.total_xp = math.min(cap_xp(), before + raw_award)
    state.level = level_for_xp(state.total_xp)
    local outcome = {
        receipt_id = id,
        event_id = request.event_id,
        source_key = request.source_key,
        base_xp = source.base_xp,
        multiplier = multiplier,
        awarded_xp = state.total_xp - before,
        total_xp = state.total_xp,
        level = state.level,
    }
    state.xp_receipts[id] = outcome
    state.xp_event_origins[request.event_id] = origin
    return true, shallow_copy(outcome), false
end

function M.spend_intent(state, request)
    local valid_owner, owner_error = validate_owner(state, request)
    if not valid_owner then return false, owner_error end
    if not non_empty_string(request.event_id) or not non_empty_string(request.intent_key) then
        return false, 'spend-event-identity-required'
    end
    local id = spend_receipt_id(request)
    local existing = state.spend_receipts[id]
    if existing then return true, shallow_copy(existing), true end
    local cost = Config.enhancement_costs[request.intent_key]
    if not cost then return false, 'unknown-spend-intent' end
    local prior_origin = state.spend_event_origins[request.event_id]
    if prior_origin and prior_origin ~= request.intent_key then return false, 'spend-event-origin-conflict' end
    for _, key in ipairs(sorted_keys(cost)) do
        local amount = cost[key]
        if (state.resources[key] or 0) < amount then return false, 'insufficient-resource:' .. key end
    end
    for _, key in ipairs(sorted_keys(cost)) do state.resources[key] = state.resources[key] - cost[key] end
    state.completed_intents[request.intent_key] = true
    local outcome = { receipt_id = id, event_id = request.event_id, intent_key = request.intent_key }
    state.spend_receipts[id] = outcome
    state.spend_event_origins[request.event_id] = request.intent_key
    return true, shallow_copy(outcome), false
end

function M.settle_reward(state, request)
    local valid_owner, owner_error = validate_owner(state, request)
    if not valid_owner then return false, owner_error end
    if not non_empty_string(request.event_id) or not non_empty_string(request.profile_key)
        or not non_empty_string(request.reward_slot_key) or not non_empty_string(request.qualification_snapshot_id) then
        return false, 'reward-event-identity-required'
    end
    local id = settlement_receipt_id(request)
    local existing = state.reward_receipts[id]
    if existing then return true, copy_reward_outcome(existing), true end
    local profile = Config.reward_profiles[request.profile_key]
    if not profile then return false, 'unknown-reward-profile' end
    local event_slot = request.event_id .. '\0' .. request.reward_slot_key
    local origin = request.profile_key .. '|' .. request.qualification_snapshot_id .. '|' .. request.resource_table_version
    local prior_origin = state.reward_event_origins[event_slot]
    if prior_origin and prior_origin ~= origin then return false, 'reward-event-origin-conflict' end

    local qualification = nil
    if profile.scope == 'public_boss' then
        qualification = M.resolve_public_qualification(request.evidence)
        if not qualification.participation_chest_eligibility then return false, 'public-chest-not-qualified' end
    elseif profile.scope == 'team_raid' then
        local resolved, qualification_error = M.resolve_team_raid_qualification(
            request.team_snapshot,
            request.owner_id,
            request.profile_key,
            request.event_id,
            request.qualification_snapshot_id
        )
        if not resolved then return false, qualification_error end
        qualification = resolved
        if not qualification.participation_chest_eligibility then return false, 'team-raid-not-qualified' end
    elseif request.encounter_qualified ~= true then
        return false, 'encounter-not-qualified'
    else
        qualification = { progression_participation = true, participation_chest_eligibility = true, rare_drop_eligibility = false, pity_eligible = false }
    end

    local bundle = Config.reward_bundles[profile.bundle]
    if not bundle then return false, 'unknown-reward-bundle' end

    -- Validate all rare-roll inputs before creating any mutable staging state.
    -- Combined with the commit-at-end transaction below, an invalid rare roll
    -- cannot leak a base bundle, first clear, unique conversion, pity change,
    -- receipt, or event-origin marker into the character state.
    local rare_roll = nil
    if profile.rare and qualification.rare_drop_eligibility then
        if type(request.roll_basis_points) ~= 'number'
            or request.roll_basis_points ~= request.roll_basis_points
            or request.roll_basis_points % 1 ~= 0
            or request.roll_basis_points < 1
            or request.roll_basis_points > 10000 then
            return false, 'invalid-rare-roll'
        end
        rare_roll = request.roll_basis_points
    end

    local staged = reward_staging_state(state)
    local awards = {}
    for _, award in ipairs(bundle.guaranteed) do
        add_resource(staged, award.key, award.amount)
        append(awards, { key = award.key, amount = award.amount })
    end

    local first_clear_result = nil
    if profile.first_clear and not staged.first_clears[request.profile_key] then
        local granted, result = award_unique(staged, profile.first_clear, awards)
        if not granted then return false, result end
        staged.first_clears[request.profile_key] = true
        first_clear_result = result
    end

    local rare_result = { attempted = false, awarded = false, pity_after = nil }
    if profile.rare and qualification.rare_drop_eligibility then
        rare_result.attempted = true
        local rare = profile.rare
        local misses = staged.pity_progress[rare.pity_pool_key] or 0
        local forced = misses >= (rare.pity_after_misses - 1)
        if forced or rare_roll <= rare.chance_basis_points then
            local granted, result = award_unique(staged, rare, awards)
            if not granted then return false, result end
            staged.pity_progress[rare.pity_pool_key] = 0
            rare_result.awarded = true
            if forced then rare_result.reason = 'pity-forced' else rare_result.reason = 'roll-success' end
            rare_result.result = result
            rare_result.pity_after = 0
        else
            staged.pity_progress[rare.pity_pool_key] = misses + 1
            rare_result.reason = 'roll-miss'
            rare_result.pity_after = misses + 1
        end
    end

    local outcome = {
        receipt_id = id,
        event_id = request.event_id,
        profile_key = request.profile_key,
        qualification_snapshot_id = request.qualification_snapshot_id,
        qualification = qualification,
        awards = awards,
        first_clear_result = first_clear_result,
        rare = rare_result,
    }
    staged.reward_receipts[id] = outcome
    staged.reward_event_origins[event_slot] = origin
    commit_reward_staging(state, staged)
    return true, copy_reward_outcome(outcome), false
end

function M.build_milestones(state)
    return {
        SKILL_SECOND_ACTIVE = state.level >= 3,
        CORE_ROUTE = state.level >= 8,
        FIRST_EQUIPMENT = state.unique_resources.EQ_HG_WEAPON_T1 == true,
        FIRST_ENHANCEMENT = state.completed_intents.HG_ENHANCE_T1 == true,
        FIRST_ARTIFACT = state.unique_resources.ART_HG_TIDE_SEAL == true,
    }
end

function M.capture_milestones(state, minute)
    for key, complete in pairs(M.build_milestones(state)) do
        if complete and state.milestone_minutes[key] == nil then state.milestone_minutes[key] = minute end
    end
end

function M.simulate_first_six_hours(owner_id)
    local state, state_error = M.new_state(owner_id)
    if not state then return false, state_error end
    for _, event in ipairs(Config.first_six_hours_trace) do
        local ok, outcome
        if event.kind == 'xp' then
            ok, outcome = M.grant_xp(state, {
                owner_scope = Config.owner_scope,
                owner_id = owner_id,
                resource_table_version = Config.resource_table_version,
                event_id = event.event_id,
                source_key = event.source_key,
                party_qualified = true,
                actor_alive = true,
            })
        elseif event.kind == 'reward' then
            ok, outcome = M.settle_reward(state, {
                owner_scope = Config.owner_scope,
                owner_id = owner_id,
                resource_table_version = Config.resource_table_version,
                event_id = event.event_id,
                profile_key = event.profile_key,
                reward_slot_key = 'primary',
                qualification_snapshot_id = 'snapshot:' .. event.event_id,
                encounter_qualified = event.encounter_qualified,
                evidence = event.evidence,
                roll_basis_points = event.roll_basis_points,
                team_snapshot = event.team_snapshot and copy_simulation_team_snapshot(event.team_snapshot, owner_id) or nil,
            })
        elseif event.kind == 'spend' then
            ok, outcome = M.spend_intent(state, {
                owner_scope = Config.owner_scope,
                owner_id = owner_id,
                resource_table_version = Config.resource_table_version,
                event_id = event.event_id,
                intent_key = event.intent_key,
            })
        elseif event.kind == 'checkpoint' then
            ok, outcome = event.minute == Config.scope.active_minutes_max, { checkpoint = event.event_id }
        else
            return false, 'unknown-trace-event:' .. tostring(event.kind)
        end
        if not ok then return false, outcome end
        append(state.timeline, { minute = event.minute, event_id = event.event_id, kind = event.kind })
        M.capture_milestones(state, event.minute)
    end
    return true, state
end

M.Config = Config

return M
