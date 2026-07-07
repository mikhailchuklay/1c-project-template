#Requires -Version 5.1
param(
    [string]$Url = 'http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp',
    [int]$Baseline = 69315,
    [string]$ProgressFile = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\size-analysis-block4-progress.txt'),
    [string]$DeleteLog = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\size-analysis-block4-delete-log.txt'),
    [string]$LockFile = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\size-analysis-block4-delete.lock')
)

[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
$base = Join-Path $PSScriptRoot 'Invoke-DataMcp.ps1'
$countBsl = Join-Path $PSScriptRoot 'Count-IncomingMail.bsl'
$code = (Get-Content -Path $countBsl -Raw -Encoding UTF8).Trim()

$left = $null
try {
    $out = & $base code -Url $Url -Text $code 2>&1 | Out-String
    if ($out -match '(\d[\d\s\u00A0]+)') { $left = [int]($Matches[1] -replace '\s','') }
}
catch { $left = -1 }

$purgePid = if (Test-Path $LockFile) { (Get-Content $LockFile -Raw).Trim() } else { '' }
$purgeAlive = $false
if ($purgePid -match '^\d+$') { $purgeAlive = $null -ne (Get-Process -Id ([int]$purgePid) -ErrorAction SilentlyContinue) }

$lastBatch = ''
if (Test-Path $DeleteLog) {
    $lastBatch = Get-Content $DeleteLog -Encoding UTF8 | Where-Object { $_ -match 'deleted=\d+;errors=\d+;left=' } | Select-Object -Last 1
}

$deleted = if ($left -ge 0) { $Baseline - $left } else { 0 }
$pct = if ($left -ge 0 -and $Baseline -gt 0) { [math]::Round(100.0 * $deleted / $Baseline, 1) } else { 0 }
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$line = "$ts | left=$left | deleted=$deleted ($pct%) | purge_pid=$purgePid alive=$purgeAlive | $lastBatch"

Add-Content -Path $ProgressFile -Value $line -Encoding UTF8
Write-Output $line
