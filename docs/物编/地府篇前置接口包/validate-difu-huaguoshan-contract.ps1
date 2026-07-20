param(
    [string]$ContractPath = (Join-Path $PSScriptRoot 'cross-chapter-interface.json'),
    [string]$ManifestPath = '',
    [string]$BindingPath = '',
    [string]$ConfigPath = '',
    [switch]$SkipNegativeTests
)

$ErrorActionPreference = 'Stop'

function New-IssueList { Write-Output -NoEnumerate ([System.Collections.Generic.List[object]]::new()) }

function Add-Issue {
    param([System.Collections.Generic.List[object]]$List, [string]$Code, [string]$Path, [string]$Message)
    $List.Add([pscustomobject]@{ code = $Code; path = $Path; message = $Message }) | Out-Null
}

function Read-JsonFile {
    param([string]$Path, [System.Collections.Generic.List[object]]$Errors, [string]$IssuePath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Issue $Errors 'file_not_found' $IssuePath "File not found: $Path"; return $null }
    try { return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json) }
    catch { Add-Issue $Errors 'invalid_json' $IssuePath $_.Exception.Message; return $null }
}

function Read-TextFile {
    param([string]$Path, [System.Collections.Generic.List[object]]$Errors, [string]$IssuePath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Issue $Errors 'file_not_found' $IssuePath "File not found: $Path"; return '' }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
}

function Assert-ExactString {
    param($Actual, [string]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [string]) -or $Actual -ne $Expected) { Add-Issue $Errors 'fixed_value_mismatch' $Path "Expected '$Expected'." }
}

function Assert-StrictBoolean {
    param($Actual, [bool]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [bool]) -or $Actual -ne $Expected) { Add-Issue $Errors 'strict_boolean_mismatch' $Path "Expected JSON boolean $Expected." }
}

function Assert-ExactArray {
    param($Actual, [string[]]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    $Values = @($Actual | ForEach-Object { [string]$_ })
    if ($Values.Count -ne $Expected.Count) { Add-Issue $Errors 'fixed_array_mismatch' $Path 'Array length does not match the fixed contract.'; return }
    for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
        if ($Values[$Index] -ne $Expected[$Index]) { Add-Issue $Errors 'fixed_array_mismatch' "${Path}[$Index]" "Expected '$($Expected[$Index])'." }
    }
}

function ConvertFrom-UnicodeCodePoints {
    param([int[]]$Points)
    return -join @($Points | ForEach-Object { [char]$_ })
}

function Find-Encounter {
    param($Manifest, [string]$RecordKey)
    $Matches = @($Manifest.encounters | Where-Object { $_.record_key -eq $RecordKey })
    Write-Output -NoEnumerate $Matches
}

function Get-LuaEncounterBlock {
    param([string]$ConfigText, [string]$EncounterKey)
    $Start = $ConfigText.IndexOf("$EncounterKey = {", [StringComparison]::Ordinal)
    if ($Start -lt 0) { return '' }
    $Tail = $ConfigText.Substring($Start)
    $Next = [regex]::Match($Tail.Substring(1), '(?m)^\s{4}HG_E_[A-Z0-9_]+\s*=')
    if ($Next.Success) { return $Tail.Substring(0, $Next.Index + 1) }
    return $Tail
}

