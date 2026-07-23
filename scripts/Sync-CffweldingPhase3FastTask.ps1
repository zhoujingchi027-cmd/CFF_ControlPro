[CmdletBinding()]
param([string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$solutionPath = Join-Path $RepositoryRoot 'CFFwelding.sln'
$systemProjectPath = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding_System.tsproj'
$plcTaskPath = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding\Tasks\Task_CffFast.TcTTO'

[xml]$systemXmlBefore = Get-Content -Raw -Encoding UTF8 -LiteralPath $systemProjectPath
$safCycle100ns = [int]$systemXmlBefore.TcSmProject.Project.Motion.NC.SafTask.CycleTime
if ($safCycle100ns -le 0 -or ($safCycle100ns % 10) -ne 0) {
    throw "Invalid NC SAF cycle: $safCycle100ns x 100 ns"
}

[xml]$plcTaskXml = Get-Content -Raw -Encoding UTF8 -LiteralPath $plcTaskPath
$plcCycleUs = [int]$plcTaskXml.TcPlcObject.Task.CycleTime
if ($plcCycleUs -ne ($safCycle100ns / 10)) {
    throw "PLC Task_CffFast cycle $plcCycleUs us does not match NC SAF cycle $safCycle100ns x 100 ns."
}

$dte = $null
$solution = $null
try {
    $dte = New-Object -ComObject 'TcXaeShell.DTE.15.0'
    $dte.UserControl = $false
    $dte.SuppressUI = $true
    $dte.MainWindow.Visible = $false
    $automationSettings = $dte.GetObject('TcAutomationSettings')
    if ($null -eq $automationSettings) { throw 'TwinCAT automation settings are unavailable.' }
    $automationSettings.SilentMode = $true

    $solution = $dte.Solution
    $solution.Open($solutionPath)

    $systemProject = $null
    $systemManager = $null
    for ($attempt = 1; $attempt -le 90 -and $null -eq $systemManager; $attempt++) {
        try {
            if ($solution.Projects.Count -ge 1) {
                $systemProject = $solution.Projects.Item(1)
                $systemManager = $systemProject.Object
            }
        }
        catch [System.Runtime.InteropServices.COMException] {
            $errorCode = '0x{0:X8}' -f ($_.Exception.HResult -band 0xffffffffL)
            if ($errorCode -notin @('0x80010001', '0x8001010A')) { throw }
        }
        if ($null -eq $systemManager) { Start-Sleep -Milliseconds 500 }
    }
    if ($null -eq $systemManager) { throw 'ITcSysManager did not become available.' }

    $fastTask = $systemManager.LookupTreeItem('TIRT^Task_CffFast')
    [xml]$fastTaskXml = $fastTask.ProduceXml($false)
    if ([int]$fastTaskXml.TreeItem.TaskDef.Priority -ne 10) {
        throw 'Task_CffFast priority is no longer 10; refusing an ambiguous update.'
    }

    if ([int]$fastTaskXml.TreeItem.TaskDef.CycleTime -ne $safCycle100ns) {
        $consumeXml = "<TreeItem><TaskDef><CycleTime>$safCycle100ns</CycleTime></TaskDef></TreeItem>"
        $fastTask.ConsumeXml($consumeXml)
        Write-Host "Updated system Task_CffFast cycle: $safCycle100ns x 100 ns"
    }
    else {
        Write-Host "System Task_CffFast cycle already synchronized: $safCycle100ns x 100 ns"
    }

    [xml]$fastTaskXmlAfter = $fastTask.ProduceXml($false)
    if ([int]$fastTaskXmlAfter.TreeItem.TaskDef.CycleTime -ne $safCycle100ns) {
        throw 'TwinCAT did not accept the Task_CffFast cycle update.'
    }

    $systemProject.Save()
    $solution.SaveAs($solutionPath)
    $dte.ExecuteCommand('File.SaveAll')
    Write-Host 'Phase 3 fast task synchronization: PASSED'
}
finally {
    if ($null -ne $solution) {
        try { $solution.Close($true) } catch { Write-Warning $_.Exception.Message }
    }
    if ($null -ne $dte) {
        try { $dte.Quit() } catch { Write-Warning $_.Exception.Message }
        if ([System.Runtime.InteropServices.Marshal]::IsComObject($dte)) {
            try { [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($dte) } catch { }
        }
    }
}
