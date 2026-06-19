#Requires -Version 5.1
<#
.SYNOPSIS
    Создаёт каталоги проекта по шаблону vanessa-bootstrap (как команда Platform Tools).

.DESCRIPTION
    Идempotent: существующие каталоги и README.md не перезаписываются.
    Манифест: tools/project-structure.json (тот же набор, что у 1c-platform-tools.dependencies.initializeProjectStructure).

.PARAMETER ProjectRoot
    Корень проекта. По умолчанию — родительский каталог tools/.

.EXAMPLE
    .\tools\init-project-structure.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot 'project-structure.json'

if (-not (Test-Path $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}

$items = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$createdDirs = 0
$createdReadmes = 0
$skippedReadmes = 0

foreach ($item in $items) {
    $dirPath = Join-Path $ProjectRoot ($item.path -replace '/', [IO.Path]::DirectorySeparatorChar)
    $readmePath = Join-Path $dirPath 'README.md'

    if (-not (Test-Path $dirPath)) {
        New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
        $createdDirs++
    } else {
        New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
    }

    if (-not (Test-Path $readmePath)) {
        $content = [string]$item.readmeContent
        if ($content.Length -gt 0) {
            [IO.File]::WriteAllText($readmePath, $content, [Text.UTF8Encoding]::new($false))
            $createdReadmes++
        }
    } else {
        $skippedReadmes++
    }
}

Write-Host "Project structure initialized in: $ProjectRoot"
Write-Host "  directories ensured: $($items.Count)"
Write-Host "  new directories:     $createdDirs"
Write-Host "  new README.md:       $createdReadmes"
Write-Host "  existing README.md:  $skippedReadmes (unchanged)"
