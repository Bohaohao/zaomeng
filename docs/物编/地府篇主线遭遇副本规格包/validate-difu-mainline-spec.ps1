param(
    [string]$ContractPath = (Join-Path $PSScriptRoot 'difu-mainline-encounter-contract.json'),
    [string]$DesignPath = (Join-Path $PSScriptRoot 'design-spec.json'),
    [string]$PreflightContractPath = '',
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
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { [string]$_ })
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
    if ($null -ne $Actual) { Add-Issue $Errors 'non_null_deferred_value' $Path 'This offline design field must remain null.' }
}

function Assert-ExactArray {
    param($Actual, [string[]]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    $Values = Get-StringArray $Actual
    if ($Values.Count -ne $Expected.Count) { Add-Issue $Errors 'fixed_array_mismatch' $Path 'Array length does not match the fixed contract.'; return }
    for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
        if ($Values[$Index] -ne $Expected[$Index]) { Add-Issue $Errors 'fixed_array_mismatch' "${Path}[$Index]" "Expected '$($Expected[$Index])'." }
    }
}

function Read-JsonFile {
    param([string]$Path, [System.Collections.Generic.List[object]]$Errors, [string]$IssuePath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Issue $Errors 'file_not_found' $IssuePath "File not found: $Path"; return $null }
    try { return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json) }
    catch { Add-Issue $Errors 'invalid_json' $IssuePath $_.Exception.Message; return $null }
}

