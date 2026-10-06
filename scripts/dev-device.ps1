<#
.SYNOPSIS
  Makes a USB-connected Android phone able to reach the local backend, then starts the backend
  if it is not already running. Run it whenever the app shows "Could not reach the server".

.DESCRIPTION
  The debug app talks to http://127.0.0.1:8000 (mobile/env/.env.development). On the phone that
  address is the phone itself, so `adb reverse` forwards it to this PC. The forward disappears
  whenever adb restarts or the cable is reseated, and the backend stops when this PC restarts.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\dev-device.ps1
#>
param(
  [int]$Port = 8000,
  # Serve the backend to other devices on the same Wi-Fi (the staging test APK talks to this PC's
  # LAN address). Without it the backend only listens on this PC (127.0.0.1) for the USB phone.
  [switch]$Lan
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# 1. Phone link ------------------------------------------------------------------------------
$devices = @(& adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\sdevice$" })
if ($devices.Count -eq 0 -and -not $Lan) {
  Write-Error 'No authorised Android device found. Connect the phone by USB and accept the debugging prompt.'
}
if ($devices.Count -gt 0) {
  & adb reverse "tcp:$Port" "tcp:$Port" | Out-Null
  Write-Host "adb reverse tcp:$Port -> this PC: OK" -ForegroundColor Green
} else {
  Write-Host 'No USB phone connected (fine in -Lan mode: test phones use the Wi-Fi address).' -ForegroundColor Yellow
}

# 2. Backend ---------------------------------------------------------------------------------
function Test-Backend {
  try {
    (Invoke-WebRequest -Uri "http://127.0.0.1:$Port/openapi.json" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200
  } catch { $false }
}

function Get-LanIp {
  (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -match 'Wi-?Fi|Ethernet' -and $_.InterfaceAlias -notmatch 'vEthernet|WSL|Loopback' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1).IPAddress
}

if (Test-Backend) {
  $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  $loopbackOnly = $listener -and $listener.LocalAddress -in @('127.0.0.1', '::1')
  if ($Lan -and $loopbackOnly) {
    # Running, but only reachable from this PC: restart it so other devices can connect.
    Write-Host 'Restarting the backend so it is reachable on the local network...'
    Stop-Process -Id $listener.OwningProcess -Force
    Start-Sleep -Seconds 2
  } else {
    Write-Host "Backend already running on port ${Port}: OK" -ForegroundColor Green
    if ($Lan) { Write-Host "Reachable for other devices at http://$(Get-LanIp):$Port" -ForegroundColor Green }
    return
  }
}

$uvicorn = Join-Path $repo 'backend\.venv\Scripts\uvicorn.exe'
if (-not (Test-Path $uvicorn)) {
  Write-Error "Backend virtualenv not found at $uvicorn. Create it and install backend\requirements.txt first."
}

Write-Host 'Starting the backend...'
Start-Process -FilePath $uvicorn `
  -ArgumentList 'app.main:app', '--host', $(if ($Lan) { '0.0.0.0' } else { '127.0.0.1' }), '--port', $Port `
  -WorkingDirectory (Join-Path $repo 'backend') `
  -RedirectStandardOutput (Join-Path $repo 'backend\uvicorn.log') `
  -RedirectStandardError (Join-Path $repo 'backend\uvicorn.err.log') `
  -WindowStyle Hidden

for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Seconds 2
  if (Test-Backend) {
    Write-Host "Backend is up on port ${Port}: OK" -ForegroundColor Green
    if ($Lan) {
      Write-Host "Reachable for other devices at http://$(Get-LanIp):$Port (Windows Firewall must allow inbound TCP $Port)." -ForegroundColor Green
    }
    return
  }
}
Write-Error "The backend did not answer on port $Port. See backend\uvicorn.err.log."
