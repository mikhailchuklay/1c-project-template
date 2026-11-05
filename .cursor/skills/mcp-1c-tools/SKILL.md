---
name: mcp-1c-tools
description: "Router for non-memory 1C MCP operations: select the server, operation skill with exact arguments, and fallback. Load before choosing a 1C tool; memory-only work enters through project-memory.md."
---

# MCP tools for 1C — router

Apply `.cursor/rules/mcp-policy.mdc → Tool availability` before routing: `.dev.env` `TOOL_*` policy plus callable tools and verified scope. Config entries alone prove nothing. The same policy owns obligations, budgets and typed-error recovery. Search: `.cursor/rules/mcp-first-search.mdc`; task sequences: `.cursor/rules/tooling-playbooks.mdc`.

**Project scope is part of the call.** For extensions or a multi-project graph, first match the current source roots to a returned base `project_id` through `list_graph_projects` (`.cursor/rules/multi-contour-search.mdc`). Supply it explicitly on every graph project-data call that exposes it, including paging and evidence. Resolve extension-layer coverage separately. Use each other server's actual selector (`configurationId` or another field only if exposed); its identifiers are not interchangeable with graph IDs. If a tool has no explicit selector, require a verified fixed/session/entity scope or use a suitable scoped tool/fallback. Never invent unsupported parameters or accept a default/foreign project as the current one. Reuse a valid mapping until the workspace/server context changes.

## Need → operation skill

Load the skill for the operation, not this whole catalogue. Each skill lists the exact argument names of its tools and example calls; no schema fetch is needed for a tool it names.

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
| *Project overlay:* project index servers not exposed for the contour, `rlm_start` exposed — local dump search | `docs/rlm-tools-bsl.md` | rlm |
| *Project overlay:* BSLLS / ACC / EDT diagnostic codes or a snippet → development standard (adapted v8std.ru text) | `docs/v8std-mcp.md` | v8std |

The operation table above is sufficient for ordinary routing. Read [server-catalog.md](docs/server-catalog.md) only to identify an unfamiliar server/alias, find a server-specific reference, or select an optional pre-alpha integration. Do not load the whole catalog before a known operation.

## Fallback chain

**Project source** (code, metadata, usages, forms, file locations): within verified contour coverage, graph → mapped code-metadata → scoped native `Grep` / `Glob` / `Read` after a bounded miss, with a one-line fallback note. Code chooses its file-scan fallback internally; current tools have no `grep` input. Skip uncovered lanes; no eligible exposed index means native search in that contour immediately. Owner: `.cursor/rules/mcp-first-search.mdc`; multiple roots, catalog/scope selectors and acceptance: `.cursor/rules/multi-contour-search.mdc`.

**External knowledge** has no interchangeable fallback chain. Select only the relevant eligible provider. Missing templates: disclose no template check; memory: `project-memory.md`; routed standards: `help-corpus-retrieval.md`; validators/live IB: `verification-gates.md`. An unavailable source never proves API absence or a passed check; block dependent design when authoritative facts are missing.

*Project overlays (1c-project-template):* `rlm-tools-bsl` is the availability substitute for the project-index lane only (`docs/rlm-tools-bsl.md`); `v8std` complements ITS for diagnostics and standards and never replaces `its_help` → `fetch_its` for normative decisions (`docs/v8std-mcp.md`); `1c-data-mcp` on a non-anonymous publication (`ibsrv`, Basic) is called through `tools/dev-standalone/Invoke-DataMcp.ps1` (`docs/1c-data-mcp.md`).

Open `docs/<server>.md` once per server per session and only for a mode or response shape the operation skill does not cover; the environment descriptor wins over any document here.
