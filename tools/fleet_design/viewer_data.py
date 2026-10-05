"""Pack every car (stock + builds) for the 360 review page: Int16 positions in
millimetres, one material index per triangle, base64."""
import base64
import json
import os
import sys

import numpy as np

import car
import cars
import options
import render
from critique import CRITIQUE

EMISSIVE = render.EMISSIVE


def pack(D, build, stickers):
    m = car.build(D, build, stickers=stickers)
    tris = m.mesh.array()
    mats = m.mesh.mats
    names = sorted(set(mats))
    idx = np.array([names.index(x) for x in mats], np.uint8)
    q = np.round(tris.reshape(-1, 3) * 1000).astype(np.int16)
    return {
        'pos': base64.b64encode(q.tobytes()).decode(),
        'mat': base64.b64encode(idx.tobytes()).decode(),
        'names': names,
        'tris': int(len(tris)),
    }


def main(out):
    verify = json.load(open(os.path.join('..', '..', 'docs', 'design', 'fleet', 'verify.json')))
    data = {'mats': render.BASE_MATS, 'emissive': sorted(EMISSIVE), 'cars': []}
    for D in cars.FLEET:
        p = D['paint']
        if 'hero' in p:
            paints = [p['hero']] + list(p['alts'])
        elif p.get('traffic'):
            paints = [(n, h) for n, h, w in cars.TRAFFIC_PAINTS]
        else:
            paints = [('Livery', p['livery']['paint'])]
        builds = [('stock', {})] + list(options.BUILDS.get(D['id'], {}).items())
        entry = {
            'id': D['id'], 'label': D['label'], 'role': D['role'], 'refs': D['refs'], 'rule': D['rule'],
            'dims': [D['L'], D['W'], D['WB']], 'critique': CRITIQUE.get(D['id'], ''),
            'verify': verify['per_car'].get(D['id'], ''),
            'paints': [list(x) for x in paints],
            'colors': cars.colors_for(D),
            'builds': [],
        }
        for name, b in builds:
            labels = [D['options'][s][o]['label'] for s, o in b.items()]
            g = pack(D, b, stickers=(name == 'stock'))
            g['name'] = name
            g['labels'] = labels
            entry['builds'].append(g)
        data['cars'].append(entry)
        print(D['id'], [g['tris'] for g in entry['builds']], flush=True)
    with open(out, 'w') as f:
        json.dump(data, f, separators=(',', ':'))
    print(out, os.path.getsize(out), 'bytes')


if __name__ == '__main__':
    main(sys.argv[1])
