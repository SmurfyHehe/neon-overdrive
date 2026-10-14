"""P3, the tuner sedan (Takumi Ronin): what it adds to the common parts recipe.

90s all-wheel-drive four-door tuner sedan, T2, sheet p3_tuner (DECIDED, Roy
291 and 301-303). The first car from parts with four doors: the common recipe
cuts the front pair, this kit cuts the rear pair (`door_rl/rr`) between the
B-pillar and the rear arch, each with its own glass, seal, handle and hinge on
the B-pillar line; the fixed quarter light behind it stays on the body. Four
riveted box overfenders (`flare_*`) stand on the skin, 8 cm proud of the arch
step (1.94 m over the flares, the sheet's width); the front leg of each rear
flare is on the rear door (`flare_door_rl/rr`) and opens with it. Slim bar
headlamps over a black slot grille, amber blinkers and the plate in the
bumper over the mouth. Four equal round tail lamps 30 cm apart in a framed
body-colour panel: the outer pair runs (`tail_*`), the inner pair is the brake
lamp (`brake_*`); amber blinkers and white reversing lamps in the rear
bumper, a lamp over the rear plate, no high brake lamp (era, Roy 1224).
300 mm vented discs on all four with bronze single-pot calipers on the
uprights, behind real ten spokes. Struts in front, a multi-link rear. The
pedestal wing is the first wing buy (Roy 302) but stays fitted until the
garage exists (the sheet); it rides on the deck lid. Clean, no wear (Roy 303).

The fleet loft is the sheet's shape and stays it (wheelbase 2.62, track 1.52,
4.48 long): this is a visual rebuild; physics, tune and the collision box are
not touched. Kept in its own file (kits.KITS imports KIT from here).
"""
import math

import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl
from kit_p2_hothatch import alloy_face

REAR_DOOR = (2.50, 3.30)   # the rear door: from the B-pillar line (shared shut line with the front door) to ahead of the arch
FLARE_X = 0.97             # a flare's outer face (the sheet: 1.94 over the flares, 8 cm proud of the 0.89 arch step)
FLARE_HL = 0.10            # a flare reaches this far past the arch, front and back
FLARE_TOP = 0.10           # and this far above it
FLARE_BEVEL = 0.02
FLARE_CHAMFER = 0.07
RIVETS = 14                # the sheet: 14 rivet heads a flare, round the arch
RIVET_R = 0.398            # on this radius from the hub
HEAD = (0.46, 0.80, 0.56, 0.68)       # slim bar headlamp, front view: x0, x1, y0, y1 (the sheet: 340 x 120)
TURN_F = (0.56, 0.72, 0.44, 0.50)     # amber blinkers in the bumper, beside the plate
MOUTH = (0.56, 0.27, 0.40)            # the bumper mouth: half width, y0, y1 (under the plate)
ROUNDS = (0.68, 0.38)                 # tail rounds, rear view x: outer (running) and inner (brake), 30 cm apart, clear of the corner
ROUND_Y = 0.795                       # their centre (the tail face rolls onto the deck from 0.885; the sheet's 0.84 would wrap)
ROUND_R = 0.0725                      # 145 mm, four the same (Roy 301)
TAIL_PANEL = (0.78, 0.70, 0.703, 0.884)   # the body-colour band they sit in: half width at the bottom, at the top, y0, y1
NOSE_KNEE = (0.55, 0.61)              # where the flat of the nose rolls back to the hood: decals there are cut in thin bands
TURN_R = (0.58, 0.74, 0.36, 0.41)     # rear blinkers in the bumper corners
REVERSE = (0.32, 0.46, 0.36, 0.41)    # reversing lamps in the bumper
PLATES = {'plate_f': ('front', 0.47, 0.26, 0.055), 'plate_r': ('rear', 0.55, 0.26, 0.055)}   # 520 x 110
FLAP = (4.16, 0.70)        # fuel flap on the right rear quarter, behind the flare
DISC_R = 0.15              # 300 mm vented discs, all four (the sheet)
CALIPER_IN = 0.0185        # the caliper's centre this far inboard of the wheel's inner face: over the disc, clear of the well's inner wall
WELL_X = 0.46               # the wheel wells' inner wall, metres from the centre line (the fleet's: 0.603)
PILLAR_LIFT = 0.0065       # the A-pillar strip lifted this much more than the common 4 mm: the merged glass under it is up to 3 mm off the loft


# --------------------------------------------------------------------------
# Helpers
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


def _bands(ctx, part, view, rect, mat, off, knee=None, fine=0.010, cell=0.045):
    """A rect decal; where it crosses a knee in the skin (y0..y1) it is laid in
    bands `fine` tall, so no flat cell spans the crease and lets it through."""
    x0, y0, x1, y1 = rect
    cuts = [y0, y1]
    if knee is not None:
        a, b = max(y0, knee[0]), min(y1, knee[1])
        if b > a:
            n = max(1, math.ceil((b - a) / fine))
            cuts += [a + (b - a) * k / n for k in range(n + 1)]
    cuts = sorted(set(round(c, 6) for c in cuts))
    for b0, b1 in zip(cuts, cuts[1:]):
        if b1 - b0 > 1e-4:
            P.decal(part, ctx.D, ctx.body_tris, {'view': view, 'rect': (x0, b0, x1, b1), 'cell': cell}, mat, off)


SKIN_PARTS = ('body', 'underbody', 'bumper_f', 'bumper_r', 'fender_fl', 'fender_fr', 'hood', 'trunk', 'door_l', 'door_r', 'door_rl', 'door_rr')


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


