$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $root '..\..')).Path
$preflightPath = Join-Path $PSScriptRoot 'preflight.ps1'
$manifestPath = Join-Path $root 'preconstruction-manifest.json'
$layoutPath = (Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs') -Recurse -File -Filter 'layout.json' |
    Where-Object { $_.FullName -like '*huaguoshan-96x72*' } |
    Select-Object -First 1).FullName
$bindingPath = Join-Path $root 'map-logic-binding.json'
if ([string]::IsNullOrWhiteSpace($layoutPath)) { throw 'Missing huaguoshan-96x72 layout.json.' }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('huaguoshan-map-binding-' + [guid]::NewGuid().ToString('N'))
$invalidBindingPath = Join-Path $tempRoot 'invalid-binding.json'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $bindingText = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8
    $encounterKeyPattern = [regex]'"encounter_key":"HG_E_MOUNTAIN_PATH"'
    if ($encounterKeyPattern.Matches($bindingText).Count -lt 1) {
        throw 'duplicate binding-property fixture could not locate encounter_key'
    }
    $duplicateBindingText = $encounterKeyPattern.Replace(
        $bindingText,
        '"encounter_key":"HG_E_MOUNTAIN_PATH","encounter_key":"HG_E_MOUNTAIN_PATH"',
        1
    )
    Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8 -Value $duplicateBindingText
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath `
            -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorActionPreference }
    if ($exitCode -eq 0) { throw 'preflight unexpectedly accepted a duplicate raw binding property' }
    $text = $result | Out-String
    if ($text -notmatch 'duplicate JSON property "encounter_key" at \$\.encounter_resource_bindings\[0\]') {
        throw "preflight did not diagnose the duplicate raw binding property: $text"
    }

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    ($binding.encounter_resource_bindings | Where-Object { $_.resource_key -eq 'area_hg_boss_jiao' } | Select-Object -First 1).expected_type = 'circleArea'
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted an invalid map resource type' }
    $text = $result | Out-String
    if ($text -notmatch 'map binding type mismatch for area_hg_boss_jiao') { throw "preflight did not report the intended binding mismatch: $text" }

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    ($binding.encounter_resource_bindings | Where-Object { $_.resource_key -eq 'area_hg_boss_jiao' } | Select-Object -First 1).role = ''
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted a blank map resource role' }
    $text = $result | Out-String
    if ($text -notmatch 'map binding resource role must be a non-empty string') { throw "preflight did not report the blank role: $text" }

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    ($binding.encounter_resource_bindings | Where-Object { $_.resource_key -eq 'area_hg_boss_jiao' } | Select-Object -First 1).role = 'unexpected_boss_role'
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted a non-empty map resource role drift' }
    $text = $result | Out-String
    if ($text -notmatch 'Lua Config encounter resource bindings do not match map logic binding') { throw "preflight did not report the non-empty role drift: $text" }

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $macaqueSpawn = @($binding.spawn_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_MACAQUE_KING' -and $_.unit_key -eq 'HG_U_MACAQUE_KING'
    })[0]
    if ($null -eq $macaqueSpawn) { throw 'Cross-Boss parity fixture could not find the Macaque King spawn.' }
    $macaqueSpawn.anchor_key = 'arena_jiaomowang_phase1'
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted a cross-Boss arena spawn' }
    $text = $result | Out-String
    if ($text -notmatch 'HG_E_MACAQUE_KING: public boss spawn anchor must match encounter boss_arena arena_mihouwang') {
        throw "preflight did not enforce Boss arena ownership: $text"
    }
    if ($text -notmatch 'Lua Config spawn bindings do not match map logic binding') {
        throw "preflight did not include spawn bindings in Lua/JSON parity: $text"
    }

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $binding.real_map_binding_verified = $true
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted editor binding drift' }
    $text = $result | Out-String
    if ($text -notmatch 'Lua Config editor_bound gate does not match map logic binding') { throw "preflight did not report editor binding drift: $text" }

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    (@(($binding.instance_contract_role_schema | Where-Object { $_.contract_key -eq 'HG_I_DRAGON_FOUR_SEAS' })[0].roles | Where-Object { $_.role -eq 'slot_bounds' })[0]).expected_type = 'circleArea'
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted an invalid instance role schema type' }
    $text = $result | Out-String
    if ($text -notmatch 'instance contract role schema expected_type is invalid') { throw "preflight did not report the invalid instance role schema type: $text" }

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    ($binding.encounter_instance_map_states | Where-Object { $_.encounter_key -eq 'HG_E_DRAGON_OLD_TIDE' } | Select-Object -First 1).slot_count = 3
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted encounter slot_count drift' }
    $text = $result | Out-String
    if ($text -notmatch 'encounter instance map state slot_count differs from instance contract') { throw "preflight did not report encounter slot_count drift: $text" }

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $binding.instance_map_contracts[0].slots[0].roles[0].resource_key = 'area_hg_dragon_four_seas_slot_1_bounds_fixture'
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidBindingPath -Encoding UTF8
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath -ManifestPath $manifestPath -LayoutPath $layoutPath -BindingPath $invalidBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted Lua/JSON instance slot drift' }
    $text = $result | Out-String
    if ($text -notmatch 'Lua Config instance map contracts do not match map logic binding') {
        throw "preflight did not compare the complete Lua/JSON instance slot contract: $text"
    }

    $synchronizedFixtureRoot = Join-Path $tempRoot 'synchronized-lua-json-role-drift'
    $fixtureManifestPath = Join-Path $synchronizedFixtureRoot 'preconstruction-manifest.json'
    $fixtureBindingPath = Join-Path $synchronizedFixtureRoot 'map-logic-binding.json'
    $fixtureLuaRoot = Join-Path $synchronizedFixtureRoot 'lua'
    New-Item -ItemType Directory -Path $synchronizedFixtureRoot -Force | Out-Null
    Copy-Item -LiteralPath $manifestPath -Destination $fixtureManifestPath -Force
    Copy-Item -LiteralPath (Join-Path $root 'lua') -Destination $fixtureLuaRoot -Recurse -Force

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $gorillaBinding = @($binding.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_MOUNTAIN_PATH' -and $_.resource_key -eq 'arena_gorilla'
    })[0]
    if ($null -eq $gorillaBinding) { throw 'synchronized role-drift fixture could not find arena_gorilla' }
    $gorillaBinding.role = 'synchronized_fixture_role'
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixtureBindingPath -Encoding UTF8

    $fixtureConfigPath = Join-Path $fixtureLuaRoot 'huaguoshan_config.lua'
    $configSource = Get-Content -LiteralPath $fixtureConfigPath -Raw -Encoding UTF8
    $rolePattern = "(?m)^([ \t]*arena_gorilla[ \t]*=[ \t]*)'major_elite_anchor'(,[ \t]*)\r?$"
    if ([regex]::Matches($configSource, $rolePattern).Count -ne 1) {
        throw 'synchronized role-drift fixture could not locate the Lua arena_gorilla role'
    }
    $configSource = [regex]::Replace($configSource, $rolePattern, "`$1'synchronized_fixture_role'`$2")
    Set-Content -LiteralPath $fixtureConfigPath -Value $configSource -Encoding UTF8

    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath `
        -ManifestPath $fixtureManifestPath -LayoutPath $layoutPath -BindingPath $fixtureBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted synchronized Lua/JSON public role drift' }
    $text = $result | Out-String
    if ($text -notmatch 'manifest resource role differs from map logic binding for HG_E_MOUNTAIN_PATH\|arena_gorilla') {
        throw "preflight did not use the manifest to reject synchronized Lua/JSON role drift: $text"
    }

    $synchronizedBossRoot = Join-Path $tempRoot 'synchronized-public-boss-identity-swap'
    $bossManifestPath = Join-Path $synchronizedBossRoot 'preconstruction-manifest.json'
    $bossBindingPath = Join-Path $synchronizedBossRoot 'map-logic-binding.json'
    $bossLuaRoot = Join-Path $synchronizedBossRoot 'lua'
    New-Item -ItemType Directory -Path $synchronizedBossRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'lua') -Destination $bossLuaRoot -Recurse -Force

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $macaqueEncounter = @($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_MACAQUE_KING' })[0]
    $jiaoEncounter = @($manifest.encounters | Where-Object { $_.record_key -eq 'HG_E_JIAO_KING' })[0]
    $macaqueEncounter.boss_unit_key = 'HG_U_JIAO_KING_P1'
    $jiaoEncounter.boss_unit_key = 'HG_U_MACAQUE_KING'
    $macaqueEncounter.map_logic_resource_keys = @($macaqueEncounter.map_logic_resource_keys | ForEach-Object {
        if ($_ -eq 'arena_mihouwang') { 'arena_jiaomowang_phase1' } else { $_ }
    })
    $jiaoEncounter.map_logic_resource_keys = @($jiaoEncounter.map_logic_resource_keys | ForEach-Object {
        if ($_ -eq 'arena_jiaomowang_phase1') { 'arena_mihouwang' } else { $_ }
    })
    $macaqueEncounter.map_logic_resource_roles.PSObject.Properties.Remove('arena_mihouwang')
    $macaqueEncounter.map_logic_resource_roles | Add-Member -NotePropertyName arena_jiaomowang_phase1 -NotePropertyValue boss_arena
    $jiaoEncounter.map_logic_resource_roles.PSObject.Properties.Remove('arena_jiaomowang_phase1')
    $jiaoEncounter.map_logic_resource_roles | Add-Member -NotePropertyName arena_mihouwang -NotePropertyValue boss_arena
    $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bossManifestPath -Encoding UTF8

    $binding = Get-Content -LiteralPath $bindingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    (@($binding.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_MACAQUE_KING' -and $_.resource_key -eq 'arena_mihouwang'
    })[0]).resource_key = 'arena_jiaomowang_phase1'
    (@($binding.encounter_resource_bindings | Where-Object {
        $_.encounter_key -eq 'HG_E_JIAO_KING' -and $_.resource_key -eq 'arena_jiaomowang_phase1'
    })[0]).resource_key = 'arena_mihouwang'
    $macaqueSpawn = @($binding.spawn_bindings | Where-Object { $_.encounter_key -eq 'HG_E_MACAQUE_KING' })[0]
    $jiaoSpawn = @($binding.spawn_bindings | Where-Object { $_.encounter_key -eq 'HG_E_JIAO_KING' })[0]
    $macaqueSpawn.unit_key = 'HG_U_JIAO_KING_P1'
    $macaqueSpawn.anchor_key = 'arena_jiaomowang_phase1'
    $jiaoSpawn.unit_key = 'HG_U_MACAQUE_KING'
    $jiaoSpawn.anchor_key = 'arena_mihouwang'
    $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bossBindingPath -Encoding UTF8

    $bossConfigPath = Join-Path $bossLuaRoot 'huaguoshan_config.lua'
    $configSource = Get-Content -LiteralPath $bossConfigPath -Raw -Encoding UTF8
    $replacements = @(
        [pscustomobject]@{
            From = "resources = { 'arena_mihouwang', 'area_hg_boss_mihou'"
            To = "resources = { 'arena_jiaomowang_phase1', 'area_hg_boss_mihou'"
        },
        [pscustomobject]@{
            From = "resources = { 'arena_jiaomowang_phase1', 'area_hg_boss_jiao'"
            To = "resources = { 'arena_mihouwang', 'area_hg_boss_jiao'"
        }
    )
    foreach ($entry in $replacements) {
        if (-not $configSource.Contains($entry.From)) { throw "synchronized Boss fixture could not locate Lua text: $($entry.From)" }
        $configSource = $configSource.Replace($entry.From, $entry.To)
    }
    $swapPairs = @(
        [pscustomobject]@{
            Left = "boss_unit_key = 'HG_U_MACAQUE_KING', boss_spawn_anchor = 'arena_mihouwang'"
            Right = "boss_unit_key = 'HG_U_JIAO_KING_P1', boss_spawn_anchor = 'arena_jiaomowang_phase1'"
            Marker = '__HG_PUBLIC_BOSS_IDENTITY_SWAP__'
        },
        [pscustomobject]@{
            Left = "        arena_mihouwang = 'boss_arena',"
            Right = "        arena_jiaomowang_phase1 = 'boss_arena',"
            Marker = '__HG_PUBLIC_BOSS_ARENA_ROLE_SWAP__'
        }
    )
    foreach ($pair in $swapPairs) {
        if (-not $configSource.Contains($pair.Left) -or -not $configSource.Contains($pair.Right)) {
            throw "synchronized Boss fixture could not locate Lua swap pair: $($pair.Left)"
        }
        $configSource = $configSource.Replace($pair.Left, $pair.Marker)
        $configSource = $configSource.Replace($pair.Right, $pair.Left)
        $configSource = $configSource.Replace($pair.Marker, $pair.Right)
    }
    Set-Content -LiteralPath $bossConfigPath -Value $configSource -Encoding UTF8

    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File $preflightPath `
        -ManifestPath $bossManifestPath -LayoutPath $layoutPath -BindingPath $bossBindingPath 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'preflight unexpectedly accepted a synchronized public Boss identity swap' }
    $text = $result | Out-String
    foreach ($pattern in @(
        'manifest HG_E_MACAQUE_KING: canonical public boss tuple must be HG_U_MACAQUE_KING -> arena_mihouwang',
        'map logic binding HG_E_MACAQUE_KING: canonical public boss tuple must be HG_U_MACAQUE_KING -> arena_mihouwang',
        'Lua Config HG_E_MACAQUE_KING: canonical public boss tuple must be HG_U_MACAQUE_KING -> arena_mihouwang'
    )) {
        if ($text -notmatch $pattern) {
            throw "preflight did not enforce canonical Boss identity across synchronized contracts: $text"
        }
    }

    Write-Output 'PASS: preflight rejects duplicate binding keys, editor-state drift, synchronized Boss identity swaps, public binding drift, and complete instance slot/schema drift.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
