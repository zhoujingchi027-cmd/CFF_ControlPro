[CmdletBinding()]
param([string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$plcRoot = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding'
$projectPath = Join-Path $plcRoot 'CFFwelding.plcproj'
$failures = New-Object 'System.Collections.Generic.List[string]'
function Fail([string]$Message) { $failures.Add($Message) }
function Get-DirectMainCaseDefaultBody {
    param([string]$Text)
    $mainCaseMatches = @([regex]::Matches($Text, '(?i)\bCASE\s+eState\s+OF\b'))
    if ($mainCaseMatches.Count -ne 1) { return '' }

    $mainCase = $mainCaseMatches[0]
    $tail = $Text.Substring($mainCase.Index)
    $tokens = [regex]::Matches(
        $tail,
        '(?i)\bEND_CASE\b|\bEND_IF\b|\bCASE\b|\bIF\b|\bELSE\b')
    $stack = New-Object 'System.Collections.Generic.List[string]'
    $defaultBodyStart = -1
    foreach ($token in $tokens) {
        switch ($token.Value.ToUpperInvariant()) {
            'CASE' { $stack.Add('CASE'); break }
            'IF' { $stack.Add('IF'); break }
            'ELSE' {
                if (($stack.Count -eq 1) -and ($stack[0] -eq 'CASE')) {
                    if ($defaultBodyStart -ge 0) { return '' }
                    $defaultBodyStart = $token.Index + $token.Length
                }
                break
            }
            'END_IF' {
                if (($stack.Count -eq 0) -or ($stack[$stack.Count - 1] -ne 'IF')) { return '' }
                $stack.RemoveAt($stack.Count - 1)
                break
            }
            'END_CASE' {
                if (($stack.Count -eq 0) -or ($stack[$stack.Count - 1] -ne 'CASE')) { return '' }
                if ($stack.Count -eq 1) {
                    if ($defaultBodyStart -lt 0) { return '' }
                    return $tail.Substring($defaultBodyStart, $token.Index - $defaultBodyStart)
                }
                $stack.RemoveAt($stack.Count - 1)
                break
            }
        }
    }
    return ''
}

if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    Fail 'PLC project is missing.'
    $projectText = ''
}
else {
    $projectText = Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8
}

$requiredObjects = @{
    'ST_ZExtSetpointConfig' = 'DUTs\Structures\ST_ZExtSetpointConfig.TcDUT'
    'FB_ZAxisExtSetpointAdapter' = 'POUs\FunctionBlocks\Axis\FB_ZAxisExtSetpointAdapter.TcPOU'
}
$objectTexts = @{}
foreach ($entry in $requiredObjects.GetEnumerator()) {
    $files = @(Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$($entry.Key).*" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -eq $entry.Key })
    if ($files.Count -ne 1) {
        Fail "Expected exactly one $($entry.Key) object; found $($files.Count)."
        continue
    }
    $text = Get-Content -LiteralPath $files[0].FullName -Raw -Encoding UTF8
    $objectTexts[$entry.Key] = $text
    try { [void][xml]$text }
    catch { Fail "Invalid TwinCAT XML: $($entry.Key)" }
    if ($projectText -notmatch [regex]::Escape($entry.Value)) {
        Fail "PLC project does not compile $($entry.Key)."
    }
}

$interfacePaths = @(
    'DUTs\Interfaces\ST_ZExtSetpointCommand.TcDUT',
    'DUTs\Interfaces\ST_ZExtSetpointStatus.TcDUT',
    'DUTs\Structures\ST_FastCommand.TcDUT',
    'DUTs\Structures\ST_FastStatus.TcDUT'
)
$interfaceText = ''
foreach ($relativePath in $interfacePaths) {
    $path = Join-Path $plcRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "Missing Phase 7 interface: $relativePath"
        continue
    }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $interfaceText += "`n$text"
    try { [void][xml]$text }
    catch { Fail "Invalid TwinCAT XML: $relativePath" }
}

foreach ($pattern in @(
    'bReset\s*:\s*BOOL',
    'bEnable\s*:\s*BOOL',
    'bFeed\s*:\s*BOOL',
    'bDisable\s*:\s*BOOL',
    'rPosition_mm\s*:\s*LREAL',
    'rVelocity_mm_s\s*:\s*LREAL',
    'rAcceleration_mm_s2\s*:\s*LREAL',
    'nDirection\s*:\s*DINT',
    'bPositiveMotionInhibit\s*:\s*BOOL',
    'bFeedAccepted\s*:\s*BOOL',
    'bReleaseOwner\s*:\s*BOOL',
    'udiFeedCycleCounter\s*:\s*UDINT',
    'bAcceptedSetpointValid\s*:\s*BOOL',
    'rAcceptedPosition_mm\s*:\s*LREAL',
    'rAcceptedVelocity_mm_s\s*:\s*LREAL',
    'rAcceptedAcceleration_mm_s2\s*:\s*LREAL',
    'nAcceptedDirection\s*:\s*DINT',
    'stZExtSetpoint\s*:\s*ST_ZExtSetpointCommand',
    'stZExtSetpoint\s*:\s*ST_ZExtSetpointStatus'
)) {
    if ($interfaceText -notmatch $pattern) { Fail "External interface is missing: $pattern" }
}

if ($objectTexts.ContainsKey('ST_ZExtSetpointConfig')) {
    $configText = $objectTexts['ST_ZExtSetpointConfig']
    foreach ($pattern in @(
        'bValid\s*:\s*BOOL',
        'tEnableTimeout\s*:\s*TIME',
        'tDisableTimeout\s*:\s*TIME',
        'rStandstillVelocity_mm_s\s*:\s*LREAL',
        'rMaximumPositionDeviation_mm\s*:\s*LREAL',
        'rMaximumVelocityStep_mm_s\s*:\s*LREAL',
        'nDirectionHoldCycles\s*:\s*UINT',
        'nPostDisableHoldCycles\s*:\s*UINT'
    )) {
        if ($configText -notmatch $pattern) { Fail "External config is missing: $pattern" }
    }
}

if ($objectTexts.ContainsKey('FB_ZAxisExtSetpointAdapter')) {
    $adapterText = $objectTexts['FB_ZAxisExtSetpointAdapter']
    # Contract matching must inspect executable ST only; comments cannot satisfy safety checks.
    $adapterText = [regex]::Replace($adapterText, '(?s)\(\*.*?\*\)|//[^\r\n]*', '')
    foreach ($pattern in @(
        'VAR_IN_OUT[\s\S]*Axis\s*:\s*AXIS_REF',
        'bDriveLinked\s*:\s*BOOL',
        'bOwnerGranted\s*:\s*BOOL',
        'bLimitsValid\s*:\s*BOOL',
        'bPostDisableHoldPending\s*:\s*BOOL',
        'MC_ExtSetPointGenEnable',
        'MC_ExtSetPointGenDisable',
        'MC_ExtSetPointGenFeed\s*\(',
        'PositionType\s*:=\s*POSITIONTYPE_ABSOLUTE',
        'Axis\.NcToPlc\.SetPos',
        'Axis\.NcToPlc\.SetVelo',
        'Axis\.NcToPlc\.SetAcc',
        'FC_IsFiniteLReal\(rValue\s*:=\s*Axis\.NcToPlc\.SetPos\)',
        'FC_IsFiniteLReal\(rValue\s*:=\s*Axis\.NcToPlc\.SetVelo\)',
        'FC_IsFiniteLReal\(rValue\s*:=\s*Axis\.NcToPlc\.SetAcc\)',
        'FC_IsFiniteLReal\(rValue\s*:=\s*rMinimumPosition_mm\)',
        'FC_IsFiniteLReal\(rValue\s*:=\s*rMaximumPosition_mm\)',
        'Axis\.Status\.ExtSetPointGenEnabled',
        'Position\s*:=\s*rFeedPosition_mm',
        'Velocity\s*:=\s*rFeedVelocity_mm_s',
        'Acceleration\s*:=\s*rFeedAcceleration_mm_s2',
        'Direction\s*:=\s*nFeedDirection',
        'bReleaseOwner\s*:=',
        'bDriveLinked\s+AND',
        'bOwnerGranted\s+AND',
        'tEnableTimeout\s*>\s*T#0S',
        'tDisableTimeout\s*>\s*T#0S',
        'bPostDisableHoldPending\s*:=\s*TRUE',
        'NOT\s+bPostDisableHoldPending\s+AND',
        'nAcceptedDirection\s*=\s*1[\s\S]*nFeedDirection\s*=\s*-1',
        '16#00007209',
        'nAcceptedDirection\s*=\s*0[\s\S]*nFeedDirection\s*<>\s*0',
        'bPrecheckOk\s*:=',
        'bActiveFeedCommandValid\s*:=',
        'bAcceptedSetpointValid\s*:=\s*TRUE',
        'rAcceptedPosition_mm\s*:=\s*Axis\.NcToPlc\.SetPos',
        'rAcceptedVelocity_mm_s\s*:=\s*Axis\.NcToPlc\.SetVelo',
        'rAcceptedAcceleration_mm_s2\s*:=\s*Axis\.NcToPlc\.SetAcc',
        'nAcceptedDirection\s*:=\s*nInitialDirection',
        'rAcceptedPosition_mm\s*:=\s*rFeedPosition_mm',
        'rAcceptedVelocity_mm_s\s*:=\s*rFeedVelocity_mm_s',
        'rAcceptedAcceleration_mm_s2\s*:=\s*rFeedAcceleration_mm_s2',
        'nAcceptedDirection\s*:=\s*nFeedDirection',
        'udiFeedCycleCounter\s*=\s*UDINT#4294967295[\s\S]*udiFeedCycleCounter\s*:=\s*1',
        'bZ_EXT_DIRECTION_HOLD\s*:\s*BOOL',
        'bZ_EXT_DIRECTION_ZERO\s*:\s*BOOL',
        'bZ_EXT_DIRECTION_PRELOAD\s*:\s*BOOL',
        'nPendingDirection\s*:\s*DINT',
        'bPositiveMotionInhibit[\s\S]*stStatus\.rAcceptedPosition_mm[\s\S]*stStatus\.nAcceptedDirection'
    )) {
        if ($adapterText -notmatch $pattern) { Fail "External adapter is missing: $pattern" }
    }

    $precheckMatch = [regex]::Match(
        $adapterText,
        '(?s)E_ZExtSetpointState\.Z_EXT_PRECHECK\s*:.*?(?=E_ZExtSetpointState\.Z_EXT_PRELOAD_DIRECTION\s*:)' )
    if (-not $precheckMatch.Success) {
        Fail 'External adapter PRECHECK branch is missing.'
    }
    else {
        if ($precheckMatch.Value -match 'stCommand\.r(?:Position|Velocity|Acceleration)_mm') {
            Fail 'External PRECHECK must not require a trajectory Feed payload before Enable.'
        }
        foreach ($pattern in @(
            'bPrecheckOk',
            'bAcceptedSetpointValid\s*:=\s*TRUE',
            'rAcceptedPosition_mm\s*:=\s*Axis\.NcToPlc\.SetPos',
            'rAcceptedVelocity_mm_s\s*:=\s*Axis\.NcToPlc\.SetVelo',
            'rAcceptedAcceleration_mm_s2\s*:=\s*Axis\.NcToPlc\.SetAcc',
            'nAcceptedDirection\s*:=\s*nInitialDirection',
            'nLastNonZeroDirection\s*:=\s*nInitialDirection'
        )) {
            if ($precheckMatch.Value -notmatch $pattern) {
                Fail "External PRECHECK contract is missing: $pattern"
            }
        }
    }

    $activeMatch = [regex]::Match(
        $adapterText,
        '(?s)(?:E_ZExtSetpointState\.)?Z_EXT_ACTIVE\s*:.*?(?=(?:E_ZExtSetpointState\.)?Z_EXT_RAMP_TO_ZERO\s*:)' )
    if (-not $activeMatch.Success) {
        Fail 'External adapter ACTIVE branch is missing.'
    }
    else {
        $activeText = $activeMatch.Value
        $inhibitIndex = $activeText.IndexOf('bPositiveMotionInhibit')
        $disableIndex = $activeText.IndexOf('stCommand.bDisable')
        if ($inhibitIndex -lt 0 -or $disableIndex -lt 0 -or $inhibitIndex -gt $disableIndex) {
            Fail 'Hard positive-motion inhibit must be handled before the controlled Disable request.'
        }
        $inhibitMatch = [regex]::Match(
            $activeText,
            '(?s)ELSIF\s+stCommand\.bPositiveMotionInhibit\s+THEN(.*?)(?=ELSIF\s+stCommand\.bDisable)' )
        if (-not $inhibitMatch.Success) {
            Fail 'Hard positive-motion inhibit branch is missing.'
        }
        else {
            foreach ($pattern in @(
                'stCommand\.rPosition_mm\s*=\s*stStatus\.rAcceptedPosition_mm',
                'stCommand\.rVelocity_mm_s\s*=\s*0\.0',
                'stCommand\.rAcceleration_mm_s2\s*=\s*0\.0',
                'stCommand\.nDirection\s*=\s*stStatus\.nAcceptedDirection',
                'bDisable\s*:=\s*TRUE'
            )) {
                if ($inhibitMatch.Groups[1].Value -notmatch $pattern) {
                    Fail "Hard inhibit exact-package contract is missing: $pattern"
                }
            }
            if ($inhibitMatch.Groups[1].Value -match 'rFeed(?:Position_mm|Velocity_mm_s|Acceleration_mm_s2)\s*:=\s*stCommand\.') {
                Fail 'Invalid hard-inhibit input must not overwrite the last safe internal Feed package.'
            }
        }
        foreach ($pattern in @(
            'bZ_EXT_DIRECTION_HOLD',
            'bZ_EXT_DIRECTION_ZERO',
            'bZ_EXT_DIRECTION_PRELOAD',
            'nFeedDirection\s*<>\s*stStatus\.nAcceptedDirection[\s\S]*stCommand\.rVelocity_mm_s\s*<>\s*0\.0[\s\S]*stCommand\.rAcceleration_mm_s2\s*<>\s*0\.0[\s\S]*stCommand\.rPosition_mm\s*<>\s*stStatus\.rAcceptedPosition_mm',
            'bClearDirectionHandshakeAfterFeed\s*:=\s*TRUE',
            'ELSIF\s+\(nFeedDirection\s*=\s*0\)[\s\S]*stCommand\.rPosition_mm\s*<>\s*stStatus\.rAcceptedPosition_mm[\s\S]*stCommand\.rVelocity_mm_s\s*<>\s*0\.0[\s\S]*stCommand\.rAcceleration_mm_s2\s*<>\s*0\.0[\s\S]*udiLatchedErrorId\s*:=\s*16#00007209',
            '16#00007209'
        )) {
            if ($activeText -notmatch $pattern) {
                Fail "External ACTIVE safety contract is missing: $pattern"
            }
        }

        $oldDirectionStandstillBranches = @([regex]::Matches(
            $activeText,
            '(?s)ELSIF\s+\(nFeedDirection\s*=\s*stStatus\.nAcceptedDirection\)\s+AND\s+\(nFeedDirection\s*<>\s*0\).*?(?=\s+ELSIF)' ))
        if ($oldDirectionStandstillBranches.Count -lt 2) {
            Fail 'Expected separate old-direction standstill reject and accept branches.'
        }
        else {
            $oldDirectionReject = $oldDirectionStandstillBranches[0].Value
            $oldDirectionAccept = $oldDirectionStandstillBranches[1].Value
            if ($oldDirectionReject -notmatch 'stStatus\.rAcceptedVelocity_mm_s\s*=\s*0\.0[\s\S]*stCommand\.rPosition_mm\s*<>\s*stStatus\.rAcceptedPosition_mm') {
                Fail 'Old-direction standstill position jump must be rejected after accepted V reaches zero.'
            }
            if ($oldDirectionAccept -notmatch 'stStatus\.rAcceptedVelocity_mm_s\s*=\s*0\.0[\s\S]*stCommand\.rPosition_mm\s*=\s*stStatus\.rAcceptedPosition_mm[\s\S]*bZ_EXT_DIRECTION_HOLD\s*:=\s*TRUE') {
                Fail 'Held old-direction P/V0/A0 packet must establish HOLD in the acceptance scan.'
            }
            if (($oldDirectionReject + $oldDirectionAccept) -match 'stStatus\.rAcceptedAcceleration_mm_s2\s*=\s*0\.0') {
                Fail 'Old-direction standstill P validation must not depend on the previous accepted acceleration being zero.'
            }
        }
    }

    $waitEnabledMatch = [regex]::Match(
        $adapterText,
        '(?s)(?:E_ZExtSetpointState\.)?Z_EXT_WAIT_ENABLED\s*:.*?(?=(?:E_ZExtSetpointState\.)?Z_EXT_ACTIVE\s*:)' )
    if (-not $waitEnabledMatch.Success) {
        Fail 'External adapter WAIT_ENABLED branch is missing.'
    }
    else {
        foreach ($pattern in @(
            'ELSIF\s+NOT\s+bPrecheckOk\s+THEN[\s\S]*bFeedThisCycle\s*:=\s*FALSE[\s\S]*bExitDueToError\s*:=\s*TRUE[\s\S]*Z_EXT_RAMP_TO_ZERO[\s\S]*ELSIF\s+Axis\.Status\.ExtSetPointGenEnabled',
            'Axis\.Status\.ExtSetPointGenEnabled\s+OR\s+fbEnable\.Enabled[\s\S]*stCommand\.bPositiveMotionInhibit',
            'stCommand\.bFeed[\s\S]*bActiveFeedCommandValid',
            'stCommand\.rPosition_mm\s*=\s*stStatus\.rAcceptedPosition_mm',
            'stCommand\.rVelocity_mm_s\s*=\s*0\.0',
            'stCommand\.rAcceleration_mm_s2\s*=\s*0\.0',
            'stCommand\.nDirection\s*=\s*stStatus\.nAcceptedDirection',
            'bFeedThisCycle\s*:=\s*FALSE[\s\S]*bExitDueToError\s*:=\s*TRUE',
            'bFeedThisCycle\s*:=\s*TRUE[\s\S]*bDisable\s*:=\s*TRUE'
        )) {
            if ($waitEnabledMatch.Value -notmatch $pattern) {
                Fail "WAIT_ENABLED hard-inhibit contract is missing: $pattern"
            }
        }
        if ($waitEnabledMatch.Value -match 'rFeed(?:Position_mm|Velocity_mm_s|Acceleration_mm_s2)\s*:=\s*stCommand\.') {
            Fail 'WAIT_ENABLED invalid hard-inhibit input must not contaminate the last safe Feed package.'
        }
    }

    $unknownStateBody = Get-DirectMainCaseDefaultBody $adapterText
    if ([string]::IsNullOrWhiteSpace($unknownStateBody)) {
        Fail 'External adapter main CASE must have one direct unknown-state default.'
    }
    else {
        $linkedLifecycle = [regex]::Match(
            $unknownStateBody,
            '(?s)IF\s+Axis\.Status\.ExtSetPointGenEnabled\s+OR\s+fbEnable\.Enabled\s+OR\s+fbDisable\.Enabled\s+THEN(?<Active>.*?)ELSE(?<Inactive>.*?)END_IF')
        if (-not $linkedLifecycle.Success) {
            Fail 'Unknown adapter state must branch on the complete linked External lifecycle condition with a direct ELSE.'
        }
        else {
            $prefix = $unknownStateBody.Substring(0, $linkedLifecycle.Index)
            foreach ($pattern in @(
                'udiLatchedErrorId\s*:=\s*16#00007206',
                'bExitDueToError\s*:=\s*TRUE',
                'stStatus\.bDone\s*:=\s*FALSE',
                'stStatus\.bReleaseOwner\s*:=\s*FALSE',
                'stStatus\.bAcceptedSetpointValid\s*:=\s*FALSE',
                'bFeedThisCycle\s*:=\s*FALSE'
            )) {
                if ($prefix -notmatch $pattern) { Fail "Unknown adapter state common fail-closed prefix is missing: $pattern" }
            }
            foreach ($pattern in @(
                'bPostDisableHoldPending\s*:=\s*TRUE',
                'eState\s*:=\s*E_ZExtSetpointState\.Z_EXT_DISABLE'
            )) {
                if ($linkedLifecycle.Groups['Active'].Value -notmatch $pattern) { Fail "Unknown linked-lifecycle route is missing: $pattern" }
            }
            foreach ($pattern in @(
                'bPostDisableHoldPending\s*:=\s*FALSE',
                'eState\s*:=\s*E_ZExtSetpointState\.Z_EXT_ERROR'
            )) {
                if ($linkedLifecycle.Groups['Inactive'].Value -notmatch $pattern) { Fail "Unknown inactive-lifecycle route is missing: $pattern" }
            }
        }
        if ($unknownStateBody -match 'bFeedThisCycle\s*:=\s*TRUE|stStatus\.bFeedAccepted\s*:=\s*TRUE|MC_ExtSetPointGenFeed\s*\(') {
            Fail 'Unknown adapter state must not publish a motion Feed.'
        }
        if ($unknownStateBody -match 'stStatus\.bReleaseOwner\s*:=\s*TRUE') {
            Fail 'Unknown adapter state must not claim owner release in the detection scan.'
        }
    }

    $feedMatch = [regex]::Match(
        $adapterText,
        '(?s)IF\s+bFeedThisCycle\s+AND\s+bDriveLinked\s+THEN.*?(?=stStatus\.eState\s*:=)' )
    if (-not $feedMatch.Success) {
        Fail 'External accepted-Feed publication block is missing.'
    }
    else {
        foreach ($pattern in @(
            'MC_ExtSetPointGenFeed',
            'bFeedAccepted\s*:=\s*TRUE',
            'rAcceptedPosition_mm\s*:=\s*rFeedPosition_mm',
            'rAcceptedVelocity_mm_s\s*:=\s*rFeedVelocity_mm_s',
            'rAcceptedAcceleration_mm_s2\s*:=\s*rFeedAcceleration_mm_s2',
            'nAcceptedDirection\s*:=\s*nFeedDirection',
            'udiFeedCycleCounter\s*=\s*UDINT#4294967295',
            'udiFeedCycleCounter\s*:=\s*1'
        )) {
            if ($feedMatch.Value -notmatch $pattern) {
                Fail "External accepted-Feed block is missing: $pattern"
            }
        }
        foreach ($pattern in @(
            'IF\s+bClearDirectionHandshakeAfterFeed\s+THEN[\s\S]*bZ_EXT_DIRECTION_HOLD\s*:=\s*FALSE[\s\S]*bZ_EXT_DIRECTION_ZERO\s*:=\s*FALSE[\s\S]*bZ_EXT_DIRECTION_PRELOAD\s*:=\s*FALSE[\s\S]*nPendingDirection\s*:=\s*0',
            'stStatus\.rAcceptedPosition_mm\s*:=\s*rFeedPosition_mm[\s\S]*stStatus\.nAcceptedDirection\s*:=\s*nFeedDirection'
        )) {
            if ($feedMatch.Value -notmatch $pattern) {
                Fail "External post-Feed handshake contract is missing: $pattern"
            }
        }
    }

    if (([regex]::Matches($adapterText, '(?m)^\s*Z_EXT_ACTIVE\s*:')).Count -ne 0) {
        Fail 'External adapter must not contain a second bare ACTIVE CASE branch.'
    }
    if (([regex]::Matches($adapterText, 'stStatus\.rAcceptedPosition_mm\s*:=\s*rFeedPosition_mm')).Count -ne 1) {
        Fail 'External accepted Feed position must be published exactly once.'
    }

    foreach ($terminalState in @('Z_EXT_DONE', 'Z_EXT_ERROR')) {
        $terminalMatch = [regex]::Match(
            $adapterText,
            "(?ms)^\s*(?:E_ZExtSetpointState\.)?$terminalState\s*:.*?(?=^\s*(?:E_ZExtSetpointState\.)?Z_EXT_[A-Z_]+\s*:|^\s*END_CASE)" )
        if (-not $terminalMatch.Success) {
            Fail "External terminal branch is missing: $terminalState"
            continue
        }
        foreach ($pattern in @(
            'stStatus\.bAcceptedSetpointValid\s*:=\s*FALSE',
            'bZ_EXT_DIRECTION_HOLD\s*:=\s*FALSE',
            'bZ_EXT_DIRECTION_ZERO\s*:=\s*FALSE',
            'bZ_EXT_DIRECTION_PRELOAD\s*:=\s*FALSE',
            'nPendingDirection\s*:=\s*0',
            'eState\s*:=\s*E_ZExtSetpointState\.Z_EXT_IDLE'
        )) {
            if ($terminalMatch.Value -notmatch $pattern) {
                Fail "$terminalState same-scan reset contract is missing: $pattern"
            }
        }
    }

    foreach ($stateName in @(
        'Z_EXT_IDLE', 'Z_EXT_PRECHECK', 'Z_EXT_PRELOAD_DIRECTION',
        'Z_EXT_PREFEED_INITIAL', 'Z_EXT_ENABLE', 'Z_EXT_WAIT_ENABLED',
        'Z_EXT_ACTIVE', 'Z_EXT_RAMP_TO_ZERO', 'Z_EXT_HOLD_DIRECTION',
        'Z_EXT_DIRECTION_ZERO', 'Z_EXT_DISABLE', 'Z_EXT_WAIT_DISABLED',
        'Z_EXT_POST_DISABLE_HOLD', 'Z_EXT_DONE', 'Z_EXT_ERROR'
    )) {
        if ($adapterText -notmatch [regex]::Escape($stateName)) {
            Fail "External lifecycle state is missing: $stateName"
        }
    }

    if ($adapterText -match 'UseTorqueOffset\s*:=\s*TRUE|MC_ExtSetPointGenFeedWithTorque') {
        Fail 'Phase 7 must keep TorqueOffset disabled.'
    }
    if ($adapterText -match 'fbDisable\.Done\s+OR') {
        Fail 'Disable Done must not bypass confirmed generator-disabled state.'
    }
    if ($projectText -match 'Tc2_MC2,3\.3\.65\.0' -and
        $adapterText -match 'ST_ExtSetPointEnableOptions|Options\s*:=') {
        Fail 'Tc2_MC2 3.3.65.0 does not expose External Enable Options.'
    }
    if ($adapterText -match 'bDriveLinked\s*:=\s*TRUE|bReady\s*:=\s*TRUE') {
        Fail 'External adapter must not force drive binding or Ready TRUE.'
    }
}

# Scan-level reference fixtures for the two stationary-position boundaries.
$stationaryFixtures = @(
    [pscustomobject]@{ Name = 'DirectionZeroPositionJump'; AcceptedP = 10.0; AcceptedV = 0.0; AcceptedA = 0.0; AcceptedDirection = 0; CommandP = 10.05; CommandV = 0.0; CommandA = 0.0; CommandDirection = 0; Expected = $false },
    [pscustomobject]@{ Name = 'OldDirectionHeldAfterNonzeroAcceptedA'; AcceptedP = 10.0; AcceptedV = 0.0; AcceptedA = -2.0; AcceptedDirection = 1; CommandP = 10.0; CommandV = 0.0; CommandA = 0.0; CommandDirection = 1; Expected = $true },
    [pscustomobject]@{ Name = 'OldDirectionPositionJumpAfterNonzeroAcceptedA'; AcceptedP = 10.0; AcceptedV = 0.0; AcceptedA = -2.0; AcceptedDirection = 1; CommandP = 10.05; CommandV = 0.0; CommandA = 0.0; CommandDirection = 1; Expected = $false })
foreach ($fixture in $stationaryFixtures) {
    $stationaryPacketAccepted = ($fixture.CommandP -eq $fixture.AcceptedP) -and
        ($fixture.CommandV -eq 0.0) -and ($fixture.CommandA -eq 0.0) -and
        ($fixture.CommandDirection -eq $fixture.AcceptedDirection) -and
        ($fixture.AcceptedV -eq 0.0)
    if ($stationaryPacketAccepted -ne $fixture.Expected) {
        Fail "Stationary packet reference failed: $($fixture.Name)"
    }
}

$fastAxisPath = Join-Path $plcRoot 'POUs\Fast\PRG_FastAxisControl.TcPOU'
if (-not (Test-Path -LiteralPath $fastAxisPath -PathType Leaf)) {
    Fail 'PRG_FastAxisControl is missing.'
}
else {
    $fastAxisText = Get-Content -LiteralPath $fastAxisPath -Raw -Encoding UTF8
    $fastAxisExecutable = [regex]::Replace($fastAxisText, '\(\*[\s\S]*?\*\)', '')
    foreach ($pattern in @(
        'fbZAxisExtSetpointAdapter\s*:\s*FB_ZAxisExtSetpointAdapter',
        'fbZAxisArbiter\.eActiveOwner\s*=\s*E_ZCommandOwner\.Z_OWNER_FORCE_PROCESS',
        'bLimitsValid\s*:=\s*GVL_Status\.stFast\.stSequence\s*\.stFastConfigSnapshot\.stLimits\.bValid',
        'bExternalCommandChannelBusy\s*:\s*BOOL',
        'udiZStandardCommandId\s*:\s*UDINT',
        'stSelectedZCommand\.bStop\s*:=\s*FALSE',
        'udiCommandId\s*:=\s*udiZStandardCommandId',
        'stFast\.stZExtSetpoint',
        'ALARM_EXTERNAL_SETPOINT_FAULT',
        'bReleaseOwner'
    )) {
        if ($fastAxisText -notmatch $pattern) { Fail "PRG_FastAxisControl is missing: $pattern" }
    }
    if ($fastAxisExecutable -match 'GVL_Config\.(?:stLimits|stZExtSetpoint|stMachine\.nFastTaskCycleUs)') {
        Fail 'PRG_FastAxisControl External lifecycle must not consume live configuration.'
    }
    if ($fastAxisText -match '\bMC_ExtSetPointGen(?:Enable|Feed|Disable)\b') {
        Fail 'PRG_FastAxisControl must delegate External MC calls to the adapter.'
    }
}

$pouFiles = @(Get-ChildItem -LiteralPath (Join-Path $plcRoot 'POUs') -Recurse -File -Filter '*.TcPOU')
$externalApiOwners = @()
foreach ($pouFile in $pouFiles) {
    $pouText = Get-Content -LiteralPath $pouFile.FullName -Raw -Encoding UTF8
    if ($pouText -match '\bMC_ExtSetPointGen(?:Enable|Feed|Disable)\b') {
        $externalApiOwners += $pouFile.BaseName
    }
}
if (@($externalApiOwners | Sort-Object -Unique).Count -ne 1 -or
    'FB_ZAxisExtSetpointAdapter' -notin $externalApiOwners) {
    Fail "External MC API must have one owner; found: $($externalApiOwners -join ', ')"
}

$sequencePath = Join-Path $plcRoot 'POUs\Fast\PRG_CffSequence.TcPOU'
if (Test-Path -LiteralPath $sequencePath -PathType Leaf) {
    $sequenceText = Get-Content -LiteralPath $sequencePath -Raw -Encoding UTF8
    if ($sequenceText -match '\bMC_[A-Za-z0-9_]+|AXIS_REF') {
        Fail 'PRG_CffSequence must not access MC function blocks or AXIS_REF.'
    }
}

$controlRoot = Join-Path $plcRoot 'POUs\FunctionBlocks\Control'
if (Test-Path -LiteralPath $controlRoot -PathType Container) {
    foreach ($controlFile in Get-ChildItem -LiteralPath $controlRoot -Recurse -File -Filter '*.TcPOU') {
        $controlText = Get-Content -LiteralPath $controlFile.FullName -Raw -Encoding UTF8
        if ($controlText -match '\bMC_[A-Za-z0-9_]+|AXIS_REF') {
            Fail "Control algorithm escaped the MC boundary: $($controlFile.Name)"
        }
    }
}

$allSourceText = ($pouFiles | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
}) -join "`n"
if ($allSourceText -match 'b(?:ZAxis|RAxis)DriveLinked\s*:=\s*TRUE|bProductionReady\s*:=\s*TRUE|bAllRequiredMappingsConfirmed\s*:=\s*TRUE') {
    Fail 'Source must not force hardware binding, mapping, or Production Ready TRUE.'
}

$reportFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Docs') -Recurse -File -Filter 'PHASE_7_EXECUTION_REPORT.md' -ErrorAction SilentlyContinue)
if ($reportFiles.Count -ne 1) {
    Fail "Expected exactly one Phase 7 execution report; found $($reportFiles.Count)."
}

if ($failures.Count -gt 0) {
    Write-Host 'Phase 7 external setpoint test: FAILED'
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}

Write-Host 'Phase 7 external setpoint test: PASSED'
Write-Host 'External API owner: FB_ZAxisExtSetpointAdapter only'
Write-Host 'Unbound hardware policy: External enable remains inhibited'
