#Requires -Version 5.1
<#
.SYNOPSIS
    Sync agent rules/skills/agents/commands from 1c-project-template into the current project.

.DESCRIPTION
    Used by /updaterules for projects created from mikhailchuklay/1c-project-template.
    Does NOT run comol/ai_rules_1c install.ps1 (different layout). Template is the SSOT
    for .cursor/rules, skills (except Platform Tools), agents, and commands.

.PARAMETER ProjectRoot
    Target project root (default: current directory).

.PARAMETER TemplateUrl
    Git URL of the template. Default: https://github.com/mikhailchuklay/1c-project-template.git
    Override via .dev.env RULES_TEMPLATE_URL.

.PARAMETER Ref
    Git ref to sync (branch/tag). Default: master. Override via RULES_TEMPLATE_REF.

.PARAMETER SkipAgentsMd
    Do not overwrite AGENTS.md.

.PARAMETER SkipDevEnvExample
    Do not overwrite .dev.env.example.

.PARAMETER DryRun
    Report actions without writing.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$TemplateUrl = '',
    [string]$Ref = '',
    [switch]$SkipAgentsMd,
    [switch]$SkipDevEnvExample,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Read-DevEnvValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path $Path)) { return $null }
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        if ($line -match "^\s*#") { continue }
        if ($line -match "^\s*$Key\s*=\s*(.*)$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Copy-TreeSync {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [string[]]$ExcludeDirNames = @()
    )
    if (-not (Test-Path $SourceDir)) {
        Write-Warning "Skip missing source: $SourceDir"
        return @{ Added = 0; Updated = 0; Skipped = 0 }
    }
    $stats = @{ Added = 0; Updated = 0; Skipped = 0 }
    Get-ChildItem -Path $SourceDir -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
        $parts = $rel -split '[\\/]'
        foreach ($ex in $ExcludeDirNames) {
            if ($parts -contains $ex) {
                $stats.Skipped++
                return
            }
        }
        $dst = Join-Path $DestDir $rel
        $dstParent = Split-Path $dst -Parent
        $action = if (Test-Path $dst) { 'Updated' } else { 'Added' }
        if ($DryRun) {
            Write-Host "  [dry-run] $action $rel"
            $stats[$action]++
            return
        }
        if (-not (Test-Path $dstParent)) {
            New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
        }
        Copy-Item -Path $_.FullName -Destination $dst -Force
        $stats[$action]++
    }
    return $stats
}

function Copy-FileSync {
    param([string]$SourceFile, [string]$DestFile, [string]$Label)
    if (-not (Test-Path $SourceFile)) {
        Write-Warning "Skip missing: $Label"
        return
    }
    if ($DryRun) {
        Write-Host "  [dry-run] Write $Label"
        return
    }
    $parent = Split-Path $DestFile -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -Path $SourceFile -Destination $DestFile -Force
    Write-Host "  OK $Label"
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Get-Location).Path
}
$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$devEnv = Join-Path $ProjectRoot '.dev.env'

if ([string]::IsNullOrWhiteSpace($TemplateUrl)) {
    $TemplateUrl = Read-DevEnvValue -Path $devEnv -Key 'RULES_TEMPLATE_URL'
}
if ([string]::IsNullOrWhiteSpace($TemplateUrl)) {
    $TemplateUrl = 'https://github.com/mikhailchuklay/1c-project-template.git'
}
if ([string]::IsNullOrWhiteSpace($Ref)) {
    $Ref = Read-DevEnvValue -Path $devEnv -Key 'RULES_TEMPLATE_REF'
}
if ([string]::IsNullOrWhiteSpace($Ref)) {
    $Ref = 'master'
}

$cache = Join-Path $env:TEMP '1c-project-template-rules'
Write-Step "Template cache: $cache"
Write-Step "URL: $TemplateUrl  ref: $Ref"

