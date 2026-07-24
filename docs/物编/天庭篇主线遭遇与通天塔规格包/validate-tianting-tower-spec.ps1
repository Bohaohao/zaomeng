[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$script:Checks = 0
$script:Errors = [System.Collections.Generic.List[string]]::new()
$PackageRoot = Split-Path -Parent $PSCommandPath
$WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $PackageRoot '..\..\..')).Path
$VerticalSliceRoot = Join-Path $WorkspaceRoot 'implementation\tianting-authority-vertical-slice'
$CombatCalibrationRoot = Join-Path $WorkspaceRoot 'implementation\combat-calibration'
$P0EvidenceAdoptionRoot = Join-Path $CombatCalibrationRoot 'evidence-adoption'
$P0EvidenceAdoptionRunner = Join-Path $P0EvidenceAdoptionRoot 'tests\run-all.ps1'
$P0ExternalCaptureOnboardingRoot = Join-Path $CombatCalibrationRoot 'external-capture-onboarding'
$P0ExternalCaptureOnboardingRunner = Join-Path $P0ExternalCaptureOnboardingRoot 'tests\run-all.ps1'
$ConstructionPreflightRoot = Join-Path $WorkspaceRoot 'implementation\tianting-y3-construction-preflight'
$ConstructionPreflightRunner = Join-Path $ConstructionPreflightRoot 'tests\Invoke-TiantingY3ConstructionPreflight.ps1'
$SurfaceManifestRoot = Join-Path $WorkspaceRoot 'implementation\tianting-surface-construction-manifest'
$SevenStarSessionReferenceRoot = Join-Path $WorkspaceRoot 'implementation\tianting-seven-star-session-reference'
$MansionSessionReferenceRoot = Join-Path $WorkspaceRoot 'implementation\tianting-mansion-session-reference'
$MainlinePresentationRoot = Join-Path $PackageRoot 'mainline-presentation'
$ObjectFieldReservationRoot = Join-Path $PackageRoot 'object-preallocation'
$ObjectFieldReservationContractPath = Join-Path $ObjectFieldReservationRoot 'tianting-object-field-reservation-contract.json'
$ObjectFieldReservationRunner = Join-Path $ObjectFieldReservationRoot 'tests\run-all.ps1'
$MansionEncounterOrchestrationRoot = Join-Path $PackageRoot 'mansion-orchestration'
$MansionEncounterOrchestrationContractPath = Join-Path $MansionEncounterOrchestrationRoot 'tianting-mansion-encounter-orchestration-contract.json'
$MansionEncounterOrchestrationRunner = Join-Path $MansionEncounterOrchestrationRoot 'tests\run-all.ps1'
$ConstructionReadinessRunner = Join-Path $WorkspaceRoot 'implementation\run-all-tianting-construction-readiness.ps1'

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

