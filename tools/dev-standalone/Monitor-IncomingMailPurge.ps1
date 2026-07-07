#Requires -Version 5.1
<#
.SYNOPSIS
    Monitor incoming-mail purge: report every N minutes, auto-restart if dead.
#>
param(
    [int]$IntervalMinutes = 30,
    [int]$BatchSize = 100,
    [string]$ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

$lockFile = Join-Path $ProjectRoot 'build\size-analysis-block4-delete.lock'
$monitorLock = Join-Path $ProjectRoot 'build\size-analysis-block4-monitor.lock'
$progressFile = Join-Path $ProjectRoot 'build\size-analysis-block4-progress.txt'
$startScript = Join-Path $PSScriptRoot 'Start-IncomingMailPurgeDetached.ps1'
$reportScript = Join-Path $PSScriptRoot 'Report-IncomingMailPurgeProgress.ps1'

if (Test-Path $monitorLock) {
    $mp = (Get-Content $monitorLock -Raw).Trim()
    if ($mp -match '^\d+$' -and (Get-Process -Id ([int]$mp) -ErrorAction SilentlyContinue)) {
        Write-Output "monitor_already_running pid=$mp"
        exit 0
    }
    Remove-Item $monitorLock -Force -ErrorAction SilentlyContinue
}
$PID | Set-Content -Path $monitorLock -Encoding ASCII

function Test-PurgeAlive {
    if (-not (Test-Path $lockFile)) { return $false }
    $p = (Get-Content $lockFile -Raw).Trim()
    if ($p -notmatch '^\d+$') { return $false }
    return $null -ne (Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue)
}

try {
    Add-Content -Path $progressFile -Value "=== monitor started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') interval=${IntervalMinutes}m auto_restart=true ===" -Encoding UTF8

    while ($true) {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        if (-not (Test-PurgeAlive)) {
            Add-Content -Path $progressFile -Value "$ts | ACTION restart purge (not alive)" -Encoding UTF8
            Write-Output "$ts RESTART purge"
            try {
                $startOut = & $startScript -BatchSize $BatchSize 2>&1 | Out-String
                Add-Content -Path $progressFile -Value "$ts | restart_result $startOut" -Encoding UTF8
                Write-Output $startOut.Trim()
            }
            catch {
                Add-Content -Path $progressFile -Value "$ts | restart_failed $($_.Exception.Message)" -Encoding UTF8
                Write-Output "restart_failed $($_.Exception.Message)"
            }
        }

        try {
            $line = & $reportScript 2>&1 | Where-Object { $_ -match 'left=' } | Select-Object -Last 1
            if ($line) { Write-Output $line }
        }
        catch {
            Write-Output "$ts report_failed $($_.Exception.Message)"
        }

        Write-Output "AGENT_LOOP_TICK_mailpurge_30m"
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}
finally {
    Remove-Item $monitorLock -Force -ErrorAction SilentlyContinue
}
