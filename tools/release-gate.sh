#!/usr/bin/env bash
# Гейт релиза: агент-разработчик запускает его перед сдачей в review (headless-agent.mdc п. 5).
#
# Командные строки проверок зафиксированы здесь — агент их не собирает и не пересказывает.
# Два режима (--mode; по умолчанию выбирается по .dev.env):
#
# extension — правка расширения (задан EXTENSION_NAME). Шаги по порядку:
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
# main-config — правка основной конфигурации в проекте «только хранилище 1С» (EXTENSION_NAME пуст,
# REPOSITORY_PATH задан; или явно --mode main-config). Типовая на поддержке несёт сотни своих
# замечаний, поэтому проверки сравниваются с базовой линией, а не с нулём:
#   (--baseline, до правок) check-modules и check-config на базовом состоянии → out/release-gate-baseline/;
#   clean-tree        в рабочем дереве нет незакоммиченных и неотслеживаемых файлов;
#   base              базовый коммит (--base) — предок HEAD и не равен ему;
#   diff-scope        git diff base..HEAD содержит только файлы задачи (--files / --files-from);
#   patch             git apply --check патча на индексе базового коммита, и патч воспроизводит HEAD;
#   check-bsl-calls   tools/check-bsl-calls.py по HEAD и по базе: новых находок нет;
#   load              (только с --load) /LoadConfigFromFiles -listFile <изменённые файлы и их XML>
#                     с параметрами хранилища (designer-batch.sh --repository) + vrunner infobase update;
#   check-modules     /CheckModules <режимы из RELEASE_GATE_CHECK_MODES>: новых ошибок к базовой линии нет;
#   check-config      /CheckConfig … <те же режимы>: новых замечаний к базовой линии нет;
#   build-cf, sha256  (только с --build-cf или --cf, после помещения в хранилище) .cf базы и его sha256.
#
# Отчёт: out/release-gate.json (машиночитаемый) и out/release-gate.txt; логи шагов — out/release-gate/.
# В отчёте: SHA HEAD, sha256 сборки, по каждому шагу команда, код возврата, хвост лога, итог PASS/FAIL.
# Код возврата: 0 — PASS; 1 — FAIL; 2 — ошибка запуска.
#
# Архитектор шаги не перезапускает, а сверяет отчёт (docs/headless-agent.md, «Приёмка по существу»).
set -uo pipefail

GATE_VERSION=2

