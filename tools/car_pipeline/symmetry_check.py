"""Is the car the same on both sides? (Roy, 2026-10-10: "make sure the cars
are symmetrical".)

    python tools/car_pipeline/symmetry_check.py p1_coupe            # the parts glb
    python tools/car_pipeline/symmetry_check.py p1_coupe --sheet    # the old one-piece sheet proxy

For every part of assets/cars/<id>/body.glb: mirror it in the centre plane and
measure how far the mirror image lies from the part it should match (its
left/right twin, or itself for a part that straddles the centre line). The
distance is taken from sample points on every triangle (corners, edge
midpoints, centre) to the nearest point of the other surface, so it sees a
triangle that is cut the other way round as well as a vertex that moved.

Exit code 1 if any part that should be a mirror image is off by more than
TOL (0.01 mm). The parts in parts.ASYMMETRIC are measured and listed but not
judged: they are one-sided on purpose and each says why.

Numpy only (it reads the glb itself), so it runs with or without Blender.
"""
import json
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
TOL = 1e-5
MIRROR = np.array([-1.0, 1.0, 1.0])


def read_glb(path):
    """-> {node name: (n,3,3) triangles in car space} for every mesh node."""
    with open(path, 'rb') as f:
        data = f.read()
    magic, _, _ = struct.unpack_from('<III', data, 0)
    if magic != 0x46546C67:
        raise SystemExit('%s is not a glb' % path)
    off, js, blob = 12, None, b''
    while off < len(data):
        ln, kind = struct.unpack_from('<II', data, off)
        chunk = data[off + 8:off + 8 + ln]
        if kind == 0x4E4F534A:
            js = json.loads(chunk.decode())
        elif kind == 0x004E4942:
            blob = chunk
        off += 8 + ln
    comp = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}

    def accessor(i):
        a = js['accessors'][i]
        bv = js['bufferViews'][a['bufferView']]
        dt = np.dtype(comp[a['componentType']])
        w = width[a['type']]
        start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride') or dt.itemsize * w
        if stride == dt.itemsize * w:
            arr = np.frombuffer(blob, dt, a['count'] * w, start).reshape(a['count'], w)
        else:
            arr = np.array([np.frombuffer(blob, dt, w, start + k * stride) for k in range(a['count'])])
        return arr.astype(float)

    out = {}

    def visit(ni, origin):
        n = js['nodes'][ni]
        if 'rotation' in n and 'mesh' in n:
            raise SystemExit('node %s is rotated: this check only handles moved parts' % n.get('name'))
        o = origin + np.array(n.get('translation', [0, 0, 0]), float)
        if 'mesh' in n:
            tris = []
            for prim in js['meshes'][n['mesh']]['primitives']:
                pos = accessor(prim['attributes']['POSITION']) + o
                idx = accessor(prim['indices']).astype(int).reshape(-1) if 'indices' in prim else np.arange(len(pos))
                tris.append(pos[idx].reshape(-1, 3, 3))
            out[n['name']] = np.concatenate(tris)
        for c in n.get('children', []):
            visit(c, o)

    for top in js['scenes'][js.get('scene', 0)]['nodes']:
        visit(top, np.zeros(3))
    return out


