#!/usr/bin/env bash
# Толстый клиент 1cv8, обычное приложение: печать, отчёты и снимки обычных форм.
#
# Инвариант тот же, что у tools/designer-batch.sh: процесс 1cv8 не берёт дисплей
# человека и не ждёт диалог. Обёртка поднимает свой Xvfb (-nolisten tcp), сама
# ставит подключение из .dev.env и /DisableStartupMessages. /DisableStartupDialogs не передаётся.
# /Out и общий тайм-аут. По тайм-ауту снимаются только своя группа процессов и
# свой Xvfb.
#
# Режимы:
#   scenario --params <файл.json>  — прогон сценария внешней обработкой
#   snapshot                       — одна форма, PNG, без JSON руками
#   --dry-run                      — команда со скрытым паролем, без запуска
#   --self-test                    — разбор JSON, белый список окон, маска пароля, XWD
#
# Коды: 0 — все шаги PASS; 1 — FAIL или тайм-аут; 2 — отказ в запуске; 3 — нет Xvfb.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=dev-standalone/_DevEnv.sh
source "${SCRIPT_DIR}/dev-standalone/_DevEnv.sh"
SKILL_DIR="${SCRIPT_DIR}/../.cursor/skills/1c-thick-client-test"
HOST="${SKILL_DIR}/scripts/host.py"
SRC_ROOT="${SKILL_DIR}/scripts"
SRC_XML="${SRC_ROOT}/ТолстыйКлиентПроверка.xml"

usage() {
	cat <<'EOF'
Использование:
  tools/thick-client-check.sh scenario --params <файл.json> [параметры]
  tools/thick-client-check.sh snapshot --metadata <Вид.Имя> [параметры]
  tools/thick-client-check.sh --self-test
  tools/thick-client-check.sh --dry-run scenario --params <файл.json>

Параметры:
  --timeout SEC          общий тайм-аут, секунды (по умолчанию 900)
  --out-dir DIR          каталог отчёта (по умолчанию <корень>/out)
  --dismiss-title TEXT   добавить заголовок в белый список: «Текст» или «Текст|действие»
                         действие: click-left, click-right, return, close
  --metadata ВИД.ИМЯ     snapshot: Документ.*, Справочник.*, Отчет.*
  --number НОМЕР         snapshot: номер документа или код справочника
  --kind KIND            snapshot: object (по умолчанию), list, report, main
  --form ИМЯ             snapshot: имя формы; пусто — форма по умолчанию
  --generate             snapshot: сформировать отчёт на открытой форме
  --date-from ГГГГ-ММ-ДД snapshot: начало периода
  --date-to ГГГГ-ММ-ДД   snapshot: конец периода
  --infobase СЕРВЕР:ПОРТ/БАЗА
                         подменить базу из .dev.env на этот серверный адрес
                         (и сборка EPF, и предприятие)
  --platform КАТАЛОГ    каталог платформы или номер сборки (8.3.14.1779)
                         (и сборка EPF, и предприятие)
  --ib-user ИМЯ         пользователь базы; пустая строка — вход без /N
                         (и сборка EPF, и предприятие)
  --dry-run              показать команду (пароль скрыт) и не запускать
  --self-test            проверить разбор сценария, белый список, маску пароля и XWD
  -h, --help             эта справка

Подключение — из .dev.env (INFOBASE_KIND, INFOBASE_PATH, PLATFORM_PATH, IB_USER,
IB_PASSWORD), запасной путь — VRUNNER_*. Унаследованный DISPLAY не используется.
EOF
}

# Белый список стартовых окон: подстрока заголовка и способ закрытия.
# Enter/Escape без опознанного заголовка не нажимаются.
DEFAULT_DISMISS=(
	"Предупреждение безопасности|confirm-safe"
	"Защита от опасных действий|confirm-safe"
	"Завершить работу|return"
)

is_windows() {
	case "$1" in
		MINGW*|MSYS*|CYGWIN*|Windows_NT) return 0 ;;
		*) return 1 ;;
	esac
}

