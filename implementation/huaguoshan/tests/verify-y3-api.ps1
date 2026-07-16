param(
    [string]$Y3LuaApiRoot = (Join-Path $env:USERPROFILE '.codex\skills\y3-lua-api'),
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaselinePath
)

$ErrorActionPreference = 'Stop'

function Get-LuaLongBracketStart {
    param(
        [string]$Source,
        [int]$Index
    )

    if ($Index -ge $Source.Length -or $Source[$Index] -ne '[') { return $null }
    $cursor = $Index + 1
    while ($cursor -lt $Source.Length -and $Source[$cursor] -eq '=') { $cursor++ }
    if ($cursor -ge $Source.Length -or $Source[$cursor] -ne '[') { return $null }

    return [pscustomobject]@{
        EqualsCount = $cursor - $Index - 1
        ContentStart = $cursor + 1
    }
}

function Move-LuaCursor {
    param(
        [string]$Source,
        [int]$Target,
        [ref]$Index,
        [ref]$Line,
        [ref]$Column
    )

    $currentIndex = [int]$Index.Value
    $currentLine = [int]$Line.Value
    $currentColumn = [int]$Column.Value
    while ($currentIndex -lt $Target) {
        if ($Source[$currentIndex] -eq "`n") {
            $currentLine++
            $currentColumn = 1
        }
        else {
            $currentColumn++
        }
        $currentIndex++
    }
    $Index.Value = $currentIndex
    $Line.Value = $currentLine
    $Column.Value = $currentColumn
}

function Test-LuaIdentifierStart {
    param([char]$Character)
    $code = [int]$Character
    return $Character -eq '_' -or ($code -ge 65 -and $code -le 90) -or ($code -ge 97 -and $code -le 122)
}

function Test-LuaIdentifierPart {
    param([char]$Character)
    $code = [int]$Character
    return (Test-LuaIdentifierStart $Character) -or ($code -ge 48 -and $code -le 57)
}

