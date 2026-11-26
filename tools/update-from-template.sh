#!/usr/bin/env bash
# Синхронизация rules/skills/agents/commands из 1c-project-template в текущий проект.
# POSIX-пара tools/update-from-template.ps1 (/updaterules) — для Linux/macOS, где нет pwsh.
# Набор файлов и правила те же; при изменении одного скрипта меняйте и второй.
set -euo pipefail

usage() {
	cat <<'EOF'
Использование: tools/update-from-template.sh [параметры]

  --project-root DIR        корень проекта (по умолчанию текущий каталог)
  --template-url URL        git-URL шаблона (по умолчанию RULES_TEMPLATE_URL из .dev.env или GitHub)
  --ref REF                 ветка/тег (по умолчанию RULES_TEMPLATE_REF или master)
  --skip-agents-md          не перезаписывать AGENTS.md
  --skip-dev-env-example    не перезаписывать .dev.env.example
  --dry-run                 только показать действия
  --check                   только сравнить commit из .rules-template-sync.json с головой ветки
                            шаблона, ничего не менять. Код: 0 — актуально, 1 — отстаёт, 2 — ошибка
  --report FILE             записать отчёт синхронизации для автоматики: строки
                            «owned <путь>» (файл шаблона) и «skip <путь> <причина>» (пропуск из-за местной правки)

Ветка шаблона: --ref, иначе RULES_TEMPLATE_REF из .dev.env, иначе ref из .rules-template-sync.json
(только для --check), иначе master. Журнал изменений шаблона — CHANGELOG-TEMPLATE.md.
EOF
}

# Версия протокола метаданных синхронизации (.rules-template-sync.json). Мажорная часть меняется
# только при несовместимом изменении формата; при несовпадении мажорной версии скрипт предупреждает.
PROTOCOL="template-sync/1.1"


PROJECT_ROOT=""; TEMPLATE_URL=""; REF=""; SKIP_AGENTS=0; SKIP_ENV_EXAMPLE=0; DRY_RUN=0; CHECK=0; REPORT=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--project-root) PROJECT_ROOT="$2"; shift 2 ;;
		--template-url) TEMPLATE_URL="$2"; shift 2 ;;
		--ref) REF="$2"; shift 2 ;;
		--skip-agents-md) SKIP_AGENTS=1; shift ;;
		--skip-dev-env-example) SKIP_ENV_EXAMPLE=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		--check) CHECK=1; shift ;;
		--report) REPORT="$2"; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 2 ;;
	esac
done

step() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

PROJECT_ROOT="$(cd "${PROJECT_ROOT:-.}" && pwd)"
DEV_ENV="$PROJECT_ROOT/.dev.env"

# Значение ключа из .dev.env без исполнения файла (как Read-DevEnvValue в .ps1).
dev_env_value() {
	[[ -f "$DEV_ENV" ]] || return 0
	sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*)$/\1/p" "$DEV_ENV" | tail -n 1 |
		sed -E "s/[[:space:]]+$//; s/^[\"']//; s/[\"']$//"
}

STAMP="$PROJECT_ROOT/.rules-template-sync.json"

# Строковое поле верхнего уровня из .rules-template-sync.json (без jq).
stamp_value() {
	[[ -f "$STAMP" ]] || return 0
	sed -n -E "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*$/\1/p" "$STAMP" | head -n 1
}

