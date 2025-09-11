param(
  # Choose which shells to configure.
  [Parameter()]
  [ValidateSet('pwsh','cmd','gitbash')]
  [string[]]$Shells = @('pwsh','cmd','gitbash'),

  # Optional: install and set a default Node.js version (e.g., '22', 'lts', 'latest')
  [Parameter()]
  [string]$NodeVersion,

  # Report only: do not change anything, do not install or write files/registry.
  [Parameter()]
  [switch]$DetectOnly,

  # Preview mode: show what would be changed, but make no changes.
  [Parameter()]
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Test-Command {
  param([Parameter(Mandatory)][string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "$([char]0x2714) $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "$([char]0x26A0) $msg" -ForegroundColor DarkYellow }
function Write-Warn($msg) { Write-Host "$([char]0x21B7) $msg" -ForegroundColor Yellow }
function Write-Do ($msg)  {
  if ($DryRun) {
    Write-Host "[DRY RUN] $msg" -ForegroundColor Magenta
  } else {
    Write-Host "$msg"
  }
}

# Resolve the actual Documents folder (handles OneDrive Known Folder Move)
function Get-DocumentsPath {
  $docs = [Environment]::GetFolderPath('MyDocuments')
  if ([string]::IsNullOrWhiteSpace($docs)) {
    $docs = Join-Path $env:USERPROFILE 'Documents'  # rare fallback
  }
  return $docs
}

# Refresh PATH from registry (safe enum overload to avoid "User" parser issues)
function Refresh-ProcessPath {
  if ($DryRun) {
    Write-Do "Would refresh process PATH from registry (User + Machine)"
    return
  }

  $userPath    = [Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::User)
  $machinePath = [Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine)
  $newPath     = @($userPath, $machinePath) -join ';'

  if (-not [string]::IsNullOrWhiteSpace($newPath)) {
    $env:Path = $newPath
    Write-Ok "Refreshed process PATH from registry"
  } else {
    Write-Skip "Registry PATH values were empty; left current process PATH unchanged"
  }
}

# Add a line to a file if not present (respects DryRun)
function Ensure-LineInFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Line
  )

  $dir             = Split-Path $Path
  $needsCreateDir  = -not (Test-Path $dir)
  $needsCreateFile = -not (Test-Path $Path)

  if ($needsCreateDir)  { Write-Do "Would create directory: $dir" }
  if ($needsCreateFile) { Write-Do "Would create file: $Path" }

  $content = if (Test-Path $Path) { Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue } else { @() }
  $hasLine = $content -and (($content -join "`n") -match [regex]::Escape($Line))

  if ($hasLine) {
    Write-Skip "Already configured: $Path"
    return
  }

  if ($DryRun) {
    Write-Do "Would append line to $($Path):`n$Line"
  } else {
    if ($needsCreateDir)  { New-Item -ItemType Directory -Path $dir | Out-Null }
    if ($needsCreateFile) { New-Item -ItemType File -Path $Path | Out-Null }
    Add-Content -LiteralPath $Path -Value $Line
    Write-Ok "Updated: $Path"
  }
}

# Try to find fnm.exe directly if PATH isn't updated yet
function Resolve-FnmPath {
  $cmd = Get-Command fnm -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Path }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\fnm.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\fnm\fnm.exe'),
    (Join-Path $env:ProgramFiles  'fnm\fnm.exe'),
    (Join-Path $env:ProgramFiles  'Fnm\fnm.exe')
  )

  foreach ($p in $candidates) {
    if (Test-Path $p) {
      $dir = Split-Path $p
      if ($env:Path -notlike "*$dir*") {
        if ($DryRun) {
          Write-Do "Would temporarily add '$dir' to PATH"
        } else {
          $env:Path = ($dir + ';' + $env:Path)
          Write-Ok ("Temporarily added '{0}' to PATH" -f $dir)
        }
      }
      return $p
    }
  }

  return $null
}

# SAFE nvm-windows detection (no executing nvm.exe -> no popup)
function Detect-Nvm {
  if ($env:NVM_HOME -or $env:NVM_SYMLINK) { return $true }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'nvm\nvm.exe'),
    (Join-Path $env:ProgramFiles  'nvm\nvm.exe')
  )

  foreach ($p in $candidates) {
    if (Test-Path $p) { return $true }
  }

  return $false
}

# -------------------------
# DETECTION (nvm, fnm, node)
# -------------------------
Write-Step "Checking for other Node managers/installations"
if (Detect-Nvm) {
  Write-Warn "Detected nvm for Windows. It's recommended to uninstall nvm before using fnm to avoid PATH conflicts."
}

