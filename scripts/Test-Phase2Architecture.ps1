[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$plcRoot = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding'
$plcProjectPath = Join-Path $plcRoot 'CFFwelding.plcproj'
$systemProjectPath = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding_System.tsproj'
$failures = New-Object 'System.Collections.Generic.List[string]'

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Get-SingleProjectFile {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Extension
    )

    $matches = @(Get-ChildItem -LiteralPath $plcRoot -Recurse -File -Filter "$Name$Extension" -ErrorAction SilentlyContinue)
    if ($matches.Count -ne 1) {
        Add-Failure "Expected exactly one $Name$Extension; found $($matches.Count)."
        return $null
    }
    return $matches[0]
}

$fastPrograms = @(
    'PRG_FastInputs',
    'PRG_CffSequence',
    'PRG_FastAxisControl',
    'PRG_FastMonitoring'
)
$mainPrograms = @(
    'PRG_ModeControl',
    'PRG_RobotInterface',
    'PRG_CommandDispatcher',
    'PRG_ProgramManager',
    'PRG_InitializeControl',
    'PRG_ServiceCalibration',
    'PRG_MaintenanceControl',
    'PRG_ManualControl',
    'PRG_AutoControl',
    'PRG_FastenerControl',
    'PRG_FeederControl',
    'PRG_ClampControl',
    'PRG_MachineMain',
    'PRG_AlarmControl',
    'PRG_TowerLightControl'
)
$slowPrograms = @(
    'PRG_HmiAdsInterface',
    'PRG_ResultTraceability',
    'PRG_Statistics',
    'PRG_Persistence'
)
$interfaceTypes = @(
    'ST_ZForceControlInput',
    'ST_ZForceControlOutput',
    'ST_ZExtSetpointCommand',
    'ST_ZExtSetpointStatus',
    'ST_ZAxisCommand',
    'ST_ZAxisStatus',
    'ST_RAxisCommand',
    'ST_RAxisStatus',
    'ST_ContactDetectInput',
    'ST_ContactDetectOutput',
    'ST_StepCriterionInput',
    'ST_StepCriterionOutput',
    'ST_CffSequenceCommand',
    'ST_CffSequenceStatus'
)

if (-not (Test-Path -LiteralPath $plcProjectPath -PathType Leaf)) {
    Add-Failure "Missing PLC project: $plcProjectPath"
    $plcProjectText = ''
}
else {
    $plcProjectText = Get-Content -Raw -Encoding UTF8 -LiteralPath $plcProjectPath
}

foreach ($programName in @($fastPrograms + $mainPrograms + $slowPrograms)) {
    $programFile = Get-SingleProjectFile -Name $programName -Extension '.TcPOU'
    if ($null -eq $programFile) {
        continue
    }

    $programText = Get-Content -Raw -Encoding UTF8 -LiteralPath $programFile.FullName
    if ($programText -notmatch "PROGRAM\s+$([regex]::Escape($programName))") {
        Add-Failure "$programName is not declared as a PROGRAM."
    }
    if ($programText -notmatch '程序骨架') {
        Add-Failure "$programName does not contain the required Chinese skeleton block comment."
    }
    if ($plcProjectText -notmatch [regex]::Escape($programFile.Name)) {
        Add-Failure "PLC project does not compile $($programFile.Name)."
    }
}

foreach ($typeName in $interfaceTypes) {
    $typeFile = Get-SingleProjectFile -Name $typeName -Extension '.TcDUT'
    if ($null -eq $typeFile) {
        continue
    }

    $typeText = Get-Content -Raw -Encoding UTF8 -LiteralPath $typeFile.FullName
    if ($typeText -notmatch "TYPE\s+$([regex]::Escape($typeName))\s*:") {
        Add-Failure "$typeName does not contain the expected TYPE declaration."
    }
    if ($typeText -notmatch 'STRUCT' -or $typeText -notmatch '\(\*') {
        Add-Failure "$typeName is not a documented STRUCT interface."
    }
    if ($plcProjectText -notmatch [regex]::Escape($typeFile.Name)) {
        Add-Failure "PLC project does not compile $($typeFile.Name)."
    }
}

$expectedFastCycleUs = 10000
$requiresSafTodo = $true
if (Test-Path -LiteralPath $systemProjectPath -PathType Leaf) {
    [xml]$phaseAwareSystemXml = Get-Content -Raw -Encoding UTF8 -LiteralPath $systemProjectPath
    if ($null -ne $phaseAwareSystemXml.TcSmProject.Project.Motion.NC.SafTask) {
        $safCycle100ns = [int]$phaseAwareSystemXml.TcSmProject.Project.Motion.NC.SafTask.CycleTime
        if (($safCycle100ns % 10) -ne 0) {
            Add-Failure "NC SAF cycle cannot be represented in PLC task microseconds: $safCycle100ns x 100 ns."
        }
        else {
            $expectedFastCycleUs = $safCycle100ns / 10
            $requiresSafTodo = $false
        }
    }
}

