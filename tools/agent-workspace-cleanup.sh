#!/usr/bin/env bash
# Уборка рабочих деревьев headless-агентов в контейнере (SVC-033-I 1.9, docs/headless-agent.md «Уборка»).
#
# Уборка — зона архитектора, владельцу на согласование не выносится. Скрипт делает её безопасно и
# повторяемо, чтобы сессия архитектора не писала ad-hoc `rm -rf` (их блокирует режим auto).
#
# Кандидат — каталог в ~/work контейнера, который является git worktree (файл .git, не каталог).
# Клоны (.git — каталог), каталоги без git и всё вне ~/work не трогаются никогда. Каталог ПРОПУСКАЕТСЯ, если:
#   - его держит активная задача: запись блокировки agent-state в состоянии working/question/review,
#     или agent-status.json задачи в этом состоянии ссылается на каталог;
#   - в нём или под ним работает процесс (cwd);
#   - он подготовлен меньше суток назад под задачу, которую ещё не запускали (нет ~/tasks/<каталог>/agent-status.json);
#   - его ветка не влита в origin/main и не запушена (иначе коммиты потеряются);
#   - он назван в --keep.
# Незакоммиченные изменения перед удалением сохраняются патчем:
#   ~/tasks/<каталог>/leftover-uncommitted-<ГГГГММДД>.patch
# Удаление — `git worktree remove --force` из основного клона этого worktree и `git worktree prune`.
#
# По умолчанию — сухой прогон (план). --apply — удалить. Печатает du -sh ~/work до и после.
#
# Пример:
#   tools/agent-workspace-cleanup.sh 1                  # план
#   tools/agent-workspace-cleanup.sh --apply 1          # удалить
#   tools/agent-workspace-cleanup.sh --apply --keep advance-offset-upd2-102 1
set -uo pipefail

usage() {
	cat <<EOF
Использование: $0 [--apply] [--keep <каталог>]... <контейнер>
  контейнер   номер контейнера агента: 1, 2, 3 (контейнер dev-agent<N>) или полное имя
  --apply     удалить (по умолчанию — только план)
  --keep D    не трогать каталог ~/work/D (можно повторять)

Коды возврата: 0 — успех; 1 — ssh/docker недоступен; 2 — ошибка аргументов.

Переменные окружения:
  AGENT_SSH_HOST          ssh-алиас хоста контейнеров (по умолчанию dev-workplaces-via-services)
  AGENT_CONTAINER_PREFIX  префикс, приписываемый к аргументу как есть (по умолчанию не задан)
  AGENT_EXEC_USER         пользователь docker exec (по умолчанию dev)
EOF
}

