#Requires -Version 5.1
param(
    [int]$IntervalMinutes = 30,
    [int]$BatchSize = 100,
    [string]$ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
)

$monitorScript = Join-Path $PSScriptRoot 'Monitor-IncomingMailPurge.ps1'
$monitorLock = Join-Path $ProjectRoot 'build\size-analysis-block4-monitor.lock'

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*Monitor-IncomingMailPurge*' -and $_.CommandLine -notlike '*Start-IncomingMailPurgeMonitor*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

if (Test-Path $monitorLock) { Remove-Item $monitorLock -Force -ErrorAction SilentlyContinue }

$cmd = "& '$monitorScript' -IntervalMinutes $IntervalMinutes -BatchSize $BatchSize"
Start-Process -FilePath 'powershell.exe' `
    -WorkingDirectory $ProjectRoot `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd `
    -WindowStyle Hidden | Out-Null

Start-Sleep -Seconds 3
if (Test-Path $monitorLock) {
    Write-Output "monitor_started pid=$((Get-Content $monitorLock -Raw).Trim()) interval=${IntervalMinutes}m"
}
else {
    Write-Error 'monitor failed to start'
    exit 1
}
