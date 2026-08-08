# Herdr session picker (fzf) + detach/switch handoff.
#
# Herdr sessions are separate server processes with separate sockets, so the
# in-app workspace picker can never show them. This provides the missing
# cross-session navigation from PowerShell.
#
#   hsw            Alt+S -> fzf picker over `herdr session list`
#   hdr [name]     Attach in a loop that honors the switch handoff file
#
# Inside a Herdr pane the picker writes the chosen session to a handoff file;
# pressing the detach key then makes the outer `hdr` loop attach to it.

function Get-HerdrHandoffPath {
    Join-Path $HOME '.herdr\.switch-target'
}

function Get-HerdrExe {
    [CmdletBinding()]
    param()

    $cmd = Get-Command herdr -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    $fallback = Join-Path $HOME '.herdr\packages\standalone\current\herdr.exe'
    if (Test-Path $fallback) { return $fallback }

    throw 'herdr executable not found on PATH or in ~\.herdr\packages\standalone\current.'
}

function Get-FzfExe {
    [CmdletBinding()]
    param()

    $cmd = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }

    # The herdr server may have been started before fzf was installed, so a
    # popup inherits a PATH without the WinGet shim directory.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\fzf.exe'),
        (Join-Path $env:ProgramData 'chocolatey\bin\fzf.exe'),
        (Join-Path $HOME 'scoop\shims\fzf.exe')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }

    return $null
}

function Get-HerdrSession {
    [CmdletBinding()]
    param()

    $exe = Get-HerdrExe
    $lines = & $exe session list 2>&1
    if ($LASTEXITCODE -ne 0) { throw "herdr session list failed: $lines" }

    $current = $env:HERDR_SESSION
    if (-not $current -and $env:HERDR_ENV -eq '1') { $current = 'default' }

    foreach ($line in $lines) {
        $text = [string]$line
        if ($text -match '^\s*name\s+status\b') { continue }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -notmatch '^(?<name>\S+)\s+(?<status>\S+)\s+(?<dir>.+?)\s+(?<sock>\S+)$') { continue }

        [pscustomobject]@{
            Name      = $Matches.name
            Status    = $Matches.status
            Directory = $Matches.dir.Trim()
            Socket    = $Matches.sock
            IsCurrent = ($Matches.name -eq $current)
        }
    }
}

function Confirm-HerdrAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Prompt)

    Write-Host ''
    Write-Host "$Prompt [y/N] " -NoNewline -ForegroundColor Yellow

    # RawUI.ReadKey needs a real console; fall back when input is redirected
    # or the host is non-interactive so the picker never throws or blocks.
    $answer = ''
    try {
        $answer = if ([Console]::IsInputRedirected) {
            [string][Console]::In.ReadLine()
        }
        else {
            [string]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character
        }
    }
    catch {
        try { $answer = [string][Console]::In.ReadLine() } catch { $answer = '' }
    }

    Write-Host $answer
    return ($answer -match '^[yY]')
}

function Show-HerdrSessionPicker {
    [CmdletBinding()]
    param([string] $Height = '40%')

    $sessions = @(Get-HerdrSession)
    if (-not $sessions) { Write-Warning 'No herdr sessions found.'; return }

    $fzf = Get-FzfExe
    if (-not $fzf) {
        Write-Warning 'fzf not found; install with: winget install --id junegunn.fzf'
        $sessions | Format-Table Name, Status, Directory
        return
    }

    $rows = $sessions | ForEach-Object {
        $marker = if ($_.IsCurrent) { '*' } else { ' ' }
        '{0} {1,-20} {2,-8} {3}' -f $marker, $_.Name, $_.Status, $_.Directory
    }

    $header = 'enter = switch/create   |   ctrl-t = new terminal tab   |   ctrl-x = stop   |   del = stop + DELETE'
    # @() is required: fzf returning a single line yields a String, and
    # indexing a String gives one character rather than the whole line.
    $picked = @($rows | & $fzf --height $Height --reverse --prompt 'herdr session> ' `
            --header $header --print-query --expect 'ctrl-t,ctrl-x,ctrl-d,del' --no-multi)

    # --print-query + --expect emit: query, pressed key, then selection if any.
    if (-not $picked -or $picked.Count -lt 2) { return }

    $query = ([string]$picked[0]).Trim()
    $key = ([string]$picked[1]).Trim()

    if ($picked.Count -gt 2 -and $picked[2] -and ([string]$picked[2]) -match '^[*\s]\s*(?<name>\S+)') {
        return [pscustomobject]@{ Name = $Matches.name; Key = $key; IsExisting = $true }
    }
    if ($query) {
        return [pscustomobject]@{ Name = $query; Key = $key; IsExisting = $false }
    }
}

function Open-HerdrSessionInTab {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    $wtPath = (Get-Command wt -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1).Source
    if (-not $wtPath) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
        if (Test-Path $candidate) { $wtPath = $candidate }
    }
    if (-not $wtPath) { Write-Warning 'Windows Terminal (wt.exe) not found.'; return }

    $loader = Join-Path $PSScriptRoot 'Invoke-HerdrSession.ps1'
    & $wtPath --window 0 new-tab --title "herdr:$Name" `
        pwsh.exe -NoLogo -NoExit -Command ". '$loader'; Connect-HerdrSession -Name '$Name'"
}

function Invoke-HerdrPickerAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Choice,
        [string] $CurrentSession
    )

    $name = $Choice.Name

    if ($Choice.Key -in @('ctrl-x', 'ctrl-d', 'del')) {
        if (-not $Choice.IsExisting) { Write-Warning "No such session: $name"; return 'handled' }

        $delete = ($Choice.Key -ne 'ctrl-x')
        $verb = if ($delete) { 'STOP AND DELETE' } else { 'STOP' }

        if ($name -eq $CurrentSession) {
            Write-Host ''
            Write-Host "  '$name' is the session you are attached to." -ForegroundColor Red
            Write-Host '  Stopping it kills every pane and process in it right now.' -ForegroundColor Red
        }

        if (Confirm-HerdrAction "$verb herdr session '$name'?") {
            Stop-HerdrSession -Name $name -Delete:$delete -Confirm:$false
        }
        return 'handled'
    }

    if (-not $Choice.IsExisting) {
        if (-not (Confirm-HerdrAction "Session '$name' does not exist. Create it?")) { return 'handled' }
    }

    if ($Choice.Key -eq 'ctrl-t') {
        Open-HerdrSessionInTab -Name $name
        return 'handled'
    }

    return 'switch'
}

