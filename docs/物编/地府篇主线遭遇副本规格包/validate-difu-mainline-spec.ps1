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

function Assert-StrictExactStringArray {
    param($Actual, [string[]]$Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [System.Array])) {
        Add-Issue $Errors 'strict_array_required' $Path 'Expected a JSON array of strings.'
        return
    }
    if ($Actual.Count -ne $Expected.Count) {
        Add-Issue $Errors 'fixed_array_mismatch' $Path 'Array length does not match the fixed contract.'
        return
    }
    for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
        if (-not ($Actual[$Index] -is [string]) -or $Actual[$Index] -ne $Expected[$Index]) {
            Add-Issue $Errors 'fixed_array_mismatch' "${Path}[$Index]" "Expected '$($Expected[$Index])'."
        }
    }
}

function Assert-NonBlankString {
    param($Actual, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [string]) -or [string]::IsNullOrWhiteSpace($Actual)) {
        Add-Issue $Errors 'blank_required_string' $Path 'Expected a non-blank string.'
    }
}

function Assert-MirroredString {
    param($Actual, $Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [string]) -or -not ($Expected -is [string]) -or $Actual -ne $Expected) {
        Add-Issue $Errors 'preflight_contract_drift' $Path 'Value must exactly mirror the canonical preflight recovery contract.'
    }
}

function Assert-MirroredBoolean {
    param($Actual, $Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [bool]) -or -not ($Expected -is [bool]) -or $Actual -ne $Expected) {
        Add-Issue $Errors 'preflight_contract_drift' $Path 'Boolean must exactly mirror the canonical preflight recovery contract.'
    }
}

function Assert-MirroredStringArray {
    param($Actual, $Expected, [string]$Path, [System.Collections.Generic.List[object]]$Errors)
    if (-not ($Actual -is [System.Array]) -or -not ($Expected -is [System.Array]) -or $Actual.Count -ne $Expected.Count) {
        Add-Issue $Errors 'preflight_contract_drift' $Path 'String array must exactly mirror the canonical preflight recovery contract.'
        return
    }
    for ($Index = 0; $Index -lt $Expected.Count; $Index++) {
        if (-not ($Actual[$Index] -is [string]) -or -not ($Expected[$Index] -is [string]) -or $Actual[$Index] -ne $Expected[$Index]) {
            Add-Issue $Errors 'preflight_contract_drift' "${Path}[$Index]" 'String array must exactly mirror the canonical preflight recovery contract.'
        }
    }
}

function Read-JsonFile {
    param([string]$Path, [System.Collections.Generic.List[object]]$Errors, [string]$IssuePath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Issue $Errors 'file_not_found' $IssuePath "File not found: $Path"; return $null }
    try { return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json) }
    catch { Add-Issue $Errors 'invalid_json' $IssuePath $_.Exception.Message; return $null }
}

function Assert-HandoffArray {
    param($Document, [string]$PropertyPath, [string]$IssueRoot, [System.Collections.Generic.List[object]]$Errors)
    $Current = $Document
    foreach ($Segment in $PropertyPath.Split('.')) {
        if (-not (Test-HasProperty $Current $Segment)) {
            Add-Issue $Errors 'missing_handoff_field' "$IssueRoot.$PropertyPath" 'Required handoff field is missing.'
            return
        }
        $Current = $Current.$Segment
    }
    if (-not ($Current -is [System.Array])) {
        Add-Issue $Errors 'handoff_array_required' "$IssueRoot.$PropertyPath" 'Handoff collection fields must remain JSON arrays; object, string, and null shapes are not allowed.'
    }
}

function Assert-HandoffObject {
    param($Document, [string]$PropertyName, [string]$IssueRoot, [System.Collections.Generic.List[object]]$Errors)
    if (-not (Test-HasProperty $Document $PropertyName)) {
        Add-Issue $Errors 'missing_handoff_field' "$IssueRoot.$PropertyName" 'Required handoff field is missing.'
        return
    }
    $Value = $Document.$PropertyName
    if ($null -eq $Value -or $Value -is [System.Array] -or $Value -is [string] -or $Value -is [ValueType]) {
        Add-Issue $Errors 'handoff_object_required' "$IssueRoot.$PropertyName" 'Handoff container must remain a JSON object.'
    }
}

function Test-HandoffDocument {
    param([string]$Name, $Document, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Document) { return }
    $IssueRoot = "handoff.$Name"
    switch ($Name) {
        'object-config-brief.json' {
            Assert-ExactString $Document.targetSkill 'y3-object-config' "$IssueRoot.targetSkill" $Errors
            Assert-HandoffObject $Document 'assetRequests' $IssueRoot $Errors
            foreach ($Path in @('unresolved')) {
                Assert-HandoffArray $Document $Path $IssueRoot $Errors
            }
        }
        'terrain-layout-brief.json' {
            Assert-ExactString $Document.targetSkill 'y3-terrain-layout' "$IssueRoot.targetSkill" $Errors
            Assert-HandoffObject $Document 'worldview' $IssueRoot $Errors
            foreach ($Path in @('worldview.hardRules','worldview.factions','worldview.visualKeywords','sessionFlow','unresolved')) {
                Assert-HandoffArray $Document $Path $IssueRoot $Errors
            }
            if ($Document.sessionFlow -is [System.Array]) {
                for ($Index = 0; $Index -lt $Document.sessionFlow.Count; $Index++) {
                    Assert-HandoffArray $Document.sessionFlow[$Index] 'systemsUsed' "$IssueRoot.sessionFlow[$Index]" $Errors
                }
            }
        }
        default {
            Add-Issue $Errors 'unexpected_handoff_json' $IssueRoot 'This package has no shape contract for the handoff JSON file.'
        }
    }
}

