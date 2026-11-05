---
name: mcp-1c-tools
<<<<<<< template
description: "Catalog of MCP servers for 1C development — search, code navigation, metadata, code review, docs, ITS, templates, local RLM. Use whenever a 1C task requires calling tools from any 1c-*-mcp / 1C-*-mcp / rlm-tools-bsl server. Each server has its own detail file under `docs/` — load it when you are about to call tools from that server, and only if the server is actually available in the current session."
=======
description: "Router for non-memory 1C MCP operations: select the server, operation skill with exact arguments, and fallback. Load before choosing a 1C tool; memory-only work enters through project-memory.md."
>>>>>>> vendor-HEAD
---

# MCP tools for 1C — router

Apply `.cursor/rules/mcp-policy.mdc → Tool availability` before routing: `.dev.env` `TOOL_*` policy plus callable tools and verified scope. Config entries alone prove nothing. The same policy owns obligations, budgets and typed-error recovery. Search: `.cursor/rules/mcp-first-search.mdc`; task sequences: `.cursor/rules/tooling-playbooks.mdc`.

**Project scope is part of the call.** For extensions or a multi-project graph, first match the current source roots to a returned base `project_id` through `list_graph_projects` (`.cursor/rules/multi-contour-search.mdc`). Supply it explicitly on every graph project-data call that exposes it, including paging and evidence. Resolve extension-layer coverage separately. Use each other server's actual selector (`configurationId` or another field only if exposed); its identifiers are not interchangeable with graph IDs. If a tool has no explicit selector, require a verified fixed/session/entity scope or use a suitable scoped tool/fallback. Never invent unsupported parameters or accept a default/foreign project as the current one. Reuse a valid mapping until the workspace/server context changes.

## Need → operation skill

Load the skill for the operation, not this whole catalogue. Each skill lists the exact argument names of its tools and example calls; no schema fetch is needed for a tool it names.

<<<<<<< template
For these tools default parameters are usually suboptimal; consult the server's `docs/<server>.md` before the first call in the session and adjust the parameters to the task:

- `1c-graph-metadata-mcp`: `search_code` (`search_type`, `detail_level`), `search_metadata` (JSON templates), `search_metadata_by_description` (`alpha`, `use_fuzzy`), `trace_impact` (`direction`, `depth`, `relationship_types`), `trace_call_chain` (`direction`, `depth`), `get_object_dossier` (`sections`), `business_search` (`include_structure`, `filter_type`).
- `1c-code-metadata-mcp`: `metadatasearch` (`object_type`, `names_only`), `get_method_call_hierarchy` (`direction`, `depth`), `graph_dependencies` (`direction`), `bsl_scope_members` (`member_type`).

If `docs/<server>.md` conflicts with the descriptor exposed by the current environment, the environment descriptor wins.

## When to use this skill

- Before writing code / a query / metadata XML — pick the MCP tool that best fits the task (template search, metadata check, syntax validation, code review).
- Before implementing a specialized capability (cryptography, СЛАУ / numerical methods, data analysis, collaboration system / bots, integration bus / queues, full-text search, regular expressions, …) — run the platform-capability check: `docsearch` → `docinfo` on `1C-docs-mcp` (+ `ssl_search` where a БСП solution is plausible). Do not trust model memory about what the platform does or does not have. Canon — `AGENTS.md → MCP Tool Calling → A.7`; procedure and trigger domains — [`docs/1C-docs-mcp.md`](docs/1C-docs-mcp.md) → *Platform capability discovery*.
- For impact analysis and code navigation — decide which server to use first (`graph` → `code-metadata` → `Grep`, or `rlm-tools-bsl` if both graph and code-metadata are unavailable — see *Fallback chain* below).
- For ITS standards (`its_help` → `fetch_its`), v8std diagnostic/standard navigation (`v8std_explain_diagnostics`, `v8std_explain_snippet`, `v8std_search` → `v8std_get_page`), and platform documentation (`docinfo` / `docsearch`).
- For code templates and project memory (`templatesearch`, `remember`, `recall`). Before **`templatesearch`**: load `docs/1c-templates-mcp.md → Query formulation (templatesearch only)` — that rule applies **only** to `templatesearch`, not to other MCP searches.

