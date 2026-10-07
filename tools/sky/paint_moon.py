"""Paints assets/sky/moon.png: a 128 px moon face in the PS2 spirit.

Greyscale albedo (the sky shader tints it silver and lights it by phase):
soft dark maria, a few rimmed craters, light grain, then posterised to
16 levels so it reads hand-painted rather than photographic. Seeded, so
re-running gives the same file. Run: python tools/sky/paint_moon.py
"""
import numpy as np
from PIL import Image

N = 128
rng = np.random.default_rng(7)
y, x = np.mgrid[0:N, 0:N] / (N - 1) * 2.0 - 1.0  # -1..1 across the face
img = np.full((N, N), 0.82)

def blob(cx, cy, r, depth):
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
    return depth * np.clip(1.0 - d * d, 0.0, 1.0) ** 1.5

# Maria: the familiar "face" arrangement, loosely, upper left heavier.
for cx, cy, r, dep in [(-0.30, -0.35, 0.38, 0.30), (0.05, -0.45, 0.30, 0.26),
                       (-0.45, 0.05, 0.30, 0.24), (0.25, -0.10, 0.26, 0.22),
                       (0.10, 0.25, 0.22, 0.18), (-0.15, 0.45, 0.18, 0.14),
                       (0.45, 0.30, 0.16, 0.12)]:
    img -= blob(cx, cy, r, dep)

# Craters: a dark floor and a bright rim, lower half (the highlands).
for cx, cy, r in [(0.15, 0.62, 0.09), (-0.40, 0.55, 0.06), (0.55, 0.05, 0.07),
                  (-0.10, 0.08, 0.05), (0.35, 0.50, 0.05)]:
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
    img -= 0.10 * np.clip(1.0 - d, 0.0, 1.0)
    img += 0.10 * np.exp(-((d - 1.05) / 0.18) ** 2)

# Bright rays from the lower crater (Tycho-ish), faint.
ang = np.arctan2(y - 0.62, x - 0.15)
dist = np.sqrt((x - 0.15) ** 2 + (y - 0.62) ** 2)
img += 0.05 * (np.cos(ang * 7.0) > 0.6) * np.exp(-dist * 2.5)

# Coarse grain, blurred a touch so it reads as brushwork, not noise.
g = rng.normal(0.0, 0.025, (N // 4, N // 4))
g = np.kron(g, np.ones((4, 4)))
img += g

img = np.clip(img, 0.0, 1.0)
img = np.round(img * 15.0) / 15.0  # posterise: 16 levels
Image.fromarray((img * 255).astype(np.uint8), "L").save("assets/sky/moon.png")
print("wrote assets/sky/moon.png")
