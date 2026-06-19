# 1c-ext-codemeta-mcp — tool catalog

Codemeta index for **extension only**: `src/cfe/{EXTENSION_NAME}/` (ChromaDB on `mcp.1commerce.ru`).

> Load this file only if the `1c-ext-codemeta-mcp` server is actually available in the current session (its tools are exposed in the tool schema).

> **Tools and parameters** are the same as on [`1c-code-metadata-mcp.md`](1c-code-metadata-mcp.md). Before a parameter-rich call, read that file for exact argument names (`object_name`, `query`, `module_path`, etc.).

## When to use this server

Use **`1c-ext-codemeta-mcp`** when the task scope is the **extension layer** — see `USER-RULES.md → MCP: configuration vs extension`.

Typical triggers:

- edits under `src/cfe/{EXTENSION_NAME}/`;
- new metadata (`NEW_OBJECTS_IN=extension`);
- searching extension overrides or extension-only objects.

Use **`1c-code-metadata-mcp`** for the main configuration (cf), borrowed objects, and default “how does the system work” questions.

## Name prefixes — not a router

- Object name prefixes in configuration and extension **do not** determine which MCP index to use.
- **Do not** pick this server from a name prefix alone — route by file path (`src/cfe/…` vs `src/cf/…`) and which metadata layer is being edited.

## Fallback

If this index returns nothing useful → one retry on **`1c-code-metadata-mcp`** with the same query → then `grep=true` and Grep per `mcp-1c-tools/SKILL.md`.

Endpoint: `https://mcp.1commerce.ru/codemeta-{PROJECT_SLUG}-ext/mcp` (see `.cursor/mcp.json`).