mask_command() {
	local out="" prev="" a
	for a in "$@"; do
		if [[ "${prev,,}" == /p ]]; then
			out+="*** "
		else
			out+="$(printf '%q' "$a") "
		fi
		prev="$a"
	done
	printf '%s' "${out% }"
}

dismiss_action() {
	local title="$1" entry pattern action
	for entry in "${DISMISS[@]}"; do
		pattern="${entry%%|*}"
		action="${entry#*|}"
		if [[ "$action" == "$entry" ]]; then
			action="click-left"
		fi
		if [[ "$title" == *"$pattern"* ]]; then
			printf '%s' "$action"
			return 0
		fi
	done
	return 1
}

self_test() {
	local fails=0 got
	python3 "$HOST" --self-test || fails=1
	got="$(mask_command /opt/1cv8/1cv8 ENTERPRISE /P secret /N user)"
	if [[ "$got" == *secret* ]]; then
		echo "self-test: пароль не замаскирован: $got" >&2
		fails=1
	fi
	if [[ "$got" != *'***'* ]]; then
		echo "self-test: в команде нет маски пароля: $got" >&2
		fails=1
	fi
	DISMISS=("${DEFAULT_DISMISS[@]}")
	if [[ "$(dismiss_action "Предупреждение безопасности")" != "confirm-safe" ]]; then
		echo "self-test: белый список не узнал предупреждение безопасности" >&2
		fails=1
	fi
	if [[ "$(dismiss_action "Завершить работу с программой?")" != "return" ]]; then
		echo "self-test: белый список не узнал завершение работы" >&2
		fails=1
	fi
	if dismiss_action "Легальность получения обновлений" >/dev/null; then
		echo "self-test: легальность обновлений закрывается без решения проекта" >&2
		fails=1
	fi
	if dismiss_action "Реализация товаров и услуг" >/dev/null; then
		echo "self-test: форма документа попала в белый список" >&2
		fails=1
	fi
	if ! is_windows "MINGW64_NT-10.0"; then
		echo "self-test: Windows не опознан" >&2
		fails=1
	fi
	if is_windows "Linux"; then
		echo "self-test: Linux принят за Windows" >&2
		fails=1
	fi
	if ((fails)); then
		return 1
	fi
	echo "self-test: пароль, белый список окон и отказ Windows проверены"
}

refuse() { echo "thick-client-check: $*" >&2; exit 2; }

TIMEOUT=""
OUT_DIR=""
DRY_RUN=0
MODE=""
PARAMS=""
SNAP_META=""
SNAP_NUMBER=""
SNAP_KIND="object"
SNAP_FORM=""
SNAP_GENERATE=0
SNAP_FROM=""
SNAP_TO=""
INFOBASE_OVERRIDE=""
PLATFORM_OVERRIDE=""
IB_USER_OVERRIDE=""
IB_USER_SET=0
DISMISS=("${DEFAULT_DISMISS[@]}")

while [[ $# -gt 0 ]]; do
	case "$1" in
		--timeout) TIMEOUT="${2:?--timeout требует значение}"; shift 2 ;;
		--out-dir) OUT_DIR="${2:?--out-dir требует значение}"; shift 2 ;;
		--dismiss-title) DISMISS+=("${2:?--dismiss-title требует значение}"); shift 2 ;;
		--params) PARAMS="${2:?--params требует значение}"; shift 2 ;;
		--metadata) SNAP_META="${2:?--metadata требует значение}"; shift 2 ;;
		--number) SNAP_NUMBER="${2:?--number требует значение}"; shift 2 ;;
		--kind) SNAP_KIND="${2:?--kind требует значение}"; shift 2 ;;
		--form) SNAP_FORM="${2:?--form требует значение}"; shift 2 ;;
		--date-from) SNAP_FROM="${2:?--date-from требует значение}"; shift 2 ;;
		--date-to) SNAP_TO="${2:?--date-to требует значение}"; shift 2 ;;
		--generate) SNAP_GENERATE=1; shift ;;
		--infobase) INFOBASE_OVERRIDE="${2:?--infobase требует сервер:порт/база}"; shift 2 ;;
		--platform) PLATFORM_OVERRIDE="${2:?--platform требует каталог или сборку}"; shift 2 ;;
		--ib-user)
			[[ $# -ge 2 ]] || refuse "--ib-user требует значение (пустая строка — вход без /N)"
			IB_USER_OVERRIDE="$2"
			IB_USER_SET=1
			shift 2
			;;
		--dry-run) DRY_RUN=1; shift ;;
		--self-test) self_test; exit $? ;;
		-h|--help) usage; exit 0 ;;
		scenario|snapshot) MODE="$1"; shift ;;
		*) refuse "неизвестный аргумент: $1" ;;
	esac
