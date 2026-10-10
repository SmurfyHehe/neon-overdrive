"""Build every Boost Simcade brand file from one vector description of the B4 mark.

The B4 "combined" turbo mark (B1 seams + B2 flame + B3 rim / hot ring) is
described once, below, as SVG. The mark's bounding box is centred in its tile
(the hand-drawn original sat 6 px left and low).

Two drawings of the same mark:
  full   seams, outline, four blades. Used at 48 px and up.
  small  no seams, no outline, fatter blades. Used at 32 and 40 px.
  tiny   no blades either: housing, flame, a bold hot ring and the hub. Used
         at 16 to 24 px (title bar, taskbar), where the full drawing is mush.

Step 1 (this script, no arguments) writes the SVG files into assets/brand/.
Step 2 rasterises them with Godot's own SVG renderer (no extra software):
    godot --headless --path . -s tools/brand_raster.gd
Step 3 (this script with "pack") builds the .ico, the project icon, the boot
splash, the Steam 184 px jpg and the Steam capsules from those PNGs:
    python tools/build_brand.py pack

Needs Pillow for step 3 only. tools/build_brand.bat runs all three.
"""
import math
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BRAND = os.path.join(ROOT, "assets", "brand")
RASTER = os.path.join(BRAND, "raster")      # step 2 output, gitignored by .gdignore? no: kept, tiny
STORE = os.path.join(BRAND, "store")
FONT = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-SemiBold.ttf")

TILE = "#1B2A4A"     # navy tile
NAVY = "#0E1424"     # deep navy: inlet, backgrounds
AMBER = "#FFC066"    # housing
SODIUM = "#FF8A1F"   # hot ring, blades, flame
SEAM = "#C97A2A"     # outline and seams
SILVER = "#C9CED6"

# Geometry, in a 256 x 256 tile. The mark's box is x 14..242, y 40..216, so its
# centre is (128, 128): equal padding left/right and top/bottom.
CX, CY = 105.0, 128.0     # centre of the housing and the wheel
R_OUT = 88.0              # outer edge of the housing
OUT_TOP = CY - R_OUT      # outlet runs along the top of the housing
OUT_BOT = OUT_TOP + 33.0
OUT_END = 209.0           # right end of the outlet
FLAME_TIP = 242.0


def _housing(inset: float) -> str:
    """Housing and outlet as one outline, pulled in by `inset` (half a stroke)."""
    r = R_OUT - inset
    top = OUT_TOP + inset
    bot = OUT_BOT - inset
    end = OUT_END - inset
    dx = math.sqrt(r * r - (CY - bot) ** 2)
    return (f"M {CX:.2f} {top:.2f} H {end - 8:.2f} Q {end:.2f} {top:.2f} {end:.2f} {top + 8:.2f} "
            f"V {bot:.2f} H {CX + dx:.2f} A {r:.2f} {r:.2f} 0 1 1 {CX:.2f} {top:.2f} Z")


def _flame() -> str:
    x0 = OUT_END - 5
    t, b = OUT_TOP + 7, OUT_BOT - 6
    m = (t + b) / 2
    outer = f"M {x0} {t} L {FLAME_TIP} {t + 1} L {FLAME_TIP - 19} {m} L {FLAME_TIP - 4} {b + 1} L {x0} {b} Z"
    inner = f"M {x0} {t + 4.5} L {FLAME_TIP - 20} {t + 5.5} L {FLAME_TIP - 29} {m} L {FLAME_TIP - 21} {b - 3.5} L {x0} {b - 4.5} Z"
    return (f'<path d="{outer}" fill="{SODIUM}"/>'
            f'<path d="{inner}" fill="{AMBER}"/>')


def _blades(fat: bool, n: int = 4) -> str:
    # One swept blade, drawn pointing up from the hub, then turned round the wheel.
    if fat:
        d = "M -17 -8 Q -22 -29 -5 -42 L 15 -37 Q 2 -26 1 -12 Z"
    else:
        d = "M -13 -9 Q -18 -31 -2 -46 L 13 -43 Q -1 -29 -2 -13 Z"
    out = []
    for i in range(n):
        out.append(f'<path d="{d}" fill="{SODIUM}" transform="rotate({360.0 * i / n:.0f})"/>')
    return "".join(out)


