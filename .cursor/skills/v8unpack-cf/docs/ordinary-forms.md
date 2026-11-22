# Ordinary forms — `Form.bin`

**An ordinary form is not XML.** In a Designer file export a managed form writes
`Forms/<Имя>/Ext/Form.xml`; an ordinary form writes `Forms/<Имя>/Ext/Form.bin` — a
1C container holding two payload entries: `form` (the layout, a brace tree) and
`module` (the form module, BSL). The sidecar `Forms/<Имя>.xml` declares which model
it is, via `<FormType>Ordinary</FormType>`.

Find them with `**/Forms/*/Ext/Form.bin`. A form whose `Form.xml` appears to be
"missing" is almost always an ordinary form, not a broken export.

### The contract — `ordinary-form/1`

The same two tools, with the same arguments and the same result payload, are
published by **`1c-code-metadata-mcp`** and **`1c-graph-metadata-mcp`**. Learn them
once. On the graph server the payload arrives in the envelope's `data` section; on
the code server it is the result itself.

#### `unpack_ordinary_form`

| Parameter | Default | Meaning |
|---|---|---|
| `form_path` | — | The `Form.bin` to read. Absolute path; Cyrillic is normal. |
| `workspace_path` | — | Where to materialise the workspace. New, empty, or a workspace this tool wrote. |
| `overwrite` | `false` | Replace an existing workspace **of this contract**. A non-empty directory the tool did not write is refused whatever this says. |
| `include` | `"summary"` | Which bounded preview to embed: `summary` (paths only), `structure`, `module`, `all`. |
| `max_chars` | `4000` | Bound on each embedded preview (server cap 20 000). |

Result: `status`, `contract`, `tool`, `workspace_path`, `manifest_path`, `source`
(`path` / `size` / `sha256`), `container`, `entries`, `entries_truncated`, `notes`,
`warnings` — plus `structure` / `structure_truncated` and `module_text` /
`module_truncated` when `include` asks for them. Each entry carries `name`, `kind`
(`brace_tree` / `bsl_module` / `text` / `container` / `binary`), `size`, `sha256`,
`encoding`, `deflated`, `path` and `decoded_path`.

#### `build_ordinary_form`

| Parameter | Default | Meaning |
|---|---|---|
| `workspace_path` | — | A workspace written by `unpack_ordinary_form`. |
| `output_path` | — | The `Form.bin` to write. Never replaced silently. |
| `overwrite` | `false` | Replace an existing output file. |
| `verify` | `true` | Re-read the result and compare the payload. Leave it on. |

Result: `status`, `contract`, `tool`, `workspace_path`, `output_path`, `output`
(`path` / `size` / `sha256`), `source`, `binary_identical`, `verified`,
`verification` (`match` / `mismatch` / `skipped`, with per-entry hashes),
`changed_entries`, `notes`.

#### Errors

A refusal is `status="error"` with an `error_code` and an actionable `hint`. The
codes: `dependency_missing`, `path_invalid`, `path_not_found`, `not_a_file`,
`not_a_container`, `unsupported_container_layout`, `workspace_not_empty`,
`workspace_exists`, `workspace_invalid`, `manifest_missing`, `manifest_invalid`,
`payload_missing`, `derived_edit_detected`, `output_exists`, `unpack_failed`,
`build_failed`, `verify_failed`.

### No MCP — the local script `tools/ordinary-form.py`

When the project has no code-index MCP with these tools (a «только хранилище»
project without an index, UT 10.3 and other configurations whose forms are almost
all ordinary), or the server cannot see the file (the export lives in the agent
container, not in the indexed sources), use the local script. It implements the same
contract on the `v8unpack` package installed in the agent image: the same workspace,
manifest, result fields, error codes and verification.

| MCP call | Local call |
|---|---|
| `unpack_ordinary_form(form_path, workspace_path, overwrite, include, max_chars)` | `python3 tools/ordinary-form.py unpack "<Form.bin>" "<workspace>" [--overwrite] [--include summary\|structure\|module\|all] [--max-chars N]` |
| `build_ordinary_form(workspace_path, output_path, overwrite, verify=true)` | `python3 tools/ordinary-form.py build "<workspace>" "<Form.bin>" [--overwrite] [--verify]` (`--verify` is the default; `--no-verify` exists only for diagnostics) |

