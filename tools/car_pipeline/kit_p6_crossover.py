"""P6, the crossover (Brannock Cairn): what it adds to the common parts recipe.

A lifted five-door hatch standing on thick black riveted cladding, a roof
rack on top, tall glass, a flat hood (sheet p6_crossover, Roy 324-327). Rear
drive with 265 rear tyres since the transmissions decision; the body is the
same 4.35 x 1.84 x 1.61 the game collides with (the sheet's 4.30 is not
applied: dimensions stay as CarSpec and NpcCarBuilder have them).

  doors      four: the front pair from the common recipe, the rear pair cut
             here (`door_rr/rl`, each with its own glass and seal), meeting the
             front door on one shut line; every door hinges just outboard of
             its skin so its front edge swings clear of what is ahead of it
  tailgate   one hatch cut out of the deck and the tail face, hinged at the
             roof's rear edge (its top shut line): glass, plate, plate lamp,
             handle, rear wiper, spoiler and high brake lamp go up with it
  cladding   bolted-on black arch pieces 4.5 cm proud of the flat flank
             (0.92 over the arches: the 1.84 overall width), a rolled lip into
             the well, a top wall back to the skin, rivets on the arch edge,
             and a sill panel joining them under the doors
  lamps      stacked twins in front (driving lamp over an amber blinker),
             split lamps behind (upper on the body corner with the brake core
             and a wrap up the pillar, amber blinker inboard; lower in the
             bumper with the reversing lamp inboard), a high brake lamp in the
             spoiler's trailing edge, a lamp over the rear plate
  rack       silver rails, two black crossbars poking past the roof edge
  bay        a flat four under the hood (low and wide), its intake, the
             radiator, the battery; skid plate under the nose (lifted: the
             low camera sees it); discs on all four behind five dark spokes

Kept in its own file so the car rebuilds can run side by side; kits.KITS
imports KIT from here. The helpers are kits.py's; the spoked wheel face is
the hot hatch's.
"""
import math

import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl
from kit_p2_hothatch import alloy_face

DOOR_S0 = 1.40          # front door: behind the front cladding's top (a black sail with the mirror ahead of it)
RDOOR = (2.36, 3.07)    # rear door: from the front door's rear edge to the thin pillar ahead of the quarter glass
RAIL_LIFT = 0.0055     # the roof rails sit this far over the sheet's (whose feet sink into the roof)
WIPER_PIVOT = 0.025     # the wiper arms pivot this far up the glass from its base (behind the hood)
A_TUCK = 0.02           # the front door glass stops this far in from the windscreen's edge (the pillar strip covers 0.04)
HINGE_OUT = 0.01        # every door hinges this far outboard of its skin, so its front edge swings clear
HATCH_HW = 0.585        # the tailgate reaches this far from the centre line; the upper lamps stand outboard of it
HATCH_Y0 = 0.60         # and down to the top of the bumper
SPOILER_IN = 0.006      # the roof spoiler starts this far behind the tailgate's top shut line, so all of it rides on the tailgate
CLAD_X = 0.92           # the cladding's outer face (4.5 cm proud of the 0.875 flank; the car's 1.84 width)
CLAD_BAND = 0.11        # it reaches this far out from the arch edge
CLAD_RIVETS = 9
SILL = (0.27, 0.50, 0.905)   # the sill panel: bottom, top, outer face (a little less proud than the arches)
HEAD = (0.505, 0.81, 0.695, 0.91)    # the upper (driving) lamp of a stack, right side, front view
TURN_F = (0.505, 0.69, 0.695, 0.79)  # the amber lamp under it
UPPER = (0.61, 0.85, 0.78, 0.97)     # the upper rear lamp on the body corner, right side, rear view
UPPER_TURN = 0.67                    # its inboard end up to here is the amber blinker
WRAP = (0.72, 0.975, 0.77, 1.04)     # its wrap up the D-pillar
LOWER = (0.58, 0.46, 0.80, 0.565)    # the lower rear lamp in the bumper (on its face, clear of the valance under it)
LOWER_REV = 0.655                    # its inboard end up to here is the reversing lamp, the rest is the brake lamp
BRAKE_C = (0.15, 0.082, 0.03)         # the high brake lamp: a pod under the spoiler's trailing edge (half width, height, depth)
CLAD_IN = 0.030                      # the cladding's lip stands this far over the tyre (the body's arch is 4.5 cm: the sheet's gap)
WELL_X = 0.46                        # the wheel wells' inner wall from the centre line: a front tyre at full lock clears it
DISC_F, DISC_R = 0.158, 0.15         # 316 / 300 mm vented discs (the sheet)
FLAP = (3.36, 0.94)                  # fuel flap on the left rear quarter, over the rear cladding: s, y
MIRROR_S = 1.50                      # the door mirrors, on the doors (behind the sail)
PLATES = {'plate_f': ('front', 0.56, 0.26, 0.055), 'plate_r': ('rear', 0.69, 0.26, 0.055)}


def _arch(D):
    wh = D['wheel']
    return wh['r'] + wh.get('arch_gap', 0.03), wh['r'] + wh.get('arch_lift', 0.0)


# --------------------------------------------------------------------------
# Laying parts on the car's own skin (the same helpers as kit_p3_tuner.py:
# tests/fleet/exterior_fit.gd holds both cars to them)
# --------------------------------------------------------------------------
def _adaptive(fn, n0=1, tol=0.0015, depth=6):
    """Parameters 0..1 for sampling fn(t) along a straight edge: n0 even steps,
    each split until its midpoint is within tol of the chord. -> (ts, cached fn)."""
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
    (skin(t)), split wherever the skin curves away from a straight line."""
    ts, sk = _adaptive(skin)
    for t0, t1 in zip(ts, ts[1:]):
        polys.append((P.facing([[face(t0), face(t1), sk(t1), sk(t0)]], want)[0], mat, kind))


def _rim(ctx, part, view, pts, off, mat='plastic', below=-0.0005):
    """Side walls round a lamp, bezel or plate laid `off` proud of the skin,
    from its outline down to 0.5 mm short of the skin: it stands on the body
    instead of hovering over it. pts: the outline in the view's 2D."""
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


