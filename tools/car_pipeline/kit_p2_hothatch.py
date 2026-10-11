"""P2, the hot hatch (Juno's car): what it adds to the common parts recipe.

Front-drive three-door, sheet p2_hothatch (Roy 291-294). Two long doors, one
big glass hatch hinged on the roof's rear edge (the roof spoiler stays on the
roof), four riveted box blisters with flat bevelled tops, a black rub strip,
slim lamps with amber corners and two fogs, tall three-cell tail blocks, a
third brake lamp under the spoiler's edge, discs in front and drums behind.

Also here, for the cars after it: `alloy_face`, which rebuilds a sheet wheel's
painted-on spokes as real ones with the brake showing between them.
"""
import math

import numpy as np

import car as fcar
import parts as P
from geom import pl
from kits import cyl, disc_brake, drum, fuel_flap, lamp_centre, lay, lay_ring, rect2

HATCH_HW = 0.55        # the hatch reaches this far from the centre line, the lamp blocks stand outboard of it
HATCH_Y0 = 0.56        # and down to the top of the bumper
BLOCK_X = (0.56, 0.685)   # the three lamp cells (rear view)
BLOCK_AMBER = (0.69, 0.72)   # the amber edge outboard of them
BLISTER_HL = 0.08      # a blister reaches this far past the arch, front and back
BLISTER_TOP = 0.085    # and this far above it
BLISTER_X = 0.915      # its outer face (the sheet: 6.5 cm proud of the doors)
BLISTER_BEVEL = 0.02
DISC_R = 0.131         # 262 mm vented discs in front
DRUM_R = 0.10          # 200 mm drums at the rear


# --------------------------------------------------------------------------
# Wheels with real spokes
# --------------------------------------------------------------------------
def alloy_face(D, part, sx, tw, brake_r, n=16):
    """The sheet wheel is a closed drum with dark shapes painted on for the
    gaps. Open it: a sidewall, the rim's lip, real spokes and hub, a barrel
    behind them, and the brake (a disc or a drum face, `brake_r`) standing in
    the barrel where it shows between the spokes. Hub at the origin."""
    wh = D['wheel']
    r = wh['r']
    R = r * wh.get('rim_ratio', 0.68)
    ng, frac, r0, r1 = fcar.RIM_GAPS.get(wh.get('rim', '5spoke'), fcar.RIM_GAPS['5spoke'])
    xo = sx * tw / 2
    out = np.array([sx, 0.0, 0.0])
    keep = []
    for i, (poly, mat) in enumerate(zip(part.polys, part.mats)):
        cap = mat == 'rubber' and np.abs(poly[:, 0] - xo).max() < 1e-6
        if not cap and mat not in ('rim', 'rim_gap', 'chrome'):
            keep.append(i)
    for name in ('polys', 'mats', 'kind', 'shut'):
        setattr(part, name, [getattr(part, name)[i] for i in keep])

    def pt(rad, a, dx):
        return np.array([xo + sx * dx, rad * math.sin(a), rad * math.cos(a)])

    def ring(ra, rb, dxa, dxb, mat, m=n, face=None):
        for k in range(m):
            a0, a1 = 2 * math.pi * (k + 0.5) / m, 2 * math.pi * (k + 1.5) / m
            q = (pt(ra, a0, dxa), pt(ra, a1, dxa), pt(rb, a1, dxb), pt(rb, a0, dxb))
            want = out if face is None else -(q[0] + q[1]) * np.array([0.0, 1.0, 1.0])
            part.add(P.facing([q], want)[0], mat)

    def disc(rad, dx, mat, m=10):
        part.add(P.facing([[pt(rad, 2 * math.pi * k / m, dx) for k in range(m)]], out)[0], mat)

    depth = -0.05
    ring(r, R, 0.0, 0.0, 'rubber')                       # the sidewall
    ring(R, R * r1, 0.003, 0.003, 'rim')                 # the rim's lip
    ring(R * r1, R * r1, 0.003, depth, 'rubber', m=12, face='in')   # the barrel
    disc(R * r1, depth, 'under_paint', 12)
    for k in range(ng):                                  # the spokes, between the sheet's gaps
        a0 = 2 * math.pi * k / ng + (1 - frac) * math.pi / ng + 2 * math.pi / ng * frac
        a1 = 2 * math.pi * (k + 1) / ng + (1 - frac) * math.pi / ng
        grow = 0.5 * (a1 - a0) * 0.9                     # a spoke widens toward the hub
        q = (pt(R * r0 * 0.9, a0 - grow, 0.008), pt(R * r1 * 1.03, a0, 0.004), pt(R * r1 * 1.03, a1, 0.004), pt(R * r0 * 0.9, a1 + grow, 0.008))
        part.add(P.facing([q], out)[0], 'rim')
    disc(R * r0, 0.008, 'rim', 2 * ng)
    disc(R * 0.18, 0.012, 'chrome', 8)                   # the centre cap
    disc(brake_r, depth + 0.022, 'steel', 12)            # the brake, seen between the spokes
    disc(brake_r * 0.45, depth + 0.032, 'steel', 8)


