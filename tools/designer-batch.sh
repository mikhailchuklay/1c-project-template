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
  --main-config   осознанная проверка только основной конфигурации: снимает отказ
                  /CheckModules, /CheckConfig, /CheckCanApplyConfigurationExtensions
                  без -Extension при заданном EXTENSION_NAME
  --repository    добавить параметры хранилища из .dev.env (/ConfigurationRepositoryF, N, P):
                  нужны загрузке по списку файлов (/LoadConfigFromFiles -listFile) в базу,
                  подключённую к хранилищу — полная загрузка туда платформой запрещена.
                  Командам хранилища (/ConfigurationRepositoryBindCfg, Lock, UnLock, Commit,
                  UpdateCfg, DumpCfg, Report, …) параметры добавляются сами, ключ не нужен
  --self-test     прогнать разбор лога на контрольных строках и выйти
  -h, --help      эта справка

Одна пакетная команда на запуск. Подключение к базе (/F, /S, /N, /P) и к хранилищу
(/ConfigurationRepositoryF, N, P), /Out, /DumpResult и /DisableStartup* обёртка ставит
сама — в аргументах их не передавать (отказ, код 2). Пароли в выводе скрыты.
Расширение в своём хранилище: REPOSITORY_PATH — хранилище расширения, у команды
ключ -Extension <имя>, например:
  tools/designer-batch.sh -- /ConfigurationRepositoryLock -Extension Расш1 -Objects список.xml

Переменные (.dev.env или окружение):
  PLATFORM_PATH, INFOBASE_KIND, INFOBASE_PATH, IB_USER, IB_PASSWORD
  (запасной вариант: VRUNNER_IBCONNECTION, VRUNNER_DBUSER, VRUNNER_DBPWD)
  REPOSITORY_PATH, REPOSITORY_USER, REPOSITORY_PASSWORD  для хранилища
  (запасной вариант: VRUNNER_STORAGE_NAME, VRUNNER_STORAGE_USER, VRUNNER_STORAGE_PWD;
  пароль — ещё файл REPOSITORY_PASSWORD_FILE, по умолчанию ~/.secrets/storage-password)
  DESIGNER_TIMEOUT          тайм-аут по умолчанию, с
  DESIGNER_HEAVY_LOCK       блокировка «одна тяжёлая операция на хост»
                            (по умолчанию $AGENT_LOCKS/designer-heavy.lock при заданном AGENT_LOCKS)
  DESIGNER_BATCH_MAIN_CONFIG_APPROVED=1  --main-config агенту после согласования архитектора
  DESIGNER_BATCH_REPO_BIND_APPROVED=1    /ConfigurationRepositoryBindCfg и UnbindCfg после
                            согласования архитектора (только окружение, не .dev.env)
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
# Слова диагностики — только с начала слова: «ЗвукОшибки», «Расш1К_ОшибкиОбмена»
# в именах объектов не диагностика (BM-1707: «Объект захвачен для редактирования:
# ОбщийМакет.Расш1К_ЗвукОшибки» при коде 0 и /DumpResult 0).
errors = r'\bошиб|\bне\s+найден|\bне\s+обнаружен|\bне\s+удалось|\bне\s+может\s+быть\s+применен|\bневозможно|\berror|\bfatal|\bfailed|\bfailure|\bexception'
warnings = r'\bпредупрежд|\bwarning'
# Полные имена объектов метаданных (Справочник.Ошибки, ОбщийМакет.Х.Макет) — данные,
# а не текст платформы: из строки убираются до поиска слов диагностики.
object_name = r'[^\W\d]\w*(?:\.[^\W\d]\w*)+'
bad = []
for line in text.splitlines():
    low = line.lower()
    for pat in success:
        low = re.sub(pat, ' ', low)
    low = re.sub(object_name, ' ', low)
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

refuse() { echo "designer-batch: $*" >&2; exit 2; }

# Команды хранилища, которые обёртка запускает (имена в нижнем регистре, без
# префикса /ConfigurationRepository). Администрирование хранилища (Create, AddUser,
# CopyUsers, OptimizeData) — не здесь: Devbox MCP storage_* или владелец хранилища.
REPO_COMMANDS=" bindcfg unbindcfg lock unlock commit updatecfg dumpcfg report setlabel clearcache clearglobalcache clearlocalcache "
REPO_ADMIN_COMMANDS=" create adduser copyusers optimizedata "
# Подключение базы к хранилищу и отключение — только по согласованию архитектора
# (инварианты 5–6 навыка 1c-repository-manage): DESIGNER_BATCH_REPO_BIND_APPROVED=1
# в окружении запуска. Значение из .dev.env не действует: .dev.env читается после проверки.
REPO_BIND_COMMANDS=" bindcfg unbindcfg "