SKIN_PARTS = ('body', 'underbody', 'bumper_f', 'bumper_r', 'fender_fl', 'fender_fr', 'hood', 'hatch',
              'door_l', 'door_r', 'door_rl', 'door_rr')


def _fans(poly):
    """A polygon's triangles fanned from each of its corners in turn."""
    n = len(poly)
    if n == 3:
        return [poly]
    return [(poly[a], poly[(a + k) % n], poly[(a + k + 1) % n]) for a in range(n) for k in range(1, n - 1)]


def _tris(polys):
    return np.array([t for poly in polys for t in _fans(poly)], float).reshape(-1, 3, 3)


class _on_skin:
    """Within it, ctx.body_tris is the car's own skin as built (the cut panels
    after merge_flat) instead of the loft: merged faces sit up to 3 mm off the
    loft, and what is laid on the loft goes through them there."""

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


def _skin_decal(ctx, part, view, rect, mat, off):
    """A rect laid on the skin as the skin itself: every skin face the view
    sees under the rect, clipped to it and moved `off` out along the view, so
    it follows each fold of the panel exactly."""
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
            if abs(n @ d) < 0.05:
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


def _skin_box(ctx, part, view, rect, mat, off):
    """A flat-faced lamp, bezel or strip: the rect laid on the skin `off`
    proud and walled down to it."""
    _skin_decal(ctx, part, view, rect, mat, off)
    _rim(ctx, part, view, K.rect2(*rect), off, 'plastic' if mat.startswith('glow') else mat)


# --------------------------------------------------------------------------
# Panels
# --------------------------------------------------------------------------
def _cuts(D, R, z, cut):
    """The rear doors (one shut line behind the front door) and the tailgate
    (the deck behind the glass and the tail face down to the bumper)."""
    for sx, nm in ((1, 'r'), (-1, 'l')):
        side = (lambda sx: lambda ps: (ps.col(1) == sx) & (ps.col(0) >= 3) & (ps.col(0) <= 7) & ~ps.mat_is('pillar'))(sx)
        cut('door_r' + nm, [((0, 0, 1), z(RDOOR[0])), ((0, 0, -1), -z(RDOOR[1])), ((0, 1, 0), R['door_y0'])], side, True)
    rear = lambda ps: ((ps.col(0) >= 8) & ~ps.mat_is('glass')) | (ps.col(0) == -2)
    cut('hatch', [((0, 0, 1), z(D['cabin']['C'])), ((1, 0, 0), -HATCH_HW), ((-1, 0, 0), -HATCH_HW), ((0, 1, 0), HATCH_Y0)], rear, True)
    return ['door_rr', 'door_rl', 'hatch']


def _decal(ctx, d):
    with _on_skin(ctx):
        return _decal_on(ctx, d)


def _decal_on(ctx, d):
    D, part, body = ctx.D, ctx.part, ctx.body_tris
    mat, view, tag = d['mat'], d['view'], d.get('tag')
    if mat in ('head', 'turn', 'tail'):
        return True                               # every lamp is a part of its own: fittings
    if mat == 'trim' and view == 'rear':
        return True                               # the rear plate brings its own recess, on the tailgate
    if mat == 'chrome':
        # the silver skid strips under the front mouth and across the rear bumper
        name = 'skid_strip_f' if view == 'front' else 'skid_strip_r'
        _skin_box(ctx, part(name, bevel=0), view, d['rect'], 'chrome', 0.003)
        return True
    if mat == 'grille':
        # the slot grille between the lamps and the bumper mouth: dark, walled down to the skin, bars across
        x0, y0, x1, y1 = d['rect']
        g = part('grille', bevel=0)
        for r in _around_plate(view, (x0, y0, x1, y1)):
            _skin_box(ctx, g, view, r, 'rubber', 0.003)
        for k in range(3):
            yc = y0 + (y1 - y0) * (k + 1) / 4
            for r in _around_plate(view, (x0 + 0.01, yc - 0.008, x1 - 0.01, yc + 0.008)):
                _skin_decal(ctx, g, view, r, 'plastic', 0.005)
        return True
    return False


def _around_plate(view, rect):
    """`rect` with the stretch behind the front plate (and its rim) left out."""
    x0, y0, x1, y1 = rect
    _, py, phw, phh = PLATES['plate_f']
    if view != 'front' or y1 <= py - phh - 0.012 or y0 >= py + phh + 0.012:
        return [rect]
    xo = phw + 0.012
    return [r for r in ((x0, y0, min(x1, -xo), y1), (max(x0, xo), y0, x1, y1)) if r[2] - r[0] > 0.01]


def _sheet_part(ctx, p):
    with _on_skin(ctx):
        return _sheet_part_on(ctx, p)


