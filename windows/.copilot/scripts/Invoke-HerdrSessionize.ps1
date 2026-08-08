# Herdr folder picker — open ANY folder as a herdr workspace.
# The Windows port of ~/.script/herdr-sessionize (bound to ctrl+f on Linux).
#
#   tmux new-session -c $dir  ->  herdr workspace create --cwd $dir
#   tmux switch-client -t X   ->  herdr workspace focus X
#
# Picking a folder that is already open focuses it instead of duplicating it.
#
#   hf              fzf folder picker
#   hf <dir>        open a specific folder directly
#   hw <dir>        same thing, non-interactive (Open-HerdrWorkspace)
#
# Search roots live in %APPDATA%\herdr\sessionize-paths, one `path[:depth]` per
# line. Override the file with $env:HERDR_SESSIONIZE_PATHS.
#
# Wire up in %APPDATA%\herdr\config.toml:
#   [[keys.command]]
#   key = "prefix+ctrl+f"
#   type = "popup"
#   command = 'pwsh -NoLogo -NoProfile -File "C:\Users\<you>\.copilot\scripts\Invoke-HerdrSessionize.ps1" -Popup'

[CmdletBinding()]
param(
    # Run the picker straight away instead of only defining the helpers.
    # Used by the herdr popup keybinding; dot-sourcing leaves it unset.
    [switch] $Popup
)

# Captured before dot-sourcing, because a dot-sourced script's param block
# writes into THIS scope and would otherwise clobber $Popup.
$runPicker = [bool]$Popup

. (Join-Path $PSScriptRoot 'Invoke-HerdrSession.ps1')

$script:HerdrSessionizeDefaults = @'
# Search roots for the herdr folder picker (ctrl+f / hf).
# One entry per line:   path[:depth]
#   depth 0  the folder itself only
#   depth 1  immediate children
#   depth 2+ search that many levels down
# Lines beginning with # are ignored. ~ expands to your home directory.
C:\Projects:1
'@

# Directory names never worth offering as a workspace root.
$script:HerdrSessionizePrune = @(
    '.git', '.svn', '.hg', 'node_modules', '.cache', '.venv', 'venv',
    '__pycache__', 'target', '.npm', '.cargo', '.rustup', 'dist', 'build',
    '.next', '.nuxt', '.parcel-cache', '.pytest_cache', '.mypy_cache',
    '.terraform', 'vendor', '.tox', '.eggs', 'site-packages',
    'bin', 'obj', 'packages', '.vs', '.vscode', 'AppData',
    'Application Data', 'Local Settings', 'My Documents', 'NetHood',
    'PrintHood', 'Recent', 'SendTo', 'Start Menu', 'Templates', 'Cookies'
)

function Get-HerdrSessionizePathFile {
    [CmdletBinding()]
    param()

    if ($env:HERDR_SESSIONIZE_PATHS) { return $env:HERDR_SESSIONIZE_PATHS }
    Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'herdr\sessionize-paths'
}

function Initialize-HerdrSessionizePathFile {
    [CmdletBinding()]
    param()

    $path = Get-HerdrSessionizePathFile
    if (Test-Path -LiteralPath $path) { return $path }

    $dir = Split-Path $path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -LiteralPath $path -Value $script:HerdrSessionizeDefaults -Encoding UTF8
    return $path
}

