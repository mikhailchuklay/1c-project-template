#!/usr/bin/env python3
"""Вспомогательные операции tools/thick-client-check.sh: XWD→PNG, отчёт, самопроверка."""

import hashlib
import json
import pathlib
import re
import shutil
import struct
import sys

from PIL import Image


def xwd_to_png(src, dst):
    data = pathlib.Path(src).read_bytes()
    if len(data) < 100:
        raise ValueError("xwd короче заголовка")
    header_size = struct.unpack_from(">I", data, 0)[0]
    words = struct.unpack_from(">25I", data, 0)
    width, height = words[4], words[5]
    byte_order = words[7]
    bpp = words[11]
    bpl = words[12]
    red_mask, green_mask, blue_mask = words[14], words[15], words[16]
    ncolors = words[19]
    if words[1] != 7 or bpp not in (24, 32) or width < 1 or height < 1:
        raise ValueError("неподдерживаемый xwd: version=%s bpp=%s %sx%s" % (words[1], bpp, width, height))
    offset = header_size + ncolors * 12
    need = bpl * height
    if offset + need > len(data):
        raise ValueError("xwd обрезан: нужно %s байт пикселей, есть %s" % (need, len(data) - offset))
    fmt = "<I" if byte_order == 0 else ">I"
    pixels = bytearray(width * height * 3)
    row = offset
    out = 0
    for _y in range(height):
        col = row
        for _x in range(width):
            pixel = struct.unpack_from(fmt, data, col)[0]
            pixels[out] = (pixel & red_mask) >> _shift(red_mask)
            pixels[out + 1] = (pixel & green_mask) >> _shift(green_mask)
            pixels[out + 2] = (pixel & blue_mask) >> _shift(blue_mask)
            col += 4 if bpp == 32 else 3
            out += 3
        row += bpl
    image = Image.frombytes("RGB", (width, height), bytes(pixels))
    pathlib.Path(dst).parent.mkdir(parents=True, exist_ok=True)
    image.save(dst, "PNG")


def _shift(mask):
    if mask == 0:
        return 0
    shift = 0
    while (mask & 1) == 0:
        mask >>= 1
        shift += 1
    return shift


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_info(path):
    file_path = pathlib.Path(path)
    if not file_path.is_file():
        return {"path": str(file_path), "size": 0, "sha256": "", "missing": True}
    return {
        "path": str(file_path),
        "size": file_path.stat().st_size,
        "sha256": sha256_file(file_path),
        "missing": False,
    }


def _extract_events(path, limit=40):
    file_path = pathlib.Path(path)
    if not file_path.is_file():
        return ""
    text = file_path.read_text(encoding="utf-8", errors="replace")
    levels = re.findall(r"<(?:\w+:)?Level>([^<]*)</(?:\w+:)?Level>", text)
    dates = re.findall(r"<(?:\w+:)?Date>([^<]*)</(?:\w+:)?Date>", text)
    comments = re.findall(r"<(?:\w+:)?Comment>([^<]*)</(?:\w+:)?Comment>", text)
    lines = []
    for index, comment in enumerate(comments[:limit]):
        level = levels[index] if index < len(levels) else ""
        moment = dates[index] if index < len(dates) else ""
        lines.append("%s\t%s\t%s" % (moment, level, comment.strip()))
    if not lines and text.strip():
        return text[:4000]
    return "\n".join(lines)


def _tail(path, lines=40):
    file_path = pathlib.Path(path)
    if not file_path.is_file():
        return ""
    data = file_path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(data[-lines:])


