[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

& (Join-Path $PSScriptRoot 'Test-ObjectFieldReservation.ps1')
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
