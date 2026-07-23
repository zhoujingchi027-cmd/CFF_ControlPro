[CmdletBinding()]
param([string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$plcRoot = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding'
$plcProjectPath = Join-Path $plcRoot 'CFFwelding.plcproj'
$failures = New-Object 'System.Collections.Generic.List[string]'
function Fail([string]$Message) { $failures.Add($Message) }

$functionNames = @(
    'FC_ClampLReal',
    'FC_ScaleLinear',
    'FC_LimitRate',
    'FC_TrapezoidIntegrate',
    'FC_RpmToRadPerSec',
    'FC_CalcEnergyIncrement',
    'FC_ConvertDirection',
    'FC_IsFiniteLReal',
    'FC_Interpolate1D',
    'FC_ValidateCalibration',
    'FC_ValidateJoinProgram',
    'FC_GetPrimaryEndCause',
    'FC_CalcStrokeVelocityLimit',
    'FC_CheckModeSourceMatrix'
)

$functionBlockNames = @(
    'FB_LowPassFilter',
    'FB_Debounce',
    'FB_SignalValidity',
    'FB_SetpointRamp',
    'FB_CommandHandshake',
    'FB_AlarmLatch'
)

if (Test-Path -LiteralPath $plcProjectPath -PathType Leaf) {
    $plcProjectText = Get-Content -Raw -Encoding UTF8 -LiteralPath $plcProjectPath
}
else {
    $plcProjectText = ''
    Fail "Missing PLC project: $plcProjectPath"
}

function Test-PouFile([string]$Name, [string]$Kind) {
    $files = @(Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$Name.TcPOU" -ErrorAction SilentlyContinue)
    if ($files.Count -ne 1) {
        Fail "Expected exactly one $Name.TcPOU; found $($files.Count)."
        return
    }

    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $files[0].FullName
    try {
        [xml]$xml = $text
    }
    catch {
        Fail "Invalid POU XML: $($files[0].FullName)"
        return
    }

    $declaration = $xml.TcPlcObject.POU.Declaration.InnerText
    $implementation = $xml.TcPlcObject.POU.Implementation.ST.InnerText
    if ($declaration -notmatch "(?m)^$Kind\s+$([regex]::Escape($Name))(\s|:)") {
        Fail "$Name is not declared as $Kind."
    }
    if (($declaration + $implementation) -notmatch '[\u4e00-\u9fff]') {
        Fail "$Name is missing Chinese interface or algorithm documentation."
    }
    if ($plcProjectText -notmatch [regex]::Escape($files[0].Name)) {
        Fail "PLC project does not compile $($files[0].Name)."
    }
    if (($declaration + $implementation) -match '\b(AXIS_REF|MC_[A-Za-z0-9_]+|GVL_[A-Za-z0-9_]+)\b') {
        Fail "$Name violates the reusable utility boundary with AXIS_REF, MC, or GVL access."
    }
}

foreach ($name in $functionNames) { Test-PouFile -Name $name -Kind 'FUNCTION' }
foreach ($name in $functionBlockNames) { Test-PouFile -Name $name -Kind 'FUNCTION_BLOCK' }

$requiredPatterns = @{
    'FB_LowPassFilter'     = @('bReset', 'rCycleTime_s', 'rTimeConstant_s', 'bValid')
    'FB_Debounce'          = @('bReset', 'tOnDelay', 'tOffDelay', 'bOutput')
    'FB_SignalValidity'    = @('bReset', 'rMinimum', 'rMaximum', 'tInvalidDelay', 'bValid')
    'FB_SetpointRamp'      = @('bReset', 'rTarget', 'rRateUpPer_s', 'rRateDownPer_s', 'rCycleTime_s')
    'FB_CommandHandshake'  = @('bReset', 'udiRequestId', 'udiAcceptedId', 'bNewRequest')
    'FB_AlarmLatch'        = @('bReset', 'bSetRequest', 'bSourceActive', 'bLatched')
}

foreach ($entry in $requiredPatterns.GetEnumerator()) {
    $file = Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$($entry.Key).TcPOU" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $file) { continue }
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    foreach ($pattern in $entry.Value) {
        if ($text -notmatch [regex]::Escape($pattern)) { Fail "$($entry.Key) is missing required reset/boundary interface: $pattern" }
    }
}

$functionContracts = @{
    'FC_ClampLReal'                = @('rMinimum', 'rMaximum')
    'FC_ScaleLinear'               = @('rInputMinimum', 'rInputMaximum', 'bValid')
    'FC_LimitRate'                 = @('rRateUpPer_s', 'rRateDownPer_s', 'rCycleTime_s')
    'FC_TrapezoidIntegrate'        = @('rPreviousValue', 'rCurrentValue', 'rCycleTime_s')
    'FC_CalcEnergyIncrement'       = @('rTorque_Nm', 'rRpm', 'rCycleTime_s')
    'FC_Interpolate1D'             = @('rX0', 'rX1', 'bValid')
    'FC_ValidateCalibration'       = @('bCalibrationValid', 'udiRevision')
    'FC_ValidateJoinProgram'       = @('stProgram', 'stMachineLimits')
    'FC_GetPrimaryEndCause'        = @('ePrimaryCriterion')
    'FC_CalcStrokeVelocityLimit'   = @('rRemainingStroke_mm', 'rMaximumDeceleration_mm_s2')
    'FC_CheckModeSourceMatrix'     = @('eOperationMode', 'eControlSource')
}

foreach ($entry in $functionContracts.GetEnumerator()) {
    $file = Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$($entry.Key).TcPOU" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $file) { continue }
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    foreach ($pattern in $entry.Value) {
        if ($text -notmatch [regex]::Escape($pattern)) { Fail "$($entry.Key) is missing required contract field: $pattern" }
    }
}

$phaseReportFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Docs') -Recurse -File -Filter 'PHASE_4_EXECUTION_REPORT.md' -ErrorAction SilentlyContinue)
if ($phaseReportFiles.Count -ne 1) {
    Fail "Expected exactly one Phase 4 execution report; found $($phaseReportFiles.Count)."
}

if ($failures.Count -gt 0) {
    Write-Host 'Phase 4 utility test: FAILED'
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}

Write-Host 'Phase 4 utility test: PASSED'
Write-Host "Function count: $($functionNames.Count)"
Write-Host "Utility FB count: $($functionBlockNames.Count)"
