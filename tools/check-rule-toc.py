#!/usr/bin/env python3
"""Проверка оглавлений длинных правил (.cursor/rules/*.mdc).

Оглавление — таблица в цитате `> | Line | Section | Read when |`. Агент читает правило с offset из
колонки Line, поэтому номер строки обязан указывать на заголовок раздела. После правки правила:
    python3 tools/check-rule-toc.py --fix
Без --fix скрипт только проверяет и завершается с кодом 1 при расхождении.
"""
import pathlib, re, sys

ROW = re.compile(r'^> \| (\d+) \| (.+?) \| (.+) \|$')


def heading_text(line):
    return line.lstrip('#').strip() if line.startswith('#') else None


def main(fix):
    bad = 0
    for path in sorted(pathlib.Path('.cursor/rules').glob('*.mdc')):
        lines = path.read_text(encoding='utf-8').split('\n')
        if not any(l.startswith('> | Line | Section |') for l in lines):
            continue
        headings = {}
        for i, l in enumerate(lines):
            t = heading_text(l)
            if t is not None:
                headings.setdefault(t, i + 1)
        changed = False
        for i, l in enumerate(lines):
            m = ROW.match(l)
            if not m:
                continue
            num, sec = int(m.group(1)), m.group(2).strip()
            want = headings.get(sec)
            if want is None:
                print(f'{path}: нет заголовка «{sec}»'); bad += 1
            elif want != num:
                if fix:
                    lines[i] = f'> | {want} | {m.group(2)} | {m.group(3)} |'; changed = True
                else:
                    print(f'{path}: «{sec}» на строке {want}, в оглавлении {num}'); bad += 1
        if changed:
            path.write_text('\n'.join(lines), encoding='utf-8'); print(f'{path}: оглавление обновлено')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main('--fix' in sys.argv[1:]))
