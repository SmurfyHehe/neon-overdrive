"""Car modelling pipeline, step 1 (docs/planning/car-look-showcase-2026-10-09.md,
section 12): build one car's body as a real mesh from its fleet numbers and
export it as glTF for Godot, with the panels that open as separate pieces and
named empties for everything that bolts on later.

    python tools/car_pipeline/build_car.py p1_coupe
    python tools/car_pipeline/build_car.py p1_coupe --build street --backend python
    blender --background --python tools/car_pipeline/build_car.py -- p1_coupe

Output (per car, per build):
    assets/cars/<id>/body.glb     the model
    assets/cars/<id>/body.json    what is in it: nodes, triangles, slots, tips,
                                  wheels, hinges, materials, dims

Where the numbers come from: the same definitions `tools/fleet_design/` uses
to draw the design sheets and to write `docs/design/fleet/fleet.json`
(`cars.py`, `options.py`). The sheet, the audit proxies and this model are
therefore one shape; a change to the car's numbers rebuilds all three. The
car id is looked up in fleet.json so the two can never name different cars.

Scene graph (glTF, Godot axes: X right, Y up, -Z forward, origin on the
ground midway between the axles):

    <id>
      body                   paint shell: everything that never moves
      hinge_hood             empty on the hinge line (rear of the hood, at the cowl)
        hood                 the hood panel, in hinge-local coordinates
      hinge_door_l/r         empties on the A-pillar hinge line, axis vertical
        door_l/r             door panel plus its glass
      hinge_trunk            empty on the deck hinge line (front of the lid)
        trunk                the lid
      mirrors, spoiler, popups, exhaust, ...   the car's own parts, one mesh each
      wheel_fl/fr/rl/rr      empties on the hubs
        wheel_*              the design-sheet wheel (rim + tyre), hub at origin
      slot_door_l/r, slot_hood, slot_sunstrip, slot_rear   sticker slots (+Z = outward normal)
      tip_0..n               exhaust tips (+Z = exhaust direction)
      mount_*                where body-shop parts attach (bumpers, skirts, wing, hood, lamps)
      hub_*, shock_top_*, strut_top_fl/fr, bay_*, exhaust_route_0..n, diff, tank
                             anchors for the real parts (car-parts plan, section 6)
      cam_*                  six camera presets, -Z looking at the car

Backends:
    blender   Blender's Python (bpy): welded mesh, one bevel loop on hard
              edges (angle limited), material slots, empties, glTF export by
              Blender's exporter. Picked automatically when `import bpy` works.
    python    a small glTF 2.0 writer with no dependencies beyond numpy: same
              scene graph, same materials, flat shaded, no bevel. This is what
              runs when Blender is not installed, so the pipeline never blocks
              on it; the bevel pass is the only thing it lacks.

Materials are one glTF material per fleet material name (paint, roof, glass,
trim, under, chrome, rim, tire, head, tail, ...), colours from the car's
paint set and tools/fleet_design/render.BASE_MATS. Step 3 replaces them with
the one car shader; the names are what it keys on.
"""
import argparse
import json
import math
import os
import struct
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
FLEET_DESIGN = os.path.join(ROOT, 'tools', 'fleet_design')
FLEET_JSON = os.path.join(ROOT, 'docs', 'design', 'fleet', 'fleet.json')
ASSETS = os.path.join(ROOT, 'assets', 'cars')
sys.path.insert(0, FLEET_DESIGN)

import car as fcar          # noqa: E402
import cars as fcars        # noqa: E402
import render as frender    # noqa: E402
from geom import Mesh, pl   # noqa: E402

GENERATOR = 'neon-overdrive tools/car_pipeline/build_car.py'
BEVEL_WIDTH = 0.012        # one chamfer loop, 1.2 cm (car-look section 2, pass 1)
BEVEL_ANGLE_DEG = 30.0     # only edges sharper than this get the loop
WELD_EPS = 1e-4


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
    """Hex colour per material name: the car's own first, then the base set."""
    cols = dict(frender.BASE_MATS)
    own = fcars.colors_for(D)
    for k, v in own.items():
        if v:
            cols[k] = v
    if not cols.get('roof'):
        cols['roof'] = cols['paint']
    if own.get('rim') and 'rim_bronze' not in own:
        cols['rim_bronze'] = own['rim']
    return cols


