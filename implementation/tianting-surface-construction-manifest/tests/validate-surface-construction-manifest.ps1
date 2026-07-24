[CmdletBinding()]
param(
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$assertions = 0
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $PSScriptRoot '..\surface-construction-manifest.json'
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw $Message }
}

function Get-StringValues {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @([string]$Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @()
        foreach ($item in $Value.Values) { $result += Get-StringValues $item }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $result = @()
        foreach ($item in $Value) { $result += Get-StringValues $item }
        return $result
    }
    if ($Value -is [pscustomobject]) {
        $result = @()
        foreach ($property in $Value.PSObject.Properties) { $result += Get-StringValues $property.Value }
        return $result
    }
    return @()
}

function Assert-NullProperties {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string[]]$Names,
        [Parameter(Mandatory = $true)][string]$Context
    )

    foreach ($name in $Names) {
        Assert-True ($Object.PSObject.Properties.Name -contains $name) "$Context is missing $name"
        Assert-True ($null -eq $Object.$name) "$Context.$name must remain null in an offline discovery package"
    }
}

$manifestFullPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workspaceRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$manifest = Get-Content -Raw -Encoding utf8 -LiteralPath $manifestFullPath | ConvertFrom-Json

Assert-True ($manifest.schema_version -eq 1) 'Unsupported manifest schema version'
Assert-True ($manifest.identity.spec_id -eq 'TT_SPEC_SURFACE_CONSTRUCTION_DISCOVERY_MANIFEST') 'Unexpected manifest identity'
Assert-True ($manifest.identity.package_status -eq 'offline_preconstruction_discovery_only') 'Manifest must remain offline-only'
Assert-True ($manifest.identity.production_gate -eq 'closed') 'Manifest production gate must remain closed'
Assert-True (-not [bool]$manifest.identity.actual_y3_write_authorized) 'Manifest must not authorize an actual Y3 write'
Assert-NullProperties -Object $manifest.identity -Names @('runtime_key', 'actual_map_root', 'actual_map_key', 'actual_ui_root', 'actual_y3editor_session', 'actual_y3helper_session') -Context 'identity'

Assert-True ($manifest.non_write_contract.mode -eq 'read_discover_validate_only') 'Manifest must be read/discover/validate only'
foreach ($requiredAction in @('create, resize, or save a Y3 map', 'create, hotfix, or save a Y3 UI JSON or UI tree', 'generate or run a Y3-Helper object plugin')) {
    Assert-True ($manifest.non_write_contract.prohibited_actions -contains $requiredAction) "Required non-write prohibition is missing: $requiredAction"
}

Assert-True ($manifest.source_artifacts.Count -ge 6) 'Source artifact coverage is incomplete'
foreach ($source in $manifest.source_artifacts) {
    $relative = ([string]$source.artifact).Replace('/', '\\')
    $path = Join-Path $workspaceRoot $relative
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Source artifact is unavailable: $($source.artifact)"
    Assert-True ([string]$source.status -match '^offline|^relative_') "Source artifact must retain an offline or relative-only status: $($source.artifact)"
}

Assert-NullProperties -Object $manifest.future_project_import_discovery.future_destination -Names @('project_root', 'map_root', 'map_key', 'ui_root', 'editor_session_id', 'helper_session_id', 'runtime_session_id') -Context 'future_destination'
Assert-True ($manifest.future_project_import_discovery.required_live_reads.Count -eq 5) 'Expected five required live discovery reads'
foreach ($read in $manifest.future_project_import_discovery.required_live_reads) {
    Assert-True ($null -eq $read.observed_value) "$($read.discovery_id) must not claim a live observation"
    Assert-True ($read.must_confirm.Count -ge 3) "$($read.discovery_id) lacks import-discovery details"
}