function Get-LuaTokens {
    param([string]$Source)

    $Source = $Source.Replace("`r`n", "`n").Replace("`r", "`n")
    $tokens = [System.Collections.Generic.List[object]]::new()
    $index = 0
    $line = 1
    $column = 1

    while ($index -lt $Source.Length) {
        $character = $Source[$index]

        if ([char]::IsWhiteSpace($character)) {
            Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
            continue
        }

        if ($character -eq '-' -and $index + 1 -lt $Source.Length -and $Source[$index + 1] -eq '-') {
            Move-LuaCursor -Source $Source -Target ($index + 2) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
            $longComment = Get-LuaLongBracketStart -Source $Source -Index $index
            if ($null -ne $longComment) {
                $closingDelimiter = ']' + ('=' * $longComment.EqualsCount) + ']'
                $closingIndex = $Source.IndexOf($closingDelimiter, $longComment.ContentStart, [StringComparison]::Ordinal)
                $target = if ($closingIndex -lt 0) { $Source.Length } else { $closingIndex + $closingDelimiter.Length }
                Move-LuaCursor -Source $Source -Target $target -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
            }
            else {
                $newlineIndex = $Source.IndexOf("`n", $index, [StringComparison]::Ordinal)
                $target = if ($newlineIndex -lt 0) { $Source.Length } else { $newlineIndex }
                Move-LuaCursor -Source $Source -Target $target -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
            }
            continue
        }

        if ($character -eq "'" -or $character -eq '"') {
            $tokenLine = $line
            $tokenColumn = $column
            $quote = $character
            $value = [System.Text.StringBuilder]::new()
            Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)

            while ($index -lt $Source.Length) {
                $stringCharacter = $Source[$index]
                if ($stringCharacter -eq $quote) {
                    Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                    break
                }
                if ($stringCharacter -ne '\') {
                    [void]$value.Append($stringCharacter)
                    Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                    continue
                }

                Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                if ($index -ge $Source.Length) { break }
                $escape = $Source[$index]
                switch ($escape) {
                    'a' { [void]$value.Append([char]7); Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column) }
                    'b' { [void]$value.Append([char]8); Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column) }
                    'f' { [void]$value.Append([char]12); Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column) }
                    'n' { [void]$value.Append("`n"); Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column) }
                    'r' { [void]$value.Append("`r"); Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column) }
                    't' { [void]$value.Append("`t"); Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column) }
                    'v' { [void]$value.Append([char]11); Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column) }
                    'z' {
                        Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                        while ($index -lt $Source.Length -and [char]::IsWhiteSpace($Source[$index])) {
                            Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                        }
                    }
                    'x' {
                        if ($index + 2 -lt $Source.Length -and $Source.Substring($index + 1, 2) -match '^[0-9A-Fa-f]{2}$') {
                            [void]$value.Append([char][Convert]::ToInt32($Source.Substring($index + 1, 2), 16))
                            Move-LuaCursor -Source $Source -Target ($index + 3) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                        }
                        else {
                            [void]$value.Append($escape)
                            Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                        }
                    }
                    'u' {
                        $unicodeMatch = [regex]::Match($Source.Substring($index), '^u\{([0-9A-Fa-f]+)\}')
                        if ($unicodeMatch.Success) {
                            [void]$value.Append([char]::ConvertFromUtf32([Convert]::ToInt32($unicodeMatch.Groups[1].Value, 16)))
                            Move-LuaCursor -Source $Source -Target ($index + $unicodeMatch.Length) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                        }
                        else {
                            [void]$value.Append($escape)
                            Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                        }
                    }
                    "`n" {
                        [void]$value.Append("`n")
                        Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                    }
                    default {
                        if ($escape -ge '0' -and $escape -le '9') {
                            $digitStart = $index
                            $digitCount = 0
                            while ($digitCount -lt 3 -and $index + $digitCount -lt $Source.Length) {
                                $digit = $Source[$index + $digitCount]
                                if ($digit -lt '0' -or $digit -gt '9') { break }
                                $digitCount++
                            }
                            [void]$value.Append([char][Convert]::ToInt32($Source.Substring($digitStart, $digitCount), 10))
                            Move-LuaCursor -Source $Source -Target ($index + $digitCount) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                        }
                        else {
                            [void]$value.Append($escape)
                            Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                        }
                    }
                }
            }

            $tokens.Add([pscustomobject]@{ Kind = 'String'; StringKind = 'Quoted'; Value = $value.ToString(); Line = $tokenLine; Column = $tokenColumn })
            continue
        }

        if ($character -eq '[') {
            $longString = Get-LuaLongBracketStart -Source $Source -Index $index
            if ($null -ne $longString) {
                $tokenLine = $line
                $tokenColumn = $column
                $closingDelimiter = ']' + ('=' * $longString.EqualsCount) + ']'
                $closingIndex = $Source.IndexOf($closingDelimiter, $longString.ContentStart, [StringComparison]::Ordinal)
                if ($closingIndex -lt 0) {
                    $stringValue = $Source.Substring($longString.ContentStart)
                    $target = $Source.Length
                }
                else {
                    $stringValue = $Source.Substring($longString.ContentStart, $closingIndex - $longString.ContentStart)
                    $target = $closingIndex + $closingDelimiter.Length
                }
                if ($stringValue.StartsWith("`n", [StringComparison]::Ordinal)) { $stringValue = $stringValue.Substring(1) }
                $tokens.Add([pscustomobject]@{ Kind = 'String'; StringKind = 'Long'; Value = $stringValue; Line = $tokenLine; Column = $tokenColumn })
                Move-LuaCursor -Source $Source -Target $target -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
                continue
            }
        }

        if (Test-LuaIdentifierStart $character) {
            $tokenLine = $line
            $tokenColumn = $column
            $start = $index
            Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
            while ($index -lt $Source.Length -and (Test-LuaIdentifierPart $Source[$index])) {
                Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
            }
            $tokens.Add([pscustomobject]@{ Kind = 'Identifier'; Value = $Source.Substring($start, $index - $start); Line = $tokenLine; Column = $tokenColumn })
            continue
        }

        $tokens.Add([pscustomobject]@{ Kind = 'Symbol'; Value = [string]$character; Line = $line; Column = $column })
        Move-LuaCursor -Source $Source -Target ($index + 1) -Index ([ref]$index) -Line ([ref]$line) -Column ([ref]$column)
    }

    return $tokens
}

