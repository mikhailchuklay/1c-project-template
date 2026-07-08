#!/usr/bin/env bash
# Launcher для mcp-1c-platform-tools на remote Linux (Cursor Server).
# Системный node часто отсутствует — используем node из cursor-server.
set -euo pipefail

NODE=$(ls "$HOME"/.cursor-server/bin/linux-x64/*/node 2>/dev/null | head -1)
MCP="$HOME/.cursor-server/extensions/yellow-hammer.mcp-1c-platform-tools-0.1.8-universal/out/src/index.js"

if [[ -z "$NODE" || ! -x "$NODE" ]]; then
	echo "Не найден node в ~/.cursor-server/bin/linux-x64/" >&2
	exit 1
fi
if [[ ! -f "$MCP" ]]; then
	echo "Не найден MCP-сервер: $MCP" >&2
	echo "Установите расширение yellow-hammer.mcp-1c-platform-tools в Cursor." >&2
	exit 1
fi

exec "$NODE" "$MCP"
