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

<<<<<<< template
**Define success criteria. Loop until verified.**

- Transform imperative tasks into verifiable goals before implementing:
  - "Add validation" → describe the invalid scenarios, then verify the code rejects them.
  - "Fix the bug" → reproduce the failing case, then verify the fix eliminates it.
  - "Refactor X" → fix observable behavior up front, then verify it is unchanged before and after.
- For multi-step tasks, state a brief plan with explicit verification points:

  ```
  1. [Step] → check: [control]
  2. [Step] → check: [control]
  3. [Step] → check: [control]
  ```

- Use the applicable verification toolset as concrete success criteria. For BSL / metadata changes: `syntaxcheck`, `check_1c_code`, `review_1c_code`, ITS standards lookup, routine-call analysis via `trace_call_chain`, and object-level impact analysis via `trace_impact`. For Markdown / rules / documentation: verify referenced paths, links, structure, and internal consistency.
- **Managed-form / programmatic UI changes** (`Form/Module.bsl` with `Элементы.Добавить`, `ИзменитьРеквизиты`, `Переместить`, or form event handlers): static gates alone are **not** sufficient — `syntaxcheck` does not validate runtime form-element properties. Load `verification-gates.mdc` (Gate 6) and `1commerce-functional-testing.mdc` (§ Programmatic form runtime gate) before declaring done. Passing API-only functional tests (e.g. integration probes via `1c-data-mcp`) does **not** substitute for form verification.
- Review the proposed changes for correctness, scope adherence, and side effects. Verify alignment with existing codebase patterns and absence of regressions.
- Explicitly verify whether anything downstream will be impacted.

Strong success criteria let you loop independently. Weak criteria ("make it work") force constant clarification.
=======
Define observable success (reproduce the bug, enumerate invalid inputs, keep behaviour across a refactor); check side effects and downstream impact; run applicable gates of `.cursor/rules/verification-gates.mdc` on the final state. Missing tools or exhausted budgets are not passes.
>>>>>>> vendor-HEAD

### 5. Deliver Clearly

Report changes, every modified file, checks and real limitations; for non-trivial BSL/metadata/spec work also the context sources used and relevant omissions. Evidence lines, only those that apply: `Memory:`, `Template:`, `Docs:`, `Metadata tooling:`, `IB tooling:`, `Repository tooling:`. Contract: `.cursor/rules/verification-delivery.mdc`.

## Project info

<<<<<<< template
The canonical project context (configuration name, platform version via `CompatibilityMode`, form mode, БСП version, top-level subsystems, metadata counts) lives in [`openspec/project.md`](openspec/project.md), generated by the installer on `init` / `update` when the project contains `Configuration.xml`. When the file is absent (the repo is not a 1C source dump) — treat the project context as undefined, fall back to `.dev.env` for operational parameters, and ask the user for anything not covered there. Absence of `openspec/project.md` is **not** a reason to stop.

Operational parameters (platform version, platform path, infobase connection, web publication, configuration storage, prefix / developer / modification comments, policy for placing new objects) — the single source of truth is [`./.dev.env`](.dev.env). Do not duplicate these values in other files.

**No field in `.dev.env` is globally mandatory.** Every parameter is task-scoped — a missing value matters only when the **current** operation depends on it; do not gather empties up front, and guessing values is PROHIBITED. Canonical classification and per-parameter defaults — `.cursor/rules/dev-standards-env.mdc §1 → "Global principle"`. Headlines: **Advisory** (`PREFIX`, `COMPANY`, `DEVELOPER`) — empty is valid, documented fallback applies, **must not be asked about, ever**; **Highly desirable** (`INFOBASE_PATH`, `PLATFORM_PATH` — IB-bound commands; `INFOBASE_PUBLISH_URL` — UI tests) — ask once, **only when the current task actually runs such an operation**, then proceed; **Defaulted** (everything else, incl. `IB_USER` / `IB_PASSWORD`, `UI_TESTING`, `SUBAGENT_MODEL_*`, `AGENT_MODEL`, `ORCHESTRATION`, `QUICKFIX_MAX_LINES`, `DEBUG_FAST_PATH`, `VERIFICATION_DEPTH`) — empty resolves to a documented default, no question; re-ask credentials only after an authentication error, `LOG_PATH` only if the resolved path is non-writable.

**Project overlays (1c-project-template):**

