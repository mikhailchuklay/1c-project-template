#!/usr/bin/env bash
# Частичная загрузка расширений из build/out/extension-partial-load-*.txt через ibcmd.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=dev-standalone/_DevEnv.sh
source "${SCRIPT_DIR}/dev-standalone/_DevEnv.sh"

ROOT="$(dev_env_project_root "$0")"
dev_env_load "$ROOT" || true
dev_env_standalone_defaults "$ROOT"

OUT="${ROOT}/build/out"
IB_USER="${IB_USER:-}"
IBCMD="$(dev_env_platform_exe ibcmd)"

shopt -s nullglob
lists=("${OUT}"/extension-partial-load-*.txt)
if [[ ${#lists[@]} -eq 0 ]]; then
	echo "Нет extension-partial-load-*.txt — сначала tools/prepare-objlist.sh" >&2
	exit 0
fi

echo "Останавливаем ibsrv перед import..."
bash "${SCRIPT_DIR}/dev-standalone/stop.sh" 2>/dev/null || true
sleep 2

for list in "${lists[@]}"; do
	name="$(basename "$list" .txt)"
	ext="${name#extension-partial-load-}"
	base="${ROOT}/src/cfe/${ext}"
	if [[ ! -d "$base" ]]; then
		echo "Каталог расширения не найден: $base" >&2
		exit 1
	fi
	echo "Загрузка расширения ${ext} (${list})..."
	"$IBCMD" infobase config import files \
		"--db-path=${INFOBASE_PATH}" \
		${IB_USER:+--user="$IB_USER"} \
		"--base-dir=${base}" \
		"--extension=${ext}" \
		<"$list"
	echo "config apply ${ext}..."
	"$IBCMD" infobase config apply \
		"--db-path=${INFOBASE_PATH}" \
		${IB_USER:+--user="$IB_USER"} \
		"--extension=${ext}" \
		--force --dynamic=force --session-terminate=force
done

bash "${SCRIPT_DIR}/dev-standalone/restart.sh"
echo "Загрузка расширений из objlist завершена."
