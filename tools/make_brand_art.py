"""Writes the placeholder brand art for Boost Simcade into assets/brand/.

Placeholders only, until the real B4 logo files are copied over the same paths:
    assets/brand/logo_B4_combined_256.png   project icon (256 px)
    assets/brand/logo_B4_combined.ico       exe icon (16, 32, 48, 256 px)
    assets/brand/boot_splash.png            boot splash (1280x720)

Run from the repo root:  python tools/make_brand_art.py
Needs Pillow (python -m pip install pillow). Re-running overwrites the files.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

NAVY = (27, 42, 74)        # Dusk navy #1B2A4A
DEEP = (14, 20, 36)        # Dusk navy #0E1424
AMBER = (255, 192, 102)    # amber #FFC066
ORANGE = (255, 138, 31)    # sodium orange #FF8A1F
SILVER = (196, 202, 212)
BOLD = "C:/Windows/Fonts/arialbd.ttf"

OUT = Path(__file__).resolve().parent.parent / "assets" / "brand"


def turbo_mark(size: int) -> Image.Image:
    """A turbine wheel: amber rim, orange vanes, silver hub, on rounded navy."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = size * 0.04
    d.rounded_rectangle([pad, pad, size - pad, size - pad], radius=size * 0.18, fill=DEEP)
    cx = cy = size / 2
    r_out = size * 0.34
    r_in = size * 0.27
    d.ellipse([cx - r_out, cy - r_out, cx + r_out, cy + r_out], outline=AMBER, width=max(2, size // 22))
    for i in range(8):
        a = i * math.pi / 4
        x1, y1 = cx + r_in * math.cos(a), cy + r_in * math.sin(a)
        a2 = a + 0.42
        x2, y2 = cx + size * 0.10 * math.cos(a2), cy + size * 0.10 * math.sin(a2)
        d.polygon([(x1, y1), (x2, y2), (cx + size * 0.10 * math.cos(a2 - 0.5), cy + size * 0.10 * math.sin(a2 - 0.5))], fill=ORANGE)
    hub = size * 0.09
    d.ellipse([cx - hub, cy - hub, cx + hub, cy + hub], fill=SILVER)
    return img


def square_icon(size: int) -> Image.Image:
    return turbo_mark(size).resize((size, size), Image.LANCZOS)


def splash() -> Image.Image:
    w, h = 1280, 720
    img = Image.new("RGB", (w, h), NAVY)
    mark = turbo_mark(300)
    img.paste(mark, (w // 2 - 150, 110), mark)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(BOLD, 56)
    text = "BOOST SIMCADE"
    tw = d.textlength(text, font=font)
    d.text(((w - tw) / 2, 470), text, font=font, fill=AMBER)
    small = ImageFont.truetype(BOLD, 22)
    note = "PLACEHOLDER ART"
    nw = d.textlength(note, font=small)
    d.text(((w - nw) / 2, 660), note, font=small, fill=SILVER)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    square_icon(256).save(OUT / "logo_B4_combined_256.png")
    sizes = [16, 32, 48, 256]
    square_icon(256).save(OUT / "logo_B4_combined.ico", sizes=[(s, s) for s in sizes])
    splash().save(OUT / "boot_splash.png")
    (OUT / "PLACEHOLDER.txt").write_text(
        "These three files are placeholders drawn by tools/make_brand_art.py.\n"
        "Replace them with the real B4 logo files at the same paths:\n"
        "  logo_B4_combined_256.png, logo_B4_combined.ico, boot_splash.png\n",
        encoding="utf-8",
    )
    print("wrote", OUT)


if __name__ == "__main__":
    main()
