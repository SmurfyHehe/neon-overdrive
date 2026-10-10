"""Re-centre the B4 logo mark inside its square tile and rebuild the .ico.

The tile (rounded navy square) already fills the 256x256 canvas, so the
non-transparent bounding box is the whole canvas. The off-centre part is the
turbo mark drawn on the tile. This script finds the bounding box of the mark
(pixels that differ from the flat tile colour), moves it so that box is centred
in the canvas (same scale, equal padding on both sides), and rebuilds the .ico
with sizes 16, 32, 48, 64, 128, 256.

Usage (from the repo root):
    python tools/recentre_logo.py

Idempotent: always reads the untouched original from assets/brand/originals/,
creating it from the current file the first time.
Needs Pillow only.
"""
import os
import shutil
import sys
from collections import Counter

from PIL import Image, ImageChops

BRAND = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "brand")
ORIG_DIR = os.path.join(BRAND, "originals")
PNG = os.path.join(BRAND, "logo_B4_combined_256.png")
ICO = os.path.join(BRAND, "logo_B4_combined.ico")
PNG_ORIG = os.path.join(ORIG_DIR, "logo_B4_combined_256_original.png")
ICO_ORIG = os.path.join(ORIG_DIR, "logo_B4_combined_original.ico")
CHECK = os.path.join(BRAND, "centring_check.png")
ICO_SIZES = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
DIFF_THRESHOLD = 30  # summed RGB distance from the tile colour that counts as "mark"


def mark_mask(img):
    """Return (soft_mask, bbox, tile_rgb) for the mark drawn on the flat tile."""
    rgb = img.convert("RGB")
    alpha = img.getchannel("A")
    pix = getattr(Image.Image, "get_flattened_data", Image.Image.getdata)
    opaque = [p for p, a in zip(pix(rgb), pix(alpha)) if a == 255]
    tile = Counter(opaque).most_common(1)[0][0]
    diff = ImageChops.difference(rgb, Image.new("RGB", img.size, tile))
    r, g, b = diff.split()
    dist = ImageChops.add(ImageChops.add(r, g), b)
    # Fully transparent corners hold black RGB; keep them out of the mark.
    dist = ImageChops.multiply(dist, alpha.point(lambda v: 255 if v == 255 else 0))
    soft = dist.point(lambda v: min(255, v * 4))  # keeps anti-aliased edges
    hard = dist.point(lambda v: 255 if v > DIFF_THRESHOLD else 0)
    hard = ImageChops.darker(hard, alpha.point(lambda v: 255 if v > 200 else 0))
    return soft, hard.getbbox(), tile


def recentre(img):
    w, h = img.size
    soft, bbox, tile = mark_mask(img)
    x0, y0, x1, y1 = bbox
    dx = round(w / 2 - (x0 + x1) / 2)
    dy = round(h / 2 - (y0 + y1) / 2)
    # Paste the mark, shifted, over a flat tile, then restore the tile alpha.
    rgb = Image.new("RGB", img.size, tile)
    rgb.paste(img.convert("RGB"), (dx, dy), soft)
    out = rgb.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out, bbox, (dx, dy)


MOCK = os.path.join(BRAND, "title_screen_mock_B4_combined.png")
SPLASH = os.path.join(BRAND, "boot_splash.png")
MOCK_MENU_TOP = 615  # the mock's menu strip starts below this row; the lockup is above it


def make_splash():
    """Centre the mock's logo lockup (turbo + BOOST SIMCADE) on a 1920x1080 splash.

    The mock is a left-aligned title screen with a menu; a boot splash should be
    the lockup alone, centred. Same scale, same background colour as the mock.
    """
    mock = Image.open(MOCK).convert("RGB")
    bg = mock.getpixel((5, 5))
    top = mock.crop((0, 0, mock.width, MOCK_MENU_TOP))
    diff = ImageChops.difference(top, Image.new("RGB", top.size, bg)).convert("L")
    box = diff.point(lambda v: 255 if v > 24 else 0).getbbox()
    lock = mock.crop(box)
    splash = Image.new("RGB", mock.size, bg)
    splash.paste(lock, ((mock.width - lock.width) // 2, (mock.height - lock.height) // 2))
    splash.save(SPLASH, optimize=True)
    return box, bg


def main():
    os.makedirs(ORIG_DIR, exist_ok=True)
    if not os.path.exists(PNG_ORIG):
        shutil.copy2(PNG, PNG_ORIG)
    if not os.path.exists(ICO_ORIG) and os.path.exists(ICO):
        shutil.copy2(ICO, ICO_ORIG)
    orig = Image.open(PNG_ORIG).convert("RGBA")
    centred, bbox, shift = recentre(orig)
    centred.save(PNG, optimize=True)
    centred.save(ICO, format="ICO", sizes=ICO_SIZES)
    # Side-by-side check: original | centred, with crosshair guides on a grey ground.
    pad = 16
    sheet = Image.new("RGBA", (256 * 2 + pad * 3, 256 + pad * 2), (60, 60, 60, 255))
    for i, im in enumerate((orig, centred)):
        sheet.alpha_composite(im, (pad + i * (256 + pad), pad))
    for i in range(2):
        cx = pad + i * (256 + pad) + 128
        for t in range(256):
            sheet.putpixel((cx, pad + t), (255, 255, 255, 160) if t % 4 < 2 else sheet.getpixel((cx, pad + t)))
            sheet.putpixel((pad + i * (256 + pad) + t, pad + 128), (255, 255, 255, 160) if t % 4 < 2 else sheet.getpixel((pad + i * (256 + pad) + t, pad + 128)))
    sheet.save(CHECK)
    _, nb, _ = mark_mask(centred)
    print("mark bbox before:", bbox, "after:", nb, "shift:", shift)
    if os.path.exists(MOCK):
        box, bg = make_splash()
        print("splash lockup bbox in mock:", box, "bg:", bg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