function Test-SourceRef {
    param([string]$SourceRef, [string]$ProjectRoot, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if ([string]::IsNullOrWhiteSpace($SourceRef)) { Add-Issue $Errors 'blank_source_ref' $Path 'Source ref must not be blank.'; return }
    $Match = [regex]::Match($SourceRef, '^(?<relative>[^:]+?)(?::(?<ranges>\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)?)?$')
    if (-not $Match.Success) { Add-Issue $Errors 'invalid_source_ref' $Path 'Source ref must use a project-relative path and optional line range.'; return }
    $Relative = $Match.Groups['relative'].Value
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') { Add-Issue $Errors 'non_relative_source_ref' $Path 'Source ref must remain under the project root.'; return }
    $Candidate = Join-Path $ProjectRoot $Relative
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { Add-Issue $Errors 'source_ref_not_found' $Path "Source file not found: $Relative"; return }
    if ($Match.Groups['ranges'].Value) {
        $LineCount = @(Get-Content -Encoding UTF8 -LiteralPath $Candidate).Count
        foreach ($Range in $Match.Groups['ranges'].Value.Split(',')) {
            $Parts = $Range.Split('-')
            $Start = [int]$Parts[0]
            $End = if ($Parts.Count -eq 2) { [int]$Parts[1] } else { $Start }
            if ($Start -lt 1 -or $End -lt $Start -or $End -gt $LineCount) { Add-Issue $Errors 'source_ref_line_out_of_range' $Path "Source line range $Range exceeds $Relative lines 1-$LineCount." }
        }
    }
}

function Test-ForbiddenFields {
    param($Value, [string]$Path, [string[]]$ForbiddenNames, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return }
    if ($Value -is [System.Array]) {
        foreach ($Item in $Value) { Test-ForbiddenFields $Item "${Path}[]" $ForbiddenNames $Errors }
        return
    }
    foreach ($Property in $Value.PSObject.Properties) {
        $PropertyPath = if ($Path) { "$Path.$($Property.Name)" } else { $Property.Name }
        if ($ForbiddenNames -contains $Property.Name) { Add-Issue $Errors 'forbidden_production_field' $PropertyPath 'This offline design package forbids the field.' }
        Test-ForbiddenFields $Property.Value $PropertyPath $ForbiddenNames $Errors
    }
}

function Find-Node {
    param($Nodes, [string]$SpecId)
    return @($Nodes | Where-Object { $_.spec_id -eq $SpecId })
}

function Test-Contract {
    param($Contract, $Preflight, [string]$ProjectRoot, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Contract) { return }

    $Root = @('schema_version','package','artifact_status','status','production_gate','implementation_handoff','scope','source_refs','contract_sync','semantic_key_policy','chapter','route_graph','content_nodes','side_instance_roles','encounter_theme_catalog','economic_boundary','deferred','forbidden_field_names','validation_contract')
    Assert-PropertySet $Contract $Root $Root 'contract' $Errors
    if ($Contract.schema_version -ne 1) { Add-Issue $Errors 'fixed_value_mismatch' 'contract.schema_version' 'Expected 1.' }
    Assert-ExactString $Contract.package 'difu-mainline-encounter-spec' 'contract.package' $Errors
    Assert-ExactString $Contract.artifact_status 'offline-design-spec' 'contract.artifact_status' $Errors
    Assert-ExactString $Contract.status 'review-ready' 'contract.status' $Errors
    Assert-ExactString $Contract.production_gate 'closed' 'contract.production_gate' $Errors
    Assert-StrictBoolean $Contract.implementation_handoff $false 'contract.implementation_handoff' $Errors

    $ScopeFields = @('includes','excludes')
    Assert-PropertySet $Contract.scope $ScopeFields $ScopeFields 'contract.scope' $Errors
    foreach ($Name in $ScopeFields) { if ((Get-StringArray $Contract.scope.$Name).Count -eq 0) { Add-Issue $Errors 'empty_scope' "contract.scope.$Name" 'Scope array must not be empty.' } }
    $SourceRefs = Get-StringArray $Contract.source_refs
    if ($SourceRefs.Count -eq 0) { Add-Issue $Errors 'empty_source_refs' 'contract.source_refs' 'At least one source ref is required.' }
    for ($Index = 0; $Index -lt $SourceRefs.Count; $Index++) { Test-SourceRef $SourceRefs[$Index] $ProjectRoot "contract.source_refs[$Index]" $Errors }

    $SyncRoot = @('preflight_contract_path','required_values')
    Assert-PropertySet $Contract.contract_sync $SyncRoot $SyncRoot 'contract.contract_sync' $Errors
    if ([string]$Contract.contract_sync.preflight_contract_path -notmatch '(^|[\\/])cross-chapter-interface\.json$') { Add-Issue $Errors 'fixed_value_mismatch' 'contract.contract_sync.preflight_contract_path' 'Expected the canonical cross-chapter interface contract filename.' }
    $RequiredValues = @('yanluo','zhuanlun','reverse_tide')
    Assert-PropertySet $Contract.contract_sync.required_values $RequiredValues $RequiredValues 'contract.contract_sync.required_values' $Errors
    $YanluoFields = @('encounter_key','encounter_type','progression_key','writes_progression')
    Assert-PropertySet $Contract.contract_sync.required_values.yanluo $YanluoFields $YanluoFields 'contract.contract_sync.required_values.yanluo' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.yanluo.encounter_key 'DF_E_YANLUO_HALL' 'contract.contract_sync.required_values.yanluo.encounter_key' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.yanluo.encounter_type 'non_team_normal_final' 'contract.contract_sync.required_values.yanluo.encounter_type' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.yanluo.progression_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'contract.contract_sync.required_values.yanluo.progression_key' $Errors
    Assert-StrictBoolean $Contract.contract_sync.required_values.yanluo.writes_progression $true 'contract.contract_sync.required_values.yanluo.writes_progression' $Errors
    $ZhuanlunFields = @('encounter_key','encounter_type','writes_yanluo_progression','recovery_policy_key')
    Assert-PropertySet $Contract.contract_sync.required_values.zhuanlun $ZhuanlunFields $ZhuanlunFields 'contract.contract_sync.required_values.zhuanlun' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.zhuanlun.encounter_key 'DF_E_ZHUANLUN_HALL' 'contract.contract_sync.required_values.zhuanlun.encounter_key' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.zhuanlun.encounter_type 'team_instance' 'contract.contract_sync.required_values.zhuanlun.encounter_type' $Errors
    Assert-StrictBoolean $Contract.contract_sync.required_values.zhuanlun.writes_yanluo_progression $false 'contract.contract_sync.required_values.zhuanlun.writes_yanluo_progression' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.zhuanlun.recovery_policy_key 'TEAM_INSTANCE_RETURN_TO_CHAPTER_INITIAL_SPAWN_V1' 'contract.contract_sync.required_values.zhuanlun.recovery_policy_key' $Errors
    $ReverseFields = @('consumer_encounter_key','minimum_level','required_progression_key','trusted_query_required')
    Assert-PropertySet $Contract.contract_sync.required_values.reverse_tide $ReverseFields $ReverseFields 'contract.contract_sync.required_values.reverse_tide' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.reverse_tide.consumer_encounter_key 'HG_E_DRAGON_REVERSE_TIDE' 'contract.contract_sync.required_values.reverse_tide.consumer_encounter_key' $Errors
    if ($Contract.contract_sync.required_values.reverse_tide.minimum_level -ne 38) { Add-Issue $Errors 'fixed_value_mismatch' 'contract.contract_sync.required_values.reverse_tide.minimum_level' 'Expected 38.' }
    Assert-ExactString $Contract.contract_sync.required_values.reverse_tide.required_progression_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'contract.contract_sync.required_values.reverse_tide.required_progression_key' $Errors
    Assert-StrictBoolean $Contract.contract_sync.required_values.reverse_tide.trusted_query_required $true 'contract.contract_sync.required_values.reverse_tide.trusted_query_required' $Errors

    $KeyPolicyFields = @('new_runtime_keys','internal_progression_consumers','node_identifiers_are_spec_local_only','side_instance_identifiers_are_spec_local_only','permitted_existing_encounter_keys')
    Assert-PropertySet $Contract.semantic_key_policy $KeyPolicyFields $KeyPolicyFields 'contract.semantic_key_policy' $Errors
    if ((Get-StringArray $Contract.semantic_key_policy.new_runtime_keys).Count -ne 0) { Add-Issue $Errors 'new_runtime_key_forbidden' 'contract.semantic_key_policy.new_runtime_keys' 'No new runtime keys are permitted in this design package.' }
    if ((Get-StringArray $Contract.semantic_key_policy.internal_progression_consumers).Count -ne 0) { Add-Issue $Errors 'internal_progression_consumer_forbidden' 'contract.semantic_key_policy.internal_progression_consumers' 'The Yanluo completion key has no approved internal Difu consumers.' }
    Assert-StrictBoolean $Contract.semantic_key_policy.node_identifiers_are_spec_local_only $true 'contract.semantic_key_policy.node_identifiers_are_spec_local_only' $Errors
    Assert-StrictBoolean $Contract.semantic_key_policy.side_instance_identifiers_are_spec_local_only $true 'contract.semantic_key_policy.side_instance_identifiers_are_spec_local_only' $Errors
    Assert-ExactArray $Contract.semantic_key_policy.permitted_existing_encounter_keys @('DF_E_YANLUO_HALL','DF_E_ZHUANLUN_HALL') 'contract.semantic_key_policy.permitted_existing_encounter_keys' $Errors

    $ChapterFields = @('spec_chapter_id','spec_chapter_id_is_spec_local_only','level_band','central_question','narrative_resolution','initial_spawn')
    Assert-PropertySet $Contract.chapter $ChapterFields $ChapterFields 'contract.chapter' $Errors
    Assert-ExactString $Contract.chapter.spec_chapter_id 'DF_CHAPTER_SPEC' 'contract.chapter.spec_chapter_id' $Errors
    Assert-StrictBoolean $Contract.chapter.spec_chapter_id_is_spec_local_only $true 'contract.chapter.spec_chapter_id_is_spec_local_only' $Errors
    if ($Contract.chapter.level_band.minimum -ne 21 -or $Contract.chapter.level_band.maximum -ne 40) { Add-Issue $Errors 'fixed_value_mismatch' 'contract.chapter.level_band' 'Expected Lv21-40.' }
    $InitialSpawnFields = @('logical_role','real_resource_binding','binding_status')
    Assert-PropertySet $Contract.chapter.initial_spawn $InitialSpawnFields $InitialSpawnFields 'contract.chapter.initial_spawn' $Errors
    Assert-ExactString $Contract.chapter.initial_spawn.logical_role 'chapter_initial_spawn' 'contract.chapter.initial_spawn.logical_role' $Errors
    Assert-Null $Contract.chapter.initial_spawn.real_resource_binding 'contract.chapter.initial_spawn.real_resource_binding' $Errors
    Assert-ExactString $Contract.chapter.initial_spawn.binding_status 'deferred_real_map_readback' 'contract.chapter.initial_spawn.binding_status' $Errors

    $RouteFields = @('representation','reference_sequence','chapter_completion_path','team_content_path')
    Assert-PropertySet $Contract.route_graph $RouteFields $RouteFields 'contract.route_graph' $Errors
    Assert-ExactString $Contract.route_graph.representation 'reference_sequence_and_nonphysical_paths' 'contract.route_graph.representation' $Errors
    $ExpectedReference = @('DF_NODE_GHOST_CITY','DF_NODE_WUCHANG_ALLEY','DF_NODE_GHOST_GATE','DF_NODE_GUIDING_COURT','DF_NODE_JUDGE_HALL','DF_NODE_YANLUO_HALL','DF_NODE_FORGET_RIVER','DF_NODE_NAIHE_BRIDGE','DF_NODE_WANGXIANG_TERRACE','DF_NODE_ZHUANLUN_HALL')
    Assert-ExactArray $Contract.route_graph.reference_sequence $ExpectedReference 'contract.route_graph.reference_sequence' $Errors
    Assert-ExactArray $Contract.route_graph.chapter_completion_path @('DF_NODE_GHOST_CITY','DF_NODE_WUCHANG_ALLEY','DF_NODE_GHOST_GATE','DF_NODE_GUIDING_COURT','DF_NODE_JUDGE_HALL','DF_NODE_YANLUO_HALL') 'contract.route_graph.chapter_completion_path' $Errors
    $TeamPathFields = @('endpoint_status','fixed_endpoint','deferred_route_nodes','reason')
    Assert-PropertySet $Contract.route_graph.team_content_path $TeamPathFields $TeamPathFields 'contract.route_graph.team_content_path' $Errors
    Assert-ExactString $Contract.route_graph.team_content_path.endpoint_status 'fixed' 'contract.route_graph.team_content_path.endpoint_status' $Errors
    Assert-ExactString $Contract.route_graph.team_content_path.fixed_endpoint 'DF_NODE_ZHUANLUN_HALL' 'contract.route_graph.team_content_path.fixed_endpoint' $Errors
    Assert-ExactArray $Contract.route_graph.team_content_path.deferred_route_nodes @('DF_NODE_FORGET_RIVER','DF_NODE_NAIHE_BRIDGE','DF_NODE_WANGXIANG_TERRACE') 'contract.route_graph.team_content_path.deferred_route_nodes' $Errors

    $Nodes = @($Contract.content_nodes)
    if ($Nodes.Count -ne 10) { Add-Issue $Errors 'content_node_count_mismatch' 'contract.content_nodes' 'Expected exactly ten Difu content nodes.' }
    $ExpectedNodes = $ExpectedReference
    foreach ($SpecId in $ExpectedNodes) {
        $Found = @($Nodes | Where-Object { $_.spec_id -eq $SpecId })
        if ($Found.Count -ne 1) { Add-Issue $Errors 'content_node_identity_mismatch' 'contract.content_nodes' "Expected exactly one node '$SpecId'."; continue }
        $Node = $Found[0]
        $NodeFields = @('spec_id','display_name','track','content_kind','design_role','encounter_theme_tags','decision_status','source_refs','contract_dependency','unresolved')
        Assert-PropertySet $Node $NodeFields $NodeFields "contract.content_nodes[$SpecId]" $Errors
        if (@('fixed','offline_design','deferred') -notcontains [string]$Node.decision_status) { Add-Issue $Errors 'invalid_decision_status' "contract.content_nodes[$SpecId].decision_status" 'Expected fixed, offline_design, or deferred.' }
        $NodeSourceRefs = @(Get-StringArray $Node.source_refs)
        if ($NodeSourceRefs.Count -eq 0) { Add-Issue $Errors 'empty_node_source_refs' "contract.content_nodes[$SpecId].source_refs" 'Every node requires at least one source ref.' }
        for ($SourceIndex = 0; $SourceIndex -lt $NodeSourceRefs.Count; $SourceIndex++) { Test-SourceRef $NodeSourceRefs[$SourceIndex] $ProjectRoot "contract.content_nodes[$SpecId].source_refs[$SourceIndex]" $Errors }
        if ((Get-StringArray $Node.unresolved).Count -eq 0) { Add-Issue $Errors 'empty_node_unresolved' "contract.content_nodes[$SpecId].unresolved" 'Every node requires explicit unresolved items.' }
    }
    $YanluoNode = (@($Nodes | Where-Object { $_.spec_id -eq 'DF_NODE_YANLUO_HALL' }))[0]
    if ($null -ne $YanluoNode) {
        Assert-ExactString $YanluoNode.content_kind 'non_team_normal_final' 'contract.content_nodes[DF_NODE_YANLUO_HALL].content_kind' $Errors
        Assert-ExactString $YanluoNode.decision_status 'fixed' 'contract.content_nodes[DF_NODE_YANLUO_HALL].decision_status' $Errors
    }
    $ZhuanlunNode = (@($Nodes | Where-Object { $_.spec_id -eq 'DF_NODE_ZHUANLUN_HALL' }))[0]
    if ($null -ne $ZhuanlunNode) {
        Assert-ExactString $ZhuanlunNode.content_kind 'team_instance' 'contract.content_nodes[DF_NODE_ZHUANLUN_HALL].content_kind' $Errors
        Assert-ExactString $ZhuanlunNode.decision_status 'fixed' 'contract.content_nodes[DF_NODE_ZHUANLUN_HALL].decision_status' $Errors
    }

    $SideRoles = @($Contract.side_instance_roles)
    if ($SideRoles.Count -ne 1) { Add-Issue $Errors 'side_instance_role_count_mismatch' 'contract.side_instance_roles' 'Expected exactly one fixed non-route side-instance role.' }
    $BaiguRoles = @($SideRoles | Where-Object { $_.spec_id -eq 'DF_SIDE_BAIGU_SECRET_REALM' })
    if ($BaiguRoles.Count -ne 1) { Add-Issue $Errors 'side_instance_role_identity_mismatch' 'contract.side_instance_roles' 'Expected exactly one DF_SIDE_BAIGU_SECRET_REALM role.' }
    else {
        $Baigu = $BaiguRoles[0]
        $BaiguFields = @('spec_id','spec_id_is_spec_local_only','display_name','content_kind','design_role','decision_status','source_refs','cross_chapter_progression','economic_boundary','unresolved')
        Assert-PropertySet $Baigu $BaiguFields $BaiguFields 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM]' $Errors
        Assert-StrictBoolean $Baigu.spec_id_is_spec_local_only $true 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].spec_id_is_spec_local_only' $Errors
        Assert-ExactString $Baigu.content_kind 'solo_instance' 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].content_kind' $Errors
        Assert-ExactString $Baigu.decision_status 'fixed' 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].decision_status' $Errors
        $BaiguSourceRefs = @(Get-StringArray $Baigu.source_refs)
        if ($BaiguSourceRefs.Count -eq 0) { Add-Issue $Errors 'empty_side_instance_source_refs' 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].source_refs' 'The side-instance role requires at least one source ref.' }
        for ($SourceIndex = 0; $SourceIndex -lt $BaiguSourceRefs.Count; $SourceIndex++) { Test-SourceRef $BaiguSourceRefs[$SourceIndex] $ProjectRoot "contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].source_refs[$SourceIndex]" $Errors }
        $BaiguProgressionFields = @('writes_yanluo_progression','consumes_yanluo_progression')
        Assert-PropertySet $Baigu.cross_chapter_progression $BaiguProgressionFields $BaiguProgressionFields 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].cross_chapter_progression' $Errors
        Assert-StrictBoolean $Baigu.cross_chapter_progression.writes_yanluo_progression $false 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].cross_chapter_progression.writes_yanluo_progression' $Errors
        Assert-StrictBoolean $Baigu.cross_chapter_progression.consumes_yanluo_progression $false 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].cross_chapter_progression.consumes_yanluo_progression' $Errors
        $BaiguEconomyFields = @('production_reward_output','numeric_reward_definition')
        Assert-PropertySet $Baigu.economic_boundary $BaiguEconomyFields $BaiguEconomyFields 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].economic_boundary' $Errors
        Assert-StrictBoolean $Baigu.economic_boundary.production_reward_output $false 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].economic_boundary.production_reward_output' $Errors
        Assert-StrictBoolean $Baigu.economic_boundary.numeric_reward_definition $false 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].economic_boundary.numeric_reward_definition' $Errors
        if ((Get-StringArray $Baigu.unresolved).Count -eq 0) { Add-Issue $Errors 'empty_side_instance_unresolved' 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].unresolved' 'The side-instance role requires explicit unresolved items.' }
    }

    $EconomicFields = @('reward_source_categories','production_economy_output','decision_source','rule')
    Assert-PropertySet $Contract.economic_boundary $EconomicFields $EconomicFields 'contract.economic_boundary' $Errors
    Assert-StrictBoolean $Contract.economic_boundary.production_economy_output $false 'contract.economic_boundary.production_economy_output' $Errors
    if ([string]$Contract.economic_boundary.decision_source -notmatch '(^|[\\/])README\.md$') { Add-Issue $Errors 'fixed_value_mismatch' 'contract.economic_boundary.decision_source' 'Decision source must resolve to its README.' }
    else { Test-SourceRef ([string]$Contract.economic_boundary.decision_source) $ProjectRoot 'contract.economic_boundary.decision_source' $Errors }

    $DeferredFields = @('real_map_root','chapter_initial_spawn_resource','physical_topology','object_records','boss_phase_parameters','instance_entry_prerequisites','reward_tables','persistence_implementation','runtime_implementation','ui_implementation','multiplayer_playtest')
    Assert-PropertySet $Contract.deferred $DeferredFields $DeferredFields 'contract.deferred' $Errors
    foreach ($Name in $DeferredFields) { Assert-Null $Contract.deferred.$Name "contract.deferred.$Name" $Errors }

    $Forbidden = Get-StringArray $Contract.forbidden_field_names
    if ($Forbidden.Count -lt 10) { Add-Issue $Errors 'invalid_forbidden_field_list' 'contract.forbidden_field_names' 'Expected a meaningful forbidden production-field list.' }
    Test-ForbiddenFields $Contract 'contract' $Forbidden $Errors
    $ValidationFields = @('validator','strict_schema','source_refs_must_resolve','negative_tests_required','cross_contract_check')
    Assert-PropertySet $Contract.validation_contract $ValidationFields $ValidationFields 'contract.validation_contract' $Errors
    Assert-ExactString $Contract.validation_contract.validator 'validate-difu-mainline-spec.ps1' 'contract.validation_contract.validator' $Errors
    Assert-StrictBoolean $Contract.validation_contract.strict_schema $true 'contract.validation_contract.strict_schema' $Errors
    Assert-StrictBoolean $Contract.validation_contract.source_refs_must_resolve $true 'contract.validation_contract.source_refs_must_resolve' $Errors
    Assert-StrictBoolean $Contract.validation_contract.negative_tests_required $true 'contract.validation_contract.negative_tests_required' $Errors
    if ([string]$Contract.validation_contract.cross_contract_check -notmatch '(^|[\\/])validate-difu-huaguoshan-contract\.ps1$') { Add-Issue $Errors 'fixed_value_mismatch' 'contract.validation_contract.cross_contract_check' 'Cross-contract check must use the canonical validator filename.' }

    $Raw = $Contract | ConvertTo-Json -Depth 100
    foreach ($Match in [regex]::Matches($Raw, 'DF_E_[A-Z0-9]+(?:_[A-Z0-9]+)*')) {
        if (@('DF_E_YANLUO_HALL','DF_E_ZHUANLUN_HALL') -notcontains $Match.Value) { Add-Issue $Errors 'new_runtime_key_forbidden' 'contract' "Unexpected runtime encounter key '$($Match.Value)'." }
    }
    if ($Raw -match 'underworld_late') { Add-Issue $Errors 'legacy_progression_key_forbidden' 'contract' 'Legacy generalized progression key is forbidden.' }

    if ($null -ne $Preflight) {
        if ($Preflight.fixed_decisions.difu_normal_final.encounter_key -ne $Contract.contract_sync.required_values.yanluo.encounter_key -or $Preflight.fixed_decisions.difu_normal_final.encounter_type -ne $Contract.contract_sync.required_values.yanluo.encounter_type) { Add-Issue $Errors 'preflight_contract_drift' 'contract.contract_sync.required_values.yanluo' 'Yanluo classification drifted from the preflight contract.' }
        if ($Preflight.progression_contract.record_key -ne $Contract.contract_sync.required_values.yanluo.progression_key -or $Preflight.progression_contract.producer_encounter_key -ne $Contract.contract_sync.required_values.yanluo.encounter_key) { Add-Issue $Errors 'preflight_contract_drift' 'contract.contract_sync.required_values.yanluo' 'Yanluo progression producer drifted from the preflight contract.' }
        if ($Preflight.fixed_decisions.difu_team_instance.encounter_key -ne $Contract.contract_sync.required_values.zhuanlun.encounter_key -or $Preflight.fixed_decisions.difu_team_instance.encounter_type -ne $Contract.contract_sync.required_values.zhuanlun.encounter_type) { Add-Issue $Errors 'preflight_contract_drift' 'contract.contract_sync.required_values.zhuanlun' 'Zhuanlun classification drifted from the preflight contract.' }
        if ($Preflight.fixed_decisions.reverse_tide_unlock.minimum_level -ne $Contract.contract_sync.required_values.reverse_tide.minimum_level -or $Preflight.fixed_decisions.reverse_tide_unlock.required_progression_key -ne $Contract.contract_sync.required_values.reverse_tide.required_progression_key) { Add-Issue $Errors 'preflight_contract_drift' 'contract.contract_sync.required_values.reverse_tide' 'Reverse Tide contract drifted from the preflight contract.' }
        Assert-ExactArray $Preflight.recovery_contract.cleanup_ack_identity_fields @('raid_instance_id','session_epoch','cleanup_token') 'preflight.recovery_contract.cleanup_ack_identity_fields' $Errors
    }
}