def _wheel(fat: bool) -> str:
    hub = 9 if fat else 7
    return f'{_blades(fat)}<circle r="{hub}" fill="{AMBER}"/>'


def _body(small: bool, tiny: bool = False) -> str:
    """Everything but the wheel: housing, seams, flame, inlet and hot ring."""
    if tiny:
        return (f'<path d="{_housing(0)}" fill="{AMBER}"/>{_flame()}'
                f'<circle cx="{CX}" cy="{CY}" r="46" fill="{NAVY}" stroke="{SODIUM}" stroke-width="14"/>'
                f'<circle cx="{CX}" cy="{CY}" r="15" fill="{AMBER}"/>')
    if small:
        parts = [f'<path d="{_housing(0)}" fill="{AMBER}"/>',
                 _flame(),
                 f'<circle cx="{CX}" cy="{CY}" r="56" fill="{NAVY}" stroke="{SODIUM}" stroke-width="9"/>']
        return "".join(parts)
    seam_r = 71.0
    a0, a1 = math.radians(15), math.radians(57.7)
    sx, sy = CX - seam_r * math.cos(a0), CY - seam_r * math.sin(a0)
    ex, ey = CX + seam_r * math.cos(a1), CY - seam_r * math.sin(a1)
    parts = [
        f'<path d="{_housing(3.5)}" fill="{AMBER}" stroke="{SEAM}" stroke-width="7" stroke-linejoin="round"/>',
        # B1 seams: the volute seam round the housing and the one along the outlet.
        f'<path d="M {sx:.2f} {sy:.2f} A {seam_r} {seam_r} 0 1 0 {ex:.2f} {ey:.2f}" fill="none" '
        f'stroke="{SEAM}" stroke-width="4" stroke-linecap="round"/>',
        f'<path d="M {CX + 22} {OUT_TOP + 16} H {OUT_END - 20}" fill="none" stroke="{SEAM}" '
        f'stroke-width="4" stroke-linecap="round"/>',
        _flame(),                                    # B2 flame
        # B3 rim: the dark inlet with the hot ring round it.
        f'<circle cx="{CX}" cy="{CY}" r="55.5" fill="{NAVY}" stroke="{SODIUM}" stroke-width="5"/>',
    ]
    return "".join(parts)


def _svg(inner: str, size: int = 256, view: str = "0 0 256 256") -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="{view}">{inner}</svg>\n')


def _tile(rx: int = 46) -> str:
    return f'<rect width="256" height="256" rx="{rx}" fill="{TILE}"/>'


def _grow(inner: str, k: float) -> str:
    """Scale the mark about the tile centre: small icons need less empty tile."""
    return f'<g transform="translate(128 128) scale({k}) translate(-128 -128)">{inner}</g>'


def _placed_wheel(fat: bool) -> str:
    return f'<g transform="translate({CX} {CY})">{_wheel(fat)}</g>'


