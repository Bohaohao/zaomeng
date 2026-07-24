[CmdletBinding()]
param(
    [string]$ContractPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $PackageRoot 'chapter-entry-contract.json'
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [string]$Code,
        [string]$Path,
        [string]$Message
    )

    $Issues.Add([pscustomobject]@{
        code = $Code
        path = $Path
        message = $Message
    }) | Out-Null
}

function Test-HasProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    return @($Object.PSObject.Properties.Name | Where-Object { $_ -ceq $Name }).Count -eq 1
}

function Get-Field {
    param($Object, [string]$Name)
    if (-not (Test-HasProperty $Object $Name)) { return $null }
    return $Object.PSObject.Properties[$Name].Value
}

function Assert-ObjectKeys {
    param(
        $Object,
        [string[]]$Expected,
        [string]$Path,
        [System.Collections.Generic.List[object]]$Issues
    )

    if ($null -eq $Object -or $Object -isnot [pscustomobject]) {
        Add-Issue $Issues 'schema_object_required' $Path 'Expected an object.'
        return
    }

    $Actual = @($Object.PSObject.Properties.Name)
    foreach ($Name in $Expected) {
        if ($Actual -notcontains $Name) {
            Add-Issue $Issues 'missing_required_field' "$Path.$Name" 'Required field is missing.'
        }
    }
    foreach ($Name in $Actual) {
        if ($Expected -notcontains $Name) {
            Add-Issue $Issues 'unexpected_field' "$Path.$Name" 'Strict contract forbids undeclared fields.'
        }
    }
}

function Assert-ExactString {
    param($Value, [string]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Issues, [string]$Code = 'fixed_value_mismatch')
    if ($Value -isnot [string] -or $Value -cne $Expected) {
        Add-Issue $Issues $Code $Path "Expected '$Expected'."
    }
}

function Assert-ExactBoolean {
    param($Value, [bool]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Issues, [string]$Code = 'fixed_value_mismatch')
    if ($Value -isnot [bool] -or $Value -ne $Expected) {
        Add-Issue $Issues $Code $Path "Expected boolean '$Expected'."
    }
}

function Assert-ExactInteger {
    param($Value, [long]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Issues, [string]$Code = 'fixed_value_mismatch')
    if ($Value -isnot [byte] -and $Value -isnot [int16] -and $Value -isnot [int32] -and $Value -isnot [int64]) {
        Add-Issue $Issues $Code $Path "Expected integer '$Expected'."
        return
    }
    if ([long]$Value -ne $Expected) {
        Add-Issue $Issues $Code $Path "Expected integer '$Expected'."
    }
}

function Assert-Null {
    param($Value, [string]$Path, [System.Collections.Generic.List[object]]$Issues)
    if ($null -ne $Value) {
        Add-Issue $Issues 'non_null_deferred_field' $Path 'This non-production contract requires the field to remain null.'
    }
}

function ConvertTo-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @([string]$Value) }
    return @($Value | ForEach-Object { [string]$_ })
}

function ConvertFrom-Utf8Base64 {
    param([string]$Value)
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function Assert-ExactArray {
    param(
        $Value,
        [string[]]$Expected,
        [string]$Path,
        [System.Collections.Generic.List[object]]$Issues
    )

    $Actual = ConvertTo-StringArray $Value
    if ($Actual.Count -ne $Expected.Count) {
        Add-Issue $Issues 'fixed_array_mismatch' $Path 'Array length differs from the fixed contract.'
        return
    }
    for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
        if ($Actual[$Index] -cne $Expected[$Index]) {
            Add-Issue $Issues 'fixed_array_mismatch' "$Path[$Index]" "Expected '$($Expected[$Index])'."
        }
    }
}

