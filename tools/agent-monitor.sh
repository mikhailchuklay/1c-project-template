#!/usr/bin/env bash
# Монитор задачи headless-агента для архитектора (docs/headless-agent.md, «Следи сам, а не жди статуса»).
#
# Раз в минуту читает по ssh состояние задачи (`agent-state get`), свежесть файлов и процессы агента
# и печатает строку только при событии:
#   state=<состояние> ...   — состояние сменилось;
#   IDLE: ...               — файлы не менялись дольше порога (один раз до возобновления активности);
#   ssh fail                — нет связи; монитор ждёт минуту и продолжает (обрыв ssh не завершает его).
# Завершается с кодом 0, когда задача пришла в review, question, error или committed
# (итоговое состояние при живом процессе агента до первого «working» считается хвостом прошлого прогона);
# с --exit-on-idle — с кодом 3 при первом IDLE (архитектору пора посмотреть на агента).
#
# Запускать фоновой командой Bash (run_in_background): она не ограничена 30 минутами,
# как инструмент Monitor, и будит архитектора по выходу скрипта. Скрипт — из tools/ рабочей копии,
# не копия во временной папке.
#
# Активность — по mtime файлов рабочего дерева и ~/tasks/<task> (без .git), а не по росту run-N.log:
# харнес cursor с `-p --output-format json` пишет лог только в конце прогона, и «лог не растёт»
# давало ложный IDLE (задача #43 1c-integration-api-bp).
#
# Только чтение: в контейнере ничего не меняет.
#
# Пример (фоновое ожидание после agent-run):
#   tools/agent-monitor.sh --exit-on-idle 1 advance-limits-43 25 issue-43-advance-limits
set -uo pipefail

usage() {
	cat <<EOF
Использование: $0 [--once | --exit-on-idle] <контейнер> <task> [idle-минуты] [рабочее-дерево]
  контейнер       номер контейнера агента: 1, 2, 3 (контейнер dev-agent<N>) или полное имя
  task            идентификатор задачи agent-state
  idle-минуты     порог предупреждения IDLE, по умолчанию 25
  рабочее-дерево  каталог рабочего дерева задачи: имя в ~/work или абсолютный путь в контейнере;
                  по умолчанию следить только за ~/tasks/<task>
  --once          один замер, вывод «state возраст процессы», без ожидания
  --exit-on-idle  выйти с кодом 3 при первом IDLE (по умолчанию — предупредить и ждать дальше)

Коды возврата: 0 — задача в review/question/error/committed; 3 — IDLE (с --exit-on-idle);
1 — ssh fail при --once; 2 — ошибка аргументов.

Переменные окружения:
  AGENT_SSH_HOST          ssh-алиас хоста контейнеров (по умолчанию dev-workplaces-via-services)
  AGENT_CONTAINER_PREFIX  префикс, приписываемый к аргументу как есть (по умолчанию не задан)
  AGENT_EXEC_USER         пользователь docker exec (по умолчанию dev)
  AGENT_MONITOR_INTERVAL  пауза между замерами, секунд (по умолчанию 60)
  AGENT_MONITOR_WINDOW    окно поиска свежих файлов, минут (по умолчанию 600)
EOF
}

ONCE=0
EXIT_ON_IDLE=0
while [[ "${1:-}" == -* ]]; do
	case "$1" in
		--once) ONCE=1; shift ;;
		--exit-on-idle) EXIT_ON_IDLE=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Неизвестный параметр: $1" >&2; usage >&2; exit 2 ;;
	esac
