#Requires -Version 7.0
<#
.SYNOPSIS
    Set up this workspace on a fresh Windows machine. The Windows counterpart
    of install.sh.

.DESCRIPTION
    git clone https://github.com/tpham2580/dotfiles.git $HOME\dotfiles
    cd $HOME\dotfiles; .\install.ps1

    The script is idempotent: run it again after pulling and it refreshes every
    config, backing up whatever it replaces into
    ~\.dotfiles-backup\<timestamp>\.

    Packages come from winget. Anything winget does not carry (herdr, hunk) is
    installed from its own upstream installer.

    Themes are deliberately NOT hardcoded here. They live in the deployed
    configs (herdr [theme], hunk theme, the nvim colorscheme) and this script
    only reports whatever it just deployed -- so changing a theme is a config
    edit, never an installer edit.

.PARAMETER NoPackages
    Deploy config files only; install nothing.

.PARAMETER PackagesOnly
    Install software only; touch no config files.

.PARAMETER Yes
    Do not prompt; assume yes.

.PARAMETER DryRun
    Print every action without doing any of it.

.EXAMPLE
    .\install.ps1 -DryRun

.EXAMPLE
    .\install.ps1 -NoPackages -Yes
#>
[CmdletBinding()]
param(
    [switch] $NoPackages,
    [switch] $PackagesOnly,
    [switch] $Yes,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

$Dotfiles = $PSScriptRoot
$Src = Join-Path $Dotfiles 'windows'
$BackupDir = Join-Path $HOME (".dotfiles-backup\{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

if (-not (Test-Path $Src)) {
    throw "windows\ not found next to install.ps1 (looked in $Dotfiles)"
}

# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------
function Write-Head { param([string] $Message) Write-Host ''; Write-Host '==> ' -NoNewline -ForegroundColor Blue; Write-Host $Message }
function Write-Good { param([string] $Message) Write-Host '  + ' -NoNewline -ForegroundColor Green; Write-Host $Message }
function Write-Note { param([string] $Message) Write-Host '  ! ' -NoNewline -ForegroundColor Yellow; Write-Host $Message }
function Write-Bad { param([string] $Message) Write-Host '  x ' -NoNewline -ForegroundColor Red; Write-Host $Message }
function Write-Skipped { param([string] $Message) Write-Host '  - ' -NoNewline -ForegroundColor DarkGray; Write-Host $Message -ForegroundColor DarkGray }
function Write-Dry { param([string] $Message) Write-Host '  [dry-run] ' -NoNewline -ForegroundColor DarkGray; Write-Host $Message -ForegroundColor DarkGray }

function Confirm-Action {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Prompt)

    if ($Yes) { return $true }
    Write-Host "  $Prompt [y/N] " -NoNewline -ForegroundColor Yellow
    $answer = ''
    try {
        $answer = if ([Console]::IsInputRedirected) { [string][Console]::In.ReadLine() }
        else { [string]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character }
    }
    catch { $answer = '' }
    Write-Host $answer
    return ($answer -match '^[yY]')
}

function Test-Tool {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------------------
# packages
#
# winget IDs are exact, and every one below was resolved against the live
# catalogue -- `winget search` happily returns third-party lookalikes, which is
# exactly how you end up with someone's fork of herdr.
# ---------------------------------------------------------------------------
$CorePackages = @(
    @{ Id = 'Microsoft.PowerShell'; Label = 'PowerShell 7'; Why = 'herdr default_shell; 5.1 is Restricted and will not dot-source the helpers' }
    @{ Id = 'Git.Git'; Label = 'Git'; Why = ''; Command = 'git' }
    @{ Id = 'GitHub.cli'; Label = 'GitHub CLI'; Why = 'git credential helper'; Command = 'gh' }
    @{ Id = 'OpenJS.NodeJS.LTS'; Label = 'Node.js LTS'; Why = 'hunk, Copilot language server, mason LSPs'; Command = 'node' }
    @{ Id = 'junegunn.fzf'; Label = 'fzf'; Why = 'the herdr sessionizer and folder picker'; Command = 'fzf' }
    @{ Id = 'BurntSushi.ripgrep.MSVC'; Label = 'ripgrep'; Why = 'telescope live_grep'; Command = 'rg' }
    @{ Id = 'sharkdp.fd'; Label = 'fd'; Why = 'telescope file finder'; Command = 'fd' }
    @{ Id = 'Neovim.Neovim'; Label = 'Neovim'; Why = ''; Command = 'nvim' }
    @{ Id = 'Microsoft.WindowsTerminal'; Label = 'Windows Terminal'; Why = '' }
    @{ Id = 'DEVCOM.JetBrainsMonoNerdFont'; Label = 'JetBrainsMono Nerd Font'; Why = 'nvim and herdr assume a Nerd Font' }
    @{ Id = 'glzr-io.glazewm'; Label = 'GlazeWM'; Why = 'tiling window manager' }
    @{ Id = 'glzr-io.zebar'; Label = 'Zebar'; Why = "GlazeWM's status bar; config.yaml startup_commands launches it" }
    @{ Id = 'GitHub.Copilot'; Label = 'GitHub Copilot CLI'; Why = 'prefix+a / prefix+shift+a' }
)

function Test-WingetPackage {
    param([string] $Id)
    winget list --id $Id --exact --source winget 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-CorePackages {
    if (-not (Test-Tool 'winget')) {
        Write-Note 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
        return
    }

    $installed = 0
    $pending = 0
    foreach ($pkg in $CorePackages) {
        if (Test-WingetPackage $pkg.Id) {
            Write-Skipped ('{0} already installed' -f $pkg.Label)
            continue
        }
        # winget only knows about what winget installed. Neovim in particular is
        # commonly unzipped to C:\tools, and installing the winget build on top
        # of it leaves two copies on PATH fighting over which config wins.
        if ($pkg.Command -and (Test-Tool $pkg.Command)) {
            $where = (Get-Command $pkg.Command).Source
            Write-Skipped ('{0} already on PATH at {1} (not via winget)' -f $pkg.Label, $where)
            continue
        }
        $note = if ($pkg.Why) { (' ({0})' -f $pkg.Why) } else { '' }
        if ($DryRun) {
            Write-Dry ('winget install --id {0}{1}' -f $pkg.Id, $note)
            $pending++
            continue
        }
        Write-Host ('  installing {0}{1}' -f $pkg.Label, $note)
        winget install --id $pkg.Id --exact --source winget --silent `
            --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) { Write-Good ('{0} installed' -f $pkg.Label); $installed++ }
        else { Write-Note ('{0} failed (winget exit {1})' -f $pkg.Label, $LASTEXITCODE) }
    }
    if ($DryRun) { Write-Good ('{0} package(s) would be installed' -f $pending) }
    elseif ($installed -eq 0) { Write-Good 'all packages already present' }
}

function Install-Herdr {
    # NOT available from winget: `winget search herdr` returns a third-party
    # fork, several minor versions behind. Always use the upstream installer.
    $local = Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe'
    if ((Test-Tool 'herdr') -or (Test-Path $local)) {
        Write-Skipped 'herdr already installed'
        return
    }
    if ($DryRun) { Write-Dry 'irm https://herdr.dev/install.ps1 | iex'; return }
    try {
        Invoke-RestMethod -Uri 'https://herdr.dev/install.ps1' -TimeoutSec 60 | Invoke-Expression
        Write-Good 'herdr installed'
    }
    catch { Write-Note "herdr install failed: $_" }
}

function Install-Hunk {
    if (Test-Tool 'hunk') { Write-Skipped 'hunk already installed'; return }
    if (-not (Test-Tool 'npm')) { Write-Note 'npm missing, cannot install hunk'; return }
    if ($DryRun) { Write-Dry 'npm install -g hunkdiff'; return }
    & npm install -g hunkdiff 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Good 'hunk installed' } else { Write-Note 'hunk install failed' }
}

# ---------------------------------------------------------------------------
# config deployment
#
# windows\ does NOT mirror $HOME one-for-one, because Windows apps disagree
# about where config lives:
#
#   AppData\Roaming\*   -> %APPDATA%        (herdr)
#   AppData\Local\*     -> %LOCALAPPDATA%   (Windows Terminal)
#   .config\nvim\*      -> %LOCALAPPDATA%\nvim
#   everything else     -> $HOME            (hunk, glazewm, zebar, copilot)
#
# The .config\nvim special case is a leftover from the Linux tree: Neovim on
# Windows reads %LOCALAPPDATA%\nvim, not ~\.config\nvim.
# ---------------------------------------------------------------------------
function Get-DeployTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $RelativePath)

    if ($RelativePath -like '.config\nvim\*') {
        return Join-Path $env:LOCALAPPDATA ($RelativePath -replace '^\.config\\nvim\\', 'nvim\')
    }
    if ($RelativePath -like 'AppData\Roaming\*') {
        return Join-Path $env:APPDATA ($RelativePath -replace '^AppData\\Roaming\\', '')
    }
    if ($RelativePath -like 'AppData\Local\*') {
        return Join-Path $env:LOCALAPPDATA ($RelativePath -replace '^AppData\\Local\\', '')
    }
    return Join-Path $HOME $RelativePath
}

# Written once and never overwritten, so per-machine edits survive both a later
# install.ps1 run and a git pull.
$SeedOnce = @(
    'AppData\Roaming\herdr\sessionize-paths'
)

# Files rewritten for this machine on the way out. herdr does not expand $HOME
# (or any variable) inside [[keys.command]], so the tracked config necessarily
# carries an absolute path to the helper scripts -- whichever machine committed
# it last. Retarget that to this machine's home so the bindings work under any
# username, instead of shipping a config that silently no-ops for everyone else.
$PathRewrite = @(
    'AppData\Roaming\herdr\config.toml'
)

function Get-DeployContent {
    <#
      Returns the text to deploy, or $null when the file should be copied
      byte-for-byte.
    #>
    param([string] $SourcePath, [string] $RelativePath)

    if ($PathRewrite -notcontains $RelativePath) { return $null }

    $text = Get-Content -LiteralPath $SourcePath -Raw
    $home_ = $HOME.TrimEnd('\') + '\'
    # MatchEvaluator, not a replacement string: `$` is a substitution token in
    # .NET replacements and a home directory is free to contain one.
    return [regex]::Replace($text, '(?i)C:\\Users\\[^\\"'']+\\', { $home_ })
}

function Backup-Target {
    param([string] $Path)
    if (-not (Test-Path $Path)) { return }
    if ($DryRun) { Write-Dry ('backup {0}' -f $Path); return }

    $rel = if ($Path.StartsWith($HOME)) { $Path.Substring($HOME.Length).TrimStart('\') } else { Split-Path $Path -Leaf }
    $dest = Join-Path $BackupDir $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    Move-Item -LiteralPath $Path -Destination $dest -Force
}

function Test-SameFile {
    # $Content is deliberately untyped: [string] would coerce $null to '', and
    # the "was this file rewritten?" test below would then be true for every
    # file, redeploying the whole tree on every run.
    param([string] $A, [string] $B, $Content)
    if (-not (Test-Path $B)) { return $false }
    if ($null -ne $Content) {
        # Compare against what would actually be written, not the repo copy,
        # or a rewritten file would look different on every single run.
        return ((Get-Content -LiteralPath $B -Raw) -eq $Content)
    }
    return (Get-FileHash -LiteralPath $A).Hash -eq (Get-FileHash -LiteralPath $B).Hash
}

function Copy-DotfileTree {
    $copied = 0
    $replaced = 0
    $seeded = 0

    foreach ($file in Get-ChildItem -Path $Src -Recurse -File -Force) {
        $rel = $file.FullName.Substring($Src.Length).TrimStart('\')
        $target = Get-DeployTarget -RelativePath $rel

        if ($SeedOnce -contains $rel) {
            if (Test-Path $target) { Write-Skipped ('{0} exists, left untouched' -f $rel); continue }
            if ($DryRun) { Write-Dry ('seed {0}' -f $target); $seeded++; continue }
            New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            Write-Good ('seeded {0} -- edit it for this machine' -f $rel)
            $seeded++
            continue
        }

        $content = Get-DeployContent -SourcePath $file.FullName -RelativePath $rel

        if (Test-SameFile $file.FullName $target $content) { continue }

        if (Test-Path $target) { Backup-Target $target; $replaced++ }
        if ($DryRun) {
            if ($null -ne $content) { Write-Dry ('deploy {0} (paths retargeted to {1})' -f $target, $HOME) }
            else { Write-Dry ('deploy {0}' -f $target) }
            $copied++
            continue
        }

        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        if ($null -ne $content) {
            Set-Content -LiteralPath $target -Value $content -Encoding UTF8 -NoNewline
            Write-Good ('{0} deployed with paths retargeted to this machine' -f $rel)
        }
        else {
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
        $copied++
    }

    Write-Good ('{0} file(s) deployed, {1} replaced, {2} seeded' -f $copied, $replaced, $seeded)
    if ($replaced -gt 0 -and -not $DryRun) { Write-Host ('    backup: {0}' -f $BackupDir) -ForegroundColor DarkGray }
}

# ---------------------------------------------------------------------------
# $PROFILE
# ---------------------------------------------------------------------------
$ProfileBeginMarker = '# >>> dotfiles: herdr >>>'
$ProfileEndMarker = '# <<< dotfiles: herdr <<<'

$ProfileBlock = @"
$ProfileBeginMarker
# Managed by dotfiles\install.ps1 -- edit the repo, not this block.
# Order matters: the sessionizer rebinds Alt+S from the session-only picker
# to the unified workspace+session one, so it must load second.
`$__herdrSession = "`$HOME\.copilot\scripts\Invoke-HerdrSession.ps1"
if (Test-Path `$__herdrSession) { . `$__herdrSession }

`$__herdrSessionizer = "`$HOME\.copilot\scripts\Invoke-HerdrSessionizer.ps1"
if (Test-Path `$__herdrSessionizer) { . `$__herdrSessionizer }
$ProfileEndMarker
"@

function Install-ProfileBlock {
    # PowerShell has four profile paths and only ever auto-loads the ones that
    # exist. The wiring can legitimately live in any of them, so scan them all
    # before writing -- checking only CurrentUserAllHosts would append a second
    # copy on a box whose wiring sits in Microsoft.PowerShell_profile.ps1, and
    # the herdr scripts would then be dot-sourced twice per shell.
    $candidates = @(
        $PROFILE.CurrentUserAllHosts
        $PROFILE.CurrentUserCurrentHost
        $PROFILE.AllUsersAllHosts
        $PROFILE.AllUsersCurrentHost
    ) | Where-Object { $_ } | Select-Object -Unique

    $managed = $candidates | Where-Object {
        (Test-Path $_) -and (Get-Content -LiteralPath $_ -Raw).Contains($ProfileBeginMarker)
    } | Select-Object -First 1

    if ($managed) {
        $existing = Get-Content -LiteralPath $managed -Raw

        # Splice by index rather than [regex]::Replace: the block contains
        # `$__herdrSession`, and `$_` is a substitution token in a .NET regex
        # replacement string, so a regex replace would silently expand it into
        # the entire profile.
        $start = $existing.IndexOf($ProfileBeginMarker)
        $endAt = $existing.IndexOf($ProfileEndMarker, $start)
        if ($endAt -lt 0) {
            Write-Note ('{0} has an opening marker but no closing one, left as-is' -f $managed)
            return
        }
        $endAt += $ProfileEndMarker.Length
        $updated = $existing.Substring(0, $start) + $ProfileBlock + $existing.Substring($endAt)
        if ($updated -eq $existing) { Write-Skipped 'profile block already up to date'; return }
        if ($DryRun) { Write-Dry ('refresh managed block in {0}' -f $managed); return }
        Set-Content -LiteralPath $managed -Value $updated -Encoding UTF8
        Write-Good ('profile block refreshed in {0}' -f $managed)
        return
    }

    # An unmanaged hand-rolled wiring is already there (this repo predates the
    # installer on the author's own box). Leave it alone rather than loading
    # the same scripts twice.
    $unmanaged = $candidates | Where-Object {
        (Test-Path $_) -and (Get-Content -LiteralPath $_ -Raw) -match 'Invoke-HerdrSession(izer)?\.ps1'
    } | Select-Object -First 1

    if ($unmanaged) {
        Write-Skipped ('{0} already loads the herdr scripts (unmanaged, left as-is)' -f $unmanaged)
        return
    }

    $path = $PROFILE.CurrentUserAllHosts
    if (-not $path) { Write-Note 'could not resolve $PROFILE'; return }
    if ($DryRun) { Write-Dry ('append managed block to {0}' -f $path); return }
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    Add-Content -LiteralPath $path -Value ("`n" + $ProfileBlock) -Encoding UTF8
    Write-Good ('profile block added to {0}' -f $path)
}

# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------
function Get-ConfigValue {
    param([string] $Path, [string] $Pattern)
    if (-not (Test-Path $Path)) { return $null }
    $m = Select-String -LiteralPath $Path -Pattern $Pattern | Select-Object -First 1
    if (-not $m) { return $null }
    return $m.Matches[0].Groups[1].Value
}

function Show-ThemeSummary {
    # Read back what was deployed instead of hardcoding names, so this stays
    # correct when the themes change.
    $herdr = Get-ConfigValue (Join-Path $env:APPDATA 'herdr\config.toml') '^\s*name\s*=\s*"([^"]+)"'
    $hunk = Get-ConfigValue (Join-Path $HOME '.config\hunk\config.toml') '^\s*theme\s*=\s*"([^"]+)"'

    Write-Host ('  herdr theme : {0}' -f ($herdr ?? '(unset)'))
    Write-Host ('  hunk theme  : {0}' -f ($hunk ?? '(unset)'))
    Write-Host '  change them in windows\AppData\Roaming\herdr\config.toml and' -ForegroundColor DarkGray
    Write-Host '  windows\.config\hunk\config.toml, then re-run this script.' -ForegroundColor DarkGray
}

function Show-Notes {
    $notes = @()
    if (-not (Test-Tool 'fzf')) { $notes += 'fzf missing: the sessionizer (prefix+alt+s) and ctrl+f will not work' }
    if (-not (Test-Tool 'nvim')) { $notes += 'neovim missing: the nvim config will not load' }
    if (-not (Test-Tool 'hunk')) { $notes += 'hunk missing: npm install -g hunkdiff' }
    if (-not (Test-Tool 'herdr')) { $notes += 'herdr missing or not on PATH: irm https://herdr.dev/install.ps1 | iex' }

    # config.yaml has `startup_commands: ['shell-exec zebar']`, so a missing
    # Zebar makes GlazeWM start with no status bar at all.
    if (-not (Test-Path 'C:\Program Files\glzr.io\Zebar\zebar.exe')) {
        $notes += 'zebar missing: GlazeWM will start without its status bar (winget install glzr-io.zebar)'
    }

    # Paths are retargeted at deploy time (see $PathRewrite), so this only fires
    # if the deployed config somehow still points at another user's home.
    $herdrConfig = Join-Path $env:APPDATA 'herdr\config.toml'
    if (Test-Path $herdrConfig) {
        $stale = Select-String -LiteralPath $herdrConfig -Pattern 'C:\\Users\\([^\\"]+)\\' -AllMatches |
            ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique | Where-Object { $_ -ne (Split-Path $HOME -Leaf) }
        if ($stale) {
            $notes += ("herdr config still points at '{0}' -- expected {1}" -f ($stale -join ', '), $HOME)
        }
    }

    if (-not $notes) { return }
    Write-Head 'Still to do'
    foreach ($n in $notes) { Write-Note $n }
}

function Update-GlazeWM {
    $exe = (Get-Command glazewm -ErrorAction SilentlyContinue).Source
    if (-not $exe) {
        $fallback = 'C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe'
        if (Test-Path $fallback) { $exe = $fallback }
    }
    if (-not $exe) { Write-Skipped 'glazewm not installed'; return }
    if ($DryRun) { Write-Dry 'glazewm command wm-reload-config'; return }

    # Only works against a running instance; a fresh box has none yet.
    & $exe command wm-reload-config 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Good 'glazewm config reloaded' }
    else { Write-Skipped 'no running glazewm to reload (it reads the config at startup)' }
}

function Update-HerdrConfig {
    if (-not (Test-Tool 'herdr')) { return }
    if ($DryRun) { Write-Dry 'herdr server reload-config'; return }
    $out = & herdr server reload-config 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Good 'herdr config reloaded' }
    else { Write-Skipped 'no running herdr server to reload' }
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
Write-Head 'Environment'
Write-Good ('dotfiles   : {0}' -f $Dotfiles)
Write-Good ('powershell : {0}' -f $PSVersionTable.PSVersion)
Write-Good ('user       : {0}' -f $env:USERNAME)
if ($DryRun) { Write-Note 'dry run -- nothing will be changed' }

if ($NoPackages) {
    Write-Skipped 'package installation skipped (-NoPackages)'
}
else {
    Write-Head 'Packages (winget)'
    Install-CorePackages

    Write-Head 'Tools outside winget'
    Install-Herdr
    Install-Hunk
}

if ($PackagesOnly) {
    Write-Skipped 'config deployment skipped (-PackagesOnly)'
}
else {
    Write-Head 'Deploying configs'
    Copy-DotfileTree

    Write-Head 'PowerShell profile'
    Install-ProfileBlock

    Write-Head 'herdr'
    Update-HerdrConfig

    Write-Head 'Window manager'
    Update-GlazeWM

    Write-Head 'Themes'
    Show-ThemeSummary
}

Show-Notes

Write-Head 'Done'
Write-Host @'
  Next:
    1. pwsh                        reload the shell (or: . $PROFILE)
    2. nvim                        let lazy.nvim install plugins, then :Copilot setup
    3. herdr                       start the multiplexer (prefix is ctrl+b)
       ctrl+b alt+s   workspace/session picker    ctrl+b ctrl+f  open a folder
       ctrl+b shift+a start Copilot CLI in this pane
    4. hz / hf / hw                the same pickers from a plain shell
'@
