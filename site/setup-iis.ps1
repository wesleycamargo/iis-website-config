param(
    [string]$SiteName = "MachineInfoSite",
    [string]$PhysicalPath = "C:\inetpub\wwwroot\machine-info",
    [int]$Port = 80,
    [string]$HostHeader = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw "This script must be run from an elevated PowerShell session (Run as Administrator)."
}

Write-Host "Installing IIS features..." -ForegroundColor Cyan

if (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue) {
    Install-WindowsFeature Web-Server, Web-Static-Content, Web-Default-Doc, Web-Http-Errors, Web-Includes | Out-Null
} elseif (Get-Command Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
    $featureNames = @(
        "IIS-WebServerRole",
        "IIS-WebServer",
        "IIS-CommonHttpFeatures",
        "IIS-StaticContent",
        "IIS-DefaultDocument",
        "IIS-HttpErrors",
        "IIS-ServerSideIncludes"
    )

    foreach ($featureName in $featureNames) {
        Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart | Out-Null
    }
} else {
    throw "Unable to install IIS features: neither Install-WindowsFeature nor Enable-WindowsOptionalFeature is available."
}

Import-Module WebAdministration

Write-Host "Ensuring IIS service is running..." -ForegroundColor Cyan
Set-Service -Name W3SVC -StartupType Automatic
if ((Get-Service -Name W3SVC).Status -ne "Running") {
    Start-Service -Name W3SVC
}

Write-Host "Preparing site files..." -ForegroundColor Cyan
if (-not (Test-Path -Path $PhysicalPath)) {
    New-Item -Path $PhysicalPath -ItemType Directory -Force | Out-Null
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$filesToCopy = @("index.shtml", "styles.css", "web.config")

foreach ($file in $filesToCopy) {
    $source = Join-Path $scriptRoot $file
    if (-not (Test-Path -Path $source)) {
        throw "Required file not found: $source"
    }
    Copy-Item -Path $source -Destination (Join-Path $PhysicalPath $file) -Force
}

$appPoolName = "$SiteName-AppPool"

if (-not (Test-Path "IIS:\AppPools\$appPoolName")) {
    New-WebAppPool -Name $appPoolName | Out-Null
}

$bindingInformation = if ([string]::IsNullOrWhiteSpace($HostHeader)) {
    "*:${Port}:"
} else {
    "*:${Port}:$HostHeader"
}

if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
    Write-Host "Updating existing site '$SiteName'..." -ForegroundColor Yellow
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name physicalPath -Value $PhysicalPath
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name applicationPool -Value $appPoolName

    Get-WebBinding -Name $SiteName | Remove-WebBinding
    New-WebBinding -Name $SiteName -Protocol "http" -Port $Port -HostHeader $HostHeader | Out-Null
} else {
    Write-Host "Creating IIS site '$SiteName'..." -ForegroundColor Cyan
    New-Website -Name $SiteName -PhysicalPath $PhysicalPath -Port $Port -HostHeader $HostHeader -ApplicationPool $appPoolName | Out-Null
}

Start-Website -Name $SiteName

$localUrl = if ([string]::IsNullOrWhiteSpace($HostHeader)) {
    "http://localhost:${Port}/"
} else {
    "http://${HostHeader}:${Port}/"
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host "Site Name    : $SiteName"
Write-Host "Physical Path: $PhysicalPath"
Write-Host "Binding      : $bindingInformation"
Write-Host "URL          : $localUrl"
