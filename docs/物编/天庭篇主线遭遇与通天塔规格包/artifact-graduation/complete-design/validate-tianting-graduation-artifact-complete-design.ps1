[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$script:Checks = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()
$PackageRoot = Split-Path -Parent $PSCommandPath
$ArtifactRoot = Split-Path -Parent $PackageRoot
$TianTingRoot = Split-Path -Parent $ArtifactRoot
$WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $TianTingRoot '..\..\..')).Path
$ContractPath = Join-Path $PackageRoot 'tianting-graduation-artifact-complete-design-contract.json'
$ParentContractPath = Join-Path $ArtifactRoot 'tianting-endgame-artifact-positioning-and-lineage-contract.json'
$ContentContractPath = Join-Path $TianTingRoot 'tianting-content-expansion-contract.json'
$AuthorityContractPath = Join-Path $TianTingRoot 'authority\tianting-progression-and-instance-authority-contract.json'
$Utf8 = [System.Text.Encoding]::UTF8

function Decode-Base64Utf8 {
  param([string]$Value)
  return $Utf8.GetString([Convert]::FromBase64String($Value))
}

$ArtifactDisplayName = Decode-Base64Utf8 '5ZGo5aSp5qCh5b6L55uY'
$ArtifactDocumentationAlias = Decode-Base64Utf8 '5LiD5puc5q+V5Lia5rOV5a6d'
$DirectDamageOrAutomaticPattern = Decode-Base64Utf8 '55u05o6l6YCg5oiQ5Lyk5a6zfOiHquWKqA=='
$Tianshu = Decode-Base64Utf8 '5aSp5p6i'
$Tianquan = Decode-Base64Utf8 '5aSp5p2D'
$Yuheng = Decode-Base64Utf8 '546J6KGh'
$Tianxuan = Decode-Base64Utf8 '5aSp55KH'
$Tianji = Decode-Base64Utf8 '5aSp546R'
$Kaiyang = Decode-Base64Utf8 '5byA6Ziz'
$Yaoguang = Decode-Base64Utf8 '55G25YWJ'
$FixedTenFragmentTitleRule = Decode-Base64Utf8 '5ZCM5LiA5pif5q6L54mH57Sv6K6h5Y2B5p6a5ZCI5oiQ5a+55bqU5pif5ZCb56ew5Y+377yM5piv55So5oi36ZSB5a6a55qE5pS26JeP6K6h5pWw77yM5LiN5piv5Y2V5qyh5o6J6JC96YeP44CC'
$DoubleSpendToken = Decode-Base64Utf8 '5Y+M6Iqx'
$SacredAttestationName = Decode-Base64Utf8 '5Zub6LGh6KaG546v'
$NoReconnectToken = Decode-Base64Utf8 '5LiN5b6X6YeN6L+e'
$NoCombatPattern = Decode-Base64Utf8 '5LiNLirmiJjmlpc='
$NoNumericChangePattern = Decode-Base64Utf8 '5LiN5pS55Y+YLirmlbDlgLw='
$NoResponseCardToken = Decode-Base64Utf8 '5LiN55Sf5oiQ5Zue5bqU5Y2h'

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

function Assert-ExactArray {
  param($Actual, [string[]]$Expected, [string]$Name)
  Assert-Condition ($Actual -is [System.Array]) "$Name; expected array"
  Assert-Condition ((@($Actual) -join '|') -eq (@($Expected) -join '|')) "$Name; expected '$(@($Expected) -join '|')', got '$(@($Actual) -join '|')'"
}

function Assert-ExactPropertyNames {
  param($Object, [string[]]$Expected, [string]$Name)
  Assert-Condition ($null -ne $Object) "$Name object exists"
  if ($null -ne $Object) {
    Assert-ExactArray @($Object.PSObject.Properties | ForEach-Object { [string]$_.Name }) $Expected "$Name property names"
  }
}

