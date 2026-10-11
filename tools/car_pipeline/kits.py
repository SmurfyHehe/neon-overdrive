"""Car modelling pipeline: what each car adds to the common parts recipe.

`parts.py` cuts any fleet car into the common set (body, hood, doors, trunk,
fenders, bumpers, glass, seals, handles, plates, wipers). A KIT is the rest of
one car: where its panels are cut, the lamps as separate parts, its brakes,
its fuel flap, what is under its lids, and what on it is NOT a mirror image
left to right. The coupe (the pilot) has no kit: it is the common recipe.

A kit is a dict (all keys optional):

    regions      panel cut lines, as parts.regions()
    panel_mats   {part: material} a cut panel that is not the car's paint
    plates       {'plate_f': (view, centre y, half width, half height), ...}
    asymmetric   {part: why} added to parts.ASYMMETRIC for this car
    no_antenna   True: no mast
    decal        f(ctx, d) -> True when it has turned the sheet decal d into parts
    sheet_part   f(ctx, p) -> True when it has turned the sheet part p into parts
    fittings     f(ctx): the car's own parts; may fill ctx.info['hinges']
    wheel        f(D, tag, sx, axle, part): brakes and hubcaps, on the wheel's
                 mesh (hub at the origin), so they cost no draw call
    anchors      f(D, R, A): move or replace the named empties

Parts added here follow the same rules as the common ones: build the RIGHT
side (or both sides of a centre part) and parts.symmetrize() makes the left
its mirror image; anything one-sided has to be in `asymmetric` with its reason.
"""
import math

import numpy as np

import car as fcar
import parts as P
from geom import AXES, pl

# Lamp parts: one glow material each, so the game can light them one by one.
#   head_l/r         headlamp: chrome bezel, lens, bulb
#   turn_fl/fr/rl/rr blinkers (and hazards), amber
#   tail_l/r         running lamps, red
#   brake_l/r(/c)    brake lamps, dark red until lit
#   reverse_l/r      reversing lamps, dark until lit


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def ellipse(cx, cy, rx, ry, n=12):
    return [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n)) for k in range(n)]