function Test-HandoffJsons {
    param([string]$HandoffDirectory, [System.Collections.Generic.List[object]]$Errors)
    if (-not (Test-Path -LiteralPath $HandoffDirectory -PathType Container)) {
        Add-Issue $Errors 'handoff_directory_not_found' 'handoff' "Handoff directory not found: $HandoffDirectory"
        return
    }
    $ExpectedNames = @('object-config-brief.json','terrain-layout-brief.json')
    $Files = @(Get-ChildItem -LiteralPath $HandoffDirectory -File -Filter *.json)
    foreach ($ExpectedName in $ExpectedNames) {
        $Matches = @($Files | Where-Object { $_.Name -eq $ExpectedName })
        if ($Matches.Count -ne 1) {
            Add-Issue $Errors 'handoff_file_identity_mismatch' 'handoff' "Expected exactly one '$ExpectedName'."
        }
    }
    foreach ($File in $Files) {
        $Document = Read-JsonFile $File.FullName $Errors "handoff.$($File.Name)"
        if ($ExpectedNames -contains $File.Name) {
            Test-HandoffDocument $File.Name $Document $Errors
        } else {
            Add-Issue $Errors 'unexpected_handoff_json' "handoff.$($File.Name)" 'Unexpected handoff JSON file requires an explicit shape contract.'
        }
    }
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

function Test-TeamRecoveryContract {
    param($Mirror, $PreflightRecovery, [System.Collections.Generic.List[object]]$Errors)

    $Path = 'contract.contract_sync.required_values.zhuanlun.team_recovery_contract'
    $RootFields = @('policy_key','applies_to','initial_spawn_reference','cleanup_ack_required','cleanup_ack_identity_fields','reentry_before_cleanup_ack','member_death','full_wipe','timeout')
    Assert-PropertySet $Mirror $RootFields $RootFields $Path $Errors
    Assert-ExactString $Mirror.policy_key 'TEAM_INSTANCE_RETURN_TO_CHAPTER_INITIAL_SPAWN_V1' "$Path.policy_key" $Errors
    Assert-StrictExactStringArray $Mirror.applies_to @('team_instance') "$Path.applies_to" $Errors
    Assert-ExactString $Mirror.initial_spawn_reference 'chapter_initial_spawn' "$Path.initial_spawn_reference" $Errors
    Assert-StrictBoolean $Mirror.cleanup_ack_required $true "$Path.cleanup_ack_required" $Errors
    Assert-StrictExactStringArray $Mirror.cleanup_ack_identity_fields @('raid_instance_id','session_epoch','cleanup_token') "$Path.cleanup_ack_identity_fields" $Errors
    Assert-ExactString $Mirror.reentry_before_cleanup_ack 'denied' "$Path.reentry_before_cleanup_ack" $Errors

    $MemberDeathFields = @('return_target','member_status','revive_before_return','left_behavior','reentry_lock','already_dead_repeat_return')
    Assert-PropertySet $Mirror.member_death $MemberDeathFields $MemberDeathFields "$Path.member_death" $Errors
    Assert-ExactString $Mirror.member_death.return_target 'chapter_initial_spawn' "$Path.member_death.return_target" $Errors
    Assert-ExactString $Mirror.member_death.member_status 'dead' "$Path.member_death.member_status" $Errors
    Assert-StrictBoolean $Mirror.member_death.revive_before_return $true "$Path.member_death.revive_before_return" $Errors
    Assert-ExactString $Mirror.member_death.left_behavior 'no_revive_no_return' "$Path.member_death.left_behavior" $Errors
    Assert-ExactString $Mirror.member_death.reentry_lock 'until_matching_cleanup_ack' "$Path.member_death.reentry_lock" $Errors
    Assert-ExactString $Mirror.member_death.already_dead_repeat_return 'forbidden' "$Path.member_death.already_dead_repeat_return" $Errors

    $FullWipeFields = @('return_target','already_dead_repeat_return','cleanup_ack_required')
    Assert-PropertySet $Mirror.full_wipe $FullWipeFields $FullWipeFields "$Path.full_wipe" $Errors
    Assert-ExactString $Mirror.full_wipe.return_target 'chapter_initial_spawn' "$Path.full_wipe.return_target" $Errors
    Assert-ExactString $Mirror.full_wipe.already_dead_repeat_return 'forbidden' "$Path.full_wipe.already_dead_repeat_return" $Errors
    Assert-StrictBoolean $Mirror.full_wipe.cleanup_ack_required $true "$Path.full_wipe.cleanup_ack_required" $Errors

    $TimeoutFields = @('return_target','eligible_member_state','already_dead_return','cleanup_ack_required')
    Assert-PropertySet $Mirror.timeout $TimeoutFields $TimeoutFields "$Path.timeout" $Errors
    Assert-ExactString $Mirror.timeout.return_target 'chapter_initial_spawn' "$Path.timeout.return_target" $Errors
    Assert-ExactString $Mirror.timeout.eligible_member_state 'active' "$Path.timeout.eligible_member_state" $Errors
    Assert-ExactString $Mirror.timeout.already_dead_return 'forbidden' "$Path.timeout.already_dead_return" $Errors
    Assert-StrictBoolean $Mirror.timeout.cleanup_ack_required $true "$Path.timeout.cleanup_ack_required" $Errors

    if ($null -eq $PreflightRecovery) { return }

    $PreflightPath = 'preflight.recovery_contract'
    $PreflightRootFields = @('policy_key','applies_to','initial_spawn_reference','cleanup_ack_required','cleanup_ack_identity_fields','reentry_before_cleanup_ack','member_death','full_wipe','timeout','production_value','candidate_value')
    Assert-PropertySet $PreflightRecovery $PreflightRootFields $PreflightRootFields $PreflightPath $Errors
    Assert-PropertySet $PreflightRecovery.member_death $MemberDeathFields $MemberDeathFields "$PreflightPath.member_death" $Errors
    Assert-PropertySet $PreflightRecovery.full_wipe $FullWipeFields $FullWipeFields "$PreflightPath.full_wipe" $Errors
    Assert-PropertySet $PreflightRecovery.timeout $TimeoutFields $TimeoutFields "$PreflightPath.timeout" $Errors
    Assert-Null $PreflightRecovery.production_value "$PreflightPath.production_value" $Errors
    Assert-Null $PreflightRecovery.candidate_value "$PreflightPath.candidate_value" $Errors

    Assert-MirroredString $Mirror.policy_key $PreflightRecovery.policy_key "$Path.policy_key" $Errors
    Assert-MirroredStringArray $Mirror.applies_to $PreflightRecovery.applies_to "$Path.applies_to" $Errors
    Assert-MirroredString $Mirror.initial_spawn_reference $PreflightRecovery.initial_spawn_reference "$Path.initial_spawn_reference" $Errors
    Assert-MirroredBoolean $Mirror.cleanup_ack_required $PreflightRecovery.cleanup_ack_required "$Path.cleanup_ack_required" $Errors
    Assert-MirroredStringArray $Mirror.cleanup_ack_identity_fields $PreflightRecovery.cleanup_ack_identity_fields "$Path.cleanup_ack_identity_fields" $Errors
    Assert-MirroredString $Mirror.reentry_before_cleanup_ack $PreflightRecovery.reentry_before_cleanup_ack "$Path.reentry_before_cleanup_ack" $Errors

    foreach ($Name in $MemberDeathFields) {
        $MirrorValue = $Mirror.member_death.$Name
        $PreflightValue = $PreflightRecovery.member_death.$Name
        if ($MirrorValue -is [bool] -or $PreflightValue -is [bool]) {
            Assert-MirroredBoolean $MirrorValue $PreflightValue "$Path.member_death.$Name" $Errors
        } else {
            Assert-MirroredString $MirrorValue $PreflightValue "$Path.member_death.$Name" $Errors
        }
    }
    foreach ($Name in $FullWipeFields) {
        $MirrorValue = $Mirror.full_wipe.$Name
        $PreflightValue = $PreflightRecovery.full_wipe.$Name
        if ($MirrorValue -is [bool] -or $PreflightValue -is [bool]) {
            Assert-MirroredBoolean $MirrorValue $PreflightValue "$Path.full_wipe.$Name" $Errors
        } else {
            Assert-MirroredString $MirrorValue $PreflightValue "$Path.full_wipe.$Name" $Errors
        }
    }
    foreach ($Name in $TimeoutFields) {
        $MirrorValue = $Mirror.timeout.$Name
        $PreflightValue = $PreflightRecovery.timeout.$Name
        if ($MirrorValue -is [bool] -or $PreflightValue -is [bool]) {
            Assert-MirroredBoolean $MirrorValue $PreflightValue "$Path.timeout.$Name" $Errors
        } else {
            Assert-MirroredString $MirrorValue $PreflightValue "$Path.timeout.$Name" $Errors
        }
    }
}

function Test-EncounterThemeCatalog {
    param($Catalog, [string[]]$ValidNodeIds, [System.Collections.Generic.List[object]]$Errors)

    $ExpectedThemes = @(
        [pscustomobject]@{ spec_id = 'DF_THEME_ENTRY_ORDER_FAILURE'; applies_to = @('DF_NODE_GHOST_CITY','DF_NODE_WUCHANG_ALLEY') },
        [pscustomobject]@{ spec_id = 'DF_THEME_DUAL_TARGET'; applies_to = @('DF_NODE_WUCHANG_ALLEY') },
        [pscustomobject]@{ spec_id = 'DF_THEME_GATE_PRESSURE'; applies_to = @('DF_NODE_GHOST_GATE') },
        [pscustomobject]@{ spec_id = 'DF_THEME_JUDGMENT'; applies_to = @('DF_NODE_GUIDING_COURT','DF_NODE_JUDGE_HALL','DF_NODE_YANLUO_HALL') },
        [pscustomobject]@{ spec_id = 'DF_THEME_RIVER_AND_BRIDGE'; applies_to = @('DF_NODE_FORGET_RIVER','DF_NODE_NAIHE_BRIDGE') },
        [pscustomobject]@{ spec_id = 'DF_THEME_MEMORY_AND_REBIRTH'; applies_to = @('DF_NODE_WANGXIANG_TERRACE','DF_NODE_ZHUANLUN_HALL') }
    )
    $Themes = @($Catalog)
    if ($Themes.Count -ne $ExpectedThemes.Count) {
        Add-Issue $Errors 'encounter_theme_catalog_count_mismatch' 'contract.encounter_theme_catalog' "Expected exactly $($ExpectedThemes.Count) theme catalog entries."
    }

    $ThemeFields = @('spec_id','applies_to','design_only','intent')
    $ReservedFields = @('runtime_key','progression_key','production_reward_output')
    foreach ($ExpectedTheme in $ExpectedThemes) {
        $Matches = @($Themes | Where-Object { $_.spec_id -eq $ExpectedTheme.spec_id })
        if ($Matches.Count -ne 1) {
            Add-Issue $Errors 'encounter_theme_identity_mismatch' 'contract.encounter_theme_catalog' "Expected exactly one theme '$($ExpectedTheme.spec_id)'."
            continue
        }
        $Theme = $Matches[0]
        $ThemePath = "contract.encounter_theme_catalog[$($ExpectedTheme.spec_id)]"
        Assert-PropertySet $Theme $ThemeFields $ThemeFields $ThemePath $Errors
        foreach ($ReservedField in $ReservedFields) {
            if (Test-HasProperty $Theme $ReservedField) {
                Add-Issue $Errors 'forbidden_theme_catalog_field' "$ThemePath.$ReservedField" 'Theme catalog entries must not carry runtime, progression, or production-economy fields.'
            }
        }
        Assert-ExactString $Theme.spec_id $ExpectedTheme.spec_id "$ThemePath.spec_id" $Errors
        Assert-StrictExactStringArray $Theme.applies_to $ExpectedTheme.applies_to "$ThemePath.applies_to" $Errors
        Assert-StrictBoolean $Theme.design_only $true "$ThemePath.design_only" $Errors
        Assert-NonBlankString $Theme.intent "$ThemePath.intent" $Errors
        foreach ($NodeId in @($Theme.applies_to)) {
            if (-not ($NodeId -is [string]) -or $ValidNodeIds -notcontains $NodeId) {
                Add-Issue $Errors 'unknown_theme_catalog_node' "$ThemePath.applies_to" "Theme references an unknown content node '$NodeId'."
            }
        }
    }
    foreach ($Theme in $Themes) {
        if (-not (Test-HasProperty $Theme 'spec_id') -or $ExpectedThemes.spec_id -notcontains [string]$Theme.spec_id) {
            Add-Issue $Errors 'encounter_theme_identity_mismatch' 'contract.encounter_theme_catalog' 'Theme catalog contains an unknown entry.'
        }
    }
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
    $PreflightDirectoryName = ([string][char]0x5730) + ([string][char]0x5E9C) + ([string][char]0x7BC7) + ([string][char]0x524D) + ([string][char]0x7F6E) + ([string][char]0x63A5) + ([string][char]0x53E3) + ([string][char]0x5305)
    $CanonicalPreflightPath = Join-Path (Split-Path -Parent $PSScriptRoot) (Join-Path $PreflightDirectoryName 'cross-chapter-interface.json')
    $CanonicalPreflightRelativePath = $CanonicalPreflightPath.Substring($ProjectRoot.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
    Assert-ExactString $Contract.contract_sync.preflight_contract_path $CanonicalPreflightRelativePath 'contract.contract_sync.preflight_contract_path' $Errors
    $RequiredValues = @('yanluo','zhuanlun','reverse_tide')
    Assert-PropertySet $Contract.contract_sync.required_values $RequiredValues $RequiredValues 'contract.contract_sync.required_values' $Errors
    $YanluoFields = @('encounter_key','encounter_type','progression_key','writes_progression')
    Assert-PropertySet $Contract.contract_sync.required_values.yanluo $YanluoFields $YanluoFields 'contract.contract_sync.required_values.yanluo' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.yanluo.encounter_key 'DF_E_YANLUO_HALL' 'contract.contract_sync.required_values.yanluo.encounter_key' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.yanluo.encounter_type 'non_team_normal_final' 'contract.contract_sync.required_values.yanluo.encounter_type' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.yanluo.progression_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'contract.contract_sync.required_values.yanluo.progression_key' $Errors
    Assert-StrictBoolean $Contract.contract_sync.required_values.yanluo.writes_progression $true 'contract.contract_sync.required_values.yanluo.writes_progression' $Errors
    $ZhuanlunFields = @('encounter_key','encounter_type','writes_yanluo_progression','recovery_policy_key','team_recovery_contract')
    Assert-PropertySet $Contract.contract_sync.required_values.zhuanlun $ZhuanlunFields $ZhuanlunFields 'contract.contract_sync.required_values.zhuanlun' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.zhuanlun.encounter_key 'DF_E_ZHUANLUN_HALL' 'contract.contract_sync.required_values.zhuanlun.encounter_key' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.zhuanlun.encounter_type 'team_instance' 'contract.contract_sync.required_values.zhuanlun.encounter_type' $Errors
    Assert-StrictBoolean $Contract.contract_sync.required_values.zhuanlun.writes_yanluo_progression $false 'contract.contract_sync.required_values.zhuanlun.writes_yanluo_progression' $Errors
    Assert-ExactString $Contract.contract_sync.required_values.zhuanlun.recovery_policy_key 'TEAM_INSTANCE_RETURN_TO_CHAPTER_INITIAL_SPAWN_V1' 'contract.contract_sync.required_values.zhuanlun.recovery_policy_key' $Errors
    Test-TeamRecoveryContract $Contract.contract_sync.required_values.zhuanlun.team_recovery_contract $Preflight.recovery_contract $Errors
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
        $BaiguFields = @('spec_id','spec_id_is_spec_local_only','display_name','content_kind','design_role','decision_status','source_refs','chapter_relation','cross_chapter_progression','economic_boundary','unresolved')
        Assert-PropertySet $Baigu $BaiguFields $BaiguFields 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM]' $Errors
        Assert-StrictBoolean $Baigu.spec_id_is_spec_local_only $true 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].spec_id_is_spec_local_only' $Errors
        Assert-ExactString $Baigu.content_kind 'solo_instance' 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].content_kind' $Errors
        Assert-ExactString $Baigu.decision_status 'fixed' 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].decision_status' $Errors
        $BaiguSourceRefs = @(Get-StringArray $Baigu.source_refs)
        if ($BaiguSourceRefs.Count -eq 0) { Add-Issue $Errors 'empty_side_instance_source_refs' 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].source_refs' 'The side-instance role requires at least one source ref.' }
        for ($SourceIndex = 0; $SourceIndex -lt $BaiguSourceRefs.Count; $SourceIndex++) { Test-SourceRef $BaiguSourceRefs[$SourceIndex] $ProjectRoot "contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].source_refs[$SourceIndex]" $Errors }
        $BaiguChapterRelationFields = @('relation_to_chapter_completion','included_in_chapter_completion_path','included_in_team_content_path','requires_yanluo_completion')
        Assert-PropertySet $Baigu.chapter_relation $BaiguChapterRelationFields $BaiguChapterRelationFields 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].chapter_relation' $Errors
        Assert-ExactString $Baigu.chapter_relation.relation_to_chapter_completion 'optional_parallel_nonblocking' 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].chapter_relation.relation_to_chapter_completion' $Errors
        Assert-StrictBoolean $Baigu.chapter_relation.included_in_chapter_completion_path $false 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].chapter_relation.included_in_chapter_completion_path' $Errors
        Assert-StrictBoolean $Baigu.chapter_relation.included_in_team_content_path $false 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].chapter_relation.included_in_team_content_path' $Errors
        Assert-StrictBoolean $Baigu.chapter_relation.requires_yanluo_completion $false 'contract.side_instance_roles[DF_SIDE_BAIGU_SECRET_REALM].chapter_relation.requires_yanluo_completion' $Errors
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

    Test-EncounterThemeCatalog $Contract.encounter_theme_catalog $ExpectedNodes $Errors

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

