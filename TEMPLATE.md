# TEMPLATE.md — инициализация нового проекта из шаблона

Чеклист после клонирования шаблона (`git clone https://github.com/mikhailchuklay/1c-project-template.git`) или копирования в каталог `{PROJECT_ROOT}`.

## 1. Идентичность проекта

Перед настройкой проверить корень проекта: есть ли Git, `packagedef` и правила
шаблона либо пока только выгрузка `src`. Существующие исходники не перезаписывать.
Если Devbox MCP подключён, сначала получить существующие базы и кластеры через
`infobase_list` / `cluster_list`, сверив схему инструментов. Адреса хранилищ получить
через `storage_web_status`, публикации баз — через `web_list`; связывать записи
по реальному проекту/базе/кластеру. Отсутствующие данные не выдумывать и не считать
выключенной функцией. Уточнить выбор личной
базы у разработчика; взять сборку платформы и порты из найденного кластера.
Не искать эти сведения полным сканированием домашнего каталога или профилей 1С.
Подробные ограничения: `.cursor/rules/devbox-setup-discovery.mdc`.

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

В MCP-конфигах шаблона и Linux-профиля все серверы явно включены
(`disabled: false`), кроме четырёх проектных codemeta/graph для основной
конфигурации и расширения (`disabled: true`). Их включать после настройки адресов
и проверки доступности индексов. После замены плейсхолдеров сохранять эти флаги;
в существующих проектах не отменять ручное отключение серверов без запроса.
Включение сервера не создаёт публикацию, индекс или локальный процесс:
Platform Tools/RLM должны быть запущены, а URL data MCP — заполнен.

При начальной настройке агент обязан также пройти [настройку персонального RLM](docs/rlm-setup.md): спросить, подключать ли его, предложить зарегистрировать проект и отдельно согласовать построение индекса. Не пропускать эти вопросы из-за доступности graph/code-metadata.

```powershell
Copy-Item .dev.env.example .dev.env
# Заполните: PLATFORM_VERSION, PLATFORM_PATH, INFOBASE_PATH, PREFIX, COMPANY, DEVELOPER
# Для DEV standalone: STANDALONE_PORT, STANDALONE_HTTP_BASE, INFOBASE_PUBLISH_URL
# Хранилище конфигурации — см. блок ниже (агент обязан спросить явно)
Copy-Item env.json.example env.json
# Заполните --ibconnection и --v8version
Copy-Item tools\vrunner.init.json.example tools\vrunner.init.json
# При необходимости — серверная ИБ
```

### Хранилище конфигурации (обязательный вопрос)

Агент (и человек при ручном заполнении) **обязан один раз спросить**:

> Проект ведётся через хранилище конфигурации 1С (хранилище разработки)?

| Ответ | Действие в `.dev.env` |
|-------|------------------------|
| **Да** | заполнить `REPOSITORY_PATH` (путь или `tcp://сервер/алиас`), `REPOSITORY_USER`, `REPOSITORY_PASSWORD` (пароль может быть пустым); `REPOSITORY_ALLOW_FORCE` не трогать |
| **Нет** | оставить `REPOSITORY_PATH` пустым (= конфигурация не привязана к хранилищу) |

Регламент при непустом `REPOSITORY_PATH`: skill `1c-repository-manage` (`.cursor/skills/1c-repository-manage/SKILL.md`, канон процесса — его `docs/repo-sdlc.md`). Вопрос задаётся **только при init** — это оверлей шаблона; сам набор правил вендора значение не спрашивает. Не хранить адрес/логин/пароль хранилища в `memory.md`. Проекты, созданные до перехода на `REPOSITORY_*`: `CONFIG_STORAGE_URL` → `REPOSITORY_PATH`, `CONFIG_STORAGE_USER/PASSWORD` → `REPOSITORY_USER/PASSWORD`, старые ключи удалить.

`memory.md` и `USER-RULES.md` уже пустые шаблоны — дополняйте по мере работы.

## 3. MCP на mcp.1commerce.ru

1. Создайте проектные индексы для `{PROJECT_SLUG}` (codemeta + graph). Расширение, которое индексируется отдельно, получает свой codemeta-сервер (`codemeta-{PROJECT_SLUG}-<ext>`); граф contract 2.0 держит слои расширений в одном проекте (`refresh_extension_layers`).
2. Замените `{PROJECT_SLUG}` в `.cursor/mcp.json`; отдельный индекс расширения добавьте своим блоком с понятным id сервера.
3. Если контуров больше одного (основная конфигурация + расширения, отдельные индексы) — опишите их в `project-contours.json` в корне проекта (формат и пример — `.cursor/rules/multi-contour-search.mdc`) и сошлитесь на файл из `USER-RULES.md`. Один контур — файл не нужен.
4. Перезагрузите окно Cursor после правки MCP.

Shared-сервисы (syntax, docs, templates, ssl, codecheck) уже указывают на `https://mcp.1commerce.ru/...`. Блок `1c-qa` (QA MCP, `https://mcp.1commerce.ru/qa/mcp`) включён, в `.dev.env.example` стоит `TOOL_QA=auto`: QA MCP — основной маршрут UI-проверок (`ui-testing-tools.mdc`), веб-клиент — запасной. Для подключения задайте переменную окружения `QA_MCP_TOKEN` (QA-токен стенда, выдаёт владелец инфраструктуры; в репозиторий не кладётся). `TOOL_QA=off` отключает QA MCP.

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

## 7. OpenSpec и правила агента

- OpenSpec: `openspec/specs/`, `openspec/changes/` — пустой skeleton готов.
- **Обновление правил из шаблона:** `/updaterules` → `tools/update-from-template.ps1` (источник: [1c-project-template](https://github.com/mikhailchuklay/1c-project-template)). Опционально в `.dev.env`: `RULES_TEMPLATE_URL`, `RULES_TEMPLATE_REF`.
- Первичная установка «голого» `comol/ai_rules_1c` через `install.ps1` — только если проект **не** из этого шаблона; для шаблонных проектов не нужна.

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
- [ ] Задан ответ по хранилищу: `REPOSITORY_PATH` заполнен (с USER/PASSWORD) или пуст
- [ ] `src/cf` содержит выгрузку или пуст с README
- [ ] MCP tools видны в Cursor после Reload Window
- [ ] `openspec/changes/` — только `README.md`
