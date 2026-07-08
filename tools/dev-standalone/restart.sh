#!/usr/bin/env bash
# Жёсткий перезапуск ibsrv с ожиданием HTTP 200.
# Использовать после config apply (CF/расширение), при «Попробуйте перезапустить сеанс»
# или когда процесс жив, а публикация не отвечает.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_DevEnv.sh
source "${SCRIPT_DIR}/_DevEnv.sh"

PROJECT_ROOT="$(dev_env_project_root "$0")"
dev_env_load "$PROJECT_ROOT" || true
dev_env_standalone_defaults "$PROJECT_ROOT"

IBSRV="$(dev_env_platform_exe ibsrv)"
PUBLISH_URL="${PUBLISH_URL:-$INFOBASE_PUBLISH_URL}"
LOG="${LOG_PATH:-${TMPDIR:-/tmp}/ibsrv.log}"
WAIT_SEC="${WAIT_SEC:-60}"

if [[ ! -f "$IBCMD_CONFIG" ]]; then
	echo "Нет config.yml: $IBCMD_CONFIG" >&2
	exit 1
fi

mkdir -p "$STANDALONE_DATA_PATH"

echo "Останавливаем ibsrv..."
pkill -9 -f "ibsrv.*${STANDALONE_ROOT}" 2>/dev/null || true
sleep 2

if pgrep -f "ibsrv.*${STANDALONE_ROOT}" >/dev/null 2>&1; then
	echo "Не удалось остановить ibsrv" >&2
	exit 1
fi

echo "Запускаем ibsrv (лог: $LOG)..."
nohup "$IBSRV" --config="$IBCMD_CONFIG" --data="$STANDALONE_DATA_PATH" >"$LOG" 2>&1 &
echo "PID=$!"

deadline=$((SECONDS + WAIT_SEC))
code=000
while (( SECONDS < deadline )); do
	code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$PUBLISH_URL" 2>/dev/null || echo 000)
	if [[ "$code" == "200" ]]; then
		echo "Проверка: $PUBLISH_URL -> OK (${SECONDS}s)"
		exit 0
	fi
	sleep 2
done

echo "Таймаут ${WAIT_SEC}s: публикация не ответила 200 (последний код: $code)" >&2
echo "Хвост лога:" >&2
tail -20 "$LOG" >&2 || true
exit 1