def _sheet_part_on(ctx, p):
    D, z = ctx.D, ctx.z
    t = p['type']
    if t == 'mirrors':
        # on the doors, behind the sail, so they open with them
        p = dict(p, s=MIRROR_S)
        pm = fcar.CarModel(D)
        fcar.add_part(pm, p)
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            tri = np.array(tri)
            nm = 'l' if tri[:, 0].mean() < 0 else 'r'
            ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
        # the sheet's mirror stands on a stub over the belt: a foot from the stub down onto the door top
        x7, y7 = fcar._section_at(D, MIRROR_S)[7][:2]
        y_stub = y7 + p.get('up', 0.09) - 0.025
        xa, xb = x7 + 0.004, x7 + 0.034
        z0, z1 = z(MIRROR_S) - 0.008, z(MIRROR_S) + 0.045
        for sx, nm in ((1, 'r'), (-1, 'l')):
            feet = [P.laid_on(ctx.body_tris, 'top', [(sx * x, z_)], -0.0005) for x in (xa, xb) for z_ in (z0, z1)]
            if any(f is None for f in feet):
                continue
            part = ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0)
            lo = [np.asarray(f[0], float) for f in feet]
            hi = [np.array([q[0], y_stub, q[2]]) for q in lo]
            c = np.mean(lo + hi, axis=0)
            for a, b in ((0, 1), (1, 3), (3, 2), (2, 0)):
                q = [lo[a], lo[b], hi[b], hi[a]]
                part.add(P.facing([q], np.mean(q, axis=0) - c)[0], 'plastic')
            part.add(P.facing([[hi[0], hi[1], hi[3], hi[2]]], (0, 1, 0))[0], 'plastic')
        return True
    if t == 'flares':
        for ai, s_ax in enumerate(fcar._axles(D)):
            _cladding(ctx, 'clad_%sr' % ('f' if ai == 0 else 'r'), s_ax)
        _sill(ctx)
        for nm in ('clad_fl', 'clad_rl', 'clad_sill_l'):
            ctx.part(nm, bevel=0)                 # named, so the right-hand piece is written as a pair
        return True
    if t == 'roof_rails':
        # silver rails (the car's bright line under sodium), black crossbars
        rails = ctx.part('roof_rails', bevel=0)
        pm = fcar.CarModel(D)
        fcar.add_part(pm, dict(p, bars=[]))
        for tri in pm.mesh.tris:
            rails.add(np.array(tri) + (0.0, RAIL_LIFT, 0.0), 'chrome')   # the sheet's feet sink into the crowned roof
        s0, s1, x = p['s0'], p['s1'], p['x']
        over = p.get('bar_over', 0.05)
        bh = p.get('bar_h', 0.028)
        bars = ctx.part('rack_bars', bevel=0)
        # the rails run level (long boxes: no vertices mid-length), so their top is their highest point
        rail = np.array([v for q in rails.polys for v in np.asarray(q, float)])
        y_top = float(rail[np.abs(np.abs(rail[:, 0]) - x) < 0.03, 1].max())
        for s in p.get('bars', []):
            # each bar sits on the two rails, its underside 1 mm over their top; built in lengths
            # with a joint over each rail (it is a part the fit test reads by its vertices)
            yb = y_top + 0.001 + bh / 2
            cuts = [-x - over, -x - 0.015, -x + 0.015, -x / 2, 0.0, x / 2, x - 0.015, x + 0.015, x + over]   # joints over the 40 mm rail
            for xa, xb in zip(cuts, cuts[1:]):
                P.obox(bars, ((xa + xb) / 2, yb, z(s)), (xb - xa, bh, 0.045), np.eye(3), 'plastic')
            for sx in (1, -1):                    # the end caps
                P.obox(bars, (sx * (x + over + 0.006), yb, z(s)), (0.012, bh + 0.006, 0.05), np.eye(3), 'rubber')
        return True
    if t == 'roof_spoiler':
        # the spoiler sits on the tailgate's top edge and goes up with it
        pm = fcar.CarModel(D)
        fcar.add_part(pm, dict(p, brake_light=False, s0=D['cabin']['C'] + SPOILER_IN))
        sp = ctx.part('spoiler', parent='hinge_hatch', bevel=0.006)
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            sp.add(np.array(tri), P.MATMAP.get(mm, mm), P.SKIN)
        # the high brake lamp: a pod hung on the spoiler's trailing face, its lit face to the rear
        # (8 cm tall: it reads as a lamp at 100 m, the car-shape rule)
        hw_, hh, dd = BRAKE_C
        vs = np.array([v for q in sp.polys for v in np.asarray(q, float)])   # its faces span the width: no centre vertices
        z_tr = float(vs[:, 2].max())
        edge = vs[vs[:, 2] > z_tr - 0.002]
        y_top = float(edge[:, 1].max())
        hb = ctx.part('brake_c', parent='hinge_hatch', bevel=0)
        P.obox(hb, (0.0, y_top - hh / 2, z_tr - 0.0005 + dd / 2), (2 * hw_, hh, dd), np.eye(3), 'plastic', {'+z': 'glow_brake'})
        return True
    return False


# --------------------------------------------------------------------------
# Cladding
# --------------------------------------------------------------------------
def _skin(ctx, s, y, off=0.0):
    """The right flank at (s, y), `off` proud of it."""
    q = P.laid_on(ctx.body_tris, 'right', [(ctx.z(s), y)], off)
    return None if q is None else np.asarray(q[0], float)


def _skin_at(ctx, s, y, s_ax, yc, Ra, off=0.0005):
    """The right flank at (s, y), read just outside the body's wheel arch when
    the point is on its edge (inside is the well)."""
    cen = np.array([s_ax, yc])
    for ds in (0.0, 0.003, -0.003, 0.006, -0.006):   # a ray down a shut gap meets no skin: read beside it
        p = np.array([s + ds, y], float)
        for m in (0.0, 0.006, 0.012, 0.024, 0.036):
            d = p - cen
            q = p
            if d[1] < 0:
                if abs(d[0]) < Ra + m:
                    q = np.array([s_ax + math.copysign(Ra + m, d[0]), p[1]])
            elif np.linalg.norm(d) < Ra + m:
                q = cen + d / np.linalg.norm(d) * (Ra + m)
            sk = _skin(ctx, q[0], q[1], off)
            if sk is not None and sk[0] > pl(ctx.D['hw'], q[0]) - 0.06:
                return sk
    raise ValueError('no skin at s %.3f y %.3f' % (s, y))


