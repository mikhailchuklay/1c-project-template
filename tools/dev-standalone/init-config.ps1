#Requires -Version 5.1
<#
.SYNOPSIS
    Инициализация конфигурации автономного сервера 1С (config.yml).
    Кроссплатформенно (Windows PowerShell 5.1 / PowerShell 7+ на Windows/Linux/macOS).
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_DevEnv.ps1')

$projectRoot = Get-ProjectRootFromScript -ScriptRoot $PSScriptRoot
$envMap = Read-DevEnvFile -ProjectRoot $projectRoot
$cfg = Get-StandaloneDefaults -ProjectRoot $projectRoot -Env $envMap
$ibcmd = Get-PlatformExe -Env $envMap -ExeName 'ibcmd'

New-Item -ItemType Directory -Force -Path $cfg.StandaloneRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $cfg.ConfigPath -Parent) | Out-Null

& $ibcmd server config init `
    --db-path="$($cfg.IbPath)" `
    --name="$($cfg.ServerName)" `
    --base="$($cfg.HttpBase)" `
    --address="$($cfg.Address)" `
    --port="$($cfg.Port)" `
    --out="$($cfg.ConfigPath)"

Write-Host "Создан: $($cfg.ConfigPath)"
Write-Host "DEV URL: $($cfg.PublishUrl)"
