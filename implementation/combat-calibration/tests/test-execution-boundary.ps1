$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$packageContract = Get-Content -LiteralPath (Join-Path $packageRoot 'package-contract.json') -Raw -Encoding utf8 | ConvertFrom-Json
$calibrationContract = Get-Content -LiteralPath (Join-Path $packageRoot 'contract\cross-profession-combat-calibration-contract.json') -Raw -Encoding utf8 | ConvertFrom-Json
$evidenceAdoptionContract = Get-Content -LiteralPath (Join-Path $packageRoot 'evidence-adoption\p0-evidence-collection-and-adoption-contract.json') -Raw -Encoding utf8 | ConvertFrom-Json
$externalCaptureOnboardingContract = Get-Content -LiteralPath (Join-Path $packageRoot 'external-capture-onboarding\package-contract.json') -Raw -Encoding utf8 | ConvertFrom-Json

if ($packageContract.runtime_handoff -ne $false -or $packageContract.production_gate -ne 'closed') {
    throw 'package runtime boundary drifted'
}
if ($calibrationContract.runtime_handoff -ne $false -or $calibrationContract.production_gate -ne 'closed' -or $calibrationContract.non_production -ne $true) {
    throw 'calibration contract production boundary drifted'
}
if ($packageContract.evidence_adoption_package.artifact -ne 'evidence-adoption/p0-evidence-collection-and-adoption-contract.json' -or $packageContract.evidence_adoption_package.status -ne 'offline-evidence-collection-plan-only' -or $packageContract.evidence_adoption_package.production_gate -ne 'closed' -or $packageContract.evidence_adoption_package.runtime_handoff -ne $false) {
    throw 'evidence-adoption package registration drifted'
}
foreach ($field in @('actual_capture_provider', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload')) {
    if ($null -ne $packageContract.evidence_adoption_package.$field) {
        throw "evidence-adoption package field $field must be null"
    }
}
if ($evidenceAdoptionContract.identity.production_gate -ne 'closed' -or $evidenceAdoptionContract.identity.runtime_handoff -ne $false -or $evidenceAdoptionContract.adoption_controls.current_adoption_state -ne 'closed' -or @($evidenceAdoptionContract.adoption_controls.current_satisfied_gate_ids).Count -ne 0) {
    throw 'evidence-adoption contract must remain closed and unadopted'
}
if ($packageContract.external_capture_onboarding_package.artifact -ne 'external-capture-onboarding/package-contract.json' -or $packageContract.external_capture_onboarding_package.status -ne 'offline-external-capture-onboarding-only' -or $packageContract.external_capture_onboarding_package.production_gate -ne 'closed' -or $packageContract.external_capture_onboarding_package.runtime_handoff -ne $false) {
    throw 'external-capture-onboarding package registration drifted'
}
foreach ($field in @('actual_capture_provider', 'actual_y3_project_ref', 'actual_source_origin_preflight_attestation', 'actual_environment_attestation', 'actual_external_artifact_manifest', 'actual_independent_review_handoff', 'actual_adoption_decision', 'absolute_projection_payload')) {
    if ($null -ne $packageContract.external_capture_onboarding_package.$field) {
        throw "external-capture-onboarding package field $field must be null"
    }
}
if ($externalCaptureOnboardingContract.identity.production_gate -ne 'closed' -or $externalCaptureOnboardingContract.identity.runtime_handoff -ne $false -or @($externalCaptureOnboardingContract.canonical_gate_snapshot.currently_satisfied_gate_ids).Count -ne 0 -or $externalCaptureOnboardingContract.trust_boundary.write_authorization -ne $false) {
    throw 'external-capture-onboarding contract must remain closed, unadopted and read-only'
}

$candidate = $calibrationContract.absolute_projection_gate.candidate
if ($candidate.status -ne 'blocked' -or $calibrationContract.absolute_projection_gate.status -ne 'blocked_pending_evidence') {
    throw 'absolute projection must remain blocked'
}
foreach ($field in @('target_object_or_unit_id','hp_max','attack_phy','attack_mag','defense_phy','defense_mag','attack_speed','attack_interval_seconds','move_speed_field','skill_damage','skill_duration_seconds')) {
    if ($null -ne $candidate.$field) {
        throw "absolute projection field $field must be null"
    }
}

$luaFiles = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter '*.lua')
if ($luaFiles.Count -ne 0) {
    throw 'offline calibration package must not contain Lua runtime files'
}

$runtimeMarkers = @('require\s*\(\s*["'']y3', 'GameAPI', 'y3\.')
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'reference') -Recurse -File) + @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'tests') -Recurse -File -Filter '*.js')
foreach ($sourceFile in $sourceFiles) {
    $content = Get-Content -LiteralPath $sourceFile.FullName -Raw -Encoding utf8
    foreach ($marker in $runtimeMarkers) {
        if ($content -match $marker) {
            throw "runtime marker '$marker' found in $($sourceFile.FullName)"
        }
    }
}

Write-Output 'PASS: combat-calibration execution boundary'