function Test-DesignSpec {
    param($Design, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Design) { return }
    foreach ($Required in @('version','project','sourceMaterials','worldview','playerExperience','coreLoop','sessionFlow','systems','content','mvp','handoffs','risks','unresolved','acceptanceCriteria')) {
        if (-not (Test-HasProperty $Design $Required)) { Add-Issue $Errors 'missing_design_spec_field' "design.$Required" 'Missing required normalizer field.' }
    }
    if ($Design.version -ne 1) { Add-Issue $Errors 'fixed_value_mismatch' 'design.version' 'Expected 1.' }
    if (@((Get-StringArray $Design.sourceMaterials) | Where-Object { $_ -eq 'difu-mainline-encounter-contract.json' }).Count -ne 1) { Add-Issue $Errors 'missing_contract_reference' 'design.sourceMaterials' 'Design spec must reference the local contract exactly once.' }
    $Progression = Get-StringArray $Design.content.progression
    if (@($Progression | Where-Object { $_ -match '^DF_PROGRESS_YANLUO_HALL_CLEARED' }).Count -ne 1) { Add-Issue $Errors 'missing_progression_contract_reference' 'design.content.progression' 'Design spec must reference the Yanluo completion key exactly once.' }
    if ((Get-StringArray $Design.mvp.mustHave).Count -eq 0 -or (Get-StringArray $Design.acceptanceCriteria).Count -eq 0) { Add-Issue $Errors 'incomplete_design_handoff' 'design' 'MVP and acceptance criteria must be non-empty.' }
}