function Test-ParallelContentFlows {
    param($Design, $Contract, [System.Collections.Generic.List[object]]$Errors)

    if (-not (Test-HasProperty $Design 'parallelContentFlows')) {
        Add-Issue $Errors 'missing_design_spec_field' 'design.parallelContentFlows' 'Parallel content flows must be explicitly declared outside the ordered session flow.'
        return
    }
    if (-not ($Design.parallelContentFlows -is [System.Array])) {
        Add-Issue $Errors 'strict_array_required' 'design.parallelContentFlows' 'Parallel content flows must be a JSON array.'
        return
    }

    $Flows = @($Design.parallelContentFlows)
    if ($Flows.Count -ne 2) {
        Add-Issue $Errors 'parallel_content_flow_count_mismatch' 'design.parallelContentFlows' 'Expected exactly the Baigu side flow and the Zhuanlun team flow.'
    }
    $BaiguFlows = @($Flows | Where-Object { $_.flow_id -eq 'DF_FLOW_BAIGU_SECRET_REALM' })
    $ZhuanlunFlows = @($Flows | Where-Object { $_.flow_id -eq 'DF_FLOW_ZHUANLUN_HALL' })
    if ($BaiguFlows.Count -ne 1) { Add-Issue $Errors 'parallel_content_flow_identity_mismatch' 'design.parallelContentFlows' 'Expected exactly one Baigu side-content flow.' }
    if ($ZhuanlunFlows.Count -ne 1) { Add-Issue $Errors 'parallel_content_flow_identity_mismatch' 'design.parallelContentFlows' 'Expected exactly one Zhuanlun team-content flow.' }

    foreach ($Flow in $Flows) {
        if (-not (Test-HasProperty $Flow 'flow_id') -or @('DF_FLOW_BAIGU_SECRET_REALM','DF_FLOW_ZHUANLUN_HALL') -notcontains [string]$Flow.flow_id) {
            Add-Issue $Errors 'parallel_content_flow_identity_mismatch' 'design.parallelContentFlows' 'Parallel content flow references an unsupported contract identity.'
        }
    }

    if ($BaiguFlows.Count -eq 1) {
        $Baigu = $BaiguFlows[0]
        $BaiguPath = 'design.parallelContentFlows[DF_SIDE_BAIGU_SECRET_REALM]'
        $BaiguFields = @('flow_id','contract_spec_id','flow_kind','chapter_relation','blocks_chapter_completion','entry_prerequisites')
        Assert-PropertySet $Baigu $BaiguFields $BaiguFields $BaiguPath $Errors
        Assert-ExactString $Baigu.flow_id 'DF_FLOW_BAIGU_SECRET_REALM' "$BaiguPath.flow_id" $Errors
        Assert-ExactString $Baigu.contract_spec_id 'DF_SIDE_BAIGU_SECRET_REALM' "$BaiguPath.contract_spec_id" $Errors
        $ExpectedRelation = 'optional_parallel_nonblocking'
        if ($null -ne $Contract) {
            $BaiguRole = @($Contract.side_instance_roles | Where-Object { $_.spec_id -eq 'DF_SIDE_BAIGU_SECRET_REALM' })
            if ($BaiguRole.Count -eq 1) { $ExpectedRelation = [string]$BaiguRole[0].chapter_relation.relation_to_chapter_completion }
        }
        Assert-ExactString $Baigu.chapter_relation $ExpectedRelation "$BaiguPath.chapter_relation" $Errors
        Assert-StrictBoolean $Baigu.blocks_chapter_completion $false "$BaiguPath.blocks_chapter_completion" $Errors
        Assert-ExactString $Baigu.flow_kind 'solo_side_instance' "$BaiguPath.flow_kind" $Errors
        Assert-ExactString $Baigu.entry_prerequisites 'deferred' "$BaiguPath.entry_prerequisites" $Errors
    }

    if ($ZhuanlunFlows.Count -eq 1) {
        $Zhuanlun = $ZhuanlunFlows[0]
        $ZhuanlunPath = 'design.parallelContentFlows[DF_NODE_ZHUANLUN_HALL]'
        $ZhuanlunFields = @('flow_id','contract_spec_id','flow_kind','chapter_relation','blocks_chapter_completion','entry_prerequisites')
        Assert-PropertySet $Zhuanlun $ZhuanlunFields $ZhuanlunFields $ZhuanlunPath $Errors
        Assert-ExactString $Zhuanlun.flow_id 'DF_FLOW_ZHUANLUN_HALL' "$ZhuanlunPath.flow_id" $Errors
        Assert-ExactString $Zhuanlun.contract_spec_id 'DF_NODE_ZHUANLUN_HALL' "$ZhuanlunPath.contract_spec_id" $Errors
        Assert-ExactString $Zhuanlun.flow_kind 'team_post_completion' "$ZhuanlunPath.flow_kind" $Errors
        Assert-ExactString $Zhuanlun.chapter_relation 'post_completion_nonblocking' "$ZhuanlunPath.chapter_relation" $Errors
        Assert-ExactString $Zhuanlun.entry_prerequisites 'deferred' "$ZhuanlunPath.entry_prerequisites" $Errors
        Assert-StrictBoolean $Zhuanlun.blocks_chapter_completion $false "$ZhuanlunPath.blocks_chapter_completion" $Errors
    }
}

