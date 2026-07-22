[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ComWithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Operation,
        [Parameter(Mandatory = $true)][string]$Description,
        [int]$MaximumAttempts = 90,
        [int]$DelayMilliseconds = 500,
        [switch]$RequireNonNull
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $result = & $Operation
            if (-not $RequireNonNull -or $null -ne $result) {
                Write-Output -NoEnumerate $result
                return
            }

            if ($attempt -eq $MaximumAttempts) {
                throw "$Description did not become available after $MaximumAttempts attempts."
            }
            if ($attempt -eq 1 -or ($attempt % 10) -eq 0) {
                Write-Warning "$Description is not available yet; retry $attempt/$MaximumAttempts."
            }
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
        catch [System.Runtime.InteropServices.COMException] {
            $errorCode = '0x{0:X8}' -f ($_.Exception.HResult -band 0xffffffffL)
            $isTransient = $errorCode -in @('0x80010001', '0x8001010A')
            if (-not $isTransient -or $attempt -eq $MaximumAttempts) {
                throw
            }

            if ($attempt -eq 1 -or ($attempt % 10) -eq 0) {
                Write-Warning "$Description is temporarily busy ($errorCode); retry $attempt/$MaximumAttempts."
            }
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
}

function Wait-TwinCatTreeItem {
    param(
        [Parameter(Mandatory = $true)]$SystemManager,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaximumAttempts = 90,
        [int]$DelayMilliseconds = 500
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            if ($SystemManager.TestItemPath($Path)) {
                return
            }
        }
        catch [System.Runtime.InteropServices.COMException] {
            $errorCode = '0x{0:X8}' -f ($_.Exception.HResult -band 0xffffffffL)
            if ($errorCode -notin @('0x80010001', '0x8001010A')) {
                throw
            }
        }

        if ($attempt -eq $MaximumAttempts) {
            throw "TwinCAT tree item did not become available: $Path"
        }
        if ($attempt -eq 1 -or ($attempt % 10) -eq 0) {
            Write-Warning "TwinCAT tree item is not available yet; retry $attempt/${MaximumAttempts}: $Path"
        }
        Start-Sleep -Milliseconds $DelayMilliseconds
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$solutionName = 'CFFwelding'
$systemProjectName = 'CFFwelding_System'
$plcProjectName = 'CFFwelding'
$solutionPath = Join-Path $RepositoryRoot "$solutionName.sln"
$systemProjectDirectory = Join-Path $RepositoryRoot $systemProjectName
$systemProjectPath = Join-Path $systemProjectDirectory "$systemProjectName.tsproj"
$expectedPlcProjectPath = Join-Path $systemProjectDirectory "$plcProjectName\$plcProjectName.plcproj"
$twinCatTemplate = 'C:\TwinCAT\3.1\Components\Base\PrjTemplate\TwinCAT Project.tsproj'
$sysManagerInterop = 'C:\Program Files (x86)\Beckhoff\TcXaeShell\Common7\IDE\Extensions\Beckhoff Automation GmbH\TwinCAT HMI\TCatSysManagerLib.dll'
$dteProgId = 'TcXaeShell.DTE.15.0'

if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot '.git') -PathType Container)) {
    throw "Repository root is not the expected independent Git repository: $RepositoryRoot"
}

if (-not (Test-Path -LiteralPath $twinCatTemplate -PathType Leaf)) {
    throw "TwinCAT project template was not found: $twinCatTemplate"
}
if (-not (Test-Path -LiteralPath $sysManagerInterop -PathType Leaf)) {
    throw "TwinCAT System Manager interop assembly was not found: $sysManagerInterop"
}
$sysManagerAssembly = [System.Reflection.Assembly]::LoadFrom($sysManagerInterop)
$plcLibraryManagerType = $sysManagerAssembly.GetType('TCatSysManagerLib._ITcPlcLibraryManager', $true)

