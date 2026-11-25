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

.PARAMETER Check
    Only compare "commit" in .rules-template-sync.json with the head of the template ref; change nothing.
    Exit code: 0 - up to date, 1 - behind (commit count and CHANGELOG-TEMPLATE.md entries marked
    [несовместимо]/[безопасность] are printed), 2 - error. Ref: -Ref, else RULES_TEMPLATE_REF,
    else "ref" from .rules-template-sync.json, else master.

.PARAMETER Report
    Write a sync report for automation: lines "owned <path>" (template-owned file) and
    "skip <path> <reason>" (skipped because of a local edit).
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$TemplateUrl = '',
    [string]$Ref = '',
    [switch]$SkipAgentsMd,
    [switch]$SkipDevEnvExample,
    [switch]$DryRun,
    [switch]$Check,
    [string]$Report = ''
)

$ErrorActionPreference = 'Stop'

# Protocol of the sync stamp (.rules-template-sync.json). The major part changes only on an
# incompatible format change; a major mismatch produces a warning.
$Protocol = 'template-sync/1.1'
$script:ReportLines = New-Object System.Collections.Generic.List[string]

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
        if ($script:ReportPrefixRoot) {
            $script:ReportLines.Add('owned ' + ($dst.Substring($script:ReportPrefixRoot.Length).TrimStart('\', '/') -replace '\\', '/'))
        }
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
    $script:ReportLines.Add("owned $Label")
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
$stampPath = Join-Path $ProjectRoot '.rules-template-sync.json'
$script:ReportPrefixRoot = $ProjectRoot

$stampData = $null
if (Test-Path $stampPath) {
    try { $stampData = Get-Content -Raw -Encoding UTF8 $stampPath | ConvertFrom-Json } catch { $stampData = $null }
}

function Test-ProtocolMajor {
    if (-not $stampData -or -not $stampData.protocol) { return }
    $have = [string]$stampData.protocol
    $haveMajor = (($have -replace '^template-sync/', '') -split '\.')[0]
    $wantMajor = (($Protocol -replace '^template-sync/', '') -split '\.')[0]
    if (-not $have.StartsWith('template-sync/') -or $haveMajor -ne $wantMajor) {
        Write-Warning "protocol mismatch: .rules-template-sync.json has '$have', script speaks '$Protocol' - read CHANGELOG-TEMPLATE.md before syncing"
    }
}

if ([string]::IsNullOrWhiteSpace($TemplateUrl)) {
    $TemplateUrl = Read-DevEnvValue -Path $devEnv -Key 'RULES_TEMPLATE_URL'
}
if ([string]::IsNullOrWhiteSpace($TemplateUrl) -and $stampData -and $stampData.templateUrl) {
    $TemplateUrl = [string]$stampData.templateUrl
}
if ([string]::IsNullOrWhiteSpace($TemplateUrl)) {
    $TemplateUrl = 'https://github.com/mikhailchuklay/1c-project-template.git'
}
if ([string]::IsNullOrWhiteSpace($Ref)) {
    $Ref = Read-DevEnvValue -Path $devEnv -Key 'RULES_TEMPLATE_REF'
}
if ($Check -and [string]::IsNullOrWhiteSpace($Ref) -and $stampData -and $stampData.ref) {
    $Ref = [string]$stampData.ref
}
if ([string]::IsNullOrWhiteSpace($Ref)) {
    $Ref = 'master'
}

$tempRoot = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [IO.Path]::GetTempPath() }
$cache = Join-Path $tempRoot '1c-project-template-rules'

# -Check: compare the project's commit with the template ref head; never writes into the project.
# Head via git ls-remote; history and changelog via a shallow fetch into a separate bare cache.
function Invoke-TemplateCheck {
    $ErrorActionPreference = 'Continue'
    if (-not $stampData) {
        [Console]::Error.WriteLine("ERROR: $stampPath not found or unreadable - run tools/update-from-template.ps1")
        exit 2
    }
    Test-ProtocolMajor
    $have = [string]$stampData.commit
    if ([string]::IsNullOrWhiteSpace($have)) {
        [Console]::Error.WriteLine("ERROR: no ""commit"" in $stampPath"); exit 2
    }
    $lines = @(git ls-remote $TemplateUrl "refs/heads/$Ref" "refs/tags/$Ref" "refs/tags/$Ref^{}" 2>$null)
    $head = ''
    foreach ($l in $lines) {
        $f = $l -split "`t"
        if ($f.Count -lt 2) { continue }
        if ($f[1].EndsWith('^{}')) { $head = $f[0]; break }
        $head = $f[0]
    }
    if (-not $head) {
        if ($Ref -match '^[0-9a-f]{7,40}$') {
            if ($Ref.StartsWith($have) -or $have.StartsWith($Ref)) {
                Write-Host "OK: pinned to commit $Ref (RULES_TEMPLATE_REF), project @$have"; exit 0
            }
            Write-Host "BEHIND: project @$have, pinned RULES_TEMPLATE_REF=$Ref - sync to the pinned commit"; exit 1
        }
        [Console]::Error.WriteLine("ERROR: ref '$Ref' not found at $TemplateUrl (git ls-remote)"); exit 2
    }
    $short = $head.Substring(0, 7)
    if ($head.StartsWith($have)) {
        Write-Host "OK: rules are up to date (template $Ref @$short)"; exit 0
    }
    $cc = "$cache-check"
    if (-not (Test-Path (Join-Path $cc 'objects'))) {
        if (Test-Path $cc) { Remove-Item -Recurse -Force $cc }
        git init -q --bare $cc 2>&1 | Out-Null
    }
    git -C $cc fetch -q --depth 200 $TemplateUrl "+${head}:refs/check/head" 2>$null
    if ($LASTEXITCODE -ne 0) {
        git -C $cc fetch -q --depth 200 $TemplateUrl "+refs/heads/${Ref}:refs/check/head" 2>$null
        if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine("ERROR: git fetch of $Ref failed"); exit 2 }
    }
    $base = git -C $cc rev-parse -q --verify "$have^{commit}" 2>$null
    if (-not $base) {
        git -C $cc fetch -q --unshallow $TemplateUrl "+refs/check/head:refs/check/head" 2>$null
        if ($LASTEXITCODE -ne 0) { git -C $cc fetch -q --deepen 2000 $TemplateUrl "+${head}:refs/check/head" 2>$null }
        $base = git -C $cc rev-parse -q --verify "$have^{commit}" 2>$null
    }
    $log = 'CHANGELOG-TEMPLATE.md'
    if ($base) {
        git -C $cc merge-base --is-ancestor refs/check/head $base 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "OK: project @$have is at or ahead of template $Ref @$short"; exit 0 }
        $n = git -C $cc rev-list --count "$base..refs/check/head"
        Write-Host "BEHIND: project @$have, template $Ref @${short}: $n commit(s) behind"
        $entries = @(git -C $cc diff --no-color -U0 $base refs/check/head -- $log 2>$null |
            Where-Object { $_ -match '^\+- ' } | ForEach-Object { $_.Substring(1) })
    } else {
        Write-Host "BEHIND: project @$have is not in the history of template $Ref @$short (rewritten or unknown commit)"
        $entries = @(git -C $cc show "refs/check/head:$log" 2>$null | Where-Object { $_ -match '^- ' })
    }
    $marked = @($entries | Where-Object { $_ -match '\[(несовместимо|безопасность)' })
    if ($marked.Count -gt 0) {
        Write-Host ''
        Write-Host "Записи журнала с пометками «несовместимо»/«безопасность» (${log}):"
        $marked | ForEach-Object { Write-Host $_ }
    }
    Write-Host ''
    Write-Host ("Новых записей в {0}: {1}. Синхронизация: tools/update-from-template.ps1 (одним исполнителем, не из агента задачи)." -f $log, $entries.Count)
    exit 1
}

