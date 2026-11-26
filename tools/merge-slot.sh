#!/usr/bin/env bash
# Слот слияния: какие изменения требуют слота и кому он принадлежит (docs/headless-agent.md,
# «Общий стенд и версии»). Одно определение на гейт, слияние и проверку PR в GitHub.
#
# Слот (tools/task-board.sh version reserve) замораживает основную ветку для изменений, которые
# входят в сборку или меняют инструменты сборки и гейта. Изменения только в «нейтральных» путях
# (документация, спецификации) основную ветку для гейта не сдвигают и слота не ждут.
#
# Использование:
#   tools/merge-slot.sh significant            читает имена файлов из stdin (по одному в строке),
#                                              печатает значимые; код 0 — значимых нет, 1 — есть
#   tools/merge-slot.sh significant-diff A B   то же для файлов, изменённых в A...B (от общего предка до B)
#   tools/merge-slot.sh owns <issue> <ветка> [<файл с текстом PR>]
#                                              код 0 — ветка или текст PR относятся к задаче <issue>
#   tools/merge-slot.sh patterns               нейтральные шаблоны
#
# Нейтральные шаблоны — MERGE_SLOT_NEUTRAL_PATHS (через пробел; шаблоны bash, `*` захватывает и `/`).
# По умолчанию: docs/* openspec/* *.md
set -uo pipefail

NEUTRAL="${MERGE_SLOT_NEUTRAL_PATHS:-docs/* openspec/* *.md}"

is_neutral() {
	local f="$1" p
	for p in $NEUTRAL; do
		# shellcheck disable=SC2254
		case "$f" in $p) return 0 ;; esac
	done
	return 1
}

significant() {
	local f rc=0
	while IFS= read -r f; do
		[[ -n "$f" ]] || continue
		is_neutral "$f" || { printf '%s\n' "$f"; rc=1; }
	done
	return $rc
}

owns() {
	local issue="${1#\#}" branch="$2" body="${3:-}"
	[[ "$issue" =~ ^[0-9]+$ ]] || return 1
	# Ветка задачи: agent/i50-…, i50-…, 50-…, …/issue-50, …/50
	[[ "$branch" =~ (^|/)(i|issue-)?${issue}(-|$) ]] && return 0
	if [[ -n "$body" && -f "$body" ]]; then
		grep -qiE "(fix(es|ed)?|close[sd]?|resolve[sd]?|refs?)[[:space:]]*:?[[:space:]]*#${issue}([^0-9]|$)" "$body" && return 0
	fi
	return 1
}

set -f
case "${1:-}" in
	significant) significant ;;
	significant-diff)
		[[ $# -eq 3 ]] || { echo "significant-diff <A> <B>" >&2; exit 2; }
		files="$(git -c core.quotePath=false diff --name-only "$2...$3")" || exit 2
		significant <<<"$files"
		;;
	owns)
		[[ $# -ge 3 ]] || { echo "owns <issue> <ветка> [<файл с текстом PR>]" >&2; exit 2; }
		owns "$2" "$3" "${4:-}"
		;;
	patterns) printf '%s\n' $NEUTRAL ;;
	*) sed -n '2,19p' "$0"; exit 2 ;;
esac
