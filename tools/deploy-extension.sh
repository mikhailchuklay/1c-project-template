#!/usr/bin/env bash
# Загрузка расширения в DEV-ИБ: частичная (import files) или полная.
#
# Порядок (docs/dev-environment.md): stop ibsrv → import → apply → restart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=dev-standalone/_DevEnv.sh
source "${SCRIPT_DIR}/dev-standalone/_DevEnv.sh"

ROOT="$(dev_env_project_root "$0")"
dev_env_load "$ROOT" || true
dev_env_standalone_defaults "$ROOT"

OUT="${ROOT}/build/out"
LOG="${LOG_PATH:-${TMPDIR:-/tmp}/deploy-extension.log}"
IB_USER="${IB_USER:-}"
EXT="${EXTENSION_NAME:-}"

MODE=partial
LIST=""

usage() {
	cat <<EOF
Использование: $0 [--full | --list FILE]

  --full          полный import каталога src/cfe/<EXTENSION_NAME>
  --list FILE     частичный import files по списку путей
  (без флагов)    build/out/extension-partial-load-<EXTENSION_NAME>.txt

EXTENSION_NAME задаётся в .dev.env.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--full) MODE=full; shift ;;
		--list) MODE=partial; LIST="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 1 ;;
	esac
done

if [[ -z "$EXT" ]]; then
	echo "EXTENSION_NAME не задан в .dev.env" >&2
	exit 1
fi

BASE="${ROOT}/src/cfe/${EXT}"
IBCMD="$(dev_env_platform_exe ibcmd)"

if [[ "$MODE" == partial && -z "$LIST" ]]; then
	candidate="${OUT}/extension-partial-load-${EXT}.txt"
	if [[ -f "$candidate" && -s "$candidate" ]]; then
		LIST="$candidate"
	fi
fi

if [[ "$MODE" == partial ]]; then
	if [[ -z "$LIST" || ! -f "$LIST" ]]; then
		echo "Список для частичной загрузки не найден. Укажите --list FILE или создайте ${OUT}/extension-partial-load-${EXT}.txt" >&2
		exit 1
	fi
	if [[ ! -s "$LIST" ]]; then
		echo "Список пуст: $LIST" >&2
		exit 1
	fi
fi

if [[ "$MODE" == full && ! -d "$BASE" ]]; then
	echo "Каталог расширения не найден: $BASE" >&2
	exit 1
fi

log() {
	echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"
}

: >"$LOG"
log "=== deploy-extension: mode=${MODE} ext=${EXT} ==="
log "ИБ: ${INFOBASE_PATH}"

log "Останавливаем ibsrv..."
bash "${SCRIPT_DIR}/dev-standalone/stop.sh" >>"$LOG" 2>&1 || true
sleep 2

if pgrep -f "ibcmd.*--extension=${EXT}" >/dev/null 2>&1; then
	log "Завершаем зависший ibcmd..."
	pkill -9 -f "ibcmd.*--extension=${EXT}" || true
	sleep 1
fi

START=$SECONDS

if [[ "$MODE" == full ]]; then
	log "=== import (полный каталог расширения) ==="
	"$IBCMD" infobase config import \
		"--db-path=${INFOBASE_PATH}" \
		${IB_USER:+--user="$IB_USER"} \
		"--extension=${EXT}" \
		"$BASE" 2>&1 | tee -a "$LOG"
else
	cnt=$(wc -l <"$LIST" | tr -d ' ')
	log "=== import files (${cnt} путей из ${LIST}) ==="
	"$IBCMD" infobase config import files \
		"--db-path=${INFOBASE_PATH}" \
		${IB_USER:+--user="$IB_USER"} \
		"--base-dir=${BASE}" \
		"--extension=${EXT}" \
		<"$LIST" 2>&1 | tee -a "$LOG"
fi

log "=== config apply ==="
"$IBCMD" infobase config apply \
	"--db-path=${INFOBASE_PATH}" \
	${IB_USER:+--user="$IB_USER"} \
	"--extension=${EXT}" \
	--force --dynamic=force --session-terminate=force 2>&1 | tee -a "$LOG"

log "=== restart ibsrv ==="
bash "${SCRIPT_DIR}/dev-standalone/restart.sh" 2>&1 | tee -a "$LOG"

elapsed=$((SECONDS - START))
log "=== готово за ${elapsed}s ==="
