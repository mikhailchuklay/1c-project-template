---
name: instruction-screenshots
description: "Capture and annotate screenshots of the 1C client for user instructions: full-resolution capture from the X display, numbered step frames, arrows, captions, blurring of personal data. Use for «инструкция со скриншотами», «сделай скриншоты», «руководство пользователя», «памятка», step-by-step guides."
argument-hint: "[capture | annotate] [output path]"
---

# instruction-screenshots — screenshots for user instructions

The agent captures the 1C window itself, marks up the steps and hands over finished PNG files for the instruction text. No RDP client and no Windows session are involved: the 1C client runs on an X display inside the container, so the capture is taken from that display at full resolution.

## Where it works

| Environment | Display | Notes |
|---|---|---|
| Developer workplace (`dev-<name>`, GNOME over RDP) | `$DISPLAY` of the session, already set in the Cursor terminal | The session must be alive: the person is connected or disconnected without logging out. Capturing shows what is on the person's screen — say before you start clicking there. |
| Agent container (`dev-agent-*`, no desktop) | the Xvfb display of the test client, usually `:99` | Start the client with the `1c-qa-testing` skill / `qa-testclient.sh start …`; capture with `--display :99`. |

Tools come with the images `onec-desktop` / `onec-agent` from `20261119-screenshots` on: `maim` (capture), `xdotool` (windows), Pillow (`python3-pil`, markup), DejaVu fonts (Cyrillic). If `shot.py capture` reports that `maim` is missing, the container runs an older image — report it, do not install packages into the container.

## Commands

`<skill-dir>` is `.cursor/skills/instruction-screenshots/`.

```bash
# the 1C window by part of its title (activated first), or the active window, or a region
python3 <skill-dir>/scripts/shot.py capture --window "Бухгалтерия предприятия" -o docs/instructions/img/raw/01.png
python3 <skill-dir>/scripts/shot.py capture --active -o raw/02.png --delay 0.5
python3 <skill-dir>/scripts/shot.py capture --region 900x600+100+80 --display :99 -o raw/03.png

# markup: JSON list of operations, coordinates in pixels of the source image
python3 <skill-dir>/scripts/shot.py annotate raw/01.png -o img/01-open-document.png --spec '[
  {"blur":  [420, 210, 640, 236]},
  {"frame": [180, 300, 520, 330], "n": 1, "label": "Выберите организацию"},
  {"arrow": [700, 120, 530, 305]},
  {"crop":  [0, 60, 1280, 720]},
  {"max_width": 1600}
]'
```

Every call prints one JSON line (`ok`, `path`, `size` or `error`). Operations: `blur` (hide data), `dim` (darken all but one area), `frame` (box with optional step number `n` and `label`), `arrow`, `text`, `crop`, `max_width`; crop and resize are applied last. Full list — the docstring of `scripts/shot.py`.

Finding coordinates: open the raw capture and read the field positions from it; for a precise grid use the `img-grid-analysis` skill on the raw capture. For a window that does not move, `xdotool getwindowgeometry <id>` gives the offset.

## Procedure

1. **Plan the steps** from the instruction text: one action — one screenshot; numbers on the image equal step numbers in the text.
2. **Prepare the screen**: test infobase, test data, window size fixed for the whole set (resize once with `xdotool windowsize`), no unrelated windows or notifications.
3. **Capture** each step after the form has finished drawing (`--delay`); keep raw captures outside the repository (`/tmp` or the task's work directory).
4. **Annotate**: blur first, then frames and arrows, then crop to the part the reader needs.
5. **Look at every final image** before inserting it (read the PNG): marks on the right field, nothing sensitive left, text readable.
6. **Insert** into the instruction with relative links; files named `NN-what-happens.png` next to the document (e.g. `docs/instructions/<topic>/img/`).

## Rules

- **Data.** Only test infobases. Blur anything that looks like real INN/KPP, bank details, amounts, full names, phones, e-mails, logins — before saving the final file. When unsure, blur.
- **Consistency.** One color (red), one mark style and one window size per instruction. Do not mix full-screen and window captures within a step sequence.
- **Size.** Crop to what matters; `max_width` 1600 unless the document needs more. Raw full-screen captures (up to 3120×2080 on a workplace) do not go into the repository.
- **Someone else's screen.** On a workplace you capture and click on the person's live session. Ask or announce before driving their UI; never capture other applications (mail, messengers, browsers with personal tabs).
- **Re-capture after UI changes.** A screenshot is evidence of the current form; after a form or command interface change, redo the affected steps rather than editing the old images.