if ($Check) {
    try { Invoke-TemplateCheck } catch { [Console]::Error.WriteLine("ERROR: -Check failed: $_"); exit 2 }
}

Test-ProtocolMajor
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

Write-Step "Sync tools/update-from-template.{ps1,sh}"
Copy-FileSync -SourceFile (Join-Path $cache 'tools\update-from-template.ps1') -DestFile (Join-Path $ProjectRoot 'tools\update-from-template.ps1') -Label 'tools/update-from-template.ps1'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\update-from-template.sh') -DestFile (Join-Path $ProjectRoot 'tools\update-from-template.sh') -Label 'tools/update-from-template.sh'

# Scripts the rules point at (headless-agent, designer-batch-checks) and their environment helpers.
Write-Step "Sync tools/deploy-extension.sh, tools/designer-batch.sh, tools/check-bsl-calls.py and tools/dev-standalone"
Copy-FileSync -SourceFile (Join-Path $cache 'tools\deploy-extension.sh') -DestFile (Join-Path $ProjectRoot 'tools\deploy-extension.sh') -Label 'tools/deploy-extension.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\designer-batch.sh') -DestFile (Join-Path $ProjectRoot 'tools\designer-batch.sh') -Label 'tools/designer-batch.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\thick-client-check.sh') -DestFile (Join-Path $ProjectRoot 'tools\thick-client-check.sh') -Label 'tools/thick-client-check.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\check-bsl-calls.py') -DestFile (Join-Path $ProjectRoot 'tools\check-bsl-calls.py') -Label 'tools/check-bsl-calls.py'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\ordinary-form.py') -DestFile (Join-Path $ProjectRoot 'tools\ordinary-form.py') -Label 'tools/ordinary-form.py'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\stand-load-guard.sh') -DestFile (Join-Path $ProjectRoot 'tools\stand-load-guard.sh') -Label 'tools/stand-load-guard.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\agent-monitor.sh') -DestFile (Join-Path $ProjectRoot 'tools\agent-monitor.sh') -Label 'tools/agent-monitor.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\agent-workspace-cleanup.sh') -DestFile (Join-Path $ProjectRoot 'tools\agent-workspace-cleanup.sh') -Label 'tools/agent-workspace-cleanup.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\release-gate.sh') -DestFile (Join-Path $ProjectRoot 'tools\release-gate.sh') -Label 'tools/release-gate.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\task-board.sh') -DestFile (Join-Path $ProjectRoot 'tools\task-board.sh') -Label 'tools/task-board.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\pr-merge.sh') -DestFile (Join-Path $ProjectRoot 'tools\pr-merge.sh') -Label 'tools/pr-merge.sh'
Copy-FileSync -SourceFile (Join-Path $cache 'tools\lists\bsl-global-names.txt') -DestFile (Join-Path $ProjectRoot 'tools\lists\bsl-global-names.txt') -Label 'tools/lists/bsl-global-names.txt'
$ds = Copy-TreeSync -SourceDir (Join-Path $cache 'tools\dev-standalone') -DestDir (Join-Path $ProjectRoot 'tools\dev-standalone')
Write-Host ("  dev-standalone: +{0} ~{1} skip {2}" -f $ds.Added, $ds.Updated, $ds.Skipped)