The result is the same JSON, printed to stdout (`"tool"` names the MCP tool it
mirrors). Exit code 0 — `status="ok"` and, for a verified build,
`verification.status == "match"`; 1 — a refusal (`error_code`, `hint`) or a
mismatch; 2 — bad arguments. The script builds into a temporary file next to the
output and replaces the output **only after** the re-read matched — a mismatch leaves
the original `Form.bin` untouched. Without `v8unpack` it answers
`error_code="dependency_missing"`; that is a blocker to report, not a reason to
parse the container by hand. The manifest records `tool: "tools/ordinary-form.py"`;
a workspace written by either route builds with either route.

### The workspace

```text
<workspace>/
  ordinary-form.json    # manifest: source, entries, hashes. Generated — never hand-edit.
  payload/
    form                # the layout brace tree, UTF-8 BOM + CRLF   <- SOURCE OF TRUTH
    module              # the form module, BSL, UTF-8 BOM + CRLF    <- SOURCE OF TRUTH
  decoded/
    form.json           # the layout as JSON-compatible data        <- derived, read-only
    module.bsl          # the module, for BSL tooling               <- derived, read-only
```

**Edit `payload/`.** `decoded/` is regenerated on every unpack and is never read
back. Editing a derived view and then building is refused with
`derived_edit_detected` rather than silently dropped — but only that refusal saves
the work, so do not rely on noticing.

### Workflow — edit an ordinary form

```powershell
# 1. Read it
unpack_ordinary_form(
    form_path="C:\src\Catalogs\Товары\Forms\Форма\Ext\Form.bin",
    workspace_path="C:\work\Форма")

# 2. Edit C:\work\Форма\payload\module (BSL) or payload\form (the layout tree).
#    Keep the UTF-8 BOM and the CRLF line endings.

# 3. Write it back, and prove nothing was lost
build_ordinary_form(
    workspace_path="C:\work\Форма",
    output_path="C:\src\Catalogs\Товары\Forms\Форма\Ext\Form.bin",
    overwrite=$true)
```

Without the MCP tools the same three steps run locally (in the agent container):

```bash
python3 tools/ordinary-form.py unpack "src/cf/Catalogs/Товары/Forms/Форма/Ext/Form.bin" "$TMPDIR/Форма"
# edit "$TMPDIR/Форма/payload/module" or payload/form — keep the UTF-8 BOM and CRLF
python3 tools/ordinary-form.py build "$TMPDIR/Форма" "src/cf/Catalogs/Товары/Forms/Форма/Ext/Form.bin" --overwrite --verify
```

Keep the workspace outside the sources (a temporary directory or `out/`), never in
`src/`.

Check `verification.status == "match"`. Then load the export into the infobase the
normal way (`/update1cbase`) — this skill writes a file, it does not touch an
infobase.