function Test-CrossContract {
    param($Contract, $Manifest, $Binding, [string]$ConfigText, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Contract -or $null -eq $Manifest -or $null -eq $Binding) { return }

    Assert-ExactString $Contract.artifact_status 'non-production-interface-contract' 'contract.artifact_status' $Errors
    Assert-ExactString $Contract.production_gate 'closed' 'contract.production_gate' $Errors
    Assert-StrictBoolean $Contract.implementation_handoff $false 'contract.implementation_handoff' $Errors

    $Reverse = $Contract.fixed_decisions.reverse_tide_unlock
    $NormalFinal = $Contract.fixed_decisions.difu_normal_final
    $TeamInstance = $Contract.fixed_decisions.difu_team_instance
    $Progression = $Contract.progression_contract
    $Recovery = $Contract.recovery_contract
    Assert-ExactString $Reverse.consumer_encounter_key 'HG_E_DRAGON_REVERSE_TIDE' 'contract.fixed_decisions.reverse_tide_unlock.consumer_encounter_key' $Errors
    if ($Reverse.minimum_level -ne 38) { Add-Issue $Errors 'fixed_value_mismatch' 'contract.fixed_decisions.reverse_tide_unlock.minimum_level' 'Expected 38.' }
    Assert-ExactString $Reverse.required_progression_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'contract.fixed_decisions.reverse_tide_unlock.required_progression_key' $Errors
    Assert-StrictBoolean $Reverse.trusted_query_required $true 'contract.fixed_decisions.reverse_tide_unlock.trusted_query_required' $Errors
    Assert-ExactString $Reverse.rejected_legacy_progression_key 'underworld_late' 'contract.fixed_decisions.reverse_tide_unlock.rejected_legacy_progression_key' $Errors
    Assert-ExactString $NormalFinal.encounter_key 'DF_E_YANLUO_HALL' 'contract.fixed_decisions.difu_normal_final.encounter_key' $Errors
    Assert-ExactString $NormalFinal.encounter_type 'non_team_normal_final' 'contract.fixed_decisions.difu_normal_final.encounter_type' $Errors
    Assert-ExactString $NormalFinal.status 'fixed-user-decision' 'contract.fixed_decisions.difu_normal_final.status' $Errors
    Assert-ExactString $Progression.producer_encounter_key 'DF_E_YANLUO_HALL' 'contract.progression_contract.producer_encounter_key' $Errors
    Assert-ExactString $TeamInstance.encounter_key 'DF_E_ZHUANLUN_HALL' 'contract.fixed_decisions.difu_team_instance.encounter_key' $Errors
    Assert-ExactString $TeamInstance.encounter_type 'team_instance' 'contract.fixed_decisions.difu_team_instance.encounter_type' $Errors
    Assert-ExactString $TeamInstance.status 'fixed-user-decision' 'contract.fixed_decisions.difu_team_instance.status' $Errors
    Assert-ExactString $Progression.record_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'contract.progression_contract.record_key' $Errors
    Assert-ExactString $Progression.owner_scope 'character' 'contract.progression_contract.owner_scope' $Errors
    Assert-ExactString $Progression.write_authority 'trusted_map_authority' 'contract.progression_contract.write_authority' $Errors
    Assert-ExactString $Progression.write_event 'completion_success' 'contract.progression_contract.write_event' $Errors
    Assert-ExactString $Progression.consumer_encounter_key 'HG_E_DRAGON_REVERSE_TIDE' 'contract.progression_contract.consumer_encounter_key' $Errors
    Assert-ExactArray $Progression.required_receipt_fields @('actor_id','actor_lifecycle_id','event_id','producer_encounter_key','session_instance_id','session_epoch','completed_tick','authority_proof_ref') 'contract.progression_contract.required_receipt_fields' $Errors
    Assert-ExactArray $Progression.idempotency_key_fields @('actor_id','event_id') 'contract.progression_contract.idempotency_key_fields' $Errors
    Assert-ExactString $Progression.write_condition 'same_actor_completed_yanluo_hall_with_authoritative_success_receipt' 'contract.progression_contract.write_condition' $Errors
    $ExpectedNonWriterSources = @(
        'DF_E_ZHUANLUN_HALL',
        (ConvertFrom-UnicodeCodePoints @(0x767D,0x9AA8,0x79D8,0x5883)),
        (ConvertFrom-UnicodeCodePoints @(0x5BA2,0x6237,0x7AEF,0x5E03,0x5C14,0x503C)),
        (ConvertFrom-UnicodeCodePoints @(0x961F,0x4F0D,0x9886,0x961F,0x6216,0x961F,0x53CB,0x8FDB,0x5EA6)),
        (ConvertFrom-UnicodeCodePoints @(0x4E16,0x754C,0x72B6,0x6001))
    )
    Assert-ExactArray $Progression.non_writer_sources $ExpectedNonWriterSources 'contract.progression_contract.non_writer_sources' $Errors
    Assert-ExactString $Recovery.policy_key 'TEAM_INSTANCE_RETURN_TO_CHAPTER_INITIAL_SPAWN_V1' 'contract.recovery_contract.policy_key' $Errors
    Assert-ExactArray $Recovery.applies_to @('team_instance') 'contract.recovery_contract.applies_to' $Errors
    Assert-ExactString $Recovery.initial_spawn_reference 'chapter_initial_spawn' 'contract.recovery_contract.initial_spawn_reference' $Errors
    Assert-StrictBoolean $Recovery.cleanup_ack_required $true 'contract.recovery_contract.cleanup_ack_required' $Errors
    Assert-ExactArray $Recovery.cleanup_ack_identity_fields @('raid_instance_id','session_epoch','cleanup_token') 'contract.recovery_contract.cleanup_ack_identity_fields' $Errors
    Assert-ExactString $Recovery.reentry_before_cleanup_ack 'denied' 'contract.recovery_contract.reentry_before_cleanup_ack' $Errors
    Assert-ExactString $Recovery.member_death.return_target 'chapter_initial_spawn' 'contract.recovery_contract.member_death.return_target' $Errors
    Assert-ExactString $Recovery.member_death.member_status 'dead' 'contract.recovery_contract.member_death.member_status' $Errors
    Assert-StrictBoolean $Recovery.member_death.revive_before_return $true 'contract.recovery_contract.member_death.revive_before_return' $Errors
    Assert-ExactString $Recovery.member_death.left_behavior 'no_revive_no_return' 'contract.recovery_contract.member_death.left_behavior' $Errors
    Assert-ExactString $Recovery.member_death.reentry_lock 'until_matching_cleanup_ack' 'contract.recovery_contract.member_death.reentry_lock' $Errors
    Assert-ExactString $Recovery.member_death.already_dead_repeat_return 'forbidden' 'contract.recovery_contract.member_death.already_dead_repeat_return' $Errors
    Assert-ExactString $Recovery.full_wipe.return_target 'chapter_initial_spawn' 'contract.recovery_contract.full_wipe.return_target' $Errors
    Assert-ExactString $Recovery.full_wipe.already_dead_repeat_return 'forbidden' 'contract.recovery_contract.full_wipe.already_dead_repeat_return' $Errors
    Assert-StrictBoolean $Recovery.full_wipe.cleanup_ack_required $true 'contract.recovery_contract.full_wipe.cleanup_ack_required' $Errors
    Assert-ExactString $Recovery.timeout.return_target 'chapter_initial_spawn' 'contract.recovery_contract.timeout.return_target' $Errors
    Assert-ExactString $Recovery.timeout.eligible_member_state 'active' 'contract.recovery_contract.timeout.eligible_member_state' $Errors
    Assert-ExactString $Recovery.timeout.already_dead_return 'forbidden' 'contract.recovery_contract.timeout.already_dead_return' $Errors
    Assert-StrictBoolean $Recovery.timeout.cleanup_ack_required $true 'contract.recovery_contract.timeout.cleanup_ack_required' $Errors

    $ReverseEncounters = Find-Encounter $Manifest 'HG_E_DRAGON_REVERSE_TIDE'
    if ($ReverseEncounters.Count -ne 1) { Add-Issue $Errors 'encounter_identity_mismatch' 'manifest.encounters' 'Expected exactly one HG_E_DRAGON_REVERSE_TIDE.' }
    else {
        $Encounter = $ReverseEncounters[0]
        Assert-ExactString $Encounter.encounter_type 'solo_boss' 'manifest.HG_E_DRAGON_REVERSE_TIDE.encounter_type' $Errors
        Assert-ExactString $Encounter.combat_scope 'solo_instance' 'manifest.HG_E_DRAGON_REVERSE_TIDE.combat_scope' $Errors
        Assert-ExactString $Encounter.runtime_fields.unlock_rule 'level_at_least_38_and_difu_yanluo_hall_cleared' 'manifest.HG_E_DRAGON_REVERSE_TIDE.runtime_fields.unlock_rule' $Errors
        Assert-ExactString $Encounter.runtime_fields.progression_key $Reverse.required_progression_key 'manifest.HG_E_DRAGON_REVERSE_TIDE.runtime_fields.progression_key' $Errors
    }
    $WrongProgressionConsumers = @($Manifest.encounters | Where-Object { $_.record_key -ne 'HG_E_DRAGON_REVERSE_TIDE' -and $null -ne $_.runtime_fields -and $_.runtime_fields.progression_key -eq $Reverse.required_progression_key })
    if ($WrongProgressionConsumers.Count -gt 0) { Add-Issue $Errors 'unauthorized_progression_consumer' 'manifest.encounters' 'Only Reverse Tide may consume the Difu progression key.' }
    $ManifestJson = $Manifest | ConvertTo-Json -Depth 100
    if ($ManifestJson -match 'DF_E_YANLUO_HALL|DF_E_ZHUANLUN_HALL') { Add-Issue $Errors 'unauthorized_difu_producer_declaration' 'manifest' 'Huaguoshan must not declare a Difu producer encounter.' }

    $OxEncounters = Find-Encounter $Manifest 'HG_E_OX_BATTLEFIELD'
    if ($OxEncounters.Count -ne 1) { Add-Issue $Errors 'encounter_identity_mismatch' 'manifest.encounters' 'Expected exactly one HG_E_OX_BATTLEFIELD.' }
    else {
        $Ox = $OxEncounters[0]
        Assert-ExactString $Ox.combat_scope 'team_instance' 'manifest.HG_E_OX_BATTLEFIELD.combat_scope' $Errors
        foreach ($Field in @('failure_return_point','member_death_return_point','timeout_return_point')) { Assert-ExactString $Ox.runtime_fields.$Field 'pt_hg_spawn' "manifest.HG_E_OX_BATTLEFIELD.runtime_fields.$Field" $Errors }
        Assert-ExactString $Ox.runtime_fields.member_death_reentry_policy 'deny_until_cleanup_ack' 'manifest.HG_E_OX_BATTLEFIELD.runtime_fields.member_death_reentry_policy' $Errors
    }

    Assert-StrictBoolean $Manifest.execution_gates.authoritative_progression_validator_bound $false 'manifest.execution_gates.authoritative_progression_validator_bound' $Errors
    Assert-StrictBoolean $Manifest.runtime_package.authoritative_progression_validator_bound $false 'manifest.runtime_package.authoritative_progression_validator_bound' $Errors
    $SpawnBindings = @($Binding.return_points | Where-Object { $_.role -eq 'spawn' })
    if ($SpawnBindings.Count -ne 1) { Add-Issue $Errors 'spawn_binding_identity_mismatch' 'binding.return_points' 'Expected exactly one spawn binding.' }
    else { Assert-ExactString $SpawnBindings[0].resource_key 'pt_hg_spawn' 'binding.return_points[spawn].resource_key' $Errors }

    $ReverseBlock = Get-LuaEncounterBlock $ConfigText 'HG_E_DRAGON_REVERSE_TIDE'
    if ([string]::IsNullOrWhiteSpace($ReverseBlock)) { Add-Issue $Errors 'lua_encounter_block_missing' 'config.HG_E_DRAGON_REVERSE_TIDE' 'Reverse Tide block is missing.' }
    else {
        if ($ReverseBlock -notmatch "unlock_rule\s*=\s*'level_at_least_38_and_difu_yanluo_hall_cleared'") { Add-Issue $Errors 'lua_contract_drift' 'config.HG_E_DRAGON_REVERSE_TIDE.unlock_rule' 'Reverse Tide unlock rule drifted.' }
        if ($ReverseBlock -notmatch "progression_key\s*=\s*'DF_PROGRESS_YANLUO_HALL_CLEARED'") { Add-Issue $Errors 'lua_contract_drift' 'config.HG_E_DRAGON_REVERSE_TIDE.progression_key' 'Reverse Tide progression key drifted.' }
        if ($ReverseBlock -match 'underworld_late') { Add-Issue $Errors 'legacy_progression_key_forbidden' 'config.HG_E_DRAGON_REVERSE_TIDE' 'Legacy progression key is forbidden.' }
    }
    $OxBlock = Get-LuaEncounterBlock $ConfigText 'HG_E_OX_BATTLEFIELD'
    if ([string]::IsNullOrWhiteSpace($OxBlock)) { Add-Issue $Errors 'lua_encounter_block_missing' 'config.HG_E_OX_BATTLEFIELD' 'Ox Battlefield block is missing.' }
    else {
        if ($OxBlock -notmatch "combat_scope\s*=\s*'team_instance'") { Add-Issue $Errors 'lua_contract_drift' 'config.HG_E_OX_BATTLEFIELD.combat_scope' 'Ox Battlefield team scope drifted.' }
        if ($OxBlock -notmatch "return_point\s*=\s*'pt_hg_spawn'") { Add-Issue $Errors 'lua_contract_drift' 'config.HG_E_OX_BATTLEFIELD.return_point' 'Ox Battlefield return point drifted.' }
        if ($OxBlock -notmatch "reentry_policy\s*=\s*'deny_until_cleanup_ack'") { Add-Issue $Errors 'lua_contract_drift' 'config.HG_E_OX_BATTLEFIELD.reentry_policy' 'Ox Battlefield reentry policy drifted.' }
    }
}

