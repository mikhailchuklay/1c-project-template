"""Юнит-тесты tools/ordinary-form.py (нужен пакет v8unpack).

    python3 -m unittest discover -s tools/tests -p "test_ordinary_form.py" -v

Синтетические обычные формы собираются тут же, бинарников в репозитории нет.
Реальные формы: ORDINARY_FORM_SAMPLES=<каталог> — пройти туда и обратно первые
ORDINARY_FORM_SAMPLES_LIMIT (по умолчанию 3) файлов `**/Ext/Form.bin`; файлы только читаются.
"""

import glob
import hashlib
import importlib.util
import io
import json
import os
import shutil
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(os.path.dirname(HERE), "ordinary-form.py")

spec = importlib.util.spec_from_file_location("ordinary_form", SCRIPT)
of = importlib.util.module_from_spec(spec)
spec.loader.exec_module(of)

try:
    from v8unpack.container import Container
    from v8unpack.container_doc import Document

    HAVE_V8 = True
except ImportError:  # pragma: no cover
    HAVE_V8 = False

BOM = b"\xef\xbb\xbf"

FORM_TREE = (
    "{27,\r\n{18,\r\n{\r\n{1,1,\r\n{\"ru\",\"Форма списка «Товары»\"}\r\n},7,4294967295},\r\n"
    "{0,\r\n{\"Многострочная\r\nстрока \"\"в кавычках\"\"\"}\r\n},\r\n"
    "{#base64:AAECAwQFBgc=}\r\n}\r\n}"
)
MODULE = (
    "&НаКлиенте\r\nПроцедура ПриОткрытии()\r\n\tСообщить(\"Привет, мир\");\r\n"
    "КонецПроцедуры\r\n"
)


def _sha(b):
    return hashlib.sha256(b).hexdigest()


def rb(path):
    with open(path, "rb") as f:
        return f.read()


def wb(path, data):
    with open(path, "wb") as f:
        f.write(data)


def write_container(path, entries, compress=()):
    """entries: [(имя, байты)]; имена из compress пишутся Deflate (как в «оптимизированных» файлах)."""
    with open(path, "wb") as f:
        c = Container()
        c.file, c.offset, c.toc = f, 0, []
        c.write_header(len(entries))
        for name, data in entries:
            attr = Document(c).write_header(io.BytesIO(data), name)
            body = zlib.compress(data, 9)[2:-4] if name in compress else data
            off = Document(c).write(io.BytesIO(body), min_block_size=c.default_block_size)
            c.toc.append((attr, off))
        c.write_table_off_content()


def container_bytes(entries):
    fd, p = tempfile.mkstemp()
    os.close(fd)
    try:
        write_container(p, entries)
        with open(p, "rb") as f:
            return f.read()
    finally:
        os.unlink(p)


def read_entries(path):
    _, entries = of._read_container(path)
    return entries


