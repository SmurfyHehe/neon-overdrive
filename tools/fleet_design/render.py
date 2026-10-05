"""Tiny software renderer for the design sheet: z-buffered, flat-shaded
triangles (the faceted low-poly look), feature lines, silhouettes and a
night mode with glowing lights. No GPU needed."""
import math
import numpy as np
from PIL import Image
from scipy import ndimage

# Amber vs. Dusk (Roy, 2026-10-05)
SKY = (0x1B, 0x2A, 0x4A)
SHADOW = (0x0E, 0x14, 0x24)
SODIUM = (0xFF, 0x8A, 0x1F)
AMBER = (0xFF, 0xC0, 0x66)
SILVER = (0xC9, 0xCE, 0xD6)
TAIL = (0xE5, 0x26, 0x2B)


def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def c01(c):
    return np.array(c, float) / 255.0


BASE_MATS = {
    'paint': '#C9CED6', 'roof': None, 'paint2': '#C9CED6',
    'trim': '#1A1D24', 'under': '#0B0E14', 'glass': '#151D2E', 'pillar': '#10141C',
    'chrome': '#C9CED6', 'rim': '#B9BEC6', 'rim_dark': '#22252C', 'rim_gap': '#0B0E14', 'rim_face': '#8D939C',
    'tire': '#15171C', 'tire_side': '#1C1F26', 'head': '#FFE7BD', 'head_off': '#5A5F68', 'tail': '#E5262B',
    'turn': '#FFC066', 'pol_r': '#E5262B', 'pol_b': '#2E4FD8', 'grille': '#0D1017', 'interior': '#141820',
    'bed': '#1E2129', 'slot': '#FF8A1F', 'exh_hole': '#050608', 'tail_off': '#5C1416', 'rim_bronze': '#9C6B3A', 'rim_gold': '#C8A04A',
}
EMISSIVE = {'head', 'tail', 'turn', 'pol_r', 'pol_b'}


def resolve_colors(mats, paint):
    """paint: dict material -> hex override (paint, roof, paint2, trim...)."""
    cols = {}
    for k, v in BASE_MATS.items():
        cols[k] = v
    cols.update({k: v for k, v in paint.items() if v})
    if not cols.get('roof'):
        cols['roof'] = cols['paint']
    return {k: c01(hexc(v)) for k, v in cols.items()}


# --------------------------------------------------------------------------
# Cameras
# --------------------------------------------------------------------------
def look_at(eye, target, up):
    eye = np.asarray(eye, float)
    f = np.asarray(target, float) - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, np.asarray(up, float))
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, r, u, f


VIEWS = {
    'side': dict(type='ortho', eye=(-30, 0.7, 0), target=(0, 0.7, 0), up=(0, 1, 0)),
    'top': dict(type='ortho', eye=(0, 30, 0), target=(0, 0, 0), up=(1, 0, 0)),
    'front': dict(type='ortho', eye=(0, 0.7, -30), target=(0, 0.7, 0), up=(0, 1, 0)),
    'rear': dict(type='ortho', eye=(0, 0.7, 30), target=(0, 0.7, 0), up=(0, 1, 0)),
    'q_front': dict(type='persp', eye=(-4.9, 1.55, -5.7), target=(0, 0.55, 0.15), up=(0, 1, 0), fov=27),
    'q_rear': dict(type='persp', eye=(5.0, 2.0, 5.8), target=(0, 0.6, -0.15), up=(0, 1, 0), fov=27),
    # Stage A chase cam: 1.85 m up, 5.2 m back, aims 12 m ahead at 0.95 m, 58 deg vertical FOV at rest
    'chase': dict(type='persp', eye=(0, 1.85, 5.2), target=(0, 0.95, -12.0), up=(0, 1, 0), fov=58),
}


def project(pts, cam, W, H):
    """pts (...,3) -> screen x, y, depth (metres along view)."""
    eye, r, u, f = look_at(cam['eye'], cam['target'], cam['up'])
    d = pts - eye
    x = d @ r
    y = d @ u
    z = d @ f
    if cam['type'] == 'ortho':
        s = cam['scale']
        cx, cy = cam.get('center', (W / 2, H / 2))
        return cx + x * s, cy - y * s, z
    fy = 1.0 / math.tan(math.radians(cam['fov']) / 2)
    fx = fy * H / W
    zz = np.maximum(z, 1e-3)
    sx = (x * fx / zz + 1) * 0.5 * W
    sy = (1 - y * fy / zz) * 0.5 * H
    return sx, sy, z


