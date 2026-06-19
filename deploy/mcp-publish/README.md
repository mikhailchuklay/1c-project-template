# Веб-публикация MCP для {PROJECT_SLUG} (IIS)

Инструкция по **отдельной** IIS-публикации HTTP-сервиса MCP для работы `1c-data-mcp` в Cursor и других MCP-клиентах.

Основана на дистрибутиве `MCP_1C_Distr` и фактической настройке сервера `{PROD_HOST}` (IIS 10, платформа 8.5.1.1302).

---

## Архитектура

```
Основная публикация                    MCP-публикация (отдельная)
/{PROJECT_SLUG}/                   /{PROJECT_SLUG}-mcp/
  ├─ тонкий клиент, веб-сервисы          ├─ только HTTP-сервис MCP
  ├─ HTTP Basic (401 без пароля)         ├─ встроенная авторизация 1С (usr в ib)
  └─ для пользователей и интеграций      └─ для MCP-клиента (без Authorization)
         │                                        │
         └──────────────┬─────────────────────────┘
                        ▼
              ИБ: Srvr="{SERVER}:{PORT}"; Ref="{PROJECT_SLUG}"
```

| Публикация | URL | Назначение |
|---|---|---|
| Основная | `http://{PROD_HOST}/{PROJECT_SLUG}/` | Работа пользователей, UI-тесты (`INFOBASE_PUBLISH_URL` в `.dev.env`) |
| MCP | `http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp` | MCP-сервер `1c-data-mcp` (`.cursor/mcp.json`) |

**`.dev.env` менять не обязательно.** `INFOBASE_PUBLISH_URL` указывает на основную публикацию; MCP живёт на отдельном URL в `.cursor/mcp.json`.

---

## Зачем отдельная публикация

MCP-клиент **не передаёт** заголовок `Authorization` на `/hs/mcp`.

Основная публикация отвечает:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Basic realm="1C:Enterprise 8.5"
```

Инструменты `1c-data-mcp` (`vcexecutecode`, `vcexecutequery`, `validatequery`, `vcloggetlasterror`) в сессии агента **не появятся**, пока endpoint требует HTTP Basic.

**Решение:** вторая публикация с **встроенной авторизацией 1С** — учётные данные технического пользователя прописаны в `default.vrd`, HTTP-запросы проходят без Basic, 1С подключается к ИБ от имени этого пользователя.

---

## Предварительные условия в ИБ

1. Установлено расширение **OneMCP.cfe** (из `MCP_1C_Distr`).
2. Создан пользователь ИБ **`mcp`** с паролем **`mcp`** (или другой — тогда поправьте `default.vrd` и параметры скрипта).
3. Пользователю назначена роль с правами:
   - **Использование** HTTP-сервиса `APA_MCP`;
   - **Чтение** (и при необходимости запись) объектов, к которым обращаются инструменты MCP.

---

## Ключевые нюансы `default.vrd`

Проверено на этом сервере. Ошибки в любом из пунктов ниже давали **HTTP 500** на корне публикации.

### 1. IIS Application — обязательно

Простого каталога в `C:\inetpub\wwwroot\` **недостаточно**. Публикация 1С на IIS должна быть зарегистрирована как **приложение** (Application), не только виртуальный каталог.

Скрипт `install-mcp-publication.ps1` делает это автоматически:

```text
appcmd add app /site.name:"Default Web Site" /path:/{PROJECT_SLUG}-mcp /physicalPath:C:\inetpub\wwwroot\{PROJECT_SLUG}-mcp
```

**Симптом без регистрации:** даже точная копия рабочего `default.vrd` из `/{PROJECT_SLUG}/` в новой папке отдаёт **HTTP 500**.

**Проверка:** `-DiagnosticCopyMain` → ожидается `HTTP root 200`.

Вручную: IIS Manager → сайт → «Преобразовать в приложение» для каталога публикации.

### 2. Каркас секций — обязателен

Нельзя публиковать **только** блок `<httpServices>`. На IIS нужен минимальный каркас, как у рабочих публикаций (`Documents`, основная `/{PROJECT_SLUG}/`):

```xml
<ws enable="false" pointEnableCommon="true" publishExtensionsByDefault="true"/>
<httpServices ...>...</httpServices>
<standardOdata enable="true" reuseSessions="autouse" sessionMaxAge="20" poolSize="10" poolTimeout="5"/>
<analytics enable="true"/>
```

`enable="false"` на `ws` / отключение OData в продакшене допустимо, но **секции должны присутствовать**.

### 3. HTTP-сервис из расширения — `publishExtensionsByDefault="true"`

HTTP-сервис MCP поставляется расширением **OneMCP**, в основной `default.vrd` его **нет**.

| Атрибут | Значение для OneMCP |
|---|---|
| `service name` (имя в метаданных) | `APA_MCP` |
| `rootUrl` (сегмент URL) | `mcp` → endpoint `/hs/mcp` |
| `publishExtensionsByDefault` | `true` на `<ws>` и `<httpServices>` |

При `publishExtensionsByDefault="false"` и явном `name="mcp"` (вместо `APA_MCP`) публикация падала с **500**.

### 4. Встроенная авторизация — в строке `ib`, одинарные кавычки

Рабочий формат (как в `MCP_1C_Distr`):

```xml
ib="Srvr=&quot;{SERVER}:{PORT}&quot;;Ref=&quot;{PROJECT_SLUG}&quot;;Usr='mcp';Pwd='mcp';"
```

- Учётные данные — в атрибуте `ib`, **не** отдельный элемент `<usr>` (на этой платформе надёжнее именно `ib`).
- Внутри строки подключения — **одинарные** кавычки: `Usr='mcp';Pwd='mcp';`.
- Неверный пользователь/пароль в `ib` → **500** (не 401).

### 5. UTF-8 без BOM

`default.vrd` должен быть **UTF-8 без BOM**. BOM (`EF BB BF` в начале файла) ломает разбор XML модулем wsisapi → **500**.

Скрипт пишет файл через `[System.IO.File]::WriteAllText` с `UTF8Encoding($false)`. Не используйте `Set-Content -Encoding UTF8` в PowerShell — добавляет BOM.

### 6. Соответствие `base` и URL

Атрибут `base` в `default.vrd` должен совпадать с URL-путём IIS:

```xml
base="/{PROJECT_SLUG}-mcp"
```

→ `http://<сервер>/{PROJECT_SLUG}-mcp/`

