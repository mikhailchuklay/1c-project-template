#Requires -Version 5.1
Get-Process ibsrv -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "ibsrv остановлен"
