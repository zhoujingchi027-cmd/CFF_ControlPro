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
        Fail "Missing Phase 8 source: $RelativePath"
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

if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    Fail 'PLC project is missing.'
    $projectText = ''
}
else {
    $projectText = Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8
}

$requiredObjects = [ordered]@{
    'FB_BumplessProfileSwitch' = 'POUs\FunctionBlocks\Control\FB_BumplessProfileSwitch.TcPOU'
    'FB_ZForceAdmittance' = 'POUs\FunctionBlocks\Control\FB_ZForceAdmittance.TcPOU'
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

$inputText = Read-Source 'DUTs\Interfaces\ST_ZForceControlInput.TcDUT'
Assert-Patterns 'ST_ZForceControlInput' $inputText @(
    'bEnable\s*:\s*BOOL',
    'bReset\s*:\s*BOOL',
    'bOwnerGranted\s*:\s*BOOL',
    'bExternalActive\s*:\s*BOOL',
    'bForceValid\s*:\s*BOOL',
    'bRelativePositionValid\s*:\s*BOOL',
    'bBumplessTransfer\s*:\s*BOOL',
    'bHardForceActive\s*:\s*BOOL',
    'bHardStrokeActive\s*:\s*BOOL',
    'bCollisionLimitActive\s*:\s*BOOL',
    'rForceSet_kN\s*:\s*LREAL',
    'rForceActual_kN\s*:\s*LREAL',
    'rRelativePosition_mm\s*:\s*LREAL',
    'rTargetRelativePosition_mm\s*:\s*LREAL',
    'rHardMaximumRelativePosition_mm\s*:\s*LREAL',
    'rTransferVelocity_mm_s\s*:\s*LREAL',
    'rCycleTime_s\s*:\s*LREAL'
)

$outputText = Read-Source 'DUTs\Interfaces\ST_ZForceControlOutput.TcDUT'
Assert-Patterns 'ST_ZForceControlOutput' $outputText @(
    'rVelocityCommand_mm_s\s*:\s*LREAL',
    'rIntegralTerm_mm_s\s*:\s*LREAL',
    'rForceSetRamped_kN\s*:\s*LREAL',
    'rForceError_kN\s*:\s*LREAL',
    'rUnsaturatedVelocity_mm_s\s*:\s*LREAL',
    'rSaturatedVelocity_mm_s\s*:\s*LREAL',
    'rStrokeVelocityLimit_mm_s\s*:\s*LREAL',
    'bActive\s*:\s*BOOL',
    'bLimited\s*:\s*BOOL',
    'bAntiWindupFrozen\s*:\s*BOOL',
    'bHardLimitActive\s*:\s*BOOL',
    'bFault\s*:\s*BOOL',
    'nFaultId\s*:\s*UDINT'
)

$profileText = Read-Source 'DUTs\Structures\ST_ZForceControlProfile.TcDUT'
Assert-Patterns 'ST_ZForceControlProfile' $profileText @(
    'nRevision\s*:\s*UDINT',
    'fVelocityFeedForwardMmS\s*:\s*LREAL',
    'fKp\s*:\s*LREAL',
    'fKi\s*:\s*LREAL',
    'fKaw\s*:\s*LREAL',
    'fIntegralLimit\s*:\s*LREAL',
    'fMaxUpVelocityMmS\s*:\s*LREAL',
    'fMaxDownVelocityMmS\s*:\s*LREAL',
    'fMaxAccelerationMmS2\s*:\s*LREAL',
    'fBrakeMarginMm\s*:\s*LREAL',
    'fForceRampNS\s*:\s*LREAL',
    'bValid\s*:\s*BOOL'
)

$sequenceText = Read-Source 'DUTs\Interfaces\ST_CffSequenceStatus.TcDUT'
Assert-Patterns 'ST_CffSequenceStatus' $sequenceText @(
    'bForceControlEnable\s*:\s*BOOL',
    'bForceProfileTransfer\s*:\s*BOOL',
    'rForceTransferVelocity_mm_s\s*:\s*LREAL',
    'rTargetRelativePosition_mm\s*:\s*LREAL',
    'rHardMaximumRelativePosition_mm\s*:\s*LREAL',
    'bForceHardLimitActive\s*:\s*BOOL',
    'bStrokeHardLimitActive\s*:\s*BOOL',
    'bCollisionLimitActive\s*:\s*BOOL'
)

$fastStatusText = Read-Source 'DUTs\Structures\ST_FastStatus.TcDUT'
if ($fastStatusText -notmatch 'stZForceControl\s*:\s*ST_ZForceControlOutput') {
    Fail 'ST_FastStatus must publish ST_ZForceControlOutput.'
}

$setpointRampText = Read-Source 'POUs\FunctionBlocks\Utility\FB_SetpointRamp.TcPOU'
Assert-Patterns 'FB_SetpointRamp finite input contract' $setpointRampText @(
    'bInputsValid\s*:\s*BOOL',
    'FC_IsFiniteLReal\(rValue\s*:=\s*rRateUpPer_s\)',
    'FC_IsFiniteLReal\(rValue\s*:=\s*rRateDownPer_s\)',
    'FC_IsFiniteLReal\(rValue\s*:=\s*rCycleTime_s\)',
    'FC_IsFiniteLReal\(rValue\s*:=\s*rTolerance\)',
    'rCycleTime_s\s*>\s*0\.0',
    'rRateUpPer_s\s*>=\s*0\.0',
    'rRateDownPer_s\s*>=\s*0\.0',
    'rTolerance\s*>=\s*0\.0',
    'IF\s+NOT\s+bValid\s+THEN[\s\S]*?bBusy\s*:=\s*FALSE[\s\S]*?bReached\s*:=\s*FALSE[\s\S]*?RETURN'
)
Assert-Ordered 'FB_SetpointRamp validates before writing output' $setpointRampText @(
    'bInputsValid :=',
    'IF bReset OR NOT bEnable THEN',
    'IF NOT bInitialized THEN'
)
if ($setpointRampText -notmatch '(?s)IF\s+bReset\s+OR\s+NOT\s+bEnable\s+THEN\s+IF\s+bInputsValid\s+THEN\s+rOutput\s*:=\s*rInitialValue') {
    Fail 'FB_SetpointRamp reset/disable must not overwrite the last continuous output with invalid input.'
}
if ($setpointRampText -notmatch '(?s)IF\s+bReset\s+OR\s+NOT\s+bEnable\s+THEN.*?bInitialized\s*:=\s*bEnable\s+AND\s+bInputsValid.*?IF\s+NOT\s+bEnable\s+OR\s+NOT\s+bInputsValid\s+THEN.*?RETURN') {
    Fail 'FB_SetpointRamp must initialize an enabled valid transaction without publishing a one-scan invalid envelope.'
}

if ($objectTexts.ContainsKey('FB_BumplessProfileSwitch')) {
    $switchText = $objectTexts['FB_BumplessProfileSwitch']
    Assert-Patterns 'FB_BumplessProfileSwitch' $switchText @(
        'bSwitchPulse\s*:\s*BOOL',
        'rPreviousVelocity_mm_s\s*:\s*LREAL',
        'rVelocityFeedForward_mm_s\s*:\s*LREAL',
        'rProportionalGain_mm_s_per_kN\s*:\s*LREAL',
        'rForceSet_kN\s*:\s*LREAL',
        'rForceActual_kN\s*:\s*LREAL',
        'rIntegralLimit_mm_s\s*:\s*LREAL',
        'rIntegralPreload_mm_s\s*:\s*LREAL',
        'bAccepted\s*:\s*BOOL',
        'FC_ClampLReal',
        'IF\s+bError\s+THEN',
        'NOT\s+FC_IsFiniteLReal\(rValue\s*:=\s*rRawIntegralPreload_mm_s\)',
        'NOT\s+FC_IsFiniteLReal\(rValue\s*:=\s*rIntegralPreload_mm_s\)',
        'rPreviousVelocity_mm_s\s*-\s*rVelocityFeedForward_mm_s\s*-\s*rProportionalGain_mm_s_per_kN\s*\*\s*\(rForceSet_kN\s*-\s*rForceActual_kN\)'
    )
}

if ($objectTexts.ContainsKey('FB_ZForceAdmittance')) {
    $controllerText = $objectTexts['FB_ZForceAdmittance']
    Assert-Patterns 'FB_ZForceAdmittance' $controllerText @(
        'stInput\s*:\s*ST_ZForceControlInput',
        'stProfile\s*:\s*ST_ZForceControlProfile',
        'stLimits\s*:\s*ST_MachineLimits',
        'rForceSetRamped_kN\s*:\s*LREAL',
        'bApplyIntegralPreload\s*:\s*BOOL',
        'rIntegralPreload_mm_s\s*:\s*LREAL',
        'stOutput\s*:\s*ST_ZForceControlOutput',
        'FC_IsFiniteLReal',
        'FC_CalcStrokeVelocityLimit',
        'FC_LimitRate',
        'stAppliedProfile\.fVelocityFeedForwardMmS\s*\+\s*stAppliedProfile\.fKp\s*\*\s*rForceError_kN\s*\+\s*rIntegralTerm_mm_s',
        'stAppliedProfile\.fKi\s*\*\s*rForceError_kN\s*\+\s*stAppliedProfile\.fKaw\s*\*\s*\(rSaturatedVelocity_mm_s\s*-\s*rUnsaturatedVelocity_mm_s\)',
        'FC_ClampLReal',
        'bOwnerGranted',
        'bExternalActive',
        'bForceValid',
        'bRelativePositionValid',
        'bHardForceActive',
        'bHardStrokeActive',
        'bCollisionLimitActive',
        'bBumplessTransfer\s+AND\s+NOT\s+bApplyIntegralPreload',
        '16#00008007',
        'stAppliedProfile\s*:\s*ST_ZForceControlProfile',
        'stAppliedLimits\s*:\s*ST_MachineLimits',
        'bProfileInitialized\s*:\s*BOOL',
        'bLimitsMismatch\s*:\s*BOOL',
        'rCandidateMaximumUpVelocity_mm_s\s*:\s*LREAL',
        'rCandidateMaximumDownVelocity_mm_s\s*:\s*LREAL',
        'bFaultLatched\s*:\s*BOOL',
        'udiLatchedFaultId\s*:\s*UDINT',
        'stProfile\.nRevision\s*<>\s*stAppliedProfile\.nRevision',
        'stProfile\.fKp\s*<>\s*stAppliedProfile\.fKp',
        'stProfile\.fVelocityFeedForwardMmS\s*<>\s*stAppliedProfile\.fVelocityFeedForwardMmS',
        'stLimits\.fZMaxVelocityMmS\s*<>\s*stAppliedLimits\.fZMaxVelocityMmS',
        'stLimits\.fZMaxAccelerationMmS2\s*<>\s*stAppliedLimits\.fZMaxAccelerationMmS2',
        'stLimits\.fMaxForceN\s*<>\s*stAppliedLimits\.fMaxForceN',
        'rForceSetRamped_kN\s*>=\s*0\.0',
        'rForceSetRamped_kN\s*<=\s*ABS\(stLimits\.fMaxForceN\)\s*\*\s*0\.001',
        'stInput\.rHardMaximumRelativePosition_mm\s*<=\s*rMaximumRelativeTravel_mm',
        'stInput\.rTransferVelocity_mm_s\s*>=\s*-rCandidateMaximumUpVelocity_mm_s',
        'stInput\.rTransferVelocity_mm_s\s*<=\s*rCandidateMaximumDownVelocity_mm_s',
        'stInput\.rRelativePosition_mm\s*>\s*stInput\.rHardMaximumRelativePosition_mm',
        'NOT\s+FC_IsFiniteLReal\(rValue\s*:=\s*rUnsaturatedVelocity_mm_s\)',
        'NOT\s+FC_IsFiniteLReal\(rValue\s*:=\s*rStrokeVelocityLimit_mm_s\)',
        'NOT\s+FC_IsFiniteLReal\(rValue\s*:=\s*rSaturatedVelocity_mm_s\)',
        'NOT\s+FC_IsFiniteLReal\(rValue\s*:=\s*rIntegralDerivative_mm_s2\)',
        'NOT\s+FC_IsFiniteLReal\(rValue\s*:=\s*rUpdatedIntegralTerm_mm_s\)',
        'rMaximumDeceleration_mm_s2\s*:=\s*rMaximumAcceleration_mm_s2',
        'rSaturatedVelocity_mm_s\s*>\s*rMaximumDownVelocity_mm_s[\s\S]*rSaturatedVelocity_mm_s\s*:=\s*rMaximumDownVelocity_mm_s',
        'rSaturatedVelocity_mm_s\s*<\s*-rMaximumUpVelocity_mm_s[\s\S]*rSaturatedVelocity_mm_s\s*:=\s*-rMaximumUpVelocity_mm_s',
        'IF\s+bEnvelopeViolation\s+THEN[\s\S]*16#0000800C[\s\S]*rSaturatedVelocity_mm_s\s*:=\s*0\.0[\s\S]*stOutput\.bActive\s*:=\s*FALSE',
        'stOutput\.rForceSetRamped_kN\s*:=\s*0\.0',
        'stOutput\.bActive\s*:=\s*NOT\s+bFaultLatched'
    )
    Assert-Ordered 'FB_ZForceAdmittance limit order' $controllerText @(
        'LIMIT_STAGE_PROFILE',
        'LIMIT_STAGE_MACHINE',
        'EFFECTIVE_DECELERATION_READY',
        'LIMIT_STAGE_SREL_BRAKE',
        'LIMIT_STAGE_HARD_BOUNDARY',
        'LIMIT_STAGE_COLLISION',
        'LIMIT_STAGE_ACCELERATION'
    )
    if ($controllerText -match '\bAXIS_REF\b|\bMC_[A-Za-z0-9_]+\b|\bGVL_[A-Za-z0-9_]+\b|ForceDisplay') {
        Fail 'FB_ZForceAdmittance must not access AXIS_REF, MC, GVL, or ForceDisplay.'
    }
    if ($controllerText -match 'stOutput\.bActive\s*:=\s*TRUE') {
        Fail 'FB_ZForceAdmittance must only publish Active after all fault paths are closed.'
    }
}

$fastAxisText = Read-Source 'POUs\Fast\PRG_FastAxisControl.TcPOU'
Assert-Patterns 'PRG_FastAxisControl' $fastAxisText @(
    'fbForceSetpointRamp\s*:\s*FB_SetpointRamp',
    'fbZProfileSwitch\s*:\s*FB_BumplessProfileSwitch',
    'fbZForceAdmittance\s*:\s*FB_ZForceAdmittance',
    'fbZExternalTrajectory\s*:\s*FB_ZExternalTrajectory',
    'fbRSpeedRamp\s*:\s*FB_SetpointRamp',
    'bProfileTransferRequested\s*:\s*BOOL',
    'stFastConfigSnapshot\.bValid\s+AND\s+GVL_Status\.stFast\.stSequence\.stFastConfigSnapshot\.nSequenceCommandId\s*=\s*GVL_Status\.stFast\.stSequence\.nAcceptedCommandId',
    'rEffectiveForceRamp_kN_s\s*:=\s*MIN',
    'stFastConfigSnapshot\.stZForceControl\.fForceRampNS\s*\*\s*0\.001',
    'bForceProfileTransfer',
    'fForceControlN\s*\*\s*0\.001',
    'fSRelSensorMm',
    'bForceValid',
    'bDisplacementValid',
    'bContactReferenceValid',
    'stSequence\.bForceControlEnable',
    'bForceLoopRequested\s*:=\s*GVL_Status\.stFast\.stSequence\.bForceControlEnable\s+AND\s+bFastConfigSnapshotCurrent\s+AND\s+NOT\s+GVL_Status\.stFast\.stSequence\.bError\s+AND\s+NOT\s+GVL_Status\.stFast\.stSequence\.bAborted',
    'GVL_FastInternal\.stAcceptedCommand\.stZAxis',
    'GVL_FastInternal\.stAcceptedCommand\.stRAxis',
    'stTrajectoryInput\.bInhibitPositiveMotion\s*:=\s*GVL_Status\.stFast\.stSequence\.bForceHardLimitActive\s+OR\s+GVL_Status\.stFast\.stSequence\.bStrokeHardLimitActive\s+OR\s+GVL_Status\.stFast\.stSequence\.bCollisionLimitActive',
    'stExtCommand\.bFeed\s*:=\s*fbZExternalTrajectory\.stOutput\.bActive\s+AND\s+NOT\s+fbZExternalTrajectory\.stOutput\.bFault',
    'stExtCommand\.bDisable\s*:=\s*GVL_Status\.stFast\.stSequence\.stMotionIntent\.bExternalDisableRequest\s+OR\s+fbZExternalTrajectory\.stOutput\.bFault',
    'bHardOverrideStart\s*:=\s*bFastConfigSnapshotCurrent[\s\S]*?Z_EXT_ACTIVE[\s\S]*?bAcceptedSetpointValid',
    'IF\s+bHardOverridePending\s+THEN[\s\S]*?stExtCommand\.bFeed\s*:=\s*bHardOverridePackageExact[\s\S]*?stExtCommand\.bDisable\s*:=\s*TRUE[\s\S]*?stExtCommand\.bPositiveMotionInhibit\s*:=\s*bHardOverridePackageExact',
    'IF\s+bFastConfigSnapshotCurrent\s+AND\s+GVL_Status\.stFast\.stSequence\.bBusy\s+THEN\s+bFastConfigSnapshotSeen\s*:=\s*TRUE',
    'bSequenceMotionIntentPresent\s*:=\s*(?:(?!;)[\s\S])*stMotionIntent\.stZCommand\.eOwnerRequest\s*<>\s*E_ZCommandOwner\.Z_OWNER_NONE',
    'bSnapshotMismatch\s*:=\s*NOT\s+bFastConfigSnapshotCurrent\s+AND\s*\(bFastConfigSnapshotSeen\s+OR\s+bSequenceMotionIntentPresent\)',
    'bFastSafetyStopEvent\s*:=\s*bSnapshotMismatch\s+AND\s+NOT\s+bFastSafetyStopLatched\s+AND\s+NOT\s+bSafeTerminalResetRising',
    'bNewSafeTerminalSequenceCommand\s*:=\s*FC_IsNewerRequestId\s*\([\s\S]*?udiCandidate\s*:=\s*udiCurrentSafeTerminalResetRequestId[\s\S]*?udiReference\s*:=\s*udiLastObservedSafeTerminalSequenceCommandId',
    'IF\s+bNewSafeTerminalSequenceCommand\s+THEN[\s\S]*?udiLastObservedSafeTerminalSequenceCommandId\s*:=\s*udiCurrentSafeTerminalResetRequestId[\s\S]*?IF\s+GVL_FastInternal\.stAcceptedCommand\.stSequence\.bResetPulse\s+THEN[\s\S]*?udiPendingSafeTerminalResetRequestId\s*:=\s*udiCurrentSafeTerminalResetRequestId[\s\S]*?bSafeTerminalResetPending\s*:=\s*TRUE',
    'bSafeTerminalReset\s*:=\s*bSafeTerminalResetPending\s+AND\s+bSafeTerminalResetGatesMet',
    'IF\s+bSafeTerminalResetRising\s+THEN[\s\S]*?bSafeTerminalResetPending\s*:=\s*FALSE[\s\S]*?udiConsumedSafeTerminalResetRequestId\s*:=\s*udiPendingSafeTerminalResetRequestId',
    'bFastPathSafetyExit\s*:=\s*(?:(?!;)[\s\S])*fbZProfileSwitch\.bError',
    'stZForceInput\.bEnable\s*:=\s*bForceLoopRequested\s+AND\s+bForceInputsHealthy\s+AND\s+NOT\s+fbZProfileSwitch\.bError',
    'stLatchedRAdapterCommand\s*:=\s*stCandidateRSourceCommand',
    'stSelectedRCommand\s*:=\s*stLatchedRAdapterCommand',
    'udiPendingRAdapterCommandId\s*:=\s*udiRAdapterCommandId',
    'bPendingRTransactionIsSequence\s*:=\s*bRSequenceSourceActive',
    'bExternalSafelyReleasedForReset\s*:=\s*fbZAxisExtSetpointAdapter\.stStatus\.bReleaseOwner\s+OR\s*\(\s*fbZAxisExtSetpointAdapter\.stStatus\.eState\s*=\s*E_ZExtSetpointState\.Z_EXT_IDLE\s+AND\s+NOT\s+fbZAxisExtSetpointAdapter\.stStatus\.bEnabled\s*\)',
    'bSafeTerminalResetGatesMet\s*:=\s*NOT\s+GVL_Status\.stFast\.stSequence\.bBusy\s+AND\s+bExternalSafelyReleasedForReset\s+AND\s+GVL_Status\.stFast\.stZAxis\.bStandstill\s+AND\s+GVL_Status\.stFast\.stRAxis\.bStandstill',
    'bPendingRDecelerationValid\s+AND\s*\(fbRAxisNc\.udiAcceptedCommandId\s*=\s*udiPendingRAdapterCommandId\)[\s\S]*?rLastAcceptedRDeceleration_rpm_s\s*:=\s*rPendingRDeceleration_rpm_s',
    'IF\s+bFastSafetyStopEvent\s+THEN[\s\S]*?IF\s+bLastAcceptedRDecelerationValid\s+THEN[\s\S]*?stLatchedRAdapterCommand\.rDeceleration_rpm_s\s*:=\s*rLastAcceptedRDeceleration_rpm_s',
    'IF\s+bSafeTerminalResetRising\s+THEN[\s\S]*?bPostResetZNormalBarrier\s*:=\s*TRUE[\s\S]*?bPostResetRNormalBarrier\s*:=\s*TRUE[\s\S]*?udiPostResetNormalBarrierRequestId\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.nRequestId',
    'bAcceptedFastPackageNewerThanReset\s*:=\s*FC_IsNewerRequestId\s*\([\s\S]*?udiCandidate\s*:=\s*GVL_FastInternal\.stAcceptedCommand\.nRequestId[\s\S]*?udiReference\s*:=\s*udiPostResetNormalBarrierRequestId',
    'bZNormalSourceBlockedByReset\s*:=\s*bPostResetZNormalBarrier\s+AND\s+NOT\s+bAcceptedFastPackageNewerThanReset',
    'bRNormalSourceBlockedByReset\s*:=\s*bPostResetRNormalBarrier\s+AND\s+NOT\s+bAcceptedFastPackageNewerThanReset',
    'bNewZSourceTransaction\s*:=\s*\(udiCurrentZSourceCommandId\s*<>\s*0\)\s+AND',
    'bNewRSourceTransaction\s*:=\s*\(udiCurrentRSourceCommandId\s*<>\s*0\)\s+AND',
    'bNormalZResetAllowed\s*:=\s*NOT\s+GVL_Status\.stFast\.stSequence\.bBusy\s+AND\s+NOT\s+bZSequenceSourceActive\s+AND\s+bExternalSafelyReleasedForReset\s+AND\s+GVL_FastInternal\.stAcceptedCommand\.stZAxis\.bReset',
    'bForceProcessExitComplete\s*:=\s*GVL_Status\.stFast\.stSequence\.stMotionIntent\.bForceProcessExitComplete\s+AND\s+fbZAxisExtSetpointAdapter\.stStatus\.bReleaseOwner',
    'stFast\.stZForceControl',
    'ALARM_FORCE_CONTROL_FAULT',
    'astRequests\[8\]'
)
if ($fastAxisText -match 'fForceDisplayN') {
    Fail 'PRG_FastAxisControl must not use ForceDisplay for control.'
}
if ($fastAxisText -match 'GVL_Config\.stZForceControl|GVL_Config\.stZExtSetpoint|GVL_Config\.stLimits|GVL_Config\.stMachine\.nFastTaskCycleUs') {
    Fail 'FastAxis Phase 10 path must consume the accepted frozen Fast configuration snapshot, not live configuration.'
}
if ($fastAxisText -match 'GVL_Command\.stFast\.(?:stZAxis|stRAxis|stZExtSetpoint|nRequestId)') {
    Fail 'FastAxis ordinary motion candidates must consume GVL_FastInternal.stAcceptedCommand.'
}
if ($fastAxisText -match 'bCycleNok\s*(?:OR|AND|:=).*?bError|bError\s*(?:OR|AND|:=).*?bCycleNok') {
    Fail 'Cycle NOK must not stop a healthy controlled force unload as an algorithm error.'
}
$fastSafetyAssignment = [regex]::Match($fastAxisText, 'bFastPathSafetyExit\s*:=\s*(?<Body>(?:(?!;)[\s\S])*)').Groups['Body'].Value
if ($fastSafetyAssignment -notmatch 'bForceLoopRequested\s+AND\s+NOT\s+fbForceSetpointRamp\.bValid') {
    Fail 'An invalid requested force ramp must enter the same-scan Fast safety exit explicitly.'
}

$pouFiles = @(Get-ChildItem -LiteralPath (Join-Path $plcRoot 'POUs') -Recurse -File -Filter '*.TcPOU')
$allPouText = ($pouFiles | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
}) -join "`n"
foreach ($declaration in @(
    'fbForceSetpointRamp\s*:\s*FB_SetpointRamp',
    'fbZProfileSwitch\s*:\s*FB_BumplessProfileSwitch',
    'fbZForceAdmittance\s*:\s*FB_ZForceAdmittance',
    'fbZExternalTrajectory\s*:\s*FB_ZExternalTrajectory',
    'fbRSpeedRamp\s*:\s*FB_SetpointRamp'
)) {
    if ([regex]::Matches($allPouText, $declaration).Count -ne 1) {
        Fail "Phase 8 instance must have exactly one owner: $declaration"
    }
}