# Разбор аргументов пакетной команды. Отказ — refuse (код 2). Задаёт CMD — команду
# в нижнем регистре — и REPO_CMD=1, если это команда хранилища (ей нужны параметры
# хранилища из .dev.env, как при --repository).
check_batch() {
	local BATCH=("$@") cmd_count=0 i a lc next name
	CMD=""
	REPO_CMD=0
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
		if [[ "$lc" == /configurationrepository* ]]; then
			local sub="${lc#/configurationrepository}"
			# Подключение к хранилищу (F — путь, N — пользователь, P — пароль), отдельной
			# или слитной формой: только из .dev.env, как /N и /P базы.
			if [[ "$sub" =~ ^[fnp]([^a-z]|$) ]]; then
				local key="${sub:0:1}"
				refuse "ключ «/ConfigurationRepository${key^^}» задаёт обёртка из REPOSITORY_PATH, REPOSITORY_USER и REPOSITORY_PASSWORD (или ~/.secrets/storage-password) — уберите его из аргументов"
			fi
			if [[ "$REPO_ADMIN_COMMANDS" == *" $sub "* ]]; then
				refuse "«$a» — администрирование хранилища, не пакетная работа агента: Devbox MCP (storage_*) или владелец хранилища"
			fi
			if [[ ! "$a" =~ ^/[A-Za-z]+$ || "$REPO_COMMANDS" != *" $sub "* ]]; then
				refuse "неизвестная команда хранилища «$a»: обёртка запускает только /ConfigurationRepository{BindCfg,UnbindCfg,Lock,UnLock,Commit,UpdateCfg,DumpCfg,Report,SetLabel,ClearCache,ClearGlobalCache,ClearLocalCache}"
			fi
			if [[ "$REPO_BIND_COMMANDS" == *" $sub "* && "${DESIGNER_BATCH_REPO_BIND_APPROVED:-}" != 1 ]]; then
				refuse "«$a» — подключение базы к хранилищу или отключение от него: только по согласованию архитектора (инварианты 5–6 навыка 1c-repository-manage). Агенту — agent-state question с причиной; после ответа запуск с DESIGNER_BATCH_REPO_BIND_APPROVED=1 (designer-batch-checks.mdc → Configuration repository operations)."
			fi
			REPO_CMD=1
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
pass|Объект захвачен для редактирования: ОбщийМакет.Расш1К_ЗвукОшибки
pass|Захват объекта отменен: ОбщийМакет.Расш1К_ЗвукОшибки
pass|Объект помещен в хранилище: Справочник.Ошибки
pass|Обработка РегистрацияОшибокОбмена получена из хранилища
fail|{ОбщийМодуль.Расш1К_ЗвукОшибки.Модуль(12,5)}: Ошибка компиляции
fail|Справочник.Ошибки: не удалось захватить объект
fail|Объект ОбщийМакет.Расш1К_ЗвукОшибки захвачен другим пользователем. Невозможно захватить объект
EOF
	if ((fails)); then return 1; fi
	echo "self-test: разбор лога исправен"

	# Аргументы пакетной команды: ожидаемый вердикт check_batch (ok — принят, refuse — код 2).
	# approved:<вердикт> — тот же разбор с DESIGNER_BATCH_REPO_BIND_APPROVED=1, иначе без него.
	local args approved
	local -a argv
	while IFS='|' read -r expect args; do
		[[ -z "$expect" ]] && continue
		approved=""
		if [[ "$expect" == approved:* ]]; then approved=1; expect="${expect#approved:}"; fi
		eval "argv=($args)"
		if (DESIGNER_BATCH_REPO_BIND_APPROVED="$approved"; check_batch "${argv[@]}") >/dev/null 2>&1; then got=ok; else got=refuse; fi
		if [[ "$got" != "$expect" ]]; then
			echo "НЕВЕРНО: аргументы — ожидалось $expect, получено $got: $args" >&2
			fails=$((fails + 1))
		fi
	done <<'ARGS'
ok|/CheckModules -Extension Расш1 -Server
refuse|/ConfigurationRepositoryBindCfg -Extension Расш1 -forceBindAlreadyBindedUser -forceReplaceCfg
refuse|/ConfigurationRepositoryUnbindCfg -Extension Расш1 -force
approved:ok|/ConfigurationRepositoryBindCfg -Extension Расш1 -forceBindAlreadyBindedUser -forceReplaceCfg
approved:ok|/ConfigurationRepositoryUnbindCfg -Extension Расш1 -force
approved:refuse|/ConfigurationRepositoryCreate -Extension Расш1
ok|/ConfigurationRepositoryLock -Extension Расш1 -Objects /tmp/objects.xml
ok|/ConfigurationRepositoryCommit -Extension Расш1 -Objects /tmp/objects.xml -comment "BM-1707"
ok|/ConfigurationRepositoryUnLock -Extension Расш1 -Objects /tmp/objects.xml
ok|/ConfigurationRepositoryUpdateCfg -Extension Расш1 -force
ok|/ConfigurationRepositoryReport /tmp/report.mxl -Extension Расш1
refuse|/ConfigurationRepositoryF tcp://srv/repo /ConfigurationRepositoryLock
refuse|/ConfigurationRepositoryN agent1 /ConfigurationRepositoryLock
refuse|/ConfigurationRepositoryP secret /ConfigurationRepositoryLock
refuse|'/ConfigurationRepositoryF"tcp://srv/repo"' /ConfigurationRepositoryLock
refuse|/ConfigurationRepositoryNagent1 /ConfigurationRepositoryLock
refuse|/ConfigurationRepositoryPsecret /ConfigurationRepositoryLock
refuse|/ConfigurationRepositoryCreate -Extension Расш1
refuse|/ConfigurationRepositoryAddUser -User x -Pwd y
refuse|/ConfigurationRepositoryLock /ConfigurationRepositoryCommit
refuse|/N admin /CheckModules
refuse|/EraseData
ARGS
	if ((fails)); then return 1; fi
	echo "self-test: разбор аргументов исправен"
}

