"""Graffiti atlas (M10, 2026-10-11): our own spray-paint art, drawn here with
Pillow from the repo's OFL fonts. Nothing is downloaded.

Writes
  assets/world/graffiti/graffiti.png        1024 x 1024 RGBA
  assets/world/graffiti/graffiti_cells.json cell rects, kind, size in metres
  docs/graffiti/contact_sheet.png           every cell on a wall, labelled

Cells: 32 small (128 x 128) in rows 0..3 and 4 wide (512 x 128) in rows 4..5.
Rows 6..7 are empty (room for the crew-franchise versions later).

  12 tags      5 crew tags (Pike Speed, Gruppe 9, Kasumi Run, Diesel Row,
               Ironbridge: the rival crews in docs/story-bible.md and the
               rival proposal) and 7 writer names in real styles: handstyles
               (connected, slanted, a flourish, crown or arrow), throw-ups
               (bubble letters, two-colour fill + outline) and one small block
   4 stencils  NO PARKING, two arrows, DUNMORE in amber with a wrench under it
   4 stickers  eggshell name sticker, round silver, navy diamond, torn half
   4 posters   torn paper, abstract colour blocks, nothing readable
   4 rollers   grey buff-out patches (also the "painted over" look)
   4 spare     empty, listed, for later
   4 wide      block-letter pieces across 512 px

Paint colours are the Amber vs Dusk set plus three muted extras; nothing
bright, no magenta, no cyan. Every random draw is seeded, so the atlas is the
same on every run (the game's test checks the cells file against the PNG).

Run from the repo root:  python tools/build_graffiti_atlas.py
"""
from __future__ import annotations

import json
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "assets", "fonts")
OUT_DIR = os.path.join(ROOT, "assets", "world", "graffiti")
SHEET = os.path.join(ROOT, "docs", "graffiti", "contact_sheet.png")

ATLAS = 1024
CELL = 128
WIDE = 512
SS = 2  # supersampling: cells are drawn at 2x and downsampled for soft edges

# Paint. Names are what the cells file reports and what the game's tint test
# checks against.
PAINT = {
    "black": (18, 16, 15),
    "white": (232, 228, 220),
    "silver": (168, 170, 174),
    "amber": (255, 192, 102),
    "sodium": (255, 138, 31),
    "rust": (142, 58, 34),
    "navy": (27, 42, 74),
    "olive": (94, 91, 60),
    "oxblood": (90, 36, 36),
    "teal": (62, 94, 90),
}
# Roller buff greys (the wall's own greys, not paint colours).
ROLLER_GREYS = [(72, 70, 66), (88, 84, 78), (64, 60, 58), (96, 94, 90)]


def font(name: str, px: int, variation: str | None = None) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(os.path.join(FONTS, name), px)
    if variation:
        f.set_variation_by_name(variation)
    return f


def fit(name: str, variation: str | None, text: str, max_w: float, max_h: float, stroke_frac: float = 0.0) -> ImageFont.FreeTypeFont:
    """The largest size at which text (with its stroke) fits max_w x max_h."""
    probe = font(name, 100, variation)
    l, t, r, b = probe.getbbox(text, stroke_width=int(100 * stroke_frac))
    w, h = max(1, r - l), max(1, b - t)
    px = int(min(max_w / w, max_h / h) * 100)
    return font(name, max(8, px), variation)


# ---------------------------------------------------------------- spray look

def noise(size: tuple[int, int], rng: random.Random, cells: int = 6) -> Image.Image:
    """Low-frequency 0..255 noise: a tiny random image scaled up smoothly."""
    small = Image.new("L", (cells, cells))
    small.putdata([rng.randint(0, 255) for _ in range(cells * cells)])
    return small.resize(size, Image.BILINEAR)


def fade(mask: Image.Image, rng: random.Random, lo: float = 0.72) -> Image.Image:
    """Multiplies the mask by soft noise so the paint is uneven, never flat."""
    n = noise(mask.size, rng, 5).point(lambda v: int(255 * (lo + (1.0 - lo) * v / 255.0)))
    return _mul(mask, n)


def _mul(a: Image.Image, b: Image.Image) -> Image.Image:
    from PIL import ImageChops
    return ImageChops.multiply(a, b)


def soften(mask: Image.Image, radius: float = 1.4) -> Image.Image:
    """Spray edge: a slight blur then a push back toward solid in the middle."""
    return mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: min(255, int(v * 1.25)))