# --------------------------------------------------------------------------
# Triangle soup helpers (n,3,3) + material per triangle
# --------------------------------------------------------------------------
def tri_normals(tris):
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    n = np.cross(b - a, c - a)
    ln = np.linalg.norm(n, axis=1)
    ln[ln < 1e-12] = 1.0
    return n / ln[:, None]


def clip_triangle(tri, n, d):
    """Split one triangle by the plane n.p >= d. Returns (inside, outside) lists."""
    dist = [float(np.dot(n, p) - d) for p in tri]
    inside = [i for i in range(3) if dist[i] >= 0]
    if len(inside) == 3:
        return [tri], []
    if not inside:
        return [], [tri]

    def lerp(i, j):
        t = dist[i] / (dist[i] - dist[j])
        return tri[i] + (tri[j] - tri[i]) * t

    if len(inside) == 1:
        i = inside[0]
        j, k = (i + 1) % 3, (i + 2) % 3
        pij, pik = lerp(i, j), lerp(i, k)
        return [np.array([tri[i], pij, pik])], [np.array([pij, tri[j], tri[k]]), np.array([pij, tri[k], pik])]
    o = [i for i in range(3) if i not in inside][0]
    j, k = (o + 1) % 3, (o + 2) % 3
    poj, pok = lerp(o, j), lerp(o, k)
    return [np.array([poj, tri[j], tri[k]]), np.array([poj, tri[k], pok])], [np.array([tri[o], poj, pok])]


def _real(tris):
    """Drop the zero-area slivers a cut exactly through a vertex leaves behind."""
    return [t for t in tris if np.linalg.norm(np.cross(t[1] - t[0], t[2] - t[0])) > 1e-9]


def clip(tris, mats, n, d):
    n = np.asarray(n, float)
    tin, min_, tout, mout = [], [], [], []
    for t, m in zip(tris, mats):
        a, b = clip_triangle(t, n, d)
        a, b = _real(a), _real(b)
        tin += a
        min_ += [m] * len(a)
        tout += b
        mout += [m] * len(b)
    return tin, min_, tout, mout


def split_region(tris, mats, planes, normal_test=None):
    """Triangles inside the convex region (all planes n.p >= d) vs the rest.
    normal_test(normals) -> bool mask picks candidate triangles first (no cut)."""
    tris = list(tris)
    mats = list(mats)
    if normal_test is not None and tris:
        mask = normal_test(tri_normals(np.array(tris)))
        pool_t = [t for t, k in zip(tris, mask) if k]
        pool_m = [m for m, k in zip(mats, mask) if k]
        out_t = [t for t, k in zip(tris, mask) if not k]
        out_m = [m for m, k in zip(mats, mask) if not k]
    else:
        pool_t, pool_m, out_t, out_m = tris, mats, [], []
    for n, d in planes:
        pool_t, pool_m, rej_t, rej_m = clip(pool_t, pool_m, n, d)
        out_t += rej_t
        out_m += rej_m
    return (pool_t, pool_m), (out_t, out_m)


def area(tris):
    if not len(tris):
        return 0.0
    t = np.asarray(tris)
    return float(0.5 * np.linalg.norm(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]), axis=1).sum())


# --------------------------------------------------------------------------
# Geometry: body, panels, parts, wheels, anchors
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
        self.mesh = mesh          # (tris list, mats list) in this node's local frame
        self.children = []
        self.extras = extras or {}

    def add(self, child):
        self.children.append(child)
        return child

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


