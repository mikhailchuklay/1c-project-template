# 1C Development Rules

# Process

## Core Principles

Apply senior-level 1C/BSL expertise within the active role's scope and permissions. Documentation is authoritative: verify platform APIs, metadata and version-dependent behaviour before use; produce reviewable, reversible changes.

- Prefer existing project code, platform mechanisms, БСП and fitting templates over new code.
- **Codebase conventions first:** follow the edited module, then its subsystem. Style may yield; ВерблюжьяНотация identifiers, correctness, security, data integrity and hard gates never yield.
- Current source outranks stale summaries; be explicit about evidence, uncertainty, residual risk and unfinished work.

## Active model adaptation

`AGENT_MODEL` in `.dev.env` (`opus5`, `sonnet5`, `fable5`, `gpt56`, `gpt6`) selects one profile, `.cursor/rules/model-<slug>.mdc`, read before the first non-trivial task. A known running model overrides a mismatched value (say so, suggest `/rulesmodel`); empty, invalid or no profile → base rules, never a neighbour, never ask. Profiles never relax gates (`.cursor/rules/model-adaptation.mdc`).

## Development Procedure

### Triage: Quick-fix vs Docs-fix vs Spec-authoring vs Full-cycle

Load `.cursor/rules/verification-policy.mdc` for triage and gates; task paths are independent of `/sdlc` QA profiles.

1. **Docs-fix** — prose only, no BSL/metadata or verifiable 1C claims: structural checks of edited files and direct references, no BSL validators.
2. **Spec-authoring** — OpenSpec with concrete 1C facts: confirm them via MCP first (`.cursor/rules/sdd-integrations.mdc`).
3. **Quick-fix** — one logical change in one module within `QUICKFIX_MAX_LINES` (default 40) or one isolated unwired metadata addition: two-line plan → edit → gates at `VERIFICATION_DEPTH`.
4. **Full-cycle** — everything else or material doubt: steps 1–5 to Definition of Done; review and behavioural confirmation unless explicitly waived. UI criteria follow `UI_TESTING`.

Transactions/posting, public contracts, wired metadata, adopted extension objects, RLS, subscriptions and scheduled jobs are full-cycle at any size. Reduced planning never waives validation or metadata tooling.

### 1. Think Before Coding — Clarify Scope First

Before editing, plan files, changes, success checks, risks and rollback; name a simpler approach if one exists; resolve low-risk ambiguity with a stated assumption. For optimization, link the technical metric to the user's business goal.

**Material fork → stop dependent work and ask using CONFUSION.** Triggers: data integrity, transactions/posting, metadata shape, public contracts, security/RLS, hard-to-reverse choices; conflict with existing code, БСП or supported versions; unspecified material handling of duplicates, missing data, external failures or an empty period.

```text
CONFUSION: <conflict / ambiguity>
Options:
  A) <option> — <consequences>
  B) <option> — <consequences>
→ Which one to pick?
```

### 2. Simplicity First — Minimal Code Only

Only the requested behaviour: no speculative features, cleanup, logging, tests or abstractions; handle realistic edge cases. Document public APIs and non-trivial logic; no placeholders or unfinished work.

### 3. Surgical Changes — Locate the Exact Insertion Point

One logical change at a time; every changed line traces to the task. Read the edit target, preserve others' edits, remove only what your change made unused; mention unrelated defects instead of fixing them.

### 4. Goal-Driven Verification — Double-Check Everything

Define observable success (reproduce the bug, enumerate invalid inputs, keep behaviour across a refactor); check side effects and downstream impact; run applicable gates of `.cursor/rules/verification-gates.mdc` on the final state. Missing tools or exhausted budgets are not passes.

### 5. Deliver Clearly

Report changes, every modified file, checks and real limitations; for non-trivial BSL/metadata/spec work also the context sources used and relevant omissions. Evidence lines, only those that apply: `Memory:`, `Template:`, `Docs:`, `Metadata tooling:`, `IB tooling:`, `Repository tooling:`. Contract: `.cursor/rules/verification-delivery.mdc`.

## Project info

