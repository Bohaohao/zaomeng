$ErrorActionPreference = 'Stop'

$runnerPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'run-all.ps1')).Path
$windowsPowerShellCandidate = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
$powershellPath = (Resolve-Path -LiteralPath $windowsPowerShellCandidate -ErrorAction Stop).Path
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('huaguoshan-runner-node-environment-' + [guid]::NewGuid().ToString('N'))
$preloadMarkerPath = Join-Path $fixtureRoot 'node-options-preload.marker'
$nodePathMarkerPath = Join-Path $fixtureRoot 'node-path-resolution.marker'
$preloadPath = Join-Path $fixtureRoot 'preload.js'
$nodePathRoot = Join-Path $fixtureRoot 'node-path'
$nodePathPackageRoot = Join-Path $nodePathRoot 'huaguoshan-runner-node-path-probe'
$unsupportedHostDirectory = Join-Path $fixtureRoot 'unsupported-host'
$unsupportedPwshPath = Join-Path $unsupportedHostDirectory 'pwsh.exe'
$originalNodeOptions = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'Process')
$originalNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
$originalPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')

$runnerTokens = $null
$runnerParseErrors = $null
$runnerAst = [Management.Automation.Language.Parser]::ParseFile(
    $runnerPath,
    [ref]$runnerTokens,
    [ref]$runnerParseErrors
)
if (@($runnerParseErrors).Count -ne 0) {
    throw "run-all.ps1 contains parse errors: $(@($runnerParseErrors | ForEach-Object { $_.Message }) -join '; ')"
}

$hostValidatorAsts = @($runnerAst.FindAll({
    param($ast)
    ($ast -is [Management.Automation.Language.FunctionDefinitionAst]) -and
        $ast.Name -ceq 'Resolve-SupportedWindowsPowerShellPath'
}, $true))
if ($hostValidatorAsts.Count -ne 1) {
    throw 'run-all.ps1 must define exactly one supported Windows PowerShell host validator.'
}
. ([scriptblock]::Create($hostValidatorAsts[0].Extent.Text))

$hostGateInvocations = @($runnerAst.FindAll({
    param($ast)
    ($ast -is [Management.Automation.Language.CommandAst]) -and
        $ast.GetCommandName() -ceq 'Resolve-SupportedWindowsPowerShellPath'
}, $true))
$nodeProbeInvocations = @($runnerAst.FindAll({
    param($ast)
    ($ast -is [Management.Automation.Language.CommandAst]) -and
        $ast.GetCommandName() -ceq 'Get-Command' -and
        $ast.Extent.Text -cmatch '\bnode\.exe\b'
}, $true) | Sort-Object { $_.Extent.StartOffset })
$childTestInvocations = @($runnerAst.FindAll({
    param($ast)
    ($ast -is [Management.Automation.Language.CommandAst]) -and
        $ast.GetCommandName() -ceq 'Invoke-RunnerPowerShellTest'
}, $true) | Sort-Object { $_.Extent.StartOffset })
if ($hostGateInvocations.Count -ne 1 -or
    $nodeProbeInvocations.Count -eq 0 -or
    $childTestInvocations.Count -eq 0 -or
    $hostGateInvocations[0].Extent.StartOffset -ge $nodeProbeInvocations[0].Extent.StartOffset -or
    $hostGateInvocations[0].Extent.StartOffset -ge $childTestInvocations[0].Extent.StartOffset) {
    throw 'The supported-host gate must execute before Node discovery and every child test.'
}

$barePowerShellInvocations = @($runnerAst.FindAll({
    param($ast)
    if ($ast -isnot [Management.Automation.Language.CommandAst]) { return $false }
    $commandName = $ast.GetCommandName()
    return $commandName -ieq 'powershell' -or $commandName -ieq 'powershell.exe'
}, $true))
if ($barePowerShellInvocations.Count -ne 0) {
    throw 'run-all.ps1 must invoke its validated absolute host path, not powershell from PATH.'
}

