$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$powershell = Join-Path $PSHOME 'powershell.exe'
foreach ($scriptName in @('validate-surface-construction-manifest.ps1', 'test-surface-construction-manifest.ps1')) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    $output = & $powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $text -notmatch '^PASS: \d+ TianTing surface-construction-manifest') {
        throw "$scriptName failed: $text"
    }
    Write-Output $text
}

Write-Output 'PASS: TianTing surface-construction-manifest offline package.'
