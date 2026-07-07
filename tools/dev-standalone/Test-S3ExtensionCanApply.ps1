#Requires -Version 5.1
<#
.SYNOPSIS
    Проверка возможности применения S3-расширения (Designer /CheckCanApplyConfigurationExtensions).
#>
[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$ExtensionName
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
$v8 = Join-Path (Join-Path $dotenv['PLATFORM_PATH'] 'bin') '1cv8.exe'

if (-not $ExtensionName) {
    $cfePath = (Get-ChildItem -Path (Join-Path $projectRoot 'src\cfe') -Directory |
        Where-Object { $_.Name -like '*S3*' } | Select-Object -First 1).FullName
    $cfgXml = Join-Path $cfePath 'Configuration.xml'
    $m = Select-String -Path $cfgXml -Pattern '<Name>([^<]+)</Name>' | Select-Object -First 1
    if ($m) { $ExtensionName = $m.Matches.Groups[1].Value }
}
if (-not $ExtensionName) { throw 'Extension name not resolved' }

Get-Process 1cv8,1cv8c -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$log = Join-Path $env:TEMP "s3_canapply_$(Get-Random).log"
$p = Start-Process -FilePath $v8 -ArgumentList @(
    'DESIGNER', "/F$ib", "/N$user", "/P$password",
    '/CheckCanApplyConfigurationExtensions', "-Extension$ExtensionName",
    "/Out$log", '/DisableStartupDialogs'
) -Wait -PassThru -NoNewWindow

$logText = ''
if (Test-Path $log) {
    $logText = Get-Content $log -Encoding Default -Raw
    Write-Host $logText
}

if ($p.ExitCode -ne 0) {
    throw "CheckCanApplyConfigurationExtensions failed: exit $($p.ExitCode)"
}

Write-Host 'CheckCanApply OK' -ForegroundColor Green
