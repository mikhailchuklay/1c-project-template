#Requires -Version 5.1
param(
    [int]$BatchSize = 100,
    [string]$ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
)

$lockFile = Join-Path $ProjectRoot 'build\size-analysis-block4-delete.lock'
$purgeScript = Join-Path $PSScriptRoot 'Remove-IncomingMailProd.ps1'

if (Test-Path $lockFile) {
    $lockPid = (Get-Content $lockFile -Raw).Trim()
    if ($lockPid -match '^\d+$' -and (Get-Process -Id ([int]$lockPid) -ErrorAction SilentlyContinue)) {
        Write-Output "already_running pid=$lockPid"
        exit 0
    }
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*Remove-IncomingMailProd*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$cmd = "& '$purgeScript' -BatchSize $BatchSize"
Start-Process -FilePath 'powershell.exe' `
    -WorkingDirectory $ProjectRoot `
    -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd `
    -WindowStyle Hidden | Out-Null

Start-Sleep -Seconds 25
$lockPid = if (Test-Path $lockFile) { (Get-Content $lockFile -Raw).Trim() } else { '' }
$alive = $false
if ($lockPid -match '^\d+$') {
    $alive = $null -ne (Get-Process -Id ([int]$lockPid) -ErrorAction SilentlyContinue)
}
if (-not $alive) {
    Write-Error "purge not running after 25s lock=$lockPid"
    exit 1
}
Write-Output "started pid=$lockPid"
