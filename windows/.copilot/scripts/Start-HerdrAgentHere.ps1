# Start an agent in the FOCUSED herdr pane instead of splitting a new one.
#
# Bound to prefix+a / prefix+shift+a as type = "shell". Herdr's type = "pane"
# opens a fresh pane on every press, so repeated presses pile up panes.
#
# A pane that already runs an agent (or any other foreground process) is left
# alone: `herdr pane run` types into the pane's shell, so firing at a live
# agent would inject the command straight into its prompt.

[CmdletBinding()]
param(
    # Pre-authorize Hunk so code review needs no approval prompts.
    [switch] $Hunk,

    # Target a specific session instead of the one that spawned this command.
    [string] $Session
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $HOME '.herdr\agent-here.log'

function Write-Log {
    param([Parameter(Mandatory)][string] $Message)
    '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message | Add-Content -LiteralPath $logPath
}

function Invoke-Herdr {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $all = if ($Session) { @('--session', $Session) + $Arguments } else { $Arguments }
    $raw = & $script:HerdrExe @all 2>&1 | Out-String

    try { $json = $raw | ConvertFrom-Json }
    catch { throw "unparsable output from 'herdr $($Arguments -join ' ')': $($raw.Trim())" }

    if ($json.error) { throw "herdr $($Arguments -join ' '): $($json.error.message)" }
    return $json.result
}

function Get-FocusedPane {
    # `pane current` resolves through the attached client and is authoritative,
    # but errors when nothing is attached; `pane list` still marks the focus.
    try { return (Invoke-Herdr @('pane', 'current', '--current')).pane }
    catch {
        $panes = @((Invoke-Herdr @('pane', 'list')).panes | Where-Object { $_.focused })
        if (-not $panes) { throw 'no focused herdr pane found.' }
        return $panes[0]
    }
}

try {
    . (Join-Path $PSScriptRoot 'Invoke-HerdrSession.ps1')
    $script:HerdrExe = Get-HerdrExe

    # Single quotes survive `pane run`, which types argv into the shell verbatim.
    $command = @('agency', 'copilot')
    if ($Hunk) { $command += @('--allow-tool', "'shell(hunk:*)'") }

    Write-Log "invoked session=[$env:HERDR_SESSION] sock=[$env:HERDR_SOCKET_PATH] hunk=[$Hunk]"

    $pane = Get-FocusedPane
    $info = (Invoke-Herdr @('pane', 'process-info', '--pane', $pane.pane_id)).process_info

    # An idle shell reports itself as its only foreground process.
    $foreign = @($info.foreground_processes | Where-Object { $_.pid -ne $info.shell_pid })

    if ($pane.agent -or $foreign) {
        $busy = if ($pane.agent) { "agent '$($pane.agent)'" } else { $foreign[0].name }
        Write-Log "skipped $($pane.pane_id): busy with $busy"
        return
    }

    Invoke-Herdr (@('pane', 'run', $pane.pane_id) + $command) | Out-Null
    Write-Log "started [$($command -join ' ')] in $($pane.pane_id)"
}
catch {
    Write-Log "error: $_ | $($_.ScriptStackTrace -replace '\s*\r?\n\s*', ' <- ')"
    exit 1
}
