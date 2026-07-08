# TEMPLATE.md — инициализация нового проекта из шаблона

Чеклист после клонирования шаблона (`git clone https://github.com/mikhailchuklay/1c-project-template.git`) или копирования в каталог `{PROJECT_ROOT}`.

## 1. Идентичность проекта

| Плейсхолдер | Где заменить | Пример |
|-------------|--------------|--------|
| `{PROJECT_SLUG}` | `.cursor/mcp.json` (URL codemeta/graph/ext/data) | `my-erp-dev` |
| `{PROJECT_NAME}` | `USER-RULES.md`, `README.md`, `packagedef` | `my-erp-dev` |
| `{INFOBASE_PUBLISH_URL}` | `.cursor/mcp.json` → `1c-data-mcp.url` | `http://localhost:8314/my-erp-dev/` |

Поиск незакрытых плейсхолдеров:

```powershell
cd {PROJECT_ROOT}
Select-String -Path . -Pattern '\{PROJECT_SLUG\}|\{PROJECT_NAME\}|\{INFOBASE_PUBLISH_URL\}' -Recurse -Exclude @('.git')
```

## 2. Параметры окружения

```powershell
Copy-Item .dev.env.example .dev.env
# Заполните: PLATFORM_VERSION, PLATFORM_PATH, INFOBASE_PATH, PREFIX, COMPANY, DEVELOPER
# Для DEV standalone: STANDALONE_PORT, STANDALONE_HTTP_BASE, INFOBASE_PUBLISH_URL
Copy-Item env.json.example env.json
# Заполните --ibconnection и --v8version
Copy-Item tools\vrunner.init.json.example tools\vrunner.init.json
# При необходимости — серверная ИБ
```

`memory.md` и `USER-RULES.md` уже пустые шаблоны — дополняйте по мере работы.

## 3. MCP на mcp.1commerce.ru

1. Создайте проектные индексы для `{PROJECT_SLUG}` (codemeta + graph; при расширении — `-ext`).
2. Замените `{PROJECT_SLUG}` в `.cursor/mcp.json`.
3. Если проект **без расширения** — удалите блоки `1c-ext-codemeta-mcp` и `1c-ext-graph-mcp`.
4. Перезагрузите окно Cursor после правки MCP.

Shared-сервисы (syntax, docs, templates, ssl, codecheck) уже указывают на `https://mcp.1commerce.ru/...`.

### OneMCP в информационной базе (если ещё не установлено)

Для `1c-data-mcp` / `Invoke-DataMcp.ps1` в ИБ нужны расширение **OneMCP** и инструменты в справочнике `APA_Инструменты`:

1. Установите `vendor/mcp/OneMCP.cfe` в ИБ (Platform Tools или Конфигуратор).
2. Импортируйте `vendor/mcp/ИнструментыДляРазработки.xml` в `APA_Инструменты`.
3. Назначьте права на HTTP-сервис `APA_MCP`.

Подробно: [vendor/mcp/README.md](vendor/mcp/README.md).

## 4. Расширения IDE

Установите:

- [1C: Platform Tools](https://marketplace.visualstudio.com/items?itemName=yellow-hammer.1c-platform-tools)
- [1C: Platform Tools MCP](https://marketplace.visualstudio.com/items?itemName=yellow-hammer.mcp-1c-platform-tools)

Skills `1c-platform-tools*` появятся из расширения, не из git.

## 5. Структура каталогов и исходники

```powershell
.\tools\init-project-structure.ps1   # идempotent
```

Выгрузите конфигурацию в `src/cf` (Platform Tools или `/getconfigfiles`).

## 6. DEV standalone (опционально)

```powershell
.\tools\dev-standalone\init-config.ps1
.\tools\dev-standalone\start.ps1
.\tools\dev-standalone\restart.ps1   # после config apply
```

На Linux (Cursor Remote):

```bash
bash tools/dev-env/linux/apply.sh      # MCP + launch/settings
bash tools/dev-standalone/init-config.sh
bash tools/dev-standalone/start.sh
```

Проверка: `INFOBASE_PUBLISH_URL` из `.dev.env` отвечает HTTP 200.

Функциональные проверки через MCP data — см. `.cursor/rules/1commerce-functional-testing.mdc` и `tools/dev-standalone/Invoke-DataMcp.ps1`.

## 7. OpenSpec и 1c-rules

- OpenSpec: `openspec/specs/`, `openspec/changes/` — пустой skeleton готов.
- Обновление правил: `/updaterules` или `install.ps1 update` из [1c-rules](https://github.com/comol/ai_rules_1c).

## 8. Git

```powershell
git init
git add .
git commit -m "Initial project from 1c-project-template"
```

`.gitignore` исключает `.dev.env`, `env.json`, `memory.md`, `build/`.

## 9. Публикация MCP на IIS (PROD, опционально)

См. [deploy/mcp-publish/README.md](deploy/mcp-publish/README.md). Замените `{PUBLISH_BASE}`, `{MCP_PUBLISH_BASE}`, строку подключения к ИБ в `default.vrd`.

## Проверка готовности

- [ ] Нет секретов в git (`grep` по паролям, IP prod-сервера)
- [ ] `src/cf` содержит выгрузку или пуст с README
- [ ] MCP tools видны в Cursor после Reload Window
- [ ] `openspec/changes/` — только `README.md`
