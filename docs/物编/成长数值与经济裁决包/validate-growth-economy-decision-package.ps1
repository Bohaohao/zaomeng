param(
  [string]$PackageRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[object]]::new()
$info = [System.Collections.Generic.List[object]]::new()

function Add-Issue {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Code,
    [string]$Message,
    [string]$Path
  )
  $List.Add([pscustomobject]@{
    code = $Code
    message = $Message
    path = $Path
  }) | Out-Null
}

function Has-Prop {
  param($Object, [string]$Name)
  return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Test-StrictBoolean {
  param($Value, [bool]$Expected)
  return $Value -is [bool] -and [bool]$Value -eq $Expected
}

function Assert-AllowedCalibrationProperties {
  param($Node, [string[]]$Allowed, [string]$Path, [string]$Context)
  if (-not ($Node -is [pscustomobject])) {
    Add-Issue $script:errors 'invalid_calibration_object' "$Context must be a JSON object." $Path
    return
  }
  foreach ($property in $Node.PSObject.Properties) {
    if ($Allowed -notcontains $property.Name) {
      Add-Issue $script:errors 'unexpected_calibration_property' "$Context contains unsupported property: $($property.Name)." $Path
    }
  }
}

function Assert-RequiredCalibrationProperties {
  param($Node, [string[]]$Required, [string]$Path, [string]$Context)
  if (-not ($Node -is [pscustomobject])) { return }
  foreach ($name in $Required) {
    if (-not (Has-Prop $Node $name)) {
      Add-Issue $script:errors 'missing_calibration_property' "$Context is missing required property: $name." $Path
    }
  }
}

function Assert-NonBlankStringItems {
  param($Value, [string]$Path, [string]$Context)
  foreach ($item in (Get-Items $Value)) {
    if (-not ($item -is [string]) -or [string]::IsNullOrWhiteSpace([string]$item)) {
      Add-Issue $script:errors 'invalid_calibration_string_item' "$Context must contain only non-blank strings." $Path
    }
  }
}

function Assert-NullCalibrationObject {
  param($Node, [string[]]$ExpectedProperties, [string]$Path, [string]$Context)
  Assert-AllowedCalibrationProperties $Node $ExpectedProperties $Path $Context
  Assert-RequiredCalibrationProperties $Node $ExpectedProperties $Path $Context
  if (-not ($Node -is [pscustomobject])) { return }
  foreach ($property in $Node.PSObject.Properties) {
    if ($null -ne $property.Value) {
      Add-Issue $script:errors 'calibration_candidate_output_must_be_null' "$Context.$($property.Name) must remain null until adoption and evidence review." $Path
    }
  }
}

function Get-Items {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [array]) { return $Value }
  return @($Value)
}

function Get-CanonicalJson {
  param($Value)
  if ($null -eq $Value) { return 'null' }
  if ($Value -is [array]) {
    $parts = @()
    foreach ($item in $Value) {
      $parts += (Get-CanonicalJson $item)
    }
    return '[' + ($parts -join ',') + ']'
  }
  if ($Value -is [pscustomobject]) {
    $parts = @()
    foreach ($property in ($Value.PSObject.Properties | Sort-Object Name)) {
      $propertyName = $property.Name | ConvertTo-Json -Compress
      $parts += ($propertyName + ':' + (Get-CanonicalJson $property.Value))
    }
    return '{' + ($parts -join ',') + '}'
  }
  return ($Value | ConvertTo-Json -Compress)
}

function Read-JsonFile {
  param([string]$RelativePath)
  $path = Join-Path $script:Root $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    Add-Issue $script:errors 'file_not_found' "Missing required package file: $RelativePath" $RelativePath
    return $null
  }
  try {
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
  } catch {
    Add-Issue $script:errors 'invalid_json' $_.Exception.Message $RelativePath
    return $null
  }
}

function Assert-DecisionRef {
  param($Node, [string]$Path)
  if ($null -eq $Node) { return }
  if (-not (Has-Prop $Node 'decision_id')) {
    Add-Issue $script:errors 'missing_decision_id' 'A governed data node is missing decision_id.' $Path
    return
  }
  if (-not (Has-Prop $Node 'decision_status')) {
    Add-Issue $script:errors 'missing_decision_status' 'A governed data node is missing decision_status.' $Path
    return
  }
  $decisionId = [string]$Node.decision_id
  if (-not $script:DecisionMap.ContainsKey($decisionId)) {
    Add-Issue $script:errors 'unknown_decision_id' "Unknown decision_id: $decisionId" $Path
    return
  }
  if ((Has-Prop $Node 'decision_status') -and ([string]$Node.decision_status -ne [string]$script:DecisionMap[$decisionId].decision_status)) {
    Add-Issue $script:errors 'decision_status_mismatch' "Node status $($Node.decision_status) does not match register status $($script:DecisionMap[$decisionId].decision_status) for $decisionId." $Path
  }
}

function Test-GovernedNode {
  param($Node, [string]$Path)
  if ($null -eq $Node) { return }
  if ($Node -is [array]) {
    for ($i = 0; $i -lt $Node.Count; $i += 1) {
      Test-GovernedNode $Node[$i] "$Path[$i]"
    }
    return
  }
  if (-not ($Node -is [pscustomobject])) { return }

  if (Has-Prop $Node 'decision_id') {
    Assert-DecisionRef $Node $Path
  }

  if (Has-Prop $Node 'decision_status') {
    $status = [string]$Node.decision_status
    if ($script:AllowedStatuses -notcontains $status) {
      Add-Issue $script:errors 'invalid_decision_status' "Unsupported decision_status: $status" $Path
    }
    if ($status -ne 'accepted-baseline') {
      if ((Has-Prop $Node 'effective_value') -and $null -ne $Node.effective_value) {
        Add-Issue $script:errors 'non_effective_has_value' "Only accepted-baseline may contain effective_value; current status is $status." $Path
      }
      if ((Has-Prop $Node 'runtime_handoff') -and [bool]$Node.runtime_handoff) {
        Add-Issue $script:errors 'non_effective_runtime_handoff' "Only adopted data can enter runtime_handoff; current status is $status." $Path
      }
    } elseif ((Has-Prop $Node 'effective_value') -and ($Node.effective_value -is [pscustomobject]) -and (Has-Prop $Node 'decision_id') -and $script:DecisionMap.ContainsKey([string]$Node.decision_id)) {
      $registeredDecisionId = [string]$Node.decision_id
      $registeredValue = $script:DecisionMap[$registeredDecisionId].effective_value
      foreach ($field in $Node.effective_value.PSObject.Properties) {
        if (-not (Has-Prop $registeredValue $field.Name)) {
          Add-Issue $script:errors 'accepted_field_not_registered' "Accepted field $($field.Name) is absent from the decision register for $($Node.decision_id)." $Path
        } elseif ((Get-CanonicalJson $field.Value) -ne (Get-CanonicalJson $registeredValue.($field.Name))) {
          Add-Issue $script:errors 'accepted_value_mismatch' "Accepted field $($field.Name) does not match the registered value for $($Node.decision_id)." $Path
        }
      }
    }
  }

  foreach ($property in $Node.PSObject.Properties) {
    $childPath = if ($Path) { "$Path.$($property.Name)" } else { $property.Name }
    Test-GovernedNode $property.Value $childPath
  }
}

function Test-CalibrationCandidateValueBoundary {
  param($Node, [string]$Path)
  if ($null -eq $Node) { return }
  if ($Node -is [array]) {
    for ($i = 0; $i -lt $Node.Count; $i += 1) {
      Test-CalibrationCandidateValueBoundary $Node[$i] "$Path[$i]"
    }
    return
  }
  if (-not ($Node -is [pscustomobject])) { return }

  $productionNumericFields = @(
    'xp_to_next',
    'cumulative_xp',
    'base_xp',
    'currency_amount',
    'balance_delta',
    'drop_probability',
    'pity_threshold',
    'grant_count',
    'upgrade_cost',
    'material_amount',
    'reward_amount'
  )
  foreach ($property in $Node.PSObject.Properties) {
    $childPath = if ($Path) { "$Path.$($property.Name)" } else { $property.Name }
    if ($property.Name -eq 'effective_value' -and $null -ne $property.Value) {
      Add-Issue $script:errors 'calibration_effective_value_forbidden' 'Calibration candidates may not contain a non-null effective_value at any depth.' $childPath
    }
    if ($property.Name -eq 'runtime_handoff' -and -not (Test-StrictBoolean $property.Value $false)) {
      Add-Issue $script:errors 'calibration_runtime_handoff_forbidden' 'Calibration candidates must use a JSON Boolean runtime_handoff=false at every depth.' $childPath
    }
    if ($productionNumericFields -contains $property.Name -and $null -ne $property.Value) {
      Add-Issue $script:errors 'calibration_production_value_forbidden' "Calibration candidates may not assign production field $($property.Name)." $childPath
    }
    Test-CalibrationCandidateValueBoundary $property.Value $childPath
  }
}

function Test-OfflineSimulationBoundary {
  param($Register)

  if ($null -eq $Register -or -not (Has-Prop $Register 'offline_simulation_boundary')) {
    Add-Issue $errors 'missing_offline_simulation_boundary' 'The decision register must explicitly classify implementation/growth/ when an offline simulator exists.' 'decision-register.json'
    return
  }

  $boundary = $Register.offline_simulation_boundary
  if ([string]$boundary.artifact_root -ne 'implementation/growth/') {
    Add-Issue $errors 'invalid_offline_simulation_root' 'Offline simulation boundary must point to implementation/growth/.' 'decision-register.json.offline_simulation_boundary'
  }
  if ([string]$boundary.artifact_status -ne 'offline_candidate_simulation_not_adopted') {
    Add-Issue $errors 'invalid_offline_simulation_status' 'Offline simulation must remain an unadopted candidate.' 'decision-register.json.offline_simulation_boundary'
  }
  if (-not (Test-StrictBoolean $boundary.runtime_handoff $false)) {
    Add-Issue $errors 'offline_simulation_runtime_handoff_forbidden' 'Offline simulation boundary must set runtime_handoff=false.' 'decision-register.json.offline_simulation_boundary'
  }
  if ([string]$boundary.allowed_execution_boundary -ne 'trusted_node_fengari_offline_test_only') {
    Add-Issue $errors 'invalid_offline_simulation_execution_boundary' 'Offline simulation may execute only in the trusted Node/Fengari test boundary.' 'decision-register.json.offline_simulation_boundary'
  }

  $prohibited = Get-Items $boundary.prohibited_consumers
  foreach ($consumer in @('Y3 runtime', 'production ledger', 'production economy baseline', 'TianTing resource table')) {
    if ($prohibited -notcontains $consumer) {
      Add-Issue $errors 'offline_simulation_consumer_not_prohibited' "Offline simulation must explicitly prohibit consumer: $consumer." 'decision-register.json.offline_simulation_boundary'
    }
  }

  $requiredDecisionIds = @('ECO-XP-001', 'ECO-ITEM-001', 'ECO-LEDGER-001', 'ECO-LEDGER-002', 'ECO-P1-001', 'ECO-DROP-001', 'ECO-TOWER-001')
  $sourceDecisionIds = Get-Items $boundary.source_decision_ids
  foreach ($decisionId in $requiredDecisionIds) {
    if ($sourceDecisionIds -notcontains $decisionId) {
      Add-Issue $errors 'offline_simulation_source_decision_missing' "Offline simulation boundary must trace decision: $decisionId." 'decision-register.json.offline_simulation_boundary'
    } elseif (-not $script:DecisionMap.ContainsKey($decisionId)) {
      Add-Issue $errors 'offline_simulation_unknown_source_decision' "Offline simulation boundary references unknown decision: $decisionId." 'decision-register.json.offline_simulation_boundary'
    } elseif ([string]$script:DecisionMap[$decisionId].decision_status -eq 'accepted-baseline') {
      Add-Issue $errors 'offline_simulation_adopted_source_mismatch' "Offline simulation source decision $decisionId is already accepted-baseline and must be removed from the candidate boundary." 'decision-register.json.offline_simulation_boundary'
    }
  }
}

function Assert-ExactStringArray {
  param($Actual, [string[]]$Expected, [string]$Code, [string]$Message, [string]$Path)
  $items = @(Get-Items $Actual)
  if ($items.Count -ne $Expected.Count) {
    Add-Issue $script:errors $Code $Message $Path
    return
  }
  for ($index = 0; $index -lt $Expected.Count; $index += 1) {
    if ([string]($items[$index]) -ne [string]($Expected[$index])) {
      Add-Issue $script:errors $Code $Message $Path
      return
    }
  }
}

function Get-GrantSignature {
  param($Grants)
  $parts = @()
  foreach ($grant in (Get-Items $Grants)) {
    $parts += ("{0}:{1}" -f [string]$grant.key, [string]$grant.amount)
  }
  return ($parts -join '|')
}

