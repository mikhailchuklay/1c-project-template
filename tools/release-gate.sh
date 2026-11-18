#!/usr/bin/env bash
# Гейт релиза: агент-разработчик запускает его перед сдачей в review (headless-agent.mdc п. 5).
#
# Командные строки проверок зафиксированы здесь — агент их не собирает и не пересказывает.
# Шаги (по порядку):
#   clean-tree        в каталоге расширения нет незакоммиченных правок (отчёт привязан к SHA HEAD);
#   contains-main     ветка содержит origin/<основная> (как tools/stand-load-guard.sh);
#   version           <Version> в Configuration.xml выше последнего релиза, тега с этим номером нет;
#   check-bsl-calls   tools/check-bsl-calls.py по каталогу расширения;
#   load              (только с --load) двухшаговая загрузка исходников HEAD в базу из .dev.env;
#   check-modules     /CheckModules … -Extension <имя> через tools/designer-batch.sh;
#   check-can-apply   /CheckCanApplyConfigurationExtensions -Extension <имя> через designer-batch.sh;
#   build-cfe         /DumpCfg <файл> -Extension <имя> через designer-batch.sh (или --cfe готовый файл);
#   sha256            контрольная сумма собранного .cfe;
#   demo:<база>       (только с --demo-bases) проверка на демо-базах актуальных версий БП.
#
# Отчёт: out/release-gate.json (машиночитаемый) и out/release-gate.txt; логи шагов — out/release-gate/.
# В отчёте: SHA HEAD, sha256 сборки, по каждому шагу команда, код возврата, хвост лога, итог PASS/FAIL.
# Код возврата: 0 — PASS; 1 — FAIL; 2 — ошибка запуска.
#
# Архитектор шаги не перезапускает, а сверяет отчёт (docs/headless-agent.md, «Приёмка по существу»).
set -uo pipefail

GATE_VERSION=1

usage() {
	cat <<'EOF'
Использование: tools/release-gate.sh [параметры]

  --load               сначала загрузить исходники HEAD в тестовую базу из .dev.env
                       (vrunner cfe load --no-update-db, затем infobase update --target);
                       без него проверяется то, что уже загружено в базу, и отчёт это отмечает
  --cfe PATH           не собирать .cfe, а взять готовый файл (sha256 считается по нему)
  --demo-bases LIST    через запятую: демо-базы актуальных версий БП для шага demo:<база>;
                       команда шага — RELEASE_GATE_DEMO_CMD (см. ниже)
  --timeout SEC        тайм-аут каждого запуска Конфигуратора (по умолчанию 1800)
  --keep-going         выполнять тяжёлые шаги, даже если упали быстрые
  -h, --help           эта справка

Переменные (.dev.env или окружение):
  EXTENSION_NAME, EXTENSIONS_PATH   расширение и каталог исходников (src/cfe по умолчанию)
  RELEASE_GATE_DEMO_CMD             шаблон команды проверки на демо-базе; подстановки
                                    {base} и {cfe}; задаёт проект, а не агент. Пока в Devbox
                                    нет инструментов обновления демо-баз, шаг выключен.

Шаги и их командные строки фиксированы; другой набор проверок — правка этого скрипта PR'ом.
EOF
}

LOAD=0
CFE_GIVEN=""
DEMO_BASES=""
TIMEOUT=1800
KEEP_GOING=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--load) LOAD=1; shift ;;
		--cfe) CFE_GIVEN="${2:-}"; shift 2 ;;
		--demo-bases) DEMO_BASES="${2:-}"; shift 2 ;;
		--timeout) TIMEOUT="${2:-}"; shift 2 ;;
		--keep-going) KEEP_GOING=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 2 ;;
	esac
done
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "--timeout: нужно положительное число секунд" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "Нужен python3 (отчёт и check-bsl-calls)" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Не git-репозиторий" >&2; exit 2; }
cd "$ROOT" || exit 2
TOOLS="$ROOT/tools"

