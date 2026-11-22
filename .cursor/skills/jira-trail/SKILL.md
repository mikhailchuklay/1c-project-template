---
name: jira-trail
description: "Leave a trail in the Jira issue at a work milestone — internal comment (automatic), worklog with client-readable text (after the user's yes), attachments of key artifacts. Use when .cursor/rules/jira-trail.mdc or a milestone step (repository commit, verified fix, answer delivered, PROD update, OpenSpec stage) points here."
---

# Jira trail — comment, worklog, attachments at a milestone

The team reads the Jira issue (наряд) to see what was done, how it was checked and how long it took. This skill writes that trail at each milestone. Basis: 1commerce-regulations SVC-001-R §10 (time is logged as work goes, not in bulk), SVC-007-I §6.15 (a worklog states an action and its result), SVC-024-I §3 (no splitting into 15-minute fragments).

## Preconditions

- Works only through the team's `jira` MCP server (`https://mcp.1commerce.ru/jira/mcp`, personal OAuth sign-in — records are authored by the signed-in person). Its tools are absent from the session → skip the whole skill silently; do not suggest installing anything.
- Comments are internal: the team has no Jira Service Desk, only the team reads issues. Worklogs may be shown to the client.

## Milestones

Run once per milestone of the same issue:

1. Changes placed into the configuration repository (хранилище).
2. A fix verified on the DEV infobase.
3. An answer, analysis or consultation delivered to the client / user.
4. The PROD infobase updated.
5. An OpenSpec stage finished (proposal ready, apply complete).

## Step 1 — the issue

Key, in order: named by the user in this chat → the repository commit comment (`<id> <KEY>`) or the git branch name → ask the user. Never guess a key; no key and no answer → stop here.

## Step 2 — internal comment (automatic)

Write it with `jira_add_comment` without asking, then show the posted text in the chat in one block. Technical detail is welcome — the reader is a colleague who must be able to repeat the check:

```markdown
**Сделано:** <action and result, one to three lines>
**Как проверено:** <query / tool / scenario and its result — enough to repeat>
**Осталось:** <open items, or «ничего»>
**Гипотезы:** <only if any; marked as unconfirmed>
```

No secrets (passwords, tokens, connection strings with credentials). One comment per milestone; do not post a comment that repeats the previous one.

**Issue linked to an Omnidesk ticket** (обращение) and the `omnidesk` server is in the session → write this as an internal note in the ticket by `.cursor/skills/omnidesk-correspondence/SKILL.md` instead: the note reaches the Jira issue automatically, so a Jira comment would duplicate it. Worklog and attachments (Steps 3–4) stay here.

## Step 3 — worklog (ask, then write)

**Duration.** From the previous milestone of this issue (or the start of work on it in this chat) to now; gaps in the conversation longer than 30 minutes are not counted. Call `jira_get_worklog` first and show what is already logged on the issue today, so the same work is not logged twice. The suggestion is a hint — the user's own value always wins.

**Rounding** — to the nearest 15 minutes, minimum 15m: remainder ≤ 7 min rounds down, ≥ 8 min rounds up.

| Spent | Log |
|---|---|
| 1–22 min | 15m |
| 23–37 min | 30m |
| 38–52 min | 45m |
| 53–67 min | 1h |
| 70 min | 1h 15m |

**Carry-over.** Less than 8 minutes since the last worklog of this issue → no separate entry; carry the time to the next milestone (SVC-024-I §3).

**Text — the client may read it.** Plain Russian, what was done and what came of it; no metadata object names, code, file paths, internal infobase or tool names. A hypothesis is marked as one. Two independent defects in one issue → two entries.

| Плохо | Хорошо |
|---|---|
| Доработан модуль объекта РеализацияТоваровУслуг, исправлен запрос в ПриЗаписи | Исправлено заполнение суммы в документе реализации при записи |
| Посмотрел, разобрался с обменом | Найдена причина остановки обмена с бухгалтерией: устаревший пароль; пароль обновлён, обмен прошёл |
| Мне кажется, дело в правах | Предположение (не подтверждено): ошибка связана с правами пользователя; проверка назначена на завтра |

**Ask** with an interactive choice (AskQuestion or equivalent), not a plain chat list. Show the issue key, what is already logged today, the proposed duration and text. Options: «Не списывать» · «Списать <N>» · «Своё время / текст». On yes → `jira_add_worklog` with the rounded `time_spent` and the approved `comment`; keep the default `adjust_estimate=auto`.

**Do not nag.** «Не списывать» is a normal answer. Two «Не списывать» in a row for the same issue in this session → stop asking for it until the user asks.

## Step 4 — attachments (offer)

Worth attaching: data exports, screenshots, query texts, verification reports, the effort-estimate file (SVC-001-R §917). Offer when such a file appeared at this milestone.

- The file has a URL reachable from the server (including a public Yandex.Disk link) → after the user's yes, `jira_attach_from_urls`.
- A local file only → the server cannot read container paths: name the file and its path so the user attaches it by hand.
- Never attach secrets; attach client personal data only when the issue needs it.

## Headless agent

The background agent (`.cursor/rules/headless-agent.mdc`, `dev-agent*` containers) writes the comment (Step 2) and attachments (Step 4) only. It does **not** write worklogs: time of an AI executor goes under its own Jira account (SVC-001-R §10.2.1), and until that account exists nothing is logged. Steps that would ask the user are skipped, not queued.

## Reporting

One line in the final answer when the skill ran: `Jira: <KEY> — comment; worklog 30m` (or `worklog skipped`, `no key`).
