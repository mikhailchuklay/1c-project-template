# Профили локальной DEV-среды

В git лежат **нейтральные** шаблоны IDE в корне (`.vscode/settings.json`, `.vscode/launch.json`, `.cursor/mcp.json`) — они рассчитаны на Windows.

Платформенные профили — в подкаталогах:

| Профиль | Каталог | Применение |
|---------|---------|------------|
| **Linux** (Cursor Remote, ibsrv, ibcmd) | [`linux/`](linux/) | `bash tools/dev-env/linux/apply.sh` |
| **Windows** | шаблоны в корне репозитория | правки вручную + `git update-index --skip-worktree` (см. [docs/dev-environment.md](../../docs/dev-environment.md)) |

## Linux

После `git clone` / `git pull` на Linux-хосте:

```bash
bash tools/dev-env/linux/apply.sh
```

Скрипт:

1. Копирует профиль в `.vscode/settings.json`, `.vscode/launch.json`, `.cursor/mcp.json`.
2. Создаёт `env.local.json` из `env.local.example.json`, если файла ещё нет (`env.local.json` в `.gitignore`).
3. Ставит `git update-index --skip-worktree` на три IDE-файла — `git pull` на Windows-машинах не затронет вашу локальную копию на Linux, и наоборот.

Снять защиту (принять версию из git):

```bash
git update-index --no-skip-worktree .vscode/settings.json .vscode/launch.json .cursor/mcp.json
```

## Что остаётся локальным (не в git)

- `.dev.env` — параметры ИБ, платформы, публикации
- `env.local.json` — vrunner-профиль `local`
- `memory.md`

## Скрипты и задачи Linux

Bash-скрипты (`tools/dev-standalone/*.sh`, `tools/*objlist*.sh`, `tools/mcp-platform-tools-launcher.sh`, `tools/deploy-extension.sh`) — **общие для репозитория**; на Windows их просто не запускают (или используют WSL).