# Task board (tools/task-board.sh) lives in the main checkout outside git: its path must be ignored.
Write-Step "Ensure .gitignore ignores .task-board/"
$giPath = Join-Path $ProjectRoot '.gitignore'
if ((Test-Path $giPath) -and (Select-String -Path $giPath -Pattern '^/?\.task-board/?$' -Quiet)) {
    Write-Host "  .gitignore already ignores .task-board/"
} elseif ($DryRun) {
    Write-Host "  [dry-run] append .task-board/ to .gitignore"
} else {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($giPath, "`n# Project task board (tools/task-board.sh), shared by worktrees`n.task-board/`n", $utf8)
    Write-Host "  OK .gitignore += .task-board/"
}

# docs/project-patterns.md belongs to the project: seed when missing, never overwrite.
Write-Step "Seed docs/project-patterns.md (only if missing)"
if (-not (Test-Path (Join-Path $ProjectRoot 'docs\project-patterns.md'))) {
    Copy-FileSync -SourceFile (Join-Path $cache 'docs\project-patterns.md') -DestFile (Join-Path $ProjectRoot 'docs\project-patterns.md') -Label 'docs/project-patterns.md'
} else {
    Write-Host "  docs/project-patterns.md exists - kept"
}

# tools/vrunner.init.json holds a specific base's connection: never committed (template: .example).
Write-Step "Ensure .gitignore ignores tools/vrunner.init.json"
if ((Test-Path $giPath) -and (Select-String -Path $giPath -Pattern '^/?tools/vrunner\.init\.json$' -Quiet)) {
    Write-Host "  .gitignore already ignores tools/vrunner.init.json"
} elseif ($DryRun) {
    Write-Host "  [dry-run] append tools/vrunner.init.json to .gitignore"
} else {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($giPath, "`n# vrunner connection to a specific base - local only (template: tools/vrunner.init.json.example)`ntools/vrunner.init.json`n", $utf8)
    Write-Host "  OK .gitignore += tools/vrunner.init.json"
}
& git -C $ProjectRoot ls-files --error-unmatch tools/vrunner.init.json 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Warning "tools/vrunner.init.json is tracked by git (connection to a specific base): git rm --cached tools/vrunner.init.json" }

# .gitattributes: the project may have its own rules - create when missing, never overwrite.
Write-Step "Sync .gitattributes (only if missing)"
$gaSrc = Join-Path $cache '.gitattributes'
$gaDst = Join-Path $ProjectRoot '.gitattributes'
if (-not (Test-Path $gaDst)) {
    Copy-FileSync -SourceFile $gaSrc -DestFile $gaDst -Label '.gitattributes'
} elseif ((Test-Path $gaSrc) -and ((Get-FileHash $gaSrc).Hash -ne (Get-FileHash $gaDst).Hash)) {
    Write-Warning ".gitattributes differs from the template - merge manually (template: $gaSrc)"
    $script:ReportLines.Add('skip .gitattributes local-differs')
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

# Lightweight stamp (does not replace .ai-rules.json protocol from install.ps1).
# No absolute project path: the stamp is committed and must not leak a local/temp directory.
$commit = (git -C $cache rev-parse --short HEAD)
$stamp = [ordered]@{
    protocol        = $Protocol
    templateUrl     = $TemplateUrl
    ref             = $Ref
    commit          = $commit
    syncedAt        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
} | ConvertTo-Json
if (-not $DryRun) {
    [IO.File]::WriteAllText($stampPath, $stamp, [Text.UTF8Encoding]::new($false))
}
$script:ReportLines.Add('owned .rules-template-sync.json')
if ($Report) {
    [IO.File]::WriteAllLines($Report, $script:ReportLines, [Text.UTF8Encoding]::new($false))
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
