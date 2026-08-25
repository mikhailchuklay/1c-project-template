---
name: 1c-configuration-storage
description: >-
  Lock, commit, label, and unlock objects in a 1C configuration storage
  (хранилище конфигурации) via Designer. Use when CONFIG_STORAGE_ENABLED=true
  and editing src/cf / IB-bound metadata, or when the user asks to capture,
  place, or label storage objects.
---

# 1C Configuration Storage

## When to load

- Rule `.cursor/rules/configuration-storage.mdc` is in scope, or
- User requests storage lock / commit / label / unlock / update from storage.

## Prerequisites

Read `.dev.env`: `CONFIG_STORAGE_*`, `PLATFORM_PATH`, `INFOBASE_PATH`, `INFOBASE_KIND`, `IB_USER`, `IB_PASSWORD`, `LOG_PATH`.

If `CONFIG_STORAGE_ENABLED` is empty or not `true` — stop; do not invent a storage URL.

Stop local `ibsrv` if it holds the IB (e.g. `tools/dev-standalone/stop.ps1`) before Designer storage ops.

## Objects list XML

Build a temporary `-objects` XML listing **only** objects to lock/commit. Do not lock unrelated objects.

## Canonical sequence

1. Optional: `/ConfigurationRepositoryUpdateCfg` when refresh is required.
2. `/ConfigurationRepositoryLock -objects <xml>`
3. Edit sources under `src/cf` (or agreed path).
4. If loading into IB: `ibcmd infobase config import files` (+ `apply`) using `INFOBASE_PATH` / `IB_USER`.
5. `/ConfigurationRepositoryCommit -objects <xml> -comment <text>`
6. `/ConfigurationRepositorySetLabel -name <label> [-comment <text>]`
7. `/ConfigurationRepositoryUnlock -objects <xml>` unless the task says keep locks.
8. Record storage version in the change report / OpenSpec `tasks.md` when relevant.

## Designer flags

```
1cv8.exe DESIGNER /F<INFOBASE_PATH> /N<IB_USER> [/P<IB_PASSWORD>]
  /ConfigurationRepositoryF<CONFIG_STORAGE_URL>
  /ConfigurationRepositoryN<CONFIG_STORAGE_USER>
  [/ConfigurationRepositoryP<CONFIG_STORAGE_PASSWORD>]
  /DisableStartupDialogs /Out<LOG>
  <Lock|Commit|SetLabel|Unlock|UpdateCfg> ...
```

Omit `/ConfigurationRepositoryP` and `/P` when passwords are empty. Use `/S` instead of `/F` when `INFOBASE_KIND=server`.

## Comment and label

- Comment: short summary + Jira URL/key and/or Omnidesk ticket link (both if both exist). Prefer a UTF-8 text file passed carefully — do not pass a bare filesystem path as the comment body (platform may store literal `File`).
- Label name: Jira key if present; else Omnidesk ticket id.

## Anti-patterns

- `/ConfigurationRepositoryUnbindCfg` — forbidden.
- `vrunner lockrepo` as primary lock — it runs UpdateCfg `-force` first and may fail with empty output; use Designer `/ConfigurationRepositoryLock`.
- Committing without label.
- Leaving objects locked after a successful commit without an explicit “keep lock” request.

## Reference scripts

Optional project-specific helpers under `tools/repo-*.py` (if present) are examples only — not a universal CLI.
