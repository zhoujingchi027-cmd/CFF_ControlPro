[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$solutionPath = Join-Path $RepositoryRoot 'CFFwelding.sln'
$dte = $null
$solution = $null

try {
    $dte = New-Object -ComObject 'TcXaeShell.DTE.15.0'
    $dte.UserControl = $false
    $dte.SuppressUI = $true
    $dte.MainWindow.Visible = $false
    $automationSettings = $dte.GetObject('TcAutomationSettings')
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
            if ($errorCode -notin @('0x80010001', '0x8001010A')) {
                throw
            }
        }
        if ($null -eq $systemManager) {
            Start-Sleep -Milliseconds 500
        }
    }
    if ($null -eq $systemManager) {
        throw 'ITcSysManager did not become available.'
    }

    $desiredPath = 'TIRT^Task_CffMain'
    $legacyPath = 'TIRT^PlcTask'
    if ($systemManager.TestItemPath($desiredPath)) {
        if ($systemManager.TestItemPath($legacyPath)) {
            throw 'Both Task_CffMain and legacy PlcTask exist; refusing an ambiguous rename.'
        }
        Write-Host 'System task already synchronized: Task_CffMain'
    }
    else {
        if (-not $systemManager.TestItemPath($legacyPath)) {
            throw 'Neither Task_CffMain nor the validated legacy PlcTask exists.'
        }

        $mainTask = $systemManager.LookupTreeItem($legacyPath)
        [xml]$taskXml = $mainTask.ProduceXml($false)
        if ([int]$taskXml.TreeItem.TaskDef.Priority -ne 20 -or
            [int]$taskXml.TreeItem.TaskDef.CycleTime -ne 100000) {
            throw 'Legacy PlcTask does not match the expected Phase 1 main task definition.'
        }

        $mainTask.Name = 'Task_CffMain'
        if (-not $systemManager.TestItemPath($desiredPath)) {
            throw 'TwinCAT XAE did not expose the renamed Task_CffMain node.'
        }
        Write-Host 'Renamed validated system task: PlcTask -> Task_CffMain'
    }

    $systemProject.Save()
    $solution.SaveAs($solutionPath)
    $dte.ExecuteCommand('File.SaveAll')
    Write-Host 'Phase 2 system task synchronization: PASSED'
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
