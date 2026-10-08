"""Draws the game's own icon and boot image (no third-party art, no fonts).

    python tools/make_brand_art.py

Writes assets/ui/icon.png (256 px) and assets/ui/boot.png (1280x720).
Palette: Amber vs. Dusk (navy #1B2A4A / #0E1424, sodium #FF8A1F, amber
#FFC066, silver). The wordmark is a hand-made 5x7 block font defined below,
so nothing here comes from an installed typeface. Needs Pillow.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

NAVY = (27, 42, 74)
DUSK = (14, 20, 36)
SODIUM = (255, 138, 31)
AMBER = (255, 192, 102)
SILVER = (201, 206, 214)
ASPHALT = (22, 22, 26)

OUT = Path(__file__).resolve().parent.parent / "assets" / "ui"

GLYPHS = {
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    " ": ["00000"] * 7,
}


def text_width(text, cell):
    return len(text) * 6 * cell - cell


def draw_text(d, text, x, y, cell, colour):
    for ch in text:
        for r, row in enumerate(GLYPHS[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    d.rectangle([x + c * cell, y + r * cell, x + (c + 1) * cell - 2, y + (r + 1) * cell - 2], fill=colour)
        x += 6 * cell


def vgrad(img, top, bottom, y0, y1):
    d = ImageDraw.Draw(img)
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0 - 1)
        d.line([(0, y), (img.width, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))


def road_scene(w, h, horizon, lamps=True):
    """Night highway seen from the lane: sodium glow on the horizon, the road
    converging to a vanishing point, amber dashes, lamp heads down both sides."""
    img = Image.new("RGB", (w, h), DUSK)
    vgrad(img, DUSK, NAVY, 0, int(horizon * 0.7))
    vgrad(img, NAVY, (120, 62, 22), int(horizon * 0.7), horizon)
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([w * 0.15, horizon - h * 0.08, w * 0.85, horizon + h * 0.08], fill=(150, 70, 15))
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.05))
    img = Image.blend(img, Image.composite(glow, img, glow.convert("L")), 0.6)
    d = ImageDraw.Draw(img)
    vx = w / 2
    d.rectangle([0, horizon, w, h], fill=(10, 10, 14))
    d.polygon([(vx - w * 0.01, horizon), (vx + w * 0.01, horizon), (w * 1.05, h), (-w * 0.05, h)], fill=ASPHALT)
    # Edge lines (silver) and the amber centre dashes, spaced in perspective.
    for side in (-1, 1):
        d.line([(vx + side * w * 0.008, horizon), (vx + side * w * 0.52, h)], fill=SILVER, width=max(1, w // 300))
    z = 1.0
    while z < 40:
        t0, t1 = 1 / z, 1 / (z + 0.6)
        y0 = horizon + (h - horizon) * t0
        y1 = horizon + (h - horizon) * t1
        hw0 = max(1, w * 0.006 * t0)
        hw1 = max(1, w * 0.006 * t1)
        d.polygon([(vx - hw0, y0), (vx + hw0, y0), (vx + hw1, y1), (vx - hw1, y1)], fill=AMBER)
        z += 1.6
    if lamps:
        for side in (-1, 1):
            z = 1.2
            while z < 30:
                t = 1 / z
                x = vx + side * w * 0.62 * t
                y = horizon + (h - horizon) * t
                top = y - h * 0.9 * t
                if x < 0 or x > w or top < 0:
                    z += 2.2
                    continue
                d.line([(x, y), (x, top)], fill=(40, 40, 48), width=max(1, int(w * 0.004 * t)))
                r = max(1.5, w * 0.012 * t)
                halo = Image.new("L", (w, h), 0)
                ImageDraw.Draw(halo).ellipse([x - r * 4, top - r * 4, x + r * 4, top + r * 4], fill=90)
                halo = halo.filter(ImageFilter.GaussianBlur(r * 2))
                img.paste(SODIUM, (0, 0), halo)
                d = ImageDraw.Draw(img)
                d.ellipse([x - r, top - r * 0.6, x + r, top + r * 0.6], fill=AMBER)
                z += 2.2
    return img


def icon():
    s = 256
    scene = road_scene(s, s, int(s * 0.46), lamps=False)
    d = ImageDraw.Draw(scene)
    # Rear of a low coupe, silver, two amber tail lamps.
    cx, by = s / 2, s * 0.86
    d.polygon([(cx - 70, by), (cx + 70, by), (cx + 66, by - 34), (cx + 44, by - 62), (cx - 44, by - 62), (cx - 66, by - 34)], fill=(60, 66, 78))
    d.polygon([(cx - 40, by - 58), (cx + 40, by - 58), (cx + 52, by - 36), (cx - 52, by - 36)], fill=DUSK)
    d.rectangle([cx - 64, by - 30, cx - 30, by - 20], fill=SODIUM)
    d.rectangle([cx + 30, by - 30, cx + 64, by - 20], fill=SODIUM)
    d.rectangle([cx - 70, by - 2, cx - 50, by + 14], fill=(8, 8, 10))
    d.rectangle([cx + 50, by - 2, cx + 70, by + 14], fill=(8, 8, 10))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=44, fill=255)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(scene, (0, 0), mask)
    ImageDraw.Draw(out).rounded_rectangle([2, 2, s - 3, s - 3], radius=42, outline=AMBER, width=4)
    out.save(OUT / "icon.png")


def boot():
    w, h = 1280, 720
    img = road_scene(w, h, int(h * 0.58))
    d = ImageDraw.Draw(img)
    cell = 9
    for text, y, colour in (("NEON", int(h * 0.16), AMBER), ("OVERDRIVE", int(h * 0.16) + 9 * cell, SILVER)):
        x = (w - text_width(text, cell)) // 2
        draw_text(d, text, x + 3, y + 3, cell, DUSK)  # drop shadow
        draw_text(d, text, x, y, cell, colour)
    img.save(OUT / "boot.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    icon()
    boot()
    print("wrote", OUT / "icon.png", OUT / "boot.png")
