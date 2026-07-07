# Внешние регламенты разработки

Проект использует собственный стек правил (`.cursor/rules/`, `AGENTS.md`, MCP, OpenSpec). Дополнительные прикладные чеклисты БСП-интеграций адаптированы из публичного регламента команды Yellow Hammer.

## Источник

| Ресурс | URL | Лицензия |
|--------|-----|----------|
| dev-rules (репозиторий) | [github.com/yellow-hammer/dev-rules](https://github.com/yellow-hammer/dev-rules) | [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) |
| dev-rules (сайт) | [yellow-hammer.github.io/dev-rules](https://yellow-hammer.github.io/dev-rules) | CC-BY-SA 4.0 |

## Что заимствовано

Структура pointer-чеклистов (не полный текст статей) — в on-demand rule:

- [`.cursor/rules/1commerce-bsp-integration-checklists.mdc`](../.cursor/rules/1commerce-bsp-integration-checklists.mdc)

Таблица `Sources & sync` внутри rule фиксирует, какие документы dev-rules легли в основу, и дату последней сверки (`Last synced`).

Project-delta (правила строже ИТС) — в:

- `dev-standards-architecture.mdc` (запросы)
- `dev-standards-forms.mdc` (UX форм)
- `extension-patterns.mdc` (multi-CFE)

## Авторитетные источники (приоритет выше dev-rules)

1. **ИТС** — `its_help` → `fetch_its` (нормативные стандарты платформы v8std)
2. **БСП / SSL** — `ssl_search` (канонический API подсистем)
3. **1С:Напарник** — `check_1c_code`, `review_1c_code` (проверка после правок)
4. **v8std.ru** — `v8std_explain_diagnostics`, `v8std_explain_snippet`, `v8std_search` → `v8std_get_page` через `v8std-mcp` ([ai.v8std.ru/mcp](https://ai.v8std.ru/mcp)) — адаптированная навигация по стандартам и мост «диагностика линтера → std»; **не заменяет** п. 1 для нормативных решений

dev-rules — curated-выжимка со ссылками на ИТС и БСП; не заменяет их.

## Как обновить заимствованные чеклисты

1. Перечитать изменённые документы в [dev-rules/docs/](https://github.com/yellow-hammer/dev-rules/tree/main/docs).
2. Проверить `ssl_search`-запросы из `1commerce-bsp-integration-checklists.mdc` — возвращают ли актуальные API.
3. Обновить rule и project-delta при необходимости.
4. Поднять даты `Last synced` в таблице `Sources & sync`.
5. Синхронизировать шаблон: `.\tools\export-project-template.ps1` → `D:\infobases-files\1c-project-template`.

## Атрибуция (CC-BY-SA 4.0)

Checklist structure adapted from [yellow-hammer/dev-rules](https://github.com/yellow-hammer/dev-rules) © Yellow Hammer contributors, licensed under [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

При существенном заимствовании новых фрагментов — сохранять атрибуцию и совместимую лицензию на производные материалы.