Write-Step "Checking for fnm"
$hasFnm = Test-Command -Name "fnm"

if (-not $hasFnm) {
  if (Test-Command -Name "node") {
    $nodeVer = (node --version) 2>$null
    Write-Warn "Detected a system Node.js installation ($nodeVer). It's recommended to uninstall system Node before switching to fnm-managed Node versions."
  } else {
    Write-Skip "No system Node detected (fnm will manage Node versions after setup)."
  }
} else {
  $fnmVer = (fnm --version) 2>$null
  Write-Ok "fnm already installed ($fnmVer)"
}

# -------- DetectOnly exits BEFORE any changes ----------
if ($DetectOnly) {
  Write-Step "DetectOnly mode complete — no changes were made."
  if ($Shells -contains 'cmd')     { Write-Host "To enable fnm in cmd later: run this script without -DetectOnly." }
  if ($Shells -contains 'gitbash') { Write-Host "To enable fnm in Git Bash later: run this script without -DetectOnly." }
  exit 0
}

# -------------------------
# Install fnm (if missing)
# -------------------------
if (-not $hasFnm) {
  Write-Step "Checking for winget"
  if (-not (Test-Command -Name "winget")) {
    Write-Host "❌ winget not found. Install 'App Installer' from the Microsoft Store, then re-run." -ForegroundColor Red
    exit 1
  }

  Write-Step "Installing fnm via winget (Schniz.fnm)"
  if ($DryRun) {
    Write-Do "Would run: winget install -e --id Schniz.fnm --accept-source-agreements --accept-package-agreements"
  } else {
    winget install -e --id Schniz.fnm --accept-source-agreements --accept-package-agreements
  }

  # Make the current session aware of fnm (skip in DryRun)
  if (-not $DryRun) {
    if (Test-Path Function:\Refresh-ProcessPath) {
      Refresh-ProcessPath
    } else {
      Write-Skip "Refresh-ProcessPath not available; skipping PATH refresh"
    }
  }

  $fnmPath = Resolve-FnmPath
  $hasFnm  = [bool]$fnmPath
  if (-not $hasFnm) { $hasFnm = Test-Command -Name "fnm" }

  if ($hasFnm) {
    if ($fnmPath) { $ver = & $fnmPath --version 2>$null } else { $ver = & fnm --version 2>$null }
    Write-Ok "fnm installed ($ver)"
  } else {
    throw "fnm installation succeeded but the command isn't resolvable in this session. Try opening a new shell."
  }
}

# Ensure we have an invokable fnm command (path or name)
$resolvedFnm = Resolve-FnmPath
if ($resolvedFnm) { $Global:FnmCmd = $resolvedFnm } else { $Global:FnmCmd = 'fnm' }

# Shared flag for all shells
$RecursiveFlag = '--version-file-strategy=recursive'

# -------------------------
# PowerShell (Windows PS5 & PS7+) — OneDrive-aware + live reload
# -------------------------
if ($Shells -contains 'pwsh') {
  Write-Step "Configuring PowerShell profiles for fnm"

  $docs       = Get-DocumentsPath
  $ps5Profile = Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
  $ps7Profile = Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
  $psSnippet  = "fnm env --use-on-cd $RecursiveFlag --shell powershell | Out-String | Invoke-Expression"

  Ensure-LineInFile -Path $ps5Profile -Line $psSnippet
  Ensure-LineInFile -Path $ps7Profile -Line $psSnippet

  if ($docs -like "*OneDrive*") { Write-Skip "Detected OneDrive Documents path: $docs" }

  # Reload current host's profile so fnm is active right away here
  Write-Step "Reloading current PowerShell profile"
  if ($DryRun) {
    Write-Do "Would dot-source: . `$PROFILE"
  } else {
    try {
      if (Test-Path $PROFILE) {
        . $PROFILE
        Write-Ok "Profile reloaded"
      } else {
        Write-Skip "Current host has no profile file yet ($PROFILE)"
      }
    } catch {
      Write-Skip "Couldn't reload profile automatically; open a NEW PowerShell window."
    }
  }
}

# -------------------------
# Git Bash (~/.bashrc)
# -------------------------
if ($Shells -contains 'gitbash') {
  Write-Step "Configuring Git Bash (~/.bashrc) for fnm"

  $bashrc      = Join-Path $env:USERPROFILE '.bashrc'
  $bashSnippet = 'eval "$(fnm env --use-on-cd --version-file-strategy=recursive --shell bash)"'

  Ensure-LineInFile -Path $bashrc -Line $bashSnippet
  Write-Skip "Open a NEW Git Bash window to use fnm (current PowerShell session cannot reload Git Bash)."
}

