---
name: 1c-thick-client-test
description: "Check ordinary 1C forms and thick-client code (#Если Клиент, #Если ТолстыйКлиентОбычноеПриложение), printing and reports, through tools/thick-client-check.sh. Use for the ordinary application. Managed forms go to 1c-qa."
argument-hint: "<scenario.json>"
---

# 1c-thick-client-test — ordinary forms in the thick client

The entry point is `tools/thick-client-check.sh`. Sources of the executor live in `scripts/` of this skill. The wrapper reads `.dev.env` and the scenario only. It starts its own Xvfb and `1cv8 ENTERPRISE /RunModeOrdinaryApplication`. Do not build a `1cv8` command line yourself.

Managed application and managed forms are the QA test client (`1c-qa`), not this skill. The test client (`1cv8c /TestClient`) does not see ordinary forms.

## When to use

- Ordinary application, ordinary forms (`Form.bin`), client code under `#Если Клиент` or `#Если ТолстыйКлиентОбычноеПриложение`.
- Printing and ordinary reports that must run on the client.
- A scenario file describes the documents, layouts and report names. Those names are not in the skill code.

## When not to use

- Managed forms, the thin client, the web client: `1c-qa` and `ui-testing-tools.mdc`.
- Reading or writing `Form.bin`: `v8unpack-cf` and `1c-form-inspect`. `unpack_ordinary_form` / `build_ordinary_form` exist on the code-index MCP at mcp.1commerce.ru; a project without that index (ep-trade), or a file the server cannot see, uses the local `tools/ordinary-form.py unpack` / `build --verify` (same contract). What the agent may change in an ordinary form itself and what goes as a package: `v8unpack-cf/docs/ordinary-forms.md` → *What the agent edits itself, what goes as a package*; this skill is the check after either.

## Run

```bash
tools/thick-client-check.sh scenario --params path/to/scenario.json
tools/thick-client-check.sh --infobase server:port/base --platform 8.3.14.1779 --ib-user '' scenario --params path/to/scenario.json
```

`--infobase`, `--platform` and `--ib-user` override `.dev.env` for both the EPF build and the enterprise run. An empty `--ib-user` omits `/N`. Do not edit `.dev.env` for a one-off base. Cache key is the source sha256, the platform build and the metadata format version chosen for that build.

Exit codes, stable for a later release-gate step `thick-client:<scenario>` (that step is not in this PR):

| Code | Meaning |
|---|---|
| 0 | Every step PASS |
| 1 | A step FAIL, or the timeout fired |
| 2 | Refused to start (arguments, missing `.dev.env`, Windows) |
| 3 | No Xvfb |

The report is `out/thick-client-check.json` and `.txt`. Evidence to hand over: that JSON plus the PDF/PNG files under `<task-dir>/evidence/`. Fields are listed in `docs/contract.md`.

## Security dialog

`/DisableStartupDialogs` is not passed: the dangerous-actions dialog defaults to No and would silently refuse `/Execute`. The wrapper may confirm «Защита от опасных действий» or «Предупреждение безопасности» only when all of these hold: the dialog appears while the phase is still `startup` (before the executor opens); the process is launching only the `.epf` under `out/thick-client-check/cache/` whose sha256 was recorded before start; a screenshot of the dialog is stored and listed in the report. The click targets a window whose title is the button «Да» or «Yes» when such a window exists. 1C draws that button inside the dialog, not as its own X window, so the usual result is a click in the left part of the dialog. The alternative is for an administrator to turn the protection off for the test user. «Легальность получения обновлений» is not confirmed by default: that click states the updates are legal on behalf of the infobase owner. A project that has made this decision passes `--dismiss-title "Легальность получения обновлений|click-left"` and records it in `AGENTS.local.md`. Other unknown modals are not confirmed: they are snapshotted and the process is stopped.

## Compatibility

| Family | Print / reports / invoice | Checked |
|---|---|---|
| УТ 10.3 | Print via export `Печать` with `args` `collector` (the configuration appends the spreadsheet to the array). Invoice of a subordinate `СчетФактураВыданный` the same way. Reports `ВедомостьТоварыНаСкладах`, `ВедомостьВзаиморасчетыСКонтрагентами` via `СформироватьОтчет` / form `ОбновитьОтчет`. ТОРГ-12 fails in the configuration expression when `ОтпускРазрешил` is empty and `Справочник.ОтветственныеЛицаОрганизаций` has no rows | Checked on `ep-trade-agent3`, platform 8.3.27.2130, compatibility 8.3.3, 2026-11-22. The builder `ПечатьСчетаФактуры1137` is not export and cannot be called. Same ТОРГ-12 error on the 8.3.2 copy (copy removed) |
| УПП 1.3 | Same method path when the document has export `Печать` | Запуск упирается в `ОбщийМодуль.ПользователиСервер.Модуль(248)`: `ОсновнаяРоль = Метаданные.ОсновнаяРоль` — «Недопустимо использование свойства "ОсновнаяРоль"». База `bm-upp-tcc-check`, платформа 8.3.14.1779, 2026-11-22. EPF формата 2.8 собрался (2.9 и 2.10 отвергнуты). Печать и отчёты — не проверено |
| БП 2.0 | — | не проверено |
| КА 1.1 | — | не проверено |
| Other configurations | Name the export method in the scenario | не проверено |
| Managed application and managed forms | — | Not this skill. QA test client (`1c-qa`) |

`?()` in 1C evaluates only the chosen branch. On the УТ copy, `ЗначениеЗаполнено(Неопределено)` is false, `?()` returns `""`, and the failing operation is `ФИООтпускРазрешил` (`Неопределено`) + `""`. That is a gap in the copy's data, and the same error happens on 8.3.2.

## Limits

Coordinate clicks and `windowclose` are only for startup dialogs the whitelist names. Closing a form after a snapshot is the executor's `Закрыть()`, not `xdotool windowclose` (`windowclose` destroyed the 1C window). Details: `docs/limits.md`. Scenario fields: `docs/scenario.md`.