function Assert-ExactNumericArray {
  param($Actual, [double[]]$Expected, [string]$Name)
  Assert-Array $Actual $Name
  $Matches = $Actual -is [System.Array] -and @($Actual).Count -eq @($Expected).Count
  if ($Matches) {
    for ($Index = 0; $Index -lt @($Expected).Count; $Index++) {
      if ([double]$Actual[$Index] -ne [double]$Expected[$Index]) {
        $Matches = $false
        break
      }
    }
  }
  Assert-Condition $Matches "$Name; expected numeric '$(@($Expected) -join '|')', got '$(@($Actual) -join '|')'"
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
      if ($Property.Name -match '^(runtime(?:_.+)?_key|runtimeKey)$') {
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

function Get-Sha256Hex {
  param([byte[]]$Bytes)
  $Hasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($Hasher.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
  }
  finally {
    $Hasher.Dispose()
  }
}

try {
  $RequiredFiles = @(
    'README.md',
    'construction-readiness-ledger.md',
    'decision-register.md',
    'tianting-mainline-tower-contract.json',
    'tianting-content-expansion-contract.json',
    'authority/tianting-progression-and-instance-authority-contract.json',
    'mainline-route.md',
    'topology-whitebox.md',
    'encounters/天庭公共遭遇规格.md',
    'instances/七星单人本规格.md',
    'instances/二十八星宿团队本规格.md',
    'combat/天庭战斗机制与可读性规格.md',
    'combat/tianting-combat-readability-contract.json',
    'combat-baseline/天庭战斗数值与单位基线裁决.md',
    'combat-baseline/tianting-combat-numeric-unit-baseline-contract.json',
    'enemy-ecology/天庭敌人生态与精英单位规格.md',
    'enemy-ecology/tianting-enemy-ecology-contract.json',
    'mainline-boss/天庭主线Boss深化规格.md',
    'mainline-boss/tianting-mainline-boss-contract.json',
    'mainline-presentation/README.md',
    'mainline-presentation/天庭主线Boss叙事与表现深化规格.md',
    'mainline-presentation/tianting-mainline-presentation-contract.json',
    'mainline-presentation/tests/Test-MainlinePresentation.ps1',
    'mainline-presentation/tests/run-all.ps1',
    'mansion-orchestration/README.md',
    'mansion-orchestration/天庭二十八星官与四圣机制编排规格.md',
    'mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json',
    'mansion-orchestration/tests/Test-MansionEncounterOrchestration.ps1',
    'mansion-orchestration/tests/run-all.ps1',
    'object-preallocation/README.md',
    'object-preallocation/天庭物编字段预占规格.md',
    'object-preallocation/tianting-object-field-reservation-contract.json',
    'object-preallocation/tests/Test-ObjectFieldReservation.ps1',
    'object-preallocation/tests/run-all.ps1',
    'terrain-layout/layout.json',
    'terrain-layout/layout-report.md',
    'terrain-layout/layout-preview.html',
    'terrain-layout/layout-preview.png',
    'terrain-layout/layout-preview.meta.json',
    'terrain-layout/天庭地图口径对齐与白盒前置裁决.md',
    'terrain-layout/tianting-map-scale-alignment-contract.json',
    'terrain-layout/scale-alignment/layout.json',
    'terrain-layout/scale-alignment/layout-report.md',
    'terrain-layout/scale-alignment/layout-preview.html',
    'terrain-layout/scale-alignment/layout-preview.png',
    'terrain-layout/scale-alignment/layout-preview.meta.json',
    'ui/天庭UI与无障碍信息架构规格.md',
    'ui/tianting-ui-accessibility-information-contract.json',
    'object-blueprint/天庭物编美术与特效需求蓝图.md',
    'object-blueprint/tianting-object-art-vfx-blueprint-contract.json',
    'tower-economy/星宿经济来源、全局通天塔运行与赛季裁决.md',
    'tower-economy/mansion-economy-global-tower-run-season-contract.json',
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

  foreach ($RelativePath in @(
    'README.md',
    'package-contract.json',
    'lua/tianting_authority_core.lua',
    'tests/fake_authority_provider.lua',
    'tests/test_tianting_authority_core.lua',
    'tests/test-execution-boundary.ps1',
    'tests/run-all.ps1',
    'tests/y3-api-baseline.json'
  )) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $VerticalSliceRoot $RelativePath) -PathType Leaf) "vertical slice required file exists: $RelativePath"
  }

  foreach ($RelativePath in @(
    'README.md',
    'package-contract.json',
    'contract/cross-profession-combat-calibration-contract.json',
    'reference/calibration-core.js',
    'tests/run-all.ps1',
    'tests/test-calibration.js',
    'tests/test-execution-boundary.ps1',
    'validation-report.md'
  )) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $CombatCalibrationRoot $RelativePath) -PathType Leaf) "P0 combat-calibration required file exists: $RelativePath"
  }

  foreach ($RelativePath in @(
    'README.md',
    'p0-evidence-collection-and-adoption-contract.json',
    'source-snapshots.json',
    'reference/evidence-adoption-core.js',
    'templates/adoption-decision-template.json',
    'templates/evidence-collection-templates.json',
    'tests/test-evidence-adoption.js',
    'tests/test-execution-boundary.ps1',
    'tests/run-all.ps1'
  )) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $P0EvidenceAdoptionRoot $RelativePath) -PathType Leaf) "P0 evidence-adoption required file exists: $RelativePath"
  }

  foreach ($RelativePath in @(
    'README.md',
    'external-capture-operation-runbook.md',
    'package-contract.json',
    'reference/external-capture-onboarding-core.js',
    'templates/provider-qualification-template.json',
    'templates/source-origin-preflight-attestation-template.json',
    'templates/environment-attestation-template.json',
    'templates/canonicalization-profile-template.json',
    'templates/external-artifact-manifest-template.json',
    'templates/independent-review-handoff-template.json',
    'tests/test-external-capture-onboarding.js',
    'tests/test-execution-boundary.ps1',
    'tests/run-all.ps1'
  )) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $P0ExternalCaptureOnboardingRoot $RelativePath) -PathType Leaf) "P0 external-capture-onboarding required file exists: $RelativePath"
  }

  foreach ($RelativePath in @(
    'README.md',
    'package-contract.json',
    'tests/Invoke-TiantingY3ConstructionPreflight.ps1',
    'tests/test-preflight.ps1',
    'tests/fixtures/synthetic-complete-directory.json'
  )) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $ConstructionPreflightRoot $RelativePath) -PathType Leaf) "P1 construction-preflight required file exists: $RelativePath"
  }

  foreach ($RelativePath in @(
    'README.md',
    'surface-construction-manifest.json',
    'tests/run-all.ps1',
    'tests/test-surface-construction-manifest.ps1',
    'tests/validate-surface-construction-manifest.ps1'
  )) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $SurfaceManifestRoot $RelativePath) -PathType Leaf) "parallel surface-manifest required file exists: $RelativePath"
  }

  foreach ($RelativePath in @(
    'README.md',
    'package-contract.json',
    'reference/seven-star-session-reference.js',
    'tests/test-seven-star-session-reference.js',
    'tests/test-execution-boundary.ps1',
    'tests/run-all.ps1'
  )) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $SevenStarSessionReferenceRoot $RelativePath) -PathType Leaf) "P2 seven-star reference required file exists: $RelativePath"
  }

  foreach ($RelativePath in @(
    'README.md',
    'package-contract.json',
    'contract/mansion-session-time-qualification-reference-contract.json',
    'reference/mansion-session-model.js',
    'tests/test-mansion-session.js',
    'tests/test-package-boundary.ps1',
    'tests/run-all.ps1'
  )) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $MansionSessionReferenceRoot $RelativePath) -PathType Leaf) "P3 mansion reference required file exists: $RelativePath"
  }
  Assert-Condition (Test-Path -LiteralPath $ConstructionReadinessRunner -PathType Leaf) 'construction-readiness aggregate runner exists'

  $P0EvidenceAdoptionOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $P0EvidenceAdoptionRunner 2>&1)
  $P0EvidenceAdoptionExitCode = $LASTEXITCODE
  if ($P0EvidenceAdoptionExitCode -ne 0) {
    throw "P0 evidence-adoption validation failed (exit $P0EvidenceAdoptionExitCode): $($P0EvidenceAdoptionOutput -join [Environment]::NewLine)"
  }
  Assert-Condition (($P0EvidenceAdoptionOutput -join [Environment]::NewLine) -match 'PASS: P0 evidence-adoption run-all') 'P0 evidence-adoption runner passes fail-closed validation'

  $P0ExternalCaptureOnboardingOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $P0ExternalCaptureOnboardingRunner 2>&1)
  $P0ExternalCaptureOnboardingExitCode = $LASTEXITCODE
  if ($P0ExternalCaptureOnboardingExitCode -ne 0) {
    throw "P0 external-capture-onboarding validation failed (exit $P0ExternalCaptureOnboardingExitCode): $($P0ExternalCaptureOnboardingOutput -join [Environment]::NewLine)"
  }
  Assert-Condition (($P0ExternalCaptureOnboardingOutput -join [Environment]::NewLine) -match 'PASS: P0 external-capture-onboarding run-all') 'P0 external-capture-onboarding runner passes fail-closed validation'

  # The reservation package owns its own closed schema and provenance checks.
  # Run it in a fresh Windows PowerShell process so a master-only invocation
  # cannot bypass its fail-closed boundary by merely checking file presence.
  $ObjectFieldReservationOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ObjectFieldReservationRunner 2>&1)
  $ObjectFieldReservationExitCode = $LASTEXITCODE
  if ($ObjectFieldReservationExitCode -ne 0) {
    throw "object field reservation subpackage validation failed (exit $ObjectFieldReservationExitCode): $($ObjectFieldReservationOutput -join [Environment]::NewLine)"
  }
  Assert-Condition (($ObjectFieldReservationOutput -join [Environment]::NewLine) -match 'PASS: \d+ assertions passed for the object field reservation package\.') 'object field reservation subpackage runner passes fail-closed validation'
  $ObjectFieldReservationOutputText = $ObjectFieldReservationOutput -join [Environment]::NewLine
  $ObjectFieldReservationDigestMatch = [regex]::Match($ObjectFieldReservationOutputText, 'contract_sha256=([0-9a-f]{64})')
  if (-not $ObjectFieldReservationDigestMatch.Success) {
    throw 'object field reservation subpackage runner must report the validated contract SHA-256'
  }
  $ObjectFieldReservationValidatedDigest = $ObjectFieldReservationDigestMatch.Groups[1].Value
  $ObjectFieldReservationSnapshotBytes = [System.IO.File]::ReadAllBytes($ObjectFieldReservationContractPath)
  $ObjectFieldReservationSnapshotDigest = Get-Sha256Hex -Bytes $ObjectFieldReservationSnapshotBytes
  if ($ObjectFieldReservationSnapshotDigest -ne $ObjectFieldReservationValidatedDigest) {
    throw 'object field reservation contract changed after subpackage validation; retry from a stable snapshot'
  }
  $ObjectFieldReservationSnapshotJson = [System.Text.UTF8Encoding]::new($false).GetString($ObjectFieldReservationSnapshotBytes)
  if ($ObjectFieldReservationSnapshotJson.Length -gt 0 -and $ObjectFieldReservationSnapshotJson[0] -eq [char]0xFEFF) {
    $ObjectFieldReservationSnapshotJson = $ObjectFieldReservationSnapshotJson.Substring(1)
  }
  Assert-Condition ($ObjectFieldReservationSnapshotDigest -eq $ObjectFieldReservationValidatedDigest) 'object field reservation master snapshot exactly matches the child-validated contract'

  # Mechanism choreography is likewise a closed offline package.  Its child
  # runner owns the detailed semantic state and replay assertions; the master
  # validates the exact snapshot it certified before joining it to this package.
  $MansionEncounterOrchestrationOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $MansionEncounterOrchestrationRunner 2>&1)
  $MansionEncounterOrchestrationExitCode = $LASTEXITCODE
  if ($MansionEncounterOrchestrationExitCode -ne 0) {
    throw "mansion encounter choreography subpackage validation failed (exit $MansionEncounterOrchestrationExitCode): $($MansionEncounterOrchestrationOutput -join [Environment]::NewLine)"
  }
  Assert-Condition (($MansionEncounterOrchestrationOutput -join [Environment]::NewLine) -match 'PASS: \d+ assertions passed for the mansion encounter choreography package\.') 'mansion encounter choreography subpackage runner passes fail-closed validation'
  $MansionEncounterOrchestrationOutputText = $MansionEncounterOrchestrationOutput -join [Environment]::NewLine
  $MansionEncounterOrchestrationDigestMatch = [regex]::Match($MansionEncounterOrchestrationOutputText, 'contract_sha256=([0-9a-f]{64})')
  if (-not $MansionEncounterOrchestrationDigestMatch.Success) {
    throw 'mansion encounter choreography subpackage runner must report the validated contract SHA-256'
  }
  $MansionEncounterOrchestrationValidatedDigest = $MansionEncounterOrchestrationDigestMatch.Groups[1].Value
  $MansionEncounterOrchestrationSnapshotBytes = [System.IO.File]::ReadAllBytes($MansionEncounterOrchestrationContractPath)
  $MansionEncounterOrchestrationSnapshotDigest = Get-Sha256Hex -Bytes $MansionEncounterOrchestrationSnapshotBytes
  if ($MansionEncounterOrchestrationSnapshotDigest -ne $MansionEncounterOrchestrationValidatedDigest) {
    throw 'mansion encounter choreography contract changed after subpackage validation; retry from a stable snapshot'
  }
  $MansionEncounterOrchestrationSnapshotJson = [System.Text.UTF8Encoding]::new($false).GetString($MansionEncounterOrchestrationSnapshotBytes)
  if ($MansionEncounterOrchestrationSnapshotJson.Length -gt 0 -and $MansionEncounterOrchestrationSnapshotJson[0] -eq [char]0xFEFF) {
    $MansionEncounterOrchestrationSnapshotJson = $MansionEncounterOrchestrationSnapshotJson.Substring(1)
  }
  Assert-Condition ($MansionEncounterOrchestrationSnapshotDigest -eq $MansionEncounterOrchestrationValidatedDigest) 'mansion encounter choreography master snapshot exactly matches the child-validated contract'

  $Contract = Read-JsonFile (Join-Path $PackageRoot 'tianting-mainline-tower-contract.json')
  $Expansion = Read-JsonFile (Join-Path $PackageRoot 'tianting-content-expansion-contract.json')
  $Authority = Read-JsonFile (Join-Path $PackageRoot 'authority/tianting-progression-and-instance-authority-contract.json')
  $FirstCycle = Read-JsonFile (Join-Path $PackageRoot 'tower-first-cycle-state-contract.json')
  $Design = Read-JsonFile (Join-Path $PackageRoot 'design-spec.json')
  $Combat = Read-JsonFile (Join-Path $PackageRoot 'combat/tianting-combat-readability-contract.json')
  $CombatNumeric = Read-JsonFile (Join-Path $PackageRoot 'combat-baseline/tianting-combat-numeric-unit-baseline-contract.json')
  $EnemyEcology = Read-JsonFile (Join-Path $PackageRoot 'enemy-ecology/tianting-enemy-ecology-contract.json')
  $MainlineBoss = Read-JsonFile (Join-Path $PackageRoot 'mainline-boss/tianting-mainline-boss-contract.json')
  $Terrain = Read-JsonFile (Join-Path $PackageRoot 'terrain-layout/layout.json')
  $TerrainPreview = Read-JsonFile (Join-Path $PackageRoot 'terrain-layout/layout-preview.meta.json')
  $MapAlignment = Read-JsonFile (Join-Path $PackageRoot 'terrain-layout/tianting-map-scale-alignment-contract.json')
  $Whitebox = Read-JsonFile (Join-Path $PackageRoot 'terrain-layout/scale-alignment/layout.json')
  $WhiteboxPreview = Read-JsonFile (Join-Path $PackageRoot 'terrain-layout/scale-alignment/layout-preview.meta.json')
  $Ui = Read-JsonFile (Join-Path $PackageRoot 'ui/tianting-ui-accessibility-information-contract.json')
  $Blueprint = Read-JsonFile (Join-Path $PackageRoot 'object-blueprint/tianting-object-art-vfx-blueprint-contract.json')
  $TowerEconomy = Read-JsonFile (Join-Path $PackageRoot 'tower-economy/mansion-economy-global-tower-run-season-contract.json')
  $MainlinePresentation = Read-JsonFile (Join-Path $MainlinePresentationRoot 'tianting-mainline-presentation-contract.json')
  $ObjectFieldReservation = $ObjectFieldReservationSnapshotJson | ConvertFrom-Json
  $MansionEncounterOrchestration = $MansionEncounterOrchestrationSnapshotJson | ConvertFrom-Json
  $VerticalPackage = Read-JsonFile (Join-Path $VerticalSliceRoot 'package-contract.json')
  $CalibrationPackage = Read-JsonFile (Join-Path $CombatCalibrationRoot 'package-contract.json')
  $Calibration = Read-JsonFile (Join-Path $CombatCalibrationRoot 'contract/cross-profession-combat-calibration-contract.json')
  $P0EvidenceAdoption = Read-JsonFile (Join-Path $P0EvidenceAdoptionRoot 'p0-evidence-collection-and-adoption-contract.json')
  $P0EvidenceSourceSnapshot = Read-JsonFile (Join-Path $P0EvidenceAdoptionRoot 'source-snapshots.json')
  $P0EvidenceCollectionTemplates = Read-JsonFile (Join-Path $P0EvidenceAdoptionRoot 'templates/evidence-collection-templates.json')
  $P0EvidenceAdoptionTemplate = Read-JsonFile (Join-Path $P0EvidenceAdoptionRoot 'templates/adoption-decision-template.json')
  $P0ExternalCaptureOnboarding = Read-JsonFile (Join-Path $P0ExternalCaptureOnboardingRoot 'package-contract.json')
  $P0OnboardingProviderQualificationTemplate = Read-JsonFile (Join-Path $P0ExternalCaptureOnboardingRoot 'templates/provider-qualification-template.json')
  $P0OnboardingSourceOriginTemplate = Read-JsonFile (Join-Path $P0ExternalCaptureOnboardingRoot 'templates/source-origin-preflight-attestation-template.json')
  $P0OnboardingEnvironmentAttestationTemplate = Read-JsonFile (Join-Path $P0ExternalCaptureOnboardingRoot 'templates/environment-attestation-template.json')
  $P0OnboardingCanonicalizationTemplate = Read-JsonFile (Join-Path $P0ExternalCaptureOnboardingRoot 'templates/canonicalization-profile-template.json')
  $P0OnboardingArtifactManifestTemplate = Read-JsonFile (Join-Path $P0ExternalCaptureOnboardingRoot 'templates/external-artifact-manifest-template.json')
  $P0OnboardingIndependentReviewTemplate = Read-JsonFile (Join-Path $P0ExternalCaptureOnboardingRoot 'templates/independent-review-handoff-template.json')
  $ConstructionPreflight = Read-JsonFile (Join-Path $ConstructionPreflightRoot 'package-contract.json')
  $SurfaceManifest = Read-JsonFile (Join-Path $SurfaceManifestRoot 'surface-construction-manifest.json')
  $SevenStarSessionReference = Read-JsonFile (Join-Path $SevenStarSessionReferenceRoot 'package-contract.json')
  $MansionSessionReferencePackage = Read-JsonFile (Join-Path $MansionSessionReferenceRoot 'package-contract.json')
  $MansionSessionReference = Read-JsonFile (Join-Path $MansionSessionReferenceRoot 'contract/mansion-session-time-qualification-reference-contract.json')
  $GrowthDesignPath = Join-Path $WorkspaceRoot 'docs\物编\成长系统规格包\design-spec.json'
  Assert-Condition (Test-Path -LiteralPath $GrowthDesignPath -PathType Leaf) 'upstream growth-system design exists for global-tower adoption gate'
  $GrowthDesign = Read-JsonFile $GrowthDesignPath
  $CombatMarkdown = Get-Content -LiteralPath (Join-Path $PackageRoot 'combat/天庭战斗机制与可读性规格.md') -Raw -Encoding UTF8
  $CombatNumericMarkdown = Get-Content -LiteralPath (Join-Path $PackageRoot 'combat-baseline/天庭战斗数值与单位基线裁决.md') -Raw -Encoding UTF8
  $EnemyEcologyMarkdown = Get-Content -LiteralPath (Join-Path $PackageRoot 'enemy-ecology/天庭敌人生态与精英单位规格.md') -Raw -Encoding UTF8
  $MainlineBossMarkdown = Get-Content -LiteralPath (Join-Path $PackageRoot 'mainline-boss/天庭主线Boss深化规格.md') -Raw -Encoding UTF8
  $MainlinePresentationMarkdown = Get-Content -LiteralPath (Join-Path $MainlinePresentationRoot '天庭主线Boss叙事与表现深化规格.md') -Raw -Encoding UTF8
  $ObjectFieldReservationMarkdown = Get-Content -LiteralPath (Join-Path $ObjectFieldReservationRoot '天庭物编字段预占规格.md') -Raw -Encoding UTF8
  $MansionEncounterOrchestrationMarkdown = Get-Content -LiteralPath (Join-Path $MansionEncounterOrchestrationRoot '天庭二十八星官与四圣机制编排规格.md') -Raw -Encoding UTF8
  $MapAlignmentMarkdown = Get-Content -LiteralPath (Join-Path $PackageRoot 'terrain-layout/天庭地图口径对齐与白盒前置裁决.md') -Raw -Encoding UTF8
  $UiMarkdown = Get-Content -LiteralPath (Join-Path $PackageRoot 'ui/天庭UI与无障碍信息架构规格.md') -Raw -Encoding UTF8
  $BlueprintMarkdown = Get-Content -LiteralPath (Join-Path $PackageRoot 'object-blueprint/天庭物编美术与特效需求蓝图.md') -Raw -Encoding UTF8
  $TowerEconomyMarkdown = Get-Content -LiteralPath (Join-Path $PackageRoot 'tower-economy/星宿经济来源、全局通天塔运行与赛季裁决.md') -Raw -Encoding UTF8
  $ObjectBrief = Read-JsonFile (Join-Path $PackageRoot 'handoff/object-config-brief.json')
  $TerrainBrief = Read-JsonFile (Join-Path $PackageRoot 'handoff/terrain-layout-brief.json')
  $ExpectedP0GateIds = @(
    'P0-GATE-01-all-12-fixed-builds-declared-and-replayed',
    'P0-GATE-02-general-physical-magical-defense-formulas-adopted',
    'P0-GATE-03-hit-crit-control-formulas-adopted',
    'P0-GATE-04-engine-action-frame-and-speed-readback',
    'P0-GATE-05-terrain-collision-and-camera-fixture',
    'P0-GATE-06-authoritative-one-to-four-member-replays',
    'P0-GATE-07-stable-object-keys-and-template-readback'
  )
  $CalibrationSourceDigest = Get-Sha256Hex -Bytes ([System.IO.File]::ReadAllBytes((Join-Path $CombatCalibrationRoot 'contract/cross-profession-combat-calibration-contract.json')))
  $P0EvidenceAdoptionSourceDigest = Get-Sha256Hex -Bytes ([System.IO.File]::ReadAllBytes((Join-Path $P0EvidenceAdoptionRoot 'p0-evidence-collection-and-adoption-contract.json')))
  $ConstructionPreflightSourceDigest = Get-Sha256Hex -Bytes ([System.IO.File]::ReadAllBytes((Join-Path $ConstructionPreflightRoot 'package-contract.json')))
  $ConstructionPreflightRunnerDigest = Get-Sha256Hex -Bytes ([System.IO.File]::ReadAllBytes($ConstructionPreflightRunner))

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
  Assert-Equal $Contract.tracks.tower_first_cycle.tianting_content_reuse.artifact 'tower-economy/mansion-economy-global-tower-run-season-contract.json' 'tower content-reuse candidate artifact'
  Assert-Equal $Contract.tracks.tower_first_cycle.tianting_content_reuse.status 'tianting_offline_candidate_pending_global_tower_adoption' 'tower content-reuse remains pending global adoption'
  Assert-Equal $Contract.tracks.tower_first_cycle.tianting_content_reuse.mini_boss_cadence 'candidate_every_5_floors; ten-floor major slots would replace rather than stack with mini-boss slots if adopted' 'tower mini-Boss candidate cadence'
  Assert-Equal $Contract.tracks.tower_first_cycle.tianting_content_reuse.major_boss_cadence 'candidate_every_10_floors; four offline creative identities only if adopted' 'tower major-Boss candidate cadence'
  Assert-Null $Contract.tracks.tower_first_cycle.tianting_content_reuse.runtime_key 'tower content-reuse runtime key'

  Assert-ExactArray $Contract.source_policy.derived_offline_artifacts @(
    'combat/tianting-combat-readability-contract.json',
    'combat-baseline/tianting-combat-numeric-unit-baseline-contract.json',
    'terrain-layout/layout.json',
    'terrain-layout/tianting-map-scale-alignment-contract.json',
    'ui/tianting-ui-accessibility-information-contract.json',
    'object-blueprint/tianting-object-art-vfx-blueprint-contract.json',
    'object-preallocation/tianting-object-field-reservation-contract.json',
    'enemy-ecology/tianting-enemy-ecology-contract.json',
    'mainline-boss/tianting-mainline-boss-contract.json',
    'mainline-presentation/tianting-mainline-presentation-contract.json',
    'mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json',
    '../../../implementation/tianting-seven-star-session-reference/package-contract.json',
    '../../../implementation/tianting-mansion-session-reference/contract/mansion-session-time-qualification-reference-contract.json',
    'tower-economy/mansion-economy-global-tower-run-season-contract.json'
  ) 'main contract derived offline artifacts'
  $DerivedContractsByName = @{}
  foreach ($DerivedContract in @($Contract.adopted_offline_contracts)) {
    $DerivedContractsByName[[string]$DerivedContract.contract] = $DerivedContract
  }
  Assert-Equal $DerivedContractsByName['tianting_combat_readability'].artifact 'combat/tianting-combat-readability-contract.json' 'main contract combat derivative artifact'
  Assert-Equal $DerivedContractsByName['tianting_combat_readability'].status 'offline_design' 'main contract combat derivative status'
  Assert-Equal $DerivedContractsByName['tianting_combat_numeric_unit_baseline'].artifact 'combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' 'main contract combat-numeric derivative artifact'
  Assert-Equal $DerivedContractsByName['tianting_combat_numeric_unit_baseline'].status 'accepted_relative_balance_baseline_offline_only' 'main contract combat-numeric derivative status'
  Assert-Equal $DerivedContractsByName['tianting_terrain_layout_dry_run'].artifact 'terrain-layout/layout.json' 'main contract terrain derivative artifact'
  Assert-Equal $DerivedContractsByName['tianting_terrain_layout_dry_run'].status 'offline_dry_run_candidate' 'main contract terrain derivative status'
  Assert-Equal $DerivedContractsByName['tianting_map_scale_alignment'].artifact 'terrain-layout/tianting-map-scale-alignment-contract.json' 'main contract map-alignment artifact'
  Assert-Equal $DerivedContractsByName['tianting_map_scale_alignment'].status 'offline_preconstruction_decision' 'main contract map-alignment status'
  Assert-Equal $DerivedContractsByName['tianting_ui_accessibility_information'].artifact 'ui/tianting-ui-accessibility-information-contract.json' 'main contract UI architecture artifact'
  Assert-Equal $DerivedContractsByName['tianting_ui_accessibility_information'].status 'offline_design' 'main contract UI architecture status'
  Assert-Equal $DerivedContractsByName['tianting_object_art_vfx_blueprint'].artifact 'object-blueprint/tianting-object-art-vfx-blueprint-contract.json' 'main contract object-art blueprint artifact'
  Assert-Equal $DerivedContractsByName['tianting_object_art_vfx_blueprint'].status 'offline_design' 'main contract object-art blueprint status'
  Assert-Equal $DerivedContractsByName['tianting_object_field_reservation'].artifact 'object-preallocation/tianting-object-field-reservation-contract.json' 'main contract object field reservation artifact'
  Assert-Equal $DerivedContractsByName['tianting_object_field_reservation'].status 'offline_field_reservation_only' 'main contract object field reservation status'
  Assert-Equal $DerivedContractsByName['tianting_enemy_ecology'].artifact 'enemy-ecology/tianting-enemy-ecology-contract.json' 'main contract enemy-ecology derivative artifact'
  Assert-Equal $DerivedContractsByName['tianting_enemy_ecology'].status 'offline_design_requirements_only' 'main contract enemy-ecology derivative status'
  Assert-Equal $DerivedContractsByName['tianting_mainline_boss_deepening'].artifact 'mainline-boss/tianting-mainline-boss-contract.json' 'main contract mainline-Boss derivative artifact'
  Assert-Equal $DerivedContractsByName['tianting_mainline_boss_deepening'].status 'offline_design_requirements_only' 'main contract mainline-Boss derivative status'
  Assert-Equal $DerivedContractsByName['tianting_mainline_narrative_presentation'].artifact 'mainline-presentation/tianting-mainline-presentation-contract.json' 'main contract mainline-presentation derivative artifact'
  Assert-Equal $DerivedContractsByName['tianting_mainline_narrative_presentation'].status 'offline_narrative_presentation_spec' 'main contract mainline-presentation derivative status'
  Assert-Equal $DerivedContractsByName['tianting_mansion_encounter_orchestration'].artifact 'mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json' 'main contract mansion encounter choreography derivative artifact'
  Assert-Equal $DerivedContractsByName['tianting_mansion_encounter_orchestration'].status 'offline_encounter_choreography_spec' 'main contract mansion encounter choreography derivative status'
  Assert-Equal $DerivedContractsByName['tianting_authority_vertical_slice'].artifact '../../../implementation/tianting-authority-vertical-slice/package-contract.json' 'main contract vertical-slice artifact'
  Assert-Equal $DerivedContractsByName['tianting_authority_vertical_slice'].status 'offline_tested_reference_only' 'main contract vertical-slice status'
  Assert-Equal $DerivedContractsByName['tianting_seven_star_session_reference'].artifact '../../../implementation/tianting-seven-star-session-reference/package-contract.json' 'main contract seven-star reference artifact'
  Assert-Equal $DerivedContractsByName['tianting_seven_star_session_reference'].status 'offline_reference_model_only' 'main contract seven-star reference status'
  Assert-Equal $DerivedContractsByName['tianting_mansion_session_reference'].artifact '../../../implementation/tianting-mansion-session-reference/contract/mansion-session-time-qualification-reference-contract.json' 'main contract mansion reference artifact'
  Assert-Equal $DerivedContractsByName['tianting_mansion_session_reference'].status 'offline_reference_model_only' 'main contract mansion reference status'
  Assert-Equal $DerivedContractsByName['mansion_economy_global_tower_run_season'].artifact 'tower-economy/mansion-economy-global-tower-run-season-contract.json' 'main contract tower-economy candidate artifact'
  Assert-Equal $DerivedContractsByName['mansion_economy_global_tower_run_season'].status 'tianting_offline_candidate_pending_global_tower_adoption' 'main contract tower-economy candidate status'
  Assert-Condition ($Contract.non_production_boundaries -contains 'Candidate layout coordinates, session galleries, preview images and logic-resource candidates do not create a current Y3 map, entrance, teleport, spawn, editor resource or runtime key.') 'main contract candidate layout remains non-production'
  Assert-Condition ($Contract.non_production_boundaries -contains 'Combat readability does not create skills, battle values, progression writes, credentials, source profiles, handoff routes or settlement inputs.') 'main contract combat remains non-production'
  Assert-Condition ($Contract.non_production_boundaries -contains 'Enemy ecology and mainline Boss deepening only define readable responsibilities and interfaces; they do not create units, objects, skills, AI, waves, maps, authority writes, rewards or economy inputs.') 'main contract enemy and Boss packages remain non-production'
  Assert-Condition ($Contract.non_production_boundaries -contains 'Object field reservation only defines logical source cards and all-null future bindings; it does not create y3-object-config assets or mode, plugins, stable object keys, copyFrom templates, resources, raw fields, runtime writes or economic effects.') 'main contract object field reservation remains non-production'
  Assert-Condition ($Contract.non_production_boundaries -contains 'The combat numeric unit baseline owns only dimensionless offline coefficients and naked-player reference snapshots; it does not assign raw Y3 fields, seconds, objects, waves, authority effects, economy inputs or tower values.') 'main contract combat numeric baseline remains non-production'

  Assert-Equal $Combat.version 1 'combat readability contract version'
  Assert-Equal $Combat.package_status 'offline-design-spec' 'combat readability contract package status'
  Assert-Equal $Combat.production_gate 'closed' 'combat readability production gate'
  Assert-Equal $Combat.identity.spec_id 'TT_SPEC_TIANTING_COMBAT_READABILITY' 'combat readability identity spec id'
  Assert-Null $Combat.identity.runtime_key 'combat readability identity runtime key'
  Assert-Condition ($Combat.source_artifacts -contains '../combat-baseline/tianting-combat-numeric-unit-baseline-contract.json') 'combat readability imports canonical combat-numeric source'
  Assert-Equal $Combat.hard_boundaries.party_cap.minimum_players 1 'combat readability minimum players'
  Assert-Equal $Combat.hard_boundaries.party_cap.maximum_players 4 'combat readability maximum players'
  Assert-Null $Combat.hard_boundaries.party_cap.runtime_key 'combat readability party runtime key'
  Assert-Condition ([string]$Combat.hard_boundaries.authority_rule -match 'must not write TT_SPEC progression') 'combat readability preserves progression writer boundary'
  Assert-Condition ([string]$Combat.hard_boundaries.session_rule -match 'active_to_cleanup_pending_to_closed') 'combat readability preserves session lifecycle boundary'
  Assert-Condition ([string]$Combat.hard_boundaries.economy_rule -match 'only TT_SPEC_EVENT_LINGXIAO_OUTER_COURT_SUCCESS') 'combat readability only allows existing Lingxiao zero-value source fact'
  Assert-Condition ([string]$Combat.hard_boundaries.economy_rule -match 'seven-star, mansion-normal and mansion-nightmare success remain deferred') 'combat readability keeps non-mainline routes out of economy handoff'
  Assert-Condition ([string]$Combat.hard_boundaries.protected_difu_key_rule -match 'DF_PROGRESS_YANLUO_HALL_CLEARED') 'combat readability preserves protected Difu key boundary'
  Assert-Null $Combat.hard_boundaries.runtime_key 'combat readability boundary runtime key'
  Assert-Equal $Combat.combat_grammar.spec_id 'TT_SPEC_TIANTING_COMBAT_READABILITY_GRAMMAR' 'combat grammar spec id'
  Assert-Null $Combat.combat_grammar.runtime_key 'combat grammar runtime key'
  Assert-ExactArray $Combat.combat_grammar.loop @('read_error_order_or_stellar_pressure', 'choose_position_route_order_or_cooperation', 'counter_or_reverse_the_wrong_rule', 'use_visible_purification_window', 'retain_evidence_for_the_next_stage') 'combat readability loop order'
  Assert-Equal $Combat.combat_grammar.required_information_layers.Count 3 'combat readability information layer count'
  Assert-Condition ([string]$Combat.combat_grammar.accessibility_rule -match 'color is never the sole') 'combat readability rejects color-only signal'
  foreach ($NumericField in @('damage', 'health', 'cooldown', 'cast_time', 'movement', 'timeout', 'revive')) {
    Assert-Null $Combat.combat_grammar.numeric_values.PSObject.Properties[$NumericField].Value "combat readability numeric value remains null: $NumericField"
  }
  Assert-Null $Combat.combat_grammar.numeric_values.runtime_key 'combat readability numeric runtime key'
  Assert-Equal $Combat.numeric_baseline_reference.artifact '../combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' 'combat readability numeric baseline reference artifact'
  Assert-Equal $Combat.numeric_baseline_reference.status 'accepted_relative_balance_baseline_offline_only' 'combat readability numeric baseline reference status'
  Assert-Condition ([string]$Combat.numeric_baseline_reference.rule -match 'keeps numeric_values null') 'combat readability keeps local numeric values null'
  Assert-Null $Combat.numeric_baseline_reference.runtime_key 'combat readability numeric baseline runtime key'
  $ExpectedCombatMainlineIds = @('TT_SPEC_COMBAT_SPLIT_SOUTH_GATE', 'TT_SPEC_COMBAT_BROKEN_RAINBOW_FORMATION', 'TT_SPEC_COMBAT_FOUR_GATE_ECHO', 'TT_SPEC_COMBAT_CELESTIAL_OBSERVATORY_RIFT', 'TT_SPEC_COMBAT_LINGXIAO_OUTER_COURT')
  Assert-ExactArray (@($Combat.coverage.mainline.encounters | ForEach-Object { [string]$_.spec_id })) $ExpectedCombatMainlineIds 'combat mainline encounter coverage order'
  Assert-ExactArray $Combat.coverage.mainline.encounters[4].phases @('identify_wrong_order', 'survive_order_pressure', 'restore_verified_order') 'combat Lingxiao phase order'
  $ExpectedCombatStarNames = @('天枢', '天璇', '天玑', '天权', '玉衡', '开阳', '瑶光')
  Assert-ExactArray (@($Combat.coverage.seven_star.trials | ForEach-Object { [string]$_.star_name })) $ExpectedCombatStarNames 'combat seven-star coverage order'
  Assert-Condition ([string]$Combat.coverage.seven_star.entry_rule -match 'single-player') 'combat seven-star remains solo'
  Assert-ExactArray $Combat.coverage.mansion_normal.structure @('front_pair', 'middle_pair', 'rear_pair', 'guard_single') 'combat normal mansion segment order'
  $ExpectedCombatQuadrants = @('东方青龙', '南方朱雀', '西方白虎', '北方玄武')
  Assert-ExactArray (@($Combat.coverage.mansion_normal.quadrants | ForEach-Object { [string]$_.quadrant })) $ExpectedCombatQuadrants 'combat normal mansion quadrants'
  Assert-ExactArray $Combat.coverage.mansion_nightmare.states @('resonance_visible', 'officer_counterplay', 'purified_officer_aid', 'sacred_core_restoration') 'combat nightmare state order'
  Assert-ExactArray (@($Combat.coverage.mansion_nightmare.quadrants | ForEach-Object { [string]$_.quadrant })) $ExpectedCombatQuadrants 'combat nightmare quadrants'
  Assert-Condition ([string]$Combat.coverage.mansion_nightmare.two_way_rule -match 'seven officers grant stellar resonance') 'combat nightmare retains seven-officer-to-sacred relation'
  Assert-Condition ([string]$Combat.coverage.mansion_nightmare.two_way_rule -match 'sacred beast grants protection') 'combat nightmare retains sacred-to-seven-officer relation'
  Assert-Condition ([string]$Combat.coverage.mansion_nightmare.rotation_rule -match 'client clock') 'combat nightmare rejects client clock'
  Assert-Condition ([string]$Combat.coverage.mansion_nightmare.disconnect_rule -match 'cannot reconnect') 'combat nightmare rejects reconnect after leave'
  $ExpectedCombatAcceptance = @(1..31 | ForEach-Object { 'TT-COMBAT-ACC-{0:D3}' -f $_ })
  Assert-ExactArray $Combat.acceptance_ids $ExpectedCombatAcceptance 'combat acceptance ids'
  $CombatMarkdownAcceptance = @([regex]::Matches($CombatMarkdown, 'TT-COMBAT-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray $CombatMarkdownAcceptance $ExpectedCombatAcceptance 'combat Markdown acceptance ids'
  Assert-Null $Combat.deferred.actual_combat_numbers 'combat deferred numbers'
  Assert-Null $Combat.deferred.actual_rewards_and_receipts 'combat deferred rewards and receipts'
  Assert-Null $Combat.deferred.actual_y3_assets_and_runtime 'combat deferred Y3 runtime'
  Assert-Null $Combat.deferred.actual_map_bindings 'combat deferred map bindings'
  Assert-Null $Combat.deferred.runtime_key 'combat deferred runtime key'
  Assert-AllRuntimeKeysNull $Combat 'combat readability contract'

  # 战斗数值基线：只允许离线相对系数和既有职业裸装参照；不得把它伪装成原始物编或权威/经济合同。
  Assert-Equal $CombatNumeric.version 1 'combat numeric contract version'
  Assert-Equal $CombatNumeric.package_status 'accepted_relative_balance_baseline_offline_only' 'combat numeric package status'
  Assert-Equal $CombatNumeric.production_gate 'closed' 'combat numeric production gate'
  Assert-Equal $CombatNumeric.identity.spec_id 'TT_SPEC_TIANTING_COMBAT_NUMERIC_UNIT_BASELINE' 'combat numeric identity spec id'
  Assert-Equal $CombatNumeric.identity.scope 'tianting_mainline_seven_star_mansion_and_four_sacred_relative_combat_baseline_only' 'combat numeric identity scope'
  Assert-Null $CombatNumeric.identity.runtime_key 'combat numeric identity runtime key'
  Assert-ExactArray $CombatNumeric.hard_boundaries.chapter_level_band @(41, 60) 'combat numeric chapter level band'
  Assert-ExactArray $CombatNumeric.hard_boundaries.party_cap @(1, 4) 'combat numeric party cap'
  Assert-Equal $CombatNumeric.hard_boundaries.tower_scope 'excluded_pending_upstream_global_tower_adoption' 'combat numeric tower exclusion'
  Assert-Condition ([string]$CombatNumeric.hard_boundaries.authority_rule -match 'authority-confirmed active-member count') 'combat numeric authority input boundary'
  Assert-Condition ([string]$CombatNumeric.hard_boundaries.cross_chapter_rule -match 'DF_PROGRESS_YANLUO_HALL_CLEARED') 'combat numeric protected Difu key boundary'
  Assert-Condition ([string]$CombatNumeric.hard_boundaries.economic_rule -match 'must not define or derive experience') 'combat numeric economy boundary'
  Assert-Condition ([string]$CombatNumeric.hard_boundaries.runtime_rule -match 'remain null') 'combat numeric runtime boundary'
  Assert-Null $CombatNumeric.hard_boundaries.runtime_key 'combat numeric hard-boundary runtime key'
  Assert-Condition ($CombatNumeric.source_policy.allowed_sources -contains '../../02-破妄英雄单位与基础属性规格.md') 'combat numeric C01 source'
  Assert-Condition ($CombatNumeric.source_policy.allowed_sources -contains '../../06-镇界英雄单位与基础属性规格.md') 'combat numeric C02 source'
  Assert-Condition ($CombatNumeric.source_policy.allowed_sources -contains '../../09-持明英雄单位与基础属性规格.md') 'combat numeric C03 source'
  Assert-Condition ($CombatNumeric.source_policy.allowed_sources -contains '../../12-巡猎英雄单位与基础属性规格.md') 'combat numeric C04 source'
  Assert-Condition ($CombatNumeric.source_policy.allowed_sources -contains '../../../归档/职业设计/12-跨职业白盒战斗夹具.md') 'combat numeric calibration-fixture source'
  Assert-Null $CombatNumeric.source_policy.runtime_key 'combat numeric source-policy runtime key'

  $ExpectedCombatReferenceProfiles = @('TT_SPEC_COMBAT_REFERENCE_C01_BARE', 'TT_SPEC_COMBAT_REFERENCE_C02_BARE', 'TT_SPEC_COMBAT_REFERENCE_C03_BARE', 'TT_SPEC_COMBAT_REFERENCE_C04_BARE')
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.spec_id 'TT_SPEC_COMBAT_PLAYER_BARE_STAT_ENVELOPE' 'combat numeric player-envelope spec id'
  Assert-ExactArray @($CombatNumeric.player_bare_stat_envelope.profiles | ForEach-Object { [string]$_.spec_id }) $ExpectedCombatReferenceProfiles 'combat numeric player-envelope profiles'
  foreach ($Profile in @($CombatNumeric.player_bare_stat_envelope.profiles)) {
    Assert-ExactArray @($Profile.reference_levels | ForEach-Object { [int]$_.level }) @(41, 45, 50, 55, 60) "combat numeric reference levels: $($Profile.profession_id)"
    Assert-Null $Profile.runtime_key "combat numeric player-profile runtime key: $($Profile.profession_id)"
  }
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.profiles[0].reference_levels[0].hp_max 3340 'combat numeric C01 Lv41 HP'
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.profiles[1].reference_levels[2].defense_phy 141 'combat numeric C02 Lv50 physical defense'
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.profiles[2].reference_levels[3].primary_attack 381 'combat numeric C03 Lv55 primary attack'
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.profiles[3].reference_levels[4].hp_max 3982 'combat numeric C04 Lv60 HP'
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.aggregate_reference.Count 5 'combat numeric aggregate reference count'
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.aggregate_reference[0].mean_primary_attack 266.5 'combat numeric Lv41 mean primary attack'
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.aggregate_reference[4].mean_hp_max 4605.0 'combat numeric Lv60 mean HP'
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.range_reference.movement_speed.minimum 3.55 'combat numeric movement minimum reference'
  Assert-Equal $CombatNumeric.player_bare_stat_envelope.range_reference.attack_interval.maximum 1.15 'combat numeric attack-interval maximum reference'
  Assert-Null $CombatNumeric.player_bare_stat_envelope.runtime_key 'combat numeric player-envelope runtime key'

  Assert-Equal $CombatNumeric.relative_scalar_system.spec_id 'TT_SPEC_COMBAT_RELATIVE_SCALAR_SYSTEM' 'combat numeric scalar-system spec id'
  $ExpectedScalarSymbols = @('H0', 'A0', 'M0', 'I0', 'R0', 'B0', 'O0', 'S0')
  Assert-ExactArray @($CombatNumeric.relative_scalar_system.scalars | ForEach-Object { [string]$_.symbol }) $ExpectedScalarSymbols 'combat numeric scalar symbols'
  foreach ($Scalar in @($CombatNumeric.relative_scalar_system.scalars)) {
    Assert-Equal $Scalar.relative_value 1.0 "combat numeric scalar relative value: $($Scalar.symbol)"
    Assert-Null $Scalar.absolute_runtime_value "combat numeric scalar absolute value remains null: $($Scalar.symbol)"
  }
  Assert-Null $CombatNumeric.relative_scalar_system.runtime_key 'combat numeric scalar-system runtime key'

  Assert-Equal $CombatNumeric.party_scaling.spec_id 'TT_SPEC_COMBAT_PARTY_SCALING_BASELINE' 'combat numeric party-scaling spec id'
  Assert-ExactArray $CombatNumeric.party_scaling.member_counts @(1, 2, 3, 4) 'combat numeric party member counts'
  Assert-ExactArray @($CombatNumeric.party_scaling.profiles | ForEach-Object { [string]$_.profile_id }) @('single_owner', 'small_monster', 'elite', 'mainline_boss', 'mansion_officer', 'sacred_beast') 'combat numeric party-scaling profiles'
  Assert-ExactArray $CombatNumeric.party_scaling.profiles[0].allowed_member_counts @(1) 'combat numeric single-owner member count'
  Assert-ExactNumericArray $CombatNumeric.party_scaling.profiles[0].exposure_multiplier @(1.0) 'combat numeric single-owner exposure scaling'
  Assert-ExactNumericArray $CombatNumeric.party_scaling.profiles[1].exposure_multiplier @(1.0, 1.0, 1.0, 1.0) 'combat numeric small-monster exposure scaling'
  Assert-ExactNumericArray $CombatNumeric.party_scaling.profiles[2].exposure_multiplier @(1.0, 1.35, 1.70, 2.05) 'combat numeric elite exposure scaling'
  Assert-ExactNumericArray $CombatNumeric.party_scaling.profiles[3].exposure_multiplier @(1.0, 1.50, 2.00, 2.50) 'combat numeric mainline-Boss exposure scaling'
  Assert-ExactNumericArray $CombatNumeric.party_scaling.profiles[4].exposure_multiplier @(1.0, 1.45, 1.90, 2.35) 'combat numeric mansion-officer exposure scaling'
  Assert-ExactNumericArray $CombatNumeric.party_scaling.profiles[5].exposure_multiplier @(1.0, 1.50, 2.00, 2.50) 'combat numeric sacred-beast exposure scaling'
  foreach ($PropertyName in @('movement_speed', 'attack_interval', 'p0_window', 'counter_window')) {
    Assert-Equal $CombatNumeric.party_scaling.invariant_multipliers.PSObject.Properties[$PropertyName].Value 1.0 "combat numeric party invariant multiplier: $PropertyName"
  }
  Assert-Equal $CombatNumeric.party_scaling.pressure_slot_limit.one_member.primary_p0_sources 1 'combat numeric solo primary P0 slot limit'
  Assert-Equal $CombatNumeric.party_scaling.pressure_slot_limit.two_to_four_members.secondary_pressures 2 'combat numeric party secondary-pressure slot limit'
  Assert-Null $CombatNumeric.party_scaling.runtime_key 'combat numeric party-scaling runtime key'

  $ExpectedCombatEnemyIds = @(
    'TT_SPEC_ENEMY_CONTROLLED_CELESTIAL_SOLDIER',
    'TT_SPEC_ELITE_FOUR_GATE_GUARD_MECHANISM',
    'TT_SPEC_ELITE_UNCONTROLLED_CLOUD_BEAST',
    'TT_SPEC_ELITE_GENERIC_STAR_OBSERVER',
    'TT_SPEC_ENTITY_PATROL_SIGNAL_ECHO',
    'TT_SPEC_ENTITY_BROKEN_RAINBOW_FORMATION_EYE',
    'TT_SPEC_ENTITY_STAR_CALENDAR_RIFT',
    'TT_SPEC_ENTITY_FRACTURED_LAW_COMMAND_NODE',
    'TT_SPEC_ENTITY_SEVEN_STAR_RULE_ECHO',
    'TT_SPEC_ENTITY_MANSION_ORIENTATION_ECHO',
    'TT_SPEC_ENTITY_NIGHTMARE_RESONANCE_SUPPORT'
  )
  Assert-ExactArray @($CombatNumeric.enemy_ecology_unit_baselines | ForEach-Object { [string]$_.spec_id }) $ExpectedCombatEnemyIds 'combat numeric enemy coverage order'
  Assert-ExactArray @($EnemyEcology.taxonomy | ForEach-Object { [string]$_.spec_id }) $ExpectedCombatEnemyIds 'combat numeric enemy coverage matches ecology taxonomy'
  Assert-Equal $CombatNumeric.enemy_ecology_unit_baselines[0].stat_basis.effective_health.coefficient 1.0 'combat numeric controlled-soldier health coefficient'
  Assert-Equal $CombatNumeric.enemy_ecology_unit_baselines[2].stat_basis.movement.coefficient 1.20 'combat numeric cloud-beast movement coefficient'
  Assert-Equal $CombatNumeric.enemy_ecology_unit_baselines[3].stat_basis.effective_health.coefficient 1.55 'combat numeric star-observer health coefficient'
  foreach ($Mechanism in @($CombatNumeric.enemy_ecology_unit_baselines | Where-Object { $_.unit_class -eq 'relation_mechanism' })) {
    Assert-Null $Mechanism.combat_stats "combat numeric relation mechanism combat stats remain null: $($Mechanism.spec_id)"
    Assert-Null $Mechanism.runtime_key "combat numeric relation mechanism runtime key: $($Mechanism.spec_id)"
  }

  $ExpectedCombatMainlineBossIds = @('TT_SPEC_MAINLINE_BOSS_SPLIT_SOUTH_GATE', 'TT_SPEC_MAINLINE_BOSS_BROKEN_RAINBOW_FORMATION', 'TT_SPEC_MAINLINE_BOSS_FOUR_GATE_IMBALANCE', 'TT_SPEC_MAINLINE_BOSS_CELESTIAL_OBSERVATORY', 'TT_SPEC_MAINLINE_BOSS_LINGXIAO_OUTER_COURT')
  Assert-ExactArray @($CombatNumeric.mainline_boss_baselines | ForEach-Object { [string]$_.spec_id }) $ExpectedCombatMainlineBossIds 'combat numeric mainline-Boss coverage order'
  Assert-ExactArray @($MainlineBoss.bosses | ForEach-Object { [string]$_.spec_id }) $ExpectedCombatMainlineBossIds 'combat numeric mainline-Boss coverage matches deepening contract'
  foreach ($Boss in @($CombatNumeric.mainline_boss_baselines)) {
    Assert-Equal $Boss.party_profile_id 'mainline_boss' "combat numeric mainline-Boss party profile: $($Boss.spec_id)"
    Assert-Equal @($Boss.phase_exposure_budget).Count 3 "combat numeric mainline-Boss phase budget count: $($Boss.spec_id)"
    foreach ($PhaseBudget in @($Boss.phase_exposure_budget)) {
      Assert-Equal $PhaseBudget.symbol 'B0' "combat numeric mainline-Boss phase scalar: $($Boss.spec_id)"
      Assert-Condition ([double]$PhaseBudget.coefficient -gt 0) "combat numeric mainline-Boss phase coefficient positive: $($Boss.spec_id)"
    }
    Assert-Condition ([double]$Boss.p0_window.minimum_coefficient -ge 1.25) "combat numeric mainline-Boss P0 minimum: $($Boss.spec_id)"
    Assert-Condition ([double]$Boss.counter_window.minimum_coefficient -ge 1.0) "combat numeric mainline-Boss counter minimum: $($Boss.spec_id)"
    Assert-Null $Boss.runtime_key "combat numeric mainline-Boss runtime key: $($Boss.spec_id)"
  }
  Assert-Equal $CombatNumeric.mainline_boss_baselines[4].phase_exposure_budget[0].coefficient 1.60 'combat numeric Lingxiao phase coefficient'

  $ExpectedCombatSevenStarIds = @('TT_SPEC_SOLO_TIANSHU', 'TT_SPEC_SOLO_TIANXUAN', 'TT_SPEC_SOLO_TIANJI', 'TT_SPEC_SOLO_TIANQUAN', 'TT_SPEC_SOLO_YUHENG', 'TT_SPEC_SOLO_KAIYANG', 'TT_SPEC_SOLO_YAOGUANG')
  Assert-ExactArray @($CombatNumeric.seven_star_trial_baselines | ForEach-Object { [string]$_.spec_id }) $ExpectedCombatSevenStarIds 'combat numeric seven-star coverage order'
  Assert-ExactArray @($CombatNumeric.seven_star_trial_baselines | ForEach-Object { [int]$_.trial_index }) @(1, 2, 3, 4, 5, 6, 7) 'combat numeric seven-star trial order'
  foreach ($Trial in @($CombatNumeric.seven_star_trial_baselines)) {
    Assert-Equal $Trial.party_profile_id 'single_owner' "combat numeric seven-star owner-only profile: $($Trial.spec_id)"
    Assert-Equal $Trial.exposure_budget.symbol 'B0' "combat numeric seven-star exposure scalar: $($Trial.spec_id)"
    Assert-Null $Trial.runtime_key "combat numeric seven-star runtime key: $($Trial.spec_id)"
  }

  $ExpectedMansionOfficerIds = @($Expansion.twenty_eight_mansions_raid.quadrants | ForEach-Object { @($_.officers | ForEach-Object { [string]$_.spec_id }) })
  $ActualMansionOfficerIds = @($CombatNumeric.mansion_officer_baselines.quadrant_assignments | ForEach-Object { @($_.officers | ForEach-Object { [string]$_.spec_id }) })
  Assert-ExactArray $ActualMansionOfficerIds $ExpectedMansionOfficerIds 'combat numeric mansion-officer coverage matches content contract'
  Assert-Equal $ActualMansionOfficerIds.Count 28 'combat numeric mansion-officer coverage count'
  Assert-ExactArray @($CombatNumeric.mansion_officer_baselines.segment_profiles | ForEach-Object { [string]$_.profile_id }) @('front_pair', 'middle_pair', 'rear_pair', 'guard_single') 'combat numeric mansion segment-profile order'
  foreach ($QuadrantAssignment in @($CombatNumeric.mansion_officer_baselines.quadrant_assignments)) {
    Assert-Equal @($QuadrantAssignment.officers).Count 7 "combat numeric mansion quadrant officer count: $($QuadrantAssignment.quadrant)"
    Assert-ExactArray @($QuadrantAssignment.officers | ForEach-Object { [string]$_.profile_id }) @('front_pair', 'front_pair', 'middle_pair', 'middle_pair', 'rear_pair', 'rear_pair', 'guard_single') "combat numeric mansion segment assignment: $($QuadrantAssignment.quadrant)"
  }
  Assert-Null $CombatNumeric.mansion_officer_baselines.runtime_key 'combat numeric mansion baseline runtime key'

  $ExpectedSacredIds = @($Expansion.twenty_eight_mansions_raid.quadrants | ForEach-Object { [string]$_.sacred_beast_spec_id })
  Assert-ExactArray @($CombatNumeric.four_sacred_nightmare_baselines | ForEach-Object { [string]$_.spec_id }) $ExpectedSacredIds 'combat numeric sacred-beast coverage matches content contract'
  foreach ($Sacred in @($CombatNumeric.four_sacred_nightmare_baselines)) {
    Assert-Equal $Sacred.party_profile_id 'sacred_beast' "combat numeric sacred party profile: $($Sacred.spec_id)"
    Assert-Equal $Sacred.core_exposure_budget.symbol 'S0' "combat numeric sacred core scalar: $($Sacred.spec_id)"
    Assert-Condition ([double]$Sacred.core_exposure_budget.coefficient -gt 3.0) "combat numeric sacred core coefficient: $($Sacred.spec_id)"
    Assert-Null $Sacred.runtime_key "combat numeric sacred runtime key: $($Sacred.spec_id)"
  }
  Assert-Equal $CombatNumeric.nightmare_resonance_relative_rule.spec_id 'TT_SPEC_NIGHTMARE_RESONANCE_RELATIVE_BASELINE' 'combat numeric nightmare-resonance spec id'
  Assert-Equal $CombatNumeric.nightmare_resonance_relative_rule.seven_officer_to_sacred_core_exposure_multiplier_per_active_link 0.10 'combat numeric nightmare core-link coefficient'
  Assert-Equal $CombatNumeric.nightmare_resonance_relative_rule.sacred_to_officer_pressure_multiplier_per_active_link 0.06 'combat numeric nightmare officer-link coefficient'
  Assert-ExactArray $CombatNumeric.nightmare_resonance_relative_rule.active_link_count @(0, 1, 2, 3, 4, 5, 6, 7) 'combat numeric nightmare active-link counts'
  Assert-Null $CombatNumeric.nightmare_resonance_relative_rule.runtime_key 'combat numeric nightmare-resonance runtime key'

  Assert-Equal $CombatNumeric.calibration_gate.spec_id 'TT_SPEC_COMBAT_ABSOLUTE_VALUE_CALIBRATION_GATE' 'combat numeric calibration-gate spec id'
  Assert-Equal $CombatNumeric.calibration_gate.status 'blocked_pending_runtime_evidence' 'combat numeric calibration-gate status'
  Assert-Equal $CombatNumeric.calibration_gate.canonical_p0_gate_source.artifact '../../../../implementation/combat-calibration/contract/cross-profession-combat-calibration-contract.json' 'combat numeric canonical P0 artifact'
  Assert-Equal $CombatNumeric.calibration_gate.canonical_p0_gate_source.contract_id 'CAL_SPEC_CROSS_PROFESSION_ABSOLUTE_COMBAT_V1' 'combat numeric canonical P0 contract id'
  Assert-Equal $CombatNumeric.calibration_gate.canonical_p0_gate_source.source_content_sha256 $CalibrationSourceDigest 'combat numeric canonical P0 source digest'
  Assert-Equal $CombatNumeric.calibration_gate.canonical_p0_gate_source.evidence_collection_artifact '../../../../implementation/combat-calibration/evidence-adoption/p0-evidence-collection-and-adoption-contract.json' 'combat numeric P0 evidence-adoption artifact'
  Assert-Equal $CombatNumeric.calibration_gate.canonical_p0_gate_source.evidence_collection_spec_id 'CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1' 'combat numeric P0 evidence-adoption spec id'
  Assert-ExactArray $CombatNumeric.calibration_gate.canonical_p0_gate_source.current_satisfied_gate_ids @() 'combat numeric canonical P0 satisfied gates'
  Assert-ExactArray $CombatNumeric.calibration_gate.must_exist_before_absolute_projection $ExpectedP0GateIds 'combat numeric calibration-gate canonical evidence sequence'
  Assert-ExactArray $CombatNumeric.calibration_gate.human_readable_evidence_summary @(
    '12 complete fixed builds with three deterministic replays each',
    'general physical, magical, defense and penetration formulas',
    'hit, crit and control-resistance formulas',
    'real Y3 action-frame, attack-speed and move-speed readback',
    'real terrain, collision, pathing and camera fixture',
    'authoritative one-to-four-member replays without authority mutation',
    'stable object keys, templates and field readback'
  ) 'combat numeric calibration-gate readable evidence sequence'
  Assert-Equal $CombatNumeric.calibration_gate.existing_offline_fixture.status 'read_only_calibration_input_not_tianting_unit_data' 'combat numeric calibration fixture status'
  Assert-Equal $CombatNumeric.calibration_gate.existing_offline_fixture.lv60_reference_target_defense_phy 180 'combat numeric calibration fixture defense value'
  Assert-Null $CombatNumeric.calibration_gate.absolute_object_field_projection 'combat numeric absolute object projection remains null'
  Assert-Null $CombatNumeric.calibration_gate.runtime_key 'combat numeric calibration-gate runtime key'
  foreach ($Property in $CombatNumeric.runtime_bindings.PSObject.Properties) {
    Assert-Null $Property.Value "combat numeric runtime binding: $($Property.Name)"
  }
  $ExpectedCombatNumericAcceptance = @(1..27 | ForEach-Object { 'TT-NUM-ACC-{0:D3}' -f $_ })
  Assert-ExactArray $CombatNumeric.acceptance_ids $ExpectedCombatNumericAcceptance 'combat numeric acceptance id index'
  Assert-ExactArray (@($CombatNumeric.acceptance | ForEach-Object { [string]$_.id })) $ExpectedCombatNumericAcceptance 'combat numeric acceptance ids'
  $CombatNumericMarkdownAcceptance = @([regex]::Matches($CombatNumericMarkdown, 'TT-NUM-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray $CombatNumericMarkdownAcceptance $ExpectedCombatNumericAcceptance 'combat numeric Markdown acceptance ids'
  Assert-NoForbiddenPropertyNames $CombatNumeric @('reward_exp', 'xp_amount', 'currency_amount', 'drop_probability', 'pity_threshold', 'source_profile', 'reward_slot_key', 'qualification_snapshot_id', 'receipt_id', 'settlement_request') 'combat numeric contract'
  Assert-AllRuntimeKeysNull $CombatNumeric 'combat numeric contract'

  # 敌人生态：只能补齐非通天塔职责与可读性，不能成为对象、波次、经济或首领替身。
  Assert-Equal $EnemyEcology.schema_version 1 'enemy ecology schema version'
  Assert-Equal $EnemyEcology.identity.spec_id 'TT_SPEC_TIANTING_ENEMY_ECOLOGY' 'enemy ecology identity spec id'
  Assert-Equal $EnemyEcology.identity.status 'offline_design_requirements_only' 'enemy ecology identity status'
  Assert-Equal $EnemyEcology.identity.production_gate 'closed' 'enemy ecology production gate'
  foreach ($FieldName in @('runtimeKey', 'objectId', 'unitId', 'resourceId')) {
    Assert-Null $EnemyEcology.identity.PSObject.Properties[$FieldName].Value "enemy ecology identity deferred field: $FieldName"
  }
  Assert-Condition ($EnemyEcology.scope.excluded -contains '通天塔层、塔Boss、塔地图、塔经济、赛季和内容抽取') 'enemy ecology excludes tower content'
  Assert-Condition ($EnemyEcology.scope.excluded -contains '进度、资格、成员快照、轮换、清理、奖励、掉落、材料、货币、收据和结算') 'enemy ecology excludes authority and economy outputs'
  Assert-Condition (@($EnemyEcology.source_contracts | Where-Object { $_.path -eq '../combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' }).Count -eq 1) 'enemy ecology references sole combat-numeric source'
  Assert-Condition (@($EnemyEcology.design_invariants | Where-Object { [string]$_ -match '本合同只引用独立数值裁决的无量纲系数' }).Count -eq 1) 'enemy ecology preserves external relative-only numeric boundary'
  $ExpectedEnemyTaxonomy = @(
    'TT_SPEC_ENEMY_CONTROLLED_CELESTIAL_SOLDIER',
    'TT_SPEC_ELITE_FOUR_GATE_GUARD_MECHANISM',
    'TT_SPEC_ELITE_UNCONTROLLED_CLOUD_BEAST',
    'TT_SPEC_ELITE_GENERIC_STAR_OBSERVER',
    'TT_SPEC_ENTITY_PATROL_SIGNAL_ECHO',
    'TT_SPEC_ENTITY_BROKEN_RAINBOW_FORMATION_EYE',
    'TT_SPEC_ENTITY_STAR_CALENDAR_RIFT',
    'TT_SPEC_ENTITY_FRACTURED_LAW_COMMAND_NODE',
    'TT_SPEC_ENTITY_SEVEN_STAR_RULE_ECHO',
    'TT_SPEC_ENTITY_MANSION_ORIENTATION_ECHO',
    'TT_SPEC_ENTITY_NIGHTMARE_RESONANCE_SUPPORT'
  )
  Assert-ExactArray (@($EnemyEcology.taxonomy | ForEach-Object { [string]$_.spec_id })) $ExpectedEnemyTaxonomy 'enemy ecology taxonomy order'
  foreach ($Ecology in @($EnemyEcology.taxonomy)) {
    Assert-Condition ([string]$Ecology.spec_id -match '^TT_SPEC_') "enemy ecology spec identity: $($Ecology.design_identity)"
    foreach ($Property in $Ecology.runtime.PSObject.Properties) {
      Assert-Null $Property.Value "enemy ecology taxonomy runtime binding: $($Ecology.spec_id)/$($Property.Name)"
    }
  }
  Assert-ExactArray $EnemyEcology.boss_ownership_guards.protected_bosses @('千里眼', '顺风耳', '巨灵神', '监律天将', '七星首领', '二十八星官', '四圣兽') 'enemy ecology protected Boss guard order'
  Assert-Condition ($EnemyEcology.authority_and_economy_boundaries.presentation_and_design_only -eq $true) 'enemy ecology is presentation and design only'
  Assert-Condition ($EnemyEcology.authority_and_economy_boundaries.forbidden_authority_mutations -contains 'progression') 'enemy ecology cannot mutate progression'
  Assert-Condition ($EnemyEcology.authority_and_economy_boundaries.forbidden_authority_mutations -contains 'session_state') 'enemy ecology cannot mutate session state'
  Assert-Condition ($EnemyEcology.authority_and_economy_boundaries.forbidden_economic_outputs -contains 'settlement') 'enemy ecology cannot produce settlement'
  foreach ($Property in $EnemyEcology.runtime_binding.PSObject.Properties) {
    Assert-Null $Property.Value "enemy ecology runtime binding: $($Property.Name)"
  }
  $ExpectedEnemyAcceptance = @(1..30 | ForEach-Object { 'TT-ENEMY-ACC-{0:D3}' -f $_ })
  Assert-ExactArray (@($EnemyEcology.acceptance | ForEach-Object { [string]$_.id })) $ExpectedEnemyAcceptance 'enemy ecology acceptance ids'
  $EnemyMarkdownAcceptance = @([regex]::Matches($EnemyEcologyMarkdown, 'TT-ENEMY-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray $EnemyMarkdownAcceptance $ExpectedEnemyAcceptance 'enemy ecology Markdown acceptance ids'
  Assert-AllRuntimeKeysNull $EnemyEcology 'enemy ecology contract'

  # 主线 Boss 深化：五组首领级遭遇只提供施工前可读性，不改写会话或经济。
  Assert-Equal $MainlineBoss.version 1 'mainline Boss contract version'
  Assert-Equal $MainlineBoss.package_status 'offline-design-spec' 'mainline Boss package status'
  Assert-Equal $MainlineBoss.production_gate 'closed' 'mainline Boss production gate'
  Assert-Equal $MainlineBoss.identity.spec_id 'TT_SPEC_TIANTING_MAINLINE_BOSS_DEEPENING' 'mainline Boss identity spec id'
  Assert-Equal $MainlineBoss.identity.scope 'non_tower_tianting_mainline_boss_readability_only' 'mainline Boss scope'
  Assert-Null $MainlineBoss.identity.runtime_key 'mainline Boss identity runtime key'
  Assert-Condition ($MainlineBoss.source_artifacts -contains '../enemy-ecology/tianting-enemy-ecology-contract.json') 'mainline Boss imports the canonical enemy-ecology source'
  Assert-Condition ($MainlineBoss.source_artifacts -contains '../combat-baseline/tianting-combat-numeric-unit-baseline-contract.json') 'mainline Boss imports the canonical combat-numeric source'
  Assert-Condition ($MainlineBoss.hard_boundaries.excluded_content -contains 'tongtian_tower') 'mainline Boss excludes tower content'
  Assert-Condition ($MainlineBoss.hard_boundaries.excluded_content -contains 'rewards') 'mainline Boss excludes rewards'
  Assert-Condition ([string]$MainlineBoss.hard_boundaries.authority_rule -match 'must not decide admission') 'mainline Boss preserves authority boundary'
  Assert-Condition ([string]$MainlineBoss.hard_boundaries.economy_rule -match 'no XP') 'mainline Boss preserves economy boundary'
  Assert-Equal $MainlineBoss.shared_readability_grammar.spec_id 'TT_SPEC_MAINLINE_BOSS_READABILITY_GRAMMAR' 'mainline Boss readability grammar spec id'
  Assert-Null $MainlineBoss.shared_readability_grammar.runtime_key 'mainline Boss readability grammar runtime key'
  Assert-Condition ($MainlineBoss.shared_readability_grammar.p0_requirements.color_as_only_carrier -eq 'forbidden') 'mainline Boss rejects color-only P0'
  foreach ($Property in $MainlineBoss.shared_readability_grammar.combat_numeric_values.PSObject.Properties) {
    Assert-Null $Property.Value "mainline Boss numeric value remains null: $($Property.Name)"
  }
  Assert-Equal $MainlineBoss.numeric_baseline_reference.artifact '../combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' 'mainline Boss numeric baseline reference artifact'
  Assert-Equal $MainlineBoss.numeric_baseline_reference.status 'accepted_relative_balance_baseline_offline_only' 'mainline Boss numeric baseline reference status'
  Assert-Condition ([string]$MainlineBoss.numeric_baseline_reference.rule -match 'keeps its local combat_numeric_values null') 'mainline Boss keeps local numeric fields null'
  Assert-Null $MainlineBoss.numeric_baseline_reference.runtime_key 'mainline Boss numeric baseline runtime key'
  $ExpectedMainlineBossIds = @(
    'TT_SPEC_MAINLINE_BOSS_SPLIT_SOUTH_GATE',
    'TT_SPEC_MAINLINE_BOSS_BROKEN_RAINBOW_FORMATION',
    'TT_SPEC_MAINLINE_BOSS_FOUR_GATE_IMBALANCE',
    'TT_SPEC_MAINLINE_BOSS_CELESTIAL_OBSERVATORY',
    'TT_SPEC_MAINLINE_BOSS_LINGXIAO_OUTER_COURT'
  )
  Assert-ExactArray (@($MainlineBoss.bosses | ForEach-Object { [string]$_.spec_id })) $ExpectedMainlineBossIds 'mainline Boss identity order'
  foreach ($Boss in @($MainlineBoss.bosses)) {
    Assert-Condition ([string]$Boss.spec_id -match '^TT_SPEC_') "mainline Boss spec identity: $($Boss.display_name)"
    Assert-Condition (@($Boss.phase_grammar).Count -ge 3) "mainline Boss has phase grammar: $($Boss.spec_id)"
    foreach ($Role in @($Boss.roles)) {
      Assert-Condition ([string]$Role.spec_id -match '^TT_SPEC_') "mainline Boss role spec identity: $($Boss.spec_id)"
      Assert-Null $Role.runtime_binding "mainline Boss role runtime binding: $($Role.spec_id)"
    }
    foreach ($Phase in @($Boss.phase_grammar)) {
      Assert-Condition ([string]$Phase.spec_id -match '^TT_SPEC_') "mainline Boss phase spec identity: $($Boss.spec_id)"
      Assert-Condition (@($Phase.p0_telegraphs).Count -gt 0) "mainline Boss P0 exists: $($Phase.spec_id)"
      foreach ($FieldName in @('decision', 'counterplay', 'visible_result', 'failure_debrief', 'field_responsibility')) {
        Assert-Condition (Test-HasProperty $Phase $FieldName) "mainline Boss phase required field exists: $($Phase.spec_id)/$FieldName"
      }
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Phase.decision)) "mainline Boss phase decision is non-empty: $($Phase.spec_id)"
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Phase.counterplay)) "mainline Boss phase counterplay is non-empty: $($Phase.spec_id)"
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Phase.visible_result)) "mainline Boss phase visible result is non-empty: $($Phase.spec_id)"
      Assert-Condition (@($Phase.failure_debrief).Count -gt 0) "mainline Boss phase failure debrief is non-empty: $($Phase.spec_id)"
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Phase.field_responsibility)) "mainline Boss phase field responsibility is non-empty: $($Phase.spec_id)"
      Assert-Null $Phase.runtime_binding "mainline Boss phase runtime binding: $($Phase.spec_id)"
    }
    Assert-Null $Boss.party_adaptation.runtime_key "mainline Boss party-adaptation runtime key: $($Boss.spec_id)"
    Assert-Null $Boss.minion_elite_interface.spawn_wave_ai_object_and_numbers "mainline Boss minion interface remains deferred: $($Boss.spec_id)"
    foreach ($Property in $Boss.runtime_bindings.PSObject.Properties) {
      Assert-Null $Property.Value "mainline Boss runtime binding: $($Boss.spec_id)/$($Property.Name)"
    }
  }
  $ExpectedMainlineBossEcologyById = @{
    'TT_SPEC_MAINLINE_BOSS_SPLIT_SOUTH_GATE' = @('TT_SPEC_ENEMY_CONTROLLED_CELESTIAL_SOLDIER', 'TT_SPEC_ENTITY_PATROL_SIGNAL_ECHO')
    'TT_SPEC_MAINLINE_BOSS_BROKEN_RAINBOW_FORMATION' = @('TT_SPEC_ENEMY_CONTROLLED_CELESTIAL_SOLDIER', 'TT_SPEC_ENTITY_BROKEN_RAINBOW_FORMATION_EYE')
    'TT_SPEC_MAINLINE_BOSS_FOUR_GATE_IMBALANCE' = @('TT_SPEC_ELITE_UNCONTROLLED_CLOUD_BEAST', 'TT_SPEC_ELITE_FOUR_GATE_GUARD_MECHANISM')
    'TT_SPEC_MAINLINE_BOSS_CELESTIAL_OBSERVATORY' = @('TT_SPEC_ELITE_GENERIC_STAR_OBSERVER', 'TT_SPEC_ENTITY_STAR_CALENDAR_RIFT')
    'TT_SPEC_MAINLINE_BOSS_LINGXIAO_OUTER_COURT' = @('TT_SPEC_ENTITY_FRACTURED_LAW_COMMAND_NODE')
  }
  foreach ($Boss in @($MainlineBoss.bosses)) {
    $BossId = [string]$Boss.spec_id
    Assert-Condition ($ExpectedMainlineBossEcologyById.ContainsKey($BossId)) "mainline Boss has ecology mapping: $BossId"
    Assert-ExactArray @($Boss.minion_elite_interface.ecology_spec_ids) @($ExpectedMainlineBossEcologyById[$BossId]) "mainline Boss ecology mapping: $BossId"
    foreach ($EcologySpecId in @($Boss.minion_elite_interface.ecology_spec_ids)) {
      Assert-Condition ($ExpectedEnemyTaxonomy -contains [string]$EcologySpecId) "mainline Boss ecology identity exists in enemy contract: $BossId/$EcologySpecId"
      Assert-Condition ($MainlineBossMarkdown -match [regex]::Escape([string]$EcologySpecId)) "mainline Boss Markdown mirrors ecology identity: $BossId/$EcologySpecId"
    }
  }
  Assert-Equal $MainlineBoss.cross_boss_minion_elite_rule.spec_id 'TT_SPEC_MAINLINE_BOSS_MINION_ELITE_INTERFACE' 'mainline Boss minion interface spec id'
  Assert-Equal $MainlineBoss.cross_boss_minion_elite_rule.permitted_interface_families.Count 5 'mainline Boss minion interface family count'
  Assert-Equal $MainlineBoss.cross_boss_minion_elite_rule.ecology_contract '../enemy-ecology/tianting-enemy-ecology-contract.json' 'mainline Boss ecology contract reference'
  Assert-Condition ([string]$MainlineBoss.cross_boss_minion_elite_rule.ecology_mapping_rule -match 'existing TT_SPEC ecology identities') 'mainline Boss ecology mapping rule'
  Assert-Null $MainlineBoss.cross_boss_minion_elite_rule.objects_skills_buffs_ai_waves_and_numbers 'mainline Boss cross-interface runtime content'
  Assert-Null $MainlineBoss.cross_boss_minion_elite_rule.runtime_key 'mainline Boss cross-interface runtime key'
  $ExpectedMainlineBossAcceptance = @(1..30 | ForEach-Object { 'TT-MAINLINE-BOSS-ACC-{0:D3}' -f $_ })
  Assert-ExactArray $MainlineBoss.acceptance_ids $ExpectedMainlineBossAcceptance 'mainline Boss acceptance id index'
  Assert-ExactArray (@($MainlineBoss.acceptance | ForEach-Object { [string]$_.id })) $ExpectedMainlineBossAcceptance 'mainline Boss acceptance ids'
  $MainlineBossMarkdownAcceptance = @([regex]::Matches($MainlineBossMarkdown, 'TT-MAINLINE-BOSS-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray $MainlineBossMarkdownAcceptance $ExpectedMainlineBossAcceptance 'mainline Boss Markdown acceptance ids'
  foreach ($Property in $MainlineBoss.deferred.PSObject.Properties) {
    Assert-Null $Property.Value "mainline Boss deferred field: $($Property.Name)"
  }
  Assert-AllRuntimeKeysNull $MainlineBoss 'mainline Boss contract'

  Assert-Equal $Terrain.version 1 'terrain layout version'
  Assert-Equal $Terrain.mode 'preview' 'terrain layout preview mode'
  Assert-Equal $Terrain.documentStatus 'offline-dry-run-candidate' 'terrain layout document status'
  Assert-Equal $Terrain.identity.spec_id 'TT_SPEC_TIANTING_TERRAIN_LAYOUT_DRY_RUN' 'terrain layout identity spec id'
  Assert-Null $Terrain.identity.runtime_key 'terrain layout identity runtime key'
  Assert-Equal $Terrain.map.id 'TT_MAP_CANDIDATE_PUBLIC_ROUTE_ATLAS' 'terrain public-map candidate id'
  Assert-Equal $Terrain.map.width 640 'terrain public-map candidate width'
  Assert-Equal $Terrain.map.height 416 'terrain public-map candidate height'
  Assert-Equal $Terrain.map.status 'diagram-only-not-editor-map' 'terrain public-map is diagram only'
  Assert-Null $Terrain.map.actualMapKey 'terrain public-map actual map key'
  Assert-Equal $Terrain.candidateMapSizes.Count 6 'terrain candidate-map size count'
  foreach ($CandidateMap in @($Terrain.candidateMapSizes)) {
    Assert-Null $CandidateMap.actualMapKey "terrain candidate map actual key: $($CandidateMap.id)"
  }
  Assert-Equal $Terrain.regions.Count 10 'terrain public-region count'
  Assert-Equal $Terrain.routes.Count 6 'terrain route count'
  Assert-Equal $Terrain.bossZones.Count 4 'terrain boss-zone count'
  Assert-Condition (@($Terrain.spawns).Count -eq 0) 'terrain creates no spawns'
  Assert-Condition (@($Terrain.decorations).Count -eq 0) 'terrain creates no decorations'
  Assert-Condition (@($Terrain.logicResources).Count -eq 0) 'terrain creates no editor logic resources'
  Assert-Condition (@($Terrain.assetSearchPlan | Where-Object { $null -ne $_.resourceId }).Count -eq 0) 'terrain asset search keeps all resource ids null'
  foreach ($CandidateLogic in @($Terrain.logicResourceCandidates)) {
    Assert-Null $CandidateLogic.editorResourceId "terrain logic candidate editor resource id: $($CandidateLogic.candidateId)"
    Assert-Null $CandidateLogic.runtimeKey "terrain logic candidate runtime key: $($CandidateLogic.candidateId)"
    Assert-Equal $CandidateLogic.status 'not-created' "terrain logic candidate not created: $($CandidateLogic.candidateId)"
  }
  $ExpectedTerrainSessionIds = @('TT_SESSION_CANDIDATE_LINGXIAO_MAINLINE', 'TT_SESSION_CANDIDATE_SEVEN_STAR_TIANSHU', 'TT_SESSION_CANDIDATE_SEVEN_STAR_TIANXUAN', 'TT_SESSION_CANDIDATE_SEVEN_STAR_TIANJI', 'TT_SESSION_CANDIDATE_SEVEN_STAR_TIANQUAN', 'TT_SESSION_CANDIDATE_SEVEN_STAR_YUHENG', 'TT_SESSION_CANDIDATE_SEVEN_STAR_KAIYANG', 'TT_SESSION_CANDIDATE_SEVEN_STAR_YAOGUANG', 'TT_SESSION_CANDIDATE_MANSION_AZURE_DRAGON_NORMAL', 'TT_SESSION_CANDIDATE_MANSION_VERMILION_BIRD_NORMAL', 'TT_SESSION_CANDIDATE_MANSION_WHITE_TIGER_NORMAL', 'TT_SESSION_CANDIDATE_MANSION_BLACK_TORTOISE_NORMAL', 'TT_SESSION_CANDIDATE_MANSION_AZURE_DRAGON_NIGHTMARE', 'TT_SESSION_CANDIDATE_MANSION_VERMILION_BIRD_NIGHTMARE', 'TT_SESSION_CANDIDATE_MANSION_WHITE_TIGER_NIGHTMARE', 'TT_SESSION_CANDIDATE_MANSION_BLACK_TORTOISE_NIGHTMARE')
  Assert-ExactArray (@($Terrain.sessionMapCandidates | ForEach-Object { [string]$_.id })) $ExpectedTerrainSessionIds 'terrain session-map candidate order'
  foreach ($SessionMap in @($Terrain.sessionMapCandidates)) {
    Assert-Null $SessionMap.actualMapKey "terrain session candidate map key: $($SessionMap.id)"
    Assert-Null $SessionMap.actualEntrance "terrain session candidate entrance: $($SessionMap.id)"
    Assert-Null $SessionMap.actualTeleport "terrain session candidate teleport: $($SessionMap.id)"
  }
  $TerrainNormalQuadrants = @($Terrain.sessionMapCandidates | Where-Object { [string]$_.sessionKind -eq 'raid-normal-1-to-4' } | ForEach-Object { [string]$_.quadrant })
  $TerrainNightmareQuadrants = @($Terrain.sessionMapCandidates | Where-Object { [string]$_.sessionKind -eq 'raid-nightmare-1-to-4' } | ForEach-Object { [string]$_.quadrant })
  Assert-ExactArray $TerrainNormalQuadrants $ExpectedCombatQuadrants 'terrain normal mansion quadrants'
  Assert-ExactArray $TerrainNightmareQuadrants $ExpectedCombatQuadrants 'terrain nightmare mansion quadrants'
  Assert-Equal $Terrain.constructionHandoff.writePolicy 'no Y3Maker/Y3 MCP write in this package; every layer remains a future confirmation-required construction candidate.' 'terrain no-write policy'
  Assert-Equal $Terrain.preview.status 'rendered' 'terrain preview status'
  Assert-Equal $TerrainPreview.status 'rendered' 'terrain preview metadata status'
  Assert-Equal $TerrainPreview.renderer 'chrome-headless' 'terrain preview metadata renderer'

  # 地图口径与白盒：640x416 图解、224x80 容量带和白盒候选不可互相物化。
  Assert-Equal $MapAlignment.version 1 'map-scale alignment contract version'
  Assert-Equal $MapAlignment.identity.spec_id 'TT_SPEC_TIANTING_MAP_SCALE_ALIGNMENT' 'map-scale alignment spec id'
  Assert-Equal $MapAlignment.identity.status 'offline-preconstruction-decision' 'map-scale alignment status'
  Assert-Null $MapAlignment.identity.runtime_key 'map-scale alignment runtime key'
  Assert-Equal $MapAlignment.source_status.production_gate 'closed' 'map-scale alignment production gate'
  Assert-Condition ($MapAlignment.source_status.actual_map_write -eq $false) 'map-scale alignment performs no map write'
  Assert-Condition ($MapAlignment.source_status.actual_resource_binding -eq $false) 'map-scale alignment performs no resource binding'
  Assert-Condition ($MapAlignment.source_status.actual_runtime_integration -eq $false) 'map-scale alignment performs no runtime integration'
  Assert-Equal $MapAlignment.coordinate_spaces.global_first_release_canvas.width 384 'global map inference width'
  Assert-Equal $MapAlignment.coordinate_spaces.global_first_release_canvas.height 320 'global map inference height'
  Assert-Null $MapAlignment.coordinate_spaces.global_first_release_canvas.actual_map_key 'global map inference actual key'
  Assert-Equal $MapAlignment.coordinate_spaces.heavenly_band_envelope.width 224 'heavenly capacity envelope width'
  Assert-Equal $MapAlignment.coordinate_spaces.heavenly_band_envelope.height 80 'heavenly capacity envelope height'
  Assert-Null $MapAlignment.coordinate_spaces.heavenly_band_envelope.actual_map_key 'heavenly capacity envelope actual key'
  Assert-Condition ($MapAlignment.coordinate_spaces.tianting_layout_diagram.is_terrain_cell -eq $false) '640x416 layout is not terrain cells'
  Assert-Condition ($MapAlignment.coordinate_spaces.tianting_layout_diagram.is_world_coordinate -eq $false) '640x416 layout is not world coordinates'
  Assert-Condition ($MapAlignment.coordinate_spaces.tianting_layout_diagram.is_runtime_map_dimension -eq $false) '640x416 layout is not runtime map dimensions'
  Assert-Equal $MapAlignment.selected_mapping_strategy.status 'selected-for-offline-whitebox-only' 'map mapping stays offline whitebox only'
  Assert-Equal $MapAlignment.selected_mapping_strategy.global_resize 'not-authorized' 'map mapping does not resize global map'
  Assert-Equal $MapAlignment.public_whitebox_allocation.occupied_width 200 'public whitebox occupied width'
  Assert-Equal $MapAlignment.public_whitebox_allocation.occupied_height 64 'public whitebox occupied height'
  Assert-Condition ($MapAlignment.public_whitebox_allocation.within_heavenly_band -eq $true) 'public whitebox remains inside heavenly capacity envelope'
  Assert-Equal $MapAlignment.public_whitebox_allocation.scenes.Count 2 'map alignment has two public whitebox scenes'
  foreach ($WhiteboxScene in @($MapAlignment.public_whitebox_allocation.scenes)) {
    Assert-Null $WhiteboxScene.actual_map_key "map alignment public scene actual map key: $($WhiteboxScene.spec_id)"
    Assert-Null $WhiteboxScene.actual_entrance "map alignment public scene actual entrance: $($WhiteboxScene.spec_id)"
    Assert-Null $WhiteboxScene.actual_teleport "map alignment public scene actual teleport: $($WhiteboxScene.spec_id)"
    Assert-Null $WhiteboxScene.actual_spawn "map alignment public scene actual spawn: $($WhiteboxScene.spec_id)"
    Assert-Condition (@($WhiteboxScene.actual_logic_resource_ids).Count -eq 0) "map alignment public scene has no logic resources: $($WhiteboxScene.spec_id)"
  }
  Assert-Equal $MapAlignment.session_whitebox_envelopes.Count 4 'map alignment session whitebox envelope count'
  foreach ($SessionEnvelope in @($MapAlignment.session_whitebox_envelopes)) {
    Assert-Null $SessionEnvelope.actual_map_key "map alignment session envelope actual map key: $($SessionEnvelope.spec_id)"
  }
  Assert-Condition ($MapAlignment.authority_and_economy_boundary.map_is_not_authority -eq $true) 'map alignment does not adjudicate authority'
  Assert-Condition ($MapAlignment.authority_and_economy_boundary.map_is_not_economy -eq $true) 'map alignment does not adjudicate economy'
  Assert-Condition ($MapAlignment.authority_and_economy_boundary.forbidden_progression_keys -contains 'DF_PROGRESS_YANLUO_HALL_CLEARED') 'map alignment preserves protected Difu key boundary'
  Assert-Condition ([string]$MapAlignment.authority_and_economy_boundary.unchanged_economy_rule -match 'Lingxiao') 'map alignment preserves Lingxiao-only source boundary'
  $ExpectedMapAcceptance = @(1..15 | ForEach-Object { 'TT-MAP-ACC-{0:D3}' -f $_ })
  Assert-ExactArray (@($MapAlignment.whitebox_acceptance | ForEach-Object { [string]$_.id })) $ExpectedMapAcceptance 'map alignment acceptance ids'
  $MapMarkdownAcceptance = @([regex]::Matches($MapAlignmentMarkdown, 'TT-MAP-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray $MapMarkdownAcceptance $ExpectedMapAcceptance 'map alignment Markdown acceptance ids'
  Assert-Null $MapAlignment.runtime_key 'map alignment contract runtime key'
  Assert-AllRuntimeKeysNull $MapAlignment 'map-scale alignment contract'

  Assert-Equal $Whitebox.version 1 'whitebox layout version'
  Assert-Equal $Whitebox.mode 'preview' 'whitebox layout preview mode'
  Assert-Equal $Whitebox.documentStatus 'offline-whitebox-candidate' 'whitebox layout document status'
  Assert-Equal $Whitebox.identity.spec_id 'TT_SPEC_TIANTING_HEAVENLY_BAND_WHITEBOX' 'whitebox layout spec id'
  Assert-Null $Whitebox.identity.runtime_key 'whitebox layout runtime key'
  Assert-Equal $Whitebox.map.width 224 'whitebox candidate map width'
  Assert-Equal $Whitebox.map.height 80 'whitebox candidate map height'
  Assert-Equal $Whitebox.map.status 'candidate-only-not-editor-map' 'whitebox candidate is not an editor map'
  Assert-Null $Whitebox.map.actualMapKey 'whitebox candidate actual map key'
  Assert-Equal $Whitebox.sceneEnvelopes.Count 2 'whitebox public scene count'
  foreach ($WhiteboxScene in @($Whitebox.sceneEnvelopes)) {
    Assert-Equal $WhiteboxScene.status 'candidate-only-not-editor-map' "whitebox scene remains a candidate: $($WhiteboxScene.id)"
    Assert-Null $WhiteboxScene.actualMapKey "whitebox scene actual map key: $($WhiteboxScene.id)"
  }
  Assert-Equal $Whitebox.chapterBoundaries.Count 1 'whitebox chapter-boundary count'
  $ChapterBoundary = $Whitebox.chapterBoundaries[0]
  Assert-Equal $ChapterBoundary.id 'TT_WB_ROUTE_GATE_TO_INNER' 'whitebox chapter-boundary id'
  Assert-Equal $ChapterBoundary.transitionKind 'chapter_boundary_transition' 'whitebox chapter-boundary transition kind'
  Assert-Condition ($ChapterBoundary.traversable -eq $false) 'whitebox chapter boundary is non-traversable'
  Assert-Equal $ChapterBoundary.nonTraversableGapCells 8 'whitebox chapter boundary gap size'
  Assert-Null $ChapterBoundary.runtimeKey 'whitebox chapter-boundary runtime key'
  Assert-Condition (@($Whitebox.routes | Where-Object { $_.id -eq 'TT_WB_ROUTE_GATE_TO_INNER' }).Count -eq 0) 'whitebox non-traversable boundary is not drawn as a route'
  Assert-ExactArray (@($Whitebox.routes | ForEach-Object { [string]$_.id })) @('TT_WB_ROUTE_INNER_TO_OBSERVATORY') 'whitebox traversable readability route set'
  Assert-Condition (@($Whitebox.spawns).Count -eq 0) 'whitebox creates no spawns'
  Assert-Condition (@($Whitebox.decorations).Count -eq 0) 'whitebox creates no decorations'
  Assert-Condition (@($Whitebox.logicResources).Count -eq 0) 'whitebox creates no logic resources'
  Assert-Equal $Whitebox.preview.status 'rendered' 'whitebox preview status'
  Assert-Equal $Whitebox.preview.renderer 'chrome-headless' 'whitebox preview renderer'
  Assert-Equal $WhiteboxPreview.status 'rendered' 'whitebox preview metadata status'
  Assert-Equal $WhiteboxPreview.renderer 'chrome-headless' 'whitebox preview metadata renderer'

  # UI 是权威结果展示层；不产生本地裁决、资格或经济写入。
  Assert-Equal $Ui.version 1 'UI architecture contract version'
  Assert-Equal $Ui.package_status 'offline-design-spec' 'UI architecture package status'
  Assert-Equal $Ui.production_gate 'closed' 'UI architecture production gate'
  Assert-Equal $Ui.artifact_kind 'offline_information_architecture_contract_not_y3_ui_json' 'UI architecture artifact kind'
  Assert-Equal $Ui.identity.spec_id 'TT_SPEC_TIANTING_UI_ACCESSIBILITY_INFORMATION_ARCHITECTURE' 'UI architecture spec id'
  foreach ($FieldName in @('runtime_key', 'ui_node_id', 'asset_id', 'icon_id', 'sound_id', 'effect_id', 'text_template_id', 'event_id', 'save_key')) {
    Assert-Null $Ui.identity.PSObject.Properties[$FieldName].Value "UI identity deferred field: $FieldName"
  }
  Assert-Condition ([string]$Ui.global_boundaries.authority_display_rule -match 'cannot be inferred') 'UI cannot infer authority facts'
  Assert-Condition ([string]$Ui.global_boundaries.dual_channel_rule -match 'Color is never the sole') 'UI rejects color-only critical warnings'
  Assert-Condition ([string]$Ui.global_boundaries.request_result_separation_rule -match 'never becomes') 'UI keeps request and authority result separate'
  Assert-Condition ([string]$Ui.global_boundaries.economy_rule -match 'No panel creates') 'UI cannot create economy input'
  Assert-Condition ([string]$Ui.global_boundaries.protected_difu_key_rule -match 'DF_PROGRESS_YANLUO_HALL_CLEARED') 'UI preserves protected Difu key boundary'
  Assert-Equal $Ui.information_surfaces.Count 7 'UI information surface count'
  foreach ($Surface in @($Ui.information_surfaces)) {
    Assert-Condition ([string]$Surface.spec_id -match '^TT_SPEC_') "UI surface spec identity: $($Surface.display_name)"
    Assert-Null $Surface.runtime_key "UI surface runtime key: $($Surface.spec_id)"
    Assert-Null $Surface.ui_node_id "UI surface node id: $($Surface.spec_id)"
    Assert-Null $Surface.asset_id "UI surface asset id: $($Surface.spec_id)"
  }
  $ExpectedUiAcceptance = @(1..24 | ForEach-Object { 'TT-UI-ACC-{0:D3}' -f $_ })
  Assert-ExactArray (@($Ui.acceptance | ForEach-Object { [string]$_.id })) $ExpectedUiAcceptance 'UI architecture acceptance ids'
  $UiMarkdownAcceptance = @([regex]::Matches($UiMarkdown, 'TT-UI-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray (@($UiMarkdownAcceptance | Sort-Object)) (@($ExpectedUiAcceptance | Sort-Object)) 'UI architecture Markdown acceptance ids'
  foreach ($Property in $Ui.deferred.PSObject.Properties) {
    Assert-Null $Property.Value "UI deferred field: $($Property.Name)"
  }
  Assert-AllRuntimeKeysNull $Ui 'UI architecture contract'

  # 物编/美术/特效蓝图只能提出可读性需求，所有真实对象和经济字段仍为空。
  Assert-Equal $Blueprint.schema_version 1 'object-art blueprint schema version'
  Assert-Equal $Blueprint.identity.spec_id 'TT_SPEC_TIANTING_OBJECT_ART_VFX_BLUEPRINT' 'object-art blueprint spec id'
  Assert-Equal $Blueprint.identity.status 'offline_design_requirements_only' 'object-art blueprint status'
  Assert-Equal $Blueprint.identity.production_gate 'closed' 'object-art blueprint production gate'
  Assert-Null $Blueprint.identity.runtime_key 'object-art blueprint runtime key'
  Assert-Null $Blueprint.identity.object_id 'object-art blueprint object id'
  Assert-Null $Blueprint.identity.resource_id 'object-art blueprint resource id'
  Assert-Condition ($Blueprint.scope.excluded -contains 'Y3对象、物编插件、Y3 JSON、Lua、地图或逻辑资源') 'object-art blueprint excludes Y3 implementation'
  foreach ($Property in $Blueprint.runtime_binding.PSObject.Properties) {
    Assert-Null $Property.Value "object-art runtime binding: $($Property.Name)"
  }
  Assert-Condition ($Blueprint.authority_and_economy_boundaries.presentation_only -eq $true) 'object-art blueprint is presentation only'
  Assert-Condition ($Blueprint.authority_and_economy_boundaries.forbidden_authority_mutations -contains 'progression') 'object-art blueprint cannot mutate progression'
  Assert-Condition ($Blueprint.authority_and_economy_boundaries.forbidden_economic_outputs -contains 'settlement') 'object-art blueprint cannot produce settlement'
  Assert-Equal $Blueprint.visual_grammar.priority_levels.Count 3 'object-art blueprint priority level count'
  Assert-Equal $Blueprint.visual_grammar.vfx_layers.Count 5 'object-art blueprint VFX layer count'
  $ExpectedBlueprintAcceptance = @(1..31 | ForEach-Object { 'TT-BLUEPRINT-ACC-{0:D3}' -f $_ })
  Assert-ExactArray (@($Blueprint.acceptance | ForEach-Object { [string]$_.id })) $ExpectedBlueprintAcceptance 'object-art blueprint acceptance ids'
  $BlueprintMarkdownAcceptance = @([regex]::Matches($BlueprintMarkdown, 'TT-BLUEPRINT-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray (@($BlueprintMarkdownAcceptance | Sort-Object)) (@($ExpectedBlueprintAcceptance | Sort-Object)) 'object-art blueprint Markdown acceptance ids'
  Assert-AllRuntimeKeysNull $Blueprint 'object-art blueprint contract'

  # 物编字段预占只冻结逻辑身份、可读性与全空字段；它不是可生成的 y3-object-config 输入。
  Assert-Equal $ObjectFieldReservation.schema_version 1 'object field reservation schema version'
  Assert-Equal $ObjectFieldReservation.identity.spec_id 'TT_SPEC_TIANTING_OBJECT_FIELD_RESERVATION' 'object field reservation spec id'
  Assert-Equal $ObjectFieldReservation.identity.package_status 'offline_field_reservation_only' 'object field reservation status'
  Assert-Equal $ObjectFieldReservation.identity.production_gate 'closed' 'object field reservation production gate'
  Assert-Condition ($ObjectFieldReservation.identity.plugin_generation -eq $false) 'object field reservation disables plugin generation'
  foreach ($FieldName in @('runtime_key', 'normalized_design_input', 'generated_plugin')) {
    Assert-Null $ObjectFieldReservation.identity.PSObject.Properties[$FieldName].Value "object field reservation identity remains null: $FieldName"
  }
  Assert-NoForbiddenPropertyNames $ObjectFieldReservation @('assets', 'mode') 'object field reservation contract'
  Assert-ExactArray $ObjectFieldReservation.gate_snapshot.required_gate_ids @('P0-GATE-01-all-12-fixed-builds-declared-and-replayed', 'P0-GATE-02-general-physical-magical-defense-formulas-adopted', 'P0-GATE-03-hit-crit-control-formulas-adopted', 'P0-GATE-04-engine-action-frame-and-speed-readback', 'P0-GATE-05-terrain-collision-and-camera-fixture', 'P0-GATE-06-authoritative-one-to-four-member-replays', 'P0-GATE-07-stable-object-keys-and-template-readback') 'object field reservation P0 gate snapshot'
  Assert-Equal @($ObjectFieldReservation.gate_snapshot.currently_satisfied_gate_ids).Count 0 'object field reservation has no satisfied P0 gate'
  Assert-Equal $ObjectFieldReservation.gate_snapshot.absolute_projection_candidate_id 'TT_CAL_ABSOLUTE_OBJECT_FIELDS_V1' 'object field reservation absolute projection candidate'
  Assert-Equal $ObjectFieldReservation.gate_snapshot.object_resource_inventory.source_spec_id 'TT_DISCOVERY_OBJECT_AND_RESOURCE_INVENTORY' 'object field reservation inventory source'
  Assert-Condition ($ObjectFieldReservation.gate_snapshot.object_resource_inventory.write_authorization -eq $false) 'object field reservation inventory prohibits writes'
  foreach ($FieldName in @('stable_object_keys', 'approved_templates', 'field_reference', 'model_animation_vfx_sfx_resources')) {
    Assert-Null $ObjectFieldReservation.gate_snapshot.object_resource_inventory.PSObject.Properties[$FieldName].Value "object field reservation inventory remains null: $FieldName"
  }
  $ObjectReservationEvidenceSource = $ObjectFieldReservation.gate_snapshot.evidence_adoption_source
  Assert-Equal $ObjectReservationEvidenceSource.artifact '../../../../implementation/combat-calibration/evidence-adoption/p0-evidence-collection-and-adoption-contract.json' 'object field reservation direct P0 evidence-adoption artifact'
  Assert-Equal $ObjectReservationEvidenceSource.spec_id 'CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1' 'object field reservation direct P0 evidence-adoption spec id'
  Assert-Equal $ObjectReservationEvidenceSource.source_content_sha256 $P0EvidenceAdoptionSourceDigest 'object field reservation direct P0 evidence-adoption digest'
  Assert-Equal $ObjectReservationEvidenceSource.current_adoption_state 'closed' 'object field reservation direct P0 evidence-adoption state'
  Assert-ExactArray $ObjectReservationEvidenceSource.currently_satisfied_gate_ids @() 'object field reservation direct P0 evidence-adoption satisfied gates'
  foreach ($FieldName in @('actual_capture_provider', 'actual_y3_project_ref', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload')) {
    Assert-Null $ObjectReservationEvidenceSource.PSObject.Properties[$FieldName].Value "object field reservation direct P0 evidence-adoption deferred field: $FieldName"
  }
  $ObjectReservationEvidenceSourceContract = @($ObjectFieldReservation.source_contracts | Where-Object { $_.artifact -eq $ObjectReservationEvidenceSource.artifact })
  Assert-Equal $ObjectReservationEvidenceSourceContract.Count 1 'object field reservation has one direct P0 evidence-adoption source contract'
  if ($ObjectReservationEvidenceSourceContract.Count -eq 1) {
    Assert-Equal $ObjectReservationEvidenceSourceContract[0].spec_id $ObjectReservationEvidenceSource.spec_id 'object field reservation direct P0 evidence-adoption source spec consistency'
    Assert-Equal $ObjectReservationEvidenceSourceContract[0].source_content_sha256 $P0EvidenceAdoptionSourceDigest 'object field reservation direct P0 evidence-adoption source digest consistency'
  }
  $ReservationBinding = @($ObjectFieldReservation.field_reservation_profiles | Where-Object { $_.spec_id -eq 'TT_SPEC_OBJRES_ALL_NULL_BINDINGS' })
  Assert-Equal $ReservationBinding.Count 1 'object field reservation all-null binding profile count'
  $ReservationBinding = $ReservationBinding[0]
  foreach ($BindingGroupName in @('future_object_binding', 'future_resource_binding', 'absolute_projection', 'future_runtime_binding')) {
    foreach ($Property in $ReservationBinding.PSObject.Properties[$BindingGroupName].Value.PSObject.Properties) {
      Assert-Null $Property.Value "object field reservation deferred field: $BindingGroupName/$($Property.Name)"
    }
  }
  $ExpectedReservationGroupCounts = @{
    'TT_SPEC_OBJRES_GROUP_ENEMY_ECOLOGY' = 11
    'TT_SPEC_OBJRES_GROUP_MAINLINE' = 5
    'TT_SPEC_OBJRES_GROUP_SEVEN_STAR' = 7
    'TT_SPEC_OBJRES_GROUP_TWENTY_EIGHT_MANSIONS' = 28
    'TT_SPEC_OBJRES_GROUP_FOUR_SACRED' = 4
  }
  Assert-Equal @($ObjectFieldReservation.logical_asset_groups).Count 5 'object field reservation source group count'
  foreach ($GroupId in $ExpectedReservationGroupCounts.Keys) {
    $ReservationGroup = @($ObjectFieldReservation.logical_asset_groups | Where-Object { $_.group_id -eq $GroupId })
    Assert-Equal $ReservationGroup.Count 1 "object field reservation group exists: $GroupId"
    Assert-Equal @($ReservationGroup[0].cards).Count $ExpectedReservationGroupCounts[$GroupId] "object field reservation group card count: $GroupId"
  }
  $AllReservationCards = @($ObjectFieldReservation.logical_asset_groups | ForEach-Object { $_.cards })
  Assert-Equal $AllReservationCards.Count 55 'object field reservation total source card coverage'
  Assert-Equal @($AllReservationCards | ForEach-Object { $_.reservation_id } | Sort-Object -Unique).Count $AllReservationCards.Count 'object field reservation identities are unique'
  Assert-Equal @($AllReservationCards | ForEach-Object { $_.source_selector } | Sort-Object -Unique).Count $AllReservationCards.Count 'object field reservation source selectors are unique'
  foreach ($ReservationCard in $AllReservationCards) {
    Assert-Condition ([string]$ReservationCard.reservation_id -match '^TT_SPEC_OBJRES_') "object field reservation card identity: $($ReservationCard.display_name)"
    Assert-Condition ([string]$ReservationCard.source_selector -match '^TT_SPEC_') "object field reservation source identity: $($ReservationCard.reservation_id)"
    Assert-Equal @($ReservationCard.semantic_skill_slots).Count 3 "object field reservation three semantic slots: $($ReservationCard.reservation_id)"
    Assert-Condition (@($ReservationCard.p0_spatial_signals).Count -gt 0) "object field reservation P0 signal: $($ReservationCard.reservation_id)"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$ReservationCard.independent_channel)) "object field reservation second channel: $($ReservationCard.reservation_id)"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$ReservationCard.counterplay_result)) "object field reservation counterplay: $($ReservationCard.reservation_id)"
    Assert-Equal $ReservationCard.future_binding_profile_ref 'TT_SPEC_OBJRES_ALL_NULL_BINDINGS' "object field reservation all-null binding: $($ReservationCard.reservation_id)"
    Assert-Null $ReservationCard.runtime_key "object field reservation runtime key: $($ReservationCard.reservation_id)"
  }
  $WeiTuZhiReservation = @($AllReservationCards | Where-Object { $_.source_selector -eq 'TT_SPEC_MANSION_WEI_TU_ZHI' })
  Assert-Equal $WeiTuZhiReservation.Count 1 'object field reservation has one canonical Wei Tu Zhi card'
  Assert-Equal @($WeiTuZhiReservation[0].alias_policy.aliases).Count 1 'object field reservation keeps one Wei Tu Zhi alias without duplicate officer'
  $ExpectedObjectReservationAcceptance = @(1..8 | ForEach-Object { 'TT-OBJRES-ACC-{0:D3}' -f $_ })
  Assert-ExactArray (@($ObjectFieldReservation.acceptance | ForEach-Object { [string]$_.id })) $ExpectedObjectReservationAcceptance 'object field reservation acceptance ids'
  $ObjectReservationMarkdownAcceptance = @([regex]::Matches($ObjectFieldReservationMarkdown, 'TT-OBJRES-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray $ObjectReservationMarkdownAcceptance $ExpectedObjectReservationAcceptance 'object field reservation Markdown acceptance ids'
  foreach ($Property in $ObjectFieldReservation.hard_boundaries.authority_and_economy.PSObject.Properties) {
    if ($Property.Name -ne 'authority_state_input') {
      Assert-Null $Property.Value "object field reservation authority/economy remains null: $($Property.Name)"
    }
  }
  foreach ($Property in $ObjectFieldReservation.hard_boundaries.current_outputs.PSObject.Properties) {
    Assert-Null $Property.Value "object field reservation current output remains null: $($Property.Name)"
  }
  Assert-AllRuntimeKeysNull $ObjectFieldReservation 'object field reservation contract'

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
  Assert-Equal $Expansion.hard_boundaries.economy.current_handoff_route_rule '当前只有既有凌霄主线成功可形成零价值来源事实候选；七星、普通星宿和噩梦星宿成功仍不得成为 handoff candidate、资格或结算输入。' 'content expansion current economy handoff route'
  Assert-Condition ($Expansion.hard_boundaries.economy.forbidden_embedded_values -contains 'xp_amount') 'content expansion prohibits embedded XP'
  Assert-Condition ($Expansion.hard_boundaries.economy.forbidden_embedded_values -contains 'drop_probability') 'content expansion prohibits drop probability'
  Assert-Condition ($Expansion.hard_boundaries.economy.forbidden_embedded_values -contains 'material_drop_count') 'content expansion prohibits material-drop count'
  Assert-Equal $Expansion.hard_boundaries.tower_identity.rule 'linglong_theme_within_global_tongtian_tower' 'content expansion tower identity'
  Assert-Equal $Expansion.hard_boundaries.tower_identity.must_not_create 'a_second_long_term_tower_system' 'content expansion second-tower prohibition'
  Assert-Null $Expansion.hard_boundaries.tower_identity.runtime_key 'content expansion tower identity runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.combat_readability.artifact 'combat/tianting-combat-readability-contract.json' 'content expansion combat derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.combat_readability.status 'offline_design' 'content expansion combat derivative status'
  Assert-Null $Expansion.derivative_offline_specs.combat_readability.runtime_key 'content expansion combat derivative runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.combat_numeric_unit_baseline.artifact 'combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' 'content expansion combat-numeric derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.combat_numeric_unit_baseline.status 'accepted_relative_balance_baseline_offline_only' 'content expansion combat-numeric derivative status'
  Assert-Condition ([string]$Expansion.derivative_offline_specs.combat_numeric_unit_baseline.rule -match '无量纲相对系数') 'content expansion combat-numeric relative-only rule'
  Assert-Null $Expansion.derivative_offline_specs.combat_numeric_unit_baseline.runtime_key 'content expansion combat-numeric derivative runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.terrain_layout.artifact 'terrain-layout/layout.json' 'content expansion terrain derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.terrain_layout.status 'offline_dry_run_candidate' 'content expansion terrain derivative status'
  Assert-Null $Expansion.derivative_offline_specs.terrain_layout.runtime_key 'content expansion terrain derivative runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.map_scale_alignment.artifact 'terrain-layout/tianting-map-scale-alignment-contract.json' 'content expansion map-alignment derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.map_scale_alignment.status 'offline_preconstruction_decision' 'content expansion map-alignment derivative status'
  Assert-Equal $Expansion.derivative_offline_specs.ui_accessibility_information.artifact 'ui/tianting-ui-accessibility-information-contract.json' 'content expansion UI derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.ui_accessibility_information.status 'offline_design' 'content expansion UI derivative status'
  Assert-Equal $Expansion.derivative_offline_specs.object_art_vfx_blueprint.artifact 'object-blueprint/tianting-object-art-vfx-blueprint-contract.json' 'content expansion object-art derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.object_art_vfx_blueprint.status 'offline_design' 'content expansion object-art derivative status'
  Assert-Equal $Expansion.derivative_offline_specs.object_field_reservation.artifact 'object-preallocation/tianting-object-field-reservation-contract.json' 'content expansion object field reservation derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.object_field_reservation.status 'offline_field_reservation_only' 'content expansion object field reservation derivative status'
  Assert-Null $Expansion.derivative_offline_specs.object_field_reservation.runtime_key 'content expansion object field reservation runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.enemy_ecology.artifact 'enemy-ecology/tianting-enemy-ecology-contract.json' 'content expansion enemy-ecology derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.enemy_ecology.status 'offline_design_requirements_only' 'content expansion enemy-ecology derivative status'
  Assert-Null $Expansion.derivative_offline_specs.enemy_ecology.runtime_key 'content expansion enemy-ecology runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.mainline_boss_deepening.artifact 'mainline-boss/tianting-mainline-boss-contract.json' 'content expansion mainline-Boss derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.mainline_boss_deepening.status 'offline_design_requirements_only' 'content expansion mainline-Boss derivative status'
  Assert-Null $Expansion.derivative_offline_specs.mainline_boss_deepening.runtime_key 'content expansion mainline-Boss runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.mainline_narrative_presentation.artifact 'mainline-presentation/tianting-mainline-presentation-contract.json' 'content expansion mainline-presentation derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.mainline_narrative_presentation.status 'offline_narrative_presentation_spec' 'content expansion mainline-presentation derivative status'
  Assert-Null $Expansion.derivative_offline_specs.mainline_narrative_presentation.runtime_key 'content expansion mainline-presentation runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.mansion_encounter_orchestration.artifact 'mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json' 'content expansion mansion encounter choreography derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.mansion_encounter_orchestration.status 'offline_encounter_choreography_spec' 'content expansion mansion encounter choreography derivative status'
  Assert-Null $Expansion.derivative_offline_specs.mansion_encounter_orchestration.runtime_key 'content expansion mansion encounter choreography derivative runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.seven_star_session_reference.artifact '../../../implementation/tianting-seven-star-session-reference/package-contract.json' 'content expansion seven-star reference artifact'
  Assert-Equal $Expansion.derivative_offline_specs.seven_star_session_reference.status 'offline_reference_model_only' 'content expansion seven-star reference status'
  Assert-Null $Expansion.derivative_offline_specs.seven_star_session_reference.runtime_key 'content expansion seven-star reference runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.mansion_session_reference.artifact '../../../implementation/tianting-mansion-session-reference/contract/mansion-session-time-qualification-reference-contract.json' 'content expansion mansion reference artifact'
  Assert-Equal $Expansion.derivative_offline_specs.mansion_session_reference.status 'offline_reference_model_only' 'content expansion mansion reference status'
  Assert-Null $Expansion.derivative_offline_specs.mansion_session_reference.runtime_key 'content expansion mansion reference runtime key'
  Assert-Equal $Expansion.derivative_offline_specs.tower_economy_full_run.artifact 'tower-economy/mansion-economy-global-tower-run-season-contract.json' 'content expansion tower-economy derivative artifact'
  Assert-Equal $Expansion.derivative_offline_specs.tower_economy_full_run.status 'tianting_offline_candidate_pending_global_tower_adoption' 'content expansion tower-economy derivative status'

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
  Assert-Condition ([string]$Expansion.seven_star_solo.star_titles.solo_origin_rule -match '单人完整可用') 'same-star title directions preserve solo value'
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
    'economy_v2_handoff_source_evidence_contract',
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
  Assert-Equal $AuthoritySources.economy_v2_authority_receipt_input_handoff '../../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json' 'authority source economy-v2 handoff contract'
  Assert-Condition ([string]$AuthoritySources.economy_v2_authority_receipt_input_handoff_rule -match 'null/deferred') 'authority economy-v2 handoff keeps economic values deferred'
  Assert-Condition ([string]$AuthoritySources.economy_v2_authority_receipt_input_handoff_rule -match '不能创建结算请求') 'authority economy-v2 handoff cannot create settlement request'
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
  Assert-Condition ([string]$AuthorityBoundaries.economy_rule -match '不能变成结算请求') 'authority logical receipts cannot become settlement requests'
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

  $AuthorityHandoffEvidence = $Authority.economy_v2_handoff_source_evidence_contract
  $HandoffEvidenceFields = @('actor_id', 'actor_lifecycle_id', 'event_id', 'producer_spec_id', 'completed_tick', 'authority_proof_ref', 'schema_version', 'source_session_spec_id', 'source_session_instance_id', 'source_session_epoch', 'source_session_revision', 'source_membership_snapshot_id', 'source_member_status')
  Assert-Equal $AuthorityHandoffEvidence.spec_id 'TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE' 'authority economy handoff source evidence spec id'
  Assert-Equal $AuthorityHandoffEvidence.decision_status 'offline_design' 'authority economy handoff source evidence status'
  Assert-Null $AuthorityHandoffEvidence.runtime_key 'authority economy handoff source evidence runtime key'
  Assert-Equal $AuthorityHandoffEvidence.source_completion_receipt_contract_spec_id 'TT_SPEC_TIANTING_COMPLETION_RECEIPT_IDEMPOTENCY' 'authority economy handoff source receipt contract'
  Assert-Equal $AuthorityHandoffEvidence.record_scope 'character_completion_input_candidate' 'authority economy handoff source evidence scope'
  Assert-Condition ([string]$AuthorityHandoffEvidence.only_issuer -match 'future_authority_resolver') 'authority economy handoff source evidence issuer'
  Assert-Condition ([string]$AuthorityHandoffEvidence.caller_input_rule -match '不得构造') 'authority economy handoff source evidence rejects caller construction'
  Assert-ExactArray $AuthorityHandoffEvidence.required_bound_fields $HandoffEvidenceFields 'authority economy handoff source evidence fields'
  Assert-Equal $AuthorityHandoffEvidence.session_route_instance_normalization.TT_SPEC_SESSION_LINGXIAO_MAINLINE 'session_instance_id -> source_session_instance_id' 'authority handoff mainline instance normalization'
  Assert-Equal $AuthorityHandoffEvidence.session_route_instance_normalization.TT_SPEC_SESSION_SEVEN_STAR 'session_instance_id -> source_session_instance_id' 'authority handoff seven-star instance normalization'
  Assert-Equal $AuthorityHandoffEvidence.session_route_instance_normalization.TT_SPEC_SESSION_MANSION_NORMAL 'raid_instance_id -> source_session_instance_id' 'authority handoff normal mansion instance normalization'
  Assert-Equal $AuthorityHandoffEvidence.session_route_instance_normalization.TT_SPEC_SESSION_MANSION_NIGHTMARE 'raid_instance_id -> source_session_instance_id' 'authority handoff nightmare mansion instance normalization'
  Assert-ExactArray $AuthorityHandoffEvidence.mansion_additional_bound_fields @('rotation_snapshot_id', 'quadrant', 'difficulty') 'authority handoff mansion additional evidence fields'
  Assert-Equal $AuthorityHandoffEvidence.candidate_member_status 'active' 'authority handoff candidate member status'
  Assert-Condition ([string]$AuthorityHandoffEvidence.member_binding_rule -match 'source_member_status 为 active') 'authority handoff active member binding'
  Assert-Condition ([string]$AuthorityHandoffEvidence.atomic_binding_rule -match '原子绑定') 'authority handoff atomic evidence binding'
  Assert-Condition ([string]$AuthorityHandoffEvidence.replay_mutation_rule -match '漂移均拒绝') 'authority handoff evidence replay mutation rejection'
  Assert-Condition ([string]$AuthorityHandoffEvidence.normal_completion_cleanup_rule -match '不自动产生经济收据') 'authority handoff cleanup cannot create economic receipt'
  Assert-Condition ([string]$AuthorityHandoffEvidence.non_economic_boundary -match 'null/deferred') 'authority handoff source evidence keeps economic values deferred'
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
  Assert-Equal $TowerReuse.full_run_contract.artifact 'tower-economy/mansion-economy-global-tower-run-season-contract.json' 'tower full-run candidate artifact'
  Assert-Equal $TowerReuse.full_run_contract.status 'tianting_offline_candidate_pending_global_tower_adoption' 'tower full-run remains candidate pending global adoption'
  Assert-Equal $TowerReuse.full_run_contract.candidate_full_run_floor_count 40 'tower candidate full-run floor count'
  Assert-Equal $TowerReuse.full_run_contract.candidate_cycle_count 8 'tower candidate cycle count'
  Assert-Equal $TowerReuse.full_run_contract.candidate_ten_floor_arc_count 4 'tower candidate ten-floor arc count'
  Assert-Null $TowerReuse.full_run_contract.runtime_key 'tower full-run candidate runtime key'
  Assert-Equal $TowerReuse.mini_boss_cadence.status 'tianting_offline_candidate_pending_global_tower_adoption' 'tower mini-Boss cadence remains candidate'
  Assert-Equal $TowerReuse.mini_boss_cadence.candidate_value 5 'tower mini-Boss candidate cadence'
  Assert-Equal $TowerReuse.major_boss_cadence.candidate_every_floors 10 'tower major-Boss candidate cadence'
  Assert-Equal $TowerReuse.major_boss_cadence.major_boss_design 'offline_creative_candidate_pending_global_tower_adoption' 'tower major-Boss design remains candidate'
  Assert-ExactArray $TowerReuse.major_boss_cadence.major_boss_spec_ids @('TT_SPEC_TOWER_MAJOR_BOSS_FLOOR_10', 'TT_SPEC_TOWER_MAJOR_BOSS_FLOOR_20', 'TT_SPEC_TOWER_MAJOR_BOSS_FLOOR_30', 'TT_SPEC_TOWER_MAJOR_BOSS_FLOOR_40') 'tower major-Boss candidate roster'
  Assert-Null $TowerReuse.major_boss_cadence.runtime_key 'tower major-Boss runtime key'
  Assert-Equal $TowerReuse.first_cycle_isolation.rule 'content_pool_only; outer orchestration may label each segment fifth beat as a content slot and use NEXT_CYCLE_HANDOFF between cycles 1 through 7, but must not rename states, alter transitions, assign runtime floor keys or otherwise mutate existing abstract beats' 'tower first-cycle isolation rule'
  Assert-Condition ($TowerReuse.first_cycle_isolation.must_not_bind_existing_beats -eq $false) 'tower first-cycle only permits non-mutating fifth-beat annotation'
  Assert-Equal $TowerReuse.first_cycle_isolation.allowed_outer_beat_annotation 'fifth_beat_content_slot_only' 'tower first-cycle outer annotation boundary'
  Assert-Array $TowerReuse.first_cycle_isolation.existing_beat_bindings 'tower first-cycle isolation bindings'
  Assert-Equal $TowerReuse.first_cycle_isolation.existing_beat_bindings.Count 0 'tower first-cycle isolation has no beat bindings'
  Assert-Null $TowerReuse.first_cycle_isolation.runtime_key 'tower first-cycle isolation runtime key'
  Assert-Null $TowerReuse.runtime_key 'content expansion tower-reuse runtime key'

  # 完整通天塔方案是天庭侧候选；上位成长系统仍未采纳总层数，不能被本包倒置为既成全局规则。
  Assert-Equal $TowerEconomy.version 1 'tower-economy candidate contract version'
  Assert-Equal $TowerEconomy.package_status 'offline-design-candidate-pending-global-tower-adoption' 'tower-economy package remains candidate pending global adoption'
  Assert-Equal $TowerEconomy.production_gate 'closed' 'tower-economy production gate'
  Assert-Equal $TowerEconomy.identity.spec_id 'TT_SPEC_MANSION_ECONOMY_GLOBAL_TOWER_RUN_SEASON' 'tower-economy identity spec id'
  foreach ($FieldName in @('runtime_key', 'tower_run_id', 'tower_cycle_id', 'tower_floor_id', 'tower_season_id', 'tower_season_snapshot_id', 'source_success_event_spec_id', 'source_profile', 'reward_slot_key', 'receipt_id', 'resource_id', 'event_id')) {
    Assert-Null $TowerEconomy.identity.PSObject.Properties[$FieldName].Value "tower-economy identity deferred field: $FieldName"
  }
  Assert-Equal $TowerEconomy.global_tower_identity.spec_id 'TT_SPEC_GLOBAL_TONGTIAN_TOWER_RUN' 'tower-economy global tower identity'
  Assert-Equal $TowerEconomy.global_tower_identity.scope 'one_and_only_one_global_long_term_tower' 'tower-economy single global tower scope'
  Assert-Condition ($TowerEconomy.global_tower_identity.must_not_create -contains 'second_tower_system') 'tower-economy forbids a second tower system'
  Assert-Equal $TowerEconomy.global_tower_adoption_gate.upstream_authority 'docs/物编/成长系统规格包/design-spec.json' 'tower-economy upstream adoption authority'
  Assert-Equal $TowerEconomy.global_tower_adoption_gate.status 'pending_global_tower_adoption' 'tower-economy upstream adoption remains pending'
  Assert-Null $TowerEconomy.global_tower_adoption_gate.runtime_key 'tower-economy global adoption gate runtime key'
  Assert-Condition (-not (Test-HasProperty $GrowthDesign 'towerEconomyFullRunContract')) 'upstream growth-system has not adopted the TianTing full-run candidate'
  Assert-Condition (-not (Test-HasProperty $GrowthDesign 'globalTowerFullRunContract')) 'upstream growth-system declares no competing accepted global full-run contract'
  Assert-Equal $TowerEconomy.entry_contract.required_level_rule 'every_participant_independently_requires_authority_confirmed_level_55' 'tower-economy per-member entry rule'
  Assert-Equal $TowerEconomy.entry_contract.protected_difu_key_rule 'DF_PROGRESS_YANLUO_HALL_CLEARED_is_not_an_entry_or_settlement_input' 'tower-economy protected Difu key boundary'
  Assert-Null $TowerEconomy.entry_contract.runtime_key 'tower-economy entry runtime key'
  Assert-Null $TowerEconomy.entry_contract.qualification_snapshot_id 'tower-economy entry qualification snapshot'
  Assert-Null $TowerEconomy.entry_contract.event_id 'tower-economy entry event id'

  $TowerRunModel = $TowerEconomy.full_run_model
  Assert-Equal $TowerRunModel.spec_id 'TT_SPEC_GLOBAL_TOWER_FULL_RUN_MODEL' 'tower-economy full-run model spec id'
  Assert-Equal $TowerRunModel.status 'tianting_offline_candidate_pending_global_tower_adoption' 'tower-economy full-run model remains candidate'
  Assert-Equal $TowerRunModel.candidate_full_run_floor_count 40 'tower-economy candidate floor count'
  Assert-Equal $TowerRunModel.candidate_cycle_count 8 'tower-economy candidate cycle count'
  Assert-Equal $TowerRunModel.candidate_ten_floor_arc_count 4 'tower-economy candidate ten-floor arc count'
  Assert-Condition ([string]$TowerRunModel.continuation_rule -match 'cycles 1 through 7') 'tower-economy continuation only opens cycles one through seven'
  Assert-Condition ([string]$TowerRunModel.cycle_terminal_policy.cycles_1_through_7 -match 'NEXT_CYCLE_HANDOFF is the only continuation') 'tower-economy non-final cycles have one continuation route'
  Assert-Condition ([string]$TowerRunModel.cycle_terminal_policy.cycle_8 -match 'NEXT_CYCLE_HANDOFF is prohibited') 'tower-economy cycle eight prohibits next-cycle handoff'
  Assert-Condition ([string]$TowerRunModel.final_run_close_rule -match 'no ninth segment') 'tower-economy final run cannot open a ninth segment'
  foreach ($FieldName in @('runtime_key', 'tower_run_id', 'tower_cycle_id', 'tower_floor_id')) {
    Assert-Null $TowerRunModel.PSObject.Properties[$FieldName].Value "tower-economy full-run deferred field: $FieldName"
  }

  $TowerBossCadence = $TowerEconomy.boss_slot_cadence
  Assert-Equal $TowerBossCadence.spec_id 'TT_SPEC_GLOBAL_TOWER_BOSS_SLOT_CADENCE' 'tower-economy boss-slot cadence spec id'
  Assert-Equal $TowerBossCadence.candidate_mini_boss_cadence 'every_five_floor_boss_slot' 'tower-economy candidate mini-Boss cadence'
  Assert-Equal $TowerBossCadence.candidate_major_boss_cadence 'every_ten_floor_boss_slot' 'tower-economy candidate major-Boss cadence'
  Assert-ExactArray (@($TowerBossCadence.planned_boss_slots | ForEach-Object { [string]$_.floor_ordinal })) @('5', '10', '15', '20', '25', '30', '35', '40') 'tower-economy candidate boss-slot floors'
  Assert-ExactArray (@($TowerBossCadence.planned_boss_slots | ForEach-Object { [string]$_.boss_scope })) @('mini', 'major', 'mini', 'major', 'mini', 'major', 'mini', 'major') 'tower-economy major slots replace mini slots'
  foreach ($BossSlot in @($TowerBossCadence.planned_boss_slots)) {
    Assert-Null $BossSlot.source_success_event_spec_id "tower-economy boss-slot source event: floor $($BossSlot.floor_ordinal)"
    Assert-Null $BossSlot.runtime_key "tower-economy boss-slot runtime key: floor $($BossSlot.floor_ordinal)"
  }
  Assert-Null $TowerBossCadence.specific_star_lord_or_mansion_officer_selection 'tower-economy specific pool selection remains deferred'
  Assert-Null $TowerBossCadence.runtime_key 'tower-economy boss-slot cadence runtime key'
  Assert-Null $TowerBossCadence.boss_instance_id 'tower-economy boss instance id'
  Assert-Null $TowerBossCadence.content_snapshot_id 'tower-economy content snapshot id'
  Assert-Equal $TowerEconomy.major_boss_designs.Count 4 'tower-economy major-Boss candidate count'
  Assert-ExactArray (@($TowerEconomy.major_boss_designs | ForEach-Object { [string]$_.spec_id })) @('TT_SPEC_TOWER_MAJOR_BOSS_FLOOR_10', 'TT_SPEC_TOWER_MAJOR_BOSS_FLOOR_20', 'TT_SPEC_TOWER_MAJOR_BOSS_FLOOR_30', 'TT_SPEC_TOWER_MAJOR_BOSS_FLOOR_40') 'tower-economy major-Boss candidate order'
  foreach ($MajorBoss in @($TowerEconomy.major_boss_designs)) {
    foreach ($FieldName in @('runtime_key', 'unit_id', 'ability_id', 'asset_id', 'source_success_event_spec_id')) {
      Assert-Null $MajorBoss.PSObject.Properties[$FieldName].Value "tower-economy major-Boss deferred field: $($MajorBoss.spec_id)/$FieldName"
    }
  }
  Assert-Condition ($TowerEconomy.content_pool_isolation.prohibited_reuse -contains 'mansion_credential') 'tower-economy does not reuse mansion credentials'
  Assert-Condition ($TowerEconomy.content_pool_isolation.prohibited_reuse -contains 'economic_receipt') 'tower-economy does not reuse economic receipts'
  Assert-Null $TowerEconomy.content_pool_isolation.runtime_key 'tower-economy content-pool runtime key'

  $TowerSeason = $TowerEconomy.season_snapshot_contract
  Assert-Equal $TowerSeason.spec_id 'TT_SPEC_GLOBAL_TOWER_SEASON_SNAPSHOT' 'tower-economy season snapshot spec id'
  Assert-Equal $TowerSeason.status 'null_deferred_authority_snapshot_semantics_only' 'tower-economy season snapshot status'
  Assert-Condition ([string]$TowerSeason.immutability_rule -match 'Client clock') 'tower-economy season rejects client clock'
  Assert-Condition ([string]$TowerSeason.mansion_rotation_isolation_rule -match 'Asia/Shanghai') 'tower-economy season isolates mansion rotation'
  foreach ($Property in $TowerSeason.fields.PSObject.Properties) {
    Assert-Null $Property.Value "tower-economy season snapshot field: $($Property.Name)"
  }
  foreach ($Property in $TowerSeason.season_values_deferred.PSObject.Properties) {
    Assert-Null $Property.Value "tower-economy season value: $($Property.Name)"
  }
  Assert-Null $TowerSeason.runtime_key 'tower-economy season runtime key'

  $TowerEconomyBoundary = $TowerEconomy.mansion_economy_source_boundary
  Assert-Equal $TowerEconomyBoundary.spec_id 'TT_SPEC_MANSION_ECONOMY_SOURCE_EMPTY_BOUNDARY' 'tower-economy empty source boundary spec id'
  Assert-Equal $TowerEconomyBoundary.current_allowed_zero_value_source_fact.source_session_spec_id 'TT_SPEC_SESSION_LINGXIAO_MAINLINE' 'tower-economy Lingxiao-only source session'
  Assert-Equal $TowerEconomyBoundary.current_allowed_zero_value_source_fact.source_success_event_spec_id 'TT_SPEC_EVENT_LINGXIAO_OUTER_COURT_SUCCESS' 'tower-economy Lingxiao-only source event'
  foreach ($FieldName in @('source_profile', 'reward_slot_key', 'receipt_id')) {
    Assert-Null $TowerEconomyBoundary.current_allowed_zero_value_source_fact.PSObject.Properties[$FieldName].Value "tower-economy Lingxiao source deferred field: $FieldName"
  }
  Assert-Equal $TowerEconomyBoundary.empty_sources.Count 4 'tower-economy empty source boundary count'
  foreach ($EmptySource in @($TowerEconomyBoundary.empty_sources)) {
    foreach ($FieldName in @('source_success_event_spec_id', 'source_profile', 'reward_slot_key', 'qualification_snapshot_id', 'receipt_id')) {
      if (Test-HasProperty $EmptySource $FieldName) {
        Assert-Null $EmptySource.PSObject.Properties[$FieldName].Value "tower-economy forbidden source field: $FieldName"
      }
    }
  }
  Assert-Null $TowerEconomyBoundary.runtime_key 'tower-economy empty source boundary runtime key'

  $TowerSettlement = $TowerEconomy.tower_drop_and_settlement_boundary
  Assert-Equal $TowerSettlement.spec_id 'TT_SPEC_GLOBAL_TOWER_DROP_AND_SETTLEMENT_EMPTY_BOUNDARY' 'tower-economy drop-and-settlement boundary spec id'
  Assert-Equal $TowerSettlement.status 'null_deferred' 'tower-economy drop-and-settlement boundary status'
  foreach ($Property in $TowerSettlement.PSObject.Properties) {
    if ($Property.Name -notin @('spec_id', 'status', 'rule')) {
      Assert-Null $Property.Value "tower-economy drop-and-settlement deferred field: $($Property.Name)"
    }
  }
  $TowerRecovery = $TowerEconomy.disconnect_cleanup_and_replay_boundary
  Assert-Equal $TowerRecovery.spec_id 'TT_SPEC_GLOBAL_TOWER_RUN_RECOVERY_AND_IDEMPOTENCY' 'tower-economy recovery boundary spec id'
  Assert-Condition ([string]$TowerRecovery.team_disconnect_rule -match 'left') 'tower-economy disconnected team member becomes left'
  Assert-Condition ([string]$TowerRecovery.team_disconnect_rule -match 'cannot reconnect') 'tower-economy left member cannot reconnect'
  Assert-Condition ([string]$TowerRecovery.cleanup_rule -match 'cleanup token') 'tower-economy cleanup requires cleanup token'
  Assert-Condition ([string]$TowerRecovery.normal_terminal_persistence_rule -match 'does not roll back') 'tower-economy normal terminal survives cleanup failure'
  foreach ($FieldName in @('runtime_key', 'tower_run_id', 'tower_cycle_id', 'cleanup_token', 'event_id')) {
    Assert-Null $TowerRecovery.PSObject.Properties[$FieldName].Value "tower-economy recovery deferred field: $FieldName"
  }
  foreach ($Property in $TowerEconomy.deferred.PSObject.Properties) {
    Assert-Null $Property.Value "tower-economy deferred field: $($Property.Name)"
  }
  $ExpectedTowerAcceptance = @(1..28 | ForEach-Object { 'TT-TOWER-ACC-{0:D3}' -f $_ })
  Assert-ExactArray (@($TowerEconomy.acceptance | ForEach-Object { [string]$_.id })) $ExpectedTowerAcceptance 'tower-economy acceptance ids'
  $TowerMarkdownAcceptance = @([regex]::Matches($TowerEconomyMarkdown, 'TT-TOWER-ACC-\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  Assert-ExactArray $TowerMarkdownAcceptance $ExpectedTowerAcceptance 'tower-economy Markdown acceptance ids'
  Assert-AllRuntimeKeysNull $TowerEconomy 'tower-economy candidate contract'

  # P0 只冻结跨职业绝对标定协议和拒绝越权投影；它不得自证实机公式或生成天庭对象字段。
  Assert-Equal $CalibrationPackage.schema_version 1 'P0 calibration package version'
  Assert-Equal $CalibrationPackage.package 'cross-profession-combat-calibration' 'P0 calibration package name'
  Assert-Equal $CalibrationPackage.package_status 'offline-calibration-reference-only' 'P0 calibration package status'
  Assert-Condition ($CalibrationPackage.runtime_handoff -eq $false) 'P0 calibration package runtime handoff remains false'
  Assert-Equal $CalibrationPackage.production_gate 'closed' 'P0 calibration package production gate'
  foreach ($PropertyName in @('creates_y3_objects', 'creates_map_or_terrain', 'writes_lua_runtime', 'writes_progress_or_economy', 'assigns_absolute_tianting_object_fields')) {
    Assert-Condition ($CalibrationPackage.boundaries.PSObject.Properties[$PropertyName].Value -eq $false) "P0 calibration package boundary remains false: $PropertyName"
  }
  Assert-Equal $CalibrationPackage.evidence_adoption_package.artifact 'evidence-adoption/p0-evidence-collection-and-adoption-contract.json' 'P0 evidence-adoption package artifact'
  Assert-Equal $CalibrationPackage.evidence_adoption_package.status 'offline-evidence-collection-plan-only' 'P0 evidence-adoption package status'
  Assert-Equal $CalibrationPackage.evidence_adoption_package.test_entry 'evidence-adoption/tests/run-all.ps1' 'P0 evidence-adoption package runner'
  Assert-Equal $CalibrationPackage.evidence_adoption_package.production_gate 'closed' 'P0 evidence-adoption package production gate'
  Assert-Condition ($CalibrationPackage.evidence_adoption_package.runtime_handoff -eq $false) 'P0 evidence-adoption package runtime handoff remains false'
  foreach ($FieldName in @('actual_capture_provider', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload')) {
    Assert-Null $CalibrationPackage.evidence_adoption_package.PSObject.Properties[$FieldName].Value "P0 evidence-adoption package deferred field: $FieldName"
  }
  Assert-Equal $CalibrationPackage.external_capture_onboarding_package.artifact 'external-capture-onboarding/package-contract.json' 'P0 external-capture-onboarding package artifact'
  Assert-Equal $CalibrationPackage.external_capture_onboarding_package.status 'offline-external-capture-onboarding-only' 'P0 external-capture-onboarding package status'
  Assert-Equal $CalibrationPackage.external_capture_onboarding_package.test_entry 'external-capture-onboarding/tests/run-all.ps1' 'P0 external-capture-onboarding package runner'
  Assert-Equal $CalibrationPackage.external_capture_onboarding_package.production_gate 'closed' 'P0 external-capture-onboarding package production gate'
  Assert-Condition ($CalibrationPackage.external_capture_onboarding_package.runtime_handoff -eq $false) 'P0 external-capture-onboarding package runtime handoff remains false'
  foreach ($FieldName in @('actual_capture_provider', 'actual_y3_project_ref', 'actual_source_origin_preflight_attestation', 'actual_environment_attestation', 'actual_external_artifact_manifest', 'actual_independent_review_handoff', 'actual_adoption_decision', 'absolute_projection_payload')) {
    Assert-Null $CalibrationPackage.external_capture_onboarding_package.PSObject.Properties[$FieldName].Value "P0 external-capture-onboarding package deferred field: $FieldName"
  }

  Assert-Equal $Calibration.schema_version 1 'P0 calibration contract version'
  Assert-Equal $Calibration.contract_id 'CAL_SPEC_CROSS_PROFESSION_ABSOLUTE_COMBAT_V1' 'P0 calibration contract id'
  Assert-Equal $Calibration.package_status 'offline-calibration-reference-only' 'P0 calibration contract status'
  Assert-Condition ($Calibration.non_production -eq $true) 'P0 calibration contract remains non-production'
  Assert-Condition ($Calibration.runtime_handoff -eq $false) 'P0 calibration contract runtime handoff remains false'
  Assert-Equal $Calibration.production_gate 'closed' 'P0 calibration contract production gate'
  Assert-Equal $Calibration.baseline_clock.fixture_timebase_hz 60 'P0 calibration fixture timebase'
  Assert-Null $Calibration.baseline_clock.engine_frame_projection 'P0 calibration engine-frame projection remains null'
  Assert-ExactArray (@($Calibration.combatant_baselines | ForEach-Object { [string]$_.profession_id })) @('C01', 'C02', 'C03', 'C04') 'P0 calibration profession order'
  foreach ($Baseline in @($Calibration.combatant_baselines)) {
    Assert-ExactArray (@($Baseline.level_anchors | ForEach-Object { [int]$_.level })) @(41, 55, 60) "P0 calibration level anchors: $($Baseline.profession_id)"
  }
  Assert-ExactArray $Calibration.fixed_build_declaration_ledger.required_levels @(41, 55, 60) 'P0 calibration fixed-build levels'
  Assert-Equal @($Calibration.fixed_build_declaration_ledger.profiles).Count 12 'P0 calibration fixed-build ledger count'
  Assert-Null $Calibration.formula_registry.general_physical_damage 'P0 general physical formula remains null'
  Assert-Null $Calibration.formula_registry.general_magical_damage 'P0 general magical formula remains null'
  Assert-Null $Calibration.formula_registry.defense_penetration_order 'P0 defense penetration formula remains null'
  Assert-Null $Calibration.formula_registry.critical_order_and_caps 'P0 critical formula remains null'
  Assert-Null $Calibration.formula_registry.hit_dodge_formula 'P0 hit-dodge formula remains null'
  Assert-Null $Calibration.formula_registry.control_duration_resistance_formula 'P0 control-resistance formula remains null'
  Assert-Equal $Calibration.absolute_projection_gate.status 'blocked_pending_evidence' 'P0 absolute projection gate status'
  Assert-ExactArray $Calibration.absolute_projection_gate.required_gate_ids $ExpectedP0GateIds 'P0 absolute projection canonical gate sequence'
  Assert-Equal @($Calibration.absolute_projection_gate.current_satisfied_gate_ids).Count 0 'P0 absolute projection current satisfied gate count'
  $AbsoluteProjectionCandidate = $Calibration.absolute_projection_gate.candidate
  Assert-Equal $AbsoluteProjectionCandidate.candidate_id 'TT_CAL_ABSOLUTE_OBJECT_FIELDS_V1' 'P0 absolute projection candidate id'
  foreach ($FieldName in @('target_object_or_unit_id', 'hp_max', 'attack_phy', 'attack_mag', 'defense_phy', 'defense_mag', 'attack_speed', 'attack_interval_seconds', 'move_speed_field', 'skill_damage', 'skill_duration_seconds')) {
    Assert-Null $AbsoluteProjectionCandidate.PSObject.Properties[$FieldName].Value "P0 absolute projection field remains null: $FieldName"
  }
  Assert-Equal $AbsoluteProjectionCandidate.status 'blocked' 'P0 absolute projection candidate status'
  Assert-AllRuntimeKeysNull $Calibration 'P0 cross-profession calibration contract'

  Assert-Equal $P0EvidenceAdoption.schema_version 1 'P0 evidence-adoption contract version'
  Assert-Equal $P0EvidenceAdoption.identity.spec_id 'CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1' 'P0 evidence-adoption identity'
  Assert-Equal $P0EvidenceAdoption.identity.package_status 'offline-evidence-collection-plan-only' 'P0 evidence-adoption status'
  Assert-Equal $P0EvidenceAdoption.identity.production_gate 'closed' 'P0 evidence-adoption production gate'
  Assert-Condition ($P0EvidenceAdoption.identity.runtime_handoff -eq $false) 'P0 evidence-adoption runtime handoff remains false'
  foreach ($FieldName in @('actual_capture_provider', 'actual_y3_project_ref', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload')) {
    Assert-Null $P0EvidenceAdoption.identity.PSObject.Properties[$FieldName].Value "P0 evidence-adoption identity deferred field: $FieldName"
  }
  Assert-Equal $P0EvidenceAdoption.source_calibration_contract.artifact '../contract/cross-profession-combat-calibration-contract.json' 'P0 evidence-adoption parent artifact'
  Assert-Equal $P0EvidenceAdoption.source_calibration_contract.contract_id 'CAL_SPEC_CROSS_PROFESSION_ABSOLUTE_COMBAT_V1' 'P0 evidence-adoption parent contract id'
  Assert-Equal $P0EvidenceAdoption.source_calibration_contract.content_sha256 $CalibrationSourceDigest 'P0 evidence-adoption parent digest'
  Assert-ExactArray $P0EvidenceAdoption.source_calibration_contract.required_gate_ids $ExpectedP0GateIds 'P0 evidence-adoption canonical gate sequence'
  Assert-ExactArray $P0EvidenceAdoption.submission_envelope.required_fields @(
    'evidence_id', 'gate_id', 'evidence_kind', 'source_capture_session_id', 'capture_run_id', 'capture_provider_proof_ref',
    'engine_build_digest', 'real_project_revision', 'map_or_fixture_revision', 'object_inventory_snapshot_digest',
    'template_readback_basis_digest', 'canonical_artifact_digest', 'capture_basis_digest', 'input_trace_digest',
    'recorded_authoritative_instant', 'collector_identity_ref', 'reviewer_identity_ref', 'external_artifact_ref', 'gate_scope'
  ) 'P0 evidence-adoption exact submission envelope'
  Assert-ExactArray $P0EvidenceAdoption.gate_scope_contract.exact_fields @('scope_kind', 'profile_id', 'deterministic_run_index', 'party_member_count', 'formula_family', 'readback_class') 'P0 evidence-adoption exact gate-scope fields'
  Assert-ExactArray $P0EvidenceAdoption.gate_scope_contract.fixed_build_profile_ids (@($Calibration.fixed_build_declaration_ledger.profiles | ForEach-Object { [string]$_.profile_id })) 'P0 evidence-adoption fixed-build profile sequence'
  Assert-ExactArray (@($P0EvidenceAdoption.gate_scope_contract.per_gate | ForEach-Object { [string]$_.gate_id })) $ExpectedP0GateIds 'P0 evidence-adoption gate-scope sequence'
  $P0EvidenceGateScopeSignatures = @($P0EvidenceAdoption.gate_scope_contract.per_gate | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.scope_kind, $_.profile_id, $_.deterministic_run_index, $_.party_member_count, $_.formula_family, $_.readback_class
  })
  Assert-ExactArray $P0EvidenceGateScopeSignatures @(
    'fixed_build_replay|required_canonical_profile|required_1_to_3|||',
    'formula_observation||||physical_magical_defense_penetration|',
    'formula_observation||||hit_crit_control|',
    'engine_readback|||||engine_action_frame_speed',
    'terrain_camera_fixture|||||terrain_collision_camera',
    'authority_party_replay|||required_1_to_4||',
    'object_template_readback|||||object_template_inventory'
  ) 'P0 evidence-adoption exact gate-scope declarations'
  Assert-Equal $P0EvidenceAdoption.capture_chain.chain_status 'external_evidence_not_collected' 'P0 evidence-adoption capture chain status'
  Assert-Condition ($P0EvidenceAdoption.capture_chain.collector_may_read_but_not_write -eq $true) 'P0 evidence-adoption collector is read-only'
  Assert-Condition ($P0EvidenceAdoption.capture_chain.submission_is_not_adoption -eq $true) 'P0 evidence-adoption submission is not adoption'
  Assert-Equal @($P0EvidenceAdoption.capture_chain.stages).Count 5 'P0 evidence-adoption capture stage count'
  Assert-Equal $P0EvidenceAdoption.adoption_controls.current_adoption_state 'closed' 'P0 evidence-adoption current adoption state'
  Assert-Condition ($P0EvidenceAdoption.adoption_controls.automatic_gate_promotion -eq $false) 'P0 evidence-adoption forbids automatic gate promotion'
  Assert-ExactArray $P0EvidenceAdoption.adoption_controls.current_satisfied_gate_ids @() 'P0 evidence-adoption satisfied gates'
  Assert-Condition ($P0EvidenceAdoption.adoption_controls.projection_review_is_separate_from_gate_adoption -eq $true) 'P0 evidence-adoption separates projection review'
  Assert-ExactArray (@($P0EvidenceAdoption.gate_collection_plans | ForEach-Object { [string]$_.gate_id })) $ExpectedP0GateIds 'P0 evidence-adoption collection plan sequence'
  foreach ($Plan in @($P0EvidenceAdoption.gate_collection_plans)) {
    Assert-Equal $Plan.collection_status 'blocked_pending_external_evidence' "P0 evidence-adoption plan blocked: $($Plan.gate_id)"
    Assert-Null $Plan.accepted_evidence_refs "P0 evidence-adoption plan evidence refs: $($Plan.gate_id)"
    Assert-Equal $Plan.adoption_status 'blocked_pending_external_evidence' "P0 evidence-adoption plan adoption status: $($Plan.gate_id)"
  }
  foreach ($Property in $P0EvidenceAdoption.deferred_outputs.PSObject.Properties) {
    Assert-Null $Property.Value "P0 evidence-adoption deferred output: $($Property.Name)"
  }
  Assert-ExactArray (@($P0EvidenceAdoption.acceptance | ForEach-Object { [string]$_.id })) @(1..13 | ForEach-Object { 'CAL-EVID-ACC-{0:D3}' -f $_ }) 'P0 evidence-adoption acceptance ids'
  Assert-Equal $P0EvidenceSourceSnapshot.identity.spec_id 'CAL_SPEC_P0_EVIDENCE_SOURCE_SNAPSHOT_V1' 'P0 evidence source snapshot identity'
  Assert-Equal $P0EvidenceSourceSnapshot.identity.status 'offline-source-snapshot-only' 'P0 evidence source snapshot status'
  Assert-Equal $P0EvidenceSourceSnapshot.sources[0].content_sha256 $CalibrationSourceDigest 'P0 evidence source snapshot parent digest'
  foreach ($FieldName in @('actual_external_capture_source', 'accepted_evidence_ledger', 'adoption_decision')) {
    Assert-Null $P0EvidenceSourceSnapshot.identity.PSObject.Properties[$FieldName].Value "P0 evidence source snapshot deferred field: $FieldName"
  }
  foreach ($Property in $P0EvidenceSourceSnapshot.external_capture_family.PSObject.Properties) {
    if ($Property.Name -ne 'rule') {
      Assert-Null $Property.Value "P0 evidence source snapshot external capture field: $($Property.Name)"
    }
  }
  Assert-Equal $P0EvidenceCollectionTemplates.identity.spec_id 'CAL_SPEC_P0_EVIDENCE_COLLECTION_TEMPLATES_V1' 'P0 evidence collection template identity'
  Assert-Equal $P0EvidenceCollectionTemplates.identity.status 'offline-template-only' 'P0 evidence collection template status'
  Assert-ExactArray (@($P0EvidenceCollectionTemplates.gate_templates | ForEach-Object { [string]$_.gate_id })) $ExpectedP0GateIds 'P0 evidence collection template gate sequence'
  foreach ($Template in @($P0EvidenceCollectionTemplates.gate_templates)) {
    Assert-Null $Template.local_records "P0 evidence collection local records: $($Template.gate_id)"
  }
  Assert-Equal $P0EvidenceAdoptionTemplate.identity.spec_id 'CAL_SPEC_P0_EXTERNAL_ADOPTION_DECISION_TEMPLATE_V1' 'P0 evidence adoption template identity'
  Assert-Equal $P0EvidenceAdoptionTemplate.identity.status 'not_created' 'P0 evidence adoption template status'
  Assert-ExactArray (@($P0EvidenceAdoptionTemplate.gate_decisions | ForEach-Object { [string]$_.gate_id })) $ExpectedP0GateIds 'P0 evidence adoption template gate sequence'
  foreach ($Decision in @($P0EvidenceAdoptionTemplate.gate_decisions)) {
    foreach ($FieldName in @('decision', 'evidence_bundle_digest', 'reviewer_proof_ref', 'reason')) {
      Assert-Null $Decision.PSObject.Properties[$FieldName].Value "P0 evidence adoption template deferred field: $($Decision.gate_id)/$FieldName"
    }
  }

  # P0 外部采集方接入包只冻结受信任现场采集的前置边界；它不能让当前离线仓库自证真实工程或越过既有采纳机关。
  Assert-Equal $P0ExternalCaptureOnboarding.schema_version 1 'P0 external-capture-onboarding contract version'
  Assert-Equal $P0ExternalCaptureOnboarding.identity.spec_id 'CAL_SPEC_EXTERNAL_CAPTURE_ONBOARDING_V1' 'P0 external-capture-onboarding identity'
  Assert-Equal $P0ExternalCaptureOnboarding.identity.package_status 'offline-external-capture-onboarding-only' 'P0 external-capture-onboarding status'
  Assert-Equal $P0ExternalCaptureOnboarding.identity.production_gate 'closed' 'P0 external-capture-onboarding production gate'
  Assert-Condition ($P0ExternalCaptureOnboarding.identity.runtime_handoff -eq $false) 'P0 external-capture-onboarding runtime handoff remains false'
  foreach ($FieldName in @('actual_capture_provider', 'actual_provider_qualification', 'actual_y3_project_ref', 'actual_source_origin_preflight_attestation', 'actual_environment_attestation', 'actual_external_artifact_manifest', 'actual_independent_review_handoff', 'actual_adoption_decision')) {
    Assert-Null $P0ExternalCaptureOnboarding.identity.PSObject.Properties[$FieldName].Value "P0 external-capture-onboarding identity deferred field: $FieldName"
  }
  $P0OnboardingSources = @($P0ExternalCaptureOnboarding.source_contracts)
  Assert-Equal $P0OnboardingSources.Count 3 'P0 external-capture-onboarding source contract count'
  Assert-Equal $P0OnboardingSources[0].artifact '../contract/cross-profession-combat-calibration-contract.json' 'P0 external-capture-onboarding parent artifact'
  Assert-Equal $P0OnboardingSources[0].contract_id 'CAL_SPEC_CROSS_PROFESSION_ABSOLUTE_COMBAT_V1' 'P0 external-capture-onboarding parent contract id'
  Assert-Equal $P0OnboardingSources[0].content_sha256 $CalibrationSourceDigest 'P0 external-capture-onboarding parent digest'
  Assert-Equal $P0OnboardingSources[1].artifact '../evidence-adoption/p0-evidence-collection-and-adoption-contract.json' 'P0 external-capture-onboarding evidence artifact'
  Assert-Equal $P0OnboardingSources[1].spec_id 'CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1' 'P0 external-capture-onboarding evidence spec id'
  Assert-Equal $P0OnboardingSources[1].content_sha256 $P0EvidenceAdoptionSourceDigest 'P0 external-capture-onboarding evidence digest'
  Assert-Equal $P0OnboardingSources[2].artifact '../../tianting-y3-construction-preflight/package-contract.json' 'P0 external-capture-onboarding preflight artifact'
  Assert-Equal $P0OnboardingSources[2].spec_id 'TT_SPEC_Y3_CONSTRUCTION_PREFLIGHT' 'P0 external-capture-onboarding preflight spec id'
  Assert-Equal $P0OnboardingSources[2].content_sha256 $ConstructionPreflightSourceDigest 'P0 external-capture-onboarding preflight digest'
  Assert-ExactArray $P0ExternalCaptureOnboarding.canonical_gate_snapshot.required_gate_ids $ExpectedP0GateIds 'P0 external-capture-onboarding canonical gate sequence'
  Assert-ExactArray $P0ExternalCaptureOnboarding.canonical_gate_snapshot.currently_satisfied_gate_ids @() 'P0 external-capture-onboarding satisfied gates'
  foreach ($FieldName in @('node_fengari_live_capture_trust_root', 'local_repository_may_register_provider', 'local_repository_may_accept_evidence', 'local_repository_may_adopt_p0_gate', 'local_repository_may_project_absolute_fields', 'write_authorization')) {
    Assert-Condition ($P0ExternalCaptureOnboarding.trust_boundary.PSObject.Properties[$FieldName].Value -eq $false) "P0 external-capture-onboarding trust boundary remains false: $FieldName"
  }
  Assert-Equal $P0ExternalCaptureOnboarding.trust_boundary.provider_execution_requirement 'external isolated process with read-only Y3/editor/authority access' 'P0 external-capture-onboarding provider isolation requirement'
  Assert-Equal $P0ExternalCaptureOnboarding.trust_boundary.transport_requirement 'canonical JSON/IPC or equivalent immutable external artifact transport' 'P0 external-capture-onboarding transport requirement'
  Assert-Equal $P0ExternalCaptureOnboarding.trust_boundary.node_fengari_role 'offline test or future materialization boundary only, never a trusted live capture provider' 'P0 external-capture-onboarding Node/Fengari boundary'
  foreach ($FieldName in @('provider_credentials', 'provider_endpoint', 'provider_private_key', 'local_provider_registration')) {
    Assert-Null $P0ExternalCaptureOnboarding.trust_boundary.PSObject.Properties[$FieldName].Value "P0 external-capture-onboarding trust deferred field: $FieldName"
  }
  Assert-ExactArray $P0ExternalCaptureOnboarding.role_separation.roles @('capture_provider', 'capture_operator', 'independent_reviewer', 'adoption_authority') 'P0 external-capture-onboarding role sequence'
  $P0OnboardingSeparationPairs = @($P0ExternalCaptureOnboarding.role_separation.must_not_be_same_principal_pairs | ForEach-Object { '{0}|{1}' -f $_[0], $_[1] })
  Assert-ExactArray $P0OnboardingSeparationPairs @(
    'capture_provider|capture_operator',
    'capture_provider|independent_reviewer',
    'capture_provider|adoption_authority',
    'capture_operator|independent_reviewer',
    'capture_operator|adoption_authority',
    'independent_reviewer|adoption_authority'
  ) 'P0 external-capture-onboarding all role-separation pairs'
  Assert-Null $P0ExternalCaptureOnboarding.role_separation.actual_role_bindings 'P0 external-capture-onboarding role bindings'
  Assert-Equal $P0ExternalCaptureOnboarding.preflight_dependency.artifact '../../tianting-y3-construction-preflight/tests/Invoke-TiantingY3ConstructionPreflight.ps1' 'P0 external-capture-onboarding preflight runner artifact'
  Assert-Equal $P0ExternalCaptureOnboarding.preflight_dependency.required_live_result 'structural_preflight_passed' 'P0 external-capture-onboarding required live preflight result'
  Assert-Condition ($P0ExternalCaptureOnboarding.preflight_dependency.preflight_is_necessary_but_not_sufficient -eq $true) 'P0 external-capture-onboarding preflight remains necessary but insufficient'
  Assert-Equal $P0ExternalCaptureOnboarding.preflight_dependency.preflight_runner_content_sha256 $ConstructionPreflightRunnerDigest 'P0 external-capture-onboarding preflight runner digest'
  Assert-Equal $P0ExternalCaptureOnboarding.preflight_dependency.required_source_origin_attestation_template 'templates/source-origin-preflight-attestation-template.json' 'P0 external-capture-onboarding source-origin template'
  Assert-Equal $P0ExternalCaptureOnboarding.preflight_dependency.current_workspace_result 'structural_preflight_blocked' 'P0 external-capture-onboarding current workspace preflight result'
  Assert-Null $P0ExternalCaptureOnboarding.preflight_dependency.real_target_map_root 'P0 external-capture-onboarding target map root'
  Assert-ExactArray $P0ExternalCaptureOnboarding.onboarding_sequence @(
    'authorization_and_role_separation',
    'real_map_local_structural_preflight',
    'provider_qualification',
    'environment_attestation',
    'read_only_capture',
    'canonicalization_and_external_manifest',
    'independent_review_handoff',
    'external_adoption_authority'
  ) 'P0 external-capture-onboarding sequence'
  $ExpectedP0OnboardingFieldworkGateIds = @('', 'P0-GATE-07-stable-object-keys-and-template-readback', 'P0-GATE-04-engine-action-frame-and-speed-readback', 'P0-GATE-05-terrain-collision-and-camera-fixture', 'P0-GATE-01-all-12-fixed-builds-declared-and-replayed', 'P0-GATE-02-general-physical-magical-defense-formulas-adopted', 'P0-GATE-03-hit-crit-control-formulas-adopted', 'P0-GATE-06-authoritative-one-to-four-member-replays')
  $ActualP0OnboardingFieldworkGateIds = @($P0ExternalCaptureOnboarding.first_fieldwork_order | ForEach-Object { if ($null -eq $_.gate_id) { '' } else { [string]$_.gate_id } })
  Assert-ExactArray $ActualP0OnboardingFieldworkGateIds $ExpectedP0OnboardingFieldworkGateIds 'P0 external-capture-onboarding fieldwork dependency order'
  foreach ($Step in @($P0ExternalCaptureOnboarding.first_fieldwork_order)) {
    Assert-Equal $Step.status 'blocked_pending_external_operator' "P0 external-capture-onboarding fieldwork status: $($Step.step_id)"
    Assert-Null $Step.external_artifact_ref "P0 external-capture-onboarding fieldwork external artifact: $($Step.step_id)"
  }
  Assert-ExactArray $P0ExternalCaptureOnboarding.template_artifacts @(
    'templates/provider-qualification-template.json',
    'templates/source-origin-preflight-attestation-template.json',
    'templates/environment-attestation-template.json',
    'templates/canonicalization-profile-template.json',
    'templates/external-artifact-manifest-template.json',
    'templates/independent-review-handoff-template.json'
  ) 'P0 external-capture-onboarding template artifact sequence'
  foreach ($Property in $P0ExternalCaptureOnboarding.deferred_outputs.PSObject.Properties) {
    Assert-Null $Property.Value "P0 external-capture-onboarding deferred output: $($Property.Name)"
  }
  Assert-ExactArray (@($P0ExternalCaptureOnboarding.acceptance | ForEach-Object { [string]$_.id })) @(1..12 | ForEach-Object { 'CAL-ONBOARD-ACC-{0:D3}' -f $_ }) 'P0 external-capture-onboarding acceptance ids'
  Assert-Equal $P0OnboardingProviderQualificationTemplate.identity.spec_id 'CAL_SPEC_EXTERNAL_CAPTURE_PROVIDER_QUALIFICATION_TEMPLATE_V1' 'P0 external-capture-onboarding provider template identity'
  Assert-Equal $P0OnboardingProviderQualificationTemplate.identity.status 'not_created' 'P0 external-capture-onboarding provider template status'
  foreach ($Property in $P0OnboardingProviderQualificationTemplate.future_role_binding.PSObject.Properties) {
    Assert-Null $Property.Value "P0 external-capture-onboarding provider role template field: $($Property.Name)"
  }
  Assert-Equal $P0OnboardingSourceOriginTemplate.identity.spec_id 'CAL_SPEC_EXTERNAL_CAPTURE_SOURCE_ORIGIN_PREFLIGHT_ATTESTATION_TEMPLATE_V1' 'P0 external-capture-onboarding source-origin template identity'
  Assert-Equal $P0OnboardingSourceOriginTemplate.identity.status 'not_created' 'P0 external-capture-onboarding source-origin template status'
  Assert-Equal $P0OnboardingSourceOriginTemplate.source_binding.preflight_contract_sha256 $ConstructionPreflightSourceDigest 'P0 external-capture-onboarding source-origin preflight contract digest'
  Assert-Equal $P0OnboardingSourceOriginTemplate.source_binding.preflight_runner_sha256 $ConstructionPreflightRunnerDigest 'P0 external-capture-onboarding source-origin runner digest'
  Assert-Equal $P0OnboardingSourceOriginTemplate.source_binding.required_live_result 'structural_preflight_passed' 'P0 external-capture-onboarding source-origin required result'
  foreach ($FieldName in @('structural_preflight_report_digest', 'provider_qualification_ref', 'read_only_authorization_ref', 'captured_authoritative_instant', 'real_project_identity_digest', 'real_map_identity_digest')) {
    Assert-Null $P0OnboardingSourceOriginTemplate.source_binding.PSObject.Properties[$FieldName].Value "P0 external-capture-onboarding source-origin deferred field: $FieldName"
  }
  Assert-Equal $P0OnboardingEnvironmentAttestationTemplate.identity.spec_id 'CAL_SPEC_EXTERNAL_CAPTURE_ENVIRONMENT_ATTESTATION_TEMPLATE_V1' 'P0 external-capture-onboarding environment template identity'
  Assert-Equal $P0OnboardingEnvironmentAttestationTemplate.source_binding.p0_contract_sha256 $CalibrationSourceDigest 'P0 external-capture-onboarding environment P0 digest'
  Assert-Equal $P0OnboardingEnvironmentAttestationTemplate.source_binding.evidence_adoption_contract_sha256 $P0EvidenceAdoptionSourceDigest 'P0 external-capture-onboarding environment evidence digest'
  Assert-Equal $P0OnboardingEnvironmentAttestationTemplate.source_binding.preflight_contract_sha256 $ConstructionPreflightSourceDigest 'P0 external-capture-onboarding environment preflight contract digest'
  Assert-Equal $P0OnboardingEnvironmentAttestationTemplate.source_binding.preflight_runner_sha256 $ConstructionPreflightRunnerDigest 'P0 external-capture-onboarding environment preflight runner digest'
  foreach ($Property in $P0OnboardingEnvironmentAttestationTemplate.required_environment_snapshot.PSObject.Properties) {
    Assert-Null $Property.Value "P0 external-capture-onboarding environment snapshot deferred field: $($Property.Name)"
  }
  Assert-Equal $P0OnboardingCanonicalizationTemplate.identity.spec_id 'CAL_SPEC_EXTERNAL_CAPTURE_CANONICALIZATION_PROFILE_TEMPLATE_V1' 'P0 external-capture-onboarding canonicalization template identity'
  Assert-Equal $P0OnboardingCanonicalizationTemplate.identity.status 'not_created' 'P0 external-capture-onboarding canonicalization template status'
  Assert-Equal $P0OnboardingArtifactManifestTemplate.identity.spec_id 'CAL_SPEC_EXTERNAL_CAPTURE_ARTIFACT_MANIFEST_TEMPLATE_V1' 'P0 external-capture-onboarding manifest template identity'
  Assert-ExactArray $P0OnboardingArtifactManifestTemplate.entries @() 'P0 external-capture-onboarding local manifest entries'
  Assert-Condition (-not (Test-HasProperty $P0OnboardingArtifactManifestTemplate.bundle_binding 'adoption_decision_ref')) 'P0 external-capture-onboarding manifest cannot pre-reference adoption'
  foreach ($Property in $P0OnboardingArtifactManifestTemplate.environment_family_binding.PSObject.Properties) {
    Assert-Null $Property.Value "P0 external-capture-onboarding manifest environment family deferred field: $($Property.Name)"
  }
  Assert-Equal $P0OnboardingIndependentReviewTemplate.identity.spec_id 'CAL_SPEC_EXTERNAL_CAPTURE_INDEPENDENT_REVIEW_HANDOFF_TEMPLATE_V1' 'P0 external-capture-onboarding review template identity'
  Assert-ExactArray (@($P0OnboardingIndependentReviewTemplate.gate_review_requests | ForEach-Object { [string]$_.gate_id })) $ExpectedP0GateIds 'P0 external-capture-onboarding review gate sequence'
  foreach ($Request in @($P0OnboardingIndependentReviewTemplate.gate_review_requests)) {
    foreach ($FieldName in @('external_manifest_entry_refs', 'review_outcome', 'review_reason')) {
      Assert-Null $Request.PSObject.Properties[$FieldName].Value "P0 external-capture-onboarding review deferred field: $($Request.gate_id)/$FieldName"
    }
  }
  Assert-AllRuntimeKeysNull $P0ExternalCaptureOnboarding 'P0 external-capture-onboarding contract'

  # P1 的结构预检故意不制造工程；当前仓库失败关闭，合成 fixture 也不能开启生产门禁。
  Assert-Equal $ConstructionPreflight.version 1 'P1 construction-preflight version'
  Assert-Equal $ConstructionPreflight.kind 'tianting-y3-construction-preflight' 'P1 construction-preflight kind'
  Assert-Equal $ConstructionPreflight.status 'structural-preflight-only' 'P1 construction-preflight status'
  Assert-Equal $ConstructionPreflight.production_gate 'closed' 'P1 construction-preflight production gate'
  Assert-Equal $ConstructionPreflight.identity.spec_id 'TT_SPEC_Y3_CONSTRUCTION_PREFLIGHT' 'P1 construction-preflight spec id'
  foreach ($FieldName in @('runtime_key', 'object_key', 'map_key', 'ui_key')) {
    Assert-Null $ConstructionPreflight.identity.PSObject.Properties[$FieldName].Value "P1 construction-preflight identity remains null: $FieldName"
  }
  Assert-Equal $ConstructionPreflight.current_workspace_fixture.expected_result 'fail_closed' 'P1 construction-preflight current workspace result'
  Assert-Condition ([string]$ConstructionPreflight.current_workspace_fixture.reason -match 'no map-local script/y3 or ui root') 'P1 construction-preflight current workspace reason'
  Assert-ExactArray $ConstructionPreflight.input_contract.y3_lualib_root.required_structure_directories @('meta', 'game') 'P1 construction-preflight required Y3 structural directories'
  Assert-Condition ($ConstructionPreflight.synthetic_fixture.contains_maps -eq $false) 'P1 construction-preflight synthetic fixture has no maps'
  Assert-Condition ($ConstructionPreflight.synthetic_fixture.contains_lua_files -eq $false) 'P1 construction-preflight synthetic fixture has no Lua files'
  Assert-Condition ($ConstructionPreflight.synthetic_fixture.contains_ui_nodes -eq $false) 'P1 construction-preflight synthetic fixture has no UI nodes'
  Assert-Condition ([string]($ConstructionPreflight.non_goals -join "\n") -match 'Create maps') 'P1 construction-preflight forbids map creation'
  Assert-Condition ([string]($ConstructionPreflight.non_goals -join "\n") -match 'Replace the separate P0') 'P1 construction-preflight preserves P0 gate'
  Assert-AllRuntimeKeysNull $ConstructionPreflight 'P1 construction-preflight contract'

  # P1 并行表面清单仅记录以后要读的事实；没有任何地图、UI、对象、资源或绝对字段绑定。
  Assert-Equal $SurfaceManifest.schema_version 1 'surface discovery manifest version'
  Assert-Equal $SurfaceManifest.identity.spec_id 'TT_SPEC_SURFACE_CONSTRUCTION_DISCOVERY_MANIFEST' 'surface discovery manifest spec id'
  Assert-Equal $SurfaceManifest.identity.package_status 'offline_preconstruction_discovery_only' 'surface discovery manifest package status'
  Assert-Equal $SurfaceManifest.identity.production_gate 'closed' 'surface discovery manifest production gate'
  Assert-Condition ($SurfaceManifest.identity.actual_y3_write_authorized -eq $false) 'surface discovery manifest does not authorize Y3 writes'
  foreach ($FieldName in @('runtime_key', 'actual_map_root', 'actual_map_key', 'actual_ui_root', 'actual_y3editor_session', 'actual_y3helper_session')) {
    Assert-Null $SurfaceManifest.identity.PSObject.Properties[$FieldName].Value "surface discovery identity remains null: $FieldName"
  }
  Assert-Equal $SurfaceManifest.non_write_contract.mode 'read_discover_validate_only' 'surface discovery manifest mode'
  Assert-Condition (@($SurfaceManifest.non_write_contract.prohibited_actions).Count -ge 6) 'surface discovery manifest prohibited-action coverage'
  Assert-Condition ([string]($SurfaceManifest.non_write_contract.prohibited_actions -join "\n") -match 'write terrain') 'surface discovery manifest forbids terrain writes'
  Assert-Condition ([string]($SurfaceManifest.non_write_contract.prohibited_actions -join "\n") -match 'Y3 UI JSON') 'surface discovery manifest forbids UI writes'
  foreach ($FieldName in @('project_root', 'map_root', 'map_key', 'ui_root', 'editor_session_id', 'helper_session_id', 'runtime_session_id')) {
    Assert-Null $SurfaceManifest.future_project_import_discovery.future_destination.PSObject.Properties[$FieldName].Value "surface discovery future destination remains null: $FieldName"
  }
  Assert-Equal @($SurfaceManifest.future_project_import_discovery.required_live_reads).Count 5 'surface discovery live-read gate count'
  Assert-Equal @($SurfaceManifest.map_whitebox_checklist.mainline_boss_whitebox_slices).Count 5 'surface discovery mainline whitebox slice count'
  Assert-Equal @($SurfaceManifest.ui_hud_checklist.surfaces).Count 3 'surface discovery HUD surface count'
  Assert-Equal @($SurfaceManifest.p0_asset_batch.profiles).Count 5 'surface discovery P0 asset batch count'
  Assert-Equal $SurfaceManifest.p0_asset_batch.status 'requirements_only_pending_p0_absolute_calibration' 'surface discovery P0 asset status'
  foreach ($Profile in @($SurfaceManifest.p0_asset_batch.profiles)) {
    foreach ($FieldName in @('unit_object_key', 'ability_object_keys', 'model_resource_id', 'animation_resource_ids', 'effect_resource_ids', 'sound_resource_ids', 'material_resource_ids', 'hp_max', 'attack_value', 'physical_defense', 'magical_defense', 'attack_interval_seconds', 'move_speed')) {
      Assert-Null $Profile.future_object_and_resource_binding.PSObject.Properties[$FieldName].Value "surface discovery P0 asset field remains null: $($Profile.blueprint_spec_id)/$FieldName"
    }
  }
  Assert-AllRuntimeKeysNull $SurfaceManifest 'surface construction discovery manifest'

  # P2 七星参考模型只复核既有权威会话语义；它没有真实进度、掉落、称号、资格或经济输出。
  Assert-Equal $SevenStarSessionReference.version 1 'P2 seven-star reference version'
  Assert-Equal $SevenStarSessionReference.spec_id 'TT_SPEC_SEVEN_STAR_SOLO_SESSION_REFERENCE' 'P2 seven-star reference spec id'
  Assert-Equal $SevenStarSessionReference.package_status 'offline-reference-model-only' 'P2 seven-star reference package status'
  Assert-Equal $SevenStarSessionReference.production_gate 'closed' 'P2 seven-star reference production gate'
  Assert-Condition ($SevenStarSessionReference.non_production -eq $true) 'P2 seven-star reference remains non-production'
  Assert-Condition (-not (Test-HasProperty $SevenStarSessionReference 'runtime_key')) 'P2 seven-star reference deliberately creates no runtime key field'
  Assert-Equal $SevenStarSessionReference.scope.kind 'single_player_repeatable_session_reference' 'P2 seven-star reference scope kind'
  Assert-Equal $SevenStarSessionReference.scope.owner_scope 'character' 'P2 seven-star owner scope'
  Assert-Equal @($SevenStarSessionReference.scope.source_contracts).Count 4 'P2 seven-star source-contract count'
  foreach ($SourcePath in @($SevenStarSessionReference.scope.source_contracts)) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $SevenStarSessionReferenceRoot $SourcePath) -PathType Leaf) "P2 seven-star source contract exists: $SourcePath"
  }
  Assert-Equal $SevenStarSessionReference.entry.actor_scope 'owner_only' 'P2 seven-star owner-only admission'
  Assert-Equal $SevenStarSessionReference.entry.required_progress_spec_id 'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN' 'P2 seven-star observatory admission'
  Assert-Equal $SevenStarSessionReference.entry.caller_progress_fields 'not_authoritative' 'P2 seven-star caller progress is non-authoritative'
  Assert-ExactArray (@($SevenStarSessionReference.route_registry | ForEach-Object { [string]$_.spec_id })) @('TT_SPEC_SOLO_TIANSHU', 'TT_SPEC_SOLO_TIANXUAN', 'TT_SPEC_SOLO_TIANJI', 'TT_SPEC_SOLO_TIANQUAN', 'TT_SPEC_SOLO_YUHENG', 'TT_SPEC_SOLO_KAIYANG', 'TT_SPEC_SOLO_YAOGUANG') 'P2 seven-star fixed route registry'
  Assert-ExactArray $SevenStarSessionReference.session_identity_fields @('owner_actor_id', 'lifecycle_id', 'session_instance_id', 'session_epoch', 'revision', 'cleanup_token') 'P2 seven-star session identity'
  Assert-ExactArray $SevenStarSessionReference.state_machine.states @('active', 'cleanup_pending', 'closed') 'P2 seven-star state lifecycle'
  Assert-ExactArray $SevenStarSessionReference.state_machine.allowed_transitions @('active -> cleanup_pending', 'cleanup_pending -> closed') 'P2 seven-star state transitions'
  Assert-ExactArray $SevenStarSessionReference.state_machine.failure_reasons @('owner_death', 'timeout', 'owner_disconnect', 'owner_lifecycle_invalid') 'P2 seven-star failure reasons'
  Assert-Equal $SevenStarSessionReference.state_machine.reentry_before_matching_cleanup 'denied' 'P2 seven-star cleanup reentry lock'
  Assert-Equal $SevenStarSessionReference.state_machine.reconnect 'not_supported_for_the_same_session' 'P2 seven-star same-session reconnect prohibition'
  Assert-Condition ($SevenStarSessionReference.completion.logical_progression_write -eq $false) 'P2 seven-star cannot write logical progression'
  Assert-Condition ($SevenStarSessionReference.completion.process_local_record_only -eq $true) 'P2 seven-star completion is process-local only'
  Assert-Condition ([string]$SevenStarSessionReference.completion.cleanup_rule -match 'remains retained') 'P2 seven-star completion survives cleanup failure'
  Assert-ExactArray $SevenStarSessionReference.completion.prohibited_outputs @('reward', 'drop', 'material_grant', 'title_grant', 'graduation_artifact', 'receipt', 'economy_v2_handoff', 'qualification') 'P2 seven-star prohibited outputs'
  Assert-ExactArray $SevenStarSessionReference.idempotency.request_key_fields @('operation', 'request_id') 'P2 seven-star idempotency key'
  Assert-Equal $SevenStarSessionReference.idempotency.same_payload 'return_existing_process_local_result' 'P2 seven-star idempotent replay result'
  Assert-Equal $SevenStarSessionReference.idempotency.payload_drift 'reject' 'P2 seven-star payload drift rejection'
  Assert-Equal $SevenStarSessionReference.execution.dependencies 'Node.js standard library only' 'P2 seven-star execution dependency boundary'
  Assert-Condition ($SevenStarSessionReference.execution.network -eq $false) 'P2 seven-star network disabled'
  Assert-Condition ($SevenStarSessionReference.execution.persistence -eq $false) 'P2 seven-star persistence disabled'
  Assert-ExactArray $SevenStarSessionReference.prohibited_surfaces @('Y3 runtime', 'Lua', 'map assets', 'UI assets', 'object data', 'absolute combat values', 'drops', 'material or title grants', 'economy-v2 input', 'runtime keys') 'P2 seven-star prohibited surfaces'

  # P3 星宿参考模型只接收注入夹具，不能读取真实时间或成为团本、资格、结算服务。
  Assert-Equal $MansionSessionReferencePackage.schema_version 1 'P3 mansion reference package version'
  Assert-Equal $MansionSessionReferencePackage.package 'tianting-mansion-session-reference' 'P3 mansion reference package name'
  Assert-Equal $MansionSessionReferencePackage.package_status 'offline-reference-only' 'P3 mansion reference package status'
  Assert-Condition ($MansionSessionReferencePackage.runtime_handoff -eq $false) 'P3 mansion reference runtime handoff remains false'
  Assert-Equal $MansionSessionReferencePackage.production_gate 'closed' 'P3 mansion reference production gate'
  Assert-Equal $MansionSessionReferencePackage.primary_contract 'contract/mansion-session-time-qualification-reference-contract.json' 'P3 mansion reference primary contract'
  foreach ($SourcePath in @($MansionSessionReferencePackage.source_contracts)) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $MansionSessionReferenceRoot $SourcePath) -PathType Leaf) "P3 mansion source contract exists: $SourcePath"
  }
  foreach ($Property in $MansionSessionReferencePackage.boundaries.PSObject.Properties) {
    Assert-Condition ($Property.Value -eq $false) "P3 mansion reference boundary remains false: $($Property.Name)"
  }
  foreach ($Property in $MansionSessionReferencePackage.deferred.PSObject.Properties) {
    Assert-Null $Property.Value "P3 mansion reference deferred field: $($Property.Name)"
  }
  Assert-Equal $MansionSessionReference.schema_version 1 'P3 mansion reference contract version'
  Assert-Equal $MansionSessionReference.identity.spec_id 'TT_SPEC_MANSION_SESSION_TIME_QUALIFICATION_REFERENCE' 'P3 mansion reference contract spec id'
  Assert-Null $MansionSessionReference.identity.runtime_key 'P3 mansion reference contract runtime key'
  Assert-Equal $MansionSessionReference.package_status 'offline-reference-only' 'P3 mansion reference contract status'
  Assert-Condition ($MansionSessionReference.runtime_handoff -eq $false) 'P3 mansion reference contract runtime handoff remains false'
  Assert-Equal $MansionSessionReference.production_gate 'closed' 'P3 mansion reference contract production gate'
  Assert-Equal $MansionSessionReference.authority_time_input.timezone 'Asia/Shanghai' 'P3 mansion reference timezone'
  Assert-Condition ([string]$MansionSessionReference.authority_time_input.input_policy -match '仅接受注入') 'P3 mansion reference injected-time policy'
  Assert-ExactArray $MansionSessionReference.authority_time_input.required_fields @('rotation_snapshot_id', 'schedule_version', 'authoritative_time_slot', 'authority_time_basis_id', 'captured_authoritative_instant', 'schema_version', 'timezone') 'P3 mansion reference authority-time fields'
  Assert-ExactArray $MansionSessionReference.authority_time_input.derived_snapshot_fields @('rotation_snapshot_id', 'schedule_version', 'authoritative_time_slot', 'quadrant', 'difficulty', 'instance_scope', 'authority_time_basis_id', 'captured_authoritative_instant', 'schema_version') 'P3 mansion reference frozen snapshot fields'
  foreach ($Slot in @('子', '辰', '申')) { Assert-Equal $MansionSessionReference.authority_time_input.slot_to_quadrant.PSObject.Properties[$Slot].Value '东方青龙' "P3 mansion azure slot: $Slot" }
  foreach ($Slot in @('丑', '巳', '酉')) { Assert-Equal $MansionSessionReference.authority_time_input.slot_to_quadrant.PSObject.Properties[$Slot].Value '南方朱雀' "P3 mansion vermilion slot: $Slot" }
  foreach ($Slot in @('寅', '午', '戌')) { Assert-Equal $MansionSessionReference.authority_time_input.slot_to_quadrant.PSObject.Properties[$Slot].Value '西方白虎' "P3 mansion white-tiger slot: $Slot" }
  foreach ($Slot in @('卯', '未', '亥')) { Assert-Equal $MansionSessionReference.authority_time_input.slot_to_quadrant.PSObject.Properties[$Slot].Value '北方玄武' "P3 mansion black-tortoise slot: $Slot" }
  Assert-ExactArray $MansionSessionReference.authority_time_input.rejected_client_fields @('client_clock', 'client_timezone', 'client_quadrant', 'requested_quadrant', 'retry_time_slot', 'local_time') 'P3 mansion rejected client-time fields'
  Assert-Condition ([string]$MansionSessionReference.authority_time_input.retry_rule -match '不能提交新的时辰输入') 'P3 mansion retry cannot recalculate time'
  Assert-Equal $MansionSessionReference.session.spec_id 'TT_SPEC_MANSION_RAID_SESSION_REFERENCE' 'P3 mansion session spec id'
  Assert-Equal $MansionSessionReference.session.kind 'team_raid' 'P3 mansion session kind'
  Assert-Equal $MansionSessionReference.session.participant_capacity.minimum 1 'P3 mansion minimum members'
  Assert-Equal $MansionSessionReference.session.participant_capacity.maximum 4 'P3 mansion maximum members'
  Assert-ExactArray $MansionSessionReference.session.identity_fields @('raid_instance_id', 'boss_instance_id', 'session_epoch', 'phase_id', 'revision', 'cleanup_token') 'P3 mansion session identity'
  Assert-ExactArray $MansionSessionReference.session.frozen_member_fields @('actor_id', 'actor_lifecycle_id', 'membership_snapshot_id', 'member_status') 'P3 mansion frozen member fields'
  Assert-ExactArray $MansionSessionReference.session.state_sequence @('active', 'cleanup_pending', 'closed') 'P3 mansion session state lifecycle'
  Assert-Equal $MansionSessionReference.session.reentry_before_matching_cleanup 'denied' 'P3 mansion cleanup reentry lock'
  Assert-Equal $MansionSessionReference.admission.normal.difficulty 'normal' 'P3 mansion normal difficulty'
  Assert-Condition ([string]$MansionSessionReference.admission.normal.per_member_mainline_rule -match 'TT_SPEC_PROGRESS_MAINLINE_CLEARED') 'P3 mansion normal per-member mainline admission'
  Assert-Equal $MansionSessionReference.admission.nightmare.difficulty 'nightmare' 'P3 mansion nightmare difficulty'
  Assert-Equal $MansionSessionReference.admission.nightmare.quadrant_match_rule 'normal_clear.quadrant == credential.quadrant == nightmare.rotation_snapshot.quadrant' 'P3 mansion nightmare quadrant match'
  Assert-ExactArray $MansionSessionReference.admission.rejected_member_classes @('leader_without_individual_mainline_completion', 'member_without_individual_mainline_completion', 'spectator', 'unfrozen_teammate', 'stale_lifecycle_member', 'client_injected_member') 'P3 mansion rejected members'
  Assert-Condition ([string]$MansionSessionReference.recovery_and_outcome.left_member_rule -match '不能在当前 raid_instance_id 重连') 'P3 mansion left member cannot reconnect'
  Assert-Condition ([string]$MansionSessionReference.recovery_and_outcome.remaining_active_rule -match 'active.*可继续') 'P3 mansion active members can continue'
  Assert-Condition ([string]$MansionSessionReference.recovery_and_outcome.cleanup_rule -match 'cleanup_token') 'P3 mansion cleanup token required'
  Assert-Condition ([string]$MansionSessionReference.recovery_and_outcome.completion_durability_rule -match '不会被回滚') 'P3 mansion completion is durable'
  Assert-Condition ([string]$MansionSessionReference.recovery_and_outcome.idempotency_rule -match '仅返回首次结果') 'P3 mansion idempotency returns first result'
  foreach ($Property in $MansionSessionReference.deferred.PSObject.Properties) {
    Assert-Null $Property.Value "P3 mansion contract deferred field: $($Property.Name)"
  }
  $MansionCredentialCrosswalk = $MansionSessionReference.nightmare_fixture_to_authority_crosswalk
  Assert-Equal $MansionCredentialCrosswalk.authority_semantic_source.artifact '../../../docs/物编/天庭篇主线遭遇与通天塔规格包/authority/tianting-progression-and-instance-authority-contract.json' 'P3 mansion credential crosswalk authority artifact'
  Assert-Condition (Test-Path -LiteralPath (Join-Path (Join-Path $MansionSessionReferenceRoot 'contract') $MansionCredentialCrosswalk.authority_semantic_source.artifact) -PathType Leaf) 'P3 mansion credential crosswalk authority artifact exists'
  Assert-Equal $MansionCredentialCrosswalk.authority_semantic_source.contract_property 'nightmare_qualification_contract' 'P3 mansion credential crosswalk authority property'
  Assert-Equal $MansionCredentialCrosswalk.authority_semantic_source.spec_id $Authority.nightmare_qualification_contract.spec_id 'P3 mansion credential crosswalk authority spec id'
  Assert-Equal $MansionCredentialCrosswalk.authority_semantic_source.semantic_ownership 'unique' 'P3 mansion credential semantics remain uniquely upstream-owned'
  Assert-ExactArray $MansionCredentialCrosswalk.authority_semantic_source.required_fields @($Authority.nightmare_qualification_contract.required_fields) 'P3 mansion credential crosswalk uses upper required fields'
  Assert-Equal $MansionCredentialCrosswalk.fixture_adapter_status 'test_only_not_an_independent_schema' 'P3 mansion credential fixture is adapter-only'
  foreach ($FieldName in @($Authority.nightmare_qualification_contract.required_fields)) {
    if ($FieldName -eq 'nightmare_access_credential') {
      Assert-Condition (Test-HasProperty $MansionCredentialCrosswalk.field_crosswalk 'opaque_credential_ref') 'P3 mansion credential crosswalk adapts the upstream opaque credential field'
    }
    else {
      Assert-Condition (Test-HasProperty $MansionCredentialCrosswalk.field_crosswalk $FieldName) "P3 mansion credential crosswalk includes upstream field: $FieldName"
    }
  }
  Assert-Condition ([string]$MansionCredentialCrosswalk.field_crosswalk.credential_quadrant -match 'fixture-only') 'P3 mansion credential quadrant is fixture-only'
  Assert-Condition ([string]$MansionCredentialCrosswalk.field_crosswalk.opaque_credential_ref -match 'fixture-only') 'P3 mansion opaque credential handle is fixture-only'
  Assert-ExactArray $MansionCredentialCrosswalk.adapter_prohibitions @('fixture field names must not override, extend, or replace the upper required_fields list', 'fixture qualification input must not define a runtime credential representation', 'fixture qualification input must not define any ownership, consumption, persistence, value, or settlement behavior') 'P3 mansion credential adapter prohibitions'
  Assert-AllRuntimeKeysNull $MansionSessionReferencePackage 'P3 mansion reference package'
  Assert-AllRuntimeKeysNull $MansionSessionReference 'P3 mansion reference contract'

  # P3's choreography is a semantic state graph over an already-authoritative
  # session.  It must never become a parallel owner of session, member or
  # completion state, even though it defines the future encounter sequencing.
  Assert-Equal $MansionEncounterOrchestration.version 1 'mansion encounter choreography version'
  Assert-Equal $MansionEncounterOrchestration.package_status 'offline-encounter-choreography-spec' 'mansion encounter choreography package status'
  Assert-Equal $MansionEncounterOrchestration.production_gate 'closed' 'mansion encounter choreography production gate'
  Assert-Condition ($MansionEncounterOrchestration.runtime_handoff -eq $false) 'mansion encounter choreography has no runtime handoff'
  Assert-Equal $MansionEncounterOrchestration.identity.spec_id 'TT_SPEC_TIANTING_MANSION_ENCOUNTER_ORCHESTRATION' 'mansion encounter choreography spec id'
  Assert-Equal $MansionEncounterOrchestration.identity.scope 'mansion_normal_and_same_quadrant_nightmare_semantic_choreography_only' 'mansion encounter choreography scope'
  foreach ($FieldName in @('runtime_key', 'map_key', 'object_id', 'ability_id', 'ui_node_id', 'resource_id')) {
    Assert-Null $MansionEncounterOrchestration.identity.PSObject.Properties[$FieldName].Value "mansion encounter choreography identity remains null: $FieldName"
  }
  Assert-Equal @($MansionEncounterOrchestration.source_contracts).Count 7 'mansion encounter choreography source-contract count'
  foreach ($Source in @($MansionEncounterOrchestration.source_contracts)) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $MansionEncounterOrchestrationRoot $Source.path) -PathType Leaf) "mansion encounter choreography source exists: $($Source.path)"
  }
  $MansionBoundaries = $MansionEncounterOrchestration.hard_boundaries
  Assert-Equal $MansionBoundaries.authority_ownership.session_owner 'existing_authority_contract_only' 'mansion encounter choreography retains authority session owner'
  Assert-Equal $MansionBoundaries.authority_ownership.session_lifecycle 'active_to_cleanup_pending_to_closed_is_not_an_encounter_state_machine' 'mansion encounter choreography cannot replace session lifecycle'
  foreach ($ForbiddenMutation in @('phase_id', 'revision', 'cleanup_token', 'member_status', 'progression', 'nightmare_credential', 'reward', 'receipt', 'economy_input')) {
    Assert-Condition (@($MansionBoundaries.authority_ownership.forbidden_mutations) -contains $ForbiddenMutation) "mansion encounter choreography forbids authority mutation: $ForbiddenMutation"
  }
  Assert-Condition ([string]$MansionBoundaries.authority_ownership.cleanup_token_rule -match 'never a player mechanism input') 'mansion encounter choreography protects cleanup token'
  Assert-Condition ([string]$MansionBoundaries.authority_ownership.completion_rule -match 'not a session completion write') 'mansion encounter choreography cannot write completion'
  Assert-ExactArray $MansionBoundaries.transition_binding.future_authority_binding_fields @('raid_instance_id', 'boss_instance_id', 'session_epoch', 'phase_id', 'revision', 'rotation_snapshot_id', 'quadrant', 'difficulty', 'actor_id', 'actor_lifecycle_id', 'membership_snapshot_id', 'member_status') 'mansion encounter choreography authority transition binding'
  Assert-ExactArray $MansionBoundaries.transition_binding.encounter_local_semantic_fields @('encounter_beat_spec_id', 'encounter_state_spec_id', 'transition_index') 'mansion encounter choreography local semantic fields'
  foreach ($ForbiddenInput in @('cleanup_token', 'client_clock', 'client_timezone', 'client_quadrant', 'local_timer', 'damage_meter', 'local_ui_state', 'unfrozen_member', 'client_reported_member_status', 'left_member', 'dead_member', 'stale_lifecycle')) {
    Assert-Condition (@($MansionBoundaries.transition_binding.forbidden_transition_inputs) -contains $ForbiddenInput) "mansion encounter choreography forbids mechanism input: $ForbiddenInput"
  }
  Assert-Equal $MansionBoundaries.transition_binding.replay_drift_policy 'reject' 'mansion encounter choreography replay drift policy'
  Assert-Condition ([string]$MansionBoundaries.transition_binding.authority_member_snapshot_rule -match 'membership_snapshot_id') 'mansion encounter choreography binds authority member snapshot identity'
  foreach ($Property in $MansionBoundaries.runtime_and_asset_bindings.PSObject.Properties) {
    Assert-Null $Property.Value "mansion encounter choreography runtime or asset field remains null: $($Property.Name)"
  }
  foreach ($Property in $MansionBoundaries.numeric_fields.PSObject.Properties) {
    Assert-Null $Property.Value "mansion encounter choreography numeric field remains null: $($Property.Name)"
  }
  foreach ($Property in $MansionBoundaries.economy_and_progression.PSObject.Properties) {
    Assert-Null $Property.Value "mansion encounter choreography economy or progression field remains null: $($Property.Name)"
  }
  $MansionGrammar = $MansionEncounterOrchestration.semantic_state_grammar
  Assert-ExactArray $MansionGrammar.normal_segment_sequence @('segment_read', 'lead_signature_telegraph', 'support_relation_commit', 'combined_counterplay', 'visible_readback', 'recover_or_transition') 'mansion encounter normal semantic sequence'
  Assert-ExactArray $MansionGrammar.nightmare_state_sequence @('resonance_visible', 'officer_counterplay', 'purified_officer_aid', 'sacred_core_restoration') 'mansion encounter nightmare semantic sequence'
  Assert-Condition ([string]$MansionGrammar.state_ownership_rule -match 'must not reuse') 'mansion encounter semantic states cannot reuse phase_id'
  Assert-Condition ([string]$MansionGrammar.terminal_candidate_rule -match 'read-only') 'mansion encounter terminal candidate remains read-only'
  $MansionTransitionGraph = $MansionGrammar.transition_graph
  Assert-ExactArray $MansionTransitionGraph.normal_states @('TT_SPEC_MANSION_NORMAL_FRONT_PAIR', 'TT_SPEC_MANSION_NORMAL_MIDDLE_PAIR', 'TT_SPEC_MANSION_NORMAL_REAR_PAIR', 'TT_SPEC_MANSION_NORMAL_GUARD_SINGLE', 'TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE') 'mansion encounter normal state graph'
  Assert-ExactArray $MansionTransitionGraph.nightmare_states @('TT_SPEC_MANSION_NIGHTMARE_CHAIN_01', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_02', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_03', 'TT_SPEC_MANSION_NIGHTMARE_CHAIN_04', 'TT_SPEC_MANSION_NIGHTMARE_SACRED_CORE_RESTORATION', 'TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE') 'mansion encounter nightmare state graph'
  Assert-Condition ([string]$MansionTransitionGraph.recovery_rule -match 'cannot increment transition_index') 'mansion encounter recovery cannot increment transition index'
  Assert-Condition ([string]$MansionTransitionGraph.transition_index_rule -match 'strictly monotonic') 'mansion encounter transition index is monotonic'
  Assert-Condition ([string]$MansionTransitionGraph.transition_index_rule -match 'skip, reversal') 'mansion encounter transition graph rejects skips and reversals'
  $MansionMemberChange = $MansionEncounterOrchestration.concurrency_and_member_change
  Assert-Condition ([string]$MansionMemberChange.pressure_budget.one_active_member -match 'one primary P0') 'mansion encounter single-member pressure has one P0'
  Assert-Condition ([string]$MansionMemberChange.pressure_budget.two_to_four_active_members -match 'one primary P0') 'mansion encounter multiplayer pressure has one P0'
  Assert-Condition ([string]$MansionMemberChange.member_change_rule -match 'authority-confirmed') 'mansion encounter member changes require authority confirmation'
  Assert-Condition ([string]$MansionMemberChange.dead_or_left_rule -match 'cannot advance') 'mansion encounter dead or left member cannot advance a beat'
  $ExpectedMansionQuadrants = @('东方青龙', '南方朱雀', '西方白虎', '北方玄武')
  $MansionNormal = $MansionEncounterOrchestration.normal_raid
  Assert-Equal $MansionNormal.spec_id 'TT_SPEC_MANSION_NORMAL_ENCOUNTER_CHOREOGRAPHY' 'mansion encounter normal identity'
  Assert-ExactArray $MansionNormal.segment_shape @('front_pair', 'middle_pair', 'rear_pair', 'guard_single') 'mansion encounter normal segment shape'
  Assert-ExactArray (@($MansionNormal.quadrant_segments | ForEach-Object { [string]$_.quadrant })) $ExpectedMansionQuadrants 'mansion encounter normal quadrant order'
  foreach ($QuadrantProfile in @($MansionNormal.quadrant_segments)) {
    Assert-ExactArray (@($QuadrantProfile.segments | ForEach-Object { [string]$_.segment })) @('front_pair', 'middle_pair', 'rear_pair', 'guard_single') "mansion encounter normal segment order: $($QuadrantProfile.quadrant)"
    Assert-ExactNumericArray (@($QuadrantProfile.segments | ForEach-Object { [double](@($_.officers).Count) })) @(2, 2, 2, 1) "mansion encounter normal segment size: $($QuadrantProfile.quadrant)"
  }
  Assert-Equal @($MansionNormal.officer_choreography_profiles).Count 28 'mansion encounter officer choreography profile count'
  foreach ($Profile in @($MansionNormal.officer_choreography_profiles)) {
    foreach ($FieldName in @('read', 'commit', 'counter', 'failure_recovery')) {
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Profile.PSObject.Properties[$FieldName].Value)) "mansion encounter officer profile field: $($Profile.spec_id)/$FieldName"
    }
    foreach ($FieldName in @('one', 'two', 'three', 'four', 'member_loss')) {
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Profile.adaptation.PSObject.Properties[$FieldName].Value)) "mansion encounter officer profile adaptation: $($Profile.spec_id)/$FieldName"
    }
    Assert-Null $Profile.runtime_binding "mansion encounter officer profile runtime binding: $($Profile.spec_id)"
  }
  Assert-Condition ([string]$MansionNormal.terminal_candidate.precondition -match 'four ordered 2\+2\+2\+1') 'mansion encounter normal terminal requires exact segments'
  Assert-Equal $MansionNormal.terminal_candidate.result 'TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE' 'mansion encounter normal terminal identity'
  foreach ($FieldName in @('session_completion_write', 'qualification_write', 'credential_write', 'reward', 'receipt', 'economy_input')) {
    Assert-Null $MansionNormal.terminal_candidate.PSObject.Properties[$FieldName].Value "mansion encounter normal terminal output remains null: $FieldName"
  }
  $MansionNightmare = $MansionEncounterOrchestration.nightmare_four_sacred
  Assert-Equal $MansionNightmare.spec_id 'TT_SPEC_MANSION_NIGHTMARE_ENCOUNTER_CHOREOGRAPHY' 'mansion encounter nightmare identity'
  Assert-Condition ([string]$MansionNightmare.same_quadrant_rule -match 'one exact quadrant') 'mansion encounter nightmare remains same-quadrant only'
  Assert-Condition ([string]$MansionNightmare.active_chain_rule -match 'one primary') 'mansion encounter nightmare retains one primary chain'
  Assert-Condition ([string]$MansionNightmare.purification_rule -match 'monotonic') 'mansion encounter nightmare purification is monotonic'
  Assert-ExactArray (@($MansionNightmare.quadrant_profiles | ForEach-Object { [string]$_.quadrant })) $ExpectedMansionQuadrants 'mansion encounter nightmare quadrant order'
  foreach ($QuadrantProfile in @($MansionNightmare.quadrant_profiles)) {
    Assert-ExactNumericArray (@($QuadrantProfile.chain_rounds | ForEach-Object { [double](@($_).Count) })) @(2, 2, 2, 1) "mansion encounter nightmare chain sizes: $($QuadrantProfile.quadrant)"
    foreach ($FieldName in @('purified_aid', 'sacred_response', 'failure_recovery', 'core_restoration')) {
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$QuadrantProfile.PSObject.Properties[$FieldName].Value)) "mansion encounter nightmare profile field: $($QuadrantProfile.spec_id)/$FieldName"
    }
  }
  Assert-Condition ([string]$MansionNightmare.terminal_candidate.precondition -match 'exactly the seven') 'mansion encounter nightmare terminal requires all seven officers'
  Assert-Equal $MansionNightmare.terminal_candidate.result 'TT_SPEC_MANSION_ENCOUNTER_TERMINAL_CANDIDATE' 'mansion encounter nightmare terminal identity'
  foreach ($FieldName in @('session_completion_write', 'qualification_write', 'credential_write', 'reward', 'receipt', 'economy_input')) {
    Assert-Null $MansionNightmare.terminal_candidate.PSObject.Properties[$FieldName].Value "mansion encounter nightmare terminal output remains null: $FieldName"
  }
  Assert-ExactArray (@($MansionEncounterOrchestration.acceptance | ForEach-Object { [string]$_.id })) @('TT-MANSION-CHOREO-ACC-001', 'TT-MANSION-CHOREO-ACC-002', 'TT-MANSION-CHOREO-ACC-003', 'TT-MANSION-CHOREO-ACC-004', 'TT-MANSION-CHOREO-ACC-005', 'TT-MANSION-CHOREO-ACC-006', 'TT-MANSION-CHOREO-ACC-007', 'TT-MANSION-CHOREO-ACC-008', 'TT-MANSION-CHOREO-ACC-009') 'mansion encounter choreography acceptance ids'
  Assert-Condition ($MansionEncounterOrchestrationMarkdown -match 'production_gate = closed') 'mansion encounter choreography Markdown states closed production gate'
  Assert-Condition ($MansionEncounterOrchestrationMarkdown -match 'membership_snapshot_id') 'mansion encounter choreography Markdown names authority membership snapshot'
  Assert-Condition ($MansionEncounterOrchestrationMarkdown -match 'transition_index') 'mansion encounter choreography Markdown documents transition index'
  Assert-Condition ($MansionEncounterOrchestrationMarkdown -match '2 \+ 2 \+ 2 \+ 1') 'mansion encounter choreography Markdown documents fixed chain shape'
  Assert-Condition ($MansionEncounterOrchestrationMarkdown -match 'null/deferred') 'mansion encounter choreography Markdown documents deferred implementation surface'
  Assert-AllRuntimeKeysNull $MansionEncounterOrchestration 'mansion encounter choreography contract'

  # 五组主线表现只组织可读叙事，所有权威、资产、数值与经济字段仍然关闭。
  Assert-Equal $MainlinePresentation.version 1 'mainline presentation contract version'
  Assert-Equal $MainlinePresentation.package_status 'offline-narrative-presentation-spec' 'mainline presentation package status'
  Assert-Equal $MainlinePresentation.production_gate 'closed' 'mainline presentation production gate'
  Assert-Equal $MainlinePresentation.identity.spec_id 'TT_SPEC_TIANTING_MAINLINE_NARRATIVE_PRESENTATION' 'mainline presentation spec id'
  Assert-Equal $MainlinePresentation.identity.scope 'five_non_tower_mainline_bosses_narrative_presentation_only' 'mainline presentation scope'
  foreach ($FieldName in @('runtime_key', 'map_key', 'ui_node_id', 'object_id', 'resource_id')) {
    Assert-Null $MainlinePresentation.identity.PSObject.Properties[$FieldName].Value "mainline presentation identity remains null: $FieldName"
  }
  Assert-Equal @($MainlinePresentation.source_contracts).Count 6 'mainline presentation source-contract count'
  foreach ($Source in @($MainlinePresentation.source_contracts)) {
    Assert-Condition (Test-Path -LiteralPath (Join-Path $MainlinePresentationRoot $Source.path) -PathType Leaf) "mainline presentation source exists: $($Source.path)"
  }
  Assert-Condition ($MainlinePresentation.hard_boundaries.original_summary_only -eq $true) 'mainline presentation uses original summaries only'
  Assert-Condition ($MainlinePresentation.hard_boundaries.source_literature.original_text_used -eq $false) 'mainline presentation contains no original text'
  Assert-Condition ($MainlinePresentation.hard_boundaries.source_literature.external_literature_reference_used -eq $false) 'mainline presentation contains no external literature reference'
  Assert-Condition ([string]$MainlinePresentation.hard_boundaries.authority_rule -match '不判断成功') 'mainline presentation cannot adjudicate authority'
  foreach ($Property in $MainlinePresentation.hard_boundaries.runtime_and_asset_bindings.PSObject.Properties) {
    Assert-Null $Property.Value "mainline presentation runtime or asset binding remains null: $($Property.Name)"
  }
  foreach ($Property in $MainlinePresentation.hard_boundaries.numeric_fields.PSObject.Properties) {
    Assert-Null $Property.Value "mainline presentation numeric field remains null: $($Property.Name)"
  }
  foreach ($Property in $MainlinePresentation.hard_boundaries.progression_and_settlement.PSObject.Properties) {
    Assert-Null $Property.Value "mainline presentation progression or settlement field remains null: $($Property.Name)"
  }
  Assert-ExactArray (@($MainlinePresentation.boss_presentation_profiles | ForEach-Object { [string]$_.spec_id })) @('TT_SPEC_MAINLINE_PRESENTATION_SPLIT_SOUTH_GATE', 'TT_SPEC_MAINLINE_PRESENTATION_BROKEN_RAINBOW_FORMATION', 'TT_SPEC_MAINLINE_PRESENTATION_FOUR_GATE_IMBALANCE', 'TT_SPEC_MAINLINE_PRESENTATION_CELESTIAL_OBSERVATORY', 'TT_SPEC_MAINLINE_PRESENTATION_LINGXIAO_OUTER_COURT') 'mainline presentation profile coverage'
  foreach ($Profile in @($MainlinePresentation.boss_presentation_profiles)) {
    Assert-Condition ([string]$Profile.source_boss_spec_id -match '^TT_SPEC_MAINLINE_BOSS_') "mainline presentation source Boss identity: $($Profile.spec_id)"
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Profile.entry_guidance.player_facing_brief)) "mainline presentation player-facing brief: $($Profile.spec_id)"
    Assert-Equal @($Profile.stage_anchors).Count 3 "mainline presentation stage-anchor count: $($Profile.spec_id)"
    foreach ($Anchor in @($Profile.stage_anchors)) {
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Anchor.warning_copy.structural_channel)) "mainline presentation structural warning: $($Profile.spec_id)/$($Anchor.anchor_label)"
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Anchor.warning_copy.independent_channel)) "mainline presentation independent warning: $($Profile.spec_id)/$($Anchor.anchor_label)"
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Anchor.warning_copy.accessibility_alternative)) "mainline presentation accessibility alternative: $($Profile.spec_id)/$($Anchor.anchor_label)"
    }
    Assert-Equal @($Profile.failure_debrief_skeleton).Count 3 "mainline presentation failure-debrief count: $($Profile.spec_id)"
    foreach ($FieldName in @('progression_write', 'reward', 'receipt', 'economy_input')) {
      Assert-Null $Profile.non_economic_narrative_confirmation.PSObject.Properties[$FieldName].Value "mainline presentation non-economic confirmation: $($Profile.spec_id)/$FieldName"
    }
    foreach ($Layer in @('L0', 'L1', 'L2', 'L3', 'L4')) {
      Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$Profile.presentation_layers.vfx_layer_intent.PSObject.Properties[$Layer].Value)) "mainline presentation VFX responsibility: $($Profile.spec_id)/$Layer"
    }
    foreach ($FieldName in @('actual_camera_path', 'audio_asset', 'vfx_asset')) {
      Assert-Null $Profile.presentation_layers.PSObject.Properties[$FieldName].Value "mainline presentation actual layer binding: $($Profile.spec_id)/$FieldName"
    }
    foreach ($Property in $Profile.runtime_bindings.PSObject.Properties) {
      Assert-Null $Property.Value "mainline presentation runtime binding: $($Profile.spec_id)/$($Property.Name)"
    }
  }
  Assert-ExactArray (@($MainlinePresentation.acceptance | ForEach-Object { [string]$_.id })) @('TT-PRESENTATION-ACC-001', 'TT-PRESENTATION-ACC-002', 'TT-PRESENTATION-ACC-003', 'TT-PRESENTATION-ACC-004', 'TT-PRESENTATION-ACC-005', 'TT-PRESENTATION-ACC-006') 'mainline presentation acceptance ids'
  Assert-AllRuntimeKeysNull $MainlinePresentation 'mainline presentation contract'

  # 纵切只在受信任 Node/Fengari 离线边界运行，不为玩家会话注册 Y3 或经济运行时。
  Assert-Equal $VerticalPackage.version 1 'authority vertical-slice package version'
  Assert-Equal $VerticalPackage.package_status 'offline-tested-reference-only' 'authority vertical-slice package status'
  Assert-Equal $VerticalPackage.production_gate 'closed' 'authority vertical-slice production gate'
  Assert-Condition ($VerticalPackage.runtime_handoff -eq $false) 'authority vertical-slice runtime handoff remains false'
  Assert-Equal $VerticalPackage.identity.spec_id 'TT_SPEC_AUTHORITY_RUNTIME_VERTICAL_SLICE' 'authority vertical-slice spec id'
  Assert-Null $VerticalPackage.identity.runtime_key 'authority vertical-slice runtime key'
  Assert-Condition ($VerticalPackage.authority_contract.protected_difu_progress_key_consumer -eq $false) 'authority vertical-slice does not consume protected Difu key'
  Assert-Equal $VerticalPackage.authority_contract.protected_difu_progress_key 'DF_PROGRESS_YANLUO_HALL_CLEARED' 'authority vertical-slice protected Difu key identity'
  Assert-Equal $VerticalPackage.authority_contract.permitted_entry_source 'DF_E_YANLUO_HALL authoritative handoff proof only' 'authority vertical-slice permitted entry source'
  Assert-Null $VerticalPackage.authority_contract.runtime_key 'authority vertical-slice authority-contract runtime key'
  Assert-Condition ([string]$VerticalPackage.trusted_execution_boundary.node_path_policy -match 'NODE_PATH is rejected') 'authority vertical-slice rejects NODE_PATH'
  Assert-Condition ($VerticalPackage.trusted_execution_boundary.rejected_environment_prefixes -contains 'NODE_') 'authority vertical-slice rejects NODE_ environment injection'
  Assert-Condition ($VerticalPackage.trusted_execution_boundary.rejected_environment_prefixes -contains 'LUA_') 'authority vertical-slice rejects LUA_ environment injection'
  Assert-Null $VerticalPackage.trusted_execution_boundary.runtime_key 'authority vertical-slice trusted-boundary runtime key'
  Assert-ExactArray $VerticalPackage.runtime_model.session_states @('active', 'cleanup_pending', 'closed') 'authority vertical-slice session state lifecycle'
  Assert-ExactArray $VerticalPackage.runtime_model.idempotency_key @('actor_id', 'event_id') 'authority vertical-slice idempotency key'
  Assert-ExactArray $VerticalPackage.runtime_model.cleanup_identity @('session_instance_id', 'session_epoch', 'revision', 'cleanup_token') 'authority vertical-slice cleanup identity'
  Assert-Null $VerticalPackage.runtime_model.runtime_key 'authority vertical-slice runtime-model runtime key'
  foreach ($Property in $VerticalPackage.non_goals.PSObject.Properties) {
    Assert-Null $Property.Value "authority vertical-slice non-goal: $($Property.Name)"
  }

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
  Assert-Equal $Tower.run_model.status 'tianting_offline_candidate_pending_global_tower_adoption' 'tower run model remains candidate pending global adoption'
  Assert-Equal $Tower.run_model.artifact 'tower-economy/mansion-economy-global-tower-run-season-contract.json' 'tower run model candidate artifact'
  Assert-Equal $Tower.run_model.candidate_full_run_floor_count 40 'tower run model candidate floor count'
  Assert-Equal $Tower.run_model.candidate_cycle_count 8 'tower run model candidate cycle count'
  Assert-Equal $Tower.run_model.candidate_ten_floor_arc_count 4 'tower run model candidate ten-floor arc count'
  Assert-Equal $Tower.floor_plan.status 'tianting_offline_candidate_pending_global_tower_adoption' 'tower floor plan remains candidate pending global adoption'
  Assert-Null $Tower.floor_plan.effective_value 'tower floor plan has no effective global value'
  Assert-Equal $Tower.floor_plan.candidate_value 'five-floor_boss_slots_with_ten-floor_major_boss_replacement' 'tower candidate floor-plan shape'
  Assert-Equal $Tower.season_policy.status 'tianting_offline_candidate_pending_global_tower_adoption' 'tower season policy remains candidate pending global adoption'
  Assert-Null $Tower.season_policy.effective_value 'tower season policy has no effective value'
  Assert-Equal $Tower.season_policy.artifact 'tower-economy/mansion-economy-global-tower-run-season-contract.json' 'tower season candidate artifact'
  foreach ($PolicyName in @('affix_policy')) {
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

  $RequiredDesignTop = @('version', 'project', 'sourceMaterials', 'worldview', 'playerExperience', 'coreLoop', 'sessionFlow', 'systems', 'content', 'mvp', 'handoffs', 'risks', 'unresolved', 'acceptanceCriteria', 'crossChapterBoundary', 'towerFirstCycleContract', 'contentExpansionContract', 'authorityProgressionAndInstanceContract', 'combatReadabilityContract', 'terrainLayoutDryRun', 'mapScaleAlignmentContract', 'uiAccessibilityInformationContract', 'objectArtVfxBlueprintContract', 'objectFieldReservationContract', 'enemyEcologyContract', 'mainlineBossDeepeningContract', 'authorityRuntimeVerticalSlice', 'sevenStarSessionReference', 'mansionSessionReference', 'mansionEncounterOrchestrationContract', 'mainlineNarrativePresentationContract', 'towerEconomyFullRunContract', 'economyV2AuthorityReceiptInputHandoff')
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
  Assert-Condition ($Design.contentExpansionContract.towerReuseDoesNotBindExistingBeats -eq $false) 'design content expansion permits only non-mutating fifth-beat annotation'
  Assert-Equal $Design.contentExpansionContract.allowedOuterBeatAnnotation 'fifth_beat_content_slot_only' 'design content expansion outer annotation boundary'
  Assert-Equal $Design.authorityProgressionAndInstanceContract.artifact 'authority/tianting-progression-and-instance-authority-contract.json' 'design authority progression and instance artifact'
  Assert-Equal $Design.authorityProgressionAndInstanceContract.status 'offline_design' 'design authority progression and instance status'
  Assert-Null $Design.authorityProgressionAndInstanceContract.runtimeKey 'design authority progression and instance runtime key'
  Assert-Equal $Design.authorityProgressionAndInstanceContract.productionGate 'closed' 'design authority progression and instance production gate'

  Assert-Equal $Design.combatReadabilityContract.artifact 'combat/tianting-combat-readability-contract.json' 'design combat readability artifact'
  Assert-Equal $Design.combatReadabilityContract.status 'offline_design' 'design combat readability status'
  Assert-Null $Design.combatReadabilityContract.runtimeKey 'design combat readability runtime key'
  Assert-Equal $Design.combatReadabilityContract.productionGate 'closed' 'design combat readability production gate'
  Assert-Equal $Design.combatReadabilityContract.acceptanceRange 'TT-COMBAT-ACC-001..031' 'design combat readability acceptance range'
  Assert-Equal $Design.terrainLayoutDryRun.artifact 'terrain-layout/layout.json' 'design terrain dry-run artifact'
  Assert-Equal $Design.terrainLayoutDryRun.status 'offline_dry_run_candidate' 'design terrain dry-run status'
  Assert-Equal $Design.terrainLayoutDryRun.mode 'preview' 'design terrain dry-run mode'
  Assert-Null $Design.terrainLayoutDryRun.runtimeKey 'design terrain dry-run runtime key'
  Assert-Null $Design.terrainLayoutDryRun.actualMapKey 'design terrain dry-run actual map key'
  Assert-Equal $Design.terrainLayoutDryRun.writePolicy 'confirmation_required_before_any_Y3Maker_or_Y3_write' 'design terrain dry-run write policy'

  Assert-Equal $Design.mapScaleAlignmentContract.artifact 'terrain-layout/tianting-map-scale-alignment-contract.json' 'design map-scale alignment artifact'
  Assert-Equal $Design.mapScaleAlignmentContract.status 'offline_preconstruction_decision' 'design map-scale alignment status'
  Assert-Null $Design.mapScaleAlignmentContract.runtimeKey 'design map-scale alignment runtime key'
  Assert-Equal $Design.mapScaleAlignmentContract.productionGate 'closed' 'design map-scale alignment production gate'
  Assert-Condition ($Design.mapScaleAlignmentContract.diagramUnitOnly -eq $true) 'design map-scale alignment preserves diagram-only boundary'
  Assert-Null $Design.mapScaleAlignmentContract.actualMapKey 'design map-scale alignment actual map key'

  Assert-Equal $Design.uiAccessibilityInformationContract.artifact 'ui/tianting-ui-accessibility-information-contract.json' 'design UI architecture artifact'
  Assert-Equal $Design.uiAccessibilityInformationContract.status 'offline_design' 'design UI architecture status'
  Assert-Null $Design.uiAccessibilityInformationContract.runtimeKey 'design UI architecture runtime key'
  Assert-Equal $Design.uiAccessibilityInformationContract.productionGate 'closed' 'design UI architecture production gate'
  Assert-Equal $Design.uiAccessibilityInformationContract.acceptanceRange 'TT-UI-ACC-001..024' 'design UI architecture acceptance range'

  Assert-Equal $Design.objectArtVfxBlueprintContract.artifact 'object-blueprint/tianting-object-art-vfx-blueprint-contract.json' 'design object-art blueprint artifact'
  Assert-Equal $Design.objectArtVfxBlueprintContract.status 'offline_design_requirements_only' 'design object-art blueprint status'
  Assert-Null $Design.objectArtVfxBlueprintContract.runtimeKey 'design object-art blueprint runtime key'
  Assert-Equal $Design.objectArtVfxBlueprintContract.productionGate 'closed' 'design object-art blueprint production gate'
  Assert-Equal $Design.objectArtVfxBlueprintContract.acceptanceRange 'TT-BLUEPRINT-ACC-001..031' 'design object-art blueprint acceptance range'

  Assert-Equal $Design.objectFieldReservationContract.artifact 'object-preallocation/tianting-object-field-reservation-contract.json' 'design object field reservation artifact'
  Assert-Equal $Design.objectFieldReservationContract.status 'offline_field_reservation_only' 'design object field reservation status'
  Assert-Null $Design.objectFieldReservationContract.runtimeKey 'design object field reservation runtime key'
  Assert-Equal $Design.objectFieldReservationContract.productionGate 'closed' 'design object field reservation production gate'
  Assert-Condition ($Design.objectFieldReservationContract.pluginGeneration -eq $false) 'design object field reservation disables plugin generation'
  Assert-Null $Design.objectFieldReservationContract.normalizedDesignInput 'design object field reservation normalized design input'
  Assert-Null $Design.objectFieldReservationContract.stableObjectKey 'design object field reservation stable object key'
  Assert-Null $Design.objectFieldReservationContract.copyFrom 'design object field reservation copyFrom'
  Assert-Null $Design.objectFieldReservationContract.absoluteObjectFieldProjection 'design object field reservation absolute object projection'
  Assert-Equal $Design.objectFieldReservationContract.acceptanceRange 'TT-OBJRES-ACC-001..008' 'design object field reservation acceptance range'

  Assert-Equal $Design.enemyEcologyContract.artifact 'enemy-ecology/tianting-enemy-ecology-contract.json' 'design enemy-ecology artifact'
  Assert-Equal $Design.enemyEcologyContract.status 'offline_design_requirements_only' 'design enemy-ecology status'
  Assert-Null $Design.enemyEcologyContract.runtimeKey 'design enemy-ecology runtime key'
  Assert-Equal $Design.enemyEcologyContract.productionGate 'closed' 'design enemy-ecology production gate'
  Assert-Equal $Design.enemyEcologyContract.acceptanceRange 'TT-ENEMY-ACC-001..030' 'design enemy-ecology acceptance range'
  Assert-Null $Design.enemyEcologyContract.unitObjectWaveAndEconomyBinding 'design enemy-ecology runtime binding'
  Assert-Equal $Design.mainlineBossDeepeningContract.artifact 'mainline-boss/tianting-mainline-boss-contract.json' 'design mainline-Boss artifact'
  Assert-Equal $Design.mainlineBossDeepeningContract.status 'offline_design_requirements_only' 'design mainline-Boss status'
  Assert-Null $Design.mainlineBossDeepeningContract.runtimeKey 'design mainline-Boss runtime key'
  Assert-Equal $Design.mainlineBossDeepeningContract.productionGate 'closed' 'design mainline-Boss production gate'
  Assert-Equal $Design.mainlineBossDeepeningContract.acceptanceRange 'TT-MAINLINE-BOSS-ACC-001..030' 'design mainline-Boss acceptance range'
  Assert-Null $Design.mainlineBossDeepeningContract.bossObjectSkillAiAndEconomyBinding 'design mainline-Boss runtime binding'

  Assert-Equal $Design.authorityRuntimeVerticalSlice.artifact '../../../implementation/tianting-authority-vertical-slice/package-contract.json' 'design authority vertical-slice artifact'
  Assert-Equal $Design.authorityRuntimeVerticalSlice.status 'offline_tested_reference_only' 'design authority vertical-slice status'
  Assert-Null $Design.authorityRuntimeVerticalSlice.runtimeKey 'design authority vertical-slice runtime key'
  Assert-Equal $Design.authorityRuntimeVerticalSlice.productionGate 'closed' 'design authority vertical-slice production gate'
  Assert-Condition ($Design.authorityRuntimeVerticalSlice.y3Integration -eq $false) 'design authority vertical-slice has no Y3 integration'

  Assert-Equal $Design.sevenStarSessionReference.artifact '../../../implementation/tianting-seven-star-session-reference/package-contract.json' 'design seven-star reference artifact'
  Assert-Equal $Design.sevenStarSessionReference.status 'offline_reference_model_only' 'design seven-star reference status'
  Assert-Null $Design.sevenStarSessionReference.runtimeKey 'design seven-star reference runtime key'
  Assert-Equal $Design.sevenStarSessionReference.productionGate 'closed' 'design seven-star reference production gate'
  Assert-Condition ($Design.sevenStarSessionReference.y3Integration -eq $false) 'design seven-star reference has no Y3 integration'
  Assert-Null $Design.sevenStarSessionReference.economyOutputs 'design seven-star reference has no economy outputs'
  Assert-Equal $Design.sevenStarSessionReference.acceptanceRange 'TT-ACC-043' 'design seven-star reference acceptance range'

  Assert-Equal $Design.mansionSessionReference.artifact '../../../implementation/tianting-mansion-session-reference/package-contract.json' 'design mansion reference artifact'
  Assert-Equal $Design.mansionSessionReference.status 'offline_reference_only' 'design mansion reference status'
  Assert-Null $Design.mansionSessionReference.runtimeKey 'design mansion reference runtime key'
  Assert-Equal $Design.mansionSessionReference.productionGate 'closed' 'design mansion reference production gate'
  Assert-Condition ($Design.mansionSessionReference.y3Integration -eq $false) 'design mansion reference has no Y3 integration'
  Assert-Null $Design.mansionSessionReference.economyOutputs 'design mansion reference has no economy outputs'
  Assert-Equal $Design.mansionSessionReference.acceptanceRange 'TT-ACC-044' 'design mansion reference acceptance range'

  Assert-Equal $Design.mansionEncounterOrchestrationContract.artifact 'mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json' 'design mansion encounter choreography artifact'
  Assert-Equal $Design.mansionEncounterOrchestrationContract.status 'offline_encounter_choreography_spec' 'design mansion encounter choreography status'
  Assert-Null $Design.mansionEncounterOrchestrationContract.runtimeKey 'design mansion encounter choreography runtime key'
  Assert-Equal $Design.mansionEncounterOrchestrationContract.productionGate 'closed' 'design mansion encounter choreography production gate'
  Assert-Condition ($Design.mansionEncounterOrchestrationContract.y3Integration -eq $false) 'design mansion encounter choreography has no Y3 integration'
  Assert-Null $Design.mansionEncounterOrchestrationContract.encounterStateMachine 'design mansion encounter choreography state machine'
  Assert-Null $Design.mansionEncounterOrchestrationContract.completionWrite 'design mansion encounter choreography completion write'
  Assert-Null $Design.mansionEncounterOrchestrationContract.economyOutputs 'design mansion encounter choreography economy outputs'
  Assert-Equal $Design.mansionEncounterOrchestrationContract.acceptanceRange 'TT-MANSION-CHOREO-ACC-001..009' 'design mansion encounter choreography acceptance range'

  Assert-Equal $Design.mainlineNarrativePresentationContract.artifact 'mainline-presentation/tianting-mainline-presentation-contract.json' 'design mainline-presentation artifact'
  Assert-Equal $Design.mainlineNarrativePresentationContract.status 'offline_narrative_presentation_spec' 'design mainline-presentation status'
  Assert-Null $Design.mainlineNarrativePresentationContract.runtimeKey 'design mainline-presentation runtime key'
  Assert-Equal $Design.mainlineNarrativePresentationContract.productionGate 'closed' 'design mainline-presentation production gate'
  Assert-Condition ($Design.mainlineNarrativePresentationContract.y3Integration -eq $false) 'design mainline-presentation has no Y3 integration'
  Assert-Null $Design.mainlineNarrativePresentationContract.economyOutputs 'design mainline-presentation has no economy outputs'
  Assert-Equal $Design.mainlineNarrativePresentationContract.acceptanceRange 'TT-PRESENTATION-ACC-001..006' 'design mainline-presentation acceptance range'

  Assert-Equal $Design.towerEconomyFullRunContract.artifact 'tower-economy/mansion-economy-global-tower-run-season-contract.json' 'design tower-economy candidate artifact'
  Assert-Equal $Design.towerEconomyFullRunContract.status 'tianting_offline_candidate_pending_global_tower_adoption' 'design tower-economy remains candidate pending global adoption'
  Assert-Null $Design.towerEconomyFullRunContract.runtimeKey 'design tower-economy runtime key'
  Assert-Equal $Design.towerEconomyFullRunContract.productionGate 'closed' 'design tower-economy production gate'
  Assert-Equal $Design.towerEconomyFullRunContract.upstreamGlobalTowerAdoption 'pending' 'design tower-economy upstream adoption gate'
  Assert-Equal $Design.towerEconomyFullRunContract.candidateFullRunFloorCount 40 'design tower-economy candidate floor count'
  Assert-Equal $Design.towerEconomyFullRunContract.candidateCycleCount 8 'design tower-economy candidate cycle count'
  Assert-Equal $Design.towerEconomyFullRunContract.candidateMajorBossEveryFloors 10 'design tower-economy candidate major-Boss cadence'
  Assert-Equal $Design.towerEconomyFullRunContract.economicValues 'null_or_deferred' 'design tower-economy economic values remain deferred'
  Assert-Null $Design.towerEconomyFullRunContract.runtimeRun 'design tower-economy runtime run'

  Assert-Equal $Design.economyV2AuthorityReceiptInputHandoff.artifact '../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json' 'design economy-v2 authority receipt input handoff artifact'
  Assert-Equal $Design.economyV2AuthorityReceiptInputHandoff.status 'offline_design_handoff' 'design economy-v2 authority receipt input handoff status'
  Assert-Null $Design.economyV2AuthorityReceiptInputHandoff.runtimeKey 'design economy-v2 authority receipt input handoff runtime key'
  Assert-Equal $Design.economyV2AuthorityReceiptInputHandoff.productionGate 'closed' 'design economy-v2 authority receipt input handoff production gate'
  Assert-Null $Design.economyV2AuthorityReceiptInputHandoff.settlementRequest 'design economy-v2 authority receipt input handoff settlement request'
  Assert-Equal $Design.economyV2AuthorityReceiptInputHandoff.economicValues 'null_or_deferred' 'design economy-v2 authority receipt input handoff economic values'
  Assert-Equal $Design.economyV2AuthorityReceiptInputHandoff.sourceEvidenceEnvelopeSpecId 'TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE' 'design economy-v2 authority receipt input handoff source evidence spec id'
  Assert-Condition ($Design.economyV2AuthorityReceiptInputHandoff.directCallerInput -eq $false) 'design economy-v2 authority receipt input handoff rejects direct caller input'

  foreach ($CollectionName in @('sourceMaterials', 'sessionFlow', 'systems', 'risks', 'unresolved', 'acceptanceCriteria')) {
    $Collection = $Design.PSObject.Properties[$CollectionName].Value
    Assert-Array $Collection "design collection: $CollectionName"
    Assert-Condition ($Collection.Count -gt 0) "design collection is non-empty: $CollectionName"
  }
  Assert-Condition (@($Design.sourceMaterials | Where-Object { $_.path -eq 'docs/物编/天庭篇主线遭遇与通天塔规格包/enemy-ecology/tianting-enemy-ecology-contract.json' }).Count -eq 1) 'design source material includes enemy ecology contract'
  Assert-Condition (@($Design.sourceMaterials | Where-Object { $_.path -eq 'docs/物编/天庭篇主线遭遇与通天塔规格包/mainline-boss/tianting-mainline-boss-contract.json' }).Count -eq 1) 'design source material includes mainline Boss contract'
  Assert-Condition (@($Design.sourceMaterials | Where-Object { $_.path -eq 'docs/物编/天庭篇主线遭遇与通天塔规格包/combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' }).Count -eq 1) 'design source material includes combat numeric contract'
  Assert-Condition (@($Design.sourceMaterials | Where-Object { $_.path -eq 'implementation/tianting-seven-star-session-reference/package-contract.json' }).Count -eq 1) 'design source material includes seven-star reference'
  Assert-Condition (@($Design.sourceMaterials | Where-Object { $_.path -eq 'implementation/tianting-mansion-session-reference/contract/mansion-session-time-qualification-reference-contract.json' }).Count -eq 1) 'design source material includes mansion reference'
  Assert-Condition (@($Design.sourceMaterials | Where-Object { $_.path -eq 'docs/物编/天庭篇主线遭遇与通天塔规格包/mainline-presentation/tianting-mainline-presentation-contract.json' }).Count -eq 1) 'design source material includes mainline presentation contract'
  Assert-Condition (@($Design.sourceMaterials | Where-Object { $_.path -eq 'docs/物编/天庭篇主线遭遇与通天塔规格包/mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json' }).Count -eq 1) 'design source material includes mansion encounter choreography contract'
  Assert-Condition (@($Design.sourceMaterials | Where-Object { $_.path -eq 'docs/物编/天庭篇主线遭遇与通天塔规格包/object-preallocation/tianting-object-field-reservation-contract.json' }).Count -eq 1) 'design source material includes object field reservation contract'
  Assert-Condition (@($Design.systems | Where-Object { $_.name -eq '天庭敌人生态与精英职责' -and $_.owner -eq 'enemy-ecology/tianting-enemy-ecology-contract.json' }).Count -eq 1) 'design system includes enemy ecology'
  Assert-Condition (@($Design.systems | Where-Object { $_.name -eq '天庭主线 Boss 深化' -and $_.owner -eq 'mainline-boss/tianting-mainline-boss-contract.json' }).Count -eq 1) 'design system includes mainline Boss deepening'
  Assert-Condition (@($Design.systems | Where-Object { $_.name -eq '天庭战斗数值与单位基线' -and $_.owner -eq 'combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' }).Count -eq 1) 'design system includes combat numeric baseline'
  Assert-Condition (@($Design.systems | Where-Object { $_.name -eq '天庭物编字段预占' -and $_.owner -eq 'object-preallocation/tianting-object-field-reservation-contract.json' }).Count -eq 1) 'design system includes object field reservation'
  Assert-Condition (@($Design.systems | Where-Object { $_.name -eq '二十八星官与四圣机制编排' -and $_.owner -eq 'mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json' }).Count -eq 1) 'design system includes mansion encounter choreography'
  Assert-Condition ((@($Design.acceptanceCriteria) -join "`n") -match '二十八星官与四圣机制编排') 'design acceptance includes mansion encounter choreography'
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
  Assert-Condition ((@($Design.handoffs.luaLogic) -join "`n") -match '七星/星宿会话离线参考包') 'design Lua handoff names the session references as test-only inputs'
  Assert-Condition ((@($Design.handoffs.objectConfig) -join "`n") -match 'object-preallocation') 'design object handoff names field reservation package'
  Assert-Condition ((@($Design.handoffs.uiPipeline) -join "`n") -match 'mainline-presentation') 'design UI handoff names mainline presentation'
  Assert-Condition ((@($Design.handoffs.reviewPanel) -join "`n") -match '七星/星宿会话离线回归') 'design review handoff names session-reference review'
  foreach ($HandoffName in @('objectConfig', 'terrainLayout', 'luaLogic', 'uiPipeline', 'reviewPanel')) {
    Assert-Condition ((@($Design.handoffs.PSObject.Properties[$HandoffName].Value) -join "`n") -match 'mansion-orchestration') "design handoff names mansion encounter choreography: $HandoffName"
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
  Assert-Condition (@($Design.content.monsters | Where-Object { $_.specId -eq 'TT_SPEC_TIANTING_ENEMY_ECOLOGY' -and $_.status -eq 'offline_design_requirements_only' }).Count -eq 1) 'design content includes enemy ecology identity'
  Assert-Condition (@($Design.content.bosses | Where-Object { $_.specId -eq 'TT_SPEC_TIANTING_MAINLINE_BOSS_DEEPENING' -and $_.status -eq 'offline_design_requirements_only' }).Count -eq 1) 'design content includes mainline Boss deepening identity'
  Assert-Condition (@($Design.content.monsters | Where-Object { $_.specId -eq 'TT_SPEC_TIANTING_COMBAT_NUMERIC_UNIT_BASELINE' -and $_.status -eq 'accepted_relative_balance_baseline_offline_only' }).Count -eq 1) 'design monster content includes combat numeric identity'
  Assert-Condition (@($Design.content.bosses | Where-Object { $_.specId -eq 'TT_SPEC_TIANTING_COMBAT_NUMERIC_UNIT_BASELINE' -and $_.status -eq 'accepted_relative_balance_baseline_offline_only' }).Count -eq 1) 'design Boss content includes combat numeric identity'

  Assert-Equal $Design.combatNumericUnitBaselineContract.artifact 'combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' 'design combat-numeric artifact'
  Assert-Equal $Design.combatNumericUnitBaselineContract.status 'accepted_relative_balance_baseline_offline_only' 'design combat-numeric status'
  Assert-Null $Design.combatNumericUnitBaselineContract.runtimeKey 'design combat-numeric runtime key'
  Assert-Equal $Design.combatNumericUnitBaselineContract.productionGate 'closed' 'design combat-numeric production gate'
  Assert-Equal $Design.combatNumericUnitBaselineContract.acceptanceRange 'TT-NUM-ACC-001..027' 'design combat-numeric acceptance range'
  Assert-Null $Design.combatNumericUnitBaselineContract.absoluteObjectFieldProjection 'design combat-numeric absolute object projection'

  Assert-Equal $ObjectBrief.targetSkill 'y3-object-config' 'object handoff target skill'
  Assert-Equal $ObjectBrief.combatReadabilitySource.artifact '../combat/tianting-combat-readability-contract.json' 'object handoff combat readability source'
  Assert-Equal $ObjectBrief.combatReadabilitySource.status 'offline_design' 'object handoff combat readability status'
  Assert-Null $ObjectBrief.combatReadabilitySource.runtimeKey 'object handoff combat readability runtime key'
  Assert-Equal $ObjectBrief.combatNumericUnitBaselineSource.artifact '../combat-baseline/tianting-combat-numeric-unit-baseline-contract.json' 'object handoff combat-numeric source'
  Assert-Equal $ObjectBrief.combatNumericUnitBaselineSource.status 'accepted_relative_balance_baseline_offline_only' 'object handoff combat-numeric status'
  Assert-Null $ObjectBrief.combatNumericUnitBaselineSource.runtimeKey 'object handoff combat-numeric runtime key'
  Assert-Null $ObjectBrief.combatNumericUnitBaselineSource.objectId 'object handoff combat-numeric object id'
  Assert-Null $ObjectBrief.combatNumericUnitBaselineSource.unitId 'object handoff combat-numeric unit id'
  Assert-Null $ObjectBrief.combatNumericUnitBaselineSource.absoluteObjectFieldProjection 'object handoff combat-numeric absolute projection'
  Assert-Equal $ObjectBrief.combatNumericUnitBaselineSource.pluginGeneration 'blocked_until_stable_object_keys_and_calibration_gate_pass' 'object handoff combat-numeric plugin gate'
  Assert-Equal $ObjectBrief.absoluteCombatCalibrationSource.artifact '../../../../implementation/combat-calibration/contract/cross-profession-combat-calibration-contract.json' 'object handoff P0 calibration artifact'
  Assert-Equal $ObjectBrief.absoluteCombatCalibrationSource.status 'offline-calibration-reference-only' 'object handoff P0 calibration status'
  Assert-Equal $ObjectBrief.absoluteCombatCalibrationSource.candidateId 'TT_CAL_ABSOLUTE_OBJECT_FIELDS_V1' 'object handoff P0 calibration candidate id'
  Assert-Null $ObjectBrief.absoluteCombatCalibrationSource.runtimeKey 'object handoff P0 calibration runtime key'
  Assert-Null $ObjectBrief.absoluteCombatCalibrationSource.targetObjectOrUnitId 'object handoff P0 calibration target object id'
  Assert-Null $ObjectBrief.absoluteCombatCalibrationSource.absoluteObjectFields 'object handoff P0 calibration object fields'
  Assert-Equal $ObjectBrief.absoluteCombatCalibrationSource.productionGate 'closed' 'object handoff P0 calibration production gate'
  Assert-Equal $ObjectBrief.absoluteCombatCalibrationSource.evidenceAdoptionArtifact '../../../../implementation/combat-calibration/evidence-adoption/p0-evidence-collection-and-adoption-contract.json' 'object handoff P0 evidence-adoption artifact'
  Assert-Equal $ObjectBrief.absoluteCombatCalibrationSource.evidenceAdoptionStatus 'offline-evidence-collection-plan-only' 'object handoff P0 evidence-adoption status'
  Assert-ExactArray $ObjectBrief.absoluteCombatCalibrationSource.evidenceAdoptionGateSnapshot.requiredGateIds $ExpectedP0GateIds 'object handoff P0 evidence-adoption gate sequence'
  Assert-ExactArray $ObjectBrief.absoluteCombatCalibrationSource.evidenceAdoptionGateSnapshot.currentSatisfiedGateIds @() 'object handoff P0 evidence-adoption satisfied gates'
  foreach ($FieldName in @('actualCaptureProvider', 'acceptedEvidenceLedger', 'adoptionDecision', 'absoluteProjectionPayload')) {
    Assert-Null $ObjectBrief.absoluteCombatCalibrationSource.evidenceAdoptionGateSnapshot.PSObject.Properties[$FieldName].Value "object handoff P0 evidence-adoption deferred field: $FieldName"
  }
  Assert-Equal $ObjectBrief.objectFieldReservationSource.artifact '../object-preallocation/tianting-object-field-reservation-contract.json' 'object handoff field reservation artifact'
  Assert-Equal $ObjectBrief.objectFieldReservationSource.status 'offline_field_reservation_only' 'object handoff field reservation status'
  Assert-Null $ObjectBrief.objectFieldReservationSource.runtimeKey 'object handoff field reservation runtime key'
  Assert-Null $ObjectBrief.objectFieldReservationSource.objectKey 'object handoff field reservation object key'
  Assert-Null $ObjectBrief.objectFieldReservationSource.copyFrom 'object handoff field reservation copyFrom'
  Assert-Null $ObjectBrief.objectFieldReservationSource.normalizedDesignInput 'object handoff field reservation normalized design input'
  Assert-Condition ($ObjectBrief.objectFieldReservationSource.pluginGeneration -eq $false) 'object handoff field reservation disables plugin generation'
  Assert-Null $ObjectBrief.objectFieldReservationSource.absoluteObjectFields 'object handoff field reservation absolute object fields'
  Assert-Equal $ObjectBrief.objectFieldReservationSource.productionGate 'closed' 'object handoff field reservation production gate'
  Assert-Equal $ObjectBrief.mansionEncounterOrchestrationSource.artifact '../mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json' 'object handoff mansion encounter choreography artifact'
  Assert-Equal $ObjectBrief.mansionEncounterOrchestrationSource.status 'offline_encounter_choreography_spec' 'object handoff mansion encounter choreography status'
  Assert-Null $ObjectBrief.mansionEncounterOrchestrationSource.runtimeKey 'object handoff mansion encounter choreography runtime key'
  Assert-Null $ObjectBrief.mansionEncounterOrchestrationSource.objectId 'object handoff mansion encounter choreography object id'
  Assert-Null $ObjectBrief.mansionEncounterOrchestrationSource.abilityIds 'object handoff mansion encounter choreography ability ids'
  Assert-Null $ObjectBrief.mansionEncounterOrchestrationSource.stateMachine 'object handoff mansion encounter choreography state machine'
  Assert-Null $ObjectBrief.mansionEncounterOrchestrationSource.numericValues 'object handoff mansion encounter choreography numeric values'
  Assert-Equal $ObjectBrief.enemyEcologySource.artifact '../enemy-ecology/tianting-enemy-ecology-contract.json' 'object handoff enemy-ecology source'
  Assert-Equal $ObjectBrief.enemyEcologySource.status 'offline_design_requirements_only' 'object handoff enemy-ecology status'
  Assert-Null $ObjectBrief.enemyEcologySource.runtimeKey 'object handoff enemy-ecology runtime key'
  Assert-Null $ObjectBrief.enemyEcologySource.objectId 'object handoff enemy-ecology object id'
  Assert-Null $ObjectBrief.enemyEcologySource.unitId 'object handoff enemy-ecology unit id'
  Assert-Null $ObjectBrief.enemyEcologySource.numericValues 'object handoff enemy-ecology numeric values'
  Assert-Equal $ObjectBrief.mainlineBossDeepeningSource.artifact '../mainline-boss/tianting-mainline-boss-contract.json' 'object handoff mainline-Boss source'
  Assert-Equal $ObjectBrief.mainlineBossDeepeningSource.status 'offline_design_requirements_only' 'object handoff mainline-Boss status'
  Assert-Null $ObjectBrief.mainlineBossDeepeningSource.runtimeKey 'object handoff mainline-Boss runtime key'
  Assert-Null $ObjectBrief.mainlineBossDeepeningSource.objectId 'object handoff mainline-Boss object id'
  Assert-Null $ObjectBrief.mainlineBossDeepeningSource.abilityIds 'object handoff mainline-Boss ability ids'
  Assert-Null $ObjectBrief.mainlineBossDeepeningSource.resourceId 'object handoff mainline-Boss resource id'
  Assert-Condition (Test-HasProperty $ObjectBrief 'assetRequests') 'object handoff asset requests'
  foreach ($AssetName in @('heroes', 'abilities', 'monsters', 'bosses', 'items', 'economy', 'progression')) {
    $Asset = $ObjectBrief.assetRequests.PSObject.Properties[$AssetName].Value
    Assert-Condition ($null -ne $Asset) "object handoff asset request: $AssetName"
    Assert-Condition ([string]$Asset.specId -match '^TT_SPEC_') "object handoff spec id: $AssetName/$($Asset.specId)"
    Assert-Null $Asset.runtimeKey "object handoff runtime key: $AssetName/$($Asset.specId)"
  }
  Assert-Equal $TerrainBrief.targetSkill 'y3-terrain-layout' 'terrain handoff target skill'
  Assert-Equal $TerrainBrief.version 3 'terrain handoff version'
  Assert-Equal $TerrainBrief.candidateLayout.artifact '../terrain-layout/layout.json' 'terrain handoff candidate layout artifact'
  Assert-Equal $TerrainBrief.candidateLayout.status 'offline-dry-run-candidate' 'terrain handoff candidate layout status'
  Assert-Equal $TerrainBrief.candidateLayout.mode 'preview' 'terrain handoff candidate layout mode'
  Assert-Null $TerrainBrief.candidateLayout.runtimeKey 'terrain handoff candidate layout runtime key'
  Assert-Equal $TerrainBrief.enemyEcologySource.artifact '../enemy-ecology/tianting-enemy-ecology-contract.json' 'terrain handoff enemy-ecology source'
  Assert-Equal $TerrainBrief.enemyEcologySource.status 'offline_design_requirements_only' 'terrain handoff enemy-ecology status'
  Assert-Null $TerrainBrief.enemyEcologySource.runtimeKey 'terrain handoff enemy-ecology runtime key'
  Assert-Equal $TerrainBrief.mainlineBossDeepeningSource.artifact '../mainline-boss/tianting-mainline-boss-contract.json' 'terrain handoff mainline-Boss source'
  Assert-Equal $TerrainBrief.mainlineBossDeepeningSource.status 'offline_design_requirements_only' 'terrain handoff mainline-Boss status'
  Assert-Null $TerrainBrief.mainlineBossDeepeningSource.runtimeKey 'terrain handoff mainline-Boss runtime key'
  Assert-Equal $TerrainBrief.mansionEncounterOrchestrationSource.artifact '../mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json' 'terrain handoff mansion encounter choreography artifact'
  Assert-Equal $TerrainBrief.mansionEncounterOrchestrationSource.status 'offline_encounter_choreography_spec' 'terrain handoff mansion encounter choreography status'
  Assert-Null $TerrainBrief.mansionEncounterOrchestrationSource.runtimeKey 'terrain handoff mansion encounter choreography runtime key'
  Assert-Null $TerrainBrief.mansionEncounterOrchestrationSource.actualMapKey 'terrain handoff mansion encounter choreography map key'
  Assert-Null $TerrainBrief.mansionEncounterOrchestrationSource.coordinates 'terrain handoff mansion encounter choreography coordinates'
  Assert-Null $TerrainBrief.mansionEncounterOrchestrationSource.collision 'terrain handoff mansion encounter choreography collision'
  Assert-Equal $TerrainBrief.y3ConstructionPreflightSource.artifact '../../../../implementation/tianting-y3-construction-preflight/package-contract.json' 'terrain handoff construction-preflight artifact'
  Assert-Equal $TerrainBrief.y3ConstructionPreflightSource.status 'structural-preflight-only' 'terrain handoff construction-preflight status'
  Assert-Null $TerrainBrief.y3ConstructionPreflightSource.runtimeKey 'terrain handoff construction-preflight runtime key'
  Assert-Null $TerrainBrief.y3ConstructionPreflightSource.actualMapRoot 'terrain handoff construction-preflight map root'
  Assert-Equal $TerrainBrief.y3ConstructionPreflightSource.productionGate 'closed' 'terrain handoff construction-preflight production gate'
  Assert-Equal $TerrainBrief.surfaceConstructionDiscoverySource.artifact '../../../../implementation/tianting-surface-construction-manifest/surface-construction-manifest.json' 'terrain handoff surface-discovery artifact'
  Assert-Equal $TerrainBrief.surfaceConstructionDiscoverySource.status 'offline_preconstruction_discovery_only' 'terrain handoff surface-discovery status'
  Assert-Null $TerrainBrief.surfaceConstructionDiscoverySource.runtimeKey 'terrain handoff surface-discovery runtime key'
  Assert-Null $TerrainBrief.surfaceConstructionDiscoverySource.actualMapKey 'terrain handoff surface-discovery map key'
  Assert-Condition ($TerrainBrief.surfaceConstructionDiscoverySource.writeAuthorized -eq $false) 'terrain handoff surface-discovery does not authorize writes'
  foreach ($RegionName in @('maps', 'waves', 'monsters', 'bosses')) {
    $Region = $TerrainBrief.PSObject.Properties[$RegionName].Value
    Assert-Condition ($null -ne $Region) "terrain handoff logical region: $RegionName"
    Assert-Condition ([string]$Region.specId -match '^TT_SPEC_') "terrain handoff spec id: $RegionName/$($Region.specId)"
    Assert-Null $Region.runtimeKey "terrain handoff runtime key: $RegionName/$($Region.specId)"
  }

  $MasterReadmeText = Get-Content -LiteralPath (Join-Path $PackageRoot 'README.md') -Raw -Encoding UTF8
  $ConstructionLedgerText = Get-Content -LiteralPath (Join-Path $PackageRoot 'construction-readiness-ledger.md') -Raw -Encoding UTF8
  $AcceptanceMatrixText = Get-Content -LiteralPath (Join-Path $PackageRoot 'acceptance-matrix.md') -Raw -Encoding UTF8
  $DecisionRegisterText = Get-Content -LiteralPath (Join-Path $PackageRoot 'decision-register.md') -Raw -Encoding UTF8
  $ValidationReportText = Get-Content -LiteralPath (Join-Path $PackageRoot 'validation-report.md') -Raw -Encoding UTF8
  Assert-Condition ($MasterReadmeText -match 'implementation/combat-calibration') 'master README links P0 calibration package'
  Assert-Condition ($MasterReadmeText -match 'implementation/combat-calibration/evidence-adoption') 'master README links P0 evidence-adoption package'
  Assert-Condition ($MasterReadmeText -match 'implementation/combat-calibration/external-capture-onboarding') 'master README links P0 external-capture-onboarding package'
  Assert-Condition ($MasterReadmeText -match 'implementation/tianting-y3-construction-preflight') 'master README links construction-preflight package'
  Assert-Condition ($MasterReadmeText -match 'implementation/tianting-surface-construction-manifest') 'master README links surface discovery manifest'
  Assert-Condition ($MasterReadmeText -match 'implementation/tianting-seven-star-session-reference') 'master README links seven-star reference package'
  Assert-Condition ($MasterReadmeText -match 'implementation/tianting-mansion-session-reference') 'master README links mansion reference package'
  Assert-Condition ($MasterReadmeText -match 'mainline-presentation') 'master README links mainline presentation package'
  Assert-Condition ($MasterReadmeText -match 'mansion-orchestration') 'master README links mansion encounter choreography package'
  Assert-Condition ($MasterReadmeText -match 'object-preallocation') 'master README links object field reservation package'
  Assert-Condition ($MasterReadmeText -match 'construction-readiness-ledger.md') 'master README links construction-readiness ledger'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-039') 'acceptance matrix includes P0 calibration row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-047') 'acceptance matrix includes P0 evidence-adoption row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-048') 'acceptance matrix includes P0 external-capture-onboarding row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-040') 'acceptance matrix includes construction-preflight row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-041') 'acceptance matrix includes surface discovery row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-042') 'acceptance matrix includes seven-star solo-title consistency row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-043') 'acceptance matrix includes seven-star reference row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-044') 'acceptance matrix includes mansion reference row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-045') 'acceptance matrix includes mainline presentation row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-046') 'acceptance matrix includes object field reservation row'
  Assert-Condition ($AcceptanceMatrixText -match 'TT-ACC-049') 'acceptance matrix includes mansion encounter choreography row'
  Assert-Condition ($DecisionRegisterText -match 'TT-DESIGN-022') 'decision register includes P0 calibration decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-DESIGN-027') 'decision register includes P0 evidence-adoption decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-DESIGN-028') 'decision register includes P0 external-capture-onboarding decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-AUTH-009') 'decision register includes construction-preflight decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-DESIGN-024') 'decision register includes seven-star solo-title consistency decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-DESIGN-025') 'decision register includes mainline-presentation decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-DESIGN-026') 'decision register includes object field reservation decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-AUTH-010') 'decision register includes seven-star reference decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-AUTH-011') 'decision register includes mansion reference decision'
  Assert-Condition ($DecisionRegisterText -match 'TT-DESIGN-029') 'decision register includes mansion encounter choreography decision'
  Assert-Condition ($ConstructionLedgerText -match 'tianting-seven-star-session-reference') 'construction ledger includes seven-star reference fixture'
  Assert-Condition ($ConstructionLedgerText -match 'implementation/combat-calibration/evidence-adoption') 'construction ledger includes P0 evidence-adoption fixture'
  Assert-Condition ($ConstructionLedgerText -match 'implementation/combat-calibration/external-capture-onboarding') 'construction ledger includes P0 external-capture-onboarding fixture'
  Assert-Condition ($ConstructionLedgerText -match 'tianting-mansion-session-reference') 'construction ledger includes mansion reference fixture'
  Assert-Condition ($ConstructionLedgerText -match 'mainline-presentation') 'construction ledger includes mainline presentation fixture'
  Assert-Condition ($ConstructionLedgerText -match 'mansion-orchestration') 'construction ledger includes mansion encounter choreography package'
  Assert-Condition ($ConstructionLedgerText -match 'object-preallocation') 'construction ledger includes object field reservation fixture'
  Assert-Condition ($ValidationReportText -match 'P0 跨职业绝对标定协议') 'validation report includes P0 calibration evidence'
  Assert-Condition ($ValidationReportText -match 'P0 实证采集与采纳') 'validation report includes P0 evidence-adoption evidence'
  Assert-Condition ($ValidationReportText -match 'P0 外部实机采集方接入前置') 'validation report includes P0 external-capture-onboarding evidence'
  Assert-Condition ($ValidationReportText -match 'P1 Y3 施工预检') 'validation report includes construction-preflight evidence'
  Assert-Condition ($ValidationReportText -match '七星单人会话参考（P2）') 'validation report includes seven-star reference evidence'
  Assert-Condition ($ValidationReportText -match '星宿会话、时辰与资格参考（P3）') 'validation report includes mansion reference evidence'
  Assert-Condition ($ValidationReportText -match '二十八星官与四圣机制编排') 'validation report includes mansion encounter choreography evidence'
  Assert-Condition ($ValidationReportText -match '五组主线叙事与表现深化') 'validation report includes mainline presentation evidence'
  Assert-Condition ($ValidationReportText -match '天庭物编字段预占') 'validation report includes object field reservation evidence'
  Assert-Condition ($ValidationReportText -notmatch 'final-count-pending') 'validation report records a fresh final package-check count'

  $PackageText = (Get-ChildItem -LiteralPath $PackageRoot -File -Recurse |
    Where-Object { $_.Name -ne 'validate-tianting-tower-spec.ps1' } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
  Assert-Condition ($PackageText -notmatch 'DF_PROGRESS_YANLUO_HALL_CLEARED\s*(可)?作为[^\r\n]{0,60}(默认前置|默认解锁|default prerequisite|default unlock)') 'package does not describe protected Difu key as a default unlock'
  Assert-Condition ($PackageText -notmatch '七星成功、普通方位成功、噩梦方位成功可成为候选输入') 'package does not route seven-star or mansion success into current economy handoff'
  Assert-Condition ($PackageText -match '当前仅凌霄主线成功可进入既有零价值来源事实候选') 'package preserves Lingxiao-only current economy handoff route'
  Assert-Condition ($PackageText -match 'TT-NUM-ACC-001\.\.027') 'package publishes combat-numeric acceptance range'
  Assert-Condition ($PackageText -match '\| TT-ACC-038 \|') 'package acceptance matrix publishes combat-numeric row'
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
