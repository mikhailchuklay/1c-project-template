#Requires -Version 5.1
<#
.SYNOPSIS
    Экспорт шаблона проекта 1С из текущего репозитория (без исходников и секретов).

.PARAMETER SourceRoot
    Корень исходного проекта (по умолчанию — родитель tools/).

.PARAMETER TargetRoot
    Каталог шаблона (по умолчанию D:\infobases-files\1c-project-template).

.PARAMETER Force
    Удалить TargetRoot перед сборкой, если каталог уже существует.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = '',
    [string]$TargetRoot = 'D:\infobases-files\1c-project-template',
    [switch]$Force
)

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $SourceRoot = Split-Path -Parent $SourceRoot
}

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Copy-Tree {
    param(
        [string]$RelativePath,
        [string[]]$ExcludeDirs = @(),
        [string[]]$ExcludeFiles = @()
    )

    $src = Join-Path $SourceRoot $RelativePath
    $dst = Join-Path $TargetRoot $RelativePath

    if (-not (Test-Path $src)) {
        Write-Warning "Skip missing: $RelativePath"
        return
    }

    $item = Get-Item $src
    if ($item.PSIsContainer) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Get-ChildItem -Path $src -Force | ForEach-Object {
            $rel = Join-Path $RelativePath $_.Name
            if ($ExcludeDirs -contains $_.Name) { return }
            if ($ExcludeFiles -contains $_.Name) { return }
            Copy-Tree -RelativePath $rel -ExcludeDirs $ExcludeDirs -ExcludeFiles $ExcludeFiles
        }
    } else {
        $parent = Split-Path $dst -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -Path $src -Destination $dst -Force
    }
}

function Set-TextFile {
    param(
        [string]$RelativePath,
        [string]$Content
    )

    $path = Join-Path $TargetRoot $RelativePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
}

if ($Force -and (Test-Path $TargetRoot)) {
    Write-Step "Removing existing target: $TargetRoot"
    Remove-Item -Path $TargetRoot -Recurse -Force
}

Write-Step "Creating target root: $TargetRoot"
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

Write-Step "Copying .cursor (rules, skills, agents, commands; no platform-tools skills)"
Copy-Tree -RelativePath '.cursor\rules'
Copy-Tree -RelativePath '.cursor\agents'
Copy-Tree -RelativePath '.cursor\commands'
Copy-Tree -RelativePath '.cursor\skills' -ExcludeDirs @(
    '1c-platform-tools',
    '1c-platform-tools-config',
    '1c-platform-tools-configuration',
    '1c-platform-tools-dependencies',
    '1c-platform-tools-extensions',
    '1c-platform-tools-external',
    '1c-platform-tools-infobase',
    '1c-platform-tools-mcp',
    '1c-platform-tools-run',
    '1c-platform-tools-setversion',
    '1c-platform-tools-support',
    '1c-platform-tools-test'
)

Write-Step "Copying root and tooling files"
foreach ($rel in @(
    'AGENTS.md',
    '.dev.env.example',
    '.gitignore',
    'packagedef',
    'tools\init-project-structure.ps1',
    'tools\project-structure.json',
    'tools\README.md',
    'tools\dev-env',
    'tools\dev-standalone',
    'tools\mcp-platform-tools-launcher.sh',
    'tools\prepare-objlist.sh',
    'tools\load-objlist-config.sh',
    'tools\load-objlist-extensions.sh',
    'tools\deploy-extension.sh',
    'tools\fix-1c-platform-tools-vrunner-cmd.ps1',
    'tools\lists',
    'objlist.txt.example',
    'deploy\mcp-publish',
    'docs',
    'openspec\config.yaml',
    'openspec\README.md',
    'openspec\specs\README.md',
    'openspec\changes\README.md',
    '.vscode\settings.json',
    '.vscode\launch.json',
    '.vscode\tasks.json'
)) {
    Copy-Tree -RelativePath $rel
}

