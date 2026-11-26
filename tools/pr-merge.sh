#!/usr/bin/env bash
# Слияние PR задачи архитектором (docs/headless-agent.md, «Общий стенд и версии»): с проверкой
# слота слияния, способа слияния и, в проекте с зеркалом хранилища, каталогов зеркала.
#
# Использование: tools/pr-merge.sh <номер PR> [--admin] [--dry-run] [--method squash|merge|rebase]
#                                  [--ignore-slot "причина"]
#
# Настройки проекта в .dev.env (в рабочем дереве без него — .dev.env основной копии):
#   MIRROR_SRC_PATHS  каталоги зеркала через запятую (например src/cfe/Расширение1Коммерция);
#                     пусто — проекта без зеркала;
#   PR_MERGE_METHOD   способ слияния: squash (по умолчанию) | merge | rebase. Проект, которому
#                     нужна история коммитов задачи в основной ветке, ставит merge.
#
# Проверки перед слиянием:
#   1. PR открыт и указывает в основную ветку origin;
#   2. слот слияния (tools/task-board.sh version list): занят другой задачей, а PR меняет значимые
#      файлы (tools/merge-slot.sh) → отказ. PR держателя слота и PR только с документацией проходят;
#      --ignore-slot "причина" — слить вопреки, причина печатается и должна попасть в отчёт;
#   3. MIRROR_SRC_PATHS задан → git diff origin/<основная>...<голова PR> -- <каталоги> пуст
#      (иначе src уйдёт в основную ветку мимо зеркала, и devbox остановит зеркало: foreign_change),
#      и способ слияния — только squash (merge-коммит с коммитами агента по src тоже останавливает зеркало).
# Код возврата: 0 — слито (или --dry-run прошёл); 1 — проверка не прошла; 2 — ошибка запуска.
set -uo pipefail

PR=""; ADMIN=(); DRY=0; METHOD=""; IGNORE_SLOT=""
usage_line='Использование: tools/pr-merge.sh <номер PR> [--admin] [--dry-run] [--method squash|merge|rebase] [--ignore-slot "причина"]'
while (($#)); do
	case "$1" in
		--admin) ADMIN=(--admin); shift ;;
		--dry-run) DRY=1; shift ;;
		--method) METHOD="${2:-}"; shift 2 || { echo "$usage_line" >&2; exit 2; } ;;
		--ignore-slot) IGNORE_SLOT="${2:-}"; shift 2 || { echo "$usage_line" >&2; exit 2; }
			[[ -n "$IGNORE_SLOT" ]] || { echo "--ignore-slot требует причину" >&2; exit 2; } ;;
		-h|--help) sed -n '2,23p' "$0"; exit 0 ;;
		*) [[ -z "$PR" && "$1" =~ ^[0-9]+$ ]] || { echo "$usage_line" >&2; exit 2; }; PR="$1"; shift ;;
	esac