function Test-DesignSpec {
    param($Design, $Contract, [System.Collections.Generic.List[object]]$Errors)
    if ($null -eq $Design) { return }
    foreach ($Required in @('version','project','sourceMaterials','worldview','playerExperience','coreLoop','sessionFlow','parallelContentFlows','systems','content','mvp','handoffs','risks','unresolved','acceptanceCriteria')) {
        if (-not (Test-HasProperty $Design $Required)) { Add-Issue $Errors 'missing_design_spec_field' "design.$Required" 'Missing required normalizer field.' }
    }
    if ($Design.version -ne 1) { Add-Issue $Errors 'fixed_value_mismatch' 'design.version' 'Expected 1.' }
    if (@((Get-StringArray $Design.sourceMaterials) | Where-Object { $_ -eq 'difu-mainline-encounter-contract.json' }).Count -ne 1) { Add-Issue $Errors 'missing_contract_reference' 'design.sourceMaterials' 'Design spec must reference the local contract exactly once.' }
    $Progression = Get-StringArray $Design.content.progression
    if (@($Progression | Where-Object { $_ -match '^DF_PROGRESS_YANLUO_HALL_CLEARED' }).Count -ne 1) { Add-Issue $Errors 'missing_progression_contract_reference' 'design.content.progression' 'Design spec must reference the Yanluo completion key exactly once.' }
    if ((Get-StringArray $Design.mvp.mustHave).Count -eq 0 -or (Get-StringArray $Design.acceptanceCriteria).Count -eq 0) { Add-Issue $Errors 'incomplete_design_handoff' 'design' 'MVP and acceptance criteria must be non-empty.' }

    if (-not ($Design.sessionFlow -is [System.Array])) {
        Add-Issue $Errors 'strict_array_required' 'design.sessionFlow' 'The normalizer session flow must remain an ordered JSON array.'
    } else {
        $SessionPhases = @($Design.sessionFlow)
        if ($SessionPhases.Count -eq 0) {
            Add-Issue $Errors 'empty_session_flow' 'design.sessionFlow' 'The regular chapter session flow must not be empty.'
        } else {
            $ExpectedSessionRoles = @('chapter_entry','route_escalation','narrative_setup','completion_final')
            if ($SessionPhases.Count -ne $ExpectedSessionRoles.Count) {
                Add-Issue $Errors 'design_session_flow_count_mismatch' 'design.sessionFlow' 'Expected the four fixed regular-chapter beats only.'
            }
            for ($Index = 0; $Index -lt [Math]::Min($SessionPhases.Count, $ExpectedSessionRoles.Count); $Index++) {
                $Phase = $SessionPhases[$Index]
                $PhasePath = "design.sessionFlow[$Index]"
                $PhaseFields = @('phase','duration','playerGoal','systemsUsed','flow_track','flow_role','successCriteria')
                if ($Index -eq ($ExpectedSessionRoles.Count - 1)) { $PhaseFields = @($PhaseFields + @('contract_spec_id')) }
                Assert-PropertySet $Phase $PhaseFields $PhaseFields $PhasePath $Errors
                Assert-NonBlankString $Phase.phase "$PhasePath.phase" $Errors
                Assert-NonBlankString $Phase.duration "$PhasePath.duration" $Errors
                Assert-NonBlankString $Phase.playerGoal "$PhasePath.playerGoal" $Errors
                if (-not ($Phase.systemsUsed -is [System.Array])) { Add-Issue $Errors 'strict_array_required' "$PhasePath.systemsUsed" 'Session phase systemsUsed must be a JSON array.' }
                Assert-ExactString $Phase.flow_track 'chapter_completion' "$PhasePath.flow_track" $Errors
                Assert-ExactString $Phase.flow_role $ExpectedSessionRoles[$Index] "$PhasePath.flow_role" $Errors
                Assert-NonBlankString $Phase.successCriteria "$PhasePath.successCriteria" $Errors
                if ($Index -eq ($ExpectedSessionRoles.Count - 1)) { Assert-ExactString $Phase.contract_spec_id 'DF_NODE_YANLUO_HALL' "$PhasePath.contract_spec_id" $Errors }
            }
            $SessionRaw = $SessionPhases | ConvertTo-Json -Depth 30
            $BaiguPhaseName = ([string][char]0x767D) + ([string][char]0x9AA8) + ([string][char]0x79D8) + ([string][char]0x5883)
            $ZhuanlunPhaseName = ([string][char]0x8F6C) + ([string][char]0x8F6E) + ([string][char]0x6BBF)
            $YanluoPhaseName = ([string][char]0x960E) + ([string][char]0x7F57) + ([string][char]0x6BBF)
            if ($SessionRaw -match 'DF_SIDE_BAIGU_SECRET_REALM|DF_NODE_ZHUANLUN_HALL' -or $SessionRaw.Contains($BaiguPhaseName) -or $SessionRaw.Contains($ZhuanlunPhaseName)) {
                Add-Issue $Errors 'design_session_flow_branch_leak' 'design.sessionFlow' 'Baigu and Zhuanlun must be declared only in parallelContentFlows, not in the ordered regular session flow.'
            }
            $YanluoPhases = @($SessionPhases | Where-Object {
                ([string]$_.contract_spec_id -eq 'DF_NODE_YANLUO_HALL') -or ([string]$_.phase).Contains($YanluoPhaseName)
            })
            if ($YanluoPhases.Count -ne 1) {
                Add-Issue $Errors 'design_session_flow_terminal_mismatch' 'design.sessionFlow' 'The regular chapter session flow must contain exactly one Yanluo final phase.'
            }
            $FinalPhaseRaw = $SessionPhases[$SessionPhases.Count - 1] | ConvertTo-Json -Depth 20
            if ($FinalPhaseRaw -notmatch 'DF_NODE_YANLUO_HALL|DF_E_YANLUO_HALL' -and -not $FinalPhaseRaw.Contains($YanluoPhaseName)) {
                Add-Issue $Errors 'design_session_flow_terminal_mismatch' 'design.sessionFlow' 'The regular chapter session flow must end at Yanluo.'
            }
        }
    }
    Test-ParallelContentFlows $Design $Contract $Errors
}