function Copy-JsonObject { param($Value) return ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json) }

function Invoke-NegativeTests {
    param($Contract, $Manifest, $Binding, [string]$ConfigText)
    $Results = [System.Collections.Generic.List[object]]::new()
    $Cases = @(
        [pscustomobject]@{ name = 'reverse_tide_wrong_progression_key'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) (Find-Encounter $M 'HG_E_DRAGON_REVERSE_TIDE')[0].runtime_fields.progression_key = 'underworld_late' } },
        [pscustomobject]@{ name = 'reverse_tide_wrong_unlock_rule'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) (Find-Encounter $M 'HG_E_DRAGON_REVERSE_TIDE')[0].runtime_fields.unlock_rule = 'underworld_late' } },
        [pscustomobject]@{ name = 'reverse_tide_lua_only_drift'; expected_code = 'lua_contract_drift'; mutate = { param($C,$M,$B,[ref]$T) $T.Value = $T.Value.Replace("progression_key = 'DF_PROGRESS_YANLUO_HALL_CLEARED'", "progression_key = 'underworld_late'") } },
        [pscustomobject]@{ name = 'ox_wrong_return_point'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) (Find-Encounter $M 'HG_E_OX_BATTLEFIELD')[0].runtime_fields.timeout_return_point = 'pt_hg_teleport_team' } },
        [pscustomobject]@{ name = 'ox_wrong_reentry_policy'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) (Find-Encounter $M 'HG_E_OX_BATTLEFIELD')[0].runtime_fields.member_death_reentry_policy = 'allow_until_cleanup_ack' } },
        [pscustomobject]@{ name = 'wrong_spawn_binding'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) (@($B.return_points | Where-Object { $_.role -eq 'spawn' })[0]).resource_key = 'pt_hg_teleport_team' } },
        [pscustomobject]@{ name = 'unauthorized_progression_consumer'; expected_code = 'unauthorized_progression_consumer'; mutate = { param($C,$M,$B,[ref]$T) $M.encounters[0].runtime_fields | Add-Member -NotePropertyName progression_key -NotePropertyValue 'DF_PROGRESS_YANLUO_HALL_CLEARED' } },
        [pscustomobject]@{ name = 'opened_production_gate'; expected_code = 'strict_boolean_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $M.execution_gates.authoritative_progression_validator_bound = $true } },
        [pscustomobject]@{ name = 'yanluo_wrong_type'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.fixed_decisions.difu_normal_final.encounter_type = 'team_instance' } },
        [pscustomobject]@{ name = 'progression_record_key_drift'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.progression_contract.record_key = 'DF_PROGRESS_FAKE' } },
        [pscustomobject]@{ name = 'progression_owner_scope_drift'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.progression_contract.owner_scope = 'account' } },
        [pscustomobject]@{ name = 'progression_authority_drift'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.progression_contract.write_authority = 'client' } },
        [pscustomobject]@{ name = 'progression_idempotency_drift'; expected_code = 'fixed_array_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.progression_contract.idempotency_key_fields = @('event_id') } },
        [pscustomobject]@{ name = 'member_death_revive_disabled'; expected_code = 'strict_boolean_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.recovery_contract.member_death.revive_before_return = $false } },
        [pscustomobject]@{ name = 'member_death_status_active'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.recovery_contract.member_death.member_status = 'active' } },
        [pscustomobject]@{ name = 'member_death_repeat_return_allowed'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.recovery_contract.member_death.already_dead_repeat_return = 'allowed' } },
        [pscustomobject]@{ name = 'full_wipe_repeat_return_allowed'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.recovery_contract.full_wipe.already_dead_repeat_return = 'allowed' } },
        [pscustomobject]@{ name = 'timeout_dead_return_allowed'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.recovery_contract.timeout.already_dead_return = 'allowed' } },
        [pscustomobject]@{ name = 'timeout_dead_member_eligible'; expected_code = 'fixed_value_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.recovery_contract.timeout.eligible_member_state = 'dead' } },
        [pscustomobject]@{ name = 'non_writer_source_drift'; expected_code = 'fixed_array_mismatch'; mutate = { param($C,$M,$B,[ref]$T) $C.progression_contract.non_writer_sources[1] = 'DF_E_YANLUO_HALL' } }
    )
    foreach ($Case in $Cases) {
        $CopyContract = Copy-JsonObject $Contract
        $CopyManifest = Copy-JsonObject $Manifest
        $CopyBinding = Copy-JsonObject $Binding
        $CopyText = $ConfigText
        $TextRef = [ref]$CopyText
        & $Case.mutate $CopyContract $CopyManifest $CopyBinding $TextRef
        $CaseErrors = New-IssueList
        Test-CrossContract $CopyContract $CopyManifest $CopyBinding $CopyText $CaseErrors
        $Results.Add([pscustomobject]@{ name = $Case.name; expected_code = $Case.expected_code; passed = (@($CaseErrors | Where-Object { $_.code -eq $Case.expected_code }).Count -gt 0); observed_codes = @($CaseErrors | Select-Object -ExpandProperty code -Unique) }) | Out-Null
    }
    return $Results
}

