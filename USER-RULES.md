# User Rules — {PROJECT_NAME}

Project-specific rules for AI agents. This file is a one-time template: the 1c-rules
installer never overwrites it after the first install.

## DEV vs PROD

- **Working environment** — local DEV infobase and publish URL from `.dev.env` (`INFOBASE_PUBLISH_URL`).
- **PROD** — reference only (`INFOBASE_PUBLISH_URL_PROD`, `INFOBASE_DATA_MCP_URL_PROD`). Do not use for daily development, UI tests, or MCP unless the user explicitly asks.
- New metadata objects — follow `NEW_OBJECTS_IN` in `.dev.env` (`main_configuration` or `extension`).

Details: [docs/dev-environment.md](docs/dev-environment.md).

## Source contours (optional)

If the project has more than one source contour (main configuration plus extensions, separate code indexes), declare the catalog in `project-contours.json` at the project root — format, roles and acceptance checks: `.cursor/rules/multi-contour-search.mdc`. State here that the catalog exists and which contour is primary, for example:

- Contour catalog: `project-contours.json` (base `src/cf` → `1c-code-metadata-mcp` + `1c-graph-metadata-mcp`; extension `src/cfe/<Name>` → `codemeta-{PROJECT_SLUG}-<ext>` or `null` when the extension has no index).

Attribute a hit by its actual source path and the server that returned it, not by object name prefix alone. A single-contour project needs no catalog.

## Migrated content from a previous setup

<!-- start of migrated content -->
<!-- end of migrated content -->