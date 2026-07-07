#Requires -Version 5.1
<#
.SYNOPSIS
    Подключает расширение Расш1КS3_S3ХранениеФайлов и отключает безопасный режим (DEV ibsrv).

.DESCRIPTION
    Требует запущенный ibsrv (tools/dev-standalone/start.ps1).
    Читает IB_USER / IB_PASSWORD из .dev.env.
#>
[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$ExtensionName = 'Расш1КS3_S3ХранениеФайлов'
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

if (-not $EnvFile) {
    $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $EnvFile = Join-Path $projectRoot '.dev.env'
}
$dotenv = Read-DotEnv -Path $EnvFile
$user = $dotenv['IB_USER']
$password = $dotenv['IB_PASSWORD']
$ibcmd = Join-Path $dotenv['PLATFORM_PATH'] 'bin\ibcmd.exe'

$ibsrv = Get-Process ibsrv -ErrorAction SilentlyContinue
if (-not $ibsrv) {
    throw 'ibsrv is not running. Run tools/dev-standalone/start.ps1 first.'
}

Write-Host "ibsrv PID=$($ibsrv.Id); extension=$ExtensionName" -ForegroundColor DarkGray

& $ibcmd --pid=$ibsrv.Id infobase config extension update `
    --name=$ExtensionName `
    --active=yes `
    --safe-mode=no `
    --unsafe-action-protection=no `
    --user=$user `
    --password=$password

& $ibcmd --pid=$ibsrv.Id infobase config extension info `
    --name=$ExtensionName `
    --user=$user `
    --password=$password