- **`INFOBASE_PUBLISH_URL` and Gate 6** — beyond the `1c-tester` subagent and `/deploy-and-test`, it is needed by **mandatory Gate 6** (`.cursor/rules/verification-gates.mdc`) when the agent delivers changes to managed-form runtime behaviour (programmatic form setup, form events, layout visibility). Empty `INFOBASE_PUBLISH_URL` = UI smoke cannot run automatically; the agent **must not** mark form/UI tasks done — record *"Gate 6 blocked — no publish URL"* in the delivery summary and leave `tasks.md` items unchecked until UI verification runs. Do **not** ask the user to manually test instead of running the gate when the URL is present. Ask for the URL **only** when Gate 6 is in scope and the value is empty. For analysis / review / documentation tasks with no form delivery, empty is fine.
- **Highly desirable for configuration storage** (`CONFIG_STORAGE_ENABLED`, `CONFIG_STORAGE_URL`, `CONFIG_STORAGE_USER`, `CONFIG_STORAGE_PASSWORD`) — when `CONFIG_STORAGE_ENABLED=true`, load `.cursor/rules/configuration-storage.mdc` and skill `1c-configuration-storage` before editing configuration objects destined for the IB / `src/cf`. Empty password omits `/ConfigurationRepositoryP`. **Failed lock (object held by another user) is a blocker** — do not import / apply / `/LoadConfigFromFiles` into the IB until lock succeeds for every object of the change; a file IB bound to storage still requires the lock. **Project init (exception to “do not gather empties up front”):** when creating or first filling `.dev.env` / following `TEMPLATE.md`, the agent **MUST ask once**: does this project develop via 1C configuration storage (хранилище)? If **yes** — set `CONFIG_STORAGE_ENABLED=true` and ask for URL, user, password (password may be empty). If **no** — set `CONFIG_STORAGE_ENABLED=false` (or leave empty = off). Outside init: if `ENABLED` is still unset and a storage-bound config edit is in scope — ask the same question once; do not invent values.

- The project is entirely in 1C (bsl) — no other programming languages.
- **Source language policy.**
  - `AGENTS.md`, `USER-RULES.md`, `LLM-RULES.md`, `memory.md`, `References.md`, and every file under `.cursor/rules/`, `.cursor/agents/`, `.cursor/skills/`, `.cursor/commands/` — written in **English**. This is the neutral working language for AI agents and keeps the rules portable across tools.
  - BSL code (identifiers, comments, string literals) — written in **Russian**, following 1C conventions.
  - Metadata synonyms, presentations, user-facing strings, event-log messages — **Russian**.
  - The agent replies to the user in **Russian**.
  - `README.md` and other human-facing top-level docs — **Russian**.
- `USER-RULES.md` and `memory.md` (project root) — additional rules; on conflict they override or extend this file. If a referenced file is unreachable, stop and tell the user instead of proceeding with a degraded ruleset. This rule applies to files that this document hard-requires (`mcp-1c-tools` skill, the on-demand rules in `.cursor/rules/` referenced from sections below) — not to optional artifacts whose absence is explicitly handled (e.g. `openspec/project.md` above, `LLM-RULES.md` below).
- `LLM-RULES.md` (project root) — the agent-maintained self-improvement layer: behavior rules distilled from observed friction and approved by the user, written **only** by the `/evolve` command (`.cursor/commands/evolve.md`). Read it together with this file when present. Precedence on conflict: `LLM-RULES.md` overrides this file and the on-demand rules; `USER-RULES.md` and `memory.md` override `LLM-RULES.md`. Absence of the file = no accumulated rules yet, **not** an error. Capture and recommendation discipline — `## Rules self-improvement` below.
=======
- Project context: `openspec/project.md` when present. Settings: `.dev.env` — never guess or duplicate values; ask only for one the current operation needs (`.cursor/rules/dev-standards-env.mdc`).
- Read root `USER-RULES.md`, `memory.md` and, when present, `LLM-RULES.md`; precedence `USER-RULES.md`/`memory.md` → `LLM-RULES.md` → this file and on-demand rules. Unreachable required rule → report the gap, stop only dependent work.
- **Language:** rules and `content/` prose — English; BSL identifiers/comments/literals, metadata synonyms, user-facing strings, replies and top-level human docs — Russian.
- Monthly: on the first non-trivial task check `.ai-rules.json` `lastUpdatesCheckAt` (else `updatedAt`/`installedAt`); missing or over 30 days → `.cursor/rules/support-feedback.mdc §4`, read-only `/checkupdates` once at the end, never auto-update.
>>>>>>> vendor-HEAD

### Path convention — source vs. installed copies

`.cursor/rules/<name>.mdc`, `.cursor/agents/<name>.md`, `.cursor/commands/<name>.md`, `.cursor/skills/<name>/SKILL.md` name the source or the active tool's installed copy — match by file name (Cursor `.mdc`), never a second vendor tree. `standards(name="<name>")` comes **only** from 1C-docs-mcp; disk routers hold headings, no URL/local fallback (`.cursor/rules/help-corpus-retrieval.mdc`).

# Tooling & Standards

## MCP Tool Calling

<<<<<<< template
The single source of truth for MCP server catalog, task→tool mapping, and fallback order is the **`mcp-1c-tools`** skill (`.cursor/skills/mcp-1c-tools/SKILL.md`). Load it before choosing 1C MCP tools; load the matching `.cursor/skills/mcp-1c-tools/docs/<server>.md` only for parameter-rich calls or when arguments are not obvious. A server counts as available only when its tools are exposed in the current session.

