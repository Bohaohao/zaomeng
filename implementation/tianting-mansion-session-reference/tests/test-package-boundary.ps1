$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$packageContractPath = Join-Path $packageRoot 'package-contract.json'
$referenceContractPath = Join-Path $packageRoot 'contract\mansion-session-time-qualification-reference-contract.json'
$workspaceRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$authorityCandidates = @(Get-ChildItem -LiteralPath (Join-Path $workspaceRoot 'docs') -Recurse -File -Filter 'tianting-progression-and-instance-authority-contract.json')
$authorityContractPath = $null
$modelPath = Join-Path $packageRoot 'reference\mansion-session-model.js'

$assertions = 0
function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    $script:assertions += 1
    if (-not $Condition) {
        throw $Message
    }
}

$packageContract = Get-Content -Raw -Encoding UTF8 $packageContractPath | ConvertFrom-Json
$referenceContract = Get-Content -Raw -Encoding UTF8 $referenceContractPath | ConvertFrom-Json
Assert-True ($authorityCandidates.Count -eq 1) 'exactly one upper authority contract must be discoverable under docs'
$authorityContractPath = $authorityCandidates[0].FullName
$authorityContract = Get-Content -Raw -Encoding UTF8 $authorityContractPath | ConvertFrom-Json

Assert-True ($packageContract.package_status -eq 'offline-reference-only') 'package status must remain offline-reference-only'
Assert-True ($packageContract.runtime_handoff -eq $false) 'runtime handoff must remain false'
Assert-True ($packageContract.production_gate -eq 'closed') 'production gate must remain closed'
Assert-True ($packageContract.boundaries.creates_engine_assets -eq $false) 'engine assets must remain outside this package'
Assert-True ($packageContract.boundaries.uses_real_clock_or_time_service -eq $false) 'real clock/time service must remain outside this package'
Assert-True ($packageContract.boundaries.uses_network_or_persistent_storage -eq $false) 'network/persistence must remain outside this package'
Assert-True ($packageContract.boundaries.creates_value_or_settlement_effects -eq $false) 'value/settlement effects must remain outside this package'
Assert-True ($referenceContract.identity.runtime_key -eq $null) 'reference identity runtime key must remain null'
Assert-True ($referenceContract.authority_time_input.timezone -eq 'Asia/Shanghai') 'reference timezone must be Asia/Shanghai'
Assert-True (@($referenceContract.authority_time_input.slot_to_quadrant.PSObject.Properties).Count -eq 12) 'all twelve shichen must be declared'
Assert-True ($referenceContract.deferred.actual_time_provider -eq $null) 'actual time provider must remain deferred'
Assert-True ($referenceContract.deferred.actual_scene_ui_object_and_network_binding -eq $null) 'actual scene/UI/object/network binding must remain deferred'
Assert-True ($referenceContract.deferred.actual_value_material_and_settlement_rules -eq $null) 'actual value/material/settlement rules must remain deferred'
Assert-True ($referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.spec_id -eq 'TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL') 'upper nightmare credential contract must remain the semantic source'
Assert-True ($referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.semantic_ownership -eq 'unique') 'fixture must not become a second nightmare credential schema'
Assert-True ($referenceContract.nightmare_fixture_to_authority_crosswalk.fixture_adapter_status -eq 'test_only_not_an_independent_schema') 'fixture mapping must remain test-only'
Assert-True (@($referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.required_fields).Count -eq 8) 'crosswalk must retain the complete upper required field list'
Assert-True ((@($referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.required_fields) -join "`n") -eq (@($authorityContract.nightmare_qualification_contract.required_fields) -join "`n")) 'crosswalk required fields must exactly follow the upper authority contract'
Assert-True ($referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.spec_id -eq $authorityContract.nightmare_qualification_contract.spec_id) 'crosswalk spec id must exactly follow the upper authority contract'

$runtimeArtifacts = Get-ChildItem -Recurse -File $packageRoot | Where-Object { $_.Extension -in @('.lua', '.y3', '.upui') }
Assert-True ($runtimeArtifacts.Count -eq 0) 'package must not contain runtime, scene, or UI artifact files'

$modelText = Get-Content -Raw -Encoding UTF8 $modelPath
Assert-True ($modelText -notmatch '\bDate\b') 'reference model must not read a clock'
Assert-True ($modelText -notmatch 'process\.|fetch\(|https?:|child_process|require\(') 'reference model must not use external execution or network surfaces'

if (-not [string]::IsNullOrWhiteSpace($env:NODE_PATH)) {
    throw 'NODE_PATH must be empty for the no-external-dependency reference test.'
}
$script:assertions += 1

Write-Output "PASS: $assertions TianTing mansion session reference boundary assertions"
