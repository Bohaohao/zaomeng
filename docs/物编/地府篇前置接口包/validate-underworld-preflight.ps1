param(
    [string]$ContractPath = (Join-Path $PSScriptRoot 'cross-chapter-interface.json'),
    [string]$DesignPath = (Join-Path $PSScriptRoot 'design-spec.json'),
    [switch]$SkipNegativeTests
)

$ErrorActionPreference = 'Stop'

function New-IssueList { Write-Output -NoEnumerate ([System.Collections.Generic.List[object]]::new()) }

function Add-Issue {
    param([System.Collections.Generic.List[object]]$List, [string]$Code, [string]$Path, [string]$Message)
    $List.Add([pscustomobject]@{ code = $Code; path = $Path; message = $Message }) | Out-Null
}

function Test-HasProperty {
    param($Object, [string]$Name)
    $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-PropertySet {
    param($Object, [string[]]$Required, [string[]]$Allowed, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Object) { Add-Issue $Errors 'missing_object' $Path 'Object must not be null.'; return }
    foreach ($Name in $Required) {
        if (-not (Test-HasProperty $Object $Name)) { Add-Issue $Errors 'missing_required_property' "$Path.$Name" 'Missing required property.' }
    }
    foreach ($Property in $Object.PSObject.Properties) {
        if ($Allowed -notcontains $Property.Name) { Add-Issue $Errors 'unexpected_property' "$Path.$($Property.Name)" 'Unknown property is not allowed.' }
    }
}

function Assert-ExactString {
    param($Actual, [string]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [string]) -or $Actual -ne $Expected) { Add-Issue $Errors 'fixed_value_mismatch' $Path "Expected '$Expected'." }
}

function Assert-StrictBoolean {
    param($Actual, [bool]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [bool]) -or $Actual -ne $Expected) { Add-Issue $Errors 'strict_boolean_mismatch' $Path "Expected JSON boolean $Expected." }
}

