#!/usr/bin/env bash
# Первичная инициализация config.yml автономного сервера DEV.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_DevEnv.sh
source "${SCRIPT_DIR}/_DevEnv.sh"

PROJECT_ROOT="$(dev_env_project_root "$0")"
dev_env_load "$PROJECT_ROOT" || true
dev_env_standalone_defaults "$PROJECT_ROOT"

IBCMD="$(dev_env_platform_exe ibcmd)"
mkdir -p "$(dirname "$IBCMD_CONFIG")" "$STANDALONE_ROOT"

"$IBCMD" server config init \
	--db-path="$INFOBASE_PATH" \
	--name="$SERVER_NAME" \
	--base="$STANDALONE_HTTP_BASE" \
	--address="$STANDALONE_ADDRESS" \
	--port="$STANDALONE_PORT" \
	--out="$IBCMD_CONFIG"

echo "Создан: $IBCMD_CONFIG"
echo "DEV URL: $INFOBASE_PUBLISH_URL"
