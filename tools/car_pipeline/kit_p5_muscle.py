"""P5, the muscle hardtop (Marlowe): what it adds to the common parts recipe.

A two-door 1968-72 style hardtop: no B-pillar, a tunnel-back rear window
between two flying buttresses, two power bulges on the hood, a full-width
grille mouth with one round lamp a side, chrome blade bumpers, one unbroken
tail lamp bar, vented discs on all four wheels. Front engine, rear drive.

Kept in its own file so two car rebuilds can run side by side without both
editing kits.py; kits.KITS imports KIT from here. The helpers are kits.py's.
"""
import math

import numpy as np

import car as fcar
import kits as K
import parts as P
from geom import pl

HEAD = (0.66, 0.58, 0.075)          # head lamp: x, y, radius (front view)
MOUTH = (0.80, 0.50, 0.66)          # grille mouth: half width, bottom, top
BLADE_F = (0.36, 0.44)              # front bumper blade, bottom and top
BLADE_R = (0.39, 0.55)              # rear bumper blade
BLADE_IN = 0.30                     # the blade stands proud outboard of this; the plate lies on the flat middle
BAR = (0.85, 0.73, 0.83)            # tail lamp bar: half width, bottom, top (1.70 x 0.10 m)
BAR_TURN = 0.72                     # the bar's ends, outboard of this, are the blinkers
DISC_R = 0.14                       # 280 mm vented discs
FLAP = (4.45, 0.60)                 # fuel flap on the left rear quarter: s, y
BUTTRESS_END = 4.32                 # where the flying buttresses meet the deck
ANTENNA = (0.80, 1.18)              # the mast on the right front fender: x, s
PLATES = {'plate_f': ('front', 0.40, 0.26, 0.055), 'plate_r': ('rear', 0.47, 0.26, 0.055)}
# No high brake lamp (Roy 1224: none, era), no seat belt, no roll cage.


def _decal(ctx, d):
    """Every sheet decal of this car is a part of its own in the fittings."""
    return True


def _sheet_part(ctx, p):
    return p['type'] == 'mirrors'     # chrome bullet mirrors, in the fittings


def _poly(part, pts, out, mat='paint', kind=P.SKIN):
    """A polygon with repeated corners dropped; nothing if it has no area."""
    q = []
    for p in pts:
        p = np.asarray(p, float)
        if not any(np.linalg.norm(p - o) < 1e-5 for o in q):
            q.append(p)
    if len(q) < 3:
        return
    if len(q) == 4:                      # a quad that is not flat: two triangles
        for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
            if np.linalg.norm(P.poly_normal(np.array(tri))) > 1e-8:
                part.add(P.facing([tri], out)[0], mat, kind)
        return
    if np.linalg.norm(P.poly_normal(np.array(q))) > 1e-8:
        part.add(P.facing([q], out)[0], mat, kind)


def _frame(ctx, part, view, x0, y0, x1, y1, w, proud, mat='chrome'):
    """A raised surround round a rectangle on the nose or the tail: what is
    inside it then sits `proud` deep in a recess."""
    front = view == 'front'
    for (ax, ay, bx, by) in ((x0 - w, y1, x1 + w, y1 + w), (x0 - w, y0 - w, x1 + w, y0),
                             (x0 - w, y0, x0, y1), (x1, y0, x1 + w, y1)):
        c = P.laid_on(ctx.body_tris, view, [((ax + bx) / 2, (ay + by) / 2)], 0.0)
        if c is None:
            continue
        c = c[0] + np.array([0.0, 0.0, (-proud if front else proud) / 2])
        P.obox(part, c, (abs(bx - ax), abs(by - ay), proud), np.eye(3), mat)


def _blade(ctx, name, view, y0, y1, proud):
    """A chrome bumper blade: flat under the plate, standing proud outboard
    of it, with a short return round each corner."""
    D, z = ctx.D, ctx.z
    front = view == 'front'
    s_end = 0.0 if front else D['L']
    sgn = -1.0 if front else 1.0
    hw = pl(D['hw'], s_end)
    blade = ctx.part(name, bevel=0)
    K.lay(ctx, blade, view, K.rect2(-BLADE_IN - 0.01, y0, BLADE_IN + 0.01, y1), 'chrome', 0.012)
    yc, h = (y0 + y1) / 2, y1 - y0
    for sx in (1, -1):
        xa, xb = sx * BLADE_IN, sx * (hw + 0.012)
        P.obox(blade, ((xa + xb) / 2, yc, z(s_end) + sgn * proud / 2), (abs(xb - xa), h, proud), np.eye(3), 'chrome')
        # the return round the corner, following the body side in two lengths
        run = (0.0, 0.08, 0.24) if front else (D['L'], D['L'] - 0.10, D['L'] - 0.24)
        pts = [np.array([sx * (pl(D['hw'], s_) + 0.006), yc, z(s_)]) for s_ in run]
        for a, b in zip(pts, pts[1:]):
            P.obox(blade, (a + b) / 2, (np.linalg.norm(b - a) + 0.012, h * 0.8, 0.014), P.frame_basis(b - a, (0, 1, 0)), 'chrome')
    return blade


