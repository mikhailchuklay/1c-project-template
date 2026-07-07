#Requires -Version 5.1
<#
.SYNOPSIS
    Sync #Udalenie anchors in S3 CFE interceptors from live IB method bodies.
#>
[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$IbDumpDir,
    [switch]$SkipDump
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

function Get-MethodBodyFromBsl {
    param([string]$Path, [string]$MethodName)
    if (-not (Test-Path $Path)) { throw "Module not found: $Path" }
    $lines = Get-Content -Path $Path -Encoding UTF8
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^(Функция|Процедура)\s+$([regex]::Escape($MethodName))\(") {
            $start = $i + 1
            break
        }
    }
    if ($start -lt 0) { throw "Method not found: $MethodName in $Path" }
    $end = -1
    for ($j = $start; $j -lt $lines.Count; $j++) {
        if ($lines[$j] -match '^Конец(Функции|Процедуры)') { $end = $j - 1; break }
    }
    return ($lines[$start..$end] -join "`n")
}

function Normalize-BslText {
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*$' -and $i -gt 0 -and $i + 1 -lt $lines.Count -and
            $lines[$i - 1] -notmatch '^\s*$' -and $lines[$i + 1] -notmatch '^\s*$') {
            continue
        }
        $out.Add($lines[$i])
    }
    return ($out -join "`n").TrimEnd("`r", "`n")
}

function Get-InsertBlock {
    param([string]$Path, [string]$MethodName)
    $raw = Get-Content -Path $Path -Raw -Encoding UTF8
    $pattern = "(?s)&ИзменениеИКонтроль\(`"$([regex]::Escape($MethodName))`"\).*?#Вставка\r?\n(.*?)\r?\n\s*#КонецВставки"
    if ($raw -match $pattern) {
        return (Normalize-BslText $Matches[1])
    }
    throw "Insert block not found for $MethodName in $Path"
}

$MethodSignatures = @{
    'ПолныйПутьТома' = '(Том)'
    'ПолноеИмяФайлаВТоме' = '(СвойстваФайла, ДатаДляРазмещенияВТоме = Неопределено)'
    'ДанныеФайла' = '(ПрисоединенныйФайл, Знач ВызыватьИсключение = Истина)'
    'СкопироватьФайл' = '(ПрисоединенныйФайл, ПутьФайлаПриемник)'
    'УдалитьФайл' = '(ПутьКФайлу)'
    'ЗаписатьДанныеФайлаВТом' = '(ПрисоединенныйФайл, ДвоичныеДанныеИлиПуть)'
    'ФайлыНаДиске' = '(Том)'
}

function Set-InterceptorFile {
    param(
        [string]$TargetPath,
        [string]$MethodName,
        [string]$ExtFuncName,
        [string]$InsertBlock,
        [string]$DeleteBody,
        [string]$Kind
    )
    $endKw = if ($Kind -eq 'Function') { 'КонецФункции' } else { 'КонецПроцедуры' }
    $startKw = if ($Kind -eq 'Function') { 'Функция' } else { 'Процедура' }
    $sig = $MethodSignatures[$MethodName]
    if (-not $sig) { throw "No signature for $MethodName" }
    $content = @"
&ИзменениеИКонтроль("$MethodName")
$startKw $ExtFuncName$sig
	
	#Удаление
$DeleteBody
	#КонецУдаления
	
	#Вставка
$InsertBlock
	#КонецВставки
	
	ПродолжитьВызов();
	
$endKw

"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($TargetPath, $content, $utf8NoBom)
}

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $EnvFile) { $EnvFile = Join-Path $projectRoot '.dev.env' }
$dotenv = Read-DotEnv -Path $EnvFile
$ib = $dotenv['INFOBASE_PATH']
$platformBin = Join-Path $dotenv['PLATFORM_PATH'] 'bin'
$user = $dotenv['IB_USER']
$password = $dotenv['IB_PASSWORD']

$cfeRoot = (Get-ChildItem -Path (Join-Path $projectRoot 'src\cfe') -Directory | Where-Object { $_.Name -like '*S3*' } | Select-Object -First 1).FullName
if (-not $cfeRoot) { throw 'S3 CFE not found' }

if (-not $IbDumpDir) {
    $IbDumpDir = Join-Path $projectRoot 'build\tmp-anchor-dump'
}
if (-not $SkipDump) {
    Get-Process 1cv8,1cv8c -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (Test-Path $IbDumpDir) { Remove-Item $IbDumpDir -Recurse -Force }
    New-Item -ItemType Directory -Path $IbDumpDir | Out-Null
    $dumpScript = Join-Path $projectRoot '.cursor\skills\1c-metadata-manage\tools\1c-db-ops\scripts\db-dump-xml.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $dumpScript `
        -V8Path $platformBin -InfoBasePath $ib -UserName $user -Password $password `
        -ConfigDir $IbDumpDir -Mode Partial `
        -Objects 'Отчет.ПроверкаЦелостностиТома,ОбщийМодуль.РаботаСФайламиВТомахСлужебный'
    if ($LASTEXITCODE -ne 0) { throw "IB dump failed: $LASTEXITCODE" }
}

