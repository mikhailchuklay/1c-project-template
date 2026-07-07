#Requires -Version 5.1
<#
.SYNOPSIS
    Устанавливает APA-инструмент s3_dev_probe через MCP vcexecutecode (без UI-импорта XML).
#>
[CmdletBinding()]
param(
    [string]$EnvFile
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$build = Join-Path $projectRoot 'build'
$zapros = Join-Path $build 's3_dev_probe_zapros.bsl'
$installer = Join-Path $build 'install-s3-apa-tools.bsl'

if (-not (Test-Path $zapros)) {
    throw "Не найден $zapros"
}
if (-not (Test-Path $installer)) {
    throw "Не найден $installer"
}

$start = Join-Path $PSScriptRoot 'start.ps1'
if (-not (Get-Process ibsrv -ErrorAction SilentlyContinue)) {
    & $start
}

$invoke = Join-Path $PSScriptRoot 'Invoke-DataMcp.ps1'
$invokeArgs = @('-Action', 'code', '-File', $installer, '-NoFlatten')
if ($EnvFile) { $invokeArgs += @('-EnvFile', $EnvFile) }

& $invoke @invokeArgs
$code = $LASTEXITCODE
if ($code -ne 0) { exit $code }

Write-Host '=== tools/list ===' -ForegroundColor Cyan
& $invoke tools @($(if ($EnvFile) { @('-EnvFile', $EnvFile) }))
exit $LASTEXITCODE
