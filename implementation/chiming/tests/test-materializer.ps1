$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $packageRoot 'preconstruction-manifest.json'
$materializer = Join-Path $packageRoot 'tools\materialize-object-commands.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('chiming-materializer-' + [Guid]::NewGuid().ToString('N'))
$fixturePath = Join-Path $tempRoot 'resolved-test-manifest.json'
$outputPath = Join-Path $tempRoot 'commands.ps1'
$refusedOutput = Join-Path $tempRoot 'must-not-exist.ps1'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in $manifest.execution_gates.PSObject.Properties) {
        if ($property.Name -eq 'map_path') { $property.Value = 'X:\Synthetic\maps\EntryMap' }
        elseif ($property.Name -eq 'script_root') { $property.Value = 'X:\Synthetic\maps\EntryMap\script' }
        elseif ($property.Name -eq 'y3_obj_edit_script') { $property.Value = 'X:\Synthetic\y3_obj_edit.py' }
        else { $property.Value = $true }
    }
    $manifest.hero.y3_id = 990300001; $manifest.hero.model_id = 990390001; $manifest.hero.icon_id = 990390002; $manifest.hero.unresolved_fields = @()
    $manifest.hero.object_fields | Add-Member -NotePropertyName common_atk_type -NotePropertyValue 1
    $manifest.hero.object_fields | Add-Member -NotePropertyName turn_speed -NotePropertyValue 10
    $manifest.hero.object_fields | Add-Member -NotePropertyName sight_range -NotePropertyValue 1200
    $manifest.hero.object_fields | Add-Member -NotePropertyName common_atk_range -NotePropertyValue 700
    $manifest.hero.object_fields | Add-Member -NotePropertyName hero_ability_list -NotePropertyValue @('990310001:1','990310018:1')
    $manifest.hero.object_fields | Add-Member -NotePropertyName common_ability_list -NotePropertyValue @('990380001:1')
    $index = 0
    foreach ($ability in $manifest.abilities) {
        $index++; $ability.y3_id = 990310000 + $index; $ability.icon_id = 990391000 + $index; $ability.unresolved_fields = @()
        $levels = [int]$ability.object_fields.ability_max_level; $geometry = @(1..$levels | ForEach-Object { 100 })
        $ability.object_fields | Add-Member -NotePropertyName ability_damage_range -NotePropertyValue $geometry
        if ($ability.object_fields.sight_type -eq 1) { $ability.object_fields | Add-Member -NotePropertyName sector_radius -NotePropertyValue $geometry; $ability.object_fields | Add-Member -NotePropertyName sector_angle -NotePropertyValue @(1..$levels | ForEach-Object { 14 }) }
        elseif ($ability.object_fields.sight_type -eq 2) { $ability.object_fields | Add-Member -NotePropertyName arrow_length -NotePropertyValue $geometry; $ability.object_fields | Add-Member -NotePropertyName arrow_width -NotePropertyValue @(1..$levels | ForEach-Object { 50 }) }
        elseif ($ability.object_fields.sight_type -eq 3) { $ability.object_fields | Add-Member -NotePropertyName circle_radius -NotePropertyValue $geometry; $ability.object_fields | Add-Member -NotePropertyName ability_cast_range -NotePropertyValue $geometry }
    }
    $index = 0
    foreach ($modifier in $manifest.modifiers) { $index++; $modifier.y3_id = 990320000 + $index; $modifier.icon_id = 990392000 + $index }
    $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixturePath -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $materializer -ManifestPath $fixturePath -OutputPath $outputPath -SkipPathExistenceCheck
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic materialization failed' }
    $generated = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
    $modifierCount = ([regex]::Matches($generated, '-type modifier -create')).Count
    $abilityCount = ([regex]::Matches($generated, '-type ability -create')).Count
    $unitCount = ([regex]::Matches($generated, '-type unit -create')).Count
    if ($modifierCount -ne 12 -or $abilityCount -ne 18 -or $unitCount -ne 1) { throw "Generated counts mismatch: modifier=$modifierCount ability=$abilityCount unit=$unitCount" }
    $firstModifier = $generated.IndexOf('-type modifier -create'); $firstAbility = $generated.IndexOf('-type ability -create'); $firstUnit = $generated.IndexOf('-type unit -create')
    if (-not ($firstModifier -lt $firstAbility -and $firstAbility -lt $firstUnit)) { throw 'Creation order must be modifiers, abilities, hero.' }
    $refusal = & powershell -NoProfile -ExecutionPolicy Bypass -File $materializer -ManifestPath $manifestPath -OutputPath $refusedOutput -SkipPathExistenceCheck 2>&1
    if ($LASTEXITCODE -ne 1) { throw 'Unresolved production manifest must be refused.' }
    if (Test-Path -LiteralPath $refusedOutput) { throw 'Refused materialization must not create output.' }
    Write-Output 'PASS: materializer generated 31 creates and refused unresolved production data.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
