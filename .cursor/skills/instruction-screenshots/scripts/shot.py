#!/usr/bin/env python3
"""Screenshots for user instructions: capture from an X display and annotate.

  shot.py capture -o step-01.png [--window TITLE | --active | --region WxH+X+Y]
                  [--display :99] [--delay 0.5] [--cursor]
  shot.py annotate step-01.png -o step-01-final.png --spec marks.json
  shot.py annotate step-01.png -o step-01-final.png --spec '[{"frame": [10, 10, 200, 40], "n": 1}]'

Capture needs maim and xdotool; annotate needs Pillow only. Spec is a JSON list applied in order,
coordinates in pixels of the source image (crop and resize come last, whatever their position):
  {"blur":  [x1, y1, x2, y2]}                       hide personal / commercial data
  {"dim":   [x1, y1, x2, y2]}                       darken everything outside the box
  {"frame": [x1, y1, x2, y2], "n": 1, "label": "…"} box, optional step number and caption
  {"arrow": [x1, y1, x2, y2]}                       arrow from (x1, y1) to (x2, y2)
  {"text":  [x, y], "label": "…"}                   caption on a light plate
  {"crop":  [x1, y1, x2, y2]}                       keep only this area
  {"max_width": 1600}                               downscale if wider
Prints one JSON line: {"ok": true, "path": …, "size": [w, h]} or {"ok": false, "error": …}.
"""
import argparse
import json
import math
import os
import pathlib
import shutil
import subprocess
import sys
import typing

COLOR = (220, 38, 38)
FONT_PATHS = ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")


def fail(msg) -> "typing.NoReturn":
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
    sys.exit(1)


def run(args, env):
    p = subprocess.run(args, env=env, text=True, capture_output=True)
    if p.returncode != 0:
        fail(f"{args[0]}: {(p.stderr or p.stdout).strip() or 'exit ' + str(p.returncode)}")
    return p.stdout.strip()


def capture(a):
    for tool in ("maim", "xdotool"):
        if not shutil.which(tool):
            fail(f"{tool} not found: the image predates onec-*:20261119-screenshots")
    env = dict(os.environ)
    if a.display:
        env["DISPLAY"] = a.display
    if not env.get("DISPLAY"):
        fail("no DISPLAY: pass --display (agent: the Xvfb display of qa-testclient.sh, usually :99)")
    cmd = ["maim", "-d", str(a.delay)]
    if not a.cursor:
        cmd.append("-u")
    if a.window or a.active:
        if a.window:
            # xdotool search exits 1 when nothing matches
            ids = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", a.window],
                                 env=env, text=True, capture_output=True).stdout.split()
            if not ids:
                fail(f"no visible window with title matching {a.window!r}")
            wid = ids[0]
            subprocess.run(["xdotool", "windowactivate", "--sync", wid], env=env, capture_output=True)
        else:
            wid = run(["xdotool", "getactivewindow"], env)
        cmd += ["-i", wid]
    elif a.region:
        cmd += ["-g", a.region]
    out = pathlib.Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    run(cmd + [str(out)], env)
    return out


def font(size):
    from PIL import ImageFont
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def box(v, im):
    x1, y1, x2, y2 = (int(round(c)) for c in v)
    x1, x2 = sorted(min(max(0, x), im.width) for x in (x1, x2))
    y1, y2 = sorted(min(max(0, y), im.height) for y in (y1, y2))
    if x2 - x1 < 2 or y2 - y1 < 2:
        fail(f"box {v} is empty or outside the image {im.width}x{im.height}")
    return x1, y1, x2, y2


def plate(d, xy, text, f, anchor="la"):
    l, t, r, b = d.textbbox(xy, text, font=f, anchor=anchor)
    d.rounded_rectangle((l - 6, t - 4, r + 6, b + 4), radius=4, fill=(255, 255, 255), outline=COLOR, width=2)
    d.text(xy, text, font=f, fill=COLOR, anchor=anchor)


