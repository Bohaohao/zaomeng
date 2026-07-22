param(
    [switch]$EnvironmentOnly,
    [switch]$NodeTrustOnly
)

$ErrorActionPreference = 'Stop'

function Assert-CleanExecutionEnvironment {
    $forbidden = @('NODE_OPTIONS', 'NODE_PATH')
    foreach ($name in $forbidden) {
        if ($null -ne [Environment]::GetEnvironmentVariable($name, 'Process')) {
            throw "Untrusted Node environment variable is set: $name"
        }
    }
    $luaNames = @(
        [Environment]::GetEnvironmentVariables('Process').Keys |
            ForEach-Object { [string]$_ } |
            Where-Object { $_ -match '(?i)^LUA_' } |
            Sort-Object -Unique
    )
    if ($luaNames.Count -ne 0) {
        throw "Untrusted Lua environment variable is set: $($luaNames -join ', ')"
    }
}

function Resolve-TrustedNode {
    param([Parameter(Mandatory = $true)][string]$OriginalPath)

    $candidates = New-Object 'Collections.Generic.List[string]'
    foreach ($entry in $OriginalPath.Split([IO.Path]::PathSeparator)) {
        $directory = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim([char]'"'))
        if ([string]::IsNullOrWhiteSpace($directory)) { continue }
        $candidate = Join-Path $directory 'node.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $candidates.Add($candidate) }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        try {
            $path = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if ($item.PSIsContainer -or [IO.Path]::GetFileName($path) -ine 'node.exe' -or [IO.Path]::GetExtension($path) -ine '.exe') {
                continue
            }
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
            if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
                $subject -notmatch '(?i)(^|,\s*)(CN|O)=(OpenJS Foundation|Node\.js Foundation)(,|$)') {
                continue
            }
            $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
            if ($version.OriginalFilename -ine 'node.exe' -or $version.ProductName -ine 'Node.js' -or
                [string]$version.ProductVersion -cnotmatch '^\d+\.\d+\.\d+$') {
                continue
            }
            $runtimeVersion = 'v{0}.{1}.{2}' -f $version.FileMajorPart, $version.FileMinorPart, $version.FileBuildPart
            if ([string]$version.ProductVersion -cne $runtimeVersion.Substring(1)) { continue }
            return [pscustomobject]@{
                Path = $path
                Directory = Split-Path -Parent $path
                ProductVersion = [string]$version.ProductVersion
                RuntimeVersion = $runtimeVersion
                Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
            }
        }
        catch { continue }
    }
    throw 'No trusted signed OpenJS/Node.js node.exe was found on the original PATH.'
}

function Assert-TrustedNode {
    param([Parameter(Mandatory = $true)]$Node)

    Assert-CleanExecutionEnvironment
    $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Node.Path).Hash
    $currentVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($Node.Path)
    if ($currentHash -cne $Node.Sha256 -or [string]$currentVersion.ProductVersion -cne $Node.ProductVersion) {
        throw "Verified Node.js identity changed during execution: $($Node.Path)"
    }
    $resolved = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $resolved -or (Resolve-Path -LiteralPath $resolved.Source).Path -ine $Node.Path) {
        throw 'Controlled PATH no longer resolves the verified Node.js executable.'
    }
}

function Assert-PinnedNode {
    param([Parameter(Mandatory = $true)]$Node)

    # Archive reproducibility uses a signed *and* content-pinned Node binary.
    # A different signed Node release may be safe generally, but it is not the
    # frozen interpreter boundary that produced this offline acceptance proof.
    $expectedRuntimeVersion = 'v20.19.5'
    $expectedSha256 = 'E6FF5F7FEFA7A94FB97ED86A9578DCF65DF1BD5D0AB3117E6CB9B9C0BC74E17A'
    Assert-TrustedNode -Node $Node
    if ($Node.RuntimeVersion -cne $expectedRuntimeVersion -or $Node.Sha256 -cne $expectedSha256) {
        throw "Pinned Node.js identity mismatch: expected $expectedRuntimeVersion/$expectedSha256, found $($Node.RuntimeVersion)/$($Node.Sha256)"
    }
}

