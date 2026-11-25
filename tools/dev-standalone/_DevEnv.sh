#!/usr/bin/env bash
# Shared .dev.env helpers for bash scripts under tools/.
# Mirrors tools/dev-standalone/_DevEnv.ps1 (cross-platform DEV standalone defaults).

set -euo pipefail

dev_env_project_root() {
	local script_path="$1"
	local base script_root cwd_root
	base="$(cd "$(dirname "$script_path")" && pwd)"
	if [[ "$base" == */tools/dev-standalone ]]; then
		script_root="$(cd "$base/../.." && pwd)"
	elif [[ "$base" == */tools ]]; then
		script_root="$(cd "$base/.." && pwd)"
	else
		script_root="$(cd "$base/../.." && pwd)"
	fi
	# Рабочее дерево, из которого вызвали скрипт, важнее места самого скрипта: вызов
	# <базовый клон>/tools/designer-batch.sh из git worktree задачи иначе молча берёт
	# .dev.env базового клона (чужая копия базы, чужой пользователь хранилища).
	cwd_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
	if [[ -n "$cwd_root" && "$cwd_root" != "$script_root" && -f "$cwd_root/.dev.env" ]]; then
		echo "dev-env: .dev.env берётся из текущего рабочего дерева $cwd_root, а не из $script_root (скрипт вызван из другого клона)" >&2
		printf '%s\n' "$cwd_root"
		return 0
	fi
	printf '%s\n' "$script_root"
}

# .dev.env читается как текст, а не через source: source съедает «\» (сервер\база → серверbase),
# режет некавыченные значения с пробелами и исполняет $(…). Формат: KEY=value, KEY="value",
# KEY='value', необязательный «export », комментарии «#» в начале строки и « #» после
# некавыченного значения. Значение берётся буквально, без подстановок; переменная экспортируется.
dev_env_parse() {
	local line key val
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		[[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
		key="${BASH_REMATCH[2]}"
		val="${BASH_REMATCH[3]}"
		if [[ "$val" =~ ^\"(.*)\"[[:space:]]*(#.*)?$ ]] || [[ "$val" =~ ^\'(.*)\'[[:space:]]*(#.*)?$ ]]; then
			val="${BASH_REMATCH[1]}"
		else
			val="${val%%[[:space:]]#*}"
			val="${val%"${val##*[![:space:]]}"}"
		fi
		printf -v "$key" '%s' "$val"
		export "${key?}"
	done <"$1"
}

dev_env_load() {
	local project_root="$1"
	# Только .dev.env. Откат на .dev.env.example убран: в шаблоне пустые значения, а в проекте
	# туда могли попасть боевые адреса — запуск без своего .dev.env должен падать явно.
	if [[ -f "$project_root/.dev.env" ]]; then
		dev_env_parse "$project_root/.dev.env"
		export DEV_ENV_FILE="$project_root/.dev.env"
		return 0
	fi
	if [[ -f "$project_root/.dev.env.example" ]]; then
		echo "dev-env: нет $project_root/.dev.env (есть только .dev.env.example). Скопируйте пример в .dev.env и заполните; .dev.env.example больше не читается." >&2
	fi
	return 1
}

dev_env_platform_exe() {
	local exe_name="$1"
	local platform_path="${PLATFORM_PATH:-}"
	if [[ -z "$platform_path" ]]; then
		echo "PLATFORM_PATH не задан в .dev.env" >&2
		return 1
	fi
	if [[ -x "${platform_path}/${exe_name}" ]]; then
		echo "${platform_path}/${exe_name}"
		return 0
	fi
	if [[ -x "${platform_path}/bin/${exe_name}" ]]; then
		echo "${platform_path}/bin/${exe_name}"
		return 0
	fi
	echo "Не найден ${exe_name} в ${platform_path} (и в bin/)" >&2
	return 1
}

dev_env_standalone_defaults() {
	local project_root="$1"
	PROJECT_SLUG="$(basename "$project_root")"
	STANDALONE_PORT="${STANDALONE_PORT:-8314}"
	STANDALONE_ADDRESS="${STANDALONE_ADDRESS:-localhost}"
	STANDALONE_HTTP_BASE="${STANDALONE_HTTP_BASE:-/${PROJECT_SLUG}-dev}"
	if [[ "${STANDALONE_HTTP_BASE}" != /* ]]; then
		STANDALONE_HTTP_BASE="/${STANDALONE_HTTP_BASE}"
	fi
	SERVER_NAME="${PROJECT_SLUG}-dev"
	if [[ -z "${INFOBASE_PUBLISH_URL:-}" ]]; then
		INFOBASE_PUBLISH_URL="http://localhost:${STANDALONE_PORT}${STANDALONE_HTTP_BASE}/"
	fi
	if [[ "${INFOBASE_PUBLISH_URL}" != */ ]]; then
		INFOBASE_PUBLISH_URL="${INFOBASE_PUBLISH_URL}/"
	fi
	STANDALONE_ROOT="${project_root}/build/standalone"
	STANDALONE_DATA_PATH="${STANDALONE_DATA_PATH:-${STANDALONE_ROOT}/data}"
	IBCMD_CONFIG="${IBCMD_CONFIG:-${STANDALONE_ROOT}/config.yml}"
	INFOBASE_PATH="${INFOBASE_PATH:-${project_root}/build/ib}"
	export PROJECT_SLUG SERVER_NAME STANDALONE_PORT STANDALONE_ADDRESS STANDALONE_HTTP_BASE
	export INFOBASE_PUBLISH_URL STANDALONE_ROOT STANDALONE_DATA_PATH IBCMD_CONFIG INFOBASE_PATH
}