@unittest.skipUnless(HAVE_V8, "v8unpack не установлен")
class OrdinaryFormTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="ordinary-form-test-")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def p(self, *parts):
        return os.path.join(self.tmp, *parts)

    def make_form(self, name="Form.bin", entries=None, compress=()):
        if entries is None:
            entries = [("form", BOM + FORM_TREE.encode()), ("module", BOM + MODULE.encode())]
        path = self.p(name)
        write_container(path, entries, compress)
        return path

    def roundtrip(self, src):
        ws = self.p("ws-" + os.path.basename(src))
        res = of.unpack(src, ws)
        self.assertEqual(res["status"], "ok")
        out = self.p("out-" + os.path.basename(src))
        b = of.build(ws, out)
        self.assertEqual(b["status"], "ok", b)
        self.assertEqual(b["verification"]["status"], "match")
        self.assertEqual(b["changed_entries"], [])
        return res, b, out

    # --- обычный случай -------------------------------------------------------------

    def test_reference_form_roundtrip(self):
        src = self.make_form()
        res, b, out = self.roundtrip(src)
        ws = res["workspace_path"]
        self.assertEqual([e["name"] for e in res["entries"]], ["form", "module"])
        self.assertEqual([e["kind"] for e in res["entries"]], ["brace_tree", "bsl_module"])
        self.assertTrue(all(e["encoding"] == "utf-8-bom" and not e["deflated"] for e in res["entries"]))
        with open(os.path.join(ws, "payload", "module"), "rb") as f:
            self.assertEqual(f.read(), BOM + MODULE.encode())
        with open(os.path.join(ws, "decoded", "form.json"), encoding="utf-8") as f:
            self.assertIn("Форма списка «Товары»", f.read())
        with open(os.path.join(ws, "decoded", "module.bsl"), "rb") as f:
            self.assertIn("ПриОткрытии".encode(), f.read())
        manifest = json.loads(rb(os.path.join(ws, of.MANIFEST)))
        self.assertEqual(manifest["contract"], "ordinary-form/1")
        self.assertEqual(manifest["source"]["sha256"], _sha(rb(src)))
        # записи собранного файла — байт в байт исходные и без сжатия
        self.assertEqual(read_entries(out), read_entries(src))
        self.assertIn(b["binary_identical"], (True, False))

    def test_module_edit_is_reported_and_written_plain(self):
        src = self.make_form()
        ws = self.p("ws")
        of.unpack(src, ws)
        new_module = BOM + (MODULE + "// правка\r\n").encode()
        with open(os.path.join(ws, "payload", "module"), "wb") as f:
            f.write(new_module)
        out = self.p("out.bin")
        b = of.build(ws, out)
        self.assertEqual(b["verification"]["status"], "match")
        self.assertEqual(b["changed_entries"], ["module"])
        got = dict(read_entries(out))
        self.assertEqual(got["module"], new_module)
        # запись не сжата: в сыром контейнере лежит сам текст
        self.assertIn("// правка".encode(), rb(out))

    def test_deflated_source_is_rebuilt_plain(self):
        src = self.make_form(compress=("form", "module"))
        res, b, out = self.roundtrip(src)
        self.assertTrue(all(e["deflated"] for e in res["entries"]))
        self.assertTrue(res["warnings"])
        raw = rb(out)
        self.assertIn("ПриОткрытии".encode(), raw)
        self.assertEqual(dict(read_entries(out))["module"], BOM + MODULE.encode())

    def test_form_without_bom_and_extra_entry(self):
        entries = [("form", FORM_TREE.encode()), ("module", MODULE.encode()), ("picture", b"\x89PNG\x00\x01\xfe")]
        src = self.make_form(entries=entries)
        res, b, out = self.roundtrip(src)
        kinds = {e["name"]: (e["kind"], e["encoding"]) for e in res["entries"]}
        self.assertEqual(kinds["form"], ("brace_tree", "utf-8"))
        self.assertEqual(kinds["picture"], ("binary", "binary"))
        self.assertTrue(res["notes"][0].startswith("Состав записей"))
        self.assertEqual([n for n, _ in read_entries(out)], ["form", "module", "picture"])

    def test_nested_container_entry_kept_whole(self):
        inner = container_bytes([("a", b"inner-a"), ("b", b"inner-b")])
        src = self.make_form(entries=[("form", BOM + FORM_TREE.encode()), ("module", BOM + MODULE.encode()),
                                      ("nested", inner)])
        res, b, out = self.roundtrip(src)
        self.assertEqual({e["name"]: e["kind"] for e in res["entries"]}["nested"], "container")
        self.assertEqual(dict(read_entries(out))["nested"], inner)

    def test_entry_order_preserved(self):
        src = self.make_form(entries=[("module", BOM + MODULE.encode()), ("form", BOM + FORM_TREE.encode())])
        res, b, out = self.roundtrip(src)
        self.assertEqual([n for n, _ in read_entries(out)], ["module", "form"])

    def test_include_previews(self):
        src = self.make_form()
        res = of.unpack(src, self.p("ws"), include="all", max_chars=20)
        self.assertTrue(res["module_truncated"])
        self.assertEqual(len(res["module_text"]), 20)
        self.assertIn("structure", res)

    # --- отказы ---------------------------------------------------------------------

    def assertFormError(self, code, fn, *a, **kw):
        with self.assertRaises(of.FormError) as ctx:
            fn(*a, **kw)
        self.assertEqual(ctx.exception.code, code)

    def test_not_a_container(self):
        path = self.p("Form.xml")
        wb(path, b"<?xml version='1.0'?><Form/>")
        self.assertFormError("not_a_container", of.unpack, path, self.p("ws"))

    def test_missing_paths(self):
        self.assertFormError("path_not_found", of.unpack, self.p("nope.bin"), self.p("ws"))
        self.assertFormError("not_a_file", of.unpack, self.tmp, self.p("ws"))
        self.assertFormError("path_not_found", of.build, self.p("nows"), self.p("o.bin"))

    def test_multiple_containers_refused(self):
        src = self.make_form()
        data = rb(src)
        wb(src, data + data)
        self.assertFormError("unsupported_container_layout", of.unpack, src, self.p("ws"))

    def test_workspace_guards(self):
        src = self.make_form()
        foreign = self.p("foreign")
        os.makedirs(foreign)
        wb(os.path.join(foreign, "keep.txt"), b"x")
        self.assertFormError("workspace_not_empty", of.unpack, src, foreign, overwrite=True)
        self.assertTrue(os.path.exists(os.path.join(foreign, "keep.txt")))
        ws = self.p("ws")
        of.unpack(src, ws)
        self.assertFormError("workspace_exists", of.unpack, src, ws)
        self.assertEqual(of.unpack(src, ws, overwrite=True)["status"], "ok")

    def test_build_refusals(self):
        src = self.make_form()
        ws = self.p("ws")
        of.unpack(src, ws)
        out = self.p("out.bin")
        wb(out, b"old")
        self.assertFormError("output_exists", of.build, ws, out)
        self.assertEqual(rb(out), b"old")
        # правка производного файла
        with open(os.path.join(ws, "decoded", "module.bsl"), "ab") as f:
            f.write(b"// lost")
        self.assertFormError("derived_edit_detected", of.build, ws, self.p("o2.bin"))
        of.unpack(src, ws, overwrite=True)
        os.unlink(os.path.join(ws, "payload", "form"))
        self.assertFormError("payload_missing", of.build, ws, self.p("o3.bin"))
        os.unlink(os.path.join(ws, of.MANIFEST))
        self.assertFormError("manifest_missing", of.build, ws, self.p("o4.bin"))
        self.assertFalse(any(n.startswith(".ordinary-form-") for n in os.listdir(self.tmp)))

    def test_overwrite_replaces_only_after_match(self):
        src = self.make_form()
        ws = self.p("ws")
        of.unpack(src, ws)
        out = self.p("out.bin")
        wb(out, b"old")
        os.chmod(out, 0o640)
        b = of.build(ws, out, overwrite=True)
        self.assertEqual(b["verification"]["status"], "match")
        self.assertEqual(read_entries(out), read_entries(src))
        self.assertEqual(os.stat(out).st_mode & 0o777, 0o640)
        fresh = self.p("fresh.bin")
        of.build(ws, fresh)
        self.assertNotEqual(os.stat(fresh).st_mode & 0o077, 0)  # не 0600 от mkstemp

    def test_cli(self):
        src = self.make_form()
        ws = self.p("ws")
        buf = io.StringIO()
        import contextlib

        with contextlib.redirect_stdout(buf):
            self.assertEqual(of.main(["unpack", src, ws]), 0)
            self.assertEqual(of.main(["build", ws, self.p("o.bin"), "--verify"]), 0)
            self.assertEqual(of.main(["build", ws, self.p("o.bin")]), 1)  # output_exists
        docs, text, dec = [], buf.getvalue(), json.JSONDecoder()
        pos = 0
        while text[pos:].strip():
            while text[pos].isspace():
                pos += 1
            obj, pos = dec.raw_decode(text, pos)
            docs.append(obj)
        self.assertEqual([d["status"] for d in docs], ["ok", "ok", "error"])
        self.assertEqual(docs[1]["verification"]["status"], "match")
        self.assertEqual(docs[2]["error_code"], "output_exists")