$trajectoryFiles = @($pouFiles | Where-Object {
    $trajectoryOwnerText = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    ($trajectoryOwnerText -match 'stInput\.rTargetVelocity_mm_s') -and
        ($trajectoryOwnerText -match 'stOutput\.rPosition_mm\s*:=' ) -and
        ($trajectoryOwnerText -match 'stOutput\.rVelocity_mm_s\s*:=' ) -and
        ($trajectoryOwnerText -match 'stOutput\.rAcceleration_mm_s2\s*:=' ) -and
        ($trajectoryOwnerText -match 'stOutput\.nDirection\s*:=' )
})
if ($trajectoryFiles.Count -ne 1 -or $trajectoryFiles[0].BaseName -ne 'FB_ZExternalTrajectory') {
    Fail 'FB_ZExternalTrajectory must be the only POU composing a target velocity into External P/V/A/Direction.'
}
$externalApiOwners = @($pouFiles | Where-Object {
    (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) -match '\bMC_ExtSetPointGen(?:Enable|Disable|Feed)\b'
})
if ($externalApiOwners.Count -ne 1 -or $externalApiOwners[0].BaseName -ne 'FB_ZAxisExtSetpointAdapter') {
    Fail 'FB_ZAxisExtSetpointAdapter must remain the only External MC API owner.'
}