function Expand-HerdrHomePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    if ($Path -eq '~') { return $HOME }
    if ($Path.StartsWith('~')) { return Join-Path $HOME $Path.Substring(1).TrimStart('\', '/') }
    return $Path
}

function Get-HerdrSessionizeDirectory {
    [CmdletBinding()]
    param()

    $file = Initialize-HerdrSessionizePathFile
    $seen = [System.Collections.Specialized.OrderedDictionary]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($raw in @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)) {
        $line = ($raw -replace '#.*$', '').Trim()
        if (-not $line) { continue }

        # Greedy `.+` claims the last colon, so a drive letter (C:\src) stays
        # part of the path and only a trailing `:<digits>` is read as a depth.
        $depth = 1
        $root = $line
        if ($line -match '^(?<root>.+):(?<depth>\d+)$') {
            $root = $Matches.root
            $depth = [int]$Matches.depth
        }

        $root = Expand-HerdrHomePath $root
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $root = (Resolve-Path -LiteralPath $root).ProviderPath.TrimEnd('\')

        if ($depth -le 0) { $seen[$root] = $true; continue }

        $queue = [System.Collections.Generic.Queue[object]]::new()
        $queue.Enqueue([pscustomobject]@{ Path = $root; Level = 0 })
        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            if ($item.Level -ge $depth) { continue }

            $children = try { [System.IO.Directory]::GetDirectories($item.Path) } catch { @() }
            foreach ($child in $children) {
                $name = [System.IO.Path]::GetFileName($child)
                if ($script:HerdrSessionizePrune -contains $name) { continue }
                $seen[$child] = $true
                $queue.Enqueue([pscustomobject]@{ Path = $child; Level = $item.Level + 1 })
            }
        }
    }

    @($seen.Keys)
}

function Get-HerdrWorkspaceLabel {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $full = $Path.TrimEnd('\')
    $home_ = $HOME.TrimEnd('\')
    # $HOME would otherwise label as "timpham/…"; keep the scratch workspace short.
    if ($full -ieq $home_) { return 'home' }

    $base = Split-Path $full -Leaf
    $parentPath = Split-Path $full -Parent
    $parent = if ($parentPath) { Split-Path $parentPath -Leaf } else { '' }

    $flat = @('Projects', 'repos', 'source', 'src', (Split-Path $home_ -Leaf))
    if (-not $parent -or ($flat -contains $parent) -or $parentPath -ieq $home_) {
        return ($base -replace '\.', '_')
    }
    '{0}/{1}' -f ($parent -replace '\.', '_'), ($base -replace '\.', '_')
}

function Invoke-HerdrApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [string] $Session
    )

    $exe = Get-HerdrExe
    $all = if ($Session) { @('--session', $Session) + $Arguments } else { $Arguments }

    $raw = & $exe @all 2>&1 | Out-String
    if (-not $raw.Trim()) { return $null }

    try { $json = $raw | ConvertFrom-Json } catch { return $null }
    if ($json.PSObject.Properties.Name -contains 'error' -and $json.error) { return $null }
    return $json.result
}

function Get-HerdrTargetSession {
    [CmdletBinding()]
    param([string] $Session)

    if ($Session) { return $Session }
    if ($env:HERDR_SESSION) { return $env:HERDR_SESSION }

    $running = @(Get-HerdrSession) | Where-Object Status -eq 'running' | Select-Object -First 1
    if ($running) { return $running.Name }
    return 'default'
}

function Test-HerdrServer {
    [CmdletBinding()]
    param([string] $Session)

    $null -ne (Invoke-HerdrApi -Arguments @('workspace', 'list') -Session $Session)
}

function Start-HerdrServer {
    [CmdletBinding()]
    param(
        [string] $Session,
        [int] $TimeoutSeconds = 15
    )

    if (Test-HerdrServer -Session $Session) { return $true }

    # `workspace create` needs a live server. Without this the workspace is
    # never created and attaching drops you into a default workspace instead of
    # the project you picked.
    $exe = Get-HerdrExe
    $args_ = if ($Session) { @('--session', $Session, 'server') } else { @('server') }
    Start-Process -FilePath $exe -ArgumentList $args_ -WindowStyle Hidden | Out-Null

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-HerdrServer -Session $Session) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

