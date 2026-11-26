#!/usr/bin/env bash
# Статус «merge-slot» на открытых PR в основную ветку (workflow merge-slot.yml).
#
# Слот слияния публикует tools/task-board.sh в переменную репозитория MERGE_SLOT (JSON:
# issue, version, expires_at, branch). Статус красный, если слот занят другой задачей и PR меняет
# значимые файлы (tools/merge-slot.sh); зелёный — слот свободен, PR принадлежит держателю слота
# или меняет только нейтральные пути (документация, спецификации).
#
# Окружение: GH_TOKEN, GITHUB_REPOSITORY, MERGE_SLOT (может быть пустым), DEFAULT_BRANCH.
set -euo pipefail

repo="$GITHUB_REPOSITORY"
slot="${MERGE_SLOT:-}"
issue="" version="" expires="" branch=""
if [[ -n "$slot" ]] && jq -e 'type=="object" and has("issue")' <<<"$slot" >/dev/null 2>&1; then
	issue="$(jq -r '.issue // ""' <<<"$slot")"
	version="$(jq -r '.version // ""' <<<"$slot")"
	expires="$(jq -r '.expires_at // ""' <<<"$slot")"
	branch="$(jq -r '.branch // ""' <<<"$slot")"
fi

active=0 why="слот слияния свободен"
if [[ -n "$issue" ]]; then
	active=1
	if [[ -n "$expires" ]] && (($(date -d "$expires" +%s 2>/dev/null || echo 0) <= $(date +%s))); then
		active=0 why="слот #$issue истёк"
	fi
	if ((active)) && [[ -n "$version" ]]; then
		# Тег с номером слота выпущен — слот снят (имя тега заканчивается номером версии).
		if gh api "repos/$repo/git/matching-refs/tags/" --paginate --jq '.[].ref' |
			grep -qE "(^|[^0-9.])${version//./\\.}$"; then
			active=0 why="тег $version выпущен"
		fi
	fi
fi
echo "Слот: ${issue:+#$issue $version до $expires}; активен=$active ($why)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh api "repos/$repo/pulls?state=open&base=$DEFAULT_BRANCH&per_page=100" --paginate \
	--jq '.[] | [.number, .head.sha, .head.ref] | @tsv' >"$tmp/prs"

while IFS=$'\t' read -r num sha ref; do
	[[ -n "$num" ]] || continue
	state=success desc="$why"
	if ((active)); then
		gh api "repos/$repo/pulls/$num" --jq '(.title // "") + "\n" + (.body // "")' >"$tmp/body"
		if [[ -n "$branch" && "$ref" == "$branch" ]] || bash tools/merge-slot.sh owns "$issue" "$ref" "$tmp/body"; then
			desc="PR держателя слота #$issue ($version)"
		else
			gh api "repos/$repo/pulls/$num/files?per_page=100" --paginate --jq '.[].filename' >"$tmp/files"
			if bash tools/merge-slot.sh significant <"$tmp/files" >"$tmp/significant"; then
				desc="только документация: слот #$issue не мешает"
			else
				state=failure
				desc="слот держит #$issue ($version) до ${expires:0:16}: слияние после его тега"
			fi
		fi
	fi
	echo "PR #$num ($ref @ ${sha:0:9}): $state — $desc"
	gh api -X POST "repos/$repo/statuses/$sha" -f state="$state" -f context="merge-slot" \
		-f description="${desc:0:140}" >/dev/null
done <"$tmp/prs"
