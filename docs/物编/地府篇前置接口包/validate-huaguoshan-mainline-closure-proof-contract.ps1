[CmdletBinding()]
param(
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Issues = New-Object System.Collections.Generic.List[object]

function Add-Issue {
    param([string]$Code, [string]$Path, [string]$Message)
    $script:Issues.Add([pscustomobject]@{ code = $Code; path = $Path; message = $Message }) | Out-Null
}

function Get-Field {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertFrom-Utf8Base64 {
    param([string]$Value)
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function Assert-Keys {
    param($Object, [string[]]$Expected, [string]$Path)
    if ($null -eq $Object) { Add-Issue 'missing_object' $Path 'Object is required.'; return }
    $actual = @($Object.PSObject.Properties.Name | Sort-Object)
    $expectedSorted = @($Expected | Sort-Object)
    if (@(Compare-Object -ReferenceObject $expectedSorted -DifferenceObject $actual).Count -ne 0) {
        Add-Issue 'strict_schema_drift' $Path "Expected fields [$($expectedSorted -join ', ')], got [$($actual -join ', ')]."
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Code, [string]$Path)
    if ($Actual -ne $Expected) { Add-Issue $Code $Path "Expected '$Expected', got '$Actual'." }
}

function Assert-Bool {
    param($Actual, [bool]$Expected, [string]$Code, [string]$Path)
    if ($Actual -isnot [bool] -or $Actual -ne $Expected) { Add-Issue $Code $Path "Expected boolean '$Expected', got '$Actual'." }
}

function Assert-Null {
    param($Actual, [string]$Path)
    if ($null -ne $Actual) { Add-Issue 'non_null_deferred_field' $Path "Expected null, got '$Actual'." }
}

function Assert-StringSet {
    param([object[]]$Actual, [string[]]$Expected, [string]$Code, [string]$Path)
    $actualStrings = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedStrings = @($Expected | Sort-Object -Unique)
    if (@(Compare-Object -ReferenceObject $expectedStrings -DifferenceObject $actualStrings).Count -ne 0) {
        Add-Issue $Code $Path "Expected [$($expectedStrings -join ', ')], got [$($actualStrings -join ', ')]."
    }
}

function Assert-SourceRefs {
    param($References, [string]$ProjectRoot)
    $expected = @{
        worldview_master = (ConvertFrom-Utf8Base64 'ZG9jcy8xMC3pobnnm67nu5/kuIDkuJbnlYzop4LmgLvnurIubWQ=')
        huaguoshan_route = (ConvertFrom-Utf8Base64 'ZG9jcy8wNy3oirHmnpzlsbHnr4flia/mnKzkuI7mjonokL3orr7orqEubWQ=')
        huaguoshan_encounter_contract = (ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYvMTUt6Iqx5p6c5bGx6YGt6YGH5LiOQk9TU+aImOaWl+Wlkee6pi5tZA==')
        growth_route_overlay = (ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYv5oiQ6ZW/5pWw5YC85LiO57uP5rWO6KOB5Yaz5YyFL3RhYmxlcy9lY29ub215LXYzLXJlc291cmNlLXRhYmxlLmpzb24=')
        difu_entry_consumer = (ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYv5Zyw5bqc56+H5YmN572u5o6l5Y+j5YyFL2NoYXB0ZXItZW50cnktY29udHJhY3QuanNvbg==')
    }
    Assert-StringSet -Actual @($References | ForEach-Object { [string]$_.role }) -Expected @($expected.Keys) -Code 'source_ref_role_drift' -Path 'contract.source_refs'
    foreach ($reference in @($References)) {
        Assert-Keys $reference @('role', 'path') 'contract.source_refs[]'
        $role = [string](Get-Field $reference 'role')
        $path = [string](Get-Field $reference 'path')
        if (-not $expected.ContainsKey($role) -or $path -ne $expected[$role]) {
            Add-Issue 'source_ref_path_drift' "contract.source_refs.$role" "Unexpected source path '$path'."
            continue
        }
        $full = [IO.Path]::GetFullPath((Join-Path $ProjectRoot ($path -replace '/', '\')))
        $rootFull = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'
        if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue 'source_ref_outside_project' "contract.source_refs.$role" 'Source reference escapes the project root.'
        } elseif (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            Add-Issue 'source_ref_missing' "contract.source_refs.$role" "Source reference '$path' does not resolve."
        }
    }
}

function Clone-Object {
    param($Object)
    return ($Object | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Validate-Contract {
    param($Contract, [string]$ProjectRoot)

    $script:Issues = New-Object System.Collections.Generic.List[object]
    Assert-Keys $Contract @('schema_version', 'package', 'artifact_status', 'status', 'production_gate', 'implementation_handoff', 'scope', 'source_refs', 'semantic_identifiers', 'producer_authorization', 'logical_proof_contract', 'rejection_contract', 'evidence_protocol', 'deferred', 'validation_contract') 'contract'
    Assert-Equal (Get-Field $Contract 'schema_version') 1 'schema_version_drift' 'contract.schema_version'
    Assert-Equal (Get-Field $Contract 'package') 'huaguoshan-mainline-closure-proof-contract' 'package_drift' 'contract.package'
    Assert-Equal (Get-Field $Contract 'artifact_status') 'non-production-interface-contract' 'artifact_status_drift' 'contract.artifact_status'
    Assert-Equal (Get-Field $Contract 'status') 'offline-interface-ready' 'status_drift' 'contract.status'
    Assert-Equal (Get-Field $Contract 'production_gate') 'closed' 'production_gate_drift' 'contract.production_gate'
    Assert-Bool (Get-Field $Contract 'implementation_handoff') $false 'implementation_handoff_drift' 'contract.implementation_handoff'

    $scope = Get-Field $Contract 'scope'
    Assert-Keys $scope @('includes', 'excludes') 'contract.scope'
    Assert-StringSet -Actual @(Get-Field $scope 'includes') -Expected @('same_actor_shark_effective_participation_to_molten_rift_discovery_sequence', 'spec_local_huaguoshan_regular_mainline_closure_proof_issue_or_replay_only', 'unique_producer_boundary_for_difu_entry_handoff') -Code 'scope_includes_drift' -Path 'contract.scope.includes'
    Assert-StringSet -Actual @(Get-Field $scope 'excludes') -Expected @('actual_runtime_or_persistent_key_or_save_write', 'map_coordinate_y3_object_unit_skill_encounter_or_session_implementation', 'xp_drop_probability_pity_currency_item_reward_economy_receipt_or_value') -Code 'scope_excludes_drift' -Path 'contract.scope.excludes'
    Assert-SourceRefs (Get-Field $Contract 'source_refs') $ProjectRoot

    $identifiers = Get-Field $Contract 'semantic_identifiers'
    Assert-Keys $identifiers @('identifier_scope', 'shark_encounter_key', 'shark_participation_evidence', 'molten_rift_discovery_event', 'huaguoshan_mainline_closure_event', 'semantic_identifier_not_runtime_key', 'actual_runtime_event_key', 'actual_runtime_progression_key', 'actual_storage_key') 'contract.semantic_identifiers'
    Assert-Equal (Get-Field $identifiers 'identifier_scope') 'spec_local_semantic_only' 'identifier_scope_drift' 'contract.semantic_identifiers.identifier_scope'
    Assert-Equal (Get-Field $identifiers 'shark_encounter_key') 'HG_E_SHARK_KING' 'shark_encounter_drift' 'contract.semantic_identifiers.shark_encounter_key'
    Assert-Equal (Get-Field $identifiers 'shark_participation_evidence') 'HG_SPEC_SHARK_PERSONAL_EFFECTIVE_PARTICIPATION_V1' 'shark_participation_identifier_drift' 'contract.semantic_identifiers.shark_participation_evidence'
    Assert-Equal (Get-Field $identifiers 'molten_rift_discovery_event') 'HG_SPEC_MOLTEN_RIFT_DISCOVERY_V1' 'molten_rift_identifier_drift' 'contract.semantic_identifiers.molten_rift_discovery_event'
    Assert-Equal (Get-Field $identifiers 'huaguoshan_mainline_closure_event') 'HG_SPEC_MAINLINE_CLOSURE_SUCCESS_V1' 'closure_identifier_drift' 'contract.semantic_identifiers.huaguoshan_mainline_closure_event'
    Assert-Bool (Get-Field $identifiers 'semantic_identifier_not_runtime_key') $true 'semantic_runtime_boundary_drift' 'contract.semantic_identifiers.semantic_identifier_not_runtime_key'
    foreach ($name in @('actual_runtime_event_key', 'actual_runtime_progression_key', 'actual_storage_key')) { Assert-Null (Get-Field $identifiers $name) "contract.semantic_identifiers.$name" }

    $producer = Get-Field $Contract 'producer_authorization'
    Assert-Keys $producer @('unique_producer', 'producer_authority', 'proof_scope', 'same_actor_required', 'same_actor_lifecycle_required', 'same_actor_lifecycle_scope', 'ordered_authority_evidence', 'route_choice_interlock', 'forbidden_substitutes') 'contract.producer_authorization'
    Assert-Bool (Get-Field $producer 'unique_producer') $true 'unique_producer_drift' 'contract.producer_authorization.unique_producer'
    Assert-Equal (Get-Field $producer 'producer_authority') 'trusted_huaguoshan_chapter_authority' 'producer_authority_drift' 'contract.producer_authorization.producer_authority'
    Assert-Equal (Get-Field $producer 'proof_scope') 'non_team_per_actor_mainline_closure_success' 'proof_scope_drift' 'contract.producer_authorization.proof_scope'
    Assert-Bool (Get-Field $producer 'same_actor_required') $true 'same_actor_drift' 'contract.producer_authorization.same_actor_required'
    Assert-Bool (Get-Field $producer 'same_actor_lifecycle_required') $true 'same_lifecycle_drift' 'contract.producer_authorization.same_actor_lifecycle_required'
    Assert-Equal (Get-Field $producer 'same_actor_lifecycle_scope') 'source_proof_issuance_evidence_only' 'same_lifecycle_scope_drift' 'contract.producer_authorization.same_actor_lifecycle_scope'
    $evidence = @(Get-Field $producer 'ordered_authority_evidence')
    $expectedEvidence = @(
        @{ id = 'HG_SPEC_FUTURE_REQUIRED_PUBLIC_ROUTE_V3'; encounter = $null },
        @{ id = 'HG_SPEC_SHARK_PERSONAL_EFFECTIVE_PARTICIPATION_V1'; encounter = 'HG_E_SHARK_KING' },
        @{ id = 'HG_SPEC_MOLTEN_RIFT_DISCOVERY_V1'; encounter = $null }
    )
    Assert-Equal $evidence.Count 3 'evidence_count_drift' 'contract.producer_authorization.ordered_authority_evidence'
    for ($index = 0; $index -lt [Math]::Min($evidence.Count, $expectedEvidence.Count); $index += 1) {
        $item = $evidence[$index]
        $expected = $expectedEvidence[$index]
        $allowed = @('order', 'semantic_id', 'meaning', 'source_profile_mapping', 'runtime_mapping')
        if ($null -ne $expected.encounter) { $allowed += 'encounter_key' }
        Assert-Keys $item $allowed "contract.producer_authorization.ordered_authority_evidence[$index]"
        Assert-Equal (Get-Field $item 'order') ($index + 1) 'evidence_order_drift' "contract.producer_authorization.ordered_authority_evidence[$index].order"
        Assert-Equal (Get-Field $item 'semantic_id') $expected.id 'evidence_identifier_drift' "contract.producer_authorization.ordered_authority_evidence[$index].semantic_id"
        if ($null -ne $expected.encounter) { Assert-Equal (Get-Field $item 'encounter_key') $expected.encounter 'evidence_encounter_drift' "contract.producer_authorization.ordered_authority_evidence[$index].encounter_key" }
        Assert-Null (Get-Field $item 'source_profile_mapping') "contract.producer_authorization.ordered_authority_evidence[$index].source_profile_mapping"
        Assert-Null (Get-Field $item 'runtime_mapping') "contract.producer_authorization.ordered_authority_evidence[$index].runtime_mapping"
    }
    $interlock = Get-Field $producer 'route_choice_interlock'
    Assert-Keys $interlock @('choice_id', 'narrative_discovery_event', 'crack_xp_source_key', 'peng_xp_source_key', 'rule', 'source_profile_mapping', 'runtime_mapping') 'contract.producer_authorization.route_choice_interlock'
    Assert-Equal (Get-Field $interlock 'choice_id') 'HG_ROUTE_PENG_OR_CRACK_V3' 'route_choice_drift' 'contract.producer_authorization.route_choice_interlock.choice_id'
    Assert-Equal (Get-Field $interlock 'narrative_discovery_event') 'HG_SPEC_MOLTEN_RIFT_DISCOVERY_V1' 'route_choice_discovery_drift' 'contract.producer_authorization.route_choice_interlock.narrative_discovery_event'
    Assert-Equal (Get-Field $interlock 'crack_xp_source_key') 'XP_HG_CRACK_DISCOVERY' 'route_choice_crack_drift' 'contract.producer_authorization.route_choice_interlock.crack_xp_source_key'
    Assert-Equal (Get-Field $interlock 'peng_xp_source_key') 'XP_PENG' 'route_choice_peng_drift' 'contract.producer_authorization.route_choice_interlock.peng_xp_source_key'
    if ([string](Get-Field $interlock 'rule') -notmatch 'Peng selection still requires discovery') { Add-Issue 'route_choice_interlock_drift' 'contract.producer_authorization.route_choice_interlock.rule' 'Peng selection must retain molten-rift discovery while blocking crack XP replay.' }
    Assert-Null (Get-Field $interlock 'source_profile_mapping') 'contract.producer_authorization.route_choice_interlock.source_profile_mapping'
    Assert-Null (Get-Field $interlock 'runtime_mapping') 'contract.producer_authorization.route_choice_interlock.runtime_mapping'
    Assert-StringSet -Actual @(Get-Field $producer 'forbidden_substitutes') -Expected @('HG_E_JIAO_KING participation alone', 'XP_PENG or Peng Demon King clear', 'HG_E_DRAGON_OLD_TIDE completion', 'HG_E_OX_BATTLEFIELD team completion', 'teammate leader party or client-reported result', 'rare award collection checklist or tower progress') -Code 'forbidden_substitutes_drift' -Path 'contract.producer_authorization.forbidden_substitutes'

    $proof = Get-Field $Contract 'logical_proof_contract'
    Assert-Keys $proof @('proof_semantic_id', 'write_authority', 'actor_lifecycle_claim_semantic', 'downstream_current_lifecycle_binding', 'idempotency_key_fields', 'required_claim_fields', 'first_accept_outcome', 'exact_replay_outcome', 'actual_runtime_proof_key', 'actual_storage_key') 'contract.logical_proof_contract'
    Assert-Equal (Get-Field $proof 'proof_semantic_id') 'HG_SPEC_MAINLINE_CLOSURE_SUCCESS_V1' 'proof_identifier_drift' 'contract.logical_proof_contract.proof_semantic_id'
    Assert-Equal (Get-Field $proof 'write_authority') 'trusted_huaguoshan_chapter_authority' 'proof_authority_drift' 'contract.logical_proof_contract.write_authority'
    Assert-Equal (Get-Field $proof 'actor_lifecycle_claim_semantic') 'immutable_source_lifecycle_audit' 'proof_source_lifecycle_claim_drift' 'contract.logical_proof_contract.actor_lifecycle_claim_semantic'
    Assert-Equal (Get-Field $proof 'downstream_current_lifecycle_binding') 'source_claim_audit_only_not_equal_to_current_entry_request' 'proof_downstream_lifecycle_binding_drift' 'contract.logical_proof_contract.downstream_current_lifecycle_binding'
    Assert-StringSet -Actual @(Get-Field $proof 'idempotency_key_fields') -Expected @('actor_id', 'event_id') -Code 'proof_idempotency_drift' -Path 'contract.logical_proof_contract.idempotency_key_fields'
    Assert-StringSet -Actual @(Get-Field $proof 'required_claim_fields') -Expected @('actor_id', 'actor_lifecycle_id', 'event_id', 'source_event_semantic_id', 'opaque_handoff_proof_ref', 'completed_tick', 'authority_proof_ref', 'schema_version') -Code 'proof_claim_fields_drift' -Path 'contract.logical_proof_contract.required_claim_fields'
    Assert-Equal (Get-Field $proof 'first_accept_outcome') 'issue_spec_local_opaque_handoff_proof_only' 'proof_first_outcome_drift' 'contract.logical_proof_contract.first_accept_outcome'
    Assert-Equal (Get-Field $proof 'exact_replay_outcome') 'return_existing_spec_local_opaque_handoff_proof_without_second_issue' 'proof_replay_outcome_drift' 'contract.logical_proof_contract.exact_replay_outcome'
    Assert-Null (Get-Field $proof 'actual_runtime_proof_key') 'contract.logical_proof_contract.actual_runtime_proof_key'
    Assert-Null (Get-Field $proof 'actual_storage_key') 'contract.logical_proof_contract.actual_storage_key'

    $rejections = Get-Field $Contract 'rejection_contract'
    Assert-Keys $rejections @('foreign_actor', 'stale_or_mismatched_actor_lifecycle', 'missing_invalid_or_foreign_authority_evidence', 'shark_participation_missing_or_not_personal', 'molten_rift_discovery_missing_or_out_of_order', 'jiao_only_peng_dragon_ox_team_rare_collection_or_tower_substitute', 'client_reported_progress_or_proof', 'replay_with_mismatched_lifecycle_or_evidence', 'teammate_leader_or_party_result') 'contract.rejection_contract'
    foreach ($property in @($rejections.PSObject.Properties)) { Assert-Equal $property.Value 'denied' 'rejection_boundary_drift' "contract.rejection_contract.$($property.Name)" }

    $protocol = Get-Field $Contract 'evidence_protocol'
    Assert-Keys $protocol @('artifact_status', 'evidence_only', 'permitted_outcomes', 'forbidden_outcomes', 'production_value', 'candidate_value') 'contract.evidence_protocol'
    Assert-Equal (Get-Field $protocol 'artifact_status') 'non-production' 'evidence_status_drift' 'contract.evidence_protocol.artifact_status'
    Assert-Bool (Get-Field $protocol 'evidence_only') $true 'evidence_only_drift' 'contract.evidence_protocol.evidence_only'
    Assert-StringSet -Actual @(Get-Field $protocol 'permitted_outcomes') -Expected @('issue_spec_local_opaque_handoff_proof_only', 'return_existing_spec_local_opaque_handoff_proof_without_second_issue') -Code 'permitted_outcomes_drift' -Path 'contract.evidence_protocol.permitted_outcomes'
    Assert-StringSet -Actual @(Get-Field $protocol 'forbidden_outcomes') -Expected @('grant_reward', 'grant_currency', 'grant_item', 'grant_xp', 'set_probability', 'set_pity', 'open_map_session', 'write_runtime_key') -Code 'forbidden_outcomes_drift' -Path 'contract.evidence_protocol.forbidden_outcomes'
    Assert-Null (Get-Field $protocol 'production_value') 'contract.evidence_protocol.production_value'
    Assert-Null (Get-Field $protocol 'candidate_value') 'contract.evidence_protocol.candidate_value'

    $deferred = Get-Field $Contract 'deferred'
    Assert-Keys $deferred @('runtime_event_key', 'runtime_progression_key', 'persistent_storage_key', 'map_key', 'map_id', 'map_coordinates', 'y3_object_ids', 'reward_values', 'xp_values', 'currency_values', 'item_values', 'drop_tables', 'probability_values', 'pity_values', 'economy_receipt') 'contract.deferred'
    foreach ($property in @($deferred.PSObject.Properties)) { Assert-Null $property.Value "contract.deferred.$($property.Name)" }

    $validation = Get-Field $Contract 'validation_contract'
    Assert-Keys $validation @('validator', 'strict_schema', 'source_refs_must_resolve', 'negative_tests_required', 'production_value', 'candidate_value') 'contract.validation_contract'
    Assert-Equal (Get-Field $validation 'validator') 'validate-huaguoshan-mainline-closure-proof-contract.ps1' 'validator_path_drift' 'contract.validation_contract.validator'
    Assert-Bool (Get-Field $validation 'strict_schema') $true 'validation_strict_drift' 'contract.validation_contract.strict_schema'
    Assert-Bool (Get-Field $validation 'source_refs_must_resolve') $true 'validation_source_ref_drift' 'contract.validation_contract.source_refs_must_resolve'
    Assert-Bool (Get-Field $validation 'negative_tests_required') $true 'validation_negative_test_drift' 'contract.validation_contract.negative_tests_required'
    Assert-Null (Get-Field $validation 'production_value') 'contract.validation_contract.production_value'
    Assert-Null (Get-Field $validation 'candidate_value') 'contract.validation_contract.candidate_value'

    $entryPath = Join-Path $ProjectRoot ((ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYv5Zyw5bqc56+H5YmN572u5o6l5Y+j5YyFL2NoYXB0ZXItZW50cnktY29udHJhY3QuanNvbg==') -replace '/', '\\')
    try { $entry = Get-Content -LiteralPath $entryPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Add-Issue 'entry_contract_unreadable' 'chapter-entry-contract.json' $_.Exception.Message; return $script:Issues.ToArray() }
    Assert-Equal (Get-Field $entry.semantic_identifiers 'hg_mainline_closure_event') 'HG_SPEC_MAINLINE_CLOSURE_SUCCESS_V1' 'entry_consumer_identifier_drift' 'chapter-entry-contract.json.semantic_identifiers.hg_mainline_closure_event'
    $entryProof = Get-Field $entry.entry_authorization 'required_handoff_proof'
    Assert-Bool (Get-Field $entry.entry_authorization 'current_request_lifecycle_required') $true 'entry_consumer_current_lifecycle_drift' 'chapter-entry-contract.json.entry_authorization.current_request_lifecycle_required'
    Assert-Equal (Get-Field $entry.entry_authorization 'current_request_lifecycle_source') 'trusted_character_authority' 'entry_consumer_current_lifecycle_source_drift' 'chapter-entry-contract.json.entry_authorization.current_request_lifecycle_source'
    Assert-Equal (Get-Field $entryProof 'source_event_semantic_id') 'HG_SPEC_MAINLINE_CLOSURE_SUCCESS_V1' 'entry_consumer_source_event_drift' 'chapter-entry-contract.json.entry_authorization.required_handoff_proof.source_event_semantic_id'
    Assert-Equal (Get-Field $entryProof 'source_event_scope') 'non_team_per_actor_mainline_closure_success' 'entry_consumer_scope_drift' 'chapter-entry-contract.json.entry_authorization.required_handoff_proof.source_event_scope'
    Assert-Equal (Get-Field $entryProof 'source_actor_lifecycle_claim') 'required_immutable_audit_only' 'entry_consumer_source_lifecycle_claim_drift' 'chapter-entry-contract.json.entry_authorization.required_handoff_proof.source_actor_lifecycle_claim'
    Assert-Bool (Get-Field $entryProof 'source_actor_lifecycle_equals_current_request') $false 'entry_consumer_source_lifecycle_equality_drift' 'chapter-entry-contract.json.entry_authorization.required_handoff_proof.source_actor_lifecycle_equals_current_request'
    Assert-Equal (Get-Field $entryProof 'producer_contract_path') (ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYv5Zyw5bqc56+H5YmN572u5o6l5Y+j5YyFL2h1YWd1b3NoYW4tbWFpbmxpbmUtY2xvc3VyZS1wcm9vZi1jb250cmFjdC5qc29u') 'entry_consumer_producer_ref_drift' 'chapter-entry-contract.json.entry_authorization.required_handoff_proof.producer_contract_path'

    $worldPath = (ConvertFrom-Utf8Base64 'ZG9jcy8xMC3pobnnm67nu5/kuIDkuJbnlYzop4LmgLvnurIubWQ=')
    $routePath = (ConvertFrom-Utf8Base64 'ZG9jcy8wNy3oirHmnpzlsbHnr4flia/mnKzkuI7mjonokL3orr7orqEubWQ=')
    $worldText = Get-Content -LiteralPath (Join-Path $ProjectRoot ($worldPath -replace '/', '\\')) -Raw -Encoding UTF8
    $routeText = Get-Content -LiteralPath (Join-Path $ProjectRoot ($routePath -replace '/', '\\')) -Raw -Encoding UTF8
    if ($worldText -notmatch (ConvertFrom-Utf8Base64 '6bKo6a2U546L6YGt6YGH') -or $worldText -notmatch (ConvertFrom-Utf8Base64 '54aU6ISJ6KOC5Y+j')) { Add-Issue 'world_source_drift' $worldPath 'World master must retain Shark-to-molten-rift causality.' }
    if ($routeText -notmatch (ConvertFrom-Utf8Base64 '6bKo6a2U546L5Liq5Lq65pyJ5pWI5Y+C5LiO') -or $routeText -notmatch (ConvertFrom-Utf8Base64 '5bi46KeE5pS25p2f')) { Add-Issue 'route_source_drift' $routePath 'Huaguoshan route must name Shark personal participation as the regular closure trigger.' }
    return $script:Issues.ToArray()
}

$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$contractPath = Join-Path $PSScriptRoot 'huaguoshan-mainline-closure-proof-contract.json'
try { $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Write-Error "Cannot parse '$contractPath': $($_.Exception.Message)"; exit 1 }

$issues = @(Validate-Contract $contract $projectRoot)
if ($issues.Count -gt 0) {
    $issues | ForEach-Object { Write-Error "[$($_.code)] $($_.path): $($_.message)" }
    exit 1
}

$negativeTests = @(
    [pscustomobject]@{ name = 'shark_encounter_replaced'; code = 'shark_encounter_drift'; mutate = { param($copy) $copy.semantic_identifiers.shark_encounter_key = 'HG_E_JIAO_KING' } },
    [pscustomobject]@{ name = 'team_scope_allowed'; code = 'proof_scope_drift'; mutate = { param($copy) $copy.producer_authorization.proof_scope = 'team_mainline_closure_success' } },
    [pscustomobject]@{ name = 'source_proof_lifecycle_scope_drift'; code = 'same_lifecycle_scope_drift'; mutate = { param($copy) $copy.producer_authorization.same_actor_lifecycle_scope = 'all_future_entry_requests' } },
    [pscustomobject]@{ name = 'route_evidence_order_changed'; code = 'evidence_order_drift'; mutate = { param($copy) $copy.producer_authorization.ordered_authority_evidence[2].order = 2 } },
    [pscustomobject]@{ name = 'peng_replaces_rift'; code = 'route_choice_interlock_drift'; mutate = { param($copy) $copy.producer_authorization.route_choice_interlock.rule = 'Peng selection does not require discovery.' } },
    [pscustomobject]@{ name = 'jiao_substitute_removed'; code = 'forbidden_substitutes_drift'; mutate = { param($copy) $copy.producer_authorization.forbidden_substitutes = @($copy.producer_authorization.forbidden_substitutes | Where-Object { $_ -ne 'HG_E_JIAO_KING participation alone' }) } },
    [pscustomobject]@{ name = 'reward_outcome_injected'; code = 'permitted_outcomes_drift'; mutate = { param($copy) $copy.evidence_protocol.permitted_outcomes += 'grant_reward' } },
    [pscustomobject]@{ name = 'runtime_key_injected'; code = 'non_null_deferred_field'; mutate = { param($copy) $copy.deferred.runtime_progression_key = 'HG_RUNTIME_FORBIDDEN' } },
    [pscustomobject]@{ name = 'closure_identifier_drift'; code = 'closure_identifier_drift'; mutate = { param($copy) $copy.semantic_identifiers.huaguoshan_mainline_closure_event = 'OTHER' } },
    [pscustomobject]@{ name = 'downstream_lifecycle_equality_drift'; code = 'proof_downstream_lifecycle_binding_drift'; mutate = { param($copy) $copy.logical_proof_contract.downstream_current_lifecycle_binding = 'must_equal_current_entry_request' } }
)

$negativeFailures = New-Object System.Collections.Generic.List[object]
foreach ($test in $negativeTests) {
    $copy = Clone-Object $contract
    & $test.mutate $copy
    $testIssues = @(Validate-Contract $copy $projectRoot)
    if (@($testIssues | Where-Object { $_.code -eq $test.code }).Count -eq 0) {
        $negativeFailures.Add([pscustomobject]@{ name = $test.name; expected = $test.code; observed = @($testIssues | ForEach-Object { $_.code }) -join ',' }) | Out-Null
    }
}
if ($negativeFailures.Count -gt 0) {
    $negativeFailures | ForEach-Object { Write-Error "Negative test '$($_.name)' expected '$($_.expected)', observed '$($_.observed)'." }
    exit 1
}

if (-not $Quiet) {
    Write-Output 'PASS huaguoshan-mainline-closure-proof-contract.json: unique Shark-to-rift producer and non-production boundary validated.'
    Write-Output ("PASS negative tests: {0}/{0}." -f $negativeTests.Count)
}