def build_report(run_dir, report_json, report_txt, meta_path):
    run = pathlib.Path(run_dir)
    meta = json.loads(pathlib.Path(meta_path).read_text(encoding="utf-8"))
    processor_path = run / "processor-result.json"
    processor = {}
    if processor_path.is_file():
        processor = json.loads(processor_path.read_text(encoding="utf-8-sig"))
    steps_out = []
    any_fail = False
    for step in processor.get("steps") or []:
        files = []
        for name in step.get("files") or []:
            info = file_info(run / name)
            files.append(info)
            if info["missing"] or info["size"] == 0:
                any_fail = True
                step["status"] = "FAIL"
                extra = "нет файла или он пуст: " + name
                step["error"] = (step.get("error") + "; " + extra).strip("; ") if step.get("error") else extra
        if step.get("status") != "PASS":
            any_fail = True
        steps_out.append({
            "index": step.get("index"),
            "action": step.get("action"),
            "status": step.get("status"),
            "seconds": step.get("seconds"),
            "error": step.get("error") or "",
            "rows": step.get("rows"),
            "nonempty": step.get("nonempty"),
            "pdf_error": step.get("pdf_error") or "",
            "ref": step.get("ref") or "",
            "number": step.get("number") or "",
            "report": step.get("report") or "",
            "layout_key": step.get("layout_key") or "",
            "external_print": step.get("external_print") or "",
            "invoice_ref": step.get("invoice_ref") or "",
            "print_path": step.get("print_path") or "",
            "print_path_note": step.get("print_path_note") or "",
            "call": step.get("call") or "",
            "files": files,
        })
    if processor.get("fatal"):
        any_fail = True
    dialogs = []
    dismissed = run / "dismissed.tsv"
    if dismissed.is_file():
        for line in dismissed.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.strip():
                continue
            parts = line.split("\t")
            title, png = parts[0], parts[1]
            dialog = {"title": title, **file_info(png)}
            if len(parts) > 2 and parts[2]:
                dialog["note"] = parts[2]
            dialogs.append(dialog)
    blocked = ""
    blocked_path = run / "blocked-modal.txt"
    if blocked_path.is_file():
        blocked = blocked_path.read_text(encoding="utf-8", errors="replace").strip()
        any_fail = True
    timeout = (run / "timeout.txt").is_file()
    if timeout:
        any_fail = True
    if not (run / "finished").is_file() and not meta.get("dry_run"):
        any_fail = True
    event_path = run / "event-log.xml"
    event_error = ""
    error_path = run / "event-log-error.txt"
    if error_path.is_file():
        event_error = error_path.read_text(encoding="utf-8", errors="replace").strip()
    verdict = "FAIL" if any_fail else "PASS"
    report = {
        "command": meta.get("command", ""),
        "platform": processor.get("platform") or meta.get("platform", ""),
        "infobase_kind": meta.get("infobase_kind", ""),
        "infobase": meta.get("infobase", ""),
        "user": processor.get("user") or meta.get("user", ""),
        "mode": processor.get("mode", ""),
        "started": processor.get("started") or meta.get("started", ""),
        "finished": meta.get("finished", ""),
        "timeout": timeout,
        "blocked_modal": blocked,
        "process_exit": meta.get("process_exit"),
        "verdict": verdict,
        "fatal": processor.get("fatal") or "",
        "event_log_error": event_error,
        "steps": steps_out,
        "startup_dialogs": dialogs,
        "out_log": str(meta.get("out_log", "")),
        "out_log_tail": _tail(meta.get("out_log", "")),
        "event_log": {
            **file_info(event_path),
            "extract": _extract_events(event_path),
            "error": event_error,
        },
    }
    pathlib.Path(report_json).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    pathlib.Path(report_txt).write_text(_render_txt(report), encoding="utf-8")
    print(verdict)
    return 0 if verdict == "PASS" else 1


