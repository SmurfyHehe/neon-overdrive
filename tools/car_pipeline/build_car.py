"""Car modelling pipeline: build one car as separate named parts from its fleet
numbers and export it as glTF for Godot (cars from parts, 2026-10-10; step 1
was docs/planning/car-look-showcase-2026-10-09.md, section 12).

    blender -b --factory-startup --python tools/car_pipeline/build_car.py -- p1_coupe
    python tools/car_pipeline/build_car.py p1_coupe --backend python

Output (per car, per build):
    assets/cars/<id>/body.glb     the model
    assets/cars/<id>/body.json    what is in it: nodes, triangles, slots, tips,
                                  wheels, hinges, materials, dims

Where the numbers come from: the same definitions `tools/fleet_design/` uses
to draw the design sheets and to write `docs/design/fleet/fleet.json`
(`cars.py`, `options.py`). The sheet, the audit proxies and this model are
therefore one shape; a change to the car's numbers rebuilds all three. The
car id is looked up in fleet.json so the two can never name different cars.
`parts.py` cuts that shape into the parts and adds the small ones.

Scene graph (glTF, Godot axes: X right, Y up, -Z forward, origin on the
ground midway between the axles):

    <id>
      body, underbody        the shell: everything that never moves
      fender_fl/fr, bumper_f, bumper_r      bolt-on panels (body-shop swaps)
      hinge_hood             empty on the hinge line (rear of the hood, at the cowl)
        hood                 the hood panel, in hinge-local coordinates
      hinge_door_l/r         empties on the A-pillar hinge line, axis vertical
        door_l/r, glass_door_*, seal_door_*, handle_*, mirror_*
      hinge_trunk            empty on the deck hinge line (front of the lid)
        trunk                the lid
      glass_*, seal_*, pillar_*, sail_*, arch_liner_*   glass, rubber, liners
      grille, turn_*, popup_*, tail_*, tail_panel, plate_*, wiper_*, antenna,
      spoiler, exhaust, bumper_r_insert                 lamps and small parts
      wheel_fl/fr/rl/rr      empties on the hubs
        wheel_*_mesh         the design-sheet wheel (rim + tyre), hub at origin
      slot_door_l/r, slot_hood, slot_sun, slot_rear   sticker slots (+Z = outward normal)
      tip_0..n               exhaust tips (+Z = exhaust direction)
      mount_*                where body-shop parts attach (bumpers, skirts, wing, hood, lamps)
      hub_*, shock_top_*, strut_top_fl/fr, bay_*, exhaust_route_0..n, diff, tank
                             anchors for the real parts (car-parts plan, section 6)
      cam_*                  six camera presets, -Z looking at the car

Every mesh carries COLOR_0: red = `ao` (baked vertex ambient occlusion, 32
rays, 1 = open), green = `shut` (1 on a shut line, 0 six millimetres from it).

Backends:
    blender   Blender's Python (bpy): the parts above plus a bevel on every
              crease sharper than 35 degrees (8 mm; 12 mm on the belt, the
              shoulder, the hood edge and the arch lips), weighted normals,
              exported by Blender's glTF exporter. Picked when `import bpy` works.
    python    a small glTF 2.0 writer with no dependencies beyond numpy: the
              same parts, gaps, `ao` and `shut`, smooth within 35 degrees, no
              bevel. This is what runs when Blender is not installed, so the
              pipeline never blocks on it.

Materials are one glTF material per name in parts.COLOURS (paint, under_paint,
plastic, chrome, rubber, plate, mirror, lens_red, glass, glow_*) plus the
wheel's; `scripts/car/car_assembler.gd` keys on the names.
"""
import argparse
import json
import math
import os
import struct
import subprocess
import sys
import types

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
FLEET_DESIGN = os.path.join(ROOT, 'tools', 'fleet_design')
FLEET_JSON = os.path.join(ROOT, 'docs', 'design', 'fleet', 'fleet.json')
ASSETS = os.path.join(ROOT, 'assets', 'cars')
sys.path.insert(0, FLEET_DESIGN)
sys.path.insert(0, HERE)

# fleet_design/render.py draws the design sheets with Pillow and scipy. This
# script only reads its colour tables, so inside Blender (whose Python has
# numpy and nothing else) those two imports are stood in for instead of
# installed.
for _name in ('PIL', 'PIL.Image', 'scipy', 'scipy.ndimage'):
    try:
        __import__(_name)
    except ImportError:
        sys.modules[_name] = types.ModuleType(_name)
        if '.' in _name:
            setattr(sys.modules[_name.split('.')[0]], _name.split('.')[1], sys.modules[_name])

import car as fcar          # noqa: E402
import cars as fcars        # noqa: E402
import render as frender    # noqa: E402
import parts as fparts      # noqa: E402
from geom import pl         # noqa: E402

GENERATOR = 'neon-overdrive tools/car_pipeline/build_car.py'
BEVEL = 0.008              # crease bevel (cars from parts: 8 mm)
BEVEL_WIDE = 0.012         # belt, shoulder, hood edge, arch lip
SMOOTH_DEG = 35.0          # smooth within a part, hard at creases sharper than this
WIDE_CURVES = (3, 6, 7, 8)  # loft edges that take BEVEL_WIDE (parts.on_curve)
AO_SAMPLES = 32
TRI_BUDGET = (5000, 6500, 7000)   # target range and ceiling for the body parts (wheels not counted)

# What the game already fixes for a car and the model has to agree with. The
# door mirrors are P1CoupeBuilder.MIRRORS / MIRROR_SIZE (the cockpit puts its
# mirror glass and cameras in them); tests/car/car_assembler.gd checks the two
# against each other.
GAME = {
    'p1_coupe': {'mirrors': [{'pos': (-1.01, 0.86, -0.55), 'yaw': 12.0, 'size': (0.21, 0.125, 0.10)},
                             {'pos': (1.01, 0.86, -0.55), 'yaw': -20.0, 'size': (0.21, 0.125, 0.10)}]},
}