def annotate(a):
    from PIL import Image, ImageDraw, ImageFilter
    try:
        spec = json.loads(pathlib.Path(a.spec).read_text(encoding="utf-8")) if os.path.exists(a.spec) else json.loads(a.spec)
    except (OSError, ValueError) as e:
        fail(f"spec: {e}")
    if not isinstance(spec, list):
        fail("spec must be a JSON list of operations")
    im = Image.open(a.image).convert("RGB")
    scale = max(1.0, im.width / 1600)  # keep marks readable on large screens
    width = max(3, int(3 * scale))
    f = font(int(20 * scale))
    crop, max_width = None, None
    for op in spec:
        if "blur" in op:
            b = box(op["blur"], im)
            region = im.crop(b)
            small = region.resize((max(1, region.width // 12), max(1, region.height // 12)))
            im.paste(small.resize(region.size).filter(ImageFilter.GaussianBlur(4)), b[:2])
        elif "dim" in op:
            b = box(op["dim"], im)
            keep = im.crop(b)
            im = Image.blend(im, Image.new("RGB", im.size, (0, 0, 0)), 0.45)
            im.paste(keep, b[:2])
        elif "frame" in op:
            b = box(op["frame"], im)
            d = ImageDraw.Draw(im)
            d.rounded_rectangle(b, radius=int(6 * scale), outline=COLOR, width=width)
            if op.get("n") is not None:
                r = int(15 * scale)
                cx, cy = max(r, b[0] - r // 2), max(r, b[1] - r // 2)
                d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=COLOR)
                d.text((cx, cy), str(op["n"]), font=f, fill=(255, 255, 255), anchor="mm")
            if op.get("label"):
                below = b[3] + int(10 * scale) + f.size < im.height
                plate(d, (b[0], b[3] + int(8 * scale)) if below else (b[0], b[1] - int(8 * scale)),
                      op["label"], f, anchor="la" if below else "ld")
        elif "arrow" in op:
            x1, y1, x2, y2 = (float(c) for c in op["arrow"])
            d = ImageDraw.Draw(im)
            ang = math.atan2(y2 - y1, x2 - x1)
            head = 18 * scale
            base = (x2 - head * 0.8 * math.cos(ang), y2 - head * 0.8 * math.sin(ang))
            d.line(((x1, y1), base), fill=COLOR, width=width + 1)
            d.polygon([(x2, y2),
                       (x2 - head * math.cos(ang - 0.45), y2 - head * math.sin(ang - 0.45)),
                       (x2 - head * math.cos(ang + 0.45), y2 - head * math.sin(ang + 0.45))], fill=COLOR)
        elif "text" in op:
            plate(ImageDraw.Draw(im), tuple(op["text"]), str(op.get("label", "")), f)
        elif "crop" in op:
            crop = box(op["crop"], im)
        elif "max_width" in op:
            max_width = int(op["max_width"])
        else:
            fail(f"unknown operation: {op}")
    if crop:
        im = im.crop(crop)
    if max_width and im.width > max_width:
        im = im.resize((max_width, round(im.height * max_width / im.width)), Image.LANCZOS)
    out = pathlib.Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out, optimize=True)
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("capture")
    c.add_argument("-o", "--output", required=True)
    g = c.add_mutually_exclusive_group()
    g.add_argument("--window", help="part of the window title, e.g. 'Бухгалтерия предприятия'")
    g.add_argument("--active", action="store_true")
    g.add_argument("--region", help="WxH+X+Y")
    c.add_argument("--display")
    c.add_argument("--delay", type=float, default=0.3)
    c.add_argument("--cursor", action="store_true", help="keep the mouse pointer")
    n = sub.add_parser("annotate")
    n.add_argument("image")
    n.add_argument("-o", "--output", required=True)
    n.add_argument("--spec", required=True, help="JSON file or inline JSON list")
    a = p.parse_args()
    out = capture(a) if a.cmd == "capture" else annotate(a)
    try:
        from PIL import Image
        size = list(Image.open(out).size)
    except Exception:
        size = None
    print(json.dumps({"ok": True, "path": str(out), "size": size}, ensure_ascii=False))


if __name__ == "__main__":
    main()
