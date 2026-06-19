# 1c-ext-graph-mcp — tool catalog

Graph index for **extension only**: `src/cfe/{EXTENSION_NAME}/` (Neo4j on `mcp.1commerce.ru`).

> Load this file only if the `1c-ext-graph-mcp` server is actually available in the current session (its tools are exposed in the tool schema).

> **Tools and parameters** are the same as on [`1c-graph-metadata-mcp.md`](1c-graph-metadata-mcp.md). Before a parameter-rich call, read that file for exact argument names (`object_name`, `query`, `routine_name`, etc.).

## When to use this server

Use **`1c-ext-graph-mcp`** when the task scope is the **extension layer** — see `USER-RULES.md → MCP: configuration vs extension`.

Typical triggers:

- impact / call graph for code under `src/cfe/{EXTENSION_NAME}/`;
- `search_code`, `get_object_dossier`, `trace_impact` for extension-only or extension-overridden objects.

Use **`1c-graph-metadata-mcp`** for the main configuration (cf) and as the host for **`compare_base_and_extension`** (base vs extension diff on the **configuration** graph).

## Name prefixes — not a router

- Object name prefixes in configuration and extension **do not** determine which MCP index to use.
- **Do not** pick this server from a name prefix alone — route by file path and which metadata layer is being edited.

## Fallback

Within extension scope: graph → codemeta — `1c-ext-graph-mcp` then `1c-ext-codemeta-mcp`, same chain as in `mcp-1c-tools/SKILL.md` but on ext servers.

If the ext index returns nothing → one retry on **`1c-graph-metadata-mcp`** → then cross-index codemeta / `grep=true` / Grep per `USER-RULES.md`.

Endpoint: `https://mcp.1commerce.ru/graph-{PROJECT_SLUG}-ext/mcp` (see `.cursor/mcp.json`).
