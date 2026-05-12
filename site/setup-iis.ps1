param(
    [string]$SiteName = "MachineInfoSite",
    [string]$PhysicalPath = "C:\inetpub\wwwroot\machine-info",
    [int]$Port = 80,
    [string]$HostHeader = "",
    [switch]$TakeOverBinding = $true
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

function Set-IisSiteStaticConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteName
    )

    $psPath = "IIS:\"
    $location = $SiteName

    Set-WebConfigurationProperty -PSPath $psPath -Location $location -Filter "system.webServer/defaultDocument" -Name "enabled" -Value "True"

    Clear-WebConfiguration -PSPath $psPath -Location $location -Filter "system.webServer/defaultDocument/files"
    try {
        Add-WebConfigurationProperty -PSPath $psPath -Location $location -Filter "system.webServer/defaultDocument/files" -Name "." -Value @{ value = "index.html" }
    } catch {
        if ($_.Exception.Message -notmatch "duplicate collection entry") {
            throw
        }
    }
}

function Get-PrimaryIPv4Address {
    $candidates = @()

    if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
        $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -and
                $_.IPAddress -ne "127.0.0.1" -and
                $_.PrefixOrigin -ne "WellKnown"
            } |
            Select-Object -ExpandProperty IPAddress
    }

    if (-not $candidates) {
        $candidates = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            ForEach-Object { $_.IPAddressToString } |
            Where-Object { $_ -ne "127.0.0.1" }
    }

    return ($candidates | Select-Object -First 1)
}

$machineHostName = [System.Net.Dns]::GetHostName()
$machineIpAddress = Get-PrimaryIPv4Address
if ([string]::IsNullOrWhiteSpace($machineIpAddress)) {
    $machineIpAddress = "Unavailable"
}

$indexPath = Join-Path $PhysicalPath "index.html"
$indexContent = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Machine Info</title>
</head>
<body>
  <h1>Machine Info</h1>
  <p>Served by IIS as static HTML</p>

  <table>
    <tr>
      <td>Hostname</td>
      <td>{{SERVER_NAME}}</td>
    </tr>
    <tr>
      <td>Server IP</td>
      <td>{{LOCAL_ADDR}}</td>
    </tr>
    <tr>
      <td>Server Port</td>
      <td>{{SERVER_PORT}}</td>
    </tr>
    <tr>
      <td>Timestamp (UTC)</td>
      <td>{{DATE_GMT}}</td>
    </tr>
  </table>
</body>
</html>
"@
$indexContent = $indexContent.Replace('{{SERVER_NAME}}', $machineHostName)
$indexContent = $indexContent.Replace('{{LOCAL_ADDR}}', $machineIpAddress)
$indexContent = $indexContent.Replace('{{SERVER_PORT}}', $Port)
$indexContent = $indexContent.Replace('{{DATE_GMT}}', [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss 'UTC'"))
Set-Content -Path $indexPath -Value $indexContent

if (Test-Path -Path (Join-Path $PhysicalPath "web.config")) {
    Remove-Item -Path (Join-Path $PhysicalPath "web.config") -Force -ErrorAction SilentlyContinue
}
if (Test-Path -Path (Join-Path $PhysicalPath "index.shtml")) {
    Remove-Item -Path (Join-Path $PhysicalPath "index.shtml") -Force -ErrorAction SilentlyContinue
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

$conflictingSites = Get-Website | Where-Object {
    if ($_.Name -eq $SiteName) {
        return $false
    }

    $siteBindings = Get-WebBinding -Name $_.Name -ErrorAction SilentlyContinue
    if (-not $siteBindings) {
        return $false
    }

    $siteBindings | Where-Object {
        $_.protocol -eq "http" -and $_.bindingInformation -eq $bindingInformation
    }
}

if ($conflictingSites) {
    if (-not $TakeOverBinding) {
        $siteNames = ($conflictingSites | ForEach-Object { "'$($_.Name)'" }) -join ", "
        throw "Binding conflict: '$bindingInformation' is already used by $siteNames. Re-run with -TakeOverBinding to automatically remove conflicting bindings."
    }

    foreach ($site in $conflictingSites) {
        Write-Host "Removing conflicting binding '$bindingInformation' from site '$($site.Name)'..." -ForegroundColor Yellow
        Remove-WebBinding -Name $site.Name -Protocol "http" -Port $Port -HostHeader $HostHeader
    }
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

Write-Host "Applying IIS default document configuration..." -ForegroundColor Cyan
try {
    Set-IisSiteStaticConfiguration -SiteName $SiteName
} catch {
    throw "Failed to apply IIS site configuration for '$SiteName'. Original error: $($_.Exception.Message)"
}

$siteState = (Get-Website -Name $SiteName).State
if ($siteState -ne "Started") {
    Start-WebAppPool -Name $appPoolName -ErrorAction SilentlyContinue
    try {
        Start-Website -Name $SiteName
    } catch {
        $siteBindings = (Get-WebBinding -Name $SiteName -ErrorAction SilentlyContinue | ForEach-Object { $_.bindingInformation }) -join ", "
        $appPoolState = (Get-WebAppPoolState -Name $appPoolName -ErrorAction SilentlyContinue).Value
        throw "Failed to start IIS site '$SiteName'. AppPool='$appPoolName' State='$appPoolState' Bindings='$siteBindings'. Original error: $($_.Exception.Message)"
    }
}

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
