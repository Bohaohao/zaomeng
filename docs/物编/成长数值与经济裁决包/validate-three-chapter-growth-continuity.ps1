[CmdletBinding()]
param(
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:Failures.Add("[$Code] $Message")
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        Add-Failure $Code "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        Add-Failure $Code $Message
    }
}

function Assert-Null {
    param(
        $Actual,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($null -ne $Actual) {
        Add-Failure $Code "$Message Expected null, got '$Actual'."
    }
}

function Assert-StringSetEqual {
    param(
        [string[]]$Actual,
        [string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $actualSorted = @($Actual | Sort-Object -Unique)
    $expectedSorted = @($Expected | Sort-Object -Unique)
    $difference = @(Compare-Object -ReferenceObject $expectedSorted -DifferenceObject $actualSorted)
    if ($difference.Count -ne 0) {
        Add-Failure $Code "$Message Expected [$($expectedSorted -join ', ')], got [$($actualSorted -join ', ')]."
    }
}

function Assert-StringSequenceEqual {
    param(
        [string[]]$Actual,
        [string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual.Count -ne $Expected.Count) {
        Add-Failure $Code "$Message Expected [$($Expected -join ', ')], got [$($Actual -join ', ')]."
        return
    }

    for ($index = 0; $index -lt $Expected.Count; $index += 1) {
        if ($Actual[$index] -ne $Expected[$index]) {
            Add-Failure $Code "$Message Expected [$($Expected -join ', ')], got [$($Actual -join ', ')]."
            return
        }
    }
}

function Get-Json {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-Failure 'invalid_json' "Cannot parse '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Get-SingleByProperty {
    param(
        [object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Code
    )

    $matches = @($Rows | Where-Object { [string]$_.PSObject.Properties[$Property].Value -eq $Value })
    if ($matches.Count -ne 1) {
        Add-Failure $Code "Expected exactly one row where $Property='$Value', got $($matches.Count)."
        return $null
    }

    return $matches[0]
}

function Get-ForbiddenPropertyPaths {
    param(
        $Node,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Forbidden
    )

    $paths = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) {
        return $paths
    }

    if ($Node -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $Node) {
            foreach ($childPath in (Get-ForbiddenPropertyPaths -Node $item -Path "$Path[$index]" -Forbidden $Forbidden)) {
                $paths.Add($childPath)
            }
            $index += 1
        }
        return $paths
    }

    foreach ($property in $Node.PSObject.Properties) {
        $propertyPath = "$Path.$($property.Name)"
        if ($Forbidden.ContainsKey([string]$property.Name)) {
            $paths.Add($propertyPath)
        }
        foreach ($childPath in (Get-ForbiddenPropertyPaths -Node $property.Value -Path $propertyPath -Forbidden $Forbidden)) {
            $paths.Add($childPath)
        }
    }

    return $paths
}

$packageRoot = Split-Path -Parent $PSCommandPath
$v2Path = Join-Path $packageRoot 'tables/economy-v2-resource-table.json'
$v3Path = Join-Path $packageRoot 'tables/economy-v3-resource-table.json'
$lineagePath = Join-Path $packageRoot 'three-chapter-growth-lineage-contract.json'
$expectedV2Hash = '3288BD9CD1BFBB516DB4808EF002C45FECCF5F1C7F4C80499DB81E31B2F84EAE'

foreach ($path in @($v2Path, $v3Path, $lineagePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure 'missing_contract_file' "Required file is missing: $path"
    }
}

if ($script:Failures.Count -eq 0) {
    $v2Hash = (Get-FileHash -LiteralPath $v2Path -Algorithm SHA256).Hash.ToUpperInvariant()
    Assert-Equal $v2Hash $expectedV2Hash 'invalid_economy_v2_hash' 'economy-v3 must inherit the exact immutable economy-v2 file bytes.'

    $v2 = Get-Json $v2Path
    $v3 = Get-Json $v3Path
    $lineage = Get-Json $lineagePath

    if ($null -ne $v2 -and $null -ne $v3 -and $null -ne $lineage) {
        Assert-Equal ([string]$v2.resource_table_version) 'economy-v2' 'invalid_economy_v2_version' 'The inherited table version is invalid.'
        Assert-Equal ([string]$v3.table) 'economy-v3-resource-table-overlay' 'invalid_economy_v3_table' 'The v3 document must stay an overlay, not a copied base table.'
        Assert-Equal ([string]$v3.resource_table_version) 'economy-v3' 'invalid_economy_v3_version' 'The overlay version is invalid.'
        Assert-Equal ([string]$v3.kind) 'versioned_delta_overlay' 'invalid_economy_v3_kind' 'The v3 document must declare versioned-delta semantics.'
        Assert-Equal ([bool]$v3.runtime_handoff) $false 'invalid_economy_v3_runtime_gate' 'economy-v3 must not enable runtime handoff.'
        Assert-Equal ([string]$v3.production_gate) 'closed' 'invalid_economy_v3_production_gate' 'economy-v3 must keep production closed.'
        Assert-Equal ([string]$v3.inherits.resource_table_version) 'economy-v2' 'invalid_economy_v3_inheritance_version' 'economy-v3 must inherit economy-v2.'
        Assert-Equal ([string]$v3.inherits.content_hash_sha256) $expectedV2Hash 'invalid_economy_v3_inheritance_hash' 'economy-v3 must pin the exact economy-v2 hash.'
        Assert-Equal ([bool]$v3.preserved_route_invariants.no_legacy_receipt_recalculation) $true 'invalid_economy_v3_history_boundary' 'economy-v3 must forbid legacy receipt recalculation.'
        Assert-Equal ([int]$v3.preserved_route_invariants.huaguoshan_total_xp) 9485 'invalid_economy_v3_total_anchor' 'Huaguoshan total XP must remain 9485.'
        Assert-Equal ([int]$v3.preserved_route_invariants.huaguoshan_target_active_minutes_at_cap) 55 'invalid_economy_v3_time_anchor' 'Huaguoshan cap anchor must remain 55 active minutes.'
        Assert-Equal ([int]$v3.preserved_route_invariants.pre_clear_cumulative_xp) 8340 'invalid_economy_v3_preclear_anchor' 'Lv19 pre-clear XP must remain 8340.'
        Assert-Equal ([int]$v3.preserved_route_invariants.pre_clear_level) 19 'invalid_economy_v3_preclear_level' 'Pre-clear level must remain Lv19.'
        Assert-Equal ([int]$v3.preserved_route_invariants.final_cumulative_xp) 9485 'invalid_economy_v3_final_anchor' 'Lv20 XP must remain 9485.'
        Assert-Equal ([int]$v3.preserved_route_invariants.final_level) 20 'invalid_economy_v3_final_level' 'Final Huaguoshan level must remain Lv20.'
        Assert-Equal ([bool]$v3.non_production_boundary.design_route_only) $true 'invalid_economy_v3_design_route_scope' 'economy-v3 must remain a design-route overlay.'
        Assert-Null $v3.non_production_boundary.source_profile_mapping 'invalid_economy_v3_source_profile_mapping' 'economy-v3 must not create a source-profile mapping.'
        Assert-Equal ([bool]$v3.non_production_boundary.actual_receipt_creation) $false 'invalid_economy_v3_receipt_execution' 'economy-v3 must not create receipts.'
        Assert-Equal ([bool]$v3.non_production_boundary.actual_economic_execution) $false 'invalid_economy_v3_economic_execution' 'economy-v3 must not execute economy actions.'
        Assert-Null $v3.non_production_boundary.runtime_keys 'invalid_economy_v3_runtime_keys' 'economy-v3 must not allocate runtime keys.'

        $v2Rows = @($v2.progression.huaguoshan_source_rows)
        $v2RowsByKey = @{}
        foreach ($row in $v2Rows) {
            $v2RowsByKey[[string]$row.source_key] = $row
        }
        Assert-Equal ([int]$v2RowsByKey['XP_EASTSEA'].base_xp) 900 'invalid_economy_v2_eastsea_base' 'The pinned economy-v2 East Sea row is unexpected.'
        Assert-Equal ([int]$v2RowsByKey['XP_CHAPTER_CLEAR'].base_xp) 1735 'invalid_economy_v2_clear_base' 'The pinned economy-v2 chapter-clear row is unexpected.'
        Assert-Equal ([int]$v2RowsByKey['XP_PENG'].base_xp) 500 'invalid_economy_v2_peng_base' 'The pinned economy-v2 Peng row is unexpected.'
        Assert-Equal ([string]$v2RowsByKey['XP_PEACH'].source_kind) 'side_quest' 'invalid_economy_v2_peach_history_kind' 'The pinned economy-v2 Peach row must retain its historical source kind.'
        Assert-Equal ([string]$v2RowsByKey['XP_CAVE'].source_kind) 'solo_instance' 'invalid_economy_v2_cave_history_kind' 'The pinned economy-v2 Cave row must retain its historical source kind.'

        $overrides = @($v3.progression_delta.row_overrides)
        Assert-StringSetEqual -Actual @($overrides | ForEach-Object { [string]$_.source_key }) -Expected @('XP_EASTSEA', 'XP_CHAPTER_CLEAR') -Code 'invalid_economy_v3_override_set' -Message 'Only East Sea and chapter-clear XP rows may be overridden.'
        $eastSeaOverride = Get-SingleByProperty -Rows $overrides -Property 'source_key' -Value 'XP_EASTSEA' -Code 'invalid_economy_v3_eastsea_override'
        $clearOverride = Get-SingleByProperty -Rows $overrides -Property 'source_key' -Value 'XP_CHAPTER_CLEAR' -Code 'invalid_economy_v3_clear_override'
        if ($null -ne $eastSeaOverride) {
            Assert-Equal ([int]$eastSeaOverride.base_xp) 1490 'invalid_economy_v3_eastsea_value' 'East Sea XP must be 1490 in the future v3 route.'
            Assert-Equal ([int]$eastSeaOverride.replaces_economy_v2_base_xp) 900 'invalid_economy_v3_eastsea_history' 'East Sea override must record the v2 base XP.'
        }
        if ($null -ne $clearOverride) {
            Assert-Equal ([int]$clearOverride.base_xp) 1145 'invalid_economy_v3_clear_value' 'Chapter-clear XP must be 1145 in the future v3 route.'
            Assert-Equal ([int]$clearOverride.replaces_economy_v2_base_xp) 1735 'invalid_economy_v3_clear_history' 'Chapter-clear override must record the v2 base XP.'
        }

        $newRows = @($v3.progression_delta.new_design_route_rows)
        Assert-Equal $newRows.Count 1 'invalid_economy_v3_new_row_count' 'The crack discovery row must be the only new design-route row.'
        $crackRow = Get-SingleByProperty -Rows $newRows -Property 'source_key' -Value 'XP_HG_CRACK_DISCOVERY' -Code 'invalid_economy_v3_crack_row'
        if ($null -ne $crackRow) {
            Assert-Equal ([int]$crackRow.base_xp) 500 'invalid_economy_v3_crack_value' 'Crack discovery XP must equal Peng XP.'
            Assert-Equal ([string]$crackRow.source_kind) 'main_quest' 'invalid_economy_v3_crack_kind' 'Crack discovery must be a non-combat forward-route design row.'
            Assert-Equal ([int]$crackRow.source_level) 14 'invalid_economy_v3_crack_level' 'Crack discovery must share the existing Peng-level anchor.'
            Assert-Null $crackRow.runtime_mapping 'invalid_economy_v3_crack_runtime_mapping' 'Crack discovery must not create a runtime mapping.'
        }

        $semanticBindings = @($v3.progression_delta.future_route_semantic_bindings)
        $expectedSemanticBindings = @{
            'XP_PEACH' = @{ historical_kind = 'side_quest'; node_id = 'HG_PEACH_GROVE_PUBLIC_MAINLINE'; node_name = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5qGD5p6X5YWs5YWx5Li76Lev57q/')) }
            'XP_CAVE' = @{ historical_kind = 'solo_instance'; node_id = 'HG_BAT_CAVE_PUBLIC_MAINLINE'; node_name = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('6J2Z6J2g56qf5YWs5YWx5Li76Lev57q/')) }
        }
        Assert-StringSetEqual -Actual @($semanticBindings | ForEach-Object { [string]$_.source_key }) -Expected @($expectedSemanticBindings.Keys) -Code 'invalid_economy_v3_route_semantic_binding_set' -Message 'Only Peach and Cave may receive future route semantic bindings.'
        foreach ($sourceKey in $expectedSemanticBindings.Keys) {
            $binding = Get-SingleByProperty -Rows $semanticBindings -Property 'source_key' -Value $sourceKey -Code 'invalid_economy_v3_route_semantic_binding'
            if ($null -ne $binding) {
                $expected = $expectedSemanticBindings[$sourceKey]
                Assert-Equal ([string]$binding.historical_economy_v2_source_kind) ([string]$expected.historical_kind) 'invalid_economy_v3_route_semantic_history' "$sourceKey must retain its exact economy-v2 historical source kind."
                Assert-Equal ([string]$binding.future_route_node_id) ([string]$expected.node_id) 'invalid_economy_v3_route_semantic_node' "$sourceKey must bind to its reviewed future route node."
                Assert-Equal ([string]$binding.future_route_node_name) ([string]$expected.node_name) 'invalid_economy_v3_route_semantic_name' "$sourceKey must bind to its reviewed player-facing route node."
                Assert-Equal ([string]$binding.future_route_semantics) 'mandatory_public_mainline' 'invalid_economy_v3_route_semantic_kind' "$sourceKey must be a future mandatory public-mainline node."
                Assert-Equal ([bool]$binding.required_for_regular_mainline_closure) $true 'invalid_economy_v3_route_semantic_closure' "$sourceKey must be required for future regular-mainline closure."
                Assert-Equal ([bool]$binding.creates_solo_instance) $false 'invalid_economy_v3_route_semantic_solo' "$sourceKey must not create a solo instance."
                Assert-Equal ([bool]$binding.is_optional_content) $false 'invalid_economy_v3_route_semantic_optional' "$sourceKey must not become optional content in the future route."
                Assert-Null $binding.source_profile_mapping 'invalid_economy_v3_route_semantic_profile' "$sourceKey cannot create a source-profile allocation."
                Assert-Null $binding.runtime_mapping 'invalid_economy_v3_route_semantic_runtime' "$sourceKey cannot create a runtime mapping."
                Assert-Equal ([bool]$binding.historical_receipt_mutation) $false 'invalid_economy_v3_route_semantic_history_mutation' "$sourceKey cannot mutate historical receipts."
                Assert-StringSetEqual -Actual @($binding.forbidden_substitutes | ForEach-Object { [string]$_ }) -Expected @('HG_E_DRAGON_OLD_TIDE', 'team_instance', 'rare_award', 'tower') -Code 'invalid_economy_v3_route_semantic_substitutes' -Message "$sourceKey must reject optional Dragon, team, rare, and tower substitutes."
            }
        }

        $resolvedSources = @{}
        foreach ($key in $v2RowsByKey.Keys) {
            $resolvedSources[$key] = [int]$v2RowsByKey[$key].base_xp
        }
        foreach ($row in $overrides) {
            $resolvedSources[[string]$row.source_key] = [int]$row.base_xp
        }
        foreach ($row in $newRows) {
            $resolvedSources[[string]$row.source_key] = [int]$row.base_xp
        }

        $choice = $v3.progression_delta.route_choice
        Assert-Equal ([string]$choice.choice_id) 'HG_ROUTE_PENG_OR_CRACK_V3' 'invalid_economy_v3_choice_id' 'The Peng-or-crack choice ID is invalid.'
        Assert-Equal ([int]$choice.selection_cardinality.minimum) 1 'invalid_economy_v3_choice_minimum' 'The route must require one branch.'
        Assert-Equal ([int]$choice.selection_cardinality.maximum) 1 'invalid_economy_v3_choice_maximum' 'The route must prohibit double collection.'
        $choiceOptions = @($choice.options)
        Assert-StringSetEqual -Actual @($choiceOptions | ForEach-Object { [string]$_.source_key }) -Expected @('XP_PENG', 'XP_HG_CRACK_DISCOVERY') -Code 'invalid_economy_v3_choice_options' -Message 'The route choice must contain exactly Peng and crack discovery.'
        foreach ($option in $choiceOptions) {
            Assert-Equal ([int]$option.base_xp) 500 'invalid_economy_v3_choice_value' "Each choice option must award 500 XP: $($option.source_key)."
        }
        $pengOption = Get-SingleByProperty -Rows $choiceOptions -Property 'source_key' -Value 'XP_PENG' -Code 'invalid_economy_v3_peng_option'
        $crackOption = Get-SingleByProperty -Rows $choiceOptions -Property 'source_key' -Value 'XP_HG_CRACK_DISCOVERY' -Code 'invalid_economy_v3_crack_option'
        if ($null -ne $pengOption) {
            Assert-Equal ([bool]$pengOption.boss_is_mandatory) $false 'invalid_economy_v3_peng_mandatory' 'Peng Demon King must remain optional.'
            Assert-Equal ([string]$pengOption.route_kind) 'optional_boss' 'invalid_economy_v3_peng_kind' 'Peng must remain the optional-boss branch.'
        }
        if ($null -ne $crackOption) {
            Assert-Equal ([string]$crackOption.route_kind) 'non_combat_discovery' 'invalid_economy_v3_crack_choice_kind' 'Crack discovery must remain the non-combat branch.'
        }
        $pairs = @($choice.anti_double_claim.prohibited_source_key_pairs)
        Assert-Equal $pairs.Count 1 'invalid_economy_v3_anti_double_pair_count' 'Exactly one prohibited Peng/crack pair is required.'
        if ($pairs.Count -eq 1) {
            Assert-StringSetEqual -Actual @($pairs[0] | ForEach-Object { [string]$_ }) -Expected @('XP_PENG', 'XP_HG_CRACK_DISCOVERY') -Code 'invalid_economy_v3_anti_double_pair' -Message 'The prohibited pair must bind Peng and crack discovery together.'
        }
        Assert-True ([string]$choice.no_boss_path_rule -match 'must remain available without defeating Peng Demon King') 'invalid_economy_v3_no_boss_path' 'The non-combat crack path must explicitly bypass Peng Demon King.'

        $segments = @($v3.progression_delta.ordered_route_segments)
        Assert-Equal $segments.Count 4 'invalid_economy_v3_segment_count' 'The future route must keep four ordered segments.'
        $expectedSegments = @(
            @{ id = 'before_choice'; selection = 'all_required'; keys = @('XP_INTRO', 'XP_MOUNTAIN', 'XP_WATERFALL', 'XP_MACAQUE', 'XP_PEACH', 'XP_CAVE', 'XP_SEVENSTAR') },
            @{ id = 'peng_or_crack'; selection = 'exactly_one'; keys = @('XP_PENG', 'XP_HG_CRACK_DISCOVERY') },
            @{ id = 'after_choice_before_clear'; selection = 'all_required'; keys = @('XP_EASTSEA', 'XP_JIAO', 'XP_SHARK') },
            @{ id = 'chapter_clear'; selection = 'all_required'; keys = @('XP_CHAPTER_CLEAR') }
        )
        foreach ($expectedSegment in $expectedSegments) {
            $segment = Get-SingleByProperty -Rows $segments -Property 'segment_id' -Value $expectedSegment.id -Code 'invalid_economy_v3_segment'
            if ($null -ne $segment) {
                Assert-Equal ([string]$segment.selection) $expectedSegment.selection 'invalid_economy_v3_segment_selection' "Segment '$($expectedSegment.id)' has an invalid selection rule."
                Assert-StringSetEqual -Actual @($segment.source_keys | ForEach-Object { [string]$_ }) -Expected $expectedSegment.keys -Code 'invalid_economy_v3_segment_sources' -Message "Segment '$($expectedSegment.id)' has invalid source keys."
            }
        }

        $beforeKeys = @('XP_INTRO', 'XP_MOUNTAIN', 'XP_WATERFALL', 'XP_MACAQUE', 'XP_PEACH', 'XP_CAVE', 'XP_SEVENSTAR')
        $afterKeys = @('XP_EASTSEA', 'XP_JIAO', 'XP_SHARK')
        $beforeChoiceXp = [int](($beforeKeys | ForEach-Object { $resolvedSources[$_] } | Measure-Object -Sum).Sum)
        $afterChoiceXp = [int](($afterKeys | ForEach-Object { $resolvedSources[$_] } | Measure-Object -Sum).Sum)
        $choiceXp = [int]$resolvedSources['XP_PENG']
        $crackXp = [int]$resolvedSources['XP_HG_CRACK_DISCOVERY']
        Assert-Equal $choiceXp $crackXp 'invalid_economy_v3_branch_equivalence' 'Peng and crack discovery must have equal XP.'
        Assert-Equal $beforeChoiceXp 3950 'invalid_economy_v3_before_choice_math' 'The preserved pre-choice total is invalid.'
        Assert-Equal $afterChoiceXp 3890 'invalid_economy_v3_after_choice_math' 'The repaired after-choice total is invalid.'
        Assert-Equal ($beforeChoiceXp + $choiceXp + $afterChoiceXp) 8340 'invalid_economy_v3_preclear_math' 'Each route branch must reach the Lv19 pre-clear anchor.'
        Assert-Equal ($beforeChoiceXp + $crackXp + $afterChoiceXp) 8340 'invalid_economy_v3_crack_preclear_math' 'The no-boss branch must reach the Lv19 pre-clear anchor.'
        Assert-Equal (($beforeChoiceXp + $choiceXp + $afterChoiceXp) + [int]$resolvedSources['XP_CHAPTER_CLEAR']) 9485 'invalid_economy_v3_final_math' 'The Peng branch must reach the Lv20 anchor.'
        Assert-Equal (($beforeChoiceXp + $crackXp + $afterChoiceXp) + [int]$resolvedSources['XP_CHAPTER_CLEAR']) 9485 'invalid_economy_v3_crack_final_math' 'The no-boss branch must reach the Lv20 anchor.'
        Assert-Equal ([int]$v3.progression_delta.route_math.before_choice_xp) $beforeChoiceXp 'invalid_economy_v3_recorded_before_choice_math' 'Recorded pre-choice math is stale.'
        Assert-Equal ([int]$v3.progression_delta.route_math.exactly_one_choice_xp) 500 'invalid_economy_v3_recorded_choice_math' 'Recorded branch XP is invalid.'
        Assert-Equal ([int]$v3.progression_delta.route_math.after_choice_before_clear_xp) $afterChoiceXp 'invalid_economy_v3_recorded_after_choice_math' 'Recorded after-choice math is stale.'
        Assert-Equal ([int]$v3.progression_delta.route_math.pre_clear_xp) 8340 'invalid_economy_v3_recorded_preclear_math' 'Recorded pre-clear math is invalid.'
        Assert-Equal ([int]$v3.progression_delta.route_math.chapter_clear_xp) 1145 'invalid_economy_v3_recorded_clear_math' 'Recorded chapter-clear math is invalid.'
        Assert-Equal ([int]$v3.progression_delta.route_math.final_xp) 9485 'invalid_economy_v3_recorded_final_math' 'Recorded final math is invalid.'

        Assert-Equal ([string]$lineage.contract_id) 'THREE_CHAPTER_GROWTH_LINEAGE_V1' 'invalid_lineage_contract_id' 'The three-chapter contract ID is invalid.'
        Assert-Equal ([bool]$lineage.runtime_handoff) $false 'invalid_lineage_runtime_gate' 'The lineage contract must not enable runtime handoff.'
        Assert-Equal ([string]$lineage.production_gate) 'closed' 'invalid_lineage_production_gate' 'The lineage contract must keep production closed.'
        Assert-Equal ([bool]$lineage.scope.design_route_only) $true 'invalid_lineage_design_route_scope' 'The lineage contract must remain a design route.'
        Assert-Null $lineage.scope.actual_source_profile_mapping 'invalid_lineage_actual_profile_mapping' 'The lineage contract must not create actual source-profile mappings.'
        Assert-Equal ([bool]$lineage.scope.actual_reward_execution) $false 'invalid_lineage_reward_execution' 'The lineage contract must not execute rewards.'
        Assert-Null $lineage.scope.runtime_keys 'invalid_lineage_runtime_keys' 'The lineage contract must not allocate runtime keys.'

        $routeChapters = @($lineage.level_20_to_60_route.chapters)
        $hg = Get-SingleByProperty -Rows $routeChapters -Property 'chapter_id' -Value 'HG' -Code 'invalid_lineage_hg_row'
        $df = Get-SingleByProperty -Rows $routeChapters -Property 'chapter_id' -Value 'DF' -Code 'invalid_lineage_df_row'
        $tt = Get-SingleByProperty -Rows $routeChapters -Property 'chapter_id' -Value 'TT' -Code 'invalid_lineage_tt_row'
        if ($null -ne $hg) {
            Assert-Equal ([int]$hg.exit_character_level) 20 'invalid_lineage_hg_exit_level' 'Huaguoshan must exit at Lv20.'
            Assert-Equal ([int]$hg.exit_cumulative_xp) 9485 'invalid_lineage_hg_exit_xp' 'Huaguoshan must exit at 9485 XP.'
            $hgFutureBindings = @($hg.future_mandatory_route_semantic_bindings)
            $expectedHgFutureBindings = @{
                'XP_PEACH' = 'HG_PEACH_GROVE_PUBLIC_MAINLINE'
                'XP_CAVE' = 'HG_BAT_CAVE_PUBLIC_MAINLINE'
            }
            Assert-StringSetEqual -Actual @($hgFutureBindings | ForEach-Object { [string]$_.source_key }) -Expected @($expectedHgFutureBindings.Keys) -Code 'invalid_lineage_hg_future_route_binding_set' -Message 'Huaguoshan lineage must repeat the two reviewed future mandatory public route bindings.'
            foreach ($sourceKey in $expectedHgFutureBindings.Keys) {
                $binding = Get-SingleByProperty -Rows $hgFutureBindings -Property 'source_key' -Value $sourceKey -Code 'invalid_lineage_hg_future_route_binding'
                if ($null -ne $binding) {
                    Assert-Equal ([string]$binding.future_route_node_id) ([string]$expectedHgFutureBindings[$sourceKey]) 'invalid_lineage_hg_future_route_node' "$sourceKey has an invalid Huaguoshan route node."
                    Assert-Equal ([string]$binding.future_route_semantics) 'mandatory_public_mainline' 'invalid_lineage_hg_future_route_semantics' "$sourceKey must remain a mandatory public mainline node."
                    Assert-Equal ([bool]$binding.required_for_regular_mainline_closure) $true 'invalid_lineage_hg_future_route_closure' "$sourceKey must remain required for Huaguoshan regular-mainline closure."
                    Assert-Null $binding.actual_source_profile 'invalid_lineage_hg_future_route_profile' "$sourceKey cannot allocate a real source profile."
                    Assert-Null $binding.runtime_mapping 'invalid_lineage_hg_future_route_runtime' "$sourceKey cannot allocate a runtime mapping."
                }
            }
        }
        if ($null -ne $df) {
            Assert-Equal ([int]$df.entry_character_level) 20 'invalid_lineage_df_entry_level' 'Difu must accept Lv20 entry.'
            Assert-StringSetEqual -Actual @($df.progression_level_band | ForEach-Object { [string]$_ }) -Expected @('21', '40') -Code 'invalid_lineage_df_band' -Message 'Difu progression band is invalid.'
            Assert-Equal ([int]$df.entry_cumulative_xp) 9485 'invalid_lineage_df_entry_xp' 'Difu must begin at 9485 XP.'
            Assert-Equal ([int]$df.successor_entry_character_level) 41 'invalid_lineage_df_tt_level' 'Difu must hand off to TianTing at Lv41.'
            Assert-Equal ([int]$df.successor_entry_cumulative_xp) 72515 'invalid_lineage_df_tt_xp' 'Difu must hand off at 72515 XP.'
            Assert-Equal ([int]$df.total_delta_xp) 63030 'invalid_lineage_df_total' 'Difu total XP envelope is invalid.'
            Assert-StringSetEqual -Actual @($df.entry_gate.forbidden | ForEach-Object { [string]$_ }) -Expected @('Peng Demon King clear', 'team clear', 'rare award', 'optional instance clear', 'tower XP') -Code 'invalid_lineage_df_nonblocking_gate' -Message 'Difu entry must not require optional, group, rare, or tower content.'
        }
        if ($null -ne $tt) {
            Assert-Equal ([int]$tt.entry_character_level) 41 'invalid_lineage_tt_entry_level' 'TianTing must require Lv41.'
            Assert-StringSetEqual -Actual @($tt.progression_level_band | ForEach-Object { [string]$_ }) -Expected @('41', '60') -Code 'invalid_lineage_tt_band' -Message 'TianTing progression band is invalid.'
            Assert-Equal ([int]$tt.entry_cumulative_xp) 72515 'invalid_lineage_tt_entry_xp' 'TianTing must begin at 72515 XP.'
            Assert-Equal ([int]$tt.final_character_level) 60 'invalid_lineage_tt_final_level' 'TianTing must finish at Lv60.'
            Assert-Equal ([int]$tt.final_cumulative_xp) 333300 'invalid_lineage_tt_final_xp' 'TianTing must finish at 333300 XP.'
            Assert-Equal ([int]$tt.total_delta_xp) 260785 'invalid_lineage_tt_total' 'TianTing total XP envelope is invalid.'
            Assert-StringSetEqual -Actual @($tt.entry_gate.forbidden | ForEach-Object { [string]$_ }) -Expected @('a raw Difu progress-key read', 'team clear', 'rare award', 'optional instance clear', 'tower XP') -Code 'invalid_lineage_tt_nonblocking_gate' -Message 'TianTing entry must not require optional, group, rare, or tower content.'
            Assert-True (@($tt.entry_gate.required | ForEach-Object { [string]$_ }) -contains 'one opaque authoritative Yanluo Hall success handoff proof for the same character') 'invalid_lineage_tt_yanluo_proof' 'TianTing must require the same-character Yanluo success proof.'
        }
        Assert-Equal ([string]$lineage.level_20_to_60_route.yanluo_handoff_boundary.producer_event) 'DF_E_YANLUO_HALL successful completion' 'invalid_lineage_yanluo_producer' 'Yanluo handoff producer is invalid.'
        Assert-Equal ([string]$lineage.level_20_to_60_route.yanluo_handoff_boundary.not_a_consumer_of) 'DF_PROGRESS_YANLUO_HALL_CLEARED raw runtime progress key' 'invalid_lineage_yanluo_key_consumer' 'TianTing may not read the raw Difu progress key.'
        Assert-Null $lineage.level_20_to_60_route.yanluo_handoff_boundary.runtime_mapping 'invalid_lineage_yanluo_runtime_mapping' 'Yanluo handoff must not add a runtime mapping.'

        $nodeMap = $lineage.design_route_node_map
        Assert-Equal ([string]$nodeMap.status) 'design-route-only' 'invalid_lineage_node_map_status' 'Design route node map must remain design-only.'
        Assert-Null $nodeMap.runtime_mapping 'invalid_lineage_node_map_runtime_mapping' 'Design route node map must not allocate a runtime mapping.'
        Assert-Equal ([string]$nodeMap.actual_source_profile_rule) 'Every listed node keeps actual_source_profile=null until a separately adopted chapter allocation maps an authority-attested source profile, count, rounding, and receipt contract.' 'invalid_lineage_node_map_profile_rule' 'Every node must keep its actual source profile deferred.'
        $mandatoryBudgetClasses = @('main_quest', 'public_normal', 'public_elite', 'public_boss', 'solo_instance')
        Assert-StringSetEqual -Actual @($nodeMap.permitted_mandatory_budget_classes | ForEach-Object { [string]$_ }) -Expected $mandatoryBudgetClasses -Code 'invalid_lineage_node_map_budget_classes' -Message 'Mandatory design nodes may use only existing main/public/solo budget classes.'
        Assert-Equal ([string]$nodeMap.node_value_rule) 'Every content node has allocated_xp=null and reward_values=null. The only numeric progression fact represented here is the already frozen minimum 1250 XP transition from Lv20 to Lv21 at the Ghost City opening; it is a gate threshold, not a newly allocated reward value.' 'invalid_lineage_node_map_value_rule' 'Node map must prohibit new reward values.'

        $mapChapters = @($nodeMap.chapters)
        $dfMapChapter = Get-SingleByProperty -Rows $mapChapters -Property 'chapter_id' -Value 'DF' -Code 'invalid_lineage_df_node_map'
        $ttMapChapter = Get-SingleByProperty -Rows $mapChapters -Property 'chapter_id' -Value 'TT' -Code 'invalid_lineage_tt_node_map'
        $expectedDfNodeIds = @('DF_ENTRY_HG_HANDOFF_LV20', 'DF_GHOST_CITY_OPENING', 'DF_WUCHANG_ALLEY', 'DF_GHOST_GATE', 'DF_RECEPTION_COURTYARD', 'DF_JUDGE_HALL', 'DF_YANLUO_HALL')
        $expectedTtNodeIds = @('TT_ENTRY_LV41_YANLUO_HANDOFF', 'TT_RIFT_NANTIAN_GATE', 'TT_BROKEN_RAINBOW_FORMATION', 'TT_FOUR_GATES_IMBALANCE', 'TT_ZHOUTIAN_OBSERVATORY', 'TT_LINGXIAO_OUTER_COURT')
        foreach ($mapShape in @(
            @{ chapter = $dfMapChapter; expectedNodeIds = $expectedDfNodeIds; entryNode = 'DF_ENTRY_HG_HANDOFF_LV20'; ghostNode = 'DF_GHOST_CITY_OPENING' },
            @{ chapter = $ttMapChapter; expectedNodeIds = $expectedTtNodeIds; entryNode = 'TT_ENTRY_LV41_YANLUO_HANDOFF'; ghostNode = $null }
        )) {
            if ($null -ne $mapShape.chapter) {
                $nodes = @($mapShape.chapter.mandatory_ordered_nodes)
                Assert-StringSequenceEqual -Actual @($nodes | ForEach-Object { [string]$_.node_id }) -Expected $mapShape.expectedNodeIds -Code 'invalid_lineage_node_map_order' -Message "Mandatory node order for '$($mapShape.chapter.chapter_id)' is invalid."
                for ($index = 0; $index -lt $nodes.Count; $index += 1) {
                    $node = $nodes[$index]
                    Assert-Equal ([int]$node.order) ($index + 1) 'invalid_lineage_node_map_order_number' "Node '$($node.node_id)' has an invalid order number."
                    Assert-Equal ([bool]$node.mandatory) $true 'invalid_lineage_node_map_mandatory' "Node '$($node.node_id)' must remain mandatory in the explicit mainline order."
                    Assert-Null $node.actual_source_profile 'invalid_lineage_node_map_actual_profile' "Node '$($node.node_id)' must not allocate a real source profile."
                    Assert-Null $node.allocated_xp 'invalid_lineage_node_map_allocated_xp' "Node '$($node.node_id)' must not allocate a concrete XP reward."
                    Assert-Null $node.reward_values 'invalid_lineage_node_map_reward_values' "Node '$($node.node_id)' must not allocate reward values."
                    if ($node.node_id -eq $mapShape.entryNode) {
                        Assert-StringSetEqual -Actual @($node.permitted_budget_classes | ForEach-Object { [string]$_ }) -Expected @() -Code 'invalid_lineage_node_map_entry_budget_classes' -Message "Entry node '$($node.node_id)' may not become an XP source."
                        Assert-Equal ([string]$node.node_kind) 'chapter_entry_gate' 'invalid_lineage_node_map_entry_kind' "Entry node '$($node.node_id)' must remain a chapter gate."
                    }
                    else {
                        Assert-StringSetEqual -Actual @($node.permitted_budget_classes | ForEach-Object { [string]$_ }) -Expected $mandatoryBudgetClasses -Code 'invalid_lineage_node_map_content_budget_classes' -Message "Content node '$($node.node_id)' may use only main/public/solo budget classes."
                        Assert-True (-not (@($node.permitted_budget_classes | ForEach-Object { [string]$_ }) -contains 'team_instance')) 'invalid_lineage_node_map_team_budget' "Mandatory node '$($node.node_id)' must never consume team-instance budget."
                    }
                }
            }
        }
        if ($null -ne $dfMapChapter) {
            $dfNodes = @($dfMapChapter.mandatory_ordered_nodes)
            $dfEntry = Get-SingleByProperty -Rows $dfNodes -Property 'node_id' -Value 'DF_ENTRY_HG_HANDOFF_LV20' -Code 'invalid_lineage_df_node_map_entry'
            $dfGhostCity = Get-SingleByProperty -Rows $dfNodes -Property 'node_id' -Value 'DF_GHOST_CITY_OPENING' -Code 'invalid_lineage_df_node_map_ghost_city'
            if ($null -ne $dfEntry) {
                Assert-StringSetEqual -Actual @($dfEntry.entry_requirements | ForEach-Object { [string]$_ }) -Expected @('same-character opaque Huaguoshan regular-mainline completion handoff proof', 'character level is at least 20') -Code 'invalid_lineage_df_node_map_entry_requirements' -Message 'Difu entry must require same-character Huaguoshan proof and Lv20.'
            }
            if ($null -ne $dfGhostCity) {
                Assert-Equal ([int]$dfGhostCity.known_level_transition.from_level) 20 'invalid_lineage_df_ghost_city_from_level' 'Ghost City must start at Lv20.'
                Assert-Equal ([int]$dfGhostCity.known_level_transition.to_level) 21 'invalid_lineage_df_ghost_city_to_level' 'Ghost City must cross to Lv21.'
                Assert-Equal ([int]$dfGhostCity.known_level_transition.minimum_xp_threshold) 1250 'invalid_lineage_df_ghost_city_threshold' 'Ghost City must retain the existing 1250 XP Lv20-to-Lv21 threshold.'
            }
            foreach ($node in @($dfNodes | Where-Object { $_.node_id -ne 'DF_GHOST_CITY_OPENING' })) {
                if ($node.PSObject.Properties.Name -contains 'known_level_transition') {
                    Assert-Null $node.known_level_transition 'invalid_lineage_df_extra_level_threshold' "Only Ghost City may name the known Lv20-to-Lv21 threshold."
                }
            }
        }
        if ($null -ne $ttMapChapter) {
            $ttNodes = @($ttMapChapter.mandatory_ordered_nodes)
            $ttEntry = Get-SingleByProperty -Rows $ttNodes -Property 'node_id' -Value 'TT_ENTRY_LV41_YANLUO_HANDOFF' -Code 'invalid_lineage_tt_node_map_entry'
            if ($null -ne $ttEntry) {
                Assert-StringSetEqual -Actual @($ttEntry.entry_requirements | ForEach-Object { [string]$_ }) -Expected @('character level is at least 41', 'one opaque authoritative Yanluo Hall success handoff proof for the same character') -Code 'invalid_lineage_tt_node_map_entry_requirements' -Message 'TianTing entry must require Lv41 plus same-character opaque Yanluo proof.'
            }
        }

        $nonMandatoryContent = @($nodeMap.non_mandatory_or_zero_xp_content)
        $expectedNonMandatoryTreatments = @{
            'DF_SIDE_BAIGU_SECRET_REALM' = 'nonblocking_equal_value_substitution_only'
            'DF_E_ZHUANLUN_HALL' = 'nonblocking_equal_value_substitution_only'
            'TT_SEVEN_STAR_SERIES' = 'nonblocking_equal_value_substitution_only'
            'TT_MANSION_NORMAL_AND_NIGHTMARE' = 'nonblocking_equal_value_substitution_only'
            'RARE_AWARD_PATHS' = 'nonblocking_equal_value_substitution_only'
            'GLOBAL_TONGTIAN_TOWER' = 'zero_xp'
        }
        Assert-StringSetEqual -Actual @($nonMandatoryContent | ForEach-Object { [string]$_.content_id }) -Expected @($expectedNonMandatoryTreatments.Keys) -Code 'invalid_lineage_node_map_nonmandatory_set' -Message 'White Bone, Turnwheel, Seven Star, mansions, rare paths, and tower must stay explicitly non-mandatory or zero-XP.'
        foreach ($content in $nonMandatoryContent) {
            $contentId = [string]$content.content_id
            if ($expectedNonMandatoryTreatments.ContainsKey($contentId)) {
                Assert-Equal ([string]$content.progression_treatment) $expectedNonMandatoryTreatments[$contentId] 'invalid_lineage_node_map_nonmandatory_treatment' "Progression treatment for '$contentId' is invalid."
            }
            Assert-Null $content.actual_source_profile 'invalid_lineage_node_map_nonmandatory_profile' "Non-mandatory content '$contentId' must not allocate a real source profile."
            Assert-StringSetEqual -Actual @($content.permitted_budget_classes | ForEach-Object { [string]$_ }) -Expected @() -Code 'invalid_lineage_node_map_nonmandatory_budget' -Message "Non-mandatory content '$contentId' may not pre-allocate a budget class."
            Assert-Null $content.reward_values 'invalid_lineage_node_map_nonmandatory_rewards' "Non-mandatory content '$contentId' must not allocate reward values."
            if ($contentId -eq 'GLOBAL_TONGTIAN_TOWER') {
                Assert-Equal ([int]$content.allocated_xp) 0 'invalid_lineage_node_map_tower_xp' 'Global Tongtian Tower must stay at zero XP.'
            }
            else {
                Assert-Null $content.allocated_xp 'invalid_lineage_node_map_nonmandatory_xp' "Non-mandatory content '$contentId' must not allocate concrete XP."
            }
        }
        Assert-Equal ([string]$nodeMap.anti_forced_content_rule) 'No listed non-mandatory content may become an entry gate, a mandatory-node predecessor, a mandatory-final-residual recipient, or a double-counted XP path. Equal-value substitution remains a future allocation requirement, not an award instruction.' 'invalid_lineage_node_map_anti_forced_rule' 'Node map must explicitly reject forced optional/group/rare/tower content.'

        $budget = $lineage.difu_and_tianting_budget_contract
        Assert-Null $budget.source_profile_mapping.value 'invalid_lineage_budget_profile_mapping' 'DF/TT budget envelopes must not create source-profile mappings.'
        $v2Weights = @{}
        foreach ($weight in @($v2.progression.future_chapter_source_budget_basis_points)) {
            $v2Weights[[string]$weight.source_kind] = [int]$weight.weight_basis_points
        }
        $contractWeights = @{}
        foreach ($weight in @($budget.weights_basis_points)) {
            $contractWeights[[string]$weight.source_kind] = [int]$weight.weight_basis_points
        }
        Assert-StringSetEqual -Actual @($contractWeights.Keys) -Expected @($v2Weights.Keys) -Code 'invalid_lineage_budget_weight_keys' -Message 'Lineage weights must equal the existing economy-v2 source-kind budget.'
        foreach ($key in $v2Weights.Keys) {
            if ($contractWeights.ContainsKey($key)) {
                Assert-Equal $contractWeights[$key] $v2Weights[$key] 'invalid_lineage_budget_weight' "Weight for '$key' differs from economy-v2."
            }
        }
        Assert-Equal ([int](($contractWeights.Values | Measure-Object -Sum).Sum)) 10000 'invalid_lineage_budget_weight_sum' 'Budget weights must sum to 10000 basis points.'

        $envelopes = @($budget.chapter_budget_envelopes)
        foreach ($expectedEnvelope in @(@{ id = 'DF'; total = 63030; residual = 4 }, @{ id = 'TT'; total = 260785; residual = 5 })) {
            $envelope = Get-SingleByProperty -Rows $envelopes -Property 'chapter_id' -Value $expectedEnvelope.id -Code 'invalid_lineage_budget_envelope'
            if ($null -ne $envelope) {
                Assert-Equal ([int]$envelope.total_delta_xp) $expectedEnvelope.total 'invalid_lineage_budget_total' "Budget total for '$($expectedEnvelope.id)' is invalid."
                $sourceRows = @($envelope.source_kind_amounts_before_residual)
                Assert-StringSetEqual -Actual @($sourceRows | ForEach-Object { [string]$_.source_kind }) -Expected @($v2Weights.Keys) -Code 'invalid_lineage_budget_rows' -Message "Budget source rows for '$($expectedEnvelope.id)' are invalid."
                $computedSum = 0
                foreach ($sourceRow in $sourceRows) {
                    $sourceKind = [string]$sourceRow.source_kind
                    if ($v2Weights.ContainsKey($sourceKind)) {
                        $expectedAmount = [int][math]::Floor(([double]$expectedEnvelope.total * [double]$v2Weights[$sourceKind]) / 10000.0)
                        Assert-Equal ([int]$sourceRow.amount) $expectedAmount 'invalid_lineage_budget_amount' "Budget amount for '$($expectedEnvelope.id)/$sourceKind' is invalid."
                        $computedSum += [int]$sourceRow.amount
                    }
                }
                Assert-Equal $computedSum ([int]$envelope.rounded_sum_before_residual) 'invalid_lineage_budget_rounded_sum' "Recorded rounded sum for '$($expectedEnvelope.id)' is invalid."
                Assert-Equal ([int]$envelope.mandatory_final_mainline_residual) ($expectedEnvelope.total - $computedSum) 'invalid_lineage_budget_residual_math' "Residual for '$($expectedEnvelope.id)' is invalid."
                Assert-Equal ([int]$envelope.mandatory_final_mainline_residual) $expectedEnvelope.residual 'invalid_lineage_budget_residual' "Expected residual for '$($expectedEnvelope.id)' is invalid."
                Assert-Equal ($computedSum + [int]$envelope.mandatory_final_mainline_residual) ([int]$envelope.resolved_total_delta_xp) 'invalid_lineage_budget_resolved_total' "Resolved total for '$($expectedEnvelope.id)' is invalid."
                Assert-Equal ([int]$envelope.resolved_total_delta_xp) $expectedEnvelope.total 'invalid_lineage_budget_total_reconciliation' "Budget for '$($expectedEnvelope.id)' does not reconcile."
                $towerRow = Get-SingleByProperty -Rows $sourceRows -Property 'source_kind' -Value 'tower' -Code 'invalid_lineage_budget_tower_row'
                if ($null -ne $towerRow) {
                    Assert-Equal ([int]$towerRow.amount) 0 'invalid_lineage_budget_tower_xp' "Tower must grant zero chapter XP in '$($expectedEnvelope.id)'."
                }
            }
        }
        Assert-Equal ([string]$budget.node_and_substitution_rules.mandatory_completion_node_class) 'main_quest' 'invalid_lineage_mandatory_node_class' 'Main quest must remain the mandatory completion node class.'
        Assert-Equal ([string]$budget.node_and_substitution_rules.mandatory_final_residual_node_class) 'mandatory_final_mainline' 'invalid_lineage_final_residual_node' 'Residual must remain on the final mainline node.'
        Assert-StringSetEqual -Actual @($budget.node_and_substitution_rules.non_blocking_node_classes | ForEach-Object { [string]$_ }) -Expected @('team_instance', 'rare_award', 'optional_instance', 'tower') -Code 'invalid_lineage_nonblocking_nodes' -Message 'Team, rare, optional, and tower nodes must remain non-blocking.'
        Assert-StringSetEqual -Actual @($budget.node_and_substitution_rules.non_blocking_source_budget_classes | ForEach-Object { [string]$_ }) -Expected @('side_quest', 'team_instance', 'repeat_clear', 'tower') -Code 'invalid_lineage_nonblocking_source_budget_classes' -Message 'Side, team, repeat, and tower budget classes must never become mandatory content.'
        Assert-Equal ([string]$budget.node_and_substitution_rules.first_clear_attachment_rule) 'A first_clear budget may attach only to an authority-available mandatory mainline, public, or solo node as its one-time settlement qualifier. It cannot name optional, rare, team, repeat, or tower content as a chapter prerequisite.' 'invalid_lineage_first_clear_attachment_rule' 'First-clear budget may only qualify an authority-available mandatory node.'
        Assert-True ([string]$budget.node_and_substitution_rules.substitution_rule -match 'side_quest, team_instance, repeat_clear, tower') 'invalid_lineage_substitution_nonblocking_scope' 'The substitution rule must explicitly cover side, team, repeat, and tower budgets.'
        Assert-Equal ([string]$budget.node_and_substitution_rules.tower_rule) 'Tower has zero XP in both chapter envelopes and cannot satisfy a chapter level gate.' 'invalid_lineage_tower_rule' 'Tower XP rule is invalid.'

        $matrix = $lineage.equipment_and_artifact_stage_matrix
        Assert-Equal ([string]$matrix.artifact_slot_contract.version) 'v1' 'invalid_lineage_artifact_slot_version' 'Artifact-slot contract version is invalid.'
        Assert-Equal ([int]$matrix.artifact_slot_contract.active_artifact_slot_count) 1 'invalid_lineage_artifact_slot_count' 'v1 must have one active artifact slot.'
        Assert-Equal @($matrix.artifact_slot_contract.mainline_required_artifact_keys).Count 0 'invalid_lineage_artifact_mainline_requirement' 'No artifact may be mainline-required.'
        Assert-Equal @($matrix.artifact_slot_contract.entry_gate_required_artifact_keys).Count 0 'invalid_lineage_artifact_entry_requirement' 'No artifact may be an entry gate.'
        $stages = @($matrix.stages)
        $hgPublic = Get-SingleByProperty -Rows $stages -Property 'stage_id' -Value 'HG_PUBLIC_BASELINE' -Code 'invalid_lineage_hg_public_stage'
        $hgRareTrinket = Get-SingleByProperty -Rows $stages -Property 'stage_id' -Value 'HG_PUBLIC_RARE_TRINKET' -Code 'invalid_lineage_hg_rare_trinket_stage'
        $hgTeam = Get-SingleByProperty -Rows $stages -Property 'stage_id' -Value 'HG_TEAM_OPTIONAL_SET' -Code 'invalid_lineage_hg_team_stage'
        $hgArtifacts = Get-SingleByProperty -Rows $stages -Property 'stage_id' -Value 'HG_ARTIFACT_CHOICES' -Code 'invalid_lineage_hg_artifact_stage'
        $dfStage = Get-SingleByProperty -Rows $stages -Property 'stage_id' -Value 'DF_MIDGAME' -Code 'invalid_lineage_df_stage'
        $ttStage = Get-SingleByProperty -Rows $stages -Property 'stage_id' -Value 'TT_ENDGAME' -Code 'invalid_lineage_tt_stage'
        if ($null -ne $hgPublic) {
            Assert-StringSetEqual -Actual @($hgPublic.logical_equipment_keys | ForEach-Object { [string]$_ }) -Expected @('EQ_HG_WEAPON_T1', 'EQ_HG_ARMOR_T1', 'EQ_HG_RING_T1') -Code 'invalid_lineage_hg_public_equipment' -Message 'Huaguoshan public first-clear equipment keys are invalid.'
            Assert-Equal ([bool]$hgPublic.mainline_required) $false 'invalid_lineage_hg_public_mandatory' 'Public baseline gear must not be a mainline requirement.'
            Assert-Null $hgPublic.stats 'invalid_lineage_hg_public_stats' 'No equipment stats may be invented here.'
        }
        if ($null -ne $hgRareTrinket) {
            Assert-StringSetEqual -Actual @($hgRareTrinket.logical_equipment_keys | ForEach-Object { [string]$_ }) -Expected @('EQ_HG_TRINKET_T1') -Code 'invalid_lineage_hg_rare_trinket_equipment' -Message 'Huaguoshan public rare trinket key is invalid.'
            Assert-Equal ([bool]$hgRareTrinket.mainline_required) $false 'invalid_lineage_hg_rare_trinket_mandatory' 'The public rare trinket must not be a mainline requirement.'
            Assert-Null $hgRareTrinket.stats 'invalid_lineage_hg_rare_trinket_stats' 'No rare trinket stats may be invented here.'
            Assert-True ([string]$hgRareTrinket.acquisition_boundary -match 'rare') 'invalid_lineage_hg_rare_trinket_boundary' 'The public rare trinket must retain its rare acquisition boundary.'
        }
        if ($null -ne $hgTeam) {
            Assert-StringSetEqual -Actual @($hgTeam.logical_equipment_keys | ForEach-Object { [string]$_ }) -Expected @('EQ_HG_SET_GUARD_T1') -Code 'invalid_lineage_hg_team_equipment' -Message 'Huaguoshan team set key is invalid.'
            Assert-Equal ([bool]$hgTeam.mainline_required) $false 'invalid_lineage_hg_team_mandatory' 'Team set must not be a mainline requirement.'
        }
        if ($null -ne $hgArtifacts) {
            $artifacts = @($hgArtifacts.artifacts)
            Assert-StringSetEqual -Actual @($artifacts | ForEach-Object { [string]$_.logical_artifact_key }) -Expected @('ART_HG_TIDE_SEAL', 'ART_HG_FLAME_CORE') -Code 'invalid_lineage_hg_artifact_keys' -Message 'Huaguoshan artifact keys are invalid.'
            foreach ($artifact in $artifacts) {
                Assert-Equal ([bool]$artifact.mainline_required) $false 'invalid_lineage_hg_artifact_mandatory' "Artifact '$($artifact.logical_artifact_key)' must remain optional."
                Assert-Null $artifact.stats 'invalid_lineage_hg_artifact_stats' "Artifact '$($artifact.logical_artifact_key)' cannot receive invented stats."
                Assert-Null $artifact.upgrade_recipe 'invalid_lineage_hg_artifact_recipe' "Artifact '$($artifact.logical_artifact_key)' cannot receive an invented upgrade recipe."
            }
        }
        foreach ($deferredStage in @($dfStage, $ttStage)) {
            if ($null -ne $deferredStage) {
                Assert-Null $deferredStage.logical_equipment_keys 'invalid_lineage_deferred_equipment' "Deferred stage '$($deferredStage.stage_id)' cannot allocate equipment keys."
                Assert-Null $deferredStage.logical_artifact_keys 'invalid_lineage_deferred_artifacts' "Deferred stage '$($deferredStage.stage_id)' cannot allocate artifact keys."
                Assert-Null $deferredStage.source_profile_mapping 'invalid_lineage_deferred_profiles' "Deferred stage '$($deferredStage.stage_id)' cannot allocate source profiles."
                Assert-Null $deferredStage.stats 'invalid_lineage_deferred_stats' "Deferred stage '$($deferredStage.stage_id)' cannot allocate stats."
            }
        }

        $resources = @($lineage.currency_material_and_receipt_boundary.resource_family_matrix)
        Assert-StringSetEqual -Actual @($resources | ForEach-Object { [string]$_.logical_key }) -Expected @('CUR_GOLD', 'CUR_RAID_MARK', 'CUR_TOWER_TOKEN', 'MAT_STRENGTHEN_SHARD', 'MAT_ADVANCE_HG', 'MAT_ARTIFACT_DUST') -Code 'invalid_lineage_resource_keys' -Message 'Currency/material lineage keys are invalid.'
        foreach ($materialKey in @('MAT_STRENGTHEN_SHARD', 'MAT_ADVANCE_HG', 'MAT_ARTIFACT_DUST')) {
            $material = Get-SingleByProperty -Rows $resources -Property 'logical_key' -Value $materialKey -Code 'invalid_lineage_material_row'
            if ($null -ne $material) {
                Assert-Equal ([string]$material.kind) 'material' 'invalid_lineage_material_kind' "'$materialKey' must remain a material."
                Assert-Equal ([string]$material.bind_rule) 'character_bound' 'invalid_lineage_material_bind' "'$materialKey' must remain character-bound."
            }
        }
        $receiptBoundary = $lineage.currency_material_and_receipt_boundary.receipt_boundary
        Assert-Equal ([string]$receiptBoundary.owner_scope) 'character' 'invalid_lineage_receipt_owner_scope' 'Resource lineage must remain character-scoped.'
        Assert-Equal ([string]$receiptBoundary.team_wallet) 'disabled' 'invalid_lineage_team_wallet' 'Team wallet must remain disabled.'
        Assert-Equal ([string]$receiptBoundary.trade) 'disabled' 'invalid_lineage_trade' 'Trade must remain disabled.'
        Assert-Equal ([bool]$receiptBoundary.design_contract_may_create_receipt) $false 'invalid_lineage_receipt_execution' 'Lineage contract must not create receipts.'

        $legacyCandidates = @($lineage.legacy_candidate_boundary)
        Assert-Equal $legacyCandidates.Count 3 'invalid_lineage_legacy_candidate_count' 'Exactly three legacy candidates are tracked here.'
        foreach ($legacyCandidate in $legacyCandidates) {
            Assert-Equal ([string]$legacyCandidate.status) 'candidate_only' 'invalid_lineage_legacy_candidate_status' "Legacy candidate '$($legacyCandidate.candidate)' must remain a candidate."
            Assert-Equal ([bool]$legacyCandidate.current_mandatory_chain) $false 'invalid_lineage_legacy_candidate_mandatory' "Legacy candidate '$($legacyCandidate.candidate)' must not become mandatory."
            Assert-Null $legacyCandidate.current_reward_source 'invalid_lineage_legacy_candidate_source' "Legacy candidate '$($legacyCandidate.candidate)' must not claim a current reward source."
        }

        $forbiddenRuntimeProperties = @{
            'runtime_key' = $true
            'object_id' = $true
            'y3_object_id' = $true
            'save_key' = $true
            'storage_key' = $true
            'materializer' = $true
            'receipt_execution' = $true
            'award_execution' = $true
            'ledger_write' = $true
            'currency_mint' = $true
            'currency_spend' = $true
            'production_endpoint' = $true
        }
        $forbiddenPaths = @()
        $forbiddenPaths += @(Get-ForbiddenPropertyPaths -Node $v3 -Path 'economy-v3' -Forbidden $forbiddenRuntimeProperties)
        $forbiddenPaths += @(Get-ForbiddenPropertyPaths -Node $lineage -Path 'three-chapter-lineage' -Forbidden $forbiddenRuntimeProperties)
        Assert-Equal $forbiddenPaths.Count 0 'forbidden_runtime_or_execution_key' "Offline contracts contain forbidden runtime/economic execution keys: $($forbiddenPaths -join ', ')."
    }
}

if ($script:Failures.Count -gt 0) {
    foreach ($failure in $script:Failures) {
        Write-Error $failure
    }
    throw "Three-chapter growth continuity validation failed with $($script:Failures.Count) error(s)."
}

if (-not $Quiet) {
    Write-Host 'PASS: three-chapter growth continuity contract is internally consistent, version-pinned, non-production, and non-executable.'
}
