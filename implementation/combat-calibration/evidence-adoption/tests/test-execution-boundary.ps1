$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$parentRoot = Split-Path -Parent $packageRoot
$contract = Get-Content -LiteralPath (Join-Path $packageRoot 'p0-evidence-collection-and-adoption-contract.json') -Raw -Encoding utf8 | ConvertFrom-Json
$sourceSnapshot = Get-Content -LiteralPath (Join-Path $packageRoot 'source-snapshots.json') -Raw -Encoding utf8 | ConvertFrom-Json
$collectionTemplates = Get-Content -LiteralPath (Join-Path $packageRoot 'templates\evidence-collection-templates.json') -Raw -Encoding utf8 | ConvertFrom-Json
$adoptionTemplate = Get-Content -LiteralPath (Join-Path $packageRoot 'templates\adoption-decision-template.json') -Raw -Encoding utf8 | ConvertFrom-Json

if ($contract.identity.production_gate -ne 'closed' -or $contract.identity.runtime_handoff -ne $false -or $contract.identity.package_status -ne 'offline-evidence-collection-plan-only') {
    throw 'evidence-adoption package production boundary drifted'
}
foreach ($field in @('actual_capture_provider', 'actual_y3_project_ref', 'accepted_evidence_ledger', 'adoption_decision', 'absolute_projection_payload')) {
    if ($null -ne $contract.identity.$field) {
        throw "evidence-adoption identity field $field must be null"
    }
}
if ($contract.source_calibration_contract.content_sha256 -notmatch '^[0-9a-f]{64}$') {
    throw 'evidence-adoption parent digest must be lowercase SHA-256'
}
if (@($contract.adoption_controls.current_satisfied_gate_ids).Count -ne 0 -or $contract.adoption_controls.current_adoption_state -ne 'closed' -or $contract.adoption_controls.automatic_gate_promotion -ne $false) {
    throw 'evidence-adoption gate promotion boundary drifted'
}
foreach ($plan in @($contract.gate_collection_plans)) {
    if ($plan.collection_status -ne 'blocked_pending_external_evidence' -or $null -ne $plan.accepted_evidence_refs -or $plan.adoption_status -ne 'blocked_pending_external_evidence') {
        throw "evidence-adoption plan $($plan.gate_id) must remain unaccepted"
    }
}
foreach ($property in $contract.deferred_outputs.PSObject.Properties) {
    if ($null -ne $property.Value) {
        throw "evidence-adoption deferred output $($property.Name) must be null"
    }
}
foreach ($field in @('actual_external_capture_source', 'accepted_evidence_ledger', 'adoption_decision')) {
    if ($null -ne $sourceSnapshot.identity.$field) {
        throw "source snapshot identity field $field must be null"
    }
}
foreach ($property in $sourceSnapshot.external_capture_family.PSObject.Properties) {
    if ($property.Name -ne 'rule' -and $null -ne $property.Value) {
        throw "source snapshot external capture field $($property.Name) must be null"
    }
}
if ($collectionTemplates.identity.status -ne 'offline-template-only' -or $null -ne $collectionTemplates.identity.actual_capture_records -or $null -ne $collectionTemplates.identity.accepted_evidence_ledger -or $null -ne $collectionTemplates.identity.absolute_projection_payload) {
    throw 'collection template boundary drifted'
}
if ($adoptionTemplate.identity.status -ne 'not_created') {
    throw 'adoption template must remain uncreated'
}
foreach ($decision in @($adoptionTemplate.gate_decisions)) {
    foreach ($field in @('decision', 'evidence_bundle_digest', 'reviewer_proof_ref', 'reason')) {
        if ($null -ne $decision.$field) {
            throw "adoption template decision $($decision.gate_id)/$field must be null"
        }
    }
}

$expectedFiles = @(
    'README.md',
    'p0-evidence-collection-and-adoption-contract.json',
    'source-snapshots.json',
    'reference\evidence-adoption-core.js',
    'templates\adoption-decision-template.json',
    'templates\evidence-collection-templates.json',
    'tests\run-all.ps1',
    'tests\test-evidence-adoption.js',
    'tests\test-execution-boundary.ps1'
)
$actualFiles = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse | ForEach-Object { $_.FullName.Substring($packageRoot.Length).TrimStart('\') } | Sort-Object)
if ((@($actualFiles) -join '|') -ne (@($expectedFiles | Sort-Object) -join '|')) {
    throw 'evidence-adoption package file allowlist drifted'
}

$runtimeMarkers = @('require\s*\(\s*["'']y3', 'GameAPI', 'y3\.')
$sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'reference') -File -Recurse -Filter '*.js') + @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'tests') -File -Filter '*.js')
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

Write-Output 'PASS: P0 evidence-adoption execution boundary'