def _cladding(ctx, name, s_ax):
    """One arch piece (right side; the left is its mirror image): a band round
    the arch from CLAD_IN over the tyre out to the body's arch edge plus
    CLAD_BAND, its outer face at CLAD_X; a rolled lip from the face into the
    wheel well, a top wall and two feet back to the flank (each following the
    skin under it), rivets along the arch edge. It lies on the skin (no cut),
    so the arch liner and the body's own arch edge stay as they are."""
    D, z = ctx.D, ctx.z
    Ra, yc = _arch(D)
    part = ctx.part(name, bevel=0)
    r_in, r_out = D['wheel']['r'] + CLAD_IN, Ra + CLAD_BAND
    y_foot = pl(D['floor'], s_ax) + 0.04
    a0 = math.asin(max(-0.95, (y_foot - yc) / r_in))
    a1 = math.asin(max(-0.95, (y_foot - yc) / r_out))
    n = 14
    angs = [a0 + (math.pi - 2 * a0) * k / n for k in range(n + 1)]
    x_lip = pl(D['hw'], s_ax) - D.get('sill_in', 0.03) - P.LIP
    side = np.array([1.0, 0.0, 0.0])
    polys = []
    rows = []
    for a in angs:
        si, yi = s_ax - r_in * math.cos(a), yc + r_in * math.sin(a)
        b = a1 + (math.pi - 2 * a1) * (a - a0) / (math.pi - 2 * a0)     # the outer edge, from foot to foot
        so, yo = s_ax - r_out * math.cos(b), yc + r_out * math.sin(b)
        rows.append((np.array([x_lip, yi, z(si)]), np.array([CLAD_X, yi, z(si)]), np.array([CLAD_X, yo, z(so)]), (so, yo), a, (si, yi)))
    for A, B in zip(rows, rows[1:]):
        a_mid = 0.5 * (A[4] + B[4])
        radial = np.array([0.0, math.sin(a_mid), -math.cos(a_mid)])
        polys.append((P.facing([[A[0], B[0], B[1], A[1]]], -radial)[0], 'plastic', P.DETAIL))   # the lip into the well
        polys.append((P.facing([[A[1], B[1], B[2], A[2]]], side)[0], 'plastic', P.SKIN))       # the outer face
        # the top wall, back to the skin along the outer edge
        (sa, ya), (sb, yb) = A[3], B[3]
        _strip(polys, lambda t, A=A, B=B: A[2] + (B[2] - A[2]) * t,
               lambda t, sa=sa, ya=ya, sb=sb, yb=yb: _skin_at(ctx, sa + (sb - sa) * t, ya + (yb - ya) * t, s_ax, yc, Ra),
               radial + side * 0.3, 'plastic', P.SKIN)
    # the two feet: from the face's bottom edge back to the skin, level
    for R_, fwd in ((rows[0], -1.0), (rows[-1], 1.0)):
        (so, yo), (s_i, yi) = R_[3], R_[5]
        _strip(polys, lambda t, R_=R_: R_[1] + (R_[2] - R_[1]) * t,
               lambda t, s_i=s_i, yi=yi, so=so, yo=yo: _skin_at(ctx, s_i + (so - s_i) * t, yi + (yo - yi) * t, s_ax, yc, Ra),
               np.array([0.0, -1.0, 0.0]), 'plastic')
    for q, m, k in polys:
        part.add(q, m, k)
    # rivet heads along the arch edge
    r_mid = 0.5 * (Ra + r_out) - 0.01
    for k in range(CLAD_RIVETS):
        a = a1 + 0.18 + (math.pi - 2 * a1 - 0.36) * k / (CLAD_RIVETS - 1)
        c = np.array([CLAD_X, yc + r_mid * math.sin(a), z(s_ax - r_mid * math.cos(a))])
        K.cyl(part, c, c + side * 0.004, 0.009, 4, 'steel', caps=(False, False), r_b=0.0)


def _sill(ctx):
    """The sill panel joining the two arch pieces under the doors (right side):
    it stops just short of them, its top and bottom walls follow the skin."""
    D, z = ctx.D, ctx.z
    Ra, _ = _arch(D)
    axles = fcar._axles(D)
    y0, y1, x = SILL
    s0, s1 = axles[0] + Ra + CLAD_BAND + 0.0015, axles[1] - Ra - CLAD_BAND - 0.0015
    part = ctx.part('clad_sill_r', bevel=0)
    face = lambda s, y: np.array([x, y, z(s)])
    sk = lambda s, y: _skin(ctx, s, y, 0.0005)
    polys = []
    polys.append((P.facing([[face(s0, y0), face(s1, y0), face(s1, y1), face(s0, y1)]], (1, 0, 0))[0], 'plastic', P.SKIN))
    _strip(polys, lambda t: face(s0 + (s1 - s0) * t, y1), lambda t: sk(s0 + (s1 - s0) * t, y1), (0.3, 1, 0), 'plastic', P.SKIN)
    _strip(polys, lambda t: face(s0 + (s1 - s0) * t, y0), lambda t: sk(s0 + (s1 - s0) * t, y0), (0.3, -1, 0), 'plastic')
    for s, out in ((s0, -1), (s1, 1)):
        _strip(polys, lambda t, s=s: face(s, y0 + (y1 - y0) * t), lambda t, s=s: sk(s, y0 + (y1 - y0) * t), (0, 0, out), 'plastic')
    for q, m, k in polys:
        part.add(q, m, k)
    for k in range(6):
        s = s0 + 0.10 + (s1 - s0 - 0.20) * k / 5
        c = face(s, 0.5 * (y0 + y1))
        K.cyl(part, c, c + np.array([0.004, 0, 0]), 0.009, 4, 'steel', caps=(False, False), r_b=0.0)


# --------------------------------------------------------------------------
# Fittings
# --------------------------------------------------------------------------
def _door_hinge(D, R, s, nm, panel, belt_s):
    sx = 1 if nm == 'r' else -1
    x = pl(D['hw'], s) + HINGE_OUT
    return {'pos': [round(sx * x, 4), round(0.5 * (R['door_y0'] + pl(D['belt'], belt_s)), 4), round(fcar._s2z(D, s), 4)],
            'axis': [0, 1, 0], 'open_sign': sx, 'open_deg': 60, 'panel': panel}


