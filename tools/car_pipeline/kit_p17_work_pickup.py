"""P17, the work pickup (Camel): what it adds to the common parts recipe.

A late-1990s mid-size four-door double cab on a 3.18 m wheelbase with a short
open bed (sheet: notes/car-sheets/p17_work_pickup-2026-10-10; Roy 439-449,
1219, 1475). Visual rebuild only: the loft, the dimensions and everything the
car drives on stay as tools/fleet_design/cars.py P17 has them.

What it has that the common recipe does not:
  - four doors: the front pair is the common one, the rear pair (`door_rr`,
    `door_rl`) is cut here from the B-pillar back to the C-pillar, each on its
    own hinge with its glass, seal and handle
  - the bed as a bolted-on box of its own (`bed`): a shut line round the cab's
    back wall, the black liner (the loft's `bed` floor and walls), black rail
    caps, and the tailgate (`tailgate`) cut out of the tail between the lamps,
    hinged at its bottom edge so it folds down level with the bed floor
  - a chrome-framed three-bar grille between wide head lamps with an amber
    block on the outer third, a chrome front bumper the plate lies on
  - stacked three-segment tail lamps at the bed corners (sheet section 6):
    red top (the brake lamp), a clear middle (reversing lamp inboard, the
    blinker's amber bulb outboard; both dark until lit), red bottom (the
    running lamp): at 100 m two red dots 34 cm apart with a dark gap
  - a high brake lamp at the top of the rear glass, a sliding centre pane
  - the sodium side stripe and its dark pinline as paint regions, so each door
    carries its own piece of it and nothing is laid over the shut lines
  - 300 mm discs in front, 260 mm drums at the rear (sheet, CarFittings),
    a chrome hub cap on each steel wheel
  - the front struts and arms in the wheel wells; nothing hangs under the belly
    (the game's Undercarriage draws the underside, and the 0.28 m floor is the
    sheet's ground clearance: tests/fleet/exterior_fit.gd)

Kept in its own file so car rebuilds can run side by side; kits.KITS imports
KIT from here. The helpers are kits.py's; the mirrors, the slider and the
bay boxes follow the street truck's (kit_p10_truck.py).
"""
import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl

# ---- panels (s along the length from the nose, metres; front/rear view x, y)
REAR_DOOR = (2.60, 3.18)             # rear door: B-pillar trailing edge to the C-pillar (side glass ends at 3.18)
BED_S = 3.37                         # the bed box starts here: the shut line behind the cab's back wall
TAILGATE_HW, TAILGATE_Y0 = 0.74, 0.80   # between the lamp columns, down to the bed floor (0.84)
TAILGATE_S = 4.755                   # its inner skin (the bed's end wall) starts at 4.758

# ---- lamps
HEAD = (0.54, 0.74, 0.72, 0.88)      # head lamp, right side (front view): the warm white part
TURN_F = (0.73, 0.75, 0.82, 0.87)    # the amber block on its outer third
GRILLE = (0.50, 0.70, 0.90)          # half width, bottom, top: chrome frame, three chrome bars, black behind
LAMP_X = (0.76, 0.87)                # tail lamp column, right side (rear view)
LAMP_TOP = (0.975, 1.06)             # red: the brake lamp
LAMP_MID = (0.735, 0.965)            # clear: reversing lamp inboard, blinker outboard
LAMP_MID_SPLIT = 0.815
LAMP_LOW = (0.64, 0.725)             # red: the running lamp, 34 cm under the brake lamp (exterior_fit: 30 cm apart, 8 cm tall)
BRAKE_C = (-0.15, 1.605, 0.15, 1.687)   # the high brake lamp over the rear glass (8 cm tall)
SLIDER = (-0.26, 1.30, 0.26, 1.56)   # the sliding centre pane of the rear window
WELL_X = 0.44                        # the wheel wells' inner wall (the tuner's 0.46, 2 cm in): the front tyres clear it at full lock
PILLAR_LIFT = 0.0065                 # the A-pillar strip lifted this much more than the common 4 mm (the tuner's)
BUMPER_F = (0.46, 0.58)              # chrome front bumper, bottom and top
BUMPER_IN = 0.30                     # flat under the plate inboard of this, 30 mm proud outboard of it

# ---- the stripe (cars.py P17 decals: sodium band, dark pinline under it), as paint regions
STRIPE = (0.40, 4.60, 0.74, 0.82)
PINLINE = (0.40, 4.60, 0.715, 0.735)

# ---- running gear and small parts
DISC_F, DRUM_R = 0.15, 0.13          # 300 mm discs in front, 260 mm drums at the rear
FLAP = (3.62, 0.98)                  # fuel flap on the left bed side, behind the cab: s, y
ANTENNA = (0.78, 1.05)               # the mast on the right front fender: x, s
PLATES = {'plate_f': ('front', 0.52, 0.26, 0.055), 'plate_r': ('rear', 0.70, 0.26, 0.055)}