def point_tri_distance(P, T, chunk=4096):
    """Distance from each point (m,3) to the nearest point of the triangles (n,3,3)."""
    a, b, c = T[:, 0], T[:, 1], T[:, 2]
    ab, ac = b - a, c - a
    nrm = np.cross(ab, ac)
    nl = np.linalg.norm(nrm, axis=1)
    ok = nl > 1e-14
    nrm = nrm / np.where(ok, nl, 1.0)[:, None]
    d00, d01, d11 = (ab * ab).sum(1), (ab * ac).sum(1), (ac * ac).sum(1)
    den = d00 * d11 - d01 * d01
    den = np.where(np.abs(den) > 1e-20, den, 1.0)
    out = np.empty(len(P))

    def seg(p, s0, s1):
        e = s1 - s0
        t = np.clip(((p[:, None, :] - s0[None]) * e[None]).sum(-1) / np.maximum((e * e).sum(1), 1e-20)[None], 0.0, 1.0)
        q = s0[None] + e[None] * t[..., None]
        return np.linalg.norm(p[:, None, :] - q, axis=-1)

    for i in range(0, len(P), chunk):
        p = P[i:i + chunk]
        ap = p[:, None, :] - a[None]
        d20, d21 = (ap * ab[None]).sum(-1), (ap * ac[None]).sum(-1)
        v = (d11[None] * d20 - d01[None] * d21) / den[None]
        w = (d00[None] * d21 - d01[None] * d20) / den[None]
        inside = ok[None] & (v >= 0) & (w >= 0) & (v + w <= 1)
        plane = np.abs((ap * nrm[None]).sum(-1))
        edge = np.minimum(np.minimum(seg(p, a, b), seg(p, b, c)), seg(p, c, a))
        out[i:i + chunk] = np.where(inside, plane, edge).min(axis=1)
    return out


def samples(T):
    """Corners, edge midpoints and centre of every triangle."""
    a, b, c = T[:, 0], T[:, 1], T[:, 2]
    return np.concatenate([a, b, c, (a + b) / 2, (b + c) / 2, (c + a) / 2, (a + b + c) / 3])


def deviation(A, B):
    """How far the mirror image of surface A lies from surface B, both ways (metres)."""
    Am = A[:, ::-1, :] * MIRROR
    return max(float(point_tri_distance(samples(Am), B).max()), float(point_tri_distance(samples(B), Am).max()))


def twin(name, names):
    if name[-1] == 'r' and name[:-1] + 'l' in names:
        return name[:-1] + 'l'
    return None


def check_glb(car_id):
    sys.path.insert(0, HERE)
    sys.path.insert(0, os.path.join(ROOT, 'tools', 'fleet_design'))
    try:
        import parts as fparts
        one_sided = dict(fparts.ASYMMETRIC)
    except Exception:
        one_sided = {}
    meshes = {k: v for k, v in read_glb(os.path.join(ROOT, 'assets', 'cars', car_id, 'body.glb')).items()
              if not k.startswith('wheel_')}
    names = set(meshes)
    rows, worst, tris = [], 0.0, 0
    for name in sorted(names):
        if name[-1] == 'l' and name[:-1] + 'r' in names:
            continue
        other = twin(name, names)
        d = deviation(meshes[name], meshes[other] if other else meshes[name])
        judged = name not in one_sided
        n = len(meshes[name]) + (len(meshes[other]) if other else 0)
        tris += n
        rows.append((name + (' / ' + other if other else ''), n, d, judged))
        if judged:
            worst = max(worst, d)
    print('%s body.glb: %d parts, %d triangles' % (car_id, len(names), tris))
    for label, n, d, judged in rows:
        if not judged:
            print('  %-34s %5d tris  %9.3f mm   one-sided on purpose: %s' % (label, n, d * 1000, one_sided[label.split(' / ')[0]]))
    bad = [(label, d) for label, n, d, judged in rows if judged and d > TOL]
    for label, d in bad:
        print('  NOT SYMMETRIC %-24s %9.4f mm' % (label, d * 1000))
    print('  %d mirrored parts and pairs: worst mirror deviation %.5f mm (limit %.2f mm)' % (
        sum(1 for r in rows if r[3]), worst * 1000, TOL * 1000))
    return 1 if bad else 0


def check_sheet(car_id):
    sys.path.insert(0, os.path.join(ROOT, 'tools', 'fleet_design'))
    import car as fcar
    import cars as fcars
    D = [d for d in fcars.FLEET if d['id'] == car_id][0]
    Dr = fcar.resolve(D, {})
    T = fcar.loft(Dr)[0].array()
    d = deviation(T, T)
    print('%s sheet proxy (the one-piece loft the game drew before): %d triangles, mirror deviation %.3f mm' % (car_id, len(T), d * 1000))
    return 0


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    car = args[0] if args else 'p1_coupe'
    sys.exit(check_sheet(car) if '--sheet' in sys.argv else check_glb(car))
