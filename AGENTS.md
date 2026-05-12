# AGENTS.md

## Repo shape (current)
- This repo has two concerns only: devcontainer setup in `.devcontainer/` and an IIS static SSI site in `site/`.
- There is no root app, no package/build manifests, no test/lint/typecheck config, and no CI workflows.

## High-value files
- `site/setup-iis.ps1`: primary automation; installs IIS features, downloads `site/` from GitHub, configures bindings/site/app pool, and validates SSI config.
- `site/web.config`: enables SSI (`serverSideInclude`), sets `index.shtml` as default document, and maps `.shtml` to `text/html`.
- `site/index.shtml`: page template using SSI echo variables.
- `.devcontainer/devcontainer.json` + `.devcontainer/Dockerfile`: PowerShell-first dev environment and installed tooling.

## Commands you can trust
- Local IIS setup (Windows, elevated PowerShell): `./site/setup-iis.ps1`
- Optional conflict behavior (from script):
  - Take over conflicting HTTP binding (default): `./site/setup-iis.ps1 -TakeOverBinding:$true`
  - Fail on binding conflict: `./site/setup-iis.ps1 -TakeOverBinding:$false`

## IIS/SSI gotchas
- If `site/web.config` is removed, equivalent IIS site/server-level settings must be configured manually or SSI/default document behavior will break.
- `setup-iis.ps1` expects to run as Administrator and throws if not elevated.
- The setup script rewrites `site/index.shtml` in deployment path by replacing `SERVER_NAME` and `LOCAL_ADDR` SSI placeholders with concrete machine values.

## Devcontainer quirks
- Default shell is `pwsh` (`postCreateCommand` changes `vscode` shell); prefer PowerShell snippets when documenting commands.
- Devcontainer mounts host OpenCode auth into `/root/.local/share/opencode/auth.json`; never print or commit credential-bearing files.
- Dockerfile installs Node.js 20 and global `opencode-ai`; treat these as environment dependencies, not project runtime deps.