# --------------------------------------------------------------------------
# Fit helpers, as kit_p3_tuner.py has them (the tuner's rebuild, which brought
# tests/fleet/exterior_fit.gd): what is laid on the car is laid on its own
# built skin, with walls down to it, so nothing hovers over a panel or cuts
# through one where merge_flat moved it off the loft.
# --------------------------------------------------------------------------
def _skin(ctx, sx, s, y, off=0.0):
    """The side skin's point at (s, y), `off` proud of it."""
    q = P.laid_on(ctx.body_tris, 'right' if sx > 0 else 'left', [(ctx.z(s), y)], off)
    return None if q is None else np.asarray(q[0], float)


def _adaptive(fn, n0=1, tol=0.0015, depth=6):
    """Parameters 0..1 for sampling fn(t) (a 3D point) along a straight edge:
    n0 even steps, each split until its midpoint is within tol of the chord.
    -> (ts, cached fn)."""
    cache = {}

    def f(t):
        if t not in cache:
            cache[t] = np.asarray(fn(t), float)
        return cache[t]
    out = [0.0]

    def rec(a, b, d):
        m = 0.5 * (a + b)
        if d > 0 and np.linalg.norm(f(m) - 0.5 * (f(a) + f(b))) > tol:
            rec(a, m, d - 1)
            rec(m, b, d - 1)
        else:
            out.append(b)
    for k in range(n0):
        rec(k / n0, (k + 1) / n0, depth)
    return out, f


def _strip(polys, face, skin, want, mat, kind=P.DETAIL):
    """A wall from a straight edge (face(t), t 0..1) back to the skin under it
    (skin(t)), split wherever the skin curves away from a straight line: a wall
    whose foot is a chord would let a bulging skin through it."""
    ts, sk = _adaptive(skin)
    for t0, t1 in zip(ts, ts[1:]):
        polys.append((P.facing([[face(t0), face(t1), sk(t1), sk(t0)]], want)[0], mat, kind))


def _rim(ctx, part, view, pts, off, mat='plastic', below=-0.0005):
    """Side walls round a lamp, bezel or plate laid `off` proud of the skin:
    from its outline down to the skin (`below` under it; the default stops
    0.5 mm short, as the panel may be triangulated either way under it), so
    it stands on the body instead of hovering over it. pts: the outline in the view's 2D."""
    q = P.laid_on(ctx.body_tris, view, [tuple(np.mean(pts, axis=0))], 0.0)
    if q is None:
        return
    centre = np.asarray(q[0], float)
    polys = []
    n = len(pts)
    for i in range(n):
        a, b = np.asarray(pts[i], float), np.asarray(pts[(i + 1) % n], float)
        top = lambda t, a=a, b=b: P.laid_on(ctx.body_tris, view, [tuple(a + (b - a) * t)], off)[0]
        bot = lambda t, a=a, b=b: P.laid_on(ctx.body_tris, view, [tuple(a + (b - a) * t)], -below)[0]
        mid = np.asarray(top(0.5), float)
        _strip(polys, top, bot, mid - centre, mat)
    for poly, m, k in polys:
        part.add(poly, m, k)


SKIN_PARTS = ('body', 'underbody', 'bumper_f', 'bumper_r', 'fender_fl', 'fender_fr', 'hood', 'trunk', 'door_l', 'door_r', 'door_rl', 'door_rr',
              'bed', 'tailgate', 'glass_backlight')


class _on_skin:
    """Within it, ctx.body_tris is the car's own skin as it is built (the cut
    panels after merge_flat) instead of the loft: merged faces sit up to 3 mm
    off the loft, and a lamp, rim, foot or handle laid on the loft goes
    through them there (the exterior fit test sees it). Every way a merged
    face can be cut into triangles is in it, so a ray from outside meets the
    highest of them: what is laid on it clears the face however Blender
    triangulates it."""

    def __init__(self, ctx):
        self.ctx = ctx

    def __enter__(self):
        ctx = self.ctx
        if not hasattr(ctx, 'skin_tris'):
            tris = []
            for name in SKIN_PARTS:
                part = ctx.parts.get(name)
                if part is None:
                    continue
                tris += [t for poly, kind in zip(part.polys, part.kind) if kind == P.SKIN for t in _fans(poly)]
            ctx.skin_tris = np.array(tris, float).reshape(-1, 3, 3)
        self.loft = ctx.body_tris
        ctx.body_tris = ctx.skin_tris
        return ctx

    def __exit__(self, *exc):
        self.ctx.body_tris = self.loft
        return False


VIEW_AB = {'front': (0, 1), 'rear': (0, 1), 'left': (2, 1), 'right': (2, 1), 'top': (0, 2)}