APPLY=0
KEEP=()
while [[ "${1:-}" == -* ]]; do
	case "$1" in
		--apply) APPLY=1; shift ;;
		--keep) [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; KEEP+=("$2"); shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Неизвестный параметр: $1" >&2; usage >&2; exit 2 ;;
	esac
done
[[ $# -eq 1 ]] || { usage >&2; exit 2; }
[[ "$1" =~ ^[a-z0-9-]+$ ]] || { echo "Недопустимое имя контейнера: $1" >&2; exit 2; }
for k in "${KEEP[@]}"; do
	[[ "$k" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Недопустимое имя в --keep: $k" >&2; exit 2; }
done

HOST="${AGENT_SSH_HOST:-dev-workplaces-via-services}"
# Имя контейнера: номер N -> dev-agent<N> (универсальные контейнеры с 21.11.2026), полное имя dev-agent… — как есть,
# прежний суффикс по харнесу (cursor1) -> dev-agent-cursor1. AGENT_CONTAINER_PREFIX, если задан, просто приписывается.
agent_container() {
	if [[ -n "${AGENT_CONTAINER_PREFIX:-}" ]]; then printf '%s%s' "$AGENT_CONTAINER_PREFIX" "$1"
	elif [[ "$1" == dev-agent* ]]; then printf '%s' "$1"
	elif [[ "$1" =~ ^[0-9]+$ ]]; then printf 'dev-agent%s' "$1"
	else printf 'dev-agent-%s' "$1"; fi
}
CONTAINER=$(agent_container "$1")
EXEC_USER="${AGENT_EXEC_USER:-dev}"

# Скрипт в контейнере получает параметры через окружение; аргументы проверены выше.
REMOTE=$(cat <<'EOS'
set -uo pipefail
cd "$HOME/work" 2>/dev/null || { echo "нет ~/work"; exit 0; }
today=$(date +%Y%m%d)
locks="${AGENT_LOCKS:-/var/lib/agent-locks}"
busy_ws=$(python3 - "$locks" "$HOME/tasks" <<'PY'
import json, os, sys
busy = ("working", "question", "review")
out = set()
locks, tasks = sys.argv[1], sys.argv[2]
for d, pick in ((locks, None), (tasks, "agent-status.json")):
    if not os.path.isdir(d):
        continue
    for n in os.listdir(d):
        p = os.path.join(d, n, pick) if pick else os.path.join(d, n)
        if not p.endswith(".json") or not os.path.isfile(p):
            continue
        try:
            j = json.load(open(p, encoding="utf-8"))
        except Exception:
            continue
        if j.get("state") in busy:
            for k in ("workspace", "base_workspace", "worktree"):
                v = j.get(k)
                if v:
                    out.add(os.path.realpath(v))
            if pick:
                out.add("task:" + n)
print("\n".join(sorted(out)))
PY
)
echo "du до: $(du -sh "$HOME/work" | cut -f1)"
fetched=" "
cwds=$(for p in /proc/[0-9]*; do readlink "$p/cwd" 2>/dev/null; done | sort -u)
for d in */; do
	d=${d%/}; full=$(realpath "$d")
	[ -d "$d/.git" ] && continue   # клон (базовый) — не трогаем никогда
	reason=""
	case " ${KEEP_LIST:-} " in *" $d "*) reason="--keep" ;; esac
	# Остаток харнеса DSH: после worktree remove он дописывает .dsh/feature-state/*.json,
	# и каталог появляется снова. Удаляем, только если кроме этих файлов там ничего нет.
	leftover=0
	if [ -z "$reason" ] && [ ! -e "$d/.git" ] && [ -d "$d/.dsh/feature-state" ] \
		&& [ -z "$(find "$d" -mindepth 1 ! -type d ! -path "$d/.dsh/feature-state/*.json" -print -quit)" ]; then
		leftover=1
	fi
	[ -z "$reason" ] && [ "$leftover" = 0 ] && [ ! -f "$d/.git" ] && reason="не git worktree (вручную)"
	[ -z "$reason" ] && printf '%s\n' "$busy_ws" | grep -qxF "$full" && reason="активная задача agent-state"
	[ -z "$reason" ] && printf '%s\n' "$busy_ws" | grep -qxF "task:$d" && reason="активная задача agent-state"
	[ -z "$reason" ] && printf '%s\n' "$cwds" | grep -q "^$full\(/\|$\)" && reason="работает процесс"
	# Дерево подготовлено под задачу, которую ещё не запустили: agent-status.json нет, а worktree создан
	# меньше суток назад. Его ветка часто уже запушена (спецификация) и выглядит «влитой» (22.11.2026, #156:
	# план чуть не удалил свежее дерево payment-status-155 соседнего архитектора).
	if [ -z "$reason" ] && [ -f "$d/.git" ] && [ ! -f "$HOME/tasks/$d/agent-status.json" ] \
		&& [ -n "$(find "$d/.git" -maxdepth 0 -mmin -1440 -print 2>/dev/null)" ]; then
		reason="подготовлено меньше суток назад, задача не запускалась (agent-status.json нет)"
	fi
	if [ -z "$reason" ] && [ "$leftover" = 1 ]; then
		size=$(du -sh "$d" | cut -f1)
		if [ "${APPLY:-0}" != 1 ]; then echo "УДАЛИТЬ  $d ($size) — остаток харнеса (.dsh/feature-state)"
		else rm -rf -- "$full" && echo "УДАЛЕНО  $d ($size) — остаток харнеса"; fi
		continue
	fi
	if [ -z "$reason" ]; then
		repo=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
		main=${repo%/.git}
		[ -d "$main/.git" ] || reason="не найден основной клон worktree"
	fi
	if [ -z "$reason" ]; then
		case "$fetched" in *" $main "*) ;; *) git -C "$main" fetch -q origin 2>/dev/null; fetched="$fetched$main " ;; esac
		head=$(git -C "$d" rev-parse HEAD 2>/dev/null)
		if ! git -C "$d" merge-base --is-ancestor "$head" origin/main 2>/dev/null \
			&& [ -z "$(git -C "$d" branch -r --contains "$head" 2>/dev/null)" ]; then
			reason="коммиты не влиты и не запушены"
		fi
	fi
	size=$(du -sh "$d" | cut -f1)
	if [ -n "$reason" ]; then echo "ПРОПУСК  $d ($size): $reason"; continue; fi
	dirty=$(git -C "$d" status --porcelain 2>/dev/null | head -1)
	if [ "${APPLY:-0}" != 1 ]; then
		echo "УДАЛИТЬ  $d ($size)${dirty:+ — незакоммиченное сохранится патчем}"; continue
	fi
	if [ -n "$dirty" ]; then
		mkdir -p "$HOME/tasks/$d"
		patch="$HOME/tasks/$d/leftover-uncommitted-$today.patch"
		# Локальные файлы окружения (копии из основного клона, с ключами) в патч не попадают.
		{ git -C "$d" diff HEAD; git -C "$d" ls-files --others --exclude-standard -z -- . \
			':(exclude).dev.env' ':(exclude).dsh/agent.env' ':(exclude).mcp.json' \
			':(exclude)AGENTS.local.md' ':(exclude)*.env' \
			| xargs -0 -r -I{} git -C "$d" diff --no-index /dev/null {}; } > "$patch" 2>/dev/null
		echo "ПАТЧ     $patch ($(du -h "$patch" | cut -f1))"
	fi
	if git -C "$main" worktree remove --force "$full" 2>/dev/null; then echo "УДАЛЕНО  $d ($size)"; git -C "$main" worktree prune
	else echo "ОШИБКА   $d: git worktree remove не прошёл, каталог оставлен"; fi
done
echo "du после: $(du -sh "$HOME/work" | cut -f1)"
EOS
)

ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" \
	docker exec -u "$EXEC_USER" -e APPLY="$APPLY" -e KEEP_LIST="${KEEP[*]:-}" \
	-i "$CONTAINER" bash -s <<<"$REMOTE" || { echo "ssh/docker exec не прошёл" >&2; exit 1; }