# --------------------------------------------------------------------------
# Definitions
# --------------------------------------------------------------------------
def fleet_ids():
    with open(FLEET_JSON) as f:
        return [c['id'] for c in json.load(f)['cars']]


def definition(car_id):
    if car_id not in fleet_ids():
        raise SystemExit('%s is not in %s' % (car_id, os.path.relpath(FLEET_JSON, ROOT)))
    for d in fcars.FLEET:
        if d['id'] == car_id:
            return d
    raise SystemExit('%s is in fleet.json but not in tools/fleet_design/cars.py' % car_id)


def build_options(D, build_name):
    if build_name in (None, 'stock'):
        return {}
    builds = D.get('builds', {})
    if build_name not in builds:
        raise SystemExit('%s has no build %r (has: %s)' % (D['id'], build_name, ', '.join(builds) or 'none'))
    return builds[build_name]


def material_colours(D):
    """Hex colour per material name: the base set, the car's own, then the parts'."""
    cols = dict(frender.BASE_MATS)
    own = fcars.colors_for(D)
    for k, v in own.items():
        if v:
            cols[k] = v
    if not cols.get('roof'):
        cols['roof'] = cols['paint']
    if own.get('rim') and 'rim_bronze' not in own:
        cols['rim_bronze'] = own['rim']
    for k, v in fparts.COLOURS.items():
        cols[k] = v or cols.get(fparts.ALIAS.get(k, k), '#808080')
    return cols


# --------------------------------------------------------------------------
# Scene
# --------------------------------------------------------------------------
def s2z(D, s):
    return fcar._s2z(D, s)


