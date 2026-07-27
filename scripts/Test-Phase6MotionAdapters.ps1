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

$axisFbRoot = Join-Path $plcRoot 'POUs\FunctionBlocks\Axis'
$requiredFbs = @('FB_AxisCommandArbiter', 'FB_ZAxisNcAdapter', 'FB_RAxisNcAdapter')
$texts = @{}
foreach ($fbName in $requiredFbs) {
    $files = @(Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$fbName.TcPOU" -ErrorAction SilentlyContinue)
    if ($files.Count -ne 1) {
        Fail "Expected exactly one $fbName.TcPOU; found $($files.Count)."
        continue
    }
    $text = Get-Content -LiteralPath $files[0].FullName -Raw -Encoding UTF8
    $texts[$fbName] = $text
    try { [void][xml]$text }
    catch { Fail "Invalid POU XML: $fbName" }
    if ($projectText -notmatch [regex]::Escape("POUs\FunctionBlocks\Axis\$fbName.TcPOU")) {
        Fail "PLC project does not compile $fbName."
    }
}

if ($texts.ContainsKey('FB_AxisCommandArbiter')) {
    $arbiterText = $texts['FB_AxisCommandArbiter']
    foreach ($pattern in @(
        'stHomeCommand\s*:\s*ST_ZAxisCommand',
        'stManualCommand\s*:\s*ST_ZAxisCommand',
        'stApproachCommand\s*:\s*ST_ZAxisCommand',
        'stForceProcessCommand\s*:\s*ST_ZAxisCommand',
        'stRetractCommand\s*:\s*ST_ZAxisCommand',
        'bFaultStopRequest\s*:\s*BOOL',
        'bForceProcessExitComplete\s*:\s*BOOL',
        'eActiveOwner\s*:\s*E_ZCommandOwner',
        'Z_OWNER_FAULT_STOP',
        'Z_OWNER_FORCE_PROCESS'
    )) {
        if ($arbiterText -notmatch $pattern) { Fail "Axis owner arbiter is missing: $pattern" }
    }
    if ($arbiterText -match 'AXIS_REF|\bMC_[A-Za-z0-9_]+') {
        Fail 'FB_AxisCommandArbiter must not access AXIS_REF or MC function blocks.'
    }
}

foreach ($adapterName in @('FB_ZAxisNcAdapter', 'FB_RAxisNcAdapter')) {
    if (-not $texts.ContainsKey($adapterName)) { continue }
    $adapterText = $texts[$adapterName]
    foreach ($pattern in @(
        'VAR_IN_OUT[\s\S]*Axis\s*:\s*AXIS_REF',
        'bDriveLinked\s*:\s*BOOL',
        'udiCommandId\s*:\s*UDINT',
        'udiAcceptedCommandId',
        'Axis\.ReadStatus\s*\(\s*\)',
        'MC_Power',
        'MC_Reset',
        'MC_Halt',
        'bDriveLinked\s+AND'
    )) {
        if ($adapterText -notmatch $pattern) { Fail "$adapterName is missing boundary behavior: $pattern" }
    }
    if ($adapterText -match 'bReady\s*:=\s*TRUE|bDriveLinked\s*:=\s*TRUE') {
        Fail "$adapterName must not force Ready or drive binding TRUE."
    }
}

if ($texts.ContainsKey('FB_ZAxisNcAdapter')) {
    $zText = $texts['FB_ZAxisNcAdapter']
    foreach ($pattern in @('MC_Home', 'MC_MoveAbsolute', 'MC_MoveVelocity', 'NcToPlc\.ActPos', 'NcToPlc\.ActVelo')) {
        if ($zText -notmatch $pattern) { Fail "Z NC adapter is missing: $pattern" }
    }
}

if ($texts.ContainsKey('FB_RAxisNcAdapter')) {
    $rText = $texts['FB_RAxisNcAdapter']
    foreach ($pattern in @('MC_MoveVelocity', 'NcToPlc\.ActVelo', 'NcToPlc\.ActTorque')) {
        if ($rText -notmatch $pattern) { Fail "R NC adapter is missing: $pattern" }
    }
    if ($rText -match 'TorqueControl|MC_TorqueControl') {
        Fail 'Phase 6 R adapter must not implement a torque loop.'
    }
}

$fastAxisPath = Join-Path $plcRoot 'POUs\Fast\PRG_FastAxisControl.TcPOU'
if (Test-Path -LiteralPath $fastAxisPath -PathType Leaf) {
    $fastAxisText = Get-Content -LiteralPath $fastAxisPath -Raw -Encoding UTF8
    foreach ($pattern in @(
        'fbZAxisArbiter\s*:\s*FB_AxisCommandArbiter',
        'fbZAxisNc\s*:\s*FB_ZAxisNcAdapter',
        'fbRAxisNc\s*:\s*FB_RAxisNcAdapter',
        'GVL_IO\.Z_axis',
        'GVL_IO\.R_axis',
        'bZAxisDriveLinked',
        'bRAxisDriveLinked',
        'GVL_Status\.stFast\.stZAxis',
        'GVL_Status\.stFast\.stRAxis'
    )) {
        if ($fastAxisText -notmatch $pattern) { Fail "PRG_FastAxisControl is missing: $pattern" }
    }
    if ($fastAxisText -match '\bMC_[A-Za-z0-9_]+') {
        Fail 'PRG_FastAxisControl must delegate every MC call to an axis adapter.'
    }
}
else { Fail 'PRG_FastAxisControl is missing.' }

$sequencePath = Join-Path $plcRoot 'POUs\Fast\PRG_CffSequence.TcPOU'
if (Test-Path -LiteralPath $sequencePath -PathType Leaf) {
    $sequenceText = Get-Content -LiteralPath $sequencePath -Raw -Encoding UTF8
    if ($sequenceText -match '\bMC_[A-Za-z0-9_]+|AXIS_REF') {
        Fail 'PRG_CffSequence must not access MC function blocks or AXIS_REF.'
    }
}

$allPouFiles = @(Get-ChildItem -LiteralPath (Join-Path $plcRoot 'POUs') -Recurse -File -Filter '*.TcPOU')
foreach ($pouFile in $allPouFiles) {
    $pouText = Get-Content -LiteralPath $pouFile.FullName -Raw -Encoding UTF8
    if ($pouText -match 'VAR_IN_OUT[\s\S]{0,300}AXIS_REF' -and $pouFile.BaseName -notin @('FB_ZAxisNcAdapter', 'FB_ZAxisExtSetpointAdapter', 'FB_RAxisNcAdapter')) {
        Fail "AXIS_REF VAR_IN_OUT escaped the Phase 6 adapters: $($pouFile.Name)"
    }
}

if (Test-Path -LiteralPath $systemProjectPath -PathType Leaf) {
    [xml]$systemXml = Get-Content -LiteralPath $systemProjectPath -Raw -Encoding UTF8
    if (@($systemXml.SelectNodes('/TcSmProject/Project/Io/*')).Count -ne 0) {
        Fail 'A real I/O configuration was added during Phase 6.'
    }
    $motionText = $systemXml.SelectSingleNode('/TcSmProject/Project/Motion').OuterXml
    foreach ($token in @('AX5000', 'SimulationDrive')) {
        if ($motionText -match [regex]::Escape($token)) { Fail "Forbidden configured drive token: $token" }
    }
}

$reportFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'Docs') -Recurse -File -Filter 'PHASE_6_EXECUTION_REPORT.md' -ErrorAction SilentlyContinue)
if ($reportFiles.Count -ne 1) { Fail "Expected exactly one Phase 6 execution report; found $($reportFiles.Count)." }

if ($failures.Count -gt 0) {
    Write-Host 'Phase 6 motion adapter test: FAILED'
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}

Write-Host 'Phase 6 motion adapter test: PASSED'
Write-Host 'MC boundary: Z/R NC adapters only'
Write-Host 'Unbound drive policy: Ready FALSE and motion gated'