def panel_regions(D):
    """Where the hood, doors and trunk are cut out of the loft (car space, s along
    the length from the nose). Kept as data so another car can override them."""
    cab = D['cabin']
    hw_mid = pl(D['hw'], 0.5 * (cab['A'] + cab['W']))
    regions = D.get('panels') or {}
    hood_s0 = regions.get('hood_s0', 0.55)
    hood_hw = regions.get('hood_hw', min(0.70, hw_mid - 0.17))
    door_s0 = regions.get('door_s0', cab['A'] + 0.04)
    pillars = cab.get('pillars') or [[cab['A'] + 1.1, cab['A'] + 1.16]]
    door_s1 = regions.get('door_s1', pillars[0][0])
    door_y0 = regions.get('door_y0', D.get('rocker_h', 0.3) + 0.01)
    trunk_s0 = regions.get('trunk_s0', cab['C'] + 0.03)
    trunk_s1 = regions.get('trunk_s1', D['L'] - 0.15)
    trunk_hw = regions.get('trunk_hw', min(0.66, pl(D['hw'], trunk_s0) - 0.2))
    return {
        'hood': {'s0': hood_s0, 's1': cab['A'], 'hw': hood_hw},
        'door': {'s0': door_s0, 's1': door_s1, 'y0': door_y0, 'x_in': 0.5},
        'trunk': {'s0': trunk_s0, 's1': trunk_s1, 'hw': trunk_hw},
    }


def cut_panels(D, tris, mats):
    """Returns dict name -> (tris, mats) for shell, hood, door_l, door_r, trunk."""
    R = panel_regions(D)
    z = lambda s: s2z(D, s)
    out = {}
    up = lambda n: n[:, 1] > 0.3
    side_r = lambda n: n[:, 0] > 0.5
    side_l = lambda n: n[:, 0] < -0.5

    h = R['hood']
    (hood, rest) = split_region(tris, mats, [((0, 0, 1), z(h['s0'])), ((0, 0, -1), -z(h['s1'])),
                                            ((1, 0, 0), -h['hw']), ((-1, 0, 0), -h['hw'])], up)
    out['hood'] = hood
    tris, mats = rest

    t = R['trunk']
    (trunk, rest) = split_region(tris, mats, [((0, 0, 1), z(t['s0'])), ((0, 0, -1), -z(t['s1'])),
                                             ((1, 0, 0), -t['hw']), ((-1, 0, 0), -t['hw'])], up)
    out['trunk'] = trunk
    tris, mats = rest

    d = R['door']
    (door_r, rest) = split_region(tris, mats, [((0, 0, 1), z(d['s0'])), ((0, 0, -1), -z(d['s1'])),
                                              ((0, 1, 0), d['y0']), ((1, 0, 0), d['x_in'])], side_r)
    out['door_r'] = door_r
    tris, mats = rest
    (door_l, rest) = split_region(tris, mats, [((0, 0, 1), z(d['s0'])), ((0, 0, -1), -z(d['s1'])),
                                              ((0, 1, 0), d['y0']), ((-1, 0, 0), d['x_in'])], side_l)
    out['door_l'] = door_l
    out['body'] = rest
    return out, R


def hinges(D, R):
    """Hinge empties: position and the axis (unit, car space) the panel turns on,
    plus the sign that opens it (right-hand rule about the axis)."""
    cab = D['cabin']
    z = lambda s: s2z(D, s)
    hood_y = pl(D['top'], cab['A'])
    hw_door = pl(D['hw'], R['door']['s0'])
    belt = pl(D['belt'], R['door']['s0'])
    trunk_y = pl(D['top'], R['trunk']['s0'])
    return {
        'hinge_hood': {'pos': [0.0, hood_y - 0.01, z(cab['A'] - 0.02)], 'axis': [1, 0, 0], 'open_sign': 1,
                       'open_deg': 45, 'panel': 'hood'},
        'hinge_trunk': {'pos': [0.0, trunk_y - 0.01, z(R['trunk']['s0'])], 'axis': [1, 0, 0], 'open_sign': -1,
                        'open_deg': 50, 'panel': 'trunk'},
        'hinge_door_r': {'pos': [hw_door - 0.02, 0.5 * (R['door']['y0'] + belt), z(R['door']['s0'])],
                         'axis': [0, 1, 0], 'open_sign': 1, 'open_deg': 60, 'panel': 'door_r'},
        'hinge_door_l': {'pos': [-(hw_door - 0.02), 0.5 * (R['door']['y0'] + belt), z(R['door']['s0'])],
                         'axis': [0, 1, 0], 'open_sign': -1, 'open_deg': 60, 'panel': 'door_l'},
    }