def _trim_door_glass(ctx):
    """The front door glass ends A_TUCK in from the windscreen's side edge,
    under the A-pillar strip: the loft's side glass and windscreen do not
    share that edge exactly, so glass and seal running right up to it cross
    the windscreen and the pillar when shut. The edge is the windscreen's own
    outermost vertex at each station; each glass polygon is cut on the
    stretch its centre lies beside."""
    ws = ctx.parts.get('glass_windshield')
    if ws is None:
        return
    corner = {}
    for q in ws.polys:
        for v in np.asarray(q, float):
            k = round(float(v[2]), 3)
            if k not in corner or v[0] > corner[k][0]:
                corner[k] = v
    line = [corner[k] for k in sorted(corner)]
    across = np.array([0.30, -1.0, 0.0])        # down the side glass from the pillar, right side
    cuts = []
    for a, b in zip(line, line[1:]):
        d = b - a
        if np.linalg.norm(d) < 0.02:
            continue
        d /= np.linalg.norm(d)
        n = across - (across @ d) * d
        n /= np.linalg.norm(n)
        # the top stretch only just clear of the windscreen (a full tuck loses its corner's seal):
        # glass sharing the windscreen's corner vertex reads as crossing it
        tuck = A_TUCK if b[2] < line[-1][2] - 0.05 else 0.003
        cuts.append((a[2], b[2], n, float(n @ a) + tuck))
    for name in ('glass_door_r', 'seal_door_r'):
        pt = ctx.parts.get(name)
        if pt is None:
            continue
        keep = list(zip(pt.polys, pt.mats, pt.kind, pt.shut))
        pt.polys, pt.mats, pt.kind, pt.shut = [], [], [], []
        for q, m, k, sh in keep:
            q = np.asarray(q, float)
            zc = float(q[:, 2].mean())
            cut = next((c for c in cuts if c[0] - 1e-6 <= zc <= c[1] + 1e-6), None)
            ins = q if cut is None else P.clip_poly(q, cut[2], cut[3])[0]
            if ins is None:
                continue
            if ins is q or (len(ins) == len(q) and np.allclose(ins, q)):
                pt.add(q, m, k, sh)
            else:
                pt.add(ins, m, k)


def _down(tris, x, z):
    """The highest point of `tris` straight under (x, z), or None."""
    from geom import raycast
    t = raycast(tris, np.array([x, 10.0, z]), np.array([0.0, -1.0, 0.0]))
    return None if t is None else np.array([x, 10.0 - t, z])


def _wipers(ctx):
    """The wipers rest on the glass itself (the merged windscreen is up to
    15 mm off the loft), a blade in pieces that follow its crown, an arm from
    a pivot low on the glass, behind the hood's shut line (the hood lifts
    forward from a hinge at its rear edge, and would come up through a pivot
    on the scuttle in front of it)."""
    D, z = ctx.D, ctx.z
    sA = D['cabin']['A']
    s_w = sA + 0.075
    half = _tris([q for q in ctx.parts['glass_windshield'].polys if np.asarray(q)[:, 0].min() > -1e-6])

    def glass_at(x, zz):
        q = _down(half, abs(x), zz)
        return None if q is None else np.array([x, q[1], q[2]])
    g0, g1 = ctx.on_top(0.3, sA + 0.05), ctx.on_top(0.3, sA + 0.30)
    up = (g1 - g0) / np.linalg.norm(g1 - g0)
    n = np.cross(np.array([1.0, 0, 0]), up)
    n = n if n[1] > 0 else -n
    for nm, x0, x1 in (('r', 0.06, 0.52), ('l', -0.50, -0.04)):
        wp = ctx.part('wiper_' + nm, bevel=0)
        wp.polys, wp.mats, wp.kind, wp.shut = [], [], [], []
        on = lambda t, x0=x0, x1=x1: glass_at(x0 + (x1 - x0) * t, z(s_w))
        if any(on(t) is None for t in (0.0, 1.0 / 3, 2.0 / 3, 1.0)):
            continue
        ts, on = _adaptive(on, n0=3, tol=0.0005)
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
        base = glass_at(x0 + 0.02, z(sA + WIPER_PIVOT + 0.065))
        if base is None:
            continue
        pivot = base + n * 0.010
        P.obox(wp, (pivot + mid) / 2, (np.linalg.norm(mid - pivot), 0.008, 0.012), P.frame_basis(mid - pivot, n), 'plastic')
        K.cyl(wp, base + n * 0.001, base + n * 0.014, 0.009, 6, 'plastic', caps=(True, True))


