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
- `docs/headless-agent.md`
- `tools/update-from-template.ps1` (the script updates itself)
- `tools/deploy-extension.sh` and `tools/dev-standalone/**` (extension load used by the rules)
- `.gitattributes` — only when the project has none; an existing one is never overwritten, a difference is reported for a manual merge

Stamp file written: `.rules-template-sync.json` (commit / URL / time).

## What is preserved

- `.dev.env`, `memory.md`, `USER-RULES.md`, `LLM-RULES.md` (project-owned; a project without `LLM-RULES.md` can copy the empty starter from the template root)
- `.cursor/mcp.json`
- `src/`, `build/`, `openspec/specs/`, `openspec/changes/` (except READMEs if you copy docs manually)

## Steps

1. Confirm the project root contains `.cursor/rules` (template-based project). If the project was installed only via `ai_rules_1c` `install.ps1 init` and never used this template, ask before overwriting.

2. Optional overrides in `.dev.env` (create keys if missing):

```env
RULES_TEMPLATE_URL=https://github.com/mikhailchuklay/1c-project-template.git
RULES_TEMPLATE_REF=master
```

<<<<<<< template
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
=======
The PowerShell channel applies every adapter frontmatter transform (including OpenCode `toolsToPermission` and Claude Code / Kimi / Qwen `toolsToDenylist`) and runs both agent frontmatter gates before reporting success. Prefer it over the agent channel whenever `git` / PowerShell are available.

3. Check installer output:
   - `Update complete.` — success;
   - `User-modified files detected: N` / files left at previous version — local edits preserved; use `-Force` / `-ForcePaths` only when the user wants the shipped version;
   - `Verification OK` / `Verification found N mismatch(es)` — hash check of freshly placed files;
   - `OpenCode agent frontmatter OK` — OpenCode gate passed (or skipped when `.opencode/agent/` is absent);
   - `OpenCode agent frontmatter INVALID` / exit code 1 — **update failed the hard gate** (see Step 5). Do not treat the run as successful.
   - `Agent tool vocabulary OK` — the Claude Code / Kimi / Qwen gate passed (or skipped when none of those agent directories exists);
   - `Agent tool vocabulary INVALID` / exit code 1 — **update failed the hard gate** (see Step 5). Do not treat the run as successful.
>>>>>>> vendor-HEAD

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-from-template.ps1
```

<<<<<<< template
Dry-run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-from-template.ps1 -DryRun
```

Skip overwriting `AGENTS.md` / `.dev.env.example`:
=======
   **OpenCode hard obligation on the agent channel.** When `opencode` is an active tool (or `.opencode/agent/` exists), every placed agent file **must** go through `adapters/opencode.yaml → agents.frontmatter.toolsToPermission` before write-back: convert the source `tools` array into a `permission` object, then apply `keep` / `drop` / `rename` / `addIf` so that `tools`, `modelTier`, `isSubagent`, and `allowParallel` are **not** left in the file. Copying `.cursor/agents/*.md` into `.opencode/agent/` verbatim is a defect — OpenCode rejects a `tools` array and will not start. Canon — `AGENT-INSTALL.md → OpenCode agents: tools array → permission object`.

   **Claude Code / Kimi / Qwen hard obligation on the agent channel.** For those tools every placed agent file **must** go through `adapters/<tool>.yaml → agents.frontmatter.toolsToDenylist` before write-back: turn the source `tools` array into that host's `disallowedTools` string and emit no `tools` key. Copying `.cursor/agents/*.md` verbatim is a defect — the abstract `Shell` / `MCP` match nothing there, and the subagent silently loses shell and every MCP server. Canon — `AGENT-INSTALL.md → Claude Code / Kimi / Qwen agents: tools array → disallowedTools`.

   **Cursor hard obligation on the agent channel.** Placed Cursor agent files **must** go through `adapters/cursor.yaml → agents.frontmatter.toolsToFlag`: emit no `tools` key (Cursor does not document the field) and set `readonly: true` on the agents whose source list grants none of `Write` / `Edit` / `Shell`. Canon — `AGENT-INSTALL.md → Cursor agents: tools array → readonly`.

5. **Mandatory post-update gates (both channels).** After the update, if `.opencode/agent/` or `.opencode/agents/` exists, verify that **no** agent markdown still has a `tools` **array** in its YAML frontmatter:
>>>>>>> vendor-HEAD

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-from-template.ps1 -SkipAgentsMd -SkipDevEnvExample
```

4. After sync:

<<<<<<< template
- Diff `AGENTS.md` if the project had local edits — merge back anything project-specific into `USER-RULES.md` or contribute to the template.
- If `.dev.env.example` gained new keys (e.g. `CONFIG_STORAGE_*`), copy them into `.dev.env`. For storage: ask once whether the project uses configuration storage (`TEMPLATE.md` §2).
- Reload the Cursor window if slash commands look stale.

## Not in scope
=======
   Then, if `.claude/agents/`, `.kimi-code/agents/`, `.qwen/agents/`, `.cursor/agents/`, `.commandcode/agents/`, `.zcode/agents/` or `.mimocode/agents/` exists, verify that no agent markdown there still names an abstract tool:

```powershell
Get-ChildItem .claude\agents, .kimi-code\agents, .qwen\agents, .cursor\agents, .commandcode\agents, .zcode\agents, .mimocode\agents -Filter *.md -File -ErrorAction SilentlyContinue |
  ForEach-Object {
    if ((Get-Content $_.FullName -Raw) -match '(?m)^(tools|disallowedTools):.*\b(Shell|MCP)\b') {
      "FAIL: $($_.FullName)"
    }
  }
```

   - Any match → **update is incomplete / failed**. Report FAIL, list the files, and repair by re-running the PowerShell channel with `-ForcePaths` on the affected agents directory (or re-applying `toolsToDenylist` / `toolsToFlag` correctly on the agent channel). Do not tell the user the update succeeded, and do not "repair" it by deleting the `tools` line — that leaves the read-only agents unrestricted.
   - If none of those agent directories exists → skip this gate.

6. Recommend restarting the AI client (OpenCode in particular) so it re-reads agent definitions and MCP config.

7. **MCP-effectiveness reminder when the bundle is absent.** After a successful update, if 1C MCP tools are not exposed in the current session **and** `.dev.env` `SUPPORT_KEY` is empty **and** `.ai-rules.json` does not have `integrations.mcp.mode = "external"` — print the same reminder as after `init` (`AGENT-INSTALL.md`, section *Remind about MCP servers when the bundle is absent*; https://vibecoding1c.ru/mcp_server). Skip it when any of those signals is present. Do not open the `/installtools` menu solely for this reminder.

8. Compare the installed `install*.md` command names from the pre-update manifest with the updated ruleset. If one or more tool installers were added, show their names and execute `installtools.md` as the next procedure in the same interactive agent task. A PowerShell-only run cannot start a new AI command, so its report must tell the user to restart and run `/installtools`. The general command owns the MCP bundle question and all optional-tool choices; do not invoke `/installmcp` separately from this post-update flow. If no installer was added, do not interrupt the user with the tool menu.

## Parameters
>>>>>>> vendor-HEAD

Refreshing the template itself from `comol/ai_rules_1c` — that is a **template maintainer** task (`install.ps1` / export into the template repo), not a per-project `/updaterules`.