### 7. `web.config` — wsisapi и блок `<system.web>`

Файл состоит из **двух** обязательных частей.

**Обработчик 1С** — версия wsisapi должна совпадать с платформой, которой опубликована ИБ:

```xml
<system.webServer>
    <handlers>
        <add name="1C Web-service Extension" path="*" verb="*"
             modules="IsapiModule"
             scriptProcessor="C:\Program Files\1cv8\8.5.1.1302\bin\wsisapi.dll"
             resourceType="Unspecified" requireAccess="None" />
    </handlers>
</system.webServer>
```

**Блок `<system.web>`** — обязателен при публикации на IIS. Без него запросы к HTTP-сервисам (в т.ч. `/hs/mcp`) могут отклоняться или отдавать **500** из‑за валидации ASP.NET:

```xml
<system.web>
    <customErrors mode="Off" />
    <httpRuntime requestPathInvalidCharacters="" requestValidationMode="2.0" />
    <pages validateRequest="false" />
</system.web>
```

| Элемент | Назначение |
|---|---|
| `customErrors mode="Off"` | Показывать реальные ошибки 1С при отладке публикации |
| `requestPathInvalidCharacters=""` | Разрешить символы в URL, которые использует 1С (в т.ч. в query string MCP) |
| `requestValidationMode="2.0"` | Режим валидации запросов, совместимый с 1С |
| `pages validateRequest="false"` | Отключить проверку входящих данных ASP.NET — иначе POST-тела MCP/HTTP-сервисов могут блокироваться |

Готовый файл — `deploy/mcp-publish/web.config` (идентичен основной публикации `/{PROJECT_SLUG}/`).

---

## Файлы в каталоге

| Файл | Назначение |
|---|---|
| `default.vrd` / `default-APA_MCP.vrd` | **Продакшен** — MCP-only, OneMCP (`APA_MCP`), встроенный `mcp/mcp` |
| `default-noauth.vrd` | Диагностика без учётных данных (ожидается 401) |
| `default-all-ext-http.vrd` | Диагностика: все HTTP-сервисы расширений, без `Usr` |
| `default-copy-main-noauth.vrd` | Диагностика: копия рабочего `default.vrd` основной публикации |
| `web.config` | Обработчик ISAPI 1С |
| `install-mcp-publication.ps1` | Развёртывание + регистрация IIS Application + проверка |

---

## Развёртывание (продакшен)

PowerShell **от имени администратора**:

```powershell
powershell -ExecutionPolicy Bypass -File "X:\dev-projects\{PROJECT_SLUG}\deploy\mcp-publish\install-mcp-publication.ps1" -McpUser mcp -McpPassword mcp
```

**Ожидаемый результат:**

```text
HTTP root 200, /hs/mcp 200
Endpoint reachable without HTTP Basic auth. MCP URL: http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp
```

