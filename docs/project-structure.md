# Структура каталогов проекта

Проект следует шаблону [vanessa-bootstrap](https://github.com/yellow-hammer/vanessa-bootstrap) —
стандартной раскладке для **1C: Platform Tools**, vanessa-runner и сценарного тестирования.

## Дерево каталогов

```text
{PROJECT_SLUG}/
├── docs/           # Документация (Markdown)
├── examples/       # Примеры кода, Gherkin, расширений
├── features/       # Сценарные тесты Vanessa (Gherkin)
├── fixtures/       # Тестовые данные и макеты
├── lib/            # Библиотеки и обработки проекта
├── src/
│   ├── cf/         # Исходники конфигурации (основной артефакт)
│   ├── cfe/        # Расширения конфигурации
│   ├── epf/        # Внешние обработки
│   ├── erf/        # Внешние отчёты
│   └── tests/      # Тестовые обработки (xUnit / Vanessa-ADD)
├── tasks/          # Скрипты и задачи OneScript
├── tests/          # Модульные тесты OneScript (*.os)
├── tools/          # Настройки vrunner, vanessa, служебные скрипты
└── vendor/         # Сторонние зависимости (не OPM)
```

Дополнительно в репозитории (не входят в vanessa-bootstrap, но используются проектом):

| Каталог | Назначение |
|---------|------------|
| `deploy/` | Скрипты публикации ИБ (MCP HTTP-сервис) |
| `openspec/` | Spec-driven development |
| `.cursor/` | MCP и навыки AI-агента |
| `.vscode/` | Настройки IDE, отладка 1С |

В каждом каталоге шаблона лежит `README.md` с кратким описанием назначения.

## Инициализация

Команда **не удаляет и не перезаписывает** существующие файлы — только создаёт отсутствующие каталоги и README.

### Вариант 1 — UI Platform Tools (рекомендуется)

1. Откройте корень проекта в Cursor.
2. **Инструменты 1С → Зависимости → Инициализировать структуру проекта**  
   или **Ctrl+Shift+P → `1C: Зависимости: Инициализировать структуру проекта`**.

### Вариант 2 — скрипт (CI / новая машина без UI)

```powershell
cd x:\dev-projects\{PROJECT_SLUG}
.\tools\init-project-structure.ps1
```

Манифест каталогов: `tools/project-structure.json`.

### Вариант 3 — MCP-агент

При подключённом `mcp-1c-platform-tools` агент может вызвать инструмент
`initializeProjectStructure` с параметром `projectPath` (корень репозитория).

## Проверка

```powershell
@('docs','examples','features','fixtures','lib','src/cf','src/cfe','tasks','tests','tools','vendor') |
  ForEach-Object { Test-Path "x:\dev-projects\{PROJECT_SLUG}\$_" }
```

Все значения должны быть `True`.

## Связанные материалы

- [Playbook: начальная настройка](initial-setup-playbook.md#2-структура-каталогов-проекта)
- [vanessa-bootstrap на GitHub](https://github.com/yellow-hammer/vanessa-bootstrap)