done

[[ -n "$MODE" ]] || { usage >&2; exit 2; }

if is_windows "$(uname -s)"; then
	refuse "Windows не поддерживается: нужен Linux, свой Xvfb и толстый клиент 1cv8. На Windows этот маршрут не запускается."
fi

ROOT="$(dev_env_project_root "$0")"
if ! dev_env_load "$ROOT"; then
	refuse "нет .dev.env в $ROOT — подключение к базе не из чего собрать"
fi

if [[ -n "$PLATFORM_OVERRIDE" ]]; then
	if [[ -d "$PLATFORM_OVERRIDE" ]]; then
		PLATFORM_PATH="$PLATFORM_OVERRIDE"
	elif [[ -d "/opt/1cv8/x86_64/${PLATFORM_OVERRIDE}" ]]; then
		PLATFORM_PATH="/opt/1cv8/x86_64/${PLATFORM_OVERRIDE}"
	else
		refuse "не найден каталог платформы: $PLATFORM_OVERRIDE"
	fi
fi
if [[ -n "$INFOBASE_OVERRIDE" ]]; then
	INFOBASE_KIND=server
	INFOBASE_PATH="$INFOBASE_OVERRIDE"
fi
if ((IB_USER_SET)); then
	IB_USER="$IB_USER_OVERRIDE"
	if [[ -z "$IB_USER" ]]; then
		IB_PASSWORD=""
	fi
fi
if [[ -n "$PLATFORM_OVERRIDE" ]]; then
	export DESIGNER_PLATFORM_PATH="$PLATFORM_PATH"
else
	unset DESIGNER_PLATFORM_PATH
fi
if [[ -n "$INFOBASE_OVERRIDE" ]]; then
	export DESIGNER_INFOBASE_KIND="$INFOBASE_KIND"
	export DESIGNER_INFOBASE_PATH="$INFOBASE_PATH"
else
	unset DESIGNER_INFOBASE_KIND DESIGNER_INFOBASE_PATH
fi
if ((IB_USER_SET)); then
	export DESIGNER_IB_USER_SET=1
	export DESIGNER_IB_USER="$IB_USER"
	export DESIGNER_IB_PASSWORD="${IB_PASSWORD:-}"
else
	unset DESIGNER_IB_USER_SET DESIGNER_IB_USER DESIGNER_IB_PASSWORD
fi

TIMEOUT="${TIMEOUT:-900}"
[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -gt 0 ]] || refuse "тайм-аут должен быть положительным числом секунд: $TIMEOUT"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
RUN_DIR="${OUT_DIR}/thick-client-check/run"
mkdir -p "$RUN_DIR"

if [[ "$MODE" == "snapshot" ]]; then
	[[ -n "$SNAP_META" || "$SNAP_KIND" == "main" ]] || refuse "snapshot требует --metadata или --kind main"
	PARAMS="${RUN_DIR}/snapshot-scenario.json"
	export SNAP_META SNAP_NUMBER SNAP_KIND SNAP_FORM SNAP_GENERATE SNAP_FROM SNAP_TO PARAMS
	python3 - <<'PY'
import json, os
step = {"action": "open_form", "kind": os.environ["SNAP_KIND"]}
if os.environ["SNAP_META"]:
    step["metadata"] = os.environ["SNAP_META"]
if os.environ["SNAP_NUMBER"]:
    step["number"] = os.environ["SNAP_NUMBER"]
if os.environ["SNAP_FORM"]:
    step["form"] = os.environ["SNAP_FORM"]