def anchors(D, R, tips, slots, parts_meta):
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
    wing = parts_meta.get('spoiler')
    A['mount_wing'] = {'pos': wing['center'] if wing else [0, pl(D['top'], L - 0.25), z(L - 0.25)]}
    A['mount_hood'] = {'pos': [0, pl(D['top'], 0.5 * (R['hood']['s0'] + R['hood']['s1'])),
                               z(0.5 * (R['hood']['s0'] + R['hood']['s1']))]}
    lamps = parts_meta.get('popups')
    if lamps:
        A['lamp_l'] = {'pos': [-abs(lamps['center'][0]), lamps['center'][1], lamps['center'][2]]}
        A['lamp_r'] = {'pos': [abs(lamps['center'][0]), lamps['center'][1], lamps['center'][2]]}
    else:
        A['lamp_l'] = {'pos': [-0.6, pl(D['top'], 0.1) - 0.05, z(0.08)]}
        A['lamp_r'] = {'pos': [0.6, pl(D['top'], 0.1) - 0.05, z(0.08)]}
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
            hub = [sx * track / 2, r, z(s_ax)]
            A['hub_' + tag] = {'pos': hub}
            A['shock_top_' + tag] = {'pos': [sx * (track / 2 - 0.12), r + wh.get('arch_gap', 0.03) + r + 0.06, z(s_ax)]}
    for sx, side in ((1, 'r'), (-1, 'l')):
        A['strut_top_f' + side] = {'pos': [sx * 0.52, pl(D['top'], cab['A'] - 0.25) - 0.08, z(cab['A'] - 0.25)]}
    bay_mid = 0.5 * (R['hood']['s0'] + R['hood']['s1'])
    A['bay_engine'] = {'pos': [0, 0.45, z(bay_mid + 0.1)]}
    A['bay_turbo'] = {'pos': [0.32, 0.55, z(bay_mid)]}
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
    model = fcar.CarModel(Dr)
    body, stations = fcar.loft(Dr)
    body_tris = body.array()
    model.mesh.extend(body)
    for i, d in enumerate(Dr.get('decals', [])):
        fcar.add_decal(model, body_tris, d, offset=0.004 + 0.0015 * i)
    shell_tris, shell_mats = list(model.mesh.tris), list(model.mesh.mats)
    shell_tris = [np.array(t) for t in shell_tris]

    # parts, one mesh each, named by tag or type
    parts = {}
    parts_meta = {}
    for p in Dr.get('parts', []):
        pm = fcar.CarModel(Dr)
        fcar.add_part(pm, p)
        if not len(pm.mesh):
            continue
        name = p.get('tag') or p['type']
        parts.setdefault(name, Mesh()).extend(pm.mesh)
    for name, m in parts.items():
        arr = m.array()
        parts_meta[name] = {'center': [round(float(v), 4) for v in arr.reshape(-1, 3).mean(0)], 'tris': len(m)}

    # exhaust (its own mesh) and the tips
    em = fcar.CarModel(Dr)
    tips = fcar.add_exhaust(em, body_tris)
    if len(em.mesh):
        parts['exhaust'] = em.mesh

    # sticker slots: placements as the Godot audit computes them
    import godot_export
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
        shell_tris = [t + dv for t in shell_tris]
        for m in parts.values():
            m.translate(dv)
        for t in tips:
            t['pos'][1] = round(t['pos'][1] - drop, 3)
        for sl in slots:
            sl['center'][1] = round(sl['center'][1] - drop, 4)

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
            tris = [wheel_arr[i] - hub for i in np.nonzero(pick)[0]]
            mats = [wm.mesh.mats[i] for i in np.nonzero(pick)[0]]
            wheels[tag] = (hub, tris, mats)

    # cut the opening panels out of the shell
    panels, R = cut_panels(Dr, shell_tris, shell_mats)
    H = hinges(Dr, R)

    root = Node(Dr['id'], extras={'build': build_name or 'stock', 'generator': GENERATOR})
    root.add(Node('body', mesh=panels['body']))
    for hname, h in H.items():
        hn = root.add(Node(hname, translation=h['pos'],
                           extras={'axis': h['axis'], 'open_sign': h['open_sign'], 'open_deg': h['open_deg']}))
        ptris, pmats = panels[h['panel']]
        hv = np.asarray(h['pos'], float)
        hn.add(Node(h['panel'], mesh=([t - hv for t in ptris], pmats)))
    for name, m in parts.items():
        root.add(Node(name, mesh=(list(m.array()), list(m.mats))))
    for tag, (hub, tris, mats) in wheels.items():
        wn = root.add(Node('wheel_' + tag, translation=hub, extras={'r': wh['r']}))
        wn.add(Node('wheel_%s_mesh' % tag, mesh=(tris, mats)))
    for name, a in anchors(Dr, R, tips, slots, parts_meta).items():
        root.add(Node(name, translation=a['pos'], rotation=a.get('quat', (0, 0, 0, 1)), extras=a.get('extras')))

    meta = {
        'id': Dr['id'], 'build': build_name or 'stock', 'generator': GENERATOR,
        'godot_axes': 'X right, Y up, -Z forward; origin on the ground midway between the axles',
        'dims': {'L': Dr['L'], 'W': Dr['W'], 'WB': Dr['WB'], 'OHf': Dr['OHf'],
                 'H_body': round(float(max(pl(Dr['top'], s) for s in stations)) - drop, 3)},
        'wheels': {'r': wh['r'], 'track': wh['track'], 'axle_z': [round(s2z(Dr, s), 3) for s in axles],
                   'hubs': {tag: [round(float(v), 4) for v in hub] for tag, (hub, _, _) in wheels.items()}},
        'hinges': H, 'panel_regions': R,
        'slots': slots, 'exhaust_tips': tips,
        'budget_tris': 10000 if Dr.get('role') == 'player' else (6000 if Dr.get('role') == 'cop' else 4000),
        'materials': {m: material_colours(Dr).get(m, '#C9CED6') for m in sorted({mm for n in root.walk() if n.mesh for mm in n.mesh[1]})},
        'emissive': sorted(frender.EMISSIVE),
    }
    return root, meta


