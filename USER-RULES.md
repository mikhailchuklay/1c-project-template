# User Rules — {PROJECT_NAME}

Project-specific rules for AI agents. This file is a one-time template: the 1c-rules
installer never overwrites it after the first install.

## DEV vs PROD

- **Working environment** — local DEV infobase and publish URL from `.dev.env` (`INFOBASE_PUBLISH_URL`).
- **PROD** — reference only (`INFOBASE_PUBLISH_URL_PROD`, `INFOBASE_DATA_MCP_URL_PROD`). Do not use for daily development, UI tests, or MCP unless the user explicitly asks.
- New metadata objects — follow `NEW_OBJECTS_IN` in `.dev.env` (`main_configuration` or `extension`).

Details: [docs/dev-environment.md](docs/dev-environment.md).

## MCP: configuration vs extension (optional)

If your project uses separate MCP indexes for the main configuration (cf) and an extension (cfe), document routing here:

| Layer | Servers | Index |
|-------|---------|-------|
| Main configuration (cf) | `1c-code-metadata-mcp`, `1c-graph-metadata-mcp` | primary codebase |
| Extension (cfe) | `1c-ext-codemeta-mcp`, `1c-ext-graph-mcp` | extension layer only |

Choose the index by metadata layer (path under `src/cfe/…` vs `src/cf/…`), not by object name prefix alone.

## Migrated content from a previous setup

<!-- start of migrated content -->
<!-- end of migrated content -->