function Read-JsonFile {
  param([string]$Path)
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ByProperty {
  param($Items, [string]$Property, [string]$Value)
  return @($Items | Where-Object { [string]$_.PSObject.Properties[$Property].Value -eq $Value })
}

try {
  foreach ($Path in @($ContractPath, $ParentContractPath, $ContentContractPath, $AuthorityContractPath)) {
    Assert-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "required contract exists: $Path"
  }

  if ($script:Errors.Count -eq 0) {
    $Contract = Read-JsonFile $ContractPath
    $Parent = Read-JsonFile $ParentContractPath
    $Content = Read-JsonFile $ContentContractPath
    $Authority = Read-JsonFile $AuthorityContractPath

    Assert-ExactPropertyNames $Contract @(
      'contract_id', 'schema_version', 'artifact_kind', 'status', 'runtime_handoff', 'production_gate', 'scope',
      'source_contracts', 'identity', 'design_stage_flow', 'single_slot_and_switching', 'shared_counter_response_gate',
      'response_state_machine', 'encounter_subscription_boundary', 'form_designs', 'material_and_source_blueprints',
      'future_source_evidence_by_material_role', 'title_and_collection_relationship', 'optional_sacred_attestation',
      'cross_profession_compatibility', 'readability_and_presentation', 'authority_failure_and_settlement_boundary',
      'future_loadout_snapshot_handoff', 'legacy_and_migration_boundary', 'non_production_boundary', 'acceptance_matrix'
    ) 'complete design root'
    Assert-Equal $Contract.contract_id 'TT_SPEC_GRADUATION_ARTIFACT_COMPLETE_DESIGN_V1' 'complete design contract id'
    Assert-Equal $Contract.schema_version 1 'complete design schema version'
    Assert-Equal $Contract.artifact_kind 'offline_tianting_graduation_artifact_complete_design_contract' 'complete design kind'
    Assert-Equal $Contract.status 'accepted-offline-design' 'complete design status'
    Assert-Condition ($Contract.runtime_handoff -eq $false) 'complete design runtime handoff remains false'
    Assert-Equal $Contract.production_gate 'closed' 'complete design production gate'

    Assert-Equal @($Contract.source_contracts).Count 6 'complete design source contract count'
    foreach ($Source in @($Contract.source_contracts)) {
      Assert-ExactPropertyNames $Source @('path', 'role') "complete design source: $($Source.path)"
      $Resolved = Join-Path $PackageRoot (([string]$Source.path) -replace '/', '\\')
      Assert-Condition (Test-Path -LiteralPath $Resolved -PathType Leaf) "complete design source resolves: $($Source.path)"
      if (Test-Path -LiteralPath $Resolved -PathType Leaf) {
        $FullPath = (Resolve-Path -LiteralPath $Resolved).Path
        Assert-Condition ($FullPath.StartsWith($WorkspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) "complete design source stays in workspace: $($Source.path)"
      }
    }

    Assert-ExactPropertyNames $Contract.identity @('artifact_spec_id', 'display_name', 'documentation_alias', 'identity_rule', 'tier', 'chapter_band', 'actual_logical_artifact_key', 'runtime_item_key', 'object_asset', 'icon_asset') 'complete design identity'
    Assert-Equal $Contract.identity.artifact_spec_id 'TT_SPEC_SEVEN_STAR_GRADUATION_ARTIFACT' 'complete design artifact identity'
    Assert-Equal $Contract.identity.display_name $ArtifactDisplayName 'complete design display name'
    Assert-Equal $Contract.identity.documentation_alias $ArtifactDocumentationAlias 'complete design documentation alias'
    Assert-Equal $Contract.identity.tier 'high_endgame_optional' 'complete design tier'
    Assert-Equal $Contract.identity.chapter_band 'TT_LV41_TO_60' 'complete design chapter band'
    foreach ($Field in @('actual_logical_artifact_key', 'runtime_item_key', 'object_asset', 'icon_asset')) {
      Assert-Null $Contract.identity.$Field "complete design identity deferred field: $Field"
    }
    Assert-Equal $Parent.identity.display_name $Contract.identity.display_name 'parent contract display name agrees with complete design'
    Assert-Equal $Content.seven_star_solo.graduation_artifact.display_name $Contract.identity.display_name 'content contract display name agrees with complete design'

    Assert-ExactArray @($Contract.design_stage_flow | ForEach-Object { [string]$_.stage_id }) @(
      'TT_ARTIFACT_STAGE_OBSERVATORY_AWARENESS',
      'TT_ARTIFACT_STAGE_SEVEN_STAR_LEARNING',
      'TT_ARTIFACT_STAGE_CELESTIAL_LAW_ALIGNMENT',
      'TT_ARTIFACT_STAGE_FORM_ATTUNEMENT',
      'TT_ARTIFACT_STAGE_OPTIONAL_SACRED_ATTESTATION'
    ) 'complete design stage order'
    foreach ($Stage in @($Contract.design_stage_flow)) {
      Assert-ExactPropertyNames $Stage @('stage_id', 'display_label', 'player_state', 'authority_anchor', 'design_role', 'relative_difficulty_band', 'actual_progress_key', 'actual_grant_event') "complete design stage: $($Stage.stage_id)"
      Assert-Null $Stage.actual_progress_key "complete design stage progress is deferred: $($Stage.stage_id)"
      Assert-Null $Stage.actual_grant_event "complete design stage grant is deferred: $($Stage.stage_id)"
    }

    Assert-Equal $Contract.single_slot_and_switching.active_artifact_slot_count 1 'complete design single artifact slot'
    Assert-Equal $Contract.single_slot_and_switching.same_artifact_form_count_per_preset 1 'complete design single form per preset'
    Assert-Condition ($Contract.single_slot_and_switching.ownership_is_not_equipping -eq $true) 'complete design ownership is not equipping'
    Assert-Condition ($Contract.single_slot_and_switching.form_selection_is_not_material_consumption -eq $true) 'complete design form selection is not material consumption'
    Assert-Condition (@($Contract.single_slot_and_switching.locked_contexts) -contains 'cleanup_pending') 'complete design locks switching during cleanup'

    Assert-ExactPropertyNames $Contract.shared_counter_response_gate @('semantic_name', 'required_player_fact', 'authority_rule', 'form_tag_match_rule', 'response_rule', 'missing_or_wrong_precondition', 'failure_precedence', 'actual_ability_key', 'cooldown', 'duration', 'damage', 'shield', 'control') 'complete design response gate'
    Assert-Condition ([string]$Contract.shared_counter_response_gate.form_tag_match_rule -match 'stabilize') 'complete design response gate declares stabilize match'
    Assert-Condition ([string]$Contract.shared_counter_response_gate.form_tag_match_rule -match 'discern') 'complete design response gate declares discern match'
    Assert-Condition ([string]$Contract.shared_counter_response_gate.form_tag_match_rule -match 'open') 'complete design response gate declares open match'
    foreach ($Field in @('actual_ability_key', 'cooldown', 'duration', 'damage', 'shield', 'control')) {
      Assert-Null $Contract.shared_counter_response_gate.$Field "complete design response gate deferred field: $Field"
    }

    Assert-ExactPropertyNames $Contract.response_state_machine @('owner_scope', 'states', 'ready_rule', 'verified_window_rule', 'resolved_rule', 'tag_mismatch_rule', 'invalidated_rule', 'idempotency_identity', 'future_window_snapshot_fields', 'actual_runtime_state_key', 'actual_response_receipt') 'complete design response state fields'
    Assert-ExactArray @($Contract.response_state_machine.states) @('ready', 'verified_window', 'resolved', 'invalidated') 'complete design response state order'
    Assert-ExactArray @($Contract.response_state_machine.idempotency_identity) @('actor_id', 'response_window_id') 'complete design response idempotency identity'
    Assert-Condition ([string]$Contract.response_state_machine.invalidated_rule -match 'cleanup_pending') 'complete design response invalidates before cleanup'
    Assert-Condition ([string]$Contract.response_state_machine.tag_mismatch_rule -match 'invalidated') 'complete design tag mismatch invalidates the response'
    Assert-Condition ([string]$Contract.response_state_machine.tag_mismatch_rule -match [regex]::Escape($NoResponseCardToken)) 'complete design tag mismatch cannot create a response card'
    foreach ($Field in @('actual_runtime_state_key', 'actual_response_receipt')) {
      Assert-Null $Contract.response_state_machine.$Field "complete design response state deferred field: $Field"
    }
    Assert-ExactArray @($Contract.encounter_subscription_boundary.supported_semantic_tags) @('stabilize', 'discern', 'open') 'complete design semantic tag set'
    Assert-Null $Contract.encounter_subscription_boundary.actual_encounter_tag_key 'complete design encounter tag key deferred'
    Assert-Null $Contract.encounter_subscription_boundary.actual_phase_write 'complete design phase write deferred'

    $ExpectedForms = @(
      'TT_SPEC_ARTIFACT_FORM_STABILIZE_SEQUENCE',
      'TT_SPEC_ARTIFACT_FORM_DISCERN_SEQUENCE',
      'TT_SPEC_ARTIFACT_FORM_OPEN_SEQUENCE'
    )
    Assert-ExactArray @($Contract.form_designs | ForEach-Object { [string]$_.form_id }) $ExpectedForms 'complete design form order'
    foreach ($Form in @($Contract.form_designs)) {
      Assert-ExactPropertyNames $Form @('form_id', 'display_label', 'compatible_semantic_tags', 'star_learning_sources', 'player_problem', 'player_input', 'response_semantics', 'visual_channel', 'independent_channel', 'failure_feedback', 'must_not_do', 'actual_effect_values') "complete design form: $($Form.form_id)"
      Assert-Equal @($Form.must_not_do).Count 3 "complete design form prohibition count: $($Form.form_id)"
      Assert-Null $Form.actual_effect_values "complete design form effect values deferred: $($Form.form_id)"
      Assert-Condition (-not ([string]$Form.response_semantics -match [regex]::Escape($DirectDamageOrAutomaticPattern))) "complete design form remains a readable response: $($Form.form_id)"
    }
    Assert-ExactArray @($Contract.form_designs[0].star_learning_sources) @($Tianshu, $Tianquan, $Yuheng) 'complete design stabilize sources'
    Assert-ExactArray @($Contract.form_designs[1].star_learning_sources) @($Tianxuan, $Tianji) 'complete design discern sources'
    Assert-ExactArray @($Contract.form_designs[2].star_learning_sources) @($Kaiyang, $Yaoguang) 'complete design open sources'
    Assert-ExactArray @($Contract.form_designs[0].compatible_semantic_tags) @('stabilize') 'complete design stabilize form tag'
    Assert-ExactArray @($Contract.form_designs[1].compatible_semantic_tags) @('discern') 'complete design discern form tag'
    Assert-ExactArray @($Contract.form_designs[2].compatible_semantic_tags) @('open') 'complete design open form tag'

    $Materials = $Contract.material_and_source_blueprints
    Assert-Equal @($Materials.fragment_categories).Count 7 'complete design seven fragment categories'
    Assert-ExactArray @($Materials.fragment_categories | ForEach-Object { "$( $_.material_spec_id )|$( $_.source_node_id )" }) @(
      'TT_SPEC_MATERIAL_TIANSHU_FRAGMENT|TT_SPEC_SOLO_TIANSHU',
      'TT_SPEC_MATERIAL_TIANXUAN_FRAGMENT|TT_SPEC_SOLO_TIANXUAN',
      'TT_SPEC_MATERIAL_TIANJI_FRAGMENT|TT_SPEC_SOLO_TIANJI',
      'TT_SPEC_MATERIAL_TIANQUAN_FRAGMENT|TT_SPEC_SOLO_TIANQUAN',
      'TT_SPEC_MATERIAL_YUHENG_FRAGMENT|TT_SPEC_SOLO_YUHENG',
      'TT_SPEC_MATERIAL_KAIYANG_FRAGMENT|TT_SPEC_SOLO_KAIYANG',
      'TT_SPEC_MATERIAL_YAOGUANG_FRAGMENT|TT_SPEC_SOLO_YAOGUANG'
    ) 'complete design fragment mapping'
    Assert-Equal $Materials.base_catalyst.material_spec_id 'TT_SPEC_MATERIAL_CELESTIAL_LAW_SEAL' 'complete design base catalyst id'
    Assert-Equal $Materials.base_catalyst.source_node_id 'TT_SPEC_MAINLINE_NODE_05_LINGXIAO_OUTER_COURT' 'complete design base catalyst source'
    Assert-Condition ($Materials.base_catalyst.required_for_base_collection_concept -eq $true) 'complete design base catalyst remains required conceptually'
    Assert-Equal $Materials.optional_sacred_catalyst.material_spec_id 'TT_SPEC_MATERIAL_FOUR_SACRED_FORGE_CORE' 'complete design sacred catalyst id'
    Assert-Equal $Materials.optional_sacred_catalyst.source_node_id 'TT_SPEC_MANSION_NIGHTMARE_MODE' 'complete design sacred catalyst source'
    Assert-Equal $Materials.optional_sacred_catalyst.upstream_reward_family_spec_id 'TT_SPEC_REWARD_SACRED_BEAST_CORE' 'complete design sacred material/reward-family mapping'
    Assert-Condition ($Materials.optional_sacred_catalyst.required_for_base_collection_concept -eq $false) 'complete design sacred catalyst is optional'
    Assert-Condition ([string]$Materials.optional_sacred_catalyst.role -match [regex]::Escape($SacredAttestationName)) 'complete design sacred catalyst only serves Four Symbols presentation'
    Assert-Condition ([string]$Materials.optional_sacred_catalyst.role -match $NoCombatPattern) 'complete design sacred catalyst has no combat strength'
    Assert-Equal @((Get-ByProperty @($Content.twenty_eight_mansions_raid.reward_families) 'spec_id' 'TT_SPEC_REWARD_SACRED_BEAST_CORE')).Count 1 'complete design upstream sacred reward family exists'
    foreach ($Field in @('actual_material_key', 'actual_quantity', 'actual_recipe', 'actual_consumption', 'actual_drop_profile', 'actual_drop_rate', 'actual_pity', 'actual_receipt')) {
      Assert-Null $Materials.$Field "complete design material deferred field: $Field"
    }

    Assert-ExactArray @($Contract.future_source_evidence_by_material_role | ForEach-Object { [string]$_.material_role }) @('seven_star_fragment_category', 'celestial_law_seal_base_catalyst', 'four_sacred_optional_attestation') 'complete design future source evidence roles'
    foreach ($Evidence in @($Contract.future_source_evidence_by_material_role)) {
      Assert-Null $Evidence.current_success_event "complete design current success event is deferred: $($Evidence.material_role)"
      Assert-Null $Evidence.current_material_grant "complete design current material grant is deferred: $($Evidence.material_role)"
    }
    $SevenEvidence = @(Get-ByProperty @($Contract.future_source_evidence_by_material_role) 'material_role' 'seven_star_fragment_category')[0]
    $LawEvidence = @(Get-ByProperty @($Contract.future_source_evidence_by_material_role) 'material_role' 'celestial_law_seal_base_catalyst')[0]
    $SacredEvidence = @(Get-ByProperty @($Contract.future_source_evidence_by_material_role) 'material_role' 'four_sacred_optional_attestation')[0]
    Assert-Equal $SevenEvidence.source_scope 'owner_only_single_player_trial' 'complete design seven-star evidence scope'
    Assert-Condition (@($SevenEvidence.required_future_evidence) -contains 'owner_actor_id') 'complete design seven-star evidence has owner'
    Assert-Equal $LawEvidence.source_scope 'private_mainline_final_effective_participant' 'complete design law-seal evidence scope'
    Assert-Condition (@($LawEvidence.required_future_evidence) -contains 'effective_participation') 'complete design law-seal evidence needs effective participation'
    Assert-Equal $SacredEvidence.source_scope 'nightmare_mansion_active_member' 'complete design sacred evidence scope'
    Assert-Condition (@($SacredEvidence.required_future_evidence) -contains 'rotation_snapshot_id') 'complete design sacred evidence has rotation snapshot'
    Assert-Condition (@($SacredEvidence.required_future_evidence) -contains 'difficulty') 'complete design sacred evidence has difficulty'
    Assert-Equal $Authority.mainline_final_session.participant_capacity.minimum 1 'complete design base catalyst remains individually reachable'

    Assert-Equal $Contract.title_and_collection_relationship.same_star_title_rule $FixedTenFragmentTitleRule 'complete design fixed ten-fragment title rule'
    Assert-Condition ([string]$Contract.title_and_collection_relationship.future_ledger_rule -match [regex]::Escape($DoubleSpendToken)) 'complete design future ledger prevents double spend'
    foreach ($Field in @('current_title_effect_values', 'current_consumption_rule', 'current_receipt_rule')) {
      Assert-Null $Contract.title_and_collection_relationship.$Field "complete design title deferred field: $Field"
    }

    Assert-Equal $Contract.optional_sacred_attestation.presentation_name $SacredAttestationName 'complete design optional sacred presentation name'
    Assert-Condition ([string]$Contract.optional_sacred_attestation.design_effect -match $NoNumericChangePattern) 'complete design sacred attestation has no numeric effect'
    Assert-Condition ($Contract.optional_sacred_attestation.is_base_graduation_requirement -eq $false) 'complete design sacred attestation is not base requirement'
    Assert-Condition ($Contract.optional_sacred_attestation.is_combat_form -eq $false) 'complete design sacred attestation is not combat form'
    foreach ($Field in @('actual_unlock_rule', 'actual_vfx_asset', 'actual_effect_value')) {
      Assert-Null $Contract.optional_sacred_attestation.$Field "complete design sacred attestation deferred field: $Field"
    }

    Assert-Equal @($Contract.cross_profession_compatibility.semantic_fit_cards).Count 4 'complete design has four profession fit cards'
    foreach ($Field in @('absolute_combat_values', 'profession_lock', 'best_in_slot_claim')) {
      Assert-Null $Contract.cross_profession_compatibility.$Field "complete design profession deferred field: $Field"
    }
    foreach ($Field in @('actual_vfx_asset', 'actual_ui_asset', 'actual_audio_asset')) {
      Assert-Null $Contract.readability_and_presentation.$Field "complete design presentation deferred field: $Field"
    }

    foreach ($Field in @('progression_writer', 'session_writer', 'cleanup_bypass', 'economy_v2_input', 'material_grant', 'title_grant', 'artifact_grant')) {
      Assert-Condition ($Contract.authority_failure_and_settlement_boundary.$Field -eq $false) "complete design authority boundary remains false: $Field"
    }
    foreach ($Field in @('actual_source_profile', 'actual_qualification', 'actual_receipt_schema')) {
      Assert-Null $Contract.authority_failure_and_settlement_boundary.$Field "complete design authority deferred field: $Field"
    }
    Assert-Condition ([string]$Contract.authority_failure_and_settlement_boundary.disconnection_rule -match [regex]::Escape($NoReconnectToken)) 'complete design disconnection cannot reconnect'
    Assert-ExactArray @($Contract.future_loadout_snapshot_handoff.required_future_fields) @('actor_id', 'actor_lifecycle_id', 'active_artifact_spec_id', 'selected_form_id', 'loadout_revision', 'session_or_raid_instance_id', 'session_epoch', 'authority_proof_ref') 'complete design future loadout snapshot fields'
    foreach ($Field in @('actual_snapshot_schema', 'actual_runtime_field_keys')) {
      Assert-Null $Contract.future_loadout_snapshot_handoff.$Field "complete design loadout snapshot deferred field: $Field"
    }
    foreach ($Field in @('future_migration_contract', 'actual_migration_cost', 'actual_migration_receipt')) {
      Assert-Null $Contract.legacy_and_migration_boundary.$Field "complete design migration deferred field: $Field"
    }

    foreach ($Property in $Contract.non_production_boundary.PSObject.Properties) {
      if ($Property.Name -eq 'economy_execution') {
        Assert-Condition ($Property.Value -eq $false) 'complete design economy execution remains false'
      }
      else {
        Assert-Null $Property.Value "complete design non-production field remains null: $($Property.Name)"
      }
    }
    Assert-ExactArray @($Contract.acceptance_matrix | ForEach-Object { [string]$_.acceptance_id }) @(
      'TT-ART-COMPLETE-001', 'TT-ART-COMPLETE-002', 'TT-ART-COMPLETE-003', 'TT-ART-COMPLETE-004', 'TT-ART-COMPLETE-005',
      'TT-ART-COMPLETE-006', 'TT-ART-COMPLETE-007', 'TT-ART-COMPLETE-008', 'TT-ART-COMPLETE-009', 'TT-ART-COMPLETE-010'
    ) 'complete design acceptance ids'
  }
}
catch {
  $script:Errors.Add("unexpected validator failure: $($_.Exception.Message)") | Out-Null
}

if ($script:Errors.Count -gt 0) {
  Write-Output "FAIL: TianTing graduation artifact complete-design validation failed ($($script:Errors.Count) errors, $($script:Checks) checks)."
  foreach ($Failure in $script:Errors) { Write-Output "- $Failure" }
  exit 1
}

Write-Output "PASS: TianTing graduation artifact complete-design contract is internally consistent ($($script:Checks) checks)."
