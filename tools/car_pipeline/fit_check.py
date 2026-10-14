"""Do the engine bay parts fit? (engine bays B0, issue #644; Roy: "no
conflicting parts of the car at all".)

    python tools/car_pipeline/fit_check.py p7_wagon        # one car
    python tools/car_pipeline/fit_check.py                 # every car with a body.glb

The bay rules of tests/car/part_fit.gd, on the glb as build_car.py wrote it,
so a kit edit fails here before Godot imports anything:

  lid shut    straight above every corner of every bay part (`engine`,
              `bay_*`) there is a lid or body panel, at least LID_CLEAR up
  walls       straight out left and right from every corner there is a panel,
              at least WALL_CLEAR away
  bay parts   two bay parts' boxes overlap by at most PART_OVERLAP, unless the
              pair is in TOUCHING

The panel swing sweep (doors, lids, flaps, pop-ups) and the record of known
panel clashes are in the Godot test only. Same thresholds; do not loosen them
to make a car pass: fix the part. One line per failure, exit code 1 on any.

Numpy only (symmetry_check.read_glb reads the glb), with or without Blender.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from symmetry_check import ROOT, read_glb  # noqa: E402

LID_CLEAR = 0.025
WALL_CLEAR = 0.010
PART_OVERLAP = 0.005
# bay part pairs built touching (a hose on its tank, the belt on its pulleys):
# bay_kit.TOUCHING, the same list tests/car/part_fit.gd carries
sys.path.insert(0, os.path.join(ROOT, 'tools', 'fleet_design'))
from bay_kit import TOUCHING as _T  # noqa: E402
TOUCHING = {tuple(sorted(p)) for p in _T}


def is_bay_part(name):
    """CarAssembler.is_bay_part: the engine and every bay_* mesh."""
    return name == 'engine' or name.startswith('bay_')


def ray_hits(o, d, T):
    """Distance along unit d from o to each triangle of T (n,3,3), nan for a miss."""
    p, e1, e2 = T[:, 0], T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
    h = np.cross(d, e2)
    det = np.einsum('ij,ij->i', e1, h)
    ok = np.abs(det) > 1e-12
    f = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    s = o - p
    u = f * np.einsum('ij,ij->i', s, h)
    q = np.cross(s, e1)
    v = f * (q @ d)
    t = f * np.einsum('ij,ij->i', e2, q)
    hit = ok & (u >= 0) & (u <= 1) & (v >= 0) & (u + v <= 1) & (t >= 0)
    return np.where(hit, t, np.nan)


def check(car_id):
    path = os.path.join(ROOT, 'assets', 'cars', car_id, 'body.glb')
    parts = {k: v for k, v in read_glb(path).items() if not k.startswith('wheel_')}
    # the bay of its own (build_car.py --bay): its parts replace the body's placeholders by name
    bay_path = os.path.join(ROOT, 'assets', 'cars', car_id, 'bay.glb')
    if os.path.exists(bay_path):
        parts.update(read_glb(bay_path))
    bay = sorted(k for k in parts if is_bay_part(k))
    others = [k for k in parts if not is_bay_part(k)]
    T = np.concatenate([parts[k] for k in others])
    owner = np.concatenate([[k] * len(parts[k]) for k in others])
    out = []
    for b in bay:
        verts = np.unique(parts[b].reshape(-1, 3).round(4), axis=0)
        worst_up, worst_side, bare_up, bare_side = {}, {}, 0, 0
        bare_at = {}
        for v in verts:
            for d, rule in (((0, 1, 0), 'up'), ((1, 0, 0), 'side'), ((-1, 0, 0), 'side')):
                t = ray_hits(v, np.array(d, float), T)
                if np.all(np.isnan(t)):
                    if rule == 'up':
                        bare_up += 1
                    else:
                        bare_side += 1
                    bare_at.setdefault(rule, []).append(v)
                    continue
                i = int(np.nanargmin(t))
                worst, clear = (worst_up, LID_CLEAR) if rule == 'up' else (worst_side, WALL_CLEAR)
                if t[i] < clear:
                    worst[owner[i]] = min(worst.get(owner[i], np.inf), t[i])
        where = lambda rule: ', '.join('(%.2f, %.2f, %.2f)' % tuple(v) for v in bare_at.get(rule, [])[:3])
        if bare_up:
            out.append('%s: lid shut: %d corners of %s have no panel above them, e.g. %s' % (car_id, bare_up, b, where('up')))
        for p, t in worst_up.items():
            out.append('%s: lid shut: %s is %.1f mm under %s, want %.0f' % (car_id, b, t * 1000, p, LID_CLEAR * 1000))
        if bare_side:
            out.append('%s: walls: %d rays from %s leave the car sideways, e.g. %s' % (car_id, bare_side, b, where('side')))
        for p, t in worst_side.items():
            out.append('%s: walls: %s is %.1f mm from %s, want %.0f' % (car_id, b, t * 1000, p, WALL_CLEAR * 1000))
    for i, a in enumerate(bay):
        for b in bay[i + 1:]:
            if (a, b) in TOUCHING:
                continue
            A, B = parts[a].reshape(-1, 3), parts[b].reshape(-1, 3)
            over = np.minimum(A.max(0), B.max(0)) - np.maximum(A.min(0), B.min(0))
            over = max(0.0, float(over.min()))
            if over > PART_OVERLAP:
                out.append('%s: bay parts: %s and %s overlap %.1f mm, want at most %.0f' % (
                    car_id, a, b, over * 1000, PART_OVERLAP * 1000))
    return bay, out


def main(argv):
    cars = argv[1:] or sorted(d for d in os.listdir(os.path.join(ROOT, 'assets', 'cars'))
                              if os.path.exists(os.path.join(ROOT, 'assets', 'cars', d, 'body.glb')))
    fails = 0
    for car_id in cars:
        bay, out = check(car_id)
        for line in out:
            print('FAIL', line)
        fails += len(out)
        print('%s: %d bay parts (%s): %s' % (car_id, len(bay), ', '.join(bay) or '-', 'ok' if not out else '%d failures' % len(out)))
    print('PASS' if fails == 0 else 'FAILURES: %d' % fails)
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
