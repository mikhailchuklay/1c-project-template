#!/usr/bin/env bash
# Launcher для mcp-1c-platform-tools на Linux:
# локальный Cursor (~/.cursor) и Cursor Remote (~/.cursor-server).
set -euo pipefail

find_node() {
	local candidate
	shopt -s nullglob
	local -a bundled=(
		"$HOME"/.cursor-server/bin/linux-x64/*/node
		"$HOME"/.cursor-server/bin/linux-arm64/*/node
	)
	for candidate in "${bundled[@]}" \
		/usr/share/cursor/resources/app/resources/helpers/node \
		/usr/bin/node
	do
		if [[ -x "$candidate" ]]; then
			echo "$candidate"
			shopt -u nullglob
			return 0
		fi
	done
	shopt -u nullglob
	return 1
}

find_server() {
	local root dir
	local -a roots=(
		"$HOME/.cursor/extensions"
		"$HOME/.cursor-server/extensions"
	)
	for root in "${roots[@]}"; do
		[[ -d "$root" ]] || continue
		dir=$(find "$root" -maxdepth 1 -type d -name 'yellow-hammer.mcp-1c-platform-tools-*' 2>/dev/null | sort -V | tail -n 1)
		if [[ -n "$dir" && -f "$dir/out/src/index.js" ]]; then
			echo "$dir/out/src/index.js"
			return 0
		fi
	done
	return 1
}

NODE=$(find_node) || {
	echo "Не найден node: ни в ~/.cursor-server, ни в Cursor, ни /usr/bin/node." >&2
	exit 1
}
MCP=$(find_server) || {
	echo "Не найден MCP-сервер yellow-hammer.mcp-1c-platform-tools." >&2
	echo "Установите расширение mcp-1c-platform-tools в Cursor." >&2
	exit 1
}

exec "$NODE" "$MCP"
