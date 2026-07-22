[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$script:Checks = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()
$PackageRoot = Split-Path -Parent $PSCommandPath

function Test-HasProperty {
  param($Object, [string]$Name)
  return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-Condition {
  param([bool]$Condition, [string]$Name)
  $script:Checks++
  if (-not $Condition) {
    $script:Errors.Add($Name) | Out-Null
  }
}

function Assert-Equal {
  param($Actual, $Expected, [string]$Name)
  Assert-Condition ($Actual -eq $Expected) "$Name; expected '$Expected', got '$Actual'"
}

function Assert-Null {
  param($Actual, [string]$Name)
  Assert-Condition ($null -eq $Actual) "$Name; expected null"
}

function Assert-Array {
  param($Actual, [string]$Name)
  Assert-Condition ($Actual -is [System.Array]) "$Name; expected an array"
}

function Assert-ExactArray {
  param($Actual, [string[]]$Expected, [string]$Name)
  Assert-Array $Actual $Name
  Assert-Condition ((@($Actual) -join '|') -eq (@($Expected) -join '|')) "$Name; expected '$(@($Expected) -join '|')', got '$(@($Actual) -join '|')'"
}

function Assert-RequiredProperties {
  param($Object, [string[]]$Names, [string]$Name)
  foreach ($PropertyName in $Names) {
    Assert-Condition (Test-HasProperty $Object $PropertyName) "$Name property exists: $PropertyName"
  }
}

function Assert-AllRuntimeKeysNull {
  param($Value, [string]$Path)

  if ($null -eq $Value -or $Value -is [string]) {
    return
  }

  if ($Value -is [System.Array]) {
    for ($Index = 0; $Index -lt $Value.Count; $Index++) {
      Assert-AllRuntimeKeysNull $Value[$Index] "${Path}[$Index]"
    }
    return
  }

  if ($Value -is [pscustomobject]) {
    foreach ($Property in $Value.PSObject.Properties) {
      $PropertyPath = "$Path.$($Property.Name)"
      if ($Property.Name -match '^runtime(?:_.+)?_key$') {
        Assert-Null $Property.Value "$PropertyPath"
      }
      Assert-AllRuntimeKeysNull $Property.Value $PropertyPath
    }
  }
}

function Assert-NoForbiddenPropertyNames {
  param($Value, [string[]]$ForbiddenNames, [string]$Path)

  if ($null -eq $Value -or $Value -is [string]) {
    return
  }

  if ($Value -is [System.Array]) {
    for ($Index = 0; $Index -lt $Value.Count; $Index++) {
      Assert-NoForbiddenPropertyNames $Value[$Index] $ForbiddenNames "${Path}[$Index]"
    }
    return
  }

  if ($Value -is [pscustomobject]) {
    foreach ($Property in $Value.PSObject.Properties) {
      $PropertyPath = "$Path.$($Property.Name)"
      Assert-Condition (-not ($ForbiddenNames -contains [string]$Property.Name)) "$PropertyPath is not a forbidden production field"
      Assert-NoForbiddenPropertyNames $Property.Value $ForbiddenNames $PropertyPath
    }
  }
}

function Read-JsonFile {
  param([string]$Path)
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

try {
  $RequiredFiles = @(
    'README.md',
    'decision-register.md',
    'tianting-mainline-tower-contract.json',
    'tianting-content-expansion-contract.json',
    'authority/tianting-progression-and-instance-authority-contract.json',
    'mainline-route.md',
    'topology-whitebox.md',
    'encounters/天庭公共遭遇规格.md',
    'instances/七星单人本规格.md',
    'instances/二十八星宿团队本规格.md',
    'economy-candidates/天庭奖励候选登记.md',
    'tower/天庭Boss复用接口.md',
    'references/西游记与造梦参考.md',
    'tower-first-cycle-state-contract.json',
    'tower-first-cycle-sequence.md',
    'design-spec.json',
    'design-spec-report.md',
    'acceptance-matrix.md',
    'validation-report.md',
    'validate-tianting-tower-spec.ps1',
    'handoff/object-config-brief.json',
    'handoff/terrain-layout-brief.json',
    'handoff/lua-logic-brief.md',
    'handoff/ui-brief.md',
    'handoff/review-brief.md'
  )

  foreach ($RelativePath in $RequiredFiles) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $PackageRoot $RelativePath) -PathType Leaf) "required file exists: $RelativePath"
  }

  $Contract = Read-JsonFile (Join-Path $PackageRoot 'tianting-mainline-tower-contract.json')
  $Expansion = Read-JsonFile (Join-Path $PackageRoot 'tianting-content-expansion-contract.json')
  $Authority = Read-JsonFile (Join-Path $PackageRoot 'authority/tianting-progression-and-instance-authority-contract.json')
  $FirstCycle = Read-JsonFile (Join-Path $PackageRoot 'tower-first-cycle-state-contract.json')
  $Design = Read-JsonFile (Join-Path $PackageRoot 'design-spec.json')
  $ObjectBrief = Read-JsonFile (Join-Path $PackageRoot 'handoff/object-config-brief.json')
  $TerrainBrief = Read-JsonFile (Join-Path $PackageRoot 'handoff/terrain-layout-brief.json')

  Assert-Equal $Contract.version 1 'contract version'
  Assert-Equal $Contract.package_status 'offline-design-spec' 'contract package status'
  Assert-Equal $Contract.production_gate 'closed' 'contract production gate'
  Assert-Equal $Contract.hard_constraints.level_band.min_level 41 'TianTing minimum level'
  Assert-Equal $Contract.hard_constraints.level_band.max_level 60 'TianTing maximum level'
  Assert-Equal $Contract.hard_constraints.tower_entry.minimum_level 55 'tower minimum level'
  Assert-Equal $Contract.hard_constraints.tower_entry.member_check 'every_solo_player_or_team_member_independently' 'tower per-member check'
  Assert-Equal $Contract.hard_constraints.tower_entry.loadout_rest_every_floors 5 'tower rest interval'
  Assert-Equal $Contract.hard_constraints.tower_identity.rule 'linglong_theme_within_global_tongtian_tower' 'tower identity'
  Assert-Equal $Contract.hard_constraints.tower_identity.must_not_create 'a_second_long_term_tower_system' 'second tower prohibition'

  $Cross = $Contract.hard_constraints.cross_chapter_boundary
  Assert-Equal $Cross.protected_existing_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'protected Difu key'
  Assert-Equal $Cross.current_allowed_consumer 'HG_E_DRAGON_REVERSE_TIDE' 'existing allowed Difu key consumer'
  Assert-Equal $Cross.tianting_rule 'must_not_consume_or_write_protected_existing_key; entry may only verify an opaque handoff proof whose trusted source producer is DF_E_YANLUO_HALL' 'TianTing Difu-key prohibition'
  Assert-Equal $Cross.entry_contract.status 'offline_design' 'TianTing entry contract status'
  Assert-Equal $Cross.entry_contract.artifact 'authority/tianting-progression-and-instance-authority-contract.json' 'entry authority-contract artifact'
  Assert-Equal $Cross.entry_contract.entry_progress_spec_id 'TT_SPEC_PROGRESS_CHAPTER_ENTERED' 'entry progress spec id'
  Assert-Equal $Cross.entry_contract.minimum_level 41 'entry minimum level'
  Assert-Equal $Cross.entry_contract.trusted_handoff_producer 'DF_E_YANLUO_HALL' 'entry trusted handoff producer'
  Assert-Equal $Cross.entry_contract.direct_protected_key_consumer 'prohibited' 'entry protected-key consumer prohibition'
  Assert-Equal $Cross.entry_contract.writer_contract 'TT_SPEC_TIANTING_PROGRESSION_AND_INSTANCE_AUTHORITY' 'entry writer authority-contract spec'
  Assert-Null $Cross.entry_contract.runtime_key 'entry contract runtime key'

  $ChapterRolesById = @{}
  foreach ($Role in @($Contract.chapter_roles)) {
    $ChapterRolesById[[string]$Role.spec_id] = $Role
    Assert-Condition ([string]$Role.spec_id -match '^TT_SPEC_') "chapter role spec id: $($Role.spec_id)"
    Assert-Null $Role.runtime_key "chapter role runtime key: $($Role.spec_id)"
  }
  Assert-Condition ($ChapterRolesById.ContainsKey('TT_SPEC_SEVEN_STAR_SOLO')) 'seven-star solo role exists'
  Assert-Equal $ChapterRolesById['TT_SPEC_SEVEN_STAR_SOLO'].decision_status 'fixed-user-requirement' 'seven-star solo role status'
  Assert-Equal $ChapterRolesById['TT_SPEC_SEVEN_STAR_SOLO'].selected_option 'seven_star_series' 'seven-star solo selection'
  Assert-Condition ($ChapterRolesById.ContainsKey('TT_SPEC_TWENTY_EIGHT_MANSIONS_RAID')) 'twenty-eight-mansions team role exists'
  Assert-Equal $ChapterRolesById['TT_SPEC_TWENTY_EIGHT_MANSIONS_RAID'].decision_status 'fixed-user-requirement' 'twenty-eight-mansions team role status'
  Assert-Equal $ChapterRolesById['TT_SPEC_TWENTY_EIGHT_MANSIONS_RAID'].chapter_completion_relation 'post_mainline_optional_repeatable_not_regular_completion' 'team raid completion relation'
  Assert-Condition ($ChapterRolesById.ContainsKey('TT_SPEC_MAINLINE_NORMAL_CLOSURE')) 'mainline normal closure role exists'
  Assert-Equal $ChapterRolesById['TT_SPEC_MAINLINE_NORMAL_CLOSURE'].decision_status 'offline_design' 'mainline normal closure status'

  Assert-Equal $Contract.tracks.chapter_mainline.ordered_nodes.Count 5 'mainline ordered-node count'
  Assert-Equal $Contract.tracks.solo_content.selected_option 'TT_SPEC_SEVEN_STAR_SOLO' 'track seven-star solo selection'
  Assert-Equal $Contract.tracks.team_content.direction 'TT_SPEC_TWENTY_EIGHT_MANSIONS_RAID' 'track twenty-eight-mansions team selection'
  Assert-Equal $Contract.tracks.team_content.chapter_completion_relation 'post_mainline_optional_repeatable_not_regular_completion' 'track team completion relation'
  Assert-Equal $Contract.tracks.tower_first_cycle.tianting_content_reuse.artifact 'tianting-content-expansion-contract.json' 'tower content-reuse artifact'
  Assert-Equal $Contract.tracks.tower_first_cycle.tianting_content_reuse.mini_boss_cadence 'deferred_3_or_5_floors' 'tower mini-Boss cadence remains deferred'
  Assert-Equal $Contract.tracks.tower_first_cycle.tianting_content_reuse.major_boss_cadence 'user_directed_every_10_floors; roster_deferred' 'tower major-Boss interface'
  Assert-Null $Contract.tracks.tower_first_cycle.tianting_content_reuse.runtime_key 'tower content-reuse runtime key'

  Assert-Equal $Expansion.version 1 'content expansion version'
  Assert-Equal $Expansion.package_status 'offline-design-spec' 'content expansion status'
  Assert-Equal $Expansion.production_gate 'closed' 'content expansion production gate'
  Assert-Equal $Expansion.hard_boundaries.level_band.min_level 41 'content expansion minimum level'
  Assert-Equal $Expansion.hard_boundaries.level_band.max_level 60 'content expansion maximum level'
  Assert-Equal $Expansion.hard_boundaries.party_cap.max_players 4 'content expansion party cap'
  Assert-Equal $Expansion.hard_boundaries.party_cap.shared_state_rule 'future_authoritative_gameplay_only' 'content expansion authority rule'
  Assert-Equal $Expansion.hard_boundaries.cross_chapter.protected_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'content expansion protected Difu key'
  Assert-Equal $Expansion.hard_boundaries.cross_chapter.tianting_default_use 'prohibited' 'content expansion protected Difu key use'
  Assert-Null $Expansion.hard_boundaries.cross_chapter.runtime_key 'content expansion cross-chapter runtime key'
  Assert-Equal $Expansion.hard_boundaries.economy.external_design_dependency 'economy-v2' 'content expansion economy dependency'
  Assert-Equal $Expansion.hard_boundaries.economy.runtime_status 'accepted_design_reference_runtime_not_integrated' 'content expansion economy status'
  Assert-Condition ($Expansion.hard_boundaries.economy.forbidden_embedded_values -contains 'xp_amount') 'content expansion prohibits embedded XP'
  Assert-Condition ($Expansion.hard_boundaries.economy.forbidden_embedded_values -contains 'drop_probability') 'content expansion prohibits drop probability'
  Assert-Condition ($Expansion.hard_boundaries.economy.forbidden_embedded_values -contains 'material_drop_count') 'content expansion prohibits material-drop count'
  Assert-Equal $Expansion.hard_boundaries.tower_identity.rule 'linglong_theme_within_global_tongtian_tower' 'content expansion tower identity'
  Assert-Equal $Expansion.hard_boundaries.tower_identity.must_not_create 'a_second_long_term_tower_system' 'content expansion second-tower prohibition'
  Assert-Null $Expansion.hard_boundaries.tower_identity.runtime_key 'content expansion tower identity runtime key'

  $SevenStars = @($Expansion.seven_star_solo.stars)
  $ExpectedStarNames = @('天枢', '天璇', '天玑', '天权', '玉衡', '开阳', '瑶光')
  Assert-Equal $Expansion.seven_star_solo.spec_id 'TT_SPEC_SEVEN_STAR_SOLO_SERIES' 'seven-star content spec id'
  Assert-Equal $Expansion.seven_star_solo.decision_status 'fixed-user-requirement' 'seven-star content status'
  Assert-Null $Expansion.seven_star_solo.runtime_key 'seven-star content runtime key'
  Assert-Equal $SevenStars.Count 7 'seven-star count'
  Assert-Condition ((@($SevenStars | ForEach-Object { [string]$_.star_name }) -join '|') -eq ($ExpectedStarNames -join '|')) 'seven-star name order'
  Assert-Equal $Expansion.seven_star_solo.star_titles.same_star_fragment_units_required 10 'same-star title fragment count'
  Assert-Equal $Expansion.seven_star_solo.star_titles.decision_status 'fixed-user-requirement' 'same-star title count status'
  Assert-Null $Expansion.seven_star_solo.star_titles.runtime_item_key 'same-star title runtime item key'
  Assert-Equal $Expansion.seven_star_solo.star_titles.effect_scope 'deferred_to_future_combat_and_title_contract' 'same-star title effect scope remains deferred'
  Assert-Equal $Expansion.seven_star_solo.fragment_rule.consumption_semantics 'deferred_to_future_economy_contract; the title recipe and graduation-artifact recipe must not silently spend the same fragment twice.' 'seven-star fragment consumption semantics'
  Assert-Null $Expansion.seven_star_solo.fragment_rule.runtime_item_key 'seven-star fragment runtime item key'
  Assert-Null $Expansion.seven_star_solo.fragment_rule.drop_count 'seven-star fragment drop count remains deferred'
  Assert-Null $Expansion.seven_star_solo.fragment_rule.drop_probability 'seven-star fragment probability remains deferred'
  Assert-Equal $Expansion.seven_star_solo.aggregate_title.spec_id 'TT_SPEC_SEVEN_STAR_AGGREGATE_TITLE' 'seven-star aggregate title spec id'
  Assert-Null $Expansion.seven_star_solo.aggregate_title.display_name 'seven-star aggregate title name remains deferred'
  Assert-Equal $Expansion.seven_star_solo.aggregate_title.unlock_rule '七个星君称号均已获得时自动解锁。' 'seven-star aggregate title auto unlock'
  Assert-Equal $Expansion.seven_star_solo.graduation_artifact.spec_id 'TT_SPEC_SEVEN_STAR_GRADUATION_ARTIFACT' 'graduation artifact spec id'
  Assert-Null $Expansion.seven_star_solo.graduation_artifact.display_name 'graduation artifact name remains deferred'
  $SevenStarSpecIds = @{}
  $SevenStarFragmentSpecIds = @{}
  $SevenStarTitleSpecIds = @{}
  $SevenStarTitles = @{}
  $SevenStarTitleTags = @{}
  $SevenStarEffectDirections = @{}
  foreach ($Star in $SevenStars) {
    Assert-Condition ([string]$Star.spec_id -match '^TT_SPEC_') "seven-star spec id: $($Star.star_name)"
    Assert-Condition (-not $SevenStarSpecIds.ContainsKey([string]$Star.spec_id)) "seven-star spec id is unique: $($Star.star_name)"
    $SevenStarSpecIds[[string]$Star.spec_id] = $true
    Assert-Null $Star.runtime_key "seven-star runtime key: $($Star.star_name)"
    Assert-Condition ([string]$Star.fragment_spec_id -match '^TT_SPEC_') "seven-star fragment spec id: $($Star.star_name)"
    Assert-Condition (-not $SevenStarFragmentSpecIds.ContainsKey([string]$Star.fragment_spec_id)) "seven-star fragment spec id is unique: $($Star.star_name)"
    $SevenStarFragmentSpecIds[[string]$Star.fragment_spec_id] = $true
    Assert-Null $Star.fragment_runtime_key "seven-star fragment runtime key: $($Star.star_name)"
    Assert-Equal $Star.fragment_name "$($Star.star_name)残片" "seven-star fragment name: $($Star.star_name)"
    Assert-Condition ([string]$Star.title_spec_id -match '^TT_SPEC_') "seven-star title spec id: $($Star.star_name)"
    Assert-Condition (-not $SevenStarTitleSpecIds.ContainsKey([string]$Star.title_spec_id)) "seven-star title spec id is unique: $($Star.star_name)"
    $SevenStarTitleSpecIds[[string]$Star.title_spec_id] = $true
    Assert-Null $Star.title_runtime_key "seven-star title runtime key: $($Star.star_name)"
    Assert-Condition ([string]$Star.title_name -match '星君$') "seven-star title name: $($Star.star_name)"
    Assert-Condition (-not $SevenStarTitles.ContainsKey([string]$Star.title_name)) "seven-star title is unique: $($Star.title_name)"
    $SevenStarTitles[[string]$Star.title_name] = $true
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Star.title_tag)) "seven-star title tag: $($Star.star_name)"
    Assert-Condition (-not $SevenStarTitleTags.ContainsKey([string]$Star.title_tag)) "seven-star title tag is unique: $($Star.star_name)"
    $SevenStarTitleTags[[string]$Star.title_tag] = $true
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Star.effect_direction)) "seven-star effect direction: $($Star.star_name)"
    Assert-Condition (-not $SevenStarEffectDirections.ContainsKey([string]$Star.effect_direction)) "seven-star effect direction is unique: $($Star.star_name)"
    $SevenStarEffectDirections[[string]$Star.effect_direction] = $true
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Star.mechanic_direction)) "seven-star mechanic direction: $($Star.star_name)"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Star.display_direction)) "seven-star display direction: $($Star.star_name)"
  }
  Assert-Condition ((@($Expansion.seven_star_solo.aggregate_title.required_title_spec_ids) -join '|') -eq ((@($SevenStars | ForEach-Object { [string]$_.title_spec_id }) -join '|'))) 'seven-star aggregate title references every single-title spec id'

  $Raid = $Expansion.twenty_eight_mansions_raid
  Assert-Equal $Raid.spec_id 'TT_SPEC_TWENTY_EIGHT_MANSIONS_RAID' 'twenty-eight-mansions content spec id'
  Assert-Equal $Raid.decision_status 'fixed-user-requirement' 'twenty-eight-mansions content status'
  Assert-Null $Raid.runtime_key 'twenty-eight-mansions content runtime key'
  Assert-Equal $Raid.chapter_relation '天庭常规主线完成后开放的最高端团队副本；它不是常规章节完成键的写入者。' 'twenty-eight-mansions chapter relation'
  Assert-Equal $Raid.canonical_name_policy 'full_name 是二十八星官的唯一规范身份；出现史料异文时只能作为后续 alias 记录，不能创建第二名星官。' 'mansion canonical-name policy'
  Assert-Equal $Raid.rotation.spec_id 'TT_SPEC_MANSION_ROTATION' 'mansion rotation spec id'
  Assert-Equal $Raid.rotation.schedule.Count 4 'mansion rotation quadrant count'
  Assert-Equal $Raid.rotation.rule '十二时辰按四个连续槽位循环，日内完整循环三次。' 'mansion rotation rule'
  Assert-Equal $Raid.rotation.snapshot_rule '首次成功创建团队会话时由未来权威时间提供方按 Asia/Shanghai 自然时辰生成 rotation_snapshot；副本生命期内锁定其方位与难度，禁止以客户端本地时钟或重试中途换宿。' 'mansion rotation snapshot rule'
  Assert-Equal $Raid.rotation.snapshot_contract.spec_id 'TT_SPEC_MANSION_ROTATION_SNAPSHOT' 'mansion rotation snapshot spec id'
  Assert-ExactArray $Raid.rotation.snapshot_contract.required_field_names @('rotation_snapshot_id', 'schedule_version', 'authoritative_time_slot', 'quadrant', 'difficulty', 'instance_scope', 'authority_time_basis_id', 'captured_authoritative_instant', 'schema_version') 'mansion rotation snapshot fields'
  Assert-Equal $Raid.rotation.snapshot_contract.client_clock_rule 'prohibited' 'mansion rotation client-clock prohibition'
  Assert-Null $Raid.rotation.snapshot_contract.runtime_key 'mansion rotation snapshot runtime key'
  Assert-Equal $Raid.rotation.trusted_time_source.spec_id 'TT_SPEC_TIME_BASIS_ASIA_SHANGHAI_SHICHEN' 'mansion trusted time source spec id'
  Assert-Equal $Raid.rotation.trusted_time_source.time_zone 'Asia/Shanghai' 'mansion trusted time source time zone'
  Assert-Equal $Raid.rotation.trusted_time_source.calendar_rule 'server-natural-twelve-earthly-branches' 'mansion trusted time source calendar rule'
  Assert-Null $Raid.rotation.trusted_time_source.implementation 'mansion trusted time source implementation remains deferred'
  Assert-Null $Raid.rotation.trusted_time_source.runtime_key 'mansion trusted time source runtime key'
  Assert-Null $Raid.rotation.runtime_key 'mansion rotation runtime key'
  $ExpectedRotationByQuadrant = @{
    '东方青龙' = @('子', '辰', '申')
    '南方朱雀' = @('丑', '巳', '酉')
    '西方白虎' = @('寅', '午', '戌')
    '北方玄武' = @('卯', '未', '亥')
  }
  $SeenRotationSlots = @{}
  foreach ($Entry in @($Raid.rotation.schedule)) {
    Assert-Condition ($ExpectedRotationByQuadrant.ContainsKey([string]$Entry.quadrant)) "rotation quadrant is valid: $($Entry.quadrant)"
    $ExpectedSlots = @($ExpectedRotationByQuadrant[[string]$Entry.quadrant])
    Assert-Condition ((@($Entry.time_slots) -join '|') -eq ($ExpectedSlots -join '|')) "rotation slots: $($Entry.quadrant)"
    foreach ($Slot in @($Entry.time_slots)) {
      Assert-Condition (-not $SeenRotationSlots.ContainsKey([string]$Slot)) "rotation slot is unique: $Slot"
      $SeenRotationSlots[[string]$Slot] = $true
    }
  }
  Assert-Equal $SeenRotationSlots.Count 12 'rotation covers all twelve time slots'

  Assert-Equal $Raid.normal_mode.spec_id 'TT_SPEC_MANSION_NORMAL_MODE' 'normal mansion mode spec id'
  Assert-Condition ([string]$Raid.normal_mode.raid_shape -match '前阵双宿、中阵双宿、后阵双宿、守位单宿') 'normal mansion uses 2+2+2+1 structure'
  Assert-Null $Raid.normal_mode.runtime_key 'normal mansion mode runtime key'
  Assert-Equal $Raid.nightmare_mode.spec_id 'TT_SPEC_MANSION_NIGHTMARE_MODE' 'nightmare mansion mode spec id'
  Assert-Condition ($Raid.nightmare_mode.all_seven_officers_present -eq $true) 'nightmare retains all seven officers'
  Assert-Equal $Raid.nightmare_mode.reciprocal_bond_contract.officer_to_sacred_beast_link_count 7 'nightmare officer-to-beast link count'
  Assert-Equal $Raid.nightmare_mode.reciprocal_bond_contract.sacred_beast_to_officer_link_count 7 'nightmare beast-to-officer link count'
  Assert-Equal $Raid.nightmare_mode.reciprocal_bond_contract.officer_to_sacred_beast_effect '宿曜贡辉' 'nightmare officer-to-beast effect'
  Assert-Equal $Raid.nightmare_mode.reciprocal_bond_contract.sacred_beast_to_officer_effect '圣兽庇护' 'nightmare beast-to-officer effect'
  Assert-Null $Raid.nightmare_mode.reciprocal_bond_contract.numeric_values 'nightmare reciprocal bond values remain deferred'
  Assert-Null $Raid.nightmare_mode.reciprocal_bond_contract.buff_runtime_key 'nightmare reciprocal bond runtime key'
  Assert-Equal $Raid.nightmare_mode.qualification_match_contract.spec_id 'TT_SPEC_NIGHTMARE_QUADRANT_MATCH' 'nightmare quadrant-match spec id'
  Assert-Equal $Raid.nightmare_mode.qualification_match_contract.rule 'normal_clear.rotation_snapshot.quadrant == nightmare_access_credential.quadrant == nightmare.rotation_snapshot.quadrant' 'nightmare quadrant-match rule'
  Assert-ExactArray $Raid.nightmare_mode.qualification_match_contract.required_field_names @('credential_subject_actor_id', 'normal_clear_rotation_snapshot_id', 'normal_clear_quadrant', 'nightmare_access_credential', 'nightmare_rotation_snapshot_id', 'owner_scope', 'authority_proof_ref', 'schema_version') 'nightmare quadrant-match fields'
  Assert-ExactArray $Raid.nightmare_mode.qualification_match_contract.required_field_names $Authority.nightmare_qualification_contract.required_fields 'nightmare qualification fields cross-reference authority contract'
  Assert-Equal $Raid.nightmare_mode.qualification_match_contract.owner_scope 'character' 'nightmare quadrant-match owner scope'
  Assert-Equal $Raid.nightmare_mode.qualification_match_contract.credential_resolution_rule 'authority resolves every participant credential; caller-provided owner, quadrant or proof fields are forbidden.' 'nightmare authoritative credential resolution rule'
  Assert-Equal $Raid.nightmare_mode.qualification_match_contract.replay_and_receipt_semantics 'admission and session replay are defined by the offline authority contract; credential issuance, consumption and economic receipt remain deferred.' 'nightmare authority-contract replay boundary'
  Assert-Null $Raid.nightmare_mode.qualification_match_contract.runtime_key 'nightmare quadrant-match runtime key'
  Assert-Null $Raid.nightmare_mode.runtime_key 'nightmare mansion mode runtime key'
  Assert-Equal $Raid.normal_clear_key.spec_id 'TT_SPEC_MANSION_NIGHTMARE_KEY' 'nightmare key candidate spec id'
  Assert-Equal $Raid.normal_clear_key.decision_status 'fixed-user-requirement' 'nightmare key candidate status'
  Assert-Null $Raid.normal_clear_key.runtime_item_key 'nightmare key candidate runtime item key'

  $ExpectedMansionsByQuadrant = @{
    '东方青龙' = @('角木蛟', '亢金龙', '氐土貉', '房日兔', '心月狐', '尾火虎', '箕水豹')
    '南方朱雀' = @('井木犴', '鬼金羊', '柳土獐', '星日马', '张月鹿', '翼火蛇', '轸水蚓')
    '西方白虎' = @('奎木狼', '娄金狗', '胃土雉', '昴日鸡', '毕月乌', '觜火猴', '参水猿')
    '北方玄武' = @('斗木獬', '牛金牛', '女土蝠', '虚日鼠', '危月燕', '室火猪', '壁水貐')
  }
  Assert-Equal $Raid.quadrants.Count 4 'mansion quadrant count'
  $SeenOfficerNames = @{}
  $SeenOfficerSpecIds = @{}
  $SeenSacredBeastSpecIds = @{}
  $QuadrantSpecByName = @{}
  foreach ($Quadrant in @($Raid.quadrants)) {
    Assert-Condition ($ExpectedMansionsByQuadrant.ContainsKey([string]$Quadrant.quadrant)) "mansion roster quadrant is valid: $($Quadrant.quadrant)"
    Assert-Condition ([string]$Quadrant.spec_id -match '^TT_SPEC_') "mansion quadrant spec id: $($Quadrant.quadrant)"
    $QuadrantSpecByName[[string]$Quadrant.quadrant] = [string]$Quadrant.spec_id
    Assert-Condition ([string]$Quadrant.sacred_beast_spec_id -match '^TT_SPEC_') "sacred-beast spec id: $($Quadrant.sacred_beast)"
    Assert-Condition (-not $SeenSacredBeastSpecIds.ContainsKey([string]$Quadrant.sacred_beast_spec_id)) "sacred-beast spec id is unique: $($Quadrant.sacred_beast)"
    $SeenSacredBeastSpecIds[[string]$Quadrant.sacred_beast_spec_id] = $true
    Assert-Null $Quadrant.sacred_beast_runtime_key "sacred-beast runtime key: $($Quadrant.sacred_beast)"
    Assert-Equal $Quadrant.officers.Count 7 "mansion officer count: $($Quadrant.quadrant)"
    Assert-Condition ((@($Quadrant.officers | ForEach-Object { [string]$_.full_name }) -join '|') -eq (@($ExpectedMansionsByQuadrant[[string]$Quadrant.quadrant]) -join '|')) "mansion officer name order: $($Quadrant.quadrant)"
    foreach ($Officer in @($Quadrant.officers)) {
      Assert-Condition ([string]$Officer.spec_id -match '^TT_SPEC_') "mansion officer spec id: $($Officer.full_name)"
      Assert-Condition (-not $SeenOfficerSpecIds.ContainsKey([string]$Officer.spec_id)) "mansion officer spec id is unique: $($Officer.full_name)"
      $SeenOfficerSpecIds[[string]$Officer.spec_id] = $true
      Assert-Condition (-not $SeenOfficerNames.ContainsKey([string]$Officer.full_name)) "mansion officer name is unique: $($Officer.full_name)"
      $SeenOfficerNames[[string]$Officer.full_name] = $true
      Assert-Array $Officer.aliases "mansion officer aliases: $($Officer.full_name)"
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Officer.unique_skill)) "mansion officer unique skill: $($Officer.full_name)"
      Assert-Null $Officer.runtime_key "mansion officer runtime key: $($Officer.full_name)"
    }
  }
  Assert-Equal $SeenOfficerNames.Count 28 'total mansion officer count'
  Assert-Equal $SeenSacredBeastSpecIds.Count 4 'total sacred-beast spec count'
  foreach ($Entry in @($Raid.rotation.schedule)) {
    Assert-Equal $Entry.raid_spec_id $QuadrantSpecByName[[string]$Entry.quadrant] "rotation raid-spec cross reference: $($Entry.quadrant)"
  }

  Assert-Equal $Raid.four_sacred_titles.spec_id 'TT_SPEC_FOUR_SACRED_TITLE_SERIES' 'four-sacred title series spec id'
  Assert-Equal $Raid.four_sacred_titles.directional_titles.Count 4 'four-sacred directional title count'
  $FourSacredTitleSpecIds = @{}
  foreach ($Title in @($Raid.four_sacred_titles.directional_titles)) {
    Assert-Condition ([string]$Title.spec_id -match '^TT_SPEC_') "four-sacred directional title spec id: $($Title.title_name)"
    Assert-Condition (-not $FourSacredTitleSpecIds.ContainsKey([string]$Title.spec_id)) "four-sacred directional title spec id is unique: $($Title.title_name)"
    $FourSacredTitleSpecIds[[string]$Title.spec_id] = $true
    Assert-Null $Title.runtime_key "four-sacred directional title runtime key: $($Title.title_name)"
  }
  Assert-Equal $Raid.four_sacred_titles.aggregate_title.spec_id 'TT_SPEC_FOUR_SACRED_AGGREGATE_TITLE' 'four-sacred aggregate title spec id'
  Assert-Equal $Raid.four_sacred_titles.aggregate_title.title_name '四象镇天' 'four-sacred aggregate title name'
  Assert-Condition ((@($Raid.four_sacred_titles.aggregate_title.required_title_spec_ids) -join '|') -eq ((@($Raid.four_sacred_titles.directional_titles | ForEach-Object { [string]$_.spec_id }) -join '|'))) 'four-sacred aggregate title references every directional-title spec id'
  Assert-Null $Raid.four_sacred_titles.aggregate_title.runtime_key 'four-sacred aggregate title runtime key'

  $AuthorityTopProperties = @(
    'version',
    'package_status',
    'production_gate',
    'implementation_handoff',
    'identity',
    'source_contracts',
    'hard_boundaries',
    'semantic_identity_policy',
    'receipt_and_idempotency_contract',
    'logical_progression',
    'entry_contract',
    'mainline_final_session',
    'seven_star_solo_session',
    'mansion_raid_session',
    'rotation_snapshot_contract',
    'nightmare_qualification_contract',
    'recovery_contract',
    'negative_cases',
    'deferred',
    'forbidden_field_names',
    'acceptance_invariants',
    'validation_contract'
  )
  Assert-RequiredProperties $Authority $AuthorityTopProperties 'authority contract'
  Assert-Equal $Authority.version 1 'authority contract version'
  Assert-Equal $Authority.package_status 'offline-design-spec' 'authority contract package status'
  Assert-Equal $Authority.production_gate 'closed' 'authority contract production gate'
  Assert-Condition ($Authority.implementation_handoff -eq $false) 'authority contract implementation handoff remains false'

  $AuthorityIdentity = $Authority.identity
  Assert-Equal $AuthorityIdentity.spec_id 'TT_SPEC_TIANTING_PROGRESSION_AND_INSTANCE_AUTHORITY' 'authority contract identity spec id'
  Assert-Null $AuthorityIdentity.runtime_key 'authority contract identity runtime key'
  Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$AuthorityIdentity.display_name)) 'authority contract identity display name'
  Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$AuthorityIdentity.scope)) 'authority contract identity scope'

  $AuthoritySources = $Authority.source_contracts
  Assert-Equal $AuthoritySources.tianting_mainline '../tianting-mainline-tower-contract.json' 'authority source mainline contract'
  Assert-Equal $AuthoritySources.tianting_content '../tianting-content-expansion-contract.json' 'authority source content contract'
  Assert-Equal $AuthoritySources.difu_cross_chapter_interface '../../地府篇前置接口包/cross-chapter-interface.json' 'authority source Difu cross-chapter contract'
  Assert-Equal $AuthoritySources.difu_team_recovery_semantics '../../地府篇前置接口包/cross-chapter-interface.json' 'authority source Difu recovery contract'
  Assert-Condition ([string]$AuthoritySources.rule -match '不读取、写入或新增既有地府进度键的消费者') 'authority source rule preserves protected Difu-key boundary'

  $AuthorityBoundaries = $Authority.hard_boundaries
  Assert-Equal $AuthorityBoundaries.protected_difu_progress_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'authority protected Difu progression key'
  Assert-Equal $AuthorityBoundaries.protected_key_rule 'must_not_read_write_register_as_consumer_or_substitute_as_tianting_default_unlock' 'authority protected Difu progression rule'
  Assert-Equal $AuthorityBoundaries.permitted_difu_handoff_source 'DF_E_YANLUO_HALL authoritative success proof only' 'authority permitted Difu handoff source'
  Assert-Equal $AuthorityBoundaries.level_band.minimum 41 'authority level band minimum'
  Assert-Equal $AuthorityBoundaries.level_band.maximum 60 'authority level band maximum'
  Assert-Equal $AuthorityBoundaries.level_band.entry_level_check 'authority_confirmed_per_actor' 'authority level check rule'
  Assert-Null $AuthorityBoundaries.level_band.runtime_key 'authority level-band runtime key'
  Assert-Equal $AuthorityBoundaries.party_cap.minimum_players 1 'authority party minimum'
  Assert-Equal $AuthorityBoundaries.party_cap.maximum_players 4 'authority party maximum'
  Assert-Equal $AuthorityBoundaries.party_cap.member_check 'every_member_independently' 'authority party per-member rule'
  Assert-Null $AuthorityBoundaries.party_cap.runtime_key 'authority party-cap runtime key'
  Assert-Equal $AuthorityBoundaries.economy_runtime_status 'accepted-design-reference-runtime-not-integrated' 'authority economy runtime status'
  Assert-Condition ([string]$AuthorityBoundaries.economy_rule -match '不授予、扣除、计算或承诺') 'authority economy rule forbids issuance'
  Assert-Condition ([string]$AuthorityBoundaries.runtime_asset_rule -match '均为 null') 'authority runtime asset rule keeps all runtime keys null'

  $SemanticIdentity = $Authority.semantic_identity_policy
  Assert-ExactArray $SemanticIdentity.new_runtime_keys @() 'authority new runtime keys'
  Assert-ExactArray $SemanticIdentity.new_persistent_keys @() 'authority new persistent keys'
  Assert-ExactArray $SemanticIdentity.new_resource_keys @() 'authority new resource keys'
  Assert-Condition ($SemanticIdentity.all_spec_ids_are_offline_only -eq $true) 'authority spec identities remain offline only'
  Assert-Condition ($SemanticIdentity.progression_records_are_logical_only -eq $true) 'authority progression records remain logical only'
  Assert-Condition ($SemanticIdentity.client_is_not_authority -eq $true) 'authority client is not authority'
  Assert-Null $SemanticIdentity.runtime_key 'authority semantic identity runtime key'

  $AuthorityReceipt = $Authority.receipt_and_idempotency_contract
  $CompletionReceiptFields = @('actor_id', 'actor_lifecycle_id', 'event_id', 'producer_spec_id', 'session_instance_id', 'session_epoch', 'completed_tick', 'authority_proof_ref', 'schema_version')
  Assert-Equal $AuthorityReceipt.spec_id 'TT_SPEC_TIANTING_COMPLETION_RECEIPT_IDEMPOTENCY' 'authority receipt spec id'
  Assert-Equal $AuthorityReceipt.decision_status 'offline_design' 'authority receipt status'
  Assert-Equal $AuthorityReceipt.receipt_kind 'authoritative_completion_receipt' 'authority receipt kind'
  Assert-Equal $AuthorityReceipt.record_scope 'character' 'authority receipt record scope'
  Assert-ExactArray $AuthorityReceipt.required_receipt_fields $CompletionReceiptFields 'authority completion receipt fields'
  Assert-ExactArray $AuthorityReceipt.session_identity_fields @('session_instance_id', 'session_epoch') 'authority receipt session identity fields'
  Assert-ExactArray $AuthorityReceipt.idempotency_key_fields @('actor_id', 'event_id') 'authority receipt idempotency fields'
  Assert-Condition ([string]$AuthorityReceipt.event_id_rule -match '客户端自填') 'authority receipt rejects client event ids'
  Assert-Condition ([string]$AuthorityReceipt.replay_result -match '不得重复写逻辑进度') 'authority receipt replay has no duplicate write'
  Assert-Condition ([string]$AuthorityReceipt.normal_completion_persistence_rule -match '不得回滚') 'authority completion survives cleanup replay'
  Assert-Null $AuthorityReceipt.runtime_key 'authority receipt runtime key'

  $LogicalProgression = $Authority.logical_progression
  $ExpectedProgressionIds = @('TT_SPEC_PROGRESS_CHAPTER_ENTERED', 'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN', 'TT_SPEC_PROGRESS_MAINLINE_CLEARED')
  $ExpectedProgressionProducers = @{
    'TT_SPEC_PROGRESS_CHAPTER_ENTERED' = 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS'
    'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN' = 'TT_SPEC_MAINLINE_NODE_04_CELESTIAL_OBSERVATORY'
    'TT_SPEC_PROGRESS_MAINLINE_CLEARED' = 'TT_SPEC_MAINLINE_NODE_05_LINGXIAO_OUTER_COURT'
  }
  $ExpectedProgressionProducerSessions = @{
    'TT_SPEC_PROGRESS_CHAPTER_ENTERED' = 'TT_SPEC_SESSION_SOUTH_GATE_TRANSITION'
    'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN' = 'TT_SPEC_SESSION_CELESTIAL_OBSERVATORY_MAINLINE'
    'TT_SPEC_PROGRESS_MAINLINE_CLEARED' = 'TT_SPEC_SESSION_LINGXIAO_MAINLINE'
  }
  $ExpectedProgressionWriteEvents = @{
    'TT_SPEC_PROGRESS_CHAPTER_ENTERED' = 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS'
    'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN' = 'TT_SPEC_EVENT_CELESTIAL_OBSERVATORY_OPEN_SUCCESS'
    'TT_SPEC_PROGRESS_MAINLINE_CLEARED' = 'TT_SPEC_EVENT_LINGXIAO_OUTER_COURT_SUCCESS'
  }
  $ExpectedProgressionPrerequisites = @{
    'TT_SPEC_PROGRESS_CHAPTER_ENTERED' = @()
    'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN' = @('TT_SPEC_PROGRESS_CHAPTER_ENTERED')
    'TT_SPEC_PROGRESS_MAINLINE_CLEARED' = @('TT_SPEC_PROGRESS_CHAPTER_ENTERED', 'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN')
  }
  Assert-Equal $LogicalProgression.spec_id 'TT_SPEC_TIANTING_LOGICAL_PROGRESSION' 'authority logical progression spec id'
  Assert-Equal $LogicalProgression.record_scope 'character' 'authority logical progression record scope'
  Assert-Condition ([string]$LogicalProgression.ordering_rule -match 'TT_SPEC_PROGRESS_CHAPTER_ENTERED → TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN → TT_SPEC_PROGRESS_MAINLINE_CLEARED') 'authority logical progression ordering rule'
  Assert-ExactArray (@($LogicalProgression.records | ForEach-Object { [string]$_.spec_id })) $ExpectedProgressionIds 'authority logical progression record order'
  $ProgressionRecordsById = @{}
  foreach ($Record in @($LogicalProgression.records)) {
    Assert-Condition (-not $ProgressionRecordsById.ContainsKey([string]$Record.spec_id)) "authority logical progression record is unique: $($Record.spec_id)"
    $ProgressionRecordsById[[string]$Record.spec_id] = $Record
    Assert-Equal $Record.record_scope 'character' "authority logical progression record scope: $($Record.spec_id)"
    Assert-Null $Record.runtime_progression_key "authority logical progression runtime progression key: $($Record.spec_id)"
    Assert-Null $Record.runtime_key "authority logical progression runtime key: $($Record.spec_id)"
    Assert-ExactArray $Record.required_receipt_fields $CompletionReceiptFields "authority logical progression receipt fields: $($Record.spec_id)"
    Assert-ExactArray $Record.idempotency_key_fields @('actor_id', 'event_id') "authority logical progression idempotency fields: $($Record.spec_id)"
  }
  foreach ($ProgressionId in $ExpectedProgressionIds) {
    Assert-Condition ($ProgressionRecordsById.ContainsKey($ProgressionId)) "authority expected logical progression record exists: $ProgressionId"
    $Record = $ProgressionRecordsById[$ProgressionId]
    Assert-Equal $Record.unique_producer_spec_id $ExpectedProgressionProducers[$ProgressionId] "authority logical progression unique producer: $ProgressionId"
    Assert-Equal $Record.producer_session_spec_id $ExpectedProgressionProducerSessions[$ProgressionId] "authority logical progression producer session: $ProgressionId"
    Assert-Equal $Record.write_event $ExpectedProgressionWriteEvents[$ProgressionId] "authority logical progression write event: $ProgressionId"
    Assert-ExactArray $Record.prerequisite_progress_spec_ids $ExpectedProgressionPrerequisites[$ProgressionId] "authority logical progression prerequisites: $ProgressionId"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Record.replay_result)) "authority logical progression replay result: $ProgressionId"
    Assert-Array $Record.non_writer_sources "authority logical progression non-writer sources: $ProgressionId"
  }
  Assert-Condition ($ProgressionRecordsById['TT_SPEC_PROGRESS_CHAPTER_ENTERED'].non_writer_sources -contains 'DF_PROGRESS_YANLUO_HALL_CLEARED') 'chapter entry does not consume protected Difu progression key'
  Assert-Condition ($ProgressionRecordsById['TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN'].non_writer_sources -contains 'TT_SPEC_SEVEN_STAR_SOLO_SERIES') 'observatory opening is not written by seven-star content'
  Assert-Condition ($ProgressionRecordsById['TT_SPEC_PROGRESS_MAINLINE_CLEARED'].non_writer_sources -contains 'TT_SPEC_TWENTY_EIGHT_MANSIONS_RAID') 'mainline completion is not written by mansion raid'

  $EntryAuthority = $Authority.entry_contract
  Assert-Equal $EntryAuthority.spec_id 'TT_SPEC_TIANTING_CHAPTER_ENTRY_AUTHORITY' 'authority chapter entry spec id'
  Assert-Null $EntryAuthority.runtime_key 'authority chapter entry runtime key'
  Assert-Equal $EntryAuthority.minimum_level 41 'authority chapter entry minimum level'
  Assert-Equal $EntryAuthority.level_validation_rule 'only_authority_confirmed_current_actor_level_at_least_41' 'authority chapter entry level validation'
  Assert-Null $EntryAuthority.required_progress_spec_id 'authority chapter entry required progress remains absent'
  Assert-Equal $EntryAuthority.writer_progress_spec_id 'TT_SPEC_PROGRESS_CHAPTER_ENTERED' 'authority chapter entry writer progress spec id'
  Assert-Equal $EntryAuthority.accepted_result 'authority_writes_only_TT_SPEC_PROGRESS_CHAPTER_ENTERED_using_TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS' 'authority chapter entry accepted result'
  Assert-ExactArray $EntryAuthority.rejections @('authority_level_below_41', 'missing_or_untrusted_yanluo_handoff_proof', 'proof_actor_id_differs_from_request_actor_id', 'proof_source_is_not_DF_E_YANLUO_HALL_authoritative_success', 'client_attempts_to_supply_progression_or_proof_result', 'stale_or_conflicting_event_replay') 'authority chapter entry rejection cases'
  $HandoffProof = $EntryAuthority.yanluo_handoff_proof
  $DifuHandoffReceiptFields = @('actor_id', 'actor_lifecycle_id', 'event_id', 'producer_encounter_key', 'session_instance_id', 'session_epoch', 'completed_tick', 'authority_proof_ref')
  $TiantingHandoffEnvelopeFields = @('actor_id', 'source_event_id', 'source_producer_encounter_key', 'source_session_instance_id', 'source_session_epoch', 'source_completed_tick', 'source_authority_proof_ref', 'handoff_authority_proof_ref', 'schema_version')
  Assert-Equal $HandoffProof.spec_id 'TT_SPEC_CHAPTER_ENTRY_HANDOFF_PROOF' 'authority chapter handoff proof spec id'
  Assert-Null $HandoffProof.runtime_key 'authority chapter handoff proof runtime key'
  Assert-Equal $HandoffProof.proof_kind 'authoritative_cross_chapter_completion_handoff_proof' 'authority chapter handoff proof kind'
  Assert-Equal $HandoffProof.source_encounter_key 'DF_E_YANLUO_HALL' 'authority chapter handoff source encounter'
  Assert-Condition ([string]$HandoffProof.source_success_rule -match 'authoritative success receipt') 'authority chapter handoff source success rule'
  Assert-Null $HandoffProof.source_progression_key 'authority chapter handoff source progression key remains absent'
  Assert-ExactArray $HandoffProof.required_source_receipt_fields $DifuHandoffReceiptFields 'authority chapter handoff source receipt fields'
  Assert-ExactArray $HandoffProof.handoff_envelope_required_fields $TiantingHandoffEnvelopeFields 'authority chapter handoff envelope fields'
  Assert-Condition ([string]$HandoffProof.handoff_envelope_rule -match 'schema_version belongs to the new TianTing handoff-proof envelope') 'authority chapter handoff envelope schema boundary'
  Assert-Equal $HandoffProof.same_actor_rule 'chapter_entry_request.actor_id == proof.actor_id' 'authority chapter handoff same actor rule'
  Assert-Condition ([string]$HandoffProof.proof_validation_rule -match 'client-provided booleans') 'authority chapter handoff rejects client proof'
  Assert-ExactArray $HandoffProof.forbidden_progression_key_operations @('read_DF_PROGRESS_YANLUO_HALL_CLEARED', 'write_DF_PROGRESS_YANLUO_HALL_CLEARED', 'register_as_DF_PROGRESS_YANLUO_HALL_CLEARED_consumer', 'use_DF_PROGRESS_YANLUO_HALL_CLEARED_as_unlock_substitute') 'authority chapter handoff protected-key operations'

  $MainlineSession = $Authority.mainline_final_session
  Assert-Equal $MainlineSession.spec_id 'TT_SPEC_SESSION_LINGXIAO_MAINLINE' 'authority mainline-final session spec id'
  Assert-Null $MainlineSession.runtime_key 'authority mainline-final session runtime key'
  Assert-Equal $MainlineSession.session_kind 'private_mainline_final' 'authority mainline-final session kind'
  Assert-Equal $MainlineSession.participant_capacity.minimum 1 'authority mainline-final participant minimum'
  Assert-Equal $MainlineSession.participant_capacity.maximum 4 'authority mainline-final participant maximum'
  Assert-Null $MainlineSession.participant_capacity.runtime_key 'authority mainline-final capacity runtime key'
  Assert-ExactArray $MainlineSession.identity_fields @('session_instance_id', 'session_epoch', 'revision', 'cleanup_token') 'authority mainline-final session identity fields'
  Assert-ExactArray $MainlineSession.member_snapshot_fields @('actor_id', 'actor_lifecycle_id', 'member_status', 'membership_snapshot_id') 'authority mainline-final member snapshot fields'
  Assert-ExactArray $MainlineSession.state_sequence @('active', 'cleanup_pending', 'closed') 'authority mainline-final state sequence'
  Assert-Equal $MainlineSession.participant_validation.required_progress_spec_id 'TT_SPEC_PROGRESS_CHAPTER_ENTERED' 'authority mainline-final prerequisite progress'
  Assert-Condition ([string]$MainlineSession.participant_validation.rule -match 'every_frozen_member_independently') 'authority mainline-final per-member validation'
  Assert-Condition ($MainlineSession.participant_validation.rejected_actor_classes -contains 'leader_without_individual_prerequisite') 'authority mainline-final rejects leader proxy'
  Assert-Condition ($MainlineSession.participant_validation.rejected_actor_classes -contains 'spectator') 'authority mainline-final rejects spectator'
  Assert-Equal $MainlineSession.completion_write_rule.writer_progress_spec_id 'TT_SPEC_PROGRESS_MAINLINE_CLEARED' 'authority mainline-final writer progression'
  Assert-Equal $MainlineSession.completion_write_rule.producer_spec_id 'TT_SPEC_MAINLINE_NODE_05_LINGXIAO_OUTER_COURT' 'authority mainline-final producer spec'
  Assert-Equal $MainlineSession.completion_write_rule.write_event 'TT_SPEC_EVENT_LINGXIAO_OUTER_COURT_SUCCESS' 'authority mainline-final completion event'
  Assert-Equal $MainlineSession.completion_write_rule.receipt_contract_spec_id 'TT_SPEC_TIANTING_COMPLETION_RECEIPT_IDEMPOTENCY' 'authority mainline-final receipt contract'
  Assert-Condition ([string]$MainlineSession.completion_write_rule.eligible_member_rule -match 'only a frozen member') 'authority mainline-final eligible member rule'
  Assert-Condition ([string]$MainlineSession.completion_write_rule.proxy_claim_rule -match 'receive no completion write') 'authority mainline-final proxy completion prohibition'
  Assert-Condition ([string]$MainlineSession.completion_write_rule.success_before_cleanup_rule -match 'cannot revoke') 'authority mainline-final success survives cleanup'
  Assert-Null $MainlineSession.completion_write_rule.runtime_key 'authority mainline-final completion runtime key'
  Assert-ExactArray $MainlineSession.cleanup_ack_identity_fields @('session_instance_id', 'session_epoch', 'revision', 'cleanup_token') 'authority mainline-final cleanup identity fields'
  Assert-Equal $MainlineSession.reentry_before_cleanup_ack 'denied' 'authority mainline-final reentry before cleanup acknowledgement'
  Assert-Null $MainlineSession.runtime_progression_key 'authority mainline-final runtime progression key'

  $SoloSession = $Authority.seven_star_solo_session
  Assert-Equal $SoloSession.spec_id 'TT_SPEC_SESSION_SEVEN_STAR' 'authority seven-star session spec id'
  Assert-Null $SoloSession.runtime_key 'authority seven-star session runtime key'
  Assert-Equal $SoloSession.session_kind 'single_player_repeatable_trial' 'authority seven-star session kind'
  Assert-Equal $SoloSession.owner_scope 'character' 'authority seven-star owner scope'
  Assert-ExactArray $SoloSession.identity_fields @('owner_actor_id', 'lifecycle_id', 'session_instance_id', 'session_epoch', 'revision', 'cleanup_token') 'authority seven-star session identity fields'
  Assert-ExactArray $SoloSession.state_sequence @('active', 'cleanup_pending', 'closed') 'authority seven-star state sequence'
  Assert-Equal $SoloSession.participant_validation.required_progress_spec_id 'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN' 'authority seven-star prerequisite progress'
  Assert-Condition ([string]$SoloSession.participant_validation.rule -match 'owner_actor_id independently requires TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN') 'authority seven-star owner validation'
  Assert-ExactArray $SoloSession.failure_triggers @('owner_death', 'timeout', 'owner_disconnect', 'owner_lifecycle_invalid') 'authority seven-star failure triggers'
  Assert-Condition ([string]$SoloSession.failure_rule -match 'cleanup_pending') 'authority seven-star failure cleanup state'
  Assert-Null $SoloSession.completion_write_rule.writer_progress_spec_id 'authority seven-star does not write mainline progression'
  Assert-Condition ([string]$SoloSession.completion_write_rule.rule -match '不写入三段天庭主线逻辑进度') 'authority seven-star completion excludes logical progression'
  Assert-Null $SoloSession.completion_write_rule.runtime_key 'authority seven-star completion runtime key'
  Assert-ExactArray $SoloSession.cleanup_ack_identity_fields @('session_instance_id', 'session_epoch', 'revision', 'cleanup_token') 'authority seven-star cleanup identity fields'
  Assert-Equal $SoloSession.reentry_before_cleanup_ack 'denied' 'authority seven-star reentry before cleanup acknowledgement'
  Assert-Null $SoloSession.runtime_progression_key 'authority seven-star runtime progression key'

  $MansionSession = $Authority.mansion_raid_session
  Assert-Equal $MansionSession.spec_id 'TT_SPEC_MANSION_RAID_SESSION_AUTHORITY' 'authority mansion session spec id'
  Assert-Null $MansionSession.runtime_key 'authority mansion session runtime key'
  Assert-Equal $MansionSession.session_kind 'team_raid' 'authority mansion session kind'
  Assert-Equal $MansionSession.participant_capacity.minimum 1 'authority mansion participant minimum'
  Assert-Equal $MansionSession.participant_capacity.maximum 4 'authority mansion participant maximum'
  Assert-Null $MansionSession.participant_capacity.runtime_key 'authority mansion capacity runtime key'
  Assert-ExactArray $MansionSession.identity_fields @('raid_instance_id', 'boss_instance_id', 'session_epoch', 'phase_id', 'revision', 'cleanup_token') 'authority mansion session identity fields'
  Assert-ExactArray $MansionSession.member_snapshot_fields @('actor_id', 'actor_lifecycle_id', 'member_status', 'membership_snapshot_id') 'authority mansion member snapshot fields'
  Assert-ExactArray $MansionSession.state_sequence @('active', 'cleanup_pending', 'closed') 'authority mansion state sequence'
  Assert-Equal $MansionSession.participant_validation.required_progress_spec_id 'TT_SPEC_PROGRESS_MAINLINE_CLEARED' 'authority mansion prerequisite progress'
  Assert-Condition ([string]$MansionSession.participant_validation.rule -match 'every_frozen_member_independently_requires_TT_SPEC_PROGRESS_MAINLINE_CLEARED') 'authority mansion per-member validation'
  foreach ($RejectedMember in @('leader_without_individual_mainline_completion', 'member_without_individual_mainline_completion', 'spectator', 'unfrozen_teammate', 'stale_lifecycle_member', 'client_injected_member')) {
    Assert-Condition ($MansionSession.participant_validation.rejected_actor_classes -contains $RejectedMember) "authority mansion rejected actor class: $RejectedMember"
  }
  Assert-ExactArray (@($MansionSession.modes | ForEach-Object { [string]$_.spec_id })) @('TT_SPEC_SESSION_MANSION_NORMAL', 'TT_SPEC_SESSION_MANSION_NIGHTMARE') 'authority mansion mode order'
  $MansionModesById = @{}
  foreach ($Mode in @($MansionSession.modes)) {
    Assert-Condition (-not $MansionModesById.ContainsKey([string]$Mode.spec_id)) "authority mansion mode is unique: $($Mode.spec_id)"
    $MansionModesById[[string]$Mode.spec_id] = $Mode
    Assert-Null $Mode.runtime_key "authority mansion mode runtime key: $($Mode.spec_id)"
    Assert-Null $Mode.completion_write_rule.writer_progress_spec_id "authority mansion mode does not write logical progression: $($Mode.spec_id)"
    Assert-Null $Mode.completion_write_rule.runtime_key "authority mansion mode completion runtime key: $($Mode.spec_id)"
  }
  Assert-Equal $MansionModesById['TT_SPEC_SESSION_MANSION_NORMAL'].difficulty 'normal' 'authority mansion normal difficulty'
  Assert-Condition ([string]$MansionModesById['TT_SPEC_SESSION_MANSION_NORMAL'].entry_rule -match 'per-member TT_SPEC_PROGRESS_MAINLINE_CLEARED') 'authority mansion normal member gate'
  Assert-Condition ([string]$MansionModesById['TT_SPEC_SESSION_MANSION_NORMAL'].completion_write_rule.rule -match '不写三段天庭主线逻辑进度') 'authority mansion normal excludes logical progression'
  Assert-Equal $MansionModesById['TT_SPEC_SESSION_MANSION_NIGHTMARE'].difficulty 'nightmare' 'authority mansion nightmare difficulty'
  Assert-Condition ([string]$MansionModesById['TT_SPEC_SESSION_MANSION_NIGHTMARE'].entry_rule -match 'TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL validation for every frozen member') 'authority mansion nightmare per-member credential gate'
  Assert-Condition ([string]$MansionModesById['TT_SPEC_SESSION_MANSION_NIGHTMARE'].completion_write_rule.rule -match '不写三段天庭主线逻辑进度') 'authority mansion nightmare excludes logical progression'
  Assert-ExactArray $MansionSession.cleanup_ack_identity_fields @('raid_instance_id', 'session_epoch', 'revision', 'cleanup_token') 'authority mansion cleanup identity fields'
  Assert-Equal $MansionSession.reentry_before_cleanup_ack 'denied' 'authority mansion reentry before cleanup acknowledgement'
  Assert-Null $MansionSession.runtime_progression_key 'authority mansion runtime progression key'

  $AuthorityRotation = $Authority.rotation_snapshot_contract
  Assert-Equal $AuthorityRotation.spec_id 'TT_SPEC_TIME_BASIS_ASIA_SHANGHAI_SHICHEN' 'authority rotation time-basis spec id'
  Assert-Null $AuthorityRotation.runtime_key 'authority rotation runtime key'
  Assert-ExactArray $AuthorityRotation.applies_to @('TT_SPEC_SESSION_MANSION_NORMAL', 'TT_SPEC_SESSION_MANSION_NIGHTMARE') 'authority rotation applies-to modes'
  Assert-Equal $AuthorityRotation.timezone 'Asia/Shanghai' 'authority rotation time zone'
  Assert-Equal $AuthorityRotation.time_basis 'server_authoritative_natural_shichen' 'authority rotation time basis'
  Assert-Null $AuthorityRotation.authority_time_provider_runtime_key 'authority rotation time-provider runtime key'
  Assert-ExactArray $AuthorityRotation.required_fields @('rotation_snapshot_id', 'schedule_version', 'authoritative_time_slot', 'quadrant', 'difficulty', 'instance_scope', 'authority_time_basis_id', 'captured_authoritative_instant', 'schema_version') 'authority rotation snapshot fields'
  Assert-Equal $AuthorityRotation.schedule.Count 4 'authority rotation schedule quadrant count'
  $AuthorityRotationSlots = @{}
  foreach ($RotationEntry in @($AuthorityRotation.schedule)) {
    Assert-Condition ($ExpectedRotationByQuadrant.ContainsKey([string]$RotationEntry.quadrant)) "authority rotation quadrant is valid: $($RotationEntry.quadrant)"
    Assert-ExactArray $RotationEntry.time_slots $ExpectedRotationByQuadrant[[string]$RotationEntry.quadrant] "authority rotation slots: $($RotationEntry.quadrant)"
    Assert-Null $RotationEntry.runtime_key "authority rotation entry runtime key: $($RotationEntry.quadrant)"
    $AuthorityRotationSlots[[string]$RotationEntry.quadrant] = $RotationEntry
  }
  foreach ($QuadrantName in $ExpectedRotationByQuadrant.Keys) {
    Assert-Condition ($AuthorityRotationSlots.ContainsKey($QuadrantName)) "authority rotation expected quadrant exists: $QuadrantName"
    $ExpansionRotationEntry = @($Raid.rotation.schedule | Where-Object { $_.quadrant -eq $QuadrantName })[0]
    Assert-Equal $AuthorityRotationSlots[$QuadrantName].raid_spec_id $ExpansionRotationEntry.raid_spec_id "authority rotation expansion raid-spec cross reference: $QuadrantName"
  }
  Assert-Condition ([string]$AuthorityRotation.creation_rule -match 'first successful authority raid-creation operation') 'authority rotation creation freezes first successful session'
  Assert-Equal $AuthorityRotation.client_clock_rule 'prohibited' 'authority rotation client clock prohibition'
  Assert-Equal $AuthorityRotation.client_quadrant_rule 'prohibited' 'authority rotation client quadrant prohibition'
  Assert-Condition ([string]$AuthorityRotation.recalculation_rule -match 'must_not_recalculate_quadrant_or_time_slot') 'authority rotation retry recalculation prohibition'
  Assert-Condition ([string]$AuthorityRotation.instance_lifetime_rule -match '不可变') 'authority rotation instance lifetime immutability'

  $NightmareQualification = $Authority.nightmare_qualification_contract
  Assert-Equal $NightmareQualification.spec_id 'TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL' 'authority nightmare credential spec id'
  Assert-Null $NightmareQualification.runtime_key 'authority nightmare credential runtime key'
  Assert-Equal $NightmareQualification.credential_scope 'character_and_quadrant' 'authority nightmare credential scope'
  Assert-Condition ($NightmareQualification.per_member_required -eq $true) 'authority nightmare credential is required per member'
  Assert-Null $NightmareQualification.credential_runtime_item_key 'authority nightmare credential runtime item key'
  Assert-Equal $NightmareQualification.credential_representation 'opaque_authority_resolved_credential' 'authority nightmare credential representation'
  Assert-ExactArray $NightmareQualification.required_fields @('credential_subject_actor_id', 'normal_clear_rotation_snapshot_id', 'normal_clear_quadrant', 'nightmare_access_credential', 'nightmare_rotation_snapshot_id', 'owner_scope', 'authority_proof_ref', 'schema_version') 'authority nightmare credential fields'
  Assert-Condition ([string]$NightmareQualification.per_member_validation_rule -match '每一个冻结成员') 'authority nightmare per-member validation rule'
  Assert-Equal $NightmareQualification.quadrant_match_rule 'normal_clear.quadrant == credential.quadrant == nightmare.rotation_snapshot.quadrant' 'authority nightmare quadrant match rule'
  Assert-Equal $NightmareQualification.actor_match_rule 'credential.credential_subject_actor_id == nightmare_member.actor_id' 'authority nightmare credential actor match rule'
  Assert-Condition ([string]$NightmareQualification.lifecycle_rule -match '跨角色凭证均被拒绝') 'authority nightmare rejects stale and cross-actor credentials'
  Assert-Condition ([string]$NightmareQualification.economy_boundary -match 'deferred_to_future_authoritative_economy_contract') 'authority nightmare economy remains deferred'

  $Recovery = $Authority.recovery_contract
  Assert-Equal $Recovery.spec_id 'TT_SPEC_TIANTING_INSTANCE_RECOVERY' 'authority recovery spec id'
  Assert-Null $Recovery.runtime_key 'authority recovery runtime key'
  Assert-ExactArray $Recovery.state_sequence @('active', 'cleanup_pending', 'closed') 'authority recovery state sequence'
  Assert-Condition ([string]$Recovery.shared_cleanup_rule -match 'instance identity, session_epoch, revision and cleanup_token all match') 'authority recovery matching cleanup identity rule'
  Assert-Equal $Recovery.solo.applies_to 'TT_SPEC_SESSION_SEVEN_STAR' 'authority solo recovery applies-to'
  Assert-ExactArray $Recovery.solo.failure_events @('owner_death', 'timeout', 'owner_disconnect', 'owner_lifecycle_invalid') 'authority solo recovery failure events'
  Assert-Equal $Recovery.solo.result 'transition_to_cleanup_pending_then_closed_only_after_matching_cleanup_ack' 'authority solo recovery result'
  Assert-Equal $Recovery.solo.reconnect_rule 'forbidden_before_matching_cleanup_ack' 'authority solo recovery reconnect prohibition'
  Assert-Null $Recovery.solo.runtime_key 'authority solo recovery runtime key'
  Assert-ExactArray $Recovery.team.applies_to @('TT_SPEC_SESSION_LINGXIAO_MAINLINE', 'TT_SPEC_SESSION_MANSION_NORMAL', 'TT_SPEC_SESSION_MANSION_NIGHTMARE') 'authority team recovery applies-to'
  Assert-Equal $Recovery.team.member_death.return_target 'current_chapter_initial_spawn' 'authority team death return target'
  Assert-Equal $Recovery.team.member_death.member_status 'dead' 'authority team death member status'
  Assert-Condition ($Recovery.team.member_death.revive_before_return -eq $true) 'authority team death revive-before-return rule'
  Assert-Equal $Recovery.team.member_death.reentry_lock 'until_matching_cleanup_ack' 'authority team death reentry lock'
  Assert-Equal $Recovery.team.member_death.already_dead_repeat_return 'forbidden' 'authority team death duplicate return prohibition'
  Assert-Null $Recovery.team.member_death.runtime_key 'authority team death runtime key'
  Assert-Equal $Recovery.team.member_disconnect.member_status 'left' 'authority team disconnect member status'
  Assert-Equal $Recovery.team.member_disconnect.reconnect_rule 'forbidden_for_the_current_raid_instance' 'authority team disconnect reconnect prohibition'
  Assert-Condition ([string]$Recovery.team.member_disconnect.completion_and_reward_eligibility -match 'cannot_receive') 'authority team disconnect completion and reward ineligibility'
  Assert-Condition ([string]$Recovery.team.member_disconnect.remaining_member_rule -match 'remaining_active_members_may_continue') 'authority team remaining members continue rule'
  Assert-Null $Recovery.team.member_disconnect.runtime_key 'authority team disconnect runtime key'
  Assert-Equal $Recovery.team.full_wipe_or_timeout.return_target 'current_chapter_initial_spawn' 'authority team wipe timeout return target'
  Assert-Condition ($Recovery.team.full_wipe_or_timeout.cleanup_ack_required -eq $true) 'authority team wipe timeout cleanup acknowledgement required'
  Assert-Equal $Recovery.team.full_wipe_or_timeout.already_dead_repeat_return 'forbidden' 'authority team wipe timeout duplicate return prohibition'
  Assert-Null $Recovery.team.full_wipe_or_timeout.runtime_key 'authority team wipe timeout runtime key'

  $ExpectedNegativeCaseIds = @(
    'TT_SPEC_NEGATIVE_PROTECTED_DIFU_KEY',
    'TT_SPEC_NEGATIVE_FORGED_ENTRY_PROOF',
    'TT_SPEC_NEGATIVE_PROXY_COMPLETION',
    'TT_SPEC_NEGATIVE_SOLO_PREMATURE_ENTRY',
    'TT_SPEC_NEGATIVE_RAID_MEMBER_GATE',
    'TT_SPEC_NEGATIVE_CLIENT_ROTATION',
    'TT_SPEC_NEGATIVE_NIGHTMARE_CREDENTIAL',
    'TT_SPEC_NEGATIVE_CLEANUP_REPLAY',
    'TT_SPEC_NEGATIVE_DUPLICATE_EVENT',
    'TT_SPEC_NEGATIVE_RUNTIME_OR_ECONOMY_LEAK'
  )
  $ExpectedNegativeResults = @(
    'reject_operation_without_progression_write_or_session_creation',
    'reject_chapter_entry_without_writing_TT_SPEC_PROGRESS_CHAPTER_ENTERED',
    'reject_actor_completion_write_and_preserve_existing_authoritative_results',
    'reject_solo_session_creation',
    'reject_raid_creation_for_the_whole_requested_roster',
    'reject_recalculation_and_return_existing_rotation_snapshot_only',
    'reject_nightmare_raid_creation_for_the_whole_requested_roster',
    'reject_cleanup_ack_and_preserve_current_lock_and_terminal_result',
    'return_first_authoritative_result_only_without_second_write_or_economic_effect',
    'reject_as_out_of_scope_for_offline_design_contract'
  )
  Assert-ExactArray (@($Authority.negative_cases | ForEach-Object { [string]$_.spec_id })) $ExpectedNegativeCaseIds 'authority negative-case order'
  for ($NegativeIndex = 0; $NegativeIndex -lt $ExpectedNegativeCaseIds.Count; $NegativeIndex++) {
    $NegativeCase = @($Authority.negative_cases)[$NegativeIndex]
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$NegativeCase.case)) "authority negative case text: $($ExpectedNegativeCaseIds[$NegativeIndex])"
    Assert-Equal $NegativeCase.expected_result $ExpectedNegativeResults[$NegativeIndex] "authority negative case result: $($ExpectedNegativeCaseIds[$NegativeIndex])"
    Assert-Null $NegativeCase.runtime_key "authority negative case runtime key: $($ExpectedNegativeCaseIds[$NegativeIndex])"
  }

  $AuthorityDeferredNames = @('trusted_proof_resolver_implementation', 'authoritative_level_query_implementation', 'authoritative_time_provider_implementation', 'actual_progression_storage', 'actual_session_storage', 'actual_cleanup_transport', 'actual_reconnect_transport', 'actual_map_and_spawn_bindings', 'actual_y3_objects_lua_ui_and_ecas', 'actual_nightmare_credential_representation_and_consumption', 'actual_reward_receipt_and_economy_issuance', 'runtime_key')
  Assert-RequiredProperties $Authority.deferred $AuthorityDeferredNames 'authority deferred'
  foreach ($DeferredName in $AuthorityDeferredNames) {
    Assert-Null $Authority.deferred.PSObject.Properties[$DeferredName].Value "authority deferred value: $DeferredName"
  }
  Assert-ExactArray $Authority.forbidden_field_names @('y3_id', 'y3_ids', 'map_resource_key', 'map_path', 'unit_id', 'ability_id', 'effect_id', 'projectile_id', 'item_id', 'item_key', 'progression_key', 'reward_amount', 'reward_exp', 'currency_amount', 'currency_key', 'item_amount', 'drop_probability', 'pity_threshold', 'equipment_stat_value', 'material_drop_count', 'key_consumption_amount') 'authority forbidden field names'
  Assert-Condition ($Authority.acceptance_invariants.Count -eq 9) 'authority acceptance invariant count'
  Assert-Condition (@($Authority.acceptance_invariants | Where-Object { [string]$_ -match '三段角色级逻辑进度' }).Count -gt 0) 'authority acceptance invariant logical progression'
  Assert-Condition (@($Authority.acceptance_invariants | Where-Object { [string]$_ -match 'Asia/Shanghai' }).Count -gt 0) 'authority acceptance invariant Asia Shanghai rotation'
  Assert-Condition (@($Authority.acceptance_invariants | Where-Object { [string]$_ -match 'normal_clear.quadrant == credential.quadrant == nightmare.rotation_snapshot.quadrant' }).Count -gt 0) 'authority acceptance invariant nightmare quadrant match'
  $AuthorityValidation = $Authority.validation_contract
  Assert-Equal $AuthorityValidation.validator '../validate-tianting-tower-spec.ps1' 'authority validation validator path'
  Assert-Condition ($AuthorityValidation.strict_schema -eq $true) 'authority validation strict schema'
  Assert-Condition ($AuthorityValidation.negative_tests_required -eq $true) 'authority validation negative tests required'
  Assert-Null $AuthorityValidation.required_runtime_key_value 'authority validation runtime key value'
  Assert-Equal $AuthorityValidation.production_gate 'closed' 'authority validation production gate'
  Assert-Null $AuthorityValidation.runtime_key 'authority validation runtime key'
  Assert-AllRuntimeKeysNull $Authority 'authority contract'
  Assert-NoForbiddenPropertyNames $Authority $Authority.forbidden_field_names 'authority contract'

  $TowerReuse = $Expansion.tower_reuse_interface
  Assert-Equal $TowerReuse.spec_id 'TT_SPEC_TOWER_TIANTING_CONTENT_REUSE' 'content expansion tower-reuse spec id'
  Assert-Equal $TowerReuse.decision_status 'fixed-user-requirement' 'content expansion tower-reuse status'
  Assert-Condition ((@($TowerReuse.mini_boss_cadence.candidate_options) -join '|') -eq '3|5') 'tower mini-Boss candidate options'
  Assert-Null $TowerReuse.mini_boss_cadence.selected_value 'tower mini-Boss selection remains deferred'
  Assert-Equal $TowerReuse.major_boss_cadence.every_floors 10 'tower major-Boss cadence'
  Assert-Equal $TowerReuse.major_boss_cadence.major_boss_design 'deferred_by_user' 'tower major-Boss design remains deferred'
  Assert-Null $TowerReuse.major_boss_cadence.runtime_key 'tower major-Boss runtime key'
  Assert-Equal $TowerReuse.first_cycle_isolation.rule 'content_pool_only; no binding to the existing five abstract beats' 'tower first-cycle isolation rule'
  Assert-Condition ($TowerReuse.first_cycle_isolation.must_not_bind_existing_beats -eq $true) 'tower first-cycle isolation prohibition'
  Assert-Array $TowerReuse.first_cycle_isolation.existing_beat_bindings 'tower first-cycle isolation bindings'
  Assert-Equal $TowerReuse.first_cycle_isolation.existing_beat_bindings.Count 0 'tower first-cycle isolation has no beat bindings'
  Assert-Null $TowerReuse.first_cycle_isolation.runtime_key 'tower first-cycle isolation runtime key'
  Assert-Null $TowerReuse.runtime_key 'content expansion tower-reuse runtime key'

  $Economy = $Contract.hard_constraints.economy_boundary
  Assert-Condition ([string]$Economy.future_resource_table_root -match '(^|/)economy-v2-resource-table\.json$') 'economy-v2 resource table root'
  Assert-Equal $Economy.required_state 'accepted-design-baseline-runtime-not-integrated' 'required resource table state'
  Assert-Equal $Economy.current_artifact_status 'accepted-design-baseline-runtime-not-integrated' 'current economy artifact status'
  Assert-Equal $Economy.resource_table_version 'economy-v2' 'economy resource table version'
  Assert-Equal $Economy.candidate_consumption_rule 'implementation/growth/ remains an offline candidate and must_not_be_used_as_tianting_resource_table' 'legacy candidate consumption prohibition'
  Assert-Equal $Economy.reference_role 'accepted_design_reference_runtime_not_integrated' 'economy reference role'
  Assert-Condition ($Contract.non_production_boundaries -contains 'implementation/growth/ remains an offline candidate; economy-v2 does not imply an authoritative runtime resource table, ledger, proof resolver or reward issuer.') 'non-production boundary must preserve the legacy candidate and runtime gate'
  Assert-Array $Economy.must_not_create 'economy forbidden values'
  Assert-Condition ($Economy.must_not_create -contains 'reward_amount') 'reward amount remains forbidden'
  Assert-Condition ($Economy.required_receipt_semantics -contains 'tower_award_class') 'tower award class is required by the current receipt contract'
  Assert-Condition ($Economy.must_not_create -contains 'season_value') 'season value remains forbidden'
  foreach ($field in @('owner_id', 'encounter_instance_id', 'qualification_snapshot_id', 'award_plan_hash', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_weekly_token_before', 'tower_weekly_token_after', 'award_outcome')) {
    Assert-Condition ($Economy.required_receipt_semantics -contains $field) "economy receipt semantics include $field"
  }
  Assert-Condition (-not ($Economy.required_receipt_semantics -contains 'actor_id')) 'economy receipt semantics use owner_id rather than actor_id'

  $Tower = $Contract.tracks.tower_first_cycle
  Assert-Equal $Tower.entry_rule 'level_at_least_55_for_every_participant' 'tower entry rule'
  Assert-Equal $Tower.rest_rule 'loadout_rest_every_5_floors' 'tower rest rule'
  Assert-Equal $Tower.linglong_relation 'theme_within_global_tower_only' 'tower Linglong relation'
  foreach ($PolicyName in @('floor_plan', 'affix_policy', 'season_policy')) {
    $Policy = $Tower.PSObject.Properties[$PolicyName].Value
    Assert-Equal $Policy.status 'deferred' "tower $PolicyName status"
    Assert-Null $Policy.effective_value "tower $PolicyName effective value"
  }
  Assert-Equal $Tower.reward_policy.status 'accepted_design_reference_runtime_not_integrated' 'tower reward policy status'
  Assert-Equal $Tower.reward_policy.resource_table_status 'accepted-design-baseline-runtime-not-integrated' 'tower reward policy resource table status'
  Assert-Equal $Tower.reward_policy.reference_role 'accepted_design_reference_runtime_not_integrated' 'tower reward policy reference role'
  Assert-Null $Tower.reward_policy.effective_value 'tower reward policy embedded effective value'
  Assert-Condition ([string]$Tower.reward_policy.resource_table_dependency -match '(^|/)economy-v2-resource-table\.json$') 'tower reward policy resource table dependency'
  Assert-Equal $Tower.reward_policy.resource_table_version 'economy-v2' 'tower reward policy resource table version'
  Assert-Equal $Tower.reward_policy.tower_qualification_policy_dependency 'TOWER_FIRST_CYCLE_QUALIFICATION_V1' 'tower reward policy qualification dependency'
  Assert-Condition ($Tower.reward_policy.qualification_snapshot_required -eq $true) 'tower reward policy qualification snapshot requirement'

  $CycleLink = $Tower.first_cycle_state_timing_contract
  Assert-Equal $CycleLink.status 'offline_design' 'tower first-cycle link status'
  Assert-Equal $CycleLink.artifact 'tower-first-cycle-state-contract.json' 'tower first-cycle link artifact'
  Assert-Equal $CycleLink.scope 'entry_gate_to_five_abstract_beats_to_fifth_rest_and_terminal_boundaries_only' 'tower first-cycle link scope'
  Assert-Equal $CycleLink.authority_rule 'future_authoritative_gameplay_logic_only' 'tower first-cycle authority rule'
  Assert-Equal $CycleLink.idempotency_rule 'future_semantic_envelope_returns_existing_authoritative_outcome_for_duplicates' 'tower first-cycle idempotency rule'
  Assert-Null $CycleLink.runtime_key 'tower first-cycle link runtime key'

  Assert-Equal $FirstCycle.version 1 'first-cycle contract version'
  Assert-Equal $FirstCycle.artifact_status 'offline_design' 'first-cycle contract status'
  Assert-Equal $FirstCycle.production_gate 'closed' 'first-cycle production gate'
  Assert-Equal $FirstCycle.inherited_constraints.future_economy_dependency 'economy-v2 exists_as_accepted-design-baseline-runtime-not-integrated; implementation/growth/ remains_an_offline_candidate_simulation_and_must_not_be_consumed' 'first-cycle growth dependency boundary'
  Assert-Equal $FirstCycle.identity.spec_id 'TT_SPEC_TOWER_FIRST_CYCLE' 'first-cycle contract spec id'
  Assert-Null $FirstCycle.identity.runtime_key 'first-cycle contract runtime key'
  Assert-Equal $FirstCycle.inherited_constraints.minimum_level_per_participant 55 'first-cycle minimum level'
  Assert-Equal $FirstCycle.inherited_constraints.member_check 'every_solo_player_or_team_member_independently' 'first-cycle per-member check'
  Assert-Equal $FirstCycle.inherited_constraints.rest_after_abstract_beat 5 'first-cycle rest beat'
  Assert-Equal $FirstCycle.inherited_constraints.linglong_relation 'theme_within_global_tongtian_tower_only' 'first-cycle Linglong relation'
  Assert-Equal $FirstCycle.inherited_constraints.protected_cross_chapter_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'first-cycle protected Difu key'
  Assert-Equal $FirstCycle.inherited_constraints.protected_key_rule 'must_not_read_or_write_as_tianting_default_input_without_new_explicit_decision' 'first-cycle protected Difu key rule'
  Assert-Equal $FirstCycle.entry_contract.spec_id 'TT_SPEC_TOWER_ENTRY_GATE' 'first-cycle entry spec id'
  Assert-Null $FirstCycle.entry_contract.runtime_key 'first-cycle entry runtime key'
  Assert-Equal $FirstCycle.entry_contract.accepted_target_state 'TT_SPEC_TOWER_STATE_BEAT_01_ACTIVE' 'first-cycle entry accept state'
  Assert-Equal $FirstCycle.entry_contract.rejected_target_state 'TT_SPEC_TOWER_STATE_ENTRY_DENIED' 'first-cycle entry reject state'

  $ExpectedCycleStateIds = @(
    'TT_SPEC_TOWER_STATE_ENTRY_CHECKING',
    'TT_SPEC_TOWER_STATE_ENTRY_DENIED',
    'TT_SPEC_TOWER_STATE_BEAT_01_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_02_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_03_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_04_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_05_ACTIVE',
    'TT_SPEC_TOWER_STATE_REST_05_OPEN',
    'TT_SPEC_TOWER_STATE_SETTLEMENT_PENDING',
    'TT_SPEC_TOWER_STATE_SETTLED',
    'TT_SPEC_TOWER_STATE_FAILURE_PENDING',
    'TT_SPEC_TOWER_STATE_FAILED',
    'TT_SPEC_TOWER_STATE_EXIT_PENDING',
    'TT_SPEC_TOWER_STATE_EXITED',
    'TT_SPEC_TOWER_STATE_NEXT_CYCLE_HANDOFF'
  )
  Assert-Array $FirstCycle.state_model.states 'first-cycle states'
  Assert-Condition ($FirstCycle.state_model.states.Count -eq $ExpectedCycleStateIds.Count) 'first-cycle state count'
  $CycleStatesById = @{}
  foreach ($State in $FirstCycle.state_model.states) {
    Assert-Condition ([string]$State.spec_id -match '^TT_SPEC_') "first-cycle state spec id: $($State.spec_id)"
    Assert-Null $State.runtime_key "first-cycle state runtime key: $($State.spec_id)"
    Assert-Condition (-not $CycleStatesById.ContainsKey([string]$State.spec_id)) "first-cycle state is unique: $($State.spec_id)"
    $CycleStatesById[[string]$State.spec_id] = $State
  }
  foreach ($StateId in $ExpectedCycleStateIds) {
    Assert-Condition ($CycleStatesById.ContainsKey($StateId)) "first-cycle expected state exists: $StateId"
  }
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_ENTRY_DENIED'].cycle_terminal) 'entry denied is cycle terminal'
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_SETTLED'].cycle_terminal) 'settled is cycle terminal'
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_FAILED'].cycle_terminal) 'failed is cycle terminal'
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_EXITED'].cycle_terminal) 'exited is cycle terminal'
  Assert-Condition ($CycleStatesById['TT_SPEC_TOWER_STATE_NEXT_CYCLE_HANDOFF'].cycle_terminal) 'next-cycle handoff is cycle terminal'

  Assert-Array $FirstCycle.abstract_floor_beats 'first-cycle abstract beats'
  Assert-Condition ($FirstCycle.abstract_floor_beats.Count -eq 5) 'first-cycle has exactly five abstract beats'
  $SortedBeats = @($FirstCycle.abstract_floor_beats | Sort-Object beat_index)
  for ($BeatIndex = 1; $BeatIndex -le 5; $BeatIndex++) {
    $Beat = $SortedBeats[$BeatIndex - 1]
    $ExpectedBeatSpecId = ('TT_SPEC_TOWER_BEAT_{0:D2}' -f $BeatIndex)
    $ExpectedActiveState = ('TT_SPEC_TOWER_STATE_BEAT_{0:D2}_ACTIVE' -f $BeatIndex)
    $ExpectedClearTarget = if ($BeatIndex -lt 5) { 'TT_SPEC_TOWER_STATE_BEAT_{0:D2}_ACTIVE' -f ($BeatIndex + 1) } else { 'TT_SPEC_TOWER_STATE_REST_05_OPEN' }
    Assert-Equal $Beat.beat_index $BeatIndex "first-cycle beat index: $BeatIndex"
    Assert-Equal $Beat.spec_id $ExpectedBeatSpecId "first-cycle beat spec id: $BeatIndex"
    Assert-Equal $Beat.active_state $ExpectedActiveState "first-cycle active state: $BeatIndex"
    Assert-Equal $Beat.clear_target_state $ExpectedClearTarget "first-cycle clear target: $BeatIndex"
    Assert-Equal $Beat.failure_target_state 'TT_SPEC_TOWER_STATE_FAILURE_PENDING' "first-cycle failure target: $BeatIndex"
    Assert-Equal $Beat.exit_target_state 'TT_SPEC_TOWER_STATE_EXIT_PENDING' "first-cycle exit target: $BeatIndex"
    Assert-Null $Beat.runtime_key "first-cycle beat runtime key: $BeatIndex"
  }

  Assert-Array $FirstCycle.transition_contract 'first-cycle transitions'
  Assert-Condition ($FirstCycle.transition_contract.Count -eq 15) 'first-cycle transition count'
  $CycleTransitionsById = @{}
  foreach ($Transition in $FirstCycle.transition_contract) {
    Assert-Condition ([string]$Transition.spec_id -match '^TT_SPEC_') "first-cycle transition spec id: $($Transition.spec_id)"
    Assert-Null $Transition.runtime_key "first-cycle transition runtime key: $($Transition.spec_id)"
    Assert-Condition (-not $CycleTransitionsById.ContainsKey([string]$Transition.spec_id)) "first-cycle transition is unique: $($Transition.spec_id)"
    $CycleTransitionsById[[string]$Transition.spec_id] = $Transition
  }
  foreach ($TransitionId in @(
    'TT_SPEC_TOWER_TRANSITION_ENTRY_ACCEPT',
    'TT_SPEC_TOWER_TRANSITION_ENTRY_DENY',
    'TT_SPEC_TOWER_TRANSITION_BEAT_01_CLEAR',
    'TT_SPEC_TOWER_TRANSITION_BEAT_02_CLEAR',
    'TT_SPEC_TOWER_TRANSITION_BEAT_03_CLEAR',
    'TT_SPEC_TOWER_TRANSITION_BEAT_04_CLEAR',
    'TT_SPEC_TOWER_TRANSITION_BEAT_05_CLEAR_TO_REST',
    'TT_SPEC_TOWER_TRANSITION_ACTIVE_BEAT_FAILURE',
    'TT_SPEC_TOWER_TRANSITION_ACTIVE_OR_REST_EXIT',
    'TT_SPEC_TOWER_TRANSITION_REST_BUILD_SWITCH',
    'TT_SPEC_TOWER_TRANSITION_REST_TO_SETTLEMENT',
    'TT_SPEC_TOWER_TRANSITION_SETTLEMENT_FINALIZE',
    'TT_SPEC_TOWER_TRANSITION_REST_TO_NEXT_CYCLE_HANDOFF',
    'TT_SPEC_TOWER_TRANSITION_FAILURE_FINALIZE',
    'TT_SPEC_TOWER_TRANSITION_EXIT_FINALIZE'
  )) {
    Assert-Condition ($CycleTransitionsById.ContainsKey($TransitionId)) "first-cycle expected transition exists: $TransitionId"
  }
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ENTRY_ACCEPT'].from 'TT_SPEC_TOWER_STATE_ENTRY_CHECKING' 'entry accept source'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ENTRY_ACCEPT'].to 'TT_SPEC_TOWER_STATE_BEAT_01_ACTIVE' 'entry accept target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ENTRY_DENY'].from 'TT_SPEC_TOWER_STATE_ENTRY_CHECKING' 'entry deny source'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ENTRY_DENY'].to 'TT_SPEC_TOWER_STATE_ENTRY_DENIED' 'entry deny target'
  for ($BeatIndex = 1; $BeatIndex -le 5; $BeatIndex++) {
    $ClearTransitionId = if ($BeatIndex -lt 5) { 'TT_SPEC_TOWER_TRANSITION_BEAT_{0:D2}_CLEAR' -f $BeatIndex } else { 'TT_SPEC_TOWER_TRANSITION_BEAT_05_CLEAR_TO_REST' }
    $ExpectedSource = 'TT_SPEC_TOWER_STATE_BEAT_{0:D2}_ACTIVE' -f $BeatIndex
    $ExpectedTarget = if ($BeatIndex -lt 5) { 'TT_SPEC_TOWER_STATE_BEAT_{0:D2}_ACTIVE' -f ($BeatIndex + 1) } else { 'TT_SPEC_TOWER_STATE_REST_05_OPEN' }
    Assert-Equal $CycleTransitionsById[$ClearTransitionId].from $ExpectedSource "clear transition source: $BeatIndex"
    Assert-Equal $CycleTransitionsById[$ClearTransitionId].to $ExpectedTarget "clear transition target: $BeatIndex"
  }
  $ExpectedActiveSources = @(
    'TT_SPEC_TOWER_STATE_BEAT_01_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_02_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_03_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_04_ACTIVE',
    'TT_SPEC_TOWER_STATE_BEAT_05_ACTIVE'
  )
  $FailureSources = @($CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ACTIVE_BEAT_FAILURE'].PSObject.Properties['from'].Value)
  Assert-Condition (($FailureSources -join '|') -eq ($ExpectedActiveSources -join '|')) 'failure transition sources'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ACTIVE_BEAT_FAILURE'].to 'TT_SPEC_TOWER_STATE_FAILURE_PENDING' 'failure transition target'
  $ExitSources = @($CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ACTIVE_OR_REST_EXIT'].PSObject.Properties['from'].Value)
  Assert-Condition (($ExitSources -join '|') -eq (($ExpectedActiveSources + 'TT_SPEC_TOWER_STATE_REST_05_OPEN') -join '|')) 'exit transition sources'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_ACTIVE_OR_REST_EXIT'].to 'TT_SPEC_TOWER_STATE_EXIT_PENDING' 'exit transition target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_REST_BUILD_SWITCH'].from 'TT_SPEC_TOWER_STATE_REST_05_OPEN' 'rest switch source'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_REST_BUILD_SWITCH'].to 'TT_SPEC_TOWER_STATE_REST_05_OPEN' 'rest switch remains in rest'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_REST_TO_SETTLEMENT'].to 'TT_SPEC_TOWER_STATE_SETTLEMENT_PENDING' 'rest settlement target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_SETTLEMENT_FINALIZE'].to 'TT_SPEC_TOWER_STATE_SETTLED' 'settlement terminal target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_REST_TO_NEXT_CYCLE_HANDOFF'].to 'TT_SPEC_TOWER_STATE_NEXT_CYCLE_HANDOFF' 'next-cycle handoff target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_FAILURE_FINALIZE'].to 'TT_SPEC_TOWER_STATE_FAILED' 'failure terminal target'
  Assert-Equal $CycleTransitionsById['TT_SPEC_TOWER_TRANSITION_EXIT_FINALIZE'].to 'TT_SPEC_TOWER_STATE_EXITED' 'exit terminal target'

  $Idempotency = $FirstCycle.idempotency_contract
  Assert-Equal $Idempotency.spec_id 'TT_SPEC_TOWER_FIRST_CYCLE_IDEMPOTENCY' 'first-cycle idempotency spec id'
  Assert-Equal $Idempotency.decision_status 'offline_design' 'first-cycle idempotency status'
  Assert-Null $Idempotency.runtime_key 'first-cycle idempotency runtime key'
  Assert-Equal $Idempotency.semantic_envelope.status 'deferred' 'first-cycle idempotency envelope status'
  Assert-Null $Idempotency.semantic_envelope.runtime_key 'first-cycle idempotency envelope runtime key'
  Assert-Null $Idempotency.semantic_envelope.assigned_values 'first-cycle idempotency envelope values'
  Assert-Array $Idempotency.semantic_envelope.required_field_names 'first-cycle idempotency envelope fields'
  foreach ($FieldName in @('future_run_scope', 'operation_id', 'request_kind', 'expected_source_state', 'actor_scope', 'qualification_snapshot_id', 'event_id', 'schema_version')) {
    Assert-Condition ($Idempotency.semantic_envelope.required_field_names -contains $FieldName) "first-cycle idempotency envelope field: $FieldName"
  }
  Assert-Array $Idempotency.rules 'first-cycle idempotency rules'
  Assert-Condition ($Idempotency.rules.Count -eq 4) 'first-cycle idempotency rule count'
  foreach ($Rule in $Idempotency.rules) {
    Assert-Condition ([string]$Rule.spec_id -match '^TT_SPEC_') "first-cycle idempotency rule spec id: $($Rule.spec_id)"
    Assert-Null $Rule.runtime_key "first-cycle idempotency rule runtime key: $($Rule.spec_id)"
  }

  $SettlementBoundary = $FirstCycle.settlement_boundary
  Assert-Equal $SettlementBoundary.spec_id 'TT_SPEC_TOWER_SETTLEMENT_BOUNDARY' 'first-cycle settlement spec id'
  Assert-Null $SettlementBoundary.runtime_key 'first-cycle settlement runtime key'
  Assert-Equal $SettlementBoundary.allowed_source_state 'TT_SPEC_TOWER_STATE_REST_05_OPEN' 'first-cycle settlement source'
  Assert-Equal $SettlementBoundary.required_intermediate_state 'TT_SPEC_TOWER_STATE_SETTLEMENT_PENDING' 'first-cycle settlement pending state'
  Assert-Equal $SettlementBoundary.terminal_state 'TT_SPEC_TOWER_STATE_SETTLED' 'first-cycle settlement terminal state'
  Assert-Equal $SettlementBoundary.economy_effect.status 'accepted_design_reference_runtime_not_integrated' 'first-cycle settlement economy status'
  Assert-Equal $SettlementBoundary.economy_effect.resource_table_status 'accepted-design-baseline-runtime-not-integrated' 'first-cycle settlement resource table status'
  Assert-Equal $SettlementBoundary.economy_effect.reference_role 'accepted_design_reference_runtime_not_integrated' 'first-cycle settlement reference role'
  Assert-Condition ([string]$SettlementBoundary.economy_effect.resource_table_dependency -match '(^|/)economy-v2-resource-table\.json$') 'first-cycle settlement resource table dependency'
  Assert-Equal $SettlementBoundary.economy_effect.resource_table_version 'economy-v2' 'first-cycle settlement resource table version'
  Assert-Null $SettlementBoundary.economy_effect.assigned_reward_values 'first-cycle settlement assigned rewards'
  Assert-Condition ($SettlementBoundary.economy_effect.prohibited -contains 'reward_amount') 'first-cycle settlement prohibits reward amount'
  Assert-Condition ($SettlementBoundary.economy_effect.prohibited -contains 'season_value') 'first-cycle settlement prohibits season value'
  foreach ($field in @('owner_id', 'qualification_snapshot_id', 'encounter_instance_id', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_weekly_token_before', 'tower_weekly_token_after', 'award_plan_hash', 'authority_proof_ref', 'award_outcome')) {
    Assert-Condition ($SettlementBoundary.economy_effect.required_receipt_fields -contains $field) "first-cycle settlement receipt includes $field"
  }

  $FailureExit = $FirstCycle.failure_and_exit_boundary
  Assert-Equal $FailureExit.spec_id 'TT_SPEC_TOWER_FAILURE_EXIT_BOUNDARY' 'first-cycle failure exit spec id'
  Assert-Null $FailureExit.runtime_key 'first-cycle failure exit runtime key'
  Assert-Condition ((@($FailureExit.failure.source_states) -join '|') -eq ($ExpectedActiveSources -join '|')) 'first-cycle failure boundary sources'
  Assert-Equal $FailureExit.failure.pending_state 'TT_SPEC_TOWER_STATE_FAILURE_PENDING' 'first-cycle failure boundary pending state'
  Assert-Equal $FailureExit.failure.terminal_state 'TT_SPEC_TOWER_STATE_FAILED' 'first-cycle failure boundary terminal state'
  Assert-Condition ((@($FailureExit.exit.source_states) -join '|') -eq (($ExpectedActiveSources + 'TT_SPEC_TOWER_STATE_REST_05_OPEN') -join '|')) 'first-cycle exit boundary sources'
  Assert-Equal $FailureExit.exit.pending_state 'TT_SPEC_TOWER_STATE_EXIT_PENDING' 'first-cycle exit boundary pending state'
  Assert-Equal $FailureExit.exit.terminal_state 'TT_SPEC_TOWER_STATE_EXITED' 'first-cycle exit boundary terminal state'

  $ContractNodes = @($Contract.worldview_anchors) + @($Contract.chapter_roles)
  foreach ($Node in $ContractNodes) {
    Assert-Condition ([string]$Node.spec_id -match '^TT_SPEC_') "contract spec id prefix: $($Node.spec_id)"
    Assert-Null $Node.runtime_key "contract runtime key: $($Node.spec_id)"
  }

  $RequiredDesignTop = @('version', 'project', 'sourceMaterials', 'worldview', 'playerExperience', 'coreLoop', 'sessionFlow', 'systems', 'content', 'mvp', 'handoffs', 'risks', 'unresolved', 'acceptanceCriteria', 'crossChapterBoundary', 'towerFirstCycleContract', 'contentExpansionContract', 'authorityProgressionAndInstanceContract')
  foreach ($Name in $RequiredDesignTop) {
    Assert-Condition (Test-HasProperty $Design $Name) "design top-level field: $Name"
  }
  Assert-Equal $Design.version 1 'design version'
  Assert-Equal $Design.project.targetDurationMinutes 0 'design duration deliberately unresolved'
  Assert-Equal $Design.crossChapterBoundary.protectedExistingKey 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'design protected Difu key'
  Assert-Equal $Design.crossChapterBoundary.defaultUse 'prohibited' 'design default Difu-key use'
  Assert-Equal $Design.crossChapterBoundary.entryContract 'authority/tianting-progression-and-instance-authority-contract.json' 'design entry contract'
  Assert-Equal $Design.crossChapterBoundary.trustedHandoffProducer 'DF_E_YANLUO_HALL' 'design entry trusted handoff producer'
  Assert-Null $Design.crossChapterBoundary.newRuntimeKey 'design new runtime key'
  Assert-Equal $Design.towerFirstCycleContract.artifact 'tower-first-cycle-state-contract.json' 'design first-cycle artifact'
  Assert-Equal $Design.towerFirstCycleContract.status 'offline_design' 'design first-cycle status'
  Assert-Equal $Design.towerFirstCycleContract.scope 'entry_gate_to_five_abstract_beats_to_fifth_rest_and_terminal_boundaries_only' 'design first-cycle scope'
  Assert-Null $Design.towerFirstCycleContract.runtimeKey 'design first-cycle runtime key'
  Assert-Null $Design.towerFirstCycleContract.totalFloorCount 'design first-cycle total floor count'
  Assert-Equal $Design.towerFirstCycleContract.economyEffect 'accepted_design_reference_runtime_not_integrated' 'design first-cycle economy effect'
  Assert-Equal $Design.towerFirstCycleContract.protectedDifuKeyUse 'prohibited' 'design first-cycle protected Difu key use'
  Assert-Equal $Design.contentExpansionContract.artifact 'tianting-content-expansion-contract.json' 'design content-expansion artifact'
  Assert-Equal $Design.contentExpansionContract.status 'offline_design' 'design content-expansion status'
  Assert-Null $Design.contentExpansionContract.runtimeKey 'design content-expansion runtime key'
  Assert-Condition ($Design.contentExpansionContract.towerReuseDoesNotBindExistingBeats -eq $true) 'design content-expansion does not bind tower beats'
  Assert-Equal $Design.authorityProgressionAndInstanceContract.artifact 'authority/tianting-progression-and-instance-authority-contract.json' 'design authority progression and instance artifact'
  Assert-Equal $Design.authorityProgressionAndInstanceContract.status 'offline_design' 'design authority progression and instance status'
  Assert-Null $Design.authorityProgressionAndInstanceContract.runtimeKey 'design authority progression and instance runtime key'
  Assert-Equal $Design.authorityProgressionAndInstanceContract.productionGate 'closed' 'design authority progression and instance production gate'

  foreach ($CollectionName in @('sourceMaterials', 'sessionFlow', 'systems', 'risks', 'unresolved', 'acceptanceCriteria')) {
    $Collection = $Design.PSObject.Properties[$CollectionName].Value
    Assert-Array $Collection "design collection: $CollectionName"
    Assert-Condition ($Collection.Count -gt 0) "design collection is non-empty: $CollectionName"
  }
  foreach ($MvpName in @('mustHave', 'shouldHave', 'later')) {
    $Collection = $Design.mvp.PSObject.Properties[$MvpName].Value
    Assert-Array $Collection "design MVP collection: $MvpName"
    Assert-Condition ($Collection.Count -gt 0) "design MVP collection is non-empty: $MvpName"
  }
  foreach ($HandoffName in @('objectConfig', 'terrainLayout', 'luaLogic', 'uiPipeline', 'reviewPanel')) {
    $Collection = $Design.handoffs.PSObject.Properties[$HandoffName].Value
    Assert-Array $Collection "design handoff collection: $HandoffName"
    Assert-Condition ($Collection.Count -gt 0) "design handoff collection is non-empty: $HandoffName"
  }
  foreach ($Bucket in @('heroes', 'abilities', 'monsters', 'bosses', 'items', 'maps', 'ui', 'economy', 'progression', 'waves')) {
    Assert-Condition (Test-HasProperty $Design.content $Bucket) "design content bucket: $Bucket"
    $Items = $Design.content.PSObject.Properties[$Bucket].Value
    Assert-Array $Items "design content bucket array: $Bucket"
    Assert-Condition ($Items.Count -gt 0) "design content bucket non-empty: $Bucket"
    foreach ($Item in $Items) {
      Assert-Condition ([string]$Item.specId -match '^TT_SPEC_') "design spec id prefix: $Bucket/$($Item.specId)"
      Assert-Null $Item.runtimeKey "design runtime key: $Bucket/$($Item.specId)"
    }
  }

  Assert-Equal $ObjectBrief.targetSkill 'y3-object-config' 'object handoff target skill'
  Assert-Condition (Test-HasProperty $ObjectBrief 'assetRequests') 'object handoff asset requests'
  foreach ($AssetName in @('heroes', 'abilities', 'monsters', 'bosses', 'items', 'economy', 'progression')) {
    $Asset = $ObjectBrief.assetRequests.PSObject.Properties[$AssetName].Value
    Assert-Condition ($null -ne $Asset) "object handoff asset request: $AssetName"
    Assert-Condition ([string]$Asset.specId -match '^TT_SPEC_') "object handoff spec id: $AssetName/$($Asset.specId)"
    Assert-Null $Asset.runtimeKey "object handoff runtime key: $AssetName/$($Asset.specId)"
  }
  Assert-Equal $TerrainBrief.targetSkill 'y3-terrain-layout' 'terrain handoff target skill'
  foreach ($RegionName in @('maps', 'waves', 'monsters', 'bosses')) {
    $Region = $TerrainBrief.PSObject.Properties[$RegionName].Value
    Assert-Condition ($null -ne $Region) "terrain handoff logical region: $RegionName"
    Assert-Condition ([string]$Region.specId -match '^TT_SPEC_') "terrain handoff spec id: $RegionName/$($Region.specId)"
    Assert-Null $Region.runtimeKey "terrain handoff runtime key: $RegionName/$($Region.specId)"
  }

  $PackageText = (Get-ChildItem -LiteralPath $PackageRoot -File -Recurse |
    Where-Object { $_.Name -ne 'validate-tianting-tower-spec.ps1' } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
  Assert-Condition ($PackageText -notmatch '(30|50)\s*(层|floors?)') 'package has no unapproved tower floor count'
  Assert-Condition ($PackageText -notmatch 'DF_PROGRESS_YANLUO_HALL_CLEARED\s*(可)?作为[^\r\n]{0,60}(默认前置|默认解锁|default prerequisite|default unlock)') 'package does not describe protected Difu key as a default unlock'
}
catch {
  $script:Errors.Add("validator exception: $($_.Exception.Message)") | Out-Null
}

if ($script:Errors.Count -gt 0) {
  Write-Output "VALIDATION FAILED: $($script:Errors.Count) issue(s) after $script:Checks check(s)"
  foreach ($ErrorMessage in $script:Errors) {
    Write-Output "- $ErrorMessage"
  }
  exit 1
}

Write-Output "VALIDATION PASSED: $script:Checks checks"