try {
    New-Item -ItemType Directory -Path $nodePathPackageRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $unsupportedHostDirectory -Force | Out-Null
    Set-Content -LiteralPath $unsupportedPwshPath -Encoding ASCII -Value ''

    $validatedPowerShellPath = Resolve-SupportedWindowsPowerShellPath `
        -HostPath $powershellPath `
        -PowerShellEdition 'Desktop'
    if ($validatedPowerShellPath -ine $powershellPath) {
        throw "Supported-host gate returned an unexpected Windows PowerShell path: $validatedPowerShellPath"
    }

    $unsupportedEditionMessage = $null
    try {
        Resolve-SupportedWindowsPowerShellPath `
            -HostPath $unsupportedPwshPath `
            -PowerShellEdition 'Core' | Out-Null
    }
    catch {
        $unsupportedEditionMessage = $_.Exception.Message
    }
    if ($unsupportedEditionMessage -cne 'Huaguoshan offline runner supports only Windows PowerShell powershell.exe. Current edition: Core') {
        throw "Unsupported pwsh edition did not fail deterministically: $unsupportedEditionMessage"
    }

    $unsupportedHostMessage = $null
    try {
        Resolve-SupportedWindowsPowerShellPath `
            -HostPath $unsupportedPwshPath `
            -PowerShellEdition 'Desktop' | Out-Null
    }
    catch {
        $unsupportedHostMessage = $_.Exception.Message
    }
    $expectedUnsupportedHostMessage = "Huaguoshan offline runner supports only Windows PowerShell powershell.exe. Current host: $unsupportedPwshPath"
    if ($unsupportedHostMessage -cne $expectedUnsupportedHostMessage) {
        throw "A host named pwsh.exe was not rejected deterministically: $unsupportedHostMessage"
    }

    $preloadMarkerLiteral = ConvertTo-Json -InputObject $preloadMarkerPath -Compress
    $nodePathMarkerLiteral = ConvertTo-Json -InputObject $nodePathMarkerPath -Compress
    Set-Content -LiteralPath $preloadPath -Encoding UTF8 -Value (
        "require('fs').writeFileSync($preloadMarkerLiteral, 'NODE_OPTIONS preload executed');"
    )
    Set-Content -LiteralPath (Join-Path $nodePathPackageRoot 'index.js') -Encoding UTF8 -Value (
        "require('fs').writeFileSync($nodePathMarkerLiteral, 'NODE_PATH module resolved'); module.exports = true;"
    )

    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', ('--require "' + $preloadPath + '"'), 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $nodePathRoot, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', '.COM;.BAT;.CMD', 'Process')

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershellPath
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -NodeIntegritySelfTestOnly' -f $runnerPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'Unable to start the runner Node integrity self-test process.'
        }
        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $standardOutput = $standardOutputTask.Result
        $standardError = $standardErrorTask.Result
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }
    $outputLines = @(
        @($standardOutput, $standardError) |
            ForEach-Object { ([string]$_) -split '\r?\n' } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if (Test-Path -LiteralPath $preloadMarkerPath) {
        throw 'NODE_OPTIONS preload executed before the runner established its controlled Node environment.'
    }
    if (Test-Path -LiteralPath $nodePathMarkerPath) {
        throw 'NODE_PATH changed module resolution inside the runner controlled Node environment.'
    }
    if ($exitCode -ne 0) {
        throw "Runner Node integrity self-test failed with exit code $exitCode`: $($outputLines -join [Environment]::NewLine)"
    }
    if ($outputLines.Count -ne 1 -or
        $outputLines[0] -cne 'PASS: controlled Node subprocess environment rejects NODE_OPTIONS and NODE_PATH injection.') {
        throw "Runner Node integrity self-test returned unexpected output: $($outputLines -join [Environment]::NewLine)"
    }
}
finally {
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $originalNodeOptions, 'Process')
    [Environment]::SetEnvironmentVariable('NODE_PATH', $originalNodePath, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', $originalPathExt, 'Process')
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

Write-Output 'PASS: run-all rejects pwsh before Node discovery and child tests and pins powershell.exe by absolute path.'
Write-Output 'PASS: run-all resolves node.exe without PATHEXT .EXE and blocks NODE_OPTIONS/NODE_PATH injection.'
