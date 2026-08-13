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

    Themes are chosen per machine with -Theme and remembered in
    ~\.dotfiles-theme, so a later run without the switch keeps whatever this
    machine already uses. The repo carries one default; the deploy rewrites the
    theme value in every config that needs it, which is why a theme is never
    committed from one machine onto another.

.PARAMETER NoPackages
    Deploy config files only; install nothing.

.PARAMETER PackagesOnly
    Install software only; touch no config files.

.PARAMETER Theme
    Colour scheme to deploy: kanagawa-wave, kanagawa-dragon or catppuccin-mocha.
    Defaults to whatever this machine chose last, then to the repo default.

.PARAMETER Yes
    Do not prompt; assume yes.

.PARAMETER DryRun
    Print every action without doing any of it.

.EXAMPLE
    .\install.ps1 -DryRun

.EXAMPLE
    .\install.ps1 -NoPackages -Yes

.EXAMPLE
    .\install.ps1 -Theme catppuccin-mocha
#>
[CmdletBinding()]
param(
    [switch] $NoPackages,
    [switch] $PackagesOnly,
    [ValidateSet('kanagawa-wave', 'kanagawa-dragon', 'catppuccin-mocha')]
    [string] $Theme,
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

function Get-HerdrPath {
    <#
      herdr can live in more than one place: the installer's target, the
      standalone package directory its bundled updater manages, or wherever a
      running instance was launched from. Checking only one of these makes the
      installer think herdr is missing and try to install over a live copy.
    #>
    $candidates = @(
        (Get-Command herdr -ErrorAction SilentlyContinue).Source
        (Get-Process herdr -ErrorAction SilentlyContinue | Select-Object -First 1).Path
        (Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe')
        (Join-Path $HOME '.herdr\packages\standalone\current\herdr.exe')
    )
    return $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Install-Herdr {
    # NOT available from winget: `winget search herdr` returns a third-party
    # fork, several minor versions behind. Always use the upstream installer.
    $existing = Get-HerdrPath
    if ($existing) {
        Write-Skipped ('herdr already installed ({0})' -f $existing)
        return
    }

    # A running herdr holds its own binary open, so the upstream installer dies
    # partway through with "the process cannot access the file because it is
    # being used by another process" -- including when install.ps1 is run from
    # inside a herdr pane. Say so instead of surfacing that error.
    $running = @(Get-Process herdr -ErrorAction SilentlyContinue)
    if ($running) {
        Write-Note ('herdr is running (pid {0}); close all sessions and re-run to install' -f ($running.Id -join ', '))
        return
    }

    if ($DryRun) { Write-Dry 'irm https://herdr.dev/install.ps1 | iex'; return }

    # Run the upstream installer as a file in a child process rather than
    # `irm | iex`. Piping it into this scope leaks its `Set-StrictMode -Version
    # Latest` and `$ErrorActionPreference = "Stop"` into everything that runs
    # after it here, and collapses any failure into a bare message with no line
    # number to act on.
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) ('herdr-install-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
    $shim      = Join-Path ([System.IO.Path]::GetTempPath()) ('herdr-shim-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
    try {
        Invoke-RestMethod -Uri 'https://herdr.dev/install.ps1' -TimeoutSec 60 -OutFile $installer
    }
    catch {
        Write-Note "could not download the herdr installer: $($_.Exception.Message)"
        return
    }

    # The upstream installer verifies the download by running herdr.exe out of
    # its staging directory, then immediately renames that directory into place.
    # Windows keeps the executable image open for roughly half a second after
    # the process exits, and a directory cannot be renamed while anything inside
    # it is open -- so the rename loses a race it never had a chance to win and
    # the install dies on "the process cannot access the file because it is
    # being used by another process" at install.ps1:638. This is not antivirus
    # and not specific to any one machine: it reproduces 3/3 here running the
    # documented `irm https://herdr.dev/install.ps1 | iex` verbatim.
    #
    # Retrying the move afterwards does NOT work. A failed directory move still
    # creates the destination, so the retry moves the staging directory *inside*
    # it and the binary lands at <release>\<staging>\herdr.exe, which upstream
    # then fails to run. The lock has to be waited out *before* the move.
    #
    # All four upstream Move-Item calls (454, 635, 638, 641) pass exactly
    # -LiteralPath and -Destination and none take pipeline input, so this proxy
    # covers them faithfully. Dot-sourcing is what puts it in scope for the
    # installer; the rest of its behaviour is untouched.
    $shimBody = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-DotfilesUnlocked {
    param([string]$Path, [int]$TimeoutMs = 15000)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $locked = $false
        foreach ($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            try { [System.IO.File]::Open($file.FullName, 'Open', 'Read', 'None').Dispose() }
            catch { $locked = $true; break }
        }
        # On timeout, fall through and let the real Move-Item report the error.
        if (-not $locked -or $sw.ElapsedMilliseconds -ge $TimeoutMs) { return }
        Start-Sleep -Milliseconds 100
    }
}

function Move-Item {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Destination
    )
    if (Test-Path -LiteralPath $LiteralPath -PathType Container) {
        Wait-DotfilesUnlocked -Path $LiteralPath
    }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}

. $env:DOTFILES_HERDR_INSTALLER
'@
    Set-Content -LiteralPath $shim -Value $shimBody -Encoding UTF8
    $env:DOTFILES_HERDR_INSTALLER = $installer

    $pwshExe = (Get-Process -Id $PID).Path
    try {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $out = & $pwshExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $shim 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Good 'herdr installed'; return }

            $text = ($out | Out-String).Trim()

            # Anything still locked after the shim waited it out is a different
            # problem -- most likely antivirus holding the downloaded package
            # open -- so back off further before trying again.
            if ($attempt -lt 3 -and $text -match 'being used by another process') {
                Write-Note ('attempt {0} hit a file lock (antivirus scan?), retrying in 5s' -f $attempt)
                Start-Sleep -Seconds 5
                continue
            }

            Write-Bad ('herdr install failed (exit {0})' -f $LASTEXITCODE)
            $tail = $text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 12
            foreach ($line in $tail) { Write-Host ('      {0}' -f $line) -ForegroundColor DarkGray }
            Write-Note 'install herdr by hand with: irm https://herdr.dev/install.ps1 | iex'
            return
        }
    }
    finally {
        Remove-Item -LiteralPath $installer, $shim -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\DOTFILES_HERDR_INSTALLER -ErrorAction SilentlyContinue
    }
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

# ---------------------------------------------------------------------------
# themes
#
# Every app names its colours differently, so a theme is a set of per-app values
# rather than one string: nvim wants a colorscheme name, herdr a built-in theme,
# GlazeWM two border colours, Zebar a CSS palette and Windows Terminal a scheme
# name. The repo stores one default and the deploy rewrites those values, so a
# machine picks a theme without ever committing it -- which is what keeps two
# machines on different themes from fighting over the same tracked files.
#
# Windows Terminal is the exception: its settings.json carries all three scheme
# definitions and only the active `colorScheme` is rewritten, because a scheme
# it does not know about would leave the profile unstyled.
# ---------------------------------------------------------------------------
$ThemeFile = Join-Path $HOME '.dotfiles-theme'
$DefaultTheme = 'kanagawa-wave'

$Themes = @{
    'kanagawa-wave'    = @{
        Nvim            = 'kanagawa-wave'
        Hunk            = 'kanagawa-wave'
        Herdr           = 'kanagawa'
        TerminalScheme  = 'Kanagawa Wave'
        BorderFocused   = '#7e9cd8'
        BorderUnfocused = '#727169'
        Bar             = @{
            bg = '31 31 40'; bgAlt = '42 42 55'; fg = '#dcd7ba'; muted = '#727169'
            accent = '#7e9cd8'; accentText = '#1f1f28'; teal = '#7fb4ca'
            green = '#76946a'; red = '#c34043'; yellow = '#c0a36e'
            accentRgb = '126 156 216'; mutedRgb = '114 113 105'; yellowRgb = '192 163 110'
        }
    }
    'kanagawa-dragon'  = @{
        Nvim            = 'kanagawa-dragon'
        Hunk            = 'kanagawa-dragon'
        Herdr           = 'kanagawa'
        TerminalScheme  = 'Kanagawa Dragon'
        BorderFocused   = '#8ba4b0'
        BorderUnfocused = '#7a8382'
        Bar             = @{
            bg = '24 22 22'; bgAlt = '40 39 39'; fg = '#c5c9c5'; muted = '#a6a69c'
            accent = '#8ba4b0'; accentText = '#181616'; teal = '#8ea4a2'
            green = '#8a9a7b'; red = '#c4746e'; yellow = '#c4b28a'
            accentRgb = '139 164 176'; mutedRgb = '166 166 156'; yellowRgb = '196 178 138'
        }
    }
    'catppuccin-mocha' = @{
        Nvim            = 'catppuccin-mocha'
        Hunk            = 'catppuccin-mocha'
        Herdr           = 'catppuccin'
        TerminalScheme  = 'Catppuccin Mocha'
        BorderFocused   = '#89b4fa'
        BorderUnfocused = '#6c7086'
        Bar             = @{
            bg = '30 30 46'; bgAlt = '49 50 68'; fg = '#cdd6f4'; muted = '#6c7086'
            accent = '#89b4fa'; accentText = '#1e1e2e'; teal = '#94e2d5'
            green = '#a6e3a1'; red = '#f38ba8'; yellow = '#f9e2af'
            accentRgb = '137 180 250'; mutedRgb = '108 112 134'; yellowRgb = '249 226 175'
        }
    }
}

# Files whose theme values are rewritten on the way out.
$ThemeRewrite = @(
    '.config\nvim\init.lua',
    '.config\hunk\config.toml',
    'AppData\Roaming\herdr\config.toml',
    '.glzr\glazewm\config.yaml',
    'AppData\Roaming\zebar\downloads\glzr-io.starter@0.0.0\styles.css',
    'AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
)

function Resolve-Theme {
    <#
      -Theme wins, then this machine's remembered choice, then the repo default.
    #>
    [CmdletBinding()]
    param([string] $Requested)

    if ($Requested) { return $Requested }

    if (Test-Path $ThemeFile) {
        $saved = (Get-Content -LiteralPath $ThemeFile -Raw).Trim()
        if ($Themes.ContainsKey($saved)) { return $saved }
        Write-Note ("{0} names an unknown theme '{1}'; falling back to {2}" -f $ThemeFile, $saved, $DefaultTheme)
    }

    return $DefaultTheme
}

function Save-Theme {
    [CmdletBinding()]
    param([string] $Name)

    if ($DryRun) { Write-Dry ('remember theme {0} in {1}' -f $Name, $ThemeFile); return }
    Set-Content -LiteralPath $ThemeFile -Value $Name -Encoding UTF8
}

function Set-ThemeValues {
    <#
      Applies the active theme to one config's text. Each pattern is anchored on
      the key it replaces so the rewrite cannot wander into unrelated content.
    #>
    [CmdletBinding()]
    param([string] $Text, [string] $RelativePath, [hashtable] $Values)

    switch ($RelativePath) {
        '.config\nvim\init.lua' {
            return [regex]::Replace($Text, "(?m)^(\s*vim\.cmd\.colorscheme\s+')[^']+(')", {
                    param($m) $m.Groups[1].Value + $Values.Nvim + $m.Groups[2].Value
                })
        }
        '.config\hunk\config.toml' {
            return [regex]::Replace($Text, '(?m)^(theme\s*=\s*")[^"]+(")', {
                    param($m) $m.Groups[1].Value + $Values.Hunk + $m.Groups[2].Value
                })
        }
        'AppData\Roaming\herdr\config.toml' {
            $text = [regex]::Replace($Text, '(?m)^(#\s*theme_label\s*=\s*")[^"]+(")', {
                    param($m) $m.Groups[1].Value + $Values.Name + $m.Groups[2].Value
                })
            # Only the name inside [theme]; herdr has no other bare `name =` key,
            # but anchor on the section anyway so it stays true if one appears.
            return [regex]::Replace($text, '(?ms)(\[theme\]\r?\nname\s*=\s*")[^"]+(")', {
                    param($m) $m.Groups[1].Value + $Values.Herdr + $m.Groups[2].Value
                })
        }
        '.glzr\glazewm\config.yaml' {
            # Anchored on the two section names rather than on match order: a
            # counter shared with a MatchEvaluator does not survive between
            # calls, which silently gave both borders the focused colour.
            $text = [regex]::Replace($Text, "(?s)(focused_window:.*?color:\s*')#[0-9a-fA-F]{6}(')", {
                    param($m) $m.Groups[1].Value + $Values.BorderFocused + $m.Groups[2].Value
                })
            return [regex]::Replace($text, "(?s)(other_windows:.*?color:\s*')#[0-9a-fA-F]{6}(')", {
                    param($m) $m.Groups[1].Value + $Values.BorderUnfocused + $m.Groups[2].Value
                })
        }
        'AppData\Roaming\zebar\downloads\glzr-io.starter@0.0.0\styles.css' {
            $bar = $Values.Bar
            $map = @{
                '--bar-bg-rgb'      = $bar.bg
                '--bar-bg-alt-rgb'  = $bar.bgAlt
                '--bar-accent-rgb'  = $bar.accentRgb
                '--bar-muted-rgb'   = $bar.mutedRgb
                '--bar-yellow-rgb'  = $bar.yellowRgb
                '--bar-fg'          = $bar.fg
                '--bar-muted'       = $bar.muted
                '--bar-accent'      = $bar.accent
                '--bar-accent-fg'   = $bar.accentText
                '--bar-teal'        = $bar.teal
                '--bar-green'       = $bar.green
                '--bar-red'         = $bar.red
                '--bar-yellow'      = $bar.yellow
            }
            $text = $Text
            foreach ($key in $map.Keys) {
                $value = $map[$key]
                # Anchor on the exact variable name; --bar-bg must not also match
                # --bar-bg-rgb, so require the colon immediately after the name.
                $text = [regex]::Replace($text, ('(?m)^(\s*{0}:\s*)[^;]+(;)' -f [regex]::Escape($key)), {
                        param($m) $m.Groups[1].Value + $value + $m.Groups[2].Value
                    })
            }
            return $text
        }
        'AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json' {
            return [regex]::Replace($Text, '("colorScheme"\s*:\s*")[^"]+(")', {
                    param($m) $m.Groups[1].Value + $Values.TerminalScheme + $m.Groups[2].Value
                })
        }
    }

    return $Text
}

function Get-DeployContent {
    <#
      Returns the text to deploy, or $null when the file should be copied
      byte-for-byte.
    #>
    param([string] $SourcePath, [string] $RelativePath)

    $needsPath = $PathRewrite -contains $RelativePath
    $needsTheme = $ThemeRewrite -contains $RelativePath
    if (-not $needsPath -and -not $needsTheme) { return $null }

    $text = Get-Content -LiteralPath $SourcePath -Raw

    if ($needsPath) {
        $home_ = $HOME.TrimEnd('\') + '\'
        # MatchEvaluator, not a replacement string: `$` is a substitution token in
        # .NET replacements and a home directory is free to contain one.
        $text = [regex]::Replace($text, '(?i)C:\\Users\\[^\\"'']+\\', { $home_ })
    }

    if ($needsTheme) {
        $text = Set-ThemeValues -Text $text -RelativePath $RelativePath -Values $script:ActiveTheme
    }

    return $text
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

# The Windows counterpart of linux/.zshenv: hunk's 'e' command reads `$EDITOR
# from the environment it inherits, and herdr panes inherit it from here. An
# EDITOR already set in the environment wins, so this only fills the gap.
if (-not `$env:EDITOR) { `$env:EDITOR = 'nvim' }
if (-not `$env:VISUAL) { `$env:VISUAL = `$env:EDITOR }

# Only the sessionizer binds Alt+S, so load order no longer decides which
# picker the terminal gets. Invoke-HerdrSession.ps1 supplies the helpers it
# builds on, so it still loads first.
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
    # Read back what was deployed instead of trusting the theme table, so a
    # rewrite that silently failed to match shows up here rather than in a
    # confusing half-themed desktop.
    $herdr = Get-ConfigValue (Join-Path $env:APPDATA 'herdr\config.toml') '^\s*#\s*theme_label\s*=\s*"([^"]+)"'
    $hunk = Get-ConfigValue (Join-Path $HOME '.config\hunk\config.toml') '^\s*theme\s*=\s*"([^"]+)"'
    $nvim = Get-ConfigValue (Join-Path $env:LOCALAPPDATA 'nvim\init.lua') "colorscheme\s+'([^']+)'"
    $terminal = Get-ConfigValue `
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json') `
        '"colorScheme"\s*:\s*"([^"]+)"'

    Write-Host ('  active theme : {0}' -f $script:ActiveThemeName) -ForegroundColor Cyan
    Write-Host ('  terminal     : {0}' -f ($terminal ?? '(unset)'))
    Write-Host ('  nvim         : {0}' -f ($nvim ?? '(unset)'))
    Write-Host ('  herdr        : {0}' -f ($herdr ?? '(unset)'))
    Write-Host ('  hunk         : {0}' -f ($hunk ?? '(unset)'))
    Write-Host ('  choices      : {0}' -f (($Themes.Keys | Sort-Object) -join ', ')) -ForegroundColor DarkGray
    Write-Host '  switch with  : .\install.ps1 -Theme <name>' -ForegroundColor DarkGray
}

function Show-Notes {
    $notes = @()
    if (-not (Test-Tool 'fzf')) { $notes += 'fzf missing: the sessionizer (prefix+alt+s) and ctrl+f will not work' }
    if (-not (Test-Tool 'nvim')) { $notes += 'neovim missing: the nvim config will not load' }
    if (-not (Test-Tool 'hunk')) { $notes += 'hunk missing: npm install -g hunkdiff' }
    if (-not (Get-HerdrPath)) { $notes += 'herdr missing or not on PATH: irm https://herdr.dev/install.ps1 | iex' }

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
    <#
      Two things bite on a fresh box, and both look like "GlazeWM is installed
      but there is no UI":

      1. The `glazewm` on PATH is the CLI *client*
         (...\GlazeWM\cli\glazewm.exe), not the window manager
         (...\GlazeWM\glazewm.exe). Running bare `glazewm` prints usage and
         exits 0 without starting anything. The WM needs `glazewm start`.
      2. winget registers no autostart entry, so nothing launches the WM at
         login even once it has been started by hand.
    #>
    $cli = (Get-Command glazewm -ErrorAction SilentlyContinue).Source
    if (-not $cli) {
        $fallback = 'C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe'
        if (Test-Path $fallback) { $cli = $fallback }
    }
    if (-not $cli) { Write-Skipped 'glazewm not installed'; return }
    # winget's shim resolves with a doubled separator (GlazeWM\\cli), which
    # works but would be written verbatim into the Run key.
    $cli = [System.IO.Path]::GetFullPath($cli)

    if (Get-Process glazewm -ErrorAction SilentlyContinue) {
        if ($DryRun) { Write-Dry 'glazewm command wm-reload-config' }
        else {
            & $cli command wm-reload-config 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Good 'glazewm config reloaded' }
            else { Write-Skipped 'glazewm running but would not reload' }
        }
    }
    elseif ($DryRun) { Write-Dry 'glazewm start (window manager not running)' }
    else {
        # Start detached: `glazewm start` runs in the foreground and would
        # block the rest of this script until the WM exits.
        Start-Process -FilePath $cli -ArgumentList 'start' -WindowStyle Hidden
        Start-Sleep -Seconds 2
        if (Get-Process glazewm -ErrorAction SilentlyContinue) { Write-Good 'glazewm started' }
        else { Write-Note 'glazewm did not start; run "glazewm start" to see the error' }
    }

    Register-GlazeWMStartup -Cli $cli
}

function Register-GlazeWMStartup {
    param([Parameter(Mandatory)][string] $Cli)

    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $value  = '"{0}" start' -f $Cli
    $existing = (Get-ItemProperty -Path $runKey -Name 'GlazeWM' -ErrorAction SilentlyContinue).GlazeWM

    if ($existing -eq $value) { Write-Skipped 'glazewm already starts at login'; return }
    if ($DryRun) { Write-Dry ('set Run\GlazeWM = {0}' -f $value); return }

    Set-ItemProperty -Path $runKey -Name 'GlazeWM' -Value $value
    Write-Good 'glazewm registered to start at login'
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

$script:ActiveThemeName = Resolve-Theme -Requested $Theme
$script:ActiveTheme = $Themes[$script:ActiveThemeName].Clone()
$script:ActiveTheme.Name = $script:ActiveThemeName
Write-Good ('theme      : {0}{1}' -f $script:ActiveThemeName, ($Theme ? ' (selected)' : ' (remembered)'))

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
    Save-Theme -Name $script:ActiveThemeName
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