if (Test-Path (Join-Path $cache '.git')) {
    $prevEa = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git -C $cache fetch --depth 1 origin $Ref 2>&1 | Out-Host
    $fetchCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEa
    if ($fetchCode -ne 0) { throw "git fetch failed ($fetchCode)" }
    $ErrorActionPreference = 'Continue'
    git -C $cache checkout -B sync FETCH_HEAD 2>&1 | Out-Host
    $coCode = $LASTEXITCODE
    if ($coCode -ne 0) {
        git -C $cache reset --hard "origin/$Ref" 2>&1 | Out-Host
        $coCode = $LASTEXITCODE
    }
    $ErrorActionPreference = $prevEa
    if ($coCode -ne 0) { throw "git checkout/reset failed ($coCode)" }
} else {
    if (Test-Path $cache) { Remove-Item -Path $cache -Recurse -Force }
    $prevEa = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git clone --depth 1 --branch $Ref $TemplateUrl $cache 2>&1 | Out-Host
    $cloneCode = $LASTEXITCODE
    if ($cloneCode -ne 0) {
        git clone --depth 1 $TemplateUrl $cache 2>&1 | Out-Host
        $cloneCode = $LASTEXITCODE
        if ($cloneCode -eq 0) {
            git -C $cache fetch --depth 1 origin $Ref 2>&1 | Out-Host
            git -C $cache checkout -B sync FETCH_HEAD 2>&1 | Out-Host
            $cloneCode = $LASTEXITCODE
        }
    }
    $ErrorActionPreference = $prevEa
    if ($cloneCode -ne 0) { throw "git clone failed ($cloneCode)" }
}