**Exception — `1c-data-mcp` when `/hs/mcp` is not anonymous.** On IIS / Apache the publication should be anonymous (`default.vrd`): that is what makes the native tools appear. The standalone server (`ibsrv`) is not anonymous, and neither is an IIS / Apache publication that was left requiring authentication. In every non-anonymous case the call is the same. Cursor's MCP client does not send `Authorization`, so the native tools stay out of the session even though the service is up. That is not "server unavailable" and not an OAuth `needsAuth` state: do **not** call `mcp_auth`, and do **not** connect through the COM connector. Load `.cursor/rules/1commerce-functional-testing.mdc` and call `tools/dev-standalone/Invoke-DataMcp.ps1` with HTTP Basic of `IB_USER` and `IB_PASSWORD` from `.dev.env`. The password is that infobase user's password; do not assume it is empty. A blank `IB_PASSWORD` means this user really has an empty password and the header is still sent — unlike Designer/ibcmd, where a blank `IB_PASSWORD` omits `/P`. On `ibsrv` an anonymous `GET` returns **503** and the same call with Basic returns **200**. Start and stop `ibsrv` only through `tools/dev-standalone/start.ps1` and `stop.ps1` — a raw `Stop-Process` leaves `lock.pid` / registry locks, and the next start then fails or is skipped.

Step-by-step playbooks per task type (writing code, review, architecture, error fixing, performance, refactoring, metadata XML, forms, integrations, documentation, platform-version comparison) live in `.cursor/rules/tooling-playbooks.mdc`.

### A. Priority and obligation

