# Среда разработки и публикации

## Две среды

| | DEV (локально) | PROD (сервер) |
|---|----------------|---------------|
| ИБ | `build\ib` (файловая) | `{SERVER}:{PORT}/{PROJECT_SLUG}` |
| Публикация | Автономный сервер `ibsrv` | IIS на `{PROD_HOST}` |
| URL веб-клиента | `http://localhost:8314/{PROJECT_SLUG}-dev/` | `http://{PROD_HOST}/{PROJECT_SLUG}/` |
| MCP data (если настроен) | `http://localhost:8314/{PROJECT_SLUG}-dev/hs/mcp` | `http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp` |

**Правило:** в `.dev.env` параметр `INFOBASE_PUBLISH_URL` всегда указывает на **DEV**.  
PROD-адреса хранятся в `INFOBASE_PUBLISH_URL_PROD` и `INFOBASE_DATA_MCP_URL_PROD` только для справки. Агент и UI-тесты не переключаются на PROD без явного запроса.

## Автономный сервер (DEV)

Конфиг: `build/standalone/config.yml`  
Каталог данных сервера: `build/standalone/data`  
Порт: **8314** (фиксированный)

```powershell
# Первичная инициализация config.yml (если ещё нет)
.\tools\dev-standalone\init-config.ps1

# Запуск / остановка
.\tools\dev-standalone\start.ps1
.\tools\dev-standalone\stop.ps1
```

Проверка:

```powershell
Invoke-WebRequest http://localhost:8314/{PROJECT_SLUG}-dev/ -UseBasicParsing
# Ожидается StatusCode 200
```

`IBCMD_CONFIG` в `.dev.env` указывает на тот же `config.yml` — слэш-команды могут использовать `ibcmd` вместо Конфигуратора.

## Связь с 1c-rules

- `INFOBASE_PUBLISH_URL` — источник правды для `/deploy-and-test`, `1c-tester`, рендера `1c-data-mcp` в MCP.
- Дополнительные ключи `INFOBASE_PUBLISH_URL_PROD`, `STANDALONE_*` — **проектные**, описаны здесь и в `USER-RULES.md`.
