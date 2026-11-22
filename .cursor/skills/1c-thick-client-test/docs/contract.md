# Отчёт `out/thick-client-check.json`

Контракт стабилен: шаг гейта `thick-client:<сценарий>` в этот PR не входит, поля ниже он сможет читать без другого формата.

Коды процесса обёртки: `0` все шаги PASS, `1` FAIL или тайм-аут, `2` отказ запуска, `3` нет Xvfb.

Поля корня:

- `command` — командная строка, пароль заменён на `***`
- `platform` — сборка платформы, как её вернул сеанс (если сеанс не дошёл до отчёта обработки — каталог платформы из запуска)
- `infobase_kind`, `infobase` — база этого прогона, с учётом `--infobase`
- `user` — пользователь; пустая строка значит вход без `/N`
- `mode` — `Обычное приложение`, когда обработка успела записать отчёт
- `started`, `finished`
- `process_exit` — код процесса `1cv8`
- `timeout` — сработал общий тайм-аут
- `blocked_modal` — заголовок неизвестного модального окна, из‑за которого прогон остановлен
- `verdict` — `PASS` или `FAIL`
- `steps[]` — `index`, `action`, `status`, `seconds`, `error`, `rows`, `nonempty`, `pdf_error`, `ref`, `layout_key`, `print_path` (`method`, `external`, `form`, `print_form`), `print_path_note`, `call`, `files[]` (`path`, `size`, `sha256`)
- `startup_dialogs[]` — снимок и, если есть, `note` (кнопка или щелчок по доле окна)
- `out_log_tail`, `event_log`

Рядом пишется `out/thick-client-check.txt` с теми же фактами. В сдачу кладут JSON и PDF/PNG в `<task-dir>/evidence/`.