# --------------------------------------------------------------------------
# Raster
# --------------------------------------------------------------------------
def rasterize(tris, cam, W, H):
    """Returns id buffer (-1 = empty) and depth buffer."""
    sx, sy, sz = project(tris.reshape(-1, 3), cam, W, H)
    sx = sx.reshape(-1, 3)
    sy = sy.reshape(-1, 3)
    sz = sz.reshape(-1, 3)
    persp = cam['type'] == 'persp'
    ids = np.full((H, W), -1, np.int32)
    zb = np.full((H, W), np.inf)
    dep = np.full((H, W), np.inf)
    for i in range(len(tris)):
        if persp and (sz[i] < 0.05).any():
            continue
        x0, x1, x2 = sx[i]
        y0, y1, y2 = sy[i]
        minx = max(int(math.floor(min(x0, x1, x2))), 0)
        maxx = min(int(math.ceil(max(x0, x1, x2))), W - 1)
        miny = max(int(math.floor(min(y0, y1, y2))), 0)
        maxy = min(int(math.ceil(max(y0, y1, y2))), H - 1)
        if minx > maxx or miny > maxy:
            continue
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        X, Y = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
        w0 = ((x1 - X) * (y2 - Y) - (x2 - X) * (y1 - Y)) / area
        w1 = ((x2 - X) * (y0 - Y) - (x0 - X) * (y2 - Y)) / area
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        z0, z1, z2 = sz[i]
        if persp:
            inv = w0 / z0 + w1 / z1 + w2 / z2
            key = -inv
            depth = 1.0 / np.maximum(inv, 1e-9)
        else:
            key = w0 * z0 + w1 * z1 + w2 * z2
            depth = key
        sub = zb[miny:maxy + 1, minx:maxx + 1]
        m = inside & (key < sub)
        sub[m] = key[m]
        ids[miny:maxy + 1, minx:maxx + 1][m] = i
        dep[miny:maxy + 1, minx:maxx + 1][m] = depth[m]
    return ids, dep


def tri_normals(tris):
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(ln, 1e-12)


def shade(tris, mats, colors, cam, night=False):
    n = tri_normals(tris)
    eye, r, u, f = look_at(cam['eye'], cam['target'], cam['up'])
    cen = tris.mean(axis=1)
    if cam['type'] == 'ortho':
        v = np.tile(-f, (len(tris), 1))
    else:
        v = eye - cen
        v /= np.linalg.norm(v, axis=1, keepdims=True)
    # double-sided: face the viewer
    flip = (n * v).sum(1) < 0
    n[flip] *= -1
    key_dir = np.array([-0.45, 0.75, -0.55]); key_dir /= np.linalg.norm(key_dir)
    fill_dir = np.array([0.7, 0.25, 0.6]); fill_dir /= np.linalg.norm(fill_dir)
    top_dir = np.array([0.0, 1.0, 0.0])
    if night:
        key_col = np.array([1.0, 0.62, 0.30]) * 0.55
        fill_col = np.array([0.30, 0.38, 0.62]) * 0.25
        amb = np.array([0.10, 0.12, 0.20])
    else:
        key_col = np.array([1.0, 0.86, 0.70]) * 0.95
        fill_col = np.array([0.48, 0.58, 0.88]) * 0.42
        amb = np.array([0.24, 0.27, 0.36])
    rim_col = np.array([1.0, 0.55, 0.14]) * (0.55 if not night else 0.8)
    kd = np.clip(n @ key_dir, 0, 1)[:, None]
    fd = np.clip(n @ fill_dir, 0, 1)[:, None]
    td = np.clip(n @ top_dir, 0, 1)[:, None]
    ndv = np.abs((n * v).sum(1))[:, None]
    rim = (1 - ndv) ** 3
    out = np.zeros((len(tris), 3))
    emis = np.zeros(len(tris), bool)
    for i, m in enumerate(mats):
        base = colors.get(m, colors['paint'])
        if m in EMISSIVE:
            out[i] = base * (1.25 if night else 1.0)
            emis[i] = True
            continue
        c = base * (amb + kd[i] * key_col + fd[i] * fill_col + td[i] * 0.10)
        if m == 'glass':
            c = base * 0.9 + 0.08 * td[i] * np.array([0.55, 0.62, 0.80]) + 0.10 * kd[i] * np.array([1, 0.8, 0.6])
        c = c + rim[i] * rim_col * (0.35 if m in ('glass', 'tire', 'under', 'tire_side', 'rim_gap') else 1.0) * 0.6
        out[i] = c
    return np.clip(out, 0, 1), emis, n


def edges_from(ids, dep, nrm_px, mat_px):
    """Feature lines: silhouette, material change, crease, depth jump."""
    H, W = ids.shape
    e = np.zeros((H, W), np.float32)
    for dy, dx in ((0, 1), (1, 0), (1, 1)):
        a = ids[:H - dy, :W - dx]
        b = ids[dy:, dx:]
        diff = a != b
        bg = (a < 0) ^ (b < 0)
        na = nrm_px[:H - dy, :W - dx]
        nb = nrm_px[dy:, dx:]
        crease = (na * nb).sum(-1) < math.cos(math.radians(32))
        mchg = mat_px[:H - dy, :W - dx] != mat_px[dy:, dx:]
        da = dep[:H - dy, :W - dx]
        db = dep[dy:, dx:]
        jump = np.abs(np.where(np.isfinite(da), da, 0) - np.where(np.isfinite(db), db, 0)) > 0.06
        both = (a >= 0) & (b >= 0)
        line = (bg * 1.0) + (diff & both & (crease | mchg | jump)) * 0.55
        e[:H - dy, :W - dx] = np.maximum(e[:H - dy, :W - dx], line)
    return e


