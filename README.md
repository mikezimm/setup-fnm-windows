# Setup-FnmWindows.ps1

A PowerShell script to install and configure [Fast Node Manager (fnm)](https://github.com/Schniz/fnm) on Windows.

This script is intended to make it easy to set up `fnm` on a user’s machine. It handles detection of existing Node.js managers, installation via **winget**, and configuration of shell startup files so that `fnm` works automatically.

---

## Features

- Detects and warns if **nvm-windows** is installed (recommends uninstalling to avoid conflicts).
- Detects and warns if a system **Node.js** install is present (if fnm isn’t installed yet).
- Installs **fnm** via **winget** if not already installed.
- Configures `fnm env` for:
  - PowerShell (Windows PowerShell 5.x and PowerShell 7+ profiles, OneDrive-aware).
  - Command Prompt (via `profile.cmd` + registry AutoRun).
  - Git Bash (`~/.bashrc`).
- Adds the flag `--version-file-strategy=recursive` to `fnm env` for project-based version resolution.
- Reloads the current PowerShell profile so `fnm` is available immediately in the same session.
- Optionally installs and sets a default Node.js version (e.g. `22`, `lts`, or `latest`).
- Supports **DryRun** and **DetectOnly** modes.

---

## Parameters

### `-Shells`
Which shells to configure. Accepts one or more of:

- `pwsh` – PowerShell (Windows PowerShell 5.x and PowerShell 7+)
- `cmd` – Command Prompt
- `gitbash` – Git Bash

Default: `pwsh,cmd,gitbash`

```powershell
-Shells pwsh,cmd
```

### `-NodeVersion`
Install and set a default Node.js version using fnm.

```powershell
-NodeVersion 22
-NodeVersion lts
```

### `-DetectOnly`
Only check for nvm, fnm, and Node.js. Print findings and exit.  
No installations, file edits, or registry changes are made.

```powershell
-DetectOnly
```

### `-DryRun`
Preview what changes would be made (file writes, registry edits, installs).  
No actual modifications are made.

```powershell
-DryRun
```

---

## Usage Examples

### Detect environment only
```powershell
.\Setup-FnmWindows.ps1 -DetectOnly
```

### Preview changes for PowerShell and cmd
```powershell
.\Setup-FnmWindows.ps1 -Shells pwsh,cmd -DryRun
```

### Install fnm, configure all shells, and install Node.js 22
```powershell
.\Setup-FnmWindows.ps1 -Shells pwsh,cmd,gitbash -NodeVersion 22
```

### Configure only PowerShell (no Node install)
```powershell
.\Setup-FnmWindows.ps1 -Shells pwsh
```

---

## After Running

- For **PowerShell**, the script reloads your profile, so you can run `fnm --version` immediately.
- For **cmd** and **Git Bash**, you must open a **new terminal window** after running the script.

Validate installation with:

```powershell
fnm --version
node --version
```

---

## Notes

- If **nvm-windows** is detected, you should uninstall it before using fnm (they conflict in how they manage Node.js).
- If a **system Node.js** is detected and fnm is not installed yet, the script recommends uninstalling system Node to avoid conflicts.
- Requires **winget** (App Installer) to install fnm. If missing, install App Installer from the Microsoft Store.

---

## License

MIT – use at your own risk. Contributions welcome!