def _wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    alloy_face(D, part, sx, tw, DISC_R if axle == 0 else DRUM_R)
    if axle == 0:
        disc_brake(part, sx, tw, r=DISC_R)    # the caliper is a body part: it must not turn with the wheel
    else:
        drum(part, sx, tw, r=DRUM_R)


# --------------------------------------------------------------------------
# Box blisters
# --------------------------------------------------------------------------
def _inset(poly, d):
    """A convex polygon (counter-clockwise) moved in by d on every edge."""
    n = len(poly)
    lines = []
    for i in range(n):
        a, b = np.array(poly[i], float), np.array(poly[(i + 1) % n], float)
        e = (b - a) / np.linalg.norm(b - a)
        nrm = np.array([-e[1], e[0]])
        lines.append((a + nrm * d, e))
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


def box_blister(ctx, name, sx, s_ax, rivets=True):
    """One bolted-on box blister over an arch: a flat outer face with a rubber
    edge round the arch, a bevel all round it, a flat top and upright ends back
    to the door skin, the arch's inner lip, and its rivets."""
    D, z = ctx.D, ctx.z
    wh = D['wheel']
    Ra = wh['r'] + wh.get('arch_gap', 0.03)
    yc = wh['r'] + wh.get('arch_lift', 0.0)
    part = ctx.part(name, bevel=0)
    b = BLISTER_BEVEL
    x_out, x_bev = BLISTER_X, BLISTER_X - b
    x_in = pl(D['hw'], s_ax) - 0.006
    x_lip = pl(D['hw'], s_ax) - D.get('sill_in', 0.03) - P.LIP
    s_a, s_b = s_ax - Ra - BLISTER_HL, s_ax + Ra + BLISTER_HL
    y_top = yc + Ra + BLISTER_TOP
    y_bot = pl(D['floor'], s_ax) + 0.015
    c = 0.07
    O = [(s_a, y_bot), (s_b, y_bot), (s_b, y_top - c), (s_b - c, y_top), (s_a + c, y_top), (s_a, y_top - c)]
    Oi = _inset(O, b)
    cen = np.array([s_ax, yc])
    side = np.array([sx, 0.0, 0.0])

    def P3(p, x):
        return np.array([sx * x, p[1], z(p[0])])

    def face(pts, x, mat, want=side):
        part.add(P.facing([[P3(p, x) for p in pts]], want)[0], mat, P.SKIN if mat == 'paint' else P.DETAIL)

    # the outer face, fanned round the arch: rubber edge strip, then paint out to the bevel
    angs = sorted({round(math.pi * k / 10, 6) for k in range(11)} |
                  {round(math.atan2(p[1] - yc, p[0] - s_ax), 6) for p in Oi[2:]})
    rows = []
    for a in angs:
        d = np.array([math.cos(a), math.sin(a)])
        rows.append((cen + d * (Ra - 0.004), cen + d * (Ra + 0.015), _ray_hit(Oi, cen, a)))
    for (i0, r0, o0), (i1, r1, o1) in zip(rows, rows[1:]):
        face((i0, i1, r1, r0), x_out, 'rubber')
        face((r0, r1, o1, o0), x_out, 'paint')
        toward = np.array([0.0, yc, z(s_ax)]) - P3((i0 + i1) / 2, 0.0) * np.array([0.0, 1.0, 1.0])
        part.add(P.facing([[P3(i0, x_out), P3(i1, x_out), P3(i1, x_lip), P3(i0, x_lip)]], toward)[0], 'rubber')
    # the two legs down to the sill
    for sgn, (i_, r_, o_) in ((1, rows[0]), (-1, rows[-1])):
        lo = lambda p: np.array([p[0], y_bot])
        face((lo(i_), i_, r_, lo(r_)), x_out, 'rubber')
        face((lo(r_), r_, o_, lo(o_)), x_out, 'paint')
        part.add(P.facing([[P3(lo(i_), x_out), P3(i_, x_out), P3(i_, x_lip), P3(lo(i_), x_lip)]],
                          np.array([0.0, 0.0, -sgn]))[0], 'rubber')
    # the bevel and the walls back to the skin (not along the bottom)
    for k in range(1, len(O)):
        j = (k + 1) % len(O)
        mid = (np.array(O[k]) + np.array(O[j])) / 2 - cen
        want = np.array([sx * 0.5, mid[1], mid[0]])
        part.add(P.facing([[P3(Oi[k], x_out), P3(Oi[j], x_out), P3(O[j], x_bev), P3(O[k], x_bev)]], want)[0], 'paint', P.SKIN)
        want = np.array([0.0, mid[1], mid[0]])
        part.add(P.facing([[P3(O[k], x_bev), P3(O[j], x_bev), P3(O[j], x_in), P3(O[k], x_in)]], want)[0], 'paint', P.SKIN)
    if rivets:
        spots = [(s_ax + ds, y_top - b - 0.035) for ds in (-0.26, 0.0, 0.26)]
        spots += [(s, y) for s in (s_a + b + 0.035, s_b - b - 0.035) for y in (yc + 0.14, yc - 0.12)]
        for p in spots:
            a = P3(p, x_out)
            cyl(part, a, a + side * 0.004, 0.009, 4, 'steel', caps=(False, False), r_b=0.0)


