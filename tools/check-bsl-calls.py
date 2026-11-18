#!/usr/bin/env python3
"""Быстрая статическая проверка вызовов BSL в исходниках расширения или конфигурации (секунды, без Конфигуратора).

Находит три класса дефектов, которые иначе ловит только синтаксический контроль платформы:
  UNDEFINED   вызов метода без префикса, которого нет ни в модуле, ни в глобальном контексте платформы;
  NOMETHOD    вызов ОбщийМодуль.Метод(), где модуль есть в исходниках, а метода в нём нет;
  NOTEXPORT   то же, но метод есть и не экспортный.
Вызовы модулей вне дерева (типовая конфигурация, БСП) не проверяются — их проверяет /CheckModules -Extension.

Запуск: python3 -I tools/check-bsl-calls.py src/cfe/<ИмяРасширения> [--globals tools/lists/bsl-global-names.txt]
Код возврата: 0 — дефектов нет, 1 — есть (по строке на находку), 2 — ошибка запуска.
Неизвестное имя глобального метода платформы (ложное UNDEFINED) добавь строкой в файл --globals.
"""
import argparse
import pathlib
import re
import sys

NAME = r"[\wА-Яа-яЁё]+"
DEF_RE = re.compile(r"^\s*(?:Асинх\s+)?(?:Процедура|Функция)\s+(" + NAME + r")\s*\([^)]*\)\s*(Экспорт)?", re.I | re.M)
QUALIFIED_RE = re.compile(r"(?<![\w.А-Яа-яЁё])(" + NAME + r")\s*\.\s*(" + NAME + r")\s*\(")
BARE_RE = re.compile(r"(?<![\w.А-Яа-яЁё&~])(" + NAME + r")\s*\(")
KEYWORDS = {"если", "иначеесли", "пока", "для", "возврат", "новый", "не", "и", "или", "вызватьисключение", "ждать",
            "процедура", "функция", "if", "elsif", "while", "for", "return", "new", "not", "and", "or", "raise", "await"}
NEW_RE = re.compile(r"(?:Новый|New)\s+$", re.I)


def strip_code(text):
    """Убирает комментарии, строковые литералы и продолжения строк запроса, сохраняя номера строк."""
    out = []
    for line in text.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("|") or stripped.startswith("//"):
            out.append("")
            continue
        line = re.sub(r'"[^"\n]*("|$)', '""', line)
        out.append(line.split("//")[0])
    return "\n".join(out)


def load_globals(path):
    names = set()
    if path and path.exists():
        for raw in path.read_text(encoding="utf-8-sig").splitlines():
            raw = raw.split("#")[0].strip()
            if raw:
                names.add(raw.lower())
    return names


def main():
    here = pathlib.Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description="Статическая проверка вызовов BSL")
    ap.add_argument("root", type=pathlib.Path)
    ap.add_argument("--globals", type=pathlib.Path, default=here / "lists" / "bsl-global-names.txt")
    args = ap.parse_args()
    if not args.root.is_dir():
        print(f"нет каталога {args.root}", file=sys.stderr)
        return 2
    global_names = load_globals(args.globals)
    if not global_names:
        print(f"пустой список глобальных имён {args.globals}", file=sys.stderr)
        return 2

    files = {f: f.read_text(encoding="utf-8-sig") for f in sorted(args.root.rglob("*.bsl"))}
    modules = {}
    for path, text in files.items():
        parts = path.parts
        if "CommonModules" in parts:
            name = parts[parts.index("CommonModules") + 1].lower()
            modules[name] = {m.group(1).lower(): bool(m.group(2)) for m in DEF_RE.finditer(text)}
            # Экспортные методы глобального общего модуля (<Global>true</Global> в описании
            # CommonModules/<Имя>.xml) вызываются без префикса — это не UNDEFINED.
            desc = pathlib.Path(*parts[:parts.index("CommonModules") + 1]) / (parts[parts.index("CommonModules") + 1] + ".xml")
            if desc.exists() and re.search(r"<Global>\s*true\s*</Global>", desc.read_text(encoding="utf-8-sig", errors="replace"), re.I):
                global_names.update(n for n, exported in modules[name].items() if exported)

    findings = []
    for path, text in files.items():
        local = {m.group(1).lower() for m in DEF_RE.finditer(text)}
        code = strip_code(text)
        rel = path.relative_to(args.root)
        for m in QUALIFIED_RE.finditer(code):
            module, method = m.group(1).lower(), m.group(2).lower()
            if module in modules:
                line = code.count("\n", 0, m.start()) + 1
                if method not in modules[module]:
                    findings.append(f"NOMETHOD  {rel}:{line} {m.group(1)}.{m.group(2)}")
                elif not modules[module][method]:
                    findings.append(f"NOTEXPORT {rel}:{line} {m.group(1)}.{m.group(2)}")
        for m in BARE_RE.finditer(code):
            name = m.group(1).lower()
            if name in KEYWORDS or name in local or name in global_names:
                continue
            if NEW_RE.search(code[max(0, m.start() - 12):m.start()]):
                continue
            line = code.count("\n", 0, m.start()) + 1
            if DEF_RE.match(code.split("\n")[line - 1]):
                continue
            findings.append(f"UNDEFINED {rel}:{line} {m.group(1)}")

    for item in findings:
        print(item)
    print(f"файлов: {len(files)}, находок: {len(findings)}", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
