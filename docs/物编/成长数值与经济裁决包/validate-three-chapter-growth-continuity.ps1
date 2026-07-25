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

function Decode-Utf8Base64 {
    param(
        [Parameter(Mandatory = $true)][string]$Value
    )

    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

$packageRoot = Split-Path -Parent $PSCommandPath
$v2Path = Join-Path $packageRoot 'tables/economy-v2-resource-table.json'
$v3Path = Join-Path $packageRoot 'tables/economy-v3-resource-table.json'
$lineagePath = Join-Path $packageRoot 'three-chapter-growth-lineage-contract.json'
$difuArtifactDirectory = Decode-Utf8Base64 '5Zyw5bqc5Lit5pyf5rOV5a6d6KOB5Yaz5YyF'
$difuArtifactFileName = 'difu-midgame-artifact-positioning-and-replacement-contract.json'
$difuArtifactRelativePath = "$difuArtifactDirectory/$difuArtifactFileName"
$difuArtifactPath = Join-Path (Join-Path $packageRoot $difuArtifactDirectory) $difuArtifactFileName
$difuArtifactDetailDirectory = Join-Path $difuArtifactDirectory 'two-artifact-detail'
$difuArtifactDetailFileName = 'difu-two-artifact-detailed-design-contract.json'
$difuArtifactDetailRelativePath = "$difuArtifactDirectory/two-artifact-detail/$difuArtifactDetailFileName"
$difuArtifactDetailPath = Join-Path (Join-Path $packageRoot $difuArtifactDetailDirectory) $difuArtifactDetailFileName
$tiantingArtifactDirectory = Decode-Utf8Base64 '5aSp5bqt56+H5Li757q/6YGt6YGH5LiO6YCa5aSp5aGU6KeE5qC85YyF'
$tiantingArtifactFileName = 'tianting-endgame-artifact-positioning-and-lineage-contract.json'
$tiantingArtifactRelativePath = "../$tiantingArtifactDirectory/artifact-graduation/$tiantingArtifactFileName"
$tiantingArtifactPath = Join-Path (Join-Path (Join-Path (Split-Path -Parent $packageRoot) $tiantingArtifactDirectory) 'artifact-graduation') $tiantingArtifactFileName
$tiantingArtifactCompleteDesignFileName = 'tianting-graduation-artifact-complete-design-contract.json'
$tiantingArtifactCompleteDesignRelativePath = "../$tiantingArtifactDirectory/artifact-graduation/complete-design/$tiantingArtifactCompleteDesignFileName"
$tiantingArtifactCompleteDesignPath = Join-Path (Join-Path (Join-Path (Join-Path (Split-Path -Parent $packageRoot) $tiantingArtifactDirectory) 'artifact-graduation') 'complete-design') $tiantingArtifactCompleteDesignFileName
$threeChapterArtifactDetailDirectory = Decode-Utf8Base64 '5LiJ56+H5rOV5a6d6K+m57uG6K6+6K6h5LiO5p2Q5paZ5p2l5rqQ5YyF'
$threeChapterArtifactDetailFileName = 'three-chapter-artifact-detail-and-material-source-contract.json'
$threeChapterArtifactDetailRelativePath = "$threeChapterArtifactDetailDirectory/$threeChapterArtifactDetailFileName"
$threeChapterArtifactDetailPath = Join-Path (Join-Path $packageRoot $threeChapterArtifactDetailDirectory) $threeChapterArtifactDetailFileName
$dfArtifactCombatGrammar = Decode-Utf8Base64 '5ZG95YaM6K+B5o2uIOKGkiDoo4HlhrMg4oaSIOWbnuatow=='
$dfArtifactAtomicSwitchToken = Decode-Utf8Base64 '5Y6f5a2Q'
$dfArtifactChallengeLockToken = Decode-Utf8Base64 '5oyR5oiY6ZSB'
$dfArtifactPrimaryAxisToken = Decode-Utf8Base64 '5LiA5Liq5Li75Yqf6IO96L20'
$dfArtifactNoLegacyToken = Decode-Utf8Base64 '5pyq5oul5pyJ5Lu75L2V6Iqx5p6c5bGx5rOV5a6d'
$dfArtifactDetailLanternName = Decode-Utf8Base64 '6ZWH6a2C5byV54Gv'
$dfArtifactDetailMirrorName = Decode-Utf8Base64 '5YuY5ZG95Lia6ZWc'
$expectedDfArtifactForbiddenSources = @(
    (Decode-Utf8Base64 '6Iqx5p6c5bGx6ZqQ6JeP5pys6aaW6YCa'),
    (Decode-Utf8Base64 '6Iqx5p6c5bGx56iA5pyJ5o6J6JC9'),
    (Decode-Utf8Base64 '55m96aqo56eY5aKD'),
    (Decode-Utf8Base64 '6L2s6L2u5q6/5Zui6Zif5a6M5oiQ'),
    (Decode-Utf8Base64 '56iA5pyJ5aWW5Yqx'),
    (Decode-Utf8Base64 '6YeN5aSN5oyR5oiY'),
    (Decode-Utf8Base64 '6YCa5aSp5aGU')
)
$dfArtifactSilentLegacyDestruction = Decode-Utf8Base64 '6Ieq5Yqo5raI6ICX44CB5Yig6Zmk44CB6ZmN57qn5oiW5peg6K6w5b2V6L2s5YyW6Iqx5p6c5bGx5rOV5a6d'
$tiantingArtifactDisplayName = Decode-Utf8Base64 '5ZGo5aSp5qCh5b6L55uY'
$expectedV2Hash = '3288BD9CD1BFBB516DB4808EF002C45FECCF5F1C7F4C80499DB81E31B2F84EAE'

foreach ($path in @($v2Path, $v3Path, $lineagePath, $difuArtifactPath, $difuArtifactDetailPath, $tiantingArtifactPath, $tiantingArtifactCompleteDesignPath, $threeChapterArtifactDetailPath)) {
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
    $difuArtifact = Get-Json $difuArtifactPath
    $difuArtifactDetail = Get-Json $difuArtifactDetailPath
    $tiantingArtifact = Get-Json $tiantingArtifactPath
    $tiantingArtifactCompleteDesign = Get-Json $tiantingArtifactCompleteDesignPath
    $threeChapterArtifactDetail = Get-Json $threeChapterArtifactDetailPath

    if ($null -ne $v2 -and $null -ne $v3 -and $null -ne $lineage -and $null -ne $difuArtifact -and $null -ne $difuArtifactDetail -and $null -ne $tiantingArtifact -and $null -ne $tiantingArtifactCompleteDesign -and $null -ne $threeChapterArtifactDetail) {
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
        $threeChapterArtifactDetailRef = $matrix.artifact_detail_and_material_source_contract
        Assert-Equal ([string]$threeChapterArtifactDetailRef.contract_id) 'THREE_CHAPTER_ARTIFACT_DETAIL_AND_MATERIAL_SOURCE_V1' 'invalid_lineage_three_chapter_artifact_detail_id' 'The lineage must reference the canonical three-chapter artifact detail contract.'
        Assert-Equal ([string]$threeChapterArtifactDetailRef.path) $threeChapterArtifactDetailRelativePath 'invalid_lineage_three_chapter_artifact_detail_path' 'The three-chapter artifact detail path is invalid.'
        Assert-Equal ([string]$threeChapterArtifactDetailRef.status) 'accepted-offline-design' 'invalid_lineage_three_chapter_artifact_detail_status' 'The three-chapter artifact detail contract must remain offline-only.'
        Assert-Equal ([int]$threeChapterArtifactDetailRef.artifact_spec_count) 5 'invalid_lineage_three_chapter_artifact_detail_count' 'The three-chapter artifact detail contract must retain exactly five artifact specs.'
        foreach ($propertyName in @('actual_item_assets', 'actual_material_keys', 'material_quantities', 'recipes', 'combat_stats', 'source_profiles', 'receipts')) {
            Assert-Null $threeChapterArtifactDetailRef.$propertyName 'invalid_lineage_three_chapter_artifact_detail_deferred' "The three-chapter artifact detail reference cannot allocate '$propertyName'."
        }
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
        if ($null -ne $dfStage) {
            Assert-Equal ([string]$dfStage.replacement_or_upgrade_rule) 'delegated_to_DF_SPEC_MIDGAME_ARTIFACT_POSITIONING_REPLACEMENT_V1' 'invalid_lineage_df_artifact_replacement_delegate' 'Difu replacement behavior must remain delegated to the dedicated offline contract.'
            $dfPositioning = $dfStage.artifact_positioning_contract
            Assert-Equal ([string]$dfPositioning.contract_id) 'DF_SPEC_MIDGAME_ARTIFACT_POSITIONING_REPLACEMENT_V1' 'invalid_lineage_df_artifact_contract_id' 'Difu must reference the dedicated artifact positioning contract.'
            Assert-Equal ([string]$dfPositioning.path) $difuArtifactRelativePath 'invalid_lineage_df_artifact_contract_path' 'Difu artifact positioning path is invalid.'
            Assert-Equal ([string]$dfPositioning.status) 'accepted-offline-design' 'invalid_lineage_df_artifact_contract_status' 'Difu artifact positioning contract must remain offline-only.'
            Assert-Equal ([string]$dfPositioning.tier) 'medium' 'invalid_lineage_df_artifact_tier' 'Difu artifact stage must be medium tier.'
            Assert-Null $dfPositioning.actual_logical_artifact_keys 'invalid_lineage_df_artifact_asset_keys' 'Difu positioning cannot allocate actual artifact keys.'
            Assert-Null $dfPositioning.source_profile_mapping 'invalid_lineage_df_artifact_profile' 'Difu positioning cannot allocate source profiles.'
            Assert-Null $dfPositioning.stats 'invalid_lineage_df_artifact_stats' 'Difu positioning cannot allocate stats.'
            Assert-Null $dfPositioning.recipes 'invalid_lineage_df_artifact_recipes' 'Difu positioning cannot allocate recipes.'
            Assert-Null $dfPositioning.consumption_rules 'invalid_lineage_df_artifact_consumption' 'Difu positioning cannot allocate consumption rules.'

            $dfDetailRef = $dfStage.artifact_detailed_design_contract
            Assert-Equal ([string]$dfDetailRef.contract_id) 'DF_SPEC_TWO_MIDGAME_ARTIFACT_DETAIL_V1' 'invalid_lineage_df_artifact_detail_contract_id' 'Difu must reference the detailed two-artifact contract.'
            Assert-Equal ([string]$dfDetailRef.path) $difuArtifactDetailRelativePath 'invalid_lineage_df_artifact_detail_contract_path' 'Difu detailed artifact path is invalid.'
            Assert-Equal ([string]$dfDetailRef.status) 'accepted-offline-design' 'invalid_lineage_df_artifact_detail_status' 'Difu detailed artifact contract must remain offline-only.'
            Assert-Equal ([int]$dfDetailRef.artifact_spec_count) 2 'invalid_lineage_df_artifact_detail_count' 'Difu detailed artifact contract must retain exactly two specs.'
            Assert-StringSetEqual -Actual @($dfDetailRef.artifact_spec_ids | ForEach-Object { [string]$_ }) -Expected @('DF_SPEC_ARTIFACT_GUIDING_LANTERN', 'DF_SPEC_ARTIFACT_KARMIC_MIRROR') -Code 'invalid_lineage_df_artifact_detail_ids' -Message 'Difu detailed artifact spec IDs are invalid.'
            foreach ($propertyName in @('actual_logical_artifact_keys', 'source_profile_mapping', 'stats', 'recipes', 'consumption_rules')) {
                Assert-Null $dfDetailRef.$propertyName 'invalid_lineage_df_artifact_detail_deferred' "Difu detailed artifact reference cannot allocate '$propertyName'."
            }
        }
        if ($null -ne $ttStage) {
            Assert-Equal ([string]$ttStage.replacement_or_upgrade_rule) 'delegated_to_TT_SPEC_ENDGAME_ARTIFACT_POSITIONING_AND_LINEAGE_V1' 'invalid_lineage_tt_artifact_replacement_delegate' 'Tianting replacement behavior must remain delegated to the dedicated offline contract.'
            $ttPositioning = $ttStage.artifact_positioning_contract
            Assert-Equal ([string]$ttPositioning.contract_id) 'TT_SPEC_ENDGAME_ARTIFACT_POSITIONING_AND_LINEAGE_V1' 'invalid_lineage_tt_artifact_contract_id' 'Tianting must reference the dedicated artifact positioning contract.'
            Assert-Equal ([string]$ttPositioning.path) $tiantingArtifactRelativePath 'invalid_lineage_tt_artifact_contract_path' 'Tianting artifact positioning path is invalid.'
            Assert-Equal ([string]$ttPositioning.status) 'accepted-offline-design' 'invalid_lineage_tt_artifact_contract_status' 'Tianting artifact positioning contract must remain offline-only.'
            Assert-Equal ([string]$ttPositioning.tier) 'high_endgame' 'invalid_lineage_tt_artifact_tier' 'Tianting artifact stage must be high endgame tier.'
            foreach ($propertyName in @('actual_logical_artifact_keys', 'source_profile_mapping', 'stats', 'recipes', 'consumption_rules')) {
                Assert-Null $ttPositioning.$propertyName 'invalid_lineage_tt_artifact_deferred' "Tianting positioning cannot allocate '$propertyName'."
            }
            $ttCompleteDesign = $ttStage.artifact_complete_design_contract
            Assert-Equal ([string]$ttCompleteDesign.contract_id) 'TT_SPEC_GRADUATION_ARTIFACT_COMPLETE_DESIGN_V1' 'invalid_lineage_tt_artifact_complete_design_id' 'Tianting complete-design contract identity is invalid.'
            Assert-Equal ([string]$ttCompleteDesign.path) $tiantingArtifactCompleteDesignRelativePath 'invalid_lineage_tt_artifact_complete_design_path' 'Tianting complete-design path is invalid.'
            Assert-Equal ([string]$ttCompleteDesign.status) 'accepted-offline-design' 'invalid_lineage_tt_artifact_complete_design_status' 'Tianting complete-design contract must remain offline-only.'
            Assert-Equal ([string]$ttCompleteDesign.display_name) $tiantingArtifactDisplayName 'invalid_lineage_tt_artifact_complete_design_name' 'Tianting complete-design display name is invalid.'
            foreach ($propertyName in @('actual_logical_artifact_key', 'actual_material_keys', 'actual_recipe', 'actual_receipts')) {
                Assert-Null $ttCompleteDesign.$propertyName 'invalid_lineage_tt_artifact_complete_design_deferred' "Tianting complete-design reference cannot allocate '$propertyName'."
            }
        }
        Assert-Equal ([string]$threeChapterArtifactDetail.contract_id) 'THREE_CHAPTER_ARTIFACT_DETAIL_AND_MATERIAL_SOURCE_V1' 'invalid_three_chapter_artifact_detail_id' 'The three-chapter artifact detail contract ID is invalid.'
        Assert-Equal ([int]$threeChapterArtifactDetail.schema_version) 1 'invalid_three_chapter_artifact_detail_schema' 'The three-chapter artifact detail schema is invalid.'
        Assert-Equal ([string]$threeChapterArtifactDetail.artifact_kind) 'offline_three_chapter_artifact_detail_and_material_source_contract' 'invalid_three_chapter_artifact_detail_kind' 'The three-chapter artifact detail kind is invalid.'
        Assert-Equal ([string]$threeChapterArtifactDetail.status) 'accepted-offline-design' 'invalid_three_chapter_artifact_detail_status' 'The three-chapter artifact detail contract must remain offline design.'
        Assert-Equal ([bool]$threeChapterArtifactDetail.runtime_handoff) $false 'invalid_three_chapter_artifact_detail_runtime' 'The three-chapter artifact detail contract must not enable runtime handoff.'
        Assert-Equal ([string]$threeChapterArtifactDetail.production_gate) 'closed' 'invalid_three_chapter_artifact_detail_production' 'The three-chapter artifact detail contract must keep production closed.'
        Assert-Equal ([int]$threeChapterArtifactDetail.global_artifact_rules.active_artifact_slot_count) 1 'invalid_three_chapter_artifact_detail_slot_count' 'The three-chapter artifact detail contract must retain one active slot.'
        Assert-Equal ([bool]$threeChapterArtifactDetail.global_artifact_rules.mainline_or_entry_artifact_requirement) $false 'invalid_three_chapter_artifact_detail_mainline_gate' 'The three-chapter artifact detail contract cannot create artifact gates.'
        $threeChapterArtifactBoundary = $threeChapterArtifactDetail.non_production_boundary
        foreach ($propertyName in @('actual_item_assets', 'new_logical_artifact_keys', 'runtime_item_keys', 'ability_assets', 'combat_stat_values', 'cooldowns', 'durations', 'ranges', 'target_counts', 'new_material_keys', 'material_quantities', 'recipes', 'consumption_rules', 'new_source_profiles', 'new_drop_rates', 'new_pity_rules', 'qualification_snapshots', 'receipt_schemas', 'y3_object_allocation')) {
            Assert-Null $threeChapterArtifactBoundary.$propertyName 'invalid_three_chapter_artifact_detail_nonproduction_value' "The three-chapter artifact detail contract cannot allocate '$propertyName'."
        }
        Assert-Equal ([bool]$threeChapterArtifactBoundary.economy_execution) $false 'invalid_three_chapter_artifact_detail_economy_execution' 'The three-chapter artifact detail contract cannot execute economy changes.'
        $threeChapterArtifactChapters = @($threeChapterArtifactDetail.chapters)
        Assert-StringSetEqual -Actual @($threeChapterArtifactChapters | ForEach-Object { [string]$_.chapter_id }) -Expected @('HG', 'DF', 'TT') -Code 'invalid_three_chapter_artifact_detail_chapters' -Message 'The three-chapter artifact detail contract must cover exactly HG, DF, and TT.'
        $threeChapterArtifactCount = @($threeChapterArtifactChapters | ForEach-Object { @($_.artifacts) }).Count
        Assert-Equal ([int]$threeChapterArtifactCount) 5 'invalid_three_chapter_artifact_detail_artifact_count' 'The three-chapter artifact detail contract must retain exactly five artifact specs.'
        foreach ($deferredStage in @($dfStage, $ttStage)) {
            if ($null -ne $deferredStage) {
                Assert-Null $deferredStage.logical_equipment_keys 'invalid_lineage_deferred_equipment' "Deferred stage '$($deferredStage.stage_id)' cannot allocate equipment keys."
                Assert-Null $deferredStage.logical_artifact_keys 'invalid_lineage_deferred_artifacts' "Deferred stage '$($deferredStage.stage_id)' cannot allocate artifact keys."
                Assert-Null $deferredStage.source_profile_mapping 'invalid_lineage_deferred_profiles' "Deferred stage '$($deferredStage.stage_id)' cannot allocate source profiles."
                Assert-Null $deferredStage.stats 'invalid_lineage_deferred_stats' "Deferred stage '$($deferredStage.stage_id)' cannot allocate stats."
            }
        }

        Assert-Equal ([string]$difuArtifact.contract_id) 'DF_SPEC_MIDGAME_ARTIFACT_POSITIONING_REPLACEMENT_V1' 'invalid_df_artifact_contract_id' 'Difu artifact contract ID is invalid.'
        Assert-Equal ([int]$difuArtifact.schema_version) 1 'invalid_df_artifact_schema_version' 'Difu artifact contract schema version is invalid.'
        Assert-Equal ([string]$difuArtifact.artifact_kind) 'offline_difu_midgame_artifact_positioning_and_replacement_contract' 'invalid_df_artifact_kind' 'Difu artifact contract kind is invalid.'
        Assert-Equal ([string]$difuArtifact.status) 'accepted-offline-design' 'invalid_df_artifact_status' 'Difu artifact contract must remain offline design.'
        Assert-Equal ([bool]$difuArtifact.runtime_handoff) $false 'invalid_df_artifact_runtime_gate' 'Difu artifact contract must not enable runtime handoff.'
        Assert-Equal ([string]$difuArtifact.production_gate) 'closed' 'invalid_df_artifact_production_gate' 'Difu artifact contract must keep production closed.'

        $difuArtifactBoundary = $difuArtifact.non_production_boundary
        Assert-Equal ([bool]$difuArtifactBoundary.design_only) $true 'invalid_df_artifact_design_only' 'Difu artifact contract must remain design-only.'
        foreach ($propertyName in @('actual_artifact_keys', 'actual_asset_ids', 'source_profile_mapping', 'reward_values', 'drop_probability', 'pity_policy', 'recipes', 'consumption_rules', 'stats', 'active_abilities', 'runtime_keys', 'y3_object_allocation')) {
            Assert-Null $difuArtifactBoundary.$propertyName 'invalid_df_artifact_nonproduction_value' "Difu artifact contract cannot allocate '$propertyName'."
        }
        Assert-Equal ([bool]$difuArtifactBoundary.actual_receipt_creation) $false 'invalid_df_artifact_receipt_execution' 'Difu artifact contract must not create receipts.'
        Assert-Equal ([bool]$difuArtifactBoundary.actual_economic_execution) $false 'invalid_df_artifact_economy_execution' 'Difu artifact contract must not execute economy changes.'

        Assert-Equal ([string]$difuArtifact.chapter_position.chapter_id) 'DF' 'invalid_df_artifact_chapter' 'Difu artifact contract must belong to DF.'
        Assert-Equal ([string]$difuArtifact.chapter_position.level_band) 'Lv21-Lv40' 'invalid_df_artifact_level_band' 'Difu artifact level band is invalid.'
        Assert-Equal ([string]$difuArtifact.chapter_position.tier) 'medium' 'invalid_df_artifact_position_tier' 'Difu artifact tier is invalid.'
        Assert-Equal ([string]$difuArtifact.chapter_position.combat_grammar) $dfArtifactCombatGrammar 'invalid_df_artifact_combat_grammar' 'Difu artifact must use the chapter combat grammar.'

        $slotContract = $difuArtifact.slot_and_loadout_contract
        Assert-Equal ([string]$slotContract.inherits_artifact_slot_version) 'v1' 'invalid_df_artifact_slot_version' 'Difu artifact must inherit v1 slot contract.'
        Assert-Equal ([int]$slotContract.active_artifact_slot_count) 1 'invalid_df_artifact_slot_count' 'Difu artifact must retain one active slot.'
        Assert-Equal ([bool]$slotContract.adds_another_active_slot) $false 'invalid_df_artifact_second_slot' 'Difu artifact cannot add a second active slot.'
        Assert-Equal ([bool]$slotContract.inactive_artifact_default_combat_effect) $false 'invalid_df_artifact_inactive_effect' 'Inactive artifacts cannot have default combat effects.'
        Assert-Equal ([bool]$slotContract.artifact_active_ability_occupies_five_active_skill_slots) $false 'invalid_df_artifact_skill_slot' 'Artifact active must not occupy a five-active skill slot.'
        Assert-True ([string]$slotContract.switching_rule -match $dfArtifactAtomicSwitchToken) 'invalid_df_artifact_switch_atomicity' 'Difu artifact switching must retain atomic loadout behavior.'
        Assert-True ([string]$slotContract.switching_rule -match $dfArtifactChallengeLockToken) 'invalid_df_artifact_switch_lock' 'Difu artifact switching must retain challenge lock behavior.'

        $axisContract = $difuArtifact.functional_axis_contract
        Assert-Equal ([int]$axisContract.axis_count) 3 'invalid_df_artifact_axis_count' 'Difu artifact must retain exactly three functional axes.'
        Assert-Equal ([int]$axisContract.artifact_primary_axis_count) 2 'invalid_df_artifact_primary_axis_count' 'Difu must retain exactly two artifact primary axes.'
        Assert-Equal ([string]$axisContract.chapter_shared_resolution_axis_id) 'DF_SPEC_ARTIFACT_AXIS_HUIZHENG' 'invalid_df_artifact_shared_resolution_id' 'Difu shared resolution axis is invalid.'
        Assert-Null $axisContract.actual_logical_artifact_keys 'invalid_df_artifact_axis_asset_keys' 'Functional axes cannot allocate artifact keys.'
        $axisRows = @($axisContract.axes)
        Assert-StringSetEqual -Actual @($axisRows | ForEach-Object { [string]$_.spec_axis_id }) -Expected @('DF_SPEC_ARTIFACT_AXIS_ZHENHUN', 'DF_SPEC_ARTIFACT_AXIS_KANMING', 'DF_SPEC_ARTIFACT_AXIS_HUIZHENG') -Code 'invalid_df_artifact_axis_set' -Message 'Difu artifact functional axes are invalid.'
        foreach ($axis in $axisRows) {
            Assert-Null $axis.stats 'invalid_df_artifact_axis_stats' "Axis '$($axis.spec_axis_id)' cannot allocate stats."
            Assert-Null $axis.ability_detail 'invalid_df_artifact_axis_ability' "Axis '$($axis.spec_axis_id)' cannot allocate ability detail."
        }
        Assert-True ([string]$axisContract.primary_axis_exclusivity -match $dfArtifactPrimaryAxisToken) 'invalid_df_artifact_axis_exclusivity' 'A concrete Difu artifact must retain one primary functional axis.'
        $zhenhunAxis = Get-SingleByProperty -Rows $axisRows -Property 'spec_axis_id' -Value 'DF_SPEC_ARTIFACT_AXIS_ZHENHUN' -Code 'invalid_df_artifact_zhenhun_axis'
        $kanmingAxis = Get-SingleByProperty -Rows $axisRows -Property 'spec_axis_id' -Value 'DF_SPEC_ARTIFACT_AXIS_KANMING' -Code 'invalid_df_artifact_kanming_axis'
        $huizhengAxis = Get-SingleByProperty -Rows $axisRows -Property 'spec_axis_id' -Value 'DF_SPEC_ARTIFACT_AXIS_HUIZHENG' -Code 'invalid_df_artifact_huizheng_axis'
        if ($null -ne $zhenhunAxis) { Assert-Equal ([string]$zhenhunAxis.classification) 'artifact_primary_axis' 'invalid_df_artifact_zhenhun_classification' 'Zhenhun must remain an artifact primary axis.' }
        if ($null -ne $kanmingAxis) { Assert-Equal ([string]$kanmingAxis.classification) 'artifact_primary_axis' 'invalid_df_artifact_kanming_classification' 'Kanming must remain an artifact primary axis.' }
        if ($null -ne $huizhengAxis) { Assert-Equal ([string]$huizhengAxis.classification) 'chapter_shared_correct_resolution' 'invalid_df_artifact_huizheng_classification' 'Huizheng must remain a shared chapter resolution.' }

        $detailContractRef = $difuArtifact.two_artifact_detailed_design_contract
        Assert-Equal ([string]$detailContractRef.contract_id) 'DF_SPEC_TWO_MIDGAME_ARTIFACT_DETAIL_V1' 'invalid_df_artifact_detail_contract_id' 'Difu artifact detail contract ID is invalid.'
        Assert-Equal ([string]$detailContractRef.path) "two-artifact-detail/$difuArtifactDetailFileName" 'invalid_df_artifact_detail_contract_path' 'Difu artifact detail contract path is invalid.'
        Assert-Equal ([string]$detailContractRef.status) 'accepted-offline-design' 'invalid_df_artifact_detail_contract_status' 'Difu artifact detail contract must remain offline design.'
        Assert-Equal ([int]$detailContractRef.artifact_spec_count) 2 'invalid_df_artifact_detail_contract_count' 'Difu artifact detail contract must retain two specs.'
        Assert-StringSetEqual -Actual @($detailContractRef.artifact_spec_ids | ForEach-Object { [string]$_ }) -Expected @('DF_SPEC_ARTIFACT_GUIDING_LANTERN', 'DF_SPEC_ARTIFACT_KARMIC_MIRROR') -Code 'invalid_df_artifact_detail_contract_ids' -Message 'Difu artifact detail contract IDs are invalid.'
        foreach ($propertyName in @('actual_logical_artifact_keys', 'source_profile_mapping', 'stats', 'recipes', 'consumption_rules')) {
            Assert-Null $detailContractRef.$propertyName 'invalid_df_artifact_detail_contract_deferred' "Difu artifact detail contract cannot allocate '$propertyName'."
        }

        $accessContract = $difuArtifact.standard_access_contract
        Assert-True ([string]$accessContract.player_facing_rule -match $dfArtifactNoLegacyToken) 'invalid_df_artifact_legacy_free_access' 'Difu standard access must cover characters without Huaguoshan artifacts.'
        Assert-Null $accessContract.specific_source_node 'invalid_df_artifact_source_node' 'Difu artifact contract cannot allocate a source node.'
        Assert-StringSetEqual -Actual @($accessContract.semantic_anchor_nodes | ForEach-Object { [string]$_ }) -Expected @('DF_NODE_GUIDING_COURT', 'DF_NODE_JUDGE_HALL') -Code 'invalid_df_artifact_semantic_anchor_nodes' -Message 'Difu artifact semantic anchors are invalid.'
        Assert-Null $accessContract.source_profile_mapping 'invalid_df_artifact_source_profile' 'Difu artifact contract cannot allocate a source profile.'
        Assert-Equal ([bool]$accessContract.automatic_grant_from_df_progress_key) $false 'invalid_df_artifact_progress_auto_grant' 'Difu artifact cannot auto-grant from the protected progress key.'
        Assert-Equal ([bool]$accessContract.normal_mainline_equip_requirement) $false 'invalid_df_artifact_equip_gate' 'Difu normal mainline cannot require artifact equip.'
        Assert-Equal ([bool]$accessContract.normal_mainline_ownership_requirement) $false 'invalid_df_artifact_ownership_gate' 'Difu normal mainline cannot require artifact ownership.'
        Assert-StringSetEqual -Actual @($accessContract.forbidden_as_sole_or_required_source | ForEach-Object { [string]$_ }) -Expected $expectedDfArtifactForbiddenSources -Code 'invalid_df_artifact_forbidden_sources' -Message 'Difu artifact must reject optional, team, rare, repeat, and tower sources as a sole or required path.'

        Assert-Equal ([string]$difuArtifactDetail.contract_id) 'DF_SPEC_TWO_MIDGAME_ARTIFACT_DETAIL_V1' 'invalid_df_artifact_detail_id' 'Difu detailed artifact contract ID is invalid.'
        Assert-Equal ([int]$difuArtifactDetail.schema_version) 1 'invalid_df_artifact_detail_schema' 'Difu detailed artifact contract schema is invalid.'
        Assert-Equal ([string]$difuArtifactDetail.artifact_kind) 'offline_difu_two_midgame_artifact_detailed_design_contract' 'invalid_df_artifact_detail_kind' 'Difu detailed artifact kind is invalid.'
        Assert-Equal ([string]$difuArtifactDetail.status) 'accepted-offline-design' 'invalid_df_artifact_detail_status' 'Difu detailed artifact contract must remain offline design.'
        Assert-Equal ([bool]$difuArtifactDetail.runtime_handoff) $false 'invalid_df_artifact_detail_runtime' 'Difu detailed artifact contract must not enable runtime handoff.'
        Assert-Equal ([string]$difuArtifactDetail.production_gate) 'closed' 'invalid_df_artifact_detail_production_gate' 'Difu detailed artifact production gate must remain closed.'

        $detailBoundary = $difuArtifactDetail.non_production_boundary
        Assert-Equal ([bool]$detailBoundary.design_only) $true 'invalid_df_artifact_detail_design_only' 'Difu detailed artifact contract must remain design only.'
        foreach ($propertyName in @('actual_artifact_keys', 'runtime_item_identifiers', 'asset_ids', 'stat_values', 'ability_values', 'source_profile_mapping', 'reward_slots', 'material_keys', 'material_quantities', 'recipes', 'consumption_rules', 'drop_probability', 'pity_policy', 'qualification_snapshot', 'receipt_schema', 'y3_object_allocation')) {
            Assert-Null $detailBoundary.$propertyName 'invalid_df_artifact_detail_nonproduction_value' "Difu detailed artifact contract cannot allocate '$propertyName'."
        }
        Assert-Equal ([bool]$detailBoundary.actual_receipt_creation) $false 'invalid_df_artifact_detail_receipt_execution' 'Difu detailed artifact contract cannot create receipts.'
        Assert-Equal ([bool]$detailBoundary.actual_economic_execution) $false 'invalid_df_artifact_detail_economy_execution' 'Difu detailed artifact contract cannot execute economy changes.'

        $detailSources = @($difuArtifactDetail.source_contracts)
        Assert-Equal $detailSources.Count 4 'invalid_df_artifact_detail_source_count' 'Difu detailed artifact contract must retain four source contracts.'
        $detailDirectory = Split-Path -Parent $difuArtifactDetailPath
        foreach ($source in $detailSources) {
            $sourceText = [string]$source.path
            Assert-True (-not [IO.Path]::IsPathRooted($sourceText)) 'invalid_df_artifact_detail_source_absolute' 'Difu detailed artifact sources must remain relative.'
            $resolvedSource = [IO.Path]::GetFullPath((Join-Path $detailDirectory $sourceText))
            Assert-True (Test-Path -LiteralPath $resolvedSource -PathType Leaf) 'invalid_df_artifact_detail_source_missing' "Difu detailed artifact source is missing: $sourceText"
        }

        $detailIdentity = $difuArtifactDetail.identity_policy
        Assert-Equal ([int]$detailIdentity.artifact_spec_count) 2 'invalid_df_artifact_detail_identity_count' 'Difu detailed artifact identity count must be two.'
        Assert-Null $detailIdentity.actual_logical_artifact_keys 'invalid_df_artifact_detail_identity_keys' 'Difu detailed artifact identities cannot allocate logical keys.'

        $sharedResolution = $difuArtifactDetail.chapter_shared_resolution
        Assert-Equal ([string]$sharedResolution.spec_axis_id) 'DF_SPEC_ARTIFACT_AXIS_HUIZHENG' 'invalid_df_artifact_detail_shared_axis' 'Difu detailed shared resolution axis is invalid.'
        Assert-Equal ([string]$sharedResolution.classification) 'chapter_shared_correct_resolution' 'invalid_df_artifact_detail_shared_classification' 'Difu detailed shared resolution classification is invalid.'
        Assert-Equal ([bool]$sharedResolution.owned_by_an_artifact) $false 'invalid_df_artifact_detail_shared_ownership' 'Difu shared resolution must not be owned by an artifact.'

        $detailArtifacts = @($difuArtifactDetail.artifacts)
        Assert-Equal $detailArtifacts.Count 2 'invalid_df_artifact_detail_artifact_count' 'Difu detailed contract must contain exactly two artifacts.'
        Assert-StringSetEqual -Actual @($detailArtifacts | ForEach-Object { [string]$_.artifact_spec_id }) -Expected @('DF_SPEC_ARTIFACT_GUIDING_LANTERN', 'DF_SPEC_ARTIFACT_KARMIC_MIRROR') -Code 'invalid_df_artifact_detail_artifact_ids' -Message 'Difu detailed artifact IDs are invalid.'

        $guidingLantern = Get-SingleByProperty -Rows $detailArtifacts -Property 'artifact_spec_id' -Value 'DF_SPEC_ARTIFACT_GUIDING_LANTERN' -Code 'invalid_df_artifact_detail_lantern'
        $karmicMirror = Get-SingleByProperty -Rows $detailArtifacts -Property 'artifact_spec_id' -Value 'DF_SPEC_ARTIFACT_KARMIC_MIRROR' -Code 'invalid_df_artifact_detail_mirror'
        $expectedDetailRows = @(
            [pscustomobject]@{ row = $guidingLantern; id = 'DF_SPEC_ARTIFACT_GUIDING_LANTERN'; name = $dfArtifactDetailLanternName; axis = 'DF_SPEC_ARTIFACT_AXIS_ZHENHUN'; node = 'DF_NODE_GUIDING_COURT'; stages = @('DF_LANTERN_STAGE_RECOGNIZE', 'DF_LANTERN_STAGE_STABILIZE', 'DF_LANTERN_STAGE_HANDOFF'); affinity = @('DF_NODE_WUCHANG_ALLEY', 'DF_NODE_GHOST_GATE', 'DF_NODE_GUIDING_COURT', 'DF_NODE_YANLUO_HALL', 'DF_NODE_ZHUANLUN_HALL') },
            [pscustomobject]@{ row = $karmicMirror; id = 'DF_SPEC_ARTIFACT_KARMIC_MIRROR'; name = $dfArtifactDetailMirrorName; axis = 'DF_SPEC_ARTIFACT_AXIS_KANMING'; node = 'DF_NODE_JUDGE_HALL'; stages = @('DF_MIRROR_STAGE_TRACE', 'DF_MIRROR_STAGE_DISCERN', 'DF_MIRROR_STAGE_REVIEW'); affinity = @('DF_NODE_JUDGE_HALL', 'DF_SIDE_BAIGU_SECRET_REALM', 'DF_NODE_YANLUO_HALL', 'DF_NODE_ZHUANLUN_HALL') }
        )
        foreach ($expectedDetail in $expectedDetailRows) {
            $artifact = $expectedDetail.row
            if ($null -eq $artifact) { continue }
            Assert-Equal ([string]$artifact.artifact_spec_id) $expectedDetail.id 'invalid_df_artifact_detail_identity' 'Difu detailed artifact identity is invalid.'
            Assert-Equal ([string]$artifact.display_name) $expectedDetail.name 'invalid_df_artifact_detail_name' 'Difu detailed artifact display name is invalid.'
            Assert-Equal ([string]$artifact.display_name_status) 'accepted-by-user-directed-detailing' 'invalid_df_artifact_detail_name_status' 'Difu detailed artifact display name status is invalid.'
            foreach ($propertyName in @('actual_logical_artifact_key', 'runtime_item_identifier')) {
                Assert-Null $artifact.$propertyName 'invalid_df_artifact_detail_asset_identifier' "Difu detailed artifact cannot allocate '$propertyName'."
            }
            Assert-Equal ([string]$artifact.tier) 'medium' 'invalid_df_artifact_detail_tier' 'Difu detailed artifact tier is invalid.'
            Assert-Equal ([string]$artifact.primary_axis_id) $expectedDetail.axis 'invalid_df_artifact_detail_primary_axis' 'Difu detailed artifact primary axis is invalid.'

            $anchor = $artifact.source_semantic_anchor
            Assert-Equal ([string]$anchor.content_node_id) $expectedDetail.node 'invalid_df_artifact_detail_anchor_node' 'Difu detailed artifact semantic anchor is invalid.'
            Assert-Equal ([string]$anchor.anchor_kind) 'regular_mainline_semantic_anchor' 'invalid_df_artifact_detail_anchor_kind' 'Difu detailed artifact anchor must remain semantic and on the regular route.'
            foreach ($propertyName in @('actual_source_event', 'source_profile_mapping', 'qualification_rule', 'reward_slot', 'receipt_schema')) {
                Assert-Null $anchor.$propertyName 'invalid_df_artifact_detail_anchor_execution' "Difu detailed artifact semantic anchor cannot allocate '$propertyName'."
            }

            $card = $artifact.gameplay_card
            Assert-Null $card.actual_ability_key 'invalid_df_artifact_detail_ability_key' 'Difu detailed artifact cannot allocate an ability key.'
            foreach ($propertyName in @('damage', 'cooldown', 'duration', 'range', 'target_count', 'status_effect_values')) {
                Assert-Null $card.$propertyName 'invalid_df_artifact_detail_ability_value' "Difu detailed artifact cannot allocate '$propertyName'."
            }
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$card.player_precondition)) 'invalid_df_artifact_detail_precondition' 'Difu detailed artifact must require a player verification precondition.'
            Assert-True (@($card.forbidden_interpretations).Count -ge 3) 'invalid_df_artifact_detail_forbidden_interpretations' 'Difu detailed artifact must retain explicit anti-automation prohibitions.'

            $growth = @($artifact.semantic_growth_route)
            Assert-StringSetEqual -Actual @($growth | ForEach-Object { [string]$_.stage_id }) -Expected @($expectedDetail.stages) -Code 'invalid_df_artifact_detail_growth_stages' -Message 'Difu detailed artifact semantic growth stages are invalid.'
            foreach ($theme in @($artifact.material_themes)) {
                foreach ($propertyName in @('actual_material_key', 'quantity', 'drop_source', 'consumption')) {
                    Assert-Null $theme.$propertyName 'invalid_df_artifact_detail_material_value' "Difu detailed artifact material theme cannot allocate '$propertyName'."
                }
            }
            $affinityIds = @($artifact.encounter_affinity | ForEach-Object { [string]$_.content_node_id })
            Assert-StringSetEqual -Actual $affinityIds -Expected @($expectedDetail.affinity) -Code 'invalid_df_artifact_detail_affinity' -Message 'Difu detailed artifact encounter affinities are invalid.'

            $upgradeBoundary = $artifact.lineage_and_upgrade_boundary
            foreach ($propertyName in @('current_upgrade_recipe', 'current_upgrade_cost', 'current_upgrade_receipt', 'current_migration_rule')) {
                Assert-Null $upgradeBoundary.$propertyName 'invalid_df_artifact_detail_upgrade_value' "Difu detailed artifact cannot allocate '$propertyName'."
            }
        }

        $detailGuards = $difuArtifactDetail.cross_chapter_and_session_guards
        Assert-Equal ([int]$detailGuards.active_artifact_slot_count) 1 'invalid_df_artifact_detail_slot_count' 'Difu detailed artifact contract must retain one active slot.'
        foreach ($propertyName in @('inactive_artifact_default_effect', 'challenge_local_switch_allowed', 'death_disconnect_or_cleanup_local_switch_allowed', 'difu_entry_requires_artifact', 'yanluo_completion_requires_artifact', 'zhuanlun_entry_requires_artifact', 'tianting_entry_requires_artifact', 'tianting_content_requires_artifact', 'reads_or_writes_protected_progress_key')) {
            Assert-Equal ([bool]$detailGuards.$propertyName) $false 'invalid_df_artifact_detail_guard' "Difu detailed artifact guard '$propertyName' must remain false."
        }
        Assert-Equal ([string]$detailGuards.protected_progress_key) 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'invalid_df_artifact_detail_progress_key' 'Difu detailed artifact progress key guard is invalid.'

        Assert-StringSetEqual -Actual @($difuArtifactDetail.acceptance_matrix | ForEach-Object { [string]$_.acceptance_id }) -Expected @('DF-ART-DETAIL-001', 'DF-ART-DETAIL-002', 'DF-ART-DETAIL-003', 'DF-ART-DETAIL-004', 'DF-ART-DETAIL-005', 'DF-ART-DETAIL-006', 'DF-ART-DETAIL-007') -Code 'invalid_df_artifact_detail_acceptance_set' -Message 'Difu detailed artifact acceptance matrix is incomplete.'
        foreach ($property in $difuArtifactDetail.deferred.PSObject.Properties) {
            Assert-Null $property.Value 'invalid_df_artifact_detail_deferred_value' "Difu detailed artifact deferred field '$($property.Name)' must remain null."
        }

        $replacementContract = $difuArtifact.legacy_and_replacement_contract
        Assert-StringSetEqual -Actual @($replacementContract.supported_legacy_entry_states | ForEach-Object { [string]$_ }) -Expected @('no_huaguoshan_artifact', 'ART_HG_TIDE_SEAL_only', 'ART_HG_FLAME_CORE_only', 'both_huaguoshan_artifacts') -Code 'invalid_df_artifact_legacy_state_set' -Message 'Difu artifact must cover all Huaguoshan ownership states.'
        Assert-StringSetEqual -Actual @($replacementContract.relationship_modes | ForEach-Object { [string]$_.mode_id }) -Expected @('DF_ARTIFACT_RETAIN_LEGACY', 'DF_ARTIFACT_SELECT_MIDGAME', 'DF_ARTIFACT_FUTURE_LINEAGE_MIGRATION') -Code 'invalid_df_artifact_replacement_mode_set' -Message 'Difu artifact replacement modes are invalid.'
        Assert-Null $replacementContract.current_migration_recipe 'invalid_df_artifact_current_recipe' 'Difu artifact contract cannot allocate a migration recipe.'
        Assert-Null $replacementContract.current_migration_cost 'invalid_df_artifact_current_cost' 'Difu artifact contract cannot allocate a migration cost.'
        Assert-Null $replacementContract.current_migration_receipt 'invalid_df_artifact_current_receipt' 'Difu artifact contract cannot allocate a migration receipt.'
        Assert-True (@($replacementContract.forbidden_replacement_behaviors | ForEach-Object { [string]$_ }) -contains $dfArtifactSilentLegacyDestruction) 'invalid_df_artifact_legacy_destruction' 'Difu artifact contract must forbid silent legacy destruction.'

        $crossChapter = $difuArtifact.cross_chapter_protection
        foreach ($propertyName in @('difu_entry_requires_artifact', 'yanluo_regular_completion_requires_artifact', 'zhuanlun_team_entry_requires_artifact', 'tianting_entry_requires_artifact', 'tianting_normal_or_nightmare_instance_requires_artifact', 'tianting_graduation_recipe_requires_specific_df_artifact', 'this_contract_reads_or_writes_protected_difu_progress_key')) {
            Assert-Equal ([bool]$crossChapter.$propertyName) $false 'invalid_df_artifact_cross_chapter_gate' "Difu artifact contract cannot enable '$propertyName'."
        }
        Assert-Equal ([string]$crossChapter.protected_difu_progress_key) 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'invalid_df_artifact_protected_key' 'Difu artifact contract must protect the Yanluo progress key.'

        $artifactEconomy = $difuArtifact.economy_and_receipt_boundary
        Assert-Equal ([string]$artifactEconomy.owner_scope_when_future_economy_is_adopted) 'character' 'invalid_df_artifact_owner_scope' 'Future Difu artifact ownership must remain character-scoped.'
        foreach ($propertyName in @('current_resource_table_version', 'current_reward_slot', 'current_qualification_rule', 'current_pity_rule', 'current_receipt_schema')) {
            Assert-Null $artifactEconomy.$propertyName 'invalid_df_artifact_current_economy' "Difu artifact contract cannot allocate '$propertyName'."
        }
        Assert-Equal ([bool]$artifactEconomy.historical_huaguoshan_receipt_recalculation) $false 'invalid_df_artifact_history_recalculation' 'Difu artifact contract cannot recalculate Huaguoshan receipts.'

        Assert-StringSetEqual -Actual @($difuArtifact.acceptance_matrix | ForEach-Object { [string]$_.acceptance_id }) -Expected @('DF-ART-ACC-001', 'DF-ART-ACC-002', 'DF-ART-ACC-003', 'DF-ART-ACC-004', 'DF-ART-ACC-005', 'DF-ART-ACC-006', 'DF-ART-ACC-007', 'DF-ART-ACC-008', 'DF-ART-ACC-009', 'DF-ART-ACC-010', 'DF-ART-ACC-011', 'DF-ART-ACC-012', 'DF-ART-ACC-013', 'DF-ART-ACC-014', 'DF-ART-ACC-015', 'DF-ART-ACC-016') -Code 'invalid_df_artifact_acceptance_set' -Message 'Difu artifact acceptance matrix is incomplete.'
        Assert-True (@($matrix.lineage_invariants | ForEach-Object { [string]$_ }) -contains 'DF standard artifact access must remain reachable without Huaguoshan optional artifacts, rare awards, optional instances, team instances, repeat clears, or tower content, while ownership and equipping remain optional.') 'invalid_lineage_df_artifact_access_invariant' 'Three-chapter lineage must retain Difu standard-access invariant.'
        Assert-True (@($matrix.lineage_invariants | ForEach-Object { [string]$_ }) -contains 'DF two-artifact detail must contain exactly Guiding Lantern on the Zhenhun primary axis and Karmic Mirror on the Kanming primary axis; Huizheng is a shared chapter resolution rather than a third or automatic artifact effect.') 'invalid_lineage_df_artifact_detail_invariant' 'Three-chapter lineage must retain the Difu two-artifact invariant.'
        Assert-True (@($matrix.lineage_invariants | ForEach-Object { [string]$_ }) -contains 'DF detailed semantic anchors may reference only Guiding Court and Judge Hall on the standard route; Baigu Secret Realm and Zhuanlun Hall may test horizontal play but cannot be a required base, upgrade, material, qualification, recipe, or mainline source.') 'invalid_lineage_df_artifact_anchor_invariant' 'Three-chapter lineage must retain the Difu semantic-anchor invariant.'
        Assert-True (@($matrix.lineage_invariants | ForEach-Object { [string]$_ }) -contains 'DF and TT chapter entry, regular completion, team eligibility, and graduation design may not require a specific Huaguoshan or Difu artifact until an explicit successor contract is separately adopted.') 'invalid_lineage_df_artifact_cross_chapter_invariant' 'Three-chapter lineage must retain artifact-free chapter and graduation gates.'

        Assert-Equal ([int]$tiantingArtifact.version) 1 'invalid_tt_artifact_contract_version' 'Tianting artifact contract version is invalid.'
        Assert-Equal ([string]$tiantingArtifact.contract_id) 'TT_SPEC_ENDGAME_ARTIFACT_POSITIONING_AND_LINEAGE_V1' 'invalid_tt_artifact_contract_id' 'Tianting artifact contract ID is invalid.'
        Assert-Equal ([string]$tiantingArtifact.artifact_kind) 'offline_tianting_endgame_artifact_positioning_and_lineage_contract' 'invalid_tt_artifact_kind' 'Tianting artifact contract kind is invalid.'
        Assert-Equal ([string]$tiantingArtifact.package_status) 'offline-design-spec' 'invalid_tt_artifact_status' 'Tianting artifact must remain offline design.'
        Assert-Equal ([string]$tiantingArtifact.production_gate) 'closed' 'invalid_tt_artifact_production_gate' 'Tianting artifact production gate must remain closed.'
        Assert-Equal ([bool]$tiantingArtifact.non_production) $true 'invalid_tt_artifact_nonproduction' 'Tianting artifact contract must remain non-production.'

        $ttIdentity = $tiantingArtifact.identity
        Assert-Equal ([string]$ttIdentity.graduation_artifact_spec_id) 'TT_SPEC_SEVEN_STAR_GRADUATION_ARTIFACT' 'invalid_tt_artifact_identity' 'Tianting artifact must reuse the existing graduation concept identity.'
        Assert-Equal ([string]$ttIdentity.display_name) $tiantingArtifactDisplayName 'invalid_tt_artifact_name' 'Tianting artifact display name is invalid.'
        Assert-Equal ([string]$ttIdentity.display_name_status) 'accepted_offline_design' 'invalid_tt_artifact_name_status' 'Tianting artifact name status is invalid.'
        Assert-Null $ttIdentity.actual_logical_artifact_key 'invalid_tt_artifact_asset_key' 'Tianting artifact cannot allocate an asset key.'
        Assert-Null $ttIdentity.runtime_item_key 'invalid_tt_artifact_runtime_item_key' 'Tianting artifact cannot allocate a runtime item key.'
        Assert-Equal ([string]$ttIdentity.tier) 'high_endgame' 'invalid_tt_artifact_identity_tier' 'Tianting artifact identity tier is invalid.'

        $ttSlot = $tiantingArtifact.slot_and_loadout_contract
        Assert-Equal ([string]$ttSlot.inherits_artifact_slot_version) 'v1' 'invalid_tt_artifact_slot_version' 'Tianting artifact must inherit v1 slot contract.'
        Assert-Equal ([int]$ttSlot.active_artifact_slot_count) 1 'invalid_tt_artifact_slot_count' 'Tianting artifact must retain one active slot.'
        Assert-Equal ([bool]$ttSlot.inactive_artifact_default_combat_effect) $false 'invalid_tt_artifact_inactive_effect' 'Inactive Tianting artifact cannot have a default combat effect.'
        Assert-Equal ([bool]$ttSlot.artifact_active_ability_occupies_five_active_skill_slots) $false 'invalid_tt_artifact_skill_slot' 'Tianting artifact active must not occupy a five-active skill slot.'

        $ttPlay = $tiantingArtifact.core_play_semantics
        Assert-Equal ([string]$ttPlay.semantic_ability_label) (Decode-Utf8Base64 '5LiD5puc5qCh5b6L') 'invalid_tt_artifact_semantic_label' 'Tianting artifact semantic label is invalid.'
        foreach ($propertyName in @('actual_ability_key', 'actual_effect_values', 'cooldown', 'duration', 'damage')) {
            Assert-Null $ttPlay.$propertyName 'invalid_tt_artifact_semantic_value' "Tianting artifact cannot allocate '$propertyName'."
        }
        $ttForms = @($ttPlay.build_forms)
        Assert-StringSetEqual -Actual @($ttForms | ForEach-Object { [string]$_.form_id }) -Expected @('TT_SPEC_ARTIFACT_FORM_STABILIZE_SEQUENCE', 'TT_SPEC_ARTIFACT_FORM_DISCERN_SEQUENCE', 'TT_SPEC_ARTIFACT_FORM_OPEN_SEQUENCE') -Code 'invalid_tt_artifact_form_set' -Message 'Tianting artifact build forms are invalid.'
        Assert-Equal $ttForms.Count 3 'invalid_tt_artifact_form_count' 'Tianting artifact must retain exactly three mutually exclusive build forms.'

        $ttMaterials = $tiantingArtifact.materials_and_ownership_boundary
        foreach ($propertyName in @('actual_material_keys', 'actual_recipe', 'actual_consumption', 'actual_drop_profiles', 'actual_pity', 'actual_receipts')) {
            Assert-Null $ttMaterials.$propertyName 'invalid_tt_artifact_material_value' "Tianting artifact cannot allocate '$propertyName'."
        }

        $ttAuthority = $tiantingArtifact.authority_and_settlement_boundary
        foreach ($propertyName in @('entry_or_progression_writer', 'session_authority_writer', 'cleanup_bypass', 'current_economy_v2_input')) {
            Assert-Equal ([bool]$ttAuthority.$propertyName) $false 'invalid_tt_artifact_authority_boundary' "Tianting artifact cannot enable '$propertyName'."
        }
        Assert-Null $ttAuthority.current_source_profile 'invalid_tt_artifact_source_profile' 'Tianting artifact cannot allocate a source profile.'
        Assert-Null $ttAuthority.current_reward_slot 'invalid_tt_artifact_reward_slot' 'Tianting artifact cannot allocate a reward slot.'

        Assert-Equal ([string]$tiantingArtifactCompleteDesign.contract_id) 'TT_SPEC_GRADUATION_ARTIFACT_COMPLETE_DESIGN_V1' 'invalid_tt_artifact_complete_design_contract_id' 'Tianting complete-design contract ID is invalid.'
        Assert-Equal ([string]$tiantingArtifactCompleteDesign.identity.display_name) $tiantingArtifactDisplayName 'invalid_tt_artifact_complete_design_name' 'Tianting complete-design display name is invalid.'
        Assert-Equal ([bool]$tiantingArtifactCompleteDesign.runtime_handoff) $false 'invalid_tt_artifact_complete_design_runtime' 'Tianting complete-design cannot enable runtime handoff.'
        Assert-Equal ([string]$tiantingArtifactCompleteDesign.production_gate) 'closed' 'invalid_tt_artifact_complete_design_production' 'Tianting complete-design must keep production closed.'
        Assert-Equal ([int](@($tiantingArtifactCompleteDesign.form_designs).Count)) 3 'invalid_tt_artifact_complete_design_forms' 'Tianting complete-design must retain three response forms.'
        Assert-Equal ([bool]$tiantingArtifactCompleteDesign.authority_failure_and_settlement_boundary.economy_v2_input) $false 'invalid_tt_artifact_complete_design_economy' 'Tianting complete-design cannot write economy-v2 input.'

        foreach ($property in $tiantingArtifact.deferred.PSObject.Properties) {
            Assert-Null $property.Value 'invalid_tt_artifact_deferred_value' "Tianting artifact deferred field '$($property.Name)' must remain null."
        }
        Assert-True (@($matrix.lineage_invariants | ForEach-Object { [string]$_ }) -contains 'TT base graduation access must retain a future ordinary or celestial-law path that is individually reachable; nightmare Four Sacred content may be optional but cannot be the unique mandatory source.') 'invalid_lineage_tt_artifact_base_path_invariant' 'Three-chapter lineage must retain the Tianting non-team base-path invariant.'

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
        $forbiddenPaths += @(Get-ForbiddenPropertyPaths -Node $difuArtifact -Path 'difu-midgame-artifact' -Forbidden $forbiddenRuntimeProperties)
        $forbiddenPaths += @(Get-ForbiddenPropertyPaths -Node $difuArtifactDetail -Path 'difu-two-artifact-detail' -Forbidden $forbiddenRuntimeProperties)
        $forbiddenPaths += @(Get-ForbiddenPropertyPaths -Node $tiantingArtifact -Path 'tianting-endgame-artifact' -Forbidden $forbiddenRuntimeProperties)
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
