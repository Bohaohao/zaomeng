$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$contract = Get-Content -LiteralPath (Join-Path $packageRoot 'package-contract.json') -Raw -Encoding utf8 | ConvertFrom-Json
$templateFiles = @(
    'templates\provider-qualification-template.json',
    'templates\source-origin-preflight-attestation-template.json',
    'templates\environment-attestation-template.json',
    'templates\canonicalization-profile-template.json',
    'templates\external-artifact-manifest-template.json',
    'templates\independent-review-handoff-template.json'
)

if ($contract.identity.package_status -ne 'offline-external-capture-onboarding-only' -or $contract.identity.production_gate -ne 'closed' -or $contract.identity.runtime_handoff -ne $false) {
    throw 'external-capture-onboarding production boundary drifted'
}
foreach ($field in @('actual_capture_provider', 'actual_provider_qualification', 'actual_y3_project_ref', 'actual_source_origin_preflight_attestation', 'actual_environment_attestation', 'actual_external_artifact_manifest', 'actual_independent_review_handoff', 'actual_adoption_decision')) {
    if ($null -ne $contract.identity.$field) {
        throw "onboarding identity field $field must remain null"
    }
}
if ($contract.trust_boundary.write_authorization -ne $false) {
    throw 'external-capture-onboarding must not authorize writes'
}
foreach ($field in @('node_fengari_live_capture_trust_root', 'local_repository_may_register_provider', 'local_repository_may_accept_evidence', 'local_repository_may_adopt_p0_gate', 'local_repository_may_project_absolute_fields')) {
    if ($contract.trust_boundary.$field -ne $false) {
        throw "onboarding trust-boundary field $field must remain false"
    }
}
foreach ($field in @('provider_credentials', 'provider_endpoint', 'provider_private_key', 'local_provider_registration')) {
    if ($null -ne $contract.trust_boundary.$field) {
        throw "onboarding trust-boundary field $field must remain null"
    }
}
if (@($contract.canonical_gate_snapshot.currently_satisfied_gate_ids).Count -ne 0) {
    throw 'external-capture-onboarding cannot satisfy P0 gates'
}
foreach ($step in @($contract.first_fieldwork_order)) {
    if ($step.status -ne 'blocked_pending_external_operator' -or $null -ne $step.external_artifact_ref) {
        throw "onboarding fieldwork step $($step.step_id) must remain blocked and empty"
    }
}
foreach ($property in $contract.deferred_outputs.PSObject.Properties) {
    if ($null -ne $property.Value) {
        throw "onboarding deferred output $($property.Name) must remain null"
    }
}
foreach ($relativeFile in $templateFiles) {
    $template = Get-Content -LiteralPath (Join-Path $packageRoot $relativeFile) -Raw -Encoding utf8 | ConvertFrom-Json
    if ($template.identity.status -ne 'not_created') {
        throw "onboarding template $relativeFile must remain uncreated"
    }
}

$expectedFiles = @(
    'README.md',
    'external-capture-operation-runbook.md',
    'package-contract.json',
    'reference\external-capture-onboarding-core.js',
    'templates\provider-qualification-template.json',
    'templates\source-origin-preflight-attestation-template.json',
    'templates\environment-attestation-template.json',
    'templates\canonicalization-profile-template.json',
    'templates\external-artifact-manifest-template.json',
    'templates\independent-review-handoff-template.json',
    'tests\run-all.ps1',
    'tests\test-external-capture-onboarding.js',
    'tests\test-execution-boundary.ps1'
)
$actualFiles = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse | ForEach-Object { $_.FullName.Substring($packageRoot.Length).TrimStart('\') } | Sort-Object)
if ((@($actualFiles) -join '|') -ne (@($expectedFiles | Sort-Object) -join '|')) {
    throw 'external-capture-onboarding package file allowlist drifted'
}

$runtimeMarkers = @('require\s*\(\s*["'']y3', 'GameAPI', 'y3\.')
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'reference') -Recurse -File -Filter '*.js') + @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'tests') -File -Filter '*.js')
foreach ($sourceFile in $sourceFiles) {
    $content = Get-Content -LiteralPath $sourceFile.FullName -Raw -Encoding utf8
    foreach ($marker in $runtimeMarkers) {
        if ($content -match $marker) {
            throw "runtime marker '$marker' found in $($sourceFile.FullName)"
        }
    }
}
foreach ($forbiddenExtension in @('*.lua', '*.y3', '*.upui')) {
    if (@(Get-ChildItem -LiteralPath $packageRoot -File -Recurse -Filter $forbiddenExtension).Count -ne 0) {
        throw "forbidden runtime artifact found: $forbiddenExtension"
    }
}

Write-Output 'PASS: P0 external-capture-onboarding execution boundary'