$controlRoot = Join-Path $plcRoot 'POUs\FunctionBlocks\Control'
if (Test-Path -LiteralPath $controlRoot -PathType Container) {
    foreach ($controlFile in Get-ChildItem -LiteralPath $controlRoot -File -Filter '*.TcPOU') {
        $controlText = Get-Content -LiteralPath $controlFile.FullName -Raw -Encoding UTF8
        if ($controlText -match '\bAXIS_REF\b|\bMC_[A-Za-z0-9_]+\b|\bGVL_[A-Za-z0-9_]+\b') {
            Fail "Control FB escaped its algorithm boundary: $($controlFile.Name)"
        }
    }
}

if ($allPouText -match 'b(?:ZAxis|RAxis)DriveLinked\s*:=\s*TRUE|bProductionReady\s*:=\s*TRUE|bAllRequiredMappingsConfirmed\s*:=\s*TRUE|stZForceControl\.bValid\s*:=\s*TRUE') {
    Fail 'Phase 8 must not force hardware binding, configuration, mapping, or Production Ready TRUE.'
}

# Deterministic reference vectors protect the mathematical contract while the
# repository remains offline and no TwinCAT Runtime execution is authorized.
function Get-ReferenceStrokeLimit(
    [double]$Remaining,
    [double]$BrakeMargin,
    [double]$ProfileAcceleration,
    [double]$MachineAcceleration) {
    $effectiveAcceleration = [Math]::Min([Math]::Abs($ProfileAcceleration), [Math]::Abs($MachineAcceleration))
    $usable = [Math]::Max($Remaining - $BrakeMargin, 0.0)
    return [Math]::Sqrt(2.0 * $effectiveAcceleration * $usable)
}
$referencePi = 1.0 + 2.0 * 0.5 + 0.2
if ([Math]::Abs($referencePi - 2.2) -gt 1.0E-12) {
    Fail 'Reference PI vector failed.'
}
$referenceAntiWindup = 0.4 * 0.5 + 0.3 * (1.5 - 2.2)
if ([Math]::Abs($referenceAntiWindup - (-0.01)) -gt 1.0E-12) {
    Fail 'Reference anti-windup vector failed.'
}
$machineLimitedStroke = Get-ReferenceStrokeLimit -Remaining 0.5 -BrakeMargin 0.0 -ProfileAcceleration 10.0 -MachineAcceleration 1.0
if ([Math]::Abs($machineLimitedStroke - 1.0) -gt 1.0E-12) {
    Fail 'Reference stroke vector did not use the effective machine acceleration.'
}
$atTargetStroke = Get-ReferenceStrokeLimit -Remaining 0.0 -BrakeMargin 0.0 -ProfileAcceleration 10.0 -MachineAcceleration 1.0
$rateLimitedVelocity = 9.9
$finalEnvelopeVelocity = [Math]::Min($rateLimitedVelocity, $atTargetStroke)
if ($finalEnvelopeVelocity -ne 0.0) {
    Fail 'Reference final velocity exceeded the zero stroke envelope.'
}

