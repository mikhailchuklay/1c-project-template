#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$TomName = "Облако S3 DEV",
    [switch]$NoCreateTom,
    [switch]$KeepProbeFile,
    [switch]$SkipMigration,
    [int]$MigrationLimit = 10,
    [string]$CredentialsFile,
    [string]$EnvFile
)
$ErrorActionPreference = "Stop"
function Read-DotEnv { param([string]$Path)
  $map = @{}; foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
    $t = $line.Trim(); if ($t -eq "" -or $t.StartsWith("#")) { continue }
    $i = $t.IndexOf("="); if ($i -lt 1) { continue }
    $map[$t.Substring(0,$i).Trim()] = $t.Substring($i+1).Trim() }
  return $map }
function Escape-BslString([string]$Value) { if ($null -eq $Value) { return "" }; return ($Value -replace "\\","\\\\") -replace '"','""' }
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $EnvFile) { $EnvFile = Join-Path $projectRoot ".dev.env" }
if (-not $CredentialsFile) { $CredentialsFile = Join-Path $projectRoot "build\dev-s3-credentials.local.env" }
if (-not (Test-Path $CredentialsFile)) { throw "Credentials not found: $CredentialsFile" }
$creds = Read-DotEnv -Path $CredentialsFile
$endpoint = $creds["YC_ENDPOINT"].TrimEnd("/")
$storageUrl = "$endpoint/$($creds["YC_BUCKET"])"
$createTom = if ($NoCreateTom) { "Ложь" } else { "Истина" }
$cleanup = if ($KeepProbeFile) { "Ложь" } else { "Истина" }
$doMigration = if ($SkipMigration) { "Ложь" } else { "Истина" }
$bsl = @"
Результат = "ошибок нет";
Попытка
	Модуль = ОбщегоНазначения.ОбщийМодуль("Расш1КS3_ТестированиеMCP");
	ПараметрыТеста = Новый Структура;
	ПараметрыТеста.Вставить("ИмяТома", "$(Escape-BslString $TomName)");
	ПараметрыТеста.Вставить("НаименованиеТома", "$(Escape-BslString $TomName)");
	ПараметрыТеста.Вставить("СоздатьТомЕслиНет", $createTom);
	ПараметрыТеста.Вставить("АдресХранилища", "$(Escape-BslString $storageUrl)");
	ПараметрыТеста.Вставить("ИмяПрефикса", "$(Escape-BslString $creds["S3_PREFIX_DEV"])");
	ПараметрыТеста.Вставить("ИмяПрефиксаРабочаяБаза", "$(Escape-BslString $creds["S3_PREFIX_DEV"])");
	ПараметрыТеста.Вставить("Регион", "$(Escape-BslString $creds["YC_REGION"])");
	ПараметрыТеста.Вставить("ИдентификаторКлючаДоступа", "$(Escape-BslString $creds["YC_ACCESS_KEY_ID"])");
	ПараметрыТеста.Вставить("СекретныйКлюч", "$(Escape-BslString $creds["YC_SECRET_ACCESS_KEY"])");
	ПараметрыТеста.Вставить("УдалятьТестовыйФайл", $cleanup);
	ПараметрыТеста.Вставить("ЛимитПереносаФайлов", $MigrationLimit);
	ПараметрыТеста.Вставить("ВыполнятьПеренос", $doMigration);
	Результат = Модуль.ВыполнитьФункциональныйТестS3(ПараметрыТеста);
Исключение
	Результат = ОписаниеОшибки();
КонецПопытки;
"@
$runner = Join-Path $projectRoot "build\s3_functional_test_runner.bsl"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($runner, $bsl, $utf8Bom)
$oneLine = (($bsl -replace "`r","" -replace "`n"," ") -replace "\s+"," ").Trim()
[System.IO.File]::WriteAllText($runner, $oneLine, (New-Object System.Text.UTF8Encoding($false)))
$invoke = Join-Path $PSScriptRoot "Invoke-DataMcp.ps1"
$output = & $invoke -Action code -File $runner 2>&1 | Out-String
Write-Host $output
if ($output -match "FAIL:") { Write-Host "=== FUNCTIONAL TEST FAILED ===" -ForegroundColor Red; exit 1 }
if ($output -notmatch "=== PASS: S3 functional test") { Write-Host "=== FUNCTIONAL TEST: no PASS marker ===" -ForegroundColor Red; exit 1 }
Write-Host "=== FUNCTIONAL TEST PASSED ===" -ForegroundColor Green
exit 0