Write-Step "Writing template configs"
Set-TextFile -RelativePath '.cursor\mcp.json' -Content @'
{
    "mcpServers": {
        "mcp-1c-platform-tools": {
            "command": "node",
            "args": [
                "${env:USERPROFILE}\\.cursor\\extensions\\yellow-hammer.mcp-1c-platform-tools-0.1.8-universal\\out\\src\\index.js"
            ],
            "env": {
                "ONEC_IPC_HOST": "127.0.0.1",
                "ONEC_IPC_PORT": "40241",
                "ONEC_IPC_TOKEN": ""
            },
            "description": "1C: Platform Tools — загрузка/выгрузка конфигурации, запуск Конфигуратора/Предприятия, сборка EPF/ERF через IPC расширения"
        },
        "rlm-tools-bsl": {
            "type": "http",
            "url": "http://127.0.0.1:9000/mcp",
            "description": "RLM tools for BSL — опционально; включите при локальной индексации"
        },
        "1c-code-metadata-mcp": {
            "url": "https://mcp.1commerce.ru/codemeta-{PROJECT_SLUG}/mcp",
            "connection_id": "1c_metadata_{PROJECT_SLUG}_001",
            "description": "Проектный codemeta (cf). Замените {PROJECT_SLUG} при инициализации проекта."
        },
        "1c-graph-metadata-mcp": {
            "url": "https://mcp.1commerce.ru/graph-{PROJECT_SLUG}/mcp",
            "connection_id": "1c_graph_{PROJECT_SLUG}_001",
            "description": "Проектный graph (cf). Замените {PROJECT_SLUG} при инициализации проекта."
        },
        "1c-ext-codemeta-mcp": {
            "url": "https://mcp.1commerce.ru/codemeta-{PROJECT_SLUG}-ext/mcp",
            "connection_id": "1c_metadata_ext_{PROJECT_SLUG}_001",
            "description": "Проектный codemeta расширения (cfe). Удалите блок, если проект без расширения."
        },
        "1c-ext-graph-mcp": {
            "url": "https://mcp.1commerce.ru/graph-{PROJECT_SLUG}-ext/mcp",
            "connection_id": "1c_graph_ext_{PROJECT_SLUG}_001",
            "description": "Проектный graph расширения (cfe). Удалите блок, если проект без расширения."
        },
        "1c-syntax-checker-mcp": {
            "url": "https://mcp.1commerce.ru/syntax/mcp",
            "connection_id": "1c_lsp_service_001",
            "description": "BSL syntax validation via BSL Language Server"
        },
        "1C-docs-mcp": {
            "url": "https://mcp.1commerce.ru/help/mcp",
            "connection_id": "1c_docs_service_001",
            "description": "1C platform documentation search (docsearch, docinfo)"
        },
        "1c-templates-mcp": {
            "url": "https://mcp.1commerce.ru/templates/mcp",
            "connection_id": "1c_templates_service_001",
            "description": "Code templates library and implementation examples search"
        },
        "1c-code-check-mcp": {
            "url": "https://mcp.1commerce.ru/codecheck/mcp",
            "connection_id": "1c_code_check_service_001",
            "description": "1C code review and quality checking (1С:Напарник) — check_1c_code, review_1c_code, ITS docs"
        },
        "1c-ssl-mcp": {
            "url": "https://mcp.1commerce.ru/ssl/mcp",
            "connection_id": "1c_ssl_service_001",
            "description": "Standard Subsystems Library (БСП / SSL) function search"
        },
        "v8std-mcp": {
            "url": "https://mcp.1commerce.ru/v8std/mcp",
            "connection_id": "v8std_service_001",
            "description": "ITS v8std standards and diagnostics (soft gate in verification-checklist)"
        },
        "1c-data-mcp": {
            "url": "{INFOBASE_PUBLISH_URL}/hs/mcp",
            "connection_id": "1c_data_mcp_001",
            "description": "1C data MCP on DEV publish. Замените {INFOBASE_PUBLISH_URL} после настройки .dev.env"
        }
    }
}
'@

Set-TextFile -RelativePath 'env.json.example' -Content @'
{
    "$schema": "https://raw.githubusercontent.com/vanessa-opensource/vanessa-runner/develop/vanessa-runner-schema.json",
    "default": {
        "--ibconnection": "/F\"{INFOBASE_PATH}\"",
        "--db-user": "",
        "--db-pwd": "",
        "--root": ".",
        "--workspace": ".",
        "--v8version": "{PLATFORM_VERSION}",
        "--locale": "ru",
        "--language": "ru",
        "--additional": "/DisplayAllFunctions /L ru",
        "--ordinaryapp": "-1"
    }
}
'@

