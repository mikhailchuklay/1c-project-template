#Requires -Version 5.1
<#
.SYNOPSIS
    Запускает MCP-инструмент s3_dev_probe (APA) для сквозного теста S3-тома.

.DESCRIPTION
    1. Читает ключи из build/dev-s3-credentials.local.env (gitignored).
    2. Вызывает tools/dev-standalone/Invoke-DataMcp.ps1 raw -Tool s3_dev_probe.
    3. Требует: ibsrv, OneMCP, загруженный APA-инструмент из ИнструментыS3Тестирование.xml,
       активное расширение Расш1КS3_S3ХранениеФайлов (safe-mode=no).

.EXAMPLE
    .\Invoke-S3DevProbe.ps1
    .\Invoke-S3DevProbe.ps1 -TomName "dev-files (https://storage.yandexcloud.net/dev-{PROJECT_SLUG}-s3)"
#>
[CmdletBinding()]
param(
    [string]$TomName = '',
    [switch]$NoCreateTom,
    [switch]$KeepProbeFile,
    [string]$CredentialsFile,
    [string]$EnvFile
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
if (-not $CredentialsFile) { $CredentialsFile = Join-Path $projectRoot 'build\dev-s3-credentials.local.env' }

if (-not (Test-Path $CredentialsFile)) {
    throw "Файл credentials не найден: $CredentialsFile. Создайте по docs/s3-yandex-setup.md"
}

$creds = Read-DotEnv -Path $CredentialsFile
$bucket = $creds['YC_BUCKET']
$endpoint = $creds['YC_ENDPOINT'].TrimEnd('/')
$storageUrl = "$endpoint/$bucket"

$argsObj = [ordered]@{
    tomname        = $TomName
    createtom      = if ($NoCreateTom) { 'false' } else { 'true' }
    storageurl     = $storageUrl
    prefix         = $creds['S3_PREFIX_DEV']
    prodprefix     = $creds['S3_PREFIX_DEV']
    region         = $creds['YC_REGION']
    accesskey      = $creds['YC_ACCESS_KEY_ID']
    secretkey      = $creds['YC_SECRET_ACCESS_KEY']
    cleanup        = if ($KeepProbeFile) { 'false' } else { 'true' }
}

$jsonArgs = ($argsObj | ConvertTo-Json -Compress)
$invokeScript = Join-Path $PSScriptRoot 'Invoke-DataMcp.ps1'

& $invokeScript -Action raw -Tool 's3_dev_probe' -Arguments $jsonArgs -EnvFile $EnvFile
exit $LASTEXITCODE