1. **Mandatory scope.** MCP calls are mandatory only for risk-bearing 1C work when a relevant server is exposed: BSL / metadata edits or review, metadata XML, forms, integrations, refactoring, performance, runtime errors, platform API checks, impact analysis, syntax / quality validation, project-memory operations, **and OpenSpec spec authoring whenever the artifact references concrete 1C facts** (metadata names, attributes, tabular sections, public API signatures, БСП subsystems, platform-version behaviour, project conventions — see the spec-authoring path in `## Development Procedure → Triage` and `.cursor/rules/sdd-integrations.mdc`). Generic Markdown / rules / documentation work that makes no such factual claims does not require 1C MCP calls; validate structure, links, paths, and internal consistency instead.
2. **Conditional external knowledge.** Use platform docs, БСП / SSL, and ITS MCP tools when the task depends on versioned platform behavior, reusable БСП APIs, or standards compliance. Do not call them for generic prose cleanup or rule-file editing unless such a fact is actually needed.
3. **Verify before writing BSL / metadata / specs — scoped hard gate.** Use the minimum evidence set from `tooling-playbooks`: quick-fix BSL edits use only the directly relevant code / syntax context; full-cycle BSL changes use templates, existing project code, metadata, and platform / БСП / ITS docs when those sources affect correctness; metadata XML / form changes use schema, examples, and metadata validation; **OpenSpec spec authoring** uses `recall` for prior project notes plus the MCP tools that confirm every 1C fact the spec references (metadata graph / code-metadata for object shape, platform / БСП / ITS docs for API and standards) — see `.cursor/rules/sdd-integrations.mdc`. In the final answer for any non-trivial BSL / metadata change **or non-trivial OpenSpec spec authoring (proposal / design / tasks / delta specs that reference real 1C objects, APIs, or БСП subsystems)**, list the context sources actually used and briefly state why any normally relevant source was skipped. Skipping a relevant source silently counts as a defect.
4. **No blind chaining.** Every MCP call must close a concrete context gap. Follow the fallback order from `mcp-1c-tools`; do not duplicate calls or continue the chain after you already have enough evidence. If `1c-graph-metadata-mcp` returns empty / non-actionable results twice on substantially different queries for the same target, fall back to `1c-code-metadata-mcp` (hybrid → `grep=true`) instead of further graph attempts. If **neither** graph **nor** code-metadata is exposed in the session, and `rlm-tools-bsl` is exposed, use it for project-source search before native tools (availability substitute — not a third search when graph/code-metadata are up). Before using **any native discovery tool** on 1C project source — `Grep` / `rg`, `Glob` / file search by pattern (`**/*.bsl`, `**/*.xml`), directory listing, semantic codebase search, `Read`-scanning of modules to locate something, or a full-module `Read` made just to find / understand one routine (prefer `get_module_structure` / `search_code` (`detail_level="L0"`) / `search_function`) — first exhaust the project-index search path from `mcp-1c-tools`, including the documented `grep=true` retry where applicable, and state why those attempts were insufficient. "Getting oriented" by globbing source trees or bulk-reading modules while project-index MCP servers are exposed is the same defect as a silent `Grep`. **The priority is bounded, not a ban:** when the project-index servers are not exposed (and `rlm-tools-bsl` is not either), native tools apply immediately (state it once, in one line); when a tuned attempt plus the documented retry returned nothing relevant, or the index is stale against fresh local edits, falling back to native search / reading is the correct next move — burning further MCP calls just to satisfy this rule is itself blind chaining. Reading your direct edit target or a file already located via MCP is normal work, not a fallback; the full boundary list — `.cursor/rules/mcp-first-search.mdc`.
5. **Validate changed 1C code.** After BSL / metadata edits: `syntaxcheck` → `check_1c_code` → `review_1c_code`, within the verification budget defined in section B below. For metadata XML use schema / XML validation; metadata **mutations** go through the `1c-metadata-manage` skill per the hard gate in `## Skills and Subagents` — hand-editing outside its documented exceptions is a defect, not a stylistic choice. Here and throughout this ruleset, `syntaxcheck` means the `1c-syntax-checker-mcp` validator step: when the session also exposes `syntaxcheck_file`, prefer it — checking the saved file by path (optionally line-filtered) is more economical than passing code text; the two tools share one validator budget. Details — `.cursor/skills/mcp-1c-tools/docs/1c-syntax-checker-mcp.md`.
6. **ITS documents.** Always follow `its_help` with `fetch_its` for every returned document ID you rely on.
7. **Platform-capability check before custom implementations in specialized domains.** When a task requires a capability beyond plain business logic — cryptography / digital signatures, solving systems of linear equations (СЛАУ) and other numerical methods, data analysis / machine learning, the collaboration system and its bots (СистемаВзаимодействия), integration buses / message queues, full-text search, regular expressions, and similar unique platform features — first ask the platform documentation MCP whether the platform already ships such a mechanism (`1C-docs-mcp`: `docsearch` by capability description → `docinfo` for every exact name found), and check БСП via `ssl_search` where a library-level solution is plausible. **Model memory is not evidence of absence** — these mechanisms are exactly what training data tends to miss, while the docs MCP indexes the real platform documentation. **When a platform or БСП mechanism is found and usable — use it** as the foundation (types, methods, subsystems, virtual tables); custom code only for glue, parameters, and project wiring — **do not** design a parallel home-grown equivalent. **Near-fit is not a rejection.** If the found mechanism covers the core need but seems slightly inconvenient (awkward API, extra conversion step, partial coverage that can be closed with thin glue code) — that is **not** grounds to hand-roll. On a genuine partial-fit fork (the mechanism covers most but not all of the requirement), raise a `CONFUSION` block — platform mechanism + glue vs. full custom implementation, with trade-offs — and let the user decide; **when asking is impossible** (autonomous / batch run, no operator) — **default to the platform mechanism** and note the residual gap in the final answer. Rejecting a found mechanism on your own authority is allowed only for hard evidence: platform version / `РежимСовместимости` incompatibility or a doc-confirmed functional mismatch with the core requirement — **state the reason** in the final answer. Hand-rolling without the capability check is a defect; hand-rolling when a usable mechanism was found is also a defect. Query patterns and the domain trigger list — `.cursor/skills/mcp-1c-tools/docs/1C-docs-mcp.md → Platform capability discovery` and *Using a found platform mechanism*.
8. **`templatesearch` `query` formulation — applies to this tool only.** The task-description rule applies **exclusively** to the **`templatesearch`** tool on `1c-templates-mcp`. It does **not** govern `query` on `docsearch`, `codesearch`, `search_code`, `metadatasearch`, `ssl_search`, `recall`, or any other MCP tool. Before the first **`templatesearch`** in a session, load `.cursor/skills/mcp-1c-tools/docs/1c-templates-mcp.md → Query formulation (templatesearch only)` and run its pre-flight on every **`templatesearch`** call: first call — the user's task text verbatim or a same-goal prose paraphrase; on a miss — reformulate as a different task description (still prose, never keywords); keyword salad (e.g. `уровень иерархии … запрос КОЛИЧЕСТВО`) is a defect equal to skipping the tool.
9. **`templatesearch` — reuse, do not reinvent.** When **`templatesearch`** returns a template that solves the same task (same goal, acceptable algorithm / query shape) — **start from that template**: take its code or query as the base and adapt only what the task requires (metadata names, field list, filters, module placement, call site). **Do not** rewrite the same solution from scratch when a fitting template is already in hand. Ignoring a matching template and hand-rolling an equivalent is a defect. If you adapted non-obvious parts, note briefly what changed and why. **Disposition (lightweight, goal-matching templates only):** when a template is used as the base — name it in one line in the final answer (`Template: <name> — used as base`); when nothing fits — one short «no fitting template» note is enough. No per-candidate analysis of everything the vector search returned. A delivered solution that shares no recognizable structure with a goal-matching template found during the task is defective and must be redone from the template. **Valid rejection reasons are narrow and must be named:** doc-confirmed version incompatibility, an explicit user requirement, or a nameable project-rule violation in the template itself (an anti-pattern from `.cursor/rules/anti-patterns.mdc`, a forbidden construct from `dev-standards-code-style.md §2`, a documented ITS-standard violation). «I'd rather write it differently» and an unnamed «выглядит неоптимально» are not reasons. A local violation is fixed **inside** the template while keeping its structure (`Template: <name> — used as base, fixed: <anti-pattern>`); full rejection is correct only when the violation is the template's core algorithm (`Template: <name> — rejected: <anti-pattern>`). Canon — `.cursor/skills/mcp-1c-tools/docs/1c-templates-mcp.md → Using a found template` (incl. *Template disposition (lightweight)*).
=======
**Hard gate:** before the first non-memory 1C MCP call (per session; per subagent run), and before writing or reviewing BSL/metadata or a 1C-fact spec, read `.cursor/rules/mcp-policy.mdc` in full, `.cursor/skills/mcp-1c-tools/SKILL.md`, then the selected operation skill. This applies even when no server is exposed. Memory-only operations enter through `.cursor/rules/project-memory.mdc`; they do not load the 1C policy/router.

