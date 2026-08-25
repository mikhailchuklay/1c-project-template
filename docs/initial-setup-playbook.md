# Playbook: начальная настройка проекта {PROJECT_SLUG}

Пошаговая инструкция для нового разработчика или новой рабочей машины.
Ориентир — Cursor + расширение **1C: Platform Tools** + серверная ИБ
`{PROJECT_SLUG}`.

## Что получится в конце

- Каталоги проекта по шаблону [vanessa-bootstrap](project-structure.md)
- Подключение к серверной ИБ из `env.json`
- Рабочие команды vrunner (выгрузка/загрузка, Конфигуратор, Предприятие)
- Установленные зависимости OneScript в `oscript_modules/`
- Настроенные MCP-серверы и навыки AI-агента
- Пакет правил **1c-rules** (AGENTS.md, rules, agents, commands, skills)
- Локальный Git и связь с GitHub

## Предварительные требования

| Компонент | Назначение |
|-----------|------------|
| [Cursor](https://cursor.com/) или VS Code | IDE |
| Расширение [1C: Platform Tools](https://marketplace.visualstudio.com/items?itemName=yellow-hammer.1c-platform-tools) | Команды 1С, vrunner, отладка |
| Расширение [1C: Platform Tools MCP](https://marketplace.visualstudio.com/items?itemName=yellow-hammer.mcp-1c-platform-tools) | MCP для агента |
| Платформа 1С **{PLATFORM_VERSION}** | `C:\Program Files\1cv8\{PLATFORM_VERSION}` |
| [.NET 8](https://dotnet.microsoft.com/download/dotnet/8.0) | Отладка 1С |
| Git | Версионирование |
| Node.js | MCP `mcp-1c-platform-tools` |
| Доступ к серверу `{SERVER}:{PORT}` | Клиент-серверная ИБ |

## 1. Открыть проект

```powershell
cd {PROJECT_ROOT}
```

В Cursor: **File → Open Folder** → каталог с файлом `packagedef` в корне.
Без `packagedef` расширение 1C: Platform Tools не активируется.

## 2. Структура каталогов проекта

Проект использует шаблон **vanessa-bootstrap** (`docs/`, `src/cf`, `features/`, `tests/` и др.).
Подробное описание дерева — в [project-structure.md](project-structure.md).

Команда **идempotent**: существующие каталоги и `README.md` не перезаписываются.

### 2.1. Через Platform Tools (рекомендуется)

**Инструменты 1С → Зависимости → Инициализировать структуру проекта**

или **Ctrl+Shift+P → `1C: Зависимости: Инициализировать структуру проекта`**.

### 2.2. Автоматически — скрипт

Для новой машины, CI или без UI расширения:

```powershell
cd {PROJECT_ROOT}
.\tools\init-project-structure.ps1
```

Скрипт читает манифест `tools/project-structure.json` (тот же набор каталогов, что у расширения).

### 2.3. Через MCP-агента

При подключённом `mcp-1c-platform-tools` попросите агента вызвать
`initializeProjectStructure` с `projectPath` = корень репозитория.

### 2.4. Проверка

```powershell
Test-Path src/cf, features, tests, tools
```

Все пути должны вернуть `True`.

> В этом репозитории структура уже создана. Шаг нужен при **новом** проекте или после `git clone`, если каталоги отсутствуют.

## 3. OneScript и OPM

### 3.1. Установка через OVM

В панели **Инструменты 1С → Зависимости**:

1. **Установить OneScript** (через OVM)
2. **Установить пакетный менеджер OneScript** (OPM)

Либо вручную в PowerShell:

```powershell
$ovm = "$env:TEMP\ovm.exe"
Invoke-WebRequest -Uri "https://github.com/oscript-library/ovm/releases/latest/download/ovm.exe" -OutFile $ovm
& $ovm install stable
& $ovm use stable
```

### 3.2. PATH — частая проблема

OVM кладёт бинарники в:

```text
%LOCALAPPDATA%\ovm\current\bin
```

После установки OVM иногда прописывает в PATH пользователя `%OVM_OSCRIPTBIN%`,
но переменная **не всегда раскрывается** — расширение не находит `oscript`/`opm`
и снова предлагает установку.

**Проверка:**

```powershell
where.exe oscript
where.exe opm
oscript -version
opm --version
```

**Исправление** — явный путь в PATH пользователя:

```powershell
$ovmBin = "$env:LOCALAPPDATA\ovm\current\bin"
[Environment]::SetEnvironmentVariable('OVM_OSCRIPTBIN', $ovmBin, 'User')

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$segments = $userPath -split ';' | Where-Object { $_ -and $_ -ne '%OVM_OSCRIPTBIN%' }
if ($segments -notcontains $ovmBin) { $segments = @($ovmBin) + $segments }
[Environment]::SetEnvironmentVariable('Path', ($segments -join ';'), 'User')
```

В `.vscode/settings.json` при необходимости добавьте OVM в PATH терминала:

```json
"terminal.integrated.env.windows": {
    "PATH": "%LOCALAPPDATA%\\ovm\\current\\bin;${env:PATH}"
}
```

Подставьте свой путь к `%LOCALAPPDATA%\ovm\current\bin`, если профиль Windows другой.

**После правки PATH полностью перезапустите Cursor** (все окна).

## 4. Подключение к информационной базе

### 4.1. `env.json` (в репозитории)

Строка подключения для vrunner — формат `/S`:

```json
"--ibconnection": "/S\"{SERVER}:{PORT}\\{PROJECT_SLUG}\""
```

Версия платформы:

```json
"--v8version": "{PLATFORM_VERSION}"
```

Учётные данные в `env.json` **не хранятся** — только в локальном профиле.

### 4.2. `env.local.json` (локально, не в git)

Создайте файл `env.local.json` в корне проекта:

```json
{
    "$schema": "https://raw.githubusercontent.com/vanessa-opensource/vanessa-runner/develop/vanessa-runner-schema.json",
    "default": {
        "--db-user": "ваш_пользователь",
        "--db-pwd": "ваш_пароль"
    }
}
```

Файл перечислен в `.gitignore`.

### 4.3. `.dev.env` (локально, не в git)

Параметры для слэш-команд и субагентов 1c-rules. Минимально заполните:

```ini
PLATFORM_VERSION=
PLATFORM_PATH={PLATFORM_PATH}
INFOBASE_KIND=server
INFOBASE_PATH={SERVER}:{PORT}/{PROJECT_SLUG}
IB_USER=ваш_пользователь
IB_PASSWORD=ваш_пароль
INFOBASE_PUBLISH_URL=http://{PROD_HOST}/{PROJECT_SLUG}/
```

**Хранилище конфигурации (обязательный вопрос при init):** спросите один раз, ведётся ли проект через хранилище 1С. Да → `CONFIG_STORAGE_ENABLED=true` + `CONFIG_STORAGE_URL` / `USER` / `PASSWORD`. Нет → `CONFIG_STORAGE_ENABLED=false` или пусто. Подробно: `TEMPLATE.md` §2, `AGENTS.md`, `.cursor/rules/configuration-storage.mdc`.

## 5. Зависимости проекта (vanessa-runner)

После того как `oscript` и `opm` доступны в PATH:

```powershell
cd {PROJECT_ROOT}
opm install -l
```

Или в UI: **Инструменты 1С → Зависимости → Установить зависимости**.

Проверка:

```powershell
.\oscript_modules\bin\vrunner.bat version
```

Ожидается версия **2.6.1** (из `packagedef`).

Каталог `oscript_modules/` не коммитится — каждый разработчик ставит зависимости локально.

## 6. Правила и навыки разработки 1С

Проекты из [1c-project-template](https://github.com/mikhailchuklay/1c-project-template) уже содержат `AGENTS.md`, `.cursor/rules/`, agents, commands, skills.  
Базовый апстрим `comol/ai_rules_1c` нужен **мейнтейнерам шаблона** (обновление самого template), не каждому проектному `/updaterules`.

### 6.1. Первая установка (только если проект без правил)

Если клонировали шаблон — этот шаг **пропустите**. Если репозиторий пустой и нет `.cursor/rules`:

```powershell
cd {PROJECT_ROOT}
$src = Join-Path $env:TEMP '1c-rules'
if (-not (Test-Path (Join-Path $src 'install.ps1'))) {
    git clone --depth 1 https://github.com/comol/ai_rules_1c.git $src
}
& "$src\install.ps1" init -Source $src
```

Установщик создаёт `.dev.env` (если нет), рендерит `.cursor/mcp.json`, копирует правила и навыки, генерирует `openspec/project.md` при наличии `Configuration.xml`.

### 6.2. Обновление правил (проект из шаблона) — основной путь

Слэш-команда **`/updaterules`** или скрипт:

```powershell
cd {PROJECT_ROOT}
# При необходимости задайте в .dev.env:
# RULES_TEMPLATE_URL=https://github.com/mikhailchuklay/1c-project-template.git
# RULES_TEMPLATE_REF=master
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-from-template.ps1
```

Скрипт клонирует/обновляет кэш шаблона и копирует `.cursor/rules`, skills (кроме Platform Tools), agents, commands, `AGENTS.md`, `.dev.env.example`.  
**Не трогает:** `.dev.env`, `memory.md`, `USER-RULES.md`, `.cursor/mcp.json`, `src/`, `openspec/specs|changes`.

После обновления: сравните diff `AGENTS.md`; новые ключи из `.dev.env.example` (например `CONFIG_STORAGE_*`) перенесите в `.dev.env`.

### 6.3. Что ставится

| Каталог / файл | Содержимое |
|----------------|------------|
| `AGENTS.md` | Всегда активные правила агента |
| `.cursor/rules/*.mdc` | On-demand правила (формы, запросы, архитектура, …) |
| `.cursor/agents/*.md` | Субагенты (`1c-developer`, `1c-explorer`, …) |
| `.cursor/commands/*.md` | Слэш-команды (`/doctor`, `/getconfigfiles`, `/deploy-and-test`, …) |
| `.cursor/skills/*/SKILL.md` | Навыки (`mcp-1c-tools`, `1c-metadata-manage`, `openspec-*`, …) |
| `USER-RULES.md`, `memory.md` | Шаблоны под проект (не перезаписываются при update) |

### 6.4. Проверка

```powershell
Test-Path AGENTS.md, .ai-rules.json, USER-RULES.md, memory.md
(Get-ChildItem .cursor\rules\*.mdc).Count    # ожидается ~29
(Get-ChildItem .cursor\skills\*\SKILL.md).Count # ожидается ~26
(Get-ChildItem .cursor\agents\*.md).Count      # ожидается ~13
```

Диагностика готовности: слэш-команда **`/doctor`**.

### 6.5. Порядок с MCP

Если MCP ставите дистрибутивом vibecoding1c.ru (`INSTALL.md`, режим 3 — `GLOBAL_ROOT`), **сначала MCP, потом 1c-rules** — установщик обнаружит внешнюю схему и не затрёт `mcp.json`. Иначе MCP рендерится из каталога 1c-rules при `init`/`update`.

## 7. MCP для AI-агента

Конфигурация проекта: `.cursor/mcp.json`.

| Сервер | Назначение |
|--------|------------|
| `mcp-1c-platform-tools` | Команды Platform Tools через IPC |
| `rlm-tools-bsl` | Локальный поиск по BSL (`127.0.0.1:9000`) |
| `1c-syntax-checker-mcp` | Проверка синтаксиса BSL |
| `1C-docs-mcp` | Справка платформы |
| `1c-templates-mcp` | Шаблоны кода |
| `1c-code-check-mcp` | 1С:Напарник |
| `1c-ssl-mcp` | БСП / SSL |
| `1c-data-mcp` | Работа с данными ИБ через HTTP-сервис |

Для Platform Tools MCP включите IPC в `.vscode/settings.json`:

```json
"1c-platform-tools.ipc.enabled": true,
"1c-platform-tools.ipc.port": 40241
```

После изменений: **Ctrl+Shift+P → Developer: Reload Window**.

### 7.1. `1c-data-mcp`

URL берётся из `INFOBASE_PUBLISH_URL` в `.dev.env`:

```text
http://{PROD_HOST}/{PROJECT_SLUG}/hs/mcp
```

Эндпоинт должен быть доступен **без пароля** (анонимный доступ в `default.vrd`).
Скрипты публикации: `deploy/mcp-publish/`.

## 8. Навыки AI-агента (skills)

Навыки — инструкции для Cursor Agent: команды Platform Tools, MCP, работа с метаданными 1С.

### 8.1. Навыки Platform Tools (команды и MCP)

В репозитории уже лежат в `.cursor/skills/` (12 навыков `1c-platform-tools-*`).

На **новой** машине или после обновления расширения:

1. **Инструменты 1С → Навыки → Добавить навыки расширения (команды и MCP)**  
   или **Ctrl+Shift+P → `1C: Навыки: Добавить навыки расширения`**
2. Выберите каталог `.cursor/skills` в корне проекта.

Команда копирует шаблоны из расширения **1C: Platform Tools**; существующие файлы не затираются.

| Навык | Назначение |
|-------|------------|
| `1c-platform-tools` | Обзор команд расширения |
| `1c-platform-tools-mcp` | Вызов MCP-инструментов Platform Tools |
| `1c-platform-tools-configuration` | Выгрузка/загрузка конфигурации |
| `1c-platform-tools-dependencies` | packagedef, opm, структура проекта |
| `1c-platform-tools-infobase` | Операции с ИБ |
| `1c-platform-tools-run` | Запуск Предприятия / Конфигуратора |
| `1c-platform-tools-test` | Vanessa, xUnit, YAxUnit |
| `1c-platform-tools-extensions` | Расширения (cfe) |
| `1c-platform-tools-external` | EPF/ERF |
| `1c-platform-tools-support` | Поддержка конфигурации |
| `1c-platform-tools-setversion` | Смена версии платформы |
| `1c-platform-tools-config` | Настройки расширения |

### 8.2. Навыки разработки 1С (cc-1c-skills)

Опционально — XML, формы, роли, СКД, метаданные:

**Инструменты 1С → Навыки → Добавить навыки разработки 1С (cc-1c-skills)**

В этом проекте уже установлены расширенные навыки (`1c-metadata-manage`, `mcp-1c-tools` и др.) в `.cursor/skills/`.

### 8.3. Проверка

```powershell
Get-ChildItem .cursor\skills\1c-platform-tools*\SKILL.md | Measure-Object
```

Ожидается **12** файлов `SKILL.md` с префиксом `1c-platform-tools`.

После добавления навыков перезагрузка окна не обязательна — агент подхватывает их при следующем запросе.

## 9. Git и GitHub

Создайте приватный репозиторий у вашего Git-провайдера и свяжите с локальным каталогом:

```powershell
git init
git remote add origin https://github.com/{ORG}/{PROJECT_SLUG}.git
```

Локально настроить автора (один раз):

```powershell
git config --global user.name "ваше_имя"
git config --global user.email "ваш_email@example.com"
```

Секреты не попадают в git: `.dev.env`, `env.local.json`, `memory.md`, `oscript_modules/`.

## 10. Первая выгрузка конфигурации

1. Убедитесь, что структура создана (шаг 2) и зависимости установлены (шаг 5).
2. В панели **Инструменты 1С → Конфигурация** выберите **Выгрузить в src/cf**.
3. Дождитесь завершения в терминале.

Альтернатива — слэш-команда `/getconfigfiles` или MCP-инструмент
`configuration_dumpToSrc`.

## 11. Проверочный чеклист

| Проверка | Команда / действие | Ожидание |
|----------|-------------------|----------|
| Структура | `Test-Path src/cf, features, tests` | все `True` |
| OneScript | `oscript -version` | `2.0.x` |
| OPM | `opm --version` | `1.x.x` |
| vrunner | `.\oscript_modules\bin\vrunner.bat version` | `2.6.1` |
| Платформа | `Test-Path "{PLATFORM_PATH}\bin\1cv8.exe"` | `True` |
| MCP IPC | Reload Window, Settings → MCP | `mcp-1c-platform-tools` connected |
| 1c-rules | `Test-Path .ai-rules.json, memory.md` | оба `True` |
| Rules | `(Get-ChildItem .cursor\rules\*.mdc).Count` | ~29 |
| Skills 1c-rules | `(Get-ChildItem .cursor\skills\*\SKILL.md).Count` | ~26 |
| Skills PT | `Get-ChildItem .cursor\skills\1c-platform-tools*\SKILL.md` | 12 файлов |
| Выгрузка | «Выгрузить в src/cf» | каталог `src/cf/` заполнен |

## 12. Типичные проблемы

### «OneScript не найден. Установить через OVM?»

OneScript установлен, но не в PATH. См. [раздел 3.2](#32-path--частая-проблема), затем перезапустите Cursor.

### «Установить зависимости» не запускается

Сначала исправьте PATH и перезапустите IDE, затем `opm install -l`.

### Команда vrunner падает с ошибкой авторизации

Проверьте `env.local.json`: `--db-user` и `--db-pwd`.

### MCP `1c-data-mcp` не подключается (401)

Настройте анонимный доступ к HTTP-сервису `mcp` на веб-публикации ИБ.
См. `deploy/mcp-publish/README.md`.

### Расширение не видит проект

В корне должен быть `packagedef`. Откройте именно корень репозитория, а не подпапку.

## 13. Структура ключевых файлов

```text
{PROJECT_SLUG}/
├── packagedef              # Маркер проекта 1С + зависимости OPM
├── env.json                # Подключение к ИБ (без паролей)
├── env.local.json          # Локальные учётные данные (gitignore)
├── .dev.env                # Параметры для агентов и слэш-команд (gitignore)
├── tools/
│   ├── vrunner.init.json   # Настройки инициализации vrunner
│   ├── project-structure.json      # Манифест vanessa-bootstrap
│   └── init-project-structure.ps1  # Скрипт инициализации каталогов
├── .vscode/
│   ├── settings.json       # Platform Tools + PATH для терминала
│   └── launch.json         # Отладка 1С
├── .cursor/
│   ├── mcp.json            # MCP-серверы
│   └── skills/             # Навыки AI-агента (Platform Tools, MCP, 1С)
├── docs/                   # Документация проекта
├── src/cf/                 # Исходники конфигурации
├── features/               # Сценарные тесты Vanessa
├── tests/                  # Модульные тесты OneScript
├── deploy/                 # Публикация HTTP-сервисов на ИБ
├── oscript_modules/        # vanessa-runner и пакеты (gitignore)
└── …                       # examples, fixtures, lib, tasks, vendor — см. project-structure.md
```

Полное дерево vanessa-bootstrap: [project-structure.md](project-structure.md).

## Связанные материалы

- [README проекта](../README.md)
- [Структура каталогов проекта](project-structure.md)
- [OpenSpec](../openspec/README.md)
- [AGENTS.md](../AGENTS.md) — правила для AI-агента
- [deploy/mcp-publish/README.md](../deploy/mcp-publish/README.md) — публикация HTTP-сервиса MCP
