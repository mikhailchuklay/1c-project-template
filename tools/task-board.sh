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
# Переменные: TASK_BOARD_FILE — другой путь к файлу доски (для проверки на копии);
#   AGENT_SSH_HOST (по умолчанию dev-workplaces-via-services), AGENT_EXEC_USER (dev) — для команды usage.
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
  usage <issue> <контейнер> <задача> [--file путь]
                                 забрать расход агента (usage из agent-status.json задачи в контейнере:
                                 номер N -> dev-agent<N>) в tokens/cost_usd/api_equiv_usd; задач у issue
                                 может быть несколько — суммируются; --file — локальный agent-status.json
  version reserve <issue> [--patch] [--from X.Y.Z.W] [--first X.Y.Z.W] [--ttl часы] [--branch ветка]
                                 слот слияния и номер выпуска: следующий от последнего тега в origin
                                 (MINOR, --patch — PATCH; --from — хотфикс от указанного выпуска;
                                 --first — номер первого выпуска, когда тегов в origin ещё нет).
                                 Слот один на репозиторий: держит другая задача — код 1 и кто держит.
                                 Повтор той же задачей возвращает её номер. Слот снимается сам, когда
                                 тег с номером появился в origin или истёк срок (по умолчанию 3 ч)
  version release <issue>        отдать слот (слияние отменено или отложено)
  version list [--json]          кто держит слот (--json — объект слота или {})
                                 Слот публикуется в GitHub (переменная репозитория MERGE_SLOT) для статуса
                                 merge-slot на PR; --branch — ветка PR держателя, если по имени ветки и
                                 тексту PR задачу не узнать. Нужен gh; TASK_BOARD_NO_PUBLISH=1 — не публиковать
  card <issue> [--markdown]      карточка задачи (markdown — для комментария в issue)
  scorecard [--days N]           сводка по исполнителям/харнесам за N дней (по умолчанию 7)
  path                           путь к файлу доски

Коды возврата: 0 — успех; 1 — отказ (стенд или слот слияния занят, нет задачи); 2 — ошибка аргументов.
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
import re
import sys
import subprocess
import tempfile

PATH = os.environ["TASK_BOARD_FILE"]
TASK_FIELDS = {"title", "priority", "architect", "executor", "harness", "model", "stand", "ib", "state",
               "pr", "release", "tokens", "cost_usd", "api_equiv_usd", "note"}
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
            elif key in ("cost_usd", "api_equiv_usd"):
                try:
                    val = float(val)
                except ValueError:
                    die(f"{key} — число")
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
            ("Стоимость агента, $", t.get("cost_usd", "нет данных")),
            ("Эквивалент по прайсу API, $", t.get("api_equiv_usd", "нет данных")), ("Хотфиксы после релиза", t.get("hotfixes", 0)),
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
                                    "hotfixes": 0, "hours": 0.0, "tokens": 0, "cost_usd": 0.0, "cost_known": 0,
                                    "equiv": 0.0, "equiv_known": 0})
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
        if isinstance(t.get("api_equiv_usd"), (int, float)):
            g["equiv"] += t["api_equiv_usd"]
            g["equiv_known"] += 1
    print(f"Сводка по харнесам и моделям за {days} дн. (с {since:%Y-%m-%d})\n")
    print("| Харнес / модель | Задач | Выпущено | Ревью/задачу | Прогонов/задачу | Хотфиксов | Часов/задачу | Токены | $ | $ экв. API |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for key, g in sorted(groups.items()):
        n = g["tasks"]
        cost = f"{g['cost_usd']:.2f}" if g["cost_known"] else "нет данных"
        equiv = f"{g['equiv']:.2f}" if g["equiv_known"] else "нет данных"
        print(f"| {key} | {n} | {g['released']} | {g['review_rounds'] / n:.1f} | {g['agent_runs'] / n:.1f} | "
              f"{g['hotfixes']} | {g['hours'] / n:.1f} | {g['tokens'] or 'нет данных'} | {cost} | {equiv} |")
    if not groups:
        print("| — | 0 | | | | | | | | |")


def container_name(c):
    if c.startswith("dev-agent"):
        return c
    return f"dev-agent{c}" if c.isdigit() else f"dev-agent-{c}"


def cmd_usage(args):
    opts, rest = parse_opts(args)
    if len(rest) != 3:
        die("usage <issue> <контейнер> <задача> [--file путь]")
    issue, cont, task = rest
    if opts.get("file"):
        raw = open(opts["file"], encoding="utf-8").read()
    else:
        host = os.environ.get("AGENT_SSH_HOST", "dev-workplaces-via-services")
        user = os.environ.get("AGENT_EXEC_USER", "dev")
        path = f"/home/{user}/tasks/{task}/agent-status.json"
        r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", host,
                            f"docker exec -u {user} {container_name(cont)} cat {path}"],
                           capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            die(f"Не прочитан {path} в {container_name(cont)}: {r.stderr.strip()[:200]}", 1)
        raw = r.stdout
    u = json.loads(raw).get("usage")
    if not isinstance(u, dict):
        die(f"В статусе задачи {task} нет usage (прогоны до образа с учётом токенов не считаются)", 1)
    with Board(True) as data:
        t = task_of(data, issue, create=False)
        t.setdefault("usage_by_task", {})[task] = {
            k: u.get(k) for k in ("input", "output", "cache_read", "cache_write", "cost_usd",
                                  "api_equiv_usd", "cost_incomplete")}
        tok, cost, equiv, incomplete = 0, 0.0, 0.0, False
        for v in t["usage_by_task"].values():
            tok += sum(int(v.get(k) or 0) for k in ("input", "output", "cache_read", "cache_write"))
            cost += float(v.get("cost_usd") or 0)
            equiv += float(v.get("api_equiv_usd") or 0)
            incomplete = incomplete or bool(v.get("cost_incomplete"))
        t["tokens"], t["cost_usd"], t["api_equiv_usd"] = tok, round(cost, 4), round(equiv, 4)
        t["cost_incomplete"] = incomplete
        t["updated_at"] = now()
        t.setdefault("log", []).append({"at": now(), "event": "usage",
                                        "note": f"{task}: {tok} токенов, ${cost:.2f} (экв. API ${equiv:.2f})"})
    print(f"#{issue}: {tok} токенов, ${cost:.4f}, эквивалент API ${equiv:.4f}"
          + (" (цена неполная)" if incomplete else ""))


