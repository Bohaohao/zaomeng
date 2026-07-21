[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$script:Checks = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()
$PackageRoot = Split-Path -Parent $PSCommandPath

function Test-HasProperty {
  param($Object, [string]$Name)
  return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-Condition {
  param([bool]$Condition, [string]$Name)
  $script:Checks++
  if (-not $Condition) {
    $script:Errors.Add($Name) | Out-Null
  }
}

function Assert-Equal {
  param($Actual, $Expected, [string]$Name)
  Assert-Condition ($Actual -eq $Expected) "$Name; expected '$Expected', got '$Actual'"
}

function Assert-Null {
  param($Actual, [string]$Name)
  Assert-Condition ($null -eq $Actual) "$Name; expected null"
}

function Assert-Array {
  param($Actual, [string]$Name)
  Assert-Condition ($Actual -is [System.Array]) "$Name; expected an array"
}

function Read-JsonFile {
  param([string]$Path)
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

try {
  $RequiredFiles = @(
    'README.md',
    'decision-register.md',
    'tianting-mainline-tower-contract.json',
    'mainline-route.md',
    'topology-whitebox.md',
    'tower-first-cycle-state-contract.json',
    'tower-first-cycle-sequence.md',
    'design-spec.json',
    'design-spec-report.md',
    'acceptance-matrix.md',
    'validation-report.md',
    'validate-tianting-tower-spec.ps1',
    'handoff/object-config-brief.json',
    'handoff/terrain-layout-brief.json',
    'handoff/lua-logic-brief.md',
    'handoff/ui-brief.md',
    'handoff/review-brief.md'
  )

  foreach ($RelativePath in $RequiredFiles) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $PackageRoot $RelativePath) -PathType Leaf) "required file exists: $RelativePath"
  }

  $Contract = Read-JsonFile (Join-Path $PackageRoot 'tianting-mainline-tower-contract.json')
  $FirstCycle = Read-JsonFile (Join-Path $PackageRoot 'tower-first-cycle-state-contract.json')
  $Design = Read-JsonFile (Join-Path $PackageRoot 'design-spec.json')
  $ObjectBrief = Read-JsonFile (Join-Path $PackageRoot 'handoff/object-config-brief.json')
  $TerrainBrief = Read-JsonFile (Join-Path $PackageRoot 'handoff/terrain-layout-brief.json')

  Assert-Equal $Contract.version 1 'contract version'
  Assert-Equal $Contract.package_status 'offline-design-spec' 'contract package status'
  Assert-Equal $Contract.production_gate 'closed' 'contract production gate'
  Assert-Equal $Contract.hard_constraints.level_band.min_level 41 'TianTing minimum level'
  Assert-Equal $Contract.hard_constraints.level_band.max_level 60 'TianTing maximum level'
  Assert-Equal $Contract.hard_constraints.tower_entry.minimum_level 55 'tower minimum level'
  Assert-Equal $Contract.hard_constraints.tower_entry.member_check 'every_solo_player_or_team_member_independently' 'tower per-member check'
  Assert-Equal $Contract.hard_constraints.tower_entry.loadout_rest_every_floors 5 'tower rest interval'
  Assert-Equal $Contract.hard_constraints.tower_identity.rule 'linglong_theme_within_global_tongtian_tower' 'tower identity'
  Assert-Equal $Contract.hard_constraints.tower_identity.must_not_create 'a_second_long_term_tower_system' 'second tower prohibition'

  $Cross = $Contract.hard_constraints.cross_chapter_boundary
  Assert-Equal $Cross.protected_existing_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'protected Difu key'
  Assert-Equal $Cross.current_allowed_consumer 'HG_E_DRAGON_REVERSE_TIDE' 'existing allowed Difu key consumer'
  Assert-Equal $Cross.tianting_rule 'must_not_consume_or_write_protected_existing_key_without_new_explicit_decision' 'TianTing Difu-key prohibition'
  Assert-Equal $Cross.entry_contract.status 'deferred' 'TianTing entry contract status'
  Assert-Null $Cross.entry_contract.required_progression_key 'entry contract progression key'
  Assert-Null $Cross.entry_contract.writer 'entry contract writer'
  Assert-Array $Cross.entry_contract.trusted_consumers 'entry contract trusted consumers'
  Assert-Condition ($Cross.entry_contract.trusted_consumers.Count -eq 0) 'entry contract trusted consumers remain empty'
  Assert-Null $Cross.entry_contract.runtime_key 'entry contract runtime key'

  $Economy = $Contract.hard_constraints.economy_boundary
  Assert-Condition ([string]$Economy.future_resource_table_root -match '(^|/)economy-v2-resource-table\.json$') 'economy-v2 resource table root'
  Assert-Equal $Economy.required_state 'accepted-design-baseline-runtime-not-integrated' 'required resource table state'
  Assert-Equal $Economy.current_artifact_status 'accepted-design-baseline-runtime-not-integrated' 'current economy artifact status'
  Assert-Equal $Economy.resource_table_version 'economy-v2' 'economy resource table version'
  Assert-Equal $Economy.candidate_consumption_rule 'implementation/growth/ remains an offline candidate and must_not_be_used_as_tianting_resource_table' 'legacy candidate consumption prohibition'
  Assert-Equal $Economy.reference_role 'accepted_design_reference_runtime_not_integrated' 'economy reference role'
  Assert-Condition ($Contract.non_production_boundaries -contains 'implementation/growth/ remains an offline candidate; economy-v2 does not imply an authoritative runtime resource table, ledger, proof resolver or reward issuer.') 'non-production boundary must preserve the legacy candidate and runtime gate'
  Assert-Array $Economy.must_not_create 'economy forbidden values'
  Assert-Condition ($Economy.must_not_create -contains 'reward_amount') 'reward amount remains forbidden'
  Assert-Condition ($Economy.required_receipt_semantics -contains 'tower_award_class') 'tower award class is required by the current receipt contract'
  Assert-Condition ($Economy.must_not_create -contains 'season_value') 'season value remains forbidden'
  foreach ($field in @('owner_id', 'encounter_instance_id', 'qualification_snapshot_id', 'award_plan_hash', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_weekly_token_before', 'tower_weekly_token_after', 'award_outcome')) {
    Assert-Condition ($Economy.required_receipt_semantics -contains $field) "economy receipt semantics include $field"
  }
  Assert-Condition (-not ($Economy.required_receipt_semantics -contains 'actor_id')) 'economy receipt semantics use owner_id rather than actor_id'

  $Tower = $Contract.tracks.tower_first_cycle
  Assert-Equal $Tower.entry_rule 'level_at_least_55_for_every_participant' 'tower entry rule'
  Assert-Equal $Tower.rest_rule 'loadout_rest_every_5_floors' 'tower rest rule'
  Assert-Equal $Tower.linglong_relation 'theme_within_global_tower_only' 'tower Linglong relation'
  foreach ($PolicyName in @('floor_plan', 'affix_policy', 'season_policy')) {
    $Policy = $Tower.PSObject.Properties[$PolicyName].Value
    Assert-Equal $Policy.status 'deferred' "tower $PolicyName status"
    Assert-Null $Policy.effective_value "tower $PolicyName effective value"
  }
  Assert-Equal $Tower.reward_policy.status 'accepted_design_reference_runtime_not_integrated' 'tower reward policy status'
  Assert-Equal $Tower.reward_policy.resource_table_status 'accepted-design-baseline-runtime-not-integrated' 'tower reward policy resource table status'
  Assert-Equal $Tower.reward_policy.reference_role 'accepted_design_reference_runtime_not_integrated' 'tower reward policy reference role'
  Assert-Null $Tower.reward_policy.effective_value 'tower reward policy embedded effective value'
  Assert-Condition ([string]$Tower.reward_policy.resource_table_dependency -match '(^|/)economy-v2-resource-table\.json$') 'tower reward policy resource table dependency'
  Assert-Equal $Tower.reward_policy.resource_table_version 'economy-v2' 'tower reward policy resource table version'
  Assert-Equal $Tower.reward_policy.tower_qualification_policy_dependency 'TOWER_FIRST_CYCLE_QUALIFICATION_V1' 'tower reward policy qualification dependency'
  Assert-Condition ($Tower.reward_policy.qualification_snapshot_required -eq $true) 'tower reward policy qualification snapshot requirement'

  $CycleLink = $Tower.first_cycle_state_timing_contract
  Assert-Equal $CycleLink.status 'offline_design' 'tower first-cycle link status'
  Assert-Equal $CycleLink.artifact 'tower-first-cycle-state-contract.json' 'tower first-cycle link artifact'
  Assert-Equal $CycleLink.scope 'entry_gate_to_five_abstract_beats_to_fifth_rest_and_terminal_boundaries_only' 'tower first-cycle link scope'
  Assert-Equal $CycleLink.authority_rule 'future_authoritative_gameplay_logic_only' 'tower first-cycle authority rule'
  Assert-Equal $CycleLink.idempotency_rule 'future_semantic_envelope_returns_existing_authoritative_outcome_for_duplicates' 'tower first-cycle idempotency rule'
  Assert-Null $CycleLink.runtime_key 'tower first-cycle link runtime key'

  Assert-Equal $FirstCycle.version 1 'first-cycle contract version'
  Assert-Equal $FirstCycle.artifact_status 'offline_design' 'first-cycle contract status'
  Assert-Equal $FirstCycle.production_gate 'closed' 'first-cycle production gate'
  Assert-Equal $FirstCycle.inherited_constraints.future_economy_dependency 'economy-v2 exists_as_accepted-design-baseline-runtime-not-integrated; implementation/growth/ remains_an_offline_candidate_simulation_and_must_not_be_consumed' 'first-cycle growth dependency boundary'
  Assert-Equal $FirstCycle.identity.spec_id 'TT_SPEC_TOWER_FIRST_CYCLE' 'first-cycle contract spec id'
  Assert-Null $FirstCycle.identity.runtime_key 'first-cycle contract runtime key'
  Assert-Equal $FirstCycle.inherited_constraints.minimum_level_per_participant 55 'first-cycle minimum level'
  Assert-Equal $FirstCycle.inherited_constraints.member_check 'every_solo_player_or_team_member_independently' 'first-cycle per-member check'
  Assert-Equal $FirstCycle.inherited_constraints.rest_after_abstract_beat 5 'first-cycle rest beat'
  Assert-Equal $FirstCycle.inherited_constraints.linglong_relation 'theme_within_global_tongtian_tower_only' 'first-cycle Linglong relation'
  Assert-Equal $FirstCycle.inherited_constraints.protected_cross_chapter_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'first-cycle protected Difu key'
  Assert-Equal $FirstCycle.inherited_constraints.protected_key_rule 'must_not_read_or_write_as_tianting_default_input_without_new_explicit_decision' 'first-cycle protected Difu key rule'
  Assert-Equal $FirstCycle.entry_contract.spec_id 'TT_SPEC_TOWER_ENTRY_GATE' 'first-cycle entry spec id'
  Assert-Null $FirstCycle.entry_contract.runtime_key 'first-cycle entry runtime key'
  Assert-Equal $FirstCycle.entry_contract.accepted_target_state 'TT_SPEC_TOWER_STATE_BEAT_01_ACTIVE' 'first-cycle entry accept state'
  Assert-Equal $FirstCycle.entry_contract.rejected_target_state 'TT_SPEC_TOWER_STATE_ENTRY_DENIED' 'first-cycle entry reject state'

  $ExpectedCycleStateIds = @(
    'TT_SPEC_TOWER_STATE_ENTRY_CHECKING',
    'TT_SPEC_TOWER_STATE_ENTRY_DENIED',
    'TT_SPEC_TOWER_STATE_BEAT_01_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_02_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_03_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_04_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_05_ACTIVE',
    'TT_SPEC_TOWER_STATE_REST_05_OPEN',
    'TT_SPEC_TOWER_STATE_SETTLEMENT_PENDING',
    'TT_SPEC_TOWER_STATE_SETTLED',
    'TT_SPEC_TOWER_STATE_FAILURE_PENDING',
    'TT_SPEC_TOWER_STATE_FAILED',
    'TT_SPEC_TOWER_STATE_EXIT_PENDING',
    'TT_SPEC_TOWER_STATE_EXITED',
    'TT_SPEC_TOWER_STATE_NEXT_CYCLE_HANDOFF'
  )
  Assert-Array $FirstCycle.state_model.states 'first-cycle states'
  Assert-Condition ($FirstCycle.state_model.states.Count -eq $ExpectedCycleStateIds.Count) 'first-cycle state count'
  $CycleStatesById = @{}
  foreach ($State in $FirstCycle.state_model.states) {
    Assert-Condition ([string]$State.spec_id -match '^TT_SPEC_') "first-cycle state spec id: $($State.spec_id)"
    Assert-Null $State.runtime_key "first-cycle state runtime key: $($State.spec_id)"
    Assert-Condition (-not $CycleStatesById.ContainsKey([string]$State.spec_id)) "first-cycle state is unique: $($State.spec_id)"
    $CycleStatesById[[string]$State.spec_id] = $State
  }
  foreach ($StateId in $ExpectedCycleStateIds) {
    Assert-Condition ($CycleStatesById.ContainsKey($StateId)) "first-cycle expected state exists: $StateId"
  }
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_ENTRY_DENIED'].cycle_terminal) 'entry denied is cycle terminal'
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_SETTLED'].cycle_terminal) 'settled is cycle terminal'
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_FAILED'].cycle_terminal) 'failed is cycle terminal'
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_EXITED'].cycle_terminal) 'exited is cycle terminal'
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_NEXT_CYCLE_HANDOFF'].cycle_terminal) 'next-cycle handoff is cycle terminal'

  Assert-Array $FirstCycle.abstract_floor_beats 'first-cycle abstract beats'
  Assert-Condition ($FirstCycle.abstract_floor_beats.Count -eq 5) 'first-cycle has exactly five abstract beats'
  $SortedBeats = @($FirstCycle.abstract_floor_beats | Sort-Object beat_index)
  for ($BeatIndex = 1; $BeatIndex -le 5; $BeatIndex++) {
    $Beat = $SortedBeats[$BeatIndex - 1]
    $ExpectedBeatSpecId = ('TT_SPEC_TOWER_BEAT_{0:D2}' -f $BeatIndex)
    $ExpectedActiveState = ('TT_SPEC_TOWER_STATE_BEAT_{0:D2}_ACTIVE' -f $BeatIndex)
    $ExpectedClearTarget = if ($BeatIndex -lt 5) { 'TT_SPEC_TOWER_STATE_BEAT_{0:D2}_ACTIVE' -f ($BeatIndex + 1) } else { 'TT_SPEC_TOWER_STATE_REST_05_OPEN' }
    Assert-Equal $Beat.beat_index $BeatIndex "first-cycle beat index: $BeatIndex"
    Assert-Equal $Beat.spec_id $ExpectedBeatSpecId "first-cycle beat spec id: $BeatIndex"
    Assert-Equal $Beat.active_state $ExpectedActiveState "first-cycle active state: $BeatIndex"
    Assert-Equal $Beat.clear_target_state $ExpectedClearTarget "first-cycle clear target: $BeatIndex"
    Assert-Equal $Beat.failure_target_state 'TT_SPEC_TOWER_STATE_FAILURE_PENDING' "first-cycle failure target: $BeatIndex"
    Assert-Equal $Beat.exit_target_state 'TT_SPEC_TOWER_STATE_EXIT_PENDING' "first-cycle exit target: $BeatIndex"
    Assert-Null $Beat.runtime_key "first-cycle beat runtime key: $BeatIndex"
  }

  Assert-Array $FirstCycle.transition_contract 'first-cycle transitions'
  Assert-Condition ($FirstCycle.transition_contract.Count -eq 15) 'first-cycle transition count'
  $CycleTransitionsById = @{}
  foreach ($Transition in $FirstCycle.transition_contract) {
    Assert-Condition ([string]$Transition.spec_id -match '^TT_SPEC_') "first-cycle transition spec id: $($Transition.spec_id)"
    Assert-Null $Transition.runtime_key "first-cycle transition runtime key: $($Transition.spec_id)"
    Assert-Condition (-not $CycleTransitionsById.ContainsKey([string]$Transition.spec_id)) "first-cycle transition is unique: $($Transition.spec_id)"
    $CycleTransitionsById[[string]$Transition.spec_id] = $Transition
  }
  foreach ($TransitionId in @(
    'TT_SPEC_TOWER_TRANSITION_ENTRY_ACCEPT',
    'TT_SPEC_TOWER_TRANSITION_ENTRY_DENY',
    'TT_SPEC_TOWER_TRANSITION_BEAT_01_CLEAR',
    'TT_SPEC_TOWER_TRANSITION_BEAT_02_CLEAR',
    'TT_SPEC_TOWER_TRANSITION_BEAT_03_CLEAR',
    'TT_SPEC_TOWER_TRANSITION_BEAT_04_CLEAR',
    'TT_SPEC_TOWER_TRANSITION_BEAT_05_CLEAR_TO_REST',
    'TT_SPEC_TOWER_TRANSITION_ACTIVE_BEAT_FAILURE',
    'TT_SPEC_TOWER_TRANSITION_ACTIVE_OR_REST_EXIT',
    'TT_SPEC_TOWER_TRANSITION_REST_BUILD_SWITCH',
    'TT_SPEC_TOWER_TRANSITION_REST_TO_SETTLEMENT',
    'TT_SPEC_TOWER_TRANSITION_SETTLEMENT_FINALIZE',
    'TT_SPEC_TOWER_TRANSITION_REST_TO_NEXT_CYCLE_HANDOFF',
    'TT_SPEC_TOWER_TRANSITION_FAILURE_FINALIZE',
    'TT_SPEC_TOWER_TRANSITION_EXIT_FINALIZE'
  )) {
    Assert-Condition ($CycleTransitionsById.ContainsKey($TransitionId)) "first-cycle expected transition exists: $TransitionId"
  }
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ENTRY_ACCEPT'].from 'TT_SPEC_TOWER_STATE_ENTRY_CHECKING' 'entry accept source'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ENTRY_ACCEPT'].to 'TT_SPEC_TOWER_STATE_BEAT_01_ACTIVE' 'entry accept target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ENTRY_DENY'].from 'TT_SPEC_TOWER_STATE_ENTRY_CHECKING' 'entry deny source'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ENTRY_DENY'].to 'TT_SPEC_TOWER_STATE_ENTRY_DENIED' 'entry deny target'
  for ($BeatIndex = 1; $BeatIndex -le 5; $BeatIndex++) {
    $ClearTransitionId = if ($BeatIndex -lt 5) { 'TT_SPEC_TOWER_TRANSITION_BEAT_{0:D2}_CLEAR' -f $BeatIndex } else { 'TT_SPEC_TOWER_TRANSITION_BEAT_05_CLEAR_TO_REST' }
    $ExpectedSource = 'TT_SPEC_TOWER_STATE_BEAT_{0:D2}_ACTIVE' -f $BeatIndex
    $ExpectedTarget = if ($BeatIndex -lt 5) { 'TT_SPEC_TOWER_STATE_BEAT_{0:D2}_ACTIVE' -f ($BeatIndex + 1) } else { 'TT_SPEC_TOWER_STATE_REST_05_OPEN' }
    Assert-Equal $CycleTransitionsById[$ClearTransitionId].from $ExpectedSource "clear transition source: $BeatIndex"
    Assert-Equal $CycleTransitionsById[$ClearTransitionId].to $ExpectedTarget "clear transition target: $BeatIndex"
  }
  $ExpectedActiveSources = @(
    'TT_SPEC_TOWER_STATE_BEAT_01_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_02_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_03_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_04_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_05_ACTIVE'
  )
  $FailureSources = @($CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ACTIVE_BEAT_FAILURE'].PSObject.Properties['from'].Value)
  Assert-Condition (($FailureSources -join '|') -eq ($ExpectedActiveSources -join '|')) 'failure transition sources'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ACTIVE_BEAT_FAILURE'].to 'TT_SPEC_TOWER_STATE_FAILURE_PENDING' 'failure transition target'
  $ExitSources = @($CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ACTIVE_OR_REST_EXIT'].PSObject.Properties['from'].Value)
  Assert-Condition (($ExitSources -join '|') -eq (($ExpectedActiveSources + 'TT_SPEC_TOWER_STATE_REST_05_OPEN') -join '|')) 'exit transition sources'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ACTIVE_OR_REST_EXIT'].to 'TT_SPEC_TOWER_STATE_EXIT_PENDING' 'exit transition target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_REST_BUILD_SWITCH'].from 'TT_SPEC_TOWER_STATE_REST_05_OPEN' 'rest switch source'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_REST_BUILD_SWITCH'].to 'TT_SPEC_TOWER_STATE_REST_05_OPEN' 'rest switch remains in rest'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_REST_TO_SETTLEMENT'].to 'TT_SPEC_TOWER_STATE_SETTLEMENT_PENDING' 'rest settlement target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_SETTLEMENT_FINALIZE'].to 'TT_SPEC_TOWER_STATE_SETTLED' 'settlement terminal target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_REST_TO_NEXT_CYCLE_HANDOFF'].to 'TT_SPEC_TOWER_STATE_NEXT_CYCLE_HANDOFF' 'next-cycle handoff target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_FAILURE_FINALIZE'].to 'TT_SPEC_TOWER_STATE_FAILED' 'failure terminal target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_EXIT_FINALIZE'].to 'TT_SPEC_TOWER_STATE_EXITED' 'exit terminal target'

  $Idempotency = $FirstCycle.idempotency_contract
  Assert-Equal $Idempotency.spec_id 'TT_SPEC_TOWER_FIRST_CYCLE_IDEMPOTENCY' 'first-cycle idempotency spec id'
  Assert-Equal $Idempotency.decision_status 'offline_design' 'first-cycle idempotency status'
  Assert-Null $Idempotency.runtime_key 'first-cycle idempotency runtime key'
  Assert-Equal $Idempotency.semantic_envelope.status 'deferred' 'first-cycle idempotency envelope status'
  Assert-Null $Idempotency.semantic_envelope.runtime_key 'first-cycle idempotency envelope runtime key'
  Assert-Null $Idempotency.semantic_envelope.assigned_values 'first-cycle idempotency envelope values'
  Assert-Array $Idempotency.semantic_envelope.required_field_names 'first-cycle idempotency envelope fields'
  foreach ($FieldName in @('future_run_scope', 'operation_id', 'request_kind', 'expected_source_state', 'actor_scope', 'qualification_snapshot_id', 'event_id', 'schema_version')) {
    Assert-Condition ($Idempotency.semantic_envelope.required_field_names -contains $FieldName) "first-cycle idempotency envelope field: $FieldName"
  }
  Assert-Array $Idempotency.rules 'first-cycle idempotency rules'
  Assert-Condition ($Idempotency.rules.Count -eq 4) 'first-cycle idempotency rule count'
  foreach ($Rule in $Idempotency.rules) {
    Assert-Condition ([string]$Rule.spec_id -match '^TT_SPEC_') "first-cycle idempotency rule spec id: $($Rule.spec_id)"
    Assert-Null $Rule.runtime_key "first-cycle idempotency rule runtime key: $($Rule.spec_id)"
  }

  $SettlementBoundary = $FirstCycle.settlement_boundary
  Assert-Equal $SettlementBoundary.spec_id 'TT_SPEC_TOWER_SETTLEMENT_BOUNDARY' 'first-cycle settlement spec id'
  Assert-Null $SettlementBoundary.runtime_key 'first-cycle settlement runtime key'
  Assert-Equal $SettlementBoundary.allowed_source_state 'TT_SPEC_TOWER_STATE_REST_05_OPEN' 'first-cycle settlement source'
  Assert-Equal $SettlementBoundary.required_intermediate_state 'TT_SPEC_TOWER_STATE_SETTLEMENT_PENDING' 'first-cycle settlement pending state'
  Assert-Equal $SettlementBoundary.terminal_state 'TT_SPEC_TOWER_STATE_SETTLED' 'first-cycle settlement terminal state'
  Assert-Equal $SettlementBoundary.economy_effect.status 'accepted_design_reference_runtime_not_integrated' 'first-cycle settlement economy status'
  Assert-Equal $SettlementBoundary.economy_effect.resource_table_status 'accepted-design-baseline-runtime-not-integrated' 'first-cycle settlement resource table status'
  Assert-Equal $SettlementBoundary.economy_effect.reference_role 'accepted_design_reference_runtime_not_integrated' 'first-cycle settlement reference role'
  Assert-Condition ([string]$SettlementBoundary.economy_effect.resource_table_dependency -match '(^|/)economy-v2-resource-table\.json$') 'first-cycle settlement resource table dependency'
  Assert-Equal $SettlementBoundary.economy_effect.resource_table_version 'economy-v2' 'first-cycle settlement resource table version'
  Assert-Null $SettlementBoundary.economy_effect.assigned_reward_values 'first-cycle settlement assigned rewards'
  Assert-Condition ($SettlementBoundary.economy_effect.prohibited -contains 'reward_amount') 'first-cycle settlement prohibits reward amount'
  Assert-Condition ($SettlementBoundary.economy_effect.prohibited -contains 'season_value') 'first-cycle settlement prohibits season value'
  foreach ($field in @('owner_id', 'qualification_snapshot_id', 'encounter_instance_id', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_weekly_token_before', 'tower_weekly_token_after', 'award_plan_hash', 'authority_proof_ref', 'award_outcome')) {
    Assert-Condition ($SettlementBoundary.economy_effect.required_receipt_fields -contains $field) "first-cycle settlement receipt includes $field"
  }

  $FailureExit = $FirstCycle.failure_and_exit_boundary
  Assert-Equal $FailureExit.spec_id 'TT_SPEC_TOWER_FAILURE_EXIT_BOUNDARY' 'first-cycle failure exit spec id'
  Assert-Null $FailureExit.runtime_key 'first-cycle failure exit runtime key'
  Assert-Condition ((@($FailureExit.failure.source_states) -join '|') -eq ($ExpectedActiveSources -join '|')) 'first-cycle failure boundary sources'
  Assert-Equal $FailureExit.failure.pending_state 'TT_SPEC_TOWER_STATE_FAILURE_PENDING' 'first-cycle failure boundary pending state'
  Assert-Equal $FailureExit.failure.terminal_state 'TT_SPEC_TOWER_STATE_FAILED' 'first-cycle failure boundary terminal state'
  Assert-Condition ((@($FailureExit.exit.source_states) -join '|') -eq (($ExpectedActiveSources + 'TT_SPEC_TOWER_STATE_REST_05_OPEN') -join '|')) 'first-cycle exit boundary sources'
  Assert-Equal $FailureExit.exit.pending_state 'TT_SPEC_TOWER_STATE_EXIT_PENDING' 'first-cycle exit boundary pending state'
  Assert-Equal $FailureExit.exit.terminal_state 'TT_SPEC_TOWER_STATE_EXITED' 'first-cycle exit boundary terminal state'

  $ContractNodes = @($Contract.worldview_anchors) + @($Contract.chapter_roles)
  foreach ($Node in $ContractNodes) {
    Assert-Condition ([string]$Node.spec_id -match '^TT_SPEC_') "contract spec id prefix: $($Node.spec_id)"
    Assert-Null $Node.runtime_key "contract runtime key: $($Node.spec_id)"
  }

  $RequiredDesignTop = @('version', 'project', 'sourceMaterials', 'worldview', 'playerExperience', 'coreLoop', 'sessionFlow', 'systems', 'content', 'mvp', 'handoffs', 'risks', 'unresolved', 'acceptanceCriteria', 'crossChapterBoundary', 'towerFirstCycleContract')
  foreach ($Name in $RequiredDesignTop) {
    Assert-Condition (Test-HasProperty $Design $Name) "design top-level field: $Name"
  }
  Assert-Equal $Design.version 1 'design version'
  Assert-Equal $Design.project.targetDurationMinutes 0 'design duration deliberately unresolved'
  Assert-Equal $Design.crossChapterBoundary.protectedExistingKey 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'design protected Difu key'
  Assert-Equal $Design.crossChapterBoundary.defaultUse 'prohibited' 'design default Difu-key use'
  Assert-Equal $Design.crossChapterBoundary.entryContract 'deferred' 'design entry contract'
  Assert-Null $Design.crossChapterBoundary.newRuntimeKey 'design new runtime key'
  Assert-Equal $Design.towerFirstCycleContract.artifact 'tower-first-cycle-state-contract.json' 'design first-cycle artifact'
  Assert-Equal $Design.towerFirstCycleContract.status 'offline_design' 'design first-cycle status'
  Assert-Equal $Design.towerFirstCycleContract.scope 'entry_gate_to_five_abstract_beats_to_fifth_rest_and_terminal_boundaries_only' 'design first-cycle scope'
  Assert-Null $Design.towerFirstCycleContract.runtimeKey 'design first-cycle runtime key'
  Assert-Null $Design.towerFirstCycleContract.totalFloorCount 'design first-cycle total floor count'
  Assert-Equal $Design.towerFirstCycleContract.economyEffect 'accepted_design_reference_runtime_not_integrated' 'design first-cycle economy effect'
  Assert-Equal $Design.towerFirstCycleContract.protectedDifuKeyUse 'prohibited' 'design first-cycle protected Difu key use'

  foreach ($CollectionName in @('sourceMaterials', 'sessionFlow', 'systems', 'risks', 'unresolved', 'acceptanceCriteria')) {
    $Collection = $Design.PSObject.Properties[$CollectionName].Value
    Assert-Array $Collection "design collection: $CollectionName"
    Assert-Condition ($Collection.Count -gt 0) "design collection is non-empty: $CollectionName"
  }
  foreach ($MvpName in @('mustHave', 'shouldHave', 'later')) {
    $Collection = $Design.mvp.PSObject.Properties[$MvpName].Value
    Assert-Array $Collection "design MVP collection: $MvpName"
    Assert-Condition ($Collection.Count -gt 0) "design MVP collection is non-empty: $MvpName"
  }
  foreach ($HandoffName in @('objectConfig', 'terrainLayout', 'luaLogic', 'uiPipeline', 'reviewPanel')) {
    $Collection = $Design.handoffs.PSObject.Properties[$HandoffName].Value
    Assert-Array $Collection "design handoff collection: $HandoffName"
    Assert-Condition ($Collection.Count -gt 0) "design handoff collection is non-empty: $HandoffName"
  }
  foreach ($Bucket in @('heroes', 'abilities', 'monsters', 'bosses', 'items', 'maps', 'ui', 'economy', 'progression', 'waves')) {
    Assert-Condition (Test-HasProperty $Design.content $Bucket) "design content bucket: $Bucket"
    $Items = $Design.content.PSObject.Properties[$Bucket].Value
    Assert-Array $Items "design content bucket array: $Bucket"
    Assert-Condition ($Items.Count -gt 0) "design content bucket non-empty: $Bucket"
    foreach ($Item in $Items) {
      Assert-Condition ([string]$Item.specId -match '^TT_SPEC_') "design spec id prefix: $Bucket/$($Item.specId)"
      Assert-Null $Item.runtimeKey "design runtime key: $Bucket/$($Item.specId)"
    }
  }

  Assert-Equal $ObjectBrief.targetSkill 'y3-object-config' 'object handoff target skill'
  Assert-Condition (Test-HasProperty $ObjectBrief 'assetRequests') 'object handoff asset requests'
  foreach ($AssetName in @('heroes', 'abilities', 'monsters', 'bosses', 'items', 'economy', 'progression')) {
    $Asset = $ObjectBrief.assetRequests.PSObject.Properties[$AssetName].Value
    Assert-Condition ($null -ne $Asset) "object handoff asset request: $AssetName"
    Assert-Condition ([string]$Asset.specId -match '^TT_SPEC_') "object handoff spec id: $AssetName/$($Asset.specId)"
    Assert-Null $Asset.runtimeKey "object handoff runtime key: $AssetName/$($Asset.specId)"
  }
  Assert-Equal $TerrainBrief.targetSkill 'y3-terrain-layout' 'terrain handoff target skill'
  foreach ($RegionName in @('maps', 'waves', 'monsters', 'bosses')) {
    $Region = $TerrainBrief.PSObject.Properties[$RegionName].Value
    Assert-Condition ($null -ne $Region) "terrain handoff logical region: $RegionName"
    Assert-Condition ([string]$Region.specId -match '^TT_SPEC_') "terrain handoff spec id: $RegionName/$($Region.specId)"
    Assert-Null $Region.runtimeKey "terrain handoff runtime key: $RegionName/$($Region.specId)"
  }

  $PackageText = (Get-ChildItem -LiteralPath $PackageRoot -File -Recurse |
    Where-Object { $_.Name -ne 'validate-tianting-tower-spec.ps1' } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
  Assert-Condition ($PackageText -notmatch '(30|50)\s*(层|floors?)') 'package has no unapproved tower floor count'
  Assert-Condition ($PackageText -notmatch 'DF_PROGRESS_YANLUO_HALL_CLEARED[^\r\n]{0,80}(默认前置|默认解锁|default prerequisite|default unlock)') 'package does not describe protected Difu key as a default unlock'
}
catch {
  $script:Errors.Add("validator exception: $($_.Exception.Message)") | Out-Null
}

if ($script:Errors.Count -gt 0) {
  Write-Output "VALIDATION FAILED: $($script:Errors.Count) issue(s) after $script:Checks check(s)"
  foreach ($ErrorMessage in $script:Errors) {
    Write-Output "- $ErrorMessage"
  }
  exit 1
}

Write-Output "VALIDATION PASSED: $script:Checks checks"
