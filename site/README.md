# IIS Static Machine Info Site

This folder contains a simple IIS-hosted static HTML page that displays server details.

## What it shows

- Hostname (`SERVER_NAME`)
- Server IP (`LOCAL_ADDR`)
- Server port (`SERVER_PORT`)
- Current UTC timestamp (`DATE_GMT`)

## Requirements

- IIS with static content support (included in standard Web Server install).

## Deploy

1. Run `setup-iis.ps1` as Administrator.
2. The script creates `index.html` in the configured IIS physical path.
3. Browse to the site URL.

## Automated setup script

Run this as Administrator to install IIS features, create a dedicated website, and generate `index.html`:

```powershell
./setup-iis.ps1
```

One-line install with `iex` (downloads installer from this repository and runs it):

```powershell
iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/wesleycamargo/iis-website-config/main/site/setup-iis.ps1'))
```

Optional parameters:

```powershell
./setup-iis.ps1 -SiteName "MachineInfoSite" -PhysicalPath "C:\inetpub\wwwroot\machine-info" -Port 8080 -HostHeader ""
```

By default, the script is idempotent on the selected port and will take over a conflicting HTTP binding from another site (for example `Default Web Site` on port `80`).

To disable this behavior and fail on conflicts instead:

```powershell
./setup-iis.ps1 -TakeOverBinding:$false
```
