[CmdletBinding()]
param([string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$plcRoot = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding'
$plcProjectPath = Join-Path $plcRoot 'CFFwelding.plcproj'
$systemProjectPath = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding_System.tsproj'
$failures = New-Object 'System.Collections.Generic.List[string]'
function Fail([string]$Message) { $failures.Add($Message) }

function Get-ExactFile([string]$Name, [string]$Extension) {
    $files = @(Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$Name$Extension" -ErrorAction SilentlyContinue)
    if ($files.Count -ne 1) {
        Fail "Expected exactly one $Name$Extension; found $($files.Count)."
        return $null
    }
    return $files[0]
}

$enumNames = @(
    'E_OperationMode','E_ControlSource','E_MachineState','E_InitializeState',
    'E_MaintenanceFunction','E_MaintenanceState','E_CffState','E_CffStep',
    'E_StepSubPhase','E_StepPrimaryCriterion','E_SecondaryCriterionAction',
    'E_StepEndCause','E_ZCommandOwner','E_ZExtSetpointState','E_AlarmLevel',
    'E_AlarmCode','E_FastenerStatus','E_FeederState','E_ReturnMode',
    'E_CalibrationState','E_CommandExecutionState','E_CommandRejectReason',
    'E_HmiCommandCode','E_RobotCommandCode','E_ProgramState','E_InterfaceEventState'
)
$structureNames = @(
    'ST_MachineConfig','ST_MachineLimits','ST_ForceCalibration',
    'ST_DisplacementCalibration','ST_CollisionCalibration','ST_ZForceControlProfile',
    'ST_RAxisProfile','ST_StepProceedingConfig','ST_CffStepProgram',
    'ST_JoinProgramHeader','ST_ProcessMonitorProfile','ST_CffJoinProgram',
    'ST_JoiningPointAssignment','ST_CycleSnapshot','ST_ProcessActual',
    'ST_ProcessFeatures','ST_StepCriterionResult','ST_CycleResult',
    'ST_AlarmRequest','ST_AlarmStatus','ST_CommandMailbox','ST_CommandPermission',
    'ST_MaintenanceHoldRequest','ST_RobotCommand','ST_RobotStatus',
    'ST_FeederInput','ST_FeederOutput','ST_CalibrationCommand',
    'ST_CalibrationStatus','ST_FastCommand','ST_FastStatus','ST_CurveSample',
    'ST_HardwareBindingStatus'
)
$gvlNames = @(
    'GVL_Const','GVL_IO','GVL_Config','GVL_Calibration','GVL_Program','GVL_Command',
    'GVL_Status','GVL_Process','GVL_Alarm','GVL_HMI','GVL_Trace','GVL_Persistent',
    'GVL_ProjectInfo'
)

if (Test-Path -LiteralPath $plcProjectPath -PathType Leaf) {
    $plcProjectText = Get-Content -Raw -Encoding UTF8 -LiteralPath $plcProjectPath
}
else {
    $plcProjectText = ''
    Fail "Missing PLC project: $plcProjectPath"
}

foreach ($enumName in $enumNames) {
    $file = Get-ExactFile $enumName '.TcDUT'
    if ($null -eq $file) { continue }
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    try { [xml]$xml = $text } catch { Fail "Invalid enum XML: $($file.FullName)"; continue }
    $declaration = $xml.TcPlcObject.DUT.Declaration.InnerText
    if ($declaration -notmatch "TYPE\s+$([regex]::Escape($enumName))\s*:") {
        Fail "Missing enum declaration: $enumName"
    }
    $enumValueLines = @($declaration.Split("`n") | Where-Object { $_ -match '^\s*[A-Z][A-Z0-9_]*\s*(:=|,|\))' })
    foreach ($line in $enumValueLines) {
        if ($line -notmatch ':=\s*-?\d+') { Fail "$enumName contains a value without explicit numeric assignment: $line" }
    }
    if ($plcProjectText -notmatch [regex]::Escape($file.Name)) { Fail "PLC project does not compile $($file.Name)." }
}

foreach ($structureName in $structureNames) {
    $file = Get-ExactFile $structureName '.TcDUT'
    if ($null -eq $file) { continue }
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    try { [xml]$xml = $text } catch { Fail "Invalid structure XML: $($file.FullName)"; continue }
    $declaration = $xml.TcPlcObject.DUT.Declaration.InnerText
    if ($declaration -notmatch "TYPE\s+$([regex]::Escape($structureName))\s*:" -or $declaration -notmatch 'STRUCT') {
        Fail "Missing STRUCT declaration: $structureName"
    }
    if ($declaration -notmatch '\(\*') { Fail "$structureName has no Chinese/public field documentation." }
    if ($plcProjectText -notmatch [regex]::Escape($file.Name)) { Fail "PLC project does not compile $($file.Name)." }
}

$gvlTextByName = @{}
foreach ($gvlName in $gvlNames) {
    $file = Get-ExactFile $gvlName '.TcGVL'
    if ($null -eq $file) { continue }
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    $gvlTextByName[$gvlName] = $text
    try { [void][xml]$text } catch { Fail "Invalid GVL XML: $($file.FullName)" }
    if ($text -notmatch "attribute 'qualified_only'") { Fail "$gvlName is missing qualified_only." }
    if ($plcProjectText -notmatch [regex]::Escape($file.Name)) { Fail "PLC project does not compile $($file.Name)." }
}

if ($gvlTextByName.ContainsKey('GVL_IO')) {
    $ioText = $gvlTextByName['GVL_IO']
    foreach ($pattern in @('Z_axis\s*:\s*AXIS_REF','R_axis\s*:\s*AXIS_REF','AT\s+%I\*','AT\s+%Q\*','TODO_HW_MAP')) {
        if ($ioText -notmatch $pattern) { Fail "GVL_IO is missing required pattern: $pattern" }
    }
    if ($ioText -notmatch "attribute 'TcContextName'\s*:=\s*'Task_CffFast'") {
        Fail 'GVL_IO allocated variables must be updated by Task_CffFast.'
    }
    if ($ioText -match ':=\s*TRUE') { Fail 'GVL_IO must not initialize any hardware input or output TRUE.' }
}
if ($gvlTextByName.ContainsKey('GVL_Status')) {
    if ($gvlTextByName['GVL_Status'] -notmatch 'bProductionReady\s*:\s*BOOL\s*:=\s*FALSE') {
        Fail 'GVL_Status must initialize bProductionReady to FALSE.'
    }
}

$bindingFile = Get-ExactFile 'ST_HardwareBindingStatus' '.TcDUT'
if ($null -ne $bindingFile) {
    $bindingText = Get-Content -Raw -Encoding UTF8 -LiteralPath $bindingFile.FullName
    foreach ($field in @('bZAxisNcAssigned','bRAxisNcAssigned','bZAxisDriveLinked','bRAxisDriveLinked','bForceInputMapped','bDisplacementInputMapped','bCollisionInputMapped','bPeripheralIoMapped','bProductionHardwareBindingComplete')) {
        if ($bindingText -notmatch $field) { Fail "ST_HardwareBindingStatus is missing $field." }
    }
    if ($bindingText -match ':=\s*TRUE') { Fail 'Hardware binding status must not default any field TRUE.' }
}

foreach ($reportName in @('HARDWARE_MANUAL_BINDING_CHECKLIST.md','IO_MAPPING_TODO.md','NC_CONFIGURATION_CHECKLIST.md')) {
    $path = Join-Path $RepositoryRoot "Docs\报告\$reportName"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "Missing Phase 3 report: $path" }
}

if (Test-Path -LiteralPath $systemProjectPath -PathType Leaf) {
    $systemText = Get-Content -Raw -Encoding UTF8 -LiteralPath $systemProjectPath
    [xml]$systemXml = $systemText
    $sections = @($systemXml.TcSmProject.Project.ChildNodes | ForEach-Object { $_.Name })
    $ioConfigurationNodes = @($systemXml.SelectNodes('/TcSmProject/Project/Io/*'))
    if ($ioConfigurationNodes.Count -gt 0 -or 'Safety' -in $sections) {
        Fail "Forbidden hardware or Safety configuration present: $($sections -join ', ')"
    }
    if ('Motion' -notin $sections) { Fail 'Offline Motion/NC project is missing.' }
    else {
        $axisNames = @($systemXml.TcSmProject.Project.Motion.NC.Axis | ForEach-Object { [string]$_.Name })
        if ((@($axisNames | Sort-Object) -join '|') -ne 'R_Axis_NC|Z_Axis_NC') {
            Fail "Offline NC axes are incorrect: $($axisNames -join ', ')."
        }
        $safCycle100ns = [int]$systemXml.TcSmProject.Project.Motion.NC.SafTask.CycleTime
        $fastTask = Get-ExactFile 'Task_CffFast' '.TcTTO'
        if ($null -ne $fastTask) {
            [xml]$fastTaskXml = Get-Content -Raw -Encoding UTF8 -LiteralPath $fastTask.FullName
            if ([int]$fastTaskXml.TcPlcObject.Task.CycleTime -ne ($safCycle100ns / 10)) {
                Fail 'Task_CffFast cycle does not equal the actual NC SAF cycle.'
            }
        }

        $fastSystemTask = @($systemXml.TcSmProject.Project.System.Tasks.Task | Where-Object { $_.Name -eq 'Task_CffFast' })
        if ($fastSystemTask.Count -ne 1 -or [int]$fastSystemTask[0].CycleTime -ne $safCycle100ns) {
            Fail 'The TwinCAT system Task_CffFast cycle does not equal the actual NC SAF cycle.'
        }
        $fastPlcContext = @($systemXml.TcSmProject.Project.Plc.Project.Instance.Contexts.Context | Where-Object { $_.Name -eq 'Task_CffFast' })
        if ($fastPlcContext.Count -ne 1 -or [int]$fastPlcContext[0].CycleTime -ne ($safCycle100ns * 100)) {
            Fail 'The PLC Task_CffFast context does not equal the actual NC SAF cycle.'
        }

        $plcOwnerName = 'TIPC^CFFwelding^CFFwelding Instance'
        $plcOwner = @($systemXml.SelectNodes('/TcSmProject/Mappings/OwnerA') | Where-Object { $_.Name -eq $plcOwnerName })
        if ($plcOwner.Count -ne 1) {
            Fail 'The PLC-to-NC mapping owner is missing.'
        }
        else {
            foreach ($axisName in @('Z_Axis_NC','R_Axis_NC')) {
                $axisOwnerName = "TINC^NC_Cff SAF^Axes^$axisName"
                $axisOwner = @($plcOwner[0].OwnerB | Where-Object { $_.Name -eq $axisOwnerName })
                if ($axisOwner.Count -ne 1) {
                    Fail "Internal mapping owner is missing for $axisName."
                    continue
                }
                $axisStem = if ($axisName -eq 'Z_Axis_NC') { 'Z_axis' } else { 'R_axis' }
                $links = @($axisOwner[0].Link | ForEach-Object { "$($_.VarA)|$($_.VarB)" } | Sort-Object)
                $expectedLinks = @(
                    "Task_CffFast Inputs^GVL_IO.$axisStem.NcToPlc|Outputs^ToPlc",
                    "Task_CffFast Outputs^GVL_IO.$axisStem.PlcToNc|Inputs^FromPlc"
                ) | Sort-Object
                if (($links -join ';') -ne ($expectedLinks -join ';')) {
                    Fail "Internal PLC-to-NC links are incorrect for $axisName."
                }
            }
        }
    }
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

if ($failures.Count -gt 0) {
    Write-Host 'Phase 3 data and binding test: FAILED'
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}

Write-Host 'Phase 3 data and binding test: PASSED'
Write-Host "Enum count: $($enumNames.Count)"
Write-Host "Structure count: $($structureNames.Count)"
Write-Host "GVL count: $($gvlNames.Count)"