def _skin_decal(ctx, part, view, rect, mat, off, skin=SKIN_PARTS):
    """A rect laid on the skin as the skin itself: every skin face the view
    sees under the rect, clipped to it and moved `off` out along the view.
    It follows each fold of the panel exactly, where a grid decal's flat
    cells cut through the fold between their corners. A face that is not a
    triangle may be split either way when it is drawn, so its copy stands
    off a little more, by how far the face is from flat. `skin`: the parts
    whose faces count (a kit with its own cut panels or glass in its skin set
    passes its own list, with ctx.skin_tris built from the same)."""
    from geom import AXES, raycast
    d = AXES[view]
    ia, ib = VIEW_AB[view]
    x0, y0, x1, y1 = rect
    planes = [(ia, x0, 1), (ia, x1, -1), (ib, y0, 1), (ib, y1, -1)]
    for name in skin:
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


# --------------------------------------------------------------------------
# Rear doors
# --------------------------------------------------------------------------
def _cuts(D, R, z, cut):
    """The rear doors: the side below the roof from the B-pillar line to the
    rear arch, down to the front doors' sill line. The B-pillar itself (the
    loft's `pillar` strip) stays on the body between the two door glasses."""
    for sx, nm in ((1, 'r'), (-1, 'l')):
        side = (lambda sx: lambda ps: (ps.col(1) == sx) & (ps.col(0) >= 3) & (ps.col(0) <= 7) & ~ps.mat_is('pillar'))(sx)
        cut('door_r' + nm, [((0, 0, 1), z(REAR_DOOR[0])), ((0, 0, -1), -z(REAR_DOOR[1])), ((0, 1, 0), R['door_y0'])], side, True)
    return ['door_rr', 'door_rl']


def _rear_doors(ctx):
    """Hinges on the B-pillar line and the handles (the common recipe makes the front pair's)."""
    D, R, z = ctx.D, ctx.R, ctx.z
    s0, s1 = REAR_DOOR
    belt = pl(D['belt'], s0)
    hs = s1 - 0.16
    hy = pl(D['belt'], hs) - 0.075
    for sx, nm in ((1, 'r'), (-1, 'l')):
        ctx.info.setdefault('hinges', {})['hinge_door_r' + nm] = {
            'pos': [round(sx * (pl(D['hw'], s0) - 0.02), 4), round(0.5 * (R['door_y0'] + belt), 4), round(z(s0), 4)],
            'axis': [0, 1, 0], 'open_sign': sx, 'open_deg': 60, 'panel': 'door_r' + nm}
        view = 'right' if sx > 0 else 'left'
        hp = ctx.part('handle_r' + nm, parent='hinge_door_r' + nm, bevel=0)
        zh = z(hs)
        _skin_decal(ctx, hp, view, (zh - 0.065, hy - 0.022, zh + 0.065, hy + 0.022), 'rubber', 0.002)
        grip = (zh - 0.0525, hy - 0.008, zh + 0.0525, hy + 0.008)   # the bar: its face follows the door's twist
        _skin_decal(ctx, hp, view, grip, 'chrome', 0.009)
        _rim(ctx, hp, view, K.rect2(*grip), 0.009, 'chrome')
        # the shut line between the front and the rear door: both panels open, so neither carries the
        # dark floor a fixed panel puts under its gap. A strip of it on the body 28 mm in (past both
        # doors' 15 mm returns and clear of the rear door's hinge 20 mm in), so the gap is not a hole
        zg = z(s0)
        ys = np.linspace(R['door_y0'] + 0.004, belt - 0.004, 8)
        edge = lambda dz: [P.laid_on(ctx.body_tris, view, [(zg + dz, y)], -0.028) for y in ys]
        fa, fb = edge(-0.012), edge(0.012)
        if all(q is not None for q in fa + fb):
            fa, fb = [np.asarray(q[0], float) for q in fa], [np.asarray(q[0], float) for q in fb]
            fa.append(fa[-1] + np.array([0.0, 0.016, 0.0]))      # on up past the belt, behind the pillar's foot
            fb.append(fb[-1] + np.array([0.0, 0.016, 0.0]))
            ys = list(ys) + [belt + 0.012]
            for k in range(len(ys) - 1):
                ctx.part('body').add(P.facing([[fa[k], fb[k], fb[k + 1], fa[k + 1]]], (sx, 0, 0))[0], 'under_paint', P.FLOOR)


# --------------------------------------------------------------------------
# Box overfenders
# --------------------------------------------------------------------------
def _inset(poly, d):
    """A convex polygon (counter-clockwise in s, y) moved in by d on every edge."""
    n = len(poly)
    lines = []
    for i in range(n):
        a, b = np.array(poly[i], float), np.array(poly[(i + 1) % n], float)
        e = (b - a) / np.linalg.norm(b - a)
        lines.append((a + np.array([-e[1], e[0]]) * d, e))
    out = []
    for i in range(n):
        (p0, e0), (p1, e1) = lines[i - 1], lines[i]
        t = np.linalg.solve(np.column_stack([e0, -e1]), p1 - p0)[0]
        out.append(p0 + e0 * t)
    return out


def _ray_hit(poly, c, a):
    """Where the ray from c at angle a leaves a convex polygon."""
    d = np.array([math.cos(a), math.sin(a)])
    best = None
    n = len(poly)
    for i in range(n):
        p, q = np.array(poly[i], float), np.array(poly[(i + 1) % n], float)
        m = np.column_stack([d, p - q])
        if abs(np.linalg.det(m)) < 1e-12:
            continue
        t, u = np.linalg.solve(m, p - c)
        if t > 1e-9 and -1e-9 <= u <= 1 + 1e-9 and (best is None or t < best):
            best = t
    return c + d * best