def _skin_decal(ctx, part, view, rect, mat, off):
    """A rect laid on the skin as the skin itself: every skin face the view
    sees under the rect, clipped to it and moved `off` out along the view.
    It follows each fold of the panel exactly, where a grid decal's flat
    cells cut through the fold between their corners. A face that is not a
    triangle may be split either way when it is drawn, so its copy stands
    off a little more, by how far the face is from flat."""
    from geom import AXES, raycast
    d = AXES[view]
    ia, ib = VIEW_AB[view]
    x0, y0, x1, y1 = rect
    planes = [(ia, x0, 1), (ia, x1, -1), (ib, y0, 1), (ib, y1, -1)]
    for name in SKIN_PARTS:
        src = ctx.parts.get(name)
        if src is None:
            continue
        for poly, kind in zip(src.polys, src.kind):
            if kind != P.SKIN:
                continue
            q = np.asarray(poly, float)
            if q[:, ia].max() < x0 or q[:, ia].min() > x1 or q[:, ib].max() < y0 or q[:, ib].min() > y1:
                continue
            n = P.poly_normal(q)
            n = n / max(np.linalg.norm(n), 1e-12)
            if abs(n @ d) < 0.05:              # some loft faces are wound the other way: the front-most test below decides
                continue
            for axis, v, sg in planes:
                q = _clip_axis(q, axis, v, sg)
                if len(q) < 3:
                    break
            if len(q) < 3:
                continue
            bend = 0.0
            if len(poly) > 3:
                pp = np.asarray(poly, float)
                bend = float(np.abs((pp - pp.mean(axis=0)) @ n).max()) * 2.0
            c = q.mean(axis=0)
            t = raycast(ctx.skin_tris, c - d * 20.0, d)
            if t is None or t < 20.0 - 0.004 - bend:  # another face stands in front of it: hidden
                continue
            part.add(P.facing([q - d * (off + bend)], -d)[0], mat, P.DETAIL)


def _clip_axis(q, axis, v, sg):
    """A polygon clipped to the side of the plane coord[axis] = v where sg * (coord - v) >= 0."""
    out = []
    m = len(q)
    for i in range(m):
        a, b = q[i], q[(i + 1) % m]
        fa, fb = sg * (a[axis] - v), sg * (b[axis] - v)
        if fa >= 0:
            out.append(a)
        if (fa >= 0) != (fb >= 0):
            out.append(a + (b - a) * (fa / (fa - fb)))
    return np.array(out, float).reshape(-1, 3)


def _fans(poly):
    """A polygon's triangles fanned from each of its corners in turn."""
    n = len(poly)
    if n == 3:
        return [poly]
    return [(poly[a], poly[(a + k) % n], poly[(a + k + 1) % n]) for a in range(n) for k in range(1, n - 1)]


def _tris(polys):
    return np.array([t for poly in polys for t in _fans(poly)], float).reshape(-1, 3, 3)


def _down(tris, x, z):
    """The highest point of `tris` straight under (x, z), or None."""
    from geom import raycast
    t = raycast(tris, np.array([x, 10.0, z]), np.array([0.0, -1.0, 0.0]))
    return None if t is None else np.array([x, 10.0 - t, z])


def _plates(ctx):
    """The plates sit 14-17 mm proud in their recess: walls round the recess down to the skin."""
    for name, (view, y, hw_p, hh_p) in PLATES.items():
        _rim(ctx, ctx.part(name), view, K.rect2(-hw_p - 0.01, y - hh_p - 0.01, hw_p + 0.01, y + hh_p + 0.01), 0.014, 'rubber')


def _wipers(ctx):
    """The common wipers lie on the loft; the merged windshield is up to 15 mm off
    it there. Rebuilt on the glass itself: a blade resting on it in pieces
    that follow its crown and an arm to it from a pivot low on the glass (the
    hood runs to the glass: a pivot on its back edge would go up with it)."""
    D, z = ctx.D, ctx.z
    sA = D['cabin']['A']
    s_w = sA + 0.075
    # the right half only, read mirrored for the left: the left half is drawn as the right's mirror image
    half = _tris([q for q in ctx.parts['glass_windshield'].polys if np.asarray(q)[:, 0].min() > -1e-6])

    def glass_at(x, zz):
        q = _down(half, abs(x), zz)
        return None if q is None else np.array([x, q[1], q[2]])
    g0, g1 = ctx.on_top(0.3, sA + 0.05), ctx.on_top(0.3, sA + 0.30)
    up = (g1 - g0) / np.linalg.norm(g1 - g0)
    n = np.cross(np.array([1.0, 0, 0]), up)
    n = n if n[1] > 0 else -n
    for nm, x0, x1 in (('r', 0.06, 0.52), ('l', -0.50, -0.04)):
        wp = ctx.part('wiper_' + nm)
        wp.polys, wp.mats, wp.kind, wp.shut = [], [], [], []
        on = lambda t: glass_at(x0 + (x1 - x0) * t, z(s_w))
        if any(on(t) is None for t in (0.0, 1.0 / 3, 2.0 / 3, 1.0)):
            continue
        ts, on = _adaptive(on, n0=3, tol=0.0005)  # the glass is crowned: a straight piece across it would dip into it
        pts = [on(t) for t in ts]
        ring = lambda q: [q + n * 0.001 - up * 0.008, q + n * 0.012 - up * 0.008, q + n * 0.012 + up * 0.008, q + n * 0.001 + up * 0.008]
        rings = [ring(q) for q in pts]
        for r0, r1 in zip(rings, rings[1:]):
            for a, b in ((0, 1), (1, 2), (2, 3)):
                q = [r0[a], r1[a], r1[b], r0[b]]
                wp.add(P.facing([q], np.mean(q, axis=0) - np.mean(r0 + r1, axis=0))[0], 'rubber')
        wp.add(P.facing([rings[0]], -(pts[1] - pts[0]))[0], 'rubber')
        wp.add(P.facing([rings[-1]], pts[-1] - pts[-2])[0], 'rubber')
        mid = on(0.5) + n * 0.017
        base = glass_at(x0 + 0.02, z(sA + 0.06))            # on the glass above its seal and its first fold
        if base is None:
            continue
        pivot = base + n * 0.010
        P.obox(wp, (pivot + mid) / 2, (np.linalg.norm(mid - pivot), 0.008, 0.012), P.frame_basis(mid - pivot, n), 'plastic')
        xb, zb = x0 + 0.02, z(sA + 0.06)                       # the pivot stands square to the glass right there
        around = [glass_at(xb + dx, zb + dz) for dx, dz in ((0.01, 0), (-0.01, 0), (0, 0.01), (0, -0.01))]
        nb = n
        if all(q is not None for q in around):
            nb = np.cross(around[2] - around[3], around[0] - around[1])
            nb = nb / np.linalg.norm(nb) * (1 if nb[1] > 0 else -1)
        K.cyl(wp, base + nb * 0.001, base + nb * 0.014, 0.009, 6, 'plastic', caps=(True, True))


