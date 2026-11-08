# Шаблон в Linux-среде: Windows-зависимости и их замены

Где шаблон написан под Windows и что делать на Linux (контейнер разработчика или агента: bash, python3, git, Xvfb, vanessa-runner, платформа в `/opt/1cv8/x86_64/<версия>`, **pwsh нет**). Состояние на 08.11.2026. Правила сюда не ссылаются: это справочник для сопровождающих шаблона и людей, которые настраивают среду.

Решения: **пара** — POSIX-вариант есть; **добавить** — нужен POSIX-вариант (S/M/L — трудоёмкость); **только Windows** — на Linux используется указанная замена. Приоритет: **P1** — агент в контейнере упрётся в обычной работе; **P2** — настройка и обслуживание, запускает человек; **P3** — возможность рабочего стола Windows.

## Инвариант запуска платформы

Процессы `1cv8` / `1cv8c`, запущенные агентом, не используют дисплей человека и не ждут диалог. Windows — скрытое окно и флаги; Linux с X-сеансом — только `xvfb-run -a` или свой `Xvfb`; без X — `ibcmd` / `vrunner`. Флаги `/DisableStartupDialogs /DisableStartupMessages /Out /DumpResult` и тайм-аут обязательны. Предпочтение: `ibcmd` → `vrunner` → `tools/designer-batch.sh`. Подробно: `.cursor/rules/designer-batch-checks.mdc`, `docs/headless-agent.md`.

## Закрыто в этом изменении

| Место | Решение |
|---|---|
| Пакетный Конфигуратор (`designer-batch-checks.mdc`, рецепт PowerShell) | `tools/designer-batch.sh` — пара: свой виртуальный экран, флаги, тайм-аут, вердикт по трём сигналам; секция POSIX в правиле |
| `/DisableStartupDialogs` в рецептах `deploy-and-test.md`, `update1cbase.md`, `loadfrom1cbase.md`, `getconfigfiles.mdc` | флаг добавлен (на Windows рецепт остаётся PowerShell) |
| `headless-agent.mdc` §2а, `docs/headless-agent.md`: «Конфигуратор работает без окон» | уточнено: только на виртуальном экране и с флагами; порядок `ibcmd` → `vrunner` → обёртка |
| `tools/update-from-template.ps1` (на dev-workplaces нет pwsh, синхронизацию делали вручную) | `tools/update-from-template.sh` — пара; команда `/updaterules` показывает оба варианта |
| `dev-standards-env.mdc`: `PLATFORM_PATH` «must contain `bin\1cv8.exe`» | указана Linux-раскладка `/opt/1cv8/x86_64/<ver>` без `bin/` и `.exe` |
| `AGENTS.md`, `1commerce-agent-autonomy.mdc` | строка про экран и ссылка на обёртку |

## Скрипты скиллов