def _outside_arch(p, cen, Ra, m=0.012):
    """(s, y) moved just clear of the wheel arch, to read the skin there: the
    loft's arch is a half circle over the hub and a straight slot below it."""
    d = p - cen
    if d[1] < 0:
        if abs(d[0]) < Ra + m:
            return np.array([cen[0] + math.copysign(Ra + m, d[0]), p[1]])
        return p
    r = np.linalg.norm(d)
    return cen + d / r * (Ra + m) if r < Ra + m else p


def _skin_x(ctx, sx, p, cen, Ra):
    """|x| of the side skin at (s, y), read just clear of the wheel arch when
    the point is on its edge (the loft's arch widens a little toward the sill,
    so the reading steps out until it is on the skin, not the well's liner)."""
    hw = pl(ctx.D['hw'], p[0])
    for m in (0.012, 0.024, 0.036, 0.05, 0.07):
        q = _skin(ctx, sx, *_outside_arch(p, cen, Ra, m))
        if q is not None and abs(q[0]) > hw - 0.06:
            return abs(q[0])
    return hw


def _flare_geometry(ctx, sx, s_ax):
    """One box overfender as polygons (car space): [(poly, mat, kind)], and
    the 2D data its split caps need. A flat outer face at FLARE_X with a
    rubber edge round the arch, a bevel all round, a flat top and upright ends
    back to the skin (each corner laid on the skin itself, so the walls meet
    it where the loft's arch step is still rising), a return round the arch
    back to the skin, and the rivets."""
    D, z = ctx.D, ctx.z
    wh = D['wheel']
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    yc = wh['r'] + wh.get('arch_lift', 0.0)
    b, c = FLARE_BEVEL, FLARE_CHAMFER
    x_out, x_bev = FLARE_X, FLARE_X - b
    s_a, s_b = s_ax - Ra - FLARE_HL, s_ax + Ra + FLARE_HL
    y_top = yc + Ra + FLARE_TOP
    y_bot = pl(D['floor'], s_ax) + 0.015
    O = [(s_a, y_bot), (s_b, y_bot), (s_b, y_top - c), (s_b - c, y_top), (s_a + c, y_top), (s_a, y_top - c)]
    Oi = _inset(O, b)
    cen = np.array([s_ax, yc])
    side = np.array([sx, 0.0, 0.0])
    polys = []

    def P3(p, x):
        return np.array([sx * x, p[1], z(p[0])])

    def skin(p):
        # the skin at this point: a point on the arch edge is read just outside it (inside is the wheel well)
        return P3(p, _skin_x(ctx, sx, np.asarray(p, float), cen, Ra))

    def face(pts, x, mat, want=side):
        polys.append((P.facing([[P3(p, x) for p in pts]], want)[0], mat, P.SKIN if mat == 'paint' else P.DETAIL))

    angs = sorted({round(math.pi * k / 10, 6) for k in range(11)} |
                  {round(math.atan2(p[1] - yc, p[0] - s_ax), 6) for p in Oi[2:]})
    rows = []
    for a in angs:
        d = np.array([math.cos(a), math.sin(a)])
        rows.append((cen + d * (Ra - 0.004), cen + d * (Ra + 0.015), _ray_hit(Oi, cen, a)))
    def wall(a, b, x, want, mat, kind):
        a, b = np.asarray(a, float), np.asarray(b, float)
        _strip(polys, lambda t: P3(a + (b - a) * t, x), lambda t: skin(a + (b - a) * t), want, mat, kind)

    for (i0, r0, o0), (i1, r1, o1) in zip(rows, rows[1:]):
        face((i0, i1, r1, r0), x_out, 'rubber')
        face((r0, r1, o1, o0), x_out, 'paint')
        # the return round the arch, from the outer face back to the skin
        toward = np.array([0.0, yc, z(s_ax)]) - P3((i0 + i1) / 2, 0.0) * np.array([0.0, 1.0, 1.0])
        wall(i0, i1, x_out, toward, 'rubber', P.DETAIL)
    # the two legs down to the sill
    for sgn, (i_, r_, o_) in ((1, rows[0]), (-1, rows[-1])):
        lo = lambda p: np.array([p[0], y_bot])
        face((lo(i_), i_, r_, lo(r_)), x_out, 'rubber')
        face((lo(r_), r_, o_, lo(o_)), x_out, 'paint')
        wall(lo(i_), i_, x_out, np.array([0.0, 0.0, -sgn]), 'rubber', P.DETAIL)
    # the bevel, and the walls back to the skin (not along the bottom)
    for k in range(1, len(O)):
        j = (k + 1) % len(O)
        mid = (np.array(O[k]) + np.array(O[j])) / 2 - cen
        want = np.array([sx * 0.5, mid[1], mid[0]])
        polys.append((P.facing([[P3(Oi[k], x_out), P3(Oi[j], x_out), P3(O[j], x_bev), P3(O[k], x_bev)]], want)[0], 'paint', P.SKIN))
        wall(O[k], O[j], x_bev, np.array([0.0, mid[1], mid[0]]), 'paint', P.SKIN)
    rivets = []
    for k in range(RIVETS):
        a = math.radians(10.0 + 160.0 * k / (RIVETS - 1))
        rivets.append(np.array([s_ax - RIVET_R * math.cos(a), yc + RIVET_R * math.sin(a)]))
    geo = {'Ra': Ra, 'yc': yc, 's_a': s_a, 's_b': s_b, 'y_top': y_top, 'y_bot': y_bot, 'O': O, 'Oi': Oi}
    return polys, rivets, geo


