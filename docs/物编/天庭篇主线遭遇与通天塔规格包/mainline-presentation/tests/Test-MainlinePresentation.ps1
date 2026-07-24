[CmdletBinding()]
param(
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$script:AssertionCount = 0

function Assert-That {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:AssertionCount++
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

$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$SpecRoot = Split-Path -Parent $PackageRoot
$ContractPath = Join-Path $PackageRoot 'tianting-mainline-presentation-contract.json'
$SpecificationFiles = @(Get-ChildItem -LiteralPath $PackageRoot -File -Filter '*.md' | Where-Object { $_.Name -ne 'README.md' })

Assert-That -Condition (Test-Path -LiteralPath $ContractPath -PathType Leaf) -Message 'contract must exist'
Assert-That -Condition ($SpecificationFiles.Count -eq 1) -Message 'one markdown specification must exist beside README'
$MarkdownPath = $SpecificationFiles[0].FullName

$SourceFiles = @(
    'mainline-boss\tianting-mainline-boss-contract.json',
    'combat\tianting-combat-readability-contract.json',
    'ui\tianting-ui-accessibility-information-contract.json',
    'object-blueprint\tianting-object-art-vfx-blueprint-contract.json',
    'mainline-route.md',
    'construction-readiness-ledger.md'
)
foreach ($RelativePath in $SourceFiles) {
    Assert-That -Condition (Test-Path -LiteralPath (Join-Path $SpecRoot $RelativePath) -PathType Leaf) -Message "source material must exist: $RelativePath"
}

try {
    $Contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    throw "contract must be valid UTF-8 JSON: $($_.Exception.Message)"
}

$Markdown = Get-Content -LiteralPath $MarkdownPath -Raw -Encoding UTF8

Assert-That -Condition ($Contract.version -eq 1) -Message 'contract version must be 1'
Assert-That -Condition ($Contract.package_status -eq 'offline-narrative-presentation-spec') -Message 'package must remain offline narrative presentation only'
Assert-That -Condition ($Contract.production_gate -eq 'closed') -Message 'production gate must remain closed'
Assert-That -Condition ($Contract.identity.spec_id -eq 'TT_SPEC_TIANTING_MAINLINE_NARRATIVE_PRESENTATION') -Message 'package identity must remain stable'
Assert-NullFields -Object $Contract.identity -Fields @('runtime_key', 'map_key', 'ui_node_id', 'object_id', 'resource_id') -Label 'identity'

Assert-That -Condition ($Contract.hard_boundaries.original_summary_only -eq $true) -Message 'only original summaries are allowed'
Assert-That -Condition ($Contract.hard_boundaries.source_literature.original_text_used -eq $false) -Message 'literary source text must not be used'
Assert-That -Condition ($Contract.hard_boundaries.source_literature.external_literature_reference_used -eq $false) -Message 'external literary reference must not be used'
Assert-NullFields -Object $Contract.hard_boundaries.runtime_and_asset_bindings -Fields @('y3_write', 'lua_write', 'map_write', 'ui_write', 'object_write', 'asset_write', 'camera_path', 'audio_asset', 'vfx_asset', 'runtime_key', 'resource_id') -Label 'runtime_and_asset_bindings'
Assert-NullFields -Object $Contract.hard_boundaries.numeric_fields -Fields @('health', 'attack', 'defense', 'attack_speed', 'movement_speed', 'damage', 'cast_seconds', 'duration_seconds') -Label 'numeric_fields'
Assert-NullFields -Object $Contract.hard_boundaries.progression_and_settlement -Fields @('progression_write', 'completion_event', 'reward', 'drop', 'receipt', 'economy_input') -Label 'progression_and_settlement'

$ExpectedProfiles = @(
    [PSCustomObject]@{
        Presentation = 'TT_SPEC_MAINLINE_PRESENTATION_SPLIT_SOUTH_GATE'
        Source = 'TT_SPEC_MAINLINE_BOSS_SPLIT_SOUTH_GATE'
        Phases = @(
            'TT_SPEC_MAINLINE_PHASE_SOUTH_GATE_DIVERGENT_ORDER',
            'TT_SPEC_MAINLINE_PHASE_SOUTH_GATE_ALTERNATING_VERIFY',
            'TT_SPEC_MAINLINE_PHASE_SOUTH_GATE_GATE_RESET'
        )
    },
    [PSCustomObject]@{
        Presentation = 'TT_SPEC_MAINLINE_PRESENTATION_BROKEN_RAINBOW_FORMATION'
        Source = 'TT_SPEC_MAINLINE_BOSS_BROKEN_RAINBOW_FORMATION'
        Phases = @(
            'TT_SPEC_MAINLINE_PHASE_RAINBOW_EYE_VERIFY',
            'TT_SPEC_MAINLINE_PHASE_RAINBOW_CHAIN_BREAK',
            'TT_SPEC_MAINLINE_PHASE_RAINBOW_GUARDIAN_CORRECTION'
        )
    },
    [PSCustomObject]@{
        Presentation = 'TT_SPEC_MAINLINE_PRESENTATION_FOUR_GATE_IMBALANCE'
        Source = 'TT_SPEC_MAINLINE_BOSS_FOUR_GATE_IMBALANCE'
        Phases = @(
            'TT_SPEC_MAINLINE_PHASE_FOUR_GATE_REVEAL',
            'TT_SPEC_MAINLINE_PHASE_FOUR_GATE_SEQUENCE_OR_SPLIT',
            'TT_SPEC_MAINLINE_PHASE_FOUR_GATE_STABILIZE'
        )
    },
    [PSCustomObject]@{
        Presentation = 'TT_SPEC_MAINLINE_PRESENTATION_CELESTIAL_OBSERVATORY'
        Source = 'TT_SPEC_MAINLINE_BOSS_CELESTIAL_OBSERVATORY'
        Phases = @(
            'TT_SPEC_MAINLINE_PHASE_OBSERVATORY_OBSERVE_DELTA',
            'TT_SPEC_MAINLINE_PHASE_OBSERVATORY_FALSE_TRACK',
            'TT_SPEC_MAINLINE_PHASE_OBSERVATORY_CALIBRATE'
        )
    },
    [PSCustomObject]@{
        Presentation = 'TT_SPEC_MAINLINE_PRESENTATION_LINGXIAO_OUTER_COURT'
        Source = 'TT_SPEC_MAINLINE_BOSS_LINGXIAO_OUTER_COURT'
        Phases = @(
            'TT_SPEC_MAINLINE_PHASE_LINGXIAO_IDENTIFY_ORDER',
            'TT_SPEC_MAINLINE_PHASE_LINGXIAO_EXECUTE_ORDER',
            'TT_SPEC_MAINLINE_PHASE_LINGXIAO_RESTORE_ORDER'
        )
    }
)

Assert-That -Condition (@($Contract.boss_presentation_profiles).Count -eq $ExpectedProfiles.Count) -Message 'exactly five mainline presentation profiles are required'

foreach ($Expected in $ExpectedProfiles) {
    $Profiles = @($Contract.boss_presentation_profiles | Where-Object { $_.spec_id -eq $Expected.Presentation })
    Assert-That -Condition ($Profiles.Count -eq 1) -Message "one profile must exist for $($Expected.Presentation)"
    $Profile = $Profiles[0]

    Assert-That -Condition ($Profile.source_boss_spec_id -eq $Expected.Source) -Message "$($Expected.Presentation) must reference its existing boss specification"
    Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Profile.entry_guidance.narrative_intent)) -Message "$($Expected.Presentation) must have a narrative entry intent"
    Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Profile.entry_guidance.player_facing_brief)) -Message "$($Expected.Presentation) must have a player-facing entry brief"
    Assert-That -Condition ($null -eq $Profile.entry_guidance.runtime_binding) -Message "$($Expected.Presentation) entry guidance cannot bind runtime"
    Assert-That -Condition (@($Profile.stage_anchors).Count -eq $Expected.Phases.Count) -Message "$($Expected.Presentation) must have the existing three-stage structure"

    for ($Index = 0; $Index -lt $Expected.Phases.Count; $Index++) {
        $Anchor = $Profile.stage_anchors[$Index]
        Assert-That -Condition ($Anchor.source_phase_spec_id -eq $Expected.Phases[$Index]) -Message "$($Expected.Presentation) stage $Index must preserve source phase order"
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Anchor.narrative_anchor)) -Message "$($Expected.Presentation) stage $Index must explain its narrative anchor"
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Anchor.evidence_to_carry_forward)) -Message "$($Expected.Presentation) stage $Index must retain evidence"
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Anchor.warning_copy.structural_channel)) -Message "$($Expected.Presentation) stage $Index must provide a structural warning channel"
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Anchor.warning_copy.independent_channel)) -Message "$($Expected.Presentation) stage $Index must provide an independent warning channel"
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Anchor.warning_copy.accessibility_alternative)) -Message "$($Expected.Presentation) stage $Index must provide an accessibility alternative"
        Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Anchor.result_readback)) -Message "$($Expected.Presentation) stage $Index must provide a readable result"
    }

    Assert-That -Condition (@($Profile.failure_debrief_skeleton).Count -ge 3) -Message "$($Expected.Presentation) must include failure debrief categories"
    Assert-That -Condition (-not [string]::IsNullOrWhiteSpace($Profile.non_economic_narrative_confirmation.what_player_can_be_told)) -Message "$($Expected.Presentation) must include non-economic narrative confirmation"
    Assert-That -Condition ($Profile.non_economic_narrative_confirmation.authority_fact_required -eq 'future_authority_accepted_terminal_fact_only') -Message "$($Expected.Presentation) confirmation must wait for authority fact"
    Assert-NullFields -Object $Profile.non_economic_narrative_confirmation -Fields @('progression_write', 'reward', 'receipt', 'economy_input') -Label "$($Expected.Presentation).non_economic_narrative_confirmation"
    Assert-NullFields -Object $Profile.presentation_layers -Fields @('actual_camera_path', 'audio_asset', 'vfx_asset') -Label "$($Expected.Presentation).presentation_layers"
    Assert-NullFields -Object $Profile.runtime_bindings -Fields @('map_key', 'ui_node_id', 'object_id', 'resource_id', 'event_id', 'runtime_key') -Label "$($Expected.Presentation).runtime_bindings"
}

Assert-That -Condition ($Markdown -match 'production_gate = closed') -Message 'markdown must state closed production gate'
Assert-That -Condition ($Markdown -match 'TT-PRESENTATION-ACC-006') -Message 'markdown must state original-summary acceptance boundary'
Assert-That -Condition ($Markdown -match 'null/deferred') -Message 'markdown must state deferred bindings'
Assert-That -Condition ($Markdown -match 'P0') -Message 'markdown must state the absolute-calibration gate'

$ForbiddenRuntimeArtifacts = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object { $_.Extension -in @('.lua', '.y3', '.upui') }
Assert-That -Condition (@($ForbiddenRuntimeArtifacts).Count -eq 0) -Message 'package must not contain runtime map, Lua or UI artifacts'

Write-Output "PASS: $script:AssertionCount assertions passed for the mainline presentation package."