def look_at_quat(eye, target, up=(0, 1, 0)):
    """Quaternion (x, y, z, w) whose -Z looks from eye at target (Godot camera)."""
    eye, target, up = (np.asarray(v, float) for v in (eye, target, up))
    f = target - eye
    f /= max(np.linalg.norm(f), 1e-9)
    z = -f
    x = np.cross(up, z)
    if np.linalg.norm(x) < 1e-6:
        x = np.cross((0, 0, -1), z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return mat_to_quat(np.column_stack([x, y, z]))


def z_axis_quat(normal):
    """Quaternion whose +Z is the given direction."""
    z = np.asarray(normal, float)
    z /= max(np.linalg.norm(z), 1e-9)
    up = np.array([0, 1, 0]) if abs(z[1]) < 0.9 else np.array([1, 0, 0])
    x = np.cross(up, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return mat_to_quat(np.column_stack([x, y, z]))


def mat_to_quat(m):
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        return [float((m[2, 1] - m[1, 2]) / s), float((m[0, 2] - m[2, 0]) / s), float((m[1, 0] - m[0, 1]) / s), float(0.25 * s)]
    i = int(np.argmax(np.diag(m)))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = math.sqrt(1.0 + m[i, i] - m[j, j] - m[k, k]) * 2
    q = [0.0, 0.0, 0.0, 0.0]
    q[i] = 0.25 * s
    q[j] = float((m[j, i] + m[i, j]) / s)
    q[k] = float((m[k, i] + m[i, k]) / s)
    q[3] = float((m[k, j] - m[j, k]) / s)
    return q


class Node:
    def __init__(self, name, translation=(0, 0, 0), rotation=(0, 0, 0, 1), mesh=None, extras=None):
        self.name = name
        self.translation = [float(v) for v in translation]
        self.rotation = [float(v) for v in rotation]
        self.mesh = mesh          # a parts.Part in this node's local frame, or None
        self.children = []
        self.extras = extras or {}
        self.origin = np.zeros(3)  # this node's origin in car space (parts only translate)
        self.mirror_of = None      # the right-hand node this one is the mirror image of (parts.Part.sym 'pair')

    def add(self, child):
        self.children.append(child)
        return child

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


def hinges(D, R):
    """Hinge empties: position and the axis (unit, car space) the panel turns on,
    plus the sign that opens it (right-hand rule about the axis)."""
    cab = D['cabin']
    z = lambda s: s2z(D, s)
    hood_y = pl(D['top'], cab['A'])
    hw_door = pl(D['hw'], R['door_s0'])
    belt = pl(D['belt'], R['door_s0'])
    trunk_y = pl(D['top'], R['trunk_s0'])
    return {
        'hinge_hood': {'pos': [0.0, hood_y - 0.01, z(cab['A'] - 0.02)], 'axis': [1, 0, 0], 'open_sign': 1,
                       'open_deg': 45, 'panel': 'hood'},
        'hinge_trunk': {'pos': [0.0, trunk_y - 0.01, z(R['trunk_s0'])], 'axis': [1, 0, 0], 'open_sign': -1,
                        'open_deg': 50, 'panel': 'trunk'},
        'hinge_door_r': {'pos': [hw_door - 0.02, 0.5 * (R['door_y0'] + belt), z(R['door_s0'])],
                         'axis': [0, 1, 0], 'open_sign': 1, 'open_deg': 60, 'panel': 'door_r'},
        'hinge_door_l': {'pos': [-(hw_door - 0.02), 0.5 * (R['door_y0'] + belt), z(R['door_s0'])],
                         'axis': [0, 1, 0], 'open_sign': -1, 'open_deg': 60, 'panel': 'door_l'},
    }


def anchors(D, R, tips, slots, centres):
    """Named empties: body-shop mounts, parts-plan anchors and camera presets."""
    cab = D['cabin']
    z = lambda s: s2z(D, s)
    L, hw0 = D['L'], pl(D['hw'], 0.5 * D['L'])
    wh = D['wheel']
    axles = fcar._axles(D)
    r = wh['r']
    A = {}
    # body-shop mounts (step 4 hangs parts here)
    A['mount_front_bumper'] = {'pos': [0, 0.5 * (pl(D['floor'], 0.05) + pl(D['waist'], 0.05)), z(0.02)]}
    A['mount_rear_bumper'] = {'pos': [0, 0.5 * (pl(D['floor'], L - 0.05) + pl(D['waist'], L - 0.05)), z(L - 0.02)]}
    for sx, nm in ((1, 'r'), (-1, 'l')):
        A['mount_skirt_' + nm] = {'pos': [sx * hw0, D.get('rocker_h', 0.3) - 0.05, z(0.5 * (axles[0] + axles[1]))]}
    A['mount_wing'] = {'pos': centres.get('spoiler') or [0, pl(D['top'], L - 0.25), z(L - 0.25)]}
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    A['mount_hood'] = {'pos': [0, pl(D['top'], hood_mid), z(hood_mid)]}
    for nm, sx in (('l', -1), ('r', 1)):
        c = centres.get('popup_' + nm)
        A['lamp_' + nm] = {'pos': c if c else [sx * 0.6, pl(D['top'], 0.1) - 0.05, z(0.08)]}
    # sticker slots and exhaust tips
    for sl in slots:
        A[sl['node']] = {'pos': sl['center'], 'quat': z_axis_quat(sl['normal']),
                         'extras': {'size': sl['size'], 'slot': sl['id']}}
    for i, t in enumerate(tips):
        A['tip_%d' % i] = {'pos': t['pos'], 'quat': z_axis_quat(t['dir']), 'extras': {'r': t['r']}}
    # parts-plan anchors (car-parts plan, section 6)
    for ai, s_ax in enumerate(axles):
        track = wh['track'] if ai == 0 else wh.get('track_rear', wh['track'])
        for sx, side in ((1, 'r'), (-1, 'l')):
            tag = ('f' if ai == 0 else 'r') + side
            A['hub_' + tag] = {'pos': [sx * track / 2, r, z(s_ax)]}
            A['shock_top_' + tag] = {'pos': [sx * (track / 2 - 0.12), r + wh.get('arch_gap', 0.03) + r + 0.06, z(s_ax)]}
    for sx, side in ((1, 'r'), (-1, 'l')):
        A['strut_top_f' + side] = {'pos': [sx * 0.52, pl(D['top'], cab['A'] - 0.25) - 0.08, z(cab['A'] - 0.25)]}
    A['bay_engine'] = {'pos': [0, 0.45, z(hood_mid + 0.1)]}
    A['bay_turbo'] = {'pos': [0.32, 0.55, z(hood_mid)]}
    A['bay_radiator'] = {'pos': [0, 0.42, z(0.22)]}
    A['bay_intercooler'] = {'pos': [0, 0.30, z(0.12)]}
    route_s = np.linspace(cab['A'] - 0.2, L - 0.1, 4)
    for i, s in enumerate(route_s):
        A['exhaust_route_%d' % i] = {'pos': [-0.25 if i < 3 else 0.0, pl(D['floor'], s) + 0.05, z(s)]}
    A['diff'] = {'pos': [0, r - 0.02, z(axles[1])]}
    A['tank'] = {'pos': [0, pl(D['floor'], axles[1] - 0.5) + 0.12, z(axles[1] - 0.5)]}
    # camera presets (garage design: six per car), -Z looks at the target
    target = [0, 0.55, 0]
    cams = {
        'cam_front_quarter': [3.6, 1.3, -4.2], 'cam_rear_quarter': [-3.6, 1.3, 4.2],
        'cam_side': [5.6, 0.9, 0.0], 'cam_top': [0.0, 5.5, -0.6],
        'cam_under': [0.0, -2.6, 0.0], 'cam_wheel': [2.4, 0.5, z(axles[0]) - 0.6],
    }
    for nm, eye in cams.items():
        tgt = [0, r, z(axles[0])] if nm == 'cam_wheel' else target
        A[nm] = {'pos': eye, 'quat': look_at_quat(eye, tgt, up=(0, 0, -1) if nm in ('cam_top', 'cam_under') else (0, 1, 0))}
    return A


def build_scene(D, build_name):
    opts = build_options(D, build_name)
    Dr = fcar.resolve(D, opts)
    Dr['game_mirrors'] = GAME.get(Dr['id'], {}).get('mirrors', [])
    kit = fparts.kit_of(Dr)
    body, stations = fcar.loft(Dr)
    body_tris = body.array()
    tips = []
    plist, info = fparts.build_parts(Dr, tips)
    R = info['regions']

    # sticker slots: placements as the Godot audit computes them
    import godot_export
    model = fcar.CarModel(Dr)
    slots = []
    for st in Dr.get('stickers', []):
        d = dict(st)
        d['mat'] = 'slot'
        d['cell'] = 0.08
        d['offset'] = 0.012
        d['add'] = False
        placed = fcar.add_decal(model, body_tris, d)
        sl = {'id': st['id'], 'view': st['view'], 'mirror': st.get('mirror', False), 'tris': placed}
        for k, pm in enumerate(godot_export._slot_placements(sl)):
            if pm is None:
                continue
            rect = st['rect']
            size = [round(abs(rect[2] - rect[0]), 3), round(abs(rect[3] - rect[1]), 3)]
            suffix = ''
            if st.get('mirror'):
                suffix = '_l' if pm['center'][0] < 0 else '_r'
            slots.append({'id': st['id'], 'node': 'slot_%s%s' % (st['id'], suffix),
                          'center': pm['center'], 'normal': pm['normal'], 'size': size, 'area': pm['area']})

    # ride height drop: body, parts and slots drop, wheels don't
    drop = Dr.get('drop', 0.0)
    if drop:
        dv = np.array([0, -drop, 0])
        for p in plist:
            p.polys = [q + dv for q in p.polys]
        for t in tips:
            t['pos'][1] = round(t['pos'][1] - drop, 3)
        for sl in slots:
            sl['center'][1] = round(sl['center'][1] - drop, 4)
        for side in info['lamps'].values():
            for c in side.values():
                c[1] -= drop

    # wheels: the sheet's rim and tyre, one mesh per corner, hub at the origin
    wm = fcar.CarModel(Dr)
    fcar.add_wheels(wm)
    wheel_arr = wm.mesh.array()
    wh = Dr['wheel']
    axles = fcar._axles(Dr)
    wheels = {}
    centres = np.array([[t.mean(0)] for t in wheel_arr]).reshape(-1, 3)
    for ai, s_ax in enumerate(axles):
        track = wh['track'] if ai == 0 else wh.get('track_rear', wh['track'])
        for sx, side in ((1, 'r'), (-1, 'l')):
            tag = ('f' if ai == 0 else 'r') + side
            hub = np.array([sx * track / 2, wh['r'], s2z(Dr, s_ax)])
            pick = (np.sign(centres[:, 0]) == sx) & (np.abs(centres[:, 2] - hub[2]) < 0.5)
            wp = fparts.Part('wheel_%s_mesh' % tag, bevel=0)
            for i in np.nonzero(pick)[0]:
                # a kit car's wheels are drawn from this mesh, so they use the assembler's material names
                mat = fparts.MATMAP.get(wm.mesh.mats[i], wm.mesh.mats[i]) if kit else wm.mesh.mats[i]
                wp.add(wheel_arr[i] - hub, mat, fparts.DETAIL)
            if kit.get('wheel'):
                kit['wheel'](Dr, tag, sx, ai, wp)     # brakes, hubcaps: part of the wheel's own mesh
            wheels[tag] = (hub, wp)

    H = hinges(Dr, R)
    H.update(info.get('hinges', {}))
    root = Node(Dr['id'], extras={'build': build_name or 'stock', 'generator': GENERATOR})
    hinge_nodes = {}
    for hname, h in H.items():
        hn = root.add(Node(hname, translation=h['pos'],
                           extras={'axis': h['axis'], 'open_sign': h['open_sign'], 'open_deg': h['open_deg']}))
        hn.origin = np.asarray(h['pos'], float)
        hinge_nodes[hname] = hn
    centre_of = {}
    order = {n: i for i, n in enumerate(fparts.CUT_PARTS)}
    for p in sorted(plist, key=lambda p: (order.get(p.name, 99), p.name)):
        if not len(p):
            continue
        c = np.concatenate(p.polys).mean(axis=0)
        if p.sym == 'centre':
            c[0] = 0.0
        centre_of[p.name] = [round(float(v), 4) for v in c]
        parent = hinge_nodes.get(p.parent, root)
        p.polys = [q - parent.origin for q in p.polys]
        node = parent.add(Node(p.name, mesh=p))
        node.origin = parent.origin
        if p.sym == 'pair':
            # the left twin: the same mesh mirrored, under the mirrored parent
            lparent = hinge_nodes.get(fparts.twin_name(p.parent, hinge_nodes), root) if p.parent else root
            twin = lparent.add(Node(p.twin))
            twin.mirror_of = node
            twin.origin = lparent.origin
            centre_of[p.twin] = [-centre_of[p.name][0], centre_of[p.name][1], centre_of[p.name][2]]
    for hname in [h for h, hn in hinge_nodes.items() if not hn.children]:
        root.children.remove(hinge_nodes.pop(hname))      # a hinge nothing hangs on (a kit without a deck lid)
        H.pop(hname)
    for tag, (hub, wp) in wheels.items():
        wn = root.add(Node('wheel_' + tag, translation=hub, extras={'r': wh['r']}))
        wn.origin = hub
        wn.add(Node(wp.name, mesh=wp)).origin = hub
    A = anchors(Dr, R, tips, slots, centre_of)
    if kit.get('anchors'):
        kit['anchors'](Dr, R, A)
    for name, a in A.items():
        root.add(Node(name, translation=a['pos'], rotation=a.get('quat', (0, 0, 0, 1)), extras=a.get('extras')))

    cols = material_colours(Dr)
    used = sorted({m for n in root.walk() if n.mesh for m in n.mesh.mats})
    is_part = lambda n: n.mesh is not None or n.mirror_of is not None
    meta = {
        'id': Dr['id'], 'build': build_name or 'stock', 'generator': GENERATOR,
        'godot_axes': 'X right, Y up, -Z forward; origin on the ground midway between the axles',
        'dims': {'L': Dr['L'], 'W': Dr['W'], 'WB': Dr['WB'], 'OHf': Dr['OHf'],
                 'H_body': round(float(max(pl(Dr['top'], s) for s in stations)) - drop, 3)},
        'wheels': {'r': wh['r'], 'track': wh['track'], 'axle_z': [round(s2z(Dr, s), 3) for s in axles],
                   'hubs': {tag: [round(float(v), 4) for v in hub] for tag, (hub, _) in wheels.items()}},
        'hinges': H, 'regions': R,
        'shut': {'gap': fparts.GAP, 'return': fparts.RETURN, 'band': fparts.BAND},
        'attributes': {'COLOR_0.r': 'ao: baked vertex ambient occlusion, %d rays, 1 = open' % AO_SAMPLES,
                       'COLOR_0.g': 'shut: 1 on a shut line, 0 at %g mm from it' % (fparts.BAND * 1000)},
        'lamps': info['lamps'], 'mirrors': Dr['game_mirrors'],
        'symmetry': {'rule': 'the left half is the mirror image of the right, vertex for vertex',
                     'mirrored_pairs': sorted(n.mirror_of.name + ' -> ' + n.name for n in root.walk() if n.mirror_of),
                     'not_mirrored': info['asymmetric']},
        'slots': slots, 'exhaust_tips': tips,
        'budget_tris': TRI_BUDGET[2],
        **({'required_slots': kit['slots']} if kit.get('slots') else {}),
        'budget_target': [TRI_BUDGET[0], TRI_BUDGET[1]],
        'materials': {m: cols.get(m, '#C9CED6') for m in used},
        'emissive': sorted(set(frender.EMISSIVE) | {m for m in used if m.startswith('glow_')}),
        'parts': {n.name: (hname if hname in H else None) for hname, hn in [(None, root)] + list(hinge_nodes.items())
                  for n in hn.children if is_part(n)},
    }
    return root, meta, Dr


# --------------------------------------------------------------------------
# Shading shared by both backends
# --------------------------------------------------------------------------
def tri_normals(T):
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    ln = np.linalg.norm(n, axis=1)
    return n, ln


def corner_normals(T, limit_deg=SMOOTH_DEG):
    """Per-corner normals (n,3,3): every corner averages the faces round its
    vertex that are within limit_deg of its own face (area weighted)."""
    if not len(T):
        return np.zeros((0, 3, 3))
    nrm, area = tri_normals(T)
    unit = nrm / np.maximum(area, 1e-12)[:, None]
    keys = np.round(T.reshape(-1, 3) / 1e-5).astype(np.int64)
    _, inv = np.unique(keys, axis=0, return_inverse=True)
    inv = inv.reshape(-1, 3)
    at = {}
    for f in range(len(T)):
        for c in range(3):
            at.setdefault(int(inv[f, c]), []).append(f)
    cos_lim = math.cos(math.radians(limit_deg))
    out = np.zeros_like(T)
    for f in range(len(T)):
        for c in range(3):
            fs = np.array(at[int(inv[f, c])])
            keep = fs[unit[fs] @ unit[f] >= cos_lim]
            n = nrm[keep].sum(axis=0)
            ln = np.linalg.norm(n)
            out[f, c] = n / ln if ln > 1e-12 else unit[f]
    return out


def bake(P, N, occluders, symmetric):
    """Vertex ambient occlusion for one part (car space). A mirrored part is
    baked folded onto the right half, so a vertex and its mirror image get the
    same value to the last bit whatever the few one-sided parts shadow."""
    P = np.array(P, float).reshape(-1, 3)
    N = np.array(N, float).reshape(-1, 3)
    if symmetric:
        left = P[:, 0] < -1e-6
        mid = np.abs(P[:, 0]) <= 1e-6
        P[left, 0] *= -1.0
        N[left, 0] *= -1.0
        N[mid, 0] = np.abs(N[mid, 0])
    ao = fparts.bake_ao(P, N, occluders, samples=AO_SAMPLES)
    if symmetric:
        # two corners that are mirror images can still differ in the last bits
        # of their normals and so in a ray or two: corners at one (folded)
        # point with the same normal to within a few degrees share one value
        keys = np.round(P / 2e-5).astype(np.int64)
        _, inv = np.unique(keys, axis=0, return_inverse=True)
        inv = inv.reshape(-1)
        order = np.argsort(inv, kind='stable')
        start = 0
        while start < len(order):
            end = start
            while end < len(order) and inv[order[end]] == inv[order[start]]:
                end += 1
            seeds = []
            for i in order[start:end]:
                for seed in seeds:
                    if np.abs(N[i] - N[seed[0]]).max() < 0.05:
                        seed.append(i)
                        break
                else:
                    seeds.append([i])
            for seed in seeds:
                ao[seed] = ao[seed].min()
            start = end
    return ao


def _hex(c):
    c = c.lstrip('#')
    return [int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def _linear(c):
    """sRGB 0..1 -> linear, which is what a glTF base colour factor (and a
    Blender colour socket) holds; Godot turns it back into the hex we mean."""
    return [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c]


def _material_json(name, meta):
    col = _linear(_hex(meta['materials'].get(name, '#C9CED6')))
    m = {'name': name, 'pbrMetallicRoughness': {'baseColorFactor': col + [1.0], 'metallicFactor': 0.0, 'roughnessFactor': 0.6}}
    if name in meta['emissive']:
        m['emissiveFactor'] = col
    if name == 'glass':
        m['pbrMetallicRoughness']['roughnessFactor'] = 0.2
    return m


# --------------------------------------------------------------------------
# Backend: pure-Python glTF 2.0 writer
# --------------------------------------------------------------------------
def write_glb_python(root, meta, out_path):
    # triangles, corner normals and the bake, per node
    data = {}
    occ = []
    flip = lambda A: A[:, ::-1, :] * fparts.MIRROR      # mirror triangles (or their normals), winding kept outward
    for node in root.walk():
        src = node.mirror_of or node
        if src.mesh is None or not len(src.mesh):
            continue
        T, M, K, S = src.mesh.tris()
        if src.mesh.sym == 'centre':
            T, M, S = np.concatenate([T, flip(T)]), M + M, np.concatenate([S, S[:, ::-1]])
        N = corner_normals(T)
        if node.mirror_of is not None:
            T, N, S = flip(T), flip(N), S[:, ::-1]
        data[node.name] = [T, M, S, N, None, src.mesh.sym is not None]
        occ.append(T + node.origin)
    occ = np.concatenate(occ)
    for node in root.walk():
        if node.name in data:
            T, M, S, N, _, sym = data[node.name]
            data[node.name][4] = bake(T + node.origin, N, occ, sym).reshape(-1, 3)

    buf = bytearray()
    accessors, buffer_views, meshes, nodes, materials = [], [], [], [], []
    mat_index = {}
    counts = {}

    def material(name):
        if name not in mat_index:
            mat_index[name] = len(materials)
            materials.append(_material_json(name, meta))
        return mat_index[name]

    def accessor(arr, kind, target=34962):
        comp, dt = (5125, '<u4') if kind == 'SCALAR' else (5126, '<f4')
        arr = np.ascontiguousarray(arr, dtype=dt)
        off = len(buf)
        buf.extend(arr.tobytes())
        while len(buf) % 4:
            buf.append(0)
        buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': arr.nbytes, 'target': target})
        acc = {'bufferView': len(buffer_views) - 1, 'componentType': comp, 'count': int(arr.shape[0]), 'type': kind}
        if kind == 'VEC3':
            acc['min'] = [float(v) for v in arr.min(0)]
            acc['max'] = [float(v) for v in arr.max(0)]
        accessors.append(acc)
        return len(accessors) - 1

    def mesh_for(node):
        T, M, S, N, AO, _ = data[node.name]
        counts[node.name] = len(T)
        prims = []
        for m in sorted(set(M)):
            idx = [i for i, mm in enumerate(M) if mm == m]
            pos = T[idx].reshape(-1, 3)
            nn = N[idx].reshape(-1, 3)
            col = np.column_stack([AO[idx].reshape(-1), S[idx].reshape(-1), np.zeros(len(pos)), np.ones(len(pos))])
            packed = np.round(np.hstack([pos / 1e-5, nn / 1e-3, col / 1e-3])).astype(np.int64)
            _, first, inv = np.unique(packed, axis=0, return_index=True, return_inverse=True)
            prims.append({'attributes': {'POSITION': accessor(pos[first], 'VEC3'), 'NORMAL': accessor(nn[first], 'VEC3'),
                                         'COLOR_0': accessor(col[first], 'VEC4')},
                          'indices': accessor(inv.reshape(-1), 'SCALAR', 34963), 'material': material(m), 'mode': 4})
        meshes.append({'name': node.name, 'primitives': prims})
        return len(meshes) - 1

    def emit(node):
        n = {'name': node.name}
        if any(abs(v) > 1e-9 for v in node.translation):
            n['translation'] = node.translation
        if any(abs(a - b) > 1e-9 for a, b in zip(node.rotation, (0, 0, 0, 1))):
            n['rotation'] = node.rotation
        if node.extras:
            n['extras'] = node.extras
        if node.name in data:
            n['mesh'] = mesh_for(node)
        nodes.append(n)
        me = len(nodes) - 1
        kids = [emit(c) for c in node.children]
        if kids:
            nodes[me]['children'] = kids
        return me

    top = emit(root)
    gltf = {
        'asset': {'version': '2.0', 'generator': GENERATOR + ' (python backend)'},
        'scene': 0, 'scenes': [{'nodes': [top]}],
        'nodes': nodes, 'meshes': meshes, 'materials': materials,
        'accessors': accessors, 'bufferViews': buffer_views,
        'buffers': [{'byteLength': len(buf)}],
    }
    js = json.dumps(gltf, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    total = 12 + 8 + len(js) + 8 + len(buf)
    with open(out_path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack('<II', len(buf), 0x004E4942))
        f.write(bytes(buf))
    return counts


# --------------------------------------------------------------------------
# Backend: Blender (bpy)
# --------------------------------------------------------------------------
def write_glb_blender(root, meta, out_path, D, bevel=True, keep_blend=None):
    import bmesh
    import bpy
    from mathutils import Matrix, Quaternion, Vector

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    # glTF/Godot (x, y, z) -> Blender (x, -z, y); Blender's exporter (Y up) maps it back.
    C = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float)

    def to_bl(v):
        return Vector((float(v[0]), -float(v[2]), float(v[1])))

    def quat_bl(q):
        x, y, z, w = q
        m = np.array(Quaternion((w, x, y, z)).to_matrix())
        return Matrix((C @ m @ C.T).tolist()).to_quaternion()

    mats = {}

    def material(name):
        if name in mats:
            return mats[name]
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        col = _linear(_hex(meta['materials'].get(name, '#C9CED6')))
        m.diffuse_color = (*col, 1.0)      # what the viewport shows in solid mode
        bsdf = m.node_tree.nodes.get('Principled BSDF')
        if bsdf:
            bsdf.inputs['Base Color'].default_value = (*col, 1.0)
            bsdf.inputs['Metallic'].default_value = 0.0
            bsdf.inputs['Roughness'].default_value = 0.2 if name == 'glass' else 0.6
            if name in meta['emissive']:
                for key in ('Emission Color', 'Emission'):
                    if key in bsdf.inputs:
                        bsdf.inputs[key].default_value = (*col, 1.0)
                        break
                if 'Emission Strength' in bsdf.inputs:
                    bsdf.inputs['Emission Strength'].default_value = 1.0
        mats[name] = m
        return m

    def build_mesh(node):
        """The part as a welded mesh with its creases weighted for the bevel."""
        part = node.mesh
        verts, loops = fparts.weld(part.polys)
        vshut = np.zeros(len(verts))
        for loop, sh in zip(loops, part.shut):
            for v, s in zip(loop, sh):
                vshut[v] = max(vshut[v], float(s))
        names = sorted(set(part.mats))
        bm = bmesh.new()
        l_shut = bm.verts.layers.float.new('shut')
        l_kind = bm.faces.layers.int.new('kind')
        l_w = bm.edges.layers.float.new('bevel_weight_edge')
        bv = []
        for co, s in zip(verts, vshut):
            v = bm.verts.new(to_bl(co))
            v[l_shut] = s
            bv.append(v)
        for loop, mat, kind in zip(loops, part.mats, part.kind):
            ring = [loop[i] for i in range(len(loop)) if loop[i] != loop[i - 1]]
            if len(set(ring)) < 3 or len(set(ring)) != len(ring):
                continue
            try:
                f = bm.faces.new([bv[i] for i in ring])
            except ValueError:
                continue
            f.material_index = names.index(mat)
            f[l_kind] = int(kind)
            f.smooth = True
        bm.normal_update()
        bm.edges.ensure_lookup_table()
        n_bev = 0
        width = part.bevel
        if bevel and width != 0:
            limit = math.radians(SMOOTH_DEG)
            for e in bm.edges:
                if len(e.link_faces) != 2 or any(f[l_kind] != fparts.SKIN for f in e.link_faces):
                    continue
                if e.calc_face_angle(0.0) <= limit:
                    continue
                w = width
                if w is None:
                    pts = [np.array([v.co.x, v.co.z, -v.co.y]) + node.origin for v in e.verts]
                    ja, jb = (fparts.on_curve(D, p, js=WIDE_CURVES) for p in pts)
                    w = BEVEL_WIDE if ja is not None and ja == jb else BEVEL
                e[l_w] = min(1.0, w / BEVEL_WIDE)
                n_bev += 1
        me = bpy.data.meshes.new(node.name)
        bm.to_mesh(me)
        bm.free()
        for nm in names:
            me.materials.append(material(nm))
        return me, n_bev

    def shape_mesh(ob, n_bev, centre):
        """Apply the bevel and triangulate; a centre part then gets its left half."""
        if n_bev:
            mod = ob.modifiers.new('Bevel', 'BEVEL')
            mod.width = BEVEL_WIDE
            mod.segments = 1
            mod.limit_method = 'WEIGHT'
            mod.offset_type = 'OFFSET'
            mod.use_clamp_overlap = True
            mod.harden_normals = False
            dg = bpy.context.evaluated_depsgraph_get()
            me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
            ob.modifiers.clear()
            old, name = ob.data, ob.data.name
            ob.data = me
            bpy.data.meshes.remove(old)
            me.name = name
        me = ob.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='BEAUTY')
        # a triangle with no area has no normal of its own and shades as a speck: take those out
        bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='BEAUTY')
        if centre:
            # the mirror image, welded along the centre line (object x = car x)
            before = set(bm.faces)
            bmesh.ops.mirror(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], matrix=Matrix.Identity(4),
                             merge_dist=2e-5, axis='X')
            # the copy comes back wound like the original: turn it to face outward
            bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f not in before])
        bm.to_mesh(me)
        bm.free()

    def mirrored_mesh(src, name):
        """A left-hand twin: the right-hand mesh mirrored, faces turned back outward."""
        bm = bmesh.new()
        bm.from_mesh(src)
        for v in bm.verts:
            v.co.x = -v.co.x
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in src.materials:
            me.materials.append(m)
        return me

    def shade_mesh(ob):
        """Mark the hard edges and weight the normals."""
        me = ob.data
        me.polygons.foreach_set('use_smooth', [True] * len(me.polygons))
        me.set_sharp_from_angle(angle=math.radians(SMOOTH_DEG))
        mod = ob.modifiers.new('Normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        mod.mode = 'FACE_AREA'
        mod.weight = 50
        dg = bpy.context.evaluated_depsgraph_get()
        me2 = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        ob.modifiers.clear()
        name = me.name
        ob.data = me2
        bpy.data.meshes.remove(me)
        me2.name = name

    def mirror_normals(src, dst):
        """Give every left-hand corner of dst the mirror image of the normal of
        its right-hand partner in src (src is dst for a part that straddles
        the centre line). The two were computed apart and can differ in the
        last bits where a face is a sliver; this makes them one."""
        def corners(me, fold):
            """Per corner: a key that is the same for a corner and its mirror
            image (its own position and its triangle's three, mirrored exactly;
            no rounding, a mirror copy is bit for bit), the triangle's side and
            the normal."""
            n = len(me.loops)
            co = np.zeros(len(me.vertices) * 3)
            me.vertices.foreach_get('co', co)
            co = co.reshape(-1, 3)
            co[np.abs(co[:, 0]) < 1e-6, 0] = 0.0
            vi = np.zeros(n, dtype=np.int32)
            me.loops.foreach_get('vertex_index', vi)
            cn = np.zeros(n * 3)
            me.corner_normals.foreach_get('vector', cn)
            tri = co[vi].reshape(-1, 3, 3)                 # every face is a triangle by now
            side = np.repeat(tri[:, :, 0].sum(axis=1), 3)
            if fold:
                tri = tri * flip
            keys = []
            for t in tri:
                pts = [tuple(p) for p in t]
                whole = tuple(sorted(pts))
                keys += [(q, whole) for q in pts]
            return keys, side, cn.reshape(-1, 3)

        flip = np.array([-1.0, 1.0, 1.0])
        same = src is dst
        sk, sside, sn = corners(src.data, False)
        table = {k: sn[i] for i, k in enumerate(sk) if not same or sside[i] > 0}
        dk, dside, dn = corners(dst.data, True)
        out = dn.copy()
        missed = 0
        for i, k in enumerate(dk):
            if same and dside[i] >= 0:
                continue
            n = table.get(k)
            if n is None:
                missed += 1
            else:
                out[i] = n * flip
        dst.data.normals_split_custom_set([tuple(float(c) for c in n) for n in out])
        return missed

    objects = {}

    def make_object(node, parent):
        n_bev = 0
        if node.mesh is not None and len(node.mesh):
            me, n_bev = build_mesh(node)
            ob = bpy.data.objects.new(node.name, me)
        elif node.mirror_of is not None:
            ob = bpy.data.objects.new(node.name, bpy.data.meshes.new(node.name))   # filled from its twin below
        else:
            ob = bpy.data.objects.new(node.name, None)
            ob.empty_display_type = 'PLAIN_AXES'
            ob.empty_display_size = 0.08
        for k, v in (node.extras or {}).items():
            ob[k] = v
        scene.collection.objects.link(ob)
        ob.parent = parent
        ob.matrix_parent_inverse = Matrix.Identity(4)
        ob.location = to_bl(node.translation)
        ob.rotation_mode = 'QUATERNION'
        ob.rotation_quaternion = quat_bl(node.rotation)
        if ob.data is not None:
            objects[node.name] = (ob, node, n_bev)
        for c in node.children:
            make_object(c, ob)
        return ob

    make_object(root, None)
    bpy.context.view_layer.update()
    counts, bevelled = {}, {}
    for name, (ob, node, n_bev) in objects.items():
        if node.mirror_of is None:
            shape_mesh(ob, n_bev, node.mesh.sym == 'centre')
            bevelled[name] = n_bev * (2 if node.mesh.sym == 'centre' else 1)
    for name, (ob, node, n_bev) in objects.items():
        if node.mirror_of is not None:
            empty = ob.data
            ob.data = mirrored_mesh(objects[node.mirror_of.name][0].data, name + '.mirror')
            bpy.data.meshes.remove(empty)
            ob.data.name = name
            bevelled[name] = bevelled[node.mirror_of.name]
    for name, (ob, node, n_bev) in objects.items():
        shade_mesh(ob)
    unmatched = 0
    for name, (ob, node, n_bev) in objects.items():
        if node.mirror_of is not None:
            unmatched += mirror_normals(objects[node.mirror_of.name][0], ob)
        elif node.mesh.sym == 'centre':
            unmatched += mirror_normals(ob, ob)
    if unmatched:
        raise SystemExit('%d corners have no mirror partner: the model is not symmetric' % unmatched)

    # the bake, on what is exported: corner positions and normals in car space
    geo = {}
    occ = []
    for name, (ob, node, _) in objects.items():
        me = ob.data
        nl = len(me.loops)
        co = np.zeros(len(me.vertices) * 3)
        me.vertices.foreach_get('co', co)
        co = co.reshape(-1, 3)
        vi = np.zeros(nl, dtype=np.int32)
        me.loops.foreach_get('vertex_index', vi)
        cn = np.zeros(nl * 3)
        me.corner_normals.foreach_get('vector', cn)
        cn = cn.reshape(-1, 3)
        to_car = lambda a: np.column_stack([a[:, 0], a[:, 2], -a[:, 1]])
        P = to_car(co[vi]) + node.origin
        N = to_car(cn)
        ls = np.zeros(len(me.polygons), dtype=np.int32)
        me.polygons.foreach_get('loop_start', ls)
        tri = np.stack([P[ls], P[ls + 1], P[ls + 2]], axis=1)
        geo[name] = (P, N, vi)
        occ.append(tri)
        counts[name] = len(me.polygons)
    occ = np.concatenate(occ)
    for name, (ob, node, _) in objects.items():
        me = ob.data
        P, N, vi = geo[name]
        ao = bake(P, N, occ, (node.mirror_of or node).mesh.sym is not None)
        shut = np.zeros(len(me.vertices))
        if 'shut' in me.attributes:
            me.attributes['shut'].data.foreach_get('value', shut)
        vao = np.ones(len(me.vertices))
        np.minimum.at(vao, vi, ao)
        if 'ao' not in me.attributes:
            me.attributes.new('ao', 'FLOAT', 'POINT')
        me.attributes['ao'].data.foreach_set('value', vao)
        col = np.column_stack([ao, shut[vi], np.zeros(len(vi)), np.ones(len(vi))])
        ca = me.color_attributes.new('ao_shut', 'FLOAT_COLOR', 'CORNER')
        ca.data.foreach_set('color', col.reshape(-1))
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = list(me.color_attributes).index(ca)

    if keep_blend:
        bpy.ops.wm.save_as_mainfile(filepath=keep_blend)
    kwargs = dict(filepath=out_path, export_format='GLB', export_yup=True, export_apply=False,
                  export_materials='EXPORT', export_extras=True, export_cameras=False,
                  export_lights=False, export_normals=True, export_texcoords=False, export_animations=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                                  export_active_vertex_color_when_no_material=True, **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(**kwargs)
    return counts, bevelled


def choose_backend(name):
    if name == 'python':
        return 'python'
    try:
        import bpy  # noqa: F401
        return 'blender'
    except ImportError:
        if name == 'blender':
            raise SystemExit('bpy is not importable: run inside Blender (blender -b --python ...); '
                             'or pass --backend python')
        return 'python'


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def git_head():
    try:
        return subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, text=True).strip()
    except Exception:
        return 'unknown'


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
        if '--' in argv:
            argv = argv[argv.index('--') + 1:]
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('car_id')
    ap.add_argument('--build', default='stock', help='stock or a build name from the car definition')
    ap.add_argument('--out', default=ASSETS, help='assets folder (default assets/cars)')
    ap.add_argument('--backend', default='auto', choices=['auto', 'blender', 'python'])
    ap.add_argument('--no-bevel', action='store_true', help='Blender backend: skip the crease bevel')
    ap.add_argument('--blend', default=None, help='Blender backend: also save the scene as this .blend to look at')
    args = ap.parse_args(argv)

    D = definition(args.car_id)
    root, meta, Dr = build_scene(D, args.build)
    backend = choose_backend(args.backend)
    out_dir = os.path.join(args.out, args.car_id)
    os.makedirs(out_dir, exist_ok=True)
    stem = 'body' if args.build in (None, 'stock') else 'body_%s' % args.build
    glb = os.path.join(out_dir, stem + '.glb')
    bevelled = {}
    if backend == 'blender':
        counts, bevelled = write_glb_blender(root, meta, glb, Dr, bevel=not args.no_bevel, keep_blend=args.blend)
    else:
        counts = write_glb_python(root, meta, glb)

    wheels = sum(v for k, v in counts.items() if k.startswith('wheel_'))
    meta['backend'] = backend
    meta['bevel'] = backend == 'blender' and not args.no_bevel
    meta['bevel_mm'] = [BEVEL * 1000, BEVEL_WIDE * 1000] if meta['bevel'] else []
    meta['bevelled_edges'] = int(sum(bevelled.values()))
    meta['source_commit'] = git_head()
    meta['nodes'] = [n.name for n in root.walk()]
    meta['tris'] = counts
    meta['tris_total'] = int(sum(counts.values()))
    meta['tris_body'] = meta['tris_total'] - int(wheels)
    with open(os.path.join(out_dir, stem + '.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('%s: %d triangles in %d meshes (%d without the wheels; target %d-%d, ceiling %d), %d nodes, backend %s%s -> %s' % (
        args.car_id, meta['tris_total'], len(counts), meta['tris_body'], TRI_BUDGET[0], TRI_BUDGET[1], TRI_BUDGET[2],
        len(meta['nodes']), backend, ' (bevel on %d edges)' % meta['bevelled_edges'] if meta['bevel'] else '',
        os.path.relpath(glb, ROOT)))
    for k, v in counts.items():
        print('  %-18s %5d' % (k, v))
    if meta['tris_body'] > TRI_BUDGET[2]:
        raise SystemExit('%d body triangles is over the ceiling of %d' % (meta['tris_body'], TRI_BUDGET[2]))


if __name__ == '__main__':
    main()
