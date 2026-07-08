# Среда разработки и публикации

## Две среды

| | DEV (локально) | PROD (сервер) |
|---|----------------|---------------|
| ИБ | `build/ib` (файловая) | `{SERVER}:{PORT}/{PROJECT_SLUG}` |
| Публикация | Автономный сервер `ibsrv` | IIS на `{PROD_HOST}` |
| URL веб-клиента | `http://localhost:8314/{PROJECT_SLUG}-dev/` | `http://{PROD_HOST}/{PROJECT_SLUG}/` |
| MCP data (если настроен) | `http://localhost:8314/{PROJECT_SLUG}-dev/hs/mcp` | `http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp` |

**Правило:** в `.dev.env` параметр `INFOBASE_PUBLISH_URL` всегда указывает на **DEV**.  
PROD-адреса хранятся в `INFOBASE_PUBLISH_URL_PROD` и `INFOBASE_DATA_MCP_URL_PROD` только для справки. Агент и UI-тесты не переключаются на PROD без явного запроса.

## Linux-профиль IDE (Cursor Remote)

На Linux-хосте после clone:

```bash
bash tools/dev-env/linux/apply.sh
```

Скрипт подставляет `@PROJECT_ROOT@` в MCP/launch/settings и ставит `skip-worktree` на IDE-файлы. Подробнее: [tools/dev-env/README.md](../tools/dev-env/README.md).

## Автономный сервер (DEV)

Конфиг: `build/standalone/config.yml`  
Каталог данных: `build/standalone/data` (или `STANDALONE_DATA_PATH`)  
Порт: `STANDALONE_PORT` (по умолчанию **8314**)

```powershell
# Первичная инициализация config.yml (если ещё нет)
.\tools\dev-standalone\init-config.ps1

# Запуск / остановка / перезапуск
.\tools\dev-standalone\start.ps1
.\tools\dev-standalone\stop.ps1
.\tools\dev-standalone\restart.ps1
```

На Linux:

```bash
bash tools/dev-standalone/init-config.sh
bash tools/dev-standalone/start.sh
bash tools/dev-standalone/stop.sh
bash tools/dev-standalone/restart.sh   # после ibcmd config apply
```

### После `ibcmd config apply`

`config apply --dynamic=force --session-terminate=force` перезапускает рабочие процессы ibsrv. Если сразу после apply CF идёт import/apply расширения через `--pid`, соединение с ibcmd может оборваться.

**Правило:** после каждого `config apply` — **`restart.sh` / `restart.ps1`**, затем MCP/тесты.

Вторая частая ошибка MCP: *«Попробуйте перезапустить сеанс»* — пул HTTP-сессий держит старый код расширения. **Лечится полным перезапуском ibsrv.**

**«Зомби» ibsrv:** процесс в `pgrep`, но `curl` на публикацию даёт `000`. `stop.sh` иногда недостаточен — `restart.sh` делает `kill -9` и ждёт HTTP 200.

`start.sh` проверяет только процесс, не HTTP — при зомби используйте `restart.sh`.

Рекомендуемый порядок загрузки в dev:

1. `ibcmd … config import` (CF или CFE)
2. `ibcmd … config apply --dynamic=force --session-terminate=force`
3. `bash tools/dev-standalone/restart.sh`
4. smoke: `tools/dev-standalone/Invoke-DataMcp.ps1 code -Text 'Результат = Строка(ТекущаяДатаСеанса());'`

### Загрузка расширения (CFE)

| Сценарий | Команда | Время |
|----------|---------|-------|
| Правки BSL / существующих объектов | `bash tools/deploy-extension.sh --list build/out/extension-partial-load-<EXT>.txt` | ~1–5 мин |
| Список из objlist | `bash tools/prepare-objlist.sh` → `bash tools/deploy-extension.sh` | ~1–5 мин |
| Новые объекты метаданных | `bash tools/deploy-extension.sh --full` | ~20–40 мин |

`EXTENSION_NAME` задаётся в `.dev.env`. Перед `ibcmd --db-path=…` **останавливайте ibsrv** (`stop.sh`).

Проверка публикации:

```powershell
Invoke-WebRequest "http://localhost:8314/{PROJECT_SLUG}-dev/" -UseBasicParsing
# Ожидается StatusCode 200
```

`IBCMD_CONFIG` в `.dev.env` указывает на `build/standalone/config.yml`.

## Связь с 1c-rules

- `INFOBASE_PUBLISH_URL` — источник правды для `/deploy-and-test`, `1c-tester`, `1c-data-mcp`.
- `STANDALONE_*`, `INFOBASE_PUBLISH_URL_PROD` — описаны здесь и в `USER-RULES.md`.