if os.environ["SNAP_GENERATE"] == "1":
    step["generate"] = True
if os.environ["SNAP_FROM"]:
    step["date_from"] = os.environ["SNAP_FROM"]
if os.environ["SNAP_TO"]:
    step["date_to"] = os.environ["SNAP_TO"]
path = os.environ["PARAMS"]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({"steps": [step]}, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
fi

[[ -n "$PARAMS" && -f "$PARAMS" ]] || refuse "не найден файл сценария (--params)"
python3 "$HOST" validate-scenario "$PARAMS" >/dev/null

V8=""
for exe in 1cv8 1cv8.exe; do
	if V8="$(dev_env_platform_exe "$exe" 2>/dev/null)"; then
		break
	fi
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
				server) CONN=(/S "${INFOBASE_PATH/\//\\}") ;;
				*) refuse "INFOBASE_KIND должен быть file или server: ${INFOBASE_KIND}" ;;
			esac ;;
	esac
elif [[ -n "${VRUNNER_IBCONNECTION:-}" ]]; then
	CONN=("${VRUNNER_IBCONNECTION:0:2}" "${VRUNNER_IBCONNECTION:2}")
else
	refuse "не задан INFOBASE_PATH (.dev.env) и нет VRUNNER_IBCONNECTION"
fi
if ((IB_USER_SET)); then
	USER_NAME="$IB_USER"
	PASSWORD="${IB_PASSWORD:-}"
else
	USER_NAME="${IB_USER:-${VRUNNER_DBUSER:-}}"
	PASSWORD="${IB_PASSWORD:-${VRUNNER_DBPWD:-}}"
fi
IB_KIND="${INFOBASE_KIND:-}"
IB_SHOWN="${INFOBASE_PATH:-${VRUNNER_IBCONNECTION:-}}"

hash_sources() {
	python3 - "$SRC_XML" "$SRC_ROOT/ТолстыйКлиентПроверка" <<'PY'
import hashlib, pathlib, sys
xml = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
paths = [xml] + sorted(p for p in root.rglob("*") if p.is_file())
digest = hashlib.sha256()
base = xml.parent
for path in paths:
    digest.update(str(path.relative_to(base)).encode())
    digest.update(b"\0")
    digest.update(path.read_bytes())
print(digest.hexdigest())
PY
}

python3 "$HOST" write-ordinary-form \
	"${SRC_ROOT}/ТолстыйКлиентПроверка/Forms/Форма/Ext/Form/Module.bsl" \
	"${SRC_ROOT}/ТолстыйКлиентПроверка/Forms/Форма/Ext/Form.bin" \
	|| refuse "не собрана обычная форма"
SRC_HASH="$(hash_sources)"
PLATFORM_BUILD="$(basename "$PLATFORM_PATH")"
META_VERSION="$(python3 "$HOST" metadata-version "$PLATFORM_BUILD")"
CACHE_DIR="${OUT_DIR}/thick-client-check/cache"
EPF="${CACHE_DIR}/${SRC_HASH}-${PLATFORM_BUILD}-f${META_VERSION}.epf"
mkdir -p "$CACHE_DIR"
if [[ ! -f "$EPF" ]]; then
	if ((DRY_RUN)); then
		echo "thick-client-check: dry-run, сборка epf не запускается (кэша нет: $EPF, формат ${META_VERSION})"
	else
		BUILD_LOG="${OUT_DIR}/thick-client-check/build.log"
		BUILD_RESULT="${OUT_DIR}/thick-client-check/build.result"
		BUILD_SRC="${CACHE_DIR}/src-${SRC_HASH}-f${META_VERSION}"
		mkdir -p "${OUT_DIR}/thick-client-check"
		python3 "$HOST" prepare-sources "$SRC_XML" "$BUILD_SRC" "$META_VERSION" \
			|| refuse "не подготовлены исходники формата ${META_VERSION}"
		echo "thick-client-check: сборка обработки (sha256 исходников ${SRC_HASH}, платформа ${PLATFORM_BUILD}, формат ${META_VERSION})"
		rm -f "$EPF"
		"${SCRIPT_DIR}/designer-batch.sh" --timeout 300 --out "$BUILD_LOG" --result "$BUILD_RESULT" -- \
			/LoadExternalDataProcessorOrReportFromFiles "${BUILD_SRC}/ТолстыйКлиентПроверка.xml" "$EPF" \
			|| refuse "сборка epf не удалась, лог $BUILD_LOG"
		[[ -s "$EPF" ]] || refuse "сборка не создала $EPF, лог $BUILD_LOG"
	fi