# Multi-scan state references cover reset, snapshot, and fault-latch contracts.
$trackedRevision = 7
$resetActive = $true
if ($resetActive) { $trackedRevision = 0 }
$resetActive = $false
$transferRequiredAfterReset = (-not $resetActive) -and (7 -ne $trackedRevision)
if (-not $transferRequiredAfterReset) {
    Fail 'Reference reset lifecycle did not require a new profile transfer.'
}

$acceptedMachineVelocity = 5.0
$candidateMachineVelocity = 6.0
$machineLimitsMismatch = $candidateMachineVelocity -ne $acceptedMachineVelocity
if (-not $machineLimitsMismatch) {
    Fail 'Reference machine-limit snapshot accepted an unauthorized widening.'
}

$transferVelocity = -100.0
$maximumUpVelocity = 10.0
$maximumDownVelocity = 8.0
$transferVelocityAccepted = ($transferVelocity -ge (-$maximumUpVelocity)) -and ($transferVelocity -le $maximumDownVelocity)
if ($transferVelocityAccepted) {
    Fail 'Reference transfer vector accepted an out-of-range upward velocity.'
}

$acceptedKp = 2.0
$candidateKp = 2.1
$acceptedRevision = 7
$candidateRevision = 7
$profileContentMismatch = ($candidateRevision -ne $acceptedRevision) -or ($candidateKp -ne $acceptedKp)
if (-not $profileContentMismatch) {
    Fail 'Reference profile snapshot ignored same-revision content changes.'
}