def _rivet(part, ctx, sx, p):
    a = np.array([sx * FLARE_X, p[1], ctx.z(p[0])])
    K.cyl(part, a, a + np.array([sx * 0.004, 0.0, 0.0]), 0.009, 4, 'steel', caps=(False, False), r_b=0.0)


def _clip_all(polys, planes):
    out = []
    for poly, mat, kind in polys:
        q = poly
        for n, d in planes:
            q, _ = P.clip_poly(q, np.asarray(n, float), d)
            if q is None:
                break
        if q is not None:
            out.append((q, mat, kind))
    return out


def _flares(ctx):
    """Four box overfenders. The rear ones are split on the rear door's shut
    line: the front leg rides on the door (`flare_door_*`, on its hinge), the
    rest is a body part, and both are closed where they are cut."""
    D, R, z = ctx.D, ctx.R, ctx.z
    axles = fcar._axles(D)
    g2 = P.GAP / 2
    for ai, s_ax in enumerate(axles):
        for sx, nm in ((1, 'r'), (-1, 'l')):
            polys, rivets, geo = _flare_geometry(ctx, sx, s_ax)
            name = 'flare_%s%s' % ('f' if ai == 0 else 'r', nm)
            if ai == 0:
                part = ctx.part(name, bevel=0)
                for q, m, k in polys:
                    part.add(q, m, k)
                for p in rivets:
                    _rivet(part, ctx, sx, p)
                continue
            s_cut, y_cut = REAR_DOOR[1], R['door_y0']
            door = ctx.part('flare_door_r' + nm, parent='hinge_door_r' + nm, bevel=0)
            body = ctx.part(name, bevel=0)
            on_door = [((0, 0, -1), -z(s_cut) + g2), ((0, 1, 0), y_cut + g2)]
            behind = [((0, 0, 1), z(s_cut) + g2)]
            under = [((0, 0, -1), -z(s_cut) - g2), ((0, -1, 0), -(y_cut - g2))]
            for q, m, k in _clip_all(polys, on_door):
                door.add(q, m, k)
            for q, m, k in _clip_all(polys, behind) + _clip_all(polys, under):
                body.add(q, m, k)
            for p in rivets:
                if p[0] < s_cut - g2 - 0.012 and p[1] > y_cut + g2 + 0.012:
                    _rivet(door, ctx, sx, p)
                elif p[0] > s_cut + g2 + 0.012 or p[1] < y_cut - g2 - 0.012:
                    _rivet(body, ctx, sx, p)
            _flare_caps(ctx, sx, s_ax, geo, door, body, s_cut, y_cut)


def _flare_caps(ctx, sx, s_ax, geo, door, body, s_cut, y_cut):
    """Close a rear flare where the door's shut line cuts it: an upright cap
    each side of the cut above the arch, a level cap each side of the door's
    bottom edge on the front leg."""
    z = ctx.z
    Ra, yc, s_a, y_top = geo['Ra'], geo['yc'], geo['s_a'], geo['y_top']
    b = FLARE_BEVEL
    x_out, x_bev = FLARE_X, FLARE_X - b
    g2 = P.GAP / 2
    fwd = np.array([0.0, 0.0, -1.0])

    def skin(s, y):
        # read just outside the arch (inside it is the wheel well)
        return np.array([sx * _skin_x(ctx, sx, np.array([s, y]), np.array([s_ax, yc]), Ra), y, z(s)])

    def X(x, y, s):
        return np.array([sx * x, y, z(s)])

    for s, part, want in ((s_cut - g2, door, -fwd), (s_cut + g2, body, fwd)):
        dx = s_ax - s
        y_lo = yc + math.sqrt(max(0.0, (Ra - 0.004) ** 2 - dx * dx))
        polys = [(P.facing([[X(x_out, y_top - b, s), X(x_bev, y_top, s), skin(s, y_top), skin(s, y_top - b)]], want)[0],
                  'paint', P.SKIN)]
        _strip(polys, lambda t, s=s, y_lo=y_lo: X(x_out, y_lo + (y_top - b - y_lo) * t, s),
               lambda t, s=s, y_lo=y_lo: skin(s, y_lo + (y_top - b - y_lo) * t), want, 'paint', P.SKIN)
        for q, m, k in polys:
            part.add(q, m, k)
    # the front leg at the door's bottom edge: from the leg's front face to the arch
    for y, part, want in ((y_cut + g2, door, np.array([0.0, -1.0, 0.0])), (y_cut - g2, body, np.array([0.0, 1.0, 0.0]))):
        dy = y - yc
        s_arch = s_ax - math.sqrt(max(0.0, (Ra - 0.004) ** 2 - dy * dy))
        polys = [(P.facing([[X(x_bev, y, s_a), X(x_out, y, s_a + b), skin(s_a + b, y), skin(s_a, y)]], want)[0], 'paint', P.SKIN)]
        _strip(polys, lambda t, y=y, s_arch=s_arch: X(x_out, y, s_a + b + (s_arch - s_a - b) * t),
               lambda t, y=y, s_arch=s_arch: skin(s_a + b + (s_arch - s_a - b) * t, y), want, 'paint', P.SKIN)
        for q, m, k in polys:
            part.add(q, m, k)


# --------------------------------------------------------------------------
# Sheet decals and parts
# --------------------------------------------------------------------------
def _decal(ctx, d):
    with _on_skin(ctx):
        return _decal_on(ctx, d)