function Test-LuaTokenCanEndExpression {
    param([object]$Token)

    if ($null -eq $Token) { return $false }
    if ($Token.Kind -eq 'Identifier' -or $Token.Kind -eq 'String') { return $true }
    return $Token.Kind -eq 'Symbol' -and $Token.Value -in @(')', ']', '}')
}

function Read-OfflineApiMetadata {
    param(
        [string]$Path,
        [string]$Label,
        [System.Collections.Generic.List[string]]$Errors
    )

    try {
        $metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
        Write-Output -NoEnumerate $metadata
    }
    catch {
        [void]$Errors.Add("$Label is not valid JSON: $($_.Exception.Message)")
    }
}

function Test-OfflineApiMetadataSchema {
    param(
        [object]$Metadata,
        [string]$Label,
        [System.Collections.Generic.List[string]]$Errors
    )

    if ($null -eq $Metadata -or $Metadata -isnot [pscustomobject]) {
        [void]$Errors.Add("$Label must be a JSON object")
        return $false
    }

    $valid = $true
    $schemaVersionProperty = $Metadata.PSObject.Properties['schema_version']
    $schemaVersion = if ($null -ne $schemaVersionProperty) { $schemaVersionProperty.Value } else { $null }
    $schemaVersionIsInteger = ($schemaVersion -is [int]) -or ($schemaVersion -is [long])
    if (-not $schemaVersionIsInteger -or $schemaVersion -ne 1) {
        [void]$Errors.Add("$Label schema_version must be the integer 1")
        $valid = $false
    }

    foreach ($field in @('status', 'repository', 'branch', 'commit', 'refreshed_on', 'scope')) {
        $property = $Metadata.PSObject.Properties[$field]
        if ($null -eq $property -or $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            [void]$Errors.Add("$Label must define required non-empty string field '$field'")
            $valid = $false
        }
    }

    foreach ($field in @('compatibility_baseline_available', 'real_map_script_root_integrated')) {
        $property = $Metadata.PSObject.Properties[$field]
        if ($null -eq $property -or $property.Value -isnot [bool]) {
            [void]$Errors.Add("$Label field '$field' must be a boolean")
            $valid = $false
        }
    }

    $modulesProperty = $Metadata.PSObject.Properties['modules']
    if ($null -eq $modulesProperty -or $modulesProperty.Value -isnot [pscustomobject]) {
        [void]$Errors.Add("$Label must define a modules object")
        $valid = $false
    }
    else {
        foreach ($module in @($modulesProperty.Value.PSObject.Properties)) {
            if ([string]::IsNullOrWhiteSpace([string]$module.Name) -or $module.Value -isnot [object[]]) {
                [void]$Errors.Add("$Label module '$($module.Name)' must be a non-empty name mapped to an array")
                $valid = $false
                continue
            }
            if (@($module.Value).Count -eq 0) {
                [void]$Errors.Add("$Label module '$($module.Name)' must list at least one non-empty string method name")
                $valid = $false
                continue
            }
            foreach ($method in @($module.Value)) {
                if ($method -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$method)) {
                    [void]$Errors.Add("$Label module '$($module.Name)' must contain only non-empty string method names")
                    $valid = $false
                }
            }
        }
    }

    $eventsProperty = $Metadata.PSObject.Properties['events']
    if ($null -eq $eventsProperty -or $eventsProperty.Value -isnot [object[]]) {
        [void]$Errors.Add("$Label must define an events array")
        $valid = $false
    }
    else {
        foreach ($eventName in @($eventsProperty.Value)) {
            if ($eventName -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$eventName)) {
                [void]$Errors.Add("$Label events must contain only non-empty strings")
                $valid = $false
            }
        }
    }

    return $valid
}