fi

SCENARIO="${RUN_DIR}/scenario.json"
OUT_LOG="${RUN_DIR}/enterprise.out"

ARGS=(ENTERPRISE "${CONN[@]}")
[[ -n "$USER_NAME" ]] && ARGS+=(/N "$USER_NAME")
[[ -n "$PASSWORD" ]] && ARGS+=(/P "$PASSWORD")
ARGS+=(
	/RunModeOrdinaryApplication
	/Execute "$EPF"
	/C "$SCENARIO"
	/L ru
	/DisableStartupMessages
	/Out "$OUT_LOG"
)
# /DisableStartupDialogs не передаётся: у диалога защиты от опасных действий
# кнопка по умолчанию — «Нет», и ключ молча запрещает /Execute. Диалоги
# закрывает наблюдатель по белому списку, а не этот ключ.

command -v Xvfb >/dev/null 2>&1 || { echo "thick-client-check: нет Xvfb — толстый клиент без своего экрана не запускаю." >&2; exit 3; }
command -v xdotool >/dev/null 2>&1 || refuse "нет xdotool"
command -v xwd >/dev/null 2>&1 || refuse "нет xwd"
command -v python3 >/dev/null 2>&1 || refuse "нет python3"

FIRST="${THICK_CLIENT_XVFB_FIRST:-120}"
DISPLAY_NUM="$FIRST"
while [[ -e "/tmp/.X${DISPLAY_NUM}-lock" || -e "/tmp/.X11-unix/X${DISPLAY_NUM}" ]]; do
	DISPLAY_NUM=$((DISPLAY_NUM + 1))
done

MASKED="$(mask_command "$V8" "${ARGS[@]}")"
echo "thick-client-check: экран=:${DISPLAY_NUM}, тайм-аут=${TIMEOUT}s"
echo "thick-client-check: $MASKED"
if ((DRY_RUN)); then
	exit 0
fi

cp "$PARAMS" "$SCENARIO"
printf '%s\n' "$EPF" >"${RUN_DIR}/executor.path"
sha256sum "$EPF" | awk -v path="$EPF" '{print path; print $1}' >"${RUN_DIR}/executor.sha"
: >"$OUT_LOG"
printf 'startup\n' >"${RUN_DIR}/phase"
rm -f "${RUN_DIR}/finished" "${RUN_DIR}/timeout.txt" "${RUN_DIR}/blocked-modal.txt" \
	"${RUN_DIR}/processor-result.json" "${RUN_DIR}/snap-request.json" \
	"${RUN_DIR}/dismissed.tsv" "${RUN_DIR}/expected-titles.txt" \
	"${RUN_DIR}"/snap-done-* "${RUN_DIR}"/snap-seen-* "${RUN_DIR}"/startup-*.png "${RUN_DIR}"/blocked-*.png

XVFB_PID=""
V8_PID=""
cleanup() {
	if [[ -n "$V8_PID" ]] && kill -0 "$V8_PID" 2>/dev/null; then
		kill -TERM -"$V8_PID" 2>/dev/null || kill -TERM "$V8_PID" 2>/dev/null || true
		sleep 1
		kill -KILL -"$V8_PID" 2>/dev/null || kill -KILL "$V8_PID" 2>/dev/null || true
	fi
	if [[ -n "$XVFB_PID" ]] && kill -0 "$XVFB_PID" 2>/dev/null; then
		kill "$XVFB_PID" 2>/dev/null || true
	fi
}
trap cleanup EXIT

Xvfb ":${DISPLAY_NUM}" -screen 0 1600x1200x24 -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 50); do
	[[ -e "/tmp/.X11-unix/X${DISPLAY_NUM}" ]] && break
	sleep 0.1
