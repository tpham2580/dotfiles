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

function Get-HerdrFocusedDirectory {
    [CmdletBinding()]
    param([string] $Session)

    $exe = Get-HerdrExe
    $all = if ($Session) {
        @('--session', $Session, 'pane', 'current', '--current')
    }
    else {
        @('pane', 'current', '--current')
    }

    try {
        $response = (& $exe @all 2>&1 | Out-String) | ConvertFrom-Json -ErrorAction Stop
        if ($response.result.pane.cwd -and
            (Test-Path -LiteralPath $response.result.pane.cwd -PathType Container)) {
            return (Resolve-Path -LiteralPath $response.result.pane.cwd).ProviderPath
        }
    }
    catch {
        Write-Verbose "Could not resolve focused Herdr pane directory: $_"
    }

    return $PWD.ProviderPath
}

function Open-HerdrSessionInTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name,
        [string] $Directory
    )

    $wtPath = (Get-Command wt -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1).Source
    if (-not $wtPath) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
        if (Test-Path $candidate) { $wtPath = $candidate }
    }
    if (-not $wtPath) { Write-Warning 'Windows Terminal (wt.exe) not found.'; return }

    $loader = Join-Path $PSScriptRoot 'Invoke-HerdrSession.ps1'
    $escapedLoader = $loader.Replace("'", "''")
    $escapedName = $Name.Replace("'", "''")
    $tabArgs = @('--window', '0', 'new-tab', '--title', "herdr:$Name")
    if ($Directory -and (Test-Path -LiteralPath $Directory -PathType Container)) {
        $tabArgs += @('--startingDirectory', (Resolve-Path -LiteralPath $Directory).ProviderPath)
    }
    $tabArgs += @(
        'pwsh.exe',
        '-NoLogo',
        '-NoExit',
        '-Command',
        ". '$escapedLoader'; Connect-HerdrSession -Name '$escapedName'"
    )
    & $wtPath @tabArgs
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
        $directory = if ($Choice.IsExisting) {
            $null
        }
        else {
            Get-HerdrFocusedDirectory -Session $CurrentSession
        }
        Open-HerdrSessionInTab -Name $name -Directory $directory
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

    $isNew = $false
    if (-not $Name) {
        $choice = Show-HerdrSessionPicker
        if (-not $choice) { return }

        $current = $env:HERDR_SESSION
        if (-not $current -and $env:HERDR_ENV -eq '1') { $current = 'default' }

        if ((Invoke-HerdrPickerAction -Choice $choice -CurrentSession $current) -ne 'switch') { return }
        $Name = $choice.Name
        $isNew = -not $choice.IsExisting
    }

    if (-not $Name) { return }

    if ($env:HERDR_ENV -eq '1' -and -not $Force) {
        $currentSession = if ($env:HERDR_SESSION) { $env:HERDR_SESSION } else { 'default' }
        $directory = Get-HerdrFocusedDirectory -Session $currentSession

        # A handoff only works when the outer shell launched Herdr through
        # Connect-HerdrSession. Sessions started directly have no loop waiting
        # to consume the switch file, so open the destination in a real tab.
        if ($env:HERDR_WRAPPED -ne '1') {
            Open-HerdrSessionInTab -Name $Name -Directory $(if ($isNew) { $directory } else { $null })
            Write-Host ''
            Write-Host "  Opened herdr session '$Name' in a new terminal tab." -ForegroundColor Cyan
            Write-Host ''
            return
        }

        Set-HerdrSwitch -Name $Name -Directory $(if ($isNew) { $directory } else { $null })
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
        [string] $Name,
        [string] $Directory
    )

    [pscustomobject]@{
        name      = $Name
        directory = $Directory
    } | ConvertTo-Json -Compress | Set-Content -Path (Get-HerdrHandoffPath) -Encoding UTF8
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
        [string] $Name,
        [string] $Directory
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
        $oldWrapped = $env:HERDR_WRAPPED
        $env:HERDR_WRAPPED = '1'
        $pushed = $false
        try {
            if ($Directory -and (Test-Path -LiteralPath $Directory -PathType Container)) {
                Push-Location -LiteralPath $Directory
                $pushed = $true
            }
            & $exe --session $Name
        }
        finally {
            if ($pushed) { Pop-Location }
            if ($null -eq $oldWrapped) {
                Remove-Item Env:\HERDR_WRAPPED -ErrorAction SilentlyContinue
            }
            else {
                $env:HERDR_WRAPPED = $oldWrapped
            }
        }

        $next = $null
        $nextDirectory = $null
        $path = Get-HerdrHandoffPath
        if (Test-Path $path) {
            $handoff = (Get-Content $path -Raw).Trim()
            Remove-Item $path -Force

            try {
                $parsed = $handoff | ConvertFrom-Json -ErrorAction Stop
                $next = $parsed.name
                $nextDirectory = $parsed.directory
            }
            catch {
                # Backward compatibility with handoff files written by the
                # previous version, which contained only the session name.
                $next = $handoff
            }
        }

        if ($next -and $next -ne $Name) {
            Write-Host "-> switching to herdr session '$next'" -ForegroundColor Cyan
            $Name = $next
            $Directory = $nextDirectory
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

# Make the ordinary `herdr` command handoff-aware. Explicit CLI arguments still
# go straight to the executable, so `herdr --version` and API commands are
# unchanged.
function global:herdr {
    $exe = Get-HerdrExe
    if ($args.Count -eq 0) {
        Connect-HerdrSession
        return
    }
    & $exe @args
}

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