function Copy-JsonObject { param($Value) return ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json) }

function Invoke-NegativeTests {
    param($Contract, $Design, $Preflight, [string]$ProjectRoot, [string]$HandoffDirectory)
    $Results = [System.Collections.Generic.List[object]]::new()
    $Cases = @(
        [pscustomobject]@{ name = 'wrong_yanluo_type'; subject = 'contract'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.contract_sync.required_values.yanluo.encounter_type = 'team_instance' } },
        [pscustomobject]@{ name = 'zhuanlun_writes_progression'; subject = 'contract'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.contract_sync.required_values.zhuanlun.writes_yanluo_progression = $true } },
        [pscustomobject]@{ name = 'legacy_progression_key'; subject = 'contract'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.contract_sync.required_values.reverse_tide.required_progression_key = 'underworld_late' } },
        [pscustomobject]@{ name = 'new_runtime_key'; subject = 'contract'; expected_code = 'new_runtime_key_forbidden'; mutate = { param($Copy) $Copy.semantic_key_policy.new_runtime_keys = @('DF_E_FAKE') } },
        [pscustomobject]@{ name = 'internal_progression_consumer'; subject = 'contract'; expected_code = 'internal_progression_consumer_forbidden'; mutate = { param($Copy) $Copy.semantic_key_policy.internal_progression_consumers = @('DF_NODE_FORGET_RIVER') } },
        [pscustomobject]@{ name = 'fake_y3_id'; subject = 'contract'; expected_code = 'forbidden_production_field'; mutate = { param($Copy) $Copy.chapter | Add-Member -NotePropertyName y3_id -NotePropertyValue 'fake-id' } },
        [pscustomobject]@{ name = 'fake_reward_amount'; subject = 'contract'; expected_code = 'forbidden_production_field'; mutate = { param($Copy) $Copy.economic_boundary | Add-Member -NotePropertyName reward_amount -NotePropertyValue 1 } },
        [pscustomobject]@{ name = 'outside_source_ref'; subject = 'contract'; expected_code = 'non_relative_source_ref'; mutate = { param($Copy) $Copy.source_refs[0] = '/outside.md:1' } },
        [pscustomobject]@{ name = 'team_endpoint_downgraded'; subject = 'contract'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.route_graph.team_content_path.endpoint_status = 'deferred' } },
        [pscustomobject]@{ name = 'node_bad_source_ref'; subject = 'contract'; expected_code = 'source_ref_not_found'; mutate = { param($Copy) $Copy.content_nodes[0].source_refs[0] = 'docs/does-not-exist.md:1' } },
        [pscustomobject]@{ name = 'baigu_writes_progression'; subject = 'contract'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.side_instance_roles[0].cross_chapter_progression.writes_yanluo_progression = $true } },
        [pscustomobject]@{ name = 'baigu_numeric_rewards'; subject = 'contract'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.side_instance_roles[0].economic_boundary.numeric_reward_definition = $true } },
        [pscustomobject]@{ name = 'chapter_identifier_not_spec_local'; subject = 'contract'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.chapter.spec_chapter_id_is_spec_local_only = $false } },
        [pscustomobject]@{ name = 'status_downgraded'; subject = 'contract'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.status = 'draft' } },
        [pscustomobject]@{ name = 'theme_catalog_runtime_key'; subject = 'contract'; expected_code = 'forbidden_theme_catalog_field'; mutate = { param($Copy) $Copy.encounter_theme_catalog[0] | Add-Member -NotePropertyName runtime_key -NotePropertyValue 'DF_E_FAKE' } },
        [pscustomobject]@{ name = 'theme_catalog_unknown_node'; subject = 'contract'; expected_code = 'unknown_theme_catalog_node'; mutate = { param($Copy) $Copy.encounter_theme_catalog[0].applies_to[0] = 'DF_NODE_NOT_IN_CONTRACT' } },
        [pscustomobject]@{ name = 'theme_catalog_design_only_false'; subject = 'contract'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) $Copy.encounter_theme_catalog[0].design_only = $false } },
        [pscustomobject]@{ name = 'preflight_contract_path_shadow'; subject = 'contract'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.contract_sync.preflight_contract_path = 'docs/other/cross-chapter-interface.json' } },
        [pscustomobject]@{ name = 'team_recovery_left_behavior_drift'; subject = 'contract'; expected_code = 'preflight_contract_drift'; mutate = { param($Copy) $Copy.contract_sync.required_values.zhuanlun.team_recovery_contract.member_death.left_behavior = 'revive_and_return' } },
        [pscustomobject]@{ name = 'team_recovery_cleanup_ack_identity_drift'; subject = 'contract'; expected_code = 'preflight_contract_drift'; mutate = { param($Copy) $Copy.contract_sync.required_values.zhuanlun.team_recovery_contract.cleanup_ack_identity_fields[2] = 'wrong_token' } },
        [pscustomobject]@{ name = 'team_recovery_timeout_drift'; subject = 'contract'; expected_code = 'preflight_contract_drift'; mutate = { param($Copy) $Copy.contract_sync.required_values.zhuanlun.team_recovery_contract.timeout.cleanup_ack_required = $false } },
        [pscustomobject]@{ name = 'design_baigu_blocks_chapter'; subject = 'design'; expected_code = 'strict_boolean_mismatch'; mutate = { param($Copy) (@($Copy.parallelContentFlows | Where-Object { $_.contract_spec_id -eq 'DF_SIDE_BAIGU_SECRET_REALM' })[0]).blocks_chapter_completion = $true } },
        [pscustomobject]@{ name = 'design_baigu_relation_drift'; subject = 'design'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) (@($Copy.parallelContentFlows | Where-Object { $_.contract_spec_id -eq 'DF_SIDE_BAIGU_SECRET_REALM' })[0]).chapter_relation = 'required_before_yanluo' } },
        [pscustomobject]@{ name = 'design_zhuanlun_entry_not_deferred'; subject = 'design'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) (@($Copy.parallelContentFlows | Where-Object { $_.contract_spec_id -eq 'DF_NODE_ZHUANLUN_HALL' })[0]).entry_prerequisites = 'approved' } },
        [pscustomobject]@{ name = 'design_session_flow_non_chapter_track'; subject = 'design'; expected_code = 'fixed_value_mismatch'; mutate = { param($Copy) $Copy.sessionFlow[0].flow_track = 'side_content' } },
        [pscustomobject]@{ name = 'design_branch_leaks_into_session_flow'; subject = 'design'; expected_code = 'design_session_flow_branch_leak'; mutate = { param($Copy) $Copy.sessionFlow += [pscustomobject]@{ phase = 'DF_NODE_ZHUANLUN_HALL'; playerGoal = 'negative test'; systemsUsed = @(); successCriteria = 'negative test' } } },
        [pscustomobject]@{ name = 'handoff_asset_request_container_shape'; subject = 'handoff'; handoff_name = 'object-config-brief.json'; expected_code = 'handoff_object_required'; mutate = { param($Copy) $Copy.assetRequests = 'not-an-object' } },
        [pscustomobject]@{ name = 'handoff_session_flow_string_shape'; subject = 'handoff'; handoff_name = 'terrain-layout-brief.json'; expected_code = 'handoff_array_required'; mutate = { param($Copy) $Copy.sessionFlow = 'not-an-array' } },
        [pscustomobject]@{ name = 'handoff_session_flow_null_shape'; subject = 'handoff'; handoff_name = 'terrain-layout-brief.json'; expected_code = 'handoff_array_required'; mutate = { param($Copy) $Copy.sessionFlow = $null } }
    )
    foreach ($Case in $Cases) {
        $CaseErrors = New-IssueList
        if ($Case.subject -eq 'contract') {
            $Copy = Copy-JsonObject $Contract
            & $Case.mutate $Copy
            Test-Contract $Copy $Preflight $ProjectRoot $CaseErrors
        } elseif ($Case.subject -eq 'design') {
            $Copy = Copy-JsonObject $Design
            & $Case.mutate $Copy
            Test-DesignSpec $Copy $Contract $CaseErrors
        } else {
            $HandoffPath = Join-Path $HandoffDirectory $Case.handoff_name
            $Original = Read-JsonFile $HandoffPath $CaseErrors "negative.handoff.$($Case.handoff_name)"
            $Copy = Copy-JsonObject $Original
            & $Case.mutate $Copy
            Test-HandoffDocument $Case.handoff_name $Copy $CaseErrors
        }
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
$HandoffDirectory = Join-Path $PSScriptRoot 'handoff'
Test-Contract $Contract $Preflight $ProjectRoot $Errors
Test-DesignSpec $Design $Contract $Errors
Test-HandoffJsons $HandoffDirectory $Errors
foreach ($ForbiddenDirectory in @('implementation\difu')) {
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot $ForbiddenDirectory)) { Add-Issue $Errors 'out_of_scope_implementation_present' $ForbiddenDirectory 'This design package must not create the implementation directory.' }
}
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
    $NegativeResults = Invoke-NegativeTests $Contract $Design $Preflight $ProjectRoot $HandoffDirectory
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
