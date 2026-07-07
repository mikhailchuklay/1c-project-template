# Шаблон проекта 1С (1c-rules + Platform Tools)

Переносимый каркас для нового проекта разработки на **1С:Предприятие** с AI-агентом в Cursor.

## Репозиторий

Публичный шаблон: [github.com/mikhailchuklay/1c-project-template](https://github.com/mikhailchuklay/1c-project-template)

Изменения в `master` — через **Pull Request** (fork или feature-ветка). Прямой push в `master` — только у владельца репозитория.

```powershell
git clone https://github.com/mikhailchuklay/1c-project-template.git my-1c-project
cd my-1c-project
```

## Что входит

- Правила, skills, agents и slash-команды **1c-rules** (`.cursor/`, `AGENTS.md`)
- OpenSpec skeleton (`openspec/`)
- Инструменты: структура vanessa-bootstrap, автономный DEV-сервер, MCP helper
- **OneMCP** для `1c-data-mcp`: `vendor/mcp/OneMCP.cfe`, `vendor/mcp/ИнструментыДляРазработки.xml`
- Шаблоны настроек: `.dev.env.example`, `env.json.example`, `.cursor/mcp.json` с плейсхолдерами

## Что не входит

- Исходники конфигурации (`src/cf`, `src/cfe`) — выгружаются из вашей ИБ
- Секреты (`.dev.env`, `env.json`, `memory.md` с фактами проекта)
- Platform Tools skills — ставятся расширением VS Code / Cursor

## Быстрый старт

1. Клонируйте репозиторий (см. выше) или скопируйте каталог шаблона в новое место.
2. Переименуйте каталог под имя проекта.
3. Следуйте чеклисту в **[TEMPLATE.md](TEMPLATE.md)**.
4. Подробная настройка — [docs/initial-setup-playbook.md](docs/initial-setup-playbook.md).

## Документация

- [TEMPLATE.md](TEMPLATE.md) — чеклист инициализации нового проекта
- [docs/README.md](docs/README.md) — оглавление playbooks