$whiteboxes = @($manifest.map_whitebox_checklist.mainline_boss_whitebox_slices)
Assert-True ($whiteboxes.Count -eq 5) 'Expected exactly five mainline boss whitebox slices'
Assert-True (($whiteboxes | ForEach-Object { $_.order }) -join ',' -eq '1,2,3,4,5') 'Mainline whitebox order must remain sequential'
foreach ($whitebox in $whiteboxes) {
    Assert-True ([string]$whitebox.blueprint_spec_id -match '^TT_SPEC_BLUEPRINT_') "$($whitebox.spec_id) lacks a blueprint source"
    Assert-True ($whitebox.whitebox_focus.Count -ge 3) "$($whitebox.spec_id) lacks readable whitebox goals"
    Assert-NullProperties -Object $whitebox.future_y3_binding -Names @('actual_map_key', 'map_relative_path', 'world_origin', 'terrain_write_set', 'logic_point_ids', 'logic_area_ids', 'camera_profile_id', 'collision_profile_id', 'spawn_id') -Context $whitebox.spec_id
}

$surfaces = @($manifest.ui_hud_checklist.surfaces)
Assert-True ($surfaces.Count -eq 3) 'Expected exactly three minimal HUD surfaces'
foreach ($surface in $surfaces) {
    Assert-True ($surface.required_display_contract.Count -ge 3) "$($surface.spec_id) lacks display requirements"
    Assert-True ([string]$surface.fallback_when_unavailable -match '^unconfirmed;') "$($surface.spec_id) must preserve the unconfirmed fallback"
    Assert-NullProperties -Object $surface.future_y3_binding -Names @('ui_json_path', 'ui_node_id', 'asset_id', 'sound_id', 'text_template_id', 'runtime_event_id') -Context $surface.spec_id
}
$combatSurface = $surfaces | Where-Object { $_.spec_id -eq 'TT_SPEC_UI_SURFACE_COMBAT_WARNING_AND_COUNTERPLAY' }
Assert-True ($null -ne $combatSurface) 'Dual-channel combat HUD surface is missing'
Assert-True ([bool]$combatSurface.color_only_prohibited) 'Dual-channel combat HUD must prohibit color-only communication'
$reviewSurface = $surfaces | Where-Object { $_.spec_id -eq 'TT_SPEC_UI_SURFACE_FAILURE_AND_REVIEW' }
Assert-True ($null -ne $reviewSurface) 'Failure/review surface is missing'

$assets = @($manifest.p0_asset_batch.profiles)
Assert-True ($assets.Count -eq 5) 'Expected exactly five P0 mainline asset profiles'
Assert-True ($manifest.p0_asset_batch.status -eq 'requirements_only_pending_p0_absolute_calibration') 'P0 asset batch must remain calibration-gated'
foreach ($gate in @('P0 absolute combat calibration acceptance', 'stable object keys and source templates')) {
    Assert-True ($manifest.p0_asset_batch.blocking_gates -contains $gate) "P0 asset gate is missing: $gate"
}
foreach ($asset in $assets) {
    Assert-NullProperties -Object $asset.future_object_and_resource_binding -Names @('unit_object_key', 'ability_object_keys', 'model_resource_id', 'animation_resource_ids', 'effect_resource_ids', 'sound_resource_ids', 'material_resource_ids', 'hp_max', 'attack_value', 'physical_defense', 'magical_defense', 'attack_interval_seconds', 'move_speed') -Context $asset.blueprint_spec_id
}

$strings = Get-StringValues $manifest
foreach ($forbiddenPattern in @('(?i)(^|[\\/])maps[\\/]', '(?i)entrymap', '(?i)^y3://', '(?i)^y3editor://')) {
    Assert-True (-not ($strings | Where-Object { $_ -match $forbiddenPattern })) "Manifest contains a concrete Y3 destination or URI matching $forbiddenPattern"
}

Assert-True ($manifest.scope_exclusions -contains 'seven-star playable implementation') 'Seven-star runtime must remain out of scope'
Assert-True ($manifest.scope_exclusions -contains 'tower run, tower bosses, drops, seasons, and economy') 'Tower/economy runtime must remain out of scope'

Write-Output "PASS: $assertions TianTing surface-construction-manifest assertions"
