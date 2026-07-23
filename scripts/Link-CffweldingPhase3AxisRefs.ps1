[CmdletBinding()]
param([string]$RepositoryRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$solutionPath = Join-Path $RepositoryRoot 'CFFwelding.sln'
$systemProjectPath = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding_System.tsproj'
$plcOwner = 'TIPC^CFFwelding^CFFwelding Instance'
$axisDefinitions = @(
    @{ AxisName = 'Z_Axis_NC'; PlcStem = 'Z_axis' },
    @{ AxisName = 'R_Axis_NC'; PlcStem = 'R_axis' }
)

function Get-ExistingLinkKeys {
    param([string]$ProjectPath)

    [xml]$projectXml = Get-Content -Raw -Encoding UTF8 -LiteralPath $ProjectPath
    $keys = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($ownerA in @($projectXml.SelectNodes('/TcSmProject/Mappings/OwnerA'))) {
        foreach ($ownerB in @($ownerA.OwnerB)) {
            foreach ($link in @($ownerB.Link)) {
                $pathA = "$($ownerA.Name)^$($link.VarA)"
                $pathB = "$($ownerB.Name)^$($link.VarB)"
                [void]$keys.Add("$pathA|$pathB")
                [void]$keys.Add("$pathB|$pathA")
            }
        }
    }
    return ,$keys
}

$existingLinkKeys = Get-ExistingLinkKeys -ProjectPath $systemProjectPath
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

    foreach ($axis in $axisDefinitions) {
        $axisOwner = "TINC^NC_Cff SAF^Axes^$($axis.AxisName)"
        $pairs = @(
            @{
                Plc = "$plcOwner^Task_CffFast Inputs^GVL_IO.$($axis.PlcStem).NcToPlc"
                Nc = "$axisOwner^Outputs^ToPlc"
            },
            @{
                Plc = "$plcOwner^Task_CffFast Outputs^GVL_IO.$($axis.PlcStem).PlcToNc"
                Nc = "$axisOwner^Inputs^FromPlc"
            }
        )

        foreach ($pair in $pairs) {
            if (-not $systemManager.TestItemPath($pair.Plc)) {
                throw "PLC process image variable is missing: $($pair.Plc)"
            }
            if (-not $systemManager.TestItemPath($pair.Nc)) {
                throw "NC process image variable is missing: $($pair.Nc)"
            }

            $key = "$($pair.Plc)|$($pair.Nc)"
            if ($existingLinkKeys.Contains($key)) {
                Write-Host "Internal link already exists: $($axis.AxisName) $($pair.Plc.Split('.')[-1])"
            }
            else {
                $systemManager.LinkVariables($pair.Plc, $pair.Nc)
                Write-Host "Created internal PLC-to-NC link: $($axis.AxisName) $($pair.Plc.Split('.')[-1])"
            }
        }
    }

    $systemProject.Save()
    $solution.SaveAs($solutionPath)
    $dte.ExecuteCommand('File.SaveAll')

    $savedLinkKeys = Get-ExistingLinkKeys -ProjectPath $systemProjectPath
    foreach ($axis in $axisDefinitions) {
        $axisOwner = "TINC^NC_Cff SAF^Axes^$($axis.AxisName)"
        $expectedPairs = @(
            "$plcOwner^Task_CffFast Inputs^GVL_IO.$($axis.PlcStem).NcToPlc|$axisOwner^Outputs^ToPlc",
            "$plcOwner^Task_CffFast Outputs^GVL_IO.$($axis.PlcStem).PlcToNc|$axisOwner^Inputs^FromPlc"
        )
        foreach ($expectedPair in $expectedPairs) {
            if (-not $savedLinkKeys.Contains($expectedPair)) {
                throw "Saved project is missing internal mapping: $expectedPair"
            }
        }
    }

    Write-Host 'Phase 3 internal AXIS_REF mapping: PASSED'
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
