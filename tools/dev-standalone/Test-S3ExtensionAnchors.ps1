#Requires -Version 5.1
<#
.SYNOPSIS
    Сверяет #Удаление в перехватчиках S3 CFE с телами методов в живой ИБ.
#>
[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$IbDumpDir
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

function Get-MethodBodyFromBsl {
    param([string]$Path, [string]$MethodName)
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

function Get-DeleteAnchor {
    param([string]$Path, [string]$MethodName)
    $lines = Get-Content -Path $Path -Encoding UTF8
    $inBlock = $false
    $inMethod = $false
    $buf = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "&ИзменениеИКонтроль\(`"$([regex]::Escape($MethodName))`"\)") {
            $inMethod = $true
            continue
        }
        if (-not $inMethod) { continue }
        if ($lines[$i] -match '^\s*#Удаление\s*$') {
            $inBlock = $true
            continue
        }
        if ($inBlock -and $lines[$i] -match '^\s*#КонецУдаления\s*$') {
            break
        }
        if ($inBlock) { $buf.Add($lines[$i]) }
    }
    if ($buf.Count -eq 0) { throw "Delete anchor not found: $MethodName in $Path" }
    return (Normalize-BslText ($buf -join "`n"))
}

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $EnvFile) { $EnvFile = Join-Path $projectRoot '.dev.env' }
$dotenv = Read-DotEnv -Path $EnvFile

$cfeRoot = (Get-ChildItem -Path (Join-Path $projectRoot 'src\cfe') -Directory | Where-Object { $_.Name -like '*S3*' } | Select-Object -First 1).FullName
if (-not $IbDumpDir) { $IbDumpDir = Join-Path $projectRoot 'build\tmp-anchor-dump' }

if (-not (Test-Path (Join-Path $IbDumpDir 'Reports\ПроверкаЦелостностиТома\Ext\ManagerModule.bsl'))) {
    & (Join-Path $PSScriptRoot 'Sync-S3ExtensionAnchors.ps1') -IbDumpDir $IbDumpDir
}

$reportIb = Join-Path $IbDumpDir 'Reports\ПроверкаЦелостностиТома\Ext\ManagerModule.bsl'
$cmIb = Join-Path $IbDumpDir 'CommonModules\РаботаСФайламиВТомахСлужебный\Ext\Module.bsl'
$reportExt = Join-Path $cfeRoot 'Reports\ПроверкаЦелостностиТома\Ext\ManagerModule.bsl'
$cmExt = Join-Path $cfeRoot 'CommonModules\РаботаСФайламиВТомахСлужебный\Ext\Module.bsl'

$methods = @('ФайлыНаДиске','ПолныйПутьТома','ПолноеИмяФайлаВТоме','ДанныеФайла','СкопироватьФайл','УдалитьФайл','ЗаписатьДанныеФайлаВТом')
$failed = @()
foreach ($m in $methods) {
    $ibPath = if ($m -eq 'ФайлыНаДиске') { $reportIb } else { $cmIb }
    $extPath = if ($m -eq 'ФайлыНаДиске') { $reportExt } else { $cmExt }
    $body = Normalize-BslText (Get-MethodBodyFromBsl -Path $ibPath -MethodName $m)
    $anchor = Get-DeleteAnchor -Path $extPath -MethodName $m
    $ok = ($anchor -eq $body)
    Write-Host ("{0,-28} anchor==IB: {1}" -f $m, $ok)
    if (-not $ok) { $failed += $m }
}

if ($failed.Count -gt 0) {
    throw "Anchor mismatch for: $($failed -join ', ')"
}

Write-Host 'Anchor test OK' -ForegroundColor Green