done
[[ -e "/tmp/.X11-unix/X${DISPLAY_NUM}" ]] || { echo "thick-client-check: Xvfb :${DISPLAY_NUM} не поднялся" >&2; exit 3; }

export DISPLAY=":${DISPLAY_NUM}"
unset WAYLAND_DISPLAY || true
# DISPLAY выше нужен xdotool/xwd этого сценария. 1cv8 получает его явно и не
# видит дисплей, который был у оболочки до запуска.

setsid "$V8" "${ARGS[@]}" >"${RUN_DIR}/enterprise-stdout.log" 2>&1 &
V8_PID=$!
echo "$V8_PID" >"${RUN_DIR}/1cv8.pid"
echo "$XVFB_PID" >"${RUN_DIR}/xvfb.pid"

declare -A SEEN=()
declare -A HANDLED=()
STARTED=$SECONDS
BLOCKED=0

window_name() {
	xdotool getwindowname "$1" 2>/dev/null || true
}

window_area() {
	local geom w h
	geom="$(xdotool getwindowgeometry --shell "$1" 2>/dev/null || true)"
	w="$(sed -n 's/^WIDTH=//p' <<<"$geom")"
	h="$(sed -n 's/^HEIGHT=//p' <<<"$geom")"
	[[ -n "${w:-}" && -n "${h:-}" ]] || { echo 0; return; }
	echo $((w * h))
}

shot_window() {
	local id="$1" png="$2" xwd="${png}.xwd"
	# У части окон GTK xwd -id даёт BadMatch. Тогда снимается весь свой экран.
	if ! xwd -id "$id" -silent >"$xwd" 2>/dev/null || [[ ! -s "$xwd" ]]; then
		xwd -root -silent >"$xwd"
	fi
	python3 "$HOST" xwd-to-png "$xwd" "$png"
	rm -f "$xwd"
}

trusted_epf() {
	local path sum got
	[[ -f "${RUN_DIR}/executor.sha" ]] || return 1
	path="$(sed -n '1p' "${RUN_DIR}/executor.sha")"
	sum="$(sed -n '2p' "${RUN_DIR}/executor.sha")"
	[[ "$path" == "${OUT_DIR}/thick-client-check/cache/"*.epf ]] || return 1
	[[ -f "$path" ]] || return 1
	got="$(sha256sum "$path" | awk '{print $1}')"
	[[ "$got" == "$sum" ]]
}

click_named_button() {
	local parent="$1" name="$2" id
	id="$(xdotool search --onlyvisible --pid "$V8_PID" --name "$name" 2>/dev/null | head -1 || true)"
	[[ -n "$id" && "$id" != "$parent" ]] || return 1
	xdotool windowactivate --sync "$id" click --window "$id" 1
}

dismiss_window() {
	local id="$1" action="$2" geom x y w h cx cy
	geom="$(xdotool getwindowgeometry --shell "$id" 2>/dev/null || true)"
	x="$(sed -n 's/^X=//p' <<<"$geom")"
	y="$(sed -n 's/^Y=//p' <<<"$geom")"
	w="$(sed -n 's/^WIDTH=//p' <<<"$geom")"
	h="$(sed -n 's/^HEIGHT=//p' <<<"$geom")"
	case "$action" in
		click-left)
			cx=$((x + w * 30 / 100))
			cy=$((y + h * 85 / 100))
			xdotool mousemove "$cx" "$cy" click 1 ;;
		click-right)
			cx=$((x + w * 70 / 100))
			cy=$((y + h * 85 / 100))
			xdotool mousemove "$cx" "$cy" click 1 ;;
		return)
			xdotool windowactivate --sync "$id" key Return ;;
		close)
			xdotool windowclose "$id" ;;
		*)
			return 1 ;;
	esac
}

title_expected() {
	local title="$1" line
	[[ -f "${RUN_DIR}/expected-titles.txt" ]] || return 1
	while IFS= read -r line; do
		[[ -n "$line" && "$title" == *"$line"* ]] && return 0
	done <"${RUN_DIR}/expected-titles.txt"
	return 1
}