# ---------------------------------------------------------------------------
# Аргументы
# ---------------------------------------------------------------------------
TIMEOUT=""
OUT_FILE=""
RESULT_FILE=""
LOAD_MODE=0
DRY_RUN=0
MAIN_CONFIG=0
WITH_REPO=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--timeout) TIMEOUT="${2:?--timeout требует значение}"; shift 2 ;;
		--out) OUT_FILE="${2:?--out требует значение}"; shift 2 ;;
		--result) RESULT_FILE="${2:?--result требует значение}"; shift 2 ;;
		--load) LOAD_MODE=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		--main-config) MAIN_CONFIG=1; shift ;;
		--repository) WITH_REPO=1; shift ;;
		--self-test) self_test; exit $? ;;
		-h|--help) usage; exit 0 ;;
		--) shift; break ;;
		*) break ;;
	esac
done
BATCH=("$@")

[[ ${#BATCH[@]} -gt 0 ]] || { usage >&2; exit 2; }

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*|Windows_NT)
		refuse "Windows: используйте PowerShell-рецепт designer-batch-checks.mdc (Start-Process -WindowStyle Hidden)" ;;
esac

check_batch "${BATCH[@]}"
((REPO_CMD)) && WITH_REPO=1

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

# Один запуск поверх .dev.env. Ставит обёртка thick-client-check: сборка EPF
# идёт той же платформой и в ту же базу, что и предприятие.
if [[ -n "${DESIGNER_PLATFORM_PATH:-}" ]]; then
	PLATFORM_PATH="$DESIGNER_PLATFORM_PATH"
fi
if [[ -n "${DESIGNER_INFOBASE_PATH:-}" ]]; then
	INFOBASE_KIND="${DESIGNER_INFOBASE_KIND:-server}"
	INFOBASE_PATH="$DESIGNER_INFOBASE_PATH"
fi
if [[ "${DESIGNER_IB_USER_SET:-}" == "1" ]]; then
	IB_USER="${DESIGNER_IB_USER:-}"
	IB_PASSWORD="${DESIGNER_IB_PASSWORD:-}"
fi

# Без -Extension проверки идут только по основной конфигурации: модули расширения
# не компилируются, а лог всё равно пишет «ошибок не обнаружено».
case "$CMD" in
	/checkmodules|/checkconfig|/checkcanapplyconfigurationextensions)
		has_ext=0
		for a in "${BATCH[@]}"; do [[ "${a,,}" == -extension ]] && has_ext=1; done
		if ((has_ext == 0 && MAIN_CONFIG == 0)) && [[ -n "${EXTENSION_NAME// /}" ]]; then
			refuse "${CMD} без -Extension не проверяет расширение адресно (/CheckModules и /CheckConfig — только основную конфигурацию). Добавьте -Extension \"${EXTENSION_NAME}\" (designer-batch-checks.mdc → The check ladder) или --main-config для осознанной проверки основной конфигурации."
		fi
		;;
esac

# Проверка всей типовой (--main-config) на БП идёт десятки минут и грузит общий хост агентов.
# Агенту без интерфейса — только по согласованию архитектора (question с оценкой времени).
if ((MAIN_CONFIG)) && [[ -n "${AGENT_HARNESS:-}" && "${DESIGNER_BATCH_MAIN_CONFIG_APPROVED:-}" != 1 ]]; then
	refuse "--main-config у агента — только по согласованию архитектора: agent-state question с целью и оценкой времени; после ответа запуск с DESIGNER_BATCH_MAIN_CONFIG_APPROVED=1 (designer-batch-checks.mdc → Heavy runs on a shared host)."
fi

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
if [[ "${DESIGNER_IB_USER_SET:-}" == "1" ]]; then
	USER_NAME="${IB_USER}"
	PASSWORD="${IB_PASSWORD:-}"
else
	USER_NAME="${IB_USER:-${VRUNNER_DBUSER:-}}"
	PASSWORD="${IB_PASSWORD:-${VRUNNER_DBPWD:-}}"
fi

ARGS=(DESIGNER "${CONN[@]}")
[[ -n "$USER_NAME" ]] && ARGS+=(/N "$USER_NAME")
[[ -n "$PASSWORD" ]] && ARGS+=(/P "$PASSWORD")
ARGS+=(/DisableStartupDialogs /DisableStartupMessages)
if ((WITH_REPO)); then
	REPO_PATH="${REPOSITORY_PATH:-${VRUNNER_STORAGE_NAME:-}}"
	REPO_USER="${REPOSITORY_USER:-${VRUNNER_STORAGE_USER:-}}"
	if [[ "${REPOSITORY_PASSWORD_EMPTY:-}" == 1 ]]; then
		# Явно пустой пароль пользователя хранилища (например, agent<N> без пароля). Ни
		# VRUNNER_STORAGE_PWD, ни общий ~/.secrets/storage-password не подставляются: там пароль
		# другого пользователя или проекта, и хранилище отвечает «неверный пароль».
		REPO_PWD=""
	else
		REPO_PWD="${REPOSITORY_PASSWORD:-${VRUNNER_STORAGE_PWD:-}}"
		# В контейнере агента пароль хранилища лежит в файле, а не в .dev.env.
		REPO_PWD_FILE="${REPOSITORY_PASSWORD_FILE:-$HOME/.secrets/storage-password}"
		if [[ -z "$REPO_PWD" && -r "$REPO_PWD_FILE" ]]; then
			REPO_PWD="$(tr -d '\r\n' <"$REPO_PWD_FILE")"
		fi
	fi
	[[ -n "$REPO_PATH" ]] || refuse "${CMD} требует хранилище: не задан REPOSITORY_PATH (.dev.env) и нет VRUNNER_STORAGE_NAME"
	ARGS+=(/ConfigurationRepositoryF "$REPO_PATH")
	[[ -n "$REPO_USER" ]] && ARGS+=(/ConfigurationRepositoryN "$REPO_USER")
	[[ -n "$REPO_PWD" ]] && ARGS+=(/ConfigurationRepositoryP "$REPO_PWD")
fi
ARGS+=("${BATCH[@]}" /Out "$OUT_FILE" /DumpResult "$RESULT_FILE")

masked() {
	local out=() prev=""
	for a in "$@"; do
		if [[ "${prev,,}" == /p || "${prev,,}" == /configurationrepositoryp ]]; then out+=("***"); else out+=("$a"); fi
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

# Одна тяжёлая операция Конфигуратора на хост: общий для контейнеров каталог блокировок
# (AGENT_LOCKS у агентов) или DESIGNER_HEAVY_LOCK. Ждём не дольше своего тайм-аута.
HEAVY_LOCK="${DESIGNER_HEAVY_LOCK:-${AGENT_LOCKS:+${AGENT_LOCKS}/designer-heavy.lock}}"
case "$CMD" in
	/checkmodules|/checkconfig|/dumpconfigtofiles|/loadconfigfromfiles|/updatedbcfg)
		if [[ -n "$HEAVY_LOCK" ]] && command -v flock >/dev/null 2>&1; then
			exec 9>>"$HEAVY_LOCK" || refuse "не открыть блокировку $HEAVY_LOCK"
			if ! flock -n 9; then
				echo "designer-batch: на хосте идёт другая тяжёлая операция Конфигуратора, жду до ${TIMEOUT}s ($HEAVY_LOCK)" >&2
				flock -w "$TIMEOUT" 9 || { echo "designer-batch: не дождался блокировки $HEAVY_LOCK за ${TIMEOUT}s" >&2; exit 1; }
			fi
		fi ;;
esac
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