def overspray(mask: Image.Image, rng: random.Random, count: int, spread: float, alpha: int = 70) -> Image.Image:
    """Fine dots around the edge of the stroke, where a can mists the wall."""
    w, h = mask.size
    edge = _mul(mask.filter(ImageFilter.MaxFilter(5)), mask.point(lambda v: 255 - v))
    px = edge.load()
    pts = [(x, y) for y in range(0, h, 2) for x in range(0, w, 2) if px[x, y] > 40]
    if not pts:
        return mask
    out = mask.copy()
    d = ImageDraw.Draw(out)
    for _ in range(count):
        x, y = rng.choice(pts)
        r = rng.random() ** 2 * spread
        a = rng.random() * math.tau
        cx, cy = x + math.cos(a) * r, y + math.sin(a) * r
        rad = rng.uniform(0.6, 1.8) * SS * 0.5
        d.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=int(alpha * rng.uniform(0.4, 1.0)))
    return out


def drips(mask: Image.Image, rng: random.Random, count: int, length: tuple[int, int]) -> Image.Image:
    """Runs under the heaviest strokes: thin lines down from the bottom edge
    with a bead at the end."""
    w, h = mask.size
    px = mask.load()
    bottoms = [(x, y) for y in range(2, h - 2) for x in range(2, w - 2, 3)
               if px[x, y] > 200 and px[x, y + 2] < 60]
    out = mask.copy()
    d = ImageDraw.Draw(out)
    for _ in range(min(count, len(bottoms))):
        x, y = rng.choice(bottoms)
        ln = rng.randint(*length) * SS
        wd = rng.uniform(1.0, 2.2) * SS
        d.line((x, y, x + rng.uniform(-1, 1) * SS, y + ln), fill=235, width=int(wd))
        bead = wd * rng.uniform(0.9, 1.5)
        d.ellipse((x - bead, y + ln - bead, x + bead, y + ln + bead), fill=240)
    return out


def paint(canvas: Image.Image, mask: Image.Image, colour: tuple[int, int, int], rng: random.Random,
          spray: float = 1.0, drip: int = 0, drip_len: tuple[int, int] = (6, 22), faded: float = 0.72) -> None:
    """Lays one colour onto the canvas through a mask with the spray look."""
    m = soften(mask, 1.2 * spray) if spray > 0 else mask
    if drip:
        m = drips(m, rng, drip, drip_len)
    if spray > 0:
        m = overspray(m, rng, int(140 * spray), 9.0 * SS * spray)
    m = fade(m, rng, faded)
    layer = Image.new("RGBA", canvas.size, colour + (0,))
    layer.putalpha(m)
    canvas.alpha_composite(layer)


# ---------------------------------------------------------------- lettering

