[CmdletBinding()]
param(
    [string]$ContractPath = '',
    [string]$SpecificationPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Checks = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:Checks++
    if (-not $Condition) {
        throw "FAIL [$script:Checks] $Message"
    }
    Write-Host "PASS [$script:Checks] $Message"
}

function Assert-Null {
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Assert-True -Condition ($null -eq $Value) -Message $Message
}

function Test-NonEmptyText {
    param([Parameter(Mandatory = $true)]$Value)
    return $Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value)
}

try {
    if ([string]::IsNullOrWhiteSpace($ContractPath)) {
        $ContractPath = Join-Path $PSScriptRoot 'difu-combat-readability-contract.json'
    }
    if ([string]::IsNullOrWhiteSpace($SpecificationPath)) {
        $specFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.md')
        Assert-True -Condition ($specFiles.Count -eq 1) -Message 'exactly one Markdown specification is present in the combat directory'
        $SpecificationPath = $specFiles[0].FullName
    }

    Assert-True -Condition (Test-Path -LiteralPath $ContractPath -PathType Leaf) -Message 'machine-readable contract exists'
    Assert-True -Condition (Test-Path -LiteralPath $SpecificationPath -PathType Leaf) -Message 'human-readable specification exists'

    $contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $specification = Get-Content -LiteralPath $SpecificationPath -Raw -Encoding UTF8

    Assert-True -Condition ($contract.version -eq 1) -Message 'contract version is 1'
    Assert-True -Condition ($contract.package_status -eq 'offline-design-spec') -Message 'package remains offline-design-spec'
    Assert-True -Condition ($contract.production_gate -eq 'closed') -Message 'production gate remains closed'
    Assert-True -Condition ($contract.identity.spec_id -eq 'DF_SPEC_COMBAT_READABILITY') -Message 'contract identity is fixed'
    Assert-Null -Value $contract.identity.runtime_key -Message 'contract creates no runtime key'

    $expectedLoop = @(
        'fate_record_or_soul_mark_evidence',
        'judgment_priority_under_pressure',
        'visible_order_restoration',
        'failure_review_for_next_judgment'
    )
    foreach ($step in $expectedLoop) {
        Assert-True -Condition ($contract.combat_identity.core_loop -contains $step) -Message "core loop includes $step"
    }
    Assert-True -Condition (Test-NonEmptyText $contract.combat_identity.difference_from_huaguoshan) -Message 'contract differentiates Huaguoshan public behavior'
    Assert-True -Condition (Test-NonEmptyText $contract.combat_identity.difference_from_tianting) -Message 'contract differentiates Tianting stellar choreography'

    Assert-True -Condition ($contract.hard_boundaries.party_cap.minimum_players -eq 1 -and $contract.hard_boundaries.party_cap.maximum_players -eq 4) -Message 'package retains one-to-four-player boundary'
    Assert-True -Condition ($contract.hard_boundaries.yanluo_rule.encounter_key -eq 'DF_E_YANLUO_HALL') -Message 'Yanluo encounter identity is preserved'
    Assert-True -Condition ($contract.hard_boundaries.yanluo_rule.is_only_normal_completion_producer -eq $true) -Message 'Yanluo remains sole normal completion producer'
    Assert-True -Condition ($contract.hard_boundaries.yanluo_rule.combat_spec_can_write_progression -eq $false) -Message 'combat specification cannot write Yanluo progression'
    Assert-True -Condition ($contract.hard_boundaries.zhuanlun_rule.encounter_key -eq 'DF_E_ZHUANLUN_HALL') -Message 'Zhuanlun encounter identity is preserved'
    Assert-True -Condition ($contract.hard_boundaries.zhuanlun_rule.writes_yanluo_progression -eq $false) -Message 'Zhuanlun cannot write Yanluo progression'
    Assert-True -Condition ($contract.hard_boundaries.zhuanlun_rule.may_replace_yanluo_normal_completion -eq $false) -Message 'Zhuanlun cannot replace Yanluo normal completion'
    Assert-True -Condition ($contract.hard_boundaries.side_instance_rule.is_optional_parallel_nonblocking -eq $true) -Message 'Baigu remains optional and nonblocking'
    Assert-True -Condition ($contract.hard_boundaries.side_instance_rule.is_mainline_entry_prerequisite -eq $false) -Message 'Baigu cannot become a mainline entry prerequisite'
    Assert-True -Condition ($contract.hard_boundaries.team_entry_rule.zhuanlun_is_mainline_entry_prerequisite -eq $false) -Message 'Zhuanlun cannot become a mainline entry prerequisite'

    $expectedEncounterIds = @(
        'DF_SPEC_COMBAT_WUCHANG_ALLEY',
        'DF_SPEC_COMBAT_GHOST_GATE',
        'DF_SPEC_COMBAT_GUIDING_COURT',
        'DF_SPEC_COMBAT_JUDGE_HALL',
        'DF_SPEC_COMBAT_BAIGU_SECRET_REALM',
        'DF_SPEC_COMBAT_YANLUO_HALL',
        'DF_SPEC_COMBAT_ZHUANLUN_HALL'
    )
    Assert-True -Condition ($contract.encounters.Count -eq $expectedEncounterIds.Count) -Message 'contract covers exactly the seven required encounters'

    $requiredEncounterFields = @('warning', 'player_decision', 'visible_restoration', 'failure_meaning', 'review', 'player_scaling', 'accessibility')
    foreach ($encounterId in $expectedEncounterIds) {
        $encounter = @($contract.encounters | Where-Object { $_.spec_id -eq $encounterId })
        Assert-True -Condition ($encounter.Count -eq 1) -Message "$encounterId exists exactly once"
        foreach ($field in $requiredEncounterFields) {
            Assert-True -Condition ($null -ne $encounter[0].$field) -Message "$encounterId includes $field"
        }
        Assert-True -Condition (Test-NonEmptyText $encounter[0].player_decision) -Message "$encounterId includes a player decision"
        Assert-True -Condition (Test-NonEmptyText $encounter[0].failure_meaning) -Message "$encounterId includes an explainable failure meaning"
        Assert-True -Condition (Test-NonEmptyText $encounter[0].review) -Message "$encounterId includes a readable review"
        Assert-True -Condition (Test-NonEmptyText $encounter[0].warning.visual_or_spatial) -Message "$encounterId has a visual or spatial warning"
        Assert-True -Condition (Test-NonEmptyText $encounter[0].warning.audio_or_ui_or_state_change) -Message "$encounterId has an independent second warning channel"
        Assert-True -Condition ($encounter[0].accessibility.color_only_forbidden -eq $true) -Message "$encounterId forbids color-only critical information"
        Assert-True -Condition ($encounter[0].player_scaling.minimum_players -ge 1 -and $encounter[0].player_scaling.maximum_players -le 4) -Message "$encounterId retains one-to-four-player adaptation"
    }

    $baigu = @($contract.encounters | Where-Object { $_.spec_id -eq 'DF_SPEC_COMBAT_BAIGU_SECRET_REALM' })[0]
    Assert-True -Condition ($baigu.player_scaling.minimum_players -eq 1 -and $baigu.player_scaling.maximum_players -eq 1) -Message 'Baigu remains a solo multi-form identification encounter'
    Assert-True -Condition ($baigu.entry_boundary.is_mainline_entry_prerequisite -eq $false -and $baigu.entry_boundary.is_team_entry_prerequisite -eq $false) -Message 'Baigu cannot gate mainline or team entry'

    $yanluo = @($contract.encounters | Where-Object { $_.spec_id -eq 'DF_SPEC_COMBAT_YANLUO_HALL' })[0]
    Assert-True -Condition ($yanluo.phases.Count -eq 3) -Message 'Yanluo retains evidence, judgment and restoration phases'
    Assert-True -Condition ($yanluo.progression_boundary.combat_spec_writes_progression -eq $false) -Message 'Yanluo combat layer does not directly write progression'
    Assert-True -Condition ($yanluo.progression_boundary.only_authoritative_success_event_may_write -eq 'DF_E_YANLUO_HALL') -Message 'only existing Yanluo authority event may write completion'

    $zhuanlun = @($contract.encounters | Where-Object { $_.spec_id -eq 'DF_SPEC_COMBAT_ZHUANLUN_HALL' })[0]
    Assert-True -Condition ($zhuanlun.progression_boundary.writes_yanluo_progression -eq $false) -Message 'Zhuanlun combat cannot write Yanluo progression'
    Assert-True -Condition ($zhuanlun.progression_boundary.may_replace_yanluo_normal_completion -eq $false) -Message 'Zhuanlun combat cannot replace normal completion'
    Assert-True -Condition ($zhuanlun.progression_boundary.uses_existing_team_cleanup_contract -eq $true) -Message 'Zhuanlun consumes existing team cleanup contract'

    foreach ($field in @('duration', 'health', 'damage', 'map', 'terrain', 'object_records', 'runtime_implementation', 'reward', 'drop', 'currency', 'xp', 'qualification', 'receipt', 'runtime_key')) {
        Assert-Null -Value $contract.deferred.$field -Message "global deferred field $field remains null"
    }
    foreach ($field in @('duration', 'health', 'damage', 'cooldown', 'cast_time', 'movement', 'timeout', 'revive', 'runtime_key')) {
        Assert-Null -Value $contract.readability_grammar.numeric_values.$field -Message "mechanic numeric field $field remains null"
    }

    foreach ($artifact in $contract.source_artifacts) {
        $resolved = Join-Path $PSScriptRoot $artifact
        Assert-True -Condition (Test-Path -LiteralPath $resolved -PathType Leaf) -Message "source resolves: $artifact"
    }

    foreach ($token in @('DF_E_YANLUO_HALL', 'DF_E_ZHUANLUN_HALL', 'DF_PROGRESS_YANLUO_HALL_CLEARED', 'null/deferred')) {
        Assert-True -Condition ($specification.Contains($token)) -Message "specification preserves token: $token"
    }

    Write-Host ''
    Write-Host "Difu combat readability contract passed: $script:Checks checks."
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
