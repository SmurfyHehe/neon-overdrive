"""Standard views for the sheet: the same framing for every car so they
compare at a glance."""
import math
import numpy as np
from PIL import Image

import render
from render import c01, SKY, SHADOW, SODIUM


def body_center_z(D):
    return D['L'] / 2 - (D['OHf'] + D['WB'] / 2)


def ortho_cam(D, view, scale, W, H, ground_px=22):
    cam = dict(render.VIEWS[view])
    cam['scale'] = scale
    zc = body_center_z(D)
    if view == 'top':
        cam['eye'] = (0, 30, 0)
        cam['target'] = (0, 0, 0)
        cam['center'] = (W / 2 - zc * scale, H / 2)
    elif view == 'side':
        cam['eye'] = (-30, 0, 0)
        cam['target'] = (0, 0, 0)
        cam['center'] = (W / 2 - zc * scale, H - ground_px)
    else:
        e = np.array(cam['eye'], float)
        cam['eye'] = (0, 0, e[2])
        cam['target'] = (0, 0, 0)
        cam['center'] = (W / 2, H - ground_px)
    return cam


def road_layer(img, cam, W, H):
    """Night road under a persp camera: sodium-lit asphalt, lane paint,
    a hazy sodium horizon (stage A look B)."""
    eye, r, u, f = render.look_at(cam['eye'], cam['target'], cam['up'])
    t = math.tan(math.radians(cam['fov']) / 2)
    px = (np.arange(W) + 0.5) / W * 2 - 1
    py = 1 - (np.arange(H) + 0.5) / H * 2
    X, Y = np.meshgrid(px * t * W / H, py * t)
    d = f[None, None, :] + X[..., None] * r[None, None, :] + Y[..., None] * u[None, None, :]
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    out = img.copy()
    # sky: dark navy, sodium glow at the horizon
    elev = d[..., 1]
    sky = c01(SHADOW)[None, None, :] * np.ones_like(out)
    glow = np.exp(-np.clip(elev, 0, None) * 18)[..., None]
    sky = sky * (1 - glow * 0.7) + (c01(SODIUM) * 0.32 + c01(SKY) * 0.4) * glow * 0.7
    down = elev < -1e-4
    tt = np.where(down, -eye[1] / np.where(down, elev, -1), np.inf)
    gx = eye[0] + d[..., 0] * tt
    gz = eye[2] + d[..., 2] * tt
    dist = np.where(down, tt, 1e9)
    asphalt = np.array([0.20, 0.185, 0.175])
    # lamp pools every 25 m, staggered left/right
    pool = np.zeros_like(gz)
    for side in (-1, 1):
        zz = (gz + (12.5 if side > 0 else 0)) % 25.0 - 12.5
        xx = gx - side * 7.0
        pool += np.exp(-(zz ** 2) / 40.0 - (xx ** 2) / 30.0)
    lit = 0.45 + 0.9 * np.clip(pool, 0, 1.2)
    ground = asphalt[None, None, :] * lit[..., None] * np.array([1.0, 0.86, 0.68])[None, None, :]
    # lane paint (2.3 m lanes, stage A), dashed
    for lx in (-3.45, -1.15, 1.15, 3.45):
        dash = ((gz % 9.0) < 3.0)
        on = (np.abs(gx - lx) < 0.06) & dash
        ground[on] = np.array([0.62, 0.58, 0.50]) * lit[on][:, None] * 0.8
    for lx in (-5.6, 5.6):
        on = np.abs(gx - lx) < 0.08
        ground[on] = np.array([0.66, 0.62, 0.52]) * lit[on][:, None] * 0.8
    # shoulders darker
    off = np.abs(gx) > 5.9
    ground[off] *= 0.55
    fog = 1 - np.exp(-np.clip(dist, 0, 400) * 0.012)
    haze = c01(SHADOW) * 0.6 + c01(SODIUM) * 0.12
    ground = ground * (1 - fog[..., None]) + haze * fog[..., None]
    out = np.where(down[..., None], ground, sky)
    return out


def warm_backdrop(img, cam, W, H):
    t = np.linspace(0, 1, H)[:, None, None]
    top = np.array([0.20, 0.17, 0.16])
    bot = np.array([0.33, 0.25, 0.18])
    return (top * (1 - t) + bot * t) * np.ones((1, W, 1))


def view_image(model, colors, view, mode='shaded', scale=120, size=None, ss=3, crop=None, lines=True,
               sil_color=None, bg=None):
    tris = model.mesh.array()
    mats = model.mesh.mats
    D = model.defn
    if view in ('side', 'top', 'front', 'rear'):
        W, H = size
        cam = ortho_cam(D, view, scale, W, H)
        extra = warm_backdrop if mode == 'night' else None
        img, cov = render.render(tris, mats, cam, W, H, colors, mode=mode, ss=ss, lines=lines,
                                 sil_color=sil_color or render.SILVER, bg=bg, extra_layers=extra,
                                 ground_shadow=(view != 'top'))
        return img
    cam = dict(render.VIEWS[view])
    W, H = size
    extra = road_layer if view == 'chase' else None
    img, cov = render.render(tris, mats, cam, W, H, colors, mode=mode, ss=ss, lines=lines,
                             sil_color=sil_color or render.SILVER, bg=bg, extra_layers=extra)
    if crop:
        img = img.crop(crop)
    return img
