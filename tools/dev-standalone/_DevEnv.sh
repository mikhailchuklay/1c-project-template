#!/usr/bin/env bash
# Shared .dev.env helpers for bash scripts under tools/.
# Mirrors tools/dev-standalone/_DevEnv.ps1 (cross-platform DEV standalone defaults).

set -euo pipefail

dev_env_project_root() {
	local script_path="$1"
	local base
	base="$(cd "$(dirname "$script_path")" && pwd)"
	if [[ "$base" == */tools/dev-standalone ]]; then
		(cd "$base/../.." && pwd)
	elif [[ "$base" == */tools ]]; then
		(cd "$base/.." && pwd)
	else
		(cd "$base/../.." && pwd)
	fi
}

dev_env_load() {
	local project_root="$1"
	local f
	for f in "$project_root/.dev.env" "$project_root/.dev.env.example"; do
		if [[ -f "$f" ]]; then
			# shellcheck disable=SC1090
			set -a
			# shellcheck disable=SC1091
			source "$f"
			set +a
			return 0
		fi
	done
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