def _pillars(ctx):
    """The A-pillar strips lie 4 mm over the loft, but the merged glass under
    them is up to 3 mm off it: each strip is lifted a little more along its own facets."""
    for nm in ('l', 'r'):
        pa = ctx.parts.get('pillar_a_' + nm)
        if pa is None:
            continue
        for k, q in enumerate(pa.polys):
            nv = P.poly_normal(q)
            ln = np.linalg.norm(nv)
            if ln > 1e-10:
                pa.polys[k] = q + nv / ln * PILLAR_LIFT



def _decal(ctx, d):
    """Every sheet decal of this car is a part of its own (fittings) or a paint region (the stripe)."""
    return True


def _sheet_part(ctx, p):
    with _on_skin(ctx):
        return _sheet_part_on(ctx, p)


def _sheet_part_on(ctx, p):
    """The door mirrors swing with the front doors, on a foot down to the door
    top; the running boards and the step bumper stand on the skin."""
    D, z = ctx.D, ctx.z
    if p['type'] == 'step':
        # a black board along each sill, its inner edge on the skin, two brackets under it
        s0, s1, y = p['s0'], p['s1'], p['y']
        for sx, nm in ((1, 'r'), (-1, 'l')):
            view = 'right' if sx > 0 else 'left'
            st = ctx.part('step', bevel=0)
            ins = [_skin(ctx, sx, s_, y + 0.01) for s_ in (s0, s1)]
            if any(q is None for q in ins):
                continue
            x_in = max(abs(q[0]) for q in ins) + 0.0005
            P.obox(st, (sx * (x_in + 0.05), y + 0.01, z(0.5 * (s0 + s1))), (0.10, 0.02, s1 - s0), np.eye(3), 'plastic')
            for s_ in (s0 + 0.25, s1 - 0.25):
                qs = [_skin(ctx, sx, s_, yy) for yy in (y - 0.05, y - 0.025, y)]
                if all(q is not None for q in qs):
                    xa = max(abs(q[0]) for q in qs) + 0.0005
                    P.obox(st, (sx * (xa + 0.5 * (x_in + 0.07 - xa)), y - 0.025, z(s_)), (x_in + 0.07 - xa, 0.05, 0.04), np.eye(3), 'plastic')
        return True
    if p['type'] == 'box' and p.get('tag') == 'step_bumper':
        # the chrome step bumper behind the tailgate: its front face on the tail skin
        cx, cy = p['xy']
        w, h, d = p['size']
        q = P.laid_on(ctx.body_tris, 'rear', [(cx, cy)], 0.0)
        if q is None:
            return False
        zf = float(np.asarray(q[0], float)[2])
        P.obox(ctx.part('step_bumper', bevel=0), (cx, cy, zf + d / 2), (w, h, d), np.eye(3), 'chrome')
        return True
    if p['type'] != 'mirrors':
        return False
    pm = fcar.CarModel(D)
    fcar.add_part(pm, p)
    for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
        tri = np.array(tri)
        nm = 'l' if tri[:, 0].mean() < 0 else 'r'
        ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
    # the sheet's mirror stands on its arm over the belt: a foot from the arm down onto the door top
    s = p.get('s', D['cabin']['A'] + 0.14)
    x7, y7 = fcar._section_at(D, s)[7][:2]
    y_arm = y7 + p.get('up', 0.09) - 0.025
    xa, xb = x7 + 0.004, x7 + 0.034
    z0, z1 = z(s) - 0.008, z(s) + 0.045
    for sx, nm in ((1, 'r'), (-1, 'l')):
        feet = [P.laid_on(ctx.body_tris, 'top', [(sx * x, z_)], -0.0005) for x in (xa, xb) for z_ in (z0, z1)]
        if any(f is None for f in feet):
            continue
        part = ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0)
        lo = [np.asarray(f[0], float) for f in feet]
        hi = [np.array([q[0], y_arm, q[2]]) for q in lo]
        c = np.mean(lo + hi, axis=0)
        for a, b in ((0, 1), (1, 3), (3, 2), (2, 0)):
            q = [lo[a], lo[b], hi[b], hi[a]]
            part.add(P.facing([q], np.mean(q, axis=0) - c)[0], 'plastic')
        part.add(P.facing([[hi[0], hi[1], hi[3], hi[2]]], (0, 1, 0))[0], 'plastic')
    return True