VERSION_RE = re.compile(r"(\d+(?:\.\d+){1,3})$")


def remote_versions():
    """Номера выпусков по тегам origin (последняя числовая часть имени тега)."""
    try:
        out = subprocess.run(["git", "ls-remote", "--tags", "--refs", "origin"], capture_output=True,
                             text=True, timeout=60, check=True).stdout
    except (subprocess.SubprocessError, OSError) as e:
        die(f"Не удалось прочитать теги origin: {e}", 1)
    found = set()
    for line in out.splitlines():
        m = VERSION_RE.search(line.rsplit("/", 1)[-1])
        if m:
            found.add(m.group(1))
    return found


def vkey(v):
    parts = [int(x) for x in v.split(".")]
    return parts + [0] * (4 - len(parts))


def bump(v, patch):
    p = vkey(v)
    if patch:
        p[2] += 1
    else:
        p[1] += 1
        p[2] = 0
    p[3] = 0
    return ".".join(map(str, p))


def publish_slot(slot):
    """Слот — в переменную репозитория MERGE_SLOT и перезапуск статуса merge-slot на PR (GitHub).

    Сбой публикации слот не отменяет: доска остаётся источником истины, но статус на PR устареет.
    TASK_BOARD_NO_PUBLISH=1 — не публиковать (проект без GitHub, тесты)."""
    if os.environ.get("TASK_BOARD_NO_PUBLISH") == "1":
        return
    body = json.dumps({k: slot[k] for k in ("issue", "version", "expires_at", "branch") if slot.get(k)},
                      ensure_ascii=False) if slot else "{}"
    try:
        subprocess.run(["gh", "variable", "set", "MERGE_SLOT", "--body", body], capture_output=True,
                       text=True, timeout=60, check=True)
    except (subprocess.SubprocessError, OSError) as e:
        err = getattr(e, "stderr", "") or str(e)
        print(f"Предупреждение: слот не опубликован в GitHub (gh variable set MERGE_SLOT): {err.strip()}",
              file=sys.stderr)
        return
    try:
        subprocess.run(["gh", "workflow", "run", "merge-slot.yml"], capture_output=True, text=True,
                       timeout=60, check=True)
    except (subprocess.SubprocessError, OSError):
        print("Предупреждение: workflow merge-slot.yml не запущен — статус на PR обновится при следующем "
              "событии PR или теге", file=sys.stderr)


