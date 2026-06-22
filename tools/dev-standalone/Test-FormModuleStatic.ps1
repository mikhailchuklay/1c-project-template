#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string]$FormModulePath,

    [string[]]$ForbiddenPatterns = @(
        'RadioButton'  # use ВидПоляФормы.ПолеПереключателя, not RadioButton
    )
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $FormModulePath)) {
    throw "Form module not found: $FormModulePath"
}

$content = Get-Content -LiteralPath $FormModulePath -Raw

foreach ($pattern in $ForbiddenPatterns) {
    if ($content -match $pattern) {
        Write-Host "Form module static check FAILED: forbidden pattern '$pattern' in $FormModulePath" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Form module static check OK: $FormModulePath" -ForegroundColor Green
exit 0