# Предупреждение, если мажорная версия протокола в метаданных проекта не совпадает со скриптом.
check_protocol() {
	local have; have="$(stamp_value protocol)"
	[[ -n "$have" ]] || return 0
	local have_major="${have#template-sync/}" want_major="${PROTOCOL#template-sync/}"
	have_major="${have_major%%.*}"; want_major="${want_major%%.*}"
	if [[ "$have" != template-sync/* || "$have_major" != "$want_major" ]]; then
		warn "protocol mismatch: .rules-template-sync.json has '$have', script speaks '$PROTOCOL' - read CHANGELOG-TEMPLATE.md before syncing"
	fi
}

[[ -n "$TEMPLATE_URL" ]] || TEMPLATE_URL="$(dev_env_value RULES_TEMPLATE_URL)"
[[ -n "$TEMPLATE_URL" ]] || TEMPLATE_URL="$(stamp_value templateUrl)"
[[ -n "$TEMPLATE_URL" ]] || TEMPLATE_URL="https://github.com/mikhailchuklay/1c-project-template.git"
[[ -n "$REF" ]] || REF="$(dev_env_value RULES_TEMPLATE_REF)"
if ((CHECK)); then [[ -n "$REF" ]] || REF="$(stamp_value ref)"; fi
[[ -n "$REF" ]] || REF="master"

CACHE="${TMPDIR:-/tmp}/1c-project-template-rules"

# --check: сравнить commit проекта с головой ветки шаблона. Ничего в проекте не меняет.
# Голова — git ls-remote; история и журнал — неглубокий fetch в отдельный кэш (bare).
run_check() {
	trap 'echo "ERROR: --check failed (line $LINENO)" >&2; exit 2' ERR
	if [[ ! -f "$STAMP" ]]; then
		echo "ERROR: $STAMP not found - project was never synced; run tools/update-from-template.sh" >&2
		exit 2
	fi
	check_protocol
	local have; have="$(stamp_value commit)"
	if [[ -z "$have" ]]; then echo "ERROR: no \"commit\" in $STAMP" >&2; exit 2; fi

	local head
	head="$(git ls-remote "$TEMPLATE_URL" "refs/heads/$REF" "refs/tags/$REF" "refs/tags/$REF^{}" 2>/dev/null |
		awk '{ sha = $1 } $2 ~ /\^\{\}$/ { peeled = $1 } END { print (peeled != "" ? peeled : sha) }')" || true
	if [[ -z "$head" ]]; then
		if [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]]; then
			# Закреплённый commit: ветки нет, сравнивать не с чем, кроме самого закрепления.
			if [[ "$have" == "${REF:0:${#have}}" || "$REF" == "${have:0:${#REF}}" ]]; then
				echo "OK: pinned to commit $REF (RULES_TEMPLATE_REF), project @$have"; exit 0
			fi
			echo "BEHIND: project @$have, pinned RULES_TEMPLATE_REF=$REF - sync to the pinned commit"; exit 1
		fi
		echo "ERROR: ref '$REF' not found at $TEMPLATE_URL (git ls-remote)" >&2
		exit 2
	fi
	if [[ "${head:0:${#have}}" == "$have" ]]; then
		echo "OK: rules are up to date (template $REF @${head:0:7})"
		exit 0
	fi

	local cc="${CACHE}-check"
	if [[ ! -d "$cc/objects" ]]; then rm -rf "$cc"; git init -q --bare "$cc"; fi
	git -C "$cc" fetch -q --depth 200 "$TEMPLATE_URL" "+$head:refs/check/head" 2>/dev/null ||
		git -C "$cc" fetch -q --depth 200 "$TEMPLATE_URL" "+refs/heads/$REF:refs/check/head"
	local base=""
	base="$(git -C "$cc" rev-parse -q --verify "$have^{commit}" 2>/dev/null)" || base=""
	if [[ -z "$base" ]]; then
		git -C "$cc" fetch -q --unshallow "$TEMPLATE_URL" "+refs/check/head:refs/check/head" 2>/dev/null ||
			git -C "$cc" fetch -q --deepen 2000 "$TEMPLATE_URL" "+$head:refs/check/head" 2>/dev/null || true
		base="$(git -C "$cc" rev-parse -q --verify "$have^{commit}" 2>/dev/null)" || base=""
	fi

	local log="CHANGELOG-TEMPLATE.md" entries marked
	if [[ -n "$base" ]]; then
		if git -C "$cc" merge-base --is-ancestor refs/check/head "$base" 2>/dev/null; then
			echo "OK: project @$have is at or ahead of template $REF @${head:0:7}"
			exit 0
		fi
		local n; n="$(git -C "$cc" rev-list --count "$base..refs/check/head")"
		echo "BEHIND: project @$have, template $REF @${head:0:7}: $n commit(s) behind"
		entries="$(git -C "$cc" diff --no-color -U0 "$base" refs/check/head -- "$log" |
			sed -n -E 's/^\+(- .*)$/\1/p')" || entries=""
	else
		echo "BEHIND: project @$have is not in the history of template $REF @${head:0:7} (rewritten or unknown commit)"
		entries="$(git -C "$cc" show "refs/check/head:$log" 2>/dev/null | sed -n -E 's/^(- .*)$/\1/p')" || entries=""
	fi
	marked="$(printf '%s\n' "$entries" | grep -E '\[(несовместимо|безопасность)' || true)"
	if [[ -n "$marked" ]]; then
		echo
		echo "Записи журнала с пометками «несовместимо»/«безопасность» ($log):"
		printf '%s\n' "$marked"
	fi
	local total=0
	[[ -z "$entries" ]] || total="$(printf '%s\n' "$entries" | grep -c . || true)"
	echo
	echo "Новых записей в $log: $total. Синхронизация: tools/update-from-template.sh (одним исполнителем, не из агента задачи)."
	exit 1
}

if ((CHECK)); then run_check; fi

check_protocol
step "Template cache: $CACHE"
step "URL: $TEMPLATE_URL  ref: $REF"
if [[ -d "$CACHE/.git" ]]; then
	git -C "$CACHE" fetch --depth 1 origin "$REF"
	git -C "$CACHE" checkout -q -B sync FETCH_HEAD
else
	rm -rf "$CACHE"
	git clone --depth 1 --branch "$REF" "$TEMPLATE_URL" "$CACHE" ||
		{ git clone --depth 1 "$TEMPLATE_URL" "$CACHE" &&
			git -C "$CACHE" fetch --depth 1 origin "$REF" &&
			git -C "$CACHE" checkout -q -B sync FETCH_HEAD; }
fi

PLATFORM_EXCLUDE=(1c-platform-tools 1c-platform-tools-config 1c-platform-tools-configuration
	1c-platform-tools-dependencies 1c-platform-tools-extensions 1c-platform-tools-external
	1c-platform-tools-infobase 1c-platform-tools-mcp 1c-platform-tools-run 1c-platform-tools-setversion
	1c-platform-tools-support 1c-platform-tools-test)

REPORT_LINES=()
report() { REPORT_LINES+=("$*"); }

copy_file() {
	# $1 — путь относительно корня шаблона; $2 — надпись (по умолчанию путь)
	local rel="$1" src="$CACHE/$1" dst="$PROJECT_ROOT/$1"
	if [[ ! -f "$src" ]]; then warn "Skip missing: $rel"; return 1; fi
	report "owned $rel"
	if ((DRY_RUN)); then
		if [[ -e "$dst" ]]; then echo "  [dry-run] Updated $rel"; else echo "  [dry-run] Added $rel"; fi
		return 0
	fi
	mkdir -p "$(dirname "$dst")"
	cp -f "$src" "$dst"
}

sync_tree() {
	# $1 — каталог относительно корня шаблона; остальные — имена исключаемых каталогов
	local dir="$1"; shift
	local added=0 updated=0 skipped=0 rel ex part skip
	if [[ ! -d "$CACHE/$dir" ]]; then warn "Skip missing source: $dir"; return; fi
	while IFS= read -r -d '' f; do
		rel="${f#"$CACHE/"}"
		skip=0
		IFS='/' read -r -a parts <<<"${rel#"$dir/"}"
		for ex in "$@"; do
			for part in "${parts[@]}"; do [[ "$part" == "$ex" ]] && skip=1; done
		done
		if ((skip)); then skipped=$((skipped + 1)); continue; fi
		if [[ -e "$PROJECT_ROOT/$rel" ]]; then updated=$((updated + 1)); else added=$((added + 1)); fi
		copy_file "$rel" >/dev/null
	done < <(find "$CACHE/$dir" -type f -print0)
	echo "  ${dir}: +${added} ~${updated} skip ${skipped}"
}

step "Sync .cursor/rules";    sync_tree .cursor/rules
step "Sync .cursor/skills (exclude Platform Tools)"; sync_tree .cursor/skills "${PLATFORM_EXCLUDE[@]}"
step "Sync .cursor/agents";   sync_tree .cursor/agents
step "Sync .cursor/commands"; sync_tree .cursor/commands

if ((!SKIP_AGENTS)); then step "Sync AGENTS.md"; copy_file AGENTS.md && echo "  OK AGENTS.md"; fi
if ((!SKIP_ENV_EXAMPLE)); then step "Sync .dev.env.example"; copy_file .dev.env.example && echo "  OK .dev.env.example"; fi

step "Sync docs/headless-agent.md"; copy_file docs/headless-agent.md && echo "  OK docs/headless-agent.md"

step "Sync tools/update-from-template.{ps1,sh}"
copy_file tools/update-from-template.ps1 && echo "  OK tools/update-from-template.ps1"
copy_file tools/update-from-template.sh && echo "  OK tools/update-from-template.sh"

# Скрипты, на которые ссылаются правила (headless-agent, designer-batch-checks), и их помощники.
step "Sync tools/deploy-extension.sh, tools/designer-batch.sh, tools/check-bsl-calls.py and tools/dev-standalone"
copy_file tools/deploy-extension.sh && echo "  OK tools/deploy-extension.sh"
copy_file tools/designer-batch.sh && echo "  OK tools/designer-batch.sh"
copy_file tools/thick-client-check.sh && echo "  OK tools/thick-client-check.sh"
copy_file tools/check-bsl-calls.py && echo "  OK tools/check-bsl-calls.py"
copy_file tools/ordinary-form.py && echo "  OK tools/ordinary-form.py"
copy_file tools/stand-load-guard.sh && echo "  OK tools/stand-load-guard.sh"
copy_file tools/agent-monitor.sh && echo "  OK tools/agent-monitor.sh"
copy_file tools/agent-workspace-cleanup.sh && echo "  OK tools/agent-workspace-cleanup.sh"
copy_file tools/release-gate.sh && echo "  OK tools/release-gate.sh"
copy_file tools/task-board.sh && echo "  OK tools/task-board.sh"
copy_file tools/pr-merge.sh && echo "  OK tools/pr-merge.sh"
copy_file tools/merge-slot.sh && echo "  OK tools/merge-slot.sh"
# Статус «merge-slot» на PR (слот слияния в GitHub): workflow и его скрипт.
copy_file .github/workflows/merge-slot.yml && echo "  OK .github/workflows/merge-slot.yml"
copy_file .github/scripts/merge-slot-status.sh && echo "  OK .github/scripts/merge-slot-status.sh"
copy_file tools/lists/bsl-global-names.txt && echo "  OK tools/lists/bsl-global-names.txt"
sync_tree tools/dev-standalone

# Доска задач (tools/task-board.sh) лежит в основной копии вне git: путь должен быть в .gitignore.
step "Ensure .gitignore ignores .task-board/"
if [[ -f "$PROJECT_ROOT/.gitignore" ]] && grep -qxE '/?\.task-board/?' "$PROJECT_ROOT/.gitignore"; then
	echo "  .gitignore already ignores .task-board/"
elif ((DRY_RUN)); then
	echo "  [dry-run] append .task-board/ to .gitignore"
else
	printf '\n# Доска задач проекта (tools/task-board.sh), общая для рабочих деревьев\n.task-board/\n' >>"$PROJECT_ROOT/.gitignore"
	echo "  OK .gitignore += .task-board/"
fi

# docs/project-patterns.md принадлежит проекту: создать из шаблона, если его нет, и не перезаписывать.
step "Seed docs/project-patterns.md (only if missing)"
if [[ ! -e "$PROJECT_ROOT/docs/project-patterns.md" ]]; then
	copy_file docs/project-patterns.md && echo "  OK docs/project-patterns.md"
else
	echo "  docs/project-patterns.md exists - kept"
fi

# tools/vrunner.init.json — адрес и пользователь конкретной базы: не коммитится (шаблон — .example).
step "Ensure .gitignore ignores tools/vrunner.init.json"
if [[ -f "$PROJECT_ROOT/.gitignore" ]] && grep -qxE '/?tools/vrunner\.init\.json' "$PROJECT_ROOT/.gitignore"; then
	echo "  .gitignore already ignores tools/vrunner.init.json"
elif ((DRY_RUN)); then
	echo "  [dry-run] append tools/vrunner.init.json to .gitignore"
else
	printf '\n# Подключение vrunner к конкретной базе — только локально (шаблон: tools/vrunner.init.json.example)\ntools/vrunner.init.json\n' >>"$PROJECT_ROOT/.gitignore"
	echo "  OK .gitignore += tools/vrunner.init.json"
fi
if git -C "$PROJECT_ROOT" ls-files --error-unmatch tools/vrunner.init.json >/dev/null 2>&1; then
	warn "tools/vrunner.init.json is tracked by git (connection to a specific base): git rm --cached tools/vrunner.init.json"
fi

# .gitattributes: у проекта могут быть свои правила — только создать, не перезаписывать.
step "Sync .gitattributes (only if missing)"
if [[ ! -e "$PROJECT_ROOT/.gitattributes" ]]; then
	copy_file .gitattributes && echo "  OK .gitattributes"
elif [[ -f "$CACHE/.gitattributes" ]] && ! cmp -s "$CACHE/.gitattributes" "$PROJECT_ROOT/.gitattributes"; then
	warn ".gitattributes differs from the template - merge manually (template: $CACHE/.gitattributes)"
	report "skip .gitattributes local-differs"
else
	echo "  .gitattributes up to date"
fi

step "Check .dev.env keys"
if [[ -f "$DEV_ENV" ]]; then
	missing="$(comm -23 <(grep -oE '^[A-Z0-9_]+=' "$CACHE/.dev.env.example" 2>/dev/null | sort -u) \
		<(grep -oE '^[A-Z0-9_]+=' "$DEV_ENV" | sort -u) | tr -d '=' | paste -sd, -)"
	if [[ -n "$missing" ]]; then warn "Keys missing in .dev.env (copy from .dev.env.example): $missing"
	else echo "  .dev.env has every key of .dev.env.example"; fi
	legacy="$(grep -oE '^CONFIG_STORAGE_[A-Z0-9_]*' "$DEV_ENV" | paste -sd, - || true)"
	[[ -z "$legacy" ]] || warn "Legacy keys in .dev.env: $legacy -> REPOSITORY_PATH / REPOSITORY_USER / REPOSITORY_PASSWORD (1c-repository-manage); remove the old keys afterwards"
else
	echo "  .dev.env not found - skipped"
fi

# Бит исполнения: как в шаблоне (100755) — и в файловой системе, и в индексе git проекта.
step "Restore executable bit from template"
fixed=0
in_repo=0
git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_repo=1
while IFS= read -r rel; do
	dst="$PROJECT_ROOT/$rel"
	[[ -f "$dst" ]] || continue
	if ((DRY_RUN)); then [[ -x "$dst" ]] || { echo "  [dry-run] +x $rel"; fixed=$((fixed + 1)); }; continue; fi
	[[ -x "$dst" ]] || { chmod +x "$dst"; fixed=$((fixed + 1)); }
	if ((in_repo)) && [[ -n "$(git -C "$PROJECT_ROOT" ls-files -- "$rel")" ]] &&
		! git -C "$PROJECT_ROOT" ls-files -s -- "$rel" | grep -q '^100755 '; then
		git -C "$PROJECT_ROOT" update-index --chmod=+x -- "$rel"
	fi
done < <(git -C "$CACHE" ls-files -s | awk '$1 == "100755" { sub(/^[^\t]*\t/, ""); print }')
echo "  executable bit set: $fixed"

COMMIT="$(git -C "$CACHE" rev-parse --short HEAD)"
json_str() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }
if ((!DRY_RUN)); then
	{
		printf '{\n'
		printf '    "protocol": %s,\n' "$(json_str "$PROTOCOL")"
		printf '    "templateUrl": %s,\n' "$(json_str "$TEMPLATE_URL")"
		printf '    "ref": %s,\n' "$(json_str "$REF")"
		printf '    "commit": %s,\n' "$(json_str "$COMMIT")"
		printf '    "syncedAt": %s\n' "$(json_str "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
		printf '}\n'
	} >"$STAMP"
fi
report "owned .rules-template-sync.json"
if [[ -n "$REPORT" ]]; then printf '%s\n' "${REPORT_LINES[@]}" >"$REPORT"; fi

step "Done (template @$COMMIT)"
cat <<'EOF'

Preserved (not overwritten):
  .dev.env, memory.md, USER-RULES.md, .cursor/mcp.json, src/, build/, openspec/specs, openspec/changes

Next:
  1. Diff AGENTS.md / .dev.env.example / .gitattributes if you had local edits.
  2. Copy the keys listed above as missing from .dev.env.example into .dev.env.
  3. Reload Cursor window if commands/skills list looks stale.
EOF
