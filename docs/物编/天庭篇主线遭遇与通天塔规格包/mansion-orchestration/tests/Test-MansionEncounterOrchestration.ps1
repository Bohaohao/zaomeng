[CmdletBinding()]
param(
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$script:AssertionCount = 0

function Assert-That {
    param(
        [Parameter(Mandatory = $true)]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:AssertionCount++
    if ($Condition -isnot [bool]) {
        throw "ASSERTION TYPE FAILED: $Message; expected boolean, got $($Condition.GetType().FullName)"
    }
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Assert-NullFields {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string[]]$Fields,
        [Parameter(Mandatory = $true)][string]$Label
    )

    foreach ($Field in $Fields) {
        Assert-That -Condition ($null -eq $Object.$Field) -Message "$Label.$Field must remain null"
    }
}

function Assert-ExactArray {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $ActualItems = @($Actual | ForEach-Object { [string]$_ })
    Assert-That -Condition (($ActualItems -join '|') -eq ($Expected -join '|')) -Message "$Label expected '$($Expected -join '|')', got '$($ActualItems -join '|')'"
}

function Assert-AllRuntimeKeysNull {
    param(
        [Parameter(Mandatory = $false)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) {
        return
    }

    if ($Value -is [System.Array]) {
        for ($Index = 0; $Index -lt $Value.Count; $Index++) {
            Assert-AllRuntimeKeysNull -Value $Value[$Index] -Path "${Path}[$Index]"
        }
        return
    }

    foreach ($Property in $Value.PSObject.Properties) {
        $PropertyPath = "$Path.$($Property.Name)"
        if ($Property.Name -match '^(runtime(?:_.+)?_key|runtimeKey)$') {
            Assert-That -Condition ($null -eq $Property.Value) -Message "$PropertyPath must remain null"
        }
        Assert-AllRuntimeKeysNull -Value $Property.Value -Path $PropertyPath
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$SpecRoot = Split-Path -Parent $PackageRoot
$ContractPath = Join-Path $PackageRoot 'tianting-mansion-encounter-orchestration-contract.json'
$MarkdownFiles = @(Get-ChildItem -LiteralPath $PackageRoot -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' })

Assert-That -Condition (Test-Path -LiteralPath $ContractPath -PathType Leaf) -Message 'machine contract must exist'
Assert-That -Condition ($MarkdownFiles.Count -eq 1) -Message 'exactly one human-readable specification must exist beside README'
$MarkdownPath = $MarkdownFiles[0].FullName

$SourceFiles = @(
    'tianting-content-expansion-contract.json',
    'combat\tianting-combat-readability-contract.json',
    'combat-baseline\tianting-combat-numeric-unit-baseline-contract.json',
    'authority\tianting-progression-and-instance-authority-contract.json',
    'object-preallocation\tianting-object-field-reservation-contract.json',
    'construction-readiness-ledger.md'
)
foreach ($RelativePath in $SourceFiles) {
    Assert-That -Condition (Test-Path -LiteralPath (Join-Path $SpecRoot $RelativePath) -PathType Leaf) -Message "source material must exist: $RelativePath"
}

try {
    $Contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $Expansion = Get-Content -LiteralPath (Join-Path $SpecRoot 'tianting-content-expansion-contract.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    throw "contracts must be valid UTF-8 JSON: $($_.Exception.Message)"
}
$Markdown = Get-Content -LiteralPath $MarkdownPath -Raw -Encoding UTF8

Assert-That -Condition ($Contract.version -eq 1) -Message 'contract version must be 1'
Assert-That -Condition ($Contract.package_status -eq 'offline-encounter-choreography-spec') -Message 'package status must remain offline encounter choreography only'
Assert-That -Condition ($Contract.production_gate -eq 'closed') -Message 'production gate must remain closed'
Assert-That -Condition ($Contract.runtime_handoff -eq $false) -Message 'package must not hand off runtime implementation'
Assert-That -Condition ($Contract.identity.spec_id -eq 'TT_SPEC_TIANTING_MANSION_ENCOUNTER_ORCHESTRATION') -Message 'identity must remain stable'
Assert-NullFields -Object $Contract.identity -Fields @('runtime_key', 'map_key', 'object_id', 'ability_id', 'ui_node_id', 'resource_id') -Label 'identity'
Assert-That -Condition (@($Contract.source_contracts).Count -eq 7) -Message 'all seven source artifacts must be declared'
foreach ($Source in @($Contract.source_contracts)) {
    Assert-That -Condition (Test-Path -LiteralPath (Join-Path $PackageRoot $Source.path) -PathType Leaf) -Message "declared source must exist: $($Source.path)"
}

$Boundaries = $Contract.hard_boundaries
Assert-That -Condition ($Boundaries.authority_ownership.session_owner -eq 'existing_authority_contract_only') -Message 'existing authority contract remains the session owner'
Assert-That -Condition ($Boundaries.authority_ownership.session_lifecycle -eq 'active_to_cleanup_pending_to_closed_is_not_an_encounter_state_machine') -Message 'encounter cannot replace session lifecycle'
Assert-That -Condition ($Boundaries.authority_ownership.cleanup_token_rule -match 'never a player mechanism input') -Message 'cleanup token remains outside mechanism input'
Assert-That -Condition ($Boundaries.authority_ownership.completion_rule -match 'not a session completion write') -Message 'encounter terminal candidate cannot write completion'
foreach ($ForbiddenMutation in @('admission', 'frozen_membership', 'member_status', 'rotation_snapshot', 'quadrant', 'difficulty', 'phase_id', 'revision', 'session_lifecycle', 'cleanup_token', 'progression', 'nightmare_credential', 'reward', 'receipt', 'economy_input')) {
    Assert-That -Condition (@($Boundaries.authority_ownership.forbidden_mutations) -contains $ForbiddenMutation) -Message "authority mutation is forbidden: $ForbiddenMutation"
}
Assert-ExactArray -Actual $Boundaries.transition_binding.future_authority_binding_fields -Expected @('raid_instance_id', 'boss_instance_id', 'session_epoch', 'phase_id', 'revision', 'rotation_snapshot_id', 'quadrant', 'difficulty', 'actor_id', 'actor_lifecycle_id', 'membership_snapshot_id', 'member_status') -Label 'future authority transition binding'
Assert-ExactArray -Actual $Boundaries.transition_binding.encounter_local_semantic_fields -Expected @('encounter_beat_spec_id', 'encounter_state_spec_id', 'transition_index') -Label 'local semantic field names'
foreach ($ForbiddenInput in @('cleanup_token', 'client_clock', 'client_timezone', 'client_quadrant', 'local_timer', 'damage_meter', 'local_ui_state', 'unfrozen_member', 'client_reported_member_status', 'left_member', 'dead_member', 'stale_lifecycle')) {
    Assert-That -Condition (@($Boundaries.transition_binding.forbidden_transition_inputs) -contains $ForbiddenInput) -Message "forbidden mechanism input is named: $ForbiddenInput"
}
Assert-That -Condition ($Boundaries.transition_binding.replay_drift_policy -eq 'reject') -Message 'mechanism replay drift must reject'
Assert-That -Condition ($Boundaries.transition_binding.authority_member_snapshot_rule -match 'membership_snapshot_id') -Message 'member binding uses the authority membership snapshot identity'
Assert-That -Condition ($Boundaries.transition_binding.authority_member_snapshot_rule -match 'member_status') -Message 'member binding uses authority member status'
Assert-NullFields -Object $Boundaries.runtime_and_asset_bindings -Fields @('y3_write', 'lua_write', 'map_write', 'object_write', 'ability_write', 'buff_write', 'projectile_write', 'ui_write', 'storage_write', 'actual_event_key', 'runtime_key', 'resource_id') -Label 'runtime and asset bindings'
Assert-NullFields -Object $Boundaries.numeric_fields -Fields @('health', 'attack', 'defense', 'damage', 'range', 'cooldown_seconds', 'cast_seconds', 'duration_seconds', 'threat', 'wave_count') -Label 'numeric fields'
Assert-NullFields -Object $Boundaries.economy_and_progression -Fields @('progression_write', 'normal_clear_qualification', 'nightmare_qualification', 'night_patrol_key', 'title', 'material', 'reward', 'receipt', 'economy_input') -Label 'economy and progression fields'

Assert-ExactArray -Actual $Contract.semantic_state_grammar.normal_segment_sequence -Expected @('segment_read', 'lead_signature_telegraph', 'support_relation_commit', 'combined_counterplay', 'visible_readback', 'recover_or_transition') -Label 'normal semantic state sequence'
Assert-ExactArray -Actual $Contract.semantic_state_grammar.nightmare_state_sequence -Expected @('resonance_visible', 'officer_counterplay', 'purified_officer_aid', 'sacred_core_restoration') -Label 'nightmare semantic state sequence'
Assert-That -Condition ($Contract.semantic_state_grammar.state_ownership_rule -match 'must not reuse') -Message 'semantic states cannot reuse phase_id'
Assert-That -Condition ($Contract.semantic_state_grammar.terminal_candidate_rule -match 'read-only') -Message 'terminal candidate remains read-only'
$TransitionGraph = $Contract.semantic_state_grammar.transition_graph
Assert-ExactArray -Actual $TransitionGraph.normal_states -Expected @('TT_SPEC_MANSION_NORMAL_FRONT_PAIR', 'TT_SPEC_MANSION_NORMAL_MIDDLE_PAIR', 'TT_SPEC_MANSION_NORMAL_REAR_PAIR', 'TT_SPEC_MANSION_NORMAL_GUARD_SINGLE', 'TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE') -Label 'normal semantic state graph'
Assert-ExactArray -Actual $TransitionGraph.normal_forward_edges -Expected @('TT_SPEC_MANSION_NORMAL_FRONT_PAIR -> TT_SPEC_MANSION_NORMAL_MIDDLE_PAIR', 'TT_SPEC_MANSION_NORMAL_MIDDLE_PAIR -> TT_SPEC_MANSION_NORMAL_REAR_PAIR', 'TT_SPEC_MANSION_NORMAL_REAR_PAIR -> TT_SPEC_MANSION_NORMAL_GUARD_SINGLE', 'TT_SPEC_MANSION_NORMAL_GUARD_SINGLE -> TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE') -Label 'normal forward graph edges'
Assert-ExactArray -Actual $TransitionGraph.nightmare_states -Expected @('TT_SPEC_MANSION_NIGHTMARE_CHAIN_01', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_02', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_03', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_04', 'TT_SPEC_MANSION_NIGHTMARE_SACRED_CORE_RESTORATION', 'TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE') -Label 'nightmare semantic state graph'
Assert-ExactArray -Actual $TransitionGraph.nightmare_forward_edges -Expected @('TT_SPEC_MANSION_NIGHTMARE_CHAIN_01 -> TT_SPEC_MANSION_NIGHTMARE_CHAIN_02', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_02 -> TT_SPEC_MANSION_NIGHTMARE_CHAIN_03', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_03 -> TT_SPEC_MANSION_NIGHTMARE_CHAIN_04', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_04 -> TT_SPEC_MANSION_NIGHTMARE_SACRED_CORE_RESTORATION', 'TT_SPEC_MANSION_NIGHTMARE_SACRED_CORE_RESTORATION -> TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE') -Label 'nightmare forward graph edges'
Assert-That -Condition ($TransitionGraph.recovery_rule -match 'cannot increment transition_index') -Message 'recovery cannot increment semantic transition index'
Assert-That -Condition ($TransitionGraph.transition_index_rule -match 'strictly monotonic') -Message 'transition index must be monotonic'
Assert-That -Condition ($TransitionGraph.transition_index_rule -match 'skip, reversal') -Message 'transition graph rejects skips and reversals'
Assert-That -Condition ($Contract.concurrency_and_member_change.pressure_budget.one_active_member -match 'one primary P0') -Message 'single-player pressure budget preserves one primary P0'
Assert-That -Condition ($Contract.concurrency_and_member_change.pressure_budget.two_to_four_active_members -match 'one primary P0') -Message 'multiplayer pressure budget preserves one primary P0'
foreach ($Prohibition in @('two_simultaneous_primary_P0_sources', 'permanent_two_location_occupancy', 'role_locked_fifth_member_assumption', 'more_members_shortens_the_read_line')) {
    Assert-That -Condition (@($Contract.concurrency_and_member_change.pressure_budget.prohibitions) -contains $Prohibition) -Message "pressure prohibition exists: $Prohibition"
}
Assert-That -Condition ($Contract.concurrency_and_member_change.member_change_rule -match 'authority-confirmed') -Message 'member changes require authority confirmation'
Assert-That -Condition ($Contract.concurrency_and_member_change.member_change_rule -match 'current beat boundary') -Message 'member changes apply only at beat boundaries'
Assert-That -Condition ($Contract.concurrency_and_member_change.dead_or_left_rule -match 'cannot advance') -Message 'dead and left members cannot advance a beat'
Assert-That -Condition ($Contract.concurrency_and_member_change.dead_or_left_rule -match 'client death or disconnect reports') -Message 'client reports cannot replace the authority member snapshot'

$ExpectedSegmentShape = @('front_pair', 'middle_pair', 'rear_pair', 'guard_single')
Assert-ExactArray -Actual $Contract.normal_raid.segment_shape -Expected $ExpectedSegmentShape -Label 'normal raid segment shape'
Assert-That -Condition (@($Contract.normal_raid.quadrant_segments).Count -eq 4) -Message 'normal choreography must cover exactly four quadrants'

$SourceOfficers = @{}
$SourceQuadrants = @{}
$SourceSacredBeasts = @{}
foreach ($SourceQuadrant in @($Expansion.twenty_eight_mansions_raid.quadrants)) {
    $SourceQuadrants[$SourceQuadrant.quadrant] = @($SourceQuadrant.officers | ForEach-Object { $_.spec_id })
    $SourceSacredBeasts[$SourceQuadrant.quadrant] = [string]$SourceQuadrant.sacred_beast
    foreach ($Officer in @($SourceQuadrant.officers)) {
        $SourceOfficers[$Officer.spec_id] = [PSCustomObject]@{ full_name = $Officer.full_name; quadrant = $SourceQuadrant.quadrant; unique_skill = $Officer.unique_skill }
    }
}
Assert-That -Condition ($SourceOfficers.Count -eq 28) -Message 'source expansion must expose exactly 28 canonical officers'

$SeenSegmentOfficers = [System.Collections.Generic.List[string]]::new()
foreach ($QuadrantProfile in @($Contract.normal_raid.quadrant_segments)) {
    Assert-That -Condition ($SourceQuadrants.ContainsKey($QuadrantProfile.quadrant)) -Message "normal profile uses a source quadrant: $($QuadrantProfile.quadrant)"
    Assert-That -Condition (@($QuadrantProfile.segments).Count -eq 4) -Message "$($QuadrantProfile.quadrant) has four normal segments"
    Assert-ExactArray -Actual @($QuadrantProfile.segments | ForEach-Object { $_.segment }) -Expected $ExpectedSegmentShape -Label "$($QuadrantProfile.quadrant) segment order"
    Assert-ExactArray -Actual @($QuadrantProfile.segments | ForEach-Object { @($_.officers).Count }) -Expected @('2', '2', '2', '1') -Label "$($QuadrantProfile.quadrant) segment sizes"
    $Flattened = [System.Collections.Generic.List[string]]::new()
    foreach ($Segment in @($QuadrantProfile.segments)) {
        Assert-That -Condition (@($Segment.officers).Count -in @(1, 2)) -Message "$($QuadrantProfile.quadrant) $($Segment.segment) has one or two officers"
        Assert-That -Condition (@($Segment.officers) -contains $Segment.lead) -Message "$($QuadrantProfile.quadrant) $($Segment.segment) lead belongs to the segment"
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Segment.combined_counter)) -Message "$($QuadrantProfile.quadrant) $($Segment.segment) has a combined counter"
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Segment.carry_forward)) -Message "$($QuadrantProfile.quadrant) $($Segment.segment) preserves readable evidence"
        foreach ($OfficerSpecId in @($Segment.officers)) {
            $Flattened.Add($OfficerSpecId)
            $SeenSegmentOfficers.Add($OfficerSpecId)
        }
    }
    Assert-ExactArray -Actual $Flattened.ToArray() -Expected $SourceQuadrants[$QuadrantProfile.quadrant] -Label "$($QuadrantProfile.quadrant) officer ordering"
}
Assert-That -Condition ((@($SeenSegmentOfficers | Select-Object -Unique)).Count -eq 28) -Message 'normal segments cover 28 unique officers'
Assert-That -Condition ($SeenSegmentOfficers.Count -eq 28) -Message 'normal segments never repeat an officer'

$Profiles = @($Contract.normal_raid.officer_choreography_profiles)
Assert-That -Condition ($Profiles.Count -eq 28) -Message 'exactly 28 officer choreography profiles are required'
$SeenProfileSourceIds = [System.Collections.Generic.List[string]]::new()
foreach ($Profile in $Profiles) {
    Assert-That -Condition ($Profile.spec_id -match '^TT_SPEC_MANSION_CHOREO_') -Message "$($Profile.full_name) choreography identity uses an offline spec identity"
    Assert-That -Condition ($SourceOfficers.ContainsKey($Profile.source_officer_spec_id)) -Message "$($Profile.full_name) references a canonical source officer"
    $SourceOfficer = $SourceOfficers[$Profile.source_officer_spec_id]
    Assert-That -Condition ($Profile.full_name -eq $SourceOfficer.full_name) -Message "$($Profile.source_officer_spec_id) preserves canonical full name"
    Assert-That -Condition ($Profile.quadrant -eq $SourceOfficer.quadrant) -Message "$($Profile.full_name) preserves source quadrant"
    Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Profile.signature_action)) -Message "$($Profile.full_name) preserves signature action label"
    foreach ($Field in @('read', 'commit', 'counter', 'failure_recovery')) {
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Profile.$Field)) -Message "$($Profile.full_name) has a $Field choreography field"
    }
    foreach ($MemberCount in @('one', 'two', 'three', 'four', 'member_loss')) {
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Profile.adaptation.$MemberCount)) -Message "$($Profile.full_name) has an adaptation branch: $MemberCount"
    }
    Assert-That -Condition ($null -eq $Profile.runtime_binding) -Message "$($Profile.full_name) has no runtime binding"
    $SeenProfileSourceIds.Add($Profile.source_officer_spec_id)
}
Assert-That -Condition ((@($SeenProfileSourceIds | Select-Object -Unique)).Count -eq 28) -Message 'officer choreography profiles have unique source identities'
Assert-That -Condition ((($SeenProfileSourceIds | Sort-Object) -join '|') -eq (($SourceOfficers.Keys | Sort-Object) -join '|')) -Message 'officer choreography profile source set exactly matches source officers'