$platformExclude = @(
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

Write-Step "Sync .cursor/rules"
$r = Copy-TreeSync -SourceDir (Join-Path $cache '.cursor\rules') -DestDir (Join-Path $ProjectRoot '.cursor\rules')
Write-Host ("  rules: +{0} ~{1} skip {2}" -f $r.Added, $r.Updated, $r.Skipped)

Write-Step "Sync .cursor/skills (exclude Platform Tools)"
$s = Copy-TreeSync -SourceDir (Join-Path $cache '.cursor\skills') -DestDir (Join-Path $ProjectRoot '.cursor\skills') -ExcludeDirNames $platformExclude
Write-Host ("  skills: +{0} ~{1} skip {2}" -f $s.Added, $s.Updated, $s.Skipped)

Write-Step "Sync .cursor/agents"
$a = Copy-TreeSync -SourceDir (Join-Path $cache '.cursor\agents') -DestDir (Join-Path $ProjectRoot '.cursor\agents')
Write-Host ("  agents: +{0} ~{1} skip {2}" -f $a.Added, $a.Updated, $a.Skipped)

Write-Step "Sync .cursor/commands"
$c = Copy-TreeSync -SourceDir (Join-Path $cache '.cursor\commands') -DestDir (Join-Path $ProjectRoot '.cursor\commands')
Write-Host ("  commands: +{0} ~{1} skip {2}" -f $c.Added, $c.Updated, $c.Skipped)

if (-not $SkipAgentsMd) {
    Write-Step "Sync AGENTS.md"
    Copy-FileSync -SourceFile (Join-Path $cache 'AGENTS.md') -DestFile (Join-Path $ProjectRoot 'AGENTS.md') -Label 'AGENTS.md'
}

if (-not $SkipDevEnvExample) {
    Write-Step "Sync .dev.env.example"
    Copy-FileSync -SourceFile (Join-Path $cache '.dev.env.example') -DestFile (Join-Path $ProjectRoot '.dev.env.example') -Label '.dev.env.example'
}

Write-Step "Sync docs/headless-agent.md"
Copy-FileSync -SourceFile (Join-Path $cache 'docs\headless-agent.md') -DestFile (Join-Path $ProjectRoot 'docs\headless-agent.md') -Label 'docs/headless-agent.md'

Write-Step "Sync tools/update-from-template.ps1"
Copy-FileSync -SourceFile (Join-Path $cache 'tools\update-from-template.ps1') -DestFile (Join-Path $ProjectRoot 'tools\update-from-template.ps1') -Label 'tools/update-from-template.ps1'

# Extension load used by rules (headless-agent) and its environment helpers.
Write-Step "Sync tools/deploy-extension.sh and tools/dev-standalone"
Copy-FileSync -SourceFile (Join-Path $cache 'tools\deploy-extension.sh') -DestFile (Join-Path $ProjectRoot 'tools\deploy-extension.sh') -Label 'tools/deploy-extension.sh'
$ds = Copy-TreeSync -SourceDir (Join-Path $cache 'tools\dev-standalone') -DestDir (Join-Path $ProjectRoot 'tools\dev-standalone')
Write-Host ("  dev-standalone: +{0} ~{1} skip {2}" -f $ds.Added, $ds.Updated, $ds.Skipped)

# .gitattributes: the project may have its own rules - create when missing, never overwrite.
Write-Step "Sync .gitattributes (only if missing)"
$gaSrc = Join-Path $cache '.gitattributes'
$gaDst = Join-Path $ProjectRoot '.gitattributes'
if (-not (Test-Path $gaDst)) {
    Copy-FileSync -SourceFile $gaSrc -DestFile $gaDst -Label '.gitattributes'
} elseif ((Test-Path $gaSrc) -and ((Get-FileHash $gaSrc).Hash -ne (Get-FileHash $gaDst).Hash)) {
    Write-Warning ".gitattributes differs from the template - merge manually (template: $gaSrc)"
} else {
    Write-Host "  .gitattributes up to date"
}

# Advisory: keys present in the template .dev.env.example but missing from the project .dev.env, and legacy keys.
Write-Step "Check .dev.env keys"
$exampleKeys = @()
$examplePath = Join-Path $cache '.dev.env.example'
if (Test-Path $examplePath) {
    $exampleKeys = Get-Content $examplePath -Encoding UTF8 | Where-Object { $_ -match '^[A-Z0-9_]+=' } | ForEach-Object { ($_ -split '=', 2)[0] }
}
if (Test-Path $devEnv) {
    $projectKeys = Get-Content $devEnv -Encoding UTF8 | Where-Object { $_ -match '^[A-Z0-9_]+=' } | ForEach-Object { ($_ -split '=', 2)[0] }
    $missing = $exampleKeys | Where-Object { $projectKeys -notcontains $_ }
    if ($missing) {
        Write-Warning ("Keys missing in .dev.env (copy from .dev.env.example): " + ($missing -join ', '))
    } else {
        Write-Host "  .dev.env has every key of .dev.env.example"
    }
    $legacy = $projectKeys | Where-Object { $_ -like 'CONFIG_STORAGE_*' }
    if ($legacy) {
        Write-Warning ("Legacy keys in .dev.env: " + ($legacy -join ', ') + " -> REPOSITORY_PATH / REPOSITORY_USER / REPOSITORY_PASSWORD (1c-repository-manage); remove the old keys afterwards")
    }
} else {
    Write-Host "  .dev.env not found - skipped"
}

# Executable bit: git on Windows (core.filemode=false) records copied files as 100644, so
# Linux agents/containers get non-executable scripts. Restore the template's 100755 in the
# project index for every synced file that is executable in the template.
Write-Step "Restore executable bit from template (git index)"
$prevEa = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$inRepo = (git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null)
$ErrorActionPreference = $prevEa
if ($inRepo -ne 'true') {
    Write-Host "  project is not a git work tree - skipped"
} else {
    $execFiles = @(git -C $cache ls-files -s | Where-Object { $_ -match '^100755 ' } |
        ForEach-Object { ($_ -split "`t", 2)[1] })
    $fixed = 0
    foreach ($rel in $execFiles) {
        $dst = Join-Path $ProjectRoot ($rel -replace '/', '\')
        if (-not (Test-Path $dst)) { continue }
        $entry = git -C $ProjectRoot ls-files -s -- $rel
        if ($entry -and $entry -match '^100755 ') { continue }
        if ($DryRun) {
            Write-Host "  [dry-run] +x $rel"
        } elseif ($entry) {
            git -C $ProjectRoot update-index --chmod=+x -- $rel
        } else {
            # new file: stage it with the executable bit (git add --chmod, git >= 2.9)
            git -C $ProjectRoot add --chmod=+x -- $rel
        }
        $fixed++
    }
    Write-Host ("  executable bit set: {0}" -f $fixed)
}

# Lightweight stamp (does not replace .ai-rules.json protocol from install.ps1)
$stampPath = Join-Path $ProjectRoot '.rules-template-sync.json'
$commit = (git -C $cache rev-parse --short HEAD)
$stamp = @{
    protocol        = 'template-sync/1.0'
    templateUrl     = $TemplateUrl
    ref             = $Ref
    commit          = $commit
    syncedAt        = (Get-Date).ToUniversalTime().ToString('o')
    projectRoot     = $ProjectRoot
} | ConvertTo-Json
if (-not $DryRun) {
    [IO.File]::WriteAllText($stampPath, $stamp, [Text.UTF8Encoding]::new($false))
}

Write-Step "Done (template @$commit)"
Write-Host @"

Preserved (not overwritten):
  .dev.env, memory.md, USER-RULES.md, .cursor/mcp.json, src/, build/, openspec/specs, openspec/changes

Next:
  1. Diff AGENTS.md / .dev.env.example / .gitattributes if you had local edits.
  2. Copy the keys listed above as missing from .dev.env.example into .dev.env (TOOL_*, USE_EDT, REPOSITORY_* ...).
     Legacy CONFIG_STORAGE_* -> REPOSITORY_PATH / REPOSITORY_USER / REPOSITORY_PASSWORD, then delete the old keys.
  3. Reload Cursor window if commands/skills list looks stale.

Upstream comol/ai_rules_1c is NOT applied here. Template maintainers refresh the template separately, then projects pull via this command.
"@