# --------------------------------------------------------------------------
# Backend: pure-Python glTF 2.0 writer
# --------------------------------------------------------------------------
def _hex(c):
    c = c.lstrip('#')
    return [int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def write_glb_python(root, meta, out_path):
    buf = bytearray()
    accessors, buffer_views, meshes, nodes, materials = [], [], [], [], []
    mat_index = {}

    def material(name):
        if name in mat_index:
            return mat_index[name]
        col = _hex(meta['materials'].get(name, '#C9CED6'))
        m = {'name': name, 'pbrMetallicRoughness': {'baseColorFactor': col + [1.0], 'metallicFactor': 0.0, 'roughnessFactor': 0.6}}
        if name in meta['emissive']:
            m['emissiveFactor'] = col
        if name == 'glass':
            m['pbrMetallicRoughness']['roughnessFactor'] = 0.2
        mat_index[name] = len(materials)
        materials.append(m)
        return mat_index[name]

    def accessor(arr):
        arr = np.ascontiguousarray(arr, dtype='<f4')
        off = len(buf)
        buf.extend(arr.tobytes())
        while len(buf) % 4:
            buf.append(0)
        buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': arr.nbytes, 'target': 34962})
        accessors.append({'bufferView': len(buffer_views) - 1, 'componentType': 5126, 'count': int(arr.shape[0]),
                          'type': 'VEC3', 'min': [float(v) for v in arr.min(0)], 'max': [float(v) for v in arr.max(0)]})
        return len(accessors) - 1

    def mesh_for(node):
        tris, mats = node.mesh
        if not len(tris):
            return None
        tris = np.asarray(tris, float)
        nrm = tri_normals(tris)
        prims = []
        for m in sorted(set(mats)):
            idx = [i for i, mm in enumerate(mats) if mm == m]
            pos = tris[idx].reshape(-1, 3)
            nn = np.repeat(nrm[idx], 3, axis=0)
            prims.append({'attributes': {'POSITION': accessor(pos), 'NORMAL': accessor(nn)}, 'material': material(m), 'mode': 4})
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
        if node.mesh is not None:
            mi = mesh_for(node)
            if mi is not None:
                n['mesh'] = mi
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


# --------------------------------------------------------------------------
# Backend: Blender (bpy)
# --------------------------------------------------------------------------
def write_glb_blender(root, meta, out_path, bevel=True):
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
        col = _hex(meta['materials'].get(name, '#C9CED6'))
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

    def make_object(node, parent):
        if node.mesh is not None and len(node.mesh[0]):
            tris, tmats = node.mesh
            tris = np.asarray(tris, float)
            # weld so the bevel modifier sees shared edges
            flat = tris.reshape(-1, 3)
            keys = np.round(flat / WELD_EPS).astype(np.int64)
            uniq, inv = np.unique(keys, axis=0, return_inverse=True)
            verts = np.zeros((len(uniq), 3))
            np.add.at(verts, inv, flat)
            counts = np.bincount(inv, minlength=len(uniq))
            verts /= counts[:, None]
            faces = inv.reshape(-1, 3).tolist()
            me = bpy.data.meshes.new(node.name)
            me.from_pydata([to_bl(v) for v in verts], [], faces)
            names = sorted(set(tmats))
            for nm in names:
                me.materials.append(material(nm))
            for poly, nm in zip(me.polygons, tmats):
                poly.material_index = names.index(nm)
                poly.use_smooth = False
            me.validate()
            me.update()
            ob = bpy.data.objects.new(node.name, me)
            if bevel and node.name not in ('exhaust',) and not node.name.startswith('wheel_'):
                mod = ob.modifiers.new('Bevel', 'BEVEL')
                mod.width = BEVEL_WIDTH
                mod.segments = 1
                mod.limit_method = 'ANGLE'
                mod.angle_limit = math.radians(BEVEL_ANGLE_DEG)
                mod.harden_normals = False
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
        for c in node.children:
            make_object(c, ob)
        return ob

    make_object(root, None)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', export_yup=True, export_apply=True,
                              export_materials='EXPORT', export_extras=True, export_cameras=False,
                              export_lights=False, export_normals=True, export_texcoords=False)


