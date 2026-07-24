[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ImplementationRoot = Split-Path -Parent $PSCommandPath
$WorkspaceRoot = Split-Path -Parent $ImplementationRoot
$MainlinePresentationContracts = @(
  Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'docs') -Recurse -File -Filter 'tianting-mainline-presentation-contract.json'
)
if ($MainlinePresentationContracts.Count -ne 1) {
  throw "Expected exactly one mainline-presentation contract below docs, found $($MainlinePresentationContracts.Count)."
}
$MainlinePresentationTest = Join-Path (Split-Path -Parent $MainlinePresentationContracts[0].FullName) 'tests\run-all.ps1'
$MansionEncounterOrchestrationContracts = @(
  Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'docs') -Recurse -File -Filter 'tianting-mansion-encounter-orchestration-contract.json'
)
if ($MansionEncounterOrchestrationContracts.Count -ne 1) {
  throw "Expected exactly one mansion encounter choreography contract below docs, found $($MansionEncounterOrchestrationContracts.Count)."
}
$MansionEncounterOrchestrationTest = Join-Path (Split-Path -Parent $MansionEncounterOrchestrationContracts[0].FullName) 'tests\run-all.ps1'
$ObjectFieldReservationContracts = @(
  Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'docs') -Recurse -File -Filter 'tianting-object-field-reservation-contract.json'
)
if ($ObjectFieldReservationContracts.Count -ne 1) {
  throw "Expected exactly one object field reservation contract below docs, found $($ObjectFieldReservationContracts.Count)."
}
$ObjectFieldReservationTest = Join-Path (Split-Path -Parent $ObjectFieldReservationContracts[0].FullName) 'tests\run-all.ps1'
$VerificationStages = @(
  [pscustomobject]@{
    Name = 'P0 cross-profession combat calibration protocol'
    Script = Join-Path $ImplementationRoot 'combat-calibration\tests\run-all.ps1'
  },
  [pscustomobject]@{
    Name = 'P1 Y3 construction structural-preflight fixtures'
    Script = Join-Path $ImplementationRoot 'tianting-y3-construction-preflight\tests\test-preflight.ps1'
  },
  [pscustomobject]@{
    Name = 'P1 mainline authority vertical-slice reference'
    Script = Join-Path $ImplementationRoot 'tianting-authority-vertical-slice\tests\run-all.ps1'
  },
  [pscustomobject]@{
    Name = 'parallel map, UI, and asset discovery manifest'
    Script = Join-Path $ImplementationRoot 'tianting-surface-construction-manifest\tests\run-all.ps1'
  },
  [pscustomobject]@{
    Name = 'P2 seven-star solo session offline reference'
    Script = Join-Path $ImplementationRoot 'tianting-seven-star-session-reference\tests\run-all.ps1'
  },
  [pscustomobject]@{
    Name = 'P3 mansion session time and qualification offline reference'
    Script = Join-Path $ImplementationRoot 'tianting-mansion-session-reference\tests\run-all.ps1'
  },
  [pscustomobject]@{
    Name = 'P3 mansion encounter choreography offline contract'
    Script = $MansionEncounterOrchestrationTest
  },
  [pscustomobject]@{
    Name = 'parallel mainline narrative and presentation contract'
    Script = $MainlinePresentationTest
  },
  [pscustomobject]@{
    Name = 'parallel object field reservation contract'
    Script = $ObjectFieldReservationTest
  }
)

foreach ($Stage in $VerificationStages) {
  if (-not (Test-Path -LiteralPath $Stage.Script -PathType Leaf)) {
    throw "Missing verification script for $($Stage.Name): $($Stage.Script)"
  }

  Write-Output "RUN: $($Stage.Name)"
  & powershell -NoProfile -ExecutionPolicy Bypass -File $Stage.Script
  if ($LASTEXITCODE -ne 0) {
    throw "Verification failed for $($Stage.Name) with exit code $LASTEXITCODE."
  }
}

Write-Output 'PASS: TianTing construction-readiness offline verification.'