def _fittings(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    L = D['L']
    cab = D['cabin']
    axles = fcar._axles(D)
    wh = D['wheel']
    r_w = wh['r']
    R = ctx.R

    # ---- the nose: a low full-width mouth 30 mm deep in a chrome surround,
    # black mesh, one large round lamp a side
    hw_m, my0, my1 = MOUTH
    gr = part('grille', bevel=0)
    K.lay(ctx, gr, 'front', K.rect2(-hw_m, my0, hw_m, my1), 'rubber', 0.003)
    _frame(ctx, gr, 'front', -hw_m, my0, hw_m, my1, 0.016, 0.030)
    hx, hy, hr = HEAD
    for k in range(4):                                   # the mesh, between the lamps
        yc = my0 + (my1 - my0) * (k + 1) / 5
        K.lay(ctx, gr, 'front', K.rect2(-(hx - hr - 0.03), yc - 0.006, hx - hr - 0.03, yc + 0.006), 'plastic', 0.009)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        head = part('head_' + nm, bevel=0)
        c = (sx * hx, hy)
        K.lay_ring(ctx, head, 'front', c, (hr, hr), (hr * 0.84, hr * 0.84), 'chrome', 0.020)
        K.lay(ctx, head, 'front', K.ellipse(c[0], c[1], hr * 0.84, hr * 0.84), 'glow_lens', 0.016)
        q = K.lay(ctx, head, 'front', K.ellipse(c[0], c[1], hr * 0.38, hr * 0.38, 8), 'glow_head', 0.018)
        if q is not None:
            ctx.lamps.setdefault('head', {})[nm] = K.lamp_centre(q)

    # ---- bumpers: chrome blades, the blinkers in the front one, the reversing lamps in the rear one
    _blade(ctx, 'bumper_blade_f', 'front', BLADE_F[0], BLADE_F[1], 0.045)
    _blade(ctx, 'bumper_blade_r', 'rear', BLADE_R[0], BLADE_R[1], 0.050)
    for sx, nm in ((1, 'r'), (-1, 'l')):
        xa, xb = sorted((sx * 0.50, sx * 0.66))
        K.lay(ctx, part('turn_f' + nm, bevel=0), 'front', K.rect2(xa, 0.378, xb, 0.422), 'glow_turn', 0.048)
        xa, xb = sorted((sx * 0.37, sx * 0.47))
        K.lay(ctx, part('reverse_' + nm, bevel=0), 'rear', K.rect2(xa, 0.445, xb, 0.495), 'glow_reverse', 0.053)

    # ---- the tail: ONE bar, 1.70 x 0.10 m, 2 cm deep in its surround. The
    # running lamp is the whole lens, the brake lamp a core strip inside it,
    # the blinkers the red ends of the bar (era); no high brake lamp.
    bw, by0, by1 = BAR
    tp = part('tail_panel', bevel=0)
    K.lay(ctx, tp, 'rear', K.rect2(-bw - 0.004, by0 - 0.004, bw + 0.004, by1 + 0.004), 'rubber', 0.003)
    _frame(ctx, tp, 'rear', -bw - 0.004, by0 - 0.004, bw + 0.004, by1 + 0.004, 0.012, 0.020)
    ym, core = (by0 + by1) / 2, 0.016
    for sx, nm in ((1, 'r'), (-1, 'l')):
        tail = part('tail_' + nm, bevel=0)
        xa, xb = sorted((0.0, sx * BAR_TURN))
        q = K.lay(ctx, tail, 'rear', K.rect2(xa, by0, xb, by1), 'glow_tail', 0.005)
        if q is not None:
            ctx.lamps.setdefault('tail', {})[nm] = K.lamp_centre(q)
        K.lay(ctx, part('brake_' + nm, bevel=0), 'rear', K.rect2(xa, ym - core, xb, ym + core), 'glow_brake', 0.008)
        xa, xb = sorted((sx * (BAR_TURN + 0.006), sx * bw))
        K.lay(ctx, part('turn_r' + nm, bevel=0), 'rear', K.rect2(xa, by0, xb, by1), 'glow_tail', 0.005)
    # the lamp over the rear plate
    pl_y = PLATES['plate_r'][1] + PLATES['plate_r'][3]
    c = P.laid_on(ctx.body_tris, 'rear', [(0.0, pl_y + 0.024)], 0.026)
    if c is not None:
        lamp = part('plate_lamp', bevel=0)
        P.obox(lamp, c[0], (0.12, 0.018, 0.024), np.eye(3), 'chrome', {'-y': 'glow_lens'})

    # ---- the hood's two power bulges: low ridges that fade in from the nose
    bulge = part('hood_bulge', parent='hinge_hood', bevel=0)
    xs = (0.13, 0.19, 0.29, 0.35)                        # foot, crest, crest, foot
    ss = (0.46, 0.80, 1.10, 1.40)
    lift = (0.0, 0.030, 0.034, 0.030)
    rows = []
    for s_, h in zip(ss, lift):
        base = [np.asarray(ctx.on_top(x, s_, 0.001), float) for x in xs]
        rows.append([base[0], base[1] + np.array([0, h, 0]), base[2] + np.array([0, h, 0]), base[3]])
    up = np.array([0.0, 1.0, 0.0])
    for a, b in zip(rows, rows[1:]):
        for k, out in ((0, (-0.6, 1, 0)), (1, up), (2, (0.6, 1, 0))):
            _poly(bulge, (a[k], a[k + 1], b[k + 1], b[k]), out)
    bulge.add(P.facing([rows[-1]], (0, 0.3, 1))[0], 'paint', P.SKIN)      # the open end at the cowl

    # ---- the tunnel back: a flying buttress each side carries the roof line
    # down to the deck; the rear window stands upright between them
    sR = cab['R']
    for sx, nm in ((1, 'r'), (-1, 'l')):
        fin = part('buttress_' + nm, bevel=0)
        sec = lambda s_: fcar.half_section(D, s_)[0]
        p0, p1 = sec(sR)[8], sec(BUTTRESS_END)[7]
        rows = []
        for k in range(6):
            t = k / 5.0
            s_ = sR + (BUTTRESS_END - sR) * t
            sc = sec(s_)
            foot = np.array([sx * sc[8][0], sc[8][1], z(s_)])
            xt, yt = p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t
            yt = max(yt, foot[1])
            crest_o = np.array([sx * xt, yt, z(s_)])
            crest_i = np.array([sx * (xt - 0.05), yt, z(s_)])
            inner = ctx.on_top(sx * (xt - 0.075), s_, 0.0)
            if inner is None or inner[1] > yt:
                inner = crest_i.copy()
            rows.append((foot, crest_o, crest_i, inner))
        for a, b in zip(rows, rows[1:]):
            _poly(fin, (a[0], a[1], b[1], b[0]), (sx, 0.3, 0))
            _poly(fin, (a[1], a[2], b[2], b[1]), (0, 1, 0))
            _poly(fin, (a[2], a[3], b[3], b[2]), (-sx, 0.2, 0))

    # ---- chrome: the belt mouldings under the glass (the door's length opens
    # with the door), the bullet mirrors
    gap = P.GAP / 2 + 0.001
    edge = lambda s_, sx: np.array([sx * fcar.half_section(D, s_)[0][7][0], fcar.half_section(D, s_)[0][7][1] + 0.004, z(s_)])
    runs = ((R['door_s0'] + gap, 1.90, True), (1.90, R['door_s1'] - gap, True),
            (R['door_s1'] + gap, 2.90, False), (2.90, cab['D'], False))
    for sx, nm in ((1, 'r'), (-1, 'l')):
        for a_s, b_s, on_door in runs:
            a, b = edge(a_s, sx), edge(b_s, sx)
            pp = part('belt_trim_door_' + nm, parent='hinge_door_' + nm, bevel=0) if on_door else part('belt_trim_' + nm, bevel=0)
            P.obox(pp, (a + b) / 2, (np.linalg.norm(b - a), 0.012, 0.018), P.frame_basis(b - a, (0, 1, 0)), 'chrome')
        # the mirror: a chrome bullet on a short stalk on the door, glass facing back
        s_m = cab['A'] + 0.24
        foot = edge(s_m, sx)
        c = foot + np.array([sx * 0.075, 0.075, 0.0])
        mp = part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0)
        K.cyl(mp, c + np.array([0, 0, 0.035]), c - np.array([0, 0, 0.045]), 0.062, 8, 'chrome', caps=(False, False))
        K.cyl(mp, c - np.array([0, 0, 0.045]), c - np.array([0, 0, 0.125]), 0.062, 8, 'chrome', caps=(False, False), r_b=0.0)
        ring = [c + np.array([0.054 * math.cos(2 * math.pi * (k + 0.5) / 8), 0.054 * math.sin(2 * math.pi * (k + 0.5) / 8), 0.030])
                for k in range(8)]
        mp.add(P.facing([ring], (0, 0, 1))[0], 'mirror')
        K.cyl(mp, foot, c - np.array([0, 0.03, 0.01]), 0.012, 4, 'chrome', caps=(False, False))
        ctx.info.setdefault('door_mirrors', {})[nm] = [round(float(v), 4) for v in c + np.array([0, 0, 0.030])]

    # ---- brakes: the single-pot caliper stays on the upright (the disc is in the wheel's mesh)
    for ai, tagf in ((0, 'f'), (1, 'r')):
        tw = wh['w'] if ai == 0 else wh.get('w_rear', wh['w'])
        for sx, nm in ((1, 'r'), (-1, 'l')):
            cal = part('caliper_' + tagf + nm, bevel=0)
            hub_x = sx * (wh['track'] / 2 - tw / 2 - 0.018)
            P.obox(cal, (hub_x, r_w + DISC_R - 0.035, z(axles[ai])), (0.04, 0.07, 0.12), np.eye(3), 'steel')

    # ---- fuel flap on the left rear quarter, behind the arch (the tank is under the trunk floor)
    K.fuel_flap(ctx, -1, FLAP[0], FLAP[1])

    # ---- antenna: one mast on the right front fender
    base = ctx.on_top(ANTENNA[0], ANTENNA[1])
    if base is not None:
        an = part('antenna', bevel=0)
        K.cyl(an, base, base + np.array([0.0, 0.62, 0.10]), 0.004, 3, 'chrome', caps=(False, False), r_b=0.002)
        P.obox(an, base + np.array([0, 0.006, 0]), (0.034, 0.014, 0.034), np.eye(3), 'chrome')

    # ---- under the hood: a dark bay floor and the radiator. No engine model yet.
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    P.obox(part('bay_floor', bevel=0), (0.0, 0.42, z(hood_mid)), (1.30, 0.02, cab['A'] - R['nose_s'] - 0.10), np.eye(3), 'rubber')
    P.obox(part('bay_radiator_core', bevel=0), (0.0, 0.595, z(R['nose_s'] + 0.10)), (0.80, 0.33, 0.05), np.eye(3), 'rubber')  # stands on the floor (part_fit)


