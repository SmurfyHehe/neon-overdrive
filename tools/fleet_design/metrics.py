"""Outline-only checks: silhouette masks for every car in every view, and how
much each pair overlaps (intersection over union). A pair with a high score
would be hard to tell apart by outline alone."""
import itertools
import numpy as np
from PIL import Image

import render
import views

ORTHO = {
    # view: (width m, height m) of the canvas; 50 px per metre
    'side': (6.0, 2.4),
    'top': (6.0, 2.4),
    'front': (2.6, 2.4),
}
PERSP = {
    'q_front': (480, 300, None),
    'q_rear': (480, 300, None),
    # chase: the full 16:9 frame at 960x540, cropped to the car
    'chase': (960, 540, (180, 140, 780, 540)),
    'ahead': (2880, 1620, None),
}
PX = 50


def masks_for(model):
    D = model.defn
    tris = model.mesh.array()
    out = {}
    for v, (wm, hm) in ORTHO.items():
        W, H = int(wm * PX), int(hm * PX)
        cam = views.ortho_cam(D, v, PX, W, H, ground_px=10)
        if v == 'top':
            cam['center'] = (W / 2 - views.body_center_z(D) * PX, H / 2)
        out[v] = render.silhouette_mask(tris, cam, W, H)
    for v, (W, H, crop) in PERSP.items():
        cam = dict(render.VIEWS.get(v, render.VIEWS['chase']))
        t = tris
        if v == 'ahead':
            # traffic seen from the player's chase cam, 14 m up the road
            t = tris + np.array([0.0, 0.0, -14.0])
            cam = dict(render.VIEWS['chase'])
        m = render.silhouette_mask(t, cam, W, H)
        if crop:
            x0, y0, x1, y1 = crop
            m = m[y0:y1, x0:x1]
        out[v] = m
    return out


def iou(a, b):
    inter = np.logical_and(a, b).sum()
    uni = np.logical_or(a, b).sum()
    return inter / max(uni, 1)


def normalized(m, size=(160, 64)):
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return np.zeros(size[::-1], bool)
    crop = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    im = Image.fromarray((crop * 255).astype(np.uint8)).resize(size, Image.BILINEAR)
    return np.array(im) > 127


def pair_table(all_masks, ids, view, norm=False):
    rows = []
    for i, j in itertools.combinations(range(len(ids)), 2):
        a = all_masks[ids[i]][view]
        b = all_masks[ids[j]][view]
        if norm:
            a, b = normalized(a), normalized(b)
        rows.append((iou(a, b), ids[i], ids[j]))
    rows.sort(reverse=True)
    return rows


def crop_union(all_masks, view, margin=12):
    """Crop every car's mask in a view to the union bounding box, so the
    cars keep their true relative size."""
    ys0, xs0, ys1, xs1 = [], [], [], []
    for cid, mm in all_masks.items():
        ys, xs = np.nonzero(mm[view])
        ys0.append(ys.min()); ys1.append(ys.max()); xs0.append(xs.min()); xs1.append(xs.max())
    H, W = next(iter(all_masks.values()))[view].shape
    y0, y1 = max(min(ys0) - margin, 0), min(max(ys1) + margin, H)
    x0, x1 = max(min(xs0) - margin, 0), min(max(xs1) + margin, W)
    for cid in all_masks:
        all_masks[cid][view] = all_masks[cid][view][y0:y1, x0:x1]