def _render_txt(report):
    lines = [
        "Команда: %s" % report["command"],
        "Платформа: %s" % report["platform"],
        "База: %s %s" % (report["infobase_kind"], report["infobase"]),
        "Пользователь: %s" % (report["user"] or "без имени"),
        "Режим запуска: %s" % report["mode"],
        "Начало: %s" % report["started"],
        "Окончание: %s" % report["finished"],
        "Код процесса 1cv8: %s" % report["process_exit"],
        "Итог: %s" % report["verdict"],
    ]
    if report["timeout"]:
        lines.append("Тайм-аут: да, процесс и Xvfb сняты")
    if report["blocked_modal"]:
        lines.append("Неизвестное модальное окно: %s" % report["blocked_modal"])
    if report["fatal"]:
        lines.append("Аварийное завершение обработки: %s" % report["fatal"])
    lines.append("")
    for step in report["steps"]:
        lines.append(
            "Шаг %s %s %s %ss" % (step["index"], step["action"], step["status"], step["seconds"])
        )
        if step["ref"]:
            lines.append("  объект: %s" % step["ref"])
        if step.get("number"):
            lines.append("  номер: %s" % step["number"])
        if step.get("report"):
            lines.append("  отчёт: %s" % step["report"])
        if step["layout_key"]:
            lines.append("  макет: %s" % step["layout_key"])
        if step.get("print_path"):
            lines.append("  путь печати: %s" % step["print_path"])
        if step.get("print_path_note"):
            lines.append("  %s" % step["print_path_note"])
        if step.get("call"):
            lines.append("  вызов: %s" % step["call"])
        if step["external_print"]:
            lines.append("  внешняя печатная форма: %s" % step["external_print"])
        if step["invoice_ref"]:
            lines.append("  счёт-фактура: %s" % step["invoice_ref"])
        if step["rows"] is not None:
            lines.append("  строк: %s; непустой: %s" % (step["rows"], "да" if step["nonempty"] else "нет"))
        if step["pdf_error"]:
            lines.append("  PDF не записан: %s" % step["pdf_error"])
        if step["error"]:
            lines.append("  ошибка: %s" % step["error"])
        for info in step["files"]:
            mark = "ОТСУТСТВУЕТ" if info["missing"] else info["sha256"]
            lines.append("  файл: %s размер=%s sha256=%s" % (info["path"], info["size"], mark))
    if report["startup_dialogs"]:
        lines.append("")
        lines.append("Стартовые окна (белый список, закрыты после снимка):")
        for dialog in report["startup_dialogs"]:
            lines.append("  %s %s sha256=%s %s" % (dialog["title"], dialog["path"], dialog["sha256"], dialog.get("note") or ""))
    lines.append("")
    lines.append("Хвост /Out:")
    lines.append(report["out_log_tail"] or "(пусто)")
    lines.append("")
    lines.append("Журнал регистрации (Ошибка и Предупреждение с начала прогона):")
    if report["event_log_error"]:
        lines.append(report["event_log_error"])
    else:
        info = report["event_log"]
        lines.append("файл: %s размер=%s sha256=%s" % (info["path"], info["size"], info["sha256"]))
        lines.append(info.get("extract") or "(записей нет)")
    lines.append("")
    return "\n".join(lines) + "\n"


def validate_scenario(path):
    data = json.loads(pathlib.Path(path).read_text(encoding="utf-8-sig"))
    steps = data.get("steps")
    if not isinstance(steps, list) or not steps:
        raise ValueError("steps должен быть непустым массивом")
    for index, step in enumerate(steps):
        action = step.get("action")
        if action not in ("print", "report", "open_form", "wait"):
            raise ValueError("шаг %s: неизвестное action %r" % (index, action))
        if action == "print" and not step.get("metadata"):
            raise ValueError("шаг %s: print требует metadata" % index)
        if action == "print" and not step.get("layout") and not step.get("method"):
            raise ValueError("шаг %s: print требует layout или method" % index)
        if action == "report" and not step.get("metadata"):
            raise ValueError("шаг %s: report требует metadata" % index)
        if action == "open_form" and step.get("kind") not in (None, "", "object", "list", "report", "main"):
            raise ValueError("шаг %s: kind открываемой формы не поддерживается" % index)
        if action == "open_form" and step.get("kind") != "main" and not step.get("metadata"):
            raise ValueError("шаг %s: open_form требует metadata" % index)
        if action == "wait" and not isinstance(step.get("seconds"), (int, float)):
            raise ValueError("шаг %s: wait требует seconds" % index)
    return data


def self_test():
    fails = 0
    sample = pathlib.Path(__file__).with_name("example-scenario.json")
    try:
        validate_scenario(sample)
    except Exception as error:
        print("self-test: пример сценария не разобран: %s" % error, file=sys.stderr)
        fails += 1
    raw = _synthetic_xwd()
    src = pathlib.Path("/tmp/thick-client-check-self.xwd")
    dst = pathlib.Path("/tmp/thick-client-check-self.png")
    src.write_bytes(raw)
    try:
        xwd_to_png(src, dst)
        image = Image.open(dst)
        if image.size != (2, 2) or image.getpixel((0, 0)) != (255, 0, 0):
            print("self-test: пиксель XWD разобран неверно: %s %s" % (image.size, image.getpixel((0, 0))), file=sys.stderr)
            fails += 1
    except Exception as error:
        print("self-test: xwd: %s" % error, file=sys.stderr)
        fails += 1
    if fails:
        return 1
    print("self-test: разбор сценария и XWD исправен")
    return 0


