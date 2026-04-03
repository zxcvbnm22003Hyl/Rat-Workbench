param(
    [string]$WorkspaceRoot = (Join-Path $PSScriptRoot ".."),
    [ValidateSet("install-rat-models", "install-rat-models-no-nl")]
    [string]$RatInstallAction = "install-rat-models-no-nl",
    [string]$ProxyUrl = "",
    [switch]$DisableProxy,
    [switch]$Launch,
    [switch]$SkipBuildToolsInstall,
    [switch]$SkipBootstrapVcpkg,
    [switch]$SkipRatInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AbsolutePath {
    param([Parameter(Mandatory = $true)][string]$PathString)

    if ([System.IO.Path]::IsPathRooted($PathString)) {
        return [System.IO.Path]::GetFullPath($PathString)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $PathString))
}

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host ""
    Write-Host ("=== " + $Message + " ===")
}

function Find-ClExecutable {
    $fromPath = Get-Command cl.exe -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    $localRoot = Join-Path $WorkspaceRoot "tools\msvc-local\VC\Tools\MSVC"
    if (Test-Path $localRoot) {
        $candidate = Get-ChildItem -Path $localRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "bin\Hostx64\x64\cl.exe" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($candidate) {
            return $candidate
        }
    }

    $vsWhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $installationPathRaw = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
        if ($installationPathRaw) {
            $installationPath = $installationPathRaw.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($installationPath)) {
                $candidate = Get-ChildItem -Path (Join-Path $installationPath "VC\Tools\MSVC") -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    ForEach-Object { Join-Path $_.FullName "bin\Hostx64\x64\cl.exe" } |
                    Where-Object { Test-Path $_ } |
                    Select-Object -First 1
                if ($candidate) {
                    return $candidate
                }
            }
        }
    }

    return $null
}

function Invoke-ManagerAction {
    param(
        [Parameter(Mandatory = $true)][string]$ManagerScript,
        [Parameter(Mandatory = $true)][string]$Action
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $ManagerScript,
        "-Action",
        $Action,
        "-WorkspaceRoot",
        $WorkspaceRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
        $arguments += @("-ProxyUrl", $ProxyUrl.Trim())
    }
    if ($DisableProxy) {
        $arguments += "-DisableProxy"
    }

    & powershell.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw ("project_rat_manager.ps1 failed for action '" + $Action + "' with exit code " + $LASTEXITCODE)
    }
}

function Ensure-BuildToolsInstalled {
    param([Parameter(Mandatory = $true)][string]$InstallerPath)

    $clPath = Find-ClExecutable
    if ($clPath) {
        Write-Host ("[ok] MSVC C++ toolchain detected: " + $clPath)
        return
    }

    if (-not (Test-Path $InstallerPath)) {
        throw "Visual Studio Build Tools bootstrapper was not found: $InstallerPath"
    }

    Write-Step "Installing Visual Studio Build Tools"
    Write-Host "This step may trigger a UAC elevation prompt and can take a long time."

    $argumentList = @(
        "--quiet",
        "--wait",
        "--norestart",
        "--nocache",
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--includeRecommended"
    )

    $process = Start-Process -FilePath $InstallerPath -ArgumentList $argumentList -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw ("Visual Studio Build Tools installation failed with exit code " + $process.ExitCode)
    }

    $clPath = Find-ClExecutable
    if (-not $clPath) {
        throw "Visual Studio Build Tools installation completed, but cl.exe is still not available."
    }

    Write-Host ("[ok] MSVC C++ toolchain installed: " + $clPath)
}

$WorkspaceRoot = Get-AbsolutePath -PathString $WorkspaceRoot
$designReadyScript = Join-Path $WorkspaceRoot "scripts\setup_project_rat_workbench.ps1"
$managerScript = Join-Path $WorkspaceRoot "scripts\project_rat_manager.ps1"
$buildToolsInstaller = Join-Path $WorkspaceRoot "tools\vs_BuildTools.exe"
$guiEntry = Join-Path $WorkspaceRoot "project_rat_gui.py"
$venvPython = Join-Path $WorkspaceRoot ".qt-venv\Scripts\python.exe"
$condaPython = Join-Path $WorkspaceRoot ".qt-conda-env\python.exe"

Write-Step "Preparing design-ready workspace"
$designReadyArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $designReadyScript,
    "-WorkspaceRoot",
    $WorkspaceRoot
)
if (-not [string]::IsNullOrWhiteSpace($ProxyUrl)) {
    $designReadyArgs += @("-ProxyUrl", $ProxyUrl.Trim())
}
if ($DisableProxy) {
    $designReadyArgs += "-DisableProxy"
}

& powershell.exe @designReadyArgs
if ($LASTEXITCODE -ne 0) {
    throw ("setup_project_rat_workbench.ps1 failed with exit code " + $LASTEXITCODE)
}

if (-not $SkipBuildToolsInstall) {
    Ensure-BuildToolsInstalled -InstallerPath $buildToolsInstaller
}

if (-not $SkipBootstrapVcpkg) {
    Write-Step "Bootstrapping vcpkg"
    Invoke-ManagerAction -ManagerScript $managerScript -Action "bootstrap-vcpkg"
}

if (-not $SkipRatInstall) {
    Write-Step ("Installing Project-Rat libraries via " + $RatInstallAction)
    Invoke-ManagerAction -ManagerScript $managerScript -Action $RatInstallAction
}

Write-Host ""
Write-Host "Rat-Workbench full environment setup completed."
Write-Host "The machine should now be ready for GUI-based magnet design and local Project-Rat builds."

if ($Launch) {
    Write-Step "Launching Rat-Workbench"
    if (Test-Path $venvPython) {
        & $venvPython $guiEntry
        exit $LASTEXITCODE
    }

    if (Test-Path $condaPython) {
        & $condaPython $guiEntry
        exit $LASTEXITCODE
    }

    throw "No GUI runtime interpreter was found after full environment setup."
}
