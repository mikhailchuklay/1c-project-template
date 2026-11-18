#!/usr/bin/env bash
# Проверка перед загрузкой расширения на общий стенд (не на свою временную копию).
#
# Отказывает, если загрузка откатит стенд для других задач:
#   1. ветка не содержит актуальную основную ветку origin;
#   2. ветка не содержит последний выпущенный релиз (ближайший тег основной ветки);
#   3. версия расширения ниже версии последнего релиза;
#   4. версия совпадает с выпущенной, а код отличается от релиза (номер уже занят).
#
# Код возврата: 0 — можно загружать; 1 — нельзя; 2 — ошибка запуска.
# Исключение: --allow "причина" — загрузка разрешается, причина пишется в stderr
# и должна попасть в протокол задачи и отчёт архитектору.
#
# Пример (docs/headless-agent.md, «Общий стенд и версии»):
#   tools/stand-load-guard.sh && xvfb-run -a vrunner cfe load --no-update-db ...
set -euo pipefail

usage() {
	cat <<EOF
Использование: $0 [--config PATH] [--allow "причина"]

  --config PATH      Configuration.xml расширения (по умолчанию
                     <EXTENSIONS_PATH|src/cfe|cfe>/<EXTENSION_NAME>/Configuration.xml)
  --allow "причина"  загрузить вопреки проверке; причина обязательна

EXTENSION_NAME берётся из окружения или .dev.env.
EOF
}

CONFIG=""
ALLOW=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--config) CONFIG="${2:-}"; shift 2 ;;
		--allow) ALLOW="${2:-}"; shift 2
			[[ -n "$ALLOW" ]] || { echo "--allow требует причину" >&2; exit 2; } ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 2 ;;
	esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Не git-репозиторий" >&2; exit 2; }
cd "$ROOT"

dev_env_value() {
	[[ -f .dev.env ]] || return 0
	sed -n "s/^$1=//p" .dev.env | tail -n1 | tr -d '\r'
}

if [[ -z "$CONFIG" ]]; then
	EXT="${EXTENSION_NAME:-$(dev_env_value EXTENSION_NAME)}"
	[[ -n "$EXT" ]] || { echo "EXTENSION_NAME не задан (окружение или .dev.env); укажите --config" >&2; exit 2; }
	EXT_ROOT="${EXTENSIONS_PATH:-$(dev_env_value EXTENSIONS_PATH)}"
	for dir in "$EXT_ROOT" src/cfe cfe; do
		[[ -n "$dir" && -f "$dir/$EXT/Configuration.xml" ]] && { CONFIG="$dir/$EXT/Configuration.xml"; break; }
	done
	[[ -n "$CONFIG" ]] || { echo "Configuration.xml расширения $EXT не найден; укажите --config" >&2; exit 2; }
fi
[[ -f "$CONFIG" ]] || { echo "Нет файла: $CONFIG" >&2; exit 2; }
CONFIG="$(realpath --relative-to="$ROOT" "$CONFIG")"

xml_version() {
	{ grep -m1 -o '<Version>[^<]*' || true; } | sed 's/<Version>//'
}

git fetch -q --tags origin
MAIN_REF="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
if [[ -z "$MAIN_REF" ]]; then
	for b in origin/main origin/master; do
		git rev-parse -q --verify "$b" >/dev/null && { MAIN_REF="$b"; break; }
	done
fi
[[ -n "$MAIN_REF" ]] || { echo "Не найдена основная ветка origin" >&2; exit 2; }

problems=()

git merge-base --is-ancestor "$MAIN_REF" HEAD ||
	problems+=("ветка не содержит актуальный $MAIN_REF ($(git rev-parse --short "$MAIN_REF")): перенесите ветку на него")

HEAD_VERSION="$(xml_version <"$CONFIG")"
[[ -n "$HEAD_VERSION" ]] || { echo "В $CONFIG нет <Version>" >&2; exit 2; }

RELEASE_TAG="$(git describe --tags --abbrev=0 "$MAIN_REF" 2>/dev/null || true)"
if [[ -n "$RELEASE_TAG" ]]; then
	git merge-base --is-ancestor "$RELEASE_TAG" HEAD ||
		problems+=("ветка не содержит последний релиз $RELEASE_TAG")
	RELEASE_VERSION="$(git show "$RELEASE_TAG:$CONFIG" 2>/dev/null | xml_version || true)"
	if [[ -n "$RELEASE_VERSION" ]]; then
		lowest="$(printf '%s\n%s\n' "$HEAD_VERSION" "$RELEASE_VERSION" | sort -V | head -n1)"
		if [[ "$HEAD_VERSION" != "$RELEASE_VERSION" && "$lowest" == "$HEAD_VERSION" ]]; then
			problems+=("версия $HEAD_VERSION ниже последнего релиза $RELEASE_TAG ($RELEASE_VERSION)")
		elif [[ "$HEAD_VERSION" == "$RELEASE_VERSION" ]] &&
			! git diff --quiet "$RELEASE_TAG" -- "$(dirname "$CONFIG")"; then
			problems+=("версия $HEAD_VERSION уже выпущена в $RELEASE_TAG, а код отличается: поднимите номер от последнего релиза")
		fi
	fi
fi

echo "Ветка: $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD); версия $HEAD_VERSION; основная $MAIN_REF; последний релиз ${RELEASE_TAG:-нет}"

if [[ ${#problems[@]} -eq 0 ]]; then
	echo "OK: загрузка на общий стенд не откатит его"
	exit 0
fi

for p in "${problems[@]}"; do echo "НЕЛЬЗЯ: $p" >&2; done
if [[ -n "$ALLOW" ]]; then
	echo "ИСКЛЮЧЕНИЕ (--allow): $ALLOW — внесите в протокол и отчёт" >&2
	exit 0
fi
echo "Загрузка на общий стенд остановлена. Своя временная копия этой проверки не требует." >&2
exit 1