def _synthetic_xwd():
    width, height, bpl = 2, 2, 8
    header = [0] * 25
    name = b"xwdump\x00"
    header[0] = 100 + len(name)
    header[1] = 7
    header[2] = 2
    header[3] = 24
    header[4] = width
    header[5] = height
    header[7] = 0
    header[8] = 32
    header[11] = 32
    header[12] = bpl
    header[13] = 4
    header[14] = 0xFF0000
    header[15] = 0x00FF00
    header[16] = 0x0000FF
    header[17] = 8
    header[19] = 0
    header[20] = width
    header[21] = height
    blob = struct.pack(">25I", *header) + name
    # LSB pixel: low byte blue, then green, red. Red pixel = 0x00FF0000 little-endian bytes.
    red = struct.pack("<I", 0x00FF0000)
    black = struct.pack("<I", 0)
    pixels = (red + black) + (black + black)
    return blob + pixels


def metadata_version(platform_build):
    numbers = []
    for part in str(platform_build).split("."):
        if part.isdigit():
            numbers.append(int(part))
        else:
            break
    while len(numbers) < 3:
        numbers.append(0)
    major, minor, patch = numbers[0], numbers[1], numbers[2]
    table = (
        ((8, 3, 27), "2.20"),
        ((8, 3, 24), "2.19"),
        ((8, 3, 23), "2.18"),
        ((8, 3, 21), "2.17"),
        ((8, 3, 20), "2.16"),
        ((8, 3, 18), "2.14"),
        ((8, 3, 17), "2.13"),
        ((8, 3, 16), "2.12"),
        ((8, 3, 15), "2.11"),
        ((8, 3, 14), "2.8"),
        ((8, 3, 13), "2.9"),
        ((8, 3, 12), "2.8"),
        ((8, 3, 11), "2.7"),
        ((8, 3, 10), "2.6"),
    )
    for gate, version in table:
        if (major, minor, patch) >= gate:
            return version
    return "2.6"


def prepare_sources(src_xml, dest_dir, version):
    source = pathlib.Path(src_xml)
    destination = pathlib.Path(dest_dir)
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source.parent / source.stem, destination / source.stem)
    text = source.read_text(encoding="utf-8")
    replaced, count = re.subn(r'(<MetaDataObject\b[^>]*\bversion=")[^"]+"', r"\g<1>" + version + '"', text, count=1)
    if count != 1:
        raise RuntimeError("в корневом XML нет version у MetaDataObject")
    (destination / source.name).write_text(replaced, encoding="utf-8")
    for xml in (destination / source.stem).rglob("*.xml"):
        body = xml.read_text(encoding="utf-8")
        body = re.sub(r'(<MetaDataObject\b[^>]*\bversion=")[^"]+"', r"\g<1>" + version + '"', body, count=1)
        xml.write_text(body, encoding="utf-8")


def snap_shell(path):
    import shlex

    data = json.loads(pathlib.Path(path).read_text(encoding="utf-8-sig"))
    print("SNAP_STEP=%s" % shlex.quote(str(data["step"])))
    print("SNAP_MODE=%s" % shlex.quote(str(data["mode"])))
    print("SNAP_TITLE=%s" % shlex.quote(str(data.get("title") or "")))
    print("SNAP_PNG=%s" % shlex.quote(str(data["png"])))