- Project context: `openspec/project.md` when present. Settings: `.dev.env` — never guess or duplicate values; ask only for one the current operation needs (`.cursor/rules/dev-standards-env.mdc`).
- Read root `USER-RULES.md`, `memory.md` and, when present, `LLM-RULES.md`; precedence `USER-RULES.md`/`memory.md` → `LLM-RULES.md` → this file and on-demand rules. Unreachable required rule → report the gap, stop only dependent work.
- **Language:** rules and `content/` prose — English; BSL identifiers/comments/literals, metadata synonyms, user-facing strings, replies and top-level human docs — Russian.
- Monthly: on the first non-trivial task check `.ai-rules.json` `lastUpdatesCheckAt` (else `updatedAt`/`installedAt`); missing or over 30 days → `.cursor/rules/support-feedback.mdc §4`, read-only `/checkupdates` once at the end, never auto-update.

### Path convention — source vs. installed copies

`.cursor/rules/<name>.mdc`, `.cursor/agents/<name>.md`, `.cursor/commands/<name>.md`, `.cursor/skills/<name>/SKILL.md` name the source or the active tool's installed copy — match by file name (Cursor `.mdc`), never a second vendor tree. `standards(name="<name>")` comes **only** from 1C-docs-mcp; disk routers hold headings, no URL/local fallback (`.cursor/rules/help-corpus-retrieval.mdc`).

# Tooling & Standards

## MCP Tool Calling

**Hard gate:** before the first non-memory 1C MCP call (per session; per subagent run), and before writing or reviewing BSL/metadata or a 1C-fact spec, read `.cursor/rules/mcp-policy.mdc` in full, `.cursor/skills/mcp-1c-tools/SKILL.md`, then the selected operation skill. This applies even when no server is exposed. Memory-only operations enter through `.cursor/rules/project-memory.mdc`; they do not load the 1C policy/router.

### A. Priority and obligation

`mcp-policy.md → A. Priority and obligation` owns tool selection and minimum evidence, scoped source search, platform-first discovery, template reuse and ITS retrieval. Load `.cursor/rules/mcp-first-search.mdc` before 1C source discovery. Platform APIs must be verified before use; a fitting template is the base; ITS search hits require full retrieval. Saved BSL follows `syntaxcheck_file` → `check_1c_code` → `review_1c_code` at the active depth; XML requires `verify_xml`.

### B. Limits and non-determinism

`mcp-policy.md → B. Limits and non-determinism` and `verification-policy.md` own validator budgets. AI output is a draft; a required check without a clean confirming result is unverified.

### C. Call discipline

`mcp-policy.md → C. Call discipline and server answers` owns bounded recovery. Each call closes a gap; no unchanged repeats. Batch independent calls, prefer structural searches and use documented arguments. A closed lane stays closed.

## Coding Standards

Before writing or reviewing BSL/metadata, load `.cursor/rules/coding-standards.mdc`; it routes domain rules and `standards(name=…)` — load only what applies.

## Skills and Subagents

- **Metadata mutations:** `.cursor/skills/1c-metadata-manage/SKILL.md` or `1c-metadata-manager`; hand edits only within the skill's exceptions, context checked before, XML after.
- **Infobase operations:** matching command procedure or `db-ops`/`web-ops`, never ad-hoc `1cv8.exe`/`ibcmd`; keep escaping, logs, sessions and retries (`.cursor/commands/update1cbase.md`).
- **Configuration repository:** `REPOSITORY_PATH` set → `.cursor/skills/1c-repository-manage/SKILL.md`: lock before edit, commit after verify; never unbind or clear the setting to bypass locks, even on request.
- **Vendor support:** never bypass a locked-object refusal with XML edits; prefer an extension; `support-edit` only as a stated decision (`.cursor/skills/1c-metadata-manage/docs/support-manage.md`).
- **Delegation:** `.cursor/rules/subagents.mdc` (+ `.cursor/rules/subagent-pipeline.mdc` for delegated full-cycle, `.cursor/rules/orchestrator-economy.mdc` when `ORCHESTRATION=economy`); subagents inherit these gates and `.cursor/rules/subagent-core.mdc`. Exploration — project `1c-explorer` only, never a host's generic explorer.
- **Style and helpers:** `CAVEMAN` → `.cursor/skills/caveman/SKILL.md` (code, evidence, errors and safety steps stay exact); Windows shell → `powershell-windows`; other skills load by description.

# Discipline

## Project memory

Before memory operations, 1C changes or correction capture, load `.cursor/rules/project-memory.mdc` and its shared tool policy. Recall scope, durable writes and failure recovery live there. With no eligible memory tools, load `.cursor/rules/memory-setup.mdc` once per session. Save corrections in the same turn; no secrets/PII.

