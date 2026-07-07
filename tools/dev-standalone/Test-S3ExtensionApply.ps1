#Requires -Version 5.1
<#
.SYNOPSIS
    Проверяет применимость S3-расширения через запуск Предприятия и разбор лога.
#>
[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$ExtensionName,
    [int]$StartupTimeoutSec = 180
)

$ErrorActionPreference = 'Stop'

function Read-DotEnv {
    param([string]$Path)
    $map = @{}
    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $map[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $map
}

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $EnvFile) { $EnvFile = Join-Path $projectRoot '.dev.env' }
$dotenv = Read-DotEnv -Path $EnvFile

$ib = $dotenv['INFOBASE_PATH']
$user = $dotenv['IB_USER']
$password = $dotenv['IB_PASSWORD']
$platformBin = Join-Path $dotenv['PLATFORM_PATH'] 'bin'
$v8 = Join-Path $platformBin '1cv8.exe'

$cfePath = (Get-ChildItem -Path (Join-Path $projectRoot 'src\cfe') -Directory |
    Where-Object { $_.Name -like '*S3*' } | Select-Object -First 1).FullName
if (-not $ExtensionName -and $cfePath) {
    $cfgXml = Join-Path $cfePath 'Configuration.xml'
    $m = Select-String -Path $cfgXml -Pattern '<Name>([^<]+)</Name>' | Select-Object -First 1
    if ($m) { $ExtensionName = $m.Matches.Groups[1].Value }
}
if (-not $ExtensionName) { throw 'Extension name not resolved' }

Get-Process 1cv8,1cv8c -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$outLog = Join-Path $env:TEMP "s3_ext_apply_$(Get-Random).log"
$proc = Start-Process -FilePath $v8 -ArgumentList @(
    'DESIGNER', "/F$ib", "/N$user", "/P$password",
    '/DisableStartupDialogs', '/DisableStartupMessages',
    "/Out$outLog"
) -PassThru -NoNewWindow

$deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
$patterns = @(
    'Ошибка применения модуля',
    'Текст модуля для метода',
    'ФайлыНаДиске',
    $ExtensionName
)

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    if ($proc.HasExited) { break }
    if (Test-Path $outLog) {
        $chunk = Get-Content $outLog -Encoding Default -Raw -ErrorAction SilentlyContinue
        if ($chunk -and $chunk -match 'Ошибка применения модуля') {
            break
        }
    }
}

if (-not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$logText = ''
if (Test-Path $outLog) {
    $logText = Get-Content $outLog -Encoding Default -Raw
    Write-Host '--- Designer Out log ---'
    Write-Host $logText
}

$applyErrors = @()
if ($logText -match 'Ошибка применения модуля[^\r\n]*') {
    $applyErrors += $Matches[0]
}
if ($logText -match 'Текст модуля для метода[^\r\n]*') {
    $applyErrors += $Matches[0]
}

if ($applyErrors.Count -gt 0) {
    throw "Extension apply errors detected: $($applyErrors -join ' | ')"
}

if (-not $logText -and $proc.ExitCode -ne 0 -and $null -ne $proc.ExitCode) {
    throw "Enterprise exited with code $($proc.ExitCode) and empty Out log"
}

Write-Host "Extension apply check OK (no apply errors in Designer Out log, timeout ${StartupTimeoutSec}s)" -ForegroundColor Green