_FORM_NAME = bytes.fromhex("000000000000000000000000000000000000000066006f0072006d0000000000")
_MODULE_NAME = bytes.fromhex("00000000000000000000000000000000000000006d006f00640075006c00650000000000")
_LAYOUT = """{27,
{16,
{
{1,0},1,4294967295},
{09ccdc77-ea1a-4a6d-ab1c-3435eada2433,
{1,
{
{10,1,
{3,4,
{0}
},
{3,4,
{0}
},
{6,3,0,1},0,
{3,3,
{-22}
},
{3,4,
{0}
},
{3,4,
{0}
},
{3,3,
{-7}
},
{3,3,
{-21}
},
{3,0,
{0},0,0,0,48312c09-257f-4b29-b280-284dd89efc1e},
{1,0}
},21,0,0,0,0,0,0,
{3,1,
{3,0,
{0},"",-1,-1,1,0}
},0,1,
{1,1,
{3,
{1,1,
{"ru","Страница1"}
},
{3,0,
{3,0,
{0},"",-1,-1,1,0}
},-1,1,1,"Страница1",1}
},1,1,0,4,
{2,8,1,1,1,0,0,0,0},
{2,8,0,1,2,0,0,0,0},
{2,14,1,1,3,0,0,8,0},
{2,14,0,1,4,0,0,8,0},0,4294967295,5,64,0},
{0}
},
{0}
},22,22,1,1,1,4,4,10},
{
{-1},1,
{0},
{0}
},
{f3e3cfa0-1ae3-11d6-a3c7-0050bae0a776,0},
{1,
{70001,e1692cc2-605b-4535-84dd-28440238746c,
{3,"ПриОткрытии",
{1,"ПриОткрытии",
{1,1,
{"ru","При открытии"}
},
{1,1,
{"ru","При открытии"}
},
{1,1,
{"ru","При открытии"}
},
{3,0,
{0},"",-1,-1,1,0},
{0,0,0}
}
}
}
},1,4,1,0,0,0,
{0},
{0},
{3,0,
{3,0,
{0},"",-1,-1,1,0}
},1,2,0,0,0,1}"""


def _block(payload):
    line = ("%08x %08x 7fffffff \r\n" % (len(payload), len(payload))).encode("ascii")
    return b"\r\n" + line + payload


def write_ordinary_form(module_path, output_path):
    module = pathlib.Path(module_path).read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    if module.startswith(b"\xef\xbb\xbf"):
        module_body = module
    else:
        module_body = b"\xef\xbb\xbf" + module
    layout = _LAYOUT.replace("\n", "\r\n").encode("utf-8")
    layout_body = b"\xef\xbb\xbf" + layout
    # Каталог указывает на блоки имён. Его размер фиксирован, смещения считаются после сборки.
    catalog_payload = b"\x00" * 0x200
    catalog = _block(catalog_payload)
    # В строке каталога занято 24 байта, остальное — выравнивание. Длина блока от этого не меняется:
    # _block пишет used=len(payload). Платформа читает used байт. Нужно used=0x18, alloc=0x200.
    catalog = b"\r\n" + b"00000018 00000200 7fffffff \r\n" + catalog_payload
    form_name = _block(_FORM_NAME)
    form_body = _block(layout_body)
    module_name = _block(_MODULE_NAME)
    module_bin = _block(module_body)
    header = b"\xff\xff\xff\x7f\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    body = catalog + form_name + form_body + module_name + module_bin
    base = len(header)
    form_at = base + len(catalog)
    module_at = form_at + len(form_name) + len(form_body)
    catalog_bytes = struct.pack(
        "<6I",
        form_at,
        form_at + len(form_name),
        0x7FFFFFFF,
        module_at,
        module_at + len(module_name),
        0x7FFFFFFF,
    )
    body = catalog[: len(catalog) - 0x200] + catalog_bytes + (b"\x00" * (0x200 - len(catalog_bytes))) + body[len(catalog):]
    out = pathlib.Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(header + body)


def main(argv):
    if len(argv) < 2:
        print("host.py: xwd-to-png | build-report | validate-scenario | --self-test", file=sys.stderr)
        return 2
    command = argv[1]
    if command == "--self-test":
        return self_test()
    if command == "xwd-to-png":
        xwd_to_png(argv[2], argv[3])
        return 0
    if command == "validate-scenario":
        validate_scenario(argv[2])
        print("сценарий разобран: %s" % argv[2])
        return 0
    if command == "write-ordinary-form":
        write_ordinary_form(argv[2], argv[3])
        return 0
    if command == "metadata-version":
        print(metadata_version(argv[2]))
        return 0
    if command == "prepare-sources":
        prepare_sources(argv[2], argv[3], argv[4])
        return 0
    if command == "snap-shell":
        snap_shell(argv[2])
        return 0
    if command == "build-report":
        return build_report(argv[2], argv[3], argv[4], argv[5])
    print("host.py: неизвестная команда %s" % command, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