function Assert-SourceRefs {
    param(
        $Value,
        [string[]]$ExpectedRoles,
        [string[]]$ExpectedPaths,
        [string[]]$ExpectedKeys,
        [string]$ProjectRoot,
        [string]$Path,
        [System.Collections.Generic.List[object]]$Issues
    )

    $References = @($Value)
    if ($References.Count -ne $ExpectedRoles.Count) {
        Add-Issue $Issues 'source_ref_count_mismatch' $Path 'Source reference count differs from the fixed contract.'
        return
    }

    $RootFull = [IO.Path]::GetFullPath($ProjectRoot)
    $RootPrefix = $RootFull.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
    for ($Index = 0; $Index -lt $ExpectedRoles.Count; $Index++) {
        $Reference = $References[$Index]
        $ReferencePath = "$Path[$Index]"
        Assert-ObjectKeys $Reference $ExpectedKeys $ReferencePath $Issues
        Assert-ExactString (Get-Field $Reference 'role') $ExpectedRoles[$Index] "$ReferencePath.role" $Issues 'source_ref_role_drift'

        $RelativePath = Get-Field $Reference 'path'
        Assert-ExactString $RelativePath $ExpectedPaths[$Index] "$ReferencePath.path" $Issues 'source_ref_path_drift'
        if ($RelativePath -isnot [string] -or [string]::IsNullOrWhiteSpace($RelativePath)) {
            Add-Issue $Issues 'source_ref_missing' "$ReferencePath.path" 'Source reference path must be a non-empty project-relative file path.'
            continue
        }
        if ([IO.Path]::IsPathRooted($RelativePath)) {
            Add-Issue $Issues 'source_ref_outside_project' "$ReferencePath.path" 'Source reference path must not be rooted.'
            continue
        }

        $Resolved = [IO.Path]::GetFullPath((Join-Path $RootFull $RelativePath))
        if (-not $Resolved.StartsWith($RootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Add-Issue $Issues 'source_ref_outside_project' "$ReferencePath.path" 'Source reference escapes the project root.'
            continue
        }
        if (-not (Test-Path -LiteralPath $Resolved -PathType Leaf)) {
            Add-Issue $Issues 'source_ref_missing' "$ReferencePath.path" 'Source reference does not resolve to an existing project file.'
        }
    }
}

function Assert-AllNullFields {
    param(
        $Object,
        [string[]]$Fields,
        [string]$Path,
        [System.Collections.Generic.List[object]]$Issues
    )

    foreach ($Field in $Fields) {
        Assert-Null (Get-Field $Object $Field) "$Path.$Field" $Issues
    }
}

function Copy-Contract {
    param($Contract)
    return ($Contract | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Validate-Contract {
    param($Contract, [string]$ProjectRoot)

    $Issues = [System.Collections.Generic.List[object]]::new()

    $ContractKeys = @(
        'schema_version', 'package', 'artifact_status', 'status', 'production_gate', 'implementation_handoff',
        'scope', 'source_refs', 'chapter_band', 'semantic_identifiers', 'entry_authorization',
        'logical_result_contract', 'rejection_contract', 'evidence_protocol', 'deferred', 'validation_contract'
    )
    $ScopeKeys = @('includes', 'excludes')
    $ScopeIncludes = @(
        'same_actor_entry_authorization_and_handoff_proof_boundary',
        'spec_local_difu_chapter_entry_write_or_replay_only',
        'entry_gate_separated_from_lv21_to_lv40_growth_band'
    )
    $ScopeExcludes = @(
        'actual_runtime_or_persistent_key_or_save_write',
        'map_coordinate_y3_object_unit_skill_encounter_or_session_implementation',
        'xp_drop_probability_pity_currency_item_reward_economy_receipt_or_value'
    )
    $SourceReferenceKeys = @('role', 'path')
    $SourceReferenceRoles = @('global_baseline', 'worldview_master', 'growth_contract', 'existing_interface_boundary', 'huaguoshan_mainline_producer_contract')
    $SourceReferencePaths = @(
        (ConvertFrom-Utf8Base64 'ZG9jcy/lhajlsYDorr7orqHln7rnur8ubWQ='),
        (ConvertFrom-Utf8Base64 'ZG9jcy8xMC3pobnnm67nu5/kuIDkuJbnlYzop4LmgLvnurIubWQ='),
        (ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYvMTgt5oiQ6ZW/57O757uf6L+b5bqm44CB5o6J6JC95LiO6ZW/5pyf55uu5qCH5aWR57qmLm1k'),
        (ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYv5Zyw5bqc56+H5YmN572u5o6l5Y+j5YyFL2Nyb3NzLWNoYXB0ZXItaW50ZXJmYWNlLmpzb24='),
        (ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYv5Zyw5bqc56+H5YmN572u5o6l5Y+j5YyFL2h1YWd1b3NoYW4tbWFpbmxpbmUtY2xvc3VyZS1wcm9vZi1jb250cmFjdC5qc29u')
    )
    $BandKeys = @('chapter', 'growth_level_range', 'entry_hard_gate')
    $GrowthKeys = @('minimum', 'maximum', 'semantic')
    $EntryGateKeys = @('minimum_authoritative_level', 'level_source', 'client_reported_level_accepted')
    $IdentifierKeys = @(
        'identifier_scope', 'hg_mainline_closure_event', 'difu_chapter_entry_result',
        'semantic_identifier_not_runtime_key', 'actual_runtime_event_key',
        'actual_runtime_progression_key', 'actual_storage_key'
    )
    $IdentifierDeferredFields = @('actual_runtime_event_key', 'actual_runtime_progression_key', 'actual_storage_key')
    $AuthorizationKeys = @(
        'same_actor_required', 'current_request_lifecycle_required', 'current_request_lifecycle_source',
        'minimum_authoritative_level', 'authoritative_level_source', 'required_handoff_proof', 'required_claim_fields'
    )
    $ProofKeys = @(
        'required', 'proof_type', 'issuer_chapter', 'source_event_semantic_id', 'source_event_scope',
        'same_actor_binding', 'source_actor_lifecycle_claim', 'source_actor_lifecycle_equals_current_request', 'authority_proof_required',
        'client_constructible', 'producer_contract_path', 'actual_runtime_proof_key'
    )
    $ClaimFields = @(
        'actor_id', 'actor_lifecycle_id', 'event_id', 'source_event_semantic_id',
        'opaque_handoff_proof_ref', 'completed_tick', 'authority_proof_ref', 'schema_version'
    )
    $ResultKeys = @(
        'result_semantic_id', 'result_scope', 'write_authority', 'idempotency_key_fields',
        'first_accept_outcome', 'exact_replay_outcome', 'replay_current_request_lifecycle_policy',
        'actual_runtime_progression_key', 'actual_storage_key'
    )
    $IdempotencyFields = @('actor_id', 'event_id')
    $ResultDeferredFields = @('actual_runtime_progression_key', 'actual_storage_key')
    $RejectionKeys = @(
        'foreign_actor', 'stale_or_untrusted_current_request_lifecycle', 'missing_or_altered_source_actor_lifecycle_claim',
        'missing_invalid_or_foreign_proof', 'replay_with_invalid_current_lifecycle_or_proof', 'teammate_leader_or_party_result',
        'client_reported_level_proof_or_progress', 'collection_progress_or_checklist',
        'rare_drop_or_rare_completion', 'dragon_palace_encounter_completion', 'ox_demon_team_instance_completion'
    )
    $EvidenceKeys = @('artifact_status', 'evidence_only', 'permitted_outcomes', 'forbidden_outcomes', 'production_value', 'candidate_value')
    $PermittedOutcomes = @('write_spec_local_logical_result_only', 'return_existing_spec_local_logical_result_without_second_write')
    $ForbiddenOutcomes = @('grant_reward', 'grant_currency', 'grant_item', 'grant_xp', 'set_probability', 'set_pity', 'open_map_session', 'write_runtime_key')
    $EvidenceDeferredFields = @('production_value', 'candidate_value')
    $ValidationKeys = @('validator', 'strict_schema', 'source_refs_must_resolve', 'negative_tests_required', 'production_value', 'candidate_value')
    $ValidationDeferredFields = @('production_value', 'candidate_value')

    Assert-ObjectKeys $Contract $ContractKeys 'contract' $Issues

    Assert-ExactInteger (Get-Field $Contract 'schema_version') 1 'contract.schema_version' $Issues
    Assert-ExactString (Get-Field $Contract 'package') 'difu-chapter-entry-contract' 'contract.package' $Issues
    Assert-ExactString (Get-Field $Contract 'artifact_status') 'non-production-interface-contract' 'contract.artifact_status' $Issues
    Assert-ExactString (Get-Field $Contract 'status') 'offline-interface-ready' 'contract.status' $Issues
    Assert-ExactString (Get-Field $Contract 'production_gate') 'closed' 'contract.production_gate' $Issues
    Assert-ExactBoolean (Get-Field $Contract 'implementation_handoff') $false 'contract.implementation_handoff' $Issues

    $Scope = Get-Field $Contract 'scope'
    Assert-ObjectKeys $Scope $ScopeKeys 'contract.scope' $Issues
    Assert-ExactArray (Get-Field $Scope 'includes') $ScopeIncludes 'contract.scope.includes' $Issues
    Assert-ExactArray (Get-Field $Scope 'excludes') $ScopeExcludes 'contract.scope.excludes' $Issues

    Assert-SourceRefs (Get-Field $Contract 'source_refs') $SourceReferenceRoles $SourceReferencePaths $SourceReferenceKeys $ProjectRoot 'contract.source_refs' $Issues

    $Band = Get-Field $Contract 'chapter_band'
    Assert-ObjectKeys $Band $BandKeys 'contract.chapter_band' $Issues
    Assert-ExactString (Get-Field $Band 'chapter') 'difu' 'contract.chapter_band.chapter' $Issues
    $Growth = Get-Field $Band 'growth_level_range'
    Assert-ObjectKeys $Growth $GrowthKeys 'contract.chapter_band.growth_level_range' $Issues
    Assert-ExactInteger (Get-Field $Growth 'minimum') 21 'contract.chapter_band.growth_level_range.minimum' $Issues
    Assert-ExactInteger (Get-Field $Growth 'maximum') 40 'contract.chapter_band.growth_level_range.maximum' $Issues
    Assert-ExactString (Get-Field $Growth 'semantic') 'growth_band_not_entry_hard_gate' 'contract.chapter_band.growth_level_range.semantic' $Issues
    $EntryGate = Get-Field $Band 'entry_hard_gate'
    Assert-ObjectKeys $EntryGate $EntryGateKeys 'contract.chapter_band.entry_hard_gate' $Issues
    Assert-ExactInteger (Get-Field $EntryGate 'minimum_authoritative_level') 20 'contract.chapter_band.entry_hard_gate.minimum_authoritative_level' $Issues 'entry_level_drift'
    Assert-ExactString (Get-Field $EntryGate 'level_source') 'trusted_character_authority' 'contract.chapter_band.entry_hard_gate.level_source' $Issues
    Assert-ExactBoolean (Get-Field $EntryGate 'client_reported_level_accepted') $false 'contract.chapter_band.entry_hard_gate.client_reported_level_accepted' $Issues

    $Identifiers = Get-Field $Contract 'semantic_identifiers'
    Assert-ObjectKeys $Identifiers $IdentifierKeys 'contract.semantic_identifiers' $Issues
    Assert-ExactString (Get-Field $Identifiers 'identifier_scope') 'spec_local_semantic_only' 'contract.semantic_identifiers.identifier_scope' $Issues
    Assert-ExactString (Get-Field $Identifiers 'hg_mainline_closure_event') 'HG_SPEC_MAINLINE_CLOSURE_SUCCESS_V1' 'contract.semantic_identifiers.hg_mainline_closure_event' $Issues
    Assert-ExactString (Get-Field $Identifiers 'difu_chapter_entry_result') 'DF_SPEC_CHAPTER_ENTERED_V1' 'contract.semantic_identifiers.difu_chapter_entry_result' $Issues
    Assert-ExactBoolean (Get-Field $Identifiers 'semantic_identifier_not_runtime_key') $true 'contract.semantic_identifiers.semantic_identifier_not_runtime_key' $Issues
    Assert-AllNullFields $Identifiers $IdentifierDeferredFields 'contract.semantic_identifiers' $Issues

    $Authorization = Get-Field $Contract 'entry_authorization'
    Assert-ObjectKeys $Authorization $AuthorizationKeys 'contract.entry_authorization' $Issues
    Assert-ExactBoolean (Get-Field $Authorization 'same_actor_required') $true 'contract.entry_authorization.same_actor_required' $Issues
    Assert-ExactBoolean (Get-Field $Authorization 'current_request_lifecycle_required') $true 'contract.entry_authorization.current_request_lifecycle_required' $Issues 'current_lifecycle_drift'
    Assert-ExactString (Get-Field $Authorization 'current_request_lifecycle_source') 'trusted_character_authority' 'contract.entry_authorization.current_request_lifecycle_source' $Issues 'current_lifecycle_source_drift'
    Assert-ExactInteger (Get-Field $Authorization 'minimum_authoritative_level') 20 'contract.entry_authorization.minimum_authoritative_level' $Issues 'entry_level_drift'
    Assert-ExactString (Get-Field $Authorization 'authoritative_level_source') 'trusted_character_authority' 'contract.entry_authorization.authoritative_level_source' $Issues
    $Proof = Get-Field $Authorization 'required_handoff_proof'
    Assert-ObjectKeys $Proof $ProofKeys 'contract.entry_authorization.required_handoff_proof' $Issues
    Assert-ExactBoolean (Get-Field $Proof 'required') $true 'contract.entry_authorization.required_handoff_proof.required' $Issues
    Assert-ExactString (Get-Field $Proof 'proof_type') 'opaque_authoritative_handoff_proof' 'contract.entry_authorization.required_handoff_proof.proof_type' $Issues
    Assert-ExactString (Get-Field $Proof 'issuer_chapter') 'huaguoshan' 'contract.entry_authorization.required_handoff_proof.issuer_chapter' $Issues
    Assert-ExactString (Get-Field $Proof 'source_event_semantic_id') 'HG_SPEC_MAINLINE_CLOSURE_SUCCESS_V1' 'contract.entry_authorization.required_handoff_proof.source_event_semantic_id' $Issues
    Assert-ExactString (Get-Field $Proof 'source_event_scope') 'non_team_per_actor_mainline_closure_success' 'contract.entry_authorization.required_handoff_proof.source_event_scope' $Issues 'producer_not_non_team'
    Assert-ExactString (Get-Field $Proof 'same_actor_binding') 'required' 'contract.entry_authorization.required_handoff_proof.same_actor_binding' $Issues 'actor_binding_drift'
    Assert-ExactString (Get-Field $Proof 'source_actor_lifecycle_claim') 'required_immutable_audit_only' 'contract.entry_authorization.required_handoff_proof.source_actor_lifecycle_claim' $Issues 'source_lifecycle_binding_drift'
    Assert-ExactBoolean (Get-Field $Proof 'source_actor_lifecycle_equals_current_request') $false 'contract.entry_authorization.required_handoff_proof.source_actor_lifecycle_equals_current_request' $Issues 'source_lifecycle_equality_drift'
    Assert-ExactBoolean (Get-Field $Proof 'authority_proof_required') $true 'contract.entry_authorization.required_handoff_proof.authority_proof_required' $Issues 'proof_authority_drift'
    Assert-ExactBoolean (Get-Field $Proof 'client_constructible') $false 'contract.entry_authorization.required_handoff_proof.client_constructible' $Issues 'client_proof_drift'
    Assert-ExactString (Get-Field $Proof 'producer_contract_path') (ConvertFrom-Utf8Base64 'ZG9jcy/niannvJYv5Zyw5bqc56+H5YmN572u5o6l5Y+j5YyFL2h1YWd1b3NoYW4tbWFpbmxpbmUtY2xvc3VyZS1wcm9vZi1jb250cmFjdC5qc29u') 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $Issues 'producer_contract_path_drift'
    Assert-Null (Get-Field $Proof 'actual_runtime_proof_key') 'contract.entry_authorization.required_handoff_proof.actual_runtime_proof_key' $Issues
    $ProducerContractPath = Join-Path $ProjectRoot ((Get-Field $Proof 'producer_contract_path') -replace '/', '\')
    if (-not (Test-Path -LiteralPath $ProducerContractPath -PathType Leaf)) {
        Add-Issue $Issues 'producer_contract_missing' 'contract.entry_authorization.required_handoff_proof.producer_contract_path' 'Huaguoshan closure-proof producer contract must resolve.'
    }
    else {
        try {
            $ProducerContract = Get-Content -LiteralPath $ProducerContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-ExactString (Get-Field (Get-Field $ProducerContract 'semantic_identifiers') 'huaguoshan_mainline_closure_event') 'HG_SPEC_MAINLINE_CLOSURE_SUCCESS_V1' 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $Issues 'producer_contract_semantic_drift'
            Assert-ExactBoolean (Get-Field (Get-Field $ProducerContract 'producer_authorization') 'unique_producer') $true 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $Issues 'producer_contract_unique_drift'
            Assert-ExactString (Get-Field (Get-Field $ProducerContract 'producer_authorization') 'proof_scope') 'non_team_per_actor_mainline_closure_success' 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $Issues 'producer_contract_scope_drift'
            Assert-ExactBoolean (Get-Field (Get-Field $ProducerContract 'producer_authorization') 'same_actor_lifecycle_required') $true 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $Issues 'producer_contract_source_lifecycle_drift'
            Assert-ExactString (Get-Field (Get-Field $ProducerContract 'producer_authorization') 'same_actor_lifecycle_scope') 'source_proof_issuance_evidence_only' 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $Issues 'producer_contract_source_lifecycle_scope_drift'
            Assert-ExactString (Get-Field (Get-Field $ProducerContract 'logical_proof_contract') 'actor_lifecycle_claim_semantic') 'immutable_source_lifecycle_audit' 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $Issues 'producer_contract_source_lifecycle_claim_drift'
            Assert-ExactString (Get-Field (Get-Field $ProducerContract 'logical_proof_contract') 'downstream_current_lifecycle_binding') 'source_claim_audit_only_not_equal_to_current_entry_request' 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $Issues 'producer_contract_downstream_lifecycle_drift'
        }
        catch {
            Add-Issue $Issues 'producer_contract_unreadable' 'contract.entry_authorization.required_handoff_proof.producer_contract_path' $_.Exception.Message
        }
    }
    Assert-ExactArray (Get-Field $Authorization 'required_claim_fields') $ClaimFields 'contract.entry_authorization.required_claim_fields' $Issues

    $Result = Get-Field $Contract 'logical_result_contract'
    Assert-ObjectKeys $Result $ResultKeys 'contract.logical_result_contract' $Issues
    Assert-ExactString (Get-Field $Result 'result_semantic_id') 'DF_SPEC_CHAPTER_ENTERED_V1' 'contract.logical_result_contract.result_semantic_id' $Issues
    Assert-ExactString (Get-Field $Result 'result_scope') 'spec_local_logical_only' 'contract.logical_result_contract.result_scope' $Issues
    Assert-ExactString (Get-Field $Result 'write_authority') 'trusted_chapter_authority' 'contract.logical_result_contract.write_authority' $Issues
    Assert-ExactArray (Get-Field $Result 'idempotency_key_fields') $IdempotencyFields 'contract.logical_result_contract.idempotency_key_fields' $Issues
    Assert-ExactString (Get-Field $Result 'first_accept_outcome') 'write_spec_local_logical_result_only' 'contract.logical_result_contract.first_accept_outcome' $Issues
    Assert-ExactString (Get-Field $Result 'exact_replay_outcome') 'return_existing_spec_local_logical_result_without_second_write' 'contract.logical_result_contract.exact_replay_outcome' $Issues 'replay_policy_drift'
    Assert-ExactString (Get-Field $Result 'replay_current_request_lifecycle_policy') 'allow_after_trusted_current_lifecycle_revalidation' 'contract.logical_result_contract.replay_current_request_lifecycle_policy' $Issues 'replay_current_lifecycle_policy_drift'
    Assert-AllNullFields $Result $ResultDeferredFields 'contract.logical_result_contract' $Issues

    $Rejection = Get-Field $Contract 'rejection_contract'
    Assert-ObjectKeys $Rejection $RejectionKeys 'contract.rejection_contract' $Issues
    foreach ($Field in @(
        'foreign_actor',
        'stale_or_untrusted_current_request_lifecycle',
        'missing_or_altered_source_actor_lifecycle_claim',
        'missing_invalid_or_foreign_proof',
        'replay_with_invalid_current_lifecycle_or_proof',
        'teammate_leader_or_party_result',
        'client_reported_level_proof_or_progress',
        'collection_progress_or_checklist',
        'rare_drop_or_rare_completion',
        'dragon_palace_encounter_completion',
        'ox_demon_team_instance_completion'
    )) {
        Assert-ExactString (Get-Field $Rejection $Field) 'denied' "contract.rejection_contract.$Field" $Issues 'rejection_boundary_drift'
    }

    $Evidence = Get-Field $Contract 'evidence_protocol'
    Assert-ObjectKeys $Evidence $EvidenceKeys 'contract.evidence_protocol' $Issues
    Assert-ExactString (Get-Field $Evidence 'artifact_status') 'non-production' 'contract.evidence_protocol.artifact_status' $Issues
    Assert-ExactBoolean (Get-Field $Evidence 'evidence_only') $true 'contract.evidence_protocol.evidence_only' $Issues
    Assert-ExactArray (Get-Field $Evidence 'permitted_outcomes') $PermittedOutcomes 'contract.evidence_protocol.permitted_outcomes' $Issues
    Assert-ExactArray (Get-Field $Evidence 'forbidden_outcomes') $ForbiddenOutcomes 'contract.evidence_protocol.forbidden_outcomes' $Issues
    Assert-AllNullFields $Evidence $EvidenceDeferredFields 'contract.evidence_protocol' $Issues

    $Deferred = Get-Field $Contract 'deferred'
    $DeferredFields = @(
        'runtime_event_key',
        'runtime_progression_key',
        'persistent_storage_key',
        'map_key',
        'map_id',
        'map_coordinates',
        'y3_object_ids',
        'reward_values',
        'xp_values',
        'currency_values',
        'item_values',
        'drop_tables',
        'probability_values',
        'pity_values',
        'economy_receipt'
    )
    Assert-ObjectKeys $Deferred $DeferredFields 'contract.deferred' $Issues
    Assert-AllNullFields $Deferred $DeferredFields 'contract.deferred' $Issues

    $Validation = Get-Field $Contract 'validation_contract'
    Assert-ObjectKeys $Validation $ValidationKeys 'contract.validation_contract' $Issues
    Assert-ExactString (Get-Field $Validation 'validator') 'validate-difu-chapter-entry-contract.ps1' 'contract.validation_contract.validator' $Issues
    Assert-ExactBoolean (Get-Field $Validation 'strict_schema') $true 'contract.validation_contract.strict_schema' $Issues
    Assert-ExactBoolean (Get-Field $Validation 'source_refs_must_resolve') $true 'contract.validation_contract.source_refs_must_resolve' $Issues
    Assert-ExactBoolean (Get-Field $Validation 'negative_tests_required') $true 'contract.validation_contract.negative_tests_required' $Issues
    Assert-AllNullFields $Validation $ValidationDeferredFields 'contract.validation_contract' $Issues

    return $Issues
}

$ExpectedPath = [IO.Path]::GetFullPath((Join-Path $PackageRoot 'chapter-entry-contract.json'))
$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PackageRoot '..\..\..'))
if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    Write-Error "Cannot resolve project root from package path: $PackageRoot"
    exit 1
}
try {
    $ResolvedPath = (Resolve-Path -LiteralPath $ContractPath -ErrorAction Stop).Path
} catch {
    Write-Error "Cannot resolve chapter entry contract: $ContractPath"
    exit 1
}

if (-not [string]::Equals([IO.Path]::GetFullPath($ResolvedPath), $ExpectedPath, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "ContractPath must resolve to this package's canonical chapter-entry-contract.json."
    exit 1
}

try {
    $Contract = Get-Content -LiteralPath $ResolvedPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "Invalid JSON in chapter entry contract: $($_.Exception.Message)"
    exit 1
}

$Errors = @(Validate-Contract $Contract $ProjectRoot)
if ($Errors.Count -gt 0) {
    $Errors | ForEach-Object { Write-Error "[$($_.code)] $($_.path): $($_.message)" }
    exit 1
}

$NegativeTests = @(
    [pscustomobject]@{ name = 'source_ref_path_drift'; expected_code = 'source_ref_path_drift'; mutate = { param($Copy) $Copy.source_refs[0].path = 'docs/README.md' } },
    [pscustomobject]@{ name = 'source_ref_missing'; expected_code = 'source_ref_missing'; mutate = { param($Copy) $Copy.source_refs[0].path = 'docs/not-a-real-source.md' } },
    [pscustomobject]@{ name = 'source_ref_escapes_project'; expected_code = 'source_ref_outside_project'; mutate = { param($Copy) $Copy.source_refs[0].path = '../../outside.md' } },
    [pscustomobject]@{ name = 'entry_level_drift'; expected_code = 'entry_level_drift'; mutate = { param($Copy) $Copy.entry_authorization.minimum_authoritative_level = 21 } },
    [pscustomobject]@{ name = 'growth_band_as_gate'; expected_code = 'entry_level_drift'; mutate = { param($Copy) $Copy.chapter_band.entry_hard_gate.minimum_authoritative_level = 21 } },
    [pscustomobject]@{ name = 'team_producer'; expected_code = 'producer_not_non_team'; mutate = { param($Copy) $Copy.entry_authorization.required_handoff_proof.source_event_scope = 'team_mainline_closure_success' } },
    [pscustomobject]@{ name = 'foreign_actor_allowed'; expected_code = 'actor_binding_drift'; mutate = { param($Copy) $Copy.entry_authorization.required_handoff_proof.same_actor_binding = 'optional' } },
    [pscustomobject]@{ name = 'current_lifecycle_removed'; expected_code = 'current_lifecycle_drift'; mutate = { param($Copy) $Copy.entry_authorization.current_request_lifecycle_required = $false } },
    [pscustomobject]@{ name = 'current_lifecycle_source_untrusted'; expected_code = 'current_lifecycle_source_drift'; mutate = { param($Copy) $Copy.entry_authorization.current_request_lifecycle_source = 'client' } },
    [pscustomobject]@{ name = 'source_lifecycle_claim_removed'; expected_code = 'source_lifecycle_binding_drift'; mutate = { param($Copy) $Copy.entry_authorization.required_handoff_proof.source_actor_lifecycle_claim = 'optional' } },
    [pscustomobject]@{ name = 'source_lifecycle_equality_forced'; expected_code = 'source_lifecycle_equality_drift'; mutate = { param($Copy) $Copy.entry_authorization.required_handoff_proof.source_actor_lifecycle_equals_current_request = $true } },
    [pscustomobject]@{ name = 'untrusted_proof_allowed'; expected_code = 'proof_authority_drift'; mutate = { param($Copy) $Copy.entry_authorization.required_handoff_proof.authority_proof_required = $false } },
    [pscustomobject]@{ name = 'client_proof_allowed'; expected_code = 'client_proof_drift'; mutate = { param($Copy) $Copy.entry_authorization.required_handoff_proof.client_constructible = $true } },
    [pscustomobject]@{ name = 'producer_contract_path_drift'; expected_code = 'producer_contract_path_drift'; mutate = { param($Copy) $Copy.entry_authorization.required_handoff_proof.producer_contract_path = 'docs/elsewhere.json' } },
    [pscustomobject]@{ name = 'replay_second_write'; expected_code = 'replay_policy_drift'; mutate = { param($Copy) $Copy.logical_result_contract.exact_replay_outcome = 'write_again' } },
    [pscustomobject]@{ name = 'replay_after_relogin_denied'; expected_code = 'replay_current_lifecycle_policy_drift'; mutate = { param($Copy) $Copy.logical_result_contract.replay_current_request_lifecycle_policy = 'deny_after_lifecycle_change' } },
    [pscustomobject]@{ name = 'invalid_current_lifecycle_allowed'; expected_code = 'rejection_boundary_drift'; mutate = { param($Copy) $Copy.rejection_contract.replay_with_invalid_current_lifecycle_or_proof = 'allowed' } },
    [pscustomobject]@{ name = 'teammate_source_allowed'; expected_code = 'rejection_boundary_drift'; mutate = { param($Copy) $Copy.rejection_contract.teammate_leader_or_party_result = 'allowed' } },
    [pscustomobject]@{ name = 'client_source_allowed'; expected_code = 'rejection_boundary_drift'; mutate = { param($Copy) $Copy.rejection_contract.client_reported_level_proof_or_progress = 'allowed' } },
    [pscustomobject]@{ name = 'collection_source_allowed'; expected_code = 'rejection_boundary_drift'; mutate = { param($Copy) $Copy.rejection_contract.collection_progress_or_checklist = 'allowed' } },
    [pscustomobject]@{ name = 'rare_source_allowed'; expected_code = 'rejection_boundary_drift'; mutate = { param($Copy) $Copy.rejection_contract.rare_drop_or_rare_completion = 'allowed' } },
    [pscustomobject]@{ name = 'dragon_source_allowed'; expected_code = 'rejection_boundary_drift'; mutate = { param($Copy) $Copy.rejection_contract.dragon_palace_encounter_completion = 'allowed' } },
    [pscustomobject]@{ name = 'ox_team_source_allowed'; expected_code = 'rejection_boundary_drift'; mutate = { param($Copy) $Copy.rejection_contract.ox_demon_team_instance_completion = 'allowed' } },
    [pscustomobject]@{ name = 'runtime_key_injected'; expected_code = 'non_null_deferred_field'; mutate = { param($Copy) $Copy.deferred.runtime_progression_key = 'DF_RUNTIME_FORBIDDEN' } },
    [pscustomobject]@{ name = 'reward_outcome_injected'; expected_code = 'fixed_array_mismatch'; mutate = { param($Copy) $Copy.evidence_protocol.permitted_outcomes += 'grant_reward' } },
    [pscustomobject]@{ name = 'unexpected_production_field'; expected_code = 'unexpected_field'; mutate = { param($Copy) $Copy.evidence_protocol | Add-Member -NotePropertyName reward_amount -NotePropertyValue 1 } }
)

$NegativeFailures = [System.Collections.Generic.List[object]]::new()
foreach ($Test in $NegativeTests) {
    $Copy = Copy-Contract $Contract
    & $Test.mutate $Copy
    $TestIssues = @(Validate-Contract $Copy $ProjectRoot)
    if (@($TestIssues | Where-Object { $_.code -ceq $Test.expected_code }).Count -eq 0) {
        $NegativeFailures.Add([pscustomobject]@{
            name = $Test.name
            expected_code = $Test.expected_code
            observed_codes = @($TestIssues | ForEach-Object { $_.code }) -join ','
        }) | Out-Null
    }
}

if ($NegativeFailures.Count -gt 0) {
    $NegativeFailures | ForEach-Object { Write-Error "Negative test '$($_.name)' did not produce '$($_.expected_code)' (observed: $($_.observed_codes))." }
    exit 1
}

Write-Output 'PASS chapter-entry-contract.json: strict schema and fixed entry boundary validated.'
Write-Output ("PASS negative tests: {0}/{0}." -f $NegativeTests.Count)
Write-Output 'PASS non-production boundary: runtime keys, maps, rewards, economy and values remain null/deferred.'
