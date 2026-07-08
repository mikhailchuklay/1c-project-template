# Списки частичной загрузки

Каталог для **проектных** списков путей расширения (опционально).

Автоматически генерируемые списки лежат в `build/out/`:

- `objlist-config.txt` — объекты `src/cf`
- `extension-partial-load-<ИмяРасширения>.txt` — объекты `src/cfe/<ИмяРасширения>`

Сгенерировать из корневого `objlist.txt`:

```bash
bash tools/prepare-objlist.sh
```

Использование:

```bash
bash tools/deploy-extension.sh --list build/out/extension-partial-load-<ИмяРасширения>.txt
```
