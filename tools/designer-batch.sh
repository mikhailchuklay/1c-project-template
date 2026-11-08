#!/usr/bin/env bash
# Пакетный запуск Конфигуратора (1cv8 DESIGNER) без экрана человека — POSIX-пара
# PowerShell-рецепта из .cursor/rules/designer-batch-checks.mdc.
#
# Инвариант: процесс 1cv8, запущенный агентом, не использует дисплей человека и не
# ждёт диалог. Поэтому обёртка:
#   - запускает Конфигуратор только на своём виртуальном экране (xvfb-run -a или
#     собственный Xvfb); унаследованный DISPLAY не используется никогда;
#   - сама добавляет /DisableStartupDialogs /DisableStartupMessages /Out /DumpResult;
#   - ограничивает запуск тайм-аутом и при срабатывании гасит только свою группу процессов;
#   - выносит вердикт по трём сигналам: код возврата, /DumpResult, текст /Out.
#
# Сначала ibcmd (tools/deploy-extension.sh), затем vrunner; эта обёртка — для того,
# чего у них нет (проверки /CheckModules, /CheckConfig, /CheckCanApplyConfigurationExtensions,
# выгрузка по -listFile и т. п.).
#
# Параметры подключения — из .dev.env (как deploy-extension.sh), иначе из VRUNNER_*.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=dev-standalone/_DevEnv.sh
source "${SCRIPT_DIR}/dev-standalone/_DevEnv.sh"

usage() {
	cat <<'EOF'
Использование: tools/designer-batch.sh [параметры] -- /<ПакетнаяКоманда> [ключи команды...]

Параметры:
  --timeout SEC   тайм-аут запуска (по умолчанию DESIGNER_TIMEOUT или 600)
  --out FILE      файл /Out (по умолчанию LOG_PATH или $TMPDIR/1cv8.log)
  --result FILE   файл /DumpResult (по умолчанию RESULT_PATH или $TMPDIR/1cv8.result)
  --load          запуск загрузки/применения: предупреждения в логе не валят вердикт
  --dry-run       показать команду (пароль скрыт) и выбранный экран, не запускать
  --self-test     прогнать разбор лога на контрольных строках и выйти
  -h, --help      эта справка

Одна пакетная команда на запуск. Подключение (/F, /S, /N, /P), /Out, /DumpResult
и /DisableStartup* обёртка ставит сама — в аргументах их не передавать.

Переменные (.dev.env или окружение):
  PLATFORM_PATH, INFOBASE_KIND, INFOBASE_PATH, IB_USER, IB_PASSWORD
  (запасной вариант: VRUNNER_IBCONNECTION, VRUNNER_DBUSER, VRUNNER_DBPWD)
  DESIGNER_TIMEOUT          тайм-аут по умолчанию, с
  DESIGNER_XVFB_FIRST       первый номер дисплея для поиска свободного (по умолчанию 99)
  DESIGNER_DISPLAY          готовый виртуальный экран (например, общий Xvfb агента);
                            не может совпадать с DISPLAY сеанса

Коды возврата: 0 — все три сигнала чистые; 1 — проверка не прошла или тайм-аут;
2 — запуск отклонён (аргументы, запрещённый ключ, нет параметров);
3 — нет виртуального экрана (используйте ibcmd или vrunner).
EOF
}

# ---------------------------------------------------------------------------
# Разбор лога /Out: сначала нейтрализуем фразы успеха, затем ищем диагностику.
# Канон — designer-batch-checks.mdc → «The success-phrase trap».
# ---------------------------------------------------------------------------
CLASSIFY_PY=$(cat <<'PY'
import re, sys
path, load_mode = sys.argv[1], sys.argv[2] == '1'
data = sys.stdin.buffer.read() if path == '-' else open(path, 'rb').read()
for enc in ('utf-8-sig', 'utf-16', 'cp1251'):
    try:
        text = data.decode(enc)
        break
    except UnicodeDecodeError:
        continue
success = [
    r'ошибок\s+не\s+обнаружено', r'предупреждений\s+не\s+обнаружено',
    r'ошибок\s*:\s*0(?![\d.,])', r'предупреждений\s*:\s*0(?![\d.,])',
    r'errors\s+were\s+not\s+found', r'warnings\s+were\s+not\s+found',
    r'errors\s*:\s*0(?![\d.,])', r'warnings\s*:\s*0(?![\d.,])',
    r'(?<![\d.,])0\s+(errors?|warnings?)\b',
]
errors = r'ошиб|не\s+найден|не\s+обнаружен|не\s+удалось|не\s+может\s+быть\s+применен|невозможно|\berror|\bfatal|\bfailed|\bfailure|\bexception'
warnings = r'предупрежд|\bwarning'
bad = []
for line in text.splitlines():
    low = line.lower()
    for pat in success:
        low = re.sub(pat, ' ', low)
    if re.search(errors, low) or (not load_mode and re.search(warnings, low)):
        bad.append(line.strip())
for line in bad[:20]:
    print(line)
sys.exit(1 if bad else 0)
PY
)
classify_log() {
	# $1 — файл лога или "-" для stdin; $2 — 1, если предупреждения не считаются провалом.
	python3 -c "$CLASSIFY_PY" "$1" "${2:-0}"
}

