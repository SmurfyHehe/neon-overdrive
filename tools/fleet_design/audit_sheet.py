"""B1 audit sheet (2026-10-05): before/after for the four revised cars, the
Godot check results, and the outline twins the 360 sweep still lists.

Inputs: renders of B1 and the revised designs (`render`, run once in each
checkout), and the JSON the Godot checks wrote to docs/design/fleet/audit.

    python audit_sheet.py render <dir>          # this checkout's 4 cars
    python audit_sheet.py <b1 dir> <now dir>    # the sheet
"""
import json
import os
import sys

from PIL import Image, ImageDraw

from render import SHADOW, AMBER, SILVER, SODIUM
from sheets import F, MUTED

AUDIT = os.path.join(os.path.dirname(__file__), '..', '..', 'docs', 'design', 'fleet', 'audit')
CARS = [('p2_hothatch', 'P2 Hot hatch', 'box blisters 6.5 cm proud of a narrower cabin, wider track, lower roof, upright hatch'),
        ('p5_muscle', 'P5 Muscle sedan', '4 cm wider, roof 3 cm lower, narrower cabin, stronger hips, taller scoop, sharper ducktail'),
        ('n1_commuter', 'N1 Commuter sedan', 'taller nose, roof and deck, wider rounder cabin, smaller wheels in bigger gaps'),
        ('p6_crossover', 'P6 Crossover (rack only)', 'crossbars poke 14 cm past the roof; street build keeps low rails')]


def render_views(out):
    import car
    import cars
    import options  # noqa: F401  (fills in the build options)
    import render
    import views
    os.makedirs(out, exist_ok=True)
    ids = [c[0] for c in CARS]
    for D in cars.FLEET:
        if D['id'] not in ids:
            continue
        m = car.build(D)
        colors = render.resolve_colors(m.mesh.mats, cars.colors_for(D))
        for v in ('q_front', 'q_rear'):
            views.view_image(m, colors, v, mode='shaded', size=(900, 560), ss=2).save(os.path.join(out, f"{D['id']}_{v}.png"))
        for v in ('front', 'rear'):
            views.view_image(m, colors, v, mode='shaded', scale=150, size=(420, 320), ss=2).save(os.path.join(out, f"{D['id']}_{v}.png"))


def tile(path, w):
    im = Image.open(path).convert('RGB')
    h = round(im.height * w / im.width)
    return im.resize((w, h), Image.LANCZOS)


def main(b1_dir, now_dir):
    W = 2560
    qw, fw = 440, 280
    row_h = 330
    H = 150 + row_h * len(CARS) + 420
    sheet = Image.new('RGB', (W, H), SHADOW)
    d = ImageDraw.Draw(sheet)
    d.text((34, 22), 'B1 AUDIT  ·  WHAT CHANGED AND WHAT THE GODOT CHECKS SAY', font=F('b', 46), fill=SILVER)
    d.text((36, 82), 'Left of each pair: B1 as delivered. Right: after the audit. Numbers from tests/fleet_*.gd run in '
                     'Godot 4.7.2 (2026-10-05).', font=F('m', 22), fill=MUTED)
    y = 140
    heads = [('3/4 FRONT', 2 * qw + 16), ('FRONT', 2 * fw + 16), ('REAR', 2 * fw + 16)]
    x = 380
    for h, w in heads:
        d.text((x, y), h + '   B1  ->  now', font=F('s', 18), fill=AMBER)
        x += w + 40
    y += 34
    for cid, label, change in CARS:
        d.text((34, y + 10), label, font=F('b', 28), fill=SILVER)
        yy = y + 52
        for line in _wrap(change, 30):
            d.text((34, yy), line, font=F('m', 18), fill=MUTED)
            yy += 24
        x = 380
        for view, w in (('q_front', qw), ('front', fw), ('rear', fw)):
            for k, src in enumerate((b1_dir, now_dir)):
                t = tile(os.path.join(src, f'{cid}_{view}.png'), w)
                sheet.paste(t, (x, y))
                if k == 1:
                    d.rectangle((x - 2, y - 2, x + w + 1, y + t.height + 1), outline=SODIUM, width=2)
                x += w + 16
            x += 24
        y += row_h

    # results
    chk = json.load(open(os.path.join(AUDIT, 'design_check.json')))
    sw = json.load(open(os.path.join(AUDIT, 'silhouette_sweep.json')))
    bud = json.load(open(os.path.join(AUDIT, 'budget_scene.json')))
    ver = json.load(open(os.path.join(AUDIT, '..', 'verify.json')))
    a = ver['audit']
    lines = [
        ('Blind test', f"fresh agent, 9 views incl. 3 high angles B1 never tested: named {a['correct']}/{a['outlines']} right; "
                       f"every miss was the high rear view, where the three sedans blur"),
        ('360 outlines', f"96 orbit cameras + chase view per car. Outline twins (no feature >1% apart): 9 view-pairs in B1, "
                         f"2 now ({len(sw.get('known_twins', [])) // 2} listed for your call; the blind tester told both pairs apart)"),
        ('Sticker slots', 'B1 failed 43 checks (slots floating 3-5.5 cm over lowered builds, the hot hatch\'s rear slot under its '
                          'spoiler, slots unseen from low rear angles); now 0. Rear slots moved to the tail panel on 9 cars'),
        ('Budget', f"30 traffic cars as separate meshes: +{round(bud['nodes_draw_calls_per_car'] * bud['traffic_cars'])} draw calls "
                   f"({bud['baseline']['dc']} -> {bud['nodes']['dc']}); as one MultiMesh per design: +{bud['multimesh_extra_draw_calls']}. "
                   f"Triangles at full budget {bud['full_budget_tris_per_frame'] // 1000}k per frame: easy for Iris Xe"),
        ('Exhaust, palette', 'every build and exhaust option has tips with 0.6 m clear for flames; 97 colours, no magenta or cyan'),
    ]
    d.text((34, y + 10), 'RESULTS', font=F('b', 28), fill=AMBER)
    y += 56
    for k, v in lines:
        d.text((34, y), k, font=F('s', 21), fill=SILVER)
        for i, line in enumerate(_wrap(v, 150)):
            d.text((300, y + i * 28), line, font=F('m', 21), fill=MUTED)
        y += 28 * len(_wrap(v, 150)) + 10
    out = os.path.join(AUDIT, 'audit_sheet.png')
    sheet.save(out, optimize=True)
    print(out)


def _wrap(text, n):
    words, lines, cur = text.split(), [], ''
    for w in words:
        if len(cur) + len(w) + 1 > n and cur:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + ' ' + w).strip()
    if cur:
        lines.append(cur)
    return lines


if __name__ == '__main__':
    if sys.argv[1] == 'render':
        render_views(sys.argv[2])
    else:
        main(sys.argv[1], sys.argv[2])