# --------------------------------------------------------------------------
# The kit
# --------------------------------------------------------------------------
def _cuts(D, R, z, cut):
    """The hatch: the deck below the glass and the tail panel down to the bumper."""
    rear = lambda ps: ((ps.col(0) >= 8) & ~ps.mat_is('glass')) | (ps.col(0) == -2)
    cut('hatch', [((0, 0, 1), z(D['cabin']['C'])), ((1, 0, 0), -HATCH_HW), ((-1, 0, 0), -HATCH_HW), ((0, 1, 0), HATCH_Y0)], rear, True)
    return ['hatch']


def _decal(ctx, d):
    D, part, body, R = ctx.D, ctx.part, ctx.body_tris, ctx.R
    mat, view, tag = d['mat'], d['view'], d.get('tag')
    if mat in ('head', 'turn', 'tail', 'tail_off', 'head_off'):
        return True                               # every lamp is a part of its own: fittings
    if tag == 'plate_recess':
        return True                               # the plate brings its own recess
    if tag == 'fstrip':                           # the black strip across the front bumper
        P.decal(part('bumper_f_insert', bevel=0), D, body, d, 'plastic', 0.004)
        return True
    if tag == 'rub':
        # the rub strip: the door's length opens with the door
        x0, y0, x1, y1 = d['rect']
        gap = P.GAP / 2 + 0.001
        for a, b, on_door in ((max(x0, R['door_s0'] + gap), R['door_s1'] - gap, True), (R['door_s1'] + gap, x1, False)):
            for sx, nm in ((1, 'r'), (-1, 'l')):
                pp = part('rub_door_' + nm, parent='hinge_door_' + nm, bevel=0) if on_door else part('rub_strip_' + nm, bevel=0)
                P.decal(pp, D, body, {'view': 'right' if sx > 0 else 'left', 'rect': (a, y0, b, y1), 'cell': 0.7}, 'plastic', 0.006)
        return True
    return False                                  # the two grilles and the rear bumper strip: the common recipe