self_test() {
	local fails=0 line expect got
	while IFS='|' read -r expect line; do
		[[ -z "$expect" ]] && continue
		if printf '%s\n' "$line" | classify_log - 0 >/dev/null; then got=pass; else got=fail; fi
		if [[ "$got" != "$expect" ]]; then
			echo "НЕВЕРНО: ожидалось $expect, получено $got: $line" >&2
			fails=$((fails + 1))
		fi
	done <<'EOF'
pass|Проверка завершена. Ошибок не обнаружено.
pass|Предупреждений: 0
pass|Ошибок: 0; предупреждений: 0
fail|Ошибок: 0; предупреждений: 1
fail|Ошибок: 01
fail|Ошибок не обнаружено. Не найден метод "ПриЗаписи"
fail|Расширение не может быть применено
fail|Объект метаданных не существует: Ошибка выгрузки
fail|Error: object not found
pass|Обновление конфигурации успешно завершено
fail|Не найдена лицензия. Не обнаружен ключ защиты программы или полученная программная лицензия!
EOF
	if ((fails)); then return 1; fi
	echo "self-test: разбор лога исправен"
}

# ---------------------------------------------------------------------------
# Аргументы
# ---------------------------------------------------------------------------
TIMEOUT=""
OUT_FILE=""
RESULT_FILE=""
LOAD_MODE=0
DRY_RUN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--timeout) TIMEOUT="${2:?--timeout требует значение}"; shift 2 ;;
		--out) OUT_FILE="${2:?--out требует значение}"; shift 2 ;;
		--result) RESULT_FILE="${2:?--result требует значение}"; shift 2 ;;
		--load) LOAD_MODE=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		--self-test) self_test; exit $? ;;
		-h|--help) usage; exit 0 ;;
		--) shift; break ;;
		*) break ;;
	esac
done
BATCH=("$@")

refuse() { echo "designer-batch: $*" >&2; exit 2; }

[[ ${#BATCH[@]} -gt 0 ]] || { usage >&2; exit 2; }

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*|Windows_NT)
		refuse "Windows: используйте PowerShell-рецепт designer-batch-checks.mdc (Start-Process -WindowStyle Hidden)" ;;
esac

# Одна пакетная команда, без ключей подключения и вывода, без запрещённых операций.
cmd_count=0
CMD=""
for i in "${!BATCH[@]}"; do
	a="${BATCH[$i]}"
	lc="${a,,}"
	# Подключение, вывод и режим запуска ставит обёртка. Слитная форма (/F/путь,
	# /N"имя") ловится по заглавной букве ключа, пути вида /srv/… не задевает.
	case "$lc" in
		designer|enterprise|/f|/s|/n|/p|/ibconnectionstring|/ibname|/out|/dumpresult|/disablestartupdialogs|/disablestartupmessages)
			refuse "ключ «$a» задаёт обёртка — уберите его из аргументов" ;;
	esac
	if [[ "$a" =~ ^/[FSNP][^a-z] ]]; then
		refuse "ключ «$a» задаёт обёртка — уберите его из аргументов"
	fi
	if [[ "$a" =~ ^/[A-Z][A-Za-z0-9]*$ ]]; then
		cmd_count=$((cmd_count + 1))
		CMD="$lc"
	fi
	case "$lc" in
		/erasedata) refuse "/EraseData запрещён правилами (designer-batch-checks.mdc → Never run)" ;;
		/ibcheckandrepair) refuse "/IBCheckAndRepair запрещён правилами" ;;
		-allextensions) refuse "-AllExtensions запрещён правилами" ;;
		-disablesupport) refuse "/ManageCfgSupport -disableSupport запрещён правилами" ;;
	esac
	if [[ "$lc" == /deletecfg ]]; then
		next="${BATCH[$((i + 1))]:-}"; name="${BATCH[$((i + 2))]:-}"
		if [[ "${next,,}" != -extension || -z "${name// /}" ]]; then
			refuse "/DeleteCfg без непустого -Extension <имя> запрещён (удаляет первое расширение списка)"
		fi
	fi
