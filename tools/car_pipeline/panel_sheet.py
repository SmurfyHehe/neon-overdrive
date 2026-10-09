"""Check sheet for a pipeline car: the panels tinted so the cut lines show, and
the same car with the hood, doors and trunk swung open on their hinges.

    python tools/car_pipeline/panel_sheet.py p1_coupe
    -> docs/design/pipeline/<id>_panels.png

Uses the fleet_design software renderer (no GPU, no Godot), on the exact scene
build_car.py exports, so what the sheet shows is what body.glb contains.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_car as bc  # noqa: E402
import render  # noqa: E402
import views  # noqa: E402

OUT_DIR = os.path.join(bc.ROOT, 'docs', 'design', 'pipeline')
TINT = {'hood': '#FFC066', 'trunk': '#F2B53A', 'door_l': '#C41E24', 'door_r': '#C41E24',
        'mirrors': '#C9CED6', 'spoiler': '#B8A27A', 'popups': '#FFE7BD', 'exhaust': '#8D939C'}


def rot(axis, deg):
    a = np.asarray(axis, float)
    a /= np.linalg.norm(a)
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    x, y, z = a
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def flatten(root, meta, opened=False, tint=False):
    """World-space triangles and material names, with hinges turned if opened."""
    tris, mats = [], []

    def visit(node, M, T):
        R = quat_mat(node.rotation)
        if opened and node.name in meta['hinges']:
            h = meta['hinges'][node.name]
            R = R @ rot(h['axis'], h['open_sign'] * h['open_deg'])
        M2 = M @ R
        T2 = T + M @ np.asarray(node.translation)
        if node.mesh is not None:
            for t, m in zip(*node.mesh):
                tris.append(np.asarray(t) @ M2.T + T2)
                mats.append(('tint_' + node.name) if tint and node.name in TINT else m)
        for c in node.children:
            visit(c, M2, T2)

    visit(root, np.eye(3), np.zeros(3))
    return tris, mats


def main(car_id='p1_coupe', build='stock'):
    D = bc.definition(car_id)
    root, meta = bc.build_scene(D, build)
    colors = dict(meta['materials'])
    colors.update({'tint_' + k: v for k, v in TINT.items()})
    colors = {k: render.c01(render.hexc(v)) for k, v in colors.items()}
    W, H = 560, 340
    shots = [('side', 'side, panels tinted', False, True), ('top', 'top, panels tinted', False, True),
             ('q_front', 'closed', False, False), ('q_front', 'open: hood, doors, trunk', True, False),
             ('q_rear', 'open, from the rear', True, False), ('side', 'open, side', True, False)]
    sheet = Image.new('RGB', (W * 3, H * 2 + 40), '#0E1424')
    draw = ImageDraw.Draw(sheet)
    draw.text((12, 10), '%s body.glb (%s build): %d triangles, %d meshes, backend %s' % (
        car_id, build, sum(len(n.mesh[0]) for n in root.walk() if n.mesh),
        sum(1 for n in root.walk() if n.mesh), 'python (no bevel)'), fill='#FFC066')
    for i, (view, label, opened, tint) in enumerate(shots):
        tris, mats = flatten(root, meta, opened=opened, tint=tint)
        cam = views.ortho_cam(D, view, W / (D['L'] + 1.2), W, H) if view in ('side', 'top') else dict(render.VIEWS[view])
        img, _ = render.render(np.array(tris), mats, cam, W, H, colors, mode='shaded', ss=2)
        x, y = (i % 3) * W, 40 + (i // 3) * H
        sheet.paste(img, (x, y))
        draw.text((x + 10, y + 8), label, fill='#E9E6DF')
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, '%s_panels.png' % car_id)
    sheet.save(out)
    print(os.path.relpath(out, bc.ROOT))


if __name__ == '__main__':
    main(*sys.argv[1:])