$NormalTerminal = $Contract.normal_raid.terminal_candidate
Assert-That -Condition ($NormalTerminal.precondition -match 'four ordered 2\+2\+2\+1') -Message 'normal terminal candidate requires the exact four-segment shape'
Assert-That -Condition ($NormalTerminal.precondition -match 'seven source officer identities') -Message 'normal terminal candidate requires all seven officers'
Assert-That -Condition ($NormalTerminal.result -eq 'TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE') -Message 'normal terminal candidate identity is stable'
Assert-NullFields -Object $NormalTerminal -Fields @('session_completion_write', 'qualification_write', 'credential_write', 'reward', 'receipt', 'economy_input') -Label 'normal terminal candidate'

$Nightmare = $Contract.nightmare_four_sacred
Assert-That -Condition ($Nightmare.spec_id -eq 'TT_SPEC_MANSION_NIGHTMARE_ENCOUNTER_CHOREOGRAPHY') -Message 'nightmare choreography identity is stable'
Assert-That -Condition ($Nightmare.same_quadrant_rule -match 'one exact quadrant') -Message 'nightmare remains same quadrant only'
Assert-That -Condition ($Nightmare.active_chain_rule -match 'one primary') -Message 'nightmare allows only one primary chain'
Assert-That -Condition ($Nightmare.purification_rule -match 'monotonic') -Message 'purification must be monotonic'
Assert-That -Condition (@($Nightmare.quadrant_profiles).Count -eq 4) -Message 'nightmare choreography covers four sacred beasts'
foreach ($NightmareProfile in @($Nightmare.quadrant_profiles)) {
    Assert-That -Condition ($SourceQuadrants.ContainsKey($NightmareProfile.quadrant)) -Message "$($NightmareProfile.sacred_beast) nightmare uses source quadrant"
    Assert-That -Condition ($NightmareProfile.sacred_beast -eq $SourceSacredBeasts[$NightmareProfile.quadrant]) -Message "$($NightmareProfile.quadrant) preserves source sacred beast"
    Assert-That -Condition (@($NightmareProfile.chain_rounds).Count -eq 4) -Message "$($NightmareProfile.quadrant) has four fixed chain rounds"
    $RoundLengths = @($NightmareProfile.chain_rounds | ForEach-Object { @($_).Count })
    Assert-That -Condition (($RoundLengths -join '|') -eq '2|2|2|1') -Message "$($NightmareProfile.quadrant) chain rounds preserve 2+2+2+1"
    $FlattenedChain = [System.Collections.Generic.List[string]]::new()
    foreach ($Round in @($NightmareProfile.chain_rounds)) {
        foreach ($OfficerSpecId in @($Round)) {
            $FlattenedChain.Add($OfficerSpecId)
        }
    }
    Assert-ExactArray -Actual $FlattenedChain.ToArray() -Expected $SourceQuadrants[$NightmareProfile.quadrant] -Label "$($NightmareProfile.quadrant) nightmare chain order"
    foreach ($Field in @('purified_aid', 'sacred_response', 'failure_recovery', 'core_restoration')) {
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($NightmareProfile.$Field)) -Message "$($NightmareProfile.quadrant) has $Field choreography"
    }
}
Assert-That -Condition ($Nightmare.terminal_candidate.precondition -match 'exactly the seven') -Message 'terminal candidate requires all seven officers'
Assert-That -Condition ($Nightmare.terminal_candidate.result -eq 'TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE') -Message 'terminal candidate identity is stable'
Assert-NullFields -Object $Nightmare.terminal_candidate -Fields @('session_completion_write', 'qualification_write', 'credential_write', 'reward', 'receipt', 'economy_input') -Label 'nightmare terminal candidate'

