# Herdr sessionizer — fzf picker over herdr workspaces and named sessions.
# The Windows port of ~/.script/herdr-sessionizer.
#
# Concept map from tmux:
#   tmux session          -> herdr WORKSPACE   (switch in place)
#   tmux switch-client -t -> herdr workspace focus
#   tmux new-session -c   -> herdr workspace create --cwd   (see hf / Invoke-HerdrSessionize)
#
# Keys inside the picker (same as Linux, plus ctrl-t):
#   enter   focus the workspace / switch to the session
#   del     close the workspace, or stop+delete a named session
#           (asks for confirmation, then reopens the picker)
#   ctrl-t  open it in a new Windows Terminal tab instead
#   ctrl-c  cancel
#
#   hz             interactive picker
#   hz -Rows       print the raw picker rows (used by the fzf reload binding)
#
# Wire up in %APPDATA%\herdr\config.toml:
#   [[keys.command]]
#   key = "prefix+alt+s"
#   type = "popup"
#   command = 'pwsh -NoLogo -NoProfile -File "C:\Users\<you>\.copilot\scripts\Invoke-HerdrSessionizer.ps1" -Popup'

[CmdletBinding()]
param(
    # Run the picker straight away instead of only defining the helpers.
    # Used by the herdr popup keybinding; dot-sourcing leaves it unset.
    [switch] $Popup,

    # Emit the raw TAB-delimited rows. fzf's reload binding calls this.
    [switch] $Rows,

    # Close/stop the entity described by -Type/-Session/-Id. fzf's del binding
    # calls this back.
    [switch] $Delete,

    # NOTE: deliberately no [ValidateSet] — fzf hands these over single-quoted
    # and validation runs before the quotes can be stripped. See Get-HerdrUnquoted.
    [string] $Type,

    [string] $Session,

    [string] $Id
)

# The picker no longer drives these entry points (see Show-HerdrSessionizerPicker),
# but they stay useful for scripting and debugging -- and fzf, if it ever calls
# back in, substitutes field placeholders as 'single-quoted' values that cmd.exe
# leaves alone and `pwsh -File` passes through verbatim.
function Get-HerdrUnquoted {
    [CmdletBinding()]
    param([string] $Value)

    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    $v = $Value.Trim()
    while ($v.Length -ge 2 -and
        (($v[0] -eq "'" -and $v[-1] -eq "'") -or ($v[0] -eq '"' -and $v[-1] -eq '"'))) {
        $v = $v.Substring(1, $v.Length - 2).Trim()
    }
    return $v
}

# Captured before dot-sourcing, because a dot-sourced script's param block
# writes into THIS scope and would otherwise clobber these.
$mode = if ($Delete) { 'delete' } elseif ($Rows) { 'rows' } elseif ($Popup) { 'popup' } else { 'library' }
$argType = Get-HerdrUnquoted $Type
$argSession = Get-HerdrUnquoted $Session
$argId = Get-HerdrUnquoted $Id

. (Join-Path $PSScriptRoot 'Invoke-HerdrSessionize.ps1')

$script:HerdrSessionizerPath = $PSCommandPath
$script:HerdrSessionizerTab = "`t"

function Get-HerdrCurrentSessionName {
    [CmdletBinding()]
    param()

    if ($env:HERDR_SESSION) { return $env:HERDR_SESSION }
    if ($env:HERDR_ENV -eq '1') { return 'default' }
    return $null
}

# ---------------------------------------------------------------- row listing
# Row format:  TYPE \t SESSION \t ID \t DISPLAY \t META
#
# Linux only has to name a workspace, because there is a single server. On
# Windows every named session is its own server with its own socket, so the
# session has to travel with the row for the later API calls to reach it.
function Get-HerdrSessionizerRow {
    [CmdletBinding()]
    param()

    $sessions = @(Get-HerdrSession)
    $current = Get-HerdrCurrentSessionName
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($session in ($sessions | Where-Object Status -eq 'running')) {
        $result = Invoke-HerdrApi -Arguments @('workspace', 'list') -Session $session.Name
        foreach ($ws in @($result.workspaces)) {
            $unit = if ($ws.pane_count -eq 1) { 'pane' } else { 'panes' }
            $here = if ($session.Name -eq $current) { '*' } else { ' ' }
            $rows.Add([pscustomobject]@{
                    Type    = 'ws'
                    Session = $session.Name
                    Id      = $ws.workspace_id
                    Display = ('{0} {1,-30} {2}' -f $here, $ws.label, $session.Name)
                    Meta    = ('({0} {1}, {2})' -f $ws.pane_count, $unit, $ws.agent_status)
                })
        }
    }

    foreach ($session in $sessions) {
        $here = if ($session.Name -eq $current) { '*' } else { ' ' }
        $rows.Add([pscustomobject]@{
                Type    = 'ses'
                Session = $session.Name
                Id      = $session.Name
                Display = ('{0} {1,-30} {2}' -f $here, $session.Name, '(session)')
                Meta    = ('[{0}]  {1}' -f $session.Status, $session.Directory)
            })
    }

    $rows
}