> Short obligation rules and verification budgets live in `AGENTS.md → MCP Tool Calling` (sections A, B, C). This skill owns the MCP catalog, routing, and fallback details.

## Server catalog

| Server (id) | Purpose | Details |
|---|---|---|
| **1c-graph-metadata-mcp** | Graph metadata (Neo4j / Cypher): structural object passport, impact analysis, call graph, usage search, business semantic search | [`docs/1c-graph-metadata-mcp.md`](docs/1c-graph-metadata-mcp.md) |
| **1c-code-metadata-mcp** | Metadata and BSL code search, navigation (modules, procedures, functions, call hierarchy), forms, XSD schemas, validation | [`docs/1c-code-metadata-mcp.md`](docs/1c-code-metadata-mcp.md) |
| **rlm-tools-bsl** | Local dump search (Python sandbox + optional SQLite BSL index). **Availability substitute only** — use when **both** graph and code-metadata are not exposed | [`docs/rlm-tools-bsl.md`](docs/rlm-tools-bsl.md) |
| **1c-templates-mcp** | Code template library + project vector memory (`remember` / `recall`) | [`docs/1c-templates-mcp.md`](docs/1c-templates-mcp.md) |
| **1c-ssl-mcp** | Standard Subsystems Library (БСП / SSL) search | [`docs/1c-ssl-mcp.md`](docs/1c-ssl-mcp.md) |
| **1C-docs-mcp** | 1C platform documentation (search by description / by exact name) | [`docs/1C-docs-mcp.md`](docs/1C-docs-mcp.md) |
| **1c-code-check-mcp** | 1С:Напарник — code review, technical check, AI rewrite/modify, ITS documentation | [`docs/1c-code-check-mcp.md`](docs/1c-code-check-mcp.md) |
| **1c-syntax-checker-mcp** | BSL syntax and style via BSL Language Server: `syntaxcheck` (code as text) and `syntaxcheck_file` (check a file on disk by path, optionally line-filtered; exposed only when a sources directory is mounted — prefer it over `syntaxcheck` when available, it is cheaper) | [`docs/1c-syntax-checker-mcp.md`](docs/1c-syntax-checker-mcp.md) |
| **1c-data-mcp** | Live-IB execution: BSL fragment run (`vcexecutecode`), query run (`vcexecutequery`), query parse-check (`validatequery`), last event-log error (`vcloggetlasterror`) | [`docs/1c-data-mcp.md`](docs/1c-data-mcp.md) |
| **v8std-mcp** | v8std.ru — adapted ITS standards, BSLLS/ACC/EDT diagnostic bridge, snippet-to-standard mapping (complements ITS, not a replacement) | [`docs/v8std-mcp.md`](docs/v8std-mcp.md) |

## Fallback chain (highest priority to lowest)

Use only the applicable branch; stop as soon as the collected evidence is sufficient. Before each call, check that it closes a concrete context gap and is not a duplicate of an earlier call.

### Project-source search before `Grep` / `Glob` / `rg`

Native discovery tools (`Grep` / `rg`, `Glob` / file search by pattern, directory listing, sequential `Read`-scanning) substitute only the project-indexing layer — locating files by mask (`**/*.bsl`, `**/*.xml`) or bulk-reading modules "to get oriented" is the same fallback as `Grep`, not a separate free action. Before falling back to any of them for 1C project-source search, exhaust:

1. `1c-graph-metadata-mcp` — `search_code`, `search_metadata`, `search_metadata_by_description`, `get_object_dossier`, `trace_impact`, `trace_call_chain` as appropriate. Skip this step if the server is not exposed.
2. `1c-code-metadata-mcp` — default indexed search / navigation (`codesearch`, `metadatasearch`, `search_function`, `search_forms`, `get_module_structure`, etc.). Skip this step if the server is not exposed.
3. `1c-code-metadata-mcp` with `grep=true` — substring retry inside the MCP index **only after** indexed / semantic / exact search did not find enough and only for tools that expose the parameter: `codesearch`, `metadatasearch`, `search_function`, `helpsearch`, `search_forms`. Typical scenarios: exact identifier, fragment of a query, metadata path, event handler name, error text, or literal string where semantic search is likely to miss.
4. **Availability substitute — `rlm-tools-bsl`.** Run this step **only** when steps 1–3 could not run because **neither** graph **nor** code-metadata is exposed in the current session, **and** `rlm-tools-bsl` **is** exposed (`rlm_start` in the tool schema). Then `rlm_projects(action="list")` if the project name is unknown → `rlm_start(project=...)` → `rlm_execute` (helpers from the start response; never `grep` on dump root) → `rlm_end`. Empty results from an **available** graph or code-metadata server do **not** trigger RLM. Details — [`docs/rlm-tools-bsl.md`](docs/rlm-tools-bsl.md).
5. Only then a native discovery tool (`Grep` / `rg` / `Glob` / `Read`-scanning) — with a mandatory short note in the response listing which project-index MCP attempts were tried (including RLM if step 4 applied, or why it was skipped) and why they did not return what was needed.

The chain is a **bounded priority, not a prohibition**: when the project-index servers are not exposed, the chain collapses to step 4 (`rlm-tools-bsl`, if exposed) and then native tools apply immediately (one-line note). When a tuned call plus the documented retry missed — fall back without spending further MCP calls on this rule. After fresh local edits the index may be stale — reading the disk state directly is legitimate. For understanding a single routine prefer fragment-level retrieval (`get_module_structure`, `search_code` `detail_level="L0"`, `search_function`) over a full-module `Read`; reading a direct edit target or an MCP-located file is normal work. Boundary cases — `content/rules/mcp-first-search.md`.

### External knowledge
=======
| Need | Skill | Servers |
|---|---|---|
| Locate or read BSL code, module layout, members of a context | `.cursor/skills/1c-code-search/SKILL.md` | graph, code |
| Facts about a metadata object: passport, attributes, tabular-part columns, objects by category or description | `.cursor/skills/1c-meta-info/SKILL.md` | graph, code |
| Usages, call chains, downstream impact, register writers, extension layers | `.cursor/skills/1c-impact/SKILL.md` | graph, code |
| Read forms, form artifacts, XSD / format specs before a form change | `.cursor/skills/1c-form-inspect/SKILL.md` | code, graph, docs |
| Validate changed BSL and metadata XML (Gates 1–3, 5) | `.cursor/skills/1c-validate/SKILL.md` | syntax, checker, code |
| Platform reference, capability check, БСП API, routed standards, ITS, configuration docs | `.cursor/skills/1c-platform-help/SKILL.md` | docs, ssl, checker, code |
| Templates as the base | `.cursor/skills/1c-templates-memory/SKILL.md` | templates |
| Memory recall / save (independent entry point) | `.cursor/rules/project-memory.mdc` | cognee, openviking, templates |
| Run a query or fragment in the live infobase, last event-log error | `.cursor/skills/1c-live-ib/SKILL.md` | data |
| Check behaviour in the 1C interface (thin client): forms, fields, tables, commands, messages | `.cursor/skills/1c-qa-testing/SKILL.md` + `.cursor/rules/qa-testclient.mdc` | qa |
| Create / edit / remove metadata, forms, roles, DCS, MXL, infobases | `.cursor/skills/1c-metadata-manage/SKILL.md` | scripts, not MCP |
| Live 1C:EDT workspace (`USE_EDT=true` only) | `docs/edt-mcp.md`, `.cursor/rules/edt-workflow.mdc` | edt |

## Server catalog
>>>>>>> vendor-HEAD

The operation table above is sufficient for ordinary routing. Read [server-catalog.md](docs/server-catalog.md) only to identify an unfamiliar server/alias, find a server-specific reference, or select an optional pre-alpha integration. Do not load the whole catalog before a known operation.

