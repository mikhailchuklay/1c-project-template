#Requires -Version 5.1
<#
.SYNOPSIS
    Остановка автономного сервера 1С (ibsrv) + снятие «висящих» блокировок.
    Кроссплатформенно (Windows PowerShell 5.1 / PowerShell 7+ на Windows/Linux/macOS).
#>
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot '_DevEnv.ps1')

$projectRoot = Get-ProjectRootFromScript -ScriptRoot $PSScriptRoot
$envMap = Read-DevEnvFile -ProjectRoot $projectRoot
$cfg = Get-StandaloneDefaults -ProjectRoot $projectRoot -Env $envMap

$lockPid = Join-Path $cfg.DataPath 'lock.pid'

# 1) Грациозно — по PID из lock.pid (на Linux/macOS SIGTERM, чтобы сервер снял блокировки сам).
if (Test-Path $lockPid) {
    $srvPid = (Get-Content $lockPid -Raw).Trim()
    if ($srvPid -match '^\d+$') {
        if ($script:OnWindows) {
            Stop-Process -Id ([int]$srvPid) -Force -ErrorAction SilentlyContinue
        } else {
            & kill -TERM $srvPid 2>$null
        }
    }
}

# 2) Подождать аккуратного завершения.
for ($i = 0; $i -lt 15; $i++) {
    if (-not (Get-Process ibsrv -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Seconds 1
}

# 3) Добить, если остался.
Get-Process ibsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 4) Снять блокировки (иначе следующий старт упрётся в lock/registry).
Remove-Item -Force -ErrorAction SilentlyContinue $lockPid
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path (Join-Path $cfg.DataPath 'ipc-data') '.registry.lock')

Write-Host "ibsrv остановлен"