function Write-HerdrSessionizerRow {
    [CmdletBinding()]
    param()

    Get-HerdrSessionizerRow | ForEach-Object {
        ($_.Type, $_.Session, $_.Id, $_.Display, $_.Meta) -join $script:HerdrSessionizerTab
    }
}

# ------------------------------------------------------------------- deletion
# Closing is destructive and `del` sits one key away from the arrows, so every
# path here confirms first. This runs in the parent process, which owns the
# console -- see the note in Show-HerdrSessionizerPicker for why it cannot run
# as an fzf binding on Windows.
function Remove-HerdrSessionizerRow {
    [CmdletBinding()]
    param(
        [string] $Type,
        [string] $Session,
        [string] $Id
    )

    if (-not $Id) { return }

    if ($Type -eq 'ws') { Remove-HerdrSessionizerWorkspace -Session $Session -Id $Id; return }

    # Never destroy the default session (as on Linux), nor the session this
    # client is attached to: closing the server out from under the attached
    # client leaves the terminal wedged.
    if ($Id -eq 'default') {
        Write-Warning 'refusing to delete the default session'
        return
    }
    if ($Id -eq (Get-HerdrCurrentSessionName)) {
        Write-Warning "refusing to delete '$Id' — it is the session you are attached to"
        return
    }

    if (-not (Confirm-HerdrAction "Stop and delete session '$Id' and every pane in it?")) { return }
    Stop-HerdrSession -Name $Id -Delete -Confirm:$false | Out-Null
}

function Remove-HerdrSessionizerWorkspace {
    [CmdletBinding()]
    param(
        [string] $Session,
        [string] $Id
    )

    $before = @((Invoke-HerdrApi -Session $Session -Arguments @('workspace', 'list')).workspaces)
    $target = $before | Where-Object workspace_id -eq $Id | Select-Object -First 1
    if (-not $target) { return }   # already closed by an earlier del

    $label = if ($target.label) { $target.label } else { $Id }
    $unit = if ($target.pane_count -eq 1) { 'pane' } else { 'panes' }
    $prompt = "Close workspace '$label' ($($target.pane_count) $unit) in session '$Session'?"
    if (-not (Confirm-HerdrAction $prompt)) { return }

    Invoke-HerdrApi -Session $Session -Arguments @('workspace', 'close', $Id) | Out-Null

    # Closing a background workspace leaves the focus where it was.
    if (-not $target.focused) { return }

    $remaining = @((Invoke-HerdrApi -Session $Session -Arguments @('workspace', 'list')).workspaces)

    # That was the last workspace: the session has nothing left to show, so
    # herdr tears it down and the client drops back to the plain terminal.
    if (-not $remaining) { return }

    # Herdr does not always pick a successor when the focused workspace goes
    # away, which strands the client on a blank view. Take over: prefer the
    # workspace that followed the closed one, else the one before it.
    $survivors = @($before | Where-Object workspace_id -ne $Id)
    $index = [Math]::Min([Array]::IndexOf([string[]]@($before.workspace_id), $Id), $survivors.Count - 1)
    if ($index -lt 0) { $index = 0 }

    $next = $survivors[$index]
    if ($next.workspace_id -notin @($remaining.workspace_id)) { $next = $remaining[0] }

    Invoke-HerdrApi -Session $Session -Arguments @('workspace', 'focus', $next.workspace_id) | Out-Null
}

