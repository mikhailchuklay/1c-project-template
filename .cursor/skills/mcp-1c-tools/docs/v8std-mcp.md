# v8std-mcp — tool catalog

[v8std.ru](https://v8std.ru) knowledge base: adapted 1C development standards, diagnostic mappings (BSLLS, ACC/АПК, EDT v8-code-style), patterns, and clean Markdown pages. Read-only — does not analyze the project or change code.

> Load this file only if the `v8std-mcp` server is actually available in the current session.

**Authority.** v8std is a curated navigation layer over ITS standards. For normative decisions, disputes, or compliance questions — always confirm via `its_help` → `fetch_its` on `1c-code-check-mcp`. Project rules marked `[Project rule — stricter than ITS standard]` override v8std when stricter.

**Endpoint.** Public hosted MCP: `https://ai.v8std.ru/mcp` ([documentation](https://v8std.ru/mcp/)).

## Tool selection

| Situation | First tool | Then |
|---|---|---|
| BSLLS / ACC / EDT diagnostic codes from `syntaxcheck` or the user | `v8std_explain_diagnostics` | `v8std_get_page` on returned ids |
| Short BSL/SDBL code fragment — which standards apply? | `v8std_explain_snippet` | `v8std_get_page` on returned ids |
| Topic search, `#std437`, unknown standard id | `v8std_search` | `v8std_get_page` on the best match |
| Known id / alias / URL — need full text | `v8std_get_page` | optional `v8std_get_related` for surrounding context |
| Move from one standard to linked diagnostics | `v8std_get_related` | `v8std_get_page` as needed |

Do **not** use `v8std_search` first when you already have diagnostic codes or a code snippet — prefer `v8std_explain_diagnostics` or `v8std_explain_snippet`.

## Tools

| Tool | Purpose | When to use |
|---|---|---|
| **v8std_search** | Hybrid search over standards, diagnostics, patterns, service pages | Arbitrary Russian phrases, `#std437`, diagnostic names when no exact code list is available |
| **v8std_get_page** | Full clean Markdown for a page by id, alias, path, or URL | After any discovery tool returns an id — read authoritative adapted text before explaining or fixing |
| **v8std_get_related** | Related standards and diagnostics from a known id | Code review context, remediation planning after a page lookup |
| **v8std_explain_snippet** | Map a short BSL/SDBL fragment to standards and likely diagnostics | Code tokens such as `ВЫБРАТЬ РАЗРЕШЕННЫЕ`, `ОткрытьФормуМодально`, `ЗаписьЖурналаРегистрации` |
| **v8std_explain_diagnostics** | Explain ACC/АПК, BSLLS, EDT/v8-code-style codes with linked standards | After `syntaxcheck` warnings or when the user pastes linter output |

## Typical workflows

### After `syntaxcheck` (BSLLS warnings)

1. Collect diagnostic codes from the `syntaxcheck` result.
2. `v8std_explain_diagnostics(codes=[...])`.
3. `v8std_get_page` for each relevant returned id.
4. If the fix is normatively ambiguous — `its_help` → `fetch_its` for the linked standard number.

### Code review — snippet check

1. `v8std_explain_snippet(snippet="...")` on the suspect fragment.
2. `v8std_get_page` on top matches.
3. Cross-check project rules (`.cursor/rules/`) for stricter project deltas.
4. `review_1c_code` / `its_help` → `fetch_its` remain the normative gates — v8std does not replace them.

## Query formats

| Target | Example queries |
|---|---|
| Standard | `#std437`, `std 437`, `стандарт 437` |
| BSLLS | `bslls:AssignAliasFieldsInQuery`, `AssignAliasFieldsInQuery` |
| ACC/АПК | `acc:1245`, `апк 1245` |
| EDT | `v8cs:common-module-name-client-server` |
| Topic | `транзакции`, `запросы`, `общие модули` |

## Relationship to other MCP servers

| Server | Role vs v8std |
|---|---|
| `1c-code-check-mcp` (`its_help` → `fetch_its`) | **Authoritative** ITS text — use for normative decisions |
| `1c-code-check-mcp` (`review_1c_code`) | Normative compliance check after edits — mandatory gate |
| `1c-syntax-checker-mcp` (`syntaxcheck`) | Produces BSLLS codes — feed into `v8std_explain_diagnostics` |
| `1C-docs-mcp` | Platform API documentation — orthogonal to development standards |

## Notes

- v8std is **not** a verification gate — do not add it to `verification-checklist.mdc`.
- Prefer `mode="hybrid"` (default) for `v8std_search`; narrow with `types` when the target kind is known.
- Source repository: [github.com/zeegin/v8std](https://github.com/zeegin/v8std) (CC0).