def _decal_on(ctx, d):
    mat, tag, view = d['mat'], d.get('tag'), d['view']
    if mat in ('head', 'turn', 'tail'):
        return True                               # every lamp is a part of its own: fittings
    if view == 'rear' and mat == 'trim' and tag is None:
        return True                               # the sheet's plate recess: the plate brings its own
    if mat == 'grille' and tag is None:           # the slot grille between the lamps, on the nose's knee: in bands
        x0, y0, x1, y1 = d['rect']
        g = ctx.part('grille', bevel=0)
        _skin_decal(ctx, g, 'front', (x0, y0, x1, y1), 'rubber', 0.005)
        _rim(ctx, g, 'front', K.rect2(x0, y0, x1, y1), 0.005, 'rubber')
        for k in range(3):
            yc = y0 + (y1 - y0) * (k + 1) / 4
            _skin_decal(ctx, g, 'front', (x0 + 0.01, yc - 0.008, x1 - 0.01, yc + 0.008), 'plastic', 0.012)
        return True
    if tag == 'rbumper':                          # the band on the rear valance: a finer grid, so the valance's bend stays under it
        x0, y0, x1, y1 = d['rect']
        _skin_decal(ctx, ctx.part('bumper_r_insert', bevel=0), 'rear', (x0, y0, x1, y1), 'plastic', 0.004)
        return True
    if tag == 'fbumper':                          # the bumper mouth, under the plate
        hw_, y0, y1 = MOUTH
        g = ctx.part('grille', bevel=0)
        _skin_decal(ctx, g, 'front', (-hw_, y0, hw_, y1), 'rubber', 0.003)
        _rim(ctx, g, 'front', K.rect2(-hw_, y0, hw_, y1), 0.003, 'rubber')
        for k in range(2):
            yc = y0 + (y1 - y0) * (k + 1) / 3
            _skin_decal(ctx, g, 'front', (-hw_ + 0.01, yc - 0.008, hw_ - 0.01, yc + 0.008), 'plastic', 0.010)
        return True
    return False


def _sheet_part(ctx, p):
    with _on_skin(ctx):
        return _sheet_part_on(ctx, p)


def _sheet_part_on(ctx, p):
    if p['type'] != 'mirrors':
        return False                              # the pedestal wing: the common recipe, on the deck lid's hinge
    pm = fcar.CarModel(ctx.D)
    fcar.add_part(pm, p)
    for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
        tri = np.array(tri)
        nm = 'l' if tri[:, 0].mean() < 0 else 'r'
        ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
    # the sheet's mirror stands on a stub 6 cm over the belt: a foot from the stub down onto the door top
    s = p.get('s', ctx.D['cabin']['A'] + 0.14)
    x7, y7 = fcar._section_at(ctx.D, s)[7][:2]
    y_stub = y7 + p.get('up', 0.09) - 0.025
    xa, xb = x7 + 0.004, x7 + 0.034
    z0, z1 = ctx.z(s) - 0.008, ctx.z(s) + 0.045
    for sx, nm in ((1, 'r'), (-1, 'l')):
        feet = [P.laid_on(ctx.body_tris, 'top', [(sx * x, z_)], -0.0005) for x in (xa, xb) for z_ in (z0, z1)]
        if any(f is None for f in feet):
            continue
        part = ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0)
        lo = [np.asarray(f[0], float) for f in feet]                   # (xa,z0) (xa,z1) (xb,z0) (xb,z1), each on the door top
        hi = [np.array([q[0], y_stub, q[2]]) for q in lo]
        c = np.mean(lo + hi, axis=0)
        for a, b in ((0, 1), (1, 3), (3, 2), (2, 0)):
            q = [lo[a], lo[b], hi[b], hi[a]]
            part.add(P.facing([q], np.mean(q, axis=0) - c)[0], 'plastic')
        part.add(P.facing([[hi[0], hi[1], hi[3], hi[2]]], (0, 1, 0))[0], 'plastic')
    return True


# --------------------------------------------------------------------------
# The car's own parts
# --------------------------------------------------------------------------
def _fittings(ctx):
    _flares(ctx)                                  # on the loft: the flares stand on its arch step
    with _on_skin(ctx):
        _fittings_on(ctx)