### A. Priority and obligation

`mcp-policy.md → A. Priority and obligation` owns tool selection and minimum evidence, scoped source search, platform-first discovery, template reuse and ITS retrieval. Load `.cursor/rules/mcp-first-search.mdc` before 1C source discovery. Platform APIs must be verified before use; a fitting template is the base; ITS search hits require full retrieval. Saved BSL follows `syntaxcheck_file` → `check_1c_code` → `review_1c_code` at the active depth; XML requires `verify_xml`.
>>>>>>> vendor-HEAD

### B. Limits and non-determinism

`mcp-policy.md → B. Limits and non-determinism` and `verification-policy.md` own validator budgets. AI output is a draft; a required check without a clean confirming result is unverified.

### C. Call discipline

`mcp-policy.md → C. Call discipline and server answers` owns bounded recovery. Each call closes a gap; no unchanged repeats. Batch independent calls, prefer structural searches and use documented arguments. A closed lane stays closed.

## Coding Standards

Before writing or reviewing BSL/metadata, load `.cursor/rules/coding-standards.mdc`; it routes domain rules and `standards(name=…)` — load only what applies.

## Skills and Subagents

<<<<<<< template
- **1C metadata — hard gate, not a preference.** Any **mutation** of metadata structure (creating / editing / removing configuration objects, forms, reports, layouts, roles, extensions, databases) is executed **through the `1c-metadata-manage` skill** (or the `1c-metadata-manager` subagent): read its `SKILL.md`, dispatch to the domain doc, drive the change with the skill's tools. Hand-editing metadata XML / `Form.xml` / MXL while the skill is available is a **defect** — same standing as a skipped validator — with exactly the narrow exceptions defined in `.cursor/skills/1c-metadata-manage/SKILL.md → Hard rule` (unambiguous one-line fix; skill not available in the session — state it once). The surrounding MCP evidence set stays mandatory per `.cursor/rules/tooling-playbooks.mdc` (`search_forms` / `inspect_form_layout` / `get_xsd_schema` before, `verify_xml` after). In the final answer of any task that mutated metadata / forms / layouts, state the path in one line: `Metadata tooling: <skill tool / subagent used>` or `hand-edit — <exception>`.
- **1C infobase operations — same hard gate.** Any operation against an infobase — creating / running it, loading or dumping the configuration, updating the DB structure (`/UpdateDBCfg`, `ibcmd infobase config apply`), web publication — is executed through the matching slash-command procedure (`/update1cbase`, `/loadfrom1cbase`, `/getconfigfiles`, `/deploy-and-test`) or the `1c-metadata-manage` skill's `db-ops` / `web-ops` tools. Composing an ad-hoc `1cv8.exe` / `ibcmd` command line from memory while these are available is a **defect**: the command procedures and scripts encode what ad-hoc lines lose — parameter escaping, `/Out` log capture, log parsing for errors hidden behind exit code 0, session termination, safety confirmations, and the **iterative retry discipline** (log check → terminate a hung / failed Configurator → fix → re-run; canon — `.cursor/commands/update1cbase.md → Update retry loop`). In the final answer of any task that ran an infobase operation, state the path in one line: `IB tooling: <command / db-ops script>` or `ad-hoc — <reason: command and skill unavailable>`.
- **Vendor support state — a refusal is a correct outcome.** The skill's mutating tools refuse to edit an object of a typical configuration that is on vendor support and locked ("на замке"), and refuse to delete one not yet taken off support; the run exits non-zero with a diagnostic. **Never route around it** by hand-editing the XML — direct edits silently break future vendor updates, and the hand-edit exceptions above do not cover this case. The default answer is a change **in an extension** (`cfe-borrow` / `cfe-patch-method`); changing support state deliberately is the skill's `support-edit` tool, and it is a decision to state in the report (which object, `editable` / `off-support`, why an extension was not the answer). Canon — `.cursor/skills/1c-metadata-manage/docs/support-manage.md`.
- **Communication style and Tone & Output** — **`caveman`** skill (`.cursor/skills/caveman/SKILL.md`). By default (`.dev.env` `CAVEMAN=on`) active for **all** tasks. `CAVEMAN=auto` restricts it to development tasks (writing / editing / refactoring code, fixing bugs, deploying) and turns it off for analysis, documentation, review and audit tasks; `CAVEMAN=off` disables auto-activation. Toggled by the `/caveman on|auto|off` command (`.cursor/commands/caveman.md`); the parameter is documented in `.cursor/rules/dev-standards-env.mdc`. Levels, safety switches and boundaries are defined inside the skill file. Session-only force (phrases "caveman please" / "stop caveman", `/caveman lite|full|ultra`) works in every mode.
- **Subagents** — when a task feels large / multi-step / multi-module and may be worth delegating — read `.cursor/rules/subagents.mdc` and decide whether to delegate or execute directly. Full subagent prompts live in `.cursor/agents/`; file names omit the `1c-` prefix and are listed in the mapping table in `.cursor/rules/subagents.mdc`. If `.dev.env` has `ORCHESTRATION=economy`, delegation of execution is the default — load `.cursor/rules/orchestrator-economy.mdc` together with `subagents.md`.
- **Exploration — project `1c-explorer` only (hard gate).** When delegating read-only codebase / metadata exploration (locate code, map a subsystem, impact / callers, "where is X / how does Y work"), launch the project's **`1c-explorer`** subagent (`.cursor/agents/explorer.md`, installed as the tool's custom agent — e.g. `.cursor/agents/explorer.md`). **Never** use the host tool's built-in Explore / `explore` / generic scout (Cursor Task `subagent_type: "explore"`, and equivalents). Built-ins cannot be overridden and do not follow the MCP-first chain or 1C report format — using them for project exploration is a defect. Narrow lookups the parent can answer with one direct MCP / read stay on the parent (no subagent). Canon — `.cursor/rules/subagents.mdc → Host-tool built-in explorers`.
- **Subagent obligations.** Every subagent inherits the rules of this file unless its own prompt explicitly overrides one. Concrete shared obligations (CONFUSION format, MCP-first search, verification checklist for mutating work) are spelled out in `.cursor/rules/subagents.mdc → Common obligations` and pointed to from every agent prompt. On material forks, subagents MUST raise the `CONFUSION` block instead of silently picking one interpretation, returning a partial result, or paraphrasing the question into prose; low-risk ambiguity follows the assumption-and-proceed rule from `Development Procedure → 1`.

