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
  $calibration
)) {
  Test-GovernedNode $node ''
}

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
  'calibration/calibration-candidates.json'
)) {
  $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $script:Root $relativePath)
  if ($raw -match '(?i)"y3_id"\s*:') {
    Add-Issue $errors 'y3_id_not_allowed' 'This decision package must not contain Y3 object IDs.' $relativePath
  }
}

if ($errors.Count -eq 0) {
  Add-Issue $info 'draft_safe' 'All non-baseline decisions remain non-effective and all inherited HG_DROP profiles remain deferred.' 'package'
  Add-Issue $info 'production_gate_closed' 'The package is structurally and semantically review-ready, not production-ready.' 'package'
}

$summary = [pscustomobject]@{
  packageRoot = $script:Root
  decisions = $script:DecisionMap.Count
  currencies = if ($null -ne $currency) { (Get-Items $currency.currencies).Count } else { 0 }
  dropProfiles = if ($null -ne $drop) { (Get-Items $drop.drop_profiles).Count } else { 0 }
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