def _fittings_on(ctx):
    D, part, z, R = ctx.D, ctx.part, ctx.z, ctx.R
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']

    _rear_doors(ctx)

    for sx, nm in ((1, 'r'), (-1, 'l')):
        # ---- slim bar headlamp: a dark housing, the lens, the bulb. The nose rolls back 14 cm over the
        # lamp's height and round its corner, so each layer is a fine decal grid that hugs the skin
        x0, x1, y0, y1 = HEAD
        xa, xb = sorted((sx * x0, sx * x1))
        head = part('head_' + nm, bevel=0)
        dec = lambda shape, mat, off: P.decal(head, D, ctx.body_tris, dict(shape, view='front', cell=0.06), mat, off)
        hr = (xa - 0.006, y0 - 0.006, xb + 0.006, y1 + 0.006)
        _skin_decal(ctx, head, 'front', hr, 'plastic', 0.007)
        _rim(ctx, head, 'front', K.rect2(*hr), 0.007)
        _skin_decal(ctx, head, 'front', (xa + 0.008, y0 + 0.008, xb - 0.008, y1 - 0.008), 'glow_lens', 0.010)
        bc = (sx * 0.5 * (x0 + x1), 0.5 * (y0 + y1))
        dec({'ellipse': (bc[0], bc[1], 0.060, 0.034, 10)}, 'glow_head', 0.013)
        q = P.laid_on(ctx.body_tris, 'front', [bc], 0.013)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = [float(v) for v in q[0]]
        # ---- front blinkers: amber, in the bumper beside the plate
        x0, x1, y0, y1 = TURN_F
        xa, xb = sorted((sx * x0, sx * x1))
        tf = part('turn_f' + nm, bevel=0)
        hr = (xa - 0.006, y0 - 0.006, xb + 0.006, y1 + 0.006)
        _skin_decal(ctx, tf, 'front', hr, 'plastic', 0.005)
        _rim(ctx, tf, 'front', K.rect2(*hr), 0.005)
        P.decal(tf, D, ctx.body_tris, {'view': 'front', 'rect': (xa, y0, xb, y1), 'cell': 0.04}, 'glow_turn', 0.008)

        # ---- the tail: four equal rounds. Outer pair: running lamps; inner pair: brake lamps.
        # Each a dark bezel, a thin red lens ring and the lit element (most of the lamp: the
        # common recipe's rule, a wide ring loses the lamp at night).
        for x, pname, glow in ((ROUNDS[0], 'tail_', 'glow_tail'), (ROUNDS[1], 'brake_', 'glow_brake')):
            c = (sx * x, ROUND_Y)
            lp = part(pname + nm, bevel=0)
            K.lay_ring(ctx, lp, 'rear', c, (ROUND_R + 0.008, ROUND_R + 0.008), (ROUND_R, ROUND_R), 'plastic', 0.0025)
            K.lay_ring(ctx, lp, 'rear', c, (ROUND_R, ROUND_R), (ROUND_R * 0.82, ROUND_R * 0.82), 'lens_red', 0.007)
            q = K.lay(ctx, lp, 'rear', K.ellipse(c[0], c[1], ROUND_R * 0.82, ROUND_R * 0.82, 12), glow, 0.006)
            if q is not None and pname == 'tail_':
                ctx.lamps.setdefault('tail', {})[nm] = K.lamp_centre(q)
        # ---- rear blinkers and reversing lamps in the bumper
        for (x0, x1, y0, y1), pname, glow in ((TURN_R, 'turn_r', 'glow_turn'), (REVERSE, 'reverse_', 'glow_reverse')):
            xa, xb = sorted((sx * x0, sx * x1))
            lp = part(pname + nm, bevel=0)
            P.decal(lp, D, ctx.body_tris, {'view': 'rear', 'rect': (xa - 0.006, y0 - 0.006, xb + 0.006, y1 + 0.006), 'cell': 0.06},
                    'plastic', 0.0025)
            K.lay(ctx, lp, 'rear', K.rect2(xa, y0, xb, y1), glow, 0.006)

    # ---- the tail panel: a dark frame round the body-colour band the four rounds sit in
    # (top and bottom lines: the band runs out to the body corners, where the tail face turns)
    hw_p, hw_top, py0, py1 = TAIL_PANEL
    tp = part('tail_panel', bevel=0)
    f = 0.006
    for rect in ((-hw_p, py0, hw_p, py0 + f), (-hw_top, py1 - f, hw_top, py1)):
        P.decal(tp, D, ctx.body_tris, {'view': 'rear', 'rect': rect, 'cell': 0.2}, 'rubber', 0.002)

    # ---- the lamp over the rear plate
    pl_y = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, pl_y + 0.024)], 0.014)
    if c is not None:
        P.obox(part('plate_lamp', bevel=0), c[0], (0.12, 0.018, 0.024), np.eye(3), 'plastic', {'-y': 'glow_lens'})

    # ---- brakes: a bronze single-pot caliper on each upright (the vented disc is in the wheel's mesh)
    for ai, tagf in ((0, 'f'), (1, 'r')):
        tw = wh['w'] if ai == 0 else wh.get('w_rear', wh['w'])
        for sx, nm in ((1, 'r'), (-1, 'l')):
            hub_x = sx * (wh['track'] / 2 - tw / 2 - CALIPER_IN)
            P.obox(part('caliper_' + tagf + nm, bevel=0), (hub_x, r_w + DISC_R - 0.035, z(axles[ai])), (0.028, 0.07, 0.12), np.eye(3), 'rim')

    # ---- what shows of the running gear in the wheel wells: a strut (in the bay, behind the well's
    # inner wall) and its lower arm in front; the multi-link rear's upper and lower arms and its shock.
    # The arms run from the inner wall out to the upright.
    for sx, nm in ((1, 'r'), (-1, 'l')):
        sf = part('susp_f' + nm, bevel=0)
        K.cyl(sf, (sx * 0.42, r_w + 0.17, z(axles[0])), (sx * 0.40, r_w + 0.36, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        K.cyl(sf, (sx * (WELL_X + 0.004), r_w - 0.08, z(axles[0])), (sx * 0.56, r_w - 0.07, z(axles[0])), 0.02, 4, 'steel', caps=(False, False))
        sr = part('susp_r' + nm, bevel=0)
        K.cyl(sr, (sx * (WELL_X + 0.004), r_w + 0.12, z(axles[1]) - 0.025), (sx * 0.55, r_w + 0.13, z(axles[1])), 0.016, 4, 'steel', caps=(False, False))
        K.cyl(sr, (sx * (WELL_X + 0.004), r_w - 0.08, z(axles[1]) + 0.03), (sx * 0.56, r_w - 0.08, z(axles[1])), 0.02, 4, 'steel', caps=(False, False))
        K.cyl(sr, (sx * 0.55, r_w + 0.02, z(axles[1]) + 0.10), (sx * 0.53, r_w + 0.315, z(axles[1]) + 0.12), 0.025, 6, 'steel', caps=(False, False))

    # ---- fuel flap on the right rear quarter, behind the flare (the tank is ahead of the rear axle)
    K.fuel_flap(ctx, 1, FLAP[0], FLAP[1])

    # ---- under the hood: a dark bay floor (narrow: the front tyres swing in under full lock) and the radiator
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    P.obox(part('bay_floor', bevel=0), (0.0, 0.42, z(hood_mid)), (0.84, 0.02, cab['A'] - R['nose_s'] - 0.10), np.eye(3), 'rubber')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.57, z(R['nose_s'] + 0.12)), (0.62, 0.28, 0.05), np.eye(3), 'rubber')

    _plates(ctx)
    _wipers(ctx)
    _antenna(ctx)
    _wing_feet(ctx)
    _pillars(ctx)
    _slot_walls(ctx)
    _pivots(ctx)