dev_env_value() {
	[[ -f .dev.env ]] || return 0
	sed -n "s/^$1=//p" .dev.env | tail -n1 | tr -d '\r' | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

EXT="${EXTENSION_NAME:-$(dev_env_value EXTENSION_NAME)}"
[[ -n "$EXT" ]] || { echo "EXTENSION_NAME не задан (окружение или .dev.env)" >&2; exit 2; }
EXT_ROOT="${EXTENSIONS_PATH:-$(dev_env_value EXTENSIONS_PATH)}"
EXT_DIR=""
for dir in "$EXT_ROOT" src/cfe cfe; do
	[[ -n "$dir" && -f "$dir/$EXT/Configuration.xml" ]] && { EXT_DIR="$(realpath --relative-to="$ROOT" "$dir/$EXT")"; break; }
done
[[ -n "$EXT_DIR" ]] || { echo "Не найден Configuration.xml расширения $EXT" >&2; exit 2; }
CONFIG="$EXT_DIR/Configuration.xml"
DEMO_CMD="${RELEASE_GATE_DEMO_CMD:-$(dev_env_value RELEASE_GATE_DEMO_CMD)}"

OUT="$ROOT/out"
LOGS="$OUT/release-gate"
mkdir -p "$LOGS" || exit 2
rm -f "$LOGS"/*.log "$LOGS"/*.result "$LOGS/steps.jsonl" "$OUT/release-gate.json" "$OUT/release-gate.txt"
STEPS="$LOGS/steps.jsonl"
: >"$STEPS"
STARTED="$(date -Is)"

xml_version() { { grep -m1 -o '<Version>[^<]*' || true; } | sed 's/<Version>//'; }

HEAD_SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
VERSION="$(xml_version <"$CONFIG")"

git fetch -q --tags origin 2>"$LOGS/fetch.log" || true
MAIN_REF="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
if [[ -z "$MAIN_REF" ]]; then
	for b in origin/main origin/master; do
		git rev-parse -q --verify "$b" >/dev/null && { MAIN_REF="$b"; break; }
	done
fi
MAIN_SHA="$( [[ -n "$MAIN_REF" ]] && git rev-parse "$MAIN_REF" || true)"
RELEASE_TAG="$( [[ -n "$MAIN_REF" ]] && git describe --tags --abbrev=0 "$MAIN_REF" 2>/dev/null || true)"
RELEASE_VERSION=""
if [[ -n "$RELEASE_TAG" ]]; then
	RELEASE_VERSION="$(git show "$RELEASE_TAG:$CONFIG" 2>/dev/null | xml_version || true)"
	[[ -n "$RELEASE_VERSION" ]] || RELEASE_VERSION="$(grep -oE '[0-9]+(\.[0-9]+)+$' <<<"$RELEASE_TAG" || true)"
fi

CFE="${CFE_GIVEN:-$OUT/$EXT-$VERSION.cfe}"
CFE_SHA=""
FAILED_FAST=0

# run_step <имя> <тяжёлый 0|1> <команда для отчёта> -- <команда> [аргументы…]
run_step() {
	local name="$1" heavy="$2" shown="$3"; shift 4
	local log="$LOGS/${name//[:\/ ]/_}.log" rc status t0 t1
	if ((heavy && FAILED_FAST && !KEEP_GOING)); then
		echo "пропущен: упал быстрый шаг (--keep-going — выполнить всё равно)" >"$log"
		rc=-1; status=SKIPPED; t0=$(date +%s); t1=$t0
	else
		t0=$(date +%s)
		"$@" >"$log" 2>&1
		rc=$?
		t1=$(date +%s)
		if ((rc == 0)); then status=PASS; else status=FAIL; ((heavy)) || FAILED_FAST=1; fi
	fi
	printf '%-16s %-7s rc=%-3s %ss  %s\n' "$name" "$status" "$rc" "$((t1 - t0))" "$shown"
	python3 -I - "$name" "$shown" "$rc" "$status" "$log" "$((t1 - t0))" >>"$STEPS" <<'PY'
import json, sys
name, cmd, rc, status, log, dur = sys.argv[1:7]
try:
    lines = open(log, encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    lines = []
print(json.dumps({"name": name, "command": cmd, "rc": int(rc), "status": status,
                  "log": log, "duration_s": int(dur), "tail": lines[-30:]}, ensure_ascii=False))
PY
}

step_clean_tree() {
	local dirty
	dirty="$(git status --porcelain -- "$EXT_DIR")"
	if [[ -n "$dirty" ]]; then
		echo "Незакоммиченные правки в $EXT_DIR — отчёт не будет соответствовать SHA $HEAD_SHA:"
		echo "$dirty"
		return 1
	fi
	echo "Каталог $EXT_DIR совпадает с коммитом $HEAD_SHA"
}

step_contains_main() {
	[[ -n "$MAIN_REF" ]] || { echo "Не найдена основная ветка origin"; return 1; }
	if git merge-base --is-ancestor "$MAIN_REF" HEAD; then
		echo "Ветка $BRANCH содержит $MAIN_REF ($MAIN_SHA)"
	else
		echo "Ветка $BRANCH не содержит актуальный $MAIN_REF ($MAIN_SHA): перенесите ветку на него"
		return 1
	fi
}

step_version() {
	local rc=0 lowest tags
	[[ -n "$VERSION" ]] || { echo "В $CONFIG нет <Version>"; return 1; }
	echo "Версия в $CONFIG: $VERSION; последний релиз: ${RELEASE_TAG:-нет} (${RELEASE_VERSION:-—})"
	if [[ -n "$RELEASE_VERSION" ]]; then
		lowest="$(printf '%s\n%s\n' "$VERSION" "$RELEASE_VERSION" | sort -V | head -n1)"
		if [[ "$VERSION" == "$RELEASE_VERSION" || "$lowest" == "$VERSION" ]]; then
			echo "Версия $VERSION не выше последнего релиза $RELEASE_VERSION: номер — следующий от релиза"
			rc=1
		fi
	fi
	tags="$(git tag -l | grep -E "(^|[^0-9.])${VERSION//./\\.}$" || true)"
	if [[ -n "$tags" ]]; then
		echo "Номер $VERSION уже занят тегом: $tags"
		rc=1
	fi
	((rc)) || echo "Номер $VERSION свободен и выше выпущенного"
	return "$rc"
}

step_demo() {
	local base="$1" cmd
	[[ -n "$DEMO_CMD" ]] || { echo "RELEASE_GATE_DEMO_CMD не задан: проверка на демо-базе $base не настроена"; return 1; }
	[[ -f "$CFE" ]] || { echo "Нет сборки $CFE"; return 1; }
	cmd="${DEMO_CMD//\{base\}/$(printf '%q' "$base")}"
	cmd="${cmd//\{cfe\}/$(printf '%q' "$CFE")}"
	echo "+ $cmd"
	bash -c "$cmd"
}

DB=("$TOOLS/designer-batch.sh" --timeout "$TIMEOUT")
q() { printf '%q ' "$@"; }

echo "release-gate: $BRANCH $HEAD_SHA, расширение $EXT $VERSION"
run_step clean-tree 0 "git status --porcelain -- $EXT_DIR" -- step_clean_tree
run_step contains-main 0 "git merge-base --is-ancestor ${MAIN_REF:-origin/main} HEAD" -- step_contains_main
run_step version 0 "<Version> $CONFIG > последний тег ${RELEASE_TAG:-—}; git tag -l '*$VERSION'" -- step_version
run_step check-bsl-calls 0 "python3 -I tools/check-bsl-calls.py $EXT_DIR" -- python3 -I "$TOOLS/check-bsl-calls.py" "$EXT_DIR"

if ((LOAD)); then
	load_cmd() {
		xvfb-run -a vrunner cfe load --no-update-db --extension-name "$EXT" "$EXT_DIR" &&
			xvfb-run -a vrunner infobase update --target "$EXT"
	}
	run_step load 1 "xvfb-run -a vrunner cfe load --no-update-db --extension-name $EXT $EXT_DIR && xvfb-run -a vrunner infobase update --target $EXT" -- load_cmd
fi

CM=(/CheckModules -ThinClient -WebClient -Server -ExternalConnection -ThickClientManagedApplication -Extension "$EXT")
run_step check-modules 1 "tools/designer-batch.sh --timeout $TIMEOUT -- $(q "${CM[@]}")" -- \
	"${DB[@]}" --out "$LOGS/check-modules.1cv8.log" --result "$LOGS/check-modules.result" -- "${CM[@]}"
CA=(/CheckCanApplyConfigurationExtensions -Extension "$EXT")
run_step check-can-apply 1 "tools/designer-batch.sh --timeout $TIMEOUT -- $(q "${CA[@]}")" -- \
	"${DB[@]}" --out "$LOGS/check-can-apply.1cv8.log" --result "$LOGS/check-can-apply.result" -- "${CA[@]}"

if [[ -n "$CFE_GIVEN" ]]; then
	run_step build-cfe 1 "готовый файл --cfe $CFE" -- test -s "$CFE"
else
	rm -f "$CFE"
	DC=(/DumpCfg "$CFE" -Extension "$EXT")
	run_step build-cfe 1 "tools/designer-batch.sh --timeout $TIMEOUT -- $(q "${DC[@]}")" -- \
		"${DB[@]}" --out "$LOGS/build-cfe.1cv8.log" --result "$LOGS/build-cfe.result" -- "${DC[@]}"
fi
run_step sha256 1 "sha256sum $CFE" -- sha256sum "$CFE"
[[ -s "$CFE" ]] && CFE_SHA="$(sha256sum "$CFE" | cut -d' ' -f1)"

if [[ -n "$DEMO_BASES" ]]; then
	IFS=',' read -r -a demo_list <<<"$DEMO_BASES"
	for base in "${demo_list[@]}"; do
		base="${base// /}"
		[[ -n "$base" ]] && run_step "demo:$base" 1 "${DEMO_CMD:-RELEASE_GATE_DEMO_CMD не задан} (base=$base)" -- step_demo "$base"
	done
fi

GATE_VERSION="$GATE_VERSION" HEAD_SHA="$HEAD_SHA" BRANCH="$BRANCH" EXT="$EXT" VERSION="$VERSION" \
MAIN_REF="$MAIN_REF" MAIN_SHA="$MAIN_SHA" RELEASE_TAG="$RELEASE_TAG" RELEASE_VERSION="$RELEASE_VERSION" \
LOAD="$LOAD" CFE="$CFE" CFE_SHA="$CFE_SHA" DEMO_BASES="$DEMO_BASES" STARTED="$STARTED" \
python3 -I - "$STEPS" "$OUT/release-gate.json" "$OUT/release-gate.txt" <<'PY'
import datetime, json, os, sys
e = os.environ
steps = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
result = "PASS" if steps and all(s["status"] == "PASS" for s in steps) else "FAIL"
report = {
    "gate_version": int(e["GATE_VERSION"]),
    "result": result,
    "sha_head": e["HEAD_SHA"],
    "branch": e["BRANCH"],
    "extension": e["EXT"],
    "version": e["VERSION"],
    "main_ref": e["MAIN_REF"],
    "main_sha": e["MAIN_SHA"],
    "last_release_tag": e["RELEASE_TAG"],
    "last_release_version": e["RELEASE_VERSION"],
    "loaded_by_gate": e["LOAD"] == "1",
    "cfe_path": e["CFE"],
    "cfe_sha256": e["CFE_SHA"],
    "demo_bases": [b.strip() for b in e["DEMO_BASES"].split(",") if b.strip()],
    "started_at": e["STARTED"],
    "finished_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "steps": steps,
}
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
with open(sys.argv[3], "w", encoding="utf-8") as f:
    f.write(f"release-gate: {result}\nSHA HEAD: {report['sha_head']} ({report['branch']})\n")
    f.write(f"Расширение: {report['extension']} {report['version']}; последний релиз: {report['last_release_tag'] or '—'}\n")
    f.write(f"Загрузка гейтом: {'да' if report['loaded_by_gate'] else 'нет — проверена уже загруженная база'}\n")
    f.write(f"Сборка: {report['cfe_path']}\nsha256: {report['cfe_sha256'] or '—'}\n\n")
    for s in steps:
        f.write(f"[{s['status']}] {s['name']} rc={s['rc']} {s['duration_s']}s\n  $ {s['command']}\n")
        if s["status"] != "PASS":
            f.write("".join(f"  | {l}\n" for l in s["tail"][-15:]))
PY
echo
cat "$OUT/release-gate.txt"
echo "Отчёт: out/release-gate.json, out/release-gate.txt"
head -n1 "$OUT/release-gate.txt" | grep -q 'PASS$' || exit 1
