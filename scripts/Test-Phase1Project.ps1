[CmdletBinding()]
param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}

$failures = New-Object 'System.Collections.Generic.List[string]'

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $failures.Add($Message)
}

function Test-RequiredFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing required file: $Path"
        return $false
    }

    return $true
}

function Read-Utf8Strict {
    param([Parameter(Mandatory = $true)][string]$Path)

    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        return $encoding.GetString([System.IO.File]::ReadAllBytes($Path))
    }
    catch {
        Add-Failure "File is not valid UTF-8: $Path"
        return $null
    }
}

$solutionPath = Join-Path $RepositoryRoot 'CFFwelding.sln'
$systemProjectPath = Join-Path $RepositoryRoot 'CFFwelding_System\CFFwelding_System.tsproj'

$solutionExists = Test-RequiredFile -Path $solutionPath
$systemProjectExists = Test-RequiredFile -Path $systemProjectPath

$plcProjects = @(
    Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -Filter 'CFFwelding.plcproj' -ErrorAction SilentlyContinue
)

if ($plcProjects.Count -ne 1) {
    Add-Failure "Expected exactly one CFFwelding.plcproj; found $($plcProjects.Count)."
}

if ($solutionExists) {
    $solutionText = Read-Utf8Strict -Path $solutionPath
    if ($null -ne $solutionText) {
        if ($solutionText -notmatch 'CFFwelding_System') {
            Add-Failure 'Solution does not reference CFFwelding_System.'
        }
    }
}

if ($systemProjectExists) {
    $systemProjectText = Read-Utf8Strict -Path $systemProjectPath
    if ($null -ne $systemProjectText) {
        try {
            [void][xml]$systemProjectText
        }
        catch {
            Add-Failure "TwinCAT system project is not valid XML: $systemProjectPath"
        }

        $forbiddenHardware = @('EP3174', 'AX5000', 'TwinSAFE', 'IO-Link')
        foreach ($token in $forbiddenHardware) {
            if ($systemProjectText -match [regex]::Escape($token)) {
                Add-Failure "Phase 1 system project contains forbidden hardware token: $token"
            }
        }
    }
}

if ($plcProjects.Count -eq 1) {
    $plcProjectText = Read-Utf8Strict -Path $plcProjects[0].FullName
    if ($null -ne $plcProjectText) {
        try {
            [void][xml]$plcProjectText
        }
        catch {
            Add-Failure "PLC project is not valid XML: $($plcProjects[0].FullName)"
        }

        foreach ($libraryName in @('Tc2_Standard', 'Tc2_MC2')) {
            if ($plcProjectText -notmatch [regex]::Escape($libraryName)) {
                Add-Failure "PLC project does not reference required library: $libraryName"
            }
        }
    }
}

$unexpectedProjectFiles = @(
    Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '(?i)(EP3174|AX5000|TwinSAFE|IO-Link)'
        }
)

if ($unexpectedProjectFiles.Count -gt 0) {
    Add-Failure "Unexpected Phase 1 hardware/generated files: $($unexpectedProjectFiles.FullName -join ', ')"
}

if ($failures.Count -gt 0) {
    Write-Host 'Phase 1 acceptance test: FAILED'
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    exit 1
}

Write-Host 'Phase 1 acceptance test: PASSED'
Write-Host "Solution: $solutionPath"
Write-Host "System project: $systemProjectPath"
Write-Host "PLC project: $($plcProjects[0].FullName)"