function Invoke-TrustedNode {
    param(
        [Parameter(Mandatory = $true)]$Node,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [AllowNull()][string]$StandardInput
    )

    Assert-TrustedNode -Node $Node
    if ($PSBoundParameters.ContainsKey('StandardInput')) {
        $output = $StandardInput | & $Node.Path @ArgumentList 2>&1
    }
    else {
        $output = & $Node.Path @ArgumentList 2>&1
    }
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

function Get-NodeModulesClosureHash {
    param(
        [Parameter(Mandatory = $true)]$Node,
        [Parameter(Mandatory = $true)][string]$NodeModulesRoot
    )

    $hasher = @'
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const root = path.resolve(process.argv[2]);
const rootStat = fs.lstatSync(root);
if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new Error("closure root must be physical");
const hash = crypto.createHash("sha256");
const activeDirectories = new Set();
const realpath = fs.realpathSync.native || fs.realpathSync;
const writeRecord = (kind, logicalPath, payload) => {
  hash.update(kind, "utf8"); hash.update("\0", "utf8");
  hash.update(logicalPath, "utf8"); hash.update("\0", "utf8");
  if (payload) hash.update(payload); hash.update("\n", "utf8");
};
function walkDirectory(physicalPath, logicalPath) {
  const resolved = realpath(physicalPath);
  const key = process.platform === "win32" ? resolved.toLowerCase() : resolved;
  if (activeDirectories.has(key)) throw new Error("reparse cycle");
  activeDirectories.add(key); writeRecord("D", logicalPath);
  const names = fs.readdirSync(resolved).sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
  for (const name of names) walk(path.join(resolved, name), logicalPath ? logicalPath + "/" + name : name);
  activeDirectories.delete(key);
}
function walk(physicalPath, logicalPath) {
  const stat = fs.lstatSync(physicalPath);
  if (stat.isSymbolicLink()) {
    writeRecord("L", logicalPath); const target = realpath(physicalPath); const targetStat = fs.statSync(physicalPath);
    if (targetStat.isDirectory()) return walkDirectory(target, logicalPath);
    if (targetStat.isFile()) { const content = fs.readFileSync(target); writeRecord("F", logicalPath, Buffer.concat([Buffer.from(String(content.length) + "\0"), content])); return; }
    throw new Error("unsupported reparse target");
  }
  if (stat.isDirectory()) return walkDirectory(physicalPath, logicalPath);
  if (stat.isFile()) { const content = fs.readFileSync(physicalPath); writeRecord("F", logicalPath, Buffer.concat([Buffer.from(String(content.length) + "\0"), content])); return; }
  throw new Error("unsupported closure entry");
}
walkDirectory(root, "");
process.stdout.write(hash.digest("hex").toUpperCase());
'@
    $result = Invoke-TrustedNode -Node $Node -ArgumentList @('-', $NodeModulesRoot) -StandardInput $hasher
    $hash = $result.Output -join ''
    if ($result.ExitCode -ne 0 -or $hash -cnotmatch '^[0-9A-F]{64}$') {
        throw "Unable to hash Fengari resolver closure: $hash"
    }
    return $hash
}

function Resolve-PinnedFengari {
    param([Parameter(Mandatory = $true)]$Node)

    $version = '0.1.0'
    $snapshot = '41ec8406e7a68140b8436c01df2bb294a02c6dc5111f463b8777f1ec3b7eef50'
    $expectedClosure = 'E8E88EFDB5BEFFE0F140BA72EDDCEC5E1B52D7788062A9FCF0E09F6988745AF4'
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is required for pinned Fengari.' }
    $store = Join-Path $env:LOCALAPPDATA 'pnpm\store'
    $suffix = '[\\/]' + [regex]::Escape('fengari-node-cli') + '[\\/]' + [regex]::Escape($version) +
        '[\\/]' + [regex]::Escape($snapshot) + '[\\/]node_modules[\\/]fengari-node-cli[\\/]src[\\/]lua-cli\.js$'
    $candidates = @(
        Get-ChildItem -LiteralPath $store -Recurse -File -Filter 'lua-cli.js' -ErrorAction Stop |
            Where-Object { $_.FullName -match $suffix } |
            Sort-Object -Property FullName |
            Select-Object -ExpandProperty FullName
    )
    if ($candidates.Count -ne 1) { throw "Expected exactly one pinned Fengari CLI, found $($candidates.Count)." }
    $cliPath = (Resolve-Path -LiteralPath $candidates[0]).Path
    $packageRoot = Split-Path -Parent (Split-Path -Parent $cliPath)
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $packageRoot 'package.json') | ConvertFrom-Json
    if ([string]$manifest.name -cne 'fengari-node-cli' -or [string]$manifest.version -cne $version) {
        throw 'Pinned Fengari package manifest identity mismatch.'
    }
    $nodeModulesRoot = Split-Path -Parent $packageRoot
    $closure = Get-NodeModulesClosureHash -Node $Node -NodeModulesRoot $nodeModulesRoot
    if ($closure -cne $expectedClosure) { throw "Pinned Fengari closure mismatch: $closure" }
    return [pscustomobject]@{
        CliPath = $cliPath
        CliSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $cliPath).Hash
        NodeModulesRoot = $nodeModulesRoot
        ClosureSha256 = $closure
    }
}