def choose_backend(name):
    if name == 'python':
        return 'python'
    try:
        import bpy  # noqa: F401
        return 'blender'
    except ImportError:
        if name == 'blender':
            raise SystemExit('bpy is not importable: run inside Blender (blender --background --python ...) '
                             'or pip install bpy; or pass --backend python')
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
    ap.add_argument('--no-bevel', action='store_true', help='Blender backend: skip the bevel loop')
    args = ap.parse_args(argv)

    D = definition(args.car_id)
    root, meta = build_scene(D, args.build)
    backend = choose_backend(args.backend)
    out_dir = os.path.join(args.out, args.car_id)
    os.makedirs(out_dir, exist_ok=True)
    stem = 'body' if args.build in (None, 'stock') else 'body_%s' % args.build
    glb = os.path.join(out_dir, stem + '.glb')
    if backend == 'blender':
        write_glb_blender(root, meta, glb, bevel=not args.no_bevel)
    else:
        write_glb_python(root, meta, glb)

    counts = {n.name: len(n.mesh[0]) for n in root.walk() if n.mesh}
    meta['backend'] = backend
    meta['bevel'] = backend == 'blender' and not args.no_bevel
    meta['source_commit'] = git_head()
    meta['nodes'] = [n.name for n in root.walk()]
    meta['tris'] = counts
    meta['tris_total'] = int(sum(counts.values()))
    with open(os.path.join(out_dir, stem + '.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('%s: %d triangles in %d meshes, %d nodes, backend %s%s -> %s' % (
        args.car_id, meta['tris_total'], len(counts), len(meta['nodes']), backend,
        ' (bevel)' if meta['bevel'] else '', os.path.relpath(glb, ROOT)))
    for k, v in counts.items():
        print('  %-14s %5d' % (k, v))


if __name__ == '__main__':
    main()