$reportIb = Join-Path $IbDumpDir 'Reports\ПроверкаЦелостностиТома\Ext\ManagerModule.bsl'
$cmIb = Join-Path $IbDumpDir 'CommonModules\РаботаСФайламиВТомахСлужебный\Ext\Module.bsl'

$reportExt = Join-Path $cfeRoot 'Reports\ПроверкаЦелостностиТома\Ext\ManagerModule.bsl'
$cmExt = Join-Path $cfeRoot 'CommonModules\РаботаСФайламиВТомахСлужебный\Ext\Module.bsl'

$cmMethods = @(
    @{ Name = 'ПолныйПутьТома'; Ext = 'Расш1КS3_ПолныйПутьТома'; Kind = 'Function' },
    @{ Name = 'ПолноеИмяФайлаВТоме'; Ext = 'Расш1КS3_ПолноеИмяФайлаВТоме'; Kind = 'Function' },
    @{ Name = 'ДанныеФайла'; Ext = 'Расш1КS3_ДанныеФайла'; Kind = 'Function' },
    @{ Name = 'СкопироватьФайл'; Ext = 'Расш1КS3_СкопироватьФайл'; Kind = 'Procedure' },
    @{ Name = 'УдалитьФайл'; Ext = 'Расш1КS3_УдалитьФайл'; Kind = 'Function' },
    @{ Name = 'ЗаписатьДанныеФайлаВТом'; Ext = 'Расш1КS3_ЗаписатьДанныеФайлаВТом'; Kind = 'Procedure' }
)

$cmParts = New-Object System.Collections.Generic.List[string]
$cmParts.Add('')
$cmParts.Add('#Область S3Перехваты')
$cmParts.Add('')

foreach ($m in $cmMethods) {
    $body = Get-MethodBodyFromBsl -Path $cmIb -MethodName $m.Name
    $insert = Get-InsertBlock -Path $cmExt -MethodName $m.Name
    $tmp = Join-Path $env:TEMP "s3-intercept-$($m.Name).bsl"
    Set-InterceptorFile -TargetPath $tmp -MethodName $m.Name -ExtFuncName $m.Ext -InsertBlock $insert -DeleteBody $body -Kind $m.Kind
    $cmParts.Add((Get-Content $tmp -Raw -Encoding UTF8).TrimEnd())
    $cmParts.Add('')
}

$cmParts.Add('#КонецОбласти')
$cmParts.Add('')

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($cmExt, ($cmParts -join "`n"), $utf8NoBom)

$reportBody = Get-MethodBodyFromBsl -Path $reportIb -MethodName 'ФайлыНаДиске'
$reportInsert = Get-InsertBlock -Path $reportExt -MethodName 'ФайлыНаДиске'
$reportTmp = Join-Path $env:TEMP 's3-intercept-report.bsl'
Set-InterceptorFile -TargetPath $reportTmp -MethodName 'ФайлыНаДиске' -ExtFuncName 'Расш1КS3_ФайлыНаДиске' -InsertBlock $reportInsert -DeleteBody $reportBody -Kind 'Function'
$reportContent = @"
#Если Сервер Или ТолстыйКлиентОбычноеПриложение Или ВнешнееСоединение Тогда

$((Get-Content $reportTmp -Raw -Encoding UTF8).TrimEnd())

#КонецЕсли
"@
[System.IO.File]::WriteAllText($reportExt, $reportContent, $utf8NoBom)

Write-Host "Anchors synced from IB dump: $IbDumpDir" -ForegroundColor Green