| Место | Что Windows-специфично | Решение | Приоритет |
|---|---|---|---|
| `1c-metadata-manage`: `form-add`, `remove-form`, `form-compile`, `meta-edit`, `meta-validate`, `web-*` | PowerShell | **пара**: `.py` с тем же набором параметров (`docs/runtime-selection.md`); в доменных доках (`form-manage.md`, `meta-manage.md`) показан только `powershell.exe` — дописать строку `python3` (S) | P1 |
| `1c-metadata-manage`: семейства `cfe-*`, `cf-*`, `form-edit/info/validate`, `meta-compile/remove/info`, `skd-*`, `role-*`, `mxl-*`, `uuid-check` (~85 тыс. строк) | нужен pwsh; Windows-кода нет, это работа с XML | **добавить**: pwsh 7 в образ агента и прогон семейств на Linux (S + M) или Python-порты (L). Пока без pwsh задача считается заблокированной (`runtime-selection.md`: ручная правка XML запрещена) — заимствование в расширение, правка форм, СКД, ролей в контейнере недоступны | P1 |
| `subsystem-*`, `xdto-*`, `interface-*`, `help`, `template-manage`, `support-edit`, `epf/erf-scaffold`, `epf-validate` | нужен pwsh | **добавить**: тем же pwsh (S); порт по требованию | P2 |
| `_common/Invoke-1CEdit.ps1` (`METADATA_PREVIEW`) | только PowerShell | **добавить** `invoke_1c_edit.py` (M); пока `-DryRun` инструмента + `git diff` | P2 |
| `_common/DevEnv.ps1` | — | **пара**: `_common/dev_env.py` | — |
| `db-*` (`db-load-xml`, `db-dump-xml`, `db-update`, `db-cfe-admin`, `db-load-git`) | `1cv8.exe`, `C:\Program Files\1cv8` | **только Windows**; на Linux — vrunner (`cf_load`/`cfe_load --no-update-db` + `infobase_update`, `cf_unload`/`cfe_unload` с явным `extension_name`), `tools/deploy-extension.sh`, `tools/load-objlist-*.sh`. Комментарий в `db-load-xml.ps1:11` и `epf-build.ps1` про «.py-порт» неверен — в шаблоне порта нет, убрать (S) | P1 |
| `db-dump-dt` / `db-load-dt` / `db-create` / `db-run` | `1cv8.exe` | **только Windows**; на Linux `ibcmd infobase dump/restore/create`, клиент — `qa-testclient.sh start` (Xvfb) | P2 |
| `epf-build`, `epf-dump`, `stub-db-create` | `1cv8.exe`, `Start-Process` | **только Windows**; на Linux vrunner `epf_compile` / `epf_decompile` | P1 |
| `repo-ops.ps1` | `1cv8.exe` | **только Windows**; на Linux vrunner `repo_lock/load/commit/unlock` (§2а). Отчёт/история/сравнение хранилища — `tools/designer-batch.sh -- /ConfigurationRepositoryReport …`. В `1c-repository-manage/SKILL.md` нет ссылки на §2а — добавить (S) | P1 |
| `install-files-update.ps1` | Планировщик задач | **только Windows**; в контейнере не нужно | P3 |
| `qa-testclient.ps1` | WinAPI | **пара**: `qa-testclient.sh` | — |

## Команды `.cursor/commands`

| Место | Что Windows-специфично | Решение | Приоритет |
|---|---|---|---|
| `deploy-and-test.md`, `update1cbase.md`, `loadfrom1cbase.md`, `getconfigfiles.md` + `getconfigfiles.mdc` | только PowerShell-блоки с `{PLATFORM_PATH}\bin\ibcmd.exe` / `1cv8.exe`, `Start-Process` | **добавить** Linux-ветку (S каждая): `tools/deploy-extension.sh`, двухшаговая загрузка vrunner, `ibcmd` через `dev_env_platform_exe`, Конфигуратор — `tools/designer-batch.sh` | P1 |
| `build-release.md`, `restore-testbase.md` | `db-dump-cf/dt`, `db-load-dt`, обратные слеши | **добавить** Linux-ветку (S): vrunner `cfe_compile`/`epf_compile`/`cf_unload`, `ibcmd infobase dump/restore` | P1 |
| `check-uuid.md` | `powershell.exe … uuid-check.ps1` | **добавить** `uuid-check.py` (S) | P1 |
| `initproject.md` | `install.ps1`, `db-create.ps1` | **только Windows**; в контейнере базы создаёт человек или devbox | P2 |
| `doctor.md` | `Get-ChildItem`, `powershell … validate-rules.ps1`, «`bin\1cv8.exe`» | **добавить** bash-проверки (S) | P2 |
| `installmcp.md`, `updatemcp.md`, `checkmcp.md`, `checkupdates.md`, `support.md`, `supportstatus.md` | PowerShell, `$env:TEMP`, `C:\Work\MCP_Distr` | **только Windows** сейчас; в контейнере MCP приходят с `mcp.1commerce.ru`. bash-варианты по требованию (M) | P2 |
| `install-windows-mcp.md`, `install-edt-mcp.md`, `installfilesupdatescript.md` | Windows-MCP, EDT, Планировщик | **только Windows**; на Linux снимки окон — `qa-testclient.sh capture` | P3 |
| `install-cognee`, `install-atlassian-mcp`, `install-rtk`, `install-officecli`, `install-agent-browser`, `install-openviking` | PowerShell как основной вариант | **пара**: в тексте есть ветка Linux/macOS | P3 |

