#!/usr/bin/env bash
# Minimal MCP client for DEV (APA_MCP). Usage: invoke-datamcp.sh code|query|tools "payload"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_DevEnv.sh
source "${SCRIPT_DIR}/_DevEnv.sh"

PROJECT_ROOT="$(dev_env_project_root "$0")"
ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.dev.env}"

read_env() {
	local key="$1"
	grep -E "^${key}=" "$ENV_FILE" | head -1 | cut -d= -f2- | sed "s/^['\"]//;s/['\"]$//"
}

if [[ ! -f "$ENV_FILE" ]]; then
	echo ".dev.env не найден: $ENV_FILE" >&2
	exit 1
fi

BASE="$(read_env INFOBASE_PUBLISH_URL)"
USER="$(read_env IB_USER)"
PASS="$(read_env IB_PASSWORD)"
URL="${BASE%/}/hs/mcp"
ACTION="${1:-tools}"
PAYLOAD="${2:-}"

AUTH=$(printf '%s:%s' "$USER" "$PASS" | base64 -w0 2>/dev/null || printf '%s:%s' "$USER" "$PASS" | base64)

rpc() {
	local body="$1"
	local hdr="$2"
	curl -sS -D "$hdr" -o "${hdr}.body" -X POST \
		-H "Authorization: Basic $AUTH" \
		-H 'Content-Type: application/json; charset=utf-8' \
		-H 'Accept: application/json, text/event-stream' \
		${SESSION:+-H "Mcp-Session-Id: $SESSION"} \
		--data-binary "$body" \
		"$URL"
}

HDR=$(mktemp)
trap 'rm -f "$HDR" "$HDR".*' EXIT

case "$ACTION" in
	tools)
		CALL='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
		rpc "$CALL" "${HDR}.c"
		;;
	code)
		FLAT=$(printf '%s' "$PAYLOAD" | tr '\n' ' ' | sed 's/  */ /g;s/^ //;s/ $//')
		ESCAPED=$(printf '%s' "$FLAT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
		CALL=$(python3 - <<PY
import json
print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"vcexecutecode","arguments":{"bslcode":$ESCAPED}}}, ensure_ascii=False))
PY
)
		rpc "$CALL" "${HDR}.c"
		;;
	query)
		FLAT=$(printf '%s' "$PAYLOAD" | tr '\n' ' ' | sed 's/  */ /g;s/^ //;s/ $//')
		ESCAPED=$(printf '%s' "$FLAT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
		CALL=$(python3 - <<PY
import json
print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"vcexecutequery","arguments":{"querytext":$ESCAPED}}}, ensure_ascii=False))
PY
)
		rpc "$CALL" "${HDR}.c"
		;;
	file)
		FLAT=$(tr '\n' ' ' < "$PAYLOAD" | sed 's/  */ /g;s/^ //;s/ $//')
		ESCAPED=$(printf '%s' "$FLAT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
		CALL=$(python3 - <<PY
import json
print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"vcexecutecode","arguments":{"bslcode":$ESCAPED}}}, ensure_ascii=False))
PY
)
		rpc "$CALL" "${HDR}.c"
		;;
	*)
		echo "Unknown action: $ACTION" >&2
		exit 1
		;;
esac

HDR="$HDR" python3 - <<'PY'
import json, sys, os
hdr = os.environ.get('HDR')
path = hdr + '.c.body'
raw = open(path, encoding='utf-8-sig').read()
if 'text/event-stream' in open(hdr + '.c', encoding='utf-8', errors='replace').read().lower() or raw.strip().startswith('data:'):
    for line in raw.splitlines():
        if line.startswith('data:'):
            obj = json.loads(line[5:].strip())
            if 'result' in obj or 'error' in obj:
                data = obj
                break
else:
    data = json.loads(raw)
if 'error' in data:
    print('ERROR:', data['error'], file=sys.stderr)
    sys.exit(1)
res = data.get('result', {})
if 'tools' in res:
    for t in res['tools']:
        print(t['name'])
else:
    for c in res.get('content', []):
        if c.get('type') == 'text':
            print(c['text'])
    if res.get('isError'):
        sys.exit(1)
PY