def _cuts(D, R, z, cut):
    """The rear doors out of the side, the tailgate out of the tail, then the
    bed box off the cab (fixed both sides: a shut line with its floor). The
    B-pillar strip stays on the body between the two door glasses."""
    s0, s1 = REAR_DOOR
    for sx, nm in ((1, 'r'), (-1, 'l')):
        side = (lambda sx: lambda ps: (ps.col(1) == sx) & (ps.col(0) >= 3) & (ps.col(0) <= 7) & ~ps.mat_is('pillar'))(sx)
        cut('door_r' + nm, [((0, 0, 1), z(s0)), ((0, 0, -1), -z(s1)), ((0, 1, 0), R['door_y0'])], side, True)
    gate = lambda ps: ~ps.mat_is('glass')
    planes = [((0, 0, 1), z(TAILGATE_S)), ((1, 0, 0), -TAILGATE_HW), ((-1, 0, 0), -TAILGATE_HW), ((0, 1, 0), TAILGATE_Y0)]
    cut('tailgate', planes, gate, True)
    # the bed is cut from what the tailgate left, so it carries the tailgate's shut line: a floor under
    # the bottom and inner edges; along the sides an edge return instead, as the tailgate's own, so the
    # tailgate (3 cm thick at its bed wall) folds down past it without sweeping through a floor
    side = lambda n: abs(n[0]) > 0.5
    round_gate = [(-np.asarray(n, float), -(d - P.GAP / 2), side(n), not side(n)) for n, d in planes]
    cut('bed', [((0, 0, 1), z(BED_S))], gate, False, [True], edges=round_gate)
    return ['door_rr', 'door_rl', 'tailgate', 'bed']


def _blade(ctx, name, y0, y1, proud):
    """The chrome front bumper: flat under the plate, standing proud outboard
    of it, with a short return round each corner (the muscle's recipe)."""
    D, z = ctx.D, ctx.z
    hw = pl(D['hw'], 0.0)
    blade = ctx.part(name, bevel=0)
    K.lay(ctx, blade, 'front', K.rect2(-BUMPER_IN - 0.01, y0, BUMPER_IN + 0.01, y1), 'chrome', 0.012)
    yc, h = (y0 + y1) / 2, y1 - y0
    for sx in (1, -1):
        xa, xb = sx * BUMPER_IN, sx * (hw + 0.012)
        P.obox(blade, ((xa + xb) / 2, yc, z(0.0) - proud / 2), (abs(xb - xa), h, proud), np.eye(3), 'chrome')
        run = (0.0, 0.08, 0.24)
        pts = [np.array([sx * (pl(D['hw'], s_) + 0.006), yc, z(s_)]) for s_ in run]
        for a, b in zip(pts, pts[1:]):
            P.obox(blade, (a + b) / 2, (np.linalg.norm(b - a) + 0.012, h * 0.8, 0.014), P.frame_basis(b - a, (0, 1, 0)), 'chrome')
    # the black valance under it
    K.lay(ctx, blade, 'front', K.rect2(-hw + 0.04, y0 - 0.06, hw - 0.04, y0 - 0.002), 'plastic', 0.004)
    return blade


def _plate(ctx, part, view, rect, mat, off):
    """A housing or bezel on the skin: the rect laid on it `off` proud, with walls down to it."""
    _skin_decal(ctx, part, view, rect, mat, off)
    _rim(ctx, part, view, K.rect2(*rect), off, mat)


def _fittings(ctx):
    _blade(ctx, 'bumper_blade_f', BUMPER_F[0], BUMPER_F[1], 0.03)   # on the loft, as it was (it fits)
    ctx.loft_tris = ctx.body_tris
    with _on_skin(ctx):
        _fittings_on(ctx)


