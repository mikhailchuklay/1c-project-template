#Requires -Version 5.1
<#
.SYNOPSIS
    Запускает удаление входящей почты как фоновое задание на сервере 1С (не зависит от локального PowerShell).

.DESCRIPTION
    1. EPF должен лежать на диске СЕРВЕРА 1С (путь, доступный ragent/crserver).
    2. Соберите EPF из src/epf/УдалениеВходящейПочты (Конфигуратор или 1c-platform-tools).
    3. Скопируйте .epf на сервер и укажите -EpfServerPath.

.EXAMPLE
    .\Start-IncomingMailServerBackgroundJob.ps1 -EpfServerPath 'C:\1c\epf\УдалениеВходящейПочты.epf'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EpfServerPath,

    [int]$BatchSize = 100,

    [string]$Url = 'http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

$base = Join-Path $PSScriptRoot 'Invoke-DataMcp.ps1'
$bslTemplate = Join-Path $PSScriptRoot 'Start-IncomingMailServerBackgroundJob.bsl'

$code = (Get-Content -Path $bslTemplate -Raw -Encoding UTF8) `
    .Replace('__EPF_PATH__', $EpfServerPath.Replace("'", "''")) `
    .Replace('__BATCH__', [string]$BatchSize) `
    .Trim()

Write-Host "Starting server background job, EPF=$EpfServerPath batch=$BatchSize"
& $base code -Url $Url -Text $code