def _sheet_part(ctx, p):
    D, z = ctx.D, ctx.z
    t = p['type']
    if t == 'mirrors':
        pm = fcar.CarModel(D)
        fcar.add_part(pm, p)
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            tri = np.array(tri)
            nm = 'l' if tri[:, 0].mean() < 0 else 'r'
            ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
        return True
    if t == 'flares' and p.get('tag') == 'flares':
        for ai, s_ax in enumerate(fcar._axles(D)):
            for sx, nm in ((1, 'r'), (-1, 'l')):
                box_blister(ctx, 'blister_%s%s' % ('f' if ai == 0 else 'r', nm), sx, s_ax, p.get('rivets', True))
        return True
    if t == 'roof_spoiler':
        pm = fcar.CarModel(D)
        fcar.add_part(pm, dict(p, brake_light=False))
        sp = ctx.part('spoiler', bevel=0.006)
        for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
            sp.add(np.array(tri), P.MATMAP.get(mm, mm), P.SKIN)
        if p.get('brake_light'):
            # the third brake lamp: a strip in the spoiler's trailing edge, over the hatch glass
            th = p.get('thick', 0.03)
            zc = z(p['s1']) + 0.003
            y = p['y1'] + th * 0.5
            q = [(-0.30, y - 0.015, zc), (0.30, y - 0.015, zc), (0.30, y + 0.015, zc), (-0.30, y + 0.015, zc)]
            ctx.part('brake_c', bevel=0).add(P.facing([np.array(q)], (0, 0, 1))[0], 'glow_brake')
        return True
    return False


