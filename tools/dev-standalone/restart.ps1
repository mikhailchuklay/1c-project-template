#Requires -Version 5.1
<#
.SYNOPSIS
    Жёсткий перезапуск ibsrv с ожиданием HTTP 200.
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_DevEnv.ps1')

$projectRoot = Get-ProjectRootFromScript -ScriptRoot $PSScriptRoot
$envMap = Read-DevEnvFile -ProjectRoot $projectRoot
$cfg = Get-StandaloneDefaults -ProjectRoot $projectRoot -Env $envMap
$ibsrv = Get-PlatformExe -Env $envMap -ExeName 'ibsrv'
$publishUrl = if ($env:PUBLISH_URL) { $env:PUBLISH_URL } else { $cfg.PublishUrl }
$waitSec = if ($env:WAIT_SEC) { [int]$env:WAIT_SEC } else { 60 }

if (-not (Test-Path $cfg.ConfigPath)) { throw "Нет config.yml: $($cfg.ConfigPath)" }

New-Item -ItemType Directory -Force -Path $cfg.DataPath | Out-Null

Write-Host 'Останавливаем ibsrv...'
Get-Process ibsrv -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Host 'Запускаем ibsrv...'
if (-not $script:OnWindows) {
    & $ibsrv "--config=$($cfg.ConfigPath)" "--data=$($cfg.DataPath)" --daemon
} else {
    Start-Process -FilePath $ibsrv -ArgumentList "--config=`"$($cfg.ConfigPath)`"","--data=`"$($cfg.DataPath)`"" -WindowStyle Hidden
}

$deadline = (Get-Date).AddSeconds($waitSec)
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest -Uri $publishUrl -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) {
            Write-Host "Проверка: $publishUrl -> OK"
            exit 0
        }
    }
    catch {
        # wait
    }
    Start-Sleep -Seconds 2
}

throw "Таймаут ${waitSec}s: публикация не ответила 200: $publishUrl"
