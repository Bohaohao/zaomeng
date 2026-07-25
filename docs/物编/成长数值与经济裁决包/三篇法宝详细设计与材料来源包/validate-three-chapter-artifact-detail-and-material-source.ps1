$ErrorActionPreference = 'Stop'

function Add-Error {
    param([string]$Message)
    $script:Errors.Add($Message) | Out-Null
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { Add-Error $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ([string]$Actual -ne [string]$Expected) { Add-Error "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-Null {
    param($Value, [string]$Message)
    if ($null -ne $Value) { Add-Error "$Message Expected null." }
}

function Get-ItemByProperty {
    param($Items, [string]$Property, [string]$Value)
    return @($Items | Where-Object { [string]$_.PSObject.Properties[$Property].Value -eq $Value })
}

$Errors = [System.Collections.Generic.List[string]]::new()
$PackageRoot = Split-Path -Parent $PSCommandPath
$EconomyRoot = Split-Path -Parent $PackageRoot
$ObjectRoot = Split-Path -Parent $EconomyRoot
$Utf8 = [System.Text.Encoding]::UTF8
function Decode-Base64Utf8 { param([string]$Value) return $Utf8.GetString([Convert]::FromBase64String($Value)) }
$DifuArtifactFolder = Decode-Base64Utf8 '5Zyw5bqc5Lit5pyf5rOV5a6d6KOB5Yaz5YyF'
$TiantingFolder = Decode-Base64Utf8 '5aSp5bqt56+H5Li757q/6YGt6YGH5LiO6YCa5aSp5aGU6KeE5qC85YyF'
$TideSealName = Decode-Base64Utf8 '5a6a5r2u546E5Y2w'
$FlameCoreName = Decode-Base64Utf8 '54aU6ISJ5Yqr5qC4'
$NonTeamToken = Decode-Base64Utf8 '6Z2e5Zui6Zif'
$BaiguProtection = Decode-Base64Utf8 '5LuF5Li65Lia6ZWc6Leo5b2i5oCB5ZCM5rqQ55eV6L+555qE5Y2V5Lq65qOA6aqM5Zy677yM5LiN5Lqn5Ye65qC45b+D5p2Q5paZ44CB6Zi25q615oiW6LWE5qC844CC'
$ZhuanlunProtection = Decode-Base64Utf8 '5LuF5Li65a6I5bqP5Lqk5o6l5LiO6K6w5b+G5LqS6K+B55qE5Zui6Zif5qOA6aqM5Zy677yM5LiN5Lqn5Ye65qC45b+D5p2Q5paZ44CB6Zi25q615oiW6LWE5qC844CC'
$TiantingArtifactDisplayName = Decode-Base64Utf8 '5ZGo5aSp5qCh5b6L55uY'
$FourSymbolsPresentationName = Decode-Base64Utf8 '5Zub6LGh6KaG546v'
$NoCombatPattern = Decode-Base64Utf8 '5LiNLirmiJjmlpc='
$ContractPath = Join-Path $PackageRoot 'three-chapter-artifact-detail-and-material-source-contract.json'
$LineagePath = Join-Path $EconomyRoot 'three-chapter-growth-lineage-contract.json'
$EconomyPath = Join-Path $EconomyRoot 'tables/economy-v2-resource-table.json'
$DifuPositioningPath = Join-Path $EconomyRoot (Join-Path $DifuArtifactFolder 'difu-midgame-artifact-positioning-and-replacement-contract.json')
$DifuDetailPath = Join-Path $EconomyRoot (Join-Path $DifuArtifactFolder 'two-artifact-detail/difu-two-artifact-detailed-design-contract.json')
$TiantingContentPath = Join-Path $ObjectRoot (Join-Path $TiantingFolder 'tianting-content-expansion-contract.json')
$TiantingArtifactPath = Join-Path $ObjectRoot (Join-Path $TiantingFolder 'artifact-graduation/tianting-endgame-artifact-positioning-and-lineage-contract.json')
$TiantingArtifactCompleteDesignPath = Join-Path $ObjectRoot (Join-Path $TiantingFolder 'artifact-graduation/complete-design/tianting-graduation-artifact-complete-design-contract.json')

foreach ($Path in @($ContractPath, $LineagePath, $EconomyPath, $DifuPositioningPath, $DifuDetailPath, $TiantingContentPath, $TiantingArtifactPath, $TiantingArtifactCompleteDesignPath)) {
    Assert-True (Test-Path -LiteralPath $Path) "Required source is missing: $Path"
}

if ($Errors.Count -eq 0) {
    $Contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $Lineage = Get-Content -LiteralPath $LineagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $Economy = Get-Content -LiteralPath $EconomyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $DifuPositioning = Get-Content -LiteralPath $DifuPositioningPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $DifuDetail = Get-Content -LiteralPath $DifuDetailPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $TiantingContent = Get-Content -LiteralPath $TiantingContentPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $TiantingArtifact = Get-Content -LiteralPath $TiantingArtifactPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $TiantingArtifactCompleteDesign = Get-Content -LiteralPath $TiantingArtifactCompleteDesignPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Assert-Equal $Contract.contract_id 'THREE_CHAPTER_ARTIFACT_DETAIL_AND_MATERIAL_SOURCE_V1' 'Contract ID is invalid.'
    Assert-Equal $Contract.schema_version 1 'Contract schema is invalid.'
    Assert-Equal $Contract.artifact_kind 'offline_three_chapter_artifact_detail_and_material_source_contract' 'Contract kind is invalid.'
    Assert-Equal $Contract.status 'accepted-offline-design' 'Contract status is invalid.'
    Assert-True (-not [bool]$Contract.runtime_handoff) 'Runtime handoff must remain false.'
    Assert-Equal $Contract.production_gate 'closed' 'Production gate must remain closed.'
    Assert-Equal @($Contract.source_contracts).Count 9 'Exactly nine declared source contracts are required.'
    foreach ($SourceContract in @($Contract.source_contracts)) {
        $DeclaredPath = [string]$SourceContract.path
        Assert-True (-not [string]::IsNullOrWhiteSpace($DeclaredPath)) 'A declared source contract path is missing.'
        if (-not [string]::IsNullOrWhiteSpace($DeclaredPath)) {
            $ResolvedSourcePath = Join-Path $PackageRoot ($DeclaredPath -replace '/', '\\')
            Assert-True (Test-Path -LiteralPath $ResolvedSourcePath -PathType Leaf) "Declared source contract does not resolve: $DeclaredPath"
        }
    }

    foreach ($Property in @('actual_item_assets','new_logical_artifact_keys','runtime_item_keys','ability_assets','combat_stat_values','cooldowns','durations','ranges','target_counts','new_material_keys','material_quantities','recipes','consumption_rules','new_source_profiles','new_drop_rates','new_pity_rules','qualification_snapshots','receipt_schemas','y3_object_allocation')) {
        Assert-Null $Contract.non_production_boundary.$Property "Non-production boundary '$Property' is invalid."
    }
    Assert-True (-not [bool]$Contract.non_production_boundary.economy_execution) 'Economy execution must remain false.'

    Assert-Equal $Contract.global_artifact_rules.active_artifact_slot_count 1 'Exactly one active artifact slot is required.'
    Assert-True (-not [bool]$Contract.global_artifact_rules.inactive_artifact_default_effect) 'Inactive artifacts must not retain effects.'
    Assert-True (-not [bool]$Contract.global_artifact_rules.challenge_local_switch_allowed) 'Challenge local switching must remain forbidden.'
    Assert-True (-not [bool]$Contract.global_artifact_rules.death_disconnect_or_cleanup_switch_allowed) 'Death/disconnect/cleanup switching must remain forbidden.'
    Assert-True (-not [bool]$Contract.global_artifact_rules.mainline_or_entry_artifact_requirement) 'Artifacts must not be chapter requirements.'
    Assert-True (-not [bool]$Contract.global_artifact_rules.later_stage_auto_consumes_earlier_artifact) 'Later stages must not auto-consume prior artifacts.'
    Assert-Equal @($Contract.global_artifact_rules.difficulty_bands).Count 5 'Exactly five relative difficulty bands are required.'
    $D2DifficultyBand = @(Get-ItemByProperty @($Contract.global_artifact_rules.difficulty_bands) 'band_id' 'D2_NONTEAM_MECHANISM_VERIFICATION')
    Assert-Equal $D2DifficultyBand.Count 1 'Exactly one non-team mechanism verification difficulty band is required.'
    if ($D2DifficultyBand.Count -eq 1) {
        $D2Meaning = [string]$D2DifficultyBand[0].meaning
        Assert-True (($D2Meaning -match 'non-team|nonteam') -or ($D2Meaning -match [regex]::Escape($NonTeamToken))) 'The D2 difficulty band must permit non-team mainline verification rather than optional solo content only.'
    }

    $Chapters = @($Contract.chapters)
    Assert-Equal $Chapters.Count 3 'Exactly three chapters are required.'
    $HG = @(Get-ItemByProperty $Chapters 'chapter_id' 'HG')
    $DF = @(Get-ItemByProperty $Chapters 'chapter_id' 'DF')
    $TT = @(Get-ItemByProperty $Chapters 'chapter_id' 'TT')
    Assert-Equal $HG.Count 1 'Huaguoshan chapter is missing or duplicated.'
    Assert-Equal $DF.Count 1 'Difu chapter is missing or duplicated.'
    Assert-Equal $TT.Count 1 'Tianting chapter is missing or duplicated.'

    if ($HG.Count -eq 1) {
        $HGArtifacts = @($HG[0].artifacts)
        Assert-Equal $HGArtifacts.Count 2 'Huaguoshan must have exactly two artifacts.'
        $Tide = @(Get-ItemByProperty $HGArtifacts 'artifact_spec_id' 'HG_SPEC_ARTIFACT_TIDE_SEAL_DETAIL')
        $Flame = @(Get-ItemByProperty $HGArtifacts 'artifact_spec_id' 'HG_SPEC_ARTIFACT_FLAME_CORE_DETAIL')
        Assert-Equal $Tide.Count 1 'Tide Seal detail is missing or duplicated.'
        Assert-Equal $Flame.Count 1 'Flame Core detail is missing or duplicated.'
        if ($Tide.Count -eq 1) {
            Assert-Equal $Tide[0].existing_logical_artifact_key 'ART_HG_TIDE_SEAL' 'Tide Seal logical key is invalid.'
            Assert-Equal $Tide[0].display_name $TideSealName 'Tide Seal display name is invalid.'
            Assert-Equal $Tide[0].acquisition_route.source_node_id 'HG_E_DRAGON_OLD_TIDE' 'Tide Seal source node is invalid.'
            Assert-Equal $Tide[0].acquisition_route.existing_authoritative_source_profile_reference 'HG_DROP_DRAGON_OLD' 'Tide Seal profile reference is invalid.'
            Assert-Equal $Tide[0].acquisition_route.relative_difficulty_band 'D2_NONTEAM_MECHANISM_VERIFICATION' 'Tide Seal difficulty band is invalid.'
            Assert-True ([bool]$Tide[0].acquisition_route.base_access_nonrandom) 'Tide Seal base access must be nonrandom.'
            Assert-Null $Tide[0].recommended_equip_level 'Tide Seal numeric equip level is not allowed.'
            Assert-Equal @($Tide[0].material_source_blueprints).Count 2 'Tide Seal must have two material blueprints.'
            foreach ($Material in @($Tide[0].material_source_blueprints)) {
                foreach ($Property in @('actual_material_key','quantity','drop_rate','pity','recipe','consumption')) { Assert-Null $Material.$Property "Tide material '$($Material.material_spec_id)' field '$Property' is not allowed." }
            }
            foreach ($Property in @('damage','cooldown','duration','range','target_count')) { Assert-Null $Tide[0].gameplay_card.$Property "Tide gameplay field '$Property' is not allowed." }
        }
        if ($Flame.Count -eq 1) {
            Assert-Equal $Flame[0].existing_logical_artifact_key 'ART_HG_FLAME_CORE' 'Flame Core logical key is invalid.'
            Assert-Equal $Flame[0].display_name $FlameCoreName 'Flame Core display name is invalid.'
            Assert-Equal $Flame[0].acquisition_route.source_node_id 'HG_E_OX_BATTLEFIELD' 'Flame Core source node is invalid.'
            Assert-Equal $Flame[0].acquisition_route.existing_authoritative_source_profile_reference 'HG_DROP_OX_RAID' 'Flame Core profile reference is invalid.'
            Assert-Equal $Flame[0].acquisition_route.relative_difficulty_band 'D4_TEAM_RARE_OR_MASTERY' 'Flame Core difficulty band is invalid.'
            Assert-True (-not [bool]$Flame[0].acquisition_route.base_access_nonrandom) 'Flame Core must remain an existing rare path.'
            Assert-Null $Flame[0].recommended_equip_level 'Flame Core numeric equip level is not allowed.'
            Assert-Equal @($Flame[0].material_source_blueprints).Count 2 'Flame Core must have two material blueprints.'
            foreach ($Material in @($Flame[0].material_source_blueprints)) {
                foreach ($Property in @('actual_material_key','quantity','drop_rate','pity','recipe','consumption')) { Assert-Null $Material.$Property "Flame material '$($Material.material_spec_id)' field '$Property' is not allowed." }
            }
            foreach ($Property in @('damage','cooldown','duration','range','target_count')) { Assert-Null $Flame[0].gameplay_card.$Property "Flame gameplay field '$Property' is not allowed." }
        }
    }

    $Profiles = @($Economy.drops_and_pity.profiles)
    $DragonProfile = @(Get-ItemByProperty $Profiles 'profile_key' 'HG_DROP_DRAGON_OLD')
    $OxProfile = @(Get-ItemByProperty $Profiles 'profile_key' 'HG_DROP_OX_RAID')
    Assert-Equal $DragonProfile.Count 1 'economy-v2 Dragon Old profile is missing.'
    Assert-Equal $OxProfile.Count 1 'economy-v2 Ox profile is missing.'
    if ($DragonProfile.Count -eq 1) {
        Assert-Equal $DragonProfile[0].first_clear.key 'ART_HG_TIDE_SEAL' 'economy-v2 Tide Seal first clear must remain unchanged.'
        Assert-Equal $DragonProfile[0].first_clear.duplicate_conversion.key 'MAT_ARTIFACT_DUST' 'economy-v2 Tide Seal duplicate conversion key must remain unchanged.'
        Assert-Equal $DragonProfile[0].first_clear.duplicate_conversion.amount 8 'economy-v2 Tide Seal duplicate conversion amount must remain unchanged.'
    }
    if ($OxProfile.Count -eq 1) {
        Assert-Equal $OxProfile[0].rare.key 'ART_HG_FLAME_CORE' 'economy-v2 Flame Core rare key must remain unchanged.'
        Assert-Equal $OxProfile[0].rare.chance_basis_points 800 'economy-v2 Flame Core chance basis points must remain unchanged.'
        Assert-Equal $OxProfile[0].rare.pity_pool_key 'PITY_HG_RAID_ARTIFACT' 'economy-v2 Flame Core pity pool must remain unchanged.'
        Assert-Equal $OxProfile[0].rare.guarantee_on_eligible_attempt 6 'economy-v2 Flame Core guarantee attempt must remain unchanged.'
        Assert-Equal $OxProfile[0].rare.duplicate_conversion.key 'CUR_RAID_MARK' 'economy-v2 Flame Core duplicate conversion key must remain unchanged.'
        Assert-Equal $OxProfile[0].rare.duplicate_conversion.amount 3 'economy-v2 Flame Core duplicate conversion amount must remain unchanged.'
    }
    $RaidPityPool = @(Get-ItemByProperty @($Economy.drops_and_pity.pity_pools) 'pity_pool_key' 'PITY_HG_RAID_ARTIFACT')
    Assert-Equal $RaidPityPool.Count 1 'economy-v2 Flame Core pity pool is missing or duplicated.'
    if ($RaidPityPool.Count -eq 1) {
        Assert-Equal $RaidPityPool[0].owner_scope 'character' 'economy-v2 Flame Core pity owner scope must remain character.'
        Assert-Equal @($RaidPityPool[0].eligible_profile_keys).Count 1 'economy-v2 Flame Core pity profile count is invalid.'
        Assert-Equal @($RaidPityPool[0].eligible_profile_keys)[0] 'HG_DROP_OX_RAID' 'economy-v2 Flame Core pity profile is invalid.'
    }

    if ($DF.Count -eq 1) {
        $DFArtifacts = @($DF[0].artifacts)
        Assert-Equal $DFArtifacts.Count 2 'Difu must have exactly two artifacts.'
        $Lantern = @(Get-ItemByProperty $DFArtifacts 'artifact_spec_id' 'DF_SPEC_ARTIFACT_GUIDING_LANTERN')
        $Mirror = @(Get-ItemByProperty $DFArtifacts 'artifact_spec_id' 'DF_SPEC_ARTIFACT_KARMIC_MIRROR')
        Assert-Equal $Lantern.Count 1 'Guiding Lantern is missing or duplicated.'
        Assert-Equal $Mirror.Count 1 'Karmic Mirror is missing or duplicated.'
        if ($Lantern.Count -eq 1) {
            Assert-Equal $Lantern[0].acquisition_route.source_node_id 'DF_NODE_GUIDING_COURT' 'Guiding Lantern must anchor to Guiding Court.'
            Assert-Equal $Lantern[0].acquisition_route.relative_difficulty_band 'D1_REGULAR_TEACHING_GUARANTEED' 'Guiding Lantern difficulty is invalid.'
            Assert-True ([bool]$Lantern[0].acquisition_route.base_access_nonrandom) 'Guiding Lantern base offer must be nonrandom.'
            Assert-Null $Lantern[0].acquisition_route.actual_source_event 'Guiding Lantern must not create a source event.'
            foreach ($Material in @($Lantern[0].material_source_blueprints)) {
                Assert-True (@('DF_NODE_GUIDING_COURT','DF_NODE_JUDGE_HALL') -contains [string]$Material.drop_point_node_id) 'Guiding Lantern material source is outside the standard route.'
                foreach ($Property in @('actual_material_key','quantity','drop_rate','pity','recipe','consumption')) { Assert-Null $Material.$Property "Lantern material '$($Material.material_spec_id)' field '$Property' is not allowed." }
            }
        }
        if ($Mirror.Count -eq 1) {
            Assert-Equal $Mirror[0].acquisition_route.source_node_id 'DF_NODE_JUDGE_HALL' 'Karmic Mirror must anchor to Judge Hall.'
            Assert-Equal $Mirror[0].acquisition_route.relative_difficulty_band 'D2_NONTEAM_MECHANISM_VERIFICATION' 'Karmic Mirror difficulty band is invalid.'
            Assert-True ([bool]$Mirror[0].acquisition_route.base_access_nonrandom) 'Karmic Mirror base offer must be nonrandom.'
            Assert-Null $Mirror[0].acquisition_route.actual_source_event 'Karmic Mirror must not create a source event.'
            foreach ($Material in @($Mirror[0].material_source_blueprints)) {
                Assert-True (@('DF_NODE_JUDGE_HALL','DF_NODE_YANLUO_HALL') -contains [string]$Material.drop_point_node_id) 'Karmic Mirror material source is outside the standard route.'
                foreach ($Property in @('actual_material_key','quantity','drop_rate','pity','recipe','consumption')) { Assert-Null $Material.$Property "Mirror material '$($Material.material_spec_id)' field '$Property' is not allowed." }
            }
            Assert-Equal $Mirror[0].optional_content_protection.DF_SIDE_BAIGU_SECRET_REALM $BaiguProtection 'Baigu protection is invalid.'
            Assert-Equal $Mirror[0].optional_content_protection.DF_NODE_ZHUANLUN_HALL $ZhuanlunProtection 'Zhuanlun protection is invalid.'
        }
    }

    Assert-Equal $DifuPositioning.contract_id 'DF_SPEC_MIDGAME_ARTIFACT_POSITIONING_REPLACEMENT_V1' 'Existing Difu positioning contract is invalid.'
    Assert-Equal $DifuPositioning.slot_and_loadout_contract.active_artifact_slot_count 1 'Existing Difu positioning contract must retain one active artifact slot.'
    Assert-True (-not [bool]$DifuPositioning.slot_and_loadout_contract.adds_another_active_slot) 'Existing Difu positioning contract cannot add an active artifact slot.'
    Assert-True (-not [bool]$DifuPositioning.cross_chapter_protection.this_contract_reads_or_writes_protected_difu_progress_key) 'Existing Difu positioning contract must not read or write protected progression.'
    Assert-Equal $DifuPositioning.cross_chapter_protection.protected_difu_progress_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'Existing Difu positioning contract protected progress key is invalid.'
    Assert-True (-not [bool]$DifuPositioning.cross_chapter_protection.tianting_entry_requires_artifact) 'Existing Difu positioning contract cannot gate Tianting entry with an artifact.'
    Assert-Equal $DifuDetail.identity_policy.artifact_spec_count 2 'Existing Difu detail must remain exactly two artifacts.'
    Assert-Equal $DifuDetail.chapter_shared_resolution.classification 'chapter_shared_correct_resolution' 'Huizheng must remain a shared chapter resolution.'
    Assert-True (-not [bool]$DifuDetail.cross_chapter_and_session_guards.reads_or_writes_protected_progress_key) 'Difu artifacts must not read or write protected progression.'

    if ($TT.Count -eq 1) {
        $TTArtifacts = @($TT[0].artifacts)
        Assert-Equal $TTArtifacts.Count 1 'Tianting must have exactly one graduation artifact identity.'
        $Graduation = @(Get-ItemByProperty $TTArtifacts 'artifact_spec_id' 'TT_SPEC_SEVEN_STAR_GRADUATION_ARTIFACT')
        Assert-Equal $Graduation.Count 1 'Seven Star graduation artifact is missing or duplicated.'
        if ($Graduation.Count -eq 1) {
            Assert-Equal $Graduation[0].display_name $TiantingArtifactDisplayName 'Tianting graduation display name is invalid.'
            Assert-Equal $Graduation[0].display_name_status 'accepted_offline_design' 'Tianting graduation display-name status is invalid.'
            Assert-Equal $Graduation[0].acquisition_route.source_node_id 'TT_SPEC_MAINLINE_NODE_04_CELESTIAL_OBSERVATORY' 'Graduation collection start node is invalid.'
            Assert-Equal $Graduation[0].acquisition_route.relative_difficulty_band 'D3_REGULAR_LATE_CHAPTER_OR_COLLECTION' 'Graduation difficulty band is invalid.'
            Assert-True ([bool]$Graduation[0].acquisition_route.base_access_nonrandom) 'Graduation base route must remain nonrandom at design level.'
            Assert-Null $Graduation[0].recommended_equip_level 'Graduation numeric equip level is not allowed.'
            $Materials = @($Graduation[0].material_source_blueprints)
            Assert-Equal $Materials.Count 9 'Graduation must define seven fragments plus two catalyst themes.'
            $ExpectedFragments = @(
                'TT_SPEC_MATERIAL_TIANSHU_FRAGMENT|TT_SPEC_SOLO_TIANSHU',
                'TT_SPEC_MATERIAL_TIANXUAN_FRAGMENT|TT_SPEC_SOLO_TIANXUAN',
                'TT_SPEC_MATERIAL_TIANJI_FRAGMENT|TT_SPEC_SOLO_TIANJI',
                'TT_SPEC_MATERIAL_TIANQUAN_FRAGMENT|TT_SPEC_SOLO_TIANQUAN',
                'TT_SPEC_MATERIAL_YUHENG_FRAGMENT|TT_SPEC_SOLO_YUHENG',
                'TT_SPEC_MATERIAL_KAIYANG_FRAGMENT|TT_SPEC_SOLO_KAIYANG',
                'TT_SPEC_MATERIAL_YAOGUANG_FRAGMENT|TT_SPEC_SOLO_YAOGUANG'
            )
            $ActualFragments = @($Materials | Where-Object { [string]$_.material_spec_id -match '_FRAGMENT$' } | ForEach-Object { "$($_.material_spec_id)|$($_.drop_point_node_id)" })
            Assert-True ((Compare-Object -ReferenceObject $ExpectedFragments -DifferenceObject $ActualFragments).Count -eq 0) 'Seven fragment source mapping is invalid.'
            $CelestialLaw = @(Get-ItemByProperty $Materials 'material_spec_id' 'TT_SPEC_MATERIAL_CELESTIAL_LAW_SEAL')
            $FourSacred = @(Get-ItemByProperty $Materials 'material_spec_id' 'TT_SPEC_MATERIAL_FOUR_SACRED_FORGE_CORE')
            Assert-Equal $CelestialLaw.Count 1 'Celestial Law Seal material is missing or duplicated.'
            Assert-Equal $FourSacred.Count 1 'Four Sacred Forge Core material is missing or duplicated.'
            if ($CelestialLaw.Count -eq 1) {
                Assert-Equal $CelestialLaw[0].drop_point_node_id 'TT_SPEC_MAINLINE_NODE_05_LINGXIAO_OUTER_COURT' 'Celestial Law Seal must come from Lingxiao Outer Court.'
                Assert-True ([bool]$CelestialLaw[0].required_for_base_collection_concept) 'Celestial Law Seal must protect the base route.'
            }
            if ($FourSacred.Count -eq 1) {
                Assert-Equal $FourSacred[0].drop_point_node_id 'TT_SPEC_MANSION_NIGHTMARE_MODE' 'Four Sacred Forge Core source is invalid.'
                Assert-Equal $FourSacred[0].upstream_reward_family_spec_id 'TT_SPEC_REWARD_SACRED_BEAST_CORE' 'Four Sacred Forge Core reward-family mapping is invalid.'
                Assert-True (-not [bool]$FourSacred[0].required_for_base_collection_concept) 'Four Sacred Forge Core must remain optional.'
                Assert-True ([string]$FourSacred[0].role -match [regex]::Escape($FourSymbolsPresentationName)) 'Four Sacred Forge Core must only serve Four Symbols presentation.'
                Assert-True ([string]$FourSacred[0].role -match $NoCombatPattern) 'Four Sacred Forge Core must not provide combat strength.'
            }
            foreach ($Material in $Materials) {
                foreach ($Property in @('actual_material_key','quantity','drop_rate','pity','recipe','consumption')) { Assert-Null $Material.$Property "Tianting material '$($Material.material_spec_id)' field '$Property' is not allowed." }
            }
            Assert-Equal $Graduation[0].title_and_double_spend_boundary.user_fixed_same_star_title_count 10 'Seven Star title count must preserve the user-fixed rule.'
            Assert-Null $Graduation[0].title_and_double_spend_boundary.current_consumption_rule 'Title consumption rule must remain deferred.'
            Assert-Null $Graduation[0].title_and_double_spend_boundary.current_receipt_rule 'Title receipt rule must remain deferred.'
        }
    }

    Assert-Equal $TiantingArtifact.identity.graduation_artifact_spec_id 'TT_SPEC_SEVEN_STAR_GRADUATION_ARTIFACT' 'Existing Tianting graduation identity is invalid.'
    Assert-Equal $TiantingArtifact.identity.display_name $TiantingArtifactDisplayName 'Existing Tianting graduation display name is invalid.'
    Assert-Equal $TiantingArtifact.identity.display_name_status 'accepted_offline_design' 'Existing Tianting graduation display-name status is invalid.'
    Assert-Null $TiantingArtifact.materials_and_ownership_boundary.actual_material_keys 'Existing Tianting material keys must remain deferred.'
    Assert-Null $TiantingArtifact.materials_and_ownership_boundary.actual_recipe 'Existing Tianting recipe must remain deferred.'
    Assert-Equal $TiantingArtifactCompleteDesign.contract_id 'TT_SPEC_GRADUATION_ARTIFACT_COMPLETE_DESIGN_V1' 'Tianting complete-design contract identity is invalid.'
    Assert-Equal $TiantingArtifactCompleteDesign.identity.display_name $TiantingArtifactDisplayName 'Tianting complete-design display name is invalid.'
    Assert-Equal $TiantingArtifactCompleteDesign.optional_sacred_attestation.presentation_name (Decode-Base64Utf8 '5Zub6LGh6KaG546v') 'Tianting complete-design sacred presentation is invalid.'
    Assert-Null $TiantingArtifactCompleteDesign.non_production_boundary.actual_item_key 'Tianting complete-design cannot allocate an item key.'
    Assert-Null $TiantingArtifactCompleteDesign.non_production_boundary.actual_ability_asset 'Tianting complete-design cannot allocate an ability asset.'
    Assert-Equal $TiantingContent.seven_star_solo.star_titles.same_star_fragment_units_required 10 'Existing user-fixed title count is invalid.'

    foreach ($Property in @('absolute_combat_values','recommended_numeric_equip_levels','actual_item_assets','actual_material_keys_and_quantities','actual_recipe_and_consumption','actual_drop_profiles_and_rates','actual_pity_and_qualification','actual_receipts_and_backpack_rules','y3_object_and_lua_implementation')) {
        Assert-Null $Contract.deferred.$Property "Deferred field '$Property' is invalid."
    }
    Assert-Equal @($Contract.acceptance_matrix).Count 7 'Exactly seven acceptance entries are required.'
}

if ($Errors.Count -gt 0) {
    Write-Output '{'
    Write-Output '  "ok": false,'
    Write-Output '  "errors": ['
    for ($Index = 0; $Index -lt $Errors.Count; $Index++) {
        $Suffix = if ($Index -lt ($Errors.Count - 1)) { ',' } else { '' }
        $Escaped = $Errors[$Index].Replace('"','\"')
        Write-Output ('    "{0}"{1}' -f $Escaped, $Suffix)
    }
    Write-Output '  ]'
    Write-Output '}'
    exit 1
}

Write-Output 'PASS: three-chapter artifact detail and material-source contract is internally consistent, chapter-aligned, and non-production.'
