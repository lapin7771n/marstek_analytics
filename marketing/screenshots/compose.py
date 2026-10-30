#!/usr/bin/env python3
"""Composes App Store screenshots from raw simulator captures. Runs on the PC, never on the Mac.

Usage: compose.py <chromium_path>
Reads raw/*.png and art/*.png, writes out/uk/<shot>.png with no alpha channel.
"""
import html
import sys
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).parent
PHONE = (1320, 2868)
PAD = (2064, 2752)
GOOD, WARN, BAD = "#3DDC97", "#FFB547", "#FF6B5E"

# crop = (x, y, w, h) in raw pixels, lifted out of the screen as a glass card.
SHOTS = [
    dict(id="iphone-1", raw="home-lasts", art="ring-green", accent=GOOD,
         lines=["Чи вистачить Marstek"], hi="до кінця відключення?", title=94,
         crop=(50, 1288, 1220, 146), crop_y=1746),
    dict(id="iphone-2", raw="home-short", art="ring-warn", accent=BAD,
         lines=["Скаже, скільки"], hi="вимкнути, щоб вистачило",
         crop=(50, 1288, 1220, 330), crop_y=1746),
    dict(id="iphone-3", raw="lock-activity-short", art="ring-warn", accent=BAD,
         lines=["Час роботи"], hi="на екрані блокування",
         crop=(40, 2040, 1240, 420), crop_y=2300),
    dict(id="iphone-4", raw="home-widgets", art="ring-green", accent=GOOD,
         lines=["Заряд і відлік"], hi="видно без\u00a0застосунку"),
    dict(id="iphone-5", raw="week", art="ring-green", accent=GOOD,
         lines=["Заряд і витрати"], hi="за весь тиждень",
         crop=(50, 1648, 1220, 696), crop_y=2000),
    dict(id="iphone-6", raw="guide", art="ring-green", accent=GOOD,
         lines=["Готово за хвилину."], hi="Без акаунта й\u00a0реклами."),
    dict(id="ipad-1", raw="ipad-home", art="ring-green", accent=GOOD, size=PAD,
         lines=["Чи вистачить батареї Marstek"], hi="до кінця відключення?", title=108),
    dict(id="ipad-2", raw="ipad-week", art="ring-green", accent=GOOD, size=PAD,
         lines=["Заряд і витрати"], hi="за весь тиждень"),
    dict(id="ipad-3", raw="ipad-guide", art="ring-green", accent=GOOD, size=PAD,
         lines=["Готово за хвилину."], hi="Без акаунта й\u00a0реклами."),
]