$resumeEmptySolution = $false
$resumeSystemProject = $false
$resumePlcProject = $false
$mc2AlreadyPresent = $false
if (Test-Path -LiteralPath $solutionPath -PathType Leaf) {
    $existingSolutionText = Get-Content -Raw -LiteralPath $solutionPath
    if ($existingSolutionText -notmatch 'Microsoft Visual Studio Solution File') {
        throw "Refusing to resume because the existing solution header is invalid: $solutionPath"
    }

    $existingProjectLines = @([regex]::Matches($existingSolutionText, '(?m)^Project\('))
    if ($existingProjectLines.Count -eq 0) {
        if (Test-Path -LiteralPath $systemProjectDirectory) {
            $existingSystemEntries = @(Get-ChildItem -Force -LiteralPath $systemProjectDirectory)
            if ($existingSystemEntries.Count -gt 0) {
                throw "Refusing to overwrite non-empty Phase 1 output: $systemProjectDirectory"
            }
        }
        $resumeEmptySolution = $true
    }
    elseif ($existingProjectLines.Count -eq 1 -and
        $existingSolutionText -match '"CFFwelding_System", "CFFwelding_System\\CFFwelding_System\.tsproj"' -and
        (Test-Path -LiteralPath $systemProjectPath -PathType Leaf)) {
        $existingPlcProjects = @(Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter '*.plcproj')
        if ($existingPlcProjects.Count -eq 1 -and
            $existingPlcProjects[0].FullName -eq $expectedPlcProjectPath) {
            $resumePlcProject = $true
            $mc2AlreadyPresent = (Get-Content -Raw -LiteralPath $expectedPlcProjectPath) -match 'Tc2_MC2'
        }
        elseif ($existingPlcProjects.Count -gt 0) {
            throw 'Refusing to resume an unexpected partially populated PLC project; manual inspection is required.'
        }
        $resumeSystemProject = $true
    }
    else {
        throw "Refusing to resume because the existing solution has unexpected projects: $solutionPath"
    }
}
elseif (Test-Path -LiteralPath $systemProjectDirectory) {
    throw "Refusing to overwrite existing Phase 1 output: $systemProjectDirectory"
}

$dte = $null
$solution = $null
$systemProject = $null
$systemManager = $null
$plcRoot = $null
$plcProject = $null
$references = $null
$libraryManager = $null
$referencesUnknown = [System.IntPtr]::Zero
$automationSettings = $null

