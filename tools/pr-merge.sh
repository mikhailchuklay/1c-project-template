#!/usr/bin/env bash
# Слияние PR задачи архитектором: только squash и, в проекте с зеркалом хранилища, только
# когда исходники уже пришли в основную ветку через зеркало (docs/headless-agent.md, правило
# «Проект с зеркалом хранилища: PR задачи — только squash-merge»).
#
# Использование: tools/pr-merge.sh <номер PR> [--admin] [--dry-run]
#
# Каталоги зеркала задаёт проект в .dev.env: MIRROR_SRC_PATHS (через запятую, например
# src/cfe/Расширение1Коммерция). Пусто — проект без зеркала: проверяется только способ слияния.
#
# Проверки перед слиянием:
#   1. PR открыт и указывает в основную ветку origin;
#   2. MIRROR_SRC_PATHS задан → git diff origin/<основная>...<голова PR> -- <каталоги> пуст
#      (иначе src уйдёт в основную ветку мимо зеркала, и devbox остановит зеркало: foreign_change);
#   3. слияние — gh pr merge --squash (merge-коммит с коммитами агента по src тоже останавливает зеркало).
# Код возврата: 0 — слито (или --dry-run прошёл); 1 — проверка не прошла; 2 — ошибка запуска.
set -uo pipefail

PR=""; ADMIN=(); DRY=0
while (($#)); do
	case "$1" in
		--admin) ADMIN=(--admin); shift ;;
		--dry-run) DRY=1; shift ;;
		-h|--help) sed -n '2,18p' "$0"; exit 0 ;;
		*) [[ -z "$PR" && "$1" =~ ^[0-9]+$ ]] || { echo "Использование: tools/pr-merge.sh <номер PR> [--admin] [--dry-run]" >&2; exit 2; }; PR="$1"; shift ;;
	esac
done
[[ -n "$PR" ]] || { echo "Нужен номер PR" >&2; exit 2; }
command -v gh >/dev/null || { echo "Нужен gh" >&2; exit 2; }
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Не git-репозиторий" >&2; exit 2; }
cd "$ROOT" || exit 2

dev_env_value() {
	[[ -f .dev.env ]] || return 0
	sed -n "s/^$1=//p" .dev.env | tail -n1 | tr -d '\r' | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

read -r STATE BASE HEAD_SHA HEAD_REF < <(gh pr view "$PR" --json state,baseRefName,headRefOid,headRefName \
	--jq '[.state,.baseRefName,.headRefOid,.headRefName]|@tsv') || { echo "PR #$PR не найден" >&2; exit 2; }
[[ "$STATE" == OPEN ]] || { echo "PR #$PR не открыт ($STATE)" >&2; exit 1; }
DEFAULT="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
[[ "$BASE" == "$DEFAULT" ]] || echo "Внимание: PR #$PR указывает в $BASE, основная ветка — $DEFAULT" >&2

git fetch -q origin "$BASE" "+refs/pull/$PR/head:refs/remotes/origin/pr/$PR" || { echo "git fetch не прошёл" >&2; exit 2; }

MIRROR="${MIRROR_SRC_PATHS:-$(dev_env_value MIRROR_SRC_PATHS)}"
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
	echo "--dry-run: PR #$PR ($HEAD_REF @ ${HEAD_SHA:0:9}) можно сливать squash"
	exit 0
fi
gh pr merge "$PR" --squash --match-head-commit "$HEAD_SHA" "${ADMIN[@]}" || exit 1
for i in 1 2 3; do
	st="$(gh pr view "$PR" --json state --jq .state 2>/dev/null || true)"
	[[ "$st" == MERGED ]] && { echo "PR #$PR слит squash"; exit 0; }
	sleep 5
done
echo "gh pr merge вернул успех, но PR #$PR не в состоянии MERGED — проверьте вручную (GitHub мог ответить 500)" >&2
exit 1