Assert-That -Condition (@($Contract.acceptance).Count -eq 9) -Message 'contract must expose nine acceptance items'
for ($Index = 1; $Index -le 9; $Index++) {
    $ExpectedId = 'TT-MANSION-CHOREO-ACC-{0:d3}' -f $Index
    Assert-That -Condition (@($Contract.acceptance | Where-Object { $_.id -eq $ExpectedId }).Count -eq 1) -Message "acceptance item exists: $ExpectedId"
}
Assert-That -Condition (@($Contract.deferred).Count -ge 4) -Message 'runtime, data and economy gaps remain explicitly deferred'
Assert-AllRuntimeKeysNull -Value $Contract -Path 'contract'

Assert-That -Condition ($Markdown -match 'production_gate = closed') -Message 'markdown states the closed production gate'
Assert-That -Condition ($Markdown -match 'phase_id') -Message 'markdown distinguishes authority phase identity'
Assert-That -Condition ($Markdown -match 'cleanup_token') -Message 'markdown protects cleanup token'
Assert-That -Condition ($Markdown -match 'membership_snapshot_id') -Message 'markdown names the authoritative member snapshot identity'
Assert-That -Condition ($Markdown -match 'transition_index') -Message 'markdown explains monotonic encounter transitions'
Assert-That -Condition ($Markdown -match '2 \+ 2 \+ 2 \+ 1') -Message 'markdown explains fixed nightmare chain sequence'
Assert-That -Condition ($Markdown -match 'null/deferred') -Message 'markdown states deferred implementation surface'
Assert-That -Condition ($Markdown -match 'TT-MANSION-CHOREO-ACC-001') -Message 'markdown exposes the acceptance range'

$ForbiddenRuntimeArtifacts = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object { $_.Extension -in @('.lua', '.y3', '.upui') }
Assert-That -Condition (@($ForbiddenRuntimeArtifacts).Count -eq 0) -Message 'package cannot contain runtime map, Lua or UI artifacts'

Write-Output "PASS: $script:AssertionCount assertions passed for the mansion encounter choreography package."
Write-Output "contract_sha256=$(Get-Sha256Hex -Path $ContractPath)"