### Supplementary skills (load on demand)

These skills are not always-on; load them by trigger from the table below. Each skill lives at `.cursor/skills/<name>/SKILL.md`. A skill counts as available only when it is actually exposed in the current session.

| Skill | Load when |
|---|---|
| **`powershell-windows`** | Writing or running shell commands on Windows (slash commands, scripts, deploy / IB flows). Required by the shell-using subagents (`developer`, `tester`, `error-fixer`, `refactoring`, `planner`, `architect`, `analytic`). |
| **`mermaid-diagrams`** | Producing diagrams (architecture, flows, ERD) for plans, designs, PRDs, code maps. |
| **`handoff`** | Compressing the current chat into a self-contained handoff document for the next session. Default path: `handoffs/handoff-<timestamp>.md`. |
| **`prompt-enhancer`** | Turning a short / unstructured note or ТЗ into a numbered imperative spec. Does not add new requirements. |
| **`transcribe`** | Transcribing audio / video (Gemini API): transcript with timecodes, optional summary, `--analyze-ui` for screen recordings. |
| **`md-to-docx`** | Converting Markdown into `.docx`. Requires Node.js and the `docx` package. |
| **`img-grid-analysis`** | Extracting column proportions from screenshots / scans of printed forms for MXL layouts. |
| **`v8unpack-cf`** | Unpacking / repacking 1C binaries (CF / CFE / EPF) into sources (JSON + BSL) **without the 1C platform** — when there is no infobase / Designer / `ibcmd`; for platform-based extraction use the `getconfigfiles` rule. |
| **`1c-configuration-storage`** | Lock / commit / label / unlock in 1C configuration storage; failed lock is a blocker (no IB import). Load when `CONFIG_STORAGE_ENABLED=true` for IB/`src/cf` edits or explicit storage ops. |
=======
- **Metadata mutations:** `.cursor/skills/1c-metadata-manage/SKILL.md` or `1c-metadata-manager`; hand edits only within the skill's exceptions, context checked before, XML after.
- **Infobase operations:** matching command procedure or `db-ops`/`web-ops`, never ad-hoc `1cv8.exe`/`ibcmd`; keep escaping, logs, sessions and retries (`.cursor/commands/update1cbase.md`).
- **Configuration repository:** `REPOSITORY_PATH` set → `.cursor/skills/1c-repository-manage/SKILL.md`: lock before edit, commit after verify; never unbind or clear the setting to bypass locks, even on request.
- **Vendor support:** never bypass a locked-object refusal with XML edits; prefer an extension; `support-edit` only as a stated decision (`.cursor/skills/1c-metadata-manage/docs/support-manage.md`).
- **Delegation:** `.cursor/rules/subagents.mdc` (+ `.cursor/rules/subagent-pipeline.mdc` for delegated full-cycle, `.cursor/rules/orchestrator-economy.mdc` when `ORCHESTRATION=economy`); subagents inherit these gates and `.cursor/rules/subagent-core.mdc`. Exploration — project `1c-explorer` only, never a host's generic explorer.
- **Style and helpers:** `CAVEMAN` → `.cursor/skills/caveman/SKILL.md` (code, evidence, errors and safety steps stay exact); Windows shell → `powershell-windows`; other skills load by description.
>>>>>>> vendor-HEAD