function Assert-PackageCandidateDoesNotTraverseReparsePoint {
    param(
        [string]$PackageRoot,
        [string]$CandidatePath,
        [string]$Label
    )

    $packageRootFull = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\', '/')
    $candidateFull = [IO.Path]::GetFullPath($CandidatePath)
    $packagePrefix = $packageRootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $candidateFull.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must remain under the package root"
    }

    $relativePath = $candidateFull.Substring($packagePrefix.Length)
    $currentPath = $packageRootFull
    foreach ($segment in $relativePath.Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $currentPath = Join-Path $currentPath $segment
        $item = Get-Item -Force -LiteralPath $currentPath
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label must not traverse a reparse point: $currentPath"
        }
    }
}

function ConvertTo-CanonicalJsonText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (ConvertTo-Json -InputObject $Value -Compress) }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [object[]]) {
        $items = @($Value | ForEach-Object { ConvertTo-CanonicalJsonText -Value $_ })
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [pscustomobject]) {
        $members = @($Value.PSObject.Properties |
            Sort-Object -Property Name |
            ForEach-Object {
                (ConvertTo-Json -InputObject ([string]$_.Name) -Compress) + ':' +
                    (ConvertTo-CanonicalJsonText -Value $_.Value)
            })
        return '{' + ($members -join ',') + '}'
    }
    if ($Value -is [System.IFormattable]) {
        return $Value.ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    return (ConvertTo-Json -InputObject $Value -Compress)
}

