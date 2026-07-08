#!/usr/bin/env bash
# Сброс зависших сеансов DEV: stop ibsrv → session-terminate (CF+CFE) → очистка кэша → restart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_DevEnv.sh
source "${SCRIPT_DIR}/_DevEnv.sh"

PROJECT_ROOT="$(dev_env_project_root "$0")"
dev_env_load "$PROJECT_ROOT" || true
dev_env_standalone_defaults "$PROJECT_ROOT"

EXT="${EXTENSION_NAME:-}"
if [[ -z "$EXT" ]]; then
	echo "EXTENSION_NAME не задан в .dev.env" >&2
	exit 1
fi

IBCMD="$(dev_env_platform_exe ibcmd)"
IB_USER="${IB_USER:-}"

echo "[1/4] Останавливаем ibsrv..."
bash "${SCRIPT_DIR}/stop.sh" 2>/dev/null || true
pkill -9 -f "ibcmd.*--extension=${EXT}" 2>/dev/null || true
sleep 2

echo "[2/4] session-terminate (CF + расширение)..."
"$IBCMD" infobase config apply \
	"--db-path=${INFOBASE_PATH}" ${IB_USER:+--user="$IB_USER"} \
	--force --dynamic=auto --session-terminate=force 2>&1 | tail -3
"$IBCMD" infobase config apply \
	"--db-path=${INFOBASE_PATH}" ${IB_USER:+--user="$IB_USER"} \
	"--extension=${EXT}" \
	--force --dynamic=auto --session-terminate=force 2>&1 | tail -3

echo "[3/4] Очистка кэша сеансов ibsrv..."
rm -f "${STANDALONE_DATA_PATH}/session-data/snccntx.dat" 2>/dev/null || true
rm -rf "${STANDALONE_DATA_PATH}/temp/"* 2>/dev/null || true

echo "[4/4] Перезапуск ibsrv..."
bash "${SCRIPT_DIR}/restart.sh"