# --------------------------------------------------------------------------
# Fit: the common recipe's fittings made to stand on the car (tests/fleet/exterior_fit.gd)
# --------------------------------------------------------------------------
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


def _antenna(ctx):
    """A short mast on the left rear quarter (the common one, with its foot
    following the slope of the deck instead of standing flat into it)."""
    D, z = ctx.D, ctx.z
    s_a = D['cabin']['C'] + 0.10
    x = -(pl(D['hw'], s_a) - 0.16)
    on = lambda dx, dz: np.asarray(P.laid_on(ctx.body_tris, 'top', [(x + dx, z(s_a) + dz)], 0.0)[0], float)
    base = on(0, 0)
    nrm = np.cross(on(0, 0.01) - on(0, -0.01), on(0.01, 0) - on(-0.01, 0))
    nrm = nrm / np.linalg.norm(nrm) * (1 if nrm[1] > 0 else -1)
    an = ctx.part('antenna', bevel=0)
    K.cyl(an, base - nrm * 0.0005, base + nrm * 0.010, 0.012, 6, 'plastic', caps=(False, True))
    foot = base + nrm * 0.010
    tip = base + np.array([0.0, 0.27, 0.06])
    K.cyl(an, foot - nrm * 0.002, tip, 0.004, 3, 'rubber', caps=(False, False), r_b=0.0024)


def _wing_feet(ctx):
    """The sheet's pedestals end 19-21 mm over the deck lid: their feet are
    brought down onto it."""
    sp = ctx.parts.get('spoiler')
    if sp is None or not sp.polys:
        return
    sp.bevel = 0                                  # its 6 mm edge bevel costs ~120 triangles a wing nobody sees at 10 m
    y_min = min(float(q[:, 1].min()) for q in sp.polys)
    deck = lambda v: P.laid_on(ctx.body_tris, 'top', [(float(v[0]), float(v[2]))], -0.0005)
    for k, q in enumerate(sp.polys):
        foot = [v[1] < y_min + 0.004 for v in q]
        if not any(foot):
            continue
        out = []
        for i in range(len(q)):
            a, b = np.asarray(q[i], float), np.asarray(q[(i + 1) % len(q)], float)
            if not foot[i]:
                out.append(a)
                continue
            hit = deck(a)
            out.append(np.array([a[0], hit[0][1], a[2]]) if hit is not None else a)
            if foot[(i + 1) % len(q)]:            # a foot edge: it follows the deck's curve, not the chord under it
                f = lambda t, a=a, b=b: (lambda p, h: np.array([p[0], h[0][1], p[2]]))(a + (b - a) * t, deck(a + (b - a) * t))
                ts, f = _adaptive(f, tol=0.0005)
                out += [f(t) for t in ts[1:-1]]
        sp.polys[k] = np.array(out, float)


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


def _slot_walls(ctx):
    """The thin wall at the foot of each arch's slot meets the side at a right
    angle down at the sill: Blender's crease bevel throws that corner 28 mm
    under the car. The wall is left out of the bevel (hidden behind the flare leg)."""
    floor_y = lambda q: pl(ctx.D['floor'], q[2] + ctx.D['OHf'] + ctx.D['WB'] / 2.0)
    for name in ('body', 'fender_fl', 'fender_fr'):
        part = ctx.parts.get(name)
        if part is None:
            continue
        for k, q in enumerate(part.polys):
            nv = P.poly_normal(q)
            ln = np.linalg.norm(nv)
            if ln < 1e-10 or abs(nv[2]) / ln < 0.9 or np.abs(q[:, 0]).min() < 0.75:
                continue
            if any(v[1] <= floor_y(v) + 1e-3 for v in q):
                part.kind[k] = P.DETAIL


def _pivots(ctx):
    """Hinge lines on the outside of each panel's leading edge (the common
    recipe's sit 2 cm inside the skin): turning about a line inboard of the
    skin swings the panel's edge forward into the fender, A-pillar or front
    door ahead of it. Same panels, same angles; only the pivot moves."""
    D, R = ctx.D, ctx.R
    cab = D['cabin']
    H = ctx.info.setdefault('hinges', {})
    verts = lambda name: np.concatenate(ctx.parts[name].polys)
    z = ctx.z
    for door, s0 in (('door_', R['door_s0']), ('door_r', REAR_DOOR[0])):
        v = verts(door + 'r')
        v = v[v[:, 0] > 0]
        zf = v[:, 2].min()
        near = v[v[:, 2] < zf + 0.03]
        x = float(near[:, 0].max()) + 0.001
        y = 0.5 * (R['door_y0'] + pl(D['belt'], s0))
        for sx, nm in ((1, 'r'), (-1, 'l')):
            H['hinge_' + door + nm] = {'pos': [round(sx * x, 4), round(y, 4), round(float(zf) - 0.0005, 4)], 'axis': [0, 1, 0],
                                       'open_sign': sx, 'open_deg': 60, 'panel': door + nm}
    v = verts('hood')
    zr = v[:, 2].max()
    near = v[v[:, 2] > zr - 0.03]
    H['hinge_hood'] = {'pos': [0.0, round(float(near[:, 1].max()) + 0.001, 4), round(float(zr) + 0.0005, 4)], 'axis': [1, 0, 0],
                       'open_sign': 1, 'open_deg': 45, 'panel': 'hood'}
    v = verts('trunk')
    zf = v[:, 2].min()
    near = v[v[:, 2] < zf + 0.03]
    H['hinge_trunk'] = {'pos': [0.0, round(float(near[:, 1].max()) + 0.001, 4), round(float(zf) - 0.0005, 4)], 'axis': [1, 0, 0],
                        'open_sign': -1, 'open_deg': 50, 'panel': 'trunk'}
    v = verts('fuel_flap')
    zf = v[:, 2].min()
    h = H['hinge_fuel_flap']
    h['pos'] = [round(float(np.abs(v[:, 0]).max()) + 0.0005, 4), h['pos'][1], round(float(zf) - 0.0005, 4)]