# Discipline

## Project memory

Before memory operations, 1C changes or correction capture, load `.cursor/rules/project-memory.mdc` and its shared tool policy. Recall scope, durable writes and failure recovery live there. With no eligible memory tools, load `.cursor/rules/memory-setup.mdc` once per session. Save corrections in the same turn; no secrets/PII.

## Rules self-improvement (`/evolve` + `LLM-RULES.md`)

Only a user-requested `/evolve` writes `LLM-RULES.md`. Friction → `rule-friction:` memory note, never an unsolicited rule edit; recommend `/evolve` at most once per session, after two signals for one behaviour or a permanent-change request. Product defects → `.cursor/rules/support-feedback.mdc`; maintaining this source ruleset is ordinary work.

# Additional rules (load on demand)

<<<<<<< template
Load the corresponding file when the task matches the rule's scenario. Each entry below is a routing cue only; the authoritative scope description is the frontmatter `description` inside the file itself. Every rule lives at `.cursor/rules/<name>.mdc`.

## Development standards

- **coding-standards** — index of code-style detail files; load before writing or reviewing code.
- **dev-standards-core** — compatibility router for the focused development-standard rules below; load only when following a legacy reference.
- **dev-standards-env** — `.dev.env`, infobase / deployment, UI testing, subagent models, orchestration, and process-tuning parameters; load only when the current task depends on one of them.
- **dev-standards-code-style** — BSL formatting, quality limits, forbidden constructs, naming, public API documentation, typography, comments, and internal review; load for BSL writing or review.
- **dev-standards-change-markers** — typical-code modification markers, metadata naming, and object-type selection; load when modifying typical code or creating / naming metadata.
- **dev-standards-architecture** — architecture patterns, extensions, platform standards, code smells; load for architectural decisions or cross-module review.
- **module-structure** — canonical region templates per module type; load before creating or restructuring a module.
- **extension-patterns** — CFE interceptors, `ПродолжитьВызов`, change markers, adopted-object constraints; load for extension code.
- **dcs-design** — СКД report design; load when designing or reviewing a DCS-based report.
- **dcs-advanced-composition** — two-pass СКД preprocessing (filtering detail records before roll-up) and direct query execution instead of the DCS engine; load only when the override of `dcs-design.md §5` is not enough.
- **bsp-access-rights** — programmatic БСП access-group profiles (`Роли.Роль` is a reference; extension roles) and the right / role / RLS check API; load when code creates, assigns, or checks access rights.
- **registers-design** — register design (dimensions, resources, periodicity, indexing, posting); load when creating or restructuring a register.
- **query-design** — router for query work; load first for any non-trivial query.
- **logging-strategy** — when / what / how to log, severity, category naming, secrets / PII bans; load when adding logging for integrations, background jobs, or transactional rollback.
- **locks-and-transactions** — managed locks, transaction boundaries, deadlock prevention; load for posting / multi-document operations, lock conflicts, or extending a transactional path.

## Model adaptation

- **model-adaptation** — router of the active-model layer: `AGENT_MODEL` resolution, accepted spellings, what a profile may / may not change, and the model-agnostic prompting baseline; load when you need the contract, when `/rulesmodel` runs, or when a profile seems to conflict with a base rule.
- **model-opus5** / **model-sonnet5** / **model-fable5** / **model-gpt56** — behaviour profiles for Claude Opus 5, Claude Sonnet 5, Claude Fable 5 (Mythos 5) and GPT-5.6; load exactly the one matching the running model, once per session.

## Subagents