def rect2(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def clip_y(pts, y0, y1):
    """A convex 2D polygon between two heights."""
    q = np.array([(x, y, 0.0) for x, y in pts])
    q, _ = P.clip_poly(q, np.array([0.0, 1.0, 0.0]), y0)
    if q is None:
        return None
    q, _ = P.clip_poly(q, np.array([0.0, -1.0, 0.0]), -y1)
    return None if q is None else [(p[0], p[1]) for p in q]


def lay(ctx, part, view, pts, mat, off, back=False):
    """A convex 2D polygon of a view laid on the body, `off` proud of it.
    -> its 3D points or None."""
    if pts is None:
        return None
    q = P.laid_on(ctx.body_tris, view, pts, off)
    if q is None:
        return None
    out = -AXES[view]
    part.add(P.facing([q], -out if back else out)[0], mat)
    return np.array(q)


def lay_ring(ctx, part, view, c, r_out, r_in, mat, off, n=12):
    po = P.laid_on(ctx.body_tris, view, ellipse(c[0], c[1], r_out[0], r_out[1], n), off)
    pi = P.laid_on(ctx.body_tris, view, ellipse(c[0], c[1], r_in[0], r_in[1], n), off)
    if po is None or pi is None:
        return
    out = -AXES[view]
    for k in range(n):
        j = (k + 1) % n
        part.add(P.facing([(po[k], po[j], pi[j], pi[k])], out)[0], mat)


def cyl(part, a, b, r, n, mat, caps=(True, True), r_b=None, kind=P.DETAIL):
    """A cylinder (or cone, r_b) from a to b."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ax = b - a
    hint = (0.0, 1.0, 0.0) if abs(ax[1]) < 0.9 * np.linalg.norm(ax) else (1.0, 0.0, 0.0)
    B = P.frame_basis(ax, hint)
    rb = r if r_b is None else r_b
    ang = [2 * math.pi * (k + 0.5) / n for k in range(n)]
    ra = [a + B @ np.array([0.0, r * math.cos(t), r * math.sin(t)]) for t in ang]
    rbp = [b + B @ np.array([0.0, rb * math.cos(t), rb * math.sin(t)]) for t in ang]
    mid = (a + b) / 2
    for k in range(n):
        j = (k + 1) % n
        out = (ra[k] + ra[j]) / 2 - a
        if rb < 1e-6:
            part.add(P.facing([(ra[k], ra[j], b)], out + ax * 0.2)[0], mat, kind)
        else:
            part.add(P.facing([(ra[k], ra[j], rbp[j], rbp[k])], out)[0], mat, kind)
    if caps[0]:
        part.add(P.facing([ra], -ax)[0], mat, kind)
    if caps[1] and rb > 1e-6:
        part.add(P.facing([rbp], ax)[0], mat, kind)
    return mid


def lamp_centre(q):
    return [float(v) for v in np.asarray(q).mean(axis=0)]


def fuel_flap(ctx, sx, s, y, hw=0.065, hh=0.055, paint='paint'):
    """A fuel flap on one side: a dark recess with the filler cap in it, and
    the flap over it on its own hinge (front edge, opens outward). It lies ON
    the skin instead of being cut into it: a cut would have to be mirrored to
    the other side to keep the body symmetrical."""
    view = 'right' if sx > 0 else 'left'
    z = ctx.z
    rec = ctx.part('fuel_recess', bevel=0)
    lay(ctx, rec, view, rect2(z(s - hw) - 0.004, y - hh - 0.004, z(s + hw) + 0.004, y + hh + 0.004), 'rubber', 0.0015)
    lay(ctx, rec, view, ellipse(z(s), y, 0.028, 0.028, 10), 'chrome', 0.003)
    hinge = P.laid_on(ctx.body_tris, view, [(z(s - hw), y)], 0.005)[0]
    flap = ctx.part('fuel_flap', parent='hinge_fuel_flap', bevel=0)
    pts = rect2(z(s - hw), y - hh, z(s + hw), y + hh)
    lay(ctx, flap, view, pts, paint, 0.005)
    lay(ctx, flap, view, pts, 'under_paint', 0.0042, back=True)
    ctx.info.setdefault('hinges', {})['hinge_fuel_flap'] = {
        'pos': [round(float(v), 4) for v in hinge], 'axis': [0, 1, 0], 'open_sign': 1 if sx > 0 else -1,
        'open_deg': 80, 'panel': 'fuel_flap'}
    return hinge


def drum(part, sx, tw, r=0.12, depth=0.03):
    """A brake drum on the inboard face of a wheel (hub at the origin)."""
    x0 = -sx * tw / 2
    cyl(part, (x0, 0, 0), (x0 - sx * depth, 0, 0), r, 10, 'steel', caps=(False, True))


def disc_brake(part, sx, tw, r=0.118, depth=0.03):
    """A small solid disc with its hat on the inboard face of a wheel."""
    x0 = -sx * tw / 2
    cyl(part, (x0 - sx * 0.012, 0, 0), (x0 - sx * 0.022, 0, 0), r, 12, 'steel')
    cyl(part, (x0, 0, 0), (x0 - sx * depth, 0, 0), r * 0.5, 8, 'steel', caps=(False, True))


def hubcap(part, sx, tw, r=0.078, h=0.03):
    """A plain chrome dome over the hub and the wheel nuts (no maker's shape)."""
    x0 = sx * (tw / 2 + 0.010)
    cyl(part, (x0, 0, 0), (x0 + sx * h, 0, 0), r, 10, 'chrome', caps=(False, False), r_b=0.0)


def lug_nuts(part, sx, tw, n=4, r_pitch=0.05):
    """The wheel nuts of a wheel that has lost its hubcap."""
    x0 = sx * (tw / 2 + 0.008)
    for k in range(n):
        a = 2 * math.pi * k / n + math.pi / 4
        c = np.array([x0, r_pitch * math.sin(a), r_pitch * math.cos(a)])
        cyl(part, c, c + np.array([sx * 0.016, 0, 0]), 0.011, 6, 'steel', caps=(False, True))


# --------------------------------------------------------------------------
# P0, the Bug: rear-engined, air-cooled, drums all round
# --------------------------------------------------------------------------
BUG_NO_CAP = 'fr'      # the wheel that has lost its hubcap (three are left: Roy 1171-1180)


def _bug_decal(ctx, d):
    D, part, body = ctx.D, ctx.part, ctx.body_tris
    mat, view, tag = d['mat'], d['view'], d.get('tag')
    if view == 'rear':
        if mat == 'grille':                       # the engine lid's louvres open with the lid
            P.decal(part('louvres', parent='hinge_trunk', bevel=0), D, body,
                    {'view': view, 'rect': d['rect'], 'cell': 0.3}, 'rubber', 0.003)
            return True
        if tag == 'rbumper':                      # the blade bumper
            P.decal(part('bumper_blade', bevel=0), D, body, {'view': view, 'rect': d['rect'], 'cell': 0.34}, 'chrome', 0.012)
            return True
        return True                               # tail lamps and the plate recess: fittings, plates
    if view == 'front':
        if mat == 'head':
            return True                           # fittings
        P.decal(part('nose_trim', bevel=0), D, body, {'view': view, 'rect': d['rect'], 'cell': 0.4}, 'plastic', 0.004)
        return True
    if tag == 'hood':
        return True                               # the primer front lid is the hood panel itself (panel_mats)
    if tag == 'fender':
        return True                               # the primer fenders are the skin itself (paint_regions)
    if mat in ('rust', 'bondo'):
        P.decal(part('wear', bevel=0), D, body, d, P.MATMAP[mat], 0.004)
        return True
    if mat == 'grille':                           # air intake slots in the rear quarters
        dd = dict(d)
        dd['cell'] = 0.3
        P.decal(part('intake', bevel=0), D, body, dd, 'rubber', 0.003)
        return True
    return False


def _bug_sheet_part(ctx, p):
    pm = fcar.CarModel(ctx.D)
    fcar.add_part(pm, p)
    for tri, mm in zip(pm.mesh.tris, pm.mesh.mats):
        tri = np.array(tri)
        nm = 'l' if tri[:, 0].mean() < 0 else 'r'
        if p['type'] == 'mirrors':                # the driver's mirror, and the stub of the lost one
            ctx.part('mirror_' + nm, parent='hinge_door_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
        else:                                     # the brackets of the missing front bumper
            ctx.part('bracket_' + nm, bevel=0).add(tri, P.MATMAP.get(mm, mm))
    return True


def _bug_fittings(ctx):
    D, part, z = ctx.D, ctx.part, ctx.z
    L = D['L']
    axles = fcar._axles(D)

    for sx, nm in ((1, 'r'), (-1, 'l')):
        # headlamps: round, standing on the fender crowns. A bucket in the
        # fender's paint from the skin forward to an upright chrome rim, the
        # lens and the bulb in it (laid flat on the sloping crown, as the
        # sheet's decal is, a round lamp is a long smear).
        head = part('head_' + nm, bevel=0)
        cx_, cy_, r = sx * 0.54, 0.84, 0.095
        hit = P.laid_on(ctx.body_tris, 'front', [(cx_, cy_)], 0.0)
        if hit is not None:
            zc = hit[0][2]                      # the crown under the lamp's centre
            zf = zc - 0.10                      # the rim stands 10 cm ahead of it
            front = np.array([0.0, 0.0, -1.0])
            cyl(head, (cx_, cy_, zc + 0.14), (cx_, cy_, zf), r, 12, 'paint_primer', caps=(False, False))
            ring = lambda rr, dz, n=12: [np.array([cx_ + rr * math.cos(2 * math.pi * (k + 0.5) / n),
                                                   cy_ + rr * math.sin(2 * math.pi * (k + 0.5) / n), zf - dz]) for k in range(n)]
            ro, ri = ring(r, 0.0), ring(r * 0.84, 0.004)
            for k in range(12):
                j = (k + 1) % 12
                head.add(P.facing([(ro[k], ro[j], ri[j], ri[k])], front)[0], 'chrome')
            head.add(P.facing([ring(r * 0.84, 0.002)], front)[0], 'glow_lens')
            bulb = ring(r * 0.36, 0.006, 8)
            head.add(P.facing([bulb], front)[0], 'glow_head')
            ctx.lamps.setdefault('head', {})[nm] = lamp_centre(bulb)
        # front blinkers: a small amber lamp on top of each fender
        base = ctx.on_top(sx * 0.63, 0.80)
        if base is not None:
            t = part('turn_f' + nm, bevel=0)
            P.obox(t, base + np.array([0, 0.003, 0]), (0.044, 0.006, 0.096), np.eye(3), 'chrome')
            P.obox(t, base + np.array([0, 0.016, 0]), (0.034, 0.022, 0.084), np.eye(3), 'glow_turn')
        # reversing lamps: a small round lamp each side of the plate
        rv = part('reverse_' + nm, bevel=0)
        c = (sx * 0.36, 0.50)
        lay_ring(ctx, rv, 'rear', c, (0.034, 0.034), (0.025, 0.025), 'chrome', 0.008, 8)
        lay(ctx, rv, 'rear', ellipse(c[0], c[1], 0.025, 0.025, 8), 'glow_reverse', 0.007)
        # what shows of the suspension in the wheel wells
        # front: two transverse torsion bar tubes, a trailing arm from each to the hub
        sf = part('susp_f' + nm, bevel=0)
        r_w = D['wheel']['r']
        for y in (r_w - 0.04, r_w + 0.07):
            a = np.array([sx * 0.56, y, z(axles[0] - 0.14)])
            b = np.array([sx * 0.625, y, z(axles[0] - 0.14)])
            cyl(sf, a, b, 0.022, 5, 'steel', caps=(False, True))
            cyl(sf, b - np.array([sx * 0.012, 0, 0]), (sx * 0.613, r_w + (y - r_w) * 0.4, z(axles[0])), 0.016, 4, 'steel', caps=(False, False))
        # rear: swing axle tube from the transaxle to the hub, and the spring plate
        sr = part('susp_r' + nm, bevel=0)
        cyl(sr, (sx * 0.30, r_w + 0.03, z(axles[1])), (sx * 0.62, r_w, z(axles[1])), 0.028, 5, 'steel', caps=(False, False))
        cyl(sr, (sx * 0.612, r_w + 0.04, z(axles[1] - 0.42)), (sx * 0.612, r_w, z(axles[1])), 0.018, 4, 'steel', caps=(False, False))

    # tail lamps. Left: one housing with the blinker, the running lamp and the
    # brake lamp as three parts. Right: the lens is gone (the sheet's missing
    # bit 4), a rusty ring round a dark socket.
    cx, cy, rx, ry = 0.56, 0.80, 0.065, 0.085
    tl = part('tail_l', bevel=0)
    lay_ring(ctx, tl, 'rear', (-cx, cy), (rx + 0.010, ry + 0.010), (rx, ry), 'chrome', 0.008)
    oval = ellipse(-cx, cy, rx, ry)
    q = lay(ctx, tl, 'rear', clip_y(oval, cy - ry / 3, cy + ry / 3), 'glow_tail', 0.007)
    if q is not None:
        ctx.lamps.setdefault('tail', {})['l'] = lamp_centre(q)
    lay(ctx, part('brake_l', bevel=0), 'rear', clip_y(oval, cy - ry, cy - ry / 3), 'glow_brake', 0.007)
    lay(ctx, part('turn_rl', bevel=0), 'rear', clip_y(oval, cy + ry / 3, cy + ry), 'glow_turn', 0.007)
    tr = part('tail_r', bevel=0)
    lay_ring(ctx, tr, 'rear', (cx, cy), (rx + 0.010, ry + 0.010), (rx - 0.010, ry - 0.010), 'paint_rust', 0.004)
    lay(ctx, tr, 'rear', ellipse(cx, cy, rx - 0.010, ry - 0.010), 'rubber', 0.006)

    # fuel flap on the right front quarter (the tank is in the front trunk)
    flap_s, flap_y = 1.24, 0.845
    neck_to = fuel_flap(ctx, 1, flap_s, flap_y)

    # under the front lid: the spare wheel standing in the nose and the tank behind it
    sp = part('bay_spare', bevel=0)
    c = np.array([0.0, 0.57, z(0.74)])
    ax = np.array([0.0, 0.94, -0.34]) * 0.085
    cyl(sp, c - ax, c + ax, 0.29, 10, 'rubber')
    cyl(sp, c + ax, c + ax * 1.03, 0.17, 10, 'steel', caps=(False, True))
    tk = part('bay_tank', bevel=0)
    P.obox(tk, (0.0, 0.66, z(1.20)), (0.80, 0.20, 0.30), np.eye(3), 'steel')
    cyl(part('fuel_neck', bevel=0), (0.34, 0.74, z(1.20)), neck_to - np.array([0.03, 0, 0]), 0.03, 6, 'steel')

    # under the rear lid: the flat four, its fan shroud, the air cleaner, the pulley
    en = part('engine', bevel=0)
    zc = z(3.86)
    P.obox(en, (0.0, 0.50, zc), (0.46, 0.28, 0.44), np.eye(3), 'steel')
    for sx in (1, -1):
        P.obox(en, (sx * 0.33, 0.44, zc), (0.16, 0.13, 0.36), np.eye(3), 'steel')
    cyl(en, (0.0, 0.68, z(3.66)), (0.0, 0.68, z(3.76)), 0.19, 8, 'plastic')
    cyl(en, (0.0, 0.64, z(3.96)), (0.0, 0.74, z(3.96)), 0.09, 6, 'plastic')
    cyl(en, (0.0, 0.50, zc + 0.22), (0.0, 0.50, zc + 0.24), 0.07, 6, 'steel', caps=(False, True))


def _bug_wheel(D, tag, sx, axle, part):
    wh = D['wheel']
    tw = wh['w'] if axle == 0 else wh.get('w_rear', wh['w'])
    drum(part, sx, tw)                    # 240 mm drums on all four
    if tag == BUG_NO_CAP:
        lug_nuts(part, sx, tw)
    else:
        hubcap(part, sx, tw)


def _bug_anchors(D, R, A):
    z = lambda s: fcar._s2z(D, s)
    axles = fcar._axles(D)
    r = D['wheel']['r']
    for name in ('bay_turbo', 'bay_radiator', 'bay_intercooler', 'strut_top_fl', 'strut_top_fr'):
        A.pop(name, None)                 # air-cooled, no turbo; torsion bars, no struts
    A['bay_engine'] = {'pos': [0, 0.50, z(3.86)]}
    A['tank'] = {'pos': [0, 0.66, z(1.20)]}
    A['diff'] = {'pos': [0, r + 0.03, z(axles[1])]}          # the transaxle, ahead of the engine
    A['torsion_bar_f'] = {'pos': [0, r + 0.015, z(axles[0] - 0.14)]}
    A['swing_axle_r'] = {'pos': [0, r + 0.03, z(axles[1])]}
    tip = D['exhaust'][0]
    route = [(0.0, 0.34, 3.95), (0.0, 0.26, 4.12), (tip['x'] * 0.6, 0.25, 4.20), (tip['x'], tip['y'], D['L'] - 0.06)]
    for i, (x, y, s) in enumerate(route):                    # engine to tip: a short pipe, all behind the axle
        A['exhaust_route_%d' % i] = {'pos': [x, y, z(s)]}


BUG = {
    'regions': {
        'nose_s': 0.30,                    # the nose apron (the front bumper itself is one of the missing bits)
        'hood_hw': 0.44,                   # the front trunk lid, between the fenders
        'trunk_s0': 3.36, 'trunk_s1': 4.26, 'trunk_hw': 0.40,   # the engine lid
        'tail_s': 3.92, 'tail_y': 0.33,    # the rear apron
    },
    'merge_flat': True,
    'panel_mats': {'hood': 'paint_primer'},   # the front lid that never got painted
    # the four pontoon fenders in primer, rocker to belt (cars._fender: s_ax +- 0.50, y 0.40 to 0.78)
    'paint_regions': [(0.35, 1.35, 0.40, 0.78, 'primer'), (2.90, 3.90, 0.40, 0.78, 'primer')],
    'plates': {'plate_f': ('front', 0.44, 0.26, 0.055), 'plate_r': ('rear', 0.51, 0.26, 0.055)},
    'asymmetric': {
        'mirror_l': "the driver's mirror is the only one left (the sheet's missing bit 3)",
        'mirror_r': 'the stub of the lost passenger mirror',
        'tail_l': 'the one tail lamp that works',
        'brake_l': 'the one tail lamp that works',
        'turn_rl': 'the one tail lamp that works',
        'tail_r': "the lens is gone (the sheet's missing bit 4): a rust ring round a dark socket",
        'fuel_recess': 'one filler, on the right front quarter',
        'fuel_flap': 'one filler, on the right front quarter',
        'fuel_neck': 'one filler, on the right front quarter',
        'wheel_%s_mesh' % BUG_NO_CAP: 'the wheel that lost its hubcap shows its wheel nuts (Roy: hubcaps on 3 wheels)',
    },
    'decal': _bug_decal, 'sheet_part': _bug_sheet_part, 'fittings': _bug_fittings,
    'wheel': _bug_wheel, 'anchors': _bug_anchors,
}

KITS = {
    'p0_beater': BUG,
}
