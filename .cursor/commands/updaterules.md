---
description: "Update agent rules from 1c-project-template (https://github.com/mikhailchuklay/1c-project-template)"
---

# /updaterules — sync rules from project template

**Source of truth for this command:** [mikhailchuklay/1c-project-template](https://github.com/mikhailchuklay/1c-project-template) (`master` by default).

Projects created from this template should **not** run `comol/ai_rules_1c` `install.ps1 update` as the primary path — that installer expects the `content/` layout of `ai_rules_1c` and will miss template overlays (e.g. `configuration-storage`, 1commerce rules, `CONFIG_STORAGE_*`).

## What is synced

From the template clone into the **current project**:

- `.cursor/rules/**`
- `.cursor/skills/**` except `1c-platform-tools*` (those come from the IDE extension)
- `.cursor/agents/**`
- `.cursor/commands/**`
- `AGENTS.md`
- `.dev.env.example`

Stamp file written: `.rules-template-sync.json` (commit / URL / time).

## What is preserved

- `.dev.env`, `memory.md`, `USER-RULES.md`
- `.cursor/mcp.json`
- `src/`, `build/`, `openspec/specs/`, `openspec/changes/` (except READMEs if you copy docs manually)

## Steps

1. Confirm the project root contains `.cursor/rules` (template-based project). If the project was installed only via `ai_rules_1c` `install.ps1 init` and never used this template, ask before overwriting.

2. Optional overrides in `.dev.env` (create keys if missing):

```env
RULES_TEMPLATE_URL=https://github.com/mikhailchuklay/1c-project-template.git
RULES_TEMPLATE_REF=master
```

3. From the project root run:

```powershell
# Prefer the script already in the project; if missing, fetch once from template:
if (-not (Test-Path .\tools\update-from-template.ps1)) {
    $tmp = Join-Path $env:TEMP '1c-project-template-bootstrap'
    if (-not (Test-Path (Join-Path $tmp '.git'))) {
        git clone --depth 1 https://github.com/mikhailchuklay/1c-project-template.git $tmp
    } else {
        git -C $tmp pull --ff-only
    }
    New-Item -ItemType Directory -Force -Path .\tools | Out-Null
    Copy-Item "$tmp\tools\update-from-template.ps1" .\tools\update-from-template.ps1 -Force
}

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-from-template.ps1
```

Dry-run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-from-template.ps1 -DryRun
```

Skip overwriting `AGENTS.md` / `.dev.env.example`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-from-template.ps1 -SkipAgentsMd -SkipDevEnvExample
```

4. After sync:

- Diff `AGENTS.md` if the project had local edits — merge back anything project-specific into `USER-RULES.md` or contribute to the template.
- If `.dev.env.example` gained new keys (e.g. `CONFIG_STORAGE_*`), copy them into `.dev.env`. For storage: ask once whether the project uses configuration storage (`TEMPLATE.md` §2).
- Reload the Cursor window if slash commands look stale.

## Not in scope

Refreshing the template itself from `comol/ai_rules_1c` — that is a **template maintainer** task (`install.ps1` / export into the template repo), not a per-project `/updaterules`.