function Assert-PinnedFengari {
    param([Parameter(Mandatory = $true)]$Node, [Parameter(Mandatory = $true)]$Fengari)

    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Fengari.CliPath).Hash -cne $Fengari.CliSha256) {
        throw 'Pinned Fengari CLI changed during execution.'
    }
    if ((Get-NodeModulesClosureHash -Node $Node -NodeModulesRoot $Fengari.NodeModulesRoot) -cne $Fengari.ClosureSha256) {
        throw 'Pinned Fengari resolver closure changed during execution.'
    }
}

function Invoke-TideTraceFixtureClosureCheck {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$IsolationVerifier,
        [switch]$SkipIsolationScan
    )

    $closureTest = Join-Path $PackageRoot 'tests\test-tide-trace-fixture-closure.ps1'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $closureTest, '-PackageRoot', $PackageRoot, '-IsolationVerifier', $IsolationVerifier)
    if ($SkipIsolationScan) { $arguments += '-SkipIsolationScan' }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $PSHOME\powershell.exe @arguments 2>&1
        $succeeded = $?
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    if (-not $succeeded -or $text -notmatch '^PASS: \d+ economy-v2 Tide Trace fixture-closure assertions\s*$') {
        throw "Tide Trace fixture-closure acceptance failed: $text"
    }
}

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workspaceRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$originalPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
$originalPathExt = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')

