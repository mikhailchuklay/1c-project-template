#!/usr/bin/env bash
# Применить Linux-профиль DEV-среды: IDE/MCP + env.local.json (если ещё нет).
# После apply файлы IDE помечаются skip-worktree — git pull не перезапишет локальную копию.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PROFILE="$(cd "$(dirname "$0")" && pwd)"

subst() {
	sed "s|@PROJECT_ROOT@|${ROOT}|g" "$1"
}

echo "Профиль: Linux DEV"
echo "Корень проекта: ${ROOT}"

mkdir -p "${ROOT}/.vscode" "${ROOT}/.cursor"

subst "${PROFILE}/vscode-settings.json" > "${ROOT}/.vscode/settings.json"
subst "${PROFILE}/vscode-launch.json" > "${ROOT}/.vscode/launch.json"
subst "${PROFILE}/cursor-mcp.json" > "${ROOT}/.cursor/mcp.json"

if [[ ! -f "${ROOT}/env.local.json" ]]; then
	subst "${PROFILE}/env.local.example.json" > "${ROOT}/env.local.json"
	echo "Создан env.local.json из шаблона."
else
	echo "env.local.json уже есть — не перезаписываем."
fi

if git -C "${ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
	git -C "${ROOT}" update-index --skip-worktree \
		.vscode/settings.json \
		.vscode/launch.json \
		.cursor/mcp.json 2>/dev/null || true
	echo "skip-worktree: .vscode/settings.json, .vscode/launch.json, .cursor/mcp.json"
fi

echo "Готово. Перезагрузите окно Cursor (Developer: Reload Window)."
