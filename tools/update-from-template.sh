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
EOF
}

PROJECT_ROOT=""; TEMPLATE_URL=""; REF=""; SKIP_AGENTS=0; SKIP_ENV_EXAMPLE=0; DRY_RUN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--project-root) PROJECT_ROOT="$2"; shift 2 ;;
		--template-url) TEMPLATE_URL="$2"; shift 2 ;;
		--ref) REF="$2"; shift 2 ;;
		--skip-agents-md) SKIP_AGENTS=1; shift ;;
		--skip-dev-env-example) SKIP_ENV_EXAMPLE=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
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

[[ -n "$TEMPLATE_URL" ]] || TEMPLATE_URL="$(dev_env_value RULES_TEMPLATE_URL)"
[[ -n "$TEMPLATE_URL" ]] || TEMPLATE_URL="https://github.com/mikhailchuklay/1c-project-template.git"
[[ -n "$REF" ]] || REF="$(dev_env_value RULES_TEMPLATE_REF)"
[[ -n "$REF" ]] || REF="master"

CACHE="${TMPDIR:-/tmp}/1c-project-template-rules"
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

copy_file() {
	# $1 — путь относительно корня шаблона; $2 — надпись (по умолчанию путь)
	local rel="$1" src="$CACHE/$1" dst="$PROJECT_ROOT/$1"
	if [[ ! -f "$src" ]]; then warn "Skip missing: $rel"; return 1; fi
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
step "Sync tools/deploy-extension.sh, tools/designer-batch.sh and tools/dev-standalone"
copy_file tools/deploy-extension.sh && echo "  OK tools/deploy-extension.sh"
copy_file tools/designer-batch.sh && echo "  OK tools/designer-batch.sh"
sync_tree tools/dev-standalone

# .gitattributes: у проекта могут быть свои правила — только создать, не перезаписывать.
step "Sync .gitattributes (only if missing)"
if [[ ! -e "$PROJECT_ROOT/.gitattributes" ]]; then
	copy_file .gitattributes && echo "  OK .gitattributes"
elif [[ -f "$CACHE/.gitattributes" ]] && ! cmp -s "$CACHE/.gitattributes" "$PROJECT_ROOT/.gitattributes"; then
	warn ".gitattributes differs from the template - merge manually (template: $CACHE/.gitattributes)"
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
		printf '    "protocol": "template-sync/1.0",\n'
		printf '    "templateUrl": %s,\n' "$(json_str "$TEMPLATE_URL")"
		printf '    "ref": %s,\n' "$(json_str "$REF")"
		printf '    "commit": %s,\n' "$(json_str "$COMMIT")"
		printf '    "syncedAt": %s,\n' "$(json_str "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
		printf '    "projectRoot": %s\n' "$(json_str "$PROJECT_ROOT")"
		printf '}\n'
	} >"$PROJECT_ROOT/.rules-template-sync.json"
fi

step "Done (template @$COMMIT)"
cat <<'EOF'

Preserved (not overwritten):
  .dev.env, memory.md, USER-RULES.md, .cursor/mcp.json, src/, build/, openspec/specs, openspec/changes

Next:
  1. Diff AGENTS.md / .dev.env.example / .gitattributes if you had local edits.
  2. Copy the keys listed above as missing from .dev.env.example into .dev.env.
  3. Reload Cursor window if commands/skills list looks stale.
EOF
