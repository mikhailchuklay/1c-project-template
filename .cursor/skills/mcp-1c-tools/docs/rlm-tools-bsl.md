# rlm-tools-bsl — tool catalog

Local MCP for token-efficient BSL / metadata search against the configuration dump on disk. The agent sends Python to a sandbox; only `print()` output returns to context. Not a RAG/graph replacement.

> Load this file only if the `rlm-tools-bsl` server is actually available in the current session (`rlm_start` is in the tool schema).

**When to use.** Only as the **availability substitute** in the project-source fallback chain: when **both** `1c-graph-metadata-mcp` and `1c-code-metadata-mcp` are **not** exposed. If either of those servers is available, do **not** start an RLM session for search — even if their first query returned empty. User-explicit «смотри через RLM» overrides this.

**Endpoint.** `http://127.0.0.1:9000/mcp` (see `.cursor/mcp.json`). Server must be running locally.

## Tools

**Managed dev-workplaces service:** registry/index password checks are disabled by
the explicit local-only deployment option `RLM_ALLOW_PASSWORDLESS_LOCAL=1`.
Do not request a password preemptively there. On an unmodified server, follow its
password challenge. User consent for mutations and index builds remains required.

**Initial setup exception.** During project onboarding, follow [RLM setup](../../../../docs/rlm-setup.md): offer connection, registration and optional indexing even when graph/code-metadata are available. This permits registry/index diagnostics and explicitly approved setup operations, not ordinary source searches through RLM.

| Tool | Purpose |
|---|---|
| **rlm_projects** | Registry of name → dump path. `action=list` is read-only. `add` / `remove` / `rename` / `update` need the project password — ask the user, never invent. |
| **rlm_index** | SQLite BSL index: `info` (read-only), `build` / `update` / `drop` (password via `confirm`). Do **not** build or drop unless the user asked. |
| **rlm_start** | Open a session. Prefer `project` (registry name) over `path`. Returns `session_id` plus helper recipes — follow those; do not grep the dump root. |
| **rlm_execute** | Run Python in the session sandbox. Batch 3–5 helpers per call; `print()` summaries only. |
| **rlm_end** | Close the session when the search is done. |

## Typical search (availability substitute)

Check `rlm_index(action="info", project=...)` before analysis and account for
known dump changes since the last successful index job. Follow the
[index lifecycle and consent policy](../../../../docs/rlm-setup.md#жизненный-цикл-индекса):
offer build for missing indexes with sources, update after relevant source changes,
and distinguish running jobs from completed ones. A missing/stale index is not
permission to build, drop or rebuild it automatically.

1. `rlm_projects(action="list")` if the project name is unknown.
2. `rlm_start(project="<name>", query="<what to find>")` — dump path is usually `src/cf`.
3. `rlm_execute(session_id, code=...)` using helpers from the `rlm_start` response (`find_module`, `search_methods`, `search_objects`, `read_procedure`, `find_callers_context`, …).
4. `rlm_end(session_id)`.

On large configs never `grep(path='.')`. Use `find_module` / indexed helpers first.

## Relationship to other MCP servers

- **Does not replace** `1c-graph-metadata-mcp` or `1c-code-metadata-mcp` when they are up.
- **Does not replace** `Grep` / `Glob` for non-1C files (rules, OpenSpec, logs).
- Index is optional but expected on large dumps; `rlm_start` reports `index.loaded`. If the index is missing, still search via helpers — do not call `rlm_index(action="build")` on your own.
