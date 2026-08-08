# Wait for a herdr session to stop, then delete its state directory.
#
# `herdr server stop` kills the pane the caller runs in, so the caller cannot
# delete afterwards -- it is already dead. Stop-CurrentHerdrSession.ps1 spawns
# this detached first, then stops the server; this reaps once the socket goes.

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Name,

    [int] $TimeoutSeconds = 60
)

. (Join-Path $PSScriptRoot 'Invoke-HerdrSession.ps1')

$exe = Get-HerdrExe
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ((Get-Date) -lt $deadline) {
    $session = Get-HerdrSession | Where-Object Name -eq $Name

    if (-not $session) { return }
    if ($session.Status -ne 'running') {
        & $exe session delete $Name --json | Out-Null
        return
    }

    Start-Sleep -Milliseconds 500
}
