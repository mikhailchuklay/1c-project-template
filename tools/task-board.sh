#!/usr/bin/env bash
# Доска задач проекта для архитекторов (docs/headless-agent.md, «Доска задач»).
#
# Один файл на проект вне git: <основная копия>/.task-board/board.json (путь в .gitignore).
# Сессии из рабочих деревьев (git worktree) пишут в тот же файл: основная копия находится
# через `git rev-parse --git-common-dir`. Каждая запись — под flock, файл заменяется атомарно.
#
# Что лежит на доске:
#   tasks   очередь работ и карточка задачи: issue, приоритет, архитектор-сессия, исполнитель
#           (контейнер/харнес), стенд/база, состояние; круги ревью, прогоны агента, время,
#           токены и $ агента (если известны), хотфиксы после релиза, заметки;
#   stands  занятость стендов и временных копий: IB id, публикации, кто держит, с какого времени.
#
# Заменяет согласование стенда сообщениями между сессиями: перед запуском агента и загрузкой
# на стенд — `list`, затем `claim`; после — `release`.
#
# Переменные: TASK_BOARD_FILE — другой путь к файлу доски (для проверки на копии).
set -euo pipefail

usage() {
	cat <<'EOF'
Использование: tools/task-board.sh <команда> [аргументы]

  list [--all] [--json]          очередь (без закрытых, --all — все) и занятость стендов
  set <issue> поле=значение…     создать/изменить задачу; поля:
                                 title priority architect executor harness model stand ib state
                                 pr release tokens cost_usd note
                                 (state: queued|working|question|review|accepted|released|closed)
  inc <issue> <счётчик> [N] [--note текст]
                                 review_rounds | agent_runs | hotfixes (+N, по умолчанию 1)
  claim <стенд> --holder <кто> [--issue N] [--ib ID] [--pub URL]… [--temp] [--note текст]
                                 занять стенд или временную копию; занят другим — код 1
  release <стенд> --holder <кто> [--drop]
                                 освободить; --drop — удалить запись (копия удалена)
  card <issue> [--markdown]      карточка задачи (markdown — для комментария в issue)
  scorecard [--days N]           сводка по исполнителям/харнесам за N дней (по умолчанию 7)
  path                           путь к файлу доски

Коды возврата: 0 — успех; 1 — отказ (стенд занят, нет задачи); 2 — ошибка аргументов.
EOF
}