Set-TextFile -RelativePath 'tools\vrunner.init.json.example' -Content @'
{
    "$schema": "https://raw.githubusercontent.com/silverbulleters/vanessa-runner/develop/vanessa-runner-schema.json",
    "default": {
        "--ibconnection": "/S\"{SERVER}:{PORT}\\{INFOBASE_NAME}\"",
        "--db-user": "",
        "--db-pwd": "",
        "--root": ".",
        "--workspace": ".",
        "--v8version": "{PLATFORM_VERSION}",
        "--locale": "ru",
        "--language": "ru",
        "--ordinaryapp": "0"
    }
}
'@

Set-TextFile -RelativePath 'packagedef' -Content @'
////////////////////////////////////////////////////////////
// Описание пакета для сборки и установки
// Полную документацию см. https://oscript.io/learn/new-project#заполнение-манифеста
//

Описание.Имя("my-1c-project")
    .Версия("1.0.0")
    .ВерсияСреды("2.0.0")
    .ЗависитОт("add")
    .ЗависитОт("vanessa-automation-single")
    .ЗависитОт("vanessa-runner", "2.6.1")

;
'@

$devEnvExamplePath = Join-Path $TargetRoot '.dev.env.example'
if (Test-Path $devEnvExamplePath) {
    $extraDevEnv = @'

# =============================================================================
# Раздел 2а. Публикации: DEV (локально) и PROD (эталон, не для ежедневной работы)
# Section 2a. Publications: DEV (local) and PROD (reference only)
# =============================================================================
#
# INFOBASE_PUBLISH_URL — единственный URL для слэш-команд, 1c-tester и MCP data.
# INFOBASE_PUBLISH_URL_PROD / INFOBASE_DATA_MCP_URL_PROD — справочно; агент не
# должен ходить на PROD без явного запроса пользователя.

INFOBASE_PUBLISH_URL_PROD=

INFOBASE_DATA_MCP_URL_PROD=

# Автономный сервер разработки (ibcmd / ibsrv)
STANDALONE_DATA_PATH=
STANDALONE_PORT=8314
STANDALONE_HTTP_BASE=
STANDALONE_ADDRESS=
'@
    $content = Get-Content -Raw -Path $devEnvExamplePath -Encoding UTF8
    if ($content -notmatch 'STANDALONE_PORT') {
        [IO.File]::AppendAllText($devEnvExamplePath, $extraDevEnv, [Text.UTF8Encoding]::new($false))
    }
}

Write-Step "Writing USER-RULES.md and memory.md templates"
Set-TextFile -RelativePath 'USER-RULES.md' -Content @'
# User Rules — {PROJECT_NAME}

Project-specific rules for AI agents. This file is a one-time template: the 1c-rules
installer never overwrites it after the first install.

## DEV vs PROD

- **Working environment** — local DEV infobase and publish URL from `.dev.env` (`INFOBASE_PUBLISH_URL`).
- **PROD** — reference only (`INFOBASE_PUBLISH_URL_PROD`, `INFOBASE_DATA_MCP_URL_PROD`). Do not use for daily development, UI tests, or MCP unless the user explicitly asks.
- New metadata objects — follow `NEW_OBJECTS_IN` in `.dev.env` (`main_configuration` or `extension`).

Details: [docs/dev-environment.md](docs/dev-environment.md).

## MCP: configuration vs extension (optional)

If your project uses separate MCP indexes for the main configuration (cf) and an extension (cfe), document routing here:

| Layer | Servers | Index |
|-------|---------|-------|
| Main configuration (cf) | `1c-code-metadata-mcp`, `1c-graph-metadata-mcp` | primary codebase |
| Extension (cfe) | `1c-ext-codemeta-mcp`, `1c-ext-graph-mcp` | extension layer only |

Choose the index by metadata layer (path under `src/cfe/…` vs `src/cf/…`), not by object name prefix alone.

## Migrated content from a previous setup

<!-- start of migrated content -->
<!-- end of migrated content -->
'@

Set-TextFile -RelativePath 'memory.md' -Content @'
# Memory

This file is the working project memory for AI agents.

