[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetMapRoot,
    [string]$UiRoot,
    [string]$ObjectInterfaceIdentifier,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
$errors = [System.Collections.Generic.List[string]]::new()

function Add-PreflightError {
    param([string]$Message)
    [void]$script:errors.Add($Message)
}

function Get-ExistingDirectory {
    param([string]$Path, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        Add-PreflightError "$Label is missing or is not a directory: $Path"
        return $null
    }
    return (Get-Item -LiteralPath $Path -Force).FullName
}

function Test-DescendantPath {
    param([string]$ParentPath, [string]$ChildPath)
    if ([string]::IsNullOrWhiteSpace($ParentPath) -or [string]::IsNullOrWhiteSpace($ChildPath)) { return $false }
    $parent = [IO.Path]::GetFullPath($ParentPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $child = [IO.Path]::GetFullPath($ChildPath)
    $prefix = $parent + [IO.Path]::DirectorySeparatorChar
    return $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

$mapRoot = Get-ExistingDirectory -Path $TargetMapRoot -Label 'target map root'
$scriptRoot = $null
$y3Root = $null
$uiResolved = $null
$objectInterfaceStatus = 'not_requested'

if ($null -ne $mapRoot) {
    $scriptRoot = Get-ExistingDirectory -Path (Join-Path $mapRoot 'script') -Label 'required map-local script root'
    if ($null -ne $scriptRoot) {
        $y3Root = Get-ExistingDirectory -Path (Join-Path $scriptRoot 'y3') -Label 'required y3-lualib root'
        if ($null -ne $y3Root) {
            foreach ($directory in @('meta', 'game')) {
                [void](Get-ExistingDirectory -Path (Join-Path $y3Root $directory) -Label "required y3-lualib structural directory '$directory'")
            }
        }
    }

    $requestedUiRoot = if ([string]::IsNullOrWhiteSpace($UiRoot)) { Join-Path $mapRoot 'ui' } else { $UiRoot }
    $uiResolved = Get-ExistingDirectory -Path $requestedUiRoot -Label 'required UI root'
    if ($null -ne $uiResolved -and -not (Test-DescendantPath -ParentPath $mapRoot -ChildPath $uiResolved)) {
        Add-PreflightError "UI root must reside under target map root: $uiResolved"
    }
}

if (-not [string]::IsNullOrWhiteSpace($ObjectInterfaceIdentifier)) {
    if ($ObjectInterfaceIdentifier -notmatch '^[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)+$') {
        Add-PreflightError "object interface identifier must be a lowercase dotted interface name, not an object key: $ObjectInterfaceIdentifier"
        $objectInterfaceStatus = 'invalid'
    }
    else {
        $objectInterfaceStatus = 'declared_opaque_not_invoked'
    }
}

$report = [ordered]@{
    package = 'tianting-y3-construction-preflight'
    result = if ($errors.Count -eq 0) { 'structural_preflight_passed' } else { 'structural_preflight_blocked' }
    production_gate = 'closed'
    target_map_root = $mapRoot
    structural_checks = [ordered]@{
        script_root = if ($null -ne $scriptRoot) { 'present' } else { 'missing' }
        y3_lualib_root = if ($null -ne $y3Root) { 'present' } else { 'missing' }
        y3_api_signature_verification = 'not_performed'
        ui_root = if ($null -ne $uiResolved) { 'present' } else { 'missing' }
        ui_node_tree_verification = 'not_performed'
        object_interface_identifier = $objectInterfaceStatus
        object_interface_availability = 'not_verified'
        editor_readback = 'not_performed'
    }
    resolved_paths = [ordered]@{
        script_root = $scriptRoot
        y3_lualib_root = $y3Root
        ui_root = $uiResolved
    }
    permissions = [ordered]@{
        maps_created = $false
        objects_created = $false
        lua_written = $false
        ui_written = $false
        production_object_creation_permitted = $false
    }
    errors = @($errors)
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 8
}
else {
    Write-Output 'TianTing Y3 construction preflight'
    Write-Output "  target map root: $($report.target_map_root)"
    Write-Output "  script root: $($report.structural_checks.script_root)"
    Write-Output "  y3-lualib root: $($report.structural_checks.y3_lualib_root)"
    Write-Output "  UI root: $($report.structural_checks.ui_root)"
    Write-Output "  object interface: $($report.structural_checks.object_interface_identifier)"
    Write-Output "  production gate: $($report.production_gate)"
    foreach ($message in $errors) { Write-Output "BLOCKED: $message" }
}

if ($errors.Count -gt 0) { exit 1 }
if (-not $AsJson) { Write-Output 'PASS: TianTing Y3 construction structural preflight passed; production remains closed.' }
