#Requires -Version 5.1
<#
.SYNOPSIS
    Gate проверки расширения Расш1КS3_S3ХранениеФайлов: validate → load → functional test.

.DESCRIPTION
    1. Rewrite-S3ExtensionVmesto
    2. cfe-validate
    3. Stop ibsrv + 1cv8*, LoadConfigFromFiles + UpdateDBCfg
    4. CheckCanApplyConfigurationExtensions
    5. ibcmd extension info
    6. start ibsrv, Enable-S3Extension, Install APA tools
    7. Invoke-S3FunctionalTest (tasks 9.2–9.5)
#>
[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$ExtensionName,
    [string]$ExtensionPath,
    [switch]$SkipFunctionalTest
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

function Stop-DevProcesses {
    Get-Process ibsrv,1cv8,1cv8c -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $EnvFile) { $EnvFile = Join-Path $projectRoot '.dev.env' }
$dotenv = Read-DotEnv -Path $EnvFile

$ib = $dotenv['INFOBASE_PATH']
$user = $dotenv['IB_USER']
$password = $dotenv['IB_PASSWORD']
$platformBin = Join-Path $dotenv['PLATFORM_PATH'] 'bin'
$ibcmd = Join-Path $platformBin 'ibcmd.exe'
$cfePath = if ($ExtensionPath) {
    $ExtensionPath
} else {
    (Get-ChildItem -Path (Join-Path $projectRoot 'src\cfe') -Directory |
        Where-Object { $_.Name -like '*S3*' } |
        Select-Object -First 1).FullName
}
if (-not $cfePath -or -not (Test-Path $cfePath)) {
    throw "S3 extension path not found under src/cfe"
}
$cfgXmlPath = Join-Path $cfePath 'Configuration.xml'
if (-not $ExtensionName -and (Test-Path $cfgXmlPath)) {
    $nameMatch = Select-String -Path $cfgXmlPath -Pattern '<Name>([^<]+)</Name>' -AllMatches |
        ForEach-Object { $_.Matches } | Select-Object -First 1
    if ($nameMatch) { $ExtensionName = $nameMatch.Groups[1].Value }
}
if (-not $ExtensionName) { throw 'Extension name not resolved' }
$cfeValidate = Join-Path $projectRoot '.cursor/skills/1c-metadata-manage/tools/1c-cfe-manage/scripts/cfe-validate.ps1'
$dbLoad = Join-Path $projectRoot '.cursor/skills/1c-metadata-manage/tools/1c-db-ops/scripts/db-load-xml.ps1'

Stop-DevProcesses

$rewriteScript = Join-Path $PSScriptRoot 'Rewrite-S3ExtensionVmesto.ps1'
$canApplyTest = Join-Path $PSScriptRoot 'Test-S3ExtensionCanApply.ps1'
$startScript = Join-Path $PSScriptRoot 'start.ps1'
$enableScript = Join-Path $PSScriptRoot 'Enable-S3Extension.ps1'
$installApa = Join-Path $PSScriptRoot 'Install-S3ApaTool.ps1'
$functionalTest = Join-Path $PSScriptRoot 'Invoke-S3FunctionalTest.ps1'

Write-Host '=== 1/7 Rewrite &Вместо interceptors ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $rewriteScript
if ($LASTEXITCODE -ne 0) { throw "Rewrite-S3ExtensionVmesto failed: $LASTEXITCODE" }

Write-Host '=== 2/7 cfe-validate ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $cfeValidate -ExtensionPath $cfePath
if ($LASTEXITCODE -ne 0) { throw "cfe-validate failed: $LASTEXITCODE" }

Write-Host '=== 3/7 LoadConfigFromFiles + UpdateDBCfg ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $dbLoad `
    -V8Path $platformBin `
    -InfoBasePath $ib `
    -UserName $user `
    -Password $password `
    -ConfigDir $cfePath `
    -Extension $ExtensionName `
    -UpdateDB
if ($LASTEXITCODE -ne 0) { throw "db-load-xml failed: $LASTEXITCODE" }

Write-Host '=== 4/7 CheckCanApplyConfigurationExtensions ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $canApplyTest -EnvFile $EnvFile -ExtensionName $ExtensionName
if ($LASTEXITCODE -ne 0) { throw "Test-S3ExtensionCanApply failed: $LASTEXITCODE" }

Write-Host '=== 5/7 ibcmd extension info ===' -ForegroundColor Cyan
& $ibcmd infobase config extension info --db-path=$ib --name=$ExtensionName --user=$user --password=$password
if ($LASTEXITCODE -ne 0) { throw "extension info failed: $LASTEXITCODE" }

if ($SkipFunctionalTest) {
    Write-Host '=== GATE OK (functional test skipped) ===' -ForegroundColor Green
    exit 0
}

Write-Host '=== 6/7 ibsrv + extension active + APA tools ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $startScript
& powershell -NoProfile -ExecutionPolicy Bypass -File $enableScript -EnvFile $EnvFile -ExtensionName $ExtensionName
if ($LASTEXITCODE -ne 0) { throw "Enable-S3Extension failed: $LASTEXITCODE" }
& powershell -NoProfile -ExecutionPolicy Bypass -File $installApa -EnvFile $EnvFile
if ($LASTEXITCODE -ne 0) { throw "Install-S3ApaTool failed: $LASTEXITCODE" }

Write-Host '=== 7/7 S3 functional test (9.2–9.5) ===' -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $functionalTest -EnvFile $EnvFile
if ($LASTEXITCODE -ne 0) { throw "Invoke-S3FunctionalTest failed: $LASTEXITCODE" }

Write-Host '=== GATE OK ===' -ForegroundColor Green