def write_svgs() -> None:
    files = {
        # The centred B4 mark on its navy tile: the icon.
        "logo_B4_combined_centred.svg": _svg(_tile() + _body(False) + _placed_wheel(False)),
        # The simplified drawing for 16 to 40 px.
        "logo_B4_small.svg": _svg(_tile(40) + _grow(_body(True) + _placed_wheel(True), 1.07)),
        # 16 to 24 px: no blades at all, a bold hot ring and hub.
        "logo_B4_tiny.svg": _svg(_tile(36) + _grow(_body(True, True), 1.09)),
        # No tile, for use on the game's own backgrounds (title, splash, capsules).
        "logo_B4_mark.svg": _svg(_body(False) + _placed_wheel(False)),
        # The mark in two layers so the game can spin the wheel (splash flutter).
        "logo_B4_mark_body.svg": _svg(_body(False)),
        "logo_B4_mark_wheel.svg": _svg(_wheel(False), 128, "-64 -64 128 128"),
    }
    for name, text in files.items():
        with open(os.path.join(BRAND, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("wrote", name)


# ---------------------------------------------------------------- pack (Pillow)

ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)
SMALL_MAX = 40     # sizes up to this use the simplified drawing


def _hex(c: str):
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def _lockup(w: int, h: int, mark_h: int, with_name: bool = True, bg=NAVY):
    """Mark on the left, BOOST over a spaced SIMCADE on the right, centred in w x h."""
    from PIL import Image, ImageDraw, ImageFont
    im = Image.new("RGB", (w, h), _hex(bg))
    mark = Image.open(os.path.join(RASTER, "mark_1024.png")).convert("RGBA")
    box = mark.getbbox()
    mark = mark.crop(box)
    mw = round(mark.width * mark_h / mark.height)
    mark = mark.resize((mw, mark_h), Image.LANCZOS)
    if not with_name:
        im.paste(mark, ((w - mw) // 2, (h - mark_h) // 2), mark)
        return im
    d = ImageDraw.Draw(im)
    big = ImageFont.truetype(FONT, round(mark_h * 1.02))
    small = ImageFont.truetype(FONT, round(mark_h * 0.27))
    bx0, by0, bx1, by1 = d.textbbox((0, 0), "BOOST", font=big)
    track = round(mark_h * 0.075)                       # letter spacing of SIMCADE
    sw = sum(d.textlength(ch, font=small) for ch in "SIMCADE") + track * 6
    sx0, sy0, sx1, sy1 = d.textbbox((0, 0), "SIMCADE", font=small)
    gap = round(mark_h * 0.26)
    line_gap = round(mark_h * 0.09)
    text_w = max(bx1 - bx0, sw)
    text_h = (by1 - by0) + line_gap + (sy1 - sy0)
    total = mw + gap + text_w
    x = (w - total) // 2
    im.paste(mark, (x, (h - mark_h) // 2), mark)
    tx = x + mw + gap
    ty = (h - text_h) // 2
    d.text((tx - bx0, ty - by0), "BOOST", font=big, fill=_hex(AMBER),
           stroke_width=max(1, round(mark_h * 0.016)), stroke_fill=_hex(AMBER))
    cx = tx
    for ch in "SIMCADE":
        d.text((cx, ty + (by1 - by0) + line_gap - sy0), ch, font=small, fill=_hex(SILVER))
        cx += d.textlength(ch, font=small) + track
    return im


def pack() -> None:
    from PIL import Image
    os.makedirs(STORE, exist_ok=True)
    frames = []
    for s in ICO_SIZES:
        frames.append(Image.open(os.path.join(RASTER, f"icon_{s}.png")).convert("RGBA"))
    # Each size was drawn at its own size from the vector, never scaled down.
    frames[-1].save(os.path.join(BRAND, "logo_B4_combined.ico"), format="ICO",
                    sizes=[(s, s) for s in ICO_SIZES], append_images=frames[:-1])
    frames[-1].save(os.path.join(BRAND, "logo_B4_combined_256.png"))
    print("wrote logo_B4_combined.ico", ICO_SIZES)

    _lockup(1920, 1080, 236).save(os.path.join(BRAND, "boot_splash.png"), optimize=True)

    # Steam: 184 px community icon (jpg), then the capsules.
    icon = Image.open(os.path.join(RASTER, "icon_full_184.png")).convert("RGBA")
    flat = Image.new("RGB", icon.size, _hex(TILE))
    flat.paste(icon, (0, 0), icon)
    flat.save(os.path.join(STORE, "steam_icon_184.jpg"), quality=95)
    for name, (w, h, mark_h) in {
        "steam_capsule_header_920x430.png": (920, 430, 150),
        "steam_capsule_small_462x174.png": (462, 174, 74),
        "steam_capsule_main_1232x706.png": (1232, 706, 210),
    }.items():
        _lockup(w, h, mark_h).save(os.path.join(STORE, name), optimize=True)
    _lockup(748, 896, 170, bg=NAVY).save(os.path.join(STORE, "steam_capsule_vertical_748x896.png"), optimize=True)
    print("wrote boot_splash.png and store/ files")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "pack":
        pack()
    else:
        write_svgs()
