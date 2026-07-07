#Requires -Version 5.1
param(
    [string]$Url = 'http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp'
)
$base = Join-Path $PSScriptRoot 'Invoke-DataMcp.ps1'
$bsl = Join-Path $PSScriptRoot 'Get-IncomingMailServerBackgroundJob.bsl'
& $base code -Url $Url -Text (Get-Content -Path $bsl -Raw -Encoding UTF8).Trim()
