# AGENTS.md

## Repo reality (verify first)
- This repository currently only contains devcontainer setup under `.devcontainer/`.
- There are no app/library source files, no test suite, and no package/build manifests at repo root.
- Treat this as environment/bootstrap infrastructure unless new project files are added.

## High-signal files
- `.devcontainer/devcontainer.json`: container definition, mounted host credentials, shell defaults.
- `.devcontainer/Dockerfile`: base image and installed tooling (PowerShell, Node.js 20, global `opencode-ai`).
- `.devcontainer/devcontainer-lock.json`: pinned devcontainer feature digests.

## Toolchain and environment quirks
- Default interactive shell is PowerShell (`pwsh`), not bash.
- `postCreateCommand` changes `vscode` user's shell to `pwsh`; assume PowerShell-first workflows when adding scripts.
- Node.js 20 is explicitly installed in the container.
- Devcontainer mounts host `~/.gitconfig`, `~/.git-credentials`, and OpenCode auth (`~/.local/share/opencode/auth.json`) into `/root/...`; do not commit or expose credential material.

## Change guidance for agents
- If asked to add project automation (test/lint/build), define commands explicitly because no repo standard exists yet.
- Prefer updating `.devcontainer/devcontainer.json` + `.devcontainer/Dockerfile` together when changing developer environment behavior.
- Re-verify assumptions with file inspection before claiming the repo has runtime entrypoints or CI workflows.