watch_windows() {
	local id title action area max_area max_id phase small now png
	max_area=0
	max_id=""
	local ids=()
	while read -r id; do
		[[ -n "$id" ]] && ids+=("$id")
	done < <(xdotool search --pid "$V8_PID" 2>/dev/null || true)
	if ((${#ids[@]})); then
	for id in "${ids[@]}"; do
		area="$(window_area "$id")"
		if ((area > max_area)); then
			max_area=$area
			max_id=$id
		fi
	done
	fi
	phase="$(tr -d '\r\n' <"${RUN_DIR}/phase" 2>/dev/null || echo startup)"
	now=$SECONDS
	if ((${#ids[@]})); then
	for id in "${ids[@]}"; do
		[[ -n "$id" ]] || continue
		title="$(window_name "$id")"
		[[ -n "$title" ]] || continue
		[[ "$title" == *thick-client-check* ]] && continue
		# Пока платформа не поставила заголовок, имя окна совпадает с именем процесса.
		[[ "$title" == "1cv8" || "$title" == "1cv8c" ]] && continue
		# Служебная заставка закрывается сама. Это не модальный вопрос.
		[[ "$title" == *"Загрузка конфигурационной информации"* ]] && continue
		[[ "$title" == *"частичная синхронизация"* ]] && continue
		if [[ -z "${SEEN[$id]:-}" ]]; then
			SEEN[$id]=$now
		fi
		if action="$(dismiss_action "$title")"; then
			if [[ "$action" == "confirm-safe" ]]; then
				if [[ "$phase" != "startup" ]] || ! trusted_epf; then
					action=""
				fi
			fi
			if [[ -n "$action" && -z "${HANDLED[$id]:-}" ]]; then
				png="${RUN_DIR}/startup-${id}.png"
				shot_window "$id" "$png" || true
				note="$action"
				if [[ "$action" == "confirm-safe" ]]; then
					if click_named_button "$id" "Да" || click_named_button "$id" "Yes"; then
						note="кнопка «Да»"
					else
						dismiss_window "$id" click-left || true
						note="кнопка отдельным окном не найдена, нажата левая нижняя доля окна"
					fi
				else
					dismiss_window "$id" "$action" || true
				fi
				printf '%s\t%s\t%s\n' "$title" "$png" "$note" >>"${RUN_DIR}/dismissed.tsv"
				HANDLED[$id]=1
			fi
			if [[ -n "$action" ]]; then
				continue
			fi
		fi
		if title_expected "$title"; then
			continue
		fi
		if [[ "$id" == "$max_id" ]]; then
			continue
		fi
		area="$(window_area "$id")"
		small=0
		# Крупное окно — форма документа или отчёта. Маленькое неизвестное — диалог.
		if ((area > 0 && area < 700 * 500)); then
			small=1
		fi
		# Пока главного окна нет, маленькие окна — заставка, а не вопрос.
		if ((max_area < 800 * 600)); then
			continue
		fi
		# Заголовок главного окна длинный. Диалог вопроса короткий.
		if ((${#title} > 40)); then
			continue
		fi
		if [[ "$small" == 1 ]] && ((now - SEEN[$id] >= 2)); then
				png="${RUN_DIR}/blocked-${id}.png"
				shot_window "$id" "$png" || true
				printf '%s\nснимок: %s\n' "$title" "$png" >"${RUN_DIR}/blocked-modal.txt"
				BLOCKED=1
				return
		fi
	done
	fi
}

serve_snapshot() {
	local request="${RUN_DIR}/snap-request.json"
	[[ -f "$request" ]] || return 0
	local SNAP_STEP="" SNAP_MODE="" SNAP_TITLE="" SNAP_PNG=""
	local step mode title png
	eval "$(python3 "$HOST" snap-shell "$request")" || return 0
	step="$SNAP_STEP"
	mode="$SNAP_MODE"
	title="$SNAP_TITLE"
	png="$SNAP_PNG"
	[[ -e "${RUN_DIR}/snap-done-${step}" ]] && return 0
	# Окно появляется раньше, чем форма успевает нарисовать команды и таблицу.
	local seen_file="${RUN_DIR}/snap-seen-${step}"
	if [[ ! -f "$seen_file" ]]; then
		printf '%s\n' "$SECONDS" >"$seen_file"
		return 0
	fi
	local seen_at=0
	seen_at="$(tr -d '\r\n' <"$seen_file")"
	if ((SECONDS - seen_at < 2)); then
		return 0
	fi
	if [[ "$mode" == "root" ]]; then
		local xwd="${png}.xwd"
		xwd -root -silent >"$xwd"
		python3 "$HOST" xwd-to-png "$xwd" "$png"
		rm -f "$xwd"
	else
		local id found="" area best=0 best_id=""
		while read -r id; do
			[[ -n "$id" ]] || continue
			local name
			name="$(window_name "$id")"
			[[ "$name" == *thick-client-check* ]] && continue
			if [[ -n "$title" && "$name" == *"$title"* ]]; then
				found="$id"
				break
			fi
			area="$(window_area "$id")"
			if ((area > best)); then
				best=$area
				best_id=$id
			fi
		done < <(xdotool search --pid "$V8_PID" 2>/dev/null || true)
		[[ -n "$found" ]] || found="$best_id"
		[[ -n "$found" ]] || return 0
		shot_window "$found" "$png"
		[[ -s "$png" ]] || return 0
		: >"${RUN_DIR}/snap-done-${step}"
		# Окно закрывает исполнитель после маркера. windowclose здесь роняет 1cv8
		# (GdkWindow unexpectedly destroyed, RenderBadPicture).
		return 0
	fi
	[[ -s "$png" ]] || return 0
	: >"${RUN_DIR}/snap-done-${step}"
}

while kill -0 "$V8_PID" 2>/dev/null; do
	if ((SECONDS - STARTED >= TIMEOUT)); then
		echo "тайм-аут ${TIMEOUT}s" >"${RUN_DIR}/timeout.txt"
		echo "thick-client-check: тайм-аут ${TIMEOUT}s, снимаю свой процесс и Xvfb" >&2
		kill -TERM -"$V8_PID" 2>/dev/null || true
		sleep 1
		kill -KILL -"$V8_PID" 2>/dev/null || true
		break
	fi
	watch_windows || true
	if ((BLOCKED)); then
		echo "thick-client-check: неизвестное модальное окно, процесс снят" >&2
		kill -TERM -"$V8_PID" 2>/dev/null || true
		sleep 1
		kill -KILL -"$V8_PID" 2>/dev/null || true
		break
	fi
	serve_snapshot || true
	sleep 0.4
done

set +e
wait "$V8_PID"
PROC_RC=$?
set -e
V8_PID=""

META="${RUN_DIR}/report-meta.json"
printf '%s\n' "$MASKED" >"${RUN_DIR}/command.masked"
python3 - "$META" "${RUN_DIR}/command.masked" "${PLATFORM_PATH:-}" "$IB_KIND" "$IB_SHOWN" "$USER_NAME" "$(date -Iseconds)" "$PROC_RC" "$OUT_LOG" <<'PY'
import json, sys
meta, command, platform, kind, base, user, finished, code, out_log = sys.argv[1:10]
json.dump({
    "command": open(command, encoding="utf-8").read().strip(),
    "platform": platform,
    "infobase_kind": kind,
    "infobase": base,
    "user": user,
    "started": "",
    "finished": finished,
    "process_exit": int(code),
    "out_log": out_log,
}, open(meta, "w"), ensure_ascii=False, indent=2)
open(meta, "a").write("\n")
PY

set +e
python3 "$HOST" build-report "$RUN_DIR" "${OUT_DIR}/thick-client-check.json" "${OUT_DIR}/thick-client-check.txt" "$META"
REPORT_RC=$?
set -e
# Свой Xvfb больше не нужен: cleanup на выходе снимет его, если он ещё жив.
if [[ -f "${RUN_DIR}/timeout.txt" || -f "${RUN_DIR}/blocked-modal.txt" ]]; then
	exit 1
fi
exit "$REPORT_RC"