def gradient_bg(W, H, top=SKY, bottom=SHADOW):
    t = np.linspace(0, 1, H)[:, None, None]
    return (c01(top) * (1 - t) + c01(bottom) * t) * np.ones((1, W, 1))


def render(tris, mats, cam, W, H, colors, mode='shaded', ss=3, bg=None, lines=True,
           sil_color=SILVER, ground_shadow=True, extra_layers=None):
    """mode: shaded | silhouette | night"""
    Ws, Hs = W * ss, H * ss
    cam_s = dict(cam)
    if cam['type'] == 'ortho':
        cam_s['scale'] = cam['scale'] * ss
        cx, cy = cam.get('center', (W / 2, H / 2))
        cam_s['center'] = (cx * ss, cy * ss)
    ids, dep = rasterize(tris, cam_s, Ws, Hs)
    covered = ids >= 0
    if bg is None:
        img = gradient_bg(Ws, Hs)
    else:
        img = np.ones((Hs, Ws, 3)) * c01(bg)
    if extra_layers is not None:
        img = extra_layers(img, cam_s, Ws, Hs)

    if ground_shadow and mode != 'silhouette':
        # soft contact shadow under the car
        sx, sy, _ = project(np.array([[0, 0, 0.0]]), cam_s, Ws, Hs)
        pts = tris.reshape(-1, 3)
        gx, gy, _ = project(np.c_[pts[:, 0], np.zeros(len(pts)), pts[:, 2]], cam_s, Ws, Hs)
        mask = np.zeros((Hs, Ws), np.float32)
        x0, x1 = int(max(gx.min(), 0)), int(min(gx.max(), Ws - 1))
        y0, y1 = int(max(gy.min(), 0)), int(min(gy.max(), Hs - 1))
        if x1 > x0 and y1 >= y0:
            mask[max(y0 - 2 * ss, 0):y1 + 2 * ss, x0:x1] = 1
            mask = ndimage.gaussian_filter(mask, sigma=6 * ss)
            img = img * (1 - 0.55 * mask[..., None])

    mat_names = sorted(set(mats))
    mat_index = {m: i for i, m in enumerate(mat_names)}
    mat_arr = np.array([mat_index[m] for m in mats])

    if mode == 'silhouette':
        col = c01(sil_color)
        img[covered] = col
        if lines:
            e = edges_from(ids, dep, np.zeros((Hs, Ws, 3)), np.zeros((Hs, Ws), np.int32))
            e = ndimage.maximum_filter(e, size=max(1, ss - 1))
            img = img * (1 - 0.0 * e[..., None])
    else:
        night = mode == 'night'
        fc, emis, nrm = shade(tris, mats, colors, cam_s, night=night)
        if night:
            # body reads as a dark shape; lights carry the identity
            dark = np.array([0.075, 0.09, 0.13])
            fc2 = fc.copy()
            for i, m in enumerate(mats):
                if not emis[i]:
                    fc2[i] = dark + 0.22 * (fc[i] - dark) * (0.5 if m != 'glass' else 0.3)
            fc = fc2
        img[covered] = fc[ids[covered]]
        if lines:
            nrm_px = np.zeros((Hs, Ws, 3))
            nrm_px[covered] = nrm[ids[covered]]
            mat_px = np.full((Hs, Ws), -1, np.int32)
            mat_px[covered] = mat_arr[ids[covered]]
            e = edges_from(ids, dep, nrm_px, mat_px)
            e = ndimage.maximum_filter(e, size=max(1, ss - 1))
            line_col = c01(SHADOW) * 0.6
            a = np.clip(e * (0.75 if not night else 0.35), 0, 1)[..., None]
            img = img * (1 - a) + line_col * a
        if night or True:
            em = np.zeros((Hs, Ws, 3))
            emask = covered.copy()
            emask[covered] = emis[ids[covered]]
            em[emask] = fc[ids[emask]]
            glow = ndimage.gaussian_filter(em, sigma=(5 * ss if night else 2 * ss, 5 * ss if night else 2 * ss, 0))
            img = img + glow * (1.6 if night else 0.35)
    img = np.clip(img, 0, 1)
    pil = Image.fromarray((img * 255).astype(np.uint8))
    if ss > 1:
        pil = pil.resize((W, H), Image.LANCZOS)
    return pil, covered


def silhouette_mask(tris, cam, W, H):
    ids, _ = rasterize(tris, cam, W, H)
    return ids >= 0
