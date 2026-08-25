# Инструменты

Предназначен для хранения любых сторонних утилит, необходимых для настройки проекта или для дополнительной установки.

## Каталоги и скрипты

| Путь | Назначение |
|------|------------|
| `dev-standalone/` | Автономный DEV-сервер (`ibsrv`): init/start/stop/restart, `Invoke-DataMcp`, `_DevEnv.ps1` / `_DevEnv.sh` |
| `dev-env/` | Профили IDE: Linux (`linux/apply.sh`, MCP launcher) |
| `prepare-objlist.sh` | Разбор `objlist.txt` → `build/out/*.txt` |
| `load-objlist-config.sh` | Частичная загрузка `src/cf` через ibcmd |
| `load-objlist-extensions.sh` | Частичная загрузка `src/cfe/*` через ibcmd |
| `deploy-extension.sh` | stop → import → apply → restart для CFE |
| `mcp-platform-tools-launcher.sh` | MCP Platform Tools на Linux (Cursor Remote) |
| `fix-1c-platform-tools-vrunner-cmd.ps1` | Workaround quoting vrunner на Windows |
| `init-project-structure.ps1` | Каталоги vanessa-bootstrap (`project-structure.json`) |
| `update-from-template.ps1` | Синхронизация rules/skills/agents/commands из git-шаблона (`/updaterules`) |
| `export-project-template.ps1` | Сборка/экспорт чистого шаблона из проектного репозитория (для мейнтейнеров) |
| `lists/` | Опциональные проектные списки partial-load |

* `*.json` — настройки vanessa-runner / автотестов  
* `vrunner.init.json.example` — шаблон подключения к ИБ  
* `syntax-check-excludes.txt` — исключения синтаксического контроля (при необходимости)

Значение параметров JSON — по схеме в файле или в справке продукта. Параметры DEV — в `.dev.env` (см. [docs/dev-environment.md](../docs/dev-environment.md)).