def _fittings(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    cab = D['cabin']
    L = D['L']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']

    for sx, nm in ((1, 'r'), (-1, 'l')):
        # slim headlamps: a black bezel, the lens, the bulb; the amber corner outboard is the blinker
        head = part('head_' + nm, bevel=0)
        xa, xb = sorted((sx * 0.42, sx * 0.64))
        y0, y1 = 0.50, 0.59
        lay(ctx, head, 'front', rect2(xa - 0.008, y0 - 0.008, xb + 0.008, y1 + 0.004), 'plastic', 0.003)
        lay(ctx, head, 'front', rect2(xa, y0, xb, y1), 'glow_lens', 0.006)
        q = lay(ctx, head, 'front', rect2(xa + 0.05, y0 + 0.02, xb - 0.05, y1 - 0.02), 'glow_head', 0.008)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = lamp_centre(q)
        xa, xb = sorted((sx * 0.645, sx * 0.70))
        lay(ctx, part('turn_f' + nm, bevel=0), 'front', rect2(xa, y0, xb, y1), 'glow_turn', 0.006)
        # fog lamps: 80 mm rounds in the bumper, beside the lower mouth (Roy 293)
        fog = part('fog_' + nm, bevel=0)
        c = (sx * 0.60, 0.33)
        lay_ring(ctx, fog, 'front', c, (0.046, 0.046), (0.036, 0.036), 'plastic', 0.008, 10)
        lay(ctx, fog, 'front', [(c[0] + 0.036 * math.cos(2 * math.pi * k / 10), c[1] + 0.036 * math.sin(2 * math.pi * k / 10))
                                for k in range(10)], 'glow_lens', 0.007)
        # the tall rear block: tail lamp on top, brake lamp, reversing lamp, and an amber edge outboard
        xa, xb = sorted((sx * BLOCK_X[0], sx * BLOCK_X[1]))
        xc, xd = sorted((sx * BLOCK_AMBER[0], sx * BLOCK_AMBER[1]))
        lay(ctx, part('lamp_block_' + nm, bevel=0), 'rear', rect2(min(xa, xc) - 0.008, 0.552, max(xb, xd) + 0.008, 0.898), 'plastic', 0.003)
        q = lay(ctx, part('tail_' + nm, bevel=0), 'rear', rect2(xa, 0.785, xb, 0.89), 'glow_tail', 0.006)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = lamp_centre(q)
        lay(ctx, part('brake_' + nm, bevel=0), 'rear', rect2(xa, 0.67, xb, 0.775), 'glow_brake', 0.006)
        lay(ctx, part('reverse_' + nm, bevel=0), 'rear', rect2(xa, 0.56, xb, 0.66), 'glow_reverse', 0.006)
        lay(ctx, part('turn_r' + nm, bevel=0), 'rear', rect2(xc, 0.56, xd, 0.89), 'glow_turn', 0.006)
        # front brakes: a single-pot caliper on the upright (the disc is in the wheel's mesh)
        hub_x = sx * (wh['track'] / 2 - wh['w'] / 2 - 0.018)
        P.obox(part('caliper_f' + nm, bevel=0), (hub_x, r_w + 0.095, z(axles[0])), (0.034, 0.07, 0.12), np.eye(3), 'plastic')
        # what shows of the suspension in the wheel wells: a strut and its arm, the torsion beam's end
        sf = part('susp_f' + nm, bevel=0)
        cyl(sf, (sx * 0.64, r_w + 0.02, z(axles[0])), (sx * 0.62, r_w + 0.34, z(axles[0]) + 0.02), 0.03, 6, 'steel', caps=(False, False))
        cyl(sf, (sx * 0.36, r_w - 0.08, z(axles[0])), (sx * 0.65, r_w - 0.06, z(axles[0])), 0.02, 4, 'steel', caps=(False, False))
        sr = part('susp_r' + nm, bevel=0)
        cyl(sr, (sx * 0.64, r_w + 0.03, z(axles[1] - 0.40)), (sx * 0.64, r_w, z(axles[1])), 0.022, 4, 'steel', caps=(False, False))
        cyl(sr, (sx * 0.30, r_w - 0.02, z(axles[1] - 0.14)), (sx * 0.64, r_w - 0.02, z(axles[1] - 0.14)), 0.03, 5, 'steel', caps=(False, False))

    # the hatch hangs on the roof's rear edge and takes its glass, plate, lamp and wiper up with it
    ctx.info.setdefault('hinges', {})['hinge_hatch'] = {
        'pos': [0.0, pl(D['top'], cab['R']) - 0.01, z(cab['R'])], 'axis': [1, 0, 0], 'open_sign': -1, 'open_deg': 75, 'panel': 'hatch'}
    lamp = part('plate_lamp', parent='hinge_hatch', bevel=0)
    lay(ctx, lamp, 'rear', rect2(-0.11, 0.752, 0.11, 0.772), 'plastic', 0.012)
    lay(ctx, lamp, 'rear', rect2(-0.09, 0.754, 0.09, 0.762), 'glow_lens', 0.0135)
    pull = part('handle_hatch', parent='hinge_hatch', bevel=0)
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, 0.60)], 0.007)
    if c is not None:
        P.obox(pull, c[0], (0.14, 0.022, 0.014), np.eye(3), 'plastic')
    # rear wiper, parked along the bottom of the hatch glass
    wp = part('wiper_rear', parent='hinge_hatch', bevel=0)
    a = P.laid_on(ctx.body_tris, 'rear', [(-0.02, 0.99)], 0.012)
    b = P.laid_on(ctx.body_tris, 'rear', [(0.40, 1.01)], 0.012)
    if a is not None and b is not None:
        a, b = a[0], b[0]
        P.obox(wp, (a + b) / 2, (np.linalg.norm(b - a), 0.014, 0.012), P.frame_basis(b - a, (0, 1, 0)), 'rubber')
        P.obox(wp, a + np.array([0.0, -0.025, 0.006]), (0.04, 0.04, 0.02), np.eye(3), 'plastic')
    # what shows when the hatch is up: the load floor and the back of the rear seat
    cargo = part('cargo', bevel=0)
    x, y, s0, s1 = 0.72, 0.46, axles[1] - 0.30, L - 0.03
    cargo.add(P.facing([[(-x, y, z(s0)), (x, y, z(s0)), (x, y, z(s1)), (-x, y, z(s1))]], (0, 1, 0))[0], 'under_paint')
    cargo.add(P.facing([[(-x, y, z(s0)), (x, y, z(s0)), (x, 0.88, z(s0) + 0.06), (-x, 0.88, z(s0) + 0.06)]], (0, 0, 1))[0], 'rubber')

    # fuel flap on the right rear quarter, between the door and the blister
    fuel_flap(ctx, 1, 2.70, 0.76)

    # under the bonnet: the transverse four, its gearbox on the left, the radiator, the battery
    en = part('engine', bevel=0)
    P.obox(en, (0.06, 0.52, z(0.50)), (0.60, 0.30, 0.34), np.eye(3), 'steel')
    P.obox(en, (0.06, 0.70, z(0.50)), (0.48, 0.06, 0.22), np.eye(3), 'plastic')
    P.obox(en, (-0.34, 0.46, z(0.54)), (0.18, 0.26, 0.30), np.eye(3), 'steel')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.50, z(0.22)), (0.60, 0.30, 0.04), np.eye(3), 'rubber')
    P.obox(part('bay_battery', bevel=0), (0.44, 0.62, z(0.84)), (0.24, 0.18, 0.17), np.eye(3), 'plastic')


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    A['bay_engine'] = {'pos': [0.06, 0.52, z(0.50)]}
    A['bay_radiator'] = {'pos': [0.0, 0.50, z(0.22)]}
    A.pop('bay_turbo', None)              # no car comes with a turbo
    A.pop('bay_intercooler', None)
    A.pop('diff', None)                   # front drive: the diff is in the gearbox
    A['torsion_beam_r'] = {'pos': [0, D['wheel']['r'] - 0.02, z(fcar._axles(D)[1] - 0.14)]}


