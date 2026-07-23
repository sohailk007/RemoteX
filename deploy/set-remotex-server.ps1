# set-remotex-server.ps1
#
# Point an installed RemoteX at the SL Brothers server, on this machine.
#
# Run per machine via your MDM/GPO/RMM (as SYSTEM/admin) during the v1.1.0
# rollout. This is needed because RemoteX caches the last server it used
# (rendezvous_server), and that cache OUTRANKS the value baked into the binary --
# so a plain upgrade does not switch machines that already ran an older build.
# Setting custom-rendezvous-server (priority #2) overrides the cache cleanly.
#
# Uses RemoteX's own supported CLI (`--option`); it does not hand-edit config.
#
# REQUIREMENTS: RemoteX installed via the MSI, and this script run elevated.

[CmdletBinding()]
param(
    [string]$Server = 'relay.slbrothers.co.uk',
    [string]$Relay  = 'relay.slbrothers.co.uk',
    [string]$Key    = 'FFWoBG8GIExaqOwLKr5pFq5ig5aPt6jwVYVjY2fwYM0=',
    # Optional: clear the stale cached rendezvous_server too (belt and braces).
    [switch]$ClearCache
)

$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Error $msg; exit 1 }

# --- must be elevated ---
$admin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail "Run this elevated (as Administrator / SYSTEM)." }

# --- locate the installed RemoteX exe ---
$exe = $null
$reg = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", `
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'RemoteX' } | Select-Object -First 1
$dir = if ($reg -and $reg.InstallLocation) { $reg.InstallLocation } else { "$env:ProgramFiles\RemoteX" }
foreach ($name in @('RemoteX.exe', 'rustdesk.exe')) {
    $p = Join-Path $dir $name
    if (Test-Path $p) { $exe = $p; break }
}
if (-not $exe) { Fail "RemoteX is not installed (no RemoteX.exe under '$dir'). Install the v1.1.0 MSI first." }
Write-Host "RemoteX exe : $exe"

# --- service must be running for the option IPC to apply ---
$svc = Get-Service -Name 'RemoteX' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Running') {
    Start-Service RemoteX
    Start-Sleep -Seconds 2
}

# --- set the server, relay and key via RemoteX's own CLI ---
& $exe --option custom-rendezvous-server $Server | Out-Null
& $exe --option relay-server            $Relay  | Out-Null
& $exe --option key                     $Key    | Out-Null
Write-Host "Applied: custom-rendezvous-server=$Server  relay-server=$Relay  key=<set>"

# --- optionally drop the stale cached rendezvous_server ---
if ($ClearCache) {
    foreach ($cfgRoot in @(
            "$env:APPDATA\RemoteX\config",
            "C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RemoteX\config",
            "C:\Windows\System32\config\systemprofile\AppData\Roaming\RemoteX\config"
        )) {
        $f = Join-Path $cfgRoot 'RemoteX2.toml'
        if (Test-Path $f) {
            (Get-Content $f) | Where-Object { $_ -notmatch '^\s*rendezvous_server\s*=' } | Set-Content $f
            Write-Host "Cleared cached rendezvous_server in $f"
        }
    }
}

# --- restart so the rendezvous mediator reconnects to the new server ---
if ($svc) {
    Restart-Service RemoteX
    Start-Sleep -Seconds 2
}

# --- verify: read the value back ---
$check = (& $exe --option custom-rendezvous-server) 2>$null
Write-Host ""
if ($check -and $check.Trim() -eq $Server) {
    Write-Host "VERIFIED: RemoteX now points at $Server" -ForegroundColor Green
} else {
    Write-Warning "Set command ran, but read-back was '$check'. Check that the RemoteX service is running and re-run."
}