## Правила, агенты, прочие скиллы

| Место | Что Windows-специфично | Решение | Приоритет |
|---|---|---|---|
| `1commerce-functional-testing.mdc:77,112-117`, `mcp-1c-tools/docs/1c-data-mcp.md:55-57` | только `start.ps1`, `Invoke-DataMcp.ps1`, обратные слеши | **пара** `start.sh`/`stop.sh` есть — назвать в тексте (S); `invoke-datamcp.sh` неполный (нет `validate-query`, `last-error`, `raw`, `--url/--user/--env-file`) — довести (S) | P1 |
| `metadata-xml-workarounds.mdc:82-83` | `meta-validate.ps1`, `cfe-validate.ps1` | `meta-validate.py` — **пара**; `cfe-validate` — см. семейство `cfe-*` | P1 |
| `.cursor/agents/metadata-manager.md:40,44` | «Use the PowerShell scripts» | **добавить** ссылку на `runtime-selection.md` и `python3` (S) | P1 |
| `AGENTS.md`: «Windows shell → `powershell-windows`» | указатель только на Windows | при следующем пересмотре бюджета — «Linux shell → bash» (S) | P2 |
| `ui-testing-tools.mdc`, `web-client-driving.mdc` (Windows-MCP, окно `#32770`) | Win32 | **только Windows**; на Linux QA MCP + agent-browser | P3 |
| `.cursor/mcp.json` (`${env:USERPROFILE}\.cursor\extensions\…`) | путь профиля Windows | **пара**: `tools/dev-env/linux/apply.sh` + `mcp-platform-tools-launcher.sh` | P2 |
| `powershell-windows`, `handoff`, `v8unpack-cf/docs/ordinary-forms.md` | PowerShell-конвенции, пример `C:\src` | **только Windows** / косметика | P3 |

## `tools/`, `deploy/`, `docs/`

| Место | Что Windows-специфично | Решение | Приоритет |
|---|---|---|---|
| `tools/dev-standalone/*.ps1` (`_DevEnv`, `init-config`, `start`, `stop`, `restart`) | PowerShell | **пара**: `.sh` с теми же именами, плюс `kill-sessions.sh` | — |
| `tools/dev-standalone/Invoke-DataMcp.ps1` | PowerShell | **пара неполная**: `invoke-datamcp.sh`, см. выше | P1 |
| `tools/dev-standalone/Test-FormModuleStatic.ps1` | PowerShell; ниоткуда не вызывается | удалить или заменить `grep` (S) | P3 |
| `tools/init-project-structure.ps1` | pwsh | **добавить** `.sh` / `.py` поверх `project-structure.json` (S) | P2 |
| `tools/export-project-template.ps1`, `tools/fix-1c-platform-tools-vrunner-cmd.ps1`, `deploy/mcp-publish/install-mcp-publication.ps1` | Windows-пути, `cmd`-кавычки, IIS | **только Windows**; на Linux не нужны (публикация — `ibsrv`/`start.sh` или `web-publish.py`) | P3 |
| `docs/dev-environment.md:67,89`, `docs/initial-setup-playbook.md:60,224-243` | PowerShell-блоки | **добавить** bash-строки рядом (S) | P2 |

`.bat`/`.cmd`, обращений к реестру Windows и `cmd /c` в инструкциях нет.

## Бэклог

Незакрытые пункты из таблиц — в issue шаблона «Linux-совместимость: остаток аудита 08.11.2026». Первые по важности: pwsh в образ агента или порт `cfe-*`; Linux-ветки в командах загрузки и выгрузки; `uuid-check.py`; паритет `invoke-datamcp.sh`.
