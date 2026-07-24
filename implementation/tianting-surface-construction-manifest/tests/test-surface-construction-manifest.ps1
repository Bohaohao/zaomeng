$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$assertions = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw $Message }
}

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $packageRoot 'surface-construction-manifest.json'
$validatorPath = Join-Path $PSScriptRoot 'validate-surface-construction-manifest.ps1'
$powershell = Join-Path $PSHOME 'powershell.exe'

$validatorOutput = & $powershell -NoProfile -ExecutionPolicy Bypass -File $validatorPath -ManifestPath $manifestPath 2>&1
$validatorText = ($validatorOutput | ForEach-Object { [string]$_ }) -join "`n"
Assert-True ($LASTEXITCODE -eq 0) "Manifest validation failed: $validatorText"
Assert-True ($validatorText -match '^PASS: \d+ TianTing surface-construction-manifest assertions\s*$') 'Validator did not report its assertion result'

$manifest = Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath | ConvertFrom-Json
Assert-True ($manifest.identity.actual_y3_write_authorized -eq $false) 'Manifest unexpectedly grants Y3 write authority'
Assert-True ($manifest.future_import_sequence[0].write_permitted -eq $false) 'The first import step must be read-only'
Assert-True ($manifest.future_import_sequence[1].write_permitted -eq $false) 'Target-map approval must not itself write Y3 data'
Assert-True ($manifest.future_import_sequence[2].write_permitted -eq 'future_explicit_confirmation_required') 'Whitebox creation must require future confirmation'
Assert-True ($manifest.future_import_sequence[3].write_permitted -eq 'future_explicit_confirmation_required') 'HUD creation must require future confirmation'
Assert-True ($manifest.future_import_sequence[4].write_permitted -eq 'future_explicit_confirmation_required') 'P0 asset binding must require future confirmation'

$mainlineIds = @($manifest.map_whitebox_checklist.mainline_boss_whitebox_slices | ForEach-Object { $_.blueprint_spec_id })
foreach ($id in @('TT_SPEC_BLUEPRINT_PATROL_FALSE_ORDER', 'TT_SPEC_BLUEPRINT_BROKEN_RAINBOW_NODE', 'TT_SPEC_BLUEPRINT_FOUR_GATE_ECHO', 'TT_SPEC_BLUEPRINT_STAR_CALENDAR_RIFT', 'TT_SPEC_BLUEPRINT_DISCIPLINE_GENERAL')) {
    Assert-True ($mainlineIds -contains $id) "Mainline whitebox handoff is missing $id"
}

$surfaceIds = @($manifest.ui_hud_checklist.surfaces | ForEach-Object { $_.spec_id })
foreach ($id in @('TT_SPEC_UI_SURFACE_COMBAT_WARNING_AND_COUNTERPLAY', 'TT_SPEC_UI_SURFACE_TEAM_AND_SESSION_STATUS', 'TT_SPEC_UI_SURFACE_FAILURE_AND_REVIEW')) {
    Assert-True ($surfaceIds -contains $id) "HUD handoff is missing $id"
}

Assert-True ($manifest.p0_asset_batch.profiles.Count -eq $mainlineIds.Count) 'P0 asset batch and whitebox batch must describe the same five mainline encounters'
Assert-True ($manifest.non_write_contract.prohibited_actions.Count -ge 6) 'Non-write contract is incomplete'

Write-Output "PASS: $assertions TianTing surface-construction-manifest test assertions"
