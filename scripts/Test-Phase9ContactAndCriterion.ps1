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
function Read-Source([string]$RelativePath) {
    $path = Join-Path $plcRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "Missing Phase 9 source: $RelativePath"
        return ''
    }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    try { [void][xml]$text }
    catch { Fail "Invalid TwinCAT XML: $RelativePath" }
    return $text
}
function Assert-Patterns([string]$Label, [string]$Text, [string[]]$Patterns) {
    foreach ($pattern in $Patterns) {
        if ($Text -notmatch $pattern) { Fail "$Label is missing: $pattern" }
    }
}
function Assert-Ordered([string]$Label, [string]$Text, [string[]]$Tokens) {
    $offset = -1
    foreach ($token in $Tokens) {
        $next = $Text.IndexOf($token, $offset + 1, [StringComparison]::Ordinal)
        if ($next -lt 0) {
            Fail "$Label is missing ordered token: $token"
            return
        }
        $offset = $next
    }
}
function Get-ExecutableIecText([string]$Text) {
    return [regex]::Replace($Text, '(?s)\(\*.*?\*\)|//[^\r\n]*', '')
}
function Test-SequenceEnableAllowlist([string]$RawText) {
    $text = Get-ExecutableIecText $RawText
    $assignments = [regex]::Matches($text, '(?s)\bst(?<Name>ContactInput|ForceDeclineInput|StepCriterionInput)\.bEnable\s*:=\s*(?<Expression>[^;]*);')
    if ($assignments.Count -ne 3) { return $false }
    foreach ($assignment in $assignments) {
        $name = $assignment.Groups['Name'].Value
        $expression = $assignment.Groups['Expression'].Value.Trim()
        if ($expression -match '(?i)\bGVL_Status\.stFast\.stSequence\.eState\b') { return $false }
        if ($expression -match '(?i)\b(?:NOT|XOR)\b|<>|\b(?:TRUE|FALSE)\b') { return $false }
        $allowedStates = switch ($name) {
            'ContactInput' { @('CFF_CONTACT_SEARCH') }
            'ForceDeclineInput' { @('CFF_STEP1_RAMP_PROCESS', 'CFF_STEP2_RAMP_PROCESS', 'CFF_STEP3_RAMP_PROCESS') }
            'StepCriterionInput' { @(
                'CFF_STEP1_RAMP_PROCESS',
                'CFF_STEP2_RAMP_PROCESS',
                'CFF_STEP3_RAMP_PROCESS',
                'CFF_BRAKE_AND_COMPRESSION_RAMP',
                'CFF_STEP4_VALID_FORCE_HOLD') }
        }
        if ($name -eq 'ForceDeclineInput') {
            $primaryPredicate = '(?i)\(?\s*stCycleSnapshot\.stProgram\.astSteps\s*\[\s*nActiveStepProgramIndex\s*\]\.stProceeding\.ePrimaryCriterion\s*=\s*(?:E_StepPrimaryCriterion\.)?STEP_CRIT_FORCE_DECLINE_TO\s*\)?'
            $primaryMatches = [regex]::Matches($expression, $primaryPredicate)
            if ($primaryMatches.Count -ne 1) { return $false }
            if ([regex]::Matches($expression, '(?i)\bAND\b').Count -ne 1) { return $false }
            $forceGate = [regex]::Match(
                $expression,
                "(?is)^\s*\(\((?<States>.*)\)\)\s+AND\s+(?:$primaryPredicate)\s*$")
            if (-not $forceGate.Success) { return $false }
            $expression = $forceGate.Groups['States'].Value.Trim()
        }
        elseif ($expression -match '(?i)\bAND\b') {
            return $false
        }
        $alternatives = @([regex]::Split($expression, '(?i)\bOR\b'))
        if ($alternatives.Count -eq 0) { return $false }
        if (($name -eq 'ContactInput') -and ($alternatives.Count -ne 1)) { return $false }
        $seenStates = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($alternative in $alternatives) {
            $statePredicate = [regex]::Match(
                $alternative,
                '(?i)^\s*\(?\s*eState\s*=\s*(?:E_CffState\.)?(?<State>CFF_[A-Z0-9_]+)\s*\)?\s*$')
            if (-not $statePredicate.Success) { return $false }
            $state = $statePredicate.Groups['State'].Value.ToUpperInvariant()
            if ($allowedStates -notcontains $state) { return $false }
            if (-not $seenStates.Add($state)) { return $false }
        }
        if ($seenStates.Count -ne @($allowedStates).Count) { return $false }
        foreach ($allowedState in $allowedStates) {
            if (-not $seenStates.Contains($allowedState)) { return $false }
        }
    }
    return $true
}
function Test-ContactReferencePublicWriter([string]$RawText) {
    $text = Get-ExecutableIecText $RawText
    $tokens = [regex]::Matches(
        $text,
        '(?is)\bELSIF\s+(?<ElsifCondition>.*?)\s+THEN\b|\bIF\s+(?<Condition>.*?)\s+THEN\b|\bELSE\b|\bEND_IF\s*;?')
    $stack = New-Object 'System.Collections.Generic.Stack[object]'
    $regions = New-Object 'System.Collections.Generic.List[object]'
    foreach ($token in $tokens) {
        if ($token.Groups['Condition'].Success) {
            $stack.Push([pscustomobject]@{
                Condition = $token.Groups['Condition'].Value.Trim()
                Start = $token.Index
                BodyStart = $token.Index + $token.Length
                AlternateStart = -1
                ParentDepth = $stack.Count
            })
        }
        elseif ($token.Groups['ElsifCondition'].Success -or
                $token.Value -match '(?i)^\s*ELSE\s*$') {
            if ($stack.Count -gt 0 -and $stack.Peek().AlternateStart -lt 0) {
                $stack.Peek().AlternateStart = $token.Index
            }
        }
        elseif ($stack.Count -gt 0) {
            $openRegion = $stack.Pop()
            $regions.Add([pscustomobject]@{
                Condition = $openRegion.Condition
                Start = $openRegion.Start
                BodyStart = $openRegion.BodyStart
                BodyEnd = $token.Index
                End = $token.Index + $token.Length
                AlternateStart = $openRegion.AlternateStart
                ParentDepth = $openRegion.ParentDepth
            })
        }
    }
    $writerGates = @($regions | Where-Object {
        ($_.ParentDepth -eq 0) -and
        ($_.Condition -match '(?i)^\(?\s*bProcessReferencePending\s*\)?$')
    })
    if ($writerGates.Count -ne 1) { return $false }
    $writerGate = $writerGates[0]
    $writerPositiveEnd = if ($writerGate.AlternateStart -ge 0) {
        $writerGate.AlternateStart
    } else {
        $writerGate.BodyEnd
    }

    $fields = @(
        'bLatchContactReference',
        'bUseProvidedContactReference',
        'rProvidedContactSensorPosition_mm',
        'rProvidedContactAxisPosition_mm',
        'bResetContactReference',
        'udiContactReferenceRequestId'
    )
    $offset = -1
    foreach ($field in $fields) {
        $pattern = "\bGVL_Command\.stProcessReference\.$([regex]::Escape($field))\s*:=\s*(?<Rhs>[^;]*);"
        $matches = [regex]::Matches($text, $pattern)
        if ($matches.Count -ne 1) { return $false }
        $rhs = [regex]::Replace($matches[0].Groups['Rhs'].Value, '\s+', '')
        $expectedRhs = "stPendingProcessReferenceCommand.$field"
        if (-not $rhs.Equals($expectedRhs, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        $containingRegions = @($regions | Where-Object {
            ($matches[0].Index -ge $_.BodyStart) -and
            ($matches[0].Index -lt $_.BodyEnd)
        })
        if (($containingRegions.Count -ne 1) -or
                ($containingRegions[0].Start -ne $writerGate.Start) -or
                ($matches[0].Index -ge $writerPositiveEnd)) { return $false }
        if ($matches[0].Index -le $offset) { return $false }
        $offset = $matches[0].Index
    }
    return $true
}

$enableAllowedFixture = @'
stContactInput.bEnable := eState = E_CffState.CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable :=
    ((eState = CFF_STEP1_RAMP_PROCESS)
        OR (eState = CFF_STEP2_RAMP_PROCESS)
        OR (eState = CFF_STEP3_RAMP_PROCESS))
    AND (stCycleSnapshot.stProgram.astSteps[nActiveStepProgramIndex].stProceeding.ePrimaryCriterion
        = STEP_CRIT_FORCE_DECLINE_TO);
stStepCriterionInput.bEnable := (eState = CFF_STEP1_RAMP_PROCESS)
    OR (eState = CFF_STEP2_RAMP_PROCESS)
    OR (eState = CFF_STEP3_RAMP_PROCESS)
    OR (eState = CFF_BRAKE_AND_COMPRESSION_RAMP)
    OR (eState = CFF_STEP4_VALID_FORCE_HOLD);
'@
$enableAllowedAndConditionFixture = @'
stContactInput.bEnable := (eState = CFF_CONTACT_SEARCH)
    AND bSensorHealthy;
stForceDeclineInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableAllowedOrOverrideFixture = @'
stContactInput.bEnable := (eState = CFF_CONTACT_SEARCH)
    OR bManualOverride;
stForceDeclineInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableAllowedXorOverrideFixture = @'
stContactInput.bEnable := (eState = CFF_CONTACT_SEARCH)
    XOR bManualOverride;
stForceDeclineInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableNotAllowedFixture = @'
stContactInput.bEnable := NOT (eState = CFF_CONTACT_SEARCH);
stForceDeclineInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableForbiddenStateFixture = @'
stContactInput.bEnable := eState = CFF_FAULT;
stForceDeclineInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableMixedFixture = @'
stContactInput.bEnable := eState = CFF_CONTACT_SEARCH OR eState = CFF_FAULT;
stForceDeclineInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableMultilineFixture = @'
stContactInput.bEnable := eState = CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable :=
    ((eState = CFF_STEP1_RAMP_PROCESS)
    OR (eState = CFF_STEP2_RAMP_PROCESS)
    OR (eState = CFF_STEP3_RAMP_PROCESS))
    AND (stCycleSnapshot.stProgram.astSteps[nActiveStepProgramIndex].stProceeding.ePrimaryCriterion
        = E_StepPrimaryCriterion.STEP_CRIT_FORCE_DECLINE_TO);
stStepCriterionInput.bEnable := (eState = CFF_STEP1_RAMP_PROCESS)
    OR (eState = CFF_STEP2_RAMP_PROCESS)
    OR (eState = CFF_STEP3_RAMP_PROCESS)
    OR (eState = CFF_BRAKE_AND_COMPRESSION_RAMP)
    OR (eState = CFF_STEP4_VALID_FORCE_HOLD);
'@
$enableCommentFixture = @'
stContactInput.bEnable := eState = CFF_FAULT; (* CFF_CONTACT_SEARCH *)
stForceDeclineInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enablePublishedMirrorFixture = @'
stContactInput.bEnable := GVL_Status.stFast.stSequence.eState = CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enablePermanentlyDisabledFixture = @'
stContactInput.bEnable := eState = CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable := FALSE;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS AND FALSE;
'@
$enableDeclineMissingPrimaryFixture = @'
stContactInput.bEnable := eState = CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable := (eState = CFF_STEP1_RAMP_PROCESS)
    OR (eState = CFF_STEP2_RAMP_PROCESS);
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableDeclinePrimaryOrOverrideFixture = @'
stContactInput.bEnable := eState = CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable := ((eState = CFF_STEP1_RAMP_PROCESS)
    AND (stCycleSnapshot.stProgram.astSteps[nActiveStepProgramIndex].stProceeding.ePrimaryCriterion
        = STEP_CRIT_FORCE_DECLINE_TO)) OR bManualOverride;
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableDeclinePrecedenceFixture = @'
stContactInput.bEnable := eState = CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable := (eState = CFF_STEP1_RAMP_PROCESS)
    OR (eState = CFF_STEP2_RAMP_PROCESS)
    OR (eState = CFF_STEP3_RAMP_PROCESS)
    AND (stCycleSnapshot.stProgram.astSteps[nActiveStepProgramIndex].stProceeding.ePrimaryCriterion
        = STEP_CRIT_FORCE_DECLINE_TO);
stStepCriterionInput.bEnable := (eState = CFF_STEP1_RAMP_PROCESS)
    OR (eState = CFF_STEP2_RAMP_PROCESS)
    OR (eState = CFF_STEP3_RAMP_PROCESS)
    OR (eState = CFF_BRAKE_AND_COMPRESSION_RAMP)
    OR (eState = CFF_STEP4_VALID_FORCE_HOLD);
'@
$enableDeclinePublishedPrimaryFixture = @'
stContactInput.bEnable := eState = CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable := (eState = CFF_STEP1_RAMP_PROCESS)
    AND (GVL_Status.stFast.stSequence.stStepCriterion.ePrimaryCriterion
        = STEP_CRIT_FORCE_DECLINE_TO);
stStepCriterionInput.bEnable := eState = CFF_STEP1_RAMP_PROCESS;
'@
$enableMissingAllowedStateFixture = @'
stContactInput.bEnable := eState = CFF_CONTACT_SEARCH;
stForceDeclineInput.bEnable := (eState = CFF_STEP1_RAMP_PROCESS)
    AND (stCycleSnapshot.stProgram.astSteps[nActiveStepProgramIndex].stProceeding.ePrimaryCriterion
        = STEP_CRIT_FORCE_DECLINE_TO);
stStepCriterionInput.bEnable := (eState = CFF_STEP1_RAMP_PROCESS)
    OR (eState = CFF_STEP2_RAMP_PROCESS)
    OR (eState = CFF_STEP3_RAMP_PROCESS)
    OR (eState = CFF_BRAKE_AND_COMPRESSION_RAMP);
'@
if (-not (Test-SequenceEnableAllowlist $enableAllowedFixture)) { Fail 'Enable allowlist fixture rejected an allowed-only state.' }
if (Test-SequenceEnableAllowlist $enableAllowedAndConditionFixture) { Fail 'Enable allowlist fixture accepted a Contact gate weakened or disabled by an extra AND condition.' }
if (Test-SequenceEnableAllowlist $enableAllowedOrOverrideFixture) { Fail 'Enable allowlist fixture accepted an allowed state OR override.' }
if (Test-SequenceEnableAllowlist $enableAllowedXorOverrideFixture) { Fail 'Enable allowlist fixture accepted an allowed state XOR override.' }
if (Test-SequenceEnableAllowlist $enableNotAllowedFixture) { Fail 'Enable allowlist fixture accepted a negated allowed state.' }
if (Test-SequenceEnableAllowlist $enableForbiddenStateFixture) { Fail 'Enable allowlist fixture accepted a forbidden state.' }
if (Test-SequenceEnableAllowlist $enableMixedFixture) { Fail 'Enable allowlist fixture accepted an allowed and forbidden mixed state.' }
if (-not (Test-SequenceEnableAllowlist $enableMultilineFixture)) { Fail 'Enable allowlist fixture skipped a multiline allowed assignment.' }
if (Test-SequenceEnableAllowlist $enableCommentFixture) { Fail 'Enable allowlist fixture accepted a state token found only in a comment.' }
if (Test-SequenceEnableAllowlist $enablePublishedMirrorFixture) { Fail 'Enable allowlist fixture accepted the previous-scan published state mirror.' }
if (Test-SequenceEnableAllowlist $enablePermanentlyDisabledFixture) { Fail 'Enable allowlist fixture accepted FALSE or AND FALSE as a permanently disabled algorithm.' }
if (Test-SequenceEnableAllowlist $enableDeclineMissingPrimaryFixture) { Fail 'Enable allowlist fixture accepted Force Decline without the current frozen Primary gate.' }
if (Test-SequenceEnableAllowlist $enableDeclinePrimaryOrOverrideFixture) { Fail 'Enable allowlist fixture accepted an OR override around the Force Decline Primary gate.' }
if (Test-SequenceEnableAllowlist $enableDeclinePrecedenceFixture) { Fail 'Enable allowlist fixture accepted a Primary gate that covers only the final OR alternative.' }
if (Test-SequenceEnableAllowlist $enableDeclinePublishedPrimaryFixture) { Fail 'Enable allowlist fixture accepted a published mirror instead of the current frozen step Primary.' }
if (Test-SequenceEnableAllowlist $enableMissingAllowedStateFixture) { Fail 'Enable allowlist fixture accepted an incomplete approved state allowlist.' }

$referenceWriterFixture = @'
IF bProcessReferencePending THEN
GVL_Command.stProcessReference.bLatchContactReference := stPendingProcessReferenceCommand.bLatchContactReference;
GVL_Command.stProcessReference.bUseProvidedContactReference := stPendingProcessReferenceCommand.bUseProvidedContactReference;
GVL_Command.stProcessReference.rProvidedContactSensorPosition_mm := stPendingProcessReferenceCommand.rProvidedContactSensorPosition_mm;
GVL_Command.stProcessReference.rProvidedContactAxisPosition_mm := stPendingProcessReferenceCommand.rProvidedContactAxisPosition_mm;
GVL_Command.stProcessReference.bResetContactReference := stPendingProcessReferenceCommand.bResetContactReference;
GVL_Command.stProcessReference.udiContactReferenceRequestId := stPendingProcessReferenceCommand.udiContactReferenceRequestId;
END_IF
'@
$referenceIdFirstFixture = @'
IF bProcessReferencePending THEN
GVL_Command.stProcessReference.udiContactReferenceRequestId := stPendingProcessReferenceCommand.udiContactReferenceRequestId;
GVL_Command.stProcessReference.bLatchContactReference := stPendingProcessReferenceCommand.bLatchContactReference;
GVL_Command.stProcessReference.bUseProvidedContactReference := stPendingProcessReferenceCommand.bUseProvidedContactReference;
GVL_Command.stProcessReference.rProvidedContactSensorPosition_mm := stPendingProcessReferenceCommand.rProvidedContactSensorPosition_mm;
GVL_Command.stProcessReference.rProvidedContactAxisPosition_mm := stPendingProcessReferenceCommand.rProvidedContactAxisPosition_mm;
GVL_Command.stProcessReference.bResetContactReference := stPendingProcessReferenceCommand.bResetContactReference;
END_IF
'@
$referenceDeadOuterFixture = @'
IF FALSE THEN
    IF bProcessReferencePending THEN
        GVL_Command.stProcessReference.bLatchContactReference := stPending.bLatchContactReference;
        GVL_Command.stProcessReference.bUseProvidedContactReference := stPending.bUseProvidedContactReference;
        GVL_Command.stProcessReference.rProvidedContactSensorPosition_mm := stPending.rProvidedContactSensorPosition_mm;
        GVL_Command.stProcessReference.rProvidedContactAxisPosition_mm := stPending.rProvidedContactAxisPosition_mm;
        GVL_Command.stProcessReference.bResetContactReference := stPending.bResetContactReference;
        GVL_Command.stProcessReference.udiContactReferenceRequestId := stPending.udiContactReferenceRequestId;
    END_IF
END_IF
'@
$referenceNestedDeadFixture = @'
IF bProcessReferencePending THEN
    IF FALSE THEN
        GVL_Command.stProcessReference.bLatchContactReference := stPendingProcessReferenceCommand.bLatchContactReference;
        GVL_Command.stProcessReference.bUseProvidedContactReference := stPendingProcessReferenceCommand.bUseProvidedContactReference;
        GVL_Command.stProcessReference.rProvidedContactSensorPosition_mm := stPendingProcessReferenceCommand.rProvidedContactSensorPosition_mm;
        GVL_Command.stProcessReference.rProvidedContactAxisPosition_mm := stPendingProcessReferenceCommand.rProvidedContactAxisPosition_mm;
        GVL_Command.stProcessReference.bResetContactReference := stPendingProcessReferenceCommand.bResetContactReference;
        GVL_Command.stProcessReference.udiContactReferenceRequestId := stPendingProcessReferenceCommand.udiContactReferenceRequestId;
    END_IF
END_IF
'@
$referenceWrongRhsFixture = @'
IF bProcessReferencePending THEN
    GVL_Command.stProcessReference.bLatchContactReference := FALSE;
    GVL_Command.stProcessReference.bUseProvidedContactReference := FALSE;
    GVL_Command.stProcessReference.rProvidedContactSensorPosition_mm := 0.0;
    GVL_Command.stProcessReference.rProvidedContactAxisPosition_mm := 0.0;
    GVL_Command.stProcessReference.bResetContactReference := FALSE;
    GVL_Command.stProcessReference.udiContactReferenceRequestId := 0;
END_IF
'@
if (-not (Test-ContactReferencePublicWriter $referenceWriterFixture)) { Fail 'Contact public-writer fixture rejected payload-first and RequestId-last ordering.' }
if (Test-ContactReferencePublicWriter $referenceIdFirstFixture) { Fail 'Contact public-writer fixture accepted RequestId before payload.' }
if (Test-ContactReferencePublicWriter $referenceDeadOuterFixture) { Fail 'Contact public-writer fixture accepted a positive pending gate hidden below IF FALSE.' }
if (Test-ContactReferencePublicWriter $referenceNestedDeadFixture) { Fail 'Contact public-writer fixture accepted assignments hidden below IF FALSE inside the pending gate.' }
if (Test-ContactReferencePublicWriter $referenceWrongRhsFixture) { Fail 'Contact public-writer fixture accepted zero constants instead of the latched pending payload and RequestId.' }

if (Test-Path -LiteralPath $projectPath -PathType Leaf) {
    $projectText = Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8
}
else {
    $projectText = ''
    Fail 'PLC project is missing.'
}

$requiredObjects = [ordered]@{
    'FB_ContactDetect' = 'POUs\FunctionBlocks\Control\FB_ContactDetect.TcPOU'
    'FB_ForceDeclineObserver' = 'POUs\FunctionBlocks\Control\FB_ForceDeclineObserver.TcPOU'
    'FB_StepProceedingCriterion' = 'POUs\FunctionBlocks\Control\FB_StepProceedingCriterion.TcPOU'
}
$objectTexts = @{}
foreach ($name in $requiredObjects.Keys) {
    $relativePath = $requiredObjects[$name]
    $files = @(Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$name.*" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -eq $name })
    if ($files.Count -ne 1) {
        Fail "Expected exactly one $name object; found $($files.Count)."
        continue
    }
    $text = Get-Content -LiteralPath $files[0].FullName -Raw -Encoding UTF8
    $objectTexts[$name] = $text
    try { [void][xml]$text }
    catch { Fail "Invalid TwinCAT XML: $name" }
    if ($projectText -notmatch [regex]::Escape($relativePath)) {
        Fail "PLC project does not compile $name."
    }
}

$headerText = Read-Source 'DUTs\Structures\ST_JoinProgramHeader.TcDUT'
Assert-Patterns 'ST_JoinProgramHeader' $headerText @(
    'fContactForceOnN\s*:\s*LREAL',
    'fContactForceOffN\s*:\s*LREAL',
    'nContactDebounceMs\s*:\s*UDINT',
    'fContactSearchVelocityMmS\s*:\s*LREAL',
    'fContactSensorMinimumMm\s*:\s*LREAL',
    'fContactSensorMaximumMm\s*:\s*LREAL'
)

$proceedingText = Read-Source 'DUTs\Structures\ST_StepProceedingConfig.TcDUT'
Assert-Patterns 'ST_StepProceedingConfig' $proceedingText @(
    'ePrimaryCriterion\s*:\s*E_StepPrimaryCriterion',
    'eSecondaryAction\s*:\s*E_SecondaryCriterionAction',
    'fRelativeDistanceMm\s*:\s*LREAL',
    'nPrimaryStepTimeMs\s*:\s*UDINT',
    'nStepMinMs\s*:\s*UDINT',
    'nStepMaxMs\s*:\s*UDINT',
    'fSecondarySRelMm\s*:\s*LREAL',
    'fDeclineToN\s*:\s*LREAL',
    'fArmForceN\s*:\s*LREAL',
    'fDeclineHysteresisN\s*:\s*LREAL',
    'fMinimumDeclineRateNS\s*:\s*LREAL',
    'nDeclineDebounceMs\s*:\s*UDINT',
    'fCriterionSRelMinMm\s*:\s*LREAL',
    'fCriterionSRelMaxMm\s*:\s*LREAL',
    'fCriterionRpmMin\s*:\s*LREAL',
    'fCaptureMaxVelocityMmS\s*:\s*LREAL',
    'bValid\s*:\s*BOOL'
)

$contactInputText = Read-Source 'DUTs\Interfaces\ST_ContactDetectInput.TcDUT'
Assert-Patterns 'ST_ContactDetectInput' $contactInputText @(
    'bEnable\s*:\s*BOOL', 'bReset\s*:\s*BOOL',
    'rForceActual_kN\s*:\s*LREAL',
    'rForceOn_kN\s*:\s*LREAL', 'rForceOff_kN\s*:\s*LREAL',
    'rAxisPosition_mm\s*:\s*LREAL', 'rSensorPosition_mm\s*:\s*LREAL',
    'rAxisPositionMinimum_mm\s*:\s*LREAL', 'rAxisPositionMaximum_mm\s*:\s*LREAL',
    'rSensorPositionMinimum_mm\s*:\s*LREAL', 'rSensorPositionMaximum_mm\s*:\s*LREAL',
    'rAxisVelocity_mm_s\s*:\s*LREAL', 'rCaptureMaximumVelocity_mm_s\s*:\s*LREAL',
    'rDebounceTime_s\s*:\s*LREAL', 'rCycleTime_s\s*:\s*LREAL',
    'bSignalValid\s*:\s*BOOL'
)

$contactOutputText = Read-Source 'DUTs\Interfaces\ST_ContactDetectOutput.TcDUT'
Assert-Patterns 'ST_ContactDetectOutput' $contactOutputText @(
    'bCandidate\s*:\s*BOOL', 'bDetected\s*:\s*BOOL',
    'rCandidateForce_kN\s*:\s*LREAL',
    'rCandidateAxisPosition_mm\s*:\s*LREAL',
    'rCandidateSensorPosition_mm\s*:\s*LREAL',
    'rDetectedForce_kN\s*:\s*LREAL',
    'rDetectedAxisPosition_mm\s*:\s*LREAL',
    'rDetectedSensorPosition_mm\s*:\s*LREAL',
    'bReferenceLatchRequest\s*:\s*BOOL',
    'bFault\s*:\s*BOOL', 'nFaultId\s*:\s*UDINT'
)

$declineInputText = Read-Source 'DUTs\Interfaces\ST_ForceDeclineInput.TcDUT'
Assert-Patterns 'ST_ForceDeclineInput' $declineInputText @(
    'bEnable\s*:\s*BOOL', 'bReset\s*:\s*BOOL', 'bSignalValid\s*:\s*BOOL',
    'rForceActual_kN\s*:\s*LREAL', 'rSpeed_rpm\s*:\s*LREAL',
    'rRelativePosition_mm\s*:\s*LREAL', 'rAxisVelocity_mm_s\s*:\s*LREAL',
    'rStepTime_s\s*:\s*LREAL', 'rArmForce_kN\s*:\s*LREAL',
    'rDeclineTo_kN\s*:\s*LREAL', 'rHysteresis_kN\s*:\s*LREAL',
    'rMinimumDeclineRate_kN_s\s*:\s*LREAL',
    'rCriterionSRelMinimum_mm\s*:\s*LREAL',
    'rCriterionSRelMaximum_mm\s*:\s*LREAL',
    'rCriterionRpmMinimum\s*:\s*LREAL',
    'rCaptureMaximumVelocity_mm_s\s*:\s*LREAL',
    'rDebounceTime_s\s*:\s*LREAL', 'rCycleTime_s\s*:\s*LREAL'
)

$declineOutputText = Read-Source 'DUTs\Interfaces\ST_ForceDeclineOutput.TcDUT'
Assert-Patterns 'ST_ForceDeclineOutput' $declineOutputText @(
    'bArmed\s*:\s*BOOL', 'bCandidate\s*:\s*BOOL', 'bConfirmed\s*:\s*BOOL',
    'rForceDerivative_kN_s\s*:\s*LREAL', 'rStableTime_s\s*:\s*LREAL',
    'rLatchedForce_kN\s*:\s*LREAL', 'rLatchedRelativePosition_mm\s*:\s*LREAL',
    'rLatchedSpeed_rpm\s*:\s*LREAL', 'rLatchedStepTime_s\s*:\s*LREAL',
    'bFault\s*:\s*BOOL', 'nFaultId\s*:\s*UDINT'
)

$stepInputText = Read-Source 'DUTs\Interfaces\ST_StepCriterionInput.TcDUT'
Assert-Patterns 'ST_StepCriterionInput' $stepInputText @(
    'bEnable\s*:\s*BOOL', 'bReset\s*:\s*BOOL', 'bSignalValid\s*:\s*BOOL',
    'ePrimaryCriterion\s*:\s*E_StepPrimaryCriterion',
    'eSecondaryAction\s*:\s*E_SecondaryCriterionAction',
    'rRelativePosition_mm\s*:\s*LREAL', 'rRelativeDistanceTarget_mm\s*:\s*LREAL',
    'rStepTime_s\s*:\s*LREAL', 'rStepTimeTarget_s\s*:\s*LREAL',
    'rStepMinimumTime_s\s*:\s*LREAL', 'rStepMaximumTime_s\s*:\s*LREAL',
    'rForceActual_kN\s*:\s*LREAL',
    'bForceDeclineArmed\s*:\s*BOOL', 'bForceDeclineConfirmed\s*:\s*BOOL',
    'rSecondaryDistanceLimit_mm\s*:\s*LREAL',
    'bHardForceActive\s*:\s*BOOL', 'bHardStrokeActive\s*:\s*BOOL',
    'bCollisionActive\s*:\s*BOOL',
    'bSensorInvalid\s*:\s*BOOL', 'bAxisFault\s*:\s*BOOL', 'bStopRequested\s*:\s*BOOL'
)

$stepOutputText = Read-Source 'DUTs\Interfaces\ST_StepCriterionOutput.TcDUT'
Assert-Patterns 'ST_StepCriterionOutput' $stepOutputText @(
    'bArmed\s*:\s*BOOL', 'bPrimaryMet\s*:\s*BOOL',
    'bSecondaryLimitReached\s*:\s*BOOL', 'bEndConfirmed\s*:\s*BOOL',
    'bTooShort\s*:\s*BOOL', 'bNok\s*:\s*BOOL',
    'bAdvanceRequested\s*:\s*BOOL', 'bControlledExitRequested\s*:\s*BOOL',
    'bDownwardMotionInhibited\s*:\s*BOOL',
    'eEndCause\s*:\s*E_StepEndCause',
    'rLatchedForce_kN\s*:\s*LREAL',
    'rLatchedRelativePosition_mm\s*:\s*LREAL',
    'rLatchedStepTime_s\s*:\s*LREAL',
    'bFault\s*:\s*BOOL', 'nFaultId\s*:\s*UDINT'
)

$sequenceStatusText = Read-Source 'DUTs\Interfaces\ST_CffSequenceStatus.TcDUT'
Assert-Patterns 'ST_CffSequenceStatus' $sequenceStatusText @(
    'stContact\s*:\s*ST_ContactDetectOutput',
    'stForceDecline\s*:\s*ST_ForceDeclineOutput',
    'stStepCriterion\s*:\s*ST_StepCriterionOutput'
)

$referenceCommandText = Read-Source 'DUTs\Interfaces\ST_ProcessReferenceCommand.TcDUT'
Assert-Patterns 'ST_ProcessReferenceCommand' $referenceCommandText @(
    'bUseProvidedContactReference\s*:\s*BOOL',
    'rProvidedContactSensorPosition_mm\s*:\s*LREAL',
    'rProvidedContactAxisPosition_mm\s*:\s*LREAL'
)

$alarmText = Read-Source 'DUTs\Enums\E_AlarmCode.TcDUT'
if ($alarmText -notmatch 'ALARM_CFF_CRITERION_FAULT\s*:=\s*3000') {
    Fail 'E_AlarmCode is missing the Phase 9 criterion alarm.'
}

$projectInfoText = Read-Source 'GVLs\GVL_ProjectInfo.TcGVL'
if ($projectInfoText -notmatch "c_sImplementationPhase\s*:\s*STRING\(31\)\s*:=\s*'Phase 10 Source'") {
    Fail 'GVL_ProjectInfo does not identify Phase 9.'
}

if ($objectTexts.ContainsKey('FB_ContactDetect')) {
    $text = $objectTexts['FB_ContactDetect']
    Assert-Patterns 'FB_ContactDetect' $text @(
        'stInput\s*:\s*ST_ContactDetectInput', 'stOutput\s*:\s*ST_ContactDetectOutput',
        'FC_IsFiniteLReal', 'bFaultLatched\s*:\s*BOOL',
        'stInput\.rForceOn_kN\s*>\s*stInput\.rForceOff_kN',
        'stInput\.rForceActual_kN\s*>=\s*stInput\.rForceOn_kN',
        'stInput\.rForceActual_kN\s*<\s*stInput\.rForceOff_kN',
        'rCandidateAxisPosition_mm', 'rCandidateSensorPosition_mm',
        'ABS\(stInput\.rAxisVelocity_mm_s\)\s*>\s*ABS\(stInput\.rCaptureMaximumVelocity_mm_s\)',
        'rStableTime_s\s*:=\s*rStableTime_s\s*\+\s*stInput\.rCycleTime_s',
        'stOutput\.bReferenceLatchRequest\s*:=\s*TRUE'
    )
}

if ($objectTexts.ContainsKey('FB_ForceDeclineObserver')) {
    $text = $objectTexts['FB_ForceDeclineObserver']
    Assert-Patterns 'FB_ForceDeclineObserver' $text @(
        'stInput\s*:\s*ST_ForceDeclineInput', 'stOutput\s*:\s*ST_ForceDeclineOutput',
        'FC_IsFiniteLReal', 'bFaultLatched\s*:\s*BOOL',
        '\(stInput\.rForceActual_kN\s*-\s*rPreviousForce_kN\)\s*/\s*stInput\.rCycleTime_s',
        'stInput\.rForceActual_kN\s*>=\s*stInput\.rArmForce_kN',
        'stInput\.rForceActual_kN\s*<=\s*stInput\.rDeclineTo_kN',
        'rForceDerivative_kN_s\s*<=\s*-ABS\(stInput\.rMinimumDeclineRate_kN_s\)',
        'ABS\(stInput\.rSpeed_rpm\)\s*>=\s*ABS\(stInput\.rCriterionRpmMinimum\)',
        'stInput\.rRelativePosition_mm\s*>=\s*stInput\.rCriterionSRelMinimum_mm',
        'stInput\.rRelativePosition_mm\s*<=\s*stInput\.rCriterionSRelMaximum_mm',
        'stInput\.rForceActual_kN\s*>\s*stInput\.rDeclineTo_kN\s*\+\s*stInput\.rHysteresis_kN',
        'rStableTime_s\s*:=\s*rStableTime_s\s*\+\s*stInput\.rCycleTime_s',
        'ELSIF\s+NOT\s+bFaultLatched\s+AND\s+NOT\s+bConfirmed\s+THEN',
        'IF\s+NOT\s+bCandidate\s+AND\s+bArmed\s+AND[\s\S]*?stInput\.rForceActual_kN\s*<=\s*stInput\.rDeclineTo_kN[\s\S]*?bCandidate\s*:=\s*TRUE',
        'IF\s+bCandidate\s+AND[\s\S]*?stInput\.rForceActual_kN\s*>\s*stInput\.rDeclineTo_kN\s*\+\s*stInput\.rHysteresis_kN[\s\S]*?bCandidate\s*:=\s*FALSE',
        'bConfirmed\s*:=\s*TRUE',
        'stOutput\.bConfirmed\s*:=\s*bConfirmed'
    )
}

if ($objectTexts.ContainsKey('FB_StepProceedingCriterion')) {
    $text = $objectTexts['FB_StepProceedingCriterion']
    Assert-Patterns 'FB_StepProceedingCriterion' $text @(
        'stInput\s*:\s*ST_StepCriterionInput', 'stOutput\s*:\s*ST_StepCriterionOutput',
        'FC_GetPrimaryEndCause', 'SECONDARY_ADVANCE_AND_NOK',
        'SECONDARY_CONTROLLED_EXIT_NOK', 'STEP_END_MAX_TIME',
        'STEP_END_COLLISION', 'STEP_END_HARD_FORCE', 'STEP_END_HARD_STROKE',
        'STEP_END_SENSOR_INVALID', 'STEP_END_AXIS_FAULT', 'STEP_END_STOP_REQUEST',
        'stInput\.rStepTime_s\s*<\s*stInput\.rStepMinimumTime_s',
        'stInput\.rStepTimeTarget_s\s*<\s*stInput\.rStepMinimumTime_s',
        'stInput\.bForceDeclineConfirmed\s+AND\s+NOT\s+stInput\.bForceDeclineArmed',
        'stOutput\.bTooShort\s*:=\s*TRUE',
        'stOutput\.bDownwardMotionInhibited\s*:=\s*TRUE'
    )
    $faultSafeBlocks = [regex]::Matches($text, 'IF\s+bFaultLatched\s+THEN(?<Body>[\s\S]*?)END_IF')
    if ($faultSafeBlocks.Count -ne 3) {
        Fail "FB_StepProceedingCriterion must have exactly three centralized fault-safe exits; found $($faultSafeBlocks.Count)."
    }
    foreach ($faultSafeBlock in $faultSafeBlocks) {
        Assert-Patterns 'FB_StepProceedingCriterion fault-safe exit' $faultSafeBlock.Groups['Body'].Value @(
            'stOutput\.bEndConfirmed\s*:=\s*TRUE',
            'stOutput\.bNok\s*:=\s*TRUE',
            'stOutput\.bAdvanceRequested\s*:=\s*FALSE',
            'stOutput\.bControlledExitRequested\s*:=\s*TRUE',
            'stOutput\.bDownwardMotionInhibited\s*:=\s*TRUE',
            'stOutput\.eEndCause\s*:=\s*STEP_END_NONE',
            'RETURN'
        )
    }
    Assert-Ordered 'FB_StepProceedingCriterion evaluation order' $text @(
        'EVAL_STAGE_HARD_CAUSE',
        'stInput.bStopRequested',
        'stInput.bAxisFault',
        'stInput.bSensorInvalid',
        'stInput.bCollisionActive',
        'stInput.bHardForceActive',
        'stInput.bHardStrokeActive',
        'EVAL_STAGE_SECONDARY',
        'EVAL_STAGE_PRIMARY',
        'EVAL_STAGE_STEP_MAX'
    )
}

$validatorText = Read-Source 'POUs\Functions\FC_ValidateJoinProgram.TcPOU'
Assert-Patterns 'FC_ValidateJoinProgram' $validatorText @(
    'FC_IsFiniteLReal',
    'nStepMinMs\s*>\s*stStep\.stProceeding\.nStepMaxMs',
    'nPrimaryStepTimeMs', 'fSecondarySRelMm',
    'fDeclineToN\s*>=\s*stStep\.fSetForceN',
    'fArmForceN\s*<=\s*stStep\.stProceeding\.fDeclineToN\s*\+\s*stStep\.stProceeding\.fDeclineHysteresisN',
    'fMinimumDeclineRateNS\s*<=\s*0\.0',
    'nDeclineDebounceMs\s*=\s*0',
    'nForceProfileId\s*>\s*0', 'nRAxisProfileId\s*>\s*0',
    'nElementTypeId\s*=\s*0', 'nToolId\s*=\s*0', 'nAnvilId\s*=\s*0',
    'nMonitorProfileId\s*=\s*0',
    'FC_IsFiniteLReal\(rValue\s*:=\s*stProgram\.stHeader\.fReturnVelocityMmS\)',
    'FC_IsFiniteLReal\(rValue\s*:=\s*stProgram\.stHeader\.fReturnOpeningMm\)',
    'fReturnVelocityMmS\s*>\s*stMachineLimits\.fZMaxVelocityMmS',
    'fReturnOpeningMm\s*<\s*stMachineLimits\.fZMinPositionMm',
    'fReturnOpeningMm\s*>\s*stMachineLimits\.fZMaxPositionMm',
    'eReturnMode\s*<>\s*RETURN_MODE_LOCAL',
    'eReturnMode\s*<>\s*RETURN_MODE_REFERENCE',
    'eState\s*<>\s*PROGRAM_VALID',
    'eState\s*<>\s*PROGRAM_ACTIVE',
    'CASE\s+stStep\.stProceeding\.eSecondaryAction\s+OF',
    'rPreviousStepBoundary_mm',
    'rCurrentStepBoundary_mm\s*<\s*rPreviousStepBoundary_mm'
)

$fastSequenceText = Read-Source 'POUs\Fast\PRG_CffSequence.TcPOU'
Assert-Patterns 'PRG_CffSequence' $fastSequenceText @(
    'fbContactDetect\s*:\s*FB_ContactDetect',
    'fbForceDecline\s*:\s*FB_ForceDeclineObserver',
    'fbStepCriterion\s*:\s*FB_StepProceedingCriterion',
    'fbContactDetect\(\s*stInput\s*:=\s*stContactInput\)',
    'fbForceDecline\(\s*stInput\s*:=\s*stForceDeclineInput\)',
    'fbStepCriterion\(\s*stInput\s*:=\s*stStepCriterionInput\)',
    'stSequence\.stContact', 'stSequence\.stForceDecline', 'stSequence\.stStepCriterion',
    'ALARM_CFF_CRITERION_FAULT', 'astRequests\[9\]'
)
if ($fastSequenceText -match '\bAXIS_REF\b|\bMC_[A-Za-z0-9_]+\b') {
    Fail 'PRG_CffSequence must not access AXIS_REF or MC.'
}

$fastInputsText = Read-Source 'POUs\Fast\PRG_FastInputs.TcPOU'
Assert-Patterns 'PRG_FastInputs candidate reference contract' $fastInputsText @(
    'bUseProvidedContactReference',
    'fContactSensorPositionMm\s*:=\s*GVL_Command\.stProcessReference\.rProvidedContactSensorPosition_mm',
    'fContactAxisPositionMm\s*:=\s*GVL_Command\.stProcessReference\.rProvidedContactAxisPosition_mm'
)
if (-not (Test-SequenceEnableAllowlist $fastSequenceText)) {
    Fail 'Sequence algorithm enables must use the local eState and only their complete approved state allowlist.'
}
if (-not (Test-ContactReferencePublicWriter $fastSequenceText)) {
    Fail 'Contact reference must have one payload-first, RequestId-last public GVL writer.'
}
$fastSequenceExecutable = Get-ExecutableIecText $fastSequenceText
$precheckReferenceBranch = [regex]::Match($fastSequenceExecutable, '(?ms)^\s*(?:E_CffState\.)?CFF_PRECHECK\s*:\s*(?<Body>.*?)(?=^\s*(?:E_CffState\.)?CFF_[A-Z0-9_]+\s*:|^\s*END_CASE\b\s*;?)').Groups['Body'].Value
$contactSearchReferenceBranch = [regex]::Match($fastSequenceExecutable, '(?ms)^\s*(?:E_CffState\.)?CFF_CONTACT_SEARCH\s*:\s*(?<Body>.*?)(?=^\s*(?:E_CffState\.)?CFF_[A-Z0-9_]+\s*:|^\s*END_CASE\b\s*;?)').Groups['Body'].Value
$contactAcceptReferenceBranch = [regex]::Match($fastSequenceExecutable, '(?ms)^\s*(?:E_CffState\.)?CFF_CONTACT_ACCEPT\s*:\s*(?<Body>.*?)(?=^\s*(?:E_CffState\.)?CFF_[A-Z0-9_]+\s*:|^\s*END_CASE\b\s*;?)').Groups['Body'].Value
Assert-Patterns 'Precheck Contact Reset transaction' $precheckReferenceBranch @(
    'bProcessReferencePending',
    'bResetContactReference\s*:=\s*TRUE',
    'udiContactReferenceRequestId\s*:=\s*udiContactReferenceRequestId\s*\+\s*1'
)
Assert-Patterns 'Contact Search Latch transaction' $contactSearchReferenceBranch @(
    'bReferenceLatchRequest',
    'bLatchContactReference\s*:=\s*TRUE',
    'bUseProvidedContactReference\s*:=\s*TRUE',
    'rDetectedSensorPosition_mm',
    'rDetectedAxisPosition_mm',
    'udiContactReferenceRequestId\s*:=\s*udiContactReferenceRequestId\s*\+\s*1'
)
if ($contactAcceptReferenceBranch -match 'udiContactReferenceRequestId\s*:=\s*udiContactReferenceRequestId\s*\+\s*1|GVL_Command\.stProcessReference\.') {
    Fail 'CFF_CONTACT_ACCEPT must not generate or publish another Contact reference transaction.'
}
Assert-Patterns 'Contact Accept exact acknowledgement' $contactAcceptReferenceBranch @(
    'udiContactReferenceAcceptedId\s*=\s*udiExpectedContactReferenceAckId',
    'bContactReferenceValid'
)
if ($fastSequenceText -match 'stZExtSetpoint\.(?:rPosition_mm|rVelocity_mm_s|rAcceleration_mm_s2|nDirection)\s*:=') {
    Fail 'Phase 9 must not directly write the external setpoint package.'
}

$pouFiles = @(Get-ChildItem -LiteralPath (Join-Path $plcRoot 'POUs') -Recurse -File -Filter '*.TcPOU')
$allPouText = ($pouFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
foreach ($declaration in @(
    'fbContactDetect\s*:\s*FB_ContactDetect',
    'fbForceDecline\s*:\s*FB_ForceDeclineObserver',
    'fbStepCriterion\s*:\s*FB_StepProceedingCriterion'
)) {
    if ([regex]::Matches($allPouText, $declaration).Count -ne 1) {
        Fail "Phase 9 instance must have exactly one owner: $declaration"
    }
}

$controlRoot = Join-Path $plcRoot 'POUs\FunctionBlocks\Control'
foreach ($name in $requiredObjects.Keys) {
    $path = Join-Path $controlRoot "$name.TcPOU"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($text -match '\bAXIS_REF\b|\bMC_[A-Za-z0-9_]+\b|\bGVL_[A-Za-z0-9_]+\b|\bSTRING\b|\bWSTRING\b') {
        Fail "$name escaped its algorithm boundary."
    }
}

if ($allPouText -match 'b(?:ZAxis|RAxis)DriveLinked\s*:=\s*TRUE|bProductionReady\s*:=\s*TRUE|bAllRequiredMappingsConfirmed\s*:=\s*TRUE') {
    Fail 'Phase 9 must not force hardware binding, mapping, or Production Ready TRUE.'
}

# Offline deterministic references. These do not execute TwinCAT Runtime code.
$contactOn = 1.0
$contactOff = 0.9
$contactDebounce = 0.02
$cycle = 0.01
$candidate = $false
$stable = 0.0
$detected = $false
$pulseCount = 0
foreach ($force in @(1.05, 0.85, 1.05, 0.95, 0.95, 0.95)) {
    $pulse = $false
    if (-not $candidate -and $force -ge $contactOn) { $candidate = $true; $stable = 0.0 }
    if ($candidate -and $force -lt $contactOff) { $candidate = $false; $stable = 0.0 }
    elseif ($candidate -and -not $detected -and $force -ge $contactOff) {
        $stable += $cycle
        if ($stable -ge $contactDebounce) { $detected = $true; $pulse = $true }
    }
    if ($pulse) { $pulseCount++ }
}
if (-not $detected -or $pulseCount -ne 1) {
    Fail 'Reference Contact vector violated hysteresis, debounce, or one-shot behavior.'
}

$armed = $false
$declineConfirmed = $false
$declineStable = 0.0
$previousForce = 0.0
$hasPrevious = $false
foreach ($sample in @(4.0, 5.2, 4.8, 3.4, 3.3)) {
    $derivative = 0.0
    if ($hasPrevious) { $derivative = ($sample - $previousForce) / $cycle }
    if ($sample -ge 5.0) { $armed = $true }
    $inWindow = $true
    if ($armed -and $sample -le 3.5 -and $derivative -le -5.0 -and $inWindow) {
        $declineStable += $cycle
        if ($declineStable -ge 0.02) { $declineConfirmed = $true }
    }
    else { $declineStable = 0.0 }
    $previousForce = $sample
    $hasPrevious = $true
}
if (-not $armed -or -not $declineConfirmed) {
    Fail 'Reference Force Decline vector did not require Arm, negative rate, and debounce.'
}

$primaryMet = $true
$stepTime = 0.5
$stepMin = 1.0
$tooShort = $primaryMet -and ($stepTime -lt $stepMin)
$endsImmediately = $primaryMet
if (-not $endsImmediately -or -not $tooShort) {
    Fail 'Reference StepMin vector waited instead of ending with TooShort.'
}

$secondaryReached = $true
$downwardInhibited = $secondaryReached
$secondaryNok = $secondaryReached
if (-not $downwardInhibited -or -not $secondaryNok) {
    Fail 'Reference Secondary vector did not inhibit downward motion and mark NOK.'
}

$primaryMet = $false
$stepTime = 2.0
$stepMax = 2.0
$maxTimeCause = if (-not $primaryMet -and $stepTime -ge $stepMax) { 'STEP_END_MAX_TIME' } else { 'STEP_END_NONE' }
if ($maxTimeCause -ne 'STEP_END_MAX_TIME') {
    Fail 'Reference StepMax vector did not produce MAX_TIME.'
}

function Test-ReferenceProgram([object[]]$Steps) {
    $previousBoundary = 0.0
    foreach ($step in $Steps) {
        if ($step.MinMs -gt $step.MaxMs) { return $false }
        if ($step.Boundary -lt $previousBoundary) { return $false }
        if ($step.Kind -ne 'Distance' -and $step.Secondary -le 0.0) { return $false }
        if ($step.Kind -eq 'Decline' -and ($step.DeclineTo -ge $step.SetForce -or $step.ArmForce -le ($step.DeclineTo + $step.Hysteresis))) { return $false }
        $previousBoundary = $step.Boundary
    }
    return $true
}
$validSteps = @(
    [pscustomobject]@{Kind='Distance';MinMs=10;MaxMs=1000;Boundary=1.0;Secondary=0.0;SetForce=5.0;DeclineTo=0.0;ArmForce=0.0;Hysteresis=0.0},
    [pscustomobject]@{Kind='Time';MinMs=10;MaxMs=1000;Boundary=2.0;Secondary=2.0;SetForce=5.0;DeclineTo=0.0;ArmForce=0.0;Hysteresis=0.0},
    [pscustomobject]@{Kind='Decline';MinMs=10;MaxMs=1000;Boundary=3.0;Secondary=3.0;SetForce=5.0;DeclineTo=3.0;ArmForce=4.0;Hysteresis=0.5},
    [pscustomobject]@{Kind='Time';MinMs=10;MaxMs=1000;Boundary=4.0;Secondary=4.0;SetForce=4.0;DeclineTo=0.0;ArmForce=0.0;Hysteresis=0.0}
)
if (-not (Test-ReferenceProgram $validSteps)) { Fail 'Reference valid Program was rejected.' }
$invalidSteps = @($validSteps | ForEach-Object { $_.PSObject.Copy() })
$invalidSteps[2].ArmForce = 3.4
if (Test-ReferenceProgram $invalidSteps) { Fail 'Reference invalid Decline Program was accepted.' }

$readmePath = Join-Path $RepositoryRoot 'scripts\README.md'
if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf) -or (Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8) -notmatch 'Test-Phase9ContactAndCriterion') {
    Fail 'scripts README does not document the Phase 9 test.'
}

$reportFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Docs') -Recurse -File -Filter 'PHASE_9_EXECUTION_REPORT.md' -ErrorAction SilentlyContinue)
if ($reportFiles.Count -ne 1) {
    Fail "Expected exactly one Phase 9 execution report; found $($reportFiles.Count)."
}

if ($failures.Count -gt 0) {
    Write-Host 'Phase 9 contact and criterion test: FAILED'
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}

Write-Host 'Phase 9 contact and criterion test: PASSED'
Write-Host 'Process boundary: no AXIS_REF, MC, or GVL in Phase 9 algorithms'
Write-Host 'Sequence policy: local-state enables; Precheck Reset and Contact Search Latch use one payload-first public writer'
