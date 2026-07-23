[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$Configuration = 'Release|TwinCAT RT (x64)'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$solutionPath = Join-Path $RepositoryRoot 'CFFwelding.sln'
$dteProgId = 'TcXaeShell.DTE.15.0'

if (-not (Test-Path -LiteralPath $solutionPath -PathType Leaf)) {
    throw "Solution was not found: $solutionPath"
}

$dte = $null
$solution = $null

try {
    Write-Host "Starting TwinCAT XAE Shell build: $dteProgId"
    $dte = New-Object -ComObject $dteProgId
    $dte.UserControl = $false
    $dte.SuppressUI = $true
    $dte.MainWindow.Visible = $false

    $automationSettings = $dte.GetObject('TcAutomationSettings')
    if ($null -eq $automationSettings) {
        throw 'TwinCAT automation settings are unavailable; silent build cannot be guaranteed.'
    }
    $automationSettings.SilentMode = $true

    $solution = $dte.Solution
    $solution.Open($solutionPath)

    $systemProject = $null
    for ($attempt = 1; $attempt -le 90 -and $null -eq $systemProject; $attempt++) {
        try {
            if ($solution.Projects.Count -ge 1) {
                $candidate = $solution.Projects.Item(1)
                if ($candidate.Name -eq 'CFFwelding_System' -and $null -ne $candidate.Object) {
                    $systemProject = $candidate
                    break
                }
            }
        }
        catch [System.Runtime.InteropServices.COMException] {
            $errorCode = '0x{0:X8}' -f ($_.Exception.HResult -band 0xffffffffL)
            if ($errorCode -notin @('0x80010001', '0x8001010A')) {
                throw
            }
        }

        if ($attempt -eq 90) {
            throw 'CFFwelding_System did not finish loading before the build timeout.'
        }
        Start-Sleep -Milliseconds 500
    }

    # XAE may expose the System Project object before Visual Studio has populated
    # SolutionBuild.SolutionConfigurations. Wait for that second asynchronous
    # load boundary as well, otherwise larger PLC projects can fail before Build.
    $availableConfigurations = @()
    $configurationLoadError = $null
    for ($attempt = 1; $attempt -le 90 -and $availableConfigurations.Count -eq 0; $attempt++) {
        try {
            $availableConfigurations = @(
                foreach ($solutionConfiguration in $solution.SolutionBuild.SolutionConfigurations) {
                    "$($solutionConfiguration.Name)|$($solutionConfiguration.PlatformName)"
                }
            )
            $configurationLoadError = $null
        }
        catch {
            # During asynchronous XAE solution loading the automation proxy can
            # briefly omit SolutionConfigurations or reject the COM call.
            $configurationLoadError = $_.Exception
            $availableConfigurations = @()
        }

        if ($availableConfigurations.Count -eq 0) {
            if ($attempt -eq 90) {
                $detail = if ($null -eq $configurationLoadError) { 'no configuration was exposed' } else { $configurationLoadError.Message }
                throw "TwinCAT solution configurations did not finish loading before the build timeout: $detail"
            }
            Start-Sleep -Milliseconds 500
        }
    }
    if ($Configuration -notin $availableConfigurations) {
        throw "Build configuration '$Configuration' is unavailable. Available: $($availableConfigurations -join ', ')"
    }

    Write-Host "Building project '$($systemProject.UniqueName)' with '$Configuration'."
    $solution.SolutionBuild.BuildProject($Configuration, $systemProject.UniqueName, $true)

    $failedProjectCount = [int]$solution.SolutionBuild.LastBuildInfo
    if ($failedProjectCount -ne 0) {
        throw "TwinCAT XAE build failed; LastBuildInfo reports $failedProjectCount failed project(s)."
    }

    Write-Host 'CFFwelding XAE build: PASSED'
    Write-Host "Configuration: $Configuration"
    Write-Host "LastBuildInfo: $failedProjectCount"
}
finally {
    if ($null -ne $solution) {
        try {
            $solution.Close($false)
        }
        catch {
            Write-Warning "TwinCAT solution close reported: $($_.Exception.Message)"
        }
    }
    if ($null -ne $dte) {
        try {
            $dte.Quit()
        }
        catch {
            Write-Warning "TwinCAT XAE Shell quit reported: $($_.Exception.Message)"
        }

        if ([System.Runtime.InteropServices.Marshal]::IsComObject($dte)) {
            try {
                [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($dte)
            }
            catch {
                Write-Warning "DTE COM release reported: $($_.Exception.Message)"
            }
        }
    }
}