function Get-ForbiddenLuaEngineReferences {
    param(
        [string]$Path,
        [System.Collections.Generic.HashSet[string]]$AllowedModules
    )

    $restrictedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in @('y3', 'GameAPI', 'GlobalAPI', 'CAPI')) { [void]$restrictedNames.Add($name) }
    $globalEnvironmentNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in @('_G', '_ENV')) { [void]$globalEnvironmentNames.Add($name) }
    $environmentAccessNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in @('debug', 'getfenv', 'setfenv', 'package', 'os', 'io', 'ffi', 'jit')) {
        [void]$environmentAccessNames.Add($name)
    }
    $dynamicLoaderNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in @('load', 'loadfile', 'dofile', 'loadstring', 'module')) { [void]$dynamicLoaderNames.Add($name) }
    $restrictedIndexNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($nameSet in @($restrictedNames, $globalEnvironmentNames, $environmentAccessNames, $dynamicLoaderNames)) {
        foreach ($name in $nameSet) { [void]$restrictedIndexNames.Add($name) }
    }
    [void]$restrictedIndexNames.Add('require')

    $source = [string](Get-Content -Raw -Encoding UTF8 -LiteralPath $Path)
    $tokens = @(Get-LuaTokens -Source $source)
    $references = [System.Collections.Generic.List[object]]::new()
    $coveredTokenIndexes = [System.Collections.Generic.HashSet[int]]::new()

    for ($tokenIndex = 0; $tokenIndex -lt $tokens.Count; $tokenIndex++) {
        $token = $tokens[$tokenIndex]
        if ($token.Kind -eq 'Identifier' -and $globalEnvironmentNames.Contains([string]$token.Value)) {
            # The offline package must not access the global environment at all.
            # This closes indirect engine lookups such as rawget(_G, 'GameAPI').
            $references.Add([pscustomobject]@{ Path = $Path; Line = $token.Line; Column = $token.Column; Display = $token.Value })
            if ($tokenIndex + 2 -lt $tokens.Count -and $tokens[$tokenIndex + 1].Kind -eq 'Symbol' -and $tokens[$tokenIndex + 1].Value -eq '.' -and
                $tokens[$tokenIndex + 2].Kind -eq 'Identifier' -and $restrictedNames.Contains([string]$tokens[$tokenIndex + 2].Value)) {
                [void]$coveredTokenIndexes.Add($tokenIndex + 2)
            }
            elseif ($tokenIndex + 3 -lt $tokens.Count -and $tokens[$tokenIndex + 1].Kind -eq 'Symbol' -and $tokens[$tokenIndex + 1].Value -eq '[' -and
                $tokens[$tokenIndex + 2].Kind -eq 'String' -and $restrictedNames.Contains([string]$tokens[$tokenIndex + 2].Value) -and
                $tokens[$tokenIndex + 3].Kind -eq 'Symbol' -and $tokens[$tokenIndex + 3].Value -eq ']') {
            }
        }

        if ($token.Kind -eq 'Identifier' -and $dynamicLoaderNames.Contains([string]$token.Value)) {
            $references.Add([pscustomobject]@{ Path = $Path; Line = $token.Line; Column = $token.Column; Display = $token.Value })
        }

        if ($token.Kind -eq 'Identifier' -and $environmentAccessNames.Contains([string]$token.Value)) {
            $references.Add([pscustomobject]@{ Path = $Path; Line = $token.Line; Column = $token.Column; Display = $token.Value })
        }

        if ($token.Kind -eq 'Symbol' -and $token.Value -eq '[' -and
            $tokenIndex -gt 0 -and $tokenIndex + 2 -lt $tokens.Count -and
            (Test-LuaTokenCanEndExpression -Token $tokens[$tokenIndex - 1]) -and
            $tokens[$tokenIndex + 1].Kind -eq 'String' -and
            $restrictedIndexNames.Contains([string]$tokens[$tokenIndex + 1].Value) -and
            $tokens[$tokenIndex + 2].Kind -eq 'Symbol' -and $tokens[$tokenIndex + 2].Value -eq ']') {
            $indexedName = [string]$tokens[$tokenIndex + 1].Value
            $references.Add([pscustomobject]@{
                Path = $Path
                Line = $tokens[$tokenIndex + 1].Line
                Column = $tokens[$tokenIndex + 1].Column
                Display = 'index:' + $indexedName
            })
        }

        if ($token.Kind -eq 'Identifier' -and $token.Value -eq 'require') {
            $previousToken = if ($tokenIndex -gt 0) { $tokens[$tokenIndex - 1] } else { $null }
            $isQualified = $null -ne $previousToken -and
                $previousToken.Kind -eq 'Symbol' -and $previousToken.Value -in @('.', ':')
            if ($isQualified) {
                $references.Add([pscustomobject]@{ Path = $Path; Line = $token.Line; Column = $token.Column; Display = 'require(qualified)' })
                continue
            }

            $argumentIndex = $tokenIndex + 1
            $parenthesized = $false
            if ($argumentIndex -lt $tokens.Count -and $tokens[$argumentIndex].Kind -eq 'Symbol' -and $tokens[$argumentIndex].Value -eq '(') {
                $parenthesized = $true
                $argumentIndex++
            }
            $argument = if ($argumentIndex -lt $tokens.Count) { $tokens[$argumentIndex] } else { $null }
            $isStaticLiteral = $null -ne $argument -and
                $argument.Kind -eq 'String' -and $argument.StringKind -eq 'Quoted'
            if ($isStaticLiteral -and $parenthesized) {
                $closingIndex = $argumentIndex + 1
                $isStaticLiteral = $closingIndex -lt $tokens.Count -and
                    $tokens[$closingIndex].Kind -eq 'Symbol' -and $tokens[$closingIndex].Value -eq ')'
            }
            if (-not $isStaticLiteral) {
                $references.Add([pscustomobject]@{ Path = $Path; Line = $token.Line; Column = $token.Column; Display = 'require(dynamic)' })
            }
            elseif ($null -eq $AllowedModules -or -not $AllowedModules.Contains([string]$argument.Value)) {
                $references.Add([pscustomobject]@{ Path = $Path; Line = $argument.Line; Column = $argument.Column; Display = 'require:' + [string]$argument.Value })
            }
        }

        if ($token.Kind -eq 'Identifier' -and $restrictedNames.Contains([string]$token.Value) -and -not $coveredTokenIndexes.Contains($tokenIndex)) {
            $references.Add([pscustomobject]@{ Path = $Path; Line = $token.Line; Column = $token.Column; Display = $token.Value })
        }
    }

    return $references
}

$packageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$errors = [System.Collections.Generic.List[string]]::new()
$authoritativeBaselineCandidate = [IO.Path]::GetFullPath((Join-Path $packageRoot 'tests\y3-api-baseline.json'))
$fallbackBaselineCandidate = [IO.Path]::GetFullPath((Join-Path $packageRoot 'y3-api-baseline.json'))
$baselineCandidates = @(
    $authoritativeBaselineCandidate,
    $fallbackBaselineCandidate
)

if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $resolvedBaselinePath = $baselineCandidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}
else {
    $baselineCandidate = $BaselinePath
    if (-not [IO.Path]::IsPathRooted($baselineCandidate)) {
        $baselineCandidate = Join-Path $packageRoot $baselineCandidate
    }
    $baselineCandidate = [IO.Path]::GetFullPath($baselineCandidate)
    $selectedPackageCandidate = @($baselineCandidates | Where-Object { $_ -ieq $baselineCandidate }) | Select-Object -First 1
    if (-not $selectedPackageCandidate) {
        throw 'BaselinePath must select the package-authoritative or package-root fallback metadata'
    }
    $resolvedBaselinePath = $selectedPackageCandidate
}
if (-not $resolvedBaselinePath -or -not (Test-Path -LiteralPath $resolvedBaselinePath -PathType Leaf)) {
    throw "offline API isolation metadata not found under package root: $packageRoot"
}
Assert-PackageCandidateDoesNotTraverseReparsePoint -PackageRoot $packageRoot -CandidatePath $resolvedBaselinePath -Label 'selected offline API isolation metadata'
$resolvedBaselinePath = (Resolve-Path -LiteralPath $resolvedBaselinePath).Path
$baseline = Read-OfflineApiMetadata -Path $resolvedBaselinePath -Label 'offline API isolation metadata' -Errors $errors
$baselineSchemaValid = $false
if ($null -ne $baseline) {
    $baselineSchemaValid = Test-OfflineApiMetadataSchema -Metadata $baseline -Label 'offline API isolation metadata' -Errors $errors
}

$authoritativeBaseline = $null
$authoritativeSchemaValid = $false
$resolvedAuthoritativeBaselinePath = $null
if (Test-Path -LiteralPath $authoritativeBaselineCandidate -PathType Leaf) {
    Assert-PackageCandidateDoesNotTraverseReparsePoint -PackageRoot $packageRoot -CandidatePath $authoritativeBaselineCandidate -Label 'authoritative tests metadata'
    $resolvedAuthoritativeBaselinePath = (Resolve-Path -LiteralPath $authoritativeBaselineCandidate).Path
    if ($resolvedAuthoritativeBaselinePath -ieq $resolvedBaselinePath) {
        $authoritativeBaseline = $baseline
        $authoritativeSchemaValid = $baselineSchemaValid
    }
    else {
        $authoritativeBaseline = Read-OfflineApiMetadata -Path $resolvedAuthoritativeBaselinePath -Label 'authoritative tests metadata' -Errors $errors
        if ($null -ne $authoritativeBaseline) {
            $authoritativeSchemaValid = Test-OfflineApiMetadataSchema -Metadata $authoritativeBaseline -Label 'authoritative tests metadata' -Errors $errors
        }
    }
}

