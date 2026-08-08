# Kill the Herdr session this pane belongs to, from a popup keybinding.
#
# Herdr has no built-in "stop session" action -- its bindings only close
# workspaces, tabs, and panes. `herdr server stop` targets the current session
# via HERDR_SOCKET_PATH, so this wraps it in a typed confirmation.
#
# Wire up in %APPDATA%\herdr\config.toml:
#   [[keys.command]]
#   key = "prefix+alt+k"
#   type = "popup"
#   command = 'pwsh -NoLogo -NoProfile -File "C:\Users\<you>\.copilot\scripts\Stop-CurrentHerdrSession.ps1"'

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Invoke-HerdrSession.ps1')

$name = if ($env:HERDR_SESSION) { $env:HERDR_SESSION } else { 'default' }

$panes = 0
try {
    $exe = Get-HerdrExe
    $json = & $exe pane list 2>$null | ConvertFrom-Json
    $panes = @($json.result.panes).Count
}
catch { }

Write-Host ''
Write-Host '  KILL HERDR SESSION' -ForegroundColor Red
Write-Host ''
Write-Host '    session : ' -NoNewline -ForegroundColor DarkGray
Write-Host $name -ForegroundColor Cyan
if ($panes) {
    Write-Host '    panes   : ' -NoNewline -ForegroundColor DarkGray
    Write-Host "$panes (all processes in them are terminated)" -ForegroundColor Yellow
}
Write-Host '    then    : ' -NoNewline -ForegroundColor DarkGray
Write-Host 'the session is DELETED, not left in the list as stopped' -ForegroundColor Yellow
Write-Host ''
Write-Host "  Type the session name to confirm, or press enter to cancel." -ForegroundColor DarkGray
Write-Host '  > ' -NoNewline -ForegroundColor Yellow

$answer = $Host.UI.ReadLine()

if ($answer -ne $name) {
    Write-Host ''
    Write-Host '  Cancelled.' -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    return
}

Write-Host ''
Write-Host "  Stopping and deleting '$name'..." -ForegroundColor Red

$exe = Get-HerdrExe

# Stopping the server kills this very pane, so the delete has to outlive it.
$reaper = Join-Path $PSScriptRoot 'Remove-StoppedHerdrSession.ps1'
$pwshPath = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1).Source
if (-not $pwshPath) { $pwshPath = 'powershell.exe' }

Start-Process -FilePath $pwshPath `
    -ArgumentList '-NoLogo', '-NoProfile', '-WindowStyle', 'Hidden', '-File', $reaper, '-Name', $name `
    -WindowStyle Hidden | Out-Null

& $exe server stop