function Switch-HerdrSession {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Name,

        # Attach directly even when running inside a Herdr pane (nests the TUI).
        [switch] $Force
    )

    if (-not $Name) {
        $choice = Show-HerdrSessionPicker
        if (-not $choice) { return }

        $current = $env:HERDR_SESSION
        if (-not $current -and $env:HERDR_ENV -eq '1') { $current = 'default' }

        if ((Invoke-HerdrPickerAction -Choice $choice -CurrentSession $current) -ne 'switch') { return }
        $Name = $choice.Name
    }

    if (-not $Name) { return }

    if ($env:HERDR_ENV -eq '1' -and -not $Force) {
        Set-HerdrSwitch -Name $Name
        Write-Host ''
        Write-Host "  Switch target set: " -NoNewline -ForegroundColor DarkGray
        Write-Host $Name -ForegroundColor Cyan
        Write-Host "  Press the detach key to leave this session and land in it." -ForegroundColor DarkGray
        Write-Host "  (Cancel with: Clear-HerdrSwitch)" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Connect-HerdrSession -Name $Name
}

function Set-HerdrSwitch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name
    )

    Set-Content -Path (Get-HerdrHandoffPath) -Value $Name -Encoding UTF8
}

function Clear-HerdrSwitch {
    [CmdletBinding()]
    param()

    $path = Get-HerdrHandoffPath
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host 'Pending herdr switch cleared.' -ForegroundColor DarkGray
    }
}

function Connect-HerdrSession {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Name
    )

    if ($env:HERDR_ENV -eq '1') {
        Write-Warning 'Already inside a Herdr pane. Use hsw to queue a switch, then detach.'
        return
    }

    $exe = Get-HerdrExe
    Clear-HerdrSwitch | Out-Null

    if (-not $Name) {
        $sessions = @(Get-HerdrSession)
        $running = $sessions | Where-Object Status -eq 'running' | Select-Object -First 1
        $Name = if ($running) { $running.Name } else { 'default' }
    }

    while ($Name) {
        & $exe --session $Name

        $next = $null
        $path = Get-HerdrHandoffPath
        if (Test-Path $path) {
            $next = (Get-Content $path -Raw).Trim()
            Remove-Item $path -Force
        }

        if ($next -and $next -ne $Name) {
            Write-Host "-> switching to herdr session '$next'" -ForegroundColor Cyan
            $Name = $next
        }
        else { $Name = $null }
    }
}

function Stop-HerdrSession {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        # Also delete the stopped session's state directory.
        [switch] $Delete
    )

    $exe = Get-HerdrExe
    if (-not $PSCmdlet.ShouldProcess($Name, 'stop herdr session')) { return }

    $out = & $exe session stop $Name --json 2>&1 | Out-String
    if ($out -match '"error"') { Write-Warning $out.Trim() } else { Write-Host "stopped '$Name'" -ForegroundColor DarkGray }

    if ($Delete) {
        $out = & $exe session delete $Name --json 2>&1 | Out-String
        if ($out -match '"error"') { Write-Warning $out.Trim() } else { Write-Host "deleted '$Name'" -ForegroundColor DarkGray }
    }
}

Set-Alias -Name hsw -Value Switch-HerdrSession -Scope Global
Set-Alias -Name hdr -Value Connect-HerdrSession -Scope Global

if (Get-Module -ListAvailable -Name PSReadLine) {
    try {
        # Re-dot-source before running: functions are cached in memory, so a
        # shell opened before an edit would otherwise keep the stale version.
        $script:HerdrLoaderPath = $PSCommandPath
        Set-PSReadLineKeyHandler -Chord 'Alt+s' -BriefDescription 'HerdrSessionPicker' `
            -LongDescription 'Pick a herdr session with fzf' -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert(
                ". '$($script:HerdrLoaderPath)'; Switch-HerdrSession")
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }
    catch { Write-Verbose "Could not bind Alt+S for the herdr session picker: $_" }
}
