#Requires -Version 5.1
[CmdletBinding()]
param(
    [int]$BatchSize = 100,
    [int]$MaxRounds = 0,
    [string]$Url = 'http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp',
    [string]$LogFile = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\size-analysis-block4-delete-log.txt')
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
$base = Join-Path $PSScriptRoot 'Invoke-DataMcp.ps1'
$bslTemplate = Join-Path $PSScriptRoot 'Remove-IncomingMailProd.bsl'
$lockFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\size-analysis-block4-delete.lock'
$mutexName = 'Global\1commerce-block4-incoming-mail-purge'
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
$mutexAcquired = $false

try {
    $mutexAcquired = $mutex.WaitOne(0, $false)
    if (-not $mutexAcquired) {
        Write-Host 'Already running (mutex)'
        exit 0
    }

    if (Test-Path $lockFile) {
        $lockPid = Get-Content $lockFile -ErrorAction SilentlyContinue
        if ($lockPid -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) {
            Write-Host "Already running PID=$lockPid"
            exit 0
        }
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
    $PID | Set-Content -Path $lockFile -Encoding ASCII
$batchCode = (Get-Content -Path $bslTemplate -Raw -Encoding UTF8).Replace('__BATCH__', [string]$BatchSize).Trim()

Add-Content -Path $LogFile -Value "=== resume $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') batch=$BatchSize ===" -Encoding UTF8

$round = 0
while ($true) {
    $round++
    if ($MaxRounds -gt 0 -and $round -gt $MaxRounds) {
        Add-Content -Path $LogFile -Value "$(Get-Date -Format 'HH:mm:ss') STOP maxRounds=$MaxRounds" -Encoding UTF8
        break
    }

    $ts = Get-Date -Format 'HH:mm:ss'
    try {
        $lines = & $base code -Url $Url -Text $batchCode 2>&1
        $raw = ($lines | Out-String)
    }
    catch {
        Add-Content -Path $LogFile -Value "$ts round=$round EXCEPTION $($_.Exception.Message)" -Encoding UTF8
        Start-Sleep -Seconds 30
        continue
    }

    $resultLine = ($lines | Where-Object { $_ -match 'deleted=\d+;.*errors=\d+;left=' } | Select-Object -Last 1)
    if (-not $resultLine) { $resultLine = ($raw -split "`n" | Where-Object { $_ -match 'deleted=' } | Select-Object -Last 1) }

    if ($resultLine -match 'deleted=(\d+);(?:skipped=(\d+);)?errors=(\d+);left=([\d\s\u00A0]+)') {
        $left = [int]($Matches[4] -replace '\s','')
        $skipped = if ($Matches[2]) { $Matches[2] } else { '0' }
        $line = "$ts round=$round deleted=$($Matches[1]);skipped=$skipped;errors=$($Matches[3]);left=$left"
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
        Write-Host $line
        if ($left -le 0) {
            Add-Content -Path $LogFile -Value "$(Get-Date -Format 'HH:mm:ss') DONE left=$left deletedInRound=$($Matches[1])" -Encoding UTF8
            break
        }
        if ([int]$Matches[1] -eq 0 -and [int]$Matches[3] -gt 0) {
            Add-Content -Path $LogFile -Value "$(Get-Date -Format 'HH:mm:ss') WARN round=$round all_failed errors=$($Matches[3]) left=$left" -Encoding UTF8
            Start-Sleep -Seconds 60
        }
    }
    elseif ($raw -match 'Ошибка|Exception') {
        Add-Content -Path $LogFile -Value "$ts round=$round ERR $raw" -Encoding UTF8
        Start-Sleep -Seconds 30
    }
    else {
        Add-Content -Path $LogFile -Value "$ts round=$round RAW $raw" -Encoding UTF8
    }

    Start-Sleep -Seconds 2
}
}
finally {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    if ($mutexAcquired) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