$taskDefinitions = @(
    [pscustomobject]@{ Name = 'Task_CffFast'; CycleUs = $expectedFastCycleUs; Calls = $fastPrograms; RequiresSafTodo = $requiresSafTodo },
    [pscustomobject]@{ Name = 'Task_CffMain'; CycleUs = 10000; Calls = $mainPrograms; RequiresSafTodo = $false },
    [pscustomobject]@{ Name = 'Task_CffSlow'; CycleUs = 50000; Calls = $slowPrograms; RequiresSafTodo = $false }
)

foreach ($taskDefinition in $taskDefinitions) {
    $taskFile = Get-SingleProjectFile -Name $taskDefinition.Name -Extension '.TcTTO'
    if ($null -eq $taskFile) {
        continue
    }

    $taskText = Get-Content -Raw -Encoding UTF8 -LiteralPath $taskFile.FullName
    try {
        [xml]$taskXml = $taskText
        $taskNode = $taskXml.TcPlcObject.Task
        if ($taskNode.Name -ne $taskDefinition.Name) {
            Add-Failure "Task name mismatch in $($taskFile.Name)."
        }
        if ([int]$taskNode.CycleTime -ne $taskDefinition.CycleUs) {
            Add-Failure "$($taskDefinition.Name) cycle must be $($taskDefinition.CycleUs) us for the current phase configuration."
        }
        $actualCalls = @($taskNode.PouCall | ForEach-Object { $_.Name })
        if (($actualCalls -join '|') -ne ($taskDefinition.Calls -join '|')) {
            Add-Failure "$($taskDefinition.Name) POU call order is incorrect."
        }
    }
    catch {
        Add-Failure "Task file is not valid XML: $($taskFile.FullName)"
    }

    if ($taskDefinition.RequiresSafTodo -and $taskText -notmatch 'TODO_NC_SAF') {
        Add-Failure 'Task_CffFast must state that its Phase 2 cycle is provisional until NC SAF is measured.'
    }
    if (-not $taskDefinition.RequiresSafTodo -and $taskDefinition.Name -eq 'Task_CffFast' -and $taskText -notmatch 'NC_Cff SAF') {
        Add-Failure 'Task_CffFast must document the Phase 3 NC SAF cycle source.'
    }
    if ($plcProjectText -notmatch [regex]::Escape($taskFile.Name)) {
        Add-Failure "PLC project does not compile $($taskFile.Name)."
    }
}

if ($plcProjectText -match 'POUs\\MAIN\.TcPOU' -or $plcProjectText -match 'Include="PlcTask\.TcTTO"') {
    Add-Failure 'Default MAIN/PlcTask objects must be replaced by the Phase 2 architecture.'
}

foreach ($reportName in @('INSTANCE_OWNERSHIP_MATRIX.md', 'INTERNAL_INTERFACE_CATALOG.md')) {
    $reportPath = Join-Path $RepositoryRoot "Docs\报告\$reportName"
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        Add-Failure "Missing Phase 2 report: $reportPath"
    }
}

if (Test-Path -LiteralPath $systemProjectPath -PathType Leaf) {
    [xml]$systemXml = Get-Content -Raw -Encoding UTF8 -LiteralPath $systemProjectPath
    $systemSections = @($systemXml.TcSmProject.Project.ChildNodes | ForEach-Object { $_.Name })
    if (@($systemXml.SelectNodes('/TcSmProject/Project/Io/*')).Count -gt 0) {
        Add-Failure 'The project unexpectedly contains configured I/O nodes.'
    }
    if ('Safety' -in $systemSections) {
        Add-Failure 'The project unexpectedly contains a Safety section.'
    }

    $expectedSystemTaskNames = @('Task_CffFast', 'Task_CffMain', 'Task_CffSlow')
    $actualSystemTaskNames = @($systemXml.TcSmProject.Project.System.Tasks.Task | ForEach-Object { [string]$_.Name })
    if ((@($actualSystemTaskNames | Sort-Object) -join '|') -ne (@($expectedSystemTaskNames | Sort-Object) -join '|')) {
        Add-Failure "TwinCAT System task names are incorrect: $($actualSystemTaskNames -join ', ')."
    }

    $actualContextNames = @($systemXml.TcSmProject.Project.Plc.Project.Instance.Contexts.Context | ForEach-Object { [string]$_.Name })
    if (($actualContextNames -join '|') -ne ($expectedSystemTaskNames -join '|')) {
        Add-Failure "PLC context order is incorrect: $($actualContextNames -join ', ')."
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Phase 2 architecture test: FAILED'
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    exit 1
}

Write-Host 'Phase 2 architecture test: PASSED'
Write-Host "PROGRAM count: $($fastPrograms.Count + $mainPrograms.Count + $slowPrograms.Count)"
Write-Host "Interface DUT count: $($interfaceTypes.Count)"
Write-Host "Task count: $($taskDefinitions.Count)"