$Errors = New-IssueList
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$Contract = Read-JsonFile $ContractPath $Errors 'contract'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $ProjectRoot 'implementation\huaguoshan\preconstruction-manifest.json' }
if ([string]::IsNullOrWhiteSpace($BindingPath)) { $BindingPath = Join-Path $ProjectRoot 'implementation\huaguoshan\map-logic-binding.json' }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $ProjectRoot 'implementation\huaguoshan\lua\huaguoshan_config.lua' }
$Manifest = Read-JsonFile $ManifestPath $Errors 'manifest'
$Binding = Read-JsonFile $BindingPath $Errors 'binding'
$ConfigText = Read-TextFile $ConfigPath $Errors 'config'
Test-CrossContract $Contract $Manifest $Binding $ConfigText $Errors
$NegativeResults = @()
if (-not $SkipNegativeTests -and $null -ne $Contract -and $null -ne $Manifest -and $null -ne $Binding) {
    $NegativeResults = Invoke-NegativeTests $Contract $Manifest $Binding $ConfigText
    foreach ($Result in $NegativeResults) {
        if (-not $Result.passed) { Add-Issue $Errors 'negative_test_failed' "negative.$($Result.name)" "Expected negative rejection: $($Result.expected_code)." }
    }
}
[pscustomobject]@{
    ok = $Errors.Count -eq 0
    contract = (Split-Path -Leaf $ContractPath)
    consumer = (Split-Path -Leaf $ManifestPath)
    errors = $Errors
    negative_tests = $NegativeResults
} | ConvertTo-Json -Depth 12
if ($Errors.Count -gt 0) { exit 1 }