# -------------------------------------------------------------------- picker
function Show-HerdrSessionizerPicker {
    [CmdletBinding()]
    param([string] $Height = '60%')

    $rows = @(Write-HerdrSessionizerRow)
    if (-not $rows) {
        Write-Warning 'no active herdr workspaces or sessions — use ctrl+f to open a folder'
        return
    }

    $fzf = Get-FzfExe
    if (-not $fzf) {
        Write-Warning 'fzf not found; install with: winget install --id junegunn.fzf'
        Get-HerdrSessionizerRow | Format-Table Type, Session, Id, Meta -AutoSize
        return
    }

    $tab = $script:HerdrSessionizerTab

    # `del` is reported through --expect rather than run as an fzf binding.
    #
    # Linux closes the row in place with execute-silent(...)+reload(...), which
    # works there because a child process can reopen /dev/tty to reach the user.
    # Windows has no such handle: fzf's own stdin is the pipe feeding it rows, so
    # a child spawned by `execute` inherits a stdin already at EOF, on a console
    # fzf is still painting. A confirmation prompt there is invisible and reads
    # nothing, so it always declines -- del appears to do nothing at all, with
    # only the reload spinner as a hint that anything happened.
    #
    # So let fzf exit on del and confirm out in Invoke-HerdrSessionizer, which
    # owns the real console. It reopens the picker afterwards, so closing
    # several workspaces in a row still works -- the list just blinks instead of
    # reloading in place.
    $picked = @($rows | & $fzf `
            --with-shell 'cmd /c' `
            --delimiter $tab --with-nth '4..' `
            --prompt 'herdr> ' --height $Height --reverse --ansi --no-multi `
            --header 'enter: switch   ctrl-t: new terminal tab   del: close (asks first)   ctrl-c: cancel' `
            --expect 'ctrl-t,del')

    # --expect emits the pressed key first (empty for enter), then the selection.
    if (-not $picked -or $picked.Count -lt 2) { return }

    $key = ([string]$picked[0]).Trim()
    $fields = ([string]$picked[1]) -split $tab
    if ($fields.Count -lt 3) { return }

    [pscustomobject]@{
        Key     = $key
        Type    = $fields[0]
        Session = $fields[1]
        Id      = $fields[2]
    }
}

# ------------------------------------------------------------------ dispatch
function Invoke-HerdrSessionizer {
    [CmdletBinding()]
    param(
        # Print the rows and exit.
        [switch] $List,

        [string] $Height = '60%'
    )

    if ($List) {
        Get-HerdrSessionizerRow | Format-Table Type, Session, Id, Meta -AutoSize
        return
    }

    # del closes the picker so the confirmation below runs on the real console,
    # then the picker is reopened -- so several rows can be closed in one go.
    $choice = $null
    while ($true) {
        $choice = Show-HerdrSessionizerPicker -Height $Height
        if (-not $choice) { return }
        if ($choice.Key -ne 'del') { break }

        Remove-HerdrSessionizerRow -Type $choice.Type -Session $choice.Session -Id $choice.Id
    }

    $current = Get-HerdrCurrentSessionName

    # Focusing works across sessions because it is a plain socket call to that
    # session's own server, so the target workspace is already selected by the
    # time the switch below lands.
    if ($choice.Type -eq 'ws') {
        Invoke-HerdrApi -Session $choice.Session `
            -Arguments @('workspace', 'focus', $choice.Id) | Out-Null
    }

    if ($choice.Key -eq 'ctrl-t') {
        Open-HerdrSessionInTab -Name $choice.Session
        return
    }

    if ($choice.Session -eq $current) { return }

    # Inside herdr the client cannot re-point itself at another server, so the
    # target is written to the handoff file and the outer `hdr` loop picks it up
    # on detach. This is the Windows stand-in for Linux's in-place attach.
    if ($env:HERDR_ENV -eq '1') {
        Set-HerdrSwitch -Name $choice.Session
        Write-Host ''
        Write-Host '  Switch target set: ' -NoNewline -ForegroundColor DarkGray
        Write-Host $choice.Session -ForegroundColor Cyan
        Write-Host '  Press the detach key (ctrl+b d) to land in it.' -ForegroundColor DarkGray
        Write-Host '  (Cancel with: Clear-HerdrSwitch)' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Connect-HerdrSession -Name $choice.Session
}

Set-Alias -Name hz -Value Invoke-HerdrSessionizer -Scope Global

if (Get-Module -ListAvailable -Name PSReadLine) {
    try {
        # Re-dot-source before running: functions are cached in memory, so a
        # shell opened before an edit would otherwise keep the stale version.
        Set-PSReadLineKeyHandler -Chord 'Alt+s' -BriefDescription 'HerdrSessionizer' `
            -LongDescription 'Pick a herdr workspace or session with fzf' -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert(
                ". '$($script:HerdrSessionizerPath)'; Invoke-HerdrSessionizer")
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }
    catch { Write-Verbose "Could not bind Alt+S for the herdr sessionizer: $_" }
}

switch ($mode) {
    'rows' { Write-HerdrSessionizerRow }
    'delete' { Remove-HerdrSessionizerRow -Type $argType -Session $argSession -Id $argId }
    # The popup window is already sized by herdr, so fill it rather than
    # reserving 40% of it for a scrollback that does not exist.
    'popup' { Invoke-HerdrSessionizer -Height '100%' }
}