$fallbackBaseline = $null
$fallbackSchemaValid = $false
$resolvedFallbackBaselinePath = $null
if (Test-Path -LiteralPath $fallbackBaselineCandidate -PathType Leaf) {
    Assert-PackageCandidateDoesNotTraverseReparsePoint -PackageRoot $packageRoot -CandidatePath $fallbackBaselineCandidate -Label 'package-root fallback metadata'
    $resolvedFallbackBaselinePath = (Resolve-Path -LiteralPath $fallbackBaselineCandidate).Path
    if ($resolvedFallbackBaselinePath -ieq $resolvedBaselinePath) {
        $fallbackBaseline = $baseline
        $fallbackSchemaValid = $baselineSchemaValid
    }
    else {
        $fallbackBaseline = Read-OfflineApiMetadata -Path $resolvedFallbackBaselinePath -Label 'package-root fallback metadata' -Errors $errors
        if ($null -ne $fallbackBaseline) {
            $fallbackSchemaValid = Test-OfflineApiMetadataSchema -Metadata $fallbackBaseline -Label 'package-root fallback metadata' -Errors $errors
        }
    }
}

$semanticMetadataCopies = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
if ($baselineSchemaValid) {
    [void]$semanticMetadataCopies.Add((ConvertTo-CanonicalJsonText -Value $baseline))
}
if ($authoritativeSchemaValid) {
    [void]$semanticMetadataCopies.Add((ConvertTo-CanonicalJsonText -Value $authoritativeBaseline))
}
if ($fallbackSchemaValid) {
    [void]$semanticMetadataCopies.Add((ConvertTo-CanonicalJsonText -Value $fallbackBaseline))
}
if ($semanticMetadataCopies.Count -gt 1) {
    [void]$errors.Add('metadata copies differ: selected BaselinePath, tests authority, and package-root fallback must be semantically identical')
}

$moduleProperties = @()
if ($baseline -is [pscustomobject]) {
    $modulesProperty = $baseline.PSObject.Properties['modules']
    if ($null -ne $modulesProperty -and $modulesProperty.Value -is [pscustomobject]) {
        $moduleProperties = @($modulesProperty.Value.PSObject.Properties)
    }
}
$moduleMethodCount = 0
foreach ($module in $moduleProperties) {
    if ($module.Value -is [object[]]) {
        $moduleMethodCount += @($module.Value).Count
    }
}
$eventNames = @()
if ($baseline -is [pscustomobject]) {
    $eventsProperty = $baseline.PSObject.Properties['events']
    if ($null -ne $eventsProperty -and $eventsProperty.Value -is [object[]]) {
        $eventNames = @($eventsProperty.Value)
    }
}
$hasCompatibilityRecords = $moduleMethodCount -gt 0 -or $eventNames.Count -gt 0