if [[ $# -eq 0 || "$1" == -h || "$1" == --help ]]; then usage; [[ $# -gt 0 ]]; exit $?; fi

if [[ -z "${TASK_BOARD_FILE:-}" ]]; then
	common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
		{ echo "Не git-репозиторий и не задан TASK_BOARD_FILE" >&2; exit 2; }
	TASK_BOARD_FILE="$(dirname "$common")/.task-board/board.json"
fi
export TASK_BOARD_FILE

exec python3 -I - "$@" <<'PY'
import datetime as dt
import fcntl
import json
import os
import sys
import tempfile

PATH = os.environ["TASK_BOARD_FILE"]
TASK_FIELDS = {"title", "priority", "architect", "executor", "harness", "model", "stand", "ib", "state",
               "pr", "release", "tokens", "cost_usd", "note"}
STATES = {"queued", "working", "question", "review", "accepted", "released", "closed"}
COUNTERS = {"review_rounds", "agent_runs", "hotfixes"}


def now():
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def die(msg, code=2):
    print(msg, file=sys.stderr)
    sys.exit(code)


class Board:
    """Доска под исключительной блокировкой: чтение → изменение → атомарная запись."""

    def __init__(self, write):
        os.makedirs(os.path.dirname(PATH), exist_ok=True)
        self.write = write
        self.lock = open(PATH + ".lock", "a")
        fcntl.flock(self.lock, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
        try:
            with open(PATH, encoding="utf-8") as f:
                self.data = json.load(f)
        except FileNotFoundError:
            self.data = {}
        self.data.setdefault("version", 1)
        self.data.setdefault("tasks", {})
        self.data.setdefault("stands", {})

    def __enter__(self):
        return self.data

    def __exit__(self, exc_type, *_):
        try:
            if self.write and exc_type is None:
                self.data["updated_at"] = now()
                fd, tmp = tempfile.mkstemp(dir=os.path.dirname(PATH), prefix=".board-")
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(self.data, f, ensure_ascii=False, indent=2)
                os.replace(tmp, PATH)
        finally:
            fcntl.flock(self.lock, fcntl.LOCK_UN)
            self.lock.close()


def task_of(data, issue, create=False):
    issue = str(issue).lstrip("#")
    t = data["tasks"].get(issue)
    if t is None:
        if not create:
            die(f"Нет задачи #{issue} на доске", 1)
        t = data["tasks"][issue] = {"issue": issue, "state": "queued", "created_at": now(),
                                    "review_rounds": 0, "agent_runs": 0, "hotfixes": 0, "log": []}
    return t


def parse_opts(args, flags=(), multi=()):
    opts, rest, i = {}, [], 0
    while i < len(args):
        a = args[i]
        if a.startswith("--"):
            key = a[2:]
            if key in flags:
                opts[key] = True
                i += 1
                continue
            if i + 1 >= len(args):
                die(f"{a} требует значение")
            if key in multi:
                opts.setdefault(key, []).append(args[i + 1])
            else:
                opts[key] = args[i + 1]
            i += 2
        else:
            rest.append(a)
            i += 1
    return opts, rest


def hours(t):
    start, end = t.get("started_at"), t.get("closed_at") or t.get("released_at")
    if not start:
        return None
    end_dt = dt.datetime.fromisoformat(end) if end else dt.datetime.now().astimezone()
    return round((end_dt - dt.datetime.fromisoformat(start)).total_seconds() / 3600, 1)


def cmd_set(args):
    if len(args) < 2:
        die("set <issue> поле=значение…")
    with Board(True) as data:
        t = task_of(data, args[0], create=True)
        for pair in args[1:]:
            if "=" not in pair:
                die(f"Ожидалось поле=значение: {pair}")
            key, val = pair.split("=", 1)
            if key not in TASK_FIELDS:
                die(f"Неизвестное поле {key}; допустимы: {', '.join(sorted(TASK_FIELDS))}")
            if key == "state":
                if val not in STATES:
                    die(f"state: одно из {', '.join(sorted(STATES))}")
                stamp = {"working": "started_at", "released": "released_at", "closed": "closed_at"}.get(val)
                if stamp and not t.get(stamp):
                    t[stamp] = now()
            if key in ("tokens", "priority"):
                val = int(val) if val.lstrip("-").isdigit() else val
            elif key == "cost_usd":
                try:
                    val = float(val)
                except ValueError:
                    die("cost_usd — число")
            if key == "note":
                t.setdefault("log", []).append({"at": now(), "note": val})
            else:
                t[key] = val
        t["updated_at"] = now()
        print(json.dumps(t, ensure_ascii=False))


def cmd_inc(args):
    opts, rest = parse_opts(args)
    if len(rest) < 2 or rest[1] not in COUNTERS:
        die(f"inc <issue> {'|'.join(sorted(COUNTERS))} [N] [--note текст]")
    n = int(rest[2]) if len(rest) > 2 else 1
    with Board(True) as data:
        t = task_of(data, rest[0], create=True)
        t[rest[1]] = int(t.get(rest[1], 0)) + n
        t.setdefault("log", []).append({"at": now(), "event": rest[1], "n": n, "note": opts.get("note", "")})
        t["updated_at"] = now()
        print(f"#{t['issue']} {rest[1]}={t[rest[1]]}")


def cmd_claim(args):
    opts, rest = parse_opts(args, flags=("temp",), multi=("pub",))
    if len(rest) != 1 or not opts.get("holder"):
        die("claim <стенд> --holder <кто> [--issue N] [--ib ID] [--pub URL]… [--temp] [--note текст]")
    name = rest[0]
    with Board(True) as data:
        s = data["stands"].get(name, {})
        holder = s.get("holder")
        if holder and holder != opts["holder"]:
            die(f"Стенд {name} занят: {holder} (issue {s.get('issue') or '—'}) с {s.get('since')}; "
                f"{s.get('note') or ''}".rstrip("; "), 1)
        s.update({"holder": opts["holder"], "since": s.get("since") if holder else now(),
                  "issue": opts.get("issue", s.get("issue", "")), "note": opts.get("note", s.get("note", ""))})
        if "ib" in opts:
            s["ib"] = opts["ib"]
        if "pub" in opts:
            s["publications"] = opts["pub"]
        if opts.get("temp"):
            s["temp_copy"] = True
        data["stands"][name] = s
        print(f"{name}: занят {s['holder']} с {s['since']}")


def cmd_release(args):
    opts, rest = parse_opts(args, flags=("drop",))
    if len(rest) != 1 or not opts.get("holder"):
        die("release <стенд> --holder <кто> [--drop]")
    name = rest[0]
    with Board(True) as data:
        s = data["stands"].get(name)
        if not s:
            die(f"Стенда {name} нет на доске", 1)
        if s.get("holder") and s["holder"] != opts["holder"]:
            die(f"Стенд {name} держит {s['holder']}, а не {opts['holder']}: освобождает держатель", 1)
        if opts.get("drop"):
            del data["stands"][name]
            print(f"{name}: запись удалена")
        else:
            s.update({"holder": "", "since": "", "issue": "", "released_at": now()})
            print(f"{name}: свободен")


def fmt_task(t):
    return (f"#{t['issue']:<5} p{t.get('priority', '-')!s:<3} {t.get('state', ''):<9} "
            f"исп={t.get('executor', '—')}/{t.get('harness', '—')}{('/' + t['model']) if t.get('model') else ''} стенд={t.get('stand', '—')} "
            f"арх={t.get('architect', '—')} ревью={t.get('review_rounds', 0)} прогоны={t.get('agent_runs', 0)} "
            f"хотфиксы={t.get('hotfixes', 0)}  {t.get('title', '')}")


def cmd_list(args):
    opts, _ = parse_opts(args, flags=("all", "json"))
    with Board(False) as data:
        tasks = [t for t in data["tasks"].values() if opts.get("all") or t.get("state") != "closed"]
        tasks.sort(key=lambda t: (t.get("priority") if isinstance(t.get("priority"), int) else 99, t["issue"]))
        if opts.get("json"):
            print(json.dumps({"tasks": tasks, "stands": data["stands"]}, ensure_ascii=False, indent=2))
            return
        print(f"Доска: {PATH}")
        print("Очередь:" if tasks else "Очередь: пусто")
        for t in tasks:
            print("  " + fmt_task(t))
        print("Стенды и временные копии:" if data["stands"] else "Стенды: нет записей")
        for name, s in sorted(data["stands"].items()):
            who = f"занят {s['holder']} с {s.get('since')} (issue {s.get('issue') or '—'})" if s.get("holder") else "свободен"
            extra = []
            if s.get("ib"):
                extra.append(f"ib={s['ib']}")
            if s.get("publications"):
                extra.append("pub=" + ",".join(s["publications"]))
            if s.get("temp_copy"):
                extra.append("временная копия")
            if s.get("note"):
                extra.append(s["note"])
            print(f"  {name:<20} {who} {' '.join(extra)}")


def cmd_card(args):
    opts, rest = parse_opts(args, flags=("markdown",))
    if len(rest) != 1:
        die("card <issue> [--markdown]")
    with Board(False) as data:
        t = task_of(data, rest[0])
    if not opts.get("markdown"):
        print(json.dumps(t, ensure_ascii=False, indent=2))
        return
    h = hours(t)
    rows = [("Исполнитель", f"{t.get('executor', '—')} ({t.get('harness', '—')}{', ' + t['model'] if t.get('model') else ''})"),
            ("Архитектор-сессия", t.get("architect", "—")), ("Стенд / база", f"{t.get('stand', '—')} / {t.get('ib', '—')}"),
            ("Круги ревью", t.get("review_rounds", 0)), ("Прогоны агента", t.get("agent_runs", 0)),
            ("Время, ч", "—" if h is None else h), ("Токены агента", t.get("tokens", "нет данных")),
            ("Стоимость агента, $", t.get("cost_usd", "нет данных")), ("Хотфиксы после релиза", t.get("hotfixes", 0)),
            ("PR", t.get("pr", "—")), ("Релиз", t.get("release", "—"))]
    print(f"**Карточка задачи #{t['issue']}** {t.get('title', '')}\n")
    print("| Показатель | Значение |\n|---|---|")
    for k, v in rows:
        print(f"| {k} | {v} |")
    notes = [e for e in t.get("log", []) if e.get("note")]
    if notes:
        print("\nЗаметки:")
        for e in notes:
            print(f"- {e['at'][:16]} {e.get('event', '')} {e['note']}".replace("  ", " "))


def cmd_scorecard(args):
    opts, _ = parse_opts(args)
    days = int(opts.get("days", 7))
    since = dt.datetime.now().astimezone() - dt.timedelta(days=days)
    groups = {}
    with Board(False) as data:
        tasks = list(data["tasks"].values())
    for t in tasks:
        stamp = t.get("updated_at") or t.get("created_at")
        if not stamp or dt.datetime.fromisoformat(stamp) < since:
            continue
        key = t.get("harness") or t.get("executor") or "—"
        if t.get("model"):
            key = f"{key} / {t['model']}"
        g = groups.setdefault(key, {"tasks": 0, "released": 0, "review_rounds": 0, "agent_runs": 0,
                                    "hotfixes": 0, "hours": 0.0, "tokens": 0, "cost_usd": 0.0, "cost_known": 0})
        g["tasks"] += 1
        g["released"] += t.get("state") in ("released", "closed")
        for c in COUNTERS:
            g[c] += int(t.get(c, 0))
        g["hours"] += hours(t) or 0
        if isinstance(t.get("tokens"), int):
            g["tokens"] += t["tokens"]
        if isinstance(t.get("cost_usd"), (int, float)):
            g["cost_usd"] += t["cost_usd"]
            g["cost_known"] += 1
    print(f"Сводка по харнесам и моделям за {days} дн. (с {since:%Y-%m-%d})\n")
    print("| Харнес / модель | Задач | Выпущено | Ревью/задачу | Прогонов/задачу | Хотфиксов | Часов/задачу | Токены | $ |")
    print("|---|---|---|---|---|---|---|---|---|")
    for key, g in sorted(groups.items()):
        n = g["tasks"]
        cost = f"{g['cost_usd']:.2f}" if g["cost_known"] else "нет данных"
        print(f"| {key} | {n} | {g['released']} | {g['review_rounds'] / n:.1f} | {g['agent_runs'] / n:.1f} | "
              f"{g['hotfixes']} | {g['hours'] / n:.1f} | {g['tokens'] or 'нет данных'} | {cost} |")
    if not groups:
        print("| — | 0 | | | | | | | |")


def main(argv):
    cmd, args = argv[0], argv[1:]
    handlers = {"list": cmd_list, "set": cmd_set, "inc": cmd_inc, "claim": cmd_claim,
                "release": cmd_release, "card": cmd_card, "scorecard": cmd_scorecard}
    if cmd == "path":
        print(PATH)
        return
    if cmd not in handlers:
        die(f"Неизвестная команда: {cmd} (tools/task-board.sh --help)")
    handlers[cmd](args)


main(sys.argv[1:])
PY
