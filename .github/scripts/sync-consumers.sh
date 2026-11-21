#!/usr/bin/env bash
# Автосинхронизация правил в проектах-подписчиках (consumers.json) после слияния в шаблон.
# Для каждого подписчика: клон его ветки, tools/update-from-template.sh из этого шаблона,
# PR «/updaterules» из ветки template-sync/<ветка> (одна на подписчика, перезаписывается),
# автослияние — только если подписчик разрешил, изменены лишь файлы шаблона и нет пропусков
# из-за местных правок. Без секрета TEMPLATE_SYNC_TOKEN — предупреждение и выход 0.
#
# Окружение: TEMPLATE_SYNC_TOKEN (токен с правами contents и pull requests у подписчиков),
# TEMPLATE_URL, TEMPLATE_REF (по умолчанию master), CONSUMERS (по умолчанию consumers.json),
# DRY_RUN=1 — без push, PR и слияния (локальная проверка; клон по TEMPLATE_SYNC_TOKEN или gh).
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC="$TEMPLATE_DIR/tools/update-from-template.sh"
CONSUMERS="${CONSUMERS:-$TEMPLATE_DIR/consumers.json}"
TEMPLATE_URL="${TEMPLATE_URL:-https://github.com/mikhailchuklay/1c-project-template.git}"
TEMPLATE_REF="${TEMPLATE_REF:-master}"
DRY_RUN="${DRY_RUN:-0}"
BOT_NAME="${BOT_NAME:-template-sync[bot]}"
BOT_EMAIL="${BOT_EMAIL:-41898283+github-actions[bot]@users.noreply.github.com}"

warn() { echo "::warning::$*"; }

if [[ -z "${TEMPLATE_SYNC_TOKEN:-}" ]]; then
	warn "TEMPLATE_SYNC_TOKEN is not set - subscribed projects were not synced. The owner adds the secret in the template repository: Settings - Secrets and variables - Actions."
	exit 0
fi
export GH_TOKEN="$TEMPLATE_SYNC_TOKEN"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