Eligibility, routing between this file and `1c-templates-mcp` (`remember` / `recall`),
fallback when the MCP server is unavailable — see `AGENTS.md → Project memory`.
There are no permanent entries yet.

Entry format (one entry = one self-contained rule). Use English for narrative,
preserve original 1C identifiers (objects, modules, attributes) as-is:

<!--
## YYYY-MM-DD — <short rule title>

- **Scope:** module / subsystem / object where the rule applies (e.g. `Документ.РеализацияТоваровУслуг`).
- **Rule:** what must / must not be done.
- **Why:** consequence of violation (production breakage / data loss / regulatory / data leak).
- **Source:** user request, incident, or external document that established the rule.
-->
'@

Write-Step "Initializing project directory skeleton"
& (Join-Path $TargetRoot 'tools\init-project-structure.ps1') -ProjectRoot $TargetRoot

Write-Step "Removing vrunner.init.json with project credentials (keep .example only)"
$vrunnerInit = Join-Path $TargetRoot 'tools\vrunner.init.json'
if (Test-Path $vrunnerInit) {
    Remove-Item $vrunnerInit -Force
}

Write-Step "Sanitizing copied docs and deploy scripts (project-specific strings)"
$sanitizePatterns = @(
    @{ From = '1commerce-tradecrm'; To = '{PROJECT_SLUG}' },
    @{ From = '1commerce:3341'; To = '{SERVER}:{PORT}' },
    @{ From = '158\.160\.70\.248'; To = '{PROD_HOST}' },
    @{ From = 'ЧуклайМ'; To = '' },
    @{ From = 'Kosmeti4k@'; To = '' },
    @{ From = 'Расширение1Коммерция'; To = '{EXTENSION_NAME}' },
    @{ From = 'D:\\infobases-files\\1commerce-tradecrm'; To = '{PROJECT_ROOT}' },
    @{ From = 'D:/infobases-files/1commerce-tradecrm'; To = '{PROJECT_ROOT}' },
    @{ From = 'x:\\dev-projects\\1commerce-tradecrm'; To = '{PROJECT_ROOT}' },
    @{ From = '8\.5\.1\.1343'; To = '{PLATFORM_VERSION}' }
)

$textExtensions = @('.md', '.ps1', '.json', '.mdc', '.yaml', '.yml', '.vrd', '.xml', '.config')
Get-ChildItem -Path $TargetRoot -Recurse -File | Where-Object {
    $textExtensions -contains $_.Extension.ToLowerInvariant()
} | ForEach-Object {
    $raw = [IO.File]::ReadAllText($_.FullName)
    $updated = $raw
    foreach ($p in $sanitizePatterns) {
        $updated = [regex]::Replace($updated, $p.From, $p.To)
    }
    if ($updated -ne $raw) {
        [IO.File]::WriteAllText($_.FullName, $updated, [Text.UTF8Encoding]::new($false))
    }
}

Write-Step "Updating .gitignore workspace entry"
$gitignorePath = Join-Path $TargetRoot '.gitignore'
if (Test-Path $gitignorePath) {
    $gi = Get-Content -Raw -Path $gitignorePath -Encoding UTF8
    $gi = $gi -replace '1commerce-tradecrm\.code-workspace', 'my-1c-project.code-workspace'
    if ($gi -notmatch '!vendor/mcp/OneMCP\.cfe') {
        $gi = $gi -replace '(\*\.dt\r?\n)', "`$1# Исключение: дистрибутив OneMCP для новых проектов (vendor/mcp/)`r`n!vendor/mcp/OneMCP.cfe`r`n"
    }
    [IO.File]::WriteAllText($gitignorePath, $gi, [Text.UTF8Encoding]::new($false))
}

Write-Step "Export complete: $TargetRoot"

$overlayRoot = Join-Path $PSScriptRoot 'template-overlay'
if (Test-Path $overlayRoot) {
    Write-Step "Applying template-overlay post-export fixes"
    Get-ChildItem -Path $overlayRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($overlayRoot.Length).TrimStart('\', '/')
        $dest = Join-Path $TargetRoot $rel
        $parent = Split-Path $dest -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -Path $_.FullName -Destination $dest -Force
    }
}

Write-Host "Template ready. See TEMPLATE.md for initialization checklist."