# -------------------------
# Command Prompt (cmd) via HKCU AutoRun
# -------------------------
if ($Shells -contains 'cmd') {
  Write-Step "Configuring Command Prompt (cmd) AutoRun for fnm"

  $profileCmd = Join-Path $env:USERPROFILE 'profile.cmd'
  $cmdScript  = @"
@echo off
REM Guard to prevent recursion
if not defined FNM_AUTORUN_GUARD (
  set "FNM_AUTORUN_GUARD=AutorunGuard"
  FOR /f "tokens=*" %%z IN ('fnm env --use-on-cd --version-file-strategy=recursive') DO CALL %%z
)
"@

  if ($DryRun) {
    Write-Do "Would write/replace $profileCmd with fnm env bootstrap script"
  } else {
    if (!(Test-Path $profileCmd) -or ((Get-Content $profileCmd -Raw) -ne $cmdScript)) {
      Set-Content -Path $profileCmd -Value $cmdScript -Encoding ASCII
      Write-Ok "Updated $profileCmd"
    } else {
      Write-Skip "Already configured: $profileCmd"
    }
  }

  $autoRunKey = 'HKCU:\Software\Microsoft\Command Processor'
  if ($DryRun) {
    Write-Do "Would set/append HKCU:\Software\Microsoft\Command Processor\AutoRun to include: $profileCmd"
  } else {
    New-Item -Path $autoRunKey -Force | Out-Null
    $currentAutoRun = (Get-ItemProperty -Path $autoRunKey -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
    if ([string]::IsNullOrWhiteSpace($currentAutoRun)) {
      New-ItemProperty -Path $autoRunKey -Name AutoRun -Value $profileCmd -PropertyType String -Force | Out-Null
      Write-Ok "Set cmd AutoRun -> $profileCmd"
    } elseif ($currentAutoRun -ne $profileCmd -and $currentAutoRun -notmatch [regex]::Escape($profileCmd)) {
      $new = "$currentAutoRun & `"$profileCmd`""
      Set-ItemProperty -Path $autoRunKey -Name AutoRun -Value $new
      Write-Ok "Appended cmd AutoRun to include $profileCmd"
    } else {
      Write-Skip "cmd AutoRun already includes $profileCmd"
    }
  }

  Write-Skip "Open a NEW Command Prompt window to use fnm (current PowerShell session cannot reload cmd)."
}

# -------------------------
# Optional: Install a base Node.js version and set as default
# -------------------------
if ($NodeVersion) {
  Write-Step "Installing Node.js version '$NodeVersion' with fnm"

  if ($DryRun) {
    Write-Do "Would run: fnm install $NodeVersion"
    Write-Do "Would run: fnm default $NodeVersion"
    Write-Do "Would run: fnm use $NodeVersion"
  } else {
    try {
      & $FnmCmd install $NodeVersion | Out-Null
      Write-Ok "Installed Node '$NodeVersion'"

      Write-Step "Setting default Node to '$NodeVersion'"
      & $FnmCmd default $NodeVersion | Out-Null
      Write-Ok "Default Node set to '$NodeVersion'"

      try {
        & $FnmCmd use $NodeVersion | Out-Null
        $ver = node --version
        Write-Ok "Active Node now $ver (if not, open a NEW PowerShell window)"
      } catch {
        Write-Skip "Could not activate in current session; open a NEW PowerShell window."
      }
    } catch {
      Write-Host "❌ Failed to install/use Node version '$NodeVersion': $($_.Exception.Message)" -ForegroundColor Red
    }
  }
}

# -------------------------
# Final checks + guidance
# -------------------------
Write-Step "Validating fnm presence"
try {
  if ($DryRun) {
    Write-Do "Would run: fnm --version"
    Write-Ok "fnm presence validation simulated (dry run)."
  } else {
    $fnmVer = & $FnmCmd --version
    Write-Ok "fnm present ($fnmVer)"
  }
} catch {
  Write-Skip "fnm not active in THIS session yet. If issues persist, open a NEW PowerShell window."
}

Write-Step "Done"
if ($Shells -contains 'pwsh') {
  Write-Host "PowerShell is configured. Test here: fnm --version; node --version (after install)."
}
if ($Shells -contains 'cmd') {
  Write-Host "Open a NEW **cmd** window to test:  fnm --version"
}
if ($Shells -contains 'gitbash') {
  Write-Host "Open a NEW **Git Bash** window to test:  fnm --version"
}
if ($NodeVersion) {
  Write-Host "Default Node is set to '$NodeVersion'. Validate with: node --version"
} else {
  Write-Host "Install a Node later with: fnm install 22  (or 'lts'); then: fnm default 22"
}