function Copy-JsonObject { param($Value) return ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json) }

function Invoke-NegativeTests {
    param($Contract, $Preflight, [string]$ProjectRoot)
    $Results = [System.Collections.Generic.List[object]]::new()
    $Cases = @(
        [pscustomobject]@{ name = 'wrong_yanluo_type'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.contract_sync.required_values.yanluo.encounter_type = 'team_instance' } },
        [pscustomobject]@{ name = 'zhuanlun_writes_progression'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.contract_sync.required_values.zhuanlun.writes_yanluo_progression = $true } },
        [pscustomobject]@{ name = 'legacy_progression_key'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.contract_sync.required_values.reverse_tide.required_progression_key = 'underworld_late' } },
        [pscustomobject]@{ name = 'new_runtime_key'; expected_code = 'new_runtime_key_forbidden'; mutate = { param($Copy) $Copy.semantic_key_policy.new_runtime_keys = @('DF_E_FAKE') } },
        [pscustomobject]@{ name = 'internal_progression_consumer'; expected_code = 'internal_progression_consumer_forbidden'; mutate = { param($Copy) $Copy.semantic_key_policy.internal_progression_consumers = @('DF_NODE_FORGET_RIVER') } },
        [pscustomobject]@{ name = 'fake_y3_id'; expected_code = 'forbidden_production_field'; mutate = { param($Copy) $Copy.chapter | Add-Member -NotePropertyName y3_id -NotePropertyValue 'fake-id' } },
        [pscustomobject]@{ name = 'fake_reward_amount'; expected_code = 'forbidden_production_field'; mutate = { param($Copy) $Copy.economic_boundary | Add-Member -NotePropertyName reward_amount -NotePropertyValue 1 } },
        [pscustomobject]@{ name = 'outside_source_ref'; expected_code = 'non_relative_source_ref'; mutate = { param($Copy) $Copy.source_refs[0] = '/outside.md:1' } },
        [pscustomobject]@{ name = 'team_endpoint_downgraded'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.route_graph.team_content_path.endpoint_status = 'deferred' } },
        [pscustomobject]@{ name = 'node_bad_source_ref'; expected_code = 'source_ref_not_found'; mutate = { param($Copy) $Copy.content_nodes[0].source_refs[0] = 'docs/does-not-exist.md:1' } },
        [pscustomobject]@{ name = 'baigu_writes_progression'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.side_instance_roles[0].cross_chapter_progression.writes_yanluo_progression = $true } },
        [pscustomobject]@{ name = 'baigu_numeric_rewards'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.side_instance_roles[0].economic_boundary.numeric_reward_definition = $true } },
        [pscustomobject]@{ name = 'chapter_identifier_not_spec_local'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.chapter.spec_chapter_id_is_spec_local_only = $false } },
        [pscustomobject]@{ name = 'status_downgraded'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.status = 'draft' } }
    )
    foreach ($Case in $Cases) {
        $Copy = Copy-JsonObject $Contract
        & $Case.mutate $Copy
        $CaseErrors = New-IssueList
        Test-Contract $Copy $Preflight $ProjectRoot $CaseErrors
        $Results.Add([pscustomobject]@{ name = $Case.name; expected_code = $Case.expected_code; passed = (@($CaseErrors | Where-Object { $_.code -eq $Case.expected_code }).Count -gt 0); observed_codes = @($CaseErrors | Select-Object -ExpandProperty code -Unique) }) | Out-Null
    }
    return $Results
}