def text_mask(size: tuple[int, int], text: str, fnt: ImageFont.FreeTypeFont, stroke: int = 0,
              shear: float = 0.0, scale_y: float = 1.0, dx: int = 0, dy: int = 0, rot: float = 0.0) -> Image.Image:
    """White text centred on a black mask, sheared (handstyle slant), scaled,
    nudged and rotated."""
    w, h = size
    big = Image.new("L", (w * 2, h * 2), 0)
    d = ImageDraw.Draw(big)
    d.text((w, h), text, font=fnt, fill=255, anchor="mm", stroke_width=stroke, stroke_fill=255)
    if scale_y != 1.0:
        big = big.resize((big.width, max(1, int(big.height * scale_y))), Image.BICUBIC)
    if shear:
        big = big.transform(big.size, Image.AFFINE, (1, shear, -shear * big.height / 2, 0, 1, 0), Image.BICUBIC)
    if rot:
        big = big.rotate(rot, Image.BICUBIC)
    cx, cy = big.width // 2 - dx, big.height // 2 - dy
    return big.crop((cx - w // 2, cy - h // 2, cx - w // 2 + w, cy - h // 2 + h))


def bubble(mask: Image.Image, grow: int) -> Image.Image:
    """Rounds a letter mask into throw-up bubbles: dilate, blur, threshold."""
    m = mask.filter(ImageFilter.MaxFilter(5))
    m = m.filter(ImageFilter.GaussianBlur(grow * 0.5)).point(lambda v: 255 if v > 128 else 0)
    return m.filter(ImageFilter.GaussianBlur(0.8)).point(lambda v: 255 if v > 128 else 0)


def ring(mask: Image.Image, width: int) -> Image.Image:
    """The outline band just outside a mask."""
    outer = mask
    for _ in range(max(1, width)):
        outer = outer.filter(ImageFilter.MaxFilter(3))
    return _mul(outer, mask.point(lambda v: 255 - v))


def polyline_mask(size: tuple[int, int], pts: list[tuple[float, float]], width: float) -> Image.Image:
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.line(pts, fill=255, width=int(width), joint="curve")
    return m


def curve(p0, p1, p2, n=18):
    """Quadratic bezier points."""
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in (i / n for i in range(n + 1))]


# ---------------------------------------------------------------- cell kinds

def cell_canvas(wide: bool = False) -> Image.Image:
    return Image.new("RGBA", ((WIDE if wide else CELL) * SS, CELL * SS), (0, 0, 0, 0))


def handstyle(name: str, colour: str, rng: random.Random, flourish: str, wide: bool = False, px: int = 86) -> Image.Image:
    """A one-liner tag: Caveat Bold, slanted, marker stroke, with a flourish
    under it, a crown over it, an arrow off the last letter or a halo on the
    first. A two-word name is stacked, the second word stepped right."""
    c = cell_canvas(wide)
    w, h = c.size
    shear = rng.uniform(-0.36, -0.2)
    rot = rng.uniform(-8, 2)
    room = 0.72 if flourish == "arrow" else 0.84
    stroke = int(1.3 * SS)
    words = name.split(" ")
    m = Image.new("L", c.size, 0)
    if len(words) == 1:
        fnt = fit("Caveat.ttf", "Bold", name, w * room * (1.0 - abs(shear) * 0.4), h * 0.6, 0.02)
        fnt = font("Caveat.ttf", min(fnt.size, px * SS), "Bold")
        m = text_mask(c.size, name, fnt, stroke=stroke, shear=shear, dy=int(4 * SS), rot=rot)
    else:
        for i, wd in enumerate(words):
            fnt = fit("Caveat.ttf", "Bold", wd, w * room * 0.9 * (1.0 - abs(shear) * 0.4), h * 0.4, 0.02)
            fnt = font("Caveat.ttf", min(fnt.size, px * SS), "Bold")
            step = (i - (len(words) - 1) / 2)
            m.paste(255, None, text_mask(c.size, wd, fnt, stroke=stroke, shear=shear,
                                         dx=int(step * 12 * SS), dy=int(step * 34 * SS + 2 * SS), rot=rot))
    bbox = m.getbbox() or (0, 0, w, h)
    if flourish == "under":
        y = bbox[3] + 3 * SS
        pts = curve((bbox[0] - 4 * SS, y - 6 * SS), (w * 0.55, y + 12 * SS), (bbox[2] + 10 * SS, y - 10 * SS))
        m.paste(255, None, polyline_mask(c.size, pts, 3.0 * SS))
    elif flourish == "crown":
        cx = (bbox[0] + bbox[2]) * 0.5 + rng.uniform(-14, 14) * SS
        y = bbox[1] - 2 * SS
        s = 9 * SS
        pts = [(cx - s * 1.6, y), (cx - s * 1.5, y - s * 0.9), (cx - s * 0.7, y - s * 0.3), (cx, y - s * 1.3),
               (cx + s * 0.7, y - s * 0.3), (cx + s * 1.5, y - s * 0.9), (cx + s * 1.6, y)]
        m.paste(255, None, polyline_mask(c.size, pts + [pts[0]], 2.6 * SS))
    elif flourish == "arrow":
        x, y = bbox[2] - 2 * SS, bbox[1] + (bbox[3] - bbox[1]) * 0.45
        tip = (min(w - 4 * SS, x + 22 * SS), y - 14 * SS)
        pts = curve((x - 8 * SS, bbox[3] - 4 * SS), (x + 6 * SS, y + 6 * SS), tip)
        m.paste(255, None, polyline_mask(c.size, pts, 2.8 * SS))
        head = [(tip[0], tip[1]), (tip[0] - 11 * SS, tip[1] + 1 * SS), (tip[0] - 2 * SS, tip[1] + 11 * SS)]
        m.paste(255, None, polyline_mask(c.size, head, 2.8 * SS))
    elif flourish == "halo":
        # a quick ring round the first letter, the way a tag gets a halo
        cx, cy = bbox[0] + 14 * SS, bbox[1] + 4 * SS
        hm = Image.new("L", c.size, 0)
        ImageDraw.Draw(hm).ellipse((cx - 16 * SS, cy - 7 * SS, cx + 16 * SS, cy + 7 * SS), outline=255, width=int(2.6 * SS))
        m.paste(255, None, hm)
    paint(c, m, PAINT[colour], rng, spray=0.55, drip=rng.randint(1, 3), drip_len=(5, 16))
    return c


def letter_masks(size: tuple[int, int], text: str, fnt: ImageFont.FreeTypeFont, overlap: float, stroke: int,
                 shear: float, rot: float) -> list[Image.Image]:
    """One mask per letter, the letters set with their sides overlapping by
    `overlap` of their width, the whole word centred."""
    w, h = size
    widths = []
    for ch in text:
        l, t, r, b = fnt.getbbox(ch, stroke_width=stroke)
        widths.append(r - l)
    adv = [wd * (1.0 - overlap) for wd in widths]
    total = sum(adv[:-1]) + widths[-1]
    x = (w - total) / 2
    masks = []
    big = (w, h)
    for ch, wd, a in zip(text, widths, adv):
        if ch != " ":
            m = Image.new("L", big, 0)
            ImageDraw.Draw(m).text((x + wd / 2, h / 2), ch, font=fnt, fill=255, anchor="mm", stroke_width=stroke, stroke_fill=255)
            masks.append(m)
        x += a
    out = []
    for m in masks:
        if shear:
            m = m.transform(m.size, Image.AFFINE, (1, shear, -shear * h / 2, 0, 1, 0), Image.BICUBIC)
        if rot:
            m = m.rotate(rot, Image.BICUBIC)
        out.append(m)
    return out


def throwup(name: str, fill: str, outline: str, rng: random.Random, wide: bool = False, px: int = 74) -> Image.Image:
    """Bubble letters, each one filled in two tones and outlined over the
    letter before it, the way a quick throw-up overlaps."""
    c = cell_canvas(wide)
    w, h = c.size
    fnt = fit("Overpass.ttf", "Black", name, w * 0.86, h * 0.56)
    fnt = font("Overpass.ttf", min(fnt.size, px * SS), "Black")
    shear = rng.uniform(-0.12, 0.08)
    rot = rng.uniform(-6, 6)
    half = Image.new("L", c.size, 0)
    ImageDraw.Draw(half).polygon([(0, 0), (w, 0), (w, int(h * 0.3)), (0, int(h * 0.62))], fill=255)
    lighter = tuple(min(255, int(v * 0.72 + 70)) for v in PAINT[fill])
    for m in letter_masks(c.size, name, fnt, 0.1, int(0.8 * SS), shear, rot):
        bub = bubble(m, 3 * SS)
        paint(c, bub, PAINT[fill], rng, spray=0.5, faded=0.8)
        paint(c, _mul(bub.filter(ImageFilter.MinFilter(5)), half), lighter, rng, spray=0.3, faded=0.85)
        paint(c, ring(bub, 2 * SS), PAINT[outline], rng, spray=0.4, drip=rng.randint(0, 1), drip_len=(6, 18), faded=0.85)
    return c


def block_piece(name: str, face: str, shade: str, outline: str, rng: random.Random, wide: bool = True, px: int = 96) -> Image.Image:
    """Block letters with a 3-D drop: shade colour stepped down-right under the
    face, then the face, then an outline. The wide cells use this."""
    c = cell_canvas(wide)
    w, h = c.size
    fnt = fit("BigShouldersDisplay.ttf", "Black", name, w * 0.84, h * 0.62)
    fnt = font("BigShouldersDisplay.ttf", min(fnt.size, px * SS), "Black")
    shear = rng.uniform(-0.1, 0.1)
    rot = rng.uniform(-3, 3)
    face_m = text_mask(c.size, name, fnt, stroke=int(1.2 * SS), shear=shear, scale_y=1.12, rot=rot, dy=int(-3 * SS))
    depth = int(rng.uniform(6, 10) * SS)
    shade_m = Image.new("L", c.size, 0)
    for i in range(1, depth + 1):
        shade_m.paste(255, (i, i), face_m)
    paint(c, shade_m, PAINT[shade], rng, spray=0.5, faded=0.78)
    paint(c, face_m, PAINT[face], rng, spray=0.6, drip=rng.randint(2, 4), drip_len=(8, 26), faded=0.8)
    # a thin highlight on the top-left of the face
    hi = _mul(face_m.filter(ImageFilter.MinFilter(3)), ring(face_m.filter(ImageFilter.MinFilter(7)), 3 * SS))
    lighter = tuple(min(255, int(v * 0.6 + 100)) for v in PAINT[face])
    paint(c, hi, lighter, rng, spray=0.3, faded=0.9)
    paint(c, ring(face_m, 3 * SS), PAINT[outline], rng, spray=0.4, faded=0.85)
    return c


def stencil_text_mask(size, lines: list[str], px: int, bridges: bool = True) -> Image.Image:
    """Cut-stencil lettering: Barlow Condensed with thin bridges cut across."""
    fnt = font("BarlowCondensed-SemiBold.ttf", px * SS)
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    w, h = size
    n = len(lines)
    for i, ln in enumerate(lines):
        y = h * 0.5 + (i - (n - 1) / 2) * px * SS * 1.05
        d.text((w / 2, y), ln, font=fnt, fill=255, anchor="mm")
    if bridges:
        bd = ImageDraw.Draw(m)
        for i, ln in enumerate(lines):
            y = h * 0.5 + (i - (n - 1) / 2) * px * SS * 1.05
            bd.line((0, y - px * SS * 0.18, w, y - px * SS * 0.18), fill=0, width=int(1.6 * SS))
            bd.line((0, y + px * SS * 0.2, w, y + px * SS * 0.2), fill=0, width=int(1.6 * SS))
    return m


def stencil(kind: str, rng: random.Random) -> Image.Image:
    c = cell_canvas()
    w, h = c.size
    if kind == "no_parking":
        m = stencil_text_mask(c.size, ["NO", "PARKING"], 36)
        paint(c, m, PAINT["white"], rng, spray=1.1, drip=2, drip_len=(4, 12), faded=0.6)
    elif kind == "arrow":
        m = Image.new("L", c.size, 0)
        d = ImageDraw.Draw(m)
        d.rectangle((w * 0.18, h * 0.42, w * 0.62, h * 0.58), fill=255)
        d.polygon([(w * 0.58, h * 0.25), (w * 0.86, h * 0.5), (w * 0.58, h * 0.75)], fill=255)
        paint(c, m, PAINT["white"], rng, spray=1.0, faded=0.65)
    elif kind == "arrow_turn":
        m = Image.new("L", c.size, 0)
        d = ImageDraw.Draw(m)
        d.rectangle((w * 0.22, h * 0.45, w * 0.58, h * 0.6), fill=255)
        d.rectangle((w * 0.5, h * 0.3, w * 0.58, h * 0.6), fill=255)
        d.polygon([(w * 0.38, h * 0.32), (w * 0.54, h * 0.1), (w * 0.7, h * 0.32)], fill=255)
        paint(c, m, PAINT["amber"], rng, spray=1.0, faded=0.65)
    elif kind == "dunmore":
        m = stencil_text_mask(c.size, ["DUNMORE"], 34)
        # the wrench under it: handle plus two open jaws
        d = ImageDraw.Draw(m)
        y = h * 0.72
        d.line((w * 0.24, y + 4 * SS, w * 0.72, y - 4 * SS), fill=255, width=int(5 * SS))
        for x, s in ((w * 0.22, 1), (w * 0.74, -1)):
            yy = y + 4 * SS if s > 0 else y - 4 * SS
            d.ellipse((x - 9 * SS, yy - 9 * SS, x + 9 * SS, yy + 9 * SS), fill=255)
            # the open jaw: a notch cut into the outer side of each end
            d.rectangle((x - 3 * SS - s * 7 * SS, yy - 10 * SS, x + 3 * SS - s * 7 * SS, yy + 10 * SS), fill=0)
        paint(c, m, PAINT["amber"], rng, spray=1.0, drip=2, drip_len=(4, 10), faded=0.65)
    return c


def sticker(kind: str, rng: random.Random) -> Image.Image:
    """Slaps: flat printed paper, so no spray; a little curl and grime."""
    c = cell_canvas()
    w, h = c.size
    d = ImageDraw.Draw(c)
    if kind == "eggshell":
        d.rounded_rectangle((w * 0.12, h * 0.2, w * 0.88, h * 0.8), radius=8 * SS, fill=PAINT["white"] + (255,))
        d.rectangle((w * 0.12, h * 0.2, w * 0.88, h * 0.38), fill=PAINT["rust"] + (255,))
        d.rounded_rectangle((w * 0.12, h * 0.2, w * 0.88, h * 0.8), radius=8 * SS, outline=PAINT["rust"] + (255,), width=int(2 * SS))
        name = Image.new("RGBA", c.size, (0, 0, 0, 0))
        fnt = font("Caveat.ttf", 44 * SS, "Bold")
        m = text_mask(c.size, "SOAK", fnt, stroke=int(1.2 * SS), shear=-0.25, dy=int(-8 * SS), rot=-4)
        layer = Image.new("RGBA", c.size, PAINT["black"] + (0,))
        layer.putalpha(m)
        c.alpha_composite(layer)
    elif kind == "round":
        d.ellipse((w * 0.2, h * 0.2, w * 0.8, h * 0.8), fill=PAINT["silver"] + (255,))
        d.ellipse((w * 0.27, h * 0.27, w * 0.73, h * 0.73), outline=PAINT["navy"] + (255,), width=int(3 * SS))
        d.ellipse((w * 0.4, h * 0.4, w * 0.6, h * 0.6), fill=PAINT["navy"] + (255,))
    elif kind == "diamond":
        d.polygon([(w * 0.5, h * 0.12), (w * 0.88, h * 0.5), (w * 0.5, h * 0.88), (w * 0.12, h * 0.5)], fill=PAINT["navy"] + (255,))
        d.polygon([(w * 0.5, h * 0.24), (w * 0.76, h * 0.5), (w * 0.5, h * 0.76), (w * 0.24, h * 0.5)], outline=PAINT["amber"] + (255,), width=int(2.5 * SS))
    elif kind == "torn":
        pts = [(w * 0.15, h * 0.22), (w * 0.85, h * 0.2), (w * 0.86, h * 0.5)]
        x = w * 0.86
        while x > w * 0.15:
            pts.append((x, h * rng.uniform(0.5, 0.66)))
            x -= w * 0.07
        pts.append((w * 0.14, h * 0.55))
        d.polygon(pts, fill=PAINT["white"] + (255,))
        d.rectangle((w * 0.15, h * 0.22, w * 0.85, h * 0.3), fill=PAINT["olive"] + (255,))
    # grime over the paper so it reads as old
    g = noise(c.size, rng, 4).point(lambda v: int(v * 0.35))
    dark = Image.new("RGBA", c.size, (20, 16, 12, 0))
    dark.putalpha(_mul(g, c.getchannel("A")))
    c.alpha_composite(dark)
    return c


def torn_poster(i: int, rng: random.Random) -> Image.Image:
    """Layers of old paper, edges torn, blank or with abstract colour blocks.
    No letters at all."""
    c = cell_canvas()
    w, h = c.size
    papers = [PAINT["white"], (205, 196, 178), (188, 176, 160), (214, 206, 190)]
    blocks = [PAINT["rust"], PAINT["olive"], PAINT["teal"], PAINT["oxblood"], PAINT["navy"], PAINT["amber"]]
    for layer in range(2 + (i % 2)):
        pts = []
        x0, y0 = w * rng.uniform(0.04, 0.2), h * rng.uniform(0.04, 0.18)
        x1, y1 = w * rng.uniform(0.78, 0.96), h * rng.uniform(0.7, 0.96)
        # the torn edge is the bottom and one side
        pts += [(x0, y0), (x1, y0)]
        y = y0
        while y < y1:
            pts.append((x1 + rng.uniform(-6, 2) * SS, y))
            y += rng.uniform(6, 14) * SS
        x = x1
        while x > x0:
            pts.append((x, y1 + rng.uniform(-10, 4) * SS))
            x -= rng.uniform(6, 14) * SS
        pts.append((x0, y1 * rng.uniform(0.8, 1.0)))
        pm = Image.new("L", c.size, 0)
        ImageDraw.Draw(pm).polygon(pts, fill=255)
        paper = Image.new("RGBA", c.size, rng.choice(papers) + (255,))
        if rng.random() < 0.8:
            bd = ImageDraw.Draw(paper)
            for _ in range(rng.randint(1, 3)):
                bx0, by0 = w * rng.uniform(0.1, 0.5), h * rng.uniform(0.1, 0.5)
                bd.rectangle((bx0, by0, bx0 + w * rng.uniform(0.15, 0.45), by0 + h * rng.uniform(0.08, 0.35)),
                             fill=rng.choice(blocks) + (255,))
        paper.putalpha(_mul(pm, noise(c.size, rng, 5).point(lambda v: 200 + v // 5)))
        c.alpha_composite(paper)
    # water stain
    g = noise(c.size, rng, 3).point(lambda v: int(v * 0.3))
    dark = Image.new("RGBA", c.size, (40, 30, 20, 0))
    dark.putalpha(_mul(g, c.getchannel("A")))
    c.alpha_composite(dark)
    return c


def roller_patch(i: int, rng: random.Random) -> Image.Image:
    """A buff-out: a roller's rectangle of flat grey, slightly uneven, with the
    streaks a roller leaves and a soft edge."""
    c = cell_canvas()
    w, h = c.size
    grey = ROLLER_GREYS[i % len(ROLLER_GREYS)]
    m = Image.new("L", c.size, 0)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = w * 0.06, h * 0.1, w * 0.94, h * 0.9
    d.rectangle((x0, y0, x1, y1), fill=255)
    # roller strokes: the edge is uneven where the roller stopped
    for k in range(5):
        yy = y0 + (y1 - y0) * k / 5
        d.rectangle((x0 - rng.uniform(0, 6) * SS, yy, x1 + rng.uniform(-6, 6) * SS, yy + (y1 - y0) / 5 + 2), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(1.5 * SS))
    streak = Image.new("L", c.size, 255)
    sd = ImageDraw.Draw(streak)
    for k in range(5):
        yy = y0 + (y1 - y0) * (k + rng.uniform(0.3, 0.7)) / 5
        sd.line((x0, yy, x1, yy + rng.uniform(-3, 3) * SS), fill=rng.randint(200, 235), width=int(2 * SS))
    m = _mul(m, _mul(streak, noise(c.size, rng, 4).point(lambda v: 215 + v // 7)))
    layer = Image.new("RGBA", c.size, grey + (0,))
    layer.putalpha(m)
    c.alpha_composite(layer)
    return c


# ---------------------------------------------------------------- the atlas

def build() -> tuple[Image.Image, list[dict]]:
    atlas = Image.new("RGBA", (ATLAS, ATLAS), (0, 0, 0, 0))
    cells: list[dict] = []
    small: list[tuple[str, str, Image.Image, list[float], str]] = []  # id, kind, image, metres, colours

    def tag(cid, img, colours, metres=(1.3, 1.3), kind="tag"):
        small.append((cid, kind, img, list(metres), colours))

    r = random.Random(1011)
    # (a) crew tags, (b) writer names: handstyles, throw-ups, one small block
    tag("tag_pike_speed", handstyle("Pike Speed", "white", r, "under", px=78), "white")
    tag("tag_gruppe_9", handstyle("Gruppe 9", "silver", r, "crown"), "silver")
    tag("tag_kasumi_run", handstyle("Kasumi Run", "amber", r, "arrow", px=74), "amber")
    tag("tag_diesel_row", block_piece("DIESEL", "rust", "black", "white", r, wide=False, px=66), "rust black white")
    tag("tag_ironbridge", handstyle("Ironbridge", "sodium", r, "crown", px=70), "sodium")
    tag("tag_kemr", throwup("KEMR", "white", "black", r), "white black")
    tag("tag_soak", throwup("SOAK", "amber", "oxblood", r), "amber oxblood")
    tag("tag_dusk", handstyle("DUSK", "silver", r, "arrow"), "silver")
    tag("tag_riot2", throwup("RIOT2", "white", "navy", r, px=64), "white navy")
    tag("tag_meks", handstyle("MEKS", "teal", r, "crown"), "teal")
    tag("tag_zeal", throwup("ZEAL", "olive", "black", r), "olive black")
    tag("tag_husk", handstyle("HUSK", "oxblood", r, "halo"), "oxblood")
    # stencils
    tag("stencil_no_parking", stencil("no_parking", r), "white", (0.7, 0.7), "stencil")
    tag("stencil_arrow", stencil("arrow", r), "white", (0.6, 0.6), "stencil")
    tag("stencil_arrow_turn", stencil("arrow_turn", r), "amber", (0.6, 0.6), "stencil")
    tag("stencil_dunmore", stencil("dunmore", r), "amber", (0.8, 0.8), "stencil")
    # stickers
    for k in ("eggshell", "round", "diamond", "torn"):
        tag("sticker_" + k, sticker(k, r), "paper", (0.28, 0.28), "sticker")
    # torn posters
    for i in range(4):
        tag("poster_%d" % i, torn_poster(i, r), "paper", (1.0, 1.0), "poster")
    # roller patches
    for i in range(4):
        tag("roller_%d" % i, roller_patch(i, r), "grey", (1.8, 1.8), "roller")
    # spare
    for i in range(4):
        tag("spare_%d" % i, cell_canvas(), "", (1.0, 1.0), "spare")
    assert len(small) == 32, len(small)

    for i, (cid, kind, img, metres, colours) in enumerate(small):
        x, y = (i % 8) * CELL, (i // 8) * CELL
        atlas.alpha_composite(img.resize((CELL, CELL), Image.LANCZOS), (x, y))
        cells.append({"id": cid, "kind": kind, "rect": [x, y, CELL, CELL], "metres": metres, "colours": colours})

    wide = [
        ("piece_pike_speed", block_piece("PIKE SPEED", "white", "navy", "black", r, px=104), "white navy black"),
        ("piece_kasumi_run", block_piece("KASUMI RUN", "amber", "oxblood", "black", r, px=104), "amber oxblood black"),
        ("piece_gruppe_9", block_piece("GRUPPE 9", "silver", "black", "sodium", r, px=104), "silver black sodium"),
        ("piece_dusk", block_piece("DUSK", "sodium", "rust", "black", r, px=108), "sodium rust black"),
    ]
    for i, (cid, img, colours) in enumerate(wide):
        x, y = (i % 2) * WIDE, 4 * CELL + (i // 2) * CELL
        atlas.alpha_composite(img.resize((WIDE, CELL), Image.LANCZOS), (x, y))
        cells.append({"id": cid, "kind": "piece", "rect": [x, y, WIDE, CELL], "metres": [5.2, 1.3], "colours": colours})
    return atlas, cells


def contact_sheet(atlas: Image.Image, cells: list[dict]) -> Image.Image:
    """Every cell on a dusk-brown wall, labelled, for the PR."""
    pad, label_h = 10, 16
    cols = 8
    smalls = [c for c in cells if c["kind"] != "piece"]
    pieces = [c for c in cells if c["kind"] == "piece"]
    rows = math.ceil(len(smalls) / cols)
    w = cols * (CELL + pad) + pad
    h = pad + rows * (CELL + label_h + pad) + len(pieces) * (CELL + label_h + pad) + 30
    sheet = Image.new("RGB", (w, h), (41, 33, 29))
    # a little wall texture
    tex = noise(sheet.size, random.Random(7), 24).point(lambda v: 230 + v // 10)
    sheet = Image.merge("RGB", [_mul(ch, tex) for ch in sheet.split()])
    fnt = font("BarlowSemiCondensed-Regular.ttf", 12)
    d = ImageDraw.Draw(sheet)
    d.text((pad, 6), "graffiti.png 1024x1024 - %d cells (contact sheet)" % len(cells), font=fnt, fill=(200, 190, 170))
    y = 30
    for i, c in enumerate(smalls):
        x = pad + (i % cols) * (CELL + pad)
        yy = y + (i // cols) * (CELL + label_h + pad)
        rx, ry, rw, rh = c["rect"]
        sheet.paste(atlas.crop((rx, ry, rx + rw, ry + rh)), (x, yy), atlas.crop((rx, ry, rx + rw, ry + rh)))
        d.text((x, yy + CELL + 1), c["id"], font=fnt, fill=(200, 190, 170))
    y += rows * (CELL + label_h + pad)
    for c in pieces:
        rx, ry, rw, rh = c["rect"]
        crop = atlas.crop((rx, ry, rx + rw, ry + rh))
        sheet.paste(crop, (pad, y), crop)
        d.text((pad, y + CELL + 1), c["id"], font=fnt, fill=(200, 190, 170))
        y += CELL + label_h + pad
    return sheet


def main() -> int:
    atlas, cells = build()
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    atlas.save(os.path.join(OUT_DIR, "graffiti.png"), optimize=True)
    with open(os.path.join(OUT_DIR, "graffiti_cells.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({
            "atlas": "graffiti.png",
            "size": [ATLAS, ATLAS],
            "palette": sorted(PAINT.keys()),
            "cells": cells,
        }, f, indent=1)
        f.write("\n")
    contact_sheet(atlas, cells).save(SHEET, optimize=True)
    print("wrote %d cells -> %s" % (len(cells), OUT_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