try {
    Write-Host "Starting TwinCAT XAE Shell automation: $dteProgId"
    $dte = New-Object -ComObject $dteProgId
    $dte.UserControl = $false
    $dte.SuppressUI = $true
    $dte.MainWindow.Visible = $false

    $automationSettings = Invoke-ComWithRetry -Description 'Get TwinCAT automation settings' -Operation {
        $dte.GetObject('TcAutomationSettings')
    }
    if ($null -eq $automationSettings) {
        throw 'TwinCAT automation settings are unavailable; silent creation cannot be guaranteed.'
    }
    $automationSettings.SilentMode = $true

    $solution = $dte.Solution
    if ($resumeEmptySolution -or $resumeSystemProject) {
        Write-Host "Resuming the validated partial Phase 1 solution: $solutionPath"
        Invoke-ComWithRetry -Description 'Open empty solution' -Operation {
            $solution.Open($solutionPath)
        }
    }
    else {
        Invoke-ComWithRetry -Description 'Create solution' -Operation {
            $solution.Create($RepositoryRoot, $solutionName)
        }
        Invoke-ComWithRetry -Description 'Save solution' -Operation {
            $solution.SaveAs($solutionPath)
        }
    }

    if ($resumeSystemProject) {
        $systemProject = Invoke-ComWithRetry -Description 'Get existing TwinCAT system project' -RequireNonNull -Operation {
            if ($solution.Projects.Count -lt 1) {
                return $null
            }
            $solution.Projects.Item(1)
        }
    }
    else {
        if (-not (Test-Path -LiteralPath $systemProjectDirectory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $systemProjectDirectory)
        }
        Write-Host "Adding TwinCAT system project: $systemProjectName"
        $systemProject = Invoke-ComWithRetry -Description 'Add TwinCAT system project from template' -RequireNonNull -Operation {
            $solution.AddFromTemplate(
                $twinCatTemplate,
                $systemProjectDirectory,
                $systemProjectName
            )
        }
    }

    if ($null -eq $systemProject) {
        $systemProject = $solution.Projects.Item(1)
    }
    if ($null -eq $systemProject) {
        throw 'TwinCAT system project was not returned by XAE Shell.'
    }

    $systemManager = Invoke-ComWithRetry -Description 'Get ITcSysManager' -RequireNonNull -Operation {
        $systemProject.Object
    }
    if ($null -eq $systemManager) {
        throw 'ITcSysManager could not be obtained from the TwinCAT system project.'
    }

    Write-Host "Creating PLC project from Standard PLC Template: $plcProjectName"
    $plcTreePath = "TIPC^$plcProjectName"
    if ($resumePlcProject) {
        Write-Host "Resuming the validated standard PLC project: $expectedPlcProjectPath"
        Wait-TwinCatTreeItem -SystemManager $systemManager -Path $plcTreePath
        $plcProject = $systemManager.LookupTreeItem($plcTreePath)
    }
    else {
        Wait-TwinCatTreeItem -SystemManager $systemManager -Path 'TIPC'
        $plcRoot = $systemManager.LookupTreeItem('TIPC')

        for ($attempt = 1; $attempt -le 90 -and $null -eq $plcProject; $attempt++) {
            try {
                $plcProject = $plcRoot.CreateChild($plcProjectName, 0, '', 'Standard PLC Template')
            }
            catch [System.Runtime.InteropServices.COMException] {
                $errorCode = '0x{0:X8}' -f ($_.Exception.HResult -band 0xffffffffL)
                if ($errorCode -notin @('0x80010001', '0x8001010A')) {
                    throw
                }

                if ($systemManager.TestItemPath($plcTreePath)) {
                    $plcProject = $systemManager.LookupTreeItem($plcTreePath)
                    break
                }
                if ($attempt -eq 90) {
                    throw
                }
                if ($attempt -eq 1 -or ($attempt % 10) -eq 0) {
                    Write-Warning "Create PLC project is temporarily busy ($errorCode); retry $attempt/90."
                }
                Start-Sleep -Milliseconds 500
            }
        }
    }
    if ($null -eq $plcProject) {
        throw 'TwinCAT XAE did not return the created PLC project tree item.'
    }

    $referencesPath = "TIPC^$plcProjectName^$plcProjectName Project^References"
    Wait-TwinCatTreeItem -SystemManager $systemManager -Path $referencesPath
    $references = $systemManager.LookupTreeItem($referencesPath)
    $referencesUnknown = [System.Runtime.InteropServices.Marshal]::GetIUnknownForObject($references)
    $libraryManager = [System.Runtime.InteropServices.Marshal]::GetTypedObjectForIUnknown(
        $referencesUnknown,
        $plcLibraryManagerType
    )
    if ($null -eq $libraryManager) {
        throw "ITcPlcLibraryManager could not be obtained at: $referencesPath"
    }

    if ($mc2AlreadyPresent) {
        Write-Host 'Required motion library is already present: Tc2_MC2'
    }
    else {
        Write-Host 'Adding required motion library: Tc2_MC2 3.3.65.0'
        Invoke-ComWithRetry -Description 'Add Tc2_MC2 library' -Operation {
            $libraryManager.AddLibrary('Tc2_MC2', '3.3.65.0', 'Beckhoff Automation GmbH')
        }
    }

    Invoke-ComWithRetry -Description 'Save TwinCAT system project' -Operation {
        $systemProject.Save()
    }
    Invoke-ComWithRetry -Description 'Save solution' -Operation {
        $solution.SaveAs($solutionPath)
    }
    Invoke-ComWithRetry -Description 'Save all XAE files' -Operation {
        $dte.ExecuteCommand('File.SaveAll')
    }

    if (-not (Test-Path -LiteralPath $solutionPath -PathType Leaf)) {
        throw "XAE Shell did not create the expected solution: $solutionPath"
    }
    if (-not (Test-Path -LiteralPath $systemProjectPath -PathType Leaf)) {
        throw "XAE Shell did not create the expected system project: $systemProjectPath"
    }

    $plcProjectFiles = @(Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter "$plcProjectName.plcproj")
    if ($plcProjectFiles.Count -ne 1) {
        throw "Expected exactly one $plcProjectName.plcproj after creation; found $($plcProjectFiles.Count)."
    }

    Write-Host 'Phase 1 project creation completed.'
    Write-Host "Solution: $solutionPath"
    Write-Host "System project: $systemProjectPath"
    Write-Host "PLC project: $($plcProjectFiles[0].FullName)"
}
finally {
    if ($null -ne $solution) {
        try {
            $solution.Close($true)
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
    }

    if ($referencesUnknown -ne [System.IntPtr]::Zero) {
        try {
            [void][System.Runtime.InteropServices.Marshal]::Release($referencesUnknown)
        }
        catch {
            Write-Warning "IUnknown release reported: $($_.Exception.Message)"
        }
    }

    if ($null -ne $dte -and [System.Runtime.InteropServices.Marshal]::IsComObject($dte)) {
        try {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($dte)
        }
        catch {
            Write-Warning "DTE COM release reported: $($_.Exception.Message)"
        }
    }
}