def _fittings_on(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    L = D['L']
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']
    R = ctx.R

    # ---- the nose: chrome-framed three-bar grille, wide lamps with amber outer blocks
    ghw, gy0, gy1 = GRILLE
    gr = part('grille', bevel=0)
    _plate(ctx, gr, 'front', (-ghw, gy0, ghw, gy1), 'rubber', 0.003)
    f = 0.022
    for rect in ((-ghw, gy1 - f, ghw, gy1), (-ghw, gy0, ghw, gy0 + f), (-ghw, gy0 + f, -ghw + f, gy1 - f), (ghw - f, gy0 + f, ghw, gy1 - f)):
        _skin_decal(ctx, gr, 'front', rect, 'chrome', 0.005)
    for k in range(3):
        yc = gy0 + (gy1 - gy0) * (k + 1) / 4
        _skin_decal(ctx, gr, 'front', (-ghw + 0.02, yc - 0.011, ghw - 0.02, yc + 0.011), 'chrome', 0.005)
    hx0, hy0, hx1, hy1 = HEAD
    for sx, nm in ((1, 'r'), (-1, 'l')):
        head = part('head_' + nm, bevel=0)
        xa, xb = sorted((sx * (hx0 - 0.008), sx * (TURN_F[0] - 0.002)))
        _plate(ctx, head, 'front', (xa, hy0 - 0.008, xb, hy1 + 0.008), 'plastic', 0.004)   # the housing
        xa, xb = sorted((sx * hx0, sx * (TURN_F[0] - 0.006)))
        _skin_decal(ctx, head, 'front', (xa, hy0, xb, hy1), 'glow_lens', 0.006)
        q = K.lay(ctx, head, 'front', K.ellipse(0.5 * (xa + xb), 0.5 * (hy0 + hy1), 0.050, 0.042, 8), 'glow_head', 0.008)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = K.lamp_centre(q)
        # the amber block on the outer third, a lamp of its own beside it
        tf = part('turn_f' + nm, bevel=0)
        xa, xb = sorted((sx * TURN_F[0], sx * (TURN_F[2] + 0.008)))
        _plate(ctx, tf, 'front', (xa, hy0 - 0.008, xb, hy1 + 0.008), 'plastic', 0.004)
        xa, xb = sorted((sx * (TURN_F[0] + 0.004), sx * TURN_F[2]))
        _skin_decal(ctx, tf, 'front', (xa, TURN_F[1], xb, TURN_F[3]), 'glow_turn', 0.006)

    # ---- the tail: a stacked three-segment lamp at each bed corner in a black housing
    lx0, lx1 = LAMP_X
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xa, xb = sorted((sx * lx0, sx * lx1))
        _plate(ctx, part('lamp_block_' + nm, bevel=0), 'rear', (xa - 0.008, LAMP_LOW[0] - 0.008, xb + 0.008, LAMP_TOP[1] + 0.008), 'plastic', 0.003)
        _skin_decal(ctx, part('brake_' + nm, bevel=0), 'rear', (xa, LAMP_TOP[0], xb, LAMP_TOP[1]), 'glow_brake', 0.005)
        tl = part('tail_' + nm, bevel=0)
        _skin_decal(ctx, tl, 'rear', (xa, LAMP_LOW[0], xb, LAMP_LOW[1]), 'glow_tail', 0.005)
        q = P.laid_on(ctx.body_tris, 'rear', [(0.5 * (xa + xb), 0.5 * (LAMP_LOW[0] + LAMP_LOW[1]))], 0.005)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = [float(v) for v in q[0]]
        ia, ib = sorted((sx * lx0, sx * LAMP_MID_SPLIT))
        _skin_decal(ctx, part('reverse_' + nm, bevel=0), 'rear', (ia, LAMP_MID[0], ib, LAMP_MID[1]), 'glow_reverse', 0.005)
        oa, ob = sorted((sx * (LAMP_MID_SPLIT + 0.005), sx * lx1))
        _skin_decal(ctx, part('turn_r' + nm, bevel=0), 'rear', (oa, LAMP_MID[0], ob, LAMP_MID[1]), 'glow_turn', 0.005)
    # the high brake lamp over the rear glass
    cx0, cy0, cx1, cy1 = BRAKE_C
    hb = part('brake_c', bevel=0)
    _plate(ctx, hb, 'rear', (cx0 - 0.008, cy0 - 0.004, cx1 + 0.008, cy1 + 0.004), 'plastic', 0.003)
    _skin_decal(ctx, hb, 'rear', (cx0, cy0, cx1, cy1), 'glow_brake', 0.005)
    # the rear window's sliding centre pane: its own glass in a rubber seal
    sx0, sy0, sx1, sy1 = SLIDER
    se = part('seal_slider', bevel=0)
    for rect in ((sx0 - 0.02, sy1, sx1 + 0.02, sy1 + 0.02), (sx0 - 0.02, sy0 - 0.02, sx1 + 0.02, sy0),
                 (sx0 - 0.02, sy0, sx0, sy1), (sx1, sy0, sx1 + 0.02, sy1)):
        _plate(ctx, se, 'rear', rect, 'rubber', 0.006)
    _skin_decal(ctx, part('glass_slider', bevel=0), 'rear', (sx0, sy0, sx1, sy1), 'glass', 0.002)
    _plate(ctx, se, 'rear', (-0.006, sy0, 0.006, sy1), 'rubber', 0.006)
    # the lamp over the rear plate
    pl_y = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, pl_y + 0.024)], 0.0125)
    if c is not None:
        P.obox(part('plate_lamp', bevel=0), c[0], (0.12, 0.018, 0.024), np.eye(3), 'plastic', {'-y': 'glow_lens'})

    # ---- the tailgate: hinged at its bottom edge, folds down level with the bed floor; a pull at the top
    th = part('handle_tailgate', parent='hinge_tailgate', bevel=0)
    _skin_decal(ctx, th, 'rear', (-0.10, 1.045, 0.10, 1.085), 'rubber', 0.002)
    grip = (-0.08, 1.058, 0.08, 1.072)
    _plate(ctx, th, 'rear', grip, 'chrome', 0.009)
    hinges = ctx.info.setdefault('hinges', {})
    hinges['hinge_tailgate'] = {'pos': [0.0, TAILGATE_Y0, round(float(z(L)), 4)], 'axis': [1, 0, 0], 'open_sign': 1,
                                'open_deg': 90, 'panel': 'tailgate'}

    # ---- the doors swing on the outer skin at their front shut line, as real hinges do: the
    # common hinge 2 cm inboard swings the front edge forward into the fender (part_fit, #674)
    s0, s1 = REAR_DOOR
    for door, s_h in (('door_', R['door_s0']), ('door_r', s0)):
        belt = pl(D['belt'], s_h)
        for sx, nm in ((1, 'r'), (-1, 'l')):
            hinges['hinge_' + door + nm] = {
                'pos': [round(float(sx * pl(D['hw'], s_h)), 4), round(float(0.5 * (R['door_y0'] + belt)), 4), round(float(z(s_h)), 4)],
                'axis': [0, 1, 0], 'open_sign': sx, 'open_deg': 60, 'panel': door + nm}
    # the hood on gooseneck hinges: the pivot a little above and behind its rear edge, so every
    # point of the hood rises and moves forward as it opens, instead of its rear corners dipping
    # into the fenders or its rear edge swinging back into the wipers and the screen (part_fit, #675)
    hinges['hinge_hood'] = {'pos': [0.0, round(float(pl(D['top'], cab['A']) + 0.01), 4), round(float(z(cab['A'] + 0.01)), 4)],
                            'axis': [1, 0, 0], 'open_sign': 1, 'open_deg': 45, 'panel': 'hood'}

    # the door glass seal does not run on under the A-pillar strip (which lies over the glass edge)
    for nm in ('r', 'l'):
        seal = ctx.parts.get('seal_door_' + nm)
        if seal is None:
            continue
        keep = [i for i, q in enumerate(seal.polys)
                if not (q.mean(axis=0)[2] < z(cab['W']) and q.mean(axis=0)[1] > pl(D['belt'], R['door_s0']) + 0.02)]
        for attr in ('polys', 'mats', 'kind', 'shut'):
            setattr(seal, attr, [getattr(seal, attr)[i] for i in keep])
    # the rear door's front shut line runs up past the B-pillar strip's trailing edge into the
    # window: a dark strip on the body 28 mm in behind it (past the door's 15 mm return), so the
    # 4 mm gap between the pillar and the rear door glass is not a slot through the cab
    for sx in (1, -1):
        view = 'right' if sx > 0 else 'left'
        zg = z(s0)
        ys = np.linspace(pl(D['belt'], s0) - 0.02, pl(D['top'], s0) - 0.05, 8)
        edge = lambda dz: [P.laid_on(ctx.loft_tris, view, [(zg + dz, y)], -0.028) for y in ys]  # the loft: no skin face under the window
        fa, fb = edge(-0.012), edge(0.012)
        if all(q is not None for q in fa + fb):
            fa, fb = [np.asarray(q[0], float) for q in fa], [np.asarray(q[0], float) for q in fb]
            for k in range(len(ys) - 1):
                ctx.part('body').add(P.facing([[fa[k], fb[k], fb[k + 1], fa[k + 1]]], (sx, 0, 0))[0], 'under_paint', P.FLOOR)
    hs = s1 - 0.16
    hy = pl(D['belt'], hs) - 0.075
    for sx, nm in ((1, 'r'), (-1, 'l')):
        view = 'right' if sx > 0 else 'left'
        hp = part('handle_r' + nm, parent='hinge_door_r' + nm, bevel=0)
        zh = z(hs)
        _skin_decal(ctx, hp, view, (zh - 0.065, hy - 0.022, zh + 0.065, hy + 0.022), 'rubber', 0.002)
        grip = (zh - 0.0525, hy - 0.008, zh + 0.0525, hy + 0.008)
        _plate(ctx, hp, view, grip, 'chrome', 0.009)

    # ---- the bed: black plastic caps along both rails, a tie-down at each corner of the floor
    cap = part('bed_rails', bevel=0)
    s_a, s_b = BED_S + 0.05, TAILGATE_S - 0.06
    n_cap = 14
    for sx in (1, -1):
        for s_ in np.linspace(s_a, s_b, n_cap + 1)[:-1]:
            t_ = s_ + (s_b - s_a) / n_cap
            # on the bed side's 5 cm top (tumble in from hw), a little in from both of its edges
            xo0, xo1 = pl(D['hw'], s_) - D['tumble'] - 0.010, pl(D['hw'], t_) - D['tumble'] - 0.010   # the sides lean in to the rail
            corners = [(xo0 - 0.03, s_), (xo0, s_), (xo1, t_), (xo1 - 0.03, t_)]
            q = [P.laid_on(ctx.body_tris, 'top', [(sx * x, z(ss))], 0.002) for x, ss in corners]
            if any(v is None or v[0][1] < 1.10 for v in q):    # only on the rail's top, never down its side
                continue
            cap.add(P.facing([[np.asarray(v[0], float) for v in q]], (0, 1, 0))[0], 'plastic')
    for s_ in (BED_S + 0.12, TAILGATE_S - 0.10):
        q = P.laid_on(ctx.body_tris, 'top', [(0.70, z(s_))], 0.0)
        if q is not None:
            P.obox(part('bed_hooks', bevel=0), np.asarray(q[0], float) + np.array([0, 0.015, 0]), (0.04, 0.03, 0.05), np.eye(3), 'steel')

    # ---- brakes: the front caliper stays on the upright (the disc is in the wheel's mesh)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        cal = part('caliper_f' + nm, bevel=0)
        hub_x = sx * (wh['track'] / 2 - wh['w'] / 2 - 0.018)
        P.obox(cal, (hub_x, r_w + DISC_F - 0.035, z(axles[0])), (0.028, 0.07, 0.12), np.eye(3), 'steel')

    # ---- what shows of the running gear in the front wells: the strut (in the bay, behind the
    # well's inner wall) and its lower arm from the inner wall out to the upright (the tuner's)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        sf = part('susp_f' + nm, bevel=0)
        K.cyl(sf, (sx * (WELL_X - 0.035), r_w + 0.17, z(axles[0])), (sx * (WELL_X - 0.055), r_w + 0.36, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        K.cyl(sf, (sx * (WELL_X + 0.004), r_w - 0.08, z(axles[0])), (sx * 0.56, r_w - 0.07, z(axles[0])), 0.02, 4, 'steel', caps=(False, False))

    # ---- fuel flap on the left bed side, behind the cab (the tank hangs ahead of the rear axle, left)
    K.fuel_flap(ctx, -1, FLAP[0], FLAP[1])

    # ---- antenna: one mast on the right front fender, its foot square to the fender's slope
    x, s_a = ANTENNA
    on = lambda dx, dz: P.laid_on(ctx.body_tris, 'top', [(x + dx, z(s_a) + dz)], 0.0)
    pts = [on(0, 0), on(0, 0.01), on(0, -0.01), on(0.01, 0), on(-0.01, 0)]
    if all(q is not None for q in pts):
        b0, zp, zm, xp, xm = [np.asarray(q[0], float) for q in pts]
        nrm = np.cross(zp - zm, xp - xm)
        nrm = nrm / np.linalg.norm(nrm) * (1 if nrm[1] > 0 else -1)
        an = part('antenna', bevel=0)
        K.cyl(an, b0 - nrm * 0.0005, b0 + nrm * 0.010, 0.014, 6, 'plastic', caps=(False, True))
        K.cyl(an, b0 + nrm * 0.008, b0 + np.array([0.0, 0.70, 0.10]), 0.004, 3, 'rubber', caps=(False, False), r_b=0.002)

    # ---- under the hood: a dark bay floor and the radiator. No engine model yet (engine bays B).
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    P.obox(part('bay_floor', bevel=0), (0.0, 0.52, z(hood_mid)), (0.84, 0.02, cab['A'] - R['nose_s'] - 0.12), np.eye(3), 'rubber')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.715, z(R['nose_s'] + 0.10)), (0.80, 0.37, 0.05), np.eye(3), 'rubber')

    _plates(ctx)
    _wipers(ctx)
    _pillars(ctx)


