param(
    [string]$Y3LuaApiRoot = (Join-Path $env:USERPROFILE '.codex\skills\y3-lua-api')
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$baseline = Get-Content -Raw -Encoding UTF8 (Join-Path $packageRoot 'y3-api-baseline.json') | ConvertFrom-Json
$sourceRoot = Join-Path $Y3LuaApiRoot 'sources\y3-lualib'

if (-not (Test-Path -LiteralPath $sourceRoot)) {
    throw "y3-lualib cache not found: $sourceRoot"
}

$actualCommit = (& git -C $sourceRoot rev-parse HEAD).Trim()
if ($actualCommit -ne $baseline.commit) {
    throw "y3-lualib commit mismatch: expected $($baseline.commit), found $actualCommit"
}

$errors = [System.Collections.Generic.List[string]]::new()
foreach ($module in $baseline.modules.PSObject.Properties) {
    $docPath = Join-Path $sourceRoot ("doc\API\{0}.md" -f $module.Name)
    if (-not (Test-Path -LiteralPath $docPath)) {
        $errors.Add("missing API module document: $($module.Name)")
        continue
    }
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $docPath
    foreach ($method in @($module.Value)) {
        if ($content -notmatch ('(?m)^##\s+' + [regex]::Escape([string]$method) + '\s*$')) {
            $errors.Add("$($module.Name).$method not found in public API docs")
        }
    }
}

$eventSource = Get-Content -Raw -Encoding UTF8 (Join-Path $sourceRoot 'meta\event.lua')
foreach ($eventName in @($baseline.events)) {
    if ($eventSource -notmatch ('M\.config\["' + [regex]::Escape([string]$eventName) + '"\]')) {
        $errors.Add("event not found: $eventName")
    }
}

$bridgeFiles = Get-ChildItem -LiteralPath (Join-Path $packageRoot 'lua') -Filter 'powang_y3_*.lua'
$directCalls = $bridgeFiles | Select-String -Pattern 'GameAPI\.|GlobalAPI\.|CAPI\.'
if ($directCalls) {
    $errors.Add('bridge contains forbidden direct engine API calls')
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) {
        Write-Error $message
    }
    exit 1
}

Write-Output "PASS: verified Powang Y3 bridge against y3-lualib $actualCommit"
Write-Output "  modules: $(@($baseline.modules.PSObject.Properties).Count)"
Write-Output "  events: $(@($baseline.events).Count)"
Write-Output "  direct engine calls: 0"
