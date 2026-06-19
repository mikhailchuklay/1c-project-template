#Requires -Version 5.1
<#
.SYNOPSIS
    Запуск автономного сервера 1С (ibsrv) для DEV-публикации на localhost.
    Кроссплатформенно (Windows PowerShell 5.1 / PowerShell 7+ на Windows/Linux/macOS).
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_DevEnv.ps1')

$projectRoot = Get-ProjectRootFromScript -ScriptRoot $PSScriptRoot
$envMap = Read-DevEnvFile -ProjectRoot $projectRoot
$cfg = Get-StandaloneDefaults -ProjectRoot $projectRoot -Env $envMap
$ibsrv = Get-PlatformExe -Env $envMap -ExeName 'ibsrv'

if (-not (Test-Path $cfg.ConfigPath)) {
    throw "Нет config.yml. Сначала выполните: init-config.ps1"
}

New-Item -ItemType Directory -Force -Path $cfg.DataPath | Out-Null

$running = Get-Process ibsrv -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "ibsrv уже запущен (PID $($running.Id))"
} else {
    if (-not $script:OnWindows) {
        # Снять возможные «висящие» блокировки от убитого ранее процесса.
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $cfg.DataPath 'lock.pid')
        Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path (Join-Path $cfg.DataPath 'ipc-data') '.registry.lock')
        # На Linux/macOS ibsrv демонизируется флагом --daemon (двойной fork, чистый detach).
        & $ibsrv "--config=$($cfg.ConfigPath)" "--data=$($cfg.DataPath)" --daemon
    } else {
        Start-Process -FilePath $ibsrv `
            -ArgumentList "--config=`"$($cfg.ConfigPath)`"", "--data=`"$($cfg.DataPath)`"" `
            -WindowStyle Hidden
    }
    Start-Sleep -Seconds 3
    Write-Host "ibsrv запущен"
}

try {
    $r = Invoke-WebRequest -Uri $cfg.PublishUrl -UseBasicParsing -TimeoutSec 15
    Write-Host "Проверка: $($cfg.PublishUrl) -> $($r.StatusCode)"
} catch {
    Write-Warning "Публикация пока не отвечает: $($cfg.PublishUrl)"
}