- **subagents** — subagent catalog, delegation rules, common obligations, model-tier routing, task templates; load when a task may be worth delegating.
- **subagent-pipeline** — full-cycle pipeline (planner → developer → spec-compliance review → optional user-requested code review → verification gate); load for full-cycle tasks delegated to subagents.
- **orchestrator-economy** — economy mode (`ORCHESTRATION=economy` in `.dev.env`, toggled by `/economymode`; a user phrase overrides for the session): parent delegates execution, keeps decisions and verification; load when the mode is on or asked about.

## Forms

- **forms** — router for all managed-form work; load first for any form task.
- **forms-add** — creating or significantly altering a form (`Form.xml` + module) plus form-presentation rules.
- **form-patterns** — layout archetypes, naming conventions, advanced ERP patterns; load when designing a layout from scratch or when placement is unspecified.
- **form-module** — form-module code: event-handler wiring, reserved property names; load when editing form-module logic or adding event handlers.
- **async-methods** — `Асинх` / `Ждать` / `Обещание` (8.3.18+); load for client-side async code.

## Tooling

- **tooling-playbooks** — step-by-step MCP playbooks per task type; load at the start of a matching task; for any refactoring — before touching the first line.
- **mcp-first-search** — MCP-first search discipline (graph → code-metadata → `grep=true` retry → `Grep`; if both graph and code-metadata are unavailable → `rlm-tools-bsl` when exposed) with a mandatory "what was tried" note; covers all native discovery tools (`Grep`, `Glob` / file search, directory listing, `Read`-scanning); load before any code / metadata / usage / call-graph / form / file-location search on 1C project source.
- **ui-testing-tools** — preferred browser / desktop automation for UI tests (`agent-browser` → built-in browser MCP → `Windows-MCP` last resort); **mandatory preflight** before web UI tests asks to run `/install-agent-browser` when missing; load before `/deploy-and-test` Step 4 / `1c-tester`; also `/install-windows-mcp`.
- **web-client-driving** — how the 1C web client behaves under a driver (snapshot reading, lists / trees / grids, reports, dialogs, anti-loop limits); load after the `ui-testing-tools.md` preflight, before the first action.

## Workflow and integrations

- **getconfigfiles** — extracting configuration objects (metadata) from an infobase into the repo.
- **configuration-storage** — 1C configuration storage regimen (lock / commit comment+label / never unbind) when `CONFIG_STORAGE_ENABLED=true`. Failed lock is a blocker: no IB import until every object is locked. File: `.cursor/rules/configuration-storage.mdc`. Playbook skill: `1c-configuration-storage`. Ask at project init whether storage is used (see `TEMPLATE.md`).
- **integrations-add** — code integrating 1C with another system (HTTP services, REST, message queues).
- **sdd-integrations** — OpenSpec guidelines; load whenever reading or updating files under `openspec/`.

## Metadata

- **metadata-xml-workarounds** — recurring metadata / form XML pitfalls; load when authoring or fixing metadata XML by hand outside the `1c-metadata-manage` skill.

## Project-specific (1commerce)

- **1commerce-functional-testing** — functional/runtime verification methodology (`1c-data-mcp` vs UI, readiness gate). Load before proving behaviour on a live infobase. File: `.cursor/rules/1commerce-functional-testing.mdc`.
- **1commerce-bsp-integration-checklists** — BSP hook pointer-checklists for new documents, print, input-based-on, form blocking (`ssl_search`-driven, configuration-agnostic). Load before creating metadata objects or wiring БСП integrations. File: `.cursor/rules/1commerce-bsp-integration-checklists.mdc`.

## Quality

- **anti-patterns** — 1C anti-pattern catalog, performance guidelines, review scoring; load for code review, performance investigation, or anti-pattern check.
- **verification-checklist** — compatibility router for verification policy, hard gates, and delivery checks; load only when following a legacy reference or when the required stage is not yet known.
- **verification-policy** — `VERIFICATION_DEPTH`, quick-fix eligibility, promotion triggers, and the quick-fix gate; load during triage.
- **verification-gates** — evidence reuse plus syntax, logic, style, impact, and metadata XML gates, and **Gate 6 — UI runtime for managed forms** (project overlay); load before validating BSL / metadata changes.
- **verification-delivery** — reproduction, plan adherence, optional review / UI test, delivery report, and verification anti-patterns; load after applicable hard gates.
- **systematic-debugging** — 4-phase debugging methodology for 1C, with a fast path for directly evidenced root causes (`DEBUG_FAST_PATH` in `.dev.env`); load for any bug / runtime error / regression, or when delegating to `1c-error-fixer` / `1c-performance-optimizer`.
- **platform-solutions** — case book of platform pitfalls and proven fix templates; load when working on a matching topic.
=======
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
>>>>>>> vendor-HEAD

# Spec-driven development workspace

`openspec/specs/` is current behaviour, `openspec/changes/` holds change artifacts; before OpenSpec work load `.cursor/rules/sdd-integrations.mdc` (owns full-cycle DoD and apply completion).