def _wheel(D, tag, sx, axle, part):
    tw = D['wheel']['w']
    if axle == 0:
        K.disc_brake(part, sx, tw, r=DISC_F)
    else:
        K.drum(part, sx, tw, r=DRUM_R)
    K.hubcap(part, sx, tw, r=0.07, h=0.025)


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    cab = D['cabin']
    axles = fcar._axles(D)
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    A['bay_engine'] = {'pos': [0, 0.70, z(hood_mid + 0.10)]}       # where the V6 goes
    A['bay_radiator'] = {'pos': [0.0, 0.715, z(R['nose_s'] + 0.10)]}
    A.pop('bay_turbo', None)              # no car comes with a turbo
    A.pop('bay_intercooler', None)
    A['diff'] = {'pos': [0, 0.31, z(axles[1])]}
    A['tank'] = {'pos': [-0.30, 0.225, z(axles[1] - 0.70)]}
    A['fuel_filler'] = {'pos': [-pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    'regions': {
        'nose_s': 0.22,                    # the front fascia under the grille and lamps
        'door_s0': 1.34, 'door_s1': 2.52,  # the front door; the rear one is cut in _cuts
        'tail_s': 4.55, 'tail_y': 0.46,    # the lower rear apron the step bumper bolts to
    },
    'merge_flat': True,
    'no_trunk': True,                      # the tail is the tailgate (cuts), the deck the open bed
    'no_antenna': True,                    # the kit stands its own, on the right front fender
    'hinge_of': {'tailgate': 'hinge_tailgate',
                 'door_rr': 'hinge_door_rr', 'door_rl': 'hinge_door_rl',
                 'glass_door_rr': 'hinge_door_rr', 'glass_door_rl': 'hinge_door_rl'},
    # the side stripe runs nose to tailgate across every panel it meets
    'paint_regions': [STRIPE + ('paint_primer',), PINLINE + ('plastic',)],
    'plates': PLATES,
    'asymmetric': {
        'fuel_recess': 'one filler, on the left bed side behind the cab',
        'fuel_flap': 'one filler, on the left bed side behind the cab',
        'antenna': 'one mast, on the right front fender',
        'exhaust': 'one oval tip, out the right rear corner (Roy 444)',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'disc 300 mm, single-pot caliper', 'rear': 'drum 260 mm'},
              'brake_lamps': 2, 'third_brake': 1, 'reverse': 2, 'blinkers_front': 2, 'blinkers_rear': 2,
              'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1, 'wipers': 2, 'fuel_flap': 1,
              'condition': 0.5},
    'cuts': _cuts, 'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
    'defn': {'well_x': WELL_X},
}