usage() {
	cat <<'EOF'
Использование: tools/release-gate.sh [параметры]

Общие:
  --mode MODE          extension | main-config; по умолчанию extension при заданном EXTENSION_NAME,
                       main-config при пустом EXTENSION_NAME и заданном REPOSITORY_PATH
  --main-config        то же, что --mode main-config
  --load               сначала загрузить исходники HEAD в тестовую базу из .dev.env
                       (extension: vrunner cfe load + infobase update; main-config: загрузка по списку
                       изменённых файлов base..HEAD с параметрами хранилища + infobase update);
                       без него проверяется то, что уже загружено в базу, и отчёт это отмечает
  --timeout SEC        тайм-аут каждого запуска Конфигуратора
                       (по умолчанию 1800; в main-config — 21600: проверка всей типовой)
  --keep-going         выполнять тяжёлые шаги, даже если упали быстрые
  -h, --help           эта справка

Режим extension:
  --cfe PATH           не собирать .cfe, а взять готовый файл (sha256 считается по нему)
  --demo-bases LIST    через запятую: демо-базы актуальных версий БП для шага demo:<база>;
                       команда шага — RELEASE_GATE_DEMO_CMD (см. ниже)

Режим main-config:
  --base REV           базовый коммит «было» (стартовая выгрузка версии хранилища); обязателен,
                       кроме --baseline (там по умолчанию HEAD)
  --files LIST         через запятую: файлы задачи; шаблоны в стиле bash, «*» захватывает и «/»
                       (например src/cf/Configuration.xml,src/cf/CommonModules/Модуль/*)
  --files-from FILE    то же построчно (пустые строки и «#…» пропускаются)
  --patch FILE         сданный патч (по умолчанию гейт пишет out/change.patch = git diff --binary base HEAD -- <src>)
  --baseline           снять базовую линию: дерево и база — в состоянии --base (до правок);
                       check-modules и check-config пишутся в каталог базовой линии, отчёт —
                       <каталог>/baseline.txt; запускается один раз на задачу до первой загрузки правок
  --import-baseline CM CC
                       принять как базовую линию готовые логи /Out прежних прогонов /CheckModules (CM)
                       и /CheckConfig (CC) на состоянии --base; в отчёте отмечается «импортирована»,
                       командные строки тех прогонов гейт не проверяет
  --baseline-dir DIR   каталог базовой линии (по умолчанию out/release-gate-baseline)
  --build-cf           после помещения в хранилище: /DumpCfg основной конфигурации базы
                       в out/<проект>-<sha>.cf и sha256
  --cf PATH            не собирать .cf, а взять готовый файл (sha256 считается по нему)

Переменные (.dev.env или окружение):
  EXTENSION_NAME, EXTENSIONS_PATH   расширение и каталог исходников (src/cfe по умолчанию)
  REPOSITORY_PATH                   хранилище 1С: при пустом EXTENSION_NAME включает main-config
  EXPORT_PATH                       исходники основной конфигурации (src/cf по умолчанию)
  RELEASE_GATE_CHECK_MODES          main-config: режимы /CheckModules и /CheckConfig, например
                                    «-ThickClientOrdinaryApplication -Server -ExternalConnection»
                                    (обычные формы) или «-ThinClient -Server -ExternalConnection»
  RELEASE_GATE_DEMO_CMD             шаблон команды проверки на демо-базе; подстановки
                                    {base} и {cfe}; задаёт проект, а не агент. Пока в Devbox
                                    нет инструментов обновления демо-баз, шаг выключен.

Шаги и их командные строки фиксированы; другой набор проверок — правка этого скрипта PR'ом.
EOF
}

MODE=""
LOAD=0
CFE_GIVEN=""
DEMO_BASES=""
TIMEOUT=""
KEEP_GOING=0
BASE_REV=""
FILES_ARG=""
FILES_FROM=""
PATCH_GIVEN=""
BASELINE_RUN=0
IMPORT_CM=""
IMPORT_CC=""
BASELINE_DIR_ARG=""
BUILD_CF=0
CF_GIVEN=""
need() { [[ $# -ge 2 && -n "$2" ]] || { echo "$1: нужно значение" >&2; exit 2; }; }
while [[ $# -gt 0 ]]; do
	case "$1" in
		--mode) need "$@"; MODE="$2"; shift 2 ;;
		--main-config) MODE=main-config; shift ;;
		--load) LOAD=1; shift ;;
		--cfe) need "$@"; CFE_GIVEN="$(realpath -m "$2")"; shift 2 ;;
		--demo-bases) need "$@"; DEMO_BASES="$2"; shift 2 ;;
		--timeout) need "$@"; TIMEOUT="$2"; shift 2 ;;
		--keep-going) KEEP_GOING=1; shift ;;
		--base) need "$@"; BASE_REV="$2"; shift 2 ;;
		--files) need "$@"; FILES_ARG="$2"; shift 2 ;;
		--files-from) need "$@"; FILES_FROM="$(realpath -m "$2")"; shift 2 ;;
		--patch) need "$@"; PATCH_GIVEN="$(realpath -m "$2")"; shift 2 ;;
		--baseline) BASELINE_RUN=1; shift ;;
		--import-baseline)
			[[ $# -ge 3 && -n "$2" && -n "$3" ]] || { echo "--import-baseline: нужны два файла (CheckModules, CheckConfig)" >&2; exit 2; }
			IMPORT_CM="$(realpath -m "$2")"; IMPORT_CC="$(realpath -m "$3")"; shift 3 ;;
		--baseline-dir) need "$@"; BASELINE_DIR_ARG="$(realpath -m "$2")"; shift 2 ;;
		--build-cf) BUILD_CF=1; shift ;;
		--cf) need "$@"; CF_GIVEN="$(realpath -m "$2")"; BUILD_CF=1; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 2 ;;
	esac
done
command -v python3 >/dev/null 2>&1 || { echo "Нужен python3 (отчёт и check-bsl-calls)" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Не git-репозиторий" >&2; exit 2; }
cd "$ROOT" || exit 2
TOOLS="$ROOT/tools"
GIT=(git -c core.quotePath=false)

dev_env_value() {
	[[ -f .dev.env ]] || return 0
	sed -n "s/^$1=//p" .dev.env | tail -n1 | tr -d '\r' | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

EXT="${EXTENSION_NAME:-$(dev_env_value EXTENSION_NAME)}"
REPO="${REPOSITORY_PATH:-$(dev_env_value REPOSITORY_PATH)}"
if [[ -z "$MODE" ]]; then
	if [[ -n "${EXT// /}" ]]; then MODE=extension
	elif [[ -n "${REPO// /}" ]]; then MODE=main-config
	else echo "EXTENSION_NAME не задан, REPOSITORY_PATH тоже (окружение или .dev.env): режим гейта не определить, укажите --mode" >&2; exit 2
	fi
fi
case "$MODE" in
	extension|main-config) ;;
	*) echo "--mode: extension или main-config, а не «$MODE»" >&2; exit 2 ;;
esac
if [[ "$MODE" == extension ]]; then
	for opt in "$BASE_REV" "$FILES_ARG" "$FILES_FROM" "$PATCH_GIVEN" "$IMPORT_CM" "$BASELINE_DIR_ARG" "$CF_GIVEN"; do
		[[ -z "$opt" ]] || { echo "--base/--files/--patch/--baseline*/--cf — ключи режима main-config" >&2; exit 2; }
	done
	((BASELINE_RUN == 0 && BUILD_CF == 0)) || { echo "--baseline и --build-cf — ключи режима main-config" >&2; exit 2; }
else
	[[ -z "$CFE_GIVEN" && -z "$DEMO_BASES" ]] || { echo "--cfe и --demo-bases — ключи режима extension" >&2; exit 2; }
	[[ "$BASELINE_RUN" == 0 || -z "$IMPORT_CM" ]] || { echo "--baseline и --import-baseline не совмещаются" >&2; exit 2; }
	[[ "$BASELINE_RUN" == 0 || "$LOAD" == 0 ]] || { echo "--baseline без --load: базу приводят к версии хранилища «было» обновлением из хранилища, гейт её не загружает" >&2; exit 2; }
fi
[[ -n "$TIMEOUT" ]] || { [[ "$MODE" == extension ]] && TIMEOUT=1800 || TIMEOUT=21600; }
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "--timeout: нужно положительное число секунд" >&2; exit 2; }

OUT="$ROOT/out"
LOGS="$OUT/release-gate"
mkdir -p "$LOGS" || exit 2
STARTED="$(date -Is)"
HEAD_SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
xml_version() { { grep -m1 -o '<Version>[^<]*' || true; } | sed 's/<Version>//'; }
q() { printf '%q ' "$@"; }
FAILED_FAST=0

# Отчёт пишется в REPORT_JSON / REPORT_TXT (в режиме --baseline — в каталог базовой линии).
REPORT_JSON="$OUT/release-gate.json"
REPORT_TXT="$OUT/release-gate.txt"
STEPS="$LOGS/steps.jsonl"

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

# ---------------------------------------------------------------------------
# Сравнение лога /Out пакетной проверки с базовой линией (режим main-config).
# Находка — непустая строка /Out без фраз успеха; позиция «(стр,кол)» отбрасывается,
# потому что правка сдвигает строки модуля. Сравниваются мультимножества строк.
# ---------------------------------------------------------------------------
COMPARE_PY=$(cat <<'PY'
import collections, json, os, re, sys
name, rc, wrapper, out, baseline_dir, base_sha, command = sys.argv[1:8]
rc = int(rc)

def read(path):
    data = open(path, "rb").read()
    for enc in ("utf-8-sig", "utf-16", "cp1251"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", "replace")

NEUTRAL = re.compile(r"^(синтаксических\s+)?ошибок\s+не\s+обнаружено|^проверка\s+\w*\s*(завершена|закончена)"
                     r"|^соединение\s+с\s+хранилищем\s+конфигурации\s+не\s+установлено|^errors\s+were\s+not\s+found")

def findings(path):
    items = []
    for line in read(path).splitlines():
        s = re.sub(r"\s+", " ", line.replace("﻿", "")).strip()
        if not s or NEUTRAL.search(s.lower()):
            continue
        items.append(re.sub(r"\(\d+,\d+\)", "()", s))
    return collections.Counter(items)

fail = []
wrap = read(wrapper) if os.path.exists(wrapper) else ""
if rc not in (0, 1):
    fail.append(f"designer-batch.sh завершился с кодом {rc} (2 — запуск отклонён, 3 — нет экрана): проверка не выполнена")
if re.search(r"сигнал 1, код возврата: тайм-аут", wrap):
    fail.append("тайм-аут: проверка не завершилась, сравнивать не с чем")
if not os.path.exists(out) or os.path.getsize(out) == 0:
    fail.append(f"лог /Out пуст или не записан: {out}")
meta_path = os.path.join(baseline_dir, "meta.json")
base_log = os.path.join(baseline_dir, f"{name}.1cv8.log")
meta = {}
if not os.path.exists(meta_path) or not os.path.exists(base_log):
    fail.append(f"нет базовой линии {baseline_dir} ({name}): до правок — tools/release-gate.sh --baseline --base {base_sha[:12]}")
else:
    meta = json.load(open(meta_path, encoding="utf-8"))
    if meta.get("base_sha") != base_sha:
        fail.append(f"базовая линия снята на {meta.get('base_sha')}, а база задачи {base_sha}")
    if meta.get("commands", {}).get(name) != command:
        fail.append(f"базовая линия снята другой командой: {meta.get('commands', {}).get(name)!r}, сейчас {command!r}")
if fail:
    print("\n".join(fail))
    sys.exit(1)
src = "импортирована: " + ", ".join(meta.get("imported_from", {}).values()) if meta.get("source") == "imported" else "снята гейтом"
before, after = findings(base_log), findings(out)
new, gone = after - before, before - after
print(f"Базовая линия ({src}, {meta.get('created_at')}): {sum(before.values())} строк; сейчас: {sum(after.values())}")
print(f"Новых строк: {sum(new.values())}; ушедших: {sum(gone.values())}")
if gone:
    print("Ушли (не ошибка):")
    for line in list(gone.elements())[:30]:
        print(f"  - {line}")
if new:
    print("НОВЫЕ относительно базовой линии:")
    for line in list(new.elements())[:200]:
        print(f"  + {line}")
    sys.exit(1)
print("Новых замечаний относительно базовой линии нет")
PY
)

# ===========================================================================
# Режим extension
# ===========================================================================
run_extension() {
	[[ -n "$EXT" ]] || { echo "EXTENSION_NAME не задан (окружение или .dev.env)" >&2; exit 2; }
	EXT_ROOT="${EXTENSIONS_PATH:-$(dev_env_value EXTENSIONS_PATH)}"
	EXT_DIR=""
	for dir in "$EXT_ROOT" src/cfe cfe; do
		[[ -n "$dir" && -f "$dir/$EXT/Configuration.xml" ]] && { EXT_DIR="$(realpath --relative-to="$ROOT" "$dir/$EXT")"; break; }
	done
	[[ -n "$EXT_DIR" ]] || { echo "Не найден Configuration.xml расширения $EXT" >&2; exit 2; }
	CONFIG="$EXT_DIR/Configuration.xml"
	DEMO_CMD="${RELEASE_GATE_DEMO_CMD:-$(dev_env_value RELEASE_GATE_DEMO_CMD)}"

	rm -f "$LOGS"/*.log "$LOGS"/*.result "$STEPS" "$REPORT_JSON" "$REPORT_TXT"
	: >"$STEPS"
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

	export R_EXT="$EXT" R_VERSION="$VERSION" R_MAIN_REF="$MAIN_REF" R_MAIN_SHA="$MAIN_SHA" \
		R_RELEASE_TAG="$RELEASE_TAG" R_RELEASE_VERSION="$RELEASE_VERSION" R_CFE="$CFE" R_CFE_SHA="$CFE_SHA" \
		R_DEMO_BASES="$DEMO_BASES"
}

# ===========================================================================
# Режим main-config
# ===========================================================================
run_main_config() {
	SRC=""
	for dir in "${EXPORT_PATH:-$(dev_env_value EXPORT_PATH)}" src/cf cf; do
		[[ -n "$dir" && -f "$dir/Configuration.xml" ]] && { SRC="$(realpath --relative-to="$ROOT" "$dir")"; break; }
	done
	[[ -n "$SRC" ]] || { echo "Не найден Configuration.xml основной конфигурации (EXPORT_PATH, src/cf)" >&2; exit 2; }
	MODES_RAW="${RELEASE_GATE_CHECK_MODES:-$(dev_env_value RELEASE_GATE_CHECK_MODES)}"
	read -r -a MODES <<<"$MODES_RAW"
	((${#MODES[@]})) || { echo "RELEASE_GATE_CHECK_MODES не задан (.dev.env): режимы проверки задаёт проект, например «-ThickClientOrdinaryApplication -Server -ExternalConnection»" >&2; exit 2; }
	for m in "${MODES[@]}"; do
		case "$m" in
			-ThinClient|-WebClient|-Server|-ExternalConnection|-ExternalConnectionServer|-ThickClientManagedApplication|-ThickClientServerManagedApplication|-ThickClientOrdinaryApplication|-ThickClientServerOrdinaryApplication|-MobileAppClient|-MobileAppServer) ;;
			*) echo "RELEASE_GATE_CHECK_MODES: «$m» — не режим проверки модулей" >&2; exit 2 ;;
		esac
	done
	BASELINE_DIR="${BASELINE_DIR_ARG:-$OUT/release-gate-baseline}"
	VERSION="$(xml_version <"$SRC/Configuration.xml")"

	if [[ -z "$BASE_REV" ]]; then
		((BASELINE_RUN)) && BASE_REV=HEAD || { echo "--base: базовый коммит «было» обязателен в режиме main-config" >&2; exit 2; }
	fi
	BASE_SHA="$(git rev-parse -q --verify "$BASE_REV^{commit}")" || { echo "--base $BASE_REV: нет такого коммита" >&2; exit 2; }

	CM=(/CheckModules "${MODES[@]}")
	CC=(/CheckConfig -ConfigLogIntegrity -IncorrectReferences "${MODES[@]}" -UnreferenceProcedures)
	CM_SHOWN="$(q "${CM[@]}")"; CM_SHOWN="${CM_SHOWN% }"
	CC_SHOWN="$(q "${CC[@]}")"; CC_SHOWN="${CC_SHOWN% }"
	DB=("$TOOLS/designer-batch.sh" --timeout "$TIMEOUT")
	# designer-batch отказывает в /CheckModules без -Extension, только если у проекта есть расширение.
	[[ -n "${EXT// /}" ]] && DB+=(--main-config)

	write_meta() {  # source, [imported cm], [imported cc]
		BASE_SHA="$BASE_SHA" CM_SHOWN="$CM_SHOWN" CC_SHOWN="$CC_SHOWN" MODES_RAW="$MODES_RAW" LOAD="$LOAD" HEAD_SHA="$HEAD_SHA" \
		python3 -I - "$BASELINE_DIR/meta.json" "$@" <<'PY'
import datetime, hashlib, json, os, sys
e = os.environ
path, source = sys.argv[1], sys.argv[2]
meta = {"base_sha": e["BASE_SHA"], "sha_head": e["HEAD_SHA"], "source": source,
        "commands": {"check-modules": e["CM_SHOWN"], "check-config": e["CC_SHOWN"]},
        "check_modes": e["MODES_RAW"], "loaded_by_gate": e["LOAD"] == "1",
        "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds")}
if source == "imported":
    meta["imported_from"] = {"check-modules": sys.argv[3], "check-config": sys.argv[4]}
    meta["imported_sha256"] = {k: hashlib.sha256(open(v, "rb").read()).hexdigest() for k, v in meta["imported_from"].items()}
    meta["note"] = "командные строки импортированных прогонов гейт не проверял"
json.dump(meta, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
	}

	# --- Импорт готовой базовой линии: без Конфигуратора и без отчёта гейта.
	if [[ -n "$IMPORT_CM" ]]; then
		for f in "$IMPORT_CM" "$IMPORT_CC"; do [[ -s "$f" ]] || { echo "Нет файла или он пуст: $f" >&2; exit 2; }; done
		mkdir -p "$BASELINE_DIR" || exit 2
		rm -f "$BASELINE_DIR"/*
		cp "$IMPORT_CM" "$BASELINE_DIR/check-modules.1cv8.log" && cp "$IMPORT_CC" "$BASELINE_DIR/check-config.1cv8.log" || exit 2
		write_meta imported "$IMPORT_CM" "$IMPORT_CC" || exit 2
		echo "Базовая линия импортирована в $BASELINE_DIR (база $BASE_SHA):"
		cat "$BASELINE_DIR/meta.json"
		exit 0
	fi

	step_clean_tree() {
		local dirty
		dirty="$(git status --porcelain --untracked-files=all)"
		if [[ -n "$dirty" ]]; then
			echo "Рабочее дерево не совпадает с коммитом $HEAD_SHA (незакоммиченное или неотслеживаемое):"
			echo "$dirty" | head -n 50
			return 1
		fi
		echo "Рабочее дерево совпадает с коммитом $HEAD_SHA"
	}

	if ((BASELINE_RUN)); then
		mkdir -p "$BASELINE_DIR" || exit 2
		rm -f "$BASELINE_DIR"/*
		REPORT_JSON="$BASELINE_DIR/baseline.json"
		REPORT_TXT="$BASELINE_DIR/baseline.txt"
		rm -f "$LOGS"/*.log "$LOGS"/*.result "$STEPS"
		: >"$STEPS"
		step_base_state() {
			if git diff --quiet "$BASE_SHA" HEAD -- "$SRC"; then
				echo "$SRC в HEAD совпадает с базой $BASE_SHA"
			else
				echo "$SRC в HEAD отличается от базы $BASE_SHA — базовая линия снимается до правок:"
				"${GIT[@]}" diff --stat "$BASE_SHA" HEAD -- "$SRC" | tail -n 20
				return 1
			fi
		}
		step_baseline_check() {  # имя, затем команда
			local name="$1" rc; shift
			"${DB[@]}" --out "$BASELINE_DIR/$name.1cv8.log" --result "$BASELINE_DIR/$name.result" -- "$@"
			rc=$?
			((rc == 0 || rc == 1)) || { echo "designer-batch.sh: код $rc — проверка не выполнена"; return 1; }
			[[ -s "$BASELINE_DIR/$name.1cv8.log" ]] || { echo "Лог /Out пуст"; return 1; }
			echo "Базовая линия $name: $(grep -c . "$BASELINE_DIR/$name.1cv8.log") строк /Out (замечания типовой — не провал)"
		}
		echo "release-gate --baseline: $BRANCH $HEAD_SHA, основная конфигурация $SRC, база $BASE_SHA"
		run_step clean-tree 0 "git status --porcelain --untracked-files=all" -- step_clean_tree
		run_step base-state 0 "git diff --quiet $BASE_SHA HEAD -- $SRC" -- step_base_state
		run_step check-modules 1 "tools/designer-batch.sh --timeout $TIMEOUT -- $CM_SHOWN" -- step_baseline_check check-modules "${CM[@]}"
		run_step check-config 1 "tools/designer-batch.sh --timeout $TIMEOUT -- $CC_SHOWN" -- step_baseline_check check-config "${CC[@]}"
		if ! grep -q '"status": "\(FAIL\|SKIPPED\)"' "$STEPS"; then write_meta gate || exit 2; fi
		export R_SRC="$SRC" R_VERSION="$VERSION" R_BASE_SHA="$BASE_SHA" R_MODES="$MODES_RAW" R_BASELINE_DIR="$BASELINE_DIR" R_REPO="$REPO" R_BASELINE_RUN=1
		return
	fi

	rm -f "$LOGS"/*.log "$LOGS"/*.result "$STEPS" "$REPORT_JSON" "$REPORT_TXT"
	: >"$STEPS"
	FILES=()
	if [[ -n "$FILES_ARG" ]]; then
		IFS=',' read -r -a parts <<<"$FILES_ARG"
		for p in "${parts[@]}"; do p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"; [[ -n "$p" ]] && FILES+=("$p"); done
	fi
	if [[ -n "$FILES_FROM" ]]; then
		[[ -f "$FILES_FROM" ]] || { echo "--files-from: нет файла $FILES_FROM" >&2; exit 2; }
		while IFS= read -r p || [[ -n "$p" ]]; do
			p="${p%$'\r'}"; p="${p%%#*}"; p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
			[[ -n "$p" ]] && FILES+=("$p")
		done <"$FILES_FROM"
	fi
	PATCH="${PATCH_GIVEN:-$OUT/change.patch}"
	PATCH_SHA=""
	CF="${CF_GIVEN:-$OUT/$(basename "$ROOT")-${HEAD_SHA:0:12}.cf}"
	CF_SHA=""

	step_base() {
		if [[ "$BASE_SHA" == "$HEAD_SHA" ]]; then echo "HEAD совпадает с базой $BASE_SHA: изменений нет"; return 1; fi
		if ! git merge-base --is-ancestor "$BASE_SHA" HEAD; then echo "База $BASE_SHA — не предок HEAD $HEAD_SHA"; return 1; fi
		echo "База: $(git log -1 --format='%H %s' "$BASE_SHA")"
		echo "HEAD: $(git log -1 --format='%H %s' HEAD)"
	}
	step_diff_scope() {
		local f p ok extra=0 changed=()
		mapfile -t changed < <("${GIT[@]}" diff --name-only --no-renames "$BASE_SHA" HEAD)
		((${#changed[@]})) || { echo "Разницы с базой $BASE_SHA нет"; return 1; }
		if ((${#FILES[@]} == 0)); then
			echo "Не задан перечень файлов задачи (--files или --files-from). Изменены:"
			printf '  %s\n' "${changed[@]}"
			return 1
		fi
		echo "Файлы задачи: ${FILES[*]}"
		for f in "${changed[@]}"; do
			ok=0
			for p in "${FILES[@]}"; do
				# shellcheck disable=SC2053  # p — шаблон
				[[ "$f" == $p ]] && { ok=1; break; }
			done
			if ((ok)); then echo "  OK      $f"; else echo "  ЛИШНИЙ  $f"; extra=1; fi
		done
		((extra == 0)) || { echo "В разнице есть файлы вне задачи"; return 1; }
		echo "Разница $BASE_SHA..HEAD: ${#changed[@]} файл(ов), все из задачи"
	}
	step_patch() {
		local idx="$LOGS/patch.index"
		rm -f "$idx"
		if [[ -z "$PATCH_GIVEN" ]]; then
			git diff --binary "$BASE_SHA" HEAD -- "$SRC" >"$PATCH" || return 1
			echo "Патч: git diff --binary $BASE_SHA HEAD -- $SRC > $PATCH"
		fi
		[[ -s "$PATCH" ]] || { echo "Патч пуст или не найден: $PATCH"; return 1; }
		GIT_INDEX_FILE="$idx" git read-tree "$BASE_SHA" || return 1
		echo "+ git apply --check --cached $PATCH   (индекс базового коммита $BASE_SHA)"
		if ! GIT_INDEX_FILE="$idx" git apply --whitespace=nowarn --check --cached "$PATCH"; then
			echo "Патч не применяется к $BASE_SHA"; rm -f "$idx"; return 1
		fi
		GIT_INDEX_FILE="$idx" git apply --whitespace=nowarn --cached "$PATCH" || { rm -f "$idx"; return 1; }
		if GIT_INDEX_FILE="$idx" git diff --cached --quiet HEAD -- "$SRC"; then
			echo "После применения к $BASE_SHA каталог $SRC совпадает с HEAD"
			rm -f "$idx"
		else
			echo "Патч не воспроизводит HEAD — расхождения:"
			GIT_INDEX_FILE="$idx" "${GIT[@]}" diff --cached --stat HEAD -- "$SRC" | tail -n 20
			rm -f "$idx"; return 1
		fi
	}
	step_bsl_calls() {
		local base_dir="$LOGS/base-src" rc_head rc_base
		rm -rf "$base_dir"; mkdir -p "$base_dir"
		git archive "$BASE_SHA" -- ":(glob)$SRC/**/*.bsl" ":(glob)$SRC/CommonModules/*.xml" | tar -x -C "$base_dir" || { echo "Не выгрузить модули базы"; return 1; }
		python3 -I "$TOOLS/check-bsl-calls.py" "$SRC" >"$LOGS/check-bsl-calls.head.txt"; rc_head=$?
		python3 -I "$TOOLS/check-bsl-calls.py" "$base_dir/$SRC" >"$LOGS/check-bsl-calls.base.txt"; rc_base=$?
		rm -rf "$base_dir"
		((rc_head < 2 && rc_base < 2)) || { echo "check-bsl-calls.py: ошибка запуска (HEAD $rc_head, база $rc_base)"; return 1; }
		python3 -I - "$LOGS/check-bsl-calls.base.txt" "$LOGS/check-bsl-calls.head.txt" <<'PY'
import collections, re, sys
def load(p):
    return collections.Counter(re.sub(r":\d+ ", " ", l.strip()) for l in open(p, encoding="utf-8") if l.strip())
base, head = load(sys.argv[1]), load(sys.argv[2])
new = head - base
print(f"Находок: база {sum(base.values())}, HEAD {sum(head.values())}; новых {sum(new.values())}")
for l in list(new.elements())[:100]:
    print(f"  + {l}")
sys.exit(1 if new else 0)
PY
	}
	step_check_vs_baseline() {  # имя, показанная команда, затем команда
		local name="$1" shown="$2" rc; shift 2
		local out="$LOGS/$name.1cv8.log" wrap="$LOGS/$name.wrapper.log"
		if [[ ! -f "$BASELINE_DIR/meta.json" || ! -f "$BASELINE_DIR/$name.1cv8.log" ]]; then
			echo "Нет базовой линии $BASELINE_DIR ($name): проверку не запускаю — сравнивать не с чем."
			echo "До правок: tools/release-gate.sh --baseline --base ${BASE_SHA:0:12} (или --import-baseline)"
			return 1
		fi
		"${DB[@]}" --out "$out" --result "$LOGS/$name.result" -- "$@" >"$wrap" 2>&1
		rc=$?
		cat "$wrap"
		echo "--- сравнение с базовой линией"
		python3 -I -c "$COMPARE_PY" "$name" "$rc" "$wrap" "$out" "$BASELINE_DIR" "$BASE_SHA" "$shown"
	}

	echo "release-gate: $BRANCH $HEAD_SHA, основная конфигурация $SRC (хранилище ${REPO:-—}), база $BASE_SHA"
	run_step clean-tree 0 "git status --porcelain --untracked-files=all" -- step_clean_tree
	run_step base 0 "git merge-base --is-ancestor $BASE_SHA HEAD" -- step_base
	run_step diff-scope 0 "git diff --name-only $BASE_SHA HEAD ⊆ ${FILES[*]:-<не задано>}" -- step_diff_scope
	run_step patch 0 "git apply --check --cached $PATCH на индексе $BASE_SHA; результат = HEAD:$SRC" -- step_patch
	[[ -s "$PATCH" ]] && PATCH_SHA="$(sha256sum "$PATCH" | cut -d' ' -f1)"
	run_step check-bsl-calls 0 "python3 -I tools/check-bsl-calls.py $SRC — новые находки к $BASE_SHA" -- step_bsl_calls

	if ((LOAD)); then
		# Полная загрузка в базу, подключённую к хранилищу, платформой запрещена («текущая конфигурация
		# помещена в хранилище»), а vrunner cf load не передаёт параметры хранилища. Поэтому — загрузка
		# по списку: изменённые файлы base..HEAD и XML-описания их объектов (и форм), с параметрами хранилища.
		LOAD_LIST="$LOGS/load-list.txt"
		step_load_cf() {
			local f rel prefix part deleted
			deleted="$("${GIT[@]}" diff --name-only --diff-filter=D "$BASE_SHA" HEAD -- "$SRC")"
			if [[ -n "$deleted" ]]; then
				echo "Удалённые файлы загрузкой по списку не переносятся — загрузите базу из хранилища иначе:"
				echo "$deleted"
				return 1
			fi
			: >"$LOAD_LIST"
			while IFS= read -r f; do
				rel="${f#"$SRC"/}"
				prefix=""
				IFS='/' read -r -a parts <<<"$rel"
				for part in "${parts[@]::${#parts[@]}-1}"; do
					prefix="${prefix:+$prefix/}$part"
					[[ -f "$SRC/$prefix.xml" ]] && echo "$prefix.xml" >>"$LOAD_LIST"
				done
				echo "$rel" >>"$LOAD_LIST"
			done < <("${GIT[@]}" diff --name-only --no-renames "$BASE_SHA" HEAD -- "$SRC")
			sort -u -o "$LOAD_LIST" "$LOAD_LIST"
			[[ -s "$LOAD_LIST" ]] || { echo "Нечего загружать: разницы в $SRC нет"; return 1; }
			echo "Список загрузки ($LOAD_LIST):"; sed 's/^/  /' "$LOAD_LIST"
			"${DB[@]}" --load --repository --out "$LOGS/load.1cv8.log" --result "$LOGS/load.result" -- \
				/LoadConfigFromFiles "$ROOT/$SRC" -listFile "$LOAD_LIST" || return 1
			xvfb-run -a vrunner infobase update
		}
		run_step load 1 "tools/designer-batch.sh --load --repository -- /LoadConfigFromFiles $SRC -listFile out/release-gate/load-list.txt && xvfb-run -a vrunner infobase update" -- step_load_cf
	fi
	run_step check-modules 1 "tools/designer-batch.sh --timeout $TIMEOUT -- $CM_SHOWN; новые к базовой линии" -- \
		step_check_vs_baseline check-modules "$CM_SHOWN" "${CM[@]}"
	run_step check-config 1 "tools/designer-batch.sh --timeout $TIMEOUT -- $CC_SHOWN; новые к базовой линии" -- \
		step_check_vs_baseline check-config "$CC_SHOWN" "${CC[@]}"

	if ((BUILD_CF)); then
		if [[ -n "$CF_GIVEN" ]]; then
			run_step build-cf 1 "готовый файл --cf $CF" -- test -s "$CF"
		else
			rm -f "$CF"
			DC=(/DumpCfg "$CF")
			run_step build-cf 1 "tools/designer-batch.sh --timeout $TIMEOUT -- $(q "${DC[@]}")" -- \
				"${DB[@]}" --out "$LOGS/build-cf.1cv8.log" --result "$LOGS/build-cf.result" -- "${DC[@]}"
		fi
		run_step sha256 1 "sha256sum $CF" -- sha256sum "$CF"
		[[ -s "$CF" ]] && CF_SHA="$(sha256sum "$CF" | cut -d' ' -f1)"
	fi

	export R_SRC="$SRC" R_VERSION="$VERSION" R_BASE_SHA="$BASE_SHA" R_MODES="$MODES_RAW" R_BASELINE_DIR="$BASELINE_DIR" \
		R_REPO="$REPO" R_FILES="$(printf '%s\n' "${FILES[@]}")" R_PATCH="$PATCH" R_PATCH_SHA="$PATCH_SHA" \
		R_CF="$( ((BUILD_CF)) && echo "$CF")" R_CF_SHA="$CF_SHA" R_BASELINE_RUN=0
}

if [[ "$MODE" == extension ]]; then run_extension; else run_main_config; fi

GATE_VERSION="$GATE_VERSION" MODE="$MODE" HEAD_SHA="$HEAD_SHA" BRANCH="$BRANCH" LOAD="$LOAD" STARTED="$STARTED" \
python3 -I - "$STEPS" "$REPORT_JSON" "$REPORT_TXT" <<'PY'
import datetime, json, os, sys
e = os.environ
g = lambda k: e.get(k, "")
steps = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
result = "PASS" if steps and all(s["status"] == "PASS" for s in steps) else "FAIL"
report = {
    "gate_version": int(e["GATE_VERSION"]),
    "mode": e["MODE"],
    "result": result,
    "sha_head": e["HEAD_SHA"],
    "branch": e["BRANCH"],
    "extension": g("R_EXT"),
    "version": g("R_VERSION"),
    "main_ref": g("R_MAIN_REF"),
    "main_sha": g("R_MAIN_SHA"),
    "last_release_tag": g("R_RELEASE_TAG"),
    "last_release_version": g("R_RELEASE_VERSION"),
    "loaded_by_gate": e["LOAD"] == "1",
    "cfe_path": g("R_CFE"),
    "cfe_sha256": g("R_CFE_SHA"),
    "demo_bases": [b.strip() for b in g("R_DEMO_BASES").split(",") if b.strip()],
}
if e["MODE"] == "main-config":
    meta_path = os.path.join(g("R_BASELINE_DIR"), "meta.json")
    meta = json.load(open(meta_path, encoding="utf-8")) if os.path.exists(meta_path) else None
    report.update({
        "baseline_run": g("R_BASELINE_RUN") == "1",
        "config_dir": g("R_SRC"),
        "repository": g("R_REPO"),
        "base_sha": g("R_BASE_SHA"),
        "check_modes": g("R_MODES"),
        "baseline_dir": g("R_BASELINE_DIR"),
        "baseline": meta,
        "files_scope": [f for f in g("R_FILES").splitlines() if f],
        "patch_path": g("R_PATCH"),
        "patch_sha256": g("R_PATCH_SHA"),
        "cf_path": g("R_CF"),
        "cf_sha256": g("R_CF_SHA"),
    })
report.update({
    "started_at": e["STARTED"],
    "finished_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "steps": steps,
})
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
with open(sys.argv[3], "w", encoding="utf-8") as f:
    title = "release-gate --baseline" if report.get("baseline_run") else "release-gate"
    f.write(f"{title}: {result}\nSHA HEAD: {report['sha_head']} ({report['branch']})\n")
    if e["MODE"] == "extension":
        f.write(f"Расширение: {report['extension']} {report['version']}; последний релиз: {report['last_release_tag'] or '—'}\n")
    else:
        f.write(f"Основная конфигурация: {report['config_dir']} {report['version']}; хранилище: {report['repository'] or '—'}\n")
        f.write(f"База: {report['base_sha']}; режимы проверки: {report['check_modes']}\n")
        meta = report["baseline"]
        if not meta:
            f.write("Базовая линия: нет\n")
        elif meta.get("source") == "imported":
            f.write(f"Базовая линия: импортирована {meta['created_at']} из {', '.join(meta['imported_from'].values())} — командные строки не проверены гейтом\n")
        else:
            f.write(f"Базовая линия: снята гейтом {meta['created_at']} на {meta['sha_head']}\n")
    f.write(f"Загрузка гейтом: {'да' if report['loaded_by_gate'] else 'нет — проверена уже загруженная база'}\n")
    if e["MODE"] == "extension":
        f.write(f"Сборка: {report['cfe_path']}\nsha256: {report['cfe_sha256'] or '—'}\n\n")
    elif not report.get("baseline_run"):
        f.write(f"Файлы задачи: {', '.join(report['files_scope']) or '—'}\n")
        f.write(f"Патч: {report['patch_path']}\nsha256 патча: {report['patch_sha256'] or '—'}\n")
        f.write(f"Сборка: {report['cf_path'] or '— (до помещения в хранилище; --build-cf после фиксации)'}\nsha256: {report['cf_sha256'] or '—'}\n\n")
    else:
        f.write("\n")
    for s in steps:
        f.write(f"[{s['status']}] {s['name']} rc={s['rc']} {s['duration_s']}s\n  $ {s['command']}\n")
        if s["status"] != "PASS":
            f.write("".join(f"  | {l}\n" for l in s["tail"][-15:]))
PY
echo
cat "$REPORT_TXT"
echo "Отчёт: ${REPORT_JSON#"$ROOT/"}, ${REPORT_TXT#"$ROOT/"}"
head -n1 "$REPORT_TXT" | grep -q 'PASS$' || exit 1
