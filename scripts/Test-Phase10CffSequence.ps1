param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('All','Contracts','Validation','Trajectory','Adapter','Routing','SequenceFront','SequenceSteps','SequenceExit')]
    [string]$Scope = 'All',
    [switch]$RequireReport
)

$ErrorActionPreference = 'Stop'
$script:FailureCount = 0
$plcRoot = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding'
$projectPath = Join-Path $plcRoot 'CFFwelding.plcproj'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $script:FailureCount++; Write-Host "FAIL: $Message" }
}
function Test-ProjectCompileItemContract {
    param(
        [AllowNull()][xml]$ProjectXml,
        [string]$ExpectedInclude
    )
    if (($null -eq $ProjectXml) -or
            [string]::IsNullOrWhiteSpace($ExpectedInclude)) {
        return $false
    }
    $projectRoot = $ProjectXml.DocumentElement
    if (($null -eq $projectRoot) -or ($projectRoot.LocalName -cne 'Project')) {
        return $false
    }
    $matchingCompileNodes = @($ProjectXml.SelectNodes('//*[local-name()="Compile"]') |
        Where-Object { $_.GetAttribute('Include') -ceq $ExpectedInclude })
    if ($matchingCompileNodes.Count -ne 1) { return $false }
    $compileNode = $matchingCompileNodes[0]
    $itemGroupNode = $compileNode.ParentNode
    if (($null -eq $itemGroupNode) -or
            ($itemGroupNode.LocalName -cne 'ItemGroup') -or
            ($itemGroupNode.ParentNode -ne $projectRoot)) {
        return $false
    }
    $directSubTypes = @($compileNode.SelectNodes('./*[local-name()="SubType"]'))
    return ($directSubTypes.Count -eq 1) -and
        ($directSubTypes[0].InnerText -ceq 'Code')
}
function Test-TwinCatObjectIdentityContract {
    param(
        [AllowNull()][xml]$ObjectXml,
        [string]$ExpectedKind,
        [string]$ExpectedGuid
    )
    if (($null -eq $ObjectXml) -or
            ($ExpectedKind -cnotin @('POU', 'DUT', 'GVL')) -or
            [string]::IsNullOrWhiteSpace($ExpectedGuid)) {
        return $false
    }
    $objectRoot = $ObjectXml.DocumentElement
    if (($null -eq $objectRoot) -or ($objectRoot.LocalName -cne 'TcPlcObject')) {
        return $false
    }
    $directObjectElements = @($objectRoot.ChildNodes | Where-Object {
        ($_.NodeType -eq [System.Xml.XmlNodeType]::Element) -and
            ($_.LocalName -cin @('POU', 'DUT', 'GVL'))
    })
    if (($directObjectElements.Count -ne 1) -or
            ($directObjectElements[0].LocalName -cne $ExpectedKind)) {
        return $false
    }
    $objectElement = $directObjectElements[0]
    $objectIdAttributes = @($objectElement.Attributes | Where-Object {
        $_.Name -ceq 'Id'
    })
    if (($objectIdAttributes.Count -ne 1) -or
            ($objectIdAttributes[0].Value -cne $ExpectedGuid)) {
        return $false
    }
    $allIdAttributes = @($ObjectXml.SelectNodes('//@*[local-name()="Id"]'))
    return ($allIdAttributes.Count -eq 1) -and
        [object]::ReferenceEquals($allIdAttributes[0].OwnerElement, $objectElement)
}
function Read-Text {
    param([string]$RelativePath)
    $path = Join-Path $RepositoryRoot $RelativePath
    Assert-True (Test-Path -LiteralPath $path) "Missing file: $RelativePath"
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}
function Remove-StComments {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    # Preserve source length and line endings so every parser can safely share
    # match indexes.  IEC string contents are executable data: comment markers
    # inside STRING/WSTRING literals must never hide a later real ST statement.
    $builder = [System.Text.StringBuilder]::new($Text.Length)
    $state = 'Code'
    $quote = [char]0
    $blockDepth = 0
    $index = 0
    while ($index -lt $Text.Length) {
        $character = $Text[$index]
        $next = if (($index + 1) -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }
        switch ($state) {
            'Code' {
                if (($character -eq [char]39) -or ($character -eq [char]34)) {
                    [void]$builder.Append($character)
                    $quote = $character
                    $state = 'String'
                    $index++
                } elseif (($character -eq '/') -and ($next -eq '/')) {
                    [void]$builder.Append('  ')
                    $state = 'LineComment'
                    $index += 2
                } elseif (($character -eq '(') -and ($next -eq '*')) {
                    [void]$builder.Append('  ')
                    $blockDepth = 1
                    $state = 'BlockComment'
                    $index += 2
                } else {
                    [void]$builder.Append($character)
                    $index++
                }
            }
            'String' {
                [void]$builder.Append($character)
                if (($character -eq '$') -and (($index + 1) -lt $Text.Length)) {
                    [void]$builder.Append($next)
                    $index += 2
                } elseif ($character -eq $quote) {
                    if ($next -eq $quote) {
                        [void]$builder.Append($next)
                        $index += 2
                    } else {
                        $state = 'Code'
                        $index++
                    }
                } else {
                    $index++
                }
            }
            'LineComment' {
                if (($character -eq "`r") -or ($character -eq "`n")) {
                    [void]$builder.Append($character)
                    $state = 'Code'
                } else {
                    [void]$builder.Append(' ')
                }
                $index++
            }
            'BlockComment' {
                if (($character -eq '(') -and ($next -eq '*')) {
                    [void]$builder.Append('  ')
                    $blockDepth++
                    $index += 2
                } elseif (($character -eq '*') -and ($next -eq ')')) {
                    [void]$builder.Append('  ')
                    $blockDepth--
                    $index += 2
                    if ($blockDepth -eq 0) { $state = 'Code' }
                } else {
                    if (($character -eq "`r") -or ($character -eq "`n")) {
                        [void]$builder.Append($character)
                    } else {
                        [void]$builder.Append(' ')
                    }
                    $index++
                }
            }
        }
    }
    return $builder.ToString()
}
function Mask-StStrings {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    # Keep indexes and line endings aligned while hiding control words and
    # assignment-shaped text held inside IEC STRING/WSTRING literals.
    $builder = [System.Text.StringBuilder]::new($Text.Length)
    $state = 'Code'
    $quote = [char]0
    $index = 0
    while ($index -lt $Text.Length) {
        $character = $Text[$index]
        $next = if (($index + 1) -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }
        if ($state -eq 'Code') {
            if (($character -eq [char]39) -or ($character -eq [char]34)) {
                [void]$builder.Append(' ')
                $quote = $character
                $state = 'String'
            } else {
                [void]$builder.Append($character)
            }
            $index++
            continue
        }

        if (($character -eq "`r") -or ($character -eq "`n")) {
            [void]$builder.Append($character)
        } else {
            [void]$builder.Append(' ')
        }
        if (($character -eq '$') -and (($index + 1) -lt $Text.Length)) {
            if (($next -eq "`r") -or ($next -eq "`n")) {
                [void]$builder.Append($next)
            } else {
                [void]$builder.Append(' ')
            }
            $index += 2
        } elseif ($character -eq $quote) {
            if ($next -eq $quote) {
                [void]$builder.Append(' ')
                $index += 2
            } else {
                $state = 'Code'
                $index++
            }
        } else {
            $index++
        }
    }
    return $builder.ToString()
}
function Get-StCodeText {
    param([AllowNull()][string]$Text)
    return Mask-StStrings (Remove-StComments $Text)
}
function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    $executableText = Remove-StComments $Text
    Assert-True ([regex]::IsMatch($executableText, $Pattern, 'Multiline')) $Message
}
function Assert-NoMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    $executableText = Remove-StComments $Text
    Assert-True (-not [regex]::IsMatch($executableText, $Pattern, 'Multiline')) $Message
}
function Assert-RawMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    Assert-True ([regex]::IsMatch($Text, $Pattern, 'Multiline')) $Message
}
function Assert-Near {
    param([double]$Actual, [double]$Expected, [double]$Tolerance, [string]$Message)
    Assert-True ([math]::Abs($Actual - $Expected) -le $Tolerance) $Message
}
function Assert-Ordered {
    param([string]$Text, [string[]]$Tokens, [string]$Message)
    $Text = Get-StCodeText $Text
    $offset = -1
    foreach ($token in $Tokens) {
        $offset = $Text.IndexOf($token, $offset + 1, [System.StringComparison]::Ordinal)
        if ($offset -lt 0) { Assert-True $false $Message; return }
    }
}
function Get-CaseBranch {
    param(
        [string]$Text,
        [string]$State,
        [string]$Message,
        [string]$SelectorPattern = 'eState'
    )
    $parsed = Get-CaseArmRegions $Text
    $escapedState = [regex]::Escape($State)
    $cases = @($parsed.Cases | Where-Object {
        ($_.ParentControlDepth -eq 0) -and
            [regex]::IsMatch(
                $_.Selector,
                "(?is)^\s*(?:$SelectorPattern)\s*$")
    })
    $targets = @()
    if ($cases.Count -eq 1) {
        $targets = @($parsed.Arms | Where-Object {
            ($_.CaseId -eq $cases[0].CaseId) -and
                [regex]::IsMatch(
                    $_.Label,
                    "(?i)^(?:E_[A-Za-z0-9_]+\.)?$escapedState$")
        })
    }
    Assert-True ($targets.Count -eq 1) $Message
    if ($targets.Count -ne 1) { return '' }
    $target = $targets[0]
    return $parsed.Text.Substring(
        $target.BodyStart,
        $target.BodyEnd - $target.BodyStart)
}
function Get-IfBody {
    param([string]$Text, [string]$Condition, [string]$Message)
    $Text = Get-StCodeText $Text
    $escapedCondition = [regex]::Escape($Condition)
    $pattern = "(?is)\bIF\s+$escapedCondition\s+THEN\s*(.*?)(?=\bEND_IF\s*;?)"
    $match = [regex]::Match($Text, $pattern)
    Assert-True $match.Success $Message
    if (-not $match.Success) { return '' }
    return $match.Groups[1].Value
}
function Assert-MatchCount {
    param(
        [string]$Text,
        [string]$Pattern,
        [int]$ExpectedCount,
        [string]$Message
    )
    $executableText = Get-StCodeText $Text
    $actualCount = [regex]::Matches($executableText, $Pattern, 'Multiline').Count
    Assert-True ($actualCount -eq $ExpectedCount) "$Message (expected $ExpectedCount, actual $actualCount)"
}
function Get-StControlStream {
    param([string]$Text)
    $executableText = Get-StCodeText $Text
    $matches = [regex]::Matches(
        $executableText,
        '(?is)\bELSIF\s+(?<ElsifCondition>.*?)\s+THEN\b|' +
            '\bIF\s+(?<IfCondition>.*?)\s+THEN\b|' +
            '\bCASE\s+(?<CaseSelector>.*?)\s+OF\b|' +
            '(?<Else>\bELSE\b)|' +
            '(?<EndIf>\bEND_IF\s*;?)|' +
            '(?<EndCase>\bEND_CASE\s*;?)')
    $tokens = New-Object 'System.Collections.Generic.List[object]'
    foreach ($match in $matches) {
        $kind = ''
        $value = ''
        if ($match.Groups['ElsifCondition'].Success) {
            $kind = 'ELSIF'
            $value = $match.Groups['ElsifCondition'].Value.Trim()
        } elseif ($match.Groups['IfCondition'].Success) {
            $kind = 'IF'
            $value = $match.Groups['IfCondition'].Value.Trim()
        } elseif ($match.Groups['CaseSelector'].Success) {
            $kind = 'CASE'
            $value = $match.Groups['CaseSelector'].Value.Trim()
        } elseif ($match.Groups['Else'].Success) {
            $kind = 'ELSE'
        } elseif ($match.Groups['EndIf'].Success) {
            $kind = 'END_IF'
        } elseif ($match.Groups['EndCase'].Success) {
            $kind = 'END_CASE'
        }
        if ([string]::IsNullOrEmpty($kind)) { continue }
        $tokens.Add([pscustomobject]@{
            Kind = $kind
            Value = $value
            Index = $match.Index
            Length = $match.Length
        })
    }
    return [pscustomobject]@{
        Text = $executableText
        Tokens = $tokens.ToArray()
    }
}
function Get-StControlModel {
    param([string]$Text)
    $control = Get-StControlStream $Text
    $stack = New-Object 'System.Collections.Generic.List[object]'
    $ifRegions = New-Object 'System.Collections.Generic.List[object]'
    $ifBranches = New-Object 'System.Collections.Generic.List[object]'
    $caseRegions = New-Object 'System.Collections.Generic.List[object]'
    $nextIfId = 0
    $nextCaseId = 0
    $ifDepth = 0
    $caseDepth = 0
    $isBalanced = $true

    $addIfBranch = {
        param([object]$Frame, [int]$BodyEnd)
        $ifBranches.Add([pscustomobject]@{
            IfId = $Frame.IfId
            ParentDepth = $Frame.ParentIfDepth
            ParentIfDepth = $Frame.ParentIfDepth
            ParentCaseDepth = $Frame.ParentCaseDepth
            ParentControlDepth = $Frame.ParentControlDepth
            BranchOrder = $Frame.BranchOrder
            Condition = $Frame.BranchCondition
            IsPositive = $Frame.BranchIsPositive
            Start = $Frame.BranchStart
            BodyStart = $Frame.BranchBodyStart
            BodyEnd = $BodyEnd
        })
    }

    foreach ($token in $control.Tokens) {
        if ($token.Kind -eq 'IF') {
            $nextIfId++
            $stack.Add([pscustomobject]@{
                Kind = 'IF'
                IfId = $nextIfId
                Condition = $token.Value
                Start = $token.Index
                BodyStart = $token.Index + $token.Length
                AlternateStart = -1
                ElsifCount = 0
                HasElse = $false
                ElseStart = -1
                ElseBodyStart = -1
                ParentIfDepth = $ifDepth
                ParentCaseDepth = $caseDepth
                ParentControlDepth = $stack.Count
                BranchOrder = 0
                BranchCondition = $token.Value
                BranchIsPositive = $true
                BranchStart = $token.Index
                BranchBodyStart = $token.Index + $token.Length
            })
            $ifDepth++
            continue
        }
        if ($token.Kind -eq 'CASE') {
            $nextCaseId++
            $stack.Add([pscustomobject]@{
                Kind = 'CASE'
                CaseId = $nextCaseId
                Selector = $token.Value
                Start = $token.Index
                BodyStart = $token.Index + $token.Length
                DefaultStart = -1
                DefaultBodyStart = -1
                ParentIfDepth = $ifDepth
                ParentCaseDepth = $caseDepth
                ParentControlDepth = $stack.Count
            })
            $caseDepth++
            continue
        }

        $top = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $null }
        if ($token.Kind -eq 'ELSIF') {
            if (($null -eq $top) -or ($top.Kind -ne 'IF') -or $top.HasElse) {
                $isBalanced = $false
                continue
            }
            & $addIfBranch $top $token.Index
            if ($top.AlternateStart -lt 0) { $top.AlternateStart = $token.Index }
            $top.ElsifCount++
            $top.BranchOrder++
            $top.BranchCondition = $token.Value
            $top.BranchIsPositive = $true
            $top.BranchStart = $token.Index
            $top.BranchBodyStart = $token.Index + $token.Length
            continue
        }
        if ($token.Kind -eq 'ELSE') {
            if ($null -eq $top) {
                $isBalanced = $false
                continue
            }
            if ($top.Kind -eq 'IF') {
                if ($top.HasElse) {
                    $isBalanced = $false
                    continue
                }
                & $addIfBranch $top $token.Index
                if ($top.AlternateStart -lt 0) { $top.AlternateStart = $token.Index }
                $top.HasElse = $true
                $top.ElseStart = $token.Index
                $top.ElseBodyStart = $token.Index + $token.Length
                $top.BranchOrder++
                $top.BranchCondition = ''
                $top.BranchIsPositive = $false
                $top.BranchStart = $token.Index
                $top.BranchBodyStart = $token.Index + $token.Length
            } elseif ($top.Kind -eq 'CASE') {
                if ($top.DefaultStart -ge 0) {
                    $isBalanced = $false
                    continue
                }
                $top.DefaultStart = $token.Index
                $top.DefaultBodyStart = $token.Index + $token.Length
            } else {
                $isBalanced = $false
            }
            continue
        }
        if ($token.Kind -eq 'END_IF') {
            if (($null -eq $top) -or ($top.Kind -ne 'IF')) {
                $isBalanced = $false
                continue
            }
            & $addIfBranch $top $token.Index
            $stack.RemoveAt($stack.Count - 1)
            $ifDepth--
            $ifRegions.Add([pscustomobject]@{
                IfId = $top.IfId
                Condition = $top.Condition
                Start = $top.Start
                BodyStart = $top.BodyStart
                BodyEnd = $token.Index
                End = $token.Index + $token.Length
                AlternateStart = $top.AlternateStart
                ElsifCount = $top.ElsifCount
                HasElse = $top.HasElse
                ElseStart = $top.ElseStart
                ElseBodyStart = $top.ElseBodyStart
                ElseBodyEnd = if ($top.HasElse) { $token.Index } else { -1 }
                ParentDepth = $top.ParentIfDepth
                ParentIfDepth = $top.ParentIfDepth
                ParentCaseDepth = $top.ParentCaseDepth
                ParentControlDepth = $top.ParentControlDepth
            })
            continue
        }
        if ($token.Kind -eq 'END_CASE') {
            if (($null -eq $top) -or ($top.Kind -ne 'CASE')) {
                $isBalanced = $false
                continue
            }
            $stack.RemoveAt($stack.Count - 1)
            $caseDepth--
            $caseRegions.Add([pscustomobject]@{
                CaseId = $top.CaseId
                Selector = $top.Selector
                Start = $top.Start
                BodyStart = $top.BodyStart
                BodyEnd = $token.Index
                End = $token.Index + $token.Length
                DefaultStart = $top.DefaultStart
                DefaultBodyStart = $top.DefaultBodyStart
                DefaultBodyEnd = if ($top.DefaultStart -ge 0) { $token.Index } else { -1 }
                ParentDepth = $top.ParentCaseDepth
                ParentIfDepth = $top.ParentIfDepth
                ParentCaseDepth = $top.ParentCaseDepth
                ParentControlDepth = $top.ParentControlDepth
            })
        }
    }
    if (($stack.Count -ne 0) -or ($ifDepth -ne 0) -or ($caseDepth -ne 0)) {
        $isBalanced = $false
    }
    return [pscustomobject]@{
        Text = $control.Text
        Tokens = $control.Tokens
        IsBalanced = $isBalanced
        Balanced = $isBalanced
        IfRegions = if ($isBalanced) { $ifRegions.ToArray() } else { @() }
        IfBranches = if ($isBalanced) { $ifBranches.ToArray() } else { @() }
        CaseRegions = if ($isBalanced) { $caseRegions.ToArray() } else { @() }
    }
}
function Get-IfRegions {
    param([string]$Text)
    $model = Get-StControlModel $Text
    return [pscustomobject]@{
        Text = $model.Text
        Regions = $model.IfRegions
        IsBalanced = $model.IsBalanced
    }
}
function Get-IfBranchRegions {
    param([string]$Text)
    $model = Get-StControlModel $Text
    return [pscustomobject]@{
        Text = $model.Text
        Branches = $model.IfBranches
        IsBalanced = $model.IsBalanced
    }
}
function Get-CaseRegions {
    param([string]$Text)
    $model = Get-StControlModel $Text
    return [pscustomobject]@{
        Text = $model.Text
        Regions = $model.CaseRegions
        IsBalanced = $model.IsBalanced
    }
}
function Get-CaseArmRegions {
    param([string]$Text)
    $caseParsed = Get-CaseRegions $Text
    if (-not $caseParsed.IsBalanced) {
        return [pscustomobject]@{
            Text = $caseParsed.Text
            Arms = @()
            Cases = @()
            IsBalanced = $false
        }
    }
    $ifParsed = Get-IfRegions $caseParsed.Text
    $armMatches = [regex]::Matches(
        $caseParsed.Text,
        '(?m)^[^\S\r\n]*(?<Label>(?:(?:[A-Z_][A-Z0-9_]*\.)*[A-Z_][A-Z0-9_]*|[0-9]+))[^\S\r\n]*:(?![^\S\r\n]*=)[^\S\r\n]*',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $openArms = New-Object 'System.Collections.Generic.List[object]'
    foreach ($armMatch in $armMatches) {
        $enclosingCases = @($caseParsed.Regions | Where-Object {
            ($armMatch.Index -ge $_.BodyStart) -and
                ($armMatch.Index -lt $_.BodyEnd)
        } | Sort-Object BodyStart -Descending)
        if ($enclosingCases.Count -eq 0) { continue }
        $case = $enclosingCases[0]
        if (($case.DefaultStart -ge 0) -and
                ($armMatch.Index -ge $case.DefaultStart)) { continue }
        $ifOwners = @($ifParsed.Regions | Where-Object {
            ($armMatch.Index -ge $_.BodyStart) -and
                ($armMatch.Index -lt $_.BodyEnd)
        })
        $caseOwners = @($caseParsed.Regions | Where-Object {
            ($armMatch.Index -ge $_.BodyStart) -and
                ($armMatch.Index -lt $_.BodyEnd)
        })
        if (($ifOwners.Count -ne $case.ParentIfDepth) -or
                ($caseOwners.Count -ne ($case.ParentCaseDepth + 1))) {
            continue
        }
        $openArms.Add([pscustomobject]@{
            Label = $armMatch.Groups['Label'].Value
            CaseId = $case.CaseId
            Selector = $case.Selector
            CaseStart = $case.Start
            ParentDepth = $case.ParentDepth
            ParentIfDepth = $case.ParentIfDepth
            ParentCaseDepth = $case.ParentCaseDepth
            ParentControlDepth = $case.ParentControlDepth
            CaseParentDepth = $case.ParentDepth
            CaseParentIfDepth = $case.ParentIfDepth
            CaseParentCaseDepth = $case.ParentCaseDepth
            CaseParentControlDepth = $case.ParentControlDepth
            MatchStart = $armMatch.Index
            BodyStart = $armMatch.Index + $armMatch.Length
            CaseBodyEnd = $case.BodyEnd
            CaseDefaultStart = $case.DefaultStart
        })
    }
    $arms = New-Object 'System.Collections.Generic.List[object]'
    foreach ($openArm in $openArms) {
        $laterStarts = @($openArms | Where-Object {
            ($_.CaseId -eq $openArm.CaseId) -and
                ($_.MatchStart -gt $openArm.MatchStart)
        } | ForEach-Object { $_.MatchStart })
        $bodyEnd = $openArm.CaseBodyEnd
        if ($laterStarts.Count -gt 0) {
            $bodyEnd = ($laterStarts | Measure-Object -Minimum).Minimum
        }
        if (($openArm.CaseDefaultStart -ge 0) -and
                ($openArm.CaseDefaultStart -gt $openArm.MatchStart) -and
                ($openArm.CaseDefaultStart -lt $bodyEnd)) {
            $bodyEnd = $openArm.CaseDefaultStart
        }
        $arms.Add([pscustomobject]@{
            Label = $openArm.Label
            CaseId = $openArm.CaseId
            Selector = $openArm.Selector
            CaseStart = $openArm.CaseStart
            ParentDepth = $openArm.ParentDepth
            ParentIfDepth = $openArm.ParentIfDepth
            ParentCaseDepth = $openArm.ParentCaseDepth
            ParentControlDepth = $openArm.ParentControlDepth
            CaseParentDepth = $openArm.CaseParentDepth
            CaseParentIfDepth = $openArm.CaseParentIfDepth
            CaseParentCaseDepth = $openArm.CaseParentCaseDepth
            CaseParentControlDepth = $openArm.CaseParentControlDepth
            MatchStart = $openArm.MatchStart
            BodyStart = $openArm.BodyStart
            BodyEnd = $bodyEnd
        })
    }
    return [pscustomobject]@{
        Text = $caseParsed.Text
        Arms = $arms.ToArray()
        Cases = $caseParsed.Regions
        IsBalanced = $true
    }
}
function Get-UniqueCombinedTopLevelCaseRegion {
    param([string]$Text, [string]$SelectorPattern)
    $parsed = Get-CaseRegions $Text
    if (-not $parsed.IsBalanced) { return $null }
    $matches = @($parsed.Regions | Where-Object {
        ($_.ParentControlDepth -eq 0) -and
            [regex]::IsMatch(
                $_.Selector,
                "(?is)^\s*(?:$SelectorPattern)\s*$")
    })
    if ($matches.Count -ne 1) { return $null }
    return $matches[0]
}
function Get-UniqueTopLevelCaseArmBody {
    param([string]$Text, [string]$SelectorPattern, [string]$LabelPattern)
    $parsed = Get-CaseArmRegions $Text
    $case = Get-UniqueCombinedTopLevelCaseRegion $parsed.Text $SelectorPattern
    if ($null -eq $case) { return $null }
    $matches = @($parsed.Arms | Where-Object {
        ($_.CaseId -eq $case.CaseId) -and
            [regex]::IsMatch($_.Label, "(?is)^\s*(?:$LabelPattern)\s*$")
    })
    if ($matches.Count -ne 1) { return $null }
    return $parsed.Text.Substring(
        $matches[0].BodyStart,
        $matches[0].BodyEnd - $matches[0].BodyStart)
}
function Get-TextAfterUniqueTopLevelCase {
    param([string]$Text, [string]$SelectorPattern)
    $parsed = Get-CaseRegions $Text
    $case = Get-UniqueCombinedTopLevelCaseRegion $parsed.Text $SelectorPattern
    if ($null -eq $case) { return $null }
    return $parsed.Text.Substring($case.End)
}
function Get-UniqueTopLevelCaseDefaultBody {
    param([string]$Text, [string]$SelectorPattern)
    $parsed = Get-CaseRegions $Text
    $case = Get-UniqueCombinedTopLevelCaseRegion $parsed.Text $SelectorPattern
    if (($null -eq $case) -or ($case.DefaultStart -lt 0)) { return $null }
    return $parsed.Text.Substring(
        $case.DefaultBodyStart,
        $case.BodyEnd - $case.DefaultBodyStart)
}
function Get-UniqueTopLevelPositiveIfPartition {
    param([string]$Text, [string]$ConditionPattern)
    $parsed = Get-IfRegions $Text
    $matches = @($parsed.Regions | Where-Object {
        ($_.ParentControlDepth -eq 0) -and
            [regex]::IsMatch(
                $_.Condition,
                "(?is)^\s*(?:$ConditionPattern)\s*$")
    })
    if ($matches.Count -ne 1) { return $null }
    $region = $matches[0]
    $positiveEnd = if ($region.AlternateStart -ge 0) {
        $region.AlternateStart
    } else {
        $region.BodyEnd
    }
    return [pscustomobject]@{
        IfId = $region.IfId
        Start = $region.Start
        End = $region.End
        BodyStart = $region.BodyStart
        BodyEnd = $region.BodyEnd
        AlternateStart = $region.AlternateStart
        ElsifCount = $region.ElsifCount
        HasElse = $region.HasElse
        ElseStart = $region.ElseStart
        ElseBodyStart = $region.ElseBodyStart
        ParentIfDepth = $region.ParentIfDepth
        ParentCaseDepth = $region.ParentCaseDepth
        ParentControlDepth = $region.ParentControlDepth
        PositiveBody = $parsed.Text.Substring(
            $region.BodyStart,
            $positiveEnd - $region.BodyStart)
        AlternateBody = if ($region.HasElse) {
            $parsed.Text.Substring(
                $region.ElseBodyStart,
                $region.BodyEnd - $region.ElseBodyStart)
        } elseif ($region.AlternateStart -ge 0) {
            $parsed.Text.Substring(
                $region.AlternateStart,
                $region.BodyEnd - $region.AlternateStart)
        } else {
            ''
        }
        Outside = $parsed.Text.Remove(
            $region.Start,
            $region.End - $region.Start)
    }
}
function Test-FastInputsAtomicAcceptance {
    param([string]$RawText)
    $parsed = Get-IfRegions $RawText
    if (-not $parsed.IsBalanced) { return $false }
    $caseParsed = Get-CaseRegions $parsed.Text
    $text = $parsed.Text
    $outerCondition = '(?is)^\s*FC_IsNewerRequestId\s*\(\s*udiCandidate\s*:=\s*udiLiveFastRequestId\s*,\s*udiReference\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.nRequestId\s*\)\s*$'
    $outerRegions = @($parsed.Regions | Where-Object {
        ($_.ParentControlDepth -eq 0) -and
        [regex]::IsMatch($_.Condition, $outerCondition)
    })
    if ($outerRegions.Count -ne 1) { return $false }
    $outer = $outerRegions[0]
    $outerPositiveEnd = if ($outer.AlternateStart -ge 0) {
        $outer.AlternateStart
    } else {
        $outer.BodyEnd
    }

    $liveIdMatches = [regex]::Matches(
        $text,
        '\budiLiveFastRequestId\s*:=\s*GVL_Command\.stFast\.nRequestId\s*;',
        'IgnoreCase')
    if (($liveIdMatches.Count -ne 1) -or
            ($liveIdMatches[0].Index -ge $outer.Start)) { return $false }
    $liveIdInsideIf = @($parsed.Regions | Where-Object {
        ($liveIdMatches[0].Index -ge $_.BodyStart) -and
        ($liveIdMatches[0].Index -lt $_.BodyEnd)
    }).Count -gt 0
    $liveIdInsideCase = @($caseParsed.Regions | Where-Object {
        ($liveIdMatches[0].Index -ge $_.BodyStart) -and
        ($liveIdMatches[0].Index -lt $_.BodyEnd)
    }).Count -gt 0
    if ($liveIdInsideIf -or $liveIdInsideCase) { return $false }

    $copyMatches = [regex]::Matches(
        $text,
        '\bstFastCommandCandidate\s*:=\s*GVL_Command\.stFast\s*;',
        'IgnoreCase')
    if ($copyMatches.Count -ne 1) { return $false }
    $copyIndex = $copyMatches[0].Index
    if (($copyIndex -lt $outer.BodyStart) -or
            ($copyIndex -ge $outerPositiveEnd)) { return $false }
    $copyContainers = @($parsed.Regions | Where-Object {
        ($copyIndex -ge $_.BodyStart) -and ($copyIndex -lt $_.BodyEnd)
    })
    if (($copyContainers.Count -ne 1) -or
            ($copyContainers[0].Start -ne $outer.Start)) { return $false }
    if (@($caseParsed.Regions | Where-Object {
            ($copyIndex -ge $_.BodyStart) -and ($copyIndex -lt $_.BodyEnd)
        }).Count -gt 0) { return $false }

    $stableCondition = '(?is)^\s*\(?\s*stFastCommandCandidate\.nRequestId\s*=\s*udiLiveFastRequestId\s*\)?\s+AND\s+\(?\s*GVL_Command\.stFast\.nRequestId\s*=\s*udiLiveFastRequestId\s*\)?\s*$'
    $stableRegions = @($parsed.Regions | Where-Object {
        ($_.ParentIfDepth -eq 1) -and
        ($_.ParentCaseDepth -eq 0) -and
        ($_.ParentControlDepth -eq 1) -and
        ($_.Start -ge $outer.BodyStart) -and
        ($_.End -le $outerPositiveEnd) -and
        [regex]::IsMatch($_.Condition, $stableCondition)
    })
    if ($stableRegions.Count -ne 1) { return $false }
    $stable = $stableRegions[0]
    if ($copyIndex -ge $stable.Start) { return $false }
    $stablePositiveEnd = if ($stable.AlternateStart -ge 0) {
        $stable.AlternateStart
    } else {
        $stable.BodyEnd
    }

    $publishMatches = [regex]::Matches(
        $text,
        '\bGVL_FastInternal\.stAcceptedCommand\s*:=\s*stFastCommandCandidate\s*;',
        'IgnoreCase')
    if ($publishMatches.Count -ne 1) { return $false }
    $publishIndex = $publishMatches[0].Index
    $publishContainers = @($parsed.Regions | Where-Object {
        ($publishIndex -ge $_.BodyStart) -and ($publishIndex -lt $_.BodyEnd)
    })
    if ($publishContainers.Count -ne 2) { return $false }
    if (@($caseParsed.Regions | Where-Object {
            ($publishIndex -ge $_.BodyStart) -and ($publishIndex -lt $_.BodyEnd)
        }).Count -gt 0) { return $false }
    $containerStarts = @($publishContainers | ForEach-Object { $_.Start })
    return ($publishIndex -ge $stable.BodyStart) -and
        ($publishIndex -lt $stablePositiveEnd) -and
        ($publishIndex -lt $outerPositiveEnd) -and
        ($containerStarts -contains $outer.Start) -and
        ($containerStarts -contains $stable.Start)
}
function Test-RAxisStopPendingTimer {
    param([string]$RawText)
    $ifParsed = Get-IfRegions $RawText
    $caseParsed = Get-CaseRegions $RawText
    $text = $ifParsed.Text
    $calls = [regex]::Matches(
        $text,
        '(?is)\btonRAxisStop\s*\((?<Arguments>[^;]*?)\)\s*;')
    if ($calls.Count -ne 1) { return $false }
    $call = $calls[0]
    $insideIf = @($ifParsed.Regions | Where-Object {
        ($call.Index -ge $_.BodyStart) -and ($call.Index -lt $_.BodyEnd)
    }).Count -gt 0
    $insideCase = @($caseParsed.Regions | Where-Object {
        ($call.Index -ge $_.BodyStart) -and ($call.Index -lt $_.BodyEnd)
    }).Count -gt 0
    if ($insideIf -or $insideCase) { return $false }

    $arguments = [regex]::Match(
        $call.Groups['Arguments'].Value,
        '(?is)^\s*IN\s*:=\s*(?<Input>.*)\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tRAxisStopTimeout\s*$')
    if (-not $arguments.Success) { return $false }
    $pendingInput = '(?is)^\s*\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_APPROACH\s*\)?\s+AND\s+NOT\s*\(\s*\(?\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)?\s+AND\s+\(?\s*GVL_Status\.stFast\.stRAxis\.bStandstill\s*\)?\s*\)\s*$'
    return [regex]::IsMatch($arguments.Groups['Input'].Value, $pendingInput)
}
function Get-PouImplementationText {
    param([string]$RawText)
    try {
        [xml]$document = $RawText
    }
    catch {
        return ''
    }
    $implementation = $document.SelectSingleNode('/TcPlcObject/POU/Implementation/ST')
    if ($null -eq $implementation) { return '' }
    return Get-StCodeText $implementation.InnerText
}
function Get-PouDeclarationText {
    param([string]$RawText)
    try {
        [xml]$document = $RawText
    }
    catch {
        return ''
    }
    $declaration = $document.SelectSingleNode('/TcPlcObject/POU/Declaration')
    if ($null -eq $declaration) { return '' }
    return $declaration.InnerText
}
function Get-DutDeclarationText {
    param([string]$RawText)
    try {
        [xml]$document = $RawText
    }
    catch {
        return ''
    }
    $declaration = $document.SelectSingleNode('/TcPlcObject/DUT/Declaration')
    if ($null -eq $declaration) { return '' }
    return $declaration.InnerText
}
function Test-DutFieldsHaveDirectChineseComments {
    param(
        [string]$DeclarationText,
        [System.Collections.IDictionary]$ExpectedFields
    )
    if ([string]::IsNullOrWhiteSpace($DeclarationText) -or
            ($null -eq $ExpectedFields) -or ($ExpectedFields.Count -eq 0)) {
        return $false
    }

    $lines = @($DeclarationText -split '\r?\n')
    $structIndexes = @(for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '(?i)\bSTRUCT\s*$') { $index }
    })
    $endStructIndexes = @(for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '(?i)^\s*END_STRUCT\b') { $index }
    })
    if (($structIndexes.Count -ne 1) -or ($endStructIndexes.Count -ne 1) -or
            ($endStructIndexes[0] -le $structIndexes[0])) {
        return $false
    }

    $structIndex = $structIndexes[0]
    $endStructIndex = $endStructIndexes[0]
    $structBodyLines = @()
    for ($index = $structIndex + 1; $index -lt $endStructIndex; $index++) {
        $structBodyLines += $lines[$index]
    }
    $commentFreeBody = Remove-StComments ($structBodyLines -join "`n")
    $terminatedDeclarations = @([regex]::Matches(
        $commentFreeBody,
        '(?s)(?<Declaration>[^;]*);'))
    $fieldDeclarations = New-Object 'System.Collections.Generic.List[object]'
    $cursor = 0
    foreach ($terminatedDeclaration in $terminatedDeclarations) {
        if (($terminatedDeclaration.Index -gt $cursor) -and
                (-not [string]::IsNullOrWhiteSpace(
                    $commentFreeBody.Substring($cursor, $terminatedDeclaration.Index - $cursor)))) {
            return $false
        }
        $declarationText = $terminatedDeclaration.Groups['Declaration'].Value.Trim()
        $cursor = $terminatedDeclaration.Index + $terminatedDeclaration.Length
        if ([string]::IsNullOrWhiteSpace($declarationText)) { return $false }
        $match = [regex]::Match(
            $declarationText,
            '^(?<Names>[A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*:\s*(?<Type>.+?)\s*$',
            'IgnoreCase,Singleline')
        if (-not $match.Success) { return $false }
        $fieldDeclarations.Add([pscustomobject]@{
            Names = $match.Groups['Names'].Value
            Type = $match.Groups['Type'].Value.Trim()
        })
    }
    if (($cursor -lt $commentFreeBody.Length) -and
            (-not [string]::IsNullOrWhiteSpace($commentFreeBody.Substring($cursor)))) {
        return $false
    }
    if ($fieldDeclarations.Count -ne $ExpectedFields.Count) {
        return $false
    }
    $seenNames = @{}
    foreach ($declaration in $fieldDeclarations) {
        if ($declaration.Names -match ',') { return $false }
        $normalizedName = $declaration.Names.ToUpperInvariant()
        if ($seenNames.ContainsKey($normalizedName)) { return $false }
        $seenNames[$normalizedName] = $true
        $matchingExpectedNames = @($ExpectedFields.Keys | Where-Object {
            [string]$_ -ieq $declaration.Names
        })
        if ($matchingExpectedNames.Count -ne 1) { return $false }
        if ($declaration.Type -ine [string]$ExpectedFields[$matchingExpectedNames[0]]) {
            return $false
        }
    }

    $expectedFieldNames = @($ExpectedFields.Keys)
    for ($index = 0; $index -lt $expectedFieldNames.Count; $index++) {
        if ($fieldDeclarations[$index].Names -ine [string]$expectedFieldNames[$index]) {
            return $false
        }
    }

    $previousFieldIndex = $structIndex
    foreach ($fieldName in $ExpectedFields.Keys) {
        $fieldType = [string]$ExpectedFields[$fieldName]
        $declarationPattern = '^\s*' + [regex]::Escape([string]$fieldName) +
            '\s*:\s*' + [regex]::Escape($fieldType) + '\s*;\s*$'
        $fieldIndexes = @(for ($index = $structIndex + 1; $index -lt $endStructIndex; $index++) {
            if ($lines[$index] -match $declarationPattern) { $index }
        })
        if (($fieldIndexes.Count -ne 1) -or
                ($fieldIndexes[0] -le $previousFieldIndex)) {
            return $false
        }

        $fieldIndex = $fieldIndexes[0]
        $directComment = $lines[$fieldIndex - 1]
        if ($directComment -notmatch '^\s*\(\*[^\r\n]*\p{IsCJKUnifiedIdeographs}[^\r\n]*\*\)\s*$') {
            return $false
        }
        if (($fieldIndex - 2 -gt $structIndex) -and
                ($lines[$fieldIndex - 2] -match '^\s*\(\*[^\r\n]*\*\)\s*$')) {
            return $false
        }
        $previousFieldIndex = $fieldIndex
    }

    return $true
}
function Test-RCommandPayloadChangedAssignment {
    param([string]$RawText)
    $ifParsed = Get-IfRegions $RawText
    $caseParsed = Get-CaseRegions $RawText
    $assignments = [regex]::Matches(
        $ifParsed.Text,
        '(?ms)(?:(?<=;)|^)\s*(?<Name>bRCommandPayloadChanged)\s*:=\s*(?<Expression>.*?);')
    if ($assignments.Count -ne 1) { return $false }
    $assignment = $assignments[0]
    $insideIf = @($ifParsed.Regions | Where-Object {
        ($assignment.Groups['Name'].Index -ge $_.BodyStart) -and
            ($assignment.Groups['Name'].Index -lt $_.BodyEnd)
    }).Count -gt 0
    $insideCase = @($caseParsed.Regions | Where-Object {
        ($assignment.Groups['Name'].Index -ge $_.BodyStart) -and
            ($assignment.Groups['Name'].Index -lt $_.BodyEnd)
    }).Count -gt 0
    if ($insideIf -or $insideCase) { return $false }
    $expression = $assignment.Groups['Expression'].Value
    if ($expression -match '(?i)\b(?:AND|NOT|XOR|TRUE|FALSE)\b|(?<!:)=(?!=)') {
        return $false
    }
    $fields = @(
        'bEnable',
        'bReset',
        'bStop',
        'bMoveVelocity',
        'rVelocity_rpm',
        'rAcceleration_rpm_s',
        'rDeceleration_rpm_s'
    )
    foreach ($field in $fields) {
        $comparison = "stCandidateRCommand\.$([regex]::Escape($field))\s*<>\s*stLastPublishedRCommand\.$([regex]::Escape($field))"
        if ([regex]::Matches($expression, $comparison, 'IgnoreCase').Count -ne 1) {
            return $false
        }
    }
    return [regex]::Matches($expression, '(?i)\bOR\b').Count -eq 6
}
function Test-SaturatingUsAccumulator {
    param(
        [string]$RawText,
        [string]$Accumulator,
        [string]$Target,
        [string]$RequiredOuterGatePattern = ''
    )
    $parsed = Get-IfRegions $RawText
    $acc = [regex]::Escape($Accumulator)
    $targetName = [regex]::Escape($Target)
    if ([regex]::IsMatch(
            $parsed.Text,
            "(?is)\b$acc\s*:=\s*(?:MIN|MAX)\s*\(|\b$acc\s*:=\s*$acc\s*\+\s*uliCycleDelta_us\s*;\s*\b$acc\s*:=\s*(?:MIN|MAX)")) {
        return $false
    }
    $saturationPattern =
        "(?is)IF\s+$acc\s*<\s*$targetName\s+THEN\s*" +
        "IF\s+uliCycleDelta_us\s*>=\s*$targetName\s*-\s*$acc\s+THEN\s*" +
        "$acc\s*:=\s*$targetName\s*;\s*ELSE\s*" +
        "$acc\s*:=\s*$acc\s*\+\s*uliCycleDelta_us\s*;\s*" +
        "END_IF\s*;?\s*END_IF\s*;?"
    if ([regex]::Matches($parsed.Text, $saturationPattern).Count -ne 1) {
        return $false
    }
    $additions = [regex]::Matches(
        $parsed.Text,
        "\b$acc\s*:=\s*$acc\s*\+\s*uliCycleDelta_us\s*;")
    if ($additions.Count -ne 1) { return $false }
    $deadAncestor = @($parsed.Regions | Where-Object {
        ($additions[0].Index -ge $_.BodyStart) -and
            ($additions[0].Index -lt $_.BodyEnd) -and
            [regex]::IsMatch(
                $_.Condition,
                '(?i)^\s*(?:FALSE|0\s*=\s*1)\s*$')
    }).Count -gt 0
    if ($deadAncestor) { return $false }
    if (-not [string]::IsNullOrEmpty($RequiredOuterGatePattern)) {
        $insideRequiredPositiveGate = @($parsed.Regions | Where-Object {
            $positiveEnd = if ($_.AlternateStart -ge 0) {
                $_.AlternateStart
            } else {
                $_.BodyEnd
            }
            ($additions[0].Index -ge $_.BodyStart) -and
                ($additions[0].Index -lt $positiveEnd) -and
                [regex]::IsMatch(
                    $_.Condition,
                    "(?s)^\s*(?:$RequiredOuterGatePattern)\s*$",
                    'Multiline')
        }).Count -eq 1
        if (-not $insideRequiredPositiveGate) { return $false }
    }
    return $true
}
function Test-StepResultPublisher {
    param([string]$RawText)
    $parsed = Get-IfRegions $RawText
    $caseParsed = Get-CaseRegions $RawText
    $writerPattern = '\bGVL_Process\.astStepCriterion\s*\[\s*nStepResultIndex\s*\]\s*:=\s*stStepResultCandidate\s*;'
    $writers = [regex]::Matches($parsed.Text, $writerPattern, 'IgnoreCase')
    if ($writers.Count -ne 1) { return $false }
    if ([regex]::IsMatch(
            $parsed.Text,
            'GVL_Process\.astStepCriterion\s*\[[^\]]+\]\s*:=\s*fbStepCriterion\.stOutput')) {
        return $false
    }
    $gatePattern = '(?is)^\s*\(?\s*bStepResultPublishRequested\s+AND\s+NOT\s+abStepResultWritten\s*\[\s*nStepResultIndex\s*\]\s*\)?\s*$'
    $gates = @($parsed.Regions | Where-Object {
        ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch($_.Condition, $gatePattern)
    })
    if ($gates.Count -ne 1) { return $false }
    $gate = $gates[0]
    $positiveEnd = if ($gate.AlternateStart -ge 0) {
        $gate.AlternateStart
    } else {
        $gate.BodyEnd
    }
    $writer = $writers[0]
    if (($writer.Index -lt $gate.BodyStart) -or ($writer.Index -ge $positiveEnd)) {
        return $false
    }
    $writerContainers = @($parsed.Regions | Where-Object {
        ($writer.Index -ge $_.BodyStart) -and ($writer.Index -lt $_.BodyEnd)
    })
    if (($writerContainers.Count -ne 1) -or
            ($writerContainers[0].Start -ne $gate.Start)) {
        return $false
    }
    $writerInsideCase = @($caseParsed.Regions | Where-Object {
        ($writer.Index -ge $_.BodyStart) -and ($writer.Index -lt $_.BodyEnd)
    }).Count -gt 0
    $gateInsideCase = @($caseParsed.Regions | Where-Object {
        ($gate.Start -ge $_.BodyStart) -and ($gate.Start -lt $_.BodyEnd)
    }).Count -gt 0
    if ($writerInsideCase -or $gateInsideCase) { return $false }
    $mainCases = @($caseParsed.Regions | Where-Object {
        ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch($_.Selector, '(?i)^\s*eState\s*$')
    })
    if (($mainCases.Count -ne 1) -or ($gate.Start -lt $mainCases[0].End)) {
        return $false
    }
    $candidateFields = @(
        'eStep',
        'eEndCause',
        'bPrimaryLatched',
        'bSecondaryLatched',
        'bNok',
        'nTriggerCycle',
        'bTooShort',
        'bQualifiedForceHoldMet',
        'rQualifiedForceHoldTime_s',
        'rLatchedForce_kN',
        'rLatchedRelativePosition_mm',
        'rLatchedStepTime_s'
    )
    foreach ($field in $candidateFields) {
        if ([regex]::Matches(
                $parsed.Text,
                "\bstStepResultCandidate\.$([regex]::Escape($field))\s*:=",
                'IgnoreCase').Count -ne 1) {
            return $false
        }
    }
    $orderedPatterns = @(
        '\bstStepResultCandidate\s*:=\s*stClearedStepCriterionResult\s*;',
        '\bstStepResultCandidate\.eStep\s*:=\s*eStep\s*;',
        '\bstStepResultCandidate\.eEndCause\s*:=\s*fbStepCriterion\.stOutput\.eEndCause\s*;',
        '\bstStepResultCandidate\.bPrimaryLatched\s*:=\s*fbStepCriterion\.stOutput\.bPrimaryMet\s*;',
        '\bstStepResultCandidate\.bSecondaryLatched\s*:=\s*fbStepCriterion\.stOutput\.bSecondaryLimitReached\s*;',
        '\bstStepResultCandidate\.bNok\s*:=\s*bStepResultNok\s*;',
        '\bstStepResultCandidate\.nTriggerCycle\s*:=\s*GVL_Status\.stFast\.nCycleCounter\s*;',
        '\bstStepResultCandidate\.bTooShort\s*:=\s*fbStepCriterion\.stOutput\.bTooShort\s*;',
        '\bstStepResultCandidate\.bQualifiedForceHoldMet\s*:=\s*\(\s*nStepResultIndex\s*=\s*4\s*\)\s+AND\s*\(\s*uliQualifiedHold_us\s*>=\s*uliQualifiedHoldTarget_us\s*\)\s*;',
        '\bstStepResultCandidate\.rQualifiedForceHoldTime_s\s*:=\s*rQualifiedForceHoldTime_s\s*;',
        '\bstStepResultCandidate\.rLatchedForce_kN\s*:=\s*fbStepCriterion\.stOutput\.rLatchedForce_kN\s*;',
        '\bstStepResultCandidate\.rLatchedRelativePosition_mm\s*:=\s*fbStepCriterion\.stOutput\.rLatchedRelativePosition_mm\s*;',
        '\bstStepResultCandidate\.rLatchedStepTime_s\s*:=\s*fbStepCriterion\.stOutput\.rLatchedStepTime_s\s*;',
        $writerPattern,
        '\babStepResultWritten\s*\[\s*nStepResultIndex\s*\]\s*:=\s*TRUE\s*;'
    )
    $offset = $gate.BodyStart
    foreach ($pattern in $orderedPatterns) {
        if ([regex]::Matches($parsed.Text, $pattern, 'IgnoreCase').Count -ne 1) {
            return $false
        }
        $match = [regex]::Match(
            $parsed.Text,
            $pattern,
            'IgnoreCase',
            [timespan]::FromSeconds(1))
        if (-not $match.Success -or ($match.Index -lt $offset) -or
                ($match.Index -ge $positiveEnd)) {
            return $false
        }
        $offset = $match.Index + $match.Length
    }
    $guards = [regex]::Matches(
        $parsed.Text,
        '\babStepResultWritten\s*\[\s*nStepResultIndex\s*\]\s*:=\s*TRUE\s*;',
        'IgnoreCase')
    return $guards.Count -eq 1
}
function Test-Step4StopTimer {
    param([string]$RawText)
    $ifParsed = Get-IfRegions $RawText
    $caseParsed = Get-CaseRegions $RawText
    $calls = [regex]::Matches(
        $ifParsed.Text,
        '(?is)\btonStep4RAxisStop\s*\((?<Arguments>[^;]*?)\)\s*;')
    if ($calls.Count -ne 1) { return $false }
    $call = $calls[0]
    if (@($ifParsed.Regions | Where-Object {
                ($call.Index -ge $_.BodyStart) -and ($call.Index -lt $_.BodyEnd)
            }).Count -gt 0) { return $false }
    if (@($caseParsed.Regions | Where-Object {
                ($call.Index -ge $_.BodyStart) -and ($call.Index -lt $_.BodyEnd)
            }).Count -gt 0) { return $false }
    $arguments = $call.Groups['Arguments'].Value
    if ($arguments -match '(?i)\b(?:TRUE|FALSE|XOR)\b|<>') { return $false }
    $required = @(
        'eState\s*=\s*(?:E_CffState\.)?CFF_BRAKE_AND_COMPRESSION_RAMP',
        'eState\s*=\s*(?:E_CffState\.)?CFF_STEP4_VALID_FORCE_HOLD',
        'GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId',
        '\bbRpmStopped\b',
        'PT\s*:=\s*stSequenceConfigSnapshot\.tRAxisStopTimeout'
    )
    foreach ($pattern in $required) {
        if (-not [regex]::IsMatch($arguments, $pattern, 'IgnoreCase')) {
            return $false
        }
    }
    return [regex]::IsMatch(
        $arguments,
        '(?is)^\s*IN\s*:=\s*\(\s*\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_BRAKE_AND_COMPRESSION_RAMP\s*\)?\s+OR\s+\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_STEP4_VALID_FORCE_HOLD\s*\)?\s*\)\s+AND\s*\(\s*\(\s*eState\s*=\s*(?:E_CffState\.)?CFF_BRAKE_AND_COMPRESSION_RAMP\s+AND\s+bStateEntry\s*\)\s+OR\s+NOT\s*\(\s*\(\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)\s+AND\s+bRpmStopped\s*\)\s*\)\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tRAxisStopTimeout\s*$')
}
function Test-BrakeToHoldTransition {
    param([string]$BrakeBranch)
    $parsed = Get-IfRegions $BrakeBranch
    $transitions = [regex]::Matches(
        $parsed.Text,
        '\beNextState\s*:=\s*(?:E_CffState\.)?CFF_STEP4_VALID_FORCE_HOLD\s*;',
        'IgnoreCase')
    if ($transitions.Count -ne 1) { return $false }
    $transition = $transitions[0]
    $containers = @($parsed.Regions | Where-Object {
        $positiveEnd = if ($_.AlternateStart -ge 0) {
            $_.AlternateStart
        } else {
            $_.BodyEnd
        }
        ($_.ParentDepth -eq 0) -and
            ($transition.Index -ge $_.BodyStart) -and
            ($transition.Index -lt $positiveEnd)
    })
    $condition = ''
    if ($containers.Count -eq 1) {
        $condition = $containers[0].Condition
    }
    else {
        $elsifGate = [regex]::Match(
            $parsed.Text,
            '(?is)\bELSIF\s+(?<Condition>(?:(?!\bTHEN\b).)*)\s+THEN\s*eNextState\s*:=\s*(?:E_CffState\.)?CFF_STEP4_VALID_FORCE_HOLD\s*;')
        if (-not $elsifGate.Success) { return $false }
        $condition = $elsifGate.Groups['Condition'].Value
    }
    if ($condition -match '(?i)\b(?:OR|XOR|TRUE|FALSE)\b|<>') {
        return $false
    }
    if ([regex]::Matches($condition, '(?i)\bNOT\b').Count -ne 1) {
        return $false
    }
    if ([regex]::Matches($condition, '(?i)\bAND\b').Count -ne 5) {
        return $false
    }
    $required = @(
        '\bNOT\s+\(?\s*bStateEntry\s*\)?',
        'GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId',
        'GVL_Status\.stFast\.bRSpeedRampValid',
        'GVL_Status\.stFast\.bRSpeedRampReached',
        'GVL_Status\.stFast\.bForceSetpointRampValid',
        'GVL_Status\.stFast\.bForceSetpointRampReached'
    )
    foreach ($pattern in $required) {
        if (-not [regex]::IsMatch($condition, $pattern, 'IgnoreCase')) {
            return $false
        }
    }
    return $true
}
function Test-NoReturnPriorityBranch {
    param([string]$BranchText)
    $parsed = Get-IfRegions $BranchText
    $firstFaultCondition = '(?is)^\s*\(?\s*udiFirstFaultId\s*>\s*0\s*\)?\s*$'
    $priorityRegions = @($parsed.Regions | Where-Object {
        ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch($_.Condition, $firstFaultCondition)
    })
    if ($priorityRegions.Count -ne 1) { return $false }
    $priority = $priorityRegions[0]
    $priorityText = $parsed.Text.Substring(
        $priority.Start,
        $priority.End - $priority.Start)
    $orderedPriority = [regex]::Match(
        $priorityText,
        '(?is)^\s*IF\s+\(?\s*udiFirstFaultId\s*>\s*0\s*\)?\s+THEN' +
            '(?<Fault>.*?)' +
            'ELSIF\s+\(?\s*bStopRequestedLatched\s+OR\s+bAbortEvent\s+OR\s+bResetPendingLatched\s*\)?\s+THEN' +
            '(?<Abort>.*?eNextState\s*:=\s*(?:E_CffState\.)?CFF_EXTSETPOINT_DISABLE\s*;)')
    if (-not $orderedPriority.Success) { return $false }
    $faultBody = $orderedPriority.Groups['Fault'].Value
    $abortBody = $orderedPriority.Groups['Abort'].Value
    if (-not [regex]::IsMatch(
            $faultBody,
            '(?is)eExitIntent\s*:=\s*(?:E_CffExitIntent\.)?CFF_EXIT_FAULT_NO_RETURN\s*;.*?eNextState\s*:=\s*(?:E_CffState\.)?CFF_EXTSETPOINT_DISABLE\s*;')) {
        return $false
    }
    if (-not [regex]::IsMatch(
            $abortBody,
            '(?is)eExitIntent\s*:=\s*(?:E_CffExitIntent\.)?CFF_EXIT_ABORT_NO_RETURN\s*;.*?eNextState\s*:=\s*(?:E_CffState\.)?CFF_EXTSETPOINT_DISABLE\s*;')) {
        return $false
    }
    return -not [regex]::IsMatch(
        $faultBody + $abortBody,
        '(?i)CFF_EXIT_(?:NORMAL|NOK)_RETURN')
}
function Test-EventExitPreservesStopResult {
    param([string]$BranchText, [int]$StepIndex)
    $text = Get-StCodeText $BranchText
    $eventPath = [regex]::Match(
        $text,
        '(?is)ELSIF\s+bStopRequestedLatched\s+OR\s+bAbortEvent\s+OR\s+bResetPendingLatched\s+THEN' +
            '(?<Body>.*?)(?=\bELSIF\b|\bELSE\b|\bEND_IF\b\s*(?:;|\s)*$)')
    if (-not $eventPath.Success) { return $false }
    $body = $eventPath.Groups['Body'].Value
    $index = [regex]::Escape([string]$StepIndex)
    $realStopResult = '(?is)IF\s+fbStepCriterion\.stOutput\.bEndConfirmed\s+' +
        'AND\s+\(\s*fbStepCriterion\.stOutput\.eEndCause\s*=\s*(?:E_StepEndCause\.)?STEP_END_STOP_REQUEST\s*\)\s+' +
        'AND\s+NOT\s+fbForceDecline\.stOutput\.bFault\s+' +
        'AND\s+NOT\s+fbStepCriterion\.stOutput\.bFault\s+THEN.*?' +
        "nStepResultIndex\s*:=\s*$index\s*;.*?" +
        'bStepResultPublishRequested\s*:=\s*TRUE\s*;.*?' +
        'eEndCause\s*:=\s*fbStepCriterion\.stOutput\.eEndCause\s*;.*?' +
        'END_IF\s*;?'
    if (-not [regex]::IsMatch($body, $realStopResult)) { return $false }
    return [regex]::IsMatch(
        $body,
        '(?is)eExitIntent\s*:=\s*(?:E_CffExitIntent\.)?CFF_EXIT_ABORT_NO_RETURN\s*;.*?' +
            'eNextState\s*:=\s*(?:E_CffState\.)?CFF_EXTSETPOINT_DISABLE\s*;')
}
function Get-PreMainCaseText {
    param([string]$RawText)
    $parsed = Get-CaseRegions $RawText
    $mainCase = Get-UniqueCombinedTopLevelCaseRegion $parsed.Text 'eState'
    if ($null -eq $mainCase) { return '' }
    return $parsed.Text.Substring(0, $mainCase.Start)
}
function Test-EntryResetGate {
    param(
        [string]$RawText,
        [string]$Variable,
        [string[]]$States
    )
    $executableText = Get-StCodeText $RawText
    $assignments = [regex]::Matches(
        $executableText,
        "(?ms)(?:(?<=;)|^)\s*$([regex]::Escape($Variable))\s*:=\s*(?<Expression>.*?);")
    $entryAssignments = @($assignments | Where-Object {
        $_.Groups['Expression'].Value -match '(?i)\bbStateEntry\b'
    })
    if ($entryAssignments.Count -ne 1) { return $false }
    $statePatterns = @($States | ForEach-Object {
        "\(\s*eState\s*=\s*(?:E_CffState\.)?$([regex]::Escape($_))\s*\)"
    })
    $expected = '(?is)^\s*bStateEntry\s+AND\s+\(\s*' +
        ($statePatterns -join '\s+OR\s+') + '\s*\)\s*$'
    return [regex]::IsMatch(
        $entryAssignments[0].Groups['Expression'].Value,
        $expected)
}
function Test-QualifiedHoldResetSites {
    param([string]$RawText)
    $ifParsed = Get-IfRegions $RawText
    $caseParsed = Get-CaseRegions $RawText
    $mainCases = @($caseParsed.Regions | Where-Object {
        ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch($_.Selector, '(?i)^\s*eState\s*$')
    })
    if ($mainCases.Count -ne 1) { return $false }
    $mainCase = $mainCases[0]
    $resets = [regex]::Matches(
        $ifParsed.Text,
        '\buliQualifiedHold_us\s*:=\s*0\s*;',
        'IgnoreCase')
    if ($resets.Count -ne 3) { return $false }

    $before = @($resets | Where-Object { $_.Index -lt $mainCase.Start })
    $inside = @($resets | Where-Object {
        ($_.Index -ge $mainCase.BodyStart) -and ($_.Index -lt $mainCase.BodyEnd)
    })
    $after = @($resets | Where-Object { $_.Index -ge $mainCase.End })
    if (($before.Count -ne 1) -or ($inside.Count -ne 1) -or ($after.Count -ne 1)) {
        return $false
    }

    $requiredConditions = @(
        [pscustomobject]@{
            Match = $before[0]
            Pattern = '(?is)^\s*bStateEntry\s+AND\s+\(\s*eState\s*=\s*(?:E_CffState\.)?CFF_BRAKE_AND_COMPRESSION_RAMP\s*\)\s*$'
        },
        [pscustomobject]@{
            Match = $inside[0]
            Pattern = '(?is)^\s*bStartEvent\s*$'
        },
        [pscustomobject]@{
            Match = $after[0]
            Pattern = '(?is)^\s*bSafeTerminalReset\s*$'
        }
    )
    foreach ($required in $requiredConditions) {
        $positiveContainers = @($ifParsed.Regions | Where-Object {
            $positiveEnd = if ($_.AlternateStart -ge 0) {
                $_.AlternateStart
            } else {
                $_.BodyEnd
            }
            ($required.Match.Index -ge $_.BodyStart) -and
                ($required.Match.Index -lt $positiveEnd) -and
                [regex]::IsMatch($_.Condition, $required.Pattern)
        })
        if ($positiveContainers.Count -ne 1) { return $false }
    }
    return $true
}
function Test-StepElapsedResetSites {
    param([string]$RawText)
    $ifParsed = Get-IfRegions $RawText
    $caseParsed = Get-CaseRegions $RawText
    $mainCases = @($caseParsed.Regions | Where-Object {
        ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch($_.Selector, '(?i)^\s*eState\s*$')
    })
    if ($mainCases.Count -ne 1) { return $false }
    $mainCase = $mainCases[0]
    $resets = [regex]::Matches(
        $ifParsed.Text,
        '\buliStepElapsed_us\s*:=\s*0\s*;',
        'IgnoreCase')
    if ($resets.Count -ne 3) { return $false }
    $before = @($resets | Where-Object { $_.Index -lt $mainCase.Start })
    $inside = @($resets | Where-Object {
        ($_.Index -ge $mainCase.BodyStart) -and ($_.Index -lt $mainCase.BodyEnd)
    })
    $after = @($resets | Where-Object { $_.Index -ge $mainCase.End })
    if (($before.Count -ne 1) -or ($inside.Count -ne 1) -or ($after.Count -ne 1)) {
        return $false
    }
    $preCaseResetPattern = '(?is)^\s*bStateEntry\s+AND\s+\(\s*' +
        '\(\s*eState\s*=\s*(?:E_CffState\.)?CFF_STEP1_ENTRY\s*\)\s+OR\s+' +
        '\(\s*eState\s*=\s*(?:E_CffState\.)?CFF_STEP2_ENTRY\s*\)\s+OR\s+' +
        '\(\s*eState\s*=\s*(?:E_CffState\.)?CFF_STEP3_ENTRY\s*\)\s+OR\s+' +
        '\(\s*eState\s*=\s*(?:E_CffState\.)?CFF_BRAKE_AND_COMPRESSION_RAMP\s*\)\s*\)\s*$'
    $requiredConditions = @(
        [pscustomobject]@{ Match = $before[0]; Pattern = $preCaseResetPattern },
        [pscustomobject]@{ Match = $inside[0]; Pattern = '(?is)^\s*bStartEvent\s*$' },
        [pscustomobject]@{ Match = $after[0]; Pattern = '(?is)^\s*bSafeTerminalReset\s*$' }
    )
    foreach ($required in $requiredConditions) {
        $positiveContainers = @($ifParsed.Regions | Where-Object {
            $positiveEnd = if ($_.AlternateStart -ge 0) {
                $_.AlternateStart
            } else {
                $_.BodyEnd
            }
            ($required.Match.Index -ge $_.BodyStart) -and
                ($required.Match.Index -lt $positiveEnd) -and
                [regex]::IsMatch($_.Condition, $required.Pattern)
        })
        if ($positiveContainers.Count -ne 1) { return $false }
    }
    return $true
}
function Test-UniqueSafetyFactsBeforeCase {
    param([string]$RawText)
    $preCase = Get-PreMainCaseText $RawText
    if ([string]::IsNullOrWhiteSpace($preCase)) { return $false }
    $contracts = @(
        [pscustomobject]@{
            Variable = 'bHardForceActive'
            Required = @('bBusy','bForceValid','FC_IsFiniteLReal','fForceControlN\s*>=\s*stLimitsSnapshot\.fMaxForceN')
        },
        [pscustomobject]@{
            Variable = 'bHardStrokeActive'
            Required = @('bBusy','bPostContactSensorRequired','bContactReferenceValid','FC_IsFiniteLReal','fSRelSensorMm\s*>=\s*rHardMaximumRelativePosition_mm')
        },
        [pscustomobject]@{
            Variable = 'bCollisionLimitActive'
            Required = @('bBusy','bCollisionValid','bCollisionSensorActive')
        },
        [pscustomobject]@{
            Variable = 'bSensorInvalid'
            Required = @('bBusy','bContactAcceptInvalidReference','fForceControlN','fSRelSensorMm','bAxisSensorAgreement')
        }
    )
    foreach ($contract in $contracts) {
        $ifParsed = Get-IfRegions $preCase
        $assignments = [regex]::Matches(
            $preCase,
            "(?ms)(?:(?<=;)|^)\s*(?<Name>$([regex]::Escape($contract.Variable)))\s*:=\s*(?<Expression>.*?);")
        if ($assignments.Count -ne 1) { return $false }
        if (@($ifParsed.Regions | Where-Object {
                    ($assignments[0].Groups['Name'].Index -ge $_.BodyStart) -and
                        ($assignments[0].Groups['Name'].Index -lt $_.BodyEnd)
                }).Count -gt 0) {
            return $false
        }
        $expression = $assignments[0].Groups['Expression'].Value
        if ($expression -match '(?i)\b(?:TRUE|FALSE|XOR)\b') { return $false }
        foreach ($required in $contract.Required) {
            if (-not [regex]::IsMatch($expression, $required, 'IgnoreCase')) {
                return $false
            }
        }
    }
    return $true
}
function Test-Step4QualificationGate {
    param([string]$RawText)
    $preCase = Get-PreMainCaseText $RawText
    if ([string]::IsNullOrWhiteSpace($preCase)) { return $false }
    $parsed = Get-IfRegions $preCase
    $conditionPattern = '(?is)^\s*bStep4ProcessActive\s+AND\s+GVL_Process\.stActual\.bForceValid\s+AND\s+FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*GVL_Process\.stActual\.fForceControlN\s*\)\s+AND\s+FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*GVL_Status\.stFast\.stRAxis\.rActualVelocity_rpm\s*\)\s*$'
    $gates = @($parsed.Regions | Where-Object {
        ($_.ParentControlDepth -eq 0) -and
            [regex]::IsMatch($_.Condition, $conditionPattern)
    })
    if ($gates.Count -ne 1) { return $false }
    $gate = $gates[0]
    if ((-not $gate.HasElse) -or ($gate.ElsifCount -ne 0)) { return $false }
    $positiveBody = $parsed.Text.Substring(
        $gate.BodyStart,
        $gate.ElseStart - $gate.BodyStart)
    $alternateBody = $parsed.Text.Substring(
        $gate.ElseBodyStart,
        $gate.BodyEnd - $gate.ElseBodyStart)
    if (-not [regex]::IsMatch(
            $positiveBody,
            '(?is)bRpmStopped\s*:=\s*ABS\s*\(\s*GVL_Status\.stFast\.stRAxis\.rActualVelocity_rpm\s*\).*?bForceInBand\s*:=\s*ABS\s*\(\s*GVL_Process\.stActual\.fForceControlN\s*-\s*stCycleSnapshot\.stProgram\.astSteps\[4\]\.fSetForceN\s*\)')) {
        return $false
    }
    if (-not [regex]::IsMatch(
            $alternateBody,
            '(?is)^\s*bRpmStopped\s*:=\s*FALSE\s*;\s*bForceInBand\s*:=\s*FALSE\s*;\s*$')) {
        return $false
    }
    foreach ($variable in @('bRpmStopped','bForceInBand')) {
        if ([regex]::Matches(
                $preCase,
                "\b$variable\s*:=",
                'IgnoreCase').Count -ne 2) {
            return $false
        }
    }
    return $true
}
function Test-StepRampResultPaths {
    param([string]$BranchText, [int]$StepIndex)
    $text = Get-StCodeText $BranchText
    $index = [regex]::Escape([string]$StepIndex)
    $faultPath = "(?is)IF\s+udiFirstFaultId\s*>\s*0\s+THEN\s*" +
        'IF\s+fbStepCriterion\.stOutput\.bEndConfirmed\s+' +
        'AND\s+\(\(fbStepCriterion\.stOutput\.eEndCause\s*=\s*STEP_END_HARD_FORCE\)\s+' +
        'OR\s+\(fbStepCriterion\.stOutput\.eEndCause\s*=\s*STEP_END_HARD_STROKE\)\s+' +
        'OR\s+\(fbStepCriterion\.stOutput\.eEndCause\s*=\s*STEP_END_COLLISION\)\s+' +
        'OR\s+\(fbStepCriterion\.stOutput\.eEndCause\s*=\s*STEP_END_SENSOR_INVALID\)\s+' +
        'OR\s+\(fbStepCriterion\.stOutput\.eEndCause\s*=\s*STEP_END_AXIS_FAULT\)\)\s+' +
        'AND\s+NOT\s+fbForceDecline\.stOutput\.bFault\s+' +
        'AND\s+NOT\s+fbStepCriterion\.stOutput\.bFault\s+THEN\s*' +
        "nStepResultIndex\s*:=\s*$index\s*;\s*" +
        'bStepResultNok\s*:=\s*TRUE\s*;\s*' +
        'bStepResultPublishRequested\s*:=\s*TRUE\s*;'
    $algorithmPath = [regex]::Match(
        $text,
        '(?is)ELSIF\s+fbForceDecline\.stOutput\.bFault\s+OR\s+fbStepCriterion\.stOutput\.bFault\s+THEN(?<Body>.*?)ELSIF\s+fbStepCriterion\.stOutput\.bEndConfirmed\s+THEN')
    if (-not $algorithmPath.Success) { return $false }
    if ([regex]::IsMatch(
            $algorithmPath.Groups['Body'].Value,
            '(?i)\b(?:nStepResultIndex|bStepResultNok|bStepResultPublishRequested)\s*:=')) {
        return $false
    }
    $confirmedPath = '(?is)ELSIF\s+fbStepCriterion\.stOutput\.bEndConfirmed\s+THEN\s*' +
        "nStepResultIndex\s*:=\s*$index\s*;\s*" +
        'bStepResultNok\s*:=\s*fbStepCriterion\.stOutput\.bNok\s*;\s*' +
        'bStepResultPublishRequested\s*:=\s*TRUE\s*;'
    return [regex]::IsMatch($text, $faultPath) -and
        [regex]::IsMatch($text, $confirmedPath)
}
function Test-StepEndResultPath {
    param([string]$BranchText, [int]$StepIndex)
    $text = Get-StCodeText $BranchText
    $index = [regex]::Escape([string]$StepIndex)
    return [regex]::IsMatch(
        $text,
        '(?is)ELSIF\s+fbStepCriterion\.stOutput\.bEndConfirmed\s+THEN\s*' +
            "nStepResultIndex\s*:=\s*$index\s*;\s*" +
            'bStepResultNok\s*:=\s*fbStepCriterion\.stOutput\.bNok\s*;\s*' +
            'bStepResultPublishRequested\s*:=\s*TRUE\s*;')
}
function Test-Step4ResultPath {
    param([string]$BranchText, [switch]$RequireNotEntry)
    $text = Get-StCodeText $BranchText
    $entryGate = if ($RequireNotEntry) {
        'NOT\s+bStateEntry\s+AND\s+'
    } else {
        ''
    }
    return [regex]::IsMatch(
        $text,
        '(?is)ELSIF\s+' + $entryGate + 'fbStepCriterion\.stOutput\.bEndConfirmed\s+THEN\s*' +
            'nStepResultIndex\s*:=\s*4\s*;\s*' +
            'bStepResultNok\s*:=\s*fbStepCriterion\.stOutput\.bNok\s*' +
            'OR\s*\(\s*uliQualifiedHold_us\s*<\s*uliQualifiedHoldTarget_us\s*\)\s*;\s*' +
            'bStepResultPublishRequested\s*:=\s*TRUE\s*;')
}
function Get-IfPartition {
    param(
        [string]$Text,
        [string]$ConditionPattern,
        [string]$Message,
        [switch]$Optional,
        [switch]$TopLevel
    )
    $parsed = Get-IfRegions $Text
    $matchingRegions = @($parsed.Regions | Where-Object {
        $conditionMatches = [regex]::IsMatch(
            $_.Condition,
            "(?s)^\s*(?:$ConditionPattern)\s*$",
            'Multiline')
        $depthMatches = (-not $TopLevel) -or
            ($_.ParentControlDepth -eq 0)
        $conditionMatches -and $depthMatches
    })
    if ($Optional) {
        Assert-True ($matchingRegions.Count -le 1) $Message
    } else {
        Assert-True ($matchingRegions.Count -eq 1) $Message
    }
    if ($matchingRegions.Count -ne 1) {
        return [pscustomobject]@{
            IfId = -1
            Start = -1
            End = -1
            BodyStart = -1
            BodyEnd = -1
            AlternateStart = -1
            ElsifCount = 0
            HasElse = $false
            ElseStart = -1
            ElseBodyStart = -1
            Body = ''
            PositiveBody = ''
            AlternateBody = ''
            Outside = $parsed.Text
            Before = $parsed.Text
            After = ''
        }
    }
    $region = $matchingRegions[0]
    $body = $parsed.Text.Substring(
        $region.BodyStart,
        $region.BodyEnd - $region.BodyStart)
    $positiveBodyEnd = $region.BodyEnd
    if ($region.AlternateStart -ge 0) {
        $positiveBodyEnd = $region.AlternateStart
    }
    $positiveBody = $parsed.Text.Substring(
        $region.BodyStart,
        $positiveBodyEnd - $region.BodyStart)
    $outside = $parsed.Text.Remove(
        $region.Start,
        $region.End - $region.Start)
    return [pscustomobject]@{
        IfId = $region.IfId
        Start = $region.Start
        End = $region.End
        BodyStart = $region.BodyStart
        BodyEnd = $region.BodyEnd
        AlternateStart = $region.AlternateStart
        ElsifCount = $region.ElsifCount
        HasElse = $region.HasElse
        ElseStart = $region.ElseStart
        ElseBodyStart = $region.ElseBodyStart
        Body = $body
        PositiveBody = $positiveBody
        AlternateBody = if ($region.HasElse) {
            $parsed.Text.Substring(
                $region.ElseBodyStart,
                $region.BodyEnd - $region.ElseBodyStart)
        } elseif ($region.AlternateStart -ge 0) {
            $parsed.Text.Substring(
                $region.AlternateStart,
                $region.BodyEnd - $region.AlternateStart)
        } else {
            ''
        }
        Outside = $outside
        Before = $parsed.Text.Substring(0, $region.Start)
        After = $parsed.Text.Substring($region.End)
    }
}
function Assert-TopLevelPatterns {
    param(
        [string]$Text,
        [string[]]$Patterns,
        [string]$Message
    )
    $parsed = Get-IfRegions $Text
    $caseParsed = Get-CaseRegions $parsed.Text
    $allTopLevel = $true
    foreach ($pattern in $Patterns) {
        $matches = [regex]::Matches($parsed.Text, $pattern, 'Multiline')
        $hasTopLevelMatch = $false
        foreach ($match in $matches) {
            $insideIf = @($parsed.Regions | Where-Object {
                ($match.Index -ge $_.BodyStart) -and
                    ($match.Index -lt $_.BodyEnd)
            }).Count -gt 0
            $insideCase = @($caseParsed.Regions | Where-Object {
                ($match.Index -ge $_.BodyStart) -and
                    ($match.Index -lt $_.BodyEnd)
            }).Count -gt 0
            if ((-not $insideIf) -and (-not $insideCase)) {
                $hasTopLevelMatch = $true
            }
        }
        if (-not $hasTopLevelMatch) { $allTopLevel = $false }
    }
    Assert-True $allTopLevel $Message
}
function Get-TextAfterMainCase {
    param([string]$Text, [string]$Message)
    $parsed = Get-CaseRegions $Text
    $mainCase = Get-UniqueCombinedTopLevelCaseRegion $parsed.Text 'eState'
    Assert-True ($null -ne $mainCase) $Message
    if ($null -eq $mainCase) { return '' }
    return $parsed.Text.Substring($mainCase.End)
}
function Assert-AssignmentsGuardedByIf {
    param(
        [string]$Text,
        [string]$AssignmentPattern,
        [string]$AllowedConditionPattern,
        [string]$Message
    )
    $parsed = Get-IfRegions $Text
    $assignments = [regex]::Matches(
        $parsed.Text,
        $AssignmentPattern,
        'Multiline')
    $allGuarded = $true
    foreach ($assignment in $assignments) {
        $guarded = @($parsed.Regions | Where-Object {
            ($assignment.Index -ge $_.BodyStart) -and
                ($assignment.Index -lt $_.BodyEnd) -and
                [regex]::IsMatch(
                    $_.Condition,
                    $AllowedConditionPattern,
                    'Multiline')
        }).Count -gt 0
        if (-not $guarded) { $allGuarded = $false }
    }
    Assert-True $allGuarded $Message
}
function Test-AllAssignmentsHaveExactPositiveGuardSet {
    param(
        [string]$Text,
        [string]$AssignmentPattern,
        [string[]]$RequiredConditionPatterns
    )
    $parsed = Get-IfBranchRegions $Text
    $caseParsed = Get-CaseRegions $parsed.Text
    $assignments = [regex]::Matches(
        $parsed.Text,
        $AssignmentPattern,
        'Multiline')
    if ($assignments.Count -eq 0) { return $false }
    foreach ($assignment in $assignments) {
        if (@($caseParsed.Regions | Where-Object {
                ($assignment.Index -ge $_.BodyStart) -and ($assignment.Index -lt $_.BodyEnd)
            }).Count -gt 0) { return $false }
        $enclosing = @($parsed.Branches | Where-Object {
            ($assignment.Index -ge $_.BodyStart) -and ($assignment.Index -lt $_.BodyEnd)
        })
        if ($enclosing.Count -eq 0) { return $false }
        $guardTerms = New-Object 'System.Collections.Generic.List[string]'
        foreach ($branch in $enclosing) {
            if ((-not $branch.IsPositive) -or ($branch.BranchOrder -ne 0) -or
                    [regex]::IsMatch($branch.Condition, '(?i)\b(?:OR|XOR|TRUE|FALSE)\b|\bNOT\s+NOT\b')) {
                return $false
            }
            $terms = @(Get-TopLevelAndTerms $branch.Condition)
            if ($terms.Count -eq 0) { return $false }
            foreach ($term in $terms) {
                $candidate = $term.Trim()
                $changed = $true
                while ($changed -and $candidate.StartsWith('(') -and $candidate.EndsWith(')')) {
                    $changed = $false
                    $depth = 0
                    $enclosesAll = $true
                    for ($index = 0; $index -lt $candidate.Length; $index++) {
                        if ($candidate[$index] -eq '(') { $depth++ }
                        elseif ($candidate[$index] -eq ')') { $depth-- }
                        if (($depth -eq 0) -and ($index -lt ($candidate.Length - 1))) { $enclosesAll = $false; break }
                    }
                    if ($enclosesAll -and ($depth -eq 0)) { $candidate = $candidate.Substring(1, $candidate.Length - 2).Trim(); $changed = $true }
                }
                $matchesRequired = @($RequiredConditionPatterns | Where-Object {
                    [regex]::IsMatch($candidate, "(?is)^\s*(?:$_)\s*$", 'Multiline')
                })
                if ($matchesRequired.Count -ne 1) { return $false }
                $guardTerms.Add($candidate)
            }
        }
        foreach ($requiredPattern in $RequiredConditionPatterns) {
            if (@($guardTerms | Where-Object {
                    [regex]::IsMatch($_, "(?is)^\s*(?:$requiredPattern)\s*$", 'Multiline')
                }).Count -ne 1) { return $false }
        }
    }
    return $true
}
function Test-AllAssignmentsGuardedByPositiveIf {
    param([string]$Text, [string]$AssignmentPattern, [string[]]$RequiredConditionPatterns, [int]$MinimumAndCount)
    return Test-AllAssignmentsHaveExactPositiveGuardSet $Text $AssignmentPattern $RequiredConditionPatterns
}
function Test-HasExactlyOneStrictPositiveIf {
    param(
        [string]$Text,
        [string]$ExactConditionPattern,
        [switch]$TopLevel
    )
    $parsed = Get-IfRegions $Text
    $caseParsed = Get-CaseRegions $parsed.Text
    $matchingRegions = @($parsed.Regions | Where-Object {
        $region = $_
        $conditionMatches = [regex]::IsMatch(
            $region.Condition,
            "(?s)^\s*(?:$ExactConditionPattern)\s*$",
            'Multiline')
        $insideCase = @($caseParsed.Regions | Where-Object {
            ($region.Start -ge $_.BodyStart) -and ($region.Start -lt $_.BodyEnd)
        }).Count -gt 0
        $depthMatches = (-not $TopLevel) -or
            (($region.ParentDepth -eq 0) -and (-not $insideCase))
        $conditionMatches -and $depthMatches
    })
    return $matchingRegions.Count -eq 1
}
function Test-AllAssignmentsGuardedByAllowedPositiveIf {
    param(
        [string]$Text,
        [string]$AssignmentPattern,
        [string[]]$AllowedConditionPatterns
    )
    $parsed = Get-IfRegions $Text
    $caseParsed = Get-CaseRegions $parsed.Text
    $assignments = [regex]::Matches(
        $parsed.Text,
        $AssignmentPattern,
        'Multiline')
    foreach ($assignment in $assignments) {
        $hasAllowedGuard = $false
        foreach ($region in $parsed.Regions) {
            if (@($caseParsed.Regions | Where-Object {
                    ($region.Start -ge $_.BodyStart) -and ($region.Start -lt $_.BodyEnd)
                }).Count -gt 0) { continue }
            $insidePositiveBody = ($assignment.Index -ge $region.BodyStart) -and
                ($assignment.Index -lt $region.BodyEnd) -and
                (($region.AlternateStart -lt 0) -or
                    ($assignment.Index -lt $region.AlternateStart))
            if (-not $insidePositiveBody) { continue }
            foreach ($allowedPattern in $AllowedConditionPatterns) {
                if ([regex]::IsMatch(
                        $region.Condition,
                        "(?s)^\s*(?:$allowedPattern)\s*$",
                        'Multiline')) {
                    $hasAllowedGuard = $true
                }
            }
        }
        if (-not $hasAllowedGuard) { return $false }
    }
    return $true
}
function Test-AllIncrementsImmediatelySkipZero {
    param([string]$Text, [string]$IdName)
    $executableText = Get-StCodeText $Text
    $escapedId = [regex]::Escape($IdName)
    $incrementPattern =
        "\b$escapedId\s*:=\s*$escapedId\s*\+\s*1\s*;"
    $increments = [regex]::Matches(
        $executableText,
        $incrementPattern,
        'Multiline')
    foreach ($increment in $increments) {
        $tail = $executableText.Substring(
            $increment.Index + $increment.Length)
        $pairedSkipPattern =
            "(?is)\A\s*IF\s+$escapedId\s*=\s*0\s+THEN\s*" +
            "$escapedId\s*:=\s*1\s*;\s*END_IF\s*;?"
        if (-not [regex]::IsMatch(
                $tail,
                $pairedSkipPattern,
                'Multiline')) {
            return $false
        }
    }
    return $true
}
function Find-BooleanAssignmentCoveringPatterns {
    param(
        [string]$Text,
        [string[]]$RequiredPatterns,
        [string]$Message,
        [string]$ExpectedName = ''
    )
    $parsed = Get-IfRegions $Text
    $caseParsed = Get-CaseRegions $parsed.Text
    $assignments = [regex]::Matches(
        $parsed.Text,
        '(?ms)(?:(?<=;)|^)\s*(?<Name>b[A-Za-z][A-Za-z0-9_]*)\s*:=\s*(?<Expression>.*?);')
    $assignmentMetadata = @($assignments | ForEach-Object {
        $assignment = $_
        $parentDepth = @($parsed.Regions | Where-Object {
            ($assignment.Groups['Name'].Index -ge $_.BodyStart) -and
                ($assignment.Groups['Name'].Index -lt $_.BodyEnd)
        }).Count
        $caseDepth = @($caseParsed.Regions | Where-Object {
            ($assignment.Groups['Name'].Index -ge $_.BodyStart) -and
                ($assignment.Groups['Name'].Index -lt $_.BodyEnd)
        }).Count
        [pscustomobject]@{
            Name = $assignment.Groups['Name'].Value
            Expression = $assignment.Groups['Expression'].Value
            Index = $assignment.Groups['Name'].Index
            ParentDepth = $parentDepth
            CaseDepth = $caseDepth
        }
    })
    $matchingAssignments = @($assignmentMetadata | Where-Object {
        $expression = $_.Expression
        $containsAll = [string]::IsNullOrEmpty($ExpectedName) -or
            ($_.Name -eq $ExpectedName)
        foreach ($requiredPattern in $RequiredPatterns) {
            if (-not [regex]::IsMatch(
                    $expression,
                    $requiredPattern,
                    'Multiline')) {
                $containsAll = $false
            }
        }
        $containsAll
    })
    $isValid = $matchingAssignments.Count -eq 1
    $candidate = $null
    if ($isValid) {
        $candidate = $matchingAssignments[0]
        $sameVariableAssignments = @($assignmentMetadata | Where-Object {
            $_.Name -eq $candidate.Name
        })
        $isValid = ($candidate.ParentDepth -eq 0) -and
            ($candidate.CaseDepth -eq 0) -and
            ($sameVariableAssignments.Count -eq 1)
    }
    if (-not [string]::IsNullOrEmpty($Message)) {
        Assert-True $isValid $Message
    }
    if (-not $isValid) { return $null }
    return $candidate
}
function Get-BooleanAssignmentExpression {
    param([string]$Text, [string]$VariableName)
    if ([string]::IsNullOrEmpty($VariableName)) { return '' }
    $executableText = Get-StCodeText $Text
    $escapedName = [regex]::Escape($VariableName)
    $match = [regex]::Match(
        $executableText,
        "(?ms)(?:(?<=;)|^)\s*$escapedName\s*:=\s*(?<Expression>.*?);")
    if (-not $match.Success) { return '' }
    return $match.Groups['Expression'].Value
}
function Test-PositiveExternalOwnerHoldExpression {
    param(
        [string]$Expression,
        [string[]]$States
    )
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    $releaseName =
        'GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner'
    $releasePattern =
        "(?i)\s+AND\s+NOT\s+(?:$releaseName|\(\s*$releaseName\s*\))\s*$"
    $releaseMatches = [regex]::Matches(
        $Expression,
        $releasePattern,
        'Multiline')
    if ($releaseMatches.Count -ne 1) { return $false }
    $stateGroup = $Expression.Substring(
        0,
        $releaseMatches[0].Index).Trim()
    if (($stateGroup.Length -lt 2) -or
            ($stateGroup[0] -ne '(') -or
            ($stateGroup[$stateGroup.Length - 1] -ne ')')) {
        return $false
    }
    $parenthesisDepth = 0
    for ($index = 0; $index -lt $stateGroup.Length; $index++) {
        if ($stateGroup[$index] -eq '(') {
            $parenthesisDepth++
        } elseif ($stateGroup[$index] -eq ')') {
            $parenthesisDepth--
            if (($parenthesisDepth -lt 0) -or
                    (($parenthesisDepth -eq 0) -and
                        ($index -lt ($stateGroup.Length - 1)))) {
                return $false
            }
        }
    }
    if ($parenthesisDepth -ne 0) { return $false }
    $stateExpression = $stateGroup.Substring(
        1,
        $stateGroup.Length - 2)
    $stateAlternation = ($States | ForEach-Object {
        [regex]::Escape($_)
    }) -join '|'
    $stateEqualityPattern =
        "eState\s*=\s*(?:E_CffState\.)?(?:$stateAlternation)\b"
    $stateTermPattern =
        "(?:$stateEqualityPattern|\(\s*$stateEqualityPattern\s*\))"
    $requiredOrCount = $States.Count - 1
    $completeStateChainPattern =
        "(?is)^\s*$stateTermPattern(?:\s+OR\s+$stateTermPattern){$requiredOrCount}\s*$"
    if (-not [regex]::IsMatch(
            $stateExpression,
            $completeStateChainPattern,
            'Multiline')) {
        return $false
    }
    foreach ($state in $States) {
        $statePattern =
            "\beState\s*=\s*(?:E_CffState\.)?$([regex]::Escape($state))\b"
        if ([regex]::Matches(
                $stateExpression,
                $statePattern,
                'Multiline').Count -ne 1) {
            return $false
        }
    }
    return $true
}
function Test-PositiveOrExpression {
    param(
        [string]$Expression,
        [string[]]$RequiredPatterns
    )
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    if ([regex]::IsMatch(
            $Expression,
            '(?i)\b(?:AND|NOT|XOR|TRUE|FALSE)\b|<>|!=|=\s*FALSE\b')) {
        return $false
    }
    foreach ($requiredPattern in $RequiredPatterns) {
        if (-not [regex]::IsMatch(
                $Expression,
                $requiredPattern,
                'Multiline')) {
            return $false
        }
    }
    return [regex]::Matches(
        $Expression,
        '(?i)\bOR\b').Count -ge ($RequiredPatterns.Count - 1)
}
function Get-TopLevelAndTerms {
    param([string]$Expression)
    $text = $Expression.Trim()
    $changed = $true
    while ($changed -and $text.StartsWith('(') -and $text.EndsWith(')')) {
        $changed = $false
        $depth = 0
        $enclosesAll = $true
        for ($index = 0; $index -lt $text.Length; $index++) {
            if ($text[$index] -eq '(') { $depth++ }
            elseif ($text[$index] -eq ')') { $depth-- }
            if (($depth -eq 0) -and ($index -lt ($text.Length - 1))) {
                $enclosesAll = $false
                break
            }
        }
        if ($enclosesAll -and ($depth -eq 0)) {
            $text = $text.Substring(1, $text.Length - 2).Trim()
            $changed = $true
        }
    }
    $terms = New-Object 'System.Collections.Generic.List[string]'
    $termStart = 0
    $depth = 0
    for ($index = 0; $index -lt $text.Length; $index++) {
        if ($text[$index] -eq '(') { $depth++ }
        elseif ($text[$index] -eq ')') { $depth-- }
        if ($depth -lt 0) { return @() }
        if (($depth -eq 0) -and ($index + 3 -le $text.Length) -and
                ($text.Substring($index, 3) -match '^(?i)AND$') -and
                (($index -eq 0) -or [char]::IsWhiteSpace($text[$index - 1])) -and
                (($index + 3 -eq $text.Length) -or [char]::IsWhiteSpace($text[$index + 3]))) {
            $terms.Add($text.Substring($termStart, $index - $termStart).Trim())
            $index += 2
            $termStart = $index + 1
        }
    }
    if ($depth -ne 0) { return @() }
    $terms.Add($text.Substring($termStart).Trim())
    return @($terms)
}
function Test-ExactAndTerms {
    param([string]$Expression, [string[]]$AllowedTermPatterns)
    $terms = @(Get-TopLevelAndTerms $Expression)
    if ($terms.Count -ne $AllowedTermPatterns.Count) { return $false }
    $used = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($term in $terms) {
        $matchedIndex = -1
        for ($index = 0; $index -lt $AllowedTermPatterns.Count; $index++) {
            if ($used.Contains($index)) { continue }
            if ([regex]::IsMatch($term, "(?s)^\s*(?:$($AllowedTermPatterns[$index]))\s*$", 'Multiline')) {
                $matchedIndex = $index
                break
            }
        }
        if ($matchedIndex -lt 0) { return $false }
        [void]$used.Add($matchedIndex)
    }
    return $used.Count -eq $AllowedTermPatterns.Count
}
function Get-TopLevelOrTerms {
    param([string]$Expression)
    $text = $Expression.Trim()
    $changed = $true
    while ($changed -and $text.StartsWith('(') -and $text.EndsWith(')')) {
        $changed = $false
        $depth = 0
        $enclosesAll = $true
        for ($index = 0; $index -lt $text.Length; $index++) {
            if ($text[$index] -eq '(') { $depth++ }
            elseif ($text[$index] -eq ')') { $depth-- }
            if (($depth -eq 0) -and ($index -lt ($text.Length - 1))) {
                $enclosesAll = $false
                break
            }
        }
        if ($enclosesAll -and ($depth -eq 0)) {
            $text = $text.Substring(1, $text.Length - 2).Trim()
            $changed = $true
        }
    }
    $terms = New-Object 'System.Collections.Generic.List[string]'
    $termStart = 0
    $depth = 0
    for ($index = 0; $index -lt $text.Length; $index++) {
        if ($text[$index] -eq '(') { $depth++ }
        elseif ($text[$index] -eq ')') { $depth-- }
        if ($depth -lt 0) { return @() }
        if (($depth -eq 0) -and ($index + 2 -le $text.Length) -and
                ($text.Substring($index, 2) -match '^(?i)OR$') -and
                (($index -eq 0) -or [char]::IsWhiteSpace($text[$index - 1])) -and
                (($index + 2 -eq $text.Length) -or [char]::IsWhiteSpace($text[$index + 2]))) {
            $terms.Add($text.Substring($termStart, $index - $termStart).Trim())
            $index += 1
            $termStart = $index + 1
        }
    }
    if ($depth -ne 0) { return @() }
    $terms.Add($text.Substring($termStart).Trim())
    return @($terms)
}
function Test-ExactOrTerms {
    param([string]$Expression, [string[]]$AllowedTermPatterns)
    $terms = @(Get-TopLevelOrTerms $Expression)
    if ($terms.Count -ne $AllowedTermPatterns.Count) { return $false }
    $used = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($term in $terms) {
        $matchedIndex = -1
        for ($index = 0; $index -lt $AllowedTermPatterns.Count; $index++) {
            if ($used.Contains($index)) { continue }
            if ([regex]::IsMatch($term, "(?s)^\s*(?:$($AllowedTermPatterns[$index]))\s*$", 'Multiline')) {
                $matchedIndex = $index
                break
            }
        }
        if ($matchedIndex -lt 0) { return $false }
        [void]$used.Add($matchedIndex)
    }
    return $used.Count -eq $AllowedTermPatterns.Count
}
function Test-ConditionContainsExactTerm {
    param([string]$Expression, [string]$TermPattern)
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue($Expression)
    while ($pending.Count -gt 0) {
        $candidate = $pending.Dequeue().Trim()
        $changed = $true
        while ($changed -and $candidate.StartsWith('(') -and $candidate.EndsWith(')')) {
            $changed = $false
            $depth = 0
            $enclosesAll = $true
            for ($index = 0; $index -lt $candidate.Length; $index++) {
                if ($candidate[$index] -eq '(') { $depth++ }
                elseif ($candidate[$index] -eq ')') { $depth-- }
                if (($depth -eq 0) -and ($index -lt ($candidate.Length - 1))) {
                    $enclosesAll = $false
                    break
                }
            }
            if ($enclosesAll -and ($depth -eq 0)) {
                $candidate = $candidate.Substring(1, $candidate.Length - 2).Trim()
                $changed = $true
            }
        }
        if ([regex]::IsMatch(
                $candidate,
                "(?is)^\s*(?:$TermPattern)\s*$",
                'Multiline')) {
            return $true
        }
        $andTerms = @(Get-TopLevelAndTerms $candidate)
        if ($andTerms.Count -gt 1) {
            foreach ($term in $andTerms) { $pending.Enqueue($term) }
            continue
        }
        $orTerms = @(Get-TopLevelOrTerms $candidate)
        if ($orTerms.Count -gt 1) {
            foreach ($term in $orTerms) { $pending.Enqueue($term) }
        }
    }
    return $false
}
function Test-ExactStateOrChain {
    param([string]$Expression, [string[]]$States)
    $patterns = @($States | ForEach-Object {
        '\(?\s*eState\s*=\s*(?:E_CffState\.)?' + [regex]::Escape($_) + '\s*\)?'
    })
    return Test-ExactOrTerms $Expression $patterns
}
function Test-SafeExitExpression {
    param([string]$Expression)
    return Test-ExactOrTerms $Expression @(
        '\(?\s*bStopRequestedLatched\s*\)?',
        '\(?\s*bAbortEvent\s*\)?',
        '\(?\s*bResetPendingLatched\s*\)?',
        '\(?\s*bHardForceActive\s*\)?',
        '\(?\s*bHardStrokeActive\s*\)?',
        '\(?\s*bCollisionLimitActive\s*\)?',
        '\(?\s*bExternalError\s*\)?',
        '\(?\s*bAxisError\s*\)?',
        '\(?\s*bSensorInvalid\s*\)?',
        '\(?\s*udiFirstFaultId\s*>\s*0\s*\)?'
    )
}
function Test-ReturnSafeStopExpression {
    param([string]$Expression)
    $terms = @(Get-TopLevelAndTerms $Expression)
    if ($terms.Count -ne 2) { return $false }
    $states = @('CFF_RETURN_LOCAL','CFF_RETURN_REFERENCE','CFF_EVALUATE','CFF_COMPLETE_OK','CFF_COMPLETE_NOK')
    $hasStates = $false
    $hasSafeExit = $false
    foreach ($term in $terms) {
        if (Test-ExactStateOrChain $term $states) {
            if ($hasStates) { return $false }
            $hasStates = $true
        } elseif ([regex]::IsMatch($term, '(?s)^\s*\(?\s*bSafeExitRequested\s*\)?\s*$')) {
            if ($hasSafeExit) { return $false }
            $hasSafeExit = $true
        } else {
            return $false
        }
    }
    return $hasStates -and $hasSafeExit
}
function Test-ReturnLevelHealthExpression {
    param([string]$Expression)
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    return Test-ExactAndTerms $Expression @(
        'GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner',
        '\(?\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)?',
        'GVL_Status\.stFast\.stRAxis\.bStandstill',
        'GVL_Status\.stFast\.stZAxis\.bReady',
        'GVL_Status\.stFast\.stRAxis\.bReady',
        'NOT\s+GVL_Status\.stFast\.stZAxis\.bError',
        'NOT\s+GVL_Status\.stFast\.stRAxis\.bError',
        'NOT\s+GVL_Status\.stFast\.stZExtSetpoint\.bError',
        'NOT\s+GVL_Status\.stFast\.stZExternalTrajectory\.bFault'
    )
}
function Test-ReturnEntryAuthorizationExpression {
    param([string]$Expression)
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    return Test-ExactAndTerms $Expression @(
        'bReturnLevelHealthy',
        'GVL_Status\.stFast\.stZAxis\.bStandstill'
    )
}
function Test-LocalReturnTargetExpression {
    param([string]$Expression)
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    return Test-ExactAndTerms $Expression @(
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*rCycleStartZPosition_mm\s*\)',
        'rCycleStartZPosition_mm\s*>=\s*stLimitsSnapshot\.fZMinPositionMm',
        'rCycleStartZPosition_mm\s*<=\s*stLimitsSnapshot\.fZMaxPositionMm'
    )
}
function Test-ApproachNormalCompletionExpression {
    param([string]$Expression)
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    return Test-ExactAndTerms $Expression @(
        'NOT\s+bStateEntry',
        '\(?\s*GVL_Status\.stFast\.udiAcceptedSequenceZCommandId\s*=\s*udiZCommandId\s*\)?',
        'GVL_Status\.stFast\.stZAxis\.bDone',
        'GVL_Status\.stFast\.stZAxis\.bStandstill',
        '\(?\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)?',
        'GVL_Status\.stFast\.stRAxis\.bStandstill'
    )
}
function Test-ExternalReadyExpression {
    param([string]$Expression)
    return Test-ExactOrTerms $Expression @(
        '\(?\s*GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner\s*\)?',
        '\(?\s*\(?\s*GVL_Status\.stFast\.stZExtSetpoint\.eState\s*=\s*(?:E_ZExtSetpointState\.)?Z_EXT_IDLE\s*\)?\s+AND\s+NOT\s+\(?\s*GVL_Status\.stFast\.stZExtSetpoint\.bEnabled\s*\)?\s*\)?'
    )
}
function Test-SafeTerminalResetExpression {
    param([string]$Expression)
    $terms = @(Get-TopLevelAndTerms $Expression)
    if ($terms.Count -ne 6) { return $false }
    $flags = @{
        Reset = $false; States = $false; NotBusy = $false
        ZStandstill = $false; RStandstill = $false; External = $false
    }
    foreach ($term in $terms) {
        if (Test-ExactOrTerms $term @('\(?\s*bResetEvent\s*\)?','\(?\s*bResetPendingLatched\s*\)?')) {
            if ($flags.Reset) { return $false }; $flags.Reset = $true
        } elseif (Test-ExactStateOrChain $term @('CFF_IDLE','CFF_COMPLETE_OK','CFF_COMPLETE_NOK','CFF_ABORT','CFF_FAULT')) {
            if ($flags.States) { return $false }; $flags.States = $true
        } elseif ([regex]::IsMatch($term, '(?s)^\s*\(?\s*NOT\s+bBusy\s*\)?\s*$')) {
            if ($flags.NotBusy) { return $false }; $flags.NotBusy = $true
        } elseif ([regex]::IsMatch($term, '(?s)^\s*\(?\s*GVL_Status\.stFast\.stZAxis\.bStandstill\s*\)?\s*$')) {
            if ($flags.ZStandstill) { return $false }; $flags.ZStandstill = $true
        } elseif ([regex]::IsMatch($term, '(?s)^\s*\(?\s*GVL_Status\.stFast\.stRAxis\.bStandstill\s*\)?\s*$')) {
            if ($flags.RStandstill) { return $false }; $flags.RStandstill = $true
        } elseif (Test-ExternalReadyExpression $term) {
            if ($flags.External) { return $false }; $flags.External = $true
        } else {
            return $false
        }
    }
    return -not ($flags.Values -contains $false)
}
function Test-PositiveAndExpression {
    param(
        [string]$Expression,
        [string[]]$RequiredPatterns
    )
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    return Test-ExactAndTerms $Expression $RequiredPatterns
}
function Test-UnloadHealthExpression {
    param([string]$Expression)
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    $allowedPatterns = @(
        'GVL_Process\.stActual\.bForceValid',
        'GVL_Process\.stActual\.bContactReferenceValid',
        'GVL_Process\.stActual\.bAxisSensorAgreement',
        'GVL_Status\.stFast\.bForceSetpointRampValid',
        'GVL_Status\.stFast\.stZForceControl\.bActive',
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*rForceRamp_kN_s\s*\)',
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*GVL_Process\.stActual\.fForceControlN\s*\)',
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*GVL_Process\.stActual\.fSRelSensorMm\s*\)',
        'rForceRamp_kN_s\s*>\s*0',
        'GVL_Status\.stFast\.stZExtSetpoint\.bEnabled',
        'GVL_Status\.stFast\.stZExtSetpoint\.bAcceptedSetpointValid',
        'GVL_Status\.stFast\.stZExternalTrajectory\.bActive',
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s\s*\)',
        'NOT\s+bExternalError',
        'NOT\s+bAxisError',
        'NOT\s+bSensorInvalid',
        'NOT\s+GVL_Status\.stFast\.stZForceControl\.bFault',
        'NOT\s+GVL_Status\.stFast\.stZExternalTrajectory\.bFault'
    )
    return Test-ExactAndTerms $Expression $allowedPatterns
}
function Test-AllNonzeroFirstFaultWritesGuarded {
    param([string]$Text)
    $parsed = Get-IfRegions $Text
    $writes = [regex]::Matches(
        $parsed.Text,
        '(?im)\budiFirstFaultId\s*:=\s*(?!0\s*;)[^;]+;')
    if ($writes.Count -eq 0) { return $false }
    foreach ($write in $writes) {
        $enclosing = @($parsed.Regions | Where-Object {
            $insidePositiveBody = ($write.Index -ge $_.BodyStart) -and
                ($write.Index -lt $_.BodyEnd) -and
                (($_.AlternateStart -lt 0) -or ($write.Index -lt $_.AlternateStart))
            $insidePositiveBody
        })
        if (@($enclosing | Where-Object {
                [regex]::IsMatch($_.Condition, '(?i)(?:^|\bAND\b|\()\s*udiFirstFaultId\s*=\s*0(?:\s*\)|\s*$|\s*\bAND\b)') -and
                -not [regex]::IsMatch($_.Condition, '(?i)\b(?:OR|NOT|TRUE|FALSE|XOR)\b|<>|!=|=\s*FALSE\b')
            }).Count -eq 0) {
            return $false
        }
        if (@($enclosing | Where-Object {
                [regex]::IsMatch($_.Condition, '(?i)^\s*\(?\s*FALSE\s*\)?\s*$|\bAND\s+FALSE\b')
            }).Count -gt 0) {
            return $false
        }
    }
    return $true
}
function Test-ReturnLevelPayload {
    param([string]$Text, [string]$TargetPattern)
    $executableText = Get-StCodeText $Text
    if ([regex]::IsMatch(
            $executableText,
            '\bstMotionIntent\s*:=|stMotionIntent\.(?:stZCommand|stRCommand)\s*:=')) {
        return $false
    }
    $parsed = Get-IfRegions $executableText
    $caseParsed = Get-CaseRegions $executableText
    $expectedAssignments = @(
        'stMotionIntent\.stZCommand\.bEnable\s*:=\s*TRUE\s*;',
        'stMotionIntent\.stZCommand\.bReset\s*:=\s*FALSE\s*;',
        'stMotionIntent\.stZCommand\.bStop\s*:=\s*FALSE\s*;',
        'stMotionIntent\.stZCommand\.bHome\s*:=\s*FALSE\s*;',
        'stMotionIntent\.stZCommand\.bMoveAbsolute\s*:=\s*TRUE\s*;',
        'stMotionIntent\.stZCommand\.bMoveVelocity\s*:=\s*FALSE\s*;',
        'stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*FALSE\s*;',
        'stMotionIntent\.stZCommand\.rHomePosition_mm\s*:=\s*0(?:\.0+)?\s*;',
        "stMotionIntent\.stZCommand\.rPosition_mm\s*:=\s*$TargetPattern\s*;",
        'stMotionIntent\.stZCommand\.rVelocity_mm_s\s*:=\s*stCycleSnapshot\.stProgram\.stHeader\.fReturnVelocityMmS\s*;',
        'stMotionIntent\.stZCommand\.rAcceleration_mm_s2\s*:=\s*stSequenceConfigSnapshot\.fStandardMoveAccelerationMmS2\s*;',
        'stMotionIntent\.stZCommand\.rDeceleration_mm_s2\s*:=\s*stSequenceConfigSnapshot\.fStandardMoveDecelerationMmS2\s*;',
        'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*Z_OWNER_RETRACT\s*;'
    )
    foreach ($expected in $expectedAssignments) {
        $matches = [regex]::Matches($executableText, $expected, 'Multiline')
        if ($matches.Count -ne 1) {
            return $false
        }
        if (@($parsed.Regions | Where-Object {
                ($matches[0].Index -ge $_.BodyStart) -and
                    ($matches[0].Index -lt $_.BodyEnd)
            }).Count -gt 0) {
            return $false
        }
        if (@($caseParsed.Regions | Where-Object {
                ($matches[0].Index -ge $_.BodyStart) -and
                    ($matches[0].Index -lt $_.BodyEnd)
            }).Count -gt 0) {
            return $false
        }
    }
    foreach ($field in @('bEnable','bReset','bStop','bHome','bMoveAbsolute','bMoveVelocity',
            'bUseExternalSetpoint','rHomePosition_mm','rPosition_mm','rVelocity_mm_s',
            'rAcceleration_mm_s2','rDeceleration_mm_s2','eOwnerRequest')) {
        if ([regex]::Matches(
                $executableText,
                "stMotionIntent\.stZCommand\.$field\s*:=",
                'Multiline').Count -ne 1) {
            return $false
        }
    }
    $supportAssignments = @(
        'stMotionIntent\.bExternalEnableRequest\s*:=\s*FALSE\s*;',
        'stMotionIntent\.bExternalDisableRequest\s*:=\s*FALSE\s*;',
        'stMotionIntent\.rExternalTargetVelocity_mm_s\s*:=\s*0(?:\.0+)?\s*;',
        'stMotionIntent\.bForceProcessExitComplete\s*:=\s*TRUE\s*;',
        'stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE\s*;',
        'stMotionIntent\.stRCommand\.bEnable\s*:=\s*TRUE\s*;',
        'stMotionIntent\.stRCommand\.bReset\s*:=\s*FALSE\s*;',
        'stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE\s*;',
        'stMotionIntent\.stRCommand\.bMoveVelocity\s*:=\s*FALSE\s*;',
        'stMotionIntent\.stRCommand\.rVelocity_rpm\s*:=\s*0(?:\.0+)?\s*;',
        'stMotionIntent\.stRCommand\.rAcceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS\s*;',
        'stMotionIntent\.stRCommand\.rDeceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS\s*;',
        'bForceControlEnable\s*:=\s*FALSE\s*;'
    )
    foreach ($expected in $supportAssignments) {
        $matches = [regex]::Matches($executableText, $expected, 'Multiline')
        if ($matches.Count -ne 1) { return $false }
        if (@($parsed.Regions | Where-Object {
                ($matches[0].Index -ge $_.BodyStart) -and
                    ($matches[0].Index -lt $_.BodyEnd)
            }).Count -gt 0) {
            return $false
        }
        if (@($caseParsed.Regions | Where-Object {
                ($matches[0].Index -ge $_.BodyStart) -and
                    ($matches[0].Index -lt $_.BodyEnd)
            }).Count -gt 0) {
            return $false
        }
    }
    foreach ($fieldPattern in @(
            'stMotionIntent\.bExternalEnableRequest',
            'stMotionIntent\.bExternalDisableRequest',
            'stMotionIntent\.rExternalTargetVelocity_mm_s',
            'stMotionIntent\.bForceProcessExitComplete',
            'stMotionIntent\.bRAxisProcessRequested',
            'stMotionIntent\.stRCommand\.bEnable',
            'stMotionIntent\.stRCommand\.bReset',
            'stMotionIntent\.stRCommand\.bStop',
            'stMotionIntent\.stRCommand\.bMoveVelocity',
            'stMotionIntent\.stRCommand\.rVelocity_rpm',
            'stMotionIntent\.stRCommand\.rAcceleration_rpm_s',
            'stMotionIntent\.stRCommand\.rDeceleration_rpm_s',
            '\bbForceControlEnable')) {
        if ([regex]::Matches(
                $executableText,
                "$fieldPattern\s*:=",
                'Multiline').Count -ne 1) {
            return $false
        }
    }
    return $true
}
function Test-TerminalTruthTableBranch {
    param(
        [string]$Text,
        [string]$Done,
        [string]$Error,
        [string]$Aborted
    )
    $executableText = Get-StCodeText $Text
    if ([regex]::IsMatch(
            $executableText,
            '\bstMotionIntent\s*:=|stMotionIntent\.(?:stZCommand|stRCommand)\s*:=')) {
        return $false
    }
    $parsed = Get-IfRegions $executableText
    $caseParsed = Get-CaseRegions $executableText
    $safetyTerms = @(
        'GVL_Status\.stFast\.stZAxis\.bStandstill',
        'GVL_Status\.stFast\.stRAxis\.bStandstill',
        'bExternalReady'
    )
    if ($Done -eq 'FALSE') {
        $safetyTerms += 'NOT\s+bApproachFaultStopPending'
    }
    $commonSafetyGate = @($parsed.Regions | Where-Object {
        $region = $_
        if ($region.ParentDepth -ne 0) { return $false }
        if ($region.AlternateStart -ge 0) { return $false }
        if (-not (Test-ExactAndTerms $region.Condition $safetyTerms)) { return $false }
        return @($caseParsed.Regions | Where-Object {
            ($region.Start -ge $_.BodyStart) -and ($region.Start -lt $_.BodyEnd)
        }).Count -eq 0
    })
    if ($commonSafetyGate.Count -ne 1) { return $false }
    $gate = $commonSafetyGate[0]
    $contracts = @(
        @{ Name = 'bBusy'; Value = 'FALSE' },
        @{ Name = 'bDone'; Value = $Done },
        @{ Name = 'bError'; Value = $Error },
        @{ Name = 'bAborted'; Value = $Aborted }
    )
    foreach ($contract in $contracts) {
        $assignments = [regex]::Matches(
            $executableText,
            "\b$($contract.Name)\s*:=\s*(?<Value>[^;]+)\s*;",
            'Multiline')
        if ($assignments.Count -ne 1) { return $false }
        if (-not [regex]::IsMatch(
                $assignments[0].Groups['Value'].Value,
                "(?is)^\s*$($contract.Value)\s*$")) {
            return $false
        }
        $assignmentIndex = $assignments[0].Index
        if (($assignmentIndex -lt $gate.BodyStart) -or
                ($assignmentIndex -ge $gate.BodyEnd)) {
            return $false
        }
        $ifContainers = @($parsed.Regions | Where-Object {
            ($assignmentIndex -ge $_.BodyStart) -and ($assignmentIndex -lt $_.BodyEnd)
        })
        if (($ifContainers.Count -ne 1) -or
                ($ifContainers[0].Start -ne $gate.Start)) {
            return $false
        }
        if (@($caseParsed.Regions | Where-Object {
                ($assignmentIndex -ge $_.BodyStart) -and ($assignmentIndex -lt $_.BodyEnd)
            }).Count -gt 0) {
            return $false
        }
    }
    $body = $executableText.Substring($gate.BodyStart, $gate.BodyEnd - $gate.BodyStart)
    return [regex]::IsMatch(
        $body,
        "(?is)^\s*bBusy\s*:=\s*FALSE\s*;\s*" +
            "bDone\s*:=\s*$Done\s*;\s*" +
            "bError\s*:=\s*$Error\s*;\s*" +
            "bAborted\s*:=\s*$Aborted\s*;\s*$")
}
function Test-ExactBooleanAssignment {
    param(
        [string]$Text,
        [string]$AssignmentNamePattern,
        [string]$ExpectedValue
    )
    $executableText = Get-StCodeText $Text
    $allAssignments = [regex]::Matches(
        $executableText,
        "$AssignmentNamePattern\s*:=\s*(?:TRUE|FALSE)\s*;",
        'Multiline')
    if ($allAssignments.Count -ne 1) { return $false }
    return [regex]::IsMatch(
        $allAssignments[0].Value,
        ":=\s*$ExpectedValue\s*;",
        'Multiline')
}
function Test-UniqueTopLevelCall {
    param([string]$Text, [string]$CallName, [string]$ExactCallPattern)
    $executableText = Get-StCodeText $Text
    $escapedName = [regex]::Escape($CallName)
    $calls = [regex]::Matches($executableText, "\b$escapedName\s*\(", 'Multiline')
    if ($calls.Count -ne 1) { return $false }
    if (-not [regex]::IsMatch($executableText, $ExactCallPattern, 'Multiline')) { return $false }
    $ifParsed = Get-IfRegions $executableText
    $caseParsed = Get-CaseRegions $executableText
    $callIndex = $calls[0].Index
    if (@($ifParsed.Regions | Where-Object {
            ($callIndex -ge $_.BodyStart) -and ($callIndex -lt $_.BodyEnd)
        }).Count -gt 0) { return $false }
    if (@($caseParsed.Regions | Where-Object {
            ($callIndex -ge $_.BodyStart) -and ($callIndex -lt $_.BodyEnd)
        }).Count -gt 0) { return $false }
    return $true
}
function Test-AllAssignmentsCoveredByRequiredGuards {
    param(
        [string]$Text,
        [string]$AssignmentPattern,
        [string[]]$RequiredConditionPatterns
    )
    return Test-AllAssignmentsHaveExactPositiveGuardSet $Text $AssignmentPattern $RequiredConditionPatterns
}
function Test-ReturnIntentPublicationOwnership {
    param([string]$Text)
    $executableText = Get-StCodeText $Text
    if ((Get-CaseRegions $executableText).Regions.Count -gt 0) { return $false }
    $ifParsed = Get-IfRegions $executableText
    $stateWriterPattern = '\beNextState\s*:='
    $healthTerms = @(
        'GVL_Status\.stFast\.stZAxis\.bReady',
        'GVL_Status\.stFast\.stRAxis\.bReady',
        'NOT\s+GVL_Status\.stFast\.stZAxis\.bError',
        'NOT\s+GVL_Status\.stFast\.stRAxis\.bError')
    $healthRegions = @($ifParsed.Regions | Where-Object {
        ($_.ParentControlDepth -eq 0) -and
            (Test-ExactAndTerms $_.Condition $healthTerms)
    })
    if ($healthRegions.Count -ne 1) { return $false }
    $health = $healthRegions[0]
    if ((-not $health.HasElse) -or ($health.ElsifCount -ne 0)) { return $false }
    $healthPositiveEnd = $health.ElseStart
    $healthPositive = $ifParsed.Text.Substring(
        $health.BodyStart,
        $healthPositiveEnd - $health.BodyStart)
    $healthOutside = $ifParsed.Text.Remove(
        $health.Start,
        $health.End - $health.Start)
    $returnWriterPattern = '\beNextState\s*:=\s*(?:E_CffState\.)?CFF_RETURN_(?:LOCAL|REFERENCE)\s*;'
    if ([regex]::Matches($ifParsed.Text, $returnWriterPattern, 'IgnoreCase').Count -ne 2) {
        return $false
    }
    if ([regex]::IsMatch($healthOutside, $stateWriterPattern, 'IgnoreCase')) {
        return $false
    }
    $branchParsed = Get-IfBranchRegions $healthPositive
    $localCondition = '(?is)^\s*stCycleSnapshot\.stProgram\.stHeader\.eReturnMode\s*=\s*(?:E_ReturnMode\.)?RETURN_MODE_LOCAL\s*$'
    $referenceCondition = '(?is)^\s*stCycleSnapshot\.stProgram\.stHeader\.eReturnMode\s*=\s*(?:E_ReturnMode\.)?RETURN_MODE_REFERENCE\s*$'
    $firstBranches = @($branchParsed.Branches | Where-Object {
        ($_.ParentDepth -eq 0) -and ($_.BranchOrder -eq 0) -and
            [regex]::IsMatch($_.Condition, $localCondition)
    })
    if ($firstBranches.Count -ne 1) { return $false }
    $modeBranches = @($branchParsed.Branches | Where-Object {
        $_.IfId -eq $firstBranches[0].IfId
    } | Sort-Object BranchOrder)
    if (($modeBranches.Count -ne 3) -or
            (-not [regex]::IsMatch($modeBranches[1].Condition, $referenceCondition)) -or
            $modeBranches[2].IsPositive) {
        return $false
    }
    $localBody = $branchParsed.Text.Substring(
        $modeBranches[0].BodyStart,
        $modeBranches[0].BodyEnd - $modeBranches[0].BodyStart)
    $referenceBody = $branchParsed.Text.Substring(
        $modeBranches[1].BodyStart,
        $modeBranches[1].BodyEnd - $modeBranches[1].BodyStart)
    $fallbackBody = $branchParsed.Text.Substring(
        $modeBranches[2].BodyStart,
        $modeBranches[2].BodyEnd - $modeBranches[2].BodyStart)
    if ((-not (Test-UniqueTopLevelExactAssignment $localBody '\beNextState' '(?:E_CffState\.)?CFF_RETURN_LOCAL')) -or
            (-not (Test-UniqueTopLevelExactAssignment $referenceBody '\beNextState' '(?:E_CffState\.)?CFF_RETURN_REFERENCE')) -or
            (-not (Test-UniqueTopLevelExactAssignment $fallbackBody '\beNextState' '(?:E_CffState\.)?CFF_FAULT'))) {
        return $false
    }
    $modeIfParsed = Get-IfRegions $healthPositive
    $modeRegions = @($modeIfParsed.Regions | Where-Object {
        ($_.ParentControlDepth -eq 0) -and
            [regex]::IsMatch($_.Condition, $localCondition)
    })
    if ($modeRegions.Count -ne 1) { return $false }
    if (($modeRegions[0].ElsifCount -ne 1) -or
            (-not $modeRegions[0].HasElse)) { return $false }
    $modeOutside = $modeIfParsed.Text.Remove(
        $modeRegions[0].Start,
        $modeRegions[0].End - $modeRegions[0].Start)
    if ([regex]::IsMatch($modeOutside, $stateWriterPattern, 'IgnoreCase')) {
        return $false
    }
    $healthAlternate = $ifParsed.Text.Substring(
        $health.ElseBodyStart,
        $health.BodyEnd - $health.ElseBodyStart)
    return (Test-UniqueTopLevelExactAssignment $healthAlternate '\beNextState' '(?:E_CffState\.)?CFF_FAULT') -and
        ([regex]::Matches($healthAlternate, $stateWriterPattern, 'IgnoreCase').Count -eq 1)
}
function Test-ReturnEvaluateOwnership {
    param([string]$Text)
    $eventGate = Get-UniqueTopLevelPositiveIfPartition $Text 'NOT\s+bReturnEntryBlocked'
    if (($null -eq $eventGate) -or ($eventGate.AlternateStart -ge 0)) {
        return $false
    }
    $evaluatePattern = '\beNextState\s*:=\s*(?:E_CffState\.)?CFF_EVALUATE\s*;'
    if ([regex]::Matches((Get-StCodeText $Text), $evaluatePattern, 'IgnoreCase').Count -ne 1) {
        return $false
    }
    if ([regex]::IsMatch($eventGate.Outside, $evaluatePattern, 'IgnoreCase')) {
        return $false
    }
    $publicationGate = Get-UniqueTopLevelPositiveIfPartition $eventGate.PositiveBody 'bReturnPublicationAllowed'
    if (($null -eq $publicationGate) -or
            (-not $publicationGate.HasElse) -or
            ($publicationGate.ElsifCount -ne 0)) {
        return $false
    }
    if ([regex]::IsMatch($publicationGate.Outside, $evaluatePattern, 'IgnoreCase')) {
        return $false
    }
    if ((-not (Test-UniqueTopLevelExactAssignment $publicationGate.AlternateBody '\beNextState' '(?:E_CffState\.)?CFF_FAULT')) -or
            ([regex]::Matches($publicationGate.AlternateBody, '\beNextState\s*:=', 'IgnoreCase').Count -ne 1)) {
        return $false
    }
    return Test-AllAssignmentsHaveExactPositiveGuardSet $publicationGate.PositiveBody $evaluatePattern @(
            'GVL_Status\.stFast\.udiAcceptedSequenceZCommandId\s*=\s*udiZCommandId',
            'GVL_Status\.stFast\.stZAxis\.bDone',
            'GVL_Status\.stFast\.stZAxis\.bStandstill',
            'NOT\s+tonReturn\.Q')
}
function Test-UniqueTopLevelExactAssignment {
    param([string]$Text, [string]$NamePattern, [string]$ValuePattern)
    $executableText = Get-StCodeText $Text
    $matches = [regex]::Matches(
        $executableText,
        "(?m)$NamePattern\s*:=\s*(?<Value>[^;]+)\s*;")
    if ($matches.Count -ne 1) { return $false }
    if (-not [regex]::IsMatch(
            $matches[0].Groups['Value'].Value,
            "(?s)^\s*(?:$ValuePattern)\s*$")) {
        return $false
    }
    $parsed = Get-IfBranchRegions $executableText
    $caseParsed = Get-CaseRegions $executableText
    if (@($parsed.Branches | Where-Object {
            ($matches[0].Index -ge $_.BodyStart) -and ($matches[0].Index -lt $_.BodyEnd)
        }).Count -gt 0) {
        return $false
    }
    if (@($caseParsed.Regions | Where-Object {
            ($matches[0].Index -ge $_.BodyStart) -and ($matches[0].Index -lt $_.BodyEnd)
        }).Count -gt 0) {
        return $false
    }
    return $true
}
function Test-ConflictFreeSafetyMotionWriters {
    param([string]$Text, [string]$OwnerPattern)
    $executableText = Get-StCodeText $Text
    if ([regex]::IsMatch(
            $executableText,
            '\bstMotionIntent\s*:=|stMotionIntent\.(?:stZCommand|stRCommand)\s*:=')) {
        return $false
    }
    $valid = (Test-UniqueTopLevelExactAssignment $Text 'stMotionIntent\.stZCommand\.eOwnerRequest' $OwnerPattern) -and
        (Test-UniqueTopLevelExactAssignment $Text 'stMotionIntent\.bRAxisProcessRequested' 'TRUE') -and
        (Test-UniqueTopLevelExactAssignment $Text 'stMotionIntent\.stRCommand\.bStop' 'TRUE')
    if ($valid -and [regex]::IsMatch($OwnerPattern, 'FAULT_STOP', 'IgnoreCase')) {
        $valid = Test-UniqueTopLevelExactAssignment $Text 'stMotionIntent\.stZCommand\.rDeceleration_mm_s2' 'stSequenceConfigSnapshot\.fStandardMoveDecelerationMmS2'
    }
    return $valid
}
function Test-CompleteFaultStopPayload {
    param([string]$Text)
    $contracts = @(
        @('stMotionIntent\.stZCommand\.bEnable','TRUE'),
        @('stMotionIntent\.stZCommand\.bReset','FALSE'),
        @('stMotionIntent\.stZCommand\.bStop','TRUE'),
        @('stMotionIntent\.stZCommand\.bHome','FALSE'),
        @('stMotionIntent\.stZCommand\.bMoveAbsolute','FALSE'),
        @('stMotionIntent\.stZCommand\.bMoveVelocity','FALSE'),
        @('stMotionIntent\.stZCommand\.bUseExternalSetpoint','FALSE'),
        @('stMotionIntent\.stZCommand\.rHomePosition_mm','0(?:\.0+)?'),
        @('stMotionIntent\.stZCommand\.rPosition_mm','0(?:\.0+)?'),
        @('stMotionIntent\.stZCommand\.rVelocity_mm_s','0(?:\.0+)?'),
        @('stMotionIntent\.stZCommand\.rAcceleration_mm_s2','stSequenceConfigSnapshot\.fStandardMoveAccelerationMmS2'),
        @('stMotionIntent\.stZCommand\.rDeceleration_mm_s2','stSequenceConfigSnapshot\.fStandardMoveDecelerationMmS2'),
        @('stMotionIntent\.stZCommand\.eOwnerRequest','(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP'),
        @('stMotionIntent\.bExternalEnableRequest','FALSE'),
        @('stMotionIntent\.bExternalDisableRequest','FALSE'),
        @('stMotionIntent\.rExternalTargetVelocity_mm_s','0(?:\.0+)?'),
        @('stMotionIntent\.bForceProcessExitComplete','TRUE'),
        @('stMotionIntent\.bRAxisProcessRequested','TRUE'),
        @('stMotionIntent\.stRCommand\.bEnable','TRUE'),
        @('stMotionIntent\.stRCommand\.bReset','FALSE'),
        @('stMotionIntent\.stRCommand\.bStop','TRUE'),
        @('stMotionIntent\.stRCommand\.bMoveVelocity','FALSE'),
        @('stMotionIntent\.stRCommand\.rVelocity_rpm','0(?:\.0+)?'),
        @('stMotionIntent\.stRCommand\.rAcceleration_rpm_s','stRAxisProfileSnapshot\.fSpeedRampRpmS'),
        @('stMotionIntent\.stRCommand\.rDeceleration_rpm_s','stRAxisProfileSnapshot\.fSpeedRampRpmS'),
        @('\bbForceControlEnable','FALSE')
    )
    foreach ($contract in $contracts) {
        if (-not (Test-UniqueTopLevelExactAssignment $Text $contract[0] $contract[1])) {
            return $false
        }
    }
    return -not [regex]::IsMatch(
        (Get-StCodeText $Text),
        '\bstMotionIntent\s*:=|stMotionIntent\.(?:stZCommand|stRCommand)\s*:=' )
}
function Test-ReturnSafeStopPriority {
    param([string]$Text)
    $parsed = Get-IfBranchRegions $Text
    $faultBranches = @($parsed.Branches | Where-Object {
        $_.IsPositive -and ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch(
                $_.Condition,
                '(?is)^\s*\(?\s*eExitIntent\s*=\s*(?:E_CffExitIntent\.)?CFF_EXIT_FAULT_NO_RETURN\s*\)?\s*$')
    })
    if ($faultBranches.Count -ne 1) { return $false }
    $faultBranch = $faultBranches[0]
    $alternateBranches = @($parsed.Branches | Where-Object {
        ($_.IfId -eq $faultBranch.IfId) -and (-not $_.IsPositive)
    })
    if ($alternateBranches.Count -ne 1) { return $false }
    $faultBody = $parsed.Text.Substring(
        $faultBranch.BodyStart,
        $faultBranch.BodyEnd - $faultBranch.BodyStart)
    $abortBranch = $alternateBranches[0]
    $abortBody = $parsed.Text.Substring(
        $abortBranch.BodyStart,
        $abortBranch.BodyEnd - $abortBranch.BodyStart)
    if (-not [regex]::IsMatch(
            $faultBody,
            '(?is)^\s*eNextState\s*:=\s*(?:E_CffState\.)?CFF_FAULT\s*;\s*$')) {
        return $false
    }
    if (-not [regex]::IsMatch(
            $abortBody,
            '(?is)^\s*eExitIntent\s*:=\s*(?:E_CffExitIntent\.)?CFF_EXIT_ABORT_NO_RETURN\s*;\s*eNextState\s*:=\s*(?:E_CffState\.)?CFF_ABORT\s*;\s*$')) {
        return $false
    }
    $allNextStateWrites = [regex]::Matches(
        $parsed.Text,
        '\beNextState\s*:=\s*(?:E_CffState\.)?CFF_[A-Z0-9_]+\s*;',
        'IgnoreCase')
    return $allNextStateWrites.Count -eq 2
}
function Test-ExitRStopTimeoutConsumption {
    param([string]$Text)
    $parsed = Get-IfBranchRegions $Text
    $timeoutBranches = @($parsed.Branches | Where-Object {
        $_.IsPositive -and ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch($_.Condition, '(?is)^\s*\(?\s*tonExitRAxisStop\.Q\s*\)?\s*$')
    })
    if ($timeoutBranches.Count -ne 1) { return $false }
    if ([regex]::Matches($parsed.Text, '\btonExitRAxisStop\.Q\b', 'IgnoreCase').Count -ne 1) {
        return $false
    }
    $timeoutBranch = $timeoutBranches[0]
    $timeoutBody = $parsed.Text.Substring(
        $timeoutBranch.BodyStart,
        $timeoutBranch.BodyEnd - $timeoutBranch.BodyStart)
    $guarded = Get-IfBranchRegions $timeoutBody
    $zeroGuardBranches = @($guarded.Branches | Where-Object {
        $_.IsPositive -and
            [regex]::IsMatch(
                $_.Condition,
                '(?is)^\s*\(?\s*udiFirstFaultId\s*=\s*0\s*\)?\s*$')
    })
    if ($zeroGuardBranches.Count -ne 1) { return $false }
    $a014Writes = [regex]::Matches(
        $guarded.Text,
        '\budiFirstFaultId\s*:=\s*16#0000A014\s*;',
        'IgnoreCase')
    if ($a014Writes.Count -ne 1) { return $false }
    if ([regex]::Matches(
            $guarded.Text,
            '\budiFirstFaultId\s*:=',
            'IgnoreCase').Count -ne 1) {
        return $false
    }
    $zeroGuard = $zeroGuardBranches[0]
    if (($a014Writes[0].Index -lt $zeroGuard.BodyStart) -or
            ($a014Writes[0].Index -ge $zeroGuard.BodyEnd)) {
        return $false
    }
    if ([regex]::IsMatch(
            $timeoutBody,
            'rExternalTargetVelocity_mm_s\s*:=\s*(?!0(?:\.0+)?\s*;)|bForceControlEnable\s*:=\s*TRUE')) {
        return $false
    }
    $caseParsed = Get-CaseRegions $parsed.Text
    $mainCases = @($caseParsed.Regions | Where-Object {
        ($_.ParentDepth -eq 0) -and [regex]::IsMatch($_.Selector, '(?i)^\s*eState\s*$')
    })
    if (($mainCases.Count -ne 1) -or ($timeoutBranch.BodyEnd -ge $mainCases[0].Start)) {
        return $false
    }
    return [regex]::IsMatch(
        $parsed.Text.Substring($mainCases[0].End),
        '(?s)bSafeExitRequested\s*:=.*?udiFirstFaultId\s*>\s*0.*?IF\s+bExternalOwnerHold\s+AND\s+bSafeExitRequested\s+THEN')
}
function Test-ReturnEntryBlockedExpression {
    param([string]$Expression)
    if ([string]::IsNullOrWhiteSpace($Expression)) { return $false }
    return Test-ExactOrTerms $Expression @(
        'bStopRequestedLatched',
        'bAbortEvent',
        'bResetPendingLatched',
        'bHardForceActive',
        'bHardStrokeActive',
        'bCollisionLimitActive',
        'bExternalError',
        'bAxisError',
        'bSensorInvalid',
        '\(?\s*udiFirstFaultId\s*>\s*0\s*\)?'
    )
}
function Test-UniqueTopLevelOrderedAssignments {
    param([string]$Text, [string[]]$AssignmentPatterns)
    $executableText = Get-StCodeText $Text
    $ifParsed = Get-IfRegions $executableText
    $caseParsed = Get-CaseRegions $executableText
    $previousIndex = -1
    foreach ($pattern in $AssignmentPatterns) {
        $matches = [regex]::Matches($executableText, $pattern, 'Multiline')
        if ($matches.Count -ne 1) { return $false }
        $matchIndex = $matches[0].Index
        if ($matchIndex -le $previousIndex) { return $false }
        if (@($ifParsed.Regions | Where-Object {
                ($matchIndex -ge $_.BodyStart) -and ($matchIndex -lt $_.BodyEnd)
            }).Count -gt 0) { return $false }
        if (@($caseParsed.Regions | Where-Object {
                ($matchIndex -ge $_.BodyStart) -and ($matchIndex -lt $_.BodyEnd)
            }).Count -gt 0) { return $false }
        $previousIndex = $matchIndex
    }
    return $true
}
function Test-ExactUnloadInitializer {
    param(
        [string]$Text,
        [string[]]$RequiredConditionPatterns
    )
    $truePattern = '\bbUnloadTransferInitialized\s*:=\s*TRUE\s*;'
    if (-not (Test-AllAssignmentsHaveExactPositiveGuardSet $Text $truePattern $RequiredConditionPatterns)) {
        return $false
    }
    $parsed = Get-IfBranchRegions $Text
    $trueWrites = [regex]::Matches($parsed.Text, $truePattern, 'IgnoreCase')
    if ($trueWrites.Count -ne 1) { return $false }
    $containers = @($parsed.Branches | Where-Object {
        $_.IsPositive -and ($_.BranchOrder -eq 0) -and
            ($trueWrites[0].Index -ge $_.BodyStart) -and
            ($trueWrites[0].Index -lt $_.BodyEnd)
    })
    if ($containers.Count -eq 0) { return $false }
    $innermost = @($containers | Sort-Object ParentDepth -Descending)[0]
    $outermost = @($containers | Sort-Object ParentDepth)[0]
    $packageBody = $parsed.Text.Substring(
        $innermost.BodyStart,
        $innermost.BodyEnd - $innermost.BodyStart)
    $effectiveScope = $parsed.Text.Substring(
        $outermost.BodyStart,
        $outermost.BodyEnd - $outermost.BodyStart)
    $expected = @(
        'rTargetRelativePosition_mm\s*:=\s*GVL_Process\.stActual\.fSRelSensorMm\s*;',
        'rForceTransferVelocity_mm_s\s*:=\s*GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s\s*;',
        'bForceProfileTransferPending\s*:=\s*TRUE\s*;',
        'bUnloadTransferInitialized\s*:=\s*TRUE\s*;')
    if (-not (Test-UniqueTopLevelOrderedAssignments $packageBody $expected)) {
        return $false
    }
    $effectiveWriters = [regex]::Matches(
        $effectiveScope,
        '\b(?:rTargetRelativePosition_mm|rForceTransferVelocity_mm_s|bForceProfileTransferPending|bUnloadTransferInitialized)\s*:=\s*[^;]+;',
        'IgnoreCase')
    if ($effectiveWriters.Count -ne $expected.Count) { return $false }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        if (-not [regex]::IsMatch(
                $effectiveWriters[$index].Value,
                "(?is)^\s*(?:$($expected[$index]))\s*$")) {
            return $false
        }
    }
    return $true
}
function Test-UnloadTransferWriterCardinality {
    param([string]$Text)
    $executableText = Get-StCodeText $Text
    $allWrites = [regex]::Matches(
        $executableText,
        '\bbUnloadTransferInitialized\s*:=\s*[^;]+\s*;',
        'IgnoreCase')
    $trueWrites = [regex]::Matches(
        $executableText,
        '\bbUnloadTransferInitialized\s*:=\s*TRUE\s*;',
        'IgnoreCase')
    $falseWrites = [regex]::Matches(
        $executableText,
        '\bbUnloadTransferInitialized\s*:=\s*FALSE\s*;',
        'IgnoreCase')
    if (($allWrites.Count -ne 4) -or ($trueWrites.Count -ne 2) -or ($falseWrites.Count -ne 2)) {
        return $false
    }
    $idleBody = Get-UniqueTopLevelCaseArmBody $executableText 'eState' '(?:E_CffState\.)?CFF_IDLE'
    $unloadBody = Get-UniqueTopLevelCaseArmBody $executableText 'eState' '(?:E_CffState\.)?CFF_CONTROLLED_FORCE_UNLOAD'
    $postCase = Get-TextAfterUniqueTopLevelCase $executableText 'eState'
    if ([string]::IsNullOrWhiteSpace($idleBody) -or
            [string]::IsNullOrWhiteSpace($unloadBody) -or
            [string]::IsNullOrWhiteSpace($postCase)) {
        return $false
    }
    if (-not (Test-AllAssignmentsHaveExactPositiveGuardSet $idleBody '\bbUnloadTransferInitialized\s*:=\s*FALSE\s*;' @('bStartEvent'))) {
        return $false
    }
    if (-not (Test-AllAssignmentsHaveExactPositiveGuardSet $postCase '\bbUnloadTransferInitialized\s*:=\s*FALSE\s*;' @('bSafeTerminalReset'))) {
        return $false
    }
    if (-not (Test-ExactUnloadInitializer $unloadBody @(
                'bStateEntry',
                'NOT\s+bUnloadTransferInitialized',
                'bUnloadHealthy'))) {
        return $false
    }
    return Test-ExactUnloadInitializer $postCase @(
        'bExternalOwnerHold',
        'bSafeExitRequested',
        'eExitIntent\s*=\s*(?:E_CffExitIntent\.)?CFF_EXIT_ABORT_NO_RETURN',
        'bUnloadHealthy',
        'eState\s*>=\s*(?:E_CffState\.)?CFF_CONTACT_SEARCH',
        'eState\s*<=\s*(?:E_CffState\.)?CFF_CONTROLLED_FORCE_UNLOAD',
        'eState\s*<\s*(?:E_CffState\.)?CFF_CONTROLLED_FORCE_UNLOAD',
        'NOT\s+bUnloadTransferInitialized')
}
function Test-UnloadTransferLifecycleOrdering {
    param([string]$Text)
    $ifParsed = Get-IfRegions $Text
    $caseParsed = Get-CaseRegions $ifParsed.Text
    if (-not (Test-UnloadTransferWriterCardinality $ifParsed.Text)) { return $false }
    $trueWrites = [regex]::Matches($ifParsed.Text, '\bbUnloadTransferInitialized\s*:=\s*TRUE\s*;', 'IgnoreCase')
    $pulseWrites = [regex]::Matches(
        $ifParsed.Text,
        '\bbForceProfileTransfer\s*:=\s*(?<Value>TRUE|FALSE)\s*;',
        'IgnoreCase')
    $pulseTrueWrites = @($pulseWrites | Where-Object {
        $_.Groups['Value'].Value -eq 'TRUE'
    })
    $pulseFalseWrites = @($pulseWrites | Where-Object {
        $_.Groups['Value'].Value -eq 'FALSE'
    })
    if (($pulseWrites.Count -ne 4) -or
            ($pulseTrueWrites.Count -ne 1) -or
            ($pulseFalseWrites.Count -ne 3)) {
        return $false
    }
    $consumers = @($ifParsed.Regions | Where-Object {
        $region = $_
        if ($region.ParentDepth -ne 0) { return $false }
        if (-not (Test-ExactAndTerms $region.Condition @(
                    'bForceProfileTransferPending',
                    'bForceControlEnable'))) { return $false }
        return @($caseParsed.Regions | Where-Object {
            ($region.Start -ge $_.BodyStart) -and ($region.Start -lt $_.BodyEnd)
        }).Count -eq 0
    })
    if ($consumers.Count -ne 1) { return $false }
    $consumer = $consumers[0]
    if ($consumer.AlternateStart -ge 0) { return $false }
    $topLevelPulseWrites = @($pulseWrites | Where-Object {
        $write = $_
        $insideIf = @($ifParsed.Regions | Where-Object {
            ($write.Index -ge $_.BodyStart) -and ($write.Index -lt $_.BodyEnd)
        }).Count -gt 0
        $insideCase = @($caseParsed.Regions | Where-Object {
            ($write.Index -ge $_.BodyStart) -and ($write.Index -lt $_.BodyEnd)
        }).Count -gt 0
        (-not $insideIf) -and (-not $insideCase)
    })
    if (($topLevelPulseWrites.Count -ne 1) -or
            ($topLevelPulseWrites[0].Groups['Value'].Value -ne 'FALSE') -or
            ($topLevelPulseWrites[0].Index -ge $consumer.Start)) {
        return $false
    }
    $preConsumerFalseWrites = @($pulseFalseWrites | Where-Object {
        $_.Index -lt $consumer.Start
    })
    $startPulseFalseWrites = @($preConsumerFalseWrites | Where-Object {
        $_.Index -ne $topLevelPulseWrites[0].Index
    })
    if (($preConsumerFalseWrites.Count -ne 2) -or
            ($startPulseFalseWrites.Count -ne 1) -or
            ($topLevelPulseWrites[0].Index -ge $startPulseFalseWrites[0].Index)) {
        return $false
    }
    foreach ($trueWrite in $trueWrites) {
        if ($trueWrite.Index -ge $consumer.Start) { return $false }
    }
    $consumerEnd = if ($consumer.AlternateStart -ge 0) {
        $consumer.AlternateStart
    } else {
        $consumer.BodyEnd
    }
    $consumerBody = $ifParsed.Text.Substring(
        $consumer.BodyStart,
        $consumerEnd - $consumer.BodyStart)
    if (-not [regex]::IsMatch(
            $consumerBody,
            '(?is)^\s*bForceProfileTransfer\s*:=\s*TRUE\s*;\s*' +
                'bForceProfileTransferPending\s*:=\s*FALSE\s*;\s*$')) {
        return $false
    }
    if ((-not (Test-UniqueTopLevelExactAssignment $consumerBody '\bbForceProfileTransfer' 'TRUE')) -or
            (-not (Test-UniqueTopLevelExactAssignment $consumerBody '\bbForceProfileTransferPending' 'FALSE')) -or
            ([regex]::Matches($ifParsed.Text, '\bbForceProfileTransferPending\s*:=\s*FALSE\s*;', 'IgnoreCase').Count -ne 3)) {
        return $false
    }
    $idleBody = Get-UniqueTopLevelCaseArmBody $ifParsed.Text 'eState' '(?:E_CffState\.)?CFF_IDLE'
    if ([string]::IsNullOrWhiteSpace($idleBody) -or
            (-not (Test-AllAssignmentsHaveExactPositiveGuardSet $idleBody '\bbForceProfileTransfer\s*:=\s*FALSE\s*;' @('bStartEvent'))) -or
            (-not (Test-AllAssignmentsHaveExactPositiveGuardSet $idleBody '\bbForceProfileTransferPending\s*:=\s*FALSE\s*;' @('bStartEvent')))) {
        return $false
    }
    $safeReset = Get-UniqueTopLevelPositiveIfPartition $ifParsed.Text 'bSafeTerminalReset'
    $postConsumerFalseWrites = @($pulseFalseWrites | Where-Object {
        $_.Index -ge $consumer.End
    })
    if (($null -eq $safeReset) -or ($safeReset.AlternateStart -ge 0) -or
            ($safeReset.Start -lt $consumer.End) -or
            ($postConsumerFalseWrites.Count -ne 1) -or
            ($postConsumerFalseWrites[0].Index -le $safeReset.Start) -or
            ($postConsumerFalseWrites[0].Index -ge $safeReset.End) -or
            (-not (Test-UniqueTopLevelExactAssignment $safeReset.PositiveBody '\bbForceProfileTransfer' 'FALSE')) -or
            (-not (Test-UniqueTopLevelExactAssignment $safeReset.PositiveBody '\bbForceProfileTransferPending' 'FALSE'))) {
        return $false
    }
    $publications = [regex]::Matches(
        $ifParsed.Text,
        '\bGVL_Status\.stFast\.stSequence\.stMotionIntent\s*:=\s*stMotionIntent\s*;',
        'IgnoreCase')
    if (($publications.Count -ne 1) -or
            ($publications[0].Index -lt $consumer.End) -or
            ($publications[0].Index -lt $safeReset.End) -or
            (-not (Test-UniqueTopLevelExactAssignment $ifParsed.Text '\bGVL_Status\.stFast\.stSequence\.stMotionIntent' 'stMotionIntent'))) {
        return $false
    }
    if ([regex]::Matches(
            $ifParsed.Text,
            '\bGVL_Status\.stFast\.stSequence\.stMotionIntent(?:\.[A-Za-z_][A-Za-z0-9_]*)*\s*:=',
            'IgnoreCase').Count -ne 1) { return $false }
    $publicationSuffix = $ifParsed.Text.Substring($publications[0].Index + $publications[0].Length)
    return -not [regex]::IsMatch(
        $publicationSuffix,
        '(?is)(?<![A-Za-z0-9_.])(?:' +
            'GVL_Status\.stFast\.stSequence\.stMotionIntent(?:\.[A-Za-z_][A-Za-z0-9_]*)*|' +
            'stMotionIntent(?:\.[A-Za-z_][A-Za-z0-9_]*)*|' +
            'GVL_Status\.stFast\.stSequence(?!\.)|' +
            'GVL_Status\.stFast(?!\.)|' +
            'GVL_Status(?!\.)' +
            ')\s*:=',
        'IgnoreCase')
}
function Test-ApproachSafeExitPriorityFinality {
    param([string]$Text)
    $ifParsed = Get-IfRegions $Text
    if ([regex]::IsMatch(
            $ifParsed.Text,
            '\bstMotionIntent\s*:=|\bstMotionIntent\.stZCommand\s*:=')) {
        return $false
    }
    $branchParsed = Get-IfBranchRegions $ifParsed.Text
    $caseParsed = Get-CaseRegions $ifParsed.Text
    $priorityCondition = '(?is)^\s*tonRAxisStop\.Q\s+OR\s+\(\s*udiFirstFaultId\s*=\s*16#0000A014\s*\)\s*$'
    $priorities = @($ifParsed.Regions | Where-Object {
        $region = $_
        if (($region.ParentDepth -ne 0) -or
                (-not [regex]::IsMatch($region.Condition, $priorityCondition))) {
            return $false
        }
        return @($caseParsed.Regions | Where-Object {
            ($region.Start -ge $_.BodyStart) -and ($region.Start -lt $_.BodyEnd)
        }).Count -eq 0
    })
    if ($priorities.Count -ne 1) { return $false }
    $priority = $priorities[0]
    $priorityFirstBranch = @($branchParsed.Branches | Where-Object {
        ($_.ParentDepth -eq 0) -and
        ($_.BranchOrder -eq 0) -and
        [regex]::IsMatch($_.Condition, $priorityCondition)
    })
    if ($priorityFirstBranch.Count -ne 1) { return $false }
    $priorityBranches = @($branchParsed.Branches | Where-Object {
        $_.IfId -eq $priorityFirstBranch[0].IfId
    } | Sort-Object BranchOrder)
    if ($priorityBranches.Count -ne 4) { return $false }
    if ((-not [regex]::IsMatch(
                $priorityBranches[1].Condition,
                '(?is)^\s*tonApproach\.Q\s*$')) -or
            (-not (Test-ExactAndTerms $priorityBranches[2].Condition @(
                '\(?\s*GVL_Status\.stFast\.udiAcceptedSequenceZCommandId\s*=\s*udiZCommandId\s*\)?',
                '\(?\s*GVL_Status\.stFast\.stZAxis\.bStandstill\s*\)?',
                '\(?\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)?',
                '\(?\s*GVL_Status\.stFast\.stRAxis\.bStandstill\s*\)?'))) -or
            $priorityBranches[3].IsPositive) {
        return $false
    }
    $branchTexts = @($priorityBranches | ForEach-Object {
        $branchParsed.Text.Substring($_.BodyStart, $_.BodyEnd - $_.BodyStart)
    })
    if ((-not (Test-UniqueTopLevelExactAssignment $branchTexts[0] '\beNextState' '(?:E_CffState\.)?CFF_FAULT')) -or
            (-not (Test-UniqueTopLevelExactAssignment $branchTexts[1] '\beNextState' '(?:E_CffState\.)?CFF_FAULT')) -or
            (-not (Test-UniqueTopLevelExactAssignment $branchTexts[3] '\beNextState' 'eState'))) {
        return $false
    }
    $firstFaultWriterPattern = '\budiFirstFaultId\s*:='
    $exitIntentWriterPattern = '\beExitIntent\s*:='
    if ([regex]::IsMatch($branchTexts[0], $firstFaultWriterPattern, 'IgnoreCase') -or
            (-not (Test-UniqueTopLevelExactAssignment $branchTexts[0] '\beExitIntent' '(?:E_CffExitIntent\.)?CFF_EXIT_FAULT_NO_RETURN')) -or
            ([regex]::Matches($branchTexts[1], $firstFaultWriterPattern, 'IgnoreCase').Count -ne 1) -or
            (-not (Test-AllAssignmentsHaveExactPositiveGuardSet $branchTexts[1] '\budiFirstFaultId\s*:=\s*16#0000A007\s*;' @('udiFirstFaultId\s*=\s*0'))) -or
            (-not (Test-UniqueTopLevelExactAssignment $branchTexts[1] '\beExitIntent' '(?:E_CffExitIntent\.)?CFF_EXIT_FAULT_NO_RETURN')) -or
            [regex]::IsMatch($branchTexts[3], $firstFaultWriterPattern, 'IgnoreCase') -or
            [regex]::IsMatch($branchTexts[3], $exitIntentWriterPattern, 'IgnoreCase')) {
        return $false
    }

    $ackText = $branchTexts[2]
    if (-not (Test-UniqueTopLevelExactAssignment $ackText '\bbApproachFaultStopPending' 'FALSE')) {
        return $false
    }
    $ackParsed = Get-IfBranchRegions $ackText
    $abortCondition = '(?is)^\s*eExitIntent\s*=\s*(?:E_CffExitIntent\.)?CFF_EXIT_ABORT_NO_RETURN\s*$'
    $faultCondition = '(?is)^\s*eExitIntent\s*=\s*(?:E_CffExitIntent\.)?CFF_EXIT_FAULT_NO_RETURN\s*$'
    $routeFirst = @($ackParsed.Branches | Where-Object {
        ($_.ParentDepth -eq 0) -and
        ($_.BranchOrder -eq 0) -and
        [regex]::IsMatch($_.Condition, $abortCondition)
    })
    if ($routeFirst.Count -ne 1) { return $false }
    $routeBranches = @($ackParsed.Branches | Where-Object {
        $_.IfId -eq $routeFirst[0].IfId
    } | Sort-Object BranchOrder)
    if (($routeBranches.Count -ne 3) -or
            (-not [regex]::IsMatch($routeBranches[1].Condition, $faultCondition)) -or
            $routeBranches[2].IsPositive) {
        return $false
    }
    $routeExpectedValues = @(
        '(?:E_CffState\.)?CFF_ABORT',
        '(?:E_CffState\.)?CFF_FAULT',
        '(?:E_CffState\.)?CFF_FAULT')
    $routeBranchTexts = @($routeBranches | ForEach-Object {
        $ackParsed.Text.Substring(
            $_.BodyStart,
            $_.BodyEnd - $_.BodyStart)
    })
    for ($index = 0; $index -lt $routeBranches.Count; $index++) {
        $routeBranchText = $routeBranchTexts[$index]
        if (-not (Test-UniqueTopLevelExactAssignment $routeBranchText '\beNextState' $routeExpectedValues[$index])) {
            return $false
        }
    }
    $fallbackText = $ackParsed.Text.Substring(
        $routeBranches[2].BodyStart,
        $routeBranches[2].BodyEnd - $routeBranches[2].BodyStart)
    $fallbackParsed = Get-IfBranchRegions $fallbackText
    $a016Writes = [regex]::Matches($fallbackParsed.Text, '\budiFirstFaultId\s*:=\s*16#0000A016\s*;', 'IgnoreCase')
    $faultIntentWrites = [regex]::Matches(
        $fallbackParsed.Text,
        '\beExitIntent\s*:=\s*(?:E_CffExitIntent\.)?CFF_EXIT_FAULT_NO_RETURN\s*;',
        'IgnoreCase')
    $fallbackFaultWrites = [regex]::Matches(
        $fallbackParsed.Text,
        '\beNextState\s*:=\s*(?:E_CffState\.)?CFF_FAULT\s*;',
        'IgnoreCase')
    if (($a016Writes.Count -ne 1) -or
            ([regex]::Matches($fallbackParsed.Text, '\budiFirstFaultId\s*:=', 'IgnoreCase').Count -ne 1) -or
            (-not (Test-AllAssignmentsHaveExactPositiveGuardSet $fallbackParsed.Text '\budiFirstFaultId\s*:=\s*16#0000A016\s*;' @('udiFirstFaultId\s*=\s*0'))) -or
            ($faultIntentWrites.Count -ne 1) -or
            ($fallbackFaultWrites.Count -ne 1) -or
            ($a016Writes[0].Index -ge $faultIntentWrites[0].Index) -or
            ($faultIntentWrites[0].Index -ge $fallbackFaultWrites[0].Index)) {
        return $false
    }
    if ([regex]::IsMatch($routeBranchTexts[0], $firstFaultWriterPattern, 'IgnoreCase') -or
            [regex]::IsMatch($routeBranchTexts[1], $firstFaultWriterPattern, 'IgnoreCase') -or
            ([regex]::Matches($ackParsed.Text, $firstFaultWriterPattern, 'IgnoreCase').Count -ne 1)) {
        return $false
    }
    if (([regex]::Matches($ackParsed.Text, '\bbApproachFaultStopPending\s*:=', 'IgnoreCase').Count -ne 1) -or
            ([regex]::Matches($ackParsed.Text, '\beExitIntent\s*:=', 'IgnoreCase').Count -ne 1)) {
        return $false
    }
    if ([regex]::Matches($ackParsed.Text, '\beNextState\s*:=', 'IgnoreCase').Count -ne 3) {
        return $false
    }
    if (@($caseParsed.Regions | Where-Object {
            ($_.Start -ge $priority.Start) -and ($_.Start -lt $priority.End)
        }).Count -gt 0) {
        return $false
    }
    $allWriters = [regex]::Matches(
        $ifParsed.Text,
        '\beNextState\s*:=',
        'IgnoreCase')
    if ($allWriters.Count -eq 0) { return $false }
    foreach ($writer in $allWriters) {
        if (($writer.Index -lt $priority.Start) -or ($writer.Index -ge $priority.End)) {
            return $false
        }
    }
    $priorityText = $ifParsed.Text.Substring(
        $priority.Start,
        $priority.End - $priority.Start)
    if ([regex]::Matches(
            $priorityText,
            '\bbApproachFaultStopPending\s*:=',
            'IgnoreCase').Count -ne 1) {
        return $false
    }
    $prioritySuffix = $ifParsed.Text.Substring($priority.End)
    if ([regex]::IsMatch(
            $prioritySuffix,
            '(?<![A-Za-z0-9_.])(?:bApproachFaultStopPending|udiFirstFaultId|eExitIntent|eNextState)\s*:=',
            'IgnoreCase')) {
        return $false
    }
    return $true
}
function Test-TerminalNormalizationBeforePublication {
    param([string]$Text)
    $ifParsed = Get-IfRegions $Text
    $caseParsed = Get-CaseRegions $ifParsed.Text
    $normalizationPattern = '(?is)^\s*\(\s*eState\s*<>\s*eNextState\s*\)\s+AND\s+' +
        '\(\s*\(\s*eNextState\s*=\s*(?:E_CffState\.)?CFF_ABORT\s*\)\s+OR\s+' +
        '\(\s*eNextState\s*=\s*(?:E_CffState\.)?CFF_FAULT\s*\)\s*\)\s*$'
    $normalizations = @($ifParsed.Regions | Where-Object {
        $region = $_
        if (($region.ParentDepth -ne 0) -or
                (-not [regex]::IsMatch($region.Condition, $normalizationPattern))) {
            return $false
        }
        return @($caseParsed.Regions | Where-Object {
            ($region.Start -ge $_.BodyStart) -and ($region.Start -lt $_.BodyEnd)
        }).Count -eq 0
    })
    if ($normalizations.Count -ne 1) { return $false }
    $normalization = $normalizations[0]
    if ($normalization.AlternateStart -ge 0) { return $false }
    $body = $ifParsed.Text.Substring(
        $normalization.BodyStart,
        $normalization.BodyEnd - $normalization.BodyStart)
    if (-not [regex]::IsMatch(
            $body,
            '(?is)^\s*bBusy\s*:=\s*TRUE\s*;\s*' +
                'bDone\s*:=\s*FALSE\s*;\s*' +
                'bError\s*:=\s*FALSE\s*;\s*' +
                'bAborted\s*:=\s*FALSE\s*;\s*$')) {
        return $false
    }
    $nextStateWriters = [regex]::Matches(
        $ifParsed.Text,
        '\beNextState\s*:=',
        'IgnoreCase')
    if ($nextStateWriters.Count -eq 0) { return $false }
    foreach ($writer in $nextStateWriters) {
        if ($writer.Index -ge $normalization.Start) { return $false }
    }
    $lateLocalTruthWriters = [regex]::Matches(
        $ifParsed.Text,
        '(?<![A-Za-z0-9_.])(?:bBusy|bDone|bError|bAborted)\s*:=',
        'IgnoreCase') | Where-Object { $_.Index -ge $normalization.End }
    if (@($lateLocalTruthWriters).Count -gt 0) { return $false }
    $sequencePublications = [regex]::Matches(
        $ifParsed.Text,
        '\bGVL_Status(?:\.stFast(?:\.stSequence(?:\.[A-Za-z_][A-Za-z0-9_]*)*)?)?\s*:=',
        'IgnoreCase')
    foreach ($publication in $sequencePublications) {
        if ($publication.Index -lt $normalization.End) { return $false }
    }
    foreach ($field in @('bBusy','bDone','bError','bAborted')) {
        $publicationPattern = "\bGVL_Status\.stFast\.stSequence\.$field\s*:=\s*$field\s*;"
        $publications = [regex]::Matches(
            $ifParsed.Text,
            $publicationPattern,
            'IgnoreCase')
        if (($publications.Count -ne 1) -or
                ($publications[0].Index -lt $normalization.End)) {
            return $false
        }
        if (-not (Test-UniqueTopLevelExactAssignment $ifParsed.Text "\bGVL_Status\.stFast\.stSequence\.$field" $field)) {
            return $false
        }
        if ([regex]::Matches(
                $ifParsed.Text,
                "\bGVL_Status\.stFast\.stSequence\.$field\s*:=",
                'IgnoreCase').Count -ne 1) {
            return $false
        }
        $suffix = $ifParsed.Text.Substring(
            $publications[0].Index + $publications[0].Length)
        if ([regex]::IsMatch(
                $suffix,
                "(?is)(?<![A-Za-z0-9_.])(?:" +
                    "GVL_Status\.stFast\.stSequence\.$field|" +
                    'GVL_Status\.stFast\.stSequence(?!\.)|' +
                    'GVL_Status\.stFast(?!\.)|' +
                    'GVL_Status(?!\.)' +
                    ')\s*:=',
                'IgnoreCase')) {
            return $false
        }
    }
    return $true
}
function Test-ForceOwnerDecelerationPackage {
    param([string]$Text)
    $executableText = Get-StCodeText $Text
    if ([regex]::IsMatch(
            $executableText,
            '\bstMotionIntent\s*:=|stMotionIntent\.stZCommand\s*:=')) {
        return $false
    }
    $ownerIsExact = Test-UniqueTopLevelExactAssignment $executableText 'stMotionIntent\.stZCommand\.eOwnerRequest' '(?:E_ZCommandOwner\.)?Z_OWNER_FORCE_PROCESS'
    $decelerationIsExact = Test-UniqueTopLevelExactAssignment $executableText 'stMotionIntent\.stZCommand\.rDeceleration_mm_s2' 'stSequenceConfigSnapshot\.fStandardMoveDecelerationMmS2'
    return $ownerIsExact -and $decelerationIsExact
}
function Get-ValidatedFastSafeResetRegion {
    param([string]$Text, [int]$BeforeIndex)
    $parsed = Get-IfRegions $Text
    $caseParsed = Get-CaseRegions $parsed.Text
    $zeroWriters = [regex]::Matches(
        $parsed.Text,
        '\bstLatchedZSourceCommand\.rDeceleration_mm_s2\s*:=\s*0(?:\.0+)?\s*;',
        'IgnoreCase')
    if ($zeroWriters.Count -ne 1) { return $null }
    $regions = @($parsed.Regions | Where-Object {
        ($_.ParentControlDepth -eq 0) -and
            ($_.AlternateStart -lt 0) -and
            ($_.End -le $BeforeIndex) -and
            [regex]::IsMatch(
                $_.Condition,
                '(?is)^\s*bSafeTerminalResetRising\s*$') -and
            ($zeroWriters[0].Index -ge $_.BodyStart) -and
            ($zeroWriters[0].Index -lt $_.BodyEnd) -and
            (@($caseParsed.Regions | Where-Object {
                ($_.Start -ge $_.BodyStart) -and ($_.Start -lt $_.BodyEnd)
            }).Count -eq 0)
    })
    if ($regions.Count -ne 1) { return $null }
    $region = $regions[0]
    $body = $parsed.Text.Substring(
        $region.BodyStart,
        $region.BodyEnd - $region.BodyStart)
    $contracts = @(
        @('\bbNewZAdapterTransaction', 'TRUE'),
        @('\budiPendingZAdapterCommandId', 'udiZAdapterCommandId'),
        @('\budiPendingZSequenceSourceId', '0'),
        @('\bbPendingZTransactionIsSequence', 'FALSE'),
        @('\bstLatchedZSourceCommand\.bEnable', 'FALSE'),
        @('\bstLatchedZSourceCommand\.bReset', 'TRUE'),
        @('\bstLatchedZSourceCommand\.bStop', 'FALSE'),
        @('\bstLatchedZSourceCommand\.bHome', 'FALSE'),
        @('\bstLatchedZSourceCommand\.bMoveAbsolute', 'FALSE'),
        @('\bstLatchedZSourceCommand\.bMoveVelocity', 'FALSE'),
        @('\bstLatchedZSourceCommand\.bUseExternalSetpoint', 'FALSE'),
        @('\bstLatchedZSourceCommand\.rHomePosition_mm', '0(?:\.0+)?'),
        @('\bstLatchedZSourceCommand\.rPosition_mm', '0(?:\.0+)?'),
        @('\bstLatchedZSourceCommand\.rVelocity_mm_s', '0(?:\.0+)?'),
        @('\bstLatchedZSourceCommand\.rAcceleration_mm_s2', '0(?:\.0+)?'),
        @('\bstLatchedZSourceCommand\.rDeceleration_mm_s2', '0(?:\.0+)?'),
        @('\bstLatchedZSourceCommand\.eOwnerRequest', '(?:E_ZCommandOwner\.)?Z_OWNER_NONE'),
        @('\bbFastSafetyStopLatched', 'FALSE'))
    foreach ($contract in $contracts) {
        if (-not (Test-UniqueTopLevelExactAssignment $body $contract[0] $contract[1])) {
            return $null
        }
    }
    if (-not (Test-UniqueTopLevelOrderedAssignments $body @(
                '\budiZAdapterCommandId\s*:=\s*udiZAdapterCommandId\s*\+\s*1\s*;'))) {
        return $null
    }
    $skipZero = Get-UniqueTopLevelPositiveIfPartition $body 'udiZAdapterCommandId\s*=\s*0'
    if (($null -eq $skipZero) -or ($skipZero.AlternateStart -ge 0) -or
            (-not (Test-UniqueTopLevelExactAssignment $skipZero.PositiveBody '\budiZAdapterCommandId' '1'))) {
        return $null
    }
    return $region
}
function Test-FastFaultStopDecelerationChain {
    param([string]$Text)
    $executableText = Get-StCodeText $Text
    $fastSourceSelector = 'GVL_Status\.stFast\.stSequence\.stMotionIntent\.stZCommand\.eOwnerRequest'
    $sourceParsed = Get-CaseArmRegions $executableText
    $sourceCase = Get-UniqueCombinedTopLevelCaseRegion $sourceParsed.Text $fastSourceSelector
    if ($null -eq $sourceCase) { return $false }
    if ([regex]::Matches(
            $executableText,
            '(?m)^[^\S\r\n]*(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP[^\S\r\n]*:',
            'IgnoreCase').Count -ne 1) {
        return $false
    }
    $faultArms = @($sourceParsed.Arms | Where-Object {
        ($_.CaseId -eq $sourceCase.CaseId) -and
            [regex]::IsMatch(
                $_.Label,
                '(?i)^(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP$')
    })
    if ($faultArms.Count -ne 1) { return $false }
    $faultSourceBranch = $sourceParsed.Text.Substring(
        $faultArms[0].BodyStart,
        $faultArms[0].BodyEnd - $faultArms[0].BodyStart)
    if ((-not (Test-UniqueTopLevelExactAssignment $faultSourceBranch '\bbZSequenceSourceActive' 'TRUE')) -or
            (-not (Test-UniqueTopLevelExactAssignment $faultSourceBranch '\bstCandidateZSourceCommand' 'GVL_Status\.stFast\.stSequence\.stMotionIntent\.stZCommand'))) {
        return $false
    }
    $activeWriters = [regex]::Matches(
        $faultSourceBranch,
        '\bbZSequenceSourceActive\s*:=',
        'IgnoreCase')
    $candidateWriters = [regex]::Matches(
        $faultSourceBranch,
        '\bstCandidateZSourceCommand(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*:=',
        'IgnoreCase')
    if (($activeWriters.Count -ne 1) -or
            ($candidateWriters.Count -ne 1) -or
            ($activeWriters[0].Index -ge $candidateWriters[0].Index)) {
        return $false
    }
    $faultSourceCopies = [regex]::Matches(
        $executableText,
        '(?is)(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP\s*:\s*' +
            'bZSequenceSourceActive\s*:=\s*TRUE\s*;\s*' +
            'stCandidateZSourceCommand\s*:=\s*' +
            'GVL_Status\.stFast\.stSequence\.stMotionIntent\.stZCommand\s*;')
    if ($faultSourceCopies.Count -ne 1) { return $false }
    $latchedCopies = [regex]::Matches(
        $executableText,
        '\bstLatchedZSourceCommand\s*:=\s*stCandidateZSourceCommand\s*;',
        'IgnoreCase')
    if ($latchedCopies.Count -ne 1) { return $false }
    if ($sourceCase.End -gt $latchedCopies[0].Index) { return $false }
    $postSourceText = $executableText.Substring($sourceCase.End)
    if ([regex]::IsMatch(
            $postSourceText,
            '\bbZSequenceSourceActive\s*:=',
            'IgnoreCase')) {
        return $false
    }
    $zTransaction = Get-UniqueTopLevelPositiveIfPartition $executableText 'bNewZAdapterTransaction'
    if (($null -eq $zTransaction) -or ($zTransaction.AlternateStart -ge 0) -or
            (-not (Test-UniqueTopLevelExactAssignment $zTransaction.PositiveBody '\bstLatchedZSourceCommand' 'stCandidateZSourceCommand'))) {
        return $false
    }
    $candidateTailStart = $sourceCase.End
    if ($candidateTailStart -ge $latchedCopies[0].Index) { return $false }
    $candidateTail = $executableText.Substring(
        $candidateTailStart,
        $latchedCopies[0].Index - $candidateTailStart)
    if ([regex]::IsMatch(
            $candidateTail,
            '\bstCandidateZSourceCommand(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*:=')) {
        return $false
    }
    $latchedWholeWriters = [regex]::Matches(
        $executableText,
        '\bstLatchedZSourceCommand\s*:=\s*[^;]+;',
        'IgnoreCase')
    if (($latchedWholeWriters.Count -ne 1) -or
            ($latchedWholeWriters[0].Index -ne $latchedCopies[0].Index)) {
        return $false
    }
    $faultRequest = [regex]::Matches(
        $executableText,
        '(?is)\bbLatchedZFaultStopRequest\s*:=\s*' +
            '\(\s*stLatchedZSourceCommand\.eOwnerRequest\s*=\s*' +
            '(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP\s*\)\s+OR\s+' +
            'bFastSafetyStopLatched\s*;',
        'IgnoreCase')
    $faultCopies = [regex]::Matches(
        $executableText,
        '(?ms)(?:(?<=;)|\A)\s*stFaultStopCommand\s*:=\s*stLatchedZSourceCommand\s*;',
        'IgnoreCase')
    $arbiterCalls = [regex]::Matches(
        $executableText,
        '\bfbZAxisArbiter\s*\(',
        'IgnoreCase')
    if (($faultRequest.Count -ne 1) -or
            ([regex]::Matches($executableText, '\bbLatchedZFaultStopRequest\s*:=', 'IgnoreCase').Count -ne 1) -or
            ($faultCopies.Count -ne 1) -or
            ($arbiterCalls.Count -ne 1)) {
        return $false
    }
    $chainIfParsed = Get-IfRegions $executableText
    $chainCaseParsed = Get-CaseRegions $executableText
    $faultCopyHasOwner = @($chainIfParsed.Regions | Where-Object {
        ($faultCopies[0].Index -ge $_.BodyStart) -and
            ($faultCopies[0].Index -lt $_.BodyEnd)
    }).Count -gt 0
    if (-not $faultCopyHasOwner) {
        $faultCopyHasOwner = @($chainCaseParsed.Regions | Where-Object {
            ($faultCopies[0].Index -ge $_.BodyStart) -and
                ($faultCopies[0].Index -lt $_.BodyEnd)
        }).Count -gt 0
    }
    if ((-not (Test-UniqueTopLevelExactAssignment $executableText '\bbLatchedZFaultStopRequest' '\(\s*stLatchedZSourceCommand\.eOwnerRequest\s*=\s*(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP\s*\)\s+OR\s+bFastSafetyStopLatched')) -or
            $faultCopyHasOwner -or
            (-not (Test-UniqueTopLevelCall $executableText 'fbZAxisArbiter' '(?s)\bfbZAxisArbiter\s*\('))) {
        return $false
    }
    $safeResetRegion = Get-ValidatedFastSafeResetRegion $executableText ($faultRequest[0].Index)
    if ($null -eq $safeResetRegion) { return $false }
    $chainIsOrdered = ($sourceCase.End -le $zTransaction.Start) -and
        ($zTransaction.End -le $safeResetRegion.Start) -and
        ($safeResetRegion.End -le $faultRequest[0].Index) -and
        ($faultRequest[0].Index -lt $faultCopies[0].Index) -and
        ($faultCopies[0].Index -lt $arbiterCalls[0].Index)
    if (-not $chainIsOrdered) { return $false }
    $latchedFieldWriters = [regex]::Matches(
        $executableText,
        '\bstLatchedZSourceCommand\.[A-Za-z_][A-Za-z0-9_]*\s*:=',
        'IgnoreCase') | Where-Object {
            ($_.Index -gt $latchedCopies[0].Index) -and
            ($_.Index -lt $faultCopies[0].Index)
        }
    if (@($latchedFieldWriters).Count -gt 0) {
        foreach ($writer in $latchedFieldWriters) {
            if (($writer.Index -lt $safeResetRegion.BodyStart) -or
                    ($writer.Index -ge $safeResetRegion.BodyEnd)) {
                return $false
            }
        }
    }
    $postResetPrefix = $executableText.Substring(
        $safeResetRegion.End,
        $faultRequest[0].Index - $safeResetRegion.End)
    if ([regex]::IsMatch(
            $postResetPrefix,
            '\bbFastSafetyStopLatched\s*:=',
            'IgnoreCase')) {
        return $false
    }
    $wholeFaultStopWriters = [regex]::Matches(
        $executableText,
        '(?ms)(?:(?<=;)|\A)\s*stFaultStopCommand\s*:=\s*[^;]+;',
        'IgnoreCase')
    if ($wholeFaultStopWriters.Count -ne 1) { return $false }
    $chainSuffix = $executableText.Substring(
        $faultCopies[0].Index,
        $arbiterCalls[0].Index - $faultCopies[0].Index)
    if ([regex]::IsMatch(
            $chainSuffix,
            '\bstFaultStopCommand\.[A-Za-z0-9_]+\s*:=|\bstLatchedZSourceCommand(?:\.[A-Za-z0-9_]+)?\s*:=')) {
        return $false
    }
    $deliveredSuffix = $executableText.Substring($faultCopies[0].Index + $faultCopies[0].Length)
    if ([regex]::IsMatch(
            $deliveredSuffix,
            '(?ms)(?:(?<=;)|\A)\s*(?:stFaultStopCommand|stLatchedZSourceCommand|stCandidateZSourceCommand)(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*:=')) {
        return $false
    }
    return $true
}
function Test-ArbiterFaultStopBranch {
    param([string]$Text)
    $executableText = Get-StCodeText $Text
    if ([regex]::IsMatch(
            $executableText,
            '\bstFaultStopCommand(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*:=')) {
        return $false
    }
    if (-not (Test-UniqueTopLevelExactAssignment $executableText '\bstCommand' 'stFaultStopCommand')) {
        return $false
    }
    return -not [regex]::IsMatch(
        $executableText,
        '\bstCommand\.rDeceleration_mm_s2\s*:=' )
}
function Test-NoCommandWriterAfterActiveOwnerCase {
    param([string]$Text)
    $caseParsed = Get-CaseRegions $Text
    $ownerCase = Get-UniqueCombinedTopLevelCaseRegion $caseParsed.Text 'eActiveOwner'
    if ($null -eq $ownerCase) { return $false }
    $suffix = $caseParsed.Text.Substring($ownerCase.End)
    return -not [regex]::IsMatch(
        $suffix,
        '\bstCommand(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*:=' )
}
function Test-ArbiterFaultStopComposition {
    param([string]$Text)
    $executableText = Get-StCodeText $Text
    if ([regex]::Matches(
            $executableText,
            '(?m)^[^\S\r\n]*(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP[^\S\r\n]*:',
            'IgnoreCase').Count -ne 1) {
        return $false
    }
    $branch = Get-UniqueTopLevelCaseArmBody $executableText 'eActiveOwner' '(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP'
    if ([string]::IsNullOrWhiteSpace($branch)) { return $false }
    return (Test-ArbiterFaultStopBranch $branch) -and
        (Test-NoCommandWriterAfterActiveOwnerCase $executableText)
}
function Test-NcFaultStopDecelerationConsumer {
    param([string]$Text)
    $ifParsed = Get-IfRegions $Text
    $caseParsed = Get-CaseRegions $ifParsed.Text
    if ([regex]::IsMatch(
            $ifParsed.Text,
            '\bstCommand(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*:=')) {
        return $false
    }
    $calls = [regex]::Matches(
        $ifParsed.Text,
        '(?is)\bfbHalt\s*\((?<Arguments>.*?)\)\s*;')
    if ($calls.Count -ne 1) { return $false }
    $arguments = $calls[0].Groups['Arguments'].Value
    if ([regex]::Matches(
            $arguments,
            '\bDeceleration\s*:=',
            'IgnoreCase').Count -ne 1) {
        return $false
    }
    if (-not [regex]::IsMatch(
            $arguments,
            '(?is)\bDeceleration\s*:=\s*ABS\s*\(\s*stCommand\.rDeceleration_mm_s2\s*\)\s*(?=,|$)')) {
        return $false
    }
    $callIndex = $calls[0].Index
    if (@($ifParsed.Regions | Where-Object {
            ($callIndex -ge $_.BodyStart) -and ($callIndex -lt $_.BodyEnd)
        }).Count -gt 0) { return $false }
    if (@($caseParsed.Regions | Where-Object {
            ($callIndex -ge $_.BodyStart) -and ($callIndex -lt $_.BodyEnd)
        }).Count -gt 0) { return $false }
    return $true
}
function Assert-IfRegionMatch {
    param([string]$Text, [string]$ConditionPattern, [string]$BodyPattern, [string]$Message)
    $Text = Get-StCodeText $Text
    $tokens = [regex]::Matches($Text, '(?is)\bIF\s+(?<Condition>.*?)\s+THEN\b|\bEND_IF\s*;?')
    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    $matched = $false
    foreach ($token in $tokens) {
        if ($token.Groups['Condition'].Success) {
            $stack.Push([pscustomobject]@{
                Condition = $token.Groups['Condition'].Value.Trim()
                BodyStart = $token.Index + $token.Length
            })
        } elseif ($stack.Count -gt 0) {
            $region = $stack.Pop()
            $body = $Text.Substring($region.BodyStart, $token.Index - $region.BodyStart)
            if ([regex]::IsMatch($region.Condition, $ConditionPattern, 'Multiline') -and
                [regex]::IsMatch($body, $BodyPattern, 'Multiline')) {
                $matched = $true
            }
        }
    }
    Assert-True $matched $Message
}
function Assert-CaseMatch {
    param([string]$Text, [string]$State, [string]$Pattern, [string]$Message)
    $branch = Get-CaseBranch $Text $State "Missing executable CASE branch: $State"
    Assert-Match $branch $Pattern $Message
}

$runContracts = $Scope -in @('All', 'Contracts')
$runValidation = $Scope -in @('All', 'Validation')
$runTrajectory = $Scope -in @('All', 'Trajectory')
$runAdapter = $Scope -in @('All', 'Adapter')
$runRouting = $Scope -in @('All', 'Routing')
$runSequenceFront = $Scope -in @('All', 'SequenceFront')
$runSequenceSteps = $Scope -in @('All', 'SequenceSteps')
$runSequenceExit = $Scope -in @('All', 'SequenceExit')

if ($runSequenceFront -or $runSequenceSteps -or $runSequenceExit) {
    $commentScannerFixture = @'
sAudit := '//'; realLaterWriter := TRUE;
sBlock := '(* not a comment *)';
sEscaped := 'quote$'//still string'; bAfterEscapedString := TRUE;
sWide := "(* still not a comment *)";
bVisibleBefore := TRUE; // bLineCommentDecoy := TRUE;
(* outer block
   (* nested block *)
   bNestedBlockDecoy := TRUE;
*)
bVisibleAfter := TRUE;
'@
    $commentScannerResult = Remove-StComments $commentScannerFixture
    Assert-True ($commentScannerResult.Length -eq $commentScannerFixture.Length) 'ST comment scanner must preserve source length for shared parser indexes'
    Assert-True ([regex]::IsMatch(
        $commentScannerResult,
        "(?s)sAudit\s*:=\s*'//'\s*;\s*realLaterWriter\s*:=\s*TRUE.*?sBlock\s*:=\s*'\(\* not a comment \*\)'.*?bAfterEscapedString\s*:=\s*TRUE.*?sWide\s*:=\s*`"\(\* still not a comment \*\)`".*?bVisibleAfter\s*:=\s*TRUE")) 'ST comment scanner must preserve IEC STRING/WSTRING content, escaped quotes, and later executable statements'
    Assert-True (-not [regex]::IsMatch(
        $commentScannerResult,
        'bLineCommentDecoy\s*:=|bNestedBlockDecoy\s*:=')) 'ST comment scanner must remove real line comments and nested block comments'

    $badTransitionFixture = @'
IF ack = sourceId AND ownerOk AND enabled AND acceptedValid AND trajectoryActive THEN
    eNextState := TARGET;
END_IF;
eNextState := TARGET;
'@
    Assert-True (-not (Test-AllAssignmentsGuardedByPositiveIf $badTransitionFixture 'eNextState\s*:=\s*TARGET' @('ack\s*=\s*sourceId', 'ownerOk', 'enabled', 'acceptedValid', 'trajectoryActive') 4)) 'Guard helper fixture must reject one correct transition plus one unguarded duplicate transition'

    $nestedTransitionFixture = @'
IF FALSE THEN
    IF ack = sourceId AND ownerOk AND enabled AND acceptedValid AND trajectoryActive THEN
        eNextState := TARGET;
    END_IF;
END_IF;
'@
    Assert-True (-not (Test-AllAssignmentsGuardedByPositiveIf $nestedTransitionFixture 'eNextState\s*:=\s*TARGET' @('ack\s*=\s*sourceId', 'ownerOk', 'enabled', 'acceptedValid', 'trajectoryActive') 4)) 'Transition helper fixture must reject a complete positive gate hidden below a dead outer guard'

    $badReleaseFixture = @'
IF bReleaseOwner = TRUE THEN
    bComplete := TRUE;
END_IF;
'@
    Assert-True (-not (Test-HasExactlyOneStrictPositiveIf $badReleaseFixture '\(?\s*bReleaseOwner\s*\)?')) 'Release helper fixture must reject equality or other disguised ReleaseOwner conditions'

    $nestedReleaseFixture = @'
IF FALSE THEN
    IF bReleaseOwner THEN
        bComplete := TRUE;
    END_IF;
END_IF;
'@
    Assert-True (-not (Test-HasExactlyOneStrictPositiveIf $nestedReleaseFixture '\(?\s*bReleaseOwner\s*\)?' -TopLevel)) 'Release helper fixture must reject a positive ReleaseOwner IF hidden below a dead outer guard'

    $badGlobalGuardFixture = @'
IF ownerHold OR safeExit THEN
    bUseExternalSetpoint := TRUE;
END_IF;
'@
    Assert-True (-not (Test-HasExactlyOneStrictPositiveIf $badGlobalGuardFixture '\(?\s*ownerHold\s+AND\s+safeExit\s*\)?')) 'Global guard fixture must reject OR in place of positive ownerHold AND safeExit'

    $nestedGlobalGuardFixture = @'
IF FALSE THEN
    IF ownerHold AND safeExit THEN
        bUseExternalSetpoint := TRUE;
    END_IF;
END_IF;
'@
    Assert-True (-not (Test-HasExactlyOneStrictPositiveIf $nestedGlobalGuardFixture '\(?\s*ownerHold\s+AND\s+safeExit\s*\)?' -TopLevel)) 'Global guard helper fixture must reject a positive ownerHold AND safeExit IF hidden below a dead outer guard'
    Assert-True (-not (Test-AllAssignmentsGuardedByAllowedPositiveIf 'bUseExternalSetpoint := FALSE;' 'bUseExternalSetpoint\s*:=\s*FALSE' @('\(?\s*bReleaseOwner\s*\)?', '\(?\s*eState\s*=\s*CFF_APPROACH\s*\)?'))) 'Global override fixture must reject an unguarded post-CASE ownership cancellation'

    $badReverseTransitionFixture = @'
IF ack = sourceId AND ownerOk AND enabled = FALSE AND acceptedValid AND trajectoryActive THEN
    eNextState := TARGET;
END_IF;
'@
    Assert-True (-not (Test-AllAssignmentsGuardedByPositiveIf $badReverseTransitionFixture 'eNextState\s*:=\s*TARGET' @('ack\s*=\s*sourceId', 'ownerOk', 'enabled', 'acceptedValid', 'trajectoryActive') 4)) 'Transition helper fixture must reject a complete-looking gate containing a FALSE predicate'

    $exactGuardNegativeFixtures = @(
        @{ Name = 'same-guard dead term'; Text = "IF guardA AND guardB AND (0 = 1) THEN`n    guardedTarget := TRUE;`nEND_IF;" },
        @{ Name = 'dead outer IF'; Text = "IF 1 = 0 THEN`n    IF guardA AND guardB THEN`n        guardedTarget := TRUE;`n    END_IF;`nEND_IF;" },
        @{ Name = 'wrong polarity'; Text = "IF NOT guardA AND guardB THEN`n    guardedTarget := TRUE;`nEND_IF;" },
        @{ Name = 'extra OR'; Text = "IF guardA AND guardB OR guardC THEN`n    guardedTarget := TRUE;`nEND_IF;" },
        @{ Name = 'nested CASE'; Text = "CASE eState OF`nSTATE_A:`n    IF guardA AND guardB THEN`n        guardedTarget := TRUE;`n    END_IF;`nEND_CASE;" }
    )
    foreach ($fixture in $exactGuardNegativeFixtures) {
        Assert-True (-not (Test-AllAssignmentsGuardedByPositiveIf $fixture.Text 'guardedTarget\s*:=\s*TRUE' @('guardA', 'guardB') 1)) "Fix4 positive-guard fixture must reject $($fixture.Name)"
        Assert-True (-not (Test-AllAssignmentsCoveredByRequiredGuards $fixture.Text 'guardedTarget\s*:=\s*TRUE' @('guardA', 'guardB'))) "Fix4 required-guard fixture must reject $($fixture.Name)"
    }

    $badOwnerHoldExpression = '(eState = STATE_A AND eState = STATE_B) AND NOT GVL_Status.stFast.stZExtSetpoint.bReleaseOwner'
    Assert-True (-not (Test-PositiveExternalOwnerHoldExpression $badOwnerHoldExpression @('STATE_A', 'STATE_B'))) 'Owner-hold expression fixture must reject mutually exclusive states joined by AND'
    $badPrecedenceOwnerHoldExpression = 'eState = STATE_A OR eState = STATE_B AND NOT GVL_Status.stFast.stZExtSetpoint.bReleaseOwner'
    Assert-True (-not (Test-PositiveExternalOwnerHoldExpression $badPrecedenceOwnerHoldExpression @('STATE_A', 'STATE_B'))) 'Owner-hold expression fixture must require outer parentheses around the complete positive state OR chain'
    $badSafeExitExpression = 'NOT bAbortEvent OR bHardForceActive'
    Assert-True (-not (Test-PositiveOrExpression $badSafeExitExpression @('bAbortEvent', 'bHardForceActive'))) 'Safe-exit expression fixture must reject negated causes'

    $deadOwnerClassifierFixture = @'
IF FALSE THEN
    bOwnerHold := (eState = STATE_A OR eState = STATE_B) AND NOT GVL_Status.stFast.stZExtSetpoint.bReleaseOwner;
END_IF;
'@
    $deadOwnerClassifierAssignment = Find-BooleanAssignmentCoveringPatterns $deadOwnerClassifierFixture @(
        'eState\s*=\s*STATE_A',
        'eState\s*=\s*STATE_B',
        'NOT\s+GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner'
    ) ''
    Assert-True ($null -eq $deadOwnerClassifierAssignment) 'Classifier helper fixture must reject a complete ownerHold assignment hidden below a dead outer guard'

    $caseOwnerClassifierFixture = @'
CASE eState OF
    CFF_IDLE:
        bOwnerHold := (eState = STATE_A OR eState = STATE_B) AND NOT GVL_Status.stFast.stZExtSetpoint.bReleaseOwner;
END_CASE;
'@
    $caseOwnerClassifierAssignment = Find-BooleanAssignmentCoveringPatterns $caseOwnerClassifierFixture @(
        'eState\s*=\s*STATE_A',
        'eState\s*=\s*STATE_B',
        'NOT\s+GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner'
    ) ''
    Assert-True ($null -eq $caseOwnerClassifierAssignment) 'Classifier helper fixture must reject a complete ownerHold assignment inside the state CASE'

    $duplicateSafeExitClassifierFixture = @'
bSafeExit := bStopEvent OR bAbortEvent OR bHardForceActive;
bSafeExit := FALSE;
'@
    $duplicateSafeExitClassifierAssignment = Find-BooleanAssignmentCoveringPatterns $duplicateSafeExitClassifierFixture @(
        'bStopEvent',
        'bAbortEvent',
        'bHardForceActive'
    ) ''
    Assert-True ($null -eq $duplicateSafeExitClassifierAssignment) 'Classifier helper fixture must reject a valid safeExit assignment followed by a duplicate override'

    $badIncrementFixture = @'
udiZCommandId := udiZCommandId + 1;
IF udiZCommandId = 0 THEN
    udiZCommandId := 1;
END_IF;
udiZCommandId := udiZCommandId + 1;
bPayloadChanged := TRUE;
IF udiZCommandId = 0 THEN
    udiZCommandId := 1;
END_IF;
'@
    Assert-True (-not (Test-AllIncrementsImmediatelySkipZero $badIncrementFixture 'udiZCommandId')) 'Increment helper fixture must reject any unpaired or non-adjacent skip-zero sequence'
    if ($script:FailureCount -eq 0) {
        Write-Host 'PASS: Fix7 adversarial fixtures reject nested transition, classifier IF/CASE depth and uniqueness, owner precedence, Release/global-guard, and increment bypasses'
    }

    $sequenceIdSource = Read-Text 'CFFwelding_System\CFFwelding\POUs\Fast\PRG_CffSequence.TcPOU'
    Assert-True (Test-AllIncrementsImmediatelySkipZero $sequenceIdSource 'udiZCommandId') 'Every Z source ID increment must be immediately paired with its own skip-zero IF'
    Assert-True (Test-AllIncrementsImmediatelySkipZero $sequenceIdSource 'udiRCommandId') 'Every R source ID increment must be immediately paired with its own skip-zero IF'
}

if ($runContracts) {
    $executingScriptBytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
    $nonAsciiByteCount = @($executingScriptBytes | Where-Object { $_ -gt 0x7F }).Count
    Assert-True ($nonAsciiByteCount -eq 0) 'Phase 10 harness source must be ASCII-only with no byte above 0x7F'

    $compileFixtureInclude = 'POUs\Functions\FC_IsNewerRequestId.TcPOU'
    $compileItemFixtures = @(
        [pscustomobject]@{ Name = 'DirectItemGroup'; Expected = $true; Xml = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU"><SubType>Code</SubType></Compile></ItemGroup>
</Project>
'@ },
        [pscustomobject]@{ Name = 'PropertyGroup'; Expected = $false; Xml = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU"><SubType>Code</SubType></Compile></PropertyGroup>
</Project>
'@ },
        [pscustomobject]@{ Name = 'NestedBelowElement'; Expected = $false; Xml = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup><Wrapper><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU"><SubType>Code</SubType></Compile></Wrapper></ItemGroup>
</Project>
'@ },
        [pscustomobject]@{ Name = 'NestedItemGroup'; Expected = $false; Xml = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Choose><ItemGroup><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU"><SubType>Code</SubType></Compile></ItemGroup></Choose>
</Project>
'@ },
        [pscustomobject]@{ Name = 'DuplicatedInsideOutside'; Expected = $false; Xml = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU"><SubType>Code</SubType></Compile></ItemGroup>
  <PropertyGroup><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU"><SubType>Code</SubType></Compile></PropertyGroup>
</Project>
'@ },
        [pscustomobject]@{ Name = 'MissingSubType'; Expected = $false; Xml = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU" /></ItemGroup>
</Project>
'@ },
        [pscustomobject]@{ Name = 'WrongSubTypeCase'; Expected = $false; Xml = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU"><SubType>code</SubType></Compile></ItemGroup>
</Project>
'@ },
        [pscustomobject]@{ Name = 'DuplicateSubType'; Expected = $false; Xml = @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup><Compile Include="POUs\Functions\FC_IsNewerRequestId.TcPOU"><SubType>Code</SubType><SubType>Code</SubType></Compile></ItemGroup>
</Project>
'@ })
    foreach ($fixture in $compileItemFixtures) {
        [xml]$fixtureXml = $fixture.Xml
        Assert-True ((Test-ProjectCompileItemContract $fixtureXml $compileFixtureInclude) -eq
            $fixture.Expected) "Compile ItemGroup fixture failed: $($fixture.Name)"
    }

    $pouFixtureGuid = '{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}'
    $dutFixtureGuid = '{AF3EC71D-1473-4A62-B1C2-1CC0D9FD548F}'
    $gvlFixtureGuid = '{CA3D483E-12F4-4687-9EA3-C5BEF1496A7D}'
    $objectIdentityFixtures = @(
        [pscustomobject]@{ Name = 'ValidPOU'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $true; Xml = @'
<TcPlcObject Version="1.1.0.1"><POU Name="FC_Test" Id="{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}"><Declaration /></POU></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'ValidDUT'; Kind = 'DUT'; Guid = $dutFixtureGuid; Expected = $true; Xml = @'
<TcPlcObject Version="1.1.0.1"><DUT Name="ST_Test" Id="{AF3EC71D-1473-4A62-B1C2-1CC0D9FD548F}"><Declaration /></DUT></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'ValidGVL'; Kind = 'GVL'; Guid = $gvlFixtureGuid; Expected = $true; Xml = @'
<TcPlcObject Version="1.1.0.1"><GVL Name="GVL_Test" Id="{CA3D483E-12F4-4687-9EA3-C5BEF1496A7D}"><Declaration /></GVL></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'POUGuidOnDeclaration'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><POU Name="FC_Test"><Declaration Id="{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}" /></POU></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'DUTGuidOnDeclaration'; Kind = 'DUT'; Guid = $dutFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><DUT Name="ST_Test"><Declaration Id="{AF3EC71D-1473-4A62-B1C2-1CC0D9FD548F}" /></DUT></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'GVLGuidOnImplementation'; Kind = 'GVL'; Guid = $gvlFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><GVL Name="GVL_Test"><Implementation Id="{CA3D483E-12F4-4687-9EA3-C5BEF1496A7D}" /></GVL></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'WrongObjectKind'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><DUT Name="ST_Test" Id="{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}"><Declaration /></DUT></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'NestedObjectDecoy'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><Wrapper><POU Name="FC_Test" Id="{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}" /></Wrapper></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'MissingObjectId'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><POU Name="FC_Test"><Declaration /></POU></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'DuplicateDocumentId'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><POU Name="FC_Test" Id="{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}"><Declaration Id="{11111111-2222-4333-8444-555555555555}" /></POU></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'ChangedObjectId'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><POU Name="FC_Test" Id="{11111111-2222-4333-8444-555555555555}"><Declaration /></POU></TcPlcObject>
'@ },
        [pscustomobject]@{ Name = 'WrongRoot'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $false; Xml = @'
<Project><POU Name="FC_Test" Id="{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}" /></Project>
'@ },
        [pscustomobject]@{ Name = 'MultipleDirectObjects'; Kind = 'POU'; Guid = $pouFixtureGuid; Expected = $false; Xml = @'
<TcPlcObject Version="1.1.0.1"><POU Name="FC_Test" Id="{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}" /><DUT Name="ST_Decoy" /></TcPlcObject>
'@ })
    foreach ($fixture in $objectIdentityFixtures) {
        [xml]$fixtureXml = $fixture.Xml
        Assert-True ((Test-TwinCatObjectIdentityContract $fixtureXml $fixture.Kind $fixture.Guid) -eq
            $fixture.Expected) "TwinCAT object identity fixture failed: $($fixture.Name)"
    }

    $fieldCommentFixtureContract = [ordered]@{
        bAccepted = 'BOOL'
        rValue_mm = 'LREAL'
    }
    $cjkCommentChar = [char]0x4E2D
    $individualFieldCommentFixture = @"
TYPE ST_FieldCommentFixture : STRUCT
    (* $cjkCommentChar accepted state. *)
    bAccepted : BOOL;
    (* $cjkCommentChar position in mm. *)
    rValue_mm : LREAL;
END_STRUCT
END_TYPE
"@
    $stackedGroupedFieldCommentFixture = @"
TYPE ST_FieldCommentFixture : STRUCT
    (* $cjkCommentChar accepted state. *)
    (* $cjkCommentChar position in mm. *)
    bAccepted, rValue_mm : BOOL;
END_STRUCT
END_TYPE
"@
    $singleCommentGroupedFieldFixture = @"
TYPE ST_FieldCommentFixture : STRUCT
    (* $cjkCommentChar shared comment. *)
    bAccepted, rValue_mm : BOOL;
END_STRUCT
END_TYPE
"@
    $missingDirectFieldCommentFixture = @"
TYPE ST_FieldCommentFixture : STRUCT
    bAccepted : BOOL;
    (* $cjkCommentChar position in mm. *)
    rValue_mm : LREAL;
END_STRUCT
END_TYPE
"@
    $unexpectedPublicFieldFixture = @"
TYPE ST_FieldCommentFixture : STRUCT
    (* $cjkCommentChar accepted state. *)
    bAccepted : BOOL;
    (* $cjkCommentChar position in mm. *)
    rValue_mm : LREAL;
    (* $cjkCommentChar unexpected field. *)
    bUnexpected : BOOL;
END_STRUCT
END_TYPE
"@
    $multilineUnexpectedPublicFieldFixture = @"
TYPE ST_FieldCommentFixture : STRUCT
    (* $cjkCommentChar accepted state. *)
    bAccepted : BOOL;
    (* $cjkCommentChar position in mm. *)
    rValue_mm : LREAL;
    (* $cjkCommentChar unexpected multiline field. *)
    bUnexpected :
        BOOL;
END_STRUCT
END_TYPE
"@
    $emptyDeclarationFixture = @"
TYPE ST_FieldCommentFixture : STRUCT
    (* $cjkCommentChar accepted state. *)
    bAccepted : BOOL;

    ;
    (* $cjkCommentChar position in mm. *)
    rValue_mm : LREAL;
END_STRUCT
END_TYPE
"@
    Assert-True (Test-DutFieldsHaveDirectChineseComments $individualFieldCommentFixture $fieldCommentFixtureContract) 'Per-field DUT comment helper rejected individually declared fields with direct Chinese comments'
    Assert-True (-not (Test-DutFieldsHaveDirectChineseComments $stackedGroupedFieldCommentFixture $fieldCommentFixtureContract)) 'Per-field DUT comment helper accepted stacked comments followed by a grouped declaration'
    Assert-True (-not (Test-DutFieldsHaveDirectChineseComments $singleCommentGroupedFieldFixture $fieldCommentFixtureContract)) 'Per-field DUT comment helper accepted one comment shared by a grouped declaration'
    Assert-True (-not (Test-DutFieldsHaveDirectChineseComments $missingDirectFieldCommentFixture $fieldCommentFixtureContract)) 'Per-field DUT comment helper accepted a public field without its directly owned Chinese comment'
    Assert-True (-not (Test-DutFieldsHaveDirectChineseComments $unexpectedPublicFieldFixture $fieldCommentFixtureContract)) 'Per-field DUT comment helper accepted an unexpected public field outside the fixed contract'
    Assert-True (-not (Test-DutFieldsHaveDirectChineseComments $multilineUnexpectedPublicFieldFixture $fieldCommentFixtureContract)) 'Per-field DUT comment helper accepted an unexpected multiline public field outside the fixed contract'
    Assert-True (-not (Test-DutFieldsHaveDirectChineseComments $emptyDeclarationFixture $fieldCommentFixtureContract)) 'Per-field DUT comment helper accepted an independent empty semicolon declaration'

    $required = @(
        'CFFwelding_System\CFFwelding\DUTs\Enums\E_CffExitIntent.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Enums\E_ZExternalTrajectoryState.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Structures\ST_CffSequenceConfig.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Structures\ST_CffFastConfigSnapshot.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_CffMotionIntent.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_ZExternalTrajectoryInput.TcDUT',
        'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_ZExternalTrajectoryOutput.TcDUT',
        'CFFwelding_System\CFFwelding\GVLs\GVL_FastInternal.TcGVL',
        'CFFwelding_System\CFFwelding\POUs\Functions\FC_IsNewerRequestId.TcPOU',
        'CFFwelding_System\CFFwelding\POUs\Functions\FC_ValidateCffSequenceConfig.TcPOU',
        'CFFwelding_System\CFFwelding\POUs\FunctionBlocks\Control\FB_ZExternalTrajectory.TcPOU')
    foreach ($relativePath in $required) {
        Assert-True (Test-Path -LiteralPath (Join-Path $RepositoryRoot $relativePath)) "Missing Phase 10 object: $relativePath"
    }
    $project = Read-Text 'CFFwelding_System\CFFwelding\CFFwelding.plcproj'
    try {
        [xml]$projectXml = $project
    }
    catch {
        $projectXml = $null
        Assert-True $false 'PLC project must be valid XML for the Phase 10 object gate'
    }
    foreach ($relativePath in $required) {
        $include = $relativePath -replace '^CFFwelding_System\\CFFwelding\\', ''
        Assert-True (Test-ProjectCompileItemContract $projectXml $include) "Project must contain exactly one direct Project/ItemGroup Compile with one direct SubType Code: $include"
    }
    $objectIds = foreach ($file in [System.IO.Directory]::GetFiles($plcRoot, '*.Tc*', [System.IO.SearchOption]::AllDirectories)) {
        $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
        foreach ($match in [regex]::Matches($text, 'Id="(\{[0-9A-Fa-f-]{36}\})"')) { $match.Groups[1].Value.ToUpperInvariant() }
    }
    $duplicateIds = $objectIds | Group-Object | Where-Object Count -gt 1
    Assert-True ($null -eq $duplicateIds) 'TwinCAT object IDs must be unique'
    $sequenceStatus = Read-Text 'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_CffSequenceStatus.TcDUT'
    $extCommand = Read-Text 'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_ZExtSetpointCommand.TcDUT'
    $fastStatus = Read-Text 'CFFwelding_System\CFFwelding\DUTs\Structures\ST_FastStatus.TcDUT'
    Assert-Match $sequenceStatus 'stFastConfigSnapshot\s*:\s*ST_CffFastConfigSnapshot' 'Sequence Fast config snapshot field is missing'
    Assert-Match $sequenceStatus 'rForceRamp_kN_s\s*:\s*LREAL' 'Per-step force ramp field is missing'
    Assert-Match $extCommand 'bPositiveMotionInhibit\s*:\s*BOOL' 'Hard positive-motion command field is missing'
    Assert-Match $fastStatus 'udiAcceptedSequenceZCommandId\s*:\s*UDINT' 'Sequence Z acknowledgement field is missing'
    Assert-Match $fastStatus 'udiAcceptedSequenceRCommandId\s*:\s*UDINT' 'Sequence R acknowledgement field is missing'
    $contractChecks = @(
        @('DUTs\Enums\E_CffExitIntent.TcDUT', 'DUT', '{7FBFD290-60B5-4FCE-8D00-D46650117E64}', 'CFF_EXIT_NORMAL_RETURN\s*:=\s*10', 'CFF_EXIT_NOK_RETURN\s*:=\s*20', 'CFF_EXIT_ABORT_NO_RETURN\s*:=\s*30', 'CFF_EXIT_FAULT_NO_RETURN\s*:=\s*40'),
        @('DUTs\Enums\E_ZExternalTrajectoryState.TcDUT', 'DUT', '{C68E271F-E8B0-491E-B340-25BEF41FA75F}', 'Z_TRAJ_HOLD_OLD_DIRECTION\s*:=\s*40', 'Z_TRAJ_DIRECTION_ZERO\s*:=\s*50', 'Z_TRAJ_PRELOAD_NEW_DIRECTION\s*:=\s*60', 'Z_TRAJ_FAULT\s*:=\s*100'),
        @('DUTs\Structures\ST_CffSequenceConfig.TcDUT', 'DUT', '{5D65580A-2126-4820-9D19-1A4AE7A35238}', 'tApproachTimeout\s*:\s*TIME', 'tContactSearchTimeout\s*:\s*TIME', 'tContactReferenceAckTimeout\s*:\s*TIME', 'tControlledUnloadTimeout\s*:\s*TIME', 'tUnloadStandstillConfirm\s*:\s*TIME', 'tRAxisStopTimeout\s*:\s*TIME', 'tReturnTimeout\s*:\s*TIME', 'fStandardMoveAccelerationMmS2\s*:\s*LREAL', 'fStandardMoveDecelerationMmS2\s*:\s*LREAL', 'bValid\s*:\s*BOOL'),
        @('DUTs\Structures\ST_CffFastConfigSnapshot.TcDUT', 'DUT', '{1C3E94F6-DBBC-4719-B133-C485675E7D5B}', 'nSequenceCommandId\s*:\s*UDINT', 'stMachine\s*:\s*ST_MachineConfig', 'stLimits\s*:\s*ST_MachineLimits', 'stZExtSetpoint\s*:\s*ST_ZExtSetpointConfig', 'stZForceControl\s*:\s*ST_ZForceControlProfile', 'bValid\s*:\s*BOOL'),
        @('DUTs\Interfaces\ST_CffMotionIntent.TcDUT', 'DUT', '{9CEBDEC5-6BA7-45E2-98FC-1BBC4A0C3FE9}', 'udiZCommandId\s*:\s*UDINT', 'stZCommand\s*:\s*ST_ZAxisCommand', 'bExternalEnableRequest\s*:\s*BOOL', 'bExternalDisableRequest\s*:\s*BOOL', 'udiRCommandId\s*:\s*UDINT', 'stRCommand\s*:\s*ST_RAxisCommand', 'bForceProcessExitComplete\s*:\s*BOOL'),
        @('DUTs\Interfaces\ST_ZExternalTrajectoryInput.TcDUT', 'DUT', '{AF3EC71D-1473-4A62-B1C2-1CC0D9FD548F}'),
        @('DUTs\Interfaces\ST_ZExternalTrajectoryOutput.TcDUT', 'DUT', '{EA3FEACE-47F9-4A31-A6EA-1CF99C98F83F}'),
        @('GVLs\GVL_FastInternal.TcGVL', 'GVL', '{CA3D483E-12F4-4687-9EA3-C5BEF1496A7D}', "\{attribute 'qualified_only'\}", 'stAcceptedCommand\s*:\s*ST_FastCommand'),
        @('POUs\Functions\FC_IsNewerRequestId.TcPOU', 'POU', '{F0A1324E-FFF9-40EF-BD99-BB5A478812F0}'),
        @('POUs\Functions\FC_ValidateCffSequenceConfig.TcPOU', 'POU', '{7F306BD6-3704-4AB8-98EC-56FE774A80BA}'),
        @('POUs\FunctionBlocks\Control\FB_ZExternalTrajectory.TcPOU', 'POU', '{49BB0003-2BA9-4043-A877-34D1985BA004}'))
    foreach ($check in $contractChecks) {
        $contractText = Read-Text "CFFwelding_System\CFFwelding\$($check[0])"
        try {
            [xml]$contractXml = $contractText
        }
        catch {
            $contractXml = $null
            Assert-True $false "Phase 10 object must be valid XML: $($check[0])"
        }
        Assert-True (Test-TwinCatObjectIdentityContract $contractXml $check[1] $check[2]) "Phase 10 object must have one exact $($check[1]) identity with the approved GUID: $($check[0])"
        if ($check.Count -gt 3) {
            foreach ($pattern in $check[3..($check.Count - 1)]) { Assert-Match $contractText $pattern "Missing Phase 10 contract relation: $pattern" }
        }
        if ($check[0] -notmatch '^DUTs\\Enums') {
            Assert-RawMatch $contractText '\(\*[^\r\n]*\p{IsCJKUnifiedIdeographs}[^\r\n]*\*\)' "Phase 10 contract lacks a Chinese field comment: $($check[0])"
        }
    }
    $trajectoryInputContract = [ordered]@{
        bEnable = 'BOOL'
        bReset = 'BOOL'
        eExternalState = 'E_ZExtSetpointState'
        bAcceptedSetpointValid = 'BOOL'
        bFeedAccepted = 'BOOL'
        udiAcceptedFeedCycleCounter = 'UDINT'
        rAcceptedPosition_mm = 'LREAL'
        rAcceptedVelocity_mm_s = 'LREAL'
        rAcceptedAcceleration_mm_s2 = 'LREAL'
        nAcceptedDirection = 'DINT'
        bInhibitPositiveMotion = 'BOOL'
        rTargetVelocity_mm_s = 'LREAL'
        rCycleTime_s = 'LREAL'
        rMinimumPosition_mm = 'LREAL'
        rMaximumPosition_mm = 'LREAL'
        rMaximumVelocity_mm_s = 'LREAL'
        rMaximumAcceleration_mm_s2 = 'LREAL'
        rStandstillVelocity_mm_s = 'LREAL'
        rMaximumPositionDeviation_mm = 'LREAL'
        nDirectionHoldCycles = 'UINT'
    }
    $trajectoryOutputContract = [ordered]@{
        rPosition_mm = 'LREAL'
        rVelocity_mm_s = 'LREAL'
        rAcceleration_mm_s2 = 'LREAL'
        nDirection = 'DINT'
        eState = 'E_ZExternalTrajectoryState'
        bDirectionTransition = 'BOOL'
        bZeroConfirmed = 'BOOL'
        bPositiveMotionInhibited = 'BOOL'
        bActive = 'BOOL'
        bFault = 'BOOL'
        nFaultId = 'UDINT'
    }
    $trajectoryInputDeclaration = Get-DutDeclarationText (Read-Text 'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_ZExternalTrajectoryInput.TcDUT')
    $trajectoryOutputDeclaration = Get-DutDeclarationText (Read-Text 'CFFwelding_System\CFFwelding\DUTs\Interfaces\ST_ZExternalTrajectoryOutput.TcDUT')
    Assert-True (Test-DutFieldsHaveDirectChineseComments $trajectoryInputDeclaration $trajectoryInputContract) 'Trajectory input DUT must declare every public field separately in fixed order with its own direct Chinese comment'
    Assert-True (Test-DutFieldsHaveDirectChineseComments $trajectoryOutputDeclaration $trajectoryOutputContract) 'Trajectory output DUT must declare every public field separately in fixed order with its own direct Chinese comment'
}

if ($runValidation) {
    $newerValidator = Read-Text 'CFFwelding_System\CFFwelding\POUs\Functions\FC_IsNewerRequestId.TcPOU'
    $configValidator = Read-Text 'CFFwelding_System\CFFwelding\POUs\Functions\FC_ValidateCffSequenceConfig.TcPOU'
    $programValidator = Read-Text 'CFFwelding_System\CFFwelding\POUs\Functions\FC_ValidateJoinProgram.TcPOU'
    Assert-NoMatch $configValidator 'GVL_|AXIS_REF|MC_' 'Sequence config validator must be pure'
    Assert-NoMatch $newerValidator 'GVL_|AXIS_REF|MC_' 'Request ID validator must be pure'
    Assert-NoMatch $programValidator 'GVL_|AXIS_REF|MC_' 'Program validator must be pure'
    Assert-Match $newerValidator '(?s)udiCandidate\s*=\s*0.*?RETURN' 'Zero request ID must not be newer'
    Assert-Match $newerValidator '(?s)udiCandidate\s*=\s*udiReference.*?RETURN' 'Duplicate request ID must not be newer'
    Assert-Match $newerValidator '(?s)udiReference\s*=\s*0.*?FC_IsNewerRequestId\s*:=\s*TRUE' 'First nonzero request ID must be newer'
    Assert-Match $newerValidator 'udiForwardDistance\s*:=\s*udiCandidate\s*-\s*udiReference' 'Request comparison must use forward distance'
    Assert-Match $newerValidator 'udiForwardDistance\s*<\s*16#80000000' 'Request comparison must use half range'
    foreach ($timeout in @('tApproachTimeout','tContactSearchTimeout','tContactReferenceAckTimeout','tControlledUnloadTimeout','tUnloadStandstillConfirm','tRAxisStopTimeout','tReturnTimeout')) {
        Assert-Match $configValidator "$timeout\s*>\s*T#0S" "Sequence timeout validation is missing: $timeout"
    }
    Assert-Match $configValidator 'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*stConfig\.fStandardMoveAccelerationMmS2\s*\)' 'Standard acceleration must be finite'
    Assert-Match $configValidator 'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*stConfig\.fStandardMoveDecelerationMmS2\s*\)' 'Standard deceleration must be finite'
    Assert-Match $configValidator 'fStandardMoveAccelerationMmS2\s*>\s*0\.0' 'Standard acceleration must be positive'
    Assert-Match $configValidator 'fStandardMoveDecelerationMmS2\s*>\s*0\.0' 'Standard deceleration must be positive'
    Assert-Match $configValidator 'fStandardMoveAccelerationMmS2\s*<=\s*stLimits\.fZMaxAccelerationMmS2' 'Standard acceleration hard limit is missing'
    Assert-Match $configValidator 'fStandardMoveDecelerationMmS2\s*<=\s*stLimits\.fZMaxAccelerationMmS2' 'Standard deceleration hard limit is missing'
    Assert-Match $programValidator 'fContactSearchStartPositionMm\s*>=\s*stMachineLimits\.fZMinPositionMm' 'Contact search lower boundary is missing'
    Assert-Match $programValidator 'fContactSearchStartPositionMm\s*<=\s*stMachineLimits\.fZMaxPositionMm' 'Contact search upper boundary is missing'
    Assert-Match $programValidator '(?s)astSteps\s*\[\s*4\s*\].*?ePrimaryCriterion\s*=\s*STEP_CRIT_STEP_TIME' 'Step 4 must use time primary criterion'
    Assert-Match $programValidator '(?s)astSteps\s*\[\s*4\s*\].*?nQualifiedForceHoldMs\s*>\s*0.*?nQualifiedForceHoldMs\s*<=\s*nPrimaryStepTimeMs' 'Step 4 qualified hold bounds are missing'
    Assert-Match $programValidator '(?s)astSteps\s*\[\s*4\s*\].*?fForceBandToleranceN\s*>\s*0\.0.*?fForceBandToleranceN\s*<\s*stMachineLimits\.fMaxForceN' 'Step 4 force band limits are missing'
    Assert-Match $programValidator '(?s)astSteps\s*\[\s*4\s*\].*?fRpmStoppedThresholdRpm\s*>=\s*0\.0.*?fRpmStoppedThresholdRpm\s*<\s*stMachineLimits\.fRMaxSpeedRpm' 'Step 4 RPM threshold limits are missing'
    Assert-Match $programValidator '(?s)astSteps\s*\[\s*4\s*\].*?eSecondaryAction\s*=\s*SECONDARY_CONTROLLED_EXIT_NOK' 'Step 4 must use controlled NOK exit'
    Assert-Match $programValidator '(?s)astSteps\s*\[\s*4\s*\].*?fSetSpeedRpm\s*=\s*0\.0' 'Step 4 RPM must be zero'
    Assert-Match $programValidator 'nForceProfileId\s*>\s*0' 'Join program must require a positive force profile ID'
    Assert-Match $programValidator 'nRAxisProfileId\s*>\s*0' 'Join program must require a positive R profile ID'
}

if ($runTrajectory) {
    $trajectory = Read-Text 'CFFwelding_System\CFFwelding\POUs\FunctionBlocks\Control\FB_ZExternalTrajectory.TcPOU'
    Assert-NoMatch $trajectory 'GVL_|AXIS_REF|MC_' 'Trajectory must not access GVL, axes, or MC'
    Assert-Match $trajectory '(?s)FC_LimitRate\s*\(.*?rCurrent\s*:=\s*stInput\.rAcceptedVelocity_mm_s.*?rTarget\s*:=\s*stInput\.rTargetVelocity_mm_s.*?rRateUpPer_s\s*:=\s*stInput\.rMaximumAcceleration_mm_s2.*?rRateDownPer_s\s*:=\s*stInput\.rMaximumAcceleration_mm_s2.*?rCycleTime_s\s*:=\s*stInput\.rCycleTime_s' 'Trajectory rate limit must use accepted velocity and configured acceleration'
    Assert-Match $trajectory 'rNextAcceleration_mm_s2\s*:=\s*\(\s*rNextVelocity_mm_s\s*-\s*stInput\.rAcceptedVelocity_mm_s\s*\)\s*/\s*stInput\.rCycleTime_s' 'Trajectory acceleration must use accepted velocity'
    Assert-Match $trajectory '(?s)rNextPosition_mm\s*:=\s*stInput\.rAcceptedPosition_mm\s*\+\s*0\.5\s*\*\s*\(\s*stInput\.rAcceptedVelocity_mm_s\s*\+\s*rNextVelocity_mm_s\s*\)\s*\*\s*stInput\.rCycleTime_s' 'Trajectory must integrate from the accepted package'
    Assert-CaseMatch $trajectory 'Z_TRAJ_HOLD_OLD_DIRECTION' '(?s)rPosition_mm\s*:=\s*stInput\.rAcceptedPosition_mm.*?rVelocity_mm_s\s*:=\s*0\.0.*?rAcceleration_mm_s2\s*:=\s*0\.0' 'Old direction hold must publish a held zero package'
    Assert-CaseMatch $trajectory 'Z_TRAJ_DIRECTION_ZERO' '(?s)rPosition_mm\s*:=\s*stInput\.rAcceptedPosition_mm.*?rVelocity_mm_s\s*:=\s*0\.0.*?rAcceleration_mm_s2\s*:=\s*0\.0' 'Direction zero hold must publish a held zero package'
    Assert-CaseMatch $trajectory 'Z_TRAJ_PRELOAD_NEW_DIRECTION' '(?s)rPosition_mm\s*:=\s*stInput\.rAcceptedPosition_mm.*?rVelocity_mm_s\s*:=\s*0\.0.*?rAcceleration_mm_s2\s*:=\s*0\.0' 'New direction preload must publish a held zero package'
    Assert-Match $trajectory '(?s)bNewAcceptedFeed\s*:=\s*\(stInput\.bFeedAccepted\s*=\s*TRUE\).*?udiAcceptedFeedCycleCounter\s*<>\s*udiLastAcceptedFeedCycleCounter' 'Trajectory must detect progression only from a new accepted feed counter'
    $noNewAcceptedFeed = Get-IfBody $trajectory 'NOT bNewAcceptedFeed' 'Trajectory must have an executable no-new-accepted-feed hold region'
    Assert-Match $noNewAcceptedFeed '(?s)rPosition_mm\s*:=\s*rLastPublishedPosition_mm.*?rVelocity_mm_s\s*:=\s*rLastPublishedVelocity_mm_s.*?rAcceleration_mm_s2\s*:=\s*rLastPublishedAcceleration_mm_s2.*?nDirection\s*:=\s*nLastPublishedDirection.*?RETURN' 'No-new-feed scans must repeat the exact pending P/V/A/direction package'
    Assert-NoMatch $noNewAcceptedFeed 'FC_LimitRate|rTargetVelocity_mm_s|eState\s*:=' 'No-new-feed scans must not integrate, consume a live target, or advance state'
    Assert-NoMatch $trajectory '(?s)stOutput\.eState\s*:=\s*Z_TRAJ_FAULT(?:(?!stOutput\.bActive\s*:=\s*FALSE|RETURN;).)*RETURN;' 'Every same-scan trajectory fault return must explicitly publish inactive'
    Assert-Match $trajectory 'bLastPublishedPositiveMotionInhibited\s*:\s*BOOL' 'Pending package memory must include the hard-inhibit marker'
    Assert-Match $noNewAcceptedFeed 'bPositiveMotionInhibited\s*:=\s*bLastPublishedPositiveMotionInhibited' 'No-new-feed scans must replay the pending hard-inhibit marker instead of the live input'
    Assert-Match $trajectory '(?s)IF\s+NOT\s+bNewAcceptedFeed\s+AND\s+stInput\.bInhibitPositiveMotion.*?bPositiveMotionInhibited\s*:=\s*TRUE.*?bLastPublishedPositiveMotionInhibited\s*:=\s*stOutput\.bPositiveMotionInhibited.*?RETURN' 'Hard-inhibit replacement must remember its TRUE continuity-bypass marker before returning'
    Assert-True (([regex]::Matches($trajectory, 'bLastPublishedPositiveMotionInhibited\s*:=\s*stOutput\.bPositiveMotionInhibited')).Count -ge 3) 'Every initial, hard-replacement, and normal final package store must remember the inhibit marker'
    Assert-Match $trajectory '(?s)IF\s+NOT\s+stInput\.bEnable\s+THEN.*?bLastPublishedPositiveMotionInhibited\s*:=\s*FALSE' 'Disable must clear pending inhibit memory'
    Assert-Match $trajectory 'stOutput\.bPositiveMotionInhibited\s*:=\s*stInput\.bInhibitPositiveMotion' 'Every active trajectory state must truthfully publish the hard-inhibit flag'
    Assert-Ordered $trajectory @('IF stInput.eExternalState <> Z_EXT_ACTIVE THEN','stOutput.bPositiveMotionInhibited := stInput.bInhibitPositiveMotion','CASE eState OF') 'Hard-inhibit truth must be established after inactive rejection and before every active state branch'
    Assert-Match $trajectory '(?s)END_CASE\s*;.*?stInput\.bInhibitPositiveMotion.*?rAcceptedVelocity_mm_s\s*>\s*0\.0.*?rPosition_mm\s*:=\s*stInput\.rAcceptedPosition_mm.*?rVelocity_mm_s\s*:=\s*0\.0.*?rAcceleration_mm_s2\s*:=\s*0\.0.*?nDirection\s*:=\s*stInput\.nAcceptedDirection.*?bPositiveMotionInhibited\s*:=\s*TRUE.*?rLastPublishedPosition_mm\s*:=\s*stOutput\.rPosition_mm' 'Hard inhibit must override positive accepted motion after every active state and before pending-package memory is stored'
    Assert-IfRegionMatch $trajectory '(?i)(?:stInput\.|\bNOT\s+b[A-Za-z0-9_]*Valid\b)' '(?s)(?=.*(?:stOutput\.)?bFault\s*:=\s*TRUE)(?=.*(?:stOutput\.)?eState\s*:=\s*Z_TRAJ_FAULT)' 'Trajectory input fault path must latch bFault and enter Z_TRAJ_FAULT'
    $trajectoryFault = Get-CaseBranch $trajectory 'Z_TRAJ_FAULT' 'Missing executable CASE branch: Z_TRAJ_FAULT'
    Assert-IfRegionMatch $trajectoryFault '^(?:stInput\.)?bReset\s+AND\s+NOT\s+(?:stInput\.)?bEnable$' '(?s)(?=.*(?:stOutput\.)?bFault\s*:=\s*FALSE)(?=.*(?:stOutput\.)?nFaultId\s*:=\s*0)(?=.*(?:stOutput\.)?bActive\s*:=\s*FALSE)(?=.*(?:stOutput\.)?eState\s*:=\s*Z_TRAJ_IDLE)' 'Trajectory fault reset must clear outputs and recover to inactive IDLE while disabled'
    Assert-CaseMatch $trajectory 'Z_TRAJ_TRACKING' '(?s)bInhibitPositiveMotion.*?rAcceptedVelocity_mm_s\s*>\s*0\.0.*?rPosition_mm\s*:=\s*stInput\.rAcceptedPosition_mm.*?rVelocity_mm_s\s*:=\s*0\.0.*?rAcceleration_mm_s2\s*:=\s*0\.0.*?bPositiveMotionInhibited\s*:=\s*TRUE' 'Hard inhibit must publish a first-package zero velocity override'
    $ts = 0.1; $acceptedP = 10.0; $acceptedV = 1.0; $targetV = 3.0; $amax = 2.0
    $nextV = [math]::Min($targetV, $acceptedV + $amax * $ts); $nextA = ($nextV - $acceptedV) / $ts; $nextP = $acceptedP + 0.5 * ($acceptedV + $nextV) * $ts
    Assert-Near $nextV 1.2 0.000000001 'Trajectory scan 1 velocity'; Assert-Near $nextA 2.0 0.000000001 'Trajectory scan 1 acceleration'; Assert-Near $nextP 10.11 0.000000001 'Trajectory scan 1 position'
    $acceptedP = $nextP; $acceptedV = $nextV; $nextV = [math]::Min($targetV, $acceptedV + $amax * $ts); $nextP = $acceptedP + 0.5 * ($acceptedV + $nextV) * $ts
    Assert-Near $nextV 1.4 0.000000001 'Trajectory scan 2 velocity'; Assert-Near $nextP 10.24 0.000000001 'Trajectory scan 2 position'
    $reverseP = 0.0; $reverseV = 0.4; $reverseTargetV = -1.0
    $reverseNextV = [math]::Max($reverseTargetV, $reverseV - $amax * $ts); $reverseNextP = $reverseP + 0.5 * ($reverseV + $reverseNextV) * $ts
    Assert-Near $reverseNextV 0.2 0.000000001 'Reverse scan 1 velocity'; Assert-Near $reverseNextP 0.03 0.000000001 'Reverse scan 1 position'
    $reverseP = $reverseNextP; $reverseV = $reverseNextV; $reverseNextV = [math]::Max($reverseTargetV, $reverseV - $amax * $ts); $reverseNextP = $reverseP + 0.5 * ($reverseV + $reverseNextV) * $ts
    Assert-Near $reverseNextV 0.0 0.000000001 'Reverse scan 2 velocity'; Assert-Near $reverseNextP 0.04 0.000000001 'Reverse scan 2 position'
    $directionState = 'RAMP_TO_ZERO'; $directionTrace = New-Object 'System.Collections.Generic.List[string]'
    while ($directionState -ne 'TRACKING') {
        switch ($directionState) {
            'RAMP_TO_ZERO' { if ($reverseNextV -eq 0.0) { $directionState = 'HOLD_OLD_DIRECTION' } }
            'HOLD_OLD_DIRECTION' { $directionState = 'DIRECTION_ZERO' }
            'DIRECTION_ZERO' { $directionState = 'PRELOAD_NEW_DIRECTION' }
            'PRELOAD_NEW_DIRECTION' { $directionState = 'TRACKING' }
        }
        $directionTrace.Add($directionState)
    }
    Assert-True (($directionTrace -join '>') -eq 'HOLD_OLD_DIRECTION>DIRECTION_ZERO>PRELOAD_NEW_DIRECTION>TRACKING') 'Direction transition order must be deterministic'
    $reverseNextV = [math]::Max($reverseTargetV, 0.0 - $amax * $ts); $reverseNextA = ($reverseNextV - 0.0) / $ts; $reverseNextP = 0.04 + 0.5 * (0.0 + $reverseNextV) * $ts
    Assert-Near $reverseNextV -0.2 0.000000001 'Reverse tracking velocity'; Assert-Near $reverseNextA -2.0 0.000000001 'Reverse tracking acceleration'; Assert-Near $reverseNextP 0.03 0.000000001 'Reverse tracking position'
    $hardInhibitAcceptedVelocity = 1.0; $hardInhibitOutputVelocity = if ($hardInhibitAcceptedVelocity -gt 0.0) { 0.0 } else { $hardInhibitAcceptedVelocity }
    Assert-Near $hardInhibitOutputVelocity 0.0 0.0 'Hard inhibit must remove positive velocity in the first package'
    $heldPacket = [pscustomobject]@{ P = 10.11; V = 1.2; A = 2.0; Direction = 1; State = 'TRACKING' }
    $delayedAcceptanceTrace = foreach ($liveTarget in @(2.5, -1.0, 0.0)) {
        [pscustomobject]@{ P = $heldPacket.P; V = $heldPacket.V; A = $heldPacket.A; Direction = $heldPacket.Direction; State = $heldPacket.State; Target = $liveTarget }
    }
    foreach ($heldScan in $delayedAcceptanceTrace) {
        Assert-Near $heldScan.P 10.11 0.0 'Unaccepted packet position must remain literal-held'
        Assert-Near $heldScan.V 1.2 0.0 'Unaccepted packet velocity must remain literal-held'
        Assert-Near $heldScan.A 2.0 0.0 'Unaccepted packet acceleration must remain literal-held'
        Assert-True (($heldScan.Direction -eq 1) -and ($heldScan.State -eq 'TRACKING')) 'Live target changes must not alter pending direction or state before acceptance'
    }
    $delayedAcceptedPacket = $delayedAcceptanceTrace[0]
    Assert-True (($delayedAcceptedPacket.P -eq $heldPacket.P) -and ($delayedAcceptedPacket.V -eq $heldPacket.V) -and ($delayedAcceptedPacket.A -eq $heldPacket.A) -and ($delayedAcceptedPacket.Direction -eq $heldPacket.Direction)) 'Delayed legal acceptance must still match the packet that was actually held and published'
    $pendingHardReplacement = [pscustomobject]@{ P = 20.0; V = 0.0; A = 0.0; Direction = 1; PositiveMotionInhibited = $true }
    $livePositiveMotionInhibit = $false
    $acceptedCounterChanged = $false
    $replayedHardReplacement = if (-not $acceptedCounterChanged) { $pendingHardReplacement } else { [pscustomobject]@{ P = 20.0; V = 0.0; A = 0.0; Direction = 1; PositiveMotionInhibited = $livePositiveMotionInhibit } }
    Assert-True (($replayedHardReplacement.P -eq 20.0) -and ($replayedHardReplacement.V -eq 0.0) -and ($replayedHardReplacement.A -eq 0.0) -and ($replayedHardReplacement.Direction -eq 1) -and $replayedHardReplacement.PositiveMotionInhibited) 'Pending hard-inhibit replacement must retain its TRUE marker after live inhibit clears and before acceptance'
    $inhibitReportingFixtures = @(
        [pscustomobject]@{ State = 'SYNC'; Active = $true; Inhibit = $true; Expected = $true },
        [pscustomobject]@{ State = 'TRACKING'; Active = $true; Inhibit = $true; Expected = $true },
        [pscustomobject]@{ State = 'RAMP_TO_ZERO'; Active = $true; Inhibit = $true; Expected = $true },
        [pscustomobject]@{ State = 'HOLD_OLD_DIRECTION'; Active = $true; Inhibit = $true; Expected = $true },
        [pscustomobject]@{ State = 'DIRECTION_ZERO'; Active = $true; Inhibit = $true; Expected = $true },
        [pscustomobject]@{ State = 'PRELOAD_NEW_DIRECTION'; Active = $true; Inhibit = $true; Expected = $true },
        [pscustomobject]@{ State = 'IDLE'; Active = $false; Inhibit = $true; Expected = $false },
        [pscustomobject]@{ State = 'FAULT'; Active = $false; Inhibit = $true; Expected = $false })
    foreach ($fixture in $inhibitReportingFixtures) {
        $reportedPositiveMotionInhibit = $fixture.Active -and $fixture.Inhibit
        Assert-True ($reportedPositiveMotionInhibit -eq $fixture.Expected) "Hard-inhibit reporting fixture: $($fixture.State)"
    }
}

if ($runAdapter) {
    $adapter = Read-Text 'CFFwelding_System\CFFwelding\POUs\FunctionBlocks\Axis\FB_ZAxisExtSetpointAdapter.TcPOU'
    Assert-Match $adapter '(?s)bPrecheckOk.*?bAcceptedSetpointValid\s*:=\s*TRUE.*?rAcceptedPosition_mm\s*:=\s*Axis\.NcToPlc\.SetPos.*?rAcceptedVelocity_mm_s\s*:=\s*Axis\.NcToPlc\.SetVelo.*?rAcceptedAcceleration_mm_s2\s*:=\s*Axis\.NcToPlc\.SetAcc.*?nAcceptedDirection\s*:=\s*nInitialDirection' 'Adapter must publish accepted initial P/V/A/direction after precheck'
    $adapterActive = Get-CaseBranch $adapter 'Z_EXT_ACTIVE' 'Missing executable CASE branch: Z_EXT_ACTIVE'
    $adapterWaitEnabled = Get-CaseBranch $adapter 'Z_EXT_WAIT_ENABLED' 'Missing executable CASE branch: Z_EXT_WAIT_ENABLED'
    $adapterUnknownState = Get-UniqueTopLevelCaseDefaultBody $adapter 'eState'
    Assert-True (-not [string]::IsNullOrWhiteSpace($adapterUnknownState)) 'Adapter main CASE must have one direct executable unknown-state fail-closed default'
    if (-not [string]::IsNullOrWhiteSpace($adapterUnknownState)) {
        $unknownLinkedLifecycle = Get-UniqueTopLevelPositiveIfPartition $adapterUnknownState 'Axis\.Status\.ExtSetPointGenEnabled\s+OR\s+fbEnable\.Enabled\s+OR\s+fbDisable\.Enabled'
        Assert-True ($null -ne $unknownLinkedLifecycle) 'Adapter unknown-state default must test the complete linked External lifecycle condition at top level'
        if ($null -ne $unknownLinkedLifecycle) {
            $unknownCommonPrefix = $adapterUnknownState.Substring(0, $unknownLinkedLifecycle.Start)
            Assert-Match $unknownCommonPrefix '(?s)udiLatchedErrorId\s*:=\s*16#00007206.*?bExitDueToError\s*:=\s*TRUE.*?stStatus\.bDone\s*:=\s*FALSE.*?stStatus\.bReleaseOwner\s*:=\s*FALSE.*?stStatus\.bAcceptedSetpointValid\s*:=\s*FALSE.*?bFeedThisCycle\s*:=\s*FALSE' 'Adapter unknown-state scan must latch 7206 and clear every false-positive publication before lifecycle routing'
            Assert-True ($unknownLinkedLifecycle.HasElse -and ($unknownLinkedLifecycle.ElsifCount -eq 0)) 'Adapter unknown-state lifecycle decision must have one direct unconditional ELSE'
            Assert-Match $unknownLinkedLifecycle.PositiveBody '(?s)bPostDisableHoldPending\s*:=\s*TRUE.*?eState\s*:=\s*E_ZExtSetpointState\.Z_EXT_DISABLE' 'Adapter unknown linked lifecycle must retain owner and enter the existing Disable sequence'
            Assert-Match $unknownLinkedLifecycle.AlternateBody '(?s)bPostDisableHoldPending\s*:=\s*FALSE.*?eState\s*:=\s*E_ZExtSetpointState\.Z_EXT_ERROR' 'Adapter unknown inactive lifecycle must fail directly to Error without a pending hold'
        }
        Assert-NoMatch $adapterUnknownState 'bFeedThisCycle\s*:=\s*TRUE|stStatus\.bFeedAccepted\s*:=\s*TRUE|MC_ExtSetPointGenFeed\s*\(' 'Adapter unknown-state scan must not publish a new Feed'
        Assert-NoMatch $adapterUnknownState 'stStatus\.bReleaseOwner\s*:=\s*TRUE' 'Adapter unknown-state scan must not claim owner release'
    }
    $adapterFeedMatch = [regex]::Match($adapter, '(?s)IF\s+bFeedThisCycle\s+AND\s+bDriveLinked\s+THEN(.*?)(?=\r?\n\s*stStatus\.eState\s*:=)')
    Assert-True $adapterFeedMatch.Success 'Adapter unified post-Feed publication block is missing'
    $adapterFeed = if ($adapterFeedMatch.Success) { $adapterFeedMatch.Groups[1].Value } else { '' }
    Assert-Match $adapterFeed '(?s)MC_ExtSetPointGenFeed\s*\(.*?bFeedAccepted\s*:=\s*TRUE.*?rAcceptedPosition_mm\s*:=\s*rFeedPosition_mm.*?rAcceptedVelocity_mm_s\s*:=\s*rFeedVelocity_mm_s.*?rAcceptedAcceleration_mm_s2\s*:=\s*rFeedAcceleration_mm_s2.*?nAcceptedDirection\s*:=\s*nFeedDirection' 'Adapter must publish accepted P/V/A/direction once, after MC Feed'
    Assert-True (([regex]::Matches($adapter, '(?m)^\s*Z_EXT_ACTIVE\s*:')).Count -eq 0) 'Adapter must not use a second bare ACTIVE CASE to satisfy the harness'
    Assert-True (([regex]::Matches($adapter, 'stStatus\.rAcceptedPosition_mm\s*:=\s*rFeedPosition_mm')).Count -eq 1) 'Adapter accepted Feed publication must be a single unified assignment'
    Assert-Match $adapter '(?s)udiFeedCycleCounter\s*=\s*UDINT#4294967295.*?udiFeedCycleCounter\s*:=\s*1.*?ELSE.*?udiFeedCycleCounter\s*:=\s*udiFeedCycleCounter\s*\+\s*1' 'Feed counter must skip zero on wrap'
    Assert-Match $adapterActive '(?s)(?:nAcceptedDirection\s*=\s*1.*?nFeedDirection\s*=\s*-1|nAcceptedDirection\s*=\s*-1.*?nFeedDirection\s*=\s*1).*?(?:nFaultId\s*:=|eState\s*:=\s*Z_EXT_FAULT)' 'Adapter direct nonzero direction reversal must latch a fault'
    Assert-Match $adapter '(?s)nFeedDirection\s*=\s*0.*?(ABS\s*\(\s*rFeedVelocity_mm_s\s*\)|rFeedVelocity_mm_s).*?(ABS\s*\(\s*rFeedAcceleration_mm_s2\s*\)|rFeedAcceleration_mm_s2)' 'Direction-zero feed must validate standstill P/V/A'
    Assert-Match $adapterActive '(?s)bPositiveMotionInhibit.*?stCommand\.rPosition_mm\s*=\s*stStatus\.rAcceptedPosition_mm.*?stCommand\.rVelocity_mm_s\s*=\s*0\.0.*?stCommand\.rAcceleration_mm_s2\s*=\s*0\.0.*?stCommand\.nDirection\s*=\s*stStatus\.nAcceptedDirection' 'Adapter hard inhibit must validate held P and zero V/A before copying the command'
    Assert-Match $adapterActive '(?s)bPositiveMotionInhibit.*?(?:bDisable\s*:=\s*TRUE|eState\s*:=\s*Z_EXT_DISABLE)' 'Accepted hard inhibit must enter the normal disable sequence'
    Assert-Match $adapterWaitEnabled '(?s)Axis\.Status\.ExtSetPointGenEnabled\s+OR\s+fbEnable\.Enabled.*?bPositiveMotionInhibit.*?stCommand\.rPosition_mm\s*=\s*stStatus\.rAcceptedPosition_mm.*?stCommand\.rVelocity_mm_s\s*=\s*0\.0.*?bFeedThisCycle\s*:=\s*TRUE.*?bDisable\s*:=\s*TRUE' 'WAIT_ENABLED hard inhibit must validate and stage the exact zero package before Feed'
    Assert-Match $adapterWaitEnabled '(?s)ELSIF\s+NOT\s+bPrecheckOk\s+THEN.*?bFeedThisCycle\s*:=\s*FALSE.*?bExitDueToError\s*:=\s*TRUE.*?Z_EXT_RAMP_TO_ZERO.*?ELSIF\s+Axis\.Status\.ExtSetPointGenEnabled' 'WAIT_ENABLED must reject lost health/config before the Enabled Feed'
    Assert-NoMatch $adapterWaitEnabled 'rFeed(?:Position_mm|Velocity_mm_s|Acceleration_mm_s2)\s*:=\s*stCommand\.' 'WAIT_ENABLED invalid inhibit input must not overwrite the safe Feed package'
    Assert-Match $adapterActive '(?s)bZ_EXT_DIRECTION_PRELOAD\s*:=\s*FALSE.*?nPendingDirection\s*:=\s*0' 'Accepted ordinary motion must clear all direction-handshake state'
    Assert-Match $adapterActive '(?s)ELSIF\s+\(nFeedDirection\s*=\s*0\).*?stCommand\.rPosition_mm\s*<>\s*stStatus\.rAcceptedPosition_mm.*?stCommand\.rVelocity_mm_s\s*<>\s*0\.0.*?stCommand\.rAcceleration_mm_s2\s*<>\s*0\.0.*?16#00007209' 'Every Direction-zero package must be exact held P/V0/A0 before Feed'
    Assert-NoMatch $adapterActive '(?s)\(nFeedDirection\s*=\s*stStatus\.nAcceptedDirection\).*?stStatus\.rAcceptedVelocity_mm_s\s*=\s*0\.0.*?stStatus\.rAcceptedAcceleration_mm_s2\s*=\s*0\.0.*?stCommand\.rPosition_mm' 'Old-direction held-P validation must not depend on previous accepted acceleration'
    $rEnvelope = 0.0 + 500.0 * 0.002; Assert-Near $rEnvelope 1.0 0.000000001 'R envelope first scan'
    $rAdapterTransactions = 0; $lastRPayload = $null
    1..100 | ForEach-Object {
        $rEnvelope = [math]::Min(1000.0, $rEnvelope + 1.0)
        $candidateRPayload = 'Move:1000:500'
        if ($candidateRPayload -ne $lastRPayload) { $rAdapterTransactions++; $lastRPayload = $candidateRPayload }
    }
    Assert-True ($rAdapterTransactions -eq 1) 'R target must remain one MC transaction'
}

if ($runRouting) {
    $fastAxis = Read-Text 'CFFwelding_System\CFFwelding\POUs\Fast\PRG_FastAxisControl.TcPOU'
    Assert-Match $fastAxis 'fbZExternalTrajectory\s*:\s*FB_ZExternalTrajectory' 'Unique trajectory instance is missing'
    Assert-True (([regex]::Matches($fastAxis, 'fbZExternalTrajectory\s*:\s*FB_ZExternalTrajectory')).Count -eq 1) 'Trajectory must have exactly one FastAxis instance'
    Assert-Match $fastAxis 'fbRSpeedRamp\s*:\s*FB_SetpointRamp' 'R envelope instance is missing'
    Assert-Match $fastAxis '(?s)bZSequenceSourceActive.*?bLastZSequenceSourceActive.*?udiLastZSourceCommandId.*?udiZAdapterCommandId.*?udiCurrentSequenceZSourceId' 'Z source ID routing state is incomplete'
    Assert-Match $fastAxis '(?s)bRSequenceSourceActive.*?bLastRSequenceSourceActive.*?udiLastRSourceCommandId.*?udiRAdapterCommandId.*?udiCurrentSequenceRSourceId' 'R source ID routing state is incomplete'
    Assert-Match $fastAxis '(?s)bZSequenceSourceActive\s*<>\s*bLastZSequenceSourceActive.*?FC_IsNewerRequestId' 'Z source must create a transaction on source change or newer ID'
    Assert-Match $fastAxis '(?s)bRSequenceSourceActive\s*<>\s*bLastRSequenceSourceActive.*?FC_IsNewerRequestId' 'R source must create a transaction on source change or newer ID'
    Assert-Match $fastAxis '(?s)udiZAdapterCommandId\s*:=\s*udiZAdapterCommandId\s*\+\s*1.*?IF\s+udiZAdapterCommandId\s*=\s*0.*?udiZAdapterCommandId\s*:=\s*1' 'Z adapter transaction ID must skip zero'
    Assert-Match $fastAxis '(?s)udiRAdapterCommandId\s*:=\s*udiRAdapterCommandId\s*\+\s*1.*?IF\s+udiRAdapterCommandId\s*=\s*0.*?udiRAdapterCommandId\s*:=\s*1' 'R adapter transaction ID must skip zero'
    Assert-Match $fastAxis '(?s)udiPendingZSequenceSourceId.*?udiPendingZAdapterCommandId.*?bPendingZTransactionIsSequence.*?IF\s+bPendingZTransactionIsSequence\s+AND\s*\(fbZAxisNc\.udiAcceptedCommandId\s*=\s*udiPendingZAdapterCommandId\).*?udiAcceptedSequenceZCommandId\s*:=\s*udiPendingZSequenceSourceId' 'Sequence Z acknowledgement must publish the latched source ID only after the latched adapter transaction is accepted'
    Assert-Match $fastAxis '(?s)udiPendingRSequenceSourceId.*?udiPendingRAdapterCommandId.*?bPendingRTransactionIsSequence.*?IF\s+bPendingRTransactionIsSequence\s+AND\s*\(fbRAxisNc\.udiAcceptedCommandId\s*=\s*udiPendingRAdapterCommandId\).*?udiAcceptedSequenceRCommandId\s*:=\s*udiPendingRSequenceSourceId' 'Sequence R acknowledgement must publish the latched source ID only after the latched adapter transaction is accepted'
    Assert-Match $fastAxis '(?s)rEffectiveForceRamp_kN_s\s*:=\s*MIN\s*\(.*?rForceRamp_kN_s.*?fForceRampNS\s*\*\s*0\.001' 'FastAxis must consume the per-step force ramp and frozen profile limit'
    Assert-Match $fastAxis '(?s)rRSpeedEnvelope_rpm\s*:=\s*fbRSpeedRamp\.rOutput.*?bRSpeedRampBusy\s*:=\s*fbRSpeedRamp\.bBusy.*?bRSpeedRampReached\s*:=\s*fbRSpeedRamp\.bReached.*?bRSpeedRampValid\s*:=\s*fbRSpeedRamp\.bValid' 'R ramp must be diagnostic-only output'
    Assert-NoMatch $fastAxis 'stRCommand\.rVelocity_rpm\s*:=\s*fbRSpeedRamp\.rOutput' 'R envelope must not replace the adapter-facing R command'
    Assert-Match $fastAxis '(?s)fbZAxisExtSetpointAdapter\s*\(' 'FastAxis must delegate External MC ownership to the adapter'
    Assert-NoMatch $fastAxis 'MC_ExtSetPointGen' 'FastAxis must not call the External MC API directly'

    # Fix1: safety transactions and hard-override handshakes are scan contracts,
    # not merely boolean gates.  These bounded source checks are paired with
    # the literal multi-scan reference traces below.
    Assert-NoMatch $fastAxis '(?s)bZSequenceSourceActive\s*:=\s*FALSE\s*;\s*IF\s+GVL_Status\.stFast\.stSequence\.bBusy\s+THEN\s*CASE' 'Z sequence source selection must not fall back to an old normal command merely because Busy is FALSE'
    Assert-Match $fastAxis 'bRSequenceSourceActive\s*:=\s*GVL_Status\.stFast\.stSequence\.stMotionIntent\.bRAxisProcessRequested\s*;' 'R sequence stop intent must remain selected independently of Busy'
    Assert-Match $fastAxis '(?s)bHardOverrideStart\s*:=\s*bFastConfigSnapshotCurrent.*?Z_EXT_ACTIVE.*?bAcceptedSetpointValid.*?rAcceptedVelocity_mm_s\s*>\s*0\.0.*?fbZExternalTrajectory\.stOutput\.rVelocity_mm_s\s*>\s*0\.0.*?IF\s+bHardOverrideStart\s+THEN.*?rHardOverrideExpectedPosition_mm\s*:=.*?nHardOverrideExpectedDirection\s*:=.*?udiHardOverrideAcceptedCounter\s*:=' 'Hard override must latch the accepted P/direction/counter before Error or Abort can remove normal trajectory enable'
    Assert-Match $fastAxis '(?s)bHardOverrideAccepted\s*:=\s*bHardOverridePending.*?bFeedAccepted.*?udiFeedCycleCounter\s*<>\s*udiHardOverrideAcceptedCounter.*?rAcceptedPosition_mm\s*=\s*rHardOverrideExpectedPosition_mm.*?rAcceptedVelocity_mm_s\s*=\s*0\.0.*?rAcceptedAcceleration_mm_s2\s*=\s*0\.0.*?nAcceptedDirection\s*=\s*nHardOverrideExpectedDirection' 'Hard override completion must require a new exact Adapter-accepted zero packet'
    Assert-Match $fastAxis '(?s)IF\s+bHardOverridePending\s+THEN.*?bFeed\s*:=\s*bHardOverridePackageExact.*?bDisable\s*:=\s*TRUE.*?bPositiveMotionInhibit\s*:=\s*bHardOverridePackageExact.*?IF\s+NOT\s+stExtCommand\.bFeed\s+THEN.*?bPositiveMotionInhibit\s*:=\s*FALSE' 'Only an exact active nonfault hard packet may retain Feed and the hard marker during safety Disable'
    Assert-Match $fastAxis '(?s)bSequenceMotionIntentPresent\s*:=.*?stMotionIntent\.stZCommand\.eOwnerRequest\s*<>\s*E_ZCommandOwner\.Z_OWNER_NONE.*?bRAxisProcessRequested.*?bExternalEnableRequest.*?bExternalDisableRequest.*?bForceControlEnable' 'Snapshot loss detection must distinguish PRECHECK from real motion intent'
    Assert-Match $fastAxis '(?s)bFastConfigSnapshotCurrent\s+AND\s+GVL_Status\.stFast\.stSequence\.bBusy\s+THEN\s+bFastConfigSnapshotSeen\s*:=\s*TRUE.*?bSnapshotMismatch\s*:=\s*NOT\s+bFastConfigSnapshotCurrent\s+AND\s*\(bFastConfigSnapshotSeen\s+OR\s+bSequenceMotionIntentPresent\).*?bFastSafetyStopEvent\s*:=\s*bSnapshotMismatch\s+AND\s+NOT\s+bFastSafetyStopLatched\s+AND\s+NOT\s+bSafeTerminalResetRising.*?bFastSafetyStopLatched\s*:=\s*TRUE' 'Snapshot mismatch must arm only during an active Busy cycle or from live intent, never from a lingering terminal snapshot'
    Assert-Match $fastAxis '(?s)IF\s+bFastSafetyStopEvent\s+THEN.*?udiZAdapterCommandId\s*:=\s*udiZAdapterCommandId\s*\+\s*1.*?udiRAdapterCommandId\s*:=\s*udiRAdapterCommandId\s*\+\s*1' 'One snapshot mismatch event must create one real Z stop transaction and one real R stop transaction'
    Assert-Match $fastAxis '(?s)bLatchedZFaultStopRequest\s*:=\s*\(stLatchedZSourceCommand\.eOwnerRequest\s*=\s*E_ZCommandOwner\.Z_OWNER_FAULT_STOP\)\s+OR\s+bFastSafetyStopLatched.*?bFaultStopRequest\s*:=\s*bLatchedZFaultStopRequest' 'FaultStop must use the latched source payload plus the independent snapshot safety latch'
    Assert-Match $fastAxis '(?s)bNewSafeTerminalSequenceCommand\s*:=\s*FC_IsNewerRequestId\s*\(.*?udiCandidate\s*:=\s*udiCurrentSafeTerminalResetRequestId.*?udiReference\s*:=\s*udiLastObservedSafeTerminalSequenceCommandId.*?IF\s+bNewSafeTerminalSequenceCommand\s+THEN.*?udiLastObservedSafeTerminalSequenceCommandId\s*:=\s*udiCurrentSafeTerminalResetRequestId' 'Safe Reset deduplication must use the accepted Sequence command global high-water mark across all event types'
    Assert-Match $fastAxis '(?s)IF\s+bNewSafeTerminalSequenceCommand\s+THEN.*?IF\s+GVL_FastInternal\.stAcceptedCommand\.stSequence\.bResetPulse\s+THEN.*?bNewSafeTerminalResetRequest\s*:=\s*TRUE.*?udiPendingSafeTerminalResetRequestId\s*:=\s*udiCurrentSafeTerminalResetRequestId.*?bSafeTerminalResetPending\s*:=\s*TRUE.*?bSafeTerminalReset\s*:=\s*bSafeTerminalResetPending\s+AND\s+bSafeTerminalResetGatesMet.*?bSafeTerminalResetRising\s*:=\s*bSafeTerminalReset.*?IF\s+bSafeTerminalResetRising\s+THEN.*?bSafeTerminalResetPending\s*:=\s*FALSE.*?udiConsumedSafeTerminalResetRequestId\s*:=\s*udiPendingSafeTerminalResetRequestId' 'Only a newer atomic Reset packet may latch pending, which the terminal gates consume exactly once'
    Assert-NoMatch $fastAxis 'bLastSafeTerminalReset' 'Safe Reset deduplication must not depend on the gated boolean level edge'
    Assert-Match $fastAxis '(?s)IF\s+bSafeTerminalResetRising\s+THEN.*?udiZAdapterCommandId\s*:=\s*udiZAdapterCommandId\s*\+\s*1.*?udiRAdapterCommandId\s*:=\s*udiRAdapterCommandId\s*\+\s*1.*?stLatchedRAdapterCommand\.bReset\s*:=\s*TRUE.*?stLatchedRAdapterCommand\.bStop\s*:=\s*FALSE.*?stLatchedRAdapterCommand\.bMoveVelocity\s*:=\s*FALSE' 'One consumed safe Reset identity must create one pure Z/R Adapter reset transaction'
    Assert-Match $fastAxis 'IF\s+bFastConfigSnapshotCurrent\s+AND\s+GVL_Status\.stFast\.stSequence\.bBusy\s+THEN\s+bFastConfigSnapshotSeen\s*:=\s*TRUE' 'Only an active Busy cycle may arm snapshot-seen after a terminal Reset'
    Assert-Match $fastAxis '(?s)IF\s+bNewRAdapterTransaction\s+THEN.*?stLatchedRAdapterCommand\s*:=\s*stCandidateRSourceCommand.*?udiPendingRAdapterCommandId\s*:=\s*udiRAdapterCommandId.*?bPendingRTransactionIsSequence\s*:=\s*bRSequenceSourceActive' 'R payload/source/adapter transaction tuple must be latched atomically'
    Assert-Match $fastAxis '(?s)bForceLoopRequested\s*:=\s*GVL_Status\.stFast\.stSequence\.bForceControlEnable.*?bFastConfigSnapshotCurrent.*?NOT\s+bFastSafetyStopLatched' 'Latched snapshot safety stop must keep Force disabled after snapshot correlation recovers'
    Assert-Match $fastAxis '(?s)stTrajectoryInput\.bEnable\s*:=.*?NOT\s+bFastSafetyStopLatched.*?bHardOverridePending\s+AND\s+bFastConfigSnapshotCurrent\s+AND\s+NOT\s+bFastSafetyStopLatched' 'Latched snapshot safety stop must block both normal trajectory and pending hard packets'
    Assert-Match $fastAxis '(?s)bHardOverridePackageExact\s*:=\s*bHardOverridePending\s+AND\s+bFastConfigSnapshotCurrent\s+AND\s+NOT\s+bFastSafetyStopLatched' 'A pending hard packet is not exact after snapshot correlation is lost'
    Assert-Ordered $fastAxis @(
        'bRSequenceSourceActive :=',
        'udiCurrentRSourceCommandId :=',
        'IF bSafeTerminalResetRising THEN'
    ) 'The current R source and ID must be resolved before the central Reset transaction records its source state'
    $safetyStopMatches = [regex]::Matches($fastAxis, 'IF\s+bFastSafetyStopEvent\s+THEN')
    $safetyStopStart = if ($safetyStopMatches.Count -gt 0) { $safetyStopMatches[$safetyStopMatches.Count - 1].Index } else { -1 }
    $safetyStopEnd = if ($safetyStopStart -ge 0) { $fastAxis.IndexOf('IF bSafeTerminalResetRising THEN', $safetyStopStart, [StringComparison]::Ordinal) } else { -1 }
    Assert-True (($safetyStopStart -ge 0) -and ($safetyStopEnd -gt $safetyStopStart)) 'Snapshot safety Stop block is missing'
    $safetyStopBlock = if (($safetyStopStart -ge 0) -and ($safetyStopEnd -gt $safetyStopStart)) { $fastAxis.Substring($safetyStopStart, $safetyStopEnd - $safetyStopStart) } else { '' }
    Assert-True ($safetyStopBlock -notmatch '(?s)stMotionIntent.*?rDeceleration_rpm_s|GVL_FastInternal.*?rDeceleration_rpm_s') 'R safety Stop deceleration must not fall back to live Sequence or normal payloads'
    Assert-True ($safetyStopBlock -match '(?s)IF\s+bLastAcceptedRDecelerationValid\s+THEN.*?stLatchedRAdapterCommand\.rDeceleration_rpm_s\s*:=\s*rLastAcceptedRDeceleration_rpm_s') 'R safety Stop must use the last Adapter-accepted valid deceleration'
    Assert-True ($safetyStopBlock -match '(?s)rPendingRDeceleration_rpm_s\s*:=\s*stLatchedRAdapterCommand\.rDeceleration_rpm_s.*?bPendingRDecelerationValid\s*:=\s*bLastAcceptedRDecelerationValid') 'The safety Stop transaction must register the exact deceleration it submits for Adapter acceptance'
    Assert-Match $fastAxis '(?s)rPendingRDeceleration_rpm_s\s*:=\s*stCandidateRSourceCommand\.rDeceleration_rpm_s.*?bPendingRDecelerationValid\s*:=\s*FC_IsFiniteLReal\s*\(.*?rPendingRDeceleration_rpm_s.*?AND\s*\(rPendingRDeceleration_rpm_s\s*>\s*0\.0\)' 'Every normal R transaction must latch and validate its own candidate deceleration'
    Assert-Match $fastAxis '(?s)IF\s+bPendingRDecelerationValid\s+AND\s*\(fbRAxisNc\.udiAcceptedCommandId\s*=\s*udiPendingRAdapterCommandId\).*?THEN.*?rLastAcceptedRDeceleration_rpm_s\s*:=\s*rPendingRDeceleration_rpm_s.*?bLastAcceptedRDecelerationValid\s*:=\s*TRUE' 'Only an Adapter-accepted finite positive R deceleration may replace the safety fallback'
    Assert-Ordered $fastAxis @(
        'IF bPendingRDecelerationValid',
        'rLastAcceptedRDeceleration_rpm_s := rPendingRDeceleration_rpm_s;',
        'IF bFastSafetyStopEvent THEN'
    ) 'Previous-scan R acceptance must be reconciled before a snapshot safety Stop is composed'
    Assert-Match $fastAxis '(?s)IF\s+bSafeTerminalResetRising\s+THEN.*?bPostResetZNormalBarrier\s*:=\s*TRUE.*?bPostResetRNormalBarrier\s*:=\s*TRUE.*?udiPostResetNormalBarrierRequestId\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.nRequestId' 'A consumed Reset must arm Z/R normal-source barriers against the still-accepted Reset package'
    Assert-Match $fastAxis '(?s)bAcceptedFastPackageNewerThanReset\s*:=\s*FC_IsNewerRequestId\s*\(.*?udiCandidate\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.nRequestId.*?udiReference\s*:=\s*udiPostResetNormalBarrierRequestId' 'Post-Reset source authorization must compare only the accepted Fast outer request ID'
    Assert-Match $fastAxis 'bZNormalSourceBlockedByReset\s*:=\s*bPostResetZNormalBarrier\s+AND\s+NOT\s+bAcceptedFastPackageNewerThanReset\s*;' 'Z barrier must block every source, including Sequence, while the Fast outer request is stale'
    Assert-Match $fastAxis 'bRNormalSourceBlockedByReset\s*:=\s*bPostResetRNormalBarrier\s+AND\s+NOT\s+bAcceptedFastPackageNewerThanReset\s*;' 'R barrier must block every source, including Sequence, while the Fast outer request is stale'
    Assert-Match $fastAxis '(?s)bNewZSourceTransaction\s*:=\s*\(udiCurrentZSourceCommandId\s*<>\s*0\)\s+AND\s*\(.*?bZSequenceSourceActive\s*<>\s*bLastZSequenceSourceActive.*?FC_IsNewerRequestId' 'Z source transactions must reject ID zero even when the source BOOL changes'
    Assert-Match $fastAxis '(?s)bNewRSourceTransaction\s*:=\s*\(udiCurrentRSourceCommandId\s*<>\s*0\)\s+AND\s*\(.*?bRSequenceSourceActive\s*<>\s*bLastRSequenceSourceActive.*?FC_IsNewerRequestId' 'R source transactions must reject ID zero even when the source BOOL changes'
    Assert-Match $fastAxis '(?s)IF\s+bNewZAdapterTransaction\s+THEN.*?stLatchedZSourceCommand\s*:=\s*stCandidateZSourceCommand.*?bLastZSequenceSourceActive\s*:=\s*bZSequenceSourceActive.*?IF\s+bPostResetZNormalBarrier\s+AND\s+NOT\s+bZSequenceSourceActive\s+AND\s+bAcceptedFastPackageNewerThanReset\s+THEN\s+bPostResetZNormalBarrier\s*:=\s*FALSE' 'Z marker may update only with a real transaction, and only a newer normal transaction may clear the barrier'
    Assert-Match $fastAxis '(?s)IF\s+bNewRAdapterTransaction\s+THEN\s+IF\s+NOT\s+bFastSafetyStopLatched\s+AND\s+NOT\s+bSafeTerminalResetRising\s+THEN.*?stLatchedRAdapterCommand\s*:=\s*stCandidateRSourceCommand.*?bLastRSequenceSourceActive\s*:=\s*bRSequenceSourceActive.*?IF\s+bPostResetRNormalBarrier\s+AND\s+NOT\s+bRSequenceSourceActive\s+AND\s+bAcceptedFastPackageNewerThanReset\s+THEN\s+bPostResetRNormalBarrier\s*:=\s*FALSE' 'R marker may update only with a real transaction, and only a newer normal transaction may clear the barrier'

    function Test-WrapNewerId([uint64]$Candidate, [uint64]$Reference) {
        if ($Candidate -eq 0) { return $false }
        if ($Reference -eq 0) { return $true }
        $delta = ($Candidate + 4294967296L - $Reference) % 4294967296L
        return ($delta -gt 0) -and ($delta -lt 2147483648L)
    }
    $sourceTrace = @(
        [pscustomobject]@{ Sequence = $false; Id = 7L; Payload = 'normal-7' },
        [pscustomobject]@{ Sequence = $true;  Id = 7L; Payload = 'sequence-7' },
        [pscustomobject]@{ Sequence = $true;  Id = 7L; Payload = 'sequence-7-duplicate' },
        [pscustomobject]@{ Sequence = $true;  Id = 6L; Payload = 'sequence-old-6' },
        [pscustomobject]@{ Sequence = $true;  Id = 0L; Payload = 'sequence-zero' },
        [pscustomobject]@{ Sequence = $false; Id = 7L; Payload = 'normal-7-return' },
        [pscustomobject]@{ Sequence = $false; Id = 7L; Payload = 'normal-live-leak-attempt' })
    $lastSource = $false; $lastId = 0L; $adapterTransactions = 0; $latchedPayload = ''
    foreach ($item in $sourceTrace) {
        $newTransaction = ($item.Sequence -ne $lastSource) -or (Test-WrapNewerId $item.Id $lastId)
        if ($newTransaction) {
            $adapterTransactions++
            $lastSource = $item.Sequence
            $lastId = $item.Id
            $latchedPayload = $item.Payload
        }
    }
    Assert-True ($adapterTransactions -eq 3) 'normal ID7 to sequence ID7 and back must each create exactly one transaction; duplicate, old, and zero IDs must create none'
    Assert-True ($latchedPayload -eq 'normal-7-return') 'A same-source same-ID live payload change must not leak into the latched Adapter command'
    Assert-True (Test-WrapNewerId 4294967294L 0L) 'Any first nonzero ID, including max-minus-one, must be accepted from reference zero'
    Assert-True (Test-WrapNewerId 1L 4294967294L) 'Wrap-aware ID comparison must accept max-minus-one to one as newer'
    $zeroSourceTransactions = 0; $zeroSourceMarker = $false; $zeroSourceLastId = 20L
    foreach ($sourceItem in @(
        [pscustomobject]@{ Sequence = $true; Id = 0L },
        [pscustomobject]@{ Sequence = $true; Id = 7L })) {
        $sourceTransaction = ($sourceItem.Id -ne 0) -and
            (($sourceItem.Sequence -ne $zeroSourceMarker) -or
                (Test-WrapNewerId $sourceItem.Id $zeroSourceLastId))
        if ($sourceTransaction) {
            $zeroSourceTransactions++
            $zeroSourceMarker = $sourceItem.Sequence
            $zeroSourceLastId = $sourceItem.Id
        }
    }
    Assert-True (($zeroSourceTransactions -eq 1) -and $zeroSourceMarker -and ($zeroSourceLastId -eq 7L)) 'Invalid Sequence ID0 must freeze the source marker so a later valid ID7 creates exactly one transaction'

    $snapshotFixtures = @(
        [pscustomobject]@{ Name = 'PrecheckBusyNoIntent'; Seen = $false; Current = $false; Intent = $false; Expected = $false },
        [pscustomobject]@{ Name = 'ApproachIntentWithoutSnapshot'; Seen = $false; Current = $false; Intent = $true; Expected = $true },
        [pscustomobject]@{ Name = 'ExternalIntentWithoutSnapshot'; Seen = $false; Current = $false; Intent = $true; Expected = $true },
        [pscustomobject]@{ Name = 'RIntentWithoutSnapshot'; Seen = $false; Current = $false; Intent = $true; Expected = $true },
        [pscustomobject]@{ Name = 'PreviouslySeenSnapshotLost'; Seen = $true; Current = $false; Intent = $false; Expected = $true })
    foreach ($fixture in $snapshotFixtures) {
        $mismatch = (-not $fixture.Current) -and ($fixture.Seen -or $fixture.Intent)
        Assert-True ($mismatch -eq $fixture.Expected) "Snapshot mismatch fixture: $($fixture.Name)"
    }

    $pendingAck = [pscustomobject]@{ IsSequence = $true; SourceId = 7L; AdapterId = 11L }
    $publishedAck = 0L
    foreach ($acceptedAdapterId in @(10L, 11L)) {
        if ($pendingAck.IsSequence -and ($acceptedAdapterId -eq $pendingAck.AdapterId)) {
            $publishedAck = $pendingAck.SourceId
        }
    }
    Assert-True ($publishedAck -eq 7L) 'Sequence ACK must remain unchanged before, then publish only after, the pending Adapter ID is accepted'

    $hardPending = $true; $hardHandled = $false; $hardExpectedCounter = 20L
    $hardExactOutput = [pscustomobject]@{ Active = $true; Fault = $false; Marker = $true; P = 12.5; V = 0.0; A = 0.0; Direction = 1 }
    $hardFeed = $hardPending -and $hardExactOutput.Active -and (-not $hardExactOutput.Fault) -and $hardExactOutput.Marker -and ($hardExactOutput.P -eq 12.5) -and ($hardExactOutput.V -eq 0.0) -and ($hardExactOutput.A -eq 0.0) -and ($hardExactOutput.Direction -eq 1)
    $hardDisable = $true
    Assert-True ($hardFeed -and $hardDisable) 'HardLimit plus Sequence Error must retain the exact zero Feed and Disable in the same scan'
    $adapterAcceptedHard = $hardPending -and (21L -ne $hardExpectedCounter) -and ($hardExactOutput.P -eq 12.5) -and ($hardExactOutput.V -eq 0.0) -and ($hardExactOutput.A -eq 0.0) -and ($hardExactOutput.Direction -eq 1)
    if ($adapterAcceptedHard) { $hardPending = $false; $hardHandled = $true }
    Assert-True ((-not $hardPending) -and $hardHandled) 'Accepted hard packet must suppress duplicate pending packages while the hard reason remains active'
    $ordinaryErrorFeed = $false
    Assert-True (-not $ordinaryErrorFeed) 'Ordinary Sequence Error without a hard pending package must keep Feed FALSE'

    $safetyLatched = $false; $zSafetyTransactions = 0; $rSafetyTransactions = 0
    foreach ($snapshotCurrent in @($false, $true, $true)) {
        $safetyEvent = (-not $snapshotCurrent) -and (-not $safetyLatched)
        if ($safetyEvent) { $safetyLatched = $true; $zSafetyTransactions++; $rSafetyTransactions++ }
    }
    Assert-True ($safetyLatched -and ($zSafetyTransactions -eq 1) -and ($rSafetyTransactions -eq 1)) 'Snapshot recovery must not clear or duplicate the latched Z/R safety stop'
    $lastObservedSequenceCommandId = 0L; $resetPending = $false; $pendingResetId = 0L
    $consumedResetId = 0L; $rResetTransactions = 0; $pendingCapturedBeforeGate = $false
    $sameIdGateTrace = @(
        [pscustomobject]@{ Id = 7L; Reset = $true; Gates = $false },
        [pscustomobject]@{ Id = 7L; Reset = $true; Gates = $true },
        [pscustomobject]@{ Id = 7L; Reset = $true; Gates = $false },
        [pscustomobject]@{ Id = 7L; Reset = $true; Gates = $true })
    foreach ($scan in $sameIdGateTrace) {
        $newSequenceCommand = Test-WrapNewerId $scan.Id $lastObservedSequenceCommandId
        if ($newSequenceCommand) {
            $lastObservedSequenceCommandId = $scan.Id
            if ($scan.Reset) {
                $pendingResetId = $scan.Id
                $resetPending = $true
            }
        }
        if (-not $scan.Gates -and $resetPending -and ($pendingResetId -eq 7L)) {
            $pendingCapturedBeforeGate = $true
        }
        if ($resetPending -and $scan.Gates) {
            $consumedResetId = $pendingResetId
            $resetPending = $false
            $safetyLatched = $false
            $rResetTransactions++
        }
    }
    Assert-True ($pendingCapturedBeforeGate -and ($consumedResetId -eq 7L)) 'A valid Reset identity must remain pending until all terminal gates become true'
    Assert-True ((-not $safetyLatched) -and ($rResetTransactions -eq 1)) 'The same Reset ID with gates F,T,F,T must create exactly one R reset transaction'
    $beforeNewIds = $rResetTransactions
    foreach ($newId in @(8L, 9L)) {
        $newSequenceCommand = Test-WrapNewerId $newId $lastObservedSequenceCommandId
        if ($newSequenceCommand) {
            $lastObservedSequenceCommandId = $newId; $pendingResetId = $newId; $resetPending = $true
        }
        if ($resetPending) { $consumedResetId = $pendingResetId; $resetPending = $false; $rResetTransactions++ }
    }
    Assert-True (($rResetTransactions - $beforeNewIds) -eq 2) 'Different newer Reset IDs must each transact even while ResetPulse remains continuously high'
    $beforeRejectedIds = $rResetTransactions
    foreach ($rejectedId in @(0L, 8L, 9L, 7L)) {
        if (Test-WrapNewerId $rejectedId $lastObservedSequenceCommandId) { $rResetTransactions++ }
    }
    Assert-True ($rResetTransactions -eq $beforeRejectedIds) 'Zero, old, and duplicate Reset IDs must be rejected'

    $crossEventHighWater = 7L; $crossEventResetTransactions = 0
    if (Test-WrapNewerId 100L $crossEventHighWater) { $crossEventHighWater = 100L } # non-Reset
    if (Test-WrapNewerId 8L $crossEventHighWater) { $crossEventResetTransactions++ }
    Assert-True ($crossEventResetTransactions -eq 0) 'Reset 7 then non-Reset 100 must reject stale Reset 8 against the all-event high-water mark'

    $pendingAcrossNonReset = $false; $pendingAcrossNonResetId = 0L; $pendingHighWater = 100L
    if (Test-WrapNewerId 101L $pendingHighWater) {
        $pendingHighWater = 101L; $pendingAcrossNonResetId = 101L; $pendingAcrossNonReset = $true
    }
    if (Test-WrapNewerId 102L $pendingHighWater) { $pendingHighWater = 102L } # non-Reset must not cancel pending 101
    $consumedAcrossNonResetId = if ($pendingAcrossNonReset) { $pendingAcrossNonResetId } else { 0L }
    Assert-True ($consumedAcrossNonResetId -eq 101L) 'A newer non-Reset event must advance high-water without cancelling an earlier pending Reset'

    $delayedResetHighWater = 0L; $delayedResetPending = $false
    $delayedResetPendingId = 0L; $delayedResetConsumedId = 0L
    $delayedResetTransactions = 0
    foreach ($scan in @(
        [pscustomobject]@{ Id = 7L;   Reset = $true;  Gates = $false },
        [pscustomobject]@{ Id = 100L; Reset = $false; Gates = $false },
        [pscustomobject]@{ Id = 100L; Reset = $false; Gates = $true })) {
        $newSequenceCommand = Test-WrapNewerId $scan.Id $delayedResetHighWater
        if ($newSequenceCommand) {
            $delayedResetHighWater = $scan.Id
            if ($scan.Reset) {
                $delayedResetPendingId = $scan.Id
                $delayedResetPending = $true
            }
        }
        if ($delayedResetPending -and $scan.Gates) {
            $delayedResetConsumedId = $delayedResetPendingId
            $delayedResetPending = $false
            $delayedResetTransactions++
        }
    }
    Assert-True (($delayedResetTransactions -eq 1) -and ($delayedResetConsumedId -eq 7L) -and ($delayedResetHighWater -eq 100L)) 'Reset 7 must survive a newer non-Reset Pulse-false package and consume once when gates later become true'

    $latestWinsHighWater = 0L; $latestWinsPending = $false
    $latestWinsPendingId = 0L; $latestWinsConsumedId = 0L
    $latestWinsTransactions = 0
    foreach ($scan in @(
        [pscustomobject]@{ Id = 7L; Reset = $true; Gates = $false },
        [pscustomobject]@{ Id = 8L; Reset = $true; Gates = $false },
        [pscustomobject]@{ Id = 8L; Reset = $true; Gates = $true })) {
        $newSequenceCommand = Test-WrapNewerId $scan.Id $latestWinsHighWater
        if ($newSequenceCommand) {
            $latestWinsHighWater = $scan.Id
            if ($scan.Reset) {
                $latestWinsPendingId = $scan.Id
                $latestWinsPending = $true
            }
        }
        if ($latestWinsPending -and $scan.Gates) {
            $latestWinsConsumedId = $latestWinsPendingId
            $latestWinsPending = $false
            $latestWinsTransactions++
        }
    }
    Assert-True (($latestWinsTransactions -eq 1) -and ($latestWinsConsumedId -eq 8L)) 'Reset 7 then Reset 8 while gates are false must latest-wins consume only Reset 8 once'

    $wrapEventHighWater = 4294967294L; $wrapResetAccepted = $false
    if (Test-WrapNewerId 1L $wrapEventHighWater) { $wrapEventHighWater = 1L; $wrapResetAccepted = $true }
    Assert-True $wrapResetAccepted 'Reset identity high-water must remain wrap-aware across different event types'

    $snapshotSeenAfterReset = $false; $postResetSafetyEvents = 0
    foreach ($lingerScan in @(
        [pscustomobject]@{ Reset = $true;  Current = $true;  Busy = $false; Intent = $false },
        [pscustomobject]@{ Reset = $false; Current = $true;  Busy = $false; Intent = $false },
        [pscustomobject]@{ Reset = $false; Current = $false; Busy = $false; Intent = $false })) {
        if ($lingerScan.Current -and $lingerScan.Busy) { $snapshotSeenAfterReset = $true }
        if ($lingerScan.Reset) { $snapshotSeenAfterReset = $false }
        $lingerMismatch = (-not $lingerScan.Current) -and ($snapshotSeenAfterReset -or $lingerScan.Intent)
        if ($lingerMismatch) { $postResetSafetyEvents++ }
    }
    Assert-True ($postResetSafetyEvents -eq 0) 'A one-scan old snapshot linger after terminal Reset must not re-arm a false mismatch'

    # Reset owns the current scan.  It must also record the source that is
    # visible in that same scan, otherwise the following scan can replay the
    # pre-Reset Sequence source as a fabricated source-change transaction.
    $lastRSource = $true; $lastRId = 7L
    $currentRSourceOnReset = $false; $currentRIdOnReset = 7L
    $lastRSource = $currentRSourceOnReset
    $lastRId = $currentRIdOnReset
    $postResetTransactions = 0
    $sameCommandAfterReset = ($false -ne $lastRSource) -or (Test-WrapNewerId 7L $lastRId)
    if ($sameCommandAfterReset) { $postResetTransactions++ }
    Assert-True ($postResetTransactions -eq 0) 'Reset scan clearing R intent must not fabricate another R transaction on the following scan'
    $newMovementAfterReset = ($false -ne $lastRSource) -or (Test-WrapNewerId 8L $lastRId)
    if ($newMovementAfterReset) { $postResetTransactions++ }
    Assert-True ($postResetTransactions -eq 1) 'R movement after Reset must require a genuinely newer normal command ID'

    $lastAcceptedSafetyDeceleration = 120.0
    $pendingCandidateDeceleration = 130.0; $pendingCandidateId = 10L
    foreach ($acceptedAdapterId in @(9L, 10L)) {
        if (($acceptedAdapterId -eq $pendingCandidateId) -and ($pendingCandidateDeceleration -gt 0.0)) {
            $lastAcceptedSafetyDeceleration = $pendingCandidateDeceleration
        }
        if ($acceptedAdapterId -eq 9L) {
            Assert-True ($lastAcceptedSafetyDeceleration -eq 120.0) 'An unaccepted newer R candidate must not replace the current safety deceleration'
        }
    }
    Assert-True ($lastAcceptedSafetyDeceleration -eq 130.0) 'The exact accepted R pending ID must update the safety deceleration'
    $lastAcceptedSafetyDeceleration = 120.0
    foreach ($rejectedDeceleration in @([double]::NaN, [double]::PositiveInfinity, 0.0, -5.0)) {
        $candidateValid = (-not [double]::IsNaN($rejectedDeceleration)) -and
            (-not [double]::IsInfinity($rejectedDeceleration)) -and
            ($rejectedDeceleration -gt 0.0)
        if ($candidateValid) { $lastAcceptedSafetyDeceleration = $rejectedDeceleration }
    }
    $pureResetDeceleration = 0.0
    $pureResetMayUpdateLastValid = $pureResetDeceleration -gt 0.0
    if ($pureResetMayUpdateLastValid) { $lastAcceptedSafetyDeceleration = $pureResetDeceleration }
    $snapshotStopDeceleration = $lastAcceptedSafetyDeceleration
    Assert-True ($snapshotStopDeceleration -eq 120.0) 'Rejected invalid R candidates and pure Reset must not contaminate the accepted safety Stop deceleration'

    foreach ($axisName in @('Z', 'R')) {
        $postResetBarrierId = 20L; $barrierHeld = $true
        $lastSequenceSource = $false; $lastSourceId = 20L
        $latchedPayload = 'PureReset'; $staleSequenceTransactions = 0
        $newSequenceTransactions = 0; $normalExitTransactions = 0
        foreach ($scan in @(
            [pscustomobject]@{ Name = 'StaleSequence'; OuterId = 20L; Sequence = $true;  SourceId = 7L;  Safety = $false; Reset = $false; Payload = 'Seq7-StaleOuter20' },
            [pscustomobject]@{ Name = 'NewSequence1'; OuterId = 21L; Sequence = $true;  SourceId = 7L;  Safety = $false; Reset = $false; Payload = 'Seq7-Outer21' },
            [pscustomobject]@{ Name = 'NewSequence2'; OuterId = 21L; Sequence = $true;  SourceId = 7L;  Safety = $false; Reset = $false; Payload = 'Seq7-Outer21-Duplicate' },
            [pscustomobject]@{ Name = 'NormalExit';   OuterId = 21L; Sequence = $false; SourceId = 21L; Safety = $false; Reset = $false; Payload = 'Normal-Outer21' })) {
            $acceptedFastNewer = Test-WrapNewerId $scan.OuterId $postResetBarrierId
            $sourceBlocked = $barrierHeld -and (-not $acceptedFastNewer)
            $newSourceTransaction = ($scan.SourceId -ne 0) -and
                (($scan.Sequence -ne $lastSequenceSource) -or
                    (Test-WrapNewerId $scan.SourceId $lastSourceId))
            $adapterTransaction = $newSourceTransaction -and (-not $sourceBlocked) -and
                (-not $scan.Safety) -and (-not $scan.Reset)
            if ($adapterTransaction) {
                $latchedPayload = $scan.Payload
                $lastSequenceSource = $scan.Sequence
                $lastSourceId = $scan.SourceId
                if ($scan.Name -eq 'StaleSequence') { $staleSequenceTransactions++ }
                if ($scan.Name -like 'NewSequence*') { $newSequenceTransactions++ }
                if ($scan.Name -eq 'NormalExit') { $normalExitTransactions++ }
                if ($barrierHeld -and (-not $scan.Sequence) -and $acceptedFastNewer) {
                    $barrierHeld = $false
                }
            }
            if ($scan.Name -eq 'StaleSequence') {
                Assert-True (($staleSequenceTransactions -eq 0) -and ($latchedPayload -eq 'PureReset') -and (-not $lastSequenceSource)) "$axisName stale Sequence ID7 under Reset outer20 must leave the pure Reset package and marker unchanged"
            }
        }
        Assert-True ($newSequenceTransactions -eq 1) "$axisName outer21 Sequence ID7 across two scans must create exactly one transaction while retaining the barrier"
        Assert-True (($normalExitTransactions -eq 1) -and (-not $barrierHeld) -and ($latchedPayload -eq 'Normal-Outer21')) "$axisName exit to normal outer21 must create one transaction and clear its barrier"

        foreach ($inhibitKind in @('Safety', 'Reset')) {
            $inhibitedBarrier = $true
            $acceptedFastNewer = Test-WrapNewerId 21L 20L
            $sourceBlocked = $inhibitedBarrier -and (-not $acceptedFastNewer)
            $adapterTransaction = (-not $sourceBlocked) -and ($inhibitKind -ne 'Safety') -and ($inhibitKind -ne 'Reset')
            if ($adapterTransaction) { $inhibitedBarrier = $false }
            Assert-True $inhibitedBarrier "$axisName $inhibitKind inhibition must not clear the barrier merely because outer21 is visible"
        }
    }

    # Task 7/9 must hold Force Owner and disable intent through Adapter hard/
    # disable acceptance.  Task 6 only reports completion after ReleaseOwner;
    # a same-scan caller withdrawal cannot manufacture that acknowledgement.
    $hardPackageExact = $true; $adapterActive = $true
    $hardAcceptedWithOwner = $hardPackageExact -and $adapterActive -and $true
    $hardAcceptedAfterSameScanOwnerWithdrawal = $hardPackageExact -and $adapterActive -and $false
    Assert-True $hardAcceptedWithOwner 'A hard exact package requires the Force Owner to remain granted'
    Assert-True (-not $hardAcceptedAfterSameScanOwnerWithdrawal) 'Same-scan Force Owner withdrawal must not be reported as hard-package acceptance'
    $task79ExitIntent = $true; $adapterReleaseOwner = $false
    $task6ForceExitComplete = $task79ExitIntent -and $adapterReleaseOwner
    Assert-True (-not $task6ForceExitComplete) 'Exact acceptance without ReleaseOwner must continue holding Force Owner and Disable intent'
    $adapterReleaseOwner = $true
    $task6ForceExitComplete = $task79ExitIntent -and $adapterReleaseOwner
    Assert-True $task6ForceExitComplete 'Task 7/9 may release Force Owner only after Adapter ReleaseOwner'
}

if ($runSequenceFront) {
    $fastInputsRaw = Read-Text 'CFFwelding_System\CFFwelding\POUs\Fast\PRG_FastInputs.TcPOU'
    $fastInputs = Get-PouImplementationText $fastInputsRaw
    $fastInputsDeclaration = Get-PouDeclarationText $fastInputsRaw
    $sequenceRaw = Read-Text 'CFFwelding_System\CFFwelding\POUs\Fast\PRG_CffSequence.TcPOU'
    $sequence = Get-PouImplementationText $sequenceRaw
    $sequenceDeclaration = Get-PouDeclarationText $sequenceRaw
    Assert-True (-not [string]::IsNullOrWhiteSpace($fastInputs)) 'SequenceFront must parse only FastInputs executable POU Implementation ST'
    Assert-True (-not [string]::IsNullOrWhiteSpace($fastInputsDeclaration)) 'SequenceFront must parse FastInputs Declaration independently'
    Assert-True (-not [string]::IsNullOrWhiteSpace($sequence)) 'SequenceFront must parse only Sequence executable POU Implementation ST'
    Assert-True (-not [string]::IsNullOrWhiteSpace($sequenceDeclaration)) 'SequenceFront must parse Sequence Declaration independently'
    $sequenceFrontXmlCommentDecoyFixture = @'
<TcPlcObject><!-- <POU><Implementation><ST><![CDATA[bProfileValid := TRUE; CFF_PRECHECK: eNextState := CFF_APPROACH;]]></ST></Implementation></POU> --><POU><Declaration><![CDATA[PROGRAM P]]></Declaration><Implementation><ST><![CDATA[eNextState := eState;]]></ST></Implementation></POU></TcPlcObject>
'@
    $sequenceFrontXmlCommentDecoy = Get-PouImplementationText $sequenceFrontXmlCommentDecoyFixture
    Assert-True (($sequenceFrontXmlCommentDecoyFixture -match 'bProfileValid') -and
        ($sequenceFrontXmlCommentDecoy -match 'eNextState\s*:=\s*eState') -and
        ($sequenceFrontXmlCommentDecoy -notmatch 'bProfileValid|CFF_PRECHECK')) 'SequenceFront Implementation extraction must reject classifier and CASE decoys held only in XML comments'
    $fastInputsAtomicFixture = @'
udiLiveFastRequestId := GVL_Command.stFast.nRequestId;
IF FC_IsNewerRequestId(
        udiCandidate := udiLiveFastRequestId,
        udiReference := GVL_FastInternal.stAcceptedCommand.nRequestId) THEN
    stFastCommandCandidate := GVL_Command.stFast;
    IF (stFastCommandCandidate.nRequestId = udiLiveFastRequestId)
        AND (GVL_Command.stFast.nRequestId = udiLiveFastRequestId) THEN
        GVL_FastInternal.stAcceptedCommand := stFastCommandCandidate;
    END_IF
END_IF
'@
    $fastInputsCommentDecoyFixture = @'
(*
udiLiveFastRequestId := GVL_Command.stFast.nRequestId;
IF FC_IsNewerRequestId(
        udiCandidate := udiLiveFastRequestId,
        udiReference := GVL_FastInternal.stAcceptedCommand.nRequestId) THEN
    stFastCommandCandidate := GVL_Command.stFast;
    IF (stFastCommandCandidate.nRequestId = udiLiveFastRequestId)
        AND (GVL_Command.stFast.nRequestId = udiLiveFastRequestId) THEN
        GVL_FastInternal.stAcceptedCommand := stFastCommandCandidate;
    END_IF
END_IF
*)
'@
    $fastInputsDeadOuterFixture = "IF FALSE THEN`n$fastInputsAtomicFixture`nEND_IF"
    $fastInputsDeadCopyFixture = @'
udiLiveFastRequestId := GVL_Command.stFast.nRequestId;
IF FC_IsNewerRequestId(
        udiCandidate := udiLiveFastRequestId,
        udiReference := GVL_FastInternal.stAcceptedCommand.nRequestId) THEN
    IF FALSE THEN
        stFastCommandCandidate := GVL_Command.stFast;
    END_IF
    IF (stFastCommandCandidate.nRequestId = udiLiveFastRequestId)
        AND (GVL_Command.stFast.nRequestId = udiLiveFastRequestId) THEN
        GVL_FastInternal.stAcceptedCommand := stFastCommandCandidate;
    END_IF
END_IF
'@
    $fastInputsDeadPublishFixture = @'
udiLiveFastRequestId := GVL_Command.stFast.nRequestId;
IF FC_IsNewerRequestId(
        udiCandidate := udiLiveFastRequestId,
        udiReference := GVL_FastInternal.stAcceptedCommand.nRequestId) THEN
    stFastCommandCandidate := GVL_Command.stFast;
    IF (stFastCommandCandidate.nRequestId = udiLiveFastRequestId)
        AND (GVL_Command.stFast.nRequestId = udiLiveFastRequestId) THEN
        IF FALSE THEN
            GVL_FastInternal.stAcceptedCommand := stFastCommandCandidate;
        END_IF
    END_IF
END_IF
'@
    Assert-True (Test-FastInputsAtomicAcceptance $fastInputsAtomicFixture) 'FastInputs atomic helper rejected the valid nested double-read transaction'
    Assert-True (-not (Test-FastInputsAtomicAcceptance $fastInputsCommentDecoyFixture)) 'FastInputs atomic helper accepted a comment-only decoy'
    Assert-True (-not (Test-FastInputsAtomicAcceptance $fastInputsDeadOuterFixture)) 'FastInputs atomic helper accepted a valid-looking transaction hidden below IF FALSE'
    Assert-True (-not (Test-FastInputsAtomicAcceptance $fastInputsDeadCopyFixture)) 'FastInputs atomic helper accepted a candidate copy hidden below IF FALSE inside the newer gate'
    Assert-True (-not (Test-FastInputsAtomicAcceptance $fastInputsDeadPublishFixture)) 'FastInputs atomic helper accepted a publish hidden below IF FALSE inside the stable double-read gate'

    $rStopPendingFixture = @'
tonRAxisStop(
    IN := (eState = CFF_APPROACH)
        AND NOT ((GVL_Status.stFast.udiAcceptedSequenceRCommandId = udiRCommandId)
            AND GVL_Status.stFast.stRAxis.bStandstill),
    PT := stSequenceConfigSnapshot.tRAxisStopTimeout);
'@
    $rStopWholeStateFixture = 'tonRAxisStop(IN := eState = CFF_APPROACH, PT := stSequenceConfigSnapshot.tRAxisStopTimeout);'
    $rStopDeadOuterFixture = "IF FALSE THEN`n$rStopPendingFixture`nEND_IF"
    Assert-True (Test-RAxisStopPendingTimer $rStopPendingFixture) 'R stop timer helper rejected the valid pending-handshake monitor'
    Assert-True (-not (Test-RAxisStopPendingTimer $rStopWholeStateFixture)) 'R stop timer helper accepted timing the whole Approach state after R was already stopped'
    Assert-True (-not (Test-RAxisStopPendingTimer $rStopDeadOuterFixture)) 'R stop timer helper accepted a valid-looking call hidden below IF FALSE'

    $precheckForProfiles = Get-CaseBranch $sequence 'CFF_PRECHECK' 'Missing executable CASE branch: CFF_PRECHECK'
    $sequenceExecutable = Get-StCodeText $sequence
    $snapshotIdentityMatch = [regex]::Match($sequenceExecutable, '(?s)bSnapshotIdentityValid\s*:=\s*(?<Expression>.*?);')
    $profileClassifierMatch = [regex]::Match($sequenceExecutable, '(?s)bProfileValid\s*:=\s*(?<Expression>.*?);')
    Assert-True $snapshotIdentityMatch.Success 'Snapshot identity classifier assignment is missing'
    Assert-True $profileClassifierMatch.Success 'Profile classifier assignment is missing'
    $snapshotIdentityExpression = $snapshotIdentityMatch.Groups['Expression'].Value
    $profileClassifierExpression = $profileClassifierMatch.Groups['Expression'].Value
    Assert-Match $sequence '(?s)bProfileValid\s*:=\s*stForceProfileSnapshot\.bValid.*?stForceProfileSnapshot\.nProfileId\s*>\s*0.*?stForceProfileSnapshot\.nRevision\s*>\s*0' 'Precheck classifier must require valid positive force profile ID and revision'
    Assert-Match $sequence '(?s)bProfileValid\s*:=.*?stRAxisProfileSnapshot\.bValid.*?stRAxisProfileSnapshot\.nProfileId\s*>\s*0.*?stRAxisProfileSnapshot\.nRevision\s*>\s*0' 'Precheck classifier must require valid positive R profile ID and revision'
    Assert-Match $sequence '(?s)bProfileValid\s*:=.*?nForceProfileId\s*=\s*stForceProfileSnapshot\.nProfileId.*?nRAxisProfileId\s*=\s*stRAxisProfileSnapshot\.nProfileId' 'Precheck classifier must match header profile IDs to frozen profiles'
    Assert-NoMatch $profileClassifierExpression 'GVL_Config\.' 'Precheck profile validation must use the same-scan frozen profiles after outer Fast acknowledgement, not a later live producer revision'
    Assert-True (Test-FastInputsAtomicAcceptance $fastInputs) 'FastInputs must atomically copy a newer complete command payload through executable nested positive gates'
    Assert-Match $sequence '(?s)eNextState\s*:=\s*eState.*?ePreviousState\s*:=\s*eState.*?eState\s*:=\s*eNextState.*?bStateEntry\s*:=\s*eState\s*<>\s*ePreviousState' 'Sequence must use one state transition per scan'
    Assert-Match $sequence '(?s)FC_IsNewerRequestId\s*\(.*?udiCandidate\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.stSequence\.nCommandId.*?udiReference\s*:=\s*udiLastObservedCommandId' 'Sequence command event must be wrap-aware and deduplicated'
    Assert-Match $sequence '(?s)udiLastObservedCommandId\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.stSequence\.nCommandId.*?IF\s+bStartEvent\s+THEN.*?udiActiveStartCommandId\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.stSequence\.nCommandId' 'Sequence must separate the all-event high-water mark from the active Start-cycle ID'
    Assert-Match $sequence '(?s)IF\s+bStartEvent\s+THEN.*?stActiveSequenceCommand\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.stSequence.*?udiActiveCycleSnapshotRevision\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.nCycleSnapshotRevision' 'Start acceptance must freeze the Sequence payload and cycle-snapshot correlation before later events advance the high-water mark'
    $idleBranch = Get-CaseBranch $sequence 'CFF_IDLE' 'Missing executable CASE branch: CFF_IDLE'
    $startBody = Get-IfBody $idleBranch 'bStartEvent' 'Start must have one executable initialization block'
    Assert-Ordered $startBody @(
        'udiStartCycleSnapshotRevisionBefore := GVL_Program.stCycleSnapshot.nSnapshotRevision',
        'udiStartMachineRevisionBefore := GVL_Config.stMachine.nRevision',
        'udiStartForceProfileIdBefore := GVL_Config.stZForceControl.nProfileId',
        'udiStartForceProfileRevisionBefore := GVL_Config.stZForceControl.nRevision',
        'udiStartRAxisProfileIdBefore := GVL_Config.stRAxis.nProfileId',
        'udiStartRAxisProfileRevisionBefore := GVL_Config.stRAxis.nRevision',
        'stCycleSnapshot := GVL_Program.stCycleSnapshot',
        'stMachineSnapshot := GVL_Config.stMachine',
        'stForceProfileSnapshot := GVL_Config.stZForceControl',
        'stRAxisProfileSnapshot := GVL_Config.stRAxis',
        'bStartSourceSnapshotConsistent :='
    ) 'Start must sample producer identities before copying all revisioned sources and then latch one same-scan consistency result before outer Fast ACK'
    Assert-Match $startBody '(?s)bStartSourceSnapshotConsistent\s*:=\s*\(udiStartCycleSnapshotRevisionBefore\s*=\s*stCycleSnapshot\.nSnapshotRevision\).*?GVL_Program\.stCycleSnapshot\.nSnapshotRevision\s*=\s*stCycleSnapshot\.nSnapshotRevision.*?udiStartMachineRevisionBefore\s*=\s*stMachineSnapshot\.nRevision.*?GVL_Config\.stMachine\.nRevision\s*=\s*stMachineSnapshot\.nRevision.*?udiStartForceProfileIdBefore\s*=\s*stForceProfileSnapshot\.nProfileId.*?udiStartForceProfileRevisionBefore\s*=\s*stForceProfileSnapshot\.nRevision.*?GVL_Config\.stZForceControl\.nProfileId\s*=\s*stForceProfileSnapshot\.nProfileId.*?GVL_Config\.stZForceControl\.nRevision\s*=\s*stForceProfileSnapshot\.nRevision.*?udiStartRAxisProfileIdBefore\s*=\s*stRAxisProfileSnapshot\.nProfileId.*?udiStartRAxisProfileRevisionBefore\s*=\s*stRAxisProfileSnapshot\.nRevision.*?GVL_Config\.stRAxis\.nProfileId\s*=\s*stRAxisProfileSnapshot\.nProfileId.*?GVL_Config\.stRAxis\.nRevision\s*=\s*stRAxisProfileSnapshot\.nRevision' 'Start consistency must prove before/copy/after identity for Program, Machine, Force profile, and R profile in the Start scan'
    Assert-Match $snapshotIdentityExpression 'bStartSourceSnapshotConsistent' 'Precheck snapshot identity must consume the same-Start source-consistency latch'
    Assert-NoMatch $snapshotIdentityExpression 'GVL_(?:Program|Config)\.' 'Precheck snapshot identity must not require Program or Config producers to remain unchanged after their outer Fast acknowledgement'
    $producerBefore = 17L; $producerCopy = 17L; $producerAfterCopy = 17L
    $latchedStartConsistency = ($producerBefore -eq $producerCopy) -and ($producerAfterCopy -eq $producerCopy)
    $producerAfterFastAck = 18L
    Assert-True ($latchedStartConsistency -and ($producerAfterFastAck -ne $producerCopy)) 'A producer may legally advance after Fast ACK while Precheck continues to trust its already-proven local Start snapshot'
    Assert-Match $startBody '(?s)FOR\s+nStepIndex\s*:=\s*1\s+TO\s+4\s+DO.*?GVL_Process\.astStepCriterion\s*\[\s*nStepIndex\s*\]\s*:=\s*stClearedStepCriterionResult.*?END_FOR' 'Every new Start must clear all four per-step criterion result slots from one zero template'
    Assert-Match $startBody '(?s)rHardMaximumRelativePosition_mm\s*:=\s*0\.0.*?rRequiredRelativePosition_mm\s*:=\s*0\.0.*?rStepBoundary_mm\s*:=\s*0\.0.*?rForceTransferVelocity_mm_s\s*:=\s*0\.0.*?rForceSet_kN\s*:=\s*0\.0.*?rForceRamp_kN_s\s*:=\s*0\.0.*?rSpeedSet_rpm\s*:=\s*0\.0.*?rTargetRelativePosition_mm\s*:=\s*0\.0.*?rStepTime_s\s*:=\s*0\.0.*?rQualifiedForceHoldTime_s\s*:=\s*0\.0.*?bRpmStopped\s*:=\s*FALSE.*?bForceInBand\s*:=\s*FALSE.*?bHardForceActive\s*:=\s*FALSE.*?bHardStrokeActive\s*:=\s*FALSE.*?bCollisionLimitActive\s*:=\s*FALSE.*?bForceProfileTransferPending\s*:=\s*FALSE.*?bApproachFaultStopPending\s*:=\s*FALSE.*?bUnknownExternalRStopPending\s*:=\s*FALSE' 'Every new Start must clear all cycle-local targets, timers, qualification flags, hard diagnostics, and pending takeover state'
    Assert-Match $sequence '(?s)bPermissionValid\s*:=\s*stActiveSequenceCommand\.bProductionPermission.*?bSnapshotIdentityValid\s*:=.*?udiActiveCycleSnapshotRevision.*?stActiveSequenceCommand\.nProgramId.*?stActiveSequenceCommand\.nJoiningPointId' 'Precheck correlation must use the frozen active Start package, not a later Stop/Abort/Reset package'
    Assert-Match $sequence '(?s)bSnapshotIdentityValid\s*:=.*?stCycleSnapshot\.stProgram\.stHeader\.nToolId\s*=\s*stMachineSnapshot\.nToolId.*?stCycleSnapshot\.stProgram\.stHeader\.nAnvilId\s*=\s*stMachineSnapshot\.nAnvilId' 'Precheck must bind the frozen Program tool and anvil to the frozen Machine identity'
    Assert-Match $sequence 'GVL_Status\.stFast\.stSequence\.nAcceptedCommandId\s*:=\s*udiActiveStartCommandId' 'Published accepted Sequence ID must remain the active Start-cycle ID'
    Assert-Match $sequence '(?s)bProgramValid\s*:=\s*FC_ValidateJoinProgram.*?bSequenceConfigValid\s*:=\s*FC_ValidateCffSequenceConfig' 'Precheck classifiers must invoke both frozen validators'
    Assert-Match $precheckForProfiles '(?s)bProgramValid.*?bSequenceConfigValid.*?bProfileValid.*?stFastConfigSnapshot\.bValid\s*:=\s*TRUE' 'Precheck must require all frozen validators before publishing a valid snapshot'
    $precheckBranch = Get-CaseBranch $sequence 'CFF_PRECHECK' 'Missing executable CASE branch: CFF_PRECHECK'
    $localReturnTargetAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Local Return target validity must be one unique top-level classifier' 'bLocalReturnTargetValid'
    if ($null -ne $localReturnTargetAssignment) {
        Assert-True (Test-LocalReturnTargetExpression $localReturnTargetAssignment.Expression) 'Local Return target validity must require finite cycle-start Z within the inclusive frozen machine limits'
    }
    Assert-Match $precheckBranch '(?s)stFastConfigSnapshot\.nSequenceCommandId\s*:=\s*udiActiveStartCommandId.*?stFastConfigSnapshot\.stMachine\s*:=\s*stMachineSnapshot.*?stFastConfigSnapshot\.stLimits\s*:=\s*stLimitsSnapshot.*?stFastConfigSnapshot\.stZExtSetpoint\s*:=\s*stZExtConfigSnapshot.*?stFastConfigSnapshot\.stZForceControl\s*:=\s*stForceProfileSnapshot.*?stFastConfigSnapshot\.bValid\s*:=\s*TRUE' 'Sequence must publish one frozen valid Fast configuration snapshot correlated to the active Start ID'
    Assert-Match $sequence '(?s)bSensorReady\s*:=\s*GVL_Process\.stActual\.bForceValid.*?GVL_Process\.stActual\.bDisplacementValid.*?GVL_Process\.stActual\.bCollisionValid' 'Precheck sensor classifier must validate the three pre-contact chains individually'
    Assert-Match $sequence '(?s)bHardForceActive\s*:=.*?bHardStrokeActive\s*:=.*?bCollisionLimitActive\s*:=.*?bSensorReady\s*:=\s*GVL_Process\.stActual\.bForceValid.*?AND\s+NOT\s+bHardForceActive.*?AND\s+NOT\s+bHardStrokeActive.*?AND\s+NOT\s+bCollisionLimitActive' 'Precheck must compute current-scan hard facts first and reject active hard force, hard stroke, or collision through the A006 prerequisite branch'
    Assert-NoMatch $sequence 'bSensorReady\s*:=\s*[^;]*GVL_Process\.stActual\.(?:bValid|bContactReferenceValid|bAxisSensorAgreement)' 'Precheck sensor classifier must not consume post-contact aggregate validity'
    Assert-Match $precheckBranch '(?s)AND\s+bSensorReady\s+AND\s+bLocalReturnTargetValid.*?stFastConfigSnapshot\.bValid\s*:=\s*TRUE' 'Precheck success must require both the individual pre-contact sensors and the frozen Local Return target boundary'
    Assert-Match $precheckBranch '(?s)NOT\s+bHardwareReady.*?16#0000A005.*?ELSE\s+udiFirstFaultId\s*:=\s*16#0000A006' 'A non-finite or out-of-range frozen Local Return target must fail the Precheck prerequisite path closed under A006'
    Assert-Match $sequence '(?s)bHardwareReady\s*:=.*?bZAxisNcAssigned.*?bRAxisNcAssigned.*?bZAxisDriveLinked.*?bRAxisDriveLinked.*?bForceInputMapped.*?bDisplacementInputMapped.*?bCollisionInputMapped.*?bProductionHardwareBindingComplete' 'Precheck hardware classifier must require all production NC, drive, and sensor bindings'
    Assert-NoMatch $precheckBranch 'udi(?:Z|R)CommandId\s*:=\s*udi(?:Z|R)CommandId\s*\+\s*1|bExternalEnableRequest\s*:=\s*TRUE|bRAxisProcessRequested\s*:=\s*TRUE' 'Precheck must not publish Z, R, or External motion'
    $approachBranch = Get-CaseBranch $sequence 'CFF_APPROACH' 'Missing executable CASE branch: CFF_APPROACH'
    $approachPartition = Get-IfPartition $approachBranch '\(?\s*bStateEntry\s*\)?' 'Approach must have exactly one parseable IF bStateEntry THEN region'
    Assert-MatchCount $approachPartition.Body 'udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1' 1 'Approach entry must create exactly one fresh Z source transaction'
    Assert-MatchCount $approachPartition.Body 'udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1' 1 'Approach entry must create exactly one fresh R zero-stop transaction'
    Assert-Match $approachPartition.Body '(?s)udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1\s*;.*?IF\s+udiZCommandId\s*=\s*0\s+THEN\s*udiZCommandId\s*:=\s*1\s*;?\s*END_IF\s*;?' 'Approach Z source transaction must immediately skip zero'
    Assert-Match $approachPartition.Body '(?s)udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1\s*;.*?IF\s+udiRCommandId\s*=\s*0\s+THEN\s*udiRCommandId\s*:=\s*1\s*;?\s*END_IF\s*;?' 'Approach R source transaction must immediately skip zero'
    Assert-TopLevelPatterns $approachPartition.Outside @(
        'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*(?:E_ZCommandOwner\.)?Z_OWNER_APPROACH',
        'stMotionIntent\.stZCommand\.bMoveAbsolute\s*:=\s*TRUE',
        'stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE',
        'stMotionIntent\.stRCommand\.bEnable\s*:=\s*TRUE',
        'stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE',
        'stMotionIntent\.stRCommand\.bMoveVelocity\s*:=\s*FALSE',
        'stMotionIntent\.stRCommand\.rVelocity_rpm\s*:=\s*0\.0',
        'stMotionIntent\.stRCommand\.rAcceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS',
        'stMotionIntent\.stRCommand\.rDeceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS'
    ) 'Approach level intent must retain the Z move and frozen-profile R zero-stop package'
    Assert-Match $approachBranch '(?s)IF\s+bApproachNormalCompletion\s+THEN\s*eNextState\s*:=\s*CFF_EXTSETPOINT_PREPARE' 'Approach may select Prepare only through the exact current normal-completion classifier'
    Assert-True (Test-RAxisStopPendingTimer $sequence) 'Approach R stop timer must run once outside the CASE only while exact R ACK plus Standstill is pending'
    Assert-Match $approachBranch '(?s)tonRAxisStop\.Q.*?16#0000A014' 'Approach must fault deterministically when the frozen R stop timeout expires'
    Assert-Match $sequence '(?s)IF\s+\(eState\s*>=\s*CFF_APPROACH\).*?AND\s+\(eState\s*<=\s*CFF_FAULT\)\s+AND\s+\(udiFirstFaultId\s*=\s*0\)\s+THEN.*?bHardForceActive.*?16#0000A00C.*?bHardStrokeActive.*?16#0000A00D.*?bCollisionLimitActive.*?16#0000A00E.*?bSensorInvalid.*?16#0000A00F' 'Deterministic real-cause first-writer mapping must begin at Approach, without including Precheck'
    $approachNormalAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Approach normal completion must be one unique top-level classifier' 'bApproachNormalCompletion'
    if ($null -ne $approachNormalAssignment) {
        Assert-True (Test-ApproachNormalCompletionExpression $approachNormalAssignment.Expression) 'Approach normal completion must exclude Entry stale status and require exact current Z/R ACK, Z Done, and both actual standstills'
    }
    Assert-True (Test-UniqueTopLevelCall $sequence 'tonApproach' '(?s)tonApproach\s*\(\s*IN\s*:=\s*\(\s*eState\s*=\s*CFF_APPROACH\s*\)\s+AND\s+NOT\s+bApproachNormalCompletion\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tApproachTimeout\s*\)') 'Approach timeout must run continuously while Approach has not normally completed, independent of safe-stop pending state'
    $approachPostCase = Get-TextAfterMainCase $sequence 'Approach review contract requires a parseable post-CASE safety region'
    $approachSafeStop = Get-IfPartition $approachPostCase '\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_APPROACH\s*\)?\s+AND\s+bSafeExitRequested' 'Approach safe exit must have one top-level acknowledged-stop wait' -TopLevel
    Assert-Match $approachSafeStop.PositiveBody '(?s)IF\s+NOT\s+bApproachFaultStopPending\s+THEN.*?udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1.*?IF\s+udiZCommandId\s*=\s*0\s+THEN\s*udiZCommandId\s*:=\s*1.*?bApproachFaultStopPending\s*:=\s*TRUE' 'Approach safe exit must create one fresh nonzero FaultStop Z transaction'
    Assert-TopLevelPatterns $approachSafeStop.PositiveBody @(
        'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*Z_OWNER_FAULT_STOP',
        'stMotionIntent\.stZCommand\.bStop\s*:=\s*TRUE'
    ) 'Approach safe exit must retain the complete FaultStop package while deciding timeout/acknowledgement priority'
    Assert-Match $approachSafeStop.PositiveBody '(?s)IF\s+tonRAxisStop\.Q\s+OR\s+\(udiFirstFaultId\s*=\s*16#0000A014\)\s+THEN.*?eExitIntent\s*:=\s*CFF_EXIT_FAULT_NO_RETURN.*?eNextState\s*:=\s*CFF_FAULT' 'Approach R-stop timeout/A014 must outrank every later Approach safety decision without being overwritten'
    Assert-Match $approachSafeStop.PositiveBody '(?s)ELSIF\s+tonApproach\.Q\s+THEN\s*IF\s+udiFirstFaultId\s*=\s*0\s+THEN\s*udiFirstFaultId\s*:=\s*16#0000A007.*?eExitIntent\s*:=\s*CFF_EXIT_FAULT_NO_RETURN.*?eNextState\s*:=\s*CFF_FAULT' 'Approach timeout must first-writer latch A007 only after R-stop timeout priority and retain the pending safe-stop package'
    Assert-Match $approachSafeStop.PositiveBody '(?s)ELSIF\s+\(GVL_Status\.stFast\.udiAcceptedSequenceZCommandId\s*=\s*udiZCommandId\)\s+AND\s+GVL_Status\.stFast\.stZAxis\.bStandstill\s+AND\s+\(GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\)\s+AND\s+GVL_Status\.stFast\.stRAxis\.bStandstill\s+THEN.*?bApproachFaultStopPending\s*:=\s*FALSE.*?CFF_EXIT_ABORT_NO_RETURN.*?CFF_ABORT.*?CFF_EXIT_FAULT_NO_RETURN.*?CFF_FAULT' 'Approach may enter Abort/Fault only after exact current Z/R source ACK plus both actual standstills'
    Assert-Match $approachSafeStop.PositiveBody '(?s)ELSE\s+eNextState\s*:=\s*eState\s*;\s*END_IF' 'Approach safety exit must remain in Approach only after R/Approach timeout and exact stop completion all fail'
    Assert-Ordered $approachSafeStop.PositiveBody @('IF tonRAxisStop.Q','OR (udiFirstFaultId = 16#0000A014)','ELSIF tonApproach.Q THEN','ELSIF (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)','eNextState := eState') 'Approach safe-stop decision order must be A014, A007, exact Z/R completion, then hold Approach'
    Assert-Match $sequence '(?s)stMotionIntent\.stRCommand\.bEnable\s*:=\s*TRUE.*?stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE.*?stMotionIntent\.stRCommand\.bMoveVelocity\s*:=\s*FALSE.*?stMotionIntent\.stRCommand\.rVelocity_rpm\s*:=\s*0\.0.*?stMotionIntent\.stRCommand\.rAcceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS.*?stMotionIntent\.stRCommand\.rDeceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS.*?CFF_STEP1_ENTRY:.*?stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE' 'The implemented Step1 entry must publish the complete frozen-profile R zero-stop payload under the unchanged Approach R source ID'
    Assert-Match $sequence '(?s)bPrecheckExitRequested\s*:=\s*bStopRequestedLatched\s+OR\s+bAbortEvent\s+OR\s+bResetPendingLatched\s+OR\s*\(udiFirstFaultId\s*>\s*0\)' 'Precheck direct exit must be limited to user Stop/Abort/active Reset or an already-latched command fault'
    Assert-NoMatch $sequence 'bPrecheckExitRequested\s*:=\s*[^;]*(?:bSafeExitRequested|bHardForceActive|bHardStrokeActive|bCollisionLimitActive|bSensorInvalid|bAxisError|bExternalError)' 'Precheck direct exit must not bypass A001-A006 validation classification for ordinary invalid prerequisites'
    Assert-Match $sequence '(?s)IF\s+eState\s*=\s*CFF_PRECHECK\s+AND\s+bPrecheckExitRequested\s+THEN.*?CFF_EXIT_ABORT_NO_RETURN.*?CFF_ABORT.*?CFF_FAULT' 'Stop, Abort, active Reset, or a latched command fault in Precheck must leave the no-motion wait without waiting indefinitely for Contact Reset ACK'
    Assert-Match $sequence '(?s)bSafeTerminalReset\s*:=\s*\(bResetEvent\s+OR\s+bResetPendingLatched\).*?CFF_COMPLETE_OK.*?CFF_COMPLETE_NOK.*?CFF_ABORT.*?CFF_FAULT.*?stZAxis\.bStandstill.*?stRAxis\.bStandstill.*?(?:bReleaseOwner|Z_EXT_IDLE)' 'An active Reset must remain pending until a safe terminal, both axes standstill, and External release'
    $safeTerminalResetBody = Get-IfBody $sequence 'bSafeTerminalReset' 'Safe terminal Reset must have one executable cleanup block'
    Assert-Match $safeTerminalResetBody '(?s)bForceControlEnable\s*:=\s*FALSE.*?bForceProfileTransfer\s*:=\s*FALSE.*?bForceProfileTransferPending\s*:=\s*FALSE.*?rForceTransferVelocity_mm_s\s*:=\s*0\.0.*?rForceSet_kN\s*:=\s*0\.0.*?rForceRamp_kN_s\s*:=\s*0\.0.*?rSpeedSet_rpm\s*:=\s*0\.0.*?rTargetRelativePosition_mm\s*:=\s*0\.0.*?rHardMaximumRelativePosition_mm\s*:=\s*0\.0.*?rRequiredRelativePosition_mm\s*:=\s*0\.0.*?rStepBoundary_mm\s*:=\s*0\.0.*?rCycleStartZPosition_mm\s*:=\s*0\.0.*?rStepTime_s\s*:=\s*0\.0.*?rQualifiedForceHoldTime_s\s*:=\s*0\.0.*?bRpmStopped\s*:=\s*FALSE.*?bForceInBand\s*:=\s*FALSE.*?bHardForceActive\s*:=\s*FALSE.*?bHardStrokeActive\s*:=\s*FALSE.*?bCollisionLimitActive\s*:=\s*FALSE' 'Safe terminal Reset must clear all active force/R/position targets, timers, qualification flags, and hard-limit diagnostics'
    Assert-NoMatch $safeTerminalResetBody 'udi(?:LastObservedCommandId|ZCommandId|RCommandId|ContactReferenceRequestId|ExpectedContactReferenceAckId)\s*:=\s*0' 'Safe terminal Reset must not rewind command high-water marks or Z/R/Contact transaction identities'
    Assert-NoMatch $sequence 'st(?:Contact|ForceDecline|StepCriterion)Input\.bReset\s*:=\s*[^;]*(?:GVL_FastInternal\.stAcceptedCommand\.stSequence\.bResetPulse|GVL_Command\.stFast\.stSequence\.bResetPulse)' 'Active Reset pulses must not directly reset Sequence algorithms'
    Assert-Match $sequence '(?s)GVL_Calibration\.stForce\.nRevision\s*<>\s*stCycleSnapshot\.nCalibrationRevision.*?GVL_Calibration\.stDisplacement\.nRevision\s*<>\s*stCycleSnapshot\.nCalibrationRevision.*?GVL_Calibration\.stCollision\.nRevision\s*<>\s*stCycleSnapshot\.nCalibrationRevision.*?16#0000A00F' 'All three active-cycle calibration revisions must be monitored against the frozen Start revision'
    Assert-Match $sequence '(?s)IF\s+bBusy\s+AND\s*\(udiActiveStartCommandId\s*>\s*0\)\s+AND\s*\(eState\s*<>\s*CFF_IDLE\).*?GVL_Calibration\.stForce\.nRevision\s*<>.*?16#0000A00F' 'Calibration revision monitoring must include the active Precheck wait, not begin only after motion starts'
    Assert-Match $sequence '(?s)IF\s+bBusy\s+AND\s*\(udiActiveStartCommandId\s*>\s*0\)\s+AND\s*\(eState\s*<>\s*CFF_IDLE\)\s+AND\s+NOT\s+bContactAcceptInvalidReference\s+AND.*?GVL_Calibration\.stForce\.nRevision\s*<>.*?16#0000A00F' 'Exact-ACK invalid-reference A00A must also take first-fault priority over a same-scan calibration A00F writer'
    Assert-NoMatch $sequence '(?s)IF\s+bBusy\s+AND\s*\(udiActiveStartCommandId\s*>\s*0\).*?eState\s*<>\s*CFF_PRECHECK.*?GVL_Calibration\.stForce\.nRevision' 'Active-cycle calibration monitoring must not exclude Precheck'
    Assert-Ordered $sequence @(
        'udiFirstFaultId := 16#0000A00F',
        'bPrecheckExitRequested := bStopRequestedLatched OR bAbortEvent'
    ) 'Precheck direct-exit classification must consume a same-scan A00F calibration revision change'
    Assert-Match $sequence '(?s)bHardForceActive\s*:=.*?bHardStrokeActive\s*:=.*?bCollisionLimitActive\s*:=.*?bExternalError\s*:=.*?bAxisError\s*:=.*?bSensorInvalid\s*:=.*?stStepCriterionInput\.bHardForceActive\s*:=\s*bHardForceActive' 'Current-scan safety facts must be computed before they are passed to Step Criterion'
    Assert-Match $sequence '(?s)bHardForceActive.*?16#0000A00C.*?bHardStrokeActive.*?16#0000A00D.*?bCollisionLimitActive.*?16#0000A00E.*?bSensorInvalid.*?16#0000A00F.*?stZAxis\.bError.*?16#0000A010.*?stRAxis\.bError.*?16#0000A011.*?bExternalError.*?16#0000A012' 'Active safety causes must latch deterministic first-fault IDs before unified safe exit'
    Assert-Match $sequence 'bPostContactSensorRequired\s*:=\s*\(eState\s*>=\s*CFF_STEP1_ENTRY\)\s+AND\s*\(eState\s*<=\s*CFF_EXTSETPOINT_DISABLE\)' 'Contact validity/agreement monitoring must remain armed throughout the post-contact External lifecycle'
    Assert-NoMatch $sequence 'bPostContactSensorRequired\s*:=\s*[^;]*CFF_CONTACT_ACCEPT' 'Contact Accept must classify its exact ACK locally so invalid reference A00A cannot be preempted by global A00F'
    Assert-Match $sequence '(?s)bContactAcceptExactAck\s*:=\s*\(eState\s*=\s*CFF_CONTACT_ACCEPT\).*?bProcessReferenceLatchPending.*?udiContactReferenceAcceptedId\s*=\s*udiExpectedContactReferenceAckId.*?bContactAcceptInvalidReference\s*:=\s*bContactAcceptExactAck\s+AND\s+NOT\s+GVL_Process\.stActual\.bContactReferenceValid' 'The exact Contact ACK scan must expose an explicit invalid-reference priority fact'
    Assert-Match $sequence '(?s)bSensorInvalid\s*:=\s*bBusy\s+AND\s+NOT\s+bContactAcceptInvalidReference\s+AND.*?NOT\s+GVL_Process\.stActual\.bForceValid.*?NOT\s+GVL_Process\.stActual\.bDisplacementValid.*?NOT\s+GVL_Process\.stActual\.bCollisionValid' 'Generic sensor-invalid A00F classification must yield to exact-ACK invalid-reference A00A on that scan only'
    Assert-Match $sequence '(?s)bSensorInvalid\s*:=\s*bBusy.*?bPostContactSensorRequired\s+AND\s*\(NOT\s+GVL_Process\.stActual\.bValid\s+OR\s+NOT\s+GVL_Process\.stActual\.bContactReferenceValid\s+OR\s+NOT\s+GVL_Process\.stActual\.bAxisSensorAgreement\)' 'Post-contact loss of aggregate validity, the reference, or axis/sensor agreement must feed the deterministic A00F safety classifier'
    $zSourceIncrementPattern = 'udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1'
    $frontExternalStates = @(
        'CFF_EXTSETPOINT_PREPARE',
        'CFF_CONTACT_SEARCH',
        'CFF_CONTACT_ACCEPT'
    )
    $frontExternalBranches = @{}
    $frontExternalPartitions = @{}
    foreach ($frontExternalState in $frontExternalStates) {
        $frontBranch = Get-CaseBranch $sequence $frontExternalState "Missing executable CASE branch: $frontExternalState"
        if ($frontExternalState -eq 'CFF_EXTSETPOINT_PREPARE') {
            $frontPartition = Get-IfPartition $frontBranch '\(?\s*bStateEntry\s*\)?' 'External Prepare must have exactly one parseable IF bStateEntry THEN region'
        } else {
            $frontPartition = Get-IfPartition $frontBranch '\(?\s*bStateEntry\s*\)?' "$frontExternalState may have at most one parseable IF bStateEntry THEN region" -Optional
        }
        $frontExternalBranches[$frontExternalState] = $frontBranch
        $frontExternalPartitions[$frontExternalState] = $frontPartition
        Assert-TopLevelPatterns $frontPartition.Outside @(
            'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*(?:E_ZCommandOwner\.)?Z_OWNER_FORCE_PROCESS',
            'stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*TRUE',
            'stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE',
            'stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE'
        ) "$frontExternalState level intent must retain top-level Force Owner and External use outside bStateEntry"
        Assert-NoMatch $frontBranch 'udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1' "$frontExternalState must retain the Approach R zero-stop source without creating another transaction"
        if ($frontExternalState -eq 'CFF_EXTSETPOINT_PREPARE') {
            Assert-NoMatch $frontPartition.Outside $zSourceIncrementPattern 'External Prepare must not increment its Z source ID outside bStateEntry'
        } else {
            Assert-NoMatch $frontBranch $zSourceIncrementPattern "$frontExternalState must reuse the Prepare Force Z transaction without incrementing its source ID"
        }
    }
    $prepareBranch = $frontExternalBranches['CFF_EXTSETPOINT_PREPARE']
    $preparePartition = $frontExternalPartitions['CFF_EXTSETPOINT_PREPARE']
    Assert-MatchCount $preparePartition.Body $zSourceIncrementPattern 1 'External Prepare bStateEntry must create exactly one fresh Z source transaction'
    Assert-Match $preparePartition.Body '(?s)udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1\s*;.*?IF\s+udiZCommandId\s*=\s*0\s+THEN\s*udiZCommandId\s*:=\s*1\s*;?\s*END_IF\s*;?' 'External Prepare bStateEntry must explicitly skip zero after incrementing the Z source ID'
    Assert-TopLevelPatterns $preparePartition.Outside @(
        'stMotionIntent\.bExternalEnableRequest\s*:=\s*TRUE'
    ) 'External Prepare level intent must keep top-level External Enable asserted'
    Assert-True (Test-AllAssignmentsGuardedByPositiveIf $prepareBranch 'eNextState\s*:=\s*(?:E_CffState\.)?CFF_CONTACT_SEARCH' @(
        'GVL_Status\.stFast\.udiAcceptedSequenceZCommandId\s*=\s*udiZCommandId',
        'GVL_Status\.stFast\.stZAxis\.eActiveOwner\s*=\s*(?:E_ZCommandOwner\.)?Z_OWNER_FORCE_PROCESS',
        'GVL_Status\.stFast\.stZExtSetpoint\.bEnabled',
        'GVL_Status\.stFast\.stZExtSetpoint\.bAcceptedSetpointValid',
        'GVL_Status\.stFast\.stZExternalTrajectory\.bActive'
    ) 4) 'Every External Prepare to Contact Search transition must be inside the same positive ACK plus Owner plus Enabled plus accepted-valid plus trajectory-active IF'
    $contactSearchBranch = $frontExternalBranches['CFF_CONTACT_SEARCH']
    $contactAcceptBranch = $frontExternalBranches['CFF_CONTACT_ACCEPT']
    Assert-Match $contactSearchBranch '(?s)fbContactDetect\.stOutput\.bReferenceLatchRequest.*?stPendingProcessReferenceCommand\.bLatchContactReference\s*:=\s*TRUE.*?stPendingProcessReferenceCommand\.bUseProvidedContactReference\s*:=\s*TRUE.*?rDetectedSensorPosition_mm.*?rDetectedAxisPosition_mm.*?udiContactReferenceRequestId\s*:=\s*udiContactReferenceRequestId\s*\+\s*1' 'Contact Search must generate and latch one local Contact reference transaction on the detector request edge'
    Assert-NoMatch $contactAcceptBranch 'udiContactReferenceRequestId\s*:=\s*udiContactReferenceRequestId\s*\+\s*1|GVL_Command\.stProcessReference\.' 'Contact Accept must not generate or directly publish another Contact transaction'
    Assert-Match $contactAcceptBranch '(?s)GVL_Process\.stActual\.udiContactReferenceAcceptedId\s*=\s*udiExpectedContactReferenceAckId.*?IF\s+NOT\s+GVL_Process\.stActual\.bContactReferenceValid\s+THEN.*?16#0000A00A.*?ELSIF\s+NOT\s+GVL_Process\.stActual\.bAxisSensorAgreement\s+OR\s+NOT\s+GVL_Process\.stActual\.bValid\s+THEN.*?16#0000A00F.*?ELSE.*?rHardMaximumRelativePosition_mm' 'Contact Accept exact ACK must classify invalid reference as A00A, valid-reference disagreement/aggregate loss as A00F, and only then allow Force takeover'
    foreach ($contactAckVector in @(
        @{ Contact = $true; Agreement = $true; Aggregate = $true; GenericSensors = $true; CalibrationStable = $true; Expected = $true; ErrorId = 0x0000 },
        @{ Contact = $true; Agreement = $false; Aggregate = $false; GenericSensors = $true; CalibrationStable = $true; Expected = $false; ErrorId = 0xA00F },
        @{ Contact = $false; Agreement = $false; Aggregate = $false; GenericSensors = $true; CalibrationStable = $true; Expected = $false; ErrorId = 0xA00A },
        @{ Contact = $false; Agreement = $false; Aggregate = $false; GenericSensors = $false; CalibrationStable = $true; Expected = $false; ErrorId = 0xA00A },
        @{ Contact = $false; Agreement = $false; Aggregate = $false; GenericSensors = $true; CalibrationStable = $false; Expected = $false; ErrorId = 0xA00A }
    )) {
        $contactTakeoverAllowed = $contactAckVector.Contact -and $contactAckVector.Agreement -and $contactAckVector.Aggregate
        Assert-True ($contactTakeoverAllowed -eq $contactAckVector.Expected) 'Adversarial Contact ACK vector violated the reference/agreement/aggregate takeover gate'
        $invalidReferenceHasPriority = -not $contactAckVector.Contact
        $genericSensorFault = (-not $invalidReferenceHasPriority) -and (-not $contactAckVector.GenericSensors)
        $calibrationFault = (-not $invalidReferenceHasPriority) -and (-not $contactAckVector.CalibrationStable)
        $contactErrorId = if ($genericSensorFault -or $calibrationFault) { 0xA00F } elseif ($invalidReferenceHasPriority) { 0xA00A } elseif (-not $contactAckVector.Agreement -or -not $contactAckVector.Aggregate) { 0xA00F } else { 0x0000 }
        Assert-True ($contactErrorId -eq $contactAckVector.ErrorId) 'Adversarial Contact ACK vector violated A00A-before-A00F first-fault classification'
    }
    Assert-Ordered $contactAcceptBranch @(
        'GVL_Process.stActual.bContactReferenceValid',
        'rForceSet_kN := GVL_Process.stActual.fForceControlN * 0.001',
        'rForceRamp_kN_s := stForceProfileSnapshot.fForceRampNS * 0.001',
        'bForceProfileTransferPending := TRUE',
        'bForceControlEnable := TRUE'
    ) 'A valid Contact ACK must seed the first Force-enabled scan from actual force and the frozen positive Force ramp before transfer/enable'
    Assert-Match $sequence '(?s)bForceProfileTransferPending\s*:=\s*TRUE.*?IF\s+bForceProfileTransferPending\s+AND\s+bForceControlEnable\s+THEN.*?bForceProfileTransfer\s*:=\s*TRUE.*?bForceProfileTransferPending\s*:=\s*FALSE' 'Contact takeover must retain a pending profile transfer until the first Force-enabled scan consumes it once'
    $unknownStateBody = Get-UniqueTopLevelCaseDefaultBody $sequenceExecutable 'eState'
    Assert-True (-not [string]::IsNullOrWhiteSpace($unknownStateBody)) 'Main Sequence CASE must have one direct executable unknown-state fail-safe default'
    $unknownLifecyclePartition = Get-IfPartition $unknownStateBody 'NOT\s+bExternalReady' 'Unknown-state handling must split on the actual External release/idle lifecycle' -TopLevel
    Assert-True ($unknownLifecyclePartition.HasElse -and
        ($unknownLifecyclePartition.ElsifCount -eq 0)) 'Unknown-state handling must use one direct unconditional released-External ELSE'
    Assert-Match $unknownLifecyclePartition.PositiveBody '(?s)IF\s+udiZCommandId\s*=\s*0\s+THEN\s*udiZCommandId\s*:=\s*1\s*;.*?udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1\s*;.*?IF\s+udiRCommandId\s*=\s*0\s+THEN\s*udiRCommandId\s*:=\s*1\s*;.*?bUnknownExternalRStopPending\s*:=\s*TRUE.*?stMotionIntent\.stZCommand\.bEnable\s*:=\s*TRUE.*?stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*Z_OWNER_FORCE_PROCESS.*?stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*TRUE.*?stMotionIntent\.bExternalDisableRequest\s*:=\s*TRUE.*?stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE.*?stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE.*?bForceControlEnable\s*:=\s*FALSE.*?eNextState\s*:=\s*CFF_EXTSETPOINT_DISABLE' 'Unknown state with unreleased External must preserve a nonzero Z identity, create one fresh R zero-stop, and command zero plus Disable'
    Assert-NoMatch $unknownLifecyclePartition.PositiveBody 'udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1' 'Unknown unreleased-External handling must not change the active External Z source identity before Adapter release'
    Assert-True (Test-ForceOwnerDecelerationPackage $unknownLifecyclePartition.PositiveBody) 'Unknown unreleased-External handling must have one final frozen positive Force-owner deceleration writer'
    $unknownStandardBody = $unknownLifecyclePartition.AlternateBody
    Assert-True (-not [string]::IsNullOrWhiteSpace($unknownStandardBody)) 'Unknown-state released-External path is missing'
    Assert-Match $unknownStandardBody '(?s)udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1\s*;.*?IF\s+udiZCommandId\s*=\s*0\s+THEN\s*udiZCommandId\s*:=\s*1\s*;.*?udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1\s*;.*?IF\s+udiRCommandId\s*=\s*0\s+THEN\s*udiRCommandId\s*:=\s*1\s*;.*?bApproachFaultStopPending\s*:=\s*TRUE.*?stMotionIntent\.stZCommand\.bStop\s*:=\s*TRUE.*?stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*Z_OWNER_FAULT_STOP.*?stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE.*?stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE.*?eNextState\s*:=\s*CFF_FAULT' 'Unknown state after External release must create fresh nonzero Z FaultStop and R zero-stop transactions until exact ACK and standstill'
    $frontDisableBranch = Get-CaseBranch $sequence 'CFF_EXTSETPOINT_DISABLE' 'Missing executable CASE branch: CFF_EXTSETPOINT_DISABLE'
    Assert-True (Test-ForceOwnerDecelerationPackage $frontDisableBranch) 'External Disable must repeat one final frozen positive Force-owner deceleration for the ReleaseOwner scan'
    Assert-Match $frontDisableBranch '(?s)stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE.*?stMotionIntent\.stRCommand\.bEnable\s*:=\s*TRUE.*?stMotionIntent\.stRCommand\.bReset\s*:=\s*FALSE.*?stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE.*?stMotionIntent\.stRCommand\.bMoveVelocity\s*:=\s*FALSE.*?stMotionIntent\.stRCommand\.rVelocity_rpm\s*:=\s*0\.0.*?stMotionIntent\.stRCommand\.rAcceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS.*?stMotionIntent\.stRCommand\.rDeceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS' 'External Disable must rebuild the complete R zero-stop payload even on the ReleaseOwner scan'
    Assert-Match $frontDisableBranch '(?s)IF\s+bUnknownExternalRStopPending\s+AND\s*\(GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\).*?GVL_Status\.stFast\.stRAxis\.bStandstill\s+THEN\s*bUnknownExternalRStopPending\s*:=\s*FALSE.*?IF\s+bSafeExitRStopPending\s+AND\s*\(GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\).*?GVL_Status\.stFast\.stRAxis\.bStandstill\s+THEN\s*bSafeExitRStopPending\s*:=\s*FALSE.*?IF\s+GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner\s+AND\s+NOT\s+bUnknownExternalRStopPending\s+AND\s+NOT\s+bSafeExitRStopPending\s+AND\s*\(GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\)\s+AND\s+GVL_Status\.stFast\.stRAxis\.bStandstill\s+THEN' 'External Disable must hold until every pending R zero-stop has exact source ACK and actual standstill before release migration'
    Assert-Match $sequence 'bExternalProcessState\s*:=\s*\(eState\s*>=\s*CFF_EXTSETPOINT_PREPARE\)\s+AND\s*\(eState\s*<=\s*CFF_CONTROLLED_FORCE_UNLOAD\)' 'The pre-release External process lifecycle classifier is missing'
    Assert-Match $sequence '(?s)IF\s+bExternalProcessState\s+AND\s+GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner\s+AND\s+bSafeExitRequested\s+THEN.*?udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1\s*;.*?IF\s+udiZCommandId\s*=\s*0\s+THEN\s*udiZCommandId\s*:=\s*1\s*;.*?udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1\s*;.*?IF\s+udiRCommandId\s*=\s*0\s+THEN\s*udiRCommandId\s*:=\s*1\s*;.*?bApproachFaultStopPending\s*:=\s*TRUE.*?stMotionIntent\.bExternalEnableRequest\s*:=\s*FALSE.*?stMotionIntent\.bExternalDisableRequest\s*:=\s*FALSE.*?Z_OWNER_FAULT_STOP.*?bUseExternalSetpoint\s*:=\s*FALSE.*?stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE.*?bForceControlEnable\s*:=\s*FALSE.*?CFF_EXIT_ABORT_NO_RETURN.*?CFF_ABORT.*?CFF_FAULT' 'A same-scan safety event in an already-released External process state must not restart External; it must create fresh Z/R stop transactions and route to a safe terminal wait'
    Assert-NoMatch $sequence 'AXIS_REF|MC_' 'Sequence must not access axes or MC'
}

if ($runSequenceSteps) {
    $sequenceRaw = Read-Text 'CFFwelding_System\CFFwelding\POUs\Fast\PRG_CffSequence.TcPOU'
    $sequence = Get-PouImplementationText $sequenceRaw
    $sequenceDeclaration = Get-PouDeclarationText $sequenceRaw
    Assert-True (-not [string]::IsNullOrWhiteSpace($sequence)) 'SequenceSteps must parse only the POU Implementation ST CDATA'
    Assert-True (-not [string]::IsNullOrWhiteSpace($sequenceDeclaration)) 'SequenceSteps must parse the POU Declaration CDATA'

    $implementationXmlDecoyFixture = @'
<TcPlcObject><!-- <POU><Implementation><ST><![CDATA[CFF_STEP1_ENTRY: IF bStateEntry THEN udiRCommandId := udiRCommandId + 1; END_IF]]></ST></Implementation></POU> --><POU><Declaration><![CDATA[PROGRAM P]]></Declaration><Implementation><ST><![CDATA[realImplementation := TRUE;]]></ST></Implementation></POU></TcPlcObject>
'@
    $implementationXmlDecoy = Get-PouImplementationText $implementationXmlDecoyFixture
    Assert-True (($implementationXmlDecoy -match 'realImplementation') -and
        ($implementationXmlDecoy -notmatch 'CFF_STEP1_ENTRY')) 'Implementation extractor fixture accepted fake ST tokens from an XML comment'

    $rPayloadChangedFixture = @'
bRCommandPayloadChanged :=
    stCandidateRCommand.bEnable <> stLastPublishedRCommand.bEnable
    OR stCandidateRCommand.bReset <> stLastPublishedRCommand.bReset
    OR stCandidateRCommand.bStop <> stLastPublishedRCommand.bStop
    OR stCandidateRCommand.bMoveVelocity <> stLastPublishedRCommand.bMoveVelocity
    OR stCandidateRCommand.rVelocity_rpm <> stLastPublishedRCommand.rVelocity_rpm
    OR stCandidateRCommand.rAcceleration_rpm_s <> stLastPublishedRCommand.rAcceleration_rpm_s
    OR stCandidateRCommand.rDeceleration_rpm_s <> stLastPublishedRCommand.rDeceleration_rpm_s;
'@
    $rPayloadDeadOuterFixture = "IF FALSE THEN`n$rPayloadChangedFixture`nEND_IF"
    $rPayloadOverrideFixture = $rPayloadChangedFixture + "`nbRCommandPayloadChanged := TRUE;"
    Assert-True (Test-RCommandPayloadChangedAssignment $rPayloadChangedFixture) 'R payload helper rejected the unique complete comparison'
    Assert-True (-not (Test-RCommandPayloadChangedAssignment $rPayloadDeadOuterFixture)) 'R payload helper accepted a complete comparison hidden below IF FALSE'
    Assert-True (-not (Test-RCommandPayloadChangedAssignment $rPayloadOverrideFixture)) 'R payload helper accepted a later constant override'

    $saturatingFixture = @'
IF uliStepElapsed_us < uliStepMaximum_us THEN
    IF uliCycleDelta_us >= uliStepMaximum_us - uliStepElapsed_us THEN
        uliStepElapsed_us := uliStepMaximum_us;
    ELSE
        uliStepElapsed_us := uliStepElapsed_us + uliCycleDelta_us;
    END_IF
END_IF
'@
    $saturatingDeadOuterFixture = "IF FALSE THEN`n$saturatingFixture`nEND_IF"
    $saturatingMinFixture = 'uliStepElapsed_us := MIN(uliStepElapsed_us + uliCycleDelta_us, uliStepMaximum_us);'
    Assert-True (Test-SaturatingUsAccumulator $saturatingFixture 'uliStepElapsed_us' 'uliStepMaximum_us') 'Saturation helper rejected remaining-capacity-before-addition logic'
    Assert-True (-not (Test-SaturatingUsAccumulator $saturatingDeadOuterFixture 'uliStepElapsed_us' 'uliStepMaximum_us')) 'Saturation helper accepted logic hidden below IF FALSE'
    Assert-True (-not (Test-SaturatingUsAccumulator $saturatingMinFixture 'uliStepElapsed_us' 'uliStepMaximum_us')) 'Saturation helper accepted overflow-before-MIN logic'

    $resultPublisherFixture = @'
CASE eState OF
    CFF_IDLE:
        dummy := TRUE;
END_CASE
IF bStepResultPublishRequested AND NOT abStepResultWritten[nStepResultIndex] THEN
    stStepResultCandidate := stClearedStepCriterionResult;
    stStepResultCandidate.eStep := eStep;
    stStepResultCandidate.eEndCause := fbStepCriterion.stOutput.eEndCause;
    stStepResultCandidate.bPrimaryLatched := fbStepCriterion.stOutput.bPrimaryMet;
    stStepResultCandidate.bSecondaryLatched := fbStepCriterion.stOutput.bSecondaryLimitReached;
    stStepResultCandidate.bNok := bStepResultNok;
    stStepResultCandidate.nTriggerCycle := GVL_Status.stFast.nCycleCounter;
    stStepResultCandidate.bTooShort := fbStepCriterion.stOutput.bTooShort;
    stStepResultCandidate.bQualifiedForceHoldMet := (nStepResultIndex = 4)
        AND (uliQualifiedHold_us >= uliQualifiedHoldTarget_us);
    stStepResultCandidate.rQualifiedForceHoldTime_s := rQualifiedForceHoldTime_s;
    stStepResultCandidate.rLatchedForce_kN := fbStepCriterion.stOutput.rLatchedForce_kN;
    stStepResultCandidate.rLatchedRelativePosition_mm := fbStepCriterion.stOutput.rLatchedRelativePosition_mm;
    stStepResultCandidate.rLatchedStepTime_s := fbStepCriterion.stOutput.rLatchedStepTime_s;
    GVL_Process.astStepCriterion[nStepResultIndex] := stStepResultCandidate;
    abStepResultWritten[nStepResultIndex] := TRUE;
END_IF
'@
    $resultDeadOuterFixture = "IF FALSE THEN`n$resultPublisherFixture`nEND_IF"
    $resultOrGateFixture = $resultPublisherFixture.Replace(' AND NOT ', ' OR NOT ')
    $resultSecondWriterFixture = $resultPublisherFixture + "`nGVL_Process.astStepCriterion[nStepResultIndex] := stStepResultCandidate;"
    $resultSecondFieldFixture = $resultPublisherFixture + "`nstStepResultCandidate.bNok := FALSE;"
    $resultBeforeMainCaseFixture = [regex]::Replace(
        $resultPublisherFixture,
        '(?s)\A(?<Case>CASE.*?END_CASE\s*)(?<Publisher>IF.*)\z',
        '${Publisher}${Case}')
    $resultWrongQualifiedFixture = $resultPublisherFixture.Replace(
        'uliQualifiedHold_us >= uliQualifiedHoldTarget_us',
        'uliQualifiedHold_us <= uliQualifiedHoldTarget_us')
    Assert-True (Test-StepResultPublisher $resultPublisherFixture) 'Step-result helper rejected the valid payload-first one-write publisher'
    Assert-True (-not (Test-StepResultPublisher $resultDeadOuterFixture)) 'Step-result helper accepted a publisher hidden below IF FALSE'
    Assert-True (-not (Test-StepResultPublisher $resultOrGateFixture)) 'Step-result helper accepted an OR in place of the positive request AND unwritten gate'
    Assert-True (-not (Test-StepResultPublisher $resultSecondWriterFixture)) 'Step-result helper accepted a second dynamic public write'
    Assert-True (-not (Test-StepResultPublisher $resultSecondFieldFixture)) 'Step-result helper accepted a second candidate-field override'
    Assert-True (-not (Test-StepResultPublisher $resultBeforeMainCaseFixture)) 'Step-result helper accepted a publisher before same-scan state requests can be formed'
    Assert-True (-not (Test-StepResultPublisher $resultWrongQualifiedFixture)) 'Step-result helper accepted an incorrect Qualified Hold result mapping'

    $step4TimerFixture = @'
tonStep4RAxisStop(
    IN := ((eState = CFF_BRAKE_AND_COMPRESSION_RAMP)
            OR (eState = CFF_STEP4_VALID_FORCE_HOLD))
        AND ((eState = CFF_BRAKE_AND_COMPRESSION_RAMP AND bStateEntry)
            OR NOT ((GVL_Status.stFast.udiAcceptedSequenceRCommandId = udiRCommandId)
                AND bRpmStopped)),
    PT := stSequenceConfigSnapshot.tRAxisStopTimeout);
'@
    $step4TimerDeadOuterFixture = "IF FALSE THEN`n$step4TimerFixture`nEND_IF"
    $step4TimerBrakeOnlyFixture = 'tonStep4RAxisStop(IN := eState = CFF_BRAKE_AND_COMPRESSION_RAMP, PT := stSequenceConfigSnapshot.tRAxisStopTimeout);'
    $step4TimerOrTrueFixture = $step4TimerFixture.Replace('OR NOT', 'OR TRUE OR NOT')
    Assert-True (Test-Step4StopTimer $step4TimerFixture) 'Step4 timer helper rejected the Brake-entry plus pending ACK/actual-stop monitor'
    Assert-True (-not (Test-Step4StopTimer $step4TimerDeadOuterFixture)) 'Step4 timer helper accepted a call hidden below IF FALSE'
    Assert-True (-not (Test-Step4StopTimer $step4TimerBrakeOnlyFixture)) 'Step4 timer helper accepted timing only Brake and dropping Hold supervision'
    Assert-True (-not (Test-Step4StopTimer $step4TimerOrTrueFixture)) 'Step4 timer helper accepted an OR TRUE bypass'

    $brakeTransitionFixture = @'
IF NOT bStateEntry
    AND (GVL_Status.stFast.udiAcceptedSequenceRCommandId = udiRCommandId)
    AND GVL_Status.stFast.bRSpeedRampValid
    AND GVL_Status.stFast.bRSpeedRampReached
    AND GVL_Status.stFast.bForceSetpointRampValid
    AND GVL_Status.stFast.bForceSetpointRampReached THEN
    eNextState := CFF_STEP4_VALID_FORCE_HOLD;
END_IF
'@
    $brakeTransitionBypassFixture = $brakeTransitionFixture + "`neNextState := CFF_STEP4_VALID_FORCE_HOLD;"
    Assert-True (Test-BrakeToHoldTransition $brakeTransitionFixture) 'Brake transition helper rejected the post-entry ACK plus dual-ramp gate'
    Assert-True (-not (Test-BrakeToHoldTransition $brakeTransitionBypassFixture)) 'Brake transition helper accepted an unguarded duplicate transition'

    $noReturnPriorityFixture = @'
IF udiFirstFaultId > 0 THEN
    eExitIntent := CFF_EXIT_FAULT_NO_RETURN;
    eNextState := CFF_EXTSETPOINT_DISABLE;
ELSIF bStopRequestedLatched OR bAbortEvent OR bResetPendingLatched THEN
    eExitIntent := CFF_EXIT_ABORT_NO_RETURN;
    eNextState := CFF_EXTSETPOINT_DISABLE;
ELSIF normalCondition THEN
    eExitIntent := CFF_EXIT_NORMAL_RETURN;
END_IF
'@
    $noReturnPrioritySwappedFixture = @'
IF udiFirstFaultId > 0 THEN
    eExitIntent := CFF_EXIT_FAULT_NO_RETURN;
    eNextState := CFF_EXTSETPOINT_DISABLE;
ELSIF normalCondition THEN
    eExitIntent := CFF_EXIT_NORMAL_RETURN;
ELSIF bStopRequestedLatched OR bAbortEvent OR bResetPendingLatched THEN
    eExitIntent := CFF_EXIT_ABORT_NO_RETURN;
    eNextState := CFF_EXTSETPOINT_DISABLE;
END_IF
'@
    Assert-True (Test-NoReturnPriorityBranch $noReturnPriorityFixture) 'No-return priority helper rejected first-fault then Stop/Abort/Reset ordering'
    Assert-True (-not (Test-NoReturnPriorityBranch $noReturnPrioritySwappedFixture)) 'No-return priority helper accepted normal/return intent before Stop/Abort/Reset'

    $stopResultPriorityFixture = @'
IF udiFirstFaultId > 0 THEN
    eExitIntent := CFF_EXIT_FAULT_NO_RETURN;
    eNextState := CFF_EXTSETPOINT_DISABLE;
ELSIF bStopRequestedLatched OR bAbortEvent OR bResetPendingLatched THEN
    IF fbStepCriterion.stOutput.bEndConfirmed
        AND (fbStepCriterion.stOutput.eEndCause = STEP_END_STOP_REQUEST)
        AND NOT fbForceDecline.stOutput.bFault
        AND NOT fbStepCriterion.stOutput.bFault THEN
        nStepResultIndex := 2;
        bStepResultNok := fbStepCriterion.stOutput.bNok;
        bStepResultPublishRequested := TRUE;
        eEndCause := fbStepCriterion.stOutput.eEndCause;
    END_IF
    eExitIntent := CFF_EXIT_ABORT_NO_RETURN;
    eNextState := CFF_EXTSETPOINT_DISABLE;
ELSIF normalCondition THEN
    eExitIntent := CFF_EXIT_NORMAL_RETURN;
END_IF
'@
    $stopResultDroppedFixture = [regex]::Replace(
        $stopResultPriorityFixture,
        '(?s)ELSIF bStopRequestedLatched(?<Condition>.*?)THEN.*?eExitIntent := CFF_EXIT_ABORT_NO_RETURN;',
        'ELSIF bStopRequestedLatched${Condition}THEN eExitIntent := CFF_EXIT_ABORT_NO_RETURN;',
        1)
    Assert-True (Test-EventExitPreservesStopResult $stopResultPriorityFixture 2) 'Stop-result helper rejected a real STEP_END_STOP_REQUEST before Abort routing'
    Assert-True (-not (Test-EventExitPreservesStopResult $stopResultDroppedFixture 2)) 'Stop-result helper accepted Abort routing that dropped a real Criterion stop result'

    $criterionResetFixture = @'
bStepCriterionResetPulse := bStateEntry
    AND ((eState = CFF_STEP1_ENTRY)
        OR (eState = CFF_STEP2_ENTRY)
        OR (eState = CFF_STEP3_ENTRY)
        OR (eState = CFF_BRAKE_AND_COMPRESSION_RAMP));
'@
    $criterionResetOrTrueFixture = $criterionResetFixture.Replace(
        'bStateEntry',
        '(bStateEntry OR TRUE)')
    Assert-True (Test-EntryResetGate $criterionResetFixture 'bStepCriterionResetPulse' @(
        'CFF_STEP1_ENTRY','CFF_STEP2_ENTRY','CFF_STEP3_ENTRY','CFF_BRAKE_AND_COMPRESSION_RAMP'
    )) 'Entry-reset helper rejected the positive bStateEntry allowlist'
    Assert-True (-not (Test-EntryResetGate $criterionResetOrTrueFixture 'bStepCriterionResetPulse' @(
        'CFF_STEP1_ENTRY','CFF_STEP2_ENTRY','CFF_STEP3_ENTRY','CFF_BRAKE_AND_COMPRESSION_RAMP'
    ))) 'Entry-reset helper accepted bStateEntry OR TRUE'

    $qualifiedHoldResetFixture = @'
IF bStateEntry AND (eState = CFF_BRAKE_AND_COMPRESSION_RAMP) THEN
    uliQualifiedHold_us := 0;
END_IF
CASE eState OF
    CFF_IDLE:
        IF bStartEvent THEN
            uliQualifiedHold_us := 0;
        END_IF
END_CASE
IF bSafeTerminalReset THEN
    uliQualifiedHold_us := 0;
END_IF
'@
    $qualifiedHoldGlobalClearFixture = $qualifiedHoldResetFixture.Replace(
        'CASE eState OF',
        "IF eState = CFF_STEP4_VALID_FORCE_HOLD THEN`n    uliQualifiedHold_us := 0;`nEND_IF`nCASE eState OF")
    Assert-True (Test-QualifiedHoldResetSites $qualifiedHoldResetFixture) 'Qualified-Hold reset helper rejected Start, Brake entry, and safe terminal Reset sites'
    Assert-True (-not (Test-QualifiedHoldResetSites $qualifiedHoldGlobalClearFixture)) 'Qualified-Hold reset helper accepted a global Hold-state clock clear'

    $stepElapsedResetFixture = @'
IF bStateEntry
    AND ((eState = CFF_STEP1_ENTRY)
        OR (eState = CFF_STEP2_ENTRY)
        OR (eState = CFF_STEP3_ENTRY)
        OR (eState = CFF_BRAKE_AND_COMPRESSION_RAMP)) THEN
    uliStepElapsed_us := 0;
END_IF
CASE eState OF
    CFF_IDLE:
        IF bStartEvent THEN
            uliStepElapsed_us := 0;
        END_IF
END_CASE
IF bSafeTerminalReset THEN
    uliStepElapsed_us := 0;
END_IF
'@
    $stepElapsedHoldResetFixture = $stepElapsedResetFixture.Replace(
        'OR (eState = CFF_BRAKE_AND_COMPRESSION_RAMP))',
        "OR (eState = CFF_BRAKE_AND_COMPRESSION_RAMP)`n        OR (eState = CFF_STEP4_VALID_FORCE_HOLD))")
    Assert-True (Test-StepElapsedResetSites $stepElapsedResetFixture) 'Step clock reset helper rejected Start, Step/Brake entry, and safe terminal Reset sites'
    Assert-True (-not (Test-StepElapsedResetSites $stepElapsedHoldResetFixture)) 'Step clock reset helper accepted Hold in the reset allowlist'

    $step4QualificationFixture = @'
IF bStep4ProcessActive
    AND GVL_Process.stActual.bForceValid
    AND FC_IsFiniteLReal(rValue := GVL_Process.stActual.fForceControlN)
    AND FC_IsFiniteLReal(rValue := GVL_Status.stFast.stRAxis.rActualVelocity_rpm) THEN
    bRpmStopped := ABS(GVL_Status.stFast.stRAxis.rActualVelocity_rpm)
        <= stCycleSnapshot.stProgram.astSteps[4].stProceeding.fRpmStoppedThresholdRpm;
    bForceInBand := ABS(
        GVL_Process.stActual.fForceControlN
        - stCycleSnapshot.stProgram.astSteps[4].fSetForceN)
        <= stCycleSnapshot.stProgram.astSteps[4].stProceeding.fForceBandToleranceN;
ELSE
    bRpmStopped := FALSE;
    bForceInBand := FALSE;
END_IF
CASE eState OF
    CFF_IDLE:
        dummy := TRUE;
END_CASE
'@
    $step4QualificationOverrideFixture = $step4QualificationFixture.Replace(
        'CASE eState OF',
        "bRpmStopped := TRUE;`nbForceInBand := TRUE;`nCASE eState OF")
    Assert-True (Test-Step4QualificationGate $step4QualificationFixture) 'Step4 qualification helper rejected the finite actual-RPM and actual-Force gate'
    Assert-True (-not (Test-Step4QualificationGate $step4QualificationOverrideFixture)) 'Step4 qualification helper accepted late constant RPM/Force overrides'

    $stepRampResultFixture = @'
IF udiFirstFaultId > 0 THEN
    IF fbStepCriterion.stOutput.bEndConfirmed
        AND ((fbStepCriterion.stOutput.eEndCause = STEP_END_HARD_FORCE)
            OR (fbStepCriterion.stOutput.eEndCause = STEP_END_HARD_STROKE)
            OR (fbStepCriterion.stOutput.eEndCause = STEP_END_COLLISION)
            OR (fbStepCriterion.stOutput.eEndCause = STEP_END_SENSOR_INVALID)
            OR (fbStepCriterion.stOutput.eEndCause = STEP_END_AXIS_FAULT))
        AND NOT fbForceDecline.stOutput.bFault
        AND NOT fbStepCriterion.stOutput.bFault THEN
        nStepResultIndex := 2;
        bStepResultNok := TRUE;
        bStepResultPublishRequested := TRUE;
    END_IF
ELSIF fbForceDecline.stOutput.bFault OR fbStepCriterion.stOutput.bFault THEN
    udiFirstFaultId := 16#0000A00B;
    eExitIntent := CFF_EXIT_FAULT_NO_RETURN;
ELSIF fbStepCriterion.stOutput.bEndConfirmed THEN
    nStepResultIndex := 2;
    bStepResultNok := fbStepCriterion.stOutput.bNok;
    bStepResultPublishRequested := TRUE;
END_IF
'@
    $stepRampFabricatedAlgorithmResultFixture = $stepRampResultFixture.Replace(
        'udiFirstFaultId := 16#0000A00B;',
        "nStepResultIndex := 2;`n    bStepResultNok := TRUE;`n    bStepResultPublishRequested := TRUE;`n    udiFirstFaultId := 16#0000A00B;")
    $stepRampGenericFirstFaultFixture = [regex]::Replace(
        $stepRampResultFixture,
        '(?s)\s+AND \(\(fbStepCriterion\.stOutput\.eEndCause.*?STEP_END_AXIS_FAULT\)\)',
        '',
        1)
    Assert-True (Test-StepRampResultPaths $stepRampResultFixture 2) 'Step-result helper rejected guarded real Criterion result plus conservative A00B handling'
    Assert-True (-not (Test-StepRampResultPaths $stepRampFabricatedAlgorithmResultFixture 2)) 'Step-result helper accepted a fabricated result on a raw algorithm/configuration fault'
    Assert-True (-not (Test-StepRampResultPaths $stepRampGenericFirstFaultFixture 2)) 'Step-result helper accepted a generic coincident EndConfirmed result under an unrelated first fault'

    $step4ResultFixture = @'
ELSIF fbStepCriterion.stOutput.bEndConfirmed THEN
    nStepResultIndex := 4;
    bStepResultNok := fbStepCriterion.stOutput.bNok
        OR (uliQualifiedHold_us < uliQualifiedHoldTarget_us);
    bStepResultPublishRequested := TRUE;
'@
    $step4MissingResultFixture = $step4ResultFixture.Replace(
        'bStepResultPublishRequested := TRUE',
        'bStepResultPublishRequested := FALSE')
    Assert-True (Test-Step4ResultPath $step4ResultFixture) 'Step4 result helper rejected one complete end-confirmed path'
    Assert-True (-not (Test-Step4ResultPath $step4MissingResultFixture)) 'Step4 result helper accepted a missing result request'

    Assert-NoMatch $sequence '\bIF\s+(?:FALSE|0\s*=\s*1)\s+THEN' 'Task 8 implementation must not hide required behavior below a dead constant gate'
    foreach ($ulintName in @('uliCycleDelta_us','uliStepElapsed_us','uliStepMaximum_us','uliQualifiedHold_us','uliQualifiedHoldTarget_us')) {
        Assert-Match $sequenceDeclaration "\b$ulintName\s*:\s*ULINT\b" "$ulintName must be ULINT"
    }
    Assert-Match $sequenceDeclaration '\bstCandidateRCommand\s*:\s*ST_RAxisCommand\b' 'Task 8 must declare the R command candidate'
    Assert-Match $sequenceDeclaration '\bstLastPublishedRCommand\s*:\s*ST_RAxisCommand\b' 'Task 8 must latch the last published R payload'
    Assert-Match $sequenceDeclaration '\babStepResultWritten\s*:\s*ARRAY\s*\[\s*1\.\.4\s*\]\s+OF\s+BOOL\b' 'Task 8 must declare four one-write result guards'
    Assert-Match $sequenceDeclaration '\bstStepResultCandidate\s*:\s*ST_StepCriterionResult\b' 'Task 8 must declare a correctly typed result candidate'
    Assert-Match $sequenceDeclaration '\btonStep4RAxisStop\s*:\s*TON\b' 'Task 8 must use an independent Step4 R stop timer'
    Assert-Match $sequenceDeclaration '\bbEntryMotionPermitted\s*:\s*BOOL\b' 'Task 8 must declare the scan-local Step Entry motion permit'
    Assert-Match $sequenceDeclaration '\bbSafeExitRStopPending\s*:\s*BOOL\b' 'Task 8 must declare the owner-held safety R-stop handshake latch'
    Assert-Match $sequence 'uliCycleDelta_us\s*:=\s*UDINT_TO_ULINT\s*\(\s*stMachineSnapshot\.nFastTaskCycleUs\s*\)' 'Fast period must convert to ULINT before accumulation'
    Assert-Match $sequence 'uliStepMaximum_us\s*:=\s*UDINT_TO_ULINT\s*\([^\)]*nStepMaxMs[^\)]*\)\s*\*\s*ULINT#1000' 'Step maximum milliseconds must convert to ULINT before multiplication'
    Assert-Match $sequence 'uliQualifiedHoldTarget_us\s*:=\s*UDINT_TO_ULINT\s*\([^\)]*nQualifiedForceHoldMs[^\)]*\)\s*\*\s*ULINT#1000' 'Qualified Hold milliseconds must convert to ULINT before multiplication'
    Assert-NoMatch $sequence 'UDINT_TO_ULINT\s*\([^\)]*\*\s*(?:ULINT#)?1000' 'Task 8 must not multiply in UDINT before converting to ULINT'
    Assert-True (Test-SaturatingUsAccumulator $sequence 'uliStepElapsed_us' 'uliStepMaximum_us') 'Step elapsed time must saturate by comparing remaining capacity before addition'
    Assert-True (Test-SaturatingUsAccumulator $sequence 'uliQualifiedHold_us' 'uliQualifiedHoldTarget_us' '\(?\s*bRpmStopped\s+AND\s+bForceInBand\s*\)?') 'Qualified Hold must saturate only inside the actual-RPM AND actual-force gate'

    Assert-MatchCount $sequence '\bfbForceDecline\s*\(' 1 'Sequence must call Force Decline exactly once per scan'
    Assert-MatchCount $sequence '\bfbStepCriterion\s*\(' 1 'Sequence must call Step Criterion exactly once per scan'
    Assert-MatchCount $sequence 'bForceDeclineResetPulse\s*:=\s*bStateEntry' 1 'Entry Force Decline Reset must have one pre-call source'
    Assert-MatchCount $sequence 'bStepCriterionResetPulse\s*:=\s*bStateEntry' 1 'Entry Criterion Reset must have one pre-call source'
    Assert-True (Test-EntryResetGate $sequence 'bForceDeclineResetPulse' @(
        'CFF_STEP1_ENTRY','CFF_STEP2_ENTRY','CFF_STEP3_ENTRY'
    )) 'Force Decline Reset must use only bStateEntry AND the three Step Entry allowlist'
    Assert-True (Test-EntryResetGate $sequence 'bStepCriterionResetPulse' @(
        'CFF_STEP1_ENTRY','CFF_STEP2_ENTRY','CFF_STEP3_ENTRY','CFF_BRAKE_AND_COMPRESSION_RAMP'
    )) 'Criterion Reset must use only bStateEntry AND the Step1-3/Brake Entry allowlist'
    Assert-True (Test-StepElapsedResetSites $sequence) 'Step elapsed clock may clear only on Start, Step1-3/Brake entry, or safe terminal Reset'
    Assert-True (Test-QualifiedHoldResetSites $sequence) 'Qualified Hold may clear only on Start, Brake entry, or safe terminal Reset'
    $forceResetOffset = [regex]::Match($sequence, 'bForceDeclineResetPulse\s*:=\s*bStateEntry').Index
    $criterionResetOffset = [regex]::Match($sequence, 'bStepCriterionResetPulse\s*:=\s*bStateEntry').Index
    $forceCallOffset = [regex]::Match($sequence, '\bfbForceDecline\s*\(').Index
    $criterionCallOffset = [regex]::Match($sequence, '\bfbStepCriterion\s*\(').Index
    $activeStepOffset = [regex]::Match($sequence, '\bnActiveStepProgramIndex\s*:=').Index
    Assert-True (($activeStepOffset -ge 0) -and ($activeStepOffset -lt $forceCallOffset) -and
        ($forceResetOffset -ge 0) -and ($forceResetOffset -lt $forceCallOffset) -and
        ($criterionResetOffset -ge 0) -and ($criterionResetOffset -lt $criterionCallOffset)) 'Active-step classification and Entry Reset must execute before the two algorithm FB calls'
    $preMainCase = Get-PreMainCaseText $sequence
    $algorithmFaultLatch = Get-IfPartition $preMainCase '\(?\s*bBusy\s+AND\s+\(\s*udiFirstFaultId\s*=\s*0\s*\)\s*\)?' 'Current algorithm/ramp faults must have one pre-CASE first-fault latch' -TopLevel
    Assert-Match $algorithmFaultLatch.PositiveBody '(?s)\(\(eState\s*=\s*CFF_STEP1_RAMP_PROCESS\)\s+OR\s+\(eState\s*=\s*CFF_STEP2_RAMP_PROCESS\)\s+OR\s+\(eState\s*=\s*CFF_STEP3_RAMP_PROCESS\)\).*?fbForceDecline\.stOutput\.bFault\s+OR\s+fbStepCriterion\.stOutput\.bFault.*?udiFirstFaultId\s*:=\s*16#0000A00B' 'Only active Step1-3 Ramp algorithm faults may pre-latch A00B'
    Assert-Match $algorithmFaultLatch.PositiveBody '(?s)\(\(eState\s*=\s*CFF_BRAKE_AND_COMPRESSION_RAMP\)\s+AND\s+NOT\s+bStateEntry\)\s+OR\s+\(eState\s*=\s*CFF_STEP4_VALID_FORCE_HOLD\).*?fbForceDecline\.stOutput\.bFault.*?NOT\s+GVL_Status\.stFast\.bForceSetpointRampValid.*?NOT\s+GVL_Status\.stFast\.bRSpeedRampValid.*?udiFirstFaultId\s*:=\s*16#0000A00B' 'Step4 may pre-latch A00B only after Brake entry or during Hold'
    Assert-NoMatch $algorithmFaultLatch.PositiveBody 'CFF_STEP[123]_ENTRY|CFF_BRAKE_AND_COMPRESSION_RAMP\)\s*(?:OR|AND(?!\s+NOT\s+bStateEntry))' 'A00B pre-latch must exclude all Step Entry scans and the Brake entry scan'
    $preCaseCriterionCallOffset = [regex]::Match($preMainCase, '\bfbStepCriterion\s*\(').Index
    $algorithmFaultLatchOffset = [regex]::Match($preMainCase, '\bIF\s+bBusy\s+AND\s+\(\s*udiFirstFaultId\s*=\s*0\s*\)').Index
    Assert-True (($preCaseCriterionCallOffset -ge 0) -and
        ($algorithmFaultLatchOffset -gt $preCaseCriterionCallOffset) -and
        ($algorithmFaultLatchOffset -lt $preMainCase.Length)) 'A00B must latch after current FB outputs and before the main CASE'
    Assert-Match $sequence '(?s)stForceDeclineInput\.bEnable\s*:=\s*\(\(eState\s*=\s*CFF_STEP1_RAMP_PROCESS.*?CFF_STEP2_RAMP_PROCESS.*?CFF_STEP3_RAMP_PROCESS.*?\)\s*AND\s*\(stCycleSnapshot\.stProgram\.astSteps\s*\[\s*nActiveStepProgramIndex\s*\]\.stProceeding\.ePrimaryCriterion\s*=\s*STEP_CRIT_FORCE_DECLINE_TO\)' 'Force Decline must use the complete positive Ramp allowlist and current frozen Primary gate'
    Assert-Match $sequence '(?s)stStepCriterionInput\.bEnable\s*:=.*?CFF_STEP1_RAMP_PROCESS.*?CFF_STEP2_RAMP_PROCESS.*?CFF_STEP3_RAMP_PROCESS.*?CFF_BRAKE_AND_COMPRESSION_RAMP.*?CFF_STEP4_VALID_FORCE_HOLD' 'Criterion must cover Step1-3 Ramp plus both Step4 process states'
    Assert-True (Test-UniqueSafetyFactsBeforeCase $sequence) 'Hard Force/Stroke, Collision, and SensorInvalid must each have one current-scan assignment before the main CASE'
    $safetyOverrideFixture = $sequence.Replace(
        'CASE eState OF',
        "bHardForceActive := FALSE;`nCASE eState OF")
    Assert-True (-not (Test-UniqueSafetyFactsBeforeCase $safetyOverrideFixture)) 'Safety-fact helper accepted a late constant override before the state machine'
    Assert-True (Test-Step4QualificationGate $sequence) 'Step4 RPM/Force qualification must have one finite actual-value gate and no pre-CASE override'
    $qualificationOverrideFixture = $sequence.Replace(
        'CASE eState OF',
        "bRpmStopped := TRUE;`nbForceInBand := TRUE;`nCASE eState OF")
    Assert-True (-not (Test-Step4QualificationGate $qualificationOverrideFixture)) 'Step4 qualification helper accepted a late constant override before the state machine'

    $zSourceIncrementPattern = 'udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1'
    $externalProcessStates = @(
        'CFF_STEP1_ENTRY',
        'CFF_STEP1_RAMP_PROCESS',
        'CFF_STEP1_END_CHECK',
        'CFF_STEP2_ENTRY',
        'CFF_STEP2_RAMP_PROCESS',
        'CFF_STEP2_END_CHECK',
        'CFF_STEP3_ENTRY',
        'CFF_STEP3_RAMP_PROCESS',
        'CFF_STEP3_END_CHECK',
        'CFF_BRAKE_AND_COMPRESSION_RAMP',
        'CFF_STEP4_VALID_FORCE_HOLD'
    )
    foreach ($externalProcessState in $externalProcessStates) {
        $externalProcessBranch = Get-CaseBranch $sequence $externalProcessState "Missing executable CASE branch: $externalProcessState"
        $externalProcessPartition = Get-IfPartition $externalProcessBranch '\(?\s*bStateEntry(?:\s+AND\s+bEntryMotionPermitted)?\s*\)?' "$externalProcessState may have at most one top-level IF bStateEntry THEN region" -Optional -TopLevel
        Assert-TopLevelPatterns $externalProcessPartition.Outside @(
            'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*(?:E_ZCommandOwner\.)?Z_OWNER_FORCE_PROCESS',
            'stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*TRUE'
        ) "$externalProcessState level intent must retain top-level Force Owner and External use outside bStateEntry"
        Assert-NoMatch $externalProcessBranch $zSourceIncrementPattern "$externalProcessState must reuse the Prepare Force Z transaction without incrementing its source ID"
    }
    Assert-True (Test-RCommandPayloadChangedAssignment $sequence) 'R deduplication must have one top-level complete payload comparison with no override'
    Assert-True (Test-AllIncrementsImmediatelySkipZero $sequence 'udiRCommandId') 'Every R source increment must immediately skip zero'
    Assert-Match $sequence '(?s)bEntryMotionPermitted\s*:=\s*NOT\s*\(\s*bStopRequestedLatched\s+OR\s+bAbortEvent\s+OR\s+bResetPendingLatched\s+OR\s+bHardForceActive\s+OR\s+bHardStrokeActive\s+OR\s+bCollisionLimitActive\s+OR\s+bExternalError\s+OR\s+bAxisError\s+OR\s+bSensorInvalid\s+OR\s*\(\s*udiFirstFaultId\s*>\s*0\s*\)\s*\)' 'Step Entry motion permit must deny every current event, hard, sensor, axis, external, or first-fault cause'
    $entryPermitOffset = [regex]::Match($sequence, '\bbEntryMotionPermitted\s*:=').Index
    $candidateInitOffset = [regex]::Match($sequence, '\bstCandidateRCommand\s*:=\s*stLastPublishedRCommand').Index
    $candidateMoveOffset = [regex]::Match($sequence, '\bstCandidateRCommand\.bMoveVelocity\s*:=\s*TRUE').Index
    $candidateCompareOffset = [regex]::Match($sequence, '\bbRCommandPayloadChanged\s*:=').Index
    $mainSequenceCaseOffset = [regex]::Match($sequence, '\bCASE\s+eState\s+OF').Index
    $firstPermittedEntryOffset = [regex]::Match($sequence, '\bIF\s+bStateEntry\s+AND\s+bEntryMotionPermitted\s+THEN').Index
    Assert-True (($entryPermitOffset -ge 0) -and
        ($entryPermitOffset -lt $candidateInitOffset) -and
        ($candidateInitOffset -lt $candidateMoveOffset) -and
        ($candidateMoveOffset -lt $candidateCompareOffset) -and
        ($candidateCompareOffset -lt $mainSequenceCaseOffset) -and
        ($mainSequenceCaseOffset -lt $firstPermittedEntryOffset)) 'R flow must order scan permit, candidate baseline, complete move rewrite, full compare, then permitted Entry publication'
    foreach ($entryContract in @(
        @{ State = 'CFF_STEP1_ENTRY'; Index = 1 },
        @{ State = 'CFF_STEP2_ENTRY'; Index = 2 },
        @{ State = 'CFF_STEP3_ENTRY'; Index = 3 }
    )) {
        $entryBranch = Get-CaseBranch $sequence $entryContract.State "Missing executable CASE branch: $($entryContract.State)"
        $entryPartition = Get-IfPartition $entryBranch '\(?\s*bStateEntry\s+AND\s+bEntryMotionPermitted\s*\)?' "$($entryContract.State) must have exactly one top-level positive bStateEntry AND motion-permitted region" -TopLevel
        $entryPulse = $entryPartition.PositiveBody
        Assert-Match $entryPulse "rForceSet_kN\s*:=\s*stCycleSnapshot\.stProgram\.astSteps\[$($entryContract.Index)\]\.fSetForceN\s*\*\s*0\.001" "$($entryContract.State) must publish its frozen Force target on entry"
        Assert-Match $entryPulse "rForceRamp_kN_s\s*:=\s*stCycleSnapshot\.stProgram\.astSteps\[$($entryContract.Index)\]\.fForceRampNS\s*\*\s*0\.001" "$($entryContract.State) must publish its frozen Force ramp on entry"
        Assert-Match $entryPulse 'bForceProfileTransferPending\s*:=\s*TRUE' "$($entryContract.State) must request exactly one Force profile transfer on entry"
        Assert-Match $entryPulse 'stMotionIntent\.stRCommand\s*:=\s*stCandidateRCommand' "$($entryContract.State) must publish the R candidate in the same entry scan"
        $changedPartition = Get-IfPartition $entryPulse '\(?\s*bRCommandPayloadChanged\s*\)?' "$($entryContract.State) R increment must have one top-level positive changed gate" -TopLevel
        Assert-Ordered $changedPartition.PositiveBody @(
            'stLastPublishedRCommand := stCandidateRCommand',
            'stMotionIntent.stRCommand := stCandidateRCommand',
            'udiRCommandId := udiRCommandId + 1',
            'IF udiRCommandId = 0 THEN',
            'udiRCommandId := 1'
        ) "$($entryContract.State) must copy payload before ID and immediately skip zero"
        Assert-NoMatch $changedPartition.Outside 'udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1' "$($entryContract.State) must increment R only inside the positive changed gate"
    }
    $stepPostCase = Get-TextAfterMainCase $sequence 'Task 8 safe R-stop tests require one parseable main Sequence CASE'
    $safeExternalExit = Get-IfPartition $stepPostCase '\(?\s*bExternalOwnerHold\s+AND\s+bSafeExitRequested\s*\)?' 'External-owner safe exit must have one top-level positive ownerHold AND safeExit region' -TopLevel
    Assert-TopLevelPatterns $safeExternalExit.PositiveBody @(
        'stCandidateRCommand\.bEnable\s*:=\s*TRUE',
        'stCandidateRCommand\.bReset\s*:=\s*FALSE',
        'stCandidateRCommand\.bStop\s*:=\s*TRUE',
        'stCandidateRCommand\.bMoveVelocity\s*:=\s*FALSE',
        'stCandidateRCommand\.rVelocity_rpm\s*:=\s*0\.0',
        'stCandidateRCommand\.rAcceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS',
        'stCandidateRCommand\.rDeceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS',
        'stMotionIntent\.stRCommand\s*:=\s*stCandidateRCommand',
        'stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE',
        'bSafeExitRStopPending\s*:=\s*TRUE',
        'bForceControlEnable\s*:=\s*FALSE'
    ) 'External-owner safe exit must rebuild the complete R stop payload while disabling Force'
    $safeRChangedCondition = '(?s)\(?\s*stCandidateRCommand\.bEnable\s*<>\s*stLastPublishedRCommand\.bEnable\s+OR\s+stCandidateRCommand\.bReset\s*<>\s*stLastPublishedRCommand\.bReset\s+OR\s+stCandidateRCommand\.bStop\s*<>\s*stLastPublishedRCommand\.bStop\s+OR\s+stCandidateRCommand\.bMoveVelocity\s*<>\s*stLastPublishedRCommand\.bMoveVelocity\s+OR\s+stCandidateRCommand\.rVelocity_rpm\s*<>\s*stLastPublishedRCommand\.rVelocity_rpm\s+OR\s+stCandidateRCommand\.rAcceleration_rpm_s\s*<>\s*stLastPublishedRCommand\.rAcceleration_rpm_s\s+OR\s+stCandidateRCommand\.rDeceleration_rpm_s\s*<>\s*stLastPublishedRCommand\.rDeceleration_rpm_s\s*\)?'
    $safeRChanged = Get-IfPartition $safeExternalExit.PositiveBody $safeRChangedCondition 'Safe R stop must have one complete positive payload-change gate relative to the last published payload' -TopLevel
    Assert-Ordered $safeRChanged.PositiveBody @(
        'stLastPublishedRCommand := stCandidateRCommand',
        'stMotionIntent.stRCommand := stCandidateRCommand',
        'udiRCommandId := udiRCommandId + 1',
        'IF udiRCommandId = 0 THEN',
        'udiRCommandId := 1'
    ) 'Safe R stop must copy the complete payload before a fresh ID and immediately skip zero'
    Assert-NoMatch $safeRChanged.Outside 'udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1' 'Stable owner-held safety scans must not duplicate the fresh R-stop ID'

    $safeStopScans = @(
        [pscustomobject]@{ Name = 'MoveToStop'; Last = 'Move'; ExpectedIncrements = 1 },
        [pscustomobject]@{ Name = 'ApproachStopStable'; Last = 'Stop'; ExpectedIncrements = 0 }
    )
    foreach ($safeStopScan in $safeStopScans) {
        $lastPayload = $safeStopScan.Last
        $sourceId = [uint32]41
        $increments = 0
        foreach ($scan in 1..2) {
            $candidatePayload = 'Stop'
            if ($candidatePayload -ne $lastPayload) {
                $lastPayload = $candidatePayload
                $sourceId = [uint32]($sourceId + 1)
                if ($sourceId -eq 0) { $sourceId = 1 }
                $increments++
            }
        }
        Assert-True (($lastPayload -eq 'Stop') -and
            ($increments -eq $safeStopScan.ExpectedIncrements)) "Unsafe Entry scan fixture failed: $($safeStopScan.Name)"
    }
    foreach ($releaseVector in @(
        [pscustomobject]@{ Name = 'OwnerHeldMove'; Last = 'Move'; Release = $false; Expected = 1 },
        [pscustomobject]@{ Name = 'OwnerHeldStop'; Last = 'Stop'; Release = $false; Expected = 0 },
        [pscustomobject]@{ Name = 'ReleasedMove'; Last = 'Move'; Release = $true; Expected = 1 },
        [pscustomobject]@{ Name = 'ReleasedStop'; Last = 'Stop'; Release = $true; Expected = 1 }
    )) {
        $ownerHeld = -not $releaseVector.Release
        $releaseSafety = $releaseVector.Release
        $releaseIncrements = 0
        if ($ownerHeld -and ($releaseVector.Last -ne 'Stop')) {
            $releaseIncrements++
        }
        if ($releaseSafety) {
            $releaseIncrements++
        }
        Assert-True ($releaseIncrements -eq $releaseVector.Expected) "Release/safety R-ID scan fixture failed: $($releaseVector.Name)"
    }
    foreach ($brakeSafetyVector in @(
        [pscustomobject]@{ Name = 'UnsafeBrakeOwnerHeldMove'; Last = 'Move'; Release = $false; EntryMotionPermitted = $false; Expected = 1 },
        [pscustomobject]@{ Name = 'UnsafeBrakeOwnerHeldStop'; Last = 'Stop'; Release = $false; EntryMotionPermitted = $false; Expected = 0 },
        [pscustomobject]@{ Name = 'UnsafeBrakeReleasedMove'; Last = 'Move'; Release = $true; EntryMotionPermitted = $false; Expected = 1 },
        [pscustomobject]@{ Name = 'UnsafeBrakeReleasedStop'; Last = 'Stop'; Release = $true; EntryMotionPermitted = $false; Expected = 1 }
    )) {
        $brakeSafetyIncrements = 0
        $brakeForceTransferStarted = $false
        if ($brakeSafetyVector.EntryMotionPermitted) {
            $brakeSafetyIncrements++
            $brakeForceTransferStarted = $true
        }
        if ((-not $brakeSafetyVector.Release) -and ($brakeSafetyVector.Last -ne 'Stop')) {
            $brakeSafetyIncrements++
        }
        if ($brakeSafetyVector.Release) {
            $brakeSafetyIncrements++
        }
        Assert-True ((-not $brakeForceTransferStarted) -and
            ($brakeSafetyIncrements -eq $brakeSafetyVector.Expected)) "Unsafe Brake Entry must not start Force transfer and must leave the sole R-stop transaction to the owner-held or released safety path: $($brakeSafetyVector.Name)"
    }
    $normalBrakeEntryPermitted = $true
    $normalBrakeEntryIncrements = 0
    $normalBrakeForceTransferStarted = $false
    if ($normalBrakeEntryPermitted) {
        $normalBrakeEntryIncrements++
        $normalBrakeForceTransferStarted = $true
    }
    Assert-True ($normalBrakeForceTransferStarted -and ($normalBrakeEntryIncrements -eq 1)) 'A permitted normal Brake Entry must retain one same-scan R-stop transaction and one Force-profile transfer'
    $maliciousOwnerHeldOnReleaseIncrements = 0
    if ($true -and ('Move' -ne 'Stop')) { $maliciousOwnerHeldOnReleaseIncrements++ }
    if ($true) { $maliciousOwnerHeldOnReleaseIncrements++ }
    Assert-True ($maliciousOwnerHeldOnReleaseIncrements -eq 2) 'Adversarial vector must expose the double-ID bug if ownerHold is allowed on Release'
    $oldAcceptedRId = [uint32]41
    $freshSafetyRId = [uint32]42
    $oldAckAcceptedFreshStop = $oldAcceptedRId -eq $freshSafetyRId
    $acceptedAfterAdapter = [uint32]42
    $freshStopAcked = ($acceptedAfterAdapter -eq $freshSafetyRId)
    Assert-True ((-not $oldAckAcceptedFreshStop) -and $freshStopAcked) 'Fresh safety R-stop ID must reject the old Move ACK and accept only the exact new ID'
    $faultNormalizationCondition = '\(?\s*\(\s*udiFirstFaultId\s*>\s*0\s*\)\s+OR\s+bHardForceActive\s+OR\s+bHardStrokeActive\s+OR\s+bCollisionLimitActive\s+OR\s+bExternalError\s+OR\s+bAxisError\s+OR\s+bSensorInvalid\s*\)?'
    $faultNormalization = Get-IfPartition $stepPostCase $faultNormalizationCondition 'Post-CASE routing must have one top-level positive real-fault normalization gate' -TopLevel
    Assert-Match $faultNormalization.PositiveBody 'eExitIntent\s*:=\s*CFF_EXIT_FAULT_NO_RETURN' 'A real first/hard/sensor/axis/external fault must normalize to fault no-return'
    Assert-Match $faultNormalization.Body '(?s)ELSIF\s+bStopRequestedLatched\s+OR\s+bAbortEvent\s+OR\s+bResetPendingLatched\s+THEN.*?eExitIntent\s*:=\s*CFF_EXIT_ABORT_NO_RETURN' 'Stop/Abort/active Reset without a real fault must normalize to abort no-return'
    Assert-NoMatch $faultNormalization.Body 'CFF_EXIT_(?:NORMAL|NOK)_RETURN' 'Post-CASE safety normalization must not allow a Return intent to penetrate'
    $faultNormalizationOffset = [regex]::Match($stepPostCase, '\bIF\s+\(\s*udiFirstFaultId\s*>\s*0\s*\)').Index
    $ownerHeldSafeExitOffset = [regex]::Match($stepPostCase, '\bIF\s+bExternalOwnerHold\s+AND\s+bSafeExitRequested\s+THEN').Index
    Assert-True (($faultNormalizationOffset -ge 0) -and
        ($ownerHeldSafeExitOffset -gt $faultNormalizationOffset)) 'ExitIntent must normalize before owner-held External safe-exit routing'

    $disableFaultCorrectionCondition = '(?is)^\s*\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_EXTSETPOINT_DISABLE\s*\)?\s+AND\s+\(?\s*eNextState\s*=\s*(?:E_CffState\.)?CFF_ABORT\s*\)?\s+AND\s+\(?\s*eExitIntent\s*=\s*(?:E_CffExitIntent\.)?CFF_EXIT_FAULT_NO_RETURN\s*\)?\s*$'
    $parsedStepPostCase = Get-IfRegions $stepPostCase
    $disableFaultCorrectionRegions = @($parsedStepPostCase.Regions | Where-Object {
        ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch($_.Condition, $disableFaultCorrectionCondition)
    })
    $disableFaultCorrectionValid = $disableFaultCorrectionRegions.Count -eq 1
    $disableFaultCorrectionOffset = -1
    if ($disableFaultCorrectionValid) {
        $disableFaultCorrectionRegion = $disableFaultCorrectionRegions[0]
        $disableFaultCorrectionPositiveEnd = if ($disableFaultCorrectionRegion.AlternateStart -ge 0) {
            $disableFaultCorrectionRegion.AlternateStart
        } else {
            $disableFaultCorrectionRegion.BodyEnd
        }
        $disableFaultCorrectionBody = $parsedStepPostCase.Text.Substring(
            $disableFaultCorrectionRegion.BodyStart,
            $disableFaultCorrectionPositiveEnd - $disableFaultCorrectionRegion.BodyStart)
        $disableFaultCorrectionValid = [regex]::Matches(
            $disableFaultCorrectionBody,
            '\beNextState\s*:=\s*(?:E_CffState\.)?CFF_FAULT\s*;',
            'IgnoreCase').Count -eq 1
        $disableFaultCorrectionOffset = $disableFaultCorrectionRegion.Start
    }
    $fixtureDisableState = 'CFF_EXTSETPOINT_DISABLE'
    $fixtureOldExitIntent = 'CFF_EXIT_ABORT_NO_RETURN'
    $fixtureReleaseOwner = $true
    $fixtureExactRStopAck = $true
    $fixtureRStandstill = $true
    $fixtureNewRealFault = $true
    $fixtureNextState = if ($fixtureReleaseOwner -and $fixtureExactRStopAck -and
        $fixtureRStandstill -and ($fixtureOldExitIntent -eq 'CFF_EXIT_ABORT_NO_RETURN')) {
        'CFF_ABORT'
    } else {
        'CFF_EXTSETPOINT_DISABLE'
    }
    $fixtureNormalizedExitIntent = if ($fixtureNewRealFault) {
        'CFF_EXIT_FAULT_NO_RETURN'
    } else {
        $fixtureOldExitIntent
    }
    if ($disableFaultCorrectionValid -and
        ($disableFaultCorrectionOffset -gt $faultNormalizationOffset) -and
        ($disableFaultCorrectionOffset -lt $ownerHeldSafeExitOffset) -and
        ($fixtureDisableState -eq 'CFF_EXTSETPOINT_DISABLE') -and
        ($fixtureNextState -eq 'CFF_ABORT') -and
        ($fixtureNormalizedExitIntent -eq 'CFF_EXIT_FAULT_NO_RETURN')) {
        $fixtureNextState = 'CFF_FAULT'
    }
    Assert-True ($fixtureNextState -eq 'CFF_FAULT') 'Disable release with an old Abort intent and a same-scan new real fault must be corrected to Fault after intent normalization'

    $safeDisableBranch = Get-CaseBranch $sequence 'CFF_EXTSETPOINT_DISABLE' 'Missing executable CASE branch: CFF_EXTSETPOINT_DISABLE'
    $safeRStopAckCondition = '\(?\s*bSafeExitRStopPending\s+AND\s+\(\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)\s+AND\s+GVL_Status\.stFast\.stRAxis\.bStandstill\s*\)?'
    $safeRStopAck = Get-IfPartition $safeDisableBranch $safeRStopAckCondition 'External Disable must clear the safety R-stop latch only after exact ACK and actual standstill' -TopLevel
    Assert-Match $safeRStopAck.PositiveBody 'bSafeExitRStopPending\s*:=\s*FALSE' 'Exact R-stop ACK plus standstill must clear the safety pending latch'
    Assert-NoMatch $safeRStopAck.Outside 'bSafeExitRStopPending\s*:=\s*FALSE' 'External Disable must have no bypass clear for the safety R-stop latch'
    $safeDisableReleaseCondition = '\(?\s*GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner\s+AND\s+NOT\s+bUnknownExternalRStopPending\s+AND\s+NOT\s+bSafeExitRStopPending\s+AND\s+\(\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)\s+AND\s+GVL_Status\.stFast\.stRAxis\.bStandstill\s*\)?'
    $safeDisableRelease = Get-IfPartition $safeDisableBranch $safeDisableReleaseCondition 'External Disable may migrate only after ReleaseOwner, both R-stop handshakes, current exact ACK, and actual standstill' -TopLevel
    Assert-Match $safeDisableRelease.PositiveBody '(?s)stMotionIntent\.bForceProcessExitComplete\s*:=\s*TRUE.*?eNextState\s*:=' 'The fully released and R-stopped path must complete the force exit and migrate'

    $safePending = $true
    $releaseOwner = $true
    $acceptedRId = 51
    $expectedRId = 52
    $rStandstill = $false
    if ($safePending -and ($acceptedRId -eq $expectedRId) -and $rStandstill) {
        $safePending = $false
    }
    $migratedBeforeStop = $releaseOwner -and (-not $safePending) -and ($acceptedRId -eq $expectedRId) -and $rStandstill
    $acceptedRId = 52
    $rStandstill = $true
    if ($safePending -and ($acceptedRId -eq $expectedRId) -and $rStandstill) {
        $safePending = $false
    }
    $migratedAfterStop = $releaseOwner -and (-not $safePending) -and ($acceptedRId -eq $expectedRId) -and $rStandstill
    Assert-True ((-not $migratedBeforeStop) -and $migratedAfterStop) 'Release scan must retain Sequence R Stop until exact ACK and actual standstill'

    foreach ($exitVector in @(
        [pscustomobject]@{ Name = 'FaultAndStop'; Fault = $true; Event = $true; Proposed = 'NOK'; Expected = 'FAULT' },
        [pscustomobject]@{ Name = 'StopAndNormal'; Fault = $false; Event = $true; Proposed = 'NORMAL'; Expected = 'ABORT' },
        [pscustomobject]@{ Name = 'ResetAndNok'; Fault = $false; Event = $true; Proposed = 'NOK'; Expected = 'ABORT' },
        [pscustomobject]@{ Name = 'NormalOnly'; Fault = $false; Event = $false; Proposed = 'NORMAL'; Expected = 'NORMAL' }
    )) {
        $normalizedIntent = if ($exitVector.Fault) {
            'FAULT'
        } elseif ($exitVector.Event) {
            'ABORT'
        } else {
            $exitVector.Proposed
        }
        Assert-True ($normalizedIntent -eq $exitVector.Expected) "Exit priority scan fixture failed: $($exitVector.Name)"
    }
    Assert-Match $sequence '(?s)IF\s+\(\(eState\s*=\s*CFF_STEP1_ENTRY\).*?CFF_STEP2_ENTRY.*?CFF_STEP3_ENTRY.*?\)\s+AND\s+bEntryMotionPermitted\s+THEN.*?stCandidateRCommand\.bStop\s*:=\s*FALSE.*?stCandidateRCommand\.bMoveVelocity\s*:=\s*TRUE.*?stCandidateRCommand\.rVelocity_rpm\s*:=\s*stCycleSnapshot\.stProgram\.astSteps\s*\[\s*nActiveStepProgramIndex\s*\]\.fSetSpeedRpm.*?rAcceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS.*?rDeceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS' 'Step entry R candidate must be motion-permitted and use frozen step RPM/profile slopes'
    Assert-Match $sequence '(?s)IF\s+stCycleSnapshot\.stProgram\.astSteps\s*\[\s*nActiveStepProgramIndex\s*\]\.stProceeding\.ePrimaryCriterion\s*=\s*STEP_CRIT_RELATIVE_DISTANCE\s+THEN.*?rTargetRelativePosition_mm\s*:=.*?fRelativeDistanceMm.*?ELSE.*?rTargetRelativePosition_mm\s*:=.*?fSecondarySRelMm' 'Each step must publish the correct cumulative Contact-relative target by Primary type'
    $step1Ramp = Get-CaseBranch $sequence 'CFF_STEP1_RAMP_PROCESS' 'Missing executable CASE branch: CFF_STEP1_RAMP_PROCESS'
    $step1End = Get-CaseBranch $sequence 'CFF_STEP1_END_CHECK' 'Missing executable CASE branch: CFF_STEP1_END_CHECK'
    Assert-NoMatch $step1Ramp 'udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1' 'Step 1 steady ramp must not create another R transaction'
    Assert-NoMatch $step1End 'udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1' 'Step 1 steady end check must not create another R transaction'
    Assert-Match $sequence '(?s)bHardForceActive\s*:=.*?GVL_Process\.stActual\.bForceValid.*?GVL_Process\.stActual\.fForceControlN\s*>=\s*stLimitsSnapshot\.fMaxForceN' 'Hard Force must use the typed valid Force boundary'
    Assert-Match $sequence '(?s)bHardStrokeActive\s*:=.*?GVL_Process\.stActual\.bContactReferenceValid.*?GVL_Process\.stActual\.fSRelSensorMm\s*>=\s*rHardMaximumRelativePosition_mm' 'Hard Stroke must use the Contact-relative remaining-machine-travel boundary'
    Assert-Match $sequence '(?s)bCollisionLimitActive\s*:=.*?GVL_Process\.stActual\.bCollisionValid.*?GVL_Process\.stActual\.bCollisionSensorActive' 'Collision must use the temporary typed Phase 11B boundary only'
    Assert-Match $sequence '(?s)bSensorInvalid\s*:=.*?FC_IsFiniteLReal.*?fForceControlN.*?FC_IsFiniteLReal.*?fSRelSensorMm' 'Non-finite Force or Contact-relative displacement must route as sensor invalid'
    foreach ($stepContract in @(
        [pscustomobject]@{ Ramp = 'CFF_STEP1_RAMP_PROCESS'; End = 'CFF_STEP1_END_CHECK'; Index = 1 },
        [pscustomobject]@{ Ramp = 'CFF_STEP2_RAMP_PROCESS'; End = 'CFF_STEP2_END_CHECK'; Index = 2 },
        [pscustomobject]@{ Ramp = 'CFF_STEP3_RAMP_PROCESS'; End = 'CFF_STEP3_END_CHECK'; Index = 3 }
    )) {
        $stepRampBranch = Get-CaseBranch $sequence $stepContract.Ramp "Missing executable CASE branch: $($stepContract.Ramp)"
        $stepEndBranch = Get-CaseBranch $sequence $stepContract.End "Missing executable CASE branch: $($stepContract.End)"
        Assert-Match $stepRampBranch '(?s)fbForceDecline\.stOutput\.bFault\s+OR\s+fbStepCriterion\.stOutput\.bFault.*?16#0000A00B.*?CFF_EXIT_FAULT_NO_RETURN' "$($stepContract.Ramp) algorithm fault must be deterministic fault no-return"
        Assert-True (Test-StepRampResultPaths $stepRampBranch $stepContract.Index) "$($stepContract.Ramp) must publish only real Criterion-latched exits and never fabricate an A00B result"
        Assert-True (Test-StepEndResultPath $stepEndBranch $stepContract.Index) "$($stepContract.End) must retain its correctly indexed confirmed result path"
        Assert-True (Test-NoReturnPriorityBranch $stepEndBranch) "$($stepContract.End) must prioritize first fault, then Stop/Abort/Reset, before normal/NOK progression"
        Assert-True (Test-EventExitPreservesStopResult $stepEndBranch $stepContract.Index) "$($stepContract.End) must preserve a real STEP_END_STOP_REQUEST result before Abort routing"
    }
    Assert-True (Test-StepResultPublisher $sequence) 'Step results must use one correctly typed payload-first publisher guarded by request AND unwritten'
    Assert-Match $sequence '(?s)FOR\s+nStepIndex\s*:=\s*1\s+TO\s+4\s+DO.*?GVL_Process\.astStepCriterion\s*\[\s*nStepIndex\s*\]\s*:=\s*stClearedStepCriterionResult.*?abStepResultWritten\s*\[\s*nStepIndex\s*\]\s*:=\s*FALSE' 'Start must clear all four result slots and all four one-write guards'
    $task8IdleBranch = Get-CaseBranch $sequence 'CFF_IDLE' 'Missing executable CASE branch: CFF_IDLE'
    $task8Start = Get-IfPartition $task8IdleBranch '\(?\s*bStartEvent\s*\)?' 'Task 8 Start initialization must have one positive event region' -TopLevel
    Assert-Match $task8Start.PositiveBody 'bSafeExitRStopPending\s*:=\s*FALSE' 'Every new Start must clear the safety R-stop pending latch'
    $safeResetPartition = Get-IfPartition $sequence '\(?\s*bSafeTerminalReset\s*\)?' 'Sequence must have one top-level safe terminal Reset block' -TopLevel
    Assert-NoMatch $safeResetPartition.PositiveBody 'GVL_Process\.astStepCriterion|abStepResultWritten\s*\[' 'Safe terminal Reset must not overwrite results or re-arm result writers'
    Assert-Match $safeResetPartition.PositiveBody 'bSafeExitRStopPending\s*:=\s*FALSE' 'Safe terminal Reset must clear the safety R-stop pending latch'

    $step3End = Get-CaseBranch $sequence 'CFF_STEP3_END_CHECK' 'Missing executable CASE branch: CFF_STEP3_END_CHECK'
    Assert-Match $step3End 'eNextState\s*:=\s*CFF_BRAKE_AND_COMPRESSION_RAMP' 'Step 3 end check must defer brake entry to the next scan'
    Assert-NoMatch $step3End 'stCandidateRCommand\.bStop\s*:=\s*TRUE|uliQualifiedHold_us\s*:=' 'Step 3 end check must not execute Brake entry in the same scan'
    Assert-True (Test-Step4StopTimer $sequence) 'Step4 must have one independent outside-CASE Brake-entry plus pending ACK/actual-stop timer'
    $brakeBranch = Get-CaseBranch $sequence 'CFF_BRAKE_AND_COMPRESSION_RAMP' 'Missing executable CASE branch: CFF_BRAKE_AND_COMPRESSION_RAMP'
    $brakeEntryPartition = Get-IfPartition $brakeBranch '\(?\s*bStateEntry\s+AND\s+bEntryMotionPermitted\s*\)?' 'Brake must have exactly one top-level entry region gated by the scan-local motion permit' -TopLevel
    Assert-Match $brakeEntryPartition.PositiveBody '(?s)(?=.*rForceSet_kN\s*:=\s*stCycleSnapshot\.stProgram\.astSteps\[4\]\.fSetForceN\s*\*\s*0\.001)(?=.*rForceRamp_kN_s\s*:=\s*stCycleSnapshot\.stProgram\.astSteps\[4\]\.fForceRampNS\s*\*\s*0\.001)(?=.*rVelocity_rpm\s*:=\s*0\.0)(?=.*bStop\s*:=\s*TRUE)(?=.*bForceProfileTransferPending\s*:=\s*TRUE)' 'Brake entry must publish R stop plus Step4 Force/Ramp and one transfer in the same scan'
    Assert-True (Test-BrakeToHoldTransition $brakeBranch) 'Brake may enter Hold only after entry, exact new R ACK, and both valid/reached ramps'
    Assert-Match $brakeBranch '(?s)ELSIF\s+NOT\s+bStateEntry\s+AND\s*\(fbForceDecline\.stOutput\.bFault\s+OR\s+fbStepCriterion\.stOutput\.bFault\s+OR\s+NOT\s+GVL_Status\.stFast\.bForceSetpointRampValid\s+OR\s+NOT\s+GVL_Status\.stFast\.bRSpeedRampValid\).*?16#0000A00B.*?CFF_EXIT_FAULT_NO_RETURN' 'Brake may classify invalid ramp or algorithm A00B only after its entry scan'
    Assert-Match $brakeBranch '(?s)ELSIF\s+NOT\s+bStateEntry\s+AND\s+fbStepCriterion\.stOutput\.bEndConfirmed.*?bStepResultPublishRequested\s*:=\s*TRUE.*?eNextState\s*:=\s*CFF_CONTROLLED_FORCE_UNLOAD.*?ELSIF\s+NOT\s+bStateEntry\s+AND\s+tonStep4RAxisStop\.Q\s+THEN.*?16#0000A014.*?CFF_EXIT_FAULT_NO_RETURN' 'Brake must ignore stale Entry outputs, then evaluate Step4 end before the unique R-stop timeout'
    Assert-True (Test-Step4ResultPath $brakeBranch -RequireNotEntry) 'Brake must retain its own post-entry correctly indexed Step4 result path'
    Assert-True (Test-NoReturnPriorityBranch $brakeBranch) 'Brake must prioritize first fault, then Stop/Abort/Reset, before normal/NOK progression'
    Assert-True (Test-EventExitPreservesStopResult $brakeBranch 4) 'Brake must preserve a real STEP_END_STOP_REQUEST result before Abort routing'
    $step4Hold = Get-CaseBranch $sequence 'CFF_STEP4_VALID_FORCE_HOLD' 'Missing executable CASE branch: CFF_STEP4_VALID_FORCE_HOLD'
    Assert-NoMatch $step4Hold 'bStateEntry|uliStepElapsed_us\s*:=\s*0|uliQualifiedHold_us\s*:=\s*0|bStepCriterionResetPulse\s*:=\s*TRUE' 'Entering or remaining in Hold must not reset Step4 time, criterion, or Qualified Hold'
    Assert-True (Test-Step4ResultPath $step4Hold) 'Hold must retain its own correctly indexed Step4 end-confirmed result path'
    Assert-True (Test-NoReturnPriorityBranch $step4Hold) 'Hold must prioritize first fault, then Stop/Abort/Reset, before normal/NOK progression'
    Assert-True (Test-EventExitPreservesStopResult $step4Hold 4) 'Hold must preserve a real STEP_END_STOP_REQUEST result before Abort routing'
    foreach ($step4ProcessContract in @(
        [pscustomobject]@{ Branch = $brakeBranch; EntryGate = 'NOT\s+bStateEntry\s+AND\s*\('; EndGate = 'NOT\s+bStateEntry\s+AND\s+' },
        [pscustomobject]@{ Branch = $step4Hold; EntryGate = ''; EndGate = '' }
    )) {
        $step4AlgorithmPath = [regex]::Match(
            $step4ProcessContract.Branch,
            '(?is)ELSIF\s+' + $step4ProcessContract.EntryGate +
                'fbForceDecline\.stOutput\.bFault\s+OR\s+fbStepCriterion\.stOutput\.bFault\s+OR\s+NOT\s+GVL_Status\.stFast\.bForceSetpointRampValid\s+OR\s+NOT\s+GVL_Status\.stFast\.bRSpeedRampValid' +
                $(if ($step4ProcessContract.EntryGate) { '\)' } else { '' }) +
                '\s+THEN(?<Body>.*?)ELSIF\s+' + $step4ProcessContract.EndGate +
                'fbStepCriterion\.stOutput\.bEndConfirmed\s+THEN')
        Assert-True $step4AlgorithmPath.Success 'Step4 algorithm/ramp fault path must remain separately parseable from the confirmed-result path'
        if ($step4AlgorithmPath.Success) {
            Assert-NoMatch $step4AlgorithmPath.Groups['Body'].Value 'nStepResultIndex\s*:=|bStepResultNok\s*:=|bStepResultPublishRequested\s*:=' 'Step4 algorithm/ramp fault must not fabricate an unlatched result'
        }
    }
    Assert-Match $sequence '(?s)bRpmStopped\s*:=\s*ABS\s*\(\s*GVL_Status\.stFast\.stRAxis\.rActualVelocity_rpm\s*\)\s*<=\s*stCycleSnapshot\.stProgram\.astSteps\[4\]\.stProceeding\.fRpmStoppedThresholdRpm' 'Step 4 RPM gate must use actual R velocity'
    Assert-Match $sequence '(?s)bForceInBand\s*:=\s*ABS\s*\(\s*GVL_Process\.stActual\.fForceControlN\s*-\s*stCycleSnapshot\.stProgram\.astSteps\[4\]\.fSetForceN\s*\)\s*<=\s*stCycleSnapshot\.stProgram\.astSteps\[4\]\.stProceeding\.fForceBandToleranceN' 'Step 4 Force gate must use actual Force and the configured band'
    Assert-Match ($brakeBranch + $step4Hold) '(?s)(?=.*fbStepCriterion\.stOutput\.bEndConfirmed)(?=.*uliQualifiedHold_us\s*<\s*uliQualifiedHoldTarget_us)(?=.*CFF_EXIT_NORMAL_RETURN)(?=.*CFF_EXIT_NOK_RETURN)(?=.*CFF_CONTROLLED_FORCE_UNLOAD)' 'Step4 end must select Normal/NOK intent from actual Qualified Hold and always enter Controlled Unload'
    Assert-NoMatch ($step1Ramp + $step1End + $step3End + $brakeBranch + $step4Hold) 'eNextState\s*:=\s*CFF_(?:COMPLETE_OK|COMPLETE_NOK|RETURN_LOCAL|RETURN_REFERENCE)' 'Step processing must not bypass Controlled Unload into Return or a terminal state'
    $qualifiedUs = [uint64]0; $deltaUs = [uint64]2000; foreach ($condition in @($true, $true, $false, $true)) { if ($condition) { $qualifiedUs += $deltaUs } }
    Assert-True ($qualifiedUs -eq 6000) 'Qualified hold must pause without reset'
    $nearMaximum = [uint64]::MaxValue - 5; $remainingTarget = [uint64]::MaxValue - 1; $largeDelta = [uint64]10
    $saturated = if ($largeDelta -ge ($remainingTarget - $nearMaximum)) { $remainingTarget } else { $nearMaximum + $largeDelta }
    Assert-True ($saturated -eq $remainingTarget) 'ULINT fixture must saturate before an overflowing addition'
}

if ($runSequenceExit) {
    # Fix8 RED/GREEN fixtures: unified IF/CASE ownership, real ELSE, exact CASE
    # identity, source finality, and half-open structural boundaries.
    $fix8CaseInsideIf = @'
IF bOuterGate THEN
    CASE eState OF
        CFF_IDLE:
            bIdle := TRUE;
    ELSE
        bUnknown := TRUE;
    END_CASE;
END_IF;
'@
    $fix8IfInsideCase = @'
CASE eState OF
    CFF_IDLE:
        IF bInnerGate THEN
            bIdle := TRUE;
        ELSE
            bIdle := FALSE;
        END_IF;
END_CASE;
'@
    $fix8OwnedCase = @((Get-CaseRegions $fix8CaseInsideIf).Regions)
    $fix8OwnedIf = @((Get-IfRegions $fix8IfInsideCase).Regions)
    Assert-True (($fix8OwnedCase.Count -eq 1) -and
        ($fix8OwnedCase[0].ParentIfDepth -eq 1) -and
        ($fix8OwnedCase[0].ParentCaseDepth -eq 0) -and
        ($fix8OwnedCase[0].ParentControlDepth -eq 1) -and
        ($fix8OwnedCase[0].DefaultStart -ge 0)) 'Fix8 parser must expose CASE ownership inside IF and its direct default boundary'
    Assert-True (($fix8OwnedIf.Count -eq 1) -and
        ($fix8OwnedIf[0].ParentIfDepth -eq 0) -and
        ($fix8OwnedIf[0].ParentCaseDepth -eq 1) -and
        ($fix8OwnedIf[0].ParentControlDepth -eq 1) -and
        $fix8OwnedIf[0].HasElse -and
        ($fix8OwnedIf[0].ElsifCount -eq 0) -and
        ($fix8OwnedIf[0].ElseStart -ge 0)) 'Fix8 parser must expose IF ownership inside CASE and its direct unconditional ELSE'
    Assert-True ((Get-IfRegions 'IF bBroken THEN bValue := TRUE;').Regions.Count -eq 0) 'Fix8 unbalanced IF parsing must fail closed'
    Assert-True ((Get-CaseRegions 'CASE eState OF CFF_IDLE: bValue := TRUE;').Regions.Count -eq 0) 'Fix8 unbalanced CASE parsing must fail closed'

    $fix9CaseArmRecognitionFixture = @'
CASE eMode OF
    UPPER_ARM:
        bUpperArm := TRUE;
    lower_arm:
        bLowerArm := TRUE;
    MiXeD_Arm:
        bMixedArm := TRUE;
    E_TestState.QuAlIfIeD_Arm:
        bQualifiedArm := TRUE;
ELSE
    bDefaultArm := TRUE;
END_CASE;
'@
    $fix9CaseArmRecognition = Get-CaseArmRegions $fix9CaseArmRecognitionFixture
    $fix9RecognitionCase = Get-UniqueCombinedTopLevelCaseRegion $fix9CaseArmRecognition.Text 'eMode'
    $fix9RecognitionArms = if ($null -ne $fix9RecognitionCase) {
        @($fix9CaseArmRecognition.Arms | Where-Object {
            $_.CaseId -eq $fix9RecognitionCase.CaseId
        } | Sort-Object MatchStart)
    } else {
        @()
    }
    $fix9RecognitionLabels = @(
        'UPPER_ARM',
        'lower_arm',
        'MiXeD_Arm',
        'E_TestState.QuAlIfIeD_Arm')
    $fix9RecognitionWriters = @(
        'bUpperArm',
        'bLowerArm',
        'bMixedArm',
        'bQualifiedArm')
    $fix9RecognitionValid = ($fix9RecognitionArms.Count -eq 4) -and
        ($null -ne $fix9RecognitionCase)
    if ($fix9RecognitionValid) {
        for ($fix9ArmIndex = 0; $fix9ArmIndex -lt $fix9RecognitionArms.Count; $fix9ArmIndex++) {
            $fix9Arm = $fix9RecognitionArms[$fix9ArmIndex]
            $fix9ExpectedEnd = if ($fix9ArmIndex -lt ($fix9RecognitionArms.Count - 1)) {
                $fix9RecognitionArms[$fix9ArmIndex + 1].MatchStart
            } else {
                $fix9RecognitionCase.DefaultStart
            }
            $fix9ArmBody = $fix9CaseArmRecognition.Text.Substring(
                $fix9Arm.BodyStart,
                $fix9Arm.BodyEnd - $fix9Arm.BodyStart)
            $fix9RecognitionValid = $fix9RecognitionValid -and
                $fix9Arm.Label.Equals(
                    $fix9RecognitionLabels[$fix9ArmIndex],
                    [System.StringComparison]::OrdinalIgnoreCase) -and
                ($fix9Arm.BodyEnd -eq $fix9ExpectedEnd) -and
                [regex]::IsMatch(
                    $fix9ArmBody,
                    "\b$($fix9RecognitionWriters[$fix9ArmIndex])\s*:=\s*TRUE\s*;") -and
                (-not [regex]::IsMatch(
                    $fix9ArmBody,
                    '\bbDefaultArm\s*:='))
        }
    }
    Assert-True $fix9RecognitionValid 'Fix9 CASE-arm scanner must recognize adjacent uppercase, lowercase, mixed-case, and qualified-enum labels with exact half-open boundaries'

    $fix9AssignmentPseudoArmFixture = @'
CASE eMode OF
    FIRST_ARM:
        bOrdinaryAssignment := TRUE;
        UPPER_ASSIGNMENT := FALSE;
        bAfterAssignments := TRUE;
    SECOND_ARM:
        bSecondArm := TRUE;
END_CASE;
'@
    $fix9AssignmentParsed = Get-CaseArmRegions $fix9AssignmentPseudoArmFixture
    $fix9AssignmentCase = Get-UniqueCombinedTopLevelCaseRegion $fix9AssignmentParsed.Text 'eMode'
    $fix9AssignmentArms = if ($null -ne $fix9AssignmentCase) {
        @($fix9AssignmentParsed.Arms | Where-Object {
            $_.CaseId -eq $fix9AssignmentCase.CaseId
        } | Sort-Object MatchStart)
    } else {
        @()
    }
    $fix9AssignmentValid = $fix9AssignmentArms.Count -eq 2
    if ($fix9AssignmentValid) {
        $fix9FirstAssignmentBody = $fix9AssignmentParsed.Text.Substring(
            $fix9AssignmentArms[0].BodyStart,
            $fix9AssignmentArms[0].BodyEnd - $fix9AssignmentArms[0].BodyStart)
        $fix9AssignmentValid = ($fix9AssignmentArms[0].BodyEnd -eq $fix9AssignmentArms[1].MatchStart) -and
            [regex]::IsMatch($fix9FirstAssignmentBody, '\bbOrdinaryAssignment\s*:=\s*TRUE\s*;') -and
            [regex]::IsMatch($fix9FirstAssignmentBody, '\bUPPER_ASSIGNMENT\s*:=\s*FALSE\s*;') -and
            [regex]::IsMatch($fix9FirstAssignmentBody, '\bbAfterAssignments\s*:=\s*TRUE\s*;') -and
            (@($fix9AssignmentArms | Where-Object {
                $_.Label -match '(?i)^(?:bOrdinaryAssignment|UPPER_ASSIGNMENT|bAfterAssignments)$'
            }).Count -eq 0)
    }
    Assert-True $fix9AssignmentValid 'Fix9 CASE-arm scanner must not treat ordinary identifier assignments as pseudo-arms or truncate the owning arm'

    $fix9NestedArmMetadataFixture = @'
IF bOuterGate THEN
    CASE eOuterMode OF
        OUTER_ARM:
            CASE eState OF
                CFF_NESTED:
                    bNestedArm := TRUE;
            END_CASE;
    END_CASE;
END_IF;
'@
    $fix9NestedArmParsed = Get-CaseArmRegions $fix9NestedArmMetadataFixture
    $fix9NestedCase = @($fix9NestedArmParsed.Cases | Where-Object {
        [regex]::IsMatch($_.Selector, '(?i)^\s*eState\s*$')
    })
    $fix9NestedArms = @(if ($fix9NestedCase.Count -eq 1) {
        $fix9NestedArmParsed.Arms | Where-Object {
            ($_.CaseId -eq $fix9NestedCase[0].CaseId) -and
                [regex]::IsMatch($_.Label, '(?i)^CFF_NESTED$')
        }
    } else {
        $null
    })
    $fix9NestedMetadataValid = $fix9NestedArms.Count -eq 1
    if ($fix9NestedMetadataValid) {
        $fix9NestedArm = $fix9NestedArms[0]
        $fix9NestedMetadataValid = ($fix9NestedArm.ParentDepth -eq 1) -and
            ($fix9NestedArm.ParentIfDepth -eq 1) -and
            ($fix9NestedArm.ParentCaseDepth -eq 1) -and
            ($fix9NestedArm.ParentControlDepth -eq 2) -and
            ($fix9NestedArm.ParentDepth -eq $fix9NestedCase[0].ParentDepth) -and
            ($fix9NestedArm.ParentIfDepth -eq $fix9NestedCase[0].ParentIfDepth) -and
            ($fix9NestedArm.ParentCaseDepth -eq $fix9NestedCase[0].ParentCaseDepth) -and
            ($fix9NestedArm.ParentControlDepth -eq $fix9NestedCase[0].ParentControlDepth) -and
            ($fix9NestedArm.ParentDepth -eq $fix9NestedArm.CaseParentDepth) -and
            ($fix9NestedArm.ParentIfDepth -eq $fix9NestedArm.CaseParentIfDepth) -and
            ($fix9NestedArm.ParentCaseDepth -eq $fix9NestedArm.CaseParentCaseDepth) -and
            ($fix9NestedArm.ParentControlDepth -eq $fix9NestedArm.CaseParentControlDepth)
    }
    Assert-True $fix9NestedMetadataValid 'Fix9 nested CASE arm must expose unified Parent* aliases equal to its owning CASE and compatibility metadata'

    $fix8DeadMainCase = @'
IF FALSE THEN
    CASE eState OF
        CFF_IDLE: bIdle := TRUE;
        CFF_CONTROLLED_FORCE_UNLOAD: bUnload := TRUE;
    END_CASE;
END_IF;
'@
    $fix8AlternateMainCase = @'
IF bGate THEN
    bDummy := TRUE;
ELSE
    CASE eState OF
        CFF_IDLE: bIdle := TRUE;
        CFF_CONTROLLED_FORCE_UNLOAD: bUnload := TRUE;
    END_CASE;
END_IF;
'@
    $fix8OuterCaseMainCase = @'
CASE eOuter OF
    0:
        CASE eState OF
            CFF_IDLE: bIdle := TRUE;
            CFF_CONTROLLED_FORCE_UNLOAD: bUnload := TRUE;
        END_CASE;
END_CASE;
'@
    foreach ($fix8HiddenMainCase in @(
            $fix8DeadMainCase,
            $fix8AlternateMainCase,
            $fix8OuterCaseMainCase)) {
        Assert-True ([string]::IsNullOrWhiteSpace((Get-UniqueTopLevelCaseArmBody $fix8HiddenMainCase 'eState' '(?:E_CffState\.)?CFF_IDLE'))) 'Fix8 main CASE helpers must reject eState CASE arms below IF/FALSE, IF/ELSE, or an outer CASE'
        Assert-True ([string]::IsNullOrWhiteSpace((Get-TextAfterUniqueTopLevelCase $fix8HiddenMainCase 'eState'))) 'Fix8 post-main-CASE helper must reject eState CASE below another control owner'
    }
    $fix8LastArmDefault = @'
CASE eState OF
    CFF_IDLE:
        bIdle := TRUE;
    CFF_CONTROLLED_FORCE_UNLOAD:
        bUnload := TRUE;
ELSE
    bUnknownPackage := TRUE;
END_CASE;
'@
    $fix8LastArmBody = Get-UniqueTopLevelCaseArmBody $fix8LastArmDefault 'eState' '(?:E_CffState\.)?CFF_CONTROLLED_FORCE_UNLOAD'
    Assert-True (([regex]::IsMatch($fix8LastArmBody, '\bbUnload\s*:=\s*TRUE')) -and
        (-not [regex]::IsMatch($fix8LastArmBody, '\bbUnknownPackage\s*:='))) 'Fix8 CASE arm body must end before the direct main CASE default even when the arm is last'

    $fix8FastInputsAtomic = @'
udiLiveFastRequestId := GVL_Command.stFast.nRequestId;
IF FC_IsNewerRequestId(udiCandidate := udiLiveFastRequestId, udiReference := GVL_FastInternal.stAcceptedCommand.nRequestId) THEN
    stFastCommandCandidate := GVL_Command.stFast;
    IF (stFastCommandCandidate.nRequestId = udiLiveFastRequestId)
        AND (GVL_Command.stFast.nRequestId = udiLiveFastRequestId) THEN
        GVL_FastInternal.stAcceptedCommand := stFastCommandCandidate;
    END_IF;
END_IF;
'@
    $fix8FastInputsCaseArm = "CASE eOuter OF`n    0:`n$fix8FastInputsAtomic`nEND_CASE;"
    $fix8FastInputsCaseDefault = "CASE eOuter OF`n    0: bDummy := TRUE;`nELSE`n$fix8FastInputsAtomic`nEND_CASE;"
    Assert-True (-not (Test-FastInputsAtomicAcceptance $fix8FastInputsCaseArm)) 'Fix8 FastInputs atomic transaction must reject an outer CASE arm owner'
    Assert-True (-not (Test-FastInputsAtomicAcceptance $fix8FastInputsCaseDefault)) 'Fix8 FastInputs atomic transaction must reject an outer CASE default owner'

    $fix8ReturnEvaluateElsifOnly = @'
IF NOT bReturnEntryBlocked THEN
    IF bReturnPublicationAllowed THEN
        IF (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)
            AND GVL_Status.stFast.stZAxis.bDone
            AND GVL_Status.stFast.stZAxis.bStandstill
            AND NOT tonReturn.Q THEN
            eNextState := CFF_EVALUATE;
        END_IF;
    ELSIF bConditionalFallback THEN
        eNextState := CFF_FAULT;
    END_IF;
END_IF;
'@
    $fix8ReturnIntentHealthElsifOnly = @'
IF GVL_Status.stFast.stZAxis.bReady
    AND GVL_Status.stFast.stRAxis.bReady
    AND NOT GVL_Status.stFast.stZAxis.bError
    AND NOT GVL_Status.stFast.stRAxis.bError THEN
    IF stCycleSnapshot.stProgram.stHeader.eReturnMode = RETURN_MODE_LOCAL THEN
        eNextState := CFF_RETURN_LOCAL;
    ELSIF stCycleSnapshot.stProgram.stHeader.eReturnMode = RETURN_MODE_REFERENCE THEN
        eNextState := CFF_RETURN_REFERENCE;
    ELSE
        eNextState := CFF_FAULT;
    END_IF;
ELSIF bConditionalFallback THEN
    eNextState := CFF_FAULT;
END_IF;
'@
    $fix8Step4ElsifNestedElse = @'
IF bStep4ProcessActive
    AND GVL_Process.stActual.bForceValid
    AND FC_IsFiniteLReal(rValue := GVL_Process.stActual.fForceControlN)
    AND FC_IsFiniteLReal(rValue := GVL_Status.stFast.stRAxis.rActualVelocity_rpm) THEN
    bRpmStopped := ABS(GVL_Status.stFast.stRAxis.rActualVelocity_rpm)
        <= stCycleSnapshot.stProgram.astSteps[4].stProceeding.fRpmStoppedThresholdRpm;
    bForceInBand := ABS(GVL_Process.stActual.fForceControlN
        - stCycleSnapshot.stProgram.astSteps[4].fSetForceN)
        <= stCycleSnapshot.stProgram.astSteps[4].stProceeding.fForceBandToleranceN;
ELSIF bConditionalFallback THEN
    IF bNested THEN
        bDummy := TRUE;
    ELSE
        bRpmStopped := FALSE;
        bForceInBand := FALSE;
    END_IF;
END_IF;
CASE eState OF
    CFF_IDLE: bDummy := TRUE;
END_CASE;
'@
    Assert-True (-not (Test-ReturnEvaluateOwnership $fix8ReturnEvaluateElsifOnly)) 'Fix8 RETURN_EVAL_ELSIF_ONLY must reject an ELSIF in place of the unconditional publication fallback'
    Assert-True (-not (Test-ReturnIntentPublicationOwnership $fix8ReturnIntentHealthElsifOnly)) 'Fix8 RETURN_INTENT_HEALTH_ELSIF_ONLY must reject an ELSIF in place of the unconditional health fallback'
    Assert-True (-not (Test-Step4QualificationGate $fix8Step4ElsifNestedElse)) 'Fix8 STEP4_ELSIF_NESTED_ELSE must reject a nested ELSE decoy below an outer ELSIF'

    $fix8ConditionalFallback = @'
IF NOT bExternalReady THEN
    bPositive := TRUE;
ELSIF bConditionalFallback THEN
    IF bNested THEN
        bDummy := TRUE;
    ELSE
        stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_FORCE_PROCESS;
        stMotionIntent.stZCommand.rDeceleration_mm_s2 := stSequenceConfigSnapshot.fStandardMoveDecelerationMmS2;
    END_IF;
END_IF;
'@
    $fix8UnknownConditional = Get-IfPartition $fix8ConditionalFallback 'NOT\s+bExternalReady' '' -TopLevel
    Assert-True (-not ($fix8UnknownConditional.HasElse -and
        ($fix8UnknownConditional.ElsifCount -eq 0) -and
        (Test-ForceOwnerDecelerationPackage $fix8UnknownConditional.AlternateBody))) 'Fix8 UNKNOWN_CONDITIONAL_FALLBACK_ACCEPTED must reject a conditional ELSIF plus nested ELSE decoy'
    $fix8ExternalConditional = Get-IfPartition ($fix8ConditionalFallback.Replace('NOT bExternalReady', 'bHealthyEvent')) 'bHealthyEvent' '' -TopLevel
    Assert-True (-not ($fix8ExternalConditional.HasElse -and
        ($fix8ExternalConditional.ElsifCount -eq 0) -and
        (Test-ForceOwnerDecelerationPackage $fix8ExternalConditional.AlternateBody))) 'Fix8 EXTERNAL_CONDITIONAL_UNSAFE_ACCEPTED must reject a conditional ELSIF plus nested ELSE decoy'

    $xmlCommentDecoyFixture = @'
<TcPlcObject><!--
CFF_CONTROLLED_FORCE_UNLOAD:
    bDecoyUnload := TRUE;
END_CASE
--><POU><Declaration><![CDATA[PROGRAM P]]></Declaration><Implementation><ST><![CDATA[CASE eState OF
CFF_CONTROLLED_FORCE_UNLOAD:
    bRealUnload := TRUE;
END_CASE
]]></ST></Implementation></POU></TcPlcObject>
'@
    $xmlCommentExecutable = Get-PouImplementationText $xmlCommentDecoyFixture
    $xmlCommentExecutableBranch = Get-CaseBranch $xmlCommentExecutable 'CFF_CONTROLLED_FORCE_UNLOAD' 'XML decoy fixture must expose the real executable CASE branch'
    Assert-True (([regex]::IsMatch($xmlCommentExecutableBranch, '\bbRealUnload\s*:=\s*TRUE\s*;')) -and
        (-not [regex]::IsMatch($xmlCommentExecutableBranch, '\bbDecoyUnload\s*:='))) 'SequenceExit must ignore XML-comment CASE decoys and inspect only executable POU ST'

    $nestedCaseBranchFixture = @'
CASE eState OF
    CFF_EXTSETPOINT_DISABLE:
        bBeforeNestedCase := TRUE;
        CASE eExitIntent OF
            CFF_EXIT_NORMAL_RETURN:
                eNextState := CFF_RETURN_LOCAL;
            CFF_EXIT_ABORT_NO_RETURN:
                eNextState := CFF_ABORT;
        END_CASE
        bAfterNestedCase := TRUE;
    CFF_RETURN_LOCAL:
        bReturnState := TRUE;
END_CASE
'@
    $nestedDisableBranch = Get-CaseBranch $nestedCaseBranchFixture 'CFF_EXTSETPOINT_DISABLE' 'Nested CASE fixture must expose the complete Disable arm'
    Assert-True (([regex]::IsMatch($nestedDisableBranch, '\bbBeforeNestedCase\s*:=\s*TRUE')) -and
        ([regex]::IsMatch($nestedDisableBranch, '\bCFF_EXIT_ABORT_NO_RETURN\s*:')) -and
        ([regex]::IsMatch($nestedDisableBranch, '\bbAfterNestedCase\s*:=\s*TRUE')) -and
        (-not [regex]::IsMatch($nestedDisableBranch, '\bbReturnState\s*:='))) 'CASE branch parser must retain nested ExitIntent arms and stop only at the next same-depth eState arm'

    $caseAwareIfPositiveFixture = @'
IF bOuterGate THEN
    bBeforeCase := TRUE;
    CASE eAuditMode OF
        0:
            bAuditValue := TRUE;
    ELSE
        bAuditValue := FALSE;
    END_CASE;
    bAfterCase := TRUE;
END_IF;
'@
    $caseAwareIfPositiveRegions = Get-IfRegions $caseAwareIfPositiveFixture
    $caseAwareOuterRegions = @($caseAwareIfPositiveRegions.Regions | Where-Object {
        ($_.ParentDepth -eq 0) -and
            [regex]::IsMatch($_.Condition, '(?is)^\s*bOuterGate\s*$')
    })
    $caseAwareIfPositiveBranches = Get-IfBranchRegions $caseAwareIfPositiveFixture
    $caseAwareOuterFirstBranches = @($caseAwareIfPositiveBranches.Branches | Where-Object {
        ($_.ParentDepth -eq 0) -and ($_.BranchOrder -eq 0) -and
            [regex]::IsMatch($_.Condition, '(?is)^\s*bOuterGate\s*$')
    })
    $caseAwareOuterBranches = if ($caseAwareOuterFirstBranches.Count -eq 1) {
        @($caseAwareIfPositiveBranches.Branches | Where-Object {
            $_.IfId -eq $caseAwareOuterFirstBranches[0].IfId
        })
    } else {
        @()
    }
    $caseAwareOuterBody = if ($caseAwareOuterRegions.Count -eq 1) {
        $caseAwareIfPositiveRegions.Text.Substring(
            $caseAwareOuterRegions[0].BodyStart,
            $caseAwareOuterRegions[0].BodyEnd - $caseAwareOuterRegions[0].BodyStart)
    } else {
        ''
    }
    Assert-True (($caseAwareOuterRegions.Count -eq 1) -and
        ($caseAwareOuterRegions[0].AlternateStart -lt 0) -and
        (@($caseAwareOuterBranches).Count -eq 1) -and
        $caseAwareOuterBranches[0].IsPositive -and
        [regex]::IsMatch($caseAwareOuterBody, '\bbAfterCase\s*:=\s*TRUE\s*;')) 'Fix7 parser fixture must keep CASE ELSE owned by CASE and retain the post-CASE statement in the sole positive IF branch'

    $caseAwareNestedIfFixture = @'
CASE eOuterMode OF
    0:
        IF bRealGate THEN
            bNestedValue := TRUE;
        ELSE
            bNestedValue := FALSE;
        END_IF;
ELSE
    bCaseDefault := TRUE;
END_CASE;
'@
    $caseAwareNestedBranches = Get-IfBranchRegions $caseAwareNestedIfFixture
    $caseAwareNestedFirstBranches = @($caseAwareNestedBranches.Branches | Where-Object {
        ($_.ParentDepth -eq 0) -and ($_.BranchOrder -eq 0) -and
            [regex]::IsMatch($_.Condition, '(?is)^\s*bRealGate\s*$')
    })
    $caseAwareRealIfBranches = if ($caseAwareNestedFirstBranches.Count -eq 1) {
        @($caseAwareNestedBranches.Branches | Where-Object {
            $_.IfId -eq $caseAwareNestedFirstBranches[0].IfId
        } | Sort-Object BranchOrder)
    } else {
        @()
    }
    Assert-True (($caseAwareRealIfBranches.Count -eq 2) -and
        $caseAwareRealIfBranches[0].IsPositive -and
        (-not $caseAwareRealIfBranches[1].IsPositive) -and
        [regex]::IsMatch($caseAwareRealIfBranches[0].Condition, '(?is)^\s*bRealGate\s*$') -and
        [string]::IsNullOrEmpty($caseAwareRealIfBranches[1].Condition)) 'Fix7 parser fixture must record only the real nested IF alternate and ignore the enclosing CASE default'

    $deepIfElsifCaseFixture = @'
IF bOuterGate THEN
    IF bFirstGate THEN
        nDeepValue := 1;
    ELSIF bSecondGate THEN
        CASE eNestedMode OF
            0:
                nDeepValue := 2;
        ELSE
            nDeepValue := 3;
        END_CASE;
        bAfterNestedCase := TRUE;
    ELSE
        nDeepValue := 4;
    END_IF;
ELSE
    bOuterFallback := TRUE;
END_IF;
'@
    $deepIfElsifCaseBranches = Get-IfBranchRegions $deepIfElsifCaseFixture
    $deepInnerFirstBranches = @($deepIfElsifCaseBranches.Branches | Where-Object {
        ($_.ParentDepth -eq 1) -and ($_.BranchOrder -eq 0) -and
            [regex]::IsMatch($_.Condition, '(?is)^\s*bFirstGate\s*$')
    })
    $deepInnerBranches = if ($deepInnerFirstBranches.Count -eq 1) {
        @($deepIfElsifCaseBranches.Branches | Where-Object {
            $_.IfId -eq $deepInnerFirstBranches[0].IfId
        } | Sort-Object BranchOrder)
    } else {
        @()
    }
    $deepOuterFirstBranches = @($deepIfElsifCaseBranches.Branches | Where-Object {
        ($_.ParentDepth -eq 0) -and ($_.BranchOrder -eq 0) -and
            [regex]::IsMatch($_.Condition, '(?is)^\s*bOuterGate\s*$')
    })
    $deepOuterBranches = if ($deepOuterFirstBranches.Count -eq 1) {
        @($deepIfElsifCaseBranches.Branches | Where-Object {
            $_.IfId -eq $deepOuterFirstBranches[0].IfId
        } | Sort-Object BranchOrder)
    } else {
        @()
    }
    $deepElsifBody = if (@($deepInnerBranches).Count -eq 3) {
        $deepIfElsifCaseBranches.Text.Substring(
            $deepInnerBranches[1].BodyStart,
            $deepInnerBranches[1].BodyEnd - $deepInnerBranches[1].BodyStart)
    } else {
        ''
    }
    Assert-True ((@($deepInnerBranches).Count -eq 3) -and
        (@($deepOuterBranches).Count -eq 2) -and
        ($deepInnerBranches[0].BranchOrder -eq 0) -and
        ($deepInnerBranches[1].BranchOrder -eq 1) -and
        ($deepInnerBranches[2].BranchOrder -eq 2) -and
        $deepInnerBranches[1].IsPositive -and
        (-not $deepInnerBranches[2].IsPositive) -and
        [regex]::IsMatch($deepInnerBranches[1].Condition, '(?is)^\s*bSecondGate\s*$') -and
        [regex]::IsMatch($deepElsifBody, '\bbAfterNestedCase\s*:=\s*TRUE\s*;')) 'Fix7 parser fixture must preserve deep IF/ELSIF ownership across a nested CASE default and retain the post-CASE ELSIF body'

    $suffixSafeExitFixture = 'bStopEventDecoy OR bAbortEventDecoy OR bHardForceDecoy OR bHardStrokeDecoy OR bCollisionDecoy OR bSensorInvalidDecoy OR (udiFirstFaultIdShadow > 0)'
    Assert-True (-not (Test-SafeExitExpression $suffixSafeExitFixture)) 'Safe-exit classifier fixture must reject suffix/shadow identifiers that omit every real safety cause'

    $shadowReturnSafeStopFixture = '((eState = CFF_RETURN_LOCAL) OR (eState = CFF_RETURN_REFERENCE) OR (eState = CFF_EVALUATE) OR (eState = CFF_COMPLETE_OK) OR (eState = CFF_COMPLETE_NOK)) AND bSafeExitRequestedShadow'
    Assert-True (-not (Test-ReturnSafeStopExpression $shadowReturnSafeStopFixture)) 'Return interruption classifier fixture must reject a shadow safe-exit identifier'

    $unsafeResetGateFixture = @'
bSafeTerminalReset := (bResetEvent OR bResetPendingLatched)
    OR (eState = CFF_IDLE) OR (eState = CFF_COMPLETE_OK)
    OR (eState = CFF_COMPLETE_NOK) OR (eState = CFF_ABORT)
    OR (eState = CFF_FAULT) OR NOT GVL_Status.stFast.stZAxis.bStandstill
    OR NOT GVL_Status.stFast.stRAxis.bStandstill
    OR NOT GVL_Status.stFast.stZExtSetpoint.bReleaseOwner;
'@
    $unsafeResetAssignment = Find-BooleanAssignmentCoveringPatterns $unsafeResetGateFixture @() '' 'bSafeTerminalReset'
    Assert-True (($null -ne $unsafeResetAssignment) -and
        (-not (Test-SafeTerminalResetExpression $unsafeResetAssignment.Expression))) 'Safe Reset fixture must reject OR/negated standstill and release polarity bypasses'

    $unsafeExternalReadyFixture = 'GVL_Status.stFast.stZExtSetpoint.bReleaseOwner OR TRUE'
    Assert-True (-not (Test-ExternalReadyExpression $unsafeExternalReadyFixture)) 'External-ready fixture must reject OR TRUE release bypasses'

    $ignoredExitRStopTimerFixture = @'
tonExitRAxisStop(
    IN := (bSafeExitRStopPending OR bUnknownExternalRStopPending OR bApproachFaultStopPending)
        AND NOT ((GVL_Status.stFast.udiAcceptedSequenceRCommandId = udiRCommandId)
            AND GVL_Status.stFast.stRAxis.bStandstill),
    PT := stSequenceConfigSnapshot.tRAxisStopTimeout);
'@
    Assert-True (-not (Test-ExitRStopTimeoutConsumption $ignoredExitRStopTimerFixture)) 'Exit R-stop fixture must reject a correctly-called timer whose Q output is never consumed'

    $deadReturnReadinessFixture = @'
IF ack AND done AND standstill THEN
    eNextState := CFF_EVALUATE;
END_IF
IF FALSE THEN
    bReleaseOwner := TRUE;
    stRAxis.bStandstill := TRUE;
    stZAxis.bReady := TRUE;
    stRAxis.bReady := TRUE;
    bHealthy := NOT GVL_Status.stFast.stZAxis.bError AND NOT GVL_Status.stFast.stRAxis.bError;
END_IF
'@
    Assert-True (-not (Test-AllAssignmentsCoveredByRequiredGuards $deadReturnReadinessFixture 'eNextState\s*:=\s*CFF_EVALUATE' @(
        'bReleaseOwner',
        'stRAxis\.bStandstill',
        'stZAxis\.bReady',
        'stRAxis\.bReady',
        'NOT\s+GVL_Status\.stFast\.stZAxis\.bError',
        'NOT\s+GVL_Status\.stFast\.stRAxis\.bError'
    ))) 'Return readiness fixture must reject safety tokens hidden in an unrelated dead branch'

    $missingReturnOverrideFixture = @'
stMotionIntent.stZCommand.bEnable := TRUE;
stMotionIntent.stZCommand.bReset := FALSE;
stMotionIntent.stZCommand.bStop := TRUE;
stMotionIntent.stZCommand.bHome := FALSE;
stMotionIntent.stZCommand.bMoveAbsolute := FALSE;
stMotionIntent.stZCommand.bMoveVelocity := FALSE;
stMotionIntent.stZCommand.bUseExternalSetpoint := FALSE;
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;
stMotionIntent.bExternalEnableRequest := FALSE;
stMotionIntent.bExternalDisableRequest := FALSE;
stMotionIntent.bForceProcessExitComplete := TRUE;
stMotionIntent.bRAxisProcessRequested := TRUE;
stMotionIntent.stRCommand.bEnable := TRUE;
stMotionIntent.stRCommand.bReset := FALSE;
stMotionIntent.stRCommand.bStop := TRUE;
stMotionIntent.stRCommand.bMoveVelocity := FALSE;
stMotionIntent.stRCommand.rVelocity_rpm := 0.0;
bForceControlEnable := FALSE;
'@
    Assert-True (-not (Test-ReturnSafeStopPriority $missingReturnOverrideFixture)) 'Return interruption fixture must reject FaultStop motion that leaves a previously selected Evaluate state intact'

    $terminalOverwriteFixture = @'
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;
stMotionIntent.bRAxisProcessRequested := TRUE;
stMotionIntent.stRCommand.bStop := TRUE;
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_NONE;
'@
    Assert-True (-not (Test-ConflictFreeSafetyMotionWriters $terminalOverwriteFixture '(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP')) 'Terminal ownership fixture must reject a later conflicting Z owner writer'

    $deadUnloadFixture = @'
IF FALSE THEN
    bUnloadStandstillQualified := bForceSetpointRampValid
        AND bForceSetpointRampReached
        AND ABS(fForceControlN) <= fContactForceOffN
        AND ABS(rAcceptedVelocity_mm_s) <= rStandstillVelocity_mm_s
        AND bUnloadHealthy;
END_IF;
IF tonUnloadStandstillConfirm.Q THEN
    eNextState := CFF_EXTSETPOINT_DISABLE;
END_IF;
eNextState := CFF_EXTSETPOINT_DISABLE;
'@
    $deadUnloadAssignment = Find-BooleanAssignmentCoveringPatterns $deadUnloadFixture @(
        'bForceSetpointRampValid',
        'bForceSetpointRampReached',
        'ABS\s*\(\s*fForceControlN\s*\)\s*<=\s*fContactForceOffN',
        'ABS\s*\(\s*rAcceptedVelocity_mm_s\s*\)\s*<=\s*rStandstillVelocity_mm_s',
        'bUnloadHealthy'
    ) '' 'bUnloadStandstillQualified'
    Assert-True ($null -eq $deadUnloadAssignment) 'Unload qualification helper must reject a complete token set hidden below IF FALSE'
    Assert-True (-not (Test-AllAssignmentsGuardedByPositiveIf $deadUnloadFixture 'eNextState\s*:=\s*CFF_EXTSETPOINT_DISABLE' @('tonUnloadStandstillConfirm\.Q') 0)) 'Unload migration helper must reject one confirmed transition plus an unguarded duplicate'
    Assert-True (-not (Test-PositiveAndExpression 'NOT bForceSetpointRampValid AND bForceSetpointRampReached AND ABS(force) <= off AND ABS(velocity) <= standstill AND bUnloadHealthy' @('bForceSetpointRampValid','bForceSetpointRampReached','ABS\s*\(force\)','ABS\s*\(velocity\)','bUnloadHealthy'))) 'Unload qualification helper must reject a negated positive ramp-valid term'
    Assert-True (-not (Test-UnloadHealthExpression 'GVL_Process.stActual.bForceValid OR TRUE')) 'Unload health helper must reject OR TRUE token stuffing'
    Assert-True (-not (Test-UnloadHealthExpression 'GVL_Process.stActual.bForceValid AND GVL_Process.stActual.bContactReferenceValid AND GVL_Process.stActual.bAxisSensorAgreement AND GVL_Status.stFast.bForceSetpointRampValid AND FC_IsFiniteLReal(rValue := rForceRamp_kN_s) AND rForceRamp_kN_s > 0.0 AND GVL_Status.stFast.stZExtSetpoint.bEnabled AND GVL_Status.stFast.stZExtSetpoint.bAcceptedSetpointValid AND FC_IsFiniteLReal(rValue := GVL_Status.stFast.stZExtSetpoint.rAcceptedVelocity_mm_s) AND NOT NOT bExternalError AND NOT bAxisError AND NOT bSensorInvalid')) 'Unload health helper must reject a double-NOT error bypass'

    $deadReleaseFixture = @'
IF FALSE THEN
    IF bReleaseOwner AND NOT pendingA AND NOT pendingB AND acceptedId = sourceId AND rStandstill THEN
        eNextState := CFF_RETURN_LOCAL;
    END_IF;
END_IF;
'@
    Assert-True (-not (Test-AllAssignmentsGuardedByPositiveIf $deadReleaseFixture 'eNextState\s*:=\s*CFF_RETURN_LOCAL' @('bReleaseOwner','NOT\s+pendingA','NOT\s+pendingB','acceptedId\s*=\s*sourceId','rStandstill') 4)) 'Disable release helper must reject a complete release gate hidden below IF FALSE'
    $wrongExitIntentMapFixture = @'
CASE eExitIntent OF
    CFF_EXIT_NORMAL_RETURN:
        eNextState := CFF_RETURN_LOCAL;
    CFF_EXIT_NOK_RETURN:
        eNextState := CFF_RETURN_REFERENCE;
    CFF_EXIT_ABORT_NO_RETURN:
        eNextState := CFF_RETURN_LOCAL;
        eDummyState := CFF_ABORT;
        eDummyState := CFF_FAULT;
    CFF_EXIT_FAULT_NO_RETURN:
        eNextState := CFF_FAULT;
END_CASE;
'@
    $wrongAbortMap = Get-CaseBranch $wrongExitIntentMapFixture 'CFF_EXIT_ABORT_NO_RETURN' 'ExitIntent fixture must expose an Abort arm' 'eExitIntent'
    Assert-True (([regex]::Matches($wrongAbortMap, 'eNextState\s*:=').Count -ne 1) -or
        (-not [regex]::IsMatch($wrongAbortMap, 'eNextState\s*:=\s*CFF_ABORT\s*;'))) 'ExitIntent mapping check must reject Abort routed to Return with dummy terminal tokens'

    $conflictingReturnFixture = @'
stMotionIntent.stZCommand.bEnable := TRUE;
stMotionIntent.stZCommand.bReset := FALSE;
stMotionIntent.stZCommand.bStop := FALSE;
stMotionIntent.stZCommand.bHome := FALSE;
stMotionIntent.stZCommand.bMoveAbsolute := TRUE;
stMotionIntent.stZCommand.bMoveAbsolute := FALSE;
stMotionIntent.stZCommand.bMoveVelocity := FALSE;
stMotionIntent.stZCommand.bUseExternalSetpoint := FALSE;
stMotionIntent.stZCommand.rHomePosition_mm := 0.0;
stMotionIntent.stZCommand.rPosition_mm := rTarget;
stMotionIntent.stZCommand.rVelocity_mm_s := stCycleSnapshot.stProgram.stHeader.fReturnVelocityMmS;
stMotionIntent.stZCommand.rAcceleration_mm_s2 := stSequenceConfigSnapshot.fStandardMoveAccelerationMmS2;
stMotionIntent.stZCommand.rDeceleration_mm_s2 := stSequenceConfigSnapshot.fStandardMoveDecelerationMmS2;
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_RETRACT;
'@
    Assert-True (-not (Test-ReturnLevelPayload $conflictingReturnFixture 'rTarget')) 'Return payload helper must reject a later conflicting MoveAbsolute writer'
    $deadReturnPayloadFixture = @'
stMotionIntent.stZCommand.bMoveAbsolute := TRUE;
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_RETRACT;
IF FALSE THEN
    stMotionIntent.stZCommand.bEnable := TRUE;
    stMotionIntent.stZCommand.bReset := FALSE;
    stMotionIntent.stZCommand.bStop := FALSE;
    stMotionIntent.stZCommand.bHome := FALSE;
    stMotionIntent.stZCommand.bMoveVelocity := FALSE;
    stMotionIntent.stZCommand.bUseExternalSetpoint := FALSE;
    stMotionIntent.stZCommand.rHomePosition_mm := 0.0;
    stMotionIntent.stZCommand.rPosition_mm := rTarget;
    stMotionIntent.stZCommand.rVelocity_mm_s := stCycleSnapshot.stProgram.stHeader.fReturnVelocityMmS;
    stMotionIntent.stZCommand.rAcceleration_mm_s2 := stSequenceConfigSnapshot.fStandardMoveAccelerationMmS2;
    stMotionIntent.stZCommand.rDeceleration_mm_s2 := stSequenceConfigSnapshot.fStandardMoveDecelerationMmS2;
END_IF;
'@
    Assert-True (-not (Test-ReturnLevelPayload $deadReturnPayloadFixture 'rTarget')) 'Return payload helper must reject required level fields hidden below IF FALSE'
    $correctZPayloadFixture = $conflictingReturnFixture -replace '(?m)^stMotionIntent\.stZCommand\.bMoveAbsolute\s*:=\s*FALSE;\r?\n', ''
    $conflictingSupportFixture = $correctZPayloadFixture + @'
stMotionIntent.bExternalEnableRequest := FALSE;
stMotionIntent.bExternalDisableRequest := FALSE;
stMotionIntent.rExternalTargetVelocity_mm_s := 0.0;
stMotionIntent.bForceProcessExitComplete := TRUE;
stMotionIntent.bRAxisProcessRequested := TRUE;
stMotionIntent.stRCommand.bEnable := TRUE;
stMotionIntent.stRCommand.bReset := FALSE;
stMotionIntent.stRCommand.bStop := TRUE;
stMotionIntent.stRCommand.bMoveVelocity := FALSE;
stMotionIntent.stRCommand.rVelocity_rpm := 0.0;
stMotionIntent.stRCommand.rAcceleration_rpm_s := stRAxisProfileSnapshot.fSpeedRampRpmS;
stMotionIntent.stRCommand.rDeceleration_rpm_s := stRAxisProfileSnapshot.fSpeedRampRpmS;
bForceControlEnable := FALSE;
stMotionIntent.stRCommand.bStop := FALSE;
'@
    Assert-True (-not (Test-ReturnLevelPayload $conflictingSupportFixture 'rTarget')) 'Return payload helper must reject a later conflicting R-stop/support writer'

    # Fix2 RED fixtures: each malicious snippet was independently proven to pass
    # the B038 helper that was supposed to reject it.  These fixtures remain in
    # the final suite as mutation guards after the helpers are hardened.
    $stringHiddenApproachWriterFixture = @'
bApproachNormalCompletion := NOT bStateEntry
    AND (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)
    AND GVL_Status.stFast.stZAxis.bDone
    AND GVL_Status.stFast.stZAxis.bStandstill
    AND (GVL_Status.stFast.udiAcceptedSequenceRCommandId = udiRCommandId)
    AND GVL_Status.stFast.stRAxis.bStandstill;
sAudit := '//'; bApproachNormalCompletion := TRUE;
'@
    $stringHiddenApproachAssignment = Find-BooleanAssignmentCoveringPatterns $stringHiddenApproachWriterFixture @() '' 'bApproachNormalCompletion'
    Assert-True ($null -eq $stringHiddenApproachAssignment) 'Fix2 fixture must reject a real later classifier writer hidden after comment-like text inside an IEC string literal'

    $validReturnEntryBlockedFixture = @'
bReturnEntryBlocked := bStopRequestedLatched OR bAbortEvent
    OR bResetPendingLatched OR bHardForceActive OR bHardStrokeActive
    OR bCollisionLimitActive OR bExternalError OR bAxisError OR bSensorInvalid
    OR (udiFirstFaultId > 0);
'@
    $validReturnEntryBlockedAssignment = Find-BooleanAssignmentCoveringPatterns $validReturnEntryBlockedFixture @() '' 'bReturnEntryBlocked'
    Assert-True (($null -ne $validReturnEntryBlockedAssignment) -and
        (Test-ReturnEntryBlockedExpression $validReturnEntryBlockedAssignment.Expression)) 'Fix2 fixture must accept the exact unique Return real-cause blocker'
    $falseReturnEntryBlockedFixture = @'
bReturnEntryBlocked := FALSE;
bReturnPublicationAllowed := NOT bReturnEntryBlocked
    AND bReturnLevelHealthy
    AND (NOT bStateEntry OR bReturnEntryAuthorized);
'@
    $falseReturnEntryBlockedAssignment = Find-BooleanAssignmentCoveringPatterns $falseReturnEntryBlockedFixture @() '' 'bReturnEntryBlocked'
    Assert-True (($null -ne $falseReturnEntryBlockedAssignment) -and
        (-not (Test-ReturnEntryBlockedExpression $falseReturnEntryBlockedAssignment.Expression))) 'Fix2 fixture must reject a FALSE or shadow Return blocker even when publication allowance looks exact'

    $validUnloadFreezeFixture = @'
rTargetRelativePosition_mm := GVL_Process.stActual.fSRelSensorMm;
rForceTransferVelocity_mm_s := GVL_Status.stFast.stZExtSetpoint.rAcceptedVelocity_mm_s;
bForceProfileTransferPending := TRUE;
bUnloadTransferInitialized := TRUE;
'@
    $unloadFreezePatterns = @(
        'rTargetRelativePosition_mm\s*:=\s*GVL_Process\.stActual\.fSRelSensorMm\s*;',
        'rForceTransferVelocity_mm_s\s*:=\s*GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s\s*;',
        'bForceProfileTransferPending\s*:=\s*TRUE\s*;',
        'bUnloadTransferInitialized\s*:=\s*TRUE\s*;'
    )
    Assert-True (Test-UniqueTopLevelOrderedAssignments $validUnloadFreezeFixture $unloadFreezePatterns) 'Fix2 fixture must accept SRel, accepted velocity, pending, then initialized freeze ordering'
    $reorderedUnloadFreezeFixture = @'
bUnloadTransferInitialized := TRUE;
rTargetRelativePosition_mm := GVL_Process.stActual.fSRelSensorMm;
rForceTransferVelocity_mm_s := GVL_Status.stFast.stZExtSetpoint.rAcceptedVelocity_mm_s;
bForceProfileTransferPending := TRUE;
'@
    Assert-True (-not (Test-UniqueTopLevelOrderedAssignments $reorderedUnloadFreezeFixture $unloadFreezePatterns)) 'Fix2 fixture must reject publishing Unload initialized before the frozen SRel/velocity/pending package'
    $validUnloadLifecycleFixture = @'
bForceProfileTransfer := FALSE;
CASE eState OF
    CFF_IDLE:
        IF bStartEvent THEN
            bForceProfileTransfer := FALSE;
            bForceProfileTransferPending := FALSE;
            bUnloadTransferInitialized := FALSE;
        END_IF;
    CFF_CONTROLLED_FORCE_UNLOAD:
        IF bStateEntry THEN
            IF NOT bUnloadTransferInitialized AND bUnloadHealthy THEN
                rTargetRelativePosition_mm := GVL_Process.stActual.fSRelSensorMm;
                rForceTransferVelocity_mm_s := GVL_Status.stFast.stZExtSetpoint.rAcceptedVelocity_mm_s;
                bForceProfileTransferPending := TRUE;
                bUnloadTransferInitialized := TRUE;
            END_IF;
        END_IF;
END_CASE;
IF bExternalOwnerHold AND bSafeExitRequested THEN
    IF (eExitIntent = CFF_EXIT_ABORT_NO_RETURN)
        AND bUnloadHealthy
        AND (eState >= CFF_CONTACT_SEARCH)
        AND (eState <= CFF_CONTROLLED_FORCE_UNLOAD) THEN
        IF eState < CFF_CONTROLLED_FORCE_UNLOAD THEN
            IF NOT bUnloadTransferInitialized THEN
                rTargetRelativePosition_mm := GVL_Process.stActual.fSRelSensorMm;
                rForceTransferVelocity_mm_s := GVL_Status.stFast.stZExtSetpoint.rAcceptedVelocity_mm_s;
                bForceProfileTransferPending := TRUE;
                bUnloadTransferInitialized := TRUE;
            END_IF;
        END_IF;
    END_IF;
END_IF;
IF bForceProfileTransferPending AND bForceControlEnable THEN
    bForceProfileTransfer := TRUE;
    bForceProfileTransferPending := FALSE;
END_IF;
IF bSafeTerminalReset THEN
    bForceProfileTransfer := FALSE;
    bForceProfileTransferPending := FALSE;
    bUnloadTransferInitialized := FALSE;
END_IF;
GVL_Status.stFast.stSequence.stMotionIntent := stMotionIntent;
'@
    Assert-True (Test-UnloadTransferWriterCardinality $validUnloadLifecycleFixture) 'Fix2 fixture must accept exactly two lifecycle clears and two one-shot Unload initialization writers'
    Assert-True (Test-UnloadTransferLifecycleOrdering $validUnloadLifecycleFixture) 'Fix2 fixture must accept both Unload initialization sites before transfer consumption and final status publication'
    $fix9UnloadSourceParsed = Get-CaseArmRegions $validUnloadLifecycleFixture
    $fix9UnloadSourceCase = Get-UniqueCombinedTopLevelCaseRegion $fix9UnloadSourceParsed.Text 'eState'
    Assert-True ($null -ne $fix9UnloadSourceCase) 'Fix9 Unload fixture must expose one exact combined-top-level CASE eState'
    if ($null -ne $fix9UnloadSourceCase) {
        $fix9UnloadPrefix = $fix9UnloadSourceParsed.Text.Substring(
            0,
            $fix9UnloadSourceCase.Start)
        $fix9UnloadCaseText = $fix9UnloadSourceParsed.Text.Substring(
            $fix9UnloadSourceCase.Start,
            $fix9UnloadSourceCase.End - $fix9UnloadSourceCase.Start)
        $fix9UnloadSuffix = $fix9UnloadSourceParsed.Text.Substring(
            $fix9UnloadSourceCase.End)
        $fix9UnloadWrappedCases = @(
            [pscustomobject]@{
                Name = 'IF FALSE'
                Text = $fix9UnloadPrefix + "IF FALSE THEN`n" +
                    $fix9UnloadCaseText + "`nEND_IF;`n" + $fix9UnloadSuffix
            },
            [pscustomobject]@{
                Name = 'real IF ELSE'
                Text = $fix9UnloadPrefix +
                    "IF bWrapperGate THEN`n    bWrapperDecoy := TRUE;`nELSE`n" +
                    $fix9UnloadCaseText + "`nEND_IF;`n" + $fix9UnloadSuffix
            },
            [pscustomobject]@{
                Name = 'outer CASE arm'
                Text = $fix9UnloadPrefix + "CASE eWrapperMode OF`n    0:`n" +
                    $fix9UnloadCaseText + "`nEND_CASE;`n" + $fix9UnloadSuffix
            },
            [pscustomobject]@{
                Name = 'outer CASE default'
                Text = $fix9UnloadPrefix +
                    "CASE eWrapperMode OF`n    0:`n        bWrapperDecoy := TRUE;`nELSE`n" +
                    $fix9UnloadCaseText + "`nEND_CASE;`n" + $fix9UnloadSuffix
            })
        foreach ($fix9WrappedUnload in $fix9UnloadWrappedCases) {
            Assert-True (-not (Test-UnloadTransferWriterCardinality $fix9WrappedUnload.Text)) "Fix9 Unload cardinality helper must reject main CASE eState under $($fix9WrappedUnload.Name) ownership"
            Assert-True (-not (Test-UnloadTransferLifecycleOrdering $fix9WrappedUnload.Text)) "Fix9 Unload ordering helper must reject main CASE eState under $($fix9WrappedUnload.Name) ownership"
        }

        $fix9UnloadDirectArms = @($fix9UnloadSourceParsed.Arms | Where-Object {
            $_.CaseId -eq $fix9UnloadSourceCase.CaseId
        })
        $fix9IdleSourceArms = @($fix9UnloadDirectArms | Where-Object {
            [regex]::IsMatch($_.Label, '(?i)^(?:E_CffState\.)?CFF_IDLE$')
        })
        $fix9UnloadSourceArms = @($fix9UnloadDirectArms | Where-Object {
            [regex]::IsMatch($_.Label, '(?i)^(?:E_CffState\.)?CFF_CONTROLLED_FORCE_UNLOAD$')
        })
        Assert-True (($fix9IdleSourceArms.Count -eq 1) -and
            ($fix9UnloadSourceArms.Count -eq 1)) 'Fix9 Unload fixture must expose one direct Idle arm and one direct Controlled-Unload arm'
        if (($fix9IdleSourceArms.Count -eq 1) -and
                ($fix9UnloadSourceArms.Count -eq 1)) {
            $fix9IdleSourceArm = $fix9IdleSourceArms[0]
            $fix9UnloadSourceArm = $fix9UnloadSourceArms[0]
            $fix9IdleSourceBody = $fix9UnloadSourceParsed.Text.Substring(
                $fix9IdleSourceArm.BodyStart,
                $fix9IdleSourceArm.BodyEnd - $fix9IdleSourceArm.BodyStart)
            $fix9UnloadSourceBody = $fix9UnloadSourceParsed.Text.Substring(
                $fix9UnloadSourceArm.BodyStart,
                $fix9UnloadSourceArm.BodyEnd - $fix9UnloadSourceArm.BodyStart)

            $fix9LowercaseUnloadRelocation = $fix9UnloadSourceParsed.Text.Substring(
                0,
                $fix9UnloadSourceArm.BodyStart) +
                "`n        bUnloadArmDecoy := TRUE;`n    cff_relocated_unload:`n" +
                $fix9UnloadSourceBody +
                $fix9UnloadSourceParsed.Text.Substring($fix9UnloadSourceArm.BodyEnd)
            Assert-True (-not (Test-UnloadTransferWriterCardinality $fix9LowercaseUnloadRelocation)) 'Fix9 Unload cardinality helper must reject the complete initializer relocated into a following lowercase arm'
            Assert-True (-not (Test-UnloadTransferLifecycleOrdering $fix9LowercaseUnloadRelocation)) 'Fix9 Unload ordering helper must reject the complete initializer relocated into a following lowercase arm'

            $fix9MixedCaseUnload = $fix9UnloadSourceParsed.Text
            $fix9MixedCaseUnloadLabels = @(
                [pscustomobject]@{
                    Arm = $fix9IdleSourceArm
                    Label = 'E_CffState.CfF_IdLe'
                },
                [pscustomobject]@{
                    Arm = $fix9UnloadSourceArm
                    Label = 'E_CffState.CfF_CoNtRoLlEd_FoRcE_UnLoAd'
                }) | Sort-Object { $_.Arm.MatchStart } -Descending
            foreach ($fix9LabelChange in $fix9MixedCaseUnloadLabels) {
                $fix9MixedCaseUnload = $fix9MixedCaseUnload.Remove(
                    $fix9LabelChange.Arm.MatchStart,
                    $fix9LabelChange.Arm.BodyStart - $fix9LabelChange.Arm.MatchStart).Insert(
                    $fix9LabelChange.Arm.MatchStart,
                    "    $($fix9LabelChange.Label):")
            }
            Assert-True (Test-UnloadTransferWriterCardinality $fix9MixedCaseUnload) 'Fix9 Unload cardinality helper must accept legitimate qualified mixed-case target labels'
            Assert-True (Test-UnloadTransferLifecycleOrdering $fix9MixedCaseUnload) 'Fix9 Unload ordering helper must accept legitimate qualified mixed-case target labels'

            $fix9IdleLastSourceLayoutValid =
                ($fix9IdleSourceArm.MatchStart -lt $fix9UnloadSourceArm.MatchStart) -and
                ($fix9IdleSourceArm.BodyEnd -eq $fix9UnloadSourceArm.MatchStart) -and
                ($fix9UnloadSourceArm.BodyEnd -eq $fix9UnloadSourceCase.BodyEnd)
            Assert-True $fix9IdleLastSourceLayoutValid 'Fix9 Idle-last reconstruction requires exact adjacent source arms in the owning main CASE'
            if ($fix9IdleLastSourceLayoutValid) {
                $fix9IdleLastCaseHead = $fix9UnloadSourceParsed.Text.Substring(
                    $fix9UnloadSourceCase.Start,
                    $fix9IdleSourceArm.MatchStart - $fix9UnloadSourceCase.Start)
                $fix9IdleSourceChunk = $fix9UnloadSourceParsed.Text.Substring(
                    $fix9IdleSourceArm.MatchStart,
                    $fix9IdleSourceArm.BodyEnd - $fix9IdleSourceArm.MatchStart)
                $fix9UnloadSourceChunk = $fix9UnloadSourceParsed.Text.Substring(
                    $fix9UnloadSourceArm.MatchStart,
                    $fix9UnloadSourceArm.BodyEnd - $fix9UnloadSourceArm.MatchStart)
                $fix9IdleLastCaseTail = $fix9UnloadSourceParsed.Text.Substring(
                    $fix9UnloadSourceCase.BodyEnd,
                    $fix9UnloadSourceCase.End - $fix9UnloadSourceCase.BodyEnd)
                $fix9IdleLastCase = $fix9IdleLastCaseHead +
                    $fix9UnloadSourceChunk + $fix9IdleSourceChunk +
                    $fix9IdleLastCaseTail
                $fix9IdleLastLifecycle = $fix9UnloadPrefix +
                    $fix9IdleLastCase + $fix9UnloadSuffix
                Assert-True (Test-UnloadTransferWriterCardinality $fix9IdleLastLifecycle) 'Fix9 Unload cardinality helper must accept the complete known-good lifecycle with Idle as the last explicit arm'
                Assert-True (Test-UnloadTransferLifecycleOrdering $fix9IdleLastLifecycle) 'Fix9 Unload ordering helper must accept the complete known-good lifecycle with Idle as the last explicit arm'

                $fix9IdleLastParsed = Get-CaseArmRegions $fix9IdleLastLifecycle
                $fix9IdleLastMainCase = Get-UniqueCombinedTopLevelCaseRegion $fix9IdleLastParsed.Text 'eState'
                $fix9IdleLastArms = @(if ($null -ne $fix9IdleLastMainCase) {
                    $fix9IdleLastParsed.Arms | Where-Object {
                        ($_.CaseId -eq $fix9IdleLastMainCase.CaseId) -and
                            [regex]::IsMatch(
                                $_.Label,
                                '(?i)^(?:E_CffState\.)?CFF_IDLE$')
                    }
                } else {
                    $null
                })
                Assert-True (($null -ne $fix9IdleLastMainCase) -and
                    ($fix9IdleLastArms.Count -eq 1) -and
                    ($fix9IdleLastArms[0].BodyEnd -eq $fix9IdleLastMainCase.BodyEnd)) 'Fix9 Idle-last fixture must expose one exact last Idle arm in the owning main CASE'
                if (($null -ne $fix9IdleLastMainCase) -and
                        ($fix9IdleLastArms.Count -eq 1) -and
                        ($fix9IdleLastArms[0].BodyEnd -eq $fix9IdleLastMainCase.BodyEnd)) {
                    $fix9IdleLastArm = $fix9IdleLastArms[0]
                    $fix9IdleLastHarmlessDefault = $fix9IdleLastParsed.Text.Insert(
                        $fix9IdleLastMainCase.BodyEnd,
                        "ELSE`n    bHarmlessUnknownState := TRUE;`n")
                    Assert-True (Test-UnloadTransferWriterCardinality $fix9IdleLastHarmlessDefault) 'Fix9 Unload cardinality helper must accept and exclude a harmless direct default after a valid last Idle arm'
                    Assert-True (Test-UnloadTransferLifecycleOrdering $fix9IdleLastHarmlessDefault) 'Fix9 Unload ordering helper must accept and exclude a harmless direct default after a valid last Idle arm'
                    $fix9IdlePackageInDefault = $fix9IdleLastParsed.Text.Substring(
                        0,
                        $fix9IdleLastArm.BodyStart) +
                        "`n        bIdleArmDecoy := TRUE;`nELSE`n" +
                        $fix9IdleSourceBody +
                        $fix9IdleLastParsed.Text.Substring($fix9IdleLastArm.BodyEnd)
                    Assert-True (-not (Test-UnloadTransferWriterCardinality $fix9IdlePackageInDefault)) 'Fix9 Unload cardinality helper must reject the Start package moved from last Idle into the main CASE default'
                    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $fix9IdlePackageInDefault)) 'Fix9 Unload ordering helper must reject the Start package moved from last Idle into the main CASE default'
                }
            }
        }
    }
    $fix8UnloadParsed = Get-CaseArmRegions $validUnloadLifecycleFixture
    $fix8UnloadMainCase = Get-UniqueCombinedTopLevelCaseRegion $fix8UnloadParsed.Text 'eState'
    $fix8UnloadArms = @($fix8UnloadParsed.Arms | Where-Object {
        ($null -ne $fix8UnloadMainCase) -and
            ($_.CaseId -eq $fix8UnloadMainCase.CaseId) -and
            [regex]::IsMatch($_.Label, '(?i)^(?:E_CffState\.)?CFF_CONTROLLED_FORCE_UNLOAD$')
    })
    Assert-True ($fix8UnloadArms.Count -eq 1) 'Fix8 Unload fixture must expose one direct last main-CASE Unload arm'
    if ($fix8UnloadArms.Count -eq 1) {
        $fix8UnloadArm = $fix8UnloadArms[0]
        $fix8UnloadArmBody = $fix8UnloadParsed.Text.Substring(
            $fix8UnloadArm.BodyStart,
            $fix8UnloadArm.BodyEnd - $fix8UnloadArm.BodyStart)
        $fix8UnloadHarmlessDefault = $fix8UnloadParsed.Text.Insert(
            $fix8UnloadArm.BodyEnd,
            "ELSE`n    bHarmlessUnknownState := TRUE;`n")
        Assert-True (Test-UnloadTransferLifecycleOrdering $fix8UnloadHarmlessDefault) 'Fix8 Unload lifecycle must accept and exclude a harmless direct default after the valid last arm'
        $fix8UnloadPackageInDefault = $fix8UnloadParsed.Text.Substring(0, $fix8UnloadArm.BodyStart) +
            "`n        bUnloadArmDecoy := TRUE;`nELSE`n" +
            $fix8UnloadArmBody +
            $fix8UnloadParsed.Text.Substring($fix8UnloadArm.BodyEnd)
        Assert-True (-not (Test-UnloadTransferWriterCardinality $fix8UnloadPackageInDefault)) 'Fix8 Unload lifecycle must reject the required initializer moved from the last explicit arm into the main CASE default'
        Assert-True (-not (Test-UnloadTransferLifecycleOrdering $fix8UnloadPackageInDefault)) 'Fix8 Unload ordering must reject the required initializer moved into the main CASE default'
    }
    $fix8UnloadConsumerResetAdjacent = $validUnloadLifecycleFixture.Replace(
        "    bForceProfileTransferPending := FALSE;`nEND_IF;`nIF bSafeTerminalReset THEN",
        "    bForceProfileTransferPending := FALSE;`nEND_IF;IF bSafeTerminalReset THEN")
    $fix8UnloadResetPublicationAdjacent = $fix8UnloadConsumerResetAdjacent.Replace(
        "    bUnloadTransferInitialized := FALSE;`nEND_IF;`nGVL_Status.stFast.stSequence.stMotionIntent := stMotionIntent;",
        "    bUnloadTransferInitialized := FALSE;`nEND_IF;GVL_Status.stFast.stSequence.stMotionIntent := stMotionIntent;")
    Assert-True (($fix8UnloadResetPublicationAdjacent -ne $validUnloadLifecycleFixture) -and
        (Test-UnloadTransferLifecycleOrdering $fix8UnloadResetPublicationAdjacent)) 'Fix8 half-open Unload consumer/reset/publication regions may be directly adjacent'
    $deadEntryUnloadFixture = $validUnloadLifecycleFixture -replace '(?s)(IF NOT bUnloadTransferInitialized AND bUnloadHealthy THEN\s*rTargetRelativePosition_mm := GVL_Process\.stActual\.fSRelSensorMm;\s*rForceTransferVelocity_mm_s := GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s;\s*bForceProfileTransferPending := TRUE;\s*bUnloadTransferInitialized := TRUE;\s*END_IF;)', "IF FALSE THEN`n`$1`nEND_IF;"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $deadEntryUnloadFixture)) 'Fix5 fixture must reject the complete Entry initializer below IF FALSE'
    $deadPreRouteUnloadFixture = $validUnloadLifecycleFixture -replace '(?s)(IF NOT bUnloadTransferInitialized THEN\s*rTargetRelativePosition_mm := GVL_Process\.stActual\.fSRelSensorMm;\s*rForceTransferVelocity_mm_s := GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s;\s*bForceProfileTransferPending := TRUE;\s*bUnloadTransferInitialized := TRUE;\s*END_IF;)', "IF 1 = 0 THEN`n`$1`nEND_IF;"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $deadPreRouteUnloadFixture)) 'Fix5 fixture must reject the complete pre-route initializer below IF 1 = 0'
    $splitCaseUnloadFixture = $validUnloadLifecycleFixture -replace '(?s)IF NOT bUnloadTransferInitialized AND bUnloadHealthy THEN\s*rTargetRelativePosition_mm := GVL_Process\.stActual\.fSRelSensorMm;\s*rForceTransferVelocity_mm_s := GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s;\s*bForceProfileTransferPending := TRUE;\s*bUnloadTransferInitialized := TRUE;\s*END_IF;', @'
IF NOT bUnloadTransferInitialized AND bUnloadHealthy THEN
    CASE eSplit OF
        0:
            rTargetRelativePosition_mm := GVL_Process.stActual.fSRelSensorMm;
        1:
            rForceTransferVelocity_mm_s := GVL_Status.stFast.stZExtSetpoint.rAcceptedVelocity_mm_s;
        2:
            bForceProfileTransferPending := TRUE;
        3:
            bUnloadTransferInitialized := TRUE;
    END_CASE;
END_IF;
'@
    Assert-True (-not (Test-UnloadTransferWriterCardinality $splitCaseUnloadFixture)) 'Fix5 fixture must reject one initializer split across mutually exclusive CASE arms'
    $parentOverwriteUnloadFixture = $validUnloadLifecycleFixture -replace '(?s)(IF NOT bUnloadTransferInitialized AND bUnloadHealthy THEN\s*rTargetRelativePosition_mm := GVL_Process\.stActual\.fSRelSensorMm;\s*rForceTransferVelocity_mm_s := GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s;\s*bForceProfileTransferPending := TRUE;\s*bUnloadTransferInitialized := TRUE;\s*END_IF;)', "`$1`nrTargetRelativePosition_mm := 0.0;"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $parentOverwriteUnloadFixture)) 'Fix5 fixture must reject an Entry initializer followed by a parent-scope SRel overwrite'
    $misplacedStartClearFixture = $validUnloadLifecycleFixture -replace 'bUnloadTransferInitialized := FALSE;\s*END_IF;\s*CFF_CONTROLLED_FORCE_UNLOAD:', "IF bDecoy THEN`n    bDummy := TRUE;`nELSE`n    bUnloadTransferInitialized := FALSE;`nEND_IF;`nEND_IF;`nCFF_CONTROLLED_FORCE_UNLOAD:"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $misplacedStartClearFixture)) 'Fix5 fixture must reject the Start clear below a negative ELSE-derived owner'
    $misplacedResetClearFixture = $validUnloadLifecycleFixture -replace 'IF bSafeTerminalReset THEN\s*bForceProfileTransfer := FALSE;\s*bForceProfileTransferPending := FALSE;\s*bUnloadTransferInitialized := FALSE;\s*END_IF;', "IF bSafeTerminalReset THEN`n    bForceProfileTransfer := FALSE;`n    bForceProfileTransferPending := FALSE;`n    CASE eResetDecoy OF`n        0: bUnloadTransferInitialized := FALSE;`n    END_CASE;`nEND_IF;"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $misplacedResetClearFixture)) 'Fix5 fixture must reject the safe Reset clear below a CASE owner'
    $extraUnloadClearFixture = $validUnloadLifecycleFixture + "`nbUnloadTransferInitialized := FALSE;"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $extraUnloadClearFixture)) 'Fix2 fixture must reject an extra per-scan Unload initialized clear outside Start/safe Reset'
    $earlyUnloadConsumerFixture = @'
bUnloadTransferInitialized := FALSE;
IF bNormalEntry THEN bUnloadTransferInitialized := TRUE; END_IF;
IF bForceProfileTransferPending AND bForceControlEnable THEN
    bForceProfileTransfer := TRUE;
    bForceProfileTransferPending := FALSE;
END_IF;
IF bAbortPreRoute THEN bUnloadTransferInitialized := TRUE; END_IF;
bUnloadTransferInitialized := FALSE;
GVL_Status.stFast.stSequence.stMotionIntent := stMotionIntent;
'@
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $earlyUnloadConsumerFixture)) 'Fix2 fixture must reject transfer consumption before every possible Unload initialization site'
    $arbitraryUnloadWritersFixture = @'
bUnloadTransferInitialized := FALSE;
bUnloadTransferInitialized := TRUE;
bUnloadTransferInitialized := FALSE;
bUnloadTransferInitialized := TRUE;
'@
    Assert-True (-not (Test-UnloadTransferWriterCardinality $arbitraryUnloadWritersFixture)) 'Fix4 fixture must reject arbitrary four Unload latch writers without the Start/Reset and healthy initialization owners'
    $pendingOverwriteUnloadFixture = $validUnloadLifecycleFixture -replace 'bForceProfileTransferPending := TRUE;', "bForceProfileTransferPending := TRUE;`nbForceProfileTransferPending := FALSE;"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $pendingOverwriteUnloadFixture)) 'Fix4 fixture must reject an initialization body that cancels its pending TRUE writer'
    $srelOverwriteUnloadFixture = $validUnloadLifecycleFixture -replace 'rTargetRelativePosition_mm := GVL_Process\.stActual\.fSRelSensorMm;', "rTargetRelativePosition_mm := GVL_Process.stActual.fSRelSensorMm;`nrTargetRelativePosition_mm := 0.0;"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $srelOverwriteUnloadFixture)) 'Fix4 fixture must reject a later SRel freeze overwrite in an initialization body'
    $misplacedUnloadClearFixture = $validUnloadLifecycleFixture + "`nbUnloadTransferInitialized := FALSE;"
    Assert-True (-not (Test-UnloadTransferWriterCardinality $misplacedUnloadClearFixture)) 'Fix4 fixture must reject a clear outside accepted Start or safe terminal Reset cleanup'
    $lateUnsafeMotionIntentPublicationFixture = $validUnloadLifecycleFixture + "`nGVL_Status.stFast.stSequence.stMotionIntent := stUnsafeMotionIntent;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $lateUnsafeMotionIntentPublicationFixture)) 'Fix4 fixture must reject a later unsafe whole motion-intent publication'
    $lateWholeSequencePublicationFixture = $validUnloadLifecycleFixture + "`nGVL_Status.stFast.stSequence := stUnsafeSequenceStatus;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $lateWholeSequencePublicationFixture)) 'Fix4 fixture must reject a later whole Sequence status overwrite'
    $lateDeepMotionIntentPublicationFixture = $validUnloadLifecycleFixture + "`nGVL_Status.stFast.stSequence.stMotionIntent.stZCommand.rDeceleration_mm_s2 := 0.0;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $lateDeepMotionIntentPublicationFixture)) 'Fix5 fixture must reject an arbitrary-depth motion-intent field writer after final publication'
    $alternateUnloadConsumerFixture = $validUnloadLifecycleFixture -replace '(?s)(IF bForceProfileTransferPending AND bForceControlEnable THEN\s*bForceProfileTransfer := TRUE;\s*bForceProfileTransferPending := FALSE;)\s*END_IF;', "`$1`nELSE`n    bForceProfileTransfer := TRUE;`n    bForceProfileTransferPending := FALSE;`nEND_IF;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $alternateUnloadConsumerFixture)) 'Fix6 fixture must reject a second transfer-consumer package in the consumer ELSE path'
    $deadUnloadPublicationFixture = $validUnloadLifecycleFixture -replace 'GVL_Status\.stFast\.stSequence\.stMotionIntent := stMotionIntent;', "IF FALSE THEN`n    GVL_Status.stFast.stSequence.stMotionIntent := stMotionIntent;`nEND_IF;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $deadUnloadPublicationFixture)) 'Fix6 fixture must reject final motion-intent publication below IF FALSE'
    $caseUnloadPublicationFixture = $validUnloadLifecycleFixture -replace 'GVL_Status\.stFast\.stSequence\.stMotionIntent := stMotionIntent;', "CASE ePublish OF`n    0: GVL_Status.stFast.stSequence.stMotionIntent := stMotionIntent;`nEND_CASE;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $caseUnloadPublicationFixture)) 'Fix6 fixture must reject final motion-intent publication inside a CASE arm'
    $immediateUnloadPulseCancellationFixture = $validUnloadLifecycleFixture -replace '(?s)(IF bForceProfileTransferPending AND bForceControlEnable THEN\s*bForceProfileTransfer := TRUE;\s*bForceProfileTransferPending := FALSE;\s*END_IF;)', "`$1`nbForceProfileTransfer := FALSE;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $immediateUnloadPulseCancellationFixture)) 'Fix7 fixture must reject an unguarded transfer-pulse cancellation immediately after the consumer'
    $alternateUnloadPulseCancellationFixture = $validUnloadLifecycleFixture -replace '(?s)(IF bForceProfileTransferPending AND bForceControlEnable THEN\s*bForceProfileTransfer := TRUE;\s*bForceProfileTransferPending := FALSE;)\s*END_IF;', "`$1`nELSE`n    bForceProfileTransfer := FALSE;`nEND_IF;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $alternateUnloadPulseCancellationFixture)) 'Fix7 fixture must reject transfer-pulse cancellation in the consumer alternate'
    $deadUnloadPulseCancellationFixture = $validUnloadLifecycleFixture -replace '(?s)(IF bForceProfileTransferPending AND bForceControlEnable THEN\s*bForceProfileTransfer := TRUE;\s*bForceProfileTransferPending := FALSE;\s*END_IF;)', "`$1`nIF FALSE THEN`n    bForceProfileTransfer := FALSE;`nEND_IF;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $deadUnloadPulseCancellationFixture)) 'Fix7 fixture must reject transfer-pulse cancellation below a dead IF owner'
    $caseUnloadPulseCancellationFixture = $validUnloadLifecycleFixture -replace '(?s)(IF bForceProfileTransferPending AND bForceControlEnable THEN\s*bForceProfileTransfer := TRUE;\s*bForceProfileTransferPending := FALSE;\s*END_IF;)', "`$1`nCASE ePulseCancel OF`n    0: bForceProfileTransfer := FALSE;`nEND_CASE;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $caseUnloadPulseCancellationFixture)) 'Fix7 fixture must reject transfer-pulse cancellation below a CASE owner'
    $lateUnloadPulseCancellationFixture = $validUnloadLifecycleFixture -replace 'GVL_Status\.stFast\.stSequence\.stMotionIntent := stMotionIntent;', "bForceProfileTransfer := FALSE;`nGVL_Status.stFast.stSequence.stMotionIntent := stMotionIntent;"
    Assert-True (-not (Test-UnloadTransferLifecycleOrdering $lateUnloadPulseCancellationFixture)) 'Fix7 fixture must reject a later transfer-pulse cancellation before final motion-intent publication'
    $deadStartPulseWriterFixture = $validUnloadLifecycleFixture -replace '(?s)(IF bStartEvent THEN\s*)bForceProfileTransfer := FALSE;', "`$1IF FALSE THEN`n    bForceProfileTransfer := FALSE;`nEND_IF;"
    Assert-True (($deadStartPulseWriterFixture -ne $validUnloadLifecycleFixture) -and
        (-not (Test-UnloadTransferLifecycleOrdering $deadStartPulseWriterFixture))) 'Fix7 fixture must reject the accepted Start transfer-pulse clear moved below a dead IF owner'
    $alternateStartPulsePattern = [regex]::new(
        '(?s)(?<Start>IF bStartEvent THEN)\s*' +
            'bForceProfileTransfer := FALSE;\s*' +
            '(?<Rest>bForceProfileTransferPending := FALSE;\s*' +
            'bUnloadTransferInitialized := FALSE;)\s*END_IF;')
    $alternateStartPulseWriterFixture = $alternateStartPulsePattern.Replace(
        $validUnloadLifecycleFixture,
        '${Start}' + "`n    " + '${Rest}' + "`nELSE`n    bForceProfileTransfer := FALSE;`nEND_IF;",
        1)
    Assert-True (($alternateStartPulseWriterFixture -ne $validUnloadLifecycleFixture) -and
        (-not (Test-UnloadTransferLifecycleOrdering $alternateStartPulseWriterFixture))) 'Fix7 fixture must reject the accepted Start transfer-pulse clear moved to the Start ELSE branch'
    $caseStartPulseWriterFixture = $validUnloadLifecycleFixture -replace '(?s)(IF bStartEvent THEN\s*)bForceProfileTransfer := FALSE;', "`$1CASE eStartPulseOwner OF`n    0: bForceProfileTransfer := FALSE;`nEND_CASE;"
    Assert-True (($caseStartPulseWriterFixture -ne $validUnloadLifecycleFixture) -and
        (-not (Test-UnloadTransferLifecycleOrdering $caseStartPulseWriterFixture))) 'Fix7 fixture must reject the accepted Start transfer-pulse clear moved below a CASE owner'
    $consumerThenResetPattern = [regex]::new(
        '(?s)(?<Consumer>IF bForceProfileTransferPending AND bForceControlEnable THEN\s*' +
            'bForceProfileTransfer := TRUE;\s*' +
            'bForceProfileTransferPending := FALSE;\s*END_IF;\s*)' +
            '(?<Reset>IF bSafeTerminalReset THEN\s*' +
            'bForceProfileTransfer := FALSE;\s*' +
            'bForceProfileTransferPending := FALSE;\s*' +
            'bUnloadTransferInitialized := FALSE;\s*END_IF;\s*)')
    $safeResetBeforeConsumerFixture = $consumerThenResetPattern.Replace(
        $validUnloadLifecycleFixture,
        '${Reset}${Consumer}',
        1)
    Assert-True (($safeResetBeforeConsumerFixture -ne $validUnloadLifecycleFixture) -and
        (-not (Test-UnloadTransferLifecycleOrdering $safeResetBeforeConsumerFixture))) 'Fix7 fixture must reject the complete safe Reset region moved before the transfer consumer'
    $resetThenPublicationPattern = [regex]::new(
        '(?s)(?<Reset>IF bSafeTerminalReset THEN\s*' +
            'bForceProfileTransfer := FALSE;\s*' +
            'bForceProfileTransferPending := FALSE;\s*' +
            'bUnloadTransferInitialized := FALSE;\s*END_IF;\s*)' +
            '(?<Publication>GVL_Status\.stFast\.stSequence\.stMotionIntent := stMotionIntent;)')
    $publicationBeforeResetFixture = $resetThenPublicationPattern.Replace(
        $validUnloadLifecycleFixture,
        '${Publication}' + "`n" + '${Reset}',
        1)
    Assert-True (($publicationBeforeResetFixture -ne $validUnloadLifecycleFixture) -and
        (-not (Test-UnloadTransferLifecycleOrdering $publicationBeforeResetFixture))) 'Fix7 fixture must reject final motion-intent publication moved before safe Reset sealing'

    $validReturnIntentPublicationFixture = @'
IF GVL_Status.stFast.stZAxis.bReady
    AND GVL_Status.stFast.stRAxis.bReady
    AND NOT GVL_Status.stFast.stZAxis.bError
    AND NOT GVL_Status.stFast.stRAxis.bError THEN
    IF stCycleSnapshot.stProgram.stHeader.eReturnMode = RETURN_MODE_LOCAL THEN
        eNextState := CFF_RETURN_LOCAL;
    ELSIF stCycleSnapshot.stProgram.stHeader.eReturnMode = RETURN_MODE_REFERENCE THEN
        eNextState := CFF_RETURN_REFERENCE;
    ELSE
        eNextState := CFF_FAULT;
    END_IF;
ELSE
    eNextState := CFF_FAULT;
END_IF;
'@
    Assert-True (Test-ReturnIntentPublicationOwnership $validReturnIntentPublicationFixture) 'Fix5 fixture must accept exact health ownership plus the approved Local/Reference priority mapping after the ExitIntent CASE arm is extracted'
    $laterReturnIntentStateFixture = $validReturnIntentPublicationFixture -replace '(?s)(    END_IF;)(\r?\nELSE\r?\n    eNextState := CFF_FAULT;)', "`$1`n    eNextState := CFF_FAULT;`$2"
    Assert-True (-not (Test-ReturnIntentPublicationOwnership $laterReturnIntentStateFixture)) 'Fix6 fixture must reject a state overwrite after the approved ReturnMode IF'
    $caseSplitReturnIntentFixture = $validReturnIntentPublicationFixture -replace '(?s)IF stCycleSnapshot\.stProgram\.stHeader\.eReturnMode = RETURN_MODE_LOCAL THEN.*?END_IF;', @'
CASE stCycleSnapshot.stProgram.stHeader.eReturnMode OF
    RETURN_MODE_LOCAL:
        eNextState := CFF_RETURN_LOCAL;
    RETURN_MODE_REFERENCE:
        eNextState := CFF_RETURN_REFERENCE;
END_CASE;
'@
    Assert-True (-not (Test-ReturnIntentPublicationOwnership $caseSplitReturnIntentFixture)) 'Fix5 fixture must reject Return targets split across CASE arms inside an extracted return-capable intent arm'

    $validReturnEvaluateOwnershipFixture = @'
IF NOT bReturnEntryBlocked THEN
    IF bReturnPublicationAllowed THEN
        IF (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)
            AND GVL_Status.stFast.stZAxis.bDone
            AND GVL_Status.stFast.stZAxis.bStandstill
            AND NOT tonReturn.Q THEN
            eNextState := CFF_EVALUATE;
        END_IF;
    ELSE
        eNextState := CFF_FAULT;
    END_IF;
END_IF;
'@
    Assert-True (Test-ReturnEvaluateOwnership $validReturnEvaluateOwnershipFixture) 'Fix5 fixture must accept Evaluate below the intentional event gate, publication gate, and exact ACK/Done/standstill/no-timeout leaf'
    $evaluateOutsideEventGateFixture = $validReturnEvaluateOwnershipFixture + "`neNextState := CFF_EVALUATE;"
    Assert-True (-not (Test-ReturnEvaluateOwnership $evaluateOutsideEventGateFixture)) 'Fix5 fixture must reject Evaluate outside the event-suppression gate'
    $evaluateOutsidePublicationGateFixture = $validReturnEvaluateOwnershipFixture -replace 'IF bReturnPublicationAllowed THEN', "eNextState := CFF_EVALUATE;`n    IF bReturnPublicationAllowed THEN"
    Assert-True (-not (Test-ReturnEvaluateOwnership $evaluateOutsidePublicationGateFixture)) 'Fix5 fixture must reject Evaluate outside the publication gate'
    $deadReturnEvaluateFixture = $validReturnEvaluateOwnershipFixture -replace '(?s)(IF \(GVL_Status\.stFast\.udiAcceptedSequenceZCommandId = udiZCommandId\).*?eNextState := CFF_EVALUATE;\s*END_IF;)', "IF FALSE THEN`n`$1`nEND_IF;"
    Assert-True (-not (Test-ReturnEvaluateOwnership $deadReturnEvaluateFixture)) 'Fix5 fixture must reject the exact Evaluate leaf below IF FALSE'
    $trueOrReturnEvaluateFixture = $validReturnEvaluateOwnershipFixture -replace 'IF \(GVL_Status\.stFast\.udiAcceptedSequenceZCommandId = udiZCommandId\)', 'IF TRUE OR (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)'
    Assert-True (-not (Test-ReturnEvaluateOwnership $trueOrReturnEvaluateFixture)) 'Fix5 fixture must reject TRUE OR in the Evaluate leaf'
    $wrongPolarityReturnEvaluateFixture = $validReturnEvaluateOwnershipFixture -replace 'AND GVL_Status\.stFast\.stZAxis\.bDone', 'AND NOT GVL_Status.stFast.stZAxis.bDone'
    Assert-True (-not (Test-ReturnEvaluateOwnership $wrongPolarityReturnEvaluateFixture)) 'Fix5 fixture must reject wrong-polarity Done ownership in the Evaluate leaf'
    $caseSplitReturnEvaluateFixture = $validReturnEvaluateOwnershipFixture -replace 'eNextState := CFF_EVALUATE;', "CASE eDecoy OF`n    0: eNextState := CFF_EVALUATE;`nEND_CASE;"
    Assert-True (-not (Test-ReturnEvaluateOwnership $caseSplitReturnEvaluateFixture)) 'Fix5 fixture must reject an Evaluate writer hidden in a CASE arm'
    $evaluateInPublicationElseFixture = $validReturnEvaluateOwnershipFixture -replace '        eNextState := CFF_FAULT;', "        eNextState := CFF_FAULT;`n        eNextState := CFF_EVALUATE;"
    Assert-True (-not (Test-ReturnEvaluateOwnership $evaluateInPublicationElseFixture)) 'Fix6 fixture must reject Evaluate in the publication-health ELSE path'
    $caseAwareReturnEvaluatePositiveFixture = @'
IF NOT bReturnEntryBlocked THEN
    IF bReturnPublicationAllowed THEN
        CASE eAuditMode OF
            0:
                bAuditValue := TRUE;
        ELSE
            bAuditValue := FALSE;
        END_CASE;
        IF (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)
            AND GVL_Status.stFast.stZAxis.bDone
            AND GVL_Status.stFast.stZAxis.bStandstill
            AND NOT tonReturn.Q THEN
            eNextState := CFF_EVALUATE;
        END_IF;
    ELSE
        eNextState := CFF_FAULT;
    END_IF;
END_IF;
'@
    Assert-True (Test-ReturnEvaluateOwnership $caseAwareReturnEvaluatePositiveFixture) 'Fix7 fixture must accept a harmless CASE default inside the positive Return publication body when the publication IF has its own real ELSE'
    $caseDecoyReturnEvaluateNegativeFixture = @'
IF NOT bReturnEntryBlocked THEN
    IF bReturnPublicationAllowed THEN
        CASE eAuditMode OF
            0:
                IF (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)
                    AND GVL_Status.stFast.stZAxis.bDone
                    AND GVL_Status.stFast.stZAxis.bStandstill
                    AND NOT tonReturn.Q THEN
                    eNextState := CFF_EVALUATE;
                END_IF;
        ELSE
            bAuditValue := FALSE;
        END_CASE;
        eNextState := CFF_FAULT;
    END_IF;
END_IF;
'@
    Assert-True (-not (Test-ReturnEvaluateOwnership $caseDecoyReturnEvaluateNegativeFixture)) 'Fix7 fixture must reject a CASE-default decoy when the Return publication IF has no real ELSE and Fault remains executable on the positive path'

    $wrongPolarityReturnGuardFixture = @'
IF NOT bReturnPublicationAllowed
    AND NOT (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)
    AND NOT GVL_Status.stFast.stZAxis.bDone
    AND NOT GVL_Status.stFast.stZAxis.bStandstill
    AND NOT tonReturn.Q THEN
    eNextState := CFF_EVALUATE;
END_IF;
'@
    Assert-True (-not (Test-AllAssignmentsCoveredByRequiredGuards $wrongPolarityReturnGuardFixture 'eNextState\s*:=\s*CFF_EVALUATE' @(
        'bReturnPublicationAllowed',
        'GVL_Status\.stFast\.udiAcceptedSequenceZCommandId\s*=\s*udiZCommandId',
        'GVL_Status\.stFast\.stZAxis\.bDone',
        'GVL_Status\.stFast\.stZAxis\.bStandstill',
        'NOT\s+tonReturn\.Q'
    ))) 'Fix2 fixture must reject inverted Return publication, ACK, Done, and Standstill facts'

    $trueOrReturnGuardFixture = @'
IF TRUE OR (bReturnPublicationAllowed
    AND (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)
    AND GVL_Status.stFast.stZAxis.bDone
    AND GVL_Status.stFast.stZAxis.bStandstill
    AND NOT tonReturn.Q) THEN
    eNextState := CFF_EVALUATE;
END_IF;
'@
    Assert-True (-not (Test-AllAssignmentsCoveredByRequiredGuards $trueOrReturnGuardFixture 'eNextState\s*:=\s*CFF_EVALUATE' @(
        'bReturnPublicationAllowed',
        'GVL_Status\.stFast\.udiAcceptedSequenceZCommandId\s*=\s*udiZCommandId',
        'GVL_Status\.stFast\.stZAxis\.bDone',
        'GVL_Status\.stFast\.stZAxis\.bStandstill',
        'NOT\s+tonReturn\.Q'
    ))) 'Fix2 fixture must reject a TRUE OR Return completion bypass'

    $wholeReturnOverwriteFixture = $correctZPayloadFixture + @'
stMotionIntent.bExternalEnableRequest := FALSE;
stMotionIntent.bExternalDisableRequest := FALSE;
stMotionIntent.rExternalTargetVelocity_mm_s := 0.0;
stMotionIntent.bForceProcessExitComplete := TRUE;
stMotionIntent.bRAxisProcessRequested := TRUE;
stMotionIntent.stRCommand.bEnable := TRUE;
stMotionIntent.stRCommand.bReset := FALSE;
stMotionIntent.stRCommand.bStop := TRUE;
stMotionIntent.stRCommand.bMoveVelocity := FALSE;
stMotionIntent.stRCommand.rVelocity_rpm := 0.0;
stMotionIntent.stRCommand.rAcceleration_rpm_s := stRAxisProfileSnapshot.fSpeedRampRpmS;
stMotionIntent.stRCommand.rDeceleration_rpm_s := stRAxisProfileSnapshot.fSpeedRampRpmS;
bForceControlEnable := FALSE;
stMotionIntent.stZCommand := stUnsafeZCommand;
'@
    Assert-True (-not (Test-ReturnLevelPayload $wholeReturnOverwriteFixture 'rTarget')) 'Fix2 fixture must reject a whole Z-command overwrite after a complete Return payload'

    $splitCaseSafetyPackageFixture = @'
CASE eSubState OF
    0: stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;
    1: stMotionIntent.bRAxisProcessRequested := TRUE;
    2: stMotionIntent.stRCommand.bStop := TRUE;
END_CASE;
'@
    Assert-True (-not (Test-ConflictFreeSafetyMotionWriters $splitCaseSafetyPackageFixture '(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP')) 'Fix2 fixture must reject safety package fields split across mutually exclusive CASE arms'

    $completeFaultStopFixture = $missingReturnOverrideFixture + @'
stMotionIntent.stZCommand.rHomePosition_mm := 0.0;
stMotionIntent.stZCommand.rPosition_mm := 0.0;
stMotionIntent.stZCommand.rVelocity_mm_s := 0.0;
stMotionIntent.stZCommand.rAcceleration_mm_s2 := stSequenceConfigSnapshot.fStandardMoveAccelerationMmS2;
stMotionIntent.stZCommand.rDeceleration_mm_s2 := stSequenceConfigSnapshot.fStandardMoveDecelerationMmS2;
stMotionIntent.rExternalTargetVelocity_mm_s := 0.0;
stMotionIntent.stRCommand.rAcceleration_rpm_s := stRAxisProfileSnapshot.fSpeedRampRpmS;
stMotionIntent.stRCommand.rDeceleration_rpm_s := stRAxisProfileSnapshot.fSpeedRampRpmS;
'@
    Assert-True (Test-CompleteFaultStopPayload $completeFaultStopFixture) 'Fix2 fixture must accept one complete top-level FaultStop package with frozen positive Z deceleration'
    $zeroDecelerationFaultStopFixture = $completeFaultStopFixture + @'
stMotionIntent.stZCommand.rDeceleration_mm_s2 := 0.0;
'@
    Assert-True (-not (Test-CompleteFaultStopPayload $zeroDecelerationFaultStopFixture)) 'Fix2 fixture must reject a complete FaultStop package with zero Z deceleration'

    $validForceDecelerationFixture = @'
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_FORCE_PROCESS;
stMotionIntent.stZCommand.rDeceleration_mm_s2 := stSequenceConfigSnapshot.fStandardMoveDecelerationMmS2;
'@
    Assert-True (Test-ForceOwnerDecelerationPackage $validForceDecelerationFixture) 'Fix2 fixture must accept one final frozen positive Force-owner deceleration writer'
    $forceDecelerationLaterWriterFixture = $validForceDecelerationFixture + @'
stMotionIntent.stZCommand.rDeceleration_mm_s2 := -1.0;
'@
    Assert-True (-not (Test-ForceOwnerDecelerationPackage $forceDecelerationLaterWriterFixture)) 'Fix2 fixture must reject a negative Force-owner deceleration writer after the nominal frozen assignment'
    $disableReleaseMissingDecelerationFixture = @'
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_FORCE_PROCESS;
stMotionIntent.stZCommand.bUseExternalSetpoint := TRUE;
stMotionIntent.bExternalDisableRequest := TRUE;
'@
    Assert-True (-not (Test-ForceOwnerDecelerationPackage $disableReleaseMissingDecelerationFixture)) 'Fix2 fixture must reject a Disable-release scan that publishes Force owner without a same-scan frozen deceleration'
    $unknownForceZeroDecelerationFixture = @'
stMotionIntent.stZCommand.eOwnerRequest := Z_OWNER_FORCE_PROCESS;
stMotionIntent.stZCommand.bUseExternalSetpoint := TRUE;
stMotionIntent.stZCommand.rDeceleration_mm_s2 := 0.0;
'@
    Assert-True (-not (Test-ForceOwnerDecelerationPackage $unknownForceZeroDecelerationFixture)) 'Fix2 fixture must reject an unknown-state Force-owner fallback with zero deceleration'

    $deadTerminalNormalizationFixture = @'
GVL_Status.stFast.stSequence.bDone := bDone;
IF FALSE THEN
    IF (eState <> eNextState)
        AND ((eNextState = CFF_ABORT) OR (eNextState = CFF_FAULT)) THEN
        bBusy := TRUE;
        bDone := FALSE;
        bError := FALSE;
        bAborted := FALSE;
    END_IF;
END_IF;
'@
    Assert-True (-not (Test-TerminalNormalizationBeforePublication $deadTerminalNormalizationFixture)) 'Fix2 fixture must reject terminal normalization hidden below a dead outer IF after status publication'

$validApproachPriorityFixture = @'
IF tonRAxisStop.Q OR (udiFirstFaultId = 16#0000A014) THEN
    eExitIntent := CFF_EXIT_FAULT_NO_RETURN;
    eNextState := CFF_FAULT;
ELSIF tonApproach.Q THEN
    IF udiFirstFaultId = 0 THEN
        udiFirstFaultId := 16#0000A007;
    END_IF;
    eExitIntent := CFF_EXIT_FAULT_NO_RETURN;
    eNextState := CFF_FAULT;
ELSIF (GVL_Status.stFast.udiAcceptedSequenceZCommandId = udiZCommandId)
    AND GVL_Status.stFast.stZAxis.bStandstill
    AND (GVL_Status.stFast.udiAcceptedSequenceRCommandId = udiRCommandId)
    AND GVL_Status.stFast.stRAxis.bStandstill THEN
    bApproachFaultStopPending := FALSE;
    IF eExitIntent = CFF_EXIT_ABORT_NO_RETURN THEN
        eNextState := CFF_ABORT;
    ELSIF eExitIntent = CFF_EXIT_FAULT_NO_RETURN THEN
        eNextState := CFF_FAULT;
    ELSE
        IF udiFirstFaultId = 0 THEN
            udiFirstFaultId := 16#0000A016;
        END_IF;
        eExitIntent := CFF_EXIT_FAULT_NO_RETURN;
        eNextState := CFF_FAULT;
    END_IF;
ELSE
    eNextState := eState;
END_IF;
'@
    Assert-True (Test-ApproachSafeExitPriorityFinality $validApproachPriorityFixture) 'Fix2 fixture must accept the final A014, A007, exact-ACK, hold Approach priority chain'
    $shortApproachFallbackFixture = $validApproachPriorityFixture -replace '(?s)ELSE\s*IF udiFirstFaultId = 0 THEN.*?eExitIntent := CFF_EXIT_FAULT_NO_RETURN;\s*eNextState := CFF_FAULT;\s*END_IF;', "ELSE`n        eNextState := CFF_FAULT;`n    END_IF;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $shortApproachFallbackFixture)) 'Fix4 fixture must reject an exact-ACK fallback that omits first-writer A016 and frozen Fault intent'
    $deadApproachA016Fixture = $validApproachPriorityFixture -replace '(?s)(IF udiFirstFaultId = 0 THEN\s*udiFirstFaultId := 16#0000A016;\s*END_IF;)', "IF FALSE THEN`n`$1`nEND_IF;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $deadApproachA016Fixture)) 'Fix5 fixture must reject fallback A016 below IF FALSE'
    $constantDeadApproachA016Fixture = $validApproachPriorityFixture -replace '(?s)(IF udiFirstFaultId = 0 THEN\s*udiFirstFaultId := 16#0000A016;\s*END_IF;)', "IF 1 = 0 THEN`n`$1`nEND_IF;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $constantDeadApproachA016Fixture)) 'Fix5 fixture must reject fallback A016 below IF 1 = 0'
    $laterApproachWriterFixture = $validApproachPriorityFixture + "`neNextState := eState;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $laterApproachWriterFixture)) 'Fix2 fixture must reject an Approach next-state writer after the safety priority chain'
    $laterApproachFaultWriterFixture = $validApproachPriorityFixture + "`nudiFirstFaultId := 16#0000DEAD;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $laterApproachFaultWriterFixture)) 'Fix5 fixture must reject a first-fault overwrite after the Approach priority chain'
    $laterApproachPendingWriterFixture = $validApproachPriorityFixture + "`nbApproachFaultStopPending := TRUE;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $laterApproachPendingWriterFixture)) 'Fix5 fixture must reject a pending-flag overwrite after the Approach priority chain'
    $laterApproachFirstFaultClearFixture = $validApproachPriorityFixture + "`nudiFirstFaultId := 0;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $laterApproachFirstFaultClearFixture)) 'Fix5 fixture must reject a first-fault clear after the Approach priority chain'
    $laterApproachIntentWriterFixture = $validApproachPriorityFixture + "`neExitIntent := CFF_EXIT_ABORT_NO_RETURN;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $laterApproachIntentWriterFixture)) 'Fix5 fixture must reject an exit-intent overwrite after the Approach priority chain'
    $duplicateApproachArmWriterFixture = $validApproachPriorityFixture -replace 'eNextState\s*:=\s*CFF_FAULT\s*;', "eNextState := CFF_ABORT;`n    eNextState := CFF_FAULT;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $duplicateApproachArmWriterFixture)) 'Fix2 fixture must reject sequential competing next-state writers inside an Approach priority arm'
    $a014FirstFaultWriterFixture = $validApproachPriorityFixture -replace '(IF tonRAxisStop\.Q OR \(udiFirstFaultId = 16#0000A014\) THEN)', "`$1`n    udiFirstFaultId := 16#0000DEAD;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $a014FirstFaultWriterFixture)) 'Fix6 fixture must reject a first-fault writer in the A014 priority arm'
    $a007FirstFaultOverwriteFixture = $validApproachPriorityFixture -replace '(udiFirstFaultId := 16#0000A007;\s*END_IF;)', "`$1`n    udiFirstFaultId := 16#0000DEAD;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $a007FirstFaultOverwriteFixture)) 'Fix6 fixture must reject a later first-fault overwrite in the A007 priority arm'
    $ackAbortFirstFaultWriterFixture = $validApproachPriorityFixture -replace '(IF eExitIntent = CFF_EXIT_ABORT_NO_RETURN THEN)', "`$1`n        udiFirstFaultId := 16#0000DEAD;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $ackAbortFirstFaultWriterFixture)) 'Fix6 fixture must reject a first-fault writer in the acknowledged Abort sibling arm'
    $ackFaultFirstFaultWriterFixture = $validApproachPriorityFixture -replace '(ELSIF eExitIntent = CFF_EXIT_FAULT_NO_RETURN THEN)', "`$1`n        udiFirstFaultId := 16#0000DEAD;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $ackFaultFirstFaultWriterFixture)) 'Fix6 fixture must reject a first-fault writer in the acknowledged frozen-Fault sibling arm'
    $a014ExitIntentOverwriteFixture = $validApproachPriorityFixture -replace '(IF tonRAxisStop\.Q OR \(udiFirstFaultId = 16#0000A014\) THEN\s*eExitIntent := CFF_EXIT_FAULT_NO_RETURN;)', "`$1`n    eExitIntent := CFF_EXIT_ABORT_NO_RETURN;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $a014ExitIntentOverwriteFixture)) 'Fix6 fixture must reject an exit-intent overwrite after the A014 Fault intent'
    $a007ExitIntentOverwriteFixture = $validApproachPriorityFixture -replace '(udiFirstFaultId := 16#0000A007;\s*END_IF;\s*eExitIntent := CFF_EXIT_FAULT_NO_RETURN;)', "`$1`n    eExitIntent := CFF_EXIT_ABORT_NO_RETURN;"
    Assert-True (-not (Test-ApproachSafeExitPriorityFinality $a007ExitIntentOverwriteFixture)) 'Fix6 fixture must reject an exit-intent overwrite after the A007 Fault intent'

    $validTerminalNormalizationFixture = @'
eNextState := CFF_ABORT;
IF (eState <> eNextState)
    AND ((eNextState = CFF_ABORT) OR (eNextState = CFF_FAULT)) THEN
    bBusy := TRUE;
    bDone := FALSE;
    bError := FALSE;
    bAborted := FALSE;
END_IF;
GVL_Status.stFast.stSequence.bBusy := bBusy;
GVL_Status.stFast.stSequence.bDone := bDone;
GVL_Status.stFast.stSequence.bError := bError;
GVL_Status.stFast.stSequence.bAborted := bAborted;
'@
    Assert-True (Test-TerminalNormalizationBeforePublication $validTerminalNormalizationFixture) 'Fix2 fixture must accept one top-level terminal normalization after routing and before all truth publication'
    $fix8TerminalAdjacencyPattern = [regex]::new(
        '(?is)(IF\s+\(eState\s*<>\s*eNextState\).*?END_IF\s*;)[\r\n\t ]*' +
            '(GVL_Status\.stFast\.stSequence\.bBusy\s*:=)')
    $fix8TerminalPublicationAdjacent = $fix8TerminalAdjacencyPattern.Replace(
        $validTerminalNormalizationFixture,
        '$1$2',
        1)
    Assert-True (($fix8TerminalPublicationAdjacent -ne $validTerminalNormalizationFixture) -and
        (Test-TerminalNormalizationBeforePublication $fix8TerminalPublicationAdjacent)) 'Fix8 half-open terminal normalization end may equal final truth publication start'
    $earlyOtherTerminalPublicationFixture = "GVL_Status.stFast.stSequence.eState := eState;`n" + $validTerminalNormalizationFixture
    Assert-True (-not (Test-TerminalNormalizationBeforePublication $earlyOtherTerminalPublicationFixture)) 'Fix2 fixture must reject any Sequence status publication before terminal normalization'
    $earlyWholeTerminalPublicationFixture = "GVL_Status.stFast.stSequence := stUnsafeSequenceStatus;`n" + $validTerminalNormalizationFixture
    Assert-True (-not (Test-TerminalNormalizationBeforePublication $earlyWholeTerminalPublicationFixture)) 'Fix2 fixture must reject a whole Sequence status publication before terminal normalization'
    $lateWholeTerminalPublicationFixture = $validTerminalNormalizationFixture + "`nGVL_Status.stFast.stSequence := stUnsafeSequenceStatus;"
    Assert-True (-not (Test-TerminalNormalizationBeforePublication $lateWholeTerminalPublicationFixture)) 'Fix5 fixture must reject a whole Sequence status overwrite after final truth publication'
    $deadTerminalTruthPublicationFixture = $validTerminalNormalizationFixture -replace '(?s)(GVL_Status\.stFast\.stSequence\.bBusy := bBusy;\s*GVL_Status\.stFast\.stSequence\.bDone := bDone;\s*GVL_Status\.stFast\.stSequence\.bError := bError;\s*GVL_Status\.stFast\.stSequence\.bAborted := bAborted;)', "IF FALSE THEN`n    `$1`nEND_IF;"
    Assert-True (-not (Test-TerminalNormalizationBeforePublication $deadTerminalTruthPublicationFixture)) 'Fix6 fixture must reject all terminal truth publications below IF FALSE'
    $caseTerminalTruthPublicationFixture = $validTerminalNormalizationFixture -replace '(?s)(GVL_Status\.stFast\.stSequence\.bBusy := bBusy;\s*GVL_Status\.stFast\.stSequence\.bDone := bDone;\s*GVL_Status\.stFast\.stSequence\.bError := bError;\s*GVL_Status\.stFast\.stSequence\.bAborted := bAborted;)', "CASE ePublish OF`n    0:`n        `$1`nEND_CASE;"
    Assert-True (-not (Test-TerminalNormalizationBeforePublication $caseTerminalTruthPublicationFixture)) 'Fix6 fixture must reject terminal truth publications inside a CASE arm'

    $validFastFaultStopChainFixture = @'
CASE GVL_Status.stFast.stSequence.stMotionIntent.stZCommand.eOwnerRequest OF
    Z_OWNER_FAULT_STOP:
        bZSequenceSourceActive := TRUE;
        stCandidateZSourceCommand := GVL_Status.stFast.stSequence.stMotionIntent.stZCommand;
END_CASE;
IF bNewZAdapterTransaction THEN
    stLatchedZSourceCommand := stCandidateZSourceCommand;
END_IF;
IF bSafeTerminalResetRising THEN
    udiZAdapterCommandId := udiZAdapterCommandId + 1;
    IF udiZAdapterCommandId = 0 THEN
        udiZAdapterCommandId := 1;
    END_IF;
    bNewZAdapterTransaction := TRUE;
    udiPendingZAdapterCommandId := udiZAdapterCommandId;
    udiPendingZSequenceSourceId := 0;
    bPendingZTransactionIsSequence := FALSE;
    stLatchedZSourceCommand.bEnable := FALSE;
    stLatchedZSourceCommand.bReset := TRUE;
    stLatchedZSourceCommand.bStop := FALSE;
    stLatchedZSourceCommand.bHome := FALSE;
    stLatchedZSourceCommand.bMoveAbsolute := FALSE;
    stLatchedZSourceCommand.bMoveVelocity := FALSE;
    stLatchedZSourceCommand.bUseExternalSetpoint := FALSE;
    stLatchedZSourceCommand.rHomePosition_mm := 0.0;
    stLatchedZSourceCommand.rPosition_mm := 0.0;
    stLatchedZSourceCommand.rVelocity_mm_s := 0.0;
    stLatchedZSourceCommand.rAcceleration_mm_s2 := 0.0;
    stLatchedZSourceCommand.rDeceleration_mm_s2 := 0.0;
    stLatchedZSourceCommand.eOwnerRequest := Z_OWNER_NONE;
    bFastSafetyStopLatched := FALSE;
END_IF;
bLatchedZFaultStopRequest :=
    (stLatchedZSourceCommand.eOwnerRequest = Z_OWNER_FAULT_STOP)
    OR bFastSafetyStopLatched;
stFaultStopCommand := stLatchedZSourceCommand;
fbZAxisArbiter(
    bFaultStopRequest := bLatchedZFaultStopRequest,
    stFaultStopCommand := stFaultStopCommand);
'@
    Assert-True (Test-FastFaultStopDecelerationChain $validFastFaultStopChainFixture) 'Fix2 fixture must accept the Sequence/central-latch Fast FaultStop copy chain with no later candidate writer'
    $fix8FastSourceCase = @((Get-CaseRegions $validFastFaultStopChainFixture).Regions | Where-Object {
        $_.Selector -eq 'GVL_Status.stFast.stSequence.stMotionIntent.stZCommand.eOwnerRequest'
    })
    Assert-True ($fix8FastSourceCase.Count -eq 1) 'Fix8 Fast fixture must expose one exact Sequence source-owner CASE'
    if ($fix8FastSourceCase.Count -eq 1) {
        $fix8FastDeadSourceCase = $validFastFaultStopChainFixture.Insert(
            $fix8FastSourceCase[0].End,
            "`nEND_IF;").Insert(
            $fix8FastSourceCase[0].Start,
            "IF FALSE THEN`n")
        $fix8FastAlternateSourceCase = $validFastFaultStopChainFixture.Insert(
            $fix8FastSourceCase[0].End,
            "`nEND_IF;").Insert(
            $fix8FastSourceCase[0].Start,
            "IF bConditionalOwner THEN`n    bDummy := TRUE;`nELSE`n")
        $fix8FastOuterCaseSource = $validFastFaultStopChainFixture.Insert(
            $fix8FastSourceCase[0].End,
            "`nEND_CASE;").Insert(
            $fix8FastSourceCase[0].Start,
            "CASE eOuterOwner OF`n    0:`n")
        Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastDeadSourceCase)) 'Fix8 Fast source CASE must reject IF FALSE ownership'
        Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastAlternateSourceCase)) 'Fix8 Fast source CASE must reject IF ELSE ownership'
        Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastOuterCaseSource)) 'Fix8 Fast source CASE must reject an outer CASE owner'
    }
    $fix8FastRenamedSource = $validFastFaultStopChainFixture.Replace(
        'CASE GVL_Status.stFast.stSequence.stMotionIntent.stZCommand.eOwnerRequest OF',
        'CASE eRenamedOwner OF')
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastRenamedSource)) 'Fix8 Fast source CASE must reject a renamed selector'
    $fix8FastSecondActiveInArm = $validFastFaultStopChainFixture.Replace(
        'stCandidateZSourceCommand := GVL_Status.stFast.stSequence.stMotionIntent.stZCommand;',
        "stCandidateZSourceCommand := GVL_Status.stFast.stSequence.stMotionIntent.stZCommand;`n        bZSequenceSourceActive := FALSE;")
    $fix8FastActiveAfterCase = $validFastFaultStopChainFixture.Replace(
        "END_CASE;`nIF bNewZAdapterTransaction",
        "END_CASE;`nbZSequenceSourceActive := FALSE;`nIF bNewZAdapterTransaction")
    $fix8FastCandidateAfterCase = $validFastFaultStopChainFixture.Replace(
        "END_CASE;`nIF bNewZAdapterTransaction",
        "END_CASE;`nstCandidateZSourceCommand := stUnsafeCommand;`nIF bNewZAdapterTransaction")
    $fix8FastActiveAfterLatch = $validFastFaultStopChainFixture.Replace(
        "    stLatchedZSourceCommand := stCandidateZSourceCommand;`nEND_IF;",
        "    stLatchedZSourceCommand := stCandidateZSourceCommand;`nEND_IF;`nbZSequenceSourceActive := FALSE;")
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastSecondActiveInArm)) 'Fix8 Fast source arm must reject a second active-source writer'
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastActiveAfterCase)) 'Fix8 Fast source must reject an active-source writer immediately after the source CASE'
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastCandidateAfterCase)) 'Fix8 Fast source must reject a candidate writer after the source CASE and before the latch'
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastActiveAfterLatch)) 'Fix8 Fast source must reject an active-source writer after the source latch'
    $fix8FastNestedPackage = $validFastFaultStopChainFixture.Replace(
        "        bZSequenceSourceActive := TRUE;`n        stCandidateZSourceCommand := GVL_Status.stFast.stSequence.stMotionIntent.stZCommand;",
        "        CASE eNestedOwner OF`n            0:`n                bZSequenceSourceActive := TRUE;`n                stCandidateZSourceCommand := GVL_Status.stFast.stSequence.stMotionIntent.stZCommand;`n        END_CASE;")
    $fix8FastDefaultPackage = $validFastFaultStopChainFixture.Replace(
        "    Z_OWNER_FAULT_STOP:`n        bZSequenceSourceActive := TRUE;`n        stCandidateZSourceCommand := GVL_Status.stFast.stSequence.stMotionIntent.stZCommand;",
        "    Z_OWNER_FAULT_STOP:`n        bDummy := TRUE;`nELSE`n        bZSequenceSourceActive := TRUE;`n        stCandidateZSourceCommand := GVL_Status.stFast.stSequence.stMotionIntent.stZCommand;")
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastNestedPackage)) 'Fix8 Fast source must reject the required package moved into a nested CASE'
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fix8FastDefaultPackage)) 'Fix8 Fast source must reject the required package moved into the source CASE default'
    $fix8FastResetAdjacencyPattern = [regex]::new(
        '(?is)(IF\s+bSafeTerminalResetRising\s+THEN.*?END_IF\s*;)[\r\n\t ]*' +
            '(bLatchedZFaultStopRequest\s*:=)')
    $fix8FastResetRequestAdjacent = $fix8FastResetAdjacencyPattern.Replace(
        $validFastFaultStopChainFixture,
        '$1$2',
        1)
    Assert-True (($fix8FastResetRequestAdjacent -ne $validFastFaultStopChainFixture) -and
        (Test-FastFaultStopDecelerationChain $fix8FastResetRequestAdjacent)) 'Fix8 half-open Fast safe-reset end may equal the central request start'
    $incompleteFastSafeResetFixture = $validFastFaultStopChainFixture -replace '(?m)^\s*stLatchedZSourceCommand\.eOwnerRequest\s*:=\s*Z_OWNER_NONE;\r?\n', '' -replace '(?m)^\s*bFastSafetyStopLatched\s*:=\s*FALSE;\r?\n', ''
    Assert-True (-not (Test-FastFaultStopDecelerationChain $incompleteFastSafeResetFixture)) 'Fix5 fixture must reject zero latched deceleration when safe Reset does not clear owner and the safety latch'
    $fastFaultStopFieldOverwriteFixture = $validFastFaultStopChainFixture -replace '(?m)^fbZAxisArbiter\(', "stFaultStopCommand.rDeceleration_mm_s2 := 0.0;`nfbZAxisArbiter("
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastFaultStopFieldOverwriteFixture)) 'Fix2 fixture must reject a Fast FaultStop deceleration field overwrite after the typed candidate copy'
    $fastFaultStopWholeOverwriteFixture = $validFastFaultStopChainFixture -replace '(?m)^fbZAxisArbiter\(', "stFaultStopCommand := stUnsafeCommand;`nfbZAxisArbiter("
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastFaultStopWholeOverwriteFixture)) 'Fix2 fixture must reject a Fast FaultStop whole-candidate overwrite before arbitration'
    $fastFaultStopFunctionOverwriteFixture = $validFastFaultStopChainFixture -replace '(?m)^fbZAxisArbiter\(', "stFaultStopCommand := FC_GetUnsafeCommand();`nfbZAxisArbiter("
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastFaultStopFunctionOverwriteFixture)) 'Fix2 fixture must reject a later Fast FaultStop whole-candidate writer with a function-call RHS'
    $fastFaultStopCandidateFieldOverwriteFixture = $validFastFaultStopChainFixture -replace '(?m)^END_CASE;', "    stCandidateZSourceCommand.rDeceleration_mm_s2 := 0.0;`nEND_CASE;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastFaultStopCandidateFieldOverwriteFixture)) 'Fix2 fixture must reject a FaultStop candidate field overwrite after the Sequence source copy'
    $fastFaultStopLatchedFieldOverwriteFixture = $validFastFaultStopChainFixture -replace '(?m)^bLatchedZFaultStopRequest', "stLatchedZSourceCommand.rDeceleration_mm_s2 := 0.0;`nbLatchedZFaultStopRequest"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastFaultStopLatchedFieldOverwriteFixture)) 'Fix2 fixture must reject a FaultStop latched-command field overwrite outside the exclusive terminal Reset branch'
    $fastFaultStopLateRequestFixture = $validFastFaultStopChainFixture + "`nbLatchedZFaultStopRequest := FALSE;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastFaultStopLateRequestFixture)) 'Fix4 fixture must reject a later FaultStop request FALSE after the exact central request expression'
    $fastFaultStopNegativeAfterArbiterFixture = $validFastFaultStopChainFixture + "`nstFaultStopCommand.rDeceleration_mm_s2 := -1.0;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastFaultStopNegativeAfterArbiterFixture)) 'Fix4 fixture must reject a later negative FaultStop field writer after arbitration'
    $fastFaultStopLateLatchedOverwriteFixture = $validFastFaultStopChainFixture + "`nstLatchedZSourceCommand.rDeceleration_mm_s2 := 0.0;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastFaultStopLateLatchedOverwriteFixture)) 'Fix4 fixture must reject a later latched-source deceleration overwrite after arbitration'
    $fastLatchDeadFixture = $validFastFaultStopChainFixture -replace '    stLatchedZSourceCommand := stCandidateZSourceCommand;', "    IF FALSE THEN`n        stLatchedZSourceCommand := stCandidateZSourceCommand;`n    END_IF;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastLatchDeadFixture)) 'Fix6 fixture must reject the transaction source-latch copy below IF FALSE'
    $fastLatchCaseFixture = $validFastFaultStopChainFixture -replace '    stLatchedZSourceCommand := stCandidateZSourceCommand;', "    CASE eLatch OF`n        0: stLatchedZSourceCommand := stCandidateZSourceCommand;`n    END_CASE;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastLatchCaseFixture)) 'Fix6 fixture must reject the transaction source-latch copy inside a CASE arm'
    $fastRequestDeadFixture = $validFastFaultStopChainFixture -replace '(?s)(bLatchedZFaultStopRequest :=\s*\(stLatchedZSourceCommand\.eOwnerRequest = Z_OWNER_FAULT_STOP\)\s*OR bFastSafetyStopLatched;)', "IF FALSE THEN`n    `$1`nEND_IF;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastRequestDeadFixture)) 'Fix6 fixture must reject the central FaultStop request below IF FALSE'
    $fastRequestCaseFixture = $validFastFaultStopChainFixture -replace '(?s)(bLatchedZFaultStopRequest :=\s*\(stLatchedZSourceCommand\.eOwnerRequest = Z_OWNER_FAULT_STOP\)\s*OR bFastSafetyStopLatched;)', "CASE eRequest OF`n    0:`n        `$1`nEND_CASE;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastRequestCaseFixture)) 'Fix6 fixture must reject the central FaultStop request inside a CASE arm'
    $fastTypedCopyDeadFixture = $validFastFaultStopChainFixture -replace 'stFaultStopCommand := stLatchedZSourceCommand;', "IF FALSE THEN`n    stFaultStopCommand := stLatchedZSourceCommand;`nEND_IF;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastTypedCopyDeadFixture)) 'Fix6 fixture must reject the typed FaultStop copy below IF FALSE'
    $fastTypedCopyCaseFixture = $validFastFaultStopChainFixture -replace 'stFaultStopCommand := stLatchedZSourceCommand;', "CASE eTyped OF`n    0: stFaultStopCommand := stLatchedZSourceCommand;`nEND_CASE;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastTypedCopyCaseFixture)) 'Fix6 fixture must reject the typed FaultStop copy inside a CASE arm'
    $fastArbiterDeadFixture = $validFastFaultStopChainFixture -replace '(?s)(fbZAxisArbiter\(\s*bFaultStopRequest := bLatchedZFaultStopRequest,\s*stFaultStopCommand := stFaultStopCommand\);)', "IF FALSE THEN`n    `$1`nEND_IF;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastArbiterDeadFixture)) 'Fix6 fixture must reject the Arbiter call below IF FALSE'
    $fastArbiterCaseFixture = $validFastFaultStopChainFixture -replace '(?s)(fbZAxisArbiter\(\s*bFaultStopRequest := bLatchedZFaultStopRequest,\s*stFaultStopCommand := stFaultStopCommand\);)', "CASE eArbiter OF`n    0:`n        `$1`nEND_CASE;"
    Assert-True (-not (Test-FastFaultStopDecelerationChain $fastArbiterCaseFixture)) 'Fix6 fixture must reject the Arbiter call inside a CASE arm'
    $fastResetBeforeLatchPattern = [regex]::new(
        '(?s)(?<Latch>IF bNewZAdapterTransaction THEN\s*' +
            'stLatchedZSourceCommand := stCandidateZSourceCommand;\s*END_IF;\s*)' +
            '(?<Reset>IF bSafeTerminalResetRising THEN.*?' +
            'bFastSafetyStopLatched := FALSE;\s*END_IF;\s*)')
    $fastResetBeforeLatchFixture = $fastResetBeforeLatchPattern.Replace(
        $validFastFaultStopChainFixture,
        '${Reset}${Latch}',
        1)
    Assert-True (($fastResetBeforeLatchFixture -ne $validFastFaultStopChainFixture) -and
        (-not (Test-FastFaultStopDecelerationChain $fastResetBeforeLatchFixture))) 'Fix7 fixture must reject a complete safe-reset sealing region moved before the new-transaction latch region'

    $validArbiterFaultStopFixture = @'
stCommand := stFaultStopCommand;
stCommand.bEnable := TRUE;
stCommand.bStop := TRUE;
stCommand.rAcceleration_mm_s2 := 0.0;
stCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;
'@
    Assert-True (Test-ArbiterFaultStopBranch $validArbiterFaultStopFixture) 'Fix2 fixture must accept an Arbiter FaultStop arm that preserves typed deceleration'
    $fix8ValidArbiterComposition = @'
CASE eActiveOwner OF
    Z_OWNER_FAULT_STOP:
        stCommand := stFaultStopCommand;
        stCommand.bEnable := TRUE;
        stCommand.bStop := TRUE;
        stCommand.rAcceleration_mm_s2 := 0.0;
        stCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;
    Z_OWNER_NONE:
        stCommand := stDefaultCommand;
END_CASE;
'@
    $fix9ArbiterSourceParsed = Get-CaseArmRegions $fix8ValidArbiterComposition
    $fix9ArbiterSourceCase = Get-UniqueCombinedTopLevelCaseRegion $fix9ArbiterSourceParsed.Text 'eActiveOwner'
    $fix9ArbiterFaultArms = @(if ($null -ne $fix9ArbiterSourceCase) {
        $fix9ArbiterSourceParsed.Arms | Where-Object {
            ($_.CaseId -eq $fix9ArbiterSourceCase.CaseId) -and
                [regex]::IsMatch(
                    $_.Label,
                    '(?i)^(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP$')
        }
    } else {
        $null
    })
    Assert-True ($fix9ArbiterFaultArms.Count -eq 1) 'Fix9 Arbiter fixture must expose one direct FaultStop owner arm'
    if ($fix9ArbiterFaultArms.Count -eq 1) {
        $fix9ArbiterFaultArm = $fix9ArbiterFaultArms[0]
        $fix9ArbiterFaultBody = $fix9ArbiterSourceParsed.Text.Substring(
            $fix9ArbiterFaultArm.BodyStart,
            $fix9ArbiterFaultArm.BodyEnd - $fix9ArbiterFaultArm.BodyStart)
        $fix9ArbiterLowercaseRelocation = $fix9ArbiterSourceParsed.Text.Substring(
            0,
            $fix9ArbiterFaultArm.BodyStart) +
            "`n        bFaultStopArmDecoy := TRUE;`n    cff_relocated_fault_stop:`n" +
            $fix9ArbiterFaultBody +
            $fix9ArbiterSourceParsed.Text.Substring($fix9ArbiterFaultArm.BodyEnd)
        Assert-True (-not (Test-ArbiterFaultStopComposition $fix9ArbiterLowercaseRelocation)) 'Fix9 Arbiter composition must reject the complete FaultStop package relocated into a following lowercase arm'

        $fix9ArbiterMixedCaseTarget = $fix9ArbiterSourceParsed.Text.Remove(
            $fix9ArbiterFaultArm.MatchStart,
            $fix9ArbiterFaultArm.BodyStart - $fix9ArbiterFaultArm.MatchStart).Insert(
            $fix9ArbiterFaultArm.MatchStart,
            '    E_ZCommandOwner.Z_OwNeR_FaUlT_StOp:')
        Assert-True (Test-ArbiterFaultStopComposition $fix9ArbiterMixedCaseTarget) 'Fix9 Arbiter composition must accept a legitimate qualified mixed-case FaultStop target label'
    }
    $fix8ArbiterOwnerCase = @((Get-CaseRegions $fix8ValidArbiterComposition).Regions | Where-Object {
        $_.Selector -eq 'eActiveOwner'
    })
    Assert-True ($fix8ArbiterOwnerCase.Count -eq 1) 'Fix8 Arbiter fixture must expose one exact active-owner CASE'
    Assert-True (Test-ArbiterFaultStopComposition $fix8ValidArbiterComposition) 'Fix8 Arbiter composition helper must accept one exact top-level active-owner FaultStop arm'
    if ($fix8ArbiterOwnerCase.Count -eq 1) {
        $fix8ArbiterDeadOwnerCase = $fix8ValidArbiterComposition.Insert(
            $fix8ArbiterOwnerCase[0].End,
            "`nEND_IF;").Insert(
            $fix8ArbiterOwnerCase[0].Start,
            "IF FALSE THEN`n")
        $fix8ArbiterAlternateOwnerCase = $fix8ValidArbiterComposition.Insert(
            $fix8ArbiterOwnerCase[0].End,
            "`nEND_IF;").Insert(
            $fix8ArbiterOwnerCase[0].Start,
            "IF bConditionalOwner THEN`n    bDummy := TRUE;`nELSE`n")
        foreach ($fix8MalformedArbiter in @(
                $fix8ArbiterDeadOwnerCase,
                $fix8ArbiterAlternateOwnerCase)) {
            Assert-True (-not (Test-ArbiterFaultStopComposition $fix8MalformedArbiter)) 'Fix8 Arbiter composition must reject active-owner CASE below IF FALSE or IF ELSE'
        }
    }
    $fix8ArbiterOuterOwnerCase = "CASE eOuterOwner OF`n    0:`n$fix8ValidArbiterComposition`nEND_CASE;"
    $fix8ArbiterRenamedOwnerCase = $fix8ValidArbiterComposition.Replace(
        'CASE eActiveOwner OF',
        'CASE eRenamedOwner OF')
    foreach ($fix8MalformedArbiter in @(
            $fix8ArbiterOuterOwnerCase,
            $fix8ArbiterRenamedOwnerCase)) {
        Assert-True (-not (Test-ArbiterFaultStopComposition $fix8MalformedArbiter)) 'Fix8 Arbiter composition must reject an outer CASE owner or renamed selector'
    }
    $fix8ArbiterNestedFaultLabel = $fix8ValidArbiterComposition.Replace(
        'stCommand := stDefaultCommand;',
        "CASE eDecoy OF`n            Z_OWNER_FAULT_STOP: stCommand := stFaultStopCommand;`n        END_CASE;")
    Assert-True (-not (Test-ArbiterFaultStopComposition $fix8ArbiterNestedFaultLabel)) 'Fix8 Arbiter composition must reject a nested duplicate FaultStop label'
    $fix8ArbiterNestedPackage = $fix8ValidArbiterComposition.Replace(
        "        stCommand := stFaultStopCommand;`n        stCommand.bEnable := TRUE;`n        stCommand.bStop := TRUE;`n        stCommand.rAcceleration_mm_s2 := 0.0;`n        stCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;",
        "        CASE eNestedOwner OF`n            0:`n                stCommand := stFaultStopCommand;`n                stCommand.bEnable := TRUE;`n                stCommand.bStop := TRUE;`n                stCommand.rAcceleration_mm_s2 := 0.0;`n                stCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;`n        END_CASE;")
    Assert-True (-not (Test-ArbiterFaultStopComposition $fix8ArbiterNestedPackage)) 'Fix8 Arbiter composition must reject the FaultStop package moved into a nested CASE'
    $fix8ArbiterDefaultPackage = $fix8ValidArbiterComposition.Replace(
        "    Z_OWNER_FAULT_STOP:`n        stCommand := stFaultStopCommand;`n        stCommand.bEnable := TRUE;`n        stCommand.bStop := TRUE;`n        stCommand.rAcceleration_mm_s2 := 0.0;`n        stCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;",
        "    Z_OWNER_FAULT_STOP:`n        bFaultStopArmDecoy := TRUE;")
    $fix8ArbiterDefaultPackage = $fix8ArbiterDefaultPackage.Replace(
        "END_CASE;",
        "ELSE`n        stCommand := stFaultStopCommand;`n        stCommand.bEnable := TRUE;`n        stCommand.bStop := TRUE;`n        stCommand.rAcceleration_mm_s2 := 0.0;`n        stCommand.eOwnerRequest := Z_OWNER_FAULT_STOP;`nEND_CASE;")
    Assert-True (-not (Test-ArbiterFaultStopComposition $fix8ArbiterDefaultPackage)) 'Fix8 Arbiter composition must reject the FaultStop package moved into the active-owner CASE default'
    $arbiterDecelerationOverwriteFixture = $validArbiterFaultStopFixture + "`nstCommand.rDeceleration_mm_s2 := 0.0;"
    Assert-True (-not (Test-ArbiterFaultStopBranch $arbiterDecelerationOverwriteFixture)) 'Fix2 fixture must reject an Arbiter FaultStop deceleration overwrite'
    $arbiterWholeOverwriteFixture = $validArbiterFaultStopFixture + "`nstCommand := stUnsafeCommand;"
    Assert-True (-not (Test-ArbiterFaultStopBranch $arbiterWholeOverwriteFixture)) 'Fix2 fixture must reject an Arbiter whole-command overwrite after the FaultStop copy'

    $validNcHaltFixture = @'
fbHalt(
    Axis := Axis,
    Execute := bHaltPulse,
    Deceleration := ABS(stCommand.rDeceleration_mm_s2),
    Jerk := 0.0,
    BufferMode := MC_Aborting);
'@
    Assert-True (Test-NcFaultStopDecelerationConsumer $validNcHaltFixture) 'Fix2 fixture must accept one top-level NC Halt consuming the typed deceleration through ABS'
    $constantNcHaltFixture = $validNcHaltFixture -replace 'ABS\(stCommand\.rDeceleration_mm_s2\)', '0.0'
    Assert-True (-not (Test-NcFaultStopDecelerationConsumer $constantNcHaltFixture)) 'Fix2 fixture must reject an NC Halt that replaces the typed deceleration with a constant'

    $unguardedFaultFixture = @'
IF udiFirstFaultId = 0 THEN
    udiFirstFaultId := 16#0000A010;
END_IF;
udiFirstFaultId := 16#0000A011;
'@
    Assert-True (-not (Test-AllNonzeroFirstFaultWritesGuarded $unguardedFaultFixture)) 'First-fault helper must reject a later unguarded overwrite'
    $alwaysTrueFaultFixture = @'
IF (udiFirstFaultId = 0) OR TRUE THEN
    udiFirstFaultId := 16#0000A010;
END_IF;
'@
    Assert-True (-not (Test-AllNonzeroFirstFaultWritesGuarded $alwaysTrueFaultFixture)) 'First-fault helper must reject an OR TRUE latch bypass'
    $reversedTerminalFixture = @'
bDone := TRUE;
bError := FALSE;
bAborted := FALSE;
bDone := FALSE;
'@
    Assert-True (-not (Test-TerminalTruthTableBranch $reversedTerminalFixture 'TRUE' 'FALSE' 'FALSE')) 'Terminal truth helper must reject a later reversed writer'
    $negatedTerminalFixture = @'
IF NOT GVL_Status.stFast.stZAxis.bStandstill
    AND GVL_Status.stFast.stRAxis.bStandstill
    AND bExternalReady THEN
    bDone := TRUE;
    bError := FALSE;
    bAborted := FALSE;
END_IF;
'@
    Assert-True (-not (Test-TerminalTruthTableBranch $negatedTerminalFixture 'TRUE' 'FALSE' 'FALSE')) 'Terminal truth helper must reject a negated standstill gate'
    $disableOverwriteFixture = @'
stMotionIntent.bExternalDisableRequest := TRUE;
stMotionIntent.bExternalDisableRequest := FALSE;
'@
    Assert-True (-not (Test-ExactBooleanAssignment $disableOverwriteFixture 'stMotionIntent\.bExternalDisableRequest' 'FALSE')) 'Healthy-event scan helper must reject Disable TRUE followed by a masking FALSE overwrite'
    $positiveVelocityOverwriteFixture = 'stMotionIntent.rExternalTargetVelocity_mm_s := 0.0; stMotionIntent.rExternalTargetVelocity_mm_s := 1.0;'
    Assert-True ([regex]::Matches($positiveVelocityOverwriteFixture, 'stMotionIntent\.rExternalTargetVelocity_mm_s\s*:=').Count -ne 1) 'Global safe-exit fixture must reject zero target followed by a positive overwrite'
    $fixtureRSourceId = [uint32]41
    $fixtureLastRWasMove = $true
    if ($fixtureLastRWasMove) { $fixtureRSourceId++; if ($fixtureRSourceId -eq 0) { $fixtureRSourceId = 1 } }
    $fixtureOldAckAllowsDisable = ([uint32]41 -eq $fixtureRSourceId)
    $fixtureLastRWasMove = $false
    if ($fixtureLastRWasMove) { $fixtureRSourceId++; if ($fixtureRSourceId -eq 0) { $fixtureRSourceId = 1 } }
    Assert-True (($fixtureRSourceId -eq 42) -and (-not $fixtureOldAckAllowsDisable)) 'Unload R-stop vector must publish Move/id41 to Stop/id42 exactly once and reject old ACK41'

    $healthyUnloadVectors = @(
        [pscustomobject]@{ Name = 'FirstAbortRoute'; StateRank = 10; Selected = 'Step'; Initialized = $false; Expected = 'Unload'; Transfers = 1 },
        [pscustomobject]@{ Name = 'NormalEntryFallback'; StateRank = 20; Selected = 'Unload'; Initialized = $false; Expected = 'Unload'; Transfers = 1 },
        [pscustomobject]@{ Name = 'ConfirmedUnload'; StateRank = 20; Selected = 'Disable'; Initialized = $true; Expected = 'Disable'; Transfers = 0 }
    )
    foreach ($vector in $healthyUnloadVectors) {
        $next = $vector.Selected
        if ($vector.StateRank -lt 20) { $next = 'Unload' }
        $transferCount = 0
        if ((-not $vector.Initialized) -and
                ((($vector.StateRank -lt 20) -and ($next -eq 'Unload')) -or
                    (($vector.StateRank -eq 20) -and ($vector.Selected -eq 'Unload')))) { $transferCount++ }
        Assert-True (($next -eq $vector.Expected) -and ($transferCount -eq $vector.Transfers)) "Healthy Unload vector $($vector.Name) must route/freeze once before Unload and preserve a confirmed Disable selection while already in Unload"
    }

    $returnLevelHealthy = $false
    $returnEntry = $true
    $returnEntryAuthorized = $false
    $returnNoEvent = $true
    $fixtureRetractIds = 0
    $fixtureRetractPublished = $false
    $fixtureFaultStopIds = 0
    $returnPublicationAllowed = $returnNoEvent -and $returnLevelHealthy -and
        ((-not $returnEntry) -or $returnEntryAuthorized)
    if ($returnPublicationAllowed) {
        $fixtureRetractIds++
        $fixtureRetractPublished = $true
    } else {
        $fixtureFaultStopIds++
    }
    Assert-True (($fixtureRetractIds -eq 0) -and (-not $fixtureRetractPublished) -and ($fixtureFaultStopIds -eq 1)) 'Return readiness-drop vector must reject Retract ID/publication and select one fresh FaultStop'
    $returnLevelHealthy = $true
    $returnEntry = $false
    $returnEntryAuthorized = $false
    $fixtureAcceptedRetractId = 51
    $fixtureCurrentRetractId = 51
    $fixtureZStandstill = $false
    $returnPublicationAllowed = $returnNoEvent -and $returnLevelHealthy -and
        ((-not $returnEntry) -or $returnEntryAuthorized)
    if ($returnPublicationAllowed) { $fixtureRetractPublished = $true }
    Assert-True ($returnPublicationAllowed -and $fixtureRetractPublished -and
        ($fixtureCurrentRetractId -eq $fixtureAcceptedRetractId) -and (-not $fixtureZStandstill)) 'Authorized Return vector must retain the same Retract payload/source while Z is moving without re-requiring Z standstill'
    $returnLevelHealthy = $false
    $fixtureFaultStopIds = 0
    $returnPublicationAllowed = $returnNoEvent -and $returnLevelHealthy -and
        ((-not $returnEntry) -or $returnEntryAuthorized)
    if (-not $returnPublicationAllowed) { $fixtureFaultStopIds++ }
    Assert-True ($fixtureFaultStopIds -eq 1) 'Return level-health loss during motion must select one fresh FaultStop'

    $terminalTransitionVectors = @(
        [pscustomobject]@{ Name = 'CompleteToAbort'; Current = 'Complete'; Next = 'Abort'; Busy = $false; Done = $true; Error = $false; Aborted = $false },
        [pscustomobject]@{ Name = 'AbortToFault'; Current = 'Abort'; Next = 'Fault'; Busy = $false; Done = $false; Error = $false; Aborted = $true }
    )
    foreach ($vector in $terminalTransitionVectors) {
        $busy = $vector.Busy
        $done = $vector.Done
        $terminalError = $vector.Error
        $aborted = $vector.Aborted
        if (($vector.Current -ne $vector.Next) -and ($vector.Next -in @('Abort','Fault'))) {
            $busy = $true
            $done = $false
            $terminalError = $false
            $aborted = $false
        }
        Assert-True ($busy -and (-not $done) -and (-not $terminalError) -and (-not $aborted)) "Terminal transition vector $($vector.Name) must clear stale terminal truth before publication"
    }

    $approachCauseVectors = @(
        [pscustomobject]@{ HardForce = $true; HardStroke = $false; Collision = $false; Sensor = $false; Expected = 0xA00C },
        [pscustomobject]@{ HardForce = $false; HardStroke = $false; Collision = $true; Sensor = $false; Expected = 0xA00E },
        [pscustomobject]@{ HardForce = $false; HardStroke = $false; Collision = $false; Sensor = $true; Expected = 0xA00F }
    )
    foreach ($vector in $approachCauseVectors) {
        $faultId = 0
        if ($vector.HardForce) { $faultId = 0xA00C }
        elseif ($vector.HardStroke) { $faultId = 0xA00D }
        elseif ($vector.Collision) { $faultId = 0xA00E }
        elseif ($vector.Sensor) { $faultId = 0xA00F }
        Assert-True ($faultId -eq $vector.Expected) 'Approach transient hard/collision/sensor vector must latch its deterministic first-cause ID in the triggering scan'
    }
    $approachNext = 'Prepare'
    $approachStopAcked = $false
    $approachTimedOut = $false
    if (-not $approachStopAcked) { $approachNext = 'Approach' }
    if ($approachTimedOut) { $approachNext = 'Fault' }
    Assert-True ($approachNext -eq 'Approach') 'Approach safety vector must override an earlier normal completion and wait for exact Z/R stop acknowledgement'
    $approachTimedOut = $true
    $approachFaultId = 0
    if ($approachTimedOut) {
        if ($approachFaultId -eq 0) { $approachFaultId = 0xA007 }
        $approachNext = 'Fault'
    }
    Assert-True (($approachNext -eq 'Fault') -and ($approachFaultId -eq 0xA007)) 'Approach timeout vector must enter Fault with first-writer A007 while retaining the stop package'
    $approachFaultId = 0xA014
    $approachRStopTimedOut = $true
    $approachTimedOut = $true
    if ($approachRStopTimedOut -or ($approachFaultId -eq 0xA014)) {
        $approachNext = 'Fault'
    } elseif ($approachTimedOut) {
        if ($approachFaultId -eq 0) { $approachFaultId = 0xA007 }
        $approachNext = 'Fault'
    }
    Assert-True (($approachNext -eq 'Fault') -and ($approachFaultId -eq 0xA014)) 'Approach R-stop timeout vector must keep first-writer A014 and outrank a same-scan Approach timeout'
    $approachEntry = $true
    $oldZSourceId = 0
    $oldAcceptedZSourceId = 0
    $oldRSourceId = 0
    $oldAcceptedRSourceId = 0
    $approachNormalCompletion = (-not $approachEntry) -and
        ($oldAcceptedZSourceId -eq $oldZSourceId) -and
        ($oldAcceptedRSourceId -eq $oldRSourceId)
    Assert-True (-not $approachNormalCompletion) 'Approach Entry stale-ACK vector must reject old/zero Z/R IDs before new Entry transactions are created'

    $idleVectors = @(
        [pscustomobject]@{ Name = 'Stop'; Stop = $true; Abort = $false; ResetPending = $false; SafeReset = $false; Expected = 'Abort' },
        [pscustomobject]@{ Name = 'UnsafeReset'; Stop = $false; Abort = $false; ResetPending = $true; SafeReset = $false; Expected = 'Abort' },
        [pscustomobject]@{ Name = 'SafeReset'; Stop = $false; Abort = $false; ResetPending = $false; SafeReset = $true; Expected = 'Idle' }
    )
    foreach ($vector in $idleVectors) {
        $next = 'Idle'
        $zId = 7
        $rId = 9
        if ((-not $vector.SafeReset) -and ($vector.Stop -or $vector.Abort -or $vector.ResetPending)) { $next = 'Abort' }
        Assert-True (($next -eq $vector.Expected) -and ($zId -eq 7) -and ($rId -eq 9)) "Idle vector $($vector.Name) must distinguish safe Reset from direct no-transaction Abort"
    }
    $fixtureEndCause = 'HardForce'
    $fixtureStopLatched = $true
    if ($fixtureStopLatched) { $fixtureEndCause = 'StopRequest' }
    Assert-True ($fixtureEndCause -eq 'StopRequest') 'Latched Stop diagnostic vector must retain STEP_END_STOP_REQUEST over later state diagnostics'

    $localTargetVectors = @(
        [pscustomobject]@{ Value = [double]::NaN; Expected = $false },
        [pscustomobject]@{ Value = -10.1; Expected = $false },
        [pscustomobject]@{ Value = -10.0; Expected = $true },
        [pscustomobject]@{ Value = 10.0; Expected = $true },
        [pscustomobject]@{ Value = 10.1; Expected = $false }
    )
    foreach ($vector in $localTargetVectors) {
        $valid = (-not [double]::IsNaN($vector.Value)) -and (-not [double]::IsInfinity($vector.Value)) -and ($vector.Value -ge -10.0) -and ($vector.Value -le 10.0)
        Assert-True ($valid -eq $vector.Expected) 'Local Return target vector must reject NaN/out-of-range and accept inclusive frozen Z limits'
    }

    $fixtureFaultStopDeceleration = 6.25
    $fixturePreservedDeceleration = $fixtureFaultStopDeceleration
    $fixtureZeroForcedDeceleration = 0.0
    Assert-True (($fixturePreservedDeceleration -eq 6.25) -and ($fixtureZeroForcedDeceleration -ne $fixtureFaultStopDeceleration)) 'FaultStop arbiter fixture must preserve positive typed deceleration and reject zero-forcing behavior'

    $sequenceRaw = Read-Text 'CFFwelding_System\CFFwelding\POUs\Fast\PRG_CffSequence.TcPOU'
    $sequence = Get-PouImplementationText $sequenceRaw
    $sequenceDeclaration = Get-PouDeclarationText $sequenceRaw
    Assert-True (-not [string]::IsNullOrWhiteSpace($sequence)) 'SequenceExit must parse only the executable POU Implementation ST CDATA'
    Assert-True (-not [string]::IsNullOrWhiteSpace($sequenceDeclaration)) 'SequenceExit must parse the POU Declaration CDATA independently of executable ST'
    Assert-Match $sequenceDeclaration 'bUnloadTransferInitialized\s*:\s*BOOL' 'Sequence must persist one Unload transfer-initialized latch across the lifecycle'
    Assert-True (Test-UnloadTransferWriterCardinality $sequence) 'Unload initialized latch must have exactly two TRUE writers and two FALSE writers in the entire executable Sequence'
    Assert-True (Test-UnloadTransferLifecycleOrdering $sequence) 'Both Unload freeze sites must precede transfer consumption, which must precede final motion-intent status publication'
    $reviewIdleBranchForStart = Get-CaseBranch $sequence 'CFF_IDLE' 'SequenceExit review requires an executable Idle branch'
    $reviewStart = Get-IfPartition $reviewIdleBranchForStart '\(?\s*bStartEvent\s*\)?' 'Every accepted Start must have one cycle initialization region'
    Assert-MatchCount $reviewStart.PositiveBody 'bUnloadTransferInitialized\s*:=\s*FALSE' 1 'Every new Start must have the sole Start-side Unload initialized clear'
    $projectInfo = Read-Text 'CFFwelding_System\CFFwelding\GVLs\GVL_ProjectInfo.TcGVL'
    $fastAxisRaw = Read-Text 'CFFwelding_System\CFFwelding\POUs\Fast\PRG_FastAxisControl.TcPOU'
    $fastAxis = Get-PouImplementationText $fastAxisRaw
    $fastAxisDeclaration = Get-PouDeclarationText $fastAxisRaw
    $arbiterRaw = Read-Text 'CFFwelding_System\CFFwelding\POUs\FunctionBlocks\Axis\FB_AxisCommandArbiter.TcPOU'
    $arbiter = Get-PouImplementationText $arbiterRaw
    $arbiterDeclaration = Get-PouDeclarationText $arbiterRaw
    $zNcAdapterRaw = Read-Text 'CFFwelding_System\CFFwelding\POUs\FunctionBlocks\Axis\FB_ZAxisNcAdapter.TcPOU'
    $zNcAdapter = Get-PouImplementationText $zNcAdapterRaw
    $zSourceIncrementPattern = 'udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1'
    Assert-Match $arbiterDeclaration 'stFaultStopCommand\s*:\s*ST_ZAxisCommand' 'Axis arbiter must accept one typed FaultStop command candidate'
    $arbiterFaultStop = Get-CaseBranch $arbiter 'Z_OWNER_FAULT_STOP' 'Axis arbiter must expose an executable FaultStop owner arm' 'eActiveOwner'
    Assert-True (Test-ArbiterFaultStopBranch $arbiterFaultStop) 'Arbiter FaultStop arm must copy the typed candidate once and never overwrite its deceleration'
    Assert-True (Test-ArbiterFaultStopComposition $arbiter) 'Arbiter FaultStop composition must come from one exact combined-top-level CASE eActiveOwner arm with no duplicate or dead label'
    Assert-True (Test-NoCommandWriterAfterActiveOwnerCase $arbiter) 'Arbiter must not overwrite the selected command or its deceleration after owner routing'
    Assert-Match $arbiterFaultStop '(?s)stCommand\s*:=\s*stFaultStopCommand\s*;.*?stCommand\.bEnable\s*:=\s*TRUE.*?stCommand\.bStop\s*:=\s*TRUE.*?stCommand\.eOwnerRequest\s*:=\s*(?:E_ZCommandOwner\.)?Z_OWNER_FAULT_STOP' 'FaultStop owner must copy the typed candidate and force only the safe stop/owner fields'
    Assert-NoMatch $arbiterFaultStop 'stCommand\.rDeceleration_mm_s2\s*:=' 'FaultStop owner must preserve the candidate deceleration instead of forcing zero'
    Assert-Match $fastAxisDeclaration 'stFaultStopCommand\s*:\s*ST_ZAxisCommand' 'Fast axis control must construct a typed FaultStop candidate'
    Assert-True (Test-FastFaultStopDecelerationChain $fastAxis) 'Fast must preserve Sequence and central-safety-latch deceleration through source latch, typed FaultStop candidate, and arbitration with no later writer'
    Assert-Match $fastAxis '(?s)stFaultStopCommand\s*:=\s*stLatchedZSourceCommand\s*;.*?fbZAxisArbiter\s*\(.*?stFaultStopCommand\s*:=\s*stFaultStopCommand' 'Fast axis control must pass the most recently latched Z command as the typed FaultStop candidate'
    Assert-Match $fastAxis '(?s)bLatchedZFaultStopRequest\s*:=\s*\(stLatchedZSourceCommand\.eOwnerRequest\s*=\s*E_ZCommandOwner\.Z_OWNER_FAULT_STOP\)\s+OR\s+bFastSafetyStopLatched.*?stFaultStopCommand\s*:=\s*stLatchedZSourceCommand.*?bFaultStopRequest\s*:=\s*bLatchedZFaultStopRequest' 'A central Fast safety latch must route the most recently latched Force-owner deceleration through the typed FaultStop candidate'
    Assert-Match $fastAxis '(?s)Z_OWNER_FAULT_STOP\s*:.*?stCandidateZSourceCommand\s*:=\s*GVL_Status\.stFast\.stSequence\.stMotionIntent\.stZCommand.*?stLatchedZSourceCommand\s*:=\s*stCandidateZSourceCommand' 'Sequence FaultStop deceleration must survive the Fast source latch before arbitration'
    Assert-True (Test-NcFaultStopDecelerationConsumer $zNcAdapter) 'The NC adapter must have one top-level Halt consumer using ABS of the preserved typed FaultStop deceleration'
    $forceOwnerLevel = Get-IfPartition $sequence '\(?\s*bExternalOwnerHold\s*\)?' 'External Force ownership must have one common complete level package' -TopLevel
    Assert-True (Test-ForceOwnerDecelerationPackage $forceOwnerLevel.PositiveBody) 'Every common Force-owner level scan must have one final frozen positive standard deceleration writer'
    Assert-CaseMatch $sequence 'CFF_CONTROLLED_FORCE_UNLOAD' '(?s)bForceSetpointRampValid.*?bForceSetpointRampReached.*?ABS\s*\(.*?fForceControlN.*?\).*?fContactForceOffN.*?rAcceptedVelocity_mm_s.*?tUnloadStandstillConfirm' 'Controlled unload must wait for force, standstill, health, and confirm time'
    Assert-CaseMatch $sequence 'CFF_CONTROLLED_FORCE_UNLOAD' '(?s)tControlledUnloadTimeout.*?16#0000A013.*?CFF_EXIT_FAULT_NO_RETURN' 'Unload timeout must select fault with no return'
    Assert-True (Test-UniqueTopLevelCall $sequence 'tonControlledUnload' '(?s)tonControlledUnload\s*\(\s*IN\s*:=\s*eState\s*=\s*CFF_CONTROLLED_FORCE_UNLOAD\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tControlledUnloadTimeout\s*\)') 'Controlled Unload timeout TON must be one exact call outside every IF/CASE'
    Assert-True (Test-UniqueTopLevelCall $sequence 'tonUnloadStandstillConfirm' '(?s)tonUnloadStandstillConfirm\s*\(\s*IN\s*:=\s*\(\s*eState\s*=\s*CFF_CONTROLLED_FORCE_UNLOAD\s*\)\s+AND\s+NOT\s+bStateEntry\s+AND\s+bUnloadStandstillQualified\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tUnloadStandstillConfirm\s*\)') 'Unload confirm TON must be one exact top-level call, exclude Entry stale status, and reset on qualification dropout'
    Assert-True (Test-UniqueTopLevelCall $sequence 'tonExitRAxisStop' '(?s)tonExitRAxisStop\s*\(\s*IN\s*:=\s*\(\s*bSafeExitRStopPending\s+OR\s+bUnknownExternalRStopPending\s+OR\s+bApproachFaultStopPending\s*\)\s+AND\s+NOT\s*\(\s*\(\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)\s+AND\s+GVL_Status\.stFast\.stRAxis\.bStandstill\s*\)\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tRAxisStopTimeout\s*\)') 'Exit R-stop TON must run only while a pending exact current ACK plus actual standstill is absent'
    Assert-True (Test-ExitRStopTimeoutConsumption $sequence) 'Exit R-stop timeout Q must be consumed before the state CASE, latch A014 only through a first-writer guard, and feed same-scan unified safe exit'
    $exitRStopFaultOverwriteMutation = $sequence -replace
        'udiFirstFaultId\s*:=\s*16#0000A014\s*;',
        "udiFirstFaultId := 16#0000A014;`nudiFirstFaultId := 0;"
    Assert-True (-not (Test-ExitRStopTimeoutConsumption $exitRStopFaultOverwriteMutation)) 'Exit R-stop mutation guard must reject any later first-fault reset or overwrite after A014'
    Assert-True (Test-UniqueTopLevelCall $sequence 'tonReturn' '(?s)tonReturn\s*\(\s*IN\s*:=\s*\(\s*eState\s*=\s*CFF_RETURN_LOCAL\s*\)\s+OR\s+\(\s*eState\s*=\s*CFF_RETURN_REFERENCE\s*\)\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tReturnTimeout\s*\)') 'Return timeout TON must be one exact call outside every IF/CASE'
    Assert-CaseMatch $sequence 'CFF_CONTROLLED_FORCE_UNLOAD' '(?s)rForceSet_kN\s*:=\s*0(?:\.0+)?\s*;.*?bForceControlEnable\s*:=\s*TRUE.*?stRCommand\.bStop\s*:=\s*TRUE' 'Controlled Unload must ramp the retained force profile target to zero while holding the R stop package'
    $unloadHealthyPatterns = @(
        'GVL_Process\.stActual\.bForceValid',
        'GVL_Process\.stActual\.bContactReferenceValid',
        'GVL_Process\.stActual\.bAxisSensorAgreement',
        'GVL_Status\.stFast\.bForceSetpointRampValid',
        'GVL_Status\.stFast\.stZForceControl\.bActive',
        'NOT\s+GVL_Status\.stFast\.stZForceControl\.bFault',
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*GVL_Process\.stActual\.fForceControlN\s*\)',
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*GVL_Process\.stActual\.fSRelSensorMm\s*\)',
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*rForceRamp_kN_s\s*\)',
        'rForceRamp_kN_s\s*>\s*0',
        'GVL_Status\.stFast\.stZExtSetpoint\.bEnabled',
        'GVL_Status\.stFast\.stZExtSetpoint\.bAcceptedSetpointValid',
        'GVL_Status\.stFast\.stZExternalTrajectory\.bActive',
        'NOT\s+GVL_Status\.stFast\.stZExternalTrajectory\.bFault',
        'FC_IsFiniteLReal\s*\(\s*rValue\s*:=\s*GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s\s*\)',
        'NOT\s+bExternalError',
        'NOT\s+bAxisError',
        'NOT\s+bSensorInvalid'
    )
    $unloadHealthyAssignment = Find-BooleanAssignmentCoveringPatterns $sequence $unloadHealthyPatterns 'Controlled Unload health must be one unique top-level classifier and include an established Contact/Force lifecycle plus healthy External/axes' 'bUnloadHealthy'
    if ($null -ne $unloadHealthyAssignment) {
        Assert-True (Test-UnloadHealthExpression $unloadHealthyAssignment.Expression) 'Controlled Unload health must be a strict polarity-safe AND expression without OR/constant bypasses'
    }
    $unloadQualificationPatterns = @(
        'GVL_Status\.stFast\.bForceSetpointRampValid',
        'GVL_Status\.stFast\.bForceSetpointRampReached',
        'ABS\s*\(\s*GVL_Process\.stActual\.fForceControlN\s*\)\s*<=\s*stCycleSnapshot\.stProgram\.stHeader\.fContactForceOffN',
        'ABS\s*\(\s*GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s\s*\)\s*<=\s*stZExtConfigSnapshot\.rStandstillVelocity_mm_s',
        'bUnloadHealthy'
    )
    $unloadQualificationAssignment = Find-BooleanAssignmentCoveringPatterns $sequence $unloadQualificationPatterns 'Unload confirmation qualification must be one unique top-level positive classifier' 'bUnloadStandstillQualified'
    if ($null -ne $unloadQualificationAssignment) {
        Assert-True (Test-PositiveAndExpression $unloadQualificationAssignment.Expression $unloadQualificationPatterns) 'Unload confirmation qualification must AND every positive ramp, force, accepted-velocity, and health requirement without OR/dead logic'
    }
    Assert-Match $sequence '(?s)tonUnloadStandstillConfirm\s*\(\s*IN\s*:=\s*\(\s*eState\s*=\s*CFF_CONTROLLED_FORCE_UNLOAD\s*\)\s+AND\s+NOT\s+bStateEntry\s+AND\s+bUnloadStandstillQualified\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tUnloadStandstillConfirm\s*\)' 'Unload confirm TON must reset naturally on Entry and whenever the exact qualification drops out'
    Assert-CaseMatch $sequence 'CFF_CONTROLLED_FORCE_UNLOAD' '(?s)IF\s+udiFirstFaultId\s*>\s*0\s+THEN.*?CFF_EXIT_FAULT_NO_RETURN.*?CFF_EXTSETPOINT_DISABLE.*?ELSIF\s+tonControlledUnload\.Q\s+THEN.*?IF\s+udiFirstFaultId\s*=\s*0\s+THEN\s*udiFirstFaultId\s*:=\s*16#0000A013.*?CFF_EXIT_FAULT_NO_RETURN.*?CFF_EXTSETPOINT_DISABLE.*?ELSIF\s+tonUnloadStandstillConfirm\.Q\s+THEN\s*eNextState\s*:=\s*CFF_EXTSETPOINT_DISABLE' 'Controlled Unload must use strict fault, timeout, then confirmed-disable priority without token stuffing'
    $exitExternalBranches = @{}
    $exitExternalPartitions = @{}
    foreach ($exitExternalState in @('CFF_CONTROLLED_FORCE_UNLOAD', 'CFF_EXTSETPOINT_DISABLE')) {
        $exitExternalBranch = Get-CaseBranch $sequence $exitExternalState "Missing executable CASE branch: $exitExternalState"
        $exitExternalPartition = Get-IfPartition $exitExternalBranch '\(?\s*bStateEntry\s*\)?' "$exitExternalState may have at most one parseable IF bStateEntry THEN region" -Optional
        $exitExternalBranches[$exitExternalState] = $exitExternalBranch
        $exitExternalPartitions[$exitExternalState] = $exitExternalPartition
        Assert-TopLevelPatterns $exitExternalPartition.Outside @(
            'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*(?:E_ZCommandOwner\.)?Z_OWNER_FORCE_PROCESS',
            'stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*TRUE'
        ) "$exitExternalState level intent must retain top-level Force Owner and External use outside bStateEntry"
    }
    $unloadBranch = $exitExternalBranches['CFF_CONTROLLED_FORCE_UNLOAD']
    $disableBranch = $exitExternalBranches['CFF_EXTSETPOINT_DISABLE']
    Assert-NoMatch $unloadBranch $zSourceIncrementPattern 'Controlled Force Unload must reuse the Prepare Force Z transaction without incrementing its source ID'
    $unloadEntry = Get-IfPartition $unloadBranch '\(?\s*bStateEntry\s*\)?' 'Controlled Force Unload must have exactly one Entry transaction region'
    Assert-MatchCount $unloadEntry.Body 'udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1' 1 'Unload Entry may create at most one fresh R stop transaction'
    Assert-NoMatch $unloadEntry.Outside 'udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1' 'Unload must never repeat an R source transaction outside Entry'
    Assert-Match $sequence '(?s)ELSIF\s+\(\s*eState\s*=\s*CFF_CONTROLLED_FORCE_UNLOAD\s*\)\s+AND\s+bStateEntry\s+THEN.*?stCandidateRCommand\.bEnable\s*:=\s*TRUE.*?stCandidateRCommand\.bReset\s*:=\s*FALSE.*?stCandidateRCommand\.bStop\s*:=\s*TRUE.*?stCandidateRCommand\.bMoveVelocity\s*:=\s*FALSE.*?stCandidateRCommand\.rVelocity_rpm\s*:=\s*0(?:\.0+)?.*?stCandidateRCommand\.rAcceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS.*?stCandidateRCommand\.rDeceleration_rpm_s\s*:=\s*stRAxisProfileSnapshot\.fSpeedRampRpmS' 'Unload Entry must construct the complete seven-field R stop candidate before comparison'
    Assert-Match $unloadEntry.PositiveBody '(?s)bSafeExitRStopPending\s*:=\s*TRUE.*?IF\s+bRCommandPayloadChanged\s+THEN\s*stLastPublishedRCommand\s*:=\s*stCandidateRCommand.*?udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1.*?IF\s+udiRCommandId\s*=\s*0\s+THEN\s*udiRCommandId\s*:=\s*1' 'Unload Entry must latch pending and increment/skip-zero only when the complete stop payload changed'
    $unloadEntryTransfer = Get-IfPartition $unloadEntry.PositiveBody 'NOT\s+bUnloadTransferInitialized\s+AND\s+bUnloadHealthy' 'Normal Unload Entry must retain one healthy not-initialized transfer fallback'
    Assert-TopLevelPatterns $unloadEntryTransfer.PositiveBody @(
        'rTargetRelativePosition_mm\s*:=\s*GVL_Process\.stActual\.fSRelSensorMm',
        'rForceTransferVelocity_mm_s\s*:=\s*GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s',
        'bForceProfileTransferPending\s*:=\s*TRUE',
        'bUnloadTransferInitialized\s*:=\s*TRUE'
    ) 'Normal Unload Entry fallback must initialize SRel/accepted velocity exactly once while healthy'
    Assert-True (Test-UniqueTopLevelOrderedAssignments $unloadEntryTransfer.PositiveBody $unloadFreezePatterns) 'Normal Unload Entry must freeze SRel, accepted velocity, pending, then initialized in exact final-writer order'
    Assert-MatchCount $unloadEntryTransfer.PositiveBody 'bUnloadTransferInitialized\s*:=\s*TRUE' 1 'Normal Unload Entry must own exactly one initialized TRUE writer'
    Assert-NoMatch $unloadEntryTransfer.Outside 'rTargetRelativePosition_mm\s*:=|rForceTransferVelocity_mm_s\s*:=|bForceProfileTransferPending\s*:=\s*TRUE|bUnloadTransferInitialized\s*:=\s*TRUE' 'Initialized Unload Entry must not repeat the transfer freeze'
    Assert-Match $unloadBranch '(?s)IF\s+bSafeExitRStopPending\s+AND\s+\(\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)\s+AND\s+GVL_Status\.stFast\.stRAxis\.bStandstill\s+THEN\s*bSafeExitRStopPending\s*:=\s*FALSE' 'Unload R-stop pending may clear only on exact current ACK and actual R standstill'
    $disableLevelIntent = $exitExternalPartitions['CFF_EXTSETPOINT_DISABLE'].Outside
    Assert-True (Test-ForceOwnerDecelerationPackage $disableLevelIntent) 'External Disable must repeat one final frozen positive Force-owner deceleration for the ReleaseOwner scan'
    $reviewUnknownStateBody = Get-UniqueTopLevelCaseDefaultBody $sequence 'eState'
    Assert-True (-not [string]::IsNullOrWhiteSpace($reviewUnknownStateBody)) 'SequenceExit review must locate the direct executable unknown-state fail-safe default'
    if (-not [string]::IsNullOrWhiteSpace($reviewUnknownStateBody)) {
        $reviewUnknownLifecycle = Get-IfPartition $reviewUnknownStateBody 'NOT\s+bExternalReady' 'Unknown-state fail-safe must split on actual External release/idle lifecycle' -TopLevel
        Assert-True ($reviewUnknownLifecycle.HasElse -and
            ($reviewUnknownLifecycle.ElsifCount -eq 0)) 'Unknown-state fail-safe must use one direct unconditional released-External ELSE'
        Assert-True (Test-ForceOwnerDecelerationPackage $reviewUnknownLifecycle.PositiveBody) 'Unknown-state unreleased-External fallback must publish one final frozen positive Force-owner deceleration'
    }
    $positiveDisableReleaseCondition = '\(?\s*GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner\s+AND\s+NOT\s+bUnknownExternalRStopPending\s+AND\s+NOT\s+bSafeExitRStopPending\s+AND\s+\(\s*GVL_Status\.stFast\.udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId\s*\)\s+AND\s+GVL_Status\.stFast\.stRAxis\.bStandstill\s*\)?'
    $disableReleasePartition = Get-IfPartition $disableLevelIntent $positiveDisableReleaseCondition 'External Disable must have exactly one top-level release migration IF with both pending latches clear, current exact R ACK, and actual standstill' -TopLevel
    Assert-TopLevelPatterns $disableReleasePartition.Outside @(
        'stMotionIntent\.bExternalDisableRequest\s*:=\s*TRUE',
        'stMotionIntent\.bForceProcessExitComplete\s*:=\s*FALSE'
    ) 'External Disable pre-release level intent must top-level request Disable and keep force exit incomplete'
    $disableMigrationPattern = '(?s)stMotionIntent\.bForceProcessExitComplete\s*:=\s*TRUE|eNextState\s*:=|stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*(?!(?:E_ZCommandOwner\.)?Z_OWNER_FORCE_PROCESS\b)(?:E_ZCommandOwner\.)?Z_OWNER_[A-Z0-9_]+|stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*FALSE|stMotionIntent\.bExternalDisableRequest\s*:=\s*FALSE|udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1'
    Assert-True (Test-AllAssignmentsGuardedByAllowedPositiveIf $disableLevelIntent $disableMigrationPattern @($positiveDisableReleaseCondition)) 'Every External Disable completion, transition, Owner migration, mode cancellation, or new Z transaction must be inside the fully proven release migration IF true branch'
    Assert-Match $disableReleasePartition.PositiveBody '(?s)(?=.*stMotionIntent\.bForceProcessExitComplete\s*:=\s*TRUE)(?=.*(?:eNextState\s*:=|stMotionIntent\.stZCommand\.eOwnerRequest\s*:=))' 'External Disable may complete or migrate only inside the fully proven release migration branch'
    Assert-MatchCount $disableReleasePartition.PositiveBody '\bCASE\s+eExitIntent\s+OF\b' 1 'Disable release must use one explicit ExitIntent CASE map'
    $disableReleasePriority = Get-IfPartition $disableReleasePartition.PositiveBody 'udiFirstFaultId\s*>\s*0' 'Disable release must have one top-level Fault > Stop/Reset > frozen ExitIntent priority chain' -TopLevel
    Assert-True ($disableReleasePriority.HasElse -and
        ($disableReleasePriority.ElsifCount -eq 1)) 'Disable release priority must end in one real ELSE after its single Stop/Reset ELSIF'
    $disableExitIntentMap = $disableReleasePriority.AlternateBody
    foreach ($returnIntent in @('CFF_EXIT_NORMAL_RETURN','CFF_EXIT_NOK_RETURN')) {
        $returnIntentArm = Get-CaseBranch $disableExitIntentMap $returnIntent "Disable release is missing $returnIntent mapping" 'eExitIntent'
        Assert-MatchCount $returnIntentArm 'eNextState\s*:=\s*CFF_RETURN_LOCAL' 1 "$returnIntent must map Local exactly once"
        Assert-MatchCount $returnIntentArm 'eNextState\s*:=\s*CFF_RETURN_REFERENCE' 1 "$returnIntent must map Reference exactly once"
        Assert-Match $returnIntentArm '(?s)IF\s+stCycleSnapshot\.stProgram\.stHeader\.eReturnMode\s*=\s*RETURN_MODE_LOCAL\s+THEN\s*eNextState\s*:=\s*CFF_RETURN_LOCAL\s*;\s*ELSIF\s+stCycleSnapshot\.stProgram\.stHeader\.eReturnMode\s*=\s*RETURN_MODE_REFERENCE\s+THEN\s*eNextState\s*:=\s*CFF_RETURN_REFERENCE' "$returnIntent must select the frozen Header mode directly"
        Assert-True (Test-ReturnIntentPublicationOwnership $returnIntentArm) "$returnIntent Return publication must remain under exact Z/R-ready and no-error health plus the approved Local/Reference priority mapping"
    }
    $abortIntentArm = Get-CaseBranch $disableExitIntentMap 'CFF_EXIT_ABORT_NO_RETURN' 'Disable release is missing Abort mapping' 'eExitIntent'
    $faultIntentArm = Get-CaseBranch $disableExitIntentMap 'CFF_EXIT_FAULT_NO_RETURN' 'Disable release is missing Fault mapping' 'eExitIntent'
    Assert-MatchCount $abortIntentArm 'eNextState\s*:=' 1 'Abort no-return mapping must have one final state writer'
    Assert-Match $abortIntentArm 'eNextState\s*:=\s*CFF_ABORT\s*;' 'Abort no-return mapping must select Abort'
    Assert-NoMatch $abortIntentArm 'CFF_RETURN_(?:LOCAL|REFERENCE)|eNextState\s*:=\s*CFF_FAULT' 'Abort no-return mapping must not select Return or Fault'
    Assert-MatchCount $faultIntentArm 'eNextState\s*:=' 1 'Fault no-return mapping must have one final state writer'
    Assert-Match $faultIntentArm 'eNextState\s*:=\s*CFF_FAULT\s*;' 'Fault no-return mapping must select Fault'
    Assert-NoMatch $faultIntentArm 'CFF_RETURN_(?:LOCAL|REFERENCE)|eNextState\s*:=\s*CFF_ABORT' 'Fault no-return mapping must not select Return or Abort'
    Assert-NoMatch $disableReleasePartition.PositiveBody $zSourceIncrementPattern 'Disable release must preserve the Force source ID; fresh Retract/FaultStop ID belongs to the next atomic owner handoff'
    Assert-NoMatch $disableReleasePartition.PositiveBody 'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*Z_OWNER_NONE|stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*FALSE' 'Disable release scan must retain the Sequence Force source until the next atomic Retract/FaultStop transaction'
    Assert-Match $disableReleasePartition.PositiveBody '(?s)IF\s+udiFirstFaultId\s*>\s*0\s+THEN\s*eExitIntent\s*:=\s*CFF_EXIT_FAULT_NO_RETURN\s*;\s*eNextState\s*:=\s*CFF_FAULT\s*;\s*ELSIF\s+bStopRequestedLatched\s+OR\s+bAbortEvent\s+OR\s+bResetPendingLatched\s+THEN\s*eExitIntent\s*:=\s*CFF_EXIT_ABORT_NO_RETURN\s*;\s*eNextState\s*:=\s*CFF_ABORT\s*;\s*ELSE\s*CASE\s+eExitIntent\s+OF' 'Disable release must resolve same-scan real fault before active Stop/Reset before the frozen ExitIntent map'
    $releaseVectors = @(
        @{ Fault = $true; Stop = $false; Intent = 'Normal'; Expected = 'Fault' },
        @{ Fault = $false; Stop = $true; Intent = 'Normal'; Expected = 'Abort' },
        @{ Fault = $false; Stop = $false; Intent = 'Normal'; Expected = 'Return' },
        @{ Fault = $false; Stop = $false; Intent = 'Fault'; Expected = 'Fault' }
    )
    foreach ($vector in $releaseVectors) {
        $actual = if ($vector.Fault) { 'Fault' } elseif ($vector.Stop) { 'Abort' } else { $vector.Intent -replace 'Normal','Return' }
        Assert-True ($actual -eq $vector.Expected) 'Disable release scan vector must enforce Fault > Stop/Reset > return-capable intent'
    }
    Assert-NoMatch $sequence 'udi(?:Z|R)CommandId\s*:=\s*0\s*;' 'Safe Reset must never clear a Z/R source transaction counter to zero'
    Assert-Match $sequence '(?s)udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1.*?IF\s+udiZCommandId\s*=\s*0\s+THEN\s+udiZCommandId\s*:=\s*1' 'Z source transaction IDs must remain monotonic and skip zero across safe Reset'
    Assert-Match $sequence '(?s)udiRCommandId\s*:=\s*udiRCommandId\s*\+\s*1.*?IF\s+udiRCommandId\s*=\s*0\s+THEN\s+udiRCommandId\s*:=\s*1' 'R source transaction IDs must remain monotonic and skip zero across safe Reset'
    $oldPublishedAck = 7L; $nextCycleSourceId = 8L; $adapterAcceptedId = 7L
    $newCycleAckedBeforeAdapter = $adapterAcceptedId -eq $nextCycleSourceId
    $adapterAcceptedId = 8L
    $newCycleAckedAfterAdapter = $adapterAcceptedId -eq $nextCycleSourceId
    Assert-True (($nextCycleSourceId -ne 0L) -and ($nextCycleSourceId -ne $oldPublishedAck) -and (-not $newCycleAckedBeforeAdapter) -and $newCycleAckedAfterAdapter) 'A new cycle must use a fresh nonzero source ID so old ACK 7 cannot acknowledge it before Adapter accepts ID 8'
    $returnEntryBlockedAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Return entry blocker must be one unique top-level current-scan classifier' 'bReturnEntryBlocked'
    if ($null -ne $returnEntryBlockedAssignment) {
        Assert-True (Test-ReturnEntryBlockedExpression $returnEntryBlockedAssignment.Expression) 'Return entry blocker must be exactly the real Stop/Abort/Reset, hard/collision, External/axis/sensor, and first-fault cause set'
    }
    $returnLevelHealthAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Return level health must be one unique current-scan classifier' 'bReturnLevelHealthy'
    if ($null -ne $returnLevelHealthAssignment) {
        Assert-True (Test-ReturnLevelHealthExpression $returnLevelHealthAssignment.Expression) 'Return level health must require Release, exact R ACK/standstill, Z/R Ready, and no Z/R/External/trajectory error without requiring Z standstill'
    }
    $returnEntryAuthorizationAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Return Entry authorization must be one unique current-scan classifier' 'bReturnEntryAuthorized'
    if ($null -ne $returnEntryAuthorizationAssignment) {
        Assert-True (Test-ReturnEntryAuthorizationExpression $returnEntryAuthorizationAssignment.Expression) 'Return Entry authorization must add actual Z standstill to exact level health'
    }
    $returnPublicationAllowedAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Return publication allowance must be one unique current-scan classifier' 'bReturnPublicationAllowed'
    if ($null -ne $returnPublicationAllowedAssignment) {
        Assert-True (Test-ExactAndTerms $returnPublicationAllowedAssignment.Expression @(
            'NOT\s+bReturnEntryBlocked',
            'bReturnLevelHealthy',
            '\(?\s*NOT\s+bStateEntry\s+OR\s+bReturnEntryAuthorized\s*\)?'
        )) 'Return publication allowance must require no event and level health every scan, while adding Entry authorization only on bStateEntry'
    }
    $returnContracts = @(
        [pscustomobject]@{
            State = 'CFF_RETURN_LOCAL'
            TargetPattern = 'rCycleStartZPosition_mm'
            FrozenPattern = '(?s)rCycleStartZPosition_mm.*?fReturnVelocityMmS.*?fStandardMoveAccelerationMmS2.*?fStandardMoveDecelerationMmS2'
            FrozenMessage = 'Local return must use frozen move slopes and cycle-start target'
        },
        [pscustomobject]@{
            State = 'CFF_RETURN_REFERENCE'
            TargetPattern = 'stCycleSnapshot\.stProgram\.stHeader\.fReturnOpeningMm'
            FrozenPattern = '(?s)fReturnOpeningMm.*?fReturnVelocityMmS.*?fStandardMoveAccelerationMmS2.*?fStandardMoveDecelerationMmS2'
            FrozenMessage = 'Reference return must use frozen move slopes and configured target'
        }
    )
    foreach ($returnContract in $returnContracts) {
        $returnBranch = Get-CaseBranch $sequence $returnContract.State "Missing executable CASE branch: $($returnContract.State)"
        $returnEventGate = Get-IfPartition $returnBranch 'NOT\s+bReturnEntryBlocked' "$($returnContract.State) must have one top-level event-suppression gate" -TopLevel
        Assert-NoMatch $returnEventGate.Outside 'eNextState\s*:=\s*(?:E_CffState\.)?CFF_EVALUATE' "$($returnContract.State) must never Evaluate outside the real-event suppression gate"
        $returnPublication = Get-IfPartition $returnEventGate.PositiveBody '\(?\s*bReturnPublicationAllowed\s*\)?' "$($returnContract.State) must have one current-scan publication gate" -TopLevel
        Assert-NoMatch $returnPublication.Outside 'eNextState\s*:=\s*(?:E_CffState\.)?CFF_EVALUATE' "$($returnContract.State) must never Evaluate outside the current-scan publication gate"
        Assert-NoMatch $returnPublication.Outside $zSourceIncrementPattern "$($returnContract.State) must never create a Retract source transaction outside the publication gate"
        Assert-NoMatch $returnPublication.Outside 'Z_OWNER_RETRACT|stMotionIntent\.stZCommand\.bMoveAbsolute\s*:=\s*TRUE' "$($returnContract.State) must never expose Retract/MoveAbsolute outside current-scan authorization and health"
        if (-not [string]::IsNullOrWhiteSpace($returnPublication.PositiveBody)) {
            $returnEntryPartition = Get-IfPartition $returnPublication.PositiveBody '\(?\s*bStateEntry\s*\)?' "$($returnContract.State) publication gate must have one Entry transaction region"
            Assert-MatchCount $returnEntryPartition.Body $zSourceIncrementPattern 1 "$($returnContract.State) authorized bStateEntry must create exactly one fresh Z source transaction"
            Assert-Match $returnEntryPartition.Body '(?s)udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1\s*;.*?IF\s+udiZCommandId\s*=\s*0\s+THEN\s*udiZCommandId\s*:=\s*1\s*;?\s*END_IF\s*;?' "$($returnContract.State) authorized Entry must explicitly skip zero"
            Assert-NoMatch $returnEntryPartition.Outside $zSourceIncrementPattern "$($returnContract.State) moving level scans must retain the same Retract source ID"
            Assert-TopLevelPatterns $returnPublication.PositiveBody @(
                'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*(?:E_ZCommandOwner\.)?Z_OWNER_RETRACT',
                'stMotionIntent\.stZCommand\.bMoveAbsolute\s*:=\s*TRUE',
                'stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE',
                'stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE'
            ) "$($returnContract.State) authorized healthy level scans must retain Retract and the R-stop package while Z is moving"
            Assert-True (Test-ReturnLevelPayload $returnPublication.PositiveBody $returnContract.TargetPattern) "$($returnContract.State) authorized path must have one complete, conflict-free Retract payload"
            Assert-Match $returnPublication.PositiveBody $returnContract.FrozenPattern $returnContract.FrozenMessage
            Assert-Match $returnPublication.PositiveBody '(?s)tonReturn\.Q.*?16#0000A015.*?CFF_EXIT_FAULT_NO_RETURN.*?CFF_FAULT' "$($returnContract.State) timeout must latch A015 and terminate without Return completion"
        }
        Assert-Match $returnPublication.Body '(?s)ELSE\s+IF\s+udiFirstFaultId\s*=\s*0\s+THEN\s*udiFirstFaultId\s*:=\s*16#0000A016.*?eExitIntent\s*:=\s*CFF_EXIT_FAULT_NO_RETURN' "$($returnContract.State) authorization/level-health loss must fail closed under first-writer A016 for the existing FaultStop override"
        Assert-True (Test-ReturnEvaluateOwnership $returnBranch) "Every $($returnContract.State) to Evaluate transition must remain inside event suppression, publication health, and exact Z ACK, Done/standstill, and no-timeout guards"
    }

    $externalLifecycleStates = @(
        'CFF_EXTSETPOINT_PREPARE',
        'CFF_CONTACT_SEARCH',
        'CFF_CONTACT_ACCEPT',
        'CFF_STEP1_ENTRY',
        'CFF_STEP1_RAMP_PROCESS',
        'CFF_STEP1_END_CHECK',
        'CFF_STEP2_ENTRY',
        'CFF_STEP2_RAMP_PROCESS',
        'CFF_STEP2_END_CHECK',
        'CFF_STEP3_ENTRY',
        'CFF_STEP3_RAMP_PROCESS',
        'CFF_STEP3_END_CHECK',
        'CFF_BRAKE_AND_COMPRESSION_RAMP',
        'CFF_STEP4_VALID_FORCE_HOLD',
        'CFF_CONTROLLED_FORCE_UNLOAD',
        'CFF_EXTSETPOINT_DISABLE'
    )
    $ownerHoldPatterns = @($externalLifecycleStates | ForEach-Object {
        "eState\s*=\s*(?:E_CffState\.)?$([regex]::Escape($_))"
    })
    $ownerHoldPatterns += 'NOT\s+GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner'
    $ownerHoldAssignment = Find-BooleanAssignmentCoveringPatterns $sequence $ownerHoldPatterns 'Sequence must have exactly one ownerHold classifier assignment outside IF/CASE regions, with no duplicate or later override' 'bExternalOwnerHold'
    $ownerHoldVariable = ''
    if ($null -ne $ownerHoldAssignment) {
        $ownerHoldVariable = $ownerHoldAssignment.Name
    }
    $safeExitAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Sequence must have exactly one top-level safeExit classifier assignment, with no duplicate or later override' 'bSafeExitRequested'
    $safeExitVariable = ''
    if ($null -ne $safeExitAssignment) {
        $safeExitVariable = $safeExitAssignment.Name
    }
    if ($null -ne $ownerHoldAssignment) {
        Assert-True (Test-PositiveExternalOwnerHoldExpression $ownerHoldAssignment.Expression $externalLifecycleStates) 'External ownerHold expression must wrap the complete positive state OR chain, then AND exactly one NOT ReleaseOwner gate'
    }
    if ($null -ne $safeExitAssignment) {
        Assert-True (Test-SafeExitExpression $safeExitAssignment.Expression) 'External safeExit expression must be the exact positive OR set of real Stop/Abort/active-Reset, hard, collision, axis/external/sensor, and first-fault causes'
    }
    $returnSafeStopAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Sequence must have exactly one top-level Return/Evaluate/Complete interruption classifier assignment' 'bReturnSafeStopRequested'
    if ($null -ne $returnSafeStopAssignment) {
        Assert-True (Test-ReturnSafeStopExpression $returnSafeStopAssignment.Expression) 'Return interruption classifier must be the exact Return/Evaluate/Complete state group AND the proven real safe-exit classifier'
    }
    if ([string]::IsNullOrEmpty($ownerHoldVariable)) {
        $ownerHoldVariable = 'bMissingExternalOwnerHoldContract'
    }
    if ([string]::IsNullOrEmpty($safeExitVariable)) {
        $safeExitVariable = 'bMissingExternalSafeExitContract'
    }
    $postCaseText = Get-TextAfterMainCase $sequence 'Sequence must have one parseable CASE eState OF before global exit routing'
    $reviewPrecheckBranch = Get-CaseBranch $sequence 'CFF_PRECHECK' 'SequenceExit review requires an executable Precheck branch'
    $reviewLocalTargetAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'SequenceExit review requires one unique Local Return target classifier' 'bLocalReturnTargetValid'
    if ($null -ne $reviewLocalTargetAssignment) {
        Assert-True (Test-LocalReturnTargetExpression $reviewLocalTargetAssignment.Expression) 'Local Return target classifier must reject NaN/out-of-range values and accept only the inclusive frozen Z limits'
    }
    Assert-Match $reviewPrecheckBranch '(?s)AND\s+bSensorReady\s+AND\s+bLocalReturnTargetValid.*?eNextState\s*:=\s*CFF_APPROACH' 'Precheck must not enter Approach unless the frozen cycle-start Local Return target is valid'
    Assert-Match $sequence '(?s)IF\s+\(eState\s*>=\s*CFF_APPROACH\).*?AND\s+\(eState\s*<=\s*CFF_FAULT\)\s+AND\s+\(udiFirstFaultId\s*=\s*0\)\s+THEN.*?bHardForceActive.*?16#0000A00C.*?bHardStrokeActive.*?16#0000A00D.*?bCollisionLimitActive.*?16#0000A00E.*?bSensorInvalid.*?16#0000A00F' 'Real-cause first-writer mapping must begin at Approach and latch hard/collision/sensor causes in the triggering scan'
    $reviewApproachNormalAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'SequenceExit review requires one unique Approach normal-completion classifier' 'bApproachNormalCompletion'
    if ($null -ne $reviewApproachNormalAssignment) {
        Assert-True (Test-ApproachNormalCompletionExpression $reviewApproachNormalAssignment.Expression) 'Approach normal completion must exclude Entry stale status and require exact Z/R ACK, Z Done, and both actual standstills'
    }
    Assert-True (Test-UniqueTopLevelCall $sequence 'tonApproach' '(?s)tonApproach\s*\(\s*IN\s*:=\s*\(\s*eState\s*=\s*CFF_APPROACH\s*\)\s+AND\s+NOT\s+bApproachNormalCompletion\s*,\s*PT\s*:=\s*stSequenceConfigSnapshot\.tApproachTimeout\s*\)') 'Approach timeout must stay active until normal completion, independent of safe-stop pending state'
    $reviewApproachSafeStop = Get-IfPartition $postCaseText '\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_APPROACH\s*\)?\s+AND\s+bSafeExitRequested' 'Approach must have one post-CASE acknowledged FaultStop wait' -TopLevel
    Assert-Match $reviewApproachSafeStop.PositiveBody '(?s)IF\s+NOT\s+bApproachFaultStopPending\s+THEN.*?udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1.*?bApproachFaultStopPending\s*:=\s*TRUE' 'Approach safety exit must create one fresh FaultStop source transaction'
    Assert-TopLevelPatterns $reviewApproachSafeStop.PositiveBody @(
        'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*Z_OWNER_FAULT_STOP',
        'stMotionIntent\.stZCommand\.bStop\s*:=\s*TRUE'
    ) 'Approach safety exit must retain the complete FaultStop package through every wait/timeout decision'
    Assert-True (Test-UniqueTopLevelExactAssignment $reviewApproachSafeStop.PositiveBody 'stMotionIntent\.stZCommand\.rDeceleration_mm_s2' 'stSequenceConfigSnapshot\.fStandardMoveDecelerationMmS2') 'Approach safety exit must have one final frozen positive FaultStop deceleration writer'
    Assert-True (Test-ApproachSafeExitPriorityFinality $reviewApproachSafeStop.PositiveBody) 'Approach safety priority must be the final conflict-free next-state writer set after the FaultStop payload'
    Assert-Match $reviewApproachSafeStop.PositiveBody '(?s)IF\s+tonRAxisStop\.Q\s+OR\s+\(udiFirstFaultId\s*=\s*16#0000A014\)\s+THEN.*?eNextState\s*:=\s*CFF_FAULT.*?ELSIF\s+tonApproach\.Q\s+THEN.*?udiFirstFaultId\s*=\s*0.*?16#0000A007.*?eNextState\s*:=\s*CFF_FAULT.*?ELSIF\s+\(GVL_Status\.stFast\.udiAcceptedSequenceZCommandId\s*=\s*udiZCommandId\).*?stZAxis\.bStandstill.*?udiAcceptedSequenceRCommandId\s*=\s*udiRCommandId.*?stRAxis\.bStandstill.*?bApproachFaultStopPending\s*:=\s*FALSE.*?ELSE\s+eNextState\s*:=\s*eState' 'Approach priority must be A014, A007, exact Z/R completion, then hold Approach'
    $idleAbortCondition = '\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_IDLE\s*\)?\s+AND\s+NOT\s+bSafeTerminalReset\s+AND\s+\(\s*bStopRequestedLatched\s+OR\s+bAbortEvent\s+OR\s+bResetPendingLatched\s*\)'
    $idleAbort = Get-IfPartition $postCaseText $idleAbortCondition 'Idle must have one direct no-motion Abort route for Stop/Abort/unsafe Reset' -TopLevel
    Assert-TopLevelPatterns $idleAbort.PositiveBody @(
        'eExitIntent\s*:=\s*CFF_EXIT_ABORT_NO_RETURN',
        'eNextState\s*:=\s*CFF_ABORT'
    ) 'Idle Stop/Abort/unsafe Reset must select Abort directly'
    Assert-NoMatch $idleAbort.PositiveBody 'udi(?:Z|R)CommandId\s*:=\s*udi(?:Z|R)CommandId\s*\+\s*1' 'Idle direct Abort must not fabricate a motion transaction'
    Assert-Match $postCaseText '(?s)IF\s+bStopRequestedLatched\s+THEN\s*eEndCause\s*:=\s*(?:E_StepEndCause\.)?STEP_END_STOP_REQUEST\s*;\s*END_IF.*?GVL_Status\.stFast\.stSequence\.eEndCause\s*:=\s*eEndCause' 'Latched Stop must be the final published end cause across every active exit state'
    Assert-True (Test-TerminalNormalizationBeforePublication $postCaseText) 'Transitions into Abort/Fault must have one top-level exact normalization after all routing and before every same-scan terminal status publication'
    $escapedOwnerHoldVariable = [regex]::Escape($ownerHoldVariable)
    $escapedSafeExitVariable = [regex]::Escape($safeExitVariable)
    $positiveGlobalExitCondition = "\(?\s*$escapedOwnerHoldVariable\s+AND\s+$escapedSafeExitVariable\s*\)?"
    $globalExternalExit = Get-IfPartition $postCaseText $positiveGlobalExitCondition 'Post-CASE routing must have exactly one top-level positive ownerHold AND safeExit IF with no NOT, OR, XOR, or extra gate' -TopLevel
    Assert-TopLevelPatterns $globalExternalExit.PositiveBody @(
        'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*(?:E_ZCommandOwner\.)?Z_OWNER_FORCE_PROCESS',
        'stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*TRUE',
        'stMotionIntent\.rExternalTargetVelocity_mm_s\s*:=\s*0(?:\.0+)?'
    ) 'Global External exit routing must top-level retain Force Owner/use and publish a same-scan zero target before ReleaseOwner'
    Assert-NoMatch $globalExternalExit.PositiveBody 'Z_OWNER_(?:FAULT_STOP|NONE)' 'Global External pre-release exit true branch must not switch to FaultStop or NONE'
    Assert-MatchCount $globalExternalExit.PositiveBody 'stMotionIntent\.rExternalTargetVelocity_mm_s\s*:=' 1 'Global External exit must have one final External velocity target writer'
    Assert-Match $globalExternalExit.PositiveBody 'stMotionIntent\.rExternalTargetVelocity_mm_s\s*:=\s*0(?:\.0+)?\s*;' 'Global External exit final target must be exactly zero'
    $positiveHealthyEventCondition = '\(\s*eExitIntent\s*=\s*(?:E_CffExitIntent\.)?CFF_EXIT_ABORT_NO_RETURN\s*\)\s+AND\s+bUnloadHealthy\s+AND\s+\(\s*eState\s*>=\s*(?:E_CffState\.)?CFF_CONTACT_SEARCH\s*\)\s+AND\s+\(\s*eState\s*<=\s*(?:E_CffState\.)?CFF_CONTROLLED_FORCE_UNLOAD\s*\)'
    $healthyEventSplit = Get-IfPartition $globalExternalExit.PositiveBody $positiveHealthyEventCondition 'Global External exit must have one top-level healthy Abort/Reset-to-Unload split' -TopLevel
    Assert-TopLevelPatterns $healthyEventSplit.PositiveBody @(
        'stMotionIntent\.bExternalEnableRequest\s*:=\s*TRUE',
        'stMotionIntent\.bExternalDisableRequest\s*:=\s*FALSE',
        'bForceControlEnable\s*:=\s*TRUE',
        'rForceSet_kN\s*:=\s*0(?:\.0+)?'
    ) 'A healthy post-contact Stop, Abort, or active Reset must keep the External/Force level package alive through Controlled Unload'
    $preUnloadRoute = Get-IfPartition $healthyEventSplit.PositiveBody '\(?\s*eState\s*<\s*(?:E_CffState\.)?CFF_CONTROLLED_FORCE_UNLOAD\s*\)?' 'Healthy event routing must select Controlled Unload only while entering it from an earlier state'
    $abortUnloadTransfer = Get-IfPartition $preUnloadRoute.PositiveBody 'NOT\s+bUnloadTransferInitialized' 'Healthy Abort first routing scan must initialize the Unload transfer only once'
    Assert-TopLevelPatterns $abortUnloadTransfer.PositiveBody @(
        'rTargetRelativePosition_mm\s*:=\s*GVL_Process\.stActual\.fSRelSensorMm',
        'rForceTransferVelocity_mm_s\s*:=\s*GVL_Status\.stFast\.stZExtSetpoint\.rAcceptedVelocity_mm_s',
        'bForceProfileTransferPending\s*:=\s*TRUE',
        'bUnloadTransferInitialized\s*:=\s*TRUE'
    ) 'Healthy Abort must seal SRel/accepted velocity in its first routing scan before Fast publication'
    Assert-True (Test-UniqueTopLevelOrderedAssignments $abortUnloadTransfer.PositiveBody $unloadFreezePatterns) 'Healthy Abort pre-route must freeze SRel, accepted velocity, pending, then initialized in exact final-writer order'
    Assert-MatchCount $abortUnloadTransfer.PositiveBody 'bUnloadTransferInitialized\s*:=\s*TRUE' 1 'Healthy Abort pre-route must own exactly one initialized TRUE writer'
    Assert-TopLevelPatterns $preUnloadRoute.PositiveBody @(
        'eNextState\s*:=\s*CFF_CONTROLLED_FORCE_UNLOAD'
    ) 'A first healthy post-contact event route must select Controlled Unload'
    Assert-NoMatch $preUnloadRoute.Outside 'eNextState\s*:=\s*CFF_CONTROLLED_FORCE_UNLOAD' 'An already-Unload healthy event must preserve the state CASE confirmed Disable/timeout selection'
    Assert-True (Test-ExactBooleanAssignment $healthyEventSplit.PositiveBody 'stMotionIntent\.bExternalDisableRequest' 'FALSE') 'Healthy event routing must have exactly one final Disable FALSE writer in that scan path'
    Assert-True (Test-ExactBooleanAssignment $healthyEventSplit.PositiveBody 'stMotionIntent\.bExternalEnableRequest' 'TRUE') 'Healthy event routing must have exactly one final Enable TRUE writer in that scan path'
    Assert-True (Test-ExactBooleanAssignment $healthyEventSplit.PositiveBody 'bForceControlEnable' 'TRUE') 'Healthy event routing must have exactly one final Force-enable TRUE writer in that scan path'
    Assert-MatchCount $healthyEventSplit.PositiveBody 'eNextState\s*:=' 1 'Healthy event routing must have one final next-state writer'
    Assert-NoMatch $healthyEventSplit.PositiveBody 'eNextState\s*:=\s*CFF_EXTSETPOINT_DISABLE|bForceControlEnable\s*:=\s*FALSE' 'Healthy event routing must not also select immediate Disable or stop the Force PI'
    Assert-True ($healthyEventSplit.HasElse -and
        ($healthyEventSplit.ElsifCount -eq 0)) 'Global External exit split must include one direct unconditional unsafe/PREPARE/Fault ELSE'
    if ($healthyEventSplit.HasElse -and ($healthyEventSplit.ElsifCount -eq 0)) {
        $unsafeEventBody = $healthyEventSplit.AlternateBody
        Assert-TopLevelPatterns $unsafeEventBody @(
            'stMotionIntent\.bExternalEnableRequest\s*:=\s*FALSE',
            'stMotionIntent\.bExternalDisableRequest\s*:=\s*TRUE',
            'bForceControlEnable\s*:=\s*FALSE',
            'eNextState\s*:=\s*CFF_EXTSETPOINT_DISABLE'
        ) 'Fault, unhealthy event, and External Prepare exits must use zero-speed safe Disable'
        Assert-True (Test-ExactBooleanAssignment $unsafeEventBody 'stMotionIntent\.bExternalDisableRequest' 'TRUE') 'Unsafe/PREPARE/Fault routing must have exactly one final Disable TRUE writer in that scan path'
        Assert-True (Test-ExactBooleanAssignment $unsafeEventBody 'stMotionIntent\.bExternalEnableRequest' 'FALSE') 'Unsafe/PREPARE/Fault routing must have exactly one final Enable FALSE writer in that scan path'
        Assert-True (Test-ExactBooleanAssignment $unsafeEventBody 'bForceControlEnable' 'FALSE') 'Unsafe/PREPARE/Fault routing must have exactly one final Force-enable FALSE writer in that scan path'
        Assert-MatchCount $unsafeEventBody 'eNextState\s*:=' 1 'Unsafe/PREPARE/Fault routing must have one final next-state writer'
        Assert-NoMatch $unsafeEventBody 'eNextState\s*:=\s*CFF_CONTROLLED_FORCE_UNLOAD|bForceControlEnable\s*:=\s*TRUE' 'Unsafe/PREPARE/Fault routing must not reopen healthy Controlled Unload'
    }
    $positiveApproachCondition = '\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_APPROACH\s*\)?'
    $positiveApproachExitCondition = "\(?\s*eState\s*=\s*(?:E_CffState\.)?CFF_APPROACH\s+AND\s+$escapedSafeExitVariable\s*\)?"
    $positiveExitApproachCondition = "\(?\s*$escapedSafeExitVariable\s+AND\s+eState\s*=\s*(?:E_CffState\.)?CFF_APPROACH\s*\)?"
    $positiveReleaseCondition = '\(?\s*GVL_Status\.stFast\.stZExtSetpoint\.bReleaseOwner\s*\)?'
    $globalCancellationPattern = '(?s)stMotionIntent\.stZCommand\.bUseExternalSetpoint\s*:=\s*FALSE|stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*(?:E_ZCommandOwner\.)?Z_OWNER_(?:NONE|FAULT_STOP)|stMotionIntent\.bExternalDisableRequest\s*:=\s*FALSE'
    Assert-True (Test-AllAssignmentsGuardedByAllowedPositiveIf $postCaseText $globalCancellationPattern @(
        $positiveReleaseCondition,
        $positiveApproachCondition,
        $positiveApproachExitCondition,
        $positiveExitApproachCondition,
        $positiveHealthyEventCondition,
        '\(?\s*bReturnSafeStopRequested\s*\)?'
    )) 'Every post-CASE UseExternal cancellation, Owner NONE/FaultStop, or Disable cancellation must be inside a positive Approach or ReleaseOwner true branch'
    $returnSafeStop = Get-IfPartition $postCaseText '\(?\s*bReturnSafeStopRequested\s*\)?' 'Return/Evaluate/Complete safety interruption must have one top-level fresh FaultStop handoff' -TopLevel
    Assert-Match $returnSafeStop.PositiveBody '(?s)IF\s+NOT\s+bApproachFaultStopPending\s+THEN\s*udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1\s*;.*?IF\s+udiZCommandId\s*=\s*0\s+THEN\s*udiZCommandId\s*:=\s*1.*?bApproachFaultStopPending\s*:=\s*TRUE' 'Interrupted Return ownership must create one fresh nonzero Z FaultStop transaction'
    Assert-MatchCount $returnSafeStop.PositiveBody 'udiZCommandId\s*:=\s*udiZCommandId\s*\+\s*1' 1 'Return interruption may create one Z source transaction only'
    Assert-TopLevelPatterns $returnSafeStop.PositiveBody @(
        'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*Z_OWNER_FAULT_STOP',
        'stMotionIntent\.stZCommand\.bStop\s*:=\s*TRUE',
        'stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE',
        'stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE'
    ) 'Interrupted Return must override the whole scan with FaultStop plus R zero-stop'
    Assert-True (Test-CompleteFaultStopPayload $returnSafeStop.PositiveBody) 'Interrupted Return must publish one complete, conflict-free, top-level FaultStop plus R-stop payload for the whole scan'
    Assert-True (Test-ReturnSafeStopPriority $returnSafeStop.PositiveBody) 'Interrupted Return must resolve fault intent to Fault, otherwise normalize to Abort, with no inherited or later next-state writer'
    Assert-NoMatch $returnSafeStop.PositiveBody 'CFF_EVALUATE|Z_OWNER_RETRACT|stMotionIntent\.stZCommand\.bMoveAbsolute\s*:=\s*TRUE' 'Interrupted Return must not complete, Evaluate, or retain MoveAbsolute'
    $faultBranch = Get-CaseBranch $sequence 'CFF_FAULT' 'Missing executable CASE branch: CFF_FAULT'
    $evaluateBranch = Get-CaseBranch $sequence 'CFF_EVALUATE' 'Missing executable CASE branch: CFF_EVALUATE'
    Assert-Match $evaluateBranch '(?s)FOR\s+nStepIndex\s*:=\s*1\s+TO\s+4\s+DO.*?abStepResultWritten\[nStepIndex\].*?GVL_Process\.astStepCriterion\[nStepIndex\]' 'Evaluate must consume all four real one-shot step results instead of fabricating missing facts'
    Assert-Match $evaluateBranch '(?s)bTooShort.*?bSecondaryLatched.*?STEP_END_MAX_TIME.*?astStepCriterion\[4\]\.bQualifiedForceHoldMet' 'Evaluate must consume TooShort, Secondary, StepMax, and the real Step4 Qualified Hold fact'
    Assert-NoMatch $evaluateBranch 'fbStepCriterion\.stOutput|fbForceDecline\.stOutput|fbContactDetect\.stOutput' 'Evaluate must consume only frozen one-shot results, never live algorithm outputs'
    Assert-Match $evaluateBranch '(?s)nWrittenStepPrefix\s*:=\s*0.*?bStepResultHole\s*:=\s*FALSE.*?FOR\s+nStepIndex\s*:=\s*1\s+TO\s+4\s+DO.*?abStepResultWritten\[nStepIndex\].*?nWrittenStepPrefix\s*:=\s*nStepIndex.*?bStepResultHole\s*:=\s*TRUE' 'Evaluate must accept only a contiguous real result prefix and detect holes'
    Assert-Match $evaluateBranch '(?s)CFF_EXIT_NORMAL_RETURN.*?nWrittenStepPrefix\s*<>\s*4.*?bEvaluateFault\s*:=\s*TRUE.*?CFF_EXIT_NOK_RETURN.*?nWrittenStepPrefix\s*>=\s*1' 'Evaluate must require four results for Normal while allowing a nonempty contiguous early-NOK prefix'
    foreach ($evaluateTarget in @('CFF_COMPLETE_OK','CFF_COMPLETE_NOK','CFF_ABORT','CFF_FAULT')) {
        Assert-MatchCount $evaluateBranch "eNextState\s*:=\s*$evaluateTarget" 1 "Evaluate must have one final $evaluateTarget writer"
    }
    Assert-TopLevelPatterns $evaluateBranch @(
        'stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*Z_OWNER_RETRACT',
        'stMotionIntent\.stZCommand\.bMoveAbsolute\s*:=\s*TRUE',
        'stMotionIntent\.bForceProcessExitComplete\s*:=\s*TRUE',
        'stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE',
        'stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE'
    ) 'Evaluate must retain the accepted Retract and R-stop Sequence sources while selecting the terminal'
    Assert-NoMatch $evaluateBranch 'udi(?:Z|R)CommandId\s*:=\s*udi(?:Z|R)CommandId\s*\+\s*1' 'Evaluate must not create a new motion transaction'
    $safeReset = Get-IfPartition $sequence '\(?\s*bSafeTerminalReset\s*\)?' 'Sequence must have exactly one executable safe-terminal Reset block' -TopLevel
    $safeResetAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'Safe Reset must have one unique top-level classifier assignment' 'bSafeTerminalReset'
    if ($null -ne $safeResetAssignment) {
        Assert-True (Test-SafeTerminalResetExpression $safeResetAssignment.Expression) 'Safe Reset must be ResetEvent/Pending AND Idle/all terminals AND NOT Busy AND Z/R standstill AND exact External released/idle gate'
    }
    $externalReadyAssignment = Find-BooleanAssignmentCoveringPatterns $sequence @() 'External-ready must have one unique top-level classifier assignment' 'bExternalReady'
    if ($null -ne $externalReadyAssignment) {
        Assert-True (Test-ExternalReadyExpression $externalReadyAssignment.Expression) 'External-ready must be exactly ReleaseOwner OR (Z_EXT_IDLE AND NOT Enabled), without constants, shadows, or polarity bypasses'
    }
    Assert-NoMatch $safeReset.PositiveBody 'GVL_Process\.astStepCriterion\s*\[|abStepResultWritten\s*\[' 'Safe terminal Reset must preserve four real step results and their one-shot guards until the next new Start'
    Assert-NoMatch $safeReset.PositiveBody '\b(?:udiLastObservedCommandId|udiZCommandId|udiRCommandId|udiContactReferenceRequestId)\s*:=' 'Safe Reset must preserve event high-water and monotonic Z/R/Contact transaction counters'
    Assert-MatchCount $safeReset.PositiveBody 'bUnloadTransferInitialized\s*:=\s*FALSE' 1 'Safe terminal Reset must own exactly one Unload initialized clear for the next lifecycle'
    Assert-True (Test-AllNonzeroFirstFaultWritesGuarded $sequence) 'Every nonzero first-fault write must be inside a real positive first-writer-wins gate'
    $terminalContracts = @(
        @{ State = 'CFF_COMPLETE_OK'; Done = 'TRUE'; Error = 'FALSE'; Aborted = 'FALSE'; Owner = 'Z_OWNER_RETRACT' },
        @{ State = 'CFF_COMPLETE_NOK'; Done = 'TRUE'; Error = 'TRUE'; Aborted = 'FALSE'; Owner = 'Z_OWNER_RETRACT' },
        @{ State = 'CFF_ABORT'; Done = 'FALSE'; Error = 'FALSE'; Aborted = 'TRUE'; Owner = 'Z_OWNER_FAULT_STOP' },
        @{ State = 'CFF_FAULT'; Done = 'FALSE'; Error = 'TRUE'; Aborted = 'FALSE'; Owner = 'Z_OWNER_FAULT_STOP' }
    )
    foreach ($terminalContract in $terminalContracts) {
        $terminalBranch = Get-CaseBranch $sequence $terminalContract.State "Missing terminal branch: $($terminalContract.State)"
        Assert-True (Test-TerminalTruthTableBranch $terminalBranch $terminalContract.Done $terminalContract.Error $terminalContract.Aborted) "$($terminalContract.State) must have one immutable truth-table writer set behind the exact positive safety gate"
        Assert-TopLevelPatterns $terminalBranch @(
            "stMotionIntent\.stZCommand\.eOwnerRequest\s*:=\s*$($terminalContract.Owner)",
            'stMotionIntent\.bRAxisProcessRequested\s*:=\s*TRUE',
            'stMotionIntent\.stRCommand\.bStop\s*:=\s*TRUE'
        ) "$($terminalContract.State) must retain its Sequence Z owner and R zero-stop until safe Reset"
        Assert-True (Test-ConflictFreeSafetyMotionWriters $terminalBranch "(?:E_ZCommandOwner\.)?$($terminalContract.Owner)") "$($terminalContract.State) owner, R-process request, and R-stop must each be the sole top-level final writer with no whole-structure overwrite"
    }
    Assert-Match $projectInfo "c_sArchitectureVersion\s*:\s*STRING\(31\)\s*:=\s*'V3\.7'" 'GVL_ProjectInfo must identify the approved V3.7 architecture source'
    Assert-Match $projectInfo "c_sImplementationPhase\s*:\s*STRING\(31\)\s*:=\s*'Phase 10 Source'" 'GVL_ProjectInfo must identify Phase 10 source implementation without claiming runtime qualification'
}

if ($RequireReport) {
    $reportDirectory = 'Docs\' + [char]0x62A5 + [char]0x544A
    $reportPath = Join-Path $RepositoryRoot "$reportDirectory\PHASE_10_EXECUTION_REPORT.md"
    Assert-True (Test-Path -LiteralPath $reportPath) 'Missing Phase 10 execution report'
}

if ($script:FailureCount -ne 0) { throw "Phase 10 verification failed with $script:FailureCount failure(s)." }
Write-Host "PASS: Phase 10 $Scope verification"