if ($baselineSchemaValid -and $hasCompatibilityRecords) {
    if ([string]$baseline.status -ne 'y3_api_compatibility_baseline' -or
        $baseline.compatibility_baseline_available -ne $true -or
        $baseline.real_map_script_root_integrated -ne $true) {
        $errors.Add('non-empty modules/events require an integrated real map script root and an explicit Y3 API compatibility baseline status')
    }

    $sourceRoot = Join-Path $Y3LuaApiRoot 'sources\y3-lualib'
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
        $errors.Add("y3-lualib cache not found for compatibility records: $sourceRoot")
    }
    else {
        $actualCommitOutput = & git -C $sourceRoot rev-parse HEAD 2>&1
        if ($LASTEXITCODE -ne 0) {
            $errors.Add("unable to read y3-lualib commit: $($actualCommitOutput | Out-String)")
        }
        else {
            $actualCommit = ([string]$actualCommitOutput).Trim()
            if ([string]::IsNullOrWhiteSpace([string]$baseline.commit)) {
                $errors.Add('Y3 API compatibility records require a pinned y3-lualib commit')
            }
            elseif ($actualCommit -ne [string]$baseline.commit) {
                $errors.Add("y3-lualib commit mismatch: expected $($baseline.commit), found $actualCommit")
            }
        }

        foreach ($module in $moduleProperties) {
            $docPath = Join-Path $sourceRoot ("doc\API\{0}.md" -f $module.Name)
            if (-not (Test-Path -LiteralPath $docPath -PathType Leaf)) { $errors.Add("missing API module document: $($module.Name)"); continue }
            $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $docPath
            foreach ($method in @($module.Value)) {
                if ($content -notmatch ('(?m)^##\s+' + [regex]::Escape([string]$method) + '\s*$')) { $errors.Add("$($module.Name).$method not found in public API docs") }
            }
        }

        $eventPath = Join-Path $sourceRoot 'meta\event.lua'
        if ($eventNames.Count -gt 0 -and -not (Test-Path -LiteralPath $eventPath -PathType Leaf)) {
            $errors.Add("missing Y3 event metadata: $eventPath")
        }
        elseif ($eventNames.Count -gt 0) {
            $eventSource = Get-Content -Raw -Encoding UTF8 -LiteralPath $eventPath
            foreach ($eventName in $eventNames) {
                if ($eventSource -notmatch ('M\.config\["' + [regex]::Escape([string]$eventName) + '"\]')) { $errors.Add("event not found: $eventName") }
            }
        }
    }
}
elseif ($baselineSchemaValid -and ([string]$baseline.status -ne 'offline_api_isolation_only' -or
    $baseline.compatibility_baseline_available -ne $false -or
    $baseline.real_map_script_root_integrated -ne $false)) {
    $errors.Add('empty modules/events must explicitly declare offline_api_isolation_only; they are not a Y3 API compatibility baseline')
}

$luaRoot = Join-Path $packageRoot 'lua'
$luaFiles = @()
if (-not (Test-Path -LiteralPath $luaRoot -PathType Container)) {
    $errors.Add("offline Lua package root not found: $luaRoot")
}
else {
    $luaFiles = @(Get-ChildItem -LiteralPath $luaRoot -Recurse -File -Filter '*.lua')
    if ($luaFiles.Count -eq 0) {
        $errors.Add("offline Lua package contains no Lua files to isolate: $luaRoot")
    }
}
$allowedModules = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($luaFile in $luaFiles) {
    $relativePath = $luaFile.FullName.Substring($luaRoot.Length).TrimStart('\', '/')
    $moduleName = ($relativePath -replace '\.lua$', '').Replace('\', '.').Replace('/', '.')
    [void]$allowedModules.Add($moduleName)
}
$forbiddenCalls = @($luaFiles | ForEach-Object { Get-ForbiddenLuaEngineReferences -Path $_.FullName -AllowedModules $allowedModules })
if ($forbiddenCalls.Count -gt 0) {
    $locations = @($forbiddenCalls | ForEach-Object { "$($_.Path):$($_.Line):$($_.Column) [$($_.Display)]" }) -join ', '
    $errors.Add("offline Lua package contains forbidden engine, global environment, or dynamic module-loading references: $locations")
}
if ($errors.Count -gt 0) { foreach ($message in $errors) { Write-Error $message }; exit 1 }
if ($hasCompatibilityRecords) {
    Write-Output "PASS: Huaguoshan Y3 API compatibility baseline and offline API isolation checks passed against y3-lualib $actualCommit"
    Write-Output "  modules: $($moduleProperties.Count)"
    Write-Output "  events: $($eventNames.Count)"
}
else {
    Write-Output 'PASS: Huaguoshan offline API isolation check passed.'
    Write-Output '  Y3 API compatibility baseline: unavailable (real map script root not integrated)'
    Write-Output '  compatibility records: modules 0, events 0 (explicitly empty)'
}
Write-Output '  forbidden engine/environment references: 0'
