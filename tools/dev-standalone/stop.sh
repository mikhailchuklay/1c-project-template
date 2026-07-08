#!/usr/bin/env bash
# Остановка автономного сервера 1С (ibsrv) для DEV-публикации.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_DevEnv.sh
source "${SCRIPT_DIR}/_DevEnv.sh"

PROJECT_ROOT="$(dev_env_project_root "$0")"
dev_env_load "$PROJECT_ROOT" || true
dev_env_standalone_defaults "$PROJECT_ROOT"

pids=$(pgrep -f "ibsrv.*${STANDALONE_ROOT}" || true)
if [[ -z "$pids" ]]; then
	echo "ibsrv не запущен"
	exit 0
fi

echo "$pids" | xargs -r kill
sleep 2
echo "ibsrv остановлен"