def _wiper_rear(ctx):
    """The rear wiper on the tailgate glass: a blade in pieces laid on the
    glass and its pivot boss at the left end."""
    from geom import AXES, raycast
    half = _tris([q for q in ctx.parts['glass_backlight'].polys if np.asarray(q)[:, 0].min() > -1e-6])
    d = AXES['rear']

    def on(x, y, off):
        t = raycast(half, np.array([abs(x), y, 0.0]) - d * 20.0, d)
        if t is None:
            return None
        q = np.array([abs(x), y, 0.0]) - d * 20.0 + d * t
        return np.array([x, q[1], q[2]]) - d * off
    wp = ctx.part('wiper_rear', parent='hinge_hatch', bevel=0)

    def normal(x, y):
        # the glass's outward normal at (x, y), from its neighbours
        g = [on(x + dx, y + dy, 0.0) for dx, dy in ((-0.02, 0), (0.02, 0), (0, -0.02), (0, 0.02))]
        if any(q is None for q in g):
            return -d
        n = np.cross(g[1] - g[0], g[3] - g[2])
        n /= np.linalg.norm(n)
        return n if n @ -d > 0 else -n
    xs = np.linspace(-0.02, 0.42, 9)
    ys = [1.21 + 0.02 * (x + 0.02) / 0.44 for x in xs]
    pts = [on(x, y, 0.0) for x, y in zip(xs, ys)]
    if any(q is None for q in pts):
        return
    for (a, b), x, y in zip(zip(pts, pts[1:]), xs, ys):
        n = normal(x + 0.0275, y)
        # 10 mm thick along the glass's normal, its underside 1.5 mm off the chord
        P.obox(wp, (a + b) / 2 + n * 0.0065, (np.linalg.norm(b - a) + 0.002, 0.010, 0.014), P.frame_basis(b - a, n), 'rubber')
    boss = on(-0.02, 1.185, 0.0)
    if boss is not None:
        n = normal(-0.02, 1.185)
        P.obox(wp, boss + n * 0.0105, (0.04, 0.018, 0.03), P.frame_basis((1, 0, 0), n), 'plastic')


def _plates(ctx):
    """The plates sit 14-17 mm proud in their recess: walls round the recess down to the skin."""
    for name, (view, y, hw_p, hh_p) in PLATES.items():
        if name in ctx.parts:
            _rim(ctx, ctx.parts[name], view, K.rect2(-hw_p - 0.01, y - hh_p - 0.01, hw_p + 0.01, y + hh_p + 0.01), 0.014, 'rubber')


def _fittings(ctx):
    with _on_skin(ctx):
        _fittings_on(ctx)
        _plates(ctx)