## Rules self-improvement (`/evolve` + `LLM-RULES.md`)

Only a user-requested `/evolve` writes `LLM-RULES.md`. Friction → `rule-friction:` memory note, never an unsolicited rule edit; recommend `/evolve` at most once per session, after two signals for one behaviour or a permanent-change request. Product defects → `.cursor/rules/support-feedback.mdc`; maintaining this source ruleset is ordinary work.

# Additional rules (load on demand)

Load `.cursor/rules/<name>.mdc` on its trigger only; routers pull companions and domain standards.

- settings, platform/ИБ, UI-test policy → `dev-standards-env`
- typical-code changes, metadata naming → `dev-standards-change-markers`
- new or restructured module / query / managed form → `module-structure` / `query-design` / `forms`
- code, review, debug, refactor, performance, metadata work → `tooling-playbooks`
- `USE_EDT=true` → `edt-workflow`; several source contours → `multi-contour-search`
- applying a configuration/extension, missing MCP validators → `designer-batch-checks`
- UI tests → `ui-testing-tools` → QA MCP: skill `1c-qa-testing` + `qa-testclient`; web: `web-client-driving`
- extract from ИБ → `getconfigfiles`; integrations → `integrations-add`
- metadata hand-edit within a skill exception → `metadata-xml-workarounds`

# Project overlays (1c-project-template)

This project was created from `mikhailchuklay/1c-project-template`; the vendored ruleset above is `comol/ai_rules_1c`. The overlays below are the only project-specific additions — everything else is vendor canon.

- **Rules update:** `/updaterules` runs `tools/update-from-template.ps1` (template is the source of truth for `.cursor/rules`, skills, agents, commands), **not** the vendor `install.ps1`. The monthly updates check (`.cursor/rules/support-feedback.mdc §4`) is `tools/update-from-template.ps1 -DryRun`, not `/checkupdates`; a vendor-side `/checkupdates` result is informational only. Project initialization — `TEMPLATE.md`.
- **Standalone dev environment:** file infobase under `ibsrv` with its own web publication (`tools/dev-standalone/start.ps1` / `stop.ps1`, `docs/dev-environment.md`). Vendor `web-ops` (Apache) stays available for server infobases; do not mix the two on one base.
- **`1c-data-mcp` on a non-anonymous publication** (`ibsrv`, or IIS / Apache not published anonymously): native tools stay hidden (Cursor sends no `Authorization`); call the service with Basic through `tools/dev-standalone/Invoke-DataMcp.ps1` — never `mcp_auth`, never the COM connector. Readiness gate and test-data discovery before a behavioural check — `.cursor/rules/1commerce-functional-testing.mdc`. Details — `.cursor/skills/mcp-1c-tools/docs/1c-data-mcp.md`.
- **`rlm-tools-bsl`** — availability substitute for the project-index lane only: when neither graph nor code-metadata is exposed for the contour and `rlm_start` is, RLM runs before native search (`.cursor/skills/mcp-1c-tools/docs/rlm-tools-bsl.md`, setup `docs/rlm-setup.md`, rule `rlm-project-setup`).
- **`v8std`** — v8std.ru standards and BSLLS / ACC / EDT diagnostic bridge; complements ITS, never replaces `its_help` → `fetch_its` for normative decisions (`.cursor/skills/mcp-1c-tools/docs/v8std-mcp.md`).
- **Project-specific rules (load on their trigger):** `1commerce-functional-testing` — proving behaviour on a live infobase (`1c-data-mcp` vs UI, readiness gate); `1commerce-bsp-integration-checklists` — БСП hook checklists for new documents, print, input-based-on, form blocking, multi-extension layout; `headless-agent` — unattended agent runs (`docs/headless-agent.md`); `devbox-setup-discovery` — discovering the company devbox-managed environment; `rlm-project-setup` — RLM index of the dump.
- **Validators:** `cfe-validate` carries project checks 20–21 (role rights on non-securable types, exchange-plan content) after the vendored 1–19 — run it before every load of an extension from XML.

# Spec-driven development workspace

`openspec/specs/` is current behaviour, `openspec/changes/` holds change artifacts; before OpenSpec work load `.cursor/rules/sdd-integrations.mdc` (owns full-cycle DoD and apply completion).
