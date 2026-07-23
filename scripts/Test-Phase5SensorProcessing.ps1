[CmdletBinding()]
param([string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$plcRoot = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding'
$projectPath = Join-Path $plcRoot 'CFFwelding.plcproj'
$systemProjectPath = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding_System.tsproj'
$failures = New-Object 'System.Collections.Generic.List[string]'
function Fail([string]$Message) { $failures.Add($Message) }

if (Test-Path -LiteralPath $projectPath -PathType Leaf) {
    $projectText = Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8
}
else {
    $projectText = ''
    Fail 'PLC project is missing.'
}

$requiredDuts = @('ST_SensorProcessingConfig', 'ST_ProcessReferenceCommand')
foreach ($dutName in $requiredDuts) {
    $files = @(Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$dutName.TcDUT" -ErrorAction SilentlyContinue)
    if ($files.Count -ne 1) {
        Fail "Expected exactly one $dutName.TcDUT; found $($files.Count)."
        continue
    }
    try { [void][xml](Get-Content -LiteralPath $files[0].FullName -Raw -Encoding UTF8) }
    catch { Fail "Invalid DUT XML: $dutName" }
    if ($projectText -notmatch [regex]::Escape($files[0].Name)) { Fail "PLC project does not compile $dutName." }
}

$ioPath = Join-Path $plcRoot 'GVLs\GVL_IO.TcGVL'
if (Test-Path -LiteralPath $ioPath -PathType Leaf) {
    $ioText = Get-Content -LiteralPath $ioPath -Raw -Encoding UTF8
    foreach ($pattern in @(
        'nForceChannelRaw\s+AT\s+%I\*\s*:\s*INT',
        'bForceChannelError\s+AT\s+%I\*\s*:\s*BOOL',
        'bForceChannelOverrange\s+AT\s+%I\*\s*:\s*BOOL',
        'bForceChannelUnderrange\s+AT\s+%I\*\s*:\s*BOOL',
        'nDisplacementChannelRaw\s+AT\s+%I\*\s*:\s*INT',
        'bDisplacementChannelError\s+AT\s+%I\*\s*:\s*BOOL',
        'bCollisionReferenceSensor\s+AT\s+%I\*\s*:\s*BOOL'
    )) {
        if ($ioText -notmatch $pattern) { Fail "GVL_IO is missing sensor placeholder: $pattern" }
    }
    if ($ioText -match ':=\s*TRUE') { Fail 'GVL_IO must not initialize a hardware signal TRUE.' }
}
else { Fail 'GVL_IO is missing.' }

$actualPath = Join-Path $plcRoot 'DUTs\Structures\ST_ProcessActual.TcDUT'
if (Test-Path -LiteralPath $actualPath -PathType Leaf) {
    $actualText = Get-Content -LiteralPath $actualPath -Raw -Encoding UTF8
    foreach ($field in @(
        'fForceRawN','fForceCriterionN','fForceControlN','fForceDisplayN',
        'fExternalDisplacementMm','fSRelSensorMm','fSRelAxisMm',
        'fAxisSensorDeltaMm','fCollisionDeltaMm','bForceValid',
        'bDisplacementValid','bCollisionValid','bContactReferenceValid'
    )) {
        if ($actualText -notmatch $field) { Fail "ST_ProcessActual is missing $field." }
    }
}
else { Fail 'ST_ProcessActual is missing.' }

$fastInputsPath = Join-Path $plcRoot 'POUs\Fast\PRG_FastInputs.TcPOU'
if (Test-Path -LiteralPath $fastInputsPath -PathType Leaf) {
    $fastText = Get-Content -LiteralPath $fastInputsPath -Raw -Encoding UTF8
    foreach ($pattern in @(
        'ARRAY\[1\.\.4\]\s+OF\s+FB_LowPassFilter',
        'fbForceSignalValidity\s*:\s*FB_SignalValidity',
        'fbDisplacementFilter\s*:\s*FB_LowPassFilter',
        'fbDisplacementSignalValidity\s*:\s*FB_SignalValidity',
        'fbCollisionDebounce\s*:\s*FB_Debounce',
        'fSRelSensorMm\s*:=',
        'fSRelAxisMm\s*:=',
        'fAxisSensorDeltaMm\s*:=',
        'fCollisionDeltaMm\s*:=',
        'udiContactReferenceRequestId',
        'udiContactReferenceAcceptedId'
    )) {
        if ($fastText -notmatch $pattern) { Fail "PRG_FastInputs is missing Phase 5 behavior: $pattern" }
    }
    if ($fastText -match 'bProductionReady\s*:=\s*TRUE|bForceInputMapped\s*:=\s*TRUE|bDisplacementInputMapped\s*:=\s*TRUE|bCollisionInputMapped\s*:=\s*TRUE') {
        Fail 'PRG_FastInputs must not force hardware mapping or Production Ready TRUE.'
    }
    try {
        [xml]$fastXml = $fastText
        if ($fastXml.TcPlcObject.POU.Implementation.ST.InnerText.TrimEnd() -notmatch ';$') {
            Fail 'PRG_FastInputs ends with an unterminated ST statement.'
        }
    }
    catch { Fail 'PRG_FastInputs XML is invalid.' }
    if ($fastText -match 'eStep.*(reset|Reset)|STEP[1-4].*RelativePosition') {
        Fail 'S_rel must not reset at individual step boundaries.'
    }
}
else { Fail 'PRG_FastInputs is missing.' }

$configPath = Join-Path $plcRoot 'GVLs\GVL_Config.TcGVL'
$commandPath = Join-Path $plcRoot 'GVLs\GVL_Command.TcGVL'
foreach ($check in @(
    @{ Path = $configPath; Pattern = 'stSensorProcessing\s*:\s*ST_SensorProcessingConfig'; Name = 'GVL_Config sensor processing contract' },
    @{ Path = $commandPath; Pattern = 'stProcessReference\s*:\s*ST_ProcessReferenceCommand'; Name = 'GVL_Command process reference contract' }
)) {
    if (-not (Test-Path -LiteralPath $check.Path -PathType Leaf)) { Fail "$($check.Name) file is missing."; continue }
    $text = Get-Content -LiteralPath $check.Path -Raw -Encoding UTF8
    if ($text -notmatch $check.Pattern) { Fail "$($check.Name) is missing." }
}

if (Test-Path -LiteralPath $systemProjectPath -PathType Leaf) {
    [xml]$systemXml = Get-Content -LiteralPath $systemProjectPath -Raw -Encoding UTF8
    $ioChildren = @($systemXml.SelectNodes('/TcSmProject/Project/Io/*'))
    if ($ioChildren.Count -ne 0) { Fail 'A real I/O configuration was added during Phase 5.' }
    $ioConfigurationNode = $systemXml.SelectSingleNode('/TcSmProject/Project/Io')
    $motionConfigurationNode = $systemXml.SelectSingleNode('/TcSmProject/Project/Motion')
    $ioConfigurationText = if ($null -eq $ioConfigurationNode) { '' } else { $ioConfigurationNode.OuterXml }
    $motionConfigurationText = if ($null -eq $motionConfigurationNode) { '' } else { $motionConfigurationNode.OuterXml }
    foreach ($token in @('EP3174','EtherCAT','TwinSAFE')) {
        if ($ioConfigurationText -match [regex]::Escape($token)) { Fail "Forbidden configured I/O/Safety token: $token" }
    }
    foreach ($token in @('AX5000','SimulationDrive')) {
        if ($motionConfigurationText -match [regex]::Escape($token)) { Fail "Forbidden configured drive/simulation token: $token" }
    }
}

$reportFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Docs') -Recurse -File -Filter 'PHASE_5_EXECUTION_REPORT.md' -ErrorAction SilentlyContinue)
if ($reportFiles.Count -ne 1) { Fail "Expected exactly one Phase 5 execution report; found $($reportFiles.Count)." }

if ($failures.Count -gt 0) {
    Write-Host 'Phase 5 sensor processing test: FAILED'
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}

Write-Host 'Phase 5 sensor processing test: PASSED'
Write-Host 'Force channels: Raw / Criterion / Control / Display'
Write-Host 'Relative channels: Sensor / Axis / Delta / Collision'