$Errors = New-IssueList
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$Contract = Read-JsonFile $ContractPath $Errors 'contract'
if ([string]::IsNullOrWhiteSpace($PreflightContractPath) -and $null -ne $Contract -and $null -ne $Contract.contract_sync) {
    $PreflightContractPath = Join-Path $ProjectRoot ([string]$Contract.contract_sync.preflight_contract_path)
}
$Preflight = Read-JsonFile $PreflightContractPath $Errors 'preflight'
$Design = Read-JsonFile $DesignPath $Errors 'design'
Test-Contract $Contract $Preflight $ProjectRoot $Errors
Test-DesignSpec $Design $Errors
foreach ($ForbiddenDirectory in @('implementation\difu','implementation\growth')) {
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot $ForbiddenDirectory)) { Add-Issue $Errors 'out_of_scope_implementation_present' $ForbiddenDirectory 'This design package must not create the implementation directory.' }
}
$NegativeResults = @()
if (-not $SkipNegativeTests -and $null -ne $Contract) {
    $NegativeResults = Invoke-NegativeTests $Contract $Preflight $ProjectRoot
    foreach ($Result in $NegativeResults) {
        if (-not $Result.passed) { Add-Issue $Errors 'negative_test_failed' "negative.$($Result.name)" "Expected negative rejection: $($Result.expected_code)." }
    }
}
[pscustomobject]@{
    ok = $Errors.Count -eq 0
    contract = (Split-Path -Leaf $ContractPath)
    design = (Split-Path -Leaf $DesignPath)
    errors = $Errors
    negative_tests = $NegativeResults
} | ConvertTo-Json -Depth 12
if ($Errors.Count -gt 0) { exit 1 }
