# Herdr session picker, launched from a Herdr popup keybinding (prefix+alt+s).
#
# Herdr sessions are separate server processes, so nothing inside a session can
# switch the attached client. Keys:
#
#   enter        queue the switch, then press the detach key -> the outer `hdr`
#                loop re-attaches to the chosen session in place
#   ctrl-t       open the chosen session in a new Windows Terminal tab instead
#   ctrl-x       stop the selected session
#   del / ctrl-d stop and delete the selected session
#
# This is a thin wrapper: all behaviour lives in Invoke-HerdrSession.ps1 so the
# popup and the shell binding (alt+s) can never drift apart.
#
# Wire up in %APPDATA%\herdr\config.toml:
#   [[keys.command]]
#   key = "prefix+alt+s"
#   type = "popup"
#   command = 'pwsh -NoLogo -NoProfile -File "C:\Users\<you>\.copilot\scripts\Select-HerdrSession.ps1"'

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Invoke-HerdrSession.ps1')

function Write-Pause {
    param([string] $Message, [string] $Color = 'Yellow')
    Write-Host ''
    Write-Host $Message -ForegroundColor $Color
    Write-Host ''
    if ([Console]::IsInputRedirected) { return }
    Write-Host 'Press any key to close...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

try {
    $choice = Show-HerdrSessionPicker -Height '100%'
}
catch {
    Write-Pause "Could not list herdr sessions: $_" 'Red'
    return
}

if (-not $choice) { return }

$current = $env:HERDR_SESSION
if (-not $current -and $env:HERDR_ENV -eq '1') { $current = 'default' }

if ((Invoke-HerdrPickerAction -Choice $choice -CurrentSession $current) -ne 'switch') {
    Write-Pause 'Done.' 'DarkGray'
    return
}

Set-HerdrSwitch -Name $choice.Name
Write-Pause "Queued: $($choice.Name)   ->   press your detach key (ctrl+b d) to land in it." 'Cyan'