`match` proves the container lost nothing; it does not prove the change is right or
that the form opens. What the agent may change itself and what goes as a manual
package, and the thick-client check after it: [the table below](#what-the-agent-edits-itself-what-goes-as-a-package).

Paths with spaces or Cyrillic go in double quotes, always. In PowerShell prefer
single-quoted literals (`'C:\src\...\Form.bin'`) when the path contains `$`.

### What the agent edits itself, what goes as a package

A rebuild with `verification.status == "match"` proves the container lost nothing —
not that the change means what was intended. For the ordinary forms of a modern
configuration `v8unpack` yields no named element tree (147 of 147 with an empty
`*.elem.json`, see [Limitations](../SKILL.md#limitations)): layout, «Данные» bindings,
events and edge bindings are positional arrays in `payload/form`. So the agent's own
write access is limited to what can be proven without a name:

| Change | Who | Condition |
|---|---|---|
| Form module code (`payload/module`, read as `decoded/module.bsl`) | Agent | Rebuild with `match`, `changed_entries == ["module"]`, module gates of `verification-gates.mdc` |
| Elements created programmatically in the module (`ПриОткрытии` / `ПередОткрытием`) with handlers attached by `УстановитьДействие` | Agent | As for the module; plus the thick-client check below |
| A property of an **existing** element — text, visibility, enabled | Agent | Only when the value is found in `payload/form` exactly once and unambiguously belongs to that element (e.g. a unique caption string); rebuild with `match`; the thick-client check with a screenshot is mandatory |
| A new element in the layout | Package | `1c-change-package` (manual), applied in the Configurator form editor |
| Data («Данные») and event bindings in the layout | Package | Same |
| Re-layout, edge bindings (привязки краёв), moving elements | Package | Same |

Thick-client check: after loading, the form is opened with the skill
`1c-thick-client-test` / `tools/thick-client-check.sh` and a screenshot is attached.
Where the project does not have it yet, the check is «не проверено» with that reason,
under Risks, never reported as passed — and a layout property edit is then a package,
not an agent edit. After a person applied a package, the agent checks the form the
same way.

### Warnings — read before the first call

- **`Form.bin` is a binary 1C container, not a document. Never edit it directly,
  never read it as XML, never open it with an XML tool.** A text editor corrupts
  it silently. It is *one* container: the reference ordinary form holds exactly two
  entries, `form` and `module`, stored verbatim. A file holding more than one
  container is a whole CF / CFE / EPF and is refused with
  `unsupported_container_layout`; an entry that is itself a container is kept whole
  rather than descended into, which is what keeps the round trip lossless.
- **Never Deflate the entries of a `Form.bin`.** 1C:Enterprise reads the `form` and
  `module` streams of a standalone ordinary form only as plain UTF-8 BOM text; a
  deflated stream is «Ошибка формата потока» and the thick client exits (observed on
  8.3.27.2074, in Designer and in Enterprise alike — a 728 KB form packed to 114 KB
  never opened again until it was repacked plain). Designer writes them plain.
  `build_ordinary_form` and `tools/ordinary-form.py build` write every entry plain whatever the manifest's `deflated`
  flag says (the flag records how the *source* stored the entry; a deflated source
  is reported in `warnings` on unpack and in `notes` on build). Do not "optimise"
  a `Form.bin` with any repacking tool's `-deflate` / `-pack` — the size it saves is
  the form it loses.
- **Do not judge a round trip by the final SHA-256.** `v8unpack` stamps container
  records with the current time, so a rebuilt `Form.bin` differs byte for byte from
  its source even when nothing changed. `binary_identical: false` together with
  `verification.status: "match"` is the **normal, correct** outcome. The equality
  that means "nothing was lost" is the logical payload — entry names, sizes and
  SHA-256 — which is what `verification` reports.
- **Preserve the workspace manifest and `payload/`.** They are what a build reads.
  A workspace without `ordinary-form.json` is not a workspace (`manifest_missing`),
  and a missing payload entry is refused (`payload_missing`) rather than built
  around.
- **A standalone `Form.bin` names nothing.** Its brace tree is positional: it is
  structurally parseable, and no token in it says "this is a button called X". Do
  not invent element names, types or handlers from it. Named element trees
  (`*.elem.json`) come from high-level CF / CFE / EPF extraction, where the
  surrounding metadata supplies the names — and even there v8unpack 1.2.6 writes a
  populated tree only for **managed** forms (see [Limitations](../SKILL.md#limitations)).
- **On Windows use `--processes 1`** for the CLI unless parallel processing has
  been validated for the artifact at hand. The MCP tools spawn no processes at all.
- **Entries are written with `nested=True` semantics, never through
  `Container.build(nested=False)`.** In `v8unpack` the `nested` flag of
  `Container.build` means "store entries as is": `nested=False` Deflates every entry
  (and in 1.2.6 crashes with `struct.error`). `tools/ordinary-form.py` writes the
  records itself in the source order (`Container.build` would sort them by name) and
  keeps an entry that is itself a container whole.
- **Nothing is overwritten silently.** An existing workspace needs
  `overwrite=true`; an existing output file needs `overwrite=true`; a non-empty
  directory the tool did not write is refused outright, `overwrite` or not.

### Which route for a form

| Situation | Route |
|---|---|
| One ordinary form, sources already on disk | `unpack_ordinary_form` / `build_ordinary_form` |
| The same, no code-index MCP or the server cannot see the file | `tools/ordinary-form.py unpack` / `build --verify` |
| Every form of a `.cf` / `.cfe` / `.epf` at once | CLI `-E`, then the per-form files it writes |
| The infobase is available and you want XML sources | `/getconfigfiles` — not this skill |
| A managed form (`Ext/Form.xml`) | `1c-metadata-manage` skill — not this skill |