done
((cmd_count == 1)) || refuse "нужна ровно одна пакетная команда на запуск, передано: $cmd_count (платформа выполняет только последнюю)"

# Известная ловушка: частичная (-listFile) или инкрементальная (-update) выгрузка
# в каталог без полной выгрузки падает с ошибкой «объект метаданных не существует».
if [[ "$CMD" == /dumpconfigtofiles ]]; then
	dump_dir=""; partial=0
	for i in "${!BATCH[@]}"; do
		case "${BATCH[$i],,}" in
			/dumpconfigtofiles) dump_dir="${BATCH[$((i + 1))]:-}" ;;
			-listfile|-update) partial=1 ;;
		esac
	done
	if ((partial)) && [[ ! -f "${dump_dir}/ConfigDumpInfo.xml" ]]; then
		refuse "частичная выгрузка (-listFile/-update) требует полной выгрузки в том же каталоге: нет ${dump_dir}/ConfigDumpInfo.xml. Сначала полная /DumpConfigToFiles в этот каталог."
	fi
fi

# ---------------------------------------------------------------------------
# Параметры из .dev.env
# ---------------------------------------------------------------------------
ROOT="$(dev_env_project_root "$0")"
dev_env_load "$ROOT" || true

TIMEOUT="${TIMEOUT:-${DESIGNER_TIMEOUT:-600}}"
[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -gt 0 ]] || refuse "тайм-аут должен быть положительным числом секунд: $TIMEOUT"
TMP="${TMPDIR:-/tmp}"
OUT_FILE="${OUT_FILE:-${LOG_PATH:-$TMP/1cv8.log}}"
RESULT_FILE="${RESULT_FILE:-${RESULT_PATH:-$TMP/1cv8.result}}"

V8=""
for exe in 1cv8 1cv8.exe; do
	if V8="$(dev_env_platform_exe "$exe" 2>/dev/null)"; then break; fi
	V8=""
done
[[ -n "$V8" ]] || refuse "не найден 1cv8: проверьте PLATFORM_PATH в .dev.env"

CONN=()
if [[ -n "${INFOBASE_PATH:-}" ]]; then
	case "$INFOBASE_PATH" in
		/F*|/S*) CONN=("${INFOBASE_PATH:0:2}" "${INFOBASE_PATH:2}") ;;
		*)
			case "${INFOBASE_KIND:-file}" in
				file) CONN=(/F "$INFOBASE_PATH") ;;
				server) CONN=(/S "${INFOBASE_PATH/\//\\}") ;;   # сервер:порт/база → сервер:порт\база
				*) refuse "INFOBASE_KIND должен быть file или server: ${INFOBASE_KIND}" ;;
			esac ;;
	esac
elif [[ -n "${VRUNNER_IBCONNECTION:-}" ]]; then
	CONN=("${VRUNNER_IBCONNECTION:0:2}" "${VRUNNER_IBCONNECTION:2}")
else
	refuse "не задан INFOBASE_PATH (.dev.env) и нет VRUNNER_IBCONNECTION"
fi
USER_NAME="${IB_USER:-${VRUNNER_DBUSER:-}}"
PASSWORD="${IB_PASSWORD:-${VRUNNER_DBPWD:-}}"

ARGS=(DESIGNER "${CONN[@]}")
[[ -n "$USER_NAME" ]] && ARGS+=(/N "$USER_NAME")
[[ -n "$PASSWORD" ]] && ARGS+=(/P "$PASSWORD")
ARGS+=(/DisableStartupDialogs /DisableStartupMessages "${BATCH[@]}" /Out "$OUT_FILE" /DumpResult "$RESULT_FILE")

masked() {
	local out=() prev=""
	for a in "$@"; do
		if [[ "${prev,,}" == /p ]]; then out+=("***"); else out+=("$a"); fi
		prev="$a"
	done
	printf '%q ' "${out[@]}"
}

# ---------------------------------------------------------------------------
# Виртуальный экран: xvfb-run -a → свой Xvfb → отказ. DISPLAY сеанса не используется.
# ---------------------------------------------------------------------------
HUMAN_DISPLAY="${DISPLAY:-}"
FIRST="${DESIGNER_XVFB_FIRST:-99}"
MODE=""
if [[ -n "${DESIGNER_DISPLAY:-}" ]]; then
	[[ "$DESIGNER_DISPLAY" != "$HUMAN_DISPLAY" ]] || refuse "DESIGNER_DISPLAY совпадает с DISPLAY сеанса ($HUMAN_DISPLAY) — это экран человека"
	MODE=display
elif command -v xvfb-run >/dev/null 2>&1; then
	MODE=xvfb-run
elif command -v Xvfb >/dev/null 2>&1; then
	MODE=xvfb