done
[[ -n "$PR" ]] || { echo "Нужен номер PR" >&2; exit 2; }
command -v gh >/dev/null || { echo "Нужен gh" >&2; exit 2; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Не git-репозиторий" >&2; exit 2; }
cd "$ROOT" || exit 2

# .dev.env вне git: в рабочем дереве задачи его обычно нет — тогда берётся файл основной копии
# (там же, где доска задач), иначе настройки проекта (способ слияния, зеркало) молча терялись бы.
DEV_ENV=".dev.env"
if [[ ! -f "$DEV_ENV" ]]; then
	common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
	[[ -n "$common" && -f "$(dirname "$common")/.dev.env" ]] && DEV_ENV="$(dirname "$common")/.dev.env"
fi
dev_env_value() {
	[[ -f "$DEV_ENV" ]] || return 0
	sed -n "s/^$1=//p" "$DEV_ENV" | tail -n1 | tr -d '\r' | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

read -r STATE BASE HEAD_SHA HEAD_REF < <(gh pr view "$PR" --json state,baseRefName,headRefOid,headRefName \
	--jq '[.state,.baseRefName,.headRefOid,.headRefName]|@tsv') || { echo "PR #$PR не найден" >&2; exit 2; }
[[ "$STATE" == OPEN ]] || { echo "PR #$PR не открыт ($STATE)" >&2; exit 1; }
DEFAULT="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
[[ "$BASE" == "$DEFAULT" ]] || echo "Внимание: PR #$PR указывает в $BASE, основная ветка — $DEFAULT" >&2

git fetch -q origin "$BASE" "+refs/pull/$PR/head:refs/remotes/origin/pr/$PR" || { echo "git fetch не прошёл" >&2; exit 2; }

# Слот слияния: пока его держит другая задача, значимые изменения в основную ветку не идут.
SLOT_JSON="$(bash tools/task-board.sh version list --json 2>/dev/null || true)"
SLOT_ISSUE="$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1] or "{}").get("issue",""))' "$SLOT_JSON" 2>/dev/null || true)"
if [[ -n "$SLOT_ISSUE" ]]; then
	SLOT_VERSION="$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1]).get("version",""))' "$SLOT_JSON")"
	SLOT_BRANCH="$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1]).get("branch",""))' "$SLOT_JSON")"
	body_file="$(mktemp)"; trap 'rm -f "$body_file"' EXIT
	gh pr view "$PR" --json title,body --jq '.title + "\n" + .body' >"$body_file" 2>/dev/null || true
	if [[ -n "$SLOT_BRANCH" && "$HEAD_REF" == "$SLOT_BRANCH" ]] || bash tools/merge-slot.sh owns "$SLOT_ISSUE" "$HEAD_REF" "$body_file"; then
		echo "Слот слияния держит #$SLOT_ISSUE ($SLOT_VERSION) — это PR держателя"
	else
		significant="$(git -c core.quotePath=false diff --name-only "origin/$BASE...origin/pr/$PR" | bash tools/merge-slot.sh significant)"
		if [[ -z "$significant" ]]; then
			echo "Слот слияния держит #$SLOT_ISSUE ($SLOT_VERSION), PR #$PR меняет только нейтральные пути — слот не мешает"
		elif [[ -n "$IGNORE_SLOT" ]]; then
			echo "ВНИМАНИЕ: слот слияния держит #$SLOT_ISSUE ($SLOT_VERSION); слияние вопреки слоту: $IGNORE_SLOT" >&2
		else
			echo "Отказ: слот слияния держит #$SLOT_ISSUE ($SLOT_VERSION). PR #$PR меняет значимые файлы:" >&2
			sed 's/^/  /' <<<"$significant" | head -n 20 >&2
			echo "Дождитесь тега $SLOT_VERSION (tools/task-board.sh version list) или договоритесь с архитектором #$SLOT_ISSUE." >&2
			exit 1
		fi
	fi
else
	echo "Слот слияния свободен"
fi

MIRROR="${MIRROR_SRC_PATHS:-$(dev_env_value MIRROR_SRC_PATHS)}"
[[ -n "$METHOD" ]] || METHOD="${PR_MERGE_METHOD:-$(dev_env_value PR_MERGE_METHOD)}"
[[ -n "$METHOD" ]] || METHOD=squash
case "$METHOD" in squash|merge|rebase) ;; *) echo "Способ слияния: squash | merge | rebase (получено «$METHOD»)" >&2; exit 2 ;; esac
if [[ -n "${MIRROR// /}" && "$METHOD" != squash ]]; then
	echo "Отказ: в проекте с зеркалом хранилища (MIRROR_SRC_PATHS) PR сливается только squash, задано «$METHOD»" >&2
	exit 1
fi
if [[ -n "${MIRROR// /}" ]]; then
	IFS=',' read -r -a paths <<<"$MIRROR"
	diff_files="$(git -c core.quotePath=false diff --name-only "origin/$BASE...origin/pr/$PR" -- "${paths[@]}")"
	if [[ -n "$diff_files" ]]; then
		echo "Отказ: PR #$PR меняет каталоги зеркала мимо зеркала ($MIRROR):" >&2
		sed 's/^/  /' <<<"$diff_files" >&2
		echo "Дождитесь, пока зеркало принесёт версию хранилища в $BASE, влейте origin/$BASE в $HEAD_REF и повторите." >&2
		exit 1
	fi
	echo "Каталоги зеркала: разницы с origin/$BASE нет"
fi

if ((DRY)); then
	echo "--dry-run: PR #$PR ($HEAD_REF @ ${HEAD_SHA:0:9}) можно сливать ($METHOD)"
	exit 0
fi
gh pr merge "$PR" "--$METHOD" --match-head-commit "$HEAD_SHA" "${ADMIN[@]}" || exit 1
for i in 1 2 3; do
	st="$(gh pr view "$PR" --json state --jq .state 2>/dev/null || true)"
	[[ "$st" == MERGED ]] && { echo "PR #$PR слит ($METHOD)"; exit 0; }
	sleep 5
done
echo "gh pr merge вернул успех, но PR #$PR не в состоянии MERGED — проверьте вручную (GitHub мог ответить 500)" >&2
exit 1
