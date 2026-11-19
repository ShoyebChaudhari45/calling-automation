# Rudvaya AI Lead Automation — n8n startup script
# Double-click start-n8n.bat (next to this file) to run this, or run it
# directly with: powershell -ExecutionPolicy Bypass -File start-n8n.ps1
#
# Sets the two environment variables n8n needs for this demo every time
# (timezone + the file-access allowlist for the dashboard/WhatsApp/simulator
# pages) so you never have to remember them, then starts n8n and opens the
# dashboard automatically once it's ready.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

$env:GENERIC_TIMEZONE = "Asia/Kolkata"
$env:N8N_RESTRICT_FILE_ACCESS_TO = "$root\pages;$env:USERPROFILE\.n8n-files"

$existing = Get-NetTCPConnection -LocalPort 5678 -State Listen -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "n8n is already running (PID $($existing.OwningProcess)). Opening the dashboard..." -ForegroundColor Green
    Start-Process "http://localhost:5678/webhook/dashboard"
    exit 0
}

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host " Starting Rudvaya AI Lead Automation Demo" -ForegroundColor Cyan
Write-Host " KEEP THIS WINDOW OPEN during the demo." -ForegroundColor Yellow
Write-Host " Closing this window stops n8n and ends the demo." -ForegroundColor Yellow
Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Boot takes about 30-60 seconds. The dashboard will open" -ForegroundColor Gray
Write-Host "automatically in your browser once n8n is ready." -ForegroundColor Gray
Write-Host ""

# Poll in the background and open the browser the moment the dashboard
# webhook responds, instead of making the presenter watch the console.
Start-Job -ScriptBlock {
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:5678/webhook/dashboard" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) {
                Start-Process "http://localhost:5678/webhook/dashboard"
                break
            }
        } catch {}
        Start-Sleep -Seconds 2
    }
} | Out-Null

n8n start
