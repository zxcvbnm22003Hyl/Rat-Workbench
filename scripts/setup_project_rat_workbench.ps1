param(
    [string]$WorkspaceRoot = (Join-Path $PSScriptRoot ".."),
    [string]$ProxyUrl = "",
    [switch]$DisableProxy,
    [switch]$Launch
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

function Set-ProxyEnvironment {
    param(
        [string]$ProxyUrlValue,
        [switch]$DisableProxyValue
    )

    $proxyKeys = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy")

    if ($DisableProxyValue) {
        foreach ($key in $proxyKeys) {
            Set-Item -Path ("Env:" + $key) -Value "" -ErrorAction SilentlyContinue
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($ProxyUrlValue)) {
        return
    }

    foreach ($key in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")) {
        Set-Item -Path ("Env:" + $key) -Value $ProxyUrlValue.Trim()
    }
}

$WorkspaceRoot = Get-AbsolutePath -PathString $WorkspaceRoot
$runtimeScript = Join-Path $WorkspaceRoot "scripts\setup_project_rat_runtime.ps1"
$bootstrapScript = Join-Path $WorkspaceRoot "scripts\bootstrap_project_rat_workspace.ps1"
$guiEntry = Join-Path $WorkspaceRoot "project_rat_gui.py"
$venvPython = Join-Path $WorkspaceRoot ".qt-venv\Scripts\python.exe"
$condaPython = Join-Path $WorkspaceRoot ".qt-conda-env\python.exe"
$cctWorkbenchRoot = Join-Path $WorkspaceRoot "cct-workbench"

Set-ProxyEnvironment -ProxyUrlValue $ProxyUrl -DisableProxyValue:$DisableProxy

Write-Step "Preparing GUI runtime"
& $runtimeScript -WorkspaceRoot $WorkspaceRoot
if ($LASTEXITCODE -ne 0) {
    throw "GUI runtime setup failed with exit code $LASTEXITCODE"
}

Write-Step "Bootstrapping upstream workspace"
& $bootstrapScript -WorkspaceRoot $WorkspaceRoot
if ($LASTEXITCODE -ne 0) {
    throw "Workspace bootstrap failed with exit code $LASTEXITCODE"
}

Write-Step "Ensuring magnet design workspace"
New-Item -ItemType Directory -Path $cctWorkbenchRoot -Force | Out-Null
Write-Host ("CCT workbench root: " + $cctWorkbenchRoot)

Write-Host ""
Write-Host "Rat-Workbench setup completed."
Write-Host "You can now open the GUI and start designing magnets."

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

    throw "No GUI runtime interpreter was found after setup."
}