def _fittings_on(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    L = D['L']
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']
    R = ctx.R
    hinges = ctx.info.setdefault('hinges', {})

    # ---- doors: the front pair's hinge moved just outboard of the skin, the rear pair's own
    for nm in ('r', 'l'):
        hinges['hinge_door_' + nm] = _door_hinge(D, R, R['door_s0'], nm, 'door_' + nm, R['door_s0'])
        hinges['hinge_door_r' + nm] = _door_hinge(D, R, RDOOR[0], nm, 'door_r' + nm, RDOOR[0])
    # the hood: hinged just behind and above its rear edge, so the whole panel
    # lifts forward and up (a hinge ahead of the edge dips the rear corners into the fenders)
    cab_a = D['cabin']['A']
    hinges['hinge_hood'] = {'pos': [0.0, round(pl(D['top'], cab_a) + 0.002, 4), round(z(cab_a) + 0.005, 4)],
                            'axis': [1, 0, 0], 'open_sign': 1, 'open_deg': 45, 'panel': 'hood'}
    _trim_door_glass(ctx)
    _wipers(ctx)
    # the rear door's handle, at the front door's height
    hs = RDOOR[1] - 0.16
    hy = pl(D['belt'], R['door_s1'] - 0.16) - 0.075
    part('handle_door_rl', parent='hinge_door_rl', bevel=0)     # named: the right one is written as a pair
    hp = part('handle_door_rr', parent='hinge_door_rr', bevel=0)
    zh = z(hs)
    _skin_decal(ctx, hp, 'right', (zh - 0.065, hy - 0.022, zh + 0.065, hy + 0.022), 'rubber', 0.002)
    grip = (zh - 0.0525, hy - 0.008, zh + 0.0525, hy + 0.008)   # the bar: its face follows the door's twist
    _skin_decal(ctx, hp, 'right', grip, 'chrome', 0.009)
    _rim(ctx, hp, 'right', K.rect2(*grip), 0.009, 'chrome')
    # behind the shut line between the two doors: a dark pillar face, so the gap is never a hole
    by0, by1 = R['door_y0'], pl(D['belt'], RDOOR[0])
    xb = pl(D['hw'], RDOOR[0]) - 0.11             # inboard of both doors' turned-in edges (they reach 0.10 in at the belt)
    part('pillar_b_shut_l', bevel=0)
    part('pillar_b_shut_r', bevel=0).add(
        P.facing([np.array([(xb, by0, z(RDOOR[0] - 0.03)), (xb, by0, z(RDOOR[0] + 0.03)),
                            (xb, by1, z(RDOOR[0] + 0.03)), (xb, by1, z(RDOOR[0] - 0.03))])], (1, 0, 0))[0], 'under_paint')

    # ---- the nose: stacked twin lamps, a driving lamp over an amber blinker
    for sx, nm in ((1, 'r'), (-1, 'l')):
        head = part('head_' + nm, bevel=0)
        xa, xb_ = sorted((sx * HEAD[0], sx * HEAD[2]))
        _skin_box(ctx, head, 'front', (xa - 0.010, TURN_F[1] - 0.010, xb_ + 0.010, HEAD[3] + 0.010), 'plastic', 0.004)
        _skin_decal(ctx, head, 'front', (xa, HEAD[1], xb_, HEAD[3]), 'glow_lens', 0.006)
        P.decal(head, D, ctx.body_tris, {'ellipse': (0.5 * (xa + xb_), 0.5 * (HEAD[1] + HEAD[3]), 0.040, 0.034, 10),
                                         'view': 'front', 'cell': 0.06}, 'glow_head', 0.008)
        q = P.laid_on(ctx.body_tris, 'front', [(0.5 * (xa + xb_), 0.5 * (HEAD[1] + HEAD[3]))], 0.008)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = [float(v) for v in q[0]]
        _skin_decal(ctx, part('turn_f' + nm, bevel=0), 'front', (xa, TURN_F[1], xb_, TURN_F[3]), 'glow_turn', 0.006)

    # ---- the tail: split lamps
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xs = lambda a, b: sorted((sx * a, sx * b))
        blk = part('lamp_block_' + nm, bevel=0)
        for (x0, y0, x1, y1), pad in ((UPPER, (0.008, 0.008, 0.008, 0.006)), (WRAP, (0.008, 0.004, 0.008, 0.008)),
                                      (LOWER, (0.008, 0.008, 0.008, 0.008))):
            xa, xb_ = xs(x0, x1)
            _skin_box(ctx, blk, 'rear', (xa - pad[0], y0 - pad[1], xb_ + pad[2], y1 + pad[3]), 'plastic', 0.004)
        # upper: the amber blinker inboard, the running lamp outboard and its wrap up the pillar
        tail = part('tail_' + nm, bevel=0)
        xa, xb_ = xs(UPPER_TURN + 0.005, UPPER[2])
        _skin_decal(ctx, tail, 'rear', (xa, UPPER[1], xb_, UPPER[3]), 'glow_tail', 0.006)
        q = P.laid_on(ctx.body_tris, 'rear', [(0.5 * (xa + xb_), 0.5 * (UPPER[1] + UPPER[3]))], 0.006)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = [float(v) for v in q[0]]
        xa, xb_ = xs(WRAP[0], WRAP[2])
        _skin_decal(ctx, tail, 'rear', (xa, WRAP[1], xb_, WRAP[3]), 'glow_tail', 0.006)
        xa, xb_ = xs(UPPER[0], UPPER_TURN)
        _skin_decal(ctx, part('turn_r' + nm, bevel=0), 'rear', (xa, UPPER[1], xb_, UPPER[3]), 'glow_turn', 0.006)
        # lower, in the bumper: the reversing lamp inboard, the brake lamp outboard (kept 40 cm under the
        # running lamp, so the two read apart at 100 m)
        xa, xb_ = xs(LOWER[0], LOWER_REV)
        _skin_decal(ctx, part('reverse_' + nm, bevel=0), 'rear', (xa, LOWER[1], xb_, LOWER[3]), 'glow_reverse', 0.006)
        xa, xb_ = xs(LOWER_REV + 0.005, LOWER[2])
        _skin_decal(ctx, part('brake_' + nm, bevel=0), 'rear', (xa, LOWER[1], xb_, LOWER[3]), 'glow_brake', 0.006)

    # ---- the tailgate: it hangs on the roof's rear edge and takes its spoiler, glass, plate, lamp, handle and wiper up
    hs = D['cabin']['C']
    hinges['hinge_hatch'] = {'pos': [0.0, round(pl(D['top'], hs) - 0.005, 4), round(z(hs), 4)],
                             'axis': [1, 0, 0], 'open_sign': -1, 'open_deg': 70, 'panel': 'hatch'}
    py = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    lamp = part('plate_lamp', parent='hinge_hatch', bevel=0)
    _skin_box(ctx, lamp, 'rear', (-0.11, py + 0.012, 0.11, py + 0.030), 'plastic', 0.012)
    _skin_decal(ctx, lamp, 'rear', (-0.09, py + 0.015, 0.09, py + 0.024), 'glow_lens', 0.0135)
    pull = part('handle_hatch', parent='hinge_hatch', bevel=0)
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, 0.80)], 0.008)
    if c is not None:
        P.obox(pull, c[0], (0.16, 0.022, 0.014), np.eye(3), 'plastic')
    _wiper_rear(ctx)
    # what shows when it is up: the boot floor and the back of the rear bench
    # (between the wheel wells, and walled down to the floor pan, so it stands on something)
    cargo = part('cargo', bevel=0)
    x, y, s0, s1 = WELL_X - 0.012, 0.62, axles[1] - 0.10, 4.00
    yf = pl(D['floor'], s1) + 0.0005
    cargo.add(P.facing([[(-x, y, z(s0)), (x, y, z(s0)), (x, y, z(s1)), (-x, y, z(s1))]], (0, 1, 0))[0], 'under_paint')
    cargo.add(P.facing([[(-x, y, z(s0)), (x, y, z(s0)), (x, 1.10, z(s0) - 0.10), (-x, 1.10, z(s0) - 0.10)]], (0, 0, 1))[0], 'rubber')
    for sx in (1, -1):
        cargo.add(P.facing([[(sx * x, yf, z(s0)), (sx * x, y, z(s0)), (sx * x, y, z(s1)), (sx * x, yf, z(s1))]], (sx, 0, 0))[0],
                  'under_paint')
    cargo.add(P.facing([[(-x, yf, z(s1)), (x, yf, z(s1)), (x, y, z(s1)), (-x, y, z(s1))]], (0, 0, 1))[0], 'under_paint')

    # ---- fuel flap on the left rear quarter, over the rear cladding
    K.fuel_flap(ctx, -1, FLAP[0], FLAP[1])
    # its hinge out past the flap's most outboard point: the flank leans in,
    # and a hinge on the skin at mid height swings the flap's lower front corner into it
    fh = hinges['hinge_fuel_flap']
    fh['pos'][0] = round(min(float(np.min(q[:, 0])) for q in ctx.parts['fuel_flap'].polys) - 0.006, 4)

    # ---- antenna: a short fin at the back of the roof, between the rails
    base = ctx.on_top(0.0, 3.62)
    if base is not None:
        P.obox(part('antenna', bevel=0), base + np.array([0.0, 0.028, 0.0]), (0.05, 0.056, 0.15), np.eye(3), 'plastic')

    # ---- brakes: the calipers stay on the uprights (the discs are in the wheels' meshes); black stock
    for ai, tagf, dr in ((0, 'f', DISC_F), (1, 'r', DISC_R)):
        tw = wh['w'] if ai == 0 else wh.get('w_rear', wh['w'])
        track = wh['track'] if ai == 0 else wh.get('track_rear', wh['track'])
        for sx, nm in ((1, 'r'), (-1, 'l')):
            hub_x = sx * (track / 2 - tw / 2 - 0.018)
            P.obox(part('caliper_' + tagf + nm, bevel=0), (hub_x, r_w + dr - 0.035, z(axles[ai])), (0.04, 0.07, 0.12),
                   np.eye(3), 'plastic')

    # ---- what shows in the wheel wells (it is lifted: the low camera sees in)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        sf = part('susp_f' + nm, bevel=0)          # a strut and its lower arm
        K.cyl(sf, (sx * 0.60, r_w + 0.02, z(axles[0])), (sx * 0.58, r_w + 0.36, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        K.cyl(sf, (sx * (WELL_X + 0.004), r_w - 0.08, z(axles[0])), (sx * 0.60, r_w - 0.06, z(axles[0])), 0.02, 4, 'steel', caps=(False, False))
        sr = part('susp_r' + nm, bevel=0)          # a multi-link's trailing arm and its shock
        K.cyl(sr, (sx * 0.60, r_w + 0.02, z(axles[1] - 0.30)), (sx * 0.60, r_w - 0.02, z(axles[1])), 0.022, 4, 'steel', caps=(False, False))
        K.cyl(sr, (sx * 0.57, r_w + 0.03, z(axles[1]) + 0.08), (sx * 0.55, r_w + 0.34, z(axles[1]) + 0.06), 0.028, 6, 'steel', caps=(False, False))

    # ---- the skid plate under the nose
    P.obox(part('skid_plate', bevel=0), (0.0, 0.2145, z(0.62)), (0.72, 0.010, 0.60), np.eye(3), 'steel')   # its top 0.5 mm under the floor

    # ---- under the hood: the flat four (low and wide), its intake, the radiator, the battery
    en = part('engine', bevel=0)
    P.obox(en, (0.0, 0.56, z(0.78)), (0.66, 0.26, 0.40), np.eye(3), 'steel')
    P.obox(en, (0.0, 0.72, z(0.80)), (0.40, 0.06, 0.26), np.eye(3), 'plastic')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.62, z(0.42)), (0.66, 0.36, 0.04), np.eye(3), 'rubber')
    P.obox(part('bay_battery', bevel=0), (-0.35, 0.62, z(0.51)), (0.18, 0.12, 0.10), np.eye(3), 'plastic')