def _wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    # the sheet's deep dish in the materials the assembler knows
    remap = {'rim_face': 'steel', 'rim_gap': 'rubber'}
    part.mats = [remap.get(m, m) for m in part.mats]
    # a vented disc: two plates with the air gap between them, and the hat
    x0 = -sx * tw / 2
    K.cyl(part, (x0 - sx * 0.010, 0, 0), (x0 - sx * 0.018, 0, 0), DISC_R, 12, 'steel')
    K.cyl(part, (x0 - sx * 0.018, 0, 0), (x0 - sx * 0.026, 0, 0), DISC_R * 0.86, 8, 'plastic', caps=(False, False))
    K.cyl(part, (x0 - sx * 0.026, 0, 0), (x0 - sx * 0.034, 0, 0), DISC_R, 12, 'steel')
    K.cyl(part, (x0, 0, 0), (x0 - sx * 0.034, 0, 0), DISC_R * 0.45, 8, 'steel', caps=(False, False))


def _anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    cab = D['cabin']
    hood_mid = 0.5 * (R['nose_s'] + cab['A'])
    A['bay_engine'] = {'pos': [0, 0.52, z(hood_mid + 0.12)]}       # where the V8 goes
    A['bay_radiator'] = {'pos': [0.0, 0.58, z(R['nose_s'] + 0.10)]}
    A.pop('bay_turbo', None)              # no car comes with a turbo
    A.pop('bay_intercooler', None)
    A['tank'] = {'pos': [0, 0.30, z(4.45)]}
    A['fuel_filler'] = {'pos': [-pl(D['hw'], FLAP[0]), FLAP[1], z(FLAP[0])]}


KIT = {
    'regions': {
        'nose_s': 0.14,                    # the header panel over the grille mouth
        'hood_hw': 0.74,
        'door_s0': 1.49, 'door_s1': 2.72,  # one long door a side, no B-pillar behind it
        'trunk_s0': 3.84, 'trunk_s1': 4.86, 'trunk_hw': 0.72,
        'tail_s': 4.20, 'tail_y': 0.38,    # the rear valance, behind the arch and under the blade
    },
    'merge_flat': True,
    'no_antenna': True,                    # the kit stands its own, on the right front fender
    'plates': PLATES,
    'asymmetric': {
        'fuel_recess': 'one filler, on the left rear quarter',
        'fuel_flap': 'one filler, on the left rear quarter',
        'antenna': 'one mast, on the right front fender',
    },
    'decal': _decal, 'sheet_part': _sheet_part, 'fittings': _fittings,
    'wheel': _wheel, 'anchors': _anchors,
}
