"""Write docs/design/fleet/fleet.json: every number the stage B2-B4 builds
need (dimensions, wheel hardpoints, curves, sticker slots, exhaust tips per
option, parts catalog, paints, proxy triangle counts)."""
import json
import os

import numpy as np

import car
import cars
import options
import render
from sheets import OUT, tri_count

BUDGET = {'player': 10000, 'cop': 6000, 'npc': 4000}


def _r(v, n=3):
    if isinstance(v, float):
        return round(v, n)
    if isinstance(v, (list, tuple)):
        return [_r(x, n) for x in v]
    if isinstance(v, dict):
        return {k: _r(x, n) for k, x in v.items()}
    return v


def slot_info(slot):
    out = {k: slot[k] for k in ('id', 'view', 'mirror', 'note', 'rect')}
    tris = slot['tris'][0] if slot['tris'] else []
    if tris:
        pts = np.array([p for t in tris for p in t])
        nrm = np.zeros(3)
        for a, b, c in tris:
            nrm += np.cross(b - a, c - a)
        nrm /= max(np.linalg.norm(nrm), 1e-9)
        # outward: away from the car's centre line
        cen = pts.mean(0)
        if np.dot(nrm, cen - np.array([0, 0.6, cen[2] if slot['view'] in ('left', 'right') else 0])) < 0:
            nrm = -nrm
        out['center'] = _r(cen.tolist())
        out['normal'] = _r(nrm.tolist())
        out['size'] = _r([abs(slot['rect'][2] - slot['rect'][0]), abs(slot['rect'][3] - slot['rect'][1])])
    return out


def car_entry(D):
    m = car.build(D)
    wh = D['wheel']
    H = float(m.mesh.array()[:, :, 1].max())
    entry = {
        'id': D['id'], 'role': D['role'], 'label': D['label'], 'refs': D['refs'], 'silhouette_rule': D['rule'],
        'dims': _r({'length': D['L'], 'width_body': D['W'], 'height': H, 'wheelbase': D['WB'],
                    'front_overhang': D['OHf'], 'rear_overhang': D['L'] - D['OHf'] - D['WB'],
                    'ground_clearance': min(v for _, v in D['floor'])}),
        'physics_hint': _r({'wheel_r': wh['r'], 'wheel_x': wh['track'] / 2, 'axle_z': D['WB'] / 2,
                            'tire_w_front': wh['w'], 'tire_w_rear': wh.get('w_rear', wh['w']),
                            'note': 'CarSpec.build_wheels uses symmetric axle_z; this origin already sits midway between the axles.'}),
        'curves': {k: _r(D[k]) for k in ('top', 'floor', 'hw', 'waist', 'belt')},
        'section': _r({k: D.get(k) for k in ('tumble', 'sill_in', 'rocker_h', 'gb_in', 'ledge') if D.get(k) is not None}),
        'cabin': _r(D['cabin']),
        'open_top': _r(D.get('open', [])),
        'wheel': _r(wh),
        'decals': _r(D.get('decals', [])),
        'parts': _r(D.get('parts', [])),
        'sticker_slots': [slot_info(s) for s in m.meta['sticker_slots']],
        'paint': D['paint'],
        'options': {slot: {k: {'label': o['label'], 'ops': _r(o['ops'])} for k, o in opts.items()}
                    for slot, opts in D['options'].items()},
        'builds': options.BUILDS.get(D['id'], {}),
        'budget_tris': BUDGET[D['role']],
        'proxy_tris': {'stock': tri_count(m)},
    }
    # exhaust tips for every exhaust option (B4 attaches flames here; they ride
    # with the body, so stance drops move them)
    tips = {'stock': m.meta['exhaust_tips']}
    for key in D['options'].get('exhaust', {}):
        if key != 'stock':
            tips[key] = car.build(D, {'exhaust': key}).meta['exhaust_tips']
    entry['exhaust_tips'] = _r(tips)
    for name, b in options.BUILDS.get(D['id'], {}).items():
        entry['proxy_tris'][name] = tri_count(car.build(D, b))
    # mod tree (step T1): the car's tree file in data/mod_trees and the look parts
    # (slot.option) each tree node gives for free. Looks only; ModTree never reads this.
    if D.get('tree'):
        entry['tree'] = D['tree']
        entry['tree_parts'] = D.get('tree_parts', {})
    return entry


def main():
    data = {
        'stage': 'B1 design sheet, 2026-10-05',
        'coords': 'Godot axes: X right, Y up, -Z forward. Origin on the ground, midway between the axles. '
                  'Curves use s = metres from the front tip; z = s - (front_overhang + wheelbase / 2).',
        'palette': {'sky': '#1B2A4A', 'shadow': '#0E1424', 'sodium': '#FF8A1F', 'window_amber': '#FFC066',
                    'silver': '#C9CED6', 'taillight_red': '#E5262B', 'police_blue (off-palette, kept by Roy 2026-10-05)': '#2E4FD8'},
        'traffic_paints': [{'name': n, 'hex': h, 'weight': w} for n, h, w in cars.TRAFFIC_PAINTS],
        'material_colours': render.BASE_MATS,
        'cars': [car_entry(D) for D in cars.FLEET],
    }
    path = os.path.join(OUT, 'fleet.json')
    with open(path, 'w') as f:
        json.dump(data, f, indent=1)
    print(path, os.path.getsize(path), 'bytes')


if __name__ == '__main__':
    main()
