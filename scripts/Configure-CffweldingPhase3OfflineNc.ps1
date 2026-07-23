[CmdletBinding()]
param([string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$solutionPath = Join-Path $RepositoryRoot 'CFFwelding.sln'
$systemProjectPath = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding_System.tsproj'
$ncTaskPath = 'TINC^NC_Cff SAF'
$axesPath = "$ncTaskPath^Axes"
$axisNames = @('Z_Axis_NC', 'R_Axis_NC')
$dte = $null
$solution = $null

[xml]$systemXmlBefore = Get-Content -Raw -Encoding UTF8 -LiteralPath $systemProjectPath
$sectionsBefore = @($systemXmlBefore.TcSmProject.Project.ChildNodes | ForEach-Object { $_.Name })
$ioConfigurationBefore = @($systemXmlBefore.SelectNodes('/TcSmProject/Project/Io/*'))
if ($ioConfigurationBefore.Count -gt 0 -or 'Safety' -in $sectionsBefore) {
    throw "A hardware or Safety configuration already exists: $($sectionsBefore -join ', ')"
}

try {
    $dte = New-Object -ComObject 'TcXaeShell.DTE.15.0'
    $dte.UserControl = $false
    $dte.SuppressUI = $true
    $dte.MainWindow.Visible = $false
    $automationSettings = $dte.GetObject('TcAutomationSettings')
    if ($null -eq $automationSettings) {
        throw 'TwinCAT automation settings are unavailable.'
    }
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

    if (-not $systemManager.TestItemPath($ncTaskPath)) {
        $ncRoot = $systemManager.LookupTreeItem('TINC')
        [void]$ncRoot.CreateChild('NC_Cff', 1)
        Write-Host 'Created offline NC task: NC_Cff SAF'
    }
    else {
        Write-Host 'Offline NC task already exists: NC_Cff SAF'
    }

    $axes = $systemManager.LookupTreeItem($axesPath)
    foreach ($axisName in $axisNames) {
        $axisPath = "$axesPath^$axisName"
        if (-not $systemManager.TestItemPath($axisPath)) {
            [void]$axes.CreateChild($axisName, 1)
            Write-Host "Created unbound offline NC axis: $axisName"
        }
        else {
            Write-Host "Offline NC axis already exists: $axisName"
        }
    }

    $unexpectedAxes = @()
    for ($index = 1; $index -le $axes.ChildCount; $index++) {
        $childName = [string]$axes.Child($index).Name
        if ($childName -notin $axisNames) { $unexpectedAxes += $childName }
    }
    if ($unexpectedAxes.Count -gt 0) {
        throw "Unexpected NC axes exist: $($unexpectedAxes -join ', ')"
    }

    $systemProject.Save()
    $solution.SaveAs($solutionPath)
    $dte.ExecuteCommand('File.SaveAll')

    [xml]$systemXmlAfter = Get-Content -Raw -Encoding UTF8 -LiteralPath $systemProjectPath
    $sectionsAfter = @($systemXmlAfter.TcSmProject.Project.ChildNodes | ForEach-Object { $_.Name })
    $ioConfigurationAfter = @($systemXmlAfter.SelectNodes('/TcSmProject/Project/Io/*'))
    if ($ioConfigurationAfter.Count -gt 0 -or 'Safety' -in $sectionsAfter) {
        throw "Offline NC creation introduced a forbidden section: $($sectionsAfter -join ', ')"
    }
    Write-Host 'Phase 3 offline NC creation: PASSED'
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