function Open-HerdrWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Path = $PWD.Path,

        # Session to open the workspace in (defaults to the current one).
        [string] $Session,

        # Stay in the shell instead of attaching when run outside herdr.
        [switch] $NoAttach
    )

    $dir = Expand-HerdrHomePath $Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Write-Warning "not a directory: $Path"
        return
    }
    $dir = (Resolve-Path -LiteralPath $dir).ProviderPath.TrimEnd('\')

    $target = Get-HerdrTargetSession -Session $Session
    if (-not (Start-HerdrServer -Session $target)) {
        Write-Warning "could not start the herdr server for session '$target'."
        return
    }

    $label = Get-HerdrWorkspaceLabel -Path $dir
    $result = Invoke-HerdrApi -Arguments @('workspace', 'list') -Session $target
    $existing = @($result.workspaces) | Where-Object { $_.label -eq $label } | Select-Object -First 1
    $id = $existing.workspace_id

    if (-not $id) {
        $created = Invoke-HerdrApi -Session $target `
            -Arguments @('workspace', 'create', '--cwd', $dir, '--label', $label)
        $id = $created.workspace.workspace_id
    }

    if (-not $id) {
        Write-Warning "could not open '$dir' as a herdr workspace."
        return
    }

    # Focus explicitly: create does not reliably focus when a client is
    # attached, which would leave you in the previous workspace after attaching.
    Invoke-HerdrApi -Arguments @('workspace', 'focus', $id) -Session $target | Out-Null

    # Already inside herdr: the focus above is the whole job, do not nest a client.
    if ($env:HERDR_ENV -eq '1' -or $NoAttach) { return }
    Connect-HerdrSession -Name $target
}

function Invoke-HerdrSessionize {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Path,

        [string] $Session,

        # Print the candidate folders and exit.
        [switch] $List,

        # Open the search-roots file in $env:EDITOR.
        [switch] $Edit
    )

    if ($Edit) {
        $file = Initialize-HerdrSessionizePathFile
        $editor = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
        & $editor $file
        return
    }

    if ($List) { Get-HerdrSessionizeDirectory; return }
    if ($Path) { Open-HerdrWorkspace -Path $Path -Session $Session; return }

    $fzf = Get-FzfExe
    if (-not $fzf) {
        Write-Warning 'fzf not found; install with: winget install --id junegunn.fzf'
        return
    }

    $dirs = @(Get-HerdrSessionizeDirectory)
    if (-not $dirs) {
        Write-Warning "no candidate folders — edit $(Get-HerdrSessionizePathFile) (hf -Edit)"
        return
    }

    # fzf spawns preview children through cmd.exe on Windows, and a double quote
    # written into the --preview string reaches it as \" (PowerShell escapes it,
    # cmd does not undo it), which silently kills the preview. fzf also wraps the
    # {} placeholder in single quotes, which cmd's `dir` does not strip. Route
    # through pwsh instead -- fzf's single quotes are a valid PowerShell string
    # literal -- and keep the quotes in an environment variable's value so none
    # ever reaches fzf's argv.
    $env:HERDR_PWSH = 'pwsh -NoLogo -NoProfile'

    $picked = @($dirs | & $fzf `
            --with-shell 'cmd /c' `
            --prompt 'open workspace> ' --height '100%' --reverse --no-multi `
            --header 'enter: open folder as a herdr workspace   ctrl-c: cancel' `
            --preview '%HERDR_PWSH% -Command Get-ChildItem -Force -Name -LiteralPath {}' `
            --preview-window 'right,50%,border-left')

    if (-not $picked -or -not $picked[0]) { return }
    Open-HerdrWorkspace -Path ([string]$picked[0]).Trim() -Session $Session
}

Set-Alias -Name hf -Value Invoke-HerdrSessionize -Scope Global
Set-Alias -Name hw -Value Open-HerdrWorkspace -Scope Global

if (Get-Module -ListAvailable -Name PSReadLine) {
    try {
        # Re-dot-source before running: functions are cached in memory, so a
        # shell opened before an edit would otherwise keep the stale version.
        $script:HerdrSessionizeLoaderPath = $PSCommandPath
        Set-PSReadLineKeyHandler -Chord 'Ctrl+f' -BriefDescription 'HerdrSessionize' `
            -LongDescription 'Open any folder as a herdr workspace' -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert(
                ". '$($script:HerdrSessionizeLoaderPath)'; Invoke-HerdrSessionize")
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }
    catch { Write-Verbose "Could not bind Ctrl+F for the herdr folder picker: $_" }
}

if ($runPicker) { Invoke-HerdrSessionize }