Коды **200 / 400 / 405 / 406** на `/hs/mcp` — нормально (endpoint доступен без Basic). Главное — **не 401 и не 500**.

---

## Диагностика при проблемах

Запускать **по порядку** (от администратора). Копировать **только одну строку** команды, без вывода предыдущих запусков.

### Шаг 1 — папка и IIS Application

```powershell
powershell -ExecutionPolicy Bypass -File "...\install-mcp-publication.ps1" -DiagnosticCopyMain
```

| Ответ | Значение |
|---|---|
| `HTTP root 200` | Папка и IIS Application в порядке |
| `HTTP root 500` | Нет Application → `appcmd add app` или «Преобразовать в приложение»; затем `iisreset` |

### Шаг 2 — структура `default.vrd` без учётных данных

```powershell
powershell -ExecutionPolicy Bypass -File "...\install-mcp-publication.ps1" -DiagnosticNoAuth
```

| Ответ | Значение |
|---|---|
| `HTTP root 401` или `200` | Структура `default.vrd` валидна |
| `HTTP 500` | Проверить каркас секций, BOM, `publishExtensionsByDefault`, имя сервиса |

### Шаг 3 — продакшен с учётными данными

```powershell
powershell -ExecutionPolicy Bypass -File "...\install-mcp-publication.ps1" -McpUser mcp -McpPassword mcp
```

| Ответ | Действие |
|---|---|
| `/hs/mcp 200` | Готово, перезапустить Cursor |
| `/hs/mcp 401` | Пользователь `mcp` не подхватывается — проверить `Usr`/`Pwd` в `ib`, существование пользователя в ИБ |
| `/hs/mcp 403` | Нет прав на HTTP-сервис `APA_MCP` |
| `/hs/mcp 404` | OneMCP не установлен или неверное `service name` |
| `/hs/mcp 500` | Неверный пароль в `ib` или повреждён `default.vrd` |

---

## Подключение MCP-клиента

В `.cursor/mcp.json` (уже настроено в проекте):

```json
"1c-data-mcp": {
  "url": "http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp",
  "connection_id": "1c_data_mcp_001"
}
```

После развёртывания **перезапустите Cursor** (или переподключите MCP-серверы), чтобы в сессии появились инструменты `1c-data-mcp`.

Проверка вручную:

```powershell
Invoke-WebRequest -Uri "http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp" -UseBasicParsing
# StatusCode должен быть 200 (или 400/405), не 401
```

---

## Сравнение с `MCP_1C_Distr` (Apache)

| Аспект | Apache (пример в дистрибутиве) | IIS (этот сервер) |
|---|---|---|
| Второй URL | `Alias "/mcptest"` → отдельная папка | `/{PROJECT_SLUG}-mcp` → отдельное **Application** |
| `default.vrd` | Только `httpServices` + `APA_MCP` | Нужен каркас `ws` / `standardOdata` / `analytics` |
| Регистрация | `SetHandler 1c-application` в `httpd.conf` | `appcmd add app` + `web.config` (wsisapi) |
| Авторизация | `Usr='...';Pwd='...';` в `ib` | То же |

---

## Безопасность

- MCP-публикация с встроенным `mcp/mcp` **не требует** HTTP Basic — endpoint доступен любому, кто знает URL. Ограничьте доступ сетью (firewall, VPN).
- Технический пользователь `mcp` должен иметь **минимально достаточные** права (только то, что нужно инструментам MCP).
- Основная публикация `/{PROJECT_SLUG}/` **не изменяется** — пользовательская аутентификация сохраняется.

---

## Откат

```powershell
# Удалить IIS Application и каталог
& "$env:windir\system32\inetsrv\appcmd.exe" delete app "Default Web Site/{PROJECT_SLUG}-mcp"
Remove-Item "C:\inetpub\wwwroot\{PROJECT_SLUG}-mcp" -Recurse -Force
```

В `.cursor/mcp.json` убрать или закомментировать `1c-data-mcp`, либо вернуть URL основной публикации (будет 401 — инструменты не заработают без отдельной MCP-публикации).

---

## Чеклист «всё работает»

- [ ] `http://{PROD_HOST}/{PROJECT_SLUG}-mcp/` → **200**
- [ ] `http://{PROD_HOST}/{PROJECT_SLUG}-mcp/hs/mcp` → **200** (не 401)
- [ ] Основная `http://{PROD_HOST}/{PROJECT_SLUG}/` → **200**, `/hs/mcp` → **401** (как и задумано)
- [ ] В Cursor после перезапуска видны инструменты `1c-data-mcp`