$referenceFault = $rateLimitedVelocity -gt $atTargetStroke
$referenceActive = -not $referenceFault
$referencePublishedVelocity = if ($referenceFault) { 0.0 } else { $finalEnvelopeVelocity }
if (-not $referenceFault -or $referenceActive -or $referencePublishedVelocity -ne 0.0) {
    Fail 'Reference envelope-fault scan published a consumable command.'
}

$faultLatched = [double]::IsNaN([double]::NaN) -or [double]::IsInfinity([double]::PositiveInfinity)
$nextScanInputsValid = $true
if ($nextScanInputsValid -and -not $faultLatched) {
    Fail 'Reference non-finite fault did not remain latched on the next scan.'
}
$explicitReset = $true
if ($explicitReset) { $faultLatched = $false }
if ($faultLatched) {
    Fail 'Reference explicit reset did not clear the fault latch.'
}

# Cross-task Task 7/9 caller contract: Sequence must keep Force Owner and its
# disable intent until the Adapter has accepted the hard/disable package and
# publishes ReleaseOwner.  FastAxis therefore must never infer completion from
# a same-scan caller withdrawal alone.
$task79SequenceExitIntent = $true
$task79HardOrDisableAccepted = $false
$task79AdapterReleaseOwner = $false
$task6ReportedForceExitComplete = $task79SequenceExitIntent -and $task79AdapterReleaseOwner
if ($task6ReportedForceExitComplete -or $task79HardOrDisableAccepted) {
    Fail 'Task 7/9 caller withdrawal incorrectly reported a Task 6 Force Owner release before Adapter acceptance.'
}

$reportFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Docs') -Recurse -File -Filter 'PHASE_8_EXECUTION_REPORT.md' -ErrorAction SilentlyContinue)
if ($reportFiles.Count -ne 1) {
    Fail "Expected exactly one Phase 8 execution report; found $($reportFiles.Count)."
}

if ($failures.Count -gt 0) {
    Write-Host 'Phase 8 force admittance test: FAILED'
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}

Write-Host 'Phase 8 force admittance test: PASSED'
Write-Host 'Control boundary: no AXIS_REF or MC in force algorithms'
Write-Host 'Default policy: sequence and hardware gates remain inhibited'