else
	hint="ibcmd"
	command -v ibcmd >/dev/null 2>&1 || [[ -x "$(dirname "$V8")/ibcmd" ]] || hint="vrunner (MCP-сервер vrunner)"
	echo "designer-batch: нет xvfb-run и Xvfb — Конфигуратор без виртуального экрана не запускаю. Используйте $hint." >&2
	exit 3
fi

case "$CMD" in
	/dumpconfigtofiles|/loadconfigfromfiles|/updatedbcfg|/dumpcfg|/loadcfg|/dumpib|/restoreib)
		if [[ -x "$(dirname "$V8")/ibcmd" ]]; then
			echo "designer-batch: для ${CMD} есть ibcmd (infobase config export/import/apply, infobase dump/restore) — он не требует экрана; предпочтительнее (см. tools/deploy-extension.sh)." >&2
		fi ;;
esac

echo "designer-batch: экран=${MODE}${DESIGNER_DISPLAY:+ $DESIGNER_DISPLAY}, тайм-аут=${TIMEOUT}s"
echo "designer-batch: $(masked "$V8" "${ARGS[@]}")"
((DRY_RUN)) && exit 0

command -v timeout >/dev/null 2>&1 || refuse "нет утилиты timeout (coreutils)"
mkdir -p "$(dirname "$OUT_FILE")" "$(dirname "$RESULT_FILE")"
rm -f "$RESULT_FILE"   # устаревший файл читался бы как вердикт этого запуска
: >"$OUT_FILE"

# Окружение процесса 1cv8: только виртуальный экран, без Wayland сеанса.
RUN_ENV=(env -u WAYLAND_DISPLAY -u DISPLAY GDK_BACKEND=x11)

XVFB_PID=""
cleanup() { [[ -n "$XVFB_PID" ]] && kill "$XVFB_PID" 2>/dev/null || true; }
trap cleanup EXIT

rc=0
case "$MODE" in
	display)
		timeout -k 30 "$TIMEOUT" "${RUN_ENV[@]}" DISPLAY="$DESIGNER_DISPLAY" "$V8" "${ARGS[@]}" || rc=$? ;;
	xvfb-run)
		timeout -k 30 "$TIMEOUT" "${RUN_ENV[@]}" xvfb-run -a -n "$FIRST" -s "-screen 0 1280x1024x24 -nolisten tcp" "$V8" "${ARGS[@]}" || rc=$? ;;
	xvfb)
		n="$FIRST"
		while [[ -e "/tmp/.X${n}-lock" || -e "/tmp/.X11-unix/X${n}" ]]; do n=$((n + 1)); done
		Xvfb ":${n}" -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &
		XVFB_PID=$!
		for _ in $(seq 1 50); do [[ -e "/tmp/.X11-unix/X${n}" ]] && break; sleep 0.1; done
		[[ -e "/tmp/.X11-unix/X${n}" ]] || { echo "designer-batch: Xvfb :${n} не поднялся" >&2; exit 3; }
		timeout -k 30 "$TIMEOUT" "${RUN_ENV[@]}" DISPLAY=":${n}" "$V8" "${ARGS[@]}" || rc=$? ;;
esac

# ---------------------------------------------------------------------------
# Вердикт: три сигнала
# ---------------------------------------------------------------------------
verdict=0
if ((rc == 124 || rc == 137)); then
	echo "сигнал 1, код возврата: тайм-аут ${TIMEOUT}s (процесс снят; повторять тот же запуск не нужно — смотрите лог)"
	verdict=1
else
	echo "сигнал 1, код возврата: $rc"
	((rc == 0)) || verdict=1
fi

if [[ -s "$RESULT_FILE" ]]; then
	dr="$(tr -d '\r\n\357\273\277 ' <"$RESULT_FILE")"
	echo "сигнал 2, /DumpResult: $dr"
	[[ "$dr" == 0 ]] || verdict=1
else
	echo "сигнал 2, /DumpResult: файл не записан"
	verdict=1
fi

if command -v python3 >/dev/null 2>&1; then
	if diag="$(classify_log "$OUT_FILE" "$LOAD_MODE")"; then
		echo "сигнал 3, /Out: диагностики нет ($OUT_FILE)"
	else
		echo "сигнал 3, /Out: найдены строки диагностики ($OUT_FILE):"
		printf '  %s\n' "$diag"
		verdict=1
	fi
else
	echo "сигнал 3, /Out: не проверен — нет python3 ($OUT_FILE); результат не подтверждён"
	verdict=1
fi

if ((verdict == 0)); then echo "ВЕРДИКТ: успех"; else echo "ВЕРДИКТ: не прошло"; fi
exit "$verdict"