try {
    Assert-CleanExecutionEnvironment
    if ($EnvironmentOnly) {
        Write-Output 'PASS: economy-v2 execution environment is clean.'
        return
    }
    $node = Resolve-TrustedNode -OriginalPath $originalPath
    $env:PATH = $node.Directory
    $env:PATHEXT = '.EXE'
    Assert-PinnedNode -Node $node
    if ($NodeTrustOnly) {
        Write-Output "PASS: economy-v2 trusted Node is $($node.Path)"
        return
    }
    $version = Invoke-TrustedNode -Node $node -ArgumentList @('--version')
    if ($version.ExitCode -ne 0 -or ($version.Output -join '').Trim() -cne $node.RuntimeVersion) {
        throw 'Signed Node executable runtime version does not match file metadata.'
    }
    $probe = @'
if (Object.prototype.hasOwnProperty.call(process.env, "NODE_OPTIONS") ||
    Object.prototype.hasOwnProperty.call(process.env, "NODE_PATH") ||
    Object.keys(process.env).some((name) => name.toUpperCase().startsWith("LUA_"))) {
  throw new Error("Node or Lua injection environment survived");
}
try { require("economy-v2-node-path-probe"); throw new Error("NODE_PATH changed resolution"); }
catch (error) { if (!error || error.code !== "MODULE_NOT_FOUND") throw error; }
'@
    $probeResult = Invoke-TrustedNode -Node $node -ArgumentList @('-') -StandardInput $probe
    if ($probeResult.ExitCode -ne 0 -or $probeResult.Output.Count -ne 0) {
        throw "Controlled Node environment probe failed: $($probeResult.Output -join [Environment]::NewLine)"
    }

    Push-Location $workspaceRoot
    try {
        $boundaryTest = Join-Path $packageRoot 'tests\test-execution-boundary.ps1'
        $boundaryOutput = & $PSHOME\powershell.exe -NoProfile -ExecutionPolicy Bypass -File $boundaryTest 2>&1
        $boundaryText = ($boundaryOutput | ForEach-Object { [string]$_ }) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $boundaryText -notmatch '^PASS: \d+ economy-v2 execution-boundary assertions\s*$') {
            throw "Execution-boundary acceptance failed: $boundaryText"
        }

        $apiVerifier = Join-Path $workspaceRoot 'implementation\huaguoshan\tests\verify-y3-api.ps1'
        Invoke-TideTraceFixtureClosureCheck -PackageRoot $packageRoot -IsolationVerifier $apiVerifier
        & $apiVerifier -PackageRoot $packageRoot

        $compilerTest = Join-Path $packageRoot 'tests\test-compiler.ps1'
        $compilerOutput = & $PSHOME\powershell.exe -NoProfile -ExecutionPolicy Bypass -File $compilerTest 2>&1
        if ($LASTEXITCODE -ne 0 -or (($compilerOutput | ForEach-Object { [string]$_ }) -join "`n") -notmatch '^economy-v2 compiler tests: PASS\s*$') {
            throw "Compiler acceptance failed: $($compilerOutput -join [Environment]::NewLine)"
        }

        $storeSafety = Invoke-TrustedNode -Node $node -ArgumentList @((Join-Path $packageRoot 'tests\test-store-safety.js'))
        $storeSafetyText = ($storeSafety.Output | ForEach-Object { [string]$_ }) -join "`n"
        if ($storeSafety.ExitCode -ne 0 -or $storeSafetyText -notmatch '^PASS: \d+ economy-v2 transaction-store safety assertions\s*$') {
            throw "Transaction-store safety acceptance failed: $storeSafetyText"
        }

        foreach ($script in @(
            (Join-Path $packageRoot 'reference\transaction-store-model.js'),
            (Join-Path $packageRoot 'reference\settlement-materializer.js'),
            (Join-Path $packageRoot 'reference\compile-economy-v2.js'),
            (Join-Path $packageRoot 'tests\test-store-safety.js'),
            (Join-Path $packageRoot 'tests\test-settlement.js'),
            (Join-Path $packageRoot 'tests\test-tianting-authority-handoff.js')
        )) {
            $check = Invoke-TrustedNode -Node $node -ArgumentList @('--check', $script)
            if ($check.ExitCode -ne 0 -or $check.Output.Count -ne 0) { throw "Node syntax check failed for ${script}: $($check.Output -join [Environment]::NewLine)" }
        }
        $fengari = Resolve-PinnedFengari -Node $node
        $intentEmitter = Join-Path $packageRoot 'tests\emit_tide_trace_intent.lua'
        $intentOutput = Join-Path $packageRoot ('tests\.tide-intent-' + [Guid]::NewGuid().ToString('N') + '.json')
        try {
            Invoke-TideTraceFixtureClosureCheck -PackageRoot $packageRoot -IsolationVerifier $apiVerifier -SkipIsolationScan
            Assert-PinnedFengari -Node $node -Fengari $fengari
            $emittedIntent = Invoke-TrustedNode -Node $node -ArgumentList @($fengari.CliPath, '-E', $intentEmitter)
            Assert-PinnedFengari -Node $node -Fengari $fengari
            Invoke-TideTraceFixtureClosureCheck -PackageRoot $packageRoot -IsolationVerifier $apiVerifier -SkipIsolationScan
            $intentText = ($emittedIntent.Output -join "`n").Trim()
            if ($emittedIntent.ExitCode -ne 0) { throw "Tide Trace intent emission failed: $intentText" }
            try { $intentText | ConvertFrom-Json | Out-Null } catch { throw "Tide Trace intent emission is not JSON: $intentText" }
            [IO.File]::WriteAllText($intentOutput, $intentText + "`n", (New-Object Text.UTF8Encoding($false)))
            $settlement = Invoke-TrustedNode -Node $node -ArgumentList @((Join-Path $packageRoot 'tests\test-settlement.js'), $intentOutput)
            $settlementText = ($settlement.Output -join "`n").Trim()
            if ($settlement.ExitCode -ne 0 -or $settlementText -notmatch '^PASS: \d+ economy-v2 settlement assertions$') {
                throw "Settlement acceptance failed: $settlementText"
            }
            $tiantingHandoff = Invoke-TrustedNode -Node $node -ArgumentList @((Join-Path $packageRoot 'tests\test-tianting-authority-handoff.js'))
            $tiantingHandoffText = ($tiantingHandoff.Output -join "`n").Trim()
            if ($tiantingHandoff.ExitCode -ne 0 -or $tiantingHandoffText -notmatch '^PASS: \d+ economy-v2 TianTing authority-handoff assertions$') {
                throw "TianTing authority-handoff acceptance failed: $tiantingHandoffText"
            }
        }
        finally {
            Remove-Item -LiteralPath $intentOutput -Force -ErrorAction SilentlyContinue
        }

        $luaTest = Join-Path $packageRoot 'tests\test_tide_trace_adapter.lua'
        $luaHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $luaTest).Hash
        Invoke-TideTraceFixtureClosureCheck -PackageRoot $packageRoot -IsolationVerifier $apiVerifier -SkipIsolationScan
        Assert-PinnedFengari -Node $node -Fengari $fengari
        $lua = Invoke-TrustedNode -Node $node -ArgumentList @($fengari.CliPath, '-E', $luaTest)
        Assert-PinnedFengari -Node $node -Fengari $fengari
        Invoke-TideTraceFixtureClosureCheck -PackageRoot $packageRoot -IsolationVerifier $apiVerifier -SkipIsolationScan
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $luaTest).Hash -cne $luaHash) { throw 'Tide Trace Lua test changed during execution.' }
        $luaText = ($lua.Output -join "`n").Trim()
        if ($lua.ExitCode -ne 0 -or $luaText -notmatch '^PASS: \d+ economy-v2 Tide Trace adapter assertions$') {
            throw "Tide Trace adapter acceptance failed: $luaText"
        }
        Write-Output "PASS: economy-v2 offline acceptance package ($settlementText; $tiantingHandoffText; $luaText)"
    }
    finally {
        Pop-Location
    }
}
finally {
    [Environment]::SetEnvironmentVariable('PATH', $originalPath, 'Process')
    [Environment]::SetEnvironmentVariable('PATHEXT', $originalPathExt, 'Process')
}
