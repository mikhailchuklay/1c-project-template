#Requires -Version 5.1
<#
.SYNOPSIS
    Удаляет битый дубль S3-расширения (hash AAAA...) из DEV ИБ.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$py = Join-Path $PSScriptRoot 'remove_s3_duplicate.py'

Get-Process 1cv8,1cv8c,ibsrv -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

& python $py
exit $LASTEXITCODE