@unittest.skipUnless(HAVE_V8 and os.environ.get("ORDINARY_FORM_SAMPLES"), "ORDINARY_FORM_SAMPLES не задан")
class RealFormsTest(unittest.TestCase):
    def test_real_forms_roundtrip(self):
        root = os.environ["ORDINARY_FORM_SAMPLES"]
        limit = int(os.environ.get("ORDINARY_FORM_SAMPLES_LIMIT", "3"))
        files = sorted(glob.glob(os.path.join(root, "**", "Ext", "Form.bin"), recursive=True))[:limit]
        self.assertTrue(files, f"В {root} нет **/Ext/Form.bin")
        tmp = tempfile.mkdtemp(prefix="ordinary-form-real-")
        try:
            for i, src in enumerate(files):
                with self.subTest(form=src):
                    before = _sha(rb(src))
                    ws, out = os.path.join(tmp, f"ws{i}"), os.path.join(tmp, f"out{i}.bin")
                    res = of.unpack(src, ws)
                    b = of.build(ws, out)
                    self.assertEqual(b["verification"]["status"], "match")
                    self.assertEqual(read_entries(out), [(e["name"], rb(os.path.join(ws, e["path"])))
                                                         for e in res["entries"]])
                    self.assertEqual(_sha(rb(src)), before)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