def page(shot):
    w, h = shot.get("size", PHONE)
    pad = w > 1500
    raw = f"../raw/{shot['raw']}.png"
    art = ROOT / "art" / f"{shot['art']}.png"
    # A phone is 1180 wide on a 1320 canvas; a tablet is 1720 wide on a 2064 canvas.
    device_w = 1720 if pad else 1180
    top = shot.get("top", 620 if not pad else 520)
    device_x = (w - device_w) / 2
    bezel = 28 if pad else 26
    radius = 90 if pad else 150
    title_size = shot.get("title", 136 if pad else 122)

    crop_html = ""
    if shot.get("crop"):
        x, y, cw, ch = shot["crop"]
        card_w = 1200
        ratio = card_w / cw
        crop_html = f"""
        <div class="card" style="left:{(w - card_w) / 2}px;top:{shot['crop_y']}px;width:{card_w}px;height:{ch * ratio}px">
          <div style="width:100%;height:100%;background:url('{raw}') no-repeat;background-size:{1320 * ratio}px auto;background-position:{-x * ratio}px {-y * ratio}px"></div>
        </div>"""

    art_html = ""
    if art.exists():
        art_size = 1050 if pad else 820
        art_html = f'<img class="art" src="../art/{shot["art"]}.png" style="width:{art_size}px;left:{w - art_size * 0.62}px;top:{-art_size * 0.16}px">'

    title = "<br>".join(html.escape(line) for line in shot["lines"])

    return f"""<!doctype html><meta charset="utf-8">
<style>
@font-face {{ font-family: Onest; src: url('../fonts/cyrillic-800.woff2'); font-weight: 800; unicode-range: U+0400-052F; }}
@font-face {{ font-family: Onest; src: url('../fonts/latin-800.woff2'); font-weight: 800; unicode-range: U+0000-03FF, U+2000-206F; }}
@font-face {{ font-family: Onest; src: url('../fonts/cyrillic-600.woff2'); font-weight: 600; unicode-range: U+0400-052F; }}
@font-face {{ font-family: Onest; src: url('../fonts/latin-600.woff2'); font-weight: 600; unicode-range: U+0000-03FF, U+2000-206F; }}
* {{ margin: 0; box-sizing: border-box; }}
body {{ width: {w}px; height: {h}px; overflow: hidden; position: relative; background: #08080B; font-family: Onest; }}
.glow {{ position: absolute; inset: 0; background:
  radial-gradient(1100px 900px at 78% 8%, {shot['accent']}2E, transparent 70%),
  radial-gradient(1300px 1000px at 10% 72%, {shot['accent']}14, transparent 72%),
  linear-gradient(180deg, #0E0E13, #070709); }}
.art {{ position: absolute; opacity: .62; filter: brightness(.82); }}
h1 {{ position: absolute; left: {96 if not pad else 172}px; right: {96 if not pad else 172}px; top: {132 if not pad else 110}px;
  color: #fff; font-size: {title_size}px; line-height: 1.06; font-weight: 800; letter-spacing: -.028em; text-wrap: balance; text-shadow: 0 4px 40px #000a; }}
h1 span {{ color: {shot['accent']}; }}
.device {{ position: absolute; left: {device_x}px; top: {top}px; width: {device_w}px; height: {h}px; padding: {bezel}px;
  border-radius: {radius}px {radius}px 0 0; background: linear-gradient(135deg, #565860, #1b1c20 22%, #101013 60%, #3c3e45);
  box-shadow: 0 60px 180px #000c, 0 0 0 2px #ffffff14 inset, 0 0 160px {shot['accent']}24; }}
.screen {{ width: 100%; height: 100%; border-radius: {radius - bezel}px {radius - bezel}px 0 0; overflow: hidden; background: #000; }}
.screen img {{ width: 100%; display: block; }}
.card {{ position: absolute; border-radius: 48px; overflow: hidden; transform: rotate(-1.2deg);
  box-shadow: 0 50px 120px #000d, 0 0 0 2px #ffffff30, 0 0 110px {shot['accent']}44; }}
</style>
<div class="glow"></div>{art_html}
<h1>{title}<br><span>{html.escape(shot['hi'])}</span></h1>
<div class="device"><div class="screen"><img src="{raw}"></div></div>{crop_html}"""


def main():
    chromium = sys.argv[1]
    work = ROOT / "html"
    out = ROOT / "out" / "uk"
    work.mkdir(exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[2:])
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=chromium)
        for shot in SHOTS:
            if only and shot["id"] not in only:
                continue
            if not (ROOT / "raw" / f"{shot['raw']}.png").exists():
                print("skip, no capture:", shot["id"])
                continue
            w, h = shot.get("size", PHONE)
            file = work / f"{shot['id']}.html"
            file.write_text(page(shot), encoding="utf-8")
            tab = browser.new_page(viewport={"width": w, "height": h})
            tab.goto(file.as_uri())
            tab.evaluate("document.fonts.ready")
            tab.wait_for_timeout(300)
            target = out / f"{shot['id']}.png"
            tab.screenshot(path=str(target))
            tab.close()
            image = Image.open(target).convert("RGB")
            image.save(target)
            if not shot.get("size"):
                medium = ROOT / "out" / "uk-6.3"
                medium.mkdir(exist_ok=True)
                image.resize((1206, 2622), Image.LANCZOS).save(medium / f"{shot['id']}.png")
            print("ok", shot["id"])
        browser.close()


if __name__ == "__main__":
    main()
