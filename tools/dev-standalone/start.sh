#!/usr/bin/env bash
# Запуск автономного сервера 1С (ibsrv) для DEV-публикации на localhost.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_DevEnv.sh
source "${SCRIPT_DIR}/_DevEnv.sh"

PROJECT_ROOT="$(dev_env_project_root "$0")"
dev_env_load "$PROJECT_ROOT" || true
dev_env_standalone_defaults "$PROJECT_ROOT"

IBSRV="$(dev_env_platform_exe ibsrv)"

if [[ ! -f "$IBCMD_CONFIG" ]]; then
	echo "Нет config.yml. Сначала выполните: tools/dev-standalone/init-config.sh" >&2
	exit 1
fi

mkdir -p "$STANDALONE_DATA_PATH"

if pgrep -f "ibsrv.*${STANDALONE_ROOT}" >/dev/null 2>&1; then
	echo "ibsrv уже запущен (PID $(pgrep -f "ibsrv.*${STANDALONE_ROOT}" | head -1))"
else
	nohup "$IBSRV" --config="$IBCMD_CONFIG" --data="$STANDALONE_DATA_PATH" >/dev/null 2>&1 &
	sleep 3
	echo "ibsrv запущен"
fi

if curl -sf --connect-timeout 5 "$INFOBASE_PUBLISH_URL" >/dev/null; then
	echo "Проверка: $INFOBASE_PUBLISH_URL -> OK"
else
	echo "Предупреждение: публикация пока не отвечает: $INFOBASE_PUBLISH_URL" >&2
fi
