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
if ($projectInfoText -notmatch "c_sImplementationPhase\s*:\s*STRING\(31\)\s*:=\s*'Phase 9'") {
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
        'STEP_END_HARD_FORCE', 'STEP_END_HARD_STROKE',
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
    'nForceProfileId\s*=\s*0', 'nRAxisProfileId\s*=\s*0',
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
    'stContactInput\.bEnable\s*:=\s*FALSE',
    'stForceDeclineInput\.bEnable\s*:=\s*FALSE',
    'stStepCriterionInput\.bEnable\s*:=\s*FALSE',
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
if ($fastSequenceText -match 'stProcessReference\.udiContactReferenceRequestId\s*:=|stSequence\.bForceControlEnable\s*:=\s*TRUE|stZExtSetpoint\.(?:rPosition_mm|rVelocity_mm_s|rAcceleration_mm_s2|nDirection)\s*:=') {
    Fail 'Phase 9 crossed the Phase 10 sequence or trajectory boundary.'
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
Write-Host 'Default policy: Phase 10 sequence enables remain disabled'
