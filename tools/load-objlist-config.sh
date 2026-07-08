#!/usr/bin/env bash
# Частичная загрузка конфигурации из build/out/objlist-config.txt через ibcmd.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=dev-standalone/_DevEnv.sh
source "${SCRIPT_DIR}/dev-standalone/_DevEnv.sh"

ROOT="$(dev_env_project_root "$0")"
dev_env_load "$ROOT" || true
dev_env_standalone_defaults "$ROOT"

OUT="${ROOT}/build/out"
LIST="${OUT}/objlist-config.txt"
CF_DIR="${ROOT}/src/cf"
IB_USER="${IB_USER:-}"

if [[ ! -f "$LIST" || ! -s "$LIST" ]]; then
	echo "Нет build/out/objlist-config.txt — сначала tools/prepare-objlist.sh" >&2
	exit 1
fi

IBCMD="$(dev_env_platform_exe ibcmd)"

echo "Останавливаем ibsrv перед import..."
bash "${SCRIPT_DIR}/dev-standalone/stop.sh" 2>/dev/null || true
sleep 2

echo "Загрузка конфигурации (частично, ${LIST})..."
"$IBCMD" infobase config import files \
	"--db-path=${INFOBASE_PATH}" \
	${IB_USER:+--user="$IB_USER"} \
	"--base-dir=${CF_DIR}" \
	<"$LIST"

echo "config apply..."
"$IBCMD" infobase config apply \
	"--db-path=${INFOBASE_PATH}" \
	${IB_USER:+--user="$IB_USER"} \
	--force --dynamic=force --session-terminate=force

bash "${SCRIPT_DIR}/dev-standalone/restart.sh"
echo "Загрузка конфигурации из objlist завершена."
