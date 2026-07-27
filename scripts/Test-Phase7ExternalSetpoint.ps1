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
    'bFeedAccepted\s*:\s*BOOL',
    'bReleaseOwner\s*:\s*BOOL',
    'udiFeedCycleCounter\s*:\s*UDINT',
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
        'nFeedDirection\s*<>\s*0[\s\S]*stCommand\.nDirection\s*<>\s*0[\s\S]*stCommand\.nDirection\s*<>\s*nFeedDirection',
        '16#00007209',
        'nFeedDirection\s*=\s*0[\s\S]*stCommand\.nDirection\s*<>\s*0'
    )) {
        if ($adapterText -notmatch $pattern) { Fail "External adapter is missing: $pattern" }
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

$fastAxisPath = Join-Path $plcRoot 'POUs\Fast\PRG_FastAxisControl.TcPOU'
if (-not (Test-Path -LiteralPath $fastAxisPath -PathType Leaf)) {
    Fail 'PRG_FastAxisControl is missing.'
}
else {
    $fastAxisText = Get-Content -LiteralPath $fastAxisPath -Raw -Encoding UTF8
    foreach ($pattern in @(
        'fbZExtSetpoint\s*:\s*FB_ZAxisExtSetpointAdapter',
        'fbZAxisArbiter\.eActiveOwner\s*=\s*E_ZCommandOwner\.Z_OWNER_FORCE_PROCESS',
        'bLimitsValid\s*:=\s*GVL_Config\.stLimits\.bValid',
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