# --------------------------------------------------------------------------
# Wheels: ten real bronze spokes, a 300 mm vented disc behind them
# --------------------------------------------------------------------------
def _wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    alloy_face(D, part, sx, tw, DISC_R)
    x0 = -sx * tw / 2
    K.cyl(part, (x0 - sx * 0.010, 0, 0), (x0 - sx * 0.018, 0, 0), DISC_R, 12, 'steel')
    K.cyl(part, (x0 - sx * 0.018, 0, 0), (x0 - sx * 0.026, 0, 0), DISC_R * 0.86, 8, 'plastic', caps=(False, False))
    K.cyl(part, (x0 - sx * 0.026, 0, 0), (x0 - sx * 0.034, 0, 0), DISC_R, 12, 'steel')
    K.cyl(part, (x0, 0, 0), (x0 - sx * 0.034, 0, 0), DISC_R * 0.45, 8, 'steel', caps=(False, False))


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    cab = D['cabin']
    axles = fcar._axles(D)
    r = D['wheel']['r']
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    A['bay_engine'] = {'pos': [0.0, 0.56, z(hood_mid + 0.10)]}          # the longitudinal straight six
    A['bay_radiator'] = {'pos': [0.0, 0.57, z(R['nose_s'] + 0.12)]}
    A['bay_turbo'] = {'pos': [0.30, 0.58, z(hood_mid + 0.05)]}          # no turbo stock: where fork B's goes (Roy 220)
    A['bay_intercooler'] = {'pos': [0.0, 0.335, z(0.10)]}               # behind the bumper mouth, shows only with a turbo
    A['diff'] = {'pos': [0.0, r - 0.01, z(axles[1])]}                   # the rear diff
    A['diff_f'] = {'pos': [0.0, r - 0.02, z(axles[0])]}                 # the front diff in the engine cradle (AWD)
    A['driveshaft'] = {'pos': [0.0, 0.22, z(0.5 * (axles[0] + axles[1]))]}
    A['subframe_f'] = {'pos': [0.0, 0.20, z(axles[0])]}
    A['subframe_r'] = {'pos': [0.0, 0.22, z(axles[1])]}
    A['tank'] = {'pos': [0.0, 0.26, z(axles[1] - 0.45)]}                # ahead of the rear axle (the sheet)
    A['fuel_filler'] = {'pos': [pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    # the wheel wells 30 cm deep instead of 16: a front tyre at full lock (38 deg) swings its leading edge
    # 29 cm in from the hub, through the fleet's usual wall 3.5 cm inside the tyre
    'defn': {'well_x': WELL_X},
    'regions': {
        'nose_s': 0.30,                    # the bumper cover is the whole nose, lamps and mouth in it
        'trunk_s1': 4.44,                  # the deck lid runs to the top of the tail face (the wing rides on it)
        'tail_s': 4.05, 'tail_y': 0.44,    # the rear bumper, behind the flare and under the plate
    },
    'merge_flat': True,
    'no_antenna': True,                    # its own, footed on the deck's slope (_antenna)
    'cuts': _cuts,
    'hinge_of': {'door_rl': 'hinge_door_rl', 'door_rr': 'hinge_door_rr',
                 'glass_door_rl': 'hinge_door_rl', 'glass_door_rr': 'hinge_door_rr',
                 'spoiler': 'hinge_trunk'},
    'plates': PLATES,
    'asymmetric': {
        'fuel_recess': 'one filler, on the right rear quarter',
        'fuel_flap': 'one filler, on the right rear quarter',
        'exhaust': 'one tip, on the left (the fleet stock exhaust)',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'vented disc 300 mm, single-pot caliper', 'rear': 'vented disc 300 mm, single-pot caliper'},
              'doors': 4, 'brake_lamps': 2, 'third_brake': 0, 'third_brake_note': 'none, era (Roy 1224)', 'reverse': 2,
              'blinkers_front': 2, 'blinkers_rear': 2, 'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1,
              'wipers': 2, 'fuel_flap': 1, 'headlamps': 'slim bar', 'condition': 0.0},
    # stance data (car-and-parts audit J2, car-shape-and-stance S3/S4): numbers for the
    # shared stance pass, NOT applied here or in the game; the model stands as the sheet
    'stance': {'ride_height': 0.12, 'arch_gap': [0.028, 0.028], 'rake_deg': 0.0, 'rear_camber_deg': 0.0,
               'body_drop': 0.010, 'wheel_push_out': 0.015, 'flare_x': FLARE_X,
               'tyre_outer_x': 0.8825, 'note': 'S3 drop 10 mm and S4 push-out 15 mm (shape note, tuner row); not applied'},
    'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