function Assert-Null {
    param($Actual, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if ($null -ne $Actual) { Add-Issue $Errors 'non_null_nonproduction_value' $Path 'Production and candidate values must be null.' }
}

function ConvertTo-StringArray {
    param($Value)
    if ($null -eq $Value) { Write-Output -NoEnumerate ([string[]]@()); return }
    [string[]]$Values = @($Value | ForEach-Object { [string]$_ })
    Write-Output -NoEnumerate $Values
}

function Assert-ExactStringArray {
    param($Actual, [string[]]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    $Values = ConvertTo-StringArray $Actual
    if ($Values.Count -ne $Expected.Count) { Add-Issue $Errors 'fixed_array_mismatch' $Path 'Array length does not match the fixed contract.'; return }
    for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
        if ($Values[$Index] -ne $Expected[$Index]) { Add-Issue $Errors 'fixed_array_mismatch' "${Path}[$Index]" "Expected '$($Expected[$Index])'." }
    }
}

function ConvertFrom-UnicodeCodePoints {
    param([int[]]$Points)
    return -join @($Points | ForEach-Object { [char]$_ })
}

function Read-JsonFile {
    param([string]$Path, [System.Collections.Generic.List[object]]$Errors, [string]$IssuePath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Issue $Errors 'file_not_found' $IssuePath "File not found: $Path"; return $null }
    try { Get-Content -Raw -Encoding utf8 -LiteralPath $Path | ConvertFrom-Json }
    catch { Add-Issue $Errors 'invalid_json' $IssuePath $_.Exception.Message; $null }
}

function Test-RelativeSourceRef {
    param([string]$SourceRef, [string]$ProjectRoot, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if ([string]::IsNullOrWhiteSpace($SourceRef)) { Add-Issue $Errors 'blank_source_ref' $Path 'source_refs must not be blank.'; return }
    $Match = [regex]::Match($SourceRef, '^(?<relative>[^:]+?)(?::(?<ranges>\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)?)?$')
    if (-not $Match.Success) { Add-Issue $Errors 'invalid_source_ref' $Path 'Source ref must use a project-relative path and optional line range.'; return }
    $Relative = $Match.Groups['relative'].Value
    if ([System.IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') { Add-Issue $Errors 'non_relative_source_ref' $Path 'Source ref must remain under the project root.'; return }
    $Candidate = Join-Path $ProjectRoot $Relative
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { Add-Issue $Errors 'source_ref_not_found' $Path "Source file not found: $Relative"; return }
    $ResolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd([char[]]@('\','/'))
    $ResolvedFile = (Resolve-Path -LiteralPath $Candidate).Path
    $Prefix = $ResolvedRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $ResolvedFile.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { Add-Issue $Errors 'source_ref_outside_project' $Path 'Source ref resolves outside the project root.'; return }
    if ($Match.Groups['ranges'].Value) {
        $LineCount = @(Get-Content -Encoding utf8 -LiteralPath $ResolvedFile).Count
        foreach ($Range in $Match.Groups['ranges'].Value.Split(',')) {
            $Parts = $Range.Split('-'); $Start = [int]$Parts[0]; $End = if ($Parts.Count -eq 2) { [int]$Parts[1] } else { $Start }
            if ($Start -lt 1 -or $End -lt $Start -or $End -gt $LineCount) { Add-Issue $Errors 'source_ref_line_out_of_range' $Path "Source line range $Range exceeds $Relative lines 1-$LineCount." }
        }
    }
}

function Test-NonProductionBoundary {
    param($Value, [string]$Path, [string[]]$ForbiddenFieldNames, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return }
    if ($Value -is [System.Array]) {
        foreach ($Item in $Value) { Test-NonProductionBoundary $Item "${Path}[]" $ForbiddenFieldNames $Errors }
        return
    }
    foreach ($Property in $Value.PSObject.Properties) {
        $PropertyPath = if ($Path) { "$Path.$($Property.Name)" } else { $Property.Name }
        if ($ForbiddenFieldNames -contains $Property.Name) { Add-Issue $Errors 'forbidden_production_field' $PropertyPath 'Non-production interface package forbids this field.' }
        if ($Property.Name -match '^(production|candidate)(?:_.*)?_value$' -and $null -ne $Property.Value) { Add-Issue $Errors 'non_null_nonproduction_value' $PropertyPath 'Production and candidate values must be null.' }
        Test-NonProductionBoundary $Property.Value $PropertyPath $ForbiddenFieldNames $Errors
    }
}

function Test-InterfaceContract {
    param($Contract, [string]$ProjectRoot, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Contract) { return }

    $Root = @('schema_version','package','artifact_status','status','production_gate','implementation_handoff','scope','source_refs','fixed_decisions','progression_contract','recovery_contract','evidence_protocol','deferred','forbidden_field_names','validation_contract')
    Assert-PropertySet $Contract $Root $Root 'contract' $Errors
    if ($Contract.schema_version -ne 1) { Add-Issue $Errors 'fixed_value_mismatch' 'contract.schema_version' 'Expected 1.' }
    Assert-ExactString $Contract.package 'difu-preflight-interface' 'contract.package' $Errors
    Assert-ExactString $Contract.artifact_status 'non-production-interface-contract' 'contract.artifact_status' $Errors
    Assert-ExactString $Contract.status 'offline-interface-ready' 'contract.status' $Errors
    Assert-ExactString $Contract.production_gate 'closed' 'contract.production_gate' $Errors
    Assert-StrictBoolean $Contract.implementation_handoff $false 'contract.implementation_handoff' $Errors

    $Scope = @('includes','excludes')
    Assert-PropertySet $Contract.scope $Scope $Scope 'contract.scope' $Errors
    foreach ($Name in $Scope) { if ((ConvertTo-StringArray $Contract.scope.$Name).Count -eq 0) { Add-Issue $Errors 'invalid_string_array' "contract.scope.$Name" 'Expected a non-empty string array.' } }
    $SourceRefs = ConvertTo-StringArray $Contract.source_refs
    if ($SourceRefs.Count -eq 0) { Add-Issue $Errors 'empty_source_refs' 'contract.source_refs' 'At least one source ref is required.' }
    for ($Index = 0; $Index -lt $SourceRefs.Count; $Index++) { Test-RelativeSourceRef $SourceRefs[$Index] $ProjectRoot "contract.source_refs[$Index]" $Errors }

    $DecisionNames = @('difu_team_instance','difu_normal_final','reverse_tide_unlock')
    Assert-PropertySet $Contract.fixed_decisions $DecisionNames $DecisionNames 'contract.fixed_decisions' $Errors
    $SimpleDecision = @('encounter_key','encounter_type','status','production_value','candidate_value')
    Assert-PropertySet $Contract.fixed_decisions.difu_team_instance $SimpleDecision $SimpleDecision 'contract.fixed_decisions.difu_team_instance' $Errors
    Assert-ExactString $Contract.fixed_decisions.difu_team_instance.encounter_key 'DF_E_ZHUANLUN_HALL' 'contract.fixed_decisions.difu_team_instance.encounter_key' $Errors
    Assert-ExactString $Contract.fixed_decisions.difu_team_instance.encounter_type 'team_instance' 'contract.fixed_decisions.difu_team_instance.encounter_type' $Errors
    Assert-ExactString $Contract.fixed_decisions.difu_team_instance.status 'fixed-user-decision' 'contract.fixed_decisions.difu_team_instance.status' $Errors
    Assert-Null $Contract.fixed_decisions.difu_team_instance.production_value 'contract.fixed_decisions.difu_team_instance.production_value' $Errors
    Assert-Null $Contract.fixed_decisions.difu_team_instance.candidate_value 'contract.fixed_decisions.difu_team_instance.candidate_value' $Errors
    Assert-PropertySet $Contract.fixed_decisions.difu_normal_final $SimpleDecision $SimpleDecision 'contract.fixed_decisions.difu_normal_final' $Errors
    Assert-ExactString $Contract.fixed_decisions.difu_normal_final.encounter_key 'DF_E_YANLUO_HALL' 'contract.fixed_decisions.difu_normal_final.encounter_key' $Errors
    Assert-ExactString $Contract.fixed_decisions.difu_normal_final.encounter_type 'non_team_normal_final' 'contract.fixed_decisions.difu_normal_final.encounter_type' $Errors
    Assert-ExactString $Contract.fixed_decisions.difu_normal_final.status 'fixed-user-decision' 'contract.fixed_decisions.difu_normal_final.status' $Errors
    Assert-Null $Contract.fixed_decisions.difu_normal_final.production_value 'contract.fixed_decisions.difu_normal_final.production_value' $Errors
    Assert-Null $Contract.fixed_decisions.difu_normal_final.candidate_value 'contract.fixed_decisions.difu_normal_final.candidate_value' $Errors

    $Unlock = @('consumer_encounter_key','minimum_level','required_progression_key','trusted_query_required','rejected_legacy_progression_key','status','production_value','candidate_value')
    Assert-PropertySet $Contract.fixed_decisions.reverse_tide_unlock $Unlock $Unlock 'contract.fixed_decisions.reverse_tide_unlock' $Errors
    Assert-ExactString $Contract.fixed_decisions.reverse_tide_unlock.consumer_encounter_key 'HG_E_DRAGON_REVERSE_TIDE' 'contract.fixed_decisions.reverse_tide_unlock.consumer_encounter_key' $Errors
    if ($Contract.fixed_decisions.reverse_tide_unlock.minimum_level -ne 38) { Add-Issue $Errors 'fixed_value_mismatch' 'contract.fixed_decisions.reverse_tide_unlock.minimum_level' 'Expected 38.' }
    Assert-ExactString $Contract.fixed_decisions.reverse_tide_unlock.required_progression_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'contract.fixed_decisions.reverse_tide_unlock.required_progression_key' $Errors
    Assert-StrictBoolean $Contract.fixed_decisions.reverse_tide_unlock.trusted_query_required $true 'contract.fixed_decisions.reverse_tide_unlock.trusted_query_required' $Errors
    Assert-ExactString $Contract.fixed_decisions.reverse_tide_unlock.rejected_legacy_progression_key 'underworld_late' 'contract.fixed_decisions.reverse_tide_unlock.rejected_legacy_progression_key' $Errors
    Assert-ExactString $Contract.fixed_decisions.reverse_tide_unlock.status 'fixed-user-decision' 'contract.fixed_decisions.reverse_tide_unlock.status' $Errors
    Assert-Null $Contract.fixed_decisions.reverse_tide_unlock.production_value 'contract.fixed_decisions.reverse_tide_unlock.production_value' $Errors
    Assert-Null $Contract.fixed_decisions.reverse_tide_unlock.candidate_value 'contract.fixed_decisions.reverse_tide_unlock.candidate_value' $Errors

    $Receipt = @('actor_id','actor_lifecycle_id','event_id','producer_encounter_key','session_instance_id','session_epoch','completed_tick','authority_proof_ref')
    $Progression = @('record_key','owner_scope','write_authority','write_event','producer_encounter_key','consumer_encounter_key','required_receipt_fields','idempotency_key_fields','write_condition','non_writer_sources','production_value','candidate_value')
    Assert-PropertySet $Contract.progression_contract $Progression $Progression 'contract.progression_contract' $Errors
    Assert-ExactString $Contract.progression_contract.record_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'contract.progression_contract.record_key' $Errors
    Assert-ExactString $Contract.progression_contract.owner_scope 'character' 'contract.progression_contract.owner_scope' $Errors
    Assert-ExactString $Contract.progression_contract.write_authority 'trusted_map_authority' 'contract.progression_contract.write_authority' $Errors
    Assert-ExactString $Contract.progression_contract.write_event 'completion_success' 'contract.progression_contract.write_event' $Errors
    Assert-ExactString $Contract.progression_contract.producer_encounter_key 'DF_E_YANLUO_HALL' 'contract.progression_contract.producer_encounter_key' $Errors
    Assert-ExactString $Contract.progression_contract.consumer_encounter_key 'HG_E_DRAGON_REVERSE_TIDE' 'contract.progression_contract.consumer_encounter_key' $Errors
    Assert-ExactStringArray $Contract.progression_contract.required_receipt_fields $Receipt 'contract.progression_contract.required_receipt_fields' $Errors
    Assert-ExactStringArray $Contract.progression_contract.idempotency_key_fields @('actor_id','event_id') 'contract.progression_contract.idempotency_key_fields' $Errors
    Assert-ExactString $Contract.progression_contract.write_condition 'same_actor_completed_yanluo_hall_with_authoritative_success_receipt' 'contract.progression_contract.write_condition' $Errors
    $ExpectedNonWriterSources = @(
        'DF_E_ZHUANLUN_HALL',
        (ConvertFrom-UnicodeCodePoints @(0x767D,0x9AA8,0x79D8,0x5883)),
        (ConvertFrom-UnicodeCodePoints @(0x5BA2,0x6237,0x7AEF,0x5E03,0x5C14,0x503C)),
        (ConvertFrom-UnicodeCodePoints @(0x961F,0x4F0D,0x9886,0x961F,0x6216,0x961F,0x53CB,0x8FDB,0x5EA6)),
        (ConvertFrom-UnicodeCodePoints @(0x4E16,0x754C,0x72B6,0x6001))
    )
    Assert-ExactStringArray $Contract.progression_contract.non_writer_sources $ExpectedNonWriterSources 'contract.progression_contract.non_writer_sources' $Errors
    Assert-Null $Contract.progression_contract.production_value 'contract.progression_contract.production_value' $Errors
    Assert-Null $Contract.progression_contract.candidate_value 'contract.progression_contract.candidate_value' $Errors

    $Recovery = @('policy_key','applies_to','initial_spawn_reference','cleanup_ack_required','cleanup_ack_identity_fields','reentry_before_cleanup_ack','member_death','full_wipe','timeout','production_value','candidate_value')
    Assert-PropertySet $Contract.recovery_contract $Recovery $Recovery 'contract.recovery_contract' $Errors
    Assert-ExactString $Contract.recovery_contract.policy_key 'TEAM_INSTANCE_RETURN_TO_CHAPTER_INITIAL_SPAWN_V1' 'contract.recovery_contract.policy_key' $Errors
    Assert-ExactStringArray $Contract.recovery_contract.applies_to @('team_instance') 'contract.recovery_contract.applies_to' $Errors
    Assert-ExactString $Contract.recovery_contract.initial_spawn_reference 'chapter_initial_spawn' 'contract.recovery_contract.initial_spawn_reference' $Errors
    Assert-StrictBoolean $Contract.recovery_contract.cleanup_ack_required $true 'contract.recovery_contract.cleanup_ack_required' $Errors
    Assert-ExactStringArray $Contract.recovery_contract.cleanup_ack_identity_fields @('raid_instance_id','session_epoch','cleanup_token') 'contract.recovery_contract.cleanup_ack_identity_fields' $Errors
    Assert-ExactString $Contract.recovery_contract.reentry_before_cleanup_ack 'denied' 'contract.recovery_contract.reentry_before_cleanup_ack' $Errors
    $MemberDeath = @('return_target','member_status','revive_before_return','left_behavior','reentry_lock','already_dead_repeat_return')
    Assert-PropertySet $Contract.recovery_contract.member_death $MemberDeath $MemberDeath 'contract.recovery_contract.member_death' $Errors
    Assert-ExactString $Contract.recovery_contract.member_death.return_target 'chapter_initial_spawn' 'contract.recovery_contract.member_death.return_target' $Errors
    Assert-ExactString $Contract.recovery_contract.member_death.member_status 'dead' 'contract.recovery_contract.member_death.member_status' $Errors
    Assert-StrictBoolean $Contract.recovery_contract.member_death.revive_before_return $true 'contract.recovery_contract.member_death.revive_before_return' $Errors
    Assert-ExactString $Contract.recovery_contract.member_death.left_behavior 'no_revive_no_return' 'contract.recovery_contract.member_death.left_behavior' $Errors
    Assert-ExactString $Contract.recovery_contract.member_death.reentry_lock 'until_matching_cleanup_ack' 'contract.recovery_contract.member_death.reentry_lock' $Errors
    Assert-ExactString $Contract.recovery_contract.member_death.already_dead_repeat_return 'forbidden' 'contract.recovery_contract.member_death.already_dead_repeat_return' $Errors
    $Wipe = @('return_target','already_dead_repeat_return','cleanup_ack_required')
    Assert-PropertySet $Contract.recovery_contract.full_wipe $Wipe $Wipe 'contract.recovery_contract.full_wipe' $Errors
    Assert-ExactString $Contract.recovery_contract.full_wipe.return_target 'chapter_initial_spawn' 'contract.recovery_contract.full_wipe.return_target' $Errors
    Assert-ExactString $Contract.recovery_contract.full_wipe.already_dead_repeat_return 'forbidden' 'contract.recovery_contract.full_wipe.already_dead_repeat_return' $Errors
    Assert-StrictBoolean $Contract.recovery_contract.full_wipe.cleanup_ack_required $true 'contract.recovery_contract.full_wipe.cleanup_ack_required' $Errors
    $Timeout = @('return_target','eligible_member_state','already_dead_return','cleanup_ack_required')
    Assert-PropertySet $Contract.recovery_contract.timeout $Timeout $Timeout 'contract.recovery_contract.timeout' $Errors
    Assert-ExactString $Contract.recovery_contract.timeout.return_target 'chapter_initial_spawn' 'contract.recovery_contract.timeout.return_target' $Errors
    Assert-ExactString $Contract.recovery_contract.timeout.eligible_member_state 'active' 'contract.recovery_contract.timeout.eligible_member_state' $Errors
    Assert-ExactString $Contract.recovery_contract.timeout.already_dead_return 'forbidden' 'contract.recovery_contract.timeout.already_dead_return' $Errors
    Assert-StrictBoolean $Contract.recovery_contract.timeout.cleanup_ack_required $true 'contract.recovery_contract.timeout.cleanup_ack_required' $Errors
    Assert-Null $Contract.recovery_contract.production_value 'contract.recovery_contract.production_value' $Errors
    Assert-Null $Contract.recovery_contract.candidate_value 'contract.recovery_contract.candidate_value' $Errors

    $Evidence = @('artifact_status','evidence_only','receipt_type','required_completion_receipt_fields','permitted_outcome','forbidden_outcomes','production_value','candidate_value')
    Assert-PropertySet $Contract.evidence_protocol $Evidence $Evidence 'contract.evidence_protocol' $Errors
    Assert-ExactString $Contract.evidence_protocol.artifact_status 'non-production' 'contract.evidence_protocol.artifact_status' $Errors
    Assert-StrictBoolean $Contract.evidence_protocol.evidence_only $true 'contract.evidence_protocol.evidence_only' $Errors
    Assert-ExactString $Contract.evidence_protocol.receipt_type 'authoritative_completion_receipt' 'contract.evidence_protocol.receipt_type' $Errors
    Assert-ExactStringArray $Contract.evidence_protocol.required_completion_receipt_fields $Receipt 'contract.evidence_protocol.required_completion_receipt_fields' $Errors
    Assert-ExactString $Contract.evidence_protocol.permitted_outcome 'write_or_replay_character_progression_key_only' 'contract.evidence_protocol.permitted_outcome' $Errors
    Assert-ExactStringArray $Contract.evidence_protocol.forbidden_outcomes @('grant_reward','grant_currency','grant_item','grant_xp','set_probability','set_pity') 'contract.evidence_protocol.forbidden_outcomes' $Errors
    Assert-Null $Contract.evidence_protocol.production_value 'contract.evidence_protocol.production_value' $Errors
    Assert-Null $Contract.evidence_protocol.candidate_value 'contract.evidence_protocol.candidate_value' $Errors

    $Deferred = @('difu_unit_records','difu_map_contract','y3_object_ids','drop_tables','reward_values','xp_values','currency_values','item_values','probability_values','pity_values')
    Assert-PropertySet $Contract.deferred $Deferred $Deferred 'contract.deferred' $Errors
    foreach ($Name in $Deferred) { Assert-Null $Contract.deferred.$Name "contract.deferred.$Name" $Errors }
    $Forbidden = @('y3_id','y3_ids','reward_exp','reward_official_res_1','reward_value','reward_amount','drop_probability','probability','probability_value','currency_amount','currency_key','item_amount','item_key','pity_threshold','pity_value')
    Assert-ExactStringArray $Contract.forbidden_field_names $Forbidden 'contract.forbidden_field_names' $Errors
    $Validation = @('validator','strict_schema','source_refs_must_resolve','negative_tests_required','production_value','candidate_value')
    Assert-PropertySet $Contract.validation_contract $Validation $Validation 'contract.validation_contract' $Errors
    Assert-ExactString $Contract.validation_contract.validator 'validate-underworld-preflight.ps1' 'contract.validation_contract.validator' $Errors
    Assert-StrictBoolean $Contract.validation_contract.strict_schema $true 'contract.validation_contract.strict_schema' $Errors
    Assert-StrictBoolean $Contract.validation_contract.source_refs_must_resolve $true 'contract.validation_contract.source_refs_must_resolve' $Errors
    Assert-StrictBoolean $Contract.validation_contract.negative_tests_required $true 'contract.validation_contract.negative_tests_required' $Errors
    Assert-Null $Contract.validation_contract.production_value 'contract.validation_contract.production_value' $Errors
    Assert-Null $Contract.validation_contract.candidate_value 'contract.validation_contract.candidate_value' $Errors
    Test-NonProductionBoundary $Contract 'contract' $Forbidden $Errors
}

function Test-DesignSpec {
    param($Design, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Design) { return }
    foreach ($Required in @('version','project','sourceMaterials','worldview','playerExperience','coreLoop','sessionFlow','systems','content','mvp','handoffs','risks','unresolved','acceptanceCriteria')) { if (-not (Test-HasProperty $Design $Required)) { Add-Issue $Errors 'missing_design_spec_field' "design.$Required" 'Missing required normalizer field.' } }
    if ($Design.version -ne 1) { Add-Issue $Errors 'fixed_value_mismatch' 'design.version' 'Expected 1.' }
    if (@((ConvertTo-StringArray $Design.sourceMaterials) | Where-Object { $_ -match 'cross-chapter-interface\.json$' }).Count -ne 1) { Add-Issue $Errors 'missing_contract_reference' 'design.sourceMaterials' 'Design spec must reference cross-chapter-interface.json exactly once.' }
    if ($null -eq $Design.content -or -not (Test-HasProperty $Design.content 'progression') -or @((ConvertTo-StringArray $Design.content.progression) | Where-Object { $_ -match '^DF_PROGRESS_YANLUO_HALL_CLEARED' }).Count -ne 1) { Add-Issue $Errors 'missing_progression_contract_reference' 'design.content.progression' 'Design spec must reference the character progression key.' }
}

function Copy-JsonObject { param($Value) ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json) }

function Invoke-NegativeTests {
    param($Contract, [string]$ProjectRoot)
    $Results = [System.Collections.Generic.List[object]]::new()
    $Cases = @(
        [pscustomobject]@{ name = 'non_null_production_value'; expected_code = 'non_null_nonproduction_value'; mutate = { param($Copy) $Copy.fixed_decisions.difu_team_instance.production_value = 1 } },
        [pscustomobject]@{ name = 'forbidden_y3_id'; expected_code = 'forbidden_production_field'; mutate = { param($Copy) $Copy.fixed_decisions.difu_team_instance | Add-Member -NotePropertyName y3_id -NotePropertyValue 'fake-id' } },
        [pscustomobject]@{ name = 'invalid_source_ref'; expected_code = 'non_relative_source_ref'; mutate = { param($Copy) $Copy.source_refs[0] = '/outside.md:1' } },
        [pscustomobject]@{ name = 'wrong_progression_key'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.fixed_decisions.reverse_tide_unlock.required_progression_key = 'underworld_late' } },
        [pscustomobject]@{ name = 'wrong_left_behavior'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.recovery_contract.member_death.left_behavior = 'revive_and_return' } },
        [pscustomobject]@{ name = 'wrong_cleanup_ack_identity'; expected_code = 'fixed_array_mismatch'; mutate = { param($Copy) $Copy.recovery_contract.cleanup_ack_identity_fields = @('session_epoch','raid_instance_id','cleanup_token') } },
        [pscustomobject]@{ name = 'non_writer_source_drift'; expected_code = 'fixed_array_mismatch'; mutate = { param($Copy) $Copy.progression_contract.non_writer_sources[1] = 'DF_E_YANLUO_HALL' } }
    )
    foreach ($Case in $Cases) {
        $Copy = Copy-JsonObject $Contract; & $Case.mutate $Copy; $CaseErrors = New-IssueList; Test-InterfaceContract $Copy $ProjectRoot $CaseErrors
        $Results.Add([pscustomobject]@{ name = $Case.name; expected_code = $Case.expected_code; passed = (@($CaseErrors | Where-Object { $_.code -eq $Case.expected_code }).Count -gt 0); observed_codes = @($CaseErrors | Select-Object -ExpandProperty code -Unique) }) | Out-Null
    }
    $Results
}

$Errors = New-IssueList
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$Contract = Read-JsonFile $ContractPath $Errors 'contract'
$Design = Read-JsonFile $DesignPath $Errors 'design'
Test-InterfaceContract $Contract $ProjectRoot $Errors
Test-DesignSpec $Design $Errors
foreach ($ForbiddenDirectory in @('implementation\difu')) { if (Test-Path -LiteralPath (Join-Path $ProjectRoot $ForbiddenDirectory)) { Add-Issue $Errors 'out_of_scope_implementation_present' $ForbiddenDirectory 'This preflight package must not create the implementation directory.' } }
$ExternalGrowthConfig = Join-Path $ProjectRoot 'implementation\growth\lua\growth_config.lua'
if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'implementation\growth')) {
    if (-not (Test-Path -LiteralPath $ExternalGrowthConfig)) {
        Add-Issue $Errors 'external_growth_boundary_invalid' 'implementation\growth' 'The external growth fixture must expose its candidate boundary configuration.'
    } else {
        $ExternalGrowthText = Get-Content -Raw -Encoding UTF8 -LiteralPath $ExternalGrowthConfig
        if ($ExternalGrowthText -notmatch "offline_candidate_simulation_not_adopted" -or $ExternalGrowthText -notmatch "runtime_handoff\s*=\s*false") {
            Add-Issue $Errors 'external_growth_boundary_invalid' 'implementation\growth' 'The external growth fixture may exist only as a runtime-closed offline candidate.'
        }
    }
}
$NegativeResults = @()
if (-not $SkipNegativeTests -and $null -ne $Contract) {
    $NegativeResults = Invoke-NegativeTests $Contract $ProjectRoot
    foreach ($Result in $NegativeResults) { if (-not $Result.passed) { Add-Issue $Errors 'negative_test_failed' "negative.$($Result.name)" "Expected negative rejection: $($Result.expected_code)." } }
}
[pscustomobject]@{ ok = $Errors.Count -eq 0; contract = (Split-Path -Leaf $ContractPath); design = (Split-Path -Leaf $DesignPath); errors = $Errors; negative_tests = $NegativeResults } | ConvertTo-Json -Depth 12
if ($Errors.Count -gt 0) { exit 1 }
