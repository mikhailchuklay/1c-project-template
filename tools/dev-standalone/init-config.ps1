#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_DevEnv.ps1"

$projectRoot = Get-ProjectRootFromScript -ScriptRoot $PSScriptRoot
$envMap = Read-DevEnvFile -ProjectRoot $projectRoot
$cfg = Get-StandaloneDefaults -ProjectRoot $projectRoot -Env $envMap
$ibcmd = Get-PlatformExe -Env $envMap -ExeName 'ibcmd.exe'

New-Item -ItemType Directory -Force -Path $cfg.StandaloneRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $cfg.ConfigPath -Parent) -Force | Out-Null

& $ibcmd server config init `
    --db-path="$($cfg.IbPath)" `
    --name="$($cfg.ServerName)" `
    --base="$($cfg.HttpBase)" `
    --address=localhost `
    --port="$($cfg.Port)" `
    --out="$($cfg.ConfigPath)"

Write-Host "Создан: $($cfg.ConfigPath)"
Write-Host "DEV URL: $($cfg.PublishUrl)"