# Синхронизация одного подписчика. Возврат 0 — готово (в т. ч. «уже актуально»), иначе — сбой.
sync_one() {
	local repo="$1" branch="$2" auto="$3" ref="$4"
	local work; work="$(mktemp -d)"
	local proj="$work/project" report="$work/report.txt" log="$work/sync.log" body="$work/body.md"
	local sync_branch="template-sync/$branch"

	git clone -q --depth 1 --branch "$branch" \
		"https://x-access-token:${TEMPLATE_SYNC_TOKEN}@github.com/${repo}.git" "$proj" || return 1

	local check_out rc=0
	check_out="$(TMPDIR="$work" bash "$SYNC" --check --project-root "$proj" \
		--template-url "$TEMPLATE_URL" --ref "$ref" 2>&1)" || rc=$?
	echo "$check_out"
	case "$rc" in
		0) echo "$repo: up to date"; rm -rf "$work"; return 0 ;;
		1) ;;
		*) echo "$repo: --check failed ($rc), syncing anyway" ;;
	esac

	git -C "$proj" checkout -q -B "$sync_branch" || return 1
	TMPDIR="$work" bash "$SYNC" --project-root "$proj" --template-url "$TEMPLATE_URL" \
		--ref "$ref" --report "$report" >"$log" 2>&1 || { cat "$log"; return 1; }
	git -C "$proj" add -A || return 1
	if git -C "$proj" diff --cached --quiet; then
		echo "$repo: nothing to commit"; rm -rf "$work"; return 0
	fi

	[[ -f "$report" ]] || { echo "no sync report"; return 1; }
	local commit changed not_owned skips
	commit="$(sed -n -E 's/^[[:space:]]*"commit"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$proj/.rules-template-sync.json")"
	changed="$(git -C "$proj" diff --cached --name-only | sort -u)"
	not_owned="$(comm -23 <(printf '%s\n' "$changed") <(sed -n 's/^owned //p' "$report" | sort -u) || true)"
	skips="$(sed -n 's/^skip //p' "$report")"

	local merge_ok=1 reason=""
	if [[ "$auto" != "true" ]]; then merge_ok=0; reason="подписчик не разрешил автослияние (autoMerge=false)"
	elif [[ -n "$not_owned" ]]; then merge_ok=0; reason="изменены файлы вне зоны шаблона: $(paste -sd, <<<"$not_owned")"
	elif [[ -n "$skips" ]]; then merge_ok=0; reason="пропуски из-за местных правок: $(paste -sd, <<<"$skips")"
	fi

	{
		echo "Автосинхронизация правил из шаблона [1c-project-template](${TEMPLATE_URL%.git}) @\`$commit\` (ветка \`$ref\`), \`tools/update-from-template.sh\`."
		echo
		echo '```text'
		echo "$check_out"
		echo '```'
		echo
		echo "Изменено файлов: $(grep -c . <<<"$changed")."
		if ((merge_ok)); then echo "Автослияние: да — изменены только файлы шаблона, пропусков нет."
		else echo "Автослияние: нет — $reason. Нужен просмотр и слияние архитектором проекта."; fi
		local warnings; warnings="$(grep '^WARNING:' "$log" || true)"
		if [[ -n "$warnings" ]]; then echo; echo "Предупреждения синхронизации:"; echo '```text'; echo "$warnings"; echo '```'; fi
		echo
		echo "Журнал изменений: \`CHANGELOG-TEMPLATE.md\` шаблона. Регламент: \`docs/headless-agent.md\`, раздел «Обновление правил из шаблона»."
	} >"$body"

	git -C "$proj" -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" \
		commit -q -m "/updaterules: правила из шаблона @$commit" || return 1
	if [[ "$DRY_RUN" == "1" ]]; then
		echo "[dry-run] $repo: would push $sync_branch, PR to $branch, merge=$merge_ok"
		cat "$body"; rm -rf "$work"; return 0
	fi
	git -C "$proj" push -q -f origin "$sync_branch" || return 1

	local title="/updaterules: правила из шаблона @$commit" num
	num="$(gh pr list -R "$repo" --head "$sync_branch" --state open --json number -q '.[0].number')"
	if [[ -z "$num" ]]; then
		gh pr create -R "$repo" --base "$branch" --head "$sync_branch" --title "$title" --body-file "$body" >/dev/null || return 1
		num="$(gh pr list -R "$repo" --head "$sync_branch" --state open --json number -q '.[0].number')"
	else
		gh pr edit "$num" -R "$repo" --title "$title" --body-file "$body" >/dev/null || return 1
	fi
	echo "$repo: PR #$num"

	if ((merge_ok)); then
		if gh pr merge "$num" -R "$repo" --squash --delete-branch; then
			echo "$repo: PR #$num merged"
		elif gh pr merge "$num" -R "$repo" --squash --delete-branch --auto; then
			echo "$repo: PR #$num will merge when required checks pass"
		else
			warn "$repo: PR #$num was not merged automatically (branch protection or conflict) - merge it by hand"
		fi
	else
		echo "$repo: PR #$num left for review: $reason"
	fi
	rm -rf "$work"
}

failed=0
count="$(jq '.consumers | length' "$CONSUMERS")"
for ((i = 0; i < count; i++)); do
	repo="$(jq -r ".consumers[$i].repository" "$CONSUMERS")"
	branch="$(jq -r ".consumers[$i].branch // \"main\"" "$CONSUMERS")"
	auto="$(jq -r ".consumers[$i].autoMerge // false" "$CONSUMERS")"
	ref="$(jq -r ".consumers[$i].templateRef // empty" "$CONSUMERS")"
	ref="${ref:-$TEMPLATE_REF}"
	echo "::group::$repo ($branch, autoMerge=$auto, template ref $ref)"
	# set -e не действует внутри условия: сбои шагов sync_one возвращает явно (|| return 1).
	if ! (sync_one "$repo" "$branch" "$auto" "$ref"); then
		echo "::error::$repo: sync failed"
		failed=$((failed + 1))
	fi
	echo "::endgroup::"
done
((failed == 0)) || { echo "$failed subscriber(s) failed"; exit 1; }