function Test-EconomyV2Adoption {
  param($Table, $Register)

  $path = 'tables/economy-v2-resource-table.json'
  if ($null -eq $Table) { return }

  if ([string]$Table.table -ne 'economy-v2-resource-table' -or [string]$Table.resource_table_version -ne 'economy-v2') {
    Add-Issue $script:errors 'invalid_economy_v2_identity' 'economy-v2 must declare its immutable table name and version.' $path
  }
  if ([string]$Table.decision_status -ne 'accepted-baseline' -or [string]$Table.package_status -ne 'accepted-design-baseline-runtime-not-integrated') {
    Add-Issue $script:errors 'invalid_economy_v2_status' 'economy-v2 must be an accepted design baseline that is not runtime-integrated.' $path
  }
  if (-not (Test-StrictBoolean $Table.runtime_handoff $false) -or [string]$Table.production_gate -ne 'closed') {
    Add-Issue $script:errors 'economy_v2_runtime_gate_open' 'economy-v2 must keep runtime_handoff=false and production_gate=closed.' $path
  }
  if ([string]$Table.supersedes.resource_table_version -ne 'economy-v1' -or [string]$Table.supersedes.path -ne 'tables/economy-v1-resource-table.json' -or [string]$Table.supersedes.content_hash_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$Table.supersedes.reason -notmatch 'Receipt-contract audit hardening only') {
    Add-Issue $script:errors 'invalid_economy_v2_supersession' 'economy-v2 must preserve a hash-bound, receipt-hardening-only supersession of economy-v1.' $path
  } else {
    $historicalPath = Join-Path $script:Root 'tables/economy-v1-resource-table.json'
    $historicalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $historicalPath).Hash
    if ($historicalHash -ine [string]$Table.supersedes.content_hash_sha256) {
      Add-Issue $script:errors 'economy_v1_historical_hash_mismatch' 'economy-v2 must retain the exact immutable economy-v1 source hash that it supersedes.' $path
    }
  }

  $expectedDecisionIds = @('ECO-XP-V2-001', 'ECO-MAT-V2-001', 'ECO-LEDGER-V2-001', 'ECO-P1-V2-001', 'ECO-DROP-V2-001', 'ECO-TOWER-V2-001')
  Assert-ExactStringArray -Actual $Table.decision_ids -Expected $expectedDecisionIds -Code 'invalid_economy_v2_decision_ids' -Message 'economy-v2 must declare its six adopted decision IDs in canonical order.' -Path "$path.decision_ids"
  foreach ($decisionId in $expectedDecisionIds) {
    if (-not $script:DecisionMap.ContainsKey($decisionId)) {
      Add-Issue $script:errors 'economy_v2_decision_not_registered' "economy-v2 decision $decisionId is absent from the decision register." $path
      continue
    }
    $decision = $script:DecisionMap[$decisionId]
    if ([string]$decision.decision_status -ne 'accepted-baseline' -or -not (Test-StrictBoolean $decision.runtime_handoff $false) -or -not (Test-StrictBoolean $decision.current $true)) {
      Add-Issue $script:errors 'invalid_economy_v2_registered_decision' "economy-v2 decision $decisionId must be accepted-baseline with runtime_handoff=false." 'decision-register.json'
    }
    if ([string]$decision.effective_value.resource_table_version -ne 'economy-v2' -or [string]$decision.effective_value.table_path -ne 'tables/economy-v2-resource-table.json') {
      Add-Issue $script:errors 'economy_v2_registered_table_mismatch' "economy-v2 decision $decisionId must point at the adopted resource table." 'decision-register.json'
    }
  }
  $adoptedTableFound = $false
  if ($null -ne $Register) {
    foreach ($entry in (Get-Items $Register.adopted_resource_tables)) {
      if ([string]$entry.resource_table_version -eq 'economy-v2' -and [string]$entry.path -eq 'tables/economy-v2-resource-table.json') {
        $adoptedTableFound = $true
        if ([string]$entry.decision_status -ne 'accepted-baseline' -or [string]$entry.package_status -ne 'accepted-design-baseline-runtime-not-integrated' -or -not (Test-StrictBoolean $entry.runtime_handoff $false) -or [string]$entry.production_gate -ne 'closed' -or -not (Test-StrictBoolean $entry.current $true) -or [string]$entry.lifecycle_status -ne 'current' -or [string]$entry.supersedes_resource_table_version -ne 'economy-v1') {
          Add-Issue $script:errors 'invalid_economy_v2_register_status' 'The registered economy-v2 table must remain a runtime-closed accepted design baseline.' 'decision-register.json.adopted_resource_tables'
        }
        $expectedHash = [string]$entry.content_hash_sha256
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $script:Root 'tables/economy-v2-resource-table.json')).Hash
        if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$' -or $actualHash -ine $expectedHash) {
          Add-Issue $script:errors 'economy_v2_resource_table_hash_mismatch' 'decision-register.json must lock the exact immutable economy-v2 resource-table SHA-256.' 'decision-register.json.adopted_resource_tables'
        }
      }
    }
  }
  if (-not $adoptedTableFound) {
    Add-Issue $script:errors 'economy_v2_table_not_registered' 'decision-register.json must register economy-v2 as an adopted, runtime-closed design table.' 'decision-register.json.adopted_resource_tables'
  }
  if ($null -eq $Register -or [string]$Register.current_accepted_resource_table_version -ne 'economy-v2') {
    Add-Issue $script:errors 'invalid_current_economy_resource_table' 'decision-register.json must name economy-v2 as the only current accepted resource table.' 'decision-register.json'
  } else {
    $historicalEntry = $null
    foreach ($entry in (Get-Items $Register.adopted_resource_tables)) {
      if ([string]$entry.resource_table_version -eq 'economy-v1') { $historicalEntry = $entry; break }
    }
    if ($null -eq $historicalEntry -or -not (Test-StrictBoolean $historicalEntry.current $false) -or [string]$historicalEntry.lifecycle_status -ne 'superseded-historical' -or [string]$historicalEntry.successor_resource_table_version -ne 'economy-v2') {
      Add-Issue $script:errors 'invalid_economy_v1_historical_register_state' 'decision-register.json must retain economy-v1 only as a superseded historical table.' 'decision-register.json.adopted_resource_tables'
    }
    $historicalDecisionMap = @{
      'ECO-XP-V1-001' = 'ECO-XP-V2-001'; 'ECO-MAT-V1-001' = 'ECO-MAT-V2-001'; 'ECO-LEDGER-V1-001' = 'ECO-LEDGER-V2-001'; 'ECO-P1-V1-001' = 'ECO-P1-V2-001'; 'ECO-DROP-V1-001' = 'ECO-DROP-V2-001'; 'ECO-TOWER-V1-001' = 'ECO-TOWER-V2-001'
    }
    foreach ($historicalId in $historicalDecisionMap.Keys) {
      $historicalDecision = $script:DecisionMap[$historicalId]
      if ($null -eq $historicalDecision -or -not (Test-StrictBoolean $historicalDecision.current $false) -or [string]$historicalDecision.superseded_by -ne [string]$historicalDecisionMap[$historicalId] -or [string]$historicalDecision.effective_scope -notmatch '^superseded-historical' -or -not ((Get-Items $historicalDecision.source_refs) -match 'economy-v1-resource-table\.json#/')) {
        Add-Issue $script:errors 'invalid_economy_v1_historical_decision' "Historical decision $historicalId must be explicitly superseded by its economy-v2 successor and use a stable table pointer." 'decision-register.json'
      }
    }
  }

  $progression = $Table.progression
  if ([string]$progression.decision_id -ne 'ECO-XP-V2-001' -or [string]$progression.owner_scope -ne 'character' -or [int]$progression.level_cap -ne 60) {
    Add-Issue $script:errors 'invalid_economy_v2_progression_header' 'economy-v2 progression must be character-scoped and capped at Lv60.' "$path.progression"
  }
  $chapterRanges = @('1-20', '21-40', '41-60')
  $actualChapterRanges = @()
  foreach ($chapter in (Get-Items $progression.chapters)) {
    $actualChapterRanges += ("{0}-{1}" -f [int]$chapter.level_range[0], [int]$chapter.level_range[1])
  }
  Assert-ExactStringArray -Actual $actualChapterRanges -Expected $chapterRanges -Code 'invalid_economy_v2_chapter_ranges' -Message 'economy-v2 must retain the Lv1-20/Lv21-40/Lv41-60 chapter ranges.' -Path "$path.progression.chapters"

  $legacyRows = Get-Items $progression.legacy_explicit_rows
  if ($legacyRows.Count -ne 19) {
    Add-Issue $script:errors 'invalid_economy_v2_legacy_row_count' 'economy-v2 must contain the 19 explicit Lv1-Lv19 rows.' "$path.progression.legacy_explicit_rows"
  } else {
    $expectedCumulative = 0
    for ($index = 0; $index -lt $legacyRows.Count; $index += 1) {
      $row = $legacyRows[$index]
      if ([int]$row.level -ne ($index + 1) -or [int]$row.cumulative_xp -ne $expectedCumulative -or [int]$row.xp_to_next -le 0) {
        Add-Issue $script:errors 'invalid_economy_v2_legacy_curve' 'The Lv1-Lv19 progression rows must be contiguous positive XP steps with cumulative totals.' "$path.progression.legacy_explicit_rows"
        break
      }
      $expectedCumulative += [int]$row.xp_to_next
    }
    if ($expectedCumulative -ne 9485) {
      Add-Issue $script:errors 'invalid_economy_v2_huaguoshan_total_xp' 'The frozen Lv1-Lv20 curve must total 9485 cumulative XP at Lv20.' "$path.progression.legacy_explicit_rows"
    }
  }
  $curve = $progression.post_huaguoshan_curve
  if ([string]$curve.formula -ne 'xp_to_next(level) = 5 * round_half_up(250 * 1.08^(level - 20))' -or [string]$curve.rounding -ne 'round_half_up_to_integer_before_multiplying_by_5') {
    Add-Issue $script:errors 'invalid_economy_v2_post_curve' 'economy-v2 must retain its exact Lv20-Lv59 formula and rounding policy.' "$path.progression.post_huaguoshan_curve"
  }
  $anchorMap = @{}
  foreach ($anchor in (Get-Items $curve.validation_anchors)) { $anchorMap[[int]$anchor.level] = $anchor }
  $runningCumulative = 9485
  for ($level = 20; $level -le 59; $level += 1) {
    $expectedNext = 5 * [math]::Round(250 * [math]::Pow(1.08, $level - 20), 0, [System.MidpointRounding]::AwayFromZero)
    if ($anchorMap.ContainsKey($level)) {
      $anchor = $anchorMap[$level]
      if ([int]$anchor.xp_to_next -ne $expectedNext -or [int]$anchor.cumulative_xp -ne $runningCumulative) {
        Add-Issue $script:errors 'invalid_economy_v2_progression_anchor' "economy-v2 validation anchor Lv$level does not match the frozen curve." "$path.progression.post_huaguoshan_curve.validation_anchors"
      }
    }
    $runningCumulative += $expectedNext
  }
  if (-not $anchorMap.ContainsKey(60) -or [int]$anchorMap[60].xp_to_next -ne 0 -or [int]$anchorMap[60].cumulative_xp -ne $runningCumulative -or $runningCumulative -ne 333300) {
    Add-Issue $script:errors 'invalid_economy_v2_level_cap_anchor' 'economy-v2 must freeze Lv60 at 333300 cumulative XP with no next-level requirement.' "$path.progression.post_huaguoshan_curve.validation_anchors"
  }
  $expectedXpSources = [ordered]@{
    'XP_INTRO' = 100; 'XP_MOUNTAIN' = 500; 'XP_WATERFALL' = 500; 'XP_MACAQUE' = 800; 'XP_PEACH' = 600; 'XP_CAVE' = 650; 'XP_SEVENSTAR' = 800; 'XP_PENG' = 500; 'XP_EASTSEA' = 900; 'XP_JIAO' = 1200; 'XP_SHARK' = 1200; 'XP_CHAPTER_CLEAR' = 1735
  }
  $xpSourceMap = @{}
  foreach ($row in (Get-Items $progression.huaguoshan_source_rows)) { $xpSourceMap[[string]$row.source_key] = [int]$row.base_xp }
  if ($xpSourceMap.Count -ne $expectedXpSources.Count) {
    Add-Issue $script:errors 'invalid_economy_v2_xp_source_count' 'economy-v2 must retain exactly the frozen Huaguoshan XP source rows.' "$path.progression.huaguoshan_source_rows"
  }
  foreach ($key in $expectedXpSources.Keys) {
    if (-not $xpSourceMap.ContainsKey($key) -or $xpSourceMap[$key] -ne $expectedXpSources[$key]) {
      Add-Issue $script:errors 'invalid_economy_v2_xp_source_value' "economy-v2 XP source $key must retain its frozen value." "$path.progression.huaguoshan_source_rows"
    }
  }
  $sourceBudget = 0
  foreach ($entry in (Get-Items $progression.future_chapter_source_budget_basis_points)) { $sourceBudget += [int]$entry.weight_basis_points }
  if ($sourceBudget -ne 10000) {
    Add-Issue $script:errors 'invalid_economy_v2_source_budget' 'Future chapter XP source weights must total 10000 basis points.' "$path.progression.future_chapter_source_budget_basis_points"
  }
  $party = $progression.party_policy
  if ([string]$party.policy_id -ne 'XP_PARTY_FULL_QUALIFIED_V1' -or [string]$party.distribution -ne 'each_qualified_character_receives_the_full_base_award_once' -or -not (Test-StrictBoolean $party.party_size_changes_base_award $false)) {
    Add-Issue $script:errors 'invalid_economy_v2_party_policy' 'economy-v2 must retain full qualified individual XP without party-size dilution.' "$path.progression.party_policy"
  }
  $repeatQuota = $party.repeat_clear_quota
  Assert-ExactStringArray -Actual $repeatQuota.quota_identity -Expected @('owner_id', 'xp_source_key', 'xp_session_id') -Code 'invalid_economy_v2_xp_repeat_quota_identity' -Message 'XP repeat quota must bind owner, source, and authoritative session.' -Path "$path.progression.party_policy.repeat_clear_quota"
  Assert-ExactStringArray -Actual $repeatQuota.receipt_fields -Expected @('xp_session_id', 'xp_repeat_multiplier_basis_points') -Code 'invalid_economy_v2_xp_repeat_quota_receipt_fields' -Message 'XP repeat quota must persist its session and multiplier receipt fields.' -Path "$path.progression.party_policy.repeat_clear_quota"
  if ([int]$repeatQuota.full_clear_multiplier_basis_points -ne 10000 -or [int]$repeatQuota.repeat_clear_multiplier_basis_points -ne 2500 -or [string]$repeatQuota.session_lifecycle -notmatch 'Reconnect' -or [string]$repeatQuota.quota_consume_rule -notmatch 'same compare-and-swap or serializable transaction' -or [string]$repeatQuota.quota_consume_rule -notmatch 'no prepared receipt or prepared state exists') {
    Add-Issue $script:errors 'invalid_economy_v2_xp_repeat_quota' 'XP repeat quota must freeze 10000/2500 multipliers, reconnect-stable sessions, atomic quota consumption, and no prepared receipt state.' "$path.progression.party_policy.repeat_clear_quota"
  }
  $xpReceiptCalculation = $party.xp_receipt_calculation
  Assert-ExactStringArray -Actual $xpReceiptCalculation.required_authoritative_inputs -Expected @('xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_session_id') -Code 'invalid_economy_v2_xp_receipt_inputs' -Message 'XP receipts must retain all immutable calculation inputs.' -Path "$path.progression.party_policy.xp_receipt_calculation"
  if ([string]$xpReceiptCalculation.calculation_rule_id -ne 'XP_FLOOR_REPEAT_THEN_OVERLEVEL_V1' -or [string]$xpReceiptCalculation.formula -notmatch 'experience_delta' -or [string]$xpReceiptCalculation.level_cap_rule -notmatch 'experience_delta=0') {
    Add-Issue $script:errors 'invalid_economy_v2_xp_receipt_calculation' 'XP receipt calculation must freeze ordering, output, and the Lv60 rejection behavior.' "$path.progression.party_policy.xp_receipt_calculation"
  }
  $xpBinding = $party.xp_receipt_binding_contract
  Assert-ExactStringArray -Actual $xpBinding.source_row_equality_fields -Expected @('xp_source_kind', 'xp_base_amount', 'xp_source_level') -Code 'invalid_economy_v2_xp_source_row_binding' -Message 'XP receipts must bind source kind, base amount, and source level to the frozen source row.' -Path "$path.progression.party_policy.xp_receipt_binding_contract"
  Assert-ExactStringArray -Actual $xpBinding.settlement_kind_values -Expected @('base_clear', 'repeat_clear') -Code 'invalid_economy_v2_xp_settlement_kinds' -Message 'XP receipts must distinguish base_clear from repeat_clear.' -Path "$path.progression.party_policy.xp_receipt_binding_contract"
  $kindBindings = Get-Items $xpBinding.settlement_kind_multiplier_binding
  if ([string]$xpBinding.source_catalog -ne 'progression.huaguoshan_source_rows' -or [string]$xpBinding.source_lookup_field -ne 'xp_source_key' -or [string]$xpBinding.unmapped_or_mismatched_source_outcome -ne 'rejected' -or [string]$xpBinding.settlement_kind_field -ne 'xp_settlement_kind' -or $kindBindings.Count -ne 2 -or [string]$kindBindings[0].xp_settlement_kind -ne 'base_clear' -or [int]$kindBindings[0].xp_repeat_multiplier_basis_points -ne 10000 -or [string]$kindBindings[1].xp_settlement_kind -ne 'repeat_clear' -or [int]$kindBindings[1].xp_repeat_multiplier_basis_points -ne 2500 -or [string]$xpBinding.over_level_multiplier_rule -notmatch 'must equal' -or [string]$xpBinding.settlement_kind_authority_rule -notmatch 'may not choose' -or [string]$xpBinding.experience_delta_rule -notmatch 'must equal') {
    Add-Issue $script:errors 'invalid_economy_v2_xp_receipt_binding_contract' 'XP receipt binding must reject source, multiplier, settlement-kind, and calculated-output drift.' "$path.progression.party_policy.xp_receipt_binding_contract"
  }

  $ledger = $Table.currencies_and_materials
  if ([string]$ledger.currency_decision_id -ne 'ECO-LEDGER-V2-001' -or [string]$ledger.material_decision_id -ne 'ECO-MAT-V2-001' -or [string]$ledger.owner_scope -ne 'character' -or [string]$ledger.team_wallet -ne 'disabled' -or [string]$ledger.trade -ne 'disabled') {
    Add-Issue $script:errors 'invalid_economy_v2_ledger_policy' 'economy-v2 currencies and materials must be character-owned, non-tradable, and without a team wallet.' "$path.currencies_and_materials"
  }
  $expectedCurrencyCaps = [ordered]@{'CUR_GOLD' = 9999999; 'CUR_RAID_MARK' = 99999; 'CUR_TOWER_TOKEN' = 99999}
  $currencyMap = @{}
  foreach ($currencyEntry in (Get-Items $ledger.currencies)) { $currencyMap[[string]$currencyEntry.currency_key] = [int]$currencyEntry.balance_cap }
  foreach ($key in $expectedCurrencyCaps.Keys) {
    if (-not $currencyMap.ContainsKey($key) -or $currencyMap[$key] -ne $expectedCurrencyCaps[$key]) {
      Add-Issue $script:errors 'invalid_economy_v2_currency_cap' "economy-v2 currency $key must retain its frozen cap." "$path.currencies_and_materials.currencies"
    }
  }
  $expectedMaterialCaps = [ordered]@{'MAT_STRENGTHEN_SHARD' = 9999; 'MAT_ADVANCE_HG' = 9999; 'MAT_ARTIFACT_DUST' = 9999}
  $materialMap = @{}
  foreach ($material in (Get-Items $ledger.material_keys)) { $materialMap[[string]$material.material_key] = [int]$material.stack_cap }
  foreach ($key in $expectedMaterialCaps.Keys) {
    if (-not $materialMap.ContainsKey($key) -or $materialMap[$key] -ne $expectedMaterialCaps[$key]) {
      Add-Issue $script:errors 'invalid_economy_v2_material_cap' "economy-v2 material $key must retain its frozen cap." "$path.currencies_and_materials.material_keys"
    }
  }
  if ([string]$ledger.balance_and_stack_cap_policy.award_application -ne 'all_or_nothing_by_award_plan' -or [string]$ledger.balance_and_stack_cap_policy.partial_award -ne 'forbidden' -or [string]$ledger.balance_and_stack_cap_policy.pending_mail -ne 'forbidden' -or [string]$ledger.balance_and_stack_cap_policy.overflow_outcome -notmatch 'pity_before and pity_after as equal') {
    Add-Issue $script:errors 'invalid_economy_v2_cap_policy' 'economy-v2 must freeze all-or-nothing balance and stack cap behavior.' "$path.currencies_and_materials.balance_and_stack_cap_policy"
  }

  $qualification = $Table.qualification
  if ([string]$qualification.public_chest_decision_id -ne 'ECO-P1-V2-001' -or [string]$qualification.final_policy_id -ne 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION' -or [int]$qualification.policy_version -ne 1) {
    Add-Issue $script:errors 'invalid_economy_v2_p1_identity' 'economy-v2 must freeze P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION v1.' "$path.qualification"
  }
  if ([string]$qualification.participation_chest_eligibility -ne 'when a qualifying public-action window opened: valid_public_action AND (damage_ratio_ge_0.03 OR valid_break OR valid_guard); otherwise: damage_ratio_ge_0.03 OR valid_break OR valid_guard') {
    Add-Issue $script:errors 'invalid_economy_v2_p1_chest_rule' 'economy-v2 must retain the action-window P1 chest rule.' "$path.qualification"
  }
  if ([string]$qualification.public_rare_eligibility -notmatch 'For public_rare_drop only' -or [string]$qualification.public_rare_eligibility -notmatch 'settled eligible participation-chest receipt' -or [string]$qualification.public_rare_eligibility -notmatch 'never inferred') {
    Add-Issue $script:errors 'invalid_economy_v2_rare_boundary' 'economy-v2 rare eligibility must require an independently attested clear and an already settled chest receipt.' "$path.qualification"
  }
  $publicChestSettlement = $qualification.public_chest_settlement
  Assert-ExactStringArray -Actual $publicChestSettlement.allowed_profile_keys -Expected @('HG_DROP_MACAQUE_PUBLIC', 'HG_DROP_JIAO_PUBLIC', 'HG_DROP_SHARK_PUBLIC') -Code 'invalid_economy_v2_public_chest_profiles' -Message 'P1 participation chest must be limited to the three frozen public profiles.' -Path "$path.qualification.public_chest_settlement"
  if ([string]$publicChestSettlement.event_type -ne 'participation_chest' -or [string]$publicChestSettlement.policy_field -ne 'p1_policy_id' -or [string]$publicChestSettlement.policy_id -ne 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION' -or [string]$publicChestSettlement.source_profile_rule -notmatch 'source_profile equals the exact public profile_key' -or [string]$publicChestSettlement.content_rule -notmatch 'only base-bundle grant' -or [string]$publicChestSettlement.downstream_binding_rule -notmatch 'same owner_id, event_id, encounter_instance_id, qualification_snapshot_id, source_profile, and resource_table_version') {
    Add-Issue $script:errors 'invalid_economy_v2_public_chest_settlement' 'P1 participation chest must be the bound public-profile base-bundle settlement path.' "$path.qualification.public_chest_settlement"
  }
  $requiredPublicSnapshotFields = @('schema_version', 'policy_id', 'snapshot_id', 'owner_id', 'encounter_instance_id', 'boss_instance_id', 'phase_id', 'event_id', 'public_action_window_opened', 'action_window_id', 'damage_ratio', 'valid_break', 'valid_guard', 'valid_public_action', 'rare_clear_attested', 'authority_proof_ref')
  Assert-ExactStringArray -Actual $qualification.public_qualification_snapshot_required_fields -Expected $requiredPublicSnapshotFields -Code 'invalid_economy_v2_public_snapshot_fields' -Message 'economy-v2 must freeze the minimum public qualification snapshot fields.' -Path "$path.qualification.public_qualification_snapshot_required_fields"
  if ([string]$qualification.team_raid_policy.policy_id -ne 'TEAM_RAID_RARE_ELIGIBILITY_V1' -or [int]$qualification.team_raid_policy.member_count_range[0] -ne 1 -or [int]$qualification.team_raid_policy.member_count_range[1] -ne 4 -or [string]$qualification.team_raid_policy.public_participation_chest_precondition -notmatch 'not-applicable' -or [string]$qualification.team_raid_policy.receipt_identity_binding -notmatch 'event_id MUST equal completion_event_id') {
    Add-Issue $script:errors 'invalid_economy_v2_team_raid_policy' 'economy-v2 must freeze the 1-4 member team raid policy without a public chest precondition.' "$path.qualification.team_raid_policy"
  }

  $drops = $Table.drops_and_pity
  if ([string]$drops.decision_id -ne 'ECO-DROP-V2-001') {
    Add-Issue $script:errors 'invalid_economy_v2_drop_decision' 'economy-v2 drop data must be governed by ECO-DROP-V2-001.' "$path.drops_and_pity"
  }
  $expectedBundles = [ordered]@{
    'mountain_common' = 'CUR_GOLD:8|MAT_STRENGTHEN_SHARD:1'; 'mountain_elite' = 'CUR_GOLD:20|MAT_STRENGTHEN_SHARD:2'; 'mountain_major' = 'CUR_GOLD:32|MAT_STRENGTHEN_SHARD:3'; 'waterfall_common' = 'CUR_GOLD:10|MAT_STRENGTHEN_SHARD:1'; 'waterfall_elite' = 'CUR_GOLD:24|MAT_STRENGTHEN_SHARD:2'; 'public_boss' = 'CUR_GOLD:50|MAT_STRENGTHEN_SHARD:3'; 'peach_common' = 'CUR_GOLD:14|MAT_STRENGTHEN_SHARD:1'; 'peach_major' = 'CUR_GOLD:34|MAT_ADVANCE_HG:1'; 'cave_common' = 'CUR_GOLD:16|MAT_STRENGTHEN_SHARD:1'; 'cave_major' = 'CUR_GOLD:38|MAT_ADVANCE_HG:1'; 'sevenstar_common' = 'CUR_GOLD:18|MAT_STRENGTHEN_SHARD:2'; 'sevenstar_elite' = 'CUR_GOLD:28|MAT_ADVANCE_HG:1'; 'sevenstar_major' = 'CUR_GOLD:42|MAT_ADVANCE_HG:2'; 'optional_major' = 'CUR_GOLD:44|MAT_ARTIFACT_DUST:2'; 'eastsea_common' = 'CUR_GOLD:20|MAT_STRENGTHEN_SHARD:2'; 'eastsea_elite' = 'CUR_GOLD:32|MAT_ADVANCE_HG:1'; 'dragon_old' = 'CUR_GOLD:100|MAT_ARTIFACT_DUST:5'; 'dragon_reverse' = 'CUR_GOLD:120|MAT_ARTIFACT_DUST:6'; 'ox_raid' = 'CUR_GOLD:120|CUR_RAID_MARK:1|MAT_ADVANCE_HG:2'
  }
  $actualBundles = @{}
  foreach ($property in $drops.reward_bundles.PSObject.Properties) { $actualBundles[$property.Name] = Get-GrantSignature $property.Value }
  if ($actualBundles.Count -ne $expectedBundles.Count) { Add-Issue $script:errors 'invalid_economy_v2_bundle_count' 'economy-v2 must retain all 19 frozen reward bundles.' "$path.drops_and_pity.reward_bundles" }
  foreach ($key in $expectedBundles.Keys) {
    if (-not $actualBundles.ContainsKey($key) -or [string]$actualBundles[$key] -ne [string]$expectedBundles[$key]) { Add-Issue $script:errors 'invalid_economy_v2_bundle_value' "economy-v2 reward bundle $key does not match the frozen value." "$path.drops_and_pity.reward_bundles" }
  }
  $expectedProfiles = [ordered]@{'HG_DROP_MOUNTAIN_COMMON'='mountain_common'; 'HG_DROP_MOUNTAIN_ELITE'='mountain_elite'; 'HG_DROP_MOUNTAIN_MAJOR'='mountain_major'; 'HG_DROP_WATERFALL_COMMON'='waterfall_common'; 'HG_DROP_WATERFALL_ELITE'='waterfall_elite'; 'HG_DROP_MACAQUE_PUBLIC'='public_boss'; 'HG_DROP_PEACH_COMMON'='peach_common'; 'HG_DROP_PEACH_MAJOR'='peach_major'; 'HG_DROP_CAVE_COMMON'='cave_common'; 'HG_DROP_CAVE_MAJOR'='cave_major'; 'HG_DROP_SEVENSTAR_COMMON'='sevenstar_common'; 'HG_DROP_SEVENSTAR_ELITE'='sevenstar_elite'; 'HG_DROP_SEVENSTAR_MAJOR'='sevenstar_major'; 'HG_DROP_PENG_OPTIONAL'='optional_major'; 'HG_DROP_EASTSEA_COMMON'='eastsea_common'; 'HG_DROP_EASTSEA_ELITE'='eastsea_elite'; 'HG_DROP_JIAO_PUBLIC'='public_boss'; 'HG_DROP_SHARK_PUBLIC'='public_boss'; 'HG_DROP_DRAGON_OLD'='dragon_old'; 'HG_DROP_DRAGON_REVERSE'='dragon_reverse'; 'HG_DROP_OX_RAID'='ox_raid'}
  $profileMap = @{}
  foreach ($profile in (Get-Items $drops.profiles)) { $profileMap[[string]$profile.profile_key] = $profile }
  if ($profileMap.Count -ne $expectedProfiles.Count) { Add-Issue $script:errors 'invalid_economy_v2_profile_count' 'economy-v2 must retain the 21 frozen HG_DROP profiles.' "$path.drops_and_pity.profiles" }
  foreach ($key in $expectedProfiles.Keys) {
    if (-not $profileMap.ContainsKey($key) -or [string]$profileMap[$key].bundle -ne [string]$expectedProfiles[$key]) { Add-Issue $script:errors 'invalid_economy_v2_profile_bundle' "economy-v2 profile $key must map to its frozen bundle." "$path.drops_and_pity.profiles" }
  }
  if ([int]$profileMap['HG_DROP_MACAQUE_PUBLIC'].rare.chance_basis_points -ne 1000 -or [int]$profileMap['HG_DROP_MACAQUE_PUBLIC'].rare.guarantee_on_eligible_attempt -ne 5 -or [int]$profileMap['HG_DROP_OX_RAID'].rare.chance_basis_points -ne 800 -or [int]$profileMap['HG_DROP_OX_RAID'].rare.guarantee_on_eligible_attempt -ne 6) {
    Add-Issue $script:errors 'invalid_economy_v2_rare_profile_values' 'economy-v2 must retain the Macaque and Ox rare probability and pity thresholds.' "$path.drops_and_pity.profiles"
  }
  $expectedProfileScopes = @{'HG_DROP_MACAQUE_PUBLIC' = 'public_boss'; 'HG_DROP_JIAO_PUBLIC' = 'public_boss'; 'HG_DROP_SHARK_PUBLIC' = 'public_boss'; 'HG_DROP_OX_RAID' = 'team_raid'}
  foreach ($key in $expectedProfileScopes.Keys) {
    if ([string]$profileMap[$key].scope -ne [string]$expectedProfileScopes[$key]) { Add-Issue $script:errors 'invalid_economy_v2_profile_scope' "economy-v2 profile $key must retain its frozen public/team scope." "$path.drops_and_pity.profiles" }
  }
  $expectedFirstClear = @{
    'HG_DROP_MACAQUE_PUBLIC' = 'EQ_HG_WEAPON_T1|CUR_GOLD:90'; 'HG_DROP_JIAO_PUBLIC' = 'EQ_HG_ARMOR_T1|CUR_GOLD:90'; 'HG_DROP_SHARK_PUBLIC' = 'EQ_HG_RING_T1|CUR_GOLD:90'; 'HG_DROP_DRAGON_OLD' = 'ART_HG_TIDE_SEAL|MAT_ARTIFACT_DUST:8'; 'HG_DROP_OX_RAID' = 'EQ_HG_SET_GUARD_T1|CUR_RAID_MARK:2'
  }
  foreach ($key in $expectedFirstClear.Keys) {
    $first = $profileMap[$key].first_clear
    $actual = "{0}|{1}:{2}" -f [string]$first.key, [string]$first.duplicate_conversion.key, [string]$first.duplicate_conversion.amount
    if ($actual -ne [string]$expectedFirstClear[$key]) { Add-Issue $script:errors 'invalid_economy_v2_first_clear_projection' "economy-v2 first-clear projection for $key must retain its exact unique or duplicate conversion." "$path.drops_and_pity.profiles" }
  }
  if ([string]$profileMap['HG_DROP_MACAQUE_PUBLIC'].rare.key -ne 'EQ_HG_TRINKET_T1' -or [string]$profileMap['HG_DROP_MACAQUE_PUBLIC'].rare.duplicate_conversion.key -ne 'CUR_GOLD' -or [int]$profileMap['HG_DROP_MACAQUE_PUBLIC'].rare.duplicate_conversion.amount -ne 110 -or [string]$profileMap['HG_DROP_OX_RAID'].rare.key -ne 'ART_HG_FLAME_CORE' -or [string]$profileMap['HG_DROP_OX_RAID'].rare.duplicate_conversion.key -ne 'CUR_RAID_MARK' -or [int]$profileMap['HG_DROP_OX_RAID'].rare.duplicate_conversion.amount -ne 3) {
    Add-Issue $script:errors 'invalid_economy_v2_rare_projection' 'economy-v2 rare grants and duplicate conversions must retain their exact frozen projection.' "$path.drops_and_pity.profiles"
  }
  $pityMap = @{}
  foreach ($pool in (Get-Items $drops.pity_pools)) { $pityMap[[string]$pool.pity_pool_key] = $pool }
  if ($pityMap.Count -ne 2 -or -not $pityMap.ContainsKey('PITY_HG_PUBLIC_GEAR') -or -not $pityMap.ContainsKey('PITY_HG_RAID_ARTIFACT')) {
    Add-Issue $script:errors 'invalid_economy_v2_pity_pools' 'economy-v2 must retain its two independent pity pools.' "$path.drops_and_pity.pity_pools"
  } else {
    Assert-ExactStringArray -Actual $pityMap['PITY_HG_PUBLIC_GEAR'].eligible_profile_keys -Expected @('HG_DROP_MACAQUE_PUBLIC') -Code 'invalid_economy_v2_public_pity_membership' -Message 'The public pity pool may contain only Macaque rare eligibility.' -Path "$path.drops_and_pity.pity_pools"
    Assert-ExactStringArray -Actual $pityMap['PITY_HG_RAID_ARTIFACT'].eligible_profile_keys -Expected @('HG_DROP_OX_RAID') -Code 'invalid_economy_v2_raid_pity_membership' -Message 'The raid pity pool may contain only Ox raid rare eligibility.' -Path "$path.drops_and_pity.pity_pools"
  }
  if ([string]$drops.profile_settlement_contract.first_clear_version_rule -notmatch 'never resets' -or [string]$drops.profile_settlement_contract.pity_increment_boundary -notmatch 'Only a committed eligible rare miss') {
    Add-Issue $script:errors 'invalid_economy_v2_drop_settlement_contract' 'economy-v2 must freeze first-clear history and committed-eligible-miss pity behavior.' "$path.drops_and_pity.profile_settlement_contract"
  }
  $pityState = $drops.pity_state_contract
  Assert-ExactStringArray -Actual $pityState.state_identity -Expected @('owner_id', 'pity_pool_key') -Code 'invalid_economy_v2_pity_state_identity' -Message 'Pity state must be character-and-pool scoped.' -Path "$path.drops_and_pity.pity_state_contract"
  Assert-ExactStringArray -Actual $pityState.rare_roll_outcome_values -Expected @('miss', 'chance_success', 'pity_forced_success') -Code 'invalid_economy_v2_pity_roll_outcomes' -Message 'Pity must distinguish miss, chance success, and forced success.' -Path "$path.drops_and_pity.pity_state_contract"
  Assert-ExactStringArray -Actual $pityState.rare_grant_disposition_values -Expected @('not_applicable', 'granted', 'duplicate_conversion') -Code 'invalid_economy_v2_pity_grant_dispositions' -Message 'Pity must distinguish empty, granted, and duplicate-conversion rare outcomes.' -Path "$path.drops_and_pity.pity_state_contract"
  Assert-ExactStringArray -Actual $pityState.required_receipt_fields -Expected @('drop_roll_id', 'drop_roll_proof_ref', 'rare_roll_outcome', 'rare_grant_disposition', 'pity_before', 'pity_after') -Code 'invalid_economy_v2_pity_receipt_fields' -Message 'Pity outcomes must retain roll identity, proof, disposition, and counters.' -Path "$path.drops_and_pity.pity_state_contract"
  if ([int]$pityState.initial_counter -ne 0 -or [string]$pityState.counter_interpretation -notmatch 'guarantee_on_eligible_attempt - 1' -or [string]$pityState.resolution_order -notmatch 'pity_forced_success before any normal random roll' -or [string]$pityState.transitions.miss -notmatch 'pity_after = pity_before \+ 1' -or [string]$pityState.transitions.chance_success -notmatch 'pity_after = 0' -or [string]$pityState.transitions.pity_forced_success -notmatch 'pity_after = 0' -or [string]$pityState.transitions.zero_award_or_rejected -notmatch 'pity_after = pity_before' -or [string]$pityState.roll_proof_rule -notmatch 'immutable authoritative roll record') {
    Add-Issue $script:errors 'invalid_economy_v2_pity_state_contract' 'Pity must freeze its initial counter, forced-success ordering, transitions, and authoritative roll proof.' "$path.drops_and_pity.pity_state_contract"
  }
  $pityMigration = $pityState.migration_record_contract
  Assert-ExactStringArray -Actual $pityMigration.migration_identity -Expected @('migration_id', 'owner_id', 'source_pity_pool_key', 'target_pity_pool_key', 'source_resource_table_version', 'target_resource_table_version') -Code 'invalid_economy_v2_pity_migration_identity' -Message 'Pity migration must have an idempotent, owner-bound identity.' -Path "$path.drops_and_pity.pity_state_contract.migration_record_contract"
  Assert-ExactStringArray -Actual $pityMigration.required_fields -Expected @('migration_id', 'owner_id', 'source_pity_pool_key', 'target_pity_pool_key', 'source_resource_table_version', 'target_resource_table_version', 'pity_before', 'pity_after', 'authority_proof_ref', 'migration_plan_hash') -Code 'invalid_economy_v2_pity_migration_fields' -Message 'Pity migration must retain complete authority and counter evidence.' -Path "$path.drops_and_pity.pity_state_contract.migration_record_contract"
  if ([string]$pityMigration.rule -notmatch 'one-time authority-attested same-family transition' -or [string]$pityMigration.rule -notmatch 'cannot delete, recalculate, or reset') {
    Add-Issue $script:errors 'invalid_economy_v2_pity_migration_rule' 'Pity migration must be forward-only, idempotent, and non-destructive.' "$path.drops_and_pity.pity_state_contract.migration_record_contract"
  }

  $tower = $Table.tower_rewards
  if ([string]$tower.decision_id -ne 'ECO-TOWER-V2-001' -or [string]$tower.entry_rule -notmatch 'Lv55' -or [string]$tower.record_scope -ne 'character' -or [int]$tower.weekly_tower_token_cap -ne 15 -or [int]$tower.xp_award -ne 0 -or [string]$tower.pity_policy -ne 'none') {
    Add-Issue $script:errors 'invalid_economy_v2_tower_header' 'economy-v2 must retain the character Lv55 tower reward boundary, 15-token weekly cap, no XP, and no pity.' "$path.tower_rewards"
  }
  if ((Get-GrantSignature $tower.first_clear_awards) -ne 'CUR_TOWER_TOKEN:3|MAT_STRENGTHEN_SHARD:3' -or (Get-GrantSignature $tower.repeat_clear_awards) -ne 'CUR_TOWER_TOKEN:1|MAT_STRENGTHEN_SHARD:1' -or (Get-Items $tower.failure_or_exit_award).Count -ne 0) {
    Add-Issue $script:errors 'invalid_economy_v2_tower_awards' 'economy-v2 must retain the frozen first-clear/repeat tower awards and no failure award.' "$path.tower_rewards"
  }
  $towerQualification = $tower.qualification_policy
  Assert-ExactStringArray -Actual $towerQualification.required_snapshot_fields -Expected @('schema_version', 'policy_id', 'snapshot_id', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'completion_event_id', 'authority_proof_ref', 'members') -Code 'invalid_economy_v2_tower_qualification_snapshot' -Message 'Tower rewards must bind the frozen authoritative qualification snapshot.' -Path "$path.tower_rewards.qualification_policy"
  Assert-ExactStringArray -Actual $towerQualification.required_member_fields -Expected @('owner_id', 'entry_level', 'entry_qualified', 'joined_before_run_lock', 'present_at_authoritative_completion', 'actor_alive_at_authoritative_completion', 'contribution_attested', 'eligible') -Code 'invalid_economy_v2_tower_qualification_member' -Message 'Tower qualification snapshot must retain every member eligibility input.' -Path "$path.tower_rewards.qualification_policy"
  if ([string]$towerQualification.policy_id -ne 'TOWER_FIRST_CYCLE_QUALIFICATION_V1' -or [string]$towerQualification.eligibility -notmatch 'present_at_authoritative_completion' -or [string]$towerQualification.receipt_binding -notmatch 'receipt.event_id must equal completion_event_id' -or [string]$towerQualification.receipt_binding -notmatch 'receipt.encounter_instance_id must equal tower_run_id' -or [string]$tower.cooperative_rule -notmatch 'TOWER_FIRST_CYCLE_QUALIFICATION_V1') {
    Add-Issue $script:errors 'invalid_economy_v2_tower_qualification_policy' 'Tower rewards must use the canonical team qualification snapshot and receipt binding.' "$path.tower_rewards.qualification_policy"
  }
  Assert-ExactStringArray -Actual $tower.required_identity -Expected @('tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'owner_id', 'encounter_instance_id', 'event_id') -Code 'invalid_economy_v2_tower_identity' -Message 'economy-v2 tower settlements must retain their full authoritative identity with canonical tower_mode and encounter instance.' -Path "$path.tower_rewards.required_identity"
  Assert-ExactStringArray -Actual $tower.tower_mode_contract.allowed_values -Expected @('first_cycle') -Code 'invalid_economy_v2_tower_mode' -Message 'economy-v2 tower rewards must use canonical first_cycle tower_mode only.' -Path "$path.tower_rewards.tower_mode_contract"
  if ([string]$tower.tower_mode_contract.canonical_field -ne 'tower_mode' -or [string]$tower.tower_mode_contract.alias_policy -notmatch 'mode is forbidden') {
    Add-Issue $script:errors 'invalid_economy_v2_tower_mode_contract' 'Tower mode must not accept a mode alias or inferred alternative.' "$path.tower_rewards.tower_mode_contract"
  }
  Assert-ExactStringArray -Actual $tower.weekly_cap_policy.quota_identity -Expected @('owner_id', 'tower_week_bucket', 'CUR_TOWER_TOKEN') -Code 'invalid_economy_v2_tower_weekly_quota_identity' -Message 'Tower weekly quota must bind owner, Asia/Shanghai week bucket, and tower token.' -Path "$path.tower_rewards.weekly_cap_policy"
  Assert-ExactStringArray -Actual $tower.weekly_cap_policy.receipt_counter_fields -Expected @('tower_weekly_token_before', 'tower_weekly_token_after') -Code 'invalid_economy_v2_tower_weekly_quota_receipt_fields' -Message 'Tower receipts must retain weekly token counter before/after values.' -Path "$path.tower_rewards.weekly_cap_policy"
  if ([string]$tower.weekly_cap_policy.bucket -notmatch 'Asia/Shanghai ISO-8601' -or [string]$tower.weekly_cap_policy.award_application -ne 'all_or_nothing_by_award_plan' -or [string]$tower.weekly_cap_policy.partial_award -ne 'forbidden' -or [string]$tower.weekly_cap_policy.cap_reached_outcome -notmatch 'tower_weekly_token_before and tower_weekly_token_after must be equal' -or [string]$tower.weekly_cap_policy.concurrency_rule -notmatch 'serializable transaction or compare-and-swap') {
    Add-Issue $script:errors 'invalid_economy_v2_tower_cap_policy' 'economy-v2 must freeze the Asia/Shanghai weekly bucket and all-or-nothing tower cap behavior.' "$path.tower_rewards.weekly_cap_policy"
  }
  $towerAwardClass = $tower.receipt_award_class_contract
  Assert-ExactStringArray -Actual $towerAwardClass.allowed_values -Expected @('first_clear', 'repeat_clear') -Code 'invalid_economy_v2_tower_award_class' -Message 'Tower receipt award classes must distinguish first_clear from repeat_clear.' -Path "$path.tower_rewards.receipt_award_class_contract"
  $towerAwardMappings = Get-Items $towerAwardClass.award_mapping
  if ([string]$towerAwardClass.field -ne 'tower_award_class' -or $towerAwardMappings.Count -ne 2 -or [string]$towerAwardMappings[0].tower_award_class -ne 'first_clear' -or [string]$towerAwardMappings[0].award_source -ne 'tower_rewards.first_clear_awards' -or [string]$towerAwardMappings[1].tower_award_class -ne 'repeat_clear' -or [string]$towerAwardMappings[1].award_source -ne 'tower_rewards.repeat_clear_awards' -or [string]$towerAwardClass.zero_award_rule -notmatch 'must not consume a first-clear history entry') {
    Add-Issue $script:errors 'invalid_economy_v2_tower_award_projection' 'Tower receipts must bind award class to the frozen award table and preserve first-clear state on zero award.' "$path.tower_rewards.receipt_award_class_contract"
  }

  $receipt = $Table.persistent_receipt_contract
  if ([string]$receipt.decision_id -ne 'ECO-LEDGER-V2-001' -or [int]$receipt.schema_version -ne 1 -or [string]$receipt.owner_scope -ne 'character') {
    Add-Issue $script:errors 'invalid_economy_v2_receipt_header' 'economy-v2 must retain its character receipt contract v1.' "$path.persistent_receipt_contract"
  }
  Assert-ExactStringArray -Actual $receipt.semantic_dedupe_identity -Expected @('owner_scope', 'owner_id', 'encounter_instance_id', 'event_id', 'source_profile', 'reward_slot_key') -Code 'invalid_economy_v2_receipt_identity' -Message 'economy-v2 receipt identity must include encounter instance and exclude resource-table version.' -Path "$path.persistent_receipt_contract.semantic_dedupe_identity"
  $requiredReceiptFields = @('schema_version', 'resource_table_version', 'owner_scope', 'owner_id', 'event_id', 'event_type', 'source_profile', 'reward_slot_key', 'encounter_instance_id', 'qualification_snapshot_id', 'p1_policy_id', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint', 'first_clear_disposition', 'rare_roll_outcome', 'rare_grant_disposition', 'xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after', 'balance_delta', 'material_delta', 'unique_grants', 'pity_before', 'pity_after', 'award_plan_hash', 'authority_proof_ref', 'receipt_id', 'commit_state', 'award_outcome')
  Assert-ExactStringArray -Actual $receipt.required_record_fields -Expected $requiredReceiptFields -Code 'invalid_economy_v2_receipt_fields' -Message 'economy-v2 must retain the complete persistent receipt envelope.' -Path "$path.persistent_receipt_contract.required_record_fields"
  Assert-ExactStringArray -Actual $receipt.global_required_non_null -Expected @('schema_version', 'resource_table_version', 'owner_scope', 'owner_id', 'event_id', 'event_type', 'source_profile', 'reward_slot_key', 'encounter_instance_id', 'balance_delta', 'material_delta', 'unique_grants', 'award_plan_hash', 'authority_proof_ref', 'receipt_id', 'commit_state', 'award_outcome') -Code 'invalid_economy_v2_global_receipt_envelope' -Message 'Every receipt must carry the authoritative non-null envelope, including encounter instance and proof.' -Path "$path.persistent_receipt_contract.global_required_non_null"
  if ([int]$receipt.global_fixed_values.schema_version -ne 1 -or [string]$receipt.global_fixed_values.resource_table_version -ne 'economy-v2' -or [string]$receipt.global_fixed_values.owner_scope -ne 'character') {
    Add-Issue $script:errors 'invalid_economy_v2_global_receipt_values' 'Every receipt must freeze schema version, resource table version, and character owner scope.' "$path.persistent_receipt_contract.global_fixed_values"
  }
  Assert-ExactStringArray -Actual $receipt.commit_states -Expected @('committed', 'rejected') -Code 'invalid_economy_v2_receipt_states' -Message 'economy-v2 must persist terminal receipt states only.' -Path "$path.persistent_receipt_contract.commit_states"
  Assert-ExactStringArray -Actual $receipt.award_outcomes -Expected @('awarded', 'weekly_token_cap_reached', 'balance_or_stack_cap_reached', 'rejected') -Code 'invalid_economy_v2_receipt_outcomes' -Message 'economy-v2 must retain the defined award outcomes.' -Path "$path.persistent_receipt_contract.award_outcomes"
  $ownerResolution = $receipt.owner_resolution_contract
  Assert-ExactStringArray -Actual $ownerResolution.authority_mapping_inputs -Expected @('actor_id', 'lifecycle_id', 'authority_proof_ref') -Code 'invalid_economy_v2_owner_resolution_inputs' -Message 'Receipt owner resolution must be authority-backed by actor, lifecycle, and proof inputs.' -Path "$path.persistent_receipt_contract.owner_resolution_contract"
  Assert-ExactStringArray -Actual $ownerResolution.forbidden_inputs -Expected @('client_supplied_owner_id', 'raw_actor_id_as_owner_id', 'raw_lifecycle_id_as_owner_id') -Code 'invalid_economy_v2_owner_resolution_forbidden_inputs' -Message 'Receipt owner resolution must reject client, raw actor, and raw lifecycle owner substitutions.' -Path "$path.persistent_receipt_contract.owner_resolution_contract"
  if ([string]$ownerResolution.owner_id_rule -notmatch 'stable character owner' -or [string]$ownerResolution.required_mapping_result -ne 'resolved_owner_id_equals_receipt_owner_id' -or [string]$ownerResolution.failure_outcome -ne 'rejected') {
    Add-Issue $script:errors 'invalid_economy_v2_owner_resolution' 'Receipt owner_id must resolve to the stable authoritative character owner.' "$path.persistent_receipt_contract.owner_resolution_contract"
  }
  $stateContract = $receipt.receipt_state_contract
  Assert-ExactStringArray -Actual $stateContract.first_clear_disposition_values -Expected @('first_clear_granted', 'duplicate_conversion', 'not_consumed_zero_award') -Code 'invalid_economy_v2_first_clear_dispositions' -Message 'First-clear disposition values must be explicitly frozen.' -Path "$path.persistent_receipt_contract.receipt_state_contract"
  $stateRows = Get-Items $stateContract.state_outcome_matrix
  if ($stateRows.Count -ne 4 -or [string]$stateRows[0].commit_state -ne 'committed' -or [string]$stateRows[0].award_outcome -ne 'awarded' -or [string]$stateRows[1].award_outcome -ne 'weekly_token_cap_reached' -or -not (Test-StrictBoolean $stateRows[1].zero_award $true) -or [string]$stateRows[2].award_outcome -ne 'balance_or_stack_cap_reached' -or -not (Test-StrictBoolean $stateRows[2].zero_award $true) -or [string]$stateRows[3].commit_state -ne 'rejected' -or [string]$stateRows[3].award_outcome -ne 'rejected' -or -not (Test-StrictBoolean $stateRows[3].no_state_mutation $true) -or [string]$stateContract.zero_award_projection_rule -notmatch 'no first-clear, pity, repeat-quota, or tower-weekly-quota mutation') {
    Add-Issue $script:errors 'invalid_economy_v2_receipt_state_matrix' 'Receipt terminal states and zero-award effects must be explicitly constrained.' "$path.persistent_receipt_contract.receipt_state_contract"
  }
  $canonical = $receipt.canonical_receipt_field_contract
  $expectedSourceProfileValues = [ordered]@{
    'experience' = @('XP_INTRO', 'XP_MOUNTAIN', 'XP_WATERFALL', 'XP_MACAQUE', 'XP_PEACH', 'XP_CAVE', 'XP_SEVENSTAR', 'XP_PENG', 'XP_EASTSEA', 'XP_JIAO', 'XP_SHARK', 'XP_CHAPTER_CLEAR')
    'drop_bundle' = @('HG_DROP_MOUNTAIN_COMMON', 'HG_DROP_MOUNTAIN_ELITE', 'HG_DROP_MOUNTAIN_MAJOR', 'HG_DROP_WATERFALL_COMMON', 'HG_DROP_WATERFALL_ELITE', 'HG_DROP_PEACH_COMMON', 'HG_DROP_PEACH_MAJOR', 'HG_DROP_CAVE_COMMON', 'HG_DROP_CAVE_MAJOR', 'HG_DROP_SEVENSTAR_COMMON', 'HG_DROP_SEVENSTAR_ELITE', 'HG_DROP_SEVENSTAR_MAJOR', 'HG_DROP_PENG_OPTIONAL', 'HG_DROP_EASTSEA_COMMON', 'HG_DROP_EASTSEA_ELITE', 'HG_DROP_DRAGON_OLD', 'HG_DROP_DRAGON_REVERSE', 'HG_DROP_OX_RAID')
    'first_clear_grant' = @('HG_DROP_MACAQUE_PUBLIC', 'HG_DROP_JIAO_PUBLIC', 'HG_DROP_SHARK_PUBLIC', 'HG_DROP_DRAGON_OLD', 'HG_DROP_OX_RAID')
    'participation_chest' = @('HG_DROP_MACAQUE_PUBLIC', 'HG_DROP_JIAO_PUBLIC', 'HG_DROP_SHARK_PUBLIC')
    'public_rare_drop' = @('HG_DROP_MACAQUE_PUBLIC')
    'team_raid_rare_drop' = @('HG_DROP_OX_RAID')
  }
  foreach ($eventType in $expectedSourceProfileValues.Keys) {
    $sourceRule = $canonical.source_profile_by_event_type.PSObject.Properties[$eventType].Value
    if ($null -eq $sourceRule) {
      Add-Issue $script:errors 'missing_economy_v2_source_profile_rule' "economy-v2 is missing a canonical source_profile rule for $eventType." "$path.persistent_receipt_contract.canonical_receipt_field_contract"
    } else {
      Assert-ExactStringArray -Actual $sourceRule.allowed_values -Expected $expectedSourceProfileValues[$eventType] -Code 'invalid_economy_v2_source_profile_values' -Message "economy-v2 must freeze canonical source_profile values for $eventType." -Path "$path.persistent_receipt_contract.canonical_receipt_field_contract"
      if ([string]$sourceRule.field_rule -notmatch 'source_profile equals') {
        Add-Issue $script:errors 'invalid_economy_v2_source_profile_rule' "economy-v2 must prohibit source_profile aliases for $eventType." "$path.persistent_receipt_contract.canonical_receipt_field_contract"
      }
    }
  }
  $towerSourceRule = $canonical.source_profile_by_event_type.PSObject.Properties['tower_reward'].Value
  if ($null -eq $towerSourceRule -or [string]$towerSourceRule.required_value -ne 'TOWER_FIRST_CYCLE_REWARD_V1') {
    Add-Issue $script:errors 'invalid_economy_v2_fixed_source_profile' 'economy-v2 must freeze the tower reward source_profile.' "$path.persistent_receipt_contract.canonical_receipt_field_contract"
  }
  $expectedSlots = [ordered]@{'experience'='xp_grant'; 'drop_bundle'='base_bundle'; 'first_clear_grant'='first_clear'; 'participation_chest'='participation_chest'; 'public_rare_drop'='rare_drop'; 'team_raid_rare_drop'='rare_drop'; 'tower_reward'='tower_cycle_reward'}
  foreach ($eventType in $expectedSlots.Keys) {
    if ([string]$canonical.reward_slot_key_by_event_type.PSObject.Properties[$eventType].Value -ne [string]$expectedSlots[$eventType]) {
      Add-Issue $script:errors 'invalid_economy_v2_reward_slot_key' "economy-v2 must freeze reward_slot_key for $eventType." "$path.persistent_receipt_contract.canonical_receipt_field_contract"
    }
  }
  Assert-ExactStringArray -Actual $canonical.tower_mode.forbidden_aliases -Expected @('mode', 'first-cycle', 'FIRST_CYCLE') -Code 'invalid_economy_v2_receipt_tower_mode_aliases' -Message 'Receipt tower_mode must reject aliases.' -Path "$path.persistent_receipt_contract.canonical_receipt_field_contract"
  if ([string]$canonical.comparison -notmatch 'case-sensitive ASCII' -or [string]$canonical.tower_mode.canonical_field -ne 'tower_mode' -or [string]$canonical.tower_mode.required_value -ne 'first_cycle') {
    Add-Issue $script:errors 'invalid_economy_v2_receipt_canonical_fields' 'economy-v2 must freeze case-sensitive canonical receipt field values.' "$path.persistent_receipt_contract.canonical_receipt_field_contract"
  }
  $resolution = $receipt.transactional_resolution_contract
  if ([string]$resolution.persistent_prepared_state -ne 'forbidden' -or [string]$resolution.lock_and_plan -notmatch 'only after those locks are held' -or [string]$resolution.commit -notmatch 'terminal committed receipt' -or [string]$resolution.retry -notmatch 'same immutable authoritative inputs' -or (Has-Prop $receipt 'prepared_resolution_contract')) {
    Add-Issue $script:errors 'invalid_economy_v2_receipt_transactional_resolution' 'Receipt resolution must have no persistent prepared state and must lock before resolving a terminal plan.' "$path.persistent_receipt_contract.transactional_resolution_contract"
  }
  if ([string]$receipt.encounter_identity_rule -notmatch 'required for every receipt type' -or [string]$receipt.replay_rule -notmatch 'terminal committed or rejected' -or [string]$receipt.replay_rule -notmatch 'different resource_table_version' -or [string]$receipt.cross_version_origin_rule -notmatch 'terminal conflict' -or [string]$receipt.public_rare_participation_chest_binding_rule -notmatch 'same binding is mandatory for public first_clear_grant' -or [string]$receipt.team_raid_event_binding_rule -notmatch 'every HG_DROP_OX_RAID' -or [string]$receipt.team_raid_event_binding_rule -notmatch 'completion_event_id' -or [string]$receipt.zero_award_pity_rule -notmatch 'pity_before equal to pity_after' -or [string]$receipt.atomicity_rule -notmatch 'serializable transaction' -or [string]$receipt.proof_rule -notmatch 'owner-resolution mapping' -or [string]$receipt.proof_rule -notmatch 'drop_roll_proof_ref') {
    Add-Issue $script:errors 'invalid_economy_v2_receipt_replay_contract' 'economy-v2 must protect instance-scoped events, terminal replay, public/team binding, zero-award pity, owner resolution, roll proof, and atomicity.' "$path.persistent_receipt_contract"
  }
  $conditionalRuleMap = @{}
  foreach ($rule in (Get-Items $receipt.conditional_field_rules)) { $conditionalRuleMap[[string]$rule.event_type] = $rule }
  foreach ($eventType in @('experience', 'drop_bundle', 'first_clear_grant', 'participation_chest', 'public_rare_drop', 'team_raid_rare_drop', 'tower_reward')) {
    if (-not $conditionalRuleMap.ContainsKey($eventType)) { Add-Issue $script:errors 'missing_economy_v2_receipt_event_type' "economy-v2 receipt contract is missing event_type rule: $eventType." "$path.persistent_receipt_contract.conditional_field_rules" }
  }
  $expectedRequiredNonNull = [ordered]@{
    'experience' = @('source_profile', 'reward_slot_key', 'encounter_instance_id', 'xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta')
    'drop_bundle' = @('source_profile', 'reward_slot_key', 'encounter_instance_id')
    'first_clear_grant' = @('source_profile', 'reward_slot_key', 'encounter_instance_id', 'first_clear_disposition')
    'participation_chest' = @('source_profile', 'reward_slot_key', 'encounter_instance_id', 'qualification_snapshot_id', 'p1_policy_id')
    'public_rare_drop' = @('source_profile', 'reward_slot_key', 'encounter_instance_id', 'qualification_snapshot_id', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'pity_before', 'pity_after', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint', 'rare_roll_outcome', 'rare_grant_disposition')
    'team_raid_rare_drop' = @('source_profile', 'reward_slot_key', 'encounter_instance_id', 'qualification_snapshot_id', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'pity_before', 'pity_after', 'rare_roll_outcome', 'rare_grant_disposition')
    'tower_reward' = @('source_profile', 'reward_slot_key', 'encounter_instance_id', 'qualification_snapshot_id', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after')
  }
  $expectedRequiredNull = [ordered]@{
    'experience' = @('p1_policy_id', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint', 'first_clear_disposition', 'rare_roll_outcome', 'rare_grant_disposition', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after', 'pity_before', 'pity_after')
    'drop_bundle' = @('p1_policy_id', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'pity_before', 'pity_after', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint', 'first_clear_disposition', 'rare_roll_outcome', 'rare_grant_disposition', 'xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after')
    'first_clear_grant' = @('p1_policy_id', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'pity_before', 'pity_after', 'rare_roll_outcome', 'rare_grant_disposition', 'xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after')
    'participation_chest' = @('xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'pity_before', 'pity_after', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint', 'first_clear_disposition', 'rare_roll_outcome', 'rare_grant_disposition', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after')
    'public_rare_drop' = @('p1_policy_id', 'xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta', 'first_clear_disposition', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after')
    'team_raid_rare_drop' = @('p1_policy_id', 'xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint', 'first_clear_disposition', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after')
    'tower_reward' = @('p1_policy_id', 'xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'pity_before', 'pity_after', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint', 'first_clear_disposition', 'rare_roll_outcome', 'rare_grant_disposition')
  }
  foreach ($eventType in $expectedRequiredNonNull.Keys) {
    if ($conditionalRuleMap.ContainsKey($eventType)) {
      Assert-ExactStringArray -Actual $conditionalRuleMap[$eventType].required_non_null -Expected $expectedRequiredNonNull[$eventType] -Code 'invalid_economy_v2_receipt_required_non_null' -Message "economy-v2 must freeze required non-null fields for $eventType." -Path "$path.persistent_receipt_contract.conditional_field_rules"
      Assert-ExactStringArray -Actual $conditionalRuleMap[$eventType].required_null -Expected $expectedRequiredNull[$eventType] -Code 'invalid_economy_v2_receipt_required_null' -Message "economy-v2 must freeze required null fields for $eventType." -Path "$path.persistent_receipt_contract.conditional_field_rules"
    }
  }
  $profileBindingRules = Get-Items $receipt.receipt_profile_binding_rules
  if ($profileBindingRules.Count -ne 4) {
    Add-Issue $script:errors 'invalid_economy_v2_profile_binding_rule_count' 'economy-v2 must declare exactly four profile-scoped receipt binding rules.' "$path.persistent_receipt_contract.receipt_profile_binding_rules"
  } else {
    $bindingMap = @{}
    foreach ($rule in $profileBindingRules) { $bindingMap[[string]$rule.rule_id] = $rule }
    $publicRule = $bindingMap['PUBLIC_PROFILE_CHEST_BINDING_V2']
    $oxRule = $bindingMap['OX_TEAM_RAID_SNAPSHOT_BINDING_V2']
    $ordinaryDropRule = $bindingMap['ORDINARY_DROP_NO_SNAPSHOT_V2']
    $ordinaryFirstRule = $bindingMap['ORDINARY_FIRST_CLEAR_NO_SNAPSHOT_V2']
    if ($null -eq $publicRule -or $null -eq $oxRule -or $null -eq $ordinaryDropRule -or $null -eq $ordinaryFirstRule) {
      Add-Issue $script:errors 'missing_economy_v2_profile_binding_rule' 'economy-v2 must retain public, Ox team-raid, ordinary drop, and ordinary first-clear binding rules.' "$path.persistent_receipt_contract.receipt_profile_binding_rules"
    } else {
      Assert-ExactStringArray -Actual $publicRule.event_types -Expected @('first_clear_grant', 'public_rare_drop') -Code 'invalid_economy_v2_public_binding_events' -Message 'Public follow-up rewards must bind a participation chest.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      Assert-ExactStringArray -Actual $publicRule.source_profiles -Expected @('HG_DROP_MACAQUE_PUBLIC', 'HG_DROP_JIAO_PUBLIC', 'HG_DROP_SHARK_PUBLIC') -Code 'invalid_economy_v2_public_binding_profiles' -Message 'Public binding must cover exactly the three public profiles.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      Assert-ExactStringArray -Actual $publicRule.required_non_null -Expected @('qualification_snapshot_id', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint') -Code 'invalid_economy_v2_public_binding_fields' -Message 'Public first-clear and rare receipts must persist the chest binding fields.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      Assert-ExactStringArray -Actual $publicRule.bound_receipt.equality_fields -Expected @('owner_id', 'event_id', 'encounter_instance_id', 'qualification_snapshot_id', 'source_profile', 'resource_table_version') -Code 'invalid_economy_v2_public_binding_identity' -Message 'Public follow-up rewards must bind the exact qualified chest identity.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      if ([string]$publicRule.bound_receipt.event_type -ne 'participation_chest' -or [string]$publicRule.bound_receipt.commit_state -ne 'committed' -or [string]$publicRule.bound_receipt.p1_policy_id -ne 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION' -or [string]$publicRule.failure_outcome -ne 'rejected') {
        Add-Issue $script:errors 'invalid_economy_v2_public_binding_contract' 'Public follow-up rewards must bind a committed P1 participation chest and reject drift.' "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      }
      Assert-ExactStringArray -Actual $oxRule.event_types -Expected @('drop_bundle', 'first_clear_grant', 'team_raid_rare_drop') -Code 'invalid_economy_v2_ox_binding_events' -Message 'Ox team-raid base, first-clear, and rare rewards must all bind the team snapshot.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      Assert-ExactStringArray -Actual $oxRule.source_profiles -Expected @('HG_DROP_OX_RAID') -Code 'invalid_economy_v2_ox_binding_profile' -Message 'Ox binding must cover only HG_DROP_OX_RAID.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      Assert-ExactStringArray -Actual $oxRule.required_non_null -Expected @('qualification_snapshot_id') -Code 'invalid_economy_v2_ox_binding_fields' -Message 'Ox rewards must carry the team qualification snapshot.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      Assert-ExactStringArray -Actual $oxRule.required_null -Expected @('p1_policy_id', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint') -Code 'invalid_economy_v2_ox_binding_nulls' -Message 'Ox team-raid rewards must not inherit public chest fields.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      Assert-ExactStringArray -Actual $oxRule.snapshot_equality_fields -Expected @('owner_id', 'event_id=completion_event_id', 'encounter_instance_id=raid_instance_id', 'source_profile=profile_key') -Code 'invalid_economy_v2_ox_snapshot_equalities' -Message 'Ox rewards must bind the owner, completion event, raid instance, and canonical source profile.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      if ([string]$oxRule.snapshot_policy_id -ne 'TEAM_RAID_RARE_ELIGIBILITY_V1' -or [string]$oxRule.snapshot_member_rule -notmatch 'rare_clear_attested is additionally required only for team_raid_rare_drop' -or [string]$oxRule.failure_outcome -ne 'rejected') {
        Add-Issue $script:errors 'invalid_economy_v2_ox_binding_contract' 'Ox rewards must bind the correct team snapshot member, completion event, and raid instance.' "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      }
      Assert-ExactStringArray -Actual $ordinaryFirstRule.source_profiles -Expected @('HG_DROP_DRAGON_OLD') -Code 'invalid_economy_v2_ordinary_first_clear_profile' -Message 'Only Dragon Old has an ordinary first-clear rule in economy-v2.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      Assert-ExactStringArray -Actual $ordinaryFirstRule.required_null -Expected @('qualification_snapshot_id', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint') -Code 'invalid_economy_v2_ordinary_first_clear_nulls' -Message 'Ordinary first-clear rewards must not carry public/team qualification artifacts.' -Path "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      if ((Get-Items $ordinaryDropRule.source_profiles).Count -ne 17 -or [string]$ordinaryDropRule.failure_outcome -ne 'rejected' -or [string]$ordinaryFirstRule.failure_outcome -ne 'rejected') {
        Add-Issue $script:errors 'invalid_economy_v2_ordinary_profile_binding' 'Ordinary drop profiles must reject unexpected snapshot or chest fields.' "$path.persistent_receipt_contract.receipt_profile_binding_rules"
      }
    }
  }
  $awardDerivation = $receipt.award_plan_derivation_contract
  $derivations = Get-Items $awardDerivation.event_type_derivations
  if ([string]$awardDerivation.derivation_id -ne 'ECO_AWARD_PLAN_DERIVATION_V2' -or [string]$awardDerivation.common_rule -notmatch 'non-negative exact projections' -or $derivations.Count -ne 7 -or [string]$awardDerivation.hash_rule -notmatch 'resolved derivation_id') {
    Add-Issue $script:errors 'invalid_economy_v2_award_plan_derivation' 'economy-v2 must bind every award plan to one exact frozen source and projection.' "$path.persistent_receipt_contract.award_plan_derivation_contract"
  } else {
    $derivationMap = @{}
    foreach ($rule in $derivations) { $derivationMap[[string]$rule.event_type] = $rule }
    foreach ($eventType in @('experience', 'drop_bundle', 'participation_chest', 'first_clear_grant', 'public_rare_drop', 'team_raid_rare_drop', 'tower_reward')) {
      if (-not $derivationMap.ContainsKey($eventType)) { Add-Issue $script:errors 'missing_economy_v2_award_derivation_event' "economy-v2 has no award derivation for $eventType." "$path.persistent_receipt_contract.award_plan_derivation_contract" }
    }
    if ([string]$derivationMap['drop_bundle'].projection -notmatch 'exact_full_bundle_only' -or [string]$derivationMap['participation_chest'].projection -notmatch 'exact_public_boss_bundle_only' -or [string]$derivationMap['first_clear_grant'].projection -notmatch 'exact_unique_grant_or_its_frozen_duplicate_conversion_only' -or [string]$derivationMap['public_rare_drop'].projection -notmatch 'exact_rare_unique_grant_or_its_frozen_duplicate_conversion_only' -or [string]$derivationMap['team_raid_rare_drop'].projection -notmatch 'exact_rare_unique_grant_or_its_frozen_duplicate_conversion_only' -or [string]$derivationMap['tower_reward'].projection -notmatch 'tower_award_class maps exactly') {
      Add-Issue $script:errors 'invalid_economy_v2_award_derivation_projection' 'economy-v2 must forbid non-table reward amounts, partial bundles, and unbound tower awards.' "$path.persistent_receipt_contract.award_plan_derivation_contract"
    }
  }
  if ([string]$receipt.profile_scope_receipt_rule -notmatch 'drop_bundle excludes all public profiles' -or [string]$receipt.public_chest_profile_binding_rule -notmatch 'p1_policy_id=P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION') {
    Add-Issue $script:errors 'invalid_economy_v2_public_chest_profile_binding' 'economy-v2 must make P1 chest the only public base-bundle path and bind public follow-up rewards.' "$path.persistent_receipt_contract"
  }
  if ([string]$receipt.hash_contract.resource_table_file_hash -notmatch 'SHA-256' -or [string]$receipt.hash_contract.award_plan_hash -notmatch 'RFC 8785' -or [string]$receipt.hash_contract.award_plan_hash -notmatch 'experience_delta' -or [string]$receipt.hash_contract.award_plan_hash -notmatch 'rare-roll proof' -or [string]$receipt.hash_contract.award_plan_hash -notmatch 'tower award class and weekly counter before/after') {
    Add-Issue $script:errors 'invalid_economy_v2_hash_contract' 'economy-v2 must freeze SHA-256 resource-table hashing and RFC 8785 award-plan hashing over all hardened derivation inputs.' "$path.persistent_receipt_contract.hash_contract"
  }
  $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:Root $path)
  if ($raw -match '(?i)"y3_id"\s*:') { Add-Issue $script:errors 'y3_id_not_allowed' 'economy-v2 may not contain Y3 object IDs.' $path }
}

function Test-EconomyV3RouteOverlay {
  param($Overlay, $Register)

  $path = 'tables/economy-v3-resource-table.json'
  if ($null -eq $Overlay) { return }

  if ([string]$Overlay.table -ne 'economy-v3-resource-table-overlay' -or [string]$Overlay.resource_table_version -ne 'economy-v3' -or [string]$Overlay.kind -ne 'versioned_delta_overlay') {
    Add-Issue $script:errors 'invalid_economy_v3_identity' 'economy-v3 must be an explicit versioned route overlay.' $path
  }
  if ([string]$Overlay.decision_id -ne 'ECO-XP-ROUTE-V3-001' -or [string]$Overlay.decision_status -ne 'accepted-baseline' -or [string]$Overlay.package_status -ne 'offline-design-only-runtime-not-integrated' -or -not (Test-StrictBoolean $Overlay.runtime_handoff $false) -or [string]$Overlay.production_gate -ne 'closed') {
    Add-Issue $script:errors 'invalid_economy_v3_status' 'economy-v3 must be an accepted, runtime-closed future-route overlay.' $path
  }
  if ([string]$Overlay.inherits.resource_table_version -ne 'economy-v2' -or [string]$Overlay.inherits.path -ne 'tables/economy-v2-resource-table.json') {
    Add-Issue $script:errors 'invalid_economy_v3_inheritance' 'economy-v3 must explicitly inherit economy-v2.' $path
  } else {
    $baseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $script:Root 'tables/economy-v2-resource-table.json')).Hash
    if ($baseHash -ine [string]$Overlay.inherits.content_hash_sha256) {
      Add-Issue $script:errors 'economy_v3_base_hash_mismatch' 'economy-v3 must bind the exact economy-v2 base-table hash.' $path
    }
  }

  $overrideMap = @{}
  foreach ($row in @(Get-Items $Overlay.progression_delta.row_overrides)) { $overrideMap[[string]$row.source_key] = $row }
  if ($overrideMap.Count -ne 2 -or $null -eq $overrideMap['XP_EASTSEA'] -or $null -eq $overrideMap['XP_CHAPTER_CLEAR'] -or [int]$overrideMap['XP_EASTSEA'].base_xp -ne 1490 -or [int]$overrideMap['XP_EASTSEA'].replaces_economy_v2_base_xp -ne 900 -or [int]$overrideMap['XP_CHAPTER_CLEAR'].base_xp -ne 1145 -or [int]$overrideMap['XP_CHAPTER_CLEAR'].replaces_economy_v2_base_xp -ne 1735) {
    Add-Issue $script:errors 'invalid_economy_v3_xp_overrides' 'economy-v3 may override only the two reviewed Huaguoshan XP rows.' $path
  }
  $newRows = @(Get-Items $Overlay.progression_delta.new_design_route_rows)
  if ($newRows.Count -ne 1 -or [string]$newRows[0].source_key -ne 'XP_HG_CRACK_DISCOVERY' -or [int]$newRows[0].base_xp -ne 500 -or $null -ne $newRows[0].runtime_mapping) {
    Add-Issue $script:errors 'invalid_economy_v3_crack_row' 'economy-v3 must contain one non-runtime 500 XP crack-discovery route row.' $path
  }
  $semanticBindingMap = @{}
  foreach ($binding in @(Get-Items $Overlay.progression_delta.future_route_semantic_bindings)) { $semanticBindingMap[[string]$binding.source_key] = $binding }
  $expectedSemanticBindings = @{
    'XP_PEACH' = @{ historical_kind = 'side_quest'; node_id = 'HG_PEACH_GROVE_PUBLIC_MAINLINE'; node_name = '桃林公共主路线' }
    'XP_CAVE' = @{ historical_kind = 'solo_instance'; node_id = 'HG_BAT_CAVE_PUBLIC_MAINLINE'; node_name = '蝙蝠窟公共主路线' }
  }
  if ($semanticBindingMap.Count -ne 2 -or $null -eq $semanticBindingMap['XP_PEACH'] -or $null -eq $semanticBindingMap['XP_CAVE']) {
    Add-Issue $script:errors 'invalid_economy_v3_route_semantic_binding_set' 'economy-v3 must bind exactly XP_PEACH and XP_CAVE to the reviewed future public-mainline semantics.' $path
  }
  foreach ($sourceKey in $expectedSemanticBindings.Keys) {
    $binding = $semanticBindingMap[$sourceKey]
    $expected = $expectedSemanticBindings[$sourceKey]
    if ($null -eq $binding -or [string]$binding.historical_economy_v2_source_kind -ne [string]$expected.historical_kind -or [string]$binding.future_route_node_id -ne [string]$expected.node_id -or [string]$binding.future_route_node_name -ne [string]$expected.node_name -or [string]$binding.future_route_semantics -ne 'mandatory_public_mainline' -or -not (Test-StrictBoolean $binding.required_for_regular_mainline_closure $true) -or -not (Test-StrictBoolean $binding.creates_solo_instance $false) -or -not (Test-StrictBoolean $binding.is_optional_content $false) -or $null -ne $binding.source_profile_mapping -or $null -ne $binding.runtime_mapping -or -not (Test-StrictBoolean $binding.historical_receipt_mutation $false)) {
      Add-Issue $script:errors 'invalid_economy_v3_route_semantic_binding' "economy-v3 future semantic binding for $sourceKey must preserve its historic kind while declaring only a non-runtime mandatory public-mainline route node." $path
      continue
    }
    $forbiddenSubstitutes = @($binding.forbidden_substitutes | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedSubstitutes = @('HG_E_DRAGON_OLD_TIDE', 'team_instance', 'rare_award', 'tower' | Sort-Object -Unique)
    if ((Compare-Object -ReferenceObject $expectedSubstitutes -DifferenceObject $forbiddenSubstitutes).Count -ne 0) {
      Add-Issue $script:errors 'invalid_economy_v3_route_semantic_substitutes' "economy-v3 future semantic binding for $sourceKey must reject Dragon Old Tide, team, rare, and tower substitutes." $path
    }
  }
  $choice = $Overlay.progression_delta.route_choice
  if ([string]$choice.choice_id -ne 'HG_ROUTE_PENG_OR_CRACK_V3' -or [int]$choice.selection_cardinality.minimum -ne 1 -or [int]$choice.selection_cardinality.maximum -ne 1 -or @(Get-Items $choice.anti_double_claim.prohibited_source_key_pairs).Count -ne 1 -or [string]$choice.no_boss_path_rule -notmatch 'must remain available without defeating Peng Demon King') {
    Add-Issue $script:errors 'invalid_economy_v3_route_choice' 'economy-v3 must freeze the exact one-of-two Peng-or-crack route and anti-double-claim boundary.' $path
  }
  $math = $Overlay.progression_delta.route_math
  if ([int]$math.pre_clear_xp -ne 8340 -or [int]$math.chapter_clear_xp -ne 1145 -or [int]$math.final_xp -ne 9485 -or [int]$Overlay.preserved_route_invariants.huaguoshan_target_active_minutes_at_cap -ne 55 -or -not (Test-StrictBoolean $Overlay.preserved_route_invariants.no_legacy_receipt_recalculation $true)) {
    Add-Issue $script:errors 'invalid_economy_v3_route_math' 'economy-v3 must preserve the reviewed Lv19/Lv20 and 55-minute anchors without historical receipt mutation.' $path
  }
  if ($null -ne $Overlay.non_production_boundary.source_profile_mapping -or -not (Test-StrictBoolean $Overlay.non_production_boundary.actual_receipt_creation $false) -or -not (Test-StrictBoolean $Overlay.non_production_boundary.actual_economic_execution $false) -or $null -ne $Overlay.non_production_boundary.runtime_keys) {
    Add-Issue $script:errors 'economy_v3_production_boundary_open' 'economy-v3 must not create source profiles, receipts, economic execution, or runtime keys.' $path
  }

  if ($null -eq $Register -or [string]$Register.current_future_route_overlay_version -ne 'economy-v3') {
    Add-Issue $script:errors 'economy_v3_not_registered_current_overlay' 'decision-register.json must name economy-v3 as the current future-route overlay while retaining economy-v2 as the only full resource table.' 'decision-register.json'
  }
  $registeredOverlay = $null
  foreach ($entry in (Get-Items $Register.adopted_route_overlays)) {
    if ([string]$entry.resource_table_version -eq 'economy-v3') { $registeredOverlay = $entry; break }
  }
  if ($null -eq $registeredOverlay -or [string]$registeredOverlay.path -ne $path -or [string]$registeredOverlay.base_resource_table_version -ne 'economy-v2' -or [string]$registeredOverlay.decision_id -ne 'ECO-XP-ROUTE-V3-001' -or [string]$registeredOverlay.decision_status -ne 'accepted-baseline' -or -not (Test-StrictBoolean $registeredOverlay.current $true) -or [string]$registeredOverlay.lifecycle_status -ne 'current-future-route-overlay' -or [string]$registeredOverlay.scope -ne 'future-huaguoshan-lv1-lv20-route-xp-and-semantic-bindings-only' -or -not (Test-StrictBoolean $registeredOverlay.runtime_handoff $false) -or [string]$registeredOverlay.production_gate -ne 'closed') {
    Add-Issue $script:errors 'invalid_economy_v3_register_entry' 'decision-register.json must register the exact runtime-closed economy-v3 route overlay.' 'decision-register.json.adopted_route_overlays'
  } else {
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $script:Root $path)).Hash
    if ($actualHash -ine [string]$registeredOverlay.content_hash_sha256 -or [string]$registeredOverlay.base_content_hash_sha256 -ne [string]$Overlay.inherits.content_hash_sha256) {
      Add-Issue $script:errors 'economy_v3_register_hash_mismatch' 'decision-register.json must bind exact economy-v3 and economy-v2 hashes.' 'decision-register.json.adopted_route_overlays'
    }
  }
  if (-not $script:DecisionMap.ContainsKey('ECO-XP-ROUTE-V3-001')) {
    Add-Issue $script:errors 'economy_v3_decision_missing' 'The economy-v3 route overlay requires an accepted decision-register entry.' 'decision-register.json'
  } else {
    $decision = $script:DecisionMap['ECO-XP-ROUTE-V3-001']
    $decisionSemanticKeys = @($decision.effective_value.future_route_semantic_binding_source_keys | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedDecisionSemanticKeys = @('XP_CAVE', 'XP_PEACH')
    if ([string]$decision.decision_status -ne 'accepted-baseline' -or -not (Test-StrictBoolean $decision.current $true) -or -not (Test-StrictBoolean $decision.runtime_handoff $false) -or [string]$decision.effective_value.base_resource_table_version -ne 'economy-v2' -or [string]$decision.effective_value.overlay_table_path -ne $path -or [string]$decision.effective_value.route_choice_id -ne 'HG_ROUTE_PENG_OR_CRACK_V3' -or [string]$decision.effective_value.scope -ne 'future-huaguoshan-lv1-lv20-route-xp-and-semantic-bindings-only' -or @(Compare-Object -ReferenceObject $expectedDecisionSemanticKeys -DifferenceObject $decisionSemanticKeys).Count -ne 0 -or -not (Test-StrictBoolean $decision.effective_value.historical_receipt_mutation $false)) {
      Add-Issue $script:errors 'invalid_economy_v3_decision' 'The registered economy-v3 decision must retain its base, overlay, choice, and no-history-mutation boundary.' 'decision-register.json'
    }
  }
}

function Test-CalibrationCandidates {
  param($Candidates)
  if ($null -eq $Candidates) { return }

  $path = 'calibration/calibration-candidates.json'
  $rootAllowedProperties = @(
    'version',
    'artifact',
    'artifact_status',
    'calibration_status',
    'non_production',
    'effective_value',
    'runtime_handoff',
    'production_gate',
    'historical_evidence_status',
    'current_baseline_reference',
    'purpose',
    'source_catalog',
    'source_snapshots',
    'assumption_catalog',
    'scenarios',
    'global_forbidden_promotions'
  )
  Assert-AllowedCalibrationProperties $Candidates $rootAllowedProperties $path 'Calibration artifact'
  Assert-RequiredCalibrationProperties $Candidates $rootAllowedProperties $path 'Calibration artifact'
  Assert-NonBlankStringItems $Candidates.global_forbidden_promotions $path 'global_forbidden_promotions'
  if ([string]$Candidates.artifact -ne 'growth-economy-calibration-candidates') {
    Add-Issue $script:errors 'invalid_calibration_artifact' 'Calibration artifact identifier is invalid.' $path
  }
  if ([string]$Candidates.artifact_status -ne 'candidate-only') {
    Add-Issue $script:errors 'invalid_calibration_artifact_status' 'Calibration artifact must remain candidate-only.' $path
  }
  if ([string]$Candidates.calibration_status -ne 'candidate') {
    Add-Issue $script:errors 'invalid_calibration_status' 'Calibration artifact must use calibration_status=candidate.' $path
  }
  if (-not (Has-Prop $Candidates 'non_production') -or -not (Test-StrictBoolean $Candidates.non_production $true)) {
    Add-Issue $script:errors 'calibration_non_production_required' 'Calibration artifact must explicitly declare the JSON Boolean non_production=true.' $path
  }
  if (-not (Has-Prop $Candidates 'effective_value') -or $null -ne $Candidates.effective_value) {
    Add-Issue $script:errors 'calibration_effective_value_forbidden' 'Calibration artifact may not contain an effective value.' $path
  }
  if (-not (Has-Prop $Candidates 'runtime_handoff') -or -not (Test-StrictBoolean $Candidates.runtime_handoff $false)) {
    Add-Issue $script:errors 'calibration_runtime_handoff_forbidden' 'Calibration artifact must explicitly declare the JSON Boolean runtime_handoff=false.' $path
  }
  if ([string]$Candidates.production_gate -ne 'closed') {
    Add-Issue $script:errors 'calibration_production_gate_open' 'Calibration artifact must keep the production gate closed.' $path
  }
  if ([string]$Candidates.historical_evidence_status -ne 'superseded-calibration-inputs-retained') {
    Add-Issue $script:errors 'invalid_calibration_historical_status' 'Calibration artifact must explicitly retain its inputs as superseded historical evidence.' $path
  }
  $baselineReference = $Candidates.current_baseline_reference
  Assert-AllowedCalibrationProperties $baselineReference @('resource_table_version', 'table_path', 'decision_register_path', 'boundary') $path 'Calibration current baseline reference'
  Assert-RequiredCalibrationProperties $baselineReference @('resource_table_version', 'table_path', 'decision_register_path', 'boundary') $path 'Calibration current baseline reference'
  $baselineVersion = if (Has-Prop $baselineReference 'resource_table_version') { [string]$baselineReference.PSObject.Properties['resource_table_version'].Value } else { '' }
  $baselineTablePath = if (Has-Prop $baselineReference 'table_path') { [string]$baselineReference.PSObject.Properties['table_path'].Value } else { '' }
  $baselineRegisterPath = if (Has-Prop $baselineReference 'decision_register_path') { [string]$baselineReference.PSObject.Properties['decision_register_path'].Value } else { '' }
  $baselineBoundary = if (Has-Prop $baselineReference 'boundary') { [string]$baselineReference.PSObject.Properties['boundary'].Value } else { '' }
  if ($baselineVersion -ne 'economy-v2' -or $baselineTablePath -ne 'docs/物编/成长数值与经济裁决包/tables/economy-v2-resource-table.json' -or $baselineRegisterPath -ne 'docs/物编/成长数值与经济裁决包/decision-register.json' -or $baselineBoundary -notlike '*must not override, compile, or issue rewards*') {
    Add-Issue $script:errors 'invalid_calibration_current_baseline_reference' 'Calibration artifact must point to economy-v2 and forbid overriding, compiling, or issuing from it.' $path
  }

  $projectRoot = (Resolve-Path -LiteralPath (Join-Path $script:Root '..\..\..')).Path
  $projectRootPrefix = $projectRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
  $sourceMap = @{}
  foreach ($source in (Get-Items $Candidates.source_catalog)) {
    $sourcePath = "$path.source_catalog"
    $sourceAllowedProperties = @('source_id', 'source_kind', 'decision_id', 'decision_status', 'source_refs', 'source_file_hashes', 'permitted_use', 'forbidden_use')
    Assert-AllowedCalibrationProperties $source $sourceAllowedProperties $sourcePath 'Calibration source'
    Assert-RequiredCalibrationProperties $source @('source_id', 'source_kind', 'source_refs', 'source_file_hashes', 'permitted_use', 'forbidden_use') $sourcePath 'Calibration source'
    if ((Has-Prop $source 'decision_id') -xor (Has-Prop $source 'decision_status')) {
      Add-Issue $script:errors 'incomplete_calibration_source_decision_ref' 'Calibration source must declare both decision_id and decision_status, or neither.' $sourcePath
    }
    $sourceId = if (Has-Prop $source 'source_id') { [string]$source.source_id } else { '' }
    if ([string]::IsNullOrWhiteSpace($sourceId)) {
      Add-Issue $script:errors 'missing_calibration_source_id' 'Calibration source is missing source_id.' $sourcePath
      continue
    }
    if ($sourceMap.ContainsKey($sourceId)) {
      Add-Issue $script:errors 'duplicate_calibration_source_id' "Duplicate calibration source_id: $sourceId" $sourcePath
      continue
    }
    $sourceMap[$sourceId] = $source
    $sourceRefs = Get-Items $source.source_refs
    Assert-NonBlankStringItems $sourceRefs $sourcePath "Calibration source $sourceId source_refs"
    Assert-NonBlankStringItems $source.permitted_use $sourcePath "Calibration source $sourceId permitted_use"
    Assert-NonBlankStringItems $source.forbidden_use $sourcePath "Calibration source $sourceId forbidden_use"
    if ($sourceRefs.Count -eq 0) {
      Add-Issue $script:errors 'missing_calibration_source_refs' "Calibration source $sourceId has no source_refs." $sourcePath
    }
    $sourceHashMap = @{}
    foreach ($sourceHash in (Get-Items $source.source_file_hashes)) {
      Assert-AllowedCalibrationProperties $sourceHash @('path', 'sha256') $sourcePath "Calibration source $sourceId source_file_hashes entry"
      Assert-RequiredCalibrationProperties $sourceHash @('path', 'sha256') $sourcePath "Calibration source $sourceId source_file_hashes entry"
      $sourceHashPath = if (Has-Prop $sourceHash 'path') { ([string]$sourceHash.path).Replace('\', '/') } else { '' }
      if ([string]::IsNullOrWhiteSpace($sourceHashPath) -or $sourceHashPath -notmatch '^(docs|implementation)/' -or $sourceHashPath -match '(^|/)\.\.(/|$)') {
        Add-Issue $script:errors 'invalid_calibration_source_hash_path' "Source $sourceId has an invalid source_file_hashes path." $sourcePath
        continue
      }
      if ($sourceHashMap.ContainsKey($sourceHashPath)) {
        Add-Issue $script:errors 'duplicate_calibration_source_hash_path' "Source $sourceId has a duplicate source_file_hashes path: $sourceHashPath" $sourcePath
        continue
      }
      $sourceHashMap[$sourceHashPath] = $sourceHash
      $expectedHash = if (Has-Prop $sourceHash 'sha256') { [string]$sourceHash.sha256 } else { '' }
      if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$') {
        Add-Issue $script:errors 'invalid_calibration_source_hash' "Source $sourceId has an invalid SHA-256 for $sourceHashPath." $sourcePath
        continue
      }
      $absoluteHashPath = Join-Path $projectRoot $sourceHashPath
      if (-not (Test-Path -LiteralPath $absoluteHashPath -PathType Leaf)) {
        Add-Issue $script:errors 'calibration_source_hash_file_not_found' "Source $sourceId hash target is missing: $sourceHashPath" $sourcePath
        continue
      }
      $resolvedHashPath = (Resolve-Path -LiteralPath $absoluteHashPath).Path
      if (-not $resolvedHashPath.StartsWith($projectRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Issue $script:errors 'calibration_source_hash_path_outside_project' "Source $sourceId hash target resolves outside the project: $sourceHashPath" $sourcePath
        continue
      }
      $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedHashPath).Hash
      if ($actualHash -ine $expectedHash) {
        Add-Issue $script:errors 'calibration_source_reference_hash_mismatch' "Source $sourceId reference hash no longer matches $sourceHashPath." $sourcePath
      }
    }
    if ($sourceHashMap.Count -eq 0) {
      Add-Issue $script:errors 'missing_calibration_source_hashes' "Source $sourceId must lock every source reference with source_file_hashes." $sourcePath
    }
    $referencedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($sourceRef in $sourceRefs) {
      $sourceRefText = [string]$sourceRef
      if ([string]::IsNullOrWhiteSpace($sourceRefText)) {
        Add-Issue $script:errors 'blank_calibration_source_ref' "Source $sourceId contains a blank source_ref." $sourcePath
        continue
      }
      $sourceRefMatch = [regex]::Match($sourceRefText, '^(?<file>(?:docs|implementation)/.+?)(?::(?<lines>\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*))?$')
      if (-not $sourceRefMatch.Success) {
        Add-Issue $script:errors 'invalid_calibration_source_ref' "Source $sourceId has an invalid repository-relative source_ref: $sourceRefText" $sourcePath
        continue
      }
      $sourceRefPath = $sourceRefMatch.Groups['file'].Value.Replace('\', '/')
      [void]$referencedPaths.Add($sourceRefPath)
      if (-not $sourceHashMap.ContainsKey($sourceRefPath)) {
        Add-Issue $script:errors 'calibration_source_ref_hash_missing' "Source $sourceId source_ref is not locked by source_file_hashes: $sourceRefPath" $sourcePath
        continue
      }
      $absoluteRefPath = Join-Path $projectRoot $sourceRefPath
      if (-not (Test-Path -LiteralPath $absoluteRefPath -PathType Leaf)) {
        Add-Issue $script:errors 'calibration_source_ref_file_not_found' "Source $sourceId source_ref file is missing: $sourceRefPath" $sourcePath
        continue
      }
      $resolvedRefPath = (Resolve-Path -LiteralPath $absoluteRefPath).Path
      if (-not $resolvedRefPath.StartsWith($projectRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Issue $script:errors 'calibration_source_ref_path_outside_project' "Source $sourceId source_ref resolves outside the project: $sourceRefPath" $sourcePath
        continue
      }
      $lineSpec = $sourceRefMatch.Groups['lines'].Value
      if (-not [string]::IsNullOrWhiteSpace($lineSpec)) {
        $lineCount = @(Get-Content -LiteralPath $resolvedRefPath -Encoding UTF8).Count
        foreach ($range in ($lineSpec -split ',')) {
          $rangeParts = $range -split '-'
          $firstLine = [int]$rangeParts[0]
          $lastLine = if ($rangeParts.Count -eq 2) { [int]$rangeParts[1] } else { $firstLine }
          if ($firstLine -lt 1 -or $lastLine -lt $firstLine -or $lastLine -gt $lineCount) {
            Add-Issue $script:errors 'invalid_calibration_source_ref_lines' "Source $sourceId source_ref line range is outside the file: $sourceRefText" $sourcePath
          }
        }
      }
    }
    foreach ($sourceHashPath in $sourceHashMap.Keys) {
      if (-not $referencedPaths.Contains($sourceHashPath)) {
        Add-Issue $script:errors 'unreferenced_calibration_source_hash' "Source $sourceId has a source_file_hashes entry without a matching source_ref: $sourceHashPath" $sourcePath
      }
    }
    if (Has-Prop $source 'decision_id') {
      Assert-DecisionRef $source "$sourcePath[$sourceId]"
    }
  }

  $snapshotMap = @{}
  foreach ($snapshot in (Get-Items $Candidates.source_snapshots)) {
    $snapshotPath = "$path.source_snapshots"
    $snapshotAllowedProperties = @('snapshot_id', 'source_id', 'source_path', 'sha256', 'observation_only', 'observed_summary', 'prohibited_promotions')
    Assert-AllowedCalibrationProperties $snapshot $snapshotAllowedProperties $snapshotPath 'Calibration source snapshot'
    Assert-RequiredCalibrationProperties $snapshot $snapshotAllowedProperties $snapshotPath 'Calibration source snapshot'
    Assert-AllowedCalibrationProperties $snapshot.observed_summary @('unit_count', 'unique_drop_profile_count', 'reward_exp_observed_range', 'zero_reward_exp_unit_count', 'nonzero_reward_exp_unit_count') $snapshotPath 'Calibration source snapshot observed_summary'
    Assert-RequiredCalibrationProperties $snapshot.observed_summary @('unit_count', 'unique_drop_profile_count', 'reward_exp_observed_range', 'zero_reward_exp_unit_count', 'nonzero_reward_exp_unit_count') $snapshotPath 'Calibration source snapshot observed_summary'
    Assert-NonBlankStringItems $snapshot.prohibited_promotions $snapshotPath 'Calibration source snapshot prohibited_promotions'
    $snapshotId = if (Has-Prop $snapshot 'snapshot_id') { [string]$snapshot.snapshot_id } else { '' }
    if ([string]::IsNullOrWhiteSpace($snapshotId)) {
      Add-Issue $script:errors 'missing_calibration_snapshot_id' 'Calibration source snapshot is missing snapshot_id.' $snapshotPath
      continue
    }
    if ($snapshotMap.ContainsKey($snapshotId)) {
      Add-Issue $script:errors 'duplicate_calibration_snapshot_id' "Duplicate calibration snapshot_id: $snapshotId" $snapshotPath
      continue
    }
    $snapshotMap[$snapshotId] = $snapshot
    $sourceId = if (Has-Prop $snapshot 'source_id') { [string]$snapshot.source_id } else { '' }
    if (-not $sourceMap.ContainsKey($sourceId)) {
      Add-Issue $script:errors 'unknown_calibration_snapshot_source' "Snapshot $snapshotId references unknown source_id: $sourceId" $snapshotPath
    } elseif ([string]$sourceMap[$sourceId].source_kind -ne 'whitebox-candidate') {
      Add-Issue $script:errors 'invalid_calibration_snapshot_source_kind' "Snapshot $snapshotId must bind a whitebox-candidate source_id, not $sourceId." $snapshotPath
    }
    if (-not (Has-Prop $snapshot 'observation_only') -or -not (Test-StrictBoolean $snapshot.observation_only $true)) {
      Add-Issue $script:errors 'calibration_snapshot_not_observation_only' "Snapshot $snapshotId must declare the JSON Boolean observation_only=true." $snapshotPath
    }
    $relativeSourcePath = if (Has-Prop $snapshot 'source_path') { [string]$snapshot.source_path } else { '' }
    if ([string]::IsNullOrWhiteSpace($relativeSourcePath) -or $relativeSourcePath -match '(^|[\\/])\.\.([\\/]|$)') {
      Add-Issue $script:errors 'invalid_calibration_snapshot_path' "Snapshot $snapshotId has an invalid source_path." $snapshotPath
      continue
    }
    $normalizedSnapshotPath = $relativeSourcePath.Replace('\', '/')
    if ($sourceMap.ContainsKey($sourceId)) {
      $boundSourceHash = $null
      foreach ($sourceHash in (Get-Items $sourceMap[$sourceId].source_file_hashes)) {
        if (([string]$sourceHash.path).Replace('\', '/') -eq $normalizedSnapshotPath) {
          $boundSourceHash = $sourceHash
          break
        }
      }
      if ($null -eq $boundSourceHash) {
        Add-Issue $script:errors 'calibration_snapshot_not_bound_to_source_file' "Snapshot $snapshotId source_path is not a hashed file of source_id $sourceId." $snapshotPath
      }
    }
    $absoluteSourcePath = Join-Path $projectRoot $relativeSourcePath
    if (-not (Test-Path -LiteralPath $absoluteSourcePath -PathType Leaf)) {
      Add-Issue $script:errors 'calibration_snapshot_source_not_found' "Snapshot $snapshotId source file is missing: $relativeSourcePath" $snapshotPath
      continue
    }
    $resolvedSourcePath = (Resolve-Path -LiteralPath $absoluteSourcePath).Path
    if (-not $resolvedSourcePath.StartsWith($projectRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      Add-Issue $script:errors 'calibration_snapshot_path_outside_project' "Snapshot $snapshotId resolves outside the project: $relativeSourcePath" $snapshotPath
      continue
    }
    $expectedHash = if (Has-Prop $snapshot 'sha256') { [string]$snapshot.sha256 } else { '' }
    if ($expectedHash -notmatch '^[A-Fa-f0-9]{64}$') {
      Add-Issue $script:errors 'invalid_calibration_snapshot_hash' "Snapshot $snapshotId must contain a SHA-256 value." $snapshotPath
      continue
    }
    if ($null -ne $boundSourceHash -and [string]$boundSourceHash.sha256 -ine $expectedHash) {
      Add-Issue $script:errors 'calibration_snapshot_hash_not_bound_to_source_file' "Snapshot $snapshotId SHA-256 does not match the hashed source file binding for $sourceId." $snapshotPath
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedSourcePath).Hash
    if ($actualHash -ine $expectedHash) {
      Add-Issue $script:errors 'calibration_source_hash_mismatch' "Snapshot $snapshotId no longer matches $relativeSourcePath." $snapshotPath
    }
  }
  foreach ($sourceId in $sourceMap.Keys) {
    if ([string]$sourceMap[$sourceId].source_kind -ne 'whitebox-candidate') { continue }
    $hasSnapshot = $false
    foreach ($snapshot in $snapshotMap.Values) {
      if ([string]$snapshot.source_id -eq $sourceId) {
        $hasSnapshot = $true
        break
      }
    }
    if (-not $hasSnapshot) {
      Add-Issue $script:errors 'missing_calibration_whitebox_snapshot' "Whitebox source $sourceId must have a source snapshot." $path
    }
  }

  $assumptionMap = @{}
  foreach ($assumption in (Get-Items $Candidates.assumption_catalog)) {
    $assumptionPath = "$path.assumption_catalog"
    $assumptionAllowedProperties = @('assumption_id', 'assumption_status', 'statement', 'basis_source_ids', 'validation_method', 'limitation')
    Assert-AllowedCalibrationProperties $assumption $assumptionAllowedProperties $assumptionPath 'Calibration assumption'
    Assert-RequiredCalibrationProperties $assumption $assumptionAllowedProperties $assumptionPath 'Calibration assumption'
    Assert-NonBlankStringItems $assumption.basis_source_ids $assumptionPath 'Calibration assumption basis_source_ids'
    $assumptionId = if (Has-Prop $assumption 'assumption_id') { [string]$assumption.assumption_id } else { '' }
    if ([string]::IsNullOrWhiteSpace($assumptionId)) {
      Add-Issue $script:errors 'missing_calibration_assumption_id' 'Calibration assumption is missing assumption_id.' $assumptionPath
      continue
    }
    if ($assumptionMap.ContainsKey($assumptionId)) {
      Add-Issue $script:errors 'duplicate_calibration_assumption_id' "Duplicate calibration assumption_id: $assumptionId" $assumptionPath
      continue
    }
    $assumptionMap[$assumptionId] = $assumption
    if ([string]$assumption.assumption_status -ne 'unvalidated') {
      Add-Issue $script:errors 'invalid_calibration_assumption_status' "Assumption $assumptionId must remain unvalidated." $assumptionPath
    }
    foreach ($field in @('statement', 'validation_method', 'limitation')) {
      if (-not (Has-Prop $assumption $field) -or [string]::IsNullOrWhiteSpace([string]$assumption.$field)) {
        Add-Issue $script:errors 'incomplete_calibration_assumption' "Assumption $assumptionId is missing $field." $assumptionPath
      }
    }
    $basisSourceIds = Get-Items $assumption.basis_source_ids
    if ($basisSourceIds.Count -eq 0) {
      Add-Issue $script:errors 'missing_calibration_assumption_basis' "Assumption $assumptionId has no basis_source_ids." $assumptionPath
    }
    foreach ($sourceId in $basisSourceIds) {
      if (-not $sourceMap.ContainsKey([string]$sourceId)) {
        Add-Issue $script:errors 'unknown_calibration_assumption_source' "Assumption $assumptionId references unknown source_id: $sourceId" $assumptionPath
      }
    }
  }

  $expectedScenarioIds = @(
    'CAL-XP-HG-LV1-20-001',
    'CAL-THROUGHPUT-HG-PUBLIC-001',
    'CAL-ECON-SINK-RELATIVE-001',
    'CAL-OX-RETRY-TIME-PRESSURE-001'
  )
  $commonScenarioProperties = @(
    'scenario_id',
    'decision_id',
    'decision_status',
    'calibration_status',
    'non_production',
    'effective_value',
    'runtime_handoff',
    'source_ids',
    'source_snapshot_ids',
    'assumption_ids',
    'scope',
    'candidate_value',
    'required_evidence',
    'promotion_gates',
    'exclusions'
  )
  $scenarioAllowedProperties = @{
    'CAL-XP-HG-LV1-20-001' = @($commonScenarioProperties + 'model_options')
    'CAL-THROUGHPUT-HG-PUBLIC-001' = $commonScenarioProperties
    'CAL-ECON-SINK-RELATIVE-001' = $commonScenarioProperties
    'CAL-OX-RETRY-TIME-PRESSURE-001' = @($commonScenarioProperties + 'documented_combat_input')
  }
  $scenarioScopeProperties = @{
    'CAL-XP-HG-LV1-20-001' = @('level_band', 'chapter', 'content_density_reference')
    'CAL-THROUGHPUT-HG-PUBLIC-001' = @('encounter_scope', 'qualification_scope', 'profile_scope')
    'CAL-ECON-SINK-RELATIVE-001' = @('growth_actions', 'comparison_mode', 'owner_scope')
    'CAL-OX-RETRY-TIME-PRESSURE-001' = @('encounter_scope', 'measurement_scope', 'reward_scope')
  }
  $scenarioCandidateValueProperties = @{
    'CAL-XP-HG-LV1-20-001' = @('relative_xp_budget_index', 'relative_source_mix_index', 'cadence_fit', 'official_xp_table', 'party_distribution_policy', 'level_difference_rule', 'death_rule', 'reconnect_rule')
    'CAL-THROUGHPUT-HG-PUBLIC-001' = @('qualification_policy_id', 'relative_throughput_index', 'currency_amount', 'material_amount', 'drop_probability', 'pity_threshold', 'pity_pool_key', 'grant_count')
    'CAL-ECON-SINK-RELATIVE-001' = @('currency_candidate_key', 'source_family', 'sink_family', 'relative_sink_index', 'currency_amount', 'upgrade_cost', 'material_amount', 'material_key', 'max_balance')
    'CAL-OX-RETRY-TIME-PRESSURE-001' = @('relative_retry_pressure_index', 'compensation_drop_delta', 'currency_amount', 'drop_probability', 'pity_threshold')
  }

  $scenarioMap = @{}
  foreach ($scenario in (Get-Items $Candidates.scenarios)) {
    $scenarioPath = "$path.scenarios"
    $scenarioId = if (Has-Prop $scenario 'scenario_id') { [string]$scenario.scenario_id } else { '' }
    if ([string]::IsNullOrWhiteSpace($scenarioId)) {
      Add-Issue $script:errors 'missing_calibration_scenario_id' 'Calibration scenario is missing scenario_id.' $scenarioPath
      continue
    }
    if ($scenarioMap.ContainsKey($scenarioId)) {
      Add-Issue $script:errors 'duplicate_calibration_scenario_id' "Duplicate calibration scenario_id: $scenarioId" $scenarioPath
      continue
    }
    $scenarioMap[$scenarioId] = $scenario
    if ($expectedScenarioIds -notcontains $scenarioId) {
      Add-Issue $script:errors 'unexpected_calibration_scenario' "Unexpected calibration scenario: $scenarioId" $scenarioPath
    }
    $allowedScenarioProperties = if ($scenarioAllowedProperties.ContainsKey($scenarioId)) { $scenarioAllowedProperties[$scenarioId] } else { $commonScenarioProperties }
    Assert-AllowedCalibrationProperties $scenario $allowedScenarioProperties $scenarioPath "Calibration scenario $scenarioId"
    Assert-RequiredCalibrationProperties $scenario $allowedScenarioProperties $scenarioPath "Calibration scenario $scenarioId"
    if ($scenarioScopeProperties.ContainsKey($scenarioId)) {
      Assert-AllowedCalibrationProperties $scenario.scope $scenarioScopeProperties[$scenarioId] $scenarioPath "Calibration scenario $scenarioId scope"
      Assert-RequiredCalibrationProperties $scenario.scope $scenarioScopeProperties[$scenarioId] $scenarioPath "Calibration scenario $scenarioId scope"
    }
    Assert-DecisionRef $scenario "$scenarioPath[$scenarioId]"
    if ([string]$scenario.decision_status -eq 'accepted-baseline') {
      Add-Issue $script:errors 'calibration_scenario_accepted_forbidden' "Calibration scenario $scenarioId may not be an accepted-baseline decision." $scenarioPath
    }
    if ([string]$scenario.calibration_status -ne 'candidate') {
      Add-Issue $script:errors 'invalid_calibration_scenario_status' "Scenario $scenarioId must use calibration_status=candidate." $scenarioPath
    }
    if (-not (Has-Prop $scenario 'non_production') -or -not (Test-StrictBoolean $scenario.non_production $true)) {
      Add-Issue $script:errors 'calibration_scenario_non_production_required' "Scenario $scenarioId must explicitly declare the JSON Boolean non_production=true." $scenarioPath
    }
    if (-not (Has-Prop $scenario 'effective_value') -or $null -ne $scenario.effective_value) {
      Add-Issue $script:errors 'calibration_effective_value_forbidden' "Scenario $scenarioId may not contain an effective value." $scenarioPath
    }
    if (-not (Has-Prop $scenario 'runtime_handoff') -or -not (Test-StrictBoolean $scenario.runtime_handoff $false)) {
      Add-Issue $script:errors 'calibration_runtime_handoff_forbidden' "Scenario $scenarioId must explicitly declare the JSON Boolean runtime_handoff=false." $scenarioPath
    }
    if ($scenarioCandidateValueProperties.ContainsKey($scenarioId)) {
      Assert-NullCalibrationObject $scenario.candidate_value $scenarioCandidateValueProperties[$scenarioId] $scenarioPath "Calibration scenario $scenarioId candidate_value"
    } elseif (-not (Has-Prop $scenario 'candidate_value') -or -not ($scenario.candidate_value -is [pscustomobject])) {
      Add-Issue $script:errors 'missing_calibration_candidate_value' "Scenario $scenarioId must include an object candidate_value." $scenarioPath
    }
    foreach ($field in @('source_ids', 'assumption_ids', 'required_evidence', 'promotion_gates')) {
      if ((Get-Items $scenario.$field).Count -eq 0) {
        Add-Issue $script:errors 'incomplete_calibration_scenario' "Scenario $scenarioId has no $field." $scenarioPath
      }
    }
    foreach ($field in @('source_ids', 'source_snapshot_ids', 'assumption_ids', 'required_evidence', 'promotion_gates', 'exclusions')) {
      Assert-NonBlankStringItems $scenario.$field $scenarioPath "Calibration scenario $scenarioId $field"
    }
    if ($scenarioId -eq 'CAL-XP-HG-LV1-20-001') {
      foreach ($modelOption in (Get-Items $scenario.model_options)) {
        Assert-AllowedCalibrationProperties $modelOption @('option_id', 'classification', 'definition') $scenarioPath "Calibration scenario $scenarioId model option"
        Assert-RequiredCalibrationProperties $modelOption @('option_id', 'classification', 'definition') $scenarioPath "Calibration scenario $scenarioId model option"
        foreach ($field in @('option_id', 'classification', 'definition')) {
          if (-not ($modelOption.$field -is [string]) -or [string]::IsNullOrWhiteSpace([string]$modelOption.$field)) {
            Add-Issue $script:errors 'invalid_calibration_model_option' "Scenario $scenarioId model option is missing a non-blank $field." $scenarioPath
          }
        }
      }
    }
    if ($scenarioId -eq 'CAL-OX-RETRY-TIME-PRESSURE-001') {
      $combatInput = $scenario.documented_combat_input
      Assert-AllowedCalibrationProperties $combatInput @('per_wipe_attribute_increment_percent', 'pressure_duration_minutes', 'source_id', 'interpretation') $scenarioPath "Calibration scenario $scenarioId documented_combat_input"
      Assert-RequiredCalibrationProperties $combatInput @('per_wipe_attribute_increment_percent', 'pressure_duration_minutes', 'source_id', 'interpretation') $scenarioPath "Calibration scenario $scenarioId documented_combat_input"
      if (-not ($combatInput.per_wipe_attribute_increment_percent -is [int]) -or [int]$combatInput.per_wipe_attribute_increment_percent -ne 5) {
        Add-Issue $script:errors 'invalid_calibration_combat_input' "Scenario $scenarioId must retain the documented +5% retry-pressure input." $scenarioPath
      }
      if (-not ($combatInput.pressure_duration_minutes -is [int]) -or [int]$combatInput.pressure_duration_minutes -ne 5) {
        Add-Issue $script:errors 'invalid_calibration_combat_input' "Scenario $scenarioId must retain the documented five-minute retry-pressure input." $scenarioPath
      }
      if ([string]$combatInput.source_id -ne 'SRC-OX-RETRY-001' -or [string]::IsNullOrWhiteSpace([string]$combatInput.interpretation)) {
        Add-Issue $script:errors 'invalid_calibration_combat_input' "Scenario $scenarioId documented_combat_input must remain bound to SRC-OX-RETRY-001 with an interpretation." $scenarioPath
      }
    }
    if (-not (Has-Prop $scenario 'source_snapshot_ids')) {
      Add-Issue $script:errors 'missing_calibration_scenario_snapshot_refs' "Scenario $scenarioId must explicitly declare source_snapshot_ids, even when empty." $scenarioPath
    }
    $scenarioSourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $whiteboxSourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($sourceId in (Get-Items $scenario.source_ids)) {
      if (-not $scenarioSourceIds.Add([string]$sourceId)) {
        Add-Issue $script:errors 'duplicate_calibration_scenario_source' "Scenario $scenarioId repeats source_id: $sourceId" $scenarioPath
      }
      if (-not $sourceMap.ContainsKey([string]$sourceId)) {
        Add-Issue $script:errors 'unknown_calibration_scenario_source' "Scenario $scenarioId references unknown source_id: $sourceId" $scenarioPath
      } elseif ([string]$sourceMap[[string]$sourceId].source_kind -eq 'whitebox-candidate') {
        [void]$whiteboxSourceIds.Add([string]$sourceId)
      }
    }
    $scenarioSnapshotIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $boundSnapshotSourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($snapshotId in (Get-Items $scenario.source_snapshot_ids)) {
      if (-not $scenarioSnapshotIds.Add([string]$snapshotId)) {
        Add-Issue $script:errors 'duplicate_calibration_scenario_snapshot' "Scenario $scenarioId repeats snapshot_id: $snapshotId" $scenarioPath
      }
      if (-not $snapshotMap.ContainsKey([string]$snapshotId)) {
        Add-Issue $script:errors 'unknown_calibration_scenario_snapshot' "Scenario $scenarioId references unknown snapshot_id: $snapshotId" $scenarioPath
      } else {
        $snapshotSourceId = [string]$snapshotMap[[string]$snapshotId].source_id
        if (-not $scenarioSourceIds.Contains($snapshotSourceId)) {
          Add-Issue $script:errors 'calibration_snapshot_not_bound_to_scenario_source' "Scenario $scenarioId snapshot $snapshotId is not bound to one of its source_ids." $scenarioPath
        } else {
          [void]$boundSnapshotSourceIds.Add($snapshotSourceId)
        }
      }
    }
    foreach ($whiteboxSourceId in $whiteboxSourceIds) {
      if (-not $boundSnapshotSourceIds.Contains($whiteboxSourceId)) {
        Add-Issue $script:errors 'missing_calibration_scenario_whitebox_snapshot' "Scenario $scenarioId must bind whitebox source_id $whiteboxSourceId to one of its source_snapshot_ids." $scenarioPath
      }
    }
    foreach ($assumptionId in (Get-Items $scenario.assumption_ids)) {
      if (-not $assumptionMap.ContainsKey([string]$assumptionId)) {
        Add-Issue $script:errors 'unknown_calibration_scenario_assumption' "Scenario $scenarioId references unknown assumption_id: $assumptionId" $scenarioPath
      }
    }
    if ((Get-Items $scenario.promotion_gates) -notcontains 'requires-explicit-design-adoption') {
      Add-Issue $script:errors 'calibration_explicit_adoption_gate_missing' "Scenario $scenarioId must require explicit design adoption." $scenarioPath
    }
  }

  foreach ($expectedScenarioId in @(
    'CAL-XP-HG-LV1-20-001',
    'CAL-THROUGHPUT-HG-PUBLIC-001',
    'CAL-ECON-SINK-RELATIVE-001',
    'CAL-OX-RETRY-TIME-PRESSURE-001'
  )) {
    if (-not $scenarioMap.ContainsKey($expectedScenarioId)) {
      Add-Issue $script:errors 'missing_required_calibration_scenario' "Missing required calibration scenario: $expectedScenarioId" $path
    }
  }

  Test-CalibrationCandidateValueBoundary $Candidates $path
}

$resolvedRoot = Resolve-Path -LiteralPath $PackageRoot -ErrorAction Stop
$script:Root = $resolvedRoot.Path
$script:AllowedStatuses = @('accepted-baseline', 'proposal', 'deferred', 'conflict', 'whitebox-candidate')

$register = Read-JsonFile 'decision-register.json'
$experience = Read-JsonFile 'tables/experience-progression.json'
$items = Read-JsonFile 'tables/item-growth.json'
$currency = Read-JsonFile 'tables/currency-ledger.json'
$drop = Read-JsonFile 'tables/drop-and-pity.json'
$tower = Read-JsonFile 'tables/tower-reward.json'
$economyV1Historical = Read-JsonFile 'tables/economy-v1-resource-table.json'
$economyV2 = Read-JsonFile 'tables/economy-v2-resource-table.json'
$economyV3 = Read-JsonFile 'tables/economy-v3-resource-table.json'
$calibration = Read-JsonFile 'calibration/calibration-candidates.json'

$script:DecisionMap = @{}
if ($null -ne $register) {
  foreach ($decision in (Get-Items $register.decisions)) {
    if (-not (Has-Prop $decision 'decision_id') -or [string]::IsNullOrWhiteSpace([string]$decision.decision_id)) {
      Add-Issue $errors 'missing_decision_id' 'Decision register entry is missing decision_id.' 'decision-register.json'
      continue
    }
    $id = [string]$decision.decision_id
    if ($script:DecisionMap.ContainsKey($id)) {
      Add-Issue $errors 'duplicate_decision_id' "Duplicate decision_id: $id" 'decision-register.json'
      continue
    }
    $script:DecisionMap[$id] = $decision

    if (-not (Has-Prop $decision 'decision_status') -or $script:AllowedStatuses -notcontains [string]$decision.decision_status) {
      Add-Issue $errors 'invalid_decision_status' "Decision $id has no supported decision_status." 'decision-register.json'
    }
    if ([string]$decision.decision_status -eq 'accepted-baseline') {
      if ((Get-Items $decision.source_refs).Count -eq 0) {
        Add-Issue $errors 'accepted_without_source' "Accepted baseline decision $id has no source_refs." 'decision-register.json'
      }
      if ([string]::IsNullOrWhiteSpace([string]$decision.adoption_ref)) {
        Add-Issue $errors 'accepted_without_adoption_ref' "Accepted baseline decision $id has no adoption_ref." 'decision-register.json'
      }
    } else {
      if ((Has-Prop $decision 'effective_value') -and $null -ne $decision.effective_value) {
        Add-Issue $errors 'non_effective_has_value' "Decision $id is not accepted-baseline but has effective_value." 'decision-register.json'
      }
      if ((Has-Prop $decision 'runtime_handoff') -and [bool]$decision.runtime_handoff) {
        Add-Issue $errors 'non_effective_runtime_handoff' "Decision $id is not accepted-baseline but has runtime_handoff=true." 'decision-register.json'
      }
    }
  }
}

foreach ($node in @(
  $experience,
  $items,
  $currency,
  $drop,
  $tower,
  $economyV3,
  $calibration
)) {
  Test-GovernedNode $node ''
}

Test-OfflineSimulationBoundary $register
Test-EconomyV2Adoption $economyV2 $register
Test-EconomyV3RouteOverlay $economyV3 $register
Test-CalibrationCandidates $calibration

if ($null -ne $currency) {
  $currencyKeys = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($entry in (Get-Items $currency.currencies)) {
    $key = [string]$entry.currency_key
    if ([string]::IsNullOrWhiteSpace($key)) {
      Add-Issue $errors 'missing_currency_key' 'Currency entry is missing currency_key.' 'tables/currency-ledger.json'
    } elseif (-not $currencyKeys.Add($key)) {
      Add-Issue $errors 'duplicate_currency_key' "Duplicate currency_key: $key" 'tables/currency-ledger.json'
    }
  }
  $requiredLedgerFields = @(
    'schema_version',
    'resource_table_version',
    'owner_scope',
    'owner_id',
    'event_id',
    'event_type',
    'source_profile',
    'balance_delta',
    'receipt_id'
  )
  $ledgerFields = Get-Items $currency.ledger_contract.proposal_value.required_record_fields
  foreach ($requiredField in $requiredLedgerFields) {
    if ($ledgerFields -notcontains $requiredField) {
      Add-Issue $errors 'missing_ledger_field' "Ledger proposal is missing required field: $requiredField" 'tables/currency-ledger.json.ledger_contract'
    }
  }
}

if ($null -ne $drop) {
  $expectedQualificationKeys = @(
    'kill_honor_credit',
    'progression_participation',
    'participation_chest_eligibility',
    'rare_drop_eligibility'
  )
  $qualificationMap = @{}
  foreach ($channel in (Get-Items $drop.qualification_channels)) {
    $key = [string]$channel.qualification_key
    if ([string]::IsNullOrWhiteSpace($key)) {
      Add-Issue $errors 'missing_qualification_key' 'Qualification channel is missing qualification_key.' 'tables/drop-and-pity.json'
    } elseif ($qualificationMap.ContainsKey($key)) {
      Add-Issue $errors 'duplicate_qualification_key' "Duplicate qualification key: $key" 'tables/drop-and-pity.json'
    } else {
      $qualificationMap[$key] = $channel
    }
  }
  foreach ($key in $expectedQualificationKeys) {
    if (-not $qualificationMap.ContainsKey($key)) {
      Add-Issue $errors 'missing_qualification_channel' "Missing required qualification channel: $key" 'tables/drop-and-pity.json'
    }
  }
  if ($qualificationMap.ContainsKey('participation_chest_eligibility')) {
    $chest = $qualificationMap['participation_chest_eligibility']
    if ([string]$chest.decision_status -eq 'conflict' -and $null -ne $chest.final_policy_id) {
      Add-Issue $errors 'conflict_policy_enabled' 'Participation chest has conflict status but final_policy_id is already set.' 'tables/drop-and-pity.json.qualification_channels'
    }
  }
  if ($qualificationMap.ContainsKey('rare_drop_eligibility')) {
    $rare = $qualificationMap['rare_drop_eligibility']
    foreach ($forbidden in @('kill_honor_credit', 'progression_participation', 'participation_chest_eligibility', 'primary_assist_role')) {
      if ((Get-Items $rare.must_not_derive) -notcontains $forbidden) {
        Add-Issue $errors 'rare_derivation_boundary_missing' "Rare eligibility must explicitly remain independent from $forbidden." 'tables/drop-and-pity.json.qualification_channels'
      }
    }
  }

  $dropProfileKeys = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($profile in (Get-Items $drop.drop_profiles)) {
    $key = [string]$profile.profile_key
    if ([string]::IsNullOrWhiteSpace($key)) {
      Add-Issue $errors 'missing_drop_profile_key' 'Drop profile is missing profile_key.' 'tables/drop-and-pity.json'
    } elseif (-not $dropProfileKeys.Add($key)) {
      Add-Issue $errors 'duplicate_drop_profile_key' "Duplicate drop profile: $key" 'tables/drop-and-pity.json'
    }
    if ([string]$profile.profile_status -ne 'deferred') {
      Add-Issue $errors 'active_drop_profile_in_draft' "Drop profile $key must remain deferred in this decision draft." 'tables/drop-and-pity.json'
    }
    if ($null -ne $profile.effective_table) {
      Add-Issue $errors 'effective_drop_table_in_draft' "Drop profile $key has an effective table before adoption." 'tables/drop-and-pity.json'
    }
  }
  if ($dropProfileKeys.Count -ne 21) {
    Add-Issue $errors 'unexpected_drop_profile_count' "Expected 21 inherited HG_DROP profile keys, found $($dropProfileKeys.Count)." 'tables/drop-and-pity.json'
  }
  $expectedDropProfileKeys = @(
    'HG_DROP_MOUNTAIN_COMMON',
    'HG_DROP_MOUNTAIN_ELITE',
    'HG_DROP_MOUNTAIN_MAJOR',
    'HG_DROP_WATERFALL_COMMON',
    'HG_DROP_WATERFALL_ELITE',
    'HG_DROP_MACAQUE_PUBLIC',
    'HG_DROP_PEACH_COMMON',
    'HG_DROP_PEACH_MAJOR',
    'HG_DROP_CAVE_COMMON',
    'HG_DROP_CAVE_MAJOR',
    'HG_DROP_SEVENSTAR_COMMON',
    'HG_DROP_SEVENSTAR_ELITE',
    'HG_DROP_SEVENSTAR_MAJOR',
    'HG_DROP_PENG_OPTIONAL',
    'HG_DROP_EASTSEA_COMMON',
    'HG_DROP_EASTSEA_ELITE',
    'HG_DROP_JIAO_PUBLIC',
    'HG_DROP_SHARK_PUBLIC',
    'HG_DROP_DRAGON_OLD',
    'HG_DROP_DRAGON_REVERSE',
    'HG_DROP_OX_RAID'
  )
  foreach ($expectedKey in $expectedDropProfileKeys) {
    if (-not $dropProfileKeys.Contains($expectedKey)) {
      Add-Issue $errors 'missing_inherited_drop_profile' "Missing inherited HG_DROP profile: $expectedKey" 'tables/drop-and-pity.json'
    }
  }
  foreach ($actualKey in $dropProfileKeys) {
    if ($expectedDropProfileKeys -notcontains $actualKey) {
      Add-Issue $errors 'unexpected_drop_profile_key' "Unexpected HG_DROP profile key: $actualKey" 'tables/drop-and-pity.json'
    }
  }
}

foreach ($relativePath in @(
  'tables/experience-progression.json',
  'tables/item-growth.json',
  'tables/currency-ledger.json',
  'tables/drop-and-pity.json',
  'tables/tower-reward.json',
  'tables/economy-v1-resource-table.json',
  'tables/economy-v2-resource-table.json',
  'tables/economy-v3-resource-table.json',
  'calibration/calibration-candidates.json'
)) {
  $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:Root $relativePath)
  if ($raw -match '(?i)"y3_id"\s*:') {
    Add-Issue $errors 'y3_id_not_allowed' 'This decision package must not contain Y3 object IDs.' $relativePath
  }
}

if ($errors.Count -eq 0) {
  Add-Issue $info 'economy_v2_adopted_design_baseline' 'economy-v2 is frozen as an accepted design baseline; legacy drafts and calibration candidates remain non-effective.' 'package'
  Add-Issue $info 'economy_v3_future_route_overlay' 'economy-v3 is a hash-bound, runtime-closed future Huaguoshan route overlay; it cannot mutate economy-v2 or historical receipts.' 'package'
  Add-Issue $info 'production_gate_closed' 'The package is structurally and semantically review-ready, not production-ready.' 'package'
}

$summary = [pscustomobject]@{
  packageRoot = $script:Root
  decisions = $script:DecisionMap.Count
  currencies = if ($null -ne $currency) { (Get-Items $currency.currencies).Count } else { 0 }
  dropProfiles = if ($null -ne $drop) { (Get-Items $drop.drop_profiles).Count } else { 0 }
  historicalEconomyV1 = if ($null -ne $economyV1Historical) { [string]$economyV1Historical.resource_table_version } else { $null }
  adoptedEconomyV2 = if ($null -ne $economyV2) { [string]$economyV2.resource_table_version } else { $null }
  futureRouteOverlayEconomyV3 = if ($null -ne $economyV3) { [string]$economyV3.resource_table_version } else { $null }
  calibrationScenarios = if ($null -ne $calibration) { (Get-Items $calibration.scenarios).Count } else { 0 }
  errors = $errors.Count
  warnings = $warnings.Count
}

[pscustomobject]@{
  ok = $errors.Count -eq 0
  errors = $errors
  warnings = $warnings
  info = $info
  summary = $summary
} | ConvertTo-Json -Depth 12

if ($errors.Count -gt 0) {
  exit 1
}