done
if [[ $# -lt 2 ]]; then usage >&2; exit 2; fi

C=$1
T=$2
IDLE=${3:-25}
W=${4:-}
SSH_HOST=${AGENT_SSH_HOST:-dev-workplaces-via-services}
# Имя контейнера: номер N -> dev-agent<N> (универсальные контейнеры с 21.11.2026), полное имя dev-agent… — как есть,
# прежний суффикс по харнесу (cursor1) -> dev-agent-cursor1. AGENT_CONTAINER_PREFIX, если задан, просто приписывается.
agent_container() {
	if [[ -n "${AGENT_CONTAINER_PREFIX:-}" ]]; then printf '%s%s' "$AGENT_CONTAINER_PREFIX" "$1"
	elif [[ "$1" == dev-agent* ]]; then printf '%s' "$1"
	elif [[ "$1" =~ ^[0-9]+$ ]]; then printf 'dev-agent%s' "$1"
	else printf 'dev-agent-%s' "$1"; fi
}
CONTAINER=$(agent_container "$C")
EXEC_USER=${AGENT_EXEC_USER:-dev}
INTERVAL=${AGENT_MONITOR_INTERVAL:-60}
WINDOW=${AGENT_MONITOR_WINDOW:-600}

for n in "$IDLE" "$INTERVAL" "$WINDOW"; do
	[[ "$n" =~ ^[0-9]+$ ]] || { echo "Ожидалось целое число, получено: $n" >&2; exit 2; }
done

# Замер внутри контейнера. Скрипт идёт через stdin (`bash -s`), аргументы — позиционные:
# без вложенного экранирования кавычек на пути ssh → docker exec → bash.
# Вывод: "<state> <возраст активности, мин> <число процессов агента>"; state "?" — agent-state не ответил.
# shellcheck disable=SC2016  # переменные раскрываются в контейнере
REMOTE='
T=$1; W=$2; WINDOW=$3
st=$(agent-state get "$T" 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)[\"state\"])" 2>/dev/null)
dirs=("$HOME/tasks/$T")
if [ -n "$W" ]; then case "$W" in /*) dirs+=("$W");; *) dirs+=("$HOME/work/$W");; esac; fi
nw=$(find "${dirs[@]}" -type f -newermt "$WINDOW minutes ago" -not -path "*/.git/*" -printf "%T@\n" 2>/dev/null | sort -n | tail -1 | cut -d. -f1)
if [ -n "$nw" ]; then age=$(( ($(date +%s) - nw) / 60 )); else age=$WINDOW; fi
p=$(pgrep -u "$(id -un)" -f "1cv8|vrunner |cursor-agent|codex|dsh" | wc -l)
echo "${st:-?} $age $p"
'

probe() {
	# shellcheck disable=SC2029  # имена контейнера и пользователя раскрываются локально намеренно
	ssh -o ConnectTimeout=20 -o BatchMode=yes "$SSH_HOST" \
		"docker exec -i -u $EXEC_USER $CONTAINER bash -s -- $(printf '%q ' "$T" "$W" "$WINDOW")" <<<"$REMOTE" 2>/dev/null
}

if [[ $ONCE -eq 1 ]]; then
	out=$(probe) || { echo "ssh fail" >&2; exit 1; }
	echo "$out"
	exit 0
fi

prev=""
idle_warned=0
seen_working=0
while true; do
	if ! out=$(probe) || [[ -z "$out" ]]; then
		echo "ssh fail"
		sleep "$INTERVAL"
		continue
	fi
	read -r st age procs <<<"$out"
	if [[ "$st" != "$prev" ]]; then
		echo "state=$st (activity age ${age}m, procs $procs)"
		prev=$st
		idle_warned=0
	fi
	[[ "$st" == working ]] && seen_working=1
	# Итоговое состояние при живом процессе агента и без увиденного «working» — хвост прошлого прогона:
	# agent-run ещё не перевёл задачу в working (ложная «сдача» в #106 1c-integration-api-bp, 19.11.2026).
	case "$st" in review | question | error | committed)
		if ((seen_working)) || [[ "${procs:-0}" -eq 0 ]]; then exit 0; fi ;;
	esac
	if [[ "${age:-0}" -ge "$IDLE" ]]; then
		if [[ $idle_warned -eq 0 ]]; then
			echo "IDLE: no file activity ${age}m, procs $procs"
			((EXIT_ON_IDLE)) && exit 3
			idle_warned=1
		fi
	else
		idle_warned=0
	fi
	sleep "$INTERVAL"
done