def cmd_version(args):
    if not args or args[0] not in ("reserve", "release", "list"):
        die("version reserve|release|list (tools/task-board.sh --help)")
    sub, args = args[0], args[1:]
    opts, rest = parse_opts(args, flags=("patch", "json"))
    tags = remote_versions() if sub != "release" else set()
    publish = []  # публикация в GitHub — после записи доски и снятия блокировки
    try:
        _cmd_version(sub, opts, rest, tags, publish)
    finally:
        if publish:
            publish_slot(publish[-1][0])


def _cmd_version(sub, opts, rest, tags, publish):
    as_json = bool(opts.get("json"))
    with Board(True) as data:
        slot = data.get("merge_slot")
        if slot:
            expired = dt.datetime.fromisoformat(slot["expires_at"]) <= dt.datetime.now().astimezone()
            if slot["version"] in tags or expired:
                why = "тег выпущен" if slot["version"] in tags else "срок истёк"
                print(f"Слот #{slot['issue']} ({slot['version']}) снят: {why}",
                      file=sys.stderr if as_json else sys.stdout)
                data.setdefault("merge_slot_log", []).append(dict(slot, closed_at=now(), closed=why))
                data["merge_slot"] = slot = None
                publish.append((None,))
        if sub == "list":
            if as_json:
                print(json.dumps(slot or {}, ensure_ascii=False))
            else:
                print(f"Слот слияния: #{slot['issue']} {slot['version']} до {slot['expires_at']}" if slot
                      else "Слот слияния свободен")
            return
        if not rest:
            die(f"version {sub} <issue>")
        issue = rest[0].lstrip("#")
        if sub == "release":
            if not slot or slot["issue"] != issue:
                die(f"#{issue} не держит слот слияния", 1)
            data.setdefault("merge_slot_log", []).append(dict(slot, closed_at=now(), closed="отдан"))
            data["merge_slot"] = None
            publish.append((None,))
            print(f"#{issue}: слот отдан")
            return
        if slot and slot["issue"] != issue:
            die(f"Слот слияния держит #{slot['issue']} ({slot['version']}) до {slot['expires_at']}: "
                "дождись его тега или договорись с его архитектором", 1)
        if slot:
            publish.append((slot,))  # повтор той же задачей заодно чинит несостоявшуюся публикацию
            print(slot["version"])
            return
        base = opts.get("from")
        if base:
            if base not in tags:
                die(f"Выпуска {base} нет среди тегов origin", 1)
        first = opts.get("first")
        if first and tags:
            die("--first только для первого выпуска: в origin уже есть теги", 1)
        if first:
            if not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", first):
                die("--first: номер вида X.Y.Z.W")
            base, ver = None, first
        elif not tags:
            die("В origin нет тегов выпусков: задай номер первого выпуска --first X.Y.Z.W", 1)
        else:
            base = max(tags, key=vkey)
        if not first:
            ver = bump(base, bool(opts.get("patch")))
        if ver in tags:
            die(f"Номер {ver} уже занят тегом в origin", 1)
        ttl = float(opts.get("ttl", 3))
        expires = (dt.datetime.now().astimezone() + dt.timedelta(hours=ttl)).isoformat(timespec="seconds")
        data["merge_slot"] = {"issue": issue, "version": ver, "base": base, "at": now(), "expires_at": expires}
        if opts.get("branch"):
            data["merge_slot"]["branch"] = opts["branch"]
        publish.append((data["merge_slot"],))
        if issue in data["tasks"]:
            data["tasks"][issue].setdefault("log", []).append({"at": now(), "event": "version",
                                                               "note": f"слот слияния, номер {ver}"})
        print(ver)


def main(argv):
    cmd, args = argv[0], argv[1:]
    handlers = {"list": cmd_list, "set": cmd_set, "inc": cmd_inc, "claim": cmd_claim,
                "release": cmd_release, "card": cmd_card, "scorecard": cmd_scorecard, "usage": cmd_usage,
                "version": cmd_version}
    if cmd == "path":
        print(PATH)
        return
    if cmd not in handlers:
        die(f"Неизвестная команда: {cmd} (tools/task-board.sh --help)")
    handlers[cmd](args)


main(sys.argv[1:])
PY