def _wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    dr = DISC_F if axle == 0 else DISC_R
    alloy_face(D, part, sx, tw, dr)           # five real spokes, the disc seen between them
    # vented: a second plate behind the face with the air gap between them, and the hat
    x0 = -sx * tw / 2
    K.cyl(part, (x0 - sx * 0.020, 0, 0), (x0 - sx * 0.028, 0, 0), dr * 0.86, 8, 'plastic', caps=(False, False))
    K.cyl(part, (x0 - sx * 0.028, 0, 0), (x0 - sx * 0.036, 0, 0), dr, 12, 'steel')
    K.cyl(part, (x0, 0, 0), (x0 - sx * 0.036, 0, 0), dr * 0.45, 8, 'steel', caps=(False, False))


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    axles = fcar._axles(D)
    A['bay_engine'] = {'pos': [0.0, 0.56, z(0.78)]}
    A['bay_radiator'] = {'pos': [0.0, 0.62, z(0.42)]}
    # the boost branch of its tree: the turbo beside the right bank, the intercooler on top under the hood scoop
    A['bay_turbo'] = {'pos': [0.42, 0.52, z(0.90)]}
    A['bay_intercooler'] = {'pos': [0.0, 0.84, z(0.86)]}
    A['diff'] = {'pos': [0.0, D['wheel']['r'], z(axles[1])]}
    A['fuel_filler'] = {'pos': [-pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    # the wheel wells' inner wall at 0.46 instead of the fleet's 0.63: a front tyre at full lock (38 deg)
    # swings its leading edge well inside the usual wall 3.5 cm in from the tyre
    'defn': {'well_x': WELL_X},
    'regions': {
        'nose_s': 0.36,                    # the front bumper ends ahead of the front cladding
        'door_s0': DOOR_S0,
        'tail_s': 4.04, 'tail_y': 0.58,    # the rear bumper, behind the rear cladding and under the tailgate
    },
    'merge_flat': True,
    'no_trunk': True,                      # the tail is one tailgate
    'no_antenna': True,                    # the kit stands its own fin on the roof
    'hinge_of': {'door_rr': 'hinge_door_rr', 'door_rl': 'hinge_door_rl',
                 'glass_door_rr': 'hinge_door_rr', 'glass_door_rl': 'hinge_door_rl',
                 'hatch': 'hinge_hatch', 'glass_backlight': 'hinge_hatch', 'plate_r': 'hinge_hatch'},
    'plates': PLATES,
    'asymmetric': {
        'wiper_rear': 'one rear wiper, on the tailgate glass',
        'fuel_recess': 'one filler, on the left rear quarter',
        'fuel_flap': 'one filler, on the left rear quarter',
        'bay_battery': 'one battery, front left',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'vented disc 316 mm, black caliper', 'rear': 'vented disc 300 mm, black caliper'},
              'brake_lamps': 2, 'third_brake': 1, 'reverse': 2, 'blinkers_front': 2, 'blinkers_rear': 2,
              'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1, 'wipers': 3, 'fuel_flap': 1, 'doors': 4,
              'condition': 0.5},
    # stance data (car-and-parts audit J2, car-shape-and-stance S3/S4): numbers for the
    # shared stance pass, NOT applied here or in the game; the model stands as the sheet.
    # Rally-raised: no drop and no push-out (the shape note keeps its 22 cm clearance)
    'stance': {'ride_height': 0.22, 'arch_gap': [0.045, 0.045], 'rake_deg': 0.0, 'rear_camber_deg': 0.0,
               'body_drop': 0.0, 'wheel_push_out': 0.0, 'flare_x': CLAD_X,
               'tyre_outer_x': [0.8975, 0.9125], 'note': 'front 235 / rear 265 tyres on a 1.56 m track; not applied'},
    'cuts': _cuts, 'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