KIT = {
    'regions': {
        'nose_s': 0.31,                    # the front bumper ends where the front blister starts
        'tail_s': 3.73, 'tail_y': 0.54,    # the rear bumper, behind the rear blister and under the lamps
    },
    'merge_flat': True,
    'no_trunk': True,                      # the tail is one glass hatch
    'antenna_s': 0.95,                     # the mast on the left front fender
    'hinge_of': {'hatch': 'hinge_hatch', 'glass_backlight': 'hinge_hatch', 'plate_r': 'hinge_hatch'},
    'plates': {'plate_f': ('front', 0.445, 0.26, 0.055), 'plate_r': ('rear', 0.69, 0.26, 0.055)},
    'asymmetric': {
        'wiper_rear': 'one rear wiper, on the hatch glass',
        'fuel_recess': 'one filler, on the right rear quarter',
        'fuel_flap': 'one filler, on the right rear quarter',
        'engine': 'a transverse engine: the gearbox hangs on its left end',
        'bay_battery': 'one battery, on the right',
        'exhaust': 'one tail pipe, on the left',
    },
    # what the lamp check reads without the game (tests/car/required_slots.gd)
    'slots': {'brakes': {'front': 'disc 262 mm, single-pot caliper', 'rear': 'drum 200 mm'},
              'brake_lamps': 2, 'third_brake': 1, 'reverse': 2, 'blinkers_front': 2, 'blinkers_rear': 2,
              'hazards': 'the four blinkers', 'plates': 2, 'plate_lamp': 1, 'wipers': 3, 'fuel_flap': 1, 'fog': 2,
              'condition': 0.45},
    'cuts': _cuts, 'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