<<<<<<< template
1. `1c-templates-mcp` — code templates and project memory (`templatesearch`, `remember`, `recall`). **`templatesearch` only:** query pre-flight (`A.8`) + **reuse found template** (`A.9`, `docs/1c-templates-mcp.md → Using a found template`).
2. `1c-ssl-mcp` — БСП / SSL reusable APIs and patterns.
3. `1C-docs-mcp` — versioned platform documentation; also the mandatory platform-capability check before hand-rolling a specialized mechanism (see `docs/1C-docs-mcp.md → Platform capability discovery`).
4. `1c-code-check-mcp` — 1С:Напарник checks, ITS standards (`its_help` → `fetch_its` for every document used), AI drafts.
5. `v8std-mcp` — diagnostic-to-standard bridge and adapted standard navigation. Use after `syntaxcheck` BSLLS codes (`v8std_explain_diagnostics`), for BSL/SDBL snippets (`v8std_explain_snippet`), or topic search (`v8std_search` → `v8std_get_page`). **Does not replace** `its_help` → `fetch_its` for normative decisions. Details — [`docs/v8std-mcp.md`](docs/v8std-mcp.md).
6. `1c-syntax-checker-mcp` — BSL syntax / style validation after edits (prefer `syntaxcheck_file` over `syntaxcheck` when it is exposed — file check by path is more economical than passing code text).
7. `1c-data-mcp` — execution against the **live** infobase (run a BSL fragment, run a query, parse-check a query, fetch the last event-log error). No `Grep` / `rg` equivalent — there is no offline substitute for "what does this running IB do right now". Call only when the question genuinely requires the live IB; default to read-only fragments and ask before any mutation. Native tools appear only when `/hs/mcp` is anonymous — that is the correct IIS / Apache publish. On `ibsrv`, and on any publication that was not made anonymous, the call is the same: an anonymous request fails (503 on `ibsrv`, typically 401 on IIS) and Basic auth of `IB_USER`/`IB_PASSWORD` returns 200. Cursor does not send `Authorization`. Use `tools/dev-standalone/Invoke-DataMcp.ps1`. Do not call `mcp_auth` and do not use the COM connector. Details — [`docs/1c-data-mcp.md`](docs/1c-data-mcp.md).
=======
## Fallback chain
>>>>>>> vendor-HEAD

**Project source** (code, metadata, usages, forms, file locations): within verified contour coverage, graph → mapped code-metadata → scoped native `Grep` / `Glob` / `Read` after a bounded miss, with a one-line fallback note. Code chooses its file-scan fallback internally; current tools have no `grep` input. Skip uncovered lanes; no eligible exposed index means native search in that contour immediately. Owner: `.cursor/rules/mcp-first-search.mdc`; multiple roots, catalog/scope selectors and acceptance: `.cursor/rules/multi-contour-search.mdc`.

<<<<<<< template
| Task | First choice (graph) | Fallback (code-metadata) |
|---|---|---|
| BSL code search | `search_code` (`fulltext` / `semantic` / `hybrid`, `detail_level` L0–L3) | `codesearch` |
| Metadata object structure | `get_object_dossier` | `get_metadata_details` |
| Impact analysis before refactoring | `trace_impact` (recursive, depth 1–5; up to 10 for `CALLS`) | `graph_dependencies` (single-level) |
| Call graph | `trace_call_chain` | `get_method_call_hierarchy` |
| Metadata search by name / structure | `search_metadata` (JSON templates) | `metadatasearch` |
| Object usage search | `find_objects_using_object` / `find_usages_of_object` | `graph_dependencies` (`direction="reverse"`) |
| Description / synonym / comment search | `search_metadata_by_description` | `metadatasearch` (`names_only=true`) |
| BSLLS/ACC/EDT code → standard | `v8std_explain_diagnostics` (`v8std-mcp`) | `v8std_search` → `v8std_get_page`; `its_help` → `fetch_its` for normative text |
| BSL/SDBL snippet → standards | `v8std_explain_snippet` (`v8std-mcp`) | `v8std_get_page`; `review_1c_code` for compliance |
=======
**External knowledge** has no interchangeable fallback chain. Select only the relevant eligible provider. Missing templates: disclose no template check; memory: `project-memory.md`; routed standards: `help-corpus-retrieval.md`; validators/live IB: `verification-gates.md`. An unavailable source never proves API absence or a passed check; block dependent design when authoritative facts are missing.
>>>>>>> vendor-HEAD

Open `docs/<server>.md` once per server per session and only for a mode or response shape the operation skill does not cover; the environment descriptor wins over any document here.
