#!/usr/bin/env python3
"""Локальная распаковка и сборка обычной формы 1С (`Ext/Form.bin`) через пакет v8unpack.

Тот же контракт `ordinary-form/1`, что у MCP-инструментов `unpack_ordinary_form` /
`build_ordinary_form` (см. `.cursor/skills/v8unpack-cf/docs/ordinary-forms.md`), для
проектов без MCP индекса кода и для файлов, которых сервер не видит.

    python3 tools/ordinary-form.py unpack <Form.bin> <workspace> [--overwrite] [--include ...]
    python3 tools/ordinary-form.py build <workspace> <Form.bin> [--overwrite] [--verify | --no-verify]

Результат — JSON в stdout. Код возврата: 0 — успех (у сборки с проверкой — только при
`verification.status == "match"`), 1 — отказ (`status="error"`, `error_code`, `hint`),
2 — ошибка аргументов.

Рабочий каталог:
    ordinary-form.json   манифест (генерируется, руками не править)
    payload/<запись>     записи контейнера как есть (без сжатия)   <- источник истины
    decoded/form.json    скобочное дерево формы как JSON            <- производное, только чтение
    decoded/module.bsl   модуль формы                               <- производное, только чтение

Сборка пишет каждую запись без сжатия (Deflate ломает обычную форму: «Ошибка формата
потока»), записи-контейнеры кладёт целиком, как есть (`nested=True`-семантика v8unpack),
сохраняет порядок записей источника и заменяет выходной файл только после проверки.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
import zlib

CONTRACT = "ordinary-form/1"
TOOL = "tools/ordinary-form.py"
TOOL_VERSION = "1.0.0"
MANIFEST = "ordinary-form.json"
PAYLOAD_DIR = "payload"
DECODED_DIR = "decoded"
INSTALL_HINT = 'pip install "v8unpack>=1.2.6,<2"'
CONTAINER_MARK = b"\xff\xff\xff\x7f"
CONTAINER64_MARK = b"\xff" * 8
BOM = b"\xef\xbb\xbf"


class FormError(Exception):
    def __init__(self, code: str, message: str, hint: str = ""):
        super().__init__(message)
        self.code = code
        self.message = message
        self.hint = hint


# --------------------------------------------------------------------------- v8unpack


def _v8():
    try:
        import v8unpack  # noqa: F401
        from v8unpack import container as container_mod
        from v8unpack.container_doc import Document
        from v8unpack.json_container_decoder import JsonContainerDecoder
    except Exception as err:  # ImportError, а также сломанная установка
        raise FormError(
            "dependency_missing",
            f"Пакет v8unpack недоступен: {err}",
            f"Установите {INSTALL_HINT} (в образе onec-agent он есть); проверка: "
            'python3 -c "import v8unpack"',
        )
    return container_mod, Document, JsonContainerDecoder


def _v8_version() -> str:
    try:
        from importlib.metadata import version

        return version("v8unpack")
    except Exception:
        return "unknown"


# --------------------------------------------------------------------------- helpers


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _file_info(path: str) -> dict:
    with open(path, "rb") as f:
        data = f.read()
    return {"path": os.path.abspath(path), "size": len(data), "sha256": _sha256(data)}


def _read_container(path: str):
    """Читает контейнер Form.bin. Возвращает (формат, [(имя, байты)])."""
    container_mod, _, _ = _v8()
    with open(path, "rb") as f:
        head = f.read(8)
        f.seek(0, os.SEEK_END)
        total = f.tell()
        if head[:4] == CONTAINER_MARK:
            cont, fmt = container_mod.Container(), "container32"
        elif head == CONTAINER64_MARK:
            cont, fmt = container_mod.Container64(), "container64"
        else:
            raise FormError(
                "not_a_container",
                f"{path} не является контейнером 1С (сигнатура {head[:4].hex()})",
                "Ожидается Ext/Form.bin обычной формы. Управляемая форма — Ext/Form.xml, "
                "её правят как XML (навык 1c-metadata-manage).",
            )
        try:
            cont.read(f, 0)
            entries = [(name, b"".join(fo.data)) for name, fo in cont.files.items()]
        except FormError:
            raise
        except Exception as err:
            raise FormError("unpack_failed", f"Не удалось прочитать контейнер {path}: {err}",
                            "Файл повреждён или это не Form.bin.")
        # Несколько контейнеров подряд — это целый CF/CFE/EPF, а не форма.
        # Container.size у v8unpack приблизителен, поэтому конец считаем по цепочкам блоков.
        end = _container_end(f, cont)
        if 0 < end < total:
            f.seek(end)
            nxt = f.read(8)
            if nxt[:4] == CONTAINER_MARK or nxt == CONTAINER64_MARK:
                raise FormError(
                    "unsupported_container_layout",
                    f"{path} содержит больше одного контейнера — это целый CF/CFE/EPF, не обычная форма",
                    "Целые бинарники распаковывает CLI v8unpack (-E/-B), см. v8unpack-cf/docs/whole-binaries.md.",
                )
    if not entries:
        raise FormError("unsupported_container_layout", f"{path}: пустой контейнер", "")
    return fmt, entries


def _doc_end(f, cont, offset: int) -> int:
    """Конец документа контейнера: максимум по его блокам (заголовок + размер блока)."""
    from struct import unpack as _unpack

    end, seen = 0, set()
    while offset != cont.end_marker and offset not in seen:
        seen.add(offset)
        f.seek(offset)
        buf = f.read(cont.block_header_size)
        if len(buf) < cont.block_header_size:
            break
        head = _unpack(cont.block_header_fmt, buf)
        try:
            block_size, nxt = int(head[3], 16), int(head[5], 16)
        except ValueError:
            break
        end = max(end, offset + cont.block_header_size + block_size)
        offset = nxt
    return end


def _container_end(f, cont) -> int:
    from struct import pack as _pack, unpack as _unpack

    _, Document, _ = _v8()
    end = _doc_end(f, cont, cont.header_size)
    toc = Document(cont).read(f, cont.header_size, cont.index_block_size)
    for item in toc.split(_pack(cont.index_fmt, cont.end_marker))[:-1]:
        try:
            attr_off, data_off = _unpack(f"2{cont.index_fmt}", item)
        except Exception:
            continue
        end = max(end, _doc_end(f, cont, attr_off), _doc_end(f, cont, data_off))
    return end


def _classify(name: str, raw: bytes):
    """Возвращает (payload, kind, encoding, deflated)."""
    deflated = False
    data = raw
    if not (data.startswith(CONTAINER_MARK) or data.startswith(BOM) or _is_utf8(data)):
        try:
            unpacked = zlib.decompress(data, -15)
        except zlib.error:
            unpacked = None
        if unpacked is not None:
            data, deflated = unpacked, True
    if data.startswith(CONTAINER_MARK) or data.startswith(CONTAINER64_MARK):
        return data, "container", "binary", deflated
    if data.startswith(BOM) and _is_utf8(data[3:]):
        encoding = "utf-8-bom"
        text = data[3:].decode("utf-8")
    elif _is_utf8(data):
        encoding = "utf-8"
        text = data.decode("utf-8")
    else:
        return data, "binary", "binary", deflated
    if name == "module":
        kind = "bsl_module"
    elif text.lstrip().startswith("{"):
        kind = "brace_tree"
    else:
        kind = "text"
    return data, kind, encoding, deflated


def _is_utf8(data: bytes) -> bool:
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def _text(data: bytes) -> str:
    if data.startswith(BOM):
        data = data[3:]
    return data.decode("utf-8")


def _decode_brace(data: bytes):
    _, _, Decoder = _v8()
    decoder = Decoder(src_dir="", file_name="form")
    return decoder.decode_file(io.StringIO(_text(data), newline=""))


def _safe_name(name: str) -> str:
    if not name or name in (".", "..") or "/" in name or "\\" in name or "\x00" in name:
        raise FormError("unsupported_container_layout", f"Недопустимое имя записи контейнера: {name!r}", "")
    return name


def _load_manifest(workspace: str) -> dict:
    path = os.path.join(workspace, MANIFEST)
    if not os.path.isdir(workspace):
        raise FormError("path_not_found", f"Нет рабочего каталога {workspace}", "Сначала выполните unpack.")
    if not os.path.isfile(path):
        raise FormError("manifest_missing", f"В {workspace} нет {MANIFEST}",
                        "Это не рабочий каталог ordinary-form: распакуйте форму заново (unpack).")
    try:
        with open(path, encoding="utf-8") as f:
            manifest = json.load(f)
    except Exception as err:
        raise FormError("manifest_invalid", f"{MANIFEST} не читается: {err}", "Распакуйте форму заново.")
    if manifest.get("contract") != CONTRACT or not isinstance(manifest.get("entries"), list):
        raise FormError("manifest_invalid", f"{MANIFEST} не контракта {CONTRACT}", "Распакуйте форму заново.")
    return manifest


def _prepare_workspace(workspace: str, overwrite: bool) -> None:
    if os.path.exists(workspace) and not os.path.isdir(workspace):
        raise FormError("workspace_invalid", f"{workspace} существует и не каталог", "Укажите другой путь.")
    if os.path.isdir(workspace) and os.listdir(workspace):
        manifest_path = os.path.join(workspace, MANIFEST)
        ours = False
        if os.path.isfile(manifest_path):
            try:
                with open(manifest_path, encoding="utf-8") as f:
                    ours = json.load(f).get("contract") == CONTRACT
            except Exception:
                ours = False
        if not ours:
            raise FormError("workspace_not_empty",
                            f"{workspace} не пуст и записан не этим инструментом — не трогаю",
                            "Укажите новый или пустой каталог.")
        if not overwrite:
            raise FormError("workspace_exists", f"Рабочий каталог {workspace} уже есть",
                            "Добавьте --overwrite, чтобы распаковать заново (правки в payload/ пропадут).")
        shutil.rmtree(workspace)
    os.makedirs(os.path.join(workspace, PAYLOAD_DIR), exist_ok=True)
    os.makedirs(os.path.join(workspace, DECODED_DIR), exist_ok=True)


def _clip(text: str, limit: int):
    return (text, False) if len(text) <= limit else (text[:limit], True)


# --------------------------------------------------------------------------- unpack


def unpack(form_path: str, workspace: str, overwrite: bool = False,
           include: str = "summary", max_chars: int = 4000) -> dict:
    if not form_path:
        raise FormError("path_invalid", "Не указан путь к Form.bin", "")
    if not os.path.exists(form_path):
        raise FormError("path_not_found", f"Нет файла {form_path}", "Проверьте путь (кириллица — в кавычках).")
    if not os.path.isfile(form_path):
        raise FormError("not_a_file", f"{form_path} — не файл", "Нужен путь к .../Forms/<Форма>/Ext/Form.bin.")
    fmt, raw_entries = _read_container(form_path)
    for name, _ in raw_entries:  # до создания каталога: отказ не оставляет недописанный workspace
        _safe_name(name)
    workspace = os.path.abspath(workspace)
    _prepare_workspace(workspace, overwrite)

    entries, warnings, notes = [], [], []
    structure = module_text = None
    for name, raw in raw_entries:
        name = _safe_name(name)
        payload, kind, encoding, deflated = _classify(name, raw)
        rel = f"{PAYLOAD_DIR}/{name}"
        with open(os.path.join(workspace, rel), "wb") as f:
            f.write(payload)
        entry = {
            "name": name,
            "kind": kind,
            "size": len(payload),
            "sha256": _sha256(payload),
            "encoding": encoding,
            "deflated": deflated,
            "path": rel,
            "decoded_path": None,
            "decoded_sha256": None,
        }
        if deflated:
            warnings.append(f"Запись {name!r} в источнике сжата Deflate; сборка запишет её без сжатия, "
                            "как пишет Конфигуратор.")
        decoded = None
        if kind == "brace_tree":
            try:
                tree = _decode_brace(payload)
                decoded = ("form.json" if name == "form" else f"{name}.json",
                           json.dumps(tree, ensure_ascii=False, indent=2).encode("utf-8"))
                if name == "form":
                    structure = decoded[1].decode("utf-8")
            except Exception as err:
                warnings.append(f"Скобочное дерево {name!r} не разобрано в JSON ({type(err).__name__}: {err}); "
                                f"читайте и правьте payload/{name}.")
        elif kind == "bsl_module":
            decoded = ("module.bsl" if name == "module" else f"{name}.bsl", payload)
            module_text = _text(payload)
        if decoded:
            drel = f"{DECODED_DIR}/{decoded[0]}"
            with open(os.path.join(workspace, drel), "wb") as f:
                f.write(decoded[1])
            entry["decoded_path"] = drel
            entry["decoded_sha256"] = _sha256(decoded[1])
        entries.append(entry)

    names = [e["name"] for e in entries]
    if names != ["form", "module"]:
        notes.append(f"Состав записей {names} отличается от эталонного ['form', 'module']; "
                     "записи сохранены как есть.")
    source = _file_info(form_path)
    manifest = {
        "contract": CONTRACT,
        "tool": TOOL,
        "tool_version": TOOL_VERSION,
        "v8unpack_version": _v8_version(),
        "created_at": _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds"),
        "source": source,
        "container": {"format": fmt, "entries": len(entries)},
        "entries": entries,
    }
    with open(os.path.join(workspace, MANIFEST), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    result = {
        "status": "ok",
        "contract": CONTRACT,
        "tool": "unpack_ordinary_form",
        "workspace_path": workspace,
        "manifest_path": os.path.join(workspace, MANIFEST),
        "source": source,
        "container": manifest["container"],
        "entries": entries,
        "entries_truncated": False,
        "notes": notes + ["Правьте payload/ (UTF-8 BOM и CRLF сохранять); decoded/ — только чтение."],
        "warnings": warnings,
    }
    if include in ("structure", "all") and structure is not None:
        result["structure"], result["structure_truncated"] = _clip(structure, max_chars)
    if include in ("module", "all") and module_text is not None:
        result["module_text"], result["module_truncated"] = _clip(module_text, max_chars)
    return result


# --------------------------------------------------------------------------- build


def _write_container(fmt: str, entries, out_file) -> None:
    """Пишет контейнер: записи без сжатия, в заданном порядке (как Container.build(nested=True))."""
    container_mod, _, _ = _v8()
    cont = container_mod.Container64() if fmt == "container64" else container_mod.Container()
    cont.file = out_file
    cont.offset = 0
    cont.toc = []
    cont.write_header(len(entries))
    for name, path in entries:
        with open(path, "rb") as fd:
            cont.add_file(fd, name, inflate=False)
    cont.write_table_off_content()


def build(workspace: str, output_path: str, overwrite: bool = False, verify: bool = True) -> dict:
    workspace = os.path.abspath(workspace)
    manifest = _load_manifest(workspace)
    if not output_path:
        raise FormError("path_invalid", "Не указан путь к выходному Form.bin", "")
    output_path = os.path.abspath(output_path)
    if os.path.isdir(output_path):
        raise FormError("not_a_file", f"{output_path} — каталог", "Укажите путь к файлу Form.bin.")
    if os.path.exists(output_path) and not overwrite:
        raise FormError("output_exists", f"{output_path} уже существует",
                        "Добавьте --overwrite, чтобы заменить его (замена — только после проверки).")
    out_dir = os.path.dirname(output_path)
    if not os.path.isdir(out_dir):
        raise FormError("path_not_found", f"Нет каталога {out_dir}", "")

    plan, expected, changed, notes = [], [], [], []
    for e in manifest["entries"]:
        name = _safe_name(e.get("name", ""))
        ppath = os.path.join(workspace, e.get("path") or f"{PAYLOAD_DIR}/{name}")
        if not os.path.isfile(ppath):
            raise FormError("payload_missing", f"Нет записи payload/{name}",
                            "Не удаляйте файлы payload/; распакуйте форму заново.")
        if e.get("decoded_path"):
            dpath = os.path.join(workspace, e["decoded_path"])
            if os.path.isfile(dpath):
                with open(dpath, "rb") as f:
                    if _sha256(f.read()) != e.get("decoded_sha256"):
                        raise FormError(
                            "derived_edit_detected",
                            f"Изменён производный файл {e['decoded_path']} — он не читается при сборке",
                            f"Перенесите правку в payload/{name} и верните {e['decoded_path']} "
                            "(или распакуйте заново).",
                        )
        with open(ppath, "rb") as f:
            data = f.read()
        if name in ("form", "module") and not data.startswith(BOM):
            notes.append(f"payload/{name} без UTF-8 BOM: Конфигуратор пишет записи формы с BOM.")
        expected.append({"name": name, "size": len(data), "sha256": _sha256(data)})
        if _sha256(data) != e.get("sha256"):
            changed.append(name)
        if e.get("deflated"):
            notes.append(f"Запись {name!r} в источнике была сжата; записана без сжатия.")
        plan.append((name, ppath))

    fd, tmp_path = tempfile.mkstemp(prefix=".ordinary-form-", suffix=".bin", dir=out_dir)
    try:
        with os.fdopen(fd, "w+b") as out:
            _write_container(manifest.get("container", {}).get("format", "container32"), plan, out)
    except FormError:
        os.unlink(tmp_path)
        raise
    except Exception as err:
        os.unlink(tmp_path)
        raise FormError("build_failed", f"Сборка не удалась: {err}", "")

    verification = {"status": "skipped", "entries": []}
    if verify:
        try:
            _, got = _read_container(tmp_path)
        except FormError as err:
            os.unlink(tmp_path)
            raise FormError("verify_failed", f"Собранный файл не читается: {err.message}", err.hint)
        got_list = [{"name": n, "size": len(d), "sha256": _sha256(d)} for n, d in got]
        rows, ok = [], len(got_list) == len(expected)
        for i, exp in enumerate(expected):
            act = got_list[i] if i < len(got_list) else None
            same = act is not None and act == exp
            ok = ok and same
            rows.append({"name": exp["name"], "expected_size": exp["size"], "expected_sha256": exp["sha256"],
                         "actual_size": act and act["size"], "actual_sha256": act and act["sha256"],
                         "actual_name": act and act["name"], "match": same})
        verification = {"status": "match" if ok else "mismatch", "entries": rows}
        if not ok:
            os.unlink(tmp_path)
            return {
                "status": "error",
                "error_code": "verify_failed",
                "hint": "Собранный контейнер не совпал с payload/ по записям; выходной файл не тронут.",
                "contract": CONTRACT,
                "tool": "build_ordinary_form",
                "workspace_path": workspace,
                "output_path": output_path,
                "verified": False,
                "verification": verification,
            }
    # mkstemp создаёт файл 0600: сохраняем права заменяемого файла, новому — обычные по umask.
    if os.path.exists(output_path):
        mode = os.stat(output_path).st_mode & 0o7777
    else:
        umask = os.umask(0)
        os.umask(umask)
        mode = 0o666 & ~umask
    os.chmod(tmp_path, mode)
    os.replace(tmp_path, output_path)
    output = _file_info(output_path)
    source = manifest.get("source", {})
    return {
        "status": "ok",
        "contract": CONTRACT,
        "tool": "build_ordinary_form",
        "workspace_path": workspace,
        "output_path": output_path,
        "output": output,
        "source": source,
        "binary_identical": output["sha256"] == source.get("sha256"),
        "verified": verification["status"] == "match",
        "verification": verification,
        "changed_entries": changed,
        "notes": notes + ["binary_identical=false при verification=match — норма: v8unpack ставит текущее "
                          "время в записях контейнера."],
    }


# --------------------------------------------------------------------------- CLI


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Обычная форма 1С (Form.bin): распаковка и сборка через v8unpack")
    sub = p.add_subparsers(dest="cmd", required=True)
    u = sub.add_parser("unpack", help="Form.bin -> рабочий каталог")
    u.add_argument("form_path")
    u.add_argument("workspace_path")
    u.add_argument("--overwrite", action="store_true")
    u.add_argument("--include", choices=["summary", "structure", "module", "all"], default="summary")
    u.add_argument("--max-chars", type=int, default=4000)
    b = sub.add_parser("build", help="рабочий каталог -> Form.bin")
    b.add_argument("workspace_path")
    b.add_argument("output_path")
    b.add_argument("--overwrite", action="store_true")
    g = b.add_mutually_exclusive_group()
    g.add_argument("--verify", dest="verify", action="store_true", default=True,
                   help="перечитать результат и сравнить записи (по умолчанию)")
    g.add_argument("--no-verify", dest="verify", action="store_false")
    args = p.parse_args(argv)
    try:
        if args.cmd == "unpack":
            res = unpack(args.form_path, args.workspace_path, args.overwrite, args.include,
                         max(1, min(args.max_chars, 20000)))
        else:
            res = build(args.workspace_path, args.output_path, args.overwrite, args.verify)
    except FormError as err:
        res = {"status": "error", "contract": CONTRACT,
               "tool": "unpack_ordinary_form" if args.cmd == "unpack" else "build_ordinary_form",
               "error_code": err.code, "message": err.message, "hint": err.hint}
    json.dump(res, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    if res.get("status") != "ok":
        return 1
    if args.cmd == "build" and args.verify and res["verification"]["status"] != "match":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
